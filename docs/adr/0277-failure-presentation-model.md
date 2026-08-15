# ADR 0277 — A felület hibakódot kap, nem kivételt

- **Státusz:** elfogadva
- **Dátum:** 2026-08-15
- **Kör:** `E13-R10` (Chapter 13, Kör 10)
- **Kapcsolódó:** [`0273`](0273-design-system-token-source-of-truth.md)

## Kontextus

A design system aszinkron állapotokat jelenít meg: betöltés, üres, offline,
sync-várakozás, degradált mód, engedély, hiba, tiltott. A legolcsóbb
implementáció a kivételt közvetlenül megjeleníti (`error.toString()`), különösen
az „ismeretlen hiba" ágon.

Ez háromszorosan rossz. Technikai zajt önt a felhasználóra; néha belső
útvonalat, azonosítót vagy kérés-részletet szivárogtat; és lehetetlenné teszi a
lokalizációt.

Külön hibaosztály az **offline kezelése hibaként**. A StrumSight felismerése
100%-ban a készüléken fut — offline állapotban az alkalmazás nagy része
működik. Aki ilyenkor teljes képernyős hibaállapotot mutat, egy működő terméket
tesz látszólag használhatatlanná.

## Döntés

1. A design system bemenete **failure-kód**, amit egy mapping lokalizált
   prezentációs modellé alakít. Nyers kivétel, stack trace, HTTP-státusz vagy
   `toString()` **soha** nem jelenik meg a felületen — az ismeretlen kód is
   emberi szöveget kap.
2. **Az offline nem hiba-stílus**, és a korábban betöltött tartalom **látható
   marad** fölötte jelzéssel. A képernyő nem ürül ki.
3. A **retry csak újrapróbálható** hibánál jelenik meg. Véglegesen megtagadott
   engedélynél a valódi kiút (beállítások megnyitása) látszik, nem hamis remény.
4. Az engedély-állapot megmondja, **mire kell** és **mi lesz, ha nem adják meg**.
5. Az üres állapot **értelmes következő lépést** kínál — az „nincs adat"
   önmagában zsákutca.
6. A skeleton **nem olvasható tartalomként** (felolvasónak „betöltés"), és
   megtartja a végleges layout geometriáját.

## Következmények

**Pozitív.** Minden hibaüzenet lokalizálható és emberi. Nincs véletlen
információszivárgás a felületen. Az offline használat végig működik.

**Negatív / ár.** Minden új hibakódhoz mapping-bejegyzés és ARB-szöveg kell —
a „csak dobjuk ki a kivételt" út lezárul.

**Amit ez a döntés TILT.** `Text(error.toString())` bármilyen fallbackként;
offline → teljes képernyős hibaállapot; retry nem újrapróbálható hibán.
