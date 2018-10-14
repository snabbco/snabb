# raptorjit.nix - compile RaptorJIT with reference toolchain

{ pkgs, source, version }:

with pkgs;
with stdenv;  # Use clang 4.0

mkDerivation rec {
  name = "raptorjit-${version}";
  inherit version;
  src = source;
  buildInputs = [ luajit ];  # LuaJIT to bootstrap DynASM
  dontStrip = true;
  patchPhase = ''
    substituteInPlace Makefile --replace "/usr/local" "$out"
  '';
  configurePhase = false;
  installPhase = ''
    make install PREFIX="$out"
  '';

  enableParallelBuilding = true;  # Do 'make -j'
}

