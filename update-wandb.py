#!/usr/bin/env nix-shell
#!nix-shell -i python3 -p python3 python3Packages.requests

import os
import re
import subprocess

import requests

gh_owner = "wandb"
gh_repo = "wandb"

release = requests.get(
    f"https://api.github.com/repos/{gh_owner}/{gh_repo}/releases/latest").json(
    )
tarball_url = release["tarball_url"]
tag_name = release["tag_name"]
assert tag_name[0] == "v"
major, minor, patch = tag_name[1:].split(".")

# nix-prefetch-url doesn't output SRI hashes for some reason. See https://discourse.nixos.org/t/why-does-nix-prefetch-url-not-return-hashes-in-sri-format/18271.
sha256 = subprocess.check_output(
    ["nix-prefetch-url", "--type", "sha256", "--unpack", tarball_url],
    text=True).strip()
srihash = subprocess.check_output(
    ["nix", "hash", "to-sri", "--type", "sha256", sha256], text=True).strip()

nix_path = os.path.join(os.path.dirname(__file__), "default.nix")
nix0 = open(nix_path, "r").read()
nix1 = re.sub("version = \".*\";", f"version = \"{major}.{minor}.{patch}\";",
              nix0)
nix2 = re.sub(r"(sha256|hash) = \".*\";", f"hash = \"{srihash}\";", nix1)
open(nix_path, "w").write(nix2)
