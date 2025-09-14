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
  # This depot contains a cached version of stdlib
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
  # Given a list of Julia packages, pack them into one depot
  mkDepsDepot = deps:
    stdenv.mkDerivation
    {
      name = "deps";
      src = symlinkJoin {
        name = "deps";
        paths = builtins.map (dep: dep.compiled) deps;
      };
      phases = ["unpackPhase" "installPhase"];
      installPhase = ''
        mkdir -p $out/compiled/
        ln -s $src/ $out/compiled/v${abridged-version}
      '';
    };
  # Builds a Julia package
  buildJuliaPackage = args @ {
    src,
    depots ? [stdlib-depot],
    deps ? [],
    # Parent manifest file
    parent-manifest ? null,
    ...
  }: let
    project = builtins.fromTOML (builtins.readFile "${src}/Project.toml");
    load-path = symlinkJoin {
      name = "deps";
      paths = builtins.map (dep: dep.load-path) deps;
    };
    deps-depot =
      if deps == []
      then []
      else [(mkDepsDepot deps)];
    input-depots = deps-depot ++ depots;
    # This leaves a trailing : for the system depot
    input-depots-paths = lib.strings.concatMapStrings (s: "${s}:") input-depots;
  in {
    inherit (project) name version;
    inherit src input-depots;
    # A special derivation for creating load paths
    load-path = stdenv.mkDerivation rec {
      inherit (project) name;
      inherit src;
      phases = ["unpackPhase" "installPhase"];
      installPhase = ''
        mkdir $out
        cp -r ${src} $out/${name}
      '';
    };
    compiled = stdenv.mkDerivation {
      inherit (args) src;
      inherit (project) name version;
      nativeBuildInputs = [julia];
      JULIA_LOAD_PATH = "${load-path}:";
      JULIA_DEPOT_PATH = ".julia:${input-depots-paths}";
      buildPhase = ''
        mkdir -p .julia
        mkdir -p .julia/packages/TextWrap/
        mkdir -p .julia/packages/ArgParse/

        if [ ! -f Manifest.toml ]; then
          ln -s ${lib.defaultTo "no-parent-manifest" parent-manifest} Manifest.toml
        fi

        julia --project ${../src/compile.jl}

        mkdir -p $out
        cp -r .julia/compiled/v${abridged-version}/* $out/
      '';
    };
  };
  # Given a built Julia package, create an environment for running code
  createJuliaEnv = {
    src,
    load-path,
    input-depots,
    ...
  }: let
    input-depots-str = lib.strings.concatMapStrings (s: "${s}:") input-depots;
  in {
    JULIA_LOAD_PATH = "${src}:${load-path}";
    JULIA_DEPOT_PATH = input-depots-str;
  };
  # Create a Julia package from a dependency file
  buildJuliaPackageWithDeps = args @ {
    src,
    lockFile ? "${src}/Lock.toml",
    ...
  }: let
    lock = builtins.fromTOML (builtins.readFile lockFile);

    depToPackage = name: {
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
        deps = builtins.concatMap (name:
          if builtins.hasAttr name allDeps
          then [allDeps.${name}]
          else [])
        dependencies;
        # FIXME: Handle different parent manfiest
        parent-manifest = "${src}/Manifest.toml";
      };

    allDeps = builtins.mapAttrs depToPackage lock.deps;
  in
    buildJuliaPackage (args
      // {
        deps = builtins.attrValues allDeps;
      });
}
