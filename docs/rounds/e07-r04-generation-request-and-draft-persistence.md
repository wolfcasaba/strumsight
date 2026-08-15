# E07-R04 — PracticeGenerationRequest és draft persistence

- **Státusz:** PREPARED (előre megírva 2026-08-15, kód olvasva: `main @ 46338f48`)
- **Típus:** Epic 7 (AI Practice Generator), SDD Ch8 Kör 4
- **Kör-azonosító:** `E07-R04`
- **Branch:** `<motor>/e07-r04-generation-request-and-draft-persistence`
- **Előfeltétel:** `E07-R03` merge-elve (goal, availability, constraints)
- **Brief szerzője:** Claude (Opus 5)
- **Előre kiosztott ADR:** [`0259`](../adr/0259-generation-request-versioning-and-draft-isolation.md)
  — **MÁR MEGÍRVA, a `docs/adr/` a TILOS zónában van.**

> ⚠ **Pre-flight (indítás előtt KÖTELEZŐ):** olvasd újra az R02/R03 TÉNYLEGES
> kimenetét (`planner_ids.dart`, `plan_enums.dart`, `practice_goal.dart`,
> `weekly_availability.dart`, `learner_constraints.dart`) — mely típusok és
> mezők születtek meg. Mérd meg a projekt **meglévő lokális tároló-mintáját**
> (`grep -rln "SharedPreferences\|getApplicationDocumentsDirectory" lib/features/`),
> és kövesd azt; ne vezess be újat. Eltérésnél §0.0 revízió, Státusz → PLANNING.

```ai-router
schema_version = 1
risk = "normal"
allowed_paths = [
  "lib/features/practice_generator/domain/model/practice_generation_request.dart",
  "lib/features/practice_generator/data/local/generation_request_serializer.dart",
  "lib/features/practice_generator/data/local/generation_draft_repository.dart",
  "lib/features/practice_generator/public.dart",
  "test/features/practice_generator/data/generation_request_serializer_test.dart",
  "test/features/practice_generator/data/generation_draft_repository_test.dart",
  "docs/rounds/e07-r04-generation-request-and-draft-persistence.md",
]
gate_tests = [
  "test/features/practice_generator/data/generation_request_serializer_test.dart",
  "test/features/practice_generator/data/generation_draft_repository_test.dart",
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

Lezáró jelzés nélkül a kör bukott. Listán kívüli fájl → `stopped`.

## 1. Cél

A generálás **teljes inputjának** verziózott, megszakítás után folytatható
dokumentummá alakítása (SDD Ch8 Kör 4).

## 2. Jelenlegi állapot — mért tények

### 2.1 Amit az R02/R03 hagyott

Typed ID-k és stabil kódú enumok (ADR 0257), `PracticeGoal`,
`WeeklyAvailability`, `LearnerConstraints`, `RequestValidator` (ADR 0258).
**A pre-flight kötelezően ellenőrzi a tényleges neveket és mezőket.**

### 2.2 A determinisztikusság az ADR 0255 §1 szerint KÖTELEZŐ

„Ugyanaz a bemenet ugyanazt a tervet adja." Ehhez a request **hash-elhető**
kell legyen, és a seed a requestből származzon — nem `Random`-ból.

### 2.3 A `Clock` és az ID-generátor injektált (ADR 0257 §5)

A domainben nincs `DateTime.now()`. A request létrehozási ideje kívülről jön.

## 3. Scope

**Benne van:**

1. `PracticeGenerationRequest` — schema version, generation mode,
   **determinisztikus seed**, a goal/availability/constraints hármas.
2. Szerializáció + **schema migráció**.
3. `GenerationDraftRepository` — a setup wizard draftjának lokális mentése,
   sérülés-tűrő olvasással.
4. **Draft ↔ aktív terv izoláció.**

**NINCS benne (tilos):**

- Tervező-algoritmus, evidence, katalógus, UI, provider.
- `Random`, `DateTime.now()`, Flutter import a domainben.
- Más `lib/features/**`, `lib/app/**`, `docs/adr/**`, `tools/**`, `.github/**`.

## 4. Engedélyezett fájlok

| Útvonal | Indok |
|---|---|
| `domain/model/practice_generation_request.dart` | **ÚJ** — a request + seed + schema version |
| `data/local/generation_request_serializer.dart` | **ÚJ** — round-trip + migráció |
| `data/local/generation_draft_repository.dart` | **ÚJ** — draft mentés/olvasás/törlés |
| `public.dart` | a barrel bővítése |
| `test/…/data/*_test.dart` (2 db) | a §6 cellái |
| `docs/rounds/e07-r04-…md` | a §10 handoff |

**Tilos zóna:** `lib/app/**` · minden más `lib/features/**` · `docs/adr/**` ·
`docs/sdd/**` · `tools/**` · `.github/**`.

## 5. Kötött architekturális döntések (ADR 0259)

### 5.1 A seed a requestből SZÁMÍTOTT, nem véletlen

A determinisztikus seed a request tartalmának **stabil hash-e**. Ugyanaz a
request ugyanazt a seedet adja, két különböző eszközön és két hét múlva is.

**NEM elfogadható gyengítés:** `Random().nextInt(...)` seed, vagy a
létrehozási időbélyeg bekeverése. Az elrontja az ADR 0255 §1
reprodukálhatóságát.

### 5.2 A hash a JELENTÉSEN alapul, nem a mezők sorrendjén

A hash bemenete kanonikus: rendezett kulcsok, normalizált értékek. A
szerializáció mezősorrendjének megváltozása **nem** változtathatja meg a
hash-t.

### 5.3 A draft SOHA nem írja felül az aktív tervet

Külön tároló-kulcs/fájl. A wizard félkész állapota nem szivároghat a
végrehajtott tervbe — ez a SDD Ch8 Kör 4 kifejezett elfogadási feltétele.

**NEM elfogadható gyengítés:** közös kulcs „státusz" mezővel megkülönböztetve.
Egy hibás írás így az aktív tervet vinné el.

### 5.4 A sérült draft KONTROLLÁLT hiba, nem összeomlás

Olvashatatlan vagy séma-sértő draft esetén a repository **hibát ad vissza**
(`AppResult` failure), és a draft eldobható — az app nem omlik össze.

### 5.5 Ismeretlen jövőbeli schema version: kontrollált elutasítás

Ha a mentett draft újabb sémájú, mint amit a kód ismer, az **hiba**, nem
„best effort" olvasás. Ugyanaz az elv, mint az ADR 0257 §4 ismeretlen
enum-kódjánál.

## 6. Acceptance criteria

| # | Kritérium | Bizonyíték |
|---|---|---|
| A1 | Request JSON round-trip veszteségmentes | `generation_request_serializer_test.dart` |
| A2 | Ugyanaz a request → **ugyanaz a hash/seed** | `..._serializer_test.dart` |
| A3 | A mezősorrend megváltozása NEM változtatja a hash-t | `..._serializer_test.dart` — kanonikus hash cella |
| A4 | Régi schema version migrálódik | `..._serializer_test.dart` |
| A5 | **Jövőbeli** schema version kontrollált hiba | `..._serializer_test.dart` |
| A6 | Sérült draft → hiba, nem összeomlás | `generation_draft_repository_test.dart` |
| A7 | Draft mentése NEM érinti az aktív tervet | `..._repository_test.dart` — külön kulcs, izolációs cella |
| A8 | Draft törölhető, és a törlés idempotens | `..._repository_test.dart` |
| A9 | Nincs `Random`, `DateTime.now()`, Flutter import a domainben | `grep` a diffben |

### 6.1 Mérce-mátrix — melyik hibás implementációt melyik cella fogja pirosra

| Hibás implementáció | Melyik cella vált PIROSRA |
|---|---|
| `Random` seed | **A2** |
| Időbélyeg a hash bemenetében | A2 |
| A hash a szerializált string sorrendjéből | **A3** |
| A migráció csak felfelé nyitott (jövőbeli sémát is olvas) | **A5** |
| Sérült draftra kivétel propagál | A6 |
| Közös kulcs draftnak és aktív tervnek | **A7** |
| A törlés hiányzó draftra hibát ad | A8 |

**A schema version három kötelező cellája** (a határ: az aktuális verzió):

| Cella | Bemenet | Elvárt |
|---|---|---|
| régebbi | `schemaVersion = aktuális - 1` | **migrálódik**, olvasható |
| a határon | `schemaVersion = aktuális` | olvasható, migráció nélkül |
| újabb | `schemaVersion = aktuális + 1` | **kontrollált hiba**, nem best-effort |

**Valódi-sértés próba (KÖTELEZŐ, §10-ben dokumentálva):** keverd az aktuális
időt a seed-hash bemenetébe → az **A2** cellának PIROSNAK kell lennie →
állítsd vissza.

## 7. Kötelező ellenőrzések

```bash
tools/round-gate.sh test/features/practice_generator/data/generation_request_serializer_test.dart test/features/practice_generator/data/generation_draft_repository_test.dart
```

Külön processzek, csonkítatlan kimenet. **Tilos** `| tail`, `| head`,
`&&`-lánc vagy bármilyen szűrés (L09); a `flutter analyze` és `flutter test`
kézi láncolása OOM-ot ad (L05). A kötelező gate-et **TILOS háttérbe küldeni**
(`run_in_background`) — az egy-fordulós harness a forduló végén megöli (L254).

## 8. Implementációs sorrend

1. `practice_generation_request.dart` — mezők, schema version, kanonikus hash.
2. `generation_request_serializer.dart` — round-trip + migráció + a jövőbeli
   verzió elutasítása.
3. `generation_draft_repository.dart` — mentés/olvasás/törlés, sérülés-tűrően,
   **külön** tárolóhelyen.
4. Tesztek a §6.1 három schema-cellájával.
5. A valódi-sértés próba, §10-be dokumentálva.
6. `tools/round-gate.sh` a §7 szerint.

## 9. Kockázatok

- **A seed „kényelmes" forrása.** `Random` vagy időbélyeg egyszerűbb, és
  pont az ADR 0255 determinisztikusságát rontja el (A2).
- **A hash a szerializált stringből.** Működik, amíg valaki át nem rendez egy
  mezőt — utána minden korábbi terv „megváltozott" (A3).
- **A közös tárolóhely.** Egy kulcs, egy státusz-mező: kevesebb kód, és egy
  hibás írás elviszi az aktív tervet (A7).
- **A „best effort" olvasás.** Jövőbeli sémát megpróbálni értelmezni
  segítőkésznek hat; csendes adatromlás (A5).

## 10. Implementation handoff — az implementer tölti ki

## 11. Review — a Claude tölti ki
