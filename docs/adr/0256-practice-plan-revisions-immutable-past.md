# ADR 0256 — A gyakorlóterv múltja megváltoztathatatlan; a változás új revízió

**Státusz:** elfogadva (2026-08-15). Az Epic 7 (AI Practice Generator) második
nyitó döntése.
Forrás: [`docs/sdd/08-epic-07-ai-practice-generator.md`](../sdd/08-epic-07-ai-practice-generator.md)
Ch8 Kör 1 („Rögzítsd ADR-ben a revision-alapú immutable múlt szabályt").
Épít: [ADR 0255](0255-deterministic-first-practice-planning.md).

## Kontextus

A gyakorlóterv élő dokumentum: a tanuló elvégez egy napot, kihagy egyet,
átütemez, célt vált, vagy a rendszer új bizonyíték alapján nehezít. A
kézenfekvő megvalósítás a terv **helyben módosítása** — és pontosan ez teszi
tönkre a terméket két ponton:

1. **A haladás elveszik.** Ha a tegnapi terv átíródik, nem lehet megmondani,
   mihez képest fejlődött a tanuló. A „mit terveztünk" és a „mit csinált"
   összemosódik.
2. **A magyarázat elveszik.** Az ADR 0255 szerint minden blokk visszavezethető
   a bemenetére. Egy helyben átírt terv esetén az a bemenet már nem létezik,
   tehát a magyarázat sem reprodukálható.

## Döntés

### 1. A terv revíziókból áll, és a korábbi revízió soha nem módosul

Egy `PracticePlan` **revíziók sorozata**. Minden változás — átütemezés,
cél-váltás, nehezítés, a modell javaslatának elfogadása — **új revíziót hoz
létre**, a korábbiak érintetlenül maradnak.

*A tiltás konkrétan:* nincs olyan művelet, amely egy már rögzített revízió
mezőit írja. A revízió írás után **immutable**.

### 2. A végrehajtás eredménye külön artefaktum

Amit a tanuló ténylegesen csinált (`outcome`), **nem a tervbe íródik vissza**,
hanem önálló rekord, amely egy konkrét revízióra hivatkozik. Így a
„terveztük" és a „megtörtént" mindig szétválasztható, és a kettő eltérése
maga is mérhető jel a következő tervhez.

### 3. Az aktuális terv egy MUTATÓ, nem egy állapot

Az „aktuális terv" a legutolsó revízió azonosítója. A váltás egy mutató
átállítása, nem tartalom-módosítás — így a visszavonás (`undo`) is
természetes: az előző revízióra mutatunk vissza, nem visszamásolunk adatot.

### 4. A revízió-lánc oka rögzített

Minden revízió **megnevezi a keletkezésének okát** (`source`: tanulói
átütemezés, rendszer-adaptáció, modell-javaslat elfogadása, cél-változás).
Enélkül a terv-történet olvashatatlan, és nem lehet mérni, hogy a modell-
javaslatok javítottak-e a terven.

## Következmények

- A tárolás **append-only** jellegű; a revíziók száma nő. A tömörítés/archiválás
  külön, későbbi kör kérdése — de a tömörítés sem írhat felül revíziót, csak
  összevonhat lezárt tartományt, dokumentált módon.
- A migráció egyszerűbb: egy régi revízió sosem változik, tehát nem kell
  „félig migrált" állapotot kezelni.
- A modell-javaslat hatása **mérhetővé válik**: a javaslat előtti és utáni
  revízió, plus a hozzájuk tartozó `outcome`-ok összevethetők.
- Az `undo` és a terv-történet UI-ja olcsón megépíthető, mert az adat már
  eleve ilyen alakú.

## Mérce

A revízió-invariánsokat a Kör 2-től épülő domain-tesztek mérik: egy rögzített
revízió módosítási kísérlete **hibát ad**, nem csendes felülírást; az
`outcome` külön entitás, amely revízióra hivatkozik; és a „legutolsó revízió"
lekérdezése mutató-olvasás, nem összefésülés.

Az `E07-R01` maga még nem ír domaint — ez az ADR a határt rögzíti, hogy a
Kör 2 ne kényszerüljön utólagos átalakításra.
