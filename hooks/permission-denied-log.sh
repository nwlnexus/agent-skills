#!/bin/sh
# PermissionDenied hook: append every auto-mode denial to a local JSON Lines log.
#
# Reads the PermissionDenied hook JSON on stdin and appends one line
#   {"ts","account","cwd","tool","tool_input","reason"}
# to ${XDG_STATE_HOME:-$HOME/.local/state}/agent/denials.jsonl (directory 0700, file 0600; the log holds the
# denied tool_input, which can include command lines). `account` is the basename of $CLAUDE_CONFIG_DIR, or
# `default` when it is unset. `ts` is UTC, RFC 3339.
#
# It never writes to stdout (so it never returns a retry decision), never exits 2 and exits 0 on every path:
# a logging failure must not change what the session sees. Without jq, or when stdin is not a JSON object,
# it still appends a line, with null fields and an "error" member, so the denial is counted.
# Design: nwlnexus/olympus-sdk#576 (spec decision H19, layer 3). Not wired anywhere by this repo.

exec >/dev/null 2>&1
trap 'exit 0' EXIT

umask 077
state=${XDG_STATE_HOME:-${HOME:-}/.local/state}
case $state in /*) ;; *) exit 0 ;; esac
dir=$state/agent
log=$dir/denials.jsonl

mkdir -p "$dir" || exit 0
chmod 700 "$dir"
[ -e "$log" ] || : >>"$log" || exit 0
chmod 600 "$log"

ts=$(date -u +%Y-%m-%dT%H:%M:%SZ)
if [ -n "${CLAUDE_CONFIG_DIR:-}" ]; then
  account=$(basename "$CLAUDE_CONFIG_DIR")
else
  account=default
fi

input=$(cat)

line=""
if command -v jq >/dev/null; then
  line=$(printf '%s' "$input" | jq -c --arg ts "$ts" --arg account "$account" '
    if type == "object" then
      {ts: $ts, account: $account, cwd: (.cwd // null), tool: (.tool_name // null),
       tool_input: (.tool_input // null), reason: (.reason // null)}
    else error("not an object") end' | head -n 1)
  if [ -z "$line" ]; then
    line=$(jq -cn --arg ts "$ts" --arg account "$account" \
      '{ts: $ts, account: $account, cwd: null, tool: null, tool_input: null, reason: null,
        error: "hook input is not a JSON object"}')
  fi
fi
if [ -z "$line" ]; then
  # No jq: keep only characters that need no JSON escaping in the account name.
  safe=$(printf '%s' "$account" | tr -cd 'A-Za-z0-9._-')
  line=$(printf '{"ts":"%s","account":"%s","cwd":null,"tool":null,"tool_input":null,"reason":null,"error":"jq not found"}' "$ts" "$safe")
fi

printf '%s\n' "$line" >>"$log"
exit 0
