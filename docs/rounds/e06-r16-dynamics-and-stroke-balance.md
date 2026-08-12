# E06-R16 — Dynamics és stroke balance

- **Státusz:** PLANNING (előre megírva 2026-08-07; pre-flight lezárva
  2026-08-12, `main` @ `e6770867`, ADR 0234)
- **SDD-kör:** [`docs/sdd/07-epic-06-audio-analysis-2.md`](../sdd/07-epic-06-audio-analysis-2.md) Kör 16; §16.1–16.5
- **Branch:** `codex/e06-r16-dynamics-and-stroke-balance`
- **Előfeltétel:** **E06-R08, E06-R10 merge**
- **Brief szerzője:** Claude (batch) · **Implementáció:** Codex (Terra)

```ai-router
schema_version = 1
risk = "high"
allowed_paths = [
  "lib/features/audio_analysis/engine/metrics/dynamics_metrics.dart",
  "lib/features/audio_analysis/engine/metrics/accent_analysis.dart",
  "lib/features/audio_analysis/engine/metrics/dynamics_gate.dart",
  "lib/features/audio_analysis/domain/analysis_metric_catalog.dart",
  "lib/features/audio_analysis/public.dart",
  "lib/l10n/app_en.arb",
  "lib/l10n/app_hu.arb",
  "test/features/audio_analysis/domain/dynamics_metric_catalog_test.dart",
  "test/features/audio_analysis/engine/dynamics_metrics_test.dart",
  "test/features/audio_analysis/engine/accent_analysis_test.dart",
  "test/property/analysis_dynamics_property_test.dart",
  "docs/rag/chunks/022-dynamics-stroke-balance.md",
  "docs/adr/0234-dynamics-evidence-and-gating-boundary.md",
  "docs/rounds/e06-r16-dynamics-and-stroke-balance.md",
]
gate_tests = [
  "test/features/audio_analysis",
  "test/property",
  "test/app",
]
native_gate = false
```

> ⚠ **Pre-flight (KÖTELEZŐ):** friss `origin/main` + E06-R08/R10 merge.
> Olvasd újra az R08 `PreprocessedAudio.originalSamples` szerződését (a
> dinamika **kizárólag** ezt használhatja) és az R10 `StrumEvent`
> `attackStrength`/`localRms`/`clipped` mezőit — ha az R10 nem szállította
> valamelyiket, a hiányzó mennyiséget **ez a kör** számolja az
> `originalSamples`-ből, ugyanazzal az ablakkal (R10 §5.1 OD-01), és ezt a
> §0.0-ban rögzíteni kell. Ellenőrizd a chunk-sorszámot (várhatóan **022**).
> PREPARED→PLANNING, brief commit előbb.

## 0. Kör-jelzés és STOP-protokoll

```bash
tools/codex-signal.sh progress "<egy sor>" ; tools/codex-signal.sh done "<egy sor>"
tools/codex-signal.sh stopped "<egy sor>" ; tools/codex-signal.sh blocked "<egy sor>"
```

Lezáró jelzés nélkül a kör bukott. Listán kívüli fájl → `stopped`.

## 0.0 Tervezési baseline és pre-flight revízió

**Pre-flight mérés (2026-08-12, baseline `main` @ `e6770867`; E06-R08 és
E06-R10 merge-elve — előfeltétel teljesül). ADR:
[0234](../adr/0234-dynamics-evidence-and-gating-boundary.md).**

Minden hivatkozott mezőt a tényleges hívási láncon mértem, nem a korábbi
brief állapot-táblájából:

1. `PreprocessedAudio.originalSamples` valóban a dinamikai bemenet
   (`domain/preprocessed_audio.dart:3-19`), míg a normalizáció kizárólag a
   `canonicalSamples` másolatát módosítja
   (`engine/preprocessing/preprocessing_stage.dart:39-78`).
2. Az R10 `EventTimelineBuilder` minden megtartott `StrumEvent`-hez ad
   `sampleIndex`, `attackStrength` és `localRms` értéket eredeti PCM-ből,
   rendre `[t,t+20 ms]` és `[t-5 ms,t+45 ms]` ablakkal
   (`engine/events/event_timeline_builder.dart:134-178,190-237`). Nincs
   viszont `StrumEvent.clipped` mező. **Feloldás:** az R16 saját,
   `dynamics_metrics.dart`-beli belső event-adatában, a meglévő 20 ms-os
   attack-ablak `originalSamples` értékein, az R07 inkluzív `|sample| >=
   0.999` határával vezeti le a clipped jelzőt; az alap domain esemény és az
   R10 builder nem változik.
3. A `SignalQualityReport` a `measured` bitet hordozza
   (`domain/signal_quality_report.dart:4-35`), ezért a gate nem fogadhat el
   legacy/fabrikált (`measured == false`) számot jelbizonyítékként. **Feloldás:**
   ilyen reporttal a dinamika fail-closed `unavailable`, `internalFailure`
   okkal; a zaj-floor sávok csak mért, véges reportból értékelhetők.
4. A `MetricGate` jelenlegi minimuma 8 esemény (streakhez 3), és runtime-ban
   validálja a paramétereit (`engine/metrics/metric_gate.dart:10-45`); a
   dinamika ezt változatlanul használja, nem vezet be párhuzamos minimumot.

A chunk-sorszám mérve **022** (utolsó meglévő: `021-rhythm-consistency-groove-
proxies.md`). **Új mennyiség ⇒ RAG-chunk** ugyanabban a commitban.

## 1. Cél

A sessionön **belüli** pengetési erő és accent-kontroll mérése az **eredeti**
amplitúdó-arányokból, minőségi kapukkal — és **értékelő állítás nélkül**,
amíg nincs target.

## 2. Jelenlegi állapot (mért, `a6e6f3d`)

- A mai eredmény **egyetlen** dinamikai jelzést hordoz: a `TimelineStrum.
  confidence` (irány-magabiztosság, nem hangerő), plusz a `downCount`/
  `upCount` leíró számok (`analyze_result.dart` 149–150).
- **Nincs** attack peak, local RMS, normalizált erősség, dinamikai szórás,
  drift vagy accent-fogalom.
- A `StrumDirection` (`lib/core/music/strum.dart`) adja a down/up értéket.
- Az R07 riportja megadja a clipping és a túl-halk jel arányát — ezek a
  dinamika **kapui**.
- Az R08 garantálja, hogy az `originalSamples` normalizálatlan.

## 3. Scope

**Benne:** eventenkénti dinamikai értékek (attack peak, local RMS, normalizált
erősség a session **mediánjához** képest, clipped flag); a hét kötelező
metrika (stroke strength CV, down/up medián arány, dinamikai drift, outlier
arány, accent accuracy **targettel**, quiet region arány, clipped event arány);
`DynamicsGate` (clipping / auto-gain bizonytalanság / túl halk jel / backing
track dominancia); `AccentAnalysis`; katalógus + ARB; RAG-chunk.

**Kívül — TILOS:** normalizáció bekapcsolása (R08 flag), a sessionök **közötti**
összehasonlítás (R25), confidence-kalibráció (R19), UI.

## 4. Engedélyezett fájlok

| Útvonal | Állapot | Miért |
|---|---|---|
| `.../engine/metrics/dynamics_metrics.dart` | ÚJ | a hét metrika |
| `.../engine/metrics/accent_analysis.dart` | ÚJ | accent target-értékelés |
| `.../engine/metrics/dynamics_gate.dart` | ÚJ | minőségi kapuk |
| `.../domain/analysis_metric_catalog.dart` | meglévő | **additív** ID-k |
| `.../public.dart` | meglévő | export |
| `lib/l10n/*.arb` | meglévő | **additív** kulcsok |
| `test/**` | ÚJ | fixture + property |
| `docs/rag/chunks/022-…md` | ÚJ | képletek + küszöbök |

**Tilos zóna:** `lib/features/audio_analysis/engine/preprocessing/**`,
`lib/features/analyze/**`, `lib/features/live/**`. Listán kívül → `stopped`.

## 5. Kötött architekturális döntések

1. **A dinamika az EREDETI amplitúdókat használja** (ADR 0206 / R08 §5.2):
   a számítás bemenete `PreprocessedAudio.originalSamples`.
   **NEM elfogadható:** a `canonicalSamples` használata, még akkor sem, ha a
   default konfigurációban a kettő azonos referencia — a **típusszintű**
   választásnak helyesnek kell lennie, és ezt teszt méri (normalizáció
   bekapcsolva is).
2. **Target nélkül nincs értékelő állítás** (SDD §16.4): a down/up arány és a
   dinamikai szórás **leíró** metrika (`descriptive` irányultság, ADR 0203).
   **NEM elfogadható:** „egyenetlen a pengetésed" jellegű minősítés target
   nélkül, és **NEM elfogadható** a `lower is better` jelölés a down/up
   arányra.
3. **A sessionön belüli normalizálás a session mediánjához történik**, ami
   invariáns a felvételi hangerőre — teszt méri, hogy a teljes klip
   ×2 skálázása a normalizált erősségeket **nem** változtatja.
   **NEM elfogadható:** abszolút dBFS-küszöbre épített „erős/gyenge" ítélet.
4. **A kapuk fail-closed módon `unavailable`-t adnak:** clipping a
   `clippedEventRatio` küszöb felett, túl halk jel, vagy backing-track
   dominancia esetén a dinamikai metrikák **nem** publikálódnak értékként.
   **NEM elfogadható:** „degradált, de azért kiírjuk a számot" ok nélkül.
5. **A globális hangerőváltozás ≠ accent** (SDD §16.5): az accent-detektálás a
   **lokális** (mozgó ablakos) mediánhoz képest mér.
   **NEM elfogadható:** a session-szintű mediánhoz mért accent.
6. **A clipped event nem számít bele** a stroke-erősség statisztikákba, de
   **szerepel** a `clippedEventRatio`-ban.

### 5.1 Nyitott döntések — előre rögzített feloldással

```yaml
open_decisions:
  - id: OD-01
    question: Mi az "outlier"?
    blocking: true
    resolution_policy: use_default
    default: >-
      normalizált erősség a [medián − 2×MAD, medián + 2×MAD] tartományon kívül
      (MAD = medián abszolút eltérés); a 2-es szorzó néven nevezett konstans.
  - id: OD-02
    question: Mekkora a lokális accent-ablak?
    blocking: true
    resolution_policy: use_default
    default: >-
      a megelőző és követő 4-4 esemény (összesen 9 elemű, középre igazított)
      mozgó medián; a szélek csonkolt ablakkal, dokumentáltan.
  - id: OD-03
    question: Mikor "domináns" a backing track?
    blocking: true
    resolution_policy: use_default
    default: >-
      a V1-ben NEM mérhető megbízhatóan → a kapu bemenete az R07
      `tonalness`/`noiseFloor` proxyja: ha a noise floor a −35 dBFS fölött van,
      a dinamika `degraded`, ha −25 dBFS fölött, `unavailable`
      (`backingTrackDominant`). Az értékek ideiglenesek az R29-ig, a chunkban.
```

## 6. Acceptance criteria

- [ ] **Fixture-mátrix — hét cella:** azonos erősségű strokeok; monoton
      növekvő erősség (drift); váltakozó accent; **egy** kiugró outlier;
      clippelt attack; down/up egyensúlytalanság (down 2× erősebb);
      csendes szakasz a közepén.
- [ ] **Gain-invariancia:** ugyanaz a fixture ×2 és ×0.5 amplitúdóval —
      a `strokeStrengthCv`, a `downUpMedianRatio` és az `outlierRatio`
      **bitre azonos** (|Δ| ≤ 1e−12). Ez a cella méri, hogy a normalizálás a
      session mediánjához történik.
- [ ] **Normalizáció-immunitás:** az R08 normalizációs flag **bekapcsolva** is
      ugyanazok az értékek (|Δ| ≤ 1e−12) — ez a cella méri, hogy a számítás az
      `originalSamples`-ből dolgozik.
- [ ] **Outlier-küszöb hármas** (2×MAD): egy eseményt úgy hangolva, hogy a
      normalizált erőssége a mediántól **1.99×MAD**, **2.00×MAD** és
      **2.01×MAD** távolságra legyen — a **2.00×MAD** még **nem** outlier
      (a határ inkluzív a tartományra nézve), a 2.01×MAD igen.
      A három amplitúdót `python3 -c`-vel kell kiszámolni a fixture MAD-jából,
      és a levezetést a teszt kommentben rögzíti.
- [ ] **Clipping-kapu küszöb hármas** (`clippedEventRatio` küszöb = 0.05):
      20 eseményből **0 / 1 / 2** clippelt (arány **0.0 / 0.05 / 0.1**) —
      a **0.05** még `degraded` (inkluzív), a 0.1 már `unavailable`
      `inputClipped` okkal.
- [ ] **Noise-floor kapu hármas:** −35.01 / −35.0 / −34.99 dBFS
      (a −35.0 már `degraded`), és −25.01 / −25.0 / −24.99 dBFS
      (a −25.0 már `unavailable` `backingTrackDominant` okkal).
- [ ] **Accent lokalitás:** egy fixture, ahol a **teljes** klip hangereje
      fokozatosan nő, de **nincs** valódi accent → az `accentAccuracy`
      **nem** jelez accentet; ugyanez a fixture session-szintű mediánnal
      **hamis** accenteket adna — a teszt mindkét ágat kiszámolja és
      **különbözőnek** követeli.
- [ ] **Target-kapu:** target nélkül az `accent.accuracy` capability
      `notApplicable`, és a `dynamics.down_up_ratio` irányultsága
      `descriptive`; targettel az accent metrika `available`.
- [ ] **Clipped-esemény kizárás:** a clippelt attack fixture-ön a
      `strokeStrengthCv` **ugyanaz**, mint a clippelt esemény nélküli
      fixture-ön (|Δ| ≤ 1e−12), de a `clippedEventRatio` **1/N**.
- [ ] **NaN-mentesség + tartomány property.**

> **Küszöb-konvenció:** minden numerikus küszöbhöz a mátrix **három** cellát
> ad — szigorúan **alatta**, pontosan **rajta**, szigorúan **fölötte** —, és a
> cellák értékei `python3 -c`-vel kiszámoltak, nem idealizált rácsból becsültek
> ([`docs/LESSONS.md`](../LESSONS.md) L13).

### 6.1 Mérce-mátrix — melyik hibás implementációt fogja pirosra

| Hibás implementáció | Melyik cella vált PIROSRA |
|---|---|
| A számítás a `canonicalSamples`-ből dolgozik | a normalizáció-immunitás cella (flag ON) |
| Abszolút dBFS-küszöb a normalizálás helyett | a gain-invariancia ×2/×0.5 cella |
| Az outlier-tartomány exkluzív | a **pontosan 2.00×MAD** nem-outlier cella |
| A clipping-kapu exkluzív | a **pontosan 0.05** `degraded` cella |
| A noise-floor kapu csak egy szintű | a −25.0 dBFS `unavailable` cella |
| Az accent session-mediánhoz mér | az accent-lokalitás „különböző" cella |
| A down/up arány `lower is better` | a `descriptive` irányultság cella |
| Target nélkül is publikál accent-pontosságot | az accent `notApplicable` cella |
| A clippelt esemény beleszámít a CV-be | a clipped-kizárás |Δ| ≤ 1e−12 cella |
| **Valódi-sértés próba (§10):** a bemenet ideiglenes átállítása `canonicalSamples`-re → a normalizáció-immunitás cella **PIROS** → visszaállítás |

## 7. Kötelező ellenőrzések

```bash
tools/round-gate.sh test/features/audio_analysis test/property test/app
```

Külön processzek, nincs `&&`/pipe/`tail`.

## 8. Implementációs sorrend

1. `docs/rag/chunks/022-…` (attack/RMS ablak, MAD-outlier, kapuk).
2. RED: gain-invariancia, normalizáció-immunitás, küszöb-hármasok,
   accent-lokalitás (a fixture-konstrukciók `python3 -c`-vel levezetve).
3. `dynamics_gate.dart` (kapuk, R07-riportból).
4. `dynamics_metrics.dart` (a hét metrika).
5. `accent_analysis.dart` (mozgó medián).
6. Katalógus + ARB; property; gate.

## 9. Kockázatok

- **Az auto-gain bizonytalansága** mérhetetlen ezen a boxon — az eval-mátrix
  PENDING sort kap („azonos játék, eltérő mikrofon-távolság"), és a metrika
  doc-commentje kimondja, hogy a sessionök **közötti** összevetés az R25
  provenance-kapujához kötött.
- **A MAD-alapú outlier érzékeny a kis mintaszámra** — az R14 `MetricGate`
  minimuma itt is érvényes; kevés eseménynél `unavailable`.
- **A backing-track kapu proxy** — a chunk kimondja, hogy ez **nem**
  forrásfelismerés (SDD §11.5), és az érték ideiglenes.

**STOP:** a normalizált puffer használata, abszolút hangerő-ítélet vagy
target nélküli értékelő állítás helyett `stopped` + brief-revízió.

## 10. Implementation handoff — az implementer tölti ki

_(üres)_

## 11. Review — a független reviewer tölti ki

Tervezett review: `docs/reviews/e06-r16-dynamics-and-stroke-balance-review.md`.
Merge csak exact-SHA zöld CI, §4-en belüli diff és nulla OPEN BLOCKER/MAJOR után.
