{ self, pkgs }:
let
  pname = "supabase_vault";
  testLib = import ./lib.nix {
    inherit self pkgs;
    testedExtensionName = pname;
  };
  inherit (testLib) mkPostgresqlWithExtensions versions;
  psql_15 = mkPostgresqlWithExtensions self.packages.${pkgs.system}.postgresql_15 [
    pname
    "pgsodium"
  ];
  psql_17 = mkPostgresqlWithExtensions self.packages.${pkgs.system}.postgresql_17 [
    pname
    "pgsodium"
  ];
  vaultGetKey = pkgs.lib.getExe (
    pkgs.writeShellScriptBin "vault-getkey" ''
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
          initialScript = pkgs.writeText "vault-init.sql" ''
            CREATE SCHEMA vault;
          '';
          ensureUsers = [ { name = "service_role"; } ];
          settings = {
            "shared_preload_libraries" = pkgs.lib.mkForce "${pname},pgsodium";
            "pgsodium.getkey_script" = vaultGetKey;
            "vault.getkey_script" = vaultGetKey;
            "search_path" = "\"$user\", public, auth, extensions";
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
                  echo "shared_preload_libraries = '${pname},pgsodium'" >> "${newDataDir}/postgresql.conf"
                  echo "vault.getkey_script = '${vaultGetKey}'" >> "${newDataDir}/postgresql.conf";
                  echo "pgsodium.getkey_script = '${vaultGetKey}'" >> "${newDataDir}/postgresql.conf";
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
      from pathlib import Path
      versions = {
        "15": [${pkgs.lib.concatStringsSep ", " (map (s: ''"${s}"'') (versions "15"))}],
        "17": [${pkgs.lib.concatStringsSep ", " (map (s: ''"${s}"'') (versions "17"))}],
      }
      extension_name = "${pname}"
      support_upgrade = True
      pg17_configuration = "${pg17-configuration}"
      ext_has_background_worker = ${
        if (testLib.installedExtension "15") ? hasBackgroundWorker then "True" else "False"
      }
      sql_test_directory = Path("${../../tests}")
      pg_regress_test_name = "${(testLib.installedExtension "15").pgRegressTestName or pname}"

      ${builtins.readFile ./lib.py}

      start_all()

      server.wait_for_unit("multi-user.target")
      server.wait_for_unit("postgresql.service")

      test = PostgresExtensionTest(server, extension_name, versions, sql_test_directory, support_upgrade)


      with subtest("Check upgrade path with postgresql 15"):
        test.check_upgrade_path("15")

      with subtest("Check pg_regress with postgresql 15 after extension upgrade"):
        test.run_sql_file("${../../../ansible/files/postgresql_extension_custom_scripts/supabase_vault/after-create.sql}")
        test.check_pg_regress(Path("${psql_15}/lib/pgxs/src/test/regress/pg_regress"), "15", pg_regress_test_name)

      last_version = None
      with subtest("Check the install of the last version of the extension"):
        last_version = test.check_install_last_version("15")

      with subtest("Check pg_regress with postgresql 15 after installing the last version"):
        test.run_sql_file("${../../../ansible/files/postgresql_extension_custom_scripts/supabase_vault/after-create.sql}")
        test.check_pg_regress(Path("${psql_15}/lib/pgxs/src/test/regress/pg_regress"), "15", pg_regress_test_name)

      with subtest("switch to postgresql 17"):
        server.succeed(
          f"{pg17_configuration}/bin/switch-to-configuration test >&2"
        )

      with subtest("Check last version of the extension after postgresql upgrade"):
        test.assert_version_matches(last_version)

      with subtest("Check upgrade path with postgresql 17"):
        test.check_upgrade_path("17")

      with subtest("Check pg_regress with postgresql 17 after extension upgrade"):
        test.run_sql_file("${../../../ansible/files/postgresql_extension_custom_scripts/supabase_vault/after-create.sql}")
        test.check_pg_regress(Path("${psql_17}/lib/pgxs/src/test/regress/pg_regress"), "17", pg_regress_test_name)

      with subtest("Check the install of the last version of the extension"):
        test.check_install_last_version("17")

      with subtest("Check pg_regress with postgresql 17 after installing the last version"):
        test.run_sql_file("${../../../ansible/files/postgresql_extension_custom_scripts/supabase_vault/after-create.sql}")
        test.check_pg_regress(Path("${psql_17}/lib/pgxs/src/test/regress/pg_regress"), "17", pg_regress_test_name)
    '';
}
