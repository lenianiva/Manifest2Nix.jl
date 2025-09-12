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
        lib-compile = pkgs.callPackage lib/compile.nix {};
      in {
        formatter = pkgs.alejandra;
        packages = rec {
          minimal-jl = lib-compile.buildJuliaPackage {src = templates/minimal;};
          minimal-jl-depot = lib-compile.mkDepsDepot [minimal-jl];
          simple-jl = lib-compile.buildJuliaPackageWithDeps {src = templates/simple;};
        };
        devShells.default = pkgs.mkShell {
          buildInputs = with pkgs; [
            pre-commit
            lib-manifest.manifest2nix
          ];
        };
        checks = {
          inherit (lib-compile) stdlib-depot;
        };
      };
      flake = {
        templates = import ./templates;
      };
    };
}
