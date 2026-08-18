# E07-R20 — Plan setup wizard és input UX

- **Státusz:** PREPARED → **pre-flight revideálva** (Claude, 2026-08-18, kód
  olvasva: `main @ e5374943`; eredetileg előre megírva 2026-08-15, kód
  olvasva: `main @ 135ef4af` — lásd §0.0)
- **Típus:** Epic 7 (AI Practice Generator), SDD Ch8 Kör 20
- **Kör-azonosító:** `E07-R20`
- **Branch:** `terra/e07-r20-plan-setup-wizard`
- **Előfeltétel:** `E07-R19` merge-elve (repository) — **teljesül** (PR #303,
  `2ce22f3b`).
- **Brief szerzője:** Claude (Opus 5)
- **Előre kiosztott ADR:** nincs — a pre-flight (§0.0) megmérte, hogy egy új
  ADR nem indokolt: a határokat az ADR 0257 (stabil enum-kódok), 0258
  (hard/soft constraint), 0259 (draft), 0260 §4 (érzékeny szöveg nem
  naplózható) és 0261 §2 (unknown önálló állapot) már lefedi, és a lenti
  §0.0 pontok kizárólag ezek alkalmazását pontosítják, új architekturális
  döntést nem hoznak.

> ⚠ **Pre-flight (indítás előtt KÖTELEZŐ):** mérd meg a projekt **ARB/l10n**
> mintáját (`lib/l10n/app_hu.arb`, `app_en.arb`) és a meglévő wizard-jellegű
> képernyők szerkezetét. **Minden felhasználói szöveg ARB-n át megy.**
> Eltérésnél §0.0 revízió.

## 0.0 Pre-flight revízió (Claude, 2026-08-18, kód olvasva: `main @ e5374943`)

A brief 2026-08-15-i mért állításait a mai kódon újramértem. Egyik pont sem
szűkíti vagy bővíti az `allowed_paths`-t vagy a §3 scope-ot — a §2 mért
állapotot pontosítják, hogy az implementer ne induljon találgatásból.

1. **A lépésenkénti draft-mentés konstrukciósan lehetséges már az első
   lépés után is.** `WeeklyAvailability(const [])` és
   `LearnerConstraints(const [])` érvényesek (nincs minimum-hossz megkötés a
   konstruktorban), `PracticeGenerationRequest.goals` alapértelmezetten
   `const []`. A meglévő, változatlan (NEM allowed_paths-on lévő, csak
   HASZNÁLANDÓ) `GenerationDraftRepository.saveDraft` így egy csak a
   cél-lépést tartalmazó draftot is el tud menteni teljes, érvényes
   `PracticeGenerationRequest`-ként — nincs szükség egy külön,
   presentation-lokális parciális draft-típusra.

2. **`generationMode` és `planHorizonDays` egyik névre szóló lépéshez sincs
   rendelve, és egyik típusnak sincs „unknown" értéke**
   (`plan_enums.dart`: `GenerationMode` 7 konkrét kód, nincs `unknown`;
   `planHorizonDays` egy sima `int`). Ez **nem** a §5.1 tiltott „nem tudom
   → default" mintája, mert egyik mező sem felhasználó-látható kérdés a §3
   öt lépése közül — nincs olyan UI-kérdés, aminek a válaszát felülírnánk.
   Mért, meglévő konvenció (`test/features/practice_generator/data/
   generation_draft_repository_test.dart`): a fixture
   `generationMode: GenerationMode.starter` + `planHorizonDays: 7` párost
   használ. A wizard a draft LÉTREHOZÁSAKOR állítsa be ugyanezt a két
   értéket rögzített scaffolding-értékként (nem lépés, nem felhasználói
   válasz); egy jövőbeli kör dolga, ha ezek is választhatóvá válnak.

3. **A „nem tudom" (A4) minden érintett lépésen a meglévő domain
   nullable/üres-lista szemantikájával fejezhető ki, domain-módosítás
   nélkül:** `PracticeGoal.targetDate` és `PracticeGoal.metricTarget` már
   nullable (a cél-lépés „nem tudom" válasza = `null`, nem egy kitalált
   dátum/metrika); egy meg nem válaszolt nap egyszerűen hiányzik a
   `WeeklyAvailability.days` listából (a lista bármilyen hosszú lehet, nincs
   7-elemű elvárás); egy meg nem adott equipment/tuning/preferencia/avoid
   egyszerűen nincs a `LearnerConstraints.constraints` listában. A wizard
   felelőssége, hogy ne konstruáljon `DailyAvailability`-t vagy
   `LearnerConstraint`-et olyan napra/kategóriára, amit a tanuló nem
   válaszolt meg — a hiány maga az „unknown".

4. **A9 (kényelmetlenségi szöveg naplózás-tilalma) egy ÚJ, kizárólag ehhez a
   wizardhoz tartozó UI-bemenetre vonatkozik, NEM a meglévő
   `SkillEvidence.DiscomfortReport`/`EvidenceAggregator.ingest` útvonalra**
   (az egy másik, korábbi kör — R05/R06 — evidence-pipeline-ja, session
   utáni önjelentésre, nem a generálási kérés setupjára). A „kényelem" lépés
   strukturáltan `LearnerConstraint(category: ConstraintCategory.comfort,
   …)` felé mehet; az ADR 0260 §4 elvét a wizard UI-szinten ismétli meg:
   bármilyen szabad szöveget gyűjt is a lépés, az csak a draftba (helyi
   storage) kerülhet — logger-hívásba (`print`, `debugPrint`, jövőbeli
   analytics-hook) sosem.

5. **A5 (azonnali hard-konfliktus) a meglévő `RequestValidator`
   kör-korlátozott hívásával érhető el, módosítás nélkül.**
   `RequestValidator.validate()` tiszta, szinkron, és részleges bemenettel
   is hívható — a `scheduledMinutes`/`constraintViolations` paraméter üresen
   hagyható, ezeket más, ezen a körön kívül eső rétegek töltik fel később. A
   wizard a SAJÁT, addig ismert `goals`/`availability` állapotával hívja
   lépésenként. A teljes cross-goal equipment-ütközés (katalógus-egyeztetés)
   ezen a körön kívül esik — az A5 mérce-cellája a goal- és
   availability-szintű, a validátorral ténylegesen visszaadható
   ütközésekre és a domain-konstruktorok (`DailyAvailability` stb.) saját
   `ArgumentError`-jaira vonatkozik, nem egy még nem létező catalog-matchre.

6. **ID-generálás: nincs projektszintű `uuid` csomag.** A `pubspec.lock`
   tartalmaz egy `uuid` bejegyzést, de az kizárólag TRANZITÍV függőség (nincs
   a `pubspec.yaml` `dependencies` blokkjában) — `import 'package:uuid/...'`
   nem fordulna, és a `pubspec.yaml` egyébként sincs az `allowed_paths`-on.
   A `GenerationRequestId`/`GoalId` stb. `X.generate(String Function()
   generateId)` mintája (ld. `planner_ids.dart`,
   `practice_generation_request.dart`) bármilyen, a
   `^[A-Za-z0-9._:-]+$` mintának megfelelő karakterláncot elfogad — elég egy
   egyszerű, csomag nélküli generátor (pl. `dart:math` `Random` + időbélyeg).

```ai-router
schema_version = 1
risk = "high"
allowed_paths = [
  "lib/features/practice_generator/presentation/screens/plan_setup_screen.dart",
  "lib/features/practice_generator/presentation/widgets/practice_goal_picker.dart",
  "lib/features/practice_generator/presentation/widgets/availability_editor.dart",
  "lib/features/practice_generator/presentation/controller/plan_setup_controller.dart",
  "lib/l10n/app_en.arb",
  "lib/l10n/app_hu.arb",
  "lib/features/practice_generator/public.dart",
  "test/features/practice_generator/presentation/plan_setup_screen_test.dart",
  "test/features/practice_generator/presentation/availability_editor_test.dart",
  "docs/rounds/e07-r20-plan-setup-wizard.md",
]
gate_tests = [
  "test/features/practice_generator/presentation/plan_setup_screen_test.dart",
  "test/features/practice_generator/presentation/availability_editor_test.dart",
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

A generálási kérés egyszerű, **hozzáférhető** és megszakítás után folytatható
felülete (SDD Ch8 Kör 20).

## 2. Jelenlegi állapot — mért tények

- Az R04 draft-repositoryja lépésenkénti mentést tesz lehetővé (ADR 0259 §3).
- Az R03 `RequestValidator`-a azonnal jelzi a hard konfliktust.
- Az ADR 0260 §4: a **kényelmetlenségre vonatkozó szabad szöveg nem
  naplózható**.
- A `practiceGeneratorEnabled` flag **OFF** — a képernyő a flag mögött él.

## 3. Scope

**Benne van:** cél-, ütemezés-, felszerelés-, preferencia- és kényelem-lépés ·
**„nem tudom"** válaszok támogatása · lépésenkénti draft-mentés · hard
konfliktus azonnali jelzése · reduced-motion és képernyőolvasó támogatás ·
magyar és angol lokalizáció.

**NINCS benne (tilos):** a terv előnézete (Kör 21) · aktiválás · a domain vagy
a validátor módosítása · **bármely flag `true`-ra állítása** · érzékeny szöveg
naplózása · `docs/adr/**`, `tools/**`, `.github/**`.

## 4. Engedélyezett fájlok

| Útvonal | Indok |
|---|---|
| `presentation/screens/plan_setup_screen.dart` | **ÚJ** — a wizard |
| `presentation/widgets/practice_goal_picker.dart` | **ÚJ** |
| `presentation/widgets/availability_editor.dart` | **ÚJ** |
| `presentation/controller/plan_setup_controller.dart` | **ÚJ** — lépés-állapot + draft |
| `lib/l10n/app_en.arb`, `app_hu.arb` | a felhasználói szövegek |
| `public.dart` | a barrel bővítése |
| `test/…/presentation/*_test.dart` (2 db) | a §6 cellái |
| `docs/rounds/e07-r20-…md` | a §10 handoff |

**Tilos zóna:** `lib/app/config/feature_flags.dart` · a generátor **domain**
és **application** rétege · más `lib/features/**` · `docs/adr/**` · `tools/**`.

## 5. Kötött architekturális döntések

### 5.1 A „nem tudom" ELSŐOSZTÁLYÚ válasz

Minden kérdésnél megadható, és **nem** vezet kitalált alapértékhez. Az
`unknown` a domainben is önálló állapot (ADR 0261 §2) — az UI ezt tükrözi.

**NEM elfogadható gyengítés:** a „nem tudom" néma átfordítása egy default
értékre. Az a tanuló nevében hazudna a rendszernek.

### 5.2 A visszalépés NEM veszít adatot

A wizard bármely lépéséről vissza lehet lépni a korábban megadott adatok
elvesztése nélkül.

### 5.3 A hard konfliktus AZONNAL látszik

Nem a végén, összegyűjtve. A tanuló ott javíthat, ahol a hibát elkövette.

### 5.4 A kényelmetlenségi szabad szöveg SOHA nem kerül naplóba

Az ADR 0260 §4 UI-oldali betartása. A napló azonosítót írhat, tartalmat nem.

### 5.5 Minden szöveg ARB-n át megy

Magyar és angol. Hard-kódolt felhasználói szöveg tilos.

### 5.6 Nagy betűméretnél nincs túlcsordulás

A hozzáférhetőség nem opció. A teszt nagy szövegméretet is mér.

## 6. Acceptance criteria

| # | Kritérium | Bizonyíték |
|---|---|---|
| A1 | Az alapfolyamat végigvihető, és a draft lépésenként mentődik | `plan_setup_screen_test.dart` |
| A2 | Az app újraindítása után a wizard folytatható | ugyanott |
| A3 | A visszalépés nem veszít adatot | ugyanott |
| A4 | A „nem tudom" NEM vezet default értékhez | ugyanott |
| A5 | A hard konfliktus azonnal látszik | ugyanott |
| A6 | Nagy betűméretnél nincs túlcsordulás | `availability_editor_test.dart` |
| A7 | Semantics (képernyőolvasó) címkék jelen vannak | ugyanott |
| A8 | Minden szöveg ARB-ből jön (hu + en) | l10n paritás-ellenőrzés |
| A9 | A kényelmetlenségi szöveg nem kerül naplóba | `plan_setup_screen_test.dart` — gyűjtő logger |

### 6.1 Mérce-mátrix — melyik hibás implementációt melyik cella fogja pirosra

| Hibás implementáció | Melyik cella vált PIROSRA |
|---|---|
| A „nem tudom" default értékre fordítva | **A4** |
| A draft csak a végén mentődik | A1/A2 |
| A visszalépés törli a lépés adatait | A3 |
| A konfliktus csak a végén jelenik meg | A5 |
| Hard-kódolt felhasználói szöveg | A8 |
| A szabad szöveg naplózva | **A9** |
| Fix magasságú sorok nagy betűméretnél | A6 |

**A wizard-állapot három kötelező cellája** (a határ: a megkezdett lépés):

| Cella | Bemenet | Elvárt |
|---|---|---|
| lépés előtt | a wizard el sem indult | nincs draft, üres állapot |
| a határon | **egy** lépés kitöltve, app újraindul | a draft visszatér, a wizard ott folytatódik |
| lépés után | minden lépés kitöltve, app újraindul | a teljes draft visszatér, generálás indítható |

**Valódi-sértés próba (KÖTELEZŐ, §10-ben dokumentálva):** fordítsd a „nem
tudom"-ot default értékre → az **A4** cellának PIROSNAK kell lennie →
állítsd vissza.

## 7. Kötelező ellenőrzések

```bash
tools/round-gate.sh test/features/practice_generator/presentation/plan_setup_screen_test.dart test/features/practice_generator/presentation/availability_editor_test.dart
```

Külön processzek, csonkítatlan kimenet. **Tilos** `| tail`, `| head`,
`&&`-lánc vagy bármilyen szűrés (L09); a `flutter analyze` és `flutter test`
kézi láncolása OOM-ot ad (L05). A kötelező gate-et **TILOS háttérbe küldeni**
(`run_in_background`) — az egy-fordulós harness a forduló végén megöli (L254).

## 8. Implementációs sorrend

1. ARB-kulcsok (hu + en) — a szövegek előre.
2. `plan_setup_controller.dart` — lépés-állapot, draft-mentés lépésenként.
3. `availability_editor.dart` és `practice_goal_picker.dart`.
4. `plan_setup_screen.dart` — navigáció, azonnali konfliktus-jelzés.
5. Tesztek a §6.1 három wizard-cellájával, nagy betűmérettel és semantics-szel.
6. A valódi-sértés próba, §10-be dokumentálva.
7. `tools/round-gate.sh` a §7 szerint.

## 9. Kockázatok

- **A „nem tudom" elnyelése.** A legkényelmesebb UI-döntés, és a rendszer a
  tanuló nevében találna ki adatot (A4).
- **A végén mentő draft.** Egyszerűbb, és pont a megszakítás utáni
  folytathatóságot veszi el (A1).
- **A naplózott kényelmetlenség.** Hibakeresés közben kézenfekvő, és a
  legérzékenyebb adatot viszi ki (A9).
- **A hard-kódolt szöveg.** Gyorsabb fejlesztés, és a magyar lokalizáció
  hiányzik majd (A8).

## 10. Implementation handoff — az implementer tölti ki

### Megvalósítás

- `presentation/controller/plan_setup_controller.dart`: immutábilis wizard
  állapot, injektált óra/ID-generátor, lépésenkénti
  `GenerationDraftRepository.saveDraft`, visszaállítás és a meglévő
  `RequestValidator` azonnali futtatása. Az unknown válaszok üres
  goal/lista/constraintként maradnak meg; a comfort szöveghez nincs logger
  vagy analytics függőség.
- `presentation/screens/plan_setup_screen.dart`: öt lépéses, visszaléphető
  képernyő, akadálymentes conflict-live-region és tartós controller-csere
  esetén draft-visszatöltés.
- `presentation/widgets/practice_goal_picker.dart`,
  `availability_editor.dart`: explicit unknown vezérlők, nagy betűméretnél
  tördelő Material-lista és lokalizált Semantics címke.
- `app_en.arb`, `app_hu.arb`: azonos, teljes wizard-szövegkészlet.
- `public.dart`: a controller és a képernyő public exportja.
- A két új widget-teszt lefedi az A1–A9 releváns celláit, benne a wizard
  előtti, határon lévő és kész állapotból való visszatöltéssel.

### Futtatott ellenőrzések

- `flutter gen-l10n` — exit 0.
- `dart format <a kör hat Dart fájlja>` — exit 0.
- `flutter test test/features/practice_generator/presentation/plan_setup_screen_test.dart test/features/practice_generator/presentation/availability_editor_test.dart`
  — exit 0, 9 teszt zöld.
- `tools/round-gate.sh test/features/practice_generator/presentation/plan_setup_screen_test.dart test/features/practice_generator/presentation/availability_editor_test.dart`
  — exit 0: format, analyze, mindkét célzott teszt, architecture, secrets és
  l10n ellenőrzés zöld.

### Kötelező valódi-sértés próba (A4)

A `PlanSetupController.selectGoal` unknown ágát ideiglenesen
`PracticeGoalType.rhythm` alapértékre fordítottam. A célzott A4 teszt:

```text
flutter test ... --plain-name 'unknown answers are persisted as absence, never defaults (A4)'
Expected: empty
Actual: [Instance of 'PracticeGoal']
exit 1
```

Ezután az ágat visszaállítottam `const <PracticeGoal>[]`-ra; a fenti,
végleges célzott tesztfuttatás exit 0-val zöld.

### Eltérések és nem futtatott ellenőrzések

- Nincs scope-elt domain/application, flag, router vagy backend változtatás.
- A teljes CI suite/property/release APK nem lokálisan fut: a kör CI-dispatch,
  review és merge a Claude-orchestrátor feladata.

### Javító kör (F1–F4, 2026-08-18)

- **F1:** `63768316` — az `AvailabilityEditor` injektált referenciadátumból
  számítja az aktuális hétfőt; az
  `availability_editor_test.dart` két különböző referenciahéten méri a
  továbbadott `DailyAvailability.date` értékét.
- **F2:** `da6c02ba` — a wizard-lépés külön draft-progressz kulcsban marad
  meg, ezért az explicit `unknown` nem keveredik a meg nem nyitott lépéssel;
  a `plan_setup_screen_test.dart` availability- és equipment-regressziói
  restart után is a 2., illetve 3. lépést várják.
- **F3:** `da6c02ba` — az A9 teszt gyűjtő `debugPrint` sinket állít be, és
  ugyanazzal a sentinel szöveggel sikeres, majd szándékosan hibás
  `saveDraft` mellett is bizonyítja a naplózás hiányát.
- **F4:** `da6c02ba` — a controller kommentje pontosan plaintext helyi
  draft-tárolást ír le, nem titkosítást.

## 11. Review — a Claude tölti ki
