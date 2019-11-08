# Nix expression for CI builds via hercules-ci.com.
# Tests run on Snabb owned/operated hardware.
# Currently simple example to compile Snabb.

with import (builtins.fetchGit {
  name = "nixpkgs-release-19.09";
  url = https://github.com/nixos/nixpkgs/;
  rev = "23af4044501b161a23fea47f8ab0b6f0efca5a6f";
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
