# E06-R10 — Review

Brief: `docs/rounds/e06-r10-event-evidence-onset-strum-timeline.md`
ADR: `docs/adr/0228-event-evidence-model-and-timeline-builder-contract.md`
Diff: `git diff 8c2e43ae..9f92431a` (main → `codex/e06-r10-event-evidence-onset-strum-timeline`)
Reviewer: Claude (independent reviewer) · Dátum: 2026-08-12
Első verdikt: CHANGES REQUESTED (lásd lent)

## Javító kör 1 — zárás (2026-08-12, fix commit `ad9317de`)

**Verdikt: APPROVED.** Terra a `.pipeline/fix-prompt-E06-R10-1.md` szerint
KIZÁRÓLAG tesztet adott hozzá (`test/features/audio_analysis/engine/
event_timeline_builder_test.dart`, +181 sor), production kódot nem
módosított — pontosan a javító kör kért scope-ja.

- **F1 zárva:** az új „preserves V1 strum timestamps, counts, and directions
  for R09 fixtures" teszt a `clip_analyzer_parity_test.dart`-tal AZONOS
  kilenc fixture-t futtatja a VALÓDI `ClipAnalyzerStage` → `LegacyEvidence` →
  `EventTimelineBuilder` láncon, és a V1 `ClipAnalyzer().analyze()`
  referenciával veti össze (darabszám, |Δ|≤1µs idő, irány). Saját, izolált
  `/tmp/review-e06-r10-fix1` klónban futtatott valódi-sértés próbával
  igazoltam, hogy a teszt VALÓBAN elkap egy end-to-end regressziót: a
  `_directionFromLegacy` irány-leképezés felcserélése (down↔up) a „two
  chords" fixture 0. strumján azonnal PIROSRA vitte pontosan ezt az új
  tesztet (`Expected: StrumDirection.up, Actual: StrumDirection.down`) —
  utána `git checkout --` visszaállítva, `git status --short` üres.
- **F2 zárva:** az új „measures attack strength and local RMS from original
  PCM" teszt egy ismert (0,9 csúcs / 0,5 háttér) PCM-pufferen a builder
  TÉNYLEGES kimenetét (`attackStrength=0.9`, `localRms=0.5108624004141064`)
  méri — ugyanazok a számok, amiket a review saját, független próbája is
  számolt (kereszt-validálva).
- **Gate újrafuttatva, saját kézzel, FRISS izolált klónban**
  (`/tmp/review-e06-r10-fix1`, a `docs/LESSONS.md` L222 szerinti
  `tools/prepare-flutter-generated.sh` előkészítéssel):
  `tools/round-gate.sh test/features/audio_analysis test/property
  test/features/analyze` → **mind a 8 lépés ZÖLD** (format, analyze,
  audio_analysis 118/118, property 76/76, analyze 64/64, architecture 12
  allowlisted deviation, secrets 0 finding, l10n 1019 üzenet) —
  `GATE_EXIT=0`.
- **Scope-audit:** `scope_audit=ok`, 2 megváltozott fájl (a teszt + a brief
  §10 handoff-frissítés), mindkettő `allowed_paths`-on belül.

Nyitva maradó MAJOR/BLOCKER: **nulla.** A merge feltétele (CI exact-SHA a
`ad9317de` fix-commiton, majd Router CI) a driver dolga a review után.

---

## Eredeti review (2026-08-12, HEAD `9f92431a`)

Verdikt akkor: **CHANGES REQUESTED**

## Összegzés

BLOCKER: 0 · MAJOR: 1 · MINOR: 1 · NOTE: 0

Független, izolált `/tmp/review-e06-r10-general` klónban (friss `flutter pub get` után, l10n codegen újragenerálva) újrafuttatott `tools/round-gate.sh test/features/audio_analysis test/property test/features/analyze` mind a **8 lépésen ZÖLD** (format, analyze, 3× test, architecture, secrets, l10n — 256 teszt összesen a három útvonalon). A brief §6.1 mérce-mátrixának négy sorát valódi mutációs próbával igazoltam egy MÁSODIK izolált klónban (`/tmp/review-e06-r10-probes`) — mind a négy a várt cellát vitte pirosra, majd visszaálltam az implementer eredeti kódjára (`git checkout --`, `git status --short` üres minden próba után). Scope tiszta: a 10 megváltozott fájl a brief 11 `allowed_paths` elemének pontos részhalmaza, a sealed `AnalysisEvent` bázisosztály és az öt testvér-típus, valamint az öt névvel nevezett, allowed_paths-on kívüli fogyasztó bitre változatlan.

Egy MAJOR találat van: a brief §6 **első**, explicit acceptance-bulletje (V1↔V2 időbélyeg-paritás mind a kilenc valódi R09-fixture-re) — aminek saját, dedikált sora van a §6.1 mérce-mátrixban is — **nincs tesztelve** a round diffjében; egy saját, eldobható próbateszttel igazoltam, hogy a viselkedés MOST ténylegesen helyes, de a mérce ezt nem őrzi jövőbeli regresszió ellen. Egy MINOR: az attackStrength/localRms számított értékét (nem csak a jelenlétét) szintén semmilyen teszt nem ellenőrzi a builderen keresztül — saját próbával igazoltam, hogy a jelenlegi számítás numerikusan helyes.

## Acceptance criteria

| # | Kritérium | Teljesült | Bizonyíték |
|---|---|---|---|
| 1 | Paritás a V1 időbélyegekkel (mind a kilenc R09-fixture) | ❌ | Nincs teszt a diffben, ami a builder eredményét a kilenc valódi R09-fixture-ön (`clip_analyzer_parity_test.dart:47-87`) a V1 `TimelineStrum`-hoz hasonlítaná (`grep -rln "EventTimelineBuilder" test/` csak a saját teszt- és property-fájlt találja, szintetikus `_evidence()`/`_audio()` fixture-ökkel). Lásd **F1**. Saját eldobható próbateszttel igazoltam, hogy a viselkedés jelenleg ténylegesen helyes mind a 9 fixture-ön (0 elnyomás mindenhol, darabszám+idő pontosan egyezik) — de ezt semmi nem őrzi. |
| 2 | Minimum separation küszöb hármas, `Duration`-alapú, 48 kHz + 44100 Hz | ✅ | `event_timeline_builder_test.dart`: „keeps pairs exactly at and above the Duration threshold" + „uses Duration separation at 48000 and 44100 Hz" (utóbbi explicit `2399/2400/2401` ÉS `2204/2205/2206` mintát fed le, `sampleRate ~/ 20` képlettel — nem hardkódolt). Saját mutációs próba: `<`→`<=` a `_suppressionReason`-ban → mindkét teszt PIROSRA vált a pontos határcellán (48 kHz: `2400 samples`), visszaállítva. |
| 3 | Suppression-diagnosztika, pár-szinten pontosan 2/2 | ✅ | `event_timeline_builder_test.dart`: „suppresses the whole second pair below 50 milliseconds" — `suppressedEvents` pontosan 2, `events` pontosan 2, mindkettő `minimumSeparation` okkal. |
| 4 | `onsetEventId` integritás | ✅ | `analysis_event_timeline_property_test.dart:64-73` minden kept `StrumEvent`-re megköveteli, hogy `onsetEventId`-je egy, a KIMENETBEN jelen lévő `OnsetEvent`-re mutasson, azonos sampleIndex/time-mal. Saját mutációs próba: a suppression-t csak az onsetre alkalmazva (a strum publikusan marad) → a property teszt PONTOSAN ezen a soron bukik (`Expected: not null, Actual: <null>`), + 2 unit teszt is pirosra vált; visszaállítva. |
| 5 | Event ID determinizmus | ✅ | `event_timeline_builder_test.dart`: „keeps IDs deterministic while namespacing separate runs" — azonos runId kétszer → azonos ID-lista; eltérő runId → eltérő ID, de azonos type/sampleIndex rész. `event_id.dart`: `type` fixen `onsetType='onset'`/`strumType='strum'` literál, nem `runtimeType.toString()`. |
| 6 | Rendezettség + duplikátummentesség property + holtverseny-sorrend | ✅ | Property teszt: `sampleIndex` monoton nem csökkenő (`greaterThanOrEqualTo`) + `(runtimeType, sampleIndex)` egyediség `Set`-tel, 80 iteráció × 40 véletlen strum, 44100/48000 Hz keverten, `PROPERTY_SEED` env-ből (alapértelmezés 42). Külön unit teszt: „orders an equal-index onset before its linked strum". Saját mutációs próba: `_EventPair.events` sorrendjét `[strum, onset]`-re cserélve → mindkét érintett teszt PIROSRA vált (`type cast` hiba), visszaállítva. |
| 7 | Határeset-mátrix (0. minta, utolsó minta, üres bemenet, egyetlen esemény) | ✅ | „handles empty evidence and native sample boundaries": üres evidence → `events` üres; 2 strum a 0. és az utolsó mintán → `sampleIndex` pontosan `[0, 47999]`. „builds an onset/strum pair…" fedi az egyetlen-esemény esetet. |
| 8 | Confidence tartomány `[0,1]`, nincs NaN | ✅ | Property teszt: `event.confidence.isFinite` + `inInclusiveRange(0, 1)` minden eseményre, 80×~évents iteráción. `_normalizedConfidence` védekezik NaN/Infinity ellen (`!value.isFinite → 0`). |
| 9 | Legacy view paritás (LegacyViewAdapter zéró kódváltozás, V1 widget teszt zöld) | ✅ | `git diff 8c2e43ae..9f92431a -- lib/features/audio_analysis/data/legacy_view_adapter.dart` üres (0 sor). `test/features/analyze/timeline_view_test.dart` szintén byte-azonos (0 sor diff) és a gate 5. lépésében ZÖLD (64/64 teszt, benne mindkét timeline_view-teszt). |
| 10 | `confidenceSource` őr — sosem `'calibrated'` | ✅ | Property teszt: `isNot(isA<OnsetEvent>().having(confidenceSource, 'calibrated'))` + külön `expect(strum.confidenceSource, isNot('calibrated'))` minden kept `StrumEvent`-re. Saját mutációs próba: a builder `confidenceSource`-át kényszerítve `'calibrated'`-re → property teszt AZONNAL pirosra vált a guard-soron (`Expected: not …'calibrated', Actual: …'calibrated'`), visszaállítva. |

## Scope-audit

Engedélyezett fájlokon kívüli változás: **nincs.** `git diff --stat 8c2e43ae..9f92431a` pontosan 10 fájl, mindegyik a brief `allowed_paths`-ának (11 elem) részhalmaza — a 11.-et (`lib/features/audio_analysis/data/legacy_view_adapter.dart`) az implementer szándékosan, dokumentáltan nem módosította (§10 handoff: „kódmódosítás nem volt szükséges"), amit a #9 acceptance-sor önállóan is megerősít.

```
docs/adr/0228-event-evidence-model-and-timeline-builder-contract.md      (ÚJ)
docs/rounds/e06-r10-event-evidence-onset-strum-timeline.md               (§0.0 self-heal + §10 handoff)
lib/features/audio_analysis/domain/analysis_event.dart                   (bővítve — csak OnsetEvent/StrumEvent)
lib/features/audio_analysis/domain/events/event_id.dart                  (ÚJ)
lib/features/audio_analysis/engine/events/event_timeline_builder.dart    (ÚJ)
lib/features/audio_analysis/public.dart                                  (export +2 sor, csak az 2 ÚJ fájlra)
test/features/audio_analysis/domain/analysis_event_test.dart             (ÚJ)
test/features/audio_analysis/domain/event_id_test.dart                   (ÚJ)
test/features/audio_analysis/engine/event_timeline_builder_test.dart     (ÚJ)
test/property/analysis_event_timeline_property_test.dart                 (ÚJ)
```

Minden egyes commit (`a0e25bfd`, `f6a5303e`, `eb7fb5df` = doksi-only pre-flight; `aac4d849`, `38a13809` = feature; `9f92431a` = doksi-only handoff) külön ellenőrizve `git show --stat`-tal — egyik sem lép ki a fenti listából.

**`analysis_event.dart` diff-hatókör:** `git diff` csak két hunkot mutat (`@@ -28,7 +28,28 @@` az `OnsetEvent`, `@@ -40,8 +61,78 @@` a `StrumEvent` konstruktorán) — a sealed `AnalysisEvent` bázisosztály (2. sor) és az öt testvér-típus (`ChordChangeEvent`, `BeatEvent`, `NoteOnsetEvent`, `AnalysisRegionEvent`, `SilenceRegionEvent`, `ClippingRegionEvent`) egyetlen sora sem szerepel egyik hunkban sem.

**Az öt, allowed_paths-on kívüli fogyasztó** (brief §5 pont 7 / ADR Kontextus) — a helyes útvonalakkal (kettő eltért a briefben feltételezettől: `legacy_analyze_adapter.dart` és a teszt-párja ténylegesen `data/` alatt van, nem `engine/legacy/`) mindegyik **0 sor diff**, közvetlenül ellenőrizve:
`lib/features/audio_analysis/data/analysis_document_codec.dart`, `lib/features/audio_analysis/data/legacy_analyze_adapter.dart`, `test/features/audio_analysis/domain/analysis_timeline_test.dart`, `test/features/audio_analysis/data/legacy_analyze_adapter_test.dart`, `test/features/audio_analysis/data/analysis_document_codec_test.dart`.

**Architektúra/domain-tisztaság:** `event_id.dart` importmentes; `event_timeline_builder.dart` importjai: `dart:math`, `package:strumsight/core/music/strum.dart` (ugyanez a minta már a nem-módosított `legacy_evidence.dart`-ban is megvolt — nem új réteg-mintázat), és kizárólag saját feature-en belüli relatív importok (`../../domain/*`, `../analysis_provenance_builder.dart`, `../legacy/legacy_evidence.dart`) — nincs `lib/features/analyze/**` vagy `lib/features/live/**` import egyik új fájlban sem. `tool/check_architecture.dart` byte-azonos (nem allowed_paths elem, nem is módosult); a gate architecture-lépése ZÖLD, 12 allowlisted deviation — ugyanannyi, mint amennyi a jelen diff module-jaitól függetlenül, sem `event_id`, sem `event_timeline_builder` nem szerepel semmilyen allowlist-fájlban.

## Megállapítások

### F1 — MAJOR — V1↔V2 időbélyeg-paritás a kilenc valódi R09-fixture-ön nincs tesztelve

- **Fájl:** hiányzó teszt; a 9 fixture definíciója `test/features/audio_analysis/engine/clip_analyzer_parity_test.dart:47-87` (referencia, NEM allowed_paths); a fix természetes helye `test/features/audio_analysis/engine/event_timeline_builder_test.dart` (allowed, már létezik).
- **Probléma:** a brief §6 **első**, listán legelső acceptance-bulletje explicit megköveteli, hogy „az R09 evidence-ből épített `StrumEvent` lista darabszámra és időre (|Δ| ≤ 1 µs) egyezik a V1 `TimelineStrum` listával… mind a kilenc R09-fixture-re". A §6.1 mérce-mátrixnak saját, dedikált sora is van erre: „A V2 más szűrést alkalmaz, mint a V1 → a paritás-cella (darabszám) a kilenc fixture-ön". `grep -rln "EventTimelineBuilder" test/` kizárólag a round saját két tesztfájlját találja — mindkettő szintetikus, kézzel írt `_evidence()`/`_audio()` fixture-ökkel dolgozik, egyik sem futtatja a builder-t a valódi 9 R09-fixture-ön (`clip_analyzer_parity_test.dart` maga változatlan, és sosem hívja az `EventTimelineBuilder`-t). Ez pontosan az a falsifikációs útvonal, amit a mérce-mátrix saját maga nevesít mint kritikus kockázatot — de a cella, ami elkapná, nem létezik.
- **Hatás:** saját, eldobható próbateszttel (`/tmp/review-e06-r10-probes/test/features/audio_analysis/engine/_r10_parity_probe_test.dart`, futtatva, majd törölve) igazoltam, hogy a kód JELENLEG ténylegesen helyesen viselkedik: mind a 9 fixture-ön (`silence`, `two chords`, `four chords C G Am F`, `ring-out overlap`, `single strum`, `known BPM strum sequence`, `throwing refiner fallback`, `empty input`, `sample rate zero`) a builder V2 `StrumEvent` darabszáma pontosan egyezik a V1 `AnalyzeResult.strums` darabszámával, 0 elnyomással minden fixture-ön, és az idő µs-pontosan egyezik. Tehát **most nincs éles hiba** — de a mérce ezt nem őrzi: egy jövőbeli, öntudatlan regresszió (pl. a minimum-separation küszöb felemelése, a dedup-kulcs módosítása, vagy egy új fixture, amiben két strum ténylegesen 50 ms-on belülre esik) csendben törhetné a valódi paritást úgy, hogy a jelenlegi teszt-szuit egyáltalán nem venné észre — pontosan az OD-02/§9 kockázati bekezdés által előrevetített forgatókönyv.
- **Kötelező javítás:** adjunk hozzá egy tesztet (`event_timeline_builder_test.dart`, allowed), ami a `clip_analyzer_parity_test.dart`-tal azonos 9 fixture-t (vagy közös `test/support/synth.dart` segédekkel egyenértékű készletet) végigfuttatja: `ClipAnalyzerStage.run()` → `EventTimelineBuilder.build()`, és a kapott `StrumEvent`-lista darabszámát/idejét(≤1 µs)/irányát a V1 `ClipAnalyzer().analyze()` `AnalyzeResult.strums`-hoz hasonlítja. Implementációs megjegyzés: az „empty input" és „sample rate zero" fixture-nél a `PreprocessedAudio` konstruktor `sampleRate ≤ 0`-ra `ArgumentError`-t dob — ezt a builder-hívás előtt kezelni kell (pl. rate-default vagy a hívás kihagyása 0 strum esetén).
- **Ellenőrzés:** az új teszt önmagában zöld mind a 9 fixture-ön; egy szándékos szűrés-mutáció (pl. `<` → `<=` vagy a suppression-küszöb megemelése) legalább egy fixture-cellát pirosra visz.
- **Státusz:** OPEN

### F2 — MINOR — `attackStrength`/`localRms` számított értékét semmilyen teszt nem ellenőrzi

- **Fájl:** `lib/features/audio_analysis/engine/events/event_timeline_builder.dart:186-227` (`_dynamicsAt`/`_absolutePeak`/`_rms`)
- **Probléma:** `grep -n "attackStrength\|localRms" test/features/audio_analysis/engine/event_timeline_builder_test.dart test/property/analysis_event_timeline_property_test.dart` **nulla** találatot ad. A builderen KERESZTÜL előállított `attackStrength`/`localRms` numerikus helyességét semmi nem ellenőrzi — `analysis_event_test.dart` csak a nyers konstruktor-mezőt teszteli (ha átadok `.7`-et, `.7`-et kapok vissza), nem a builder tényleges csúcs-/RMS-számítását egy ismert PCM-pufferen.
- **Hatás:** saját, eldobható próbateszttel (`/tmp/review-e06-r10-probes/test/features/audio_analysis/engine/_r10_dynamics_probe_test.dart`, futtatva, majd törölve) igazoltam, hogy a jelenlegi számítás numerikusan HELYES: egy 1000 Hz-es, ismert csúcsú (0,9 egy 0,5-ös háttéren) szintetikus pufferen a builder `attackStrength=0.9` (pontos egyezés a kézzel számolt `[t, t+20 ms]` ablak-maximummal) és `localRms=0.5108624004141064` (pontos egyezés a kézzel számolt `[t−5 ms, t+45 ms]` ablak-RMS-szel, 1e-9 tűréssel) értéket ad. Nincs éles hiba — de a mérce nem véd egy jövőbeli regresszió ellen (pl. ablakhossz-elgépelés, `<=`/`<` csere az ablakhatáron, vagy a peak/RMS-számítás felcserélése).
- **Kötelező javítás (nem blokkoló ebben a körben, follow-up is elfogadható):** egy determinisztikus unit teszt, ami egy ismert PCM-pufferre (pl. egyetlen csúcs + konstans háttér) kézzel számolt csúcs-/RMS-értéket hasonlít a builder tényleges `OnsetEvent.attackStrength`/`localRms` kimenetéhez.
- **Ellenőrzés:** az új teszt zöld; egy ablakhossz-mutáció (pl. `_attackWindow` 20 ms → 10 ms) pirosra viszi.
- **Státusz:** OPEN (nem blokkoló, de ebben a javító körben együtt zárva F1-gyel)

## Mutációs próbák (eldobhatók, mind visszaállítva)

Mind a négy próba a `/tmp/review-e06-r10-probes` izolált klónban futott (a `/tmp/review-e06-r10-general` gate-futtató klón érintése nélkül, párhuzamos race elkerülésére); mindegyik után `git checkout --` az érintett fájlra + `git status --short` üres ellenőrzés.

| # | Mutáció | Célzott teszt | Eredmény |
|---|---|---|---|
| 1 | `_suppressionReason`: `<` → `<=` | „keeps pairs exactly at and above the Duration threshold" + „uses Duration separation at 48000 and 44100 Hz" | PIROS pontosan a `2400 samples`/határ-cellán (`Expected: length 4, Actual: length 2`); a 44100 Hz-es ág is elbukik |
| 2 | Pár-elnyomás atomicitásának törése (csak az onset kerül elnyomásra, a strum publikusan marad) | „suppresses the whole second pair below 50 milliseconds" + property teszt (`onsetEventId` integritás) | PIROS mindkét helyen: unit teszt `Expected: length 2, Actual: length 3`; property teszt `Expected: not null, Actual: <null>` az `onsets[strum.onsetEventId]` soron |
| 3 | `_EventPair.events`: `[onset, strum]` → `[strum, onset]` | „builds an onset/strum pair with stable linked IDs" + „orders an equal-index onset before its linked strum" | PIROS mindkettő, tiszta `type 'StrumEvent' is not a subtype of type 'OnsetEvent' in type cast` hibával |
| 4 | `confidenceSource` a builderben kényszerítve `EventConfidenceSources.calibrated`-re | property teszt (`confidenceSource` őr) + „builds an onset/strum pair…" | PIROS mindkettő: property teszt `Expected: not …'calibrated'`; unit teszt `Expected: 'heuristic', Actual: 'calibrated'` |

## Gate-bizonyíték ellenőrzése

| Gate | Állított eredmény (implementer, §10 handoff) | Ellenőrizve (saját, izolált klón, friss `flutter pub get` után) |
|---|---|---|
| format | zöld | ✅ `dart format --output=none --set-exit-if-changed lib test tool`: 1294 fájl, 0 változott |
| analyze | zöld | ✅ `flutter analyze lib/ test/ tool/`: „No issues found!" (11,6 s) |
| test test/features/audio_analysis | zöld | ✅ 116/116 teszt zöld (benne mind a 13 round-specifikus: 2 `analysis_event_test`, 3 `event_id_test`, 7 `event_timeline_builder_test`, 1 property) |
| test test/property | zöld | ✅ 76/76 teszt zöld, `PROPERTY_SEED=42` (env hiányában — a HORIZON-konvenciónak megfelelően) |
| test test/features/analyze | zöld (átírás nélkül) | ✅ 64/64 teszt zöld, benne `timeline_view_test.dart` 2 teszt — a diffben nem szerepel |
| architecture | zöld, 12 allowlisted deviation | ✅ „Architecture dependencies OK (12 allowlisted deviation(s))" — azonos szám, nem ez a diff okozza |
| secrets | (nem jelentve explicit a §10-ben) | ✅ „Secret scan OK (2230 file(s) scanned, 0 finding(s))" |
| l10n | (nem jelentve explicit a §10-ben) | ✅ „L10n parity OK (en → hu, 1019 message(s))" |
| `python3 tools/scope-audit.py` | `scope_audit=ok`, 10/10 changed path | ✅ manuálisan megerősítve `git diff --stat` + fájlonkénti allowed_paths-egyeztetéssel |

**Módszertani megjegyzés:** a gate első futtatási kísérlete a `flutter analyze` lépésen 931 hamis hibával bukott (`AppLocalizations`/`app_localizations.dart` hiányzó típus) — ez a friss klón hiányzó, gitignore-olt l10n-generátumából (`lib/l10n/app_localizations*.dart`, `flutter pub get` generálja, `generate: true` a pubspec.yaml-ben) eredt, NEM a round kódjából; egyik hibasor sem érintette a round bármely fájlját (ugyanaz a mért mintázat, mint `docs/LESSONS.md` L222). `flutter pub get` után a gate hibátlanul lefutott, lásd fent.

## Merge-döntés

Az ADR 0052 / brief §11 szerint: minden gate zöld ÉS nulla nyitott BLOCKER/MAJOR szükséges a merge-hez. A gate ténylegesen zöld (saját, izolált, teljes-kimenetű újrafuttatás), a scope tiszta, és a négy célzottan kért falsifikációs próba mindegyike valóban elkapja a hozzá tartozó hibaosztályt — ez erős evidencia arra, hogy a lefedett kritériumok (2, 3, 4, 5, 6, 8, 9, 10) valóban, nem csak látszólag teljesülnek.

**F1 (MAJOR) miatt a verdikt CHANGES REQUESTED — merge nem mehet, amíg nyitva van.** Fontos ugyanakkor, hogy F1 (és F2) **nem éles hibát** jelent — mindkettőt saját, független próbateszttel igazoltam mint jelenleg helyesen működőt; a hiányzó VÉDELEM a probléma, nem a viselkedés. A javítás mindkét esetben tiszta teszt-hozzáadás, meglévő, allowed_paths-on belüli fájlokban (`event_timeline_builder_test.dart`), zéró production-kód-kockázattal — egy javító körben lezárható, utána a gate újrafuttatásával és a CI dispatch-csal a szokásos módon mehet a merge.

CI (`full-gate.yml` + `router-ci.yml`) a javító kör előtt, a round HEAD-jén (`9f92431a`) már lefutott és zöld volt — mivel a javító kör kódot módosít, a merge előtt **újra kell dispatch-elni** a javított HEAD-en (ADR 0086 §2).
