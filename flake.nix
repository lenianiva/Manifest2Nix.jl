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
        lib-compile = pkgs.callPackage lib/compile.nix {};
      in {
        formatter = pkgs.alejandra;
        packages = {
          inherit (lib-compile) stdlib-depot;
          minimal-lib = lib-compile.buildJuliaPackage {src = templates/minimal;};
        };
        devShells.default = pkgs.mkShell {
          buildInputs = with pkgs; [
            pre-commit
          ];
        };
      };
      flake = {
        templates = import ./templates;
      };
    };
}
