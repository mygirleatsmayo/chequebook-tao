# Domain Docs

How the engineering skills should consume this repo's domain documentation when exploring the codebase.

## Before exploring, read these

- **`CONTEXT.md`** at the repo root, or
- **`CONTEXT-MAP.md`** at the repo root if it exists — it points at one `CONTEXT.md` per context. Read each one relevant to the topic.
- **`.mayosdd/adr/`** — read ADRs that touch the area you're about to work in. In multi-context repos, also check `src/<context>/.mayosdd/adr/` for context-scoped decisions.

If any of these files don't exist, proceed silently. The `/mayosdd-domain-modeling` skill creates them lazily when terms or decisions actually get resolved.

## File structure

This is a single-context repository. Domain docs belong at the repository root:

```
/
├── CONTEXT.md
├── .mayosdd/adr/
└── src/
```

## Use the glossary's vocabulary

When output names a domain concept, use the term as defined in `CONTEXT.md`. If the concept is not in the glossary yet, note that gap for `/mayosdd-domain-modeling`.

## Flag ADR conflicts

If output contradicts an existing ADR, surface it explicitly rather than silently overriding.
