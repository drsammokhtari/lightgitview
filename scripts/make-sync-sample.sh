#!/bin/sh
# Creates a throwaway workspace with one repo per sync case, to check that Sync only touches what cannot conflict.
set -eu
root=${1:?usage: make-sync-sample.sh <folder>}
rm -rf "$root"; mkdir -p "$root/.remotes"; cd "$root"
g() { git -c user.name=T -c user.email=t@example.com -c init.defaultBranch=main "$@"; }
mk() { # name: a bare remote and a working clone holding p.txt and q.txt
  g init -q --bare ".remotes/$1.git"
  g clone -q ".remotes/$1.git" "$1" 2>/dev/null
  (cd "$1" && g checkout -q -b main && echo p > p.txt && echo q > q.txt && g add -A && g commit -q -m seed && g push -q -u origin main)
}
remote_commit() { # name file content: a commit on the remote, made through a scratch clone
  g clone -q ".remotes/$1.git" "_o-$1" 2>/dev/null
  (cd "_o-$1" && echo "$3" > "$2" && g add -A && g commit -q -m "remote $2" && g push -q origin main)
  rm -rf "_o-$1"
}
mk s-same
mk s-behind;   remote_commit s-behind r1.txt one
mk s-ahead;    (cd s-ahead && echo a > a.txt && g add -A && g commit -q -m local)
mk s-dirty-ok; remote_commit s-dirty-ok r2.txt two; echo "local edit" > s-dirty-ok/q.txt
mk s-overlap;  remote_commit s-overlap p.txt remote; echo "local edit" > s-overlap/p.txt
mk s-diverged; remote_commit s-diverged r3.txt three; (cd s-diverged && echo d > d.txt && g add -A && g commit -q -m local)
mk s-conflict; remote_commit s-conflict p.txt remote; (cd s-conflict && echo local > p.txt && g commit -q -am local && g fetch -q && { g merge origin/main >/dev/null 2>&1 || true; })
mk s-noup;     (cd s-noup && g checkout -q -b feat)
mk s-detached; (cd s-detached && g checkout -q --detach)
echo "$root"
