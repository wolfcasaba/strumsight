# ADR 0566 — A kapu költség-kerete korlátos optimalizálás, nem költség-arány; és a költségek fogyasztóit a kódból kell kiolvasni

- **Státusz:** elfogadva (mérés + keret-korrekció; **egyetlen szállított konstans sem mozdul**)
- **Dátum:** 2026-09-12
- **Kör:** E18-R43
- **Kapcsolódó:** ADR 0555 D4 (amit ez **a feltett formájában lezár**), ADR 0549 (az
  illesztett kapu és a 0,85-re állítás), ADR 0556 (a nyíl, **sötét**), ADR 0567 (a
  bekötetlen asset mért megtartása — ugyanebből a körből), ADR 0474 (`kind`-fegyelem),
  `ml/probe_gate_cost_frame.py`, `ml/probe_gate_window_jitter.py`,
  `test/tooling/guitarset_threshold_sweep_test.dart`, `docs/LESSONS.md` L682

## Kontextus

Az ADR 0555 D4 nyitva hagyta a keretet és megnevezte a tankönyvi javítást: mondjuk meg a
`C_FS / C_FP` arányt, vezessük le a küszöböt Chow általánosításából, és riportoljunk
**precision/recall reject curve**-öket (Fischer & Wollstadt 2023).

Ez a kör megmérte azokat a bemeneteket, amiket ez a javítás **igényel** — és a mérés azt
mondja, hogy a javasolt keret **egyik költséget sem tudja kifejezni**.

## Döntés

### D1 — Egyik költség sem lineáris, tehát arány nem fejezi ki őket

**Az elnyomott ütés nem levonás, hanem SZAKADÉK.** A `rhythm_grading.dart` 3. döntése
kimondja: „egy kihagyott slot nem von le semmit" — a `directionAccuracy` érintetlen, csak
a `coverage` csökken. De a `minimumRhythmCoverage` (0,5) alatt a `rhythmAttemptEvidence`
**nulla bizonyítékot** ad vissza, tehát a kísérlet **nem halad**. Egy lépcsőfüggvénynek
nincs „hiba-egységre jutó költsége", amit arányba lehetne tenni.

Egzakt binomiálissal, a **mért** megtartás mellett, egy olyan tanulóra, aki **minden**
ütést eljátszott:

```
  kapu    p(hallva)   4 slot   8 slot   16 slot
  0,439     0,596      0,184    0,180    0,150
  0,850     0,649      0,127    0,107    0,068   <- a szállított kapu
  nincs     0,941      0,001    0,000    0,000
```

A szállított kapun a **hibátlanul eljátszott** 8-slotos kísérletek **10,7%-a** nulla
bizonyítékot ad. És nincs második kapu, amit be kellene kalkulálni: a
`rhythm_practice_screen.dart` minden ütést `isConfirmed: true`-val épít, tehát a
`coverage` **pontosan** a megtartás.

**A szám korpusz-függő, és ezt ki kell írni.** A 0,649-es megtartás mind a 72 GuitarSet
fájlra vonatkozik; a 12 fájlos held-out szeleten ugyanaz az asset **0,758**-at tart meg, és
onnan a szakadék 8 slotnál **0,024**. Tehát a szállított kapu szakadéka
**2,4%–10,7%** között van, attól függően, milyen anyagon mérjük — és mindkét vég **alsó
korlát**, mert a függetlenség optimista: az elnyomás **sorozatos** (halk gitár, csendes
szoba, egy letompított húr), a sorozat pedig többet tol a padló alá, mint a független eset.

**A fantom nem feltétel nélkül kreditál.** A `gradeRhythm` **maximum-kardinalitással**
illeszt, tehát egy lejátszott ütés melletti fantom `extraConfirmedStrokes` lesz
(„jelentjük, de nem vonjuk le"). A kár **feltételes**: nyitott slot kell hozzá — és a
nyitott slotokat épp az elnyomás hozza létre. Mérve, 8 slot 80 bpm-en: a fantomok
**4,7%-a** esik nyitott slot ±50 ms-os ablakába.

```
  kapu    fantom/kísérlet   nyitott-slot fedés   slot-verdikt hamis állítás   P(nincs biz.)
  0,439        0,87              0,0539                  0,047                   0,180
  0,850        1,14              0,0468                  0,053                   0,107
  nincs        7,96              0,0079                  0,063                   0,000
```

És a **kiszorítás** — amikor egy fantom a maximum-kardinalitású illesztésben **elveszi**
a slotot a tanuló valódi ütésétől, és a saját irányát teszi rá — mérve a szállító úton:
a fantomok **1,1–1,5%-a** esik egy annotált esemény ±50 ms-án belül. A bányászott
negatív-korpusz ezt **nem** tudta volna megválaszolni: a `ml/negatives.py` minden
jelöltet kizár egy annotált onset 120 ms-os környezetéből, tehát a dupla-trigger
populáció ott **konstrukció szerint** nincs benne.

**Ezért a keret Neyman–Pearson, nem Chow:** *minimalizáld a hamis állításokat úgy, hogy
P(nincs bizonyíték) ≤ δ* (Tong, Feng & Zhao 2016: az NP-orákulum küszöbe **α-függő**, nem
1/2). Egy skalár költség-arány ezt nem tudja leírni, mert az egyik oldal **lépcső**, a
másik **feltételes**.

**A pedagógia ugyanezt mondja, ellenőrzött forrásból.** Buekers, Magill & Hall (1992,
*QJEP* 44(1)): anticipációs időzítésnél a **korrekt** KR **redundáns** a saját szenzoros
visszajelzéssel — mégis a **hibás** KR befolyásolta a tanulást, és a retenciós tesztek
10 perc / 1 hét / **1 hónap** után is. Egy hamis állítás kára tehát **nem múlik el**, és
nem írja felül egy helyes állítás haszna. *(Amit egy keresési összefoglaló „1:1 és 4:1
arányokról" állított, a fizetős kivonatból **nem tudtam ellenőrizni**, ezért nem
használjuk. És a mi feladatunk **nem** tisztán redundáns: egy kezdő gyakran nem hallja a
saját ütésirányát, tehát a `C_FS` sem nulla.)*

### D2 — A D4 által név szerint kért reject curve-ök, és amit megmutatnak

Held-out GuitarSeten (ismeretlen játékos **és** dallam), a **kevert** folyamon
(pengetések + hamis onsetek), mert ezt látja egy kapu:

```
  kapu    elutasít%   LE pont./recall   FEL pont./recall   macro-F1
  0,124      67,2      0,818 / 0,694     0,245 / 0,255      0,5005
  0,293      63,6      0,797 / 0,717     0,228 / 0,304      0,5079
  0,439      62,3      0,793 / 0,724     0,221 / 0,324      0,5100
  0,850      58,9      0,765 / 0,729     0,206 / 0,363      0,5044
  nincs       0,0      0,731 / 0,729     0,043 / 0,422      0,4038
```

**Kapu nélkül a FEL precizitása 0,206 → 0,043-ra omlik.** Az ok mérve: a kaput túlélő
fantomok **93,8%-át** hívja a modell „fel"-nek (0,85-nál még 50,7%). A laza vég tehát
pontosan azt az osztályt mérgezi, ami a termék differenciátora, és *recall*-ban fizet
(0,363 → 0,422).

**És ez korrigálja a D1 költség-modelljét.** A D1 modell csak a **slot-verdiktet** nézi,
ahol a matcher megvédi a fantomot; a **precizitás** minden fantomot számol. A kettő **nem
ugyanaz a fogyasztó** — ezért van D3, és ezért írja ki a próba, hogy a „nincs kapu" sorait
nem szabad a 3c szakasz nélkül elhinni.

### D3 — A két költség fogyasztóit a KÓDBÓL olvastuk ki, nem az ADR-ekből, és ez fordít

A szállított 0,85 indoklása (`live_crnn_classifier.dart`) két hazugságot tett egymás
mellé. Végigolvasva a fogyasztókat:

| az indoklás állítása | amit a kód tesz |
|---|---|
| „az elnyomott pengetés **levonás**" | **Nem.** `noEvidence` nem von le; a `coverage` esik, és 0,5 alatt **nulla bizonyíték** (D1) |
| „a fantom olyan slotot **kreditál**, amit a tanuló nem játszott" | Csak **nyitott** slotban (4,7%); egyébként `extraConfirmedStrokes`, amit **egyetlen widget sem jelenít meg** |
| a **nyíl**, ami a fantomot a tanulónak megmutatná | A `RhythmLane` a **notált** rácsot rajzolja, és észlelt ütést nem is kap; a `practice_highway` és a `practice_feedback` szintén a **várt** irányt (`CompiledTargetEvent`, `expectedDirection`). Az egyetlen hely, ami **észlelt** irányt mutat, a **megosztó kártya** nyíl-sora. Az ADR 0556 élő nyila **tervezett, de sötét** (`settledTier = false`) |

Vagyis **a költség, ami a kaput szorosan tartja, nagyrészt egy felületet védett, ami ma
nincs**, míg a költség, amit fizet — a 10,7%-os „nem tudom megítélni" — a **ma szállító**
pontozót érinti. A kapu *de facto* egy **aggregált precizitás-küszöb** (D2), nem
slot-verdikt-küszöb, és ezt eddig egyik dokumentum sem mondta ki.

### D4 — `RhythmSlotOutcome.unclear` a produkcióban ELÉRHETETLEN

A `gradeRhythm` négy kimenetet ismer, és az `unclear` („valami történt, de nem
megerősített") **nem fordulhat elő**: az egyetlen produkciós `DetectedStroke`-előállító
(`rhythm_practice_screen.dart:522`) minden ütést `isConfirmed: true`-val épít, mert „a
pipeline csak akkor közöl pengetést, ha az iránya megerősített". A kapu által eldobott
információ tehát nem **degradálódik**, hanem **megszűnik**. Ez nem az itt javítandó hiba,
hanem a D1 szakadék szerkezeti oka: nincs csatorna a „félig hallottam" állapotnak, pedig a
pontozó már tudná fogadni.

### D5 — Semmilyen kapu-konstans NEM mozdul ebben a körben

Két okból:

1. **A keret most változott** (D1/D2/D3). Egy konstans elmozdítása ugyanabban a körben
   összekeverné a két változást — ugyanaz az ok, amiért az ADR 0555 D4 nem ott javított.
2. **A megtartás, amire a küszöb-illesztés hivatkozik, nem a szállított modell
   megtartása** — lásd ADR 0567. Egy kapu újrakalibrálása azon az assetn, amit a következő
   kör ki fog cserélni, kétszer elvégzett és egyszer sem érvényes munka.

Amit a kör **ad** helyette: a `guitarset_threshold_sweep_test.dart` mostantól kiírja a
**produkciós P(no-strum) eloszlását valódi pengetéseken**, tehát egy jelölt kapu
megtartása a **szállító** úton közvetlenül kiolvasható, nem egy Python-kvantilisből
extrapolálva. Ez a bekötő kör műszere.

### D6 — A söprés-eszköz egy sorát duplán számolta, és ez mostantól lehetetlen

A kapu-lista nyolc `(suppress, margin)` rekord, és a tálkák map-je **rekord-érték
szerint** kulcsol. Amikor az ADR 0549 a `noStrumThreshold`-ot **0,85-re** állította, a
listában **már volt** egy `0.85` literál — a két érték-egyenlő rekord **egy** tálkára
esett, a ciklus kétszer futott rá. A szállított sor `kept`-je **8558**-at írt 4279 helyett,
a fantom-szám 862-t 431 helyett. **És semmi nem látszott hibásnak**, mert minden *arány*
olyan osztás, amiben a kettes kiesik.

Javítva: a duplikált literál helyén a `fittedNoStrumThreshold` (provenienciával), plusz egy
`expect`, hogy a kulcsok száma egyezzen a lista hosszával. A tábla most **pontosan**
reprodukálja a független alapvonalat (3789 / 4015 / 4279 / 10106).

### D7 — A mérőeszköz assetje felülírható, és a tábla kiírja, melyiket mérte

Mert a fán **két** 3-osztályos modell van, és egy Python-megtartás meg egy söprés-megtartás
**különböző modelleken** mért szám, hacsak az asset-utat rá nem állítjuk (ADR 0567, L682
§1). Ezért `STRUM_3C_ASSET` környezeti felülírás, a **szállított** asset a default, és a
fejléc kiírja, melyik futott. *(A settled asset nincs a `pubspec.yaml`-ban — az assetek
fájlonként deklaráltak —, tehát nem kerül az APK-ba.)*

## Amit a kör MÉRT, és ami terméki lelet önmagában

**Aki csendesen játszik, többet veszít.** A bányászott negatívok a pitch-alapú annotáció
miatt tartalmazhatnak valódi, de hangmagasságot nem adó csapásokat (tenyér-tompítás, holt
perkusszív ütés), amire a `ml/negatives.py` docstringje maga figyelmeztet. Mérve, a
held-out pengetéseket hangosság szerint decilisekbe osztva:

```
  hangosság-decilis      1 (legcsendesebb)   ...   10 (leghangosabb)
  elnyomási arány             0,147                      0,020
```

**7×-es gradiens.** Ez nem a teljes elnyomást magyarázza (ott 5,6% az összes), de önmagában
terméki következmény: a **kezdő** csendesen és egyenetlenül játszik, tehát pont ő kapja a
legtöbb „nem tudom megítélni"-t. A docstring kikötése — „aki a tompított ütést
**kreditálni** akarja, előbb ezt a halmazt nézze meg" — ezzel mért súlyt kapott.

**Az ablak központozására való érzékenység**, mellékleletként a `probe_gate_window_jitter.py`-ből:

```
  offszet   megtartás .439   .650   .850
   -15 ms        0,936      0,962  0,983
     0 ms        0,938      0,960  0,968
   +15 ms        0,802      0,856  0,892
   +30 ms        0,454      0,529  0,629
```

Erősen **aszimmetrikus**: korán lenni ingyen van, későn lenni katasztrofális — és
fizikailag értelmes, mert az ablak pre-rollja 3 keret (30 ms), tehát +30 ms-nál az attack a
pre-rollba csúszik, ahova a modell csendet tanult. A szállító út **nem** ott van: a
detektor előjeles késése mérve **p50 = −8,3 ms** (korán), p90 = +1,5 ms, és csak **1,4%**
van +30 ms-on túl; a `windowAt` ugyanazt a +2,5 hop attack-korrekciót alkalmazza, mint a
jelentett idő. Ez tehát **nem** aktuális hiba, hanem **kockázati felület**: bármi, ami a
detektor késését növeli (más eszköz, más puffer, más onset-paraméter), itt fizet
aránytalanul.

## Amit NEM állítunk

- **Nincs felhasználói adat.** A 10,7%-os szakadék a mért megtartásból számolt
  binomiális, nem megfigyelt kísérlet-statisztika.
- **A kezdő szobájának fantom-arányát nem mérjük**, hanem söpörjük (0,5×…4×): a
  nyíl-oldal lineáris az arányban, a pontozó-oldal nem, tehát **nincs** olyan
  multiplikátor, ami egyetértésre bírná őket — ez nem egy optimalizálás, hanem kettő.
- **A kiszorítás n=5–9** a szoros kapukon (n=33–34 kapu nélkül): az „1,1–1,5%" a kapu
  nélküli sorból hitelesíthető, a szoros kapuk sorai kis mintán állnak.
- **A Buekers-kísérlet anticipációs időzítés, nem gitár.** Amit átvisz: egy hamis állítás
  kára tartós. Amit **nem**: hogy a korrekt állítás nálunk is redundáns lenne.
- **A D2 reject curve-jei a settled modellen, orákulum-ablakon készültek**, a szállított
  modell in-situ söprése pedig ezzel **ellentétes** irányt mutat a macro-F1-en (0,4192 a
  0,439-en vs 0,4311 a 0,85-ön). Ez **nem** ellentmondás, hanem két kísérlet: más modell,
  más ablak-építő. Összevetni őket pont az a hiba, amit ez a kör egyszer már elkövetett
  (ADR 0567, L682 §1).
- **Az `audio → ablak` szakaszt nincs fixtúra, ami a Python-építőhöz pinelné.** A
  `crnn_live*_parity.json` `windows → probs` (a **hálót**), a `logmel_parity.json`
  `pcm → logmel` (a **kinyerőt** azonos PCM-en), a `crnn_frontend_test.dart` Dart-belső
  geometriát. A kettő együtt **úgy látszik**, mintha az egész utat fedné. Ebben a körben
  megmérve **egyezik** (ADR 0567), tehát ez lappangó fedési hiány, nem aktuális hiba.

## Alternatívák, amiket elvetettem

- **`C_FS / C_FP` kimondása és Chow inverziója** (amit a D4 javasolt): a kalibráció jó
  lenne hozzá (ECE **0,0249** ezen a keveréken, a binek követik egymást), tehát **nem a
  kalibráció** zárja ki, hanem a **lépcső** és a **feltételesség**. Ráadásul a
  küszöb-inverzió *posterior*-állítás, a mi posteriorunk pedig a tanítási priorra
  kalibrált, nem az app prior-jára — külön prior-korrekciót kívánna.
- **A kapu szétválasztása fogyasztónként, most** (a D3 logikus folytatása): nem ebben a
  körben, a D5 2. pontja miatt. A precedens megvan: az ADR 0556 D3 már megengedi, hogy a
  nyíl és a pontozó **különböző** információt hordozzon.
- **A `minimumRhythmCoverage` csökkentése** a szakadék ellen: ez a bizonyíték-küszöböt
  engedné le, nem a motor csendjét javítaná — egy vékony kísérlet kapna jogot állítani.
