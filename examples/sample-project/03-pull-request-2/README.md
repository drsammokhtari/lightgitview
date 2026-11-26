# 03 · Pull request

Kind: category. One folder per pull request. Second folder of the category: pull request #9 on beta-site.

Reads one pull request, lets you comment, approve, request changes or close it, and records what you did.

## Needs

- `02-repo`: reads `02-repo*/outputs/status.json` to find the repo and its branch.

## Put in

- [ ] Pull request number: a click on Review in the side panel, for repo `beta-site`, sample: `inputs/sample-pr.json`
- [ ] The patch: produced by `gh pr diff`, sample: `inputs/sample-pr-diff.patch`
- [ ] Your comment or review text: typed in the app, sample: `inputs/sample-review.md`

## Expect out

- [ ] `pr.json`: number, title, state, author, head, base, additions, deletions
- [ ] `files.csv`: one row per changed file with its additions and deletions
- [ ] `review.md`: your text and the decision (comment, approve, request changes, close, or none yet) with the time

## Check before moving on

Signs: Jordan, after reading the files and diff.

- [ ] The paths in `files.csv` equal the files in `inputs/sample-pr-diff.patch`
- [ ] Additions and deletions in `pr.json` equal the sums in `files.csv` (5 and 45 for this pull request)
- [ ] A comment or a request for changes has text
- [ ] Approve and close are recorded in `review.md` with the time; if the branch was deleted, `review.md` says so

## How the app does it

1. Read `02-repo*/outputs/status.json` and find the repo. Done when its path is known.
2. Run `gh pr view 9 --json` with the fields in `rules/github-pull-requests.md`. Done when the fields decode.
3. Run `gh pr diff 9` and split it by file. Done when every path in `files` has a patch.
4. Write `working/pr.json` and `working/files.csv`. Done when the sums match.
5. On your Comment click run `gh pr comment`; on Approve or Request changes run `gh pr review`; on Close run `gh pr close`, with `--delete-branch` only if you chose it. Each asks first. Done when `gh` returns success.
6. Write `working/review.md`. Done when the decision and time are recorded.

## Tool

GitHub CLI (`gh`, free). It must be installed and signed in. See the PRD's Tools section.

## Rules

- `rules/github-pull-requests.md`: review states [15], comment [17], close [16], diff [18], view fields [19].
- `rules/house-rules.md`: every public act asks first.
