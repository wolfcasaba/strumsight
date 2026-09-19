# ADR 0559 — A letisztult tier megépült, és szándékosan SÖTÉT: egy fogyasztó nélküli számítás nem kerül a tanuló telefonjára

- **Státusz:** elfogadva (implementáció; a szállított viselkedés **nem változik**)
- **Dátum:** 2026-09-12
- **Kör:** E18-R36
- **Kapcsolódó:** ADR 0556 (a nyíl, D3 = ez a tier), ADR 0552/0554 (a kétszintű döntés),
  ADR 0558 D1 (a szabály, ami majd fogyasztja), `docs/LESSONS.md` L674

## Kontextus

Az ADR 0556 D3 kimondta a kétszintű döntést, az ADR 0558 D1 pedig **megmérte a szabályt**,
ami a letisztult irányt a **pontozásba** vezeti (döntetlen-törő fúzió, `c* = 0,000`). A
szabály a **238 ms-os** tieren mért, tehát bekötés előtt a tiernek **léteznie kell**.

## Döntés

### D1 — A letisztult pillanat DERIVÁLT, nem beírt szám

`LiveCrnnFrontend.framesUntilComplete` a modell geometriájából számol: rés-hossz, `preFrames`,
`modelHop`, FFT-méret. A szállított framinggel (44,1 kHz, hop 256, ablak 1024) **41 frame =
238 ms** — ugyanaz a 238 ms, amin a tier mérve van. A `+1` frame a középpont-kerekítés
tartaléka (a `_buildWindow` a legközelebbi **modell**-frame-re kerekít, ami félhopot, 5 ms-ot
csúsztathat); 5,8 ms késleltetést fizetni a biztos oldal, mert **korán** érkezni épp azt a
nullázást hozná vissza, ami ellen a tier van.

**Megmérve, nem feltéve** (`strum_settled_tier_test.dart`): a letisztult pillanatban a
streamelt ablak **azonos** a teljes jelből számolt referenciával (1e-9), a gyors pillanatban
pedig az utolsó sor **a csend log-mele** — egyetlen konstans mind a 128 melen. A levágás tehát
valódi, és a tier valóban eltünteti.

### D2 — A revízió IRÁNYT revideál, létezést soha

A `StrumRevision` a már bejelentett ütés irányát frissíti. **Nem kreálhat** ütést, **nem
vonhat vissza** egyet, és nem mond semmit arról, hogy történt-e ütés — azt a gyors határidő
eldöntötte, és nem nyitjuk újra.

Az identitás **egész frame-index**, nem időbélyeg. 200 bpm tizenhatodon az ütések ~13
frame-re vannak, a letisztulás 41 frame — **akár három ütés van levegőben**. Egy float-idő
egyezéshez epszilon kellene, és egy elég bő epszilon **átérne a szomszéd ütésre**. Ez pontosan
az ADR 0556 2. csapdája.

**A három csapda mérve:**

| csapda | teszt |
|---|---|
| a revízió nem kreál ütést | egy onset → **pontosan egy** esemény + egy revízió; a heurisztikus út **nulla** revíziót ad |
| nem ír át **újabb** ütést | 3+ ütés levegőben → minden revízió a **saját** `onsetFrame`-jét nevezi, szigorúan növő sorrendben |
| elnyomott onset nem éled újra | elnyomott gyors verdikt → **nincs** esemény és **nincs** revízió; a sín egyszer hívva, másodszor soha |

Plusz a fordított eset: egy **letisztult elnyomás** nem vonja vissza a már bejelentett ütést.
Az esemény minden fogyasztóhoz megérkezett; törlése egy olyan ütést tüntetne el, amit a tanuló
**látott** — a D1 által tiltott látható önjavítás. A gyors verdikt tehát **áll**, és revízió
nem születik.

És a sorrend, ami könnyen elromlott volna: a két várólista közül a **letisztultat** kell
előbb leszívni, mert a gyors ág **visszatér** — egy frame-en egy korábbi ütés letisztult
verdiktje és egy későbbi ütés gyors verdiktje **együtt** eshet be. A teszt ezt nem remélni
hagyja: a rés-környezetet söpri (28/29/30 frame) és **megköveteli**, hogy az ütközés
legalább egyszer bekövetkezzen — ellenkező esetben kiírja, hogy a sorrend sosem lett tesztelve.

### D3 — És a tier SÖTÉT: `settledTier = false` a default

Az élő CRNN-nel a sín mögött a `settleAfterFrames` **41**, tehát a tier bekapcsolása
**ütésenként egy második modell-forwardot** jelent. A `settledRevision`-t **ma senki nem
olvassa**, tehát ez a költség a tanuló telefonján **pontosan semmit nem vásárolna**.

A nagyságrend nem elhanyagolható: ezen a **JIT-es teszt-harnesszen** egy forward
**~29 ms**. **Ez NEM az eszközön mért szám**, és a kettő nem hasonlítható össze (a release
AOT lényegesen gyorsabb) — épp ezért nem állítok on-device értéket. Amit állítok: a duplázás
**nem ingyenes**, a mértéke **ismeretlen**, és 200 bpm tizenhatodon ~13 ütés/másodperc van.

A flag **nem felhasználói kapcsoló**, hanem a sín, ami megakadályozza, hogy egy fogyasztó
nélküli számítás szállítódjon. Azt a kör kapcsolja fel, amelyik (a) **fogyasztja** a revíziót
az ADR 0558 D1 szabályával, és (b) **megmérí a költséget profile-buildben** — ugyanaz a kör,
ami a +0,0723 macro-F1-gyel indokolni is tudja.

Egy teszt **őrzi**: opt-in nélkül nem csak hogy nincs revízió, hanem a második forward **ki
sem megy**.

### D4 — Minden teszt-dublőr kimondja, hogy nincs letisztult tierje

A `settleAfterFrames` a sín **kötelező** tagja, nem default-tal ellátott. Nyolc dublőrt
kellett hozzáírni, és ez szándékos: egy default **csendben** beválasztaná a jövő
osztályozóit a „nincs letisztult tier" értékbe — ami a biztonságos érték, de **elrejti a
döntést**.

Két dublőrnél ez **nem formalitás**: a `guitarset_direction_boundary_test.dart` és a
`guitarset_threshold_sweep_test.dart` rekorderei a **valódi** osztályozóhoz delegálnak és
minden hívást a `calls` listába fűznek. Delegálás esetén a mért futás **ütésenként egy extra
verdiktet** kapott volna, **más levágáson** — pont azt a felvételt rontva el, amiből minden
határ újrapontozódik.

## Következmények

- A bekötő kör (ADR 0558 D1) **indulhat**: a tier megvan, a szabály mérve van.
- A flag felkapcsolása **profile-build mérést** kíván, nem becslést.
- A `StrumEvent` kapott egy `onsetFrame` mezőt. Additív, és az egyetlen építési helye az
  analyzer — a `features/audio_analysis` azonos nevű domain-eseménye **más osztály**, nem
  érinti.

## Amit NEM állítunk

- **Nincs on-device költség-szám.** A ~29 ms JIT-mérés felső korlát és nem átvihető.
- **A tier nyeresége itt nem mérve**; az az ADR 0558 száma (0,6061 vs 0,5262 macro), és
  külön korpusz-mérés, nem ez a kör.
- A `settledRevision` **egy frame-en egy** verdikt. FIFO, tehát sűrű sorozatban egy verdikt
  **késhet** egy frame-et, de **kimaradni nem tud** — ugyanaz a feltevés, amin a gyors tier
  eddig is állt.
