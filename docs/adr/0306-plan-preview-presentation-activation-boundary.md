# ADR 0306 — Plan-preview presentation activation boundary

**Státusz:** elfogadva (2026-08-18).  
**Forrás:** E07-R21 pre-flight, SDD Ch8 Kör 21.  
**Épít:** [ADR 0263](0263-bounded-deterministic-plan-repair.md) (a validáció
aktiválási kapu), [ADR 0264](0264-explainable-priority-and-versioned-policy.md)
(faktoronkénti magyarázat), [ADR 0266](0266-generation-orchestration-and-no-partial-activation.md)
(nincs részleges aktiválás).

## Kontextus

A jelenlegi `GenerationOrchestrator.generate()` egy sikeresen validált tervet
azonnal aktívvá tesz (`generation_orchestrator.dart:150-154`). Emiatt az R21
nem kötheti rá a preview-t erre a már összevont generation-útra anélkül, hogy
egy korábbi kör application-szerződését módosítaná. Ugyanakkor a jelenlegi
publikus contract már elég egy önálló, fixture-rel is mérhető preview-hoz:
`AdaptivePracticePlan`, `PlanValidationContext`, `PlanValidator` és
`GenerationPlanActivation` mind elérhető.

## Döntés

1. Az R21 `PlanPreviewController` kész tervet és validációs kontextust kap;
   nem importálja és nem hívja a `GenerationOrchestrator`-t vagy a
   `PlanGeneratorController`-t.
2. Minden kézi szerkesztés után ugyanaz a `PlanValidator.validate` fut. Az
   `error` vagy `fatal` lelet blokkolja az aktiválást; `warning` esetén a
   felhasználónak külön, explicit áttekintést kell nyugtáznia.
3. Aktiválás csak az explicit megerősítő műveletben történhet, az injektált
   `GenerationPlanActivation`-ön, a `PlanStatus.active` másolattal. Kilépés
   és sikertelen validálás nem hívhat aktivációt.
4. A reason-sheet kizárólag strukturált reason/faktor adatokból és ARB
   lokalizációból állíthat szöveget; nem használ hálózatot és nem állíthat a
   confidence-nél erősebbet.

## Következmények

- A preview önmagában tesztelhető és offline marad, de még nem a tényleges
  generation-flow képernyője.
- A valódi bekötés egy későbbi, külön kiosztott kör feladata: előbb a
  `generate()` és az aktiválás összevont application-határát kell explicit
  hívásokra bontani.

## Mérce

Az E07-R21 A1–A8 cellái a preview-ból kényszerítik ki a kilépési/hibaút
aktiválásmentességet, az edit utáni validálást, a warning-áttekintést, valamint
az offline, lokalizált és confidence-hű magyarázatot.
