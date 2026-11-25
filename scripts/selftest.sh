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
echo "selftest ok"
