# ADR 0549 — A „nem-pengetés" kapu korpusz-függő, és a szállított értéke feljebb kerül (0,439 → 0,85)

- **Státusz:** elfogadva
- **Dátum:** 2026-09-12
- **Kör:** E18-R25
- **Kapcsolódó:** ADR 0512 (a margó-döntés), ADR 0355 (a CRNN-visszaesés),
  `docs/eval/guitarset-strum-baseline.md`, `docs/LESSONS.md` L662, L663,
  `ml/live_3c_threshold.json`, RAG chunk 018

## Kontextus

A szállított 3 osztályos élő modell tanult „nem-pengetés" fejjel rendelkezik, és a
`LiveCrnnStrumClassifier.classifyProbs` **elnyomja a nyilat**, ha
`P(no-strum) > noStrumThreshold`. A küszöb illesztett érték: a modell **saját held-out
eval foldján** az a P(no-strum) kvantilis, ami a **valódi pengetések 95%-át megtartja**
(n=2013), miközben a hamis onsetek 93%-át elutasítja (`ml/live_3c_threshold.json`).

Ez a 95% volt az egyetlen szám, ami a kapu költségéről szólt — és **csak a saját
foldján**. A projekt értékelő korpuszában nincs irány ground truth, tehát a kapu
hatását valódi, független pengetés-anyagon **soha nem mérték**.

## A mérés

[GuitarSet](https://zenodo.org/records/3371780) (CC-BY 4.0), 72 Rock/Funk comping fájl,
8089 annotált esemény, **3035 tiszta söprés**. Az irány-címke a hexafonikus pickup
**húronkénti** hangkezdeteiből származik: a söprés sorrendje maga az irány. A mérőeszköz
validálása (húr-index ↔ hangmagasság, konvenció-egyezés, küszöb-stabilitás) a
`docs/eval/guitarset-strum-baseline.md`-ben.

**Az illesztett kapu erre az anyagra a valódi pengetések 59,6%-át tartja meg, nem 95%-ot.**

Söprés ugyanazon a korpuszon, egy átfutásban (a valószínűségek rögzítve, a kapuk utólag
alkalmazva):

```
  kapu    onset P   onset F1   pengetés-recall   irány macro-F1
  0,439     0,913     0,5828             0,596           0,4192   ← illesztett
  0,650     0,906     0,6013             0,620           0,4235
  0,850     0,899     0,6223             0,649           0,4311
  none      0,701     0,7847             0,955           0,4506
```

Közben kiderült, hogy **két** kapu van egymás mögött, nem egy: a fenti elnyomás, és a
`live_pipeline._isDirectionConfirmed` **margó**-kapuja (ADR 0512). A margó nem mozgató —
ki- és bekapcsolva ±0,0003 az irány macro-F1-en —, és ez a döntés nem nyúl hozzá.

## Döntés

### D1 — A szállított kapu 0,85

`noStrumThreshold = 0.85`. Az illesztett 0,439-hez képest **minden oszlopon jobb**:
onset F1 0,5828 → 0,6223, pengetés-megtartás 0,596 → 0,649, irány macro-F1
0,4192 → 0,4311. A **pontosság** fizet, 0,913 → 0,899: **1,4 pont**.

**Ellenőrizve, nem feltételezve.** A változás után a *független* alapvonal-próba a
szállított úton: onset P **0,900**, onset F1 **0,6224**, pengetés-recall **0,649**, irány
macro-F1 **0,4313** — kerekítésen belül egyezik a söprés jóslatával. A heurisztika-ág
**változatlan** (0,786 / 0,954 / 0,2953), vagyis a változás csak azt érintette, amit
érintenie kellett.

### D2 — A kaput NEM vesszük ki, pedig a recall és az irány ott a legjobb

`none` mellett a pengetés-recall 0,955 és az irány macro-F1 0,4506 — mindkettő jobb. A
pontosság viszont **0,701**: a jelentett pengetések közel három tizede nem párosul
annotált eseménnyel.

Ez nem elvont költség. A tananyag ritmus-pontozásában egy fantom pengetés **olyan slotot
kreditál, amit a tanuló nem játszott** — miközben a kapu eredeti baja épp az ellenkező:
elnyomott pengetés = levonás azért, amit a motor nem hallott meg. **Mindkettő hazugság,
csak ellentétes előjellel**, és a pillér egyiket sem engedheti meg. A 0,85 az a pont, ahol
a mérés szerint az egyik irányba javítunk anélkül, hogy a másikba érdemben rontanánk.

### D3 — Az illesztett érték MEGMARAD, külön néven

`fittedNoStrumThreshold = 0.4387717843055725` a kódban marad, a provenienciájával. Két
okból:

1. Az illesztés **valódi mérés**, saját rekorddal (`ml/live_3c_threshold.json`, amit az
   `ml/train_live_3c.py` ír). A szám helyben felülírása **törölte volna a bizonyítékot a
   számra**, és a JSON-t ellentmondásban hagyta volna a kóddal, anélkül hogy bármi
   megmondaná, melyik a helyes.
2. A jövőbeli modellhez **újra illeszteni kell**, és akkor a recept kell, nem egy
   kézzel beállított konstans.

Őrtesztté is van tűzve, hogy az eltérés **szándékos**: a
`live_crnn_3class_test.dart` pineli mindkét számot és azt, hogy a szállított a
**nagyobb** — így senki nem „rendezi el" a kettőt azzal, hogy visszaszinkronizálja a
konstanst a JSON-ra.

### D4 — A küszöb modell-specifikus, és ez a tanulság nem a számról szól

Az illesztett kapu a **saját** foldján 95%-ot tartott, idegen anyagon 59,6%-ot. Ez nem
egy rosszul kiszámolt szám, hanem egy **korpuszra illesztett döntés, amit korpuszon
kívül használtunk**. Minden új modellnél újra kell mérni, és lehetőleg **nem csak a
saját foldján**. Ezt a RAG chunk 018 rögzíti.

## Következmények

- Több nyíl jelenik meg élesben, és közülük több hamis — **mérve 1,4 pont pontosság**.
- Kevesebb valódi pengetés vész el a ritmus-pontozásból: a megtartás 0,596 → 0,649.
- Az irány-pontosság (0,4313) **továbbra is messze** a Chapter 14 §7.2 Alpha kapu alatt
  (0,80), és messze az [arXiv 2508.07973](https://arxiv.org/html/2508.07973) mikrofonos
  számai alatt (le 85,51 / fel 79,02). **Ez a döntés javít, nem megoldást ad.**
- A nyitott ág változatlan: a cikk közös onset+irány+akkord CRNN-jéhez **nincs
  tanítóadatunk** (a készletük nem publikus, a GuitarSet iránycímkéje levezetett, amit
  tanítás előtt zaj-szempontból minősíteni kell).

## Alternatívák, amiket elvetettem

- **A kapu kivétele** (D2): a legjobb recall és irány, de 0,701 pontosság — fantom
  kreditálás a tanulónál.
- **A konstans helyben felülírása** (D3): törölte volna az illesztés provenienciáját.
- **A margó-kapu hangolása**: mérve nem mozgat (±0,0003).
- **Újratanítás GuitarSeten**: a levezetett iránycímke zaját előbb minősíteni kell, és a
  szintetikus generátorunkról az L660-ban derült ki, hogy átlapolásnál tranzienseket
  gyárt — arra tanítani a saját műtermékeit tanítaná meg.
