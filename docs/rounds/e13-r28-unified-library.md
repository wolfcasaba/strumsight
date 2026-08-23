# E13-R28 — Unified Library és Session Detail UI

- **Státusz:** PREPARED (előre megírva 2026-08-15, kód olvasva: `main @ c732ec75`)
- **Típus:** Chapter 13 (UI/UX Design System), Kör 28
- **Kör-azonosító:** `E13-R28`
- **Branch:** `<motor>/e13-r28-unified-library`
- **Előfeltétel:** `E13-R27` merge-elve (elemzési eredmények)
- **Brief szerzője:** Claude (Opus 5)
- **Előre kiosztott ADR:** nincs — az ADR 0279 (megerősítés) és 0283 érvényes.

> ⚠ **Pre-flight (indítás előtt KÖTELEZŐ):** mérd fel a TÉNYLEGES tárolási és
> szinkron-állapot típusokat, valamint azt, hogy a törlés melyik use case-ben
> él — a §5.4 kimondja, hogy a felület csak belépési pont. Eltérésnél §0.0
> revízió.

```ai-router
schema_version = 1
risk = "high"
allowed_paths = [
  "lib/features/library_v2/",
  "lib/app/routing/",
  "lib/l10n/app_en.arb",
  "lib/l10n/app_hu.arb",
  "test/features/library_v2/item_routing_test.dart",
  "test/features/library_v2/corrupt_item_test.dart",
  "test/features/library_v2/delete_confirmation_test.dart",
  "test/features/library_v2/sync_conflict_test.dart",
  "test/ui/goldens/",
  "docs/rounds/e13-r28-unified-library.md",
]
gate_tests = [
  "test/features/library_v2/item_routing_test.dart",
  "test/features/library_v2/corrupt_item_test.dart",
  "test/features/library_v2/delete_confirmation_test.dart",
  "test/features/library_v2/sync_conflict_test.dart",
  "test/ui/goldens/e13_r28_screens_golden_test.dart",
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

Az UI-40–UI-41 egységes tétel-lista, tárolási/szinkron-státusz és **biztonságos
adatkezelés** (SDD Ch13 Kör 28).

## 2. Jelenlegi állapot — mért tények

- A könyvtár többféle tételt fog össze (gyakorlás, elemzés, dal, setlist) —
  a route-olásnak típus-biztosnak kell lennie.
- Az R22 kimondta: a sérült rekord izolált. Ez a kör ugyanezt az egységes
  listára terjeszti ki.
- Az ADR 0279 kimondta: a destruktív megerősítés a következményt nevezi meg.

## 3. Scope

**Benne van:** az egységes könyvtár keresés / szűrés / lista-részlet felülete
**típus-biztos** route-olással · a session részletnézete (metaadat,
eredmény-előnézet, jegyzet, export, összehasonlítás, törlés) · sérült tétel
izolálása, tárhely-közeli-limit, helyi/felhő és **szinkron-ütközés** állapotok ·
tárhely-kezelési belépési pont (a tényleges törlést a repository use case
végzi) · a legacy Library route adaptere · lapozás, stabil görgetés, offline
cached tesztek.

**NINCS benne (tilos):** a törlési vagy szinkron-logika implementálása a
felületen · a tárolási séma módosítása · más képernyők migrációja ·
`docs/adr/**`, `tools/**`, `.github/**`.

## 4. Engedélyezett fájlok

| Útvonal | Indok |
|---|---|
| `lib/features/library_v2/` | az egységes könyvtár |
| `lib/app/routing/` | **kizárólag** a legacy alias |
| `lib/l10n/app_{en,hu}.arb` | a könyvtár-szövegek |
| `test/features/library_v2/*_test.dart` (4) | a §6 cellái |
| `docs/rounds/e13-r28-…md` | a §10 handoff |

**Tilos zóna:** `lib/features/**` a `library_v2/` KIVÉTELÉVEL ·
`lib/core/design_system/**` · `lib/core/theme/**` · `docs/adr/**` ·
`docs/sdd/**` · `tools/**` · `.github/**`.

## 5. Kötött architekturális döntések

### 5.1 A sérült tétel NEM töri a listát

Egyetlen olvashatatlan rekord nem viheti magával az egész könyvtárat — hibásként
jelenik meg, a többi elérhető marad (az ADR 0283 §5 kiterjesztése).

### 5.2 A helyi tartalom OFFLINE megnyitható

Ami a készüléken van, hálózat nélkül is elérhető.

### 5.3 A törlés HATÓKÖRE világos

A megerősítés kimondja, mi törlődik: csak a nyers hang, csak az eredmény, vagy
minden. Az ADR 0279 §1 alkalmazása a legveszélyesebb műveletre.

**NEM elfogadható gyengítés:** „Törlöd? Igen/Nem" a hatókör megnevezése nélkül.
A felhasználó nem tudja, mit veszít.

### 5.4 A felület NEM implementál törlési logikát

A tárhely-kezelés belépési pont; a tényleges műveletet a repository use case
végzi. Így a törlés egy helyen mérhető és tesztelhető.

### 5.5 A nyers eszköz hiánya mellett az EREDMÉNY megmarad

Ha a nyers hangot törölték vagy hiányzik, a származtatott elemzés továbbra is
megnyitható. A kettő nem egyetlen egység.

### 5.6 A szinkron-ütközés MEGMONDJA a választást

Nem néma felülírás: a felhasználó látja, melyik verzió melyik, és dönt.

## 6. Acceptance criteria

| # | Kritérium | Bizonyíték |
|---|---|---|
| A1 | A tétel-típusok route-olása típus-biztos, nem téveszt célt | `item_routing_test.dart` |
| A2 | A sérült tétel izolált, a lista működik | `corrupt_item_test.dart` |
| A3 | A helyi tartalom offline megnyitható | ugyanott |
| A4 | A törlés hatóköre a megerősítésben megjelenik | `delete_confirmation_test.dart` |
| A5 | A felület nem implementál törlési logikát (use case-t hív) | `grep` a diffben |
| A6 | A nyers eszköz hiánya mellett az eredmény megmarad | `corrupt_item_test.dart` |
| A7 | A szinkron-ütközés választást kínál, nem néma felülírást | `sync_conflict_test.dart` |
| A8 | A legacy Library route működik | `item_routing_test.dart` |
| A9 | A kör §3-ban megnevezett MINDEN képernyőről golden-felvétel készül és be van commitolva — 412×915 compact portrait ÉS `textScaleFactor: 2.0` | `e13_r28_screens_golden_test.dart` + a `test/ui/goldens/*.png` a diffben |

### 6.1 Mérce-mátrix — melyik hibás implementációt melyik cella fogja pirosra

| Hibás implementáció | Melyik cella vált PIROSRA |
|---|---|
| Egy sérült rekord kiüti a listát | **A2** |
| „Törlöd? Igen/Nem" hatókör nélkül | **A4** |
| A törlés a widgetben történik | **A5** |
| A nyers hang hiánya elrejti az eredményt | **A6** |
| A szinkron némán felülír | **A7** |
| A típus szerinti route elágazás hibás célt ad | A1 |
| A képernyő elcsúszik, túlcsordul vagy nagy szövegméretnél olvashatatlan | **A9** |

**A törlés-hatókör három kötelező cellája** (a küszöb: mi törlődik):

| Cella | Bemenet | Elvárt |
|---|---|---|
| a küszöb alatt | csak a nyers hang | a megerősítés kimondja: **az eredmény megmarad** |
| rajta (a küszöbön) | **csak az eredmény** | a megerősítés kimondja, hogy a nyers hang megmarad |
| a küszöb fölött | a teljes tétel | a megerősítés kimondja, hogy **minden** törlődik és visszafordíthatatlan |

**Valódi-sértés próba (KÖTELEZŐ, §10-ben dokumentálva):** cseréld a törlési
megerősítést általános „Igen/Nem"-re → az **A4** cellának PIROSNAK kell lennie
→ állítsd vissza.

## 7. Kötelező ellenőrzések

```bash
tools/round-gate.sh test/features/library_v2/item_routing_test.dart test/features/library_v2/corrupt_item_test.dart test/features/library_v2/delete_confirmation_test.dart test/features/library_v2/sync_conflict_test.dart test/ui/goldens/e13_r28_screens_golden_test.dart
```

**A golden-felvétel (A9) rögzítése — a mérce ÚJ, nem alku tárgya:** a képernyő
minden állapotát NEM kell felvenni, a §3 szerinti alap-nézet elég, de a két
keret (412×915 compact portrait és ugyanaz `textScaleFactor: 2.0` mellett)
KÖTELEZŐ. Minta és futó precedens: `test/features/live/chord_timeline_golden_test.dart`
(valódi kapu, nem `skip`-elt rögzítő). Előállítás:

```bash
~/flutter/bin/flutter test --update-goldens test/ui/goldens/e13_r28_screens_golden_test.dart
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

1. Az egységes lista + típus-biztos route-olás.
2. A sérült tétel izolálása és az offline elérhetőség.
3. A session részletnézete (metaadat, előnézet, jegyzet, export).
4. A törlés-hatókör három cellája — use case hívással.
5. A szinkron-ütközés választó felülete.
6. A legacy route adaptere + lapozás, stabil görgetés.
7. A valódi-sértés próba, §10-be dokumentálva.
8. `tools/round-gate.sh` a §7 szerint.

## 9. Kockázatok

- **A hatókör nélküli törlés.** A leggyakoribb visszafordíthatatlan
  felhasználói hiba forrása (A4).
- **A felületbe költöző törlési logika.** Kényelmes, és megsokszorozza a
  helyeket, ahol adat veszhet el (A5).
- **A néma szinkron-felülírás.** A felhasználó munkáját viszi el úgy, hogy
  észre sem veszi (A7).

## 10. Implementation handoff — az implementer tölti ki

## 11. Review — a Claude tölti ki
