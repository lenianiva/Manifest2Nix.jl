{
  config,
  lib,
  pkgs,
  #julia ? pkgs.julia-bin,
  stdenv,
  runCommand,
  symlinkJoin,
  cacert,
  fetchurl,
  zstd,
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
  mkDepsDepot = deps: let
    # Collect all requisite artifacts
    artifacts = lib.mergeAttrsList (builtins.map (dep: dep.artifacts) deps);
    artifacts-join =
      if artifacts != []
      then
        symlinkJoin {
          name = "artifacts";
          paths = builtins.attrValues artifacts;
        }
      else "";
  in
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
        ${
          if artifacts-join != ""
          then "ln -s ${artifacts-join} $out/artifacts"
          else ""
        }
        ln -s $src/ $out/compiled/v${abridged-version}
      '';
    };
  # This dictionary matches against targets in the `Artifact.toml` file.
  artifactProperties = let
    p = stdenv.hostPlatform;
  in {
    arch =
      if p.isAarch
      then "aarch64"
      else "x86_64";
    os =
      if p.isDarwin
      then p.darwinPlatform
      else "linux";
    libc =
      if p.isMusl
      then "musl"
      else "libc";
  };
  filterPlatformDependentArtifact = artifact:
    if builtins.isList artifact
    then let
      candidates = builtins.filter (art: lib.matchAttrs (builtins.intersectAttrs art artifactProperties) art) artifact;
    in (
      if candidates == []
      then null
      else builtins.head candidates
    )
    else artifact;
  collectArtifacts = artifactsPath: let
    artifacts = builtins.fromTOML (builtins.readFile artifactsPath);
    remap = name: candidates: let
      artifact = filterPlatformDependentArtifact candidates;
    in
      if artifact == null
      then {}
      else let
        key = artifact.git-tree-sha1;
        # Julia will try the downloads in order until one succeeds. Nix cannot
        # do this.
        download = builtins.head artifact.download;
        src = fetchurl {
          #inherit name;
          inherit (download) url;
          hash = "sha256:${download.sha256}";
        };
        result =
          stdenv.mkDerivation
          {
            inherit name src;
            version = key;
            # Set this to prevent nix from guessing the source root
            sourceRoot = ".";
            nativeBuildInputs = [zstd];
            installPhase = ''
              mkdir -p $out/${key}/
              mv ./* $out/${key}/
            '';
          };
      in {
        "${key}" = result;
      };
  in
    lib.attrsets.concatMapAttrs remap artifacts;
  #symlinkJoin {
  #  name = "artifacts";
  #  paths = builtins.attrValues mapping;
  #};
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
    artifact-path = "${src}/Artifacts.toml";
    artifacts =
      if lib.pathExists artifact-path
      then collectArtifacts artifact-path
      else {};
    artifacts-depot =
      if artifacts != {}
      then [
        (stdenv.mkDerivation
          {
            name = "artifact-depot";
            inherit src;
            phases = ["unpackPhase" "installPhase"];
            installPhase = ''
              mkdir -p $out/
              ln -s ${symlinkJoin {
                name = "artifacts";
                paths = builtins.attrValues artifacts;
              }} $out/artifacts
            '';
          })
      ]
      else [];
    deps-depot =
      if deps == []
      then []
      else [(mkDepsDepot deps)];
    input-depots = artifacts-depot ++ deps-depot ++ depots;
    # This leaves a trailing : for the system depot
    input-depots-paths = lib.strings.concatMapStrings (s: "${s}:") input-depots;
  in {
    inherit (args) deps;
    inherit (project) name version;
    inherit src artifacts input-depots;
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

    # FIXME: Handle different parent manifest paths
    manifest = builtins.fromTOML (builtins.readFile "${src}/Manifest.toml");
    # Flatten the dependency tree
    flatDeps =
      lib.mapAttrs (
        key: {dependencies, ...}:
          lib.unique (dependencies
            ++ (builtins.concatMap (k:
              if builtins.hasAttr k flatDeps
              then builtins.getAttr k flatDeps
              else [])
            dependencies))
      )
      lock.deps;
    # Trim a parent manifest to contain only relevant parts in a dependency list
    trimManifest = {
      depsNames,
      manifest,
    }:
      pkgs.writers.writeTOML "Manifest.toml"
      (
        lib.setAttr manifest "deps" (lib.filterAttrs (key: _v: true) manifest.deps)
      );

    depToPackage = name: {
      repo,
      rev,
      dependencies,
      ...
    }: let
      depsNames = builtins.getAttr name flatDeps;
    in
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
        depsNames;
        parent-manifest = trimManifest {inherit depsNames manifest;};
      };

    allDeps = builtins.mapAttrs depToPackage lock.deps;
  in
    buildJuliaPackage (args
      // {
        deps = builtins.attrValues allDeps;
      });
}
