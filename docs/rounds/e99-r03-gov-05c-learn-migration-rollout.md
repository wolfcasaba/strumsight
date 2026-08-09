# E99-R03 (GOV-05c) — Learn migráció a Practice Engine V2-re

- **Státusz:** PLANNING (pre-flight lezárva 2026-08-09, kód olvasva:
  `main @ 458eddc6`; a sugár **mérve** egy `/tmp` próba-klónban, nem becsülve)
- **Típus:** **governance-kör** (nem SDD-fejezet) — a `HANDOFF.md` §6
  „Kötelező sorrend" 3. pontjának harmadik harmada
- **Kör-azonosító:** `E99-R03`. Az `E99` a governance-körök fenntartott
  pszeudo-epic kódja (nem valódi epic) — a `tools/ai_router/brief.py:19`
  `(?i)(e\d{2}-r\d{2})` és a `tools/round-pipeline.sh:278`
  `^[A-Z][0-9]{2}-R[0-9]{2}$` mintája miatt a „GOV-05c" alakú fájlnév kiesne a
  gépi kapukból. Emberi neve végig **GOV-05c**.
- **Branch:** `codex/e99-r03-gov-05c-learn-migration-rollout`
- **Előfeltétel:** GOV-05a (`E99-R01`) merge-elve (`d958b75e`)
- **Brief szerzője:** Claude (Opus 5) · **Implementáció:** Codex (Terra)
- **Előre kiosztott ADR:** [`0198`](../adr/0198-learn-migration-rollout-boundary.md)
  — **MÁR MEGÍRVA az orchesztrátor által, a `docs/adr/` a TILOS zónában van.**
  Az implementer ADR-t NEM hoz létre és NEM módosít.

```ai-router
schema_version = 1
risk = "high"
allowed_paths = [
  "lib/app/config/feature_flags.dart",
  "test/app/app_config_test.dart",
  "test/app/feature_flags_test.dart",
  "test/features/learn/learn_migration_parity_test.dart",
  "test/features/learn/learn_rollback_test.dart",
  "docs/manual-testing/practice-engine-device-matrix.md",
  "docs/rounds/e99-r03-gov-05c-learn-migration-rollout.md",
]
gate_tests = [
  "test/app",
  "test/features/learn",
  "test/core",
  "test/features/live",
  "test/features/songs",
]
native_gate = true
```

> **A `gate_tests` lista az [L203](../LESSONS.md) szerint készült:** nem csak
> a módosított adatforrás (`FeatureFlags.forEnvironment`) hívóit fedi, hanem a
> `LearnScreen` **összes teszt-pumpolóját** is — `grep -rln "LearnScreen" test/`
> → 14 fájl, öt könyvtárban (`test/app`, `test/core`, `test/features/learn`,
> `test/features/live`, `test/features/songs`). A GOV-05a briefjéből pontosan
> ez a réteg maradt ki (review MINOR-1).
>
> `native_gate = true`: a kör terméke egy lab APK, amelyben a Learn a V2
> motoron fut — az APK a készülékes elfogadás bemenete.

## 0. Kör-jelzés és STOP-protokoll

```bash
tools/codex-signal.sh progress "<egy sor>"
tools/codex-signal.sh done "<egy sor>"
tools/codex-signal.sh stopped "<egy sor>"
tools/codex-signal.sh blocked "<egy sor>"
```

Lezáró jelzés nélkül a kör bukott. **Listán kívüli fájl érintése → `stopped`**,
akkor is, ha „csak teszt", és akkor is, ha „csak egy sor". Ez a kör **egyetlen
új fájlt sem hoz létre**.

## 1. Cél

A Learn ma a **legacy** ágon fut minden környezetben. Ez a kör átállítja a
Practice Engine V2-re `production`-ön kívül — egyetlen flag-sor, négy őr
átirányítása, és **semmilyen UI-változás**.

A migráció definíció szerint **láthatatlan**: ugyanaz a Learn, más motorral.
Ha a felületen bármi megváltozik, az regresszió, nem funkció.

## 2. Jelenlegi állapot (mérve 2026-08-09, `main @ 458eddc6`)

### 2.1 A flag és a validáció

`lib/app/config/feature_flags.dart:59` — `migratedLearnEnabled: false`,
hard-kódolt, a `nonProd` predikátumtól függetlenül. Dart-define override nincs.

`lib/app/config/app_config.dart:115–116` — `migratedLearnEnabled` **megköveteli**
a `practiceEngineV2Enabled`-t. Az utóbbi már `nonProd` (60. sor), tehát
`migratedLearnEnabled: nonProd` esetén a két flag **azonos** minden
környezetben, és a validáció konstrukció szerint nem tud elhasalni. **Nem kell
új validációs szabály.**

### 2.2 A migrált út KÉSZ — nincs drótozási rés

`lib/features/learn/screens/learn_screen.dart` öt helyen ágazik a flagre
(187, 253, 303, 313, 326. sor): V2 megfigyelés-gyűjtés, a mikrofon-rés zárása
pause/finish előtt, `scoreLessonV2` pontozás, `_recordLearnMomentV2` rögzítés.

A `_recordLearnMomentV2` a `practiceSessionRecordingProvider`-t olvassa, amely
**teljesen drótozott** (`practice_session_recording.dart:199–208`), nem dob.
`grep -rn "UnimplementedError" lib/features/practice/ lib/features/learn/`
→ **nulla találat**. Ez a kör tehát NEM ütközik abba a hiányzó-production-
drótozás hibaosztályba, ami az AI Tutort blokkolja (`HANDOFF.md` §3).

### 2.3 A meglévő őrök

- `test/features/learn/learn_migration_parity_test.dart` — **51 cellás
  paritás-mátrix** flag-ON állapotban, plusz rossz irányok / kihagyások /
  páratlan extrák / szigorúan a tűréshatáron belüli és kívüli időeltolások /
  azonos nem-nulla input latency mindkét úton. A 303. sori „A7" teszt a
  flag-határt méri.
- `test/features/learn/learn_rollback_test.dart` — a flag-OFF ág
  viselkedés-azonossága és a V1 tároló érintetlensége; a 133. sori „A8" teszt
  a flag-határt méri.

### 2.4 A TÉNYLEGES sugár — mérve, nem becsülve

Egy `/tmp` próba-klónban a flaget `nonProd`-ra billentettem, majd lefuttattam
az L203 szerinti KÉT réteg unióját:

| Futtatott halmaz | Eredmény |
|---|---|
| `test/features/learn` + `test/app` | **260-ból 4 bukás** (1 skip, körtől független) |
| `test/core` + `test/features/live` + `test/features/songs` | **610/610 zöld** |

**A négy bukás MINDEGYIKE flag-kikötő állítás, nem viselkedési regresszió:**

1. `test/app/app_config_test.dart:196` — „environment defaults match the
   guarded rollout table": a `development` (202. sor) és a `lab` (210. sor)
   `expect(...migratedLearnEnabled, isFalse)` cellája. A production cella
   (218. sor) helyes marad.
2. `test/app/feature_flags_test.dart` — a GOV-05a-ban írt A4 kerítés
   (`'keeps unrelated rollout flags disabled in every environment'`), amely
   ciklusban állítja a `migratedLearnEnabled` `false`-t minden környezetre.
3. `test/features/learn/learn_migration_parity_test.dart:303` — „A7 — the V2
   ON flag production default stays OFF (no rollout)". **Figyelem:** a teszt
   NEVE production-t mond, de a törzse `AppEnvironment.development`-et mér
   (304–308. sor) — a név és a mérés eddig sem egyezett.
4. `test/features/learn/learn_rollback_test.dart:133` — „A8 —
   `FeatureFlags.migratedLearnEnabled` default is OFF in every env", ciklus
   `AppEnvironment.values` felett.

**A tizenhárom, `appConfigProvider`-t NEM kikötő Learn-képernyő-teszt mind
ZÖLD maradt a V2 úton:** `expected_chord_hint`, `hit_burst`, `learn_screen`,
`live_scoring_jitter`, `next_lesson_cta`, `review_r100_fixes`,
`setlist_expected_hint`, `visual_offset`, `waltz_count_in`,
`onboarding_first_win`, `screen_size_guard`, `expected_hint_cleared_on_live`,
`setlist_flow`. **Ezekhez NEM kell hozzányúlni** — és nincsenek is az
engedélyezett listán.

## 3. Scope

**Benne:**

1. `migratedLearnEnabled: false` → `nonProd` a `FeatureFlags.forEnvironment`
   factoryban, és a 43–45. sori doc-comment átírása (ma azt állítja:
   „migrated Learn stays OFF everywhere until the parity rollout decision" —
   a döntés megszületett, ez az ADR 0198).
2. A `migratedLearnEnabled` doc-commentje a mezőnél (93. sor környéke), ha
   avulttá válik.
3. A §2.4 **négy** őrének átirányítása a production-határra.
4. A `docs/manual-testing/practice-engine-device-matrix.md` migrated-Learn
   szakaszának frissítése: az út mostantól alapértelmezetten él lab buildben,
   a cellák PENDING-ek.
5. A brief §10 handoff kitöltése.

**Kívül (ebben a körben TILOS):**

- **Bármilyen UI-változás** (ADR 0198 Döntés 4). A `learn_screen.dart`, a
  `lesson_list_screen.dart` és minden más `lib/features/**/screens|presentation`
  fájl a tilos zónában van. Nincs új belépési pont, nincs „V2" jelölés.
- **Bármely más flag értéke.** `songTrainerV2Enabled` (GOV-05a óta `nonProd`),
  `aiTutor*` (BLOKKOLT, `HANDOFF.md` §3), mind a 11 `vision*` (BLOKKOLT) —
  mind változatlan.
- **A 13 zöld Learn-képernyő-teszt bármelyike.** Ha valamelyik mégis pirosra
  váltana, az ÚJ információ → `stopped` (OD-02), nem néma javítás.
- Új validációs szabály az `app_config.dart`-ban (§2.1).
- Új ARB-kulcs, `lib/l10n/` bármely fájlja.
- Új ADR — a 0198 megvan, `docs/adr/` tilos zóna.
- `.github/`, `tool/`, `tools/`, `assets/`.

## 4. Engedélyezett fájlok

| Útvonal | Miért |
|---|---|
| `lib/app/config/feature_flags.dart` | a `migratedLearnEnabled` sora + doc-commentek |
| `test/app/app_config_test.dart` | a rollout-tábla dev/lab cellái |
| `test/app/feature_flags_test.dart` | a GOV-05a A4 kerítés átirányítása |
| `test/features/learn/learn_migration_parity_test.dart` | az A7 őr átirányítása |
| `test/features/learn/learn_rollback_test.dart` | az A8 őr átirányítása |
| `docs/manual-testing/practice-engine-device-matrix.md` | migrated-Learn szakasz |
| `docs/rounds/e99-r03-gov-05c-learn-migration-rollout.md` | §10 handoff |

**Tilos zóna:** `lib/features/**` (MINDEN — ez a kör egyetlen production
Dart-sort sem ír a `feature_flags.dart`-on kívül), `lib/app/routing/`,
`lib/app/home_shell.dart`, `lib/app/config/app_config.dart`,
`lib/app/bootstrap/`, `lib/l10n/`, `docs/adr/`, `.github/`, `tool/`, `tools/`,
`assets/`, és a §2.4-ben felsorolt 13 zöld tesztfájl.

**A fájllista a tervezőt is köti:** ha a kör kivihetetlennek bizonyul a listán
belül, a helyes lépés a `stopped` indoklással — nem a lista csendes tágítása.

## 5. Kötött architekturális döntések

Forrás: [ADR 0198](../adr/0198-learn-migration-rollout-boundary.md).

### 5.1 A flag-határ alakja

`migratedLearnEnabled: nonProd` — ugyanaz a predikátum, amit a
`practiceEngineV2Enabled`, `practiceDetailedHistoryEnabled` és (GOV-05a óta) a
`songTrainerV2Enabled` használ. NINCS dart-define override, NINCS új
környezet, NINCS rollout-stage enum, NINCS felhasználói kapcsoló (ez
availability-flag, nem preferencia). Az alapértelmezett konstruktor paramétere
(`this.migratedLearnEnabled = false`, 16. sor) **változatlan**.

### 5.2 A négy őr átirányítása — a törlés NEM elfogadható feloldás

Mindegyiknél megmarad, hogy `migratedLearnEnabled == false`
`AppEnvironment.production`-ben; a `development`/`lab` cella `true`-ra vált.

**Nem elfogadható:** bármelyik teszt vagy `group` törlése; `skip`-elés; olyan
átírás, amely után nem marad `AppEnvironment.production`-re szóló állítás.

**Az A7 tesztnél külön figyelem:** a neve „production default stays OFF", de a
törzse ma `development`-et mér. Az átirányításnál a **nevet és a mérést
össze kell hozni** — a teszt mérjen `AppEnvironment.production`-t, és a neve
maradjon/legyen ezzel összhangban. A név-mérés eltérés csendes fenntartása
nem elfogadható.

### 5.3 A rollback-őr flag-OFF ága érintetlen

A `learn_rollback_test.dart` flag-OFF viselkedés-tesztjei (az A8 flag-határ
teszten kívül) **szó szerint változatlanok**. Ez a visszaút gépi garanciája.

### 5.4 Semmilyen UI-változás

Lásd §3 „Kívül". A migráció láthatatlan.

### 5.5 Nyitott döntések — előre rögzített feloldással (ADR 0138)

```yaml
open_decisions:
  - id: OD-01
    question: >
      A device-mátrix migrated-Learn sorai milyen státusszal nyíljanak?
    blocking: false
    resolution_policy: use_default
    default: >
      PENDING. A valós eszközös bizonyíték a user menete; a PENDING sor NEM
      merge-kapu (a GOV-05a és az Epic 5 gyakorlata).

  - id: OD-02
    question: >
      Mi a teendő, ha a §2.4-ben ZÖLDNEK mért 13 Learn-képernyő-teszt
      valamelyike mégis pirosra vált?
    blocking: true
    resolution_policy: stop_and_ask
    default: >
      `stopped` jelzés, a teszt nevével és a NYERS kimenettel. Ez tudatosan
      halt-pont, NEM use_default: az orchesztrátor a flaget átbillentve
      MEGMÉRTE, hogy mind a 13 zöld. Ha mégis piros, akkor vagy a mérés
      környezete tért el, vagy a migrált út tényleges viselkedési
      regressziót hoz — mindkettő olyan ÚJ információ, ami a rollout-döntést
      érintheti, tehát nem futhat át egy default-on. A teszt javítása vagy a
      listára vétele TILOS jelzés nélkül.

  - id: OD-03
    question: >
      Az A7 teszt nevét vagy a törzsét igazítsuk egymáshoz?
    blocking: false
    resolution_policy: use_default
    default: >
      A TÖRZSET a névhez: a teszt mérjen `AppEnvironment.production`-t
      (§5.2). A név már ma is a helyes szándékot fejezi ki.
```

## 6. Acceptance criteria

- [ ] **A1 — Környezet-mátrix a flagre**, három **külön** cellaként (nem
  `AppEnvironment.values` ciklus — a ciklus egyetlen hibaüzenetbe olvasztja a
  három cellát):

  | `AppEnvironment` | elvárt `migratedLearnEnabled` |
  |---|---|
  | `development` | `true` |
  | `lab` | `true` |
  | **`production`** | **`false`** |

  A `production` cella az egyetlen, ami megkülönbözteti a helyes `nonProd`
  megoldást a hibás „mindenhol `true`"-tól.

- [ ] **A2 — A default konstruktor változatlan:** `const FeatureFlags(
  accountEnabled: false, diagnosticsEnabled: false, labModeAvailable: false)`
  → `migratedLearnEnabled == false`. A meglévő állítás
  (`app_config_test.dart:222` környéki „new constructor fields are optional")
  érintetlen marad.

- [ ] **A3 — Mind a NÉGY őr átirányítva, egyik sem törölve.** A §2.4 négy
  tesztje/csoportja továbbra is létezik, és **mindegyik** tartalmaz legalább
  egy `AppEnvironment.production` → `isFalse` állítást. Törlés, `skip`, vagy
  minden production-állítás eltávolítása **nem elfogadható**.

- [ ] **A4 — Az A7 teszt neve és mérése egyezik** (§5.2, OD-03): a törzs
  `AppEnvironment.production`-t mér.

- [ ] **A5 — Az `AppConfig` validáció mind a három környezetben ÉRVÉNYES
  konfigurációt ad.** `AppConfig.resolve` (vagy a `app_config_test.dart`
  meglévő mintája szerinti hívás) `development`, `lab` és `production`
  esetén is `problems`-mentes — a `migratedLearnEnabled requires
  practiceEngineV2Enabled` szabály egyik környezetben sem sül el.

- [ ] **A6 — Kerítés: a többi rollout-flag NEM mozdult.** Mind a három
  környezetre: `songTrainerV2Enabled == nonProd` (dev/lab `true`, prod
  `false`), `aiTutorEnabled`, `aiTutorCloudEnabled`, `visionEnabled` mind
  `false`. (A 11 vision flag teljes mátrixát a
  `test/features/vision/vision_offline_regression_test.dart` méri — annak
  **módosítás nélkül zölden kell maradnia**; tilos zóna.)

- [ ] **A7 — A rollback-őr flag-OFF ága szó szerint változatlan.** A
  `learn_rollback_test.dart` diffje kizárólag az A8 flag-határ tesztet
  érinti; a viselkedés-tesztek (`'A8 — flag OFF renders the same Play control
  as the legacy build'`, `'A8 — flag OFF leaves the V1 store and
  lesson-progress untouched'`) egyetlen `expect`-je sem változik.

- [ ] **A8 — Nulla production Dart-változás a flagen kívül.**
  `git diff --name-only origin/main...HEAD | grep '^lib/'` **kizárólag**
  `lib/app/config/feature_flags.dart`-ot ad. Ez az ADR 0198 Döntés 4
  („a migráció láthatatlan") gépi mércéje.

- [ ] **A9 — A device-mátrix migrated-Learn szakasza frissítve**, PENDING
  cellákkal (OD-01).

- [ ] **A10 — A gate zöld**, a §7 szerinti egyetlen artefaktum-hívással.

> **Miért nincs alatta/rajta/fölötte cellahármas:** a kör egyetlen
> acceptance-pontja sem numerikus küszöbre mér — minden mérce logikai
> (flag-érték, teszt megléte, fájl érintettsége). A helyére a **teljes**
> logikai cellamátrix lép: az A1 három környezet-cellája és az A6 kerítése
> kötelező, egyik sem hagyható el.

### 6.1 Mérce-mátrix — melyik hibás implementációt melyik cella fogja pirosra

| Hibás implementáció | Melyik cella vált PIROSRA |
|---|---|
| `migratedLearnEnabled: true` (hard-kódolt, minden környezetben) | **A1 `production` cella** + A3 mind a négy őre |
| A flip elmarad (marad `false`) | A1 `development` és `lab` cellák |
| A default konstruktor paramétere is `true`-ra írva | **A2** |
| Bármelyik őr törölve / `skip`-elve | **A3** |
| Az A7 teszt továbbra is `development`-et mér | **A4** |
| A flip „ráfut" a tutor/vision flagre is | **A6** |
| A rollback-őr viselkedés-tesztjei is átírva | **A7** (reviewer eldobható próbája: `git diff` a fájlra) |
| Bármilyen UI-„igazítás" a `learn_screen.dart`-ban | **A8** (`git diff --name-only` egynél több `lib/` fájlt ad) |

**Valódi-sértés próba (kötelező, §10-ben dokumentálandó):** írd át
ideiglenesen a factory `migratedLearnEnabled` sorát `nonProd` helyett
`true`-ra → az **A1 `production` cellájának PIROSNAK kell lennie** → állítsd
vissza, és idézd a nyers kimenetet.

## 7. Kötelező ellenőrzések

**Egyetlen parancs, csővezeték és `tail` nélkül:**

```bash
tools/round-gate.sh test/app test/features/learn test/core test/features/live test/features/songs
```

A lépések külön processzként futnak, csonkítatlan kimenettel. **Tilos**
`| tail`, `| head`, `&&`-lánc vagy bármilyen szűrés (`docs/LESSONS.md` L09);
a `flutter analyze` és `flutter test` kézi láncolása ezen a gépen OOM-ot ad
(L05).

Ez a lista **szándékosan széles**: az L203 szerint a `LearnScreen` mind a 14
teszt-pumpolóját fedi, öt könyvtárban. Ne szűkítsd.

A teljes suite + randomizált property gate + APK a CI-ban (ADR 0053) — azt az
**orchesztrátor** indítja; az implementer `gh`-t nem hív.

## 8. Implementációs sorrend

1. `feature_flags.dart`: az 59. sor `false` → `nonProd`, és a 43–45. sori
   doc-comment átírása (+ a mező doc-commentje, ha avul).
2. `app_config_test.dart`: a rollout-tábla `development`/`lab` cellái
   `isTrue`-ra; a production cella marad; A5 hozzáadása, ha még nincs.
3. `feature_flags_test.dart`: az A4 kerítés átirányítása (a
   `migratedLearnEnabled` kikerül a „minden környezetben false" ciklusból, és
   megkapja a saját három celláját — A1); a többi flag kerítése marad (A6).
4. `learn_migration_parity_test.dart`: az A7 őr átirányítása + a név/mérés
   összehozása (§5.2).
5. `learn_rollback_test.dart`: az A8 őr átirányítása; a viselkedés-tesztek
   érintetlenül.
6. Gate futtatása — **itt már zöldnek kell lennie**; ha nem, OD-02.
7. A valódi-sértés próba (§6.1) + visszaállítás.
8. `practice-engine-device-matrix.md` (A9).
9. Záró gate + §10 handoff + `done`.

## 9. Kockázatok

1. **A pontozás motorja megváltozik** (`scoreLessonV2`), tehát a
   lecke-csillagok és a Progress irány-pontossága elvileg más értéket adhat
   ugyanarra a játékra. Az 51 cellás paritás-mátrix ezt méri szintetikusan;
   valós hangon a GOV-06 fogja.
2. **A migrált út valós eszközön még sosem futott.** A szintetikus zöld nem
   „done" (HORIZON) — a device-mátrix PENDING sorai teszik ezt láthatóvá.
3. **A 13 zöld teszt zöldsége mérés, nem garancia** — más gépen/CI-ban
   eltérhet. Ezért OD-02 `stop_and_ask`, nem `use_default`.
4. **A `development` is átáll**, tehát minden CI dev-build a V2 Learn-t
   futtatja. Szándékos (ADR 0198).

## 10. Implementation handoff — a Codex tölti ki

- Fájlonkénti összefoglaló.
- Futtatott parancsok + **TÉNYLEGES, csonkítatlan** kimenet.
- A §6.1 valódi-sértés próba: mit írtál át, melyik cella lett piros (nyers
  kimenet), és a visszaállítás igazolása.
- Az **A8** bizonyítéka: a `git diff --name-only origin/main...HEAD | grep '^lib/'`
  tényleges kimenete.
- Melyik OD-t használtad, és hogyan.
- Eltérések a tervtől és okuk; nem futtatott ellenőrzések és okuk; follow-upok.

> Minden viselkedési állításhoz add meg a tesztet, ami bizonyítja. Állítás
> teszt nélkül = bemondás.

## 11. Review — a Claude tölti ki

Link: `docs/reviews/e99-r03-gov-05c-learn-migration-rollout-review.md`
