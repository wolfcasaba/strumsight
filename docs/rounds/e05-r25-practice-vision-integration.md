# E05-R25 — Practice Engine vision integráció

- **Státusz:** PREPARED (előre megírva 2026-08-05, kód olvasva: main @ `5d082dc`)
- **SDD-kör:** [`docs/sdd/06-epic-05-computer-vision.md`](../sdd/06-epic-05-computer-vision.md) Kör 25; §25
- **Branch:** `codex/e05-r25-practice-vision-integration`
- **Előfeltétel:** **E05-R22, E05-R23, E05-R24 merge**
- **Brief szerzője:** Claude (batch) · **Implementáció:** Codex (Terra)

```ai-router
schema_version = 1
risk = "high"
allowed_paths = [
  "lib/features/vision/domain/integration/vision_practice_contract.dart",
  "lib/features/practice/data/vision/practice_vision_adapter.dart",
  "lib/features/practice/domain/model/practice_session_result.dart",
  "lib/features/practice/public.dart",
  "lib/features/vision/public.dart",
  "lib/features/practice/presentation/widgets/practice_vision_dimension.dart",
  "lib/l10n/app_en.arb",
  "lib/l10n/app_hu.arb",
  "test/features/practice/data/practice_vision_adapter_test.dart",
  "test/features/practice/domain/practice_session_result_vision_test.dart",
  "test/features/practice/presentation/practice_vision_dimension_test.dart",
  "docs/rounds/e05-r25-practice-vision-integration.md",
]
gate_tests = [
  "test/features/practice",
  "test/features/vision",
]
native_gate = false
```

> ⚠ **Pre-flight (KÖTELEZŐ):** `origin/main` + E05-R22/R23/R24 merge; olvasd újra
> `lib/features/practice/domain/model/practice_session_result.dart` **mai
> mezőit és minden hívóhelyét** (`rg -n "PracticeSessionResult" lib test | wc -l`),
> valamint a `practice/public.dart` exportjait. **A meglévő audio-pontozás
> viselkedése nem változhat.** Nincs ÚJ ADR. PREPARED→PLANNING, brief commit előbb.

## 0. Kör-jelzés és STOP-protokoll

```bash
tools/codex-signal.sh progress "<egy sor>" ; tools/codex-signal.sh done "<egy sor>"
tools/codex-signal.sh stopped "<egy sor>" ; tools/codex-signal.sh blocked "<egy sor>"
```

Lezáró jelzés nélkül a kör bukott. Listán kívüli fájl → `stopped`.

## 0.0 Tervezési baseline és pre-flight revízió

**PREPARED.** Nincs előre kiosztott ADR.

## 1. Cél

**Opcionális** vision-bizonyíték hozzáadása kiválasztott Practice gyakorlatokhoz
úgy, hogy az audio-pontozás **bitre változatlan** marad, és vision nélkül nincs
semmilyen regresszió.

## 2. Jelenlegi állapot (mért, `5d082dc`)

- A Practice Engine V2 él (`lib/features/practice/`), a `PracticeSessionResult`
  a `domain/model/` alatt; az eredmény ma **kizárólag audio** alapú.
- A cross-feature import szabálya: **csak `public.dart`** (architektúra-őr);
  a `check_architecture` allowlist **nem bővülhet**.
- A `visionPracticeIntegrationEnabled` flag OFF (E05-R03).

## 3. Scope

**Benne:** `VisionPracticeContract` (a vision oldal exportált, szűk API-ja),
`PracticeVisionAdapter` a Practice `data/` rétegében (a **fogyasztó** oldalon,
SDD §8 `lib/integrations/` helyett — ADR-döntés E05-R01 §5.7), a
`PracticeSessionResult` **additív, opcionális** vision-referenciája, három
pilot gyakorlat capability-gate-elve (**Small Strum Motion**, **Down/Up
Symmetry**, **Chord Change Economy**), a session-summary vision-dimenzió UI,
és a degradált/hiányzó vision melletti audio-only visszaesés.

**Kívül — TILOS:** az audio-pontozás bármely számítása, Speed Builder
vision-gate élesítése (flag mögött, de **default OFF** és nem e kör tárgya a
hangolása), Song Trainer (R26), Tutor (R27), persistence (R28).

## 4. Engedélyezett fájlok

| Útvonal | Állapot | Miért |
|---|---|---|
| `.../vision/domain/integration/vision_practice_contract.dart` | ÚJ | szűk vision API |
| `.../practice/data/vision/practice_vision_adapter.dart` | ÚJ | fogyasztó-oldali adapter |
| `.../practice/domain/model/practice_session_result.dart` | meglévő | **additív, opcionális** mező |
| `lib/features/practice/public.dart`, `lib/features/vision/public.dart` | meglévő | additív export |
| `.../practice/presentation/widgets/practice_vision_dimension.dart` | ÚJ | summary-dimenzió |
| `lib/l10n/app_*.arb` | meglévő | **csak additív** kulcs |
| `test/features/practice/*` | ÚJ | adapter + parity + widget |
| `docs/rounds/e05-r25-*.md` | meglévő | §10 handoff |

**Tilos zóna:** minden más practice-fájl; `lib/features/live/`; DSP;
`docs/rag`. Listán kívül → `stopped`.

## 5. Kötött architekturális döntések

1. **Az audio-pontozás nem változik.** A vision **külön dimenzió**, sosem
   módosítja az audio score-t. **NEM elfogadható:** kombinált „összpontszám",
   sem az audio score súlyozása vision-adattal.
2. **Vision nélkül nulla regresszió:** `visionPracticeIntegrationEnabled = false`
   vagy hiányzó kamera esetén a Practice viselkedése **bitre azonos** a maival.
   Ezt **parity-fixture** méri, nem szemrevételezés.
3. **A Practice nem ismeri a camera-implementációt** — csak a
   `VisionPracticeContract`-ot a `vision/public.dart`-on át. **NEM elfogadható:**
   `lib/features/vision/` belső import a practice-ből (az architektúra-őr
   allowlistje nem bővülhet).
4. **Rossz vision-quality → a gyakorlat audio-only módra vált**, a session
   megszakítása nélkül, és ezt a summary **jelzi** (nem tesz úgy, mintha
   megfigyelte volna).
5. **A pilot gyakorlatok capability-gate-eltek:** ha a szükséges capability
   hiányzik, a gyakorlat **elérhető marad** audio-only módban.
6. **A vision referencia opcionális mező** a resultban — a szerializáció
   visszafelé kompatibilis (régi rekord olvasható).

## 6. Acceptance criteria

- [ ] **Audio-parity fixture (a kör kulcsbizonyítéka):** rögzített practice
      session bemenet → az audio score, a metrikák és a history-bejegyzés
      **bitre azonos** vision ON és OFF mellett is. A teszt a teljes result
      szerializált alakját hasonlítja (a vision mezőt kivéve).
- [ ] **Vision-állapot mátrix:** `unavailable / degraded / good` — mindhárom
      cellában a gyakorlat **befejezhető**, az audio score azonos, és a summary
      vision-dimenziója rendre: nincs / részleges + magyarázat / teljes.
- [ ] **Capability-gate teszt** a három pilot gyakorlatra: hiányzó capability →
      audio-only, de **nem** letiltott gyakorlat.
- [ ] **Visszafelé kompatibilitás:** vision-mező nélküli, korábban mentett
      result **olvasható** (deszerializációs teszt).
- [ ] **Architektúra-őr:** `test/core/architecture_dependency_test.dart` zöld,
      az allowlist **nem bővült** (a diff ezt mutatja).
- [ ] **Lokalizációs paritás** zöld.
- [ ] **Valódi-sértés próba (§10):** az audio score megszorzása egy
      vision-tényezővel → az audio-parity fixture PIROS → visszaállítás.

## 7. Kötelező ellenőrzések

```bash
tools/round-gate.sh test/features/practice test/features/vision
```

Külön processzek, nincs `&&`/pipe/`tail`. A valós eszközös pilot-gyakorlat a
device-mátrix **PENDING** sora.

## 8. Implementációs sorrend

1. RED: audio-parity fixture (ez a mérce) + vision-állapot mátrix.
2. `VisionPracticeContract` + adapter.
3. Result additív mező + szerializáció.
4. Pilot gyakorlatok + summary-dimenzió + ARB; gate.

## 9. Kockázatok

- **A result-modell bővítése** sok hívóhelyet érint (a pre-flight `rg`
  számolása kötelező); ha meglévő teszt elbukik → **megállás és jelentés**.
- **A „kombinált pontszám" kísértése** — a §5.1 tiltása és a parity-fixture
  az egyetlen őr.

**STOP:** audio-score módosítás, belső vision-import vagy allowlist-bővítés
helyett dokumentált brief-revízió.

## 10. Implementation handoff — az implementer tölti ki

_(üres)_

## 11. Review — a független reviewer tölti ki

Tervezett review: `docs/reviews/e05-r25-practice-vision-integration-review.md`.
Merge csak exact-SHA zöld CI, §4-en belüli diff és nulla OPEN BLOCKER/MAJOR után.
