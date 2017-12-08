# Check that generated sources match the repo version.
{ pkgs, raptorjit }:
with pkgs; with lib;

# Generated files that are kept in tree.
let generatedFiles =
  "lj_bcdef.h lj_ffdef.h lj_libdef.h lj_recdef.h lj_folddef.h host/buildvm_arch.h";
in

overrideDerivation raptorjit (as:
  {
    checkPhase = ''
      for f in ${generatedFiles}; do
        echo "checking $f.."
        diff -u src/reusevm/$f src/$f
      done
      echo "all files ok"
    '';
    doCheck = true;
  })
