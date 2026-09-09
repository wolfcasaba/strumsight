# E14-R33 — Chord release-kapu sorok és a chord-sáv rolloutja

- **Státusz:** LESZÁLLÍTVA (sorok + clamp) / **PARTIAL** (a számok mérése hiányzik)
- **ADR:** [`0541`](../adr/0541-chord-gate-rows-and-rollout.md)
- **Csomag:** PKG-B · **Készült:** 2026-09-09
- **Doksi:** [`docs/eval/release-gate-stages.md`](../eval/release-gate-stages.md)

## 1. Cél

A Ch14 §7.5 chord Beta célok kerüljenek be a kapu-fájlba **letiltva**, kapjon
a chord-sáv saját rollout-clampet, és a nem ábrázolható kapuk **maradjanak
ki** — hamis metrika-út helyett dokumentált hiány.

## 2. Mért kiindulóállapot

- Három chord Alpha sor (weighted accuracy 0,80 · macro-F1 0,70 ·
  N.C./unknown F1 0,88); a §7.4 további sorai és a teljes §7.5 hiányzik.
- `falseVisibleChordEventsPerMinute` **létezik** (ADR 0521 D1); a
  `chordMacroF1.perLabel` blokkból a leggyengébb recall **származtatható**.
- `confirmed accepted accuracy`, `chord transition p50/p95` és
  `event finalization flip` mögött **nincs metrika**.
- A baseline chord accuracy 0,671 — a kapu piros.

## 3. Scope

BENNE: öt letiltott §7.5 Beta sor; a `chordMacroF1.weakestSupportedRecall`
származtatott extractor; a chord-sáv clampje (a `chord` + `shared` sorokra);
a nem ábrázolható kapuk dokumentált kihagyása.

KÍVÜL: a §7.4 két újonnan ábrázolható Alpha sora (ADR 0541 D3 — az élő Alpha
kapu változatlan marad); a feature-flag registry (PKG-D).

## 4. Fájlok

Módosított (E14-R24-gyel közösen):
- `evaluation/recognition/recognition_release_gate.json` (chord Beta sorok)
- `lib/features/live/domain/evaluation/recognition_release_gate.dart`
  (`chordMacroF1.weakestSupportedRecall` + a fenntartott címkék halmaza)
- `test/features/live/evaluation/recognition_release_gate_test.dart`
- `test/features/live/evaluation/rollout_licence_test.dart`
- `docs/eval/release-gate-stages.md`

## 6. Acceptance

| # | Kritérium | Állapot |
|---|---|---|
| 1 | Az öt §7.5 chord Beta sor a fájlban, mind letiltva | **PINNED-BY-TEST** |
| 2 | A leggyengébb támogatott recall kihagyja a `noChord`/`unknown` címkéket | **PINNED-BY-TEST** |
| 3 | Nulla supportú osztály nem számít „0 recall”-nak; ha nincs támogatott osztály, az érték `null` → FAIL | **PINNED-BY-TEST** |
| 4 | A chord-rolloutot a strum-bukás nem fogja, a shared-bukás igen | **PINNED-BY-TEST** |
| 5 | A chord-sávon `beta` elérhetetlen a letiltott sorok miatt | **PINNED-BY-TEST** |
| 6 | Nincs kapu-sor nem létező metrikára | **PINNED-BY-TEST** (a nem létező `metricPath` tipizált hiba) |
| 7 | Bármely chord Beta/Alpha küszöb teljesülése | **NEEDS-MEASUREMENT** |
| 8 | Model card ↔ manifest osztálylista egyezés | **PINNED-BY-TEST** (`chord_corpus_manifest_test.dart` gépi tükör) |
| 9 | Device-mátrix, rollback-gyakorlat | **NEEDS-MEASUREMENT** (ember + eszköz) |

## 7. Verifikáció

Lokális gate nem futtatható; a cellák a §6-ban.

## 10. Handoff

- **PKG-D:** a `chordModelRolloutStage` mező már a fán van, alapértéke `off`
  (részletek: `e14-r24-gate-stages-and-rollout.md` §10).
- **PKG-E:** amíg a chord-sáv effektív fokozata `off`, a felhasználó a legacy
  NNLS eredményét látja; a CRNN a shadow-ágon mérhető.
- **Következő chord-mérési kör:** a §7.4 két hiányzó Alpha sorának
  bekapcsolása, amint a korpusz létezik (ADR 0541 D3).
