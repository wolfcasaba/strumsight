# E06-R12 — Független review

- **Brief:** `docs/rounds/e06-r12-beat-grid-and-tempo-curve.md`
- **Vizsgált implementáció:** `ea3e2ca0` (javítás); eredeti implementáció: `31d1663a`
- **Bázis:** `49900aae`
- **Reviewer:** Terra orchestrátor (implementer: `sonnet-impl`)
- **Dátum:** 2026-08-12
- **Verdikt:** APPROVED

## Ellenőrzött bizonyítékok

- Gépi scope-audit: `ok`, 11 módosított útvonal, mind a brief allowlistjében.
- Izolált klón: `/tmp/review-e06-r12-remote`, exact HEAD `31d1663a`.
- `tools/round-gate.sh test/features/audio_analysis test/property test/features/analyze`:
  **MINDEN GATE ZÖLD**.
- Mutáció: a target-first visszatérés kikapcsolása a
  `beat_grid_estimator.dart:93` sorban a
  `beat_grid_estimator_test.dart` target-celláját pirosra vitte; visszaállítva.
- Mutáció: a stabil alsó küszöb `>=` → `>` cseréje a
  `tempo_curve_builder.dart:139` sorban a pontosan 114.0 BPM tesztet pirosra
  vitte; visszaállítva.

## Leletek

| Súlyosság | Hely | Lelet | Bizonyíték / javítási irány |
|---|---|---|---|
| MAJOR | `lib/features/audio_analysis/engine/rhythm/tempo_curve_builder.dart:15-55` | Az exportált `TempoCurve` konstruktor csak a `legacyBpm` értéket validálja. `medianBpm`, `iqrBpm`, `driftSlopeBpmPerMinute` és `stableRegionRatio` elfogadhat `NaN`/végtelen (a ratio negatív vagy 1 fölötti is lehet), noha a §5.5 és §6 NaN-mentes tempo curve-öt ír elő. | Eltávolítandó review-próba: `TempoCurve(status: CapabilityStatus.available, legacyBpm: 120, medianBpm: double.nan)` **nem dobott**; a próbateszt exit 1-gyel bukott, mert `throwsArgumentError`-t várt. A javítás validálja az összes opcionális számszerű summary mezőt (median `(0,400]`, IQR `>=0`, slope véges, stable ratio `[0,1]`) és teszteli az elutasítást a már engedélyezett `tempo_curve_builder_test.dart`-ban. |

## Javítási re-review

Az azonos `sonnet-impl` motor javító commitja `ea3e2ca0` kizárólag a kijelölt
production- és tesztfájlt módosította; a scope-audit `ok` (2 útvonal). A
`TempoCurve` most rejectálja a nem véges/tartományon kívüli `medianBpm`,
`iqrBpm`, `driftSlopeBpmPerMinute` és `stableRegionRatio` értékeket. A
regressziós tesztek külön mérik a NaN, végtelen, alsó/felső határ és érvényes
határérték cellákat (45 célzott teszt zöld).

Friss izolált klón, exact `ea3e2ca0`: a kötelező
`tools/round-gate.sh test/features/audio_analysis test/property test/features/analyze`
ismét **MINDEN GATE ZÖLD**. A két korábbi mutációs próba már az eredeti
implementációban bizonyította a target-first és az inkluzív stabil-küszöb
mércéit; mindkettő visszaállítva, a review-klón tiszta.

## Merge-döntés

Nincs nyitott BLOCKER vagy MAJOR. A független review APPROVED; merge csak az
exact végleges branch-SHA-n zöld Full Gate és Router CI után engedett.
