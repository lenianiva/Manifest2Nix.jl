{
  description = "Minimal Julia Project";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    flake-parts.url = "github:hercules-ci/flake-parts";
    manifest2nix.url = "git+https://codeberg.org/aniva/Manifest2Nix.jl.git";
  };

  outputs = inputs @ {
    nixpkgs,
    flake-parts,
    manifest2nix,
    ...
  }:
    flake-parts.lib.mkFlake {inherit inputs;} {
      systems = [
        "aarch64-darwin"
        "aarch64-linux"
        "x86_64-darwin"
        "x86_64-linux"
      ];

      perSystem = {system, ...}: let
        pkgs = import nixpkgs {
          inherit system;
          overlays = [(manifest2nix.fromManifest ./Manifest.toml)];
        };

        inherit (pkgs) julia;
        m2nlib = manifest2nix.mkLib pkgs;
        package = m2nlib.buildJuliaPackage {src = ./.;};
      in {
        packages = rec {
          default =
            pkgs.runCommand "mystery"
            (m2nlib.createPackageEnv package)
            ''
              ${julia}/bin/julia -e "import Minimal; Minimal.mystery();" > $out
            '';
        };

        devShells.default = pkgs.mkShell {
          packages = [m2nlib.manifest2nix];
        };
      };
    };
}
