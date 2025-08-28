{ inputs, ... }:
{
  perSystem =
    { system, pkgs, ... }:
    let
      go124 = inputs.nixpkgs-go124.legacyPackages.${system}.go_1_24;
      # Use completely clean nixpkgs without any overlays for gatekeeper
      cleanPkgs = inputs.nixpkgs.legacyPackages.${system};
      buildGoModule = cleanPkgs.buildGoModule.override { go = go124; };
    in
    {
      packages.gatekeeper = buildGoModule {
        pname = "gatekeeper";
        version = "0.1.0";

        src = inputs.gatekeeper-src;

        vendorHash = "sha256-pdF+bhvZQwd2iSEHVtDAGihkYZGSaQaFdsF8MSrWuKQ=";

        buildInputs =
          [ cleanPkgs.pam ]
          ++ cleanPkgs.lib.optionals cleanPkgs.stdenv.isDarwin [
            cleanPkgs.darwin.apple_sdk.frameworks.Security
          ];

        buildPhase = ''
          runHook preBuild
          go build -buildmode=c-shared -o pam_jwt_pg.so
          runHook postBuild
        '';

        installPhase = ''
          runHook preInstall
          mkdir -p $out/lib/security
          cp pam_jwt_pg.so $out/lib/security/
          runHook postInstall
        '';

        meta = with pkgs.lib; {
          description = "PAM module for JWT authentication with PostgreSQL backend";
          homepage = "https://github.com/supabase/jit-db-gatekeeper";
          license = licenses.mit;
          platforms = platforms.unix;
        };
      };
    };
}
