# E02-R09 review — Event matcher és legacy timing parity

- **Kör:** E02-R09 — [`docs/rounds/e02-r09-event-matcher.md`](../rounds/e02-r09-event-matcher.md)
- **ADR:** [0075](../adr/0075-practice-event-matcher.md) (+ a §2b kiegészítés ebben a körben)
- **Branch / commit:** `codex/e02-r09-event-matcher` @ **`4359db1`**, javító kör @ **`9179483`**
- **Implementer:** **Codex**
- **Reviewer:** Claude (Opus 5), read-only — production kódot nem írtam
- **Dátum:** 2026-07-31
- **Verdikt:** első kör **CHANGES REQUESTED** (0 BLOCKER · 0 MAJOR · **1 MINOR** ·
  3 NOTE) → javító kör után **APPROVED** (lásd §9)

---

## 1. Összefoglaló

A kör egy pure, determinisztikus, kurzoralapú `PracticeEventMatcher`-t ad, ami a
legacy `LessonScorer` párosítási szemantikáját (ADR 0075 P1–P9) a levezetett
védősávon kívül **bitre** megőrzi, és a sávon belüli — kvantálásból eredő —
divergenciát **megnevezett, tesztelt viselkedésként** pinneli ki.

**A kör érdemi tartalma nem a kód, hanem egy szerződéshiba megfogása.** Az
implementer **kétszer** állt meg `stopped` jelzéssel, és **mindkétszer az
orchestrátornak volt igaza híján** — részletek a §5-ben. Egyszer sem tágított
fájllistát és egyszer sem igazította csendben a tesztet a hibás előíráshoz.

## 2. Scope-audit

`git diff --stat 1983bdb..4359db1`:

| Fájl | Sor | A brief §4 engedi? |
|---|---|---|
| `lib/features/practice/domain/service/practice_event_matcher.dart` | +257 | ✅ ÚJ |
| `test/features/practice/domain/practice_event_matcher_test.dart` | +430 | ✅ ÚJ |
| `test/features/practice/domain/practice_event_matcher_parity_test.dart` | +652 | ✅ ÚJ |
| `test/property/practice_event_matcher_property_test.dart` | +394 | ✅ ÚJ |
| `docs/rounds/e02-r09-event-matcher.md` | §8 | ✅ csak a handoff |

**Nincs listán kívüli fájl.** `lib/features/learn/**`: **0 sor** — a paritás
referenciája sértetlen. A `lib/` alatti teljes diff a **egyetlen** új
matcher-fájl (A9 ✅). Hívó, provider, feature flag nincs.

## 3. Gate — SAJÁT futtatás, izolált klónban

Nem bemondásra: `git clone --branch codex/e02-r09-event-matcher … /tmp/review-e02-r09`,
majd az előírt egyetlen artefaktum-hívás, csővezeték nélkül:

```
tools/round-gate.sh test/features/practice/ test/property/practice_event_matcher_property_test.dart
```

| Lépés | Eredmény |
|---|---|
| [1] format | ZÖLD (532 fájl, 0 changed) |
| [2] analyze | ZÖLD |
| [3] test `test/features/practice/` | ZÖLD — **462** teszt |
| [4] test property | ZÖLD — **3** teszt |
| [5] architecture | ZÖLD (12 allowlisted, **nem bővült**) |

Exit code **0**. Egyezik az implementer §8-ban közölt kimenetével.

**Property gate friss seedekkel** (a CI HARD lépését utánozva) — `PROPERTY_SEED`
= `20260731`, `987654321`, `13`: mindhárom **3/3 zöld**. Nem seed-42-re hangolt.

## 4. Valódi-sértés próbák (a review saját mércéje)

A zöld gate nem bizonyíték — ezért **tíz** eldobható rontást vittem a matcherbe
külön klónban (`/tmp/probe-e02-r09`), és megnéztem, PIROSRA fut-e a hozzá tartozó
őr. **Mind a tíz piros lett**, tehát minden előírt él valóban őrzött:

| # | Szándékos rontás | Melyik szabály | Eredmény |
|---|---|---|---|
| 1 | jogosultság `<=` → `<` | P2 / A2 | 🔴 PIROS |
| 2 | holtverseny `<` → `<=` | P4 / A4 | 🔴 PIROS |
| 3 | zárás `<` → `<=` | P7 / A2 | 🔴 PIROS |
| 4 | latency elhagyva a **záró** ágon | P1 / A3 | 🔴 PIROS |
| 5 | latency elhagyva a **párosítási** ágon | P1 / A1 | 🔴 PIROS |
| 6 | kurzor → **full scan** | A6 számláló | 🔴 PIROS |
| 7 | rossz irány **nem** fogyaszt | P5 / A5 | 🔴 PIROS |
| 8 | **non-vacuity:** a matcher soha nem párosít | A1 | 🔴 PIROS |
| 9 | `timingOffset` előjel megfordítva | §5.1 | 🔴 PIROS |
| 10 | opcionális cél `missed`-ként zárul | §5.5 / A5 | 🔴 PIROS |

A **6.** a brief által külön kért próba: a kurzorosság **mérve** van, nem ígérve.
A **8.** azt zárja ki, hogy a paritás azért legyen egzakt, mert egyik oldal sem
párosít semmit — a harness bizonyítottan **nem üres**.

A próbák után a forrás bitre visszaállítva (`diff` OK); a próbaklón eldobható.

## 5. A kör érdemi hozadéka: két orchestrátor-hiba, mindkettő a mércében

| # | A hiba | Ki fogta meg | Feloldás |
|---|---|---|---|
| 1 | Az A1 **tűrés nélküli µs-paritást** írt elő a legacyvel szemben, miközben a bemenet **µs-ra kvantált** compiled target. A legacy kerekítetlen `double`-lel dönt → a két időalap ≤ 0,5 µs-ban eltér, ami a döntési határon meghatározó. **Matematikailag teljesíthetetlen volt.** | Implementer (`stopped`) | brief §0.1 + ADR 0075 **§2b**: a µs-alap az igazság; levezetett védősáv; A1b/A1c új pontok |
| 2 | A §0.1-be írt `anthem-drive` referenciacella (`153 061,408 / 153 061,041 µs`) **téves** volt — idealizált nyolcad-rácsból számoltam, de a lecke mintája `[_d, null, _d, _u, null, _u, _d, _u]`, így a hivatkozott `beat 0 → 0,5` pár **nem is létezik**. | Implementer (`stopped`) | a kanonikus cella `[5,6]`, felezőpont `4 744 898 µs`, `153 061,265306 / 153 061,183673 µs` |

Mindkét számot **függetlenül reprodukáltam** a review előtt; a 2.-nál az
implementer mérése bizonyult helyesnek. **Egyik esetben sem tágított
fájllistát és nem igazította hozzá a tesztet a hibás briefhez** — ez pontosan
a STOP-klauzula rendeltetése.

Külön kiemelendő: az implementer a **saját zöld harness-ét** minősítette
elégtelen bizonyítéknak (51 szcenárió, 0 µs eltérés, de az élek érintetlenül),
és adversarial auditot futtatott ellene. A védősáv így nem véletlen elkerülés:
a harness **állítással** ellenőrzi minden megfigyelésre (`≥ 1 µs` jogosultság,
`≥ 2 µs` argmin, `≥ 1 µs` zárás), és **0** kizárt megfigyelést jelent.

## 6. Acceptance criteria — tételes ellenőrzés

| # | Kritérium | Bizonyíték | ✓ |
|---|---|---|---|
| A1 | 17 lecke × 3 latency egzakt paritás | 51 szcenárió, max eltérés **0 µs**, kizárva **0**; valódi `LessonScorer` orákulum, cél-szintű egész összevetés, `closeTo` sehol; non-vacuity próbával igazolva | ✅ |
| A1b | időalap-eltérés ≤ 0,5 µs | **348** esemény mérve, max **0,489795919508 µs** (`anthem-drive[23]`) — a 0,5 elméleti korlát alatt, ahogy kell | ✅ |
| A1c | a két divergencia-cella kipinnelve | `first-strums[0]` és `anthem-drive[5,6]`, egzakt legacy `double` értékekkel; **egyeznek a reviewer független számításával** | ✅ |
| A2 | él-mátrix hat cellája + együttes cella | mind kipinnelve; 1., 3. próba pirosra fut | ✅ |
| A3 | latency-mátrix (0/40/**300** ms) | mindkét útvonalon; a 300 > 280 ms külön állítva; 4., 5. próba pirosra fut | ✅ |
| A4 | holtverseny + ±1 µs szomszédok | egész-µs felezőpont, azonos időnél kisebb index; 2. próba pirosra fut | ✅ |
| A5 | egy-az-egyhez invariánsok | unit + property; 7., 10. próba pirosra fut | ✅ |
| A6 | kurzor **43 000 ≤ 1 344 000**, memória **4 = 4** | a két `@visibleForTesting` számláló; 6. próba (full scan) pirosra fut | ✅ |
| A7 | randomizált property | 3/3 zöld seed 42 **és** három friss seed mellett | ✅ |
| A8 | domain-tisztaság + architecture | gate [5] zöld, allowlist változatlan; a purity-teszt könyvtár-rekurzív, tehát automatikusan fedi az új fájlt | ✅ |
| A9 | nulla production viselkedésváltozás | `lib/` diff = 1 fájl, `learn/` 0 sor, hívó/provider/flag nincs | ✅ |

## 7. Leletek

### MINOR-1 — A `PracticeEventMatchResult` `==`/`hashCode` sehol nincs tesztelve

`lib/features/practice/domain/service/practice_event_matcher.dart:73–92`

Az új publikus értéktípus kézzel írt `operator ==` és `hashCode` párt kap, de a
repóban **egyetlen teszt sem hivatkozik rá** (`grep -rn "PracticeEventMatchResult" test/`
csak a matcher saját tesztjeit hozza, és azok sem egyenlőséget mérnek). A
szomszédos domain-modellek egyenlőségét a `practice_value_equality_test.dart`
őrzi — az új típus kimaradt belőle (az a fájl nem volt az engedélyezett listán,
tehát ez **nem az implementer scope-sértése**).

Ellenőrzéssel mindkét metódus **helyes** (mind a hat mezőt fedi, szimmetrikusan),
tehát élő hiba nincs — a lelet **fedettségi**: egy későbbi mezőbővítés csendben
kihagyhatja az egyik oldalt, és semmi nem fogná meg. Ez pontosan az E02-R04
MAJOR-jainak osztálya („nem tesztelt állítás a típusról").

**Javasolt irány:** a `practice_event_matcher_test.dart`-ba (már engedélyezett
fájl) egy egyenlőség/hashCode teszt — azonos mezőkkel egyenlő, **mezőnként**
eltérve nem egyenlő. Production kód nem változik.

### NOTE-1 — Az „unmodifiable eredménynézet" állítás nincs teszttel bizonyítva

`practice_event_matcher.dart:111, 128`. A `results` valóban `UnmodifiableListView`,
és a §8 handoff „live unmodifiable eredménynézet"-et állít, de nincs teszt, ami
a mutációra dobott kivételt mérné. A típusrendszer garantálja, ezért **nem
blokkol** — a MINOR-1 javításával egy sorban lezárható.

### NOTE-2 — A matcher nem adja vissza a párosított megfigyelés **irányát**

A `PracticeEventMatchResult` a `sequence`-et, a korrigált időt és az előjeles
eltérést hordozza, a `StrumDirection`-t nem. Ez **szándékos és helyes** (ADR 0075
§1: a matcher pontozás-mentes, `O(célesemény)` memória, megfigyelést nem tárol),
de a **Kör 10** direction-scorerének a hívónál kell párban tartania a
megfigyelést a visszakapott eredménnyel. Érdemes az R10 briefjében kimondani,
nehogy ott derüljön ki.

### NOTE-3 — Rendezetlen, kézzel épített target viselkedése dokumentált, de nem tesztelt

A §8 helyesen rögzíti (a brief §2.2 kérése szerint), hogy szerződéssértő,
nem monoton `events` listán a bináris alsó korlát és a kurzor jogosult célt
átugorhat, és a matcher **szándékosan nem** rendez át futásidőben. Teszt nincs
rá — nem is kell, mert a compiler `StateError`-ral fail-fast (`practice_target_compiler.dart:189`).
Rögzítve, hogy a Kör 11 hívója se essen bele.

## 8. Merge-döntés

**0 BLOCKER · 0 MAJOR** → a merge nincs blokkolva. A MINOR-1 a diffet nem
hizlalja és már engedélyezett fájlban javítható, ezért **rövid javító kört**
kérek rá (a NOTE-1-gyel együtt), utána CI-dispatch és zöld kapus merge.

**Nyitott az R10/R11 felé:** NOTE-2 (irány a hívónál), NOTE-3 (rendezetlen
target), és a brief §10.6 korábbi follow-upjai.

---

## 9. Javító kör — újraellenőrzés (`9179483`)

**Verdikt: APPROVED.** Diff: **csak** `practice_event_matcher_test.dart` (+220)
és a §8 handoff — **production kód nem változott**, ahogy elő volt írva.

### 9.1 Egy negyedik orchestrátor-hiba, megint a mércében

A javító prompt eredeti MINOR-1 előírása (**„mind a hat mezőre külön cella"**)
**önellentmondó volt** a vele egy lapon álló „production kód NEM változik"
kikötéssel: a `PracticeEventMatchResult` mindkét konstruktora privát (`._`,
`._open`), tehát tesztből csak a matcher publikus API-ján át kaphatók példányok,
a `timingOffset` pedig származtatott (`observedAt − target.time`), ezért soha
nem variálható önállóan. Az implementer **harmadszor is `stopped`-dal jelzett**,
és a következtetése pontosabb volt a kérésnél:

**A `timingOffset` jelenléte az `==`-ben bizonyíthatóan redundáns** — `observedAt`
és (a `target`-en keresztül) `target.time` már összevetésre kerül, tehát nincs
olyan két példány, amit **csak** ő különböztetne meg. Nem hiányzó teszt, hanem
levezetett tény; a §8 ezt rögzíti is.

A pontosított előírás (négy izolált negatív cella + egy összevont
`observedAt`/`timingOffset` cella + pozitív cella) így teljesíthető lett,
production API-tágítás nélkül.

### 9.2 Gate — saját újrafuttatás friss klónban

`/tmp/review2-e02-r09`, ugyanaz az egyetlen artefaktum-hívás:
format **ZÖLD** · analyze **ZÖLD** · `test/features/practice/` **ZÖLD — 469
teszt** (462 → 469, azaz **+7** új cella) · property **ZÖLD 3** ·
architecture **ZÖLD** (allowlist változatlan). Exit **0**.

### 9.3 A lelet zárásának valódi-sértés próbája

Hét további rontás a matcheren (`/tmp/probe2-e02-r09`), az `==`/`hashCode`/
unmodifiable őrökre:

| Szándékos rontás | Eredmény |
|---|---|
| `==` kihagyja a `resolution` mezőt | 🔴 PIROS |
| `==` kihagyja a `matchedObservationSequence` mezőt | 🔴 PIROS |
| `==` kihagyja a `targetIndex` mezőt | 🔴 PIROS |
| `==` kihagyja a `target` mezőt | 🔴 PIROS |
| `==` kihagyja az `observedAt` **és** `timingOffset` mezőt | 🔴 PIROS |
| `results` már nem `UnmodifiableListView` | 🔴 PIROS |
| `hashCode` → konstans `0` | 🟢 zöld maradt |

**Az utolsó NEM lelet, és szándékosan nem is az.** A Dart-szerződés csak annyit
követel, hogy **egyenlő** objektumok hashCode-ja egyezzen; a konstans hashCode
legális (csak teljesítmény-romlás), a hash-ütközés megengedett. Egy „különböző
objektum → különböző hashCode" állítás **túlspecifikálás** volna. A próbám volt
rossz, nem a teszt — rögzítve, hogy a következő reviewer ne írja ki leletnek.

**MINOR-1 és NOTE-1 lezárva.** NOTE-2 és NOTE-3 szándékosan nyitva (R10/R11).
