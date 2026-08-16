# E07-R15 — WeeklyScheduler és terhelésrotáció

- **Státusz:** PLANNING (pre-flight revízió: 2026-08-16, `main @ 0a1f6709`)
- **Típus:** Epic 7 (AI Practice Generator), SDD Ch8 Kör 15
- **Kör-azonosító:** `E07-R15`
- **Branch:** `<motor>/e07-r15-weekly-scheduler`
- **Előfeltétel:** `E07-R14` merge-elve (időfelosztás)
- **Brief szerzője:** Claude (Opus 5)
- **Előre kiosztott ADR:** [0299](../adr/0299-weekly-scheduler-contract.md)
  — a heti ütemező explicit, domain-pure input/output szerződése.

> ⚠ **Pre-flight (indítás előtt KÖTELEZŐ):** olvasd újra az R03
> `weekly_availability.dart` és az R14 `time_budget.dart` tényleges alakját.
> Eltérésnél §0.0 revízió, Státusz → PLANNING.

```ai-router
schema_version = 1
risk = "high"
allowed_paths = [
  "lib/features/practice_generator/domain/model/schedule_decision.dart",
  "lib/features/practice_generator/domain/policy/scheduling_policy.dart",
  "lib/features/practice_generator/domain/service/weekly_scheduler.dart",
  "lib/features/practice_generator/public.dart",
  "test/features/practice_generator/scheduling/weekly_scheduler_test.dart",
  "test/features/practice_generator/scheduling/scheduling_policy_test.dart",
  "test/fixtures/practice_generator/scheduling",
  "docs/rounds/e07-r15-weekly-scheduler.md",
  "docs/adr/0299-weekly-scheduler-contract.md",
]
gate_tests = [
  "test/features/practice_generator/scheduling/weekly_scheduler_test.dart",
  "test/features/practice_generator/scheduling/scheduling_policy_test.dart",
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

## 0.0 H3 self-heal scope-revízió (2026-08-16)

**Módosítás (ADR 0112 önjavító kör, 2026-08-16).** Ez a revízió kizárólag az
`allowed_paths` hiányát javítja; a scheduler szerződése, acceptance criteria és
a mérce változatlanok.

**Mért gyökérok.** A két névre szóló scheduling-teszt mind ugyanazt a
nem-triviális, paraméterezhető `WeeklyAvailability` / `TimeBudget` /
`ScheduleCandidate` összeállítást használja. Az implementer ezért a repo
meglévő `test/fixtures/<feature>/<terület>/<név>_fixtures.dart` konvenciója
szerint létrehozta a
`test/fixtures/practice_generator/scheduling/scheduling_fixtures.dart`
megosztott builder-fájlt, de az eredeti `allowed_paths` egyetlen fixture-helyet
sem adott. A scope-audit ezért helyesen megállította a kört:

```bash
python3 tools/scope-audit.py --repo /home/ubuntu/ss-minimax-e07-r15 \
  --brief docs/rounds/e07-r15-weekly-scheduler.md \
  --base 5e0c08a5fda48a323cebdf22d9814824c89016dc
# exit 1 — path outside allowed scope:
# test/fixtures/practice_generator/scheduling/scheduling_fixtures.dart
```

**Szűk feloldás.** Az allowlist a bare
`test/fixtures/practice_generator/scheduling` könyvtárral bővül. Ez nem az
egész `practice_generator` fixture-fát engedi meg: csak a két R15 teszt által
közösen használt scheduling-builder helyet. A self-heal regressziós tesztje
ugyanazzal az `audit_legacy_scope()` funkcióval bizonyítja, hogy a mért út most
in-scope, egy közvetlen, `scheduling/`-en kívüli szomszéd út pedig továbbra is
scope-sértés.
## 0.0 Pre-flight revízió (2026-08-16)

- **Mérés:** `WeeklyAvailability` a helyi `LocalDate`-hez kötött és egy
  unavailable naphoz `maximumMinutes == 0`-t kényszerít
  (`domain/model/weekly_availability.dart`). A napi időkeret tényleges
  megszerzési lánca `DailyAvailability` →
  `TimeBudgetAllocator.allocate(availability: …)`; az allocator unavailable
  napra `ArgumentError`-ral fail-closed módon leáll
  (`domain/service/time_budget_allocator.dart`). Nincs még scheduler-input,
  -döntés vagy policy típus, és a `PracticeBlock` már prescriptiont igényel,
  miközben az SDD pipeline-ban a scheduling a prescription construction előtt
  van.
- **Feloldás:** az ADR 0299 a scheduler saját `ScheduleCandidate`,
  `WeeklyScheduleRequest` és `ScheduleDecision` domain-contractját rögzíti.
  A request az R14-ben már elosztott `TimeBudget`-et és az R03 availabilityt
  kapja, ezért az ütemező nem szerez erőforrást és nem számol újra napi
  budgetet. A `today` és az opcionális song céldátum explicit input; nincs
  óraolvasás. A pihenőnap a brief szigorúbb szabálya szerint üres, még könnyű
  ismétlés sem kerül rá.
- **Scope:** a foglalt ADR 0299 és ez a brief explicit engedélyezett artefaktum;
  a korábbi `docs/adr/**` tiltás erre az egy, még nem merge-elt ADR-re nem
  vonatkozik. Más ADR, SDD, tool vagy production útvonal továbbra is tilos.
- **Küszöbmérés:** `python3 -c 'limit=2; print({"below": 1, "at": limit,
  "above": limit + 1})'` → `1 / 2 / 3`; a high-load sorozat maximuma 2,
  ezért a 2 még elfogadott, a 3. nap átrendezendő.

## 1. Cél

A kiválasztott receptek napokra rendezése fókusz-, pihenő- és periodizációs
szabályokkal (SDD Ch8 Kör 15).

## 2. Jelenlegi állapot — mért tények

- Az R03 elérhetősége **naponta változó**, helyi dátumhoz kötött.
- Az R14 napi kerete pontos, a hard maximum inkluzív.
- A determinizmus kötelező: ugyanaz a bemenet ugyanazt a hetet adja.

## 3. Scope

**Benne van:** napi elsődleges/másodlagos fókusz-limit · nagy terhelésű napok
egymásutániságának védelme · pihenőnap-kezelés · dal-cél fázisok céldátumhoz ·
esedékes ismétlések **korlátos** arányban · a naponta változó elérhetőség
tiszteletben tartása.

**NINCS benne (tilos):** progresszió/regresszió (Kör 16) · ismétlés-politika
(Kör 17) · orchestrator (Kör 18) · kötelező blokk elérhetetlen napra ·
Flutter, `DateTime.now()`, `Random` · más `lib/features/**`, `docs/adr/**`.

## 4. Engedélyezett fájlok

| Útvonal | Indok |
|---|---|
| `domain/model/schedule_decision.dart` | **ÚJ** — döntés + indoklás |
| `domain/policy/scheduling_policy.dart` | **ÚJ** — limitek, rotáció, arányok |
| `domain/service/weekly_scheduler.dart` | **ÚJ** — az ütemező |
| `public.dart` | a barrel bővítése |
| `test/…/scheduling/*_test.dart` (2 db) | a §6 cellái |
| `test/fixtures/practice_generator/scheduling/` | a két scheduling-teszt közös, paraméterezhető builderjei |
| `docs/rounds/e07-r15-…md` | a §10 handoff |

**Tilos zóna:** más `lib/features/**` · `lib/app/**` · `docs/adr/**` ·
`docs/sdd/**` · `tools/**` · `.github/**`.

## 5. Kötött architekturális döntések

### 5.1 Elérhetetlen napra NINCS kötelező blokk

Ha a tanuló egy napra nulla időt adott meg, arra a napra nem kerül kötelező
gyakorlás. Az „opcionális" jelölés sem kerülheti meg ezt.

**NEM elfogadható gyengítés:** „csak 5 perc, belefér". A nulla nulla.

### 5.2 A nagy terhelésű napok NEM követhetik egymást a limiten túl

A periodizáció lényege a regeneráció. A limit a policy explicit paramétere.

### 5.3 A pihenőnap NEM tölthető fel „könnyű" tartalommal

A pihenőnap pihenőnap. Ismétlés vagy „csak egy kis" gyakorlás nem tehető rá —
különben a fogalom kiürül.

### 5.4 Az ismétlések aránya KORLÁTOS

Az esedékes ismétlés nem foglalhatja el a napot; a policy felső arányt szab.
Ez az R17 napi budget-jével együtt hat (SDD Ch8 Kör 17: „a queue nem tölti ki
a teljes napot").

### 5.5 A dal-cél fázisok a CÉLDÁTUMHOZ igazodnak

Céldátum előtt könnyű ismétlés lehetséges (nem új anyag). A fázisok
determinisztikusan következnek a céldátumból és a mai naptól.

### 5.6 Az ütemező REPRODUKÁLHATÓ

Ugyanaz a bemenet ugyanazt a heti beosztást adja; a napok bejárási sorrendje
rögzített.

## 6. Acceptance criteria

| # | Kritérium | Bizonyíték |
|---|---|---|
| A1 | Nulla elérhetőségű napra nincs kötelező blokk | `weekly_scheduler_test.dart` |
| A2 | A nagy terhelésű napok limitje nem sérül | ugyanott |
| A3 | Pihenőnapra nem kerül tartalom | ugyanott |
| A4 | Az ismétlés-arány a policy korlátja alatt marad | `scheduling_policy_test.dart` |
| A5 | Céldátum előtt könnyű ismétlés kerül, nem új anyag | `weekly_scheduler_test.dart` |
| A6 | Ugyanaz a bemenet → ugyanaz a heti beosztás | ugyanott |
| A7 | A napi fókusz-limit (elsődleges/másodlagos) betartva | ugyanott |
| A8 | A helyi dátumhatárok helyesek (hét eleje/vége) | ugyanott |

### 6.1 Mérce-mátrix — melyik hibás implementációt melyik cella fogja pirosra

| Hibás implementáció | Melyik cella vált PIROSRA |
|---|---|
| „5 perc belefér" elérhetetlen napra | **A1** |
| A nagy terhelésű napok egymás után | A2 |
| Pihenőnapra könnyű ismétlés | **A3** |
| Az ismétlés kitölti a napot | A4 |
| Céldátum előtt új anyag | A5 |
| A napok bejárása `Map` sorrendben | A6 |

**A napi terhelés három kötelező cellája** (a határ: az egymás utáni nagy terhelésű napok limitje):

| Cella | Bemenet | Elvárt |
|---|---|---|
| alatta | limit 2, egymás után 1 nagy terhelésű nap | elfogadva |
| a határon | limit 2, egymás után **2** | **elfogadva** (inkluzív) |
| fölötte | limit 2, egymás után 3 | **átrendezve** — a harmadik könnyebb lesz |

**Valódi-sértés próba (KÖTELEZŐ, §10-ben dokumentálva):** tegyél kötelező
blokkot nulla elérhetőségű napra → az **A1** cellának PIROSNAK kell lennie →
állítsd vissza.

## 7. Kötelező ellenőrzések

```bash
tools/round-gate.sh test/features/practice_generator/scheduling/weekly_scheduler_test.dart test/features/practice_generator/scheduling/scheduling_policy_test.dart
```

Külön processzek, csonkítatlan kimenet. **Tilos** `| tail`, `| head`,
`&&`-lánc vagy bármilyen szűrés (L09); a `flutter analyze` és `flutter test`
kézi láncolása OOM-ot ad (L05). A kötelező gate-et **TILOS háttérbe küldeni**
(`run_in_background`) — az egy-fordulós harness a forduló végén megöli (L254).

## 8. Implementációs sorrend

1. `scheduling_policy.dart` — limitek, rotáció, arányok, fázisok.
2. `schedule_decision.dart` — a döntés + indoklás.
3. `weekly_scheduler.dart` — determinisztikus bejárás.
4. Tesztek a §6.1 három terhelés-cellájával.
5. A valódi-sértés próba, §10-be dokumentálva.
6. `tools/round-gate.sh` a §7 szerint.

## 9. Kockázatok

- **A „belefér még" logika.** Elérhetetlen napra tett blokk a legkárosabb: a
  tanuló azonnal elbukik a saját tervén (A1).
- **A pihenőnap felhígítása.** Ismétléssel „nem terhelés" — de a
  regenerációt elveszi (A3).
- **A `Map`-sorrendű bejárás.** Determinisztikusnak látszik, futásonként más
  lehet (A6).

## 10. Implementation handoff — az implementer tölti ki

## 11. Review — a Claude tölti ki
