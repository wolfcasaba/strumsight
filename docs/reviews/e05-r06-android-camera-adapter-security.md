# E05-R06 — Dedikált biztonsági review

Brief: `docs/rounds/e05-r06-android-camera-adapter.md`
Diff: `git diff main...codex/e05-r06-android-camera-adapter` (exact head `f2bd8bd`)
Reviewer: Claude (dedikált biztonsági review — `AGENTS.md` §15.1, a brief `risk = "high"` mezője váltja ki) · Dátum: 2026-08-06
Hatókör: READ-ONLY — ez a jelentés a kimenet, production kódot nem módosít.
Verdikt: **PASS — a merge biztonsági alapon NEM tiltott** (0 CRITICAL · 0 BLOCKER · 0 MAJOR)

## Összegzés

| Súlyosság | Darab |
|---|---|
| CRITICAL | 0 |
| BLOCKER | 0 |
| MAJOR | 0 |
| MINOR | 0 |
| NOTE | 2 |

Bizonyított titok-szivárgást, consent-megkerülést, RCE-t, path traversalt vagy
megszegett termékhatárt (`AGENTS.md` §5) **nem** találtam. A kör az első
production Android kamera-capture adaptert (`PluginCameraCapture`) köti a
meglévő platform-semleges `CameraCapture` contract mögé, a `visionEnabled` flag
mögött (alapból kikapcsolva), UI-fogyasztó nélkül. A két NOTE **nem** hiba
ebben a körben — előretekintő védőkorlát a következő, vision-UI-t és
hiba-megjelenítést hozó körnek. A CRITICAL/BLOCKER hiánya miatt a §15.1
merge-tilalom biztonsági okból nem áll fenn.

> Megjegyzés a scope-ról: a párhuzamos **correctness** review
> (`docs/reviews/e05-r06-android-camera-adapter-review.md`) egy nyitott MAJOR-t
> (F1 — teszt-minőség: a „callbackben dobott kivétel" cella nem a `finally`-t
> méri) jelzett, amit azóta a review saját maga FIXED-re zárt (`2c629db`,
> önállóan újra-ellenőrizve). Az F1 **nem** biztonsági lelet volt, és nem
> ennek a jelentésnek a tárgya; a merge-döntés a két review együttes
> eredménye.

## Amit tételesen ellenőriztem — kritérium → bizonyíték

| # | Ellenőrzés (feladat + §5 határ) | Eredmény | Bizonyíték (fájl:sor / parancs) |
|---|---|---|---|
| 1 | **Nyers frame nem kerül logba/lemezre/hálózatra** (ADR 0183, §5) | ✅ TISZTA | A három ÚJ core-fájlban NULLA logolóhívás: `grep -rniE "print\(|debugPrint|developer\.log|logger|\.log\(" lib/core/camera/{plugin_camera_capture,camera_frame_binding,camera_error_mapping}.dart` → nincs találat. Semmilyen disk/net sink: se `File(`, `writeAs*`, `path_provider`, `dio`, `http`, `Share`, `socket` a diff `lib/core/camera/` részében (teljes fájl-olvasással is igazolva). A frame-bájtok kizárólag memóriában élnek: `plugin_camera_capture.dart:277-289` (`_copyPlanes` szinkron másolat) → `camera_frame.dart:23` (`Uint8List.fromList(bytes)` második, saját tulajdonú másolat) |
| 2 | **`CameraFrame`/`CameraFailure.toString()` nem szerializál nyers buffert** | ✅ TISZTA | `CameraFrame`/`PlatformCameraFrame`/`CameraCrop` NEM ír felül `toString`-et → alap `Instance of '...'` (nincs bájt-dump). `AppFailure.toString()` szándékosan kihagyja a `cause`-t és `stackTrace`-t (`app_failure.dart:96-100`, kommenttel: „may contain a URL, a request body or other sensitive payload"). `AppResult.Failure.toString()` csak a `code`-ot írja (`app_result.dart:87-89`). A meglévő `test/core/camera/camera_contract_test.dart:41` (`failure.toString()` nem tartalmaz `'Uint8List'`-et) regresszió nélkül zöld |
| 3 | **Plugin-kivétel higiénia** — a `CameraException` mint `cause` átadva | ✅ TISZTA (lásd NOTE-S1) | `camera_error_mapping.dart:9-17`: a nyers `plugin.CameraException` `cause`-ként az `CameraFailure`-be kerül, de **csak programozott vizsgálatra** — sehol nem szerializálódik/logolódik elérhető úton (`grep -rniE "\.cause" lib/` → csak dokumentációs komment két repóban, NINCS logoló felhasználás). Az adapter által gyártott `CameraException` leírás statikus, nem érzékeny angol szöveg (`plugin_camera_capture.dart:219`: `'No camera is available.'`) |
| 4 | **Ellátási lánc** — `camera` és tranzitív függőségek | ✅ IGAZOLVA | pub.dev API-val ellenőrizve: `camera 0.11.4` (publisher **flutter.dev**), `camera_android_camerax 0.6.30` (**flutter.dev**), `camera_platform_interface 2.13.1` (**flutter.dev**). A `pubspec.lock` sha256 **pontosan egyezik** a pub.dev közzétett `archive_sha256`-tal mindhárom csomagra. Nincs typosquat (a nevek a hivatalos federált „camera" plugin-család pontos nevei), minden `source: hosted`, `url: "https://pub.dev"` |
| 5 | **win32 major változatlan, nincs `dependency_overrides`** | ✅ IGAZOLVA | `pubspec.lock` `win32` továbbra is major 6 (tranzitív, sha256 `ba6f4bba…`, `version: "6.3.0"`); a diff NEM érinti a `win32` bejegyzést. A diffben nincs `dependency_overrides` |
| 6 | **Instantiation-gating** — `visionEnabled == false` ⇒ nincs adapter/platform-érintés | ✅ TISZTA | `camera_providers.dart:24-31`: a `return null` az ELSŐ ág; a gyár (`cameraCaptureFactoryProvider` → `createPlatformCameraCapture`) csak a flag-igaz ág után hívódik (`(...)()`). Ráadásul `createPlatformCameraCapture` csak konstruál — a valódi platformhívás (`plugin.availableCameras()`) a `start()`-ban lévő `_PluginCameraController.create`-ig halasztott. Teszttel is: `plugin_camera_capture_test.dart:134-149` (`factoryCalls == 0`, `provider == null`) |
| 7 | **Front-kamera `mirror` metaadat** — nem szivárogtat semmit | ✅ TISZTA | `plugin_camera_capture.dart:260-262`: `mirror = lensDirection == front` — tisztán geometriai bool, nincs PII/eszközazonosító |
| 8 | **Prompt-injection / nem megbízható input** (§5.1) | ✅ TISZTA | A diff NEM ad hozzá dal-fájl/MusicXML/MIDI/zip parse-ot, AI-providert, felhasználói szöveget. Az egyetlen külső input: (a) frame-bájtok — átlátszatlan bináris, buffernbe másolva, SOHA nem értelmezve utasításként; (b) `CameraException.code` string — fix, kisbetűsített allowlist ellen, **fail-closed** default ággal (`camera_error_mapping.dart:15`: `_ => CameraFailureKind.frame`, ami hiba, SOHA nem siker; `camera_error_mapping_test.dart:13` igazolja) |
| 9 | **OWASP-jellegű átvizsgálás** (injection/deser/path traversal) | ✅ TISZTA | Nincs fájlútvonal, nincs deszerializáció, nincs injection-felület. `_copyPlanes` (`plugin_camera_capture.dart:277-289`) a plugin által megadott plane-hosszakat összegzi egy `Uint8List`-be — OS-kamera-HAL forrás, nem támadó-kontrollált; nincs veszélyes index-aritmetika. A diff NEM érint natív/manifest/gradle/kotlin/plist fájlt (name-only ellenőrizve) |
| 10 | **Titkok új fájlokban — a fixture-k valóban fake-ek?** (szemantikai szint) | ✅ TISZTA | Az egyetlen titok-gyanús hozzáadott sor a tesztben `diagnosticsToken: AppConfig.devDiagnosticsToken` — ez a `app_config.dart:56` szerint `'strumsight-lab-dev'`, egy nyilvánvalóan fake dev-placeholder konstans, nem valódi token. A teszt-fixture `CameraException('CameraNotFound', …)` és `[byte]` bájtok is nyilvánvalóan szintetikusak. (A gépi `check_secrets` gate külön zöld — §10 handoff: „secrets: ZÖLD, 0 findings") |

## Termékhatárok (`AGENTS.md` §5) — külön kiértékelve

1. **Nyers audio/kamera-frame nem hagyja el az eszközt alapból** → **TARTVA.**
   Nincs kimenő csatorna a diffben; a frame memóriában, saját Dart-másolatként
   él, kézbesítés/dropped után GC-zhető (ADR 0183 „no-raw-frame-persistence").
2. **Kijelentkezett / flag-off állapotban nincs rejtett hálózati vagy platform
   kérés** → **TARTVA.** `visionEnabled == false` mellett az adapter nem is
   példányosul, a plugin nem inicializálódik (kritérium #6).
3. **Secret/token/frame/audio nem kerül logba vagy commitba** → **TARTVA.**
   Nincs logolás az új kódban; a `cause` sosem szerializálódik; a commit csak
   fake fixture-t tartalmaz; a lock-hash-ek igazoltak (kritériumok #1–3, #10).
4. **Cloud/community nem rontja az offline alapélményt** → **N/A** — ez a kör
   nem ad hálózati/felhő funkciót.
5. **Gyenge confidence nem jelenik meg biztos állításként** → **N/A** — ez a
   kör nem végez inferenciát és nem tesz technikai állítást.

### Pozitív megerősítés (mért, nem feltételezett)

- **`enableAudio: false`** a `CameraController`-en (`plugin_camera_capture.dart:229`)
  — a kamera-session **explicit nem** vesz fel hangot, így az új kamera-képesség
  nem nyithat véletlen audio-exfil utat. Közvetlen összhang a „nyers audio nem
  hagyja el az eszközt" határral.
- **Szinkron buffer-másolat a plugin-callback visszatérése ELŐTT**
  (`_copyPlanes` a `startImageStream` callbackjében, `plugin_camera_capture.dart:246-269`)
  — mire a microtask kézbesít, már a saját Dart-tulajdonú másolatból olvasunk,
  nem a plugin által újrahasznosított natív bufferből: nincs use-after-free és
  nyers natív buffer nem szökik ki. A production `release: () {}` no-op ezért
  helyes.

## Megállapítások

### N1 (NOTE-S1) — a `cause` nyers platform-`CameraException`-t tart; a JÖVŐBELI hiba-megjelenítő/crash-reporter kör irányítsa a redaktoron át

- **Fájl:** `lib/core/camera/camera_error_mapping.dart:17`; a védelem ma:
  `lib/core/foundation/app_failure.dart:96-100`, `app_result.dart:87-89`.
- **Failure scenario (jövőbeli, ma NEM elérhető):** ha egy későbbi kör (pl. a
  vision-UI vagy egy crash-reporter) közvetlenül `failure.cause.toString()`-et
  vagy `'$failure.cause'`-t naplóz/jelent — megkerülve a `LogRedactor`-t —,
  akkor egy platform-eredetű `CameraException.description` (ami elvben
  eszközmodell-szöveget tartalmazhat) kikerülhet. **Ma ez nincs:** egyetlen
  fogyasztó sem szerializálja a `cause`-t (kritérium #3), a `toString`-ek
  kihagyják, és a `LogRedactor` az önkényes objektumot amúgy is a típusára
  csökkenti (`log_redactor.dart:92-93`).
- **Sértett szabály:** §5 (secret/érzékeny string a logban) — **preventív**,
  nem aktuális sértés.
- **Javasolt irány:** a `cause`-t megjelenítő/jelentő kör KIZÁRÓLAG a redaktáló
  loggeren keresztül adja tovább (soha `cause.toString()` közvetlenül), és a
  UI a stabil `FailureCode`-ra lokalizáljon (ahogy az `app_failure.dart`
  fejléc-komment előírja). Ehhez a körhöz **nincs teendő**.

### N2 (NOTE-S2) — a `LogRedactor` kulcs-fragmentumai nem fedik a kamera/frame/kép mezőneveket (előretekintő védőkorlát a vision-logoláshoz)

- **Fájl:** `lib/core/logging/log_redactor.dart:27-45` (`sensitiveKeyFragments`).
- **Failure scenario (jövőbeli, ma NEM elérhető):** a redaktor kulcs-alapú
  ejtése tartalmaz `audio`/`pcm`/`wav`/`clip`/`samples` fragmentumot, de
  `camera`/`frame`/`image`/`pixel`/`yuv` fragmentumot **nem**. Egy nagy
  frame-bájttömböt a >16 szám szabály (`log_redactor.dart:83-85`) továbbra is
  `[redacted:N numbers]`-ként fedi, de egy frame-ből származtatott, NEM
  szám-lista mezőt (pl. egy kis dekódolt struktúra) kamera-szerű kulcs alatt
  nem ejtene kulcs alapján. **Ma ez nincs:** ez a kör semmit sem logol.
- **Sértett szabály:** §5 (nyers frame a logban) — **preventív**, defense-in-depth.
- **Javasolt irány:** amikor a vision-út először logol frame-metaadatot, vagy
  vegyél fel `camera`/`frame`/`image` fragmentumot a `sensitiveKeyFragments`-be,
  vagy hagyatkozz tudatosan a >16-szám/hosszú-string szabályra és fedd le
  teszttel. Ehhez a körhöz **nincs teendő**.

## Ellátási-lánc igazolás (részletes bizonyíték)

pub.dev publikus API-val, a review során lefuttatva (a box hálózata elérhető):

| Csomag | Lock verzió | Publisher (pub.dev) | Lock sha256 == pub.dev archive_sha256 |
|---|---|---|---|
| `camera` | 0.11.4 (direct main) | flutter.dev | ✅ `4142a19a…dc437` egyezik |
| `camera_android_camerax` | 0.6.30 (transitive) | flutter.dev | ✅ `8516fe30…2577` egyezik |
| `camera_platform_interface` | 2.13.1 (transitive) | flutter.dev | ✅ `4524ca6e…3498` egyezik |
| `camera_avfoundation`, `camera_web`, `flutter_plugin_android_lifecycle`, `stream_transform` | 0.9.23+2 / 0.3.5+4 / 2.0.35 / 2.1.1 (transitive) | a hivatalos federált camera-család várt tranzitív halmaza | névre/struktúrára igazolt, `source: hosted`, pub.dev |

A `win32` a diffben érintetlen, major 6 marad (`6.3.0`) — a CLAUDE.md „ONE
win32 major" invariáns nem sérül, `dependency_overrides` nincs.

## Scope-audit (biztonsági szemszög)

`git diff --name-only main...codex/e05-r06-android-camera-adapter`: minden
production/teszt-változás az `allowed_paths` §0.0 R1–R3 utáni végleges listáján
belül. A `docs/reviews/…-review.md` (a correctness review doksija) plusz
docs-fájl, nem production. **Natív/manifest változás nincs** → ez a kör NEM ad
új platform-permissiont (a kamera-permission az E05-R04 hatóköre volt); nincs új
`Dio`/HTTP hívás, nincs consent-kapu megkerülés.

## Merge-döntés (biztonsági)

**Biztonsági alapon a merge NEM tiltott** — 0 CRITICAL, 0 BLOCKER, 0 MAJOR. Az
`AGENTS.md` §15.1 kritikus/blokkoló merge-tilalma ebből a review-ból nem áll
fenn. A tényleges merge továbbra is az ADR 0052 zöld gate + exact-SHA zöld CI +
a correctness review nyitott MAJOR-jának lezárása után történhet — de ezek nem
biztonsági feltételek.
