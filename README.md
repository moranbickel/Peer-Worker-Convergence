# Peer-Worker Convergence

[![smoke](https://github.com/moranbickel/Peer-Worker-Convergence/actions/workflows/smoke.yml/badge.svg)](https://github.com/moranbickel/Peer-Worker-Convergence/actions/workflows/smoke.yml)

A Git routine and shell scripts for one operator running several persistent
coding sessions on separate branches.

## Inspect a worker's state

In an existing worker repository with an `origin/main` branch:

```sh
git fetch origin
git rev-list --count HEAD..origin/main
git log --oneline origin/main..HEAD
```

The count shows commits on the fetched main that the worker lacks. The log shows
commits on the worker that main lacks. These commands do not merge or publish work.

Read the [concurrent-worker walkthrough](examples/concurrent-beta-walkthrough.md)
before adopting the merge script. The examples are illustrative workflows.

## The routine

- At session start, synchronize the worker with main.
- At session end, land the intended work through your repository's review and
  merge process.
- Keep implementation commits off the canonical main checkout.

The [checklist](templates/ceremony-checklist.md), [hooks](templates/hooks/), and
[bundle script](templates/scripts/concurrent-beta.sh) implement parts of this
routine. Read their assumptions before installing them. The direct-main hook
requires a `.canonical-clone` marker to be active.

The [protocol](PROTOCOL.md) covers selecting commits, concurrent publication,
shared-file conflicts, and recovery. Its merge examples need adaptation to your
branch protection and review requirements.

## Limits

This is for persistent worker branches. Ordinary short-lived branches and pull
requests may already be sufficient for your workflow.

Git ancestry can show that work has already landed. It cannot show that another
isolated session has just started the same task. See the
[scope-collision example](examples/scope-collision-walkthrough.md).

The [already-fixed crash test](https://github.com/moranbickel/agent-crash-tests/tree/main/cases/already-fixed)
demonstrates a related pickup error using a synthetic fixture.

For handoff files, see [Three-Body-Protocol](https://github.com/moranbickel/Three-Body-Protocol).
For work-item records, see [Docket](https://github.com/moranbickel/Docket).

Maintained by [Moran Bickel](https://github.com/moranbickel).
Prose: [CC BY 4.0](LICENSE-CC-BY-4.0). Templates and code: [MIT](LICENSE-MIT).
