# ADR 0286 — A hiányzó mérőszám nem nulla, és minden diagramnak van szöveges alternatívája

- **Státusz:** elfogadva
- **Dátum:** 2026-08-15
- **Kör:** `E13-R27` (Chapter 13, Kör 27)
- **Kapcsolódó:** [`0283`](0283-results-never-overstate-certainty.md),
  [`0282`](0282-diagram-text-alternative-and-handedness.md)

## Kontextus

Az elemzési eredmény sok mérőszámot mutat, és nem mindegyik áll rendelkezésre
minden felvételhez: van, amit a felvétel jellege nem enged mérni, és van, amit
az adott eredmény-verzió nem támogat. A típusrendszer felől a legolcsóbb
megoldás a `?? 0` — egyetlen karakternyi kényelem, ami a **nincs adatot rossz
eredménnyé** hazudja.

A második buktató az adatvizualizáció. Az idővonal, a hullámforma és a trend
grafikonok felolvasóval némák: az ADR 0282-ben az akkorddiagramra kimondott elv
ide is tartozik.

A harmadik az összehasonlítás. Két session összevetése akkor is „működik", ha
eltérő eredmény-verzióból származnak — csak épp félrevezet, mert a mérőszámok
számítási alapja más.

## Döntés

1. **A hiányzó mérőszám nem nulla.** A „nincs adat" és a „nem támogatott"
   önálló, látható állapot, indoklással.
2. **A confidence minden mérőszám mellett látható** — nem csak az áttekintőben.
3. **Minden diagramnak van szöveges összegzése** (trend, szélsőértékek) és
   bejárható **esemény-lista alternatívája**.
4. **Az idővonal virtualizált** — hosszú felvételnél is használható marad. Ez
   acceptance-kritérium, nem optimalizációs törekvés.
5. **Az összehasonlítás csak kompatibilis adat között indul**, és az
   inkompatibilitás oka megjelenik.
6. A **kijelölésből indított gyakorlás** helyesen paraméterez.

## Következmények

**Pozitív.** A felhasználó tudja, mit mértünk és mit nem. Az analitika
felolvasóval is használható. Az összevetések értelmezhetők maradnak.

**Negatív / ár.** Minden mérőszámnak háromállapotú megjelenítés kell (nincs
adat / alacsony megbízhatóság / mért), és minden diagramhoz szöveges összegzőt
kell írni.

**Amit ez a döntés TILT.** A `?? 0`-t a mérőszám megjelenítésénél; a szöveges
összegzés nélküli diagramot; a nem virtualizált idővonalat; az eltérő verziójú
eredmények összevetését.
