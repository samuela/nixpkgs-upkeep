#!/usr/bin/env nix-shell
#!nix-shell -i python3 -p python3 python3Packages.requests

import os
import re
import subprocess
from datetime import datetime

import requests

gh_owner = "google"
gh_repo = "jax"

# jax and jaxlib are both released from the same GitHub repo, so we need to
# filter out only the jax releases.
all_releases = requests.get(
    f"https://api.github.com/repos/{gh_owner}/{gh_repo}/releases").json()
jax_releases = [r for r in all_releases if r["tag_name"].startswith("jax-v")]
release = max(
    jax_releases,
    key=lambda r: datetime.strptime(r["published_at"], "%Y-%m-%dT%H:%M:%SZ"))
tarball_url = release["tarball_url"]
tag_name = release["tag_name"]
print(f"Found release {tag_name}")
assert tag_name.startswith("jax-v")
major, minor, patch = tag_name[5:].split(".")

sha256 = subprocess.check_output(["nix-prefetch-url", "--unpack", tarball_url],
                                 text=True).strip()

nix_path = os.path.join(os.path.dirname(__file__), "default.nix")
nix0 = open(nix_path, "r").read()
nix1 = re.sub("version = \".*\";", f"version = \"{major}.{minor}.{patch}\";",
              nix0)
nix2 = re.sub("sha256 = \".*\";", f"sha256 = \"{sha256}\";", nix1)
open(nix_path, "w").write(nix2)
