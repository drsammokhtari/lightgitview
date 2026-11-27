# House rules (from the user)

Source: the user, onboarding row 9, 2026-11-25.

- A commit needs a non-empty message. The Commit button stays off until there is one.
- Before committing, warn when a changed or untracked file looks like a secret (for example `.env`). The person decides.
- Taken as default, not said by the user: Push and Pull ask for a click each time; nothing runs by itself.
- Deleting a repo moves its folder to the Trash after a confirmation that names its uncommitted changes and unpushed commits. Taken as default, PROPOSED (2026-11-26).
- Deleting a branch never touches main, master, the remote's default branch or the checked-out branch; asks before force-deleting an unmerged branch; and for origin asks for the branch name to be typed. Taken as default, PROPOSED (2026-11-26).
- Cloning refuses a destination folder that already exists, and a failed clone removes the half-made folder it was creating. Taken as default, PROPOSED (2026-11-26).
- Deleting a repo on GitHub as well asks for owner/name to be typed, deletes on GitHub first, and leaves the folder alone if GitHub refuses. Taken as default, PROPOSED (2026-11-26).
- Every public act on a pull request (comment, approve, request changes, close) asks first. Taken as default, PROPOSED (2026-11-26).
- Sync (the button for the workspace shown) pulls what is behind and pushes the commits already made, and nothing else. It never commits files, merges, rebases, stashes or force-pushes. A repo is left exactly as it is, and tagged in the repo list, when a merge or rebase is in progress, files have unresolved conflicts, HEAD is detached, the branch has no upstream, the fetch fails, the branch has diverged, or you changed a file the remote also changed. Taken as default, PROPOSED (2026-11-27): the user asked that a repo susceptible to conflict is not touched and gets a tag.
