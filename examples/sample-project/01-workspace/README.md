# 01 · Workspace

Kind: step. Done once per project.

Finds every git repo directly inside the workspace folder.

## Needs

- Nothing. This is the first folder.

## Put in

- [ ] Workspace folder: the parent folder of your repos (a path), chosen in the app, from your own disk, sample: `inputs/sample-workspace.json`
- [ ] A repo to clone (optional): a URL or owner/name, a destination folder, a folder name, an optional branch and the workspaces it joins, typed or picked in the app, sample: `inputs/sample-clone.md`
- [ ] A click on Sync (optional): the button above the repo list, for the workspace being shown. No input and no sample file; each repo's result is a row in `sync.csv`
- [ ] A repo to delete (optional): chosen by right-click on a repo in the app, either from disk only or from disk and GitHub. No sample file; the act is recorded in `removed.csv`

## Expect out

- [ ] `repos.json`: one object per repo found, with its folder name and absolute path
- [ ] `cloned.csv`: one row per clone (url, path, branch, workspaces, cloned_on); empty when none
- [ ] `sync.csv`: one row per repo per sync (repo, result, tag, reason, commits, synced_on); `result` is pulled, pushed, up to date or left alone; empty when none
- [ ] `removed.csv`: one row per repo deleted (folder, path, scope, github, uncommitted, unpushed, removed_on); empty when none

## Check before moving on

Signs: Jordan, after comparing the list with the folder in Finder.

- [ ] Every folder in `inputs/sample-workspace.json` with `is_repo` true appears in `repos.json`
- [ ] No folder with `is_repo` false appears in `repos.json`
- [ ] `repos.json` lists 2 repos for the sample (`alpha-api`, `beta-site`)
- [ ] A cloned repo appears in `repos.json`, its folder holds a `.git` entry, every workspace named in `cloned.csv` lists it, and a failed clone leaves no folder behind
- [ ] A deleted repo is gone from `repos.json` and its folder is in the Trash; `removed.csv` names how many uncommitted changes and unpushed commits it had; a row with scope `disk and github` names the GitHub repo, and the repo name was typed to confirm
- [ ] After a sync, every repo pulled or pushed shows its new counts; every row of `sync.csv` with result `left alone` has a tag and a reason, and that repo is exactly as before (same HEAD, same changed files, no merge started)

## How the app does it

1. Read `config/project.json` for `workspace_path`. Done when the folder exists.
2. List its direct sub-folders. Done when every sub-folder has been looked at.
3. Check each for a `.git` entry (the app's test; `git rev-parse --is-inside-work-tree` is the documented one). Done when each is marked repo or not.
4. Write `working/repos.json` with the repos. Done when its count equals the number of `true` answers.
5. On your Delete from disk click, show the uncommitted and unpushed counts and ask. On yes move the folder to the Trash, drop it from `repos.json` and from every workspace, and add a row to `working/removed.csv`. Done when the folder is no longer in the workspace folder.
6. On your Clone click, refuse an empty source or a destination that already exists. A URL runs `git clone`; owner/name runs `gh repo clone`. On success add the repo to the list and the chosen workspaces and add a row to `working/cloned.csv`; on failure remove the half-made folder and show the message. Done when the new folder is in `repos.json`, or nothing is left behind.
7. On your Delete from disk and GitHub click, read the origin remote for owner/name; if it is not on github.com, stop and say so. Show the counts and ask for owner/name to be typed. Run `gh repo delete owner/name --yes`. Only if it succeeds do step 5. If it fails, show the message from `gh` and leave the folder alone. Done when the repo is gone from GitHub and the folder is in the Trash, or nothing changed.
8. On your Sync click, take the repos four at a time, one network job per repo at a time. Leave a repo alone and tag it when a merge, rebase, cherry-pick or revert is in progress or a file has unresolved conflicts (Conflicts), HEAD is not on a branch (Detached), the branch has no upstream (No upstream) or the fetch fails (Fetch failed). Otherwise fetch with `--no-write-fetch-head`. Both ahead and behind: leave it, tag Diverged. Behind: list the files the remote changed with `git diff --name-only -z HEAD @{upstream}`; if you also changed any, leave it, tag Would conflict; else run `git merge --ff-only @{upstream}`. Ahead: run `git push`. Write a row per repo to `working/sync.csv`. Done when every repo has a row and every repo left alone is unchanged.

## Tool

System git (free). See the PRD's Tools section.

## Rules

- `rules/git-behaviour.md`: repo detection [7].
- `rules/git-behaviour.md`: `git clone` [23].
- `rules/github-pull-requests.md`: `gh repo clone` [24], `gh repo list` [25], `gh repo delete` needs owner/repo with `--yes` and the delete_repo scope [22].
- `rules/git-behaviour.md`: fast-forward only [28], fetch without FETCH_HEAD [29], push default [2] (Sync).
- `rules/house-rules.md`: Sync never merges, rebases, stashes or force-pushes, and a repo that could conflict is left alone and tagged.
- `rules/house-rules.md`: deleting asks first; deleting on GitHub asks for the name to be typed.
