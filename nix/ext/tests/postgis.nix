{ self, pkgs }:
let
  pname = "postgis";
  inherit (pkgs) lib;
  installedExtension =
    postgresMajorVersion: self.packages.${pkgs.system}."psql_${postgresMajorVersion}/exts/${pname}-all";
  versions = postgresqlMajorVersion: (installedExtension postgresqlMajorVersion).versions;
  postgresqlWithExtension =
    postgresql:
    let
      majorVersion = lib.versions.major postgresql.version;
      pkg = pkgs.buildEnv {
        name = "postgresql-${majorVersion}-${pname}";
        paths = [
          postgresql
          postgresql.lib
          (installedExtension majorVersion)
        ];
        passthru = {
          inherit (postgresql) version psqlSchema;
          lib = pkg;
          withPackages = _: pkg;
        };
        nativeBuildInputs = [ pkgs.makeWrapper ];
        pathsToLink = [
          "/"
          "/bin"
          "/lib"
        ];
        postBuild = ''
          wrapProgram $out/bin/postgres --set NIX_PGLIBDIR $out/lib
          wrapProgram $out/bin/pg_ctl --set NIX_PGLIBDIR $out/lib
          wrapProgram $out/bin/pg_upgrade --set NIX_PGLIBDIR $out/lib
        '';
      };
    in
    pkg;
  testLib = import ./lib.nix {
    inherit self pkgs;
    testedExtensionName = pname;
  };
  psql_15 = postgresqlWithExtension self.packages.${pkgs.system}.postgresql_15;
  psql_17 = postgresqlWithExtension self.packages.${pkgs.system}.postgresql_17;
in
self.inputs.nixpkgs.lib.nixos.runTest {
  name = pname;
  hostPkgs = pkgs;
  nodes.server = { config, ... }: testLib.mkDefaultNixosTestNode { inherit config psql_15 psql_17; };
  testScript =
    { nodes, ... }:
    let
      pg17-configuration = "${nodes.server.system.build.toplevel}/specialisation/postgresql17";
    in
    ''
      versions = {
        "15": [${lib.concatStringsSep ", " (map (s: ''"${s}"'') (versions "15"))}],
        "17": [${lib.concatStringsSep ", " (map (s: ''"${s}"'') (versions "17"))}],
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
        installed_extensions=run_sql(r"""SELECT extname, extversion FROM pg_extension where extname = '${pname}';""")
        latestVersion = versions["15"][-1]
        majMinVersion = ".".join(latestVersion.split('.')[:1])
        assert f"${pname},{majMinVersion}" in installed_extensions, f"Expected ${pname} version {latestVersion}, but found {installed_extensions}"

      with subtest("switch to postgresql 17"):
        server.succeed(
          "${pg17-configuration}/bin/switch-to-configuration test >&2"
        )

      with subtest("Check ${pname} latest extension version after upgrade"):
        installed_extensions=run_sql(r"""SELECT extname, extversion FROM pg_extension;""")
        latestVersion = versions["17"][-1]
        majMinVersion = ".".join(latestVersion.split('.')[:1])
        assert f"${pname},{majMinVersion}" in installed_extensions

      check_upgrade_path("17")
    '';
}
