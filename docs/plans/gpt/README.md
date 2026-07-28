# GPT plan corpus — development-plan chunks (RAG)

Chunked sections of the (long, externally authored) development plan, searchable via
`node tools/rag.mjs --corpus plan "<query>"`. One section = one file: `NNN-<slug>.md`,
ids start at **101** (dsp chunks own 001–099).

## ⚠️ Ground rules

1. **Plan ≠ truth.** `docs/rag/chunks/` (dsp corpus) holds MEASURED parameters and real-audio
   verdicts. A plan chunk NEVER overrides a dsp chunk. On contradiction the measurement wins
   and the plan chunk moves to `status: conflicts` with the refuting evidence in `verdict:`.
   Conflicted/rejected chunks STAY in the corpus — deleting them lets the idea come back.
2. **Triage before build.** Every incoming section is compared against `HANDOFF.md` +
   dsp chunks 001–018 and gets a `status` before any round picks it up.
3. **Living corpus.** When a round lands a chunk, set `status: done` + `as_built:`.
   When a new plan version replaces a section, the new chunk lists `supersedes: [old-id]`
   and the old one gets `status: superseded` (kept on disk).
4. Update `INDEX.md` in the same commit as any chunk change.

## Frontmatter template

```yaml
---
id: 101
topic: <one-line section title>
tags: [strum, ui, ml, monetization]
status: new          # new | active | done | conflicts | superseded | rejected
depends_on: []       # other plan ids and/or dsp chunk ids (e.g. 016b)
supersedes: []       # plan ids this version replaces
as_built:            # once done: file paths / round number
verify: <what proves it done — test, measured number, real-guitar APK check>
verdict:             # for conflicts/rejected: WHY, with the refuting measurement
source: chatgpt-plan <upload date>
---
```

## Status lifecycle

`new` → (triage) → `active` | `conflicts` | `rejected` | already `done`
`active` → (round lands) → `done`
any → (new plan version) → `superseded`

## Search

```bash
node tools/rag.mjs --corpus plan --status active "next feature"   # what's actionable
node tools/rag.mjs --semantic "hogyan pontozzuk a pengetést"      # hybrid, Hungarian OK
node tools/rag.mjs --list --corpus plan                           # full inventory
```

Drop new raw plan material into `docs/plans/gpt-inbox/` (gitignored ok) or paste in chat —
it gets chunked + triaged from there.
