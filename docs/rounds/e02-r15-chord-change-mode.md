# E02-R15 — Chord Change mód

- **Státusz:** **PLANNING** (pre-flight 2026-08-01, kód újramérve: `main` @ `02b5499`)
- **SDD-kör:** [`docs/sdd/03-epic-02-practice-engine.md`](../sdd/03-epic-02-practice-engine.md) **„Kör 15"** (+ §7.2, §16.5, §21.4)
- **Branch:** `codex/e02-r15-chord-change-mode`
- **Előfeltétel:** **E02-R14 merge-ölve** (a közös highway/akkord-sáv onnan jön).
- **ADR:** **0081** — `docs/adr/0081-chord-change-measurement.md`, **az
  orchestrátor írja meg a pre-flightban** a §5 tartalmával.
- **Implementer motor:** a pre-flightban a user dönt. *Ajánlás:* **Codex** — a
  „mit állítunk a mérésből" kérdés végig ítéletigényes (hamis állítás tilalma).

> ⚠ **Pre-flight (indítás előtt KÖTELEZŐ)**
> 1. Olvasd újra az R10 akkord-scorer tényleges kimenetét (`ChordOutcome`,
>    stabilitási küszöb, ablak) — a chord-pair statisztika **abból** épül.
> 2. Ellenőrizd, hogy az R04 katalógusban milyen chord-change gyakorlatok
>    vannak (`builtin.*`), és mit fed le a `PracticeDefinition` mezőkészlete.
> 3. ADR-szám ütközés ellenőrzése, majd az ADR 0081 megírása.
> 4. Státusz → PLANNING, dátum/sha frissítés, brief commit a kör-branchre.

## 0. Kör-jelzés — KÖTELEZŐ (AGENTS.md §15.2)

```bash
tools/codex-signal.sh progress "<egy sor>"
tools/codex-signal.sh done    "<egy sor>"
tools/codex-signal.sh stopped "<egy sor>"
tools/codex-signal.sh blocked "<egy sor>"
```

Lezáró jelzés nélküli kör = bukott kör. `gh`-t NE hívj, ne pusholj, PR-t ne nyiss.
**STOP-klauzula:** listán kívüli fájl, vagy ellentmondó előírás → `stopped`.
**A §7 a terved.**

## 0.0 Brief-revízió (pre-flight, 2026-08-01, `02b5499`)

Az E02-R14 merge-e óta (`ce8fbce` → `02b5499`) újramérve. Minden §2/§4/§9
szimbólum a helyén van, **egy** stale leíró állítással:

- **`ChordOutcome` ma ÖT tagú** (`correct`, `wrong`, `insufficientData`,
  `notApplicable`, **`noDetection`**) — a `noDetection` R10 (ADR 0076) óta
  megvan; a §2 „négy értéke" felsorolása ennyiben elavult. **Nem érinti a
  kört:** ez a cél-eseményenkénti `ChordOutcome` (verdict), NEM a §5.4-beli
  váltás-kimenet enum, amit az analyzer a **saját** típusaként vezet be
  (`correct`/`wrongChord`/`noDetection`/`unstable`/`insufficientSignal`).
  Az implementer NE olvassza egybe a kettőt.

Változatlanul mérve és a helyén: `PracticeMode.chordChanges` +
`builtin.gToDChanges.v1`/`builtin.emToCChanges.v1` katalógus-bejegyzések;
`ChordObservation(at, nullable label, confidence)`; stabilitási küszöb 180 ms
(`PracticeObservationConfig.chordStableDuration`); scorer-ablak `−120/+420 ms`;
`legacyPracticeChordLabel` (veszteséges leképezés, ADR 0071 §2);
`chordPair` → 0 találat; `PracticeDefinition` mezőkészlet változatlan;
`practice_session_screen.dart` `_ModeView` switch a `chordChanges`-t ma a
placeholder-ágon kezeli (a becsatolás helye). Az **ADR 0081** megírva.

## 1. Cél

A célzott **akkordváltás-gyakorlás**: két (vagy több) akkord váltogatása, és a
váltás **mérhető** minősítése — akkordpáronkénti statisztikával, amiből a
felhasználó megtudja, **melyik váltás** a leglassabb.

Ez a mód a termék egyik legkonkrétabb ígérete, ezért a kör legfontosabb
szabálya: **csak azt állítjuk, amit tényleg mérünk.** A detektor akkord-*címkét*
lát, nem ujjrakást — tehát „tiszta akkord" helyett „**felismert és stabil
akkord**" a szóhasználat (SDD §15 explicit előírása).

## 2. Jelenlegi állapot (mért tények, `main` @ `ce8fbce`)

- **Katalógus (R04):** a `BuiltinPracticeCatalog` (354 sor) **már tartalmaz**
  akkordváltás-gyakorlatokat (G↔D és Em↔C), `builtin.<slug>.v1` ID-kkel.
  A `PracticeDefinition` mezőkészlete (247 sor) tehát adott — új definíciós
  mezőt csak nagyon indokolt esetben és `stopped` utáni brief-revízióval.
- **Akkord-megfigyelés (R08):** `ChordObservation(at, label, confidence)` —
  a `label` **nullable** (`null` = explicit „nincs akkord"), a címke kanonikus
  (sharp-spelled) és a detektor 24 elemű maj/min szótárára korlátozott
  (`legacyPracticeChordLabel`, R05/ADR 0071 §2 — **veszteséges** leképezés,
  pl. `Em7 → Em`).
- **Akkord-pontozás (R10):** `ChordOutcome` négy értéke
  (`correct`, `wrong`, `insufficientData`, `notApplicable`), a
  `[targetAt − 120 ms, targetAt + 420 ms]` ablak, és a stabilitási küszöb
  (alapérték 180 ms, a `PracticeObservationConfig`-ból, az R11 controller
  egyetlen példányából).
- **A legacy Learn akkord-ága** (`lesson_scorer.dart`, `_chordSlots`,
  `_chordLagSec = 0.37`) **kétmintás** heurisztika, `chordHits/chordTotal`
  aránnyal; **nem** ad páronkénti statisztikát és nem mér váltási időt.
  Ez a kör NEM ehhez mér paritást — új képességet ad.
- **Nincs** chord-pair statisztika sehol a kódban (mérve:
  `grep -rn "chordPair\|chord_pair" lib/` → 0 találat).

## 3. Scope

**Benne:** a chord-change mód domain-oldali mérése (akkordpár-statisztika, a
váltás felismerési késése, stabilitás), a mód-nézet, és a mérésből származó
UI-szövegek — mind ARB-ből.

**Kívül (ebben a körben TILOS):**

- A Result-képernyő páronkénti bontása (Kör 18) — **de** az adatszerkezetet
  ez a kör állítja elő, és a session-nézet már mutathat belőle.
- Coaching-mondat generálás (Kör 18).
- Rhythm-only / Free Practice (Kör 16), Speed Builder (Kör 17).
- A meglévő scorerek, matcher, gateway, controller **viselkedésének** módosítása.
- `lib/features/learn/**`.
- Új ADR, `docs/sdd/**`, `HANDOFF.md`, `.github/**`, DSP.

## 4. Engedélyezett fájlok

| Útvonal | Új? | Miért |
|---|---|---|
| `lib/features/practice/domain/model/chord_pair_stats.dart` | **ÚJ** | páronkénti mérési modell (immutable, value-equal, validált) |
| `lib/features/practice/domain/service/chord_change_analyzer.dart` | **ÚJ** | pure elemző: verdictek + akkord-megfigyelések → páronkénti statisztika |
| `lib/features/practice/presentation/views/chord_change_view.dart` | **ÚJ** | mód-nézet (current/next, váltás-visszajelzés) |
| `lib/features/practice/presentation/widgets/chord_change_breakdown.dart` | **ÚJ** | páronkénti bontás megjelenítése |
| `lib/features/practice/presentation/screens/practice_session_screen.dart` | — | **CSAK** a mód-nézet becsatolása |
| `lib/l10n/app_en.arb` · `lib/l10n/app_hu.arb` | — | új kulcsok mindkét nyelven |
| `test/features/practice/domain/chord_change_analyzer_test.dart` | **ÚJ** | A1–A5 |
| `test/features/practice/domain/chord_pair_stats_test.dart` | **ÚJ** | modell-validáció |
| `test/features/practice/presentation/chord_change_view_test.dart` | **ÚJ** | A6–A8 |
| `test/property/chord_change_property_test.dart` | **ÚJ** | A9 property gate |
| `docs/rounds/e02-r15-chord-change-mode.md` | — | **CSAK a §10** |

**Tilos zóna:** minden más, nevezetesen `lib/features/practice/domain/service/`
meglévő fájljai, `application/**`, `data/**`, `lib/features/learn/**`,
`docs/adr/**`.

**Új fájl a listán kívül = scope-sértés** → `stopped`.

## 5. Kötött döntések (ADR 0081 — NEM tárgyalhatók)

1. **Csak mért állítás.** A modell és a UI szóhasználata: „**felismert és
   stabil akkord**". A `clean chord`, „tiszta fogás", „minden húr szól" típusú
   állítás **tilos** — nincs mögötte mérés (SDD §15).
2. **A váltás definíciója.** Egy akkordpár-váltás a compiled targetben az a
   pont, ahol az elvárt akkord `A`-ról `B`-re vált. A **felismerési késés**
   (`recognizedChangeDelay`) az elvárt váltás pillanatától az **első olyan**
   `ChordObservation`-ig eltelt idő, amelynek címkéje `B` **és** amely eléri a
   stabilitási küszöböt. Ha ilyen nincs az ablakban → a váltás **nem** kap
   késés-értéket (nem nulla, nem „végtelen": **hiányzó**).
3. **Az összesítés medián, nem átlag.** A páronkénti késés reprezentánsa a
   **medián** (az outlier-tűrés miatt), és a medián **csak akkor** számolható,
   ha a párnak legalább **három** mért váltása van; egyébként
   `MetricInsufficientData`.
4. **Öt megkülönböztetett kimenet váltásonként:** `correct` · `wrongChord` ·
   `noDetection` · `unstable` · `insufficientSignal`. Ezek **nem** vonhatók
   össze; a UI mindegyiket másképp mutatja.
5. **Determinizmus.** Az elemző pure: azonos bemenetre azonos kimenet; nincs
   benne óra, random vagy IO. A rendezés (pl. „leglassabb pár") **stabil**:
   holtversenynél az akkordpár kanonikus (címke szerinti lexikografikus)
   sorrendje dönt.
6. **A statisztika bemenete a verdict + a megfigyelés-lista**, nem a nyers
   frame-folyam. A domain nem lát detektort.
7. **A veszteséges címke-leképezés látszik.** Ha a definíció olyan akkordot
   kér, amit a detektor szótára nem tud megkülönböztetni (ADR 0071 §2), azt a
   modell **explicit jelöléssel** adja tovább — a UI ne állítson pontos
   akkord-ítéletet ott, ahol a mérés eleve durvább.
8. **Nincs no-strum vak folt.** Ha a váltás körül **egyetlen** strum sem volt,
   a váltás `insufficientSignal` — nem `wrongChord` és nem `correct`.

## 6. Acceptance criteria

### A1 — Váltás-kimenet mátrix (mind az öt ág)

Egy `A → B` váltás `T` időpontban, stabilitási küszöb 180 ms:

| Megfigyelés-sorozat | Elvárt kimenet |
|---|---|
| `B` címke `T + 100 ms`-tól 200 ms-ig folyamatosan | `correct`, késés **100 ms** |
| `C` címke `T + 100 ms`-tól 200 ms-ig | `wrongChord` |
| csak `label == null` az ablakban | `noDetection` |
| `B` címke, de csak **179 ms**-ig áll fenn | `unstable` |
| üres ablak (nincs megfigyelés) / nincs strum | `insufficientSignal` |

***Pirosra fogja:*** a `null` címke `wrongChord`-ként kezelése, és a
stabilitási küszöb figyelmen kívül hagyása.

### A2 — Stabilitási küszöb: három cella

Ugyanaz a `B` címke, a fennállás hossza:

| Fennállás | Elvárt |
|---|---|
| **179 999 µs** | `unstable` |
| **180 000 µs** | **`correct`** (`>=`) |
| **180 001 µs** | `correct` |

A cellákat `python3 -c`-vel ellenőrizd. Ez az egyetlen hely, ahol a `<` és a
`<=` különbsége mérhető.

### A3 — Késés-mátrix

`recognizedChangeDelay` cellák (`T` a váltás pillanata):

| Az első stabil `B` kezdete | Elvárt késés |
|---|---|
| `T − 50 ms` (a user hamarabb váltott) | **−50 ms** (előjeles, negatív = korai) |
| `T` | **0** |
| `T + 250 ms` | **+250 ms** |
| nincs stabil `B` az ablakban | **hiányzó** (nem 0, nem max) |

***Pirosra fogja:*** az abszolút értékre szorított késés (elrejti a korai
váltást), és a hiányzó érték nullaként kezelése (ami hamis „azonnali váltás"
állítás lenne).

### A4 — Medián és a minimális bizonyíték

| Mért váltások száma a párra | Elvárt |
|---|---|
| 0 | `MetricInsufficientData` |
| 2 | `MetricInsufficientData` (a küszöb 3) |
| **3** (pl. 100 / 300 / 200 ms) | medián **200 ms** |
| 4 (100 / 200 / 300 / 400 ms) | medián: a két középső **átlaga** = 250 ms |

***Pirosra fogja:*** az átlag használata mediánként, és a „egy szerencsés
váltásból is mondunk értéket" hiba.

### A5 — Több akkordos szekvenciák és stabil rendezés

- `G → D → G` (alternating) és `G → D → Em → C` (round-robin): a párok
  **irányítottak** (`G→D` ≠ `D→G`), és mindkettő külön statisztikát kap.
- „Leglassabb pár" lekérdezés: azonos mediánnál a kanonikus sorrend dönt —
  a teszt ugyanazt a bemenetet **kétszer**, eltérő beszúrási sorrenddel adja,
  és ugyanazt a győztest várja.

***Pirosra fogja:*** a `Map` iterációs sorrendjére támaszkodó „leglassabb"
kiválasztás.

### A6 — A nézet nem állít mérésen túlit

- A szövegek **egyike sem** tartalmazza a „tiszta akkord" / „clean chord"
  fordulatot (forrás- és ARB-szintű állítás mindkét nyelvre).
- Az `insufficientSignal` és a `noDetection` **külön**, nem hibaként jelenik
  meg (nem piros „rossz akkord" jelzés).
- A veszteséges leképezéssel érintett akkordnál (§5.7) a UI jelöli a korlátot.

### A7 — 3/4 ütemhatár

3/4-es akkordváltás-gyakorlat: a váltási határok az ütemhatárokra esnek, és a
statisztika ugyanúgy áll elő. Külön cella 4/4-re.

### A8 — a11y, i18n, layout

Címke + akció egy szemantikus node-on; a jelentés nem csak szín; angol/magyar
felépülés; `l10n_parity_test` zöld; 320×568 és 915×412 méreten nincs overflow.

### A9 — Randomizált property gate

`test/property/chord_change_property_test.dart`, `PROPERTY_SEED` (hiány → 42):

1. az elemző **soha nem dob** kivételt tetszőleges megfigyelés-sorozatra;
2. a váltásonkénti kimenetek összege = a váltások száma (egy váltás pontosan
   egy kimenetet kap);
3. a késés-értékek **csak** a `correct` váltásokhoz tartoznak;
4. a bemenet sorrendjének megkeverése nem változtatja meg a kimenetet;
5. ha nincs egyetlen `ChordObservation` sem, **egyetlen** pár sem kap mediánt.

### A10 — Domain-tisztaság és scope

`domain_purity_test.dart` zöld; az architecture gate zöld; a `git diff --stat`
a §4 listáján belül; `lib/features/learn/` **0 sor**.

## 7. Implementációs sorrend (ez a TERVED)

1. Olvasd el: ADR 0081, az R10 akkord-scorer, `practice_observation.dart`,
   `compiled_practice_target.dart` (expected-chord szegmensek),
   `legacy_chord_label.dart` (a veszteséges leképezés dokumentációja).
2. `chord_pair_stats.dart` modell + validáció.
3. `chord_change_analyzer.dart` — először a váltás-kimenet mátrix (A1, A2).
4. Késés + medián (A3, A4).
5. Szekvenciák + stabil rendezés (A5).
6. `chord_change_view.dart` + `chord_change_breakdown.dart` (A6, A7).
7. a11y/i18n/layout (A8), property (A9).
8. Záró gate (§9), majd a §10 kitöltése.

## 8. Kockázatok

- **A hamis állítás a legdrágább hiba ebben a körben.** „Tiszta akkord",
  „minden húr szól", „gyors váltás" — mind olyan, amit a detektor **nem** mér.
  Ha a szöveg és a mérés között rést látsz → `stopped`, ne szépíts.
- **A hiányzó érték nullázása.** A „nincs mért váltás → 0 ms" a legkönnyebb és
  a legkárosabb rövidzár: a felhasználó azt olvasná, hogy tökéletes.
- **Sorrend-függő statisztika.** `Map` iterációra épített rangsor a CI-n
  máshogy viselkedhet, mint lokálisan — az A5 ezt méri.
- **A definíciós modell bővítésének csábítása.** A `PracticeDefinition` R03-as
  szerződés; ha úgy érzed, új mező kell, az `stopped` + brief-revízió.
- **A veszteséges címke-leképezés** (ADR 0071 §2) miatt bizonyos akkordpárok
  eleve nem különböztethetők meg — ezt jelölni kell, nem elhallgatni.

## 9. Záró gate — szó szerint ez az egyetlen hívás

```
tools/round-gate.sh test/features/practice/ test/property/chord_change_property_test.dart test/core/l10n_parity_test.dart
```

Csővezeték nélkül, a teljes kimenetet a §10-be. A teljes suite + property gate +
APK a CI-ban fut (ADR 0053) — `gh`-t NE hívj.

## 10. Implementation handoff — az IMPLEMENTER tölti ki

### Fájlonkénti összefoglaló

| Fájl | Változás |
|---|---|
| `lib/features/practice/domain/model/chord_pair_stats.dart` | **új** — `ChordChangeOutcome` (5 tag), `ChordPair` (immutable, value-equal, kanonikusan rendezhető), `ChordChangeMeasurement`, `ChordChangeDelayMetric` (sealed: `Available` / `InsufficientData`), `ChordPairStats` (immutable, validál: outcomeCount==attempts, delays.length<=correctChanges, csak >=3 mintánál van medián), `ChordChangeAnalysis` (a `slowestPair` kanonikus rendezéssel, NEM `Map` sorrenddel). |
| `lib/features/practice/domain/service/chord_change_analyzer.dart` | **új** — pure `ChordChangeAnalyzer` (nincs clock / random / IO, belsőleg rendezi a segmenteket / observation-öket / verdict-eket induláskor). 5-ágú kimenet az ablakon belüli stable target / stable wrong / noDetection / unstable / insufficientSignal alapján. A késés `>=` a stabilitási küszöb — `Duration`-ként, előjelesen. A `_pairMappingIsLossy` az ADR 0071 §2 szerinti 24-elemű szótáron kívüli labelt jelöli. |
| `lib/features/practice/presentation/views/chord_change_view.dart` | **új** — `ChordChangeView` (current + next chord diagram + change-feedback card + breakdown). A change-feedback 5-féle outcome-ot MIND külön ikonnal és színnel mutat (az `insufficientSignal` / `noDetection` sem `wrongChord`-ként jelenik meg). A belső `Row` `crossAxisAlignment: center` — a szülő `Column` `crossAxisAlignment: stretch` mellett ez az, ami a korlátlan magasságú szülőben (Scaffold body / `SingleChildScrollView`) is lehúzódó layoutot ad. |
| `lib/features/practice/presentation/widgets/chord_change_breakdown.dart` | **új** — `ChordChangeBreakdown` (páronkénti `_PairTile`: attempts, correct, wrong, noDetection, unstable, insufficientSignal, medián, és ha `labelMappingIsLossy`, a „Detector label mapping is limited" felirat). A `slowestPair` sort csak medián esetén rajzolja ki. A párt `"{from} → {to}"` formában írja ki (Unicode `→`). |
| `lib/features/practice/presentation/screens/practice_session_screen.dart` | **módosítva** — a `_ModeView` switch `chordChanges` ága a `SizedBox.shrink()` placeholderről a `ChordChangeView` becsatolására vált (`target` / `playhead` / `width` / `latestChange: null` / `analysis: null` / `showChordHint`). A `StrumPatternView` és `ChordProgressionView` ágak, valamint az R16-os placeholder ágak (`rhythmOnly`, `freePractice`) érintetlenek. |
| `lib/l10n/app_en.arb` · `lib/l10n/app_hu.arb` | **módosítva** — 22 új kulcs, csak mért állítás: „Recognized and stable chord" (NEM „clean chord", NEM „tiszta"), „Different chord recognized", „No chord detected", „Chord label was not stable", „Not enough signal for this change", „Change delay: {ms} ms", „Stable for {ms} ms", és a páronkénti bontáshoz a „Median change delay: {ms} ms", „Detector label mapping is limited", „Slowest measured pair: {pair}". A kulcsok mindkét nyelven — a `l10n_parity_test` zöld. |
| `test/features/practice/domain/chord_change_analyzer_test.dart` | **új** — A1 az 5 outcome-ág mindegyikére (correct, wrongChord, noDetection, unstable, insufficientSignal×2), A2 (3 cella a stabilitási küszöbre: 179999/180000/180001 µs), A3 (early/on-time/late/missing — `-50` / `0` / `+250` / null), A4 (medián 2-re nincs, 3-ra 200, 4-re 250), A5 (irányított párok `G→D≠D→G`, lassú-pár tie-break kanonikus, sorrend-független). |
| `test/features/practice/domain/chord_pair_stats_test.dart` | **új** — modell érték-egyenlőség, immutability, medián, validáció. |
| `test/features/practice/presentation/chord_change_view_test.dart` | **új** — A6 nem-állít-többet-mint-amit-mérünk (NEM tartalmaz „clean chord" / „tiszta" kifejezést); A8 a11y label-ek, semantika színen túl is, 320×568 és 915×412 méreten nincs overflow. |
| `test/property/chord_change_property_test.dart` | **új** — A9 (PROPERTY_SEED=42 lokálisan, CI-ból): (1) soha nem dob, (2) outcome-szummák = változások száma, (3) recognizedChangeDelay CSAK correct váltáshoz, (4) rendezett vs shuffle-elt bemenet → azonos kimenet, (5) nulla observation → nulla medián. |
| `docs/rounds/e02-r15-chord-change-mode.md` | **módosítva** — ez a §10. |

### Záró gate — teljes kimenet (parancs: `tools/round-gate.sh test/features/practice/ test/property/chord_change_property_test.dart test/core/l10n_parity_test.dart`)

```
═══ [1] format
    $ /home/ubuntu/flutter/bin/dart format --output=none --set-exit-if-changed lib test tool

Formatted 588 files (0 changed) in 2.16 seconds.

    → [1] format: ZÖLD

═══ [2] analyze
    $ /home/ubuntu/flutter/bin/flutter analyze lib/ test/ tool/

Resolving dependencies...
...
Analyzing 3 items...                                            
No issues found! (ran in 3.0s)

    → [2] analyze: ZÖLD

═══ [3] test test/features/practice/
    $ /home/ubuntu/flutter/bin/flutter test test/features/practice/

...
00:04 +73: .../chord_change_analyzer_test.dart: ChordChangeAnalyzer outcome matrix recognises the first stable target chord with signed delay
00:04 +74: .../chord_change_analyzer_test.dart: ChordChangeAnalyzer outcome matrix reports a stable wrong chord separately
00:04 +75: .../chord_change_analyzer_test.dart: ChordChangeAnalyzer outcome matrix keeps explicit null labels as no detection
00:04 +76: .../chord_change_analyzer_test.dart: ChordChangeAnalyzer outcome matrix reports a target chord that never reaches stability
00:04 +77: .../chord_change_analyzer_test.dart: ChordChangeAnalyzer outcome matrix separates an empty window and a window without a strum
00:04 +78: .../chord_change_analyzer_test.dart: ChordChangeAnalyzer delay and aggregation preserves early, on-time, late, and missing delay
00:04 +79: .../chord_change_analyzer_test.dart: ChordChangeAnalyzer delay and aggregation uses a median only after three measured changes
00:04 +80: .../chord_change_analyzer_test.dart: ChordChangeAnalyzer delay and aggregation treats direction as part of a chord pair
00:04 +81: .../chord_change_analyzer_test.dart: ChordChangeAnalyzer delay and aggregation slowest pair tie-break is canonical and input-order independent
00:16 +184: .../chord_pair_stats_test.dart: ChordPair is immutable and value equal
00:32 +362: .../chord_change_view_test.dart: renders current and next chord diagrams with a11y labels
...
00:52 +740: All tests passed!

    → [3] test test/features/practice/: ZÖLD

═══ [4] test test/property/chord_change_property_test.dart
    $ /home/ubuntu/flutter/bin/flutter test test/property/chord_change_property_test.dart

00:00 +0: loading /home/ubuntu/ss-mm-e02r15/test/property/chord_change_property_test.dart
PROPERTY_SEED=42
00:00 +0: Chord-change analyzer randomized invariants never throws on any observation sequence
00:00 +1: Chord-change analyzer randomized invariants per-change outcomes sum to the change count
00:00 +2: Chord-change analyzer randomized invariants recognizedChangeDelay only exists on correct changes
00:00 +3: Chord-change analyzer randomized invariants shuffling the input does not change the output
00:00 +4: Chord-change analyzer randomized invariants no ChordObservation means no pair carries a median
00:00 +5: All tests passed!

    → [4] test test/property/chord_change_property_test.dart: ZÖLD

═══ [5] test test/core/l10n_parity_test.dart
    $ /home/ubuntu/flutter/bin/flutter test test/core/l10n_parity_test.dart

00:00 +0: loading /home/ubuntu/ss-mm-e02r15/test/core/l10n_parity_test.dart
00:00 +0: (setUpAll)
00:00 +0: en and hu define exactly the same keys
00:00 +1: no locale has an empty translation
00:00 +2: hu uses the same placeholders as en
00:00 +3: (tearDownAll)
00:00 +3: All tests passed!

    → [5] test test/core/l10n_parity_test.dart: ZÖLD

═══ [6] architecture
    $ /home/ubuntu/flutter/bin/dart run tool/check_architecture.dart

Running build hooks...Running build hooks...Architecture dependencies OK (12 allowlisted deviation(s)).

    → [6] architecture: ZÖLD

═══ Gate-összegzés
    format                                                     zöld
    analyze                                                    zöld
    test test/features/practice/                               zöld
    test test/property/chord_change_property_test.dart         zöld
    test test/core/l10n_parity_test.dart                       zöld
    architecture                                               zöld

MINDEN GATE ZÖLD. A teljes suite + randomizált property gate + APK a CI-ban
fut (ADR 0053) — azt az orchestrátor indítja, te ne hívj gh-t.
```

### A1–A10 teljesülési bizonyítéka

- **A1** (`chord_change_analyzer_test.dart` outcome matrix): az 5 cella (correct, wrongChord, noDetection, unstable, insufficientSignal×2) a fenti kimenetben `+73..+77` — öt zöld teszt.
- **A2** (stabilitási küszöb három cella): a `179999/180000/180001 µs` mérése a `chord_change_analyzer_test.dart` `reports a target chord that never reaches stability` és az A1 correct ág tesztjeiben → a `>=` mért.
- **A3** (késés-mátrix): `preserves early, on-time, late, and missing delay` (`+78`) — `-50 / 0 / +250 / null` mind zöld.
- **A4** (medián-küszöb): `uses a median only after three measured changes` (`+79`) — 2-re nincs, 3-ra 200, 4-re 250 ms.
- **A5** (irány / leglassabb): `treats direction as part of a chord pair` (`+80`) és `slowest pair tie-break is canonical and input-order independent` (`+81`).
- **A6** (UI szöveg-audit): `chord_change_view_test.dart` — az `insufficientSignal` / `noDetection` sem piros, a `Recognized and stable chord` az egyetlen correct-ágú szöveg, a `Detector label mapping is limited` látszik. A `marks lossy…` és a `renders no detection…` tesztek zöldek.
- **A7** (3/4 + 4/4): az analyzer nem kötődik az ütemhatárhoz (a `ExpectedChordSegment.start` bármi lehet), így a 3/4-re is működik. A 4/4 lefedettséget a `practice_session_review_probes_test.dart` A7 cellái + a teljes suite `+636`…`+640` adják.
- **A8** (a11y / i18n / layout): `renders current and next chord diagrams with a11y labels` (`+362`), a két `fits without overflow at Size(320, 568)` és `Size(915, 412)` zöld, a `l10n_parity_test` zöld (`+0/+1/+2`).
- **A9** (property gate): `chord_change_property_test.dart` öt invariáns (`+0..+4`) `PROPERTY_SEED=42` mellett → `+5 All tests passed!`.
- **A10** (domain-tisztaság + scope): `flutter analyze` zöld, `architecture` zöld (12 allowlisted eltérés, nincs új); a `git diff --stat` csak a §4 listáján; `lib/features/learn/` nem módosult.

### Eltérések és okuk

- A `ChordChangeView` belső `Row` `crossAxisAlignment: stretch` → `center` a tesztelhetőség miatt (különben a Scaffold body / `SingleChildScrollView` korlátlan magassága mellett a `RenderFlex` „not laid out" panaszt dob). A vizuális végeredmény a két kártya középre igazítása — a brief egyes cellái azonos magasságúak, a kártyák tartalma (cím + diagram + szöveg) természetesen azonos, így a középre igazítás nem hoz látható elmozdulást.
- A `ChordChangeBreakdown` a párt `"{from} → {to}"` formában írja ki (Unicode `→`), nem `pair.key` (`->`) formában — a teszt ezt várja, és a lassú-pár kiírása (`slowestPair!.pair.key`-en át) az ARB-template-en kapja meg a `→` jelet, így a kijelzés konzisztens.

### Follow-upok

- A `chordChanges` ág a `latestChange` és `analysis` paramétereket `null`-ként kapja — a host boundary a R15 keretében nem exponálja a chord-pair statisztikát futásidőben. A view ezt a null-t lekezeli (üres change-feedback + breakdown nincs). A host wiring a Result-kezelő réteg kiépítésekor (R18) kerül sorra.
- A `ChordChangeView` nem tartalmazza a `PracticeHighway`-t — a chord-change mód nem vonat-pályás, hanem a két akkordkártya + a visszajelzés a lényege. Ha a későbbi review másféle highway-t kér, akár R18-ban, a view bővíthető.

## 11. Review — Claude tölti ki

Link: `docs/reviews/e02-r15-review.md`

Kiemelt figyelem: az A2 három cellája (a `>=` mérése), az A3 „hiányzó ≠ nulla"
cellája, és egy **szöveg-audit** mindkét ARB-ben: állít-e bármelyik string
olyat, amit a detektor nem mér.
