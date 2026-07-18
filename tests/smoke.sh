#!/usr/bin/env bash
# smoke.sh - syntax + lint floor for every shipped shell script.
#
# The floor: every .sh in the repo must parse under `bash -n` (the hard
# gate - a script that does not parse is broken on arrival), and pass
# `shellcheck` when shellcheck is available on the runner (advisory - a
# missing shellcheck is never a failure, and shellcheck findings are
# reported but do not gate the result). Zero fixtures; this is a static
# check of the shipped scripts as-is.
#
# Run from anywhere:  bash tests/smoke.sh
#
# Exit codes:
#   0 - every script parses under bash -n
#   1 - one or more scripts failed bash -n (or no scripts were found)
#
# Portable to bash 3.2+ (no mapfile / associative arrays).

set -uo pipefail

# Resolve the repo root from this script's location so the result does
# not depend on the caller's working directory.
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT" || exit 1

# Enumerate shipped shell scripts. Prefer git (the authoritative list of
# tracked files); fall back to find for a non-git checkout.
SCRIPTS=()
if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  while IFS= read -r f; do
    SCRIPTS+=("$f")
  done < <(git ls-files '*.sh')
else
  while IFS= read -r f; do
    SCRIPTS+=("${f#./}")
  done < <(find . -type f -name '*.sh')
fi

if [ "${#SCRIPTS[@]}" -eq 0 ]; then
  echo "smoke: no .sh files found under $ROOT" >&2
  exit 1
fi

echo "smoke: checking ${#SCRIPTS[@]} shell script(s) under $ROOT"

# --- Hard gate: bash -n (syntax). Report every failure, not just the first. ---
syntax_errors=0
for s in "${SCRIPTS[@]}"; do
  if bash -n "$s"; then
    echo "  bash -n  ok     $s"
  else
    echo "  bash -n  ERROR  $s" >&2
    syntax_errors=$((syntax_errors + 1))
  fi
done

# --- Advisory: shellcheck (never gates the result). ---
if command -v shellcheck >/dev/null 2>&1; then
  echo "smoke: shellcheck present - running advisory lint (findings do not gate)"
  for s in "${SCRIPTS[@]}"; do
    shellcheck "$s" || true
  done
else
  echo "smoke: shellcheck not found - skipping advisory lint (not a failure)"
fi

if [ "$syntax_errors" -ne 0 ]; then
  echo "smoke: FAIL - $syntax_errors script(s) failed bash -n." >&2
  exit 1
fi

echo "smoke: PASS - all ${#SCRIPTS[@]} script(s) parse under bash -n."
exit 0
