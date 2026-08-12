# E06-R10 — Event evidence modell és onset/strum timeline V2

- **Státusz:** PREPARED → **revideálva** (ADR 0112 önjavító kör, H3, 2026-08-12
  — a §0.0 rögzíti a mért gyökérokot és a feloldást; eredetileg előre megírva
  2026-08-07, kód olvasva: main @ `a6e6f3d`)
- **SDD-kör:** [`docs/sdd/07-epic-06-audio-analysis-2.md`](../sdd/07-epic-06-audio-analysis-2.md) Kör 10; §9.6, §13.1–13.2
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
  fallback flag és suppression-diagnosztika — ezeket adja hozzá ez a kör,
  additív/opcionális mezőkkel (OD-03), és a `confidence` egyelőre továbbra is
  a CRNN vagy a heurisztika nyers, kalibrálatlan értéke marad.
- A `timeline_view.dart` a `TimelineStrum` listát rendereli
  (`isDown` alapján ↓/↑).
- Az R09 `LegacyEvidence` adja a nyers strum/chord listát + a hívási
  paramétereket.

## 3. Scope

**Benne:** a MEGLÉVŐ `OnsetEvent` és `StrumEvent` (`domain/analysis_event.dart`,
H3 self-heal revízió — §0.0) bővítése a hiányzó evidence-mezőkkel (a bázis
`confidence` marad az onset confidence; direction confidence, attack
strength, local RMS, source/`confidenceSource`, fallback flag ÚJ) —
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
   strum **hivatkozik** a saját onsetjére `onsetEventId`-vel.
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
5. **Az esemény-lista időrendben, duplikátummentesen** kerül ki: azonos sample
   indexen legfeljebb egy event típusonként.
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
```

## 6. Acceptance criteria

- [ ] **Paritás a V1 időbélyegekkel:** az R09 evidence-ből épített
      `StrumEvent` lista **darabszámra** és **időre** (|Δ| ≤ 1 µs) egyezik a
      V1 `TimelineStrum` listával, és az irányok azonosak — mind a kilenc
      R09-fixture-re.
- [ ] **Minimum separation küszöb hármas** (50 ms, 48 000 Hz-en 2400 minta):
      két onset **2399** minta távolságra → a második **elnyomva**;
      **2400** minta → a második **megmarad** (a határ inkluzív);
      **2401** minta → megmarad. A mintaszámokat `python3 -c`-vel számolva.
- [ ] **Suppression-diagnosztika:** a fenti 2399-mintás cellában a
      diagnosztikai lista **pontosan 1** bejegyzést tartalmaz, okkal és
      időponttal; a publikus lista **1** eseményt.
- [ ] **Event ID determinizmus:** ugyanaz a bemenet kétszer építve **azonos**
      ID-listát ad; **eltérő** runId esetén az ID-k eltérnek, de a sorrend és a
      típus/sampleIndex rész azonos.
- [ ] **Rendezettség + duplikátummentesség property:**
      `PROPERTY_SEED`-ből vezérelt véletlen onset-halmazokra a kimenet
      **szigorúan monoton** sample index szerint, és nincs két azonos
      `(type, sampleIndex)` pár.
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
| A minimum separation `<` helyett `<=` | a **pontosan 2400 mintás** cella |
| A suppressed event némán eltűnik | a suppression-diagnosztika „pontosan 1 bejegyzés" cella |
| Az event ID `hashCode`-ból készül | az ID-determinizmus cella |
| Az ID globális számlálóból | a „két külön build azonos ID-t ad" cella |
| Csak `Duration` kerül tárolásra, sample index nem | a 0. és az utolsó mintás határeset-cella (kerekítés miatt elcsúszik) |
| A V2 más szűrést alkalmaz, mint a V1 | a paritás-cella (darabszám) a kilenc fixture-ön |
| A nyers CRNN-confidence `calibrated`-ként jelölve | a `confidenceSource` őr |
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

_(üres)_

## 11. Review — a független reviewer tölti ki

Tervezett review: `docs/reviews/e06-r10-event-evidence-onset-strum-timeline-review.md`.
Merge csak exact-SHA zöld CI, §4-en belüli diff és nulla OPEN BLOCKER/MAJOR után.
