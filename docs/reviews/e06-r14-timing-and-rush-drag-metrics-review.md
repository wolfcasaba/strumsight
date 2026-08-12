# E06-R14 — Review

Brief: `docs/rounds/e06-r14-timing-and-rush-drag-metrics.md`  
Diff: `76f18991..8e6733cb`  
Reviewer: Codex (orchestrator), independent isolated clone  
Dátum: 2026-08-12  
Verdikt: **APPROVED**

## Összegzés

BLOCKER: 0 · MAJOR: 0 · MINOR: 1 · NOTE: 2

Az R14 a tíz target és tíz, külön azonosítójú free-play timing metrikát,
minimum-minta kaput és evidenciára visszamutató hotspotokat adja. A kezdeti
security review két MAJOR és két MINOR leletét hozta; a három blokkoló
input-/confidence-lelet ugyanazon branch két javító commitjában (`0fb01d48`,
`8e6733cb`) zárult. A scope, architektúra és termékhatárok megfelelnek.

## Acceptance criteria

| Kritérium | Teljesült | Bizonyíték |
|---|---|---|
| Előjel- és on-time mátrix | ✅ | `timing_metrics_test.dart` sign + 124/125/126 ms cellák |
| p90, gate, streak, arányok | ✅ | ugyanott: 162 ms p90, 7/8/9, streak, 3/10 és 1/8 |
| Target/free-play ID elkülönítés | ✅ | katalogus-teszt és `TimingMetricSuiteIds` |
| Hotspot referenciális integritás | ✅ | `timing_hotspots_test.dart` |
| ARB paritás és külön rush/drag kulcs | ✅ | `check_l10n_parity.dart` green |
| Véges/range property | ✅ | `analysis_timing_property_test.dart`, `PROPERTY_SEED=42` |
| Runtime fail-closed gate | ✅ | `MetricGate` runtime `ArgumentError`; mutációs próba piros, visszaállítva zöld |
| Gyenge coverage nem ad hamis magas confidence-et | ✅ | `8/1007` regressziós cella, `timing_metrics_test.dart` |

## Scope-audit

`python3 tools/scope-audit.py --repo /tmp/review-e06-r14 --brief ... --base
76f18991` → **OK**, 13 módosított path; minden a brief által engedélyezett.
`git diff --check 76f18991..8e6733cb` → zöld.

## Megállapítások

### F1 — MAJOR — Runtime minimum-gate only asserted

- **Státusz:** FIXED (`0fb01d48`)
- A release-ben eltűnő assert helyett a `MetricGate` runtime `ArgumentError`-t
  dob; 0/negatív küszöbökre regressziós teszt készült.

### F2 — MAJOR — Sparse target evidence high confidence-et örökölt

- **Státusz:** FIXED (`8e6733cb`)
- A target confidence ma az R13 értékét a `min(matched/expected,
  matched/observed)` coverage faktorral csökkenti; teljes coverage-nél változatlan.

### F3 — MINOR — Free-play NaN input confidence

- **Státusz:** FIXED (`0fb01d48`)
- A free-play boundary a nem véges observed confidence-et publikálás előtt
  elutasítja; a `double.nan` regressziós cella zöld.

### F4 — MINOR — Free-play nearest-beat párosítás skálázódása

- **Státusz:** OPEN, follow-up R14 consumer-wiring előtt
- **Fájl:** `timing_metrics.dart`
- A jelenlegi, még bekötetlen út `O(observed × beats)` keresést használ.
  Consumer/UI-bekötés előtt kétmutatós/bináris keresés vagy explicit
  cardinality/cancellation korlát szükséges.

## Gate-bizonyíték

Az izolált `/tmp/review-e06-r14` klónban futtatva:

```bash
tools/round-gate.sh test/features/audio_analysis test/property test/app
```

Mind a nyolc lépés zöld: format, analyze, a három tesztcsoport,
architecture, secrets és l10n. A kód-mutatációs próba a minimum-kapu
`8 → 1` változatával célzottan piros lett, majd visszaállítva zöld.

## Merge-döntés

Lokális review: jóváhagyva. A merge további feltétele az exact-SHA teljes CI,
property gate, release APK és Router CI success.
