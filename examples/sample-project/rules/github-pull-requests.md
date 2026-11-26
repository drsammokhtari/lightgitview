# GitHub pull request behaviour the app relies on

Pages read on 2026-11-26. No effective dates are published for these commands. Each rests on one manual page: SINGLE SOURCE.

- `gh pr review` takes `--approve`, `--request-changes` or `--comment`, with `--body` [15]. Source: https://cli.github.com/manual/gh_pr_review
- `gh pr close` closes a pull request; `--delete-branch` deletes the local and remote branch [16]. Source: https://cli.github.com/manual/gh_pr_close
- `gh pr comment` adds a comment with `--body` [17]. Source: https://cli.github.com/manual/gh_pr_comment
- `gh pr diff` prints the patch; `--color never` turns colour off [18]. Source: https://cli.github.com/manual/gh_pr_diff
- `gh pr view --json` gives number, title, body, state, url, headRefName, baseRefName, isDraft, author, additions, deletions, files, comments, reviews and reviewDecision [19]. Source: https://cli.github.com/manual/gh_pr_view

UNVERIFIED: whether GitHub offers any way to delete a pull request (the app closes it instead). UNVERIFIED: whether `gh` refuses to approve your own pull request.
