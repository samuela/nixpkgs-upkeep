let
  # Last updated: 1/30/2022. Check for new commits at status.nixos.org.
  pkgs = import (fetchTarball "https://github.com/NixOS/nixpkgs/archive/5efc8ca954272c4376ac929f4c5ffefcc20551d5.tar.gz") { };
in
pkgs.mkShell {
  buildInputs = with pkgs; [
    dhall
    dhall-json
    # Necessary for yaml-to-dhall
    haskellPackages.dhall-yaml
    # dhall-lsp-server # TODO this doesn't seem to work with nix-env-selector, report issue?
    gitAndTools.gh
    python3
    python3Packages.requests
    yapf
  ];
}
