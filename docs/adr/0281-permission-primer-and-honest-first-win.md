# ADR 0281 — Engedély-primer és igazmondó „első siker"

- **Státusz:** elfogadva
- **Dátum:** 2026-08-15
- **Kör:** `E13-R16` (Chapter 13, Kör 16)
- **Kapcsolódó:** [`0276`](0276-stage-scaffold-owns-no-resources.md),
  [`0277`](0277-failure-presentation-model.md),
  [`0279`](0279-consequence-first-confirmations.md)

## Kontextus

Az első indítás két döntést kényszerít ki, mindkettő visszafordíthatatlan
következménnyel:

1. **A mikrofon-engedély.** A rendszer párbeszéde egyszer jelenik meg
   értelmesen; a végleges elutasítás után már csak a beállításokon át van út
   vissza. A kontextus nélkül felbukkanó kérés a leggyakoribb oka a végleges
   elutasításnak.
2. **Az első felismerési élmény.** Az onboarding erős késztetést ad arra, hogy
   a végén mindenképp siker legyen — „hogy jó élmény legyen". Csakhogy a
   StrumSight egyetlen ígérete a felismerés **igazmondása**. Egy hamis
   „Gratulálunk!" az első percben pontosan azt a bizalmat rombolja le, amire az
   egész termék épül.

## Döntés

1. **Nincs engedélykérés kontextus nélkül.** A rendszer-párbeszédet mindig
   megelőzi a primer: mire kell, mi lesz, ha nem adják meg. Végleges elutasítás
   esetén a beállítások megnyitása az akció, nem az újrakérés (ADR 0277 §3).
2. **Az „első siker" nem hazudik.** Gyenge jel vagy bizonytalan felismerés
   esetén a folyamat ezt kimondja és segít (közelebb a mikrofonhoz, csendesebb
   környezet) — nem gratulál. A küszöb a kör mérce-mátrixában **0,60**
   (a határ inkluzív).
3. **A biztonságos mód nem töröl adatot.** Helyreállítási felület, nem gyári
   visszaállítás; ami törlődik, azt a felhasználó kéri tárgy-specifikus
   megerősítéssel (ADR 0279).
4. **A mikrofon a route elhagyásakor felszabadul** (az ADR 0276 folytatása a
   feature oldalán).
5. Az onboarding **visszatérhető és folytatható**, és a régi ellenőrzőpont-
   állapot migrálódik — a meglévő felhasználó nem kezdi elölről.
6. A helyreállítási képernyő hibamegjelenítése **redaktált** (ADR 0277 §1).

## Következmények

**Pozitív.** Kevesebb végleges engedély-elutasítás. Az első élmény hiteles: ha
a felismerés bizonytalan, azt a felhasználó megtanulja értelmezni ahelyett,
hogy később csalódna. A helyreállítás nem jár adatvesztéssel.

**Negatív / ár.** Az onboarding befejezési aránya mérhetően romolhat, mert nem
minden felhasználó ér el valódi sikert az első percben. Ezt tudatosan vállaljuk.

**Amit ez a döntés TILT.** A feltétel nélküli siker-képernyőt; a hidegen
felbukkanó engedélykérést; a biztonságos mód adattörlését; a nyitva maradó
mikrofont.
