# E14-R36 — Today és a „10 hasznos perc" lánc (ADR 0546)

- **Kör:** E14-R36 · **Csomag:** PKG-C · **ADR:** 0546
- **Ág:** `claude/laptop-apk-debug-prompt-kys4oa`
- **Környezet:** nincs Dart/Flutter SDK → **lokális gate nem futtatható**;
  egyetlen teszt sem futott le itt. Mérce: `full-gate.yml` + a valós
  APK-teszt.

## 1. Cél

A Ch14 Kör 36 hiányzó fele: a nevesített **10 perces LÁNC**
(`hangolás → ritmus/akkord gyakorlat → rövid eredmény`) egyetlen vezetett
folyamként, állapotgéppel — lépések, továbblépés, megszakítás, folytatás —,
a Today-kártyáról vezérelve, **az audit-L1 CTA megsértése nélkül**.

## 2. Mért állapot (a kör előtt)

- `TodayHubScreen` kész: egyetlen elsődleges CTA, streak/napi cél,
  `TodayPlanSnapshot` empty/loading/error, `practiceCatalogProvider`
  const-lookup, 2 tapon belüli indulás.
- A lánc **nem létezett**: a CTA `/practice/setup?id=`-re megy, a hangoló
  külön sziget (`/practice/tuner`), semmi nem köti össze őket és semmi nem
  tudja, hogy a felhasználó félbehagyta.
- `PracticeEntry` nap-granularitású (nincs időbélyeg) — „gyakorolt-e azóta?"
  a naplóból nem válaszolható meg. Ami mozog:
  `dailyGoalActiveSecondsProvider(today)`.
- `/practice/result` a routerben `PracticeResultFallback` — Today felől
  odanavigálni zsákutca.
- `StorageKeys` nem PKG-C tulajdon → új perzisztens kulcs ebben a körben nem
  születhet.

## 3. Scope

**Benne:** `TenMinutePlan` kompozíciós szabály; `TenMinuteFlowState` +
`resolveTenMinuteFlow` (tiszta, nem író feloldás); `TenMinuteFlowController`;
lépés→route szabály (közös a hétköznapi CTA-val); a Today-kártya lánc-módja;
a hangoló átadási pontja; `features/today/public.dart` barrel (a hangoló
csak ezen keresztül ér a láncba).

**Kívül:** bármilyen változtatás `lib/features/practice/**`-ben (PKG-F);
új route regisztrálása (`lib/app/routing/**` nem PKG-C); a `.arb` fájlok
(l10n scratch-protokoll); a lánc cross-launch perzisztálása (`StorageKeys`).

## 4. Érintett fájlok

**Új**

- `lib/features/today/domain/ten_minute_flow.dart`
- `lib/features/today/domain/ten_minute_flow_destinations.dart`
- `lib/features/today/providers/ten_minute_flow_providers.dart`
- `lib/features/today/public.dart`
- `test/features/today/ten_minute_flow_test.dart`
- `test/features/today/ten_minute_flow_navigation_test.dart`
- `test/features/tuner/ten_minute_flow_handoff_test.dart`

**Módosított**

- `lib/features/today/screens/today_hub_screen.dart` — lánc-mód a hero
  kártyán; a `_primaryCtaLocation` privát metódus helyett a megosztott
  `practiceStartLocation` szabály (az L1 URI bitre azonos marad)
- `lib/features/tuner/screens/tuner_screen.dart` — a lánc 1. lépésének
  átadási gombja a `bottomAction` slotban

**l10n scratch:** `<scratch>/l10n/PKG-C.json` — `base` szegmens 11 kulcs,
`tuner` szegmens 2 kulcs (kulcs + `@`-metaadat + magyar fordítás együtt).

## 5. Döntések

Lásd [ADR 0546](../adr/0546-ten-minute-practice-chain.md) D1–D7. Röviden:
a kompozíció szabály (2 + maradék + 1, összeg-invariánssal); a lánc opt-in és
soha nem rontja el az L1 CTA-t; a recap helyben renderelődik (nincs
`/practice/result` zsákutca); a `play` lépést MÉRT idő zárja; a hangolást
csak a játékos zárja; 2 órás resume-ablak tiszta feloldással; session-scope
kimondva, cross-launch resume nem készült el.

## 6. Acceptance

| # | Kritérium | Státusz |
|---|---|---|
| A1 | A kompozíciós szabály összege minden elfogadott totálra pontos | **PINNED-BY-TEST** — `ten_minute_flow_test.dart` „the sum invariant holds for EVERY accepted total" |
| A2 | Egy 1 perc játékot sem fedező totál elutasításra kerül, nem szorul össze | **PINNED-BY-TEST** — „a total that cannot fund one minute of playing is REJECTED" + „exactly at the 2 + 1 + 1 boundary is accepted" |
| A3 | A lánc lépés-sorrendje `tune → play → review`, majd véget ér | **PINNED-BY-TEST** — „the chain is tune → play → review, then it ends" |
| A4 | Megszakítás: a resume-ablakon belül folytatható, azon túl eldobódik; visszafelé lépő óra nem bizonyíték | **PINNED-BY-TEST** — „interruption (folytatás / megszakítás)" csoport 3 cellája + „a chain left behind hours ago is NOT resurrected" |
| A5 | Folytatás: a hubot elhagyva és visszatérve UGYANAZ a lépés folytatódik | **PINNED-BY-TEST** — „the chain survives leaving the hub" |
| A6 | 2 tap = a lánc első láncszeme (valódi `TunerScreen`, valódi routeren) | **PINNED-BY-TEST** — „start + next action = 2 taps to the tuner route" + „two taps from Today land on the real TunerScreen" |
| A7 | Minden lánc-CTA VALÓS, regisztrált route-ra mutat | **PINNED-BY-TEST** — a valódi `routerProvider`-es cella (a `placeholder_wiring` őr szabálya a láncra alkalmazva) |
| A8 | Az audit-L1 CTA nem regresszált: lánc nélkül az elsődleges CTA az ajánlott gyakorlat setup-URI-ja | **PINNED-BY-TEST** — „with no chain running the ONE primary CTA still lands on the recommended practice" + a meglévő `hub_navigation_test.dart` L1 csoport változatlanul zöld |
| A9 | A1 sértetlen: minden lánc-állapotban pontosan EGY `FilledButton` | **PINNED-BY-TEST** — két cella (lánc nélkül / lánc közben) |
| A10 | A `play` lépés a hétköznapi CTA-val AZONOS URI-ra megy | **PINNED-BY-TEST** — „the play step opens the SAME recommended exercise" |
| A11 | A recapra váltást MÉRT gyakorlási idő nyitja, nem a setup megnyitása | **PINNED-BY-TEST** — „MEASURED practice time — not having opened the setup screen — is what promotes the chain" + a domain 3 cellája |
| A12 | A hangolás lépését csak a játékos zárja le, és rögtön a gyakorlatra visz | **PINNED-BY-TEST** — `ten_minute_flow_handoff_test.dart` 4 cellája |
| A13 | Offline: a lánc egyetlen hálózati hívást sem tesz | **PINNED-BY-TEST (közvetetten)** — a `today_hub_test.dart` A4 forrás-szkennelése a teljes `lib/features/today` fán fut, és a lánc semmilyen erőforrás-API-t nem hivatkozik; a `fake_network_guard` szintén nem kap új hívást |
| A14 | A lánc túléli a process halálát (cross-launch resume) | **NOT-DONE** — `StorageKeys` nem PKG-C tulajdon; javasolt patch a §10-ben. A jelenlegi viselkedés ŐSZINTE: kilőtt app után nincs lánc |
| A15 | A 2 / 7 / 1 perces arány pedagógiailag helyes | **NEEDS-MEASUREMENT** — terméki/mérési kérdés (E14-R40 field study); a szabály paraméteres, hogy cserélhető legyen |
| A16 | A cellák ténylegesen zöldek | **NEEDS-MEASUREMENT** — nincs Dart SDK; a mérce a CI |

## 7. Verifikáció

Lokálisan **nem futtatható**. A körben megírt cellák (fájl → csoport):

- `test/features/today/ten_minute_flow_test.dart` — 5 csoport, 17 cella
  (kompozíciós szabály, lépésgép, megszakítás, mért bizonyíték, tiszta
  feloldás)
- `test/features/today/ten_minute_flow_navigation_test.dart` — 5 csoport,
  8 cella (opt-in/L1, kétérintéses indulás, folytatás, megszakítás, recap,
  valódi router)
- `test/features/tuner/ten_minute_flow_handoff_test.dart` — 4 cella

Sikeres verifikációt **tilos állítani** (Ch14 §9/9).

## 8. Kockázatok

- **KÖTELEZŐ golden-újragenerálás.** A Today hub hero-kártyája egy másodlagos
  akciógombbal bővült, ezért a `test/ui/goldens/goldens/e13_r17_today_hub_compact.png`
  és `…_compact_scale2.png` **el fog térni**. A PKG-C tulajdon kifejezetten
  kizárja a golden PNG-k írását (és a boxon nincs Flutter SDK), ezért ezt az
  orchestrátornak / a felhasználó gépének kell elvégeznie:

  ```bash
  flutter test --update-goldens test/ui/goldens/e13_r17_screens_golden_test.dart
  ```

  A többi golden **nem** érintett: a hangoló új gombja csak futó lánc mellett
  renderelődik (a golden-cellák nem indítanak láncot), a metronóm változása
  pedig csak reduced motion alatt látszik. A `e13_r36` / `e15_r13`
  variant-mátrixok NEM golden-összehasonlítók, hanem overflow-mátrixok — a
  Today body `ListView`, tehát a plusz gomb ott görgethető, nem túlcsordulás.
- **Formázás.** `dart format` nem futott; a fájlok kézzel 80 oszlopra és a
  szomszédos fájlok stílusára vannak igazítva, de egy formázás-kapu
  eltérést jelezhet.
- **Copy-függő állítások.** Három cella szöveget keres
  (`'Step 1 of 3'`, `'Tune up'`, `'Finish'`). Ezek a `<scratch>/l10n/PKG-C.json`
  angol értékei; ha az orchestrátor a beolvasztáskor átfogalmazza őket, a
  cellákat vele együtt kell frissíteni.
- **A `today/public.dart` új barrel.** Kézzel írt (a `today` alatt nincs
  `public/` fragment-könyvtár, tehát a generált-barrel őr nem érinti), de a
  cross-feature import-őr MOST kezdi el figyelni ezt a felületet.

## 9. Nem-célok

Nem hangol DSP-küszöböt. Nem nyúl a gyakorló-motorhoz. Nem regisztrál új
route-ot. Nem billenti át az `adaptiveShellEnabled` GA-zászlót (R35 nyitott
pontja **emberi döntés**).

## 10. Handoff

### 10.1 Kérés az orchestrátorhoz — l10n

`<scratch>/l10n/PKG-C.json` beolvasztása: `base` szegmens (11 kulcs,
`todayHubTenMinute*`) és `tuner` szegmens (2 kulcs, `tunerTenMinute*`),
mindkettő `en` + `hu` + `@`-metaadattal, a meglévő szegmens-sorrend
megtartásával.

### 10.2 Javasolt patch PKG-D-nek — cross-launch resume (A14)

Két lépés, mindkettő PKG-D / core tulajdon:

1. `lib/core/storage/storage_keys.dart`, a `--- practice ---` blokk után:

   ```dart
   // --- today ---------------------------------------------------------------
   /// The in-progress "10 useful minutes" chain (E14-R36, ADR 0546 D7).
   /// Holds only the step, the start time and the active-seconds baseline —
   /// never a plan the user did not start.
   static const String tenMinuteFlow = 'ss.today.ten_minute_flow';
   ```

2. `lib/features/today/providers/ten_minute_flow_providers.dart` (PKG-C
   tulajdon, a következő PKG-C körben landolható, amint a kulcs a fán van):
   a `TenMinuteFlowController.build()` a `keyValueStoreProvider`-ből
   olvassa vissza a szerializált állapotot, `start`/`advance`/`abandon`
   pedig `PersistedPreference.persist`-tel írja. A visszaolvasott állapotra
   a `resolveTenMinuteFlow` resume-ablak szabálya **változatlanul** áll, így
   egy tegnapi lánc nem támad fel.

### 10.3 Amit a következő PKG-C kör folytathat

- A recap ma a Today-kártya. Ha a gyakorló-motor egy tényleges
  `PracticeResult`-ot ad át (PKG-F), a `review` lépés kaphat valódi
  eredmény-route-ot — `tenMinuteStepLocation` már `String?`-ot ad, tehát
  egyetlen `switch` ág cseréje.
- A `TenMinutePlan.of(total)` paraméteres: egy 5 vagy 20 perces változat
  konfigurálható, amint van rá mérés (A15).
