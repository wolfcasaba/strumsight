# E05-R06 — Android camera production adapter

- **Státusz:** PLANNING (előre megírva 2026-08-05, kód olvasva: main @ `5d082dc`; pre-flight 2026-08-06, mérve: main @ `796978b`)
- **SDD-kör:** [`docs/sdd/06-epic-05-computer-vision.md`](../sdd/06-epic-05-computer-vision.md) Kör 6; §11.2, §11.4
- **Branch:** `codex/e05-r06-android-camera-adapter`
- **Előfeltétel:** **E05-R02 (ADR 0184), E05-R03, E05-R05 merge**
- **Brief szerzője:** Claude (batch) · **Implementáció:** Codex (Terra)

```ai-router
schema_version = 1
risk = "high"
allowed_paths = [
  "lib/features/vision/data/camera/plugin_camera_capture.dart",
  "lib/features/vision/data/camera/camera_frame_binding.dart",
  "lib/features/vision/data/camera/camera_error_mapping.dart",
  "lib/core/camera/camera_providers.dart",
  "pubspec.yaml",
  "pubspec.lock",
  "test/features/vision/data/plugin_camera_capture_test.dart",
  "test/features/vision/data/camera_error_mapping_test.dart",
  "docs/rounds/e05-r06-android-camera-adapter.md",
]
gate_tests = [
  "test/features/vision/data",
  "test/core/camera",
]
native_gate = false
```

> ⚠ **Pre-flight (KÖTELEZŐ):** `origin/main` + E05-R02/R03/R05 merge; olvasd újra
> az **ADR 0184** választott stackjét (ha a runbook megdöntötte, EZ a kör követi
> a módosított ADR-t), a `pubspec.yaml` mai `dependencies` blokkját és a
> **win32 gotchát** (CLAUDE.md: ONE win32 major; `flutter_secure_storage` v10 →
> win32 ^6). Nincs ÚJ ADR. PREPARED→PLANNING, brief commit előbb.

## 0. Kör-jelzés és STOP-protokoll

```bash
tools/codex-signal.sh progress "<egy sor>" ; tools/codex-signal.sh done "<egy sor>"
tools/codex-signal.sh stopped "<egy sor>" ; tools/codex-signal.sh blocked "<egy sor>"
```

Lezáró jelzés nélkül a kör bukott. Listán kívüli fájl → `stopped`.

## 0.0 Tervezési baseline és pre-flight revízió

**PLANNING.** Mérve `origin/main` @ `796978b` (E05-R02/R03/R05 mind merge-elve,
working tree tiszta). Nincs ÚJ ADR ebben a körben — a §1 döntés a meglévő
ADR 0184 végrehajtása.

**ADR-hivatkozás javítás (0167 → 0184).** A brief minden `ADR 0167`
hivatkozása elavult volt. Az E05-R02 saját briefje
(`docs/rounds/e05-r02-camera-technology-decision.md`, „ADR-szám revízió"
szakasz) dokumentálja, hogy a 2026-08-05-i előre-kiosztás **0167** volt, de az
E05-R01 hat ADR-je (0178–0183) miatt a tényleges kiosztott szám **ADR 0184**
(`docs/adr/0184-vision-camera-capture-stack.md`) lett — a `HANDOFF.md` E05-R02
bejegyzése is ezt a számot használja. Ez a pre-flight minden `0167`
előfordulást (fejléc, előfeltétel-sor, pre-flight blockquote, §1, §3) `0184`-re
javít; a §4 engedélyezett fájllista és a §5–§9 tartalmi előírásai változatlanok.

**A döntés mérve, nem megdöntve.** ADR 0184 3. pontja: C2 (saját CameraX
platform channel) csak akkor váltja C1-et, ha a device runbook M05
(latest-frame backpressure) vagy M10 (monoton timestamp) bukását rögzíti.
Mérve: `docs/manual-testing/vision-device-matrix.md` §2.8 mind a 12 sora
**PENDING**, és `docs/baseline/epic-05-camera-stack-evaluation.md` M05/M10
sorai **MÉRENDŐ** (ezen a boxon nincs Android SDK, valós eszközös mérés itt
nem futtatható) — tehát nincs rögzített C1-bukás. **C1 (hivatalos Flutter
`camera` plugin, CameraX-backed Androidon) marad az operatív alapértelmezés**,
ez a kör ezért a plugin-utat implementálja; a §3 „ha az ADR 0184 a plugin-utat
választotta" feltétele teljesül, a saját Kotlin platform-channel TILOS marad.

**Pre-flight mérési megerősítések (nincs eltérés a brief tartalmi
előírásaitól, csak a fenti számhiba):**

- `visionEnabled` létezik (`lib/app/config/feature_flags.dart:114`), és ma
  sehol nem olvassa senki a `lib/`-ben — ez a kör lesz az első fogyasztója;
  a gate bemenete `lib/app/config/app_config.dart:190`
  (`appConfigProvider` → `.flags.visionEnabled`).
- A hat `FailureCode.camera*` konstans (`lib/core/foundation/app_failure.dart:42-48`)
  szó szerint egyezik a meglévő `CameraFailureMapper`
  (`lib/core/camera/camera_failure.dart`) hat kimenetével — a hiba-mapping
  mátrix (§6.1) célértékei ma is elérhetők, nincs hiányzó enum-érték.
- `CameraSessionCoordinator.acquire()`-nak ma **nulla** hívója van `lib/`-ben
  (`grep -rn "\.acquire(" lib/` → egyetlen találat, a mikrofon-analóg
  `mic_capture.dart`) — a lease-fogyasztás valóban R06 scope-on kívül van,
  ahogy a brief állítja; ez a kör csak a `CameraCapture` adaptert köti be a
  providerbe, a coordinatort/lease-t nem érinti.
- Az `AudioCaptureFactory` mintája (`lib/core/audio/capture/audio_capture_factory.dart`)
  a precedens a `camera_providers.dart` bekötéshez: `typedef … Function()`
  gyár + valódi plugin-backed implementáció — az implementer ezt a meglévő
  mintát követi, nem tervez újat.

**§0.0 revízió (2026-08-06, R1 — post-stop): `pubspec.lock` felvéve az
allowed_paths-ba.** Az implementer helyesen `stopped`-ot jelzett
(`0942b97`): a `camera` függőség felvétele szükségképpen frissíti a
trackelt `pubspec.lock`-ot, de az eredeti lista csak a `pubspec.yaml`-t
engedte — a §6/§6.1 acceptance criteria ugyanakkor már eredetileg is a
`pubspec.lock`-ot mérte (`rg -n "win32" pubspec.lock`), tehát a hiány a
listában belső ellentmondás volt, nem szándékos korlátozás. Négy korábbi
kör (`e03-r06`, `e03-r07`, `e03-r11`, `e03-r15` — mind függőség-felvétel)
ugyanígy, explicit `pubspec.lock` allowed_paths-bejegyzéssel oldotta ezt
meg; ez a revízió ugyanazt a mintát követi. Az allowed_paths mostantól
tartalmazza a `pubspec.lock`-ot (fent). Semmilyen más engedélyezett fájl,
tilos zóna vagy tartalmi előírás nem változott. Terra jelenlegi mért
win32-evidenciája (a stop előtti, még változatlan lock alapján): a
lock ma `win32` `6.3.0`-t old fel — ez a §5.6/§9 win32-ellenőrzés
kiindulási állapota, nem a `camera` hozzáadása utáni eredmény.

## 1. Cél

Az ADR 0184 szerinti production capture-adapter bekötése a **meglévő**
`CameraCapture` contract mögé: preview + **latest-frame** analysis stream,
megőrzött timestamp/rotation/mirror metaadattal és **mindig** felszabaduló
platform-bufferrel.

## 2. Jelenlegi állapot (mért, `5d082dc`, + a megelőző körök)

- `lib/core/camera/` (E05-R03/R05): contract, `CameraFrame` ownership, fake,
  failure-térkép, coordinator, lease, lifecycle guard, providerek.
- `pubspec.yaml`: **nincs `camera*` függőség**; a `flutter_secure_storage` v10
  tartja a **win32 ^6** kényszert — új plugin hozzáadása előtt a version-solve
  ellenőrzése kötelező.
- **Ezen a boxon nincs Android SDK** — a natív oldal fordítási bizonyítéka a CI
  `build-apk.yml` futása; instrumented teszt itt nem futtatható.

## 3. Scope

**Benne:** a plugin-alapú `CameraCapture` implementáció (`PluginCameraCapture`),
frame-binding (platform buffer → `CameraFrame`, **mindig** felszabadítva, hiba
esetén is), platform-hibák (disconnected, in-use, max-cameras-in-use, device
error) → stabil `FailureCode` mapping, a plugin függőség felvétele, és a
production adapter bekötése a providerbe **`visionEnabled` flag mögé**.

**Kívül — TILOS:** ML inference (R12+), transform (R07), UI, saját Kotlin
platform-channel **ha az ADR 0184 a plugin-utat választotta** (ha a saját
channelt választotta, a Kotlin fájlok a pre-flightban kerülnek a listára,
dokumentált brief-revízióval).

## 4. Engedélyezett fájlok

| Útvonal | Állapot | Miért |
|---|---|---|
| `.../data/camera/plugin_camera_capture.dart` | ÚJ | production adapter |
| `.../data/camera/camera_frame_binding.dart` | ÚJ | buffer → `CameraFrame` |
| `.../data/camera/camera_error_mapping.dart` | ÚJ | platformhiba → `FailureCode` |
| `lib/core/camera/camera_providers.dart` | R05-ből | production adapter bekötése |
| `pubspec.yaml` | meglévő | camera függőség |
| `test/features/vision/data/*` | ÚJ | adapter + mapping tesztek |
| `docs/rounds/e05-r06-*.md` | meglévő | §10 handoff |

**Tilos zóna:** minden más; `docs/rag`; DSP; audio-útvonal. Listán kívül → `stopped`.

## 5. Kötött architekturális döntések

1. **Latest-frame backpressure.** Ha az elemzés lassabb, mint a capture, a
   **régi frame eldobódik** — nincs korlátlan sor. **NEM elfogadható:**
   „kis buffer" bevezetése konfigurálható mérettel, mert az késleltetést halmoz;
   a dropped-frame **számláló kötelező** (a performance summary bemenete).
2. **A platform buffer minden úton felszabadul** — sikeres feldolgozás, dobott
   frame, kivétel és close esetén is. **NEM elfogadható:** csak a happy path-on
   felszabadító `finally` nélküli kód.
3. **A metaadat nem veszhet el:** capture timestamp (monotonic), rotation,
   mirror state, width/height, crop. **NEM elfogadható** a rotation „majd a
   UI-ban" korrekciója (a transform réteg az R07, és az ehhez a metaadathoz nyúl).
4. **A plugin típusa nem szivároghat ki** a `lib/core/camera/` contractból
   (ADR 0163) — a `data/` réteg a határ. **NEM elfogadható** plugin-import a
   `lib/core/` vagy `lib/features/vision/domain/` alatt.
5. **A production adapter `visionEnabled == false` mellett nem példányosítható**
   (a provider a flaget nézi) — a mai app viselkedése változatlan.
6. **Win32-szabály:** ha a plugin version-solve win32 major-ütközést hoz,
   az **`stopped`**, nem `dependency_overrides`.

## 6. Acceptance criteria

- [ ] **Buffer-felszabadítás mátrix (fake platform-réteggel), cellánként teszt:**
      feldolgozott frame · eldobott frame (backpressure) · a callbackben dobott
      kivétel · close alatti frame — mind a négy után a release **pontosan
      egyszer** hívódik. A számlálót a teszt olvassa.
- [ ] **Hiba-mapping mátrix:** disconnected / in-use / max-cameras-in-use /
      device-error / ismeretlen kód → külön `FailureCode`, az ismeretlen
      **nem** képződik sikerre.
- [ ] **Backpressure-teszt:** N gyors frame + lassú fogyasztó → a fogyasztó a
      **legfrissebbet** kapja, és a dropped-számláló `N - kapott`.
- [ ] **Metaadat round-trip:** rotation ∈ {0,90,180,270} × mirror ∈ {true,false}
      mátrix — mind a 8 cella átmegy a bindingen változatlanul.
- [ ] `pubspec.lock` version-solve zöld, **win32 major változatlan** (a §10-ben
      a `rg -n "win32" pubspec.lock` kimenete idézve).
- [ ] **A natív bizonyíték a CI:** a `build-apk.yml` zöld futása az exact SHA-n
      (orchestrátor dispatch). A 100 start/stop stresszteszt és a valós preview
      a device-mátrix **PENDING** sora — nem merge-kapu.

### 6.1 Mérce-mátrix — melyik hibás implementációt fogja pirosra

| Hibás implementáció | Melyik cella vált PIROSRA |
|---|---|
| A `release()` a `try` blokkon belül marad (a catch-ág nem szabadít fel) | buffer-mátrix **„callbackben dobott kivétel"** cellája (a számláló 0) |
| A `release()` kétszer fut a close alatt érkező frame-re | buffer-mátrix **„close alatti frame"** cellája (a számláló 2 ≠ 1) |
| A backpressure a **legrégebbi** frame-et adja át | backpressure-teszt (a fogyasztó nem a legfrissebbet kapja) |
| Az ismeretlen platform-kód default ága sikerre képződik | hiba-mapping mátrix ismeretlen-cellája |
| A binding elejti a `mirror` metaadatot | round-trip mátrix 8 cellájából a 4 mirror-cella |
| A `pubspec.yaml` win32 majort emel | a §6 win32-cellája (`rg -n "win32" pubspec.lock`) |

## 7. Kötelező ellenőrzések

```bash
tools/round-gate.sh test/features/vision/data test/core/camera
```

Külön processzek, nincs `&&`/pipe/`tail`. `native_gate = false`: ezen a boxon
nincs Android SDK — a fordítás bizonyítéka a CI.

## 8. Implementációs sorrend

1. Függőség + version-solve ellenőrzés (win32!).
2. RED: buffer-, backpressure-, mapping- és metaadat-mátrix.
3. Frame binding → adapter → error mapping.
4. Provider-bekötés flag mögé; gate.

## 9. Kockázatok

- **A plugin frame-callbackje nem szinkron ownershipű** → a `CameraFrame`
  érvényességi szabálya sérülhet; a binding felelőssége a másolás vagy a
  szinkron feldolgozás kikényszerítése (a döntést a §10 rögzíti).
- **Version-solve robbanás** (win32, AGP, minSdk). A minSdk emelése ebben a
  körben **nem** engedélyezett scope-tágítás nélkül → `stopped`.
- **A CI APK-build lassabb lesz** az új plugintől; ez nem indok a gate kikapcsolására.

**STOP:** `dependency_overrides`, minSdk-emelés, plugin-típus szivárgás a core-ba
vagy mércegyengítés helyett dokumentált brief-revízió.

## 10. Implementation handoff — az implementer tölti ki

**2026-08-06 — STOPPED before implementation.** The required `camera`
dependency solve would regenerate the tracked `pubspec.lock`, but §4 permits
only `pubspec.yaml` and does not permit `pubspec.lock`. Per §0 and §9 this is a
scope conflict, so no production or dependency file was changed.

Required Win32 evidence from `rg -n "win32" pubspec.lock` before the stop:

```text
1181:  win32:
1184:      name: win32
```

The existing lock resolves `win32` at `6.3.0` (the surrounding lock entry).
No version solve was run because it would first write the out-of-scope lock
file. A revised brief must explicitly allow `pubspec.lock` before this round
can add the plugin and verify the one-major invariant.

**2026-08-06 — STOPPED after R1 scope revision, before implementation.** The
R1 revision correctly added `pubspec.lock`, and a temporary C1 dependency solve
resolved `camera ^0.11.3` to `camera 0.11.4` without changing the `win32` major.
The dependency was then removed again: a required §5.3 / §6 metadata invariant
cannot be represented by the existing closed core contract. In particular,
`lib/core/camera/camera_frame.dart` has fields only for `timestamp`, `width`,
`height`, `format`, and `orientation`; it has no mirror or crop metadata.
The required round-trip matrix explicitly covers mirror, and §5.3 requires crop
preservation. Adding either field requires changing that core file, but it is
not in §4 `allowed_paths`. No adapter-local field can make the data available
to the existing `CameraCapture.frames` consumer without changing the contract.

The required signal was sent before this detailed audit:

```text
stopped — E05-R06 scope conflict: CameraFrame lacks required mirror/crop metadata but lib/core/camera/camera_frame.dart is outside allowed_paths
```

Required fresh Win32 evidence after reverting the temporary solve:

```text
1181:  win32:
1184:      name: win32
```

The surrounding unchanged lock entry remains `win32 6.3.0`. No production or
test source is retained. The required gate was run exactly as specified:
`tools/round-gate.sh test/features/vision/data test/core/camera`. Its format
and analyze stages were green (`Formatted 1041 files (0 changed)`; `No issues
found!`), then its first test stage stopped red because the intentionally
uncreated `test/features/vision/data` directory does not exist; consequently
the artifact did not run `test/core/camera`. No new `docs/LESSONS.md` entry was
written because that file is outside the brief's allowed paths. A further brief
revision must explicitly allow the core contract change and define how crop is
represented before implementation can continue.

## 11. Review — a független reviewer tölti ki

Tervezett review: `docs/reviews/e05-r06-android-camera-adapter-review.md`.
Merge csak exact-SHA zöld CI, §4-en belüli diff és nulla OPEN BLOCKER/MAJOR után.
