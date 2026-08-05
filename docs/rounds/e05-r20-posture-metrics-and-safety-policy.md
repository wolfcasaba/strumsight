# E05-R20 — Posture metric engine és safety policy

- **Státusz:** PREPARED (előre megírva 2026-08-05, kód olvasva: main @ `5d082dc`)
- **SDD-kör:** [`docs/sdd/06-epic-05-computer-vision.md`](../sdd/06-epic-05-computer-vision.md) Kör 20; §21
- **Branch:** `codex/e05-r20-posture-metrics-and-safety-policy`
- **Előfeltétel:** **E05-R14, E05-R18 merge**
- **Brief szerzője:** Claude (batch) · **Implementáció:** Codex (Terra)

```ai-router
schema_version = 1
risk = "high"
allowed_paths = [
  "lib/features/vision/domain/metrics/posture_metrics.dart",
  "lib/features/vision/domain/metrics/posture_metric_engine.dart",
  "lib/features/vision/domain/safety/vision_safety_policy.dart",
  "lib/features/vision/domain/safety/safety_claim_guard.dart",
  "lib/features/vision/public.dart",
  "test/features/vision/domain/posture_metric_engine_test.dart",
  "test/features/vision/domain/safety_claim_guard_test.dart",
  "test/fixtures/vision/posture",
  "docs/rounds/e05-r20-posture-metrics-and-safety-policy.md",
]
gate_tests = [
  "test/features/vision",
]
native_gate = false
```

> ⚠ **Pre-flight (KÖTELEZŐ):** `origin/main` + E05-R14/R18 merge; olvasd újra az
> R14 `PostureBaseline` kapuját és az **AI Tutor safety policy** mai alakját
> (`lib/features/ai_tutor/` — Epic 4, ADR 0132/0141): a vision safety-nyelvezet
> ezzel **összehangolt**, nem versengő. Nincs ÚJ ADR (0162 bővítése).
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

**Baseline-hoz viszonyított**, nem diagnosztikai testtartás-observation, és egy
gépi **safety claim guard**, amely egészségügyi/diagnosztikai állítást nem
enged ki a rendszerből.

## 2. Jelenlegi állapot (mért, megelőző körök)

- Az R14 adja a szűkített pose-landmarkokat és a `PostureBaseline`-t (csak
  valid quality + minimum látható idő mellett jön létre).
- Az R18 rögzítette a `MetricDefinition` szerződést — ez a kör ugyanazt használja.
- Az Epic 4 tutor-oldalán már létezik safety/claim-kezelés (ADR 0132/0141);
  a vision oldal **saját, szűkebb** guardot kap, ugyanazzal a filozófiával.

## 3. Scope

**Benne:** shoulder asymmetry, torso lean, elbow drift és opcionális neck proxy
metrikák (mind **baseline-relatív**, ahol értelmezhető), minimum látható
időtartam + session drift window, `VisionSafetyPolicy` (engedélyezett
állítás-kódok, semleges nyelvezet), `SafetyClaimGuard` (tiltott claim-osztályok
gépi kiszűrése), és a fájdalom-bejelentés kezelésének **átadási** szabálya.

**Kívül — TILOS:** UI-szöveg/ARB (R23/R24), tutor-integráció (R27), fusion (R22),
orvosi tartalom, diagnózis.

## 4. Engedélyezett fájlok

| Útvonal | Állapot | Miért |
|---|---|---|
| `.../domain/metrics/posture_metrics.dart` | ÚJ | metrika-katalógus |
| `.../domain/metrics/posture_metric_engine.dart` | ÚJ | számítás |
| `.../domain/safety/vision_safety_policy.dart` | ÚJ | engedélyezett claim-kódok |
| `.../domain/safety/safety_claim_guard.dart` | ÚJ | gépi őr |
| `lib/features/vision/public.dart` | meglévő | additív export |
| `test/features/vision/domain/*`, `test/fixtures/vision/posture` | ÚJ | tesztek |
| `docs/rounds/e05-r20-*.md` | meglévő | §10 handoff |

**Tilos zóna:** minden más; `lib/features/ai_tutor/`; ARB. Listán kívül → `stopped`.

## 5. Kötött architekturális döntések

1. **Nincs egészségügyi claim.** Tiltott osztályok: diagnózis, sérülés-jóslat,
   fájdalom-magyarázat, gyógyulási tanács, „ez ártalmas" típusú minősítés.
   **NEM elfogadható** ezek enyhébb megfogalmazása sem („ez hosszú távon
   fájdalmat okozhat") — a guard **kód-szinten** tiltja, nem prózában.
2. **Baseline nélkül nincs abszolút ítélet.** Ha nincs baseline (R14 kapuja),
   a posture metrikák `notObservable`-ök. **NEM elfogadható:** populációs
   átlagra alapozott „helyes tartás" ítélet.
3. **A kimenet claim-kód, nem mondat.** A metric engine kódot ad
   (pl. `postureShoulderAsymmetryIncreasedVsBaseline`), a szöveg az R23 policy +
   ARB dolga. **NEM elfogadható** hardcode-olt magyar/angol mondat.
4. **Fájdalom-bejelentés:** a vision réteg **nem értelmez** fájdalmat; a
   bejelentés a tutor safety útjára kerül (R27), és a vision oldal csak jelzi,
   hogy a coaching-cue-kat el kell hallgattatni.
5. **Alacsony pose confidence → `notObservable`** (nem pontozás).
6. **A guard mindkét irányban őriz:** a policy-katalógus **minden** kódját
   ellenőrzi, hogy engedélyezett osztályba esik-e, ÉS elutasít minden nem
   katalogizált kódot (fail-closed allowlist).

## 6. Acceptance criteria

- [ ] **Claim-guard teszt (a kör kulcsbizonyítéka):** rögzített tiltott-minta
      lista (diagnózis, jóslat, fájdalom, gyógyulás, „ártalmas") — a guard
      **mind** elutasítja; és egy nem katalogizált kód is elutasításra kerül
      (fail-closed).
- [ ] **Valódi-sértés próba (§10):** egy tiltott osztályba eső claim-kód
      ideiglenes felvétele a katalógusba → a guard teszt PIROS → visszaállítás.
- [ ] **Baseline-mátrix:** baseline hiányzik / részleges / teljes — az első
      kettőnél `notObservable`, a harmadiknál baseline-relatív érték.
- [ ] **Metrikánkénti unit teszt** (4 metrika) tipikus / határ / degenerált
      esettel, és **visibility-mátrix** (alatt / rajta / fölött).
- [ ] **Kameraperspektíva-fixture-ök:** legalább 3 nézőpont; a metrikák
      előjele és nagyságrendje konzisztens (a perspektíva nem fordítja meg).
- [ ] **NaN/Infinity guard** a teljes fixture-mátrixon.

## 7. Kötelező ellenőrzések

```bash
tools/round-gate.sh test/features/vision
```

Külön processzek, nincs `&&`/pipe/`tail`. CI-dispatch/PR/merge = orchestrátor.

## 8. Implementációs sorrend

1. RED: claim-guard + baseline-mátrix.
2. Policy-katalógus (allowlist) + guard.
3. Metrikák egyenként, baseline-relatív módon.
4. Perspektíva-fixture-ök; gate.

## 9. Kockázatok

- **A „segítő" megfogalmazás észrevétlenül egészségügyi állítássá válik** — ez a
  kör legfőbb kockázata; a fail-closed allowlist az egyetlen gépi őr.
- **A baseline ritkán jön létre** valós használatban (R14 szigorú kapuja), így a
  posture-metrikák gyakran `notObservable`-ök lesznek; ez **helyes viselkedés**,
  nem hiba — a device-mátrix PENDING mérése adhat okot a küszöb hangolására.

**STOP:** egészségügyi claim, populációs abszolút ítélet vagy hardcode-olt
mondat helyett dokumentált brief-revízió.

## 10. Implementation handoff — az implementer tölti ki

_(üres)_

## 11. Review — a független reviewer tölti ki

Tervezett review: `docs/reviews/e05-r20-posture-metrics-and-safety-policy-review.md`.
Merge csak exact-SHA zöld CI, §4-en belüli diff és nulla OPEN BLOCKER/MAJOR után.

> **Reviewer figyelem:** safety-kritikus kör — a `security-reviewer` ágens
> bevonása KÖTELEZŐ (claim-osztályok, fail-closed allowlist).
