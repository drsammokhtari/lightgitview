# Changelog

## v1.2.0 · 2026-11-26
- Right-click a changed file or folder for more actions: include or exclude from the commit, reveal in Finder, open, copy path, ignore, discard. The same list is under a new "..." button on each row.
- **Edit files:** click a file in the tree or the changes list. A changed file opens on its diff with an **Edit** tab; an unchanged file opens in the editor. Save with ⌘S; the changes list and counts update. Moving to another file with unsaved edits asks Save or Don't Save. Text files up to 1 MB; binary, larger and non-UTF-8 files say why they can't be edited.
- Layout: the columns now have fixed, readable widths (file tree 200, changes list 340) and only the diff takes spare room, so the Refresh, Pull and Push buttons and the right-hand panel are no longer pushed out of the window. The window cannot be made narrower than 1380 pixels. The ignore button on file rows moved into the "..." menu.
- **File tree:** click a repo and a second sidebar shows its folders and files. Changed files carry their status letter and folders with changes carry a dot. Click a file to read its diff, or its text if unchanged. Right-click for Reveal in Finder, Open and Copy path. The Files toolbar button hides it.
- **Clone repo…** (the + button or the workspace menu): paste a URL or owner/name, or pick one from your GitHub repos; choose the folder to clone into and its name, an optional branch, and the workspaces it joins (or create one). The clone is refused if the folder exists, and a failed clone leaves nothing behind.
- `sh scripts/selftest.sh` checks cloning against the sample remote and no longer writes your saved settings.

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
