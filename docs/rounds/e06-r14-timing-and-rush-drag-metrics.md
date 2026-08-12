# E06-R14 — Timing és rush/drag metrikák

- **Státusz:** PREPARED (előre megírva 2026-08-07, kód olvasva: main @ `a6e6f3d`)
- **SDD-kör:** [`docs/sdd/07-epic-06-audio-analysis-2.md`](../sdd/07-epic-06-audio-analysis-2.md) Kör 14; §15.2–15.5
- **Branch:** `codex/e06-r14-timing-and-rush-drag-metrics`
- **Előfeltétel:** **E06-R13 merge**
- **Brief szerzője:** Claude (batch) · **Implementáció:** Codex (Terra)

```ai-router
schema_version = 1
risk = "high"
allowed_paths = [
  "lib/features/audio_analysis/engine/metrics/timing_metrics.dart",
  "lib/features/audio_analysis/engine/metrics/timing_hotspots.dart",
  "lib/features/audio_analysis/engine/metrics/metric_gate.dart",
  "lib/features/audio_analysis/domain/analysis_metric_catalog.dart",
  "lib/features/audio_analysis/public.dart",
  "lib/l10n/app_en.arb",
  "lib/l10n/app_hu.arb",
  "test/features/audio_analysis/domain/timing_metric_catalog_test.dart",
  "test/features/audio_analysis/engine/timing_metrics_test.dart",
  "test/features/audio_analysis/engine/timing_hotspots_test.dart",
  "test/property/analysis_timing_property_test.dart",
  "docs/adr/0232-timing-metric-identity-and-publication-boundary.md",
  "docs/rounds/e06-r14-timing-and-rush-drag-metrics.md",
  "docs/reviews/e06-r14-timing-and-rush-drag-metrics-review.md",
]
gate_tests = [
  "test/features/audio_analysis",
  "test/property",
  "test/app",
]
native_gate = false
```

> ⚠ **Pre-flight (KÖTELEZŐ):** friss `origin/main` + E06-R13 merge. Olvasd újra
> az R13 `AlignmentResult` **tényleges** mezőneveit és az R02
> `analysis_metric_catalog.dart` mai tartalmát — a katalógus bővítése
> **additív**, meglévő ID **nem nevezhető át** (ADR 0203). Ellenőrizd az
> ARB-fájlok mai kulcsstruktúráját és a hu/en **paritás-őrt** (ha van külön
> teszt, azt is a gate-be kell venni). PREPARED→PLANNING, brief commit előbb.

## 0. Kör-jelzés és STOP-protokoll

```bash
tools/codex-signal.sh progress "<egy sor>" ; tools/codex-signal.sh done "<egy sor>"
tools/codex-signal.sh stopped "<egy sor>" ; tools/codex-signal.sh blocked "<egy sor>"
```

Lezáró jelzés nélkül a kör bukott. Listán kívüli fájl → `stopped`.

## 0.0 Tervezési baseline és pre-flight revízió

**PREPARED → PLANNING (R1 pre-flight, 2026-08-12, orchestrator).**
`tools/round-slots.py reserve-adr --round E06-R14` a **0232** számot
foglalta. A batch brief régi `ADR 0203`/`0204` hivatkozásai az E06-R02-ben
dokumentált számozás-eltolódás miatt a tényleges [ADR 0218](../adr/0218-analysis-metric-id-and-version-governance.md) és
[ADR 0219](../adr/0219-analysis-capability-aware-publication.md) dokumentumokra
mutatnak; a 0203/0204 fájlok nem léteznek. Az új [ADR 0232](../adr/0232-timing-metric-identity-and-publication-boundary.md)
az e körben ténylegesen bővülő katalógus saját identity- és publikációs
határát rögzíti.

Mérés a friss `main`-en (`76f18991`): az R13
`AlignmentMatch.timingError` már pontosan `observed.time - expected.time`
(negatív = early, pozitív = late), `AlignmentResult` mezői `matches`,
`missedExpected`, `extraObserved`, `confidence`; a `TolerancePolicy` 120
BPM-en 125 ms-t ad, és 126 ms már nem párosítható. A meglévő
`timing.mean_absolute_error.v1` csak az R02 által előre felvett, általános
katalógus-konstans: nem nevezhető át és nem használható az új mode-szétválasztás
helyett. Ezért R14 kizárólag új, `timing.target_*` és `timing.freeplay_*`
ID-kat ad hozzá, az eredeti konstans változatlan marad.

A kötelező review-artefaktum és a saját ADR explicit bekerült az
`allowed_paths` listába, így a review commitolható scope-sértés nélkül
(LESSONS L88).

## 1. Cél

A target-alapú timing visszajelzés tíz kötelező metrikája, **helyes
előjellel**, tempófüggő toleranciával, minimum-eseményszám kapuval és
timing-hotspotokkal — a free-play timing **külön metric ID** alatt.

## 2. Jelenlegi állapot (mért, `a6e6f3d`)

- **Nincs semmilyen timing metrika** az Analyze úton. Az `AnalyzeResult`
  `bpm` + `strums` + `chords` triót ad; sem eltérés, sem sietés/késés fogalom
  nincs.
- A Practice Engine V2 rendelkezik saját pontozással
  (`practice_scorer_property_test.dart`, `practice_metrics.dart`) — ezt az
  Epic 6 **nem írja felül** (SDD §27.1).
- Az R13 adja az `AlignmentResult`-ot (matched párok `Δt`-vel, missed, extra),
  az R12 a beat-rácsot, az R07 a jelminőséget.
- Az ARB-fájlok: `lib/l10n/app_en.arb` (1 313 sor), `app_hu.arb` (1 247 sor);
  az `analyze` prefixű kulcsok száma **11**.

## 3. Scope

**Benne:** a tíz kötelező timing metrika (`mean absolute error`,
`median absolute error`, `p90`, `signed bias`, `on-time ratio`, `early ratio`,
`late ratio`, `missed ratio`, `extra ratio`, `longest stable streak`);
tempófüggő tolerance-policy **felhasználása** (az R13 policy-ját hívja);
`MetricGate` (minimum eseményszám → `unavailable`); timing hotspotok;
free-play külön metric ID; a metric katalógus **additív** bővítése; a
metrikanevek és a sietés/késés **külön** üzenetkulcsai en+hu ARB-ben.

**Kívül — TILOS:** ritmus/groove (R15), dinamika (R16), confidence-kalibráció
(R19), insightok (R20), UI-widget, a Practice pontozás érintése.

## 4. Engedélyezett fájlok

| Útvonal | Állapot | Miért |
|---|---|---|
| `.../engine/metrics/timing_metrics.dart` | ÚJ | a tíz metrika |
| `.../engine/metrics/timing_hotspots.dart` | ÚJ | hotspot-építés |
| `.../engine/metrics/metric_gate.dart` | ÚJ | minimum eseményszám kapu |
| `.../domain/analysis_metric_catalog.dart` | meglévő | **additív** ID-k |
| `.../public.dart` | meglévő | export |
| `lib/l10n/app_en.arb`, `app_hu.arb` | meglévő | **additív** üzenetkulcsok |
| `test/**` | ÚJ | metrika + hotspot + property |

**Tilos zóna:** `lib/features/practice/**`, `lib/features/analyze/**`,
`lib/features/audio_analysis/presentation/**`. Listán kívül → `stopped`.

## 5. Kötött architekturális döntések

1. **Az előjel-konvenció kötött** (SDD §15.2): `error = observed − expected`;
   **negatív = sietés**, **pozitív = késés**. **NEM elfogadható:** fordított
   konvenció „mert a UI-nak úgy kényelmesebb" — a UI a `messageKey`-vel
   fordít.
2. **A sietés és a késés KÜLÖN üzenetkulcs**, nem egyetlen kulcs előjeles
   számmal. **NEM elfogadható:** `analysisTimingBias` egyetlen kulccsal.
3. **Reference nélkül nincs target-timing metrika** (SDD §15.5): free-play
   módban a metrikák **külön ID**-t kapnak
   (`timing.freeplay_*`, a target-alapú `timing.target_*`), és a free-play
   confidence a beat-rács confidence-ének függvénye.
   **NEM elfogadható:** azonos metric ID a két módban.
4. **Minimum eseményszám kapu:** a kapu alatt a metrika **`unavailable`**
   `insufficientEvents` okkal — nem 0, nem `null`, nem `NaN`.
   **NEM elfogadható:** „0 eseményből 0 ms hiba".
5. **A hotspot evidence-re mutat vissza:** minden timing hotspot tartalmazza
   az érintett **event ID-ket** (R10) és a metric ID-ket.
   **NEM elfogadható:** hotspot event-hivatkozás nélkül.
6. **A metrikák ID-je és verziója a katalógusból** (ADR 0203); a
   `sampleCount` minden metrikán kitöltött.

### 5.1 Nyitott döntések — előre rögzített feloldással

```yaml
open_decisions:
  - id: OD-01
    question: Mennyi a minimum eseményszám?
    blocking: true
    resolution_policy: use_default
    default: >-
      8 MATCHED pár (nem összes observed) — néven nevezett konstans;
      a `longest stable streak` külön, 3 pár minimummal (különben
      a streak fogalma értelmetlen).
  - id: OD-02
    question: Mi az "on-time"?
    blocking: true
    resolution_policy: use_default
    default: >-
      |error| <= tolerance (az R13 TolerancePolicy ugyanazon értéke) —
      a HATÁR INKLUZÍV, és ugyanaz a szám, amivel az illesztés dolgozott;
      külön "szigorúbb on-time ablak" NEM kerül bevezetésre.
  - id: OD-03
    question: Hogyan számoljon a p90?
    blocking: true
    resolution_policy: use_default
    default: >-
      lineáris interpolációjú percentilis a rendezett |error| listán
      (a `numpy` "linear" módszerével egyező), a képlet a doc-commentben,
      és a teszt egy KÉZZEL kiszámolt, python3-mal ellenőrzött értékre mér.
```

## 6. Acceptance criteria

- [ ] **Előjel-mátrix — négy cella:** minden esemény **korán** (−30 ms) →
      `signedBias < 0`, `earlyRatio == 1.0`, `lateRatio == 0.0`;
      minden **későn** (+30 ms) → tükörkép; **váltakozó** (±30 ms) →
      `signedBias ≈ 0` (|Δ| ≤ 1e−9) de `meanAbsoluteError == 30 ms`;
      **tökéletes** → minden hibametrika 0, `onTimeRatio == 1.0`.
- [ ] **On-time küszöb hármas** (120 BPM, tolerancia 125 ms):
      **124 ms**, **125 ms**, **126 ms** eltérésű esemény — a **125 ms**
      on-time (inkluzív), a **126 ms** nem *és* az R13 szerint **nem is
      párosul** → `extra`+`missed`. A cellák a `python3 -c`-vel számolt
      értékekkel.
- [ ] **p90 kézi cella:** tíz elemű, ismert |error| lista
      (`[0,10,20,30,40,50,60,70,80,900]` ms) → a p90 értéke a dokumentált
      képlet szerint **`python3 -c "import statistics"`-mal ellenőrzött**
      konkrét szám; a teszt erre mér, nem tartományra. A cella egyben azt is
      méri, hogy a **medián** (25 ms) és a **p90** érdemben eltér — ez a
      „néhány nagy hiba dominál" insight (R20) alapja.
- [ ] **Minimum eseményszám hármas:** **7 / 8 / 9** matched pár — a **8**
      esetén a metrika `available` (inkluzív), a 7 esetén `unavailable`
      `insufficientEvents` okkal, és a `value` **nem** 0.
- [ ] **Streak-mátrix:** `longest stable streak` a `[on, on, off, on, on, on]`
      sorozatra **3**; a `[off]*6`-ra **0**; a `[on]*3`-ra **3** (a 3-as
      minimumon); a `[on]*2`-re **`unavailable`** (a streak-minimum alatt).
- [ ] **Missed/extra arányok:** 10 expected + 8 observed, 7 párral →
      `missedRatio == 3/10`, `extraRatio == 1/8`; a nevezők a
      doc-commentben rögzítettek, és a teszt **mindkét** nevezőt méri.
- [ ] **Free-play elkülönítés:** free-play futásban a metric ID-k
      `timing.freeplay_*`, target futásban `timing.target_*`; teszt méri, hogy
      a két halmaz **diszjunkt**, és hogy free-play confidence ≤ a beat-rács
      confidence-e.
- [ ] **Hotspot-visszamutatás:** minden generált hotspot `evidenceIds` listája
      **nem üres**, és minden ID **létező** eventre mutat (referenciális
      integritás-teszt).
- [ ] **ARB-paritás:** minden új kulcs **mindkét** ARB-ben szerepel, és a
      sietés/késés **két külön** kulcs; a `flutter analyze` zöld (a generált
      lokalizáció fordul).
- [ ] **NaN-mentesség property:** véletlen alignment-eredményekre egyetlen
      metrika sem `NaN`/`±Infinity`, minden arány `[0,1]`-ben.

> **Küszöb-konvenció:** minden numerikus küszöbhöz a mátrix **három** cellát
> ad — szigorúan **alatta**, pontosan **rajta**, szigorúan **fölötte** —, és a
> cellák értékei `python3 -c`-vel kiszámoltak, nem idealizált rácsból becsültek
> ([`docs/LESSONS.md`](../LESSONS.md) L13).

### 6.1 Mérce-mátrix — melyik hibás implementációt fogja pirosra

| Hibás implementáció | Melyik cella vált PIROSRA |
|---|---|
| Fordított előjel-konvenció | az „minden korán → `signedBias < 0`" cella |
| Egyetlen üzenetkulcs előjeles számmal | az ARB „két külön kulcs" cella |
| Az on-time ablak exkluzív | a **pontosan 125 ms** on-time cella |
| Külön, szigorúbb on-time ablak | a 124/125 ms cellák eltérő elvárt értéke |
| A p90 „nearest rank" módszerrel | a kézzel számolt p90 cella |
| A minimum eseményszám exkluzív | a **pontosan 8 pár** `available` cella |
| Gate alatt 0-t publikál | a „a `value` nem 0" cella |
| A missed nevezője az observed (nem expected) | a `missedRatio == 3/10` cella |
| A free-play és target azonos ID-t kap | a diszjunkt-ID cella |
| A hotspot nem hivatkozik eventre | a referenciális integritás cella |
| **Valódi-sértés próba (§10):** a minimum-eseményszám kapu ideiglenes kiszedése → a 7-páros `unavailable` cella **PIROS** → visszaállítás |

## 7. Kötelező ellenőrzések

```bash
tools/round-gate.sh test/features/audio_analysis test/property test/app
```

Külön processzek, nincs `&&`/pipe/`tail`.

## 8. Implementációs sorrend

1. Katalógus-bővítés (additív ID-k, target + freeplay).
2. RED: előjel-, küszöb-, p90-, streak- és arány-mátrix.
3. `metric_gate.dart` (minimum eseményszám).
4. `timing_metrics.dart` (a tíz metrika, dokumentált képletekkel).
5. `timing_hotspots.dart` (evidence-visszamutatás).
6. ARB-kulcsok en+hu; property; gate.

## 9. Kockázatok

- **A p90 definíciója** csendben eltérhet a későbbi eval-harness (R29)
  számításától — ezért a képlet a doc-commentben és a tesztben **kézzel
  kiszámolt** értékkel rögzített.
- **A missed/extra nevezői** könnyen felcserélődnek — a teszt mindkettőt
  külön méri.
- **Az ARB közös fájl** — kizárólag additív; meglévő kulcs átírása azonnali
  BLOCKER.

**STOP:** a Practice pontozás átírása, meglévő metric ID átnevezése vagy a
tolerancia „finomhangolása" helyett `stopped` + brief-revízió.

## 10. Implementation handoff — az implementer tölti ki

_(üres)_

## 11. Review — a független reviewer tölti ki

Tervezett review: `docs/reviews/e06-r14-timing-and-rush-drag-metrics-review.md`.
Merge csak exact-SHA zöld CI, §4-en belüli diff és nulla OPEN BLOCKER/MAJOR után.
