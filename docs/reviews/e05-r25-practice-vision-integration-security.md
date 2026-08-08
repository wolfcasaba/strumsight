# E05-R25 — Biztonsági / adatvédelmi / prompt-injection review

**Brief:** `docs/rounds/e05-r25-practice-vision-integration.md`
**ADR:** `docs/adr/0192-practice-vision-integration-contract.md`
**Diff vizsgálva:** `2a0d79a` (`codex/e05-r25-practice-vision-integration`) vs `origin/main` (`git diff origin/main...HEAD -- lib/ test/ lib/l10n/`)
**Reviewer:** Claude (security-reviewer agent, READ-ONLY, izolált `/tmp/security-review-e05-r25` klón)
**Dátum:** 2026-08-08
**Verdikt: PASS — 0 CRITICAL / 0 BLOCKER / 0 MAJOR.** Nincs merge-tiltó biztonsági lelet. 1 MINOR (latens, reprodukálható) + 4 NOTE, mind follow-up jellegű a következő (consumer-bekötő) körhöz.

## Összegzés

**CRITICAL: 0 · BLOCKER: 0 · MAJOR: 0 · MINOR: 1 · NOTE: 4**

A kör adatvédelmi felülete a MÉRT állapot szerint tiszta: az új adapter,
a bővített result-modell és a widget **kizárólag aggregát** vision-mezőket
érint (nincs nyers frame/landmark/koordináta/arcpont sehol), nincs új
hálózati hívás, log, analytics, perzisztencia, dependency, asset vagy
permission, és a capability-gate **fail-closed** módon mindig audio-only
útra esik. Az audio-pontozás bitre változatlan (mapper-parity teszttel
bizonyítva). AI-provider / tool-calling / prompt-injection felület ebben a
körben nincs.

Az **egyetlen MINOR** nem a kör kódjában lévő tényleges szivárgás, hanem egy
**enforcement-rés**: a brief §5.3 által „szűk kontraktusnak" (§3) nevezett
`vision/public.dart` barrel valójában **nyers landmark-/pose(arc)-/geometry-/
koordináta-típusokat és landmark-provider osztályokat is re-exportál**, és a
két gépi őr (architektúra + domain-purity), amire a brief/ADR a határ
kikényszerítését bízza, **nem korlátozza, mely szimbólumok jönnek át** a
barrelen. R25 nyitja meg az **első** `practice → vision/public.dart` élt (3
fájlban, köztük egy domain-modellben), ezért ez a latens rés most válik
practice-oldalról elérhetővé. MA nincs áthágás; a következő kör
(consumer-bekötés) előtt érdemes bezárni.

## Acceptance criteria (a §6 mátrix független ellenőrzése)

| # | Kritérium | Teljesült | Bizonyíték (saját mérés az izolált klónban) |
|---|---|---|---|
| 1 | **Audio-parity fixture (kulcsbizonyíték):** result + history-bejegyzés bitre azonos vision ON/OFF mellett | ✅ | `practice_session_result_vision_test.dart:21-43` — `_audioProjection` egyenlő, és `mapper.toHistoryEntry(visionEnabled) == mapper.toHistoryEntry(audioOnly)`; teszt ZÖLD |
| 2 | Vision-állapot mátrix `unavailable/degraded/good` determinisztikusan a `VisionQualitySummary.overall`-ból | ✅ | `practice_vision_adapter_test.dart:8-45` (`good→good`, `needsImprovement→degraded`, `notObservable`/null`→unavailable`); widget 3 állapota `practice_vision_dimension_test.dart:22-45` |
| 3 | Capability-gate a 3 pilotra: hiányzó capability → audio-only, **nem** letiltott | ✅ | `practice_vision_adapter_test.dart:47-70` — mindhárom pilot `isPracticeAvailable == true`, `mode == audioOnly`, `quality == unavailable` |
| 4 | Visszamenőleges API-kompat (a: 12 hívóhely `vision` nélkül fordul; b: `vision:null` egyenlőség-regresszió; c: mapper-érintetlenség) | ✅ | (a) analyze+test ZÖLD az összes hívóhelyen; (b) `practice_session_result_vision_test.dart:13-19` `==` és `hashCode` azonos; (c) 1. cella mapper-parity |
| 5 | Architektúra-őr ZÖLD, allowlist **nem** bővült | ✅ | gate `architecture: ZÖLD (12 allowlisted deviation)`; a diff nem érinti `tool/check_architecture.dart`-ot |
| 6 | Lokalizációs paritás ZÖLD | ✅ | gate `l10n: ZÖLD (en → hu, 1001 message)` |
| 7 | Valódi-sértés próba: audio score × vision-tényező → parity PIROS → visszaállítás | ✅ (implementer §10) + saját megerősítés | Az adapter/result/widget **sehol** nem olvassa/módosítja az audio score-t (grep 0 `scorePoints|score|metrics.overall` a 3 új fájlban); a parity-fixture létezik és ZÖLD |

## Scope-audit

Engedélyezett fájlokon kívüli változás: **nincs.** A diff pontosan a
`allowed_paths` 11 `lib/`/`test/`/`l10n` útvonalát érinti (+ 2 docs). **Nincs
`pubspec.yaml` érintés, nincs új dependency, nincs új asset** → ellátási lánc
felület nulla. A `check_secrets.dart` gépi őr ZÖLD (2030 fájl, 0 finding), és
a teszt-fixture-ök szemantikailag is nyilvánvalóan fake-ek (`'vision-session'`,
`'practice-session'`, `'test-v1'`, `'builtin.quarter-downstrokes.v1'`) — nincs
valódi kulcs/token/jelszó.

## Megállapítások

### MINOR-1 — A `vision/public.dart` szentesített csatorna nyers-média típusokat is re-exportál; a két gépi őr nem korlátozza a szimbólum-használatot

- **Fájl (mért bizonyíték):**
  - `lib/features/vision/public.dart:24-30` — nyers landmark export
    (`domain/landmarks/hand_landmarks.dart`, `pose_landmarks.dart`,
    `hand_track*.dart`, `landmark_smoothing.dart`, `posture_baseline.dart`);
    `:31-34` — `domain/geometry/*` (guitar_landmark_mapper, guitar_region,
    geometry_confidence, geometry_tracker); `:55-60` — landmark **provider**
    osztályok (`native_/recorded_hand_landmark_provider`, pose ugyanígy);
    `:61-62` — `NormalizedPoint` / `NormalizedRect` nyers koordináta-típusok.
  - `tool/check_architecture.dart:236-239` — `_isFeaturePublicBarrel` csak azt
    ellenőrzi, hogy a cél-útvonal `/public.dart`-ra végződik; **nincs
    szimbólum-szintű korlát**.
  - `test/features/practice/domain/domain_purity_test.dart:5-14` — a tiltott
    minták kizárólag fix framework/storage import-sorok (`package:flutter`,
    riverpod, dio, shared_preferences) + ambient IO; **cross-feature import
    vagy szimbólum-használat nincs ellenőrizve**.
  - R25 diff: `practice_vision_adapter.dart:1`,
    `practice_session_result.dart:2` (DOMAIN modell),
    `practice_vision_dimension.dart:4` — mindhárom importálja a barrelt.
- **Failure scenario (reprodukálható a JELENLEGI guard-okkal):** egy jövőbeli
  practice fájl (pl. R26, amikor a `practice_result_screen.dart`-ba köti az
  adaptert) beír egy `import 'package:strumsight/features/vision/public.dart';`
  sort — amit **R25 tett szentesített mintává a practice feature-ben** — és
  hivatkozik a `HandLandmarks` / `PoseLandmarks` / `NormalizedPoint` /
  `RecordedHandLandmarkProvider` szimbólumra. Ekkor nyers landmark-koordináta
  vagy arcpont kerülhet a practice rétegbe (log, perzisztencia, UI), és **sem a
  `check_architecture.dart`, sem a `domain_purity_test.dart` nem fogja el** —
  mindkettő zöld marad.
- **Sértett elv (potenciális, jövőbeli):** ADR 0178 (privacy-by-default — nyers
  média/landmark a rétegben nem terjedhet), AGENTS.md §5 termékhatár #1 (nyers
  kamera-frame/landmark alapból nem hagyhatja el az eszközt) és #3 (nyers
  kamera-frame nem kerülhet logba/perzisztenciába).
- **Miért nem BLOCKER:** R25 kódja **egyetlen** nyers típust sem használ. Mért
  bizonyíték: grep 0 `landmark|geometry|CameraImage|Frame|pixel` a 4 új/módosított
  fájlban; a `PracticeSessionResult.vision`-ből elérhető teljes objektum-gráf
  raw-media-mentes (lásd „Ami rendben volt" 2. sor). A határ MA nincs áthágva.
- **Miért nem MAJOR:** egyetlen in-round acceptance-kritérium sem bukik (az
  architektúra-őr ZÖLD, az allowlist nem bővült), és nincs jelenlegi untrusted
  fogyasztó — a lelet latens, de reprodukálható és release-elérhető. (Az ADR
  0192 Döntés 3 elismeri a guard-ok nem-tranzitív korlátját, de az elemzés
  csak az UI/Flutter-coupling ágra terjed ki, a **nyers-média export** ágra
  nem — ez a rés a security-releváns.)
- **Javasolt fix irány (a következő kör bekötése ELŐTT):** (a) szimbólum-szintű
  negatív guard — a `lib/features/practice/` fájlok nem hivatkozhatnak a nyers
  landmark/geometry/provider/`NormalizedPoint` szimbólumkészletre még
  `public.dart`-on át sem (a `privacy-allowlist` mintát pozitívan pinelve);
  VAGY (b) a `vision/public.dart` szétválasztása domain-safe (aggregát) vs.
  raw/UI barrelre, és a practice csak a domain-safe-et importálja. Az ADR 0192
  „Elutasított alternatívák" ezt egy jövőbeli önálló ADR-re bízza — a lelet
  azt sürgeti, hogy ez R26 ELŐTT szülessen meg.

### NOTE 1 — Prompt-injection / user-string felület: N/A ebben a körben

Nincs AI-provider hívás, tool-calling vagy tudásbázis-visszakeresés a diffben.
A pilot-azonosítók (`vision.pilot.*`) és `metricIds` (`picking.strokeAmplitude`
stb.) hardcode-olt gépi konstansok
(`vision_practice_contract.dart:69-108`), nem user-input. A widget egyetlen
string-argumentuma a `practiceResultDimensionSemantic("{label}: {value}")`
helperbe **kizárólag lokalizált statikus stringeket** ad
(`practice_vision_dimension.dart:26-31`). A LESSONS „user strings vs domain
transforms" minta **nem alkalmazható** — nincs user-authored érték, amely
machine-value transzformba folyna. Amikor R27 (Tutor) valós provider-t/toolt
köt be, ez a határ újra-ellenőrzendő.

### NOTE 2 — `hashCode` identitás-nemdeterminizmus (latens, jövőbeli, nem biztonsági)

`PracticeSessionResult.hashCode` (`:181`) az `Object.hash(..., vision)`-ön át a
`VisionSessionResult` **identitás**-hashCode-ját használja (a típusnak nincs
érték-egyenlősége — ADR 0192 Döntés 6). MA ártalmatlan: mind a 12 hívóhelyen
`vision == null` (a `null.hashCode` stabil), és a perzisztencia (mapper)
sosem olvassa a mezőt (bizonyítva a mapper-parity teszttel,
`practice_session_result_vision_test.dart:38-41`). **Nincs PII/session-id
naplózás** (grep 0 `print|log|toString` a 4 fájlban) — a task #4 kérdésére a
válasz: nem szivárog azonosító. Ha egy jövőbeli kör kitölti a `vision`-t ÉS a
`hashCode`-ot process-határon átívelő kulcsként/dedup-ként használja, az
identityHashCode nemdeterminizmusa okozhat hibát — ez tisztán code-quality
follow-up, nem biztonsági lelet.

### NOTE 3 — `overall == good` setup-minőségi jel, nem per-capability tracking-confidence (§5.5 határeset)

A `visionPracticeQualityFor` (`vision_practice_contract.dart:104-112`) a
`good`-ot a `VisionQualitySummary.overall`-ból származtatja, ami **setup-minőségi
roll-up** (framing/lighting/blur/stability/roiCoverage), nem per-capability-család
tracking-confidence. A widget ezt „Visual observation complete."-ként jeleníti
meg. A jelenlegi copy **szándékosan generikus** (nem állít konkrét technikát), a
per-technika insightok a `sessionSummary`-ben (confidence-gated) élnek, amit a
widget MA nem is renderel — ezért ez **MA nem hamis-confidence** (§5.5 tartva).
Forward-looking: az R26 consumer-bekötésnek ügyelnie kell, hogy a „teljes
megfigyelés" ne olvasódjon „a te testtartásod/pengetésed követve lett"-ként,
mert az `overall` nem per-capability jel.

### NOTE 4 — Practice-domain tranzitív Flutter/nyers-média fordítási függése (ADR 0192 által elismert korlát)

A `practice_session_result.dart:2` a `vision/public.dart`-ot importálja, ami
tranzitívan Flutter UI-t (`presentation/screens/*`, `overlays/*`) **és** a
MINOR-1-ben leírt nyers-média típusokat is behúzza a practice **domain**
fordítási gráfjába. A `domain_purity_test.dart` ezt nem fogja el (csak
közvetlen `package:flutter` import-sort tilt, tranzitívat nem). Az ADR 0192
Döntés 3 ezt tudatosan elfogadott korlátként dokumentálja; nem önálló
biztonsági lelet, de ugyanannak a „barrel túl széles" történetnek (MINOR-1) a
része, és a MINOR-1 fix (b) változata ezt is megszünteti.

## Ami rendben volt (tételes bizonyítékkal)

| Terület | Bizonyíték |
|---|---|
| **Nyers frame/landmark/arcpont a 4 új/módosított fájlban (§5.1/ADR 0178)** | grep 0 `landmark\|geometry\|CameraImage\|Frame\|pixel\|rawFrame` |
| **A `PracticeSessionResult.vision`-ből elérhető gráf raw-media-mentes** | `VisionSession`=id(String)+ts (fájl explicit: „neither a camera frame nor a platform capture object"); `VisionQualitySummary`=7 enum + int frameCount (a frame-lista nem retinálódik); `CalibrationLossState`=enum; `VisionInsight`=`evidenceIds`(String-lista)+confidence(0..1)+enum-ok; `observedFrameCount`=int — **nincs koordináta/frame/pixel** |
| **Cross-feature import fegyelem (§5.3)** | mind a 3 `practice → vision` import a `vision/public.dart`-ra mutat (`practice_vision_adapter.dart:1`, `practice_session_result.dart:2`, `practice_vision_dimension.dart:4`); nincs belső `features/vision/` import |
| **Capability-gate fail-closed (§5.4/§5.5)** | `practice_vision_adapter.dart:24-39`: hiányzó capability → `unavailable`+`audioOnly`; null/`notObservable` session → `unavailable`+`audioOnly`; csak `good` → `audioAndVision`; `isPracticeAvailable` mindig `true`; **nincs vision-only út** (a `PracticeVisionMode` mindkét ága tartalmaz audiót) |
| **Audio-pontozás bitre változatlan (§5.1)** | az adapter/result/widget sehol nem olvassa/módosítja az audio score-t; mapper-parity teszt byte-azonos ON/OFF |
| **Nincs log/analytics/hálózat/perzisztencia/permission a diffben (§5 #2,#3)** | grep 0 `print\|debugPrint\|log\|analytics\|Dio\|http\|Socket\|File(\|SharedPreferences\|SecureStore` a 4 fájlban; nincs `toString` override; nincs pubspec/asset |
| **Nincs hardcode user-facing string a domainben** | contract = gépi ID-k/enum-ok; adapter = 0 string; widget = kizárólag `l10n.*` lookup; EN/HU ARB kulcsok additívak és paritásban |
| **Titok/fixture szemantika** | `check_secrets` ZÖLD (2030 fájl, 0 finding); a fixture-ök fake identifierek, nincs valódi kulcs |

## Gépi kapu (saját reprodukció az izolált klónban)

`flutter pub get` után `tools/round-gate.sh test/features/practice
test/features/vision` — **kilépési kód 0, minden lépés ZÖLD** (külön
processzek): `format`, `analyze` (No issues), `test test/features/practice`,
`test test/features/vision`, `architecture` (12 allowlisted deviation,
változatlan), `secrets` (2030 fájl, 0 finding), `l10n` (en→hu, 1001 message).
Az első futás pirosa (`GATE_EXIT=10`) tisztán a friss klón feloldatlan
függőségei miatt volt (`flutter_lints/flutter.yaml` package-URI hiba `pub get`
előtt) — nem kód-hiba.

## Konklúzió

**PASS — merge biztonsági szempontból nem tiltott.** 0 CRITICAL/BLOCKER/MAJOR.
A MINOR-1 (barrel-szélesség / szimbólum-szinten nem kikényszerített határ)
latens és MA nincs áthágva, de a MÉRT enforcement-rés valós — ajánlott a fixe
az R26 consumer-bekötés ELŐTT, hogy a `practice → vision` él ne válhasson
nyers-média szivárgás szentesített útjává. A 4 NOTE follow-up jellegű.
