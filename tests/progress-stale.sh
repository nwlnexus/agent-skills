#!/bin/sh
# Behaviour tests for hooks/progress-stale.sh (the Stop hook that reports a stale docs/progress file).
#   sh tests/progress-stale.sh        (needs git, touch -d / -t; run by scripts/validate-skills.sh)
set -u
here=$(cd "$(dirname "$0")" && pwd)
hook="$here/../hooks/progress-stale.sh"
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
pass=0
fail=0

ok() { pass=$((pass + 1)); printf 'ok   %s\n' "$1"; }
bad() { fail=$((fail + 1)); printf 'FAIL %s\n' "$1"; }
check() { # name, command...
  name=$1
  shift
  if "$@"; then ok "$name"; else bad "$name"; fi
}
# run_hook <json>: stdout of the hook; $? is the hook's exit status via $tmp/status.
run_hook() {
  out=$(printf '%s' "$1" | sh "$hook" 2>"$tmp/stderr")
  echo $? >"$tmp/status"
  printf '%s' "$out"
}
status() { cat "$tmp/status"; }
# set_age <file> <minutes>: mtime that many minutes in the past (portable: epoch arithmetic + touch -t).
set_age() {
  ts=$(($(date +%s) - $2 * 60))
  stamp=$(date -d "@$ts" +%Y%m%d%H%M.%S 2>/dev/null || date -r "$ts" +%Y%m%d%H%M.%S)
  touch -t "$stamp" "$1"
}

repo="$tmp/repo"
mkdir -p "$repo/docs/progress"
git -C "$repo" init -q
git -C "$repo" checkout -q -b task/x 2>/dev/null || true
pf="$repo/docs/progress/2026-10-26-561-policy.md"
printf '# progress\n' >"$pf"

# 1. stale file (45 minutes): one factual line
set_age "$pf" 45
out=$(run_hook "{\"session_id\":\"s\",\"cwd\":\"$repo\",\"hook_event_name\":\"Stop\"}")
check "stale: exits 0" [ "$(status)" = 0 ]
check "stale: one line" [ "$(printf '%s\n' "$out" | wc -l | tr -d ' ')" = 1 ]
check "stale: names path and age" [ "$out" = "progress file $pf last updated 45 minutes ago" ]
check "stale: nothing on stderr" [ ! -s "$tmp/stderr" ]

# 2. fresh file (5 minutes): silent
set_age "$pf" 5
out=$(run_hook "{\"cwd\":\"$repo\"}")
check "fresh: exits 0" [ "$(status)" = 0 ]
check "fresh: prints nothing" [ -z "$out" ]

# 3. boundary: exactly at the threshold is not stale, one minute past is
set_age "$pf" 20
out=$(run_hook "{\"cwd\":\"$repo\"}")
check "20 minutes: silent" [ -z "$out" ]
set_age "$pf" 21
out=$(run_hook "{\"cwd\":\"$repo\"}")
check "21 minutes: notice" [ "$out" = "progress file $pf last updated 21 minutes ago" ]

# 4. threshold override
out=$(PROGRESS_STALE_MINUTES=60 run_hook "{\"cwd\":\"$repo\"}")
check "threshold 60: silent at 21 minutes" [ -z "$out" ]

# 5. a subdirectory of the repo resolves to the same work tree
mkdir -p "$repo/sub/dir"
out=$(run_hook "{\"cwd\":\"$repo/sub/dir\"}")
check "subdirectory cwd: notice" [ "$out" = "progress file $pf last updated 21 minutes ago" ]

# 6. no progress file, not a git repo, bad JSON, empty stdin: silent and exit 0
rm "$pf"
out=$(run_hook "{\"cwd\":\"$repo\"}")
check "no progress file: silent" [ -z "$out" ]
check "no progress file: exits 0" [ "$(status)" = 0 ]
mkdir "$tmp/plain"
out=$(run_hook "{\"cwd\":\"$tmp/plain\"}")
check "not a git repo: silent" [ -z "$out" ]
check "not a git repo: exits 0" [ "$(status)" = 0 ]
out=$(run_hook 'not json at all')
check "bad JSON: exit 0" [ "$(status)" = 0 ]
out=$(run_hook '')
check "empty stdin: exit 0" [ "$(status)" = 0 ]
out=$(run_hook '{"cwd":"/nonexistent/dir"}')
check "missing cwd dir: exit 0" [ "$(status)" = 0 ]

# 7. never prints a decision
set_age "$repo/docs/progress/a.md" 60 2>/dev/null || { printf 'x\n' >"$repo/docs/progress/a.md"; set_age "$repo/docs/progress/a.md" 60; }
out=$(run_hook "{\"cwd\":\"$repo\"}")
no_decision() { case $1 in *'"decision"'* | '{'*) return 1 ;; *) return 0 ;; esac; }
check "stale notice is plain text, no decision JSON" no_decision "$out"

printf '%s passed, %s failed\n' "$pass" "$fail"
[ "$fail" = 0 ]
