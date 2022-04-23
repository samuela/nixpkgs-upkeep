#!/usr/bin/env nix-shell
#!nix-shell -i python3 -p python3Packages.requests gitAndTools.gh

import argparse
import json
import os
import re
import select
import subprocess
import sys
from typing import List, NamedTuple, Tuple

import requests

parser = argparse.ArgumentParser()
parser.add_argument("--attr", required=True, help="Attribute to build")
parser.add_argument(
    "--cc",
    action="append",
    default=[],
    help="non-maintainer GitHub username(s) to cc, option can be repeated")
parser.add_argument(
    "--nixpkgs",
    default=".",
    help="Path to nixpkgs directory, default is current working directory")

args = parser.parse_args()
attr = args.attr
cc = args.cc


class ProcessResult(NamedTuple):
    returncode: int
    stdout: List[str]
    stderr: List[str]


def run(cmd_args) -> ProcessResult:
    """Run a command, piping stdout and stderr through while also capturing them."""
    print(f">>> {' '.join(cmd_args)}")
    p = subprocess.Popen(cmd_args,
                         stdout=subprocess.PIPE,
                         stderr=subprocess.PIPE,
                         cwd=args.nixpkgs)
    stdout = []
    stderr = []
    while True:
        r, _, _ = select.select([p.stdout.fileno(), p.stderr.fileno()], [], [])
        # For some reason the fd's will sometimes say that they're ready to read
        # but then will read an empty byte string.
        no_read = True
        for fd in r:
            if fd == p.stdout.fileno():
                read = p.stdout.readline()
                if read != b"":
                    no_read = False
                    sys.stdout.buffer.write(b"stdout: " + read)
                    sys.stdout.flush()
                    stdout.append(read)
            elif fd == p.stderr.fileno():
                read = p.stderr.readline()
                if read != b"":
                    no_read = False
                    sys.stderr.buffer.write(b"stderr: " + read)
                    sys.stderr.flush()
                    stderr.append(read)

        if no_read and p.poll() is not None:
            return ProcessResult(p.poll(), stdout, stderr)


build_result = run(["nix-build", "-A", attr])

if build_result.returncode == 0:
    print("Build succeeded")
    sys.exit(0)

# Find the error lines in the stderr...
stderr_utf8 = [line.decode("utf-8") for line in build_result.stderr]
first_error_line_re = r"error: builder for '/nix/store/\w{32}-(.*).drv' failed with exit code \d+;"
first_error_line_ = [(ix, re.match(first_error_line_re, line).group(1))
                     for ix, line in enumerate(stderr_utf8)
                     if re.match(first_error_line_re, line) is not None]
assert len(first_error_line_) == 1
first_error_line_ix, failing_pname_version = first_error_line_[0]

# Note that after `first_error_line_ix` there's the "last 10 log lines:" and
# then, starts 10 lines of logs.
last_10_log_lines = stderr_utf8[first_error_line_ix + 2:first_error_line_ix +
                                12]

# Pytest will output things like
#     ==== 17 failed, 2164 passed, 53 skipped, 598 warnings in 604.22s (0:10:04) =====
# And the timing info will screw up our hash calculation, so we have to strip it
# out.
last_10_log_lines_pure = re.sub(r"\d+.\d+s", "", "".join(last_10_log_lines))
last_10_log_lines_pure = re.sub(r"\d+:\d+:\d+", "", last_10_log_lines_pure)

# Note that we don't include the nixpkgs commit or the /nix/store/xxx hash here,
# since those change very frequently and would likely create duplicate issues.
tag = hash(f"nixpkgs-upkeep {failing_pname_version} {last_10_log_lines_pure}")

# Check if an issue already exists for this tag.
existing_issues = requests.get(
    "https://api.github.com/search/issues",
    headers={
        "Accept": "application/vnd.github.v3+json"
    },
    params={
        "q": f"{tag} org:NixOS repo:nixpkgs is:issue is:open author:samuela"
    }).json()
existing_issues_count = existing_issues["total_count"]
if existing_issues_count > 0:
    print(
        f"{existing_issues_count} existing issue(s) found for tag {tag}: {existing_issues}"
    )
    sys.exit(build_result.returncode)


# Parse out the pname and version, then parse out attr from pname.
def split_pname_version(pname_version: str) -> Tuple[str, str]:
    pieces = pname_version.split("-")
    return "-".join(pieces[:-1]), pieces[-1]


failing_pname, failing_version = split_pname_version(failing_pname_version)


def pname_to_attr(pname: str) -> str:
    if pname.startswith("python3.9-"):
        return f"python39Packages.{pname[10:]}"
    elif pname.startswith("python3.10-"):
        return f"python310Packages.{pname[11:]}"
    # jaxlib has an "internal" package for the bazel build. Annoying to hardcode
    # but better UX this way.
    elif pname == "bazel-build-jaxlib":
        return "python3Packages.jaxlib"
    else:
        return pname


failing_attr = pname_to_attr(failing_pname)

commit = subprocess.run(["git", "log", "-1", "--pretty=format:%H"],
                        cwd=args.nixpkgs,
                        stdout=subprocess.PIPE).stdout.decode("utf-8").strip()


def get_maintainers(attr: str) -> List[str]:
    p = subprocess.run([
        "nix", "eval", "--json", "--file", args.nixpkgs,
        f"{attr}.meta.maintainers"
    ],
                       stdout=subprocess.PIPE)
    if p.returncode == 0:
        maintainers_json = json.loads(p.stdout.decode("utf-8").strip())
        return [m["github"] for m in maintainers_json]
    else:
        print(f"Failed to get maintainers for {attr}")
        return []


attr_maintainers = get_maintainers(attr)
failing_attr_maintainers = get_maintainers(failing_attr)

nix_info = subprocess.run(
    ["nix-shell", "-p", "nix-info", "--run", "nix-info -m"],
    stdout=subprocess.PIPE).stdout.decode("utf-8").strip()

# We provide defaults to the env var lookup just so that it's easier in
# development.
github_workflow_url = f"https://github.com/{os.environ.get('GITHUB_REPOSITORY', '<GITHUB_REPOSITORY>')}/actions/runs/{os.environ.get('GITHUB_RUN_ID', '<GITHUB_RUN_ID>')}"
issue_body = f"""
## Issue description
Build of `{failing_attr}` failed on x86_64-linux as of {commit}. This is currently breaking `{attr}`.

```
{"".join(stderr_utf8[first_error_line_ix:]).strip()}
```

[full build log]({github_workflow_url})

{attr} maintainers cc: {" ".join([f"@{m}" for m in attr_maintainers])}
{failing_attr} maintainers cc: {" ".join([f"@{m}" for m in failing_attr_maintainers])}
Other cc: {" ".join([f"@{m}" for m in cc]) if len(cc) > 0 else "n/a"}

### Steps to reproduce
1. Checkout nixpkgs at commit {commit}
2. Run `nix-build -A {failing_attr}`

## Technical details
```
 {nix_info}
```

## Misc.
This issue was automatically generated by [nixpkgs-upkeep](https://github.com/samuela/nixpkgs-upkeep).
- [CI workflow]({github_workflow_url}) that created this issue.
- Internal tag: {tag}
"""

# Create issue
subprocess.run([
    "gh", "issue", "create", "--repo", "NixOS/nixpkgs", "--assignee",
    ",".join(failing_attr_maintainers), "--title",
    f"`{failing_attr}` build failure on x86_64-linux as of `{commit[:8]}`",
    "--body", issue_body
],
               check=True)

sys.exit(build_result.returncode)
