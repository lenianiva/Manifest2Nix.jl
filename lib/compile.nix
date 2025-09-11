{
  config,
  lib,
  pkgs,
  julia ? pkgs.julia-bin,
  stdenv,
  cacert,
  ...
}: let
  abridged-version = "${lib.versions.major julia.version}.${lib.versions.minor julia.version}";
in {
  buildJuliaPackage = args @ {src, ...}: let
    project = builtins.fromTOML (builtins.readFile "${src}/Project.toml");
  in
    stdenv.mkDerivation (args
      // {
        inherit (project) name version;
        nativeBuildInputs = [julia];
        JULIA_PKG_OFFLINE = "true";
        JULIA_PKG_SERVER = "";
        JULIA_DEPOT_PATH = ".julia";
        JULIA_SSL_CA_ROOTS_PATH = cacert;
        buildPhase = ''
          mkdir -p $JULIA_DEPOT_PATH
          julia --project -e "import Pkg; Pkg.Registry.rm(\"General\"); Pkg.build()"

          mkdir -p $out
          cp -r $JULIA_DEPOT_PATH/compiled/v${abridged-version} $out/
        '';
      });
}
