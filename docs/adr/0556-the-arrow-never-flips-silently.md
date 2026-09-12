# ADR 0556 — A nyíl soha nem fordul át csendben: a gyors hívás irányt csak elég margónál mond

- **Státusz:** elfogadva (az ADR 0552 D4 megjelenítési részét **pontosítja**)
- **Dátum:** 2026-09-12
- **Kör:** E18-R32
- **Kapcsolódó:** ADR 0552/0554 (a kétszintű döntés), ADR 0555 (a kapu), ADR 0549 D2
  (a két ellentétes hazugság), ADR 0512 (a margó-kapu), `docs/LESSONS.md` L670

## Kontextus

Az ADR 0552 D4 kimondta a kétszintű döntést: **ideiglenes** irány-válasz a 70 ms-os élő
határidőnél a nyílhoz, **letisztult** válasz ~238 ms-nál a ritmus-pontozáshoz. Azt **nem**
mondta meg, mi történik, ha a kettő **nem egyezik** — és ez nem részletkérdés, mert a
tanuló ezt látja.

A kézenfekvő olvasat: a nyíl megjelenik 70 ms-nál, és ha a letisztult válasz más, **csendben
átfordul**. Ez a kör ezt elveti.

## Amit a kutatás mond (Sonnet 5 agent, 2026-09-12)

**A legközelebbi valódi analóg az élő feliratozás.** Du és mások (CHI 2023, *Modeling and
Improving Text Stability in Live Captions*): a gyors, bizonytalan részleges hipotézis
**látható javítása mért költség** — zavaró, fárasztó, rontja a követést —, **akkor is, ha a
végeredmény helyes**. A kutatók minimalizálandó problémának kezelik, nem semleges
tervezési választásnak.

**A bizalom-irodalom ugyanerre mutat.** Hoff & Bashir (2015, *Trust in Automation*, *Human
Factors* 57(3)): a magabiztosan tévedő, majd magát javító rendszer többet rombol a
bizalomból, mint az őszintén lassabb; és a „cry wolf"-hatás miatt a felhasználó
**leértékeli a gyors jelet**, még akkor is, ha az később megjavul.

**Amit az irodalom NEM dönt el, és ezt ki kell mondani.** A guidance-hipotézis
(Salmoni, Schmidt & Walter 1984; Winstein & Schmidt 1990; Park, Shea & Wright 2000) valódi
és jól megalapozott: az azonnali, gyakori kiterjesztett visszajelzés javítja a gyakorlás
közbeni teljesítményt, de **elnyomja a tanuló saját hibaérzékelését** → rosszabb megtartás.
**De a manipulált változó ott a gyakoriság és a közben/utána volt, MÁSODPERCES skálán** —
senki nem mért 70 ms vs 240 ms-ot. Ez a szakirodalom tehát arról beszél, hogy
*ütésenként vagy frázis után* adjunk-e visszajelzést, **nem arról**, amit itt választunk.
Ugyanígy: a latencia-észlelési irodalom (Ng és mások 2012; Jota és mások 2013; Forch és
mások 2017) szerint **mindkét** késleltetés észlelhető, de ez nem mondja meg, hogy
pedagógiailag káros-e.

**És a gitár-pedagógia** (gyakorlói konszenzus, nem kontrollált kutatás): a pengetés-irányt
**előre begyakorolt motoros szekvenciaként** tanítják, metronómra drillezve — nem ütésenként
javítva.

## Döntés

### D1 — A nyíl SOHA nem fordul át utólag

A látható javításnak mért költsége van a legközelebbi vizsgált tartományban, és a
bizalom-irodalom szerint a gyors jel leértékelődik. Egy gyakorló tanuló **százas
nagyságrendben** lát ütést egy menetben; száz átfordulás nem „részlet".

### D2 — De a pontozás sem mérhet olyan ellen, amit a tanuló nem látott

A naiv alternatíva az lenne, hogy a nyíl az ideiglenes választ mutatja, a pontozás a
letisztultat, és az eltérés **láthatatlan**. Ez **nem kevesebb hazugság, csak rejtettebb**:
a tanuló „le"-t lát, és „fel"-ként kapja az értékelést. Az ADR 0549 D2 két ellentétes
hazugságát ez egy harmadikkal toldaná meg.

### D3 — Ezért: a gyors hívás irányt CSAK elég margónál mond

A megjelenítés szabálya:

1. **Elég margó** a 70 ms-os hívásnál → a nyíl megjelenik, és **ez marad** (a letisztult
   hívás nem írja át a megjelenítést).
2. **Rövid margó** → **irány-semleges ütés-jel**: „ütés volt, az irányt nem mondom".
3. A **letisztult** hívás adja az irányt a **ritmus-pontozáshoz** és az ütem utáni
   áttekintéshez — vagyis oda, ahol nincs latencia-igény és ahol a hamis válasz fáj.

Így **nincs átfordulás**, és **nincs olyan irány-állítás, amit a pontozó megcáfol**: ha a
gyors hívás nem mondott irányt, akkor nem is mondott semmit, amit később meg kellene
tagadni.

**A sín ehhez megvan**, nem kell építeni:

- `StrumPrediction.decision` margó-kapuja (ADR 0512) — ma feltétel nélkül igazat ad
  valószínűség nélküli eseményre, tehát a margó-fogalom létezik és használatlan;
- a **null irány** már most is kibocsát `StrumEvent`-et („kétértelmű pengetés, nem
  nem-pengetés", RAG chunk 018) — vagyis az „ütés volt, de nem mondom meg, merre" állapot
  **ábrázolható**, csak eddig nem használtuk megjelenítési döntésre.

### D4 — Az irány-visszajelzés súlypontja az ütem UTÁNRA kerül

A kutatás egy következtetést **sejtésként** jelölt, amit átveszek, mert a termék saját
premisszájával egyezik: az **irány** olyan dimenzió, amiben a tanuló propriocepciója és
szeme **már erős** — a **időzítés** az, amit nem tud magán észrevenni. A külső visszajelzés
ott ér a legtöbbet, ahol a belső gyenge.

Ezért a részletes irány-visszajelzés (melyik ütésen tévedtél) az **ütem/frázis utáni**
áttekintésbe tartozik, nem ütésenkénti nyíl-korrekcióba. Ez egyúttal a gitár-pedagógia
gyakorlatával is egyezik (minta-drill metronómra, tanári javítás frázis között), és a
guidance-hipotézissel is: kevesebb ütésenkénti kiterjesztett visszajelzés, jobb megtartás.

### D5 — Amit NEM állítunk

A (D1–D4) **tervezési döntés bizonytalanság alatt**, nem bizonyított optimum. Az irodalom
**nem** hasonlította össze a „gyors, néha téves, majd javított" / „lassabb, de helyes" /
„gyors megjelenítés, pontos pontozás" hármast egyetlen motoros készségen sem, pláne nem
pengetés-irányon. A feliratozási és bizalom-bizonyíték **analógia**, nem replikáció.

Ezért: a választást **meg kell mérni a saját tanulóinkon**, megtartásra (másnapi
visszatérés, önkorrekciós képesség), nem csak menet közbeni pontosságra — ez az a
megszerzés-vs-megtartás különbség, amit Salmoni és mások 1984-ben megalapoztak. Amíg ez
nem fut, ez a döntés **indoklással bíró választás, nem eredmény**, és így is kell idézni.

## Következmények

- A bekötő kör (AGENTS.md §9) a D3 szabályát valósítja meg, és három csapdához kell teszt:
  a revízió **nem kreálhat** ütést (`_strumSeq` változatlan), **nem írhat át egy újabb**
  ütést (200 bpm tizenhatodon ~75 ms-ra vannak az ütések, a letisztulás ~240 ms → akár
  három van levegőben), és az **elnyomott onset nem éled újra**.
- A margó-küszöböt (mikor „elég" a margó) **mérni kell**, nem megtippelni: az a pont, ahol a
  gyors hívás irány-pontossága elfogadható. Ez a bekötő kör mérése.
- A `reggae-skank`-szerű leckéken ez különösen számít: ott a gyors hívás a leggyengébb
  (felütés-pontosság 0,26 a 70 ms-os szinten, GuitarSet), tehát gyakran **semleges jelet**
  fog adni — ami helyes, mert a hamis nyíl ott lenne a legkárosabb.
