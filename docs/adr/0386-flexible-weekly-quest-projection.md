# ADR 0386 — Rugalmas, monoton heti quest-projekció

- **Státusz:** elfogadva
- **Dátum:** 2026-08-21
- **Kör:** `E08-R18` (Chapter 9, Kör 18)
- **Kapcsolódó:** [`0290`](0290-compassionate-streaks-and-idempotent-claims.md),
  [`0382`](0382-quest-objective-and-lifecycle-contract.md),
  [`0384`](0384-deterministic-capability-safe-daily-quest-generation.md)

## Kontextus

A Chapter 9 R18 heti célja egyszerre támaszkodik a terv elérhető idejére, a
heti consistency-projekcióra és a quest lifecycle-ra. A generátornak ezért
újragenerálható célértéket kell adnia úgy, hogy a hét közbeni tervmódosítás
soha ne írja vissza a már elért haladást.

Az R17 precedense caller-fed, immutable snapshotból és dokumentált
UTF-8/FNV-1a seedből dolgozik. Az R11 `weeklyConsistency()` projekciója szintén
caller-fed és repositorymentes. A WeeklyRecap UI viszont külön kör: ha az
application réteg itt kész angol mondatot gyártana, megkerülné az ARB
lokalizációs határt és idő előtt összekötné a domain tényeket a felülettel.

## Döntés

1. **Caller-fed, pure heti snapshot.** A heti generátor schedule-t, stabil
   profile snapshot keyt, elérhető napot és percet, normál heti percet,
   korábbi és frissen mért completed unitot, verziózott candidate-listát és
   improvement-measurement availabilityt kap. Nem olvas órát, repositoryt,
   tervet, hálózatot vagy platform plugint.

2. **A heti seed az R17 mintájának újrafelhasználása.** A seed material
   `generationEpochDay|profileSnapshotKey|catalogVersion`; a hívó a hét stabil
   kezdőnapját adja `generationEpochDay`-ként. A candidate stable ID-val
   kibővített UTF-8 anyag 64 bites FNV-1a sorrendkulcsot ad. `Random()` mag
   nélkül, `DateTime.now()`, `String.hashCode` és ambiens iteration-order
   tilos.

3. **Zárt heti kind és meglévő típusos objective.** A négy kind:
   `activeDays`, `planBlock`, `modeDiversity`, `improvement`. A candidate a
   kind mellett meglévő `QuestObjective`-et és pozitív base targetet hordoz.
   A valid párok rendre `MetricQuestObjective(eventCount)`,
   `PlanBlockQuestObjective`, `MetricQuestObjective(diversityXp)` és
   `MetricQuestObjective(improvementXp)`. Cross-wiring fail-closed.

4. **Magyarázható, egészértékű skálázás.** Pozitív elérhető idő mellett a
   target `ceil(baseTargetUnits * availableMinutes /
   baselineWeeklyMinutes)`. Az output derivation mezői változatlanul
   visszaadják e három számot és az elérhető napokat. Active-days kindnál a
   target további capje `min(scaledTarget, availableDays, 5)`; így 6 vagy 7
   kötelező nap nem jöhet létre. Más kindnál a pozitív elérhető idő legalább
   egy unitot ad. Nulla elérhető nap vagy perc nem gyárt kötelező questet.

5. **A progress quest-azonosságon belül monoton.** A snapshot a korábbi
   progresszt stabil `previousQuestId`-vel együtt adja. Ha ez az ID az
   aktuálisan kiválasztott candidate ID-ja, a kimeneti progress
   `max(previousCompletedUnits, observedCompletedUnits)`; eltérő replacement
   csak a saját `observedCompletedUnits` értékével indul. Pozitív previous
   progress ID nélkül invalid input. A target új tervre csökkenhet, de azonos
   quest progressze nem; a completion kizárólag `progress >= target`.
   Kihagyott napból nincs negatív delta, levonás vagy büntetés.

6. **Measurement fail-closed.** Improvement candidate csak explicit elérhető
   improvement measurement mellett eligible. Measurement hiányában a többi
   candidate közül történik stabil választás; teljes candidate-hiány üres
   eredmény, nem kitalált improvement.

7. **A rollover adat, nem mondat.** A generátor nyelvfüggetlen, zárt statuszt
   és exact target/progress tényeket ad. User-facing szöveg, sürgetés,
   szégyenítés és localization key kitalálása nincs ebben a rétegben; a
   későbbi WeeklyRecap UI ARB-ból jelenít meg.

8. **Az availability hét-tartomány.** `availableDays` csak `0..7` lehet; a
   3- és 7-napos végpontot a shipping active-days targeten külön mérjük.

9. **Nincs új persistence schema.** A generált heti quest a meglévő
   `QuestDefinition` weekly cadence-ét használja; a skálázási/progress/
   rollover adatok application projectionök. Perzisztencia- és UI-wiring
   külön kör marad.

## Következmények

A cél reprodukálható, az elérhető idővel arányos és a felhasználó már elért
haladását tervedit után is megőrzi. A 7/7 grind és az improvement-adat
kitalálása szerkezetileg kizárt. Az application contract valamivel bővebb,
mert a hívónak explicit snapshotot és candidate-metaadatot kell összeállítania;
ez a purity és a későbbi adapterek tesztelhetőségének ára.

## Mérce

Az E08-R18 brief A1–A10 cellái mérik a 3/4/5/6/7 aktívnap-mátrixot, a
360→180 perces 6→3 skálázási referenciát, a `max(previous, observed)`
same-ID monotonitást és a cross-ID isolationt, a kipinnelt seedet, a négy kind
cross-wiringját, a measurement fail-closed ágat, az immutable nézeteket és a
nyelvfüggetlen rollover projekciót. A reviewer valódi-sértésként 7-re lazítja
az aktívnap-capet; az A1 cellának pirosra kell váltania, restore után a teljes
kör-gate zöld.
