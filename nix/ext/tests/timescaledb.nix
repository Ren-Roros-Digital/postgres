{ self, pkgs }:
let
  pname = "timescaledb";
  testLib = import ./lib.nix {
    inherit self pkgs;
    testedExtensionName = pname;
  };
  inherit (testLib) psql_15;
  versions = (testLib.installedExtension "15").versions;
in
self.inputs.nixpkgs.lib.nixos.runTest {
  name = "timescaledb";
  hostPkgs = pkgs;
  nodes.server =
    { config, ... }:
    pkgs.lib.mkMerge [
      (testLib.mkDefaultNixosTestNode { inherit config psql_15; })
      {
        services.postgresql = {
          ensureUsers = [ { name = "service_role"; } ];
          settings = {
            shared_preload_libraries = pkgs.lib.mkForce "timescaledb";
          };
        };
      }
    ];
  testScript =
    { ... }:
    ''
      ${builtins.readFile ./lib.py}

      start_all()

      server.wait_for_unit("multi-user.target")
      server.wait_for_unit("postgresql.service")

      versions = {
        "15": [${pkgs.lib.concatStringsSep ", " (map (s: ''"${s}"'') versions)}],
      }
      extension_name = "${pname}"
      support_upgrade = True
      sql_test_directory = Path("${../../tests}")

      test = PostgresExtensionTest(server, extension_name, versions, sql_test_directory, support_upgrade)

      with subtest("Check upgrade path with postgresql 15"):
        test.check_upgrade_path("15")

      with subtest("Test switch_${pname}_version"):
        test.check_switch_extension_with_background_worker(Path("${psql_15}/lib/${pname}.so"), "15")
    '';
}
