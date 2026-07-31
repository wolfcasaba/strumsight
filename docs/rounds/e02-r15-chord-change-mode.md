# E02-R15 — Chord Change mód

- **Státusz:** **PREPARED** (előre megírva 2026-07-31, kód olvasva: `main` @ `ce8fbce`)
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

*(Fájlonkénti összefoglaló · a záró gate TÉNYLEGES, teljes kimenete · az A1–A10
pontok teljesülése bizonyítékkal · eltérések és okuk · follow-upok.)*

## 11. Review — Claude tölti ki

Link: `docs/reviews/e02-r15-review.md`

Kiemelt figyelem: az A2 három cellája (a `>=` mérése), az A3 „hiányzó ≠ nulla"
cellája, és egy **szöveg-audit** mindkét ARB-ben: állít-e bármelyik string
olyat, amit a detektor nem mér.
