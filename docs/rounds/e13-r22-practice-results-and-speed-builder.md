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
  "lib/l10n/app_en.arb",
  "lib/l10n/app_hu.arb",
  "test/features/practice/result_confidence_test.dart",
  "test/features/practice/history_corrupt_record_test.dart",
  "test/features/practice/speed_ladder_test.dart",
  "test/features/practice/reward_idempotency_test.dart",
  "docs/rounds/e13-r22-practice-results-and-speed-builder.md",
]
gate_tests = [
  "test/features/practice/result_confidence_test.dart",
  "test/features/practice/history_corrupt_record_test.dart",
  "test/features/practice/speed_ladder_test.dart",
  "test/features/practice/reward_idempotency_test.dart",
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
| `lib/l10n/app_{en,hu}.arb` | az eredmény-szövegek |
| `test/features/practice/*_test.dart` (4) | a §6 cellái |
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

### 6.1 Mérce-mátrix — melyik hibás implementációt melyik cella fogja pirosra

| Hibás implementáció | Melyik cella vált PIROSRA |
|---|---|
| Pontos százalék gyenge jel mellett | **A1** |
| A részleges session teljesként jelenik meg | A2 |
| Egy sérült rekord kiüti a listát | **A3** |
| A jutalom a képernyőn számolva | **A5** |
| A csúcs-futam „legjobb"-ként | A6 |
| A következő lépés csak szöveges tanács | A7 |

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
tools/round-gate.sh test/features/practice/result_confidence_test.dart test/features/practice/history_corrupt_record_test.dart test/features/practice/speed_ladder_test.dart test/features/practice/reward_idempotency_test.dart
```

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
