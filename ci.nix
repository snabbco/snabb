# Nix expression for CI builds via hercules-ci.com.
# Tests run on Snabb owned/operated hardware.
# Currently simple example to compile Snabb.

with import (builtins.fetchTarball {
  name = "nixpkgs-release-19.09";
  url = https://github.com/nixos/nixpkgs/archive/d628521d0b79df8882980a897f1e91fe78c29660.tar.gz;
  sha256 = "0rdhng8wig4bbmq8r8fcq55zk8nac7527p0qk5whyd1zh9xffiyv";
}) {};
{
  build = stdenv.mkDerivation {
    name = "snabb";
    src = ./.;
    installPhase = ''
      install -D src/snabb $out/bin/snabb
    '';
  };
}
