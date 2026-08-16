# ADR 0298 — Az időfelosztás öt typed budgetet, inkluzív hard maximumot és determinisztikus javítást használ

**Státusz:** elfogadva (2026-08-16). Az Epic 7 időfelosztási döntése.
Forrás: [`docs/sdd/08-epic-07-ai-practice-generator.md`](../sdd/08-epic-07-ai-practice-generator.md)
Ch8 Kör 14. Épít: [ADR 0255](0255-deterministic-first-practice-planning.md),
[ADR 0256](0256-practice-plan-revisions-immutable-past.md),
[ADR 0258](0258-hard-and-soft-planning-constraints.md).

## Kontextus

Az R13 már meghatározza, mely jelölt gyakorlatok kompatibilisek és milyen
prioritással érkeznek. Ezt még pontos napi időkeretté kell alakítani. Egyetlen
"perc" mező összemossa az aktív játékot, a setupot, a pihenőt és a rövid
reflexiót; a blokkonként felfelé kerekítés pedig észrevétlenül átlépné a
tanuló hard napi maximumát.

## Döntés

1. A `TimeBudget` az SDD §21.1 öt typed mennyiségét hordozza:
   `activePlaying`, `elapsedSession`, `rest`, `setup`, `reflection`. Minden
   érvényes budgetnél `elapsedSession == activePlaying + rest + setup +
   reflection`. A warmup aktív játék, nem új budget-típus.
2. A `DailyAvailability.maximumStrength == hard` maximuma inkluzív. A
   felosztó sem jelöltet, sem a kerekítés utáni eredményt nem engedhet fölé.
   A kerekítés lefelé, a policy explicit incrementjére történik; a végső
   exact-budget repair csak a hard maximumon belül oszthat vissza percet.
3. Öt percnél a policy külön micro-plan útvonalat használ: pontosan egy
   primary active-playing fókuszblokk marad, a többi opcionális játékblokk
   nem arányosan zsugorodik törmelékre.
4. A napi keret rövidítése vagy hosszabbítása explicit, typed allocation
   change-ot ad `PlanChangeReason.systemAdaptation` indokkal. A korábbi,
   completed tervmúltat ez a kör nem módosítja.
5. A felosztó domain-pure: nincs óraolvasás, `Random`, Flutter vagy globális
   mutable állapot; minden bemenet caller-supplied.

## Következmények

- A UI később külön tudja mutatni az aktív játékot és a teljes session-időt.
- A hard maximum a policy és az allocator minden kódútján ugyanolyan
  szerződés, nem pontozási preferencia.
- A weekly scheduling (R15) az elkészült napi allokációt használja, nem írja
  át annak aritmetikáját.

## Mérce

Az E07-R14 unit- és property-cellái mérik az öt budget egyenletét, az
`19 / 20 / 21` perces alatta/határon/fölötte hard-max esetet, az ötperces
egyfókuszos útvonalat, a minimum primary garanciát és a determinisztikus
change-indoklást. A review valódi-sértés próbája a lefelé kerekítést felfelé
cseréli: az A1/A4 cellának pirosra kell váltania.
