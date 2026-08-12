# E06-R15 — Biztonsági / adatvédelmi / prompt-injection review

- **Kör:** E06-R15 — Rhythm consistency és groove proxyk
- **Branch:** `codex/e06-r15-rhythm-consistency-and-groove` @ `d8d21e67`
- **Baseline:** `main` @ `be93642d` (merge-base)
- **Reviewer:** Claude (security-reviewer, READ-ONLY — AGENTS.md §15.1)
- **Kötelezettség:** a brief `risk = "high"` → dedikált security review kötelező
- **Dátum:** 2026-08-12
- **Verdikt:** **PASS** — 0 CRITICAL, 0 BLOCKER, 0 MAJOR, 1 MINOR, 4 NOTE

---

## Összefoglaló

Tisztán számítási/DSP-metrika kör az Audio Analysis V2-ben. Két új engine-fájl
(`rhythm_metrics.dart`, `subdivision_analysis.dart`), additív katalógus- és
ARB-bővítés, két export, tesztek és egy RAG-chunk. **Nincs** nyers audio, mic,
hálózat, secret, tárolás, auth vagy AI-provider érintés (grep + olvasás + gépi
secret-scan igazolva). A modul **bekötetlen**: a `lib/`-ben nincs fogyasztója,
csak a `public.dart` exportja teszi elérhetővé jövőbeli körök számára. Emiatt
minden lelet **latens** — reprodukálható, de nincs jelenlegi bemeneti út hozzá.

A brief §0.0 pre-flight / ADR 0233 Döntés 3 legfontosabb kötése — az
`rhythm.inferred_*` confidence felülről korlátos a felhasznált `BeatPoint`-ok
confidence-átlagával — **minden inferred kimeneti ágon érvényesül**, mérve
(lásd lentebb). A NaN-fail-open hazard (a §5.5 tipikus mintája) **le van zárva**
a domain-határon.

---

## Leletek

### MINOR-1 — `buildRhythmMetrics` szuperlineáris O(események × beatek) költség, bemeneti hosszkorlát nélkül

- **Hely:**
  - `lib/features/audio_analysis/engine/metrics/subdivision_analysis.dart:90-93`
    (`analyze` eseményenkénti hurok) → `:119-133` (`_phaseFor` a beat-tömböt
    esemény**enként** 0-tól újraszkenneli a tartalmazó intervallumig)
  - `lib/features/audio_analysis/engine/metrics/rhythm_metrics.dart:250-255`
    (`_accentPositionConsistency`: beat**enként** `events.where(...).toList()`
    az **összes** eseményen)
- **Failure scenario:** `buildRhythmMetrics` E eseményt és B beatet kap. Mind a
  `_phaseFor` (eseményenként a beateket), mind az `_accentPositionConsistency`
  (beatenként az eseményeket) rendezett bemeneten is 0-ról újraszkennel
  (nincs two-pointer/merge), így a munka O(E·B). E = B = N-re mérve (pure-Dart
  probe, cél-rács, események a beatekbe esve):

  | N | idő |
  |---|---|
  | 1 000 | 44 ms |
  | 2 000 | 55 ms |
  | 4 000 | 200 ms |
  | 8 000 | 729 ms |
  | 16 000 | 3 451 ms |

  Tiszta kvadratikus görbe (~4× duplázásonként); N=32k ~14 s-ra extrapolál. Egy
  hosszú/sűrű klip vagy jövőbeli importált target (sok onset + sok beat) több
  másodperces stallt okozhatna az analízis-isolate-en. A memória-korlát rendben
  (nincs O(N²) allokáció; a `usedBeats` halmaz-deduplikált).
- **Sértett szabály:** ADR 0183 „no unbounded runtime accumulation"; a
  komplexitás sem az ADR 0233-ban, sem a brief §9 Kockázatokban **nincs
  dokumentálva** (szemben az E06-R13 O(n·m)-mel, amit a brief kimondott).
- **Miért MINOR és nem MAJOR:** bekötetlen (nincs untrusted feed — a `lib/`-ben
  0 fogyasztó, csak `public.dart` export), a valós audio-eredetű N kicsi
  (5 perc szólógitár ≈ 2400 onset / 600 beat → ~50-100 ms), és **egyetlen
  in-round acceptance-kritérium sem bukik el** — a property-teszt max. 24
  eseményt és 10 beatet jár be (`analysis_rhythm_property_test.dart:57,72`), a
  skálát semmi nem fedi. Kalibráció: az E06-R13 review azonos, bekötetlen
  szuperlineáris leletet MINOR-nak minősített
  (`docs/reviews/e06-r11-...` és az E06-R13 precedens).
- **Javítás iránya:** two-pointer merge a rendezett események és beatek felett
  (mindkét szkennelés O(E+B)-re esik), és/vagy fail-closed bemeneti hosszkorlát.
  **MUST-fix-before** a modul untrusted/importált sűrű bemenetre kötése (R16
  dinamika, R25 session comparison, bármely import-út).

---

### NOTE-1 — `_modeFor` félrevezető hibaüzenet üres beat-rácsra

- **Hely:** `rhythm_metrics.dart:168-174`
- **Scenario:** `BeatGrid(beats: const [])` konstruálható (a `BeatGrid` ctor
  nem tiltja az üres listát). Ekkor `sources` üres halmaz, `length != 1` →
  `throw ArgumentError('BeatGrid must not mix target and estimated beat
  sources.')` — az üzenet „kevert forrást" állít, holott a rács **üres**. Mérve
  reprodukálva.
- **Értékelés:** **fail-closed** (dob, nem crash-el, nem hurkol), és **nem
  szivárogtat** belső adatot — kizárólag a hibaüzenet pontatlansága. Nem
  biztonsági sértés; robusztussági megjegyzés.
- **Javítás iránya:** külön ág üres `beats`-re (pl. `insufficientEvents`/
  explicit „empty grid" üzenet).

### NOTE-2 — minden metrika `evidence` mezője az összes `event.id`-t másolja

- **Hely:** `rhythm_metrics.dart:81, 92, 104` (`evidence: <String>[for (final
  event in events) event.id]`)
- **Scenario:** ~6 metrika, mindegyik egy E-hosszú `event.id`-listát épít
  (külön példányonként). Jelenleg **nincs** perzisztálva (a
  `analysis_document_codec` változatlan) és nincs log-sink; az `event.id`-k
  szintetikus azonosítók (validáltan nem-üres, nem PII/nem nyers audio).
- **Értékelés:** forward-looking redakció-/memória-megjegyzés: ha egy jövőbeli
  kör az `evidence`-t szerializálja vagy logolja, az összes `event.id` kikerül.
  Alacsony kockázat (az id nem érzékeny), de a redakció-review bar ott
  esedékes. Memória-amplifikáció elhanyagolható.

### NOTE-3 — `AnalysisMetricResult.confidence` NaN-vak ellenőrzés (R02 kód, diffen kívül)

- **Hely:** `lib/features/audio_analysis/domain/analysis_metric.dart:98`
  (`if (confidence < 0 || confidence > 1) throw`) — **nem** ebben a körben
  módosított fájl (E06-R02).
- **Scenario:** a `< 0 || > 1` idióma **elfogadja** a `double.nan`-t
  (`NaN < 0` és `NaN > 1` is `false`), és mérve `double.nan.clamp(0,1) = 1.0`
  (azaz egy NaN confidence, ha eljutna a clampig, **1.0 = hamis maximum
  bizonyosság** lenne — §5.5 sértés). **Ebben a körben nem elérhető:** a
  producerek csak véges confidence-t adnak (lásd „Lezárt nem-leletek / NaN").
  Az E06-R02 review már katalogizálta ezt latensként.
- **Értékelés:** defense-in-depth megjegyzés, nem R15-lelet; az R15 sosem táplál
  NaN-t ebbe a ctorba (mérve).

### NOTE-4 — hibaüzenet interpolálja az `event.id`-t

- **Hely:** `rhythm_metrics.dart:193-196`
  (`ArgumentError.value(event.confidence, 'events[${event.id}].confidence')`)
- **Scenario:** nem-véges esemény-confidence esetén az `event.id` a
  hibaüzenetbe kerül. Az `event.id` validáltan nem-üres szintetikus azonosító
  (nem secret/PII/nyers audio), és az `ArgumentError` ebben a körben nincs
  log-/jelzés-sinkbe vezetve.
- **Értékelés:** tiszta; a teljesség kedvéért jelezve (§5 „hibaüzenet nem
  szivárogtat belső adatot" — itt nem szivárog érzékeny adat).

---

## Lezárt nem-leletek (bizonyítékkal)

- **Confidence-korlát (§5.5 / ADR 0233 Döntés 3) — HELYES minden inferred
  ágon.** `_confidence` (`rhythm_metrics.dart:205-218`) inferred módban
  `(eventConfidence * beatConfidence).clamp(0,1)`, ahol
  `beatConfidence = mean(usedBeats.confidence)`. Mivel `eventConfidence ≤ 1`
  (események `[0,1]`-re validáltak), a szorzat **mindig ≤ beatConfidence** =
  a felhasznált beatek confidence-átlaga. Ugyanezt a `confidence` értéket
  olvassa a `percentage` (`:76`), `scalar` (`:89`) és `unboundedRatio` (`:101`)
  is; az `unavailable` ág hardkódolt `confidence: 0` (`:63`). **Nincs
  megkerülő ág.** Mérve: homogén `BeatPoint.confidence = 0.4`, `event.confidence
  = 1` mellett a max publikált inferred confidence = **0.3999… ≤ 0.4**;
  `swingStatus = notApplicable`. A `≤ 0.4` acceptance-cellát és a §10
  valódi-sértés próbát (korlát kiszedése → 1.0 > 0.4 → PIROS) a
  `rhythm_metrics_test.dart:134-160` fedi.
- **NaN-fail-open — LEZÁRVA a határon.** `_validateEvents`
  (`rhythm_metrics.dart:189-203`) `!event.confidence.isFinite` → dob (bezárja
  az `AnalysisEvent` ctor R02-es NaN-elfogadó rését). `BeatPoint`
  (`beat_point.dart:14`) `!confidence.isFinite || <0 || >1` → dob, tehát
  `beat.confidence` mindig véges `[0,1]`. Így NaN sosem ér el a `.clamp`-ig
  (mérve: NaN esemény-confidence → `ArgumentError`).
- **Nincs IO / hálózat / secret / mic / audio / log sink** a két új
  prod-fájlban (grep: `dart:io|http|dio|Socket|File|print|log|Supabase|
  SecureStore|SharedPreferences|toJson|jsonEncode|base64|writeAs|readAs` — 0
  találat). Bekötetlen: `lib/`-ben 0 fogyasztó (`buildRhythmMetrics|
  RhythmMetricReport|SubdivisionAnalyzer` — csak a `public.dart:53-54` export).
- **Prompt-injection §5.1 — N/A.** Nincs AI-provider, tool-hívás, tudásbázis,
  prompt vagy provider-válasz. A bemenet numerikus/enum domain-objektum
  (`List<AnalysisEvent>`, `BeatGrid`), nem szöveg. A metrika-ID-k hardkódolt
  `const`-ok (`analysis_metric_catalog.dart:56-77`) — nincs bemenetből épített
  ID/kulcs, így nincs injekció-alakú string-interpoláció. Az ARB-kulcsok
  statikus, placeholder nélküli címkék.
- **Swing target-only invariáns — strukturálisan tartva.** Az inferred suite
  `swingRatio`-ja `null` (`analysis_metric_catalog.dart:142-151`); a publikáló
  (`:155-157`) és az unavailable (`:117`) ág is `if (ids.swingRatio case final
  swingId?)` kapun megy, így inferred módban swing sosem publikálódik. Mérve.
- **Metric ID integritás.** Minden használt ID a `AnalysisMetricId.known`-ban
  (`:104-114`), különben az `AnalysisMetricResult` ctor dob (`:92-93`); a
  target/inferred halmaz metszete üres (a katalógus-teszt fedi). Nincs
  unknown-ID crash.
- **Fail-closed provenance.** `_modeFor` (`:168-187`) kevert vagy azonosítatlan
  beat-forrásra `ArgumentError`-t dob — nem talál ki módot. A publikus
  `SubdivisionAnalysis.forCandidateDeviations` (`subdivision_analysis.dart:30-37`)
  nem-támogatott kulcsra / nem-véges / negatív deviációra dob; üres map →
  `unavailable`.
- **Degenerált bemenetek — nincs crash/hurok/0-osztás.** Minden osztás védett
  (`medianIoi <= 0`, `long/short <= 0`, `width <= 0`, `duration <= 0`,
  `values.isEmpty`). Mérve: 1-beat rács → 6 metrika, subdiv `unavailable`;
  beatgridből kilógó események (inferred) → confidence `{0.0}` (biztonságos
  alulbecslés, nem hamis-magas); üres beat-rács → fail-closed `ArgumentError`.
- **Nincs secret / token / PII** a tesztekben, ARB-ban, RAG-chunkban (grep +
  olvasás), és a gépi őr `tool/ci/check_secrets.dart` **0 találat / 2284 fájl**.
  A `rhythm_metric_catalog_test.dart:47-60` maga is teszteli a §5.1 „nincs
  stiláris címke/score" határt (regex `(swing|shuffle|groove)_?(score|style)`
  az ID-kon + mindkét ARB-fájlon) — ez POZITÍV.
- **Scope.** Az implementer-commit (`d8d21e67`) pontosan a brief §4
  allowed_paths 12 fájlját érinti; az ADR 0233 külön pre-flight commit
  (`1b523f7d`, orchestrátor-hatáskör, ADR 0087 §2), nem implementer-drift.

---

## Amit végignéztem

`rhythm_metrics.dart` (330 sor) és `subdivision_analysis.dart` (157 sor) teljes
olvasása; a domain-függőségek (`beat_point`, `beat_grid`, `analysis_event`,
`analysis_metric`, `analysis_capability`, `metric_gate`) validációja; a
katalógus- és export-bővítés; mindkét ARB-diff; mind a 4 tesztfájl; a
RAG-chunk; a brief §0.0 pre-flight és az ADR 0233. Mérési bizonyíték: pure-Dart
probe (a gráf `dart:` + relatív import, nincs `pub get`) a komplexitásra, a
confidence-korlátra, a degenerált bemenetekre és a NaN-kezelésre; `git diff`
scope-ellenőrzés; broad secret-grep a teljes diffen; `check_secrets.dart`
gépi futtatás.

**Merge-ajánlás:** nincs blokkoló lelet. A MINOR-1 (O(E·B)) MUST-fix-before a
modul untrusted/importált sűrű bemenetre kötése — a merge-et most nem blokkolja.
