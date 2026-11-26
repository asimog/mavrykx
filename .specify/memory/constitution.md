# Maverick — constitution

**Status:** current · **Date:** 2026-11-26

Spec Kit requires a project constitution. This file adds no principles of its own: the repository's operating rules are [AGENTS.md](../../AGENTS.md), and the binding decisions are [docs/v0/01-decisions.md](../../docs/v0/01-decisions.md).

Where a Spec Kit workflow and this repository meet, the repository wins:

1. **Documentation only.** There is no application code, build or test suite. A spec describes the design; it never claims the product exists.
2. **One writer per truth.** Every fact has one owning document. A spec points to it rather than restating it.
3. **One scope.** No phasing, MVP, version labels or staged releases.
4. **No implementation until the conditions in [00-README](../../docs/v0/00-README.md) pass.** If those conditions fail, change the deployment or the editor — do not add features.
5. **Every decision is in the register.** A spec may not contradict a recorded FD, VD, RD, AS, OQ or RK item; a new decision gets a new ID in the same series.

The Spec Kit artefacts under `.specify/` are tooling, not design authority. The design set in `docs/v0/` remains the source.
