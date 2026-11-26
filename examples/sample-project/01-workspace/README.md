# 01 · Workspace

Kind: step. Done once per project.

Finds every git repo directly inside the workspace folder.

## Needs

- Nothing. This is the first folder.

## Put in

- [ ] Workspace folder: the parent folder of your repos (a path), chosen in the app, from your own disk, sample: `inputs/sample-workspace.json`
- [ ] A repo to delete (optional): chosen by right-click on a repo in the app. No sample file; the act is recorded in `removed.csv`

## Expect out

- [ ] `repos.json`: one object per repo found, with its folder name and absolute path
- [ ] `removed.csv`: one row per repo moved to the Trash (folder, path, uncommitted, unpushed, removed_on); empty when none

## Check before moving on

Signs: Jordan, after comparing the list with the folder in Finder.

- [ ] Every folder in `inputs/sample-workspace.json` with `is_repo` true appears in `repos.json`
- [ ] No folder with `is_repo` false appears in `repos.json`
- [ ] `repos.json` lists 2 repos for the sample (`alpha-api`, `beta-site`)
- [ ] A deleted repo is gone from `repos.json` and its folder is in the Trash; `removed.csv` names how many uncommitted changes and unpushed commits it had

## How the app does it

1. Read `config/project.json` for `workspace_path`. Done when the folder exists.
2. List its direct sub-folders. Done when every sub-folder has been looked at.
3. Check each for a `.git` entry (the app's test; `git rev-parse --is-inside-work-tree` is the documented one). Done when each is marked repo or not.
4. Write `working/repos.json` with the repos. Done when its count equals the number of `true` answers.
5. On your Delete repo click, show the uncommitted and unpushed counts and ask. On yes move the folder to the Trash, drop it from `repos.json` and from every workspace, and add a row to `working/removed.csv`. Done when the folder is no longer in the workspace folder.

## Tool

System git (free). See the PRD's Tools section.

## Rules

- `rules/git-behaviour.md`: repo detection [7].
