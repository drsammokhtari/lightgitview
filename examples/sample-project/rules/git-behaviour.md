# Git behaviour the app relies on

- Status is read with `git status --porcelain=v2 --branch`; porcelain output stays stable across Git versions and user configuration [1]. Source: [1] https://git-scm.com/docs/git-status
- Branch header lines give `# branch.head`, `# branch.upstream` and `# branch.ab +<ahead> -<behind>`; untracked items print as `? <path>` [1].
- `-z` ends each line with a NUL byte and prints paths unquoted [1].
- Pull is fast-forward-only: it fails when the local branch has diverged [3]. Source: https://git-scm.com/docs/git-pull
- Push with no arguments uses the branch's upstream, or `origin` when none is set [2]. Source: https://git-scm.com/docs/git-push
- A commit takes its message with `-m <msg>` [4]. Source: https://git-scm.com/docs/git-commit
- Credentials come from a git credential helper; on macOS `git-credential-osxkeychain` stores them [6]. Source: https://git-scm.com/docs/gitcredentials
- A folder is a repo when `git rev-parse --is-inside-work-tree` prints `true` [7]. Source: https://git-scm.com/docs/git-rev-parse

Effective date: the pages were read on 2026-11-25; no effective date is published for these behaviours. UNVERIFIED: the exact git version the user has installed.
