# E05-R15 — Review

Brief: `docs/rounds/e05-r15-guitar-coordinates-and-homography.md`
Diff: `git diff bf3960a..13dc79b` (branch `minimax/e05-r15-guitar-coordinates-and-homography`)
Reviewer: Claude Sonnet 5 · Dátum: 2026-08-07
Verdikt: **CHANGES REQUIRED**

## Összegzés

BLOCKER: 0 · MAJOR: 2 · MINOR: 1 · NOTE: 2

Az implementer (MiniMax M3) jelzése `done`, „round-gate 8/8 ZÖLD" — ez a saját
munkapéldányában futott, tehát önmagában nem bizonyíték (AGENTS.md §15.1).
Egy teljesen friss `/tmp` klónban **függetlenül újrafuttatva a gate 8/8 ZÖLD
maradt** (lásd lent) — ez a mérce valódi bizonyítéka. A két MAJOR lelet nem a
gate-en bukik el, hanem tartalmi/lefedettségi hiány, amit a gate szerkezetileg
nem tud elkapni — pontosan az a mintázat, amit ez a review-lépés keres.

## Acceptance criteria (brief §6)

| # | Kritérium | Teljesült | Bizonyíték |
|---|---|---|---|
| 1 | Szintetikus perspektív fixture-mátrix, 4 nézőpont × 3 méret, python3-számolt | ⚠️ Részleges | `docs/rounds/…§10.1`: csak 2 a 4 névvel megnevezett nézőpont közül (`front`×3 méret, `oblique`×1 méret) — **`oldalról` és `felülről` teljesen hiányzik**. Ld. **F2**. |
| 2 | Property teszt (`PROPERTY_SEED`): round-trip ≤1e-6, %-küszöb | ✅ | `test/property/homography_property_test.dart` — 500 trial, ≥99% ráta; futtatva: `PROPERTY_SEED=42`, zöld. |
| 3 | Degenerált-mátrix cellák: kollineáris / nem konvex / nulla terület / kondíció alatt-rajta-fölött | ⚠️ Részleges | Kollineáris ✅ (`homography_test.dart:50`), nem konvex ✅ (`polygon2_test.dart:118`, chevron), nulla terület ✅ (`polygon2_test.dart:18`), kondíció alatt/fölött ✅ — de a „rajta" cella (`homography_test.dart:249`) egy cond≈122 esetet használ, ami NEM közel a tényleges 1e3 küszöbhöz. Ld. **F3**. |
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
   Ld. **F1**.
2. **Kondíció-guard valódi-sértés próba.** `/tmp/mutate-e05-r15` klónban
   `lib/core/geometry/homography.dart:145` sorát `if (false && (...))`-ra
   módosítva (a guard tényleges kiiktatása), majd
   `flutter test test/core/geometry/homography_test.dart` — PONTOSAN a
   „condition number: cell above threshold → conditionNumberExceeded" teszt
   bukott (8 zöld, 1 piros), minden más teszt változatlanul zöld maradt. A
   guard tehát genuinely load-bearing, nem holt kód. Klón törölve a próba
   után.

## Megállapítások

### F1 — MAJOR — `Polygon2.contains` hibás nem tengelyillesztett polygonokra

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

### F2 — MAJOR — a fixture-mátrix két névvel megnevezett nézőpontot teljesen kihagy

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

### F3 — MINOR — a „kondíció a küszöbön" cella nem a tényleges határt próbálja

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

### F4 — NOTE — a kondíciószám-metrika a 2×2 lineáris blokkra szűkül, nem a teljes 3×3 homográfiára

`homography.dart:379-398` (`_measureConditionNumber`) csak a mátrix felső
2×2 lineáris blokkját méri, a projektív sort (`h[6..8]`) figyelmen kívül
hagyva. A döntés dokumentált és indokolt (a §10.2 python-referencia is
UGYANEZT az egyszerűsített metrikát futtatja, tehát a kalibráció
önkonzisztens, de nem független bizonyíték arra, hogy a 2×2-metrika jó proxy
a teljes projektív mátrix kondíciójára). Elméletileg elképzelhető egy
mátrix, aminek a lineáris blokkja jól kondicionált, miközben a projektív
sor extrém — ez a mai küszöb mellett átcsúszna. A jelenlegi kör
fixture-jein és a property-teszt 500 mintáján nem manifesztálódott
probléma; follow-up egy jövőbeli körnek (pl. R16 tracking vagy R18+
metrikák, amikor valós kalibrációs adat kezd átfolyni rajta).

### F5 — NOTE — normálegyenletek egy egzaktul meghatározott 8×8 rendszerhez

`homography.dart:239-262` a DLT-t a normálegyenleteken (`AᵀA·h=Aᵀb`)
keresztül oldja meg, holott 4 korrespondenciára a rendszer egzaktul
meghatározott (8 egyenlet, 8 ismeretlen) — a normálegyenlet-négyzetesítés
a kondíciószámot négyzetre emeli (κ(AᵀA)=κ(A)²), ami egy közvetlen
Gauss-elimináció a nyers 8×8 rendszeren jobb numerikus gyakorlat lett
volna. A Hartley-normalizálás miatt a mért κ(A) ≈1.1-2 tartományban marad,
így κ(A)² is elhanyagolható — a jelenlegi fixture-ökön nincs mérhető hatás.
Nem blokkoló, csak jó gyakorlat megjegyzés egy jövőbeli refaktorhoz.

## Architektúra + termékhatárok

- **Core-tisztaság:** `grep -rn "dart:ui\|package:flutter\|features/" lib/core/geometry/*.dart` — csak doc-comment-hivatkozás, forráskód-import NULLA. `architecture` gate-lépés is zöld.
- **`public.dart` contract:** két additív export (`guitar_landmark_mapper`,
  `guitar_region`), nincs törölt/módosított meglévő export.
- **AGENTS.md §5 termékhatárok:** nincs hálózat, storage, mic, secret —
  a modul tisztán in-memory pure-Dart matematika. (A dedikált
  security-review — risk=high — külön fájlban készül, ld. lent.)
- **Lifecycle-erőforrás:** nincs `StreamSubscription`/isolate/timer a
  modulban — nem releváns.

## Dedikált biztonsági review (risk = "high")

A brief `ai-router` blokkja `risk = "high"`-t jelöl, ezért AGENTS.md §15.1
szerint kötelező a `security-reviewer` ágens független futása. **Folyamatban
van, a jelentés `docs/reviews/e05-r15-guitar-coordinates-and-homography-security.md`
néven készül** — ennek a funkcionális review-nak a verdiktje a biztonsági
jelentés lezárása UTÁN válik véglegessé (a merge mindkettőt megköveteli).

## Merge-döntés

**Merge TILOS jelenleg** (2 nyitott MAJOR — F1, F2 — az ADR 0052 zöld kapu
ellenére, mert a gate szerkezetileg nem méri sem a `contains` nem-tengelyes
esetét, sem a fixture-mátrix teljességét). Javító kör szükséges, ugyanaz a
motor (MiniMax M3), a fenti F1–F3 leletlistával. A dedikált security-review
lezárása a merge második, független feltétele.
