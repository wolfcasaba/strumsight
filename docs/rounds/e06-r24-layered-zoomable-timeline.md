# E06-R24 — Többrétegű, zoomolható timeline

- **Státusz:** PLANNING (pre-flight felülvizsgálva 2026-08-13, main @ `4d2ff97`)
- **SDD-kör:** [`docs/sdd/07-epic-06-audio-analysis-2.md`](../sdd/07-epic-06-audio-analysis-2.md) Kör 24; §25.6–25.8
- **Branch:** `terra/e06-r24-layered-zoomable-timeline`
- **Előfeltétel:** **E06-R23 merge** — teljesítve (PR #241, squash `d5a95e44`)
- **Brief szerzője:** Claude (batch) · **Implementáció:** Terra (`.pipeline/engine-override`, 2026-08-08 motor-felállás — AGENTS.md §15.6.1)

```ai-router
schema_version = 1
risk = "high"
allowed_paths = [
  "lib/features/audio_analysis/presentation/analysis_timeline_screen.dart",
  "lib/features/audio_analysis/presentation/widgets/timeline_lane.dart",
  "lib/features/audio_analysis/presentation/widgets/timeline_lanes.dart",
  "lib/features/audio_analysis/presentation/widgets/timeline_ruler.dart",
  "lib/features/audio_analysis/presentation/widgets/hotspot_navigator.dart",
  "lib/features/audio_analysis/presentation/controllers/timeline_view_state.dart",
  "lib/features/audio_analysis/presentation/controllers/timeline_viewport.dart",
  "lib/features/audio_analysis/public.dart",
  "lib/app/routing/app_router.dart",
  "lib/app/routing/app_route.dart",
  "lib/l10n/app_en.arb",
  "lib/l10n/app_hu.arb",
  "test/features/audio_analysis/presentation/analysis_timeline_screen_test.dart",
  "test/features/audio_analysis/presentation/timeline_viewport_test.dart",
  "test/features/audio_analysis/presentation/hotspot_navigator_test.dart",
  "docs/rounds/e06-r24-layered-zoomable-timeline.md",
  "docs/adr/0243-analysis-timeline-lane-data-source-and-degraded-boundary.md",
]
gate_tests = [
  "test/features/audio_analysis",
  "test/app",
]
native_gate = false
```

> ⚠ **Pre-flight (KÖTELEZŐ):** friss `origin/main` + E06-R23 merge — teljesítve.
> Olvasd újra a `lib/features/analyze/widgets/timeline_view.dart`-ot (170 sor)
> — az a **kompatibilitási** nézet, ami **változatlan** marad, és a
> `test/features/analyze/timeline_view_test.dart` az őre. **A tényleges router
> fájl `lib/app/routing/app_router.dart` és a route-katalógus
> `lib/app/routing/app_route.dart`** — a `lib/app/router/` **NEM létezik**
> (ld. §0.0 2. javító pre-flight, ez a header-korrekció ELŐZŐ verziója
> tévesen „mérve, létezik"-nek jelölte).
> Az R23 `OverviewViewModel` (`presentation/controllers/overview_view_model.dart`)
> a formázást az `OverviewLabels` portra delegálja; a konkrét megvalósítás
> `AppLocalizationsOverviewLabels`
> (`presentation/widgets/labels_adapter.dart`) — a timeline
> `formatDuration`/`formatDbfs`/`formatRatio`/`formatMetricValue` hívásokhoz
> **ezt** használja újra (import, nem duplikálás); egyik fájl sincs a kör
> engedélyezett listáján, csak OLVASva/importálva. PREPARED→PLANNING kész,
> lásd §0.0 a mért eltérésekért és a döntésekért.

## 0. Kör-jelzés és STOP-protokoll

```bash
tools/codex-signal.sh progress "<egy sor>" ; tools/codex-signal.sh done "<egy sor>"
tools/codex-signal.sh stopped "<egy sor>" ; tools/codex-signal.sh blocked "<egy sor>"
```

Lezáró jelzés nélkül a kör bukott. Listán kívüli fájl → `stopped`.
**STOP on scope conflict:** listán kívüli fájl kell → `stopped` + jelentés.

## 0.0 Tervezési baseline és pre-flight revízió

**2026-08-13 pre-flight, main @ `4d2ff97`.** A batch-brief nem nevezett meg
konkrét `AnalysisDocument`-mezőt egyik lane-hez sem, és három tényleges
eltérést tartalmazott, amelyeket ez a revízió a dispatch előtt felold:

1. **`fl_chart` NEM függősége a projektnek** (mérve: nulla találat a
   `pubspec.yaml`-ben és a `lib/`-ben) — a §2 „A `fl_chart` a projekt
   függősége" állítás téves. A `pubspec.yaml` amúgy sincs az engedélyezett
   fájllistán, tehát hozzáadása scope-sértés lenne. Minden lane natív Flutter
   widget/`CustomPainter` rajzolással készül, harmadik féltől függő
   chart-csomag nélkül.
2. **OD-01 „ADR 0202" hivatkozása elavult sorszám** — a 0200–0205 blokk
   0215–0220-ra tolódott (ld. [ADR 0217](../adr/0217-analysis-raw-audio-retention.md)
   fejléce, „Sorszám-jegyzet"). A helyes hivatkozás **ADR 0217**
   (raw audio retention); az OD-01 döntése (nyers PCM UI-ba töltése tilos)
   változatlan, csak a sorszám javult.
3. **Branch- és implementer-mező frissítve** a 2026-08-08 motor-felállásra
   (`terra`, ld. fejléc) — a batch-brief a korábbi `minimax` queue-értéket
   örökölte, a tényleges implementer a `.pipeline/engine-override` szerint
   Terra.

**2026-08-13, 2. javító pre-flight (implementer STOP, 0 munka végezve).** Az
első dispatch (Terra) a brief `lib/app/router/app_router.dart`
`allowed_paths`-bejegyzését ellenőrizve azonnal, helyesen `stopped`-ot
jelzett: ez az útvonal **nem létezik** — a tényleges, flag-gate-elt router
`lib/app/routing/app_router.dart` (ugyanaz a hiba, amit az R23 testvérkör
saját pre-flightja már egyszer kimért és javított — ld. R23 §0.0 1. pont —,
de ez a brief batch-authoring idején örökölte, és a jelen kör ELSŐ
pre-flightja tévesen „mérve, létezik"-nek jelölte a fejlécben ahelyett, hogy
ténylegesen futtatott volna egy `test -e` ellenőrzést). Az implementer NULLA
fájlt módosított, csak jelzett — a branch a pre-flight commit óta
változatlan (`1348c3f6`).

**Feloldás:** `allowed_paths` és §4 javítva
`lib/app/routing/app_router.dart`-ra; hozzáadva
`lib/app/routing/app_route.dart` (a route-katalógus — a timeline útvonalnak
**új konstansra** van szüksége, ugyanúgy, ahogy az R23 `analysisOverview`/
`analysisMetricDetail` konstansai is ebben a fájlban élnek, nem a
router-fájlban). **Flag-döntés (nincs új flag):** a `lib/app/config/
feature_flags.dart` NINCS az engedélyezett listán, tehát a timeline route a
MEGLÉVŐ `audioAnalysisV2Enabled` flaget használja — ugyanazt, mint az R23
`analysisOverview`/`analysisMetricDetail` route párja —, nem vezet be külön
`analysisTimelineEnabled` sub-flaget.

**ADR:** [0243](../adr/0243-analysis-timeline-lane-data-source-and-degraded-boundary.md)
— nyolc lane → konkrét, mért `AnalysisDocument`-mező leképezés (chord=
`timeline.chordSegments`, beat/bar=`timeline.beats`+`.bars`+`.tempoPoints`,
strum/onset=`timeline.events` szűrve `OnsetEvent`/`StrumEvent`-re,
dynamics=`timeline.dynamicPoints`, pitch=`timeline.pitchSegments`,
hotspot overlay=`document.hotspots`, timing error=`document.hotspots.where(kind
== timing)`, waveform=mindig `unavailable`); a gazdagabb, csak
engine-belüli R12/R17 típusok (`BeatGrid`, `TempoCurvePoint`,
`MonophonicPitchSegment`) NEM lane-bemenetek; a `CapabilityStatus.degraded`
**látható marad** figyelmeztető jelzéssel (nem esik egy kategóriába a
rejtett `unavailable`/`notApplicable`-lel — ld. a kilencedik mátrix-cellát
§6-ban); hiányzó `CapabilityReport`-bejegyzés fail-closed `unavailable`. A
kód-ellenőrzés részletei és a citációk az ADR-ben.

## 1. Cél

A részletes időbeli evidence **interaktív** megjelenítése: capability szerint
megjelenő sávok, zoom/pan, tartomány-kijelölés, hotspot-navigáció — hosszú
sessionön is **virtualizált** rendereléssel és **szöveges** accessibility
alternatívával.

## 2. Jelenlegi állapot (mért, `a6e6f3d`)

- A mai `timeline_view.dart` (170 sor) **egyetlen**, nem zoomolható nézet:
  a `TimelineChord` szegmenseket és a `TimelineStrum` ↓/↑ jeleket rajzolja
  egy fix szélességű sávon. **Nincs** zoom, pan, kijelölés, hotspot vagy
  waveform.
- A `session_detail_screen.dart` ugyanezt a widgetet használja a mentett
  sessionre.
- Az R10/R11/R12/R14/R16/R17 adják az event-, szegmens-, beat-, timing-,
  dinamika- és pitch-adatokat; az R20 a hotspotokat.
- A `fl_chart` **NEM** függősége a projektnek (mérve, 2026-08-13 — §0.0/ADR
  0243): nulla találat a `pubspec.yaml`-ben és a `lib/`-ben. A `pubspec.yaml`
  nincs a kör engedélyezett fájllistáján, tehát hozzáadása scope-sértés
  lenne — minden lane natív Flutter widget/`CustomPainter` rajzolással
  készül.

## 3. Scope

**Benne:** `AnalysisTimelineScreen`; lane-architektúra (waveform preview,
chord, beat/bar, strum/onset, timing error, dynamics, pitch, hotspot overlay —
**capability szerint** megjelenítve); `TimelineViewport` (zoom, pan, min/max
zoom, tartomány-kijelölés — **tiszta, tesztelhető** logika widget nélkül);
`TimelineRuler` (adaptív időcímkék); `HotspotNavigator` (előző/következő);
lane elrejtés/megjelenítés; **virtualizált** rajzolás; szöveges
accessibility-összefoglaló minden sávhoz; ARB.

**Kívül — TILOS:** a V1 `timeline_view.dart` módosítása, összehasonlítás
(R25), export (R27), bármilyen számítás a presentation rétegben.

## 4. Engedélyezett fájlok

| Útvonal | Állapot | Miért |
|---|---|---|
| `.../presentation/analysis_timeline_screen.dart` | ÚJ | képernyő |
| `.../presentation/widgets/timeline_lane.dart` | ÚJ | egy sáv |
| `.../presentation/widgets/timeline_lanes.dart` | ÚJ | sáv-kompozíció |
| `.../presentation/widgets/timeline_ruler.dart` | ÚJ | adaptív időskála |
| `.../presentation/widgets/hotspot_navigator.dart` | ÚJ | hotspot ugrás |
| `.../presentation/controllers/timeline_view_state.dart` | ÚJ | nézetállapot |
| `.../presentation/controllers/timeline_viewport.dart` | ÚJ | zoom/pan matek (tiszta) |
| `.../public.dart` | meglévő | export |
| `lib/app/routing/app_router.dart` | meglévő | **additív** route, flag mögött |
| `lib/app/routing/app_route.dart` | meglévő | **additív** route-konstans (`AppRoutes.analysisTimeline`) |
| `lib/l10n/*.arb` | meglévő | **additív** kulcsok |
| `test/**` | ÚJ | viewport + widget + navigátor teszt |
| `docs/adr/0243-analysis-timeline-lane-data-source-and-degraded-boundary.md` | ÚJ (pre-flight) | lane-adatforrás + degraded döntés |

**Tilos zóna:** `lib/features/analyze/**`, `lib/features/audio_analysis/engine/**`,
`lib/features/audio_analysis/domain/**`. Listán kívül → `stopped`.

## 5. Kötött architekturális döntések

1. **A zoom/pan matek tiszta és widget-mentes:** a `TimelineViewport`
   unit-tesztelhető, `BuildContext` nélkül. **NEM elfogadható:** a
   transzformáció a `CustomPainter`-be temetve.
2. **Virtualizált rajzolás:** a látható tartományon **kívüli** eventek nem
   kapnak widgetet és nem kerülnek a rajzolási listába. Ezt **számláló**
   méri (a lane a ténylegesen feldolgozott elemek számát kiadja) — a mérés
   **eszköze**. **NEM elfogadható:** 5 000 event → 5 000 widget.
3. **A sáv capability szerint jelenik meg:** `unavailable`/`notApplicable`
   capability esetén a sáv **magyarázattal** rejtve van, nem üresen kirajzolva.
   **NEM elfogadható:** üres pitch-sáv indoklás nélkül. **`degraded`
   (ADR 0243):** a sáv **látható marad**, explicit figyelmeztető jelzéssel
   (pl. `ConfidenceBadge`-mintájú ikon+szöveg) — **NEM** esik egy kategóriába
   a rejtett `unavailable`/`notApplicable` ágakkal.
4. **Minden sávhoz szöveges összefoglaló** (SDD §25.8): a grafikon
   információja `Semantics`-en keresztül **szövegként** is elérhető.
   **NEM elfogadható:** kizárólag vizuális információ.
5. **A zoom korlátos:** `minZoom` = a teljes klip elfér; `maxZoom` = a
   dokumentált legfinomabb felbontás; a viewport **soha** nem hagyja el a
   `[0, duration]` tartományt. **NEM elfogadható:** végtelen zoom vagy
   a klipen kívülre csúszó ablak.
6. **A V1 `timeline_view.dart` érintetlen** és továbbra is a
   `session_detail_screen` nézete.
7. **Nincs számítás a UI-ban:** a sávok kész adatokat rajzolnak.

### 5.1 Nyitott döntések — előre rögzített feloldással

```yaml
open_decisions:
  - id: OD-01
    question: Honnan jön a waveform preview?
    blocking: true
    resolution_policy: use_default
    default: >-
      a dokumentumban tárolt, LERITKÍTOTT preview-burkoló (min/max párok,
      legfeljebb 2000 pont) — ha az R21 dokumentuma NEM tartalmaz ilyet, a
      waveform sáv `unavailable` (`modelUnavailable` helyett a
      dokumentált "nincs preview adat" ok), és a többi sáv fut. NYERS PCM
      betöltése a UI-ba TILOS (ADR 0217 — a brief eredeti "ADR 0202"
      hivatkozása elavult sorszám volt, ld. §0.0).
  - id: OD-02
    question: Mekkora a maxZoom?
    blocking: true
    resolution_policy: use_default
    default: >-
      olyan, hogy 1 logikai pixel = 1 ms (azaz a látható ablak minimum
      szélessége a képernyő szélessége ms-ban); a minZoom a teljes klip.
      Mindkettő néven nevezett konstans.
  - id: OD-03
    question: Gesztusok?
    blocking: false
    resolution_policy: use_default
    default: >-
      pinch zoom + vízszintes pan; a tartomány-kijelölés hosszú nyomás +
      húzás. A teszt a VIEWPORT API-ját hívja közvetlenül, nem szimulál
      multi-touch gesztust.
```

## 6. Acceptance criteria

- [ ] **Viewport-mátrix — kilenc cella (tiszta unit-teszt):** zoom be/ki a
      középpont körül; pan balra/jobbra; **minZoom** és **maxZoom** elérése;
      pan a **bal** és a **jobb** széllel ütközve; zoom a klip széléhez közel
      (az ablak nem lóg ki). Mindegyikben a `[start, end]` a `[0, duration]`-on
      belül marad.
- [ ] **Zoom-küszöb hármas:** `maxZoom` mellett az ablak szélessége
      **a küszöb alatt / pontosan a küszöbön / fölötte** — a **pontosan a
      küszöbön** lévő zoom **elfogadott** (inkluzív), a szűkebb **clamp-elve**
      van. A három értéket `python3 -c`-vel számolva a képernyőszélességből
      (pl. 400 logikai px → minimum ablak **400 ms**; a cellák
      **399 / 400 / 401 ms**).
- [ ] **Virtualizáció:** **5 000** eventes dokumentum, a látható ablakban
      **50** eventtel → a lane feldolgozott-elem számlálója **≤ 100**
      (a határérték a briefben rögzített: látható + egy képernyőnyi tartalék);
      és a widget-fa mélysége/eleme nem nő lineárisan az 5 000-rel.
- [ ] **Sáv-mátrix — nyolc cella:** mind a nyolc sáv **megjelenik**, ha a
      capability `available`; és **rejtve, magyarázattal**, ha `unavailable`
      vagy `notApplicable`. A pitch- és a timing-sávra külön cella
      (ezek a leggyakrabban hiányzók).
- [ ] **Degraded-cella (kilencedik, ADR 0243):** `CapabilityStatus.degraded`
      esetén a sáv **látható marad**, explicit figyelmeztető jelzéssel — ez a
      cella külön a nyolc fő cellától, mert egy `available`-re és
      `unavailable`-re helyesen reagáló implementáció is hibásan kezelheti a
      `degraded`-et (pl. az `unavailable` ághoz sorolva elrejtheti).
- [ ] **Hotspot-navigáció:** 3 hotspot esetén a „következő" háromszor lépve
      körbeér vagy megáll (a szerződés szerint, dokumentáltan), és a viewport
      **tartalmazza** a hotspot tartományát minden lépés után.
- [ ] **Adaptív címkék:** 5 s-os és 300 s-os klipen a `TimelineRuler`
      **eltérő** címkesűrűséget ad (nem ugyanaz a lépésköz), és egyetlen
      címke sem fedi át a szomszédját (a teszt a számított pozíciókat méri).
- [ ] **Accessibility:** minden megjelenő sávhoz tartozik `Semantics` leírás,
      ami tartalmazza a sáv nevét **és** egy szöveges összefoglalót
      (pl. „12 akkordszegmens, C–G–Am–F"); a hotspot-lista screen reader
      számára **listaként** elérhető.
- [ ] **Nyelvi paritás + overflow:** hu/en, 320 px és 600 px szélesség,
      `textScaleFactor` 1.0 és 2.0 — nincs overflow, nincs nyers kulcs.
- [ ] **Flag-kapu + V1 érintetlenség:** a route a flag mögött; a
      `git diff --stat` nem tartalmaz `lib/features/analyze/**` útvonalat, és
      a `test/features/analyze/timeline_view_test.dart` **átírás nélkül** zöld.
- [ ] **Nyers PCM nincs a UI-ban:** forrásolvasó teszt méri, hogy a
      `presentation/` fájlok nem hivatkoznak PCM-mezőre és nem importálnak
      `data/input/` útvonalat.

> **Küszöb-konvenció:** minden numerikus küszöbhöz a mátrix **három** cellát
> ad — szigorúan **alatta**, pontosan **rajta**, szigorúan **fölötte** —, és a
> cellák értékei `python3 -c`-vel kiszámoltak, nem idealizált rácsból becsültek
> ([`docs/LESSONS.md`](../LESSONS.md) L13).

### 6.1 Mérce-mátrix — melyik hibás implementációt fogja pirosra

| Hibás implementáció | Melyik cella vált PIROSRA |
|---|---|
| Minden eventhez widget készül | a virtualizáció „számláló ≤ 100" cellája |
| A viewport kilóghat a klipen kívülre | a pan-széllel-ütközés két cellája |
| A maxZoom exkluzív | a **pontosan 400 ms** ablak elfogadott-cella |
| A zoom/pan a painterbe van temetve | a tiszta viewport unit-teszt (nem fordul/nem hívható) |
| Az `unavailable` sáv üresen kirajzolódik | a pitch-sáv rejtve+magyarázat cellája |
| A ruler fix lépésközt használ | az 5 s vs 300 s eltérő címkesűrűség cella |
| Hiányzó `Semantics` a sávon | az accessibility cella |
| Nyers PCM-et tölt be a waveformhoz | a „nincs PCM a UI-ban" forrásolvasó cella |
| A hotspot ugrás nem hozza be a tartományt | a hotspot-navigáció viewport-cellája |
| A `degraded` capability-t úgy kezeli, mint az `unavailable`-t (elrejti a sávot) | a degraded-cella (kilencedik, ADR 0243) |
| Timing-error lane szkalár `timing.*` metrikából "számol" idősort a UI-ban | az 5.7 „nincs számítás a UI-ban" elv + forrásolvasó cella (a lane csak `document.hotspots.where(kind==timing)`-ot rajzol, ADR 0243) |
| **Valódi-sértés próba (§10):** a viewport `clamp` hívásának ideiglenes törlése → a pan-széllel-ütközés cella **PIROS** → visszaállítás |

## 7. Kötelező ellenőrzések

```bash
tools/round-gate.sh test/features/audio_analysis test/app
```

Külön processzek, nincs `&&`/pipe/`tail`; a kimenet csonkítatlan.

## 8. Implementációs sorrend

1. `timeline_viewport.dart` (tiszta matek) + a kilenc cellás unit-teszt.
2. RED: virtualizáció-, sáv- és hotspot-mátrix.
3. `timeline_lane.dart` + `timeline_lanes.dart` (capability-vezérelt).
4. `timeline_ruler.dart` (adaptív címkék).
5. `hotspot_navigator.dart`.
6. `analysis_timeline_screen.dart` + route + ARB.
7. Accessibility- és overflow-tesztek; gate.

## 9. Kockázatok

- **A teljesítmény-benchmark widget-tesztben megbízhatatlan** — ezért a
  mérce **nem** wall-clock, hanem a feldolgozott elemek **számlálója**
  (determinisztikus).
- **A waveform preview hiánya** (OD-01) csökkenti az élményt; a §10-ben
  follow-upként rögzítendő, melyik kör (R28 cache vagy egy későbbi) szállítja.
- **A multi-touch gesztus tesztelése törékeny** — az OD-03 szerint a teszt a
  viewport API-ját hívja.

**STOP:** a V1 timeline módosítása, nyers PCM betöltése vagy a virtualizáció
elhagyása helyett `stopped` + brief-revízió.

## 10. Implementation handoff — az implementer tölti ki

- `controllers/timeline_viewport.dart` + teszt: tiszta, bounded zoom/pan/
  reveal-range matematikát és az inkluzív 399/400/401 ms küszöböt fed.
- `analysis_timeline_screen.dart`, lane/ruler/navigator widgetek: nyolc
  capability-vezérelt lane, fail-closed hiányzó capability, látható degraded
  jelzés, Canvas-virtualizáció, hotspot körbejárás, range-selection és
  szöveges semantics; a waveform mindig magyarázattal unavailable.
- Route/public export/ARB: az új route ugyanazon `audioAnalysisV2Enabled`
  flag mögött van, angol és magyar szövegekkel. A ruler és a selection az
  R23 `AppLocalizationsOverviewLabels.formatDuration` helperét használja.
- Javító kör #1: a hotspot overlay lane immár kizárólag
  `document.hotspots.isNotEmpty` alapján jelenik meg (a `targetAlignment`
  capability-től függetlenül), az üres lista pedig a lokalizált „nincs
  problémás pont” indoklást kapja. A capability-ág explicit
  `available`/`degraded` allowlist lett, ezért jövőbeli státusz nem jelenhet
  meg mérésként.
- Javító kör #1: a hotspot-lista minden eleméhez külön, lokalizált
  index/típus/súlyosság `Semantics` node tartozik. A navigációs gombok teljes
  szélességben tördelnek; a lane-címek is rugalmasak, mert a hu × 320 px × 2×
  regressziós mátrix tényleges `RenderFlex` overflow-t talált.
- Javító kör #1: a widget-teszt lefedi az en/hu × 320/600 px × 1.0/2.0
  kombinációt, a hotspot adatvezérelt kapuját és az elem-szemantikát; a
  forrásolvasó PCM-őr a valódi `PcmAnalysisInput` típusnevet és
  `domain/analysis_input.dart` importot tiltja. A `TimelineViewState` most a
  screen viewport- és selection-állapotát tartja, explicit `clearSelection`
  metódussal és teszttel. A zoom-ki és a `HotspotNavigator.previous()` is
  kapott tükör regressziós tesztet. Mindkét ARB-ból eltűntek a duplikált
  timeline title/description kulcsok.
- Futott: `flutter gen-l10n`; célzott screen teszt (9/9 PASS); viewport +
  hotspot-navigátor tesztek (9/9 PASS); majd `tools/round-gate.sh
  test/features/audio_analysis test/app` — format zöld, analyze zöld,
  `audio_analysis` 483 teszt PASS, `app` 69 teszt PASS, architecture/secrets/
  l10n zöld (`1244` üzenet).
- Eltérés: a V2 dokumentum nem tartalmaz decimált waveform-previewt, ezért
  a rögzített OD-01/ADR 0243 szerint a waveform lane unavailable marad.
  Nyers audio/PCM nem lett importálva vagy olvasva.

## 11. Review — a független reviewer tölti ki

Tervezett review: `docs/reviews/e06-r24-layered-zoomable-timeline-review.md`.
Merge csak exact-SHA zöld CI, §4-en belüli diff és nulla OPEN BLOCKER/MAJOR után.
