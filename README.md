# nixpkgs-upkeep

Auto-updates bot for Nixpkgs. Updating packages in Nixpkgs is important but tedious work. nixpkgs-upkeep is a simple bot that checks for updates every 12 hours and creates PRs so you don't have to.

Currently the following packages are updated:

- plexamp
- python3Packages.matplotlib
- spotify
- vscode
- vscodium

Submit a PR to get your favorite Nix packages added to this list!

All the activity goes down in the form of GitHub Actions, so go check those out to see the logs, etc.

## FAQ

```
refusing to allow a Personal Access Token to create or update workflow `.github/workflows/editorconfig.yml` without `workflow` scope
```

Sometimes we get errors like this when pushing to samuela/nixpkgs, because samuela/nixpkgs is behind the upstream fork. When the fork is missing changes to sensitive files like `.github/...` stuff the push is rejected.

Fix is to manually pull from upstream and push to the fork to get things up-to-date.
