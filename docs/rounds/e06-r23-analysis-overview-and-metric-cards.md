# E06-R23 — Overview screen és metric cardok

- **Státusz:** PREPARED (előre megírva 2026-08-07, kód olvasva: main @ `a6e6f3d`)
- **SDD-kör:** [`docs/sdd/07-epic-06-audio-analysis-2.md`](../sdd/07-epic-06-audio-analysis-2.md) Kör 23; §25.1, §25.4–25.5, §25.8
- **Branch:** `minimax/e06-r23-analysis-overview-and-metric-cards`
- **Előfeltétel:** **E06-R20, E06-R22 merge**
- **Brief szerzője:** Claude (batch) · **Implementáció:** MiniMax M3 (UI-dominált kör, ADR 0069)

```ai-router
schema_version = 1
risk = "high"
allowed_paths = [
  "lib/features/audio_analysis/presentation/analysis_overview_screen.dart",
  "lib/features/audio_analysis/presentation/widgets/metric_card.dart",
  "lib/features/audio_analysis/presentation/widgets/insight_card.dart",
  "lib/features/audio_analysis/presentation/widgets/confidence_badge.dart",
  "lib/features/audio_analysis/presentation/widgets/signal_quality_card.dart",
  "lib/features/audio_analysis/presentation/analysis_metric_detail_screen.dart",
  "lib/features/audio_analysis/presentation/controllers/overview_view_model.dart",
  "lib/features/audio_analysis/public.dart",
  "lib/app/router/app_router.dart",
  "lib/l10n/app_en.arb",
  "lib/l10n/app_hu.arb",
  "test/features/audio_analysis/presentation/analysis_overview_screen_test.dart",
  "test/features/audio_analysis/presentation/metric_card_test.dart",
  "test/features/audio_analysis/presentation/overview_view_model_test.dart",
  "docs/rounds/e06-r23-analysis-overview-and-metric-cards.md",
]
gate_tests = [
  "test/features/audio_analysis",
  "test/app",
]
native_gate = false
```

> ⚠ **Pre-flight (KÖTELEZŐ):** friss `origin/main` + E06-R20/R22 merge.
> Olvasd újra a **tényleges** router-fájl útvonalát és alakját (a batch idején
> `lib/app/router/` feltételezett — ha a repo `go_router` konfigja máshol van,
> a fájllistát a pre-flight javítja), a `lib/core/theme/` token-fájlokat
> (`app_colors.dart`, `app_palette.dart`) és a `lib/core/widgets/app_card.dart`
> mintáját — **meglévő** kártya-primitívet kell újrahasználni, nem újat
> építeni. Ellenőrizd az R19 `CapabilityStatus` és `CapabilityUnavailableReason`
> ARB-kulcsait: a kártya azokat jeleníti meg. PREPARED→PLANNING.

## 0. Kör-jelzés és STOP-protokoll

```bash
tools/codex-signal.sh progress "<egy sor>" ; tools/codex-signal.sh done "<egy sor>"
tools/codex-signal.sh stopped "<egy sor>" ; tools/codex-signal.sh blocked "<egy sor>"
```

Lezáró jelzés nélkül a kör bukott. Listán kívüli fájl → `stopped`.
**STOP on scope conflict:** listán kívüli fájl kell → `stopped` + jelentés,
NEM néma létrehozás.

## 0.0 Tervezési baseline és pre-flight revízió

**PREPARED.** Új ADR nincs.

## 1. Cél

A V2 eredmény **capability-tudatos**, nem túlzsúfolt áttekintő képernyője:
elsődleges insight + erősség + következő gyakorlat + a fő metrikák + a
jelminőség — minden metrikán **érthető** megbízhatóság-jelzéssel és
**magyarázott** `unavailable` állapottal.

## 2. Jelenlegi állapot (mért, `a6e6f3d`)

- A mai `analyze_screen.dart` (432 sor) egyetlen képernyőn intéz mindent:
  felvétel-vezérlés, importálás, `TimelineView`, mentés a Libraryba, Lab-panel,
  megosztás, „gyakorlólecke ebből" akció. Importjai közt van a
  `library/public.dart`, `diagnostics/public.dart`, `learn/public.dart`,
  `settings/public.dart`, `share/public.dart`.
- **Nincs** overview-fogalom, **nincs** metrikakártya, **nincs**
  confidence-megjelenítés.
- Az elérhető közös UI-primitívek: `lib/core/widgets/app_card.dart`,
  `skeleton`, `gradient_text`, `brand_heading`, `empty_state.dart`, plusz a
  `core/theme/` tokenek.
- Az R20 adja az insighteket + rangsort, az R19 a státuszokat/confidence-t,
  az R22 a controllert és az állapotokat.

## 3. Scope

**Benne:** `AnalysisOverviewScreen` (a SDD §25.4 kilenc blokkjából az első
nyolc; a kilencedik — mentés/összehasonlítás/megosztás/Tutor — **gombhelyek**,
a bekötés az R25/R26/R27 dolga); újrahasználható `MetricCard` (öt állapot),
`InsightCard`, `ConfidenceBadge`, `SignalQualityCard`;
`AnalysisMetricDetailScreen` (egy metrika részletei);
`OverviewViewModel` (a dokumentumból **megjelenítési** modell — számítás
nélkül); route bekötés a `audioAnalysisV2Enabled` flag mögé; ARB en+hu.

**Kívül — TILOS:** timeline (R24), összehasonlítás (R25), export/megosztás
(R27), a V1 `analyze_screen.dart` módosítása, **bármilyen metrika-számítás**
a presentation rétegben.

## 4. Engedélyezett fájlok

| Útvonal | Állapot | Miért |
|---|---|---|
| `.../presentation/analysis_overview_screen.dart` | ÚJ | áttekintő |
| `.../presentation/widgets/metric_card.dart` | ÚJ | öt állapotú kártya |
| `.../presentation/widgets/insight_card.dart` | ÚJ | insight + action |
| `.../presentation/widgets/confidence_badge.dart` | ÚJ | megbízhatóság-jelzés |
| `.../presentation/widgets/signal_quality_card.dart` | ÚJ | felvételminőség |
| `.../presentation/analysis_metric_detail_screen.dart` | ÚJ | metrika-részletek |
| `.../presentation/controllers/overview_view_model.dart` | ÚJ | megjelenítési modell |
| `.../public.dart` | meglévő | képernyő export |
| `lib/app/router/app_router.dart` | meglévő | **additív** route, flag mögött |
| `lib/l10n/*.arb` | meglévő | **additív** kulcsok |
| `test/**` | ÚJ | widget + view model tesztek |

**Tilos zóna:** `lib/features/analyze/**`, `lib/features/audio_analysis/engine/**`,
`lib/features/audio_analysis/domain/**`, `lib/core/theme/**`.
Listán kívül → `stopped`.

## 5. Kötött architekturális döntések

1. **A presentation nem számol.** A kártya azt jeleníti meg, amit a
   dokumentum tartalmaz; a `OverviewViewModel` **formáz** (mértékegység,
   előjel, lokalizált szöveg), de **nem** aggregál, nem küszöböl, nem dönt
   státuszt. **NEM elfogadható:** `if (confidence > 0.7) status = available`
   a UI-ban — a státusz az R19-é.
2. **Öt kártya-állapot kötelező:** `available`, `degraded`, `unavailable`,
   `notApplicable`, **alacsony confidence**. Az `unavailable` **mindig**
   megjeleníti az **okot** és egy **javítási tanácsot**.
   **NEM elfogadható:** üres kártya, „—", vagy elrejtett metrika ok nélkül.
3. **Nincs color-only kódolás** (SDD §25.8): minden állapotot **szöveg vagy
   ikon** is hordoz. **NEM elfogadható:** kizárólag zöld/sárga/piros pötty.
4. **Nincs hamis score:** a UI nem alkot összesített „pontszámot" a
   metrikákból. **NEM elfogadható:** „Összpontszám: 78".
5. **Maximum-policy tiszteletben tartva** (R20): alapból **egy** javítandó,
   **egy** erősség, **egy** következő gyakorlat, **egy** felvételi warning; a
   többi „Részletek" mögött. **NEM elfogadható:** az összes insight kilistázása.
6. **A route a flag mögött:** `audioAnalysisV2Enabled == false` esetén a route
   **nem létezik** (nem csak üres képernyőt ad).
7. **Az akciógombok leíróból** (R20 `RecommendedAnalysisAction`) készülnek;
   a még be nem kötött akciók **letiltott** állapotban, magyarázattal
   jelennek meg. **NEM elfogadható:** olyan gomb, ami némán nem csinál semmit.

### 5.1 Nyitott döntések — előre rögzített feloldással

```yaml
open_decisions:
  - id: OD-01
    question: Hova kerül a képernyő a navigációban?
    blocking: true
    resolution_policy: use_default
    default: >-
      önálló route (`/analysis/overview`), a flag mögött; a V1 Analyze
      képernyő NEM kap belépőpontot rá ebben a körben (a V1 érintése tilos) —
      a belépő az R30 rollout-köréé. A teszt a route-ot közvetlenül nyitja.
  - id: OD-02
    question: A confidence hogyan jelenjen meg a normál felhasználónak?
    blocking: true
    resolution_policy: use_default
    default: >-
      három fokozat SZÖVEGGEL (SDD §19.5): "Magas megbízhatóság" /
      "Közepes megbízhatóság" / "Bizonytalan mérés"; a numerikus érték
      KIZÁRÓLAG Lab módban. A fokozathatárok az R19 küszöbei (0.7 / 0.4),
      a UI NEM vezet be sajátot.
  - id: OD-03
    question: Melyek a "fő" metrikák az overview-n?
    blocking: false
    resolution_policy: use_default
    default: >-
      timing (mean absolute error), rhythm (IOI konzisztencia), dynamics
      (stroke strength CV), harmony (chord szegmensszám) — kategóriánként
      EGY, a többi a detail képernyőn.
```

## 6. Acceptance criteria

- [ ] **Állapot-mátrix — öt cella:** ugyanaz a metrika `available`,
      `degraded`, `unavailable` (okkal), `notApplicable` és **alacsony
      confidence** állapotban — mind az öt kártya külön widget-teszttel,
      és az `unavailable` cellában a **ok szövege ÉS a tanács** megjelenik.
- [ ] **Dokumentum-mátrix — négy cella:** teljes eredmény; degradált eredmény;
      minden metrika `unavailable`; **érvényes, de üres** elemzés (csend) —
      mindegyik rendereldik **overflow nélkül**.
- [ ] **Overflow-mátrix:** **320 px** és **600 px** szélességen,
      `textScaleFactor` **1.0** és **2.0** mellett (4 kombináció) —
      **nincs** `RenderFlex overflow` (a teszt a `FlutterError` naplót nézi),
      és minden szöveg olvasható (nem `Ellipsis`-be vágott kulcsinformáció).
- [ ] **Nyelvi paritás:** magyar és angol locale-lal is rendereldik, és a
      megjelenő szövegek egyike sem a nyers kulcs (`analysisXyz` alak) —
      teszt méri mindkét nyelven.
- [ ] **Nincs color-only:** teszt méri, hogy minden állapot-jelzéshez tartozik
      **szöveges** `Semantics` label vagy látható címke.
- [ ] **Nincs számítás a UI-ban:** forrásolvasó teszt méri, hogy a
      `presentation/` fájlok nem importálnak `engine/` útvonalat, és nem
      tartalmaznak összehasonlítást confidence-küszöbre (`> 0.7`, `< 0.4`
      literál).
- [ ] **Maximum-policy:** olyan dokumentumra, ahol 9 insight van, az
      overview **pontosan 4** kártyát mutat, és a „Részletek" megnyitása után
      látszik a többi.
- [ ] **Flag-kapu:** `audioAnalysisV2Enabled == false` esetén a route
      **nem** oldható fel (a router-teszt ezt méri), és a V1 útvonalak
      változatlanok.
- [ ] **Letiltott akció magyarázattal:** a még be nem kötött akciógomb
      `enabled == false` **és** van hozzá tooltip/segédszöveg.
- [ ] **Szemantika:** minden kártya rendelkezik `Semantics` leírással, ami
      tartalmazza a metrika nevét, az értéket **és** a megbízhatóságot.
- [ ] **V1 érintetlen:** `git diff --stat` nem tartalmaz
      `lib/features/analyze/**` útvonalat.

> **Küszöb-konvenció:** minden numerikus küszöbhöz a mátrix **három** cellát
> ad — szigorúan **alatta**, pontosan **rajta**, szigorúan **fölötte** —, és a
> cellák értékei `python3 -c`-vel kiszámoltak, nem idealizált rácsból becsültek
> ([`docs/LESSONS.md`](../LESSONS.md) L13).

### 6.1 Mérce-mátrix — melyik hibás implementációt fogja pirosra

| Hibás implementáció | Melyik cella vált PIROSRA |
|---|---|
| A UI maga dönt státuszt confidence-küszöbből | a „nincs számítás a UI-ban" forrásolvasó cella |
| Az `unavailable` metrika elrejtve | az `unavailable` kártya „ok + tanács" cellája |
| Csak színnel jelzi az állapotot | a „nincs color-only" `Semantics` cella |
| Összesített pontszámot mutat | a „nincs hamis score" — a 4 dokumentum-cella egyike sem tartalmaz `Összpontszám` szöveget |
| Az összes insightot kilistázza | a „pontosan 4 kártya" cella |
| 320 px-en túlcsordul | az overflow-mátrix 320 px / 2.0 cellája |
| Hiányzó hu fordítás | a nyelvi paritás cella (nyers kulcs jelenik meg) |
| A route flag nélkül él | a flag-kapu router-cella |
| Néma, letiltás nélküli gomb | a letiltott-akció cella |
| **Valódi-sértés próba (§10):** egy metrikakártya `Semantics` labeljének ideiglenes törlése → a szemantika-cella **PIROS** → visszaállítás |

## 7. Kötelező ellenőrzések

```bash
tools/round-gate.sh test/features/audio_analysis test/app
```

Külön processzek, nincs `&&`/pipe/`tail`. A gate a `format` → `analyze` →
`test` → `architecture` lépéseket külön processzként futtatja; a kimenet
**csonkítatlan** (nincs `| tail`).

## 8. Implementációs sorrend

1. `overview_view_model.dart` (formázás, számítás nélkül) + unit-teszt.
2. RED: kártya-állapot mátrix (öt cella).
3. `confidence_badge.dart` + `metric_card.dart`.
4. `insight_card.dart` + `signal_quality_card.dart`.
5. `analysis_overview_screen.dart` + `analysis_metric_detail_screen.dart`.
6. Route a flag mögé; ARB en+hu.
7. Overflow-, nyelvi és szemantika-tesztek; gate.

## 9. Kockázatok

- **Az ARB kulcsok hiánya az egyik nyelven** csendben nyers kulcsot jelenít
  meg — a nyelvi paritás cella ezt fogja meg.
- **A `textScaleFactor: 2.0`** a leggyakoribb overflow-forrás — a mátrix
  kötelező, nem opcionális.
- **A V1 képernyő „gyors bekötése"** csábító, de tilos: a belépőpont az
  R30 rollout-döntése.

**STOP:** a V1 `analyze_screen.dart` módosítása, UI-oldali küszöbölés vagy
összesített pontszám bevezetése helyett `stopped` + brief-revízió.

## 10. Implementation handoff — az implementer tölti ki

_(üres)_

## 11. Review — a független reviewer tölti ki

Tervezett review: `docs/reviews/e06-r23-analysis-overview-and-metric-cards-review.md`.
Merge csak exact-SHA zöld CI, §4-en belüli diff és nulla OPEN BLOCKER/MAJOR után.
