# ADR 0278 — Az AI-eredet látható, és nem csak szín

- **Státusz:** elfogadva
- **Dátum:** 2026-08-15
- **Kör:** `E13-R12` (Chapter 13, Kör 12)
- **Kapcsolódó:** [`0277`](0277-failure-presentation-model.md),
  [`0279`](0279-consequence-first-confirmations.md)

## Kontextus

A StrumSight vegyes modell-topológiát használ: a felismerés on-device, egyes
coach- és elemző funkciók viszont felhő-modellt hívhatnak. A felhasználó
szempontjából ez nem stílusbeli különbség, hanem **adatvédelmi tény**: elhagyta-e
az adat a készüléket.

A kártyafelületeken erős a csábítás elrejteni ezt: a provenance-jelölés helyet
foglal, és a kártya „tisztább" nélküle. Ugyanez a kísértés hajtja a
csak-színnel jelölt állapotokat is (confidence pötty, offline pötty) — kevés
hely, gyors implementáció.

A projekt az `E13-R03`-ban már kimondta: az állapot nem jelölhető csak színnel.
Ez az ADR ugyanezt terjeszti ki az AI-eredetre, és a kártya-akciók
kiszámíthatóságára.

## Döntés

1. **Minden AI-eredetű tartalom megmutatja, helyi vagy felhő modell adta.** A
   provenance nem rejthető részletnézetbe.
2. Egyetlen badge jelentése sem támaszkodik **csak színre** — ikon vagy szöveg
   mindig kíséri.
3. A kártya **egésze csak akkor kattintható, ha pontosan egy fő akciója van.**
   Több akció mellett a háttér nem nyel el koppintást, és a beágyazott gomb
   koppintása nem buborékol fel.
4. A skeleton tartja a geometriát és kimarad a semantics fából (az ADR 0277 §6
   folytatása).
5. A kártya-komponensek **nem hívnak AI-t** és nem tartalmaznak üzleti logikát;
   a confidence küszöbeit a felismerési réteg határozza meg, nem a felület.

## Következmények

**Pozitív.** A felhasználó minden AI-tartalomnál látja, hol futott a modell.
A színvak és a felolvasót használó felhasználó ugyanazt az információt kapja.
A kártya-koppintás kiszámítható.

**Negatív / ár.** A provenance-jelölés helyet foglal, és sűrű listákban
tervezési kényszert jelent.

**Amit ez a döntés TILT.** A provenance elrejtését „tisztább kártya" indokkal;
a csak színes állapotjelölést; a több akciót tartalmazó kártya
`InkWell`-be csomagolását.
