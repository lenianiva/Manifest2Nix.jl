{
  config,
  lib,
  pkgs,
  #julia ? pkgs.julia-bin,
  stdenv,
  runCommand,
  symlinkJoin,
  cacert,
  ...
}: let
  julia = pkgs.julia-bin;
  abridged-version = "${lib.versions.major julia.version}.${lib.versions.minor julia.version}";
in rec {
  stdlib-depot =
    runCommand "julia-stdlib" {
      JULIA_PKG_OFFLINE = "true";
      JULIA_PKG_SERVER = "";
      JULIA_SSL_CA_ROOTS_PATH = cacert;
      buildInputs = [julia];
    } ''
      mkdir -p $out
      JULIA_DEPOT_PATH=$out julia --project -e "import Pkg"
    '';
  mkDepsDepot = deps:
    stdenv.mkDerivation {
      name = "deps";
      src = symlinkJoin {
        name = "deps";
        paths = builtins.attrValues deps;
      };
      phases = ["unpackPhase" "installPhase"];
      installPhase = ''
        mkdir -p $out/compiled/
        ln -s $src/ $out/compiled/v${abridged-version}
      '';
    };
  buildJuliaPackage = args @ {
    src,
    depots ? [stdlib-depot],
    deps ? [],
    ...
  }: let
    project = builtins.fromTOML (builtins.readFile "${src}/Project.toml");
    deps-depot =
      if deps == null
      then []
      else [(mkDepsDepot deps)];
    input-depots = lib.strings.concatMapStrings (s: "${s}:") (deps-depot ++ depots);
  in
    stdenv.mkDerivation (args
      // {
        inherit (project) name version;
        nativeBuildInputs = [julia];
        JULIA_PKG_OFFLINE = "true";
        JULIA_PKG_SERVER = "";
        JULIA_DEPOT_PATH = ".julia:${input-depots}";
        JULIA_SSL_CA_ROOTS_PATH = cacert;
        buildPhase = ''
          mkdir -p .julia
          julia --project ${../src/compile.jl}

          mkdir -p $out
          ls .julia
          cp -r .julia/compiled/v${abridged-version}/* $out/
        '';
      });
  # Create a Julia package from a dependency file
  buildJuliaPackageWithDeps = args @ {
    src,
    lockFile ? "${src}/Lock.toml",
    ...
  }: let
    lock = builtins.fromTOML (builtins.readFile lockFile);
    depToPackage = name: dep @ {
      repo,
      rev,
      dependencies,
      ...
    }:
      buildJuliaPackage {
        src = builtins.fetchGit {
          url = repo;
          inherit rev;
          shallow = true;
        };
        deps = lib.getAttrs dependencies allDeps;
      };
    allDeps = builtins.mapAttrs depToPackage lock.deps;
  in
    buildJuliaPackage (args
      // {
        deps = allDeps;
      });
}
