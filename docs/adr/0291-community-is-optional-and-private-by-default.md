# ADR 0291 — A közösség opcionális, és alapból privát

- **Státusz:** elfogadva
- **Dátum:** 2026-08-15
- **Kör:** `E13-R33` (Chapter 13, Kör 33)
- **Kapcsolódó:** [`0279`](0279-consequence-first-confirmations.md),
  [`0278`](0278-ai-provenance-is-visible.md)

## Kontextus

A StrumSight magja on-device és egyszemélyes: a felismerés, a gyakorlás és az
elemzés fiók nélkül is teljes. A közösségi réteg erre épül rá — és pontosan
ezért kell élesen elválasztani.

A gyakorlási adat a felhasználó legszemélyesebb tartalma: mit játszik rosszul,
mennyit gyakorol, hogyan hangzik. Egy előre kiválasztott „Nyilvános" közönség
egyetlen félrekattintásból visszavonhatatlan megosztást csinál.

Az offline sor külön kockázat: újrapróbálkozáskor a poszt vagy a komment
duplikálódhat. Ez nem belső hiba, hanem nyilvánosan látható és kínos.

## Döntés

1. **A termék magja közösség nélkül teljes.** Semmilyen alapfunkció nem
   követel fiókot vagy nyilvános profilt; a belépő elutasítása nem zár ki semmit.
2. **Az alapértelmezett közönség nem nyilvános** — sem a profil, sem a poszt.
   A nyilvánosság választás, kimondott megerősítéssel a visszavonhatatlanságról.
3. **A nyers gyakorlási adat nem megy implicit módon.** A megosztás tételesen
   megmutatja, mi kerül ki; a nyers hang alapból nem tartozik bele.
4. **A tiltás azonnal hat, helyben is** — nem kell megvárni a szerver
   megerősítését ahhoz, hogy a tartalom eltűnjön.
5. **Az újrapróbálkozás nem duplikál** posztot vagy kommentet: az offline sor
   idempotencia-kulcsot használ, ami a transzportban él és a felületen nem
   jelenik meg.
6. **Az eltávolított tartalom helyőrzőt kap** — nem tűnik el némán a szálból.
7. **A ranglistára kerülés opt-in** (`E13-R34`): a kihíváshoz csatlakozás nem
   egyenlő a nyilvános rangsorolás vállalásával.

## Következmények

**Pozitív.** A közösségi funkció nem kényszer, és a felhasználó minden
megosztásról tud. A magánszféra az alapállapot, nem a beállítás.

**Negatív / ár.** Lassabb közösségi növekedés: kevesebb nyilvános tartalom
keletkezik, mint alapból nyilvános alapértékkel.

**Amit ez a döntés TILT.** Az előre kiválasztott „Nyilvános" közönséget; a
nyers gyakorlási adat implicit megosztását; a szerver-válaszra váró tiltást; a
kulcs nélküli offline újrapróbálkozást.
