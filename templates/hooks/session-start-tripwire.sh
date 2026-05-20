#!/usr/bin/env bash
# session-start-tripwire.sh
# α-enforcer for Peer-Worker Convergence.
#
# Refuses to let a session begin work in a worker that's behind origin/main
# by more than a threshold. Forces α (pull main into worker) to run as the
# first action of every session.
#
# Usage: invoke as the first thing a session does.
#   ./session-start-tripwire.sh /path/to/workerN
#
# Exit codes:
#   0 — worker is sufficiently in sync; session may proceed
#   1 — worker is drifted beyond threshold; α must run before work
#   2 — error (worker tree missing, origin unreachable, etc.)
#
# Why the threshold is configurable:
# Set DRIFT_THRESHOLD too low (e.g., 1) and the tripwire fires every time
# any other worker β-merges — operator fatigue from spurious blocks.
# Set it too high (e.g., 100) and the worker can accumulate enough drift
# that recovery is non-trivial. The default of 10 is a compromise: small
# enough that drift stays cheap to recover, large enough that routine
# in-session-cycle merges don't trigger.
#
# Adjust per project. If you run many short workers, lower it. If your
# convergence cadence is slower (workers cycle daily, not hourly), raise.

set -euo pipefail

WORKER_DIR="${1:-}"
DRIFT_THRESHOLD="${DRIFT_THRESHOLD:-10}"

if [[ -z "$WORKER_DIR" ]]; then
  echo "usage: $0 /path/to/workerN" >&2
  exit 2
fi

if [[ ! -e "$WORKER_DIR/.git" ]]; then
  echo "error: $WORKER_DIR is not a git worktree" >&2
  exit 2
fi

if ! git -C "$WORKER_DIR" fetch origin --quiet 2>/dev/null; then
  echo "error: could not fetch origin (is it reachable?)" >&2
  exit 2
fi

# Count commits on origin/main that aren't yet in the worker's HEAD.
BEHIND=$(git -C "$WORKER_DIR" rev-list --count HEAD..origin/main)

if [[ "$BEHIND" -le "$DRIFT_THRESHOLD" ]]; then
  echo "session-start-tripwire: worker is in sync ($BEHIND commit(s) behind origin/main; threshold $DRIFT_THRESHOLD)."
  exit 0
fi

cat >&2 <<EOF
session-start-tripwire: BLOCKED — worker is $BEHIND commit(s) behind origin/main (threshold: $DRIFT_THRESHOLD).

Run α before any work:
  cd $WORKER_DIR
  git merge --ff-only origin/main    # if no local unique commits
  # OR
  git merge origin/main              # if local unique commits exist; resolve shared-file conflicts per playbook

You're operating against a stale picture of main. Any work you do now will
need to be reconciled with the changes you haven't yet pulled — better to
reconcile them now than to discover them mid-session.
EOF
exit 1
