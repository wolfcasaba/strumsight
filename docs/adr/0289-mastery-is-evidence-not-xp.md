# ADR 0289 — Az elsajátítottság bizonyíték, nem XP

- **Státusz:** elfogadva
- **Dátum:** 2026-08-15
- **Kör:** `E13-R31` (Chapter 13, Kör 31)
- **Kapcsolódó:** [`0283`](0283-results-never-overstate-certainty.md),
  [`0286`](0286-charts-need-a-text-alternative.md)

## Kontextus

A fejlődési felület a leghosszabb távú ígéretet teszi a felhasználónak: „ennyit
fejlődtél". A legolcsóbb megvalósítás az XP — az eltöltött idő és a végzett
gyakorlatok pontszáma. Motiválóbb, könnyebb számolni, és mindig van mit mutatni.

Csakhogy az XP a **részvételt** méri, nem a tudást. Aki sokat gyakorol rosszul,
XP-ben haladó, valójában nem. Ha az elsajátítottság XP-ből származik, a
felület pontosan azt hazudja, amit a felhasználó a legjobban szeretne hinni.

Két kapcsolódó buktató: a **trend két adatpontból** (ami zaj, nem irány), és a
**mérőszám-verzió váltása**, ami hirtelen javulásnak látszik, pedig csak a
mérce változott.

## Döntés

1. **Az elsajátítottság mért teljesítményből származik, nem XP-ből.**
2. **A bizonyíték auditálható**: minden elsajátítottsági állítás mögött
   konkrét, megnyitható session áll.
3. **A hiányzó adat nem nulla** (ADR 0286 §1 alkalmazása a fejlődési
   mérőszámokra).
4. **A trendhez minimális adatmennyiség kell** — a kör mérce-mátrixában
   **5 adatpont** (a határ inkluzív). Ez alatt a felület kimondja, hogy még
   nincs elég adat.
5. **A mérőszám-verzió váltása látható a történetben** — nem látszik törésnek
   vagy hirtelen javulásnak.
6. **Az ajánlás tiszteletben tartja a képesség-előfeltételeket**: nem javasol
   olyan gyakorlatot, aminek az előfeltétele hiányzik.

## Következmények

**Pozitív.** A fejlődési szám jelent valamit, és ellenőrizhető. A felhasználó
nem csalódik később abban, amit a felület állított.

**Negatív / ár.** Az új felhasználó sokáig üres vagy „nincs elég adat"
állapotot lát, ami motivációs szempontból gyengébb, mint egy azonnal növekvő
XP-sáv. Ezt tudatosan vállaljuk.

**Amit ez a döntés TILT.** Az XP megjelenítését elsajátítottságként; a
bizonyíték nélküli (vagy sehova nem vezető) állítást; a trendet elégtelen
adatból; a verzióváltás javulásként való ábrázolását.
