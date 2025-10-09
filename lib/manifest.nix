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

  self = lib-compile.buildJuliaPackageWithDeps {
    inherit src;
    pre-exec = "using Manifest2Nix;";
  };
in {
  manifest2nix = pkgs.writeShellApplication {
    name = "manifest2nix";
    runtimeInputs = [julia];
    runtimeEnv = lib-compile.createPackageEnv self;
    text = ''
      ${julia}/bin/julia -e "using Manifest2Nix; main()" -- "$@"
    '';
  };
}
