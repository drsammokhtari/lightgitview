# Sample project: Jordan Avery's repos

Work: a developer on their own Mac keeps many git repos in sync and produces commits and pushes for the remote.

The main stakeholder is Jordan Avery (sample name), the only user and own sign-off. No AI is used: the app runs the system `git` and the person does every act.

| id | name | kind | needs | signs |
|---|---|---|---|---|
| 01-workspace | Workspace | step | nothing | Jordan, after matching the repo list to the folder |
| 02-repo | Repo | category (one per repo) | 01-workspace | Jordan, after reading the diff and message |

Order of work: pick the workspace folder once (01), then work each repo in any order (02, 02-repo-2, ...): status, changes, stage, commit, pull, push. New repos can turn up at any time.
