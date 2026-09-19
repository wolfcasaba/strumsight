# ADR 0544 — `RecognitionMode` és az expected-chord prior szigorú izolációja: additív bias helyett dokumentált tie-breaker

**Státusz:** elfogadva (2026-09-09) · **Kör:** E14-R30 · **Felülírja:** a round-137-es `ViterbiChordDecoder.expectedPrior` additív mechanizmusát (chunk 016 rec #1)

## Kontextus (mért)

- `lib/features/live/engine/dsp/viterbi_chord_decoder.dart` 96. és 108. sora
  (a kör előtti fán): `_delta[s] = sim[s] + (s == _expectedIdx ? expectedPrior : 0)`.
  Ez **additív bias a trellisben**, nem tie-breaker: minden képkockán újra
  hozzáadódik, tehát **halmozódik** az akkumulált útpontszámban.
- A prior beállítói: `practice_session_controller` →
  `live_practice_observation_gateway` → `real_strum_engine` →
  `live_pipeline.setExpectedChord`, illetve `learn_screen`.
- Az egyetlen védelem szabad játék módban `live_screen.dart:93`
  (`setExpectedChord(null)` belépéskor) — **konvenció, nem gépi őr**: ha egy
  hívó kihagyja, semmi sem lesz piros.
- `RecognitionMode` típus a kör előtt **nem létezett** a fán.
- Mit NEM tudunk: nincs mérés arról, hogy a prior a valós tanulói hibákon
  mennyit segített vagy ártott. A round-137-es 0,05 érték indoklása a
  chunk 016-ban „kicsi, a valós hasonlósági rés alatt marad" — ez **állítás,
  nem mérés**.

## Döntés

### D1 — `RecognitionMode` a felismerési domainben, KONSTRUKCIÓS paraméterként

Új típus: `lib/features/live/domain/recognition/recognition_mode.dart`

```dart
enum RecognitionMode { free, guided }
```

Két tag, nem három. A tervben szereplő `lab` **szándékosan kimarad**: nincs
fogyasztója, és egy nem használt állapot a kimerítő `switch`-ekben csak vak
ágat szül. A Live képernyő három termék-módja (Free Play / Guided Pattern /
Accuracy Check, R37) erre a kettőre **képződik le** — a leképezés PKG-F
feladata, nem ezé a körré.

A mód a motor **konstrukciós** paramétere (`LivePipeline({mode})`,
`RealStrumEngine({mode})`), **nem futásidejű setter**. Alapértéke `free`
(fail-closed: az a rezsim, amelyben semmi külső nem befolyásolja a verdiktet).
`RecognitionMode.allowsExpectedChordPrior` a szabály gépi olvasható alakja,
kimerítő `switch`-csel, `default` nélkül.

### D2 — A hint EGYETLEN hordozója egy csak guided módban építhető típus

```dart
final class ExpectedChordHint {
  const ExpectedChordHint._(this.label);
  static ExpectedChordHint? forMode(RecognitionMode mode, String? label);
}
```

A konstruktor privát, a fájl az egyetlen könyvtára, tehát **a fán sehol nem
lehet hintet előállítani** `forMode`-on kívül — és `forMode` `free` módban
`null`-t ad. `ViterbiChordDecoder.setExpected` szignatúrája `String?`-ről
`ExpectedChordHint?`-re változik.

Ettől az izoláció **strukturális**: szabad játékban nincs hint-ÉRTÉK, amit a
dekóder alkalmazhatna. Nem arról van szó, hogy a dekóder „figyelmen kívül
hagyja" — nincs mit figyelmen kívül hagynia.

Két független szűrőpont marad (defence in depth, mert a két oldal külön
izolátumban fut):

1. `RealStrumEngine.setExpectedChord` — a címke `free` módban **el sem hagyja
   a metódust**, az izolátum-határon nem megy át semmi;
2. `LivePipeline.setExpectedChord` — a másik oldalon újra átfut a
   `forMode`-on, mert az izolátum nem bízik a hívójában.

### D3 — Guided módban a prior TIE-BREAKER, nem bias: a trellisbe nem lép be

A hint **nem kerül bele** a trellis-rekurzióba. A trellis pontosan az, ami
prior nélkül lenne (bit-azonos). A kiolvasásnál — miután a prior-mentes
trellis kiválasztotta a győztest — az elvárt állapot **csak akkor** veheti át a
JELENTÉST, ha a képkocka valódi döntetlen, `expectedTieBreakBand = 0.05`
sávon belül **mindkét** mérőszámon:

1. akkumulált útpontszám: `best - delta[expected] <= band`, és
2. az adott képkocka nyers szótár-hasonlósága: `sim[best] - sim[expected] <= band`.

Mindkettő kell: (1) önmagában egy régi útelőnyt engedne dönteni, (2)
önmagában figyelmen kívül hagyná a szekvenciát. A tie-break **nem alkalmazható
a no-chord állapot ellen** (elvárás nem varázsol akkordot csendből).

A 0,05 érték **változatlanul átvéve** a törölt `expectedPrior`-ból: ez a kör a
mechanizmust cseréli, nem hangol (nincs mérés, ami új számot indokolna).

**Mit jelent ez számszerűen — őszintén:** mivel a trellis a hintet nem látja,
beállt állapotban minden nem-vezető állapot legalább `selfBonus = 0,22`-vel van
lemaradva (`gap = simVezető − simKövető + selfBonus`), ami **messze kívül van a
0,05-ös sávon**. Vagyis egy BEÁLLT trellisben a tie-break sosem tud tüzelni; a
gyakorlati hatása a szekvencia-kezdetre és egy váltás közvetlen környezetére
korlátozódik, ahol az akkumulált pontszámok tényleg egymáson vannak. Ez a
prior **jelentős gyengülése** a round-137-es viselkedéshez képest. A hatása a
valós tanórai pontosságra **ISMERETLEN** — nincs mérésünk. A kör ezt vállalja:
a Ch14 §12/1 szerint a küszöbök vak átírása tilos, a „hangos audió mindig
győz" garancia viszont nem opcionális.

### D4 — Az egyetlen viselkedésváltozás guided módban ez, semmi más

A `chord_matcher.dart` (legacy sablon-illesztő) **érintetlen**: nincs rajta
expected prior, és nem is a Live úton fut (a Live út NNLS-chroma →
`ChordDictionary` → `ViterbiChordDecoder`). A `decodeBatch` /
`decodeBatchFromScores` (Analyze, ML seam) sosem látta a priort, most sem.

### D5 — A mód minden diagnosztikai kimenetben rögzül

`LivePipeline.mode` olvasható getter; `ChordLatchDiagnostics.mode` és a
`RecognitionShadowObserver.onRecognitionFrame(mode: …)` is hordozza. Egy
`guided` módban felvett mérés **nem hasonlítható** egy `free`-hez.

**Amit itt NEM tettünk meg:** a `RecognitionRuntimeInfo` és az evaluation
manifest bővítése `mode` mezővel (a Ch14 §7 „minden export hordozza a
mode-ot" igénye). Mindkét fájl MÁS csomag kizárólagos tulajdona
(`recognition_runtime_info.dart` → PKG-E, `evaluation/**` → PKG-B), ezért a
patch a kör jelentésében van megfogalmazva, nem itt landolt. **Ez a kör tehát
a §7 elfogadási feltétel harmadik pontján PARTIAL.**

## Következmények

- `test/features/live/dsp/viterbi_decoder_test.dart` „ambiguous maj-vs-maj7
  evidence resolves to the expected chord" cellája a RÉGI (additív) viselkedést
  rögzítette — **frissítve**: tartós maj7 evidencia most `Cmaj7`-et ad, és a
  cella indoklása a levezetett `gap ≥ selfBonus > band` invariáns. Ezt a
  jelentés külön kiemeli.
- Az összes többi round-137/142 biztonsági cella (tiszta G, zajos G, csend,
  ismeretlen címke, reset) **változatlanul zöld** — a mechanizmus-csere a
  „soha ne írja felül az audiót" irányt csak erősíti.
- `live_screen.dart:93` konvenció-nullázása **feleslegessé válik** (de nem
  hibás); a fájl PKG-F tulajdona, a törlés az ő köre.

## Mit mér ez, és mit nem

| Állítás | Státusz |
|---|---|
| Free módban a hint bit-azonos kimenetet ad hint nélkülihez | **TESZTTEL RÖGZÍTVE** (`recognition_mode_isolation_test.dart`) |
| Free módban hint nem is építhető | **TESZTTEL RÖGZÍTVE** (típusszint + cella) |
| Guided módban egy tiszta audio-győztest a prior nem fordít meg | **TESZTTEL RÖGZÍTVE** (viterbi cellák, levezetett invariáns) |
| Guided módban a prior valódi döntetlent eldönt | **TESZTTEL RÖGZÍTVE** (egzakt aug-döntetlen, 0,8228 × 3) |
| A prior gyengülése javítja vagy rontja a tanórai pontosságot | **NEM MÉRT — ismeretlen** |
| A mód minden EXPORTBAN (runtime info, manifest) rögzül | **PARTIAL** — lásd D5 |
