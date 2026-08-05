# E05-R05 — CameraSessionCoordinator és lifecycle ownership

- **Státusz:** PREPARED (előre megírva 2026-08-05, kód olvasva: main @ `5d082dc`)
- **SDD-kör:** [`docs/sdd/06-epic-05-computer-vision.md`](../sdd/06-epic-05-computer-vision.md) Kör 5; §10, §11
- **Branch:** `codex/e05-r05-camera-session-coordinator-and-lifecycle`
- **Előfeltétel:** **E05-R03, E05-R04 merge**
- **Brief szerzője:** Claude (batch) · **Implementáció:** Codex (Terra)

```ai-router
schema_version = 1
risk = "high"
allowed_paths = [
  "lib/core/camera/camera_session_coordinator.dart",
  "lib/core/camera/camera_session_lease.dart",
  "lib/core/camera/camera_lifecycle_guard.dart",
  "lib/core/camera/camera_providers.dart",
  "test/core/camera/camera_session_coordinator_test.dart",
  "test/core/camera/camera_lifecycle_guard_test.dart",
  "docs/rounds/e05-r05-camera-session-coordinator-and-lifecycle.md",
]
gate_tests = [
  "test/core/camera",
]
native_gate = false
```

> ⚠ **Pre-flight (KÖTELEZŐ):** `origin/main` + E05-R03/R04 merge; olvasd újra
> `lib/core/audio/lifecycle/audio_session_coordinator.dart`,
> `audio_session_lease.dart`, `audio_lifecycle_guard.dart` és
> `lib/core/platform/app_lifecycle.dart` (`isBackgroundLifecycleState`).
> Nincs ÚJ ADR (ADR 0056 mintája + 0161/0165). PREPARED→PLANNING, brief commit előbb.

## 0. Kör-jelzés és STOP-protokoll

```bash
tools/codex-signal.sh progress "<egy sor>" ; tools/codex-signal.sh done "<egy sor>"
tools/codex-signal.sh stopped "<egy sor>" ; tools/codex-signal.sh blocked "<egy sor>"
```

Lezáró jelzés nélkül a kör bukott. Listán kívüli fájl → `stopped`.

## 0.0 Tervezési baseline és pre-flight revízió

**PREPARED.** Nincs előre kiosztott ADR.

## 1. Cél

Garantálni, hogy **egyszerre pontosan egy** StrumSight-modul birtokolja a
kamerát, és **minden** kilépési útvonal (stop, route-leave, app-háttér, hiba,
dispose) felszabadítsa.

## 2. Jelenlegi állapot (mért, `5d082dc`)

- `AudioSessionCoordinator` (ADR 0056): egy owner; a második **kontrollált
  `audioSessionBusy` failure**-t kap, **nem** lopja el a mikrofont; a kritikus
  szakasz (foglalt-e? → foglald) az **első `await` előtt, szinkron** fut;
  `revokeAll()` a háttérbe kerüléskor az `onRevoke` callbackkel bont.
  Ez a coordinator **pontos szerkezeti mintája**.
- `AudioSessionLease` + `AudioOwner` enum a lease/owner precedense.
- `isBackgroundLifecycleState`: `paused|hidden|detached` — az `inactive`
  szándékosan kimarad (értesítési sáv, hívásbanner nem öli a sessiont).
- Az E05-R03-ból létezik a `CameraCapture` contract és a fake.

## 3. Scope

**Benne:** `CameraSessionCoordinator` + `CameraSessionLease` + `CameraOwner`
enum (`visionSetup`, `visionPractice`, `songVision`, `labCapture`),
`CameraLifecycleGuard` (app-lifecycle → revoke), Riverpod providerek (csak
immutable állapot), strukturált lifecycle log-események **raw adat nélkül**.

**Kívül — TILOS:** production camera adapter (R06), UI, permission-logika (R04),
inference, transform (R07).

## 4. Engedélyezett fájlok

| Útvonal | Állapot | Miért |
|---|---|---|
| `lib/core/camera/camera_session_coordinator.dart` | ÚJ | exkluzív owner |
| `lib/core/camera/camera_session_lease.dart` | ÚJ | lease + owner enum |
| `lib/core/camera/camera_lifecycle_guard.dart` | ÚJ | háttér → revoke |
| `lib/core/camera/camera_providers.dart` | ÚJ | providerek (immutable state) |
| `test/core/camera/*` | ÚJ | race + lifecycle tesztek |
| `docs/rounds/e05-r05-*.md` | meglévő | §10 handoff |

**Tilos zóna:** minden más. Listán kívül → `stopped`.

## 5. Kötött architekturális döntések

1. **Egy lease egyszerre.** A második owner **kontrollált
   `cameraSessionBusy` failure**-t kap. **NEM elfogadható:** a futó owner
   elvétele („majd a friss owner fontosabb"), sem a néma sorbaállítás.
2. **A kritikus szakasz szinkron**, az első `await` **előtt** foglal — két
   egyidejű `acquire` nem láthatja szabadnak. **NEM elfogadható** olyan
   implementáció, ahol a foglalás `await` után történik.
3. **Háttérbe kerüléskor (`paused|hidden|detached`) a kamera azonnal bezár**,
   és **resume után NEM indul újra magától** — csak explicit felhasználói
   folytatásra (ADR 0161: a felhasználó tudja, mikor él a kamera).
   **NEM elfogadható:** auto-resume „kényelmi" opcióként.
4. **Dispose után nincs state-frissítés** (a repó ismert silent-no-op osztálya).
5. **A log-események mezői:** owner, ok, időbélyeg, lease-id — **tilos** bármi,
   ami képi vagy személyes tartalom (ADR 0161).
6. **Az audio és a camera lease független**: a camera coordinator **nem
   érintheti** az `AudioSessionCoordinator`-t. **NEM elfogadható** közös
   „media lease" bevezetése ebben a körben.

## 6. Acceptance criteria

- [ ] **Verseny-mátrix, cellánként külön teszt:** (a) két egyidejű `acquire` →
      egy siker + egy `cameraSessionBusy`; (b) `acquire` közbeni cancel;
      (c) `close` + `close`; (d) `close` közbeni `acquire`; (e) interruption
      alatt `close`; (f) revoke közbeni frame-esemény.
- [ ] **Lifecycle-mátrix:** `paused`, `hidden`, `detached` → revoke; `inactive`
      és `resumed` → **nem** revoke, és **nem** auto-start. Mind a **öt**
      `AppLifecycleState` külön cella (a határ két oldala is).
- [ ] Route-leave teszt fake adapterrel: a stream megszűnik, és nincs
      `setState`/provider-írás dispose után.
- [ ] **Valódi-sértés próba (§10-ben dokumentálva):** a foglalás áthelyezése
      az első `await` **mögé** → a (a) cella PIROS → visszaállítás.
- [ ] Az audio-oldali tesztek (`test/core/audio`) változatlanul zöldek.

## 7. Kötelező ellenőrzések

```bash
tools/round-gate.sh test/core/camera
```

Külön processzek, nincs `&&`/pipe/`tail`. A valós Android kamera-indikátor
ellenőrzése a device-mátrix **PENDING** sora, nem merge-kapu.

## 8. Implementációs sorrend

1. RED: verseny- és lifecycle-mátrix.
2. Lease + owner enum.
3. Coordinator (szinkron kritikus szakasz).
4. Lifecycle guard + providerek; gate.

## 9. Kockázatok

- **Az `inactive` beemelése** a háttér-állapotok közé egy értesítési sáv
  lehúzásakor ölné meg a sessiont — a mátrix ezt méri.
- **A revoke sorrendje:** előbb az owner bontása, utána a lease felszabadítása
  (az audio precedens szerint); fordítva egy pillanatra „szabad" lease mellett
  élő kamera marad.

**STOP:** production adapter behúzása, közös media-lease vagy mércegyengítés
helyett dokumentált brief-revízió.

## 10. Implementation handoff — az implementer tölti ki

_(üres)_

## 11. Review — a független reviewer tölti ki

Tervezett review: `docs/reviews/e05-r05-camera-session-coordinator-and-lifecycle-review.md`.
Merge csak exact-SHA zöld CI, §4-en belüli diff és nulla OPEN BLOCKER/MAJOR után.
