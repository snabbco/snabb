import (builtins.fetchTarball {
  name = "nixos-unstable-2023-08-17";
  url = "https://github.com/NixOS/nixpkgs/archive/caac0eb6bdcad0b32cb2522e03e4002c8975c62e.zip";
  # Hash obtained using `nix-prefetch-url --unpack <url>`
  sha256 = "0vajy7k2jjn1xrhfvqip9c77jvm22pr1y3h8qw4460dz70a4yqy6";
})