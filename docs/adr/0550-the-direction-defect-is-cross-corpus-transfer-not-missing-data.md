# ADR 0550 — Az irány-felismerés defektje ÁTVITEL, nem hiányzó adat

- **Státusz:** elfogadva
- **Dátum:** 2026-09-12
- **Kör:** E18-R27
- **Kapcsolódó:** ADR 0549 (a korpuszra illesztett kapu), ADR 0512 (a margó-döntés),
  ADR 0355 (a CRNN-visszaesés), `docs/eval/guitarset-strum-baseline.md`,
  `docs/LESSONS.md` L660–L665, `ml/probe_direction_headroom.py`, RAG chunk 018

## Kontextus

Három egymást követő kör mozgatott **egy skalárt** az irány-pontosságért:

| kör | amit állított | eredmény |
|---|---|---|
| ADR 0549 | az elnyomó kapu 0,439 → 0,85 | **valódi** javulás, minden oszlopon |
| utána | a le/fel döntési határ eltolása | **nincs** (csak prior-illesztés, L664) |
| — | a margó-kapu (ADR 0512) | ±0,0003, nem mozgató |

Az irány macro-F1 ezután **0,4313** a szállított úton, fel-F1 **0,1905** a tartalék
játékosokon — messze a Chapter 14 §7.2 Alpha kapu (0,80) alatt. A rögzített következő
lépés *„iránycímkés tanítóadat kell, és az a blokkoló"* volt.

**Ez az állítás téves volt, és ez az ADR visszavonja.**

## A mérés

`ml/probe_direction_headroom.py` — sima **logisztikus regresszió** 240 sávösszegzett
jellemzőn, amiket **a modell saját transzformációs geometriájával** vesz
(`ml/features.py`: N_FFT 2048 @ 16 kHz = 128 ms ablak, HOP 160 = 10 ms, 15 frame).
Ground truth a GuitarSet hexafonikus húronkénti hangkezdetei, ugyanazzal a
csoportosítással és `isClean` szűrővel, mint a szállított út mérése. Egy lineáris modell
sokkal tompább egy CRNN-nél, tehát amit elér, az **alsó korlát** a kinyerhetőre.

Játékos- **és** darab-diszjunkt teszten (a GuitarSet minden játékosa ugyanazt a 12
Rock/Funk darabot játssza, tehát a darab-osztás nem luxus):

```
  ág                                    le       fel     macro    AUC
  lo = a modell saját geometriája     0,9152   0,6294   0,7723   0,8928
  hi = 5,8 ms ablak, 3,7 ms hop       0,8335   0,4534   0,6435   0,7900
  SZÁLLÍTOTT CRNN                     0,5848   0,1905   0,3876     —
```

Kontrollok (mind ugyanezen az osztáson): véletlenített címkék **7 magon** AUC
0,4096–0,5905; húrszám **mint egyetlen jellemző** AUC 0,4058; a 3–4 húros, mindkét
osztályból jól képviselt részhalmazon a macro **változatlan** (0,7702). Részletek és a
többi osztás a mérés-dokumentumban.

## Döntés

### D1 — A diagnózis átkerül: ez ÁTVITELI hiba

Az irány-információ **benne van abban, amit a modell már most megkap**, és egy lineáris
olvasó **háromszor** jobb fel-F1-et hoz ki belőle (0,6294 vs 0,1905) ismeretlen
játékoson és ismeretlen darabon. Tehát nem képesség-, nem adat- és nem bemenet-hiány:
a modell **egy korpuszon tanult, és egy másikra nem viszi át**.

Ez **pontosan az ADR 0549 betegsége**, de már nem egy skaláron, hanem **az egész modell
szintjén**. Az ottani tanulság („korpuszra illesztett döntést korpuszon kívül
használtunk") itt megismétlődik nagyban, és ezért nem elszigetelt hiba, hanem minta.

**A korpusz-deficit meg is van nevezve.** A Klangio GST-MM-2025 (`ml/klangio.py`) 82
felvétel, 11767 ütés, 38% felütés — az osztály-egyensúly tehát **jobb**, mint a
GuitarSeté. De `guitarist_of(rid) = str(rid)[0]`, a blokkok `1xxx / 2xxx / 4xxx`:
**három gitáros.** Három emberen nem lehet játékos-invariáns pengetés-timbre-t
megtanulni, és a leave-one-guitarist-out szám sem tudja ezt megmutatni, mert ott is
ugyanaz a három ember, ugyanaz a terem, gitár és mikrofon.

### D2 — A GuitarSet levezetett iránycímkéi TANÍTÓADATKÉNT elfogadva

Az ADR 0549 nyitva hagyta, hogy *„a levezetett iránycímke zaját tanítás előtt
minősíteni kell"*. **Minősítve.** A rajtuk illesztett modell **ismeretlen játékosra ÉS
ismeretlen darabra** általánosít (AUC 0,8928), miközben a véletlenített címkés kontroll
hét magon 0,41–0,59 között van. Zajos címkén ez nem történhetne meg.

A címkék tehát taníthatók, és a 3038 tiszta söprés **hat új játékost** hoz a meglévő
három mellé.

### D3 — Az irány-fejet SZIGORÚAN onset utáni ablakon kell pontozni

Mérve: a **kizárólag onset előtti** hangból az irány AUC **0,7128**-cal megjósolható.
Ez nem mérés, hanem **váltakozás-tipp** — a comping le-fel-le-fel, tehát aki tudja, mi
volt az előző ütés, az ingyen tippel. Egy 128 ms-os, az onsetre centrált ablak **minden**
frame-jében ott van az attack, tehát frame-index szerinti ablációval ez **nem látszik**;
külön ki kell vágni.

**Miért nem engedhetjük meg.** A tananyag mintái **nem váltakoznak**: a `D DU UDU`-ban
két lefelé ütés van egymás után, a `reggae-skank` szinte csak felütés. Egy modell, ami a
váltakozásból tippel, pont ezeken a leckéken mond rosszat — és a tanulónak **pont ott**
mondja a leghatározottabban, ahol téved. Ez ugyanaz a hazugság-kategória, mint a fantom
pengetés az ADR 0549 D2-ben.

A szigorúan onset utáni szám ezért az **őszinte**: macro 0,6645, fel-F1 0,4545, AUC
0,7507 — **még így is messze** a szállított 0,1905 felett. Innentől minden irány-szám
ezen az ablakon értendő, vagy meg kell mondani, hogy nem.

### D4 — A bemenet időfelbontásához NEM nyúlunk

Azzal a hipotézissel indultunk, hogy a 128 ms-os ablak a baj: a tiszta söprések medián
hossza 22,2 ms, a húrok közti késés ~8 ms, és 40,7%-uk két 10 ms-os frame alatt lezajlik.
**A kontrollált kísérlet megbuktatta** — a nagy felbontás *minden* osztáson rosszabb
(0,6435 vs 0,7723). A mikrofonon az irány tehát nem elsősorban a söprés **sorrendjéből**,
hanem a **spektrális egyensúlyból** olvasható, amit a hosszabb ablak stabilabban mér.

A söprés-statisztikák igazak és megmaradnak; csak **nem azt jelentik**, amit hittünk.

## Következmények

- A következő kör a **két korpuszon együtt** tanít, és a becsületes szám a
  **korpuszközi** kiértékelés: az egyiken tanulva a másikon mérni. Ez az egyetlen
  protokoll, ami a most azonosított defektet **nem tudja elrejteni**.
- A szállított eszközön semmi nem változik ebben a körben. **Mérés előbb, változtatás
  utána** — az ADR 0549 azért volt jó döntés, mert a söprés már megvolt hozzá.
- A `docs/eval/guitarset-strum-baseline.md` korábbi záró állítása („nincs iránycímkés
  tanítóadat, az a blokkoló") ott **vissza van vonva**, nem törölve: a téves állítás és a
  javítása együtt többet mond, mint a javítás egyedül.
- Az Alpha kapu (macro-F1 ≥ 0,80) **nem teljesül** és ez a kör sem teljesíti. A lineáris
  alsó korlát 0,7723 (darab-diszjunkt osztáson 0,8279) azt mondja, hogy a kapu **elérhető
  közelségben van** — de csak úgy, hogy a modell azt is kinyeri, amit ma nem.

## Alternatívák, amiket elvetettem

- **Nagyobb időfelbontás a bemeneten** (D4): mérve rosszabb, minden osztáson.
- **További küszöb-hangolás**: kimerült (ADR 0549 hozott, L664 nem).
- **Tanítás a saját szintetikus generátorunkon**: az L660 szerint átlapolásnál
  tranzienseket gyárt, tehát a saját műtermékeit tanítaná meg.
- **Lineáris modell szállítása a CRNN helyett**: a 0,7723 egy *alsó korlát a
  kinyerhetőre*, nem egy szállítható eszköz — nincs no-strum feje, nincs
  élő-út paritás-fixture-je, és a 240 sávösszegzett jellemző nem a szállított
  frontend kimenete. Az értéke a **diagnózis**, nem a termék.
- **Csak a GuitarSeten tanítani**: a Klangio telefon-mikrofonos és a mi telepítési
  körülményünk; elhagyni azt a korpuszt ugyanaz a hiba lenne ellenkező előjellel.
