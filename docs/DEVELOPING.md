# LightGitView

A light Mac app: pick a folder of git repos, click a repo, see status and changes, then commit, pull and push. One binary, no dependencies, runs your system `git`.

## Build and run

```sh
sh scripts/build-app.sh          # makes dist/LightGitView.app (about 1 MB)
open "dist/LightGitView.app"
sh scripts/selftest.sh           # builds a sample workspace and checks the PRD's numbers
sh scripts/make-sample.sh ~/sample-workspace   # real sample repos to try the app on
```

## Which file to edit

| Change | File |
|---|---|
| What git commands run, parsing | `Sources/LightGitView/Git.swift`, `Store.swift` |
| Screens and buttons | `Sources/LightGitView/Views.swift` |
| Colours, font, window | `Sources/LightGitView/App.swift` |
| Name, bundle id, icon | `scripts/build-app.sh`, `branding/logo.png` |
| Secret-looking file names | `Change.looksSecret` in `Git.swift` |

## Decisions

- Standalone SwiftUI, not the AI studio template: v1 has no AI, so no engine, uv or Claude sign-in. See `brief.md`.
- A folder is listed as a repo when it holds a `.git` entry (the PRD named `git rev-parse`; that returns true inside any repo's sub-folder, so `.git` is the safer test).
- Commit: the app clears the index, adds only the ticked files, then commits. Push is held while the repo is behind; Pull is fast-forward-only.
- The folder you pick is remembered; no other settings are stored.
