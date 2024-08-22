# Run like this:
#   nix-build /path/to/this/directory
# ... and the files are produced in ./result/bin/snabb

{ pkgs ? (import <nixpkgs> {})
, source ? ./.
, version ? "dev"
}:

with pkgs;

stdenv.mkDerivation rec {
  name = "snabb-${version}";
  inherit version;
  src = lib.cleanSource source;

  buildInputs = [ makeWrapper ];

  patchPhase = ''
    patchShebangs .
    
  '';

  preBuild = ''
    make clean
  '';

  installPhase = ''
    mkdir -p $out/bin
    cp src/snabb $out/bin
  '';

  enableParallelBuilding = true;
}
