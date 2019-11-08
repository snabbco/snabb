# Nix expression for CI builds via hercules-ci.com.
# Tests run on Snabb owner/operated hardware.
# Currently simple example to compile Snabb.

with import <nixpkgs> {};
{
  build = stdenv.mkDerivation {
    name = "snabb";
    src = ./.;
    installPhase = ''
      install -D src/snabb $out/bin/snabb
    '';
  };
}
