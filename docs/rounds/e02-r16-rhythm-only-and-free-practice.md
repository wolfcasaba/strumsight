# E02-R16 — Rhythm-only és Free Practice mód

- **Státusz:** **PREPARED** (előre megírva 2026-07-31, kód olvasva: `main` @ `ce8fbce`)
- **SDD-kör:** [`docs/sdd/03-epic-02-practice-engine.md`](../sdd/03-epic-02-practice-engine.md) **„Kör 16"** (+ §7.4, §7.5, §20.4, §20.5)
- **Branch:** `codex/e02-r16-rhythm-and-free-practice`
- **Előfeltétel:** **E02-R14 merge-ölve** (közös highway); az R15 nem előfeltétel.
- **ADR:** **0082** — `docs/adr/0082-free-practice-honest-summary.md`, **az
  orchestrátor írja meg a pre-flightban** a §5 tartalmával.
- **Implementer motor:** a pre-flightban a user dönt. *Ajánlás:* **MiniMax M3**
  a nézetekre, **de** a §5.1 „nincs hamis score" invariáns szigorú mátrix-
  acceptance-szel — ha a user az egységes motort preferálja, Codex.

> ⚠ **Pre-flight (indítás előtt KÖTELEZŐ)**
> 1. Olvasd újra az R10 aggregátort: hogyan adja vissza a `freePracticeOpen`
>    profil az `overall`-t (`MetricNotApplicable` kell legyen).
> 2. Ellenőrizd az R11 controller `playingElapsed` kezelését — az „aktív idő"
>    ebből jön, nem a wall-órából.
> 3. ADR-szám ütközés ellenőrzése, majd az ADR 0082 megírása.
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

Két mód, egy közös elv: **ne állítsunk többet, mint amit mérünk.**

- **Rhythm-only** — célakkord nélküli ritmusgyakorlás: a timing számít, az
  akkord-dimenzió `notApplicable`, az irány opcionális.
- **Free Practice** — cél nélküli, **pontozatlan** session: a rendszer
  *tényeket* összegez (pengetésszám, le/fel arány, akkord-idővonal, detektált
  BPM-minták, tempó-stabilitás, aktív jel), és **semmilyen** pontszámot,
  pass/fail ítéletet vagy pontosságot nem közöl.

Ez a kör állítja elő továbbá a **streak-jogosultság pure predikátumát**
(SDD §20.5) — a streak-rendszerbe kötése az **E02-R19** dolga.

## 2. Jelenlegi állapot (mért tények, `main` @ `ce8fbce`)

- **Profilok (R03):** `ScoringProfile.rhythmOnlyDefault` (`rhythm: 100`) és
  `ScoringProfile.freePracticeOpen` (**üres** súlyok,
  `completionThresholdPercent = 0`, `overallThresholdPercent = 0`).
- **Módok (R03):** a `PracticeMode` enum tartalmazza a `rhythmOnly` és a
  `freePractice` értéket; a `BuiltinPracticeCatalog` (R04) **már szállít**
  rhythm-only gyakorlatot és free-practice sablont.
- **Adapterek (R05):** az **eseménymentes** Analyze-import szándékosan
  `freePractice` módot kap (ADR 0071) — tehát a Free Practice útnak már ma van
  valódi tartalmi forrása.
- **Metrika-modell (R03):** `MetricNotApplicable` és `MetricInsufficientData`
  létezik — a „nincs adat" **nem** 0-ként ábrázolandó.
- **Aktív idő (R07/R11):** `PracticeSessionState.playingElapsed` — a doc-comment
  szerint „a daily goal kizárólag ezt használja (SDD §12.2)". A count-in
  (`countInElapsed`) és a pause (`pausedElapsed`) **külön** akkumulátor.
- **A mai (legacy) streak-út:** `streakProvider.recordPracticeToday()`
  (`learn_screen.dart:284`) — bármilyen befejezett lecke rögzít. Jogosultsági
  predikátum **nincs** (mérve: `grep -rn "eligib" lib/` → 0 találat).
- **Detektált BPM:** a `LiveFrame.bpm` mező létezik; a Free Practice
  összegzésének ez a bemenete (a gatewayen keresztül, R08).

## 3. Scope

**Benne:** a Free Practice összegző (pure), a streak-jogosultsági predikátum
(pure), a két mód-nézet, ARB-kulcsok, tesztek.

**Kívül (ebben a körben TILOS):**

- A streak/daily goal **bekötése** a valódi rendszerbe — **Kör 19**. Itt csak a
  predikátum és a mérőszámok készülnek el, hívó nélkül.
- Result-képernyő (Kör 18), Speed Builder (Kör 17), Chord Change (Kör 15).
- A scorerek, az aggregátor, a controller **viselkedésének** módosítása.
- `lib/features/learn/**`, `lib/features/streak/**`, `lib/features/progress/**`.
- Új ADR, `docs/sdd/**`, `HANDOFF.md`, `.github/**`, DSP.

## 4. Engedélyezett fájlok

| Útvonal | Új? | Miért |
|---|---|---|
| `lib/features/practice/domain/model/free_practice_summary.dart` | **ÚJ** | pontszám-mentes összegző modell |
| `lib/features/practice/domain/service/free_practice_summarizer.dart` | **ÚJ** | pure összegző (megfigyelések → tények) |
| `lib/features/practice/domain/service/practice_session_eligibility.dart` | **ÚJ** | streak-jogosultsági predikátum (pure, hívó nélkül) |
| `lib/features/practice/presentation/views/rhythm_only_view.dart` | **ÚJ** | mód-nézet |
| `lib/features/practice/presentation/views/free_practice_view.dart` | **ÚJ** | mód-nézet (élő tények, nincs score) |
| `lib/features/practice/presentation/screens/practice_session_screen.dart` | — | **CSAK** a két mód-nézet becsatolása |
| `lib/l10n/app_en.arb` · `lib/l10n/app_hu.arb` | — | új kulcsok mindkét nyelven |
| `test/features/practice/domain/free_practice_summarizer_test.dart` | **ÚJ** | A2–A5 |
| `test/features/practice/domain/practice_session_eligibility_test.dart` | **ÚJ** | A6 küszöb-mátrix |
| `test/features/practice/presentation/rhythm_only_view_test.dart` | **ÚJ** | A1 |
| `test/features/practice/presentation/free_practice_view_test.dart` | **ÚJ** | A7–A8 |
| `test/property/free_practice_property_test.dart` | **ÚJ** | A9 |
| `docs/rounds/e02-r16-rhythm-only-and-free-practice.md` | — | **CSAK a §10** |

**Tilos zóna:** minden más, nevezetesen `lib/features/streak/**`,
`lib/features/progress/**`, `lib/features/learn/**`,
`lib/features/practice/application/**`, `data/**`, `docs/adr/**`.

**Új fájl a listán kívül = scope-sértés** → `stopped`.

## 5. Kötött döntések (ADR 0082 — NEM tárgyalhatók)

1. **Free Practice alatt NINCS:** miss, pass/fail, overall accuracy, combo,
   „jól/rosszul játszottál" állítás. A modellben ez azt jelenti, hogy az
   `overall` **`MetricNotApplicable`** (nem 0, nem null-ként ábrázolt hiány).
2. **A Free Practice összegző csak tényeket ad:** pengetésszám, le/fel eloszlás
   (darabszám **és** arány), akkord-idővonal (címke + időtartam), detektált
   BPM-minták, tempó-stabilitás, aktív jel időtartama.
3. **Tempó-stabilitás definíciója.** A szomszédos pengetések közti intervallumok
   **mediántól** vett abszolút eltéréseinek mediánja (MAD-jellegű, outlier-tűrő),
   és **csak** akkor számolható, ha legalább **négy** pengetés van (három
   intervallum). Egyébként `MetricInsufficientData`.
4. **Rhythm-only:** a chord-dimenzió `notApplicable`; az irány **opcionális** —
   ha a definíció eseményei nem hordoznak irányt, a direction-dimenzió is
   `notApplicable`, **nem** 0.
5. **Az extra pengetés Rhythm-onlyban informatív.** A `ExtraStrumPolicy.ignore`
   mellett az extra pengetés **számlálódik és megjelenik**, de **nem** von le
   pontot és **nem** jelenik meg hibaként (SDD §22.4: kezdőt ne büntessünk).
6. **Aktív idő = `playingElapsed`.** Sem a count-in, sem a pause, sem a setup
   nem számít bele — se a Free Practice összegzőbe, se a jogosultságba.
7. **Streak-jogosultság (SDD §20.5), pure predikátum, hívó nélkül:**

   ```text
   eligible = activeDuration >= 20 s
           || resolvedRequiredTargets >= 4
           || freePracticeStrums >= 8
   ```

   Mindhárom feltétel **`>=`**. A predikátum ebben a körben **nincs bekötve**
   sehová (a bekötés a Kör 19), de teljes mátrix-fedéssel tesztelt.
8. **Nincs kitalált adat.** Ha egy mérőszám nem számolható (nincs elég minta),
   a modell `MetricInsufficientData`-t ad, és a UI **nem** mutat helyette
   nullát vagy kötőjelet pontszám-szerű formában.

## 6. Acceptance criteria

### A1 — Rhythm-only dimenzió-mátrix

| Definíció | `chord` | `direction` | `rhythm` |
|---|---|---|---|
| irány nélküli események, akkord nélkül | `NotApplicable` | **`NotApplicable`** | `Available` |
| irányos események, akkord nélkül | `NotApplicable` | `Available` | `Available` |
| nulla megfigyelés érkezett | `NotApplicable` | `InsufficientData` | `InsufficientData` |

***Pirosra fogja:*** a „nincs akkord → chord = 0%" implementáció.

### A2 — Free Practice: nulla score minden ágon

- `overall` == `MetricNotApplicable` **minden** free-practice futásra
  (üres session, hosszú session, sok pengetés, nulla pengetés).
- A `PracticeAttemptResult.outcome` **`notScored`** (a meglévő enum értéke),
  soha nem `passed`/`failed`.
- A verdict-lista **üres** (nincs célesemény), és `totalTargets == 0`.

**NEM elfogadható gyengítés:** „a UI úgyis elrejti" — a modellben kell
helyesnek lennie, mert az R18 result és az R19 progress ebből olvas.

### A3 — Pengetésszám és le/fel eloszlás

10 pengetés (7 le, 3 fel) → `strumCount == 10`, `downCount == 7`,
`upCount == 3`, és az arány a **kiszámolt** érték (70% / 30%). Nulla pengetés →
a **darabszámok 0**, az **arány `InsufficientData`** (nem 0%).

***Pirosra fogja:*** a `0/0` osztás nullaként elfedése.

### A4 — Tempó-stabilitás: három cella a minimum-mintaszámra

| Pengetések száma | Elvárt |
|---|---|
| **3** | `InsufficientData` |
| **4** | számolt érték |
| 12 egyenletes (500 ms) | stabilitás = **0** eltérés |
| 12, közte egy 1500 ms-os kihagyás | a mediánt az outlier **nem** rántja el (az érték a mediánhoz közel marad) |

A számokat `python3 -c`-vel ellenőrizd.

***Pirosra fogja:*** az átlag+szórás alapú „stabilitás", amit egyetlen szünet
tönkretesz.

### A5 — Akkord-idővonal összegzés

Három egymást követő akkord-megfigyelés (`G` 4 s, `null` 1 s, `C` 3 s) →
az idővonal **három** szegmenst ad a helyes időtartamokkal; a `null` szegmens
**explicit „nincs akkord"**, nem kihagyott lyuk.

### A6 — Streak-jogosultság: három cella minden feltételre

| Feltétel | alatta | **rajta** | fölötte |
|---|---|---|---|
| aktív idő | 19 999 ms → false | **20 000 ms → true** | 20 001 ms → true |
| feloldott kötelező cél | 3 → false | **4 → true** | 5 → true |
| free-practice pengetés | 7 → false | **8 → true** | 9 → true |

Plusz: mindhárom feltétel alatta → **false**; bármelyik teljesül → **true**
(VAGY-kapcsolat), és a **rövid first-win** eset (kevés cél, rövid idő, de
`resolvedRequiredTargets >= 4`) → **true**.

***Pirosra fogja:*** az ÉS-kapcsolat, és a `>` / `>=` felcserélése bármelyik
küszöbön.

### A7 — A Free Practice nézet nem hazudik

- A felületen **nincs** „accuracy", „pontosság", „%", „pass", „score" jellegű
  megjelenítés (forrás- és ARB-szintű állítás mindkét nyelvre).
- Az `InsufficientData` mérőszámok lokalizált „még nincs elég adat" szöveget
  kapnak, **nem** 0-t vagy `—`-t pontszám formában.
- Nulla jel esetén a nézet **explicit** „nem hallottunk pengetést" állapotot mutat.

### A8 — a11y, i18n, layout

Címke + akció egy szemantikus node-on; a jelentés nem csak szín; angol/magyar
felépülés; `l10n_parity_test` zöld; 320×568 és 915×412 méreten nincs overflow;
200%-os szövegméretnél sincs.

### A9 — Randomizált property gate

`test/property/free_practice_property_test.dart`, `PROPERTY_SEED` (hiány → 42):

1. az összegző **soha nem dob** kivételt tetszőleges megfigyelés-sorozatra;
2. `downCount + upCount == strumCount` **minden** futásra;
3. free-practice futásból **soha** nem keletkezik `MetricAvailable` overall;
4. a jogosultsági predikátum **monoton**: egy pengetés/másodperc hozzáadása
   `true`-ból nem csinál `false`-ot;
5. az idővonal szegmensek időtartamainak összege ≤ az aktív idő.

### A10 — Domain-tisztaság és scope

`domain_purity_test.dart` zöld; architecture gate zöld; `git diff --stat` a §4
listáján belül; `lib/features/streak/`, `lib/features/progress/`,
`lib/features/learn/` **0 sor**.

## 7. Implementációs sorrend (ez a TERVED)

1. Olvasd el: ADR 0082, `practice_metrics.dart`, `scoring_profile.dart`
   (`rhythmOnlyDefault`, `freePracticeOpen`), az R10 aggregátor, és az
   `analyze_practice_adapter.dart` (miért `freePractice`).
2. `free_practice_summary.dart` modell.
3. `free_practice_summarizer.dart` (A3–A5).
4. `practice_session_eligibility.dart` + a teljes mátrix (A6).
5. `rhythm_only_view.dart` (A1) és `free_practice_view.dart` (A7).
6. a11y/i18n/layout (A8), property (A9).
7. Záró gate (§9), majd a §10 kitöltése.

## 8. Kockázatok

- **A „mutassunk valamit" nyomás.** Egy üres Free Practice összegzés csúnya —
  de a hamis 0% rosszabb. A §5.1 és az A2 pont ezt védi.
- **A jogosultsági predikátum bekötésének csábítása.** A streak- és
  progress-fájlok tilos zónában vannak; a bekötés az R19. Ha „csak egy sor
  lenne", akkor is `stopped`.
- **A tempó-stabilitás definíciója.** Átlag+szórás helyett medián-alapú —
  ez szándékos, mert egy szünet nem jelent instabil tempót.
- **A `null` akkord-címke.** Ez a modellben **explicit** érték, nem hiányzó
  adat; az idővonalon is meg kell jelennie.
- **`AsyncValue.value`** (nullable), **NEM** `.valueOrNull`.

## 9. Záró gate — szó szerint ez az egyetlen hívás

```
tools/round-gate.sh test/features/practice/ test/property/free_practice_property_test.dart test/core/l10n_parity_test.dart
```

Csővezeték nélkül, a teljes kimenetet a §10-be. A teljes suite + property gate +
APK a CI-ban fut (ADR 0053) — `gh`-t NE hívj.

## 10. Implementation handoff — az IMPLEMENTER tölti ki

*(Fájlonkénti összefoglaló · a záró gate TÉNYLEGES, teljes kimenete · az A1–A10
pontok teljesülése bizonyítékkal · eltérések és okuk · follow-upok.)*

## 11. Review — Claude tölti ki

Link: `docs/reviews/e02-r16-review.md`

Kiemelt figyelem: **szöveg-audit** mindkét ARB-ben (A7), az A6 kilenc
küszöb-cellája, és **valódi-sértés próba** az A2-re (ideiglenesen
`MetricAvailable(0)` overall a free-practice úton → pirosnak kell lennie).
