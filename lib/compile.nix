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
        JULIA_PKG_OFFLINE = "true";
        JULIA_DEPOT_PATH = ".julia";
        buildPhase = ''
          mkdir .julia
          mkdir -p $out
          julia --project -e "import Pkg; Pkg.precompile()"
          cp -r $JULIA_DEPOT_PATH/compiled/${julia.version} $out/
        '';
      });
}
