# E14-R41 — Opt-in béta telemetria, privacy-kapu és a felismerési zászlókészlet

- **Kör-azonosító:** `E14-R41` (Chapter 14, Kör 41). A kör a PKG-D csomag
  1. hullámos szállítmánya, és magában hordozza az `E14-R23` / `E14-R24` /
  `E14-R33` / `E14-R40` körök **zászló-felét** is (a terv §4 PKG-D
  kötelezettsége: a teljes E14 zászlókészlet EGYBEN landol).
- **ADR:** [0542](../adr/0542-opt-in-beta-telemetry-consent-and-recognition-rollout-flags.md)
  (foglalva: `python3 tools/round-slots.py reserve-adr --round E14-R41`)
- **Dátum:** 2026-09-09
- **Implementer:** Claude (Opus 5), PKG-D
- **Terv:** [`epic-14-completion-plan.md`](epic-14-completion-plan.md) §2 R41,
  §4 PKG-D

## 1. Cél

Az opt-in béta telemetria **hiányzó consent-kapcsolóját**, a
**felismerési aggregátum-esemény sémáját**, a **redakciós őrt** és az
**egyetlen feltöltési kaput** szállítani — plusz a Ch14 sáv teljes
zászló-felületét, hogy a 2. hullám (PKG-E, PKG-F) fogyasztóknak legyen mit
fogyasztania.

Amit a kör **nem** csinál: nem épít transportot, nem küld semmit, és nem
írja alá a privacy reviewt.

## 2. Mért állapot (2026-09-09, `claude/laptop-apk-debug-prompt-kys4oa`)

| Tény | Bizonyíték |
|---|---|
| Nincs telemetria-consent kapcsoló a fán | `lib/core/telemetry/telemetry_sink.dart` saját doc-kommentje: *„no telemetry-consent switch exists on the tree today"* |
| Nincs transport | `telemetry_sink.dart` csak `NoopTelemetrySink` + `ConsentGatedTelemetrySink`; a `telemetry_redaction_test.dart` A7 cellája tiltja is |
| A három felismerési zászlónak nulla fogyasztója van | `grep -rn recognitionShadowModeEnabled lib/` → csak definíció |
| Egyetlen Ch14 §7 küszöb sem zöld | `baseline_manifest.json`: onset F1@50 ms 0,674 (kapu 0,82), chord accuracy 0,671 (kapu 0,80), `direction`/`noChord`/`latency`/`calibration` = `not-measured` |
| A zászló-audit `final bool` mezőket parse-ol | `tool/check_feature_flags.dart:42-45` |
| A `lib/core/telemetry/**` tiltja a csupasz `String` MEZŐT | `test/core/telemetry/telemetry_redaction_test.dart` A1 |
| Az esemény-katalógus kétirányban kényszerített | ugyanott, MINOR-5 |

## 3. Scope

**Benne:** consent-modell (3 állapotú enum + copy-verzió enum + forgó
pszeudonim), perzisztencia, feltöltési kapu, aggregátum-esemény +
allowlist-kódoló, Privacy Center kártya, field-session tag típusa, hat új
zászló-mező (négy bool + két enum), registry-bejegyzések, tesztek.

**Kívül:** transport; a `tool/release/*.py` béta-profil ellenőrzők (tilos
zóna); a shadow-plumbing (PKG-A seam + PKG-E implementáció, 2. hullám); a
privacy review aláírása; a `.arb` fájlok (l10n scratch protokoll).

## 4. Fájlok

**Új**
- `lib/app/config/recognition_rollout_stage.dart`
- `lib/core/telemetry/{telemetry_consent,recognition_telemetry_event,telemetry_upload_gate,field_session_tag}.dart`
- `lib/features/settings/data/telemetry_settings_storage.dart`
- `lib/features/settings/providers/telemetry_consent_provider.dart`
- `test/core/telemetry/{telemetry_consent,recognition_telemetry_event}_test.dart`
- `test/features/settings/telemetry_consent_center_test.dart`
- `test/privacy/beta_telemetry_egress_test.dart`
- `test/property/telemetry_redaction_property_test.dart`
- `docs/adr/0542-*.md`, `docs/release/ch14-recognition-rollout.md`

**Módosított**
- `lib/app/config/feature_flags.dart` (6 új mező + `==`/`hashCode`/`toString`)
- `lib/core/feature_flags/feature_flag_registry.dart` (4 új bejegyzés)
- `lib/core/telemetry/{telemetry_event,public}.dart`
- `lib/features/settings/{public.dart,screens/privacy_center_screen.dart}`
- `test/app/config/feature_flags_test.dart`
- `docs/analytics/event-catalog.md` (**tulajdonoson kívüli**, de az enum
  bővítésének gépileg kikényszerített kísérője — lásd §10)

**l10n:** 13 új kulcs a `scratchpad/l10n/PKG-D.json`-ban (`base` szegmens),
az orchestrátor olvasztja be.

## 5. Nem elfogadható gyengítések

- `nonProd` alapértelmezés bármelyik felismerési kapura → egy dev build mérés
  nélkül venne fel rollout-fokozatot.
- `bool` consent → nem tudja megkülönböztetni a „még nem kérdeztük"-et a
  „nemet mondott"-tól.
- Szabad `String` modellverzió az eseményen → visszanyitja az ADR 0484 D1
  lyukat.
- Denylist-redakció → minden még nem ismert kulcsot továbbenged.
- A Privacy Center kapcsolója olyan build-ben, ami úgysem küld → hazugság
  szebb formában.

## 6. Elfogadási feltételek

| # | Feltétel | Státusz |
|---|---|---|
| A1 | Az alapértelmezett consent `notAsked`, és a kapu elutasít | **PINNED-BY-TEST** — `telemetry_consent_test.dart`, `telemetry_consent_center_test.dart` |
| A2 | A kapu három feltétele ÉS-kapcsolatban van; egyik sem nyit önmagában | **PINNED-BY-TEST** — `telemetry_consent_test.dart` (5 cella) |
| A3 | Az opt-out azonnal hat, és nincs visszamenőleges flush | **PINNED-BY-TEST** — `telemetry_consent_test.dart` + `beta_telemetry_egress_test.dart` |
| A4 | A visszavonás TÖRLI a pszeudonim kulcsokat | **PINNED-BY-TEST** — `telemetry_consent_center_test.dart` |
| A5 | A kódolt kulcshalmaz sosem lépi túl a független allowlistet | **PINNED-BY-TEST** — `telemetry_redaction_property_test.dart` (randomizált, `PROPERTY_SEED`) |
| A6 | Öt tiltott tartalom-kategória sosem jelenik meg a kimenetben | **PINNED-BY-TEST** — ugyanott |
| A7 | A béta-út ma nulla hálózati kérést indít | **PINNED-BY-TEST** — `beta_telemetry_egress_test.dart` (`FakeNetworkGuard`); a cella azt bizonyítja, hogy MA nincs küldő |
| A8 | Minden felismerési kapu `off` MINDEN környezetben | **PINNED-BY-TEST** — `feature_flags_test.dart` |
| A9 | Az enum-mezők nincsenek a registryben, a bool-ok igen | **PINNED-BY-TEST** — `feature_flags_test.dart` |
| A10 | A UI nem állít küldést, amíg nincs transport | **PINNED-BY-TEST** — `telemetry_consent_center_test.dart` |
| A11 | A béta rollback egy kapcsoló | **PINNED-BY-TEST** (a kapu `betaTelemetryEnabled: false` mellett zár) + **dokumentum** (`ch14-recognition-rollout.md` §3) |
| A12 | Privacy review + threat model PASS | **NEEDS-MEASUREMENT** — emberi aláírás, nem ez a kör |
| A13 | A shadow-fogyasztó valóban nem futtat inferenciát flag OFF mellett | **NEEDS-MEASUREMENT** — nincs fogyasztó; PKG-E 2. hullám |

## 7. Verifikáció

Ezen a boxon **nincs Dart SDK** — `flutter analyze` / `flutter test` /
`gen-l10n` nem futtatható, a `tools/round-gate.sh` nem mérce itt. A mérce a
session végén futtatott `full-gate.yml` + `build-apk.yml`. A kör
jelentése a megírt cellákat sorolja, sikeres verifikációt **nem állít**
(Ch14 §9).

## 10. Handoff

- **PKG-E (2. hullám):** a shadow-futás feltétele a PÁR — `stage.runsInference`
  ÉS a boolean mesterkapcsoló (ADR 0542 D2). A `RecognitionTelemetryQualityBucket`
  leképezése az élő jelminőség-állapotgépről a fogyasztó dolga.
- **PKG-F (2. hullám):** a `newLiveStageEnabled` változatlan; fogyasztót ez a
  kör nem ad hozzá.
- **Orchestrátor:** (1) `scratchpad/l10n/PKG-D.json` beolvasztása a `base`
  szegmensbe; (2) a `docs/analytics/event-catalog.md` egysoros bővítése
  tulajdonoson kívüli szerkesztés — a `telemetry_redaction_test.dart` MINOR-5
  cellája kétirányban kényszeríti, tehát az enum-bővítés nélküle PIROS lenne;
  ha a review ezt visszautasítja, az enum-értéket kell visszavonni, nem a
  doksi sort.
- **Transport, ha valaha jön:** kizárólag a `TelemetryUploadGate` mögé
  konstruálva, és a `beta_telemetry_egress_test.dart` cellát ki kell
  terjeszteni magára a küldőre.
