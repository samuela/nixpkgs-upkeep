#!/usr/bin/env nix-shell
#!nix-shell -i bash -p curl jq gitAndTools.hub semver-tool

set -eou pipefail

# Check that there's a diff from the updater script. See https://stackoverflow.com/questions/3878624/how-do-i-programmatically-determine-if-there-are-uncommitted-changes.
if git diff-index --quiet HEAD --; then
    echo "No diff after running updater."
    exit 0
fi

newversion="$(nix-instantiate --eval -E "with import ./. {}; lib.getVersion $PACKAGE" --json | jq -r)"

# Sometimes there's a diff but the version is still the same. For example this
# happens when the hash has been changed to be in SRI format. In other cases you
# can even get downgrade suggestions as in https://github.com/NixOS/nixpkgs/pull/197638.
if [[ $(semver compare "$PRE_VERSION" "$newversion") != "-1" ]]; then
    echo "$newversion does not appear to be an upgrade from $PRE_VERSION"
    exit 0
fi

echo "Updating $PACKAGE from version $PRE_VERSION to version $newversion"

# GitHub doesn't support exact matches in its Search thingy (https://stackoverflow.com/questions/26433561/how-to-search-on-github-to-get-exact-matches-like-what-quotes-do-for-google).
# As a workaround we tag each PR with a unique string we can search later to
# check if we've already created a PR for the same update.
tag=$(echo "nixpkgs-upkeep $PACKAGE $newversion $TARGET_BRANCH" | md5sum | cut -d ' ' -f 1)

# Search to see if we've already created a PR for this version of the package.
existing_prs=$(curl --silent --get -H "Accept: application/vnd.github.v3+json" --data-urlencode "q=$tag org:NixOS repo:nixpkgs type:pr author:samuela" https://api.github.com/search/issues)
existing_prs_count=$(echo "$existing_prs" | jq .total_count)
if [ "$existing_prs_count" -gt 0 ]; then
    echo "There seems to be an existing PR for this change already:"
    echo "$existing_prs" | jq .items[].pull_request.html_url
    exit 0
fi

# We need to set up our git user config in order to commit.
git config --global user.email "skainsworth@gmail.com"
git config --global user.name "nixpkgs-upkeep-bot"

# We need to get a complete unshallow checkout if we're going to push to another
# repo. See https://github.community/t/automating-push-to-public-repo/17742/11?u=samuela
# and https://stackoverflow.com/questions/28983842/remote-rejected-shallow-update-not-allowed-after-changing-git-remote-url.
# We start with only a shallow clone because it's far, far faster and it most
# cases we don't ever need to push anything.
git fetch --unshallow origin

# Checkout the target branch first so that our commit has the right parent.
git checkout "$TARGET_BRANCH"

# See https://serverfault.com/questions/151109/how-do-i-get-the-current-unix-time-in-milliseconds-in-bash.
branch="upkeep-bot/$PACKAGE-$newversion-$(date +%s)"
git checkout -b "$branch"
git add .
git commit -m "$PACKAGE: $PRE_VERSION -> $newversion"
git push --set-upstream "https://samuela:$GH_TOKEN@github.com/samuela/nixpkgs.git" "$branch"

tested_box=" "
if [ "$TESTED_OTHER_LINUX" == "true" ]; then
    tested_box="x"
fi

# Note: we cannot put the tag into a comment because GitHub search apparently does not index them.
# Also we need to escape backticks for code blocks because otherwise they turn into string interpolation, running the
# commands. See https://stackoverflow.com/a/2310284/3880977.
message=$(cat <<-_EOM_
${PACKAGE}: ${PRE_VERSION} -> ${newversion}

###### Motivation for this change
Upgrades ${PACKAGE} from ${PRE_VERSION} to ${newversion}

This PR was automatically generated by [nixpkgs-upkeep](https://github.com/samuela/nixpkgs-upkeep).
- [CI workflow](${GITHUB_WORKFLOW_URL}) that created this PR.
- Internal tag: ${tag}.

###### Things done

<!-- Please check what applies. Note that these are not hard requirements but merely serve as information for reviewers. -->

- [ ] Tested using sandboxing ([nix.useSandbox](https://nixos.org/nixos/manual/options.html#opt-nix.useSandbox) on NixOS, or option \`sandbox\` in [\`nix.conf\`](https://nixos.org/nix/manual/#sec-conf-file) on non-NixOS linux)
- Built on platform(s)
   - [ ] NixOS
   - [ ] macOS
   - [${tested_box}] other Linux distributions
- [ ] Tested via one or more NixOS test(s) if existing and applicable for the change (look inside [nixos/tests](https://github.com/NixOS/nixpkgs/blob/master/nixos/tests))
- [ ] Tested compilation of all pkgs that depend on this change using \`nix-shell -p nixpkgs-review --run "nixpkgs-review wip"\`
- [ ] Tested execution of all binary files (usually in \`./result/bin/\`)
- [ ] Determined the impact on package closure size (by running \`nix path-info -S\` before and after)
- [ ] Ensured that relevant documentation is up to date
- [x] Fits [CONTRIBUTING.md](https://github.com/NixOS/nixpkgs/blob/master/.github/CONTRIBUTING.md).

_EOM_
)

echo "Creating a new PR on NixOS/nixpkgs..."
GITHUB_USER=samuela GITHUB_PASSWORD=$GH_TOKEN hub pull-request \
    --head samuela:"$branch" \
    --base NixOS:"$TARGET_BRANCH" \
    --message "$message"
