# ADR 0275 — Az ötterületes alkalmazás-shell flag mögött, adapterekkel

- **Státusz:** elfogadva
- **Dátum:** 2026-08-15
- **Kör:** `E13-R08` (Chapter 13, Kör 8)
- **Kapcsolódó:** [`0273`](0273-design-system-token-source-of-truth.md)

## Kontextus

A Chapter 13 célarchitektúrája öt elsődleges terület: Today, Practice, Songs,
Coach, Profile. A repóban mérve **51 `*_screen.dart`** él a jelenlegi
navigáció alatt, és a Ch13 §7.5 **tizenkét legacy route**-ot nevez meg,
amelyekre kívülről (megosztott link, könyvjelző, értesítés) is mutathat hivatkozás.

A teljes információs architektúra egyetlen körben nem migrálható. Ha mégis
megpróbálnánk, a shell és az 51 képernyő tartalmi átalakítása egyszerre bukna
vagy sikerülne — mérni egyiket sem lehetne külön.

## Döntés

1. Az új shell **feature flag mögött** épül, alapértelmezetten **kikapcsolva**.
   A bekapcsolás **user-döntés** (a projekt állandó szabálya: a flag-rollout
   termékdöntés), nem az implementáló köré.
2. Az öt destination első körben **legacy képernyő-adaptereket** mutat. Így a
   navigációs váz külön mérhető a tartalmi migrációtól (Kör 16–35).
3. **Egyetlen legacy route sem törhet el.** Mindegyikhez redirect vagy alias
   tartozik, a deep-link paraméterek megőrzésével. A „ez a route úgysem
   használt" érv nem elfogadható: a kódból nem látszik, mire mutat kívülről
   egy megosztott link.
4. A redirect-térkép **aciklikus** — gépi cella méri, nem szemrevételezés.
5. Stage Mode route alatt nincs elsődleges navigáció.

## Következmények

**Pozitív.** A mai navigáció változatlan marad, amíg a user be nem kapcsolja az
újat. A shell és a tartalom hibái külön mérhetők. A legacy linkek élnek.

**Negatív / ár.** Átmenetileg két navigációs út létezik egymás mellett, és az
adapterek külön kódot jelentenek, amit a migrációs körök végén el kell takarítani.

**Amit ez a döntés TILT.** Az új shell alapértelmezett bekapcsolása; a legacy
route-ok redirect nélküli elhagyása; a tartalmi migráció beszivárgása ebbe a körbe.
