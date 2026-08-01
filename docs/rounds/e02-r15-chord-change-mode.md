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
| `test/features/practice/domain/chord_change_analyzer_test.dart` | **új** — A1 az 5 outcome-ág mindegyikére (correct, wrongChord, noDetection, unstable, insufficientSignal×2), A2 (3 cella a stabilitási küszöbre: 179999/180000/180001 µs), A3 (early/on-time/late/missing — `-50` / `0` / `+250` / null), A4 (medián 2-re nincs, 3-ra 200, 4-re 250), A5 (irányított párok `G→D≠D→G`, lassú-pár tie-break kanonikus, sorrend-független), A7 (külön 3/4 és 4/4 ütemhatár-cella, mindkettő `correct` + 100 ms késés + páronkénti statisztika). |
| `test/features/practice/domain/chord_pair_stats_test.dart` | **új** — modell érték-egyenlőség, immutability, medián, validáció. |
| `test/features/practice/presentation/chord_change_view_test.dart` | **új** — A6 nem-állít-többet-mint-amit-mérünk (NEM tartalmaz „clean chord" / „tiszta" kifejezést); A8 a11y label-ek, semantika színen túl is, 320×568 és 915×412 méreten nincs overflow. |
| `test/property/chord_change_property_test.dart` | **új** — A9 (PROPERTY_SEED=42 lokálisan, CI-ból): (1) soha nem dob, (2) outcome-szummák = változások száma, (3) recognizedChangeDelay CSAK correct váltáshoz, (4) rendezett vs shuffle-elt bemenet → azonos kimenet, (5) nulla observation → nulla medián. |
| `docs/rounds/e02-r15-chord-change-mode.md` | **módosítva** — ez a §10. |

### Záró gate — teljes kimenet (parancs: `tools/round-gate.sh test/features/practice/ test/property/chord_change_property_test.dart test/core/l10n_parity_test.dart`)

```

═══ [1] format
    $ /home/ubuntu/flutter/bin/dart format --output=none --set-exit-if-changed lib test tool

Formatted 588 files (0 changed) in 2.18 seconds.

    → [1] format: ZÖLD

═══ [2] analyze
    $ /home/ubuntu/flutter/bin/flutter analyze lib/ test/ tool/

Resolving dependencies...
Downloading packages...
  _fe_analyzer_shared 99.0.0 (105.0.0 available)
  analyzer 12.1.0 (14.1.0 available)
  dio 5.10.0 (5.11.0 available)
  dio_web_adapter 2.2.0 (2.2.1 available)
  flutter_local_notifications 22.0.1 (22.2.0 available)
  flutter_local_notifications_platform_interface 12.0.0 (12.1.0 available)
  flutter_riverpod 3.3.2 (3.4.2 available)
  flutter_secure_storage_darwin 0.3.2 (0.4.0 available)
  flutter_secure_storage_platform_interface 2.0.1 (2.0.2 available)
  hooks 2.0.2 (2.1.0 available)
  intl 0.20.2 (0.20.3 available)
  jni 1.0.0 (1.0.3 available)
  jni_flutter 1.0.1 (1.0.2 available)
  matcher 0.12.19 (0.12.20 available)
  meta 1.18.0 (1.19.0 available)
  objective_c 9.4.1 (9.5.0 available)
  package_config 2.2.0 (3.0.0 available)
  package_info_plus 10.2.0 (10.2.1 available)
  permission_handler 12.0.3 (13.0.0 available)
  permission_handler_android 13.0.1 (14.0.0 available)
  permission_handler_apple 9.4.10 (9.5.0 available)
  permission_handler_html 0.1.3+5 (0.1.4+0 available)
  permission_handler_platform_interface 4.3.0 (4.4.0 available)
  permission_handler_windows 0.2.1 (0.2.2 available)
  record_use 0.6.0 (1.0.0 available)
  riverpod 3.3.2 (3.4.2 available)
  share_plus 13.2.0 (13.3.0 available)
  share_plus_platform_interface 7.1.0 (7.2.0 available)
  shared_preferences_android 2.4.26 (2.4.27 available)
  synchronized 3.4.1 (3.4.1+1 available)
  test 1.31.0 (1.31.2 available)
  test_api 0.7.11 (0.7.13 available)
  test_core 0.6.17 (0.6.19 available)
  uuid 4.5.3 (4.6.0 available)
  vector_math 2.2.0 (2.4.2 available)
  wakelock_plus 1.6.1 (1.7.0 available)
  wakelock_plus_platform_interface 1.5.1 (1.6.0 available)
  xml 6.6.1 (7.0.1 available)
Got dependencies!
38 packages have newer versions incompatible with dependency constraints.
Try `flutter pub outdated` for more information.
Analyzing 3 items...                                            
No issues found! (ran in 2.9s)

    → [2] analyze: ZÖLD

═══ [3] test test/features/practice/
    $ /home/ubuntu/flutter/bin/flutter test test/features/practice/

Resolving dependencies...
Downloading packages...
  _fe_analyzer_shared 99.0.0 (105.0.0 available)
  analyzer 12.1.0 (14.1.0 available)
  dio 5.10.0 (5.11.0 available)
  dio_web_adapter 2.2.0 (2.2.1 available)
  flutter_local_notifications 22.0.1 (22.2.0 available)
  flutter_local_notifications_platform_interface 12.0.0 (12.1.0 available)
  flutter_riverpod 3.3.2 (3.4.2 available)
  flutter_secure_storage_darwin 0.3.2 (0.4.0 available)
  flutter_secure_storage_platform_interface 2.0.1 (2.0.2 available)
  hooks 2.0.2 (2.1.0 available)
  intl 0.20.2 (0.20.3 available)
  jni 1.0.0 (1.0.3 available)
  jni_flutter 1.0.1 (1.0.2 available)
  matcher 0.12.19 (0.12.20 available)
  meta 1.18.0 (1.19.0 available)
  objective_c 9.4.1 (9.5.0 available)
  package_config 2.2.0 (3.0.0 available)
  package_info_plus 10.2.0 (10.2.1 available)
  permission_handler 12.0.3 (13.0.0 available)
  permission_handler_android 13.0.1 (14.0.0 available)
  permission_handler_apple 9.4.10 (9.5.0 available)
  permission_handler_html 0.1.3+5 (0.1.4+0 available)
  permission_handler_platform_interface 4.3.0 (4.4.0 available)
  permission_handler_windows 0.2.1 (0.2.2 available)
  record_use 0.6.0 (1.0.0 available)
  riverpod 3.3.2 (3.4.2 available)
  share_plus 13.2.0 (13.3.0 available)
  share_plus_platform_interface 7.1.0 (7.2.0 available)
  shared_preferences_android 2.4.26 (2.4.27 available)
  synchronized 3.4.1 (3.4.1+1 available)
  test 1.31.0 (1.31.2 available)
  test_api 0.7.11 (0.7.13 available)
  test_core 0.6.17 (0.6.19 available)
  uuid 4.5.3 (4.6.0 available)
  vector_math 2.2.0 (2.4.2 available)
  wakelock_plus 1.6.1 (1.7.0 available)
  wakelock_plus_platform_interface 1.5.1 (1.6.0 available)
  xml 6.6.1 (7.0.1 available)
Got dependencies!
38 packages have newer versions incompatible with dependency constraints.
Try `flutter pub outdated` for more information.
00:00 +0: loading /home/ubuntu/ss-mm-e02r15/test/features/practice/domain/meter_test.dart
00:00 +0: /home/ubuntu/ss-mm-e02r15/test/features/practice/domain/meter_test.dart: Meter validation accepts 4/4, 3/4, and supported 6/8 meter
00:00 +1: /home/ubuntu/ss-mm-e02r15/test/features/practice/domain/meter_test.dart: Meter validation rejects beats-per-bar values outside 1 through 16
00:00 +2: /home/ubuntu/ss-mm-e02r15/test/features/practice/domain/meter_test.dart: Meter validation rejects unsupported beat units
00:00 +3: /home/ubuntu/ss-mm-e02r15/test/features/practice/domain/meter_test.dart: Meter validation aggregates independent field failures
00:00 +4: /home/ubuntu/ss-mm-e02r15/test/features/practice/domain/meter_test.dart: Meter tick arithmetic computes exact ticks per bar for supported meters
00:00 +5: /home/ubuntu/ss-mm-e02r15/test/features/practice/domain/meter_test.dart: Meter tick arithmetic fails fast symmetrically for every invalid input field
00:00 +6: /home/ubuntu/ss-mm-e02r15/test/features/practice/domain/meter_test.dart: Meter value semantics uses both fields as its value identity
00:00 +7: /home/ubuntu/ss-mm-e02r15/test/features/practice/domain/practice_value_equality_test.dart: Practice value equality helpers compares lists structurally and hashes equal lists equally
00:00 +8: /home/ubuntu/ss-mm-e02r15/test/features/practice/domain/practice_value_equality_test.dart: Practice value equality helpers compares maps structurally independent of insertion order
00:00 +9: /home/ubuntu/ss-mm-e02r15/test/features/practice/domain/practice_definition_test.dart: PracticeDefinition validation accepts a complete valid definition
00:00 +10: /home/ubuntu/ss-mm-e02r15/test/features/practice/domain/practice_definition_test.dart: PracticeDefinition validation aggregates definition fields and nested Tempo failures
00:00 +11: /home/ubuntu/ss-mm-e02r15/test/features/practice/domain/practice_definition_test.dart: PracticeDefinition validation rejects a non-positive total duration
00:00 +12: /home/ubuntu/ss-mm-e02r15/test/features/practice/domain/practice_definition_test.dart: PracticeDefinition validation requires a non-empty target list only for scored modes
00:00 +13: /home/ubuntu/ss-mm-e02r15/test/features/practice/domain/practice_definition_test.dart: PracticeDefinition validation reports decreasing positions as unsorted
00:00 +14: /home/ubuntu/ss-mm-e02r15/test/features/practice/domain/practice_definition_test.dart: PracticeDefinition validation reports duplicate event IDs independently of positions
00:00 +15: /home/ubuntu/ss-mm-e02r15/test/features/practice/domain/practice_definition_test.dart: PracticeDefinition validation reports duplicate positions without treating them as unsorted
00:00 +16: /home/ubuntu/ss-mm-e02r15/test/features/practice/domain/practice_definition_test.dart: PracticeDefinition validation rejects positions at and beyond the exclusive totalBeats bound
00:00 +17: /home/ubuntu/ss-mm-e02r15/test/features/practice/domain/practice_definition_test.dart: PracticeDefinition validation passes nested event failures through unchanged
00:00 +18: /home/ubuntu/ss-mm-e02r15/test/features/practice/domain/practice_definition_test.dart: PracticeDefinition validation enforces exact mode-to-weight-key compatibility
00:00 +19: /home/ubuntu/ss-mm-e02r15/test/features/practice/domain/practice_definition_test.dart: PracticeDefinition validation displayTitle accepts null and non-blank text, rejects blank
00:00 +20: /home/ubuntu/ss-mm-e02r15/test/features/practice/domain/practice_definition_test.dart: PracticeDefinition value semantics deeply compares lists and supports Set and Map keys
00:00 +21: /home/ubuntu/ss-mm-e02r15/test/features/practice/domain/beat_time_converter_test.dart: BeatTimeConverter forward conversion uses one final microsecond rounding step
00:00 +22: /home/ubuntu/ss-mm-e02r15/test/features/practice/domain/beat_time_converter_test.dart: BeatTimeConverter forward conversion exposes exact quarter-beat and meter-aware bar durations
00:00 +23: /home/ubuntu/ss-mm-e02r15/test/features/practice/domain/beat_time_converter_test.dart: BeatTimeConverter inverse conversion round-trips every 32-tick grid point over 64 quarter beats
00:01 +24: /home/ubuntu/ss-mm-e02r15/test/features/practice/domain/beat_time_converter_test.dart: BeatTimeConverter inverse conversion rejects negative elapsed time
00:01 +25: /home/ubuntu/ss-mm-e02r15/test/features/practice/domain/beat_time_converter_test.dart: BeatTimeConverter validation guards every conversion member rejects an invalid tempo
00:01 +26: /home/ubuntu/ss-mm-e02r15/test/features/practice/domain/beat_time_converter_test.dart: BeatTimeConverter validation guards every conversion member rejects an invalid meter
00:01 +27: /home/ubuntu/ss-mm-e02r15/test/features/practice/domain/domain_purity_test.dart: practice domain has no ambient IO, nondeterminism, or app imports
00:01 +28: /home/ubuntu/ss-mm-e02r15/test/features/practice/domain/domain_purity_test.dart: purity scan ignores forbidden spellings in comments and strings
00:01 +29: /home/ubuntu/ss-mm-e02r15/test/features/practice/domain/domain_purity_test.dart: purity scan recognizes root l10n and Riverpod imports
00:01 +30: /home/ubuntu/ss-mm-e02r15/test/features/practice/domain/domain_purity_test.dart: purity scan inspects executable string interpolation bodies
00:01 +31: /home/ubuntu/ss-mm-e02r15/test/features/practice/domain/practice_event_test.dart: canonical practice chord labels accepts null and sharp-spelled major or minor labels
00:01 +32: /home/ubuntu/ss-mm-e02r15/test/features/practice/domain/practice_event_test.dart: canonical practice chord labels rejects empty, no-chord, flat, extended, lowercase, and padded labels
00:01 +33: /home/ubuntu/ss-mm-e02r15/test/features/practice/domain/practice_event_test.dart: PracticeEvent validation accepts scored events and a marker without scored attributes
00:01 +34: /home/ubuntu/ss-mm-e02r15/test/features/practice/domain/practice_event_test.dart: PracticeEvent validation reports an empty ID with the pinned code literal
00:01 +35: /home/ubuntu/ss-mm-e02r15/test/features/practice/domain/practice_event_test.dart: PracticeEvent validation rejects a zero duration with the pinned code literal
00:01 +36: /home/ubuntu/ss-mm-e02r15/test/features/practice/domain/practice_event_test.dart: PracticeEvent validation requires a scored attribute on a non-marker event
00:01 +37: /home/ubuntu/ss-mm-e02r15/test/features/practice/domain/practice_event_test.dart: PracticeEvent validation forbids scored attributes on marker events
00:01 +38: /home/ubuntu/ss-mm-e02r15/test/features/practice/domain/practice_event_test.dart: PracticeEvent validation aggregates independent event failures
00:01 +39: /home/ubuntu/ss-mm-e02r15/test/features/practice/domain/practice_event_test.dart: PracticeEvent value semantics supports structural equality, hashing, Set, and Map keys
00:02 +40: /home/ubuntu/ss-mm-e02r15/test/features/practice/domain/beat_position_test.dart: BeatPosition subdivisions uses 480 ticks per quarter-note beat
00:02 +41: /home/ubuntu/ss-mm-e02r15/test/features/practice/domain/beat_position_test.dart: BeatPosition subdivisions represents supported fractions with exact integer equality
00:02 +42: /home/ubuntu/ss-mm-e02r15/test/features/practice/domain/beat_position_test.dart: BeatPosition legacy bridge converts the current half-beat grid without deviation
00:02 +43: /home/ubuntu/ss-mm-e02r15/test/features/practice/domain/beat_position_test.dart: BeatPosition legacy bridge round-trips every supported deterministic subdivision position
00:02 +44: /home/ubuntu/ss-mm-e02r15/test/features/practice/domain/beat_position_test.dart: BeatPosition legacy bridge rounds one third of a beat to the nearest exact triplet tick
00:02 +45: /home/ubuntu/ss-mm-e02r15/test/features/practice/domain/beat_position_test.dart: BeatPosition legacy bridge rejects non-finite legacy input explicitly
00:02 +46: /home/ubuntu/ss-mm-e02r15/test/features/practice/domain/beat_position_test.dart: BeatPosition invariants rejects negative data-driven positions in every runtime path
00:02 +47: /home/ubuntu/ss-mm-e02r15/test/features/practice/domain/beat_position_test.dart: BeatPosition invariants keeps the const constructor guarded in checked builds
00:02 +48: /home/ubuntu/ss-mm-e02r15/test/features/practice/domain/beat_position_test.dart: BeatPosition value operations sorts deterministically and compareTo agrees with equality
00:02 +49: /home/ubuntu/ss-mm-e02r15/test/features/practice/domain/beat_position_test.dart: BeatPosition value operations adds and subtracts positions exactly
00:02 +50: /home/ubuntu/ss-mm-e02r15/test/features/practice/domain/beat_position_test.dart: BeatPosition value operations has a deterministic diagnostic representation
00:02 +51: /home/ubuntu/ss-mm-e02r15/test/features/practice/domain/tempo_test.dart: Tempo validation accepts the closed 30.0 through 300.0 BPM boundaries
00:02 +52: /home/ubuntu/ss-mm-e02r15/test/features/practice/domain/tempo_test.dart: Tempo validation reports finite values outside the range without clamping
00:02 +53: /home/ubuntu/ss-mm-e02r15/test/features/practice/domain/tempo_test.dart: Tempo validation reports NaN and infinities as not finite
00:02 +54: /home/ubuntu/ss-mm-e02r15/test/features/practice/domain/tempo_test.dart: Tempo value semantics uses BPM as its value identity
00:02 +55: /home/ubuntu/ss-mm-e02r15/test/features/practice/domain/practice_validation_test.dart: PracticeValidationCode defines the complete stable code set
00:03 +56: /home/ubuntu/ss-mm-e02r15/test/features/practice/domain/practice_validation_test.dart: PracticeValidationCode pins target compiler validation and failure codes
00:03 +57: /home/ubuntu/ss-mm-e02r15/test/features/practice/domain/practice_validation_test.dart: PracticeValidationCode pins the five pre-existing codes at their producing boundaries
00:03 +58: /home/ubuntu/ss-mm-e02r15/test/features/practice/domain/practice_validation_test.dart: PracticeValidationFailure has value semantics
00:03 +59: /home/ubuntu/ss-mm-e02r15/test/features/practice/domain/practice_validation_test.dart: PracticeValidationFailure has a deterministic diagnostic representation
00:03 +60: /home/ubuntu/ss-mm-e02r15/test/features/practice/domain/compiled_practice_target_test.dart: Compiled practice target value models scalar models compare structurally and hash equal values equally
00:03 +61: /home/ubuntu/ss-mm-e02r15/test/features/practice/domain/compiled_practice_target_test.dart: Compiled practice target value models aggregate compares every list and scalar structurally
00:03 +62: /home/ubuntu/ss-mm-e02r15/test/features/practice/domain/compiled_practice_target_test.dart: Compiled practice target value models aggregate stores unmodifiable snapshots of every list
00:03 +63: /home/ubuntu/ss-mm-e02r15/test/features/practice/domain/practice_session_config_test.dart: PracticeSessionConfig validation accepts all closed range boundaries
00:03 +64: /home/ubuntu/ss-mm-e02r15/test/features/practice/domain/practice_session_config_test.dart: PracticeSessionConfig validation reports empty IDs and an invalid snapshot version
00:03 +65: /home/ubuntu/ss-mm-e02r15/test/features/practice/domain/practice_session_config_test.dart: PracticeSessionConfig validation rejects count-in values outside zero through four
00:03 +66: /home/ubuntu/ss-mm-e02r15/test/features/practice/domain/practice_session_config_test.dart: PracticeSessionConfig validation rejects loop counts outside one through 32
00:03 +67: /home/ubuntu/ss-mm-e02r15/test/features/practice/domain/practice_session_config_test.dart: PracticeSessionConfig validation rejects input latency outside zero through 500 milliseconds
00:03 +68: /home/ubuntu/ss-mm-e02r15/test/features/practice/domain/practice_session_config_test.dart: PracticeSessionConfig validation rejects visual latency outside zero through 500 milliseconds
00:03 +69: /home/ubuntu/ss-mm-e02r15/test/features/practice/domain/practice_session_config_test.dart: PracticeSessionConfig validation requires a strictly positive session timeout
00:03 +70: /home/ubuntu/ss-mm-e02r15/test/features/practice/domain/practice_session_config_test.dart: PracticeSessionConfig validation passes nested Tempo failures through unchanged
00:03 +71: /home/ubuntu/ss-mm-e02r15/test/features/practice/domain/practice_session_config_test.dart: PracticeSessionConfig validation aggregates at least three independent failures
00:03 +72: /home/ubuntu/ss-mm-e02r15/test/features/practice/domain/practice_session_config_test.dart: PracticeSessionConfig value semantics compares all fields and copyWith preserves or changes explicitly
00:04 +73: /home/ubuntu/ss-mm-e02r15/test/features/practice/domain/chord_change_analyzer_test.dart: ChordChangeAnalyzer outcome matrix recognises the first stable target chord with signed delay
00:04 +74: /home/ubuntu/ss-mm-e02r15/test/features/practice/domain/chord_change_analyzer_test.dart: ChordChangeAnalyzer outcome matrix reports a stable wrong chord separately
00:04 +75: /home/ubuntu/ss-mm-e02r15/test/features/practice/domain/chord_change_analyzer_test.dart: ChordChangeAnalyzer outcome matrix keeps explicit null labels as no detection
00:04 +76: /home/ubuntu/ss-mm-e02r15/test/features/practice/domain/chord_change_analyzer_test.dart: ChordChangeAnalyzer outcome matrix reports a target chord that never reaches stability
00:04 +77: /home/ubuntu/ss-mm-e02r15/test/features/practice/domain/chord_change_analyzer_test.dart: ChordChangeAnalyzer outcome matrix 179999 microseconds of stability remains unstable
00:04 +78: /home/ubuntu/ss-mm-e02r15/test/features/practice/domain/chord_change_analyzer_test.dart: ChordChangeAnalyzer outcome matrix 180001 microseconds of stability is correct
00:04 +79: /home/ubuntu/ss-mm-e02r15/test/features/practice/domain/chord_change_analyzer_test.dart: ChordChangeAnalyzer outcome matrix separates an empty window and a window without a strum
00:04 +80: /home/ubuntu/ss-mm-e02r15/test/features/practice/domain/chord_change_analyzer_test.dart: ChordChangeAnalyzer meter boundaries 3/4 change on a bar boundary produces correct statistics
00:04 +81: /home/ubuntu/ss-mm-e02r15/test/features/practice/domain/chord_change_analyzer_test.dart: ChordChangeAnalyzer meter boundaries 4/4 change on a bar boundary produces correct statistics
00:04 +82: /home/ubuntu/ss-mm-e02r15/test/features/practice/domain/chord_change_analyzer_test.dart: ChordChangeAnalyzer delay and aggregation preserves early, on-time, late, and missing delay
00:04 +83: /home/ubuntu/ss-mm-e02r15/test/features/practice/domain/chord_change_analyzer_test.dart: ChordChangeAnalyzer delay and aggregation uses a median only after three measured changes
00:04 +84: /home/ubuntu/ss-mm-e02r15/test/features/practice/domain/chord_change_analyzer_test.dart: ChordChangeAnalyzer delay and aggregation treats direction as part of a chord pair
00:04 +85: /home/ubuntu/ss-mm-e02r15/test/features/practice/domain/chord_change_analyzer_test.dart: ChordChangeAnalyzer delay and aggregation slowest pair tie-break is canonical and input-order independent
00:04 +86: /home/ubuntu/ss-mm-e02r15/test/features/practice/domain/practice_result_test.dart: PracticeAttemptResult validation accepts a valid attempt and aggregates nested values
00:04 +87: /home/ubuntu/ss-mm-e02r15/test/features/practice/domain/practice_result_test.dart: PracticeAttemptResult validation rejects a negative attempt index
00:04 +88: /home/ubuntu/ss-mm-e02r15/test/features/practice/domain/practice_result_test.dart: PracticeAttemptResult validation rejects duplicate verdict target IDs
00:04 +89: /home/ubuntu/ss-mm-e02r15/test/features/practice/domain/practice_result_test.dart: PracticeAttemptResult validation compares the verdict list and all other fields structurally
00:04 +90: /home/ubuntu/ss-mm-e02r15/test/features/practice/domain/practice_result_test.dart: PracticeSessionResult validation accepts a valid session with canonical coaching codes
00:04 +91: /home/ubuntu/ss-mm-e02r15/test/features/practice/domain/practice_result_test.dart: PracticeSessionResult validation rejects an empty session ID and attempt list
00:04 +92: /home/ubuntu/ss-mm-e02r15/test/features/practice/domain/practice_result_test.dart: PracticeSessionResult validation requires attempt indexes to be strictly increasing
00:04 +93: /home/ubuntu/ss-mm-e02r15/test/features/practice/domain/practice_result_test.dart: PracticeSessionResult validation continues nested validation after an attempt ordering failure
00:04 +94: /home/ubuntu/ss-mm-e02r15/test/features/practice/domain/practice_result_test.dart: PracticeSessionResult validation rejects negative active and paused durations
00:04 +95: /home/ubuntu/ss-mm-e02r15/test/features/practice/domain/practice_result_test.dart: PracticeSessionResult validation rejects an unknown coaching-summary code
00:04 +96: /home/ubuntu/ss-mm-e02r15/test/features/practice/domain/practice_result_test.dart: PracticeSessionResult validation aggregates attempt and highest-stable-tempo failures
00:04 +97: /home/ubuntu/ss-mm-e02r15/test/features/practice/domain/practice_result_test.dart: PracticeSessionResult validation compares attempt and coaching lists structurally
00:04 +98: /home/ubuntu/ss-mm-e02r15/test/features/practice/domain/practice_result_test.dart: PracticeSessionResult derived attempts finalAttempt selects the greatest index independent of list order
00:04 +99: /home/ubuntu/ss-mm-e02r15/test/features/practice/domain/practice_result_test.dart: PracticeSessionResult derived attempts bestAttempt selects the greatest available overall score
00:04 +100: /home/ubuntu/ss-mm-e02r15/test/features/practice/domain/practice_result_test.dart: PracticeSessionResult derived attempts bestAttempt breaks score ties with the smaller index
00:04 +101: /home/ubuntu/ss-mm-e02r15/test/features/practice/domain/practice_result_test.dart: PracticeSessionResult derived attempts derived getters return null when no attempt is comparable
00:05 +102: /home/ubuntu/ss-mm-e02r15/test/features/practice/domain/practice_metrics_test.dart: MetricValue validation accepts available score boundaries and explicit unavailable states
00:05 +103: /home/ubuntu/ss-mm-e02r15/test/features/practice/domain/practice_metrics_test.dart: MetricValue validation reports non-finite values without a duplicate range failure
00:05 +104: /home/ubuntu/ss-mm-e02r15/test/features/practice/domain/practice_metrics_test.dart: MetricValue validation rejects finite values outside zero through one
00:05 +105: /home/ubuntu/ss-mm-e02r15/test/features/practice/domain/practice_metrics_test.dart: MetricValue validation requires an insufficient-data reason code
00:05 +106: /home/ubuntu/ss-mm-e02r15/test/features/practice/domain/practice_metrics_test.dart: PracticeMetrics validation accepts a valid metric set including signed timing bias
00:05 +107: /home/ubuntu/ss-mm-e02r15/test/features/practice/domain/practice_metrics_test.dart: PracticeMetrics validation passes nested metric failures through unchanged
00:05 +108: /home/ubuntu/ss-mm-e02r15/test/features/practice/domain/practice_metrics_test.dart: PracticeMetrics validation rejects negative total target count
00:05 +109: /home/ubuntu/ss-mm-e02r15/test/features/practice/domain/practice_metrics_test.dart: PracticeMetrics validation rejects resolved targets greater than total targets
00:05 +110: /home/ubuntu/ss-mm-e02r15/test/features/practice/domain/practice_metrics_test.dart: PracticeMetrics validation rejects negative max combo and score points
00:05 +111: /home/ubuntu/ss-mm-e02r15/test/features/practice/domain/practice_metrics_test.dart: PracticeMetrics validation rejects a negative mean absolute offset
00:05 +112: /home/ubuntu/ss-mm-e02r15/test/features/practice/domain/practice_metrics_test.dart: Practice metric value semantics compares every MetricValue subtype by structure and subtype
00:05 +113: /home/ubuntu/ss-mm-e02r15/test/features/practice/domain/practice_metrics_test.dart: Practice metric value semantics compares PracticeMetrics structurally
00:05 +114: /home/ubuntu/ss-mm-e02r15/test/features/practice/domain/practice_chord_scorer_test.dart: PracticeChordScorer A3 inclusive asymmetric window -120001 us is outside the chord window
00:05 +115: /home/ubuntu/ss-mm-e02r15/test/features/practice/domain/practice_chord_scorer_test.dart: PracticeChordScorer A3 inclusive asymmetric window -120000 us is inside the chord window
00:05 +116: /home/ubuntu/ss-mm-e02r15/test/features/practice/domain/practice_chord_scorer_test.dart: PracticeChordScorer A3 inclusive asymmetric window -119999 us is inside the chord window
00:05 +117: /home/ubuntu/ss-mm-e02r15/test/features/practice/domain/practice_chord_scorer_test.dart: PracticeChordScorer A3 inclusive asymmetric window 419999 us is inside the chord window
00:05 +118: /home/ubuntu/ss-mm-e02r15/test/features/practice/domain/practice_chord_scorer_test.dart: PracticeChordScorer A3 inclusive asymmetric window 420000 us is inside the chord window
00:05 +119: /home/ubuntu/ss-mm-e02r15/test/features/practice/domain/practice_chord_scorer_test.dart: PracticeChordScorer A3 inclusive asymmetric window 420001 us is outside the chord window
00:05 +120: /home/ubuntu/ss-mm-e02r15/test/features/practice/domain/practice_chord_scorer_test.dart: PracticeChordScorer A3 outcome branches stable expected label is correct
00:05 +121: /home/ubuntu/ss-mm-e02r15/test/features/practice/domain/practice_chord_scorer_test.dart: PracticeChordScorer A3 outcome branches stable different label is wrong
00:05 +122: /home/ubuntu/ss-mm-e02r15/test/features/practice/domain/practice_chord_scorer_test.dart: PracticeChordScorer A3 outcome branches only null labels are noDetection, not wrong or insufficient
00:05 +123: /home/ubuntu/ss-mm-e02r15/test/features/practice/domain/practice_chord_scorer_test.dart: PracticeChordScorer A3 outcome branches an empty target window is insufficient data
00:05 +124: /home/ubuntu/ss-mm-e02r15/test/features/practice/domain/practice_chord_scorer_test.dart: PracticeChordScorer A3 outcome branches a label below the stability threshold is insufficient data
00:05 +125: /home/ubuntu/ss-mm-e02r15/test/features/practice/domain/practice_chord_scorer_test.dart: PracticeChordScorer A3 outcome branches a target without an expected chord is not applicable
00:05 +126: /home/ubuntu/ss-mm-e02r15/test/features/practice/domain/practice_chord_scorer_test.dart: PracticeChordScorer stability and aggregation the longest stable segment wins even when it is the wrong chord
00:05 +127: /home/ubuntu/ss-mm-e02r15/test/features/practice/domain/practice_chord_scorer_test.dart: PracticeChordScorer stability and aggregation nonconsecutive runs of the same label are not merged
00:05 +128: /home/ubuntu/ss-mm-e02r15/test/features/practice/domain/practice_chord_scorer_test.dart: PracticeChordScorer stability and aggregation unordered observations produce the same deterministic result
00:05 +129: /home/ubuntu/ss-mm-e02r15/test/features/practice/domain/practice_chord_scorer_test.dart: PracticeChordScorer stability and aggregation available outcomes use one integer truncating division
00:05 +130: /home/ubuntu/ss-mm-e02r15/test/features/practice/domain/practice_chord_scorer_test.dart: PracticeChordScorer stability and aggregation samples outside every window report insufficient samples
00:05 +131: /home/ubuntu/ss-mm-e02r15/test/features/practice/domain/practice_chord_scorer_test.dart: PracticeChordScorer stability and aggregation unmatched optional chord target does not dilute the metric
00:05 +132: /home/ubuntu/ss-mm-e02r15/test/features/practice/domain/practice_chord_scorer_test.dart: PracticeChordScorer stability and aggregation the event-score view rejects mutation
00:06 +133: /home/ubuntu/ss-mm-e02r15/test/features/practice/domain/practice_enums_test.dart: PracticeMode stable codes pins every code, round-trips, and rejects unknown codes
00:06 +134: /home/ubuntu/ss-mm-e02r15/test/features/practice/domain/practice_enums_test.dart: PracticeMode stable codes exposes the exact scored dimensions for each mode
00:06 +135: /home/ubuntu/ss-mm-e02r15/test/features/practice/domain/practice_enums_test.dart: PracticeSource stable codes pins every code, round-trips, and rejects unknown codes
00:06 +136: /home/ubuntu/ss-mm-e02r15/test/features/practice/domain/practice_enums_test.dart: PracticeDifficulty stable codes pins every code, round-trips, and rejects unknown codes
00:06 +137: /home/ubuntu/ss-mm-e02r15/test/features/practice/domain/practice_enums_test.dart: PracticeScoreDimension stable codes pins every code, round-trips, and rejects unknown codes
00:06 +138: /home/ubuntu/ss-mm-e02r15/test/features/practice/domain/practice_enums_test.dart: ExtraStrumPolicy stable codes pins every code, round-trips, and rejects unknown codes
00:06 +139: /home/ubuntu/ss-mm-e02r15/test/features/practice/domain/practice_enums_test.dart: TimingGrade stable codes pins every code, round-trips, and rejects unknown codes
00:06 +140: /home/ubuntu/ss-mm-e02r15/test/features/practice/domain/practice_enums_test.dart: PracticeAttemptOutcome stable codes pins every code, round-trips, and rejects unknown codes
00:06 +141: /home/ubuntu/ss-mm-e02r15/test/features/practice/domain/practice_enums_test.dart: PracticeFinishReason stable codes pins every code, round-trips, and rejects unknown codes
00:07 +142: /home/ubuntu/ss-mm-e02r15/test/features/practice/domain/practice_timing_scorer_test.dart: PracticeTimingScorer A1 boundary matrix early 0 us is exactly 1000 per mille
00:07 +143: /home/ubuntu/ss-mm-e02r15/test/features/practice/domain/practice_timing_scorer_test.dart: PracticeTimingScorer A1 boundary matrix late 0 us is exactly 1000 per mille
00:07 +144: /home/ubuntu/ss-mm-e02r15/test/features/practice/domain/practice_timing_scorer_test.dart: PracticeTimingScorer A1 boundary matrix early 49999 us is exactly 1000 per mille
00:07 +145: /home/ubuntu/ss-mm-e02r15/test/features/practice/domain/practice_timing_scorer_test.dart: PracticeTimingScorer A1 boundary matrix late 49999 us is exactly 1000 per mille
00:07 +146: /home/ubuntu/ss-mm-e02r15/test/features/practice/domain/practice_timing_scorer_test.dart: PracticeTimingScorer A1 boundary matrix early 50000 us is exactly 1000 per mille
00:07 +147: /home/ubuntu/ss-mm-e02r15/test/features/practice/domain/practice_timing_scorer_test.dart: PracticeTimingScorer A1 boundary matrix late 50000 us is exactly 1000 per mille
00:07 +148: /home/ubuntu/ss-mm-e02r15/test/features/practice/domain/practice_timing_scorer_test.dart: PracticeTimingScorer A1 boundary matrix early 50001 us is exactly 800 per mille
00:07 +149: /home/ubuntu/ss-mm-e02r15/test/features/practice/domain/practice_timing_scorer_test.dart: PracticeTimingScorer A1 boundary matrix late 50001 us is exactly 800 per mille
00:07 +150: /home/ubuntu/ss-mm-e02r15/test/features/practice/domain/practice_timing_scorer_test.dart: PracticeTimingScorer A1 boundary matrix early 119999 us is exactly 800 per mille
00:07 +151: /home/ubuntu/ss-mm-e02r15/test/features/practice/domain/practice_timing_scorer_test.dart: PracticeTimingScorer A1 boundary matrix late 119999 us is exactly 800 per mille
00:07 +152: /home/ubuntu/ss-mm-e02r15/test/features/practice/domain/practice_timing_scorer_test.dart: PracticeTimingScorer A1 boundary matrix early 120000 us is exactly 800 per mille
00:07 +153: /home/ubuntu/ss-mm-e02r15/test/features/practice/domain/practice_timing_scorer_test.dart: PracticeTimingScorer A1 boundary matrix late 120000 us is exactly 800 per mille
00:07 +154: /home/ubuntu/ss-mm-e02r15/test/features/practice/domain/practice_timing_scorer_test.dart: PracticeTimingScorer A1 boundary matrix early 120001 us is exactly 800 per mille
00:07 +155: /home/ubuntu/ss-mm-e02r15/test/features/practice/domain/practice_timing_scorer_test.dart: PracticeTimingScorer A1 boundary matrix late 120001 us is exactly 800 per mille
00:07 +156: /home/ubuntu/ss-mm-e02r15/test/features/practice/domain/practice_timing_scorer_test.dart: PracticeTimingScorer A1 boundary matrix early 200000 us is exactly 575 per mille
00:07 +157: /home/ubuntu/ss-mm-e02r15/test/features/practice/domain/practice_timing_scorer_test.dart: PracticeTimingScorer A1 boundary matrix late 200000 us is exactly 575 per mille
00:07 +158: /home/ubuntu/ss-mm-e02r15/test/features/practice/domain/practice_timing_scorer_test.dart: PracticeTimingScorer A1 boundary matrix early 279999 us is exactly 351 per mille
00:07 +159: /home/ubuntu/ss-mm-e02r15/test/features/practice/domain/practice_timing_scorer_test.dart: PracticeTimingScorer A1 boundary matrix late 279999 us is exactly 351 per mille
00:07 +160: /home/ubuntu/ss-mm-e02r15/test/features/practice/domain/practice_timing_scorer_test.dart: PracticeTimingScorer A1 boundary matrix early 280000 us is exactly 350 per mille
00:07 +161: /home/ubuntu/ss-mm-e02r15/test/features/practice/domain/practice_timing_scorer_test.dart: PracticeTimingScorer A1 boundary matrix late 280000 us is exactly 350 per mille
00:07 +162: /home/ubuntu/ss-mm-e02r15/test/features/practice/domain/practice_timing_scorer_test.dart: PracticeTimingScorer A1 boundary matrix an unmatched required target is a zero-score miss
00:07 +163: /home/ubuntu/ss-mm-e02r15/test/features/practice/domain/practice_timing_scorer_test.dart: PracticeTimingScorer aggregation uses integer accumulation and one truncating mean division
00:07 +164: /home/ubuntu/ss-mm-e02r15/test/features/practice/domain/practice_timing_scorer_test.dart: PracticeTimingScorer aggregation signed timing bias truncates toward zero in integer microseconds
00:07 +165: /home/ubuntu/ss-mm-e02r15/test/features/practice/domain/practice_timing_scorer_test.dart: PracticeTimingScorer aggregation open unmatched optional target does not dilute the rhythm dimension
00:07 +166: /home/ubuntu/ss-mm-e02r15/test/features/practice/domain/practice_timing_scorer_test.dart: PracticeTimingScorer aggregation finalized unmatched optional target does not dilute the rhythm dimension
00:07 +167: /home/ubuntu/ss-mm-e02r15/test/features/practice/domain/practice_timing_scorer_test.dart: PracticeTimingScorer aggregation an empty target has no applicable rhythm metric
00:07 +168: /home/ubuntu/ss-mm-e02r15/test/features/practice/domain/practice_timing_scorer_test.dart: PracticeTimingScorer aggregation the event-score view rejects mutation
00:07 +169: /home/ubuntu/ss-mm-e02r15/test/features/practice/domain/scoring_profile_test.dart: ScoringProfile validation accepts a valid weighted profile and an empty weight map
00:07 +170: /home/ubuntu/ss-mm-e02r15/test/features/practice/domain/scoring_profile_test.dart: ScoringProfile validation accepts closed threshold endpoints and equal positive windows
00:07 +171: /home/ubuntu/ss-mm-e02r15/test/features/practice/domain/scoring_profile_test.dart: ScoringProfile validation pins the legacy Learn parity profile literals
00:07 +172: /home/ubuntu/ss-mm-e02r15/test/features/practice/domain/scoring_profile_test.dart: ScoringProfile validation validates the four built-in non-strum profiles and pins literals
00:07 +173: /home/ubuntu/ss-mm-e02r15/test/features/practice/domain/scoring_profile_test.dart: ScoringProfile validation built-in non-strum profile weights exactly match their mode scored dimensions
00:07 +174: /home/ubuntu/ss-mm-e02r15/test/features/practice/domain/scoring_profile_test.dart: ScoringProfile validation reports an empty identifier with the pinned code literal
00:07 +175: /home/ubuntu/ss-mm-e02r15/test/features/practice/domain/scoring_profile_test.dart: ScoringProfile validation rejects zero and negative windows
00:07 +176: /home/ubuntu/ss-mm-e02r15/test/features/practice/domain/scoring_profile_test.dart: ScoringProfile validation rejects perfect greater than good and good greater than match
00:07 +177: /home/ubuntu/ss-mm-e02r15/test/features/practice/domain/scoring_profile_test.dart: ScoringProfile validation rejects weight sums of 99 and 101
00:07 +178: /home/ubuntu/ss-mm-e02r15/test/features/practice/domain/scoring_profile_test.dart: ScoringProfile validation rejects a negative weight independently of the exact sum
00:07 +179: /home/ubuntu/ss-mm-e02r15/test/features/practice/domain/scoring_profile_test.dart: ScoringProfile validation rejects thresholds outside the closed zero to 100 range
00:07 +180: /home/ubuntu/ss-mm-e02r15/test/features/practice/domain/scoring_profile_test.dart: ScoringProfile validation aggregates independent failures in one call
00:07 +181: /home/ubuntu/ss-mm-e02r15/test/features/practice/domain/scoring_profile_test.dart: ScoringProfile value semantics compares the weight map structurally and hashes it by value
00:15 +182: /home/ubuntu/ss-mm-e02r15/test/features/practice/domain/practice_target_legacy_parity_test.dart: Practice target legacy baseline parity ten frozen scenarios match finish and every event within 1 us
00:15 +183: /home/ubuntu/ss-mm-e02r15/test/features/practice/domain/practice_target_legacy_parity_test.dart: Practice target shipped-lesson parity pins all 17 lesson IDs in the measured order
00:15 +184: /home/ubuntu/ss-mm-e02r15/test/features/practice/domain/practice_target_legacy_parity_test.dart: Practice target shipped-lesson parity all valid 50, 75 and 100 percent tempos match within 1 us
00:15 +185: /home/ubuntu/ss-mm-e02r15/test/features/practice/domain/chord_pair_stats_test.dart: ChordPair is immutable and value equal
00:15 +186: /home/ubuntu/ss-mm-e02r15/test/features/practice/domain/chord_pair_stats_test.dart: ChordPair is immutable and value equal
00:15 +187: /home/ubuntu/ss-mm-e02r15/test/features/practice/domain/chord_pair_stats_test.dart: ChordPair is immutable and value equal
00:15 +188: /home/ubuntu/ss-mm-e02r15/test/features/practice/domain/practice_target_legacy_parity_test.dart: Practice target corpus invariants whole-bar rounding is a no-op for every pinned shipped ID
00:15 +189: /home/ubuntu/ss-mm-e02r15/test/features/practice/domain/practice_target_legacy_parity_test.dart: Practice target corpus invariants whole-bar rounding is a no-op for every pinned shipped ID
00:15 +190: /home/ubuntu/ss-mm-e02r15/test/features/practice/domain/practice_target_legacy_parity_test.dart: Practice target corpus invariants whole-bar rounding is a no-op for every pinned shipped ID
00:15 +191: /home/ubuntu/ss-mm-e02r15/test/features/practice/domain/practice_target_legacy_parity_test.dart: Practice target corpus invariants eventless Analyze import keeps one positive 4/4 bar
00:16 +192: /home/ubuntu/ss-mm-e02r15/test/features/practice/domain/practice_observation_test.dart: PracticeObservation validation accepts closed confidence boundaries for both observation types
00:16 +193: /home/ubuntu/ss-mm-e02r15/test/features/practice/domain/practice_observation_test.dart: PracticeObservation validation rejects a negative timestamp
00:16 +194: /home/ubuntu/ss-mm-e02r15/test/features/practice/domain/practice_observation_test.dart: PracticeObservation validation rejects a negative strum sequence
00:16 +195: /home/ubuntu/ss-mm-e02r15/test/features/practice/domain/practice_observation_test.dart: PracticeObservation validation reports non-finite confidence without a duplicate range failure
00:16 +196: /home/ubuntu/ss-mm-e02r15/test/features/practice/domain/practice_observation_test.dart: PracticeObservation validation rejects finite confidence outside zero through one
00:16 +197: /home/ubuntu/ss-mm-e02r15/test/features/practice/domain/practice_observation_test.dart: PracticeObservation validation uses the canonical chord-label contract including null
00:16 +198: /home/ubuntu/ss-mm-e02r15/test/features/practice/domain/practice_observation_test.dart: PracticeObservation value semantics compares each concrete subtype structurally
00:16 +199: /home/ubuntu/ss-mm-e02r15/test/features/practice/domain/practice_target_compiler_test.dart: PracticeTargetCompiler timeline structure rounds a partial 4/4 definition up to a complete final bar
00:16 +200: /home/ubuntu/ss-mm-e02r15/test/features/practice/domain/practice_target_compiler_test.dart: PracticeTargetCompiler timeline structure uses three quarter beats per 3/4 count-in and bar step
00:16 +201: /home/ubuntu/ss-mm-e02r15/test/features/practice/domain/practice_target_compiler_test.dart: PracticeTargetCompiler timeline structure pins two count-in bars and repeated-pass bar boundaries
00:16 +202: /home/ubuntu/ss-mm-e02r15/test/features/practice/domain/practice_target_compiler_test.dart: PracticeTargetCompiler timeline structure gives a downbeat event and its bar boundary the same time at 90 BPM
00:16 +203: /home/ubuntu/ss-mm-e02r15/test/features/practice/domain/practice_target_compiler_test.dart: PracticeTargetCompiler timeline structure computes total duration from all absolute ticks at 90 BPM
00:16 +204: /home/ubuntu/ss-mm-e02r15/test/features/practice/domain/practice_target_compiler_test.dart: PracticeTargetCompiler timeline structure compiles the final in-range tick instead of dropping it
00:16 +205: /home/ubuntu/ss-mm-e02r15/test/features/practice/domain/practice_target_compiler_test.dart: PracticeTargetCompiler timeline structure uses effective tempo at 50 and 75 percent without accumulation
00:16 +206: /home/ubuntu/ss-mm-e02r15/test/features/practice/domain/practice_target_compiler_test.dart: PracticeTargetCompiler timeline structure excludes markers while preserving a one-event target
00:16 +207: /home/ubuntu/ss-mm-e02r15/test/features/practice/domain/practice_target_compiler_test.dart: PracticeTargetCompiler timeline structure projects target metadata and every scored event field
00:16 +208: /home/ubuntu/ss-mm-e02r15/test/features/practice/domain/practice_target_compiler_test.dart: PracticeTargetCompiler timeline structure a marker-only scored definition compiles without scored events
00:16 +209: /home/ubuntu/ss-mm-e02r15/test/features/practice/domain/practice_target_compiler_test.dart: PracticeTargetCompiler loops repeats every source event with absolute positions and loop indexes
00:16 +210: /home/ubuntu/ss-mm-e02r15/test/features/practice/domain/practice_target_compiler_test.dart: PracticeTargetCompiler loops selects one source bar and rebases it before repeating
00:16 +211: /home/ubuntu/ss-mm-e02r15/test/features/practice/domain/practice_target_compiler_test.dart: PracticeTargetCompiler loops accepts the rounded final partial bar as a whole-bar loop
00:16 +212: /home/ubuntu/ss-mm-e02r15/test/features/practice/domain/practice_target_compiler_test.dart: PracticeTargetCompiler loops computes barIndex from ticksPerBar for multi-bar passes
00:16 +213: /home/ubuntu/ss-mm-e02r15/test/features/practice/domain/practice_target_compiler_test.dart: PracticeTargetCompiler loops rejects invalid loop range Instance of 'PracticeLoopRange' without clamping
00:16 +214: /home/ubuntu/ss-mm-e02r15/test/features/practice/domain/practice_target_compiler_test.dart: PracticeTargetCompiler loops rejects invalid loop range Instance of 'PracticeLoopRange' without clamping
00:16 +215: /home/ubuntu/ss-mm-e02r15/test/features/practice/domain/practice_target_compiler_test.dart: PracticeTargetCompiler loops rejects invalid loop range Instance of 'PracticeLoopRange' without clamping
00:16 +216: /home/ubuntu/ss-mm-e02r15/test/features/practice/domain/practice_target_compiler_test.dart: PracticeTargetCompiler expected-chord segments matches the pinned legacy pre-roll and merges repeated labels
00:16 +217: /home/ubuntu/ss-mm-e02r15/test/features/practice/domain/practice_target_compiler_test.dart: PracticeTargetCompiler expected-chord segments uses the named 120-tick lookahead for a one-beat chord change
00:16 +218: /home/ubuntu/ss-mm-e02r15/test/features/practice/domain/practice_target_compiler_test.dart: PracticeTargetCompiler expected-chord segments returns no segments when no compiled event carries a chord
00:16 +219: /home/ubuntu/ss-mm-e02r15/test/features/practice/domain/practice_target_compiler_test.dart: PracticeTargetCompiler expected-chord segments extends one chord across the complete session timeline
00:16 +220: /home/ubuntu/ss-mm-e02r15/test/features/practice/domain/practice_target_compiler_test.dart: PracticeTargetCompiler expected-chord segments carries chord changes across a repeated loop boundary
00:16 +221: /home/ubuntu/ss-mm-e02r15/test/features/practice/domain/practice_target_compiler_test.dart: PracticeTargetCompiler validation order definition validation wins and rejects zero totalBeats
00:16 +222: /home/ubuntu/ss-mm-e02r15/test/features/practice/domain/practice_target_compiler_test.dart: PracticeTargetCompiler validation order config validation wins before definition ID mismatch
00:16 +223: /home/ubuntu/ss-mm-e02r15/test/features/practice/domain/practice_target_compiler_test.dart: PracticeTargetCompiler validation order definition ID mismatch wins before variation mismatch
00:16 +224: /home/ubuntu/ss-mm-e02r15/test/features/practice/domain/practice_target_compiler_test.dart: PracticeTargetCompiler validation order rejects a non-matching Easy variation explicitly
00:16 +225: /home/ubuntu/ss-mm-e02r15/test/features/practice/domain/practice_target_compiler_test.dart: PracticeTargetCompiler validation order variation mismatch wins before an invalid loop range
00:16 +226: /home/ubuntu/ss-mm-e02r15/test/features/practice/domain/practice_target_compiler_test.dart: PracticeTargetCompiler validation order accepts a matching non-null Easy variation ID
00:16 +227: /home/ubuntu/ss-mm-e02r15/test/features/practice/domain/practice_target_compiler_test.dart: PracticeTargetCompiler empty and deterministic outputs compiles positive-length Free Practice without target events
00:16 +228: /home/ubuntu/ss-mm-e02r15/test/features/practice/domain/practice_target_compiler_test.dart: PracticeTargetCompiler empty and deterministic outputs returns equal, hash-equal targets with nondecreasing event times
00:17 +229: /home/ubuntu/ss-mm-e02r15/test/features/practice/domain/practice_score_aggregator_test.dart: PracticeScoreAggregator A4 available-dimension weighting does not fill an unavailable chord dimension with zero
00:17 +230: /home/ubuntu/ss-mm-e02r15/test/features/practice/domain/practice_score_aggregator_test.dart: PracticeScoreAggregator A4 available-dimension weighting pins every integer overall table cell
00:17 +231: /home/ubuntu/ss-mm-e02r15/test/features/practice/domain/practice_score_aggregator_test.dart: PracticeScoreAggregator A4 available-dimension weighting free practice has no overall score
00:17 +232: /home/ubuntu/ss-mm-e02r15/test/features/practice/domain/practice_score_aggregator_test.dart: PracticeScoreAggregator A5 completion and pass gate 16 of 20 resolved and 699 overall
00:17 +233: /home/ubuntu/ss-mm-e02r15/test/features/practice/domain/practice_score_aggregator_test.dart: PracticeScoreAggregator A5 completion and pass gate 16 of 20 resolved and 700 overall
00:17 +234: /home/ubuntu/ss-mm-e02r15/test/features/practice/domain/practice_score_aggregator_test.dart: PracticeScoreAggregator A5 completion and pass gate 17 of 20 resolved and 699 overall
00:17 +235: /home/ubuntu/ss-mm-e02r15/test/features/practice/domain/practice_score_aggregator_test.dart: PracticeScoreAggregator A5 completion and pass gate 17 of 20 resolved and 700 overall
00:17 +236: /home/ubuntu/ss-mm-e02r15/test/features/practice/domain/practice_score_aggregator_test.dart: PracticeScoreAggregator A5 completion and pass gate 18 of 20 resolved and 699 overall
00:17 +237: /home/ubuntu/ss-mm-e02r15/test/features/practice/domain/practice_score_aggregator_test.dart: PracticeScoreAggregator A5 completion and pass gate 18 of 20 resolved and 700 overall
00:17 +238: /home/ubuntu/ss-mm-e02r15/test/features/practice/domain/practice_score_aggregator_test.dart: PracticeScoreAggregator A5 completion and pass gate zero resolved targets is incomplete rather than failed
00:17 +239: /home/ubuntu/ss-mm-e02r15/test/features/practice/domain/practice_score_aggregator_test.dart: PracticeScoreAggregator A5 completion and pass gate unmatched optional target is excluded from completion counters
00:17 +240: /home/ubuntu/ss-mm-e02r15/test/features/practice/domain/practice_score_aggregator_test.dart: PracticeScoreAggregator A5 completion and pass gate matched optional target is excluded from completion counters
00:17 +241: /home/ubuntu/ss-mm-e02r15/test/features/practice/domain/practice_score_aggregator_test.dart: A6 increments combo before the fifth-hit multiplier
00:17 +242: /home/ubuntu/ss-mm-e02r15/test/features/practice/domain/practice_score_aggregator_test.dart: A6 combo resets and optional isolation a wrong direction resets before the next clean hit
00:17 +243: /home/ubuntu/ss-mm-e02r15/test/features/practice/domain/practice_score_aggregator_test.dart: A6 combo resets and optional isolation a miss resets before the next clean hit
00:17 +244: /home/ubuntu/ss-mm-e02r15/test/features/practice/domain/practice_score_aggregator_test.dart: A6 combo resets and optional isolation matched down optional target neither increments nor resets combo
00:17 +245: /home/ubuntu/ss-mm-e02r15/test/features/practice/domain/practice_score_aggregator_test.dart: A6 combo resets and optional isolation matched up optional target neither increments nor resets combo
00:17 +246: /home/ubuntu/ss-mm-e02r15/test/features/practice/domain/practice_score_aggregator_test.dart: A8 every verdict and the complete attempt result are valid
00:17 +247: /home/ubuntu/ss-mm-e02r15/test/features/practice/domain/practice_verdict_test.dart: PracticeVerdict validation accepts matched and unmatched consistent verdicts at score bounds
00:17 +248: /home/ubuntu/ss-mm-e02r15/test/features/practice/domain/practice_verdict_test.dart: PracticeVerdict validation reports an empty target event ID
00:17 +249: /home/ubuntu/ss-mm-e02r15/test/features/practice/domain/practice_verdict_test.dart: PracticeVerdict validation reports non-finite event score without a duplicate range failure
00:17 +250: /home/ubuntu/ss-mm-e02r15/test/features/practice/domain/practice_verdict_test.dart: PracticeVerdict validation rejects finite event scores outside zero through one
00:17 +251: /home/ubuntu/ss-mm-e02r15/test/features/practice/domain/practice_verdict_test.dart: PracticeVerdict validation rejects unmatched verdicts with observed time or matched grades
00:17 +252: /home/ubuntu/ss-mm-e02r15/test/features/practice/domain/practice_verdict_test.dart: PracticeVerdict validation accepts and pins all five canonical coaching codes
00:17 +253: /home/ubuntu/ss-mm-e02r15/test/features/practice/domain/practice_verdict_test.dart: PracticeVerdict validation rejects an unknown coaching code
00:17 +254: /home/ubuntu/ss-mm-e02r15/test/features/practice/domain/practice_verdict_test.dart: PracticeVerdict value semantics compares all scalar, enum, and nullable fields
00:18 +255: /home/ubuntu/ss-mm-e02r15/test/features/practice/domain/practice_event_matcher_parity_test.dart: PracticeEventMatcher legacy LessonScorer parity pins the complete 16 lesson catalog plus first-win
00:18 +256: /home/ubuntu/ss-mm-e02r15/test/features/practice/domain/practice_event_matcher_parity_test.dart: PracticeEventMatcher legacy LessonScorer parity keeps every compiled event within 0.5 us of legacy time
A1b measuredEvents=348 maximumTimebaseDifferenceUs=0.489795919508 cell=anthem-drive[23]
00:18 +257: /home/ubuntu/ss-mm-e02r15/test/features/practice/domain/practice_event_matcher_parity_test.dart: PracticeEventMatcher legacy LessonScorer parity pins the first-strums compiled eligibility divergence
00:18 +258: /home/ubuntu/ss-mm-e02r15/test/features/practice/domain/practice_event_matcher_parity_test.dart: PracticeEventMatcher legacy LessonScorer parity pins the anthem-drive [5, 6] compiled midpoint divergence
00:18 +259: /home/ubuntu/ss-mm-e02r15/test/features/practice/domain/practice_event_matcher_parity_test.dart: PracticeEventMatcher legacy LessonScorer parity matches every target exactly across all 51 latency scenarios
A1 parity scenarios=51 maximumDifferenceUs=0 excludedObservations=0
00:18 +260: /home/ubuntu/ss-mm-e02r15/test/features/practice/domain/practice_event_matcher_test.dart: PracticeEventMatcher eligibility and close boundaries pins all six cells around the 280 ms boundary
00:18 +261: /home/ubuntu/ss-mm-e02r15/test/features/practice/domain/practice_event_matcher_test.dart: PracticeEventMatcher eligibility and close boundaries exact boundary stays open and eligible after advance
00:18 +262: /home/ubuntu/ss-mm-e02r15/test/features/practice/domain/practice_event_matcher_test.dart: PracticeEventMatcher latency correction pins matching and closing for 0, 40 and 300 ms latency
00:18 +263: /home/ubuntu/ss-mm-e02r15/test/features/practice/domain/practice_event_matcher_test.dart: PracticeEventMatcher tie breaking midpoint and neighboring microseconds choose the pinned target
00:18 +264: /home/ubuntu/ss-mm-e02r15/test/features/practice/domain/practice_event_matcher_test.dart: PracticeEventMatcher tie breaking equal-time targets choose the smaller list index
00:18 +265: /home/ubuntu/ss-mm-e02r15/test/features/practice/domain/practice_event_matcher_test.dart: PracticeEventMatcher one-to-one resolution a wrong direction consumes the target before a correct retry
00:18 +266: /home/ubuntu/ss-mm-e02r15/test/features/practice/domain/practice_event_matcher_test.dart: PracticeEventMatcher one-to-one resolution an out-of-window extra leaves every target resolution unchanged
00:18 +267: /home/ubuntu/ss-mm-e02r15/test/features/practice/domain/practice_event_matcher_test.dart: PracticeEventMatcher one-to-one resolution one observation resolves at most one of two eligible targets
00:18 +268: /home/ubuntu/ss-mm-e02r15/test/features/practice/domain/practice_event_matcher_test.dart: PracticeEventMatcher one-to-one resolution a restarted gateway sequence can match a later target
00:18 +269: /home/ubuntu/ss-mm-e02r15/test/features/practice/domain/practice_event_matcher_test.dart: PracticeEventMatcher one-to-one resolution resolved count is monotonic and terminal results never reopen
00:18 +270: /home/ubuntu/ss-mm-e02r15/test/features/practice/domain/practice_event_matcher_test.dart: PracticeEventMatcher one-to-one resolution finalize separates required misses from unmatched optional targets
00:19 +271: /home/ubuntu/ss-mm-e02r15/test/features/practice/domain/practice_event_matcher_test.dart: PracticeEventMatcher one-to-one resolution an optional target remains matchable before its window closes
00:19 +272: /home/ubuntu/ss-mm-e02r15/test/features/practice/domain/practice_event_matcher_test.dart: PracticeEventMatcher one-to-one resolution finalize is idempotent
00:19 +273: /home/ubuntu/ss-mm-e02r15/test/features/practice/domain/practice_event_matcher_test.dart: PracticeEventMatcher one-to-one resolution signed offsets keep early negative and late positive
00:19 +274: /home/ubuntu/ss-mm-e02r15/test/features/practice/domain/practice_event_matcher_test.dart: PracticeEventMatcher one-to-one resolution an empty target is safe to match, advance, and finalize
00:19 +275: /home/ubuntu/ss-mm-e02r15/test/features/practice/domain/practice_event_matcher_test.dart: PracticeEventMatchResult value semantics separate matchers produce equal results and hash codes
00:19 +276: /home/ubuntu/ss-mm-e02r15/test/features/practice/domain/practice_event_matcher_test.dart: PracticeEventMatchResult value semantics targetIndex alone contributes to equality
00:19 +277: /home/ubuntu/ss-mm-e02r15/test/features/practice/domain/practice_event_matcher_test.dart: PracticeEventMatchResult value semantics target alone contributes to equality
00:19 +278: /home/ubuntu/ss-mm-e02r15/test/features/practice/domain/practice_event_matcher_test.dart: PracticeEventMatchResult value semantics resolution alone contributes to equality
00:19 +279: /home/ubuntu/ss-mm-e02r15/test/features/practice/domain/practice_event_matcher_test.dart: PracticeEventMatchResult value semantics matched observation sequence alone contributes to equality
00:19 +280: /home/ubuntu/ss-mm-e02r15/test/features/practice/domain/practice_event_matcher_test.dart: PracticeEventMatchResult value semantics observedAt and timingOffset together contribute to equality
00:19 +281: /home/ubuntu/ss-mm-e02r15/test/features/practice/domain/practice_event_matcher_test.dart: PracticeEventMatchResult value semantics results rejects mutation
00:19 +282: /home/ubuntu/ss-mm-e02r15/test/features/practice/domain/practice_event_matcher_test.dart: PracticeEventMatcher measured scaling 20k targets and 1k strums stay below the cursor threshold
A6 cursor examined=43000 threshold=1344000
00:19 +283: /home/ubuntu/ss-mm-e02r15/test/features/practice/domain/practice_event_matcher_test.dart: PracticeEventMatcher measured scaling 100k extras do not grow retained records beyond four targets
A6 memory retained=4 threshold=4
00:20 +284: /home/ubuntu/ss-mm-e02r15/test/features/practice/domain/practice_direction_scorer_test.dart: PracticeMetricReasonCode pins the complete stable code set
00:20 +285: /home/ubuntu/ss-mm-e02r15/test/features/practice/domain/practice_direction_scorer_test.dart: PracticeDirectionScorer A2 matrix matched equal direction is correct and worth 1000 per mille
00:20 +286: /home/ubuntu/ss-mm-e02r15/test/features/practice/domain/practice_direction_scorer_test.dart: PracticeDirectionScorer A2 matrix matched different direction is wrong and worth zero
00:20 +287: /home/ubuntu/ss-mm-e02r15/test/features/practice/domain/practice_direction_scorer_test.dart: PracticeDirectionScorer A2 matrix unmatched directional target is wrong when signal existed
00:20 +288: /home/ubuntu/ss-mm-e02r15/test/features/practice/domain/practice_direction_scorer_test.dart: PracticeDirectionScorer A2 matrix target without direction is not applicable when matched
00:20 +289: /home/ubuntu/ss-mm-e02r15/test/features/practice/domain/practice_direction_scorer_test.dart: PracticeDirectionScorer A2 matrix target without direction is not applicable when unmatched
00:20 +290: /home/ubuntu/ss-mm-e02r15/test/features/practice/domain/practice_direction_scorer_test.dart: PracticeDirectionScorer A2 matrix directional targets with zero strum signal are insufficient data
00:20 +291: /home/ubuntu/ss-mm-e02r15/test/features/practice/domain/practice_direction_scorer_test.dart: PracticeDirectionScorer input and aggregation fails fast when a matched sequence has no observation mapping
00:20 +292: /home/ubuntu/ss-mm-e02r15/test/features/practice/domain/practice_direction_scorer_test.dart: PracticeDirectionScorer input and aggregation uses integer accumulation and one truncating division
00:20 +293: /home/ubuntu/ss-mm-e02r15/test/features/practice/domain/practice_direction_scorer_test.dart: PracticeDirectionScorer input and aggregation open unmatched optional direction target does not dilute the metric
00:20 +294: /home/ubuntu/ss-mm-e02r15/test/features/practice/domain/practice_direction_scorer_test.dart: PracticeDirectionScorer input and aggregation finalized unmatched optional direction target does not dilute the metric
00:20 +295: /home/ubuntu/ss-mm-e02r15/test/features/practice/domain/practice_direction_scorer_test.dart: PracticeDirectionScorer input and aggregation target-index pairing supports restarted observation sequences
00:20 +296: /home/ubuntu/ss-mm-e02r15/test/features/practice/domain/practice_direction_scorer_test.dart: PracticeDirectionScorer input and aggregation fails fast when a target mapping carries the wrong sequence
00:20 +297: /home/ubuntu/ss-mm-e02r15/test/features/practice/domain/practice_direction_scorer_test.dart: PracticeDirectionScorer input and aggregation the event-score view rejects mutation
00:20 +298: /home/ubuntu/ss-mm-e02r15/test/features/practice/domain/practice_scorer_legacy_parity_test.dart: Practice scorer legacy LessonScorer parity pins the complete 16 lesson catalog plus first-win
00:20 +299: /home/ubuntu/ss-mm-e02r15/test/features/practice/domain/practice_scorer_legacy_parity_test.dart: Practice scorer legacy LessonScorer parity measures the compiled timebase guard at at most 0.5 us
A7b measuredEvents=348 maximumTimebaseDifferenceUs=0.489795919508 cell=anthem-drive[23]
00:20 +300: /home/ubuntu/ss-mm-e02r15/test/features/practice/domain/practice_scorer_legacy_parity_test.dart: Practice scorer legacy LessonScorer parity matches score, combo, counters and direction across 51 scenarios
A7 parity scenarios=51 excludedGuardBandEvents=0
00:21 +301: /home/ubuntu/ss-mm-e02r15/test/features/practice/domain/practice_scorer_legacy_parity_test.dart: Practice scorer legacy LessonScorer parity pins 18 representative extrema divergence cells
A7c representativeDivergenceCells=18
00:21 +302: /home/ubuntu/ss-mm-e02r15/test/features/practice/domain/practice_scorer_legacy_parity_test.dart: Practice scorer legacy LessonScorer parity discovers and pins every actual boundary divergence cell
A7c exhaustiveDivergenceCells=3213 fingerprint=375672841
00:21 +303: /home/ubuntu/ss-mm-e02r15/test/features/practice/domain/practice_session_state_test.dart: PracticeSessionState initial state is idle and empty
00:21 +304: /home/ubuntu/ss-mm-e02r15/test/features/practice/domain/practice_session_state_test.dart: PracticeSessionState value equality: same fields → equal
00:21 +305: /home/ubuntu/ss-mm-e02r15/test/features/practice/domain/practice_session_state_test.dart: PracticeSessionState value equality: any field change → not equal
00:21 +306: /home/ubuntu/ss-mm-e02r15/test/features/practice/domain/practice_session_state_test.dart: PracticeSessionState copyWith: explicit overrides win; cleared fields go to null
00:21 +307: /home/ubuntu/ss-mm-e02r15/test/features/practice/domain/practice_session_state_test.dart: PracticeSessionState timelinePosition: formula holds for all five anchor combinations
00:21 +308: /home/ubuntu/ss-mm-e02r15/test/features/practice/domain/practice_session_state_test.dart: PracticeSessionState isActive: true for countIn/running/paused/finishing only
00:21 +309: /home/ubuntu/ss-mm-e02r15/test/features/practice/domain/practice_session_state_test.dart: allowedTransitions (SDD §11.2 verbatim) idle → preparing
00:21 +310: /home/ubuntu/ss-mm-e02r15/test/features/practice/domain/practice_session_state_test.dart: allowedTransitions (SDD §11.2 verbatim) preparing → permissionRequired | ready | failed
00:21 +311: /home/ubuntu/ss-mm-e02r15/test/features/practice/domain/practice_session_state_test.dart: allowedTransitions (SDD §11.2 verbatim) permissionRequired → preparing | cancelled
00:21 +312: /home/ubuntu/ss-mm-e02r15/test/features/practice/domain/practice_session_state_test.dart: allowedTransitions (SDD §11.2 verbatim) ready → countIn | cancelled
00:21 +313: /home/ubuntu/ss-mm-e02r15/test/features/practice/domain/practice_session_state_test.dart: allowedTransitions (SDD §11.2 verbatim) countIn → running | paused | cancelled | failed
00:21 +314: /home/ubuntu/ss-mm-e02r15/test/features/practice/domain/practice_session_state_test.dart: allowedTransitions (SDD §11.2 verbatim) running → paused | finishing | cancelled | failed
00:21 +315: /home/ubuntu/ss-mm-e02r15/test/features/practice/domain/practice_session_state_test.dart: allowedTransitions (SDD §11.2 verbatim) paused → countIn | running | finishing | cancelled
00:21 +316: /home/ubuntu/ss-mm-e02r15/test/features/practice/domain/practice_session_state_test.dart: allowedTransitions (SDD §11.2 verbatim) finishing → completed | failed
00:21 +317: /home/ubuntu/ss-mm-e02r15/test/features/practice/domain/practice_session_state_test.dart: allowedTransitions (SDD §11.2 verbatim) completed → ready | idle
00:21 +318: /home/ubuntu/ss-mm-e02r15/test/features/practice/domain/practice_session_state_test.dart: allowedTransitions (SDD §11.2 verbatim) cancelled → ready | idle
00:21 +319: /home/ubuntu/ss-mm-e02r15/test/features/practice/domain/practice_session_state_test.dart: allowedTransitions (SDD §11.2 verbatim) failed → preparing | idle
00:21 +320: /home/ubuntu/ss-mm-e02r15/test/features/practice/domain/practice_session_state_test.dart: allowedTransitions (SDD §11.2 verbatim) every status has a transition entry
00:22 +321: /home/ubuntu/ss-mm-e02r15/test/features/practice/presentation/practice_session_lifecycle_test.dart: A6 — app-lifecycle forward matrix countIn + background → exactly 1 PausePractice(interruption)
00:23 +322: /home/ubuntu/ss-mm-e02r15/test/features/practice/presentation/practice_session_lifecycle_test.dart: A6 — app-lifecycle forward matrix countIn + background → exactly 1 PausePractice(interruption)
00:23 +323: /home/ubuntu/ss-mm-e02r15/test/features/practice/presentation/practice_session_lifecycle_test.dart: A6 — app-lifecycle forward matrix countIn + background → exactly 1 PausePractice(interruption)
00:23 +324: /home/ubuntu/ss-mm-e02r15/test/features/practice/presentation/practice_session_lifecycle_test.dart: A6 — app-lifecycle forward matrix countIn + background → exactly 1 PausePractice(interruption)
00:23 +325: /home/ubuntu/ss-mm-e02r15/test/features/practice/presentation/practice_session_lifecycle_test.dart: A6 — app-lifecycle forward matrix countIn + background → exactly 1 PausePractice(interruption)
00:23 +326: /home/ubuntu/ss-mm-e02r15/test/features/practice/presentation/practice_session_lifecycle_test.dart: A6 — app-lifecycle forward matrix countIn + background → exactly 1 PausePractice(interruption)
00:24 +327: /home/ubuntu/ss-mm-e02r15/test/features/practice/presentation/practice_highway_test.dart: A2 — rest and same-direction neighbours are distinct markers two consecutive down strokes build two markers
00:24 +328: /home/ubuntu/ss-mm-e02r15/test/features/practice/presentation/practice_highway_test.dart: A2 — rest and same-direction neighbours are distinct markers two consecutive down strokes build two markers
00:24 +329: /home/ubuntu/ss-mm-e02r15/test/features/practice/presentation/practice_highway_test.dart: A2 — rest and same-direction neighbours are distinct markers two consecutive down strokes build two markers
00:24 +330: /home/ubuntu/ss-mm-e02r15/test/features/practice/presentation/practice_highway_test.dart: A2 — rest and same-direction neighbours are distinct markers two consecutive down strokes build two markers
00:24 +331: /home/ubuntu/ss-mm-e02r15/test/features/practice/presentation/practice_highway_test.dart: A2 — rest and same-direction neighbours are distinct markers two consecutive down strokes build two markers
00:24 +332: /home/ubuntu/ss-mm-e02r15/test/features/practice/presentation/practice_highway_test.dart: A2 — rest and same-direction neighbours are distinct markers two consecutive down strokes build two markers
00:24 +333: /home/ubuntu/ss-mm-e02r15/test/features/practice/presentation/practice_highway_test.dart: A2 — rest and same-direction neighbours are distinct markers two consecutive down strokes build two markers
00:24 +334: /home/ubuntu/ss-mm-e02r15/test/features/practice/presentation/practice_session_lifecycle_test.dart: A7 — leak guards five mount/unmount cycles → 0 lingering listeners
00:24 +335: /home/ubuntu/ss-mm-e02r15/test/features/practice/presentation/practice_session_lifecycle_test.dart: A7 — leak guards five mount/unmount cycles → 0 lingering listeners
00:24 +336: /home/ubuntu/ss-mm-e02r15/test/features/practice/presentation/practice_session_lifecycle_test.dart: A7 — leak guards five mount/unmount cycles → 0 lingering listeners
00:24 +337: /home/ubuntu/ss-mm-e02r15/test/features/practice/presentation/practice_session_lifecycle_test.dart: A7 — leak guards five mount/unmount cycles → 0 lingering listeners
00:24 +338: /home/ubuntu/ss-mm-e02r15/test/features/practice/presentation/practice_session_lifecycle_test.dart: A7 — leak guards five mount/unmount cycles → 0 lingering listeners
00:24 +339: /home/ubuntu/ss-mm-e02r15/test/features/practice/presentation/practice_session_lifecycle_test.dart: A7 — leak guards five mount/unmount cycles → 0 lingering listeners
00:24 +340: /home/ubuntu/ss-mm-e02r15/test/features/practice/presentation/practice_session_lifecycle_test.dart: A7 — leak guards five mount/unmount cycles → 0 lingering listeners
00:24 +341: /home/ubuntu/ss-mm-e02r15/test/features/practice/presentation/practice_session_lifecycle_test.dart: A7 — leak guards five mount/unmount cycles → 0 lingering listeners
00:24 +342: /home/ubuntu/ss-mm-e02r15/test/features/practice/presentation/practice_session_lifecycle_test.dart: A7 — leak guards five mount/unmount cycles → 0 lingering listeners
00:24 +343: /home/ubuntu/ss-mm-e02r15/test/features/practice/presentation/practice_session_lifecycle_test.dart: A7 — leak guards five mount/unmount cycles → 0 lingering listeners
00:24 +344: /home/ubuntu/ss-mm-e02r15/test/features/practice/presentation/practice_session_lifecycle_test.dart: A8 — a11y / i18n / layout controls have 48×48 dp hit area and one semantics node each
00:25 +345: /home/ubuntu/ss-mm-e02r15/test/features/practice/presentation/practice_session_lifecycle_test.dart: A8 — a11y / i18n / layout countIn shows the remaining-beats number, even with reduced motion
00:25 +346: /home/ubuntu/ss-mm-e02r15/test/features/practice/presentation/practice_session_lifecycle_test.dart: A8 — a11y / i18n / layout English + Hungarian locales both render without throwing
00:25 +347: /home/ubuntu/ss-mm-e02r15/test/features/practice/presentation/practice_session_lifecycle_test.dart: A8 — a11y / i18n / layout no raw status enum name leaks to the user-facing surface
00:25 +348: /home/ubuntu/ss-mm-e02r15/test/features/practice/presentation/practice_highway_import_guard_test.dart: all six files exist on disk
00:25 +349: /home/ubuntu/ss-mm-e02r15/test/features/practice/presentation/practice_highway_import_guard_test.dart: no Learn-internal symbols are referenced
00:25 +350: /home/ubuntu/ss-mm-e02r15/test/features/practice/presentation/practice_highway_import_guard_test.dart: no Practice domain service/ import
00:25 +351: /home/ubuntu/ss-mm-e02r15/test/features/practice/presentation/practice_highway_import_guard_test.dart: no scoring / matcher in the widget layer
00:26 +352: /home/ubuntu/ss-mm-e02r15/test/features/practice/presentation/practice_highway_scaling_test.dart: 2 000 events, 4 s visibility → examined ≤ 64 and built markers ≤ 64
00:26 +353: /home/ubuntu/ss-mm-e02r15/test/features/practice/presentation/practice_highway_scaling_test.dart: 2 000 events, 4 s visibility → examined ≤ 64 and built markers ≤ 64
00:27 +354: /home/ubuntu/ss-mm-e02r15/test/features/practice/presentation/practice_hub_screen_test.dart: A1: hub renders a card per catalog definition with displayTitle
00:28 +355: /home/ubuntu/ss-mm-e02r15/test/features/practice/presentation/practice_highway_scaling_test.dart: playhead advances 100 steps → cumulative examined ≤ 100 × 64 and the marker count stays bounded each step
00:29 +356: /home/ubuntu/ss-mm-e02r15/test/features/practice/presentation/practice_highway_scaling_test.dart: playhead advances 100 steps → cumulative examined ≤ 100 × 64 and the marker count stays bounded each step
00:29 +357: /home/ubuntu/ss-mm-e02r15/test/features/practice/presentation/practice_highway_scaling_test.dart: playhead advances 100 steps → cumulative examined ≤ 100 × 64 and the marker count stays bounded each step
00:29 +358: /home/ubuntu/ss-mm-e02r15/test/features/practice/presentation/practice_highway_scaling_test.dart: playhead advances 100 steps → cumulative examined ≤ 100 × 64 and the marker count stays bounded each step
00:29 +359: /home/ubuntu/ss-mm-e02r15/test/features/practice/presentation/practice_highway_scaling_test.dart: playhead advances 100 steps → cumulative examined ≤ 100 × 64 and the marker count stays bounded each step
00:30 +360: /home/ubuntu/ss-mm-e02r15/test/features/practice/presentation/practice_highway_scaling_test.dart: playhead advances 100 steps → cumulative examined ≤ 100 × 64 and the marker count stays bounded each step
00:30 +361: /home/ubuntu/ss-mm-e02r15/test/features/practice/presentation/practice_highway_scaling_test.dart: playhead advances 100 steps → cumulative examined ≤ 100 × 64 and the marker count stays bounded each step
00:30 +362: /home/ubuntu/ss-mm-e02r15/test/features/practice/presentation/practice_highway_scaling_test.dart: playhead advances 100 steps → cumulative examined ≤ 100 × 64 and the marker count stays bounded each step
00:30 +363: /home/ubuntu/ss-mm-e02r15/test/features/practice/presentation/practice_highway_scaling_test.dart: playhead advances 100 steps → cumulative examined ≤ 100 × 64 and the marker count stays bounded each step
00:30 +364: /home/ubuntu/ss-mm-e02r15/test/features/practice/presentation/practice_highway_scaling_test.dart: playhead advances 100 steps → cumulative examined ≤ 100 × 64 and the marker count stays bounded each step
00:30 +365: /home/ubuntu/ss-mm-e02r15/test/features/practice/presentation/practice_highway_scaling_test.dart: 2 000 events, playhead at the end → examined ≤ 64 and built markers ≤ 64
00:31 +366: /home/ubuntu/ss-mm-e02r15/test/features/practice/presentation/chord_change_view_test.dart: renders current and next chord diagrams with a11y labels
00:32 +367: /home/ubuntu/ss-mm-e02r15/test/features/practice/presentation/practice_routing_test.dart: A7: flag ON, /practice builds the Hub
00:32 +368: /home/ubuntu/ss-mm-e02r15/test/features/practice/presentation/practice_routing_test.dart: A7: flag ON, /practice builds the Hub
00:32 +369: /home/ubuntu/ss-mm-e02r15/test/features/practice/presentation/practice_routing_test.dart: A7: flag ON, /practice builds the Hub
00:32 +370: /home/ubuntu/ss-mm-e02r15/test/features/practice/presentation/practice_routing_test.dart: A7: flag ON, /practice builds the Hub
00:32 +371: /home/ubuntu/ss-mm-e02r15/test/features/practice/presentation/practice_routing_test.dart: A7: flag ON, /practice builds the Hub
00:33 +372: /home/ubuntu/ss-mm-e02r15/test/features/practice/presentation/practice_routing_test.dart: A7: flag ON, /practice builds the Hub
00:33 +373: /home/ubuntu/ss-mm-e02r15/test/features/practice/presentation/practice_routing_test.dart: A7: flag ON, /practice builds the Hub
00:33 +374: /home/ubuntu/ss-mm-e02r15/test/features/practice/presentation/practice_routing_test.dart: A7: flag ON, /practice builds the Hub
00:33 +375: /home/ubuntu/ss-mm-e02r15/test/features/practice/presentation/practice_routing_test.dart: A7: flag ON, /practice builds the Hub
00:33 +376: /home/ubuntu/ss-mm-e02r15/test/features/practice/presentation/practice_routing_test.dart: A7: flag ON, /practice builds the Hub
00:33 +377: /home/ubuntu/ss-mm-e02r15/test/features/practice/presentation/practice_routing_test.dart: A7: flag ON, /practice builds the Hub
00:33 +378: /home/ubuntu/ss-mm-e02r15/test/features/practice/presentation/practice_routing_test.dart: A7: flag ON, /practice builds the Hub
00:33 +379: /home/ubuntu/ss-mm-e02r15/test/features/practice/presentation/practice_routing_test.dart: A7: flag ON, /practice builds the Hub
00:33 +380: /home/ubuntu/ss-mm-e02r15/test/features/practice/presentation/practice_routing_test.dart: A7: flag ON, /practice builds the Hub
00:33 +381: /home/ubuntu/ss-mm-e02r15/test/features/practice/presentation/practice_routing_test.dart: A7: flag ON, /practice builds the Hub
00:34 +382: /home/ubuntu/ss-mm-e02r15/test/features/practice/presentation/practice_routing_test.dart: A7: flag ON, /practice/setup?id=<known> builds the Setup
00:34 +383: /home/ubuntu/ss-mm-e02r15/test/features/practice/presentation/practice_session_screen_test.dart: A1 — status render matrix preparing shows the progress indicator
00:35 +384: /home/ubuntu/ss-mm-e02r15/test/features/practice/presentation/practice_session_screen_test.dart: A1 — status render matrix preparing shows the progress indicator
00:35 +385: /home/ubuntu/ss-mm-e02r15/test/features/practice/presentation/practice_session_screen_test.dart: A1 — status render matrix preparing shows the progress indicator
00:35 +386: /home/ubuntu/ss-mm-e02r15/test/features/practice/presentation/practice_session_screen_test.dart: A1 — status render matrix preparing shows the progress indicator
00:35 +387: /home/ubuntu/ss-mm-e02r15/test/features/practice/presentation/practice_session_screen_test.dart: A1 — status render matrix preparing shows the progress indicator
00:35 +388: /home/ubuntu/ss-mm-e02r15/test/features/practice/presentation/practice_session_screen_test.dart: A1 — status render matrix permissionRequired shows the CORE MicPermissionBanner
00:36 +389: /home/ubuntu/ss-mm-e02r15/test/features/practice/presentation/practice_session_screen_test.dart: A1 — status render matrix ready shows Start, no count-in overlay
00:36 +390: /home/ubuntu/ss-mm-e02r15/test/features/practice/presentation/practice_session_screen_test.dart: A1 — status render matrix countIn shows the remaining beats overlay
00:36 +391: /home/ubuntu/ss-mm-e02r15/test/features/practice/presentation/practice_session_screen_test.dart: A1 — status render matrix running shows HUD with elapsed/attempt/score
00:36 +392: /home/ubuntu/ss-mm-e02r15/test/features/practice/presentation/practice_session_screen_test.dart: A1 — status render matrix paused shows the pause label and Resume
00:36 +393: /home/ubuntu/ss-mm-e02r15/test/features/practice/presentation/chord_progression_view_test.dart: current + next + upcoming-bar cells render with ChordDiagram
00:36 +394: /home/ubuntu/ss-mm-e02r15/test/features/practice/presentation/chord_progression_view_test.dart: current + next + upcoming-bar cells render with ChordDiagram
00:36 +395: /home/ubuntu/ss-mm-e02r15/test/features/practice/presentation/chord_progression_view_test.dart: current + next + upcoming-bar cells render with ChordDiagram
00:36 +396: /home/ubuntu/ss-mm-e02r15/test/features/practice/presentation/chord_progression_view_test.dart: current + next + upcoming-bar cells render with ChordDiagram
00:36 +397: /home/ubuntu/ss-mm-e02r15/test/features/practice/presentation/chord_progression_view_test.dart: current + next + upcoming-bar cells render with ChordDiagram
00:36 +398: /home/ubuntu/ss-mm-e02r15/test/features/practice/presentation/chord_progression_view_test.dart: current + next + upcoming-bar cells render with ChordDiagram
00:36 +399: /home/ubuntu/ss-mm-e02r15/test/features/practice/presentation/chord_progression_view_test.dart: current + next + upcoming-bar cells render with ChordDiagram
00:36 +400: /home/ubuntu/ss-mm-e02r15/test/features/practice/presentation/chord_progression_view_test.dart: current + next + upcoming-bar cells render with ChordDiagram
00:36 +401: /home/ubuntu/ss-mm-e02r15/test/features/practice/presentation/chord_progression_view_test.dart: current + next + upcoming-bar cells render with ChordDiagram
00:36 +402: /home/ubuntu/ss-mm-e02r15/test/features/practice/presentation/chord_progression_view_test.dart: current + next + upcoming-bar cells render with ChordDiagram
00:36 +403: /home/ubuntu/ss-mm-e02r15/test/features/practice/presentation/chord_progression_view_test.dart: current + next + upcoming-bar cells render with ChordDiagram
00:37 +404: /home/ubuntu/ss-mm-e02r15/test/features/practice/presentation/chord_progression_view_test.dart: current + next + upcoming-bar cells render with ChordDiagram
00:37 +405: /home/ubuntu/ss-mm-e02r15/test/features/practice/presentation/chord_progression_view_test.dart: current + next + upcoming-bar cells render with ChordDiagram
00:37 +406: /home/ubuntu/ss-mm-e02r15/test/features/practice/presentation/chord_progression_view_test.dart: current + next + upcoming-bar cells render with ChordDiagram
00:37 +407: /home/ubuntu/ss-mm-e02r15/test/features/practice/presentation/chord_progression_view_test.dart: current + next + upcoming-bar cells render with ChordDiagram
00:37 +408: /home/ubuntu/ss-mm-e02r15/test/features/practice/presentation/chord_progression_view_test.dart: current + next + upcoming-bar cells render with ChordDiagram
00:37 +409: /home/ubuntu/ss-mm-e02r15/test/features/practice/presentation/chord_progression_view_test.dart: current + next + upcoming-bar cells render with ChordDiagram
00:37 +410: /home/ubuntu/ss-mm-e02r15/test/features/practice/presentation/chord_progression_view_test.dart: current + next + upcoming-bar cells render with ChordDiagram
00:37 +411: /home/ubuntu/ss-mm-e02r15/test/features/practice/presentation/practice_session_screen_test.dart: Review regressions — recoverable errors leave and re-enter in the same ProviderScope shows no stale error
00:37 +412: /home/ubuntu/ss-mm-e02r15/test/features/practice/presentation/chord_progression_view_test.dart: showChordHint=false clears the chord hint (R10 / legacy parity)
00:37 +413: /home/ubuntu/ss-mm-e02r15/test/features/practice/presentation/practice_session_screen_test.dart: A4 — exit matrix preparing: no confirmation, 0 commands, screen stays
00:37 +414: /home/ubuntu/ss-mm-e02r15/test/features/practice/presentation/chord_progression_view_test.dart: four ChordOutcome values render with pairwise distinct signals
00:37 +415: /home/ubuntu/ss-mm-e02r15/test/features/practice/presentation/chord_progression_view_test.dart: four ChordOutcome values render with pairwise distinct signals
00:37 +416: /home/ubuntu/ss-mm-e02r15/test/features/practice/presentation/practice_session_screen_test.dart: A4 — exit matrix countIn: confirmation shown, confirmed → 1 CancelPractice
00:37 +417: /home/ubuntu/ss-mm-e02r15/test/features/practice/presentation/practice_session_screen_test.dart: A4 — exit matrix countIn: confirmation shown, confirmed → 1 CancelPractice
00:37 +418: /home/ubuntu/ss-mm-e02r15/test/features/practice/presentation/practice_session_screen_test.dart: A4 — exit matrix countIn: confirmation shown, confirmed → 1 CancelPractice
00:37 +419: /home/ubuntu/ss-mm-e02r15/test/features/practice/presentation/practice_session_screen_test.dart: A4 — exit matrix countIn: confirmation shown, confirmed → 1 CancelPractice
00:37 +420: /home/ubuntu/ss-mm-e02r15/test/features/practice/presentation/chord_progression_view_test.dart: chord progression view fits without overflow at Size(915.0, 412.0)
00:38 +421: /home/ubuntu/ss-mm-e02r15/test/features/practice/presentation/practice_session_screen_test.dart: A4 — exit matrix running: confirmation shown, confirmed → 1 CancelPractice
00:38 +422: /home/ubuntu/ss-mm-e02r15/test/features/practice/presentation/practice_session_screen_test.dart: A4 — exit matrix running: confirmation shown, confirmed → 1 CancelPractice
00:38 +423: /home/ubuntu/ss-mm-e02r15/test/features/practice/presentation/practice_session_screen_test.dart: A4 — exit matrix paused: confirmation shown, confirmed → 1 CancelPractice
00:38 +424: /home/ubuntu/ss-mm-e02r15/test/features/practice/presentation/practice_session_screen_test.dart: A4 — exit matrix countIn: confirmation rejected → 0 commands, screen stays
00:38 +425: /home/ubuntu/ss-mm-e02r15/test/features/practice/presentation/practice_session_screen_test.dart: A4 — exit matrix finishing: no exit possible, 0 commands
00:38 +426: /home/ubuntu/ss-mm-e02r15/test/features/practice/presentation/practice_session_screen_test.dart: A4 — exit matrix completed: no confirmation, 0 commands
00:38 +427: /home/ubuntu/ss-mm-e02r15/test/features/practice/presentation/practice_session_screen_test.dart: A4 — exit matrix cancelled: no confirmation, 0 commands
00:38 +428: /home/ubuntu/ss-mm-e02r15/test/features/practice/presentation/practice_session_screen_test.dart: A4 — exit matrix failed: no confirmation, 0 commands
00:39 +429: /home/ubuntu/ss-mm-e02r15/test/features/practice/presentation/practice_session_screen_test.dart: A4 — exit matrix two rapid Exit taps in countIn → 1 CancelPractice (M1 single-fire gate)
00:39 +430: /home/ubuntu/ss-mm-e02r15/test/features/practice/presentation/practice_session_screen_test.dart: A5 — NavigateToResult duplicate guard two NavigateToResult effects → 1 navigation call
00:39 +431: /home/ubuntu/ss-mm-e02r15/test/features/practice/presentation/practice_setup_screen_test.dart: A4 controller matrix — domain-derived limits only BPM 29 invalid, 30 valid, 300 valid, 301 invalid
00:39 +432: /home/ubuntu/ss-mm-e02r15/test/features/practice/presentation/practice_setup_screen_test.dart: A4 controller matrix — domain-derived limits only count-in bars -1 / 0 / 2 / 4 / 5 — only 0..4 are valid
00:39 +433: /home/ubuntu/ss-mm-e02r15/test/features/practice/presentation/practice_setup_screen_test.dart: A4 controller matrix — domain-derived limits only loop count 0 / 1 / 32 / 33 — only 1..32 are valid
00:39 +434: /home/ubuntu/ss-mm-e02r15/test/features/practice/presentation/practice_setup_screen_test.dart: A4 controller matrix — domain-derived limits only default config is seeded from the definition
00:39 +435: /home/ubuntu/ss-mm-e02r15/test/features/practice/presentation/practice_setup_screen_test.dart: A5 mode-specific visibility Free Practice hides the scoring profile row
00:40 +436: /home/ubuntu/ss-mm-e02r15/test/features/practice/presentation/strum_pattern_view_test.dart: renders the pattern preview with down/up/rest cells
00:40 +437: /home/ubuntu/ss-mm-e02r15/test/features/practice/presentation/strum_pattern_view_test.dart: renders the pattern preview with down/up/rest cells
00:41 +438: /home/ubuntu/ss-mm-e02r15/test/features/practice/presentation/strum_pattern_view_test.dart: renders the pattern preview with down/up/rest cells
00:41 +439: /home/ubuntu/ss-mm-e02r15/test/features/practice/presentation/strum_pattern_view_test.dart: renders the pattern preview with down/up/rest cells
00:41 +440: /home/ubuntu/ss-mm-e02r15/test/features/practice/presentation/practice_setup_screen_test.dart: A6 Start command shape Start button is disabled when config is invalid
00:41 +441: /home/ubuntu/ss-mm-e02r15/test/features/practice/presentation/practice_setup_screen_test.dart: A6 Start command shape Start button is disabled when config is invalid
00:41 +442: /home/ubuntu/ss-mm-e02r15/test/features/practice/presentation/practice_setup_screen_test.dart: A6 Start command shape Start button is disabled when config is invalid
00:41 +443: /home/ubuntu/ss-mm-e02r15/test/features/practice/presentation/strum_pattern_view_test.dart: renders without exception when verdict and metrics are null
00:41 +444: /home/ubuntu/ss-mm-e02r15/test/features/practice/presentation/practice_setup_screen_test.dart: unknown id shows the localized error state
00:41 +445: /home/ubuntu/ss-mm-e02r15/test/features/practice/presentation/practice_setup_screen_test.dart: missing id shows the localized error state
00:41 +446: /home/ubuntu/ss-mm-e02r15/test/features/practice/presentation/practice_setup_screen_test.dart: the meter readout renders the definition meter (3/4, 6/8, 4/4)
00:42 +447: /home/ubuntu/ss-mm-e02r15/test/features/practice/data/builtin_practice_catalog_test.dart: BuiltinPracticeCatalog contains exactly ten definitions in pinned ID order
00:42 +448: /home/ubuntu/ss-mm-e02r15/test/features/practice/data/builtin_practice_catalog_test.dart: BuiltinPracticeCatalog every definition validates with no failures
00:42 +449: /home/ubuntu/ss-mm-e02r15/test/features/practice/data/builtin_practice_catalog_test.dart: BuiltinPracticeCatalog definition IDs are globally unique
00:42 +450: /home/ubuntu/ss-mm-e02r15/test/features/practice/data/builtin_practice_catalog_test.dart: BuiltinPracticeCatalog all() returns the same order on repeated calls
00:42 +451: /home/ubuntu/ss-mm-e02r15/test/features/practice/data/builtin_practice_catalog_test.dart: BuiltinPracticeCatalog byId returns the pinned definition and null for unknown IDs
00:42 +452: /home/ubuntu/ss-mm-e02r15/test/features/practice/data/builtin_practice_catalog_test.dart: BuiltinPracticeCatalog byMode returns only definitions of the requested mode
00:42 +453: /home/ubuntu/ss-mm-e02r15/test/features/practice/data/builtin_practice_catalog_test.dart: BuiltinPracticeCatalog byDifficulty returns only definitions of the requested difficulty
00:42 +454: /home/ubuntu/ss-mm-e02r15/test/features/practice/data/builtin_practice_catalog_test.dart: BuiltinPracticeCatalog firstWaltz is 3/4 with twelve total beats on the quarter grid
00:42 +455: /home/ubuntu/ss-mm-e02r15/test/features/practice/data/builtin_practice_catalog_test.dart: BuiltinPracticeCatalog titleKey and descriptionKey follow the practiceCatalog regex
00:42 +456: /home/ubuntu/ss-mm-e02r15/test/features/practice/data/builtin_practice_catalog_test.dart: BuiltinPracticeCatalog free-practice template has no events and an open scoring profile
00:42 +457: /home/ubuntu/ss-mm-e02r15/test/features/practice/data/builtin_practice_catalog_test.dart: BuiltinPracticeCatalog strumPattern events carry no chord and chordChanges events do
00:42 +458: /home/ubuntu/ss-mm-e02r15/test/features/practice/data/builtin_practice_catalog_test.dart: BuiltinPracticeCatalog data layer purity source forbids ambient IO, randomness, framework, and l10n imports
00:42 +459: /home/ubuntu/ss-mm-e02r15/test/features/practice/data/builtin_practice_catalog_test.dart: BuiltinPracticeCatalog PracticeDefinition integrity event IDs are unique within every definition
00:42 +460: /home/ubuntu/ss-mm-e02r15/test/features/practice/data/builtin_practice_catalog_test.dart: BuiltinPracticeCatalog per-definition immutability events list rejects add() for every catalog definition
00:42 +461: /home/ubuntu/ss-mm-e02r15/test/features/practice/data/builtin_practice_catalog_test.dart: BuiltinPracticeCatalog per-definition immutability skillTags list rejects add() for every catalog definition
00:42 +462: /home/ubuntu/ss-mm-e02r15/test/features/practice/data/builtin_practice_catalog_test.dart: BuiltinPracticeCatalog chord-change bar grouping builtin.gToDChanges.v1 holds G for the first bar, D for the second
00:42 +463: /home/ubuntu/ss-mm-e02r15/test/features/practice/data/builtin_practice_catalog_test.dart: BuiltinPracticeCatalog chord-change bar grouping builtin.emToCChanges.v1 holds Em for the first bar, C for the second
00:42 +464: /home/ubuntu/ss-mm-e02r15/test/features/practice/data/adapters/song_practice_adapter_test.dart: practiceDefinitionFromSong — parity with toLesson() events 4/4 single-bar 8-slot pattern, 1 chord
00:42 +465: /home/ubuntu/ss-mm-e02r15/test/features/practice/data/adapters/song_practice_adapter_test.dart: practiceDefinitionFromSong — parity with toLesson() events 4/4 four-bar 8-slot pattern with up-strokes
00:42 +466: /home/ubuntu/ss-mm-e02r15/test/features/practice/data/adapters/song_practice_adapter_test.dart: practiceDefinitionFromSong — parity with toLesson() events 4/4 eight-bar full-eighth pattern
00:42 +467: /home/ubuntu/ss-mm-e02r15/test/features/practice/data/adapters/song_practice_adapter_test.dart: practiceDefinitionFromSong — parity with toLesson() events 3/4 six-slot pattern over four bars
00:42 +468: /home/ubuntu/ss-mm-e02r15/test/features/practice/data/adapters/song_practice_adapter_test.dart: practiceDefinitionFromSong — parity with toLesson() events mixed rests pattern still expands correctly
00:42 +469: /home/ubuntu/ss-mm-e02r15/test/features/practice/data/adapters/song_practice_adapter_test.dart: practiceDefinitionFromSong — parity with toLesson() events empty/whitespace name falls back to null displayTitle
00:42 +470: /home/ubuntu/ss-mm-e02r15/test/features/practice/data/adapters/song_practice_adapter_test.dart: practiceDefinitionFromSong — definition surface IDs, source, mode, profile match the ADR contract
00:42 +471: /home/ubuntu/ss-mm-e02r15/test/features/practice/data/adapters/song_practice_adapter_test.dart: practiceDefinitionFromSong — controlled failure modes rejects empty chords
00:42 +472: /home/ubuntu/ss-mm-e02r15/test/features/practice/data/adapters/song_practice_adapter_test.dart: practiceDefinitionFromSong — controlled failure modes rejects pattern length that does not fit the meter
00:42 +473: /home/ubuntu/ss-mm-e02r15/test/features/practice/data/adapters/song_practice_adapter_test.dart: practiceDefinitionFromSong — controlled failure modes rejects a pattern with only null slots
00:42 +474: /home/ubuntu/ss-mm-e02r15/test/features/practice/data/adapters/song_practice_adapter_test.dart: practiceDefinitionFromSong — controlled failure modes rejects bpm above the Tempo ceiling (400)
00:42 +475: /home/ubuntu/ss-mm-e02r15/test/features/practice/data/adapters/song_practice_adapter_test.dart: practiceDefinitionFromSong — controlled failure modes rejects bpm below the Tempo floor (10)
00:42 +476: /home/ubuntu/ss-mm-e02r15/test/features/practice/data/adapters/song_practice_adapter_test.dart: practiceDefinitionFromSong — controlled failure modes none of the failure paths throws
00:42 +477: /home/ubuntu/ss-mm-e02r15/test/features/practice/data/adapters/song_practice_adapter_test.dart: song_practice_adapter source guard forbidden to call Song.toLesson() — source-level scan
00:43 +478: /home/ubuntu/ss-mm-e02r15/test/features/practice/data/adapters/lesson_practice_adapter_test.dart: practiceDefinitionFromLesson — full parity on the shipped catalog catalog baseline: 16 curriculum + first-win
00:43 +479: /home/ubuntu/ss-mm-e02r15/test/features/practice/data/adapters/lesson_practice_adapter_test.dart: practiceDefinitionFromLesson — full parity on the shipped catalog lesson.id=first-strums matches every event slot exactly
00:43 +480: /home/ubuntu/ss-mm-e02r15/test/features/practice/data/adapters/lesson_practice_adapter_test.dart: practiceDefinitionFromLesson — full parity on the shipped catalog lesson.id=two-chord-change matches every event slot exactly
00:43 +481: /home/ubuntu/ss-mm-e02r15/test/features/practice/data/adapters/lesson_practice_adapter_test.dart: practiceDefinitionFromLesson — full parity on the shipped catalog lesson.id=eighth-drive matches every event slot exactly
00:43 +482: /home/ubuntu/ss-mm-e02r15/test/features/practice/data/adapters/lesson_practice_adapter_test.dart: practiceDefinitionFromLesson — full parity on the shipped catalog lesson.id=fifties-doo-wop matches every event slot exactly
00:43 +483: /home/ubuntu/ss-mm-e02r15/test/features/practice/data/adapters/lesson_practice_adapter_test.dart: practiceDefinitionFromLesson — full parity on the shipped catalog lesson.id=two-finger-frame matches every event slot exactly
00:43 +484: /home/ubuntu/ss-mm-e02r15/test/features/practice/data/adapters/lesson_practice_adapter_test.dart: practiceDefinitionFromLesson — full parity on the shipped catalog lesson.id=first-waltz matches every event slot exactly
00:43 +485: /home/ubuntu/ss-mm-e02r15/test/features/practice/data/adapters/lesson_practice_adapter_test.dart: practiceDefinitionFromLesson — full parity on the shipped catalog lesson.id=down-up-groove matches every event slot exactly
00:43 +486: /home/ubuntu/ss-mm-e02r15/test/features/practice/data/adapters/lesson_practice_adapter_test.dart: practiceDefinitionFromLesson — full parity on the shipped catalog lesson.id=folk-pattern matches every event slot exactly
00:43 +487: /home/ubuntu/ss-mm-e02r15/test/features/practice/data/adapters/lesson_practice_adapter_test.dart: practiceDefinitionFromLesson — full parity on the shipped catalog lesson.id=barre-groove matches every event slot exactly
00:43 +488: /home/ubuntu/ss-mm-e02r15/test/features/practice/data/adapters/lesson_practice_adapter_test.dart: practiceDefinitionFromLesson — full parity on the shipped catalog lesson.id=anthem-drive matches every event slot exactly
00:43 +489: /home/ubuntu/ss-mm-e02r15/test/features/practice/data/adapters/lesson_practice_adapter_test.dart: practiceDefinitionFromLesson — full parity on the shipped catalog lesson.id=rising-minor matches every event slot exactly
00:43 +490: /home/ubuntu/ss-mm-e02r15/test/features/practice/data/adapters/lesson_practice_adapter_test.dart: practiceDefinitionFromLesson — full parity on the shipped catalog lesson.id=waltz-time matches every event slot exactly
00:43 +491: /home/ubuntu/ss-mm-e02r15/test/features/practice/data/adapters/lesson_practice_adapter_test.dart: practiceDefinitionFromLesson — full parity on the shipped catalog lesson.id=reggae-skank matches every event slot exactly
00:43 +492: /home/ubuntu/ss-mm-e02r15/test/features/practice/data/adapters/lesson_practice_adapter_test.dart: practiceDefinitionFromLesson — full parity on the shipped catalog lesson.id=funk-chop matches every event slot exactly
00:43 +493: /home/ubuntu/ss-mm-e02r15/test/features/practice/data/adapters/lesson_practice_adapter_test.dart: practiceDefinitionFromLesson — full parity on the shipped catalog lesson.id=blues-shuffle matches every event slot exactly
00:43 +494: /home/ubuntu/ss-mm-e02r15/test/features/practice/data/adapters/lesson_practice_adapter_test.dart: practiceDefinitionFromLesson — full parity on the shipped catalog lesson.id=push-and-pull matches every event slot exactly
00:43 +495: /home/ubuntu/ss-mm-e02r15/test/features/practice/data/adapters/lesson_practice_adapter_test.dart: practiceDefinitionFromLesson — full parity on the shipped catalog lesson.id=first-win matches every event slot exactly
00:43 +496: /home/ubuntu/ss-mm-e02r15/test/features/practice/data/adapters/lesson_practice_adapter_test.dart: practiceDefinitionFromLesson — Easy parity lesson.id=first-strums easy variant mirrors simplified events
00:43 +497: /home/ubuntu/ss-mm-e02r15/test/features/practice/data/adapters/lesson_practice_adapter_test.dart: practiceDefinitionFromLesson — Easy parity lesson.id=two-chord-change easy variant mirrors simplified events
00:43 +498: /home/ubuntu/ss-mm-e02r15/test/features/practice/data/adapters/lesson_practice_adapter_test.dart: practiceDefinitionFromLesson — Easy parity lesson.id=eighth-drive easy variant mirrors simplified events
00:43 +499: /home/ubuntu/ss-mm-e02r15/test/features/practice/data/adapters/lesson_practice_adapter_test.dart: practiceDefinitionFromLesson — Easy parity lesson.id=fifties-doo-wop easy variant mirrors simplified events
00:43 +500: /home/ubuntu/ss-mm-e02r15/test/features/practice/data/adapters/lesson_practice_adapter_test.dart: practiceDefinitionFromLesson — Easy parity lesson.id=two-finger-frame easy variant mirrors simplified events
00:43 +501: /home/ubuntu/ss-mm-e02r15/test/features/practice/data/adapters/lesson_practice_adapter_test.dart: practiceDefinitionFromLesson — Easy parity lesson.id=first-waltz easy variant mirrors simplified events
00:43 +502: /home/ubuntu/ss-mm-e02r15/test/features/practice/data/adapters/lesson_practice_adapter_test.dart: practiceDefinitionFromLesson — Easy parity lesson.id=down-up-groove easy variant mirrors simplified events
00:43 +503: /home/ubuntu/ss-mm-e02r15/test/features/practice/data/adapters/lesson_practice_adapter_test.dart: practiceDefinitionFromLesson — Easy parity lesson.id=folk-pattern easy variant mirrors simplified events
00:43 +504: /home/ubuntu/ss-mm-e02r15/test/features/practice/data/adapters/lesson_practice_adapter_test.dart: practiceDefinitionFromLesson — Easy parity lesson.id=barre-groove easy variant mirrors simplified events
00:43 +505: /home/ubuntu/ss-mm-e02r15/test/features/practice/data/adapters/lesson_practice_adapter_test.dart: practiceDefinitionFromLesson — Easy parity lesson.id=anthem-drive easy variant mirrors simplified events
00:43 +506: /home/ubuntu/ss-mm-e02r15/test/features/practice/data/adapters/lesson_practice_adapter_test.dart: practiceDefinitionFromLesson — Easy parity lesson.id=rising-minor easy variant mirrors simplified events
00:43 +507: /home/ubuntu/ss-mm-e02r15/test/features/practice/data/adapters/lesson_practice_adapter_test.dart: practiceDefinitionFromLesson — Easy parity lesson.id=waltz-time easy variant mirrors simplified events
00:43 +508: /home/ubuntu/ss-mm-e02r15/test/features/practice/data/adapters/lesson_practice_adapter_test.dart: practiceDefinitionFromLesson — Easy parity lesson.id=reggae-skank easy variant mirrors simplified events
00:43 +509: /home/ubuntu/ss-mm-e02r15/test/features/practice/data/adapters/lesson_practice_adapter_test.dart: practiceDefinitionFromLesson — Easy parity lesson.id=funk-chop easy variant mirrors simplified events
00:43 +510: /home/ubuntu/ss-mm-e02r15/test/features/practice/data/adapters/lesson_practice_adapter_test.dart: practiceDefinitionFromLesson — Easy parity lesson.id=blues-shuffle easy variant mirrors simplified events
00:43 +511: /home/ubuntu/ss-mm-e02r15/test/features/practice/data/adapters/lesson_practice_adapter_test.dart: practiceDefinitionFromLesson — Easy parity lesson.id=push-and-pull easy variant mirrors simplified events
00:43 +512: /home/ubuntu/ss-mm-e02r15/test/features/practice/data/adapters/lesson_practice_adapter_test.dart: practiceDefinitionFromLesson — Easy parity lesson.id=first-win easy variant mirrors simplified events
00:43 +513: /home/ubuntu/ss-mm-e02r15/test/features/practice/data/adapters/lesson_practice_adapter_test.dart: practiceDefinitionFromLesson — displayTitle + chord consistency chord labels match legacyPracticeChordLabel for every event
00:43 +514: /home/ubuntu/ss-mm-e02r15/test/features/practice/data/adapters/lesson_practice_adapter_test.dart: practiceDefinitionFromLesson — displayTitle + chord consistency twoFingerFrame chords normalize to Em / C in order
00:43 +515: /home/ubuntu/ss-mm-e02r15/test/features/practice/data/adapters/lesson_practice_adapter_test.dart: practiceDefinitionFromLesson — displayTitle + chord consistency bluesShuffle chords normalize to A / D
00:43 +516: /home/ubuntu/ss-mm-e02r15/test/features/practice/data/adapters/lesson_practice_adapter_test.dart: practiceDefinitionFromLesson — displayTitle + chord consistency every chord in every lesson definition is canonical
00:43 +517: /home/ubuntu/ss-mm-e02r15/test/features/practice/data/adapters/lesson_practice_adapter_test.dart: practiceDefinitionFromLesson — displayTitle + chord consistency displayTitle carries the lesson name and falls back to null
00:43 +518: /home/ubuntu/ss-mm-e02r15/test/features/practice/data/adapters/lesson_practice_adapter_test.dart: practiceDefinitionFromLesson — controlled failure modes returns Failure for empty events list
00:43 +519: /home/ubuntu/ss-mm-e02r15/test/features/practice/data/adapters/lesson_practice_adapter_test.dart: practiceDefinitionFromLesson — controlled failure modes displayTitle trims whitespace and becomes null for empty name
00:43 +520: /home/ubuntu/ss-mm-e02r15/test/features/practice/data/adapters/lesson_practice_adapter_test.dart: practiceDefinitionFromLesson — difficulty mapping preserves beginner, intermediate and advanced tiers
00:43 +521: /home/ubuntu/ss-mm-e02r15/test/features/practice/data/adapters/daily_challenge_practice_adapter_test.dart: practiceDefinitionFromDailyChallenge — determinism the same epoch day produces structurally equal definitions
00:43 +522: /home/ubuntu/ss-mm-e02r15/test/features/practice/data/adapters/daily_challenge_practice_adapter_test.dart: practiceDefinitionFromDailyChallenge — determinism consecutive epoch days produce different definitions
00:43 +523: /home/ubuntu/ss-mm-e02r15/test/features/practice/data/adapters/daily_challenge_practice_adapter_test.dart: practiceDefinitionFromDailyChallenge — determinism definition ID encodes the epoch day
00:43 +524: /home/ubuntu/ss-mm-e02r15/test/features/practice/data/adapters/daily_challenge_practice_adapter_test.dart: practiceDefinitionFromDailyChallenge — pattern handling pattern longer than 8 slots is truncated to 8 events
00:43 +525: /home/ubuntu/ss-mm-e02r15/test/features/practice/data/adapters/daily_challenge_practice_adapter_test.dart: practiceDefinitionFromDailyChallenge — pattern handling pattern shorter than 8 slots is preserved as-is
00:43 +526: /home/ubuntu/ss-mm-e02r15/test/features/practice/data/adapters/daily_challenge_practice_adapter_test.dart: practiceDefinitionFromDailyChallenge — pattern handling every event has a null chord (strum-only)
00:43 +527: /home/ubuntu/ss-mm-e02r15/test/features/practice/data/adapters/daily_challenge_practice_adapter_test.dart: practiceDefinitionFromDailyChallenge — pattern handling event positions are eighth-note slots starting at zero
00:43 +528: /home/ubuntu/ss-mm-e02r15/test/features/practice/data/adapters/daily_challenge_practice_adapter_test.dart: practiceDefinitionFromDailyChallenge — definition surface source, mode, keys, difficulty, profile match ADR contract
00:43 +529: /home/ubuntu/ss-mm-e02r15/test/features/practice/data/adapters/daily_challenge_practice_adapter_test.dart: practiceDefinitionFromDailyChallenge — definition surface custom bpm is honored when in range
00:43 +530: /home/ubuntu/ss-mm-e02r15/test/features/practice/data/adapters/daily_challenge_practice_adapter_test.dart: practiceDefinitionFromDailyChallenge — controlled failure modes empty pattern is rejected
00:43 +531: /home/ubuntu/ss-mm-e02r15/test/features/practice/data/adapters/daily_challenge_practice_adapter_test.dart: practiceDefinitionFromDailyChallenge — controlled failure modes bpm out of range is rejected
00:43 +532: /home/ubuntu/ss-mm-e02r15/test/features/practice/data/adapters/daily_challenge_practice_adapter_test.dart: practiceDefinitionFromDailyChallenge — controlled failure modes non-finite bpm is rejected
00:43 +533: /home/ubuntu/ss-mm-e02r15/test/features/practice/data/adapters/daily_challenge_practice_adapter_test.dart: practiceDefinitionFromDailyChallenge — controlled failure modes none of the failure paths throws
00:43 +534: /home/ubuntu/ss-mm-e02r15/test/features/practice/data/adapters/daily_challenge_practice_adapter_test.dart: practiceDefinitionFromDailyChallenge — displayTitle trims whitespace and falls back to null for empty names
00:44 +535: /home/ubuntu/ss-mm-e02r15/test/features/practice/data/adapters/legacy_chord_label_test.dart: legacyPracticeChordLabel returns null for null input
00:44 +536: /home/ubuntu/ss-mm-e02r15/test/features/practice/data/adapters/legacy_chord_label_test.dart: legacyPracticeChordLabel returns null for empty and whitespace-only labels
00:44 +537: /home/ubuntu/ss-mm-e02r15/test/features/practice/data/adapters/legacy_chord_label_test.dart: legacyPracticeChordLabel passes canonical labels through unchanged
00:44 +538: /home/ubuntu/ss-mm-e02r15/test/features/practice/data/adapters/legacy_chord_label_test.dart: legacyPracticeChordLabel reduces 7th / minor variants to their parent majmin
00:44 +539: /home/ubuntu/ss-mm-e02r15/test/features/practice/data/adapters/legacy_chord_label_test.dart: legacyPracticeChordLabel rewrites flat roots to their sharp enharmonic
00:44 +540: /home/ubuntu/ss-mm-e02r15/test/features/practice/data/adapters/legacy_chord_label_test.dart: legacyPracticeChordLabel drops the slash-bass of a slash chord
00:44 +541: /home/ubuntu/ss-mm-e02r15/test/features/practice/data/adapters/legacy_chord_label_test.dart: legacyPracticeChordLabel returns null for unparseable roots
00:44 +542: /home/ubuntu/ss-mm-e02r15/test/features/practice/data/adapters/legacy_chord_label_test.dart: legacyPracticeChordLabel returns null for empty after slash-bass removal
00:44 +543: /home/ubuntu/ss-mm-e02r15/test/features/practice/data/adapters/legacy_chord_label_test.dart: legacyPracticeChordLabel trims surrounding whitespace before parsing
00:44 +544: /home/ubuntu/ss-mm-e02r15/test/features/practice/data/adapters/legacy_chord_label_test.dart: legacyPracticeChordLabel every non-null output is canonical
00:44 +545: /home/ubuntu/ss-mm-e02r15/test/features/practice/data/adapters/analyze_practice_adapter_test.dart: practiceDefinitionFromAnalyze — non-empty clip three strums with two chord lanes produce deterministic ticks
00:44 +546: /home/ubuntu/ss-mm-e02r15/test/features/practice/data/adapters/analyze_practice_adapter_test.dart: practiceDefinitionFromAnalyze — non-empty clip preserves 3/4 meter on the resulting definition
00:44 +547: /home/ubuntu/ss-mm-e02r15/test/features/practice/data/adapters/analyze_practice_adapter_test.dart: practiceDefinitionFromAnalyze — non-empty clip unordered strums come out sorted
00:44 +548: /home/ubuntu/ss-mm-e02r15/test/features/practice/data/adapters/analyze_practice_adapter_test.dart: practiceDefinitionFromAnalyze — BPM fallbacks bpm=0 falls back to 90 BPM
00:44 +549: /home/ubuntu/ss-mm-e02r15/test/features/practice/data/adapters/analyze_practice_adapter_test.dart: practiceDefinitionFromAnalyze — BPM fallbacks bpm=400 falls back to 90 BPM
00:44 +550: /home/ubuntu/ss-mm-e02r15/test/features/practice/data/adapters/analyze_practice_adapter_test.dart: practiceDefinitionFromAnalyze — BPM fallbacks bpm=NaN falls back to 90 BPM
00:44 +551: /home/ubuntu/ss-mm-e02r15/test/features/practice/data/adapters/analyze_practice_adapter_test.dart: practiceDefinitionFromAnalyze — BPM fallbacks bpm=80 is preserved
00:44 +552: /home/ubuntu/ss-mm-e02r15/test/features/practice/data/adapters/analyze_practice_adapter_test.dart: practiceDefinitionFromAnalyze — tick collision forward-push two strums 0.0005s apart push the second onto the next tick
00:44 +553: /home/ubuntu/ss-mm-e02r15/test/features/practice/data/adapters/analyze_practice_adapter_test.dart: practiceDefinitionFromAnalyze — empty strum list falls back to freePractice + open scoring + no events
00:44 +554: /home/ubuntu/ss-mm-e02r15/test/features/practice/data/adapters/analyze_practice_adapter_test.dart: practiceDefinitionFromAnalyze — empty strum list all-non-finite strums are dropped, triggering empty-branch
00:44 +555: /home/ubuntu/ss-mm-e02r15/test/features/practice/data/adapters/analyze_practice_adapter_test.dart: practiceDefinitionFromAnalyze — controlled failure modes blank sourceId is rejected
00:44 +556: /home/ubuntu/ss-mm-e02r15/test/features/practice/data/adapters/analyze_practice_adapter_test.dart: practiceDefinitionFromAnalyze — controlled failure modes out-of-range beatsPerBar is rejected
00:44 +557: /home/ubuntu/ss-mm-e02r15/test/features/practice/data/adapters/analyze_practice_adapter_test.dart: practiceDefinitionFromAnalyze — in-loop timeline grow totalBeats grows by one bar when rounding lands on the bound
00:44 +558: /home/ubuntu/ss-mm-e02r15/test/features/practice/data/adapters/analyze_practice_adapter_test.dart: practiceDefinitionFromAnalyze — t0 normalization non-zero t0 normalizes times, and last tick at bound-1 keeps totalBeats at 4.0
00:44 +559: /home/ubuntu/ss-mm-e02r15/test/features/practice/data/adapters/analyze_practice_adapter_test.dart: practiceDefinitionFromAnalyze — definition surface source, difficulty, keys, tags match ADR contract
00:45 +560: /home/ubuntu/ss-mm-e02r15/test/features/practice/data/live_practice_observation_gateway_test.dart: §6.2 lag-guard matrix (read on derived lag) row 1: (-1,-1), timelineNow=0 → at=0, no log
00:45 +561: /home/ubuntu/ss-mm-e02r15/test/features/practice/data/live_practice_observation_gateway_test.dart: §6.2 lag-guard matrix (read on derived lag) row 1: (-1,-1), timelineNow=10s → at=10s, no log
00:45 +562: /home/ubuntu/ss-mm-e02r15/test/features/practice/data/live_practice_observation_gateway_test.dart: §6.2 lag-guard matrix (read on derived lag) row 2: (-1,0.5), timelineNow=0 → at=0, no log
00:45 +563: /home/ubuntu/ss-mm-e02r15/test/features/practice/data/live_practice_observation_gateway_test.dart: §6.2 lag-guard matrix (read on derived lag) row 2: (-1,0.5), timelineNow=10s → at=10s, no log
00:45 +564: /home/ubuntu/ss-mm-e02r15/test/features/practice/data/live_practice_observation_gateway_test.dart: §6.2 lag-guard matrix (read on derived lag) row 3: (1.0,-1), timelineNow=0 → at=0, no log
00:45 +565: /home/ubuntu/ss-mm-e02r15/test/features/practice/data/live_practice_observation_gateway_test.dart: §6.2 lag-guard matrix (read on derived lag) row 3: (1.0,-1), timelineNow=10s → at=10s, no log
00:45 +566: /home/ubuntu/ss-mm-e02r15/test/features/practice/data/live_practice_observation_gateway_test.dart: §6.2 lag-guard matrix (read on derived lag) row 4: (1.0,1.0), timelineNow=0 → at=0, no log
00:45 +567: /home/ubuntu/ss-mm-e02r15/test/features/practice/data/live_practice_observation_gateway_test.dart: §6.2 lag-guard matrix (read on derived lag) row 4: (1.0,1.0), timelineNow=10s → at=10s, no log
00:45 +568: /home/ubuntu/ss-mm-e02r15/test/features/practice/data/live_practice_observation_gateway_test.dart: §6.2 lag-guard matrix (read on derived lag) row 5: (1.0,1.10), timelineNow=0 → at=0, no log
00:45 +569: /home/ubuntu/ss-mm-e02r15/test/features/practice/data/live_practice_observation_gateway_test.dart: §6.2 lag-guard matrix (read on derived lag) row 5: (1.0,1.10), timelineNow=10s → at=10s, no log
00:45 +570: /home/ubuntu/ss-mm-e02r15/test/features/practice/data/live_practice_observation_gateway_test.dart: §6.2 lag-guard matrix (read on derived lag) row 6: (1.0,0.90), timelineNow=0 → at=0 (clamp), no log
00:45 +571: /home/ubuntu/ss-mm-e02r15/test/features/practice/data/live_practice_observation_gateway_test.dart: §6.2 lag-guard matrix (read on derived lag) row 6: (1.0,0.90), timelineNow=10s → at=9.9s, no log
00:45 +572: /home/ubuntu/ss-mm-e02r15/test/features/practice/data/live_practice_observation_gateway_test.dart: §6.2 lag-guard matrix (read on derived lag) row 7: (1.0,0.5001), timelineNow=0 → at=0 (clamp), no log
00:45 +573: /home/ubuntu/ss-mm-e02r15/test/features/practice/data/live_practice_observation_gateway_test.dart: §6.2 lag-guard matrix (read on derived lag) row 7: (1.0,0.5001), timelineNow=10s → at=9.5001s, no log
00:45 +574: /home/ubuntu/ss-mm-e02r15/test/features/practice/data/live_practice_observation_gateway_test.dart: §6.2 lag-guard matrix (read on derived lag) row 8: (1.0,0.50), timelineNow=0 → at=0 (lag nem levont), 1 warning
00:45 +575: /home/ubuntu/ss-mm-e02r15/test/features/practice/data/live_practice_observation_gateway_test.dart: §6.2 lag-guard matrix (read on derived lag) row 8: (1.0,0.50), timelineNow=10s → at=10s (lag nem levont), 1 warning
00:45 +576: /home/ubuntu/ss-mm-e02r15/test/features/practice/data/live_practice_observation_gateway_test.dart: §6.2 lag-guard matrix (read on derived lag) row 9: (1.0,0.4999), timelineNow=0 → at=0 (lag nem levont), 1 warning
00:45 +577: /home/ubuntu/ss-mm-e02r15/test/features/practice/data/live_practice_observation_gateway_test.dart: §6.2 lag-guard matrix (read on derived lag) row 9: (1.0,0.4999), timelineNow=10s → at=10s (lag nem levont), 1 warning
00:45 +578: /home/ubuntu/ss-mm-e02r15/test/features/practice/data/live_practice_observation_gateway_test.dart: §6.3 confidence-határ matrix confidence=0.0 below threshold → no observation
00:45 +579: /home/ubuntu/ss-mm-e02r15/test/features/practice/data/live_practice_observation_gateway_test.dart: §6.3 confidence-határ matrix confidence=0.5499 below threshold → no observation
00:45 +580: /home/ubuntu/ss-mm-e02r15/test/features/practice/data/live_practice_observation_gateway_test.dart: §6.3 confidence-határ matrix confidence=0.55 exactly at threshold → observation emitted
00:45 +581: /home/ubuntu/ss-mm-e02r15/test/features/practice/data/live_practice_observation_gateway_test.dart: §6.3 confidence-határ matrix confidence=0.5501 above threshold → observation emitted
00:45 +582: /home/ubuntu/ss-mm-e02r15/test/features/practice/data/live_practice_observation_gateway_test.dart: §6.3 confidence-határ matrix confidence=1.0 maximum → observation emitted
00:45 +583: /home/ubuntu/ss-mm-e02r15/test/features/practice/data/live_practice_observation_gateway_test.dart: §6.3 confidence-határ matrix below-threshold strum advances dedup so the same seq does not re-emit
00:45 +584: /home/ubuntu/ss-mm-e02r15/test/features/practice/data/live_practice_observation_gateway_test.dart: §6.2b a lag hatóköre és a fajtánkénti padló (R2) de-jitter túléli a chord observationt (R0 PRÓBA-A)
00:45 +585: /home/ubuntu/ss-mm-e02r15/test/features/practice/data/live_practice_observation_gateway_test.dart: §6.2b a lag hatóköre és a fajtánkénti padló (R2) chord change-point nem kap idegen lagot (R0 PRÓBA-B, 300 ms)
00:45 +586: /home/ubuntu/ss-mm-e02r15/test/features/practice/data/live_practice_observation_gateway_test.dart: §6.2b a lag hatóköre és a fajtánkénti padló (R2) chord change-point nem kap idegen lagot (R2, 600 ms, határ fölött)
00:45 +587: /home/ubuntu/ss-mm-e02r15/test/features/practice/data/live_practice_observation_gateway_test.dart: §6.4 monotonitás és sűrű sorszám változatlan timelineNow mellett a nagy lagú frame után a lag nélküli frame at-ja nem kisebb
00:45 +588: /home/ubuntu/ss-mm-e02r15/test/features/practice/data/live_practice_observation_gateway_test.dart: §6.4 monotonitás és sűrű sorszám strumSeq 5→9 ugrás → observation sequence 0,1
00:45 +589: /home/ubuntu/ss-mm-e02r15/test/features/practice/data/live_practice_observation_gateway_test.dart: §6.4 monotonitás és sűrű sorszám két küszöb feletti strum között egy küszöb alatti → sequence 0,1
00:45 +590: /home/ubuntu/ss-mm-e02r15/test/features/practice/data/live_practice_observation_gateway_test.dart: §6.4 monotonitás és sűrű sorszám start → 3 strum → stop → start → 1 strum: utolsó sequence=0, at nem a régi lastEmittedAt-ra clampelve
00:45 +591: /home/ubuntu/ss-mm-e02r15/test/features/practice/data/live_practice_observation_gateway_test.dart: §6.5 chord-mintavétel matrix ugyanaz a label 10 frame-en belül → pontosan 1 ChordObservation
00:45 +592: /home/ubuntu/ss-mm-e02r15/test/features/practice/data/live_practice_observation_gateway_test.dart: §6.5 chord-mintavétel matrix label-váltás C → G → új observation
00:45 +593: /home/ubuntu/ss-mm-e02r15/test/features/practice/data/live_practice_observation_gateway_test.dart: §6.5 chord-mintavétel matrix akkord → nincs akkord → label:null observation is kiadódik
00:45 +594: /home/ubuntu/ss-mm-e02r15/test/features/practice/data/live_practice_observation_gateway_test.dart: §6.5 chord-mintavétel matrix nem kanonikus label a detektorból (Em7, G/B, H) → redukció, observation validate() üres
00:45 +595: /home/ubuntu/ss-mm-e02r15/test/features/practice/data/live_practice_observation_gateway_test.dart: §6.5 chord-mintavétel matrix változatlan label, de eltelt chordStableDuration → újramintavétel
00:45 +596: /home/ubuntu/ss-mm-e02r15/test/features/practice/data/live_practice_observation_gateway_test.dart: §6.5 chord-mintavétel matrix a Live úton a confidence mindig 1.0, és chordMinConfidence=0.99 SEM szűr chordot
00:45 +597: /home/ubuntu/ss-mm-e02r15/test/features/practice/data/live_practice_observation_gateway_test.dart: §6.6 életciklus start ×2 → mindkettő Success, engine.startCalls == 1
00:45 +598: /home/ubuntu/ss-mm-e02r15/test/features/practice/data/live_practice_observation_gateway_test.dart: §6.6 életciklus stop ×2 → mindkettő Success, engine.stopCalls == 1
00:45 +599: /home/ubuntu/ss-mm-e02r15/test/features/practice/data/live_practice_observation_gateway_test.dart: §6.6 életciklus dispose után start/stop → Failure (gateway disposed)
00:45 +600: /home/ubuntu/ss-mm-e02r15/test/features/practice/data/live_practice_observation_gateway_test.dart: §6.6 életciklus setExpectedChord → engine.expectedChordCalls utolsó eleme a label; stop után az utolsó elem null
00:45 +601: /home/ubuntu/ss-mm-e02r15/test/features/practice/data/live_practice_observation_gateway_test.dart: §6.6 életciklus setExpectedChord a start előtt → sikeres start után az engine megkapja a labelt
00:45 +602: /home/ubuntu/ss-mm-e02r15/test/features/practice/data/live_practice_observation_gateway_test.dart: §6.7 hibaleképezés megtagadott engedély → Failure(PermissionFailure), engine.startCalls==0
00:45 +603: /home/ubuntu/ss-mm-e02r15/test/features/practice/data/live_practice_observation_gateway_test.dart: §6.7 hibaleképezés request() után granted → engine.startCalls==1
00:45 +604: /home/ubuntu/ss-mm-e02r15/test/features/practice/data/live_practice_observation_gateway_test.dart: §6.7 hibaleképezés érvénytelen config → Failure(configurationInvalid), engine.startCalls==0
00:45 +605: /home/ubuntu/ss-mm-e02r15/test/features/practice/data/live_practice_observation_gateway_test.dart: §6.7 hibaleképezés engine stream AudioFailure(audioSessionBusy) → stream hiba ugyanaz, engine.stopCalls==1, stream nem zárul be, újabb start sikerül
00:45 +606: /home/ubuntu/ss-mm-e02r15/test/features/practice/data/live_practice_observation_gateway_test.dart: §6.7 hibaleképezés engine stream StateError → AudioFailure(practiceObservationStreamFailed)
00:45 +607: /home/ubuntu/ss-mm-e02r15/test/features/practice/data/live_practice_observation_gateway_test.dart: §6.7 hibaleképezés a hiba után beküldött frame NEM ad observationt
00:45 +608: /home/ubuntu/ss-mm-e02r15/test/features/practice/data/live_practice_observation_gateway_test.dart: §6.8 log-fegyelem 200 érvényes, observationt adó frame feldolgozása után a logger a start/stop páron kívül nem kap bejegyzést
00:45 +609: /home/ubuntu/ss-mm-e02r15/test/features/practice/data/live_practice_observation_gateway_test.dart: §6.8 log-fegyelem tíz, tartományon kívüli lagú frame ugyanabban a másodpercben → 1 warning
00:45 +610: /home/ubuntu/ss-mm-e02r15/test/features/practice/application/practice_session_integration_test.dart: perfect session: result is non-null, scorePoints > 0, navigateToResult fired exactly once
00:45 +611: /home/ubuntu/ss-mm-e02r15/test/features/practice/application/practice_session_integration_test.dart: wrong direction: matched strum with wrong direction → directionOutcome == wrong
00:46 +612: /home/ubuntu/ss-mm-e02r15/test/features/practice/application/practice_session_integration_test.dart: chord failure: matched strum with wrong chord → chordOutcome == wrong
00:46 +613: /home/ubuntu/ss-mm-e02r15/test/features/practice/application/practice_session_integration_test.dart: pause/resume: playingElapsed freezes, pausedElapsed grows, resume reaches running
00:46 +614: /home/ubuntu/ss-mm-e02r15/test/features/practice/application/practice_session_integration_test.dart: restart: from paused → countIn with attemptIndex + 1
00:46 +615: /home/ubuntu/ss-mm-e02r15/test/features/practice/application/practice_session_integration_test.dart: cancel: user cancel → result == null, recorder.recordCalls == 0
00:46 +616: /home/ubuntu/ss-mm-e02r15/test/features/practice/application/practice_session_integration_test.dart: stream failure: observation stream error → ShowRecoverableError, session stays running
00:46 +617: /home/ubuntu/ss-mm-e02r15/test/features/practice/application/practice_session_integration_test.dart: no signal: many unmatched strums → direction+rhythm MetricInsufficientData(noSignal)
00:46 +618: /home/ubuntu/ss-mm-e02r15/test/features/practice/application/practice_session_integration_test.dart: complete cleanup: FinishPractice → finished → full resource teardown (gateway dispose, tick stop, recorder called once)
00:46 +619: /home/ubuntu/ss-mm-e02r15/test/features/practice/application/practice_session_integration_test.dart: expected chord sequence: gateway.setExpectedChord called with each segment chord in order, then null on finish
00:46 +620: /home/ubuntu/ss-mm-e02r15/test/features/practice/application/practice_observation_activation_test.dart: maps every practice session status to its capture decision
00:46 +621: /home/ubuntu/ss-mm-e02r15/test/features/practice/application/practice_observation_activation_test.dart: policy keys cover exactly the session status enum
00:46 +622: /home/ubuntu/ss-mm-e02r15/test/features/practice/application/practice_observation_activation_test.dart: paused disables capture and closes the chunk 014 pause gap
00:47 +623: /home/ubuntu/ss-mm-e02r15/test/features/practice/application/practice_catalog_controller_test.dart: practiceCatalogProvider returns the full built-in catalog in declaration order
00:47 +624: /home/ubuntu/ss-mm-e02r15/test/features/practice/application/practice_catalog_controller_test.dart: practiceCatalogProvider is backed by the BuiltinPracticeCatalog by default
00:47 +625: /home/ubuntu/ss-mm-e02r15/test/features/practice/application/practice_catalog_controller_test.dart: practiceCatalogProvider rewires when practiceCatalogRepositoryProvider is overridden
00:48 +626: /home/ubuntu/ss-mm-e02r15/test/features/practice/application/practice_session_timing_test.dart: pause / resume bookkeeping pause does not advance activeElapsed or playingElapsed
00:48 +627: /home/ubuntu/ss-mm-e02r15/test/features/practice/application/practice_session_timing_test.dart: pause / resume bookkeeping playingElapsed advances only while status == running
00:48 +628: /home/ubuntu/ss-mm-e02r15/test/features/practice/application/practice_session_timing_test.dart: daily goal — countInBars=2, 4/4, 120 BPM (§6.4) 4 beats playing + 10s pause + 2 bars resume = exact playingElapsed
00:48 +629: /home/ubuntu/ss-mm-e02r15/test/features/practice/application/practice_session_timing_test.dart: countInBars == 0 countIn → running happens immediately at active=0
00:48 +630: /home/ubuntu/ss-mm-e02r15/test/features/practice/application/practice_session_timing_test.dart: resume-anchor (§5.5, §0.1) pause at countInDuration + 2.5 bars → resume anchors at the 2nd musical bar boundary
00:48 +631: /home/ubuntu/ss-mm-e02r15/test/features/practice/application/practice_session_timing_test.dart: resume-anchor (§5.5, §0.1) pause EXACTLY on a bar boundary → anchor is that boundary
00:48 +632: /home/ubuntu/ss-mm-e02r15/test/features/practice/application/practice_session_timing_test.dart: resume-anchor (§5.5, §0.1) pause 1µs after a bar boundary → anchor is the SAME boundary
00:48 +633: /home/ubuntu/ss-mm-e02r15/test/features/practice/application/practice_session_timing_test.dart: 3/4 meter (§0.1) resume count-in is 3 beats long, not 4
00:48 +634: /home/ubuntu/ss-mm-e02r15/test/features/practice/application/practice_session_timing_test.dart: 3/4 meter (§0.1) count-in click effects: initial count-in emits meter.beatsPerBar clicks
00:48 +635: /home/ubuntu/ss-mm-e02r15/test/features/practice/application/practice_session_timing_test.dart: RestartAttempt (§0.1) full second attempt: timelineBase=0, activeBase==activeElapsed, playingElapsed=0, wallElapsed continues
00:48 +636: /home/ubuntu/ss-mm-e02r15/test/features/practice/application/practice_session_timing_test.dart: session timeout (§5.6, §6.4) wallElapsed > sessionTimeout → finishing + timedOut
00:48 +637: /home/ubuntu/ss-mm-e02r15/test/features/practice/application/practice_session_timing_test.dart: session timeout (§5.6, §6.4) timeout wins over completedTimeline when both conditions met
00:48 +638: /home/ubuntu/ss-mm-e02r15/test/features/practice/application/practice_session_timing_test.dart: 0.5 practice speed (§0.1) halving effectiveTempo halves the bar boundaries — playingElapsed matches real time, not timeline time
00:48 +639: /home/ubuntu/ss-mm-e02r15/test/features/practice/application/practice_session_timing_test.dart: count-in click batching (§5.7) a single big ClockAdvanced spanning the whole count-in emits all click effects in order, no duplicates
00:48 +640: /home/ubuntu/ss-mm-e02r15/test/features/practice/application/practice_session_timing_test.dart: pause during count-in (§0.1) a single PausePractice during count-in freezes countInElapsed
00:48 +641: /home/ubuntu/ss-mm-e02r15/test/features/practice/application/practice_session_timing_test.dart: double pause/resume in same bar (§0.1) two consecutive pause/resume cycles preserve the timeline
00:48 +642: /home/ubuntu/ss-mm-e02r15/test/features/practice/application/practice_session_timing_test.dart: §6.1 purity guardrails (file-content checks) reducer does not define its own beat-to-time formula (no `bpm` or `60` literal)
00:49 +643: /home/ubuntu/ss-mm-e02r15/test/features/practice/application/practice_session_review_probes_test.dart: P1: permissionRequired + PreparationSucceeded is rejected
00:49 +644: /home/ubuntu/ss-mm-e02r15/test/features/practice/application/practice_session_review_probes_test.dart: P1b: permissionRequired + PreparationFailed is rejected
00:49 +645: /home/ubuntu/ss-mm-e02r15/test/features/practice/application/practice_session_review_probes_test.dart: P2: 2-bar initial count-in (4/4, 120 BPM) emits 8 clicks
00:49 +646: /home/ubuntu/ss-mm-e02r15/test/features/practice/application/practice_session_review_probes_test.dart: P3: timeout beats completedTimeline when both conditions hold
00:49 +647: /home/ubuntu/ss-mm-e02r15/test/features/practice/application/practice_session_review_probes_test.dart: P4: paused past sessionTimeout → finishing + timedOut
00:49 +648: /home/ubuntu/ss-mm-e02r15/test/features/practice/application/practice_session_review_probes_test.dart: P5: second attempt timelinePosition starts at Duration.zero
00:49 +649: /home/ubuntu/ss-mm-e02r15/test/features/practice/application/practice_session_review_probes_test.dart: P6: timelinePosition can exceed totalDuration, status is no longer running
00:49 +650: /home/ubuntu/ss-mm-e02r15/test/features/practice/application/practice_session_review_probes_test.dart: R1 MAJOR-3: statusPath walks every adjacent edge through allowedTransitions
00:49 +651: /home/ubuntu/ss-mm-e02r15/test/features/practice/application/practice_session_review_probes_test.dart: StartPractice sets countInSpanBeats = countInBars * beatsPerBar (R1 MAJOR-4)
00:49 +652: /home/ubuntu/ss-mm-e02r15/test/features/practice/application/practice_session_controller_test.dart: A1 — status stream emits every transition idle → preparing → ready on PreparePractice + Succeeded
00:49 +653: /home/ubuntu/ss-mm-e02r15/test/features/practice/application/practice_session_controller_test.dart: A1 — status stream emits every transition FinishPractice + tick crosses finishing → completed
00:49 +654: /home/ubuntu/ss-mm-e02r15/test/features/practice/application/practice_session_controller_test.dart: A2 — capture-activation matrix startCalls == 1 when entering countIn
00:49 +655: /home/ubuntu/ss-mm-e02r15/test/features/practice/application/practice_session_controller_test.dart: A2 — capture-activation matrix countIn → running keeps startCalls unchanged
00:49 +656: /home/ubuntu/ss-mm-e02r15/test/features/practice/application/practice_session_controller_test.dart: A2 — capture-activation matrix running → paused stops the gateway exactly once
00:49 +657: /home/ubuntu/ss-mm-e02r15/test/features/practice/application/practice_session_controller_test.dart: A2 — capture-activation matrix paused → countIn (resume) restarts the gateway (startCalls == 2)
00:49 +658: /home/ubuntu/ss-mm-e02r15/test/features/practice/application/practice_session_controller_test.dart: A3 — finish single-flight multiple FinishPractice calls produce exactly one record()
00:49 +659: /home/ubuntu/ss-mm-e02r15/test/features/practice/application/practice_session_controller_test.dart: A3 — finish single-flight finishReason maps to userFinished on FinishPractice
00:49 +660: /home/ubuntu/ss-mm-e02r15/test/features/practice/application/practice_session_controller_test.dart: A4 — cleanup matrix completed: disposeCalls == 1, recordCalls == 1
00:49 +661: /home/ubuntu/ss-mm-e02r15/test/features/practice/application/practice_session_controller_test.dart: A4 — cleanup matrix cancelled (a) user CancelPractice: disposeCalls == 1, recordCalls == 0
00:49 +662: /home/ubuntu/ss-mm-e02r15/test/features/practice/application/practice_session_controller_test.dart: A4 — cleanup matrix cancelled (b) gateway-start Failure: cancelled, recordCalls == 0
00:49 +663: /home/ubuntu/ss-mm-e02r15/test/features/practice/application/practice_session_controller_test.dart: A4 — cleanup matrix failed (compileTarget Failure) — preparing → failed, recordCalls == 0
00:49 +664: /home/ubuntu/ss-mm-e02r15/test/features/practice/application/practice_session_controller_test.dart: A5 — error matrix permission denied during preparing → permissionRequired
00:49 +665: /home/ubuntu/ss-mm-e02r15/test/features/practice/application/practice_session_controller_test.dart: A5 — error matrix compileTarget Failure → preparing → failed (reducer-origin effect)
00:49 +666: /home/ubuntu/ss-mm-e02r15/test/features/practice/application/practice_session_controller_test.dart: A5 — error matrix gateway.start() Failure → cancelled, recorder NOT called
00:50 +667: /home/ubuntu/ss-mm-e02r15/test/features/practice/application/practice_session_controller_test.dart: A6 — pause semantics running → paused: strum during pause does not change liveScore
00:50 +668: /home/ubuntu/ss-mm-e02r15/test/features/practice/application/practice_session_controller_test.dart: A6 — pause semantics playingElapsed freezes during paused; pausedElapsed grows
00:50 +669: /home/ubuntu/ss-mm-e02r15/test/features/practice/application/practice_session_controller_test.dart: A6 — pause semantics resume continues the timeline from the bar-boundary anchor (no jump)
00:50 +670: /home/ubuntu/ss-mm-e02r15/test/features/practice/application/practice_session_controller_test.dart: A6 — pause semantics Meter 4/4 × countInBars=0: pause/resume cycle completes
00:50 +671: /home/ubuntu/ss-mm-e02r15/test/features/practice/application/practice_session_controller_test.dart: A6 — pause semantics Meter 4/4 × countInBars=1: pause/resume cycle completes
00:50 +672: /home/ubuntu/ss-mm-e02r15/test/features/practice/application/practice_session_controller_test.dart: A6 — pause semantics Meter 4/4 × countInBars=2: pause/resume cycle completes
00:50 +673: /home/ubuntu/ss-mm-e02r15/test/features/practice/application/practice_session_controller_test.dart: A6 — pause semantics Meter 3/4 × countInBars=0: pause/resume cycle completes
00:50 +674: /home/ubuntu/ss-mm-e02r15/test/features/practice/application/practice_session_controller_test.dart: A6 — pause semantics Meter 3/4 × countInBars=1: pause/resume cycle completes
00:50 +675: /home/ubuntu/ss-mm-e02r15/test/features/practice/application/practice_session_controller_test.dart: A6 — pause semantics Meter 3/4 × countInBars=2: pause/resume cycle completes
00:50 +676: /home/ubuntu/ss-mm-e02r15/test/features/practice/application/practice_session_controller_test.dart: A8 — single observation-config source gateway receives exactly the controller-provided config
00:50 +677: /home/ubuntu/ss-mm-e02r15/test/features/practice/application/practice_session_controller_test.dart: A8 — single observation-config source 400ms chordStableDuration: 250ms-stable chord run → MetricInsufficientData(chordUnstable)
00:50 +678: /home/ubuntu/ss-mm-e02r15/test/features/practice/application/practice_session_controller_test.dart: A8 — single observation-config source 180ms chordStableDuration: same 250ms run → MetricAvailable
00:50 +679: /home/ubuntu/ss-mm-e02r15/test/features/practice/application/practice_session_controller_test.dart: A13 — noSignal pinned (current behaviour, NOT a fix) many unmatched strums → direction+rhythm MetricInsufficientData (noSignal); scorePoints == 0 (no matches, but signal was registered)
00:50 +680: /home/ubuntu/ss-mm-e02r15/test/features/practice/application/practice_session_controller_test.dart: A14 — scoring pass discipline 100 ticks in running with no observation → liveScore unchanged
00:50 +681: /home/ubuntu/ss-mm-e02r15/test/features/practice/application/practice_session_controller_test.dart: A14 — scoring pass discipline a ChordObservation alone → liveScore unchanged
00:50 +682: /home/ubuntu/ss-mm-e02r15/test/features/practice/application/practice_session_controller_test.dart: A14 — scoring pass discipline a StrumObservation → liveScore changes (new aggregation)
00:50 +683: /home/ubuntu/ss-mm-e02r15/test/features/practice/application/practice_session_controller_test.dart: A14 — scoring pass discipline FinishPractice alone does not change liveScore (the final pass updates `result`, not `liveScore`)
00:50 +684: /home/ubuntu/ss-mm-e02r15/test/features/practice/application/practice_session_controller_test.dart: A15 — finishReason mapping cancelled by user → result == null
00:50 +685: /home/ubuntu/ss-mm-e02r15/test/features/practice/application/practice_session_controller_test.dart: A15 — finishReason mapping cancelled by gateway failure → result == null
00:50 +686: /home/ubuntu/ss-mm-e02r15/test/features/practice/application/practice_session_controller_test.dart: A15 — finishReason mapping failed → result == null
00:50 +687: /home/ubuntu/ss-mm-e02r15/test/features/practice/application/practice_session_controller_test.dart: A16 — finishing is observable FinishPractice + tick crosses through finishing
00:50 +688: /home/ubuntu/ss-mm-e02r15/test/features/practice/application/practice_session_controller_test.dart: A17 — failed is reachable ONLY from preparing (pin) PreparationFailed from countIn is rejected by the reducer
00:50 +689: /home/ubuntu/ss-mm-e02r15/test/features/practice/application/practice_session_controller_test.dart: A17 — failed is reachable ONLY from preparing (pin) PreparationFailed from paused is rejected by the reducer
00:50 +690: /home/ubuntu/ss-mm-e02r15/test/features/practice/application/practice_session_controller_test.dart: A17 — failed is reachable ONLY from preparing (pin) gateway-start failure → cancelled, recorder NOT called (R14 contract)
00:50 +691: /home/ubuntu/ss-mm-e02r15/test/features/practice/application/practice_session_controller_test.dart: A9 — controller layer-purity guard no forbidden symbol appears in the controller source (ADR 0077 §10 / R10d / R13)
00:50 +692: /home/ubuntu/ss-mm-e02r15/test/features/practice/application/practice_observation_gateway_test.dart: PracticeObservationConfig uses the brief defaults
00:50 +693: /home/ubuntu/ss-mm-e02r15/test/features/practice/application/practice_observation_gateway_test.dart: PracticeObservationConfig has value equality
00:50 +694: /home/ubuntu/ss-mm-e02r15/test/features/practice/application/practice_observation_gateway_test.dart: PracticeObservationConfig validates every confidence and duration boundary
00:50 +695: /home/ubuntu/ss-mm-e02r15/test/features/practice/application/practice_observation_gateway_test.dart: PracticeObservationConfig invalid config is represented by configuration.invalid
00:50 +696: /home/ubuntu/ss-mm-e02r15/test/features/practice/application/practice_observation_gateway_test.dart: FakePracticeObservationGateway keeps start and stop idempotent
00:50 +697: /home/ubuntu/ss-mm-e02r15/test/features/practice/application/practice_observation_gateway_test.dart: FakePracticeObservationGateway records expected chord and exposes a controllable stream
00:50 +698: /home/ubuntu/ss-mm-e02r15/test/features/practice/application/practice_observation_gateway_test.dart: FakePracticeObservationGateway returns the injected start result
00:50 +699: /home/ubuntu/ss-mm-e02r15/test/features/practice/application/practice_observation_gateway_test.dart: FakePracticeObservationGateway rejects operations after dispose
00:51 +700: /home/ubuntu/ss-mm-e02r15/test/features/practice/application/practice_session_reducer_test.dart: happy path: idle → preparing → ready → countIn → running → finishing → completed
00:51 +701: /home/ubuntu/ss-mm-e02r15/test/features/practice/application/practice_session_reducer_test.dart: permission path: preparing → permissionRequired → preparing → ready
00:51 +702: /home/ubuntu/ss-mm-e02r15/test/features/practice/application/practice_session_reducer_test.dart: pause/resume: the resume count-in actually runs
00:51 +703: /home/ubuntu/ss-mm-e02r15/test/features/practice/application/practice_session_reducer_test.dart: pause during count-in is accepted
00:51 +704: /home/ubuntu/ss-mm-e02r15/test/features/practice/application/practice_session_reducer_test.dart: cancel before start: ready → cancelled
00:51 +705: /home/ubuntu/ss-mm-e02r15/test/features/practice/application/practice_session_reducer_test.dart: cancel during running: running → cancelled
00:51 +706: /home/ubuntu/ss-mm-e02r15/test/features/practice/application/practice_session_reducer_test.dart: failure and retry: preparing → failed → preparing
00:51 +707: /home/ubuntu/ss-mm-e02r15/test/features/practice/application/practice_session_reducer_test.dart: double start: the second StartPractice is rejected; state unchanged
00:51 +708: /home/ubuntu/ss-mm-e02r15/test/features/practice/application/practice_session_reducer_test.dart: double finish: the second FinishPractice is rejected
00:51 +709: /home/ubuntu/ss-mm-e02r15/test/features/practice/application/practice_session_reducer_test.dart: restart attempt: paused → countIn, attemptIndex +1, attemptElapsed 0
00:51 +710: /home/ubuntu/ss-mm-e02r15/test/features/practice/application/practice_session_reducer_test.dart: background interruption: PausePractice(PauseCause.interruption) preserves the cause on the state
00:51 +711: /home/ubuntu/ss-mm-e02r15/test/features/practice/application/practice_session_reducer_test.dart: exhaustive transition matrix every (status, input) pair matches the pinned table
00:51 +712: /home/ubuntu/ss-mm-e02r15/test/features/practice/application/practice_session_reducer_test.dart: exhaustive transition matrix rejected transitions return the input state by value
00:51 +713: /home/ubuntu/ss-mm-e02r15/test/features/practice/application/practice_session_reducer_test.dart: exhaustive transition matrix reducer never throws on any (status, input) pair
00:51 +714: /home/ubuntu/ss-mm-e02r15/test/features/practice/application/practice_session_reducer_test.dart: rejection carries from / input / code; never throws
00:51 +715: /home/ubuntu/ss-mm-e02r15/test/features/practice/application/practice_session_reducer_test.dart: StartPractice is rejected when target is null
00:51 +716: /home/ubuntu/ss-mm-e02r15/test/features/practice/application/practice_session_reducer_test.dart: ChangeTempoBeforeAttempt updates config.effectiveTempo and invalidates target
00:51 +717: /home/ubuntu/ss-mm-e02r15/test/features/practice/application/practice_session_reducer_test.dart: §6.1 source-purity guardrails reducer does not define its own beat-to-time formula (no bare `bpm` identifier, no `60` literal in arithmetic)
00:51 +718: /home/ubuntu/ss-mm-e02r15/test/features/practice/application/practice_session_reducer_test.dart: §6.1 source-purity guardrails reducer source does not contain DateTime.now, Stopwatch, Random, print
00:51 +719: /home/ubuntu/ss-mm-e02r15/test/features/practice/application/practice_session_reducer_test.dart: §6.1 source-purity guardrails reducer / command / effect files do not import Flutter or Riverpod
00:52 +720: /home/ubuntu/ss-mm-e02r15/test/features/practice/application/practice_session_clock_test.dart: MonotonicPracticeSessionClock now() before any start() returns zero in every field
00:52 +721: /home/ubuntu/ss-mm-e02r15/test/features/practice/application/practice_session_clock_test.dart: MonotonicPracticeSessionClock start() places the clock in a fresh session state
00:52 +722: /home/ubuntu/ss-mm-e02r15/test/features/practice/application/practice_session_clock_test.dart: MonotonicPracticeSessionClock start() is idempotent: repeated start() does not throw or distort
00:52 +723: /home/ubuntu/ss-mm-e02r15/test/features/practice/application/practice_session_clock_test.dart: MonotonicPracticeSessionClock active + paused == wall invariant holds after pause and resume
00:52 +724: /home/ubuntu/ss-mm-e02r15/test/features/practice/application/practice_session_clock_test.dart: MonotonicPracticeSessionClock pause() while paused is a no-op (state-machine fields unchanged)
00:52 +725: /home/ubuntu/ss-mm-e02r15/test/features/practice/application/practice_session_clock_test.dart: MonotonicPracticeSessionClock resume() while running is a no-op (state-machine fields unchanged)
00:52 +726: /home/ubuntu/ss-mm-e02r15/test/features/practice/application/practice_session_clock_test.dart: MonotonicPracticeSessionClock resetAttempt() zeros attempt; paused unchanged; wall/active unchanged
00:52 +727: /home/ubuntu/ss-mm-e02r15/test/features/practice/application/practice_session_clock_test.dart: MonotonicPracticeSessionClock start() while paused is a no-op (no fields reset)
00:52 +728: /home/ubuntu/ss-mm-e02r15/test/features/practice/application/practice_session_clock_test.dart: FakePracticeSessionClock now() before any start() returns zero in every field
00:52 +729: /home/ubuntu/ss-mm-e02r15/test/features/practice/application/practice_session_clock_test.dart: FakePracticeSessionClock start() places the clock in a fresh session state
00:52 +730: /home/ubuntu/ss-mm-e02r15/test/features/practice/application/practice_session_clock_test.dart: FakePracticeSessionClock start() is idempotent: repeated start() does not throw or distort
00:52 +731: /home/ubuntu/ss-mm-e02r15/test/features/practice/application/practice_session_clock_test.dart: FakePracticeSessionClock active + paused == wall invariant holds after pause and resume
00:52 +732: /home/ubuntu/ss-mm-e02r15/test/features/practice/application/practice_session_clock_test.dart: FakePracticeSessionClock pause() while paused is a no-op (state-machine fields unchanged)
00:52 +733: /home/ubuntu/ss-mm-e02r15/test/features/practice/application/practice_session_clock_test.dart: FakePracticeSessionClock resume() while running is a no-op (state-machine fields unchanged)
00:52 +734: /home/ubuntu/ss-mm-e02r15/test/features/practice/application/practice_session_clock_test.dart: FakePracticeSessionClock resetAttempt() zeros attempt; paused unchanged; wall/active unchanged
00:52 +735: /home/ubuntu/ss-mm-e02r15/test/features/practice/application/practice_session_clock_test.dart: FakePracticeSessionClock start() while paused is a no-op (no fields reset)
00:52 +736: /home/ubuntu/ss-mm-e02r15/test/features/practice/application/practice_session_clock_test.dart: FakePracticeSessionClock advance() grows wall by the delta while running
00:52 +737: /home/ubuntu/ss-mm-e02r15/test/features/practice/application/practice_session_clock_test.dart: FakePracticeSessionClock advance() while paused grows wall AND paused; active stays put
00:52 +738: /home/ubuntu/ss-mm-e02r15/test/features/practice/application/practice_session_clock_test.dart: FakePracticeSessionClock advance() after resume resumes active growth from the resume point
00:52 +739: /home/ubuntu/ss-mm-e02r15/test/features/practice/application/practice_session_clock_test.dart: FakePracticeSessionClock resetAttempt() after an active session only zeros attempt
00:52 +740: /home/ubuntu/ss-mm-e02r15/test/features/practice/application/practice_session_clock_test.dart: FakePracticeSessionClock start() after pause is a no-op (clock stays paused, fields intact)
00:52 +741: /home/ubuntu/ss-mm-e02r15/test/features/practice/application/practice_session_clock_test.dart: FakePracticeSessionClock pause() before start() is a no-op (no fields change)
00:52 +742: /home/ubuntu/ss-mm-e02r15/test/features/practice/application/practice_session_clock_test.dart: FakePracticeSessionClock resetAttempt() before start() is a no-op
00:52 +743: /home/ubuntu/ss-mm-e02r15/test/features/practice/application/practice_session_clock_test.dart: FakePracticeSessionClock active + paused == wall invariant holds across 200 random steps
00:52 +744: All tests passed!

    → [3] test test/features/practice/: ZÖLD

═══ [4] test test/property/chord_change_property_test.dart
    $ /home/ubuntu/flutter/bin/flutter test test/property/chord_change_property_test.dart

Resolving dependencies...
Downloading packages...
  _fe_analyzer_shared 99.0.0 (105.0.0 available)
  analyzer 12.1.0 (14.1.0 available)
  dio 5.10.0 (5.11.0 available)
  dio_web_adapter 2.2.0 (2.2.1 available)
  flutter_local_notifications 22.0.1 (22.2.0 available)
  flutter_local_notifications_platform_interface 12.0.0 (12.1.0 available)
  flutter_riverpod 3.3.2 (3.4.2 available)
  flutter_secure_storage_darwin 0.3.2 (0.4.0 available)
  flutter_secure_storage_platform_interface 2.0.1 (2.0.2 available)
  hooks 2.0.2 (2.1.0 available)
  intl 0.20.2 (0.20.3 available)
  jni 1.0.0 (1.0.3 available)
  jni_flutter 1.0.1 (1.0.2 available)
  matcher 0.12.19 (0.12.20 available)
  meta 1.18.0 (1.19.0 available)
  objective_c 9.4.1 (9.5.0 available)
  package_config 2.2.0 (3.0.0 available)
  package_info_plus 10.2.0 (10.2.1 available)
  permission_handler 12.0.3 (13.0.0 available)
  permission_handler_android 13.0.1 (14.0.0 available)
  permission_handler_apple 9.4.10 (9.5.0 available)
  permission_handler_html 0.1.3+5 (0.1.4+0 available)
  permission_handler_platform_interface 4.3.0 (4.4.0 available)
  permission_handler_windows 0.2.1 (0.2.2 available)
  record_use 0.6.0 (1.0.0 available)
  riverpod 3.3.2 (3.4.2 available)
  share_plus 13.2.0 (13.3.0 available)
  share_plus_platform_interface 7.1.0 (7.2.0 available)
  shared_preferences_android 2.4.26 (2.4.27 available)
  synchronized 3.4.1 (3.4.1+1 available)
  test 1.31.0 (1.31.2 available)
  test_api 0.7.11 (0.7.13 available)
  test_core 0.6.17 (0.6.19 available)
  uuid 4.5.3 (4.6.0 available)
  vector_math 2.2.0 (2.4.2 available)
  wakelock_plus 1.6.1 (1.7.0 available)
  wakelock_plus_platform_interface 1.5.1 (1.6.0 available)
  xml 6.6.1 (7.0.1 available)
Got dependencies!
38 packages have newer versions incompatible with dependency constraints.
Try `flutter pub outdated` for more information.
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

Resolving dependencies...
Downloading packages...
  _fe_analyzer_shared 99.0.0 (105.0.0 available)
  analyzer 12.1.0 (14.1.0 available)
  dio 5.10.0 (5.11.0 available)
  dio_web_adapter 2.2.0 (2.2.1 available)
  flutter_local_notifications 22.0.1 (22.2.0 available)
  flutter_local_notifications_platform_interface 12.0.0 (12.1.0 available)
  flutter_riverpod 3.3.2 (3.4.2 available)
  flutter_secure_storage_darwin 0.3.2 (0.4.0 available)
  flutter_secure_storage_platform_interface 2.0.1 (2.0.2 available)
  hooks 2.0.2 (2.1.0 available)
  intl 0.20.2 (0.20.3 available)
  jni 1.0.0 (1.0.3 available)
  jni_flutter 1.0.1 (1.0.2 available)
  matcher 0.12.19 (0.12.20 available)
  meta 1.18.0 (1.19.0 available)
  objective_c 9.4.1 (9.5.0 available)
  package_config 2.2.0 (3.0.0 available)
  package_info_plus 10.2.0 (10.2.1 available)
  permission_handler 12.0.3 (13.0.0 available)
  permission_handler_android 13.0.1 (14.0.0 available)
  permission_handler_apple 9.4.10 (9.5.0 available)
  permission_handler_html 0.1.3+5 (0.1.4+0 available)
  permission_handler_platform_interface 4.3.0 (4.4.0 available)
  permission_handler_windows 0.2.1 (0.2.2 available)
  record_use 0.6.0 (1.0.0 available)
  riverpod 3.3.2 (3.4.2 available)
  share_plus 13.2.0 (13.3.0 available)
  share_plus_platform_interface 7.1.0 (7.2.0 available)
  shared_preferences_android 2.4.26 (2.4.27 available)
  synchronized 3.4.1 (3.4.1+1 available)
  test 1.31.0 (1.31.2 available)
  test_api 0.7.11 (0.7.13 available)
  test_core 0.6.17 (0.6.19 available)
  uuid 4.5.3 (4.6.0 available)
  vector_math 2.2.0 (2.4.2 available)
  wakelock_plus 1.6.1 (1.7.0 available)
  wakelock_plus_platform_interface 1.5.1 (1.6.0 available)
  xml 6.6.1 (7.0.1 available)
Got dependencies!
38 packages have newer versions incompatible with dependency constraints.
Try `flutter pub outdated` for more information.
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
- **A2** (stabilitási küszöb három cella): a `chord_change_analyzer_test.dart` külön `179999 microseconds of stability remains unstable` és `180001 microseconds of stability is correct` cellája, valamint az A1 `recognises the first stable target chord with signed delay` pontos 180000 µs-os cellája → `179999→unstable`, `180000→correct`, `180001→correct`, tehát a `>=` mért.
- **A3** (késés-mátrix): `preserves early, on-time, late, and missing delay` (`+78`) — `-50 / 0 / +250 / null` mind zöld.
- **A4** (medián-küszöb): `uses a median only after three measured changes` (`+79`) — 2-re nincs, 3-ra 200, 4-re 250 ms.
- **A5** (irány / leglassabb): `treats direction as part of a chord pair` (`+80`) és `slowest pair tie-break is canonical and input-order independent` (`+81`).
- **A6** (UI szöveg-audit): `chord_change_view_test.dart` — az `insufficientSignal` / `noDetection` sem piros, a `Recognized and stable chord` az egyetlen correct-ágú szöveg, a `Detector label mapping is limited` látszik. A `marks lossy…` és a `renders no detection…` tesztek zöldek.
- **A7** (3/4 + külön 4/4): a `chord_change_analyzer_test.dart` `3/4 change on a bar boundary produces correct statistics` cellája `Meter(beatsPerBar: 3)` mellett a G `[0, 3s)` → D `[3s, 6s)` váltási határt a második ütemhatárhoz köti, majd `correct`, 100 ms késést és G→D páronkénti statisztikát vár. A külön `4/4 change on a bar boundary produces correct statistics` cella ugyanezt méri G `[0, 4s)` → D `[4s, 8s)` és `Meter(beatsPerBar: 4)` mellett.
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
