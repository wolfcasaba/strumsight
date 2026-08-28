# E15-R13 — A sáv lezárása: teljes migrációs mérés, vizuális regresszió és APK-evidencia

- **Státusz:** PREPARED (előre megírva 2026-08-28, kód olvasva: `main @ 4cb32eb0`)
- **Típus:** Chapter 15 (UI-aktiválás és -befejezés), Kör 13 — a sáv ZÁRÓ köre
- **Kör-azonosító:** `E15-R13`
- **Branch:** `<motor>/e15-r13-ui-closure-and-release-evidence`
- **Előfeltétel:** `E15-R12` merge-elve (és a sáv minden korábbi köre)
- **Brief szerzője:** Claude (Opus 5)
- **Előre kiosztott ADR:** nincs — záró/mérési kör.

**Visszakeresett előzmény:** `node tools/knowledge-rag.mjs --corpus lessons,halts,adr --top 5 "visual regression closure migration status golden inventory"` → a `halts/round-status-E07-R30` (epic-záró minta) és **[ADR 0376](../adr/0376-ui-baseline-inventory-contract.md)** (UI baseline inventory és screenshot-corpus szerződés). A záró mérés ennek a szerződésnek a nyelvén beszél.

> ⚠ **Pre-flight (indítás előtt KÖTELEZŐ):** futtasd a migrációs mérést és a `tool/check_screen_reachability.dart`-ot (E15-R03), és a §2 számait EZEKKEL írd felül. A kör állítása nem lehet „minden migrálva", ha a mérés mást mond.

## 0.0 Mit jelent itt a „kész"

A sáv célja nem a 96/96 formális szám, hanem hogy a felhasználó által ELÉRHETŐ minden képernyő a design-rendszeren legyen. Az `E15-R03` visszavonási terve szerint „visszavonandó" képernyők migrálatlanul is lezártnak számítanak — de akkor a tervben ott a nevesített visszavonó kör. A záró mérés ezt a KÉT halmazt (migrált + tervezetten visszavont) veti össze az elérhetőségi méréssel.

```ai-router
schema_version = 1
risk = "normal"
allowed_paths = [
  "test/ui/goldens/e15_r13_full_variant_matrix_test.dart",
  "docs/ui/migration-status.md",
  "docs/ui/legacy-backlog.md",
  "docs/ui/chapter-15-completion-report.md",
  "docs/rounds/e15-r13-ui-closure-and-release-evidence.md",
]
gate_tests = [
  "test/ui/goldens/e15_r13_full_variant_matrix_test.dart",
  "test/ui/ui_inventory_test.dart",
  "test/tooling/screen_reachability_test.dart",
  "test/accessibility/closure_suite_test.dart",
]
native_gate = true
```

## 0. Kör-jelzés és STOP-protokoll

```bash
tools/codex-signal.sh progress "<egy sor>"
tools/codex-signal.sh done "<egy sor>"
tools/codex-signal.sh stopped "<egy sor>"
tools/codex-signal.sh blocked "<egy sor>"
```

**STOP-protokoll:** ha a mérés migrálatlan, de ELÉRHETŐ képernyőt talál, a kimenet a `stopped` jelzés és a lista — a sáv nem zárható le „majdnem készen".

## 1. Cél

Bizonyítani, hogy minden elérhető képernyő a design-rendszeren van, hogy a felület 200%-os szövegskálán és mindkét locale-on ép, és hogy a felhasználó kap egy telepíthető APK-t, amin ez látszik.

## 2. Jelenlegi állapot — mért tények (a pre-flight írja felül)

- A sáv indulásakor: **43 / 96** képernyő migrált (44,8%), **53** legacy, ebből a routerben hivatkozott **27**.
- `test/ui/goldens/` **20** golden-teszt fájl + **144** PNG; a Ch13 záró variáns-mátrixa (`e13_r36_variant_matrix_test.dart`) **192** cellát mér, PNG nélkül.
- `docs/ui/legacy-backlog.md` §1: az `E15-R02` után **0** nyitott elrendezési tétel kell legyen.
- A `tools/round-gate.sh` és a CI a merge-kapu; az APK-t a `build-apk.yml` dispatch adja (ADR 0053) — a dispatch az orchesztrátoré.

## 3. Scope

**Benne van:** `test/ui/goldens/e15_r13_full_variant_matrix_test.dart` — PNG-mentes variáns-mátrix a MÉRT elérhető képernyő-halmazra × {világos, sötét} × {en, hu} × {compact portrait, landscape} × {textScale 1.0, 2.0}, minden cella `RenderFlex`-túlcsordulás és pump-kivétel nélkül · `docs/ui/migration-status.md` végleges, MÉRT állapot · `docs/ui/legacy-backlog.md` lezárása (nyitott tétel csak dátummal, gazdával és nevesített körrel maradhat) · `docs/ui/chapter-15-completion-report.md` (mit szállított a sáv, mit mértünk, mi maradt).

**NINCS benne (tilos):**

- `lib/**` módosítás (a záró kör MÉR, nem javít — talált hiba `stopped` + backlog).
- Új golden PNG felvétele ezen a boxon (ADR 0426).
- A `ui_inventory_test.dart` egzakt számának megváltoztatása.
- `docs/adr/**`.

## 4. Engedélyezett fájlok

| Útvonal | Indok |
|---|---|
| `test/ui/goldens/e15_r13_full_variant_matrix_test.dart` | ÚJ — a záró variáns-mátrix |
| `docs/ui/migration-status.md` | végleges MÉRT állapot |
| `docs/ui/legacy-backlog.md` | lezárás |
| `docs/ui/chapter-15-completion-report.md` | ÚJ — zárójelentés |

**Tilos zóna:** `lib/**` · `test/ui/goldens/goldens/**` · `docs/adr/**` · `tools/**` · `.github/**`

## 5. Kötött architekturális döntések

Nincs ADR. Két kötelező szabály:

### 5.1 A záró állítás MÉRÉSBŐL jön

„Minden elérhető képernyő migrált" csak akkor írható le, ha a `check_screen_reachability.dart` + a migrációs mérés együtt ezt adja. **NEM elfogadható gyengítés:** kerekített vagy becsült arány a jelentésben.

### 5.2 A talált hiba LELET, nem javítandó munka

**NEM elfogadható gyengítés:** egy túlcsordulás gyors javítása a `lib/`-ben, ami elrejtené, mit mért a záró kör.

## 6. Acceptance criteria

| # | Kritérium | Bizonyíték |
|---|---|---|
| A1 | MINDEN elérhető képernyő migrált (vagy a tervben nevesített visszavonó körhöz rendelt) | `screen_reachability_test.dart` + a mérés kimenete a §10-ben |
| A2 | A záró variáns-mátrix MINDEN cellája túlcsordulás és kivétel nélkül renderel | `e15_r13_full_variant_matrix_test.dart` |
| A3 | A `legacy-backlog.md`-ben nincs gazdátlan vagy dátum nélküli nyitott tétel | a dokumentum + a mátrix-teszt szerkezeti cellája |
| A4 | A `ui_inventory_test.dart` egzakt száma VÁLTOZATLAN | a §7 gate |
| A5 | A zárójelentés minden állítása parancs- vagy fájl-hivatkozású | `docs/ui/chapter-15-completion-report.md` |
| A6 | ZÖLD teljes CI-futás a kör-branchen, és belőle telepíthető APK-artefaktum | orchesztrátor-dispatch linkje a §10-ben |

**Küszöb-cellahármas a szövegskálára** (a kötelező határ `2.0`, INKLUZÍV): a küszöb **alatt** (`1.5`) → minden cella zöld; **pontosan rajta** (`2.0`) → minden cella zöld, EZ az A2 feltétele; a küszöb **fölött** (`2.5`) → nem követelmény, és a `2.0` teljesítése nem hivatkozhat rá.

### 6.1 Mérce-mátrix — melyik hibás implementációt melyik cella fogja pirosra

| Hibás implementáció | Melyik cella vált PIROSRA |
|---|---|
| A mátrix csak a migrált képernyőket méri, az elérhető legacyket kihagyja | A1 |
| A jelentés „100%"-ot ír, miközben a mérés kevesebbet ad | A5 |
| Egy nyitott backlog-tétel gazda nélkül marad | A3 |
| A záró kör „menet közben" javít egy talált túlcsordulást | A4/A6 (a `git diff` a `lib/`-ben scope-sértés) |

**Valódi-sértés próba (KÖTELEZŐ, a §10-ben dokumentálva):** vegyél ki egy elérhető képernyőt a mátrix bemeneti listájából, futtasd a §7 gate-et → az **A1** cellának PIROSNAK kell lennie → állítsd vissza.

## 7. Kötelező ellenőrzések

```bash
tools/round-gate.sh test/ui/goldens/e15_r13_full_variant_matrix_test.dart test/ui/ui_inventory_test.dart test/tooling/screen_reachability_test.dart test/accessibility/closure_suite_test.dart
```

A záró mérés (a kimenet a §10-be):

```bash
dart run tool/check_screen_reachability.dart --format table
```

A teljes suite + property gate + APK a CI-ban fut (ADR 0053); a dispatch és a kiadás-link az orchesztrátoré.

## 8. Implementációs sorrend

1. A két mérés futtatása (elérhetőség + migráció).
2. `e15_r13_full_variant_matrix_test.dart` a MÉRT elérhető halmazra.
3. `migration-status.md` és `legacy-backlog.md` lezárás.
4. `chapter-15-completion-report.md`.
5. A valódi-sértés próba a §10-be; a CI-dispatch és az APK-link az orchesztrátortól.

## 9. Kockázatok

- **Kozmetikai zárás.** A „minden kész" állítás mérés nélkül (A1, A5).
- **Mátrix-robbanás.** Az elérhető halmaz × 16 variáns sok cella — a teszt fusson `pumpAndSettle` nélkül, ahol lehet, és a §7 futásideje maradjon a gate keretein belül.
- **Javítás-csábítás.** A talált hiba backlogba megy, nem a kör diffjébe (§5.2).

## 10. Implementation handoff — az implementer tölti ki

## 11. Review — a Claude tölti ki
