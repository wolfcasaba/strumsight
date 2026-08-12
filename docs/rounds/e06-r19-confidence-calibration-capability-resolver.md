# E06-R19 — Confidence calibration és capability resolver

- **Státusz:** PLANNING (pre-flight revízió: 2026-08-12, main @ `cc8faca1`; ADR [0237](../adr/0237-analysis-confidence-combiner-and-capability-resolver.md))
- **SDD-kör:** [`docs/sdd/07-epic-06-audio-analysis-2.md`](../sdd/07-epic-06-audio-analysis-2.md) Kör 19; §7.5, §19.1–19.6
- **Branch:** `codex/e06-r19-confidence-calibration-capability-resolver`
- **Előfeltétel:** **E06-R07, E06-R14, E06-R16, E06-R17 merge**
- **Brief szerzője:** Claude (batch) · **Implementáció:** Codex (Terra)

```ai-router
schema_version = 1
risk = "high"
allowed_paths = [
  "lib/features/audio_analysis/engine/confidence/capability_resolver.dart",
  "lib/features/audio_analysis/engine/confidence/confidence_combiner.dart",
  "lib/features/audio_analysis/engine/confidence/calibration_table.dart",
  "lib/features/audio_analysis/engine/confidence/capability_thresholds.dart",
  "lib/features/audio_analysis/domain/analysis_capability.dart",
  "lib/features/audio_analysis/public.dart",
  "lib/l10n/app_en.arb",
  "lib/l10n/app_hu.arb",
  "test/features/audio_analysis/domain/capability_report_test.dart",
  "test/features/audio_analysis/engine/capability_resolver_test.dart",
  "test/features/audio_analysis/engine/confidence_combiner_test.dart",
  "test/property/analysis_confidence_property_test.dart",
  "docs/rounds/e06-r19-confidence-calibration-capability-resolver.md",
]
gate_tests = [
  "test/features/audio_analysis",
  "test/property",
  "test/app",
]
native_gate = false
```

> ⚠ **Pre-flight ELVÉGEZVE (2026-08-12, lásd §0.0):** a tényleges
> capability-kapukat (`MetricGate`, `DynamicsGate`, `PitchCapabilityGate`)
> számba vettük — `DynamicsGate`/`PitchCapabilityGate` mozgatása a fájllista
> tágítása nélkül NEM megy, ezért a §0.0 **nem** `stopped`-ot választott,
> hanem szűkítette a scope-ot: ez a kör az ÚJ `engine/confidence/**` modult
> szállítja, a meglévő kapuk átvezetése egy jövőbeli körre marad. Az R02
> `analysis_capability.dart` bővítése kizárólag **additív**.
> PREPARED→PLANNING megtörtént, brief commitolva.

## 0. Kör-jelzés és STOP-protokoll

```bash
tools/codex-signal.sh progress "<egy sor>" ; tools/codex-signal.sh done "<egy sor>"
tools/codex-signal.sh stopped "<egy sor>" ; tools/codex-signal.sh blocked "<egy sor>"
```

Lezáró jelzés nélkül a kör bukott. Listán kívüli fájl → `stopped`.

## 0.0 Tervezési baseline és pre-flight revízió

**PLANNING — pre-flight revízió (2026-08-12, `cc8faca1`, 192 commit
renonszancia a brief `a6e6f3d` mérési baseline-jéhez képest).** Két mért
lelet, mindkettő itt feloldva (ADR 0237 rögzíti részletesen):

1. **Stale ADR-hivatkozások.** A brief eredeti szövege „ADR 0201"
   (confidence/abstention), „ADR 0204" (capability-publikáció) és „ADR
   0203" (metric-version) számokra hivatkozott. Ezek a számok az R01
   pre-flight (2026-08-11) óta **elavultak**: a teljes hatos ADR-blokk
   0200–0205-ről 0215–0220-ra tolódott, amit [ADR 0216](../adr/0216-analysis-confidence-calibration-and-abstention.md)
   és [ADR 0219](../adr/0219-analysis-capability-aware-publication.md)
   saját fejléce is dokumentál („Sorszám-jegyzet"). A helyes megfeleltetés
   — **0201→0216, 0204→0219, 0203→0218** — a brief teljes szövegében
   javítva (lásd §5 pont 3 és 6 lent).
2. **`§8` lépéssor 6. pontja („A metrika-modulok kapu-hívásainak
   átvezetése") KIVÉVE a kör scope-jából.** Mérve: a három szórt kapu
   közül `DynamicsGate` (`engine/metrics/dynamics_gate.dart`, R16) és
   `PitchCapabilityGate` (`engine/pitch/pitch_capability_gate.dart`, R17)
   **ma is önállóan konstruálnak** `CapabilityStatus`/`CapabilityReport`-ot
   (nem csak bool küszöböt, mint a `MetricGate`) — de egyik fájl sincs a
   kör `allowed_paths`-án: a `dynamics_gate.dart` a §4 explicit tilos
   zónájában él, a `pitch_capability_gate.dart` pedig nincs se az
   engedélyezett listán, se a tilos zóna felsorolásában. A retrofit tehát
   vagy a tilos zóna feloldását, vagy a fájllista bővítését igényelné —
   a §9 kockázat pontosan ezt a helyzetet jósolta meg, és a feloldást a
   §0.0-ra bízta. **Döntés: a lépés kimarad**, mert egyetlen acceptance
   criterion sem igényli (mindegyik a resolvert közvetlen, szintetikus
   bemenettel hívja), és a retrofit egy jövőbeli bekötő kör feladata
   marad (HANDOFF §3 follow-up-ként rögzítve zárás után). A §6 „Egyetlen
   döntési pont" kritériumát ennek megfelelően **az ÚJ `engine/confidence/**`
   modulra szűkítve** kell mérni (lásd az adott bullet módosított
   szövegét lent) — nem repó-szintű, retroaktív állításként a már
   merge-elt R16/R17 kódra.

Minden más brief-állítás (a domainmodell 14/4/13 értéke, az ARB-ek
tisztán additív állapota, a `confidenceThreshold` Live-only hatóköre) a
kódban változatlanul igaznak mérve — a fenti két ponton kívül nincs további
revízió az ELSŐ pre-flight-ban.

**Harmadik lelet — az implementer ELSŐ dispatchja találta (2026-08-12,
`stopped`, ld. lent §10):** a §6 „Nincs átlag" acceptance criterion a
`[0.9, 0.9, 0.9, 0.9, 0.1]` vektor geometriai átlagát „0.5581…"-ként
rögzítette. Terra lefuttatta a brief saját szabálya szerinti
`python3 -c` ellenőrzést, és `0.5799546134795288`-at kapott — a „0.5581…"
egy számolási hiba volt az eredeti (2026-08-07) brief-írásban, nem egy
alternatív, dokumentálatlan képlet eredménye (ellenőrizve: sem a súlyozatlan,
sem több kézenfekvő súlyozott/harmonikus/RMS-változat nem adja ki
„0.5581…"-et erre a vektorra). **Feloldás:** a §6 kipinnelt értéke javítva
`0.5799546134795288`-ra (`0.57995…`); a formula (geometriai átlag,
egyenlő súlyokkal) és a „nem egyenlő 0.74" állítás változatlan — ez tiszta
aritmetikai javítás, nem architekturális döntés, ezért nem igényel ADR
0237-módosítást. A kör Terra ugyanazon workpéldányában, a javított
brieffel folytatható.

## 1. Cél

**Egyetlen** helyen eldönteni, hogy melyik metrika publikálható, milyen
státusszal és milyen confidence-szel — verziózott küszöbökkel, indokolt
kombinációval és Lab-diagnosztikai lebontással.

## 2. Jelenlegi állapot (mért, `a6e6f3d`)

- A mai V1-ben **nincs** confidence a metrikákon: az `AnalyzeResult` egyetlen
  confidence-e a `TimelineStrum.confidence`, ami a CRNN softmaxa vagy a
  heurisztika értéke — **kalibrálatlan**, és semmilyen publikációs kaput nem
  vezérel.
- A `settings` ad egy felhasználói `confidenceThreshold` beállítást
  (`ss.settings.confidence_threshold`), amit a **Live** felület használ — az
  Analyze nem.
- Az Epic 6 eddigi körei **szórtan** vezettek be kapukat: R14 `MetricGate`
  (minimum eseményszám), R16 `DynamicsGate` (clipping/zaj), R17
  `PitchCapabilityGate` (voiced arány/polifónia), R12 (rövid klip),
  R15 (rács-confidence korlát).
- Az R07 riportja adja a jelminőséget, az R13 az illesztés minőségét.

## 3. Scope

**Benne:** `CapabilityResolver` (**egy** belépő: bemenete a jelminőség,
eseményszám, modell-confidence, target elérhetőség, illesztési minőség, mód és
modell-elérhetőség; kimenete `CapabilityReport` **minden** capabilityre);
`ConfidenceCombiner` (indokolt kombináció, **nem** egyszerű átlag);
`CalibrationTable` (verziózott, monoton leképezés a nyers score → kalibrált
confidence irányba); `CapabilityThresholds` (verziózott küszöbök egy helyen);
Lab-diagnosztikai breakdown; ARB az `unavailable` okok lokalizálásához.

**Kívül — TILOS:** új metrika, a meglévő metrikák **számításának**
módosítása, insight (R20), UI, kalibrációs **dataset** (R29).

## 4. Engedélyezett fájlok

| Útvonal | Állapot | Miért |
|---|---|---|
| `.../engine/confidence/capability_resolver.dart` | ÚJ | egyetlen döntési pont |
| `.../engine/confidence/confidence_combiner.dart` | ÚJ | kombinációs policy |
| `.../engine/confidence/calibration_table.dart` | ÚJ | verziózott leképezés |
| `.../engine/confidence/capability_thresholds.dart` | ÚJ | küszöbök egy helyen |
| `.../domain/analysis_capability.dart` | meglévő | **additív** ok-értékek |
| `.../public.dart` | meglévő | export |
| `lib/l10n/*.arb` | meglévő | **additív** `unavailable` szövegek |
| `test/**` | ÚJ | mátrix + property |

**Tilos zóna:** `.../engine/metrics/**` (az R14–R18 területe — a kapuk
**hívása** átalakítható, a metrikaszámítás **nem**), `lib/features/analyze/**`,
`lib/features/settings/**`. Listán kívül → `stopped`.

## 5. Kötött architekturális döntések

1. **Egyetlen resolver, egyetlen igazság:** minden capability státusza és
   confidence-e a `CapabilityResolver`-ből jön. **NEM elfogadható:** a
   metrika-modulokban maradó, párhuzamos kapu-döntés — a metrika legfeljebb
   **bemenetet** ad a resolvernek (eseményszám, nyers score).
2. **Nincs indokolatlan átlag** (SDD §19.4): a dokumentum overall
   confidence-e **nem** a metrikák számtani átlaga; a szabály:
   `min` a kritikus capabilityken, súlyozott aggregátum a többin, és
   **kritikus capability `unavailable` → overall legfeljebb `degraded`**.
   **NEM elfogadható:** `metrics.map((m) => m.confidence).average`.
3. **A nyers score nem probability** (ADR 0216, javított szám — lásd
   §0.0): a resolver a
   `CalibrationTable`-ön keresztül képez le, a tábla **verziózott** és a
   provenance-be kerül. A V1 táblája **identitás** (nincs valós kalibráció),
   de **explicit** `calibrationVersion = "identity.v1"` jelöléssel.
   **NEM elfogadható:** a nyers softmax `calibrated` jelöléssel.
4. **Az abstention első osztályú** (SDD §19.6): a resolver adhat
   `unavailable`-t **magas** input-minőség mellett is, ha a hipotézisek
   ellentmondanak (`confidenceTooLow`).
5. **Minden `unavailable` ok lokalizálható**: mind a 13 (R02)
   `CapabilityUnavailableReason` értékhez van ARB-kulcs **mindkét** nyelven.
   **NEM elfogadható:** „ismeretlen ok" fallback szöveg.
6. **A küszöbök verziózottak és egy helyen élnek**; a `thresholdsVersion` a
   provenance-be kerül, és a változtatása **metric version** emelést von maga
   után (ADR 0218, javított szám — lásd §0.0).
7. **Determinizmus:** azonos bemenetre azonos kimenet; a resolver
   állapotmentes.

### 5.1 Nyitott döntések — előre rögzített feloldással

```yaml
open_decisions:
  - id: OD-01
    question: Melyek a "kritikus" capabilityk?
    blocking: true
    resolution_policy: use_default
    default: >-
      signalQuality és onsetTimeline — enélkül a dokumentum érdemi része
      nem áll meg. A lista néven nevezett konstans, a doc-comment indokolja.
  - id: OD-02
    question: Hogyan kombináljon a ConfidenceCombiner?
    blocking: true
    resolution_policy: use_default
    default: >-
      geometriai átlag a FÜGGETLEN tényezőkön (signal quality, model
      confidence, alignment quality), majd `min` a KEMÉNY kapukkal
      (event count elég? modell elérhető?). A geometriai átlag azért, mert
      egyetlen gyenge tényező érdemben lehúzza az eredményt — a számtani
      átlag elrejtené. A képlet a doc-commentben.
  - id: OD-03
    question: Hol a degraded/available határ?
    blocking: true
    resolution_policy: use_default
    default: >-
      confidence >= 0.7 → available; 0.4 <= confidence < 0.7 → degraded;
      < 0.4 → unavailable (confidenceTooLow). Néven nevezett konstansok,
      ideiglenesek az R29-ig.
```

## 6. Acceptance criteria

- [ ] **Capability-mátrix — kilenc bemeneti eset:** magas minőségű + target;
      clippelt bemenet; zajos bemenet; túl rövid klip; modell hiányzik;
      gyenge illesztés; részleges capability (pitch OK, dynamics nem);
      **határon** lévő confidence; ellentmondó hipotézisek. Mindegyikre
      **minden** capability státusza + oka ellenőrzött (nem csak egyé).
- [ ] **Available/degraded/unavailable küszöb hármasok — hat cella:**
      confidence **0.3999 / 0.4 / 0.4001** (a **0.4** már `degraded`,
      inkluzív) és **0.6999 / 0.7 / 0.7001** (a **0.7** már `available`).
      A hat érték `python3 -c`-vel generált, és a teszt közvetlenül a
      resolvernek adja őket.
- [ ] **Nincs átlag:** egy eset, ahol öt metrika confidence-e
      `[0.9, 0.9, 0.9, 0.9, 0.1]` — a számtani átlag **0.74**, a szerződött
      overall viszont ettől **eltér** (a geometriai átlag
      `python3 -c 'import math; v=[0.9,0.9,0.9,0.9,0.1]; print(math.prod(v) ** (1/len(v)))'`-vel
      számolva **0.5799546134795288…**, azaz **0.57995…**), és a teszt a
      **szerződöttre** mér, valamint **explicit** kimondja, hogy a 0.74
      **PIROS**. (Javított érték — az eredeti „0.5581…" számolási hiba volt,
      lásd §0.0 3. pont.)
- [ ] **Kritikus capability hatása:** `signalQuality` `unavailable` esetén az
      overall completion **legfeljebb** `degraded`, akkor is, ha minden más
      metrika 1.0 confidence-ű.
- [ ] **Kalibráció-jelölés:** minden publikált confidence mellett szerepel a
      `calibrationVersion`, és a V1-ben ez **`identity.v1`**; teszt méri, hogy
      **egyetlen** confidence sincs `calibrated` forrásjelöléssel valódi
      tábla nélkül.
- [ ] **Monotonitás property:** a `CalibrationTable` leképezése **monoton
      nemcsökkenő** — véletlen bemenetekre `x1 ≤ x2 ⇒ f(x1) ≤ f(x2)`, és
      `f(x) ∈ [0,1]`.
- [ ] **Ok-lokalizáció teljesség:** teszt iterál a
      `CapabilityUnavailableReason.values` **összes** értékén, és mindegyikre
      **mindkét** ARB-ben talál kulcsot (a hiányzó → PIROS).
- [ ] **Egyetlen döntési pont (§0.0 szerint szűkítve az ÚJ modulra):** teszt
      (statikus, forrásolvasó a `test/tooling` mintájára **vagy**
      hívásszámlálós seam) méri, hogy az `engine/confidence/**` fájlok között
      **pontosan egy hely** (`capability_resolver.dart`) állít be
      `CapabilityStatus`-t — a `confidence_combiner.dart`/`calibration_table.dart`/
      `capability_thresholds.dart` csak bemenetet/leképezést ad, státuszt nem.
      **Nem** követeli meg, hogy a már merge-elt `DynamicsGate`/
      `PitchCapabilityGate` (R16/R17, `allowed_paths`-on kívül) is a
      resolveren keresztül döntsön — az a retrofit egy jövőbeli bekötő kör
      scope-ja (§0.0, ADR 0237).
- [ ] **Determinizmus:** ugyanaz a bemenet 100 futásra bitazonos kimenet.

> **Küszöb-konvenció:** minden numerikus küszöbhöz a mátrix **három** cellát
> ad — szigorúan **alatta**, pontosan **rajta**, szigorúan **fölötte** —, és a
> cellák értékei `python3 -c`-vel kiszámoltak, nem idealizált rácsból becsültek
> ([`docs/LESSONS.md`](../LESSONS.md) L13).

### 6.1 Mérce-mátrix — melyik hibás implementációt fogja pirosra

| Hibás implementáció | Melyik cella vált PIROSRA |
|---|---|
| Számtani átlag az overall confidence-hez | a „nincs átlag" cella (0.74 explicit PIROS) |
| A `degraded` küszöb exkluzív | a **pontosan 0.4** `degraded` cella |
| Az `available` küszöb exkluzív | a **pontosan 0.7** `available` cella |
| A kritikus capability nem húzza le az overallt | a `signalQuality` unavailable cella |
| A nyers score `calibrated` jelöléssel megy ki | a `calibrationVersion == identity.v1` cella |
| A kalibrációs tábla nem monoton | a monotonitás property |
| Hiányzik egy `unavailable` ok ARB-kulcsa | az ok-lokalizáció teljesség cella |
| A metrika-modul maga állít státuszt | az „egyetlen döntési pont" cella |
| A resolver állapotot tart (cache) | a 100 futásos determinizmus cella |
| **Valódi-sértés próba (§10):** egy `CapabilityUnavailableReason` ARB-kulcs ideiglenes törlése → a teljesség-cella **PIROS** → visszaállítás |

## 7. Kötelező ellenőrzések

```bash
tools/round-gate.sh test/features/audio_analysis test/property test/app
```

Külön processzek, nincs `&&`/pipe/`tail`.

## 8. Implementációs sorrend

1. `capability_thresholds.dart` (a szórt küszöbök összegyűjtése, verzióval).
2. RED: capability-mátrix, küszöb-hármasok, „nincs átlag" cella.
3. `calibration_table.dart` (identity.v1, monoton szerződés).
4. `confidence_combiner.dart` (geometriai átlag + kemény kapuk).
5. `capability_resolver.dart` (egyetlen belépő).
6. ~~A metrika-modulok kapu-hívásainak átvezetése~~ — **KIVÉVE §0.0 szerint**
   (a `DynamicsGate`/`PitchCapabilityGate` retrofitja `allowed_paths`-on
   kívül esik; egy jövőbeli bekötő kör feladata).
7. ARB-teljesség; property; gate.

## 9. Kockázatok

- ~~A kapuk átvezetése érintheti az R14–R18 fájljait~~ — **feloldva a §0.0
  pre-flight revízióban (ADR 0237):** a lépés kimarad ebből a körből,
  nincs `stopped`. A `DynamicsGate`/`PitchCapabilityGate` továbbra is
  önállóan dönt `CapabilityStatus`-ról — mért, dokumentált, nyitva hagyott
  gap egy jövőbeli bekötő kör számára (HANDOFF §3).
- **A geometriai átlag 0-ra érzékeny** — a képlet `max(ε, x)` alsó vágást
  használ, `ε = 1e−6`, dokumentáltan.
- **A küszöbök kalibrálatlanok** — az eval-mátrix PENDING sort kap, és az
  R29 kalibrálja őket.

**STOP:** az ÚJ `engine/confidence/**` modulon belüli párhuzamos
kapu-döntés, számtani átlag vagy a nyers score `calibrated` jelölése
helyett `stopped` + brief-revízió. (A `DynamicsGate`/`PitchCapabilityGate`
meglévő, önálló döntése a §0.0 szerint tudott és elfogadott állapot —
**nem** STOP-ok.)

## 10. Implementation handoff — az implementer tölti ki

### Stopped — 2026-08-12

- **Módosított production/test fájlok:** nincs.
- **Blokkoló:** a §6 „Nincs átlag” acceptance criterion a
  `[0.9, 0.9, 0.9, 0.9, 0.1]` vektorra geometriai átlagként `0.5581…`-et
  rögzít. A kötelezően előírt ellenőrzés tényleges kimenete:
  `python3 -c 'import math; values=[0.9,0.9,0.9,0.9,0.1]; print(math.prod(values) ** (1 / len(values))); print(sum(values) / len(values))'`
  → `0.5799546134795288` és `0.74`. A `0.5581…` ezért nem lehet ennek a
  vektornak a geometriai átlaga.
- **Nem futtatott ellenőrzések:** `tools/round-gate.sh test/features/audio_analysis test/property test/app` nem futott, mert a hibás, kötött acceptance criterion mellett nem írható olyan implementáció/test, amely egyszerre teljesíti a brief OD-02 geometriai-átlag szerződését és a §6 kipinnelt értékét.
- **Szükséges folytatás:** Claude/brief-szerző javítsa a §6 és szükség esetén
  a §6.1 mérce-cella elvárt értékét `0.5799546134795288`-ra, vagy dokumentált
  ADR/brief-revízióban határozzon meg más, nem geometriai aggregációt. Ezután
  a kör új sessionben indítható újra.

## 11. Review — a független reviewer tölti ki

Tervezett review: `docs/reviews/e06-r19-confidence-calibration-capability-resolver-review.md`.
Merge csak exact-SHA zöld CI, §4-en belüli diff és nulla OPEN BLOCKER/MAJOR után.
