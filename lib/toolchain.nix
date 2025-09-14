{
  config,
  lib,
  system,
  pkgs,
  fetchzip,
  stdenv,
  fixDarwinDylibNames,
  autoPatchelfHook,
  ...
}: {
  toolchain-fetch = pkgs.writeShellApplication {
    name = "toolchain-fetch";
    runtimeInputs = with pkgs; [jq coreutils nix];
    text = ''exec ${./toolchain-fetch.sh} "$@"'';
  };
  fetchBinaryToolchain = version: let
    config = (import ./sources.nix).${version}.${system};
    tarball = fetchzip (config
      // {
        name = "julia";
      });
    mkDerivation = args @ {nativeBuildInputs ? [], ...}:
      stdenv.mkDerivation (args
        // {
          phases = ["unpackPhase" "installPhase"];
          nativeBuildInputs =
            nativeBuildInputs
            ++ lib.optional stdenv.isDarwin fixDarwinDylibNames
            ++ lib.optionals stdenv.isLinux [autoPatchelfHook stdenv.cc.cc.lib];
        });
  in
    # Patch binaries
    mkDerivation {
      name = "julia";
      inherit version;
      src = tarball;
      installPhase = ''
        mkdir -p $out/
        cp -r . $out/
      '';
    };
}
