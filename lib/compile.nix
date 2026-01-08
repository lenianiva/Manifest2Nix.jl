{
  config,
  lib,
  julia,
  stdenv,
  runCommand,
  symlinkJoin,
  cacert,
  fetchgit,
  fetchurl,
  zstd,
  writers,
  writeText,
  ...
}: let
  abridged-version = "${lib.versions.major julia.version}.${lib.versions.minor julia.version}";
  JULIA_SSL_CA_ROOTS_PATH = "${cacert}/etc/ssl/certs/ca-bundle.crt";
in rec {
  # This depot contains a cached version of stdlib
  stdlibDepot =
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
    artifacts = lib.mergeAttrsList (builtins.map (dep: dep.artifacts or {}) deps);
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
        paths = builtins.map (dep: lib.addErrorContext "While compiling ${dep.name}" dep.compiled) (builtins.filter (dep: dep.compiled != null) deps);
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
    llvm_version = "18";
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
    depots ? [stdlibDepot],
    deps ? [],
    # Override the manifest file. This is necessary if the project doesn't come
    # with its own manifest.
    manifest ? null,
    pre-exec ? "",
    nativeBuildInputs ? [],
    env ? {},
    # If set to false, skip precompilation. `.compile` will be `null`
    precompile ? true,
  }: let
    name = args.name or (builtins.fromTOML (builtins.readFile "${src}/Project.toml")).name;
    version = args.version or (builtins.fromTOML (builtins.readFile "${src}/Project.toml")).version;
    load-path = symlinkJoin {
      name = "${name}-load-path";
      paths = builtins.map (dep: dep.load-path) deps;
    };
    artifacts =
      if lib.pathExists "${src}/Artifacts.toml"
      then collectArtifacts "${src}/Artifacts.toml"
      else
        (
          if lib.pathExists "${src}/JuliaArtifacts.toml"
          then collectArtifacts "${src}/JuliaArtifacts.toml"
          else {}
        );
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
      writers.writeTOML "Project.toml"
      {
        inherit name version uuid;
        deps = builtins.listToAttrs (builtins.map (dep: {
            inherit (dep) name;
            value = dep.uuid;
          })
          deps);
      };
  in {
    inherit name version uuid src deps artifacts input-depots;
    # A special derivation for creating load paths
    load-path = stdenv.mkDerivation rec {
      inherit name src;
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
    compiled =
      if precompile
      then
        stdenv.mkDerivation ({
            inherit (args) src;
            inherit name version;
            dontInstall = true;
            nativeBuildInputs = [julia] ++ nativeBuildInputs;
            JULIA_LOAD_PATH = "${load-path}:";
            JULIA_DEPOT_PATH = ".julia:${input-depots-paths}";
            inherit JULIA_SSL_CA_ROOTS_PATH;
            configurePhase =
              if manifest != null
              then ''
                rm -f Manifest.toml JuliaManifest.toml
                ln -s ${manifest} Manifest.toml
                cat Manifest.toml
              ''
              else null;
            buildPhase = ''
              mkdir -p $out

              echo "Load Path: $JULIA_LOAD_PATH"
              echo "Depot Path: $JULIA_DEPOT_PATH"

              if [ -f Project.toml ] || [ -f JuliaProject.toml ]; then
                mkdir -p .julia
                julia --project ${../src/compile.jl}
                ${pre-exec-command}

                mv .julia/compiled/v${abridged-version}/* $out/
              fi
            '';
          }
          // env)
      else null;
  };
  # Given a built Julia package, create an environment for running code
  createEnv = {
    name ? null,
    package,
    workingDepot ? "",
    withDepot ? true,
  }: let
    inherit (package) deps name;
    packages = [package] ++ deps;
    load-path = symlinkJoin {
      name = "${name}-load-path";
      paths = builtins.map (dep: dep.load-path) packages;
    };
  in
    {
      JULIA_LOAD_PATH = "${load-path}:";
      inherit JULIA_SSL_CA_ROOTS_PATH;
    }
    // lib.attrsets.optionalAttrs withDepot {
      JULIA_DEPOT_PATH = "${workingDepot}:${mkDepsDepot {
        inherit name;
        deps = packages;
      }}:${stdlibDepot}";
    };
  # Create a Julia package from a dependency file
  buildJuliaPackageWithDeps = {
    src,
    name ? null,
    lockFile ? "${src}/Lock.toml",
    manifestFile ? "${src}/Manifest.toml",
    pre-exec ? "",
    nativeBuildInputs ? [],
    override ? {},
    cpuTarget ? null,
    # Per package environment override
    env ? {},
    # If set to false, skip dependency precompilation
    precompileDeps ? true,
    precompile ? true,
  }: let
    lock = builtins.fromTOML (builtins.readFile lockFile);

    project = builtins.fromTOML (builtins.readFile "${src}/Project.toml");
    manifest = builtins.fromTOML (builtins.readFile manifestFile);

    # NOTE: Julia manifest's `deps` attribute uses arrays of tables [[...]], but
    # each key only has one value.
    manifestDeps = builtins.mapAttrs (_k: v: builtins.head v) manifest.deps;

    isStdLib = attrset: (!builtins.hasAttr "path" attrset) && (!builtins.hasAttr "git-tree-sha1" attrset);

    # Flat dependency tree
    flatDeps =
      lib.mapAttrs (
        key: {deps ? [], ...}:
          lib.lists.remove key (lib.lists.unique (deps
            ++ (builtins.concatMap (
                k: flatDeps.${k} or []
              )
              deps)))
      )
      manifestDeps;

    commonEnv = {JULIA_CPU_TARGET = cpuTarget;};
    combinedEnvOf = name: (lib.mergeAttrsList (builtins.map (name: env.${name} or {}) ([name] ++ flatDeps.${name}))) // commonEnv;

    # Generates a shortened manifest which contains all dependencies of a particular package
    trimManifest = {
      name,
      depsNames,
      manifest,
    }: let
      inDep = x: (builtins.elem x depsNames) || (builtins.hasAttr x manifestDeps && isStdLib manifestDeps.${x});
      # Filter weakdeps
      filterWeaks = dep: let
        weakdeps =
          if builtins.isAttrs (dep.weakdeps or [])
          then lib.filterAttrs (depName: _depUUID: inDep depName) (dep.weakdeps or [])
          else builtins.filter inDep (dep.weakdeps or []);
        extensions = lib.filterAttrs (_ext: d:
          if builtins.isList d
          then builtins.all inDep d
          else inDep d) (dep.extensions or {});
      in
        (
          lib.optionalAttrs (weakdeps != [] && weakdeps != {}) {
            inherit weakdeps;
          }
        )
        // (
          lib.optionalAttrs (extensions != {}) {
            inherit extensions;
          }
        )
        // (builtins.removeAttrs dep ["weakdeps" "extensions"]);
      mapDep = depName:
        builtins.map (dep:
          if builtins.hasAttr depName override
          then
            lib.setAttr (filterWeaks dep) "path"
            "${
              if builtins.isAttrs override.${depName}
              then override.${depName}.src
              else override.${depName}
            }"
          else filterWeaks dep);
      deps = builtins.mapAttrs mapDep (lib.filterAttrs (key: _v: inDep key) manifest.deps);
    in
      writers.writeTOML "Manifest.toml"
      (
        lib.setAttr manifest "deps" deps
      );

    # Convert one dependency in the lock file to a Julia package
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
      fetched = fetchgit {
        url = repo;
        inherit rev hash;
      };
    in
      buildJuliaPackage {
        inherit name uuid version;
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
        manifest = trimManifest {inherit name depsNames manifest;};
        env = combinedEnvOf name;
        precompile = precompileDeps;
      };

    allDeps = builtins.seq flatDeps (
      builtins.mapAttrs (name: info:
        if builtins.hasAttr name override
        then
          (let
            o = override.${name};
          in
            if builtins.isAttrs o
            then o
            else depToPackage name (info // {src = o;}))
        else depToPackage name info)
      # Filter out stdlib repos, since they do not need to be built
      (lib.filterAttrs (k: _v: !(isStdLib manifestDeps.${k})) lock.deps)
    );
  in
    buildJuliaPackage {
      env = (lib.mergeAttrsList (builtins.map (name: env.${name} or {}) (builtins.attrNames manifestDeps))) // commonEnv;
      inherit src nativeBuildInputs pre-exec precompile;
      deps = builtins.attrValues allDeps;
      manifest = trimManifest {
        name =
          if name == null
          then project.name
          else name;
        depsNames = builtins.attrNames manifestDeps;
        inherit manifest;
      };
    };
}
