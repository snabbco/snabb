# Check that generated sources match the repo version.
{ pkgs, raptorjit }:
with pkgs; with lib;

# Generated files that are kept in tree.
let generatedFiles =
  "lj_bcdef.h lj_ffdef.h lj_libdef.h lj_recdef.h lj_folddef.h host/buildvm_arch.h";
in

overrideDerivation raptorjit (as:
  {
    preBuild = ''
      pushd src
      mkdir old
      for f in ${generatedFiles}; do
        cp $f old/
      done
      popd
    '' + as.preBuild;
    checkPhase = ''
      pushd src
      mkdir new
      for f in ${generatedFiles}; do
        cp $f new/
      done
      echo "Checking that in-tree generated VM code is up-to-date..."
      diff -u old new || (echo "Error: Stale generated code"; exit 1)
      popd
    '';
    doCheck = true;
  })
