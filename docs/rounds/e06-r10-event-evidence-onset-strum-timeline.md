# E06-R10 — Event evidence modell és onset/strum timeline V2

- **Státusz:** PREPARED (előre megírva 2026-08-07, kód olvasva: main @ `a6e6f3d`)
- **SDD-kör:** [`docs/sdd/07-epic-06-audio-analysis-2.md`](../sdd/07-epic-06-audio-analysis-2.md) Kör 10; §9.6, §13.1–13.2
- **Branch:** `codex/e06-r10-event-evidence-onset-strum-timeline`
- **Előfeltétel:** **E06-R09 merge**
- **Brief szerzője:** Claude (batch) · **Implementáció:** Codex (Terra)

```ai-router
schema_version = 1
risk = "high"
allowed_paths = [
  "lib/features/audio_analysis/domain/events/onset_event.dart",
  "lib/features/audio_analysis/domain/events/strum_event.dart",
  "lib/features/audio_analysis/domain/events/event_id.dart",
  "lib/features/audio_analysis/engine/events/event_timeline_builder.dart",
  "lib/features/audio_analysis/data/legacy_view_adapter.dart",
  "lib/features/audio_analysis/public.dart",
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

## 0. Kör-jelzés és STOP-protokoll

```bash
tools/codex-signal.sh progress "<egy sor>" ; tools/codex-signal.sh done "<egy sor>"
tools/codex-signal.sh stopped "<egy sor>" ; tools/codex-signal.sh blocked "<egy sor>"
```

Lezáró jelzés nélkül a kör bukott. Listán kívüli fájl → `stopped`.

## 0.0 Tervezési baseline és pre-flight revízió

**PREPARED.** Új ADR nincs.

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
- **Nincs** sample index, **nincs** event ID, **nincs** attack strength vagy
  local RMS, **nincs** suppression-diagnosztika, és a `confidence` a CRNN
  vagy a heurisztika nyers értéke (kalibrálatlan).
- A `timeline_view.dart` a `TimelineStrum` listát rendereli
  (`isDown` alapján ↓/↑).
- Az R09 `LegacyEvidence` adja a nyers strum/chord listát + a hívási
  paramétereket.

## 3. Scope

**Benne:** `OnsetEvent` és `StrumEvent` **külön** típus (sample index,
`Duration` idő, onset confidence, direction, direction confidence, attack
strength, local RMS, source, fallback flag); `EventId` stabil, **runon belül**
determinisztikus generálás; `EventTimelineBuilder` (rendezés, duplikátumszűrés,
minimum separation, suppression-diagnosztika); a `LegacyViewAdapter` bővítése,
hogy a V2 eseményekből a mai `TimelineStrum` lista előálljon.

**Kívül — TILOS:** onset-detektor **algoritmus** (a V1 SuperFlux marad),
DSP-konstans, chord (R11), beat (R12), `lib/features/analyze/**`,
`lib/features/live/**`.

## 4. Engedélyezett fájlok

| Útvonal | Állapot | Miért |
|---|---|---|
| `.../domain/events/onset_event.dart` | ÚJ | onset evidence |
| `.../domain/events/strum_event.dart` | ÚJ | strum evidence (irány + erő) |
| `.../domain/events/event_id.dart` | ÚJ | stabil ID-generálás |
| `.../engine/events/event_timeline_builder.dart` | ÚJ | rendezés/dedup/suppression |
| `.../data/legacy_view_adapter.dart` | meglévő | V2 → mai `TimelineStrum` |
| `.../public.dart` | meglévő | event típusok exportja |
| `test/features/audio_analysis/**`, `test/property/**` | ÚJ | tesztek |

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
2. `event_id.dart` + a két event típus.
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

**STOP:** új cross-feature import, DSP-konstans vagy V1-módosítás helyett
`stopped` + brief-revízió.

## 10. Implementation handoff — az implementer tölti ki

_(üres)_

## 11. Review — a független reviewer tölti ki

Tervezett review: `docs/reviews/e06-r10-event-evidence-onset-strum-timeline-review.md`.
Merge csak exact-SHA zöld CI, §4-en belüli diff és nulla OPEN BLOCKER/MAJOR után.
