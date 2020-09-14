#!/usr/bin/env nix-shell
#!nix-shell -i bash -p curl gnugrep gnused gawk

# See https://github.com/NixOS/nixpkgs/pull/97938. This can be deleted when that's merged.

set -eou pipefail

ROOT="$(dirname "$(readlink -f "$0")")"
if [ ! -f "$ROOT/vscodium.nix" ]; then
  echo "ERROR: cannot find vscodium.nix in $ROOT"
  exit 1
fi

# VSCodium

VSCODIUM_VER=$(curl -Ls -w %{url_effective} -o /dev/null https://github.com/VSCodium/vscodium/releases/latest | awk -F'/' '{print $NF}')
sed -i "s/version = \".*\"/version = \"${VSCODIUM_VER}\"/" "$ROOT/vscodium.nix"

VSCODIUM_LINUX_URL="https://github.com/VSCodium/vscodium/releases/download/${VSCODIUM_VER}/VSCodium-linux-x64-${VSCODIUM_VER}.tar.gz"
VSCODIUM_LINUX_SHA256=$(nix-prefetch-url ${VSCODIUM_LINUX_URL})
sed -i "s/x86_64-linux = \".\{52\}\"/x86_64-linux = \"${VSCODIUM_LINUX_SHA256}\"/" "$ROOT/vscodium.nix"

VSCODIUM_DARWIN_URL="https://github.com/VSCodium/vscodium/releases/download/${VSCODIUM_VER}/VSCodium-darwin-${VSCODIUM_VER}.zip"
VSCODIUM_DARWIN_SHA256=$(nix-prefetch-url ${VSCODIUM_DARWIN_URL})
sed -i "s/x86_64-darwin = \".\{52\}\"/x86_64-darwin = \"${VSCODIUM_DARWIN_SHA256}\"/" "$ROOT/vscodium.nix"