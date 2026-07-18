# Peer-Worker Convergence

[![smoke](https://github.com/moranbickel/Peer-Worker-Convergence/actions/workflows/smoke.yml/badge.svg)](https://github.com/moranbickel/Peer-Worker-Convergence/actions/workflows/smoke.yml)

A protocol for running several AI coding sessions on one repository without their
branches drifting apart. If you run multiple long-lived sessions alongside a
shared main, this is the start-and-end routine that keeps them in sync instead of
slowly diverging.

I built it developing ORCA, a closed-source legal-AI system, one of a series
alongside [Russian-Judge](https://github.com/moranbickel/Russian-Judge) and
[Three-Body-Protocol](https://github.com/moranbickel/Three-Body-Protocol). The
failure it solves is below: a worker that drifted far enough from main to make
convergence expensive, because "converge when I remember to" is not a routine.

## The failure it solves

I had three git worktrees running in parallel for several weeks, each with a Claude Code session attached. Each had its own long-lived branch and its own slice of the work. The plan was simple: each one pushes to its own branch, and we converge through `main` from time to time.

The plan didn't survive contact with reality.

One evening I checked a worker I hadn't driven in about two weeks. I expected it to be five, maybe ten commits ahead of `main`. It was **274 commits ahead.**

Nothing was broken. The worker had been doing real work and shipping real commits, with me closing the loop each time. But "converge from time to time" really meant "converge when I remember to," and without a fixed trigger, I didn't remember to. That branch drifted. The other two drifted in their own directions. By the time I noticed, putting them back together took hours of cherry-picks, conflict resolution on shared files, and reading git history line by line.

The lesson: multi-session AI work has a convergence problem, and "merge often" doesn't fix it. "Often" depends on remembering, and remembering is the part that fails. What works is a fixed routine tied to a specific moment: the same steps at the start and end of every session, every time, whether or not you feel like it. Peer-Worker Convergence is that routine.

---


## Three-Body and Peer-Worker: sibling pieces

[Three-Body Protocol](https://github.com/moranbickel/Three-Body-Protocol) covers coordination *across time*: how the thinking AI, the implementing AI, and you stay aligned across days and weeks, through files like STATUS_NOW and DECISIONS_LOG.

Peer-Worker Convergence covers coordination *across parallel sessions*: how several worker branches stay in sync with `main`, and with each other, during the same working week.

The two fit together. Three-Body's bridge files are some of the shared files this protocol's convergence routine has to merge.

---


## What this protocol is not

It is **not** a replacement for short-lived feature branches and pull requests. If you work solo, one session at a time, with each branch living for a single feature and dying after merge, your normal GitHub workflow already keeps things converged. This protocol is for a different case: branches that are *workspaces*, not *features*. They live a long time, hold many tasks, run in parallel with other workers, and merge through `main` continuously rather than once per feature.

It is also a different shape from native multi-agent platforms. Anthropic's [Claude Code Agent Teams](https://code.claude.com/docs/en/agent-teams) (April 2026) coordinates *one team under one operator*, where the agents share a planning context and the platform handles handoff between them. That's the right tool when the work splits cleanly inside a single thinking context.

Peer-Worker is for a different setup: *one operator running several independent sessions*, each with its own context, converging through git rather than through shared prompt state. You'd want this for two reasons:

- **Different contexts matter.** A session loaded with strategy and status context thinks differently from one loaded with focused implementation context. You want both, and you don't want to rebuild them on every prompt.
- **Attention shifts.** When one session is deep in a hard problem, you don't want the others to pause. Independent sessions let you move your attention between several work surfaces while each keeps making progress.

If your work has a single clean breakdown, Agent Teams is the simpler choice. If it has several parallel threads running at their own pace, Peer-Worker is the shape that holds up.

Finally, it is **not** a complete solution. It handles convergence. It does not handle how to divide work across workers (that's [Three-Body](https://github.com/moranbickel/Three-Body-Protocol)), how to review what each worker produces (that's [Russian Judge](https://github.com/moranbickel/Russian-Judge)), or how to attest the work as AI-generated ([CSAE](https://github.com/moranbickel/CSAE)). It doesn't even cover all of coordination: it handles convergence and attribution fully, but [scope collision](#scope-collision-the-third-axis) (two workers unknowingly doing the same task) only partly. It catches the already-finished case, not the in-flight one. Think of it as one load-bearing piece, not the whole structure.

---


## Peer-Worker vs. alternatives

| Dimension | Ad-hoc multi-session | Canonical worker | Peer-Worker Convergence |
|---|---|---|---|
| Workers | Equal, no rules | One primary, others temporary | Equal, peer topology |
| Convergence trigger | "When you remember" | Through the canonical | Session start + session end routine |
| Failure mode | Drift compounds silently | Canonical becomes bottleneck | Documented anti-patterns; trip-wired |
| Concurrent commits to main | Implicit, race-prone | Canonical-only | Explicitly forbidden (γ rule) |
| Shared-file conflicts | Hand-resolved each time | Avoided by single writer | Resolution playbook per file class |
| Long-lived worker branches | Yes, fragile | No | Yes, by design |
| Best for | Solo + occasional multi-session | One human juggling 1-2 sessions | 2+ persistent concurrent sessions |

The middle column (one canonical worker that the others sync to) is what most people try first, and it's fine when the workload is light. Peer topology earns its keep once you're routinely running two or three sessions at once for days at a stretch.

---


## The protocol, at a glance

Three rules, two ceremony shapes, one canonical artifact.

**The canonical artifact** is `main` on origin. It is the single source of truth. Nothing else is.

**The three rules:**

```
α  (session start)   Pull main into worker before any work.
β  (session end)     Merge worker → main, push main.
γ  (forever)         Never commit directly to main.
```

The Greek letters are just labels, so they don't collide with other rule numbering in your project. Call them whatever you like.

**Diagram:**

```
   ┌───────────────┐   ┌───────────────┐   ┌───────────────┐
   │   worker1     │   │   worker2     │   │   worker3     │
   │   (branch)    │   │   (branch)    │   │   (branch)    │
   └───────┬───────┘   └───────┬───────┘   └───────┬───────┘
           │                   │                   │
           │ α: pull           │ α: pull           │ α: pull
           │ β: push merge     │ β: push merge     │ β: push merge
           │                   │                   │
           └───────────────────┼───────────────────┘
                               ▼
                ┌──────────────────────────────┐
                │     origin/main              │
                │     (canonical, γ-protected) │
                └──────────────────────────────┘
```

Every worker pulls from `main` at session start and pushes back through `main` at session end. Nothing commits straight to `main`. Workers never merge into each other; they only meet through `main`. That last rule is what keeps the history from turning into a tangle.

Workers will sometimes write to the same shared files (STATUS_NOW, DECISIONS_LOG, BACKLOG, generated indexes). Those conflicts have a fixed resolution playbook. See [Shared files: resolution playbook](#shared-files-resolution-playbook) below.

---


## A worked example

Say I'm running two sessions today. `worker1` is doing schema changes. `worker2` is doing documentation. They both touch `docs/STATUS_NOW.md` and `docs/DECISIONS_LOG.md`.

**Morning, worker1 session start (α):**

```bash
cd /repo/worker1
git fetch origin
git merge --ff-only origin/main
```

The fast-forward succeeds because worker1 has no unmerged commits since the last convergence. The worker is now in sync with `main`.

**Mid-day:** both workers commit to their own branches. No conflict yet, because neither has pushed.

**Late afternoon, worker1 session end (β):**

```bash
cd /repo/worker1
git push origin worker1/main           # publish worker branch
cd /repo/canonical-clone               # clean clone, no editing happens here
git fetch origin
git merge --ff-only worker1/main       # main now ahead by worker1's commits
git push origin main                   # canonical published
```

**Evening, worker2 session end (β):**

worker2 fetches origin and finds that `main` is now ahead by worker1's commits. It pulls them in (a merge, not a fast-forward, because worker2 also has local commits). There's a conflict on `STATUS_NOW.md`: both workers edited it. The playbook says newest wins (by commit timestamp or the file's own `Last updated:` field, not filesystem mtime), with no hybrid. worker2 resolves it and finishes its β.

By the next morning, all three (`origin/main`, `origin/worker1/main`, `origin/worker2/main`) agree. No drift. No 274-commit surprise.

The whole routine adds maybe two minutes per session boundary. Skipping it can cost hours.

---


## Concurrent-aware β: the precision-target side-branch

The simple routine assumes one worker merges at a time. When two workers finish at roughly the same moment, it has a weak spot: worker1's merge can sweep in worker2's already-pushed-but-not-yet-merged commits, so it's no longer clear which worker shipped what.

The move is one small, specific git operation: **don't merge worker1/main straight into main.** Instead, cherry-pick worker1's exact commits onto a fresh side-branch *created from `origin/main`*, push that side-branch, and merge it into `main`.

The side-branch then holds *only* worker1's intended commits. worker2's commits, even if already pushed to `worker2/main`, stay on worker2's branch until worker2 runs its own β. Nothing gets absorbed by accident.

In commands, worker1's concurrent-aware β looks like this:

```bash
# 1. Identify the exact commits to ship
COMMITS=$(git -C /repo/worker1 log origin/main..worker1/main --pretty=%H --reverse)

# 2. Create a fresh side-branch from origin/main (NOT from worker1/main)
cd /repo/canonical-clone
git fetch origin
git checkout -b worker1-bundle-$(date +%Y%m%d) origin/main

# 3. Cherry-pick worker1's commits onto the side-branch
for sha in $COMMITS; do git cherry-pick $sha; done

# 4. Push the side-branch and merge into main
git push origin HEAD
git checkout main
git merge --ff-only worker1-bundle-$(date +%Y%m%d)
git push origin main
```

Two moves do the work. Step 2 roots the side-branch at `origin/main` rather than `worker1/main`, which is what isolates the bundle. Step 3 cherry-picks by SHA instead of merging the whole branch, which is what keeps the scope exact. Step 4's `--ff-only` guarantees no surprise commits sneak in during the merge.

If you root the side-branch at `worker1/main` instead, you inherit whatever worker1 has piled up locally, including anything that snuck in concurrently. Rooting at `origin/main` starts from canonical truth and adds only the commits you chose.

If worker2 starts its own β while worker1's side-branch is still in flight, worker2 runs the same steps against its own commit range. Both bundles land on `main` as clean fast-forwards, neither absorbs the other, and it stays clear which worker shipped what.

Once you wrap it in a script ([`templates/scripts/concurrent-beta.sh`](./templates/scripts/concurrent-beta.sh)), it collapses to:

```bash
./scripts/concurrent-beta.sh worker1
```

Four operations (cherry-pick, push side-branch, fast-forward merge, push main) reduce to one command. The point is the same as everywhere else here: make the safe path the one you can run without thinking.

**What can go wrong:** cherry-pick conflicts on shared files (especially STATUS_NOW), picking the wrong SHAs across branches, and commits tangled together so they don't cherry-pick cleanly. See [`PROTOCOL.md`](./PROTOCOL.md) §Recovery for how to diagnose and recover. The side-branch flow is the protocol's strongest move, and also where people hit the most friction.

The full ceremony (bundle naming, attestation, the verification step, recovery from a botched cherry-pick) is in [`PROTOCOL.md`](./PROTOCOL.md).

---


## Scope collision: the third axis

Convergence and attribution both deal with commits that *have already been written*. α/β make sure they reach `main`; the side-branch β makes sure each lands under the right worker. Neither watches for a third problem: two workers doing **the same task** without knowing it.

One worker picks up a task. Another worker, in its own session with its own context, picks up the same task. Both build it. Both converge cleanly. Convergence succeeds, attribution is exact, and you've built the same thing twice. You find out at merge time, after the work is already done. The side-branch β will even merge both copies without complaint, because each bundle is fine on its own. The first two axes are doing exactly their job. They were never watching for this.

Call it **scope collision**. Convergence asks *did the commits reach main*. Attribution asks *whose bundle*. Collision asks *should this work have started at all*.

The obvious fix is a live claim registry: before you start, you write "I'm taking task X" somewhere shared, and others check it before they pick. It falls apart for a structural reason: session identity isn't stable. Sessions get spawned, re-spawned, isolated into fresh worktrees, and rotated, so a registry keyed on "which session holds X" goes out of date the moment that session stops being the session that exists. The fix that survives asks a question with no identity in it: **has X's change already landed on canonical?** Before starting a task, check whether its change is already an ancestor of `origin/main`. If it is, don't start. The check reads only two things, the task ID and git ancestry, and neither of those rotates. It works best alongside the α tripwire, because a stale worker wouldn't see a recently-landed task and would wave a redo through.

**What it doesn't catch.** This stops the *already-finished* case: the work shipped, and a second worker is about to repeat it. It does **not** stop the *in-flight* case: two workers starting the same task at the same time, neither finished yet. Nothing in the commit graph can tell "nobody did this" apart from "someone is doing this right now." Closing that case needs a live claim layer, which is the fragile thing this approach avoids on purpose. So the coverage is uneven: the common, durable case is solved by a check that can't go stale; the simultaneous case isn't, and the protocol doesn't pretend otherwise. Pick-time ancestry is a strong floor, not a ceiling.

The full treatment (the mechanics, the honest limit, and how it relates to the shared-worktree race) is in [`PROTOCOL.md`](./PROTOCOL.md) §"Scope collision - the third axis". A worked example of two sessions colliding on one task is in [`examples/scope-collision-walkthrough.md`](./examples/scope-collision-walkthrough.md).

---


## Shared files: resolution playbook

Several workers write the same files (STATUS_NOW, DECISIONS_LOG, BACKLOG,
generated indexes), but those files are only canonically valid on main. Each
class has a fixed resolution rule - newest-wins for living state, keep-both for
append-only logs, hand-merge for ID-keyed structured files, regenerate for
generated indexes. The full table, with the reasoning behind each rule and why
`git merge-file --union` corrupts ID-keyed files, is in [`PROTOCOL.md`](./PROTOCOL.md)
(Shared-file resolution playbook).

## Mechanically enforced, not remembered

The hard part of a session-boundary routine is that you will forget it. Not at first; the first week it's fresh and you remember. But a few sessions in, late at night, halfway through a context switch, it slips. Discipline loses to fatigue, reliably. So don't lean on discipline. Put the check in tooling that runs whether you remember or not.

Three light enforcement layers cover the three rules. None is intrusive; all three carry real weight.

**Session-start tripwire (α enforcer).** A script that runs as the first thing in a fresh session. It runs `git rev-list --count HEAD..origin/main` and refuses to continue if the count is over a threshold. I use 10: small enough that a worker stays close to canonical, large enough not to fire on routine in-session work. The threshold is the dial that defines "drift." Under it, you're in sync. Over it, you're working against a stale picture, and the work you're about to do will pile on more staleness. The session can't continue until α runs.

**Session-end check (β enforcer).** A script that runs before a session is allowed to close. It runs `git log --oneline origin/main..HEAD` on the worker branch; if there's any output, the worker has unmerged work that hasn't reached `main`, and the check refuses to let the session close until β finishes. This is the highest-leverage layer of the three, because the failure it prevents (stranded commits drifting into a 274-commit pile) is the exact failure that started all this.

**Branch-naming pre-commit hook (γ enforcer).** A `pre-commit` hook on the canonical clone that rejects direct commits outright. It also enforces a naming convention: the directory `worker1` must hold the branch `worker1/main`, and a commit from a directory whose name doesn't match its checked-out branch is rejected. That second check is what makes the hook hold up when someone is on a wrongly-named branch in a worker tree and tries to commit anyway. Together: no direct commits to `main`, and no commits from misnamed branches anywhere.

Templates for all three are in [`templates/hooks/`](./templates/hooks/). They're short shell scripts. Read them, set your threshold, install.

The pattern underneath all three is the point: a step you *can't* skip is worth more than a step you have to remember. That's true even working alone, and more true with several workers in play.

---


## When to use it, and when not to

**Use it when:**
- You run two or more concurrent Claude Code (or equivalent) sessions on one repo.
- Each session lives for days, not minutes. The branches are workspaces you return to, not feature branches.
- The work runs in parallel and benefits from separate commit history per session.
- Drift between branches stays invisible until it bites.

**Don't use it when:**
- You work one session at a time. Your normal branch-and-PR flow already converges.
- You use short-lived feature branches. They merge and die; no convergence routine needed.
- You run a standard team workflow with code review. Pull requests are already the convergence point for that model.
- You have one operator and one chat window. The failure this prevents doesn't happen.
- You run fewer than two long-lived sessions for multiple days a week. Plain feature branches plus a little discipline are cheaper than this protocol.

The real question isn't "are you using AI?" It's "do you have several long-lived branches with one person's attention split across them?" If yes, you have the convergence problem. If no, you don't.

---


## Adopt the mechanics in 30 minutes; internalize the discipline over a week

1. **Decide your worker topology.** How many sessions do you actually run at once? Peer-worker pays off at two or more, sustained. Below that, it's overkill.
2. **Set up worker worktrees.** Run `git worktree add /path/to/worker1 -b worker1/main origin/main` for each. Directory names and branch names follow a convention so a hook can enforce them.
3. **Adopt the three rules.** Drop the α/β/γ checklist from [`templates/ceremony-checklist.md`](./templates/ceremony-checklist.md) into your STATUS_NOW or a session-start prompt.
4. **Install the tripwires.** Three scripts in [`templates/hooks/`](./templates/hooks/). They're small; read them, set the threshold, install. For the γ enforcer (`no-direct-main-commits.sh`), also run `touch .canonical-clone` at the canonical clone's root. That marker is what arms the hook; without it the hook quietly does nothing and direct commits go through.
5. **Document the shared files.** List the files several workers will write. For each, write down its resolution rule (per the table above). Put that list at the top of your DECISIONS_LOG so every fresh session sees it.

Setup takes about 30 minutes. The discipline takes longer to settle in. The first time you forget β at session end, you'll feel the cost. By the third time you cleanly cherry-pick through a concurrent collision, the side-branch steps feel automatic. That's the honest curve: quick to install, slower to make second nature.

For the formal protocol (the full ceremony shapes, the side-branch mechanics, the attestation step), see [`PROTOCOL.md`](./PROTOCOL.md). For a complete walkthrough including a concurrent-β collision, see [`examples/concurrent-beta-walkthrough.md`](./examples/concurrent-beta-walkthrough.md).

---


## Related work

I looked at the field before publishing. The closest pieces:

**Anthropic's [Claude Code Agent Teams](https://code.claude.com/docs/en/agent-teams)** (April 2026) ships native multi-Claude-Code coordination at the platform level: teams of agents under one operator, sharing context within the team. Peer-Worker covers the independent-sessions case described above in *What this protocol is not*. Different shape, different operating reality; the two compose if you run both.

**Long-lived `git worktree` as a workflow** predates AI by years; engineering blogs have long used worktrees for parallel-task isolation, hot-fix lanes, and concurrent feature work. Peer-Worker is the AI-multi-session version: same isolation primitive, new convergence problem, because the workers are now operator-driven sessions rather than developer task lanes.

**Stacked-diff tools** (Sapling, Graphite, ghstack) coordinate concurrent feature work at a different layer. They're about navigable PR stacks, not long-lived parallel branches converging through `main`. Adjacent, not competing; if your team uses stacked diffs and also has the multi-session problem, the two layers compose.

**Standard GitFlow / GitHub Flow** with feature branches and PRs is the convergence routine for short-lived feature work. It assumes branches die after merge. Peer-Worker is for the case where they don't.

**Trunk-based development** keeps branches short and pushes complexity into feature flags. It works well for a coordinated team, but it assumes a shared team rhythm. Peer-Worker is for the asymmetric solo-with-AI-helpers case, where the "team" is one person and several parallel AI sessions on their own schedules.

**Christian Crumlish's ["Three-AI Orchestra"](https://medium.com/building-piper-morgan/the-three-ai-orchestra-lessons-from-coordinating-multiple-ai-agents-0aeb570e3298)** (September 2025) is adjacent, but at the chat-coordination layer rather than the git-convergence layer. The two compose: orchestrate at the prompt layer, converge at the git layer.

If you know of closer prior art, please open an issue. I'd genuinely like to position this against it.

---


## Related

This is one of a series of methodology pieces from building [ORCA](#about-orca):

- **[Russian Judge](https://github.com/moranbickel/Russian-Judge)** - adversarial AI review with structured verdicts.
- **[Three-Body Protocol](https://github.com/moranbickel/Three-Body-Protocol)** - coordination across sessions in time.
- **Peer-Worker Convergence** - *this repo.* Coordination across sessions in parallel.
- **[CSAE](https://github.com/moranbickel/CSAE)** - attestation chains for AI-generated commits.
- **[Pre-IMPL Forensic Discipline](https://github.com/moranbickel/Pre-IMPL-Forensic-Discipline)** - catching wrong premises before they become wrong commits (v0.1 draft).

More pieces as they're written.


## About ORCA

ORCA (Orchestrated Reasoning for Civil Action) is an AI legal reasoning system I'm building for Israeli civil litigation. It's a decision system, not a document generator: it reasons about which causes of action hold, which elements the evidence supports, and what relief follows. A programmer builds a document generator; a litigator builds a decision system. The system is closed-source; the methodology behind it is open. This repo publishes the coordination methodology, not ORCA's internals: no source code, knowledge bases, prompts, customer data, or roadmap.

See my [GitHub profile](https://github.com/moranbickel) for the full body of work and how to follow ORCA's progress.

---


## License

- Prose: [CC BY 4.0](./LICENSE-CC-BY-4.0)
- Templates and code: [MIT](./LICENSE-MIT)

- Moran Bickel
