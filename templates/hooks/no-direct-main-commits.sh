#!/usr/bin/env bash
# no-direct-main-commits.sh
# γ-enforcer for Peer-Worker Convergence.
#
# Pre-commit hook for the canonical clone. Rejects any commit attempt
# unless the operator has explicitly bypassed via the BYPASS_GAMMA
# environment variable.
#
# Install (canonical clone only):
#   1. cp this file to .git/hooks/pre-commit and `chmod +x` it.
#   2. `touch .canonical-clone` at the repo root. This marker is what ARMS
#      the hook (see the check below). WITHOUT THE MARKER THE HOOK SILENTLY
#      NO-OPS and direct commits to main are allowed - defeating rule γ.
# Do NOT install in worker trees - workers SHOULD accept commits; only the
# canonical clone should not (and worker trees must NOT carry the marker).
#
# Why a bypass mechanism exists:
# Operators occasionally need to commit directly to main - release tags,
# manual recovery operations, ceremonial commits. Forbidding all direct
# commits unconditionally would make these legitimate operations
# impossible. The bypass is intentionally awkward (an env var, not a CLI
# flag) so it's deliberate. If you find yourself bypassing routinely,
# the protocol isn't fitting the work - investigate.

set -euo pipefail

REPO_ROOT="$(git rev-parse --show-toplevel)"

# Convention: the canonical clone's root contains a marker file
# (.canonical-clone) created at clone-setup time (install step 2 above). It
# is what distinguishes the canonical clone from a worker tree. If the marker
# is absent, this hook treats the repo as a worker tree and allows the commit
# - so a canonical clone WITHOUT the marker silently disarms γ. Adjust the
# convention if your project uses a different one.
if [[ ! -f "$REPO_ROOT/.canonical-clone" ]]; then
  # Not in the canonical clone (no marker). Worker trees may commit freely.
  exit 0
fi

if [[ "${BYPASS_GAMMA:-}" == "1" ]]; then
  echo "γ-enforcer: BYPASSED (BYPASS_GAMMA=1). Direct commit to main allowed." >&2
  echo "γ-enforcer: log the rationale in DECISIONS_LOG." >&2
  exit 0
fi

cat >&2 <<EOF
γ-enforcer: REFUSED - direct commit to main is forbidden by Peer-Worker Convergence rule γ.

All commits must land via a worker (workerN/main → β-merge to main).

If you genuinely need to commit directly to main (release tag, manual recovery,
ceremonial commit): set BYPASS_GAMMA=1 and re-attempt. Document the rationale
in DECISIONS_LOG.

If you reached here by accident: switch to a worker tree and commit there instead.
EOF
exit 1
