# 02 · Repo

Kind: category. One folder per git repo. Second folder of the category: beta-site.

Shows one repo's status and changes, then commits, pulls and pushes it.

## Needs

- `01-workspace`: reads `01-workspace/outputs/repos.json`.

## Put in

- [ ] The repo's working folder: a git repo on disk, from your workspace, sample: `inputs/sample-git-status.txt`
- [ ] Changes to review: the diff of the working tree, produced by git, sample: `inputs/sample-diff.patch`
- [ ] Commit message: one line you type in the app, sample: `inputs/sample-commit-message.md`

## Expect out

- [ ] `status.json`: branch, upstream, ahead, behind, counts of changed and untracked files
- [ ] `changes.csv`: one row per changed or untracked file with its status, lines added and lines deleted
- [ ] `commit.md`: the commit message and the files committed, written after you press Commit

## Check before moving on

Signs: Jordan, after reading the diff and the message.

- [ ] The files in `changes.csv` equal the files listed in `inputs/sample-git-status.txt`
- [ ] Added and deleted line totals equal those in `inputs/sample-diff.patch`
- [ ] No file that looks like a secret (`.env`) is in the commit
- [ ] The commit message is not empty
- [ ] After Push, ahead is 0 and the push result is saved; Pull showed behind 0 first

## How the app does it

1. Read `01-workspace/outputs/repos.json` and find this repo. Done when its path is known.
2. Run `git status --porcelain=v2 --branch`. Done when branch, upstream, ahead and behind are read.
3. Write `working/status.json`. Done when counts equal the lines of each kind.
4. Run `git diff --numstat` for tracked files and list `? ` entries as untracked. Write `working/changes.csv`. Done when every changed and untracked path has a row.
5. Warn on paths matching the house rule for secrets. Done when each flagged path is shown.
6. On your Commit click with a non-empty message, run `git add` for ticked files then `git commit -m`. Write `working/commit.md`. Done when the commit exists.
7. On your Pull click run `git pull --ff-only`; on your Push click run `git push`. Done when ahead/behind are re-read.

## Tool

System git (free). See the PRD's Tools section.

## Rules

- `rules/git-behaviour.md`: status, pull, push, commit [1][2][3][4].
- `rules/house-rules.md`: message required; secret warning.
