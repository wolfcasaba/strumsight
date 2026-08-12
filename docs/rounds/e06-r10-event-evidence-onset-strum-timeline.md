# E06-R10 — Event evidence modell és onset/strum timeline V2

- **Státusz:** PREPARED → **revideálva** (ADR 0112 önjavító kör, H3, 2026-08-12
  — a §0.0 rögzíti a mért gyökérokot és a feloldást; eredetileg előre megírva
  2026-08-07, kód olvasva: main @ `a6e6f3d`)
- **SDD-kör:** [`docs/sdd/07-epic-06-audio-analysis-2.md`](../sdd/07-epic-06-audio-analysis-2.md) Kör 10; §9.6, §13.1–13.2
- **ADR:** [0228](../adr/0228-event-evidence-model-and-timeline-builder-contract.md) (pre-flight, 2026-08-12)
- **Branch:** `codex/e06-r10-event-evidence-onset-strum-timeline`
- **Előfeltétel:** **E06-R09 merge**
- **Brief szerzője:** Claude (batch) · **Implementáció:** Codex (Terra)

```ai-router
schema_version = 1
risk = "high"
allowed_paths = [
  "lib/features/audio_analysis/domain/analysis_event.dart",
  "lib/features/audio_analysis/domain/events/event_id.dart",
  "lib/features/audio_analysis/engine/events/event_timeline_builder.dart",
  "lib/features/audio_analysis/data/legacy_view_adapter.dart",
  "lib/features/audio_analysis/public.dart",
  "test/features/audio_analysis/domain/analysis_event_test.dart",
  "test/features/audio_analysis/engine/event_timeline_builder_test.dart",
  "test/features/audio_analysis/domain/event_id_test.dart",
  "test/property/analysis_event_timeline_property_test.dart",
  "docs/rounds/e06-r10-event-evidence-onset-strum-timeline.md",
  "docs/adr/0228-event-evidence-model-and-timeline-builder-contract.md",
]
gate_tests = [
  "test/features/audio_analysis",
  "test/property",
]
native_gate = false
```

> ⚠ **Pre-flight (KÖTELEZŐ):** friss `origin/main` + E06-R09 merge. Olvasd újra
> az R09 `LegacyEvidence` **tényleges** mezőit — a builder ebből dolgozik.
> Olvasd újra a `lib/features/analyze/widgets/timeline_view.dart` (170 sor)
> `TimelineStrum`-fogyasztását: a `LegacyViewAdapter` **ezt** a shape-et kell
> hogy tudja előállítani. PREPARED→PLANNING, brief commit előbb.
>
> **H3 self-heal revízió után (§0.0):** olvasd újra a MEGLÉVŐ
> `lib/features/audio_analysis/domain/analysis_event.dart`-ot — az
> `OnsetEvent`/`StrumEvent` már ott él a sealed `AnalysisEvent` családban,
> ezt a KÖR EZT BŐVÍTI, nem új fájlt ír. Olvasd el a §9 kockázatait a
> megosztott-fájl blast radiusról, mielőtt hozzányúlsz.

## 0. Kör-jelzés és STOP-protokoll

```bash
tools/codex-signal.sh progress "<egy sor>" ; tools/codex-signal.sh done "<egy sor>"
tools/codex-signal.sh stopped "<egy sor>" ; tools/codex-signal.sh blocked "<egy sor>"
```

Lezáró jelzés nélkül a kör bukott. Listán kívüli fájl → `stopped`.

## 0.0 Tervezési baseline és pre-flight revízió

**PREPARED → revideálva (ADR 0112 önjavító kör, H3, 2026-08-12).** Új ADR
nincs — [ADR 0215](../adr/0215-analysis-document-versioning.md) 4. döntési
pontja már lefedi az itt szükséges szabályt („additív, hátrafelé kompatibilis
mező NEM igényel verzióemelést"), ez a revízió csak ALKALMAZZA azt, nem hoz
új normatív döntést.

**Mért gyökérok (H3 halt, Terra első futási kísérlete, 2026-08-12 01:29 UTC):**
ez a brief 2026-08-07-én, **batch-ben, az Epic 6 kickoff ELŐTT** íródott
(`main @ a6e6f3d` — ezen a commiton `lib/features/audio_analysis/` MÉG NEM
létezett; `git log --oneline a6e6f3d -1` → az E05-R11 utáni állapot). A §2
„Jelenlegi állapot" ezért kizárólag a régi V1 `TimelineStrum`-modellt látta,
és két ÚJ fájlt írt elő `OnsetEvent`/`StrumEvent` néven
(`domain/events/onset_event.dart`, `.../strum_event.dart`). Az azóta
lezajlott **E06-R02** kör megalkotta a valódi V2 domain modellt, és a brief
**SAJÁT** SDD-hivatkozása (§9.6 „Kezdeti event típusok: `OnsetEvent`;
`StrumEvent`; …") ezt a KÉT nevet már ott, a sealed `AnalysisEvent` család
(`domain/analysis_event.dart`, ekkor még nem engedélyezett fájl) tagjaként
rögzítette — `rg -n 'class OnsetEvent|class StrumEvent' lib/features/audio_analysis`
mindkettőt ott találja, `analysis_document_codec.dart`,
`legacy_analyze_adapter.dart`, `legacy_view_adapter.dart` és három teszt már
használja is. A két új fájl a `public.dart` barrelben ambiguous exportot
adott volna a már élő nevek mellé — Terra ezt mérve `stopped`-ot jelzett.

**Feloldás:** a kör az SDD §13.1–13.2 „strum event tartalmazhatja: irány;
irány confidence; onset confidence; attack strength; local RMS; source
classifier; fallback flag" követelményét a MEGLÉVŐ `OnsetEvent`/`StrumEvent`
**bővítéseként** valósítja meg, nem párhuzamos, új típusként — ez pontosan az
SDD saját szövege, nem új architekturális döntés (§5 pont 1 ezért
változatlan marad: TOVÁBBRA is két külön típus, nem `isStrum` boolean). Az
`allowed_paths` a két kollidáló ÚJ fájl helyett a meglévő
`domain/analysis_event.dart`-ot listázza. Az `EventId`
(`domain/events/event_id.dart`) és az `EventTimelineBuilder`
(`engine/events/event_timeline_builder.dart`) NEM ütközik semmivel — mindkét
név `rg`-vel nulla találatot ad a teljes repóban —, ezért ÚJ fájlként
megmaradt. A pontos kompatibilitási szabály: OD-03 (§5.1).

**Regressziós védelem:** `tools/brief-lint.py` új, **strict**-szintű `S5`
leletje (docs/LESSONS.md) ugyanezt a fájlnév→típusnév ütközés-heurisztikát
futtatja minden brief allowed_paths-ára. Mérve: az Epic 6 még nyitott
**R11** (`ChordSegment`, ütközik: `domain/analysis_segment.dart`), **R12**
(`TempoPoint`, ütközik: `domain/analysis_timeline.dart`) és **R17**
(`PitchSegment`, ütközik: `domain/analysis_segment.dart`) briefje is
ugyanezt a hibaosztályt hordozza. Ez a self-heal kör **szándékosan nem
nyúlt hozzájuk** — az önjavító jogosultság kizárólag a HALT-olt körre szól
(ADR 0112 §2); mindegyiket a SAJÁT pre-flightjuk revideálja majd, ugyanezzel
a mintával (bővítés a meglévő fájlban, nem új fájl). A lelet `strict` szintű
(nem CI-kapu), mert a bevezetéskor NEM minden nyitott brief teljesítette —
pontosan a brief-lint saját base/strict szabálya szerint.

### 0.0.1 Pre-flight ADR 0228 — a hátralévő nyitott architekturális felület

A H3 self-heal kizárólag a fájl-cél-ütközést zárta; a hat új evidence-mező
pontos elhelyezése, az `EventId` formátuma és a builder összevonási szabálya
formálisan nyitva maradt. **[ADR 0228](../adr/0228-event-evidence-model-and-timeline-builder-contract.md)**
(ez a pre-flight, 2026-08-12) ezt zárja le — az implementer az ADR 7 döntését
köti magára, a §5/§5.1 alább ezekkel összhangban áll. **Egy mért rést is zár**
(ADR 0228 3. döntés): a §6 acceptance-mátrix „2399/2400/2401 minta, 48 000
Hz-en" hármasa a PROPERTY/UNIT teszt saját, 48 kHz-re választott
fixture-konstrukciója — a builder tényleges minimum-separation
összehasonlítása **`Duration`-alapú** (a két event `.time` mezője), NEM
rögzített mintaszám-küszöb. Mérve: a kilenc R09-fixture (`clip_analyzer_
parity_test.dart`) mind `sampleRate: 44100`-on fut, és 2400 minta 44100 Hz-en
**54,42 ms**, NEM 50 ms — egy mintaszám-alapú (rátafüggetlen) implementáció
ezen a rátán néma paritás-regressziót okozna (§6 első acceptance pontja).

**Második mért rés (ADR 0228 7. döntés):** a §5 pont 1 kötelezővé teszi a
`StrumEvent.onsetEventId` mezőt, és a §6.1 mátrix egy „onsetEventId
hivatkozás cellát" vár — de ez a mező NEM szerepel sem a §0.0 „ami
TOVÁBBRA is hiányzik" listáján, sem a §3 scope-felsorolásán, sem az OD-03
öt-mezős listáján, és nincs hozzá dedikált acceptance-pont. Mérve
(`lib/features/audio_analysis/engine/legacy/legacy_evidence.dart`, teljes
fájl olvasva): a `LegacyEvidence` **nem** hordoz független onset-listát —
kizárólag `strums` (irány/idő/confidence) és `chords`, pontosan azt
tükrözve, amit a §2 már leír („az onset és a strum azonos fogalom" a mai
V1-ben). A hiány feloldása: **OD-04** (lásd §5.1) — a builder minden
`LegacyStrumEvidence`-hez EGY szintetizált `OnsetEvent`-et épít ugyanarra a
sample indexre/időre, és a hozzá tartozó `StrumEvent.onsetEventId`-je erre
mutat; a suppression a (onset, strum) PÁRT atomikusan kezeli.

### 0.0.2 Terra első futása — RENDEZETTSÉG/MONOTONITÁS ütközés (dispatch #1, 2026-08-12 02:21 UTC)

Terra a fenti brief-változatot mérve, **fájl írása előtt** `stopped`-ot
jelzett: „same-index onset/strum pairs cannot make one combined event list
strictly monotonic by sample index" — helyesen. Az OD-04 (fent) minden
szintetizált (onset, strum) párt AZONOS `sampleIndex`-re helyez, a §6
„Rendezettség + duplikátummentesség property" bullet viszont **szigorúan
monoton** sample indexet várt a KOMBINÁLT (onset+strum együtt) listától — a
kettő egyszerre nem teljesíthető egyetlen párra sem, tehát minden legalább
egy strumot tartalmazó valódi bemeneten szisztematikusan bukna. Terra nulla
fájlt módosított (`git status --short` üres a stopped jelzés után) — tiszta
STOP, nincs mit visszaállítani.

**Feloldás (ADR 0228 8. döntés):** a kombinált lista rendezési kulcsa
**`sampleIndex` monoton NEM CSÖKKENŐ** (nem szigorúan növekvő); AZONOS
`sampleIndex`-en legfeljebb **egy esemény TÍPUSONKÉNT** él (ez §5 pont 5
eredeti, változatlan dedup-szabálya); és amikor egy `OnsetEvent` és a hozzá
`onsetEventId`-vel kapcsolódó `StrumEvent` AZONOS `sampleIndex`-en áll, a
listában az **`OnsetEvent` mindig megelőzi a StrumEvent-jét** (determinisztikus
holtverseny-szabály). A §5 pont 5 és a §6 property-bullet szövege lent ennek
megfelelően pontosított — nem új döntés, a §5 pont 5 EREDETI „legfeljebb egy
event típusonként" szabálya már ezt implikálta, csak a property-bullet
„szigorúan monoton" szóhasználata mondott neki ellent.

### 0.0.3 Terra második futása — SUPPRESSION-SZÁMLÁLÁSI ütközés (dispatch #2, 2026-08-12 02:29 UTC)

Terra a §0.0.2 javítás után **valódi, scope-on belüli munkát commitolt**
(`event_id.dart` + teszt, `EventId.onset`/`EventId.strum` — pontosan az ADR
0228 2. döntése szerint: `<runId>:<type>:<sampleIndex>`, `type` rögzített
literál, NEM `runtimeType`), majd ismét `stopped`-ot jelzett, mielőtt a
builderhez ért volna: „OD-04 keeps an onset+strum pair (2 events), but §6
requires 1 public event after suppression." Helyes észrevétel — a §6
„Suppression-diagnosztika" és „Minimum separation" bulletek EREDETI „1
esemény" számozása a H3 self-heal ELŐTTI, párosítás-mentes világképet
tükrözte (amikor egy „onset" még önálló, strumtól független entitás lett
volna); az OD-04 pár-szintű szintetizálás mellett egy megtartott/elnyomott
LOGIKAI egység mindig **2** fizikai eseményt jelent (1 onset + 1 strum).

**Feloldás (ADR 0228 9. döntés):** a §6 „Minimum separation" és
„Suppression-diagnosztika" bulletek lent PÁR-szinten számolnak: a
minimum-separation teszt bemenete KÉT `LegacyStrumEvidence` (két PÁR, nem két
bare onset); a suppression-diagnosztika **pontosan 2** bejegyzést vár a
diagnosztikai listán (a második pár mindkét eseménye) és **pontosan 2**
eseményt a publikus listán (az első pár mindkét eseménye) — nem 1. Ez nem
lazítja a mércét: a §5 pont 1/OD-04 „nincs árva onsetEventId" szabálya
enélkül is kizárta volna, hogy egy pár szétessen a suppression során — a
bulletek számozása most már ezt EXPLICITEN, ellenőrizhetően állítja.

## 1. Cél

Az onset és a strum **külön** eseménnyé választása, sample-index alapú,
auditálható evidence-szel és **stabil event ID-kkel**, amikre a hotspotok és a
metrikák később hivatkozhatnak.

## 2. Jelenlegi állapot (mért, `a6e6f3d`)

- A mai modell **egyetlen** eseménytípust ismer: `TimelineStrum{direction,
  timeSec, confidence}` (`analyze_result.dart` 46–73). Az onset és a strum
  **azonos fogalom** — a `_strumPass` a `LivePipeline` `latestStrum`
  identitásváltását tekinti új eseménynek (`clip_analyzer.dart` 123–140),
  és az időbélyeg a `frame.latestStrumTime` (a strum saját attack ideje,
  r145 — a feed-pozíció 85–165 ms-ot késett ±40 ms jitterrel).
- **A V2 `domain/analysis_event.dart` MÁR létezik** (E06-R02 óta — ennek a
  briefnek az eredeti 2026-08-07-i baseline-ja, `a6e6f3d`, ELŐTTE íródott,
  amikor ez a fájl még nem is létezett; H3 self-heal revízió, §0.0): a
  sealed `AnalysisEvent` bázis már hordoz `id`/`time`/`confidence`/opcionális
  `sampleIndex`-et, és `OnsetEvent`/`StrumEvent` már **két külön**, `final`
  típus (nem `isStrum` boolean). **Ami TOVÁBBRA is hiányzik** a kért
  evidence-ből: determinisztikus (nem hívó-adott) `EventId`-formátum,
  irány-confidence, attack strength, local RMS, `confidenceSource`,
  fallback flag, `StrumEvent.onsetEventId`-hivatkozás és
  suppression-diagnosztika — ezeket adja hozzá ez a kör, additív/opcionális
  mezőkkel (OD-03/OD-04), és a `confidence` egyelőre továbbra is a CRNN vagy
  a heurisztika nyers, kalibrálatlan értéke marad.
- A `timeline_view.dart` a `TimelineStrum` listát rendereli
  (`isDown` alapján ↓/↑).
- Az R09 `LegacyEvidence` adja a nyers strum/chord listát + a hívási
  paramétereket.

## 3. Scope

**Benne:** a MEGLÉVŐ `OnsetEvent` és `StrumEvent` (`domain/analysis_event.dart`,
H3 self-heal revízió — §0.0) bővítése a hiányzó evidence-mezőkkel (a bázis
`confidence` marad az onset confidence; direction confidence, attack
strength, local RMS, source/`confidenceSource`, fallback flag, és a
`StrumEvent`-en `onsetEventId`-hivatkozás — mind ÚJ, OD-04) —
**továbbra is két külön típus**, nem egy `isStrum` boolean; `EventId` stabil,
**runon belül** determinisztikus generálás (ÚJ fájl); `EventTimelineBuilder`
(rendezés, duplikátumszűrés, minimum separation, suppression-diagnosztika,
ÚJ fájl); a `LegacyViewAdapter` bővítése, hogy a V2 eseményekből a mai
`TimelineStrum` lista előálljon.

**Kívül — TILOS:** onset-detektor **algoritmus** (a V1 SuperFlux marad),
DSP-konstans, chord (R11), beat (R12), `lib/features/analyze/**`,
`lib/features/live/**`, az `analysis_event.dart` TÖBBI típusa
(`ChordChangeEvent`/`BeatEvent`/`NoteOnsetEvent`/`SilenceRegionEvent`/
`ClippingRegionEvent`) és a fájl `AnalysisEvent` bázisosztálya — kizárólag
`OnsetEvent`/`StrumEvent` bővül.

## 4. Engedélyezett fájlok

| Útvonal | Állapot | Miért |
|---|---|---|
| `.../domain/analysis_event.dart` | **meglévő (H3 revízió, §0.0)** | `OnsetEvent`/`StrumEvent` bővítése — csak ez a két típus, a testvér-típusok érintetlenek |
| `.../domain/events/event_id.dart` | ÚJ | stabil ID-generálás (nem ütközik: `rg` 0 találat) |
| `.../engine/events/event_timeline_builder.dart` | ÚJ | rendezés/dedup/suppression |
| `.../data/legacy_view_adapter.dart` | meglévő | V2 → mai `TimelineStrum` |
| `.../public.dart` | meglévő | event típusok exportja (nincs új exportnév, csak bővült típus) |
| `test/.../domain/analysis_event_test.dart` | ÚJ | az `OnsetEvent`/`StrumEvent` bővítés dedikált tesztje |
| `test/features/audio_analysis/engine/event_timeline_builder_test.dart`, `test/features/audio_analysis/domain/event_id_test.dart`, `test/property/**` | ÚJ | tesztek |

**Tilos zóna:** `lib/features/analyze/**`, `lib/features/live/**`,
`docs/rag/**`, `assets/**`. Listán kívül → `stopped`.

## 5. Kötött architekturális döntések

1. **Az onset ≠ strum** (SDD §13.1): két külön típus, két külön lista; egy
   strum **hivatkozik** a saját onsetjére `onsetEventId`-vel (nullable
   `String?` mező, OD-03-mintájú additív bővítés — a jelenlegi bemenetre
   vonatkozó szintetizálási szabályt lásd OD-04).
   **NEM elfogadható:** egyetlen event-típus `isStrum` boolean mezővel.
2. **Minden event hordoz sample indexet ÉS `Duration` időt** (SDD §9.7), és a
   kettő a preprocessing mapping-jén (R08) keresztül konzisztens.
   **NEM elfogadható:** csak az egyik tárolása „a másik kiszámolható" alapon.
3. **Az event ID stabil és determinisztikus a runon belül**:
   `<runId>:<type>:<sampleIndex>` alak — ugyanaz a bemenet ugyanazokat az
   ID-ket adja. **NEM elfogadható:** `hashCode`, `Random`, vagy növekvő
   globális számláló.
4. **A suppressed event NEM tűnik el nyomtalanul:** a diagnosztikai ágba kerül
   (ok + időpont), a publikus timeline-ba nem. **NEM elfogadható:** a
   suppression néma eldobása.
5. **Az esemény-lista időrendben, duplikátummentesen** kerül ki: a rendezési
   kulcs `sampleIndex` monoton **nem csökkenő** (NEM szigorúan növekvő — egy
   OD-04-szintetizált (onset, strum) pár AZONOS `sampleIndex`-en él);
   ugyanazon `sampleIndex`-en legfeljebb egy event **típusonként** (ez a
   dedup-szabály, változatlan). Holtverseny (azonos `sampleIndex`, két
   különböző típus): az **`OnsetEvent` a listában megelőzi a hozzá
   `onsetEventId`-vel kapcsolódó `StrumEvent`-et** (ADR 0228 8. döntés,
   §0.0.2 — Terra dispatch #1 stopped-jelzésének feloldása).
   **NEM elfogadható:** a kombinált lista „szigorúan monoton" (duplikátum
   sampleIndex SEHOL, típustól függetlenül) — ez matematikailag
   kizárná minden OD-04-pár létezését.
6. **A confidence itt még nyers, de JELÖLT:** minden event `confidenceSource`
   mezőt kap (`heuristic`/`crnn`/`calibrated`); a kalibráció az R19 dolga.
   **NEM elfogadható:** kalibrálatlan érték `calibrated` jelöléssel.
7. **A bővítés additív és hátrafelé kompatibilis** ([ADR 0215](../adr/0215-analysis-document-versioning.md)
   4. döntés — H3 self-heal revízió, §0.0): az ÚJ mezők nem törölhetnek, nem
   nevezhetnek át és nem alakíthatnak át meglévő mezőt; a meglévő, NEM
   allowed_paths-on lévő hívók (`legacy_analyze_adapter.dart`,
   `analysis_document_codec.dart`, `analysis_timeline_test.dart`,
   `legacy_analyze_adapter_test.dart`, `analysis_document_codec_test.dart`)
   a mai, minimális konstruktor-hívással **VÁLTOZATLANUL** fordulnak és
   futnak. **NEM elfogadható:** bármelyik új mező kötelező (nem-nullable,
   alapérték nélküli) paraméterré tétele — lásd OD-03.

### 5.1 Nyitott döntések — előre rögzített feloldással

```yaml
open_decisions:
  - id: OD-01
    question: Az attack strength és a local RMS honnan jön?
    blocking: true
    resolution_policy: use_default
    default: >-
      a builder SAJÁT, dokumentált ablakából számol az R08 originalSamples
      pufferén (attack peak = |max| a [t, t+20 ms] ablakban; local RMS =
      RMS a [t−5 ms, t+45 ms] ablakban), NEM a LivePipeline belső értékeiből
      — így nem kell új cross-feature import, és a mennyiség auditálható.
  - id: OD-02
    question: Mekkora a minimum separation?
    blocking: true
    resolution_policy: use_default
    default: >-
      50 ms — pontosan a mai `_bpmFromStrums` `dt > 0.05` szűrőjének értéke
      (clip_analyzer.dart 234), hogy a V2 ne szűrjön MÁSHOGY, mint a V1
      tempószámítás. Az érték néven nevezett konstans, doc-commenttel.
  - id: OD-03
    question: >-
      Az OnsetEvent/StrumEvent bővítés hogyan marad additív, ha a típus MÁR
      élt a codec/legacy-adapter/teszt oldalán (H3 self-heal mérés, §0.0)?
    blocking: true
    resolution_policy: use_default
    default: >-
      minden ÚJ mező (directionConfidence, attackStrength, localRms,
      confidenceSource, fallbackReason) opcionális/nullable vagy
      dokumentált alapértékes named paraméter a MEGLÉVŐ konstruktoron — a
      codec (`analysis_document_codec.dart`) és a
      `legacy_analyze_adapter.dart` emiatt NEM allowed_paths elem és NEM is
      módosul ebben a körben; a codec az új mezőket egyelőre NEM
      (de)szerializálja (szándékos, dokumentált rés — lásd §9). Az `id`
      mező TÍPUSA nem változik: az `EventId`-generátor a determinisztikus
      `<runId>:<type>:<sampleIndex>` stringet a meglévő `String id` mezőbe
      írja.
  - id: OD-04
    question: >-
      A LegacyEvidence nem hordoz független onset-listát (csak strums/
      chords, mérve — §0.0.1) — honnan jön akkor a StrumEvent.onsetEventId
      által hivatkozott OnsetEvent?
    blocking: true
    resolution_policy: use_default
    default: >-
      a builder minden `LegacyStrumEvidence`-bejegyzéshez PONTOSAN egy
      `OnsetEvent`-et szintetizál, azonos `time`/`sampleIndex`-szel, mint a
      belőle épített `StrumEvent` (ez tükrözi a mai V1 szemantikát — §2: „az
      onset és a strum azonos fogalom"), és a `StrumEvent.onsetEventId`-je
      erre az `OnsetEvent.id`-re mutat. A minimum-separation/suppression a
      (onset, strum) PÁRT egy egységként kezeli: ha a strum elnyomásra kerül
      (OD-02), a hozzá tartozó szintetizált onset IS a diagnosztikai ágba
      kerül, nem marad árva (hivatkozás nélküli) esemény a publikus
      listában. **NEM elfogadható:** a strum elnyomása anélkül, hogy a
      párja onsetje is elnyomásra kerülne (ez árva `OnsetEvent`-et hagyna a
      publikus timeline-ban).
```

## 6. Acceptance criteria

- [ ] **Paritás a V1 időbélyegekkel:** az R09 evidence-ből épített
      `StrumEvent` lista **darabszámra** és **időre** (|Δ| ≤ 1 µs) egyezik a
      V1 `TimelineStrum` listával, és az irányok azonosak — mind a kilenc
      R09-fixture-re.
- [ ] **Minimum separation küszöb hármas** (`Duration`-alapú összehasonlítás,
      ADR 0228 3. döntés — a builder a `.time`-ot hasonlítja, NEM a
      `sampleIndex`-et; a bemenet KÉT `LegacyStrumEvidence`, azaz KÉT
      (onset, strum) PÁR, OD-04 — a separation a két pár közös
      `sampleIndex`-ét/`time`-ját hasonlítja, a §0.0.2/8. döntés szerint,
      NEM egy páron belüli onset↔strum távolságot, ami mindig 0):
      a fixture 48 000 Hz-en épül — a két pár **2399** minta (49,98 ms)
      távolságra → a **második PÁR** (mindkét eseménye: onset ÉS strum)
      **elnyomva**; **2400** minta (50,00 ms) → a második pár **megmarad**
      (a határ inkluzív); **2401** minta (50,02 ms) → megmarad. A
      mintaszámokat `python3 -c`-vel számolva. **Ugyanezt a hármat 44100
      Hz-es bemeneten is** (a kilenc R09-fixture rátája, `python3 -c
      'print(0.05*44100)'` → 2205,0) meg kell ismételni: **2204** minta
      (49,98 ms) → a második pár elnyomva; **2205** minta (50,00 ms) →
      megmarad; **2206** minta (50,02 ms) → megmarad — igazolva, hogy a
      builder NEM egy 48 kHz-re hardkódolt mintaszám-küszöböt tartalmaz.
- [ ] **Suppression-diagnosztika (ADR 0228 7. döntés — a suppression a
      (onset, strum) párt ATOMIKUSAN kezeli, §0.0.1):** a fenti 2399-mintás
      cellában a diagnosztikai lista **pontosan 2** bejegyzést tartalmaz — a
      második pár `OnsetEvent`-je ÉS `StrumEvent`-je, mindkettő okkal és
      időponttal —; a publikus lista **pontosan 2** eseményt tartalmaz — az
      **első** pár `OnsetEvent`-je és `StrumEvent`-je. **NEM elfogadható:**
      „1 esemény" bármelyik listán — egy PÁR sosem bomlik szét a
      suppression során (ld. §5 pont 1/OD-04: árva `onsetEventId` tilos).
- [ ] **`onsetEventId` integritás (OD-04):** minden publikált `StrumEvent`
      `onsetEventId`-je egy, a UGYANABBAN a buildben jelen lévő `OnsetEvent`
      `id`-jére mutat, azonos `time`/`sampleIndex`-szel; ha egy strum
      elnyomásra kerül, a párja onset is a diagnosztikai ágba kerül (nincs
      árva onset a publikus listában, és nincs `null`-ra vagy nem létező
      ID-re mutató `onsetEventId` egyetlen publikált strumon sem).
- [ ] **Event ID determinizmus:** ugyanaz a bemenet kétszer építve **azonos**
      ID-listát ad; **eltérő** runId esetén az ID-k eltérnek, de a sorrend és a
      típus/sampleIndex rész azonos.
- [ ] **Rendezettség + duplikátummentesség property (ADR 0228 8. döntés,
      §0.0.2):** `PROPERTY_SEED`-ből vezérelt véletlen onset-halmazokra a
      kimenet `sampleIndex`-e **monoton nem csökkenő**, és nincs két azonos
      `(type, sampleIndex)` pár. **Külön (nem property-, hanem determinisztikus
      unit-teszt) eset:** egyetlen `LegacyStrumEvidence`-ből épített
      (onset, strum) pár a kimenetben **AZONOS `sampleIndex`-en, egymás
      mellett** jelenik meg, ebben a sorrendben: `OnsetEvent` majd a hozzá
      `onsetEventId`-vel kapcsolódó `StrumEvent` — ez NEM sérti a monoton
      nem csökkenő szabályt, és NEM azonos `(type, sampleIndex)` pár (a két
      esemény típusa különböző).
- [ ] **Határeset-mátrix:** onset a **0.** mintán; onset az **utolsó** mintán;
      üres bemenet; egyetlen esemény — mind a négy kontrollált kimenetet ad
      (nem dob, nem ad negatív időt).
- [ ] **Confidence tartomány:** minden event confidence-e `[0,1]`-ben, és
      egyetlen event sem `NaN` — property-teszt méri.
- [ ] **Legacy view paritás:** `LegacyViewAdapter` a V2 eseményekből olyan
      `TimelineStrum` listát ad, amit a `timeline_view.dart` renderel — a
      mai widget-teszt (`test/features/analyze/timeline_view_test.dart`)
      **átírás nélkül** zöld marad (a gate méri).
- [ ] **`confidenceSource` őr:** teszt méri, hogy egyetlen R10-ben előállított
      event sem kap `calibrated` forrást.

> **Küszöb-konvenció:** minden numerikus küszöbhöz a mátrix **három** cellát
> ad — szigorúan **alatta**, pontosan **rajta**, szigorúan **fölötte** —, és a
> cellák értékei `python3 -c`-vel kiszámoltak, nem idealizált rácsból becsültek
> ([`docs/LESSONS.md`](../LESSONS.md) L13).

### 6.1 Mérce-mátrix — melyik hibás implementációt fogja pirosra

| Hibás implementáció | Melyik cella vált PIROSRA |
|---|---|
| Egyetlen event-típus `isStrum` flaggel | a fordítás (két külön típus a szerződés) + a `onsetEventId` hivatkozás cella |
| A minimum separation `<` helyett `<=` | a **pontosan 2400 mintás** (pár-szintű) cella |
| A suppressed event némán eltűnik | a suppression-diagnosztika „pontosan 2 bejegyzés" cella |
| A suppression csak a strumot vagy csak az onsetet nyomja el a párból, nem mindkettőt | a suppression-diagnosztika PONTOS SZÁMLÁLÁSA (2 ≠ 1 a diagnosztikai listán) + az `onsetEventId` integritás cella |
| Az event ID `hashCode`-ból készül | az ID-determinizmus cella |
| Az ID globális számlálóból | a „két külön build azonos ID-t ad" cella |
| Csak `Duration` kerül tárolásra, sample index nem | a 0. és az utolsó mintás határeset-cella (kerekítés miatt elcsúszik) |
| A V2 más szűrést alkalmaz, mint a V1 | a paritás-cella (darabszám) a kilenc fixture-ön |
| A nyers CRNN-confidence `calibrated`-ként jelölve | a `confidenceSource` őr |
| A minimum separation `sampleIndex`-et hasonlít rögzített mintaszám-küszöbhöz (nem `Duration`-t) | a **44100 Hz-es** 2205-mintás hármas cella (a 48 kHz-es cella ekkor is zöld maradna — csak a 44100 Hz-es leplezi le) |
| A strum elnyomásra kerül, de a párja `OnsetEvent` a publikus listában marad (árva hivatkozás) | az `onsetEventId` integritás cella (OD-04) |
| A holtverseny sorrendje `StrumEvent` majd `OnsetEvent` (megfordítva) | a §6 „egyetlen `LegacyStrumEvidence`" unit-teszt (ADR 0228 8. döntés) |
| A rendezés szigorúan monotonra kényszerül (pl. a StrumEvent sampleIndexét +1-gyel eltolja, hogy „ne ütközzön") | a `onsetEventId` integritás cella (a `time`/`sampleIndex` már nem egyezne az OnsetEvent-tel) + a V1-paritás cella (a strum ideje eltolódna) |
| **Valódi-sértés próba (§10):** a duplikátumszűrés ideiglenes kiszedése → a rendezettség/dedup property **PIROS** → visszaállítás |

## 7. Kötelező ellenőrzések

```bash
tools/round-gate.sh test/features/audio_analysis test/property test/features/analyze
```

Külön processzek, nincs `&&`/pipe/`tail`.

## 8. Implementációs sorrend

1. RED: paritás-, separation-, ID- és határeset-mátrix.
2. `event_id.dart` (ÚJ) + a MEGLÉVŐ `OnsetEvent`/`StrumEvent` bővítése
   additív mezőkkel (`domain/analysis_event.dart`, §0.0/OD-03).
3. `event_timeline_builder.dart` (rendezés, dedup, suppression, attack/RMS).
4. `LegacyViewAdapter` bővítése + a V1 widget-teszt zöldjének igazolása.
5. Property-teszt; gate.

## 9. Kockázatok

- **Az attack/RMS ablakok új DSP-mennyiségek** — a doc-comment rögzíti a
  képletet és az ablakhosszt; ha a §10-ben mért érték a V1 confidence-től
  érdemben eltér, az **follow-up**, nem a mérce lazítása.
- **A `timeline_view.dart` shape-je** kötött: a `LegacyViewAdapter` a **mai**
  `TimelineStrum` alakot kell adja; ha ez nem lehetséges, `stopped`.
- **A separation-érték összekötése a V1 BPM-szűrővel** szándékos; ha a V1
  értéke a pre-flightban más, a briefet **javítani kell**, nem a tesztet.
- **A codec egyelőre NEM szerializálja az új mezőket** (OD-03 — additív,
  [ADR 0215](../adr/0215-analysis-document-versioning.md) 4. pontja szerint
  ehhez nem kell séma-verzió-emelés, DE kódváltozás nélkül az
  `AnalysisDocumentCodec.encode`/`decode` csendben eldobná őket). Ez
  **szándékos, dokumentált rés** ebben a körben (a codec nincs
  `allowed_paths`-on) — a §6 acceptance nem kéri a codec-fidelitást, csak a
  `LegacyViewAdapter` paritást. Follow-up: amikor egy jövőbeli kör
  ténylegesen perzisztálja a builder kimenetét, a codec bővítése (és egy
  dedikált round-trip teszt) kötelező előfeltétel.
- **A `domain/analysis_event.dart` mostantól nem izolált, ÚJ fájl, hanem egy
  öt korábbi, merge-elt kör által fogyasztott, megosztott szerződés**
  (codec, `legacy_view_adapter.dart`, `legacy_analyze_adapter.dart`, három
  teszt). A diffnek `git diff` szinten kell bizonyítania, hogy ezek a NEM
  allowed_paths-on lévő fogyasztók bitre változatlanok maradnak (§5 pont 7)
  — ha a reviewer ezt nem tudja megerősíteni, MAJOR.
- **Ugyanez a hibaosztály (fájlnév→típusnév ütközés) él még három nyitott
  Epic 6 briefben** (R11 `ChordSegment`, R12 `TempoPoint`, R17
  `PitchSegment` — mérve `tools/brief-lint.py --all --level strict`, `S5`
  lelet). Ez a self-heal kör **szándékosan nem nyúlt hozzájuk** (a
  jogosultság kizárólag a HALT-olt körre szól) — mindegyiket a SAJÁT
  pre-flightjuk revideálja, ugyanezzel a mintával.

**STOP:** új cross-feature import, DSP-konstans vagy V1-módosítás helyett
`stopped` + brief-revízió.

## 10. Implementation handoff — az implementer tölti ki

- **Commitok:** `aac4d849` (`EventId`) és `38a13809` (evidence model +
  timeline builder); branch: `codex/e06-r10-event-evidence-onset-strum-timeline`.
- **Módosítások:** a meglévő `OnsetEvent`/`StrumEvent` additív evidence
  mezőket kapott; az új, stateless `EventId` `<runId>:<type>:<sampleIndex>`
  azonosítót készít; az `EventTimelineBuilder` V1 `LegacyEvidence`-ből
  atomikus onset/strum párokat épít, `Duration`-alapú 50 ms suppressionnel,
  diagnosztikával és eredeti PCM-ből mért attack/RMS értékekkel. A meglévő
  `LegacyViewAdapter` változtatás nélkül már a V2 `StrumEvent`-eket vetíti a
  mai `TimelineStrum` alakra, ezért kódmódosítás nem volt szükséges.
- **Lefuttatott ellenőrzések:**
  `flutter test test/features/audio_analysis/domain/analysis_event_test.dart test/features/audio_analysis/domain/event_id_test.dart test/features/audio_analysis/engine/event_timeline_builder_test.dart test/property/analysis_event_timeline_property_test.dart`
  → 13 teszt zöld; `tools/round-gate.sh test/features/audio_analysis
  test/property test/features/analyze` → format, analyze, mindhárom tesztág,
  architecture, secrets és l10n zöld; `python3 tools/scope-audit.py ...`
  → `scope_audit=ok` (10/10 changed path az allowed scope-ban).
- **Javító kör 1 (F1/F2, 2026-08-12):**
  `flutter test test/features/audio_analysis/engine/event_timeline_builder_test.dart`
  → 9 teszt zöld, köztük a „preserves V1 strum timestamps, counts, and
  directions for R09 fixtures” (a `ClipAnalyzerStage` kilenc R09-fixture-e,
  V1 darabszám/idő/irány paritással; zero-rate esetben builder nélkül üres
  eredmény) és a „measures attack strength and local RMS from original PCM”
  (0.9-es peak, `localRms = 0.5108624004141064`, 1e-9 tűrés). A teljes,
  csonkítatlan `tools/round-gate.sh test/features/audio_analysis test/property
  test/features/analyze` futás sikeres: format (1294 fájl, 0 változás),
  analyze (No issues found), mindhárom tesztág, architecture, secrets és l10n
  zöld. `python3 tools/scope-audit.py --repo /home/ubuntu/ss-terra-e06-r10
  --brief docs/rounds/e06-r10-event-evidence-onset-strum-timeline.md --base
  8c2e43ae --kv` → `scope_audit=ok`, 12 changed path az allowed scope-ban.
- **Nem futtatott ellenőrzések:** teljes `flutter test`, friss seedelt property
  gate és release APK — a kör szabálya szerint a CI/orchestrátor futtatja;
  lokális APK-build szándékosan nem futott.
- **Ismert rés/kockázat:** az új evidence mezőket a codec ebben a körben még
  nem perzisztálja (OD-03, dokumentált scope-határ); a builder még nincs a
  shipping V1 útvonalra kötve, ezért a meglévő termékviselkedés változatlan.

## 11. Review — a független reviewer tölti ki

Tervezett review: `docs/reviews/e06-r10-event-evidence-onset-strum-timeline-review.md`.
Merge csak exact-SHA zöld CI, §4-en belüli diff és nulla OPEN BLOCKER/MAJOR után.
