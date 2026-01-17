{
  config,
  lib,
  system,
  pkgs,
  fetchzip,
  p7zip,
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
      dontFixup = stdenv.isDarwin;
      installPhase = ''
        runHook preInstall
        mkdir -p $out/
        mv ./* $out/
        rm -f $out/libexec/julia/7z
        ln -s ${p7zip}/bin/7z $out/libexec/julia/7z
        runHook postInstall
      '';
    };
}
