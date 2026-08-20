# ADR 0336 — Generated public barrel collision waiver requires migration evidence

**Státusz:** elfogadva (E99-R18 pre-flight, 2026-08-20)  
**Kapcsolódó kör:** E99-R18 (GOV-12)  
**Kapcsolódó előzmény:** ADR 0307 §5; E99-R18/H8; lessons/L343

## Kontextus

E99-R18 a `practice_generator` feature kézzel karbantartott `public.dart`
barreljét determinisztikus, fragmentum-alapú generálásra állítja át. A
slot-tervezőben elsőként javasolt `lib/features/*/public.dart` glob azonban
minden feature root barreljét generáltnak minősítené, függetlenül attól, hogy
a feature ténylegesen átállt-e a generátorra.

Mérés: csak a `practice_generator` rendelkezik `public/*.dart`
fragmentumokkal. A széles glob miatt a
`SlotPlanningTest::test_real_epic_four_rounds_are_correctly_rejected` nem
észleli az E04-R15/E04-R16 valós, nem migrált `public.dart` ütközését.

## Döntés

Egy `public.dart` csak akkor kerülhet ki a slot-konfliktus számításból, ha a
konkrét feature-ben bizonyítottan generált output: fragmentum-forrás, a
generátor frissességét mérő teszt és explicit nyilvántartási bejegyzés
egyaránt létezik. E99-R18-ban ez kizárólag
`lib/features/practice_generator/public.dart`.

Egy globális feature-glob önmagában nem generálási bizonyíték. A nem
regisztrált feature root barrelek és minden `public/*.dart` fragmentum teljes
értékű ütközési felület marad.

## Következmények

- A pilot párhuzamos, újragenerálható outputja nem blokkolja a slot-tervezőt.
- Nem migrált feature-ek briefjei továbbra is biztonságosan ütköznek.
- Egy jövőbeli feature csak saját generátor-migrációs körében kerülhet a
  nyilvántartásba, a hozzá tartozó ellenőrzésekkel együtt.
