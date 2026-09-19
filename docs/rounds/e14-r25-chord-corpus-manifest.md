# E14-R25 — Kiegyensúlyozott chord-korpusz: manifest-szerződés és szintetikus generátor

- **Státusz:** LESZÁLLÍTVA (szerződés + validátor + generátor) / **PARTIAL** (valós korpusz nincs)
- **ADR:** [`0538`](../adr/0538-chord-corpus-manifest-and-synthetic-generator.md)
- **Csomag:** PKG-B · **Készült:** 2026-09-09
- **Doksi:** [`docs/eval/chord-corpus-plan.md`](../eval/chord-corpus-plan.md)

## 1. Cél

A Ch14 §7.1 korpusz **alakja** legyen gépi szerződés, mielőtt bárki felvenné:
kötelező felvételi metaadatok, osztály-egyensúly riport, grouped-split
diszjunktság, hard-negatív arány — plusz egy determinisztikus **szintetikus**
korpusz, amivel a validátor és a dekóder-plumbing hajtható.

## 2. Mért kiindulóállapot

- Nincs chord-korpusz manifest-szerződés; a `baseline_manifest_schema.json`
  a legacy DSP baseline-t írja le, nem egy felveendő korpuszt.
- Klangio: 82 felvétel / 3 gitáros / egy elrendezés → device- és
  guitar-szerinti grouped holdout **nem definiálható**.
- `chord-train.yml` letölti a GuitarSet-et: gitáros-szintű LOGO ✅,
  telefon-mikrofon / szoba / capo / pick-finger ❌.

## 3. Scope

BENNE: JSON-séma + kézi validátor; osztály-egyensúly és minimum-support
riport; grouped-split a SHIPPED builderrel; szintetikus generátor
(teszt-oldalon); doksi + ADR.

KÍVÜL: `test/support/synth.dart` (más csomagok közös fájlja — érintetlen);
bármely valós felvétel; a `chord-train.yml` (tiltott zóna, változatlanul
használható).

## 4. Fájlok

Új:
- `evaluation/recognition/chord_corpus_manifest_schema.json`
- `lib/features/live/domain/evaluation/chord_corpus_manifest.dart`
- `test/features/live/evaluation/support/synthetic_chord_corpus.dart`
- `test/features/live/evaluation/chord_corpus_manifest_test.dart`
- `test/features/live/evaluation/synthetic_chord_corpus_test.dart`
- `docs/eval/chord-corpus-plan.md`

## 6. Acceptance

| # | Kritérium | Állapot |
|---|---|---|
| 1 | Minden felvételi körülmény kötelező; hiány = tipizált hiba úttal | **PINNED-BY-TEST** |
| 2 | Zárt címke-szótár; `Csus4` elutasítva | **PINNED-BY-TEST** |
| 3 | A szótár tükrözi az `assets/ml/model_manifest.json` 25 osztályát | **PINNED-BY-TEST** (gépi tükör) |
| 4 | Osztály-egyensúly riport nevesíti a hiányzó/gyenge osztályokat | **PINNED-BY-TEST** |
| 5 | Grouped split a shipped leakage-detektorral; hiányzó kulcs = hiba | **PINNED-BY-TEST** |
| 6 | Hard-negatív csak `noChord` címkével | **PINNED-BY-TEST** |
| 7 | Szintetikus korpusz kapu-bizonyítéknak elutasított, megnevezve | **PINNED-BY-TEST** |
| 8 | A generátor determinisztikus seedre, és seedenként különbözik | **PINNED-BY-TEST** |
| 9 | Osztályonkénti VALÓS minimum-support, telefon/szoba/távolság fedés | **NEEDS-MEASUREMENT** (§7.1 korpusz + `chord-train.yml`) |

## 7. Verifikáció

Lokális gate nem futtatható. A `synthetic_chord_corpus_test.dart` szándékosan
rövid (0,2 s/tétel, 4 címke), hogy a suite gyors maradjon; az alak azonos a
teljes 24-címkés sweep-pel.

## 10. Handoff

- **Felhasználó:** a felvételi mezőlista és a diszpécsek
  `docs/eval/training-and-holdout-repro.md` §4-ben; nyers audió a repóba
  **nem** kerül, csak a manifest + `corpusSha256`.
- **PKG-B (következő chord-mérési kör):** GuitarSet-ből előálló manifest,
  majd a §7.4 két hiányzó Alpha sorának bekapcsolása (ADR 0541 D3).
