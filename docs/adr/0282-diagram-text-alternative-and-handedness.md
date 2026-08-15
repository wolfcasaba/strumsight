# ADR 0282 — Az akkorddiagram szöveges alternatívája és a kezesség

- **Státusz:** elfogadva
- **Dátum:** 2026-08-15
- **Kör:** `E13-R20` (Chapter 13, Kör 20)
- **Kapcsolódó:** [`0280`](0280-accessibility-contract-and-live-region-budget.md)

## Kontextus

A tanulási tartalom jelentős része **grafikus**: akkorddiagram, fogásminta,
fretboard. Ez felolvasóval önmagában néma. A kézenfekvő megoldás — az akkord
nevét semantics labelként megadni — nem elég: a név nem mondja meg, hova kell
tenni az ujjakat. Pont az a tartalom veszik el, amiért a képernyő létezik.

A kezesség ehhez kapcsolódó, önálló buktató. A balkezes megjelenítéshez a rajz
tükrözése kevés: ha a szöveges leírás a jobbkezes húrsorrendet követi, a két
csatorna **ellentmond egymásnak**. Ez rosszabb, mint ha egyáltalán nem lenne
tükrözés, mert a felhasználó nem tudja, melyiknek higgyen.

## Döntés

1. **Minden akkorddiagramnak szöveges alternatívája van** — húr-bund-ujj
   szinten, nem csak az akkord neve. A rajz és a szöveg **ugyanabból a
   forrásból** származik, hogy ne csúszhassanak el.
2. **Balkezes módban a szöveg is tükrözött.** A felolvasott húrsorrend a
   tükrözött elrendezést követi.
3. A **zárolás oka mindig megjelenik** — a puszta „Zárolva" zsákutca.
4. A **hiányzó offline eszköz nem omlaszt**: a képernyő működik és letöltést
   kínál (az ADR 0277 §2 szellemében).
5. A **meglévő haladás megmarad** a migráció után. Ez a migráció legdrágább
   lehetséges hibája.
6. A gyakorlás-akció a megnyitott akkorddal paraméterez — rossz paraméterezés
   esetén a felhasználó némán mást gyakorol.

## Következmények

**Pozitív.** A tanulási tartalom felolvasóval is teljes értékű. A balkezes
felhasználó két egybevágó csatornát kap. A migráció nem veszít haladást.

**Negatív / ár.** Minden diagram-adatnak szöveges leképezést is kell adnia, és
ezt a kezesség szerint kell származtatni — a diagram-modell nem lehet puszta
rajz-leírás.

**Amit ez a döntés TILT.** A puszta akkordnevet semantics labelként; a csak
rajz-szintű tükrözést; az indoklás nélküli zárolást; a haladás nullázását.
