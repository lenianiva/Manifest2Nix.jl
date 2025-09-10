{
  config,
  lib,
  pkgs,
  julia ? pkgs.julia-bin,
  ...
}: {
  buildJuliaPackage = args @ {src, ...}: let
    project = builtins.fromTOML (builtins.readFile "${src}/Project.toml");
  in
    pkgs.stdenv.mkDerivation (args
      // {
        inherit (project) name version;
        nativeBuildInputs = [julia];
        buildPhase = ''
          mkdir .julia
          mkdir -p $out
          JULIA_DEPOT_PATH=.julia julia --project -e "import Pkg; Pkg.precompile()"
          cp -r .julia/compiled/${julia.version} $out/
        '';
      });
}
