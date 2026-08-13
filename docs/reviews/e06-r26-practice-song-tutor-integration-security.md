# E06-R26 — Security / adatvédelmi / prompt-injection review

- **Kör:** E06-R26 — Practice, Song és Tutor integráció
- **Branch:** `codex/e06-r26-practice-song-tutor-integration`
- **Reviewelt HEAD:** `e8faa8fd` (`git diff 76c127bb..e8faa8fd` — 12 fájl, +1335/−9)
- **Utó-ellenőrzés:** `b1fc0a9d` (a funkcionális review 4 MAJOR-jára adott javító
  commit, `/home/ubuntu/ss-terra-e06-r26`) — **a jelen jelentés minden lelete
  ott is él**, ld. §Utó-ellenőrzés
- **Reviewer:** Claude (dedikált security-reviewer agent, READ-ONLY — production
  kód nem módosult, AGENTS.md §15.1)
- **Dátum:** 2026-08-13
- **Brief kockázat:** `risk = "high"` → kötelező dedikált security review
- **Verdikt:** **FAIL (1 MAJOR)** — 0 CRITICAL · 0 BLOCKER · **1 MAJOR** · 4 MINOR · 3 NOTE

> A MAJOR nem határsértés (§5-listát nem sért) és **nem** bizonyított élő
> szivárgás — a kör teljesen bekötetlen, a flagek mindenhol `false`. A
> besorolás oka: a kör EGYETLEN adatvédelmi szerződését (Tutor-redakció) őrző
> teszt **nem azt a csatornát figyeli, amin a mérésem szerint az adat kifolyik**,
> és a szivárgás a szállított `fromDocument()` kódon át reprodukálható. A
> merge-bar (§11: 0 MAJOR) miatt ez blokkol; a zárás olcsó (érték-szintű
> negatív teszt + döntés a sanitizálásról), ld. MAJOR-1 javasolt irány.

## Scope és módszer

Négy ÚJ adapter az `audio_analysis` feature alatt, plusz 2 flag, a barrel 4 új
exportja és egy határ-őrteszt. **Nincs** hálózati hívás, **nincs** storage-írás,
**nincs** AI-provider hívás, **nincs** új dependency (a `pubspec.yaml` nincs a
diffben), **nincs** új asset, **nincs** engedélykérés ebben a körben.

Mért bizonyíték-alapok:

1. **Pure-Dart szonda a valódi kódon** (`/tmp/r26probe/`): a
   `tutor_analysis_snapshot.dart` szó szerinti másolata, amiből CSAK a
   `flutter_riverpod`/`app_config` import és a provider-blokk lett kivágva (a
   `TutorSnapshotRedaction`, a négy value-osztály, a `TutorAnalysisSnapshot`
   konstruktor, a `fromDocument`, a `_eventKind` és a `_metricFactValue`
   **változatlan**), a domain típusok pedig a review-példány valódi fájljaiból
   `file://` importtal (`lib/features/audio_analysis/domain/**` — nulla
   `package:` import, tisztán Dart). `dart run probe.dart`.
2. **Őr-összehasonlító szonda** (`/tmp/r26arch/`): szintetikus projektgyökér +
   a `tool/check_architecture.dart` `checkArchitecture()` valódi hívása,
   szemben a kör új tesztjének szó szerinti regexével.
3. `dart run tool/check_architecture.dart` a review-példányon →
   `Architecture dependencies OK (12 allowlisted deviation(s))`.
4. `flutter test test/tooling/analysis_cross_feature_boundary_test.dart
   test/features/audio_analysis/application/tutor_analysis_snapshot_test.dart
   test/features/audio_analysis/application/progress_evidence_adapter_test.dart`
   → `All tests passed!` (5 teszt).

---

## MAJOR-1 — A Tutor-redakciós őr KULCS-szintű, a szivárgás pedig ÉRTÉK-szintű: szabad szöveges ID-k szó szerint átmennek a Tutor tényblobba

- **Fájl:** `lib/features/audio_analysis/application/adapters/tutor_analysis_snapshot.dart:147`
  (`insightIds`), `:161-175` (event/hotspot ID-k), `:92-98` + `:100-105`
  (`TutorTargetContext.fromTarget` → `id`), `:131-137` (`toJson`)
- **Őr:** `test/features/audio_analysis/application/tutor_analysis_snapshot_test.dart:17-20`
- **Sértett szabály:** ADR 0132 (Tutor adatvédelem), brief §5 Döntés 3 („nem
  tartalmaz … fájlnevet consent nélkül"), §6 „Tutor-redakció" acceptance
  criterion; AGENTS.md §5 #3 (adat nem szivároghat ki nem szánt csatornán) és
  ADR 0131/0134 (külső tartalom **adatként**, nem utasításként a promptba).
- **Failure scenario (reprodukálva):** egy `AnalysisDocument`, aminek egy
  `OnsetEvent.id`-je / `AnalysisInsight.id`-je / `AnalysisHotspot.id`-je
  (mindhárom **szabad szöveges `String`**, a domain csak `trim().isEmpty`-t
  tilt: `analysis_event.dart:9`, `analysis_insight.dart:26-32`,
  `analysis_hotspot.dart:22-24`) fájlrendszer-útvonalat vagy utasítás-szöveget
  tartalmaz → a `fromDocument()` **szó szerint** átmásolja a snapshotba, a
  `toJson()` kiírja, és a kör redakciós tesztje **ZÖLD marad**:

  ```
  P1 injection text present in Tutor JSON: true
  P1 .wav path present in Tutor JSON: true / true      (private-demo.wav, secret-take.wav)
  P1 committed redaction test still PASSES: true
  P1b targetContext id verbatim: true
  ```

  (a szonda a teszt két assertion-jét szó szerint újrajátssza:
  `forbiddenKeys` → `json.contains('"$key"')`, plusz `json.contains('secret.wav')`).
- **Miért vak az őr:** a `forbiddenKeys` (`:11-19`) egy **kulcsnév**-lista, a
  teszt pedig `'"pcm"'`, `'"fileName"'` … alakú **JSON-kulcsokat** keres. A
  `toJson()` kulcskészlete viszont fix literál (`insightIds`, `metricFacts`,
  `hotspots`, `events`, `targetContext` + a gyerekek `id`/`confidence`/…), tehát
  a kulcs-assertion **konstrukció szerint mindig igaz** — akkor is, ha az
  ÉRTÉKEK bármit hordoznak. Az egyetlen érték-szintű próba
  (`isNot(contains('secret.wav'))`) egy olyan mezőt céloz
  (`AnalysisInputSummary.sourceName`, `analysis_input_summary.dart:29`), amit a
  snapshot **strukturálisan sosem olvas** — a fixture tehát egy már eleve zárt
  ajtót tesztel. Következmény: az orchesztrátor 1. kérdésére a válasz az, hogy
  **a kulcsokra tett aktív enforcement (assert construction-kor) NEM oldaná meg
  a problémát** — az biztonsági színház lenne; a rés az érték-oldalon van.
- **Reachability ma (enyhítő tények — ezért nem CRITICAL/BLOCKER):**
  - a jelenlegi event-ID-gyártó gépi:
    `EventId.onset/strum` → `<runId>:onset:<sampleIndex>`
    (`domain/events/event_id.dart:11-27`), a metric-ID-k pedig **zárt
    katalógusból** valók (`AnalysisMetricResult` ctor:
    `analysis_metric.dart:92-94` → `AnalysisMetricId.contains`), tehát ma egyik
    engine-gyártó sem tesz nem megbízható szöveget ID-be;
  - **egy csatorna viszont már ma külső tartalomból táplálkozik:** importált
    MusicXML/MIDI → `SongId('musicxml-${_slug(title)}')`
    (`song_trainer/data/importers/musicxml_mapper.dart:345`,
    `midi_importer.dart:229`) → `SongDocument.id.value` →
    `_definitionId(...)` (`song_practice_compiler.dart:299-305`) →
    `CompiledPracticeTarget.definitionId` → **ebben a körben**
    `PracticeAnalysisAdapter.toAnalysisTarget` (`practice_analysis_adapter.dart:89`)
    → `AnalysisTarget.id` → `TutorTargetContext.id` → Tutor-JSON. A `_slug`
    `[a-z0-9-]`-re szűkít és a `SongIdValidator` 128 karakterre vág
    (`song_id.dart:126,136-146,182-208`), tehát a támadó-befolyás **erősen
    degradált** (nincs újsor, nincs írásjel) — de nem nulla, és semmi nem
    ellenőrzi a `TutorTargetContext` oldalán;
  - a kör bekötetlen: `grep -rn` szerint **egyetlen** `lib/` fájl sem importálja
    az `audio_analysis/public.dart`-ot, és egyik új adapter neve sem fordul elő
    az adapter-fájlokon kívül; mindkét flag `false` minden környezetben.
- **Javasolt irány (nem én implementálom):** (a) a redakciós tesztet
  **érték-szintűvé** tenni — a fixture tegyen kanárit MINDEN átvitt szabad
  szöveges mezőbe (`event.id`, `insight.id`, `hotspot.id`, `target.id`,
  `CategoryMetricValue`), és a JSON-ra vessen tiltást; (b) a snapshot-határon
  vagy normalizálni (allow-list charset + hosszkorlát, mint a `SongIdValidator`),
  vagy **rögzíteni ADR-ben**, hogy a Tutor-prompt ezeket a mezőket
  strukturáltan, adat-szerepben, escape-elve kapja (ADR 0134) és sosem
  utasítás-kontextusban.
- **Státusz:** OPEN

---

## MINOR-1 — Az „≤ 50 event" kemény korlát mellett a `metricFacts` payload korlátlan (100 000 pontos idősor → 1,58 MB „kompakt" snapshot)

- **Fájl:** `tutor_analysis_snapshot.dart:194-205` (`_metricFactValue`),
  `:199-201` (`TimeSeriesMetricValue` → teljes pontlista), `:116-123` (a cap
  **csak** az `events`-re vonatkozik)
- **Sértett szabály:** brief §5 Döntés 3 („nem tartalmaz … teljes waveformot,
  több ezer eventet"), §3 „kompakt … tények"
- **Failure scenario (reprodukálva):** egy dokumentum EGYETLEN metrikával,
  aminek az értéke 100 000 pontos `TimeSeriesMetricValue`, és 5000 eventtel:

  ```
  P3 events kept: 50 of 5000 (silently truncated, no marker in JSON: true)
  P3 time-series points kept: 100000 of 100000
  P3 Tutor JSON size: 1581484 bytes
  P3 committed redaction test still PASSES: true
  P5 insightIds kept: 2000 of 2000
  ```

  Az `events` kapu 50-nél zár, a `metricFacts`, a `hotspots` és az `insightIds`
  viszont **korlátlan** — az idősor egy idő szerinti amplitúdó-/feature-görbe,
  vagyis pontosan az a „waveform-szerű" payload, amit a §5 Döntés 3 kizár.
- **Miért MINOR (latens):** ma **egyetlen** engine-stage sem gyárt
  `TimeSeriesMetricValue`/`DistributionMetricValue`-t — a `grep` szerint csak a
  codec dekódolja őket (`data/analysis_document_codec.dart:491-501`), és ott
  sincs hosszkorlát a listákon. A csatorna tehát létezik, de gyártó nélkül.
- **Javasolt irány:** a `TutorAnalysisSnapshot` ctorába ugyanolyan kemény
  korlát a `metricFacts`/`hotspots`/`insightIds` darabszámra és a beágyazott
  lista-payload méretére, mint az `events`-re — vagy az idősor/eloszlás
  értékeket a Tutor-határon aggregátumra (min/max/átlag/percentilis) redukálni.
- **Státusz:** OPEN

## MINOR-2 — Néma event-csonkítás: a Tutor 50 eventet lát 5000-ből, jelzés nélkül

- **Fájl:** `tutor_analysis_snapshot.dart:167-168` (`.take(maxEvents)`),
  `:131-137` (`toJson` — nincs `truncated`/`totalEventCount` mező)
- **Sértett szabály:** AGENTS.md §5 #5 (gyenge/hiányos evidencia nem jelenhet
  meg biztos állításként), SDD Ch7 §20.7
- **Failure scenario:** 5000 eventes elemzés → a snapshot 50 eventet visz, és a
  JSON-ban **semmi** nem jelzi a csonkítást (mért: `!json.contains('truncat')`
  → `true`). A jövőbeli Tutor-prompt ezt teljes ténylistaként kapja, és
  levonhat olyan következtetést („mindössze 50 leütés volt", „a gyakorlás
  rövid"), ami a valóságnak ellentmond — miközben a `fromDocument` a
  **kronológiailag első** 50-et tartja meg, tehát a hosszú felvétel vége
  szisztematikusan eltűnik.
- **Javasolt irány:** `totalEventCount` + `eventsTruncated` mező a snapshotban
  (a darabszám nem PII), és a Tutor-prompt sablonjában kötelező caveat.
- **Státusz:** OPEN

## MINOR-3 — `ProgressEvidenceAdapter`: sosem ürülő, korlátlan `Set` egy app-élettartamú provideren + folyamat-lokális „egyszeriség"

- **Fájl:** `progress_evidence_adapter.dart:22` (`e8faa8fd`) / `:25` (`b1fc0a9d`)
  — `final Set<String> _creditedDocumentIds = <String>{}`, `:24-36` / `:27-39`
  (`credit`); a javító commitban `:76-83` az új
  `progressEvidenceAdapterProvider`
- **Sértett szabály:** nincs §5-határ; erőforrás-kezelési anti-pattern +
  a brief §6 „Progress evidence egyszer" kritérium tényleges hatóköre
- **Failure scenario:** (a) a `b1fc0a9d`-ben bevezetett
  `Provider<ProgressEvidenceAdapter?>` **nem** `autoDispose`, tehát a
  `ProviderContainer` élettartamáig (= app-session) ugyanaz a példány él, és a
  `_creditedDocumentIds` minden feldolgozott dokumentum ID-jével nő,
  **soha nem ürül, nincs felső korlát** — hosszú session + sok elemzés esetén
  monoton memórianövekedés (nem DoS, de nem korlátos állapot egy hosszú életű
  objektumon). (b) Az idempotencia **kizárólag folyamat-lokális**: app-újraindítás
  után ugyanaz a `documentId` ismét kreditálható. A brief acceptance
  criterionje („a másodszori feldolgozás nem hoz újat") csak process-en belül
  igaz; a teszt (`progress_evidence_adapter_test.dart:8-12`) pontosan ezt a
  szűk esetet méri.
- **Javasolt irány:** korlátos struktúra (LRU / max-méret) vagy — a bekötési
  körben — perzisztens, dokumentum-ID szerinti kreditálás-napló; a brief
  szövegében pedig pontosítani, hogy az „egyszeri" garancia process-lokális.
- **Státusz:** OPEN

## MINOR-4 — `_fallbackMetric`: idegen metrika confidence-e kerül a skill-evidence-be, és üres dokumentum is „elhasználja" az idempotencia-kulcsot

- **Fájl:** `progress_evidence_adapter.dart:26-36` + `:39-53` (`e8faa8fd`)
- **Sértett szabály:** AGENTS.md §5 #5 (gyenge confidence nem jelenhet meg
  biztos állításként)
- **Failure scenario:** ha a dokumentumban nincs `timing.` prefixű metrika, a
  `firstWhere(..., orElse: _fallbackMetric)` a lista **első** metrikáját adja
  vissza (`:52`), és a visszaadott `AnalysisSkillEvidence.confidence` ennek az
  **idegen** metrikának a confidence-e lesz (pl. egy
  `harmony.chord_coverage.v1` 0,95-je „general skill evidence, confidence
  0,95"-ként jelenik meg). Ha a dokumentum metrikái üresek, a fallback egy
  `unavailable`, `confidence: 0` rekordot ad — az adapter **mégis kiad** egy
  evidence-t (nem `null`), és a `_creditedDocumentIds.add` már megtörtént
  (`:28`), tehát egy későbbi, gazdagabb újraelemzés ugyanarra a
  `documentId`-re már `null`-t kap.
- **Javasolt irány:** ha nincs `timing.` metrika, `null` (vagy explicit
  `unavailableReason`-nel jelölt, confidence nélküli) evidence, és az
  idempotencia-kulcsot csak sikeres kreditálás után elkölteni.
- **Státusz:** OPEN

---

## Megfigyelések (NOTE)

### NOTE-1 — A kör új határ-őrtesztje szigorúan gyengébb, mint a már meglévő `tool/check_architecture.dart` (mért)

- **Fájl:** `test/tooling/analysis_cross_feature_boundary_test.dart:32-34`
- A regex `(?:import|export)\s+'([^']*features/[^']+)'` két mintát nem lát:
  (a) **relatív** cross-feature import (a stringben nincs `features/`
  substring), (b) **dupla idézőjeles** URI (a repo nem kapcsolja be a
  `prefer_single_quotes` lintet — `analysis_options.yaml:25` kommentben van).
  Szintetikus fán mérve:

  ```
  round-guard violations found: 0
  check_architecture violations found: 1
    tool flagged: lib/features/audio_analysis/application/adapters/evasive.dart
                  -> lib/features/practice/domain/model/compiled_practice_target.dart
  ```

  (`import '../../../practice/domain/model/compiled_practice_target.dart';`; a
  dupla idézőjeles `package:` variánsra ugyanez az eredmény.)
- **Miért csak NOTE:** a valódi védelmet a `tool/check_architecture.dart` adja,
  ami tokenizálva olvas (kezeli a dupla/tripla idézőjelet, raw stringet,
  kommentet: `:468-583`) és feloldja a relatív URI-kat (`:411-432`), és a
  `tools/round-gate.sh:232-233` külön lépésként futtatja. A kör kódjára
  ténylegesen mérve: `Architecture dependencies OK (12 allowlisted
  deviation(s))`. Az egyetlen valós cross-feature import az adapterekben
  `package:strumsight/features/practice/public.dart`
  (`practice_analysis_adapter.dart:3`) — szabályos barrel.
- **Javasolt irány:** az új teszt ne duplikálja gyengébben a meglévő őrt —
  hívja meg a `checkArchitecture()`-t a feature-re szűkítve, vagy a
  brief-kritérium hivatkozzon a tool-ra mint mércére.

### NOTE-2 — Az allowlist-őr pontos egyenlőséget vár (12), az ADR 0176 viszont „csak szűkülhet"-et ír

- **Fájl:** `test/tooling/analysis_cross_feature_boundary_test.dart:49-57`
  (`expect(entries, 12)`), `tool/check_architecture.dart:9-22`
- Az orchesztrátor 5. kérdésére a mért válasz: **az allowlist NEM nőtt** — a
  `tool/check_architecture.dart` a diffben egyáltalán nem szerepel
  (`git diff --name-status 76c127bb..e8faa8fd`), bájtra változatlan, és
  pontosan **12** `analyze → live` bejegyzést tartalmaz. A teszt viszont
  egyenlőséget pin-el, így egy jogos **szűkítés** (egy deviáció valódi
  megszüntetése) pirosra váltaná — az őr a szabály egyik irányát fordítva
  kényszeríti. (`entries <= 12` lenne a szabálykövető forma.)

### NOTE-3 — A snapshot „immutable", de a beágyazott idősor-pontlisták mutálhatók (visszaút a dokumentumhoz NINCS)

- **Fájl:** `tutor_analysis_snapshot.dart:116-119` (négy `List.unmodifiable`),
  `:199-201` (a belső `<Object>[timeUs, value]` listák **növelhetők**)
- Mért:

  ```
  P4 inner time-series point list is MUTABLE: 3 entries after add
  P4 outer series list is unmodifiable
  ```

  A brief §6 „Tutor-immutabilitás" kritériumát a teszt csak az
  `events.add` → `UnsupportedError` cellával fedi.
- **Biztonsági hatás: nincs** — a belső listák a `fromDocument`-ben frissen
  létrejött objektumok, mutálásuk **nem** ér vissza az `AnalysisDocument`-hez;
  külön szondával igazoltam, hogy a `List.unmodifiable` **másol** (nem alias):
  `identical(copy, source) == false`, és a forrás utólagos bővítése nem
  látszik a másolaton.

---

## Amit végignéztem és tisztának találtam (negatív bizonyíték)

- **Nyers audio / PCM / waveform a snapshotban: NINCS, strukturálisan.** A
  `fromDocument` az `AnalysisDocument` 15 mezőjéből **négyet** olvas
  (`insights`, `metrics`, `hotspots`, `timeline.events`) + opcionálisan a
  targetet. A PCM-hordozó típus (`PcmAnalysisInput.samples`) sehol nem érinti a
  dokumentumot; a fájlnév (`AnalysisInputSummary.sourceName`,
  `analysis_input_summary.dart:29`), az eszköz-/platform-mező
  (`AnalysisProvenance.platform`, `modelManifestIds`, `dspConfigHash`,
  `featureFlagSnapshot`) és a `signalQuality` **egyáltalán nincs beolvasva** —
  ezért megy át a teszt `secret.wav` próbája.
- **Fail-closed típusbővítésre (fordítási időben).** A `_eventKind`
  (`:184-192`) és a `_metricFactValue` (`:194-205`) **sealed** hierarchián
  switch-el (`AnalysisEvent`, `AnalysisMetricValue`) — egy ÚJ event- vagy
  metrika-típus bevezetése **fordítási hibát** ad, nem néma átfolyást. Az
  orchesztrátor 1. kérdésének „jövőbeli mezőbővítés" ága ezért az ÚJ TÍPUS
  irányban zárt; a nyitott irány a szabad szöveges értékek (MAJOR-1) és egy
  meglévő value-osztály új mezője (az viszont csak akkor szivárog, ha valaki
  explicit felveszi a `Tutor*Fact` osztályba — szándékos lépés).
- **≤ 50 event kemény korlát MINDEN konstrukciós úton (orchesztrátor 2. kérdés):
  IGEN.** A cap a **konstruktorban** él (`:120-122`), valódi `throw
  ArgumentError`-ral (nem `assert` — release buildben is aktív), a
  `List.unmodifiable` **után** mérve. Mért: közvetlen `TutorAnalysisSnapshot(...)`
  51 eventtel → `ArgumentError`; 50 → elfogadva. A `fromDocument` `.take(50)`-je
  ezen felül csak kényelmi csonkítás.
- **Referencia-szivárgás (orchesztrátor 3. kérdés): NINCS.** A snapshot
  mezőinek zárt halmaza: `List<String>` + három value-osztály, amelyek mezői
  `String`/`int`/`double`, plusz az EGYETLEN `Object?`
  (`TutorMetricFact.value`, `:31`). A `fromDocument` ezt mindig primitívre vagy
  friss, `unmodifiable` másolatra képezi (mérve: `List.unmodifiable` másol).
  `AnalysisDocument`-re mutató mező sehol. (Megjegyzés a jövőnek: a `value`
  típusa `Object?`, tehát egy KÉZZEL összerakott `TutorMetricFact(value:
  document)` bármit megtarthatna — ezt a `fromDocument` nem teheti, de a típus
  nem tiltja.)
- **Flag-kapu.** Mindkét új flag `false` a default konstruktorban
  (`feature_flags.dart:39-40`) ÉS a `forEnvironment` gyárban (`:90-91`) —
  **nincs** `dart-define`/`bool.fromEnvironment` felülírás egyikre sem
  (a fájl kommentje is rögzíti, hogy a practice-flageknek nincs override-ja).
  A `usesNetwork` (`:200`) változatlanul csak `accountEnabled ||
  diagnosticsEnabled` — az új flagek helyesen **nem** implikálnak hálózatot.
  Flag OFF → az adapter-providerek `null`-t adnak, a példány létre sem jön
  (`tutor_analysis_snapshot.dart:225-231`, `practice_analysis_adapter.dart:198-205`,
  `song_analysis_adapter.dart:196-201`, `b1fc0a9d`-ben
  `progress_evidence_adapter.dart:76-83`).
- **Sink-hiány (a négy adapterben).** `grep` a `print|debugPrint|Logger|log(|
  stderr|stdout|File(|Directory(|Dio|http|SharedPreferences|SecureStore|
  toString()` mintákra: **nulla találat**. Nincs egyedi `toString()` override,
  tehát a default `toString` csak a típusnevet írja; a `throw
  ArgumentError.value(events, 'events', …)` (`:121`) a **listát** adja át — ez
  hibaüzenetben az event-ID-ket rendereli, de a hívó adja, nem PII-forrás, és
  nem kerül logba (nincs logger). Titok/kulcs/token nincs a diffben.
- **Ellátási lánc.** Nincs új dependency (`pubspec.yaml`/`pubspec.lock` nincs a
  diffben), nincs új asset, nincs natív kód (`native_gate = false`).
- **Tilos zóna.** A `git diff --name-status` szerint **egyetlen** fájl sem
  változott `lib/features/{practice,song_trainer,ai_tutor,progress,analyze}/**`
  alatt — az OD-04 megoldás (típus-inferencia explicit típusnév nélkül,
  `practice_analysis_adapter.dart:70-86`) valóban nulla változást igényelt a
  `practice/public.dart`-on.
- **Barrel-bővítés.** A `public.dart` +4 export, pontosan a négy új adapter
  fájlja — nem szélesít mást. Az `audio_analysis/public.dart`-ot **egyetlen**
  `lib/` fájl sem importálja, tehát a kör teljesen bekötetlen.
- **Prompt-injection az importált tartalom felől.** Zip/MXL/MIDI kicsomagolás,
  path traversal, méretkorlát: **nem érinti ez a kör** (nincs fájl-I/O). Az
  egyetlen import-eredetű adatfolyam a MAJOR-1-ben leírt
  `musicxml → slug → SongId → definitionId → AnalysisTarget.id` lánc.

---

## Utó-ellenőrzés a javító commiton (`b1fc0a9d`, `/home/ubuntu/ss-terra-e06-r26`)

A funkcionális review 4 MAJOR-jára adott javítás **nem érinti** a jelen
jelentés tárgyát: `git diff e8faa8fd..b1fc0a9d` szerint
`tutor_analysis_snapshot.dart`, `public.dart`, `tool/check_architecture.dart`,
`analysis_cross_feature_boundary_test.dart`,
`tutor_analysis_snapshot_test.dart` és `feature_flags.dart` **mind
VÁLTOZATLAN**. Ezért MAJOR-1, MINOR-1, MINOR-2, MINOR-4 és mindhárom NOTE
szó szerint áll `b1fc0a9d`-n is.

Egy lelet **erősödött**: a `ProgressEvidenceAdapter` a javításban kapott egy
nem-`autoDispose` `Provider`-t (`progress_evidence_adapter.dart:76-83`), tehát
a korlátlan `_creditedDocumentIds` mostantól bizonyítottan app-élettartamú
példányon él → MINOR-3 relevánsabb, mint `e8faa8fd`-n volt.

A javításban új típus (`SongChordContext`, display/concert akkord-pár) és a
`clampTempoForReduction` guard-metódus jelent meg — biztonsági/adatvédelmi
szempontból semlegesek (érték-objektum + numerikus alsó korlát, `throw`-alapú
validációval `!isFinite`-ra és `< 0`-ra).

---

## Verdikt

**FAIL (1 MAJOR)** — a merge-bar (§11: 0 MAJOR) miatt blokkol.

A kör adatvédelmi **struktúrája jó**: a snapshot a dokumentum mezőinek szűk,
tudatosan választott részhalmazát viszi, a PCM/fájlnév/eszköz-mezőket
strukturálisan kizárja, a sealed-switch fordítási időben zárja az új
típusokat, az event-korlát valódi `throw`-val minden konstrukciós úton él, és
nincs se hálózat, se log, se storage, se dependency. A **mérce** viszont nem
azt méri, ami sérülhet: a redakciós teszt kulcsokat néz, miközben a mérésem
szerint az érték-oldal (szabad szöveges ID-k) szó szerint átereszt egy
fájlnevet és egy utasítás-szöveget a Tutor tényblobjába — zöld teszt mellett.
Ez a kör EGYETLEN adatvédelmi szerződése, és a következő kör ezt a tesztet
fogja bizonyítéknak tekinteni.

Zárás javasolt minimuma: érték-szintű negatív teszt (kanári MINDEN átvitt
szabad szöveges mezőben) + írásban rögzített döntés arról, hogy a Tutor-prompt
ezeket adatként, escape-elve kapja (ADR 0134). A MINOR-ok és NOTE-ok
follow-upnak megfelelnek.
