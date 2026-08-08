# E05-R22 — Dedikált biztonsági review (risk = "high")

Brief: `docs/rounds/e05-r22-observation-fusion-and-evidence.md`
Diff: `git diff origin/main...HEAD` (branch `codex/e05-r22-observation-fusion-and-evidence`, HEAD `7e9bd17`, base `960a346`)
Reviewer: `security-reviewer` ágens · Dátum: 2026-08-08
Verdikt: **APPROVED (PASS)** — 0 CRITICAL, 0 BLOCKER, 0 MAJOR, **1 MINOR, 3 NOTE**. A biztonsági dimenzióban nincs merge-blokkoló lelet.

> **Orchestrátor megjegyzés (Claude Sonnet 5, utólag fűzve):** ez a pass a
> `7e9bd17` (implementer első fordulója) állapotán futott, PÁRHUZAMOSAN a
> funkcionális review-val (`e05-r22-observation-fusion-and-evidence-review.md`).
> A funkcionális review önálló, adverzális próbával UGYANAZT a rést mérte ki,
> amit ez a jelentés **NOTE-3**-ként dokumentál (a memóriakorlát a `fuse()`
> fegyelmére támaszkodik) — a két független mérés egymást erősíti. A
> funkcionális review F1 (MAJOR) leletként vitte javító körre, és a `8b5a8f4`
> fix-commit **lezárta**: `add()` immár önmagában is korlátoz, fuse-hívástól
> függetlenül. **A NOTE-3 tehát a `8b5a8f4` óta megoldott**, a jelentés
> további része (MINOR-1, NOTE-1, NOTE-2) változatlanul nyitott/érvényes.

> Az AGENTS.md §15.1 szerint kötelező dedikált biztonsági pass (a brief
> `ai-router` blokkja `risk = "high"`). A kimenet READ-ONLY: jelentés, nem
> javítás. A merge-et a funkcionális review + az ADR 0052 zöld kapu együtt
> szabályozza; ez a jelentés csak a security/privacy/injection dimenziót fedi.

## Súlyossági séma

A `docs/execution/09-review-report.md` táblája (BLOCKER/MAJOR/MINOR/NOTE),
kiegészítve a CRITICAL szinttel (bizonyított titok-szivárgás / consent-
megkerülés / RCE / path traversal → merge tilos). Ebben a körben CRITICAL = 0.

## Módszer

- Izolált, read-only klón (`/tmp/security-review-e05-r22`), a megosztott
  working tree (`/home/ubuntu/music-theory`) érintése nélkül.
- **Reprodukció a TÉNYLEGES szállított kódon:** a `confidence_model.dart`
  importgráfja tiszta Dart (nulla `package:` import — csak `vision_frame_quality.dart`
  + `sync_quality.dart`, mindkettő import nélküli), a `geometry_confidence.dart`
  import nélküli. Egy scratch-próba relatív importtal futtatta a valódi
  osztályokat `dart --enable-asserts` (= `flutter test` viselkedés) és
  `dart --no-enable-asserts` (= release APK viselkedés) mellett. A [1a]–[3]
  hivatkozások e próba KIMENETEI, nem kézi elemzés.
- A többi állítás (IO/hálózat/perzisztencia hiánya, scope, provenance) kód-
  olvasás + `grep` bizonyítékkal, tételesen alább.

## Összegzés

CRITICAL: 0 · BLOCKER: 0 · MAJOR: 0 · MINOR: 1 · NOTE: 3

## Scope-audit

A brief `ai-router.allowed_paths` listája **pontosan** egyezik a diff-fel;
listán kívüli változás **nincs**:

| allowed_paths | diff-ben | státusz |
|---|---|---|
| `domain/evidence/{vision_observation,vision_evidence,evidence_provenance,confidence_model}.dart` | A (add) | ✅ |
| `application/observation_fusion.dart` | A | ✅ |
| `public.dart` (csak additív export) | M | ✅ |
| `test/features/vision/{application/observation_fusion_test,domain/confidence_model_test}.dart` | A | ✅ |
| `test/fixtures/vision/evidence` (`observed_wrist_deviation.json`) | A | ✅ |
| `docs/adr/0190-…md`, `docs/rounds/e05-r22-…md` | A/M | ✅ |

`pubspec.yaml`/`.lock`/`.yaml` **nem** változott (nincs új dependency).
A `public.dart` diff kizárólag öt új `export` sor — nincs re-export-elrejtés,
nincs törölt contract.

## Tiszta területek (bizonyítékkal)

1. **Nincs hálózat / HTTP / socket / fájl-I/O / isolate / FFI / storage a
   production kódban.**
   `grep -nE 'print\(|debugPrint|log\(|logger|dio|Dio|http|HttpClient|File\(|Directory\(|SecureStorage|secure_storage|SharedPreferences|KeyValueStore|Supabase|dart:io'`
   az öt új production fájlon + `public.dart` → **nulla találat**. A
   `dart:convert` egyetlen production-használata a determinisztikus FNV-1a ID
   `utf8.encode`-ja (`vision_evidence.dart:56`), nem szerializációs sink.

2. **Nincs nyers kamera-/landmark-/frame-adat perzisztálása vagy logolása.**
   A `VisionObservation` (a fúzió bemenete) kizárólag AGGREGÁLT numerikát hordoz:
   `timestampUs:int`, `metricObservation` (double value + double confidence),
   `frameQuality` (enum bucketek + skalár aggregátumok: meanLuminance, sharpness,
   cameraMotion, roiCoverageRatio, clipping ratiók — **nem** pixel, **nem**
   koordináta), `geometryConfidence` (2 double), `syncQuality` (enum),
   `modelVersion:String`. Sehol nincs landmark-koordináta vagy frame-buffer. A
   `toJson()` felszín (`vision_evidence.dart:39-46`, `evidence_provenance.dart:57-65`,
   `vision_observation.dart` nincs is toJson) is csak id/metric-kulcs/value/
   confidence/observationState + provenance verzió-stringeket ad ki — nyers mező
   nincs, tehát egy JÖVŐBELI perzisztencia is konstrukció szerint privacy-safe.
   Minden in-memory, és a memória korlátos (lásd 8. pont).

3. **Nincs secret / titok.** Az egyetlen új nem-kód fájl a
   `observed_wrist_deviation.json` fixture — csak numerikus evidence +
   **nyilvánvalóan fake** verzió-azonosítók (`model-test-v1`, `fusion-test-v1`,
   `quality-test-v1`, `quality`/`excellent` bucketek). Nincs token/kulcs/jelszó;
   szemantikailag valódi fixture. A fixture-t **csak a teszt** olvassa
   (`observation_fusion_test.dart:34-36`, golden-string összevetés), production
   nem tölti be.

4. **Nincs AI-provider / prompt / tool-calling felszín (§5.1 nem sérül).** A
   réteg sehol nem hív LLM-et, nem épít promptot, nincs allowlist/tool-dispatch.
   Külső tartalom **adatként** sem folyik be utasításként: nincs `fromJson`,
   nincs `jsonDecode`, nincs importált-fájl-parsing. A `modelVersion`/`metricId`
   stringek egy jövőbeli claim-rétegben adatként hordozódhatnak, de az ezen a
   körön kívüli felszín.

5. **Nincs unsafe deserialization.** `grep -nE 'fromJson|jsonDecode|Codec|decode\(|readAs|rootBundle|loadString'`
   az új production fájlokon → **nulla**. Csak `toJson` (kifelé szerializálás)
   létezik. A [[error-escapes-on-exception-catch]] típusú „Error szökik az
   `on Exception` catch-ből" hazárd itt nem alkalmazható: nincs decode-út.

6. **Nincs importált-tartalom / path traversal / zip-bomba felszín.** Nincs
   `File`, nincs archívum-kicsomagolás, nincs útvonal-összefűzés production
   oldalon. Az egyetlen `File(...)` a tesztben van, repo-relatív golden
   fixture-re.

7. **Nincs új platform permission, nincs új dependency** (pubspec érintetlen),
   így nincs új ellátási-lánc- vagy engedély-felszín.

8. **Korlátos memória (ADR 0183).** A `fuse()` a lezárt ablak előtti nyers
   observationöket eldobja (`observation_fusion.dart:99-104`), az evidence-cache
   `maximumRetainedEvidence`-re vágott (`:95-97`, default 128). A 10 perces
   teszt méri: `retainedObservationCount ≤ 11` (`observation_fusion_test.dart:132-133`).
   (A `fuse()` fegyelemtől való függés a NOTE-3.)

9. **§5 „gyenge confidence nem jelenhet meg biztos állításként" — a fő
   termékhatár — az alaptervben TELJESÜL.** A confidence-modell végig
   **min-alapú** (monoton nem-növekvő): `combine = min(model,quality,geometry,sync)`
   (`confidence_model.dart:42-47`), `qualityContribution = min(5 al-metrika)`
   (`:58-64`), `_lowestSyncQuality` a legrosszabb sync-et veszi
   (`observation_fusion.dart:262-269`), `usesTrackedGeometry` MINDEN observationtől
   `tracked`-et követel (`:199-204`, különben `manual`). A `confidence_model_test`
   pinneli, hogy egy gyenge komponenst nem átlagol el. A nem-véges „szemét"
   bemenetet, amely §5.5-öt sértene, a FORRÁSNÁL valódi runtime-őr fogja el
   (lásd MINOR-1 ellen-bizonyíték): `MetricObservation.observable` factory a
   nem-véges value/out-of-range confidence-t `notObservable`-re ejti
   (`metric_observation.dart:17-28`, valódi `if`, nem assert), a
   `GeometryConfidence` **dob** NaN-ra ([3] alább, release-load-bearing,
   `geometry_confidence.dart:78-91`). A quality/sync komponens enum→fix double.

10. **Determinisztikus, nem-titkos ID.** `deterministicId` FNV-1a az
    `metric.key:startUs:endUs` kulcsból (`vision_evidence.dart:49-62`) — nincs
    `DateTime.now()`, nincs random (ADR 0190 §6). Cache-kulcs, nem biztonsági
    token; kollízió-biztonsági követelmény nem releváns.

## Megállapítások

### MINOR-1 — `ConfidenceComponents` assert-only [0,1] validáció (exportált publikus API, release-ben strippelt)

- **Fájl:** `lib/features/vision/domain/evidence/confidence_model.dart:11-14`
  (a négy `assert(x >= 0 && x <= 1)`); a típus exportálva:
  `lib/features/vision/public.dart` (`export '…/confidence_model.dart'`).
- **Reprodukált failure scenario** (a valódi szállított osztályon, a próba
  kimenete):
  - `--enable-asserts` (= `flutter test`): `ConfidenceComponents(model: NaN, …)`
    → **AssertionError** ([1a]). A teszt-suite tehát strukturálisan nem tudja
    lefedni a release-viselkedést.
  - `--no-enable-asserts` (= release APK): ugyanaz **létrejön**, és
    `ConfidenceModel.combine(...)` **`NaN`-t ad vissza** ([1a]). Egy jövőbeli
    KÜLSŐ fogyasztó (a típus a vision publikus barrel-en van), amely
    `ConfidenceComponents`-et közvetlenül épít egy még nem őrzött numerikus
    forrásból, runtime-őr nélkül kap NaN (vagy a `model` slotban [0,1]-en kívüli)
    confidence-et. `NaN` összehasonlításai (`>=`, `>`) mind hamisak → a downstream
    „elég magabiztos?" kapuk **fail-open** irányba dőlnek (§5 „gyenge confidence
    nem jelenhet meg biztos állításként").
- **Őszinte szűkítés / ellen-bizonyíték (szintén reprodukálva):**
  - **A jelen kör `fuse()` útján NEM elérhető.** A négy komponens forrása
    build-módtól függetlenül a forrásnál őrzött: `model` ⇐
    `MetricObservation.observable` (valódi factory-őr, `metric_observation.dart:17-28`),
    `quality`/`sync` ⇐ enum→fix double, `geometry` ⇐ `GeometryConfidence` (valódi
    dob, [3]). Így a `fuse()` mindig véges [0,1] komponenst ad át.
  - A min-reduce a NaN-t a `quality`/`geometry`/`sync` slotban **eldobja**
    ([1b] → 0.9), a [0,1] fölötti magas értéket **min-nel levágja** ([1c] → 1.0);
    **csak** a `model` slotban (a reduce első eleme) lévő NaN propagál ([1a] → NaN).
- **Sértett elv:** a repó SAJÁT, kimondott „miért `throw` és nem `assert`"
  release-load-bearing szerződése (`geometry_confidence.dart:66-76`, R16 F2), és
  az UGYANEBBEN a diffben helyesen csináló testvérek: `VisionEvidence`
  (`vision_evidence.dart:19-24`), `EvidenceProvenance` (`evidence_provenance.dart:39-46`),
  `VisionObservation` (`vision_observation.dart:99-106`) — mind valódi
  `if (!cond) throw ArgumentError`. Ez az EGY value-típus tér el a saját
  diffjében bevált mintától.
- **Javasolt javítás iránya:** a négy `assert` cseréje valódi
  `if (!(x.isFinite && x >= 0 && x <= 1)) throw ArgumentError(...)`-ra a
  `ConfidenceComponents` konstruktorban — bájt-azonos a diff testvéreivel.
- **Ellenőrzés:** teszt, amely `ConfidenceComponents(model: double.nan, …)`-ra
  `throwsA(isA<ArgumentError>())`-t vár (Error, ami release-ben is elsül), **nem**
  `isA<AssertionError>()`-t.
- **Súlyosság-indoklás:** MINOR — reprodukálható + release-elérhető +
  teszt-lefedhetetlen, de **latens** (nincs kör-beli fogyasztó/untrusted feed,
  és a rossz kimenet szűk: kizárólag a `model` slot NaN-ja). Nem határsértés
  (a `fuse()` út őrzött), ezért nem BLOCKER/MAJOR. A táblázat szerint körön
  belül javítható (egy sor/mező, a diff nem nő érdemben), vagy follow-up.

### NOTE-1 — `FusionThresholds` assert-only bound; runtime-épített `inferredConfidencePenalty ≥ 1` megfordítja az inferred<observed invariánst

- **Fájl:** `lib/features/vision/application/observation_fusion.dart:20-23`
  (asserts), exportálva a `public.dart` `observation_fusion.dart` exportján át.
- **Scenario:** ADR 0190 §4 megköveteli, hogy az `inferred` confidence
  **szigorúan** kisebb legyen az azonos ablak szakadásmentes eseténél. A penalty
  alkalmazása `combine * (hasInterpolatedGap ? inferredConfidencePenalty : 1)`
  (`:174-176`). Az `assert(inferredConfidencePenalty > 0 && < 1)` őrzi — de
  release-ben strippelt. Reprodukált aritmetika [2]: penalty=1.5 → inferred 0.75
  > observed 0.5 (megfordulás); penalty=1.0 → egyenlő (nem szigorúan kisebb).
- **Miért csak NOTE (gyengébb, mint MINOR-1):** minden JELENLEGI konstrukciós
  hely `const FusionThresholds(...)` (teszt `:18`), és a `const` konstruktor az
  asserteket **fordítási időben** futtatja (nem strippelhető) — egy degenerált
  `const` tehát nem fordul le. A release-strippelt út csak egy JÖVŐBELI nem-const/
  runtime konstrukcióból érhető el (pl. beállításból származtatott thresholds),
  ami ma nem létezik. Továbbá `combine*penalty > 1` esetén a `VisionEvidence`
  valódi `confidence ≤ 1` dobása fail-closed elkapja (`vision_evidence.dart:19-24`);
  csak a `0 < combine·penalty ≤ 1` ablak (pl. 0.75) csúszik át néma
  megfordulásként.
- **Javítás iránya:** ugyanaz a valódi-`throw` kezelés, mint MINOR-1
  (version/count/penalty/retention mezőkre).

### NOTE-2 — `VisionEvidence.value` nincs véges-ellenőrizve (aszimmetria a `confidence`-hez képest)

- **Fájl:** `lib/features/vision/domain/evidence/vision_evidence.dart:19-29` a
  `confidence.isFinite`-et validálja (valódi dob), a `value`-t **nem**;
  `observation_fusion.dart:180-184` a `value`-t a `MetricObservation.value`-k
  számtani átlagaként számolja.
- **Scenario:** a `MetricObservation.observable` csak `isFinite`-et ellenőriz,
  magnitúdót nem; egy jövőbeli, patologikusan nagy-de-véges metrika-érték feed az
  átlagoláskor `±Infinity`-be túlcsordulhat, és egy `observationState=observed`,
  `value=Infinity` evidence átmegy a konstruktoron. Ma nincs production
  `jsonEncode` sink (a `toJson`-t csak a teszt hívja), tehát ez ma nem crash; de
  egy jövőbeli perzisztencia/telemetria kör `jsonEncode(evidence.toJson())`-ja
  **dobna** (a Dart JSON-encoder elutasítja a NaN/Infinity-t) — fail-open-to-crash
  a perzisztencia-úton. Olcsó konzisztencia-fix: `value == null || value.isFinite`
  validálása a `VisionEvidence` konstruktorban, a `confidence`-őr mellett.

### NOTE-3 — a korlátos memória és a provenance-hűség a per-metrika `fuse()` fegyelmére támaszkodik

- **(a)** `observation_fusion.dart:99-104` a nyers observationöket **csak** a
  `fuse()`-ban vágja, és csak a fúzált metrikára. `add()`/`addAll()` `fuse()`
  nélkül (vagy A metrika etetése, miközben csak B-t fúzálunk) az adott metrika
  listáját nem vágja → korlátlan in-memory növekedés (elemenként kicsi, de érinti
  az ADR 0183 „nincs korlátlan runtime-akkumuláció"-t). A reális használat minden
  etetett metrikát ablakonként fúzál (a 10 perces teszt e fegyelem alatt méri a
  `≤ 11`-et), ezért latens.
- **(b)** `observation_fusion.dart:199-211` a provenance `usesTrackedGeometry`-t
  az ablak MINDEN `observations`-én számolja, míg az egyetlen-geometria-forrás
  kapu (`:138`, `_hasSingleGeometrySource`) **csak** a `visible` részhalmazt
  nézi. Egy nem-visible `manual` observation az ablakban a rögzített provenance-t
  `manual`-ra billentheti akkor is, ha minden visible (fúzált) observation
  `tracked` volt. Konzervatív irányba téved (alul-állítja a trackinget, sosem
  túl), tehát ez provenance-hűségi megjegyzés, nem false-confidence — de a
  provenance-tengely következetesen a `visible`-t olvassa, mint a
  confidence-tengely.

## A `risk = "high"` címkéről

Ugyanaz a mintázat, mint E05-R15-nél: klasszikus adatbiztonsági/privacy
támadási felszín gyakorlatilag **nulla** (nincs hálózat/IO/perzisztencia/secret/
provider/import/dependency/permission) — tiszta in-memory numerikus fúzió. A
„high" akkor helyes, ha **numerikus korrektség mint biztonsági kérdés**-ként
olvassuk (§5 „gyenge confidence nem jelenhet meg biztos állításként"). Ellentétben
R15-tel — ahol az „egyetlen őr" vak volt, és reprodukálhatóan ~10⁷ nagyságrendű
koordinátát adott 0,88 confidence-szel (valódi BLOCKER) — R22 fúziója min-alapú,
és a nem-véges bemenetét a forrásnál valódi runtime-dobások fogják el, így
**egyetlen termékhatár sem sérül ténylegesen**. A maradék seedek az assert-only
value-típusok (MINOR-1, NOTE-1) — latensek és olcsón megkeményíthetők. A
kötelező dedikált review így itt megerősítést adott (nincs rejtett szivárgás),
nem BLOCKER-t.

## Merge-döntés

0 CRITICAL / 0 BLOCKER / 0 MAJOR → a biztonsági dimenzió **nem blokkolja** a
merge-et. A **MINOR-1** legjobban körön belül javítható (mezőnként egy sor,
azonos a diff testvéreivel — a diff nem nő érdemben), de a súlyossági tábla
szerint follow-up is lehet. A **NOTE-1..3** megkeményítési follow-upok, elsősorban
az első valódi fogyasztót/perzisztenciát bekötő jövőbeli kör számára. Az összesített
merge-döntést a funkcionális review + a változatlan ADR 0052 zöld kapu adja.
