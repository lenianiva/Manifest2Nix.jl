{
  description = "A Nix library for building Julia Projects";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-parts.url = "github:hercules-ci/flake-parts";
  };

  outputs = inputs @ {
    self,
    flake-parts,
    ...
  }:
    flake-parts.lib.mkFlake {inherit inputs;} {
      flake = {
        templates = import ./templates;
        mkLib = import ./lib/compile.nix;
      };
      systems = ["x86_64-linux" "aarch64-linux" "aarch64-darwin" "x86_64-darwin"];
      perSystem = {
        config,
        self',
        inputs',
        pkgs,
        system,
        ...
      }: let
        lib-manifest = pkgs.callPackage lib/manifest.nix {};
        lib-compile = pkgs.callPackage self.mkLib {};
      in {
        formatter = pkgs.alejandra;
        packages = rec {
          inherit (pkgs) julia julia-bin;
        };
        devShells.default = pkgs.mkShell {
          buildInputs = with pkgs; [
            pre-commit
            lib-manifest.manifest2nix
          ];
        };
        checks = (import test/checks.nix) {inherit pkgs lib-manifest lib-compile;};
      };
    };
}
