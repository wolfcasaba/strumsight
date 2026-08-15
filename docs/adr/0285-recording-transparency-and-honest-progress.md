# ADR 0285 — Felvétel-átláthatóság és igazmondó haladásjelzés

- **Státusz:** elfogadva
- **Dátum:** 2026-08-15
- **Kör:** `E13-R26` (Chapter 13, Kör 26)
- **Kapcsolódó:** [`0281`](0281-permission-primer-and-honest-first-win.md),
  [`0283`](0283-results-never-overstate-certainty.md),
  [`0284`](0284-import-preview-is-not-a-commit.md)

## Kontextus

Az elemzési folyamat két érzékeny pontot érint. Az első a **nyers hangfelvétel**:
ez a legérzékenyebb adat, amit a termék kezel, és a felhasználónak a felvétel
pillanatában kell tudnia, megmarad-e vagy csak a származtatott elemzés.
A megőrzés-beállítás a beállítások közé rejtve nem informált beleegyezés.

A második a **haladásjelzés**. Az elemzés hosszú, és a felület üresnek hat
alatta. Ebből születik a legelterjedtebb UI-hazugság: időzítőből animált
százalék, ami nem a tényleges munkából jön. Ugyanaz a hibaosztály, amit az
ADR 0283 az eredményekre már kimondott — magabiztos állítás mérés nélkül.

## Döntés

1. **A felvétel-jelzés állandó**, amíg a mikrofon aktív, és **a megőrzés
   állapota a felvétel közben látható** — nem csak a beállításokban.
2. **Nincs hamis százalék.** A haladás a tényleges szakaszokból jön. Ha egy
   szakasz nem ad haladás-információt, a felület határozatlan jelzést mutat.
3. **A megszakítás idempotens**: kétszer megnyomva sem keletkezik két
   megszakítás, és a folyamat konzisztens állapotban áll meg.
4. **Hiba után nincs árva mikrofon vagy ideiglenes fájl** — minden hibaútvonalon
   takarítunk (az ADR 0284 §2 elve a felvételi oldalon).
5. **A kevés tárhely a felvétel előtt jelzett**, nem a közepén derül ki.
6. **A degradált mód kimondja az okát** (hő, akkumulátor) — nem néma
   teljesítményesés.
7. A **torzítás és a csend külön állapot**, cselekvésre hívó szöveggel.

## Következmények

**Pozitív.** A felhasználó a felvétel pillanatában informált. A haladásjelzés
hihető, mert igaz. A megszakítás és a hibaág nem hagy nyomot a rendszerben.

**Negatív / ár.** A határozatlan jelzés kevesebb megnyugtatást ad, mint egy
kúszó százalék — ezt tudatosan vállaljuk. A szakasz-szintű haladás megkövetel
egy tényleges szakasz-modellt a feladat-életciklustól.

**Amit ez a döntés TILT.** Az időzítőből animált százalékot; a megőrzés-állapot
elrejtését a beállításokba; a takarítás elhagyását a hibaágon.
