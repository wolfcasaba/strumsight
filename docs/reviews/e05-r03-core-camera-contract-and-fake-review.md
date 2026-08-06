# E05-R03 — Review

Brief: `docs/rounds/e05-r03-core-camera-contract-and-fake.md`
Diff: `git diff ed1bbe3..ddd2c96` (main pre-flight HEAD → implementer HEAD)
Reviewer: Claude Sonnet 5 (orchestrator) · Dátum: 2026-08-06
Implementer: Terra (Codex CLI, `gpt-5.6-terra`)
Verdikt: **APPROVED**

## Összegzés

BLOCKER: 0 · MAJOR: 0 · MINOR: 0 · NOTE: 1

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

### N1 — NOTE — `FeatureFlags.hashCode` időközben teljessé vált

- **Fájl:** `lib/app/config/feature_flags.dart:180-196`
- **Megfigyelés:** a brief §2 szerint a `hashCode` javítása „megengedett, nem
  hiba” — az implementer a bővítéssel egyszerre a korábban hiányzó
  `songTrainerV2Enabled`/`aiTutorEnabled`/`aiTutorCloudEnabled` mezőket is
  bevonta a hash-be. Az `==` már korábban is teljes volt, tehát ez csak a
  hash-kollízió esélyét csökkenti, viselkedést nem változtat. Nem blokkoló,
  csak dokumentálva.

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
| CI Full Gate (no APK) | dispatch `31085437507` | ⏳ folyamatban a jelentés írásakor, merge előtt exact-SHA-n ellenőrizve |
| Router CI | `31085432672` **success** (branch push) | ✅ |

## Merge-döntés

Nulla nyitott BLOCKER/MAJOR, minden helyi gate saját kézzel zöld izolált
klónban, scope-audit tiszta. Merge a Full Gate (no APK) futás sikeres
lezárása és az exact-SHA egyezés (branch HEAD ↔ CI `headSha`) után, az ADR
0052 zöld kapuja szerint.
