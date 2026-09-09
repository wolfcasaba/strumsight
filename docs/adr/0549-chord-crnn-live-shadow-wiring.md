# ADR 0549 — A szállított Chord CRNN élő shadow bekötése: integritás-kapu, klip- és streaming-illesztő, gyök/minőség egyezési mátrix

**Státusz:** elfogadva (2026-09-09) · **Kör:** E14-R26 · **Kapcsolódó:** ADR 0548 (shadow-infrastruktúra), ADR 0355 (fail-visible aktiválás), ADR 0542 D2 (zászlópár)

## Kontextus (mért)

- `assets/ml/chord_crnn.bin` (CCRN v1, 100×144 CQT, 25 osztály) a fán van, de
  **egyetlen betöltője** `lib/features/analyze/providers/analyze_providers.dart`
  volt: a Live izolátum csak a **strum** súlyokat kapta meg
  (`real_strum_engine.dart::_liveCrnnWeights`). A Live akkordútja végig
  NNLS-chroma → `ChordDictionary` → `ViterbiChordDecoder`. Ez a Ch14 §4.5
  állítása, a kör előtt is igaz volt.
- A manifest bejegyzés **már létezett** és a deklarált sha256
  (`8f7596d4…09fc74`) **egyezik** az asseten futtatott sha256-tal (python,
  2026-09-09). A manifestbe tehát nem kellett új sort írni; a kör ehelyett
  gépi ellenőrzést ad rá.
- `assets/ml/model_manifest.json` **nem bundle-asset** (a `pubspec.yaml`
  csak a `.bin` fájlokat sorolja), tehát a futó app nem tudja megnyitni.

## Döntések

**D1 — Fail-VISIBLE aktiválás, `FallbackReason`-nel, és fail-CLOSED
integritás.**
`ChordShadowActivation.activate(bytes, expectedSha256:)` vagy egy futtatható
runnert ad, vagy egy zárt kódot: `assetMissing` (nincs/üres bájt),
`parseFailed` (rossz magic/verzió, csonka fájl **vagy hash-eltérés**),
`shapeMismatch` (a bin/osztályszám nem illik a build front-endjéhez). Néma
no-op nincs; a kód a `RecognitionRuntimeInfo.chordFallbackReason` mezőn és a
Lab panelen **lokalizált** szövegként jelenik meg (nyers enum-név sosem).
Hash-eltérésnél a modell **nem** töltődik be: olyan bájtoknak, amelyek nem az
átnézett bájtok, nincs mért viselkedésük.

**D2 — A manifest-hash konstansként él a kódban, gépi őrrel.**
Mivel a manifest nem asset, a futásidejű ellenőrzés egy Dart konstansra
(`ChordCrnnShadowRunner.shippedChordModelSha256`) támaszkodik. Hogy ez ne
tudjon elsodródni, egy teszt **három** értéket hasonlít össze: a lemezen lévő
asset tényleges sha256-át, a manifest deklarált értékét és a konstanst — a
modell cseréje a konstans frissítése nélkül **pirosít**, nem szállít
ellenőrizetlen blobot. Ugyanez a cella rögzíti a `format`, `format_version`,
`input_shape` és `output_classes` egyezést is.

**D3 — Az egyezési taxonómia ZÁRT: 26 osztály.**
`ShadowChordClass` = gyök (0..11) × majmin minőség, plusz `N.C.` és
`unknown`. Ettől a konfúziós mátrix **fix méretű tömb** lehet ahelyett, hogy
a két motor tetszőleges címkéivel nőne. A majmin redukció a szállított
`ml/chords/labels.py` szabályát tükrözi; mivel a `features/live` nem
függhet a `features/analyze`-tól (a függés fordítva már fennáll), a szabály
**duplikálva** van, és egy paritás-cella köti a
`MlChordDecoder.majminReduce`-hoz.

Két külön, szándékos döntés a „nincs akkord" körül:
- az **olvashatatlan** címke `unknown`, **nem** `N.C.` — a „nem tudom
  elolvasni" és a „nem szólt akkord" különböző leletek, összemosásuk
  hamisan növelné az N.C. egyezést;
- a képkocka, amelyen a produkció **nem adott ki** akkordot, `N.C.`-ként
  kerül a mátrixba. Ez tudatosan összemossa a csendet a „még nem elég
  magabiztos a latch"-csel, mert a képernyőt néző felhasználónak ez a kettő
  ugyanaz, és a szétválasztásukhoz olyan akkord-konfidencia mező kellene,
  amit a kiadott `LiveFrame` nem hordoz. Az összemosás **itt van kimondva**,
  nem egy arányban elrejtve.

**D4 — Két illesztő, egy modell; a streaming korlátai kimondva.**
- `runClip(pcm, sr)` — a teljes felvett buffer egy menetben (a `ChordCrnn`
  szekvenciahossz-független). Ez a **determinisztikus** út, ezért ezt hajtja
  a Lab összehasonlítás, és ezért tesztelhető egyáltalán a riport.
- `addPcm`/`poll()` — élő menethez: fix, **egyszer** lefoglalt PCM-gyűrű
  pontosan `windowFrames × hop` mintával; `emitEveryFrames` hoponként újra
  fut a modell a hátsó ablakon, és az **utolsó** keret poszteriorja a
  verdikt, a motor saját óráján bélyegezve.
- **Őszinte korlát:** a `CqtExtractor` középre párnáz, tehát a hátsó ablak
  legfrissebb kerete ott lát párnázást, ahol egy folytonos CQT jövőbeli
  audiót látna, és a GRU minden ablakon nulla állapotról indul. A streaming
  verdikt ezért **nem bit-azonos** a `runClip`-pel ugyanazon az audión, és
  hogy valós gitáron mekkora az eltérés, az **NEM MÉRT** (nincs eszköz és
  nincs korpusz ezen a gépen). Semmi lefelé nem kezeli nullának: a shadow
  riport összehasonlítási felület, sosem bemenet a felismerésbe.
- `windowFrames = 100` a **modell szerződése** (`train_chord.py`), nem
  hangolható paraméter. `emitEveryFrames = 8` riport-kadencia: CPU-t cserél
  összehasonlítási sűrűségre, és egyetlen felismerési küszöböt sem érint.

**D5 — `real_strum_engine.dart` NEM változott.**
Az akkord-súlyokat a Lab útja tölti be a fő izolátumon (a `rootBundle` úgyis
csak ott él), és a `compute()` hívás viszi át. Az izolátumbeli élő bekötéshez
szükséges minimális patch (`_DspInit.chordCrnnWeights` + egy
`ShadowSnapshot` üzenettípus a visszaúton) a kör jelentésében szerepel;
alkalmazása PKG-A fájljában külön döntés.

## Mit mérünk, és mit nem

| Állítás | Státusz |
|---|---|
| A kód-konstans, a manifest és az asset sha256-a azonos | **PINNED-BY-TEST** |
| Hiányzó / csonka / hamis hash-ű asset → tipizált `FallbackReason` | **PINNED-BY-TEST** |
| A címkelista index-azonos a szállított majmin taxonómiával | **PINNED-BY-TEST** |
| A klip-dekódolás determinisztikus, rácsa a CQT hop | **PINNED-BY-TEST** |
| A streaming gyűrű egyszer foglal és nem nő | **PINNED-BY-TEST** |
| NNLS ↔ CRNN egyezés valós gitáron, időben illesztve | **NEEDS-MEASUREMENT** |
| Latencia / memória eszközön | **NEEDS-MEASUREMENT** |
| Melyik akkordút a jobb | **UNKNOWN** — ez R27 kérdése, és korpusz nélkül nem dönthető |
