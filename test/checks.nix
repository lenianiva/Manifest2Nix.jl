{
  pkgs,
  lib-manifest,
  lib-compile,
  ...
}: let
  minimal-jl = lib-compile.buildJuliaPackage {src = ../templates/minimal;};
  simple-jl = lib-compile.buildJuliaPackageWithDeps {src = ../templates/simple;};
  artefact-jl = lib-compile.buildJuliaPackageWithDeps {src = ./artefact;};

  # Integration tests
  images-jl = lib-compile.buildJuliaPackageWithDeps {src = ./images;};
in {
  inherit (lib-compile) stdlib-depot;

  # Ensure all the templates can build
  minimal-jl = minimal-jl.compiled;
  minimal-jl-depot = lib-compile.mkDepsDepot [minimal-jl];
  simple-jl = simple-jl.compiled;

  artefact-jl = artefact-jl.compiled;
  artefact-jl-artefact = lib-compile.generateArtifactFile "${./artefact}/Artifacts.toml";
  images-jl = images-jl.compiled;
}
