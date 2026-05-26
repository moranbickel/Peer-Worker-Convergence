# Peer-Worker Convergence

**A protocol for running multiple AI coding sessions on one repo without divergence.** Names the architectural problem that emerges when you have N concurrent Claude Code sessions (or equivalent — Cursor sessions, Copilot agents, multi-IDE workflows) committing to long-lived worker branches alongside a canonical main, and gives you the rules and ceremonies that keep those branches converging instead of drifting.

If you've ever opened a worker branch a week later to find it ahead of main by a number you didn't expect — and weren't sure which commits were already merged elsewhere — this is the protocol.

I built it while developing [ORCA](#about-orca), an AI legal reasoning system for Israeli civil litigation. It's part of a series of methodology pieces I'm publishing from that work, alongside [Russian Judge](https://github.com/moranbickel/russian-judge) and [Three-Body Protocol](https://github.com/moranbickel/three-body-protocol).

---

## The failure it solves

I had three git worktrees running in parallel for several weeks, each with a Claude Code session attached. Each worktree had its own long-lived branch and its own slice of the work. The plan was that they'd each push to their own branch and we'd periodically converge through `main`.

The plan didn't survive contact with reality.

One evening I went to check a worker I hadn't actively driven in about two weeks. I expected it to be five, maybe ten commits ahead of `main`. It was **274 commits ahead.**

Nothing was broken. The worker had been doing real work, shipping real commits, with the operator (me) closing the loop. But "converge periodically through main" turned out to mean "converge when I remember to." And without a hard ceremony, I didn't remember to. The branch drifted. The other two workers drifted in their own directions. By the time I noticed, reconciling them was a multi-hour exercise of cherry-picks, conflict resolution on shared files, and forensic git-log reading.

That was the moment I realized:

**Multi-session AI workflows have a convergence problem, and it isn't solved by "merge often."** "Often" is a vibe. What you need is a ceremony with a definite trigger — a thing that happens at the start and end of every session, mechanically, whether you remember it or not.

Peer-Worker Convergence is that ceremony.

---

## Three-Body and Peer-Worker — sibling pieces

[Three-Body Protocol](https://github.com/moranbickel/three-body-protocol) addresses coordination *across sessions in time* — how the thinking AI, the implementing AI, and you stay aligned across days and weeks via STATUS_NOW and DECISIONS_LOG.

Peer-Worker Convergence addresses coordination *across sessions in parallel* — how N concurrent worker branches stay aligned with main and with each other during the same operating week.

Three-Body's bridge files are among the shared files this protocol's convergence ceremony has to handle. The two pieces compose.

---

## What this protocol is not

Peer-Worker is **not** a substitute for short-lived feature branches and PRs. If you're working solo, on a single session, with each branch living for one feature and dying after merge — your existing GitHub workflow already converges things. This protocol is for the case where worker branches are *spaces*, not *features*: long-lived, multi-task, parallel to other workers, and merging through main as a continuous discipline rather than a per-feature event.

It's also not the same architectural shape as native multi-agent platforms. Anthropic's [Claude Code Agent Teams](https://code.claude.com/docs/en/agent-teams) (April 2026) coordinates *one team under one operator*, where agents share a planning context and the platform handles intra-team handoff. That's the right tool when the work decomposes cleanly within a single thinking context.

Peer-Worker addresses a different topology: *one operator running N independent sessions*, each with its own thinking context, converging through git rather than through shared prompt state. Two reasons you'd want this:

- **Different contexts matter.** A session pre-loaded with strategic / discipline / status context thinks differently from a session pre-loaded with focused implementation context. You want both, and you don't want to recompose them every prompt.
- **Asymmetric attention.** When one session is mid-flight on a hard problem, you don't want the others paused. Independent sessions let you context-switch at the operator level — fluid attention across N work surfaces, each making progress in parallel.

If your work has a single coherent decomposition, Agent Teams is the cleaner shape. If your work has multiple parallel contexts with independent cadences, peer-worker is the shape that survives the operator-attention reality.

And finally it's **not** a complete solution. It addresses the convergence ceremony. It does not address how to design work across workers (that's [Three-Body](https://github.com/moranbickel/three-body-protocol)), how to review the work each worker produces (that's [Russian Judge](https://github.com/moranbickel/russian-judge)), or how to attest the work as AI-generated (CSAE, planned). It's a load-bearing piece, not the whole structure.

---

## Peer-Worker vs alternatives

| Dimension | Ad-hoc multi-session | Canonical worker | Peer-Worker Convergence |
|---|---|---|---|
| Workers | Equal, no rules | One primary, others temporary | Equal, peer topology |
| Convergence trigger | "When you remember" | Through the canonical | Session start + session end ceremony |
| Failure mode | Drift compounds silently | Canonical becomes bottleneck | Documented anti-patterns; trip-wired |
| Concurrent commits to main | Implicit, race-prone | Canonical-only | Explicitly forbidden (γ rule) |
| Shared-file conflicts | Hand-resolved each time | Avoided by single writer | Resolution playbook per file class |
| Long-lived worker branches | Yes, fragile | No | Yes, by design |
| Best for | Solo + occasional multi-session | One human juggling 1-2 sessions | 2+ persistent concurrent sessions |

The middle column (canonical worker) is what most people do first, and what most teams settle on if the workload is light. Peer topology pays off when you're routinely running 2-3 concurrent sessions for multiple days at a stretch.

---

## The protocol, at a glance

Three rules. Two ceremonies. One canonical artifact.

**The canonical artifact:** `main` on origin. It is the single source of truth. Nothing else is.

**The three rules:**

```
α  (session start)   Pull main into worker before any work.
β  (session end)     Merge worker → main, push main.
γ  (forever)         Never commit directly to main.
```

The Greek letters are just labels — α/β/γ keeps them from colliding with other rule numbering in your project. Call them what you want.

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

Every worker pulls from main on session start. Every worker pushes back through main on session end. Nothing commits directly to main. Workers never merge to each other — only through main. That last constraint is what keeps the graph from becoming a tangle.

Workers will sometimes write to the same shared files (STATUS_NOW, DECISIONS_LOG, BACKLOG, generated indexes). Those conflicts have a deterministic resolution playbook — see [Shared files: resolution playbook](#shared-files-resolution-playbook) below.

---

## A worked example

Suppose I'm running two concurrent sessions today. `worker1` is working on schema changes. `worker2` is working on documentation. They share `docs/STATUS_NOW.md` and `docs/DECISIONS_LOG.md`.

**Morning — worker1 session start (α):**

```bash
cd /repo/worker1
git fetch origin
git merge --ff-only origin/main
```

The ff-only succeeds because worker1 has no unique unmerged commits since the last convergence. The worker is now in sync with main.

**Mid-day — both workers commit independently to their own branches.** No conflict yet, because neither has pushed.

**Late afternoon — worker1 session end (β):**

```bash
cd /repo/worker1
git push origin worker1/main           # publish worker branch
cd /repo/canonical-clone               # clean clone, no editing happens here
git fetch origin
git merge --ff-only worker1/main       # main now ahead by worker1's commits
git push origin main                   # canonical published
```

**Evening — worker2 session end (β):**

worker2 fetches origin and discovers `main` is ahead by worker1's commits. It pulls them in (merge, not ff-only, because worker2 also has local commits). Conflict on `STATUS_NOW.md` — both workers updated it. Resolution per the shared-file playbook: newest wins (by commit timestamp or the file's `Last updated:` field, not filesystem mtime), not a hybrid. Conflict resolved, worker2 finishes its β.

By morning the next day, all three artifacts (`origin/main`, `origin/worker1/main`, `origin/worker2/main`) agree. No drift. No 274-commit surprise.

The whole ceremony adds maybe two minutes per session boundary. The cost of skipping it is unbounded.

---

## Concurrent-aware β: the precision-target side-branch

The simple ceremony assumes one worker β-merges at a time. When two workers are mid-flight and both want to β at roughly the same time, the simple shape has a failure mode: worker1's β can sweep in worker2's already-pushed-but-not-yet-merged commits under worker1's bundle, blurring attribution.

This is the architecturally novel part of the protocol. The fix is a small but specific git move: **don't merge worker1/main directly into main.** Instead, cherry-pick worker1's specific commits onto a fresh side-branch *created from `origin/main`*, push the side-branch, then merge the side-branch into main.

The side-branch contains *only* worker1's intended scope, by construction. worker2's commits — even if already pushed to `worker2/main` — stay on worker2's branch until worker2's own β runs. No attribution blur. No accidental scope absorption.

In commands, worker1's concurrent-aware β looks like:

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

The two non-obvious moves are step 2 (the side-branch is rooted at `origin/main`, not at `worker1/main` — this is what isolates the bundle) and step 3 (cherry-pick by SHA, not full branch merge — this is what keeps the scope exact). Step 4's `--ff-only` is what guarantees no surprise commits sneak in during the merge.

If you root the side-branch at `worker1/main`, you inherit whatever worker1 has accumulated locally — including any commits that snuck in concurrently. Rooting at `origin/main` starts from canonical truth, and you add only the commits you explicitly chose.

If worker2 starts its own β while worker1's side-branch is in flight, worker2 does the same dance against its own commit range. Both bundles land on main as clean ff-merges, neither absorbs the other, attribution stays exact.

Once installed as a script ([`templates/scripts/concurrent-beta.sh`](./templates/scripts/concurrent-beta.sh)), this collapses to:

```bash
./scripts/concurrent-beta.sh worker1
```

The four operations — cherry-pick, push side-branch, ff-merge, push main — fit on one line of operator action. *Mechanically enforced, not remembered* applies to ceremony shape as well as ceremony trigger.

**What can go wrong:** cherry-pick conflicts on shared files (especially STATUS_NOW), SHA misidentification across worker branches, intertwined commits that resist clean cherry-pick selection. See [`PROTOCOL.md`](./PROTOCOL.md) §Recovery for diagnostic and recovery procedures — the side-branch flow is the protocol's strongest move but also where adoption friction is highest.

The full ceremony — bundle naming conventions, attestation discipline, verification step, recovery from a botched cherry-pick — is in [`PROTOCOL.md`](./PROTOCOL.md).

---

## Shared files: resolution playbook

Some files are written by every worker but only canonically valid on main. Each class has a resolution rule. Don't improvise.

| File class | Resolution |
|---|---|
| Living state (e.g. STATUS_NOW) | Newest wins — binary choice, don't hybridize. "Newest" = the conflicting commit's timestamp or the file's own `Last updated:` field, **not** filesystem mtime (git doesn't preserve mtime across clones). |
| Append-only (e.g. DECISIONS_LOG) | Both sides' new entries; sort by timestamp. |
| Structured ID-keyed (e.g. BACKLOG) | Hand-merge by ID-keyed section. Never `git merge-file --union` — corrupts ID structure. |
| Auto-generated index | Discard both sides; regenerate from current canonical inputs. |
| Plain text living docs | Prefer newer; flag for re-review next session. |

`PROTOCOL.md` has the full playbook with the why behind each rule. The short version: structured files have structure; treating them as line-oriented is what corrupts them.

---

## Mechanically enforced, not remembered

The hardest thing about a session-boundary ceremony is that you'll forget it. Not the first time — the first time you'll remember because you just adopted the protocol. The fifth time, late at night, mid-context-switch, you'll forget. Operator fatigue defeats discipline. Mechanical enforcement defeats operator fatigue.

Three light enforcement layers cover the three rules. None of them is intrusive; all of them are load-bearing.

**Session-start tripwire (α enforcer).** A script invoked as the first thing a fresh session does. It runs `git rev-list --count HEAD..origin/main` and refuses to proceed if the count exceeds a threshold. I use 10 — small enough that worker history stays close to canonical, large enough that the tripwire doesn't fire on routine in-session-cycle work. The threshold is the dial that defines "drift." Below it: you're operating in sync. Above it: you're operating against a stale picture, and the work you're about to do will compound the staleness. The session can't continue until α runs.

**Session-end check (β enforcer).** A script invoked before a session is allowed to close out. It runs `git log --oneline origin/main..HEAD` on the worker branch; if the output is non-empty, the worker has unmerged work that hasn't reached main. The check refuses session close until β completes. This is the highest-leverage enforcer in the set — the failure mode it prevents (stranded commits that drift into a 274-commit pile) is exactly the failure mode that motivated the protocol.

**Branch-naming pre-commit hook (γ enforcer).** A `pre-commit` hook installed on the canonical clone that rejects direct commits, full stop. It pairs with a directory-to-branch naming convention — worker directory `worker1` is required to have branch `worker1/main`, and a commit attempted from a directory whose name doesn't map to its checked-out branch is rejected. This second job (naming-convention check) is what makes the hook robust against the case where someone is on a wrongly-named branch in a worker tree and tries to commit anyway. Together: no direct commits to main, and no commits from misnamed branches anywhere.

Templates for all three live in [`templates/hooks/`](./templates/hooks/). They're short shell scripts; adapt to your shell, set your threshold, and install.

The pattern is the load-bearing insight: **ceremony you mechanically can't skip is worth more than ceremony you discipline yourself to remember.** This is true at the personal scale — your future-3am-self will skip the discipline; their future-3am-self can't skip the script. It's more true when multiple workers are involved.

---

## When to use it — and when not to

**Use it when:**
- You're running 2+ concurrent Claude Code (or equivalent) sessions on one repo
- Each session lives for days, not minutes — workers are *spaces* you return to, not feature branches
- The work is parallel and benefits from independent commit history per session
- Drift between branches is invisible until it bites

**Don't use it when:**
- One session at a time — your standard branch + PR flow already converges
- Short-lived feature branches — they merge and die; no convergence ceremony needed
- Standard team workflow with code review — PRs ARE the convergence ceremony for that model
- You only have one operator and one chat window — the failure mode this prevents doesn't trigger
- You are running fewer than two long-lived worker sessions for multiple days a week — plain feature branches plus discipline are cheaper than this protocol

The gate isn't "are you using AI?" It's "do you have N long-lived branches with a single operator's attention divided across them?" If yes, you have the convergence problem. If no, you don't.

---

## Adopt the mechanics in 30 minutes; internalize the discipline over a week

1. **Decide on worker topology.** How many concurrent sessions do you actually run? Peer-worker pays off at N ≥ 2, sustained. Below that, this is overkill.
2. **Set up worker worktrees.** `git worktree add /path/to/worker1 -b worker1/main origin/main` for each. Worker directory names and branch names follow a convention so a hook can enforce them.
3. **Adopt the three rules.** Drop the α/β/γ checklist from [`templates/ceremony-checklist.md`](./templates/ceremony-checklist.md) into your equivalent of STATUS_NOW or a session-start prompt.
4. **Install the tripwires.** Three scripts in [`templates/hooks/`](./templates/hooks/). They're small. Skim them, adapt the threshold, install. For the γ-enforcer (`no-direct-main-commits.sh`), also `touch .canonical-clone` at the canonical clone's root — that marker is what arms the hook; without it the hook silently no-ops and direct commits to main go through.
5. **Document the shared files.** List the files multiple workers will write. For each, write down the resolution rule (per the table above). Put the list at the top of your DECISIONS_LOG so every fresh session sees it.

The setup is 30 minutes. The discipline takes longer to internalize. The first time you forget β at session-end, you'll feel the ceremony tax. The third time you cherry-pick correctly under a concurrent collision, the side-branch dance will feel automatic. That's the honest curve — fast to install, slower to make second nature.

For the formal protocol — full ceremony shapes, side-branch cherry-pick mechanics, attestation discipline — see [`PROTOCOL.md`](./PROTOCOL.md). For a complete walkthrough including a concurrent-β collision, see [`examples/concurrent-beta-walkthrough.md`](./examples/concurrent-beta-walkthrough.md).

---

## Related work

I surveyed the field before publishing. The closest adjacent pieces:

**Anthropic's [Claude Code Agent Teams](https://code.claude.com/docs/en/agent-teams)** (April 2026) ships native multi-Claude-Code coordination at the platform level — teams of agents under one operator, shared context within the team. Peer-Worker addresses the independent-sessions topology described in *What this protocol is not* — different shape, different operating reality, the two compose if you're running both.

**Long-lived `git worktree` as a workflow pattern** predates AI by years — see various engineering blog posts on using worktrees for parallel-task isolation, hot-fix lanes, and concurrent feature work. Peer-Worker is the AI-multi-session evolution: same isolation primitive, new convergence problem because the workers are operator-driven sessions rather than developer task lanes.

**Stacked-diff tools** (Sapling, Graphite, ghstack) coordinate concurrent feature work at a different layer — they're about navigable PR stacks, not long-lived parallel branches converging through main. Adjacent, not competing; if your team uses stacked diffs and also has the multi-session problem, the two layers compose.

**Standard GitFlow / GitHub Flow** with feature branches + PRs is the convergence ceremony for short-lived feature work. It assumes branches die after merge. Peer-Worker is for the case where they don't.

**Trunk-based development** keeps branches short and shifts complexity into feature flags. It works well for team coordination but assumes a coordinated team rhythm. Peer-Worker is for asymmetric solo-with-AI-helpers workflows where the "team" is one human and N parallel AI sessions running on independent cadences.

**Christian Crumlish's ["Three-AI Orchestra"](https://medium.com/building-piper-morgan/the-three-ai-orchestra-lessons-from-coordinating-multiple-ai-agents-0aeb570e3298)** (September 2025) is adjacent but at the chat-coordination layer, not the git-convergence layer. The two protocols compose: orchestrate at the prompt layer; converge at the git layer.

If you know of closer prior art, please open an issue — I'd genuinely like to position this against it.

---

## Related

This is one of a series of methodology pieces from building [ORCA](#about-orca):

- **[Russian Judge](https://github.com/moranbickel/russian-judge)** — adversarial AI review with structured verdicts.
- **[Three-Body Protocol](https://github.com/moranbickel/three-body-protocol)** — coordination across sessions in time.
- **Peer-Worker Convergence** — *this repo.* Coordination across sessions in parallel.
- **[CSAE](https://github.com/moranbickel/csae)** — attestation chains for AI-generated commits.

More pieces as they're written.

## About ORCA

ORCA — Orchestrated Reasoning for Civil Action — is an AI legal reasoning system I'm building for Israeli civil litigation. It's a decision system, not a document generator: it reasons about which causes of action hold, which elements the evidence supports, and what relief follows. A programmer builds a document generator; a litigator builds a decision system. The system is closed-source; the methodology that produced it is open. This repo publishes the coordination methodology, not ORCA's product internals — no source code, knowledge bases, prompts, customer data, or implementation roadmap.

See my [GitHub profile](https://github.com/moranbickel) for the full body of work and how to follow ORCA's progress.

---

## License

- Prose: [CC BY 4.0](./LICENSE-CC-BY-4.0)
- Templates and code: [MIT](./LICENSE-MIT)

— Moran Bickel
