#!/bin/sh
# Stop hook: tell the session when a long task's progress file has gone stale.
#
# Reads the Stop hook JSON on stdin (only `cwd` is used; $PWD when absent). When the git work tree at that
# directory has a docs/progress/*.md file whose mtime is older than 20 minutes, prints one factual line per file:
#   progress file <path> last updated <n> minutes ago
# (<path> is absolute) and prints nothing otherwise. It never prints a decision or a JSON body and always exits 0 (never 2), so it
# cannot block or re-prompt a session; the notice is information only.
#
# Environment (for tests): PROGRESS_STALE_MINUTES overrides the 20 minute threshold.
# Portable: POSIX sh, GNU or BSD stat.

threshold=${PROGRESS_STALE_MINUTES:-20}
case $threshold in '' | *[!0-9]*) threshold=20 ;; esac

input=$(cat 2>/dev/null || true)
cwd=$(printf '%s' "$input" | sed -n 's/.*"cwd"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -n 1)
[ -n "$cwd" ] && [ -d "$cwd" ] || cwd=$PWD

root=$(git -C "$cwd" rev-parse --show-toplevel 2>/dev/null) || exit 0
[ -n "$root" ] || exit 0

now=$(date +%s 2>/dev/null) || exit 0

for file in "$root"/docs/progress/*.md; do
  [ -f "$file" ] || continue
  mtime=$(stat -c %Y "$file" 2>/dev/null || stat -f %m "$file" 2>/dev/null) || continue
  case $mtime in '' | *[!0-9]*) continue ;; esac
  minutes=$(((now - mtime) / 60))
  if [ "$minutes" -gt "$threshold" ]; then
    printf 'progress file %s last updated %s minutes ago\n' "$file" "$minutes"
  fi
done

exit 0
