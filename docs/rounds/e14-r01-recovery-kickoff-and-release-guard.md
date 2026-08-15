# E14-R01 — Recovery kickoff, scope freeze és release guard

- **Státusz:** PLANNING (pre-flight lezárva 2026-08-15, `main @ e90edaa2`;
  pre-flight revideálva 2026-08-15, `main @ 344c2fdc` — §0.0 hozzáadva)
- **Típus:** **Chapter 14 program-nyitó kör** (Recognition Accuracy & Useful UI Recovery)
- **Kör-azonosító:** `E14-R01`. Az `E14` a **FEJEZETET** jelöli, nem epicet
  (az epicek E01–E10) — ugyanaz a minta, mint az `E99` governance-pszeudoepic.
- **Branch:** `<motor>/e14-r01-recovery-kickoff-and-release-guard`
- **Előfeltétel:** a Chapter 14 a repóban (`e90edaa2`)
- **Brief szerzője:** Claude (Opus 5)
- **Előre kiosztott ADR:** [`0271`](../adr/0271-recognition-recovery-program.md)
  — **MÁR MEGÍRVA, a `docs/adr/` a TILOS zónában van.**

> ⚠ **KÉT DRIFT a SDD szövegéhez képest — mérve, kötelezően így:**
> 1. A SDD Kör 01 azt írja, hozd létre a `docs/sdd/14-recognition-ui-recovery.md`
>    fájlt. **A fejezet MÁR a repóban van**
>    (`docs/sdd/14-chapter-14-recognition-ui-recovery.md`, `e90edaa2`) — **ne
>    hozd létre újra**, és ne is módosítsd.
> 2. A SDD az `ADR 0213`-at jelöli. **Az foglalt**
>    (`0213-ai-tutor-production-wiring-and-sse-transport.md`); a program ADR-je
>    a `tools/round-slots.py reserve-adr` által adott **0271**.

```ai-router
schema_version = 1
risk = "high"
allowed_paths = [
  "lib/app/config/feature_flags.dart",
  "test/app/config/feature_flags_test.dart",
  "docs/eval/recognition-release-guard.md",
  "docs/rounds/e14-r01-recovery-kickoff-and-release-guard.md",
]
gate_tests = [
  "test/app/config/feature_flags_test.dart",
]
native_gate = false
```

## 0.0 Pre-flight mérési kiegészítés (Claude orchestrátor, 2026-08-15, `main @ 344c2fdc`)

A pre-flight a §1 mérési szabálya szerint kigrepelte a brief két állítását a
tényleges kódból. Mindkettő pontosítást igényel — az alábbi két pont a brief
§2.2/§6.1-ét egészíti ki, nem írja felül:

1. **A `FeatureFlags` bővítésének valójában ÖT helye van, nem négy.** A §2.2
   három helyet nevez (konstruktor, `forEnvironment`, `toString`) + „az `==`
   operátor is" — mérve (`lib/app/config/feature_flags.dart:222-304`): az
   `operator ==` UTÁN van egy ötödik hely, a `hashCode` gettere. Ez egy hat
   mezős `legacyHash`-ből (az eredeti hat flag) és egy `additionalBits`
   `List<bool>`-ból épül, amibe MINDEN `songTrainerV2Enabled` óta felvett flag
   bekerült (lásd a lista utolsó eleme: `analysisTutorIntegrationEnabled`). A
   három új flaget ugyanoda, a lista VÉGÉRE kell felvenni, ugyanabban a
   sorrendben, mint a konstruktorban/`toString`-ben. Ez a Dart
   equals/hashCode-szerződést önmagában nem sérti (két különböző objektum
   ugyanazon hash-sel technikailag megengedett), de megtöri a kódbázis
   következetes mintáját, amit a review MINOR-ként jelezne — olcsóbb most
   felvenni, mint egy javító körben.
2. **A §6.1 „rajta (a küszöbön)" cellája konkrétan: `AppEnvironment.lab`.**
   Az `AppEnvironment` enum (`lib/app/config/app_environment.dart:13-23`)
   pontosan három értéket vesz fel: `development`, `lab`, `production`. A
   §6.1 másik két cellája explicit `production`-t és `development`-et nevez
   meg; az egyetlen fennmaradó, egyik cellában sem szereplő érték a `lab` —
   ez adja a három enumérték teljes lefedettségét. A cella tehát:
   `FeatureFlags.forEnvironment(AppEnvironment.lab, accountEnabled: false)`
   → mindhárom új flag `false`.

Mindkét pont a meglévő teszt-mintát követi
(`test/app/config/feature_flags_test.dart` `group('Practice Generator
feature flags', ...)`) — a három új flagre írj hasonló, önálló csoportot
(pl. `group('Recognition recovery feature flags', ...)`).

## 0. Kör-jelzés és STOP-protokoll

```bash
tools/codex-signal.sh progress "<egy sor>"
tools/codex-signal.sh done "<egy sor>"
tools/codex-signal.sh stopped "<egy sor>"
tools/codex-signal.sh blocked "<egy sor>"
```

Lezáró jelzés nélkül a kör bukott. Listán kívüli fájl → `stopped`.

## 1. Cél

A felismerés-helyreállítási program megnyitása: a rollout-kapcsolók bevezetése
és a release-kapu **dokumentált** követelménye — **felhasználói
viselkedésváltozás nélkül** (SDD Ch14 Kör 01).

## 2. Jelenlegi állapot — mért tények

### 2.1 A probléma, amiért a program indul (a Ch14 mért kiindulása)

A **jelenleg szállított** appról: chord accuracy **67,1%**, onset F1 **67,4%**,
direction **80,7%** — és a Live UI **külön confidence, uncertainty és
signal-quality állapot nélkül** mutat magabiztos chord/arrow kártyákat. A
szállított Chord CRNN **nincs bekötve** a Live primary útba.

A fejezet alapszabálya: **`UNKNOWN > CONFIDENTLY WRONG`**.

### 2.2 A `FeatureFlags` bővítésének HÁROM helye

`lib/app/config/feature_flags.dart`: konstruktor (opcionális, `= false`
default), `factory FeatureFlags.forEnvironment`, és `toString()` — mind a
három tételesen sorolja a flageket. Az `==` operátor is.

**Mérve (E07-R01):** az új, opcionális flagek nem törik el az 51+ meglévő
`FeatureFlags(...)` példányosítást.

### 2.3 A CI-kapu H-GATEGUARD terület

A SDD Kör 01 negyedik feladata a release workflow blokkolása. A `.github/**`
módosítása **emberi döntés** (H-GATEGUARD), **nem implementer-hatáskör** —
lásd §5.4.

## 3. Scope

**Benne van:**

1. Három feature flag: `recognitionRecoveryEnabled`,
   `recognitionShadowModeEnabled`, `newLiveStageEnabled` — **mindhárom
   `false` MINDEN környezetben**.
2. `docs/eval/recognition-release-guard.md` — a release-kapu **követelménye**
   írásban: mit kell teljesítenie egy új felismerési modellnek az aktiválás
   előtt (evaluation report + model manifest + checksum + rollback).
3. A legacy DSP baseline-státuszának rögzítése.

**NINCS benne (tilos):**

- **Bármely flag `true`-ra állítása.**
- **`.github/**` bármilyen módosítása** — H-GATEGUARD (§5.4).
- A `docs/sdd/**` módosítása (a fejezet adott), `docs/adr/**` (az ADR 0271 megírva).
- Bármilyen DSP/ML konstans, modell, `lib/features/**` érintése.
- Új felhasználói viselkedés.

## 4. Engedélyezett fájlok

| Útvonal | Indok |
|---|---|
| `lib/app/config/feature_flags.dart` | a három flag a §2.2 három helyén |
| `test/app/config/feature_flags_test.dart` | a flagek alapértelmezése |
| `docs/eval/recognition-release-guard.md` | **ÚJ** — a kapu követelménye írásban |
| `docs/rounds/e14-r01-…md` | a §10 handoff |

**Tilos zóna:** `.github/**` · `docs/sdd/**` · `docs/adr/**` · `tools/**` ·
`lib/features/**` · `ml/**` · minden modell-asset.

## 5. Kötött architekturális döntések (ADR 0271)

### 5.1 A három flag MINDEN környezetben `false`

Nem `nonProd`. A `forEnvironment` gyár több flaget `nonProd`-ra állít — **ez a
három nem ilyen**. A bekapcsolás külön, mért kapuhoz kötött döntés.

**NEM elfogadható gyengítés:** `nonProd`-ra állítás „hogy fejlesztés közben
látszódjon".

### 5.2 A legacy DSP marad a baseline

A jelenlegi feldolgozás **nem cserélhető** mért A/B report és ADR nélkül. A
program célja a mérés megteremtése, nem az azonnali modellcsere.

### 5.3 A kör NULLA felhasználói viselkedést változtat

Nincs UI-módosítás, nincs modell-aktiválás. Ez acceptance-cella (A5).

### 5.4 A CI-kapu bővítése EMBERI döntés — a kör DOKUMENTÁLJA, nem implementálja

A release-kapu követelményét a `docs/eval/recognition-release-guard.md`
rögzíti. A `.github/workflows/**` tényleges módosítása **H-GATEGUARD**: ha a
kör úgy ítéli, hogy a gate-et most kell bekötni, **`blocked` jelzést ad**, és
nem nyúl hozzá.

**NEM elfogadható gyengítés:** a workflow „csak egy sorral" bővítése.

### 5.5 A kapu-követelmény MÉRHETŐ, nem szándéknyilatkozat

A dokumentum konkrétan megnevezi, mely artefaktum (evaluation report, model
manifest, corpus hash, rollback recept) hiánya blokkolja az aktiválást — hogy
egy későbbi kör gépi ellenőrzést tudjon rá írni.

## 6. Acceptance criteria

| # | Kritérium | Bizonyíték |
|---|---|---|
| A1 | A három flag létezik a konstruktorban, a gyárban, a `toString`-ben és az `==`-ban | `feature_flags_test.dart` |
| A2 | **Mindhárom `false` MINDEN környezetben** | ugyanott — production ÉS nem-production cella |
| A3 | A meglévő `FeatureFlags(...)` hívóhelyek változatlanul fordulnak | `flutter analyze` + teljes suite |
| A4 | A release-guard dokumentum megnevezi a kötelező artefaktumokat | review |
| A5 | **Nulla felhasználói viselkedésváltozás** | `git diff --stat` — nincs `lib/features/**` |
| A6 | A `.github/**` érintetlen | `git diff --stat` |
| A7 | A `docs/sdd/**` és `docs/adr/**` érintetlen | `git diff --stat` |

### 6.1 Mérce-mátrix — melyik hibás implementációt melyik cella fogja pirosra

| Hibás implementáció | Melyik cella vált PIROSRA |
|---|---|
| A flag `nonProd`-ra állítva a gyárban | **A2** (a nem-production cella) |
| A flag kimarad a `toString`/`==`-ból | A1 |
| `required` paraméterként felvéve | A3 |
| A kör hozzányúl a Live UI-hoz | **A5** |
| A workflow „egy sorral" bővítve | **A6** |
| A fejezet-fájl újraírása | A7 |
| A guard-dokumentum csak szándékot fogalmaz meg | A4 |

**A flag-alapértelmezés három kötelező cellája** (a küszöb: a környezet):

| Cella | Bemenet | Elvárt |
|---|---|---|
| a küszöb alatt | `AppEnvironment.production` | mindhárom `false` |
| rajta (a küszöbön) | `forEnvironment` alapértelmezett hívása | mindhárom `false` |
| a küszöb fölött | `AppEnvironment.development` | mindhárom **`false`** — NEM `nonProd` |

**Valódi-sértés próba (KÖTELEZŐ, §10-ben dokumentálva):** állítsd az egyik
flaget `nonProd`-ra → az **A2** nem-production cellájának PIROSNAK kell
lennie → állítsd vissza.

## 7. Kötelező ellenőrzések

```bash
tools/round-gate.sh test/app/config/feature_flags_test.dart
```

Külön processzek, csonkítatlan kimenet. **Tilos** `| tail`, `| head`,
`&&`-lánc vagy bármilyen szűrés (L09); a `flutter analyze` és `flutter test`
kézi láncolása OOM-ot ad (L05). A kötelező gate-et **TILOS háttérbe küldeni**
(`run_in_background`) — az egy-fordulós harness a forduló végén megöli (L254).

## 8. Implementációs sorrend

1. A három flag a konstruktorban (opcionális, `= false`).
2. A gyár, a `toString` és az `==` bővítése.
3. `feature_flags_test.dart` — a §6.1 három környezeti cellája.
4. `docs/eval/recognition-release-guard.md` — mérhető kapu-követelmény.
5. A valódi-sértés próba, §10-be dokumentálva.
6. `tools/round-gate.sh` a §7 szerint.

## 9. Kockázatok

- **A `nonProd` minta másolása.** A gyár sok flaget így állít; a
  copy-paste automatikusan ezt hozná (A2).
- **A CI-kapu megkísértése.** A SDD kéri, de a `.github/**` H-GATEGUARD —
  a kör dokumentál és jelez, nem implementál (A6, §5.4).
- **A scope tágulása a Live UI felé.** A truthfulness hotfix a **Kör 13**;
  itt még nulla viselkedésváltozás a cél (A5).

## 10. Implementation handoff — az implementer tölti ki

**Státusz:** implementálva 2026-08-15 a
`terra/e14-r01-recovery-kickoff-and-release-guard` branchen.

### Módosított fájlok

- `lib/app/config/feature_flags.dart`: három opcionális, alapértelmezetten
  `false` recognition-recovery flag; a gyár mindhárom környezetben explicit
  `false` értéket ad; az `==`, `hashCode` és `toString()` is tartalmazza őket.
- `test/app/config/feature_flags_test.dart`: önálló recognition-recovery
  tesztcsoport konstruktor-defaultra, érték-szemantikára, valamint production,
  lab és development gyárértékre.
- `docs/eval/recognition-release-guard.md`: az aktiválást blokkoló, konkrét
  evaluation report, baseline/candidate manifest, corpus hash és rollback
  recept szerződése; a legacy DSP baseline marad.

### Futtatott ellenőrzések és tényleges eredmények

- RED: `flutter test test/app/config/feature_flags_test.dart` a teszt első
  felvétele után a várt fordítási hibával bukott: a három új named parameter és
  getter még nem létezett.
- GREEN: ugyanaz a célzott teszt a megvalósítás után `7` teszttel,
  `All tests passed!` eredménnyel zárt.
- Valódi-sértés próba: a gyárban ideiglenesen
  `recognitionRecoveryEnabled: nonProd` értékkel futtatott ugyanazon teszt
  várt módon bukott. A lab és development cella `Expected: false`,
  `Actual: <true>` hibát adott; production zöld maradt. A helyes explicit
  `false` visszaállítása után a célzott teszt ismét `7`/`7` zöld.
- `tools/round-gate.sh test/app/config/feature_flags_test.dart` — exit `0`:
  format: `1508 files (0 changed)`; analyze: `No issues found!`; célzott
  teszt: `7`/`7`; architecture: `OK (12 allowlisted deviation(s))`; secret
  scan: `2606 file(s) scanned, 0 finding(s)`; l10n parity: `1276 message(s)`.

### Eltérések, nem futtatott ellenőrzések és scope

- Nincs eltérés a brief scope-jától. Nem módosult `.github/**`, `docs/sdd/**`,
  `docs/adr/**`, `lib/features/**`, DSP/ML konstans vagy modell-asset.
- A teljes Flutter suite, randomizált property gate és CI release evidence nem
  futott lokálisan: ezek a kör utáni CI-dispatch és orchestrátori kapu részei.

## 11. Review — a Claude tölti ki
