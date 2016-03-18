# nix expression to build the Snabb manual.
#
# Run like this:
#   nix-build /path/to/this/directory
# ... and the files are produced in ./result/

with import <nixpkgs> {};

stdenv.mkDerivation rec {
  name = "snabb-manual";
  src = ./../../.;

  buildInputs = [ ditaa pandoc git
   (texlive.combine {
      inherit (texlive) scheme-small luatex luatexbase sectsty titlesec cprotect bigfoot titling droid;
    })
  ];

  patchPhase = ''
    patchShebangs src/doc src/scripts
  '';

  buildPhase = ''
    # needed for font cache
    export TEXMFCACHE=`pwd`

    make book -C src
  '';

  installPhase = ''
    mkdir -p $out/share/doc
    cp src/doc/snabbswitch.* $out/share/doc
    # Give manual to Hydra
    mkdir -p $out/nix-support
    echo "doc-pdf manual $out/share/doc/snabbswitch.pdf" \
      >> $out/nix-support/hydra-build-products;
  '';
}
