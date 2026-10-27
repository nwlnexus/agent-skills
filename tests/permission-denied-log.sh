#!/bin/sh
# Behaviour tests for hooks/permission-denied-log.sh (the PermissionDenied hook that appends to denials.jsonl).
#   sh tests/permission-denied-log.sh        (needs jq; run by scripts/validate-skills.sh)
set -u
here=$(cd "$(dirname "$0")" && pwd)
hook="$here/../hooks/permission-denied-log.sh"
tmp=$(mktemp -d)
trap 'chmod -R u+w "$tmp" 2>/dev/null; rm -rf "$tmp"' EXIT
pass=0
fail=0

ok() { pass=$((pass + 1)); printf 'ok   %s\n' "$1"; }
bad() { fail=$((fail + 1)); printf 'FAIL %s\n' "$1"; }
check() { # name, command...
  name=$1
  shift
  if "$@"; then ok "$name"; else bad "$name"; fi
}
command -v jq >/dev/null 2>&1 || { echo "FAIL jq is required to run these tests"; exit 1; }

# run_hook <json> [env assignments...]: hook stdout in $tmp/stdout, stderr in $tmp/stderr, status in $tmp/status.
run_hook() {
  input=$1
  shift
  printf '%s' "$input" | env "$@" sh "$hook" >"$tmp/stdout" 2>"$tmp/stderr"
  echo $? >"$tmp/status"
}
status() { cat "$tmp/status"; }
mode() { stat -c %a "$1" 2>/dev/null || stat -f %Lp "$1"; }
lines() { wc -l <"$1" | tr -d ' '; }
last() { tail -n 1 "$1"; }
field() { last "$1" | jq -c "$2"; }
silent() { [ ! -s "$tmp/stdout" ] && [ ! -s "$tmp/stderr" ]; }

bash_denial='{"session_id":"s1","transcript_path":"/x.jsonl","cwd":"/work/repo","permission_mode":"auto","hook_event_name":"PermissionDenied","tool_name":"Bash","tool_input":{"command":"gh pr merge 12 --squash --delete-branch","description":"Merge PR"},"tool_use_id":"toolu_1","reason":"[Production Deploy]"}'

# 1. a Bash denial: one line with the six fields, nothing on stdout or stderr, exit 0
state="$tmp/state"
log="$state/agent/denials.jsonl"
run_hook "$bash_denial" XDG_STATE_HOME="$state" CLAUDE_CONFIG_DIR="$tmp/home/.claude-personal"
check "bash: exits 0" [ "$(status)" = 0 ]
check "bash: nothing on stdout" [ ! -s "$tmp/stdout" ]
check "bash: nothing on stderr" [ ! -s "$tmp/stderr" ]
check "bash: one line" [ "$(lines "$log")" = 1 ]
check "bash: exactly the six keys" [ "$(field "$log" 'keys')" = '["account","cwd","reason","tool","tool_input","ts"]' ]
check "bash: account is the config dir basename" [ "$(field "$log" '.account')" = '".claude-personal"' ]
check "bash: cwd" [ "$(field "$log" '.cwd')" = '"/work/repo"' ]
check "bash: tool" [ "$(field "$log" '.tool')" = '"Bash"' ]
check "bash: tool_input kept as an object" [ "$(field "$log" '.tool_input.command')" = '"gh pr merge 12 --squash --delete-branch"' ]
check "bash: reason" [ "$(field "$log" '.reason')" = '"[Production Deploy]"' ]
check "bash: ts is UTC RFC 3339" sh -c "tail -n 1 '$log' | jq -r .ts | grep -Eq '^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z\$'"
check "directory is 0700" [ "$(mode "$state/agent")" = 700 ]
check "file is 0600" [ "$(mode "$log")" = 600 ]

# 2. a second denial appends; an MCP denial keeps its tool name; no CLAUDE_CONFIG_DIR means account "default"
run_hook '{"cwd":"/w","tool_name":"mcp__memory__forget","tool_input":{"id":"m1"},"mcp_server":{"name":"memory"},"reason":"Classifier unavailable"}' XDG_STATE_HOME="$state" CLAUDE_CONFIG_DIR=
check "append: two lines" [ "$(lines "$log")" = 2 ]
check "append: first line intact" [ "$(head -n 1 "$log" | jq -r .tool)" = Bash ]
check "mcp: tool name" [ "$(field "$log" '.tool')" = '"mcp__memory__forget"' ]
check "unset config dir: account default" [ "$(field "$log" '.account')" = '"default"' ]

# 3. modes are tightened on an existing directory and file
chmod 755 "$state/agent"
chmod 644 "$log"
run_hook "$bash_denial" XDG_STATE_HOME="$state"
check "existing dir re-tightened to 0700" [ "$(mode "$state/agent")" = 700 ]
check "existing file re-tightened to 0600" [ "$(mode "$log")" = 600 ]

# 4. no XDG_STATE_HOME: falls back to $HOME/.local/state
home="$tmp/home2"
mkdir -p "$home"
run_hook "$bash_denial" -u XDG_STATE_HOME HOME="$home"
check "HOME fallback: logged under ~/.local/state/agent" [ "$(lines "$home/.local/state/agent/denials.jsonl")" = 1 ]

# 5. bad input still logs a valid line with an error, and exits 0 silently
s5="$tmp/s5"
for input in 'not json at all' '' '"a string"' '[1,2]'; do
  run_hook "$input" XDG_STATE_HOME="$s5"
  check "bad input '$input': exits 0" [ "$(status)" = 0 ]
  check "bad input '$input': silent" silent
done
check "bad input: one valid line each" [ "$(jq -c 'select(.error == "hook input is not a JSON object")' "$s5/agent/denials.jsonl" | wc -l | tr -d ' ')" = 4 ]
run_hook '{"tool_name":"Bash"} {"tool_name":"Edit"}' XDG_STATE_HOME="$tmp/s5b"
check "two JSON values: one line" [ "$(lines "$tmp/s5b/agent/denials.jsonl")" = 1 ]

# 6. without jq on PATH: still one valid line, account sanitised, exit 0
bin="$tmp/bin"
mkdir -p "$bin"
for t in sh cat date basename mkdir chmod tr head; do
  p=$(command -v "$t") && ln -s "$p" "$bin/$t"
done
run_hook "$bash_denial" PATH="$bin" XDG_STATE_HOME="$tmp/s6" CLAUDE_CONFIG_DIR='/x/we"ird'
check "no jq: exits 0" [ "$(status)" = 0 ]
check "no jq: silent" silent
check "no jq: line is valid JSON with the error" [ "$(jq -r .error "$tmp/s6/agent/denials.jsonl")" = "jq not found" ]
check "no jq: account sanitised" [ "$(jq -r .account "$tmp/s6/agent/denials.jsonl")" = weird ]

# 7. unwritable state directory: exit 0, nothing printed
ro="$tmp/ro"
mkdir -p "$ro"
chmod 500 "$ro"
run_hook "$bash_denial" XDG_STATE_HOME="$ro"
check "unwritable: exits 0" [ "$(status)" = 0 ]
check "unwritable: silent" silent
run_hook "$bash_denial" XDG_STATE_HOME=relative/path HOME=
check "relative state dir: exits 0" [ "$(status)" = 0 ]
check "relative state dir: nothing created" [ ! -e relative/path ]

printf '%s passed, %s failed\n' "$pass" "$fail"
[ "$fail" = 0 ]
