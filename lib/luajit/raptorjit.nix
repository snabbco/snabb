# raptorjit.nix - compile RaptorJIT with reference toolchain

{ pkgs, source, version }:

with pkgs;
with stdenv;  # Use clang 4.0

mkDerivation rec {
  name = "raptorjit-${version}";
  inherit version;
  src = source;
  buildInputs = [ luajit ];  # LuaJIT to bootstrap DynASM
  installPhase = ''
    mkdir -p $out/bin
    cp src/luajit $out/bin/raptorjit
    mkdir -p $out/lib
    cp src/libluajit.a $out/lib/
  '';

  enableParallelBuilding = true;  # Do 'make -j'
}

