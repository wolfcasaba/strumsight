# E06-R17 — Biztonsági / adatvédelmi / prompt-injection review

- **Kör:** E06-R17 — Monofonikus pitch capability
- **Branch:** `codex/e06-r17-monophonic-pitch-capability` @ `6dd76109` (a review a
  `2c02f031` feature-commit **prod-kódját** fedi; a fix-kör csak `test/**`-et érint)
- **Baseline:** `main` @ `2c08dc5b` (merge-base)
- **Reviewer:** Claude (security-reviewer, READ-ONLY — AGENTS.md §15.1)
- **Kötelezettség:** a brief `risk = "high"` → dedikált security review kötelező
- **Dátum:** 2026-08-12
- **Verdikt:** **PASS** — 0 CRITICAL, 0 BLOCKER, 0 MAJOR, 1 MINOR, 2 NOTE

> **ÚJRA-FUTÁS.** Az előző kísérlet helyesen jelezte, hogy az implementáció még
> nem volt a GitHubon, és megtagadta a review-t. A `2c02f031` feature-commit
> mostanra jelen van — függetlenül igazolva friss `/tmp` klónból
> (`git cat-file -t 2c02f031` → commit; a branch 15 lib/test fájlt ad hozzá) —,
> így a review most a valódi prod-kódot fedi.

---

## Összefoglaló

Tisztán számítási monofonikus-pitch capability az Audio Analysis V2-ben, az
`analysisPitchEnabled` flag mögött (alapérték: **false**). Új domain
value-típusok (`PitchFrame`, `MonophonicPitchSegment`), engine (`PitchCapabilityGate`,
`MonophonicPitchSegmentBuilder`, `PitchFrameExtractor`, `pitch_metrics.dart`),
additív katalógus- és ARB-bővítés (7 metric ID + 7 ARB kulcs), két domain- és
három engine-export. **Nincs** hálózat, mic, nyers-audio perzisztencia/log,
secret, auth vagy AI-provider érintés (grep + olvasás + gépi secret-scan
igazolva). A modul **bekötetlen**: a `lib/`-ben 0 fogyasztó, csak a `public.dart`
export teszi elérhetővé. Emiatt minden lelet **latens** — reprodukálható, de
nincs jelenlegi bemeneti út hozzá.

Két kiemelt biztonsági kötés **mérve teljesül**:

- **A capability-kapu seam-je (§5.5).** Az `onAvailable` (a metrika-számítás
  egyetlen belépője) **csak** minden kapu (flag → monofon target → frames →
  voiced-ratio → medián confidence → spread → zaj) után hívódik. Flag-off és
  polifon (nagy spread) bemeneten **0** hívás; jó bemeneten **1**.
- **NaN-fail-open LE VAN ZÁRVA a value-típus határon.** A §5.5/E06-R02 tipikus
  `< lo || > hi` NaN-elfogadó idiómája **itt nem ismétlődik**: mind a négy
  érintett ctor valódi `throw`-val (`!x.isFinite || …`) dob NaN-re, így a gate/
  metric futásidejű puszta `<`/`>` összehasonlításai **bizonyítottan** sosem
  látnak NaN-t.

A `lib/core/audio/dsp`, `lib/core/audio/pitch`, `lib/features/tuner` blast-radius
**üres** (a core YIN/framer/tuner bájt-azonos).

---

## Leletek

### MINOR-1 — `buildPitchMetrics` O(szegmens × célhang) költség, bemeneti korlát és dokumentáció nélkül

- **Hely:**
  - `lib/features/audio_analysis/engine/metrics/pitch_metrics.dart:141-144`
    (`matched`: **minden** szegmensre `_targetFor(...)`) → `:254-260`
    (`_targetFor` = `targets.reduce(...)` az **összes** célhangon)
  - `lib/features/audio_analysis/engine/metrics/pitch_metrics.dart:268-284`
    (`_dropoutRatio`: célhang**onként** az **összes** szegmens, beágyazott hurok)
- **Failure scenario:** `buildPitchMetrics` S szegmenst és N célhangot kap. Mind a
  `matched` építése (szegmensenként a célhangokat), mind a `_dropoutRatio`
  (célhangonként a szegmenseket) rendezett bemeneten is teljes bejárással
  dolgozik (nincs elő-index/two-pointer), így a munka O(S·N). S = N-re mérve
  (pure-Dart probe a **valódi kódon**, a klón `package_config`-ján keresztül):

  | N | idő |
  |---|---|
  | 1 000 | 35 ms |
  | 2 000 | 73 ms |
  | 4 000 | 168 ms |
  | 8 000 | 619 ms |

  Szuperlineáris görbe (~3,7× a 4k→8k duplázáson); N=40k ~15 s-ra extrapolál
  (az E06-R11 `_mergeShortSegments` 13 s@40k precedensével egyezik). Egy
  hosszú/sűrű klip vagy jövőbeli importált target több másodperces stallt
  okozhatna az analízis-isolate-en. A memória-korlát rendben (nincs O(N²)
  allokáció).
- **Sértett szabály:** ADR 0183 „no unbounded runtime accumulation"; a komplexitás
  sem az ADR 0235-ben, sem a brief §9 Kockázatokban **nincs dokumentálva**
  (grep: 0 találat).
- **Miért MINOR és nem MAJOR:** bekötetlen (a `lib/`-ben 0 fogyasztó, csak
  `public.dart` export), a flag alap-false, a valós monofon gyakorlat N-je kicsi
  (pár száz hang → <10 ms), és **egyetlen in-round acceptance-kritérium sem bukik
  el** (a property/unit tesztek kis N-t járnak). Kalibráció: az E06-R15 review
  azonos, bekötetlen, dokumentálatlan szuperlineáris leletet MINOR-nak minősített
  (MINOR-1).
- **Javítás iránya:** a célhangokat idő szerint elő-indexelni (bináris keresés /
  two-pointer sweep a rendezett szegmens-kezdetekre) a reduce-per-szegmens
  helyett; a dropout-lefedettséget egyetlen összefésülő bejárással. **MUST-fix-
  before** a modul untrusted / hosszú-audio / importált sűrű targetre kötése.

---

### NOTE-1 — `PitchCapabilityGate(minimumVoicedRatio: 0)` + csupa-unvoiced bemenet → `RangeError` (median üres listán)

- **Hely:** `pitch_capability_gate.dart:28-40` (a ctor csak `minimumVoicedRatio < 0`-t
  utasít el, a **0-t megengedi**) → `:84` (`voicedRatio < minimumVoicedRatio`) →
  `:91-93` (`_median` a voiced frame-eken) → `:146-152` (`_median` üres listán
  `sorted[-1]`)
- **Failure scenario:** ha egy hívó `PitchCapabilityGate(minimumVoicedRatio: 0)`-t
  konstruál és csupa unvoiced frame-et ad, akkor `voicedRatio = 0`, a `0 < 0`
  **false** → a kapu **nem** tér vissza `unavailable`-lel, továbbmegy a
  `_median([])`-hez → `RangeError` (unhandled). Mérve reprodukálva.
- **Sértett szabály:** robusztusság (ADR 0183 degenerált-bemenet fail-closed);
  **nem** termékhatár-sértés — crash, nem hamis pitch-adat, nem szivárgás.
- **Miért NOTE:** az alap `minimumVoicedRatio = 0.35` biztonságos (voiced üres →
  `0 < 0.35` → `unavailable/insufficientEvents`); a hiba egy **nem-alapértelmezett,
  önmagában értelmetlen** konfigot (0 voiced-ratio küszöb) **és** csupa-unvoiced
  bemenetet igényel; a modul bekötetlen (0 hívó a gate-et egyáltalán nem
  konstruálja). Fail-closed (dob), nem hamis-magas confidence.
- **Javítás iránya:** a ctor utasítsa el a `minimumVoicedRatio <= 0`-t (ahogy a
  `maximumPitchSpreadCents` már `<= 0`-t tilt), vagy guardolni a `voiced.isEmpty`
  ágat a `_median` előtt. **Reclassify MINOR**, ha valaha egy hívó
  konfigurálható/injektált `minimumVoicedRatio`-val hozza létre a kaput.

### NOTE-2 — az exportált `centsBetween` nem-pozitív Hz-re nem-véges értéket ad

- **Hely:** `monophonic_pitch_segment_builder.dart:79-80` (`centsBetween`);
  `public.dart:61` (a builder exportja **cross-feature publikussá** teszi a
  top-level segéd-függvényt)
- **Failure scenario:** `centsBetween(leftHz, rightHz) = 1200*log(rightHz/leftHz)/ln2`.
  Nem-pozitív bemenetre nem-véges — mérve: `centsBetween(0,220)=Infinity`,
  `centsBetween(220,0)=-Infinity`, `centsBetween(-1,1)=NaN`. Belső hívó **sosem**
  ad nem-pozitívat (minden frekvencia a `PitchFrame`/`MonophonicPitchSegment`
  ctorban `>0`-ra validált), de a `public.dart` mostantól cross-feature API-ként
  exportálja a függvényt, **guard nélkül**.
- **Sértett szabály:** forward-looking §5.5 (egy nem-véges cent-érték egy jövőbeli
  fogyasztónál hamis metrikaként jelenhetne meg) + API-higiénia. Jelenleg **nem
  elérhető** (nincs külső hívó).
- **Miért NOTE:** nincs jelenlegi fogyasztó; tiszta függvény, nincs IO/secret/
  side-effect; a belső használat mind validált-pozitív bemeneten fut.
- **Javítás iránya:** a `centsBetween`-t ne exportáld a `public.dart`-ból (tartsd
  feature-privátnak), vagy guardold a bemenetet `> 0`-ra (különben explicit
  fail-closed dobás).

---

## Lezárt nem-leletek (bizonyítékkal)

- **Property 1 — Nincs hamis pitch polifon bemeneten (kapu-sorrend + seam).** A
  `PitchCapabilityGate.evaluate` szigorúan sorrendben kapuz: flag (`:57`) →
  monofon target (`:66`) → frames üres (`:75`) → voiced-ratio (`:84`) → medián
  confidence (`:94`) → spread/polifon (`:98`) → zaj (`:101-108`), és **csak
  ezután** hívja az `onAvailable`-t (`:121`) — ez a metrika-számítás egyetlen
  belépője (`pitch_metrics.dart:100-110`). Mérve: flag-off → `notApplicable`,
  onAvailable **0** hívás; polifon (nagy spread) → `unavailable/polyphonicInput`,
  **0** hívás; jó bemenet → `available`, **1** hívás. §5.5 POZITÍV.
- **Property 6 — NaN-fail-open LE VAN ZÁRVA a value-típus határon.** A §5.5/E06-R02
  tipikus `< lo || > hi` idiómája **nem ismétlődik**: a `PitchFrame` (`:16`
  confidence, `:22-25` frequencyHz), a `MonophonicPitchSegment` (`:23` medianHz,
  `:29-31` cents, `:34` confidence), a `PitchTargetNote` (`pitch_metrics.dart:19-24`)
  és a `PitchCapabilityGate` saját küszöbei (`:28-40`) mind `!x.isFinite || …`
  valódi `throw`-val validálnak. Mérve: mind a négy kritikus ctor `ArgumentError`-t
  dob NaN-re. **Következmény:** a gate futásidejű összehasonlításai (`:84`, `:94`,
  `:98`) puszta `<`/`>`-t használnak, de az operandusok **bizonyítottan végesek**
  (a forrás value-típus elutasítja a nem-végeset), így ez **nem** NaN-fail-open —
  erősebb garancia, mint az R02-ben, ahol nyers `double` ért a comparisonhöz. A
  `buildPitchMetrics` a `confidence`-t szintén `!isFinite||<0||>1` throw-val
  ellenőrzi (`:132`); a `signalQuality` NaN-ját a gate explicit `!isFinite`
  kapuk fogják (`:103-104`).
- **Property 2 — Nincs diagnosztikai keretezés.** A 7 új ARB kulcs kizárólag
  metrika-**nevek** ("Median cents error" / „Medián centhiba", "Pitch stability" /
  „Hangmagasság stabilitása", stb.) — nincs gitár-setup/health verdikt. A
  `pitch_metrics.dart:124-126` doc-comment explicit: „Neither metric diagnoses an
  instrument setup or tuning fault (SDD §17.4)"; a katalógus `:97-98`:
  „descriptive intonation evidence, never a diagnosis". A median cents error
  előjeles **relatív cent-offset tény** (positive=sharp / negative=flat), nem
  ítélet.
- **Property 3 — Blast radius ÜRES.** `git diff 2c08dc5b..2c02f031 --
  lib/core/audio/dsp lib/core/audio/pitch lib/features/tuner` = üres (függetlenül
  futtatva). A core YIN/framer/tuner bájt-azonos. A feature-commit (`2c02f031`)
  saját footprintje pontosan a brief `allowed_paths`-a (15 fájl: `domain/pitch`,
  `engine/pitch`, `engine/metrics/pitch_metrics.dart`, additív katalógus/public/
  ARB, tesztek + 1 round-doc sor) — nincs implementer-drift.
- **Property 4 — Nincs IO / hálózat / secret / log / perzisztencia.** A 8 új
  prod-fájlban 0 valós találat (`dio|http|socket|print|log(|logger|SecureStorage|
  SharedPreferences|File(|writeAs|toJson|toMap|jsonEncode|secret|token|password` —
  a talált „dio" az „au**dio**" substring, a `log(` a MIDI/cent `math.log`
  képlet). A gépi őr `tool/ci/check_secrets.dart`: **0 találat / 2309 fájl**.
  Nincs unsafe ID-interpoláció: az `evidence` mező `'pitch-$index'` (int index,
  **nem** címke) — az E06-R11 `_defaultId` nyers-label-interpoláló hibája **itt
  nem ismétlődik**.
- **Property 5 — Flag-off tényleg inert.** `analysisPitchEnabled = false`
  alapérték a ctorban (`feature_flags.dart:34`) **és** a `forEnvironment`-ben
  (`:81`); nincs `bool.fromEnvironment`/dart-define override. A `lib/`-ben **0**
  fogyasztó (`PitchCapabilityGate|buildGatedPitchMetrics|MonophonicPitchSegment
  Builder|PitchFrameExtractor|MonophonicPitchTarget|analysisPitchEnabled` — csak
  az új pitch-fájlok és a `public.dart` export).
- **Codec változatlan → privacy-pozitív.** Az `analysis_document_codec` / data-
  réteg egyetlen új pitch-típust sem hivatkoz (grep) — a `PitchFrame`/
  `MonophonicPitchSegment`/`PitchMetricReport`/`CapabilityReport.details` **nem**
  szerializálódik/perzisztálódik. A gate `details` map-je (`:115-119`) csak
  numerikus derivált (`voicedRatio`/`medianConfidence`/`pitchSpreadCents`), nincs
  nyers audio/PII, és nincs log-sink.
- **Prompt-injection §5.1 — N/A.** Nincs AI-provider / tool-hívás / tudásbázis /
  prompt / provider-válasz. A bemenet numerikus/enum domain-objektum
  (`List<PitchFrame>`, `MonophonicPitchTarget`, `SignalQualityReport`), nem szöveg.
  A metric ID-k hardkódolt `const`-ok; az ARB-kulcsok statikus, placeholder
  nélküli címkék.
- **Az extractor NaN-védve.** A `PitchFrameExtractor` (`:60-64`) a nem-véges /
  tartományon kívüli YIN-frekvenciát unvoiced frame-mé (confidence 0) alakítja; a
  `detector.clarity` a **FROZEN** YIN-ben mindig `clamp(0,1)`
  (`yin_pitch_detector.dart:65`), így a `PitchFrame(confidence: clarity)` nem dob
  véges bemeneten.

---

## Amit végignéztem

Mind a 8 új prod-fájl teljes olvasása (`pitch_capability_gate.dart` 152,
`pitch_metrics.dart` 301, `monophonic_pitch_segment_builder.dart` 100,
`pitch_frame_extractor.dart` 79, a két domain value-típus, katalógus +20,
`public.dart` +6); a domain-függőségek validációja (`analysis_capability`,
`analysis_metric`, `signal_quality_report`); a frozen YIN `clarity`-korlát;
mindkét ARB-diff; a feature-commit scope (`git show --stat 2c02f031`); a flag
default + `fromEnvironment`; a codec-referencia grep; broad secret-grep + gépi
`check_secrets.dart` futtatás. Mérési bizonyíték: pure-Dart probe a **valódi
kódon** a klón `package_config`-ján keresztül
(`dart --packages=…/.dart_tool/package_config.json`) — a gate-seam, a
NaN-elutasítás, a `minimumVoicedRatio=0` crash, a `centsBetween` nem-pozitív
viselkedés és az O(S·N) skálázás mind reprodukálva; a disposable probe-fájlok
eltávolítva, az izolált klón tiszta.

**Merge-ajánlás:** nincs blokkoló lelet. A MINOR-1 (O(S·N)) **MUST-fix-before** a
modul untrusted / importált / hosszú-audio bemenetre kötése — a merge-et most nem
blokkolja.
