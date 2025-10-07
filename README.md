# Manifest2Nix.jl

A Nix library for creating reproducible Julia builds.

## Usage

### Overlay

...

### Package Building

Once there is a fixed Julia version available as `pkgs.julia`, create the
`manifest2nix` library by calling the `mkLib` function:

```nix
m2nlib = pkgs.callPackage manifest2nix.mkLib {}
```

In `m2nlib`, some functions are available for building Julia packages:

- `manifest2nix`
- `buildJuliaPackage { src, depots, deps }`: Builds a Julia package with
  explicit dependencies.
- `buildJuliaPackageWithDeps { src, lockFile ? "${src}/Lock.toml" }`: Build a
  Julia package along with dependencies.
- `stdlib-depot`: A Julia depot containing a precompiled version of Julia
  standard libraries.
- `mkDepsDepot deps`: Given a list of Julia packages, create a depot containing
  all of them.
- `createJuliaEnv package`: Given a Julia package, create a environment in which
  Julia can run and see the precompiled version of the given package.

### System Image Caching

## Contributing

Use the provided flake `devShell`, and install pre-commit hooks:

``` sh
pre-commit install --install-hooks
```
