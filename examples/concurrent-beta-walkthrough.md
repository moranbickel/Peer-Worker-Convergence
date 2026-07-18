# Concurrent-β Walkthrough

A full end-to-end walkthrough of two operator-driven sessions converging through main during the same operating window, including a β collision and the precision-target side-branch recovery.

The scenario: two worker trees (`worker1` and `worker2`) on a shared repo. One operator (you) is alternating attention between them across an afternoon. Each worker is mid-stream on its own scope:

- `worker1` - refactoring a payment-handling module. Three commits today.
- `worker2` - updating documentation across several files, including STATUS_NOW and DECISIONS_LOG. Five commits today.

Both workers need to land before end of day. Neither knows about the other's commits until convergence happens.

This walkthrough shows: both workers running α at session start, both workers committing independently, both attempting β around the same time, the collision that follows, and the resolution.

---

## Timeline

| Wall clock | worker1 (refactor) | worker2 (docs) |
|---|---|---|
| 09:00 | α - `git fetch && git merge --ff-only origin/main` ✓ | - |
| 09:30 | Commit 1: refactor payment-validation function. | - |
| 10:00 | - | α - `git fetch && git merge --ff-only origin/main` ✓ |
| 10:15 | Commit 2: update payment-handler tests. | - |
| 10:30 | - | Commit 1: update STATUS_NOW with today's docs scope. |
| 11:00 | Commit 3: add error-handling for new edge case. | Commit 2: update DECISIONS_LOG. |
| 11:30 | - | Commit 3: rewrite section 2 of architecture doc. |
| 13:30 | - | Commit 4: rewrite section 3 of architecture doc. |
| 14:00 | (no further commits today; ready for β) | - |
| 14:30 | - | Commit 5: update STATUS_NOW with end-of-day state. |
| 15:00 | β.1 - `git push origin worker1/main` ✓ | - |
| 15:01 | canonical-clone: `git merge --ff-only worker1/main` ✓ | - |
| 15:02 | `git push origin main` ✓ - worker1 β complete. | - |
| 15:05 | - | β.1 - `git push origin worker2/main` ✓ |
| 15:06 | - | canonical-clone: `git merge --ff-only worker2/main` **fails** - not fast-forwardable. |

This is the moment. The world changed under worker2's β.1: worker1 landed first, main moved, worker2's β.1 can't ff-merge anymore.

worker2 doesn't panic-merge. It switches to β.2.

---

## worker2's β.2 ceremony

```bash
# Step 1: identify worker2's exact commits to ship, relative to current origin/main
COMMITS=$(git -C /repo/worker2 log origin/main..worker2/main --pretty=%H --reverse)
echo "$COMMITS"
# Output (5 SHAs):
#   abc1234... (Commit 1: update STATUS_NOW)
#   def5678... (Commit 2: update DECISIONS_LOG)
#   ghi9abc... (Commit 3: rewrite section 2)
#   jkl0def... (Commit 4: rewrite section 3)
#   mno1234... (Commit 5: update STATUS_NOW eod)
```

The commit range is computed against *current* `origin/main`, which now includes worker1's three commits. The cherry-pick will land worker2's five commits on top of worker1's three.

```bash
# Step 2: create the side-branch in canonical clone, rooted at current origin/main
cd /repo/canonical-clone
git fetch origin
BUNDLE="worker2-bundle-20260520-150700"
git checkout -b "$BUNDLE" origin/main
```

`origin/main` here already has worker1's commits. The side-branch starts from the latest canonical truth.

```bash
# Step 3: cherry-pick worker2's commits in order
for sha in $COMMITS; do
  git cherry-pick "$sha" || break
done
```

The first cherry-pick (`abc1234`, worker2's STATUS_NOW update) conflicts. worker1 didn't touch STATUS_NOW, but worker2 updated it based on yesterday's main; the current main has a STATUS_NOW update from elsewhere (the previous session's β-merge that worker2 didn't see).

`git status`:
```
On branch worker2-bundle-20260520-150700
You are currently cherry-picking commit abc1234.

Unmerged paths:
  both modified:   docs/STATUS_NOW.md
```

Resolution per the shared-file playbook: **living state, newest-by-mtime wins**. worker2's update is the newer state; accept worker2's version.

```bash
git checkout --theirs docs/STATUS_NOW.md
git add docs/STATUS_NOW.md
git cherry-pick --continue
```

The remaining four commits cherry-pick cleanly: they touch DECISIONS_LOG (append-only) and architecture docs that worker1 didn't touch.

```bash
# Step 4: push the side-branch
git push origin "$BUNDLE"

# Step 5: merge side-branch into main (ff-only)
git checkout main
git fetch origin
git merge --ff-only "$BUNDLE"
git push origin main
```

`git merge --ff-only` succeeds because the side-branch was rooted at `origin/main` at step 2 and has only forward progress since.

```bash
# Step 6: verification
git merge-base --is-ancestor "$BUNDLE" origin/main; echo $?
# Output: 0   (ancestor - every cherry-picked commit is reachable from main)

# Step 7: clean up the side-branch
git branch -d "$BUNDLE"
git push origin --delete "$BUNDLE"
```

worker2's β is complete.

---

## Final state

```
origin/main:
  ├── merge-commit: "Merge bundle worker2-bundle-20260520-150700 into main"
  │     ├── worker2 commit 5 (STATUS_NOW eod)
  │     ├── worker2 commit 4 (section 3)
  │     ├── worker2 commit 3 (section 2)
  │     ├── worker2 commit 2 (DECISIONS_LOG)
  │     └── worker2 commit 1 (STATUS_NOW) [conflict resolved against worker1-era main]
  ├── worker1 commit 3 (error-handling)
  ├── worker1 commit 2 (tests)
  ├── worker1 commit 1 (refactor)
  └── (earlier commits)
```

Both workers' scopes are exact. No attribution blur: every commit is reachable from main via either the worker1 fast-forward range or the worker2 side-branch merge. A reader of `git log` can reconstruct who shipped what.

Verification across all workers:

```bash
git -C /repo/worker1 rev-list --count HEAD..origin/main
# 5  (main is ahead by worker2's 5 commits - worker1 will catch up at next α)

git -C /repo/worker2 rev-list --count HEAD..origin/main
# 0  (worker2 just β'd; in sync)

git -C /repo/worker1 rev-list --count origin/main..origin/worker1/main
# 0  (no stranded commits on worker1)

git -C /repo/worker2 rev-list --count origin/main..origin/worker2/main
# 0  (no stranded commits on worker2)
```

All four checks pass. Convergence complete.

---

## What was non-obvious

Four moves in this walkthrough are worth calling out because they're easy to get wrong:

**1. worker2 didn't panic when β.1 failed.** The fast-path failure was the signal to switch ceremonies, not the signal to force-merge. The β.1 → β.2 fallback is intended behavior.

**2. The cherry-pick range was computed against *current* `origin/main`, not yesterday's.** `git log origin/main..worker2/main` re-reads main as it exists right now, which includes worker1's commits. A stale cached range would have shipped wrong.

**3. The side-branch was rooted at `origin/main`, not at `worker2/main`.** If worker2 had used `git checkout -b worker2-bundle worker2/main`, the side-branch would have inherited worker2's stale base, and the final merge to main wouldn't ff-only cleanly. Rooting at canonical is what makes the bundle scope-exact.

**4. STATUS_NOW resolution was *binary*, not hybrid.** worker2 took its own version (newer-by-mtime). It did not try to merge worker2's intent with the main-era content. The playbook is binary because hybrid resolutions produce fictional state.

The whole ceremony, including the conflict, took about three minutes. The 274-commit recovery would have taken hours.

---

## What if both workers β'd at exactly the same moment?

The walkthrough has worker1 finishing β about three minutes before worker2 started. What about the truly simultaneous case?

`git push origin main` is atomic at the remote: either the push is a fast-forward (succeeds) or it isn't (rejected). If two workers race to push main:

- The first push wins (fast-forwards canonical).
- The second push fails with `non-fast-forward` rejection.
- The loser fetches, discovers the change, and re-runs β.2 with a fresh side-branch rooted at the now-updated `origin/main`.

The "race" reduces to one worker doing β.2 against an origin that briefly was something else. There's no scenario where both pushes succeed; the canonical artifact's fast-forward property prevents it.

The shared-worktree race problem (two sessions on one worker tree) is a different failure mode: that one isn't prevented by atomic remote operations. See [`PROTOCOL.md`](../PROTOCOL.md) §"The shared-worktree race problem".

---

← Back to [`README.md`](../README.md) · [`PROTOCOL.md`](../PROTOCOL.md)

- Moran Bickel
