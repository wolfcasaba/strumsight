# ADR 0284 — Az import-előnézet nem véglegesítés

- **Státusz:** elfogadva
- **Dátum:** 2026-08-15
- **Kör:** `E13-R24` (Chapter 13, Kör 24)
- **Kapcsolódó:** [`0279`](0279-consequence-first-confirmations.md),
  [`0277`](0277-failure-presentation-model.md)

## Kontextus

A dal-import **külső, nem megbízható fájlt** dolgoz fel. Az elemző kétféle
leletet ad vissza: figyelmeztetést (a tartalom gyanús vagy hiányos, de
használható) és blokkoló hibát (a fájl nem dolgozható fel biztonságosan).

Két kísértés jelentkezik a felület oldalán. Az egyik az „ideiglenes" mentés:
az előnézet állapotkezelése egyszerűbb, ha a dal már be van írva a tárolóba —
csakhogy onnantól a megszakítás is hagy maga után adatot, és az előnézet
véglegesítéssé válik. A másik a blokkoló hiba felpuhítása: a felhasználó
elakadása kellemetlen, ezért csábító egy „folytasd mindenképp" gomb — ami
pontosan a biztonsági ellenőrzést kerüli meg.

Külön, már mért hibaosztály a `try/catch`-be fojtott írási hiba: a mentés
elbukik, a felület nem szól, és a felhasználó munkája némán elvész.

## Döntés

1. **Az előnézet nem hoz létre tartós rekordot és nem publikál semmit.** Amíg a
   felhasználó nem erősít meg, nincs mentés és nincs kimenő adat.
2. **A megszakítás takarít**: megszakított import után nem marad ideiglenes
   fájl.
3. **A blokkoló hiba nem kerülhető meg.** A figyelmeztetés és a blokkoló hiba
   két különböző dolog, és a felületen is annak látszik. Nincs „mindegy,
   folytasd" út.
4. **A piszkozat mentési hiba után is megmarad** — a szerkesztett tartalom nem
   vész el, és a hiba látható.
5. **A csak olvasható forrás csak másolható**: a felület saját másolat
   készítését kínálja szerkesztés helyett.
6. **A húzás-műveletnek billentyűs/gombos alternatívája van** — a szakaszok
   átrendezése motorikusan korlátozott és felolvasót használó felhasználónak is
   elérhető.

## Következmények

**Pozitív.** A megszakított import nem hagy nyomot. A nem megbízható fájl nem
jut be. A szerkesztő munkája nem veszik el némán.

**Negatív / ár.** Az előnézet állapotkezelése bonyolultabb (memóriában tartott
elemzési eredmény), és a blokkoló hibánál a felhasználó tényleg elakad — ezt
világos magyarázattal kell kísérni.

**Amit ez a döntés TILT.** Az „ideiglenes" mentést az előnézetben; a blokkoló
hiba figyelmeztetésként kezelését; a piszkozat eldobását mentési hiba után; a
kizárólag húzással elérhető átrendezést.
