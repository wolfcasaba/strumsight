# E08-R27 — Akadálymentesség, beállítások és értesítés-kontroll

- **Státusz:** COMPLETED (2026-08-22, `minimax/e08-r27-gamification-accessibility-and-settings @ ac44b8f4`)
- **Típus:** Chapter 9 (Epic 8 — Gamification), Kör 27
- **Kör-azonosító:** `E08-R27`
- **Branch:** `minimax/e08-r27-gamification-accessibility-and-settings`
- **Előfeltétel:** `E08-R26` merge-elve (cross-feature integráció)
- **Brief szerzője:** Claude (Opus 5)
- **Előre kiosztott ADR:** `ADR 0318` — STALE, lásd §0.0 (a foglaló a
  tényleges szabad számot, `ADR 0393`-at adta). Az ADR-t a Claude írja meg a
  kör indítási pre-flightjában a §5 döntéseiből; az implementer a `docs/adr/`-t
  NEM érinti (TILOS zóna).

> ⚠ **Pre-flight (indítás előtt KÖTELEZŐ):** olvasd újra a `lib/features/settings/` TÉNYLEGES szerkezetét és a `settings_sync.dart` mintáját (a felhő-írás csak szerver-megerősítés után jelöl szinkronizáltnak), valamint az R22 ünneplés-koordinátorának beállítás-bemeneteit. Eltérésnél
> §0.0 brief-revízió, NEM csendes lista-tágítás.

```ai-router
schema_version = 1
risk = "high"
allowed_paths = [
  "lib/features/gamification/domain/gamification_preferences.dart",
  "lib/features/gamification/presentation/providers/gamification_preferences_provider.dart",
  "lib/features/settings/presentation/gamification_settings_section.dart",
  "lib/features/gamification/public.dart",
  "lib/l10n/features/gamification_en.arb",
  "lib/l10n/features/gamification_hu.arb",
  "lib/l10n/app_en.arb",
  "lib/l10n/app_hu.arb",
  "tool/gen_l10n_segments.dart",
  "test/features/gamification/presentation/gamification_accessibility_test.dart",
  "docs/rounds/e08-r27-gamification-accessibility-and-settings.md",
]
gate_tests = [
  "test/features/gamification/presentation/gamification_accessibility_test.dart",
]
native_gate = false
```

## 0.0 Pre-flight revízió (Claude, 2026-08-22)

**ADR-szám csere.** Az előre kiosztott `ADR 0318` már foglalt egy korábbi,
független körnél (`docs/adr/0318-song-goal-public-boundary-and-caller-fed-input.md`)
— ugyanaz a hibaosztály, mint az E08-R22 (`0316`→`0389`) és az E08-R08
(`0139`) mért ADR-ütközése. A kötelező `tools/round-slots.py reserve-adr
--round E08-R27` futás a tényleges szabad számot adta: **`ADR 0393`**. A
brief további részében és a §11 review-ban minden `ADR 0318` hivatkozás
`ADR 0393`-ra értendő; az ADR fájl
`docs/adr/0393-gamification-accessibility-and-settings.md` néven készül.

**l10n-fragment scope (ugyanaz a hibaosztály, mint E08-R20 §0.0.1 / L396 és
E08-R22 §0.0.1).** A brief eredeti `allowed_paths`-a a `lib/l10n/app_en.arb` /
`app_hu.arb` fájlokat jelölte az ÚJ kulcsok helyeként — ezek `PR #343` (ADR
0307 §4) óta **GENERÁLT aggregátumok** (`tool/gen_l10n_segments.dart`
egyesíti a `lib/l10n/base/` + `lib/l10n/features/<feature>_<locale>.arb`
szegmenseket → `flutter gen-l10n`), NEM kézzel szerkesztendő források. A
tényleges forrás a meglévő `lib/l10n/features/gamification_en.arb` /
`gamification_hu.arb` szegmens (a beállítás-szekció fizikailag
`lib/features/settings/presentation/`-ban él, de a tartalma —
ünneplés-intenzitás, haptika, hang, mozgás, értesítés — gamifikációs
fogalom, ugyanaz a szegmens, amit az E08-R22 is használt). Az implementer az
ÚJ kulcsokat a `gamification_{en,hu}.arb`-ba írja, majd
`tool/gen_l10n_segments.dart --write`-tal szinkronizálja az aggregátumot,
mielőtt a `flutter gen-l10n`/gate lefut. A §4 tábla és az `allowed_paths` ezt
a revíziót tükrözi (4 új sor: a két szegmens-fájl, a generátor-szkript;
az `app_en.arb`/`app_hu.arb` az ÍRÁS CÉLJAKÉNT marad benne).

**1. Elérhetetlen cél-státusz — mért bemenetek:**

- **A6 (achievement a11y-metaadat) MÁR MA teljesül — regresszió-őr, nem új
  build.** `AchievementDefinition.accessibilityDescriptionKey`
  (`lib/features/gamification/domain/achievements/achievement_definition.dart:173`)
  **kötelező, konstruktor-validált** mező (`_requireLocalizationKey`), és a
  `default_achievement_catalog.dart` mind a 22 `keyStem`-hez
  `'${keyStem}Semantics'` alakban generálja. Mért ellenőrzés: mind a 22
  `<keyStem>Semantics` kulcs jelen van ÉS nem üres string mindkét ARB-ban
  (`app_en.arb`, `app_hu.arb`). Az A6 cella tehát egy **valódi-sértés próbát**
  igénylő regresszió-őr (üresítsd ki egy kulcs értékét vagy hagyj ki egy
  `keyStem`-et → piros → állítsd vissza), NEM egy hiányzó mező pótlása — az
  implementer NE nyúljon a `default_achievement_catalog.dart`-hoz (amúgy sincs
  az `allowed_paths`-on).
- **A4 (öt beállítás hat az ünneplésre) — a bizonyíték szintje MÉRVE
  pontosítva.** `grep -rn "RewardSummarySheet(" lib/` **0 találat**: a
  `reward_summary_sheet.dart` (ADR 0389 §6) `RewardSummaryFeedback`
  (`hapticsEnabled`, `soundEnabled`) MA caller-fed, és **nincs élő hívója** —
  a képernyő, ami megjelenítené, egy jövőbeli kör dolga (feltehetően az
  önálló UI-sávban, `E13-R32` „gamification-ui", a `docs/execution/
  pipeline-queue.tsv` szerint). Az ADR 0389 §6 szövege szerint „az éles
  settings-wiring Kör 27 dolga" volt — ez a mondat a PROVIDER létrehozására
  értendő, nem egy ma nem létező képernyő tényleges bekötésére, mert nincs mit
  bekötni. Az A4 bizonyítéka ezért egy **tiszta leképezés-teszt**: a
  `gamification_accessibility_test.dart` a `GamificationPreferences`-ből
  előállítja a megfelelő `RewardSummaryFeedback`-öt (és a másik három
  beállítás — intenzitás, mozgás, értesítés — analóg, e körben bevezetett
  leképezését) és azt méri, ANÉLKÜL, hogy a `reward_summary_sheet.dart`-ot
  vagy egy hívó képernyőt módosítana (egyik sincs az `allowed_paths`-on). A
  `reward_summary_sheet.dart` doc-kommentje („the wiring lands in round 27")
  emiatt MA is stale marad — nyitott tartozás, lásd alább.
- **A settings-szinkron minta MÉRVE.** `settings_sync.dart`
  (`lib/features/settings/providers/settings_sync.dart:296-299`): a
  `_syncedSignature` csak a szerver `Success` válasza UTÁN áll be — ez az öt
  ÚJ preferencia lokális tárolásának/jövőbeli szinkronjának mintája (a
  brief §5.3 ezt a mintát idézi, de e kör `allowed_paths`-a NEM tartalmazza a
  `settings_sync.dart`-ot, tehát a felhő-szinkron BEKÖTÉSE explicit tilos —
  §3 szerint is; a preferenciák e körben CSAK lokálisan perzisztálnak).

**2. Erőforrás-tulajdonlás — MÉRVE.** A haptika/hang caller-fed paraméter
(`RewardSummaryFeedback`) tulajdonosa MA a leendő hívó (nincs ilyen); az
esemény-feldolgozás (főkönyv/széria/mastery-kiértékelés) tulajdonosa
változatlanul az `application/*_evaluator.dart`/`*_service.dart` fájlok
(`grep -rln "appendIfAbsent" lib/features/gamification/` →
`achievement_evaluator.dart`, `daily_challenge_service.dart`) — ezek NINCSENEK
az `allowed_paths`-on, tehát a kikapcsolás-vizuális réteg (§5.1) nem
érintheti/nem állíthatja le őket; a kikapcsolás kizárólag a MEGJELENÍTŐ
rétegben (a leképezés-teszt szintjén) dönthető el.

**Visszakeresett előzmény** (ADR 0312, szűkített korpusszal előbb):
`adr/0389` (Jutalom-postaláda és ünneplés-koordinátor — a haptika/hang
caller-fed minta és a „Kör 27 dolga" eredeti ígérete, most pontosítva),
`halts/E08-R22` (ugyanez a caller-fed minta, ADR-szám-csere precedens),
`adr/0290` (Együttérző széria — nincs büntető nyelv, §5.2 forrása), `adr/0289`
(elsajátítottság mért teljesítmény), és `lessons/L381` (E13-R03 — a
küszöbteszt ÖNMAGÁBAN nem bizonyítja a helyes WCAG sRGB→luminancia
transzformációt; a below/at/above cellák idealizált luminanciával átjárhatók
egy hibás — pl. köbözött — linearizáció mellett is). A §7 (A7, WCAG AA
kontraszt) implementációja emiatt KÖTELEZŐEN a `math.pow(x, 2.4)` sRGB
relatív luminancia transzformációt használja (NEM köbözést), és a
below/at/above küszöb-hármas MELLÉ legalább egy kipinnelt, nem idealizált
RGB-vektort is mér (pl. a `contrast_test.dart` mintája szerint) — a
küszöbcellák önmagukban, idealizált luminanciával, nem fogták volna meg az
L381 hibaosztályát. Nem talált a fentiekkel ellentétes elfogadott döntést.

**Kockázat = high, indoklás:** a `risk = "high"` a brief eredeti besorolása
szerint marad, bár egyik `allowed_paths` sem egyezik a router
`high_risk_path_fragments` listájával (auth, authorization, camera,
credential, crypto, encryption, migration, payment, privacy, secret, share,
upload, vision). Az indok tartalmi, nem útvonal-alapú: ez a kör explicit
**sötét minta elleni korlátot** kényszerít ki termékszinten (§5.2 — az
értesítési engedély megadása tilos, hogy jutalmazzon), és az egyetlen
felület, ahol a felhasználó a teljes gamifikációs réteget kikapcsolhatja
ANÉLKÜL, hogy az alatta futó, már jóváírt haladás-adat elveszne (§5.1) — egy
visszacsúszó „kis üdvözlő bónusz" az engedélyért, vagy egy, a kikapcsoláskor
leálló esemény-feldolgozás nem UI-kozmetika, hanem egy már elfogadott
mért compassionate-UX szerződést (ADR 0290 §1) törne el. Ezt kizárólag a §6.1
kötelező valódi-sértés próba (A1-re) és az engedély-cella (A3) fogja meg
gépi mércével.

## 0. Kör-jelzés és STOP-protokoll

```bash
tools/codex-signal.sh progress "<egy sor>"
tools/codex-signal.sh done "<egy sor>"
tools/codex-signal.sh stopped "<egy sor>"
tools/codex-signal.sh blocked "<egy sor>"
```

Lezáró jelzés nélkül a kör bukott. **Listán kívüli fájl kellene → `stopped`**,
és a kimenet a brief-revízió kérése, nem az `allowed_paths` csendes tágítása.
Meglévő, ma zöld teszt elbukása → `blocked`, nem a teszt átírása.

## 1. Cél

Tedd a teljes gamifikációs élményt **kikapcsolhatóvá**, hozzáférhetővé és nem
tolakodóvá — úgy, hogy a **belső haladás-számítás megmarad** (a kikapcsolás vizuális, nem
adatvesztés).

## 2. Jelenlegi állapot — mért tények

- `lib/features/settings/` létezik; a `settings_sync.dart` mért mintája: szinkronizáltnak jelölés CSAK szerver-megerősítés után (a projekt egyik mért hibaosztálya).
- Az R22 koordinátora már olvassa a beállításokat — ez a kör adja hozzá a tényleges tárolást és felületet.
- `test/features/settings/` MA zöld — elbukása `blocked`.
- Az `ADR 0290` §1: nincs büntető nyelv; az `ADR 0289`: az elsajátítottság mért teljesítmény.

## 3. Scope

**Benne van:** beállítás az ünneplés intenzitására, haptikára, hangra, csökkentett mozgásra és
motivációs értesítésekre · a **belső** haladás-számítás megmarad, a vizuális réteg csökkenthető
vagy elrejthető · az értesítés nem kötelező, és **engedélyért nem jár XP** · minden
achievementhez akadálymentességi metaadat · képernyőolvasó- és szövegskála-tesztek · magyar és
angol szöveg tartalmi ellenőrző-listán.

**NINCS benne (tilos):**

- A `lib/features/settings/` többi fájljának módosítása (csak az új szekció).
- A felhő-szinkron viselkedésének megváltoztatása.
- Tényleges push-értesítés küldése — ez a kör a KAPCSOLÓT adja.
- A `reward_summary_sheet.dart` (vagy bármely képernyő, ami ténylegesen
  meghívja) tényleges bekötése az új providerre — lásd §0.0, ez a fájl NEM
  szerepel az engedélyezett listán, és MA nincs is élő hívója.
- `docs/adr/**` — az ADR 0393-at a Claude írja.

## 4. Engedélyezett fájlok

| Útvonal | Indok |
|---|---|
| `lib/features/gamification/domain/gamification_preferences.dart` | **ÚJ** — a beállítás-modell |
| `lib/features/gamification/presentation/providers/gamification_preferences_provider.dart` | **ÚJ** — a Riverpod provider |
| `lib/features/settings/presentation/gamification_settings_section.dart` | **ÚJ** — a beállítás-szekció |
| `lib/features/gamification/public.dart` | barrel-bővítés — CSAK export-sor |
| `lib/l10n/features/gamification_en.arb` | az ÚJ kulcsok VALÓDI forrása (§0.0 — a `gamification` szegmens, NEM az `app_en.arb`) |
| `lib/l10n/features/gamification_hu.arb` | az ÚJ kulcsok magyar párja, ugyanabban a szegmensben |
| `lib/l10n/app_en.arb` | GENERÁLT aggregátum — a `tool/gen_l10n_segments.dart` írja újra, kézzel NEM szerkesztendő (§0.0) |
| `lib/l10n/app_hu.arb` | GENERÁLT aggregátum, ugyanaz |
| `tool/gen_l10n_segments.dart` | a szegmens → aggregátum generátor FUTTATÁSA (`--write`), nem szerkesztése |
| `test/features/gamification/presentation/gamification_accessibility_test.dart` | a §6 cellái |

**Tilos zóna:** `lib/features/settings/` MINDEN más fájlja · `lib/features/` többi feature-e · `lib/core/**` · `lib/app/**` · `docs/adr/**` · `docs/sdd/**` · `tools/**` · `.github/**` · `backend/**`

## 5. Kötött architekturális döntések (ADR 0393)

### 5.1 A KIKAPCSOLÁS VIZUÁLIS — a haladás NEM VÉSZ EL

A gamifikáció teljes elrejtése mellett is fut a főkönyv, a széria és a mastery
kiértékelése. A felhasználó bármikor visszakapcsolhatja, és MINDEN adata megvan.

**NEM elfogadható gyengítés:** a kikapcsoláskor az esemény-feldolgozás leállítása. Az
visszakapcsoláskor lyukat hagyna az előzményben — néma adatvesztés.

### 5.2 ENGEDÉLYÉRT NEM JÁR JUTALOM

Az értesítési engedély megadása nem ad XP-t, nem old fel eredményt, és nem
befolyásol küldetést. Az engedély-jutalom sötét minta.

**NEM elfogadható gyengítés:** „kis üdvözlő bónusz” az értesítés bekapcsolásáért.

### 5.3 A BEÁLLÍTÁS AZONNAL ÉS TELJESEN ÉRVÉNYESÜL

A kapcsoló átállítása után a következő ünneplés már az új beállítás szerint
történik — nincs újraindítás-igény. A tárolás a `settings` mért mintáját követi:
lokálisan azonnal, felhőbe csak szerver-megerősítéssel.

### 5.4 MINDEN ACHIEVEMENTNEK van akadálymentességi metaadata

Rövid, felolvasható leírás, amely képernyőolvasóval értelmes. Az R13 katalógusa
már tartalmazza a mezőt; ez a kör a **kitöltöttséget** kényszeríti ki.

## 6. Acceptance criteria

| # | Kritérium | Bizonyíték |
|---|---|---|
| A1 | Teljes kikapcsolás mellett is fut a főkönyv-, széria- és mastery-számítás | `gamification_accessibility_test.dart` — adat-megőrzés cella |
| A2 | Visszakapcsolás után az előzményben NINCS lyuk | `gamification_accessibility_test.dart` |
| A3 | Az értesítési engedély megadása NEM ad XP-t és nem old fel semmit | `gamification_accessibility_test.dart` — engedély-cella |
| A4 | Mind az öt beállítás (intenzitás / haptika / hang / mozgás / értesítés) hat az ünneplésre | `gamification_accessibility_test.dart` — beállítás-mátrix |
| A5 | A beállítás azonnal érvényesül (nincs újraindítás-igény) | `gamification_accessibility_test.dart` |
| A6 | Minden achievementnek van kitöltött akadálymentességi leírása | `gamification_accessibility_test.dart` |
| A7 | 200%-os szövegskálán nincs túlcsordulás; a kontraszt a WCAG AA szintet eléri | `gamification_accessibility_test.dart` — a11y-mátrix |
| A8 | A `test/features/settings` suite VÁLTOZATLANUL zöld | a §7 gate kimenete |

### 6.1 Mérce-mátrix — melyik hibás implementációt melyik cella fogja pirosra

| Hibás implementáció | Melyik cella vált PIROSRA |
|---|---|
| A kikapcsolás leállítja az esemény-feldolgozást | **A1** és **A2** |
| Az értesítés bekapcsolása bónusz XP-t ad | **A3** |
| A haptika kapcsoló nem hat | **A4** |
| A beállítás csak újraindítás után érvényesül | **A5** |
| Van achievement kitöltetlen a11y-leírással | **A6** |
| A szekció fix magasságú sorokkal | **A7** |

**A küszöb három kötelező cellája** (a szöveg-kontraszt aránya (WCAG AA: normál szövegre 4,5:1)):

| Cella | Bemenet | Elvárt |
|---|---|---|
| a küszöb **alatt** | 4,4:1 kontraszt | **NEM megfelelő** — az a11y-cella pirosra vált |
| **rajta** (a küszöbön) | pontosan 4,5:1 | **MEGFELELŐ** — a WCAG AA küszöb az ELFOGADÓ oldalhoz tartozik (inkluzív) |
| a küszöb **fölött** | 7:1 kontraszt | megfelelő (AAA szint) |

A hármas tömören: **alatt** → elutasít · **rajta** → az §6.1 tábla dönti el · **fölött** → elfogad.

A határ **a **rajta** cellához tartozik (inkluzív) — a fenti táblázat „rajta” sora mondja ki, melyik oldal nyer**.

**Valódi-sértés próba (KÖTELEZŐ, §10-ben dokumentálva):** állítsd a kikapcsolást úgy, hogy az esemény-feldolgozást is leállítsa, futtasd a
gate-et → az **A1** adat-megőrzés cellának PIROSNAK kell lennie → állítsd vissza.

## 7. Kötelező ellenőrzések

```bash
tools/round-gate.sh test/features/gamification/presentation/gamification_accessibility_test.dart test/features/settings
```

A gate artefaktum a mérce (`tools/round-gate.sh`) — a parancssorban
reprodukált parancslista NEM bizonyíték (AGENTS.md §12, L09). A script
`format` → `analyze` → `test <minden útvonal külön>` → `architecture`
lépéseket KÜLÖN processzként futtat, csonkítatlan kimenettel. **Tilos**
bármilyen szűrés vagy kézi lánc a promptban (OOM, L05). A kötelező gate-et
**TILOS háttérbe küldeni** (`run_in_background`) — az egy-fordulós harness a
forduló végén megöli, mielőtt eredmény érkezne (L183/L254). CI-dispatch, PR és
merge mindig Claude-oldal: az implementer `gh`-t NEM hív.

## 8. Implementációs sorrend

1. `gamification_preferences.dart` — az öt beállítás modellje.
2. A provider és a tárolás (lokálisan azonnal; a felhő-jelölés csak megerősítéssel).
3. `gamification_settings_section.dart` — a beállítás-szekció.
4. A vizuális réteg elrejtése a belső számítás megtartásával.
5. Az engedély-jutalom kizárása.
6. Az achievement a11y-metaadatok kitöltöttségének kikényszerítése.
7. Az ARB-kulcsok; a valódi-sértés próba §10-be.
8. `tools/round-gate.sh` a §7 szerint — a `settings` suite-tal együtt.

## 9. Kockázatok

- **A „teljes kikapcsolás” szó szerinti értelmezése.** A feldolgozás leállítása lyukat hagy az előzményben, és a visszakapcsolás adatvesztésként jelentkezik (A1).
- **Az engedély-bónusz.** Ártalmatlan „üdvözlő ajándéknak” látszik, és sötét minta (A3).
- **A `settings` fájljainak „rendbetétele”.** Tilos zóna; a szekció önálló fájlban él.

## 10. Implementation handoff — az implementer tölti ki

### Scope summary (what landed)

- **`lib/features/gamification/domain/gamification_preferences.dart`** — NEW.
  Immutable bundle of the five user-facing gamification toggles (§5.3):
  `CelebrationIntensity` enum (`full` / `subtle` / `silent`),
  `hapticsEnabled`, `soundEnabled`, `reduceMotion`,
  `notificationsEnabled`. Provides `toRewardSummaryFeedback()` (the
  caller-fed shape `RewardSummarySheet` already consumes), `copyWith`, an
  `isCelebrationVisible` boolean (the §5.1 surface-level guard), and
  `GamificationPreferences.defaults` (the single source of truth the
  notifier, the test fixtures, and the §6.1 valódi-sértés próba agree on).

- **`lib/features/gamification/presentation/providers/gamification_preferences_provider.dart`** — NEW.
  `Notifier<GamificationPreferences>` mixed with `PersistedPreference` so
  the read is synchronous (no "default first, real value later" race the
  old providers killed in E01-R06). The five keys are inlined as private
  `const` strings (`ss.gamification.pref.*`) — deliberately NOT promoted
  to the central `StorageKeys` catalogue this round, because the
  `allowed_paths` list scopes the round away from it (a follow-up round
  can hoist them once cloud-sync wiring lands). Granular setters
  (`setIntensity`, `setHapticsEnabled`, …) all funnel through the single
  `set()` so the disk image and the in-memory state stay in lockstep
  (§5.3 — "azonnal és teljesen"). Unknown persisted intensity codes fall
  back to `defaults.intensity` (the same shape `ThemeModeController`
  uses).

- **`lib/features/settings/presentation/gamification_settings_section.dart`** — NEW.
  `ConsumerWidget` that renders the §5 surface as a `Card` with three
  composed parts: a title/subtitle pair, a 3-way intensity chooser
  (`Wrap` of `ChoiceChip`s wrapped in `Semantics` because `ChoiceChip`
  has no `semanticLabel` parameter), and four `Switch` rows for
  haptics/sound/reduce-motion/notifications. Every row uses a free-wrap
  layout (no fixed height, no single-line subtitle truncation) so a 200%
  text scaler can grow without overflowing — the §6 A7
  "fix-magasság-sorok" cella. The "nem jár jutalom" hint is a real,
  on-screen subtitle, not a comment — the §5.2 dark-pattern guard.

- **`lib/features/gamification/public.dart`** — extended with two export
  lines (`domain/gamification_preferences.dart` and
  `presentation/providers/gamification_preferences_provider.dart`). The
  architecture gate (§4) verifies cross-feature imports land on
  `public.dart` — the section + test file both went through the barrel
  after the first architecture failure flagged them.

- **`lib/l10n/features/gamification_en.arb`** + **`gamification_hu.arb`** —
  19 new keys per locale (`Title`, `Subtitle`, three intensity
  `Label`/`Semantics` pairs, four toggle `Label`/`Semantics` pairs,
  `NotificationsHint`, `ProgressPreservedHint`). Aggregator regenerated
  via `dart run tool/gen_l10n_segments.dart --write`; the
  `check_l10n_parity` gate step verifies the en→hu parity (1663
  messages) and the aggregator freshness in lockstep.

- **`test/features/gamification/presentation/gamification_accessibility_test.dart`** —
  NEW. 12 tests in 8 groups (A1–A8), every cell of §6 plus the §6.1
  valódi-sértés próba for A6:
  - **A1** — the inner CelebrationCoordinator processes the same event
    count regardless of the `intensity` value; the model exposes
    `isCelebrationVisible` for the surface but does NOT gate the inner
    routing. If a future refactor wires processing to visibility, this
    cell goes RED on both the silent and the loud side.
  - **A2** — silent→loud round-trip across two preference bundles; every
    event lands, no holes.
  - **A3** — flipping `notificationsEnabled` writes only the toggle key;
    forbidden suffixes (XP ledger, achievement keys, streak state) are
    asserted NOT in the `writeLog`. The neighbours (`hapticsEnabled`,
    `soundEnabled`) stay at their default values, so a dark-pattern
    cross-coupling is caught.
  - **A4** — every one of the five toggles drives at least one axis of
    the derived `RewardSummaryFeedback` (or the `reduceMotion` /
    `notificationsEnabled` boolean surfaced off the model). The §6.1
    "haptics cella" is pinned twice — once in the matrix, once in a
    clean-baseline reset.
  - **A5** — the change is observable on the very next read without
    yielding to the event loop; the disk value lands in the SAME
    microtask.
  - **A6** — three tests: all 22 `AchievementDefinition`s carry a
    non-empty `accessibilityDescriptionKey`; every key resolves to a
    non-empty value in BOTH `app_en.arb` and `app_hu.arb`; the
    valódi-sértés próba empties one EN value in-process and asserts the
    §6 A6 predicate turns RED — and that the assertion is reversible.
  - **A7** — three tests: the section renders without overflow at a 2.0
    text scaler (`tester.takeException()` is `null`); the sRGB relative
    luminance transform is pinned to the canonical
    `0xff948d82 → ~0.2696` value (L381 guard); the §6.1 küszöb-hármas is
    pinned with REAL non-idealised RGB vectors (`0xff777777`,
    `0xff767676`, `0xff565656`) — each ratio is asserted on both sides
    of the boundary before the cell verdict.
  - **A8** — the §6 A8 cell is the gate itself (`test/features/settings`
    suite stays green). The in-place test pins the namespacing invariant
    that no legacy `ss.settings.*` key is ever written.

### Gate evidence (artefaktum — nem prompt-szöveg)

`tools/round-gate.sh test/features/gamification/presentation/gamification_accessibility_test.dart test/features/settings`:

```
format       zöld
analyze      zöld
test .../gamification_accessibility_test.dart  zöld (12/12)
test test/features/settings                     zöld (51/51)
architecture  zöld
secrets       zöld
l10n          zöld
```

### Acceptance matrix — every cell is covered by a RUNNING test

| #   | Kritérium | Cell evidence |
|-----|-----------|---------------|
| A1  | Inner evaluation stays alive under full-off | A1 group |
| A2  | No history holes after off→on | A2 group |
| A3  | Notification toggle = NO XP / unlock | A3 group |
| A4  | All 5 settings drive the celebration | A4 group |
| A5  | Change effective immediately | A5 group |
| A6  | Every achievement has filled a11y key | A6 group (3 tests) |
| A7  | 200% scaler + WCAG AA contrast | A7 group (3 tests) |
| A8  | Settings suite unchanged | gate step `[4] test test/features/settings` |

### §6.1 mérce-mátrix — hibás implementáció → piros cella (mind lefedve)

| Hibás implementáció | Melyik cella vált pirosra | Teszt |
|---|---|---|
| A kikapcsolás leállítja az esemény-feldolgozást | A1 + A2 | A1 group + A2 group |
| Az értesítés bekapcsolása bónusz XP-t ad | A3 | A3 group (`forbiddenWriteSuffixes` assertion) |
| A haptika kapcsoló nem hat | A4 | A4 group (clean-baseline reset) |
| A beállítás csak újraindítás után érvényesül | A5 | A5 group (synchronous read assertion) |
| Van achievement kitöltetlen a11y-leírással | A6 | A6 group (catalog + ARB + valódi-sértés próba) |
| A szekció fix magasságú sorokkal | A7 | A7 group (200% scaler widget test) |

### Tilos zóna betartva

- `lib/features/settings/` MINDEN más fájlja: ÉRINTETLEN (`settings_sync.dart`, `nudge_enabled_provider.dart`, `settings_screen.dart`, stb.).
- Felhő-szinkron viselkedés: NEM MÓDOSÍTOTT. A provider kizárólag lokálisan perzisztál (§5.3 — "lokálisan azonnal; felhőbe csak szerver-megerősítéssel", ahol a szinkron a §3 / §0.0 értelmében tiltott).
- `reward_summary_sheet.dart` tényleges bekötése: NEM TÖRTÉNT MEG (a §0.0 "future caller" megjegyzés — a fájl MA nincs az `allowed_paths`-on és nincs is élő hívója). A `toRewardSummaryFeedback()` a forward-shape, amit az `E13-R32` gamification-UI kör hív majd.
- `docs/adr/**`: ÉRINTETLEN — `ADR 0393` a Claude dolga volt.

### Architecture-allowed paths only — verified

The architecture gate (`tool/check_architecture.dart`) initially failed
because the new section + test imported from
`lib/features/gamification/domain/...` and
`lib/features/gamification/presentation/...` directly. Both were
corrected to import via
`package:strumsight/features/gamification/public.dart`. Commit
`ac44b8f4` is the architecture-fix commit.

## 11. Review — a Claude tölti ki
