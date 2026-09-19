# ADR 0548 — Strum shadow mód az alkalmazásban: korlátos, Lab-látható összehasonlítás a meglévő kimeneti seam-en

**Státusz:** elfogadva (2026-09-09) · **Kör:** E14-R23 · **Kapcsolódó:** ADR 0545 D6 (seam), ADR 0542 D2 (zászlópár), ADR 0271 (UNKNOWN > CONFIDENTLY WRONG)

## Kontextus (mért)

- `recognitionShadowModeEnabled` a kör előtt **egyetlen fogyasztóval sem
  rendelkezett** a `lib/**`-ben (a `grep` csak a definíciót és a teszteket
  találta). Shadow-plumbing tehát nem volt, csak zászló.
- PKG-A leszállította a **seam-et**
  (`lib/features/live/engine/recognition_shadow_observer.dart`): egyetlen
  hívási pont a `LivePipeline.addChunk`-ban, `void` visszatérés, névvel adott
  argumentumok (`mode`, `frame`, `chord`, `strum`), no-op null objektummal.
- PKG-D leszállította a **kaput**: `recognitionShadowModeEnabled &&
  strumModelRolloutStage.runsInference`, aszimmetrikus ÉS, mindkét oldalon
  fail-closed alapértékkel, és `shadow.isUserVisible == false`.
- A seam **kimeneti csap**: a `LiveFrame`-et és a két tipizált predikciót adja
  át, **jellemzőt (log-mel/CQT keretet) nem**. A terv §4 (R23) továbbá
  kimondja: „nincs második FFT".
- A `RealStrumEngine` izolátum-protokollja a `_fromDsp` porton **csak
  `LiveFrame`-et** továbbít; az izolátumban létrehozott megfigyelőnek nincs
  visszaútja a UI izolátumhoz, a gyár pedig 0 argumentumú top-level függvény,
  tehát `SendPort`-ot sem tud kapni.

## Döntések

**D1 — A kapu EGY helyen dől el: `RecognitionShadowGate.fromFlags`.**
A két félből álló ÉS-t egyetlen tiszta függvény értékeli ki, és semmi más
bemenete nincs (nem Lab-kapcsoló, nem debug-build, nem felhasználói
beállítás). Ez a PKG-D „consumed-by" szerződésének a másik fele. Zárt kapunál
a session **nem épít pipeline-t, nem parse-ol modellt és egyetlen CQT keretet
sem számol** — a teszt nem „lefutott, de eldobtuk" állapotot mér, hanem azt,
hogy a szándékosan hibás bájtokat **meg sem próbálta** betölteni.

**D2 — Két sáv, két megfigyelő, egy fan-out.**
A strum- és az akkord-sáv külön zászlópáron lóg, ezért két külön
`RecognitionShadowObserver`, amelyeket a
`CompositeRecognitionShadowObserver` fűz a seam egyetlen hívási pontjára.
`try`/`catch` nincs: egy hibás megfigyelőnek hangosan kell elszállnia, nem
néma no-op-pá válnia (AGENTS.md).

**D3 — Amit a strum-sáv MÉR, pontosan (és amit nem).**
JELÖLT = a modell saját verdiktje az onsetre: a `pDown`/`pUp`/`pNoStrum`
argmax-a, a szerződés saját absztenciós szabályával
(`StrumPrediction.decision == uncertain`). PRODUKCIÓ = amit a pipeline
ténylegesen **kiadott** arra az onsetre (`frame.latestStrum` azon a
képkockán, ahol a `strumSeq` előrelép).

Ez tehát **nyers modell-verdikt vs. szállított kimenet**: azt méri, milyen
gyakran változtat az irány-kapu, a no-strum elnyomás és a kiadási kadencia a
modell válaszán. **NEM** futtat második inferenciát egy MÁSIK hálóval — a
seam kimenetet ad, nem jellemzőt, a terv pedig tiltja a második FFT-t. Egy
valóban különböző jelölt-háló összehasonlításához **jellemző-csap** kell a
`live_pipeline.dart`-ban; a pontos patch a kör jelentésében szerepel, és
**nem ebben a körben** landol. Ez a kör tehát a shadow-INFRASTRUKTÚRÁT és a
strum-sáv verdikt-összehasonlítását szállítja; a „candidate model" szó
szigorúbb olvasata **NEM MÉRT** és nem is állított.

**D4 — Minden tárolás korlátos, konstrukciós időben lefoglalva.**
`ShadowRingBuffer` fix kapacitású, legrégebbit-eldobó gyűrű; a konfúziós
mátrix egyetlen 26×26-os `Int32List`; a latencia-hisztogram egyetlen
`Int32List`. A rögzítés útján a **minta-objektumon kívül nincs allokáció**,
és a gyűrű megtelte után az objektumszám sem nő. Ez a Ch14 Kör 22 memória-
kérdésének a **strukturális** fele; a tényleges eszközmérés továbbra is
NEEDS-MEASUREMENT, és a kód sehol nem tesz úgy, mintha megvolna.

**D5 — Az arány NULL, ha nincs mit összehasonlítani.**
`agreementRate` üres ablakon `null`, nem `0.0` és nem `1.0`; a Lab „nincs
összehasonlítható" sort ír, nem `0%`-ot. A „a modell nem volt ott"
(heurisztikus út) külön számláló a „a modell nem válaszolt" (absztenció)
mellett — a kettő összemosása pontosan az a hiba, amit a Ch14 §9 tilt.
A riport magával viszi a `RecognitionMode`-ot és a rollout-fokozatot is
(`RecognitionRuntimeInfo.recognitionMode` / `.shadowStage`), mert egy
`guided` mérés nem hasonlítható egy `free` méréshez.

**D6 — A futtató egy MÁSODIK, rövid életű pipeline a felvett PCM felett.**
Az izolátumbeli megfigyelőnek nincs visszaútja (lásd Kontextus), a
`real_strum_engine.dart` protokollja pedig PKG-A tulajdona. Ezért az
összehasonlítást a Lab „capture & analyze" útja hajtja: ugyanazon a rögzített
bufferen egy **külön** `LivePipeline` fut `compute()`-ban, a seam-en
keresztül. Következmények, kimondva:
- a produkciós út **konstrukció szerint** érinthetetlen (nincs közös objektum),
  és ezt a bit-azonossági cella külön is rögzíti;
- amit ez a forma **nem** tud megmutatni: a két pipeline belső állapotának
  elsodródása egy hosszú élő menet alatt. Ehhez az izolátum-protokoll
  bővítése kell — a patch a jelentésben van.

## Mit mérünk, és mit nem

| Állítás | Státusz |
|---|---|
| Zárt kapunál nulla inferencia és nulla modell-parse | **PINNED-BY-TEST** |
| A shadow kimenet soha nem ér el `LiveFrame`-et (bit-azonosság a seam-en) | **PINNED-BY-TEST** |
| A riport determinisztikus ugyanarra a PCM-re | **PINNED-BY-TEST** |
| A gyűrű és a lefoglalt tár konstans N képkocka után | **PINNED-BY-TEST** (objektumszám) |
| 10 perces valós A/B memória- és CPU-mérés eszközön | **NEEDS-MEASUREMENT** |
| Egy MÁSIK jelölt-háló futtatása ugyanazokon a jellemzőkön | **NOT DELIVERED** (jellemző-csap kell, patch a jelentésben) |
| Hogy a mért egyet-nem-értés zenei szempontból jó vagy rossz | **UNKNOWN** — nincs annotált korpusz a mérés mellé |
