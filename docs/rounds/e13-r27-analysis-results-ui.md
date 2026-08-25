# E13-R27 — Analysis Overview, Timeline, Metric és Compare UI

- **Státusz:** PREPARED (előre megírva 2026-08-15, kód olvasva: `main @ c732ec75`)
- **Típus:** Chapter 13 (UI/UX Design System), Kör 27
- **Kör-azonosító:** `E13-R27`
- **Branch:** `<motor>/e13-r27-analysis-results-ui`
- **Előfeltétel:** `E13-R26` merge-elve (felvétel és feldolgozás)
- **Brief szerzője:** Claude (Opus 5)
- **Előre kiosztott ADR:** [`0286`](../adr/0286-charts-need-a-text-alternative.md)
  — **a Claude írja meg a kör indításakor; a `docs/adr/` a TILOS zónában van.**

> ⚠ **Pre-flight (indítás előtt KÖTELEZŐ):** olvasd el az elemzési eredmény
> TÉNYLEGES szerkezetét (verzió, mérőszámok, hiányzó/nem támogatott jelölés),
> mert a §5.1 „hiányzó metrika nem 0" cella a mért mezőkre épül. Eltérésnél
> §0.0 revízió.

```ai-router
schema_version = 1
risk = "high"
allowed_paths = [
  "lib/features/analyze/results/",
  "lib/core/design_system/components/analytics/",
  "lib/core/design_system/public.dart",
  "lib/l10n/base/app_en.arb",
  "lib/l10n/base/app_hu.arb",
  "lib/l10n/app_en.arb",
  "lib/l10n/app_hu.arb",
  "test/features/analyze/results/metric_missing_test.dart",
  "test/features/analyze/results/timeline_virtualization_test.dart",
  "test/features/analyze/results/chart_semantics_test.dart",
  "test/features/analyze/results/compare_compatibility_test.dart",
  "test/fixtures/analyze/results/",
  "test/ui/goldens/",
  "docs/rounds/e13-r27-analysis-results-ui.md",
]
gate_tests = [
  "test/features/analyze/results/metric_missing_test.dart",
  "test/features/analyze/results/timeline_virtualization_test.dart",
  "test/features/analyze/results/chart_semantics_test.dart",
  "test/features/analyze/results/compare_compatibility_test.dart",
  "test/ui/goldens/e13_r27_screens_golden_test.dart",
]
native_gate = false
```

## 0.0 BRIEF-REVÍZIÓ — 2026-08-25, batch pre-flight (E13-R17…R35)

A brief 2026-08-15-én készült; ez a pre-flight `main @ 41fbd40` ellen mért.
**Visszakeresett előzmény:** [L478](../LESSONS.md) (a pre-flight csak szűkíthet;
a tágítás H3), [ADR 0307 §4](../adr/0307-parallel-round-execution.md) (a
`lib/l10n/app_*.arb` GENERÁLT aggregátum, a forrás a `base/` és a
`features/` szegmens), [L481](../LESSONS.md) (a lánc remote konténerből nem
indítható). A hibaosztályt a **teljes Ch13 sávon** mérte ki egy batch-vizsgálat:
az R17–R35 MIND a generált aggregátumot sorolta fel forrásként (`agg=2, frag=0`).

**Kockázat = high, indoklás:** az elemzési eredmények a felhasználó felvételéből származó adatot jelenítik meg és exportálhatóvá teszik.

### R1 — `lib/l10n/app_{en,hu}.arb` GENERÁLT aggregátum → a FORRÁS a szegmens

A kör fájából `lib/features/analyze/results/` **még nem létezik** — a képernyőket ez a kör hozza létre, tehát MINDEN szövege új.

A kör ezért **nem tudott volna egyetlen szöveget sem írni** a saját listáján
belül. Feloldás — H3 lista-tágítás, **user-engedéllyel (2026-08-25)**, a
lehető legszűkebb alakban:

- `analyze` → nincs saját fragmentuma, a kulcsai a `base/app_*.arb` szegmensben élnek

Az aggregátum a listán MARAD, de **kizárólag generált kimenetként**
(`dart run tool/gen_l10n_segments.dart --write`); a merge-elt precedens
egységesen a forrást ÉS a regenerált aggregátumot is commitolja (E09-R26
`df0ad3dd`, E13-R12 `376b8a1d`, E13-R10 `b11ab2ed`). **Új fragmentum NEM
készül**, ezért a `test/l10n/arb_parity_test.dart` beégetett szegmens-listáját
sem kell bővíteni — a felvett források mind szerepelnek benne.

### R2 — a kör SAJÁT feature-fáján élő, ma zöld widget-tesztek (FELVÉVE)

Ezek közvetlenül a migrálandó képernyőkre állítanak, tehát a migráció után
pirosra váltanának, ami a §0 szerint `blocked` lenne:

  - nincs ilyen.

**A jogosultság szűk:** a teszteket az ÚJ widgetekre kell ráállítani. A lefedett
viselkedést gyengíteni, cellát törölni vagy `skip`-elni **TILOS** — az a mérce
meggyengítése, amit a gate-guard emberhez eszkalál.

### R3 — keresztmetszeti tesztek (NEM kerültek listára — figyelmeztetés)

A kör fájára hivatkozó további widget-tesztek közös infrastruktúrán élnek
(`test/app/**`, `test/core/**`, más feature-ek fái) — nincs ilyen. Ezeket a kör
**NEM** szerkesztheti: ha egy elbukik, az `blocked` jelzés és célzott
brief-revízió, nem csendes átírás. A körbe húzásuk a scope-fegyelem feladása
lenne.

## 0. Kör-jelzés és STOP-protokoll

```bash
tools/codex-signal.sh progress "<egy sor>"
tools/codex-signal.sh done "<egy sor>"
tools/codex-signal.sh stopped "<egy sor>"
tools/codex-signal.sh blocked "<egy sor>"
```

Lezáró jelzés nélkül a kör bukott. Listán kívüli fájl → `stopped`.

## 1. Cél

Az UI-37–UI-39 Studio Analytics rendszere **confidence-tudatos**, virtualizált
és hozzáférhető adatvizualizációval (SDD Ch13 Kör 27).

## 2. Jelenlegi állapot — mért tények

- Az R12 mérőszám-kártyái és badge-ei, az R26 feldolgozási felülete készen áll.
- Az ADR 0283 kimondta: az eredmény nem állít többet, mint amit mértünk — ez a
  kör ennek vizualizációs oldala.
- A felvételek hosszúak lehetnek: az idővonalnak **virtualizáltnak** kell lennie.

## 3. Scope

**Benne van:** pontszám-gyűrű, mérőszám-kártya, trend, confidence-jelmagyarázat
és insight komponensek · az áttekintő összegzés-központú elrendezése részleges
és nem támogatott mérőszám-állapotokkal · **virtualizált** idővonal, hullámforma,
átfedés, kijelölés és esemény-vizsgáló · a mérőszám részletnézete és a
session-összehasonlítás **kompatibilitási szabályai** · diagram-szöveg-összegzés
és esemény-lista alternatíva · nagy fixture-ös teljesítmény- és görgetés-teszt.

**NINCS benne (tilos):** az elemzési logika vagy a mérőszám-számítás módosítása ·
DSP (AGENTS.md §9) · a felvétel/feldolgozás (Kör 26) · `docs/adr/**`,
`tools/**`, `.github/**`.

## 4. Engedélyezett fájlok

| Útvonal | Indok |
|---|---|
| `analyze/results/` | az eredmény-felületek |
| `design_system/components/analytics/` | **ÚJ** — diagram-komponensek |
| `public.dart` | az export bővítése |
| `lib/l10n/base/app_{en,hu}.arb` | **FORRÁS** — a mérőszám-szövegek (a kör feature-ei még nem migráltak, a kulcsaik itt élnek) |
| `lib/l10n/app_{en,hu}.arb` | **CSAK GENERÁLT KIMENET** — kizárólag `dart run tool/gen_l10n_segments.dart --write`, kézzel írni TILOS |
| `test/features/analyze/results/*_test.dart` (4) | a §6 cellái |
| `docs/rounds/e13-r27-…md` | a §10 handoff |

**Tilos zóna:** `lib/features/analyze/` a `results/` KIVÉTELÉVEL ·
`lib/core/theme/**` · `docs/adr/**` · `docs/sdd/**` · `tools/**` · `.github/**`.

## 5. Kötött architekturális döntések (ADR 0286)

### 5.1 A hiányzó mérőszám NEM nulla

A „nincs adat" és a „nulla" két különböző dolog. Nullaként megjelenítve a
felhasználó rossz teljesítménynek olvassa azt, amit meg sem mértünk.

**NEM elfogadható gyengítés:** `?? 0` a mérőszám megjelenítésénél. Ez a
projekt legveszélyesebb hibaosztálya: magabiztos, hamis állítás.

### 5.2 Minden diagramnak van SZÖVEGES összegzése

Grafikon önmagában felolvasóval néma (az ADR 0282 elve az adatvizualizációra).
A szöveges összegzés a trendet és a szélsőértékeket mondja ki, az esemény-lista
pedig bejárható alternatíva.

### 5.3 A confidence LÁTHATÓ a mérőszám mellett

Nem elég a számot mutatni: mellette látszik, mennyire megbízható.

### 5.4 Az idővonal VIRTUALIZÁLT

Hosszú felvételnél is használható marad. Ez acceptance-cella (A4), nem
optimalizációs törekvés.

### 5.5 Az összehasonlítás CSAK kompatibilis adat között

Eltérő eredmény-verziók vagy nem összemérhető mérőszámok között a felület nem
kínál összehasonlítást — és megmondja, miért nem.

**NEM elfogadható gyengítés:** „a közös mezőket úgyis össze lehet hasonlítani".
Eltérő számítási alap mellett az összevetés félrevezet.

### 5.6 A kijelölésből INDÍTHATÓ gyakorlás

A nehéz szakasz kijelölése után a gyakorlás helyesen paraméterezve indul.

## 6. Acceptance criteria

| # | Kritérium | Bizonyíték |
|---|---|---|
| A1 | A hiányzó mérőszám NEM nullaként jelenik meg | `metric_missing_test.dart` |
| A2 | A nem támogatott mérőszám külön állapot, indoklással | ugyanott |
| A3 | A confidence minden mérőszám mellett látható | ugyanott |
| A4 | Az idővonal nagy fixture mellett is virtualizált és használható | `timeline_virtualization_test.dart` |
| A5 | Minden diagramnak van szöveges összegzése és esemény-lista alternatívája | `chart_semantics_test.dart` |
| A6 | Az összehasonlítás csak kompatibilis adat között indul | `compare_compatibility_test.dart` |
| A7 | Az inkompatibilitás oka megjelenik | ugyanott |
| A8 | A kijelölésből indított gyakorlás helyesen paraméterez | `timeline_virtualization_test.dart` |
| A9 | A kör §3-ban megnevezett MINDEN képernyőről golden-felvétel készül és be van commitolva — 412×915 compact portrait ÉS `textScaleFactor: 2.0` | `e13_r27_screens_golden_test.dart` + a `test/ui/goldens/*.png` a diffben |

### 6.1 Mérce-mátrix — melyik hibás implementációt melyik cella fogja pirosra

| Hibás implementáció | Melyik cella vált PIROSRA |
|---|---|
| `?? 0` a hiányzó mérőszámra | **A1** |
| A nem támogatott mérőszám elrejtve | A2 |
| A confidence csak az áttekintőben | A3 |
| Az egész idővonal egyszerre renderelve | **A4** |
| Diagram szöveges összegzés nélkül | **A5** |
| Eltérő verziójú eredmények összevetése | **A6** |
| A képernyő elcsúszik, túlcsordul vagy nagy szövegméretnél olvashatatlan | **A9** |

**A mérőszám-megjelenítés három kötelező cellája** (a küszöb: van-e mért érték):

| Cella | Bemenet | Elvárt |
|---|---|---|
| a küszöb alatt | nincs mérés (hiányzó/nem támogatott) | **„nincs adat"** — soha nem 0 |
| rajta (a küszöbön) | mért érték, alacsony megbízhatósággal | az érték **confidence-jelöléssel** |
| a küszöb fölött | mért érték, magas megbízhatósággal | az érték normál jelöléssel |

**Valódi-sértés próba (KÖTELEZŐ, §10-ben dokumentálva):** írj `?? 0`-t a
hiányzó mérőszám megjelenítésébe → az **A1** cellának PIROSNAK kell lennie →
állítsd vissza.

## 7. Kötelező ellenőrzések

```bash
tools/round-gate.sh test/features/analyze/results/metric_missing_test.dart test/features/analyze/results/timeline_virtualization_test.dart test/features/analyze/results/chart_semantics_test.dart test/features/analyze/results/compare_compatibility_test.dart test/ui/goldens/e13_r27_screens_golden_test.dart
```

**A golden-felvétel (A9) rögzítése — a mérce ÚJ, nem alku tárgya:** a képernyő
minden állapotát NEM kell felvenni, a §3 szerinti alap-nézet elég, de a két
keret (412×915 compact portrait és ugyanaz `textScaleFactor: 2.0` mellett)
KÖTELEZŐ. Minta és futó precedens: `test/features/live/chord_timeline_golden_test.dart`
(valódi kapu, nem `skip`-elt rögzítő). Előállítás:

```bash
~/flutter/bin/flutter test --update-goldens test/ui/goldens/e13_r27_screens_golden_test.dart
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

1. Az analitika-komponensek (pontszám-gyűrű, mérőszám-kártya, trend,
   confidence-jelmagyarázat).
2. A mérőszám-megjelenítés három cellája — hiányzó ≠ nulla.
3. Az áttekintő összegzés-központú elrendezése.
4. A virtualizált idővonal + nagy fixture-ös cella.
5. Diagram-szöveg-összegzés és esemény-lista alternatíva.
6. Az összehasonlítás kompatibilitási szabályai + indoklás.
7. A valódi-sértés próba, §10-be dokumentálva.
8. `tools/round-gate.sh` a §7 szerint.

## 9. Kockázatok

- **A `?? 0` reflex.** Egyetlen karakternyi kényelem, és a felhasználó rossz
  eredménynek olvassa a hiányzó mérést (A1).
- **A nem virtualizált idővonal.** Rövid teszt-fixture-rel nem látszik, hosszú
  felvételen használhatatlan (A4).
- **A „közös mezők" összevetése.** Logikusnak tűnik, és eltérő számítási alap
  mellett félrevezet (A6).

## 10. Implementation handoff — az implementer tölti ki

## 11. Review — a Claude tölti ki
