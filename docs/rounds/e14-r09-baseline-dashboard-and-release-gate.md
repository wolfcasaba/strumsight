# E14-R09 — Baseline dashboard és fail-closed release gate

- **Státusz:** PREPARED (előre megírva 2026-08-20, kód olvasva: `main @ b0979855`)
- **Típus:** Chapter 14 (Recognition Accuracy & Useful UI Recovery), Kör 9 —
  a „mérési és bizonyítási alap" blokk (R01–R09) ZÁRÓ köre
- **Kör-azonosító:** `E14-R09`
- **Branch:** `<motor>/e14-r09-baseline-dashboard-and-release-gate`
- **Előfeltétel:** `E14-R08` merge-elve (a harness, amelynek a kimenetét a
  dashboard és a kapu olvassa).
- **Brief szerzője:** Claude (Opus 5)
- **Előre kiosztott ADR:** `0361` — **a Claude írja meg, a `docs/adr/` a TILOS zónában van.**

> ⚠ **Pre-flight (indítás előtt KÖTELEZŐ):** olvasd újra a
> `docs/eval/recognition-release-guard.md`-t (E14-R01) — a kapu küszöbei a
> Chapter 14 §7.2/§7.4 Alpha-értékeiből jönnek, és a guard-dokumentum a
> hivatkozási pont. Ellenőrizd az `E14-R08` report-sémáját is. Eltérésnél
> §0.0 revízió.

```ai-router
schema_version = 1
risk = "normal"
allowed_paths = [
  "lib/features/live/domain/evaluation/recognition_release_gate.dart",
  "lib/features/live/data/evaluation/recognition_report_renderer.dart",
  "evaluation/recognition/recognition_release_gate.json",
  "tool/recognition_report.dart",
  "test/features/live/evaluation/recognition_release_gate_test.dart",
  "test/features/live/evaluation/recognition_report_renderer_test.dart",
  "docs/eval/recognition-dashboard.md",
  "docs/rounds/e14-r09-baseline-dashboard-and-release-gate.md",
]
gate_tests = [
  "test/features/live/evaluation/recognition_release_gate_test.dart",
  "test/features/live/evaluation/recognition_report_renderer_test.dart",
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

A release-döntés ne egyetlen százalékon múljon: ugyanabból a mérésből
készüljön JSON, Markdown és HTML report per-player/-device/-guitar/-room/
-technique bontással, külön mutatva a **confident wrong**, **uncertain
correct** és **rejected** eseményeket — és legyen mellette egy verziózott,
**fail-closed** kapu (`recognition_release_gate.json`), amely hiányzó metrikára
FAIL-t ad.

### 1.1 Visszakeresett előzmény (ADR 0312)

- **E14-R01 release guard:** a szabály (`UNKNOWN > CONFIDENTLY WRONG`) és a
  baseline-számok (akkord 67,1%, onset F1 50 ms 67,4%, irány 80,7%) — a kapu
  ezekhez képest mér, és a guard-dokumentum a hivatkozás.
- **ADR 0053 / round-gate:** a repóban a kapu artefaktum, nem prompt-szöveg —
  ezért a release gate is futtatható fájl + teszt, nem doksi-mondat.

## 2. Jelenlegi állapot — mért tények

- `docs/eval/recognition-release-guard.md` — MEGVAN (E14-R01), de **nincs**
  géppel olvasható küszöbfájl mellette.
- `evaluation/recognition/` — az `E14-R02` és `E14-R08` tölti fel manifesttel,
  fixture-rel; kapu-fájl **nincs**.
- Dashboard/report renderer a felismerési oldalon **nincs**.

## 3. Scope

**Benne:** kapu-modell + verziózott küszöbfájl, fail-closed kiértékelés,
JSON/Markdown/HTML renderer ugyanabból a reportból, bontások, a három
esemény-kategória külön megjelenítése, CLI, doksi.

**Nincs benne:** küszöb-hangolás modellre, modellcsere, `ml/**`, valós korpusz
a repóban, CI-workflow módosítás, UI a telefonon.

## 4. Engedélyezett fájlok

| Útvonal | Miért |
|---|---|
| `lib/features/live/domain/evaluation/recognition_release_gate.dart` | kapu-modell + kiértékelés |
| `lib/features/live/data/evaluation/recognition_report_renderer.dart` | JSON/MD/HTML ugyanabból a forrásból |
| `evaluation/recognition/recognition_release_gate.json` | verziózott küszöbök |
| `tool/recognition_report.dart` | CLI: report + kapu |
| `test/features/live/evaluation/recognition_release_gate_test.dart` | fail-closed mátrix |
| `test/features/live/evaluation/recognition_report_renderer_test.dart` | három formátum, determinizmus |
| `docs/eval/recognition-dashboard.md` | olvasási útmutató |
| `docs/rounds/e14-r09-baseline-dashboard-and-release-gate.md` | §10 handoff |

**Tilos zóna:** minden más — kiemelten `docs/eval/recognition-release-guard.md`
(E14-R01 rekordja), `ml/**`, `lib/features/live/engine/**`, `assets/**`,
`docs/adr/**`, `.github/workflows/**`, `tools/round-gate.sh`.

## 5. Kötött architekturális döntések (ADR 0361)

### 5.1 A kapu fail-closed

Hiányzó metrika = **FAIL**, nem „nincs adat, átengedjük". **NEM elfogadható**
gyengítés: `null` → `skip`, vagy default-érték behelyettesítése a hiányzó
metrika helyére.

### 5.2 A küszöbfájl verziózott, és a report hivatkozza

A `recognition_release_gate.json` gyökerében `schemaVersion` és
`thresholdsVersion`; a report minden kapu-ítélethez leírja, MELYIK verzió
alapján döntött.

### 5.3 Egy forrás, három formátum

A JSON, a Markdown és a HTML UGYANABBÓL a köztes modellből készül; tilos
külön-külön összeállítani őket (különben elcsúsznak).

### 5.4 A három esemény-kategória külön látszik

`confidentWrong`, `uncertainCorrect`, `rejected` külön számláló; egyik sem
olvad be az „accuracy" számba.

### 5.5 A baseline felülírása emberi döntés

A kapu-fájl küszöbeinek lazítása a kód-oldalon nem lehetséges: a fájl a
`docs/eval/recognition-dashboard.md` szerint review-hoz kötött, és a teszt
rögzíti az aktuális Alpha-értékeket.

## 6. Acceptance criteria

1. Hiányzó metrika esetén a kapu ítélete **FAIL**, és a hiányzó metrika neve
   megjelenik az indoklásban.
2. A küszöb-összehasonlítás mindhárom cellája mérve, az Alpha irány-küszöb
   (0,90 accepted direction accuracy) példáján: a küszöb **alatt** (0,899) →
   FAIL; **rajta** (pontosan 0,900) → PASS, mert a határ az elfogadó oldalhoz
   tartozik; **fölött** (0,901) → PASS.
3. A három formátum ugyanazokat a számokat tartalmazza (a teszt a Markdownból
   és a HTML-ből visszaolvasott értékeket a JSON-hoz hasonlítja).
4. A `confidentWrong` / `uncertainCorrect` / `rejected` számlálók külön
   szerepelnek, és a `rejected` NEM számít hibás találatnak.
5. Kétszeri futtatás bájtra azonos JSON-t és Markdownt ad.
6. A report minden kapu-ítéletnél megnevezi a `thresholdsVersion`-t.
7. Ismeretlen `schemaVersion` a kapu-fájlban típusos hiba, nem default.

### 6.1 Mérce-mátrix — melyik hibás implementációt melyik cella fogja pirosra

| Hibás implementáció | Melyik cella vált PIROSRA |
|---|---|
| Hiányzó metrika → `skip` | 1. pont FAIL-cellája |
| A küszöb-összehasonlítás szigorú (`>`) | 2. pont **rajta (0,900)** cellája |
| A HTML külön számol kerekítést | 3. pont formátum-egyezés cellája |
| A `rejected` beleszámít a hibás találatokba | 4. pont cellája |
| A renderer időbélyeget ír a kimenetbe | 5. pont bájtra-azonos cellája |
| Ismeretlen séma-verzió → default küszöbök | 7. pont típusos-hiba cellája |

## 7. Kötelező ellenőrzések

```bash
tools/round-gate.sh test/features/live/evaluation
```

Külön processzben futó `format` → `analyze` → célzott teszt → `architecture`
(AGENTS.md §12). `&&` láncolás tilos (L05/L09). CI-dispatch/PR/merge
Claude-oldal.

### 7.1 Falszifikációs cella

A §10-ben dokumentáld: a hiányzó-metrika ág ideiglenes `skip`-re állításával az
1. pont cellája **PIROS**, visszaállítva **ZÖLD**.

## 8. Implementációs sorrend

1. Kapu-modell + küszöbfájl + fail-closed teszt.
2. Köztes report-modell.
3. Renderer (JSON → MD → HTML) + determinizmus-teszt.
4. CLI + doksi.

## 9. Kockázatok

- **A kapu túl korai szigora:** a küszöbök az Alpha-szintet rögzítik; ha a
  jelenlegi baseline alatta van, az a kapu HELYES viselkedése, nem hiba — a
  release-döntés emberi.
- **HTML-generálás mérete:** a renderer maradjon sablon-alapú, külső
  függőség nélkül (nincs új pubspec-függés — az a tilos zóna).
- **Átfedés az `E14-R08`-cal:** a metrikák SZÁMÍTÁSA ott van; itt csak
  olvasás és megjelenítés történik.

## 10. Implementation handoff — az implementer tölti ki

## 11. Review — a Claude tölti ki
