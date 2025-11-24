{
  config,
  lib,
  pkgs,
  julia,
  stdenv,
  runCommand,
  symlinkJoin,
  cacert,
  fetchgit,
  fetchurl,
  zstd,
  writeText,
  ...
}: let
  abridged-version = "${lib.versions.major julia.version}.${lib.versions.minor julia.version}";
  JULIA_SSL_CA_ROOTS_PATH = "${cacert}/etc/ssl/certs/ca-bundle.crt";
in rec {
  # This depot contains a cached version of stdlib
  stdlib-depot =
    runCommand "julia-stdlib" {
      JULIA_PKG_OFFLINE = "true";
      JULIA_PKG_SERVER = "";
      inherit JULIA_SSL_CA_ROOTS_PATH;
      nativeBuildInputs = [julia];
    } ''
      mkdir -p $out
      JULIA_DEPOT_PATH=$out julia --project -e "import Pkg"
    '';
  # Given a list of Julia packages, pack them into one depot
  mkDepsDepot = {
    name,
    deps,
  }: let
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
      name = "${name}-deps";
      src = symlinkJoin {
        name = "${name}-compiled";
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
    libgfortran_version = "5.0.0";
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
    name ? null,
    version ? null,
    uuid ? "",
    src,
    depots ? [stdlib-depot],
    deps ? [],
    # Parent manifest file
    root-manifest ? null,
    pre-exec ? "",
    nativeBuildInputs ? [],
    env ? {},
  }: let
    name = args.name or (builtins.fromTOML (builtins.readFile "${src}/Project.toml")).name;
    version = args.version or (builtins.fromTOML (builtins.readFile "${src}/Project.toml")).version;
    load-path = symlinkJoin {
      name = "${name}-load-path";
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
      else [(mkDepsDepot {inherit name deps;})];
    input-depots = artifacts-depot ++ deps-depot ++ depots;
    # This leaves a trailing : for the system depot
    input-depots-paths = lib.strings.concatMapStrings (s: "${s}:") input-depots;
    pre-exec-command =
      if pre-exec != ""
      then "julia --project ${writeText "pre-exec.jl" pre-exec}"
      else "";
    # A compatibility shim for Julia packages without a `Project.toml` file.
    project-toml =
      pkgs.writers.writeTOML "Project.toml"
      {
        inherit name version uuid;
      };
  in {
    inherit name version;
    inherit src deps artifacts input-depots;
    # A special derivation for creating load paths
    load-path = stdenv.mkDerivation rec {
      inherit name;
      inherit src;
      phases = ["unpackPhase" "installPhase"];
      installPhase = ''
        if [ -f Project.toml ] || [ -f JuliaProject.toml ]; then
          mkdir -p $out
          ln -s ${src} $out/${name}
        else
          mkdir -p $out/${name}
          ln -s ${src}/* $out/${name}/
          ln -s ${project-toml} $out/${name}/Project.toml
        fi
      '';
    };
    compiled = stdenv.mkDerivation ({
        inherit (args) src;
        inherit name version;
        dontInstall = true;
        nativeBuildInputs = [julia] ++ nativeBuildInputs;
        JULIA_LOAD_PATH = "${load-path}:";
        JULIA_DEPOT_PATH = ".julia:${input-depots-paths}";
        inherit JULIA_SSL_CA_ROOTS_PATH;
        buildPhase = ''
          mkdir -p .julia

          echo "Load Path: $JULIA_LOAD_PATH"

          if [ ! -f Manifest.toml ]; then
            ln -s ${lib.defaultTo "no-root-manifest" root-manifest} Manifest.toml
          fi

          mkdir -p $out

          if [ -f Project.toml ]; then
            julia --project ${../src/compile.jl}
            ${pre-exec-command}

            mv .julia/compiled/v${abridged-version}/* $out/
          fi
        '';
      }
      // env);
  };
  # Given a built Julia package, create an environment for running code
  createEnv = {
    name ? null,
    package,
    workingDepot ? "",
  }: let
    inherit (package) deps name;
    packages = [package] ++ deps;
    load-path = symlinkJoin {
      name = "${name}-load-path";
      paths = builtins.map (dep: dep.load-path) packages;
    };
  in {
    JULIA_LOAD_PATH = "${load-path}:";
    JULIA_DEPOT_PATH = "${workingDepot}:${mkDepsDepot {
      inherit name;
      deps = packages;
    }}:${stdlib-depot}";
    inherit JULIA_SSL_CA_ROOTS_PATH;
  };
  # Create a Julia package from a dependency file
  buildJuliaPackageWithDeps = {
    src,
    lockFile ? "${src}/Lock.toml",
    manifestFile ? "${src}/Manifest.toml",
    pre-exec ? "",
    nativeBuildInputs ? [],
    override ? {},
    env ? {},
  }: let
    lock = builtins.fromTOML (builtins.readFile lockFile);

    # FIXME: Handle different parent manifest paths
    project = builtins.fromTOML (builtins.readFile "${src}/Project.toml");
    manifest = builtins.fromTOML (builtins.readFile manifestFile);

    # NOTE: Julia manifest uses arrays of tables [[...]], but each key only has
    # one value.
    manifestDeps = builtins.mapAttrs (_k: v: builtins.head v) manifest.deps;

    isStdLib = attrset: (!builtins.hasAttr "path" attrset) && (!builtins.hasAttr "git-tree-sha1" attrset);
    convertWeakDeps = v:
      if builtins.isAttrs v
      then builtins.attrNames v
      else v;

    # Flatten the dependency tree
    flatDeps =
      lib.mapAttrs (
        key: {
          deps ? [],
          weakdeps ? [],
          ...
        }: let
          d = deps ++ (convertWeakDeps weakdeps);
        in
          lib.lists.unique (d
            ++ (builtins.concatMap (
                k: flatDeps.${k} or []
              )
              d))
      )
      manifestDeps;

    trimManifest = {
      name,
      depsNames,
      manifest,
    }:
      pkgs.writers.writeTOML "Manifest.toml"
      (
        lib.setAttr manifest "deps" (lib.filterAttrs (key: _v: name == key || lib.lists.elem key depsNames) manifest.deps)
      );

    depToPackage = name: {
      version,
      repo,
      rev,
      hash,
      uuid,
      subdir ? "",
      src ? null, # Optionally override the source path to ignore repo and rev
      ...
    }: let
      depsNames = builtins.getAttr name flatDeps;
      fetched = pkgs.fetchgit {
        url = repo;
        inherit rev hash;
      };
    in
      buildJuliaPackage {
        inherit name uuid version env;
        src =
          if builtins.isNull src
          then "${fetched}/${subdir}"
          else src;
        deps =
          builtins.concatMap (
            dep:
              lib.optional
              (builtins.hasAttr dep allDeps)
              allDeps.${dep}
          )
          depsNames;
        root-manifest = trimManifest {inherit name depsNames manifest;};
        pre-exec =
          if (name == project.name)
          then pre-exec
          else "";
        inherit nativeBuildInputs;
      };

    allDeps =
      builtins.mapAttrs (name: info:
        if builtins.hasAttr name override
        then
          (let
            o = builtins.getAttr name override;
          in
            if builtins.isAttrs o
            then o
            else depToPackage name (info // {src = o;}))
        else depToPackage name info)
      # Filter out stdlib repos, since they do not need to be built
      (lib.filterAttrs (k: _v: !(isStdLib manifestDeps.${k})) lock.deps);
  in
    buildJuliaPackage {
      inherit src nativeBuildInputs;
      deps = builtins.attrValues allDeps;
      root-manifest = manifestFile;
    };
}
