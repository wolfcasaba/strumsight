# ADR 0328 — A gamification baseline mért migrációs szerződés

- **Státusz:** elfogadva
- **Dátum:** 2026-08-19
- **Kör:** `E08-R01` (Chapter 9, Kör 1)
- **Kapcsolódó:** [`0289`](0289-mastery-is-evidence-not-xp.md),
  [`0290`](0290-compassionate-streaks-and-idempotent-claims.md)

## Kontextus

Az Epic 8 a már szállított Progress, Streak és Learn állapotból indul. A
storage-kulcs, a régi kulcs és a tényleges JSON-wire alak hiányos vagy
dokumentációból másolt leltára a későbbi migrációban néma adatvesztést okozhat.
Az elvi termékhatárokat a 0289 és 0290 már rögzíti, ezért ez nem új reward- vagy
streak-policy.

## Döntés

1. Az `docs/baseline/epic-08-start.md` a jelenlegi gamification-releváns
   storage-kulcsok, legacy párjaik és wire-formátumaik mért kiindulópontja.
2. A baseline minden tényszerű állítása a szállított kód fájl- és
   sorhivatkozásával készül; a dokumentációval való eltérést nem simítja el.
3. Későbbi Epic 8 migráció az érintett kulcsokkal és formátumokkal a baseline
   ellen vet össze, mielőtt új tárolót ír vagy régit töröl.
4. A baseline nem normatív jutalom- vagy mastery-szabály forrása: ezekben a
   0289 és 0290 elsőbbséget élvez.

## Következmények

**Pozitív.** A migráció auditálhatóan a valós, régi állapotból indul.

**Negatív / ár.** A dokumentumot minden releváns legacy változtatás előtt újra
meg kell mérni; nem válhat egy egyszeri, elavult összefoglalóvá.
