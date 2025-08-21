{
  lib,
  nixosModulesPath,
  config,
  ...
}:
let
  cfg = config.supabase.services.logrotate;
in
{
  imports = map (path: nixosModulesPath + path) [
    # FIXME: we can't use the logrotate module from nixpkgs becauce it's defined as a no-op option in system-manager:
    # https://github.com/numtide/system-manager/blob/main/nix/modules/default.nix#L102-L108
    #
    # error: The option `services.logrotate' in module `/nix/store/...-source/nix/modules'
    # would be a parent of the following options,but its type `attribute set' does not support nested options.
    #
    # "/services/logging/logrotate.nix"
  ];

  options = {
    supabase.services.logrotate = {
      enable = lib.mkEnableOption "Whether to enable the logrotate systemd service.";
    };
  };

  config = lib.mkIf cfg.enable {
    environment.etc = {
      "logrotate.d/logrotate-postgres-auth.conf".text = ''
        /var/log/postgresql/auth-failures.csv {
          size 10M
          rotate 5
          compress
          delaycompress
          notifempty
          missingok
        }
      '';
      "logrotate.d/logrotate-postgres-csv.conf".text = ''
        /var/log/postgresql/postgresql.csv {
          size 50M
          rotate 9
          compress
          delaycompress
          notifempty
          missingok
          postrotate
            sudo -u postgres /usr/lib/postgresql/bin/pg_ctl -D /var/lib/postgresql/data logrotate
          endscript
        }
      '';
      "logrotate.d/logrotate-postgres.conf".text = ''
        /var/log/postgresql/postgresql.log {
          size 50M
          rotate 3
          copytruncate
          delaycompress
          compress
          notifempty
          missingok
        }
      '';
      "logrotate.d/logrotate-walg.conf".text = ''
        /var/log/wal-g/*.log {
          size 50M
          rotate 3
          copytruncate
          delaycompress
          compress
          notifempty
          missingok
        }
      '';
    };

    # FIXME: logrotate.service isn't a valid unit file (missing ExecStart), because it's already provided by Ubuntu:
    # systemd.services.logrotate = {
    #   wantedBy = lib.mkForce [
    #     "system-manager.target"
    #   ];
    # };

    # Overide systemd logrotate.timer to run every 5 minutes:
    systemd.timers.logrotate = {
      wantedBy = [ "timers.target" ];
      timerConfig.OnCalendar = "*:0/5";
      timerConfig.Persistent = true;
    };
  };
}
