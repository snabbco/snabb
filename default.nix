# default.nix - define the build environment for RaptorJIT
#
# This file can be used by 'nix-build' or 'nix-shell' to create a
# pristine build environment with precisely the expected software in
# $PATH. This makes it possible to build raptorjit in the same way on
# any machine.
#
# See README.md for usage instructions.

{ pkgs ? (import <nixpkgs> {}) # Use default nix distro (for now...)
, source ? ./.
, version ? "dev"
}:

with pkgs;
with clangStdenv;            # Clang instead of GCC

mkDerivation rec {
  name = "raptorjit-${version}";
  inherit version;
  src = lib.cleanSource source;
  buildInputs = [ luajit ];  # LuaJIT to bootstrap DynASM
  installPhase = ''
    mkdir -p $out/bin
    cp src/luajit $out/bin/raptorjit
  '';

  enableParallelBuilding = true;  # Do 'make -j'
}

