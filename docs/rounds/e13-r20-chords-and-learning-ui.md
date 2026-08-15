# E13-R20 — Chord Library, Learning Path és Lesson UI

- **Státusz:** PREPARED (előre megírva 2026-08-15, kód olvasva: `main @ e9a2c8b2`)
- **Típus:** Chapter 13 (UI/UX Design System), Kör 20
- **Kör-azonosító:** `E13-R20`
- **Branch:** `<motor>/e13-r20-chords-and-learning-ui`
- **Előfeltétel:** `E13-R19` merge-elve (tuner/metronóm)
- **Brief szerzője:** Claude (Opus 5)
- **Előre kiosztott ADR:** [`0282`](../adr/0282-diagram-text-alternative-and-handedness.md)
  — **a Claude írja meg a kör indításakor; a `docs/adr/` a TILOS zónában van.**

> ⚠ **Pre-flight (indítás előtt KÖTELEZŐ):** mérd fel a TÉNYLEGES akkord- és
> lecke-domain modelleket (fogásminta, variáció, előfeltétel mezők), valamint a
> meglévő haladás-tárolást — a §5.3 „legacy haladás megmarad" cellája arra
> hivatkozik. Eltérésnél §0.0 revízió.

```ai-router
schema_version = 1
risk = "high"
allowed_paths = [
  "lib/features/chords/",
  "lib/features/learn/",
  "lib/core/design_system/components/music/ss_chord_diagram.dart",
  "lib/core/design_system/public.dart",
  "lib/l10n/app_en.arb",
  "lib/l10n/app_hu.arb",
  "test/features/chords/chord_library_test.dart",
  "test/features/chords/chord_diagram_text_test.dart",
  "test/features/learn/learning_path_test.dart",
  "test/features/learn/lesson_offline_test.dart",
  "docs/rounds/e13-r20-chords-and-learning-ui.md",
]
gate_tests = [
  "test/features/chords/chord_library_test.dart",
  "test/features/chords/chord_diagram_text_test.dart",
  "test/features/learn/learning_path_test.dart",
  "test/features/learn/lesson_offline_test.dart",
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

Az UI-11–UI-14 migrációja közös Learning Mode komponensekre, **balkezes** és
**offline** tartalomtámogatással (SDD Ch13 Kör 20).

## 2. Jelenlegi állapot — mért tények

- Az R11 űrlapelemei (keresés, chip, választó) és az R12 kártyái készen állnak.
- Az R15 lokalizációs kapui élnek — az új szövegek ARB-paritással jönnek.
- Az akkorddiagram grafikus elem: felolvasóval **önmagában néma**.

## 3. Scope

**Benne van:** az akkordtár keresés/szűrés/kedvencek elrendezése · az akkord
részletnézete (diagram, fogás, variációk, gyakorlás-akció) · a tanulási út
**lineáris, hozzáférhető alternatívával** · a lecke részletnézetének készenléti,
előfeltétel-, letöltési és haladás-állapotai · **balkezes** diagram és szöveges
leképezés · hiányzó tartalom / offline / zárolt / migrációs állapotok.

**NINCS benne (tilos):** a tanulási domain-logika vagy az előfeltétel-számítás
módosítása · a haladás-adat sémájának törése · más képernyők migrációja ·
`docs/adr/**`, `tools/**`, `.github/**`.

## 4. Engedélyezett fájlok

| Útvonal | Indok |
|---|---|
| `lib/features/chords/` | az akkordtár UI-ja |
| `lib/features/learn/` | tanulási út + lecke UI |
| `components/music/ss_chord_diagram.dart` | **ÚJ** — diagram + szöveges alternatíva |
| `public.dart` | az export bővítése |
| `lib/l10n/app_{en,hu}.arb` | a tartalmi szövegek |
| `test/features/**` (4) | a §6 cellái |
| `docs/rounds/e13-r20-…md` | a §10 handoff |

**Tilos zóna:** `lib/features/**` a két érintett KIVÉTELÉVEL ·
`lib/core/theme/**` · `docs/adr/**` · `docs/sdd/**` · `tools/**` · `.github/**`.

## 5. Kötött architekturális döntések (ADR 0282)

### 5.1 A diagramnak SZÖVEGES alternatívája van

Az akkorddiagram grafikus információ. Felolvasóval a fogás szöveges leírásként
érhető el („E-húr: üres, A-húr: 2. bund, …"). Enélkül a tartalom vak
felhasználónak nem létezik.

**NEM elfogadható gyengítés:** csak az akkord neve semantics labelként. A név
nem mondja meg, hova kell tenni az ujjakat — pont a lecke lényege veszik el.

### 5.2 A balkezes megjelenítés a SZÖVEGET is tükrözi

Nem elég a rajzot tükrözni: a szöveges leírásnak is a balkezes húrsorrendet
kell követnie, különben a két csatorna ellentmond egymásnak.

### 5.3 A meglévő haladás MEGMARAD

A migráció nem nullázhatja a felhasználó eddigi eredményét. Ez
acceptance-cella (A5).

### 5.4 A zárolás OKA világos

„Zárolva" önmagában zsákutca. Meg kell mondani, mi oldja fel.

### 5.5 A hiányzó offline tartalom NEM omlaszt

Ha egy lecke eszköze nincs letöltve, a képernyő működik, és felajánlja a
letöltést — nem hibaállapotba esik (ADR 0277 §2 szellemében).

### 5.6 A gyakorlás-akció HELYESEN paraméterez

Az akkord részletnézetéből indított gyakorlás azzal az akkorddal indul.
Rossz paraméterezés esetén a felhasználó némán mást gyakorol.

## 6. Acceptance criteria

| # | Kritérium | Bizonyíték |
|---|---|---|
| A1 | A diagramnak szöveges alternatívája van (fogás-leírás) | `chord_diagram_text_test.dart` |
| A2 | Balkezes módban a rajz ÉS a szöveg is tükrözött | ugyanott |
| A3 | A zárolás oka megjelenik | `learning_path_test.dart` |
| A4 | Hiányzó offline eszköz nem omlaszt, letöltést kínál | `lesson_offline_test.dart` |
| A5 | A meglévő haladás megmarad a migráció után | `learning_path_test.dart` |
| A6 | A gyakorlás-akció a megnyitott akkorddal paraméterez | `chord_library_test.dart` |
| A7 | A keresés/szűrés/kedvencek működik és állapota megmarad | ugyanott |
| A8 | A tanulási útnak van lineáris, hozzáférhető alternatívája | `learning_path_test.dart` |

### 6.1 Mérce-mátrix — melyik hibás implementációt melyik cella fogja pirosra

| Hibás implementáció | Melyik cella vált PIROSRA |
|---|---|
| Csak az akkord neve semantics labelként | **A1** |
| Balkezes rajz jobbkezes szöveggel | **A2** |
| „Zárolva" indoklás nélkül | A3 |
| Hiányzó eszköz → hibaállapot | **A4** |
| A haladás nullázódik | **A5** |
| A gyakorlás mindig az első akkorddal indul | **A6** |

**A balkezes leképezés három kötelező cellája** (a küszöb: a kezesség-beállítás):

| Cella | Bemenet | Elvárt |
|---|---|---|
| a küszöb alatt | jobbkezes (alapértelmezett) | a mai húrsorrend, rajz és szöveg egyezik |
| rajta (a küszöbön) | **balkezes bekapcsolva** | rajz **és** szöveg is tükrözött |
| a küszöb fölött | balkezes + képernyőolvasó | a felolvasott sorrend a tükrözöttet követi |

**Valódi-sértés próba (KÖTELEZŐ, §10-ben dokumentálva):** tükrözd csak a rajzot,
a szöveget ne → az **A2** cellának PIROSNAK kell lennie → állítsd vissza.

## 7. Kötelező ellenőrzések

```bash
tools/round-gate.sh test/features/chords/chord_library_test.dart test/features/chords/chord_diagram_text_test.dart test/features/learn/learning_path_test.dart test/features/learn/lesson_offline_test.dart
```

Külön processzek, csonkítatlan kimenet. **Tilos** `| tail`, `| head`,
`&&`-lánc vagy bármilyen szűrés (L09); a `flutter analyze` és `flutter test`
kézi láncolása OOM-ot ad (L05). A kötelező gate-et **TILOS háttérbe küldeni**
(`run_in_background`) — az egy-fordulós harness a forduló végén megöli (L254).

## 8. Implementációs sorrend

1. `ss_chord_diagram.dart` — rajz **és** szöveges alternatíva egy forrásból.
2. A kezesség három cellája.
3. Az akkordtár keresés/szűrés/kedvencek + állapotmegőrzés.
4. Az akkord részletnézete + helyesen paraméterezett gyakorlás-akció.
5. A tanulási út lineáris alternatívával, zárolási okkal.
6. A lecke offline/hiányzó eszköz állapotai.
7. A valódi-sértés próba, §10-be dokumentálva.
8. `tools/round-gate.sh` a §7 szerint.

## 9. Kockázatok

- **A néma diagram.** A rajz elkészül, a szöveges alternatíva marad el, és a
  tanulási tartalom fele hozzáférhetetlen lesz (A1).
- **A félig tükrözött balkezes nézet.** A két csatorna ellentmond, ami rosszabb,
  mint a tükrözés hiánya (A2).
- **A haladás elvesztése.** A migráció legdrágább hibája: a felhasználó
  bizalmát viszi (A5).

## 10. Implementation handoff — az implementer tölti ki

## 11. Review — a Claude tölti ki
