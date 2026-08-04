# E04-R06 — Kurált tutor tudásbázis schema és első content pack

- **Státusz:** PREPARED (előre megírva 2026-08-04, kód olvasva: main @ `fbe1e82`)
- **SDD-kör:** [`docs/sdd/05-epic-04-ai-guitar-teacher.md`](../sdd/05-epic-04-ai-guitar-teacher.md) Kör 6; §35
- **Branch:** `codex/e04-r06-knowledge-schema-and-content-pack`
- **Előfeltétel:** Epic 3 (E03-R22) lezárva; **E04-R01 merge**
- **Brief szerzője:** Claude (batch) · **Implementáció:** Codex (Terra)

```ai-router
schema_version = 1
risk = "high"
allowed_paths = [
  "assets/tutor_knowledge/manifest.json",
  "assets/tutor_knowledge/en/",
  "assets/tutor_knowledge/hu/",
  "lib/features/ai_tutor/data/knowledge/knowledge_document.dart",
  "lib/features/ai_tutor/data/knowledge/knowledge_codec.dart",
  "tool/build_tutor_knowledge_manifest.dart",
  "lib/features/ai_tutor/public.dart",
  "pubspec.yaml",
  "test/features/ai_tutor/data/knowledge_codec_test.dart",
  "test/features/ai_tutor/data/knowledge_manifest_test.dart",
  "docs/rounds/e04-r06-knowledge-schema-and-content-pack.md",
]
gate_tests = [
  "test/features/ai_tutor/data",
]
native_gate = false
```

> ⚠ **Pre-flight (KÖTELEZŐ):** `origin/main` + E04-R01 merge; olvasd újra
> `AGENTS.md` (**§9 DSP-tilalom!**), Chapter 1/5, `HANDOFF.md`. **ADR-reconcile:**
> a batch **0135**-öt oszt (tutor-knowledge-governance); ha E03-R21/R22 vagy a
> korábbi Epic 4 körök eltolták, javítsd. `rg`/`ls`: a `docs/rag/chunks/` mai
> tartalma (**NEM másolható** ide), a `pubspec.yaml` `assets:` szekciója.
> PREPARED→PLANNING, brief commit az implementer ELŐTT.

## 0. Kör-jelzés és STOP-protokoll

```bash
tools/codex-signal.sh progress "<egy sor>" ; tools/codex-signal.sh done "<egy sor>"
tools/codex-signal.sh stopped "<egy sor>" ; tools/codex-signal.sh blocked "<egy sor>"
```

Lezáró jelzés nélkül a kör bukott. Listán kívüli fájl/contract → `stopped`.

## 0.0 Tervezési baseline és pre-flight revízió

**PREPARED — a mért §0.0-t az élesedő pre-flight tölti ki.** Előre kiosztott ADR:
**0135** (tutor-knowledge-governance) — **orchestrátor** írja a pre-flightban, NEM
implementer-diff, NEM TOML `allowed_paths`.

## 1. Cél

Felhasználói célú, **review-zott, verziózott** gitároktatási tudásbázis
létrehozása, a fejlesztői DSP RAG-től **szigorúan elkülönítve**.

## 2. Jelenlegi állapot

- Nincs user-célú tutor knowledge pack (SDD §3.2/6/7); a `docs/rag/chunks/`
  **fejlesztői DSP-anyag** (AGENTS.md §9), NEM tanulói tartalom → nem másolható.
- `assets/` és `pubspec.yaml` `assets:` szekció létezik — additív bővítés.
- Nincs approval-lifecycle vagy manifest-hash konvenció tutor-tartalomra.

## 3. Scope

**Benne:** `KnowledgeDocument`/`KnowledgeChunk` schema, approved/reviewNeeded/
rejected lifecycle, első jogtiszta en+hu dokumentumok (rhythm/chord/technique/
practice/safety), locale+skill+difficulty+license+hash minden dokumhoz,
determinisztikus build-tool, **approved-only** production manifest, content review
checklist, CI hash-ellenőrzés.

**Kívül — TILOS:** `docs/rag` automatikus másolása, retrieval/index (R07), UI,
jogvédett/harmadik-fél tartalom.

## 4. Engedélyezett fájlok

| Útvonal | Állapot | Miért |
|---|---|---|
| `assets/tutor_knowledge/manifest.json` | ÚJ | approved-only manifest |
| `assets/tutor_knowledge/en/`, `.../hu/` | ÚJ | jogtiszta en/hu dokumentumok |
| `.../data/knowledge/knowledge_document.dart` | ÚJ | document/chunk schema |
| `.../data/knowledge/knowledge_codec.dart` | ÚJ | determinisztikus codec |
| `tool/build_tutor_knowledge_manifest.dart` | ÚJ | reprodukálható build |
| `lib/features/ai_tutor/public.dart` | előző körökből | additív export |
| `pubspec.yaml` | meglévő | assets-bejegyzés (csak additív) |
| `test/features/ai_tutor/data/*` | ÚJ | schema/hash/approved-only tesztek |
| `docs/rounds/e04-r06-*.md` | meglévő | §10 handoff + review checklist |
| `docs/adr/0135-tutor-knowledge-governance.md` | ÚJ (pre-flight, **orchestrátor**) | governance döntés |

**Tilos zóna:** `docs/rag` (olvasható precedensként, de NEM másolható),
minden más fájl, más kör briefje. Listán kívül → `stopped`.

## 5. Kötött architekturális döntések

1. **ADR 0135:** a user tutor knowledge pack **külön** a `docs/rag` DSP-anyagtól;
   automatikus másolás TILOS; a production manifest **kizárólag approved** dokumentumot
   tartalmaz. **NEM elfogadható:** reviewNeeded/rejected dokumentum a production buildben.
2. Minden dokumentum locale+skill+difficulty+license+**hash**-t hordoz; determinisztikus
   chunking → reprodukálható build.
3. CI ellenőrzi a manifest+chunk hash-eket.

## 6. Acceptance criteria

- [ ] Manifest schema-validált; **duplicate ID**, **missing license**, **hash
      mismatch**, **corrupt content** külön hibakóddal elutasított (mind a 4 eset).
- [ ] **Approved-only build:** reviewNeeded/rejected dokumentum kizárva a production
      manifestből — teszt bizonyítja; **NEM elfogadható** enyhébb szűrés.
- [ ] Locale coverage: rhythm/chord/technique/practice/safety mind en+hu.
- [ ] A build **reprodukálható** (kétszeri futtatás bit-azonos manifest/chunk).

A reviewer az approved-only szűrőt eldobható mutációval (egy reviewNeeded átcsúszik)
pirosra váltja.

## 7. Kötelező ellenőrzések

```bash
tools/round-gate.sh test/features/ai_tutor/data
```

Külön processzek, nincs `&&`/pipe/`tail`. A `pubspec.yaml` assets-változás CI-ben
asset-gate alatt is fut. CI = orchestrátor exact-SHA dispatch.

## 8. Implementációs sorrend

1. Schema + codec + RED hash/approved-only tesztek.
2. Első en+hu dokumentumok + license/hash.
3. Determinisztikus build-tool + manifest.
4. `pubspec.yaml` assets; gate.

Javasolt commit: `feat(ai-tutor-knowledge): add curated versioned tutor knowledge pack`.

## 9. Kockázatok

- **Jogtisztaság:** csak saját/engedélyezett tartalom, license-mezővel — jogvédett
  tab/lyrics TILOS.
- A `docs/rag` másolásának kísértése (AGENTS.md §9) → `stopped`, nem néma átemelés.

**STOP:** `docs/rag` másolás, approved-only gyengítés vagy licenc-hiányos dokumentum
helyett dokumentált brief-revízió.

## 10. Implementation handoff — az implementer tölti ki

_(üres)_

## 11. Review — a független reviewer tölti ki

Tervezett review: `docs/reviews/e04-r06-knowledge-schema-and-content-pack-review.md`.
Merge csak exact-SHA zöld CI, §4-en belüli diff és nulla OPEN BLOCKER/MAJOR után.
