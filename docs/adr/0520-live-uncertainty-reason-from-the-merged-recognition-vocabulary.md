# ADR 0520 — A Live képernyő „miért nem sikerült" állítása a MERGE-ELT felismerési szótárból jön, nem egy második, képernyő-lokális heurisztikából

- **Státusz:** Elfogadva
- **Kör:** `E14-R13` (Chapter 14 — Recognition Accuracy & Useful UI Recovery, Kör 13)
- **Dátum:** 2026-09-05
- **Implementer motor:** `sonnet-impl` (Claude Sonnet 5, `--effort high`)
- **Kapcsolódó:**
  [ADR 0505](0505-versioned-recognition-frame-contract-and-legacy-adapter.md)
  (D3: a **zárt, hatelemű** `RecognitionRejectReason`; D6: tipizált `fromJson`,
  ismeretlen név → hiba, nem néma `null`),
  [ADR 0516](0516-live-chord-decision-wiring.md)
  (D1/D5: a `LiveFrame` HORDOZZA a keret-szintű akkord-döntést és az okát),
  [ADR 0276](0276-stage-scaffold-owns-no-resources.md)
  (a Stage-slotok — a banner helye a `feedback` slot),
  [ADR 0271](0271-recognition-recovery-program.md)
  (`UNKNOWN > CONFIDENTLY WRONG`),
  [ADR 0277](0277-failure-presentation-model.md)
  (a felület hibakódot kap, nem kivételt; az ismeretlen kód is emberi szöveget kap),
  [ADR 0424](0424-localization-resilience-contract.md)
  (a `lib/l10n/app_{en,hu}.arb` **generált aggregátum**, a szerkeszthető forrás
  a `lib/l10n/base/` + `lib/l10n/features/<feature>_<locale>.arb` szegmens —
  a brief §0.0 és a HANDOFF ezt a szerződést „ADR 0307 §4" néven hivatkozza,
  a pre-flight mérése szerint tévesen: a `0307` a kör-pipeline
  áteresztő-programja, az l10n-szegmens szerződése a `0424`)

## Kontextus — a pre-flight MÉRT tényei (2026-09-05, `main @ 190a83e7`)

Ez a kör a **dispatch előtt** egyszer már H3-ra futott: az előre megírt briefje
2026-08-20-án, a `88e08e65` commiton készült, és a fa azóta elmozdult alatta
(a teljes diagnózis: `.pipeline/halt-detail-E14-R13.md`, lecke
[L646](../LESSONS.md#l646); a feloldó heal: squash `190a83e7`). A revideált
brief §0.0-ja négy tényt mért újra; ez az ADR a belőlük következő normatív
döntéseket rögzíti.

### 1. Az ok-szótár MÁR MERGE-ELVE VAN, és zárt

```
$ sed -n '/^enum RecognitionRejectReason/,/^}/p' \
    lib/features/live/domain/recognition/recognition_decision.dart
enum RecognitionRejectReason {
  lowConfidence, unstable, signalQuality, noChord, modelUnavailable, timeout;
```

**Hat** elem, `toJson`/`fromJson` párral, ahol az ismeretlen név tipizált hiba
(ADR 0505 D6). Egy MÁSODIK, UI-oldali ok-taxonómia (az eredeti brief §5.4-e
négyeleműt írt elő) pontosan az [L549](../LESSONS.md#l549) /
[L636](../LESSONS.md#l636) hibaosztály: két versengő definíció ugyanarra a
kérdésre.

### 2. A termelő be van kötve, a fogyasztó NULLA

```
$ grep -n "chordDecision:\|chordRejectReason:" lib/features/live/engine/dsp/live_pipeline.dart
405:      chordDecision: chord?.decision,
406:      chordRejectReason: chord?.rejectReason,

$ grep -rn "RecognitionRejectReason" lib/ --include=*.dart \
    | grep -v "domain/recognition\|model/live_frame\|public.dart\|live_pipeline"
(üres)
```

A `LiveFrame` mezői léteznek és töltve vannak (`live_frame.dart:76,80`), a
`LivePipeline.debugDeriveChordDecision` ma **három** okot állít elő
(`signalQuality`, `noChord`, `lowConfidence` — `live_pipeline.dart:334-348`),
a UI viszont **egyetlen** helyen sem olvassa őket.

### 3. A képernyő ma egy KÉPERNYŐ-LOKÁLIS heurisztikából mondja meg, mi a baj

```
$ sed -n '265,269p' lib/features/live/screens/live_screen.dart
    final isWeakSignal =
        !_paused &&
        frame.listening &&
        frame.inputLevel < SsSignalQualityIndicator.defaultWeakThreshold;
```

Ez az `isWeakSignal` hajtja a `feedback` slot `weakLabel`-jét
(`live_screen.dart:373` → `l10n.liveWeakSignal`) — nyers `inputLevel`-küszöb,
amely a felismerő tényleges verdiktjéről semmit nem tud. A „nincs akkord"
prompt (`liveWaitingForChord`) pedig a `ChordTimeline`-on BELÜL él
(`chord_timeline.dart:127`).

### 4. A Stage-elrendezés MÁR ELDŐLT

A képernyő az ADR 0276 `SsStageScaffold`-ját használja öt nevesített slottal
(`live_screen.dart:299,336,362,377,402`). Az eredeti brief §5.1–5.3-a és 6.
acceptance-pontja (hierarchia, a history másodlagossága, `reduce motion`, a CTA
három állapota) ezért **már merge-elt döntés**, saját futó mércével — nem
ennek a körnek a döntési helye.

## Döntés

### D1 — Egyetlen ok-szótár: a merge-elt, hatelemű enum

A Live képernyő felismerési okot **kizárólag** a
`RecognitionRejectReason` hat eleméből jelenít meg. Új UI-oldali
ok-kategória-halmaz, ok-összevonás vagy „egyéb" gyűjtőkategória **tilos**. Ha a
szótár bővül, az az `lib/features/live/domain/recognition/**` rétegé (ADR 0505
D3), nem a UI-é.

### D2 — A leképezés kimerítő `switch`, `default:` ág NÉLKÜL

Az ok → honosított szöveg leképezés kimerítő `switch`-csel készül. A `default:`
(illetve a `_`) ág **tilos**: egy jövőbeli enum-elem **fordítási hibát** adjon,
ne néma általánosítást. Ez a mechanikus megfelelője az ADR 0505 D6
fail-closed dekódolásának, és a mércéje az iterációs cella
(`RecognitionRejectReason.values` fölött, mindkét locale-on).

### D3 — A hat szöveg páronként KÜLÖNBÖZŐ, mindkét locale-ban

Egyetlen általános szöveg hatszor kiosztva formálisan teljesítené a D2-t,
miközben a felhasználó semmivel sem tudna többet. A distinctness ezért a
szerződés része, nem stílus-kérdés: mindkét locale-ban páronként eltérő
szöveget kell adni.

### D4 — A banner a `feedback` slotban él, és ott az EGYETLEN ok-állítás

A banner helye az ADR 0276 `feedback` slotja. Amikor
`frame.chordRejectReason != null`, a banner az egyetlen hely, ahol a képernyő a
felismerés kudarcának okát állítja — a `SsSignalQualityIndicator` általános
`weakLabel` szövege (`liveWeakSignal`) ilyenkor **nem jelenhet meg
egyszerre** a bannerrel. Két egyidejű, eltérő magyarázat ugyanarra a kudarcra
maga a hibaosztály, amit ez a kör megszüntet.

### D5 — A heurisztikus ág megmarad a „nincs döntés" esetre, érintetlenül

Amikor `frame.chordRejectReason == null` (megerősített akkord, vagy még
egyáltalán nincs döntés — pl. az első frame előtt), a MA MERGE-ELT viselkedés
**bitre változatlan**: a `weakLabel` és a `ChordTimeline`
`liveWaitingForChord` promptja pontosan úgy működik, mint ma. A kör **nem
távolít el** merge-elt állapotot; egy pontosabb forrást **ad hozzá** egy addig
lefedetlen ágra. A két merge-elt cella (`live_stage_test.dart` `liveWeakSignal`
⟂ `liveWaitingForChord`) ezért **átkötendő**, nem törlendő — cella törlése,
`skip`-je vagy gyengítése tilos ([L593](../LESSONS.md#l593)).

### D6 — A képernyő nem hoz felismerési döntést

A UI megjelenít. Küszöb, stabilizálás, abstention és ok-levezetés az R10–R12
rétegéé (ADR 0512 / 0516 / 0518). A banner nem következtet okot a nyers
`inputLevel`-ből, nem sorol össze két enum-elemet egy szövegre, és nem ír
`LiveFrame`-et.

### D7 — Az ok-szövegek FORRÁSA a `lib/l10n/base/` szegmens

A hat kulcs mindkét nyelven a `lib/l10n/base/app_{en,hu}.arb` **forrás**
szegmensbe kerül; a `lib/l10n/app_{en,hu}.arb` aggregátumot kizárólag a
`dart run tool/gen_l10n_segments.dart --write` írja (ADR 0424). Az
aggregátum kézi szerkesztése tilos — ez volt a kör eredeti haltjának mért
gyökéroka ([L469](../LESSONS.md#l469), [L646](../LESSONS.md#l646)), és a
`brief-lint` **S16** foka azóta gépi őre az osztálynak.

### D8 — A banner tördel; a támogatott textscale-határ 200%, inkluzív

A banner nem kaphat fix magasságot és nem csonkíthat: a támogatott felső
határ **200%** (a határ IDE tartozik), és alatta/rajta nincs `RenderFlex`
overflow. 200% fölött a kör garanciát nem vállal — ott a mérce annyi, hogy a
képernyő nem dob kivételt ([L517](../LESSONS.md#l517)).

## Következmények

- A `LiveFrame.chordRejectReason` mezőnek **első valódi fogyasztója** lesz; az
  ADR 0505 D3 szótára ezzel a termelő–szerződés–fogyasztó láncon végig zárt
  (az [L625](../LESSONS.md#l625) hibaosztály — „deklarált, de sehonnan ki nem
  olvasható enum" — erre a mezőre megszűnik).
- A `debugDeriveChordDecision` ma csak három okot állít elő; a másik három
  (`unstable`, `modelUnavailable`, `timeout`) a szerződés része, de a live
  pipeline-nak nincs útja hozzájuk. A banner ettől függetlenül **mind a hatot
  lefedi** (D2) — új ok-út BEVEZETÉSE külön kör, saját ADR-rel.
- A frame nélküli default állapotban `chordRejectReason == null`, tehát a
  banner nem látszik: a két merge-elt pixel-golden (`textScale 1.0` és `2.0`)
  **változatlan** kell maradjon. Ha elmozdul, az a D5 elhatárolásának
  szennyeződését jelzi, és a kör handoffjának meg kell neveznie a pontos
  widget-szintű okot.
- A Stage-slotok, a hero, a transport, a timeline és a BeatCounter
  elrendezése (ADR 0276), a `SsMotionScope`, a design-tokenek és a
  `recognition_release_gate.json` küszöblistája **nem** nyílik újra ebben a
  körben.

## Alternatívák, amelyeket elvetettünk

1. **Saját, négyelemű UI-taxonómia** (az eredeti brief §5.4-e). Elvetve: a
   merge-elt, zárt hatelemű enum mellé állított második szótár az L549/L636
   hibaosztály, és az ADR 0505 D3 fölé osztana új normát.
2. **`default:` ág egyetlen általános szöveggel.** Elvetve: a jövőbeli
   enum-bővítés némán, hibaüzenet nélkül általánosítana — pont az ellenkezője
   az ADR 0505 D6 fail-closed elvének.
3. **A heurisztikus `weakLabel` ág eltávolítása.** Elvetve: merge-elt
   viselkedést törölne egy olyan ágon (`chordRejectReason == null`), amelyet a
   döntés-alapú forrás nem fed le — regresszió lenne, nem tisztítás.
4. **A banner elhelyezése a `hero` vagy a `timeline` slotban.** Elvetve: az
   ADR 0276 a `feedback` slotot jelöli ki a felismerés minőségéről szóló
   visszajelzésnek; máshová téve a hero vagy a history merge-elt hierarchiája
   mozdulna el.
5. **A kulcsok felvétele a generált `lib/l10n/app_{en,hu}.arb`-ba.** Elvetve
   (és mérten teljesíthetetlen): az aggregátum frissességét a gate `l10n`
   lépése kapuzza, a forrás a szegmens (ADR 0424, L469).
</content>
