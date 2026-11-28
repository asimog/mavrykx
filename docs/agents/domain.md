# Domain Docs

How the engineering skills consume this repo's domain documentation when exploring the design.

## Before exploring, read these

- **`docs/v1/02-domain-model.md`** — the canonical definitions, entities, ownership, relationships,
  lifecycles and invariants.
- **The rest of `docs/v1/`** as needed. Each decision lives in the document where it applies.

This repo keeps no `GLOSSARY.md` and no `docs/adr/`. Do not create them. Vocabulary has one writer,
`docs/v1/02-domain-model.md`. Decisions have one writer, the document that owns them.

## Use the vocabulary

When your output names a domain concept — an issue title, a proposal, a hypothesis, a test name — use
the term as defined in the domain model. Do not drift to synonyms the model rejects: a Matter is not
a proceeding, a hearing is not an order, a fact is not evidence, a document is not a version, an
authority is not a citation, a task is not a deadline. Rejected entities stay rejected: `action`,
`assignment`, sub-matter, `Workspace` or `Project` for the Matter.

If the concept you need is not defined yet, that is a real gap. Record it in
`docs/v1/02-domain-model.md`, not in a new glossary file.

## Flag conflicts

If your output contradicts a decision recorded in `docs/v1/`, surface it explicitly and fix the
document that owns the decision. Never silently override it, and never open a parallel decision log.
