{ self, pkgs }:
let
  testsDir = ./.;
  testFiles = builtins.attrNames (builtins.readDir testsDir);
  nixFiles = builtins.filter (
    name: builtins.match ".*\\.nix$" name != null && name != "default.nix" && name != "lib.nix"
  ) testFiles;
  extTest =
    extension_name:
    let
      pname = extension_name;
      inherit (pkgs) lib;
      versions = postgresqlMajorVersion: (testLib.installedExtension postgresqlMajorVersion).versions;
      postgresqlWithExtension =
        postgresql:
        let
          majorVersion = lib.versions.major postgresql.version;
          pkg = pkgs.buildEnv {
            name = "postgresql-${majorVersion}-${pname}";
            paths = [
              postgresql
              postgresql.lib
              (testLib.installedExtension majorVersion)
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
        testedExtensionName = extension_name;
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
          from pathlib import Path
          versions = {
            "15": [${lib.concatStringsSep ", " (map (s: ''"${s}"'') (versions "15"))}],
            "17": [${lib.concatStringsSep ", " (map (s: ''"${s}"'') (versions "17"))}],
          }
          extension_name = "${pname}"
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

          test = PostgresExtensionTest(server, extension_name, versions, sql_test_directory)

          with subtest("Check upgrade path with postgresql 15"):
            test.check_upgrade_path("15")

          with subtest("Check pg_regress with postgresql 15 after extension upgrade"):
            test.check_pg_regress(Path("${psql_15}/lib/pgxs/src/test/regress/pg_regress"), "15", pg_regress_test_name)

          last_version = None
          with subtest("Check the install of the last version of the extension"):
            last_version = test.check_install_last_version("15")

          if ext_has_background_worker:
            with subtest("Test switch_${pname}_version"):
              test.check_switch_extension_with_background_worker(Path("${psql_15}/lib/${pname}.so"), "15")

          with subtest("Check pg_regress with postgresql 15 after installing the last version"):
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
            test.check_pg_regress(Path("${psql_17}/lib/pgxs/src/test/regress/pg_regress"), "17", pg_regress_test_name)

          with subtest("Check the install of the last version of the extension"):
            test.check_install_last_version("17")

          with subtest("Check pg_regress with postgresql 17 after installing the last version"):
            test.check_pg_regress(Path("${psql_17}/lib/pgxs/src/test/regress/pg_regress"), "17", pg_regress_test_name)
        '';
    };
in
builtins.listToAttrs (
  map (file: {
    name = "ext-" + builtins.replaceStrings [ ".nix" ] [ "" ] file;
    value = import (testsDir + "/${file}") { inherit self pkgs; };
  }) nixFiles
)
// builtins.listToAttrs (
  map
    (extName: {
      name = "ext-${extName}";
      value = extTest extName;
    })
    [
      "hypopg"
      "index_advisor"
      "pg_cron"
      "pg_hashids"
      "pg_graphql"
      "pg_jsonschema"
      "pg_net"
      "pgaudit"
      "pg_tle"
      "vector"
      "wrappers"
    ]
)
