let
  # Last updated: 2022-04-25. Check for new commits at status.nixos.org.
  # Tracking nixos-21.11
  pkgs = import (fetchTarball "https://github.com/NixOS/nixpkgs/archive/c254b8c915ac912ae9ee9dc74eac555ccbf33795.tar.gz") { };
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
