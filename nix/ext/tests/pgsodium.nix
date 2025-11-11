{ self, pkgs }:
let
  pname = "pgsodium";
  testLib = import ./lib.nix {
    inherit self pkgs;
    testedExtensionName = pname;
  };
  inherit (testLib) mkPostgresqlWithExtensions versions;
  psql_15 = mkPostgresqlWithExtensions self.packages.${pkgs.system}.postgresql_15 [
    pname
    "hypopg"
  ];
  psql_17 = mkPostgresqlWithExtensions self.packages.${pkgs.system}.postgresql_17 [
    pname
    "hypopg"
  ];

  pgsodiumGetKey = pkgs.lib.getExe (
    pkgs.writeShellScriptBin "pgsodium-getkey" ''
      echo 0000000000000000000000000000000000000000000000000000000000000000
    ''
  );
in
self.inputs.nixpkgs.lib.nixos.runTest {
  name = pname;
  hostPkgs = pkgs;
  nodes.server =
    { config, ... }:
    pkgs.lib.mkMerge [
      (testLib.mkDefaultNixosTestNode { inherit config psql_15 psql_17; })
      {
        services.postgresql = {
          settings = {
            "shared_preload_libraries" = pkgs.lib.mkForce pname;
            "pgsodium.getkey_script" = pgsodiumGetKey;
          };
        };

        specialisation.postgresql17.configuration = {
          systemd.services.postgresql-migrate = {
            script = pkgs.lib.mkForce (
              let
                oldPostgresql = psql_15;
                newPostgresql = psql_17;
                oldDataDir = "${builtins.dirOf config.services.postgresql.dataDir}/${oldPostgresql.psqlSchema}";
                newDataDir = "${builtins.dirOf config.services.postgresql.dataDir}/${newPostgresql.psqlSchema}";
              in
              ''
                if [[ ! -d ${newDataDir} ]]; then
                  install -d -m 0700 -o postgres -g postgres "${newDataDir}"
                  ${newPostgresql}/bin/initdb -D "${newDataDir}"
                  echo "shared_preload_libraries = '${pname}'" >> "${newDataDir}/postgresql.conf"
                  echo "pgsodium.getkey_script = '${pgsodiumGetKey}'" >> "${newDataDir}/postgresql.conf";
                  ${newPostgresql}/bin/pg_upgrade --old-datadir "${oldDataDir}" --new-datadir "${newDataDir}" \
                    --old-bindir "${oldPostgresql}/bin" --new-bindir "${newPostgresql}/bin"
                else
                  echo "${newDataDir} already exists"
                fi
              ''
            );
          };
        };
      }
    ];
  testScript =
    { nodes, ... }:
    let
      pg17-configuration = "${nodes.server.system.build.toplevel}/specialisation/postgresql17";
    in
    ''
      versions = {
        "15": [${pkgs.lib.concatStringsSep ", " (map (s: ''"${s}"'') (versions "15"))}],
        "17": [${pkgs.lib.concatStringsSep ", " (map (s: ''"${s}"'') (versions "17"))}],
      }

      def run_sql(query):
        return server.succeed(f"""sudo -u postgres psql -t -A -F\",\" -c \"{query}\" """).strip()

      def check_upgrade_path(pg_version):
        with subtest("Check ${pname} upgrade path"):
          firstVersion = versions[pg_version][0]
          server.succeed("sudo -u postgres psql -c 'DROP EXTENSION IF EXISTS ${pname};'")
          run_sql(f"""CREATE EXTENSION ${pname} WITH VERSION '{firstVersion}' CASCADE;""")
          installed_version = run_sql(r"""SELECT extversion FROM pg_extension WHERE extname = '${pname}';""")
          assert installed_version == firstVersion, f"Expected ${pname} version {firstVersion}, but found {installed_version}"
          for version in versions[pg_version][1:]:
            run_sql(f"""ALTER EXTENSION ${pname} UPDATE TO '{version}';""")
            installed_version = run_sql(r"""SELECT extversion FROM pg_extension WHERE extname = '${pname}';""")
            assert installed_version == version, f"Expected ${pname} version {version}, but found {installed_version}"

      start_all()

      server.wait_for_unit("multi-user.target")
      server.wait_for_unit("postgresql.service")

      check_upgrade_path("15")

      with subtest("Check ${pname} latest extension version"):
        server.succeed("sudo -u postgres psql -c 'DROP EXTENSION ${pname};'")
        server.succeed("sudo -u postgres psql -c 'CREATE EXTENSION ${pname} CASCADE;'")
        installed_extensions=run_sql(r"""SELECT extname, extversion FROM pg_extension;""")
        latestVersion = versions["15"][-1]
        assert f"${pname},{latestVersion}" in installed_extensions

      with subtest("switch to postgresql 17"):
        server.succeed(
          "${pg17-configuration}/bin/switch-to-configuration test >&2"
        )

      check_upgrade_path("17")
    '';
}
