{
  config,
  lib,
  pkgs,
  julia,
  stdenv,
  symlinkJoin,
  ...
}: let
  inherit (pkgs.lib.fileset) unions toSource fileFilter;
  lib-compile = pkgs.callPackage ./compile.nix {};
  src = toSource {
    root = ../.;
    fileset = unions [
      ../Project.toml
      ../Manifest.toml
      ../Lock.toml
      (fileFilter (file: file.hasExt "jl") ../src)
    ];
  };

  packages = [self] ++ self.deps;

  self = lib-compile.buildJuliaPackageWithDeps {
    inherit src;
  };
  load-path = symlinkJoin {
    name = "deps";
    paths = builtins.map (dep: dep.load-path) packages;
  };
in rec {
  manifest2nix = pkgs.writeShellApplication {
    name = "manifest2nix";
    runtimeInputs = [julia];
    runtimeEnv = {
      JULIA_LOAD_PATH = "${load-path}:";
      JULIA_DEPOT_PATH = ".julia:${lib-compile.mkDepsDepot packages}";
    };
    text = ''
      ${julia}/bin/julia -e "using Manifest2Nix; main()" -- "$@"
    '';
  };
}
