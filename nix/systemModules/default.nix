{
  ...
}:
{
  imports = [ ./tests ];
  flake = {
    systemModules = {
      logrotate = ./logrotate.nix;
    };
  };
}
