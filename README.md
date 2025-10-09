# Manifest2Nix.jl

A Nix library for creating offline and reproducible Julia builds.

Julia uses a [Ahead-Of-Time](https://docs.julialang.org/en/v1/devdocs/aot/)
compilation system. This means Julia generates native code for functions that it
can compile, while it still needs access to the source code in order to compile
just-in-time. Manifest2Nix is designed to take advantage of this system by
precompiling as much code as possible.

## Usage

``` sh
nix flake new --template git+https://codeberg.org/aniva/Manifest2Nix.jl.git ./minimal
```

### Overlay

Before building any Julia library, there first has to be a Julia toolchain. Generate a toolchain via one of 4 methods:

1. `pkgs` comes with a default `julia` package. It may work or it may not work.
2. Use the provided `self.fromJuliaBin` overlay, which uses the `julia-bin`
   package.
3. Use the `self.fromVersion version` overlay, e.g. `manifest2nix.fromVersion
   "1.11"`.
4. Use the `self.fromManifest path` overlay, which reads the version from a
   `Manifest.toml` file.

### Package Building

Once there is a fixed Julia version available as `pkgs.julia`, create the
`manifest2nix` library by calling the `mkLib` function:

```nix
m2nlib = manifest2nix.mkLib pkgs
```

In `m2nlib`, some functions are available for building Julia packages:

- `manifest2nix`: Tool for creating the `Lock.toml`. To create a `Lock.toml`
  file, execute at the root of a Julia project

```sh
manifest2nix lock --project .
```
- `buildJuliaPackage { src, depots, deps, pre-exec ? "" }`: Builds a Julia package with
  explicit dependencies. If `pre-exec` is not null, it will run in Julia after
  precompilation to force Julia to generate more compiled code.
- `buildJuliaPackageWithDeps { src, lockFile ? "${src}/Lock.toml", pre-exec ? "" }`:
Build a Julia package along with dependencies.
- `stdlib-depot`: A Julia depot containing a precompiled version of Julia
  standard libraries.
- `mkDepsDepot deps`: Given a list of Julia packages, create a depot containing
  all of them.
- `createPackageEnv package`: Given a Julia package, create an environment in which
  Julia can run and see the precompiled version of the given package.

### System Image Caching

## Contributing

Use the provided flake `devShell`, and install pre-commit hooks:

``` sh
pre-commit install --install-hooks
```
