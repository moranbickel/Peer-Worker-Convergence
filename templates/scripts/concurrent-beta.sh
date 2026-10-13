#!/usr/bin/env bash
#
# concurrent-beta.sh - precision-target side-branch β-merge (Peer-Worker Convergence, β.2)
#
# Prepares a worker branch's unique commits for canonical main WITHOUT absorbing a
# concurrent worker's pushed-but-unmerged commits. It cherry-picks the worker's
# exact commits onto a fresh side-branch rooted at origin/main and pushes that
# side-branch. The side-branch contains only the chosen scope, by construction -
# so attribution stays exact even when two workers β at roughly the same time.
#
# DEFAULT: publish the side-branch and stop. Nothing touches local or remote
# main. If the GitHub CLI (`gh`) is on PATH and origin is a GitHub remote, a pull
# request is opened and its URL printed; otherwise the exact PR / compare
# instructions are printed. Landing is then your repository's normal review and
# merge process, which works under branch protection.
#
# OPT-IN: --direct-main (or PWC_DIRECT_MAIN=1) restores the older behaviour:
# fast-forward local main to the side-branch and `git push origin main`. This
# FAILS under branch protection / required reviews and publishes without review.
# Use it only on repositories you control that have no protection on main.
#
# This automates the manual ceremony in README.md ("Concurrent-aware β") and
# PROTOCOL.md. Copy it into your own repo (e.g. as scripts/concurrent-beta.sh)
# and run it from the canonical clone - the checkout that tracks origin/main.
#
# Usage:
#   ./concurrent-beta.sh [--direct-main] <worker> [canonical-branch]
#
#   <worker>            worker name; the worker branch is "<worker>/main" on origin
#                       (e.g. "worker1" -> origin/worker1/main)
#   [canonical-branch]  canonical branch name; defaults to "main"
#   --direct-main       opt in to pushing main directly (see above)
#
# Environment:
#   PWC_DIRECT_MAIN=1   same as --direct-main
#   PWC_GH=<command>    the GitHub CLI to use instead of `gh` (default: gh)
#
# Example:
#   ./concurrent-beta.sh worker1
#
# Exit codes:
#   0  success (or nothing to ship). A missing or failing `gh` is not an error.
#   1  cherry-pick conflict - resolve by hand (see PROTOCOL.md §Recovery)
#   2  usage / precondition error
#
# Portable to bash 3.2+ (no mapfile). Requires: git. Optional: gh.

set -euo pipefail

USAGE="usage: concurrent-beta.sh [--direct-main] <worker> [canonical-branch]"

DIRECT="${PWC_DIRECT_MAIN:-0}"
POSITIONAL=()
for arg in "$@"; do
  case "$arg" in
    -h|--help) echo "$USAGE" >&2; exit 0 ;;
    --direct-main) DIRECT=1 ;;
    -*) echo "error: unknown option: ${arg}" >&2; echo "$USAGE" >&2; exit 2 ;;
    *) POSITIONAL+=("$arg") ;;
  esac
done

if [ "${#POSITIONAL[@]}" -eq 0 ] || [ "${#POSITIONAL[@]}" -gt 2 ]; then
  echo "$USAGE" >&2
  exit 2
fi

WORKER="${POSITIONAL[0]}"
MAIN="${POSITIONAL[1]:-main}"
WORKER_REF="${WORKER}/main"
SIDE="${WORKER}-bundle-$(date +%Y%m%d-%H%M%S)"
GH_BIN="${PWC_GH:-gh}"

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
if [ "$DIRECT" = "1" ]; then
  echo "Shipping ${COUNT} commit(s) from origin/${WORKER_REF} onto ${MAIN} via ${SIDE} (direct-main mode):"
else
  echo "Preparing ${COUNT} commit(s) from origin/${WORKER_REF} for review against ${MAIN} via ${SIDE}:"
fi
git log "origin/${MAIN}..origin/${WORKER_REF}" --oneline --reverse

# Remember where we started so default mode can leave the checkout as it found it.
START_BRANCH="$(git symbolic-ref -q --short HEAD || true)"

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

# 4. Push the side-branch.
git push origin "$SIDE"

if [ "$DIRECT" = "1" ]; then
  # 5a. OPT-IN: ff-merge into main and push main. Fails under branch protection.
  git checkout "$MAIN"
  git merge --ff-only "$SIDE"
  git push origin "$MAIN"

  echo ""
  echo "Done. ${COUNT} commit(s) from ${WORKER_REF} landed on ${MAIN} via ${SIDE} (clean ff-merge, direct-main mode)."
  echo "Clean up the side-branch when ready:"
  echo "  git push origin --delete ${SIDE}"
  echo "  git branch -D ${SIDE}"
  exit 0
fi

# 5b. DEFAULT: leave main alone. Put the checkout back, then propose the branch.
if [ -n "$START_BRANCH" ] && [ "$START_BRANCH" != "$SIDE" ]; then
  git checkout -q "$START_BRANCH"
fi

# GitHub remote? Read the configured URL (not the rewritten one).
REMOTE_URL="$(git config --get remote.origin.url || true)"
GITHUB_SLUG=""
case "$REMOTE_URL" in
  *github.com[:/]*)
    GITHUB_SLUG="$(printf '%s\n' "$REMOTE_URL" | sed -e 's#^.*github\.com[:/]##' -e 's#/*$##' -e 's#\.git$##')"
    ;;
esac

echo ""
echo "Published ${SIDE} (${COUNT} commit(s) from ${WORKER_REF}). ${MAIN} was not changed."

PR_OPENED=0
if [ -n "$GITHUB_SLUG" ] && command -v "$GH_BIN" >/dev/null 2>&1; then
  if PR_OUT="$("$GH_BIN" pr create --base "$MAIN" --head "$SIDE" --fill 2>&1)"; then
    PR_OPENED=1
    echo "Pull request:"
    printf '%s\n' "$PR_OUT"
  else
    echo "note: '${GH_BIN} pr create' failed; open the pull request by hand instead:" >&2
    printf '%s\n' "$PR_OUT" >&2
  fi
fi

if [ "$PR_OPENED" -eq 0 ]; then
  echo "Next: open a pull request (merge request) with base ${MAIN} and head ${SIDE}."
  if [ -n "$GITHUB_SLUG" ]; then
    echo "  https://github.com/${GITHUB_SLUG}/compare/${MAIN}...${SIDE}?expand=1"
    echo "  or, with the GitHub CLI: gh pr create --base ${MAIN} --head ${SIDE} --fill"
  else
    echo "  Use your forge's compare / new pull request page for origin."
  fi
fi

echo ""
echo "After the pull request is merged, clean up:"
echo "  git push origin --delete ${SIDE}   # skip if your forge deletes merged branches"
echo "  git branch -D ${SIDE}"
