# ADR 0283 — Az eredmény nem állít többet, mint amit mértünk

- **Státusz:** elfogadva
- **Dátum:** 2026-08-15
- **Kör:** `E13-R22` (Chapter 13, Kör 22)
- **Kapcsolódó:** [`0281`](0281-permission-primer-and-honest-first-win.md),
  [`0278`](0278-ai-provenance-is-visible.md)

## Kontextus

Az eredmény-képernyők erős nyomást gyakorolnak az egységes megjelenítés felé:
minden session után legyen egy szám, minden előzmény-sor legyen összevethető.
A gyakorlás viszont nem mindig mérhető megbízhatóan — gyenge mikrofonjel, zajos
környezet, félbeszakadt session vagy csak-lejátszás mód mellett a mérés
bizonytalan vagy nem is történt.

Ilyenkor egy pontos százalék kiírása **magabiztos hazugság**: a felület
ugyanolyan határozottan állít valamit, mint amikor tényleg mért. A projekt ezt a
hibaosztályt máshol már többször kimondta (ADR 0251 §2, 0253 §3, 0261 §2, 0268):
a néma, magabiztos tévedés veszélyesebb, mint a látható hiba.

Ehhez kapcsolódik a jutalom kérdése. Ha a felület számolja ki a jutalmat a
session adataiból, az eredmény minden újranyitása újabb jutalmat ad.

## Döntés

1. **Alacsony megbízhatóságnál az eredmény nem kategorikus.** Tartomány és
   magyarázat jelenik meg pontszám-ítélet helyett. A küszöb a kör
   mérce-mátrixában **0,60** (a határ inkluzív), egyezően az ADR 0281 §2-vel.
2. **A csak-lejátszás nem kap pontszámot** — a felület kimondja, hogy nem volt
   mérés (`E13-R25` A1).
3. **A részleges session részlegesként** jelenik meg, nem teljesként.
4. **A jutalom a főkönyvből jön**, nem UI-oldali számításból: az eredmény
   újranyitása nem duplikálhat jutalmat.
5. **A sérült előzmény-rekord izolált** — nem omlasztja a listát; a többi
   rekord elérhető marad.
6. Az előzmények **offline elérhetők** (helyi adat).
7. A **következő lépés végrehajtható**: gomb, ami a javasolt gyakorlatot a
   helyes paraméterezéssel indítja — nem puszta tanács.

## Következmények

**Pozitív.** A felhasználó megtanulja, mikor bízhat a mérésben. A jutalom-rendszer
nem inflálódik. Egyetlen rossz rekord nem viszi el az előzményeket.

**Negatív / ár.** Az eredmény-képernyők nem egységesek: néha szám van, néha
tartomány és magyarázat. Ez tervezési többletmunka, és tudatosan vállaljuk.

**Amit ez a döntés TILT.** A pontos százalékot gyenge jel mellett; a becsült
pontszámot csak-lejátszásnál; a jutalom UI-oldali kiszámítását; a részleges
session teljesként való megjelenítését.
