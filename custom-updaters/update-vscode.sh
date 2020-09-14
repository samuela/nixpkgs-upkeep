#!/usr/bin/env nix-shell
#!nix-shell -i bash -p curl gnugrep gnused gawk

# See https://github.com/NixOS/nixpkgs/pull/97938. This can be deleted when that's merged.

set -eou pipefail

ROOT="$(dirname "$(readlink -f "$0")")"
if [ ! -f "$ROOT/vscode.nix" ]; then
  echo "ERROR: cannot find vscode.nix in $ROOT"
  exit 1
fi

# VSCode

VSCODE_VER=$(curl -s -L "https://code.visualstudio.com/Download" | grep "is now available" | awk -F'</span>' '{print $1}' | awk -F'>' '{print $NF}')
VSCODE_VER=$(curl -s -L "https://code.visualstudio.com/updates/v${VSCODE_VER/./_}" | grep "Downloads:" | awk -F'code.visualstudio.com/' '{print $2}' | awk -F'/' '{print $1}')
sed -i "s/version = \".*\"/version = \"${VSCODE_VER}\"/" "$ROOT/vscode.nix"

VSCODE_LINUX_URL="https://vscode-update.azurewebsites.net/${VSCODE_VER}/linux-x64/stable"
VSCODE_LINUX_SHA256=$(nix-prefetch-url ${VSCODE_LINUX_URL})
sed -i "s/x86_64-linux = \".\{52\}\"/x86_64-linux = \"${VSCODE_LINUX_SHA256}\"/" "$ROOT/vscode.nix"

VSCODE_DARWIN_URL="https://vscode-update.azurewebsites.net/${VSCODE_VER}/darwin/stable"
VSCODE_DARWIN_SHA256=$(nix-prefetch-url ${VSCODE_DARWIN_URL})
sed -i "s/x86_64-darwin = \".\{52\}\"/x86_64-darwin = \"${VSCODE_DARWIN_SHA256}\"/" "$ROOT/vscode.nix"