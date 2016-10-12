# Run like this:
#   nix-build /path/to/this/directory
# ... and the files are produced in ./result/

{ pkgs ? (import <nixpkgs> {})
}:

with pkgs;

stdenv.mkDerivation rec {
  name = "snabb-manual";
  src = ../../.;

  buildInputs = [ ditaa pandoc git
   (texlive.combine {
      inherit (texlive) scheme-small luatex luatexbase sectsty titlesec cprotect bigfoot titling droid collection-luatex;
   })
  ];

  patchPhase = ''
    patchShebangs src/doc
    patchShebangs src/scripts
  '';

  buildPhase = ''
    # needed for font cache
    export TEXMFCACHE=`pwd`

    make book -C src
  '';

  installPhase = ''
    mkdir -p $out/share/doc
    cp src/obj/doc/snabb.* $out/share/doc

    # Give manual to Hydra
    mkdir -p $out/nix-support
    echo "doc-pdf manual $out/share/doc/snabb.pdf"  >> $out/nix-support/hydra-build-products;
    echo "doc HTML $out/share/doc/snabb.html"  >> $out/nix-support/hydra-build-products;
    echo "doc epub $out/share/doc/snabb.epub"  >> $out/nix-support/hydra-build-products;
    echo "doc markdown $out/share/doc/snabb.markdown"  >> $out/nix-support/hydra-build-products;
  '';
}
