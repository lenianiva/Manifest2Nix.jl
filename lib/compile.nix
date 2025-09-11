{
  config,
  lib,
  pkgs,
  julia ? pkgs.julia-bin,
  stdenv,
  runCommand,
  cacert,
  ...
}: let
  abridged-version = "${lib.versions.major julia.version}.${lib.versions.minor julia.version}";
in rec {
  stdlib-depot =
    runCommand "julia-stdlib" {
      JULIA_PKG_OFFLINE = "true";
      JULIA_PKG_SERVER = "";
      JULIA_SSL_CA_ROOTS_PATH = cacert;
      buildInputs = [julia];
    } ''
      mkdir -p $out
      JULIA_DEPOT_PATH=$out julia --project -e "import Pkg"
    '';
  buildJuliaPackage = args @ {src, ...}: let
    project = builtins.fromTOML (builtins.readFile "${src}/Project.toml");
  in
    stdenv.mkDerivation (args
      // {
        inherit (project) name version;
        nativeBuildInputs = [julia];
        JULIA_PKG_OFFLINE = "true";
        JULIA_PKG_SERVER = "";
        JULIA_DEPOT_PATH = ".julia:${stdlib-depot}";
        JULIA_SSL_CA_ROOTS_PATH = cacert;
        buildPhase = ''
          mkdir -p .julia
          julia --project ${../src/compile.jl}

          mkdir -p $out
          ls .julia
          cp -r .julia/compiled/v${abridged-version} $out/
        '';
      });
}
