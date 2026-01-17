{
  description = "A Nix library for building Julia Projects";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-parts.url = "github:hercules-ci/flake-parts";
  };

  outputs = inputs @ {
    self,
    nixpkgs,
    flake-parts,
    ...
  }:
    flake-parts.lib.mkFlake {inherit inputs;} {
      flake =
        (import lib/overlays.nix)
        // {
          templates = import ./templates;
          mkLib = pkgs: (pkgs.callPackage ./lib/compile.nix {}) // (pkgs.callPackage ./lib/manifest.nix {});
        };
      systems = ["x86_64-linux" "aarch64-linux" "aarch64-darwin" "x86_64-darwin"];
      perSystem = {
        config,
        self',
        inputs',
        system,
        ...
      }: let
        pkgs = import nixpkgs {
          inherit system;
          overlays = [(self.fromVersion "1.12.4")];
          #overlays = [self.fromJuliaBin];
        };
        lib-manifest = pkgs.callPackage lib/manifest.nix {};
        lib-compile = self.mkLib pkgs;
        lib-toolchain = pkgs.callPackage lib/toolchain.nix {};
      in {
        packages = rec {
          inherit (pkgs) julia julia-bin;
          inherit (lib-toolchain) toolchain-fetch;
          inherit (lib-manifest) manifest2nix;
        };
        formatter = pkgs.alejandra;
        devShells.default = pkgs.mkShell {
          buildInputs = with pkgs; [
            julia
            pre-commit
          ];
        };
        checks = ((import test/checks.nix) {inherit pkgs lib-compile;}) // ((import test/version.nix) {inherit nixpkgs system;});
      };
    };
}
