{
  pkgs,
  lib-manifest,
  lib-compile,
  ...
}: let
  minimal-jl = lib-compile.buildJuliaPackage {src = ../templates/minimal;};
  simple-jl = lib-compile.buildJuliaPackageWithDeps {src = ../templates/simple;};
  artefact-jl = lib-compile.buildJuliaPackageWithDeps {src = ./artefact;};
in {
  inherit (lib-compile) stdlib-depot;

  # Ensure all the templates can build
  minimal-jl = minimal-jl.compiled;
  minimal-jl-depot = lib-compile.mkDepsDepot [minimal-jl];
  simple-jl = simple-jl.compiled;

  # Check individual cases
  artefact-jl = artefact-jl.compiled;
}
