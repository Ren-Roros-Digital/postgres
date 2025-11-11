# lib.nix
#
# Common utilities and configuration builders for PostgreSQL extension tests.
#
# This module provides reusable functions to create NixOS test nodes with
# standard PostgreSQL configurations, reducing duplication across extension
# test files.
#
# ## Exports
#
# - `installedExtension`: Function to get the installed extension package for a PostgreSQL version
# - `mkDefaultNixosTestNode`: Creates a NixOS test node with standard PostgreSQL setup
# - `psql_15`: PostgreSQL 15 package with the tested extension
# - `psql_17`: PostgreSQL 17 package with the tested extension
# - `versions`: Function to get available extension versions for a PostgreSQL version
# - `mkPostgresqlWithExtensions`: Builds a PostgreSQL package with a list of extensions
#
# ## Examples
#
# See existing test files for real-world examples:
# - Simple tests: postgis.nix, http.nix, plpgsql_check.nix
# - With custom settings: vault.nix, pgsodium.nix
# - With environment variables: pgroonga.nix
# - Complex specialisations: pgrouting.nix
{
  self,
  pkgs,
  testedExtensionName,
}:
rec {
  # Get the installed extension package for a specific PostgreSQL major version.
  #
  # Type: installedExtension :: String -> Derivation
  #
  # Example:
  #   installedExtension "15" => derivation
  installedExtension =
    postgresMajorVersion: # The PostgreSQL major version (e.g., "15", "17")
    self.packages.${pkgs.system}."psql_${postgresMajorVersion}/exts/${testedExtensionName}-all";

  # Create a default NixOS test node with PostgreSQL configured for extension testing.
  #
  # When psql_17 is null, the postgresql17 specialisation is disabled.
  # This is useful for extensions that only support PostgreSQL 15.
  #
  # Override or extend configuration using lib.mkMerge:
  # Example:
  #   lib.mkMerge [
  #     (mkDefaultNixosTestNode { inherit config psql_15 psql_17; })
  #     { services.postgresql.settings.shared_preload_libraries = lib.mkForce "my_ext"; }
  #   ]
  mkDefaultNixosTestNode =
    {
      config, # The node's config attribute
      psql_15, # PostgreSQL 15 package with extension
      psql_17 ? null, # PostgreSQL 17 package with extension (optional)
      ...
    }:
    {
      virtualisation = {
        forwardPorts = [
          {
            from = "host";
            host.port = 13022;
            guest.port = 22;
          }
        ];
      };
      services.openssh = {
        enable = true;
      };

      services.postgresql = {
        enable = true;
        package = psql_15;
        enableTCPIP = true;
        authentication = ''
          local all postgres peer map=postgres
          local all all peer map=root
        '';
        identMap = ''
          root root supabase_admin
          postgres postgres postgres
        '';
        ensureUsers = [
          {
            name = "supabase_admin";
            ensureClauses.superuser = true;
          }
        ];
        settings = (installedExtension "15").defaultSettings or { };
      };

      networking.firewall.allowedTCPPorts = [ config.services.postgresql.settings.port ];

      specialisation.postgresql17.configuration = pkgs.lib.mkIf (psql_17 != null) {
        services.postgresql = {
          package = pkgs.lib.mkForce psql_17;
          settings = (installedExtension "17").defaultSettings or { };
        };

        systemd.services.postgresql-migrate = {
          serviceConfig = {
            Type = "oneshot";
            RemainAfterExit = true;
            User = "postgres";
            Group = "postgres";
            StateDirectory = "postgresql";
            WorkingDirectory = "${builtins.dirOf config.services.postgresql.dataDir}";
          };
          script =
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
                ${newPostgresql}/bin/pg_upgrade --old-datadir "${oldDataDir}" --new-datadir "${newDataDir}" \
                  --old-bindir "${oldPostgresql}/bin" --new-bindir "${newPostgresql}/bin" \
                  ${
                    if config.services.postgresql.settings.shared_preload_libraries != null then
                      " --old-options='-c shared_preload_libraries=${config.services.postgresql.settings.shared_preload_libraries}' --new-options='-c shared_preload_libraries=${config.services.postgresql.settings.shared_preload_libraries}'"
                    else
                      ""
                  }
              else
                echo "${newDataDir} already exists"
              fi
            '';
        };

        systemd.services.postgresql = {
          after = [ "postgresql-migrate.service" ];
          requires = [ "postgresql-migrate.service" ];
        };
      };
    };

  # Build a PostgreSQL package that includes a list of extensions.
  #
  # The included extension can be accessed via the `testedExtension` attribute.
  #
  mkPostgresqlWithExtensions =
    postgresql: # The PostgreSQL package to extend with the extension
    extensions: # A list of extension packages to include, the first will be the testedExtension
    let
      majorVersion = pkgs.lib.versions.major postgresql.version;
      # Build paths for all extensions
      extensionPaths = map (
        ext: self.packages.${pkgs.system}."psql_${majorVersion}/exts/${ext}-all"
      ) extensions;
      # Automatically add orioledb if building for OrioleDB
      orioledbPaths =
        pkgs.lib.optional postgresql.isOrioleDB
          self.packages.${pkgs.system}."psql_orioledb-17/exts/orioledb";
      pkg = pkgs.buildEnv {
        name = "postgresql-${majorVersion}-${testedExtensionName}";
        paths = [
          postgresql
          postgresql.lib
        ] ++ extensionPaths ++ orioledbPaths;
        passthru = {
          inherit (postgresql) version psqlSchema;
          lib = pkg;
          testedExtension = builtins.head extensionPaths;
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
  psql_15 = mkPostgresqlWithExtensions self.packages.${pkgs.system}.postgresql_15 [
    testedExtensionName
  ];
  psql_17 = mkPostgresqlWithExtensions self.packages.${pkgs.system}.postgresql_17 [
    testedExtensionName
  ];
  # Get available extension versions for a specific PostgreSQL major version.
  versions =
    postgresqlMajorVersion: # The PostgreSQL major version (e.g., "15", "17")
    (installedExtension postgresqlMajorVersion).versions;
}
