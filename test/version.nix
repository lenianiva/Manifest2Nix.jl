# Check manifest2nix can build with all provided Julia versions.
{
  nixpkgs,
  system,
}: let
  sources = import ../lib/sources.nix;
  overlays = import ../lib/overlays.nix;
  checkVersion = version: let
    pkgs = import nixpkgs {
      inherit system;
      overlays = [(overlays.fromVersion version)];
    };
    lib-compile = pkgs.callPackage ../lib/compile.nix {};
    version-dir = ../version + "/${pkgs.lib.versions.major version}.${pkgs.lib.versions.minor version}";
    package = lib-compile.buildJuliaPackageWithDeps {
      src = ../.;
      manifestFile = "${version-dir}/Manifest.toml";
      lockFile = "${version-dir}/Lock.toml";
    };
  in
    package.compiled;
in
  builtins.mapAttrs (version: _: checkVersion version) sources
