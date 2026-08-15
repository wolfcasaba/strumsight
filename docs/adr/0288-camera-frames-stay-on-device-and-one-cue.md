# ADR 0288 — A képkocka a készüléken marad, és egyszerre egy jelzés szól

- **Státusz:** elfogadva
- **Dátum:** 2026-08-15
- **Kör:** `E13-R30` (Chapter 13, Kör 30)
- **Kapcsolódó:** [`0276`](0276-stage-scaffold-owns-no-resources.md),
  [`0285`](0285-recording-transparency-and-honest-progress.md),
  [`0283`](0283-results-never-overstate-certainty.md)

## Kontextus

A vision-alapú coaching a mikrofonnál is érzékenyebb bemenetet használ: a
képkocka a felhasználó otthonáról készül. Két kísértés jelentkezik.

Az első a **korai kamera-indítás**: az előnézet gyorsabbnak hat, ha már a
beállítás megnyitásakor él a kamera. Ez kérés nélkül készít képet a
felhasználó környezetéről.

A második a **hibakeresés kedvéért mentett képkocka**. Fejlesztés közben
felbecsülhetetlen, és a legérzékenyebb adatot viszi ki a memóriából a
tárolóba.

Külön, használhatósági természetű probléma a **jelzések száma**. A technikai
elemzés több leletet is adhat egyszerre, és mindegyik hasznosnak tűnik. Játék
közben viszont három egyidejű korrekciós jelzésből egyik sem dolgozható fel.

## Döntés

1. **A kamera csak explicit felhasználói akció után indul** — nem a képernyő
   megnyitásakor és nem előnézet céljából.
2. **A képkocka alapból nem mentődik.** A feldolgozás a készüléken,
   memóriában történik; mentés csak explicit felhasználói döntésre, és a
   megőrzés státusza végig látható (ADR 0285 §1 elve a képre).
3. **Egyszerre pontosan egy prioritásos jelzés** látszik: több egyidejű lelet
   esetén a legmagasabb prioritású.
4. **Az alacsony megbízhatóság nem kategorikus** a technikai mérőszámokon sem
   (ADR 0283 §1).
5. **A nem támogatott eszköz csak-hang alternatívát kap** — nem üres képernyőt
   és nem zsákutcát.
6. **A kamera és a mikrofon minden kilépési úton felszabadul**, a háttérbe
   kerülést is beleértve.
7. A **hibakereső csontváz labor-only**: flag mögött, production útvonalon nem
   elérhető.

## Következmények

**Pozitív.** A kamera használata felhasználói döntés marad, és nem keletkezik
képanyag a készüléken. A Stage játék közben is olvasható.

**Negatív / ár.** Az előnézet indítása egy koppintással több; a hibakeresés
nehezebb mentett képkockák nélkül (a labor-only csontváz ezt részben pótolja).

**Amit ez a döntés TILT.** A kamera automatikus indítását; a képkockák
naplózás céljából történő mentését; az egyidejű több jelzést; a hibakereső
felület production elérhetőségét.
