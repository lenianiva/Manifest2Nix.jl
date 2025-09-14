rec {
  # Use the `julia-bin` package as toolchain
  fromJuliaBin = final: prev @ {julia-bin, ...}: prev // {julia = julia-bin;};
  fromVersion = version: final: prev:
    prev
    // {
      julia = (prev.callPackage ./toolchain.nix {}).fetchBinaryToolchain version;
    };
  fromManifest = manifest-path: let
    manifest = builtins.fromTOML (builtins.readFile manifest-path);
  in
    fromVersion manifest.julia_version;
}
