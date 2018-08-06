# raptorjit.nix - compile RaptorJIT with reference toolchain

{ pkgs, source, version }:

with pkgs;
with stdenv;

mkDerivation rec {
  name = "raptorjit-${version}";
  inherit version;
  src = source;
  buildInputs = [ luajit ];  # LuaJIT to bootstrap DynASM
  dontStrip = true;
  installPhase = ''
    install -D src/raptorjit $out/bin/raptorjit
    install -D src/lj_dwarf.dwo $out/lib/raptorjit.dwo
  '';

  enableParallelBuilding = true;  # Do 'make -j'
}

