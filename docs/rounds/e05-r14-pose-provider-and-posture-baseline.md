# E05-R14 — Pose landmark provider és posture baseline

- **Státusz:** PREPARED (előre megírva 2026-08-05, kód olvasva: main @ `5d082dc`)
- **SDD-kör:** [`docs/sdd/06-epic-05-computer-vision.md`](../sdd/06-epic-05-computer-vision.md) Kör 14; §16
- **Branch:** `codex/e05-r14-pose-provider-and-posture-baseline`
- **Előfeltétel:** **E05-R09, E05-R12 merge**
- **Brief szerzője:** Claude (batch) · **Implementáció:** Codex (Terra)

```ai-router
schema_version = 1
risk = "high"
allowed_paths = [
  "lib/features/vision/domain/landmarks/pose_landmarks.dart",
  "lib/features/vision/domain/landmarks/posture_baseline.dart",
  "lib/features/vision/data/landmarks/pose_landmark_provider.dart",
  "lib/features/vision/data/landmarks/native_pose_landmark_provider.dart",
  "lib/features/vision/data/landmarks/recorded_pose_landmark_provider.dart",
  "lib/features/vision/public.dart",
  "assets/ml/model_manifest.json",
  "test/features/vision/domain/posture_baseline_test.dart",
  "test/features/vision/data/pose_landmark_provider_test.dart",
  "test/features/vision/data/pose_privacy_audit_test.dart",
  "docs/rounds/e05-r14-pose-provider-and-posture-baseline.md",
]
gate_tests = [
  "test/features/vision",
  "test/tooling",
]
native_gate = false
```

> ⚠ **Pre-flight (KÖTELEZŐ):** `origin/main` + E05-R09/R12 merge; olvasd újra az
> R12 manifest-sémáját és fail-closed init-szabályát, valamint az R09
> quality-gate-jét (a baseline csak jó quality mellett készülhet).
> Nincs ÚJ ADR (0161/0168 bővítése). PREPARED→PLANNING, brief commit előbb.

## 0. Kör-jelzés és STOP-protokoll

```bash
tools/codex-signal.sh progress "<egy sor>" ; tools/codex-signal.sh done "<egy sor>"
tools/codex-signal.sh stopped "<egy sor>" ; tools/codex-signal.sh blocked "<egy sor>"
```

Lezáró jelzés nélkül a kör bukott. Listán kívüli fájl → `stopped`.

## 0.0 Tervezési baseline és pre-flight revízió

**PREPARED.** Nincs előre kiosztott ADR.

## 1. Cél

**Adatminimalizált** felsőtest-pose pipeline (arcelemzés nélkül), alacsonyabb
cadence-en, és személyes **posture baseline**, amely kizárólag jó setup-quality
és stabil frame mellett készülhet.

## 2. Jelenlegi állapot (mért, megelőző körök)

- Az R12 kész: manifest-séma checksummal/licenccel, fail-closed init,
  rögzített-kimenetű adapter mint CI-út. A pose ugyanezt a mintát követi.
- Az R09 kész: `VisionFrameQuality` + ablakos summary — ez a baseline kapuja.
- Nincs pose-modell a repóban; a `visionPoseTrackingEnabled` flag OFF (R03).

## 3. Scope

**Benne:** `PoseLandmarks` **szűkített** ponthalmazzal, `PoseLandmarkProvider`
+ production és rögzített adapter, cadence-szabályozás (a kéz-modellnél
ritkábban), visibility gate, `PostureBaseline` collector ablak, posture quality
és drift observation modellek, manifest-bejegyzés, privacy-audit teszt.

**Kívül — TILOS:** posture metrikák és safety policy (R20), fusion (R22),
UI, arcfelismerés bármely formája, DSP.

## 4. Engedélyezett fájlok

| Útvonal | Állapot | Miért |
|---|---|---|
| `.../domain/landmarks/pose_landmarks.dart` | ÚJ | szűkített pose modell |
| `.../domain/landmarks/posture_baseline.dart` | ÚJ | baseline collector |
| `.../data/landmarks/pose_landmark_provider.dart` | ÚJ | interfész |
| `.../data/landmarks/native_pose_landmark_provider.dart` | ÚJ | production adapter |
| `.../data/landmarks/recorded_pose_landmark_provider.dart` | ÚJ | fixture-adapter |
| `lib/features/vision/public.dart` | meglévő | additív export |
| `assets/ml/model_manifest.json` | meglévő | **additív** pose bejegyzés |
| `test/features/vision/*` | ÚJ | mapping + baseline + privacy tesztek |
| `docs/rounds/e05-r14-*.md` | meglévő | §10 handoff |

**Tilos zóna:** minden más; audio modellfájlok; `docs/rag`. Listán kívül → `stopped`.

## 5. Kötött architekturális döntések

1. **Adatminimalizálás (ADR 0161):** kizárólag váll, könyök, csukló, csípő és
   **legfeljebb egy** semleges fej-referenciapont (pl. nyakpont) tárolható.
   **NEM elfogadható:** szem/orr/száj/fül landmark tárolása, logolása vagy
   továbbadása — akkor sem, ha a modell kiadja. A modell kimenetét a mapping
   **eldobja**, nem a fogyasztó.
2. **Nincs arcfelismerés, nincs identitás-jellemző** — sem számított
   embedding, sem arc-crop. **NEM elfogadható** „debug célú" kivétel.
3. **A pose külön leállítható** (`visionPoseTrackingEnabled`), és a kikapcsolása
   nem befolyásolja a kéz-pipeline-t.
4. **Alacsonyabb cadence:** a pose futási gyakorisága konfigurált, és
   alapértelmezetten a kéz-modell **töredéke**; a cadence a device tier
   szerint tovább csökkenthető (R29).
5. **Baseline csak valid körülményből:** jó quality (R09) + stabil frame +
   minimum látható időtartam. **NEM elfogadható:** részleges ablakból számolt
   baseline „hogy legyen valami" — ilyenkor nincs baseline, és a későbbi
   posture-observation `notObservable`.
6. **Fail-closed manifest** az R12 szabálya szerint; asset hiányában
   capability `unavailable`, `status = "deferred"` bejegyzéssel.

## 6. Acceptance criteria

- [ ] **Mapping-teszt:** a fixture provider-kimenet arc-pontjai a
      `PoseLandmarks`-ban **nem jelennek meg**; a megtartott pontok listája
      pontosan az engedélyezett halmaz.
- [ ] **Privacy-audit teszt (a kör kulcsbizonyítéka):** a `PoseLandmarks`
      szerializált alakja és a logolt mezők egy **rögzített, elvárt
      kulcshalmazzal** egyeznek; új mező csak a snapshot frissítésével kerülhet be.
- [ ] **Valódi-sértés próba (§10):** egy arc-landmark ideiglenes átengedése a
      mappingen → a privacy-audit teszt PIROS → visszaállítás.
- [ ] **Baseline-mátrix:** quality a küszöb **alatt / rajta / fölött** × látható
      időtartam a minimum **alatt / rajta / fölött** — a baseline csak a
      „rajta vagy fölötte" cellákban jön létre; a többiben `notObservable`.
- [ ] **Cadence-teszt:** N kéz-frame-re a pose-hívások száma a konfigurált
      arány szerinti (számmal), és a cadence állítása azonnal érvényesül.
- [ ] **Kikapcsolás-teszt:** `visionPoseTrackingEnabled = false` → a pose
      provider **nem példányosul**, a kéz-pipeline változatlan.

## 7. Kötelező ellenőrzések

```bash
tools/round-gate.sh test/features/vision test/tooling
```

Külön processzek, nincs `&&`/pipe/`tail`. A valós eszközös pose-latency és a
rövid thermal-mérés a device-mátrix **PENDING** sora.

## 8. Implementációs sorrend

1. RED: privacy-audit + mapping + baseline-mátrix.
2. `PoseLandmarks` (szűkített) + mapping.
3. Provider-ek + cadence.
4. Baseline collector + manifest; gate.

## 9. Kockázatok

- **A modell arc-pontokat is ad**; ha a mapping „kényelemből" mindent átenged,
  a privacy-ígéret sérül — a privacy-audit teszt az egyetlen gépi őr.
- **A baseline túl szigorú** lesz, és sosem jön létre valós használatban; ezt
  a device-mátrix PENDING mérése deríti ki, a küszöb konfigurált marad.

**STOP:** arc-landmark tárolása, közös kéz/pose cadence vagy a baseline-kapu
lazítása helyett dokumentált brief-revízió.

## 10. Implementation handoff — az implementer tölti ki

_(üres)_

## 11. Review — a független reviewer tölti ki

Tervezett review: `docs/reviews/e05-r14-pose-provider-and-posture-baseline-review.md`.
Merge csak exact-SHA zöld CI, §4-en belüli diff és nulla OPEN BLOCKER/MAJOR után.

> **Reviewer figyelem:** ez a kör privacy-kritikus (ADR 0161) — a
> `security-reviewer` ágens bevonása KÖTELEZŐ (adatminimalizálás, logolt mezők).
