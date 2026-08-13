# E06-R24 — Security / adatvédelmi / prompt-injection review

- **Kör:** E06-R24 — Többrétegű, zoomolható timeline
- **Branch:** `terra/e06-r24-layered-zoomable-timeline`
- **Diff:** `git diff 2a24cacc..7081b7bc` (16 fájl, +1292/−3), HEAD `7081b7bc`
- **Reviewer:** Claude (dedikált security-reviewer agent, READ-ONLY — production kód nem módosult, AGENTS.md §15.1)
- **Dátum:** 2026-08-13
- **Brief kockázat:** `risk = "high"` → kötelező dedikált security review
- **Verdikt:** **PASS** — 0 CRITICAL · 0 BLOCKER · 0 MAJOR · **0 MINOR (1 FIXED)** · 4 NOTE

> **Javítás után (orchesztrátor, 2026-08-13, javító kör #1, commit
> `4b895474`):** MINOR-1 zárva — a forrásolvasó teszt most a valódi
> `PcmAnalysisInput` típusnevet és a `domain/analysis_input.dart` importot
> tiltja a fantom `pcmSamples` string helyett
> (`test/features/audio_analysis/presentation/analysis_timeline_screen_test.dart`).
> A négy NOTE tájékoztató marad, nem igényelt javítást.

## Scope

Tisztán presentation-réteg: az új `AnalysisTimelineScreen` egy MÁR
ELKÉSZÍTETT `AnalysisDocument`-et jelenít meg (`GoRouterState.extra`-n át
kapja). Nincs hálózati hívás, nincs storage-írás, nincs auth, nincs
AI-provider hívás ebben a körben.

## Megállapítások

### MINOR-1 — A „nincs nyers PCM a UI-ban" forrásolvasó teszt egy fantom-tokent tilt, nem a valódi PCM-mezőt

- **Fájl:** `test/features/audio_analysis/presentation/analysis_timeline_screen_test.dart:154-164`
- **Sértett szabály:** AGENTS.md §5 (nyers audio nem kerülhet a UI-ba) / ADR 0217 — az ellenőrző-mechanizmus szigora, nem maga a határ (az jelenleg tartja magát, ld. lent).
- **Probléma:** a teszt csak két szó szerinti stringet tilt:
  ```dart
  expect(sources, isNot(contains('data/input/')));
  expect(sources, isNot(contains('pcmSamples')));
  ```
  A tényleges nyers-audio hordozó a `PcmAnalysisInput.samples`
  (`List<double>`, `lib/features/audio_analysis/domain/analysis_input.dart:54,61`),
  amit az engine/data rétegek `input.samples`/`input.input.samples` alakban
  olvasnak. A `'pcmSamples'` literál **fantom**: `grep -rn 'pcmSamples' lib/
  test/` szerint EGYETLEN production fájlban sem fordul elő — kizárólag egy
  AI-tutor redakciós canary-tesztben (`test/features/ai_tutor/application/
  context/redaction_test.dart:15`, `prompts/prompt_injection_test.dart:99`).
  Egy jövőbeli presentation-módosítás, ami importálja a
  `domain/analysis_input.dart`-ot (az útvonala `domain/`, nem
  `data/input/`) és `.samples`-t vagy a `PcmAnalysisInput` típust olvassa,
  MINDKÉT assertion mellett zölden futna át.
- **Enyhítő tény (miért MINOR, nem MAJOR):** a határt ma ténylegesen a
  **típus-struktúra** tartja: az `AnalysisDocument` (a screen EGYETLEN
  bemenete) sehol nem hordoz `samples`/`PcmAnalysisInput`-ot — mezői
  (`input: AnalysisInputSummary`, `timeline`, `capabilities`, `metrics`,
  `hotspots`, `insights`, `warnings`) egyike sem. Nincs elérhető
  regressziós út a dokumentum típusán át, és a jelen diff egyetlen fájlja
  sem hivatkozik PCM-re.
- **Javasolt irány:** a teszt a valódi felületet tiltsa: `PcmAnalysisInput`
  típusnév, a `.samples` mezőelérés mintája, és a `domain/analysis_input.dart`
  import — a strukturális garanciát (a dokumentum nem hordoz PCM-et) tartsd
  meg elsődleges, teszttel alátámasztott bizonyítékként.
- **Státusz:** OPEN (nem blokkol — follow-up)

## Megfigyelések (NOTE)

- **NOTE-1 — Capability-státusz kezelés fail-closed a hiányzó riportra
  (helyes), de fail-open irányú egy jövőbeli 5. státuszértékre.**
  `timeline_lanes.dart:143-167` — a `_lane()` keresés ma helyesen
  fail-closed (hiányzó riport → `unavailable` → rejtve, magyarázattal, ADR
  0243 Döntés 4 szerint); `degraded` helyesen látható marad
  figyelmeztetéssel. A branch alakja `if (null || unavailable ||
  notApplicable) hide; else show` — a `CapabilityStatus` ma zárt, négy
  értékű, mind a négy kezelve, tehát NEM reprodukálható — de egy jövőbeli
  5. enum-érték az `else`-ágba esne és FIGYELMEZTETÉS NÉLKÜL, biztosként
  jelenne meg. Előretekintő javaslat: `if (available) show; else if
  (degraded) show+warn; else hide` alakra váltani.
- **NOTE-2 — Duplikált ARB-kulcsok mindkét nyelven** (ugyanaz a lelet, mint
  a normál review F4-je — nem biztonsági kérdés, nincs secret/PII érintve,
  minden placeholder biztonságos (`{count}` int, előformázott Duration,
  sosem nyers dokumentum-string); a normál reviewnak jelezve.
- **NOTE-3 — `TimelineViewState` halott kód, és a klasszikus
  nullable-copyWith-nem-tud-törölni mintát hordozza** (nem biztonsági,
  ugyanaz a fájl, mint a normál review F5-je) — `copyWith` `selectionStart
  ?? this.selectionStart` miatt a selection sosem törölhető `null`-ra ezen
  keresztül. Ártalmatlan, amíg használaton kívül van; jelzve, hogy egy
  jövőbeli bekötés ne örökölje a hibás törlés-szemantikát.
- **NOTE-4 — A `public.dart` barrel bővül `TimelineViewport`-tal (ártalmatlan
  — csak `Duration`+`logicalWidth`, nincs benne evidence/PCM); a
  `visibleItemsFor` minden gesztus-frame-en O(n) végigpásztázza a teljes
  item-listát** — a widget-/painter-szám helyesen korlátos (ez a brief
  mérőszáma), de a szűrés maga lineáris. Az `AnalysisDocument` a
  felhasználó SAJÁT, pipeline-korlátozott eredménye, tehát ez teljesítmény-
  észrevétel, nem biztonsági DoS (megbízható, korlátos bemenet).

## Amit tisztának találtam (bizonyítékkal)

- **Nincs nyers PCM/audio a UI-ban (§5, ADR 0217):** a `presentation/`
  teljes grep-je (`pcm|samples|Float32List|Int16List|Uint8List|rawAudio|
  data/input`) csak megnyugtató kommentekre illeszkedik; a fenti két
  strukturális tény miatt a screen bemenetéből a PCM elérhetetlen.
- **Nincs rejtett hálózat/secret (§5.2):** `http|Dio|apiKey|token|secret|
  password|signing` grep az új fájlokon → nulla találat; egyik új
  production fájl sem importál `Dio`/`http`/Supabase-t.
- **Prompt injection / adat utasításként értelmezése nincs:** egyetlen
  dokumentum-eredetű string sem jut el végrehajtásig, navigációig, logig,
  kivétel-üzenetig vagy Semantics-labelig. Az egyetlen dokumentum-string,
  ami a widget-rétegbe jut, az akkord `label` (`timeline_lanes.dart:42`) —
  ez tárolt, de SOSEM kirajzolt adat (`_LanePainter` csak `start`/`finish`-t
  használ). `AnalysisHotspot.id`/`metricIds`/`evidenceIds`,
  `AnalysisInputSummary.fingerprint` sosem kerül olvasásra a timeline
  kódban. A route path a konstans `AppRoutes.analysisTimeline`, sosem
  adat-eredetű string; az `extra` a típusos objektum, nem string.
- **Nincs PII logban/kivételben/Semantics-ben:** nincs `print`/`log`/
  `debugPrint` egyetlen új fájlban sem. Minden Semantics-label l10n-string +
  egész számláló + `formatDuration` kimenet. A két `throw` (`HotspotNavigator`
  `StateError`, `TimelineViewport.zoomBy` `ArgumentError.value(scale,…)`)
  statikus szöveget/gesztus-skalárt hordoz — nincs benne fájlútvonal,
  eszközazonosító vagy felhasználói tartalom.
- **Gyenge confidence nem jelenik meg biztosként (§5):** `degraded` látható
  marad figyelmeztetéssel; `unavailable`/`notApplicable`/hiányzó riport
  rejtve, magyarázattal. Pontosan az ADR 0243 szerint.
- **Flag-kapu + fail-closed routing:** az új `GoRoute` az
  `if (audioAnalysisV2Enabled) …[ ]` blokkban él (elérhetetlen flag-off
  alatt); a `redirect` a hibás/hiányzó `extra`-t `AppRoutes.live`-ra tereli,
  tehát a builder `state.extra! as AnalysisDocument` castja csak a redirect
  garanciája UTÁN fut — nincs null-deref.
- **Degenerált bemenet ellen robusztus:** a `TimelineViewport` konstruktor-
  invariánsai `assert`-ek (release-ben eldobva), de az `AnalysisTimeline`
  valódi `ArgumentError`-t dob negatív `duration`-re és tartományon kívüli
  `bars`-ra, tehát az a degenerált dokumentum, ami egy `clamp(lower>upper)`
  crash-t okozhatna, nem is konstruálható.

## Merge-döntés

Biztonsági szempontból **nincs akadálya a merge-nek** — a nyitott 3 MAJOR
(normál review F1–F3) és a fenti MINOR-1 (ez a review) nem
biztonsági/adatvédelmi jellegű blokkoló, hanem a normál review + ez a
follow-up listája szerint javítandó a soron következő javító körben.
