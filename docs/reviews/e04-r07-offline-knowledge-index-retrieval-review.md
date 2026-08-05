# Review — E04-R07 Offline knowledge index és retrieval

- **Kör:** E04-R07
- **Branch:** `codex/e04-r07-offline-knowledge-index-retrieval`
- **Implementer commit:** `056f531` (`feat(ai-tutor-rag): add deterministic local knowledge retrieval`)
- **Pre-flight commit:** `99c6022` (ADR 0136 + brief §0.0 revízió)
- **Implementer motor:** Codex (`gpt-5.6-terra`, örökölt kézi override)
- **Reviewer:** Claude Opus 4.8 (független, read-only, izolált `/tmp/review-e04-r07` klón)
- **Verdikt:** ✅ **APPROVED** — 0 BLOCKER / 0 MAJOR / 0 MINOR / 1 NOTE

## 1. Jelzés + handoff

`.codex-round-status`: `status=done`, head `056f531`. A signal-időpont `dirty_files=1`
mezőjét kivizsgáltam (L21): a commit befejezése után a working tree **tiszta**
(`git status --short` üres); a tranziens dirty a commit közbeni gitignore-olt
generált előfeltétel volt, nem elveszett szerkesztés. Brief §10 handoff kitöltve.

## 2. Gate — újrafuttatva SAJÁT kézzel (izolált klón)

`git clone --branch codex/e04-r07-… → /tmp/review-e04-r07`, `prepare-flutter-generated.sh`,
majd `tools/round-gate.sh test/features/ai_tutor/data`:

```
format          zöld
analyze         zöld
test test/features/ai_tutor/data  zöld  (47 teszt)
architecture    zöld  (12 allowlisted deviation)
MINDEN GATE ZÖLD
```

## 3. Scope-audit

`git diff --name-only e79a0eb...056f531` — mind a 10 fájl a brief `allowed_paths`
listáján belül (a §0.0 szűkítés után: `public.dart` **kivéve**, `docs/adr/0136`
hozzáadva). A `lib/features/ai_tutor/public.dart` **érintetlen** (üres boundary),
így a `ai_tutor_boundary_test.dart` nulla-export invariánsa sértetlen. A merge-elt
`knowledge_codec.dart`/`knowledge_document.dart` **nem módosult** — a retrieval a
meglévő R06 codec API-ra épül (`contentHashForDocument/Chunk`, `chunkDocument`).
**Listán kívüli fájl: nincs.**

## 4. Acceptance criteria — tételes bizonyíték

| Kritérium | Bizonyíték |
|---|---|
| hu+en query, skill-boost, topic-filter | `knowledge_retriever_test.dart:70,85,110` — locale-szeparált en/hu találat, `preferredSkillBoost`, topic(=skill) szűrő |
| Discrimination mátrix (min-score inkluzív `>=`, max-result cap) | `…:124–185`, cellák `_fixtureScore`-ból számítva; **mutáció-próba** lent |
| Duplicate collapse + stable tie-break (shuffle-invariáns) | `…:187–224` — 3 különböző input-sorrend (reversed + dup) → azonos `['alpha#1','zulu#1']` |
| Corrupt index → fallback, nem crash; empty kontrollált | `…:311,328` asset-repo fallback (empty index + hibakód + `logger.error`); `…:226` kontrollált empty |
| Latency baseline dokumentálva | `docs/baseline/epic-04-knowledge-retrieval.md` (index-load 36,3 ms; warm p50 0,449 ms; fixture-index) |

## 5. Kötött döntések (ADR 0136 / brief §5) — megfelel

1. **Determinisztikus, stable tie-break** `(score desc, sourceId asc, chunkIndex asc)`
   — `knowledge_retriever.dart:119–125`. Az index is kanonikusan rendez
   (`knowledge_index.dart:73`). Rendezés-független.
2. **Query soha nem trusted content** — kimenet `TutorSourceRef` (id/locale/topic/
   version/chunkIndex/chunkHash), a query szövege **nem** szivárog: `…:264` teszt
   igazolja.
3. **Index-load-failure nem omlaszt** — `AssetKnowledgeRepository.loadIndex()` minden
   hibaosztályt fallbackre fog (`KnowledgeIndexLoadResult.fallback` + fail-loud
   `logger.error`), üres indexszel.
4. **Embedding-backend seam nyitva** — `KnowledgeRetrievalBackend` interfész, a
   `KnowledgeRetriever` a lexical első implementáció.
5. **`topic` ≡ `skill`** (mért §0.0): a query `topic`/`preferredSkill` a
   `KnowledgeSkill` enumon operál — nincs kitalált keyword/heading mező.

## 6. Valódi-sértés próba (eldobható, dokumentált, visszaállítva)

**Min-score inkluzivitás.** A `knowledge_retriever.dart:76` `if (score < query.minScore)`
→ `<=` mutáció (a határt EXKLUZÍVvá téve) a klónban:

```
KnowledgeRetriever uses an inclusive min-score … [E]
  Expected: contains all of ['delta-title', 'delta-title-content']
    Actual: ['delta-title-content']   (has too few elements 1 < 2)
Some tests failed.
```

A `score == minScore` doc (`delta-title`) kiesett → a teszt **PIROS**. A mutációt
`git checkout`-tal visszaállítottam. A discrimination-guard tehát ténylegesen fog.
(A shuffle-invariáns tie-break guard szerkezetileg is bizonyított: 3 input-permutáció
azonos kimenettel — input-sorrend-függő rendezés RED-re váltaná.)

## 7. Architektúra / termékhatárok

- Feature → `core/logging` import (megengedett irány; core↛feature nem sérül).
- `public.dart` érintetlen → boundary-invariáns OK; nincs UI, nincs plugin, nincs
  hálózat/mic/secret a diffben. Provider-mentes (ADR 0131).
- A `tool/build_tutor_knowledge_index.dart` determinisztikus (nincs óra/random/float
  a build-úton — ADR 0135 vonala öröklődik).

## 8. Leletek

| # | Osztály | Fájl:sor | Leírás |
|---|---|---|---|
| N1 | NOTE | `knowledge_retriever_test.dart:154` | Az `exclusiveBelow` változó a `inclusive`-kal **azonos** query-paraméterekkel készül; a neve más szándékot sugall, de a hordozott assertion (`delta-content` kizárva, mert score < min) érvényes és értelmes. Kozmetikai redundancia; javítása fölöslegesen hizlalná a diffet — follow-up, nem blokkol. |

**Nincs BLOCKER/MAJOR/MINOR.** Merge-re kész az exact-SHA zöld CI után.
