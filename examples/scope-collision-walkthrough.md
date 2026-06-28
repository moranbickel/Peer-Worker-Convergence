# Scope-Collision Walkthrough

A walkthrough of the third coordination axis: two operator-driven sessions independently doing **the same work**, where convergence and attribution both succeed and you still build the thing twice, and the pick-time ancestry guard that prevents the durable case.

The scenario: two worker trees (`worker1` and `worker2`) on a shared repo, one operator alternating attention across several days. The unit of work is an item with a stable identifier (`FIX-204`, `FIX-205`) landed on canonical with a commit-message convention, `fix(FIX-204): …`. That convention is the only thing the guard reads; substitute your own (a closed-item record, a tag) and nothing else changes.

This walkthrough has two parts. **Part 1** is the collision the guard catches: the work already shipped and a second session is about to redo it. **Part 2** is the collision it can't: two sessions starting the same item before either has landed.

---

## Part 1 — the already-landed collision (what the guard catches)

### Without the guard

`worker1` picks up `FIX-204` on Monday and ships it. `worker2`, in a fresh session on Wednesday with its own context, picks up the same item. The operator, juggling several sessions across the week, has lost track of the fact that it already shipped.

| Wall clock | worker1 | worker2 |
|---|---|---|
| Mon 09:00 | α — `git fetch && git merge --ff-only origin/main` ✓ | — |
| Mon 09:05 | Picks `FIX-204`. | — |
| Mon 11:00 | Commit: `fix(FIX-204): harden the session-end check`. | — |
| Mon 15:00 | β — `fix(FIX-204)` lands on `origin/main`. | — |
| Wed 09:00 | — | α — `git fetch && git merge --ff-only origin/main` ✓ |
| Wed 09:05 | — | Picks `FIX-204` (operator forgot it shipped Monday). |
| Wed 11:00 | — | Commit: `fix(FIX-204): harden the session-end check` *(again)*. |
| Wed 15:00 | — | β.2 — the second `FIX-204` lands cleanly on `origin/main`. |

Note what *didn't* fail. worker2's α succeeded: it pulled main, so its tree literally contains Monday's `fix(FIX-204)` commit. Its β.2 succeeded: the bundle was well-formed, rooted at `origin/main`, attribution exact. Both axes did exactly their jobs. And `origin/main` now carries the same fix twice: a redo commit that re-implements work already present, discovered at review time after Wednesday's session-cost is spent. Convergence asked *did the commits reach main* (yes); attribution asked *whose bundle* (worker2's, cleanly); neither asked *should this work have started at all*.

### With the guard

The guard runs once, at pick time, before worker2 starts:

```bash
# Pick-time ancestry guard — run before starting item X (worker2, Wednesday)
ITEM="FIX-204"

git -C /repo/worker2 fetch origin     # α-freshness: see what has landed since last sync

# Is the item's change already an ancestor of canonical?
if git -C /repo/worker2 log origin/main --grep="fix($ITEM)" --oneline | grep -q .; then
  echo "REFUSE: $ITEM already landed on origin/main — you are about to redo shipped work."
  git -C /repo/worker2 log origin/main --grep="fix($ITEM)" --oneline -1   # show the landing commit
  exit 1
fi
echo "proceed: no fix($ITEM) on canonical"
```

On Wednesday this prints `REFUSE` and the SHA of Monday's commit. worker2 never starts; the redo never happens. The check named no session: not "is someone holding FIX-204," but "is FIX-204's change an ancestor of `origin/main`." The item-ID names the work; ancestry is a fact about the commit graph. Neither rotates when sessions are spawned, isolated, or rolled, so the guard can't go stale the way a claim registry does.

The `git fetch` on the first line is load-bearing; see non-obvious move #2 below.

---

## Part 2 — the in-flight collision (what the guard can't catch)

Now both sessions pick the *same* item on the *same* morning, before either has landed anything.

| Wall clock | worker1 | worker2 |
|---|---|---|
| 09:00 | α ✓. Picks `FIX-205`. Guard: no `fix(FIX-205)` on main → **proceed**. | — |
| 09:02 | — | α ✓. Picks `FIX-205`. Guard: no `fix(FIX-205)` on main → **proceed**. |
| 09:00–14:00 | Implements `FIX-205`. | Implements `FIX-205`. |
| 15:00 | β — `fix(FIX-205)` lands on `origin/main`. | — |
| 15:30 | — | β.2 — the second `FIX-205` lands on `origin/main`. |

Both guards ran. Both were *correct*: at 09:00 and 09:02, nothing matching `fix(FIX-205)` was an ancestor of `origin/main`, because nobody had landed it yet. The guard reported the literal truth of the commit graph, and the commit graph has no entry for "someone is implementing this right now." It cannot distinguish "nobody did this" from "two people are doing this simultaneously," because the only durable evidence either way is a *landed commit*, and at pick time there isn't one.

This is the asymmetric limit, stated plainly: the cheap, common case (work shipped, a peer about to redo it across a multi-day window) is solved by a check that can't rot. The simultaneous case (two peers picking the identical item in the same few minutes) is not, and the protocol doesn't pretend otherwise. Closing the in-flight window needs a live claim layer keyed on session identity, which is exactly the fragile substrate this discipline was built to avoid. Pick-time ancestry is a high-value floor, not a ceiling. (And the floor covers the wider window: across long-lived sessions, "shipped Monday, re-picked Wednesday" happens far more often than "both picked it at 09:00.")

---

## What was non-obvious

Four moves are worth calling out because they're easy to get wrong:

**1. The guard keys on item-ID + ancestry, never on session identity.** The tempting design ("before starting, check who's holding X") names a session, and sessions are unstable: spawned, re-spawned, isolated into fresh worktrees, rotated. A check that names a session goes stale the instant that session stops being the session that exists. A check that names only the work and the commit graph has nothing to go stale.

**2. α-freshness is what makes the ancestry test accurate.** The guard's `git fetch` (or a fresh α) is non-optional. If worker2 ran the check against a stale `origin/main` ref (one fetched before Monday's β), it wouldn't see `fix(FIX-204)`, would conclude "not landed," and would wave the redo through. The third-axis guard and the α tripwire compose: α keeps the picture current; the guard reads the current picture.

**3. The guard is pre-action, not merge-time.** Convergence and attribution both act on commits that already exist: they decide where written work goes. The ancestry guard acts *before* the work is written, at the moment of picking. That's the only place the redo cost can be prevented rather than detected; by merge time the cost is already spent.

**4. The in-flight gap is structural, not a bug to be patched later.** No threshold, script, or cleverness closes it without reintroducing a live claim registry. Naming it as a known limit is the honest move; the alternative (a claim layer that rots) is worse than the gap.

The whole guard is one `git log --grep` against canonical, run once at pick time. The work it prevents, a full re-implementation of something already shipped, is unbounded.

---

← Back to [`README.md`](../README.md) · [`PROTOCOL.md`](../PROTOCOL.md) §"Scope collision — the third axis"

— Moran Bickel
