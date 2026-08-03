# E03-R12 — Standard MIDI importer review

Brief: `docs/rounds/e03-r12-midi-importer.md`
Diff: `origin/main...codex/e03-r12-midi-importer`
Reviewer: Codex / Terra
Dátum: 2026-08-03
Reviewed head: `f29773d` before this review-artifact commit
Verdikt: **APPROVED**

## Összegzés

**BLOCKER: 0 · MAJOR: 0 · MINOR: 0 · NOTE: 1**

Az előző review F1–F4 leletei zártak. A parser format 0-nál pontosan egy
MTrk chunkot követel; az azonos pitchű átfedések FIFO aktív-note sorral
mind megmaradnak, egyszeri warninggal; a meter és key meta események teljes
idővonala mapelődik; a MIDI track count pedig a közös, konfigurálható
`ImportLimits` policyben, a track parse előtt korlátozott.

## Független ellenőrzés

| Ellenőrzés | Eredmény |
|---|---|
| Izolált clone gate | PASS — format, analyze, 7 MIDI importer teszt, 6 malformed teszt, architecture |
| Scope audit | PASS — a produkciós/test/fixture diff a brief §4-ben szerepel; ez a review-fájl reviewer-artefaktum |
| `git diff --check origin/main...HEAD` | PASS a jelen review-fájl formázásával |
| F1 valódi mutáció | PASS — a format-0 `count != 1` őr ideiglenes eltávolításakor a saját regressziós teszt 1-es kóddal piros lett; a módosítás visszaállítva |

## Korábbi leletek lezárása

| Lelet | Státusz | Bizonyíték |
|---|---|---|
| F1: format 0 több track | CLOSED | `midi_parser_adapter.dart` format-0 őr + célzott mutáció-teszt |
| F2: azonos pitchű átfedés elveszik | CLOSED | per-key FIFO active-note lista, overlap warning és regressziós teszt |
| F3: későbbi meter/key meta esemény elveszik | CLOSED | teljes `MeterMap`/`KeyMap` iteráció és két-változásos snapshot teszt |
| F4: MIDI track-limit H3 | CLOSED | `ImportLimits.maxMidiTrackCount`, stable failure code, max−1/max/max+1 teszt |

## Note

- Az izolált klón legelső gate-je a generált `l10n` fájlok hiánya miatt 625
  diagnosztikával állt meg. `flutter pub get && flutter gen-l10n` után az
  azonos gate zöld lett; ez az ismert klón-bootstrap előfeltétel, nem az R12
  diff hibája.

## Merge-döntés

Lokális és független ellenőrzés alapján a diff jóváhagyott. A squash merge
feltétele még az exact-head Build Android APK CI teljes zöld eredménye,
beleértve a teljes Flutter suite-ot, a property gate-et és az APK-t.
