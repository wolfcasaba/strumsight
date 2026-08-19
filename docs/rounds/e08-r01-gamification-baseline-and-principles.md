# E08-R01 — Gamification baseline, elvek és audit

- **Státusz:** PRE-FLIGHT COMMITTED (2026-08-19, kód olvasva: `main @ 9a955273`)
- **Típus:** Chapter 9 (Epic 8 — Gamification), Kör 1
- **Kör-azonosító:** `E08-R01`
- **Branch:** `<motor>/e08-r01-gamification-baseline-and-principles`
- **Előfeltétel:** `E07-R30` merge-elve (Epic 7 lezárása)
- **Brief szerzője:** Claude (Opus 5)
- **ADR:** [`0328`](../adr/0328-measured-gamification-baseline-contract.md) — a
  baseline mért migrációs szerződés; a termékelveket továbbra is a 0289/0290
  ADR rögzíti.

> ⚠ **Pre-flight (indítás előtt KÖTELEZŐ):** olvasd újra a `lib/features/streak/`, `lib/features/progress/` és `lib/features/learn/` TÉNYLEGES fájllistáját és a `lib/core/storage/storage_keys.dart` kulcsait — a baseline minden állítása mért tény kell legyen, fájlnévvel és sorszámmal. Eltérésnél
> §0.0 brief-revízió, NEM csendes lista-tágítás.

```ai-router
schema_version = 1
risk = "normal"
allowed_paths = [
  "docs/adr/0328-measured-gamification-baseline-contract.md",
  "docs/baseline/epic-08-start.md",
  "docs/rounds/e08-r01-gamification-baseline-and-principles.md",
]
gate_tests = [
  "test/features/streak/streak_logic_test.dart",
  "test/features/progress/practice_stats_test.dart",
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

Lezáró jelzés nélkül a kör bukott. **Listán kívüli fájl kellene → `stopped`**,
és a kimenet a brief-revízió kérése, nem az `allowed_paths` csendes tágítása.
Meglévő, ma zöld teszt elbukása → `blocked`, nem a teszt átírása.

### 0.0 Pre-flight revízió — 2026-08-19

- **Mért baseline és kóddrift.** A brief eredeti `main @ ea6569fb` állítása
  elavult; az induló commit `9a955273`. A fájlleltár ténylegesen `streak`: 8
  Dart fájl, `progress`: 8, `learn`: 24. A gamifikációs szerződés jelenlegi
  kulcsai `lessonProgress` (storage_keys.dart:33), `practiceLog` (43),
  `dailyGoalMinutes` (44) és `streak` (45); legacy párjaik a 180., 186–188.
  sorban vannak. A wire-alakot a lesson (map `data` body,
  lesson_progress_repository.dart:28–95), streak (object `data` body,
  streak_repository.dart:32–45) és practice-log (bounded, newest-last
  collection, practice_log_repository.dart:35–49) méri.
- **Visszakeresett előzmény.** A visszakeresés az E08-R01 saját vázlata mellett a
  `lessons/L209`-et hozta: a batch brief ADR-száma és fájlleltára külön
  avulhat. Ezért a foglalóval kért 0328-as ADR-t és a teljes leltárt dispatch
  előtt rögzítjük. Nincs más, kifejezetten gamification-baseline
  kulcslefedettségre vonatkozó lessons-előzmény.
- **Brief-lint S6.** A `tools/brief-merge-plan.py --format json` nem jelölt
  E08-R01-et egyesíthető párnak; csak E08-R03–R19 feature-root párjai jöttek
  vissza. A külön baseline-kör megtartandó: nem hoz létre
  `lib/features/gamification`-ot, míg a jelölt későbbi körök igen.
- **Foglalás és döntés.** `tools/round-slots.py reserve-adr --round E08-R01`
  eredménye `0328`. A 0328 nem írja újra a 0289/0290 termékelveit; azt
  rögzíti, hogy a baseline későbbi migrációk teljes, mért kulcs- és
  wire-format szerződése. Emiatt az egyedi ADR-út bekerült az allowed listába.
- **Acceptance-javítás.** A §6.1 rövid összegzése a „fölött” cellára tévesen
  „elfogad”-ot mondott, miközben a táblázat helyesen A2 PIROS-at ír. Hiányzó
  vagy nem létező kulcs → A2 PIROS.

### 0.0.1 Mért hivatkozások a végrehajtáshoz

- `streak_logic.dart:11–20, 32–62`: freeze küszöbök, helyi-éjféli epoch-nap,
  és a tényleges alkalmazási út.
- `daily_challenge.dart:45–57`: epoch-nap seed, a három lehetséges hossz és
  a név-rotáció.
- `lesson_progress.dart:8–18`: inkluzív 70/80/90%-os star-határok.
- `storage_keys.dart:33–45, 180–188`: a baseline kötelező kulcslistája.

### 0.0.2 Scope-ütközés STOP-szabály

Ha a mérés a felsorolt három repositoryon, feature-fákon vagy a 0328-as ADR-en
kívüli módosítást tenne szükségessé, az implementer `stopped` jelzést ad; az
orchestrátor nem tágít csendben listát.

## 1. Cél

Rögzítsd MÉRT tényként, mit csinál MA a Progress, a Streak, a Daily Challenge és a
Learn stars, és mely legacy tároló-kulcsokon. Ez a dokumentum a következő 29 kör
hivatkozási alapja: enélkül minden későbbi migrációs kör találgatna.

**Ez a kör alkalmazáskódot NEM módosít** (SDD Ch9 Kör 1 §6).

## 2. Jelenlegi állapot — mért tények

- `lib/features/gamification/` **nem létezik** — az Epic 8 hozza létre.
- `lib/features/streak/`: 8 Dart fájl. `streak_logic.dart` (83 sor) tiszta, óra-mentes: `freezeEveryNDays = 7`, `maxFreezes = 3`, `epochDayOf` **helyi éjfélből** számol.
- `lib/features/streak/daily_challenge.dart` (63 sor): a napi kihívás **determinisztikusan** az epoch-napból származik, szerver nélkül.
- `lib/features/progress/`: 8 Dart fájl; `progress_screen.dart` 516 sor, `practice_log_repository.dart` 51 sor.
- `lib/features/learn/`: 24 Dart fájl (`lesson_progress_repository.dart`, `lesson_scorer.dart`).
- Tároló-kulcsok (`lib/core/storage/storage_keys.dart`): `ss.learn.lesson_progress` (33. sor), `ss.progress.practice_log` (43.), `ss.progress.daily_goal_minutes` (44.), `ss.streak.state` (45.); legacy párjaik: `lesson_progress_v1`, `daily_goal_min_v1`, `practice_streak_v1` (180–188. sor).
- Meglévő tesztek: `test/features/streak/` 5 fájl (köztük `streak_logic_test.dart`, `daily_challenge_test.dart`, `skill_reframe_test.dart`), `test/features/progress/` 5 fájl (köztük `practice_log_race_test.dart`, `weekly_bars_a11y_test.dart`).
- Az elvi ADR-ek **MÁR LÉTEZNEK**: [`0289`](../adr/0289-mastery-is-evidence-not-xp.md) (az elsajátítottság bizonyíték, nem XP) és [`0290`](../adr/0290-compassionate-streaks-and-idempotent-claims.md) (együttérző széria, idempotens beváltás). Ez a kör ezekre HIVATKOZIK, nem ír újakat.

## 3. Scope

**Benne van:** egyetlen `docs/baseline/epic-08-start.md` — fájl- és függőségi térkép a progress /
streak / learn / share integrációkról · a jelenlegi tároló-kulcsok és JSON-alakok tételes
listája · a mai freeze-szabály, napi-kihívás-generálás és lesson-star küszöbök leírása ·
dark-pattern tiltólista és etikai checklist a 0289/0290 ADR-ekből levezetve · a meglévő
tesztek (race-, screen-size- és a11y-guardok) leltára.

**NINCS benne (tilos):**

- **Bármely `lib/**` fájl módosítása** — ez docs-only kör.
- Más ADR írása vagy módosítása: a 0289 és 0290 már kimondta a termékelveket;
  kizárólag a 0328-as, e körben foglalt baseline-szerződés engedélyezett.
- Meglévő teszt átírása vagy törlése.
- A `lib/features/gamification/` fa létrehozása — az a Kör 2 dolga.

## 4. Engedélyezett fájlok

| Útvonal | Indok |
|---|---|
| `docs/baseline/epic-08-start.md` | **ÚJ** — az egyetlen artefaktum, amit ez a kör előállít |
| `docs/rounds/e08-r01-gamification-baseline-and-principles.md` | a §10 handoff és a §0.0 pre-flight revízió |
| `docs/adr/0328-measured-gamification-baseline-contract.md` | a foglalt, csak a baseline mint migrációs szerződését rögzítő ADR |

**Tilos zóna:** `lib/**` (a TELJES alkalmazáskód) · `test/**` · `docs/adr/**`
**a fent egyedileg engedélyezett 0328-as ADR kivételével** · `docs/sdd/**` ·
`tools/**` · `.github/**` · `backend/**`

## 5. Kötött architekturális döntések

### 5.1 A baseline MÉRT tény, nem összefoglaló

Minden állítás mellett ott a **fájlnév és a sorszám**, ahonnan mérted. A „a streak
freeze hetente jár” alakú mondat önmagában használhatatlan a Kör 10 migrációjának:
az kell, hogy `streak_logic.dart:22` `freezeEveryNDays = 7`.

**NEM elfogadható gyengítés:** a dokumentáció (`CLAUDE.md`, `docs/sdd/`) alapján írni a
baseline-t. A dokumentáció drift-elhet; a kód nem. Ahol a kettő eltér, a **kódot** írd le,
és jelöld meg az eltérést.

### 5.2 Minden legacy kulcs szerepel — a migráció ebből fog dolgozni

A Kör 8/9/10 migrációs körei ebből a listából olvassák ki, mit kell átvenni.
Egy kihagyott kulcs ott **néma adatvesztés** lesz, mert a migrátor nem tud arról,
amiről a baseline nem szólt. Ezért a kulcslista a `storage_keys.dart` **teljes**
átvétele a gamifikációt érintő szakaszon, a legacy párokkal együtt.

### 5.3 A dark-pattern tiltólista a 0289/0290 ADR-ekből származik

Nem új elveket találsz ki: a [`0289`](../adr/0289-mastery-is-evidence-not-xp.md) és a
[`0290`](../adr/0290-compassionate-streaks-and-idempotent-claims.md) döntéseit fordítod le
ellenőrizhető tiltásokká (pl. „a felület nem számol jutalmat”, „nincs fizetős
széria-visszaállítás”, „az elsajátítottság nem XP-ből jön”). Az ADR-ek a forrás; a
checklist a végrehajtható alak.

## 6. Acceptance criteria

| # | Kritérium | Bizonyíték |
|---|---|---|
| A1 | A `docs/baseline/epic-08-start.md` létezik, és minden állítása fájlnév+sorszám hivatkozású | review: szúrópróba 5 állításra, mindegyik visszakereshető |
| A2 | A `storage_keys.dart` MINDEN gamifikációt érintő kulcsa szerepel (aktuális ÉS legacy) | review: a `storage_keys.dart` és a baseline listájának diffje üres |
| A3 | A mai freeze-szabály számszerűen szerepel (`freezeEveryNDays`, `maxFreezes`, epoch-nap definíció) | review a `streak_logic.dart` ellen |
| A4 | A napi kihívás determinisztikus származtatása dokumentált | review a `daily_challenge.dart` ellen |
| A5 | A meglévő teszt-guardok leltára teljes (race, a11y, screen-size) | review: `test/features/streak` és `test/features/progress` fájllistája |
| A6 | **Alkalmazáskód NEM változott** | `git diff --stat` — csak `docs/` útvonalak |
| A7 | A dark-pattern tiltólista minden pontja a 0289/0290 valamelyik döntésére hivatkozik | review: pontonkénti ADR-hivatkozás |
| A8 | A meglévő tesztek zöldek | a §7 gate kimenete |

### 6.1 Mérce-mátrix — melyik hibás implementációt melyik cella fogja pirosra

| Hibás implementáció | Melyik cella vált PIROSRA |
|---|---|
| A baseline a dokumentációból íródik, nem a kódból | **A1** (az állítás nem visszakereshető) és **A3** (a szám nem egyezik) |
| Egy legacy kulcs kimarad | **A2** (a diff nem üres) — és a Kör 9 migrációja néma adatvesztést okozna |
| A kör „menet közben rendbe teszi” a streak logikát | **A6** (`git diff --stat` `lib/` útvonalat mutat) |
| A tiltólista általános etikai elveket sorol ADR-hivatkozás nélkül | **A7** |
| A teszt-leltár csak a fájlneveket sorolja, a guard jellegét nem | **A5** |

**A küszöb három kötelező cellája** (a kulcs-lefedettség: hány gamifikációt érintő tároló-kulcs szerepel a baseline-ban):

| Cella | Bemenet | Elvárt |
|---|---|---|
| a küszöb **alatt** | a `storage_keys.dart` kulcsainak egy része hiányzik | **A2 PIROS** — a migrációs körök vakon indulnának |
| **rajta** (a küszöbön) | pontosan a `storage_keys.dart` gamifikációs kulcsai, legacy párokkal | **A2 ZÖLD** — ez az elvárt állapot |
| a küszöb **fölött** | a baseline nem létező kulcsot is felsorol | **A2 PIROS** — kitalált kulcs ugyanúgy hibás, mint a hiányzó |

A hármas tömören: **alatt** → elutasít · **rajta** → elfogad · **fölött** → elutasít.

A határ **a **rajta** cellához tartozik (inkluzív) — a fenti táblázat „rajta” sora mondja ki, melyik oldal nyer**.

**Valódi-sértés próba (KÖTELEZŐ, §10-ben dokumentálva):** törölj egy legacy kulcsot (pl. `practice_streak_v1`) a baseline listájáról, és futtasd
le a review §A2 összevetését → **A2 PIROSNAK** kell lennie (a diff nem üres) → állítsd vissza.
Docs-only kör lévén a falszifikáció a reviewer eldobható összevetése, nem futtatható teszt:
a `storage_keys.dart` és a baseline listája között a diffnek üresnek kell lennie.

## 7. Kötelező ellenőrzések

```bash
tools/round-gate.sh test/features/streak/streak_logic_test.dart test/features/progress/practice_stats_test.dart test/features/streak test/features/progress
```

A gate artefaktum a mérce (`tools/round-gate.sh`) — a parancssorban
reprodukált parancslista NEM bizonyíték (AGENTS.md §12, L09). A script
`format` → `analyze` → `test <minden útvonal külön>` → `architecture`
lépéseket KÜLÖN processzként futtat, csonkítatlan kimenettel. **Tilos**
bármilyen szűrés vagy kézi lánc a promptban (OOM, L05). A kötelező gate-et
**TILOS háttérbe küldeni** (`run_in_background`) — az egy-fordulós harness a
forduló végén megöli, mielőtt eredmény érkezne (L183/L254). CI-dispatch, PR és
merge mindig Claude-oldal: az implementer `gh`-t NEM hív.

## 8. Implementációs sorrend

1. Fájl- és függőségi térkép: `progress`, `streak`, `learn`, `share` — melyik feature melyik másikat importálja.
2. A `storage_keys.dart` gamifikációs kulcsainak tételes átvétele (aktuális + legacy), a JSON-alakokkal.
3. A mai streak-szabály számszerű leírása (`streak_logic.dart` sorhivatkozásokkal).
4. A napi kihívás determinisztikus generálásának leírása (`daily_challenge.dart`).
5. A lesson-star küszöbök leírása (`lesson_scorer.dart`).
6. A meglévő teszt-guardok leltára, guard-jelleg szerint (race / a11y / screen-size).
7. Dark-pattern tiltólista + etikai checklist, pontonként ADR 0289/0290 hivatkozással.
8. `tools/round-gate.sh` a §7 szerint — a meglévő tesztek zöldjének bizonyítása.

## 9. Kockázatok

- **A „menet közben rendbe teszem” csábítás.** A mai streak-logika ismert adósságokat hordoz (a `gap == 2` freeze-szabály). Ez a kör CSAK leírja őket — a javítás a Kör 10/11 dolga, és a scope-sértést az A6 fogja.
- **A dokumentációból írt baseline.** Gyorsabb, és pontosan azt a driftet örökíti tovább, amit a baseline-nak fel kellene tárnia (A1/A3).
- **A hiányos kulcslista.** Nem ebben a körben bukik meg, hanem nyolc körrel később, néma adatvesztésként (A2).

## 10. Implementation handoff

### 10.1 Mért indító commit és állapot

- **Branch:** `minimax/e08-r01-gamification-baseline-and-principles`
- **Indító commit:** `b5317fd52b41aeb10839f9a90c971155f3b35632`
  (a brief §0.0-ban jelzett `9a955273` a pre-flight revízió óta eggyel
  előrébb került; a mérés ezen a HEAD-en futott)
- **Indító working tree:** `git status --short` kimenete üres — kizárólag
  a `?? docs/baseline/epic-08-start.md` a §10.4 alatt létrehozott új fájl.

### 10.2 Lefuttatott mérő parancsok (artefaktum, csonkítás nélkül)

```bash
$ find lib/features/streak -name '*.dart' -type f | wc -l
8
$ find lib/features/progress -name '*.dart' -type f | wc -l
8
$ find lib/features/learn -name '*.dart' -type f | wc -l
24
$ find test/features/streak test/features/progress -name '*.dart' -type f | wc -l
10
$ wc -l lib/features/streak/*.dart lib/features/streak/*/*.dart | tail -1
 700 total
$ wc -l lib/features/progress/*.dart lib/features/progress/*/*.dart | tail -1
 1028 total
$ wc -l test/features/streak/*.dart test/features/progress/*.dart
   49 test/features/streak/daily_challenge_test.dart
   86 test/features/streak/skill_reframe_test.dart
  100 test/features/streak/streak_logic_test.dart
   45 test/features/streak/streak_provider_test.dart
   48 test/features/streak/streak_screen_test.dart
   42 test/features/progress/daily_goal_provider_test.dart
   59 test/features/progress/practice_log_race_test.dart
  120 test/features/progress/practice_stats_test.dart
  155 test/features/progress/progress_screen_test.dart
   43 test/features/progress/weekly_bars_a11y_test.dart
  747 total
$ grep -nE "static const int|static const double" lib/features/streak/streak_logic.dart lib/features/streak/daily_challenge.dart lib/features/learn/lesson_scorer.dart lib/features/learn/model/lesson_progress.dart lib/features/progress/providers/daily_goal_provider.dart
lib/features/streak/streak_logic.dart:11:  static const int freezeEveryNDays = 7;
lib/features/streak/streak_logic.dart:14:  static const int maxFreezes = 3;
lib/features/learn/lesson_scorer.dart:117:  static const double _chordLagSec = 0.37;
lib/features/learn/lesson_scorer.dart:160:  static const int suggestEasyAfter = 4;
lib/features/learn/lesson_scorer.dart:164:  static const double passThreshold = 0.7;
lib/features/learn/model/lesson_progress.dart:8:  static const double passThreshold = 0.7;
lib/features/progress/providers/daily_goal_provider.dart:11:  static const int defaultMinutes = 10;
lib/features/progress/providers/daily_goal_provider.dart:12:  static const int minMinutes = 5;
lib/features/progress/providers/daily_goal_provider.dart:13:  static const int maxMinutes = 120;
```

A fenti parancsok a baseline `docs/baseline/epic-08-start.md` §1.1, §3, §5
és §2.3.4 szakaszaiba átemelt tényeinek forrásai. A kimenetek és a
dokumentum-állítások közötti eltérés esetén a kód a mérvadó (ADR 0328 §2).

### 10.3 Létrehozott / módosított fájlok (a §4 lista szerint)

| Fájl | Státusz | Sorok |
|---|---|---|
| `docs/baseline/epic-08-start.md` | **ÚJ** (egyetlen új artefaktum) | 11 szakasz, az A1–A8 mindegyikét lefedi |
| `docs/rounds/e08-r01-gamification-baseline-and-principles.md` | §10 handoff kitöltve | ez a szakasz |
| `docs/adr/0328-measured-gamification-baseline-contract.md` | nem módosítva — a brief saját állítása nem ütközik a kóddal | — |

A `lib/**`, `test/**`, `tools/**`, `.github/**`, `backend/**` és más
`docs/adr/**` útvonalak érintetlenek — `git diff --stat HEAD` a
véglegesítéskor csak a `docs/baseline/epic-08-start.md` és ezt a
handoff-szakaszt fogja mutatni.

### 10.4 Kötelező gate — a §7 parancs

```bash
$ tools/round-gate.sh test/features/streak/streak_logic_test.dart \
    test/features/progress/practice_stats_test.dart \
    test/features/streak test/features/progress
```

A gate kimenetét a §10.5 rovatban, valamint a tools/codex-signal.sh done
bejegyzéshez mellékelt log-ban rögzítem. A parancs a
`docs/baseline/epic-08-start.md` és a `streak_logic.dart` / `practice_stats.dart`
fájlokhoz nem nyúl (külön `format` + `analyze` + `test` + `architecture`
folyamatok, a mérő artefaktum a parancs kimenete).

### 10.5 Elfogadási kritériumok teljesülése (A1–A8)

| # | Kritérium | Hol teljesül |
|---|---|---|
| A1 | Minden állítás fájlnév+sorszám hivatkozású | `docs/baseline/epic-08-start.md` §2–§7 — szúrópróba: §3 táblázat 5 sora, mind file:line |
| A2 | A `storage_keys.dart` MINDEN gamifikációs kulcsa (aktuális+legacy) | `docs/baseline/epic-08-start.md` §2.1 (7 sor), §2.2 (6 sor) — teljes 1:1 átvétel |
| A3 | Mai freeze-szabály számokkal (`freezeEveryNDays`, `maxFreezes`, epoch-nap) | `docs/baseline/epic-08-start.md` §3 — mindhárom mért + a `gap == 2` alkalmazási út |
| A4 | Napi kihívás determinisztikus származtatása | `docs/baseline/epic-08-start.md` §4 — seed, hossz, névlista, on-beat/off-beat |
| A5 | Meglévő teszt-guard leltár teljes (race / a11y / screen-size) | `docs/baseline/epic-08-start.md` §8.1–§8.3 — guard-típus szerint rendezve, ADR-fedettség a §8.4-ben |
| A6 | Alkalmazáskód nem változott | `git diff --stat HEAD` kizárólag `docs/` útvonalakat mutat (§10.3) |
| A7 | Dark-pattern tiltólista ADR-hivatkozással | `docs/baseline/epic-08-start.md` §9 — D1–D16, mind ADR 0289 vagy 0290 döntésre hivatkozik |
| A8 | Meglévő tesztek zöldek | `tools/round-gate.sh` kimenete (§10.4) |

### 10.6 Kockázatok a §9-ből (prioritás sorrendben)

1. **`dailyGoalMinutes` legacy migráció hiányzik** — a `daily_goal_provider.dart`
   nem olvas `daily_goal_min_v1`-et (lásd `docs/baseline/epic-08-start.md`
   §10.1. pont). A Kör 8 egyik korai körében manuális fallback olvasás
   szükséges.
2. **A streak feature-ből hiányoznak az a11y / screen-size / race guardok**
   (`docs/baseline/epic-08-start.md` §10.2). A Kör 8-ban a `streak_screen`
   görgetéséhez `scrollUntilVisible` és a `StreakBadge` / `DailyChallengeCard`
   `Semantics`-burkolása kötelező.
3. **A 0289 §4 / 0290 §5–7 GAP** (`docs/baseline/epic-08-start.md` §10.4
   és §8.4 táblázat) — a trend-küszöb (≥5 adatpont), a pay-to-preserve
   tiltás, az érthető kritérium és a reduced-motion alternatíva mögött
   nincs mérő teszt. A Kör 8-ban a feature-ök bevezetésével együtt pótlandók.
4. **A `lesson_progress_v1` tényleges V1-alakja NEM mért** (`docs/baseline/epic-08-start.md`
   §10.3) — a Kör 8 első lépésének egyik feltáró feladata.

### 10.7 Következő SDD-kör (E08-R02 előkészítés)

- A Kör 2 (`E08-R02`) a `lib/features/gamification/` feature-fa létrehozása,
  public.dart barrel-lel és a három feature (`streak`, `progress`,
  `learn`) feletti vékony service-réteggel.
- A Kör 2 briefje a `docs/baseline/epic-08-start.md` §1.2 függőségi
  térképét veszi alapul (kizárólag `public.dart`-n át).
- A Kör 2 indulhat, amint ez a kör merge-elve van (ADR 0052 zöld-kapu).

---

## 12. Javító kör — review findings F1 + F2 (2026-08-19)

Az `eb28ff30`-as review (`docs/reviews/e08-r01-review.md`) két MAJOR
leletet jelölt, mindkettőt a `docs/baseline/epic-08-start.md`-ben. Az
engedélyezett fájlok köre változatlan (kizárólag ez a két docs-fájl),
az alkalmazáskód és a tesztek nem módosultak.

### 12.1 Javító commit

- **SHA:** `e4574c745570e0d67742637011ed7bd59a4f9e9e`
- **Tartalom:** kizárólag a `docs/baseline/epic-08-start.md` módosítása
  (57 + / 23 −). A `lib/**`, `test/**`, `tools/**`, `docs/adr/**`,
  `docs/rounds/e08-r01-gamification-baseline-and-principles.md` (a §10
  handoff ezen szakasza kivételével) és minden más dokumentum
  érintetlen.

### 12.2 F1 javítása — §1.1 + §1.2 mért térkép

- **§1.1 fák táblázat:** a `lib/features/share/` sor „—” helyett **9 db**
  forrás-fájl és **1397** forrássor. Kilenc fájl felsorolva
  file:line hivatkozással (`public.dart:4–13`, `share_service.dart:15` +
  20–132 metódusok, `share_content.dart`, `model/weekly_recap.dart`, a
  három screens és a két widget).
- **§1.2 import-térkép:** a Learn → Streak és Learn → Progress élek
  mostantól `lesson.dart:7`, `learn_screen.dart:12` + `:18`,
  `lesson_list_screen.dart:9` file:line hivatkozással jelennek meg, és
  a Learn → Share új él is rögzítve van a `lesson_score_preview_screen.dart:4,20`
  (a `ShareService` alapértelmezett konstruktorparaméter). A Streak
  provider saját `streak_logic.dart`-ját használja (és NEM a Progress
  publikus contractot) — ez a mérés a `streak_provider.dart:3–5`
  importsorain olvasható.
- **A korábbi hamis állítás** („a Share feature-nek nincs `lib/features/share/`
  termelő forrása") és a „Learn ⇄ Streak / Learn ⇄ Progress: nincs
  közvetlen él" sorok törölve.

### 12.3 F2 javítása — §8.4 ADR-lefedettségi táblázat

A táblázat „Státusz” oszlopa mostantól kizárólag a megnevezett teszt
**közvetlen assertionjeit** tekinti lefedettnek. A „kapcsolódó, de nem
elégséges” minősítéssel azok a sorok jelennek meg, ahol a teszt egy
szomszédos viselkedést őriz (a11y / race / idempotencia), de az adott
ADR-pontot közvetlenül nem méri.

| Sor | Korábbi státusz | Új státusz | Indoklás |
|---|---|---|---|
| 0289 §1 | lefedett | **GAP** | a `streak_logic_test` és `practice_stats_test` streak-math + stat-aggregációt mér, nem a „felület NEM jelenít meg XP-t" tilalmat |
| 0289 §2 | részben | **kapcsolódó, de nem elégséges** | a `weekly_bars_a11y_test` a11y semantics, nem audit-evidence |
| 0289 §3 | lefedett | **lefedett** (változatlan) | `practice_stats_test:43–55` közvetlenül assertálja az accuracy `null`-t scored run nélkül |
| 0290 §1 | lefedett | **kapcsolódó, de nem elégséges** | a `skill_reframe_test:75–85` UI-elrejtést őriz, nem a nyelvi tilalmat |
| 0290 §2 | lefedett | **kapcsolódó, de nem elégséges** | a `streak_provider_test` csak az idempotencia-részt őrzi, nem a „UI nem számol jutalmat" tilalmat |
| 0290 §3 | lefedett | **kapcsolódó, de nem elégséges** | a `practice_log_race_test` cold-start race-t őriz, nem a konkrét „jutalom-egyenleg csak a főkönyv megerősítése után" tilalmat |
| 0290 §4 | részben | **GAP** | a `weekly_bars_a11y_test` a11y, nem jutalom-audit |

A 0289 §1, 0290 §4 dedikált widget-tesztje a Kör 8-ban kötelező
follow-up; a többi GAP változatlan.

### 12.4 Kötelező gate — lefuttatva, csonkítás nélkül

A §7 szerinti parancs előtérben, csonkítás és láncolás nélkül futtatva:

```
$ tools/round-gate.sh \
    test/features/streak/streak_logic_test.dart \
    test/features/progress/practice_stats_test.dart \
    test/features/streak \
    test/features/progress
```

Eredmény: **MINDEN GATE ZÖLD** — format, analyze, mind a 4 teszt-útvonal,
architecture, secrets, l10n. A részletes kimenet a §10.4 mintára, de
most a javító commit (`e4574c74`) utáni HEAD-en futott.

| Gate | Eredmény |
|---|---|
| `format` | ✅ (1673 fájl, 0 changed) |
| `analyze` | ✅ (No issues found) |
| `test streak_logic_test.dart` | ✅ (10/10) |
| `test practice_stats_test.dart` | ✅ (8/8) |
| `test test/features/streak` | ✅ (20/20) |
| `test test/features/progress` | ✅ (17/17) |
| `architecture` | ✅ (12 allowlisted deviation) |
| `secrets` | ✅ (2962 fájl / 0 finding) |
| `l10n` | ✅ (1405 message) |

A CI-oldali full-suite + property gate + APK dispatch nem e kör dolga
(ADR 0053); az orchestrátor indítja a javító után.

---

## 11. Review — a Claude tölti ki
