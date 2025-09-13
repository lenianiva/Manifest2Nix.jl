{
  pkgs,
  lib-manifest,
  lib-compile,
  ...
}: rec {
  inherit (lib-compile) stdlib-depot;

  # Ensure all the templates can build
  minimal-jl = lib-compile.buildJuliaPackage {src = ../templates/minimal;};
  minimal-jl-depot = lib-compile.mkDepsDepot [minimal-jl];
  simple-jl = lib-compile.buildJuliaPackageWithDeps {src = ../templates/simple;};
}
