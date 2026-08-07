# E06-R24 — Többrétegű, zoomolható timeline

- **Státusz:** PREPARED (előre megírva 2026-08-07, kód olvasva: main @ `a6e6f3d`)
- **SDD-kör:** [`docs/sdd/07-epic-06-audio-analysis-2.md`](../sdd/07-epic-06-audio-analysis-2.md) Kör 24; §25.6–25.8
- **Branch:** `minimax/e06-r24-layered-zoomable-timeline`
- **Előfeltétel:** **E06-R23 merge**
- **Brief szerzője:** Claude (batch) · **Implementáció:** MiniMax M3 (UI-dominált kör, ADR 0069)

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
  "lib/app/router/app_router.dart",
  "lib/l10n/app_en.arb",
  "lib/l10n/app_hu.arb",
  "test/features/audio_analysis/presentation/analysis_timeline_screen_test.dart",
  "test/features/audio_analysis/presentation/timeline_viewport_test.dart",
  "test/features/audio_analysis/presentation/hotspot_navigator_test.dart",
  "docs/rounds/e06-r24-layered-zoomable-timeline.md",
]
gate_tests = [
  "test/features/audio_analysis",
  "test/app",
]
native_gate = false
```

> ⚠ **Pre-flight (KÖTELEZŐ):** friss `origin/main` + E06-R23 merge. Olvasd újra
> a `lib/features/analyze/widgets/timeline_view.dart`-ot (170 sor) — az a
> **kompatibilitási** nézet, ami **változatlan** marad, és a
> `test/features/analyze/timeline_view_test.dart` az őre. Ellenőrizd az R23
> `OverviewViewModel` formázási helpereit: a timeline **ugyanazokat**
> használja, nem duplikál. PREPARED→PLANNING, brief commit előbb.

## 0. Kör-jelzés és STOP-protokoll

```bash
tools/codex-signal.sh progress "<egy sor>" ; tools/codex-signal.sh done "<egy sor>"
tools/codex-signal.sh stopped "<egy sor>" ; tools/codex-signal.sh blocked "<egy sor>"
```

Lezáró jelzés nélkül a kör bukott. Listán kívüli fájl → `stopped`.
**STOP on scope conflict:** listán kívüli fájl kell → `stopped` + jelentés.

## 0.0 Tervezési baseline és pre-flight revízió

**PREPARED.** Új ADR nincs.

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
- A `fl_chart` a projekt függősége, de a timeline-hoz **nem** kötelező.

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
| `lib/app/router/app_router.dart` | meglévő | **additív** route, flag mögött |
| `lib/l10n/*.arb` | meglévő | **additív** kulcsok |
| `test/**` | ÚJ | viewport + widget + navigátor teszt |

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
   **NEM elfogadható:** üres pitch-sáv indoklás nélkül.
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
      betöltése a UI-ba TILOS (ADR 0202).
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

_(üres)_

## 11. Review — a független reviewer tölti ki

Tervezett review: `docs/reviews/e06-r24-layered-zoomable-timeline-review.md`.
Merge csak exact-SHA zöld CI, §4-en belüli diff és nulla OPEN BLOCKER/MAJOR után.
