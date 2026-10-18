#!/usr/bin/env sh
# Validate every skill under skills/: SKILL.md present, frontmatter has
# `name` (== directory name) and a non-empty `description`; bundled shell
# scripts pass `sh -n` and shellcheck (when installed). Exit 1 on any failure.
set -u
ROOT=$(cd "$(dirname "$0")/.." && pwd)
fail=0
err() { echo "FAIL: $*" >&2; fail=1; }

for dir in "$ROOT"/skills/*/; do
  [ -d "$dir" ] || continue
  name=$(basename "$dir")
  md="$dir/SKILL.md"
  if [ ! -f "$md" ]; then err "$name: missing SKILL.md"; continue; fi
  [ "$(sed -n 1p "$md")" = "---" ] || err "$name: SKILL.md must start with --- frontmatter"
  fm=$(awk 'NR==1{next} /^---$/{exit} {print}' "$md")
  fm_name=$(printf '%s\n' "$fm" | sed -n 's/^name:[[:space:]]*//p' | head -n 1)
  [ "$fm_name" = "$name" ] || err "$name: frontmatter name is '$fm_name', expected '$name'"
  printf '%s\n' "$fm" | grep -q '^description:[[:space:]]*[^[:space:]]' || err "$name: frontmatter needs a non-empty description"
  for sh_file in "$dir"/scripts/*.sh; do
    [ -f "$sh_file" ] || continue
    sh -n "$sh_file" || err "$name: $(basename "$sh_file") has a syntax error"
    if command -v shellcheck >/dev/null 2>&1; then
      shellcheck "$sh_file" || err "$name: shellcheck failed on $(basename "$sh_file")"
    fi
  done
  echo "ok: $name"
done
exit $fail
