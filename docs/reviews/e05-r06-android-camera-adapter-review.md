# E05-R06 — Review

Brief: `docs/rounds/e05-r06-android-camera-adapter.md`
Diff: `git diff main...codex/e05-r06-android-camera-adapter` (kód-review exact head `f2bd8bd`; F1 javító kör után `2c629db`)
Reviewer: Claude Sonnet 5 (orchestrator) · Dátum: 2026-08-06
Verdikt: **APPROVED F1 javító kör után** (0 nyitott BLOCKER/MAJOR/MINOR; a
dedikált security-reviewer eredménye külön szakaszban, `docs/reviews/e05-r06-android-camera-adapter-security.md`)

## Összegzés

BLOCKER: 0 · MAJOR: 1 (FIXED) · MINOR: 0 · NOTE: 2

## Javító kör (F1)

**Commit `2c629db`** (Terra). A „throwing frame callback…" tesztet lecserélte
egy `PlatformCameraFrame(width: 0, …)`-ra, ami valóban a
`CameraFrameBinding.bind()` szinkron törzséből (a meglévő `CameraFrame`
konstruktor `ArgumentError`-ján át) dobja a kivételt — pontosan a review
javaslata szerint, plusz egy extra, nem kért ellenőrzéssel (`errors.single`
konkrétan `CameraFailure` és `FailureCode.cameraFrameFailed`, valamint
`fail(...)` az `onData`-n, ami bizonyítja, hogy érvénytelen frame sosem
kézbesül sikeresen).

**A review önállóan, friss izolált klónban (`/tmp/review-e05-r06-fix1`,
törölve) újra-futtatta a gate-et (mind a 6 lépés zöld) és megismételte a
mutáció-kill próbát**: a `finally`-t ismét eltávolítva a JAVÍTOTT teszt most
**piros** (`Expected: [1], Actual: []`) — a brief §6.1 „callbackben dobott
kivétel" cellája most már valóban géppel bizonyított. F1 **Státusz: FIXED**.

Az implementáció tartalmilag helyes és jó minőségű — mind a négy önálló
mutáció-kill próba, amit a review futtatott, a várt módon viselkedett, KIVÉVE
egyet: a „callbackben dobott kivétel" elfogadási cella tesztje nem azt a
hibaosztályt fogja pirosra, amit a brief §6.1 leír, bár maga a termék-kód
helyes (l. F1 — a review saját, javított próbateszttel igazolta mindkét
állítást).

## Módszertan

Minden próba **izolált klónban** futott (`/tmp/review-e05-r06`, `git clone
--branch codex/e05-r06-android-camera-adapter`), a mutáció → piros → eredeti
visszaállítás → zöld ciklussal, a megosztott munkapéldány (`/home/ubuntu/
ss-codex-e05-r06`, `/home/ubuntu/music-theory`) érintése nélkül. A klón a
review végén törölhető.

## Acceptance criteria

| # | Kritérium (brief §6) | Teljesült | Bizonyíték |
|---|---|---|---|
| 1 | Buffer-felszabadítás mátrix — 4 cella, mindegyik pontosan egyszer released | ⚠️ Részben | processed/dropped/close-cella: kód olvasva + a dropped-cella mutáció-kill próbával (Probe B, lásd lent) igazolva. „callbackben dobott kivétel" cella: **a termékkód helyes** (Probe A2 igazolta), de a checked-in teszt nem ezt a hibaosztályt méri — lásd F1 |
| 2 | Hiba-mapping mátrix — 5 kód, mind külön `FailureCode`, ismeretlen ≠ siker | ✅ | `test/core/camera/camera_error_mapping_test.dart`; mutáció-kill próba (Probe D): az ismeretlen-kód ágat `device-error`-ral azonosra állítva a teszt PIROSRA vált (`camera.frame_failed` → `camera.initialization_failed` mismatch) |
| 3 | Backpressure-teszt — N gyors frame, legfrissebb kézbesítve, dropped = N−kapott | ✅ | `plugin_camera_capture_test.dart` „rapid frames…"; mutáció-kill próba (Probe B): a legrégebbi-frame-megtartásra állítva mindkét backpressure-teszt PIROSRA vált (`Expected: [5], Actual: [1]`) |
| 4 | Metaadat round-trip — rotation×mirror 8 cella változatlanul átmegy | ✅ | `plugin_camera_capture_test.dart` „binding preserves every rotation and mirror…" — mind a 4 `CameraOrientation` × 2 `mirror` érték tesztelve; `CameraFrameBinding.bind` egyenes mezőmásolás (nincs logika, ami elronthatná anélkül, hogy ez a teszt elkapná) |
| 5 | `pubspec.lock` win32 major változatlan | ✅ | Függetlenül ellenőrizve: `rg -n win32 pubspec.lock` → `version: "6.3.0"`, azonos a kör előtti állapottal; a §10 handoff idézi a `camera 0.11.4` + `camera_android_camerax 0.6.30` + `camera_platform_interface 2.13.1` solve-ot |
| 6 | A natív bizonyíték a CI (`build-apk.yml` zöld az exact SHA-n) | ⏳ Függőben | Az orchestrátor a review után dispatch-eli — nem ennek a jelentésnek a tárgya |

## Scope-audit

`git diff --stat main...codex/e05-r06-android-camera-adapter` (izolált
klónban futtatva): **10 fájl, mind a 10 az allowed_paths listán** (a §0.0
R1–R3 revíziók utáni, végleges lista). Engedélyezett fájlokon kívüli
változás: **nincs**. A `.codex-round-status` gépi `scope_audit=ok` mezőjét is
ellenőriztem — `scope_audit_changed=10`, egyezik.

## Architektúra és termékhatárok (AGENTS.md §5–§6)

- **Core↛feature, plugin-encapsuláció:** `grep -rln "package:camera" lib/` →
  kizárólag `plugin_camera_capture.dart` és `camera_error_mapping.dart`.
  Semmi más `lib/core/camera/` fájl, és `lib/features/vision/` (ami ez a kör
  nem is hoz létre) nem importálja a plugint. Ez pontosan a §0.0 R3
  korlátozás, amit a review külön ellenőrzött, nem csak elfogadott bemondásra.
- **`visionEnabled == false` ⇒ nincs instantiation:** kód olvasva
  (`camera_providers.dart:24-31`, a `return null` az ELSŐ sor, a
  `cameraCaptureFactoryProvider` csak utána `watch`-olva) ÉS mutáció-kill
  próbával igazolva (Probe C): a guard eltávolítva → a „vision flag off…"
  teszt PIROSRA vált (`Expected: null, Actual: <FakeCameraCapture>`).
- **Nyers frame nem kerül logba:** `grep -rn "print(\|debugPrint(" lib/core/
  camera/{plugin_camera_capture,camera_frame_binding,camera_error_mapping}
  .dart` → nulla találat. A meglévő R03 `camera_contract_test.dart` teszt
  (`failure.toString() nem tartalmaz 'Uint8List'-et`) továbbra is zöld,
  regresszió nélkül.
- **Lifecycle-erőforrás felszabadítás:** `cameraCaptureProvider`
  `ref.onDispose(() => unawaited(capture.close()))`-t regisztrál — a
  provider disposal-nál a valódi adapter is lezár, nem csak a fake-ekben
  tesztelt út.

## Megállapítások

### F1 — MAJOR — a „callbackben dobott kivétel" elfogadási cella nem azt méri, amit a brief előír

- **Fájl:** `test/core/camera/plugin_camera_capture_test.dart:64-87` (teszt);
  a valós védelem `lib/core/camera/plugin_camera_capture.dart:182-199`
  (`_deliverLatestFrame` try/catch/**finally**).
- **Probléma:** a teszt egy **downstream stream-listener** kivételét dobja
  (`capture.frames.listen((_) => throw StateError(...))`,
  `runZonedGuarded`-del elkapva). Egy `sync: true` broadcast
  `StreamController.add()` hívása esetén ez a kivétel a Dart Zone-hibakezelőn
  keresztül fut, **nem** száll vissza szinkron az `add()` hívási pontjára —
  tehát a `_deliverLatestFrame` metódus try/catch/finally blokkját soha nem
  éri el, és a `finally` jelenléte/hiánya nem befolyásolja az eredményt.
  **Empirikusan igazolva:** a `finally`-t eltávolítva (a `release()`-t a
  `try` blokk végére mozgatva, pontosan a brief §6.1 által leírt hibás
  implementáció) a checked-in teszt **továbbra is zöld marad** — tehát a
  brief saját mérce-mátrix-sora („A release() a try blokkon belül marad… a
  számláló 0") jelenleg **nincs** géppel bizonyítva, holott a §6 ezt
  kötelező, számozott elfogadási kritériumként írja elő.
- **A termékkód maga helyes:** a review egy MÁSIK, valódi belső hibát okozó
  próbateszttel igazolta ezt — `CameraFrameBinding.bind()` hívást
  megbuktatva (`width: 0`, ami a meglévő `CameraFrame` konstruktor
  `ArgumentError`-ját váltja ki, tehát VALÓBAN a try blokkon belülről, a
  `bind()`-ból száll fel a kivétel): az eredeti (mutálatlan) kóddal a teszt
  zöld (`releases == [1]`), a `finally` eltávolítása után **piros**
  (`Expected: [1], Actual: []`). Ez bizonyítja, hogy a `finally` ma
  ténylegesen szükséges és helyesen működik — csak a checked-in teszt nem ezt
  a hibaosztályt reprodukálja.
- **Hatás:** egy jövőbeli refaktor, amely véletlenül kiveszi a `finally`-t
  (pl. a hibakezelés átszervezésekor), **nem buktatna semmilyen tesztet** —
  a brief saját mérce-mátrixa ezt a pontos regressziót ígéri elkapni, és ma
  nem kapja el.
- **Kötelező javítás:** cseréld le (vagy egészítsd ki) a „throwing frame
  callback…" tesztet úgy, hogy a kivétel a `_deliverLatestFrame` szinkron
  törzséből (pl. `CameraFrameBinding.bind()`-ból, `width: 0`-s frame-mel,
  ahogy a review próbateszt tette) szálljon fel, ne a downstream listenerből.
  A review saját próbaverziója (fent leírva) közvetlenül átvehető.
- **Ellenőrzés:** a javított teszt zöld az eredeti kóddal, és piros, ha a
  `finally`-t ideiglenesen eltávolítod (a review ezt már elvégezte és
  visszaállította az izolált klónban — a javító kör ismételje meg a saját
  branch-én, hogy a commit mellé kerüljön a piros→zöld bizonyíték).
- **Státusz:** FIXED (`2c629db`) — l. „Javító kör (F1)" fent, önálló újra-
  ellenőrzéssel.

### N1 — NOTE — a `crop` mező mai értéke mindig `null` production-ban

A `camera` plugin `CameraImage`-je ma nem jelent crop-régiót; a
`PluginCameraCapture` ezért `crop: null`-t küld, dokumentáltan (§10 handoff).
Ez a §0.0 R2 revízió által kifejezetten megengedett, gyengébb mérce-bár —
nem lelet, csak rögzítve a jövőbeli (R07) referencia kedvéért: ha egy
későbbi plugin-verzió crop-ot kezd jelenteni, a binding már készen áll rá
(mutáció-kill próbával igazolva a review során, a fake réteg felől).

### N2 — NOTE — a hiba-kód string-egyeztetés a plugin dokumentációja alapján, nem futásidőben igazolva

`camera_error_mapping.dart` a `CameraException.code` várt értékeit
(`CameraDisconnected`, `CameraInUse`, `CameraMaxCamerasInUse`,
`CameraDeviceError`) kis- és nagybetű-függetlenül hasonlítja. Ezen a boxon
nincs Android SDK, tehát ezek a pontos string-ek valós eszközön/CI APK-n
nem voltak közvetlenül megfigyelhetők ebben a körben — a mapping a plugin
publikus dokumentációjára/forráskódjára épül. Nem blokkoló (az „ismeretlen
kód" ág biztonságosan `camera.frame_failed`-re esik vissza, nem sikerre),
de érdemes a device-mátrix PENDING soraiban egy tételt nyitni, ha a jövőbeli
valós-eszközös teszt más kódot észlel.

## Gate-bizonyíték ellenőrzése

| Gate | Állított eredmény (§10 handoff) | Ellenőrizve |
|---|---|---|
| format | zöld (1046 fájl, 0 változott) | ✅ saját izolált futtatás, azonos eredmény |
| analyze | zöld | ✅ saját izolált futtatás, azonos eredmény |
| test test/core/camera | zöld, 56 teszt | ✅ saját izolált futtatás: 56/56 zöld |
| architecture | zöld | ✅ saját izolált futtatás; a diff nem érinti `tool/**`-t, az allowlist változatlan (ADR 0180 kikötése) |
| secrets | zöld | ✅ saját izolált futtatás |
| l10n | zöld | ✅ saját izolált futtatás |
| CI (teljes suite + property + APK) | — | ⏳ dispatch az F1 javítás UTÁNI exact SHA-ra következik |

**F1 utáni re-run** (`/tmp/review-e05-r06-fix1`, izolált klón, törölve):
format/analyze/test (56/56)/architecture/secrets/l10n mind zöld, azonos a
fenti táblával.

## Merge-döntés

**A kód-review oldala szerint mehet a merge** — 0 nyitott BLOCKER/MAJOR/MINOR
(F1 FIXED, önállóan újra-ellenőrizve). A brief `risk = "high"`, ezért a
**dedikált security-reviewer PASS-ja is kötelező feltétel** (AGENTS.md §15.1)
— ezt az orchestrátor a security-jelentés (`docs/reviews/
e05-r06-android-camera-adapter-security.md`) alapján zárja le, majd
dispatch-eli a CI-t (`tools/round-ci-plan.py` szerint `build-apk.yml` +
`router-ci.yml`) és exact-SHA zöld után merge-el (ADR 0052).
