# 01 · Workspace

Kind: step. Done once per project.

Finds every git repo directly inside the workspace folder.

## Needs

- Nothing. This is the first folder.

## Put in

- [ ] Workspace folder: the parent folder of your repos (a path), chosen in the app, from your own disk, sample: `inputs/sample-workspace.json`

## Expect out

- [ ] `repos.json`: one object per repo found, with its folder name and absolute path

## Check before moving on

Signs: Jordan, after comparing the list with the folder in Finder.

- [ ] Every folder in `inputs/sample-workspace.json` with `is_repo` true appears in `repos.json`
- [ ] No folder with `is_repo` false appears in `repos.json`
- [ ] `repos.json` lists 2 repos for the sample (`alpha-api`, `beta-site`)

## How the app does it

1. Read `config/project.json` for `workspace_path`. Done when the folder exists.
2. List its direct sub-folders. Done when every sub-folder has been looked at.
3. Run `git rev-parse --is-inside-work-tree` in each. Done when each is marked repo or not.
4. Write `working/repos.json` with the repos. Done when its count equals the number of `true` answers.

## Tool

System git (free). See the PRD's Tools section.

## Rules

- `rules/git-behaviour.md`: repo detection [7].
