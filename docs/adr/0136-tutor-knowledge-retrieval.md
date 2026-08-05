# ADR 0136 — Deterministic offline tutor knowledge retrieval

- **Státusz:** Elfogadva (E04-R07 pre-flight, 2026-08-05)
- **Kör:** E04-R07 — Offline knowledge index és retrieval
- **Implementer motor:** Codex (`gpt-5.6-terra`, örökölt kézi override, `codex-round.sh`)
- **Epic:** [Chapter 5 — Epic 4: AI Guitar Teacher](../sdd/05-epic-04-ai-guitar-teacher.md) Kör 7
- **Kontext-ADR-ek:** [0135](0135-tutor-knowledge-governance.md) (knowledge governance,
  approved-only hash-lezárt manifest), [0131](0131-ai-tutor-provider-boundary.md)
  (provider-boundary, determinisztikus on-device coaching),
  [0132](0132-ai-tutor-privacy-and-consent.md) (privacy/consent)

## Kontextus

Az ADR 0135 (E04-R06) leszállította a felhasználói célú, approved-only,
hash-lezárt tutor tudásbázist (`assets/tutor_knowledge/` + determinisztikus
manifest), de **hívó és retrieval nélkül** (`public.dart` üres marad). Ahhoz,
hogy a későbbi prompt-körök (R12/R16) forrásmegjelöléssel tudjanak a tudásbázisra
támaszkodni, kell egy **determinisztikus, offline** keresési réteg, amely a
manifestből + a chunkolt dokumentumtartalomból relevancia szerint sorrendez.

Mért kiindulás (baseline `main` @ `e79a0eb`, E04-R07 pre-flight):

- `lib/features/ai_tutor/data/knowledge/` tartalma: `knowledge_document.dart`
  (`KnowledgeDocument`/`KnowledgeChunk` immutable schema), `knowledge_codec.dart`
  (determinisztikus JSON codec + bekezdés-chunker). **Retrieval/index nem
  létezik.**
- A `KnowledgeDocument` **mért** mezőkészlete (`knowledge_document.dart:81–93`):
  `schemaVersion`, `id`, `locale`, `skill` (`KnowledgeSkill`: rhythm/chord/
  technique/practice/safety), `difficulty` (`KnowledgeDifficulty`: beginner/
  intermediate/advanced), `license`, `version`, `status`, `title`, `body`,
  `contentHash`. **Nincs `topic`, `keywords` vagy `heading` mező** — sem a
  domain schemában, sem az asset-JSON-okban (`assets/tutor_knowledge/**`).
- `lib/features/ai_tutor/public.dart` **üres** boundary (csak `library;`
  deklaráció), amit a `test/features/ai_tutor/ai_tutor_boundary_test.dart`
  nulla-import/export invariánssal őriz (E04-R02 óta). Bármely export → RED.
- Determinizmus-precedens: E03-R05 capability-resolver és E02-R09 matcher
  (stable tie-break, fail-loud).

## Döntés

1. **Lexical-first, determinisztikus ranking.** A retrieval első (és e körben
   egyetlen) backendje egy **lexical** ranker a manifestből épített offline
   indexen. A relevancia a **ténylegesen létező szövegmezőkből** számítódik:
   dokumentum-`title` (magasabb súly) és a chunk `content` / dokumentum-`body`
   (alacsonyabb súly) token-egyezései. **Nincs külön `keywords`/`heading` mező**
   (mérve: nem létezik), ezért ezek nem képezik a ranking bemenetét; a jövőbeli
   embedding-backend interfésze nyitva marad.

2. **`topic` ≡ `skill`.** A brief „topic-filter" fogalma a mért schemában a
   `KnowledgeSkill` enumnak felel meg. Az index **locale + skill + difficulty**
   szerint szűrhető/boostolható — mindhárom mező létezik. `topic` néven külön
   dimenzió nem jön létre.

3. **Stable tie-break, shuffle-invariáns.** Azonos score-ú találatok sorrendje
   **determinisztikus, forrás-iterációtól független** kulcson dől el (pl.
   `(score desc, documentId asc, chunkIndex asc)`). Rendezéstől/map-iterációtól
   függő találati sorrend **nem elfogadható** (ADR 0135 determinizmus-vonala).

4. **Provenance-olt kimenet.** A retriever kimenete `TutorSourceRef` érték,
   amely a forrásdokumentumot/chunkot azonosítja (id, locale, skill, chunk-hash).
   A **query user-inputja soha nem válik trusted contenté** — a retrieval nem
   eszkalál trust-szintet, csak forrásjelölt referenciát ad vissza.

5. **Inkluzív min-score, kötött max-result.** A policy-határok determinisztikusak
   és a fixture-indexből géppel számítottak: `score < minScore` → kizárt;
   `score == minScore` → **benne** (inkluzív `>= minScore`); a találatok száma
   `maxResults`-ban felülről kötött (a `maxResults + 1`. kimarad).

6. **Fail-loud, nem-omlasztó index-load.** Corrupt/olvashatatlan index → stabil
   hibakóddal logolt **fallback** (üres/kontrollált eredmény), az app nem
   omlik össze. Az üres eredmény kontrollált, nem kivétel.

7. **Belső réteg, export nélkül (allowed-list szűkítés).** E kör **nem exportál**
   a `public.dart`-ból — a retrieval `data/knowledge/` + `domain/models/` belső
   marad, mert (a) nincs még hívó (R12/R16 fogyasztja), és (b) az üres-boundary
   invariánst a `ai_tutor_boundary_test.dart` őrzi. Ezért a brief eredeti
   allowed_paths listájából a `lib/features/ai_tutor/public.dart` **eltávolítva**
   (§0.0 revízió). Production viselkedés változatlan.

## Következmények

- A retrieval a hash-lezárt, approved-only manifestre (ADR 0135) épül; a
  reprodukálhatóság öröklődik: kétszeri index-build bit-azonos.
- A stable tie-break és a min-score inkluzivitás regressziót fog: eldobható
  mutáció (pl. `>=` → `>`, vagy a másodlagos rendezőkulcs elvétele) a
  discrimination-mátrix / shuffle-invariáns tesztet azonnal pirosra váltja.
- Az embedding-backend interfésze nyitva marad; a lexical az első
  implementáció, nem a végállomás — a `TutorSourceRef` kontraktus stabil.
- Mivel a réteg belső marad (nincs export), a `public.dart` üres-boundary
  invariáns sértetlen; a hívó bekötése külön, későbbi kör (R12) döntése.
