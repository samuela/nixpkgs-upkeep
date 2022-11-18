let
  # Last updated: 2022-11-17. Check for new commits at https://status.nixos.org.
  # Tracking nixos-21.11
  pkgs = import (fetchTarball "https://github.com/NixOS/nixpkgs/archive/eabc38219184cc3e04a974fe31857d8e0eac098d.tar.gz") { };
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
    unixtools.watch
    yapf
  ];
}
