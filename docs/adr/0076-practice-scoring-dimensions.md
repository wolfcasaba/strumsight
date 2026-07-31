# ADR 0076 — Practice V2 pontozási dimenziók: timing, direction, chord és az aggregátor

**Státusz:** elfogadva (E02-R10 pre-flight, 2026-07-31).
Épít az [ADR 0066](0066-practice-beat-position-tick.md) (µs/tick időalap),
[ADR 0068](0068-practice-domain-contracts.md) (verdict/metrics/profil modellek),
[ADR 0072](0072-practice-target-compiler.md) (compiled target) és
[ADR 0075](0075-practice-event-matcher.md) (event matcher) döntéseire.
Kör: [`docs/rounds/e02-r10-practice-scorers.md`](../rounds/e02-r10-practice-scorers.md).

## Kontextus

Az R09 matcher megmondja, **melyik megfigyelés melyik célesemény**, de ítéletet
nem mond. A `PracticeVerdict` és a `PracticeMetrics` az R03 óta létezik, de
**semmi nem állítja elő őket** — csak tesztek konstruálják kézzel. Ez a kör az
első előállítójuk.

A kör két kockázata mért, nem elméleti:

1. **Időalap-eltérés.** A legacy `LessonScorer` kerekítetlen `double`
   másodpercekkel dönt, a compiled target egész µs-mal. Az R09 kimérte
   ([ADR 0075 §2b](0075-practice-event-matcher.md)): a két időalap legfeljebb
   **0,5 µs**-ban tér el (mért maximum **0,489795919508 µs**, `anthem-drive[23]`).
   A párosítási küszöbön ez már eldöntött kérdés; a **timing grade** három
   küszöbén (perfect/good/match) ugyanez az eltérés a `perfect`/`good`
   besorolást — és rajta keresztül a pontszámot (100 vs. 70) — flippelheti.
2. **„Nem mértük" ≠ „nulla".** Egy el nem érhető dimenzió 0%-ként való
   beszámítása a felhasználót olyasmiért bünteti, amit meg sem mértünk. Ez a
   projekt hamis-állítás-tilalmának pontozás-oldali megfelelője.

## Döntés

### 1. Négy pure domain service

`practice_timing_scorer` · `practice_direction_scorer` · `practice_chord_scorer`
· `practice_score_aggregator`, mind a `lib/features/practice/domain/service/`
alatt. Egyik sem hívja a másikat a saját bemenetén kívül; Flutter/Riverpod/Dio
import tilos (`package:meta` megengedett). A bemenet a **matcher kimenete**, nem
a nyers megfigyelés-folyam — a scorer nem párosít újra.

### 2. Belül egész ezrelék, kifelé `perMille / 1000`

Minden pontszám belső ábrázolása **egész 0..1000**, a kifelé adott `double` a
`perMille / 1000` hányados. Lebegőpontos akkumuláció tilos.

Indok: a `0.8 - 0.45 * ratio` alak a `matchWindow` határon
`0.35000000000000003`-at ad, tehát a határcella egzakt teszttel nem fogható meg.
Az egész-ezrelék ábrázolás determinisztikussá teszi a kerekítést, és
mindkét oldalon ugyanaz az `int → double` konstrukció fut.

### 3. Timing event score

`off = |observedAt − targetAt|`, csonkoló (`~/`, nulla felé) osztással:

```text
off <= perfectWindow  -> 1000                                            (perfect)
off <= goodWindow     ->  800                                            (good)
off <= matchWindow    ->  800 - (450 * (off - goodWindow)) ~/ (matchWindow - goodWindow)
                                                    (early ha offset < 0, egyébként late)
nincs párosítás       ->    0                                            (missed)
```

A grade-határok **`<=`**-ek, a legacy `_timingFor` szerint. A `legacyLearnParity`
ablakaival (50/120/280 ms) a származtatott értékek — `python3`-mal ellenőrizve a
pre-flightban — `50 000 µs → 1000`, `120 000 µs → 800`, `200 000 µs → 575`,
`279 999 µs → 351`, `280 000 µs → 350`.

### 4. Direction

Csak az **elvárt iránnyal rendelkező** célesemények számítanak:
`correct = 1000`, `wrong = 0`, párosítatlan = `0`. Nulla ilyen célesemény →
`MetricNotApplicable` (**nem** 0). Van irányos célesemény, de nulla
strum-megfigyelés érkezett → `MetricInsufficientData(noSignal)` (**nem** 0).

**A megfigyelt irány a scorer bemenetének része.** A matcher eredménye
szándékosan **nem hordozza** a párosított megfigyelés irányát (E02-R09 review
NOTE-2: a matcher pontozás-mentes, `O(célesemény)` memóriájú, megfigyelést nem
tárol) — csak a `matchedObservationSequence` van meg. A direction-scorer ezért a
`sequence → StrumObservation` leképezést **explicit paraméterként** kéri.
Hiányzó leképezés esetén **fail-fast (`StateError`)**, nem csendes `wrong`: a
néma hibás ítélet rosszabb, mint a leállás. A matcher emiatt **nem bővül** — az
lezárt kör.

### 5. Chord

Ablak: **`[targetAt − 120 ms, targetAt + 420 ms]`**, mindkét vég inkluzív. Az
aszimmetria szándékos: a legacy `_chordLagSec = 0.37` mérte ki, hogy az
akkord-detektálás késik — a szimmetrikus ablak ezt a késést hibának minősítené.

A döntés az ablakba eső `ChordObservation`-ökből: a legtovább fennálló címke
egyezése dönt `correct`/`wrong` között; üres ablak, vagy ha egyetlen címke sem
éri el a stabilitási küszöböt → `insufficientData`; ha az ablak minden
megfigyelése `label == null` → **`noDetection`**; elvárt akkord nélküli
célesemény → `notApplicable`.

A **`chordStableDuration` nem a `ScoringProfile`-on van**, hanem a
`PracticeObservationConfig`-on (`lib/features/practice/application/`, R08,
alapérték 180 ms) — a scorer **paraméterként** kapja. A `ScoringProfile`
bővítése ezzel a mezővel tilos.

### 5b. A `ChordOutcome` additívan bővül `noDetection`-nel

**Mért ütközés a pre-flightban:** a kör tervezett viselkedése öt chord-kimenetet
ír le, a `ChordOutcome` enum viszont **négyértékű**
(`correct, wrong, insufficientData, notApplicable`) — `noDetection` **nincs**
benne, és a `practice_verdict.dart` a kör tiltott zónájában volt.

Feloldás: a `ChordOutcome` **additívan** bővül a `noDetection` értékkel, az enum
**végére** fűzve (meglévő érték átnevezése, törlése, átsorolása tilos). Ez
biztonságos: a `ChordOutcome`-nak ma **egyetlen production fogyasztója sincs**
(mérve: `grep -rn ChordOutcome lib/ test/` → három találat, mind teszt-oldali
konstrukció), tehát nincs kimerítő `switch`, amit a bővítés törne.

Miért nem az `insufficientData`-ba olvasztva: a „hallgattunk, de akkordot nem
hallottunk" és a „nem gyűlt elég adat" **különböző** felhasználói üzenet és
különböző coaching (Kör 18), és az **E02-R15 briefje már erre a
megkülönböztetésre épül** (`noDetection` · `unstable` · `insufficientSignal`,
külön jelenítve). Az összevonás egy későbbi kört kényszerítene a modell
újranyitására.

### 6. Metrika-indokkódok stabil készlete

`PracticeMetricReasonCode` (additív a `practice_metrics.dart`-ban), legalább:
`practice.metric.no_signal` · `practice.metric.no_applicable_targets` ·
`practice.metric.chord_unstable` · `practice.metric.insufficient_samples`.
Szabad string reason-code a scorerből nem kerülhet ki.

### 7. Overall: EGYETLEN csonkoló osztás, csak az elérhető dimenziókra

```text
overallPerMille = Σ(weight_i * scorePerMille_i) ~/ Σ(weight_i)
```

ahol `i` **kizárólag** az `MetricAvailable` dimenziókon fut. A nem elérhető
dimenzió **a nevezőből is kimarad** — nulla értékkel beszámítani tilos. Ha nincs
egyetlen elérhető súlyozott dimenzió sem (`freePracticeOpen`, üres súlyok) →
`overall = MetricNotApplicable`.

A különbség nem kozmetikai: `chordProgressionDefault` profilon `rhythm = 1000`,
`direction = 1000`, `chord = n/a` esetén a helyes eredmény **1000**, a
nulla-kitöltéses hibás implementációé **650**.

### 8. Completion és a kettős pass-kapu

`completion = resolvedTargets / totalTargets` ezrelékben, ahol „resolved" minden
**kötelező** (nem `optional`) lezárt célesemény. A `optionalUnmatched` feloldás
sem completionben, sem dimenzióban **nem büntethető**.

A pass **csak akkor** igaz, ha `completionPerMille >= completionThresholdPercent * 10`
**és** `overallPerMille >= overallThresholdPercent * 10`. A completion-kapu az
SDD §16.6 által külön kiemelt „kevés, de jó eventtel is átmegy" hiba ellen van.

### 9. Combo és pont — legacy-paritással

`combo++` a tiszta feloldás **előtt**, majd `points += base * multiplier(combo)` a
**már növelt** combóval. Multiplier-lépcsők `5/10/20 → ×2/×3/×4`; base
`100/70/40` a `perfect/good/egyéb-találat` szerint. `wrong` és `missed` nullázza
a combót és nem ad pontot; `optional` célesemény a combót nem befolyásolja.

A sorrend nem részletkérdés: a „növelés ELŐTTI multiplierrel szorzunk" változat
az ötödik egymás utáni találatnál tér el először (600 helyett 500).

### 10. A pass-politika szándékosan eltér a legacytől

A legacy `passed = accuracy >= 0.70`; a §8 kettős kapuja **más politika**. A
scorer az újat implementálja, a paritás-teszt a `passed`/`outcome` mezőt **nem**
hasonlítja. A migrált Learn pass-leképezése az **E02-R19** hatásköre.

### 11. `ScoringProfile` drift — a kód a mérce

A `chordProgressionDefault` súlyai a kódban **40/25/35** (rhythm/direction/chord),
az SDD §16.6-ban 35/30/35. **A kód a mérce** (az R03-ban így ment át a review-n,
és a validáció is erre épül). A súlyokat ez a kör **nem** írja át; az eltérés
feloldása az SDD-szöveg oldalán, külön körben történik.

### 12. A µs-kvantált időalap az igazság; a paritás védősávval érvényes

A scorer a compiled targetet követi, nem a legacy `double`-t. A `double` időalap
visszahozása a domainbe tilos — két lezárt kört nyitna újra (ADR 0066 / 0072).

A legacyvel való egyezés ezért **a döntési határoktól levezetett védősávon
kívül** követelmény, ott viszont **egzaktul, tűrés nélkül**. Egy esemény akkor
esik a sávba, ha `| |offset| − küszöb | < 1 µs` a §3 három küszöbének
bármelyikére. A sáv szélessége **mérendő**, nem feltételezendő (a kör A7b
pontja), a sávba eső cellák pedig **kipinnelve**, a tényleges eseménylistából
generálva (A7c) — az idealizált rácsból számolt referenciacella az E02-R09 mért
hibája volt ([`docs/LESSONS.md`](../LESSONS.md) L16).

## Következmények

- A `PracticeVerdict` és `PracticeMetrics` első előállítója létrejön; a modellek
  R03 óta álló validációi élesben mérnek (a kör A8 pontja).
- A `ChordOutcome` ötértékű lesz. Bárki, aki később kimerítő `switch`-et ír rá,
  öt ágat kezel.
- **Hívó továbbra sincs**: a practice flagek OFF-ban maradnak, a production
  viselkedés változatlan. Az első valódi hívó az **E02-R11** session controller.
- Kockázat: ha a mért védősáv szélesebb a levezetettnél, az **lelet** (a kör
  `stopped`-dal áll meg a két számmal), nem a tűrés kiszélesítésével kezelendő.

## Elutasított alternatívák

- **Lebegőpontos pontszám végig.** A `matchWindow` határon nem ad egzaktul
  tesztelhető értéket (§2).
- **Nulla-kitöltés a hiányzó dimenzióra.** Hamis állítást tesz a felhasználó
  teljesítményéről (§7).
- **A `noDetection` beolvasztása az `insufficientData`-ba** a modell
  érintetlenül hagyásáért: az R15 külön jelenítést vár, az összevonás oda
  tolná a modellnyitás költségét (§5b).
- **A matcher bővítése iránnyal**, hogy a direction-scorernek ne kelljen külön
  bemenet: lezárt kört nyitna újra, és a matcher `O(célesemény)` memória-
  garanciáját rontaná (ADR 0075).
