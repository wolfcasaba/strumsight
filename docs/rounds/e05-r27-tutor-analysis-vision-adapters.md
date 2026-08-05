# E05-R27 — AI Tutor és Analysis vision evidence adapterek

- **Státusz:** PREPARED (előre megírva 2026-08-05, kód olvasva: main @ `5d082dc`)
- **SDD-kör:** [`docs/sdd/06-epic-05-computer-vision.md`](../sdd/06-epic-05-computer-vision.md) Kör 27; §27
- **Branch:** `codex/e05-r27-tutor-analysis-vision-adapters`
- **Előfeltétel:** **E05-R22, E05-R23, E05-R24 merge**; Epic 4 (AI Tutor) lezárva
- **Brief szerzője:** Claude (batch) · **Implementáció:** Codex (Terra)

```ai-router
schema_version = 1
risk = "high"
allowed_paths = [
  "lib/features/vision/domain/integration/vision_context_snapshot.dart",
  "lib/features/vision/domain/integration/vision_claim_guard.dart",
  "lib/features/ai_tutor/data/context/tutor_vision_context_adapter.dart",
  "lib/features/analyze/model/analysis_vision_reference.dart",
  "lib/features/analyze/providers/analysis_vision_adapter.dart",
  "lib/features/ai_tutor/public.dart",
  "lib/features/analyze/public.dart",
  "lib/features/vision/public.dart",
  "test/features/vision/domain/vision_claim_guard_test.dart",
  "test/features/ai_tutor/data/tutor_vision_context_adapter_test.dart",
  "test/features/analyze/analysis_vision_adapter_test.dart",
  "docs/rounds/e05-r27-tutor-analysis-vision-adapters.md",
]
gate_tests = [
  "test/features/vision",
  "test/features/ai_tutor",
  "test/features/analyze",
]
native_gate = false
```

> ⚠ **Pre-flight (KÖTELEZŐ):** `origin/main` + E05-R22/R23/R24 merge; olvasd újra
> az Epic 4 **`TutorContextSnapshot`** mai alakját és a **redakciós szabályát**
> (ADR 0141: a prompt-builder CSAK redaktált snapshotot fogad), valamint a
> `TutorSourceRef` citációs típust. A vision snapshot ehhez **illeszkedik**.
> Nincs ÚJ ADR (0161/0162 + 0141 bővítése). PREPARED→PLANNING, brief commit előbb.

## 0. Kör-jelzés és STOP-protokoll

```bash
tools/codex-signal.sh progress "<egy sor>" ; tools/codex-signal.sh done "<egy sor>"
tools/codex-signal.sh stopped "<egy sor>" ; tools/codex-signal.sh blocked "<egy sor>"
```

Lezáró jelzés nélkül a kör bukott. Listán kívüli fájl → `stopped`.

## 0.0 Tervezési baseline és pre-flight revízió

**PREPARED.** Nincs előre kiosztott ADR.

## 1. Cél

A vision eredmények **minimális, privacy-safe és claim-guardolt** elérhetővé
tétele a Tutor és az Analysis számára — úgy, hogy a tutor **csak valid
bizonyítékból** beszélhessen a vizuális megfigyelésekről.

## 2. Jelenlegi állapot (mért, `5d082dc`)

- Az Epic 4 kész: `TutorContextSnapshot` **redaktált** bemenettel, trusted/
  untrusted határ, `TutorSourceRef` citációk (ADR 0141), tool-allowlist (0137),
  action-confirmation (0139).
- Az Analysis (`lib/features/analyze/`) audio-klip elemzést ad; vision-hivatkozás
  nincs.
- A `visionTutorIntegrationEnabled` és `visionAnalysisIntegrationEnabled` OFF.

## 3. Scope

**Benne:** `VisionContextSnapshot` (**csak** aggregátum + insight-kód +
confidence + observability), `VisionClaimGuard` (bizonyíték nélküli vizuális
állítás blokkolása), a Tutor-oldali context-adapter, az Analysis-oldali
vision-referencia adapter közös session-idővel, cross-modal **inferred**
provenance, és deterministic fallback `notObservable` esetre.

**Kívül — TILOS:** prompt-sablon módosítása, tutor tool/action réteg,
raw frame / teljes landmark-stream / arcpont bárhová továbbadása, UI,
persistence (R28).

## 4. Engedélyezett fájlok

| Útvonal | Állapot | Miért |
|---|---|---|
| `.../vision/domain/integration/vision_context_snapshot.dart` | ÚJ | minimalizált snapshot |
| `.../vision/domain/integration/vision_claim_guard.dart` | ÚJ | claim-őr |
| `.../ai_tutor/data/context/tutor_vision_context_adapter.dart` | ÚJ | tutor-oldali adapter |
| `.../analyze/model/analysis_vision_reference.dart` | ÚJ | analysis-hivatkozás |
| `.../analyze/providers/analysis_vision_adapter.dart` | ÚJ | analysis-oldali adapter |
| `*/public.dart` (ai_tutor, analyze, vision) | meglévő | additív export |
| `test/features/*` | ÚJ | guard + snapshot + round-trip |
| `docs/rounds/e05-r27-*.md` | meglévő | §10 handoff |

**Tilos zóna:** minden más; `lib/features/ai_tutor/` prompt/tool/action fájlok;
`docs/rag`. Listán kívül → `stopped`.

## 5. Kötött architekturális döntések

1. **Adatminimalizálás (ADR 0161):** a snapshot **kizárólag** aggregátumot,
   insight-kódot, confidence-t és observability-t tartalmaz. **NEM elfogadható:**
   raw frame, teljes landmark-idősor, arcpont, kép-URI, vagy „debug" mező —
   semmilyen flag mögött sem.
2. **Claim guard fail-closed:** ha egy vizuális állításhoz **nincs** megfelelő
   confidence-ű evidence, az állítás **blokkolt**, és a fallback egy
   determinisztikus `notObservable` szöveg-kód. **NEM elfogadható:** „a modell
   majd óvatosan fogalmaz" indoklás — a guard gépi.
3. **Cross-modal insight `inferred`-ként jelölt** (nem `observed`), és a
   provenance megmondja, mely audio és mely vision bizonyítékból származik.
4. **A vision snapshot az Epic 4 redakciós határának *untrusted-mentes*
   oldalán van:** géptől jövő, strukturált adat, nem felhasználói szöveg —
   de a beillesztés **ugyanazon a redaktált úton** történik. **NEM elfogadható**
   a snapshot beszúrása a prompt-építés megkerülésével.
5. **Analysis ↔ Vision összekapcsolás közös session-idővel** (R21 mapping),
   nem wall clockkal.
6. **Egyik adapter sem küld hálózatra semmit** — a network-guard teszt méri.

## 6. Acceptance criteria

- [ ] **Minimization snapshot teszt (a kör kulcsbizonyítéka):** a
      `VisionContextSnapshot` szerializált kulcskészlete egy **rögzített**
      halmazzal egyezik; új mező csak a snapshot frissítésével kerülhet be.
- [ ] **Tiltott-mező mátrix:** frame / landmark-lista / arcpont / kép-URI —
      mind a négy típusra teszt, hogy a snapshot **nem tartalmazza**, még
      akkor sem, ha a forrás evidence hordozza.
- [ ] **Claim-guard mátrix:** confidence a küszöb **alatt / rajta / fölött** ×
      evidence **van / nincs** = 6 cella; állítás csak az „evidence van +
      küszöb fölött/rajta" cellákban engedélyezett.
- [ ] **Fallback-teszt:** blokkolt állítás esetén determinisztikus
      `notObservable` kód, kétszeri futás azonos.
- [ ] **Analysis round-trip:** a vision-referencia a közös session-idővel
      oda-vissza feloldható; wall clock **nem** szerepel.
- [ ] **Network-spy teszt:** az adapterek használata **nulla** hálózati kérést
      generál (a repó meglévő offline-guard mintájával).
- [ ] **Valódi-sértés próba (§10):** a landmark-lista átengedése a snapshotba
      → a minimization teszt PIROS → visszaállítás.

## 7. Kötelező ellenőrzések

```bash
tools/round-gate.sh test/features/vision test/features/ai_tutor test/features/analyze
```

Külön processzek, nincs `&&`/pipe/`tail`. CI-dispatch/PR/merge = orchestrátor.

## 8. Implementációs sorrend

1. RED: minimization + tiltott-mező + claim-guard mátrix.
2. `VisionContextSnapshot` + `VisionClaimGuard`.
3. Tutor-adapter (a redaktált úton).
4. Analysis-adapter + network-spy; gate.

## 9. Kockázatok

- **A „hasznos extra mező"** (pl. néhány landmark „a jobb magyarázatért")
  csendben sérti az adatminimalizálást — a rögzített kulcshalmaz az őr.
- **A guard megkerülése** a tutor prompt oldaláról: ezért a prompt-fájlok a
  tilos zónában vannak, és az integráció csak az adapteren át mehet.

**STOP:** raw/landmark adat továbbadása, prompt-fájl módosítása vagy a
claim-guard lazítása helyett dokumentált brief-revízió.

## 10. Implementation handoff — az implementer tölti ki

_(üres)_

## 11. Review — a független reviewer tölti ki

Tervezett review: `docs/reviews/e05-r27-tutor-analysis-vision-adapters-review.md`.
Merge csak exact-SHA zöld CI, §4-en belüli diff és nulla OPEN BLOCKER/MAJOR után.

> **Reviewer figyelem:** privacy- és prompt-injection-érintett kör — a
> `security-reviewer` ágens bevonása KÖTELEZŐ.
