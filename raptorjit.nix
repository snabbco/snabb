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
  patchPhase = ''
    substituteInPlace Makefile --replace "/usr/local" "$out"
  '';
  configurePhase = false;
  installPhase = ''
    make install PREFIX="$out"
  '';
  # Simple inventory test.
  installCheckPhase = ''
    for file in bin/raptorjit lib/libraptorjit-5.1.so \
                lib/pkgconfig/raptorjit.pc; do
      echo "Checking for $file"
      test -f $out/$file
    done
  '';
  doInstallCheck = true;
  enableParallelBuilding = true;  # Do 'make -j'
}

