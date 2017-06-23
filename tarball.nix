# Run like this:
#   nix-build ./tarball.nix
# or
#   nix-build --argstr hydraName snabb-lwaftr --argstr version v1.0.0 ./tarball.nix
# and the release tarball will be written to ./result/ . It will contain
# both the sources and the executable, patched to run on Linux LSB systems.
#
# NOTE: Hydra doesn't use the --tags parameter in the "git describe" command (see
# https://github.com/NixOS/hydra/blob/master/src/lib/Hydra/Plugin/GitInput.pm#L148
# ), so lightweight (non-annotated) tags are not found. Always create annotated
# tags with the "git tag" command by using one of the -a, -s or -u options.

{ nixpkgs ? <nixpkgs>
, hydraName ? "snabb"
, src ? ./.
, version ? "dev"
}:

let
  pkgs = import nixpkgs {};
  name = (src:
    if builtins.isAttrs  src then
      # Called from Hydra with "src" as "Git version", get the version from git tags.
      # If the last commit is the tag's one, you'll just get the tag name: "v3.1.7";
      # otherwise you'll also get the number of commits since the last tag, and the
      # shortened commit checksum: "v3.1.7-7-g89747a1".
      "${hydraName}-${src.gitTag}"
    else
      # Called from the command line, the user supplies the version.
      "${hydraName}-${version}") src;
in {
  tarball = pkgs.stdenv.mkDerivation rec {
    inherit name src;

    buildInputs = with pkgs; [ makeWrapper patchelf ];

    postUnpack = ''
      mkdir -p $out/$name
      cp -a $sourceRoot/* $out/$name
    '';

    preBuild = ''
      make clean
    '';

    installPhase = ''
      mv src/snabb $out
    '';

    fixupPhase = ''
      patchelf --shrink-rpath $out/snabb
      patchelf --set-rpath /lib/x86_64-linux-gnu $out/snabb
      patchelf --set-interpreter /lib64/ld-linux-x86-64.so.2 $out/snabb
    '';

    doDist = true;

    distPhase = ''
      cd $out
      tar Jcf $name.tar.xz *
      # Make the tarball available for download through Hydra.
      mkdir -p $out/nix-support
      echo "file tarball $out/$name.tar.xz" >> $out/nix-support/hydra-build-products
    '';
  };
}
