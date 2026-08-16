# ADR 0299 — A WeeklyScheduler explicit, domain-pure heti döntési szerződést használ

**Státusz:** elfogadva (2026-08-16). E07-R15 saját, még nem merge-elt döntése.
Forrás: [`docs/sdd/08-epic-07-ai-practice-generator.md`](../sdd/08-epic-07-ai-practice-generator.md)
Ch8 §22 és Kör 15. Épít: [ADR 0255](0255-deterministic-first-practice-planning.md),
[ADR 0258](0258-hard-and-soft-planning-constraints.md),
[ADR 0298](0298-time-budget-allocation-contract.md).

## Kontextus

Az R03 `WeeklyAvailability` naponta eltérő, helyi dátumú hard korlátot hordoz.
Az R14 `TimeBudgetAllocator` ezt egy napra osztja fel és unavailable napra
fail-closed módon nem ad budgetet. A schedulernek ezek után, de a
prescription-construction előtt kell meghatároznia, mely kiválasztott jelölt
mely napra kerül. A meglévő `PracticeBlock` nem lehet az input: már kész
`ExercisePrescription`-t követel, tehát későbbi pipeline-fázisban áll.

## Döntés

1. A scheduler új, Flutter-, óra- és véletlenszám-mentes típusokat használ:
   `ScheduleCandidate` (stabil azonosító, fókusz, terhelés, új-anyag/review,
   időtartam), `WeeklyScheduleRequest` (availability, a már kiosztott napi
   `TimeBudget`-ek, jelöltek, explicit `today`, rest-day-ek és opcionális
   song céldátum), valamint `ScheduleDecision`/napi döntések.
2. A request validálása fail-closed: minden budget napja legyen available és
   a hozzá tartozó availability hard maximumán belül; rest dayre nem lehet
   döntést kiadni. A scheduler nem szerez lease-t/lockot/handle-t és nem
   futtatja újra az R14 allokátort.
3. A `SchedulingPolicy` explicit, verziózott paramétereket hordoz: maximum
   egy primary és egy secondary fókusz naponta, egymást követő high-load
   napok inkluzív maximuma, valamint az esedékes review-k felső aránya.
   A jelöltek és napok rögzített, stabil kulcsú rendezésben járódnak be.
4. Pihenőnap üres. Unavailable nap üres. Ezekre sem kötelező, sem könnyű,
   opcionális vagy review tartalom nem kerülhet.
5. Song céldátum esetén a `today`–target távolság tisztán kiszámított fázist
   ad. A policy light-review időablakában új anyag nem kerül a tervbe;
   kizárólag light review jelölt választható. A rendszer nem olvassa a
   rendszerórát.

## Következmények

- A scheduler eredménye a következő, prescription-construction kör közvetlen
  bemenete lesz, nem módosít visszamenőleges plan/blokk adatot.
- Minden napi döntéshez géppel vizsgálható indok- és policy-kód társul; nem
  learner free text.
- A rest-day szabály ebben a körben szigorúbb az SDD általános példáinál:
  a kör briefje szerint nincs tartalom. A reflection/theory lehetőség csak
  későbbi, külön döntéssel vezethető be.

## Mérce

Az E07-R15 tesztjei mérik a nulla availabilityt, rest dayt, `1 / 2 / 3`
high-load sorozatot az inkluzív 2-es limittel, review-arányt, céldátum előtti
light-review kizárólagosságát, napi fókuszlimitet, hét-dátumhatárt és teljes
determinizmust. A review valódi-sértés próbája egy unavailable napra kényszerített
kötelező blokk; az A1 cellának pirosra kell váltania.
