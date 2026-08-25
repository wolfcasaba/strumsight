# E13-R22 — Practice result, history és Speed Builder UI

- **Státusz:** PREPARED (előre megírva 2026-08-15, kód olvasva: `main @ 74f8a8ec`)
- **Típus:** Chapter 13 (UI/UX Design System), Kör 22
- **Kör-azonosító:** `E13-R22`
- **Branch:** `<motor>/e13-r22-practice-results-and-speed-builder`
- **Előfeltétel:** `E13-R21` merge-elve (aktív session UI)
- **Brief szerzője:** Claude (Opus 5)
- **Előre kiosztott ADR:** [`0283`](../adr/0283-results-never-overstate-certainty.md)
  — **a Claude írja meg a kör indításakor; a `docs/adr/` a TILOS zónában van.**

> ⚠ **Pre-flight (indítás előtt KÖTELEZŐ):** olvasd el a TÉNYLEGES jutalom-
> főkönyv (ledger) interfészét — a §5.4 kimondja, hogy a jutalom-összegzés
> onnan jön, nem UI-oldali számításból. Ha nincs ilyen réteg, `blocked`
> jelzéssel állj meg. Eltérésnél §0.0 revízió.

```ai-router
schema_version = 1
risk = "high"
allowed_paths = [
  "lib/features/practice/results/",
  "lib/features/practice/history/",
  "lib/features/practice/speed_builder/",
  "lib/l10n/base/app_en.arb",
  "lib/l10n/base/app_hu.arb",
  "lib/l10n/app_en.arb",
  "lib/l10n/app_hu.arb",
  "test/features/practice/result_confidence_test.dart",
  "test/features/practice/history_corrupt_record_test.dart",
  "test/features/practice/speed_ladder_test.dart",
  "test/features/practice/reward_idempotency_test.dart",
  "test/ui/goldens/",
  "test/ui/ui_inventory_test.dart",
  "docs/rounds/e13-r22-practice-results-and-speed-builder.md",
]
gate_tests = [
  "test/features/practice/result_confidence_test.dart",
  "test/features/practice/history_corrupt_record_test.dart",
  "test/features/practice/speed_ladder_test.dart",
  "test/features/practice/reward_idempotency_test.dart",
  "test/ui/goldens/e13_r22_screens_golden_test.dart",
  "test/ui/ui_inventory_test.dart",
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

**Kockázat = high, indoklás:** az eredmény- és előzmény-felületek a felhasználó teljes gyakorlási történetét (személyes adat) jelenítik meg.

### R1 — `lib/l10n/app_{en,hu}.arb` GENERÁLT aggregátum → a FORRÁS a szegmens

A kör fájából `lib/features/practice/results/`, `lib/features/practice/history/`, `lib/features/practice/speed_builder/` **még nem létezik** — a képernyőket ez a kör hozza létre, tehát MINDEN szövege új.

A kör ezért **nem tudott volna egyetlen szöveget sem írni** a saját listáján
belül. Feloldás — H3 lista-tágítás, **user-engedéllyel (2026-08-25)**, a
lehető legszűkebb alakban:

- `practice` → nincs saját fragmentuma, a kulcsai a `base/app_*.arb` szegmensben élnek

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

### R4 — a képernyő-leltár őre (H3 önjavító kör, ADR 0112, 2026-08-25)

A `test/ui/ui_inventory_test.dart` **repó-szintű** őr: a `tool/ui_inventory.dart`
a `lib/features/**` fa `_screen.dart` végű fájljait számolja, a teszt pedig
EGZAKT `hasLength(...)`-et állít rájuk. Ez a kör a(z) `lib/features/practice/history/`, `lib/features/practice/results/`, `lib/features/practice/speed_builder/` könyvtár-előtag
alá képernyőt hoz vagy hozhat, tehát a szám **elmozdul**, és az exact-SHA Full
Gate pirosra vált.

A `test/ui/goldens/` előtag ezt **nem** fedi (az a `test/ui/` fának csak az egyik
ága), a leltárteszt utólagos felvétele pedig tágítás, azaz **H3** — az
orchestrátor a pre-flightban nem oldhatja fel ([L478](../LESSONS.md)). Ezért
kerül a listára MOST, az önjavító körben.

**MÉRVE (E13-R16, 2026-08-25):** pontosan ez a hiány állította meg a sáv első
migrációs körét — [full-gate 32867296946](https://github.com/wolfcasaba/strumsight/actions/runs/32867296946)
6366 passed / 2 failed, `hasLength(79)` a tényleges 81 ellen. A `9acd14e5`
sáv-szintű batch pre-flight azért nem találta meg, mert a `tools/brief-lint.py`
`S9` szabálya csak LITERÁLIS `*_screen.dart` útvonalat nézett, KÖNYVTÁR-előtagot
nem — a predikátumot ugyanez az önjavító kör javította, regressziós teszttel
([L483](../LESSONS.md)).

**A jogosultság PONTOSAN a szám emelése** a kör tényleges képernyőszámára; a
leltárteszt minden más állítása érintetlen marad. Kerülőút (képernyő-átnevezés
vagy a `tool/ui_inventory.dart` szabályának lazítása) **TILOS** — az a mérce
meghamisítása.

## 0. Kör-jelzés és STOP-protokoll

```bash
tools/codex-signal.sh progress "<egy sor>"
tools/codex-signal.sh done "<egy sor>"
tools/codex-signal.sh stopped "<egy sor>"
tools/codex-signal.sh blocked "<egy sor>"
```

Lezáró jelzés nélkül a kör bukott. Listán kívüli fájl → `stopped`.

## 1. Cél

Az UI-21–UI-23 (eredmény, előzmények, tempó-progresszió) **összegzés-központú**
felületei (SDD Ch13 Kör 22).

## 2. Jelenlegi állapot — mért tények

- Az R12 mérőszám- és insight-kártyái, az R10 állapotai készen állnak.
- Az R21 lezárta a session-t; ez a kör mutatja meg az eredményét.
- A jutalom-főkönyv **idempotens** réteg — az összegzés onnan jön.

## 3. Scope

**Benne van:** az eredmény mérőszám / insight / következő lépés elrendezése
**confidence-tudatosan** · az előzmények szűrhető, **sérült rekordot izoláló**
listája · a Speed Builder beállítás / aktív / eredmény elrendezése · megosztás,
tutor és korrekció route-leképezés · a jutalom-összegzés a **főkönyvből** ·
elégtelen jel, részleges session és offline sync állapotok.

**NINCS benne (tilos):** a pontozás vagy a jutalom-logika módosítása · a
jutalom UI-oldali **számítása** · más képernyők migrációja · `docs/adr/**`,
`tools/**`, `.github/**`.

## 4. Engedélyezett fájlok

| Útvonal | Indok |
|---|---|
| `practice/results/` | az eredmény-felület |
| `practice/history/` | az előzmények |
| `practice/speed_builder/` | a tempó-progresszió |
| `lib/l10n/base/app_{en,hu}.arb` | **FORRÁS** — az eredmény-szövegek (a kör feature-ei még nem migráltak, a kulcsaik itt élnek) |
| `lib/l10n/app_{en,hu}.arb` | **CSAK GENERÁLT KIMENET** — kizárólag `dart run tool/gen_l10n_segments.dart --write`, kézzel írni TILOS |
| `test/features/practice/*_test.dart` (4) | a §6 cellái |
| `test/ui/ui_inventory_test.dart` | **repó-szintű képernyő-leltár őr** — a kör új `lib/features/**/*_screen.dart`-ot hozhat, ezért az egzakt `hasLength(...)` elmozdul; a jogosultság PONTOSAN a szám emelése, más állítás nem érinthető (§0.0/R4) |
| `docs/rounds/e13-r22-…md` | a §10 handoff |

**Tilos zóna:** `lib/features/**` a három érintett KIVÉTELÉVEL ·
`lib/core/design_system/**` · `lib/core/theme/**` · `docs/adr/**` ·
`docs/sdd/**` · `tools/**` · `.github/**`.

## 5. Kötött architekturális döntések (ADR 0283)

### 5.1 Az alacsony megbízhatóságú eredmény NEM kategorikus

Ha a felismerés bizonytalan volt, az eredmény ezt **kimondja**, és nem közöl
pontos százalékot ítéletként. A bizonytalanság a felületen is bizonytalanság
marad.

**NEM elfogadható gyengítés:** „78%" kiírása gyenge jel mellett is, mert „így
egységesebb". Az a mérés hitelét adja fel a látszatért.

### 5.2 A sérült rekord IZOLÁLT, nem omlasztja a listát

Egyetlen olvashatatlan előzmény-rekord nem viheti magával az egész képernyőt —
a sor hibásként jelenik meg, a többi elérhető marad.

### 5.3 Az előzmények OFFLINE elérhetők

Helyi adat. Hálózat nélkül is látszik.

### 5.4 A jutalom a FŐKÖNYVBŐL jön, nem UI-számításból

Az eredmény újranyitása nem adhat újabb jutalmat. Az idempotencia forrása a
főkönyv; a felület csak megjelenít.

**NEM elfogadható gyengítés:** a jutalom kiszámítása a képernyőn a session
adataiból. Újranyitáskor duplikálódik.

### 5.5 A Speed Builder a STABIL legjobb tempót mutatja

Egyetlen szerencsés futam nem „legjobb". A stabilitás definíciója a domainé; a
felület azt jeleníti meg, amit kap.

### 5.6 A következő lépés VÉGREHAJTHATÓ

Nem tanács, hanem gomb: elindítja a javasolt gyakorlatot a helyes
paraméterezéssel.

## 6. Acceptance criteria

| # | Kritérium | Bizonyíték |
|---|---|---|
| A1 | Alacsony megbízhatóságnál az eredmény nem kategorikus | `result_confidence_test.dart` |
| A2 | Részleges session eredménye részlegesként jelenik meg | ugyanott |
| A3 | Sérült előzmény-rekord izolált, a lista működik | `history_corrupt_record_test.dart` |
| A4 | Az előzmények offline elérhetők | ugyanott |
| A5 | A jutalom újranyitáskor NEM duplikálódik | `reward_idempotency_test.dart` |
| A6 | A Speed Builder a stabil legjobb tempót mutatja | `speed_ladder_test.dart` |
| A7 | A következő lépés végrehajtható és helyesen paraméterez | `result_confidence_test.dart` |
| A8 | A megosztás-route helyes adattartalommal indul | ugyanott |
| A9 | A kör §3-ban megnevezett MINDEN képernyőről golden-felvétel készül és be van commitolva — 412×915 compact portrait ÉS `textScaleFactor: 2.0` | `e13_r22_screens_golden_test.dart` + a `test/ui/goldens/*.png` a diffben |

### 6.1 Mérce-mátrix — melyik hibás implementációt melyik cella fogja pirosra

| Hibás implementáció | Melyik cella vált PIROSRA |
|---|---|
| Pontos százalék gyenge jel mellett | **A1** |
| A részleges session teljesként jelenik meg | A2 |
| Egy sérült rekord kiüti a listát | **A3** |
| A jutalom a képernyőn számolva | **A5** |
| A csúcs-futam „legjobb"-ként | A6 |
| A következő lépés csak szöveges tanács | A7 |
| A képernyő elcsúszik, túlcsordul vagy nagy szövegméretnél olvashatatlan | **A9** |

**Az eredmény-megbízhatóság három kötelező cellája** (a küszöb: **0,60**, az
ADR 0281 §2-vel egyező határ):

| Cella | Bemenet | Elvárt |
|---|---|---|
| a küszöb alatt | 0,45 | **nem kategorikus** — tartomány + magyarázat, nincs pontszám-ítélet |
| rajta (a küszöbön) | pontosan **0,60** | kategorikus eredmény megengedett (a határ inkluzív) |
| a küszöb fölött | 0,85 | kategorikus eredmény |

**Valódi-sértés próba (KÖTELEZŐ, §10-ben dokumentálva):** számold ki a jutalmat
a képernyőn a főkönyv helyett → az **A5** cellának PIROSNAK kell lennie →
állítsd vissza.

## 7. Kötelező ellenőrzések

```bash
tools/round-gate.sh test/features/practice/result_confidence_test.dart test/features/practice/history_corrupt_record_test.dart test/features/practice/speed_ladder_test.dart test/features/practice/reward_idempotency_test.dart test/ui/goldens/e13_r22_screens_golden_test.dart test/ui/ui_inventory_test.dart
```

**A golden-felvétel (A9) rögzítése — a mérce ÚJ, nem alku tárgya:** a képernyő
minden állapotát NEM kell felvenni, a §3 szerinti alap-nézet elég, de a két
keret (412×915 compact portrait és ugyanaz `textScaleFactor: 2.0` mellett)
KÖTELEZŐ. Minta és futó precedens: `test/features/live/chord_timeline_golden_test.dart`
(valódi kapu, nem `skip`-elt rögzítő). Előállítás:

```bash
~/flutter/bin/flutter test --update-goldens test/ui/goldens/e13_r22_screens_golden_test.dart
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

1. Az eredmény-felület + a megbízhatóság három cellája.
2. A részleges session és az elégtelen jel állapota.
3. Az előzmények listája, sérült rekord izolálásával, offline.
4. A jutalom-összegzés a főkönyvből + az idempotencia-cella.
5. A Speed Builder három felülete + a stabil legjobb tempó.
6. A következő lépés végrehajtható akciója + a megosztás-route.
7. A valódi-sértés próba, §10-be dokumentálva.
8. `tools/round-gate.sh` a §7 szerint.

## 9. Kockázatok

- **A kategorikus pontszám.** Egységesnek látszik, és bizonytalan mérésre
  ítéletet mond — a termék hitelét viszi (A1).
- **A UI-oldali jutalom.** Kényelmes, és minden újranyitáskor duplikál (A5).
- **A sérült rekord.** Ritka, és ha kiüti a listát, az összes előzmény
  elérhetetlen lesz (A3).

## 10. Implementation handoff — az implementer tölti ki

## 11. Review — a Claude tölti ki
