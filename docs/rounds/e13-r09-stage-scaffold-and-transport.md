# E13-R09 — StageScaffold és session transport

- **Státusz:** PREPARED (előre megírva 2026-08-15, kód olvasva: `main @ 93a6c19a`)
- **Típus:** Chapter 13 (UI/UX Design System), Kör 9
- **Kör-azonosító:** `E13-R09`
- **Branch:** `<motor>/e13-r09-stage-scaffold-and-transport`
- **Előfeltétel:** `E13-R08` merge-elve (adaptive scaffold)
- **Brief szerzője:** Claude (Opus 5)
- **Előre kiosztott ADR:** [`0276`](../adr/0276-stage-scaffold-owns-no-resources.md)
  — **a Claude írja meg a kör indításakor; a `docs/adr/` a TILOS zónában van.**

> ⚠ **Pre-flight (indítás előtt KÖTELEZŐ):** mérd fel, MELYIK réteg birtokolja
> ma a mikrofon/kamera életciklust (`lib/features/**` alatt), mert az §5.1
> kimondja: a Stage layout NEM veheti át. Eltérésnél §0.0 revízió.

```ai-router
schema_version = 1
risk = "high"
allowed_paths = [
  "lib/core/design_system/layouts/ss_stage_scaffold.dart",
  "lib/core/design_system/components/music/ss_session_transport.dart",
  "lib/core/design_system/public.dart",
  "test/core/design_system/stage/ss_stage_scaffold_test.dart",
  "test/core/design_system/stage/ss_session_transport_test.dart",
  "test/core/design_system/stage/stage_back_confirmation_test.dart",
  "docs/rounds/e13-r09-stage-scaffold-and-transport.md",
]
gate_tests = [
  "test/core/design_system/stage/ss_stage_scaffold_test.dart",
  "test/core/design_system/stage/ss_session_transport_test.dart",
  "test/core/design_system/stage/stage_back_confirmation_test.dart",
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

Közös, **életciklus-semleges** Stage layout a Live, Practice, Song, Tuner,
Metronome és Vision aktív állapotához (SDD Ch13 Kör 9).

## 2. Jelenlegi állapot — mért tények

- Az R08 bevezette, hogy Stage route alatt nincs primary navigation — ez a kör
  tölti meg tartalommal a Stage felületet.
- A hat aktív mód ma külön-külön oldja meg a fejlécet, a transportot és a
  biztonságos területet.
- A Ch13 §9.9 megadja a slot-szerkezetet: status header, hero, feedback,
  timeline/beat, bottom action.

## 3. Scope

**Benne van:** `SsStageScaffold` — safe area, orientáció, képernyő-ébrentartás
**kérése**, primary-nav-mentes szerkezet · `SsSessionTransport` idle /
count-in / active / paused / finishing / disabled állapotokkal · az öt slot
API-ja · portrait / landscape / expanded elrendezés · a mentetlen session
vissza-megerősítés **hookja** (callback, nem logika) · high contrast és 2.0
text scale.

**NINCS benne (tilos):** **erőforrás-kezelés a widgetben** — mikrofon, kamera,
felvétel indítása/leállítása · DSP vagy időzítés (AGENTS.md §9) ·
`lib/features/**` · `lib/core/theme/**` · `docs/adr/**`, `tools/**`,
`.github/**`.

## 4. Engedélyezett fájlok

| Útvonal | Indok |
|---|---|
| `layouts/ss_stage_scaffold.dart` | **ÚJ** — a Stage váz |
| `components/music/ss_session_transport.dart` | **ÚJ** — a transport |
| `public.dart` | az export bővítése |
| `test/…/stage/*_test.dart` (3) | a §6 cellái |
| `docs/rounds/e13-r09-…md` | a §10 handoff |

**Tilos zóna:** `lib/features/**` · `lib/core/theme/**` · `lib/app/**` ·
`docs/adr/**` · `docs/sdd/**` · `tools/**` · `.github/**`.

## 5. Kötött architekturális döntések (ADR 0276)

### 5.1 A StageScaffold NEM indít mikrofont, kamerát vagy felvételt

Prezentációs réteg. Az erőforrás-életciklus a feature-é marad — különben a
layout beépítése bárhol csendben engedélykérést és felvételt indítana.

**NEM elfogadható gyengítés:** „a kényelem kedvéért a scaffold indítja a
mikrofont, ha kap egy `autoStart` flaget". Az egy UI-komponensbe rejtett
adatgyűjtés.

### 5.2 A Pause és a Finish MINDIG látható aktív session alatt

Nem rejthető el görgetés, overflow menü vagy „elegánsabb elrendezés" mögé. Aki
játszik, egyetlen mozdulattal meg tud állni.

**NEM elfogadható gyengítés:** a Finish áthelyezése overflow menübe helyhiány
miatt. Landscape-ben ez pont a leggyakoribb helyzet.

### 5.3 A vissza-megerősítés HOOK, nem beépített párbeszéd

A scaffold jelzi, hogy adatvesztés fenyeget, és a feature dönt a szövegről és a
mentésről. Az adatvesztés-tény ismerete a feature-é.

### 5.4 Landscape-ben nincs túlcsordulás

A hat mód közül több landscape-ben használatos (Stage a gitár mellett). Ez
acceptance-cella (A4).

### 5.5 A képernyő-ébrentartás KÉRÉS, és visszavonódik

A scaffold kéri, de nem birtokolja: az elhagyáskor a kérés megszűnik.

## 6. Acceptance criteria

| # | Kritérium | Bizonyíték |
|---|---|---|
| A1 | A scaffold NEM indít mikrofont/kamerát/felvételt | `ss_stage_scaffold_test.dart` + `grep` a diffben |
| A2 | Pause és Finish minden aktív állapotban látható | `ss_session_transport_test.dart` |
| A3 | A hat transport-állapot mindegyike megkülönböztethető | ugyanott |
| A4 | Landscape-ben és 2.0 text scale mellett nincs túlcsordulás | `ss_stage_scaffold_test.dart` |
| A5 | A rendszer-vissza adatvesztésnél a hookot hívja, pontosan egyszer | `stage_back_confirmation_test.dart` |
| A6 | Stage alatt nincs primary navigation | `ss_stage_scaffold_test.dart` |
| A7 | A képernyő-ébrentartás kérése elhagyáskor visszavonódik | ugyanott |
| A8 | A semantics sorrend a vizuális sorrendet követi | `ss_stage_scaffold_test.dart` |

### 6.1 Mérce-mátrix — melyik hibás implementációt melyik cella fogja pirosra

| Hibás implementáció | Melyik cella vált PIROSRA |
|---|---|
| `autoStart` a scaffoldban, ami mikrofont nyit | **A1** |
| A Finish overflow menübe kerül | **A2** |
| A paused és az active vizuálisan azonos | A3 |
| Fix magasságú Stage fejléc | **A4** |
| A vissza-hook kétszer hív | **A5** |
| Az ébrentartás bent ragad kilépés után | A7 |

**A vissza-megerősítés három kötelező cellája** (a küszöb: van-e mentetlen adat):

| Cella | Bemenet | Elvárt |
|---|---|---|
| a küszöb alatt | nincs mentetlen adat | a hook **nem hívódik**, a vissza azonnal működik |
| rajta (a küszöbön) | van mentetlen adat, a feature megerősít | a hook **pontosan egyszer** hívódik, a kilépés megtörténik |
| a küszöb fölött | van mentetlen adat, a feature elutasít | a hook egyszer hívódik, a kilépés **elmarad** |

**Valódi-sértés próba (KÖTELEZŐ, §10-ben dokumentálva):** tedd a Finish gombot
overflow menübe → az **A2** cellának PIROSNAK kell lennie → állítsd vissza.

## 7. Kötelező ellenőrzések

```bash
tools/round-gate.sh test/core/design_system/stage/ss_stage_scaffold_test.dart test/core/design_system/stage/ss_session_transport_test.dart test/core/design_system/stage/stage_back_confirmation_test.dart
```

Külön processzek, csonkítatlan kimenet. **Tilos** `| tail`, `| head`,
`&&`-lánc vagy bármilyen szűrés (L09); a `flutter analyze` és `flutter test`
kézi láncolása OOM-ot ad (L05). A kötelező gate-et **TILOS háttérbe küldeni**
(`run_in_background`) — az egy-fordulós harness a forduló végén megöli (L254).

## 8. Implementációs sorrend

1. `ss_stage_scaffold.dart` — slotok, safe area, orientáció, ébrentartás-kérés.
2. `ss_session_transport.dart` — a hat állapot.
3. A vissza-hook + a három cellája.
4. Landscape és 2.0 text scale cellák.
5. Semantics sorrend.
6. A valódi-sértés próba, §10-be dokumentálva.
7. `tools/round-gate.sh` a §7 szerint.

## 9. Kockázatok

- **Az erőforrás-kezelés becsúszása.** Kényelmes lenne a layoutból indítani, és
  ettől bárhol elhelyezve mikrofont nyitna (A1).
- **A helyhiányos landscape.** A Finish elrejtése ilyenkor kézenfekvő és
  pontosan a legrosszabb (A2/A4).
- **A kétszer hívott vissza-hook.** Duplán megjelenő párbeszédet ad, amit
  kézzel nehéz észrevenni (A5).

## 10. Implementation handoff — az implementer tölti ki

## 11. Review — a Claude tölti ki
