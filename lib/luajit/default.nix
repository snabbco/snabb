# default.nix - define the build environment for RaptorJIT
#
# This file can be used by 'nix-build' or 'nix-shell' to create a
# pristine build environment with precisely the expected software in
# $PATH. This makes it possible to build raptorjit in the same way on
# any machine.
#
# See README.md for usage instructions.

{ pkgs ? (import ./pkgs.nix) {}
, source ? pkgs.lib.cleanSource ./.
, version ? "dev"
, check ? false }:

let
  callPackage = (pkgs.lib.callPackageWith { inherit pkgs source version; });
  raptorjit = (callPackage ./raptorjit.nix {});
  test = name: args: (callPackage ./test.nix { inherit raptorjit name args; });
  check-generated-code = (callPackage ./check-generated-code.nix { inherit raptorjit; });
in

# Build RaptorJIT and run mulitple test suites.
{
  raptorjit  = raptorjit;
  test-O3    = test "O3"    "-O3";
  test-O2    = test "O2"    "-O2";
  test-O1    = test "O1"    "-O1";
  test-nojit = test "nojit" "-joff";
} //
(if check then { inherit check-generated-code; } else {})

