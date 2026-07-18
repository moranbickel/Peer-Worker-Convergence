#!/usr/bin/env bash
#
# concurrent-beta.sh - precision-target side-branch β-merge (Peer-Worker Convergence, β.2)
#
# Ships a worker branch's unique commits to canonical main WITHOUT absorbing a
# concurrent worker's pushed-but-unmerged commits. It does this by cherry-picking
# the worker's exact commits onto a fresh side-branch rooted at origin/main, then
# fast-forward-merging that side-branch into main. The side-branch contains only
# the chosen scope, by construction - so attribution stays exact even when two
# workers β at roughly the same time.
#
# This automates the manual ceremony in README.md ("Concurrent-aware β") and
# PROTOCOL.md. Copy it into your own repo (e.g. as scripts/concurrent-beta.sh)
# and run it from the canonical clone - the checkout that tracks origin/main.
#
# Usage:
#   ./concurrent-beta.sh <worker> [canonical-branch]
#
#   <worker>            worker name; the worker branch is "<worker>/main" on origin
#                       (e.g. "worker1" -> origin/worker1/main)
#   [canonical-branch]  canonical branch name; defaults to "main"
#
# Example:
#   ./concurrent-beta.sh worker1
#
# Exit codes:
#   0  success (or nothing to ship)
#   1  cherry-pick conflict - resolve by hand (see PROTOCOL.md §Recovery)
#   2  usage / precondition error
#
# Portable to bash 3.2+ (no mapfile). Requires: git.

set -euo pipefail

if [ "${1:-}" = "-h" ] || [ "${1:-}" = "--help" ] || [ "$#" -eq 0 ]; then
  echo "usage: concurrent-beta.sh <worker> [canonical-branch]" >&2
  [ "$#" -eq 0 ] && exit 2 || exit 0
fi

WORKER="$1"
MAIN="${2:-main}"
WORKER_REF="${WORKER}/main"
SIDE="${WORKER}-bundle-$(date +%Y%m%d-%H%M%S)"

# 0. Refresh canonical truth before measuring anything.
git fetch origin

# Sanity: the worker branch and canonical branch must exist on origin.
if ! git rev-parse --verify --quiet "origin/${MAIN}" >/dev/null; then
  echo "error: origin/${MAIN} not found. Is this the canonical clone?" >&2
  exit 2
fi
if ! git rev-parse --verify --quiet "origin/${WORKER_REF}" >/dev/null; then
  echo "error: origin/${WORKER_REF} not found. Has ${WORKER} pushed its branch?" >&2
  exit 2
fi

# 1. Identify the exact commits to ship: worker commits not yet on canonical main,
#    oldest-first so cherry-pick replays them in order.
COMMITS="$(git log "origin/${MAIN}..origin/${WORKER_REF}" --pretty=%H --reverse)"
if [ -z "$COMMITS" ]; then
  echo "Nothing to ship: origin/${WORKER_REF} has no commits ahead of origin/${MAIN}."
  exit 0
fi

COUNT="$(printf '%s\n' "$COMMITS" | wc -l | tr -d ' ')"
echo "Shipping ${COUNT} commit(s) from origin/${WORKER_REF} onto ${MAIN} via ${SIDE}:"
git log "origin/${MAIN}..origin/${WORKER_REF}" --oneline --reverse

# 2. Fresh side-branch from origin/main (NOT from the worker branch). Rooting at
#    canonical truth is what keeps a concurrent worker's commits out of this scope.
git checkout -b "$SIDE" "origin/${MAIN}"

# 3. Cherry-pick the worker's commits, in order, onto the side-branch.
for sha in $COMMITS; do
  if ! git cherry-pick "$sha"; then
    echo "" >&2
    echo "Cherry-pick conflict on ${sha}." >&2
    echo "Resolve the conflict, then: git cherry-pick --continue" >&2
    echo "Then finish the ceremony by hand, or: git cherry-pick --abort && git checkout ${MAIN} && git branch -D ${SIDE}" >&2
    echo "See PROTOCOL.md §Recovery for shared-file (STATUS_NOW) and SHA-misidentification cases." >&2
    exit 1
  fi
done

# 4. Push the side-branch, ff-merge into main, push main.
git push origin "$SIDE"
git checkout "$MAIN"
git merge --ff-only "$SIDE"
git push origin "$MAIN"

echo ""
echo "Done. ${COUNT} commit(s) from ${WORKER_REF} landed on ${MAIN} via ${SIDE} (clean ff-merge)."
echo "Clean up the side-branch when ready:"
echo "  git push origin --delete ${SIDE}"
echo "  git branch -D ${SIDE}"
