# Kiegyensúlyozott chord-korpusz — szerződés és felvételi terv (E14-R25)

- **ADR:** [0538](../adr/0538-chord-corpus-manifest-and-synthetic-generator.md)
- **Séma:** [`evaluation/recognition/chord_corpus_manifest_schema.json`](../../evaluation/recognition/chord_corpus_manifest_schema.json)
- **Validátor:** `lib/features/live/domain/evaluation/chord_corpus_manifest.dart`
- **Állapot:** a **szerződés + validátor + szintetikus smoke-korpusz** kész;
  **valós korpusz nincs**, tehát a §7.4/§7.5 chord-sorok mérése továbbra is
  NEEDS-MEASUREMENT.

## 1. Mit ellenőriz a validátor

1. **Minden felvételi körülmény kötelező**: `voicing`, `capo`, `pickStyle`,
   `loudness`, `room`, `distanceCm`, `guitar`, `player`, `device`,
   `durationMs`, `tempoBpm`. Hiányzó mező = tipizált hiba a pontos JSON
   útvonallal (`corpus.items[3].device`), nem csendes `null`.
2. **Zárt szótár**: a `label` a 24 támogatott maj/min osztály valamelyike vagy
   a fenntartott `noChord`. Egy `Csus4` **elutasítás** — a nyílt halmazú
   akkord az open-set korpuszba tartozik (E14-R32), nem ide.
3. **Osztály-egyensúly riport** (`classBalance(minimumSupport: n)`):
   osztályonkénti support, a hiányzó osztályok listája, a minimum alatti
   osztályok listája **névvel**, N.C.- és hard-negatív darabszám, valamint a
   hard-negatív arány (`null`, ha a korpusz üres — sosem `0`).
4. **Grouped-split diszjunktság**: `buildFolds(strategy)` a SHIPPED
   `recognition_split.dart` buildert és `LeakageDetector`-t hajtja meg, tehát
   a szivárgás-szabály egyetlen implementációban él.
5. **Hard-negatív invariáns**: `hardNegativeCategory` csak `noChord` címkével.
6. **Szintetikus korpusz visszautasítása**: `gateEvidenceRefusal` nem `null`
   egy `synthetic` korpuszra, és megnevezi a korpuszt — a kapu-bizonyíték
   sosem lehet generált audió (Ch14 §12/2).

## 2. A szintetikus generátor (kizárólag a validátor hajtására)

`test/features/live/evaluation/support/synthetic_chord_corpus.dart` —
seedelt, determinisztikus Karplus–Strong pengetés + lecsengő harmonikus
sorozat, minden támogatott címke × 3 voicing × 3 tempó (alapból 216 tétel).
A manifest `corpusKind: synthetic`, a `corpusSha256` maga is önleíró
(`synthetic:seed=…`). **Semmilyen itt mért szám nem a termék mérése.**

Használata: a validátor és a dekóder-plumbing tesztelése
(`chord_engine_comparison_harness_test.dart` fixtúrái is innen jönnek).

## 3. A valós út: `chord-train.yml` + GuitarSet

```bash
gh workflow run chord-train.yml
```

(A workflow `push`-ra is indul, ha `ml/chords/**` változik.) Letölti a
Klangio-t (pinned SHA) és a **GuitarSet**-et (Zenodo): valódi gitár, valódi
akkordcímke, gitáros-szintű LOGO. Ezen tehát **ténylegesen mérhető** az
osztályonkénti minimum-support és a gitáros szerinti grouped split.

A GuitarSet-ből előálló manifest kitöltendő mezői:

| Mező | GuitarSet-ből | Megjegyzés |
|---|---|---|
| `player` | ✅ (guitarist id) | a LOGO fold kulcsa |
| `guitar` | ⚠️ konstans | egy hangszer-elrendezés |
| `device` | ❌ | **nincs telefon-mikrofon** |
| `room` / `distanceCm` | ❌ | stúdió-elrendezés |
| `capo`, `pickStyle`, `loudness` | ❌/részben | nem kontrollált dimenzió |
| `label`, `voicing`, `tempoBpm`, `durationMs` | ✅/részben | a címke és az idő megvan |

## 4. Ami csak a felhasználó felvételeivel teljesíthető (§7.1)

8 gitáros · 6 telefonmodell · 4 gitár · pick és finger · quiet/medium/loud ·
≥4 szoba és több telefon–gitár távolság · 24 kiegyensúlyozott osztály ·
hard-negatív audió. A rögzítendő mezők listája:
[training-and-holdout-repro.md §4](training-and-holdout-repro.md).
Nyers audió a repóba nem kerül — csak a manifest és a `corpusSha256`.
