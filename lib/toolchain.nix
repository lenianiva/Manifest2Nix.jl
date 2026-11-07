{
  config,
  lib,
  pkgs,
  fetchzip,
  p7zip,
  stdenv,
  fixDarwinDylibNames,
  autoPatchelfHook,
  ...
}: let
  inherit (stdenv.hostPlatform) system;
in {
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
    # `autoPatchelf` will skip all paths listed in `autoPatchelfExclude`
    # relative to `$out`
    mkDerivation = args @ {
      nativeBuildInputs ? [],
      autoPatchelfExclude ? [],
      ...
    }:
      stdenv.mkDerivation (builtins.removeAttrs args ["autoPatchelfExclude"]
        // {
          nativeBuildInputs =
            nativeBuildInputs
            ++ lib.optional stdenv.hostPlatform.isDarwin fixDarwinDylibNames
            ++ lib.optionals stdenv.hostPlatform.isLinux [autoPatchelfHook stdenv.cc.cc.lib];
        }
        // lib.optionalAttrs (stdenv.hostPlatform.isLinux && autoPatchelfExclude != []) {
          # autoPatchelfHook has no exclusion option, so disable it and run
          # `autoPatchelf` on all non-excluded files instead.
          dontAutoPatchelf = true;
          postFixup =
            (args.postFixup or "")
            + ''
              mapfile -d "" autoPatchelfPaths < <(
                find "$out" \( ${lib.concatMapStringsSep " -o " (p: "-path \"$out/${p}\"") autoPatchelfExclude} \) -prune \
                  -o ! -type d -print0
              )
              autoPatchelf -- "''${autoPatchelfPaths[@]}"
            '';
        });
  in
    # Patch binaries
    mkDerivation {
      name = "julia";
      inherit version;
      src = tarball;
      dontFixup = stdenv.hostPlatform.isDarwin;
      # Patching the bundled stdlib pkgimages invalidates their checksums, so
      # Julia would reject them.
      autoPatchelfExclude = ["share/julia/compiled"];
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
