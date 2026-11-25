#!/bin/sh
# Creates the sample workspace from project/ as real git repos: alpha-api (ahead 1) and beta-site (behind 2).
set -eu
root=${1:-$HOME/sample-workspace}
rm -rf "$root"; mkdir -p "$root/.remotes"; cd "$root"
g() { git -c user.name="Jordan Avery" -c user.email="jordan@example.com" -c init.defaultBranch=main "$@"; }
seq_lines() { i=1; while [ $i -le "$2" ]; do echo "$1 $i"; i=$((i+1)); done; }
mk() { # name branch
  g init -q --bare "$root/.remotes/$1.git"
  g clone -q "$root/.remotes/$1.git" "$1" 2>/dev/null; cd "$1"; g checkout -q -b "$2"
}
# alpha-api: 1 commit ahead, 2 changed, 2 untracked, +14 -3
mk alpha-api main
mkdir src; seq_lines "old line" 3 > src/api.py; printf 'alpha-api\n' > README.md
g add -A; g commit -q -m "Initial"; g push -q -u origin main
echo "second" >> README.md; g commit -qam "Local only commit"
{ seq_lines "new line" 12; } > src/api.py; printf 'alpha-api\nsecond\nRun with python -m api.\nSet API_URL first.\n' > README.md
echo "API_KEY=sample" > .env; echo "todo" > notes.txt
cd "$root"
# beta-site: 2 behind, 2 changed (index.html +5 -5, old.css -40), 0 untracked
mk beta-site dev
seq_lines "old html" 5 > index.html; seq_lines "css" 40 > old.css
g add -A; g commit -q -m "Initial"; g push -q -u origin dev
cd "$root"; g clone -q "$root/.remotes/beta-site.git" _other 2>/dev/null; cd _other; g checkout -q dev
echo a > a.txt; g add -A; g commit -q -m "Remote 1"; echo b > b.txt; g add -A; g commit -q -m "Remote 2"; g push -q origin dev
cd "$root"; rm -rf _other; cd beta-site; g fetch -q
seq_lines "new html" 5 > index.html; rm old.css
cd "$root"; mkdir old-notes; echo "not a repo" > old-notes/readme.txt
echo "$root"
