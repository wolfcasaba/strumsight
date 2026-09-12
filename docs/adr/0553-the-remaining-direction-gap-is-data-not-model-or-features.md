# ADR 0553 — A maradék irány-rés ADAT, nem modell és nem jellemző: a frontendhez NEM nyúlunk

- **Státusz:** elfogadva
- **Dátum:** 2026-09-12
- **Kör:** E18-R30
- **Kapcsolódó:** ADR 0552 (a kétszintű döntés), ADR 0551, ADR 0550, ADR 0549,
  `docs/eval/guitarset-strum-baseline.md`, `docs/LESSONS.md` L664–L668,
  `ml/probe_direction_representation.py`

## Kontextus

Az ADR 0552 után a választott konfiguráció (Klangio + GuitarSet, 238 ms) **macro-F1
0,6446**, a többségi alapvonal 0,4468, a Ch14 §7.2 Alpha kapu **0,80**. A rést addig
egyetlen számként kezeltük (0,088 a „lineáris padlóhoz"), de az a padló **más
reprezentáción** volt mérve, mint amit a CRNN megkap. Ez a kör szétszedi, és eldönti,
melyik irányba érdemes következő kört költeni.

## A mérés

### 1. A modell-oldal: nincs rés

238 ms-on, ugyanazon a játékos- és darab-diszjunkt osztáson, **a CRNN saját bemenetén**
(128 log-mel):

```
  lineáris padló a CRNN SAJÁT bemenetén    macro 0,6601   95% CI [0,6088, 0,7108]
  betanított CRNN                          macro 0,6446
```

**0,0155 a rés** — a hibahatáron jóval belül. A CRNN tehát **gyakorlatilag eléri a saját
bemenetének lineáris plafonját.** Több epoch, több paraméter, más regularizáció nincs hova
dolgozzon (és az ADR 0551 D5 már megmérte, hogy a zsugorítás **összeomlasztja**).

### 2. A „szélesebb sáv jobb" megállapítás NEM replikált

Egyetlen osztáson monoton volt: 128 → 8 sáv, 0,6601 → 0,7160. **18 jelölt foldon** (minden
játékos sorra kiemelve, keresztezve a darab-osztás három rotációjával, mindig mindkét
tengelyen diszjunktul; 14 használható):

```
  szállított 128 log-mel     0,6715 ± 0,0828   [0,5552, 0,7845]
  32 sávra poolozva          0,7090 ± 0,0802
  16 sávra poolozva          0,6731 ± 0,0897
   8 sávra poolozva          0,6931 ± 0,1063
  16 geometriai amplitúdó    0,7270 ± 0,0821   [0,5993, 0,8648]   (13 fold)
```

**Nem monoton, és minden érték benne van minden másik szórásában.** Az egy osztáson látott
rendezettség **műtermék** volt.

### 3. A reprezentáció PLAFON, nem padló

Gradient boosting ugyanazokon a foldokon és jellemzőkön:

```
  szállított 128 log-mel, boosted        0,6492 ± 0,1277   (vs 0,6715 lineáris)
  16 sávra poolozva, boosted             0,6490 ± 0,1142   (vs 0,6731)
  16 geometriai amplitúdó, boosted       0,6822 ± 0,1193   (vs 0,7270)
```

**Minden reprezentáción rosszabb, mint a logisztikus regresszió.** Egy erősebb olvasó
**kevesebbet** nyer ki — vagyis túlilleszkedik, és nincs kiaknázatlan nemlineáris
szerkezet. A ~0,73 tehát **plafon**.

### 4. A geometriai reprezentáció előnye NEM bizonyított

Párosítva (ugyanazok a foldok, ugyanazok a söprések), 13 foldon:

```
  átlagos különbség          +0,0636   sd 0,0981   SE 0,0272
  95% CI (normális)          [+0,0103, +0,1170]   ← nullát kizár
  geometriai nyer            9/13 fold
  előjel-teszt (kétoldali)   p = 0,2668           ← NEM utasít el
  a legnagyobb egyetlen fold +0,3096
```

A két teszt **ellentmond**, és ez önmagában az eredmény: a normális CI-t a **farok viszi**
(egy fold +0,3096, miközben 4 fold negatív), tehát a **normalitás-feltevés** a hibás, nem
az eloszlásfüggetlen teszt.

## Döntés

### D1 — A szállított jellemző-kinyerőhöz NEM nyúlunk

A reprezentáció-váltás `ml/features.py`-t **és** a Dart-párját (`crnn_frontend.dart`)
érinti az r134-es paritás-fegyelem alatt: fixtúrák, paritás-tesztek, exportált súlyok,
újratanítás. Ehhez a 2. és 4. pont **nem elég bizonyíték** — a sávszám-hatás nem replikált,
a geometriai előny pedig egy kiugró foldon áll.

Ez nem óvatosság, hanem a saját hibám kijavítása egy körrel korábbról: az előző kör
**egyetlen osztáson** mérte a monoton sávszám-hatást, és ha nem keresztvalidálom, akkor
ebből frontend-csere és egy Dart-paritás kör lett volna — **nulla nyereségért**.

### D2 — A modell-oldal LEZÁRVA

A CRNN a saját bemenetének plafonján van (0,0155, hibahatáron belül), a boosting
mindenhol rosszabb, a zsugorítás összeomlaszt. **Kapacitás-, regularizáció- és
architektúra-javaslatokat ebben az ügyben ezentúl mérés nélkül nem fogadunk el** — a
bizonyítási teher azon van, aki állítja, hogy van még ott hely.

### D3 — Az Alpha kapu NEM érhető el ebből a korpuszból és ebből a geometriából

A legjobb olvasó a foldokon **0,727 ± 0,082**, és erősebb modell rosszabb. A kapu **0,80**.
Tehát a rés **nem finomítási** kérdés.

**A maradék rés ADAT.** És ez nem feltételezés: a korpusz-diverzitás az **egyetlen** emelő,
ami eddig mérhetően **átvitt** (ADR 0552 D2 — a GuitarSet hozzáadása mindkét korpuszon
javított, beleértve az eredeti Klangio-domént). Ma kilenc gitáros van összesen (Klangio 3 +
GuitarSet 6), egyik sem a célhardveren kívül a Klangio telefonos felvételein.

**Következő kör ezért nem modellezés, hanem gyűjtés:**

1. a **user saját telefonos felvétele** — pontos címkék, célhardver, nincs licenc-kérdés,
   és egyszerre lezárja az L660 nyitott tételét (felülszámol-e a motor valódi nyolcadokon);
2. további iránycímkés vagy hexafonikus korpuszok felderítése.

### D3a — Az egy-osztásos mérés ÉHEZTETI a tanítást, tehát a 0,6446 alsó korlát

Ellenőriztem, hogy a GuitarSet **keresztezett** kombinációi (1471 söprés a 3056-ból)
hozzáadhatók-e a tanításhoz. **Nem:** 886 közülük *játékost* oszt a teszttel, 585 *darabot*,
és **egyetlen olyan sincs, amelyik egyiket sem** — a „használható, ha a teszt-fold diszjunkt"
megfogalmazás igaz, de üres.

A vizsgálat viszont egy valódi tételt hozott: az egy-osztásos terv egyszerre **három
játékost és nyolc darabot** tart vissza, a 18-fold CV viszont csak **egy játékost és egy
darabcsoportot**, tehát foldonként **lényegesen több** tanítóadat van:

```
  18-fold CV tanító-méret:  min 1296   median 1635   max 2100
  az egy osztás:                                     1055
```

Vagyis az ADR 0552 **0,6446**-ja azt írja le, amit a konfiguráció **1055 söprésből** tud,
nem a képességét. Ezért a tartalék-teljesítményt **ezentúl foldok fölött** kell jelenteni,
nem egy osztáson — és a szállítható modell a teljes tanítókészleten tanul, miközben a
becslés a CV-ből jön.

### D4 — A kétszintű döntés (ADR 0552) VÁLTOZATLANUL áll

Annak a nyeresége mérve +0,1429, architektúra-költség nélkül, és ez a kör nem érinti. A
bekötő kör továbbra is a következő **építési** feladat; ez az ADR csak azt mondja meg, hogy
**utána** nem a modellen vagy a jellemzőkön kell tovább csiszolni.

## Következmények

- Az irány-fej a jelenlegi adatból **0,6446**-ot tud, a plafon ~0,73, a kapu 0,80 — ezt a
  három számot együtt kell idézni, különben a „még hangolunk rajta" válasz hihetőnek tűnik.
- A mérőeszköz megmarad (`ml/probe_direction_representation.py`), és a **negatív**
  eredményeit a docstringje tartalmazza, hogy a következő kör ne futtassa újra ugyanazt.
- A külső korpuszok **nincsenek verziókövetve** (`ml/data/`, `ml/*.npz` gitignorált), tehát
  elkötelezett riportok, nem CI-kapuk.

## Alternatívák, amiket elvetettem

- **Frontend-csere a geometriai sávokra** (D1): egy kiugró foldon álló +0,0636, az
  előjel-teszt nem utasít el, és Dart-paritás munkát kér.
- **Nemlineáris fej a meglévő jellemzőkön** (D2/D3): mérve **rosszabb** mindenhol.
- **Nagyobb/kisebb CRNN**: a nagyobbnak nincs hova (plafon), a kisebb összeomlik
  (ADR 0551 D5).
- **A sávszám-hatás kiaknázása** anélkül, hogy replikálódott volna: ez pont az a hiba, amit
  ez a kör elkapott.
- **Az Alpha kapu „majdnem elérve" keretezése**: 0,6446 a 0,80-ból, plafonnal 0,73-on. Nem
  majdnem.
