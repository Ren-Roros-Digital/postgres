{ inputs, ... }:
let
  ghWorkflows = builtins.attrNames (builtins.readDir ../.github/workflows);
  lintedWorkflows = [ "ansible-test.yml" ];
in
{
  imports = [ inputs.git-hooks.flakeModule ];
  perSystem =
    { config, ... }:
    {
      pre-commit = {
        check.enable = true;
        settings = {
          hooks = {
            actionlint = {
              enable = true;
              excludes = builtins.filter (name: !builtins.elem name lintedWorkflows) ghWorkflows;
              verbose = true;
            };

            ansible-lint = {
              enable = true;
              verbose = true;
              settings = {
                configPath = "${../.ansible-lint.yml}";
                subdir = "ansible/tests";
              };
            };

            treefmt = {
              enable = true;
              package = config.treefmt.build.wrapper;
              pass_filenames = false;
              verbose = true;
            };
          };
        };
      };
    };
}
