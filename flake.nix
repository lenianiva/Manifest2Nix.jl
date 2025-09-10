{
  description = "A Nix library for building Julia Projects";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-parts.url = "github:hercules-ci/flake-parts";
  };

  outputs = inputs @ {flake-parts, ...}:
    flake-parts.lib.mkFlake {inherit inputs;} {
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
      in {
        formatter = pkgs.alejandra;
        packages = {
        };
        devShells.default = pkgs.mkShell {
          buildInputs = with pkgs; [
            pre-commit
            lib-manifest.manifest2nix
          ];
        };
      };
      flake = {
        templates = import ./templates;
      };
    };
}
