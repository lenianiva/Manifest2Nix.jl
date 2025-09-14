{
  pkgs,
  lib-manifest,
  lib-compile,
  ...
}: let
  minimal-jl = lib-compile.buildJuliaPackage {src = ../templates/minimal;};
  simple-jl = lib-compile.buildJuliaPackageWithDeps {src = ../templates/simple;};
in {
  inherit (lib-compile) stdlib-depot;

  # Ensure all the templates can build
  minimal-jl = minimal-jl.compiled;
  minimal-jl-depot = lib-compile.mkDepsDepot [minimal-jl];
  simple-jl = simple-jl.compiled;
}
