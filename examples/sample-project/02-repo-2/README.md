# 02 · Repo

Kind: category. One folder per git repo. Second folder of the category: beta-site.

Shows one repo's status and changes, then commits, pulls and pushes it.

## Needs

- `01-workspace`: reads `01-workspace/outputs/repos.json`.

## Put in

- [ ] The repo's working folder: a git repo on disk, from your workspace, sample: `inputs/sample-git-status.txt`
- [ ] Changes to review: the diff of the working tree, produced by git, sample: `inputs/sample-diff.patch`
- [ ] Commit message: one line you type in the app, sample: `inputs/sample-commit-message.md`
- [ ] A branch to delete (optional): chosen by right-click in the right-hand panel, local, origin or both; no sample file
- [ ] A click on a file in the file tree or the changes list, and edits you type in it (optional): no sample file
- [ ] An ignore choice (optional): a click on a changed file or folder (this file, its folder, or all files with its extension), sample: `inputs/sample-ignore.md`

## Expect out

- [ ] `status.json`: branch, upstream, ahead, behind, counts of changed and untracked files
- [ ] `changes.csv`: one row per changed or untracked file with its status, lines added and lines deleted
- [ ] `branches-deleted.csv`: one row per branch deletion (branch, scope, unmerged, pull_request, deleted_on); empty when none
- [ ] `ignored.csv`: one row per ignore (pattern, scope, untracked); empty when none
- [ ] `commit.md`: the commit message and the files committed, written after you press Commit

## Check before moving on

Signs: Jordan, after reading the diff and the message.

- [ ] The files in `changes.csv` equal the files listed in `inputs/sample-git-status.txt`
- [ ] Added and deleted line totals equal those in `inputs/sample-diff.patch`
- [ ] No file that looks like a secret (`.env`) is in the commit
- [ ] The commit message is not empty
- [ ] After Push, ahead is 0 and the push result is saved; Pull showed behind 0 first
- [ ] A saved edit shows in `changes.csv` with updated counts, and switching files with unsaved edits asked first
- [ ] The file tree lists every tracked file and every untracked file that is not ignored, and each changed file carries its status letter
- [ ] Every row of `branches-deleted.csv` is gone from the places its scope names, and none names main, master, the default branch or the checked-out branch
- [ ] Every row of `ignored.csv` is in `.gitignore`, and every file listed as untracked there is still on disk

## How the app does it

1. Read `01-workspace/outputs/repos.json` and find this repo. Done when its path is known.
2. Run `git status --porcelain=v2 --branch`. Done when branch, upstream, ahead and behind are read.
3. Write `working/status.json`. Done when counts equal the lines of each kind.
4. Run `git diff --numstat` for tracked files and list `? ` entries as untracked. Write `working/changes.csv`. Done when every changed and untracked path has a row.
5. Warn on paths matching the house rule for secrets. Done when each flagged path is shown.
6. On your Commit click with a non-empty message, run `git add` for ticked files then `git commit -m`. Write `working/commit.md`. Done when the commit exists.
7. On your Pull click run `git fetch`, then `git merge --ff-only @{upstream}` (not `git pull`, which merges whatever is in FETCH_HEAD); every fetch the app makes uses `--no-write-fetch-head` and runs one network job at a time per repo; on your Push click run `git push`. Done when ahead/behind are re-read.
8. On opening the repo, run `git ls-files -z --cached --others --exclude-standard` and build the folder tree, folders first. Mark changed files with their status letter and folders that hold changes with a dot. On a click open the file: a changed file shows its diff with an Edit tab, an unchanged file opens in the editor (text files up to 1 MB). On Save write the file, then re-read status and the tree. Done when every listed path is in the tree and a saved edit shows in `changes.csv`.
9. On your Delete branch click, refuse main, master, the remote's default branch and the checked-out branch. Count the commits only on the branch, find an open pull request that uses it, and ask; for origin or both ask for the branch name to be typed. Local: `git branch -d`; if git says it is not fully merged, ask again, then `-D`. Origin: `git push origin --delete`. Both: local first. Add a row to `working/branches-deleted.csv`. Done when the branch is gone from the places the scope names.
10. On your Ignore click write the pattern to `.gitignore`; for a tracked file ask first, then run `git rm --cached` so the file stays on disk. Add a row to `working/ignored.csv`. Done when the file no longer shows in the list as untracked.

## Tool

System git (free). See the PRD's Tools section.

## Rules

- `rules/git-behaviour.md`: status, pull, push, commit [1][2][3][4].
- `rules/git-behaviour.md`: `git branch -d` and `-D` [27], `git push --delete` [2]; `git ls-files` lists tracked and not-ignored untracked files [26]; .gitignore does not affect tracked files [20]; `git rm --cached` keeps the file [21].
- `rules/house-rules.md`: message required; secret warning; every public act asks first.
