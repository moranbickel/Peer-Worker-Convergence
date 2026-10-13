#!/usr/bin/env bash
# test-concurrent-beta.sh - behavioural tests for templates/scripts/concurrent-beta.sh.
#
# Each case builds a throwaway bare "origin", a canonical clone (where the helper
# runs) and a worker that has pushed <worker>/main, then drives the helper and
# asserts on what actually landed on origin. Nothing touches the network.
#
# Covered:
#   a. default mode pushes the side branch and leaves origin/main (and local main) alone
#   b. default mode with no usable `gh` still succeeds and prints PR instructions
#      (b2: a stub gh is called with the right arguments; b3: a failing gh is non-fatal)
#   c. opt-in direct mode (--direct-main, PWC_DIRECT_MAIN=1) fast-forwards origin/main
#   d. origin/main advancing after the worker started: the side branch is rooted
#      at the NEW origin/main
#   e. cherry-pick conflict: exit 1, origin/main unchanged, nothing published
#   plus: an unknown option is a usage error.
#
# Run from anywhere:  bash tests/test-concurrent-beta.sh
#
# Exit codes: 0 all cases held, 1 one or more failed.
# Portable to bash 3.2+ (no mapfile). Requires: git.

set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HELPER="$ROOT/templates/scripts/concurrent-beta.sh"

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

# Hermetic git: no global/system config leaks into the fixtures.
export GIT_CONFIG_NOSYSTEM=1
export GIT_CONFIG_GLOBAL="$WORK/gitconfig"
: > "$GIT_CONFIG_GLOBAL"
export GIT_AUTHOR_NAME=test GIT_AUTHOR_EMAIL=test@example.com
export GIT_COMMITTER_NAME=test GIT_COMMITTER_EMAIL=test@example.com
export GIT_CONFIG_COUNT=3
export GIT_CONFIG_KEY_0=commit.gpgsign GIT_CONFIG_VALUE_0=false
export GIT_CONFIG_KEY_1=core.autocrlf GIT_CONFIG_VALUE_1=false
export GIT_CONFIG_KEY_2=protocol.file.allow GIT_CONFIG_VALUE_2=always
# The developer's own settings must not leak into the cases.
unset PWC_DIRECT_MAIN PWC_GH

PASS=0
FAIL=0
pass() { echo "  ok    $1"; PASS=$((PASS + 1)); }
fail() { echo "  FAIL  $1" >&2; FAIL=$((FAIL + 1)); }

# is <label> <got> <want>
is() {
  if [ "$2" = "$3" ]; then pass "$1"; else fail "$1 (got '$2', want '$3')"; fi
}
# has <label> <haystack> <needle>
has() {
  case "$2" in *"$3"*) pass "$1";; *) fail "$1 (missing '$3' in: $2)";; esac
}
# lacks <label> <haystack> <needle>
lacks() {
  case "$2" in *"$3"*) fail "$1 (found '$3' in: $2)";; *) pass "$1";; esac
}

N=0
# new_fixture : sets ORIGIN, CANON, WORKER_DIR for a fresh case.
#   origin main = base ; canonical clone tracks it ; worker1/main = base + one commit
new_fixture() {
  N=$((N + 1))
  local d="$WORK/case$N"
  ORIGIN="$d/origin.git"; CANON="$d/canonical"; WORKER_DIR="$d/worker"
  mkdir -p "$d"
  git init -q --bare -b main "$ORIGIN"
  git clone -q "$ORIGIN" "$WORKER_DIR" 2>/dev/null
  echo base > "$WORKER_DIR/shared.txt"
  git -C "$WORKER_DIR" add shared.txt
  git -C "$WORKER_DIR" commit -q -m "base"
  git -C "$WORKER_DIR" push -q origin main
  git clone -q "$ORIGIN" "$CANON" 2>/dev/null
  git -C "$WORKER_DIR" checkout -q -b worker1/main
  echo w1 > "$WORKER_DIR/worker1.txt"
  git -C "$WORKER_DIR" add worker1.txt
  git -C "$WORKER_DIR" commit -q -m "worker1 change"
  git -C "$WORKER_DIR" push -q origin worker1/main
}

# Make the canonical clone's origin look like a GitHub remote while still
# resolving to the local bare repo (insteadOf rewrites only at connect time).
pretend_github() {
  git -C "$CANON" config remote.origin.url "https://github.com/example/repo.git"
  git -C "$CANON" config "url.$ORIGIN.insteadOf" "https://github.com/example/repo.git"
}

origin_main() { git -C "$ORIGIN" rev-parse refs/heads/main; }
first_side() { git -C "$ORIGIN" for-each-ref --format='%(refname:short)' 'refs/heads/worker1-bundle-*' | head -n1; }
# run_helper <args...> : combined output in $OUT, exit status in $RC
run_helper() {
  OUT="$(cd "$CANON" && bash "$HELPER" "$@" 2>&1)"; RC=$?
}

echo "test-concurrent-beta: (a) default mode publishes the side branch only"
# Protects: the safe default. If the helper pushed main here, every adopter with
# branch protection would see a failure and every adopter without it would get an
# unreviewed publication.
new_fixture
main_before="$(origin_main)"
local_main_before="$(git -C "$CANON" rev-parse main)"
run_helper worker1
is "default mode exits 0" "$RC" 0
side="$(first_side)"
[ -n "$side" ] && pass "side branch exists on origin" || fail "side branch exists on origin: $OUT"
is "origin/main unchanged" "$(origin_main)" "$main_before"
is "local main unchanged" "$(git -C "$CANON" rev-parse main)" "$local_main_before"
is "side branch is exactly origin/main plus 1 commit" \
  "$(git -C "$ORIGIN" rev-list --count "main..${side:-main}")" 1
git -C "$ORIGIN" cat-file -e "${side:-main}:worker1.txt" 2>/dev/null \
  && pass "side branch carries the worker commit" || fail "side branch carries the worker commit"
lacks "output does not claim a landing on main" "$OUT" "landed on main"
has "output tells the adopter how to open a PR" "$OUT" "open a pull request"

echo "test-concurrent-beta: (b) no usable gh is not fatal"
# Protects: adopters without the GitHub CLI. The remote is made to look like a
# GitHub remote so the gh branch is genuinely entered, then the gh binary is
# pointed at a name that does not exist.
new_fixture
pretend_github
main_before="$(origin_main)"
PWC_GH=definitely-not-installed-gh run_helper worker1
is "exits 0 without gh" "$RC" 0
side="$(first_side)"
[ -n "$side" ] && pass "side branch still pushed" || fail "side branch still pushed: $OUT"
is "origin/main unchanged" "$(origin_main)" "$main_before"
has "prints the GitHub compare URL" "$OUT" "https://github.com/example/repo/compare/main...$side"

echo "test-concurrent-beta: (b2) gh present: PR is requested with the right arguments"
# Protects: the PR hand-off. A stub gh records its arguments; the helper must ask
# for base=main and head=<side branch>, and show what gh printed.
new_fixture
pretend_github
STUB="$WORK/stub-gh$N"
ARGS="$WORK/gh-args$N"
printf '#!/usr/bin/env bash\necho "$@" > "%s"\necho "https://github.com/example/repo/pull/7"\n' "$ARGS" > "$STUB"
chmod +x "$STUB"
PWC_GH="$STUB" run_helper worker1
is "exits 0 with gh" "$RC" 0
side="$(first_side)"
has "gh called with --base main" "$(cat "$ARGS" 2>/dev/null)" "--base main"
has "gh called with --head <side>" "$(cat "$ARGS" 2>/dev/null)" "--head $side"
has "prints the PR URL" "$OUT" "https://github.com/example/repo/pull/7"

echo "test-concurrent-beta: (b3) gh failing is not fatal"
# Protects: a gh that is installed but unauthenticated must not turn a published
# side branch into a failed run.
new_fixture
pretend_github
STUB="$WORK/stub-gh$N"
printf '#!/usr/bin/env bash\necho "gh: not logged in" >&2\nexit 4\n' > "$STUB"
chmod +x "$STUB"
PWC_GH="$STUB" run_helper worker1
is "exits 0 when gh fails" "$RC" 0
[ -n "$(first_side)" ] && pass "side branch pushed" || fail "side branch pushed"
has "falls back to compare instructions" "$OUT" "compare"

echo "test-concurrent-beta: (c) opt-in direct mode fast-forwards origin/main"
# Protects: the explicit escape hatch for unprotected repos, and that it stays
# opt-in. Same fixture shape as (a); only the opt-in differs, which shows (a) is
# not passing merely because publication is broken.
for how in flag env; do
  new_fixture
  base_main="$(origin_main)"
  if [ "$how" = flag ]; then
    run_helper worker1 --direct-main
  else
    PWC_DIRECT_MAIN=1 run_helper worker1
  fi
  is "direct ($how) exits 0" "$RC" 0
  is "direct ($how): origin/main advanced by one commit" \
    "$(git -C "$ORIGIN" rev-list --count "$base_main..main")" 1
  is "direct ($how): tip is the cherry-picked commit" \
    "$(git -C "$ORIGIN" log -1 --format=%s main)" "worker1 change"
done

echo "test-concurrent-beta: (d) origin/main advances between worker start and helper run"
# Protects: the fetch-first property. A side branch rooted at a stale view of
# main would publish a branch that silently lacks newer work.
new_fixture
peer="$WORK/peer$N"
git clone -q "$ORIGIN" "$peer" 2>/dev/null
echo p > "$peer/peer.txt"
git -C "$peer" add peer.txt
git -C "$peer" commit -q -m "peer lands on main"
git -C "$peer" push -q origin main
new_main="$(origin_main)"
# The canonical clone has NOT fetched yet: its origin/main is stale.
run_helper worker1
is "exits 0" "$RC" 0
side="$(first_side)"
is "side branch is rooted at the NEW origin/main" "$(git -C "$ORIGIN" rev-parse "${side:-main}~1")" "$new_main"
git -C "$ORIGIN" cat-file -e "${side:-main}:peer.txt" 2>/dev/null \
  && pass "side branch has the peer's commit" || fail "side branch has the peer's commit"
git -C "$ORIGIN" cat-file -e "${side:-main}:worker1.txt" 2>/dev/null \
  && pass "side branch has the worker's commit" || fail "side branch has the worker's commit"
is "origin/main untouched" "$(origin_main)" "$new_main"

echo "test-concurrent-beta: (e) cherry-pick conflict"
# Protects: the conflict contract. A conflict must stop the run with exit 1 and
# publish nothing; a helper that pushed a half-built side branch (or main) here
# would turn a recoverable stop into a published partial bundle.
new_fixture
echo "worker edit" > "$WORKER_DIR/shared.txt"
git -C "$WORKER_DIR" commit -q -am "worker edits shared"
git -C "$WORKER_DIR" push -q origin worker1/main
peer="$WORK/peer$N"
git clone -q "$ORIGIN" "$peer" 2>/dev/null
echo "peer edit" > "$peer/shared.txt"
git -C "$peer" commit -q -am "peer edits shared"
git -C "$peer" push -q origin main
main_before="$(origin_main)"
run_helper worker1
is "conflict exits 1" "$RC" 1
is "origin/main unchanged" "$(origin_main)" "$main_before"
is "no side branch published" "$(first_side)" ""
has "prints the recovery message" "$OUT" "Cherry-pick conflict"
# Same conflict in direct mode must also leave main alone. Recover the canonical
# clone first, as the printed recovery steps instruct.
git -C "$CANON" cherry-pick --abort >/dev/null 2>&1
git -C "$CANON" checkout -q main
git -C "$CANON" for-each-ref --format='%(refname:short)' 'refs/heads/worker1-bundle-*' |
  while read -r b; do git -C "$CANON" branch -q -D "$b"; done
run_helper worker1 --direct-main
is "direct-mode conflict exits 1" "$RC" 1
is "direct-mode conflict leaves origin/main unchanged" "$(origin_main)" "$main_before"

echo "test-concurrent-beta: usage"
# Protects: a typo such as --direct_main must not be taken as a worker name or
# silently ignored, either of which would change which mode runs.
new_fixture
run_helper worker1 --no-such-option
is "unknown option exits 2" "$RC" 2
is "unknown option publishes nothing" "$(first_side)" ""

echo ""
echo "test-concurrent-beta: $PASS passed, $FAIL failed."
[ "$FAIL" -eq 0 ] || exit 1
exit 0
