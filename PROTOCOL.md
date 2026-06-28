# Peer-Worker Convergence Protocol

This is the formal specification of the protocol described informally in [`README.md`](./README.md). The README is the *why*; this is the *how*, with enough specificity that a reader can implement it without ambiguity.

The protocol has three rules, two ceremony shapes, one canonical artifact, and an explicit recovery discipline for when something has already gone wrong.

---

## Topology and vocabulary

Before the rules:

| Term | Meaning |
|---|---|
| **Canonical** | `origin/main`. The single source of truth. Authoritative for every shared file. |
| **Canonical clone** | A working copy of the repo dedicated to β-merge operations. No editing happens here. Worker trees are where work happens; the canonical clone is where convergence happens. |
| **Worker** | A long-lived workspace where an operator-driven session does its work. Implemented as a `git worktree`. |
| **Worker branch** | `workerN/main` — the long-lived branch checked out in a worker. One worker, one branch, persistent across sessions. |
| **Side-branch** | A short-lived branch created from `origin/main` to bundle a specific worker's commits during a concurrent-aware β. Named `workerN-bundle-<timestamp>`. Lives only as long as the β ceremony takes. |
| **Session** | A continuous span of operator attention on one worker, bounded by α at the start and β at the end. |

The peer topology: N workers, all equal. No primary. No canonical worker. The canonical artifact is `origin/main`, not any one worker. Workers converge through `origin/main`, never directly with each other.

---

## The three rules — formal definitions

### α — Session start

**Trigger:** First action in any new session against a worker.

**Preconditions:**
- The worker tree exists.
- `origin` is reachable.

**Procedure:**
```bash
cd /repo/workerN
git fetch origin

# If worker has no unique commits since last convergence:
git merge --ff-only origin/main

# If worker has unique in-progress commits:
git merge origin/main
# Resolve any shared-file conflicts per the playbook (below).
```

**Postconditions:**
- `git rev-list --count HEAD..origin/main` returns `0`.
- All shared files reflect canonical truth as of session start.

**Invariant:** A session that has not completed α has not started. No work may be committed against a worker that has not run α this session.

**Mechanical enforcement:** Session-start tripwire script. See [`templates/hooks/session-start-tripwire.sh`](./templates/hooks/session-start-tripwire.sh).

---

### β — Session end

**Trigger:** Last action in any session against a worker, before close.

**Two ceremony shapes:**
- **β.1** — Solo-fast-path. Used when no other workers are concurrently mid-flight in a β of their own.
- **β.2** — Precision-target side-branch. Used by default in any environment with 2+ concurrent workers. Safe to use when β.1 would also work; not safe to skip when β.1 would not work.

When in doubt: use β.2. Its overhead is small; its safety property holds in all cases β.1 holds and additional cases β.1 does not. **The asymmetry is steep — β.2 costs seconds you don't notice; the failure mode β.2 prevents costs hours of git archaeology you do.**

**Postconditions (both shapes):**
- Every commit on `workerN/main` is reachable from `origin/main`.
- `origin/main` has advanced.
- No commits from other workers were absorbed under this worker's scope.

**Invariant:** A session that has not completed β has stranded work. The next session inheriting this worker may discover it as "ahead of main" by an unknown number of commits — the 274-commit failure mode.

**Mechanical enforcement:** Session-end check script. See [`templates/hooks/session-end-check.sh`](./templates/hooks/session-end-check.sh).

---

### γ — No direct commits to main

**Trigger:** Any commit attempt in the canonical clone.

**Procedure:** A pre-commit hook rejects the commit unless an operator-mediated bypass is invoked explicitly.

**Why an explicit bypass exists:** human operators occasionally need to commit directly to main for genuinely manual interventions — release tags, ceremonial commits, recovery operations. The hook protects against habitual direct-commit accidents (especially mid-context-switch) without forbidding the operator from acting deliberately.

**Mechanical enforcement:** Pre-commit hook on the canonical clone. See [`templates/hooks/no-direct-main-commits.sh`](./templates/hooks/no-direct-main-commits.sh).

---

## β.1 — Solo-fast-path ceremony

Used when no other workers are mid-β.

```bash
# 1. Publish the worker branch
cd /repo/workerN
git push origin workerN/main

# 2. Switch to canonical clone (no editing here)
cd /repo/canonical-clone
git fetch origin

# 3. Fast-forward main
git checkout main
git merge --ff-only workerN/main

# 4. Push canonical
git push origin main

# 5. Verify convergence
git rev-list --count origin/main..origin/workerN/main
# Expected: 0 (every workerN/main commit is now reachable from main).
# Failure mode: a positive count means workerN/main has commits main lacks -- β didn't land.
# (Note the direction: A..B counts commits on B not on A. We want "nothing on the
#  worker that main is missing," which is origin/main..origin/workerN/main == 0.)
```

If step 3 fails (`merge --ff-only` rejects because main has commits not in `workerN/main`), the world has changed under you — another worker β-merged while you were preparing. Switch to β.2.

---

## β.2 — Precision-target side-branch ceremony

The architecturally distinctive piece of the protocol. Used by default when concurrent workers exist.

**The core insight:** the side-branch is rooted at `origin/main`, not at the worker branch. This is what isolates the bundle to your worker's intended scope and prevents accidental absorption of concurrent workers' commits.

```bash
# 1. Identify the exact commits to ship from this worker
COMMITS=$(git -C /repo/workerN log origin/main..workerN/main --pretty=%H --reverse)

# 2. Create the side-branch in the canonical clone, rooted at origin/main
cd /repo/canonical-clone
git fetch origin
BUNDLE="workerN-bundle-$(date +%Y%m%d-%H%M%S)"
git checkout -b "$BUNDLE" origin/main

# 3. Cherry-pick the commits in order
for sha in $COMMITS; do
  git cherry-pick "$sha" || break
done
# If the loop broke: see Recovery section. Do not proceed without resolving.

# 4. Push the side-branch
git push origin "$BUNDLE"

# 5. Merge the side-branch into main (ff-only required)
git checkout main
git fetch origin
git merge --ff-only "$BUNDLE"
git push origin main

# 6. Verification
git merge-base --is-ancestor "$BUNDLE" origin/main; echo $?
# Expected: 0 (ancestor — every cherry-picked commit is reachable from main).

# 7. Delete the side-branch locally and on origin
git branch -d "$BUNDLE"
git push origin --delete "$BUNDLE"
```

**Bundle naming convention:** `<worker>-bundle-<timestamp>`. The timestamp suffix matters — if a β.2 fails midway and you retry, the retry gets a new timestamp, so the failed bundle remains visible in history for forensic recovery.

**Attestation discipline (light version):** the merge commit produced by step 5 carries the bundle name in its message: `Merge bundle workerN-bundle-<timestamp> into main`. This is enough to forensically reconstruct "which worker shipped which commit when" from `git log` alone, without external attestation infrastructure. The full attestation chain — linking AI-generated commits to operator-approved bundles with cryptographic continuity — is the subject of a separate methodology piece (CSAE, planned).

**Verification step:** step 6 is non-optional. β.2 is correct only when every cherry-picked commit ends up reachable from `origin/main`. If verification fails, you've shipped a partial bundle — see Recovery.

---

## Shared-file resolution playbook

Files written by multiple workers need a deterministic resolution rule. Improvising at merge time is how structured files get corrupted.

| File class | Resolution | Why |
|---|---|---|
| **Living state** (e.g. STATUS_NOW) | Newest wins — binary choice, never hybridize. Decide "newest" by the **conflicting commit's timestamp** (`git log -1 --format=%cI <ref> -- STATUS_NOW.md`) or the file's own **`Last updated:`** field — **not** filesystem mtime. | The file represents a snapshot of *now*. The newer snapshot is, by definition, more accurate; hybridizing two snapshots produces a fictional state that was never true at any point. Filesystem mtime is not deterministic here — git does not preserve it across clones (a fresh checkout stamps every file at clone time), so the commit timestamp or an in-file authored timestamp is the reliable signal. |
| **Append-only** (e.g. DECISIONS_LOG) | Both sides' new entries; sort by timestamp. | The file is a log. Logs append; conflict resolution that drops one side's entries silently loses decisions. Timestamp sort produces a chronologically correct merged log. |
| **Structured ID-keyed** (e.g. BACKLOG) | Hand-merge by ID-keyed section. **Never `git merge-file --union`.** | Union-merging interleaves lines, corrupting ID-keyed structure. The file becomes syntactically valid but semantically wrong. See the worked example below. |
| **Auto-generated index** | Discard both sides; regenerate from current canonical inputs. | An index is a derived artifact. If the inputs are clean, regenerating produces the correct index. Merging two stale indices is wasted effort. |
| **Plain text living docs** | Prefer newer; flag for re-review next session. | If both workers were editing this, neither has the full picture. The newer version is the better starting point; the flag prevents silent acceptance of the loser's lost edits. |

### Why `git merge-file --union` corrupts ID-keyed structured files

Consider a BACKLOG.md with rows like:

```
| ID-001 | OPEN | desc-A | owner-1 |
| ID-002 | OPEN | desc-B | owner-2 |
```

Worker1 changes ID-001 to DONE:

```
| ID-001 | DONE | desc-A | owner-1 |
| ID-002 | OPEN | desc-B | owner-2 |
```

Worker2 changes ID-002 to DONE:

```
| ID-001 | OPEN | desc-A | owner-1 |
| ID-002 | DONE | desc-B | owner-2 |
```

`git merge-file --union` will produce *both* line-level versions of both rows, interleaved:

```
| ID-001 | OPEN | desc-A | owner-1 |
| ID-001 | DONE | desc-A | owner-1 |
| ID-002 | OPEN | desc-B | owner-2 |
| ID-002 | DONE | desc-B | owner-2 |
```

Now ID-001 appears twice with conflicting state. The file parses as Markdown but no longer has unique IDs — any downstream tool that reads it (an index generator, a status query, a renderer) returns wrong answers.

The hand-merge rule: re-key the file by ID, merge each ID's row independently (newer-wins or explicit choice per row), and write the result back. Slow, but correct. Cheap to script once you've done it twice.

---

## The shared-worktree race problem

A failure mode worth naming as a class because it's invisible until it bites.

**The class:** two operator-driven sessions attach to the same worker tree at the same time. Each session runs α, each session makes commits, each session runs β. The git operations don't conflict at the file-system level (git locks per-operation), but the *session-level state* races — one session's α may have read main as it existed before the other session's β landed, and the work it produces is now operating against a stale picture.

**The symptom:** commits land in unexpected order; STATUS_NOW updates from one session get overwritten by the other; β.1 fails with merge conflicts that "shouldn't be possible" because each session believed it was operating in sync.

**The mitigation pattern (sanitized):** a lock file under `.git/` (e.g., `.git/worker-session.lock`) acquired at session start and released at session end. Sessions attempting to attach to a worker with an active lock either fail-fast (cleanest) or escape to an isolated worktree spawned just for the attempted session. The exact implementation depends on your tooling; the *pattern* — lock at session boundary, refuse double-attach — is general.

This is one of the cases where ceremony alone isn't enough; the mitigation has to be mechanical, because the race window is invisible to the operator.

**Implementation note:** the lock pattern needs to handle orphan locks (session crashed, lock left behind) and staleness (lock older than some threshold assumed dead). Both are well-trodden ground in distributed-systems literature; the protocol just says lock-at-boundary, refuse-double-attach, and handle the lifecycle correctly. A naïve single-file lock will fail on the first crash; budget for the harder cases.

---

## Scope collision — the third axis

A second failure mode worth naming as a class, because convergence is silent about it.

**The two axes the rules already cover.** Convergence (α/β) keeps every worker's commits reaching `origin/main` so nothing drifts. Clean attribution (β.2) keeps each bundle scoped to its own worker so nobody's commits get absorbed under someone else's. Both are about commits that *have been written* — where they go, and whose bundle they land in.

**The axis they don't cover.** Neither rule stops two workers from independently doing *the same work*. Worker1 picks up a task; worker2, in its own session with its own context, picks up the same task; both implement it; both converge cleanly. Convergence succeeds. Attribution is exact. And you have built the same thing twice — discovered at merge time, after the cost is already spent. β.2 will even merge both cleanly, because each bundle is well-formed in isolation. The first two axes are working exactly as designed; they were never watching for this.

Call it **scope collision**. Convergence asks *did the commits reach main*; attribution asks *whose bundle*; collision asks *should this work have started at all*.

**Why the obvious fix is fragile.** The instinct is a live claim registry: before starting, a worker writes "I'm taking task X" somewhere shared; others check it before they pick. It decays for a structural reason — **session identity is unstable.** Sessions are spawned, re-spawned, isolated into fresh worktrees, rotated; a registry keyed on "which session holds X" drifts the moment the session it names stops being the session that exists. Claim entries outlive their claimants, nobody trusts them, the registry rots into ceremony nobody reads.

**The discipline that works: identity-independent, pick-time prevention.** Don't ask "who is working on X." Ask a question with no identity in it: **has X's change already landed on canonical?** Before starting an item, check whether its change is already an ancestor of `origin/main`; if it is, refuse to start. The check keys on two things only — the **work-item identifier** and **git ancestry** — neither of which rotates. The item-ID names the work, not the worker; ancestry is a property of the commit graph, not of any session. The unstable substrate is sidestepped because the question never mentions it.

```
# Pick-time guard (pre-action; keyed on item-id + ancestry — no session identity)
# Before starting work on item X:
if <the change for X> is an ancestor of origin/main:
    refuse — X already landed; you are about to redo shipped work
else:
    proceed
```

The "<the change for X> is an ancestor" test is deliberately abstract: bind it to whatever marks an item landed in your repo — a commit-message convention (`fix(X):`), a closed-item record, a tag. What matters is that it reads the *commit graph*, not a registry of intentions.

**The honest limit — state it plainly.** This catches *already-landed* collisions: the work shipped and a second worker is about to redo it. It does **not** catch *in-flight* collisions: two workers starting the same item at the same time, neither landed yet. Nothing in the commit graph distinguishes "nobody did this" from "someone is doing this right now" — that needs a live claim layer, the fragile thing this discipline avoids. So the third axis is covered *asymmetrically*: the cheap, durable case is solved by a check that can't rot; the simultaneous case is not, and the protocol doesn't pretend otherwise. Pick-time ancestry is a high-value floor, not a ceiling. (The already-landed case is also the more common one across long-lived sessions — the "shipped but a peer is about to re-pick it" window is far wider than the "two peers pick the identical item in the same minute" window.)

**Mechanical enforcement.** Like the other rules, this wants to be a script, not a memory — a pre-action guard that runs the ancestry test at pick time and refuses on a hit. It pairs with the session-start tripwire (α): α-freshness is what makes the ancestry test accurate (a stale worker wouldn't see a recently-landed item and would wave through a redo). The two compose.

**Relationship to the shared-worktree race.** That race is *two sessions on one worker* producing non-deterministic session-state; this is *two workers doing one task* producing duplicate work. Different failure, different fix — a session-boundary lock vs. a pick-time ancestry check — but siblings in the same family: coordination hazards convergence alone is silent about.

---

## Anti-patterns

The most useful section for someone deciding whether to adopt this. People learn faster from "don't do this" than from "do this." Six anti-patterns, each with what people try, why it fails, what to do instead.

### 1. "I'll just commit directly to main this once."

**What people try:** bypass γ for a "small fix" because pushing through a worker feels like overhead.

**Why it fails:** it works the first time. It works the tenth. On time fifteen, the operator commits to main from inside a worker tree while a concurrent worker is in flight, and the worker's next β fails with a non-obvious conflict. Direct commits also poison the canonical-clone-is-not-for-editing discipline — once people see commits land there, the discipline erodes.

**What to do instead:** every change goes through a worker. If γ feels heavy, install the pre-commit hook so the heaviness becomes mechanical instead of disciplinary.

### 2. "I'll merge workerN/main directly into main; it's faster."

**What people try:** skip the side-branch in β.2 because the cherry-pick loop feels like overhead. Most often this happens right after a β.1 has failed — the operator is mid-context-switch, frustrated, and reaches for `git merge workerN/main` to push through.

**Why it fails:** this is the exact failure mode β.2 was designed to prevent. If any concurrent worker pushed to its own branch before yours, your direct-merge sweeps in their commits under your bundle's attribution. The forensic question "who shipped this commit?" becomes unanswerable.

**What to do instead:** use β.2 by default. β.1 is fine when you're certain no other worker is in flight. The cost of using β.2 when β.1 would have worked is two extra git operations. The cost of using β.1 when β.2 was needed is attribution corruption.

### 3. "I'll use `git merge-file --union` on STATUS_NOW conflicts; it's cleaner."

**What people try:** union-merge any shared-file conflict because it auto-resolves.

**Why it fails:** union-merging produces a file that's syntactically valid but represents no real state. For STATUS_NOW specifically, the file claims two contradictory current states simultaneously. The next session reading it makes decisions against a fictional picture.

**What to do instead:** per the resolution playbook. Living-state files: newest wins. Don't hybridize.

### 4. "I'll let the worker run for a few weeks; I'll converge when it's natural."

**What people try:** skip β at session-end when "nothing's urgent."

**Why it fails:** this is the 274-commit failure mode. "Natural convergence" is an oxymoron — convergence is ceremony, not nature. Without a forced trigger, drift accumulates silently until the next time you happen to look.

**What to do instead:** β every session. Install the session-end check so you mechanically cannot close a session with unmerged work.

### 5. "I'll have one worker be canonical and the others sync to it."

**What people try:** replace peer topology with a star topology, designating one worker as primary.

**Why it fails:** this is what most people do first. It works at low load. Under sustained 2-3 concurrent sessions, the canonical worker becomes the convergence bottleneck, and it has the same drift problem internally — just moved one layer.

**What to do instead:** peer topology with `origin/main` as canonical. Workers are equal. The convergence point is the remote, not any one worker.

### 6. "I'll attach a second session to this worker because the first session is busy."

**What people try:** open a second terminal on the same worker tree to "make progress" while the first session is mid-something.

**Why it fails:** the shared-worktree race problem. Two sessions racing on one worker produce non-deterministic state.

**What to do instead:** one session per worker at any time. If you need a second concurrent session, spin up a second worker (a new worktree) and run it peer-to-peer. Lockfile mitigation makes this mechanical.

---

## Recovery

The 274-commit anecdote in the README *is* the recovery story — the prevention is the protocol, but recovery is what happens when the protocol failed (or wasn't yet in place). The discipline across every recovery scenario below is one principle: **don't compound the failure.** A protocol violation creates a divergent state; the fix is to converge through the protocol, not to bypass it again. The four sub-sections below are each that principle applied to a specific failure mode.

### Recovery from a stranded worker (the 274-commit case)

**Symptom:** you check a worker that hasn't been driven recently. `git log --oneline origin/main..workerN/main` returns dozens or hundreds of commits.

**Procedure:**
1. **Do not panic-merge.** A direct β-merge of a stranded worker may sweep in shared-file changes that conflict with everything that's happened on main since the worker last converged. Read the situation first.
2. **Compute the divergence:** `git log --oneline origin/main...workerN/main`. The triple-dot shows both sides. Look for any commits on main that the worker doesn't have — there will be many.
3. **Check shared-file impact:** for each canonical shared file, compare the worker's version to `origin/main`'s version. If the worker's version is newer-but-stale (worker edited based on stale main), you need the playbook.
4. **Bundle in segments if needed:** if the stranded worker's commits cover multiple topical workstreams, consider β.2 in segments — one bundle per workstream — rather than one giant bundle. Easier to review, easier to revert if needed.
5. **Run β.2 once per segment.** Each segment gets its own side-branch from current `origin/main`, its own cherry-pick subset, its own merge.
6. **Verify per-bundle.** Don't batch verification across bundles; each one should individually satisfy the verification step.

The first 274-commit recovery I did took multiple hours. Subsequent ones got faster — partly because the protocol prevented recurrence and partly because the recovery itself is script-able.

### Recovery from a botched cherry-pick during β.2

**Symptom:** the cherry-pick loop in β.2 step 3 broke. Output shows a conflict; the worktree is in a `CHERRY_PICK_HEAD` state.

**Procedure:**
1. **Don't abort yet.** First check `git status` and read the conflict. If it's tractable (e.g., a STATUS_NOW conflict you can resolve per the playbook), resolve it, `git cherry-pick --continue`, resume the loop from the next commit.
2. **If untractable, abort cleanly:** `git cherry-pick --abort`. The side-branch is now in a partial state — it contains all commits up to the one that failed.
3. **Decide: ship partial or restart?** If the landed commits are coherent on their own (e.g., a complete sub-feature), you may ship the partial bundle. If they're incoherent, delete the side-branch (`git branch -D <bundle>`) and start over with a smaller commit range.
4. **Investigate the conflict's root cause before re-running.** A cherry-pick conflict during β.2 is usually a sign that something happened on main while you were preparing — another worker β-merged a related change. If so, fetch fresh, recompute the COMMITS list relative to *current* `origin/main`, and try again.

### Recovery from a worker that's been out of sync for weeks

**Symptom:** you suspect a worker has been operating against stale main for an extended period — work it produced may have been based on assumptions no longer true.

**Procedure:**
1. **Don't auto-merge.** Treat the worker as a quarantine candidate first.
2. **Read its recent commit history:** what assumptions did it make? Are those assumptions still true on current main? Pay particular attention to changes that referenced *other* shared files (the worker might have edited STATUS_NOW based on a version of DECISIONS_LOG that no longer exists).
3. **For each commit, decide: cherry-pick, rewrite, or discard.** A commit still semantically correct against current main: cherry-pick via β.2. A commit semantically wrong against current main: rewrite — manually port the *intent* to current main as a new commit, then discard the original.
4. **Sync STATUS_NOW from current main, not from the stranded worker.** Whatever the stranded worker thought the current state was is wrong by definition. Start from canonical truth.

The most expensive recovery — slow, requires judgment, and tends to find latent bugs the staleness was masking. Worth it. The alternative (auto-merging a stale worker) corrupts main.

### Recovery from a γ violation

**Symptom:** a commit landed directly on `origin/main` without going through a worker — either the hook was bypassed or wasn't installed.

**Procedure:** depends on whether the commit is shareable through a worker after-the-fact.
1. **If the commit can be cleanly ported:** cherry-pick it into the appropriate worker as a new commit, push, then revert the original direct commit on main, then β-merge the worker. The history now shows the commit landed via worker, plus a revert of the rule violation — clean audit trail.
2. **If reverting is impractical** (e.g., a release tag, a security fix that couldn't wait for ceremony): leave it, but log the γ violation in DECISIONS_LOG with the rationale. Recurring γ violations indicate the protocol isn't fitting the work, not that the work is wrong.

---

## Verification

Quick incantations to confirm convergence happened:

| Check | Command | Expected |
|---|---|---|
| Worker is in sync with main | `git -C /repo/workerN rev-list --count HEAD..origin/main` | `0` |
| Main has all of worker's commits | `git -C /repo/workerN rev-list --count workerN/main..origin/main` | `≥ 0` (positive = main is ahead, fine) |
| No worker is ahead of main | for each worker: `git -C /repo/workerN rev-list --count origin/main..origin/workerN/main` | All `0` |
| Bundle is reachable from main | `git merge-base --is-ancestor <bundle> origin/main; echo $?` | `0` |

Run these after every β. If any fails, β didn't complete — investigate before continuing.

---

## Glossary

- **α** — session-start rule. Pull main into worker before any work.
- **β** — session-end rule. Merge worker → main, push main. Two ceremony shapes: β.1 (solo-fast-path) and β.2 (precision-target side-branch).
- **γ** — no-direct-main-commits rule. Pre-commit hook enforces.
- **Bundle** — the side-branch created during β.2, named `<worker>-bundle-<timestamp>`.
- **Canonical** — `origin/main`. The single source of truth.
- **Canonical clone** — a working copy of the repo dedicated to β operations; no editing happens here.
- **Drift** — divergence between a worker branch and `origin/main` that grew silently.
- **Peer topology** — N workers, all equal; convergence through canonical, not through any one worker.
- **Side-branch** — the short-lived branch in β.2, rooted at `origin/main`.
- **Stranded** — a worker with commits that haven't reached `origin/main`. The state β is designed to prevent.
- **Worker** — a long-lived workspace implemented as a `git worktree`. Workers are *spaces*, not *features*.

---

For the informal motivation and the failure-it-solves story, see [`README.md`](./README.md). For a complete walkthrough including a concurrent-β collision, see [`examples/concurrent-beta-walkthrough.md`](./examples/concurrent-beta-walkthrough.md).

— Moran Bickel
