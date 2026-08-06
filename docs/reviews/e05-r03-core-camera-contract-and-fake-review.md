# E05-R03 — Review

Brief: `docs/rounds/e05-r03-core-camera-contract-and-fake.md`
Diff: `git diff ed1bbe3..ddd2c96` (main pre-flight HEAD → implementer HEAD)
Reviewer: Claude Sonnet 5 (orchestrator) · Dátum: 2026-08-06
Implementer: Terra (Codex CLI, `gpt-5.6-terra`)
Verdikt: **CHANGES REQUESTED** (1. kör, javító kör szükséges)

## Összegzés

BLOCKER: 0 · MAJOR: 1 · MINOR: 0 · NOTE: 1

**Frissítés (CI, exact-SHA `b0f678d`, run
[31085620321](https://github.com/wolfcasaba/strumsight/actions/runs/31085620321)):**
mindkét job (`Coverage`, `full-gate`) pirosra váltott — 1 regresszió a teljes
suite-ban, amit a lokálisan futtatott célzott gate (`test/core/camera
test/app/feature_flags_test.dart`) nem fedett le, mert a sérült teszt más
fájlban van. Lásd F1.

## Acceptance criteria

| # | Kritérium | Teljesült | Bizonyíték |
|---|---|---|---|
| 1 | Lifecycle-mátrix (start→frame→close; close→close; start-cancel; close-utáni frame; interruption+close) — mind az öt cella | ✅ | `test/core/camera/fake_camera_capture_test.dart` `group('FakeCameraCapture lifecycle matrix')`, 5 külön teszt, mind zöld izolált klónban |
| 2 | Hiba-mátrix (busy/unavailable/initialization/frame/interrupted) → külön `FailureCode`, nincs `granted`-szerű default | ✅ | `test/core/camera/fake_camera_capture_test.dart` `group('FakeCameraCapture failure matrix')` + `camera_contract_test.dart` „maps every controlled failure”; `CameraFailureMapper._codeFor` switch kimerítő |
| 3 | Ownership: callback után használt buffer hibát ad, nem csendben nullát | ✅ | `camera_frame.dart` `assertValid()`/`byteAt`/`copyBytes` → `StateError`; **mutáció-próba**: `assertValid()` törzsét kiürítve a `camera_contract_test.dart` „a frame is invalidated…” teszt PIROSRA vált (`Expected: throws StateError, Actual: returned null`), majd visszaállítva — a guard valódi |
| 4 | Flag-mátrix: mind a 11 vision flag `false` production/lab/development-ben; `usesNetwork` változatlan | ✅ | `test/app/feature_flags_test.dart` `group('Computer Vision feature flags')`; `usesNetwork` getter diffje: `accountEnabled \|\| diagnosticsEnabled` — nincs vision-hivatkozás |
| 5 | `test/core/architecture_dependency_test.dart` zöld, allowlist nem bővül | ✅ | `git diff ed1bbe3..HEAD -- test/core/architecture_dependency_test.dart tool/check_architecture.dart` üres; gate „12 allowlisted deviation(s)” — a pre-round szám, nem nőtt |

## Scope-audit

`git diff --stat ed1bbe3..ddd2c96` — 12 fájl, mind a brief §4 `allowed_paths`
listáján (6 új `lib/core/camera/*`, additív `app_failure.dart` +
`feature_flags.dart`, 3 teszt + a brief maga). Engedélyezett fájlokon kívüli
változás: **nincs**. `.codex-round-status`: `scope_audit=ok`,
`scope_audit_changed=12`.

## Megállapítások

### F1 — MAJOR — `FeatureFlags.hashCode` bővítése eltör egy scope-on kívüli, meglévő tesztet

- **Fájl:** `lib/app/config/feature_flags.dart:180-196` (a hiba forrása) →
  `test/app/app_config_test.dart:262-263` (a piros teszt, **nincs** a brief
  `allowed_paths` listáján)
- **Probléma:** a brief §2 csak *megengedte* a hiányos `hashCode` kiegészítését
  ("javítása megengedett, elhagyása nem hiba"), nem írta elő. Az implementer a
  vision-mezőkkel EGYÜTT a korábban is hiányzó
  `songTrainerV2Enabled`/`aiTutorEnabled`/`aiTutorCloudEnabled` mezőket is
  bevonta az `Object.hash(...)` hívásba. A `test/app/app_config_test.dart`
  egy MEGLÉVŐ, kör előtti teszt egy **kőbe vésett 6-argumentumos**
  `Object.hash(false, false, false, false, false, true)` értékkel hasonlítja
  össze `detailedHistory.hashCode`-ot — az argumentumszám (6→20)
  megváltozása a Dart `Object.hash` keverési függvénye miatt MÁS értéket ad
  még változatlan `false` mezőknél is.
- **Hatás:** a teljes CI suite pirosra vált mindkét jobban (`Coverage`,
  `full-gate`) — 2997 passed, **1 failed**, exact-SHA `b0f678d`, run
  [31085620321](https://github.com/wolfcasaba/strumsight/actions/runs/31085620321).
  A célzott gate (`test/core/camera test/app/feature_flags_test.dart`) ezt
  nem látja, mert a sérült teszt egy másik fájlban van — ez pontosan a brief
  §9 kockázata (enum/mező-bővítés máshol tör), csak a `hashCode`-on, nem a
  `FailureCode`-on keresztül.
- **Kötelező javítás:** a `hashCode` gettert állítsa vissza az EREDETI 6
  mezőre (`accountEnabled, diagnosticsEnabled, labModeAvailable,
  practiceEngineV2Enabled, migratedLearnEnabled,
  practiceDetailedHistoryEnabled`) — a `lib/app/config/feature_flags.dart` a
  brief engedélyezett listáján van, a `test/app/app_config_test.dart` NEM,
  tehát a scope-on belüli oldalt kell a scope-on kívüli, változatlanul hagyandó
  teszthez igazítani, nem fordítva. A `==` és `toString()` teljessége
  (beleértve a 11 vision flaget) marad — azokat nem érinti ez a teszt.
- **Ellenőrzés:** `flutter test test/app/app_config_test.dart` zöld, majd
  `tools/round-gate.sh test/core/camera test/app/feature_flags_test.dart` és a
  teljes CI (`full-gate.yml`) újrafuttatása az új exact-SHA-n.
- **Státusz:** OPEN

(N1 törölve — a korábban itt jelzett `hashCode`-teljesség maga bizonyult a
F1 gyökérokának, lásd fent.)

## Gate-bizonyíték ellenőrzése

Saját kézzel, **izolált** `/tmp/review-e05-r03` klónban (branch
`codex/e05-r03-core-camera-contract-and-fake`, HEAD `ddd2c96`), NEM a közös
munkafán:

| Gate | Állított eredmény | Ellenőrizve |
|---|---|---|
| format | zöld | ✅ (saját futás) |
| analyze | zöld | ✅ (saját futás) |
| test `test/core/camera` | 15/15 zöld | ✅ (saját futás, + mutáció-próba a piros oldalon is lefutott) |
| test `test/app/feature_flags_test.dart` | 5/5 zöld | ✅ (saját futás) |
| architecture | zöld, 12 allowlisted deviation (változatlan) | ✅ (saját futás) |
| secrets | zöld | ✅ (saját futás) |
| l10n | zöld | ✅ (saját futás) |
| CI Full Gate (no APK), HEAD `b0f678d` | dispatch [31085620321](https://github.com/wolfcasaba/strumsight/actions/runs/31085620321) | ❌ **PIROS** — `Coverage` és `full-gate` job is: 2997 passed, **1 failed** (F1) |
| Router CI | `31085432672` **success** (branch push) | ✅ |

## Merge-döntés

**Merge TILOS** — 1 nyitott MAJOR (F1) és a CI a merge-jelölt exact-SHA-n
(`b0f678d`) piros. Javító kör szükséges (1. javító kör, Terra), utána a
review-t frissítem és a CI-t az új exact-SHA-n újra-dispatch-elem.
