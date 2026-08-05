# E05-R04 — Camera permission gateway és platform deklarációk

- **Státusz:** PREPARED (előre megírva 2026-08-05, kód olvasva: main @ `5d082dc`)
- **SDD-kör:** [`docs/sdd/06-epic-05-computer-vision.md`](../sdd/06-epic-05-computer-vision.md) Kör 4; §12
- **Branch:** `codex/e05-r04-camera-permission-and-platform-declarations`
- **Előfeltétel:** **E05-R03 merge**
- **Brief szerzője:** Claude (batch) · **Implementáció:** Codex (Terra)

```ai-router
schema_version = 1
risk = "high"
allowed_paths = [
  "lib/core/camera/camera_permission.dart",
  "lib/core/platform/platform_providers.dart",
  "android/app/src/main/AndroidManifest.xml",
  "ios/Runner/Info.plist",
  "test/core/camera/camera_permission_test.dart",
  "test/core/platform/platform_declarations_test.dart",
  "docs/rounds/e05-r04-camera-permission-and-platform-declarations.md",
]
gate_tests = [
  "test/core/camera",
  "test/core/platform",
]
native_gate = false
```

> ⚠ **Pre-flight (KÖTELEZŐ):** `origin/main` + E05-R03 merge; olvasd újra
> `lib/core/platform/microphone_permission.dart` **teljes egészében** (a camera
> gateway ennek a szerződésnek a párja) és `lib/core/platform/platform_providers.dart`
> mai provider-készletét. Nincs ÚJ ADR (0161/0163 bővítése).
> PREPARED→PLANNING, brief commit az implementer indítása ELŐTT.

## 0. Kör-jelzés és STOP-protokoll

```bash
tools/codex-signal.sh progress "<egy sor>" ; tools/codex-signal.sh done "<egy sor>"
tools/codex-signal.sh stopped "<egy sor>" ; tools/codex-signal.sh blocked "<egy sor>"
```

Lezáró jelzés nélkül a kör bukott. Listán kívüli fájl → `stopped`.

## 0.0 Tervezési baseline és pre-flight revízió

**PREPARED.** Nincs előre kiosztott ADR.

## 1. Cél

A kameraengedély **opcionális, fail-closed** bevezetése: gateway-interfész +
production implementáció + platform-deklarációk, úgy, hogy kamera nélkül a mai
app minden útvonala változatlanul működjön.

**Scope-megjegyzés (tudatos eltérés az SDD Kör 4-től):** a permission **UI**
(képernyő/panel, denied/permanently-denied CTA-k) és a hozzá tartozó ARB
kulcsok az **E05-R08** (setup wizard) körbe kerültek — ott van a UI-kontextus,
és így ez a biztonságkritikus kör nem hígul UI-munkával. Ez a kör a gateway,
a hibatérkép és a deklarációk.

## 2. Jelenlegi állapot (mért, `5d082dc`)

- `lib/core/platform/microphone_permission.dart`: `MicrophonePermissionState`
  (granted/denied/permanentlyDenied/restricted/**unavailable**),
  `MicrophonePermissionGateway` (`currentState()`, `request()`),
  `PermissionHandlerMicrophoneGateway` — a plugin-hiba (`MissingPluginException`)
  **`unavailable`**, sosem `granted`. Ez a másolandó szerződés.
- `android/app/src/main/AndroidManifest.xml`: `RECORD_AUDIO`, `INTERNET`,
  `POST_NOTIFICATIONS`, `RECEIVE_BOOT_COMPLETED`. **Nincs `CAMERA`.**
- `ios/Runner/Info.plist`: nincs `NSCameraUsageDescription`.
- `permission_handler: ^12.0.0` már függőség — új plugin **nem kell**.
- `lib/core/platform/platform_providers.dart` tartalmazza a platform-gateway
  providereket; a camera permission gateway ide, additívan kerül.

## 3. Scope

**Benne:** `CameraPermissionState` + `CameraPermissionGateway` +
`PermissionHandlerCameraGateway`, camera `PermissionFailure` mapping,
Riverpod provider, Android `CAMERA` permission (**`android:required="false"`
feature-deklarációval**), iOS `NSCameraUsageDescription` privacy-pontos angol
szöveggel, és a deklarációkat őrző strukturális tesztek.

**Kívül — TILOS:** UI/ARB (R08), camera indítás, coordinator (R05),
`RECORD_AUDIO`-hoz nyúlás, bármely meglévő permission viselkedésének változtatása.

## 4. Engedélyezett fájlok

| Útvonal | Állapot | Miért |
|---|---|---|
| `lib/core/camera/camera_permission.dart` | ÚJ | state + gateway + prod impl |
| `lib/core/platform/platform_providers.dart` | meglévő | **additív** provider |
| `android/app/src/main/AndroidManifest.xml` | meglévő | `CAMERA` + `uses-feature` |
| `ios/Runner/Info.plist` | meglévő | `NSCameraUsageDescription` |
| `test/core/camera/camera_permission_test.dart` | ÚJ | állapot-mátrix |
| `test/core/platform/platform_declarations_test.dart` | ÚJ | manifest/plist őr |
| `docs/rounds/e05-r04-*.md` | meglévő | §10 handoff |

**Tilos zóna:** minden más. Listán kívül → `stopped`.

## 5. Kötött architekturális döntések

1. **Fail-closed:** ismeretlen/hibás permission-állapot → `unavailable`, ami
   **nem** engedélyezés. **NEM elfogadható:** `catch` ág, amely `granted`-et,
   `true`-t vagy „optimista" alapértelmezést ad; és **nem elfogadható** üres
   `catch` (AGENTS.md §10).
2. **A permission csak explicit felhasználói akcióra kérhető** — a gateway
   `request()`-je **soha nem hívódhat** app-bootstrapból vagy route-buildből.
   Ezt az R08 UI-köre használja; itt a szabály a dokumentált contract.
3. **Android:** `<uses-permission android:name="android.permission.CAMERA" />`
   **és** `<uses-feature android:name="android.hardware.camera" android:required="false" />`
   — kamera nélküli eszközön az app telepíthető marad. **NEM elfogadható**
   a `required="true"`, sem a `CAMERA` permission `uses-feature` nélkül.
4. **iOS usage string:** angol, és **nem állíthat felhőfeltöltést**; kötelezően
   tartalmazza, hogy a feldolgozás a készüléken marad, és felvétel nem készül
   (ADR 0161). **NEM elfogadható** általános „to use the camera" szöveg.
5. **A `RECORD_AUDIO` út érintetlen** — a mikrofon-tesztek nem regresszálhatnak.

## 6. Acceptance criteria

- [ ] **Állapot-mátrix teszt** mind az öt állapotra (granted, denied,
      permanentlyDenied, restricted, unavailable) × `currentState()`/`request()`,
      injektált fake plugin-réteggel; a `MissingPluginException` ág **külön**
      cella, és `unavailable`-t ad.
- [ ] A gateway `failure` térképe: `denied` → retryable, `permanentlyDenied` és
      `restricted` → **nem** retryable, `unavailable` → nem retryable.
- [ ] **Deklaráció-őr teszt** (pure Dart, fájlt olvas): a manifest tartalmazza a
      `CAMERA` permissiont ÉS az `android:required="false"` uses-feature-t; a
      plist tartalmazza az `NSCameraUsageDescription`-t; a usage string nem
      tartalmazza az `upload`/`cloud`/`server` szavakat.
- [ ] **Valódi-sértés próba (§10-ben dokumentálva):** az `uses-feature` sor
      ideiglenes törlése → a deklaráció-őr teszt PIROS → visszaállítás.
- [ ] `test/core/platform` és a mikrofonos tesztek **változatlanul zöldek**.

## 7. Kötelező ellenőrzések

```bash
tools/round-gate.sh test/core/camera test/core/platform
```

Külön processzek, nincs `&&`/pipe/`tail`. A tényleges Android manifest-merge és
a plist-betöltés bizonyítéka a CI `build-apk` futása (orchestrátor dispatch);
a valós eszközös permission-dialógus a device-mátrix **PENDING** sora.

## 8. Implementációs sorrend

1. RED: állapot-mátrix + deklaráció-őr tesztek.
2. `CameraPermissionState` + gateway + production impl.
3. Manifest + plist.
4. Provider; gate.

## 9. Kockázatok

- **Manifest-merge ütközés** más plugin `CAMERA` deklarációjával — csak a CI
  APK-build mutatja meg; ha piros, az `stopped`, nem lokális workaround.
- **`permission_handler` camera API** eltérhet a mikrofonétól; a gateway
  ugyanazt a *saját* enumot adja vissza — plugin-típus nem szivároghat ki.

**STOP:** UI/ARB fájl érintése, `RECORD_AUDIO` módosítása vagy mércegyengítés
helyett dokumentált brief-revízió.

## 10. Implementation handoff — az implementer tölti ki

_(üres)_

## 11. Review — a független reviewer tölti ki

Tervezett review: `docs/reviews/e05-r04-camera-permission-and-platform-declarations-review.md`.
Merge csak exact-SHA zöld CI, §4-en belüli diff és nulla OPEN BLOCKER/MAJOR után.
