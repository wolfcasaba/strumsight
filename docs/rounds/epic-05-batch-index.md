# Epic 5 (Computer Vision) — batch előkészítési index

- **Státusz:** PREPARED (batch előre megírva **2026-08-05**, kód olvasva: `main` @ `5d082dc`)
- **SDD-forrás:** [`docs/sdd/06-epic-05-computer-vision.md`](../sdd/06-epic-05-computer-vision.md) (Chapter 6, Kör 1–30)
- **Előfeltétel-epic:** Epic 4 (AI Guitar Teacher) lezárva — **E04-R24 merge**.
  A batch készítésekor az E04-R12 volt az utolsó merge-elt kör; az E04-R13…R24
  `pending`.
- **User-döntés (2026-08-05):** „kezdd el az Epic 5 előkészítését, tedd be a
  pipeline-ba, hogy amikor az Epic 4-gyel végez, induljon automatikusan az
  Epic 5 is." → a 30 queue-sor **`pending`** státusszal, közvetlenül az
  E04-R24 után; a lánc **nem áll meg az epic-határon**.
- **Záró-kör waiver:** az **E05-R30** NEM kap ADR 0087 §7 szerinti kézi
  epic-záró indítást (az Epic 4 E04-R24 precedense szerint) — a briefje
  pre-decidálja a rollout/flag/ADR kérdéseket. Változatlan marad az automata
  független Claude-review (ADR 0055) és az exact-SHA zöld CI.

> ⚠ **Ez az index nem futtatható artefaktum.** A körök briefjei az
> `e05-rNN-*.md` fájlok. Minden brief `PREPARED`; az élesedéskor a kötelező
> ⚠ pre-flight méri újra a driftet, és állítja `PLANNING`-re a kör-branchen.

---

## 1. Az Epic 5 három szerkezeti különbsége (KÖTELEZŐ olvasmány)

Az Epic 1–4 tisztán szoftveres volt. Az Epic 5 nem — ezért a batch három
szabályt épít **minden** briefbe:

**(a) Valós eszközös bizonyíték ≠ merge-kapu.** Ezen a boxon nincs Android SDK
és nincs kamerás eszköz; az SDD több köre (Kör 2, 6, 12, 14, 21, 29, 30) valós
mérést ír elő. A pipeline ezeket **nem tudja** elvégezni, és egy teljesíthetetlen
acceptance-pont a HALT → önjavítás → emberi eszkaláció útra vinné a láncot.
Feloldás (E05-R01 §5.8, minden brief örökli): a nem mérhető bizonyíték a
`docs/manual-testing/vision-device-matrix.md`-be kerül **PENDING** sorként,
felelőssel és a mérendő számmal. **Merge-kapu marad:** `tools/round-gate.sh` +
exact-SHA zöld CI (a natív fordítás bizonyítéka a `build-apk` futás). A valós
eszközös elfogadás a **merge UTÁNI** termékelfogadás (HORIZON, CLAUDE.md).

**(b) Döntési körök mérés nélkül is zárnak.** A Kör 2 (camera stack) és a
Kör 17 (automatikus detektor) az SDD-ben mérés-vezérelt döntés. A briefek
**feltételes ADR-t** írnak elő: kimondott default döntés + **számszerű
megdöntési küszöb** + futtatható mérési runbook, amit valós eszközön az ember
(vagy egy későbbi eszközös kör) hajt végre. Így a kör determinisztikusan zár,
és a döntés visszakövethető, nem „majd kiderül".

**(c) H-GATEGUARD határ a záró körben.** Az SDD Kör 30 CI-oldali model-gate-et
kér, de a `.github/workflows/*` és a `tool/ci/*` a mércét jelenti, amit egy
önmagát mérő session nem írhat át (ADR 0112/0138, `.claude/hooks/protect_factory_files.py`).
Az **E05-R30** ezért a gate **teszt-oldali** megfelelőjét szállítja
(`test/tooling/vision_model_integrity_test.dart` + architektúra-guard bővítés),
és a completion report **nevesíti** a hátralévő CI-munkát → **ember által
engedélyezett governance-kör (`GOV-xx`)**. Ez tudatos határ, nem hiány.

---

## 2. Kör-térkép (30 kör)

| Kör | Cím | Motor | Előre kiosztott ADR | Előfeltétel (Epic 5-ön belül) | Brief |
|---|---|---|---|---|---|
| E05-R01 | Vision baseline, capability audit, ADR-ek | codex | 0161–0166 | — (Epic 4 zárva) | `e05-r01-vision-baseline-and-adrs.md` |
| E05-R02 | Camera technology döntési kapu + runbook | codex | 0167 | R01 | `e05-r02-camera-technology-decision.md` |
| E05-R03 | Core camera contract, fake, vision flagek | codex | — | R01, R02 | `e05-r03-core-camera-contract-and-fake.md` |
| E05-R04 | Camera permission gateway + platform deklarációk | codex | — | R03 | `e05-r04-camera-permission-and-platform-declarations.md` |
| E05-R05 | CameraSessionCoordinator + lifecycle ownership | codex | — | R03, R04 | `e05-r05-camera-session-coordinator-and-lifecycle.md` |
| E05-R06 | Android camera production adapter | codex | — | R02, R03, R05 | `e05-r06-android-camera-adapter.md` |
| E05-R07 | Frame transform + overlay koordinátarendszer | codex | — | R03, R06 | `e05-r07-frame-transform-and-overlay-coordinates.md` |
| E05-R08 | Vision setup wizard + permission UX | **minimax** | — | R04, R05, R06, R07 | `e05-r08-vision-setup-wizard.md` |
| E05-R09 | Frame quality assessor | codex | — | R06, R07, R08 | `e05-r09-frame-quality-assessor.md` |
| E05-R10 | Calibration domain + verziózott tárolás | codex | — | R08 | `e05-r10-calibration-domain-and-store.md` |
| E05-R11 | Manual guitar geometry calibration UI | **minimax** | — | R07, R08, R10 | `e05-r11-manual-guitar-geometry-calibration-ui.md` |
| E05-R12 | Hand landmark provider + model manifest | codex | 0168 | R06, R07 | `e05-r12-hand-landmark-provider-and-model-manifest.md` |
| E05-R13 | Hand track assignment + temporal smoothing | codex | — | R12 | `e05-r13-hand-track-assignment-and-smoothing.md` |
| E05-R14 | Pose provider + posture baseline | codex | — | R09, R12 | `e05-r14-pose-provider-and-posture-baseline.md` |
| E05-R15 | Guitar coordinate system + homography | codex | — | R07, R10, R13 | `e05-r15-guitar-coordinates-and-homography.md` |
| E05-R16 | Geometry tracking + calibration loss | codex | — | R10, R15 | `e05-r16-geometry-tracking-and-calibration-loss.md` |
| E05-R17 | Automatikus guitar detector döntési kör | codex | 0169 | R11, R16 | `e05-r17-auto-guitar-detector-decision.md` |
| E05-R18 | Bal kéz (fretting) metric engine | codex | — | R13, R15, R16 | `e05-r18-fretting-hand-metric-engine.md` |
| E05-R19 | Jobb kéz (picking) stroke metric engine | codex | — | R13, R15, R18 | `e05-r19-picking-hand-stroke-metrics.md` |
| E05-R20 | Posture metric engine + safety policy | codex | — | R14, R18 | `e05-r20-posture-metrics-and-safety-policy.md` |
| E05-R21 | Audio–vision clock mapping + latency kalibráció | codex | 0170 | R06, R12, R19 | `e05-r21-audio-vision-clock-mapping.md` |
| E05-R22 | Observation fusion + evidence engine | codex | — | R09, R16, R18, R19, R20, R21 | `e05-r22-observation-fusion-and-evidence.md` |
| E05-R23 | Feedback policy + realtime cue budget | codex | — | R20, R22 | `e05-r23-feedback-policy-and-cue-budget.md` |
| E05-R24 | Vision session controller + realtime overlay | codex | — | R05, R08, R11, R16, R22, R23 | `e05-r24-vision-session-controller-and-overlay.md` |
| E05-R25 | Practice Engine vision integráció | codex | — | R22, R23, R24 | `e05-r25-practice-vision-integration.md` |
| E05-R26 | Song Trainer vision integráció | codex | — | R24, R25 | `e05-r26-song-trainer-vision-integration.md` |
| E05-R27 | AI Tutor + Analysis evidence adapterek | codex | — | R22, R23, R24 | `e05-r27-tutor-analysis-vision-adapters.md` |
| E05-R28 | Persistence, privacy control, törlés | codex | — | R10, R22, R24 | `e05-r28-vision-persistence-privacy-and-deletion.md` |
| E05-R29 | Device tier, performance, thermal hardening | codex | — | R24, R26 | `e05-r29-device-tier-performance-thermal.md` |
| E05-R30 | Dataset, evaluation, minőségi kapuk, Epic zárás (ZÁRÓ) | codex | — | MIND (R01–R29) | `e05-r30-dataset-evaluation-and-epic-closure.md` |

---

## 3. ADR-kiosztás (PROVIZÓRIKUS — pre-flightban reconcile KÖTELEZŐ)

A batch készítésekor a legmagasabb ADR **0141**. A **0142–0160** blokk az Epic 4
hátralévő 12 körének (E04-R13…R24) és a governance-munkának **fenntartott** —
Epic 5 ezért **0161-től** oszt:

| ADR | Kör | Tárgy |
|---|---|---|
| 0161 | R01 | Vision privacy by default (nincs raw frame feltöltés/mentés consumer úton) |
| 0162 | R01 | Capability-aware feedback (requiredCapability + confidence + observability) |
| 0163 | R01 | Android-first camera strategy (nincs platform-típus a domainben) |
| 0164 | R01 | Manual calibration fallback (a production geometria-út) |
| 0165 | R01 | Audio-priority degradation (romló deadline → a vision enged) |
| 0166 | R01 | No-raw-frame persistence (aggregátum + insight + capability) |
| 0167 | R02 | Camera capture stack (feltételes döntés + megdöntési küszöbök) |
| 0168 | R12 | Hand landmark inference stack + model-asset licenc/integritás |
| 0169 | R17 | Automatikus guitar geometry detection (default: experimental-only) |
| 0170 | R21 | Audio–vision szinkron-szerződés (monotonic óra, sync bucketek) |

**Reconciliation-szabály (minden brief ⚠ pre-flightjában):** indítás előtt
`ls docs/adr/ | sort | tail` a valós next-free számhoz; ha az Epic 4 hátralévő
körei vagy egy párhuzamos governance-munka a 0160 fölé fogyasztott,
**told el az egész 0161–0170 blokkot**, és javítsd az érintett briefek §5-ét
és ezt a táblát. (Mért ütközés 2026-08-05: két párhuzamos ág foglalta a 0139-et
— `tools/tests/test_adr_numbering.py` azóta gépi kapu.)

---

## 4. Motor-besorolás (ADR 0069 mért szabály, gépileg ellenőrizve)

A `pipeline-queue.tsv` szabálya (`test_open_rounds_follow_the_measured_engine_rule`):
`risk == "normal"` → minimax; `risk == "high"` ÉS UI/ARB > domain+app+data →
minimax; egyébként → codex.

Az Epic 5 túlnyomó része core/domain/data, geometria-, privacy- vagy
invariáns-kritikus (kamera-lifecycle, permission, homográfia, confidence,
safety-claim, adatminimalizálás) → **codex (Terra)**. Kizárólag a két
UI-dominált kör — **R08** (setup wizard) és **R11** (kalibrációs editor) —
megy **minimax**-ra. A batch minden briefjén lefuttatva a szabály
(2026-08-05): mind a 30 sor egyezik a brief mért mezőivel.

---

## 5. Queue-sorok (a `pipeline-queue.tsv` VÉGÉN, E04-R24 után)

`pending` státusszal élesítve — a lánc az Epic 4 után **megállás nélkül**
folytatja az Epic 5-tel (user-döntés 2026-08-05).

Leállítás, ha kell: a cron-sor kivétele (`crontab -e`) — a `--halt` NEM erre
való (ADR 0112 szerint önjavító kört indít). Epic-határon való megállításhoz a
30 sor `pending` → `hold` átírása elég:
`sed -i -E 's/^(E05-R[0-9]+\t.*\t)pending$/\1hold/' docs/execution/pipeline-queue.tsv`

---

## 6. Globális pre-flight emlékeztetők (minden Epic 5 brief örökli)

- **Greenfield feature:** ma nincs `lib/core/camera/`, `lib/core/geometry/`,
  `lib/core/ml/`, `lib/features/vision/`, és nincs camera függőség/permission.
- **Az audio-oldali minta a másolandó szerződés:** `AudioSessionCoordinator`
  (ADR 0056, exkluzív lease + kontrollált busy failure),
  `MicrophonePermissionGateway` (a plugin-hiba SOHA nem `granted`),
  `isBackgroundLifecycleState` (paused|hidden|detached, az `inactive` NEM).
- **Flag helye:** `lib/app/config/feature_flags.dart`; az Epic 5 additívan
  **11** vision flaget ad, mind **default OFF minden környezetben**,
  dart-define override nélkül (a `songTrainerV2Enabled` precedense szerint).
- **Storage:** `lib/core/storage/storage_keys.dart` `ss.` névtér + verziózott
  envelope + record-szintű karantén; kulcs helyben SOHA nem írható át.
- **Model-asset:** `assets/ml/model_manifest.json` + `ml/make_manifest.py` +
  `test/tooling/ml_asset_manifest_test.dart` (ADR 0063) — a vision manifest
  ezt **bővíti**; checksum + licenc + output schema kötelező (AGENTS.md §9).
- **Domain purity + cross-feature határ:** `tool/check_architecture.dart`;
  a `lib/features/*/domain/` framework-mentes, a cross-feature import csak
  `public.dart`-on át, és az **allowlist csak szűkülhet**.
- **SDD-deviáció (E05-R01 §5.7):** a SDD §8 `lib/integrations/` könyvtára
  helyett az adapterek a **fogyasztó feature** `data/`/`services/` rétegében
  élnek, és a `vision/public.dart`-ot importálják.
- **DSP-tilalom (AGENTS.md §9):** vision-teljesítmény miatt DSP-paraméter,
  audio-ütemezés vagy audio-modell **nem** módosítható.
- **Gate:** `tools/round-gate.sh <érintett test-útvonalak>` — egyetlen lokális
  záró gate, külön processz format/analyze/test/architecture, nincs `&&`/pipe;
  full suite + property + APK CI = orchestrátor exact-SHA dispatch.
- **`native_gate = false` minden körben:** ezen a boxon nincs Android SDK; a
  natív fordítás bizonyítéka a CI `build-apk.yml` futása.
