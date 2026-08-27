# E13-R30 review — Vision Setup, Coach Stage és Result UI

- **Kör:** `E13-R30` (Chapter 13, Kör 30)
- **Ág:** `sonnet-impl/e13-r30-vision-ui`
- **Reviewer:** Claude (Opus 5), orchestrátor-session — READ-ONLY, production-kód
  a review alatt nem módosult (ADR 0055). A próbatesztek eldobható klónban
  (`/tmp/review-e13-r30`) futottak, és a fa minden próba után visszaállt.
- **Implementer:** `sonnet-impl` (Claude Sonnet 5, `--effort high`, `tools/mm-round.sh`)
- **Base → HEAD:** `9a92e335` → `5258957d` (23 fájl, 1736 beszúrás)
- **Kockázat:** `risk = "high"` → a `security-reviewer` ügynök futtatása KÖTELEZŐ
  volt, és lefutott (§4)

## 1. VÉGSŐ DÖNTÉS: **APPROVED**

0 BLOCKER · 0 MAJOR · 3 MINOR · 4 NOTE. Nyitott BLOCKER/MAJOR nincs, a merge
nincs blokkolva.

## 2. A mérce — a SAJÁT mérésem, nem az implementer bemondása

Az implementer futása a wrapper **3600 s abszolút időkorlátjába** ütközött
(`status=timeout`), **mielőtt** commitolni vagy a záró kaput lefuttatni tudta
volna: `dirty_files=23`, `head=ec5d7da0` (a pre-flight commit). A §10 handoff
ekkor már ki volt töltve és zöld golden-felvételt állított — a `timeout`
jelzés mellett ez **bizonyítatlan**, ezért a teljes mércét én futtattam le.

A jelzésfájl mért mezői:

```
status=timeout   dirty_files=23   gate_shape=ok
scope_audit=ok   scope_audit_base=ec5d7da0   scope_audit_changed=23
branch=sonnet-impl/e13-r30-vision-ui
```

A 23 fájl **mind az `allowed_paths`-on belül** volt, ezért nem veszett el
munka: az orchestrátor a mért, scope-auditált fát commitolta (`5258957d`), és
minden további mérés EZEN a HEAD-en történt.

### 2.1 A kör kapuja — újrafuttatva, TELJES egészében

`tools/round-gate.sh` a brief §7 szerinti mind a 14 teszt-útvonalon, külön
processzekben, csonkítatlanul (`GATE_EXIT:0`, `/tmp/gate-e13-r30.log`):

| Lépés | Eredmény |
|---|---|
| format · analyze | zöld · zöld |
| `test/features/vision/vision_permission_test.dart` | zöld |
| `test/features/vision/vision_one_cue_test.dart` | zöld |
| `test/features/vision/vision_cleanup_test.dart` | zöld |
| `test/features/vision/vision_degraded_test.dart` | zöld |
| `test/features/vision/presentation/` (4 pinnelt teszt) | zöld |
| `test/features/vision/data/pose_privacy_audit_test.dart` | zöld |
| `test/features/vision/data/vision_export_privacy_test.dart` | zöld |
| `test/features/vision/vision_offline_regression_test.dart` | zöld |
| `test/ui/goldens/e13_r30_screens_golden_test.dart` | zöld |
| `test/ui/ui_inventory_test.dart` | zöld |
| `test/core/architecture_dependency_test.dart` | zöld |
| `test/tooling/{dio_factory,preferences_plugin_import,route_literal}_guard_test.dart` | zöld |
| architecture · secrets · l10n | zöld · zöld · zöld |

**19/19 lépés zöld.** A négy pinnelő teszt (§0.0/B8) — köztük a valódi
`routerProvider`-en járó `vision_session_routing_test.dart` — **változatlanul**
zöld: az implementer a saját kódját igazította, nem a mércét.

### 2.2 Scope-audit — függetlenül újramérve

```
$ python3 tools/scope-audit.py --repo … --brief docs/rounds/e13-r30-vision-ui.md --base 9a92e335
Legacy scope audit OK (9a92e335fff9..5258957d1e63, 23 changed path(s), 0 generated/ignored)
```

A tilos zóna **érintetlen**: `lib/features/vision/{domain,application,data}/**`,
`lib/core/design_system/**`, `lib/app/routing/**`, `docs/adr/**`, `tools/**`,
`.github/**` — egyikben sincs változás (`git diff --stat` üres rájuk).

### 2.3 Golden a KAPU architektúráján (ADR 0426 §2–§3)

Hat PNG commitolva (`test/ui/goldens/goldens/e13_r30_*`), mindhárom felületről
két kerettel (412×915 compact portrait ÉS `textScaleFactor: 2.0`).
A felvétel `tools/golden-x86.sh record`-dal készült, **nem**
`flutter test --update-goldens`-szel — a §0.0/B6 pre-flight revízió épp ezt a
merge-elt ADR 0426 ütközést oldotta fel a kör ELEJÉN, javító kör nélkül.
A gate `[11]` lépése (`e13_r30_screens_golden_test.dart`) zöld.

Az implementer a felvétel ELŐTT két **valódi**, `textScale=2.0`-nál előjövő
elrendezési hibát javított a saját kódjában (a Setup AppBar-akció 250 px-es
túlcsordulása, és egy `Row`-ban túlcsorduló DS-legenda helyett feature-lokális
`_ConfidenceLegend`) — a golden itt tehát a rendeltetése szerint működött:
megmutatta, hogy a képernyő **eleve** csúnya, nem csak azt, hogy megváltozott.

## 3. Valódi-sértés próbák — ELDOBHATÓ, a fa visszaállt

A §6.1 mérce-mátrix négy súlyozott sorát mutáció-öléssel mértem
(`/tmp/probes-r30.log`). Mind a négy a **kijelölt** cellát váltotta pirosra:

| Próba (mátrix-sor) | Mutáció | Piros cella |
|---|---|---|
| „A kamera nyitva marad háttérbe kerüléskor" (**A7**) | `ref.watch(cameraLifecycleGuardProvider)` törölve a Stage-ből | `vision_cleanup_test.dart` → *„the app going to the background revokes and releases the camera"* |
| „A hő-korlát néma lassulásként" (**A5**) | a `_ThermalBanner` renderelése törölve | `vision_degraded_test.dart` → *„both at once render as two separate, distinctly worded signals"* ÉS *„thermal pressure while tracking shows only the thermal banner"* |
| „A csontváz production route-on" (**A8**) | a build-szintű `labModeAvailable` kapu kivéve | `vision_one_cue_test.dart` → *„production (labModeAvailable=false) hides the toggle and never renders the skeleton…"* |
| „Két jelzés egyszerre" (**A3**) | az implementer saját próbája: második, kódolt cue-szöveg a Stage-re | `vision_one_cue_test.dart` → *„three simultaneous findings…"*, `Expected: no matching candidates / Actual: Found 1 widget with text "Keep the fretting pattern consistent."` (§10-ben a teljes kimenet) |

A próbák után `git status --short` **üres** — a fa változatlan.

## 4. Biztonsági review (KÖTELEZŐ, `risk = "high"`)

A `security-reviewer` ügynök read-only futása: **PASS, 0 BLOCKER / 0 MAJOR /
0 MINOR, 5 NOTE.** Amit kimért:

- **A1 / ADR 0288 §1 — TARTVA.** A teljes hívási lánc végigmérve: sem a
  `VisionSetupScreen.build()`, sem a `VisionSessionScreen.build()` nem indít
  capture-t; mindkettő csak a `cameraLifecycleGuardProvider`-t mountolja, ami
  kizárólag *revoke*-ol, nem `acquire`-öl (`camera_providers.dart:44-52`). A
  három `.acquire(` hívó mind user-akció metódusban van, a kör scope-ján kívül.
- **A2 / ADR 0178 §1 — TARTVA.** A production diffre futtatott sink-grep
  (`File(`, `writeAs`, `SharedPreferences`, `SecureStorage`, `Dio`, `http`,
  `jsonEncode`, `log(`, `path_provider`) **nulla** valódi találat: nincs ÚJ
  perzisztencia-, fájlírás-, log- vagy hálózati út, amin képkocka kimehetne.
  Mentési affordancia nem létezik → a H2-határ nem sérült.
- **A7 — TARTVA.** A completed-result korai visszatérés a guard-`watch` UTÁN
  van, tehát a guard sosem esik ki; új lease/stream/subscription megtartás nincs.
- **A8 — TARTVA, defense-in-depth.** `labModeAvailable && labModeProvider`
  kettős kapu, és az `app_config.dart:161-166` production artefaktumon
  `ConfigurationException`-t dob, ha a build-szintű flag mégis igaz lenne.
- **Adatszivárgás — NINCS.** A Result csak aggregált értéket renderel
  (`duration.inMinutes`, `observedFrameCount` mint darabszám, `insight.code`
  → kategória, `confidence` → fok + szöveg); a `VisionInsight.evidenceIds`
  **nem** renderelődik, landmark-koordináta / frame-handle / pixeladat sehol.
- **Új engedély, plugin, hálózati kliens vagy tárolókulcs: NINCS** — a
  `pubspec.yaml` és minden platform-konfiguráció érintetlen.

## 5. Leletek

### MINOR-1 — a képesség-szolgáltató ma konstans `supported`, tehát az A6 production-úton nem érhető el

`lib/features/vision/presentation/providers/vision_capability_providers.dart:13-15`
a `visionDeviceCapabilityProvider`-t fixen `VisionDeviceCapability.supported`-re
állítja; valódi eszközdetektálás nincs bekötve. Az A6 két cellája ezért
kizárólag teszt-oldali `overrideWithValue`-val hajtható meg.

**Miért nem MAJOR:** ez a pre-flight §0.0/B4 **mért** és **kimondott**
szűkítése — a `VisionCapability` típus a fán nem létezik, az egyetlen
`audioOnly`-előállító a user `skip()`-je, a valódi jelforrás bekötése pedig az
`application/`/`data/` réteget kívánná, ami a kör tilos zónája. A provider
doc-commentje ezt szó szerint rögzíti, tehát nem rejtett adósság. A felület
maga kész és mért; csak a jel hiányzik hozzá.

**Követő kör:** a `VisionDeviceTier` / `device_tier_benchmark.dart` jelének
bekötése egy olyan körben, aminek az `application/` a scope-jában van.

### MINOR-2 — a hő-banner ugyanezen okból ma production-úton nem jelenhet meg

`vision_thermal_providers.dart:9-18`: a `visionThermalDecisionProvider`
alapértelmezett heurisztikus bemenete csupa nulla (`receivedFrames: 0` →
`load = 0`), tehát a `visionThermalThrottleLoad = 70` küszöb valódi
képkocka-forrás nélkül sosem lépődik át. Ugyanaz az osztály, mint a MINOR-1,
és a §0.0/B3 ugyanígy előre kimondta (`application/`-ban **0** thermal-hivatkozás).

### MINOR-3 — a megőrzés-státusz a FUTÓ Stage-en nem hangzik el

Az ADR 0288 §2 szerint a megőrzés státusza „**végig** látható". A kör a
belépésnél (`VisionSetupScreen._PrivacyNotice`) és a kilépésnél
(`vision_result_screen.dart:66`, `Key('vision-result-frame-retention')`)
kimondja, a futó session Stage-én viszont nem. A `security-reviewer` ezt
NOTE-2-ként mérte ki.

**Miért nem blokkoló:** perzisztencia-út nem létezik (lásd §4/A2), a
`visionEnabled` alapból hamis, és vision modell-bináris nincs a fán — tehát ma
nincs olyan futó session, ami képkockát dolgozna fel. A valódi capture
bekötésekor viszont a Stage-en is ki KELL mondani; ez a követő kör dolga.

## 6. NOTE-ok

- **NOTE-1 — a §0.0-B pre-flight megtérült.** A tizenegy B-pont mind ELŐRE
  fogott meg egy hibaosztályt: a B6 (ADR 0426 golden-parancs) és a B9
  (`ui_inventory` 91→92) külön-külön is garantált CI-piros és javító kör lett
  volna, a B2 szűkítés pedig a képfeldolgozást emelte ki a kör keze ügyéből.
  A kör **0 javító körrel** zárult.
- **NOTE-2 — a Result route nélkül él.** A `VisionResultScreen`-t a
  `VisionSessionScreen` komponálja be `VisionSessionStatus.completed` +
  nem-null `result` esetén; a SDD UI-47 `/coach/vision/result/:sessionId`
  route-ja **nincs** regisztrálva (§0.0/B10 — a `lib/app/routing/` a kör tilos
  zónája, felvétele H3 lett volna). Egy későbbi, routing-scope-ú kör dolga.
- **NOTE-3 — a `_ThermalBanner` és a `_ConfidenceLegend` feature-lokális
  widget, nem DS-komponens.** A §0.0/B5 mérése szerint a SDD által kért
  `SsCalibrationFrame`, `SsInlineMessage`, `SsPrimaryButton`, `SsVisionOverlay`,
  `SsTechniqueCue`, `SsConfidenceBadge` egyike sem létezik. A design-system
  határa tiszta maradt: az importok a `public.dart` barrelen mennek, és a
  `test/core/architecture_dependency_test.dart` zöld — épp az a lelet-osztály,
  ami az E13-R16/F8-ban 11 sértést adott.
- **NOTE-4 — mért teszt-csapda, dokumentálva.** A §10 rögzíti, hogy
  `testWidgets` fake-clock zónája alatt a `FakeCameraCapture.close()`
  (broadcast `StreamController.close()`) awaitolása sosem tér vissza, míg sima
  `test()`-ben azonnal lezárul; a takarítást váró cellák ezért
  `tester.runAsync(...)`-ba csomagolják. Ez LESSONS-értékű megfigyelés.

## 7. Acceptance-teljesítés

| # | Kritérium | Verdikt | Bizonyíték |
|---|---|---|---|
| A1 | A kamera csak explicit akció után indul | ✅ | `vision_permission_test.dart` A1 (mount/begin/calibrate → `startCalls == 0`, csak a Start tap után `== 1`) + §4 hívási lánc |
| A2 | A képkocka alapból nem mentődik, státusz látható | ✅ (MINOR-3) | ugyanott A2, két cella + §4 sink-grep |
| A3 | Egyszerre pontosan egy prioritásos jelzés | ✅ | `vision_one_cue_test.dart` A3, küszöb-hármas (0/1/3→1) + valódi-sértés próba |
| A4 | Alacsony megbízhatóságnál nem kategorikus | ✅ | `vision_degraded_test.dart` A4, mindkét irány |
| A5 | Hő és követés-vesztés külön állapot | ✅ (MINOR-2) | ugyanott A5, négy kombináció + mutáció-ölés |
| A6 | Nem támogatott eszköz csak-hang alternatíva | ✅ (MINOR-1) | `vision_permission_test.dart` A6, mindkét irány |
| A7 | Kamera és mikrofon minden kilépési úton felszabadul | ✅ | `vision_cleanup_test.dart` 5 kilépési út + mutáció-ölés |
| A8 | A csontváz productionben nem elérhető | ✅ | `vision_one_cue_test.dart` A8, mindkét irány + mutáció-ölés |
| A9 | Golden mindhárom felületről, két kerettel | ✅ | `e13_r30_screens_golden_test.dart` + 6 commitolt PNG |

## 8. Merge-kapu

- lokális `tools/round-gate.sh`: **19/19 zöld** (`GATE_EXIT:0`)
- `scope_audit`: **ok** (23 fájl, 0 sértés)
- Router CI a merge SHA-n (`5258957d`): **success**
  ([33046083607](https://github.com/wolfcasaba/strumsight/actions/runs/33046083607))
- Full Gate a merge SHA-n (`5258957d`): a §9 rögzíti

## 9. Full Gate — exact-SHA

A CI-tervező (`tools/round-ci-plan.py`) döntése — **nem** a sajátom:

```json
{"apk_required": false, "dispatch": ["full-gate.yml"], "skipped": ["build-apk.yml"],
 "router_ci_expected": true, "router_ci_paths_hit": ["docs/rounds/e13-r30-vision-ui.md"],
 "reasons": ["a diff nem érint natív/release-útvonalat — a teljes mérce-lánc … APK-építés nélkül fut"]}
```

`native_gate = false`, a diff 23 fájlja mind Dart/ARB/PNG/dokumentum — natív,
`android/`, `ios/`, `assets/`, `pubspec.*` érintés nincs.

- **Full Gate (no APK)**, run [33046092179](https://github.com/wolfcasaba/strumsight/actions/runs/33046092179),
  `headSha = 5258957d` (== a lokális HEAD), **conclusion: success**
- **Router CI**, run [33046083607](https://github.com/wolfcasaba/strumsight/actions/runs/33046083607),
  `headSha = 5258957d`, **conclusion: success**

Mindkét kapu a merge SHA-n zöld (ADR 0086 §2, ADR 0171 §3). A merge mehet.
