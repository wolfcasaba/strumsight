# E13-R21 — Practice setup és aktív session UI

- **Státusz:** PREPARED (előre megírva 2026-08-15, kód olvasva: `main @ e9a2c8b2`)
- **Típus:** Chapter 13 (UI/UX Design System), Kör 21
- **Kör-azonosító:** `E13-R21`
- **Branch:** `<motor>/e13-r21-practice-session-ui`
- **Előfeltétel:** `E13-R20` merge-elve (tanulási felületek)
- **Brief szerzője:** Claude (Opus 5)
- **Előre kiosztott ADR:** nincs — az ADR 0276/0279 érvényes erre a körre.

> ⚠ **Pre-flight (indítás előtt KÖTELEZŐ):** olvasd el a TÉNYLEGES gyakorlási
> állapotgépet (`lib/features/practice/`) — a §5.1 kimondja, hogy a widget nem
> tárol üzleti állapotot, tehát a UI ehhez az állapotgéphez kapcsolódik, nem
> mellé épít. Eltérésnél §0.0 revízió.

```ai-router
schema_version = 1
risk = "high"
allowed_paths = [
  "lib/features/practice/",
  "lib/l10n/app_en.arb",
  "lib/l10n/app_hu.arb",
  "test/features/practice/session/setup_validation_test.dart",
  "test/features/practice/session/session_transitions_test.dart",
  "test/features/practice/session/pause_recovery_test.dart",
  "test/features/practice/session/result_navigation_test.dart",
  "test/fixtures/practice/session/",
  "test/ui/goldens/",
  "docs/rounds/e13-r21-practice-session-ui.md",
]
gate_tests = [
  "test/features/practice/session/setup_validation_test.dart",
  "test/features/practice/session/session_transitions_test.dart",
  "test/features/practice/session/pause_recovery_test.dart",
  "test/features/practice/session/result_navigation_test.dart",
  "test/ui/goldens/e13_r21_screens_golden_test.dart",
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

Az UI-18–UI-20 (gyakorlás-beállítás, aktív session, szünet és helyreállítás)
implementálása az új Stage-, űrlap- és helyreállítás-komponensekkel
(SDD Ch13 Kör 21).

## 2. Jelenlegi állapot — mért tények

- Az R09 StageScaffoldja és transportja, az R11 űrlapelemei és az R13
  megerősítés-rendszere készen állnak.
- A gyakorlási állapotgép **létező** réteg — a UI hozzá kapcsolódik.
- Az ADR 0276 kimondta: a Stage layout nem birtokol erőforrást; a session
  indítása felhasználói szándékra történik.

## 3. Scope

**Benne van:** a beállítási felület (paraméterek, készenlét, engedély) · az
aktív session Stage-elrendezése gyakorlat-specifikus slotokkal · a szünet és
helyreállítás overlay felhasználói és rendszer-megszakítás állapotokkal · a UI
kapcsolása a meglévő állapotgéphez · rossz hangolás, degradált képesség,
gyenge jel és háttérből visszatérés állapotai · **fake órán és motoron**
alapuló determinisztikus tesztek.

**NINCS benne (tilos):** üzleti állapot tárolása widgetben · a gyakorlási
állapotgép vagy a pontozás módosítása · DSP (AGENTS.md §9) · más képernyők ·
`docs/adr/**`, `tools/**`, `.github/**`.

## 4. Engedélyezett fájlok

| Útvonal | Indok |
|---|---|
| `lib/features/practice/` | a három felület migrációja |
| `lib/l10n/app_{en,hu}.arb` | a session-szövegek |
| `test/features/practice/session/*_test.dart` (4) | a §6 cellái |
| `docs/rounds/e13-r21-…md` | a §10 handoff |

**Tilos zóna:** `lib/features/**` a `practice/` KIVÉTELÉVEL ·
`lib/core/design_system/**` · `lib/core/theme/**` · `docs/adr/**` ·
`docs/sdd/**` · `tools/**` · `.github/**`.

## 5. Kötött architekturális döntések

### 5.1 A widget NEM tárol üzleti állapotot

A session állapota az állapotgépé. A widget megjelenít és eseményt küld —
különben két igazságforrás keletkezik, és a háttérből visszatérés után
elcsúsznak.

**NEM elfogadható gyengítés:** „csak a számláló marad a widgetben, az úgyis
egyszerű". A háttérből visszatérés pont ezt nullázza.

### 5.2 A Pause/Resume NEM duplikál eseményt

Ismételt koppintás, rendszer-megszakítás és visszatérés kombinációjából sem
keletkezhet két esemény — az meghamisítaná a gyakorlási statisztikát.

### 5.3 Az eredményre navigálás PONTOSAN EGYSZER történik

Az ADR 0279 §5 mintája: a session lezárása egyetlen navigációt vált ki, akkor
is, ha a lezárás több forrásból érkezik.

### 5.4 A session indítása REPRODUKÁLHATÓ a konfigurációból

Ugyanaz a beállítás ugyanazt a sessiont adja — enélkül a hibák nem
reprodukálhatók, és az eredmények nem összevethetők.

### 5.5 A kilépés adatvesztési következménye VILÁGOS

Az ADR 0279 §1 szerint: a megerősítés kimondja, mi vész el — nem „Igen/Nem".

### 5.6 A UI NEM blokkolja a DSP-t

Nehéz elrendezési munka nem futhat az audio-feldolgozás rovására; a felület
frissítése nem tarthatja fel a feldolgozást.

## 6. Acceptance criteria

| # | Kritérium | Bizonyíték |
|---|---|---|
| A1 | A session ugyanabból a konfigurációból reprodukálható | `setup_validation_test.dart` |
| A2 | A Pause/Resume nem duplikál eseményt | `session_transitions_test.dart` |
| A3 | Az eredményre navigálás pontosan egyszer történik | `result_navigation_test.dart` |
| A4 | A widget nem tárol üzleti állapotot (háttérből visszatérve helyes) | `pause_recovery_test.dart` |
| A5 | A kilépés adatvesztési következménye szövegben megjelenik | `session_transitions_test.dart` |
| A6 | Rossz hangolás / degradált képesség / gyenge jel külön állapot | ugyanott |
| A7 | A beállítás validációja hibás bemenetet nem enged tovább | `setup_validation_test.dart` |
| A8 | Portrait és landscape elrendezésben nincs túlcsordulás | `session_transitions_test.dart` |
| A9 | A kör §3-ban megnevezett MINDEN képernyőről golden-felvétel készül és be van commitolva — 412×915 compact portrait ÉS `textScaleFactor: 2.0` | `e13_r21_screens_golden_test.dart` + a `test/ui/goldens/*.png` a diffben |

### 6.1 Mérce-mátrix — melyik hibás implementációt melyik cella fogja pirosra

| Hibás implementáció | Melyik cella vált PIROSRA |
|---|---|
| A számláló a widget állapotában | **A4** |
| A Resume új „session indult" eseményt küld | **A2** |
| A lezárás két forrásból kétszer navigál | **A3** |
| A konfiguráció egy mezője nem kerül át | A1 |
| „Biztos vagy benne? Igen/Nem" kilépéskor | **A5** |
| A gyenge jel és a rossz hangolás összevonva | A6 |
| A képernyő elcsúszik, túlcsordul vagy nagy szövegméretnél olvashatatlan | **A9** |

**Az eredmény-navigáció három kötelező cellája** (a küszöb: hányszor futhat):

| Cella | Bemenet | Elvárt |
|---|---|---|
| a küszöb alatt | a session megszakad mentés nélkül | **0** navigáció az eredményre |
| rajta (a küszöbön) | egyszeri lezárás | **pontosan 1** navigáció |
| a küszöb fölött | lezárás + a rendszer is lezárja (kettős forrás) | **pontosan 1** navigáció |

**Valódi-sértés próba (KÖTELEZŐ, §10-ben dokumentálva):** tedd a session
számlálóját a widget állapotába → az **A4** cellának PIROSNAK kell lennie →
állítsd vissza.

## 7. Kötelező ellenőrzések

```bash
tools/round-gate.sh test/features/practice/session/setup_validation_test.dart test/features/practice/session/session_transitions_test.dart test/features/practice/session/pause_recovery_test.dart test/features/practice/session/result_navigation_test.dart test/ui/goldens/e13_r21_screens_golden_test.dart
```

**A golden-felvétel (A9) rögzítése — a mérce ÚJ, nem alku tárgya:** a képernyő
minden állapotát NEM kell felvenni, a §3 szerinti alap-nézet elég, de a két
keret (412×915 compact portrait és ugyanaz `textScaleFactor: 2.0` mellett)
KÖTELEZŐ. Minta és futó precedens: `test/features/live/chord_timeline_golden_test.dart`
(valódi kapu, nem `skip`-elt rögzítő). Előállítás:

```bash
~/flutter/bin/flutter test --update-goldens test/ui/goldens/e13_r21_screens_golden_test.dart
```

A keletkezett PNG-ket **commitolni kell** — enélkül az A9 nem teljesült. A
márkabetűtípusok a teszt-hostban nem töltődnek be (fallback face); ez a
meglévő golden-teszt mért viselkedése, az elrendezést, méretezést és színeket
nem érinti. MIÉRT ez a kör dolga és nem az E13-R36-é: a záró vizuális
regressziós kör csak azt tudja megmondani, hogy valami MEGVÁLTOZOTT — azt,
hogy a képernyő eleve csúnya-e, a saját körében kell látni.

Külön processzek, csonkítatlan kimenet. **Tilos** `| tail`, `| head`,
`&&`-lánc vagy bármilyen szűrés (L09); a `flutter analyze` és `flutter test`
kézi láncolása OOM-ot ad (L05). A kötelező gate-et **TILOS háttérbe küldeni**
(`run_in_background`) — az egy-fordulós harness a forduló végén megöli (L254).

## 8. Implementációs sorrend

1. A beállítási felület + validáció + reprodukálhatósági cella.
2. Az aktív session Stage-elrendezése, az állapotgéphez kapcsolva.
3. A szünet/helyreállítás overlay, felhasználói és rendszer-megszakítással.
4. A Pause/Resume esemény-duplikáció cellája.
5. Az eredmény-navigáció három cellája.
6. A kilépési megerősítés következmény-központú szövege.
7. A valódi-sértés próba, §10-be dokumentálva.
8. `tools/round-gate.sh` a §7 szerint.

## 9. Kockázatok

- **A widgetbe szivárgó állapot.** „Csak egy számláló" — és a háttérből
  visszatérés után hamis eredményt ad (A4).
- **A kettős lezárás.** Ritka, de duplikált eredményt vagy dupla navigációt
  okoz (A3).
- **Az elnagyolt kilépési szöveg.** A gyakorlás közbeni véletlen kilépés a
  leggyakoribb adatvesztési út (A5).

## 10. Implementation handoff — az implementer tölti ki

## 11. Review — a Claude tölti ki
