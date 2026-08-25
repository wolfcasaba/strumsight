# E13-R31 — Progress Dashboard és Skill Detail UI

- **Státusz:** PREPARED (előre megírva 2026-08-15, kód olvasva: `main @ 0f7afd9a`)
- **Típus:** Chapter 13 (UI/UX Design System), Kör 31
- **Kör-azonosító:** `E13-R31`
- **Branch:** `<motor>/e13-r31-progress-and-skills`
- **Előfeltétel:** `E13-R30` merge-elve (vision UI)
- **Brief szerzője:** Claude (Opus 5)
- **Előre kiosztott ADR:** [`0289`](../adr/0289-mastery-is-evidence-not-xp.md)
  — **a Claude írja meg a kör indításakor; a `docs/adr/` a TILOS zónában van.**

> ⚠ **Pre-flight (indítás előtt KÖTELEZŐ):** olvasd el a TÉNYLEGES haladás- és
> mérőszám-modelleket, kiemelten a **verziózást** — a §5.5 migrációs cella a
> mért verzió-mezőre épül. Eltérésnél §0.0 revízió.

```ai-router
schema_version = 1
risk = "high"
allowed_paths = [
  "lib/features/progress_v2/",
  "lib/l10n/base/app_en.arb",
  "lib/l10n/base/app_hu.arb",
  "lib/l10n/app_en.arb",
  "lib/l10n/app_hu.arb",
  "test/features/progress_v2/dashboard_states_test.dart",
  "test/features/progress_v2/mastery_evidence_test.dart",
  "test/features/progress_v2/metric_migration_test.dart",
  "test/features/progress_v2/chart_semantics_test.dart",
  "test/ui/goldens/",
  "docs/rounds/e13-r31-progress-and-skills.md",
]
gate_tests = [
  "test/features/progress_v2/dashboard_states_test.dart",
  "test/features/progress_v2/mastery_evidence_test.dart",
  "test/features/progress_v2/metric_migration_test.dart",
  "test/features/progress_v2/chart_semantics_test.dart",
  "test/ui/goldens/e13_r31_screens_golden_test.dart",
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

**Kockázat = high, indoklás:** a fejlődési felület a felhasználó teljes tanulási történetét (személyes adat) aggregálja.

### R1 — `lib/l10n/app_{en,hu}.arb` GENERÁLT aggregátum → a FORRÁS a szegmens

A kör fájából `lib/features/progress_v2/` **még nem létezik** — a képernyőket ez a kör hozza létre, tehát MINDEN szövege új.

A kör ezért **nem tudott volna egyetlen szöveget sem írni** a saját listáján
belül. Feloldás — H3 lista-tágítás, **user-engedéllyel (2026-08-25)**, a
lehető legszűkebb alakban:

- `progress_v2` → nincs saját fragmentuma, a kulcsai a `base/app_*.arb` szegmensben élnek

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

Az UI-49–UI-50 hosszú távú, **bizonyíték-alapú** fejlődési felülete
(SDD Ch13 Kör 31).

## 2. Jelenlegi állapot — mért tények

- Az R27 analitika-komponensei és az ADR 0286 („hiányzó ≠ nulla", diagram
  szöveges alternatívája) készen állnak.
- A mérőszámok **verziózottak** — a régi és az új nem feltétlenül összemérhető.
- Az R17 Profile Hub adja a belépési pontot.

## 3. Scope

**Benne van:** a fejlődési áttekintő új felhasználó / trend / offline /
migráció állapotai · a képesség részletnézete (elsajátítottság, előfeltétel,
**bizonyíték**, következő lépés) · időtáv-, cél- és export-vezérlők ·
diagram-összegzés és a képesség-gráf **lineáris** hozzáférhető alternatívája ·
a bizonyíték-hivatkozások a megfelelő session route-ra · mérőszám-verzió
migráció és elégtelen adat állapotai.

**NINCS benne (tilos):** a haladás- vagy elsajátítottság-számítás módosítása ·
XP-alapú elsajátítottság bevezetése · más képernyők · `docs/adr/**`,
`tools/**`, `.github/**`.

## 4. Engedélyezett fájlok

| Útvonal | Indok |
|---|---|
| `lib/features/progress_v2/` | a két felület |
| `lib/l10n/base/app_{en,hu}.arb` | **FORRÁS** — a fejlődés-szövegek (a kör feature-ei még nem migráltak, a kulcsaik itt élnek) |
| `lib/l10n/app_{en,hu}.arb` | **CSAK GENERÁLT KIMENET** — kizárólag `dart run tool/gen_l10n_segments.dart --write`, kézzel írni TILOS |
| `test/features/progress_v2/*_test.dart` (4) | a §6 cellái |
| `docs/rounds/e13-r31-…md` | a §10 handoff |

**Tilos zóna:** `lib/features/**` a `progress_v2/` KIVÉTELÉVEL ·
`lib/core/design_system/**` · `lib/core/theme/**` · `docs/adr/**` ·
`docs/sdd/**` · `tools/**` · `.github/**`.

## 5. Kötött architekturális döntések (ADR 0289)

### 5.1 Az elsajátítottság NEM XP-alapú

A képesség szintje **mért teljesítményből** származik, nem az eltöltött időből
vagy a begyűjtött pontokból. Aki sokat gyakorol rosszul, nem lesz haladó.

**NEM elfogadható gyengítés:** az XP megjelenítése elsajátítottságként „mert
motiválóbb". Az összekeveri a részvételt a tudással.

### 5.2 A bizonyíték AUDITÁLHATÓ

Minden elsajátítottsági állítás mögött konkrét, megnyitható session áll. A
felhasználó ellenőrizheti, mire alapoztuk.

### 5.3 A hiányzó adat NEM nulla

Az ADR 0286 §1 alkalmazása a fejlődési mérőszámokra.

### 5.4 A trendhez MINIMÁLIS adatmennyiség kell

Két pontból nem rajzolunk trendet. Elégtelen adat esetén a felület ezt kimondja.

### 5.5 A mérőszám-verzió váltása LÁTHATÓ a történetben

Ha a számítás módja változott, a régi és az új szakasz megkülönböztethető — nem
látszik törésnek vagy hirtelen javulásnak.

### 5.6 Az ajánlás TISZTELETBEN TARTJA a képesség-függőségeket

Nem javasol olyan gyakorlatot, aminek az előfeltétele hiányzik.

## 6. Acceptance criteria

| # | Kritérium | Bizonyíték |
|---|---|---|
| A1 | Az elsajátítottság nem XP-ből származik | `mastery_evidence_test.dart` |
| A2 | Minden elsajátítottsági állítás mögött megnyitható bizonyíték áll | ugyanott |
| A3 | A hiányzó adat NEM nullaként jelenik meg | `dashboard_states_test.dart` |
| A4 | Elégtelen adat esetén nincs trend, és ezt a felület kimondja | ugyanott |
| A5 | A mérőszám-verzió váltása látható a történetben | `metric_migration_test.dart` |
| A6 | Az offline fejlődés látható (helyi adat) | `dashboard_states_test.dart` |
| A7 | Az ajánlás nem sérti a képesség-előfeltételeket | `mastery_evidence_test.dart` |
| A8 | A diagramnak szöveges összegzése, a gráfnak lineáris alternatívája van | `chart_semantics_test.dart` |
| A9 | A kör §3-ban megnevezett MINDEN képernyőről golden-felvétel készül és be van commitolva — 412×915 compact portrait ÉS `textScaleFactor: 2.0` | `e13_r31_screens_golden_test.dart` + a `test/ui/goldens/*.png` a diffben |

### 6.1 Mérce-mátrix — melyik hibás implementációt melyik cella fogja pirosra

| Hibás implementáció | Melyik cella vált PIROSRA |
|---|---|
| Az XP elsajátítottságként megjelenítve | **A1** |
| A bizonyíték-hivatkozás nem nyit meg semmit | **A2** |
| `?? 0` a hiányzó mérőszámra | **A3** |
| Trend két adatpontból | **A4** |
| A verzióváltás hirtelen javulásként | **A5** |
| Előfeltétel nélküli gyakorlat ajánlása | A7 |
| A képernyő elcsúszik, túlcsordul vagy nagy szövegméretnél olvashatatlan | **A9** |

**A trend három kötelező cellája** (a küszöb: a minimális adatpont-szám, **5**):

| Cella | Bemenet | Elvárt |
|---|---|---|
| a küszöb alatt | 3 adatpont | **nincs trend** — „még nincs elég adat" |
| rajta (a küszöbön) | pontosan **5** adatpont | trend megjelenik (a határ inkluzív) |
| a küszöb fölött | 30 adatpont | trend megjelenik |

**Valódi-sértés próba (KÖTELEZŐ, §10-ben dokumentálva):** származtasd az
elsajátítottságot az XP-ből → az **A1** cellának PIROSNAK kell lennie →
állítsd vissza.

## 7. Kötelező ellenőrzések

```bash
tools/round-gate.sh test/features/progress_v2/dashboard_states_test.dart test/features/progress_v2/mastery_evidence_test.dart test/features/progress_v2/metric_migration_test.dart test/features/progress_v2/chart_semantics_test.dart test/ui/goldens/e13_r31_screens_golden_test.dart
```

**A golden-felvétel (A9) rögzítése — a mérce ÚJ, nem alku tárgya:** a képernyő
minden állapotát NEM kell felvenni, a §3 szerinti alap-nézet elég, de a két
keret (412×915 compact portrait és ugyanaz `textScaleFactor: 2.0` mellett)
KÖTELEZŐ. Minta és futó precedens: `test/features/live/chord_timeline_golden_test.dart`
(valódi kapu, nem `skip`-elt rögzítő). Előállítás:

```bash
~/flutter/bin/flutter test --update-goldens test/ui/goldens/e13_r31_screens_golden_test.dart
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

1. Az áttekintő új felhasználó / offline / migráció állapotai.
2. A trend három cellája — minimális adatmennyiséggel.
3. A képesség részletnézete, auditálható bizonyíték-hivatkozásokkal.
4. A mérőszám-verzió migráció láthatósága.
5. Az ajánlás előfeltétel-tisztelete.
6. Diagram-összegzés és lineáris gráf-alternatíva.
7. A valódi-sértés próba, §10-be dokumentálva.
8. `tools/round-gate.sh` a §7 szerint.

## 9. Kockázatok

- **Az XP mint elsajátítottság.** Motiválóbb és hamis: a részvételt tudásnak
  mutatja (A1).
- **A dísz-bizonyíték.** A hivatkozás ott van, de nem vezet sehova —
  auditálhatatlan állítás marad (A2).
- **A verzióváltás mint javulás.** A felhasználó azt hiszi, fejlődött, pedig a
  mérce változott (A5).

## 10. Implementation handoff — az implementer tölti ki

## 11. Review — a Claude tölti ki
