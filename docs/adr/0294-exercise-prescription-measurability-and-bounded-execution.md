# ADR 0294 — ExercisePrescription mérhetőségi és korlátos végrehajtási határa

**Státusz:** elfogadva (2026-08-16, E07-R09 pre-flight).  
**Forrás:** [E07-R09](../rounds/e07-r09-exercise-prescription.md), SDD Ch8 §15.
**Épít:** [ADR 0255](0255-deterministic-first-practice-planning.md),
[ADR 0258](0258-hard-and-soft-planning-constraints.md) és
[ADR 0262](0262-catalog-snapshot-revisions-and-capability-truth.md).

## Kontextus

Az R08 `ExerciseCandidate` teljes, explicit `ExerciseCapability` mapet és
nem üres `skillTargets` listát ad, de nem hordoz tetszőleges, szabad szöveges
metric-code → measurement-capability táblát. Egy ilyen leképezés kitalálása
lehetővé tenné, hogy a recept olyan eredményt állítson biztosan mérhetőnek,
amelyet a kiválasztott executor ténylegesen nem tud igazolni.

Az ExercisePrescriptionnek emellett korlátosnak kell lennie, miközben a napi
hard időkeret csak a későbbi, Kör 10-beli tervszinten létezik. A recipe nem
olvashatja és nem találhatja ki ezt a későbbi állapotot.

## Döntés

1. Minden `SuccessCriteria` explicit, nem üres
   `Set<ExerciseCapability> requiredCapabilities` értéket hordoz. A recept
   konstrukciója kizárólag akkor fogadja el, ha a kiválasztott candidate
   minden követelt capabilityje `supported`. A criterion nem vezet be
   szabad szöveges metric-code → capability következtetést.
2. `completion` és `assessmentOnly` sem implicit kivétel: az üres
   requirement nem jelent mérhetőséget, és assessment blokkból nem lesz
   hamis pass/fail állítás.
3. A repetition minden nyílt végű változata explicit, pozitív maximumot
   kap; nincs „gyakorlatilag végtelen” default.
4. A recipe explicit `hardElapsedLimit` értéket hordoz. Az aktív és rest
   idő teljes elapsed összege ezt inkluzívan nem lépheti túl; a rest nem
   aktív játékidő, de az elapsed részét képezi. Ez az ADR 0258 §3-mal
   összhangban áll, anélkül hogy a későbbi tervmodellt importálná.
5. A fallback a primary-val pontosan azonos skill-target halmazt céloz;
   a lista sorrendje nem jelent pedagógiai eltérést.
6. A JSON-kódok zártak és veszteségmentesek: ismeretlen, hiányzó vagy üres
   enum-/capability-kód kontrollált konstrukciós hiba, sosem default.

## Következmények

- A domain értékobjektumok tiszták és determinisztikusak maradnak; nincs
  Flutter-, óra-, véletlen- vagy hálózatfüggés.
- A későbbi executor csak olyan sikert publikálhat, amelyhez ez a recept
  explicit, támogatott capabilityt deklarált; részletes mérési metrika
  bekötése egy későbbi, saját scope-jú kör feladata.
- A Kör 10 a recipe `hardElapsedLimit` értékét a napi hard korláttal
  összevetheti, de az R09 nem szerel össze tervet.

## Mérce

Az E07-R09 A1–A7 cellái: maximum nélküli/fölötti repetition elutasítása,
unsupported tempo vagy criteria-capability elutasítása, teljes
skill-target-halmazt cserélő fallback elutasítása, explicit criterion
követelménye, veszteségmentes JSON round-trip, valamint a `hardElapsedLimit`
alatti / határon lévő / fölötti elapsed idő hármasa.
