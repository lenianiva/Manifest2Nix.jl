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
  mkDepsDepot = deps:
    stdenv.mkDerivation
    {
      name = "deps";
      src = symlinkJoin {
        name = "deps";
        paths = deps;
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
      if deps == null
      then []
      else [(mkDepsDepot deps)];
    input-depots = lib.strings.concatMapStrings (s: "${s}:") (deps-depot ++ depots);
  in
    stdenv.mkDerivation (args
      // {
        inherit (project) name version;
        nativeBuildInputs = [julia];
        JULIA_LOAD_PATH = "${load-path}:";
        JULIA_DEPOT_PATH = ".julia:${input-depots}";
        JULIA_SSL_CA_ROOTS_PATH = cacert;
        buildPhase = ''
          mkdir -p .julia
          mkdir -p .julia/packages/TextWrap/
          mkdir -p .julia/packages/ArgParse/

          if [ ! -f Manifest.toml ]; then
            ln -s ${lib.defaultTo "none" parent-manifest} Manifest.toml
          fi

          julia --project ${../src/compile.jl}

          mkdir -p $out
          cp -r .julia/compiled/v${abridged-version}/* $out/
        '';
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
        deps = builtins.concatMap (name:
          if builtins.hasAttr name allDeps
          then [(builtins.getAttr name allDeps)]
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
