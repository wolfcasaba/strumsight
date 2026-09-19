# ADR 0548 — A fül-rung: az időzítés a demonstrációból jön, az IRÁNY a pendulumból

- **Státusz:** elfogadva
- **Dátum:** 2026-09-12
- **Kör:** E18-R21
- **Kapcsolódó:** ADR 0545 (nincs váltás-időzítés pontszám), ADR 0546 (a pulzus
  csatornája), `docs/LESSONS.md` L660,
  `docs/research/strumming-direction-pedagogy-2026-09.md`,
  `docs/superpowers/specs/2026-09-11-gamified-curriculum-design.md` §3

## Kontextus

A négy ritmus-mód közül a negyedik, a `listenAndRepeat`, **deklarálva volt és
játszhatatlan**: `demonstratesFirst: true`, `showsArrowRow: false`, és egyetlen rung
sem használta. Az ADR 0546 már megmérte, miért nem egysoros a bekötés — az app nem
játszhat hangot, amíg pontoz (16 klikkből 15 jelentett pengetés) —, tehát a
demonstrációt és a kísérletet **időben** el kell választani.

De volt egy ennél erősebb, pedagógiai ellenvetés, és ezt kellett előbb eldönteni.

## Az ellenvetés, és miért nem áll

A mód elveszi a nyílsort. Az app egyetlen hangja a klikk. **Egy klikk nem tudja
közölni, hogy az ütés LE vagy FEL volt** — miközben pont ez az, amit a pillér pontoz.
Elsőre ez úgy néz ki, hogy a mód vagy hamis (irányt kér, amit nem adott meg), vagy
értelmetlen (irányt nem pontoz, és akkor nem a pillér része).

Az ellenvetés feloldódik, és ugyanazon a szabályon, amin a rács áll. Folyamatos
pengetésben **az irány nem szabad információ**: az ütemre eső ütések lefelé, az „és"-ek
felfelé mennek, mert a kéz inga módjára jár és nem áll meg
(`docs/research/strumming-direction-pedagogy-2026-09.md`).

És a **fülre tanulásról** szóló források pontosan ezt a munkamegosztást írják le: keresd
meg az *ismétlődő* ritmikai ötletet, kopogd ki, majd mondd ki semleges szótagokkal —
kifejezetten **anélkül**, hogy eldöntenéd, melyik szótag melyik ütés. Amit a fül ad, az
a **MIKOR**. Az irányt a pendulum adja.

Ebből két döntés következik, nem részlet.

## Döntés

### D1 — A klikk NEM kódol irányt

Egy magasabb hang, ami „fel"-et jelent, olyan jelzést tanítana, ami a gitáron **nem
létezik**. Az akcentus az ütem 1-es ütését jelöli, ami metrum, és a metrum igaz.
Őrteszt: `rhythm_demonstration_test.dart` külön cella arra, hogy egyetlen felütés sem
szól máshogy.

### D2 — A mód CSAK pendulum-rácson őszinte, és ezt a konstruktor visszautasítja

Ha egy rács megütött irányai eltérnek a pendulumtól — a tanított 3/4-es valcer
jogosan ilyen —, akkor a demonstráció az időzítést hordozza, és az eltérést **semmi**,
mert épp a notációt vettük el. Ott irányt pontozni azt jelentené, hogy a tanulót olyan
információért büntetjük, amit soha nem kapott meg.

Ezért a `RhythmAssignment` konstruktora **kidobja** a `!showsArrowRow &&
!followsPendulum` kombinációt. Általánosan fogalmazva, nem a `listenAndRepeat`-re
szabva: a tiltás arról szól, hogy *rejtett notáció csak levezethető irányt kérhet*. Az
authored rácsok maguk **nem** tiltottak — az a valcert nevezné hibásnak.

### D3 — Az idővonal: két demó ütem, EGY CSENDES ütem, majd a beszámolás

```
| demó 1 | demó 2 | CSENDES ütem | beszámolás | 1. ütem ... (pontozott)
```

**Két demó ütem, nem egy.** A források első lépése az *ismétlődő* ötlet felismerése; egy
egyszeri bemutatás nem ad mit ismétlődőként felismerni.

**Egy csendes ütem, a metrumon.** Két független indok, és az első önmagában is elég:
egyetlen klikk-színnel a demonstráció és a beszámolás **egybefolyna** — egy
negyed-mintánál szó szerint azonosak lennének, tehát a tanuló nem hallaná, hol ér véget
a „hallgasd" és hol kezdődik a „játszd". És megtartja a pulzust, amit a demonstráció
épp felépített; egy metrumon kívüli szünet azt törné el.

**MÉRVE** (`test/features/live/demonstration_preroll_test.dart`), kontrollal — ugyanaz
az előadás ugyanazokon az absztolút időpontokon, egyszer hangzó, egyszer néma
pre-rollal:

```
notated strokes : 24
pre-roll ON  : reported 39, dropped before bar 1: 15, scored 24
pre-roll OFF : reported 24, scored 24
```

A pre-roll **15 ütésként hallatszik** (az ADR 0546 eredménye ezen az idővonalon), **mind
kívül esik** a kísérleten és a meglévő `countsTowardAttempt` dobja el, és a kísérlet
**azonosan** hallatszik — minden ütés 5 ms-on belül. A megnevezett kockázat — hogy húsz
klikk **átállítja az adaptív onset-küszöböt**, és a tanulót a saját demonstrációja által
felemelt küszöbhöz mérjük — így mérve van, nem kibeszélve. Új mechanizmus nem kellett.

### D4 — A `needsMetronome` igazra javítva, és a haptikus pulzus az, ami ezt ingyenessé teszi

A mód `needsMetronome: false`-szal volt deklarálva, **a pontozás megírása előtt**. A
kísérletet fix tempón, 50 ms-os ablakban, rácsra helyezve pontozzuk — tehát a pulzus
megvonása nem tisztábbá tenné a feladatot, hanem **a tanuló tempó-elcsúszását és a
mintáját EGYÜTT** mérné, és egy bukás értelmezhetetlen lenne. Pont az az ok, amiért az
ADR 0545 a váltás-időzítés pontszámot elvetette.

Ez itt azért nem kerül semmibe, mert a pontozott ütemek pulzusa **haptikus** (ADR 0546
D1): az érzett ütés a **pulzust** hordozza, a **mintát nem**, tehát nem szivárogtatja ki
azt, amit a fülnek kellene szállítania.

### D5 — A demonstráció alatt a metronóm HALLGAT

Nem biztonságból — itt semmi nincs pontozva —, hanem mert a demonstráció ütései **maguk
is klikkek**, és egy ugyanolyan színű ütem-klikk rájuk rétegezve **olvashatatlanná**
tenné a mintát: a tanuló nem tudná, melyik klikk volt ütés és melyik a pulzus.
`CurriculumPulsePhase.demonstration` → `CurriculumPulse.none`.

### D6 — A `showsArrowRow` most tényleg be van kötve, és a LENGÉS nem notáció

A mező deklarált volt és **a képernyő nem olvasta**. Két dolgot kellett szétválasztani:

- a **sáv** (`RhythmLane`) a notáció → `showsArrowRow: false` mellett **nem renderelődik**;
- a **pendulum** a kéz mozgása → renderelődik, de **minden átmenet szellem**.

A lengés maga nem notáció: adott felosztásnál minden mintára azonos, és a tanulónak
mindenképpen meg kell tennie. Hogy **MELYIK** átmenet üt, az viszont maga a minta —
megjelölve visszaadná, amit a mód elvett, és a fül-rungot **végignézéssel** lehetne
teljesíteni.

### D7 — A rung: ugyanaz a minta, megtompítva, a ritmus-pillér végén

`mission.byEar` a `level.byEar`-ban, közvetlenül a `mission.dDuUdU` után, saját
skillel (`rhythm.byEar`). Ugyanaz a `D DU UDU` — **semmi új a játékban**, csak a kapaszkodó
elvéve, ami a kurzus „egy új hiba-lehetőség rungonként" elve. **Tompítva**, mert az új
dolog a fül: a damp kiveszi az akkordot mint zavaró tényezőt, és akusztikailag is illik
a demonstrációhoz — egy tompított ütés perkusszív, mint a klikk.

Saját skill, nem több bizonyíték a `strumPattern`-re: egy hallott minta visszajátszása
**más képesség**, mint egy notált eljátszása. A **metrika** ugyanaz
(`rhythm.directionAccuracy`, a `rhythm.` névtér routolja), a feladat nem.

## Következmények

- A négy deklarált ritmus-módból mind a négy **játszható**. A pillérnek van záró rungja,
  amit nem lehet olvasással teljesíteni.
- A létra 14 rungról **15**-re nőtt.
- Ha a metronóm némítva van, a demonstráció is néma — és akkor **nincs mit visszajátszani**.
  Ez szándékos, nem félmegoldás: a némítás egy kapcsoló (ADR 0546 D3), és hangtalan
  demonstráció után mintát pontozni azt jelentené, hogy olyat kérünk, amit nem adtunk meg.

## Alternatívák, amiket elvetettem

- **Irányt kódolni a klikk magasságával.** Ez tanítana valami hamisat (D1), és pont azt
  a standing constraintet sértené, ami miatt ez a pillér egyáltalán mérésre épül.
- **A `needsMetronome: false` betartása.** Értelmezhetetlen pontszámot adott volna (D4).
- **A pendulumot is elrejteni.** A kéz mozgása nem notáció, és egy álló inga a tanulót
  hideg karral indítaná az 1. ütemre — pont az, amit a beszámolás megelőz.
- **Csendes ütem nélkül.** Egy negyed-minta demonstrációja és a beszámolás azonos lenne.
