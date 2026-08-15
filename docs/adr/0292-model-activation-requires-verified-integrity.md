# ADR 0292 — Modell csak igazolt integritással aktiválható

- **Státusz:** elfogadva
- **Dátum:** 2026-08-15
- **Kör:** `E13-R35` (Chapter 13, Kör 35)
- **Kapcsolódó:** [`0287`](0287-no-automatic-tool-execution-in-the-tutor.md),
  [`0279`](0279-consequence-first-confirmations.md)

## Kontextus

Az offline AI modellkezelő letöltött binárist aktivál. Egy hamisított vagy
sérült modell mindent lát, amit a mikrofon — ez a termék legmagasabb tétű
bizalmi döntése.

A szokásos felpuhítás így hangzik: az ellenőrzés elbukott, de mutassunk
figyelmeztetést és hagyjuk, hogy „a felhasználó döntsön". A felhasználónak
azonban nincs eszköze eldönteni, hogy egy ellenőrzőösszeg-eltérés hálózati hiba
vagy támadás — a döntés áthárítása itt nem tisztelet, hanem a felelősség
elhárítása.

Ugyanebbe a körbe tartozik a **beállítás-szinkron** mért hibaosztálya: a
`try/catch`-be fojtott felhő-írás után a felület „Mentve"-t mutat, miközben az
adat elveszett. A projekt ezt már megmérte, és a szabály azóta él: szinkronizált
jelölés csak szerver-megerősítés után.

## Döntés

1. **Hibás vagy hiányzó integritás-igazolás esetén a modell nem aktiválható.**
   Nincs „aktiváld mégis" út.
2. **A beállítás csak szerver-megerősítés után jelölhető szinkronizáltnak.**
   Sikertelen írás után a felület jelzi a függőben lévő állapotot és újrapróbál.
3. **A fiók opcionális**: a bejelentkezési képernyőről mindig van „fiók nélkül
   tovább" út, és a hitelesítési hiba nem szivárogtat technikai részletet.
4. **Az adatvédelem nem rejtett**: a leltár, az export és a törlés a beállítások
   felső szintjéről elérhető.
5. **A megosztás alapból minimális adatot visz** — a redakció az alapállapot, a
   felhasználó **bővíti**, nem szűkíti; a felület tételesen mutatja, mi kerül ki.
6. **A destruktív adatművelet explicit és auditálható**: az export és a törlés
   feladatként jelenik meg, állapottal és eredménnyel, az ADR 0279
   következmény-központú megerősítésével.

## Következmények

**Pozitív.** Hamisított modell nem lép működésbe. A beállítás-vesztés láthatóvá
válik. A megosztás alapértéke a védelem.

**Negatív / ár.** Hálózati hiba miatt megszakadt letöltés után a felhasználónak
újra kell töltenie, és nincs kézi megkerülő út — ezt világos magyarázat kíséri.

**Amit ez a döntés TILT.** Az „aktiváld mégis" utat hibás ellenőrzésnél; az
optimista „Mentve" feliratot szerver-megerősítés nélkül; az alapból teljes
adatot vivő megosztást.
