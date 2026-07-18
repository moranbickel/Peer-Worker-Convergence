# Peer-Worker Convergence - α/β/γ Checklist

| Rule | When | Action |
|---|---|---|
| **α** | Session start | `git fetch origin && git merge origin/main` (ff-only if possible) |
| **β** | Session end | Push `workerN/main`; β.1 ff-merge → main OR β.2 side-branch ceremony; push main |
| **γ** | Forever | No direct commits to main. All work via workers. |

**β.1 fast-path:** push worker, ff-merge in canonical clone, push main. Use when no concurrent β is in flight.

**β.2 side-branch (default for 2+ workers):** cherry-pick worker commits onto a fresh branch from `origin/main`, push side-branch, ff-merge into main, push, verify with `git merge-base --is-ancestor`.

**If β.1 fails:** switch to β.2. The fast-path failure is the signal to switch ceremonies, not to force-merge.

Full ceremony in [`PROTOCOL.md`](../PROTOCOL.md). Worked example with collision in [`examples/concurrent-beta-walkthrough.md`](../examples/concurrent-beta-walkthrough.md).
