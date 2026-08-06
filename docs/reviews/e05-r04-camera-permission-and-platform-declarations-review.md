# E05-R04 — Review

Brief: `docs/rounds/e05-r04-camera-permission-and-platform-declarations.md`
Diff: `git diff origin/main...codex/e05-r04-camera-permission-and-platform-declarations`
Reviewer: Claude Sonnet 5 (orchestrátor) · Dátum: 2026-08-06
Verdikt: **APPROVED**

## Összegzés

BLOCKER: 0 · MAJOR: 0 · MINOR: 0 · NOTE: 1

Az implementer (Terra) pontosan a §0.0 pre-flight-revideált engedélyezett
fájllistán belül dolgozott, a mikrofon-permission precedenst hűen másolta
(fail-closed `unavailable`, plugin-típus izolálva, saját enum), és minden
acceptance criteria mérve teljesült. A gate-eket saját kézzel, izolált
`/tmp/review-e05-r04` klónban futtattam újra — mind zöld. Mutáció-kill próbát
saját kézzel megismételtem az `uses-feature` sorra. Dedikált security-reviewer
(a brief `risk = "high"`) **PASS**, 0 BLOCKER/MAJOR/MINOR, 1 NOTE (ugyanaz,
lásd lent).

## Pre-flight-korrekció megjegyzése (nem a review tárgya, de a scope-audit
miatt releváns)

A kör közben az implementer wrapper (`codex-round.sh`) a munka ELEJÉN
`git pull --rebase origin main`-t futtatott, mert eközben a párhuzamos
`ops/orchestrator-effort-max` PR (#165) mergelt a `main`-be. Ez a záró
`.codex-round-status`-ban `scope_audit=VIOLATION`-t jelzett két `tools/`
fájlra (`tools/round-pipeline.sh`,
`tools/tests/test_round_pipeline_fallback.py`) — ez FÉLREVEZETŐ jelzés: a
scope-audit a rebase ELŐTTI base commit-hoz (`85820f6`) hasonlított, miközben
a rebase után ezek a fájlok már a mergelt PR #165 tartalmát hordozzák
változatlanul. Igazolás: `git diff origin/main -- tools/round-pipeline.sh
tools/tests/test_round_pipeline_fallback.py` **üres** (a fájlok byte-azonosak
az aktuális `origin/main`-nel). A valódi diff `git diff origin/main...HEAD`
pontosan a brief 6+1 engedélyezett fájlját tartalmazza, semmi mást. Nem
BLOCKER, nem is scope-sértés — mérési artefaktum, a merge nem érinti a
`tools/`-t.

## Acceptance criteria

| # | Kritérium | Teljesült | Bizonyíték |
|---|---|---|---|
| 1 | Állapot-mátrix teszt (5 állapot × currentState/request, injektált fake, MissingPluginException külön cella) | ✅ | `test/core/camera/camera_permission_test.dart` — 6 `_stateCases` × 2 metódus + 3 külön hiba-cella (40, 53, 67. sor); saját futtatás: 32/32 zöld |
| 2 | `failure` térkép: denied→retryable, permanentlyDenied/restricted→nem, unavailable→nem | ✅ | `camera_permission_test.dart:93-114`, mérve zöld |
| 3 | Deklaráció-őr teszt (CAMERA + uses-feature required=false + NSCameraUsageDescription + tiltott szavak) | ✅ | `test/core/platform/platform_declarations_test.dart`, saját futtatás zöld |
| 4 | Valódi-sértés próba (`uses-feature` törlése → piros) | ✅ (reviewer pótolta, a §10 handoff üresen maradt) | saját futtatás: sor törlése → `platform_declarations_test.dart` PIROS (`does not contain 'android.hardware.camera'`) → visszaállítás → zöld |
| 5 | `test/core/platform` + mikrofon-tesztek változatlanul zöldek | ✅ | `microphone_permission_test.dart` 4/4 zöld ugyanabban a futásban |

## Scope-audit

`git diff --stat origin/main...HEAD` (a helyes, aktuális bázis):

```
android/app/src/main/AndroidManifest.xml           |   3 +
docs/rounds/e05-r04-...md                          |  41 ++++-
ios/Runner/Info.plist                              |   2 +
lib/core/camera/camera_permission.dart             | 142 +++++++++++++++++
lib/core/foundation/app_failure.dart               |   1 +
test/core/camera/camera_permission_test.dart       | 170 +++++++++++++++++++++
test/core/platform/platform_declarations_test.dart |  30 ++++
```

Pontosan a §0.0 „Frissített engedélyezett fájllista" — **listán kívüli
változás nincs**. A `.codex-round-status` `scope_audit=VIOLATION` jelzése
stale-base mérési hiba (lásd fent), nem valódi sértés.

## Megállapítások

### F1 — NOTE — `limited`/`provisional` plugin-állapot `granted`-re térképezve

- **Fájl:** `lib/core/camera/camera_permission.dart:129-131`
- **Megfigyelés:** a `CameraPermissionPluginState.limited`/`.provisional` →
  `CameraPermissionState.granted`. Bit-azonos a shippelt
  `microphone_permission.dart` mintájával, és a `permission_handler` camera
  API-ja gyakorlatilag sosem ad ilyen státuszt (foto-könyvtár- ill.
  notification-fogalom). Nem reprodukálható, nem blokkoló — jövőbeli
  follow-up, ha a plugin API bővül.
- **Státusz:** WONTFIX (nem indokolt ebben a körben — a precedens-követés a
  kötött döntés).

## Architektúra és termékhatárok

- **Domain-függetlenség / core→feature tilalom:** a fájl `lib/core/camera/`-ban
  marad, csak `foundation/app_failure.dart`-ot importál — nincs feature-import.
- **Plugin-típus izoláció:** `PermissionStatus` csak
  `PermissionHandlerCameraPlugin._map`-ben látszik, a gateway kontraktus saját
  `CameraPermissionState` enumot ad — igazolva.
- **`request()` sosem hívódik automatikusan:** grep az egész `lib/`-ben — 0
  hívó a `cameraPermissionGatewayProvider`-re vagy a gateway-re (a security
  review is megerősítette).
- **`RECORD_AUDIO` út érintetlen:** a mikrofon-tesztek ugyanabban a futásban
  zöldek, a manifest-diff additív.

## Gate-bizonyíték ellenőrzése

| Gate | Állított eredmény | Ellenőrizve |
|---|---|---|
| format | zöld | ✅ saját futtatás, `/tmp/review-e05-r04` |
| analyze | zöld | ✅ saját futtatás |
| test test/core/camera | zöld (32/32) | ✅ saját futtatás |
| test test/core/platform | zöld (5/5) | ✅ saját futtatás |
| architecture | zöld | ✅ saját futtatás |
| secrets | zöld | ✅ saját futtatás |
| l10n | zöld | ✅ saját futtatás |
| build-apk.yml (CI) | success, exact-SHA `fbf53d3` | ✅ [31089056201](https://github.com/wolfcasaba/strumsight/actions/runs/31089056201) |
| router-ci.yml (CI) | success, exact-SHA `fbf53d3` | ✅ [31089056972](https://github.com/wolfcasaba/strumsight/actions/runs/31089056972) |
| Security review (dedikált, `risk=high`) | PASS, 0 BLOCKER/MAJOR/MINOR, 1 NOTE (=F1) | ✅ |

## Merge-döntés

ADR 0052: minden gate zöld ÉS nincs nyitott BLOCKER/MAJOR → **merge**. A
feltétel teljesül, javító kör nem szükséges.
