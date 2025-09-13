{
  config,
  lib,
  pkgs,
  ...
}: {
  manifest2nix = pkgs.writeShellApplication {
    name = "manifest2nix";
    runtimeInputs = [pkgs.julia-bin];
    text = ''
      ${pkgs.julia-bin}/bin/julia --project -e "using Manifest2Nix; main()" -- "$@"
    '';
  };
}
