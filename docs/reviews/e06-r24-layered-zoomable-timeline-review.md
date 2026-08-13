# E06-R24 — Review

Brief: `docs/rounds/e06-r24-layered-zoomable-timeline.md`
Diff: `git diff 2a24cacc..7081b7bc` (pre-flight commit → implementer HEAD, 16 files, +1292/-3)
Reviewer: Claude (Sonnet 5, orchestrator) · Dátum: 2026-08-13
Verdikt: CHANGES REQUIRED

## Összegzés

BLOCKER: 0 · MAJOR: 3 · MINOR: 4 · NOTE: 2

Mechanikailag a kör erős: a gate-et **kétszer, függetlenül**, két külön
klónban futtattam (`/home/ubuntu/ss-terra-e06-r24` és a hivatalos, kizárólag
review célra klónozott `/tmp/review-e06-r24`) — mindkétszer **MINDEN GATE
ZÖLD** (format, analyze, `test test/features/audio_analysis`, `test
test/app`, architecture, secrets, l10n). A `TimelineViewport` tiszta,
widget-mentes, jól tesztelt matek. A jelzésfájl `gate_shape=VIOLATION`-je
**hamis pozitív** volt (L245 minta): az egyetlen regex-találat a
`docs/LESSONS.md` L245 bejegyzésének SAJÁT idézett szövege, amit az
implementer olvasott ki diagnosztikai céllal — nem egy csonkított/láncolt
gate-hívás. A tartalmi hűség viszont — pontosan a `sdd-round-review` skill
alapelve szerint ("a zöld gate NEM bizonyíték") — három helyen elmarad a
brief szó szerinti előírásától; ezek a MAJOR leletek.

## Acceptance criteria

| # | Kritérium | Teljesült | Bizonyíték |
|---|---|---|---|
| 1 | Viewport-mátrix — kilenc cella | ⚠️ 8/9 | `timeline_viewport_test.dart` 6 teszt: zoom-be(center)✅, pan-bal/jobb+mindkét-szél-ütközés✅, minZoom/maxZoom(399/400/401ms)✅, near-edge-zoom✅, timeForPixel/pixelForTime✅, revealRange mindkét széllel✅. **Zoom-KI (scale<1, szélesítés) nincs unit-tesztelve** — ld. F6 (kézzel átszámolva helyesnek bizonyult, de a briefben névvel nevezett cella hiányzik). |
| 2 | Zoom-küszöb hármas | ✅ | `timeline_viewport_test.dart:43-67`, pontosan 399/400/401 ms, gate-ben PASS. |
| 3 | Virtualizáció | ✅ | `TimelineLane.visibleItemsFor` statikus, unit-tesztelhető; `analysis_timeline_screen_test.dart:50-79`: 5000 item / 50 látható → `visible.length <= 100`, PASS a gate-ben. |
| 4 | Sáv-mátrix — nyolc cella | ❌ | 7/8 lane helyesen `available`-re jelenik meg (`analysis_timeline_screen_test.dart:81-135`) — de a **hotspot lane cellája hibás alapon zöld**: a teszt kifejezetten `targetAlignment: available`-t állít be ahhoz, hogy a hotspot lane megjelenjen, miközben `hotspots: []` (a `_document()` helperben, 214. sor) — azaz a lane egy **capability-státusztól** függ, nem attól, hogy VAN-e hotspot. Ld. **F1 (MAJOR)**. |
| 5 | Degraded-cella (kilencedik) | ✅ | `analysis_timeline_screen_test.dart:22-48` — `chordTimeline: degraded` → lane látható marad + "Limited confidence" szöveg; `monophonicPitch: unavailable` → lane rejtve. Kód-olvasással igazolva, hogy egy `degraded→hidden` regresszió erre a cellára pirosra váltana. |
| 6 | Hotspot-navigáció | ⚠️ | `hotspot_navigator_test.dart` — **csak `next()`**: 3 hotspot, négyszeri lépés (0→1→2→0, körbeér), minden lépésnél `revealRange` ellenőrizve. **`previous()` nulla tesztelve** — ld. F7 (MINOR; a brief §3 explicit „előző/következő"-t ír elő). |
| 7 | Adaptív címkék | ✅ | `analysis_timeline_screen_test.dart:137-152` — 5s vs 300s klip eltérő `interval`-t ad, a pozíciók rendezettek/duplikátum-mentesek. |
| 8 | Accessibility | ⚠️ | Lane-Semantics (név+összegzés) tesztelve (1. teszt, `find.bySemanticsLabel`). **A „hotspot-lista screen reader számára listaként elérhető" nincs tesztelve, és az implementáció sem épít explicit lista-szemantikát** — két gombot csomagol egyetlen `Semantics(label: "N hotspots")`-ba. Ld. F3 (MAJOR). |
| 9 | Nyelvi paritás + overflow | ❌ | **Nulla teszt** hu/en válzásra, 320/600 px szélességre vagy `textScaleFactor` 1.0/2.0-ra bárhol a diffben. Ld. F2 (MAJOR). |
| 10 | Flag-kapu + V1 érintetlenség | ✅ | `git diff --stat` nulla `lib/features/analyze/**` (16/16 fájl az engedélyezett listán); **saját kézzel futtatva**: `flutter test test/features/analyze/timeline_view_test.dart` → 2/2 PASS, változatlan fájlon. |
| 11 | Nyers PCM nincs a UI-ban | ✅ | `analysis_timeline_screen_test.dart:154-164` forrásolvasó teszt (`data/input/`, `pcmSamples` string-keresés a teljes `presentation/`-en) — PASS; kézi grep-pel megerősítve, hogy a diff egyetlen fájlja sem importál `data/input/`-ot. |

## Scope-audit

Engedélyezett fájlokon kívüli változás: **nincs.** `scope_audit=ok`,
`scope_audit_changed=16` a jelzésfájlban; saját `git diff --stat
2a24cacc..7081b7bc` is pontosan a 16, a brief §4/`allowed_paths`-ában
felsorolt fájlt mutatja (7 új `presentation/` fájl, 3 új teszt, `app_route
.dart`+`app_router.dart` additív route, `public.dart` 2 export, 2 ARB, a
kör-brief saját magát). Tilos zóna (`lib/features/analyze/**`,
`audio_analysis/engine/**`, `audio_analysis/domain/**`) érintetlen.

## Megállapítások

### F1 — MAJOR — A hotspot-overlay lane rossz, adattól független kapun (`targetAlignment` capability) fut, nem a hotspot-adat jelenlétén

- **Fájl:** `lib/features/audio_analysis/presentation/widgets/timeline_lanes.dart:121-130` (a hotspot lane hívása `AnalysisCapability.targetAlignment`-tel) + `:143-168` (`_lane()` — a kapu-logika: hiányzó/`unavailable`/`notApplicable` riport → a teljes lane rejtve).
- **Probléma:** az ADR 0243 (ezt a kört megelőző, saját pre-flight döntésem) kifejezetten rögzíti: „Waveform preview és hotspot-overlay have no dedicated AnalysisCapability member — hotspots carry their own per-item confidence/severity instead", és a lane adatforrása `document.hotspots` (MINDEN kind). Az implementáció ehelyett a hotspot lane-t a `targetAlignment` capability-hez kötötte — egy capability, ami KIZÁRÓLAG arról szól, van-e referencia-cél, amihez a játékos időzítését igazítani lehet. Ugyanezen a képernyőn a Prev/Next hotspot-gombok (`analysis_timeline_screen.dart:94-116`) helyesen **adat-vezérelten** (`widget.document.hotspots.isNotEmpty`) jelennek meg — a KÉT mechanizmus a UGYANAZON adatra inkonzisztens forrásból dönt.
- **Hatás:** egy `freePlay` (cél nélküli) sessionben, aminek VAN detektált hotspotja (pl. `kind: rhythm`/`dynamics`/`harmony`/`pitch` — egyik sem függ target-alignmenttől), a `targetAlignment` capability `notApplicable` lesz (nincs mihez igazítani), és a hotspot lane **„unavailable"-ként rejtve jelenik meg**, MIKÖZBEN a fölötte lévő Prev/Next gombok aktívak és működnek — a felhasználó lépked a hotspotok között, miközben a hotspot-sáv azt állítja, a mérés nem elérhető. Ez pont a `AnalysisTimelineScreen` doc-commentjének ("no PCM, engine type or timing metric is reconstructed here") és a brief §5.3 elvének ellentmond: a sávnak a **tényleges adatot** kell tükröznie, nem egy hozzá nem tartozó capability-flaget.
- **Bizonyíték:** a saját teszt (`analysis_timeline_screen_test.dart:81-135`) kifejezetten `targetAlignment: available`-t állít be (miközben `hotspots: []`), hogy a hotspot lane egyáltalán megjelenjen — ez saját maga bizonyítja a kapu-függőséget.
- **Kötelező javítás:** a hotspot lane jelenjen meg, ha `document.hotspots.isNotEmpty` (ugyanaz a feltétel, mint a Prev/Next gomboké), NEM egy `AnalysisCapability`-lookup alapján. Ha üres a hotspot-lista, a §5.3 szerinti „magyarázattal rejtve" ág fusson (pl. „nincs hotspot" ok, nem „mérés nem elérhető").
- **Ellenőrzés:** regressziós teszt, ami `targetAlignment`-et KIHAGYJA a `capabilities` listából (vagy `notApplicable`-re állítja) ÉS `hotspots`-ot egy valódi elemmel tölti fel — a hotspot lane-nek MEG KELL jelennie.
- **Státusz:** OPEN

### F2 — MAJOR — „Nyelvi paritás + overflow" acceptance criterion nulla teszttel

- **Fájl:** `test/features/audio_analysis/presentation/analysis_timeline_screen_test.dart` (a teljes fájl — nincs benne ilyen teszt).
- **Probléma:** a brief §6 explicit, névvel nevezett kritériuma: „hu/en, 320 px és 600 px szélesség, `textScaleFactor` 1.0 és 2.0 — nincs overflow, nincs nyers kulcs." A diff egyik fájljában sincs `Locale('hu')`/`tester.view.physicalSize`/`MediaQuery(data: ... textScaler:...)` mintázatú teszt.
- **Hatás:** semmi nem fogná meg, ha egy magyar fordítás (pl. a hosszabb `analysisTimelineHotspotList`/`analysisTimelineSelection` sztringek) 320 px-en vagy 2×-es szövegméretnél `RenderFlex overflowed` hibát dobna, vagy ha egy hiányzó ARB-kulcs nyersen (`analysisTimelineXyz`) jelenne meg a UI-n.
- **Kötelező javítás:** legalább egy `testWidgets` mátrix-teszt: {hu, en} × {320, 600} logikai px szélesség × {1.0, 2.0} `textScaleFactor` — `tester.takeException()` nulla, és `find.textContaining('analysisTimeline')` (nyers kulcs minta) `findsNothing`.
- **Ellenőrzés:** az új teszt fusson és legyen zöld a gate-ben; ideiglenesen egy ARB-kulcs eltávolításával/hosszú placeholder-sztringgel próbaként pirosra vihető.
- **Státusz:** OPEN

### F3 — MAJOR — A hotspot-lista nincs screen reader számára navigálható LISTAKÉNT felépítve

- **Fájl:** `lib/features/audio_analysis/presentation/analysis_timeline_screen.dart:94-116`.
- **Probléma:** a brief §6 Accessibility pontja explicit: „a hotspot-lista screen reader számára **listaként** elérhető." A jelenlegi felépítés egyetlen `Semantics(label: "N hotspots")` konténerbe csomagol két navigációs GOMBOT (Prev/Next) — nincs semmilyen elem-szintű (index/összesen, egyenkénti hotspot-leírás) szemantikai struktúra, amit egy screen reader listaként bejárhatna. Nincs teszt sem, ami BÁRMILYEN „lista" értelmezést igazolna.
- **Hatás:** egy screen reader felhasználó a jelenlegi implementációval csak azt hallja, hogy „3 hotspot van" + két gombot ("előző"/"következő") — nem tudja megelőzőleg átfutni, mik a hotspotok (típus, súlyosság, időpont), csak szekvenciálisan, egyesével a viewportot mozgatva fedezheti fel őket. Ez lényegesen szegényebb, mint amit a §25.8 „hotspot lista" elve előír.
- **Kötelező javítás:** vagy explicit lista-szemantika (minden hotspothoz saját `Semantics` node index/típus/súlyosság leírással, `SemanticsSortKey`-vel rendezve), vagy — ha a brief szerzőjének szándéka a Prev/Next-only navigáció volt — a §0.0-ban dokumentált revízió, ami PONTOSAN meghatározza, mit jelent itt a „lista", és teszttel bizonyítja.
- **Ellenőrzés:** widget-teszt, ami `tester.getSemantics(find.byType(...))`-tal bejárja a hotspot-szemantika fát és igazolja, hogy mind a 3 hotspot egyedileg elérhető.
- **Státusz:** OPEN

### F4 — MINOR — Duplikált ARB-kulcsok mindkét nyelvi fájlban

- **Fájl:** `lib/l10n/app_en.arb` és `lib/l10n/app_hu.arb`.
- **Probléma:** `analysisTimelineTitle` és `analysisTimelineDescription` (a `@`-doksi-párjukkal együtt) **kétszer** szerepel mindkét fájlban (`grep -c '"analysisTimelineTitle":' lib/l10n/app_en.arb` → 2; ugyanígy a másik három kulcs/fájl-kombináció). A JSON-dekóder csendben az utolsó előfordulást tartja meg (a két érték egyébként azonos, tehát futásidejű hatás nincs), de ez sosem szándékos.
- **Hatás:** ártalmatlan futásidőben (a `l10n` gate-lépés is zöld volt), de rossz kódhigiénia, és egy jövőbeli szigorúbb JSON-lint pirosra vihetné.
- **Kötelező javítás:** a 4-4 duplikált sor törlése mindkét ARB-fájlból.
- **Ellenőrzés:** `grep -c` mindkét kulcsra mindkét fájlban → 1.
- **Státusz:** OPEN

### F5 — MINOR — `TimelineViewState` létrehozva, de sosem használva

- **Fájl:** `lib/features/audio_analysis/presentation/controllers/timeline_view_state.dart` (teljes fájl, 23 sor).
- **Probléma:** a brief §4 táblázata ezt a fájlt „nézetállapot" céllal írja elő, és az implementáció létre is hozza (`viewport`/`selectionStart`/`selectionEnd` + `copyWith`) — de az `AnalysisTimelineScreen` a GYAKORLATBAN nem ezt használja: az állapotot nyers `State` mezőkben tartja (`_viewport`, `_selectionStart`, `_selectionEnd` stb., `analysis_timeline_screen.dart:21-25`). Repó-szintű grep: a `TimelineViewState` szimbólum a SAJÁT fájlján kívül SEHOL nem fordul elő `lib/`-ben vagy `test/`-ben.
- **Hatás:** halott kód — nincs hívója, nincs rá teszt, karbantartási zavart okoz (a jövőbeli olvasó feltételezné, hogy ez az állapotmodell).
- **Kötelező javítás:** vagy törölni a fájlt (és kivenni az `allowed_paths`-ból/§4-ből egy brief-revízióval), vagy ténylegesen bekötni a screen state-jébe.
- **Ellenőrzés:** `grep -rn "TimelineViewState" lib/ test/` a fájl saját definícióján kívül nulla találatot ad, VAGY a screen ténylegesen ezt használja.
- **Státusz:** OPEN

### F6 — MINOR — Zoom-KI irány nincs unit-tesztelve (a „kilenc cella" egyike hiányzik)

- **Fájl:** `test/features/audio_analysis/presentation/timeline_viewport_test.dart`.
- **Probléma:** a 6 teszt mindegyike vagy zoom-BE-t (`scale > 1`), vagy pan/edge/mapping esetet fed — `zoomBy(scale < 1, ...)` (a klip SZÉLESÍTÉSE) sehol nincs közvetlenül tesztelve, pedig a brief §6 „zoom be/**ki** a középpont körül" mindkét irányt névvel nevezi.
- **Hatás:** próbateszttel empirikusan igazolva (`/tmp/review-e06-r24/test/_scratch/zoom_out_probe_test.dart`, eldobható, nem commitolva): `zoomBy(scale: 0.5, focalTime: 5s)` egy `[4s,6s]` ablakból pontosan `[3s,7s]`-re szélesedik (szimmetrikusan a focal-pont körül), és egy szél-közeli `scale: 0.1` zoom-ki sem lép ki a `[0,10s]` tartományból (`isWithinDuration` igaz marad) — mindkét próba PASS. A kód tehát **helyesnek bizonyul**; ez jelenleg teszt-lefedettségi hiány, nem bizonyított hiba.
- **Kötelező javítás:** egy `test()` explicit `scale < 1` esettel (középpont körüli szélesedés + a `[0,duration]`-on belül maradás).
- **Ellenőrzés:** az új teszt fusson zölden.
- **Státusz:** OPEN

### F7 — MINOR — `HotspotNavigator.previous()` nulla tesztelve

- **Fájl:** `test/features/audio_analysis/presentation/hotspot_navigator_test.dart`.
- **Probléma:** a brief §3 Scope explicit „HotspotNavigator (előző/következő)"-t ír elő; az egyetlen teszt csak `next()`-et fed (bár a §6 acceptance criterion szó szerint is csak a „következő"-t nevezi meg — ez a lelet a §3 SCOPE, nem a §6 acceptance ellen szól).
- **Hatás:** a `previous()` implementáció (`hotspot_navigator.dart:34-49`) szinte tükörképe a `next()`-nek — kód-olvasással NEM találtam benne hibát —, de módosításnál (pl. a jövőbeli R25 összehasonlítás-kör hozzáér) egy regresszió észrevétlen maradna.
- **Kötelező javítás:** egy tükör-teszt a `next()`-éhez hasonlóan (3 hotspot, 4× `previous()`, körbeérés + `revealRange` minden lépésnél).
- **Ellenőrzés:** az új teszt fusson zölden.
- **Státusz:** OPEN

### F8 — NOTE — A brief által kötelezővé tett valódi-sértés próba nincs dokumentálva a §10-ben; a reviewer pótolta

- **Fájl:** `docs/rounds/e06-r24-layered-zoomable-timeline.md` §6.1 utolsó sora: „Valódi-sértés próba (§10): a viewport `clamp` hívásának ideiglenes törlése → a pan-széllel-ütközés cella PIROS → visszaállítás."
- **Megfigyelés:** az implementer §10 handoffja nem említi ezt a próbát. A reviewer pótolta: `TimelineViewport._withClampedStart`-ban a `_clampDuration(...)` hívást ideiglenesen `requestedStart`-ra cserélve (`/tmp/review-e06-r24`, eldobható klón), a `pans in both directions and clamps against both clip edges` teszt determinisztikusan PIROSRA váltott (`'!start.isNegative': is not true.`) — a klón visszaállítás nélkül eldobva. A guard valódi.
- **Státusz:** nem blokkol; jövőbeli körnél a §10 kitöltésekor ezt a próbát is dokumentálni kell.

### F9 — NOTE — A tempó-görbe (`tempoPoints`) sehol nem jelenik meg

- **Fájl:** `lib/features/audio_analysis/presentation/widgets/timeline_lanes.dart:50-62` (beat/bar lane).
- **Megfigyelés:** az ADR 0243 a beat/bar lane adatforrásába a `.tempoPoints`-ot is felvette, de a tényleges lane csak `beats`+`bars`-t rajzol — a `TimelineLaneItem` pont/tartomány modellje nem alkalmas folytonos BPM-érték megjelenítésére, úgyhogy ez valószínűleg indokolt egyszerűsítés, nem hiba. Follow-up: egy jövőbeli kör dönthet egy dedikált tempó-alsáv bevezetéséről.
- **Státusz:** nem blokkol.

## Gate-bizonyíték ellenőrzése

| Gate | Állított eredmény | Ellenőrizve |
|---|---|---|
| format | zöld (implementer) | ✅ saját futtatás (kétszer, két klónban) |
| analyze | zöld (implementer) | ✅ saját futtatás, „No issues found!" mindkétszer |
| `test test/features/audio_analysis` | zöld (implementer) | ✅ saját futtatás, 477 teszt PASS |
| `test test/app` | zöld (implementer) | ✅ saját futtatás, 69 teszt PASS |
| architecture | zöld (implementer) | ✅ saját futtatás, „12 allowlisted deviation(s)" — előzetes, nem e kör hozta |
| secrets | zöld (implementer) | ✅ saját futtatás, 0 finding |
| l10n | zöld (implementer) | ✅ saját futtatás, „OK (en → hu, 1234 message(s))" — **de ld. F4**, a paritás-ellenőrző nem szűri a duplikált kulcsot |
| V1 kompat (`test/features/analyze/timeline_view_test.dart`) | nincs a kör gate_tests-jében | ✅ saját, célzott futtatás, 2/2 PASS változatlan fájlon |
| CI (teljes suite + property + APK) | — | még nem dispatch-elve — a review UTÁNI lépés |

`gate_shape=VIOLATION` a jelzésfájlban: **hamis pozitív**, ld. Összegzés — a
konkrét regex-találat a `docs/LESSONS.md` L245 bejegyzésének idézett
szövegére illeszkedett, nem egy tényleges csonkított/láncolt gate-hívásra.

## Merge-döntés

**Merge TILOS.** 3 nyitott MAJOR (F1, F2, F3). Javító kör szükséges —
ugyanaz a motor (Terra), a fenti F1–F7 leletlistával a promptban; a
NOTE-tételek (F8, F9) tájékoztató jellegűek, nem kötelező javítani.
