# E13-R12 — Kártyák, badge-ek, insight és status komponensek

- **Státusz:** PREPARED (előre megírva 2026-08-15, kód olvasva: `main @ 93a6c19a`)
- **Típus:** Chapter 13 (UI/UX Design System), Kör 12
- **Kör-azonosító:** `E13-R12`
- **Branch:** `<motor>/e13-r12-cards-badges-and-status`
- **Előfeltétel:** `E13-R11` merge-elve (action/input készlet)
- **Brief szerzője:** Claude (Opus 5)
- **Előre kiosztott ADR:** [`0278`](../adr/0278-ai-provenance-is-visible.md)
  — **a Claude írja meg a kör indításakor; a `docs/adr/` a TILOS zónában van.**

> ⚠ **Pre-flight (indítás előtt KÖTELEZŐ):** mérd fel, milyen TÉNYLEGES
> AI-mód és sync-állapot típusok léteznek ma (a coach/analysis rétegben), mert
> a §5.1 provenance-badge ezekre képez. Eltérésnél §0.0 revízió.

```ai-router
schema_version = 1
risk = "high"
allowed_paths = [
  "lib/core/design_system/components/cards/ss_metric_card.dart",
  "lib/core/design_system/components/cards/ss_insight_card.dart",
  "lib/core/design_system/components/cards/ss_coach_action_card.dart",
  "lib/core/design_system/components/cards/ss_content_card.dart",
  "lib/core/design_system/components/ai/ss_model_status_card.dart",
  "lib/core/design_system/components/ai/ss_provenance_badge.dart",
  "lib/core/design_system/components/feedback/ss_status_badge.dart",
  "lib/core/design_system/documentation/component_catalog_screen.dart",
  "lib/core/design_system/public.dart",
  "lib/l10n/app_en.arb",
  "lib/l10n/app_hu.arb",
  "test/core/design_system/cards/ss_cards_test.dart",
  "test/core/design_system/cards/ss_badges_test.dart",
  "docs/rounds/e13-r12-cards-badges-and-status.md",
]
gate_tests = [
  "test/core/design_system/cards/ss_cards_test.dart",
  "test/core/design_system/cards/ss_badges_test.dart",
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

Újrahasznosítható információs komponensek a hubokhoz, eredményekhez, az AI-,
sync- és confidence-felületekhez (SDD Ch13 Kör 12).

## 2. Jelenlegi állapot — mért tények

- Az R03 kimondta: az állapot **nem csak színnel** jelölt, és az alacsony
  confidence nem `danger`.
- Az R05 adja a felület-hierarchiát, az R07 az ikonokat, az R10 a skeletont.
- Az R10 skeleton-szabálya érvényes itt is: a skeleton geometriát tart, és nem
  olvasható tartalomként.

## 3. Scope

**Benne van:** `SsMetricCard`, `SsInsightCard`, `SsCoachActionCard`,
`SsModelStatusCard` és általános tartalmi kártya · offline, sync pending,
local AI, cloud AI, on-device, adatvédelmi láthatóság és confidence badge-ek
**ikon + szöveg** formában · kártya-akció hierarchia és beágyazott érintési cél
szabályai · compact és expanded sűrűség · a kártyákhoz illő skeletonok ·
Component Catalog állapot-mátrix.

**NINCS benne (tilos):** `lib/features/**` átállítása · AI-hívás vagy
üzleti logika a komponensben · a confidence **küszöbeinek** meghatározása
(az a felismerési rétegé) · `lib/core/theme/**` · `docs/adr/**`, `tools/**`,
`.github/**`.

## 4. Engedélyezett fájlok

| Útvonal | Indok |
|---|---|
| `cards/ss_metric_card.dart` | **ÚJ** — mérőszám (Montserrat, tabular) |
| `cards/ss_insight_card.dart` | **ÚJ** |
| `cards/ss_coach_action_card.dart` | **ÚJ** |
| `cards/ss_content_card.dart` | **ÚJ** — általános |
| `ai/ss_model_status_card.dart` | **ÚJ** — modell-állapot |
| `ai/ss_provenance_badge.dart` | **ÚJ** — helyi / felhő / on-device |
| `feedback/ss_status_badge.dart` | **ÚJ** — offline, sync, confidence |
| `documentation/component_catalog_screen.dart` | állapot-mátrix |
| `public.dart` | az export bővítése |
| `lib/l10n/app_{en,hu}.arb` | badge- és kártyaszövegek |
| `test/…/cards/*_test.dart` (2) | a §6 cellái |
| `docs/rounds/e13-r12-…md` | a §10 handoff |

**Tilos zóna:** `lib/features/**` · `lib/core/theme/**` · `lib/app/**` ·
`docs/adr/**` · `docs/sdd/**` · `tools/**` · `.github/**`.

## 5. Kötött architekturális döntések (ADR 0278)

### 5.1 Az AI-eredet LÁTHATÓ, és nem csak szín

Minden AI-eredetű tartalom megmutatja, **helyi vagy felhő** modell adta-e. Ez
adatvédelmi kérdés: a felhasználónak joga tudni, elhagyta-e adat a készüléket.

**NEM elfogadható gyengítés:** a provenance elrejtése egy részletnézetbe „hogy
tisztább legyen a kártya". A felhő-hívás ténye nem részletkérdés.

### 5.2 A badge jelentése NEM csak szín

Ikon vagy szöveg mindig kíséri (az R03 §5.3 folytatása). Színvakság mellett is
egyértelmű.

### 5.3 A kártya EGÉSZE csak akkor kattintható, ha EGY fő akciója van

Több akció esetén a kártya-háttér nem nyel el koppintást — különben a
felhasználó nem tudja, mi fog történni.

**NEM elfogadható gyengítés:** a kártya `InkWell`-be csomagolása több gomb
mellett. A beágyazott érintési célok kiszámíthatatlanná válnak.

### 5.4 A skeleton geometriát TART és nem olvasható tartalomként

Az R10 szabálya itt is él — a kártya betöltés közben nem ugrik.

### 5.5 A komponens NEM hív AI-t és nem tartalmaz üzleti logikát

Prezentációs réteg: minden adat kívülről jön.

### 5.6 A hosszú magyar cím nem csordul túl

Az R04 fixture-szabálya szerint, compact és expanded sűrűségben is.

## 6. Acceptance criteria

| # | Kritérium | Bizonyíték |
|---|---|---|
| A1 | Az AI-eredet (helyi/felhő) minden AI-tartalomnál látható | `ss_badges_test.dart` |
| A2 | Egy badge jelentése sem csak színnel jelölt | ugyanott |
| A3 | A kártya háttere csak egyetlen fő akciónál kattintható | `ss_cards_test.dart` |
| A4 | Beágyazott akció koppintása NEM váltja ki a kártya-akciót | ugyanott |
| A5 | A skeleton tartja a geometriát, és nincs a semanticsben | ugyanott |
| A6 | Hosszú magyar cím compact és expanded sűrűségben sem csordul túl | `ss_cards_test.dart` |
| A7 | A komponensek nem importálnak feature-logikát | architektúra-guard |
| A8 | Minden új szöveg ARB-n át megy (en + hu) | `grep` a diffben |

### 6.1 Mérce-mátrix — melyik hibás implementációt melyik cella fogja pirosra

| Hibás implementáció | Melyik cella vált PIROSRA |
|---|---|
| A provenance csak a részletnézetben | **A1** |
| A confidence csak színes pötty | **A2** |
| A kártya `InkWell`-ben, két gombbal | **A3** |
| A beágyazott gomb koppintása felbuborékol | **A4** |
| A skeleton más magasságú, mint a kész kártya | A5 |
| Csak angol fixture | A6 |

**A kártya-kattinthatóság három kötelező cellája** (a küszöb: a fő akciók száma):

| Cella | Bemenet | Elvárt |
|---|---|---|
| a küszöb alatt | 0 akció (tisztán információs) | a kártya **nem** kattintható |
| rajta (a küszöbön) | **1** fő akció | a teljes kártya kattintható |
| a küszöb fölött | 2+ akció | a kártya **nem** kattintható, csak a gombok |

**Valódi-sértés próba (KÖTELEZŐ, §10-ben dokumentálva):** tedd kattinthatóvá a
kártya hátterét két akció mellett → az **A3** cellának PIROSNAK kell lennie →
állítsd vissza.

## 7. Kötelező ellenőrzések

```bash
tools/round-gate.sh test/core/design_system/cards/ss_cards_test.dart test/core/design_system/cards/ss_badges_test.dart
```

Külön processzek, csonkítatlan kimenet. **Tilos** `| tail`, `| head`,
`&&`-lánc vagy bármilyen szűrés (L09); a `flutter analyze` és `flutter test`
kézi láncolása OOM-ot ad (L05). A kötelező gate-et **TILOS háttérbe küldeni**
(`run_in_background`) — az egy-fordulós harness a forduló végén megöli (L254).

## 8. Implementációs sorrend

1. `ss_status_badge.dart` + `ss_provenance_badge.dart` — ikon + szöveg.
2. `ss_metric_card.dart` — Montserrat, tabular figures (az R04 szerint).
3. `ss_insight_card.dart`, `ss_coach_action_card.dart`, `ss_content_card.dart`.
4. `ss_model_status_card.dart`.
5. A kattinthatóság három cellája + a beágyazott hit-test.
6. Skeletonok + ARB (en + hu) + Component Catalog mátrix.
7. A valódi-sértés próba, §10-be dokumentálva.
8. `tools/round-gate.sh` a §7 szerint.

## 9. Kockázatok

- **A provenance elrejtése.** A tisztább kártya kedvéért eltűnik egy
  adatvédelmi tény (A1).
- **A mindenhol kattintható kártya.** Egységesnek tűnik, és két akció mellett
  kiszámíthatatlan (A3/A4).
- **A csak színes confidence.** A leggyorsabb megoldás, és pont a termék
  bizonytalanság-kommunikációját teszi hozzáférhetetlenné (A2).

## 10. Implementation handoff — az implementer tölti ki

## 11. Review — a Claude tölti ki
