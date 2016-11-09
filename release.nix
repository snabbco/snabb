# Run like this:
#   nix-build /path/to/this/directory/release.nix -A manual
# ... and the files are produced in ./result/

{ pkgs ? (import <nixpkgs> {})
}:

with pkgs;

let
  # see https://github.com/snabbco/snabb/blob/master/src/doc/testing.md
  test_env = fetchurl {
    url = "http://lab1.snabb.co:2008/~max/assets/vm-ubuntu-trusty-14.04-dpdk-snabb.tar.gz";
    sha256 = "0323591i925jhd6wv8h268wc3ildjpa6j57n4p9yg9d6ikwkw06j";
  };
  requiredGetEnv = var:  let
      maybeEnv = builtins.getEnv var;
    in if (maybeEnv != "") then maybeEnv else throw "Please export shell variable ${var}";
in rec {
  manual = import ./src/doc {};
  snabb = import ./default.nix {};
  tests = stdenv.mkDerivation rec {
    name = "snabb-tests";

    src = snabb.src;

    # allow sudo
    __noChroot = true;
    requiredSystemFeatures = [ "lugano" ];

    buildInputs = [ git telnet tmux numactl bc iproute which qemu ];

    buildPhase = ''
      export PATH=$PATH:/var/setuid-wrappers/
      export HOME=$TMPDIR

      # make sure we reuse the snabb built in another derivation
      ln -s ${snabb}/bin/snabb src/snabb
      sed -i 's/testlog snabb/testlog/' src/Makefile

      # setup the environment
      mkdir ~/.test_env
      tar xvzf ${test_env} -C ~/.test_env/
    '';

    doCheck = true;
    checkPhase = ''
      export SNABB_PCI0=${ requiredGetEnv "SNABB_PCI0" }
      export SNABB_PCI_INTEL0=${ requiredGetEnv "SNABB_PCI_INTEL0" }
      export SNABB_PCI_INTEL1=${ requiredGetEnv "SNABB_PCI_INTEL1" }

      # run tests
      sudo -E make test -C src/
    '';

    installPhase = ''
      mkdir -p $out/nix-support

      # keep the logs
      cp src/testlog/* $out/
      for f in $(ls $out/* | sort); do
        echo "file log $f"  >> $out/nix-support/hydra-build-products
      done
    '';
   };
}
