# E04-R17 — Conversation repository, summary és inspectable memory

- **Státusz:** PLANNING (pre-flight élesítve 2026-08-05, kód olvasva: main @ `8fea8b2`)
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

**Élesítve 2026-08-05, main @ `8fea8b2`. Előfeltétel OK:** E04-R02 merge-elve
(`db778c4`, PR #125). Minden itt hivatkozott típust a kódban mértem ki.

### Mért baseline (grep-elve, nem táblából)

- **`KeyValueStore`** (`lib/core/storage/key_value_store.dart`): szinkron olvasók
  (`readString/readInt/…`, típus-eltérés → `null`, sosem dob), a **write sosem
  néma** — platform-hiba → `StorageException(code, {key, cause})`. `remove(key)`,
  `contains(key)` létezik. **`clear()`/`keys()` NINCS** a contracton → delete-all
  nem tud „minden kulcsot" törölni, csak a **tételesen felsorolt** tutor-kulcsokat
  (ezért a delete-all teszt a `StorageKeys` tutor-kulcslistáját járja be).
- **`AppResult<T>`** (`app_result.dart`): `sealed`, `Success`/`Failure`,
  `AppResult.failure(AppFailure)`. **`StorageFailure`** (`app_failure.dart`)
  `FailureCode.storageRead/storageWrite/storageUnavailable` kódokkal.
- **Silent-no-op ellenszer minta (E02-R18, mérve
  `local_practice_history_repository.dart`):** a repo a JSON-envelope-ot
  **közvetlenül** `keyValueStore.writeString(...)`-szel írja (nem a
  `JsonDocumentStore.write`-on át, mert az elnyeli a `StorageException`-t), a
  `StorageException`-t `catch`-eli és `AppResult.failure(StorageFailure)`-ré
  képezi. **Ezt kövesd.**
- **Karantén (`StorageKeys.quarantineOf(key) => '$key.corrupt'`)** + verziózott
  envelope (`{'schemaVersion': N, 'items': [...]}`) a követendő korrupt-izoláló
  minta. A `TutorConversationCodec` (már létezik, `supportedSchemaVersion = 1`,
  `TutorConversationCodecException`) és a `TutorConversation`/`TutorMessage`
  modellek (E04-R02) készen állnak — **a repo ezeket használja, nem ír újat.**
- **`StorageKeys.all`** guard-tesztjei (`key_value_store_test.dart` uniqueness +
  `startsWith('ss.')`, `diagnostics_storage_separation_test.dart` no
  `diag/pcm/wav`) **additív-biztosak** `ss.tutor.*` kulcsokra — nem kell
  módosítani őket, és nincsenek is a listán.
- **Memory-oldal greenfield:** `TutorMemoryFact`/`TutorMemoryRepository` ma nem
  létezik (grep: nincs találat) — ÚJ contract + modell + lokális impl.

### §0.0 revízió-1 — `public.dart` kivétele az engedélyezett listából (autonómia: lista-szűkítés)

**Mért ütközés:** `test/features/ai_tutor/ai_tutor_boundary_test.dart` (NINCS az
engedélyezett listán) azt állítja, hogy a `public.dart` **nulla** import/export
direktívát tartalmaz (üres-boundary invariáns, HANDOFF §6: az export „R16+-ra
halasztva", amíg valódi külső hívó nem érkezik). Ha az implementer additív
exportot ír a `public.dart`-ba, ez a **tilos zónában lévő** teszt pirosra vált,
és nem javítható a scope-on belül. A repository-k/modellek a feature-en **belül**
közvetlen importtal elérhetők (R12/R13 mintája), így a publikus export nem
előfeltétele az acceptance-nek. **Feloldás:** `lib/features/ai_tutor/public.dart`
törölve az `allowed_paths`-ból és a §4 tábla additív-export sora törölve. Az
üres-boundary invariáns zöld marad. (ADR 0087 §2 — engedélyezett-fájllista
szűkítése az orchestrátor hatásköre.)

### ADR: nincs új (ADR 0134 hatálya)

Ez a kör **nem hoz új architekturális döntést** — ADR 0134 (memory-policy:
local-first, megtekinthető/szerkeszthető/törölhető, dokumentált retention) már
rögzíti a policyt, a tárolási mintát pedig ADR 0084 (verziózott envelope +
karantén) és ADR 0090 (atomikus save + korrupt-izoláció) adja; a privacy-korlát
ADR 0132. Új ADR-szám **nem** kerül lefoglalásra (mért döntés, a brief batch-kori
állítását megerősíti).

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

### Megvalósítás

- `StorageKeys`: három additív `ss.tutor.*` kulcs és a tételes
  `tutorAiData` delete-all lista; a kulcsok a globális `all` listába is
  bekerültek.
- Conversation repository: verziózott dokumentum-envelope, dokumentumokból
  helyreállítható index, lapozás, message-provenance summary és rekord-szintű
  karantén. A dokumentum az index előtt íródik, ezért index-írási hiba után a
  mentett beszélgetés a következő olvasáskor visszanyerhető.
- Memory repository: candidate-deduplikáció, érzékeny-content elutasítás,
  inspect/edit/delete, explicit retention purge, redaktált export és minden
  deklarált tutor-kulcsot (a karanténjával együtt) törlő delete-all.
- A két új teszt a fenti acceptance-útvonalakat, restartot és a
  `StorageException` → `StorageFailure` nem-néma hibautat méri.

### Ellenőrzések

- RED: a két új repository-teszt a még nem létező contractok/implementációk
  miatt fordítási hibával megállt.
- `flutter test test/features/ai_tutor/data/local_tutor_conversation_repository_test.dart`
  — 6 teszt zöld.
- `flutter test test/features/ai_tutor/data/local_tutor_memory_repository_test.dart`
  — 6 teszt zöld.
- `flutter test test/features/ai_tutor/data` — 109 teszt zöld.
- `flutter analyze` — a `tools/prepare-flutter-generated.sh` előkészítés után
  zöld, nulla lelettel.
- `tools/round-gate.sh test/features/ai_tutor/data` — format, analyze, 109
  célzott teszt, architecture és secrets: zöld.
- Eltávolítható mutáció: a `tutorMemoryFacts` törlésének ideiglenes kihagyása
  a delete-all tesztet és a tárolóhiba-tesztet is pirosra váltotta; a változás
  azonnal vissza lett vonva.

### Eltérés / nem futtatott ellenőrzés

- Nincs scope-eltérés. A teljes CI-t és az APK-buildet az orchestrátor indítja.

## 11. Review — a független reviewer tölti ki

Tervezett review: `docs/reviews/e04-r17-conversation-repository-and-memory-review.md`.
Merge csak exact-SHA zöld CI, §4-en belüli diff és nulla OPEN BLOCKER/MAJOR után.
