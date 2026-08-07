# ADR 0187 — Automatic guitar/neck geometry detector: go/no-go

- **Státusz:** Elfogadva (E05-R17 pre-flight, 2026-08-07)
- **Kör:** E05-R17 — Automatikus guitar/neck detector döntési kör
- **Implementer motor:** MiniMax M3 — ezt az ADR-t az orchestrátor (Claude
  Sonnet 5) írta a pre-flightban (ADR 0055, pipeline-prompt §2); az
  implementer a támogató artefaktumokat (harness, manifest, baseline doc)
  szállítja ez ellen a döntés ellen mérve.
- **Epic:** [Chapter 6 — Epic 5: Computer Vision](../sdd/06-epic-05-computer-vision.md)
  Kör 17, §31 (Dataset és annotáció), §32 (Evaluation stratégia)
- **Kontext-ADR-ek:** [0181](0181-vision-manual-calibration-fallback.md)
  (a manual kalibráció a production út — ez a kör ennek a kiváltását
  vizsgálja és utasítja el), [0179](0179-vision-capability-aware-feedback.md)
  (`notObservable` > hamis ítélet elve — ennek a döntésnek a magja),
  [0178](0178-vision-privacy-by-default.md) (kizárólag on-device
  feldolgozás), [0185](0185-vision-hand-landmark-inference-stack.md)
  (falszifikálható újradöntési feltétel mintája, amit ez az ADR követ)

## Kontextus

Az SDD Ch6 §17.1 a manual + tracked geometriát írja elő MVP-nek; a Kör 17
(§2803) egy **külön kérdést** tesz fel: érdemes-e a jövőben egy **automatikus**
guitar/neck detektort építeni, ami a manual kalibrációt (4 sarokpont
kijelölése, ADR 0181) kiválthatná vagy megelőlegezhetné. Az SDD §32.3 ezt
mondja ki a legélesebben: *„A production rollout legfontosabb gate-je nem a
landmark demo látványossága, hanem a hamis technikai feedback aránya."* — egy
detektor tehát nem azon mérendő, hogy lenyűgöző-e egy demóban, hanem azon,
hogy ritkábban téved-e magabiztosan, mint a ma szállított manual+tracked út.

**Ma mérhető korlátok (2026-08-07, `main` E05-R16 után):**

1. **Nincs consentelt gitáros képanyag ebben a környezetben** (a kör-brief
   §2) — az SDD §31.2 explicit consent-, retenciós- és hozzáférés-szabályokat
   ír elő minden emberi felvételhez, ami ma egyszerűen nincs meg.
2. **`AGENTS.md` §9**: „Training nem fut normál fejlesztési körben, hacsak a
   fejezet külön nem írja elő." A Kör 17 SDD-feladatlistája (§2809) valóban
   előírna egy „tanítható megközelítést", de ez **csak a fenti 1. pont
   feloldása UTÁN** válik elvégezhetővé — enélkül a training-lépésnek
   egyszerűen nincs min futnia.
3. **A production geometria útja már él és teszteltnek bizonyult** (ADR
   0181, E05-R10/R11 kézi kalibráció, E05-R16 tracking + hiszterézises
   `CalibrationLossMachine`). Egy új detektor tehát nem egy hiányzó
   funkciót pótol, hanem egy MÁR MŰKÖDŐ út mellé/fölé kerülne — a mérce ezért
   szigorúbb, mint egy „jobb, mint a semmi" összevetés.

Emiatt ez a kör **nem** hoz létre datasetet vagy modellt (a kör-brief §3
tételesen tiltja) — ehelyett a **döntési keretet** rögzíti: mikor lenne
egyáltalán érdemes ezt megpróbálni, mit kellene mérnie egy jövőbeli körnek, és
mi a mérce, ami fölött a kísérlet „production-candidate"-nek minősülhetne.

## Döntés

1. **Alapállás: `experimental-only`.** A gitárgeometria production útja
   **változatlanul a kézi kalibráció + R16 tracking** (ADR 0181). Egy
   automatikus detektor legfeljebb a már deklarált, ma is `false` alapértékű
   `visionExperimentalFineFretEnabled` flag mögött élhet (`lib/app/config/
   feature_flags.dart`) — ezt a flaget az E05-R01 device-mátrix (§2.7) már
   pontosan erre a célra tartotta fenn, ÚJ flag bevezetése tehát nem
   indokolt. A detektor **sosem váltja ki**, csak **felajánlhatja** a
   kalibrációt (ADR 0181 §Döntés 2) — ez a kör ezt a korlátot nem lazítja.

2. **Az átfordítás számmal kötött feltétele — `experimental-only` →
   `production-candidate`.** Egy jövőbeli kör csak akkor javasolhatja a
   detektort `production-candidate`-nek, ha **ugyanezzel a harness-szel**,
   **valós, consentelt, a §31.1 kategóriák szerint diverz** adaton mérve, **a
   következő MINDEGYIKE** teljesül:

   | Metrika | Küszöb | Egység / definíció |
   |---|---|---|
   | mean anchor error | **≤ 0.030** | normalizált `[0,1]×[0,1]` kamera-tér euklideszi távolság a detektált és a felhasználó által megerősített manual anchor-pontok között, frame-enként átlagolva, majd az eval-seten átlagolva |
   | p95 anchor error | **≤ 0.050** | ugyanaz a mérték, 95. percentilis |
   | failure rate | **≤ 0.05 (5%)** | azon frame-ek aránya, ahol NINCS detekció gitár jelenlétekor (false negative) VAGY a detekció anchor error-a > 0,10 (magabiztosan téves) |
   | minimum eval-korpusz | **≥ 200 frame, ≥ 3 különböző gitár, ≥ 2 fényhelyzet, mindkét kezesség** | SDD §31.1 kategória-lefedettség; enélkül a fenti három szám statisztikailag nem értelmezhető |

   **A számok indoklása, nem találomra választva:** a `0.030`/`0.050` a MÁR
   SZÁLLÍTOTT R16 `CalibrationLossMachine` saját hiszterézis-küszöbeiből
   (`degradedDriftBound=0.05`, `lostDriftBound=0.10`,
   `recoveryDriftBound=0.04` — `lib/features/vision/domain/geometry/
   geometry_confidence.dart`) származik, **azonos normalizált egységben**: a
   mean-küszöb (0.030) **0,02-vel a `degradedDriftBound` alatt** marad — vagyis
   egy automatikus detektornak MAGÁBAN, tracking nélkül is jobbnak kell
   lennie, mint amit a rendszer saját maga is „még rendben van"-nak tekint,
   mert ez a hiba a tracking-hibára RÁADÓDIK, nem helyettesíti azt. A
   failure-rate küszöb (5%) az `lostDriftBound`-ot használja a „magabiztosan
   téves" definíciójára, mert ez az a pont, ahol a ma szállított rendszer már
   `lost`-ot jelentene és elnyomná a feedbacket — egy automatikus detektornak
   ennél RITKÁBBAN szabad ugyanoda jutnia anélkül, hogy jelezné.

   Ez a táblázat **rögzített ADR-döntés**, nem egy jövőbeli kör szabadon
   módosíthatja mérés nélkül — újraszámolás csak dokumentált ADR-kiegészítéssel
   (ADR 0185 §Döntés 5 mintája).

3. **Consent kötelező, forrás szerint korlátozott.** Dataset kizárólag
   explicit, dokumentált hozzájárulással gyűjthető (SDD §31.2: cél,
   retenció, hozzáférés-kontroll, törlés, publikálási tiltás). **Tilos
   forrás:** webről gyűjtött vagy más módon ismeretlen jogállású kép,
   harmadik féltől licenc nélkül átvett anyag. A `ml/vision/
   dataset_manifest.md` ezt kategóriánként tételesen rögzíti (implementer
   feladat, ez a kör indítja).

4. **A harness reprodukálható és adat nélkül is determinisztikusan záró.**
   `ml/vision/evaluate_geometry_baseline.py` üres bemenetre `NO_DATA`
   státusszal és definiált, nem-nulla kilépési kóddal áll meg — SOSEM
   nulla-értékű metrikával, mert a „nincs mérve" és a „mérve, és tökéletes"
   összetévesztése pontosan az a hiba, amit a §32.3 false-feedback-gate
   elve kizár. A `--self-test` kapcsoló szintetikus bemeneten bizonyítja a
   metrika-számítást ÉS a fenti táblázat mean-anchor-error határának
   helyes kezelését a küszöb alatt/rajta/fölötte hármason (kör-brief §6.2).

   **A táblázat a `≤` relációt rögzíti (1. pont), tehát a HATÁR a
   MINŐSÍTŐ (jobb/megfelelő) oldalhoz tartozik** — pontosan úgy, ahogy a
   fenti indoklás alapjául szolgáló R16 `CalibrationLossMachine` a saját
   határát kezeli (`isLost => drift > lostDriftBound`: a `drift ==
   lostDriftBound` pillanat MÉG NEM `lost`, a szigorú `>` csak fölötte
   billen át). Ugyanez itt: `0.029` → a mean-tengely önmagában
   **megfelel** (`≤ 0.030`), `0.030` → a mean-tengely **pontosan a
   határon még megfelel** (`0.030 ≤ 0.030`), tehát MINDKETTŐ esetben a
   döntés `production-candidate`, HA a másik két tengely (p95, failure
   rate) is a saját küszöbén belül marad a szintetikus self-testben
   rögzített, megfelelő értéken; `0.031` → a mean-tengely **már NEM felel
   meg** (`0.031 > 0.030`), a döntés `experimental`, függetlenül a másik
   két tengelytől. Egy korábbi szövegváltozat ezt megfordítva írta le
   (a határt a NEM-minősítő oldalhoz kötve) — ez ellentmondott volna a
   fenti `≤ 0.030` táblázatnak és az R16-precedensnek is; a
   `decision()` implementációnak ezt a — jelen — irányt kell követnie,
   nem a korábbi (hibás) leírást.

5. **A hamis geometria kockázata — miért rosszabb, mint ha nincs detektor.**
   A ma szállított útnak van talaja: a manual anchor a FELHASZNÁLÓ saját
   megerősített kattintása, és az R16 tracker minden driftet a **hozzá**
   viszonyítva mér — ha eltér, van mihez képest észlelnie az eltérést, és a
   `CalibrationLossMachine` `lost` állapotban elnyomja a feedbacket (ADR
   0179 elve, E05-R16 BLOCKER-1 javítás után bizonyítva). Egy **teljesen
   automatikus** detektornak a kezdeti (cold-start) detekciónál **nincs
   ehhez hasonló referenciája** — egy szisztematikusan téves, de
   magabiztos kimenet (pl. felcserélt nyak-irány, rossz gitár egy
   többgitáros frame-ben, capo tévesen nutnak olvasva) **csendben
   `available`-ként** viselkedhetne egy teljes sessionön át, és az erre épülő
   fret/string coaching **mérési bizonyíték nélkül találgatna** — ez pontosan
   az, amit `AGENTS.md` §5 kizár („Kamera és AI nem találgathat exact
   string/fret vagy technikai hibát mérési bizonyíték nélkül"). Ez STRUKTURÁLIS
   kockázat, nem a mai detektor-hiány melléktermeke: még ha egy jövőbeli
   detektor a 2. pont számait teljesítené is, **a kimenete akkor is
   kizárólag a manual kalibrációs UI előtöltéseként jelenhet meg, explicit
   felhasználói megerősítéssel** — a `production-candidate` minősítés a
   detektor **javaslat-minőségét** engedélyezi jobbnak minősíteni, nem azt,
   hogy megkerülje a megerősítést. Ez a záró mondat a jövőbeli aktiváló kör
   számára is köti a kezet: megerősítés nélküli automatikus geometria-
   commit ADR-kiegészítés nélkül nem vezethető be.

## Következmények

- A `ml/vision/evaluate_geometry_baseline.py` harness és a fenti táblázat
  **stabil mérce marad** minden jövőbeli detektor-kísérlethez — nem kell
  minden kísérletnél újra kitalálni, mit jelent a „jobb".
- A `docs/baseline/epic-05-guitar-detector-evaluation.md` (implementer
  feladat) a manual kalibráció idő-/hibaköltségét **kontextusként** becsüli
  meg (pl. a device-mátrix ≤30 mp kalibrációs ablak-küszöbéhez viszonyítva),
  de ez **nem módosítja** a fenti 2. pont rögzített számait — a becslés azt
  indokolja, MEGÉRI-e egyáltalán a jövőben erőforrást tenni a kísérletbe, nem
  azt, hogy hol legyen a mérce.
- Amíg nincs valós, consentelt, a minimum-korpuszt elérő mérés, a döntés
  **változatlanul `experimental-only`** marad — ez a kör önmagában NEM nyit
  meg semmilyen production utat, és nem ad hozzá model assetet vagy
  pubspec-függőséget (ADR 0185 §Döntés 3 mintáját követve: aszal nélküli
  függőség hamis haladás-látszatot keltene).
- A `docs/manual-testing/vision-device-matrix.md` §2.7 sorai (már léteznek
  E05-R01 óta) változatlanul a jövőbeli aktiváló kör mérési helye — ez a kör
  nem módosítja a mátrixot, csak a PENDING sorokat jelöli meg a baseline
  dokumentumban, melyik számot kell valós eszközön mérni.

## Elutasított alternatívák

- **A detektor automatikus, megerősítés nélküli geometria-forrássá tétele,
  ha a 2. pont számait teljesíti.** Elvetve: ez pontosan az 5. pontban
  leírt strukturális kockázatot nyitná meg — a numerikus küszöb a
  **javaslat-minőségről** szól, nem a megerősítés kihagyásáról. ADR 0181
  §Döntés 2 ezt már kizárja; ez az ADR megerősíti, nem lazítja.
- **Azonnali „production candidate" vagy „go" minősítés mérés nélkül.**
  Elvetve: nincs consentelt adat ma (Kontextus 1. pont), és az SDD §32.3
  szerint a landmark-demo látványossága nem helyettesíti a hamis-feedback-
  arány mérését. Egy mérés nélküli „ígéretes" minősítés pontosan az a hiba,
  amit a kör-brief §5.1 kizár.
- **`no-go` — a kísérleti út teljes lezárása.** Elvetve: a kör-brief és az
  SDD Kör 17 kifejezetten egy **reprodukálható, jövőben újrafuttatható**
  harness-t és dataset-politikát kér, nem a kérdés véglegesbe zárását: egy
  `no-go` ellentmondana annak, hogy ez a kör maga építi meg az ehhez
  szükséges mérőeszközt. Ha egy jövőbeli mérés tartósan a küszöb alatt marad,
  egy KÜLÖN, mérésekkel alátámasztott ADR-kiegészítés zárhatja `no-go`-ra —
  ez az ADR ezt nem dönti el előre.
- **Web-scraped vagy más ismeretlen jogállású kép a dataset gyorsításához.**
  Elvetve: sérti az SDD §31.2 consent-szabályt és a kör-brief §5.3
  klauzuláját; a `dataset_manifest.md` tiltott-forrás listája ezt tételesen
  kizárja.
- **Felhő alapú (hosztolt) detekciós API.** Elvetve: sérti az ADR 0178
  §Döntés 1-et („a kamerakép feldolgozása kizárólag a készüléken történik,
  raw frame nem kerül hálózatra") — ez nem ennek a körnek a döntése, hanem
  egy már elfogadott korlát, amit egy automatikus detektor nem írhat felül.
- **A küszöbszámokat egy jövőbeli kör szabadon, mérés nélkül újraszámolhatja,
  ha a 2. pont túl szigorúnak bizonyul.** Elvetve: ez pont azt a fajta néma
  mérce-lazítást tenné lehetővé, amit a §32.3 false-feedback-gate elve
  kizár. Újraszámolás csak dokumentált, mért indoklású ADR-kiegészítéssel
  (ADR 0185 §Döntés 5 precedens).
