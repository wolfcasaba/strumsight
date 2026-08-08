# E05-R30 — Dataset, evaluation, minőségi kapuk és Epic 5 lezárás (ZÁRÓ)

- **Státusz:** PLANNING (előre megírva 2026-08-05, kód olvasva: main @ `5d082dc`;
  pre-flight 2026-08-08: minden mért állítás — 12 elemű architektúra-allowlist
  mind `analyze → live`, 11 vision flag `false` a `FeatureFlags.forEnvironment`
  EGYETLEN factory-jában (nincs dart-define override), az öt ÚJ fájl
  ténylegesen hiányzik, a hat meglévő fájl ténylegesen létezik, az SDD §32/35/
  36/39/40 szakaszok léteznek — a kódnak megfelelőnek bizonyult; §0.0 revízió
  nem szükséges, ÚJ ADR nem szükséges, a záró-kör waiver [ADR 0087](../adr/0087-autonomous-round-pipeline.md)
  §7 + [ADR 0112](../adr/0112-self-healing-pipeline.md) alapján érvényes)
- **SDD-kör:** [`docs/sdd/06-epic-05-computer-vision.md`](../sdd/06-epic-05-computer-vision.md) Kör 30; §32, §35, §36, §39, §40
- **Branch:** `codex/e05-r30-dataset-evaluation-and-epic-closure`
- **Előfeltétel:** **E05-R01…R29 MIND merge-elve**
- **Brief szerzője:** Claude (batch) · **Implementáció:** Codex (Terra)

```ai-router
schema_version = 1
risk = "high"
allowed_paths = [
  "tool/check_architecture.dart",
  "ml/vision/evaluate_vision_metrics.py",
  "ml/vision/dataset_manifest.md",
  "docs/sdd/epic-05-completion-report.md",
  "docs/runbooks/vision-rollout.md",
  "docs/manual-testing/vision-device-matrix.md",
  "docs/manual-testing/vision-performance-benchmark.md",
  "README.md",
  "test/core/architecture_dependency_test.dart",
  "test/tooling/vision_model_integrity_test.dart",
  "test/features/vision/vision_offline_regression_test.dart",
  "docs/rounds/e05-r30-dataset-evaluation-and-epic-closure.md",
]
gate_tests = [
  "test/features/vision",
  "test/core",
  "test/tooling",
]
native_gate = false
```

> ⚠ **Pre-flight (KÖTELEZŐ):** `origin/main` + **mind a 29 megelőző kör merge**;
> olvasd újra a `tool/check_architecture.dart` allowlistjét (CSAK szűkülhet) és
> a `docs/manual-testing/vision-device-matrix.md` összes PENDING sorát.
> **Nincs ÚJ ADR** (regressziós/lezáró kör). PREPARED→PLANNING, brief commit előbb.

## 0. Kör-jelzés és STOP-protokoll

```bash
tools/codex-signal.sh progress "<egy sor>" ; tools/codex-signal.sh done "<egy sor>"
tools/codex-signal.sh stopped "<egy sor>" ; tools/codex-signal.sh blocked "<egy sor>"
```

Lezáró jelzés nélkül a kör bukott. Listán kívüli fájl → `stopped`.

## 0.0 Tervezési baseline és pre-flight revízió

**PLANNING (pre-flight lezárva 2026-08-08).** Nincs előre kiosztott ADR. **Záró-kör
waiver** (lásd §5.7). A két kötelező mérési szabály (elérhetetlen cél-státusz,
erőforrás-tulajdonlás) és a §2 összes numerikus/fájl-állítása grep-elve — nulla
eltérés a kódtól, revízió nem szükséges:

- `tool/check_architecture.dart` allowlist: pontosan **12** bejegyzés, mind
  `analyze → live` (grep `docs/rounds/...§2` állítása szó szerint egyezik).
- Vision flag-ek: pontosan **11** (`visionEnabled`, `visionSetupEnabled`,
  `visionHandTrackingEnabled`, `visionPoseTrackingEnabled`,
  `visionGuitarGeometryEnabled`, `visionPracticeIntegrationEnabled`,
  `visionSongIntegrationEnabled`, `visionTutorIntegrationEnabled`,
  `visionAnalysisIntegrationEnabled`, `visionExperimentalFineFretEnabled`,
  `visionLabCaptureEnabled`), mind `false` az EGYETLEN
  `FeatureFlags.forEnvironment` factoryban, dart-define override nélkül — az
  „elérhetetlen cél-státusz" mérés input-oldala: nincs olyan bemenet, ami
  igazra tudná állítani ezeket.
- Az öt ÚJ fájl (`ml/vision/evaluate_vision_metrics.py`,
  `docs/sdd/epic-05-completion-report.md`, `docs/runbooks/vision-rollout.md`,
  `test/tooling/vision_model_integrity_test.dart`,
  `test/features/vision/vision_offline_regression_test.dart`) ténylegesen
  hiányzik; a hat meglévőként hivatkozott fájl ténylegesen létezik.
- SDD §32.1–32.5 (incl. §32.3 False feedback gate), §35.1–35.6, §36.1–36.4,
  §39, §40 mind léteznek `docs/sdd/06-epic-05-computer-vision.md`-ben.
- Erőforrás-tulajdonlás: a kör nem rendel lease/lock/handle/subscription
  erőforrást egyetlen réteghez sem (teszt/doksi/harness-only diff) — a
  szabály nem alkalmazható.

## 1. Cél

A Computer Vision feature minőségi kapuinak, model-integritásának és
dokumentációjának lezárása, valamint az Epic 5 completion report elkészítése —
minden nem validált képesség **flag-off** állapotban.

## 2. Jelenlegi állapot (a kör indulásakor mérendő)

- Az R01–R29 leszállította a teljes vision-vertikumot; az összes vision flag
  **OFF** (E05-R03), és a valós eszközös bizonyítékok a device-mátrixban
  **PENDING** sorokként gyűltek.
- `tool/check_architecture.dart` allowlistje ma 12 örökölt kivételt tartalmaz
  (mind `analyze → live` DSP-import); a vision **nem** adott hozzá egyet sem.
- `test/tooling/ml_asset_manifest_test.dart` őrzi az asset-manifestet (ADR 0063).

## 3. Scope

**Benne:** vision dataset manifest + consent-dokumentáció véglegesítése,
evaluation harness (hand tracking, quality, geometry, metrika, **false feedback**
mérésére, `--self-test`-tel), model-integritás teszt (checksum + output schema)
a `test/` oldalon, **architektúra-guard bővítés** (raw frame persistence és
cross-feature belső import ellen), offline/vision-off regressziós teszt,
`docs/sdd/epic-05-completion-report.md`, rollout-runbook, README/privacy leírás
frissítése, és a production vs experimental képesség-lista véglegesítése.

**Kívül — TILOS (H-GATEGUARD, ADR 0112/0138):** `.github/workflows/*` és
`tool/ci/*` — a **CI-oldali** vision model-gate hozzáadása a mércét módosítja,
azt csak **ember által engedélyezett governance-kör** végezheti (`GOV-xx`).
Ez a kör a gate **teszt-oldali** megfelelőjét szállítja (`test/tooling/`), és a
completion report **nevesíti a hátralévő CI-munkát**. Szintén kívül: bármely
`lib/` production fájl, új feature, flag ON-ra állítása.

## 4. Engedélyezett fájlok

| Útvonal | Állapot | Miért |
|---|---|---|
| `tool/check_architecture.dart` | meglévő | **új szabály** (raw frame / belső import) |
| `ml/vision/evaluate_vision_metrics.py` | ÚJ | evaluation harness |
| `ml/vision/dataset_manifest.md` | R17-ből | véglegesítés |
| `docs/sdd/epic-05-completion-report.md` | ÚJ | zárójelentés |
| `docs/runbooks/vision-rollout.md` | ÚJ | rollout/rollback |
| `docs/manual-testing/vision-*.md` | meglévő | PENDING sorok összesítése |
| `README.md` | meglévő | vision + privacy leírás |
| `test/core/architecture_dependency_test.dart` | meglévő | az új szabály tesztje |
| `test/tooling/vision_model_integrity_test.dart` | ÚJ | checksum + schema kapu |
| `test/features/vision/vision_offline_regression_test.dart` | ÚJ | vision-off paritás |
| `docs/rounds/e05-r30-*.md` | meglévő | §10 handoff |

**Tilos zóna:** `.github/`, `tool/ci/`, `lib/`, `tools/round-gate.sh`,
`.claude/hooks/`, `docs/rag`. Listán kívül → `stopped`.

## 5. Kötött architekturális döntések

1. **Architektúra-guard bővítés:** új, gépi szabály (a) raw frame/pixel típus
   **nem** kerülhet persistence- vagy provider-state-be, (b) más feature **nem**
   importálhat `lib/features/vision/` belsőt (csak `public.dart`).
   Az allowlist **nem bővülhet** — ha egy meglévő import sértene, az
   **megállás és jelentés**, nem allowlist-bejegyzés.
2. **False feedback gate:** a harness mérje a hamis negatív cue arányát a
   rögzített fixture-készleten; a **production-supported** metrikákra a
   dokumentált küszöb alatt kell lennie. **NEM elfogadható:** a küszöb
   utólagos felemelése a mért értékhez — ilyenkor a metrika **experimental**
   besorolást kap (ez a megengedett kimenet).
3. **Vision-off paritás:** minden vision flag OFF mellett a teljes app
   viselkedése **bitre azonos** az Epic 5 előtti állapottal a lefedett
   útvonalakon (Practice audio score, Song Trainer timing, Analysis, Tutor).
4. **Minden vision flag OFF marad merge-kor.** A GA-flip **pipeline-on kívüli**,
   külön user/termék döntés. **NEM elfogadható:** bármely flag ON-ra állítása
   ebben a körben.
5. **A rollout-létra kötött:** internal → Lab → opt-in beta → limited
   production → GA, metrikánkénti capability-gate-tel; a runbook tartalmazza a
   **rollback**-et (flag OFF + előző asset visszaállítás).
6. **A valós eszközös bizonyíték a completion reportban tételes:** minden
   PENDING sor felsorolva, eszközzel és a mérendő számmal. A report **nem
   állíthat** nem mért eredményt (a mért hibaosztály: handoffba írt valótlan
   állítás).
7. **Záró-kör waiver:** az ADR 0087 §7 kézi epic-záró indítása **nem** él —
   a brief pre-decidálja a rollout/flag/ADR kérdéseket, így a pre-flightnak
   nincs eldöntetlen emberi kérdése. **Változatlan marad** az automata
   független Claude-review (ADR 0055), az exact-SHA zöld CI és a valós eszközös
   HORIZON-elfogadás (ez utóbbi merge UTÁNI termékelfogadás).

## 6. Acceptance criteria

- [ ] **Architektúra-guard valódi-sértés próba (§10):** egy ideiglenes, tiltott
      import (`practice` → `vision` belső fájl) → `test/core/architecture_dependency_test.dart`
      PIROS → visszaállítás. Ugyanez a raw-frame szabályra.
- [ ] **Model-integritás teszt:** rossz checksum / eltérő output schema / hiányzó
      licenc → mindhárom PIROS-t ad; a jó eset zöld.
- [ ] **Vision-off paritás fixture:** Practice audio score, Song Trainer
      timing, Analysis és Tutor kimenet **bitre azonos** flag-OFF mellett.
- [ ] **Evaluation harness:** `--self-test` lefut és zöld; adat nélkül
      `NO_DATA`; a false-feedback metrika szintetikus fixture-en számolt.
- [ ] **Completion report** tartalmazza: teljesített DoD-pontok, a
      **production-supported vs experimental** végleges lista, minden PENDING
      valós eszközös mérés tételesen, és a **hátralévő CI-munka** (workflow-oldali
      model-gate) nevesítve mint governance-kör.
- [ ] **Flag-audit:** mind a 11 vision flag `false` minden környezetben (teszt).
- [ ] `git diff --stat` **nem** tartalmaz `.github/`, `tool/ci/`, `lib/` fájlt.

### 6.1 Küszöb-mátrix — a false-feedback kapu három cellája

A §2 2. pontja („False feedback gate") dokumentált küszöböt ír elő a
production-supported metrikákra. A harness mind a három cellát mérje:

| Cella | Mért hamis-negatív arány | Elvárt kimenet |
|---|---|---|
| alatt | küszöb − 1 lépés | `PASS` — a metrika **production-supported** marad |
| rajta | pontosan a küszöb | `PASS` (a határ **inkluzív**) |
| fölött | küszöb + 1 lépés | a metrika **`experimental`** besorolást kap |

**A küszöb utólagos felemelése a mért értékhez tiltott** (§2 2. pont): a
megengedett kimenet az `experimental` átsorolás.

## 7. Kötelező ellenőrzések

```bash
tools/round-gate.sh test/features/vision test/core test/tooling
```

Külön processzek, nincs `&&`/pipe/`tail`. A **teljes** Flutter suite, a
property-gate és az APK a CI-ben fut (orchestrátor exact-SHA dispatch); a
backend regresszió akkor, ha a diff érinti (itt nem érinti).

## 8. Implementációs sorrend

1. Architektúra-guard szabály + valódi-sértés próba.
2. Model-integritás teszt.
3. Vision-off paritás fixture.
4. Evaluation harness + dataset manifest véglegesítés.
5. Completion report + runbook + README; gate.

## 9. Kockázatok

- **A guard-bővítés meglévő importot sért** → a helyes válasz a megállás és
  jelentés, nem az allowlist bővítése (az allowlist csak szűkülhet).
- **A CI-oldali model-gate hiánya** miatt a completion report „félkésznek"
  tűnhet; ezért nevesítve átadjuk governance-körnek — ez tudatos határ,
  nem elfelejtett munka.
- **A report valótlan állítást tesz** a nem mért eszközös eredményekről; a §5.6
  tételes PENDING-listája ezt zárja ki.

**STOP:** workflow/`tool/ci` érintése, allowlist-bővítés, flag ON vagy nem mért
eredmény állítása helyett dokumentált brief-revízió.

## 10. Implementation handoff — az implementer tölti ki

_(üres)_

## 11. Review — a független reviewer tölti ki

Tervezett review: `docs/reviews/e05-r30-dataset-evaluation-and-epic-closure-review.md`.
Merge csak exact-SHA zöld CI, §4-en belüli diff és nulla OPEN BLOCKER/MAJOR után.
