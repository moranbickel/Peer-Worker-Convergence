# Changelog

All notable changes to Peer-Worker Convergence are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.1.0] — 2026-05-20

Initial release.

### Added
- `README.md` — protocol overview, failure-it-solves narrative, α/β/γ rules at a glance, vs-alternatives table, worked example, concurrent-aware side-branch ceremony with command-level example, shared-file resolution playbook, mechanical-enforcement section, related-work survey.
- `PROTOCOL.md` — formal specification with preconditions/postconditions/invariants for the three rules, both β ceremony shapes, full shared-file resolution playbook including the `merge-file --union` corruption worked example, shared-worktree race as a named class with lock-lifecycle implementation notes, six anti-patterns, four-scenario recovery section, verification incantations, glossary.
- `examples/concurrent-beta-walkthrough.md` — end-to-end walkthrough of two operator-driven sessions converging through main, including a β.1 failure and β.2 precision-target side-branch recovery.
- `templates/hooks/session-end-check.sh` — β-enforcer; refuses session close with stranded commits.
- `templates/hooks/session-start-tripwire.sh` — α-enforcer; blocks work when worker is drifted beyond threshold.
- `templates/hooks/no-direct-main-commits.sh` — γ-enforcer; pre-commit hook on canonical clone.
- `templates/ceremony-checklist.md` — α/β/γ card-stock reference.
- `diagram.svg` — protocol topology diagram.

### Context
Third of five methodology pieces from ORCA. Companion to [Russian Judge](https://github.com/moranbickel/russian-judge) (adversarial AI review) and [Three-Body Protocol](https://github.com/moranbickel/three-body-protocol) (coordination across sessions in time). This piece addresses coordination across sessions in parallel.

[0.1.0]: https://github.com/moranbickel/peer-worker-convergence/releases/tag/v0.1.0
