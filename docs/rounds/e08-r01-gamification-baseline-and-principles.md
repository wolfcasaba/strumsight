# E08-R01 — Gamification baseline, elvek és audit

- **Státusz:** PREPARED (előre megírva 2026-08-18, kód olvasva: `main @ ea6569fb`)
- **Típus:** Chapter 9 (Epic 8 — Gamification), Kör 1
- **Kör-azonosító:** `E08-R01`
- **Branch:** `<motor>/e08-r01-gamification-baseline-and-principles`
- **Előfeltétel:** `E07-R30` merge-elve (Epic 7 lezárása)
- **Brief szerzője:** Claude (Opus 5)
- **ADR:** nincs — ez a kör nem hoz kötött architekturális döntést.

> ⚠ **Pre-flight (indítás előtt KÖTELEZŐ):** olvasd újra a `lib/features/streak/`, `lib/features/progress/` és `lib/features/learn/` TÉNYLEGES fájllistáját és a `lib/core/storage/storage_keys.dart` kulcsait — a baseline minden állítása mért tény kell legyen, fájlnévvel és sorszámmal. Eltérésnél
> §0.0 brief-revízió, NEM csendes lista-tágítás.

```ai-router
schema_version = 1
risk = "normal"
allowed_paths = [
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
- Új ADR írása: a 0289 és 0290 már kimondta az elveket; a `docs/adr/` TILOS zóna.
- Meglévő teszt átírása vagy törlése.
- A `lib/features/gamification/` fa létrehozása — az a Kör 2 dolga.

## 4. Engedélyezett fájlok

| Útvonal | Indok |
|---|---|
| `docs/baseline/epic-08-start.md` | **ÚJ** — az egyetlen artefaktum, amit ez a kör előállít |
| `docs/rounds/e08-r01-gamification-baseline-and-principles.md` | a §10 handoff és a §0.0 pre-flight revízió |

**Tilos zóna:** `lib/**` (a TELJES alkalmazáskód) · `test/**` · `docs/adr/**` · `docs/sdd/**` · `tools/**` · `.github/**` · `backend/**`

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

A hármas tömören: **alatt** → elutasít · **rajta** → az §6.1 tábla dönti el · **fölött** → elfogad.

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

## 10. Implementation handoff — az implementer tölti ki

## 11. Review — a Claude tölti ki
