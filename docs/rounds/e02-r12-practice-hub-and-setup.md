# E02-R12 — Practice Hub és Setup UI

- **Státusz:** **PREPARED** (előre megírva 2026-07-31, kód olvasva: `main` @ `ce8fbce`)
- **SDD-kör:** [`docs/sdd/03-epic-02-practice-engine.md`](../sdd/03-epic-02-practice-engine.md) **„Kör 12"** (+ §21.1, §21.2, §22)
- **Branch:** `codex/e02-r12-practice-hub-setup`
- **Előfeltétel:** **E02-R11 merge-ölve** (a Setup a controller `PreparePractice`
  parancsát indítja).
- **ADR:** **0078** — `docs/adr/0078-practice-feature-surface-and-routing.md`,
  **az orchestrátor írja meg a pre-flightban** a §5 tartalmával.
- **Implementer motor:** a pre-flightban a user dönt. *Ajánlás:* **MiniMax M3** —
  volumenkör (widget + ARB + teszt), kevés ítéletigényes éllel (ADR 0069 §15.6).

> ⚠ **Pre-flight (indítás előtt KÖTELEZŐ)**
> 1. Olvasd újra az R11 controller providereit és a `PracticeSessionConfig`
>    validációját — a Setup mezőkészlete ahhoz igazodik.
> 2. Ellenőrizd, hogy az `AppRoutes` és az `app_router.dart` nem változott-e
>    (a §4 diff-felülete kicsi és pontos kell legyen).
> 3. ADR-szám ütközés ellenőrzése, majd az ADR 0078 megírása.
> 4. Státusz → PLANNING, dátum/sha frissítés, brief commit a kör-branchre.

## 0. Kör-jelzés — KÖTELEZŐ (AGENTS.md §15.2)

```bash
tools/codex-signal.sh progress "<egy sor>"
tools/codex-signal.sh done    "<egy sor>"
tools/codex-signal.sh stopped "<egy sor>"
tools/codex-signal.sh blocked "<egy sor>"
```

Lezáró jelzés nélküli kör = bukott kör. `gh`-t NE hívj, ne pusholj, PR-t ne nyiss.
**STOP-klauzula:** listán kívüli fájl, vagy ellentmondó előírás → `stopped`.
**A §7 a terved.**

## 1. Cél

A Practice Engine V2 tizenegy kör után **teljesen láthatatlan**: nincs egyetlen
képernyője sem. Ez a kör hozza létre a feature **belépési felületét** — a
Practice Hubot és a Setup képernyőt — a `practiceEngineV2Enabled` flag mögött,
**pontozó UI nélkül** (a session-képernyő a Kör 13).

A kör után egy fejlesztői buildben a felhasználó eljut a katalógustól a
konfigurált session **indításáig**; a session maga még nem jelenik meg.

## 2. Jelenlegi állapot (mért tények, `main` @ `ce8fbce`)

- **A `lib/features/practice/` alatt nincs `presentation/` könyvtár**, egyetlen
  widget és képernyő sincs. A feature ma: `domain/` (20 modell + 2 service +
  1 repository), `application/` (7 fájl), `data/` (2 + 4 adapter).
  **`public.dart` sincs** (a `songs`, `progress`, `streak`, `chords`,
  `library`, `learn` feature-öknek van — a barrel-minta tehát adott).
- **Routing:** `lib/app/routing/app_route.dart` — `AppRoutes` **17 útvonal-
  konstanssal** és az ötelemű `shellTabs` listával (`live`, `analyze`, `learn`,
  `library`, `settings`). `app_router.dart`: `ShellRoute` az öt tabra + a
  teljes képernyős route-ok. Guard-teszt: `test/tooling/route_literal_guard_test.dart`
  — **navigációs hívásban route-string-literál TILOS**, csak `AppRoutes` konstans.
- **Flag:** `AppConfig.flags.practiceEngineV2Enabled`
  (`lib/app/config/feature_flags.dart:41`) — **non-prod: true, production: false**,
  dart-define override **nincs**. A widget-oldali olvasás mintája mérve:
  `ref.watch(appConfigProvider).flags.labModeAvailable`
  (`settings_screen.dart:204`).
- **Katalógus-providerek (R04):** `practiceCatalogProvider` — a tíz beépített
  gyakorlat `PracticeDefinition`-ként; `practiceCatalogRepositoryProvider`
  felülírható tesztben.
- **i18n:** `lib/l10n/app_en.arb` **375 kulcs**, `app_hu.arb` ugyanannyi.
  Gate: `test/core/l10n_parity_test.dart` — azonos kulcshalmaz **és** üres
  fordítás tilos. **A `practice*` prefixű kulcsok ma teljesen hiányoznak**
  (mérve: `grep '"practice' lib/l10n/app_en.arb` → 0 találat).
- **Layout-őr:** `test/core/screen_size_guard_test.dart` — minden fő képernyőt
  320×568 és 915×412 méreten pumpál; a RenderFlex-túlcsordulás teszthiba.
  **Az új képernyőket ide fel kell venni.**
- **Widget-teszt minta:** `ProviderScope(overrides: [...preferenceOverrides(), ...])`
  + `MaterialApp(localizationsDelegates: AppLocalizations.localizationsDelegates)`
  (lásd `test/features/progress/progress_screen_test.dart`).
- **`PracticeSessionConfig`** (`domain/model/practice_session_config.dart`,
  206 sor) — a Setup által állítható mezők **egyetlen validációs forrása**.
  A UI **nem** definiál saját szabályt.

## 3. Scope

**Benne:** két képernyő (Hub, Setup), a hozzájuk tartozó widgetek, egy setup-
controller az `application/` alatt, a feature barrel (`public.dart`), két új
route flag mögött, ARB-kulcsok mindkét nyelven, widget- és routing-tesztek.

**Kívül (ebben a körben TILOS):**

- **A session-képernyő, a highway, a HUD, bármilyen scoring-megjelenítés** —
  Kör 13/14.
- A Result képernyő, history-lista — Kör 18.
- A Speed Builder **működése** (a Setup csak a **konfigurációját** veszi fel és
  validálja; a policy és az attempt-lánc a Kör 17).
- A `learn`, `songs`, `streak` feature-ök bármilyen módosítása (a Daily
  Challenge adapter **már kész**, R05 — csak hívni kell).
- Business logic widgetben: pontozás, matcher, target-fordítás, óra.
- Új ADR, `docs/sdd/**`, `HANDOFF.md`, `.github/**`, DSP.

## 4. Engedélyezett fájlok

| Útvonal | Új? | Miért |
|---|---|---|
| `lib/features/practice/presentation/screens/practice_hub_screen.dart` | **ÚJ** | Hub |
| `lib/features/practice/presentation/screens/practice_setup_screen.dart` | **ÚJ** | Setup |
| `lib/features/practice/presentation/widgets/practice_mode_card.dart` | **ÚJ** | mód-kártya |
| `lib/features/practice/presentation/practice_route_args.dart` | **ÚJ** | tipizált route-argumentumok + biztonságos feloldás |
| `lib/features/practice/application/practice_setup_controller.dart` | **ÚJ** | a Setup állapota (SDD §8.1 szerinti hely) |
| `lib/features/practice/public.dart` | **ÚJ** | feature-barrel (SDD §8.1) |
| `lib/app/routing/app_route.dart` | — | **CSAK** két új konstans (`practiceHub`, `practiceSetup`) |
| `lib/app/routing/app_router.dart` | — | **CSAK** a két route regisztrációja a flag mögött |
| `lib/l10n/app_en.arb` | — | új `practice*` kulcsok |
| `lib/l10n/app_hu.arb` | — | ugyanazok magyarul (a parity-gate kötelező) |
| `test/features/practice/presentation/practice_hub_screen_test.dart` | **ÚJ** | A1–A3 |
| `test/features/practice/presentation/practice_setup_screen_test.dart` | **ÚJ** | A4–A6 |
| `test/features/practice/presentation/practice_routing_test.dart` | **ÚJ** | A7 (flag + fallback) |
| `test/core/screen_size_guard_test.dart` | — | **CSAK** a két új képernyő felvétele a meglévő mintába |
| `docs/rounds/e02-r12-practice-hub-and-setup.md` | — | **CSAK a §10** (handoff) |

**Tilos zóna:** minden más. Nevezetesen `lib/features/practice/domain/**`,
`lib/features/practice/data/**`, `lib/features/learn/**`, `lib/app/config/**`
(a flag **értéke** nem változik), `lib/app/home_shell.dart` (a Practice **nem**
lesz shell-tab ebben a körben), `docs/adr/**`, `.github/**`.

**Új fájl a listán kívül = scope-sértés** → `stopped`.

## 5. Kötött döntések (ADR 0078 — NEM tárgyalhatók)

1. **A Practice felület flag mögött van.** A két route **csak akkor**
   regisztrálódik, ha `appConfigProvider.flags.practiceEngineV2Enabled` igaz.
   Flag OFF mellett a `/practice*` útvonalra navigálás a router meglévő
   `onException` szabálya szerint a Live-ra esik vissza — **nem** fehér képernyő,
   **nem** kivétel.
2. **A Practice NEM lesz shell-tab ebben a körben.** A `shellTabs` ötelemű
   marad; a Hub teljes képernyős route. (A navigációs hely kérdése a rollout
   döntés része, Kör 19/20.)
3. **Tipizált route-argumentum.** A Setup a definíció **azonosítóját** kapja
   (string path/query paraméter), és a képernyő **oldja fel** a katalógusból.
   Feloldhatatlan azonosító → lokalizált hibaállapot + „vissza a Hubra" út,
   **soha nem** kivétel és **soha nem** üres képernyő.
4. **A UI nem definiál validációs szabályt.** Minden mező-korlát a
   `PracticeSessionConfig.validate()` / `Tempo` / `Meter` kódjaiból jön, és a
   Start gomb tiltása **ugyanazon** a validáción alapul. A UI legfeljebb
   *megjeleníti* a hibakódhoz tartozó lokalizált szöveget.
5. **Minden user-facing szöveg ARB-ból jön**, mindkét nyelven kitöltve. A domain
   és az application réteg **nem** tartalmaz megjelenítendő szöveget (SDD §22.3).
6. **A widget nem tartalmaz business logikát**: nincs benne pontozás, matcher,
   target-fordítás, `DateTime.now()` vagy `Stopwatch`. A Hub „Continue" és
   „Recent" blokkjai ebben a körben **placeholder-határok** (üres állapot), mert
   a history a Kör 18-ban készül el — a placeholder **ne** hazudjon adatot.
7. **Accessibility alapok kötelezőek** már itt: minimum 48×48 dp érintőfelület,
   szemantikus címke minden vezérlőn, a jelentés nem csak színre épül.
8. **A Start gomb a controller `PreparePractice` parancsát adja ki** — a Setup
   **nem** navigál a session-képernyőre (az még nem létezik). A navigációs pont
   a Kör 13-ban kerül be, TODO-komment **nélkül**: a Start ebben a körben a
   validált config előállításáig és a parancs kiadásáig tart.

## 6. Acceptance criteria

### A1 — A Hub a katalógusból renderel

`practiceCatalogRepositoryProvider` felülírva egy ismert, **három** definíciót
adó fake-kel → a Hub pontosan három mód-kártyát mutat, a definíciók
`displayTitle`-jével. Nulla definíció → lokalizált üres állapot (`EmptyState`),
**nem** üres `ListView`.

***Pirosra fogja:*** a beégetett kártyalista.

### A2 — Mód-szűrés

`PracticeMode` szerinti szűrés: az öt módra (strumPattern, chordChange,
chordProgression, rhythmOnly, freePractice) **külön cella** — a szűrő
kiválasztása után csak az adott módú definíciók látszanak, és a szűrő
törlése után újra mind.

**NEM elfogadható gyengítés:** egyetlen mód tesztelése „a többi ugyanaz a kód"
indoklással — a fixture default-ja pont az a pont, ahol a hibás és a helyes
implementáció megkülönböztethetetlen.

### A3 — A Hub nem hazudik adatot

- „Continue" blokk: **nincs** korábbi session → a blokk **nem jelenik meg**
  (nem „0 perc", nem „—").
- „Recent" blokk: ugyanez.
- Daily Challenge belépő: a meglévő `daily_challenge_practice_adapter`
  `AppResult` hibája esetén a belépő **letiltott** állapotban jelenik meg
  lokalizált magyarázattal, nem tűnik el némán.

### A4 — Setup: alapértékek és a domain-validáció egyezése

Mátrix, minden cellához külön `expect`:

| Mező | Cella | Elvárt |
|---|---|---|
| BPM | 29 / 30 / 300 / 301 | tiltva / **engedve** / **engedve** / tiltva (`Tempo` 30–300 zárt) |
| count-in ütem | 0 / 1 / 2 / 4 | mind engedve, a `PracticeSessionConfig` szerint |
| meter | 4/4 · 3/4 · 6/8 | a kijelzés az adott ütemmutatót mutatja |
| loop | ki / be | a `PracticeSessionConfig` mezője követi |

A **határcellák** (30 és 300) a `<=`/`<` különbséget mérik — ezek nem
hagyhatók el.

***Pirosra fogja:*** a UI-ban külön beírt `min: 40, max: 240` típusú
slider-korlát, ami eltér a domain validációtól.

### A5 — Mód-specifikus mezők

- **Free Practice** kiválasztva → a pontozási beállítások (difficulty profil,
  pass-küszöb megjelenítés) **nem láthatók** (SDD: „Free Practice hides scoring
  options").
- **Speed Builder** bekapcsolva → a start/target/step BPM mezők megjelennek, és
  a `target < start` kombináció **tiltja** a Startot lokalizált hibával.
- **Rhythm-only** → az akkord-választó nem látszik.

### A6 — Start csak érvényes configgal

Érvénytelen konfigurációnál a Start gomb **letiltott**, és a hiba lokalizált
szövegként látszik. Érvényesnél a Start pontosan **egy** `PreparePractice`
parancsot ad ki (fake controller hívásnaplója).

### A7 — Routing: flag, fallback, literál-tilalom

| Cella | Elvárt |
|---|---|
| flag ON, `/practice` | a Hub épül fel |
| flag ON, `/practice/setup?id=<ismert>` | a Setup a feloldott definícióval |
| flag ON, `/practice/setup?id=<ismeretlen>` | lokalizált hibaállapot + vissza-út, **nincs** kivétel |
| flag OFF, `/practice` | a router `onException` szerinti fallback (Live), **nincs** kivétel |

Plusz: `test/tooling/route_literal_guard_test.dart` **zöld marad** — minden
navigáció `AppRoutes` konstanson keresztül.

### A8 — i18n parity és accessibility

- `test/core/l10n_parity_test.dart` zöld: minden új kulcs **mindkét** ARB-ben,
  üres fordítás nélkül.
- Mindkét képernyő angolul **és** magyarul felépül (widget-teszt két locale-lal).
- `tester.ensureSemantics()` mellett minden interaktív elem **címkével és
  akcióval EGY** szemantikus node-on (a `chord_tile_a11y_test.dart` mintája).
- 200%-os szövegméret (`textScaler`) mellett **nincs** overflow.
- `test/core/screen_size_guard_test.dart` zöld a két új képernyővel (320×568 és
  915×412).

### A9 — Nincs business logic a widgetben

Guard-jellegű állítás a saját tesztfájlban: a két képernyő forrása **nem
tartalmazza** a `Stopwatch`, `DateTime.now(`, `Timer(`, `matcher`, `scorer`
mintákat, és nem importál `domain/service/`-t.

### A10 — Nulla változás a legacy úton

`git diff --stat origin/main...HEAD` a §4 listáján belül; `lib/features/learn/`
**0 sor**; `lib/app/home_shell.dart` **0 sor**; a `feature_flags.dart`
**0 sor** (a flag értéke nem változik).

## 7. Implementációs sorrend (ez a TERVED)

1. Olvasd el: ADR 0078, `PracticeSessionConfig`, `PracticeDefinition`,
   `practice_catalog_controller.dart`, `app_route.dart`, `app_router.dart`,
   a `progress_screen.dart`-ot mint stílus-horgonyt, és a
   `route_literal_guard_test.dart`-ot.
2. ARB-kulcsok mindkét nyelven (előbb a szövegek, hogy ne maradjon literál).
3. `public.dart` barrel + `practice_route_args.dart`.
4. `practice_setup_controller.dart` (állapot + a domain-validáció becsatolása).
5. Hub képernyő + mód-kártya, üres állapotokkal (A1–A3).
6. Setup képernyő (A4–A6).
7. Route-regisztráció a flag mögött (A7).
8. a11y + layout-őr + i18n (A8), guard-állítás (A9).
9. Záró gate (§9), majd a §10 kitöltése.

## 8. Kockázatok

- **A route-regisztráció közös fájl.** Az `app_router.dart`-ban **csak** a két
  új `GoRoute` és a flag-feltétel jelenhet meg; minden más sor változatlan.
- **ARB-drift.** Kulcs csak az egyik nyelvben = piros parity-gate. A magyar
  szövegek **valódi fordítások** legyenek, nem angol másolatok.
- **A Hub „Continue" csábítása.** A history a Kör 18-é; ha itt bevezetsz egy
  ideiglenes tárolót, az duplikált szerződés lesz → `stopped`.
- **A 6/8 ütemmutató** a `Meter`-ben létezik; a Setup megjelenítése nem
  feltételezheti a 4/4-et.
- **`AsyncValue.value`** (nullable), **NEM** `.valueOrNull` (Riverpod 3.3.2).

## 9. Záró gate — szó szerint ez az egyetlen hívás

```
tools/round-gate.sh test/features/practice/ test/core/l10n_parity_test.dart test/core/screen_size_guard_test.dart test/tooling/route_literal_guard_test.dart test/app/routing/
```

Csővezeték nélkül, a teljes kimenetet a §10-be. A teljes suite + property gate +
APK a CI-ban fut (ADR 0053) — `gh`-t NE hívj.

## 10. Implementation handoff — az IMPLEMENTER tölti ki

*(Fájlonkénti összefoglaló · a záró gate TÉNYLEGES, teljes kimenete · az A1–A10
pontok teljesülése bizonyítékkal · eltérések és okuk · follow-upok.)*

## 11. Review — Claude tölti ki

Link: `docs/reviews/e02-r12-review.md`

Kiemelt figyelem: a **flag OFF** út tényleges kipróbálása (nem csak a teszt
állítása), az A4 határcellái (30/300 BPM), és hogy a Setup **tényleg** a domain
validációt hívja-e, nem egy másolt szabálykészletet.
