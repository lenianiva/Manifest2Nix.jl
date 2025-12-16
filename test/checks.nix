{
  pkgs,
  lib-compile,
}: let
  inherit (pkgs) julia;
  minimal-jl = lib-compile.buildJuliaPackage {src = ../templates/minimal;};
  simple-jl = lib-compile.buildJuliaPackageWithDeps {src = ../templates/simple;};
  simple-direct-jl = lib-compile.buildJuliaPackageWithDeps {
    src = ../templates/simple;
    precompileDeps = false;
  };
  artefact-jl = lib-compile.buildJuliaPackageWithDeps {src = ./artefact;};
  override-jl-direct = lib-compile.buildJuliaPackageWithDeps {
    src = ./override;
    override = {Artefact = artefact-jl;};
    env = {Override = {OVERRIDE_MYSTERY = "mystery2";};};
  };
  override-jl-src = lib-compile.buildJuliaPackageWithDeps {
    src = ./override;
    override = {Artefact = ./artefact;};
    env = {Override = {OVERRIDE_MYSTERY = "mystery2";};};
  };
  # Integration tests
  version-dir = ../version + "/${pkgs.lib.versions.major julia.version}.${pkgs.lib.versions.minor julia.version}";
  self-jl = lib-compile.buildJuliaPackageWithDeps {
    src = ../.;
    manifestFile = "${version-dir}/Manifest.toml";
    lockFile = "${version-dir}/Lock.toml";
  };
  images-jl = lib-compile.buildJuliaPackageWithDeps {src = ./images;};
  graphnn-jl = lib-compile.buildJuliaPackageWithDeps {src = ./graphnn;};
in {
  inherit (pkgs) julia;
  julia-version = pkgs.testers.testVersion {package = julia;};
  inherit (lib-compile) stdlibDepot;

  # Ensure all the templates can build
  minimal-jl = minimal-jl.compiled;

  minimal-jl-exec = pkgs.testers.testEqualContents {
    assertion = "call function in package";
    expected = pkgs.writeText "expected" "Minimal";
    actual =
      pkgs.runCommand "actual"
      (lib-compile.createEnv {
        package = minimal-jl;
        workingDepot = ".julia";
      })
      ''
        ${julia}/bin/julia -e "import Minimal; Minimal.mystery();" > $out
      '';
  };
  minimal-jl-depot = lib-compile.mkDepsDepot {
    name = "mini";
    deps = [minimal-jl];
  };
  simple-jl = simple-jl.compiled;
  simple-direct-jl = simple-jl.compiled;
  simple-jl-script = let
    script = builtins.path {
      path = ../templates/simple/script/normal.jl;
      name = "normal.jl";
    };
    workingDepot = ".julia";
  in
    pkgs.testers.testEqualContents {
      assertion = "Execute script";
      expected = pkgs.writeText "expected" "1.0480426577669817";
      actual =
        pkgs.runCommand "actual"
        (lib-compile.createEnv {
          package = simple-jl;
          inherit workingDepot;
        })
        ''
          mkdir ${workingDepot}
          ${julia}/bin/julia ${script} > $out
          ls .julia
          if [ ! -z "$( ls -A ${workingDepot} )" ]; then
            exit 1
          fi
        '';
    };

  artefact-jl = artefact-jl.compiled;
  override-jl-direct = override-jl-direct.compiled;
  override-jl-src = override-jl-src.compiled;

  self-jl = self-jl.compiled;
  images-jl = images-jl.compiled;
  graphnn-jl = graphnn-jl.compiled;
}
