# E13-R30 — Vision Setup, Coach és Result UI

- **Státusz:** PREPARED (előre megírva 2026-08-15, kód olvasva: `main @ 0f7afd9a`)
- **Típus:** Chapter 13 (UI/UX Design System), Kör 30
- **Kör-azonosító:** `E13-R30`
- **Branch:** `<motor>/e13-r30-vision-ui`
- **Előfeltétel:** `E13-R29` merge-elve (coach/tutor)
- **Brief szerzője:** Claude (Opus 5)
- **Előre kiosztott ADR:** [`0288`](../adr/0288-camera-frames-stay-on-device-and-one-cue.md)
  — **a Claude írja meg a kör indításakor; a `docs/adr/` a TILOS zónában van.**

> ⚠ **Pre-flight (indítás előtt KÖTELEZŐ):** mérd meg, hogy a vision modell-
> bináris és a képkocka-forrás TÉNYLEGESEN elérhető-e ezen a build-en (a
> projekt korábban mérte, hogy a vision rollout hiányzó modell-binárison
> BLOKKOLT). Ha nincs, a kör a **fake képkocka-folyamra** épül, és ezt a §10
> rögzíti. Eltérésnél §0.0 revízió.

```ai-router
schema_version = 1
risk = "high"
allowed_paths = [
  # §0.0/B2 — SZŰKÍTÉS: az eredeti `lib/features/vision/` KÖNYVTÁR-előtag
  # magába foglalta a `data/landmarks/**` képfeldolgozást és a teljes
  # `domain/**`-t, amit viszont a §3 tilos-listája KIMONDOTTAN kizár („a
  # vision modell vagy a képfeldolgozás módosítása"). Az előtag a
  # `presentation/`-re szűkül; a kör minden mért igénye ott van (a mérést
  # lásd §0.0/B2).
  "lib/features/vision/presentation/",
  "lib/l10n/base/app_en.arb",
  "lib/l10n/base/app_hu.arb",
  "lib/l10n/app_en.arb",
  "lib/l10n/app_hu.arb",
  "test/features/vision/presentation/guitar_calibration_screen_test.dart",
  "test/features/vision/presentation/vision_preview_overlay_test.dart",
  "test/features/vision/presentation/vision_setup_screen_test.dart",
  "test/features/vision/vision_permission_test.dart",
  "test/features/vision/vision_one_cue_test.dart",
  "test/features/vision/vision_cleanup_test.dart",
  "test/features/vision/vision_degraded_test.dart",
  "test/ui/goldens/",
  "test/ui/ui_inventory_test.dart",
  "docs/rounds/e13-r30-vision-ui.md",
]
gate_tests = [
  "test/features/vision/vision_permission_test.dart",
  "test/features/vision/vision_one_cue_test.dart",
  "test/features/vision/vision_cleanup_test.dart",
  "test/features/vision/vision_degraded_test.dart",
  # §0.0/B8 — FUTTATNI KELL, SZERKESZTENI TILOS (nincsenek az allowed_paths-on):
  # a `presentation/` fa negyedik tesztje a VALÓDI routeren jár
  # (`vision_session_routing_test.dart`), a másik három a privacy- és
  # offline-szerződést pinneli.
  "test/features/vision/presentation/",
  "test/features/vision/data/pose_privacy_audit_test.dart",
  "test/features/vision/data/vision_export_privacy_test.dart",
  "test/features/vision/vision_offline_regression_test.dart",
  "test/ui/goldens/e13_r30_screens_golden_test.dart",
  "test/ui/ui_inventory_test.dart",
  "test/core/architecture_dependency_test.dart",
  "test/tooling/dio_factory_guard_test.dart",
  "test/tooling/preferences_plugin_import_guard_test.dart",
  "test/tooling/route_literal_guard_test.dart",
]
native_gate = false
```

## 0.0 BRIEF-REVÍZIÓ — 2026-08-25, batch pre-flight (E13-R17…R35)

A brief 2026-08-15-én készült; ez a pre-flight `main @ 41fbd40` ellen mért.
**Visszakeresett előzmény:** [L478](../LESSONS.md) (a pre-flight csak szűkíthet;
a tágítás H3), [ADR 0307 §4](../adr/0307-parallel-round-execution.md) (a
`lib/l10n/app_*.arb` GENERÁLT aggregátum, a forrás a `base/` és a
`features/` szegmens), [L481](../LESSONS.md) (a lánc remote konténerből nem
indítható). A hibaosztályt a **teljes Ch13 sávon** mérte ki egy batch-vizsgálat:
az R17–R35 MIND a generált aggregátumot sorolta fel forrásként (`agg=2, frag=0`).

**Kockázat = high, indoklás:** a vision felület a KAMERA-engedélyt (camera/authorization) kéri és élő képet dolgoz fel.

### R1 — `lib/l10n/app_{en,hu}.arb` GENERÁLT aggregátum → a FORRÁS a szegmens

A kör fája ma **89** l10n-kulcsot használ, és mind feloldható: `app` = 89 kulcs.

A kör ezért **nem tudott volna egyetlen szöveget sem írni** a saját listáján
belül. Feloldás — H3 lista-tágítás, **user-engedéllyel (2026-08-25)**, a
lehető legszűkebb alakban:

- `vision` → nincs saját fragmentuma, a kulcsai a `base/app_*.arb` szegmensben élnek

Az aggregátum a listán MARAD, de **kizárólag generált kimenetként**
(`dart run tool/gen_l10n_segments.dart --write`); a merge-elt precedens
egységesen a forrást ÉS a regenerált aggregátumot is commitolja (E09-R26
`df0ad3dd`, E13-R12 `376b8a1d`, E13-R10 `b11ab2ed`). **Új fragmentum NEM
készül**, ezért a `test/l10n/arb_parity_test.dart` beégetett szegmens-listáját
sem kell bővíteni — a felvett források mind szerepelnek benne.

### R2 — a kör SAJÁT feature-fáján élő, ma zöld widget-tesztek (FELVÉVE)

Ezek közvetlenül a migrálandó képernyőkre állítanak, tehát a migráció után
pirosra váltanának, ami a §0 szerint `blocked` lenne:

  - `test/features/vision/presentation/guitar_calibration_screen_test.dart`
  - `test/features/vision/presentation/vision_preview_overlay_test.dart`
  - `test/features/vision/presentation/vision_setup_screen_test.dart`

**A jogosultság szűk:** a teszteket az ÚJ widgetekre kell ráállítani. A lefedett
viselkedést gyengíteni, cellát törölni vagy `skip`-elni **TILOS** — az a mérce
meggyengítése, amit a gate-guard emberhez eszkalál.

### R3 — keresztmetszeti tesztek (NEM kerültek listára — figyelmeztetés)

A kör fájára hivatkozó további widget-tesztek közös infrastruktúrán élnek
(`test/app/**`, `test/core/**`, más feature-ek fái) — 3 ilyen fájl van. Ezeket a kör
**NEM** szerkesztheti: ha egy elbukik, az `blocked` jelzés és célzott
brief-revízió, nem csendes átírás. A körbe húzásuk a scope-fegyelem feladása
lenne.

### R4 — a képernyő-leltár őre (H3 önjavító kör, ADR 0112, 2026-08-25)

A `test/ui/ui_inventory_test.dart` **repó-szintű** őr: a `tool/ui_inventory.dart`
a `lib/features/**` fa `_screen.dart` végű fájljait számolja, a teszt pedig
EGZAKT `hasLength(...)`-et állít rájuk. Ez a kör a(z) `lib/features/vision/` könyvtár-előtag
alá képernyőt hoz vagy hozhat, tehát a szám **elmozdul**, és az exact-SHA Full
Gate pirosra vált.

A `test/ui/goldens/` előtag ezt **nem** fedi (az a `test/ui/` fának csak az egyik
ága), a leltárteszt utólagos felvétele pedig tágítás, azaz **H3** — az
orchestrátor a pre-flightban nem oldhatja fel ([L478](../LESSONS.md)). Ezért
kerül a listára MOST, az önjavító körben.

**MÉRVE (E13-R16, 2026-08-25):** pontosan ez a hiány állította meg a sáv első
migrációs körét — [full-gate 32867296946](https://github.com/wolfcasaba/strumsight/actions/runs/32867296946)
6366 passed / 2 failed, `hasLength(79)` a tényleges 81 ellen. A `9acd14e5`
sáv-szintű batch pre-flight azért nem találta meg, mert a `tools/brief-lint.py`
`S9` szabálya csak LITERÁLIS `*_screen.dart` útvonalat nézett, KÖNYVTÁR-előtagot
nem — a predikátumot ugyanez az önjavító kör javította, regressziós teszttel
([L483](../LESSONS.md)).

**A jogosultság PONTOSAN a szám emelése** a kör tényleges képernyőszámára; a
leltárteszt minden más állítása érintetlen marad. Kerülőút (képernyő-átnevezés
vagy a `tool/ui_inventory.dart` szabályának lazítása) **TILOS** — az a mérce
meghamisítása.

### S12 — a fa-szintű őrök a kör LOKÁLIS kapujába (2026-08-25)

A kör lokális kapuja eddig KIZÁRÓLAG a saját céltesztjeit futtatta, ezért a
teljes `lib/` fát pásztázó őrök leletei szerkezetileg csak a ~17 perces
exact-SHA Full Gate-en jelentek meg — javító kör árán. MÉRT eset: **E13-R16/F8**
(`docs/reviews/e13-r16-review.md`), ahol mind a három új képernyő közvetlenül
importálta a `design_system/foundations/**`-ot a `public.dart` helyett — **11
sértés** —, és a review szó szerint rögzíti, miért nem fogta a célzott gate:
a `tools/round-gate.sh` `architecture` lépése a `tool/check_architecture.dart`-ot
futtatja, ami egy MÁSIK, tágabb szabálykészlet; a design-system-határ mércéje
egy külön `test/core/` teszt, amit csak a teljes suite futtat.

Ezért ez a kör mostantól a `gate_tests`-ben futtatja ezeket az őröket:

- `test/core/architecture_dependency_test.dart`
- `test/tooling/dio_factory_guard_test.dart`
- `test/tooling/preferences_plugin_import_guard_test.dart`
- `test/tooling/route_literal_guard_test.dart`

A kiválasztás MÉRT, nem vaktában: a globális őrök a `Directory('lib')` teljes
fát pásztázzák (bármelyik kör diffje elmozdíthatja őket), a szűkített őrök pedig
csak akkor kerülnek fel, ha a kör `allowed_paths`-a metszi a pásztázott
gyökeret.

**Ezek az őrök NEM kerülnek az `allowed_paths`-ra** — és ez szándékos: a kör
futtatja, de NEM szerkesztheti őket, tehát a lelet javítása kizárólag a kör
SAJÁT kódjában történhet. Cella törlése, `skip`-je vagy küszöb-lazítása így
gépileg kizárt, a mérce pedig tiszta erősítést kap.

## 0.0-B BRIEF-REVÍZIÓ — 2026-08-27, indítás előtti pre-flight (`main @ 9a92e335`)

A `brief-lint` (strict) **nem adott leletet**; az alábbi B-pontok a saját
mérésemből származnak (ADR 0087 §2: a kör saját, még nem merge-elt briefje az
én hatásköröm — kizárólag SZŰKÍTÉS és dokumentált feloldás).

**Visszakeresés (ADR 0312, kötelező — szűkítve ELŐSZÖR):**
`--corpus lessons,halts,adr` → [L486](../LESSONS.md#l486) (a golden a
RASZTERIZÁLÁST rögzíti; a `ColorScheme.fromSeed`-szín box↔CI diffet ad),
[ADR 0178](../adr/0178-vision-privacy-by-default.md) (vision privacy by
default — a frame nem megy hálózatra és **nem íródik tartós tárba production
kódban**; egyetlen kivétel az explicit consentelt Lab capture),
[L154](../LESSONS.md#l154) (a kamera-erőforrás acceptance-cellája a TELJES
capture-kontraktuson mérendő, nem a UI-enumon), [L449](../LESSONS.md#l449)
(az `indexedStack` shell életben tartja a bejárt brancheket, ezért az
erőforrás-tulajdonos képernyő nem szabadul fel). `--corpus lessons,halts` →
[L148](../LESSONS.md#l148), [L150](../LESSONS.md#l150),
[L217](../LESSONS.md#l217) (a teardown-callback a warm-up ablakban elveszhet,
míg a lease-t felszabadító külső `finally` feltétel nélkül lefut). Teljes
korpusz → SDD Ch13 UI-45/UI-46/UI-47 és a §21.5 vision-folyam.

### B1 — a brief SAJÁT kötelező pre-flightja: a vision modell-bináris NINCS a fán, a képkocka-forrás FAKE

A brief fejléce ezt kötelezővé tette. Mérve:

- `assets/ml/model_manifest.json` → `vision_models[]` mindkét eleme
  (`hand_landmarker`, `pose_landmarker`) `"status": "deferred"`, a `sha256`
  mindkettőn csupa nulla, az útvonaluk `assets/ml/*_deferred.tflite`.
- `ls assets/ml/*_deferred.tflite` → **No such file or directory**. Az
  `assets/ml/` tartalma: `chord_crnn.bin`, `strum_crnn*.bin`,
  `model_manifest.json` — vision-bináris NINCS.
- `FeatureFlags.visionEnabled` alapértéke **`false`**
  (`lib/app/config/feature_flags.dart:24` és `:86`), és a
  `cameraCaptureProvider` (`lib/core/camera/camera_providers.dart:24-30`)
  kikapcsolt flag mellett `null`-t ad, **plugin-példányosítás nélkül**.

**Következmény:** a kör a **fake képkocka-folyamra** épül
(`lib/core/camera/fake_camera_capture.dart` — determinisztikus, plugin nélküli
`CameraCapture`) és teszt-oldali állapot-felülírásra. Ez a §10-ben rögzítendő.
A kör NEM tölt le, nem generál és nem hivatkozik modell-binárist.

### B2 — SZŰKÍTÉS: `lib/features/vision/` → `lib/features/vision/presentation/`

Az eredeti előtag és a §3 tilos-listája ellentmondott egymásnak: az előtag alá
esik a `data/landmarks/**` (képfeldolgozás) és a teljes `domain/**`, amit a §3
kimondottan kizár. A szűkítés feloldja az ellentmondást, és mérve **elég**:

- **egy-jelzés (A3):** a prioritás-választás MÁR KÉSZ a domainben —
  `CueBudget.selectRealtime` (`domain/feedback/cue_budget.dart:11-31`)
  `VisionInsight?`-ot ad vissza (EGYET vagy semmit), és a
  `VisionSessionState.realtimeCue` (`application/vision_session_state.dart:96`)
  eleve **egyes számú, nullable** mező. A kör dolga tehát tisztán a
  megjelenítés.
- **erőforrás-tulajdonlás (a §1/2. mérési szabály):** `grep -rn "\.acquire(" lib/`
  → PONTOSAN három hívó, mind a presentationon KÍVÜL:
  `application/vision_session_controller.dart:157`,
  `application/vision_setup_controller.dart:163`,
  `lib/core/audio/mic_capture.dart:82`. A presentation ma sem szerez
  erőforrást, és **nem is fog**: az A7 bizonyítéka a kilépési utak
  controller-/guard-elengedése, nem új release-kód.
- a kör által olvasott típusok (`VisionSessionResult`, `VisionThermalDecision`,
  `VisionOverlayQuality`, `VisionSetupStep`) merge-eltek és **csak olvasásra**
  kellenek.

### B3 — A5/hő: a `VisionSessionStatus`-ból ma NEM állítható elő (§1/1. mérési szabály)

`grep -n "enum VisionSessionStatus" -A 17 application/vision_session_state.dart`
→ 15 érték, **egyik sem hő-jellegű**; a követés-vesztés viszont VAN:
`VisionSessionStatus.calibrationLost`. `grep -rn "thermal" application/vision_session_controller.dart`
→ **0 találat**; a `ThermalStateAdapter`
(`data/performance/thermal_state_adapter.dart:41`) `const`, tiszta
kiértékelő, és `grep -rn "ThermalStateAdapter" lib/` szerint **egyetlen
production hívója sincs** (csak tesztek).

**Feloldás (szűkítés, nem tágítás):** az **A5** hő-cellája a
**presentation-rétegen** mér: egy `presentation/providers/` alatti,
tesztből felülírható szolgáltató adja a hő-UI-állapotot a merge-elt
`VisionThermalDecision`-ből, a Stage pedig **külön, nevesített** állapotként
jeleníti meg — a `calibrationLost`-tól elkülönítve. Az `application/`, a
`data/` és a `domain/` viselkedése NEM módosul.

### B4 — A6/nem támogatott eszköz: a `audioOnly` lépésnek ma PONTOSAN EGY előállítója van

`grep -n "VisionSetupStep\." application/vision_setup_controller.dart` →
a `VisionSetupStep.audioOnly` egyetlen írási helye a `:154`, a `skip()`
metódusban (`:152-155`), ami **felhasználói akció**, nem képesség-jelzés. A
SDD UI-45 adatkontraktusában megnevezett `VisionCapability` típus a fán
**NEM létezik** (`grep -rn "VisionCapability" lib/ test/` → 0 találat).

**Feloldás:** az **A6** is presentation-oldalon mér — egy tesztből
felülírható képesség-szolgáltató (`presentation/providers/`) állítja a
beállítás-felületet a csak-hang alternatívára. A `skip()` mint második
előállító változatlan marad, az `application/` nem módosul.

### B5 — a SDD által kért DS-komponensek fele NEM létezik → mért helyettesítők

`lib/core/design_system/public.dart` ellen mérve — **HIÁNYZIK:**
`SsCalibrationFrame`, `SsInlineMessage`, `SsPrimaryButton`, `SsVisionOverlay`,
`SsTechniqueCue`, `SsConfidenceBadge`. **VAN:** `SsPermissionState`,
`SsSignalQualityIndicator`, `SsButton`, `SsStageScaffold`,
`SsSessionTransport`, `SsMetricCard`, `SsInsightCard`, `SsConfidenceLegend`,
`SsCoachActionCard`, `SsStatusBadge`, `SsProvenanceBadge`, `SsCard`,
`SsSection`, `SsEmptyState`, `SsFailureState`.

A hiányzókat a meglévőkkel VAGY feature-lokális widgettel kell kiváltani. A
`lib/core/design_system/**` **tilos zóna marad** — új DS-komponens NEM készül
(ugyanaz a szűkítés, mint az E13-R28/B5-ben). A design-system importja
kizárólag a `public.dart` barrelen át mehet: ezt a
`test/core/architecture_dependency_test.dart` méri (E13-R16/F8, 11 sértés —
lásd §0.0/S12).

### B6 — §7: a `flutter test --update-goldens` ütközik a merge-elt ADR 0426-tal

A brief §7-e ARM-en rögzítene goldent, amit az x86-os merge-kapu nulla
toleranciájú komparátora MINDIG pirosra vált
([ADR 0426](../adr/0426-golden-rasterization-on-the-gate-architecture.md) §2–§3,
[L486](../LESSONS.md#l486), [L493](../LESSONS.md#l493)). A merge-elt
E13-R23…R29 precedens egységesen a `tools/golden-x86.sh record|check`
alakot használja — a §7 erre vált (lásd lentebb).

### B7 — a kör ADR-t NEM ír

A kiosztott [`0288`](../adr/0288-camera-frames-stay-on-device-and-one-cue.md)
**már merge-elve van** (2026-08-15, `5b32bd8e`), a `docs/adr/` pedig tilos
zóna. Ez a sávon a **tizenharmadik** ADR nélküli kör egymás után (E13-R17…R30).
`tools/round-slots.py reserve-adr` ezért nem fut: nincs új döntés.

**Az ADR 0178 határa (H2-veszély):** a merge-elt ADR 0178 §1 szerint raw frame
**production kódban nem íródik tartós tárba**; az egyetlen kivétel az explicit
consentelt Lab capture. A §5.2 „mentés csak explicit felhasználói döntésre"
tehát **NEM** jogosít új production mentési útra — az A2 bizonyítéka az, hogy
a felület a megőrzés státuszát KIMONDJA és alapból NEM ment. Új
frame-perzisztencia bevezetése **H2**, azaz `stopped` jelzés.

### B8 — pinnelő tesztek a `gate_tests`-be (futtatni KELL, szerkeszteni TILOS)

A `presentation/` fa negyedik tesztje
(`vision_session_routing_test.dart`) a VALÓDI `routerProvider`-en pumpálja a
`VisionSessionScreen`-t, tehát a képernyő átalakítása elbuktathatja. Vele
együtt a privacy- és offline-szerződés pinjei is a `gate_tests`-be kerülnek
(`pose_privacy_audit_test.dart`, `vision_export_privacy_test.dart`,
`vision_offline_regression_test.dart`). **Egyik sincs az `allowed_paths`-on** —
ha egy elbukik, a kör a SAJÁT kódját javítja, nem a tesztet.

### B9 — `ui_inventory`: a mai szám **91**

`test/ui/ui_inventory_test.dart:15` ma `expect(first.screenPaths, hasLength(91))`
(az E13-R28 emelte 89→91). Ez a kör a Vision Result felületet
`lib/features/vision/presentation/screens/vision_result_screen.dart`-ként
hozza → **92**. A jogosultság PONTOSAN a szám valósághoz igazítása; ha a kör
végül nem hoz új `*_screen.dart`-ot, a `91` **érintetlen marad**. A leltár
minden más állítása, a `tool/ui_inventory.dart` szabálya és a képernyők neve
**nem módosulhat**.

### B10 — a Vision Result felület ROUTE NÉLKÜL épül (a router tilos zóna)

A SDD UI-47 `/coach/vision/result/:sessionId` route-ot ír elő, de a
`lib/app/routing/` **nincs az `allowed_paths`-on** (a szomszéd E13-R28-ban
user-jóváhagyással rajta volt; itt nincs, és a felvétele **H3** lenne —
[L478](../LESSONS.md#l478)). Mérve: `lib/app/routing/app_router.dart:555-578`
három vision-route-ot regisztrál (setup, guitar-geometry, session), result
route NINCS.

**Feloldás (szűkítés):** a Vision Result a `VisionSessionScreen`-ből,
feature-en belüli kompozícióval jelenik meg, amikor a munkamenet
`VisionSessionStatus.completed` állapotba ér. A route regisztrációja a kör
scope-ján KÍVÜL marad, és ezt a §10 rögzíti. Route-literál használata TILOS —
a `test/tooling/route_literal_guard_test.dart` a gate-ben méri.

### B11 — l10n: a FORRÁS a `base/` szegmens

`ls lib/l10n/features/` → `community`, `design_system`, `gamification`,
`onboarding`, `tuner` — **`vision` fragmentum NINCS**, tehát a vision-kulcsok
a `lib/l10n/base/app_{en,hu}.arb` szegmensben élnek (a §0.0/R1 állítása
igazolva). Az aggregátumot **kizárólag**
`dart run tool/gen_l10n_segments.dart --write` írja. Új fragmentum NEM készül,
a `test/l10n/arb_parity_test.dart:20` beégetett `('base/app', …)` sora
változatlan.

## 0. Kör-jelzés és STOP-protokoll

```bash
tools/codex-signal.sh progress "<egy sor>"
tools/codex-signal.sh done "<egy sor>"
tools/codex-signal.sh stopped "<egy sor>"
tools/codex-signal.sh blocked "<egy sor>"
```

Lezáró jelzés nélkül a kör bukott. Listán kívüli fájl → `stopped`.

## 1. Cél

Az UI-45–UI-47 kamera-, kalibrációs, élő-jelzés és eredmény-felülete
**adatvédelmi és hő-védelemmel** (SDD Ch13 Kör 30).

## 2. Jelenlegi állapot — mért tények

- Az R09 StageScaffoldja, az R10 engedély-állapotai és az R29 coach-akciói
  készen állnak.
- A kamera a mikrofonnál is érzékenyebb bemenet: a képkocka a felhasználó
  otthonáról készül.
- A vision képesség **eszközfüggő** — a nem támogatott készüléknek is kell út.

## 3. Scope

**Benne van:** a Vision beállítás engedély-primerrel, elhelyezési útmutatóval,
előnézettel és kalibrációs készenléttel · a Vision coach **egy-jelzéses** Stage
elrendezése gyenge fény / takarás / követés elvesztése / hő / csak-hang
állapotokkal · az eredmény követés-minőség, technikai mérőszám és korrekciós
elrendezése · **labor-only** hibakereső csontváz flag mögött, productionben
rejtve · kamera- és mikrofon-jelzés, route-takarítás és **képkocka-megőrzés**
státusz · fake képkocka-folyamon és hő-állapoton alapuló determinisztikus
tesztek.

**NINCS benne (tilos):** a vision modell vagy a képfeldolgozás módosítása
(AGENTS.md §9) · a képkockák alapértelmezett mentése · a hibakereső csontváz
production útvonalon · `docs/adr/**`, `tools/**`, `.github/**`.

## 4. Engedélyezett fájlok

| Útvonal | Indok |
|---|---|
| `lib/features/vision/presentation/` | a három felület — **SZŰKÍTVE** a §0.0/B2 mérése szerint (a `domain/`, `application/` és `data/` KIVÉVE: ott él a képfeldolgozás, és a kör minden igénye a presentationban van) |
| `lib/l10n/base/app_{en,hu}.arb` | **FORRÁS** — a vision-szövegek (a kör feature-ei még nem migráltak, a kulcsaik itt élnek) |
| `lib/l10n/app_{en,hu}.arb` | **CSAK GENERÁLT KIMENET** — kizárólag `dart run tool/gen_l10n_segments.dart --write`, kézzel írni TILOS |
| `test/features/…` (3 meglévő teszt) | ma zöld, a migrált képernyőkre állítandó — lásd §0.0 R2 |
| `test/features/vision/*_test.dart` (4) | a §6 cellái |
| `test/ui/ui_inventory_test.dart` | **repó-szintű képernyő-leltár őr** — a kör új `lib/features/**/*_screen.dart`-ot hozhat, ezért az egzakt `hasLength(...)` elmozdul; a jogosultság PONTOSAN a szám emelése, más állítás nem érinthető (§0.0/R4) |
| `docs/rounds/e13-r30-…md` | a §10 handoff |

**Tilos zóna:** `lib/features/**` a `vision/presentation/` KIVÉTELÉVEL —
tehát a `lib/features/vision/{domain,application,data}/**` IS tilos
(§0.0/B2) · a vision modell és a képfeldolgozás ·
`lib/core/design_system/**` (§0.0/B5) · `lib/app/routing/**` (§0.0/B10) ·
`docs/adr/**` · `docs/sdd/**` · `tools/**` · `.github/**`.

## 5. Kötött architekturális döntések (ADR 0288)

### 5.1 A kamera CSAK explicit felhasználói akció után indul

Nem a képernyő megnyitásakor, nem előnézet céljából. Az ADR 0276 elve a
legérzékenyebb bemenetre.

**NEM elfogadható gyengítés:** „az előnézet a beállítás megnyitásakor indul,
hogy gyorsabb legyen". Az a felhasználó otthonáról készít képet kérés nélkül.

### 5.2 A képkocka ALAPBÓL nem mentődik

A feldolgozás a készüléken, memóriában történik. Mentés csak explicit
felhasználói döntésre, és a státusz végig látható (az ADR 0285 §1 elve a
képre).

### 5.3 EGYSZERRE EGY prioritásos jelzés

Játék közben több egyidejű korrekciós jelzés használhatatlan. A felület mindig
a legfontosabbat mutatja — ez acceptance-cella (A3), nem stílus.

**NEM elfogadható gyengítés:** három jelzés egymás alatt, „mert mindegyik
hasznos". Játék közben egyik sem lesz feldolgozható.

### 5.4 Az alacsony megbízhatóság NEM kategorikus

Az ADR 0283 §1 alkalmazása a technikai mérőszámokra.

### 5.5 A nem támogatott eszköz CSAK-HANG alternatívát kap

Nem üres képernyőt és nem „a készüléked nem alkalmas" zsákutcát.

### 5.6 A hibakereső csontváz LABOR-ONLY

Flag mögött, production útvonalon nem elérhető (az R02 §5.4 mintája).

## 6. Acceptance criteria

| # | Kritérium | Bizonyíték |
|---|---|---|
| A1 | A kamera csak explicit akció után indul | `vision_permission_test.dart` |
| A2 | A képkocka alapból nem mentődik, és a státusz látható — **ADR 0178 §1 határa (§0.0/B7): új production frame-perzisztencia bevezetése H2 → `stopped`** | ugyanott |
| A3 | Egyszerre pontosan egy prioritásos jelzés látszik | `vision_one_cue_test.dart` |
| A4 | Alacsony megbízhatóságnál az eredmény nem kategorikus | `vision_degraded_test.dart` |
| A5 | Hő-korlát és követés-vesztés külön, kimondott állapot — a hő a §0.0/B3 szerinti **presentation-szolgáltatóból**, a követés-vesztés a merge-elt `VisionSessionStatus.calibrationLost`-ból; a két állapot szövege és jelzése KÜLÖNBÖZIK | ugyanott |
| A6 | Nem támogatott eszköz csak-hang alternatívát kap — a §0.0/B4 szerinti, tesztből felülírható **presentation-szintű képesség-szolgáltatóból** (az `application/` `skip()` útja változatlan) | `vision_permission_test.dart` |
| A7 | A kamera és a mikrofon minden kilépési úton felszabadul | `vision_cleanup_test.dart` |
| A8 | A hibakereső csontváz productionben nem elérhető | `vision_one_cue_test.dart` |
| A9 | A kör §3-ban megnevezett MINDEN képernyőről golden-felvétel készül és be van commitolva — 412×915 compact portrait ÉS `textScaleFactor: 2.0` | `e13_r30_screens_golden_test.dart` + a `test/ui/goldens/*.png` a diffben |

### 6.1 Mérce-mátrix — melyik hibás implementációt melyik cella fogja pirosra

| Hibás implementáció | Melyik cella vált PIROSRA |
|---|---|
| A kamera a képernyő megnyitásakor indul | **A1** |
| A képkockák naplózásra mentve | **A2** |
| Két jelzés egyszerre | **A3** |
| Kategorikus technikai pontszám gyenge követésnél | A4 |
| A hő-korlát néma lassulásként | A5 |
| A kamera nyitva marad háttérbe kerüléskor | **A7** |
| A csontváz production route-on | A8 |
| A képernyő elcsúszik, túlcsordul vagy nagy szövegméretnél olvashatatlan | **A9** |

**A jelzés-prioritás három kötelező cellája** (a küszöb: egyidejű jelzések száma):

| Cella | Bemenet | Elvárt |
|---|---|---|
| a küszöb alatt | nincs korrekciós lelet | **0** jelzés — a Stage tiszta |
| rajta (a küszöbön) | **1** lelet | 1 jelzés |
| a küszöb fölött | 3 egyidejű lelet | **1** jelzés — a legmagasabb prioritású |

**Valódi-sértés próba (KÖTELEZŐ, §10-ben dokumentálva):** jeleníts meg két
jelzést egyszerre → az **A3** cellának PIROSNAK kell lennie → állítsd vissza.

## 7. Kötelező ellenőrzések

```bash
tools/round-gate.sh test/features/vision/vision_permission_test.dart test/features/vision/vision_one_cue_test.dart test/features/vision/vision_cleanup_test.dart test/features/vision/vision_degraded_test.dart test/features/vision/presentation/ test/features/vision/data/pose_privacy_audit_test.dart test/features/vision/data/vision_export_privacy_test.dart test/features/vision/vision_offline_regression_test.dart test/ui/goldens/e13_r30_screens_golden_test.dart test/ui/ui_inventory_test.dart test/core/architecture_dependency_test.dart test/tooling/dio_factory_guard_test.dart test/tooling/preferences_plugin_import_guard_test.dart test/tooling/route_literal_guard_test.dart
```

**A golden-felvétel (A9) rögzítése — a mérce ÚJ, nem alku tárgya:** a képernyő
minden állapotát NEM kell felvenni, a §3 szerinti alap-nézet elég, de a két
keret (412×915 compact portrait és ugyanaz `textScaleFactor: 2.0` mellett)
KÖTELEZŐ. Minta és futó precedens: `test/features/live/chord_timeline_golden_test.dart`
(valódi kapu, nem `skip`-elt rögzítő). Előállítás:

```bash
tools/golden-x86.sh record test/ui/goldens/e13_r30_screens_golden_test.dart
tools/golden-x86.sh check  test/ui/goldens/e13_r30_screens_golden_test.dart
```

> **§0.0/B6 — a `flutter test --update-goldens` TILOS ezen a boxon.** Az ARM-en
> rögzített pixel az x86-os merge-kapu nulla toleranciájú komparátorán MINDIG
> piros ([ADR 0426](../adr/0426-golden-rasterization-on-the-gate-architecture.md)
> §2–§3, [L486](../LESSONS.md#l486), [L493](../LESSONS.md#l493)). A
> `tools/golden-x86.sh` a CI-vel azonos architektúrán vesz fel és ellenőriz —
> a mérce (nulla tolerancia, ugyanaz a komparátor és golden-készlet)
> változatlan. Kilépési kódok: `0` = egyezik, `10` = valódi golden-eltérés,
> `20` = környezeti hiba, `30` = hibás hívás.

A keletkezett PNG-ket **commitolni kell** — enélkül az A9 nem teljesült. A
márkabetűtípusok a teszt-hostban nem töltődnek be (fallback face); ez a
meglévő golden-teszt mért viselkedése, az elrendezést, méretezést és színeket
nem érinti. MIÉRT ez a kör dolga és nem az E13-R36-é: a záró vizuális
regressziós kör csak azt tudja megmondani, hogy valami MEGVÁLTOZOTT — azt,
hogy a képernyő eleve csúnya-e, a saját körében kell látni.

Külön processzek, csonkítatlan kimenet. **Tilos** `| tail`, `| head`,
`&&`-lánc vagy bármilyen szűrés (L09); a `flutter analyze` és `flutter test`
kézi láncolása OOM-ot ad (L05). A kötelező gate-et **TILOS háttérbe küldeni**
(`run_in_background`) — az egy-fordulós harness a forduló végén megöli (L254).

> **Review-megjegyzés:** ez a kör kamerát és adatmegőrzést érint, ezért a
> review-ban a `security-reviewer` ügynök futtatása kötelező.

## 8. Implementációs sorrend

1. A beállítás engedély-primerrel — kamera CSAK explicit akcióra.
2. A képkocka-megőrzés státusza, alapból mentés nélkül.
3. Az egy-jelzéses Stage + a három prioritás-cella.
4. Gyenge fény / takarás / követés-vesztés / hő / csak-hang állapotok.
5. Az eredmény-felület, nem kategorikus alacsony megbízhatósággal.
6. Kamera- és mikrofon-takarítás minden kilépési úton; labor-only csontváz.
7. A valódi-sértés próba, §10-be dokumentálva.
8. `tools/round-gate.sh` a §7 szerint.

## 9. Kockázatok

- **Az „azonnali" előnézet.** Gyorsabbnak hat, és kérés nélkül kapcsolja be a
  kamerát a felhasználó otthonában (A1).
- **A három egyidejű jelzés.** Mindegyik hasznosnak tűnik, és együtt
  használhatatlanok játék közben (A3).
- **A hibakeresés kedvéért mentett képkocka.** A legérzékenyebb adat, és a
  fejlesztői kényelem viszi ki (A2).

## 10. Implementation handoff — az implementer tölti ki

- [x] **Fake képkocka-folyam, MIÉRT.** A pre-flight (§0.0/B1) mérése szerint
      nincs vision modell-bináris a fán (`assets/ml/*_deferred.tflite`
      hiányzik, `model_manifest.json` mindkét vision-bejegyzése
      `status: deferred`), és `FeatureFlags.visionEnabled` alapból `false`.
      A kör ezért a meglévő `lib/core/camera/fake_camera_capture.dart`
      (`FakeCameraCapture`, plugin-mentes, determinisztikus) + a
      `cameraCaptureFactoryProvider`/`cameraSessionCoordinatorProvider`
      teszt-oldali felülírására épít minden új tesztben — nem tölt le, nem
      generál és nem hivatkozik modell-binárist. Az `application/`-ban a
      kamera-nyitás/zárás logika (permission → setup → calibrating →
      running → completed) már készen állt (E05/E24 körökből); ez a kör
      csak a presentation-réteget bővítette rá.
- [x] **Vision Result — route nélkül.** `lib/app/routing/` a kör tilos
      zónája (§0.0/B10), ezért a `VisionResultScreen` NEM kap regisztrált
      route-ot. A `VisionSessionScreen.build()` a `VisionSessionStatus
      .completed` + nem-null `state.result` esetén cseréli le a Stage
      testét a `VisionResultScreen`-re, in-feature kompozícióval
      (`lib/features/vision/presentation/screens/vision_session_screen.dart`
      `state.status == VisionSessionStatus.completed && result != null`
      ág). A "Korrekciós gyakorlat indítása" elsődleges művelet a meglévő
      `controller.begin()`-t hívja újra — nincs új navigációs célpont.
- [x] **Hő vs. követés-vesztés — külön állapot, külön szöveg.** Új,
      tesztből felülírható presentation-provider:
      `lib/features/vision/presentation/providers/vision_thermal_providers.dart`
      (`visionThermalDecisionProvider` → `ThermalStateAdapter.evaluate`,
      `visionThermalUiStateProvider` a 70-es küszöbbel). A Stage egy
      `_ThermalBanner` widgetet (`Key('vision-thermal-throttled')`,
      `l10n.visionSessionThermalThrottled`) jelenít meg, amikor a hő-terhelés
      a küszöb felett van — ez FÜGGETLEN a
      `VisionSessionStatus.calibrationLost` ághoz tartozó, már létező
      `l10n.visionSessionCalibrationLost` szövegtől. A négy kombináció
      (egyik sem / csak hő / csak követés-vesztés / mindkettő) le van
      fedve a `vision_degraded_test.dart` A5 csoportjában — mindkettő
      EGYSZERRE is külön-külön látszik (nem olvad egy üzenetbe).
- [x] **A3 valódi-sértés próba.** `vision_session_screen.dart`-ban
      ideiglenesen egy MÁSODIK, kódolt cue-szöveget (`Text(l10n
      .visionInsightFrettingFocus)`) rendereltem a valódi (egyetlen)
      `state.realtimeCue` szövege MELLÉ, majd lefuttattam
      `flutter test test/features/vision/vision_one_cue_test.dart --plain-name
      "three simultaneous"`. A cella PIROSRA váltott, a tényleges kimenet:
      ```
      Expected: no matching candidates
        Actual: _TextWidgetFinder:<Found 1 widget with text
          "Keep the fretting pattern consistent.": [...]>
         Which: means one was found but none were expected
      ```
      (a teszt a legmagasabb-prioritású `postureFocus` szövegen kívül minden
      más cue-szöveg hiányát várja — a beszúrt második `frettingFocus`
      szöveg pont ezt sértette). Ezután a beszúrt sort eltávolítottam, és a
      teljes `vision_one_cue_test.dart` újra zöld (5/5).
- [x] **`tools/golden-x86.sh` kimenete.**
      `record`: `00:00 +0 … 00:02 +6: All tests passed!` (6/6, Flutter
      3.44.2 linux/amd64, docker).
      `check`: `00:00 +0 … 00:02 +6: All tests passed!`, kilépési kód `0`.
      Commitolt PNG-k (`test/ui/goldens/goldens/`):
      `e13_r30_vision_setup_compact.png`,
      `e13_r30_vision_setup_compact_scale2.png`,
      `e13_r30_vision_coach_stage_compact.png`,
      `e13_r30_vision_coach_stage_compact_scale2.png`,
      `e13_r30_vision_result_compact.png`,
      `e13_r30_vision_result_compact_scale2.png`.
      A felvétel előtt két, textScale=2.0-nál jelentkező valódi elrendezési
      hibát javítottam a saját kódban (nem a DS-ben): a Vision Setup
      AppBar "Continue without camera" akciója 250px-szel túlcsordult a
      toolbaron (`ConstrainedBox` + ellipszis a javítás), és a
      `SsConfidenceLegend` (DS, tilos zóna) egy Sorban túlcsordult egy
      hosszú magyar címkénél — ezt egy feature-lokális `_ConfidenceLegend`
      váltotta ki (Column + `Expanded`, §0.0/B5 fallback-szabály).
- [x] **`ui_inventory` szám.** `91 → 92` — az új
      `lib/features/vision/presentation/screens/vision_result_screen.dart`
      egy `*_screen.dart` fájl (§0.0/B9). `test/ui/ui_inventory_test.dart`
      frissítve; a leltár minden más állítása változatlan.

**Mért, dokumentálásra érdemes tesztelési csapda (nem alkalmazáskód-hiba):**
a `testWidgets` fake-clock zónája alatt a `FakeCameraCapture.close()`
(broadcast `StreamController.close()`) awaitolása SOSEM tér vissza —
ugyanaz a hívás egy sima `test()`-ben azonnal lezárul. Minden teszt, amely
`stop()`/`leaveRoute()`/háttérbe-kerülést/`container.dispose()`-t vár be,
`tester.runAsync(...)`-ba csomagolva hívja ezt (lásd
`vision_permission_test.dart`, `vision_cleanup_test.dart`
`_runRealAndSettle` segédje) — enélkül a teszt a `flutter test`
saját időkorlátjáig (nem a `pumpAndSettle` rövid ciklusáig) lefagyott
lenne.

## 11. Review — a Claude tölti ki
