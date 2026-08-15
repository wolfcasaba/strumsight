# ADR 0260 — Az evidence nem hordoz nyers médiát, és a fájdalom nem gyengeség

**Státusz:** elfogadva (2026-08-15). Az Epic 7 evidence-modelljének döntése.
Forrás: [`docs/sdd/08-epic-07-ai-practice-generator.md`](../sdd/08-epic-07-ai-practice-generator.md) Ch8 Kör 5.
Épít: [ADR 0254](0254-analysis-run-request-and-v2-runner-wiring.md) §2
(a PCM soha nem lesz dokumentum),
[ADR 0256](0256-practice-plan-revisions-immutable-past.md) (immutable múlt).

## Kontextus

A generátor négy forrásból lát: Learn (lecke-eredmények), Progress
(gyakorlási napló), Analyze (elemzési metrikák) és a tanuló saját jelzései
(kényelmetlenség, fájdalom). Ezeket közös, confidence-aware formába kell
rendezni — és a forma két ponton dönt el sorsokat.

## Döntés

### 1. Nyers média soha nem kerül az evidence-be

Sem hangminta, sem képkocka, sem fájlútvonal a nyers felvételhez. Az evidence
**származtatott mérőszámokat** hordoz, plus a forrás azonosítóját.

Ez az ADR 0254 §2 folytatása: ott a PCM nem lett dokumentum, itt nem lesz
evidence. Az evidence perzisztálódik és exportálható — ami bekerül, az
kimegy az eszközről is.

### 2. A discomfort NEM átlagolódik a teljesítménybe

A kényelmetlenség önálló jelzés, saját skálán, saját mezőben.

*Miért ez a legfontosabb döntés ebben a körben:* ha a fájdalom
beleátlagolódna a teljesítmény-pontszámba, egy fájdalmas gyakorlás **gyenge
teljesítménynek** látszana — és a rendszer logikája szerint **többet**
gyakoroltatna abból, ami fáj. Ez nem elméleti hiba: pontosan így viselkedne
egy közös `score` mező forrás-címkével.

### 3. A deduplikáció kulcsa a forrás outcome ID-ja

Ugyanaz a gyakorlás nem kerülhet be kétszer, akkor sem, ha két adapter is
látja. Nem időbélyeg, nem tartalom-hash — a forrás azonosítója.

### 4. Érzékeny szöveg soha nem kerül naplóba

A tanuló szabad szöveges megjegyzése (pl. a fájdalom leírása) nem naplózható.
A napló azonosítót és kategóriát írhat, tartalmat nem.

### 5. Az elévült evidence nem törlődik, csak elveszti a súlyát

Az elévülés a **lekérdezésnél** dől el (`validUntil`, recency); a tárolóból
nem törlünk automatikusan. A skill-becslő reducernek (Kör 6) látnia kell,
hogy volt régi mérés — különben a „nincs adat" és a „régi adat" állapot
megkülönböztethetetlen. Az ADR 0256 immutable-múlt elvének folytatása.

### 6. Jövőbeli és érvénytelen időbélyeg kontrollált hiba

Jövőbeli mérési időpont, negatív időtartam, `validUntil < measuredAt` → hiba,
nem csendes korrekció. A csendes javítás elrejtené a hibás adapter forrását.

## Következmények

- Az evidence exportálható és megosztható marad anélkül, hogy a felhasználó
  hangja vagy videója elhagyná az eszközt.
- A Kör 6 reducere **két különböző jelet** kap (teljesítmény, kényelem), és a
  fájdalom a nehézség csökkentése felé hat, nem a növelése felé.
- Az „ismeretlen" és a „gyenge" állapot elkülöníthető marad — ez a Kör 6
  külön elfogadási feltétele is.

## Mérce

Az `E07-R05` §6.1 mérce-mátrixa, benne az elévülés három kötelező cellájával
(érvényes / **a határon, inkluzív** / elévült, de a tárolóban megvan) és a
valódi-sértés próbával: a tanuló szabad szövegét a naplóba írva az **A5**
cellának pirosnak kell lennie.
