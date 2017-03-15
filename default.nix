{ pkgs ? (import <nixpkgs> {})
, source ? ./.
, version ? "dev"
}:

with pkgs;
with clangStdenv;

mkDerivation rec {
  name = "raptorjit-${version}";
  inherit version;
  src = lib.cleanSource source;
  enableParallelBuilding = true;
  buildInputs = [ luajit ];
  installPhase = ''
    mkdir -p $out/bin
    cp src/luajit $out/bin/raptorjit
  '';
}
