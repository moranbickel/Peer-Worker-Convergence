#!/usr/bin/env bash
# session-end-check.sh
# β-enforcer for Peer-Worker Convergence.
#
# Refuses to allow a worker session to close while it has commits that
# haven't reached origin/main. This is the highest-leverage enforcer in
# the protocol - its job is to prevent the 274-commit drift failure mode
# by mechanically refusing the close-without-β path.
#
# Usage: invoke as the last thing a session does, before close.
#   ./session-end-check.sh /path/to/workerN
#
# Exit codes:
#   0 - session may close (worker is converged)
#   1 - session cannot close (worker has unmerged commits; run β first)
#   2 - error (worker tree missing, origin unreachable, etc.)
#
# Why this is the highest-leverage enforcer:
# The session-start tripwire (α) catches stale state at session start -
# important, but recoverable: you pull main and continue. The pre-commit
# hook (γ) blocks accidents at commit-time - important, but the affected
# commits are obvious and easy to retry. This check is different: the
# failure mode it prevents (stranded commits piling up over weeks) is
# invisible until you happen to look, and the cost grows nonlinearly with
# time. A 5-commit drift takes minutes to recover; a 274-commit drift
# takes hours. The enforcer's value is exactly proportional to how much
# operator fatigue it absorbs.

set -euo pipefail

WORKER_DIR="${1:-}"
if [[ -z "$WORKER_DIR" ]]; then
  echo "usage: $0 /path/to/workerN" >&2
  exit 2
fi

if [[ ! -e "$WORKER_DIR/.git" ]]; then
  echo "error: $WORKER_DIR is not a git worktree" >&2
  exit 2
fi

# Refresh remote state. Non-optional - the check is meaningless against
# a stale view of origin/main.
if ! git -C "$WORKER_DIR" fetch origin --quiet 2>/dev/null; then
  echo "error: could not fetch origin (is it reachable?)" >&2
  exit 2
fi

# Count commits on the worker branch that are not yet on origin/main.
# If this is non-zero, β hasn't run.
STRANDED=$(git -C "$WORKER_DIR" rev-list --count origin/main..HEAD)

if [[ "$STRANDED" == "0" ]]; then
  echo "session-end-check: worker is converged (0 stranded commits)."
  exit 0
fi

cat >&2 <<EOF
session-end-check: REFUSED - worker has $STRANDED commit(s) not on origin/main.

Run β before closing this session. See PROTOCOL.md §β for the procedure.

Stranded commits:
$(git -C "$WORKER_DIR" log origin/main..HEAD --oneline)

If you genuinely intend to leave these stranded (e.g., the session is being
suspended rather than closed), document the rationale in DECISIONS_LOG before
overriding this check.
EOF
exit 1
