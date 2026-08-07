# E05-R15 — Review

Brief: `docs/rounds/e05-r15-guitar-coordinates-and-homography.md`
Diff: `git diff bf3960a..13dc79b` (branch `minimax/e05-r15-guitar-coordinates-and-homography`)
Reviewer: Claude Sonnet 5 · Dátum: 2026-08-07 (frissítve a dedikált
security-review után, majd a MiniMax javító kör 1 független
újra-ellenőrzése után, mindhárom ugyanaznap)
Verdikt: **CHANGES REQUIRED — javító kör 1 UTÁN is (BLOCKER-1 részlegesen
nyitva, ld. „Javító kör 1 eredménye" lent); motor-eszkaláció Codexre**

## Összegzés

**BLOCKER: 1 · MAJOR: 2 · MINOR: 3 · NOTE: 4**

Az implementer (MiniMax M3) jelzése `done`, „round-gate 8/8 ZÖLD" — ez a saját
munkapéldányában futott, tehát önmagában nem bizonyíték (AGENTS.md §15.1).
Egy teljesen friss `/tmp` klónban **függetlenül újrafuttatva a gate 8/8 ZÖLD
maradt** (lásd lent) — ez a mérce valódi bizonyítéka. Egyik nyitott lelet sem
a gate-en bukik el — mind tartalmi/lefedettségi hiány, amit a gate
szerkezetileg nem tud elkapni. A BLOCKER a dedikált security-review
(risk=high, AGENTS.md §15.1) során került elő, és a saját, független
próbámmal más véletlen-paraméterekkel is megerősítve — ez a legsúlyosabb
lelet, súlyosabb, mint amit a funkcionális pass önmagában talált volna.

## Javító kör 1 eredménye (MiniMax M3, `20a67c1` → `ef6fc57`)

**MAJOR-1 ZÁRVA, MAJOR-2 ZÁRVA, BLOCKER-1 CSAK RÉSZLEGESEN.** Friss `/tmp`
klón, gate 8/8 ZÖLD (`format`/`analyze`/mindhárom teszt-scope/
`architecture`/`secrets`/`l10n`, csonkítatlan artefaktumként újrafuttatva).

- **MAJOR-1 ✅ ZÁRVA.** `polygon2.dart:112-117` — az `.abs()` eltávolítva,
  a nevező előjeles `(b.y - a.y)`. Saját próba (rombusz, fordított
  csúcssorrend, döntött quad, két triviálisan kívüli pont) mind az öt
  esetben helyes eredményt ad. A javító kör commitja: `23008c6`.
- **MAJOR-2 ✅ ZÁRVA.** Két új, python3-referenciával alátámasztott teszt
  (`side`/`top` nézőpont, mindkettő `cond(2×2)=1600 > 1e3` →
  `conditionNumberExceeded`) — legitim, dokumentált elutasítás (a brief §9
  szellemében, nem hiányzó munka). A javító kör commitja: `89f1a9f`.
- **BLOCKER-1 ⚠️ RÉSZLEGES — ÚJRA NYITOTT.** A javítás (`7ceef3e`) az
  `apply()` KIMENETI magnitúdóját mintázza 5 kanonikus ponton (4 sarok +
  középpont) — ez VALÓDI, mérhető javulás (a saját véletlen-keresésem,
  UGYANAZZAL a seeddel/paraméterekkel mint a security-review előtti próba,
  323 340 → **95 119** találatra csökkent, és 16 281 kalibrációt most
  helyesen elutasít), **DE nem zárja le a rést**: 33 174, a guard-ot
  átjátszó mapper közül **95 119 rácspont-minta** adott továbbra is
  `|uv|>10` kimenetet `>0,5` confidence mellett, legrosszabb eset
  `923 643` nagyságrendű `uv`. **Gyökérok:** az `apply()`-KIMENET
  mintavételezése nem elegendő, mert a kimenet (számláló/`w` hányados) NEM
  affin függvény — 5 pont bármelyikén lehet kicsi a kimenet, miközben a
  `w=0` „eltűnő egyenes" a mintapontok KÖZÖTT metszi a `[0,1]²` tartományt.

  **Matematikailag TELJES, saját próbával validált javasolt javítás:** mivel
  `w(x,y) = h6·x + h7·y + h8` (a homogén nevező) MAGA affin, egy affin
  függvény értéke bármely belső ponton a sarok-értékek konvex kombinációja
  — tehát ha a 4 sarkon `w` AZONOS előjelű és egyik sem közel nullához
  (a `h[8]=1` kanonikus skálához képest), a `[0,1]²` tartomány EGYETLEN
  pontján sem közelítheti a nullát (a minimum `|w|` a tartomány felett
  bizonyíthatóan a sarok-minimum). Ezt saját, 50 000 próbás kereséssel
  (UGYANAZZAL a seeddel) validáltam a jelenlegi guard-ot átjátszó
  mapperek felett: **0 hamis negatív** (minden talált blowup-esetet a
  `w`-alapú ellenőrzés is elutasított volna), 9 623 valódi találat, 22 653
  helyesen átengedett eset, 795 (≈3,4%) enyhén túl-szigorú eset (ami a
  SAJÁT 11×11-es rács-mintavételem korlátja miatt lehet hamis pozitív is —
  a valós ráta valószínűleg ennél alacsonyabb). A pontos repro-eset is
  helyesen elutasítva (`wCheckPasses=false`). **A pontos javasolt kódalak
  a §„BLOCKER-1 — javító kör 2" szakaszban.**

  Motor-eszkaláció (AGENTS.md §15.6, user-döntés 2026-08-01, küszöb 1): a
  MiniMax egy javító kört kapott, a BLOCKER-1 utána is nyitva maradt →
  **a következő javító kört a Codex viszi**, külön munkapéldányban.

## Acceptance criteria (brief §6)

| # | Kritérium | Teljesült | Bizonyíték |
|---|---|---|---|
| 1 | Szintetikus perspektív fixture-mátrix, 4 nézőpont × 3 méret, python3-számolt | ⚠️ Részleges | `docs/rounds/…§10.1`: csak 2 a 4 névvel megnevezett nézőpont közül (`front`×3 méret, `oblique`×1 méret) — **`oldalról` és `felülről` teljesen hiányzik**. Ld. **F2**. |
| 2 | Property teszt (`PROPERTY_SEED`): round-trip ≤1e-6, %-küszöb | ✅ | `test/property/homography_property_test.dart` — 500 trial, ≥99% ráta; futtatva: `PROPERTY_SEED=42`, zöld. |
| 3 | Degenerált-mátrix cellák: kollineáris / nem konvex / nulla terület / kondíció alatt-rajta-fölött; „fölött hibát ad, nem eredményt" | ❌ Nem teljesül a szó szerinti garancia | Kollineáris ✅ (`homography_test.dart:50`), nem konvex ✅ (`polygon2_test.dart:118`, chevron), nulla terület ✅ (`polygon2_test.dart:18`) — DE a „fölött hibát ad" garancia **megsérül** azokra a mátrixokra, amik a küszöb ALATT mérnek, mégis szemetet adnak (a projektív sor vak folt miatt). Ld. **BLOCKER-1**. A „rajta" cella (`homography_test.dart:249`) emellett egy cond≈122 esetet használ, ami NEM közel a tényleges 1e3 küszöbhöz. Ld. **MINOR-1**. |
| 4 | Confidence-propagáció: output ≤ input, rosszabb kondíciónál szigorúan kisebb | ✅ | `guitar_landmark_mapper_test.dart:156,180` — mindkét irány tesztelve, az utóbbi KÉT valódi (mild vs. skewed) kalibrációt hasonlít össze, nem szintetikus számot. |
| 5 | NaN/Infinity guard, kimerítő assert | ✅ | `homography_test.dart:187` (200 random pont) + `homography_property_test.dart` (200 trial) + mapper `non-finite input → null` teszt. |
| 6 | Valódi-sértés próba: kondíció-ellenőrzés kiiktatása → „fölött" cella PIROS → visszaállítás | ⚠️ Implementer nem dokumentálta (§10-ben nincs nyoma) — **a reviewer saját kézzel elvégezte** (lásd „Próbatesztek" lent): a kondíció-guard kiiktatásával PONTOSAN a „cell above threshold" teszt bukott (8/9 zöld maradt), minden más érintetlen. A kritérium TELJESÜL, a bizonyítékot ez a jelentés pótolja. |

## Scope-audit

```
git diff --stat bf3960a..13dc79b
```

12 fájl változott, **mind a 12 szerepel a brief `allowed_paths` listáján**,
egy sem kívül. `tools/mm-round.sh` saját gépi scope-auditja is `scope_audit=ok`
(`scope_audit_changed=12`). Engedélyezett fájlokon kívüli változás: **nincs.**

## Gate-bizonyíték ellenőrzése

Friss, izolált `/tmp` klón (`/tmp/review-e05-r15`, azóta törölve), a
`round-gate.sh`-t **egyetlen, csonkítatlan artefaktumként** futtatva:

```bash
tools/round-gate.sh test/core/geometry test/features/vision test/property/homography_property_test.dart
```

| Gate | Állított eredmény (implementer) | Ellenőrizve (reviewer, friss klón) |
|---|---|---|
| format | zöld | ✅ ZÖLD |
| analyze | zöld | ✅ ZÖLD |
| test test/core/geometry | zöld | ✅ ZÖLD |
| test test/features/vision | zöld | ✅ ZÖLD |
| test test/property/homography_property_test.dart | zöld (99%+ ≤1e-6) | ✅ ZÖLD |
| architecture | zöld | ✅ ZÖLD |
| secrets | (nem említve) | ✅ ZÖLD |
| l10n | (nem említve) | ✅ ZÖLD |

Exit code 0, 8/8. **Megjegyzés a gate-shape-ről:** a nyers implementer-log
tartalmaz köztes, önellenőrző `round-gate.sh … \| tail -N` hívásokat (a
regisztrációban dokumentált M3-gyengeség: „invariánst lazít") — ezek a
`gate_shape` gépi őrt NEM buktatták (`gate_shape=ok` a jelzésfájlban), és a
fenti független, csonkítatlan újrafuttatás megerősíti a végeredményt. Rögzítve
mint mintázat, nem lelet — a mérce a végén tartotta magát.

## Próbatesztek (eldobható, a merge előtt törölve)

1. **`Polygon2.contains` — nem tengelyillesztett polygon próba.** Egy origó
   középpontú rombuszt (`(0,-1),(1,0),(0,1),(-1,0)`) építve, a `(0,0)` pont
   `Polygon2.contains`-szal vizsgálva → `false`-t adott, holott a rombusz
   közepe triviálisan a rombuszon BELÜL van. Megismételve fordított
   csúcssorrenddel → szintén `false`. Egy nem-tengelyes, gitárnyak-szerű
   négyszögön (`(0.1,0.1),(0.9,0.3),(0.8,0.9),(0.2,0.7)`) egy belső pont
   viszont HELYESEN `true`-t adott — a hiba tehát geometria-függő, nem
   univerzális, ami azért veszélyesebb (alkalmi ellenőrzésen átcsúszhat).
   Ld. **MAJOR-1**.
2. **Kondíció-guard valódi-sértés próba.** `/tmp/mutate-e05-r15` klónban
   `lib/core/geometry/homography.dart:145` sorát `if (false && (...))`-ra
   módosítva (a guard tényleges kiiktatása), majd
   `flutter test test/core/geometry/homography_test.dart` — PONTOSAN a
   „condition number: cell above threshold → conditionNumberExceeded" teszt
   bukott (8 zöld, 1 piros), minden más teszt változatlanul zöld maradt. A
   guard tehát genuinely load-bearing, nem holt kód. Klón törölve a próba
   után.
3. **A dedikált security-review (risk=high) MAJOR-1 leletének független
   megerősítése, MÁS véletlen-paraméterekkel.** A `security-reviewer` ágens
   198 222 véletlen `GuitarCalibration`-t vizsgálva talált olyan mappert,
   ami alacsony (~3) kondíciószámot jelent, mégis 10⁷-es nagyságrendű u/v-t
   ad egy képen-belüli ponton. Egy SAJÁT, tőle független próbában
   (50 000 véletlen kalibráció, 11×11-es rács minden sikeresen épített
   mapperen, seed=7, a szállított kódot közvetlenül importálva egy `/tmp`
   klónban) **49 455 mapper épült sikeresen**; az alacsony/megbízhatónak
   jelentett (`reportedCond ≤ 50`) mapperek rácspontjai közül **323 340
   mintapont** adott `|uv| > 10` nagyságrendű kimenetet `> 0.5`
   confidence-szel. Legrosszabb eset:
   `reportedCond=2.89`, kamera-pont `(0.9, 1.0)` → `(u,v) =
   (3 183 316, 2 649 428)`, `confidence=0.884`. Ld. **BLOCKER-1**.

## Megállapítások

### BLOCKER-1 — a kondíciószám-őr vak a projektív sorra: érvényes kalibrációk milliós nagyságrendű, magas-confidence-ű szemetet adnak

- **Fájl:** `lib/core/geometry/homography.dart:379-398` (`_measureConditionNumber`),
  `:166-172` (`apply`, a `safeW = w == 0 ? 1e-300 : w` szingularitás-elfedő
  trükk); `lib/features/vision/domain/geometry/guitar_landmark_mapper.dart:180-200`
  (`mapPoint`), `:225-230` (`_conditionPenaltyFor`).
- **Probléma:** `_measureConditionNumber` KIZÁRÓLAG a mátrix felső 2×2
  lineáris blokkját méri (`h[0],h[1],h[3],h[4]`), a projektív sort
  (`h[6..8]`) figyelmen kívül hagyva — a kódkomment szerint „the projective
  row only affects points at infinity", ami TÉVES állítás: a projektív sor
  határozza meg a `w = h6·x + h7·y + h8 = 0` „eltűnő egyenest", és ha ez az
  egyenes átmegy a `[0,1]×[0,1]` kamera-kereten (ami a ténylegesen használt
  tartomány), az arra közeli pontok kimenete minden határon túl nő —
  FÜGGETLENÜL attól, hogy a 2×2 blokk milyen jól kondicionált. Az
  `apply()`-ban lévő `safeW` trükk csak a PONTOSAN nulla `w`-t védi;
  egy közel-nulla (de nemnulla) `w` egy nagy, de véges eredményt ad, ami
  átmegy a `mapPoint` `isFinite` őrén.
- **Hatás — közvetlen AGENTS.md §5 termékhatár-sértés** („Gyenge confidence
  nem jelenhet meg biztos állításként"): **mindkét független próba** (a
  security-reviewer ágens ÉS a reviewer saját, más paraméterekkel futtatott
  keresése) talált teljesen ÉRVÉNYES, konstruálható `GuitarCalibration`-t
  (nut/bridge/polygon mind `[0,1]²`-ben, nem degenerált, a mapper sikeresen
  megépül), aminek a KONDÍCIÓSZÁMA alacsony/megbízhatónak tűnő (a reviewer
  próbájában `2.89`, jóval a `1e3` küszöb alatt), miközben egy hétköznapi,
  kereten-belüli landmark-pont (`(0.9, 1.0)`) `(u,v)=(3 183 316,
  2 649 428)`-ra képeződik **`confidence=0.884`** mellett. Ez PONTOSAN a
  brief §9 által „a kör legveszélyesebb hibájaként" megnevezett forgatókönyv
  ténylegesen bekövetkezik, a round saját, egyetlen deklarált őre
  (kondíciószám-küszöb) mellett is. A hiba jelenleg release-buildben is
  elérhető, mert a `GuitarCalibration`/`NormalizedPoint` validáló
  `assert`-jei stripped-ek (a security-review NOTE-d pontja) — bár a mai
  hívási láncban a bemenet maga (a kalibráció) nem kell legyen sérült, csak
  „szerencsétlen geometriájú" (lásd a fenti két próba — mindkettő
  TELJESEN ÉRVÉNYES, korrupció nélküli kalibrációkat generált).
- **Kötelező javítás:** a `core/geometry` réteg (`Homography`) maradjon
  tér-semleges, ezért a javítás a domain-tudatos rétegbe
  (`GuitarLandmarkMapper.fromCalibration`) kerüljön: a homográfia sikeres
  megépítése UTÁN, még a mapper visszaadása ELŐTT, mintavételezd az
  `apply()`-t néhány kanonikus, a kamera-normalizált `[0,1]×[0,1]` tartományt
  lefedő ponton (pl. a 4 sarok + középpont), és ha BÁRMELYIK mintapont
  `(u,v)` nagysága egy dokumentált, bőkezű határt túllép (pl. a gitártér
  saját `u∈[0,1]`/`v∈[-1,1]` definíciójához képest nagyságrendekkel nagyobb
  — egy konkrét, a fájl tetején deklarált konstans, pl.
  `guitarSpaceSanityBound`), a mapper építése dobjon egy ÚJ, típusos
  kudarc-okot (pl. `GuitarLandmarkMapperSetupFailure.unstableMapping`),
  UGYANÚGY, ahogy a kondíciószám-túllépés is teszi ma. (Alternatív, a
  `core/geometry` rétegben maradó megoldás: a TELJES 3×3 homográfia valódi
  kondíciószámát mérni SVD-vel, vagy explicit ellenőrizni, hogy a `w=0`
  egyenes metszi-e a `[0,1]²` tartományt — ez matematikailag pontosabb, de
  nagyobb implementációs kockázat egy már egyszer numerikusan megcsúszott
  körben; a kimenet-mintavételezés egyszerűbb és közvetlenül a MEGFIGYELT
  hibamódot céloz.)
- **Ellenőrzés:** a fenti két próba (security-reviewer 198k-mintás keresése
  és a reviewer 50k-mintás keresése) reprodukálhatóként a javítás UTÁN 0
  találatot kell adjon `|uv|>10 && confidence>0.5` mellett alacsony
  (`≤50`) jelentett kondíciószámú mapperek között. Adj property-tesztet a
  `test/property/homography_property_test.dart`-hoz VAGY egy új
  `guitar_landmark_mapper_test.dart` esethez, ami ezt a random-search mintát
  intézményesíti (nem csak egyszeri kézi próba marad).
- **Státusz:** OPEN

### MAJOR-1 — `Polygon2.contains` hibás nem tengelyillesztett polygonokra (funkcionális pass lelete)

- **Fájl:** `lib/core/geometry/polygon2.dart:112-117`
- **Probléma:** a ray-casting metszéspont-számítás nevezőjében `.abs()`
  szerepel: `(point.x < (b.x - a.x) * (point.y - a.y) / ((b.y - a.y).abs() +
  1e-300) + a.x)`. A standard (helyes) formula a **előjeles**
  `(b.y - a.y)`-t osztja, mert a metszéspont x-koordinátája előjel-függő; az
  `.abs()` minden olyan élnél megfordítja az eredményt, ahol `b.y < a.y`. A
  megelőző XOR-feltétel (`(a.y > point.y) != (b.y > point.y)`) garantálja,
  hogy ezen az ágon `a.y ≠ b.y` mindig teljesül — az `.abs()`-nak tehát
  SOHA nincs jogos szerepe, csak hibát okoz. Az egyetlen teszt-csoport
  (`polygon2_test.dart:152-177`) egy tengelyillesztett egységnégyzetet
  használ, amin a hiba matematikailag NEM tud megnyilvánulni (lásd a
  próbateszt fenti levezetését) — ez a mérés miatt maradhatott zölden.
- **Hatás:** `Polygon2.contains` jelenleg **nem hívja senki production
  kódból** ebben a körben (`GuitarRegionClassifier.classify` saját, egyszerű
  `u`/`v` sáv-vizsgálatot használ, nem polygon-alapú), tehát a mai
  viselkedést nem rontja. DE a `Polygon2` a `core/geometry` publikus,
  bármely jövőbeli feature által importálható API-ja (nincs `public.dart`
  barrel mögé zárva) — a modul saját doksija a `contains`-t a három
  „complete predicate set" tagjaként hirdeti. A hiba a valós gitárnyak-
  poligonok döntő részénél (bármi, ami nem tengelyillesztett téglalap)
  csendben rossz igen/nem választ adna egy jövőbeli hívónak.
- **Kötelező javítás:** távolítsd el az `.abs()`-t a nevezőből (az előjeles
  `(b.y - a.y)` a helyes forma; a `+1e-300` elhagyható, mert az XOR-ág már
  garantálja a nemnulla nevezőt). Adj hozzá egy nem tengelyillesztett
  regressziós tesztet a `Polygon2.contains` csoporthoz (pl. a fenti
  rombusz-eset vagy egy ferde gitárnyak-szerű négyszög, amin a hibás verzió
  ELŐZŐLEG piros lett volna).
- **Ellenőrzés:** az új teszt piros a jelenlegi kódon, zöld a javítás után;
  a meglévő 3 `contains`-teszt bitre változatlanul zöld marad.
- **Státusz:** OPEN

### MAJOR-2 — a fixture-mátrix két névvel megnevezett nézőpontot teljesen kihagy

- **Fájl:** `docs/rounds/e05-r15-guitar-coordinates-and-homography.md §10.1`
  (és a hozzá tartozó `homography_test.dart` / `guitar_landmark_mapper_test.dart`
  fixture-ök)
- **Probléma:** a brief §6 első cellája név szerint négy nézőpontot kér
  (`szemből, oldalról, felülről, ferdén`) × 3 gitárméretet. A szállított
  python3-referencia (§10.1) négy bejegyzést tartalmaz: `front_medium`,
  `front_small`, `front_large`, `oblique_med` — vagyis a négy megnevezett
  kategóriából csak **kettő** (szemből, ferdén) van jelen, és azokból is csak
  a „szemből" kapja meg mindhárom méretet. **`oldalról` és `felülről`
  bejegyzés egyáltalán nincs**, és a §10.6 „Eltérések a brief-től" szakasz
  ezt nem indokolja/dokumentálja — úgy néz ki, mint kihagyott munka, nem
  tudatos hatókör-döntés.
- **Hatás:** a brief §9 Kockázatok pontosan azért kért független, sokféle
  nézőpontból számolt fixture-öket, mert „a tolerancia a fixture-ökhöz
  igazodik ahelyett, hogy a fixture-ök függetlenek lennének" a legveszélyesebb
  hiba. A 500 mintás property teszt szélesen mintavételez véletlenszerű
  quadokat, de ez NEM helyettesíti a név szerint kért, függetlenül
  python3-mal számolt `oldalról`/`felülről` eseteket — pont azokat a
  perspektívákat, amik a leginkább rosszul kondicionáltak lehetnek
  (egy „oldalról" nézett gitárnyak közel egyenesbe lapul).
- **Kötelező javítás:** számolj ki (python3-mal, a §10.1 mintáját követve)
  legalább egy `side` és egy `top` fixture-t, és adj hozzájuk Dart tesztet
  (akár elfogadó, ha a kondíciószám a küszöb alatt marad; akár **elutasító**
  `conditionNumberExceeded`-teszt, ha egy oldalnézet ténylegesen
  degenerálthoz közeli — ez utóbbi is legitim módon zárja a cellát, és
  pontosan a round saját kockázat-fókuszát erősíti). Ha a döntés az, hogy
  `oldalról`/`felülről` szándékosan degenerált/elutasított eset, dokumentáld
  ezt kifejezetten a §10.6-ban.
- **Ellenőrzés:** a két új fixture python3-kimenete idézve a §10-ben, a
  hozzájuk tartozó Dart teszt zöld (vagy elutasító teszt esetén a
  `conditionNumberExceeded` reason zöld).
- **Státusz:** OPEN

### MINOR-1 — a „kondíció a küszöbön" cella nem a tényleges határt próbálja

- **Fájl:** `test/core/geometry/homography_test.dart:249-275`
- **Probléma:** a négy kondíció-cellából az „above threshold" (cond≈2400) és
  az „on threshold" névre keresztelt teszt (cond≈122, a saját kommentje
  szerint is „well below 1e3") között nincs olyan eset, ami a tényleges
  `homographyMaxConditionNumber = 1e3` határ közelében (pl. ±5%-on belül)
  mérne — a `cond <= 1e3` vs. `cond < 1e3` döntés (a kódban: `cond >
  homographyMaxConditionNumber` a dobási feltétel, tehát `<=` elfogad) emiatt
  nincs ténylegesen próbára téve.
- **Hatás:** alacsony — a jelenlegi implementáció konzisztens és
  dokumentált, csak a teszt-lefedettség nem éri el a brief „rajta" cellájának
  szó szerinti szándékát.
- **Kötelező javítás:** cseréld vagy egészítsd ki a „cell on threshold"
  tesztet egy olyan konstrukcióval, aminek mért kondíciója 1e3 ±1-2%-on belül
  van (python3-mal számolva), és explicit assertálja, hogy pontosan a
  dokumentált határon fogad el / utasít el.
- **Ellenőrzés:** az új teszt a jelenlegi `<=` implementáción zöld; egy
  ideiglenes `>=`-re cserélt mutáció esetén pirosra vált (opcionális, de
  ajánlott önellenőrzés a fix-körben).
- **Státusz:** OPEN

**A korábban itt szereplő „2×2 blokk vs. teljes 3×3" NOTE a security-review
után BLOCKER-1-be olvadt** — az akkor csak elméletinek jelölt kockázat
mindkét független próbával ténylegesen reprodukálva lett, lásd fent.

### MINOR-2 — `GuitarLandmarkMapper.fromCalibration` doksija „null"-t ígér, a kód mindig dob

- **Fájl:** `lib/features/vision/domain/geometry/guitar_landmark_mapper.dart:120-126`
  (doc-comment) vs. `:132-136`, `:144-148`, `:166-168` (mindhárom hibaág
  `throw`-ol).
- **Probléma:** a metódus doksija szó szerint azt írja: „Returns `null`
  (with a typed reason) when the polygon is degenerate, the anchors
  coincide, or the solved homography exceeds…", a visszatérési típus
  nullable (`GuitarLandmarkMapper?`) — de a metódus egyetlen ága sem ad
  vissza `null`-t, mindegyik `GuitarLandmarkMapperSetupException`-t dob. A
  kör saját tesztje (`guitar_landmark_mapper_test.dart:63-85`) helyesen
  `throwsA`-t vár, tehát a KÓD és a TESZT egyetért — csak a doc-comment és a
  szignatúra téved.
- **Hatás:** egy jövőbeli hívó, aki a doksit/típust olvassa (nem a tesztet),
  `if (mapper == null)` mintát írna `try/catch` nélkül — degenerált
  kalibrációnál (pl. 3 kollineáris/duplikált polygon-csúcs, ami a release-
  stripped `assert` miatt konstruálható) elkapatlan kivétel omlasztaná a
  hívó keretet.
- **Kötelező javítás:** válassz egyet — (a) igazítsd a doksit a tényleges
  `throw`-viselkedéshez és tedd nem-nullable-lá a visszatérési típust; vagy
  (b) tényleg adj vissza `null`-t a doksinak megfelelően, a reason-t egy
  out-paraméterben vagy result-objektumban.
- **Ellenőrzés:** a meglévő 3 hibaág-teszt (`degeneratePolygon`,
  `anchorsCoincident`, a homográfia-hibából származtatott ág) változatlanul
  zöld marad bármelyik választás mellett.
- **Státusz:** OPEN

### MINOR-3 — `Polygon2.validate`/`isConvex`/`orientation` csendben „érvényesnek" fogad el NaN/Infinity polygont

- **Fájl:** `lib/core/geometry/polygon2.dart:66-75` (`validate`).
- **Probléma:** `area.abs() <= polygonDegenerateAreaTolerance` — ha `area`
  `NaN` (mert egy csúcs `NaN`), az IEEE754 szabály szerint `NaN <= bármi`
  mindig `false`, tehát a degenerált-ág NEM fut le, és a függvény
  `PolygonValidity.valid()`-ot ad vissza egy nem-véges polygonra. A modul
  saját doksija (`polygon2.dart:9-13`) kifejezetten ígéri, hogy „the
  silent-numeric-garbage rule forbids returning 'just false'" — ez a
  „csendben ÉRVÉNYESNEK" irány ugyanennek az elvnek a megsértése a másik
  oldalról.
- **Hatás ebben a körben ma korlátozott:** a `GuitarLandmarkMapper.fromCalibration`
  hívási láncában a `Polygon2.validate` után közvetlenül következő
  `Homography.solve` SAJÁT, feltétel nélküli (`assert`-mentes) finiteness-
  ellenőrzése elkapja a NaN-t, mielőtt bármi szemét kiszivárogna — tehát a
  MAI mapper-út redundánsan védett, véletlenül, nem tervezetten. DE a
  `Polygon2` publikus API, `validate`/`isConvex`/`orientation` bármely
  jövőbeli hívója, aki NEM megy át a `Homography.solve`-on, ezt a védelmet
  nem kapja meg.
- **Kötelező javítás:** adj egy explicit `isFinite`-ellenőrzést minden
  csúcsra `validate` elején (új `PolygonDegenerateReason.nonFinite`, a
  `tooFewVertices` UTÁN, a `zeroSignedArea` ELŐTT ellenőrizve).
- **Ellenőrzés:** új teszt egy `NaN`/`Infinity` csúcsú polygonon —
  `validate(...).isValid == false` és a helyes reason.
- **Státusz:** OPEN

### NOTE-1 — normálegyenletek egy egzaktul meghatározott 8×8 rendszerhez

`homography.dart:239-262` a DLT-t a normálegyenleteken (`AᵀA·h=Aᵀb`)
keresztül oldja meg, holott 4 korrespondenciára a rendszer egzaktul
meghatározott (8 egyenlet, 8 ismeretlen) — a normálegyenlet-négyzetesítés
a kondíciószámot négyzetre emeli (κ(AᵀA)=κ(A)²), ami egy közvetlen
Gauss-elimináció a nyers 8×8 rendszeren jobb numerikus gyakorlat lett
volna. A Hartley-normalizálás miatt a mért κ(A) ≈1.1-2 tartományban marad,
így κ(A)² is elhanyagolható — a jelenlegi fixture-ökön nincs mérhető hatás.
Nem blokkoló, csak jó gyakorlat megjegyzés egy jövőbeli refaktorhoz.

### NOTE-2 — `Homography.solve` egy `ArgumentError`-t (nem `Exception`-t) dob rossz korrespondencia-számra

`homography.dart:92-97` `ArgumentError`-t dob, inkonzisztensen a modul saját
`HomographyError implements Exception`-jével. Egy `on Exception`/
`on HomographyError` mintát használó hívó (mint a mapper `:166`-on) ezt NEM
kapná el. Ma ártalmatlan (a mapper fix 4-pontos quadot épít), de a
`Homography.solve` publikus core API — egy jövőbeli, változó hosszúságú
hívó elkapatlan crash-t kapna. A kör saját tesztje (`homography_test.dart:19-27`)
ezt szándékos választásként rögzíti — inkonzisztens, de tudatos.

### NOTE-3 — koordináta-értékek kivétel-üzenetekben

`guitar_space.dart:38-42,90-97,130-136`, `guitar_landmark_mapper.dart:56-62`,
`homography.dart:432-433` nyers koordináta/confidence-értékeket
interpolál `ArgumentError`/`toString` szövegekbe. Ezek landmark-SZÁRMAZTATOTT
számok (nem nyers kamera-frame), és ez a modul sosem logol — tehát ma NEM
sérül a §5 termékhatár. Defense-in-depth: ha egy jövőbeli hívó logolná ezeket
a kivételeket, pozíció-adat kerülne logba — vezesd át a redakciós határon,
és ne tegyél koordinátát perzisztálható üzenetbe.

### NOTE-4 — csendes szemét-útvonalak az inverzen

`mapPointInverse` (`guitar_landmark_mapper.dart:204-207`) `clamp`-eli a
guitar→camera eredményt `[0,1]`-re, csendben plauzibilis-nek látszó
`NormalizedPoint`-tá alakítva egy tartományon kívüli inverzet. Ma
debug/overlay-only (R24). Kapcsolódóan: az inverz homográfia kondíciószámát
a kód méri, de SOHA nem validálja a küszöb ellen (`homography.dart:159` —
csak az előre-mátrixot ellenőrzi `:145-147`).

## Architektúra + termékhatárok

- **Core-tisztaság:** `grep -rn "dart:ui\|package:flutter\|features/" lib/core/geometry/*.dart` — csak doc-comment-hivatkozás, forráskód-import NULLA. `architecture` gate-lépés is zöld.
- **`public.dart` contract:** két additív export (`guitar_landmark_mapper`,
  `guitar_region`), nincs törölt/módosított meglévő export.
- **AGENTS.md §5 termékhatárok:** nincs hálózat, storage, mic, secret — a
  modul tisztán in-memory pure-Dart matematika (a dedikált security-review
  ezt függetlenül, grep- és futtatott-harness-szinten megerősítette). **DE
  a „gyenge confidence nem jelenhet meg biztos állításként" határ MEGSÉRÜL**
  — ld. BLOCKER-1.
- **Lifecycle-erőforrás:** nincs `StreamSubscription`/isolate/timer a
  modulban — nem releváns.

## Dedikált biztonsági review (risk = "high")

A brief `ai-router` blokkja `risk = "high"`-t jelöl, ezért AGENTS.md §15.1
szerint kötelező a `security-reviewer` ágens független futása. **Lezárva**,
teljes jelentés: [`docs/reviews/e05-r15-guitar-coordinates-and-homography-security.md`](e05-r15-guitar-coordinates-and-homography-security.md)
— **FAIL (soft)**, 0 CRITICAL/BLOCKER (a security-reviewer saját
osztályozásában; a jelentésben MAJOR-1-nek nevezett lelet ebbe a
funkcionális review-ba **BLOCKER-1**-ként lett felvéve, mert a brief §11
szabálya szerint „nulla OPEN BLOCKER/MAJOR" a merge feltétele, és a lelet
ténylegesen megszegi az AGENTS.md §5 nem tárgyalható termékhatárát — ez a
súlyossági tábla „megszegett termékhatár" sora). A security-reviewer
verdiktje: a klasszikus adatbiztonsági/privacy dimenzióban a `risk="high"`
címke túl konzervatív (nincs hálózat/tárolás/secret/AI-hívás/importált
fájl), de a valós kockázat — numerikus korrektség mint biztonsági kérdés —
pontosan ott landolt, ahova a brief §9 előre jelezte.

## BLOCKER-1 — javító kör 2 (Codex), pontos specifikáció

A javító kör 1 (MiniMax) MAJOR-1-et és MAJOR-2-t lezárta, de a BLOCKER-1
javítása (apply()-kimenet mintavételezése 5 ponton) **matematikailag nem
teljes** — lásd fent. Az alábbi, saját 50 000-próbás kereséssel validált
(0 hamis negatív) javítás a **javasolt, konkrét irány** a javító kör 2-höz:

**Hol:** `lib/core/geometry/homography.dart` — adj egy ÚJ publikus metódust
a `Homography` osztályhoz (a `debugMatrix` „Test/debug only" — ne azt
használd production kódból):

```dart
/// The homogeneous denominator `w = h6·x + h7·y + h8` at [point], BEFORE
/// perspective division. `apply(point) = (numerator_x, numerator_y) / w`;
/// this is the raw denominator a caller can use to detect where the
/// projective row drives the mapping toward its vanishing line, without
/// waiting for the divided-out result to blow up.
double homogeneousW(Point2 point) => _h[6] * point.x + _h[7] * point.y + _h[8];
```

**Hol:** `lib/features/vision/domain/geometry/guitar_landmark_mapper.dart` —
cseréld le a jelenlegi `_checkFrameBounded` (apply()-magnitúdó 5 ponton)
metódust egy `w`-alapú ellenőrzésre a `[0,1]×[0,1]` tartomány **4 sarkán**
(a középpont NEM szükséges — egy affin függvény szélsőértéke konvex
tartomány fölött mindig a csúcsokon van, tehát a 4 sarok KIMERÍTŐ mintavétel,
matematikailag, nem csak heurisztikusan):

```dart
static void _checkFrameBounded(Homography h) {
  const corners = [Point2(0, 0), Point2(1, 0), Point2(0, 1), Point2(1, 1)];
  final wValues = corners.map(h.homogeneousW).toList();
  // h[8] == 1.0 mindig (Homography.solve renormalizálja) — ez a kanonikus
  // referencia-skála, tehát a küszöb dimenzió nélküli.
  final allSameSign = wValues.every((w) => w.isNegative == wValues.first.isNegative);
  final allBoundedAway = wValues.every((w) => w.abs() >= wMinBound);
  if (!allSameSign || !allBoundedAway) {
    throw const GuitarLandmarkMapperSetupException(
      GuitarLandmarkMapperSetupFailure.unstableMapping,
    );
  }
}
```

(A `wMinBound` konkrét értékét python3-mal vagy egy saját random-search
kalibrációval indokold a §10-ben — a review saját próbája `0.1`-et
használt, 0 hamis negatívval 50 000 próbán; ez jó kiindulópont, de a
végső döntés és indoklás a javító kör dolga.)

**Kötelező, hogy a javító kör MEGISMÉTELJE (ne csak elfogadja) az
adversarial validációt** — ez nem csak stílus kérdése, hanem a review
saját próbájának reprodukálhatósága:

1. A pontos BLOCKER-1 repro-eset (a §10-ben és a
   `guitar_landmark_mapper_test.dart`-ban már rögzítve) továbbra is
   `unstableMapping`-et dobjon.
2. Írj egy ÚJ property-tesztet vagy egy determinisztikus (fix seedű)
   random-search tesztet, ami — hasonlóan a review próbájához — sok
   véletlen kalibrációt épít, és minden olyan mapperre, ami átjut az ÚJ
   `w`-alapú guard-on, ellenőrzi hogy egy sűrű (pl. 11×11) rácson SEHOL
   nem ad `|uv| > guitarSpaceSanityBound`-ot. Ez a teszt intézményesíti
   az adversarial keresést, nem csak egy egyszeri kézi próbaként marad.
3. A meglévő `front_medium`-alapú „stays inside the sanity bound" pozitív
   teszt bitre változatlanul zöld maradjon.

## BLOCKER-1 — javító kör 2 közbeni STOP és feloldás (Codex helyesen megállt)

A Codex a fenti 4-sarkos konstrukció-idejű specifikációt implementálva
`stopped`-ot jelzett: **`front_medium`** (a teljes tesztsuite referencia
fixture-e) a saját próbájával NEM azonos előjelű a 4 sarkán. Az
orchestrátor független próbával (`_fourSourcePoints`-replikáció +
`debugMatrix`, majd finomított pásztázás) **megerősítette**: `front_medium`
ténylegesen rendelkezik egy korábban észrevétlen, szűk eltűnő-egyenes
sávval kamera-tér `y≈0,25-0,27` közelében (`apply(0.5,0.26)` magnitúdója
`5,6`). A 4-sarkos ellenőrzés matematikailag HELYES (ténylegesen felfedezi
a hibát), de **hatókörben túl szigorú**: egy 95%-ban jó kalibrációt
egészében elutasítana egyetlen keskeny sáv miatt.

**Feloldás (dokumentálva a brief §0.0.1-ben, ADR 0087 §2 szerint
önállóan dönthető — a kör saját, még nem merge-elt artefaktumát érinti,
nem H4 halt):** a védelem KONSTRUKCIÓ-idejű, teljes-kalibrációt-elutasító
szintről PONT-szintűre tolódik — `mapPoint()` a TÉNYLEGESEN lekérdezett
ponton számítja a `homogeneousW`-t, és csak AZT az egy landmarket adja
vissza `null`-ként, ha a küszöb alatt van, nem a teljes kalibrációt utasítja
el. Ez szigorúbb garancia (a valódi pontot vizsgálja, nem egy véges
mintavételi proxyt) ÉS nem dobja el a `front_medium`-hoz hasonló, javarészt
jó kalibrációkat. A pontos kódalak és a BLOCKER-1 repro-teszt átírásának
iránya a brief §0.0.1-ben. A javító kör 2 ezzel a revideált iránnyal
folytatódik ugyanabban a munkapéldányban.

## Merge-döntés

**Merge TILOS jelenleg** (1 nyitott BLOCKER — BLOCKER-1 a javító kör 1 után
részlegesen javítva, a javító kör 2 folyamatban a fenti revideált,
pont-szintű iránnyal). **A MiniMax motor-eszkalációs szabálya (AGENTS.md
§15.6, user-döntés 2026-08-01) kimerült** ezen a leleten (egy javító kör
után is nyitva) — **a javító kört a Codex viszi**, külön munkapéldányban
(`tools/codex-round.sh` + `tools/codex-watch.sh`). MAJOR-1 és MAJOR-2 zárva,
nem kerülnek vissza a javító kör 2 promptjába. MINOR-1..3 opcionális, csak
ha nem hizlalja érdemben a diffet.
