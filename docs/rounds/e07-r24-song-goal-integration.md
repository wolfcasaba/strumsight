# E07-R24 — Song goal és Song Trainer integráció

- **Státusz:** PREPARED (előre megírva 2026-08-15, kód olvasva: `main @ 19b30557`)
- **Típus:** Epic 7 (AI Practice Generator), SDD Ch8 Kör 24
- **Kör-azonosító:** `E07-R24`
- **Branch:** `<motor>/e07-r24-song-goal-integration`
- **Előfeltétel:** `E07-R23` merge-elve (végrehajtás)
- **Brief szerzője:** Claude (Opus 5)
- **Előre kiosztott ADR:** nincs — a határokat az ADR 0262 (revíziók,
  hiányzó tartalom) és 0264 (prioritás) rögzíti.

> ⚠ **Pre-flight (indítás előtt KÖTELEZŐ):** mérd meg a Song Trainer
> **tényleges** `public.dart` felületét (szakaszok, hotspotok, revízió) —
> csak azon át olvasható. Eltérésnél §0.0 revízió.

```ai-router
schema_version = 1
risk = "high"
allowed_paths = [
  "lib/features/practice_generator/data/adapter/song_goal_reader_adapter.dart",
  "lib/features/practice_generator/domain/service/song_goal_planner.dart",
  "lib/features/practice_generator/domain/service/song_block_compiler.dart",
  "lib/features/practice_generator/public.dart",
  "test/features/practice_generator/song_goal/song_goal_planner_test.dart",
  "test/features/practice_generator/song_goal/song_goal_reader_adapter_test.dart",
  "docs/rounds/e07-r24-song-goal-integration.md",
]
gate_tests = [
  "test/features/practice_generator/song_goal/song_goal_planner_test.dart",
  "test/features/practice_generator/song_goal/song_goal_reader_adapter_test.dart",
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

Dal- és szakaszcélok beépítése a heti tervbe, előfeltételekkel és céldátummal
(SDD Ch8 Kör 24).

## 2. Jelenlegi állapot — mért tények

- Az R15 ütemezője kezeli a **céldátumhoz igazodó fázisokat**.
- Az R08 katalógusa **csak létező forrásra** mutató jelöltet enged (ADR 0262 §1).
- Az architektúra-őr tiltja a Song Trainer belső importját.

## 3. Scope

**Benne van:** dal-szakaszok és hotspotok olvasása a **publikus** API-n ·
dal-tartomány jelöltek · **alapozás → integráció → szimuláció** fázisok ·
akkord/ritmus előfeltétel-skillhez kötés · hiányzó asset és revízió kezelése ·
a dal-session eredményének normalizálása.

**NINCS benne (tilos):** a Song Trainer módosítása · vision/analyze evidence
(Kör 25) · flag `true`-ra állítása · más feature belső importja ·
`docs/adr/**`, `tools/**`, `.github/**`.

## 4. Engedélyezett fájlok

| Útvonal | Indok |
|---|---|
| `data/adapter/song_goal_reader_adapter.dart` | **ÚJ** — publikus API-n olvas |
| `domain/service/song_goal_planner.dart` | **ÚJ** — fázisok, céldátum |
| `domain/service/song_block_compiler.dart` | **ÚJ** — szakasz → blokk |
| `public.dart` | a barrel bővítése |
| `test/…/song_goal/*_test.dart` (2 db) | a §6 cellái |
| `docs/rounds/e07-r24-…md` | a §10 handoff |

**Tilos zóna:** `lib/features/song_trainer/**` tartalma · `lib/app/**` ·
`docs/adr/**` · `docs/sdd/**` · `tools/**` · `.github/**`.

## 5. Kötött architekturális döntések

### 5.1 A dal NEM nyomhatja el az alap készségeket

A dal-cél a heti terv **egy része**, nem az egésze. A policy felső arányt szab
a dal-blokkokra, hogy az alapkészségek ne sorvadjanak el.

**NEM elfogadható gyengítés:** „a tanuló ezt a dalt akarja, adjunk neki csak
azt". Rövid távon örül, hosszú távon megreked.

### 5.2 A céldátum UTÁN nincs automatikus új blokk

A céldátum elteltével a rendszer **nem** ütemez magától új dal-blokkot —
a tanuló dönt a folytatásról. Enélkül a terv csendben végtelenné válna.

### 5.3 Az előfeltétel-skill ELŐBB jön

Ha a szakasz akkordváltást vagy ritmust igényel, amit a tanuló még nem tud, az
előfeltétel gyakorlása előbb ütemeződik (ADR 0264 §4 prerequisite-boost).

### 5.4 Az UTOLSÓ fázisban nincs indokolatlan ÚJ technika

A szimulációs fázis a meglévő tudás összerakásáról szól. Új technika
bevezetése közvetlenül a céldátum előtt kontraproduktív.

### 5.5 Hiányzó dal/asset: FALLBACK vagy EXPLICIT hiba

Nem csendes kihagyás. Vagy van értelmes helyettesítés, vagy a rendszer
megmondja, mi hiányzik (ADR 0262 §5 mintájára).

## 6. Acceptance criteria

| # | Kritérium | Bizonyíték |
|---|---|---|
| A1 | A dal-blokkok aránya a policy korlátja alatt marad | `song_goal_planner_test.dart` |
| A2 | Céldátum után NINCS automatikus új dal-blokk | ugyanott |
| A3 | Az előfeltétel-skill előbb ütemeződik | ugyanott |
| A4 | Az utolsó fázisban nincs új technika | ugyanott |
| A5 | Hiányzó dal → fallback vagy explicit hiba, nem csend | `song_goal_reader_adapter_test.dart` |
| A6 | Elavult dal-revízió detektált | ugyanott |
| A7 | Az adapter csak a publikus API-t használja | architektúra-őr + diff |
| A8 | A dal-eredmény normalizálása az R23 szabályai szerint | `song_goal_planner_test.dart` |

### 6.1 Mérce-mátrix — melyik hibás implementációt melyik cella fogja pirosra

| Hibás implementáció | Melyik cella vált PIROSRA |
|---|---|
| A dal kitölti a hetet | **A1** |
| Céldátum után is ütemez | **A2** |
| Az előfeltétel a szakasszal együtt vagy utána | A3 |
| Új technika a szimulációs fázisban | A4 |
| Hiányzó dal csendes kihagyása | **A5** |
| Belső import a Song Trainerből | A7 |

**A céldátum három kötelező cellája** (a küszöb: a céldátum):

| Cella | Bemenet | Elvárt |
|---|---|---|
| a küszöb alatt | a céldátum **előtt** | teljes fázis-ütemezés, könnyű ismétlés is |
| rajta (a küszöbön) | **a céldátum napja** | ütemez, de **nincs új technika** (szimulációs fázis) |
| a küszöb fölött | a céldátum **után** | **nincs automatikus** új dal-blokk |

**Valódi-sértés próba (KÖTELEZŐ, §10-ben dokumentálva):** vedd ki a dal-arány
korlátját → az **A1** cellának PIROSNAK kell lennie → állítsd vissza.

## 7. Kötelező ellenőrzések

```bash
tools/round-gate.sh test/features/practice_generator/song_goal/song_goal_planner_test.dart test/features/practice_generator/song_goal/song_goal_reader_adapter_test.dart
```

Külön processzek, csonkítatlan kimenet. **Tilos** `| tail`, `| head`,
`&&`-lánc vagy bármilyen szűrés (L09); a `flutter analyze` és `flutter test`
kézi láncolása OOM-ot ad (L05). A kötelező gate-et **TILOS háttérbe küldeni**
(`run_in_background`) — az egy-fordulós harness a forduló végén megöli (L254).

## 8. Implementációs sorrend

1. `song_goal_reader_adapter.dart` — publikus API, revízió, hiányzó asset.
2. `song_block_compiler.dart` — szakasz → blokk, előfeltétellel.
3. `song_goal_planner.dart` — fázisok, arány-korlát, céldátum-viselkedés.
4. Tesztek a §6.1 három céldátum-cellájával.
5. A valódi-sértés próba, §10-be dokumentálva.
6. `tools/round-gate.sh` a §7 szerint.

## 9. Kockázatok

- **A dal mint egyetlen tartalom.** A tanuló ezt kéri, és fél év múlva egy
  dalt tud, alapok nélkül (A1).
- **A végtelen dal-terv.** Céldátum után is ütemezve a terv sosem zárul (A2).
- **Az új technika a hajrában.** Jó szándékú „még ezt is", és a tanuló a
  koncert előtt bizonytalanodik el (A4).

## 10. Implementation handoff — az implementer tölti ki

## 11. Review — a Claude tölti ki
