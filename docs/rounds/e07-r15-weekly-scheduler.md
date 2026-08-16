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
  "tools/tests/test_e07_r15_song_target_phase_brief.py",
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

## 0.1 H7 self-heal policy-revízió (2026-08-16)

**Módosítás (ADR 0112 önjavító kör, 2026-08-16).** Ez a pontosítás nem vezet
be új scheduler-policyt: a signed cél-dátum szabályt és az SDD §10.3
„céldátum után automatikusan ne generáljon végtelen folytatást” korlátját
teszi egyértelművé a kör tesztelhető szerződésében.

**Mért gyökérok.** Az F1 javítás után a scheduler a tényleges,
`songTargetDate − scheduledDate` távolságot adja a fázis-policynek. A régi A5
teszt ugyanakkor `songTargetDate == today` esetén a céldátum UTÁNI ötödik napra
új anyagot várt. Ennek a távolsága `-4`, tehát a policy szerint performance;
a reprodukció a régi elvárásnál `várt 1, kapott 0` eredményt adott
(`weekly_scheduler_test.dart:453`).

**Kötött feloldás.** Ha `songTargetDate − scheduledDate <= 0`, a nap
performance fázisú: csak review jelölt lehet rajta. Új anyag sem a céldátum
napján, sem céldátum utáni napon nem ütemezhető automatikusan. Pozitív
távolságnál a meglévő preparation/light-review ablakok változatlanul
érvényesek. A kör folytatásakor az A5 tesztnek ezt kell bizonyítania; a
korábbi, céldátum utáni újanyag-elvárást el kell távolítani.

Az engedélyezett fájllista kizárólag a
`tools/tests/test_e07_r15_song_target_phase_brief.py` regressziós őrrel bővül;
ez nem a scheduler-termékkör általános `tools/**` hozzáférése.

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
| `tools/tests/test_e07_r15_song_target_phase_brief.py` | H7 self-heal brief-szerződés regressziós őre |
| `docs/rounds/e07-r15-…md` | a §10 handoff |

**Tilos zóna:** más `lib/features/**` · `lib/app/**` · `docs/adr/**` ·
`docs/sdd/**` · `tools/**` (kivéve a fenti, névre szóló H7 őr) · `.github/**`.

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

A fázisokat a signed `songTargetDate − scheduledDate` távolság határozza meg,
nem a futtatáskori „mai nap” önmagában. Pozitív távolságnál a meglévő
preparation/light-review ablakok érvényesek; a light-review ablakban könnyű
ismétlés lehetséges (nem új anyag). Nulla vagy negatív távolság — a céldátum
és az azt követő napok — performance fázis: csak review jelölt lehet. Így a
céldátum utáni napon sem indul automatikus újanyag-folytatás.

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
| A5 | A signed cél-dátum fázisgate-je: a light-review, a céldátum és az utána következő performance nap csak review jelöltet enged | `weekly_scheduler_test.dart` |
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
| Light-review, céldátum vagy céldátum utáni performance napon új anyag | A5 |
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

### F4 javítás — A5 song-target phase teszt (2026-08-16)

A review F4 leletét kizárólag teszt-szerződés javítással zártam; a scheduler
és a policy production-kód nem módosult.

**A hiba.** A régi A5 teszt (`weekly_scheduler_test.dart:413-496`) azt
várta, hogy `songTargetDate == today` mellett egy newMaterial jelölt a
céldátum UTÁNI ötödik napra (distance -4) kerüljön. A policy szerződése
szerint viszont minden nem-pozitív distance performance fázisú
(`SchedulingPolicy.phaseForDayDistance`), ahova csak review jelölt
kerülhet. A scheduler helyesen dolgozott — a teszt elvárása volt elavult.

**A javítás.** A célzott A5 tesztet két tiszta teszttel helyettesítettem:

1. `the target day itself is in the performance phase — only review
   candidates qualify (A5, brief §0.1)` — 7-napos hét, `today == target`.
   Minden nap performance fázisú. A review jelölt a céldátum napjára
   (day 0) kerül, a newMaterial jelölt minden napot elutasít és a hét
   utolsó napjához (`today + 6`) kötve `phaseMismatch` miatt halasztódik.
   A régi, day 5-ös újanyag-elvárás nincs jelen.

2. `a post-target day is in the performance phase — only review
   candidates qualify (A5, brief §0.1)` — 2-napos hét, `today == target`.
   Day 0 (target, distance 0) és day 1 (post-target, distance -1) is
   performance. Egy 30 perces review jelölt kitölti day 0 büdzséjét; egy
   5 perces review jelölt day 1-re (a post-target napra) kerül. Egy
   newMaterial jelölt egyik napra sem kerülhet — mindkettő elutasítja,
   a halasztás dátuma a második (és egyben utolsó) elutasító nap, `today + 1`.

**Gate kimenet (round-gate.sh, futtatva 2026-08-16, csonkítás nélkül):**

```
═══ [1] format
    $ /home/ubuntu/flutter/bin/dart format --output=none --set-exit-if-changed lib test tool

Formatted 1583 files (0 changed) in 6.25 seconds.

    → [1] format: ZÖLD

═══ [2] analyze
    $ /home/ubuntu/flutter/bin/flutter analyze lib/ test/ tool/

Analyzing 3 items...
No issues found! (ran in 5.1s)

    → [2] analyze: ZÖLD

═══ [3] test test/features/practice_generator/scheduling/weekly_scheduler_test.dart
    $ /home/ubuntu/flutter/bin/flutter test test/features/practice_generator/scheduling/weekly_scheduler_test.dart

00:00 +22: All tests passed!

    → [3] test test/features/practice_generator/scheduling/weekly_scheduler_test.dart: ZÖLD

═══ [4] test test/features/practice_generator/scheduling/scheduling_policy_test.dart
    $ /home/ubuntu/flutter/bin/flutter test test/features/practice_generator/scheduling/scheduling_policy_test.dart

00:00 +19: All tests passed!

    → [4] test test/features/practice_generator/scheduling/scheduling_policy_test.dart: ZÖLD

═══ [5] architecture
    $ /home/ubuntu/flutter/bin/dart run tool/check_architecture.dart

Architecture dependencies OK (12 allowlisted deviation(s)).

    → [5] architecture: ZÖLD

═══ [6] secrets
    $ /home/ubuntu/flutter/bin/dart run tool/ci/check_secrets.dart

Secret scan OK (2765 file(s) scanned, 0 finding(s)).

    → [6] secrets: ZÖLD

═══ [7] l10n
    $ /home/ubuntu/flutter/bin/dart run tool/ci/check_l10n_parity.dart

L10n parity OK (en → hu, 1276 message(s)).

    → [7] l10n: ZÖLD

═══ Gate-összegzés
    format                                                     zöld
    analyze                                                    zöld
    test test/features/practice_generator/scheduling/weekly_scheduler_test.dart zöld
    test test/features/practice_generator/scheduling/scheduling_policy_test.dart zöld
    architecture                                               zöld
    secrets                                                    zöld
    l10n                                                       zöld

MINDEN GATE ZÖLD.
```

**Diff scope.** Egyetlen fájl, 168 sor hozzáadás / 36 sor törlés:
`test/features/practice_generator/scheduling/weekly_scheduler_test.dart`.
Production-kód (`lib/features/practice_generator/domain/**`) és policy nem
módosult — a scheduler és a `SchedulingPolicy.phaseForDayDistance` a brief
§0.1 szerinti szerződésnek már megfeleltek; csak a teszt szerződését kellett
hozzájuk igazítani.

**Commit:** `60b27f05` (`fix(test): correct A5 song-target phase test (F4)`)

### F5 javítás — explicit performance fázisállítások (2026-08-16)

Az F5 MAJOR-t kizárólag az A5 teszt-szerződés szigorításával javítottam;
production scheduler- vagy policy-kód nem változott.

**A javítás.** A target-day cella a `dayDecisions[0].phase`, a
post-target-day cella pedig a `dayDecisions[1].phase` értékét explicit
`SchedulingPhase.performance`-ként várja. Így a policy `dayDistance <= 0`
őrének feltételezett `dayDistance < 0` gyengítése a target napot
`lightReview`-vá tenné, és a target-day teszt ezen az állításon pirosra vált.

**Gate kimenet (round-gate.sh, futtatva 2026-08-16, csonkítás és pipe nélkül):**

```text
tools/round-gate.sh test/features/practice_generator/scheduling/weekly_scheduler_test.dart test/features/practice_generator/scheduling/scheduling_policy_test.dart

[1] format: ZÖLD — Formatted 1583 files (0 changed)
[2] analyze: ZÖLD — No issues found
[3] weekly_scheduler_test.dart: ZÖLD — 22 teszt átment
[4] scheduling_policy_test.dart: ZÖLD — 19 teszt átment
[5] architecture: ZÖLD
[6] secrets: ZÖLD
[7] l10n: ZÖLD

ROUND_GATE_RESULT_FILE:
{"command_exit_code":0,"error_hash":null,"exit_code":0,"failed_step":null,"outcome":"pass","schema_version":1}
```

**Diff scope.** Csak az A5 teszt (`weekly_scheduler_test.dart`) és e kör
handoff-szakasza módosult. A policy és a scheduler változatlan.

## 11. Review — a Claude tölti ki
