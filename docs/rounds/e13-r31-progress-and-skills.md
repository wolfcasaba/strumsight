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
  "lib/l10n/app_en.arb",
  "lib/l10n/app_hu.arb",
  "test/features/progress_v2/dashboard_states_test.dart",
  "test/features/progress_v2/mastery_evidence_test.dart",
  "test/features/progress_v2/metric_migration_test.dart",
  "test/features/progress_v2/chart_semantics_test.dart",
  "docs/rounds/e13-r31-progress-and-skills.md",
]
gate_tests = [
  "test/features/progress_v2/dashboard_states_test.dart",
  "test/features/progress_v2/mastery_evidence_test.dart",
  "test/features/progress_v2/metric_migration_test.dart",
  "test/features/progress_v2/chart_semantics_test.dart",
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
| `lib/l10n/app_{en,hu}.arb` | a fejlődés-szövegek |
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

### 6.1 Mérce-mátrix — melyik hibás implementációt melyik cella fogja pirosra

| Hibás implementáció | Melyik cella vált PIROSRA |
|---|---|
| Az XP elsajátítottságként megjelenítve | **A1** |
| A bizonyíték-hivatkozás nem nyit meg semmit | **A2** |
| `?? 0` a hiányzó mérőszámra | **A3** |
| Trend két adatpontból | **A4** |
| A verzióváltás hirtelen javulásként | **A5** |
| Előfeltétel nélküli gyakorlat ajánlása | A7 |

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
tools/round-gate.sh test/features/progress_v2/dashboard_states_test.dart test/features/progress_v2/mastery_evidence_test.dart test/features/progress_v2/metric_migration_test.dart test/features/progress_v2/chart_semantics_test.dart
```

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
