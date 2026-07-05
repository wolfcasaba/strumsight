---
name: rag-systems
description: Use when searching the recipewiser-mobile codebase semantically — conceptual questions ("where do we log water", "how is the energy ring computed") where you don't know the exact identifier. Covers the scope-tagged Flutter code RAG and when to prefer it over grep.
---

# RAG Systems — recipewiser-mobile

The mobile repo ships a **scope-tagged code RAG** over the Dart source: `tools/flutter-rag.mjs`
(362 chunks across 28 scopes).

## Usage

```bash
SCOPE=<name> node tools/flutter-rag.mjs "<query>"   # scoped to one feature/area
node tools/flutter-rag.mjs "<query>"                # whole-repo
```

Examples:
```bash
SCOPE=nutrition node tools/flutter-rag.mjs "how is the energy ring computed"
SCOPE=log node tools/flutter-rag.mjs "where do we log water"
```

## When to use which

| Question | Tool |
|----------|------|
| Conceptual — "where do we do X?", "how is Y computed?" and you DON'T know the identifier | `flutter-rag.mjs` (semantic) FIRST |
| You know the exact symbol / string / file | Grep / Glob directly |
| "Is feature X ported from web? real gap?" | Read `PARITY.md` / `SCOPE_REVIEW.md` (NOT search) |

Use semantic search BEFORE grep for conceptual questions — it beats keyword search when you
don't know the exact name. Fall back to grep once the RAG points you at the right scope/file.

## Cross-project note

The web app (`~/Recipewiser`) has its own separate RAG (`pnpm code-search`, Jina embeddings) and a
QA/visual index — those are web-only, don't invoke them here. The shared layer between the two
projects is the **Viking** brain (`mcp__viking__*`), not the code indexes. Lessons about RAG usage
worth sharing go to Viking via `viking_remember` / `viking_skill_add`.
