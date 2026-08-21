# ADR 0376 — UI baseline inventory és screenshot-corpus szerződés

- **Státusz:** elfogadva (2026-08-21, E13-R01 pre-flight)
- **Kontextus:** SDD Chapter 13, Kör 1;
  [`docs/rounds/e13-r01-ui-baseline-inventory.md`](../rounds/e13-r01-ui-baseline-inventory.md)
- **Kapcsolódó:** [ADR 0059](0059-central-route-catalogue-and-validated-navigation.md)
  (központi route-katalógus), [ADR 0138](0138-factory-hardening-scope-guard-and-independence.md)
  (exact implementer-scope)

## Kontextus

A Chapter 13 migrációja előtt olyan reprodukálható UI-pillanatkép kell,
amelyből később eldönthető, hogy egy route, képernyő, accessibility-lelet vagy
vizuális állapot szándékosan változott-e. A baseline-kör nem javíthatja közben
a felmért alkalmazáskódot, mert azzal saját kiinduló állapotát írná át.

A korábbi E13-R01 brief csak dokumentációs és inventory-fájlokat engedett,
miközben az SDD hét compact-portrait screenshotot és azok megnyithatósági
tesztjét is követelte. Az E13-R01/H3 self-heal ezt hét exact PNG- és egy exact
validátor-útvonallal oldotta fel, a `lib/**` scope megnyitása nélkül.

## Döntés

1. **Read-only alkalmazásbaseline.** E13-R01 alatt `lib/**` nem módosul. A
   képernyő-, route-, komponens-, token- és accessibility-leltár a méréskori
   production fát írja le; a talált hibák javítása későbbi kör feladata.
2. **Determinista inventory.** Az inventory-generátor rendezett, azonos
   repository-tartalomra azonos kimenetet ad. A production képernyő határa az
   összes `lib/features/**/*_screen.dart`; teszt- vagy fixture-widget nem
   production képernyő.
3. **A központi route-katalógus a route-baseline forrása.** A route-térkép az
   ADR 0059 szerinti `AppRoutes` katalógust és az `app_router.dart` tényleges,
   flag-gelt regisztrációját együtt méri. A dokumentáció a jelenlegi és cél
   route-ok mellett a redirect- és deep-link kockázatot is rögzíti.
4. **Exact screenshot-corpus.** A corpus pontosan a Live, Tuner, Analyze,
   Learn, Library, Settings és onboarding compact-portrait főállapot hét PNG-je.
   Mindegyik fix viewportból, offline/determinisztikus fake-ekkel renderelt
   production screen-widgetből készül; placeholder vagy kézzel rajzolt mock
   nem baseline.
5. **Kétlépcsős screenshot-bizonyítás.** A hordozható teszt az exact fájllistát,
   dekódolhatóságot, pozitív byte- és pixelméretet, valamint portrait alakot
   méri. A független reviewer mind a hét képet ténylegesen megnyitja és a
   dokumentált capture recipe-t a production widgetekkel összeveti.
6. **A baseline nem design-jóváhagyás.** A dokumentáció kifejezetten kimondja,
   hogy a corpus regressziós kiindulópont, nem a Chapter 13 cél-designja.

## Következmények

- A későbbi UI-migrációk diffjei ugyanahhoz a név szerinti corpushoz és
  determinista inventoryhoz viszonyíthatók.
- A kör szándékosan rögzíthet ismert overflow-, semantics- vagy token-adósságot;
  ezek jelenléte nem teszi jóváhagyottá a hibát, csak prioritásos backlogot ad.
- Egy újabb baseline-kép vagy más production útvonal nem adható hozzá némán:
  brief-revízió és új scope-audit szükséges.
- A strukturális PNG-teszt önmagában nem bizonyítja a képek eredetét, ezért a
  manuális, képenkénti független review merge-feltétel.

## Elutasított alternatívák

- **Golden teszt bevezetése ebben a körben.** Elutasítva: platformfüggő pixel-
  baseline-t és frissítési workflow-t hozna a felmérő körbe; az SDD ehhez a
  körhöz megnyithatóságot és nem-ürességet követel.
- **A screenshot-könyvtár teljes engedélyezése.** Elutasítva: a név szerinti
  hét corpus helyett észrevétlenül további képek kerülhetnének a baseline-ba.
- **Talált UI-hibák azonnali javítása.** Elutasítva: megszüntetné a valódi
  kiinduló állapot bizonyíthatóságát és megsértené a kör read-only célját.
