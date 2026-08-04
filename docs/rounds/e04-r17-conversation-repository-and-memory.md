# E04-R17 — Conversation repository, summary és inspectable memory

- **Státusz:** PREPARED (előre megírva 2026-08-04, kód olvasva: main @ `fbe1e82`)
- **SDD-kör:** [`docs/sdd/05-epic-04-ai-guitar-teacher.md`](../sdd/05-epic-04-ai-guitar-teacher.md) Kör 17; §35
- **Branch:** `codex/e04-r17-conversation-repository-and-memory`
- **Előfeltétel:** Epic 3 (E03-R22) lezárva; **E04-R02 merge**
- **Brief szerzője:** Claude (batch) · **Implementáció:** Codex (Terra)

```ai-router
schema_version = 1
risk = "high"
allowed_paths = [
  "lib/features/ai_tutor/domain/repositories/tutor_conversation_repository.dart",
  "lib/features/ai_tutor/domain/repositories/tutor_memory_repository.dart",
  "lib/features/ai_tutor/domain/models/tutor_memory_fact.dart",
  "lib/features/ai_tutor/data/repositories/local_tutor_conversation_repository.dart",
  "lib/features/ai_tutor/data/repositories/local_tutor_memory_repository.dart",
  "lib/core/storage/storage_keys.dart",
  "lib/features/ai_tutor/public.dart",
  "test/features/ai_tutor/data/local_tutor_conversation_repository_test.dart",
  "test/features/ai_tutor/data/local_tutor_memory_repository_test.dart",
  "docs/rounds/e04-r17-conversation-repository-and-memory.md",
]
gate_tests = [
  "test/features/ai_tutor/data",
]
native_gate = false
```

> ⚠ **Pre-flight (KÖTELEZŐ):** `origin/main` + E04-R02 merge; olvasd újra
> `AGENTS.md`, Chapter 1/2 (**storage szabályok**)/5, `HANDOFF.md`. Nincs ÚJ ADR
> (R01 **0134** memory-policy bővítése). `rg`: a `StorageKeys` `ss.` névtér +
> `StorageKeys.all`, a verziózott envelope + karantén minta (E03-R07/E02-R18);
> a `KeyValueStore`/`StorageException` mai alakja (silent-no-op tilalom!).
> PREPARED→PLANNING, brief commit az implementer ELŐTT.

## 0. Kör-jelzés és STOP-protokoll

```bash
tools/codex-signal.sh progress "<egy sor>" ; tools/codex-signal.sh done "<egy sor>"
tools/codex-signal.sh stopped "<egy sor>" ; tools/codex-signal.sh blocked "<egy sor>"
```

Lezáró jelzés nélkül a kör bukott. Listán kívüli fájl/contract → `stopped`.

## 0.0 Tervezési baseline és pre-flight revízió

**PREPARED — a mért §0.0-t az élesedő pre-flight tölti ki.** Nincs előre kiosztott ADR.

## 1. Cél

Lokális, verziózott beszélgetéstárolás, összegzés, **megtekinthető memória** és
**tényleges törlés** — corrupt rekord izolálásával.

## 2. Jelenlegi állapot

- Nincs tutor-repository (SDD §3.2/2). A `StorageKeys` `ss.` névtér + verziózott
  envelope + karantén (E02-R18 history, E03-R07 repo) a követendő minta.
- **Silent-no-op tilalom:** a cloud/tár-írás hibája sosem néma try/catch (round 17);
  a repository közvetlenül a `KeyValueStore`-ral ír, propagálja a `StorageException`-t.

## 3. Scope

**Benne:** conversation + memory repository contract, file/db lokális impl (Chapter 2),
atomikus save, conversation-index + pagination, structured summary (message-provenance),
memory-candidate dedup + sensitivity-filter, user view/edit/delete memory-fact,
retention policy, redacted export, **delete-all AI data**, corrupt-rekord izoláció.

**Kívül — TILOS:** UI (R22), cloud-sync (a remote törlés R22/R23 policy), provider-SDK.

## 4. Engedélyezett fájlok

| Útvonal | Állapot | Miért |
|---|---|---|
| `.../domain/repositories/tutor_conversation_repository.dart` | ÚJ | contract |
| `.../domain/repositories/tutor_memory_repository.dart` | ÚJ | contract |
| `.../domain/models/tutor_memory_fact.dart` | ÚJ | memory-fact modell |
| `.../data/repositories/local_tutor_conversation_repository.dart` | ÚJ | lokális impl |
| `.../data/repositories/local_tutor_memory_repository.dart` | ÚJ | lokális impl |
| `lib/core/storage/storage_keys.dart` | meglévő | tutor kulcsok (additív, `StorageKeys.all`-ba) |
| `lib/features/ai_tutor/public.dart` | előző körökből | additív export |
| `test/features/ai_tutor/data/*` | ÚJ | atomic/corrupt/delete tesztek |
| `docs/rounds/e04-r17-*.md` | meglévő | §10 handoff |

**Tilos zóna:** minden más fájl, más feature belső contractja, `docs/rag`,
más kör briefje. Listán kívül → `stopped`.

## 5. Kötött architekturális döntések

1. **Atomikus save**; corrupt conversation **izolált** (nem teszi olvashatatlanná az
   indexet) — karantén (ADR 0134). **NEM elfogadható:** egy sérült rekord az egész
   index elvesztése.
2. **A törlés tényleges** (local delete-all); a tár-írás hibája **nem néma** (StorageException propagál).
3. Memory-fact **megtekinthető/szerkeszthető/törölhető**; sensitivity-filter a candidate-re.
4. A storage-schema **verziózott**; jövőbeli schemaVersion kihagyva (E02-R18 minta).

## 6. Acceptance criteria

- [ ] atomic save; index-recovery; pagination; summary-provenance; memory-dedupe;
      **sensitive reject**; retention; **delete-all** ténylegesen üríti a kulcsokat;
      corrupt-record izolált; restart utáni betöltés.
- [ ] **Delete-all** után a `StorageKeys` tutor-kulcsai üresek — teszt; reviewer eldobható
      mutációval (egy kulcs kimarad a törlésből) pirosra váltja.
- [ ] Tár-írási hiba → `AppResult.failure`, NEM néma no-op.

## 7. Kötelező ellenőrzések

```bash
tools/round-gate.sh test/features/ai_tutor/data
```

Külön processzek, nincs `&&`/pipe/`tail`. CI = orchestrátor.

## 8. Implementációs sorrend

1. RED atomic/corrupt/delete-all/silent-no-op tesztek.
2. contract + memory-fact modell.
3. lokális impl + StorageKeys kulcsok.
4. Additív export; gate.

## 9. Kockázatok

- Silent-no-op csapda (round 17) — a hiba propagáljon, ne nyelje el try/catch.
- Delete-all hiányos scope — minden tutor-kulcsot lefedni (R22 UI erre épül).

**STOP:** néma tár-hiba, hiányos delete-all vagy corrupt-index-omlás helyett
dokumentált brief-revízió.

## 10. Implementation handoff — az implementer tölti ki

_(üres)_

## 11. Review — a független reviewer tölti ki

Tervezett review: `docs/reviews/e04-r17-conversation-repository-and-memory-review.md`.
Merge csak exact-SHA zöld CI, §4-en belüli diff és nulla OPEN BLOCKER/MAJOR után.
