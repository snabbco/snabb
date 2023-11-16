# Test that libraptorjit can be dynamically linked.
{ pkgs, raptorjit, ... }:
with pkgs; with stdenv;

# Trivial C program to dynamically link with raptorjit.
let csrc = writeScript "test.c" ''
  #include <stdio.h>
  int main(int argc, char **argv) {
    printf("dynamically linked executable worked ok!\n");
    return 0;
  }
''; in

runCommand "test-libraptorjit" { nativeBuildInputs = [ gcc raptorjit ]; } ''
  gcc -lraptorjit-5.1 -o ./test ${csrc}
  ./test | tee $out
''

