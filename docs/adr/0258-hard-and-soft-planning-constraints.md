# ADR 0258 — A hard korlát sérthetetlen, a soft költséggel sérthető

**Státusz:** elfogadva (2026-08-15). Az Epic 7 korlát-modelljének döntése.
Forrás: [`docs/sdd/08-epic-07-ai-practice-generator.md`](../sdd/08-epic-07-ai-practice-generator.md) Ch8 Kör 3.
Épít: [ADR 0255](0255-deterministic-first-practice-planning.md),
[ADR 0257](0257-planner-typed-ids-and-stable-enum-codes.md).

## Kontextus

A tervező hét korlát-kategóriát kezel: equipment, tuning, capability,
comfort, accessibility, preference, avoid. A kézenfekvő megvalósítás mindre
egyetlen „költség" mezőt tenne, és a legolcsóbb tervet választaná.

Ez két esetben elfogadhatatlan:

- **Fizikai korlát.** Ha a tanulónak fáj a csuklója, vagy nincs meg a
  hangszere/hangolása, a terv nem lehet „egy kicsit drágább, de vállalható".
  Végrehajthatatlan.
- **Az idő.** Ha valaki keddre 20 percet adott meg felső korlátként, egy
  21 perces terv nem „majdnem jó" — hazugság a naptárában.

## Döntés

### 1. Két különböző dolog, nem egy skála két vége

- **Hard korlát:** a tervező kimenete **nem sértheti meg**. Ha nincs ilyen
  terv, az eredmény hiba vagy csökkentett terv — **soha nem** hard-sértő terv.
- **Soft korlát:** preferencia. Megsérthető, és a sértés **költséget** kap,
  amit a prioritás-motor mérlegel.

*A kritikus tiltás:* a hard korlát „nagyon nagy költségű soft"-ként való
kezelése. Elég rossz alternatívák mellett a rendszer akkor mégis megsértené —
pontosan azt, amit a „hard" szó kizár.

### 2. A keménység KÜLÖN mező, nem a kategória következménye

Ugyanaz a kategória lehet hard vagy soft, tanulótól függően. A SDD elfogadási
feltétele nevesíti is: *„Comfort hard constraintként kezelhető."* Fájdalom
esetén a kényelem nem preferencia.

### 3. A napi hard időmaximum inkluzív, és befelé kerekít

20 perces hard maximum mellett a 20 perces terv **elfogadható**, a 21 perces
**nem**. Kerekítés mindig lefelé — a felfelé kerekítés csendes túllépés.

### 4. Az elérhetőség helyi dátumhoz kötött, nem UTC-pillanathoz

A heti elérhetőség helyi naptári napot és perceket tárol, nem `DateTime`-ot.
Az UTC-re váltás megjelenítési és végrehajtási kérdés.

*Miért fontos:* a `DateTime`-alapú modell nyári-időszámítás-váltáskor és
utazáskor **csendben** tolja el a napokat — a felhasználó terve megváltozik,
és semmi nem jelzi.

### 5. A validátor jelez, nem old fel

A `RequestValidator` konfliktust **detektál** (pl. a hard korlátok együtt
kielégíthetetlenek). A determinisztikus javítás külön felelősség — a
`PlanValidator és deterministic repair` (Ch8 Kör 11) dolga.

### 6. Túl sok elsődleges cél: figyelmeztetés, nem hiba

A fókusz elvesztése valós kockázat, de nem érvénytelenség. A rendszer jelez,
a döntés a tanulóé.

## Következmények

- A prioritás-motor (Kör 12) és a jelölt-választó (Kör 13) **kétlépcsős**
  lesz: előbb hard-szűrés, aztán soft-költség szerinti rendezés. A hard
  korlát sosem kerül a költségfüggvénybe.
- Egy kielégíthetetlen hard-halmaz **látható hiba** lesz, nem csendben rossz
  terv — ez a felhasználónak is magyarázható.
- A helyi-dátum modell miatt a tervező egységtesztjei időzóna-semlegesek.

## Mérce

Az `E07-R03` §6.1 mérce-mátrixa, benne a napi időkorlát három kötelező
cellájával (alatta / **a határon, inkluzív** / fölötte), a DST-váltó
fixture-rel, és a valódi-sértés próbával: a hard korlát költség fejében való
megsérthetővé tételekor az **A1** cellának pirosnak kell lennie.
