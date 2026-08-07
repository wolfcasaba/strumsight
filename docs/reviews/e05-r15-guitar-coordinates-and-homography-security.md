# E05-R15 — Dedikált biztonsági review (risk = "high")

Brief: `docs/rounds/e05-r15-guitar-coordinates-and-homography.md`
Diff: `git diff bf3960a..13dc79b` (branch `minimax/e05-r15-guitar-coordinates-and-homography`)
Reviewer: `security-reviewer` ágens (dispatch: orchestrátor, Claude Sonnet 5) · Dátum: 2026-08-07
Verdikt: **FAIL (soft)** — 0 CRITICAL, 0 BLOCKER (a security-reviewer saját
osztályozásában), **1 MAJOR** (a funkcionális review-ban `BLOCKER-1`-ként
felvéve — ld. lent), 2 MINOR, 4 NOTE.

> **Megjegyzés a jelentés eredetéről:** a `security-reviewer` ágens a
> jelentést a válaszába írta, nem a `docs/reviews/…-security.md` fájlba
> (egy — feltehetően téves — belső instrukcióra hivatkozott, miszerint
> „ne írj .md jelentésfájlt"). Ezt a fájlt az orchestrátor hozta létre az
> ágens VÁLTOZATLAN tartalmával, mert az AGENTS.md §15.1 szerint ennek a
> fájlnak léteznie kell a merge előtt. **A jelentés fő állítását (a
> kondíciószám-őr vak a projektív sorra) az orchestrátor egy SAJÁT, az
> ágenstől független próbával más véletlen-paraméterekkel megismételte és
> megerősítette** — lásd a funkcionális review
> (`e05-r15-guitar-coordinates-and-homography-review.md`) „Próbatesztek"
> szakaszát és a `BLOCKER-1` bejegyzést. A jelentés többi (MINOR/NOTE)
> állítását az orchestrátor a saját kódolvasásával kereszt-ellenőrizte,
> nem futtatott próbával — ezek plauzibilisek és a hivatkozott fájl:sor
> helyek egyeznek a szállított kóddal.

## Módszer

A geometria-gráf tiszta `dart:math` + relatív importok; a mapper-lánc csak
`camera_coordinate_space.dart`-ot (nulla import) és `guitar_calibration.dart`-ot
ad hozzá. Az ágens az összeset scratch-be másolta, relatív importokra írta át
(az eredetieket nem érintve), és a TÉNYLEGES `Homography`/`GuitarLandmarkMapper`
kódot futtatta `--enable-asserts` és `--no-enable-asserts` mellett is. Minden
numerikus állítás a szállított kód KIMENETE, nem kézi elemzés.

## Tiszta területek (bizonyítékkal)

- **Nincs hálózat / HTTP / socket / fájl-I/O / isolate / FFI.**
  `grep -rniE 'dart:io|HttpClient|Socket|Dio|package:http|File\(|Process\.|SecureStorage|SharedPreferences|KeyValueStore'`
  a két új `lib/` könyvtáron — az egyetlen találat `math.log(cond)` (matek
  hívás). A teljes modul importja `dart:math` + testvér domain-típusok.
- **Nincs nyers kamera-/landmark-adat perzisztálása.** Pont be, pont ki;
  sehol storage API.
- **Nincs logolás/analytics/diagnostics sink, nincs secret** (nincs mit
  szivárogtatni; a `secrets` gate zöld), **nincs AI-provider/prompt/
  tool-calling felszín**, **nincs importált-fájl/path-traversal felszín**
  (nincs `File`, nincs archívum), **nincs új dependency, nincs új platform
  permission.**
- **Nincs korlátlan ciklus / DoS.** Minden ciklus a fix 4-pontos rendszer
  vagy a neck-polygon hosszára korlátozott; minden osztás védett (`apply`
  `safeW`, `_inverse3x3`/`_invertAffine` `det<1e-15`, `_solveLinearSystem`
  `pivot<1e-15`, `_normalize` `meanDist==0`, `_fourSourcePoints` `uLen==0`).
- **A globális confidence-propagáció aritmetikailag helyes** (brief §5.3):
  `confidence = (visibility · penalty).clamp(0,1)`, `penalty ∈ [0.5, 1.0]`
  (monoton csökkenő a mért kondícióban) → a kimenet sosem nagyobb a
  bemenetnél. A hiba az, hogy MELYIK kondicionálás vezérli a penalty-t (ld.
  MAJOR-1 / a funkcionális review BLOCKER-1-je), nem a propagáció maga.
- **`Polygon2.contains` `.abs()`-nevezője:** az ágens CW/CCW négyzeteket és
  egy döntött quadot próbált, mindegyik helyes eredményt adott — az ágens
  NEM tudta reprodukálni a hibát a saját próbáival, ezért NEM jelentette.
  (A funkcionális review saját, MÁS geometriájú próbája — egy origó-
  középpontú rombusz — IGEN reprodukálta; ld. ott `MAJOR-1`. A két review
  egymást kiegészíti, nem mond ellent egymásnak — a hiba geometria-függő.)

## Megállapítások

### MAJOR-1 (security) — a kondíciószám-őr vak a projektív sorra; érvényes kalibrációk ~10⁷-es nagyságrendű gitár-koordinátát adnak ~0,88 confidence-szel

*(A funkcionális review-ban `BLOCKER-1` néven szerepel, mert a termékhatár-
sértés — AGENTS.md §5 „gyenge confidence nem jelenhet meg biztos
állításként" — a súlyossági tábla szerint BLOCKER, nem MAJOR. A tartalmi
leírás és a javasolt irány azonos; a teljes indoklás, a saját független
reprodukció és a javasolt javítás ott van kifejtve, hogy egy helyen legyen
a merge-döntéshez szükséges teljes kép.)*

- **Hol:** `lib/core/geometry/homography.dart:379-398` (`_measureConditionNumber`),
  `:166-172` (`apply`, a `safeW = w == 0 ? 1e-300 : w` szingularitás-elfedés);
  `lib/features/vision/domain/geometry/guitar_landmark_mapper.dart:180-200`
  (`mapPoint`), `:225-230` (`_conditionPenaltyFor`).
- **Megsértett szabály:** brief §9 (a kondíció-küszöb „az egyetlen őr" a kör
  legveszélyesebb hibája ellen), brief §5.2 („NEM elfogadható … 'majdnem jó'
  mátrix visszaadása figyelmeztetés nélkül"), brief §5.3 + AGENTS.md §5
  („gyenge confidence nem jelenhet meg biztos állításként") + ADR 0179 /
  SDD §5.5.
- **Reprodukált hibaforgatókönyv (a szállító mapperen végigfuttatva):** a
  `_measureConditionNumber` KIZÁRÓLAG a 2×2 affin blokkot méri, a
  projektív sort (`h[6..8]`) figyelmen kívül hagyva, egy TÉVES kódkomment
  mellett („the projective row only affects points at infinity"). 198 222
  érvényes `GuitarCalibration` átvizsgálásával (minden `NormalizedPoint`
  `[0,1]²`-ben, elválasztott anchorok, konvex 4-szög — semmi hibás) a
  `GuitarLandmarkMapper.fromCalibration` + `mapPoint` láncon átküldve,
  **2 971 164** kereten-belüli landmark-minta adott `|u/v| > 10`-et
  `confidence > 0,6`-tal. Legrosszabb eset: a jelzett kondíciószám `3,30`
  (≪1e3 → elfogadva „kiválónak"), miközben egy kereten-belüli landmark a
  kamera `(0.10, 0.60)` pontján `(u,v) = (-57 247 992, -42 577 384)`-re
  képeződik **0,876 confidence-szel** (bemeneti visibility 0,95). A
  `mapPoint` `!uv.isFinite → null` őre NEM sül el, mert a szemét nagy, de
  VÉGES (a `safeW` trükk a szingularitást végtelen helyett kb. 10⁷-re
  fordítja), és a `_conditionPenaltyFor` ugyanazt a vak globális kondíciót
  olvassa, tehát a penalty ≈1,0 marad.
- **Miért MAJOR/BLOCKER, nem csak MINOR:** a brief EZT az egy ellenőrzést
  emeli az egyetlen őr rangjára a kör kimondott #1 kockázata ellen, és ez a
  szállítható, publikus felszínen (`GuitarLandmarkMapper.fromCalibration` +
  `mapPoint`) végig, ÉRVÉNYES bemenettel megkerülhető. A szó szerinti
  elfogadási tesztek csak azért zöldek, mert egyikük sem próbál kereten-
  belüli eltűnő-egyenest (`homography_test.dart:151-185` a rosszkondíciós
  esetet KIZÁRÓLAG a 2×2 blokk összenyomásával idézi elő;
  `homography_property_test.dart:113-127` közel-téglalap quadokat
  mintavételez, ±0,1 skew-vel).
- **Javasolt javítási irány:** olyan kondicionálást mérj, ami a projektív
  sort is figyelembe veszi a TÉNYLEGES ROI fölött — teljes 3×3 SVD-
  kondíciószám, vagy explicit ellenőrzés, hogy a `w = h6·x+h7·y+h8`
  eltűnik-e / előjelet vált-e a `[0,1]²` sarkai között — és az `apply`
  típusos hibát adjon (vagy a hívó kezelje kötelezően a nem-véges jelet)
  osztás helyett `1e-300`-zal. Adj egy elfogadási cellát kereten-belüli
  eltűnő-egyenessel, és a confidence-penalty-t pontonként (a lokális `|w|`-
  ból), ne a globális blokk-kondícióból származtasd.

## Egyéb leletek (MINOR/NOTE) — a funkcionális review-ba felvéve

A security-reviewer az alábbi további, alacsonyabb súlyú leleteket találta;
mindegyiket az orchestrátor a saját kódolvasásával kereszt-ellenőrizte és a
funkcionális review-ba vette fel a teljes indoklással (fájl:sor, javasolt
javítás), hogy egy helyen legyen a javító kör bemenete:

- **MINOR-2 (funkcionális review):** `GuitarLandmarkMapper.fromCalibration`
  doksija „returns null"-t ígér, de minden hibaág `throw`-ol — crash-csapda
  egy doksit-hívő jövőbeli fogyasztónak.
- **MINOR-3 (funkcionális review):** `Polygon2.validate`/`isConvex`/
  `orientation` csendben „érvényesnek" fogad el NaN/Infinity polygont
  (`NaN <= tolerancia` mindig hamis) — a modul saját „nincs csendes szemét"
  elvének megsértése a másik irányból. Ma redundánsan védett a
  `Homography.solve` downstream finiteness-ellenőrzése által, de a
  `Polygon2` publikus API, más jövőbeli hívó nem kapja meg ezt a védelmet.
- **NOTE-1..4 (funkcionális review):** normálegyenletek egy egzaktul
  meghatározott 8×8 rendszerhez (numerikus gyakorlat, nem hiba); `Homography.solve`
  `ArgumentError`-t dob `HomographyError`-family helyett rossz
  korrespondencia-számra (inkonzisztens, de szándékos és tesztelt); nyers
  koordináták kivétel-üzenetekben (defense-in-depth, ma nincs logoló
  fogyasztó); `mapPointInverse` csendben clampeli a tartományon kívüli
  inverzet (debug/overlay-only, R24).

## A `risk = "high"` címkéről

**Túl konzervatív a klasszikus adatbiztonsági/privacy dimenzióra, de a
mögöttes megérzés helyes.** Ennek a körnek gyakorlatilag NULLA klasszikus
biztonsági támadási felszíne van: nincs hálózat, I/O, perzisztálás, secret,
AI-provider/prompt, importált-tartalom feldolgozás, új dependency vagy
permission — tiszta in-memory matematika. Ha a „high" adatszivárgási jelnek
volt szánva, félrekategorizált (ez a legalacsonyabb-szivárgási-kockázatú
körfajta). DE a „high" címke helyesen követi a kör VALÓS veszélyét, ami
numerikus **korrektség mint biztonsági kérdés**: a brief maga (§9) nevezi
meg „egy rosszul kondicionált homográfia, ami működőnek látszik" mint a
legveszélyesebb kimenetet — és pontosan ide landolt MAJOR-1/BLOCKER-1. A
kötelező dedikált review tehát megérte a költségét.

## Merge-döntés

Ennek a jelentésnek a verdiktje **FAIL (soft)** — a merge-et a funkcionális
review (`e05-r15-guitar-coordinates-and-homography-review.md`) egyesített
BLOCKER/MAJOR/MINOR listája és annak „Merge-döntés" szakasza szabályozza. A
security-review önmagában NEM talált klasszikus adatbiztonsági/privacy
sértést (0 CRITICAL/BLOCKER a saját dimenziójában); a MAJOR-1 lelet a
funkcionális review BLOCKER-1-jével azonos gyökérokú, együtt kell javítani.
