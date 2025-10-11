{
  config,
  lib,
  pkgs,
  julia,
  stdenv,
  runCommand,
  symlinkJoin,
  cacert,
  fetchurl,
  zstd,
  writeText,
  ...
}: let
  abridged-version = "${lib.versions.major julia.version}.${lib.versions.minor julia.version}";
in rec {
  # This depot contains a cached version of stdlib
  stdlib-depot =
    runCommand "julia-stdlib" {
      JULIA_PKG_OFFLINE = "true";
      JULIA_PKG_SERVER = "";
      JULIA_SSL_CA_ROOTS_PATH = cacert;
      nativeBuildInputs = [julia];
    } ''
      mkdir -p $out
      JULIA_DEPOT_PATH=$out julia --project -e "import Pkg"
    '';
  # Given a list of Julia packages, pack them into one depot
  mkDepsDepot = deps: let
    # Collect all requisite artifacts
    artifacts = lib.mergeAttrsList (builtins.map (dep: dep.artifacts) deps);
    artifacts-join =
      if artifacts != {}
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
    inherit (p) libc;
    cxxstring_abi = "cxx11";
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
  # Builds a Julia package
  buildJuliaPackage = args @ {
    src,
    depots ? [stdlib-depot],
    deps ? [],
    # Parent manifest file
    root-manifest ? null,
    pre-exec ? "",
    nativeBuildInputs ? [],
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
    pre-exec-command =
      if pre-exec != ""
      then "julia --project ${writeText "pre-exec.jl" pre-exec}"
      else "";
  in {
    inherit (project) name version;
    inherit src deps artifacts input-depots;
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
      nativeBuildInputs = [julia] ++ nativeBuildInputs;
      JULIA_LOAD_PATH = "${load-path}:";
      JULIA_DEPOT_PATH = ".julia:${input-depots-paths}";
      JULIA_SSL_CA_ROOTS_PATH = cacert;
      buildPhase = ''
        mkdir -p .julia

        if [ ! -f Manifest.toml ]; then
          ln -s ${lib.defaultTo "no-root-manifest" root-manifest} Manifest.toml
        fi

        julia --project ${../src/compile.jl}
        ${pre-exec-command}

        mkdir -p $out
        cp -r .julia/compiled/v${abridged-version}/* $out/
      '';
    };
  };
  # Given a built Julia package, create an environment for running code
  createPackageEnv = self @ {
    src,
    name,
    deps,
    load-path,
    ...
  }: let
    packages = [self] ++ self.deps;
    load-path = symlinkJoin {
      name = "${name}-deps";
      paths = builtins.map (dep: dep.load-path) packages;
    };
  in {
    JULIA_LOAD_PATH = "${load-path}:";
    JULIA_DEPOT_PATH = ".julia:${mkDepsDepot packages}:${stdlib-depot}";
    JULIA_SSL_CA_ROOTS_PATH = cacert;
  };
  # Create a Julia package from a dependency file
  buildJuliaPackageWithDeps = {
    src,
    lockFile ? "${src}/Lock.toml",
    manifestFile ? "${src}/Manifest.toml",
    pre-exec ? "",
    nativeBuildInputs ? [],
  }: let
    lock = builtins.fromTOML (builtins.readFile lockFile);

    # FIXME: Handle different parent manifest paths
    project = builtins.fromTOML (builtins.readFile "${src}/Project.toml");
    manifest = builtins.fromTOML (builtins.readFile manifestFile);

    # Flatten the dependency tree
    flatDeps =
      lib.mapAttrs (
        key: {dependencies, ...}:
          lib.uniqueStrings (dependencies
            ++ (builtins.concatMap (k:
              if builtins.hasAttr k flatDeps
              then builtins.getAttr k flatDeps
              else [])
            dependencies))
      )
      lock.deps;
    # Trim a parent manifest to contain only relevant parts in a dependency list
    trimManifest = {
      name,
      depsNames,
      manifest,
    }:
      pkgs.writers.writeTOML "Manifest.toml"
      (
        lib.setAttr manifest "deps" (lib.filterAttrs (key: _v: true) manifest.deps)
        #lib.setAttr manifest "deps" (lib.filterAttrs (key: _v: name == key || lib.lists.elem key depsNames) manifest.deps)
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
        deps = builtins.concatMap (dep:
          if builtins.hasAttr dep allDeps
          then [allDeps.${dep}]
          else [])
        depsNames;
        root-manifest = trimManifest {inherit name depsNames manifest;};
        pre-exec =
          if (name == project.name)
          then pre-exec
          else "";
        inherit nativeBuildInputs;
      };

    allDeps = builtins.mapAttrs depToPackage lock.deps;
  in
    buildJuliaPackage {
      inherit src nativeBuildInputs;
      deps = builtins.attrValues allDeps;
      root-manifest = manifestFile;
    };
}
