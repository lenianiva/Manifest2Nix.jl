{
  pkgs,
  lib-compile,
}: let
  inherit (pkgs) julia;
  minimal-jl = lib-compile.buildJuliaPackage {src = ../templates/minimal;};
  simple-jl = lib-compile.buildJuliaPackageWithDeps {src = ../templates/simple;};
  artefact-jl = lib-compile.buildJuliaPackageWithDeps {src = ./artefact;};
  override-jl = lib-compile.buildJuliaPackageWithDeps {
    src = ./override;
    override = {Artefact = artefact-jl;};
  };
  # Integration tests
  version-dir = ../version + "/${pkgs.lib.versions.major julia.version}.${pkgs.lib.versions.minor julia.version}";
  self-jl = lib-compile.buildJuliaPackageWithDeps {
    src = ../.;
    manifestFile = "${version-dir}/Manifest.toml";
    lockFile = "${version-dir}/Lock.toml";
  };
  images-jl = lib-compile.buildJuliaPackageWithDeps {src = ./images;};
in {
  inherit (pkgs) julia;
  julia-version = pkgs.testers.testVersion {package = julia;};
  inherit (lib-compile) stdlib-depot;

  # Ensure all the templates can build
  minimal-jl = minimal-jl.compiled;

  minimal-jl-exec = pkgs.testers.testEqualContents {
    assertion = "call function in package";
    expected = pkgs.writeText "expected" "Minimal";
    actual =
      pkgs.runCommand "actual"
      (lib-compile.createPackageEnv minimal-jl)
      ''
        ${julia}/bin/julia -e "import Minimal; Minimal.mystery();" > $out
      '';
  };
  minimal-jl-depot = lib-compile.mkDepsDepot [minimal-jl];
  simple-jl = simple-jl.compiled;

  artefact-jl = artefact-jl.compiled;
  override-jl = override-jl.compiled;

  self-jl = self-jl.compiled;
  images-jl = images-jl.compiled;
}
