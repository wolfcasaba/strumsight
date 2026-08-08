# ADR 0190 — Vision observation fusion and evidence engine

- **Státusz:** Elfogadva (E05-R22 pre-flight, 2026-08-08)
- **Kör:** E05-R22 — Vision observation fusion és evidence engine
- **Implementer motor:** Codex (Terra, `gpt-5.6-terra`, `~/.codex-terra`) — az
  ADR-t az orchesztrátor (Claude Sonnet 5) írta a pre-flightban (ADR 0055,
  pipeline-prompt §2).
- **Epic:** [Chapter 6 — Epic 5: Computer Vision](../sdd/06-epic-05-computer-vision.md) §9.5–9.6, §23.1–23.2
- **Kontext-ADR-ek:** [0179](0179-vision-capability-aware-feedback.md)
  (capability-aware feedback: `requiredCapability`/`confidence`/`observability`
  kötelező mezők, *no feedback is better than false feedback*),
  [0188](0188-vision-safety-claim-guard.md) (claim-kód alapú kimenet, amit ez a
  réteg később hordoz), [0189](0189-vision-audio-sync-contract.md) (a `sync`
  komponens forrása)

> **Számozási megjegyzés:** a kör briefje (2026-08-05, batch-írás) egy jövőbeli
> „0162" ADR-számra hivatkozott, de ez a szám **sosem lett fájl** a
> `docs/adr/`-ban, és a `docs/execution/pipeline-queue.tsv` E05-R22 sora is
> `nincs`-et tart ADR-oszlopban — tehát nem egy elavult foglalás (mint a
> 0170→0189 minta E05-R21-nél), hanem egy sosem realizált előzetes terv. A
> pipeline pre-flight-tábla ennek megfelelően `nincs`-et adott át, a
> `tools/round-slots.py reserve-adr --round E05-R22` hívás **0190**-et adott.

## Kontextus

A pre-flight (pipeline-prompt §1, két kötelező mérési szabály) a kódot mérte a
brief §5 komponens-alapú confidence-modellje mögött, mert a brief négy
komponenst (`model`/`quality`/`geometry`/`sync`) nevez meg, de egyiket sem köti
konkrét, meglévő típushoz:

1. **„model" komponens — `MetricObservation`** (`domain/metrics/metric_observation.dart`,
   R18). Két állapotú `MetricObservability {observable, notObservable}`,
   `value: double?`, `confidence: double` `[0, 1]`-re validálva a
   konstruktorban (érvénytelen bemenet ⇒ `notObservable`, sosem NaN/Infinity
   szivárgás). A három metrika-motor (`fretting_metric_engine.dart`,
   `picking_metric_engine.dart`, `posture_metric_engine.dart`) **mindegyike
   saját maga számolja** ezt a confidence-et (pl. posture:
   `1 - min(1, |mean drift|)`, fretting/picking: `mean(landmark confidence)`
   vagy hasonló, motoronként dokumentált formula) — ez a fúzió „model"
   bemenete, változtatás nélkül fogyasztva.
2. **„geometry" komponens — `GeometryConfidence`** (`domain/geometry/geometry_confidence.dart`,
   R16). `confidence: double [0,1]` + `drift: double >= 0`, konstruktor-validált
   (`throw ArgumentError`, release-load-bearing — R16 fix-round F2 precedens).
   `isTracked` a `trackingConfidenceThreshold` (0.5) fölött.
3. **„quality" komponens — `VisionFrameQuality`/`VisionQualitySummary`**
   (`domain/quality/`, R09). **Mérve: egyik metrika-motor sem importálja vagy
   fogyasztja ma ezt a típust** (`grep -rn "VisionFrameQuality\|VisionQualitySummary"
   lib/features/vision/domain/metrics/` nulla találat a motorfájlokban) — a
   frame-quality pipeline ma kizárólag a setup-képernyő cue-jait táplálja. Az
   osztály doc-commentje explicit szűkíti a hatókört: „carries no landmark,
   inference, or technical-playing claim." A fúzió ennek a típusnak az
   **első technikai-confidence fogyasztója** — ez architekturálisan rendben
   van (a quality egy ELŐFELTÉTEL bármilyen downstream claimhez, technikai
   vagy sem), de a `VisionQualitySummary.fromFrames` saját, cue-priorizáló
   ablakozását (egyetlen aktív cue) **nem** szabad újrafelhasználni számként —
   az bemutatási logika, nem tiszta confidence-jel.
4. **„sync" komponens — `SyncQuality`, NEM `PickingSyncQuality`.** Két,
   szándékosan **különálló** enum azonos névkészlettel
   (`poor/acceptable/good/excellent`): `SyncQuality`
   (`domain/sync/sync_quality.dart`, R21, a valódi `ClockMapping`-ből
   számolható) és `PickingSyncQuality` (`domain/metrics/picking_metrics.dart:75`,
   R19, ma **injektált**, „Grep over the repository … confirms zero hits
   outside this file" — a valódi forrás bekötése explicit **jövőbeli** kör
   dolga, a picking-motor doc-commentje szerint is). A fúzió `sync`
   komponense a **R21 `SyncQuality`**-t olvassa; a `PickingSyncQuality`
   motor-belüli hard gate (event-level metrika `notObservable`, ha a sync
   `poor`/`acceptable`) **változatlan marad**, és a kettő **nem vonható
   össze** ebben a körben — az egyik a motor saját, kemény előfeltétele, a
   másik a fúziós réteg lágy komponense.
5. **`{Fretting,Picking,Posture}MetricDefinition.window` és
   `.minimumVisibility` ma HASZNÁLATON KÍVÜLI mezők.** Mindhárom katalógus
   konstruktor-validálja őket (`window > Duration.zero`,
   `minimumVisibility ∈ [0,1]`), de egyik motor sem olvassa ki futás közben
   (`grep -n "\.window\b" lib/features/vision/domain/metrics/*.dart` a
   `picking_metric_engine.dart`-beli egyetlen találat egy MÁSIK típus —
   `PickingStrokeCut.window` — mezője, nem ez). Ezek a mezők a katalógus
   írásakor (R18) explicit erre a jövőbeli fogyasztóra lettek fenntartva.
6. **Az „observed / inferred / notObservable / experimental" négyes NEM
   létezik ma sehol a kódban**, és a `VisionEvidence.observability` SDD-vázlat
   (§9.6) is csak a `ObservabilityState observability` mezőtípust nevezi meg,
   tartalom nélkül — a négy érték maga csak a Kör 22 feladatlistában (SDD
   3005. sor) és a §5.2/§7.1 kapacitás-vázlatban (`experimental` mint
   capability-szint, `CapabilityState`/L5) szerepel. **`CapabilityState`
   (SDD §7.2) szintén nincs implementálva** (`grep -rn "CapabilityState"
   lib/features/vision/` nulla találat), és egyik ma élő capability-enum
   (`FrettingCapability {handTracking, guitarRelativeTracking}`,
   `PickingCapability {guitarRelativeTracking}`,
   `PostureCapability {poseTracking}`) sem hordoz kísérleti szintet. Az
   „elérhetetlen cél-státusz" mérési szabály (pipeline-prompt §1/1) tehát itt
   nem egy létező reducert talál elavultnak, hanem egy **soha nem
   implementált** bemenetet — ez brief-revíziót igényel, nem hallgatólagos
   „majd kitalálja az implementer" döntést.
7. **Erőforrás-tulajdonlás (pipeline-prompt §1/2): nem releváns.** A brief
   egyetlen acceptance-cellája sem rendel lease/lock/handle/subscription-t
   egy réteghez; a `.acquire(` hívás (`vision_setup_controller.dart:163`,
   `CameraSessionLease`) a kamera-session életciklusáé, amit ez a tisztán
   domain/application fúziós réteg nem érint.

## Döntés

1. **A négy komponens forrása fixen kötött, ahogy fent mérve:** `model` ⇐
   `MetricObservation.confidence`; `quality` ⇐ `VisionFrameQuality`/
   `VisionQualitySummary` (R09) — az adott evidence-ablakkal **egyező**
   időablakra újraszámolt frame-quality, nem az UI setup-summary
   újrafelhasználva; `geometry` ⇐ `GeometryConfidence.confidence` (R16),
   csak a `guitarRelativeTracking`-et igénylő metrikáknál (a `handTracking`-
   only/`poseTracking`-only metrikáknál a geometry komponens `1.0`, azaz
   semleges — nincs gitárgeometria-igény, tehát nincs mit büntetni); `sync`
   ⇐ `SyncQuality` (R21), **nem** `PickingSyncQuality`.
2. **A kombináció monoton nem-növekvő** (brief §5/2 újra megerősítve): a
   négy numerikus komponensből `min` vagy szorzat (a fúzió választja és
   dokumentálja, a 12 cellás propagáció-mátrix ezt méri) — a kategorikus
   bemenetek (quality/geometry/sync bucket) numerikus leképezése **soha** nem
   growing: egy gyengébb kategorikus bucket sosem eredményezhet magasabb
   numerikus hozzájárulást, mint egy jobb bucket. **NEM elfogadható**
   átlagolás.
3. **A fúziós ablak-hossz metrikánként a meglévő
   `{Fretting,Picking,Posture}MetricDefinition.window` mezőt használja** —
   ez a mező pontosan erre a célra lett fenntartva (R18), és ma nincs más
   fogyasztója; a fúzió NEM vezet be egy második, párhuzamos
   ablak-hossz-fogalmat. A brief §5/1 „minimum frame-szám / minimum látható
   időtartam" és a §5/1 (SDD §23.2) „maximum gap" ÚJ, fúzió-tulajdonú
   küszöbök, **rátéve** erre az ablak-hosszra, nem helyette.
4. **Az evidence-szintű `ObservationState` (`observed`/`inferred`/
   `notObservable`/`experimental`) pontos gyártási szabálya:**
   - **`experimental`** — capability-szintű kapu, minden más tengelyt felülír
     (SDD §7.1 L5 / §5.2 kísérleti capability-koncepció). **Ma egyik élő
     capability-enumnak sincs kísérleti értéke** (mérve, fent) — tehát a
     jelenlegi három katalógusból **elérhetetlen**. A fúzió a `case`-t
     **kimerítően kezeli** (nincs `default`/throw), de a bemeneti oldalon
     **nem szabad** mesterséges triggert kitalálni egyik meglévő metrikára
     sem — a teszt egy **negatív, kizárásos** cella: a teljes mai katalógus
     egyetlen tiszta ablakra sem termel `experimental`-t. Egy jövőbeli kör,
     amely tényleges kísérleti-szintű metrikát vezet be, köti be az első
     valódi triggert.
   - **`notObservable`** — a frame-szám vagy a látható időtartam a metrika
     minimuma alatt van, VAGY az ablakon belüli szakadás meghaladja a
     metrikára dokumentált maximális gap-et (a bemeneti oldal ekkor nem
     hidalható át felelősen).
   - **`inferred`** — a minimum frame/időtartam küszöb teljesül, ÉS az
     ablakon belül van legalább egy, a max-gap-en BELÜLI szakadás, amit a
     aggregáció áthidalt/interpolált — a confidence emiatt **szigorúan**
     alacsonyabb, mint az azonos ablak szakadás nélküli esete lenne (soha
     nem változatlan — ez a §6 „Gap/occlusion teszt" cellája).
   - **`observed`** — a minimum küszöb teljesül ÉS nincs belső szakadás a
     ablakban (folytonos bemenet).
5. **A provenance kötelező és elégséges az újraszámoláshoz** (brief §5/3,
   megerősítve): metrika-azonosító, ablak, model-verzió (ha a metrikának van
   ilyen bemenete), geometry-forrás (`tracked`/`manual`, R16-szemantika),
   sync-bucket, thresholds-verzió.
6. **Az evidence ID determinisztikus hash** az ablak-kulcsból + metrikából
   (brief §5/5, megerősítve) — nem `DateTime.now()`, nem véletlenszám.
7. **Korlátos memória:** az ablakon kívüli nyers observation eldobódik (brief
   §5/6, megerősítve).

**NEM elfogadható:** a négy komponens átlagolása; a `quality` komponensnek a
`VisionQualitySummary` cue-priorizáló API-ján (egyetlen aktív cue) keresztüli
származtatása; a `sync` komponens összemosása a motor-belüli
`PickingSyncQuality` kapuval; egy második, `MetricDefinition.window`-tól
független ablak-hossz bevezetése; `experimental` mesterséges triggerelése egy
ma nem-kísérleti metrikán.

## Következmények

- A `VisionFrameQuality`/`VisionQualitySummary` (R09) első technikai-confidence
  fogyasztója ez a kör — a típus doc-commentjét egy jövőbeli kör pontosíthatja
  („setup-only" → „setup és evidence-fúzió"), de ez a kör nem módosítja a
  fájlt (nincs az `allowed_paths`-on).
- A `SyncQuality` (R21) → `PickingSyncQuality` (R19) valódi bekötése
  **továbbra is nyitott, jövőbeli kör dolga** — ez az ADR explicit
  dokumentálja, hogy a két típus fúzió utáni egyesítése tudatos halasztás,
  nem felejtés.
- Az `experimental` állapot típusszinten létezik és kimerítően kezelt, de
  gyártási triggere nincs — egy jövőbeli, kísérleti-szintű metrikát bevezető
  kör (SDD §4.3, §7.1 L5) adja az első valódi bemenetet; eddig a negatív
  kizárásos teszt védi a regressziót.
- A `{Fretting,Picking,Posture}MetricDefinition.window`/`.minimumVisibility`
  mezők ezzel a körrel kapják meg az első valódi fogyasztójukat — a jövőbeli
  metrika-katalógus-módosító körök tudják, hogy ezek élő szerződések, nem
  holt dokumentáció.

## Elutasított alternatívák

- **A `quality` komponenst a `VisionQualitySummary.setupCue`/`overall`
  mezőjéből származtatni közvetlenül.** Elvetve: a típus saját doc-commentje
  szerint „setup observability only", és a `fromFrames` cue-elsőbbségi logika
  (egyetlen aktív cue) bemutatási szempontból optimalizált, nem tiszta
  confidence-jel; a fúzió a nyers `VisionFrameQuality` mezőket olvassa a
  SAJÁT ablakára, nem az UI setup-summary paralel ablakát.
- **`SyncQuality` és `PickingSyncQuality` egyesítése ebben a körben.**
  Elvetve: mindkettő módosítása vagy az egyik a másikra cserélése
  `picking_metric_engine.dart`/`picking_metrics.dart` érintését igényelné,
  ami kívül esik az `allowed_paths`-on, és összemosná a motor kemény
  előfeltételét a fúzió lágy komponensével.
- **Egy második, önálló per-metrika ablak-hossz bevezetése a fúziós
  fájlokban.** Elvetve: a `MetricDefinition.window` család pontosan erre lett
  fenntartva (R18), és egy párhuzamos szám két, idővel szétcsúszó „ablak"
  fogalmat hozna létre ugyanarra a metrikára.
- **`experimental` kihagyása az enumból, amíg nincs valódi trigger.** Elvetve:
  az SDD Kör 22 feladatlistája és a §5.2/§7.1 capability-vázlat explicit
  megnevezi; a típus hiánya egy jövőbeli kör számára áttervezést (migrációt)
  igényelne. Az enum-érték felvétele exhaustive-kezeléssel és negatív
  kizárásos teszttel olcsó ma; a hallgatólagos kihagyás lenne a meglepő
  regresszió egy jövőbeli olvasónak.
- **`experimental` triggerelése egy ma nem-kísérleti metrikán (pl. mesterséges
  capability-flag hozzáadása egy meglévő metrikához csak teszt-lefedettségért).**
  Elvetve: fabrikált termékviselkedés valódi tervezési alap nélkül — pont az
  a fajta spekulatív kód, amit a repó konvenciói (nincs hipotetikus jövőre
  tervezés) tiltanak.
