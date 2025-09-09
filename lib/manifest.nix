{
  config,
  lib,
  pkgs,
  ...
}: {
  lock-manifest = pkgs.writeShellApplication {
    name = "lock-manifest";
    runtimeInputs = [pkgs.julia-bin];
    text = ''
      ${pkgs.julia-bin}/bin/julia --project="$PWD" src/manifest.jl
    '';
  };
}
