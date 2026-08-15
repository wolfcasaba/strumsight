# ADR 0290 — Együttérző széria és idempotens beváltás

- **Státusz:** elfogadva
- **Dátum:** 2026-08-15
- **Kör:** `E13-R32` (Chapter 13, Kör 32)
- **Kapcsolódó:** [`0283`](0283-results-never-overstate-certainty.md),
  [`0289`](0289-mastery-is-evidence-not-xp.md)

## Kontextus

A gamifikáció két helyen tud kárt okozni.

Az első a **széria nyelve**. A megszakadt széria tény, de a szokásos microcopy
kudarccá teszi: felkiáltójelek, veszteség-nyelv, sürgetés. Ez rövid távon
növeli a visszatérést, hosszú távon szorongást termel — és a felhasználó a
terméket hagyja ott, nem a rossz szokást. A fizetős széria-visszaállítás
ugyanennek a szorongásnak a monetizálása.

A második a **jutalom kiszámítása a felületen**. Ha a UI számol, az eredmény
minden újranyitása újabb jutalmat ad, offline sorból pedig duplikálódik. A
projekt ezt már kimondta az ADR 0283 §4-ben; itt a gamifikációs felület a
legnagyobb kitett felület.

## Döntés

1. **Nincs büntető vagy bűntudatkeltő széria-nyelv.** A pihenőnap és a türelmi
   idő normális állapot; a széria vége tényközlés, nem ítélet.
2. **A beváltás idempotens, és a felület nem számít jutalmat** — a főkönyv
   use case-ét hívja. Offline állapotban a beváltás sorba kerül, és online
   visszatéréskor **nem duplikál**.
3. **Nincs optimista jóváírás** a főkönyv megerősítése előtt (ugyanaz a mért
   hibaosztály, mint a beállítás-szinkronnál: az elnyelt írási hiba néma
   eltérést hagy).
4. **A jutalom forrása auditálható** — a felhasználó megnézheti, mit miért kapott.
5. **Nincs fizetős megőrzés (pay-to-preserve).**
6. **Az eredmény feltétele érthető és teljesíthető** — nincs rejtett kritérium.
7. **Az ünneplésnek van csökkentett mozgású alternatívája**: a visszajelzés
   megmarad, más modalitásban.

## Következmények

**Pozitív.** A rendszer nem szorongásra épít. A jutalom-egyenleg konzisztens a
főkönyvvel. A gamifikáció csökkentett mozgás mellett is működik.

**Negatív / ár.** A visszatérési mutató valószínűleg alacsonyabb, mint agresszív
széria-mechanikával; és egy monetizációs út (megőrzés-vásárlás) zárva marad.

**Amit ez a döntés TILT.** A veszteség-nyelvet a szériánál; az optimista
jóváírást; a jutalom UI-oldali kiszámítását; a fizetős visszaállítást.
