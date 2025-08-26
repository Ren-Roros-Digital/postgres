{ inputs, ... }:
{
  perSystem =
    { system, ... }:
    let

      go124 =
        let
          candidate = inputs.nixpkgs-go124.legacyPackages.${system};
        in
        if candidate ? go_1_24 then
          candidate.go_1_24
        else
          throw "❌ nixpkgs-go124.${system} does not provide go_1_24!";
    in
    {
      packages.gatekeeper = inputs.gatekeeper.lib.${system}.makeGatekeeper { go = go124; };
    };
}
