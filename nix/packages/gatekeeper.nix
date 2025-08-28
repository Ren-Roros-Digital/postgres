{
  inputs,
  system,
  pkgs,
  ...
}:
let
  go124 = inputs.nixpkgs-go124.legacyPackages.${system}.go_1_24;
  # Use completely clean nixpkgs without any overlays for gatekeeper
  #cleanPkgs = inputs.nixpkgs.legacyPackages.${system};
  buildGoModule = pkgs.buildGoModule.override { go = go124; };
in

buildGoModule {
  pname = "gatekeeper";
  version = "0.1.0";

  src = pkgs.fetchFromGitHub {
    owner = "supabase";
    repo = "jit-db-gatekeeper";
    rev = "refs/heads/main";
    hash = "sha256-hrYh1dBxk+aN3b/J9mZqk/ZXHmWA/MIqZLVgICT7e90=";
  };

  vendorHash = "sha256-G9x2TARSJMn30R6ZOlsggxEtn5t2ezWz1YtkLXdYiAE=";

  buildInputs = [
    pkgs.pam
  ] ++ pkgs.lib.optionals pkgs.stdenv.isDarwin [ pkgs.darwin.apple_sdk.frameworks.Security ];

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
}
