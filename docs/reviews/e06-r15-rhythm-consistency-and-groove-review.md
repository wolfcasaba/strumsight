# E06-R15 — Review

Brief: docs/rounds/e06-r15-rhythm-consistency-and-groove.md
Diff: `git diff main...codex/e06-r15-rhythm-consistency-and-groove` (base `be93642d`, head `d8d21e67`)
Reviewer: Claude Sonnet 5 (orchestrátor) · Dátum: 2026-08-12
Verdikt: APPROVED

## Összegzés

BLOCKER: 0 · MAJOR: 0 · MINOR: 2 · NOTE: 0

Independens gate-újrafuttatás (izolált `/tmp/review-e06-r15` klón, friss
`prepare-flutter-generated.sh`): **MINDEN GATE ZÖLD** (format, analyze, `test
test/features/audio_analysis` [252 teszt], `test test/property` [az új
`analysis_rhythm_property_test.dart`-tal együtt, `PROPERTY_SEED=42`], `test
test/app`, architecture, secrets, l10n) — teljes, csonkítatlan log:
`/tmp/review-e06-r15-gate.log`, `GATE_EXIT=0`.

## Acceptance criteria

| # | Kritérium | Teljesült | Bizonyíték |
|---|---|---|---|
| 1 | Fixture-mátrix (7 cella) | ✅ | `rhythm_metrics_test.dart`: uniform eighths, irregular+accelerando (2 fixture egy testben), target swing, inferred low-confidence, insufficient-data — mind egyedi teszt; „random onsets" a 200-trial `analysis_rhythm_property_test.dart`-ban (véletlen `count ∈ [0,25)` esemény, véletlen confidence) |
| 2 | IOI-konzisztencia küszöb hármas | ✅ | `rhythm_metrics_test.dart:51-90`; **függetlenül újraszámolva** `python3 -c` (mean=median=100, sd=10→CV 0.1→0.9; sd=50→CV 0.5→0.5) — egyezik |
| 3 | Subdivision-mátrix (1/2/3/4 + ambiguous→degraded) | ✅ | `subdivision_analysis_test.dart:6-89`, mind az öt cella |
| 4 | Ambiguitás-küszöb hármas (1.049/1.05/1.051) | ✅ | 1.049 és 1.051 explicit teszt (`subdivision_analysis_test.dart:91-112`); a pontos **1.05** a `candidateDeviations: {2:1.0, 3:1.05,...}` cellában rejlik (1.05/1.0=1.05 pontosan) — függetlenül újraszámolva `python3 -c`, mindhárom pont egyezik |
| 5 | Confidence-korlát (homogén grid `confidence=0.4` → minden `rhythm.inferred_*` ≤0.4) | ✅ | `rhythm_metrics_test.dart:134-160` mindegyik metrikára külön ellenőriz; **saját, az implementertől független valódi-sértés próba**: a `beatConfidence` szorzó ideiglenes kivétele → `rhythm_metrics_test.dart` PIROSRA vált (`Actual: <1.0>` vs várt `≤0.4`) → visszaállítva, ld. lent |
| 6 | Swing-kapu (target nélkül `notApplicable`+hiányzik; targettel 2.0±0.05) | ✅ | `rhythm_metrics_test.dart:92-132`; a 2:1 fixture **függetlenül újraszámolva** `python3 -c` → 2.003, ±0.05-ön belül |
| 7 | Metric ID diszjunkció | ✅ | `rhythm_metric_catalog_test.dart:8-15` (`intersection` üres) + `RhythmMetricSuiteIds.inferred.swingRatio` típusszinten `null` (a const konstruktor nem kapja meg) |
| 8 | Nincs stiláris címke | ✅ | `rhythm_metric_catalog_test.dart:47-60`, `(?i)(swing|shuffle|groove)_?(score|style)` regex az ID-k ÉS mindkét ARB fájl teljes tartalma ellen; a `swing_ratio` szó szerint sosem illeszkedik erre a mintára (a „ratio" nem „score"/„style"), tehát a brief kivétel-klóza a gyakorlatban tárgytalan, de nem is okoz hamis negatívot |
| 9 | NaN-mentesség + tartomány property | ✅ | `analysis_rhythm_property_test.dart`, 200 seedelt trial, `PROPERTY_SEED=42`, confidence `[0,1]`, ratio `[0,1]`, subdivision `{1,2,3,4}` — zöld a független gate-futásban |
| 10 | §6.1 utolsó sor — valódi-sértés próba a confidence-korláton | ✅ | Implementer saját próbája (§10 handoff) ÉS a reviewer **másik** mutációja (a szorzó helyett a teljes `beatConfidence`-tényező eltávolítása) — mindkettő pirosra viszi ugyanazt a tesztet, mindkettő visszaállítva |

## Scope-audit

Engedélyezett fájlokon kívüli változás: **nincs.** `git diff --stat
main...codex/e06-r15-rhythm-consistency-and-groove` 13 fájl (12 a brief §4
listájából + a pre-flight saját `docs/adr/0233-...md`-je, ami nem a brief
listáján van, de az orchestrátor saját, ADR 0087 §2 szerinti pre-flight
artefaktuma, nem az implementer diffje). A gépi `scope_audit=ok`
(`.codex-round-status`, `scope_audit_changed=12`) egyezik a kézi diffstattal.

## Megállapítások

### F1 — MINOR — üres beat-grid összeomlasztja a `_modeFor`-t ahelyett, hogy gracefully degradálna

- **Fájl:** `lib/features/audio_analysis/engine/metrics/rhythm_metrics.dart:168-187` (`_modeFor`), hívva a `buildRhythmMetrics:40`-ből, MIELŐTT bármilyen elégtelen-adat kapu (`MetricGate`) lefutna.
- **Probléma:** ha a bemeneti `BeatGrid.beats` üres, `beatGrid.beats.map(...).toSet()` üres halmazt ad, `sources.length != 1` → `0 != 1` → azonnali `ArgumentError` dobás („BeatGrid must not mix target and estimated beat sources.” — a hibaüzenet is félrevezető erre az esetre, hiszen nincs keverés, csak hiány). Ez **mérve valós, elérhető kimenet** a meglévő R12 `BeatGridEstimator.estimate()`-től: a `DefaultFreePlayBeatInference.infer()` `eventTimes.length < 2` esetén `const <BeatPoint>[]`-t ad vissza (`beat_grid_estimator.dart:28`), és az `estimate()` ezt egy **legitim, degraded-státuszú** `BeatGrid`-be csomagolja (`status: inferred.length >= 2 ? available : degraded`, `beat_grid_estimator.dart:104-106`) — tehát egy nagyon rövid/ritka free-play klip természetes kimenete pontosan az a bemenet, amin ez a függvény összeomlik.
- **Hatás:** MA nincs élő hívó (a modul teljesen bekötetlen — SDD/brief §3), tehát production-crash kockázat MOST nincs. De a testvér R14 minta (`timing_metrics.dart:167-172`, `_estimatedBeatDuration`: `beats.length < 2` esetén dokumentált fallback, nem dobás) — amit az ADR 0233 Döntés 3 kifejezetten követendőnek jelöl ki — itt NEM követett minta: a modul minden más helyen (fő `MetricGate`, `SubdivisionAnalyzer` saját belső ág) gracefully `unavailable`/`degraded`-ra fut, csak ez az egy előfeltétel-ellenőrzés dob kivételt. Egy jövőbeli bekötő kör, ha közvetlenül a valós `BeatGridEstimator` kimenetét adja át egy rövid felvételre, kivételt kapna metrika-jelentés helyett.
- **Kötelező javítás (jövőbeli bekötő körnek, NEM blokkolja ezt a kört):** `buildRhythmMetrics` elején (vagy a `_modeFor` belsejében) explicit `if (beatGrid.beats.isEmpty)` ág, amely ugyanazt az `unavailable`/`insufficientEvents` suite-ot adja vissza, amit a `!mainAvailable` ág már ma is előállít — nem új hibakód, csak egy korábbi kilépési pont ugyanahhoz a meglévő ágazathoz.
- **Ellenőrzés:** egy fixture `BeatGrid(beats: [], ...)`-tal hívott `buildRhythmMetrics` ne dobjon, hanem `CapabilityStatus.unavailable`-t adjon `insufficientEvents`-szel — ez a cella MA nincs a suite-ban (sem a hét cellás fixture-mátrixban, sem a 200-trial property tesztben, ahol a grid mindig 10 rögzített beatet kap).
- **Státusz:** OPEN (nem blokkoló — a brief egyetlen acceptance-kritériuma sem írja elő explicit ezt a bemeneti alakot, és a funkció teljes egészében bekötetlen; dokumentálva, hogy a jövőbeli bekötő kör pre-flightja mérje újra).

### F2 — MINOR — az OD-03 stabil-sorozat tolerancia bare literál, nem named constant

- **Fájl:** `lib/features/audio_analysis/engine/metrics/rhythm_metrics.dart:235` (`_longestStableIoiStreak`: `(interval - medianIoi).abs() <= medianIoi * 0.1`).
- **Probléma:** a `0.1` (10%) küszöb inline literál, míg a szomszédos, ugyanabban a commitban bevezetett `SubdivisionCandidates.ambiguityRatio` (`subdivision_analysis.dart:11`, 5%-os küszöb) **named `static const`**. A brief OD-03 kifejezetten „a küszöb néven nevezett konstans a chunkban" formulát ír elő, és a projekt AGENTS.md §10 tiltja az indokolatlan magic number-t. A `docs/rag/chunks/021-...md` dokumentálja a 0.10 értéket prózában, de a Dart-oldali kód nem ad neki nevet.
- **Hatás:** tisztán karbantarthatósági — a viselkedés helyes és tesztelt (`rhythm_metrics_test.dart` OD-03 ág, RAG-chunk formula egyezik), csak a jövőbeli módosítónak egy string-keresés helyett a képlet újraolvasására van szüksége.
- **Kötelező javítás:** egy kis named constant kiemelése (pl. `stableStreakTolerance`) a `rhythm_metrics.dart` tetején, ugyanabban a stílusban, mint `SubdivisionCandidates.ambiguityRatio`.
- **Ellenőrzés:** nincs viselkedésváltozás, csak elnevezés — a meglévő OD-03 tesztek változatlanul zöldek maradnak.
- **Státusz:** OPEN (nem blokkoló, kozmetikai; a diffet érdemben nem növelő körben javítható, különben follow-up).

## Gate-bizonyíték ellenőrzése

| Gate | Állított eredmény | Ellenőrizve |
|---|---|---|
| format | zöld (implementer: „No issues found") | ✅ saját, izolált `/tmp/review-e06-r15` klónban újrafuttatva — zöld |
| analyze | zöld | ✅ saját újrafuttatás — „No issues found! (ran in 18.0s)" |
| test test/features/audio_analysis | zöld, 252 teszt | ✅ saját újrafuttatás — „252: All tests passed!" |
| test test/property | zöld (az új `analysis_rhythm_property_test.dart`-tal) | ✅ saját újrafuttatás — „84: All tests passed!", `PROPERTY_SEED=42` |
| test test/app | zöld | ✅ saját újrafuttatás — „69: All tests passed!" |
| architecture | zöld | ✅ „Architecture dependencies OK (12 allowlisted deviation(s))" — a 12 a MEGLÉVŐ, korábbi körökből örökölt allowlist, ez a kör nem adott hozzá újat |
| secrets | zöld | ✅ „Secret scan OK (2284 file(s) scanned, 0 finding(s))" |
| l10n | zöld | ✅ „L10n parity OK (en → hu, 1037 message(s))" — az additív rhythm/swing ARB-kulcsok mindkét nyelven jelen vannak |
| CI (teljes suite + property + APK) | — | ⏳ orchestrátor dispatch-eli a review után (`round-ci-plan.py` szerint) |

## Architektúra és termékhatárok (AGENTS.md §6/§7/§5)

- Domain-függetlenség: a két új fájl csak `dart:math`-ot és a feature saját
  `domain`/`engine` almoduljait importálja — nincs Flutter/Riverpod/Dio/
  storage-plugin import.
- `public.dart`: additív export, nincs törölt/módosított meglévő export sor.
- Nincs `BuildContext`, widget, `StreamSubscription`, mic/camera/timer/
  wakelock — a modul tisztán szinkron, pure-function számítás, nincs
  lifecycle-erőforrás, amit fel kellene szabadítani.
- §5 termékhatárok: nincs hálózat, nincs nyers audio-perzisztencia, nincs
  secret; a confidence-korlát (§6/#5) kifejezetten a „gyenge confidence nem
  jelenhet meg biztos állításként" elvet szolgálja, és mérve helyesen működik.

## Biztonsági review

A brief `risk = "high"`-nak jelöli (AGENTS.md §15.1) → kötelező dedikált
security review a `security-reviewer` ágenssel, külön dokumentumban:
`docs/reviews/e06-r15-rhythm-consistency-and-groove-security.md`. **Ez a
review-jelentés a security-review-t NEM helyettesíti** — a merge-döntés
mindkét jelentés zöld/PASS állapotát megköveteli.

## Merge-döntés

Az ADR 0052 szerint: minden gate zöld ÉS nincs nyitott BLOCKER/MAJOR →
**merge mehet**, feltéve hogy a dedikált security review is 0
CRITICAL/BLOCKER/MAJOR-t jelent (AGENTS.md §15.1), és a CI (teljes suite +
property + APK vagy full-gate, a `round-ci-plan.py` szerint) is zöld a
merge SHA-n.
