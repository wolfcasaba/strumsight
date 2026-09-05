# E14-R11 — A chord-döntés bekötése a merge-elt felismerési szerződésbe

- **Státusz:** REVIDÁLVA a pre-flightban (2026-09-05, kód olvasva: `main @ 744797b8`)
- **Típus:** Chapter 14, Kör 11 (truthfulness hotfix blokk)
- **Kör-azonosító:** `E14-R11`
- **Branch:** `sonnet-impl/e14-r11-chord-uncertainty-and-separate-confidence`
- **Előfeltétel:** `E14-R04` (RecognitionFrame V2), `E14-R05` (SignalQuality),
  `E14-R10` (irány-abstention bekötés) — mind merge-elve.
- **Brief szerzője:** Claude (Opus 5) · **§0.0 revízió:** Claude (Opus 5), orchestrátor
- **ADR:** `0516` (`docs/adr/0516-live-chord-decision-wiring.md`) — a pre-flightban
  MEGÍRVA és commitolva. A `docs/adr/` az implementernek TILOS zóna.

---

## 0.0 Pre-flight revízió (ADR 0087 §2 — az orchestrátor hatásköre)

A `brief-lint` két `strict` leletet adott (**S12**, **S15**). Mindkettő javítva;
a revízió MÉRT indoklása az **ADR 0516 „Kontextus"** szakaszában van tételesen.
A rövid változat — **mi maradt igaz, mi nem, és hol van a kör EGYETLEN
döntési helye**:

**Ami MÁR NEM igaz** (a brief 2026-08-20-i alapja azóta elmozdult):

1. *„A `noChord`/`unknownChord`/`lowSignal` megkülönböztetés nincs a
   frame-ben"* → **elavult**. A `RecognitionDecision` (6 állapot) és a
   `RecognitionRejectReason` (6 ok, köztük `noChord`, `signalQuality`,
   `lowConfidence`) MERGE-ELVE él. Egy új enum második, divergens szótár
   volna ugyanarra a döntésre — ez az E14-R10 H3 / [L636](../LESSONS.md#l636)
   hibaosztálya. **A kör a merge-elt szótárat KÖTI BE, nem épít másodikat.**
2. *„Két külön confidence-mező a `LiveFrame`-ben"* → a szétválasztást az
   **ADR 0505 már kimondta** (`RecognitionFrame`: „the chord- and
   direction-confidence are carried SEPARATELY"). Ez a kör beköti.
3. *A nyers `chordConfidence` double a frame-en* → **tilos**: az
   ADR 0505 D2 szerint kalibrálatlan valószínűség nem kerülhet
   confidence-alakú mezőbe. Nincs mért akkord-kalibráció a fában.
4. *Az előre kiosztott `0363` ADR-szám* → **elavult**; a foglaló a
   **`0516`**-ot adta (a legmagasabb létező szám `0512`).

**Ami KIKERÜLT a körből — és miért (S15 → a feloldás lista-tágítást kívánna, ADR 0087 §2 H3):**

A brief UI-céljai (`confidence_pill.dart`, `chord_display.dart`) **halott
kódra** mutatnak. Mérve: e két widgetnek a `lib/` fában **nulla** használója
van, egyedül a `test/features/live/live_widgets_test.dart` importálja őket. A
SZÁLLÍTOTT Live felület a `live_screen.dart` → `SsChordHero` úton rajzol, és
ott (`live_screen.dart:350`), illetve a `chord_timeline_card.dart:225`-ben írja
ki a kalibrálatlan százalékot. A két widget átírása tehát **semmit nem
változtatna azon, amit a felhasználó lát** — a valódi javítás a
`lib/features/live/screens/**`-ot kívánná, amit ez a brief maga sorol a TILOS
zónába. Ráadásul a pill százalékát a listán KÍVÜLI
`live_widgets_test.dart:50` (`find.textContaining('94%')`) pinneli ki, tehát a
§5.2 változtatása egy nem engedélyezett fájlt vinne pirosra (S14-osztály).

Ezért a `confidence_pill.dart`, a `chord_display.dart`, a két ARB és a
`confidence_pill_test.dart` **kikerült** az engedélyezett listáról (a lista
SZŰKÍTÉSE az orchestrátor hatásköre; a tágítás nem az). A kör a **domain-felet**
szállítja hiánytalanul.

> ⚠ **NYITVA MARAD, nevesítve:** a Chapter 14 §9/6 („kalibrálatlan
> valószínűséget tilos százalékként mutatni") UI-adóssága **NEM teljesül**
> ebben a körben. Külön kör kell rá, amelynek `allowed_paths`-a tartalmazza a
> `lib/features/live/screens/live_screen.dart`-ot és a
> `lib/features/live/widgets/chord_timeline_card.dart`-ot. Lásd ADR 0516 D6.

**A kör EGYETLEN döntési helye:** `lib/features/live/engine/dsp/live_pipeline.dart` —
ott, ahol az E14-R10 az irányt kötötte be (`_isDirectionConfirmed`).

**S12 javítva:** a §7 gate-parancs mostantól szó szerint tükrözi a `gate_tests`
listát.

**Visszakeresett előzmény (ADR 0312, kötelező):** `knowledge-rag` szűkítve
(`lessons,halts,adr`) + teljes korpuszon lefuttatva. Releváns találatok:
[ADR 0271](../adr/0271-recognition-recovery-program.md) (a gyökérok:
„a `LiveFrame` túl kevés információt visz a UI-nak"),
[L624](../LESSONS.md#l624) (a szerződés-kör felépítheti a bizonytalanság
szótárát, majd a saját fogyasztójában nem használja — ez a kör pontosan ezt a
hézagot zárja az akkord-oldalon),
[L636](../LESSONS.md#l636) (az előre írt brief mért alapja elmozdul alatta).

---

```ai-router
schema_version = 1
risk = "normal"
allowed_paths = [
  "lib/features/live/model/live_frame.dart",
  "lib/features/live/engine/dsp/live_pipeline.dart",
  "lib/features/live/public.dart",
  "test/features/live/chord_uncertainty_test.dart",
  "docs/rounds/e14-r11-chord-uncertainty-and-separate-confidence.md",
]
gate_tests = [
  "test/features/live/chord_uncertainty_test.dart",
  "test/features/live",
]
native_gate = false
```

## 0. Kör-jelzés és STOP-protokoll

```bash
tools/codex-signal.sh progress "<egy sor>"
tools/codex-signal.sh done "<egy sor>"
tools/codex-signal.sh stopped "<egy sor>"
tools/codex-signal.sh blocked "<egy sor>"
```

**A kör-jelzés kötelező: lezáró jelzés nélkül a kör bukott.** Ha bármilyen
munka a fenti `allowed_paths` listán KÍVÜLI fájlt kívánna, **NE írd át**:
adj `stopped` jelzést, és a jelentésben mondd meg, melyik fájl és miért.
A `docs/adr/**` ebben a körben is TILOS — az ADR 0516 már meg van írva.

**A brief §8 a terved — nincs külön task-lista.** Doc-commentben csak olyan
állítás szerepelhet, amit teszt bizonyít (`const`, `immutable`, küszöbérték).

## 1. Cél

A Live pipeline akkord-verdiktje **tipizált, merge-elt szótárú döntéssé**
váljon: a `RecognitionDecision` + `RecognitionRejectReason` páros mondja meg,
hogy az akkord megerősített, bizonytalan vagy elutasított — és ha elutasított,
**miért** (`noChord` / `signalQuality` / `lowConfidence`). Ez az információ
additívan jusson el a `LiveFrame`-ig, hogy egy későbbi UI-kör a bizonytalanságot
meg tudja jeleníteni (ADR 0271 gyökérok).

**A felhasználó által látott viselkedés ebben a körben NEM változik** — a kör
additív. A `showChord` kapu, a `current` mező és a küszöbök változatlanok.

## 2. Jelenlegi állapot — mért tények (`main @ 744797b8`)

- `live_pipeline.dart:368` — `double get chordConfidence => _lastChord?.confidence ?? 0;`
  — létezik, de a frame nem viszi tovább, és ez **kalibrálatlan** szám.
- `live_pipeline.dart:338-341` — `final showChord = _lastChord != null && _chordLatched;`
  → `current: showChord ? Chord(...) : null`. A döntés ma egy `bool`.
- `live_pipeline.dart:244-268` — a Schmitt-kapu: `_chordConfEma >= _chordConfRise`
  → latch; `< _chordConfRelease` → (debounce után) elenged.
- `dsp_config.dart:75,76,81` — `chordConfRise = 0.54`, `chordConfRelease = 0.22`,
  `chordConfEmaAlpha = 0.35`; `:55` — `chordMinTonalness = 0.7`.
- `live_pipeline.dart:364` — `SignalQualitySnapshot get signalQuality` (E14-R05).
- `live_frame.dart:70` — `double get confidence => latestStrum?.confidence ?? 0;`
  — ez a STRUM confidence-e.
- `ChordPrediction(` termelő a `lib/` fában: **nulla** (a saját konstruktorán és
  a `fromJson`-on kívül).
- `live_pipeline.dart:299-313` — `_isDirectionConfirmed` (E14-R10, ADR 0512):
  **ez a követendő alak** az akkord-oldalon.

## 3. Scope

**Benne:** a `ChordPrediction` legyártása a pipeline-ban a merge-elt szótárral;
a `decision` + `rejectReason` levezetése a MÁR SZÁLLÍTOTT kapuból; a tipizált
döntés additív továbbadása a `LiveFrame`-ben; a `public.dart` additív exportja;
a mérce-tesztek.

**Nincs benne:** DSP-küszöb hangolása, ÚJ enum vagy állapotnév, nyers
százalék bárhol, UI/képernyő-változtatás, l10n, a `live_frame_adapter.dart`
átkötése, a `chord_prediction.dart` módosítása.

## 4. Engedélyezett fájlok

| Útvonal | Miért |
|---|---|
| `lib/features/live/engine/dsp/live_pipeline.dart` | **a kör egyetlen döntési helye**: a `ChordPrediction` levezetése |
| `lib/features/live/model/live_frame.dart` | additív, tipizált `chordDecision` + `chordRejectReason` |
| `lib/features/live/public.dart` | additív export, ha kell |
| `test/features/live/chord_uncertainty_test.dart` | a kör mércéje (ÚJ fájl) |
| `docs/rounds/e14-r11-…md` | §10 handoff |

**Tilos zóna:** minden más — kiemelten `docs/adr/**`,
`lib/features/live/screens/**`, `lib/features/live/widgets/**`,
`lib/features/live/domain/recognition/**` (a szerződés MERGE-ELT: olvasd és
használd, ne írd át), `lib/l10n/**`, `lib/features/live/engine/dsp/dsp_config.dart`
(küszöb-hangolás tilos), `.github/workflows/**`, `tools/**`.

## 5. Kötött architekturális döntések (ADR 0516)

### 5.1 A merge-elt szótár kötelező, második nem épül

A `decision` értéke `RecognitionDecision`, az ok `RecognitionRejectReason`.
**NEM elfogadható:** új enum, `String` állapotnév, `bool`-hármas vagy bármilyen
saját „uncertainty" típus.

### 5.2 A `calibratedConfidence` marad `null`

Nincs mért akkord-kalibráció. **NEM elfogadható** az EMA, a match-confidence
vagy bármely nyers valószínűség bemásolása ebbe a mezőbe (ADR 0505 D2).

### 5.3 Küszöb nem duplikálódik és nem hangolódik

A levezetés a `DspConfig` MEGLÉVŐ értékeit és a pipeline MEGLÉVŐ
`_chordLatched` / `_chordConfEma` állapotát használja. **NEM elfogadható** új
számliterál küszöbként a `live_pipeline.dart`-ban.

**Inkluzivitás:** a rise-oldal **megerősítés-oldalon inkluzív**
(`_chordConfEma >= _chordConfRise` → latch) — ez a ma szállított viselkedés.

### 5.4 A `rejectReason` a `decision`-nal EGYÜTT keletkezik

Soha nem külön tárolt mező, ami eldriftelhet (ez a
`StrumPrediction.rejectReason` merge-elt mintája). Leképezés:

| Mért helyzet | `decision` | `rejectReason` |
|---|---|---|
| a kapu latch-elt, van akkord-match | `confirmed` | `null` |
| a jel-minőség nem `good` és nem `unknown` | `rejected` | `signalQuality` |
| tonalness-kapuzott / nincs akkord-match | `rejected` | `noChord` |
| van match, de a kapu alatt | `uncertain` | `lowConfidence` |

A jel-minőség ELŐBB dönt, mint a kapu.

### 5.5 Additív szerződés

A `LiveFrame` új mezői alapértelmezett `null`-osak; a meglévő `confidence`
getter és minden meglévő mező marad (deprecation-komment igen, törlés nem).
A `LiveFrame.empty` és a `copyWith` viselkedése nem romolhat el.

### 5.6 A viselkedés nem változik

A `showChord` kapu és a `current` mező kimenete bit-azonos marad. Ez a kör
**csak hozzáad**.

## 6. Acceptance criteria

Minden pont a `test/features/live/chord_uncertainty_test.dart`-ban mérve.

1. **A pipeline tipizált akkord-verdiktet ad.** Van egy elérhető
   `ChordPrediction?` (getter a pipeline-on), amelynek `decision`-je a merge-elt
   `RecognitionDecision` értéke. `ChordPrediction` termelő a `lib/`-ben:
   már nem nulla.
2. **A `decision == confirmed` PONTOSAN akkor, amikor a mai `showChord`.**
   Ugyanaz a bemenet, amire a frame `current != null`, `confirmed`-et ad; és
   fordítva, `current == null` mellett soha nem `confirmed`.
3. **A négy leképezési sor (5.4) mind mérve** — külön cella a `confirmed`, a
   `signalQuality`, a `noChord` és a `lowConfidence` sorra.
4. **Küszöb-hármas a rise-kapun** (a határ **megerősítés-oldalon inkluzív**,
   `chordConfRise = 0.54`):
   - EMA `0.53` (a küszöb **alatt**) → **nem** `confirmed`;
   - EMA `0.54` (pontosan **rajta**) → `confirmed` (a határ ide tartozik);
   - EMA `0.55` (a küszöb **fölött**) → `confirmed`.
   A levezetésnek unit-szinten elérhetőnek kell lennie (pl.
   `@visibleForTesting` belépési pont), hogy a hármas EXAKT EMA-értékkel
   mérhető legyen, ne audio-vezérléssel közelítve.
5. **A `calibratedConfidence` `null`** minden legyártott `ChordPrediction`-ön.
6. **Chord ≠ strum forrás.** A `LiveFrame.confidence` (strum) és a
   `chordDecision` (akkord) külön forrásból jön: olyan cella, ahol a strum
   confidence magas, de az akkord-döntés `uncertain`/`rejected` — és fordítva.
7. **Kompatibilitás.** A `LiveFrame` régi hívói fordulnak; `LiveFrame.empty`
   új mezői `null`-ok; a `copyWith` megőrzi őket.
8. **Az adapter-hézag KIMONDVA pinnelve (ADR 0516 D7).** A
   `LiveFrameAdapter.toLiveFrame` kimenetén a `chordDecision` `null` marad —
   a teszt ezt a hézagot rögzíti, hogy ne néma legyen.

### 6.1 Mérce-mátrix — melyik hibás implementációt melyik cella fogja pirosra

| Hibás implementáció | Melyik cella vált PIROSRA |
|---|---|
| Új saját enum a merge-elt `RecognitionDecision` helyett | 1. pont (fordítási cella: a teszt a merge-elt típust várja) |
| A chord-döntésbe a STRUM confidence kerül | 6. pont |
| A `confirmed` a mai `showChord`-tól eltér | 2. pont |
| A `signalQuality` és a `lowConfidence` ok összeolvad | 3. pont |
| A rise-küszöb exkluzívvá válik (`>`) | 4. pont „pontosan rajta" cellája |
| Az EMA bemásolása `calibratedConfidence`-be | 5. pont |
| A régi `LiveFrame` mező törlése | 7. pont fordítási cellája |
| Az adapter némán tölteni kezdi az új mezőt | 8. pont |

## 7. Kötelező ellenőrzések

A `gate_tests` listát szó szerint tükröző, EGYETLEN gate-hívás
(`&&`-láncolás tilos, L05/L09):

```bash
tools/round-gate.sh test/features/live/chord_uncertainty_test.dart test/features/live
```

Külön processzben futó `format` → `analyze` → célzott tesztek →
`architecture` (AGENTS.md §12). CI-dispatch/PR/merge Claude-oldal.

### 7.1 Falszifikációs cella (a §10-ben dokumentáld)

A `decision` levezetésében a `_chordConfEma` ideiglenes lecserélésével a strum
confidence-re a **6. pont PIROS**, visszaállítva **ZÖLD**. Írd le a
tényleges kimenetet (teszt-név + `flutter test` sor), ne csak az állítást.

## 8. Implementációs sorrend

1. `live_pipeline.dart`: a `decision` + `rejectReason` levezetése az 5.4
   táblázat szerint, unit-szinten elérhető belépési ponttal; a
   `ChordPrediction` legyártása; a félrevezető `chordConfidence` getter
   doksijának pontosítása (kalibrálatlan!).
2. `live_frame.dart`: additív `chordDecision` + `chordRejectReason` mezők
   (alapértelmezett `null`), `copyWith` és `empty` karbantartása.
3. A pipeline `_buildFrame()`-je tölti az új mezőket.
4. `public.dart`: additív export, ha a teszt a barrelen át importál.
5. `test/features/live/chord_uncertainty_test.dart`: a §6 mind a 8 pontja.

## 9. Kockázatok

- **Második szótár (fő kockázat):** a legkönnyebb hiba egy saját enum. Az 5.1
  és a 6.1 első sora ezt fogja meg.
- **Kalibrálatlan szám becsúszása:** az 5. acceptance-pont őrzi.
- **Viselkedés-drift:** az 5.6 + 2. pont pinneli, hogy a `showChord` kapu nem
  mozdul.
- **Hívó-drift:** 19+ `LiveFrame`-hívó; a 7. pont a kompatibilitási cella.

## 10. Implementation handoff — az implementer tölti ki

## 11. Review — a Claude tölti ki
