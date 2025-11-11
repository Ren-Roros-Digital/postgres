{ self, pkgs }:
let
  pname = "pg_repack";
  testLib = import ./lib.nix {
    inherit self pkgs;
    testedExtensionName = pname;
  };
  inherit (testLib) versions psql_15 psql_17;
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
        "15": [${pkgs.lib.concatStringsSep ", " (map (s: ''"${s}"'') (versions "15"))}],
        "17": [${pkgs.lib.concatStringsSep ", " (map (s: ''"${s}"'') (versions "17"))}],
      }
      extension_name = "${pname}"
      support_upgrade = False
      pg17_configuration = "${pg17-configuration}"
      sql_test_directory = Path("${../../tests}")

      ${builtins.readFile ./lib.py}

      start_all()

      server.wait_for_unit("multi-user.target")
      server.wait_for_unit("postgresql.service")

      test = PostgresExtensionTest(server, extension_name, versions, sql_test_directory, support_upgrade)

      with subtest("Check upgrade path with postgresql 15"):
        test.check_upgrade_path("15")

      last_version = None
      with subtest("Check the install of the last version of the extension"):
        last_version = test.check_install_last_version("15")

      with subtest("switch to postgresql 17"):
        server.succeed(
          f"{pg17_configuration}/bin/switch-to-configuration test >&2"
        )

      with subtest("Check last version of the extension after upgrade"):
        test.assert_version_matches(last_version)

      with subtest("Check upgrade path with postgresql 17"):
        test.check_upgrade_path("17")
    '';
}
