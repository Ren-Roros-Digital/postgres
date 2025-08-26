{ inputs, ... }:
{
  perSystem =
    { system, ... }:
    let
      go124 = inputs.nixpkgs-go124.legacyPackages.${system}.go_1_24;
    in
    {
      packages.gatekeeper = inputs.gatekeeper.lib.${system}.makeGatekeeper { go = go124; };
    };
}
