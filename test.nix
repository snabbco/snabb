{ pkgs, raptorjit, source, name, args }:

pkgs.stdenv.mkDerivation {
  name = "test-${name}";
  src = source;
  buildInputs = [ raptorjit ];
  phases = "unpackPhase buildPhase";
  buildPhase = ''
    mkdir $out
    cd testsuite/test
    echo "Running testsuite with ${args} and output to $out/log.txt"
    raptorjit ${args} test.lua 2>&1 > $out/log.txt
    result=$?
    echo -n "*** TEST RESULTS (${args}): "
    tail -1 $out/log.txt
    exit $result
  '';
}

