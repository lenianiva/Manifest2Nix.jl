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
      (fileFilter (file: file.hasExt "jl") ../src)
    ];
  };

  version-dir = ../version + "/${lib.versions.major julia.version}.${lib.versions.minor julia.version}";

  self = lib-compile.buildJuliaPackageWithDeps {
    inherit src;
    manifestFile = "${version-dir}/Manifest.toml";
    lockFile = "${version-dir}/Lock.toml";
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
