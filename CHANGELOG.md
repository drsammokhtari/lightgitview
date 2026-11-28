# Changelog

## v1.5.1 · 2026-11-28
- **Fixed: the app froze on a repo with thousands of untracked files** (for example rendered video frames or an un-ignored node_modules). The changes list rebuilt its folder rows from every file on each redraw, and the file tree held up to 30,000 files. Now, when a repo has more than 1,000 untracked files, untracked folders are listed as one row each, with a **Show all N files** button above the list that lists every file. Folder rows in the changes list are now built in one pass instead of rescanning every change per folder. The file tree stops at 5,000 files.

## v1.5.0 · 2026-11-27
- **Create repo…** (the + button or the workspace menu, next to Clone): makes a new local folder under the folder you pick and the same repo on GitHub as its `origin`. You choose the name, the GitHub account or organisation, Private (the default) or Public (asks to confirm), a description, the first branch name, and optionally a README, a .gitignore template and a license. The app runs `git init`, makes the first commit, then `gh repo create --push`. A name that already exists on GitHub or as a folder is refused before anything is made; if GitHub refuses, the new folder is removed; if only the first push fails, the folder is kept and the message says so. The repo joins the workspaces you tick. Needs the GitHub CLI signed in.

## v1.4.1 · 2026-11-27
- Sync's button hover text now says that it pushes only commits you already made and never commits files. No behaviour change: Sync has never committed anything.

## v1.4.0 · 2026-11-27
- **Sync a workspace:** a Sync button above the repo list (also in the workspace menu and in the toolbar, ⇧⌘S) brings every repo of the workspace shown level with its remote. A repo that is behind is fast-forwarded, a repo that is ahead is pushed, and nothing is ever merged, rebased, stashed or force-pushed. A repo that could conflict is not touched and gets a tag in the sidebar (Would conflict, Diverged, Conflicts, No upstream, Detached, Fetch failed, Pull failed, Push failed); hover for the reason, which is also shown on the repo page. Local edits to files the remote did not change do not stop a pull. The tag clears on the next Sync or on a successful Pull or Push.

## v1.3.1 · 2026-11-26
- **Universal app:** the build now makes one app that runs natively on both Apple Silicon (arm64) and Intel (x86_64) Macs. `scripts/build-app.sh` builds each architecture and joins them with `lipo`.

## v1.3.0 · 2026-11-26
- **Fixed: "Cannot fast-forward to multiple branches" on Pull.** The app's own background fetches overlapped `git pull` and left FETCH_HEAD with several entries, so the first Pull failed and the second worked. Pull now runs `git fetch` and then `git merge --ff-only` on the upstream branch by name; the app's fetches no longer write FETCH_HEAD; and fetch, pull and push never overlap on one repo.
- **Everything stays up to date:** every action (Refresh, Pull, Push, Commit, Discard, Ignore, Save, switching or deleting a branch, closing a pull request, cloning) now re-reads the whole repo: the counts in the repo list, the file tree, the changes list, the open file and its diff, and the right-hand panel. The app also re-reads the selected repo when you come back to it from another app. A fetch that hangs is stopped after 30 seconds, and the status shows first, then is corrected after the fetch.
- **Delete branches safely** from the right-hand panel: right-click a branch for Delete local branch, Delete branch on origin, or Delete local and origin. main, master, the remote's default branch and the branch you are on are never deleted; unmerged commits and open pull requests are named first; git's safe delete runs first and force-deleting needs a second yes; deleting on origin asks you to type the branch name.
- **Close a pull request from its row** in the panel: Close, or Close and delete its branch (GitHub cannot delete a pull request, so it is closed).

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
