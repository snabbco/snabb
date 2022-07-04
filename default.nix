# Run like this:
#   nix-build /path/to/this/directory
# ... and the files are produced in ./result/bin/snabb

{ pkgs ? (import <nixpkgs> {})
, source ? ./.
, version ? "dev"
, supportOpenstack ? true
}:

with pkgs;

stdenv.mkDerivation rec {
  name = "snabb-${version}";
  inherit version;
  src = lib.cleanSource source;

  buildInputs = [ makeWrapper ];

  patchPhase = ''
    patchShebangs .
    
  '' + lib.optionalString supportOpenstack ''
    # We need a way to pass $PATH to the scripts
    sed -i '2iexport PATH=${git}/bin:${mariadb}/bin:${which}/bin:${procps}/bin:${coreutils}/bin' src/program/snabbnfv/neutron_sync_master/neutron_sync_master.sh.inc
    sed -i '2iexport PATH=${git}/bin:${coreutils}/bin:${diffutils}/bin:${nettools}/bin' src/program/snabbnfv/neutron_sync_agent/neutron_sync_agent.sh.inc
  '';

  preBuild = ''
    make clean
  '';

  installPhase = ''
    mkdir -p $out/bin
    cp src/snabb $out/bin
  '';

  enableParallelBuilding = true;
}
