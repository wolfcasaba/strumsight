# ADR 0550 — Live Stage V2: a hat döntési állapot megkülönböztetett megjelenítése, és a stage-mód mint a felismerési rezsimtől FÜGGETLEN fogalom

**Státusz:** elfogadva (2026-09-09) · **Kör:** E14-R37 · **Épít rá:** ADR 0505 (döntési állapotgép), ADR 0516 (`LiveFrame.chordDecision`), ADR 0520/0535 (reject-ok bannerek), ADR 0544 (`RecognitionMode`), ADR 0274 (reduced motion)

## Kontextus (mért)

- `lib/features/live/screens/live_screen.dart` a kör előtt **egyetlen**
  döntési állapotot sem jelenített meg. A `LiveFrame.chordDecision` mezőt
  (ADR 0516 óta létezik, `LivePipeline` mindig kitölti) a képernyő **nem
  olvasta**; csak a `chordRejectReason`-t, az `UncertaintyReasonBanner`-en át.
- A hero (`SsChordHero`) feltétele `frame.current != null` volt. Ez ma
  véletlenül helyes: `live_pipeline.dart:469` a `current`-et
  `showChord = _lastChord != null && _chordLatched` alapján tölti, és a
  `debugDeriveChordDecision` **ugyanebből** a bitből ad `confirmed`-et. Tehát a
  „csak megerősített akkordot mutatunk" ma a PRODUCER egybeesése, nem a
  képernyő őre — bármely másik producer (stabilizer, `LiveFrameAdapter`, mock)
  átcsúszhat rajta.
- A `chord_timeline.dart` négy `flutter_animate` láncot futtat (beat-pulzus,
  flash/shimmer, belépés, ghost-fade) és két implicit tweent
  (`AnimatedOpacity`/`AnimatedScale`), **egyik sem** kérdezte meg az
  `SsMotionScope`-ot. Ez az E14-R39 audit B15-ös lelete, PKG-F tulajdonra
  hivatkozva nyitva hagyva (`docs/accessibility/ch14-r39-audit.md`).
- „Mód" fogalom a képernyőn nem létezett. A `RecognitionMode` (ADR 0544) a
  MOTOR konstrukciós rezsimje — más kérdésre válaszol, mint az, hogy a
  képernyő mutat-e célt.
- Amit NEM tudunk: nincs mérés arról, hogy a `candidate` / `provisional` /
  `expired` állapotokat a `LivePipeline` valaha is előállítja-e. Ma
  bizonyíthatóan **nem** (`debugDeriveChordDecision` csak `confirmed`,
  `rejected`, `uncertain` értéket ad). A hatból hármat tehát a szerződés miatt
  renderelünk, nem mért forgalom miatt — ezt a kör briefje NEEDS-MEASUREMENT
  sorként viszi tovább.

## Döntés

### D1 — A hero DETEKCIÓS slot: csak `confirmed` verdikt tehet bele akkordot

`live_screen.dart` új, tiszta, statikus őre:

```dart
static bool _decisionClaimsChord(RecognitionDecision? decision) =>
    switch (decision) {
      RecognitionDecision.confirmed => true,
      RecognitionDecision.candidate ||
      RecognitionDecision.provisional ||
      RecognitionDecision.uncertain ||
      RecognitionDecision.rejected ||
      RecognitionDecision.expired => false,
      null => true,
    };
```

Kimerítő, `default` nélkül: egy hetedik állapot fordítási hiba lesz, nem
csendes „igen". A `null` ág **szándékos**: az a producer, amelyik tipizált
döntést egyáltalán nem ad (mockok, az onboarding first-win motorja, a
`LiveFrameAdapter` határ), a kör előtti viselkedést tartja meg — ez a kör nem
talál ki verdiktet olyasminek, ami nem állít semmit.

Ugyanez az őr kapuzza a képernyőolvasós narrációt (`SsLiveRegion`): egy
bizonytalan akkordot kimondani ugyanaz a hamis állítás, mint kiírni.

### D2 — `LiveStageMode` külön típus, és a CÉLBÓL származtatva

`lib/features/live/providers/live_stage_mode.dart`:

```dart
enum LiveStageMode { freePlay, guided }
```

Nem ugyanaz, mint a `RecognitionMode`, és nem is képződik rá kölcsönösen
egyértelműen:

| kérdés | típus |
|---|---|
| befolyásolhatja-e egy elvárt akkord a DEKÓDERT? | `RecognitionMode` (ADR 0544) |
| mutat-e a KÉPERNYŐ éppen célt a játékosnak? | `LiveStageMode` |

A stage-mód **származtatott** (`liveStageModeProvider` a
`liveGuidedTargetProvider`-ből): egyetlen igazságforrás van arra, hogy
„vezetett-e a kör", így a mód és a cél nem tud szétcsúszni. Üres címke nem cél.

A képernyőn a mód SZÓVAL és ikonnal jelenik meg, sosem csak színnel — az
E14-R39 mérés szerint (`docs/accessibility/ch14-r39-audit.md`) a
konfidencia-tokenek szürkeárnyalatban egyetlen szürkévé esnek össze, tehát egy
hue-alapú módjelzés nem jelzés.

### D3 — A cél a `feedback` slotban él, sosem a `hero`-ban

`GuidedTargetCard`: szerep-címke (`Cél`), majd az akkord; a szemantikai
címke **szerep-elöl** mond („Cél akkord: Am"). Három elválasztás — a slot, a
címke és a szemantika — együtt zárja ki, hogy egy elvárás felismerésként
olvasódjon. Ez ugyanaz a hiba a képernyőn, amit az ADR 0544 a DSP-útból
kivett.

### D4 — Vezetett STAGE szabad MOTORON: ez a szállított konfiguráció

A `strumEngineProvider` mostantól **explicit** `mode:`-dal épül, egy új,
felülírható `liveRecognitionModeProvider`-ből, amelynek értéke
`RecognitionMode.free`. Következmény, kimondva: a vezetett Live-stage
**megmutatja** a célt, de a verdikt továbbra is kizárólag audio-alapú.

Ez szándékos, és a fordítottja a tiltott: egy vezetett MOTOR szabadnak látszó
képernyő mögött nem ábrázolható (`ExpectedChordHint.forMode`). Azért nem
emeljük a rezsimet guided-ra:

1. egyetlen mikrofon van, és a `strumEngineProvider` az app egyetlen
   detektáló kliense — Live, Learn és a Practice gateway MIND ezt az egy
   példányt hajtja; egy második, guided motor második mikrofon-klienst nyitna,
   amit ezen a boxon nem lehet mérni;
2. az ADR 0544 D3 maga mondja ki, hogy a tie-break valós órai értéke
   **UNKNOWN**. Egy nem mért nyereségért nem építünk be egy nem mérhető
   erőforrás-kockázatot (Ch14 §12/1).

A rezsim ezzel egy deklarált, felülírható érték lett egy implicit
konstruktor-alapérték helyett: az a kör, amelyik a mikrofon-lízing kérdését
eldönti, EGY helyen emeli, és minden fogyasztó vele mozdul.

### D5 — Minden animált elem az `SsMotionScope`-ot kérdezi, és a mozgás
extentje nullázódik, nem az információ

`chord_timeline.dart` egyszer old fel (`SsMotionScope.reduceMotionOf`), és
átadja: a beat-pulzus és a flash/shimmer/settle gesztus reduced motion alatt
**nem épül fel**; a belépés `.animate` burkolója viszont MEGMARAD, nulla
hosszú tweenekkel, mert az `onPlay` hordozza az „új akkord landolt" haptikát —
a haptika visszajelzés, nem mozgás (ADR 0274 §5.1). A history-kártyák tier-je
(kisebb + halványabb = régebbi) információ, ezért megmarad; csak a hozzá vezető
tween lesz nulla hosszú.

### D6 — A hat állapot MEGKÜLÖNBÖZTETVE, egy kimerítő szótárból

`RecognitionStateChip.textFor` / `.iconFor` — ugyanaz a szerződés, amit az
`UncertaintyReasonBanner` a reject-ok tengelyen visz, a döntés tengelyre
alkalmazva: kimerítő `switch`, `default` nélkül, saját mondat és saját glyph
állapotonként. A `provisional` az EGYETLEN, amely megnevezi az akkordot — és
csak egy explicit hedge-mondaton belül („Valószínűleg C…"), sosem verdiktként.

## Következmények

- **Vállalt:** két golden PNG (`e13_r18_live_stage_compact{,_scale2}.png`)
  eltér, mert a stage kapott egy mód-chipet. Újragenerálás Flutter SDK-t
  igényel — a kör riportja kéri az orchestrátortól.
- **Vállalt:** a `candidate` / `provisional` / `expired` chip-ágakat ma
  semmilyen éles producer nem éri el. Teszt fedi őket, forgalom nem.
- **Nem vállalt:** a terv R37 (3) pontja — az opcionális history bottom sheet
  — kimarad; nincs hozzá termékdöntés, és a fix timeline ma nem mért hiba.
  A `newLiveStageEnabled` zászlót ez a kör **nem** kapcsolja fogyasztóhoz: a
  szállított változás nem egy alternatív stage, hanem az egyetlen stage
  igazmondóbbá tétele, amit zászló mögé rejteni azt jelentené, hogy a hamis
  állítás marad az alapértelmezés.
