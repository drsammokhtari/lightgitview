# Changelog

## v1.1 · 2026-11-26
- Ignore from the changes list: add a file, its folder, or all files with its extension to `.gitignore`. For a file git already tracks the app asks, then stops tracking it (the file stays on disk).
- Right-click a repo: **Delete from disk** moves the folder to the Trash after a confirmation that names uncommitted changes and unpushed commits. **Delete from disk and GitHub** also deletes the repo on GitHub for good: you type its owner/name to confirm, GitHub is deleted first, and the folder is only touched if GitHub agreed. Needs the GitHub CLI with the delete_repo permission (`gh auth refresh -s delete_repo`).
- Pull requests: open one from the side panel to read its changed files and diff and its conversation; comment, approve, request changes or close it (with an option to delete its branch). Uses the GitHub CLI.
- `sh scripts/selftest.sh` now also checks the ignore patterns and the pull request parsing.

## v1.0 · 2026-11-25
- First release.
- Browse a folder of git repos and see each one's branch, changes, and commits to push or pull.
- Commit only the files you tick, with a folder tree and tick boxes for whole folders.
- Pull (fast-forward only), push, refresh and fetch from the app.
- Discard changes with a confirmation; new files and folders go to the Trash.
- Ignore files and folders from the changes list.
- Group repos into workspaces, with an "All repos" view.
- Side panel with branches, commits not yet on your machine, and pull requests.
- Warns before you commit a file that looks like a secret.
