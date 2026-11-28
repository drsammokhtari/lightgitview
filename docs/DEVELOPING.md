# LightGitView

A light Mac app: pick a folder of git repos, click a repo, see status and changes, then commit, pull and push. One binary, no dependencies, runs your system `git`.

## Build and run

```sh
sh scripts/build-app.sh          # makes dist/LightGitView.app, universal: Apple Silicon + Intel (about 6 MB)
open "dist/LightGitView.app"
sh scripts/selftest.sh           # builds a sample workspace and checks the PRD's numbers
sh scripts/make-sample.sh ~/sample-workspace   # real sample repos to try the app on
```

## Which file to edit

| Change | File |
|---|---|
| What git commands run, parsing | `Sources/LightGitView/Git.swift`, `Store.swift` |
| Screens and buttons | `Sources/LightGitView/Views.swift` |
| Colours, font, window | `Sources/LightGitView/App.swift` |
| Name, bundle id, icon | `scripts/build-app.sh`, `branding/logo.png` |
| Secret-looking file names | `Change.looksSecret` in `Git.swift` |
| What the ignore menu offers (file, folder, extension) | `IgnoreScope` in `Git.swift`, `askIgnore` in `Views.swift` |
| Right-click and "..." menus on changed files and folders | `fileMenu`, `dirMenu`, `rowActions` in `Views.swift` |
| Pull, fetch and push (one job at a time per repo) | `Store.pull`, `Store.fetchRemote`, `Store.gated`, `RepoGate` in `Git.swift`; do not use `git pull` |
| Keeping every panel current | `Store.reload` (status, then the panel and tree), `Store.revision`, `reloadOpenFile` in `Views.swift`; end every new action with `await reload(repo)` |
| Deleting branches, closing pull requests from the panel | `Store.protectedNames`, `branchFacts`, `deleteLocalBranch`, `deleteRemoteBranch`, `askDeleteBranch`, `askClosePR` |
| Editing a file (open, edit, save) | `Store.fileForEditing`, `Store.saveFile`, `openFile` and `saveEdit` in `Views.swift` |
| File tree sidebar | `FileNode` and `TreeBuilder` in `Git.swift`, `Store.loadTree`, `FileTreePane` in `Views.swift` |
| Sync a workspace (pull, push, tag risky repos) | `Store.syncRepos`, `Store.syncOne`, `SyncTag` in `Store.swift`; `SidebarRow` tag and the Sync buttons in `Views.swift`; `scripts/make-sync-sample.sh` builds the nine test cases |
| Large repos (collapsing untracked folders, tree limit) | `Store.untrackedLimit`, `Store.treeLimit`, `Store.readStatus`, `Store.collapsedUntracked` |
| Clone repo | `Store.cloneRepo`, `CloneSource` in `Git.swift`, `CloneSheet` in `Views.swift` |
| Create repo (local folder + GitHub origin) | `Store.createRepo`, `makeLocalRepo`, `githubOwners`, `NewRepo` in `Git.swift`, `CreateRepoSheet` in `Views.swift` |
| Delete repo (disk, and disk plus GitHub) | `Store.deleteRepo`, `Store.deleteRepoEverywhere`, `GitHubRemote` in `Git.swift`, `askDeleteRepo` and `askDeleteEverywhere` in `Views.swift` |
| Pull request review (view, diff, comment, review, close) | `PRDetail` and `PRParser` in `Git.swift`, `Store.loadPR` and the `gh` calls, `PRSheet` in `Views.swift` |

## Decisions

- Standalone SwiftUI, not the AI studio template: v1 has no AI, so no engine, uv or Claude sign-in. See `brief.md`.
- A folder is listed as a repo when it holds a `.git` entry (the PRD named `git rev-parse`; that returns true inside any repo's sub-folder, so `.git` is the safer test).
- Commit: the app clears the index, adds only the ticked files, then commits. Push is held while the repo is behind; Pull is fast-forward-only.
- Repos folders, workspaces and the selected workspace are remembered; nothing else is stored.
- Sync never commits, merges, rebases, stashes or force-pushes; it only fast-forwards and pushes commits that already exist. `syncOne` leaves a repo alone, and tags it, unless a fast-forward pull or a plain push cannot conflict; the checks run before anything changes. Add any new risk to `syncOne` and a case to `make-sync-sample.sh`.
- Ignoring a tracked file also runs `git rm --cached` after a yes, because a .gitignore does not affect files git already tracks.
- Delete from disk moves the folder to the Trash instead of removing it. Delete from disk and GitHub runs `gh repo delete owner/repo --yes` first, asks for the name to be typed, and leaves the folder alone if GitHub refuses. It never passes `--accept-cascading-deletion-of-private-forks`. Untracked files and folders that you discard go to the Trash too.
- GitHub cannot delete a pull request, so the app closes it. Pull request features need the GitHub CLI (`gh`), signed in; the rest of the app needs only `git`.
