#!/usr/bin/env nix-shell
#!nix-shell -i bash -p curl jq gitAndTools.hub

set -eou pipefail

package=$1

# Check that there's a diff from the updater script. See https://stackoverflow.com/questions/3878624/how-do-i-programmatically-determine-if-there-are-uncommitted-changes.
if git diff-index --quiet HEAD --; then
    echo "No diff after running updater."
    exit 0
fi

newversion="$(nix eval --raw -f . $package.version)"
echo "Updating $package to version $newversion"

# GitHub doesn't support exact matches in its Search thingy (https://stackoverflow.com/questions/26433561/how-to-search-on-github-to-get-exact-matches-like-what-quotes-do-for-google).
# As a workaround we tag each PR with a unique string we can search later to
# check if we've already created a PR for the same update.
tag=$(echo "nixpkgs-upkeep $package $newversion" | md5sum | cut -d ' ' -f 1)

# Search to see if we've already created a PR for this version of the package.
existing_prs=$(curl --silent --get -H "Accept: application/vnd.github.v3+json" --data-urlencode "q=$tag org:NixOS repo:nixpkgs type:pr author:samuela" https://api.github.com/search/issues)
existing_prs_count=$(echo $existing_prs | jq .total_count)
if [ $existing_prs_count -gt 0 ]; then
    echo "There seems to be an existing PR for this change already:"
    echo $existing_prs | jq .items[].pull_request.html_url
    exit 0
fi

# We need to set up our git user config in order to commit.
git config --global user.email "foo@bar.com"
git config --global user.name "upkeep-bot"

# See https://serverfault.com/questions/151109/how-do-i-get-the-current-unix-time-in-milliseconds-in-bash.
branch="upkeep-bot/$package-$newversion-$(date +%s)"
git checkout -b $branch
git add .
git commit -m "Update $package to $newversion"
git push --set-upstream https://samuela:$GH_TOKEN@github.com/samuela/nixpkgs.git $branch

# TODO: can we put the tag into a comment and still have the search work?
message=$(cat <<-_EOM_
Update ${package} to ${newversion}

This PR was automatically generated by [nixpkgs-upkeep](https://github.com/samuela/nixpkgs-upkeep).

Internal tag: ${tag}
_EOM_
)
hub pull-request \
    --head samuela:$branch \
    --base NixOS:master \
    --message "$message"
