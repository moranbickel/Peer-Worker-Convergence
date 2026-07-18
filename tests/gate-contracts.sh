#!/usr/bin/env bash
# gate-contracts.sh - exit-code contract tests for the enforcer scripts.
#
# These are the *gates*: scripts whose exit code decides whether an action
# is allowed. A gate that silently fails open (exit 0 when it should
# refuse) is worse than no gate, so its contract is worth pinning with a
# test. Each fixture builds a throwaway git repo, drives the gate, and
# asserts the exact exit code the gate promises.
#
# Covered here:
#   - templates/hooks/no-direct-main-commits.sh  (gamma-enforcer, marker-armed)
#   - templates/hooks/session-end-check.sh        (beta-enforcer, drift refusal)
#
# The session-start tripwire and concurrent-beta script are advisory /
# ceremony helpers rather than gates; `bash -n` in smoke.sh covers their
# cheap failure mode, and they are intentionally not pinned here.
#
# The fixtures are hermetic: they neutralize any global/system git config
# (GIT_CONFIG_GLOBAL / GIT_CONFIG_NOSYSTEM) so an ambient hooksPath, a
# global pre-push hook, or an autocrlf setting on the contributor's machine
# cannot interfere with the throwaway repos.
#
# Run from anywhere:  bash tests/gate-contracts.sh
#
# Exit codes:
#   0 - every contract held
#   1 - one or more contracts were violated
#
# Portable to bash 3.2+ (no mapfile). Requires: git.

set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GAMMA_HOOK="$ROOT/templates/hooks/no-direct-main-commits.sh"
BETA_CHECK="$ROOT/templates/hooks/session-end-check.sh"

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

# Hermetic git: no global, no system config leaks into the fixtures.
export GIT_CONFIG_NOSYSTEM=1
export GIT_CONFIG_GLOBAL="$WORK/gitconfig"
: > "$GIT_CONFIG_GLOBAL"

PASS=0
FAIL=0
pass() { echo "  ok    $1"; PASS=$((PASS + 1)); }
fail() { echo "  FAIL  $1" >&2; FAIL=$((FAIL + 1)); }

# Assert a command exits with an exact code. Usage: expect <code> <label> -- <cmd...>
expect() {
  local want="$1" label="$2"
  shift 3 # drop want, label, and the literal "--"
  local got=0
  "$@" >/dev/null 2>&1 || got=$?
  if [ "$got" -eq "$want" ]; then
    pass "$label (exit $got)"
  else
    fail "$label (expected exit $want, got $got)"
  fi
}

# A git wrapper that always carries a test identity, disables signing, and
# keeps line endings untouched, so the harness works on any machine.
g() {
  git -c user.email=test@example.com -c user.name=test \
      -c commit.gpgsign=false -c core.autocrlf=false \
      -c protocol.file.allow=always "$@"
}

echo "gate-contracts: no-direct-main-commits.sh (gamma-enforcer)"

# The hook arms on the .canonical-clone marker at the repo root - NOT on the
# branch name. Marker present + no bypass => refuse; marker absent => allow
# (worker tree); marker present + BYPASS_GAMMA=1 => allow (deliberate escape).
gamma_repo="$WORK/gamma"
g init -q -b main "$gamma_repo"

# Allow-path: no marker (this is what a worker tree looks like).
expect 0 "worker tree (no marker) is allowed" -- \
  bash -c "cd '$gamma_repo' && bash '$GAMMA_HOOK'"

# Reject-path: arm the gate with the marker. Same invocation as the
# allow-path above - only the marker differs, which is what proves the
# fixture discriminates rather than always-refusing.
touch "$gamma_repo/.canonical-clone"
expect 1 "canonical clone (marker present) is refused" -- \
  bash -c "cd '$gamma_repo' && bash '$GAMMA_HOOK'"

# Deliberate escape: marker present but BYPASS_GAMMA=1.
expect 0 "canonical clone with BYPASS_GAMMA=1 is allowed" -- \
  env BYPASS_GAMMA=1 bash -c "cd '$gamma_repo' && bash '$GAMMA_HOOK'"

echo "gate-contracts: session-end-check.sh (beta-enforcer)"

# Build a bare origin with one commit on main, then a worker clone of it.
origin="$WORK/origin.git"
seed="$WORK/seed"
worker="$WORK/worker"
g init -q --bare -b main "$origin"
g clone -q "$origin" "$seed"
echo "one" > "$seed/file.txt"
g -C "$seed" add file.txt
g -C "$seed" commit -q -m "initial commit"
g -C "$seed" push -q origin main
g clone -q "$origin" "$worker"
# Let the hook's internal `git fetch origin` succeed against a local path
# even on runners that restrict the file transport by default.
g -C "$worker" config protocol.file.allow always

# In-sync: worker HEAD == origin/main => 0 stranded => allow.
expect 0 "converged worker (0 stranded) may close" -- bash "$BETA_CHECK" "$worker"

# Stranded: worker commits ahead of origin/main without pushing => refuse.
echo "two" > "$worker/file.txt"
g -C "$worker" add file.txt
g -C "$worker" commit -q -m "unmerged local commit"
expect 1 "worker with an unmerged commit is refused" -- bash "$BETA_CHECK" "$worker"

# Error contract: missing argument => 2 (not 0, not 1).
expect 2 "missing worker-dir argument is an error" -- bash "$BETA_CHECK"

# Error contract: a path that is not a git worktree => 2.
notgit="$WORK/notgit"
mkdir -p "$notgit"
expect 2 "non-git path is an error" -- bash "$BETA_CHECK" "$notgit"

echo ""
echo "gate-contracts: $PASS passed, $FAIL failed."
if [ "$FAIL" -ne 0 ]; then
  exit 1
fi
exit 0
