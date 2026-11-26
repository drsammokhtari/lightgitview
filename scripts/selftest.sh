#!/bin/sh
# Builds a sample workspace and checks the app's numbers against the sample project's "accepts".
set -eu
here=$(cd "$(dirname "$0")/.." && pwd)
ws=$(mktemp -d)/sample-workspace
sh "$here/scripts/make-sample.sh" "$ws" >/dev/null
out=$(cd "$here" && swift run -c release LightGitView --selftest "$ws" 2>/dev/null)
echo "$out"
echo "$out" | grep -q 'alpha-api branch=main upstream=origin/main ahead=1 behind=0 changed=2 untracked=2 added=14 deleted=3' || { echo "FAIL alpha-api"; exit 1; }
echo "$out" | grep -q 'beta-site branch=dev upstream=origin/dev ahead=0 behind=2 changed=2 untracked=0 added=5 deleted=45' || { echo "FAIL beta-site"; exit 1; }
echo "$out" | grep -q old-notes && { echo "FAIL old-notes listed"; exit 1; }
echo "$out" | grep -q 'ignore-ext notes-listed=false gitignore-listed=true' || { echo "FAIL ignore-ext"; exit 1; }
echo "$out" | grep -q 'ignore-tracked README code=D' || { echo "FAIL ignore-tracked"; exit 1; }
echo "$out" | grep -q 'scopes /src/a.py /src/ \*.py /ref/x/' || { echo "FAIL scopes"; exit 1; }
echo "$out" | grep -q 'pr files=2 comments=1 reviews=1 open=true diffs=README.md,src/api.py' || { echo "FAIL pr parse"; exit 1; }
echo "$out" | grep -q 'remotes me/app me/app me/app nil nil' || { echo "FAIL remote slug"; exit 1; }
echo "$out" | grep -q 'clone err=none listed=true inWorkspace=true duplicate=true failedLeftover=false folder=app short=true url=false' || { echo "FAIL clone"; exit 1; }
echo "$out" | grep -q 'tree top=docs/,src/,README.md src=a/,b.py' || { echo "FAIL tree"; exit 1; }
echo "$out" | grep -q 'repotree .*src' || { echo "FAIL repo tree"; exit 1; }
echo "$out" | grep -q 'edit read=true why=none missing=true save=ok added=12->13' || { echo "FAIL edit"; exit 1; }
echo "$out" | grep -q 'branches protected=true unmerged=1 safeRefused=true force=ok local=ok remote=ok gone=true' || { echo "FAIL branch delete"; exit 1; }
echo "$out" | grep -q 'reload tree=true status=true revision=1 timeout=124' || { echo "FAIL reload"; exit 1; }
echo "$out" | grep -q 'pull errors=0 behind=0 banner=ok' || { echo "FAIL pull"; exit 1; }
echo "selftest ok"
