#!/usr/bin/env nix-shell
#!nix-shell -i python3 -p python3 python3Packages.requests

import os
import re
import subprocess

import requests

latest = requests.get("https://api.github.com/repos/matplotlib/matplotlib/releases/latest").json()["tag_name"]
assert latest[0] == "v"
major, minor, patch = latest[1:].split(".")

sha256 = subprocess.check_output(["nix-prefetch-url", f"https://files.pythonhosted.org/packages/source/m/matplotlib/matplotlib-{major}.{minor}.{patch}.tar.gz"], text=True).strip()

nix_path = os.path.join(os.path.dirname(__file__), "default.nix")
nix0 = open(nix_path, "r").read()
nix1 = re.sub("version = \".*\";", f"version = \"{major}.{minor}.{patch}\";", nix0)
nix2 = re.sub("sha256 = \".*\";", f"sha256 = \"{sha256}\";", nix1)
open(nix_path, "w").write(nix2)
