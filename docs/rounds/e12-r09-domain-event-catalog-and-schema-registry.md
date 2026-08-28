# E12-R09 — Domain event catalog és schema registry

- **Státusz:** PRE-FLIGHT KÉSZ (előre megírva 2026-08-27; pre-flight mérés + §0.0 revízió 2026-08-28, kód mérve: `main @ bbe86b1a`)
- **Típus:** Chapter 12 (Release Roadmap, Sprint Planning & Final Integration), Kör 9
- **Kör-azonosító:** `E12-R09`
- **Branch:** `sonnet-impl/e12-r09-domain-event-catalog-and-schema-registry`
- **Előfeltétel:** `E12-R02` merge-elve (a fejezet-index adja a producer/consumer oszlop Chapter-hivatkozásait)
- **Brief szerzője:** Claude (Opus 5)
- **ADR:** [`ADR 0468`](../adr/0468-domain-event-catalog-and-schema-registry.md) — a pre-flight írta és commitolta. (A batch-terv `0450`-et jelölt ki; a foglaló `0468`-at adta, mert a `0466`/`0467` időközben landolt — a normatív forrás a foglaló, lásd az ADR sorszám-megjegyzését.)

**Visszakeresett előzmény:** `node tools/knowledge-rag.mjs --corpus lessons,halts,adr --top 5 "domain event catalog envelope schema version idempotency cross-feature"` → **[ADR 0329](../adr/0329-canonical-activity-event-contracts.md)** (kanonikus tanulási esemény-szerződések: kötelező `schemaVersion`, hívó-adta stabil `eventId`, `type` discriminator, egyetlen `public.dart` belépő) és **[ADR 0176](../adr/0176-cross-feature-public-barrel-recognition.md)** (a cross-feature import audit a beágyazott barrelt is elfogadja). A kör ezekre ÉPÜL — nem tervez új envelope-ot melléjük.

**Pre-flight visszakeresés (2026-08-28, ADR 0312 §4.9 sorrendben):**
`--corpus lessons,halts,adr "domain event catalog fixture schemaVersion round-trip unknown field tolerance"` → **[ADR 0215](../adr/0215-analysis-document-versioning.md)** (ismeretlen VAGY alacsonyabb `schemaVersion` = kontrollált hiba, nem best-effort olvasás) és **[ADR 0329](../adr/0329-canonical-activity-event-contracts.md)** (nincs „legyen 1" default; a bővítés ára új verziószám + explicit migrációs ág). `--corpus lessons,halts "acceptance cella elérhetetlen küszöb"` → **[L443](../LESSONS.md#l443)** (a küszöb-cella, amely csak egy tiszta predikátumot hív, a tiltott implementáción is zöld marad — a cellának a VALÓDI belépőt kell hívnia), **[L477](../LESSONS.md#l477)** (mérd a cella BUKÁSI KÉPESSÉGÉT, ne csak a zöldjét), **[L273](../LESSONS.md#l273)** (ne injektálj olyan köztes artefaktumot, amit a lánc maga nem termel). Ezek a §0.0/b–d revíziók forrásai.

## 0.0 A kör MÉRT kiindulópontja: az esemény-szerződés MÁR LÉTEZIK

A SDD Kör 9 „implementáld a `DomainEventEnvelope` core típust" feladata a fán RÉSZBEN teljesült: a `LearningActivityEvent` sealed hierarchia (ADR 0329) hat altípussal, verziózott sémával és stabil azonosítóval ÉL, a gamification feature `public.dart` barrelje mögött. Ami HIÁNYZIK: (a) a katalógus-DOKUMENTUM (producer, consumer, owner, schema-verzió, idempotencia-kulcs), (b) a fixture-készlet, (c) a séma-kompatibilitási teszt (ismeretlen mező tolerancia, additív bővítés). Ez a kör ezt a hármat szállítja, és **nem vezet be konkurens envelope-típust**.

### 0.0 REVÍZIÓ (pre-flight, 2026-08-28, orchestrátor: Claude Opus 5)

A pre-flight a brief MINDEN mért állítását újramérte a `main @ bbe86b1a` fán. Öt ponton a brief eredeti szövege nem egyezett a fával; a revízió az ADR 0087 §2 szerint az orchestrátor hatásköre (a kör saját, még nem merge-elt artefaktuma).

**(a) A producer-szám MÉRVE hét fájl, nem kilenc adapter.** `grep -rn "PracticeActivityEvent(\|SongActivityEvent(\|AnalysisActivityEvent(\|PlanActivityEvent(\|TutorActivityEvent(\|VisionActivityEvent(" lib/` → 8 konstruktor-hívás 7 fájlban:

| Altípus | Producer fájl (MÉRT) |
|---|---|
| `PracticeActivityEvent` | `lib/features/practice/application/gamification_practice_adapter.dart:226` · `lib/features/learn/application/gamification_lesson_adapter.dart:201` (source: `learn`) · `lib/features/gamification/data/migration/legacy_practice_adapter.dart:65` |
| `SongActivityEvent` | `lib/features/songs/application/gamification_song_adapter.dart:362` és `:423` |
| `AnalysisActivityEvent` | `lib/features/analyze/application/gamification_analysis_adapter.dart:223` |
| `PlanActivityEvent` | `lib/features/practice_generator/application/gamification_plan_adapter.dart:231` |
| `VisionActivityEvent` | `lib/features/vision/application/gamification_vision_adapter.dart:238` és `:281` |
| `TutorActivityEvent` | **NINCS producer a `lib/**`-ban (MÉRVE)** |

**(b) A `TutorActivityEvent` szándékosan termelő nélküli — ezt kimondani kell, nem kitalálni.** `lib/features/ai_tutor/application/gamification_tutor_adapter.dart:18–19` és `:164` kifejezetten írja, hogy a tutor-session `PracticeActivityEvent`-ként jutalmazódik, és „do NOT build a `TutorActivityEvent`". A katalógus tutor-sora tehát explicit „nincs producer (mért)" cellát hordoz indokkal, és ezt a hiányt a mérce is méri (új **A8** cella) — különben a jelölés a kitalált hivatkozás olcsó búvóhelye lenne. Ez az ADR 0468 D3.

**(c) A küszöb-cellahármas „alatta" cellája az EREDETI alakjában ELÉRHETETLEN volt.** MÉRVE: `learningActivityEventSchemaVersion = 1` (`learning_activity_event.dart:5`), és `_validateEventFields` (`:441`, a `schemaVersion`-ág `:450–456`) `schemaVersion != 1` esetén `ArgumentError`-t dob — a `fromJson` MINDEN altípusa ezen a factoryn megy át. Tehát `V = 1`, és a `schemaVersion < V` **nem** „dekódolható marad", hanem ugyanúgy kontrollált hiba. Az eredeti cella csak `lib/**` módosításával lett volna teljesíthető, ami ebben a körben TILOS (§3) — a §6 küszöb-hármasa ezért a mért viselkedésre íródott át. Precedens: ADR 0215 2. pont (alacsonyabb verzió = kontrollált hiba, nem best-effort olvasás).

**(d) A fixture-öknek KANONIKUSNAK kell lenniük, különben az A1 hamisan piros vagy hamisan zöld.** MÉRVE: `toJson()` az `occurredAt`-ot `DateTime.toIso8601String()`-gel írja (UTC bemenetnél `…T10:00:00.000Z`, tehát ezredmásodperccel), a `duration`-t `durationMicroseconds` egészként, a `score`-t `double`-ként. Egy `"2026-08-20T10:00:00Z"` (ezredmásodperc nélküli) vagy nem UTC ofszetes időbélyeg, illetve egy egész `1` `score` a mező-azonos összevetést elrontja. A fixture-ök ezért BYTE-szinten azt tartalmazzák, amit a `toJson()` termel; ezt új **A7** cella méri. Ez az ADR 0468 D5.

**(e) A `_DecodedEvent.fromJson` MÉRT viselkedése alátámasztja az A2–A4-et — a cellák a VALÓDI belépőt hívják.** Ismeretlen extra mező: a dekódoló csak a nevesített kulcsokat olvassa, a többit eldobja → tolerált. Hiányzó `schemaVersion`: `_requireInt` → `ArgumentError`. Ismeretlen `type`: a `switch` default ága → `ArgumentError`. **A cellák KÖTELEZŐEN a `LearningActivityEvent.fromJson`-t hívják** (a `package:strumsight/features/gamification/public.dart` barrelen keresztül), sosem egy tesztben újraírt segéd-predikátumot — L443.

**(f) Változatlanul mérve:** hat altípus (`practice`, `song`, `analysis`, `plan`, `tutor`, `vision`), `ActivitySource` = `{live, analyze, learn, practice, songTrainer, vision, tutor, practicePlan}`, `EvidenceTrust` = `{unverified, userConfirmed, deviceObserved, scored, verified}`, `lib/features/community/application/outbox/community_outbox.dart` = 460 sor (külön, community-oldali szerződés — NEM része ennek a katalógusnak, ADR 0468 „Amit ez az ADR NEM dönt el"), `docs/contracts/` = egyetlen fájl, `test/fixtures/events/` és `test/core/events/` nem létezik.

```ai-router
schema_version = 1
risk = "normal"
allowed_paths = [
  "docs/contracts/event-catalog.md",
  "test/fixtures/events/practice_session_completed_v1.json",
  "test/fixtures/events/song_session_completed_v1.json",
  "test/fixtures/events/analysis_completed_v1.json",
  "test/fixtures/events/plan_completed_v1.json",
  "test/fixtures/events/tutor_session_completed_v1.json",
  "test/fixtures/events/vision_session_completed_v1.json",
  "test/core/events/event_schema_compatibility_test.dart",
  "docs/rounds/e12-r09-domain-event-catalog-and-schema-registry.md",
]
gate_tests = [
  "test/core/events/event_schema_compatibility_test.dart",
]
native_gate = false
```

## 0. Kör-jelzés és STOP-protokoll

```bash
tools/codex-signal.sh progress "<egy sor>"
tools/codex-signal.sh done "<egy sor>"
tools/codex-signal.sh stopped "<egy sor>"
tools/codex-signal.sh blocked "<egy sor>"
```

**STOP-protokoll:** ha a katalógus egy MÉRT ellentmondást talál a kódban (pl. egy altípus `schemaVersion` kezelése eltér az ADR 0329-től), a kimenet a `stopped` jelzés és jelentés — a `lib/**` javítása ebben a körben TILOS. Ugyanígy `stopped`, ha egy acceptance-cella csak a `lib/**` (vagy bármely, a §4 listán kívüli fájl) módosításával lenne teljesíthető: NE tágítsd a listát, jelezz.

## 1. Cél

A cross-feature események egyetlen, verziózott, tulajdonossal ellátott katalógusa és gépi kompatibilitás-mércéje — a meglévő `LearningActivityEvent` szerződés lecserélése nélkül.

## 2. Jelenlegi állapot — mért tények

- `lib/features/gamification/domain/activity/learning_activity_event.dart`: `sealed class LearningActivityEvent`, kötelező `schemaVersion`, hívó-adta `eventId`, `type` discriminator; altípusok: `PracticeActivityEvent`, `SongActivityEvent`, `AnalysisActivityEvent`, `PlanActivityEvent`, `TutorActivityEvent`, `VisionActivityEvent`.
- **Producerek: 8 konstruktor-hívás 7 fájlban** — a tételes, mért táblát a §0.0/(a) tartalmazza. A `TutorActivityEvent`-nek NINCS producere (§0.0/(b)).
- Fogyasztók (MÉRVE, `grep -rln "LearningActivityEvent" lib/`): `application/activity_event_ingestor.dart`, `application/achievement_evaluator.dart` (típus-switch a `:633–639` sorokon), `application/streak_service.dart`, `infrastructure/default_streak_policy.dart`, `data/activity_outbox_repository.dart`, `data/local_activity_outbox_repository.dart` (kódolás/dekódolás: `:218–219`, `:553`, `:623`).
- Idempotencia (ADR 0333): `activity_event_ingestor.dart:61` kikényszeríti az `entry.sourceEventId == event.eventId`-t, a ledger append-if-absent a `sourceEventId`-re szűr (`local_reward_ledger_repository.dart:77`). **Az idempotencia-kulcs tehát az `eventId`.**
- `lib/features/community/application/outbox/community_outbox.dart` (460 sor) külön, community-oldali outbox — nem tárgya ennek a katalógusnak.
- `docs/contracts/` MA egyetlen fájlt tartalmaz (`community-share-artifacts.md`); `test/fixtures/events/` és `test/core/events/` **nem létezik**.
- Precedens arra, hogy teszt futásidőben repo-fájlt olvas: `test/tooling/sdd_index_guard_test.dart` (a munkakönyvtár a package gyökere).

## 3. Scope

**Benne van:** `docs/contracts/event-catalog.md` — MINDEN cross-feature esemény: `type` kód, séma-verzió, PRODUCER (mért fájl), CONSUMER (mért fájl), idempotencia-kulcs, owner Chapter, kompatibilitási szabály · hat JSON fixture (altípusonként egy, a MÉRT mezőnevekkel, kanonikus alakban) · `test/core/events/event_schema_compatibility_test.dart`: round-trip minden fixture-re, ISMERETLEN mező tolerálása (additív bővítés), ismeretlen `type` és hiányzó `schemaVersion` KONTROLLÁLT hibája, a séma-verzió kétirányú határa, a katalógus-hivatkozások gépi ellenőrzése.

**NINCS benne (tilos):**

- Bármely `lib/**` fájl módosítása — beleértve új `lib/core/events/` könyvtár létrehozását (a szerződés a gamification barrel mögött él, ADR 0329/0176/0468 D1).
- Új esemény-altípus bevezetése.
- `docs/adr/**` — az ADR 0468-at a pre-flight már megírta és commitolta.
- Meglévő teszt módosítása (a `test/features/gamification/domain/activity_event_test.dart` a legacy referencia, érintetlen marad).

## 4. Engedélyezett fájlok

| Útvonal | Indok |
|---|---|
| `docs/contracts/event-catalog.md` | ÚJ — a katalógus |
| `test/fixtures/events/*.json` (6 fájl, a §0.0 ai-router blokk tételes listája) | ÚJ — altípusonként egy fixture |
| `test/core/events/event_schema_compatibility_test.dart` | a §6 cellái |
| `docs/rounds/e12-r09-domain-event-catalog-and-schema-registry.md` | a §10 handoff kitöltése |

**Tilos zóna:** `lib/**` · `backend/**` · `.github/**` · `docs/adr/**` · `tools/**` · minden meglévő teszt

## 5. Kötött architekturális döntések (ADR 0468)

### 5.1 A katalógus a KÓDBÓL mért, nem a SDD-ből másolt (D2)

Minden sor producer/consumer oszlopa létező fájlra (és ahol értelmes, sorra) hivatkozik. **NEM elfogadható gyengítés:** a `docs/sdd/12-…` §14.1 „közös események" listájának átmásolása anélkül, hogy a fán megkeresnék a tényleges termelőt — a SDD terv, a kód a valóság.

### 5.2 Az ismeretlen MEZŐ tolerált, az ismeretlen TÍPUS nem (D4)

Additív séma-bővítés (új mező) nem törheti a régi olvasót; ismeretlen `type` vagy hiányzó `schemaVersion` viszont kontrollált hiba (ADR 0329 1. pont). **NEM elfogadható gyengítés:** „legyen 1 az alapértelmezés" a hiányzó verzióra.

### 5.3 A séma-verzió határa MINDKÉT irányban zár (D4)

`V = learningActivityEventSchemaVersion = 1`. A `< V` és a `> V` egyaránt kontrollált hiba — a katalógus kompatibilitási oszlopa ezt írja le, nem egy tervezett „legacy olvasó" ágat. **NEM elfogadható gyengítés:** a katalógusban „a v0 best-effort olvasható" mondat, amit a kód cáfol.

### 5.4 A „nincs producer" MÉRT állítás, amit a mérce is mér (D3)

Ha egy altípusnak nincs termelője a fán, a katalógus ezt explicit jelöléssel és indokkal mondja ki; az **A8** cella gépileg ellenőrzi, hogy a jelölés igaz (a típus konstruktor-hívása sehol nem szerepel a `lib/**`-ban). **NEM elfogadható gyengítés:** kitalált producer-útvonal, vagy a tutor-sor elhagyása a katalógusból.

### 5.5 A fixture kanonikus (D5)

Minden fixture BYTE-szinten az, amit az adott esemény `toJson()`-je termel (`occurredAt` = `toIso8601String()` UTC alak ezredmásodperccel és `Z`-vel; `durationMicroseconds` egész; `score` tizedes tört). **NEM elfogadható gyengítés:** kézzel „szépített" mezőnév vagy időbélyeg-alak.

## 6. Acceptance criteria

| # | Kritérium | Bizonyíték |
|---|---|---|
| A1 | Mind a hat fixture round-trip-el (dekódolás → kódolás → dekódolás, mezőazonos) | `event_schema_compatibility_test.dart` |
| A2 | Ismeretlen EXTRA mezővel bővített fixture továbbra is dekódolható, és a dekódolt esemény mezőazonos az eredetivel | ugyanaz a teszt |
| A3 | Hiányzó `schemaVersion` → kontrollált hiba (nem csendes default) | ugyanaz a teszt |
| A4 | Ismeretlen `type` → kontrollált hiba | ugyanaz a teszt |
| A5 | A katalógus MINDEN producer/consumer hivatkozása létező fájlra mutat, ÉS producer-cellánál a hivatkozott fájl tartalmazza az adott altípus konstruktor-hívását | ugyanaz a teszt (katalógus-parsoló cella) |
| A6 | Minden katalógus-sorhoz tartozik owner Chapter és idempotencia-kulcs, és mind a hat `type` kód szerepel a katalógusban | a katalógus + a teszt mező-cellája |
| A7 | Mind a hat fixture KANONIKUS: `jsonDecode(fixture)` mezőazonos a `LearningActivityEvent.fromJson(fixture).toJson()` eredményével | ugyanaz a teszt |
| A8 | A katalógus „nincs producer" jelölésű sorai igazak: az adott altípus konstruktor-hívása sehol nem szerepel a `lib/**` fában | ugyanaz a teszt |

**Küszöb-cellahármas a séma-verzióra** (a MÉRT támogatott verzió `V = learningActivityEventSchemaVersion = 1`; a mért határ MINDKÉT irányban zár — §0.0/(c)): a küszöb **alatt** (`schemaVersion: 0`) → KONTROLLÁLT hiba (`ArgumentError`), nem best-effort olvasás; **pontosan rajta** (`schemaVersion: 1`) → dekódolható, a mezők azonosak; a küszöb **fölött** (`schemaVersion: 2`) → KONTROLLÁLT hiba, nem csendes elfogadás. Mind a három cella a valódi `LearningActivityEvent.fromJson` belépőt hívja egy fixture-ből származó, egyetlen mezőben módosított map-en (L443).

### 6.1 Mérce-mátrix — melyik hibás implementációt melyik cella fogja pirosra

| Hibás implementáció | Melyik cella vált PIROSRA |
|---|---|
| A teszt szigorúan tiltja az ismeretlen mezőt (nincs additív bővíthetőség) | A2 |
| A dekódoló hiányzó `schemaVersion`-re 1-et feltételez | A3 |
| A katalógus egy nem létező `lib/core/events/…` fájlra hivatkozik producerként | A5 |
| A katalógus létező, de az adott eseményt NEM termelő fájlra hivatkozik producerként | A5 (konstruktor-jelenlét ág) |
| Egy fixture kézzel írt mezőnevet használ a MÉRT helyett (`occurred_at` vs `occurredAt`) | A1 |
| Egy fixture nem kanonikus időbélyeget vagy egész `score`-t használ | A7 |
| A `tutor` sor kitalált producer-útvonalat kap, vagy kimarad a katalógusból | A8, illetve A6 |
| A dekódoló a jövőbeli (`> V`) séma-verziót csendben elfogadja | a küszöb-hármas „fölött" cellája |
| A dekódoló a `< V` verziót best-effort olvassa | a küszöb-hármas „alatta" cellája |

**Valódi-sértés próba (KÖTELEZŐ, a §10-ben dokumentálva):** vedd ki az egyik fixture-ből a `schemaVersion` mezőt, futtasd a §7 gate-et → az **A3** cellának PIROSNAK kell lennie → állítsd vissza, és a gate legyen újra zöld. A §10-be a MÉRT kimenet kerül (a bukó cella neve és a hibaüzenet), nem a próba leírása.

## 7. Kötelező ellenőrzések

```bash
tools/round-gate.sh test/core/events/event_schema_compatibility_test.dart
```

## 8. Implementációs sorrend

1. A MÉRÉS: a §0.0/(a) producer-tábla és a §2 fogyasztó-listája ELLENŐRZÉSE a fán (a sorszámok elmozdulhattak — a fájl és a konstruktor-hívás a mérce).
2. A hat fixture a MÉRT mezőnevekkel, kanonikus alakban (§5.5).
3. `event_schema_compatibility_test.dart` (RED-ből indulva).
4. `docs/contracts/event-catalog.md`.
5. A valódi-sértés próba a §10-be, MÉRT kimenettel.

## 9. Kockázatok

- **Párhuzamos envelope bevezetése.** A legdrágább hiba: egy új `lib/core/events/` típus a meglévő ADR 0329 szerződés mellé — kettős igazság (tilos zóna).
- **A katalógus terv-alapú kitöltése.** A SDD listája nem egyezik a fa MÉRT állapotával (A5).
- **A fixture-ek elavulása.** Ha egy altípus mezőt kap, a fixture néma marad — ezért méri az A1 a MEZŐAZONOS round-tripet és az A7 a kanonikus alakot.
- **Kitalált producer a termelő nélküli típushoz.** A `tutor` sor a legvalószínűbb hely, ahol egy „logikusnak tűnő" út bekerül a katalógusba (A8).

## 10. Implementation handoff — az implementer tölti ki

**Státusz: KÉSZ.** A §4 engedélyezett fájllistán kívül semmi nem módosult; `lib/**` érintetlen.

### Leszállított artefaktumok

- `docs/contracts/event-catalog.md` — a hat típus katalógusa (producer/consumer fájl:sor,
  idempotencia-kulcs = `eventId` mind a hatnál, owner Chapter, kompatibilitási szabály),
  a `tutor` sor explicit „NO PRODUCER (mért)" jelöléssel és indoklással
  (`gamification_tutor_adapter.dart:164–170` hivatkozással).
- `test/fixtures/events/*.json` (6 fájl) — a MÉRT `toJson()` mezőnevekkel és alakkal
  (UTC `occurredAt` ezredmásodperccel+`Z`, `durationMicroseconds` egész, `score` tizedes tört).
- `test/core/events/event_schema_compatibility_test.dart` — 22 teszt, A1–A8 + a
  kétirányú séma-verzió küszöb-hármas; a katalógus-cellák (A5/A6/A8) a fájlt
  ténylegesen beolvassák és a `docs/contracts/event-catalog.md`-t egy kis
  markdown-táblázat-parszolóval ellenőrzik a MÉRT fán.

### §0.0/(a)–(f) revízió — újra-ellenőrizve az implementáció során

A pre-flight producer/consumer táblája (§0.0/(a), §2) a fán VÁLTOZATLANUL igaz maradt:
8 konstruktor-hívás 7 fájlban, `TutorActivityEvent`-nek nincs producere. A gate
A5/A8 cellái ezt gépileg is megerősítették (zöld).

### Két hiba a katalógus/teszt első verziójában — RED-ből GREEN-be javítva

1. **A katalógus-doksi saját envelope-mező-táblájában** (a `type` mező sora) egy
   escape-elt `\|` karaktersorozat volt a leíró szövegben. A markdown-renderelőnek ez
   helyes, de a teszt saját, egyszerű `split('|')`-alapú táblázat-parszolója nem ismeri
   a backslash-escape-et — a sor extra cellákra esett szét, és egy hamis „type" nevű
   katalógus-sorként jelent meg, ami az A5/A6 celláit hamisan pirosra vitte
   (`Actual: Set:['type', 'practice', ...]`). Javítás: a leíró szöveg pipe-mentesre írva
   (`practice` / `song` / … helyett `\|`-lánc).
2. **Az A8 „nincs producer" ellenőrzés hamis pozitívot adott**: az
   `achievement_evaluator.dart:638` Dart 3 mintaillesztő `switch`-ága
   (`TutorActivityEvent() => AchievementEventKind.tutor,`) szintaktikailag tartalmazza a
   `TutorActivityEvent(` alsztringet, de ez nem konstruktor-hívás, hanem üres objektum-minta.
   A naiv `.contains('TutorActivityEvent(')` ezt termelőként azonosította. Javítás: az A5/A8
   producer-detektálás `_containsConstructorCall` segédfüggvényre váltott, amely a nyitó zárójel
   utáni első nem-whitespace karaktert vizsgálja — ha az rögtön `)`, az mintaillesztés, nem hívás.

### Valódi-sértés próba (§6, MÉRT kimenet)

`test/fixtures/events/practice_session_completed_v1.json`-ból ideiglenesen eltávolítva a
`"schemaVersion": 1,` sor, majd `tools/round-gate.sh test/core/events/event_schema_compatibility_test.dart`
futtatva. A gate a `test` lépésen PIROSRA váltott (kilépési kód 1), 3 bukott teszttel:

```
Invalid argument (schemaVersion): must be an int: null
  package:strumsight/features/gamification/domain/activity/learning_activity_event.dart 542:5   _requireInt
  package:strumsight/features/gamification/domain/activity/learning_activity_event.dart 512:22  new _DecodedEvent.fromJson
  package:strumsight/features/gamification/domain/activity/learning_activity_event.dart 46:35   LearningActivityEvent.fromJson

Failing tests:
  … practice fixture is canonical and round-trips
  … practice fixture with an unknown extra field still decodes and keeps every original field unchanged
  … Schema-version threshold … schemaVersion at V=1 decodes with every field unchanged
```

Megjegyzés a §6 szövegéhez képest: a brief az „A3 cella" pirosra váltását írta elő. A
ténylegesen mért hatás a **round-trip/kanonikus (A1/A7) cellákon és a küszöb-hármas „rajta"
ccustomáján** jelentkezett, mert ezek olvassák be közvetlenül a sérült fixture-fájlt —
maga a szintetikus A3 teszt egy memóriabeli másolaton dolgozik, ezért mindig lefut és
zölden bizonyítja ugyanazt a `_requireInt`-ágat, függetlenül a fixture-fájl állapotától.
A mérés lényegét ez nem gyengíti: a gate egy valódi séma-sértést ténylegesen és azonnal
pirosra vált, ugyanazon a kódágon, amit az A3 teszt is fed — ez a próba célja (L443/L477).
A fixture ezután visszaállítva (`git diff --stat` üres), a gate újrafuttatva: mind a 6
lépés zöld (lásd alább).

### Gate-eredmény (végleges, MÉRT)

```
tools/round-gate.sh test/core/events/event_schema_compatibility_test.dart
  [1] format       zöld
  [2] analyze      zöld
  [3] test         zöld (22/22)
  [4] architecture zöld
  [5] secrets      zöld
  [6] l10n         zöld
```

## 11. Review — a Claude tölti ki

**VERDIKT: APPROVED** (2026-08-28, reviewelt HEAD `eedf4ac6`) — teljes jelentés:
[`docs/reviews/e12-r09-review.md`](../reviews/e12-r09-review.md).

- Scope-audit a §4 lista ellen: `OK` (9 útvonal, `lib/**` érintetlen).
- Célzott teszt IZOLÁLT `/tmp` klónban: **22/22 zöld**.
- Három valódi-sértés próba, mind a várt cellát PIROSRA váltotta: P1 hamis
  producer → A5, P2 valódi `TutorActivityEvent(...)` a fán → A8, P3 nem
  kanonikus `occurredAt` → A7.
- BLOCKER 0 · MAJOR 0 · MINOR 0 · NOTE 3 (F1: a §6 próba-szövege az A3 cellát
  jelölte meg, a mért hatás az A1/A7 + küszöb-„rajta" cellákon jelentkezett —
  az implementer ezt kimondta; F2: a katalógus-parszoló üres-cella
  robusztussága; F3: elgépelés a §10-ben).
