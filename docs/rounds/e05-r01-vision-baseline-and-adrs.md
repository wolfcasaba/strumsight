# E05-R01 — Vision baseline, capability audit és alapozó ADR-ek

- **Státusz:** PLANNING (pre-flight mérve 2026-08-06, base: `origin/main` @ `41a0b29`)
- **SDD-kör:** [`docs/sdd/06-epic-05-computer-vision.md`](../sdd/06-epic-05-computer-vision.md) Kör 1; §5, §7, §32, §35, §37
- **Branch:** `codex/e05-r01-vision-baseline-and-adrs`
- **Előfeltétel:** Epic 4 (**E04-R24**) lezárva
- **Brief szerzője:** Claude (batch) · **Implementáció:** Codex (Terra)

```ai-router
schema_version = 1
risk = "high"
allowed_paths = [
  "docs/baseline/epic-05-vision-start.md",
  "docs/manual-testing/vision-device-matrix.md",
  "docs/manual-testing/vision-performance-benchmark.md",
  "docs/adr/0178-vision-privacy-by-default.md",
  "docs/adr/0179-vision-capability-aware-feedback.md",
  "docs/adr/0180-vision-android-first-camera-strategy.md",
  "docs/adr/0181-vision-manual-calibration-fallback.md",
  "docs/adr/0182-vision-audio-priority-degradation.md",
  "docs/adr/0183-vision-no-raw-frame-persistence.md",
  "docs/rounds/e05-r01-vision-baseline-and-adrs.md",
]
gate_tests = [
  "test/tooling",
]
native_gate = false
```

> ⚠ **Pre-flight (KÖTELEZŐ):** `origin/main` + **E04-R24 merge**; olvasd újra
> `AGENTS.md` (§9 DSP/ML-tilalom, §12 gate), `docs/sdd/06-epic-05-*.md`
> Chapter 6, `HANDOFF.md`. **ADR-reconcile:** `ls docs/adr/ | sort | tail` —
> a 0161–0170 blokk Epic 5-re FENNTARTOTT, de az Epic 4 hátralévő körei
> (R13–R24) 0142-től fogyaszthatnak; ütközéskor **told el az egész
> 0161–0170 blokkot** és javítsd minden E05 brief §5-ét + a batch-indexet.
> PREPARED→PLANNING, brief commit az implementer indítása ELŐTT.
> **[FELOLDVA a §0.0-ban]** — a blokk 0178–0183-ra tolva a foglalóval; a fenti
> `ls`-alapú ADR-választás helyett `tools/round-slots.py reserve-adr` a forrás.

## 0. Kör-jelzés és STOP-protokoll

```bash
tools/codex-signal.sh progress "<egy sor>" ; tools/codex-signal.sh done "<egy sor>"
tools/codex-signal.sh stopped "<egy sor>" ; tools/codex-signal.sh blocked "<egy sor>"
```

Lezáró jelzés nélkül a kör bukott. Listán kívüli fájl → `stopped`.

## 0.0 Tervezési baseline és pre-flight revízió

**Pre-flight mérve 2026-08-06 (E05-R01 orchestrátor, base `origin/main` @ `41a0b29`).**

1. **ADR-blokk eltolva 0161–0166 → 0178–0183.** Az `origin/main` legmagasabb
   ADR-je a disken **0177** (`0177-ai-tutor-safety-injection-usage-evaluation-gate.md`);
   az Epic 4 R13–R24 körei a tervezett 0161–0170 Epic-5 blokk fölé, 0171–0177-re
   fogyasztottak. A race-mentes forrás a foglaló (`tools/round-slots.py
   reserve-adr --round E05-R01`, ADR 0138/pipeline-prompt §1.0.1), **nem** az
   `ls docs/adr | tail`; a foglaló hat egymást követő szabad számot adott:
   **0178, 0179, 0180, 0181, 0182, 0183**. Minden §5/§4/§9 hivatkozás és az
   `allowed_paths` erre a hat számra frissült.
2. **Az ADR-eket az orchestrátor (Claude) írta a pre-flightban** (ADR 0055,
   pipeline-prompt §2) — a hat ADR (0178–0183) már commitolva van ezen a
   kör-branchen az implementer indítása ELŐTT. **Az implementer (DeepSeek v4 Pro)
   hatóköre ezért a maradék három dokumentum:** a mért `docs/baseline/…`,
   a `docs/manual-testing/vision-device-matrix.md` és a
   `…/vision-performance-benchmark.md` sablon. Az ADR-fájlok az `allowed_paths`
   listán maradnak (a kör összdiffje része), de az implementer nem módosítja
   őket; a scope-audit az implementer base→head diffjét méri, amelyben az ADR-ek
   már nem jelennek meg.
3. **Mérés a §2 állításaihoz:** `origin/main` @ `41a0b29`. A `camera*` hiánya, a
   manifest-permission-lista, a `lib/features/` felsorolás és a KÉSZ audio/
   permission/model-asset minták a base commit ellen ellenőrizendők (az
   implementer a baseline dokumentumban a **nyers parancs-kimenettel** rögzíti).

## 1. Cél

Az Epic 5 mérhető kiindulási állapotának rögzítése és a **hat kötelező vision
architekturális döntés** megírása. **Ebben a körben production kód NEM változik**
(SDD Kör 1 utolsó feladatpontja) — a feature flagek az E05-R03-ban kerülnek be.

## 2. Jelenlegi állapot (mért, `5d082dc`)

- **Nincs kamera a repóban:** a `pubspec.yaml` `dependencies` blokkjában nincs
  `camera*` csomag; az `android/app/src/main/AndroidManifest.xml` csak
  `RECORD_AUDIO`, `INTERNET`, `POST_NOTIFICATIONS`, `RECEIVE_BOOT_COMPLETED`
  permissiont deklarál; nincs `NSCameraUsageDescription` az iOS pliste-ben.
- **Nincs `lib/core/camera/`, `lib/core/geometry/`, `lib/core/ml/`, sem
  `lib/features/vision/`.** A `lib/features/` ma 18 feature-t tartalmaz
  (`ai_tutor`, `analyze`, `auth`, `chords`, `diagnostics`, `learn`, `library`,
  `live`, `metronome`, `onboarding`, `practice`, `progress`, `settings`,
  `share`, `song_trainer`, `songs`, `streak`, `tuner`).
- **Az audio-oldali minta, amihez a camera lifecycle-nak igazodnia kell, KÉSZ:**
  `lib/core/audio/lifecycle/audio_session_coordinator.dart` (exkluzív owner,
  második ownernek `audioSessionBusy` failure, ADR 0056),
  `audio_session_lease.dart`, `audio_lifecycle_guard.dart`,
  `lib/core/platform/app_lifecycle.dart` (`isBackgroundLifecycleState`:
  paused|hidden|detached — az `inactive` szándékosan NEM).
- **Permission-minta KÉSZ:** `lib/core/platform/microphone_permission.dart` —
  `MicrophonePermissionState` (granted/denied/permanentlyDenied/restricted/
  **unavailable**), ahol a plugin-hiba SOHA nem `granted`. A camera gateway
  ennek a szerződésnek a másolata lesz (E05-R04).
- **Model-asset minta KÉSZ:** `assets/ml/model_manifest.json` +
  `ml/make_manifest.py` + `test/tooling/ml_asset_manifest_test.dart`
  (ADR 0063) — a vision modellmanifestje ezt bővíti, nem újat épít.
- **Device-mátrix precedens:** `docs/manual-testing/practice-engine-device-matrix.md`.
- **Architektúra-őr:** `tool/check_architecture.dart` + `test/core/architecture_dependency_test.dart`
  (core→features tilos, közös domain framework-mentes, cross-feature csak
  `public.dart`-on át; az allowlist CSAK szűkülhet).

## 3. Scope

**Benne:** `docs/baseline/epic-05-vision-start.md` (a §2 mérések teljes,
parancs-kimenettel alátámasztott változata), device-mátrix és
performance-benchmark **sablon**, a production/experimental metrika-lista
observability-előfeltételekkel, és a hat ADR.

**Kívül — TILOS:** bármely `lib/`, `test/`, `android/`, `ios/`, `pubspec.yaml`
módosítás; DSP-paraméter; model-asset; másik kör briefje; `docs/rag`.

## 4. Engedélyezett fájlok

| Útvonal | Állapot | Miért |
|---|---|---|
| `docs/baseline/epic-05-vision-start.md` | ÚJ | mért kiindulási állapot |
| `docs/manual-testing/vision-device-matrix.md` | ÚJ | valós eszközös mátrix sablon |
| `docs/manual-testing/vision-performance-benchmark.md` | ÚJ | benchmark sablon |
| `docs/adr/0178…0183-*.md` | ÚJ (orchestrátor írta pre-flightban) | hat alapozó döntés |
| `docs/rounds/e05-r01-*.md` | meglévő | §10 handoff |

**Tilos zóna:** minden más. Listán kívül → `stopped`.

## 5. Kötött architekturális döntések (a hat ADR tartalma)

1. **ADR 0178 — privacy by default.** A kamerakép **kizárólag a készüléken**
   dolgozódik fel. **NEM elfogadható** gyengítés: „debug buildben feltölthető",
   „opt-in esetén elmenthető a preview" — a raw frame mentése és hálózatra
   küldése *consumer kódban* tiltott, kivétel csak az explicit consentelt Lab
   capture, külön flag mögött (`visionLabCaptureEnabled`, default OFF).
2. **ADR 0179 — capability-aware feedback.** Minden insighthoz kötelező
   `requiredCapability` + `confidence` + `observability` mező. **NEM
   elfogadható:** „ha nincs adat, adjunk általános tanácsot" — hiányzó
   megfigyelhetőség esetén `notObservable`, nem gyengébb ítélet.
3. **ADR 0180 — Android-first camera strategy.** Az Epic Android-on szállít;
   az iOS út a contract szintjén készül el, futó adapter nélkül. **NEM
   elfogadható:** platform-specifikus típus a domainben.
4. **ADR 0181 — manual calibration fallback.** A gitárgeometria **production
   útja a kézi kalibráció**; bármely automatikus detektor csak experimental
   flag mögött és csak a manual fallback megtartásával létezhet.
5. **ADR 0182 — audio-priority degradation.** Ha az audio deadline romlik, a
   **vision** degradálódik, sosem az audio. **NEM elfogadható:** az audio
   feldolgozási ablak/hop módosítása vision-teljesítmény miatt (AGENTS.md §9).
6. **ADR 0183 — no-raw-frame persistence.** A persistence rétegben raw kép és
   teljes landmark-idősor alapértelmezetten nem tárolható; a
   `VisionSessionResult` aggregátum + insight + capability + model-verzió.
7. **Deviáció az SDD §8-tól, itt rögzítve:** a `lib/integrations/` könyvtár
   helyett a repó élő konvenciója marad — a Practice/Song/Tutor/Analysis
   adapterek a **fogyasztó feature `data/` rétegében** élnek, és kizárólag a
   `lib/features/vision/public.dart` API-t importálják (a `check_architecture`
   allowlist NEM bővül).
8. **Valós eszközös bizonyíték kezelése (a teljes Epicre kötelező):** amit a
   pipeline nem tud megmérni (valós kamera, FPS, thermal, soak), az a
   `docs/manual-testing/vision-device-matrix.md`-ben **PENDING** sorként
   rögzül, felelőssel és a mérendő számmal. Ez **nem merge-kapu és nem HALT-ok**
   — a merge-kapu változatlanul a `tools/round-gate.sh` + exact-SHA zöld CI;
   a valós eszközös elfogadás a merge UTÁNI termékelfogadás (HORIZON).

## 6. Acceptance criteria

- [ ] A baseline minden állítása mellett ott a **parancs és a kimenet**, amiből
      származik (pl. `rg -n "camera" pubspec.yaml` → nincs találat).
- [ ] A hat ADR mindegyike tartalmaz **Kontextus / Döntés / Következmények /
      Elutasított alternatívák** szekciót, és mindegyikben szerepel legalább egy
      explicit **„NEM elfogadható"** mondat (§5).
- [ ] A metrika-lista **kétoszlopos**: production-supported vs experimental,
      metrikánként `requiredCapability` + minimum observability előfeltétel.
- [ ] A device-mátrix sablon soronként tartalmaz: eszköz, Android verzió,
      kamera, mért érték helye, státusz (`PENDING`/`PASS`/`FAIL`), felelős.
- [ ] `git diff --stat` **egyetlen** `lib/`, `test/`, `android/`, `ios/`,
      `pubspec.yaml` fájlt sem érint.

### 6.1 Mérce-mátrix — melyik hibás kimenet vált PIROSRA

Ez a kör **docs-only**, gépi teszt nem méri a tartalmát, ezért a falszifikáció a
reviewer **eldobható próbája** (a §11-ben dokumentálva, visszaállítással):

| Próba | Elvárt eredmény |
|---|---|
| Bármelyik ADR-ből töröld a **„NEM elfogadható"** mondatot | a §6 2. cellája bizonyítatlan → review **elutasít** |
| A baseline egy állítása mellől töröld a forrás-parancsot | az állítás mérhetetlen → review **elutasít** |
| Tegyél egyetlen `lib/` vagy `test/` fájlt a diffbe | a gépi **scope-audit** (ADR 0138) `VIOLATION` → a kör `stopped` |
| A metrika-listából vedd ki a `requiredCapability` oszlopot | a §6 3. cellája PIROS (a lista nem kétoszlopos) |

## 7. Kötelező ellenőrzések

```bash
tools/round-gate.sh test/tooling
```

Külön processzek, nincs `&&`/pipe/`tail`. A CI-dispatch, PR és merge az
orchestrátoré — az implementer `gh`-t nem hív.

## 8. Implementációs sorrend

1. Mérés (`rg`/`ls`/`sed`) → baseline dokumentum a nyers kimenetekkel.
2. **A hat ADR (0178–0183) már kész** — az orchestrátor írta a pre-flightban
   (§0.0), ezen a branchen commitolva. NE módosítsd őket; a baseline és a
   metrika-lista a §5 döntéseire hivatkozzon a helyes 0178–0183 számokkal.
3. Device-mátrix + benchmark sablon.
4. Gate.

## 9. Kockázatok

- **Az ADR-ek prózává hígulnak.** Ellenszer: minden ADR-ben kötelező a „NEM
  elfogadható" mondat — erre a következő 29 kör hivatkozik.
- **Az ADR-sorszám ütközik** egy párhuzamos Epic 4 körrel (mérve 2026-08-05,
  `test_adr_numbering.py`). Ellenszer: pre-flight `ls docs/adr/ | sort | tail`,
  és a blokk eltolása, nem egyedi átszámozás.

**STOP:** ha a pre-flight production kód módosítását igényelné, vagy az
ADR-blokk ütközik — dokumentált brief-revízió, nem néma scope-tágítás.

## 10. Implementation handoff — az implementer tölti ki

_(üres)_

## 11. Review — a független reviewer tölti ki

Tervezett review: `docs/reviews/e05-r01-vision-baseline-and-adrs-review.md`.
Merge csak exact-SHA zöld CI, §4-en belüli diff és nulla OPEN BLOCKER/MAJOR után.
