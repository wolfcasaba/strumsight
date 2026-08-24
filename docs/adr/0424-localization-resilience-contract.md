# ADR 0424 — A lokalizációs törésbiztonság szerződése: fragmentum-szintű paritás, nyelvhelyes többes szám, racsnis szöveg-guard

- **Státusz:** elfogadva (2026-08-24)
- **Kör:** E13-R15 (Chapter 13 — UI/UX Design System, Kör 15)
- **Kontextus:** ADR 0307 §4 (ARB-fragmentum architektúra), ADR 0277
  (hibaüzenet-modell), SDD Ch13 §9.15 (tartalmi szabályok), `docs/LESSONS.md`
  L342, L365, L369, L396, L452, L460
- **Döntéshozó:** Claude (Opus 5) orchestrátor, a kör pre-flightjában, mérés
  alapján

## 1. Kontextus

A StrumSight kétnyelvű (en/hu). A „minden felhasználói szöveg ARB-n át megy"
szabály (CLAUDE.md) eddig **szövegesen** létezett, gépi mérce nélkül a
design-system rétegben. Közben az l10n-architektúra átalakult: az ADR 0307 §4
óta a `lib/l10n/app_<locale>.arb` **generált aggregátum**, a szerkeszthető
forrás a `lib/l10n/base/` + `lib/l10n/features/<feature>_<locale>.arb`.

A meglévő paritás-kapu (`test/core/l10n_parity_test.dart` +
`tool/ci/check_l10n_parity.dart`) az **aggregátumot** méri. Mérve
(2026-08-24, `7038f194`): a paritás minden szinten teljes — aggregátum
1838/1838, és mind az öt szegmens 1:1. A kockázat tehát nem a mai állapot,
hanem a **jövőbeli drift**, és az, hogy egy aggregátum-szintű hiba nem mondja
meg, melyik fragmentumot kell kinyitni.

Három konkrét, mért csapda indokolja a döntést:

1. **A generált fájl forrásnak nézése.** Négy körben ismétlődött (L365, L369
   — H3 self-heal, L396, és most az E13-R15 briefje). A brief-oldali
   allowlist a generált aggregátumot sorolta fel ARB-írás céljára.
2. **A tükrözött magyar többes szám.** Mérve három kulcs
   (`streakV2{Current,Longest,Total}Semantics`): az en ICU `plural`-t használ,
   a hu csupasz `{count} nap`-ot. Ez **helyes magyar** — számnév után a főnév
   egyes számban marad. Egy „a hu is legyen plural" őr helyes kulcsokat
   váltana pirosra.
3. **A javíthatatlan sértés.** A `ss_validation_summary.dart:90`
   (`label: '${l10n.dsFieldErrorSemanticPrefix}: $message'`) valódi
   mondat-összefűzés, de a hívási helye kívül esik az E13-R15 engedélyezett
   listáján. Vagy elhallgatjuk (a guard hatókörét szűkítve), vagy nyilvánosan
   nyilvántartjuk.

## 2. Döntés

### 2.1 Az ARB-paritás mércéje FRAGMENTUM-szintű

Az en/hu kulcsparitást **minden forrás-szegmensre külön** mérjük
(`lib/l10n/base/app_{en,hu}.arb`, `lib/l10n/features/<f>_{en,hu}.arb`), nem
csak az aggregátumon. A hibaüzenetnek meg kell neveznie a **fragmentumot**.

Ez nem váltja le az aggregátum-szintű kaput — az a generátor kulcsvesztését
fogja (ADR 0307 §4), a fragmentum-szintű pedig a fordítói driftet, javítható
mutatóval.

### 2.2 A többes szám mércéje NYELVHELYESSÉG, nem tükrözés

1. en ICU `plural` → kötelező `other` ág.
2. A hu párja lehet ICU `plural` (min. `other`), **vagy** csupasz `{count}` —
   mindkettő helyes magyar.
3. A hu `plural` ágai csak `=<szám>` / `zero` / `one` / `other` lehetnek; a
   `few`/`many` (szláv, arab kategóriák) jelenléte hiba.
4. A hu üzenet `count=1` és `count=3` melletti kimenete **csak a számjegyben**
   térhet el.

**Amit ez TILT:** a „minden nyelv az angol ICU-szerkezetét másolja" szabályt.
A lokalizáció nem tükrözés.

### 2.3 A beégetett szöveg guardja RACSNI, befagyasztott alaphalmazzal

A guard hatóköre a **már migrált, routolt** design-system rétegek:
`components/**`, `accessibility/**`, `layouts/**`, `motion/**`. Kimarad a
`documentation/**` (fejlesztői galéria — mérve nulla hivatkozás rá a barrel-
exporton kívül; a minta-szövegei szándékosan illusztratívak) és a token/téma
réteg (`foundations/**`, `themes/**`, `icons/**`), amelyben nincs
felhasználói mondat.

A hatókörön belül ismert, de a kör scope-ján kívül eső sértéseket
**befagyasztott alaphalmaz** tartja nyilván. A mérce **pontos egyenlőség**:

- új sértés → piros (a lista nem nőhet);
- javított, de a listáról ki nem vett sértés → **szintén piros** (a lista nem
  avulhat el).

Minden bejegyzéshez kötelező a `fájl:sor`, a sértés osztálya, és az indok,
miért nem javítható abban a körben.

**Amit ez TILT:** a részhalmaz-alapú (`containsAll`, „legalább ennyi meg van
engedve") őrt, és a hatókör csendes szűkítését egy kényelmetlen találat körül.

### 2.4 A pszeudo-lokalizáció TESZT-MÓD, nem regisztrált nyelv

A pszeudo-locale string-transzformáció + teszt-oldali burkolat. Nem kerül a
`supportedLocales`-be, nem kap `AppLocalizations` delegáltat, és nem módosítja
az `l10n.yaml`-t. A transzform **legalább 1,6×** hosszúságot ad, és a
`{placeholder}` tokeneket érintetlenül hagyja.

### 2.5 A hossz-cellák `tester.view`-val méreteznek

A `MediaQuery(data: MediaQueryData(size: …))` widget-tesztben **nem** méretezi
a layoutot (L452, E13-R09-ben mérve). A clipping-cellák ezért
`tester.view.physicalSize` + `devicePixelRatio` párost állítanak, `addTearDown`
visszaállítással, és **igazolniuk kell**, hogy a tényleges render-méret
megegyezik a deklarálttal.

### 2.6 A formázók tiszta függvények

A locale-tudatos formázók (`lib/core/i18n/ss_formatters.dart`) `package:intl`
`NumberFormat`/`DateFormat` hívásokra épülnek, explicit `localeName`
paraméterrel. Nem olvasnak `BuildContext`-et, és nem használnak `toString()`-et
dátumra vagy számra.

**Amit ez TILT:** a tizedesjel, az ezres elválasztó és a dátum-sorrend
hardcode-olását (`en`: `1,234.5`; `hu`: `1 234,5`).

## 3. Alternatívák, amiket elvetettünk

| Alternatíva | Miért nem |
|---|---|
| Csak aggregátum-szintű paritás (a meglévő kapu) | A hibaüzenet nem mutat fájlra; a javító 5 szegmensben keresgél |
| „A hu tükrözze az en ICU-szerkezetét" | Három mérve helyes magyar kulcsot váltana pirosra (§1/2) |
| A guard hatóköréből kivenni az `inputs/**`-ot | Elhallgatná a §1/3 valódi sértést; a racsni nyilvánosan tartja |
| A galéria beemelése a hatókörbe | 38 azonnali piros, nem routolt kódra → a guardot kikapcsolnák |
| A pszeudo-locale valódi regisztrált nyelvként | `supportedLocales` és `l10n.yaml` érintése; szállított artefaktum lenne egy teszt-eszközből |
| Golden PNG a clipping mérésére | 4 golden van az egész repóban; font-törékeny CI-ben, és a golden csak bájt-diffre pirosodik, a túlcsordulásra nem |

## 4. Miért nem gyengül ettől a mérce

| Kockázat | Őr |
|---|---|
| a fragmentum-paritás csak az aggregátumot méri | cella: egy fragmentumból törölt kulcs pirosra vált, **és** a fragmentum neve szerepel az üzenetben |
| a racsni részhalmazra lazul | cella: a lista elavulása (javított, de bent hagyott sértés) is piros |
| a guard hatóköre csendben szűkül | a hatókör konstans a tesztben, rekurzív bejárással — új komponens automatikusan bekerül |
| a hu plural-szabály tükrözésre csúszik vissza | cella: `few{…}` beírása pirosra vált; `{count}`-os hu NEM vált pirosra |
| a hossz-cella a default viewporton mér | cella: a deklarált és a tényleges render-méret egyezését állítja (L452) |
| a pszeudo-transzform szétvágja a placeholdert | cella: token-megőrzés + számított minimum-hossz (1,6×) |

## 5. Következmények

**Pozitív.** A fordítói drift a fragmentumra mutató hibával bukik. A magyar
nyelvhelyesség gépi mérce, nem lektori vélemény. Az ismert, körön kívüli
sértések nyilvánosak és nem szaporodhatnak. A clipping-mérés a valódi
viewporton fut.

**Negatív / ár.** Minden új ARB-fragmentum egy újabb szegmens a paritás-
cellában. A racsni-lista karbantartást igényel: aki javít egy sértést, a
listát is frissítenie kell (ez szándékos — a lista nem avulhat el).

**Amit ez a döntés TILT.** Kézzel szerkesztett `lib/l10n/app_<locale>.arb`;
részhalmaz-alapú szöveg-guard; „az angol ICU-szerkezet a mérce" plural-őr;
`MediaQuery(size:)`-zal méretezett clipping-cella; `toString()` dátumra vagy
számra a formázókban.
