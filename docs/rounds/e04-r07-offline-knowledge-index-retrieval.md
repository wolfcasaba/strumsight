# E04-R07 — Offline knowledge index és retrieval

- **Státusz:** PLANNING (pre-flight mérve 2026-08-05, kód olvasva: main @ `e79a0eb`)
- **SDD-kör:** [`docs/sdd/05-epic-04-ai-guitar-teacher.md`](../sdd/05-epic-04-ai-guitar-teacher.md) Kör 7; §35
- **Branch:** `codex/e04-r07-offline-knowledge-index-retrieval`
- **Előfeltétel:** Epic 3 (E03-R22) lezárva; **E04-R06 merge**
- **Brief szerzője:** Claude (batch) · **Implementáció:** Codex (Terra)

```ai-router
schema_version = 1
risk = "high"
allowed_paths = [
  "lib/features/ai_tutor/data/knowledge/knowledge_index.dart",
  "lib/features/ai_tutor/data/knowledge/knowledge_retriever.dart",
  "lib/features/ai_tutor/data/knowledge/asset_knowledge_repository.dart",
  "lib/features/ai_tutor/domain/models/tutor_source_ref.dart",
  "tool/build_tutor_knowledge_index.dart",
  "docs/adr/0136-tutor-knowledge-retrieval.md",
  "test/features/ai_tutor/data/knowledge_index_test.dart",
  "test/features/ai_tutor/data/knowledge_retriever_test.dart",
  "docs/baseline/epic-04-knowledge-retrieval.md",
  "docs/rounds/e04-r07-offline-knowledge-index-retrieval.md",
]
gate_tests = [
  "test/features/ai_tutor/data",
]
native_gate = false
```

> ⚠ **Pre-flight (KÖTELEZŐ):** `origin/main` + E04-R06 merge; olvasd újra
> `AGENTS.md`, Chapter 1/5, `HANDOFF.md`. Nincs ÚJ ADR (R06 0135 governance
> bővítése). `rg`: az R06 `KnowledgeDocument`/manifest mai alakja + az asset-út.
> PREPARED→PLANNING, brief commit az implementer ELŐTT.

## 0. Kör-jelzés és STOP-protokoll

```bash
tools/codex-signal.sh progress "<egy sor>" ; tools/codex-signal.sh done "<egy sor>"
tools/codex-signal.sh stopped "<egy sor>" ; tools/codex-signal.sh blocked "<egy sor>"
```

Lezáró jelzés nélkül a kör bukott. Listán kívüli fájl/contract → `stopped`.

## 0.0 Tervezési baseline és pre-flight revízió

**Mérve az orchestrátor pre-flightjában (main @ `e79a0eb`, E04-R06 merge megvan).**

**ADR:** ÚJ **[ADR 0136](../adr/0136-tutor-knowledge-retrieval.md)** — deterministic
offline tutor knowledge retrieval (az orchestrátor írta a pre-flightban; 0135 volt a
legmagasabb merge-elt szám). Az ADR 0135 (merge-elt) **NEM módosul**.

**Mért schema (`lib/features/ai_tutor/data/knowledge/knowledge_document.dart:81–93`):**
a `KnowledgeDocument` mezői: `schemaVersion`, `id`, `locale`, `skill`
(`KnowledgeSkill`: rhythm/chord/technique/practice/safety), `difficulty`
(`KnowledgeDifficulty`: beginner/intermediate/advanced), `license`, `version`,
`status`, `title`, `body`, `contentHash`. Az asset-JSON-ok (`assets/tutor_knowledge/**`)
ugyanezek. A `KnowledgeCodec` (`knowledge_codec.dart`) determinisztikus JSON codec +
bekezdés-chunker → `KnowledgeChunk` (documentId, index, content, contentHash).
A manifest (`assets/tutor_knowledge/manifest.json`) doc-onként: id/locale/skill/
difficulty/license/version/contentHash/sourcePath + chunk-lista.

**REVÍZIÓ 1 — mért mezőkészlet (a §3/§6 „topic"/„keywords"/„heading" avult):**
a schemában **nincs `topic`, `keywords`, `heading` mező** (grep: 0 találat). Ezért:
- **`topic` ≡ `skill`** — a „topic-filter" a `KnowledgeSkill` enumon szűr.
- A ranking a **létező szövegen** súlyoz: `title` (nagyobb súly) + chunk
  `content`/`body` (kisebb súly). Nincs külön keyword/heading dimenzió.
- Az index **locale + skill + difficulty** aware (mindhárom mező létezik).

**REVÍZIÓ 2 — allowed-list SZŰKÍTÉS (`public.dart` eltávolítva):** a brief eredeti
listája `lib/features/ai_tutor/public.dart`-ot „additív export"-ként tartalmazta, de
a `test/features/ai_tutor/ai_tutor_boundary_test.dart` **nulla-import/export
invariánst** őriz — bármely export a public.dart-ból RED. E körnek **nincs hívója**
(R12/R16 fogyasztja majd a retrievalt), így az R06-precedens szerint a réteg belső
marad (`data/knowledge/` + `domain/models/`), a `public.dart` **üres és érintetlen**.
A `public.dart` az allowed_paths-ből eltávolítva; helyette `docs/adr/0136-…md`. Az
allowed-lista szűkítése az orchestrátor autonómiájában van (ADR 0087 §2).

**Mért §1 szabályok:** (1) *elérhetetlen cél-státusz* — a min-score/max-result határ
policy, nem meglévő reducer; az inkluzivitás (`>= minScore`) a kötött szemantika,
fixture-indexből géppel számítva. (2) *erőforrás-tulajdonlás* — a kör nem rendel
lease/lock/subscription-t réteghez; N/A.

## 1. Cél

**Determinisztikus, offline** tudásbázis-keresés forrásjelöléssel, a későbbi
embedding-backend interfészét nyitva hagyva.

## 2. Jelenlegi állapot

- R06 után létezik az approved en+hu knowledge pack + manifest; **retrieval nincs**.
- A domain determinizmus-precedense az E03-R05 capability-resolver + E02-R09 matcher
  (stable tie-break, fail-loud).

## 3. Scope

**Benne:** locale/topic/skill/difficulty-aware index, lexical ranking (title/heading/
keywords/body súlyok), duplicate-chunk collapse, min-score + max-result policy,
stable tie-break, `TutorSourceRef` kimenet, index-load-failure fallback, latency
baseline, embedding-backend interfész.

**Kívül — TILOS:** cloud embedding, prompt-építés (R12), UI, a query trusted-content-té
tétele.

## 4. Engedélyezett fájlok

| Útvonal | Állapot | Miért |
|---|---|---|
| `.../data/knowledge/knowledge_index.dart` | ÚJ | offline index |
| `.../data/knowledge/knowledge_retriever.dart` | ÚJ | ranking + retrieval |
| `.../data/knowledge/asset_knowledge_repository.dart` | ÚJ | asset-betöltés |
| `.../domain/models/tutor_source_ref.dart` | ÚJ | forrásjelölés |
| `tool/build_tutor_knowledge_index.dart` | ÚJ | determinisztikus index-build |
| `docs/adr/0136-tutor-knowledge-retrieval.md` | ÚJ | retrieval-kontraktus ADR |
| `test/features/ai_tutor/data/*` | ÚJ | ranking/collapse/corrupt tesztek |
| `docs/baseline/epic-04-knowledge-retrieval.md` | ÚJ | latency baseline |
| `docs/rounds/e04-r07-*.md` | meglévő | §10 handoff |

**Tilos zóna:** minden más fájl, más feature belső contractja, `docs/rag`,
más kör briefje. Listán kívül → `stopped`.

## 5. Kötött architekturális döntések

1. A ranking **determinisztikus, stable tie-break**-kel (ADR 0135). **NEM
   elfogadható:** rendezéstől függő találati sorrend.
2. A **query user-inputja soha nem lesz trusted content** — a retriever kimenete
   `TutorSourceRef`, provenance-szal.
3. Index-load-failure **nem omlasztja az appot** (fallback), fail-loud logolással.
4. Az embedding-backend interfész nyitva marad (lexical az első backend).

## 6. Acceptance criteria

- [ ] hu és en query találatot ad; skill-boost és topic-filter tesztelt.
- [ ] **Discrimination mátrix** a min-score + max-result határra: score < min → kizárt;
      score = min → **inkluzív** (kötött); score > min → benne; és result-count = max /
      max+1 (a max+1. kimarad). Cellák géppel számítva a fixture-indexből.
- [ ] Duplicate-chunk collapse + stable tie-break (shuffle-invariáns) tesztelt.
- [ ] Corrupt index → fallback, nem crash; empty result kontrollált.
- [ ] Latency baseline dokumentált (load + query, fixture-indexen).

A reviewer a tie-break stabilitását vagy a min-score inkluzivitást eldobható
mutációval pirosra váltja.

## 7. Kötelező ellenőrzések

```bash
tools/round-gate.sh test/features/ai_tutor/data
```

Külön processzek, nincs `&&`/pipe/`tail`. CI = orchestrátor.

## 8. Implementációs sorrend

1. RED ranking-mátrix + collapse + corrupt tesztek.
2. Index + retriever + source-ref + asset-repo.
3. Determinisztikus index-build tool + latency baseline.
4. Additív export; gate.

Javasolt commit: `feat(ai-tutor-rag): add deterministic local knowledge retrieval`.

## 9. Kockázatok

- A lexical ranking könnyen nem-determinisztikussá válik (map-iterációs sorrend) —
  explicit stable rendezés kötelező.
- A query-injection kockázata: a retrieval-input nem eszkalálhat trust-szintet.

**STOP:** nem-determinisztikus ranking, query-trust eszkaláció vagy mércegyengítés
helyett dokumentált brief-revízió.

## 10. Implementation handoff — az implementer tölti ki

_(üres)_

## 11. Review — a független reviewer tölti ki

Tervezett review: `docs/reviews/e04-r07-offline-knowledge-index-retrieval-review.md`.
Merge csak exact-SHA zöld CI, §4-en belüli diff és nulla OPEN BLOCKER/MAJOR után.
