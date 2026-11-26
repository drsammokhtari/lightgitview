# Sample project: Jordan Avery's repos

Work: a developer on their own Mac keeps many git repos in sync and produces commits and pushes for the remote.

The main stakeholder is Jordan Avery (sample name), the only user and own sign-off. No AI is used: the app runs the system `git` and the person does every act.

| id | name | kind | needs | signs |
|---|---|---|---|---|
| 01-workspace | Workspace | step | nothing | Jordan, after matching the repo list to the folder |
| 02-repo | Repo | category (one per repo) | 01-workspace | Jordan, after reading the diff and message |
| 03-pull-request | Pull request | category (one per pull request) | 02-repo | Jordan, after reading the files and diff |

Order of work: pick the workspace folder once (01), then work each repo in any order (02, 02-repo-2, ...): status, changes, ignore, stage, commit, pull, push. Open each pull request when it needs a review (03, 03-pull-request-2, ...). New repos and pull requests can turn up at any time. Deleting a repo is done from 01-workspace.

Version 1.1 (2026-11-26) added: ignore from the changes list, delete a repo, and pull request review. 03-pull-request and these changes are PROPOSED until the user confirms them.
