# E15-R11 — Vision, onboarding és a maradék közösségi képernyő

- **Státusz:** READY (pre-flight brief-revízió §0.0, 2026-09-03, `main @ aead0d49`; előre megírva 2026-08-28, `main @ 4cb32eb0`)
- **Típus:** Chapter 15 (UI-aktiválás és -befejezés), Kör 11
- **Kör-azonosító:** `E15-R11`
- **Branch:** `<motor>/e15-r11-vision-onboarding-community-migration`
- **Előfeltétel:** `E15-R03` merge-elve (a visszavonási terv dönti el, mit KELL migrálni)
- **Brief szerzője:** Claude (Opus 5)
- **Előre kiosztott ADR:** nincs — migrációs kör, kötött ÚJ architekturális döntés nélkül (a hivatkozott szerződéseket korábbi ADR-ek rögzítik).

**Visszakeresett előzmény:** `node tools/knowledge-rag.mjs --corpus lessons,halts,adr --top 5 "vision setup session calibration onboarding UI"` → **[ADR 0181](../adr/0181-vision-manual-calibration-fallback.md)** (kézi kalibrációs tartalék) — a kalibrációs folyamat lépései és tartalék-útja nem változhat.

> ⚠ **Pre-flight (indítás előtt KÖTELEZŐ):** olvasd be a `docs/ui/retirement-plan.md` (E15-R03) sorait erre a batch-re, és mérd újra, mely képernyők legacyk MÉG:
> ```bash
> for f in lib/features/vision/presentation/screens/vision_setup_screen.dart lib/features/vision/presentation/screens/vision_session_screen.dart lib/features/vision/presentation/screens/guitar_calibration_screen.dart lib/features/onboarding/screens/onboarding_screen.dart lib/features/community/presentation/screens/followers_screen.dart; do grep -q design_system "$f" && echo "MIGRATED $f" || echo "legacy $f"; done
> ```
> A megíráskor mind a **5** felsorolt képernyő legacy volt. Ami időközben migrálódott, azt a §3 scope-ból ki kell venni.

## 0.0 Pre-flight brief-revízió (orchestrátor, 2026-09-03, `main @ aead0d49`)

A pre-flight a brief MINDEN hivatkozott komponensnevét és minden érintett
kipinnelt harnesst kimért a kódból. A `brief-lint --level strict` (a PR #543 /
S14 utáni tooling) **0 leletet** adott — az alábbi hét lelet a lint hatókörén
KÍVÜL esik, ezért kézi mérés fogta meg őket. **Ez a szakasz ERŐSEBB a brief
többi részénél**: ahol eltér, ez érvényes.

### R1 (BASE) — a §3/§5.2 három komponense NEM LÉTEZIK

MÉRVE (`grep -rl "class Ss…" lib/core/design_system/`):

| Brief-név | Mérés | Amit HELYETTE használsz |
|---|---|---|
| `SsListTile` | **ABSENT** | `SsContentCard` / `SsEventListRow` (lista-sor), `SsSwitchRow` (kapcsolós sor) |
| `SsErrorState` | **ABSENT** | **`SsFailureState`** (+ `SsFailurePresentation` / `SsFailureAction`) |
| `SsMetricTile` | **ABSENT** | `SsMetricCard` (skeletonja: `SsMetricCardSkeleton`) |

`lib/core/design_system/**` **tilos zóna** (§4), tehát hiányzó komponenst
létrehozni NEM szabad. A §5.2 szerződése változatlan tartalommal, MÉRT nevekkel:
üres → `SsEmptyState`, hiba → **`SsFailureState`**, betöltés → `SsSkeleton`
(vagy `SsAsyncState`). A vision-út engedély-állapotára létezik dedikált
komponens: **`SsPermissionState`** — ahol a képernyő ma engedély-elutasítást
rajzol, azt használd.

A ténylegesen létező felület (a `public.dart` barrel mögött) 53 `Ss*` osztály;
ha egy állapothoz nem találsz komponenst, az **STOP** (`stopped` jelzés), nem
saját komponens.

### R2 (BASE, L593) — a kipinnelt harnessek téma NÉLKÜL pumpolnak

MÉRVE — csupasz `MaterialApp`, `theme:` nélkül:
`vision_setup_screen_test.dart:23`, `guitar_calibration_screen_test.dart:80`,
`vision_one_cue_test.dart:36`, `vision_degraded_test.dart:29`,
`block_mute_test.dart:37`, `onboarding_test.dart:52` és `:108`.

A migrált képernyő `SsCard`-ja `ss_surface.dart:42` → `ss_elevation.dart:14-15`
úton **két `!`-es** `theme.extension<SsColorScheme>()!` /
`theme.extension<SsThemeBehavior>()!` olvasást végez → téma nélkül
**null-check crash**. Ez pontosan az [L593](../LESSONS.md#l593) (E15-R09
BLOCKER-1) hibaosztálya.

**Kötelező:** minden érintett harness a VALÓDI futásidejű témát adja
(`SsLightTheme.data()` / `SsDarkTheme.data()`, [ADR 0466](../adr/0466-app-runtime-theme-is-the-design-system-theme.md)),
`theme:`-ként a `MaterialApp`-ra. Ez a harness **valósághűbbé tétele**, nem
gyengítés: cella törlése, `skip`-je vagy állítás-lazítása továbbra is TILOS
(§0.0 alap-szabály, A4).

### R3 (L593) — egy kipinnelt harness kimaradt a kapuból

`test/app/offline_network_guard_test.dart:293` **`VisionSessionScreen`**-t
állít (`find.byType`), de a brief sem az `allowed_paths`-on, sem a
`gate_tests`-ben nem sorolta fel → a kör saját kapuja nem mérné.

Felvéve a **`gate_tests`-be, MÉRÉS-ONLY** (az `allowed_paths`-ra NEM): a fájl
`:170`-en a valódi `StrumSightApp`-ot pumpolja, tehát az ADR 0466 óta a
design-rendszer témáját ÖRÖKLI — R2-okból nem bukhat el. Ha mégis pirosra vált,
a **képernyőt** kell javítani, nem a tesztet; ha a teszt módosítása lenne
szükséges, az **STOP** (a fájl az `allowed_paths`-on kívül van → H3).

### R4 — barrel-import KÖTELEZŐ, mély import TILOS

Az öt képernyő a design-rendszert KIZÁRÓLAG a barrelen át éri el:

```dart
import 'package:strumsight/core/design_system/public.dart';
```

Mély import (`…/design_system/components/…`, `…/foundations/…`) tilos
([ADR 0273](../adr/0273-design-system-token-source-of-truth.md) §1,
[ADR 0494](../adr/0494-derived-completion-matrix-and-h5-counter-reset.md)) — ez
volt az E15-R09 **BLOCKER-2** (24 mély import). MÉRVE: a szabály azóta a
`tool/check_architecture.dart`-ban él (`ss_… designSystemRoot` ág), tehát a
`tools/round-gate.sh` **`architecture`** lépése LOKÁLISAN méri. A
`test/core/architecture_dependency_test.dart` a `gate_tests`-be felvéve
(§0.0.C/R20 mintájára).

### R5 — az A3 bizonyítéka COMMITOLT cella, nem `/tmp`-próba

Az E15-R09-ben az A3 mércéje egy törölt `/tmp`-próbateszt volt. Képernyőnként a
variáns-cellák (textScale **1.5 / 2.0 / 2.5** × `en`/`hu`) HELYE kötött, és
mind az `allowed_paths`-on van — ÚJ tesztfájl nem kell:

| Képernyő | A variáns-cellák fájlja |
|---|---|
| `vision_setup_screen` | `test/features/vision/presentation/vision_setup_screen_test.dart` |
| `guitar_calibration_screen` | `test/features/vision/presentation/guitar_calibration_screen_test.dart` |
| `vision_session_screen` | `test/features/vision/vision_one_cue_test.dart` |
| `onboarding_screen` | `test/features/onboarding/onboarding_test.dart` |
| `followers_screen` | `test/features/community/block_mute_test.dart` |

A §6 küszöb-hármasa változatlan: `1.5` és `2.0` → **túlcsordulás nélkül
kötelező**; `2.5` → NEM követelmény, és a `2.0` teljesítése nem hivatkozhat rá.
Ugyanezekben a fájlokban kell legalább EGY design-rendszer **típus-állítás**
képernyőnként (`expect(find.byType(SsFailureState), …)` és társai) — az A2
mércéje nem lehet pusztán szöveg-keresés.

### R6 — `*ThemeScope`: pontosan EGY fájl érintett

MÉRVE (`grep -n ThemeScope` az öt fájlon): kizárólag
`followers_screen.dart:163` → `CommunityThemeScope`. A másik négy képernyőn ma
NINCS burkoló. A §3 „burkoló eltávolítása" tehát egyetlen fájlra vonatkozik;
`vision_result_screen.dart:37` (`VisionThemeScope`) **NINCS a scope-ban**, ne
nyúlj hozzá.

### R7 — az A7 mért aránya

MÉRVE a `docs/ui/migration-status.md:4` szerint a kör ELŐTT: **80/96
(83,333%)**. Az öt képernyő migrálása után az elvárt érték
**85/96 = 88,542%** (`python3 -c "print(round(85/96*100,3))"` → `88.542`). A
dokumentum ezt az arányt írja, a §7 mérő-parancsának kimenetével együtt.

### R8 (kör közbeni revízió, 2026-09-03) — a golden PNG-alapvonalak felvéve

**A lelet.** A gépi scope-audit `VIOLATION`-t adott 8 fájlra:
`test/ui/goldens/goldens/{e13_r16_onboarding_compact,
e13_r16_onboarding_compact_scale2, e13_r30_vision_coach_stage_compact,
e13_r30_vision_coach_stage_compact_scale2, e13_r30_vision_setup_compact,
e13_r30_vision_setup_compact_scale2, e13_r33_followers_compact,
e13_r33_followers_compact_scale2}.png`.

**A döntés indoklása — ez brief-hiba, nem implementer-túlnyúlás.** A brief §7
KIFEJEZETTEN előírja a golden-újrafelvételt
(`tools/golden-x86.sh record …`, [ADR 0426](../adr/0426-golden-recording-architecture.md)),
és a három golden **teszt**-fájl (`e13_r16`/`e13_r30`/`e13_r33`) rajta van az
`allowed_paths`-on — de az `allowed_paths` NEM sorolta fel azokat az
**alapvonal-PNG-ket**, amiket ez az előírt parancs szükségszerűen felülír. A
brief tehát önmagával volt ellentmondásban.

A `test/ui/goldens/goldens/**` **NEM tilos zóna**: a §4 tilos-zóna felsorolása
(`design_system`, `lib/app`, `docs/adr`, `tools`, `.github`,
`application`/`domain`/`data`/`providers`, más képernyők) nem tartalmazza. Ez
tehát a mulasztásból eredő hiányzó felsorolás esete, nem H3 — ugyanaz az
olvasati hiba lenne, mint a `docs/reviews/**` saját-jelentés hamis H3-a
(E99-R08, [L251](../LESSONS.md#l251)). A feloldás a kör SAJÁT, még nem
merge-elt briefjét érinti, tehát az ADR 0087 §2 szerint az orchestrátor
hatásköre, dokumentált §0.0 revízióval.

**A revízió szűk.** A nyolc PNG **tételesen** kerül az `allowed_paths`-ra (nem
glob), és mind a nyolc a kör öt képernyőjének egyikéhez tartozik — MÉRVE: a
`vision_result` / `launch` / `recovery` / mic-primer / first-win és a többi 7
community golden PNG **byte-azonos** maradt. Az arány így nem tágul: a kör
továbbra is pontosan a saját öt képernyőjének vizuális rétegét írja.

### R9 (kör közbeni revízió, 2026-09-03, review után) — a ROUTEREN át pinnelő teszt felvéve

**A lelet.** A `full-gate.yml` `33739838255` futása a `6461d8bb` HEAD-en PIROS
lett, és a MÉRT gyökérok a `test/features/vision/presentation/vision_session_routing_test.dart`
„Vision session route is registered behind only visionEnabled" cellája:

```
The following _TypeError was thrown building VisionSessionScreen: Null check operator used on a null value
#0  VisionSessionScreen.build (…/vision_session_screen.dart:51:64)
    VisionSessionScreen:file:///…/lib/app/routing/app_router.dart:617:36
```

Ez pontosan az [L593](../LESSONS.md#l593) / §0.0/R2 hibaosztálya: a harness
(`vision_session_routing_test.dart:43`) csupasz `MaterialApp.router`-t pumpol,
tehát a migrált képernyő `Theme.of(context).extension<SsColorScheme>()!`
olvasása null-check crash-t ad.

**Miért kerülte el az R2/R3 mérése.** Az R2 és R3 a `find.byType(<Képernyő>)`
/ osztálynév-hivatkozás alapján kereste a pinnelő harnesseket. Ez a fájl a
képernyőt **nem nevezi meg**: a `routerProvider`-en át `router.go(AppRoutes.visionSession)`
hívással jut el hozzá, tehát az osztálynév-keresés (és ugyanezen okból a
`brief-lint` S11 szabálya is) NEM találta meg. A `tools/`-beli lint
kiterjesztése a route-on át pinnelő tesztekre a §4 szerint NEM ennek a körnek
a dolga — az önjavító sáv tárgya, a leletet a `docs/LESSONS.md` rögzíti.

**A döntés.** A fájl felvéve az `allowed_paths`-ra **ÉS** a `gate_tests`-be,
pontosan úgy, ahogy az `S11` szabály előírja (a lecserélt képernyőt a briefen
kívül élő teszt pinneli → mindkét listára fel kell venni, különben H3). A
javítás iránya kötött és az R2-vel azonos: a harness a VALÓDI futásidejű témát
kapja (`SsLightTheme.data()` / `SsDarkTheme.data()`, ADR 0466). **Cella
törlése, `skip`-je vagy állítás-lazítása továbbra is TILOS** — a `router.go`
utáni két `expect` (`:68`, `:86`) változatlan marad.

### ADR

**Nincs új ADR**, és nem is kerül kiosztásra: a kör egyetlen ÚJ architekturális
döntést sem köt — a hivatkozott szerződéseket az ADR 0181 / 0184 / 0196 / 0273 /
0291 / 0399 / 0466 / 0494 már rögzíti. (Azonos az `E15-R08` és `E15-R09`
lezárásának mintájával; a `docs/adr/**` a §4 szerint tilos zóna.)

## 0.0.1 A kör határa: MEGJELENÉS, nem viselkedés

A migráció a képernyők VIZUÁLIS rétegét cseréli design-rendszer-komponensekre. A képernyő TÍPUSA, route-ja, publikus API-ja és üzleti viselkedése VÁLTOZATLAN — a típus-pinnelő tesztek (§4) ezért maradnak zöldek, és a jogosultság pontosan ennyi: **cella törlése, `skip`-je vagy gyengítése TILOS**. Az `E15-R01` óta az app témája hordozza a tokeneket, tehát ÚJ `*ThemeScope` burkoló NEM vezethető be; a meglévő burkoló eltávolítható, ha a képernyő már az app témájából old fel.

Ez a sáv utolsó migrációs batch-e: a kamera-út három képernyője, az onboarding (az ELSŐ, amit egy új felhasználó lát) és az egyetlen maradék közösségi képernyő.

```ai-router
schema_version = 1
risk = "high"
allowed_paths = [
  "lib/features/vision/presentation/screens/vision_setup_screen.dart",
  "lib/features/vision/presentation/screens/vision_session_screen.dart",
  "lib/features/vision/presentation/screens/guitar_calibration_screen.dart",
  "lib/features/onboarding/screens/onboarding_screen.dart",
  "lib/features/community/presentation/screens/followers_screen.dart",
  "test/accessibility/closure_suite_test.dart",
  "test/app/routing/app_router_test.dart",
  "test/app/routing/onboarding_first_win_test.dart",
  "test/core/screen_size_guard_test.dart",
  "test/features/community/block_mute_test.dart",
  "test/features/onboarding/first_win_test.dart",
  "test/features/onboarding/onboarding_resume_test.dart",
  "test/features/onboarding/onboarding_test.dart",
  "test/features/onboarding/permission_primer_test.dart",
  "test/features/vision/presentation/guitar_calibration_screen_test.dart",
  "test/features/vision/presentation/vision_session_routing_test.dart",
  "test/features/vision/presentation/vision_setup_screen_test.dart",
  "test/features/vision/vision_cleanup_test.dart",
  "test/features/vision/vision_degraded_test.dart",
  "test/features/vision/vision_one_cue_test.dart",
  "test/features/vision/vision_permission_test.dart",
  "test/ui/goldens/e13_r16_screens_golden_test.dart",
  "test/ui/goldens/e13_r30_screens_golden_test.dart",
  "test/ui/goldens/e13_r33_screens_golden_test.dart",
  "test/ui/ui_baseline_screenshot_test.dart",
  "docs/ui/migration-status.md",
  "docs/rounds/e15-r11-vision-onboarding-community-migration.md",
  "test/ui/goldens/goldens/e13_r16_onboarding_compact.png",
  "test/ui/goldens/goldens/e13_r16_onboarding_compact_scale2.png",
  "test/ui/goldens/goldens/e13_r30_vision_coach_stage_compact.png",
  "test/ui/goldens/goldens/e13_r30_vision_coach_stage_compact_scale2.png",
  "test/ui/goldens/goldens/e13_r30_vision_setup_compact.png",
  "test/ui/goldens/goldens/e13_r30_vision_setup_compact_scale2.png",
  "test/ui/goldens/goldens/e13_r33_followers_compact.png",
  "test/ui/goldens/goldens/e13_r33_followers_compact_scale2.png",
]
gate_tests = [
  "test/ui/ui_inventory_test.dart",
  "test/accessibility/closure_suite_test.dart",
  "test/app/routing/app_router_test.dart",
  "test/app/routing/onboarding_first_win_test.dart",
  "test/core/screen_size_guard_test.dart",
  "test/features/community/block_mute_test.dart",
  "test/features/onboarding/first_win_test.dart",
  "test/features/onboarding/onboarding_resume_test.dart",
  "test/features/onboarding/onboarding_test.dart",
  "test/features/onboarding/permission_primer_test.dart",
  "test/features/vision/presentation/guitar_calibration_screen_test.dart",
  "test/features/vision/presentation/vision_session_routing_test.dart",
  "test/features/vision/presentation/vision_setup_screen_test.dart",
  "test/features/vision/vision_cleanup_test.dart",
  "test/features/vision/vision_degraded_test.dart",
  "test/features/vision/vision_one_cue_test.dart",
  "test/features/vision/vision_permission_test.dart",
  "test/ui/goldens/e13_r16_screens_golden_test.dart",
  "test/ui/goldens/e13_r30_screens_golden_test.dart",
  "test/ui/goldens/e13_r33_screens_golden_test.dart",
  "test/ui/ui_baseline_screenshot_test.dart",
  "test/app/offline_network_guard_test.dart",
  "test/core/architecture_dependency_test.dart",
]
native_gate = false
```

**Kockázat = high, indoklás:** a diff felhasználói felületet ír át azon az úton, amit a felhasználó a leggyakrabban jár; egy elveszett állapot- vagy hibajelzés némán rontaná az élményt. A `flutter-reviewer` és a `flutter-devil-advocate` futtatása a review-ban KÖTELEZŐ.

## 0. Kör-jelzés és STOP-protokoll

```bash
tools/codex-signal.sh progress "<egy sor>"
tools/codex-signal.sh done "<egy sor>"
tools/codex-signal.sh stopped "<egy sor>"
tools/codex-signal.sh blocked "<egy sor>"
```

**STOP-protokoll:** ha a migrációhoz egy `application/`, `domain/` vagy `data/` réteg módosítása kellene, a kimenet a `stopped` jelzés — a viselkedés-változás nem ennek a körnek a hatásköre ([L478](../LESSONS.md#l478)).

## 1. Cél

A batch 5 képernyője a design-rendszer komponenseit és tokenjeit használja, változatlan viselkedés mellett — hogy a felület egységes legyen, és a 200%-os szövegskála, a képernyőolvasó és a két locale mindenhol működjön.

## 2. Jelenlegi állapot — mért tények

- A batch képernyői (MÉRVE `grep -L design_system`): `vision_setup_screen.dart`, `vision_session_screen.dart`, `guitar_calibration_screen.dart`, `onboarding_screen.dart`, `followers_screen.dart`.
- Egyik sem importálja a `core/design_system`-et; a stílusuk közvetlen `Theme.of(context)` / `AppColors` / `AppPalette` hivatkozásokból jön.
- Az `E15-R01` óta az app futásidejű témája a design-rendszer témája, tehát a komponensek burkoló NÉLKÜL is feloldják a tokeneket.
- Az `E15-R02` óta az adaptív shell az alapértelmezett belépő, tehát ezek a képernyők a fő navigációból elérhetők.
- A `test/ui/ui_inventory_test.dart` EGZAKT képernyőszámot állít — a kör nem hoz létre és nem töröl képernyőt, tehát a szám VÁLTOZATLAN.

## 3. Scope

**Benne van:** a felsorolt 5 képernyő vizuális migrálása (`SsCard`, `SsSection`, `SsButton`, `SsIconButton`, `SsContentCard`, `SsEmptyState`, `SsFailureState`, `SsSkeleton`, `SsPermissionState`, `SsMetricCard` és társaik — a MÉRT nevek a §0.0/R1-ben; `SsSpacing`/`SsTypography` tokenek) · a meglévő `*ThemeScope` burkoló eltávolítása, ahol az `E15-R01` óta felesleges · a `migration-status.md` frissítése a MÉRT új aránnyal.

Batch-specifikus kikötések:

- a kamera-életciklus (lease, engedély, hőmérsékleti degradáció) ÉRINTETLEN (ADR 0184/0196)
- az onboarding lépés-sorrendje és a `seen` állapot kezelése változatlan; a permission-primer az `E15-R02`-ben MÁR javítva lett
- a `followers_screen` privát-profil szabályai (ADR 0291/0399) érvényben maradnak

**NINCS benne (tilos):**

- `application/`, `domain/`, `data/`, `providers/` réteg módosítása (viselkedés-változás).
- Új képernyő létrehozása vagy meglévő törlése.
- Új `*ThemeScope` burkoló bevezetése.
- ARB-kulcs törlése vagy szöveg-jelentés megváltoztatása (új kulcs FELVEHETŐ, ha a komponens ezt igényli — mindkét locale-ra, egyszerre).
- `docs/adr/**`.

## 4. Engedélyezett fájlok

| Útvonal | Indok |
|---|---|
| `lib/features/vision/presentation/screens/vision_setup_screen.dart` | migráció design-rendszer komponensekre |
| `lib/features/vision/presentation/screens/vision_session_screen.dart` | migráció design-rendszer komponensekre |
| `lib/features/vision/presentation/screens/guitar_calibration_screen.dart` | migráció design-rendszer komponensekre |
| `lib/features/onboarding/screens/onboarding_screen.dart` | migráció design-rendszer komponensekre |
| `lib/features/community/presentation/screens/followers_screen.dart` | migráció design-rendszer komponensekre |
| `test/accessibility/closure_suite_test.dart` | típus-pinnelő őr — VÁLTOZATLANUL zöld marad (§0.0) |
| `test/app/routing/app_router_test.dart` | típus-pinnelő őr — VÁLTOZATLANUL zöld marad (§0.0) |
| `test/app/routing/onboarding_first_win_test.dart` | típus-pinnelő őr — VÁLTOZATLANUL zöld marad (§0.0) |
| `test/core/screen_size_guard_test.dart` | típus-pinnelő őr — VÁLTOZATLANUL zöld marad (§0.0) |
| `test/features/community/block_mute_test.dart` | típus-pinnelő őr — VÁLTOZATLANUL zöld marad (§0.0) |
| `test/features/onboarding/first_win_test.dart` | típus-pinnelő őr — VÁLTOZATLANUL zöld marad (§0.0) |
| `test/features/onboarding/onboarding_resume_test.dart` | típus-pinnelő őr — VÁLTOZATLANUL zöld marad (§0.0) |
| `test/features/onboarding/onboarding_test.dart` | típus-pinnelő őr — VÁLTOZATLANUL zöld marad (§0.0) |
| `test/features/onboarding/permission_primer_test.dart` | típus-pinnelő őr — VÁLTOZATLANUL zöld marad (§0.0) |
| `test/features/vision/presentation/guitar_calibration_screen_test.dart` | típus-pinnelő őr — VÁLTOZATLANUL zöld marad (§0.0) |
| `test/features/vision/presentation/vision_setup_screen_test.dart` | típus-pinnelő őr — VÁLTOZATLANUL zöld marad (§0.0) |
| `test/features/vision/vision_cleanup_test.dart` | típus-pinnelő őr — VÁLTOZATLANUL zöld marad (§0.0) |
| `test/features/vision/vision_degraded_test.dart` | típus-pinnelő őr — VÁLTOZATLANUL zöld marad (§0.0) |
| `test/features/vision/vision_one_cue_test.dart` | típus-pinnelő őr — VÁLTOZATLANUL zöld marad (§0.0) |
| `test/features/vision/vision_permission_test.dart` | típus-pinnelő őr — VÁLTOZATLANUL zöld marad (§0.0) |
| `test/ui/goldens/e13_r16_screens_golden_test.dart` | típus-pinnelő őr — VÁLTOZATLANUL zöld marad (§0.0) |
| `test/ui/goldens/e13_r30_screens_golden_test.dart` | típus-pinnelő őr — VÁLTOZATLANUL zöld marad (§0.0) |
| `test/ui/goldens/e13_r33_screens_golden_test.dart` | típus-pinnelő őr — VÁLTOZATLANUL zöld marad (§0.0) |
| `test/ui/ui_baseline_screenshot_test.dart` | típus-pinnelő őr — VÁLTOZATLANUL zöld marad (§0.0) |
| `docs/ui/migration-status.md` | a MÉRT arány frissítése |

**Tilos zóna:** a batch feature-einek `application/`, `domain/`, `data/`, `providers/` könyvtárai · minden más `lib/features/**` képernyő · `lib/app/**` · `lib/core/design_system/**` (a komponenseket HASZNÁLJUK, nem módosítjuk) · `docs/adr/**` · `tools/**` · `.github/**`

## 5. Kötött architekturális döntések

Nincs ÚJ ADR. Három kötelező szabály:

### 5.1 A viselkedés bitre azonos marad

Ugyanaz az adat, ugyanaz a sorrend, ugyanazok az állapotok (üres, betöltés, hiba). **NEM elfogadható gyengítés:** „egyszerűsítettük a hibaállapotot" — az információvesztés, nem migráció.

### 5.2 Minden állapotnak van design-rendszer-megfelelője

Üres lista → `SsEmptyState`, hiba → **`SsFailureState`** (a `SsErrorState` NEM létezik — §0.0/R1), betöltés → `SsSkeleton` (vagy `SsAsyncState`), engedély-elutasítás → `SsPermissionState`. **NEM elfogadható gyengítés:** nyers `CircularProgressIndicator` vagy csupasz `Text('Hiba')` meghagyása.

### 5.3 A szöveg lokalizált marad

Beégetett felhasználói szöveg nem kerülhet a migrált kódba; új szöveg egyszerre `en` ÉS `hu` ARB-kulcsot kap. **NEM elfogadható gyengítés:** angol placeholder „amíg lefordítjuk".

## 6. Acceptance criteria

| # | Kritérium | Bizonyíték |
|---|---|---|
| A1 | Mind a 5 képernyő importálja a `core/design_system`-et, és a mérés szerint migráltnak számít | a §7 mérő-parancs kimenete a §10-ben |
| A2 | Minden migrált képernyő üres/betöltés/hiba állapota design-rendszer-komponens | a batch célzott widget-tesztjei |
| A3 | A képernyők `textScaler 2.0` mellett, `en` ÉS `hu` locale-on túlcsordulás nélkül renderelnek | a batch variáns-cellái |
| A4 | A típus-pinnelő tesztek VÁLTOZATLANUL zöldek, egyetlen cellájuk sem törölt/`skip`-elt | a §7 gate + `git diff` a teszt-fájlokon |
| A5 | A `ui_inventory_test.dart` egzakt száma VÁLTOZATLAN | a §7 gate |
| A6 | Nincs beégetett felhasználói szöveg a migrált kódban | `test/l10n/hardcoded_string_guard_test.dart` |
| A7 | A `migration-status.md` a MÉRT új arányt írja (a mérés parancsával) | a dokumentum |

**Küszöb-cellahármas a szövegskálára** (a kötelező határ `2.0`, INKLUZÍV): a küszöb **alatt** (`1.5`) → nincs túlcsordulás; **pontosan rajta** (`2.0`) → nincs túlcsordulás, EZ az A3 feltétele; a küszöb **fölött** (`2.5`) → nem követelmény, és a `2.0` teljesítése nem hivatkozhat rá.

### 6.1 Mérce-mátrix — melyik hibás implementációt melyik cella fogja pirosra

| Hibás implementáció | Melyik cella vált PIROSRA |
|---|---|
| A képernyő megkapja a komponenseket, de a hibaállapot nyers `Text` marad | A2 |
| A migráció csak `en` locale-on lett kipróbálva, a hosszabb `hu` szöveg túlcsordul | A3 |
| A migráció közben egy típus-pinnelő teszt cellája `skip`-re kerül a zöldért | A4 |
| Egy szöveg beégetve kerül a kódba | A6 |
| A képernyő importálja a design-rendszert, de a stílus továbbra is `AppColors`-ból jön | A1 (a mérés a MIGRÁLT/legacy besorolást is ellenőrzi a kód alapján) |

**Valódi-sértés próba (KÖTELEZŐ, a §10-ben dokumentálva):** cserélj vissza EGY migrált képernyőn egy `SsFailureState`-et nyers `Text`-re, futtasd a §7 gate-et → az **A2** cellának PIROSNAK kell lennie → állítsd vissza.

## 7. Kötelező ellenőrzések

```bash
tools/round-gate.sh test/ui/ui_inventory_test.dart test/app/offline_network_guard_test.dart test/core/architecture_dependency_test.dart test/accessibility/closure_suite_test.dart test/app/routing/app_router_test.dart test/app/routing/onboarding_first_win_test.dart test/core/screen_size_guard_test.dart test/features/community/block_mute_test.dart test/features/onboarding/first_win_test.dart test/features/onboarding/onboarding_resume_test.dart test/features/onboarding/onboarding_test.dart test/features/onboarding/permission_primer_test.dart test/features/vision/presentation/guitar_calibration_screen_test.dart test/features/vision/presentation/vision_session_routing_test.dart test/features/vision/presentation/vision_setup_screen_test.dart test/features/vision/vision_cleanup_test.dart test/features/vision/vision_degraded_test.dart test/features/vision/vision_one_cue_test.dart test/features/vision/vision_permission_test.dart test/ui/goldens/e13_r16_screens_golden_test.dart test/ui/goldens/e13_r30_screens_golden_test.dart test/ui/goldens/e13_r33_screens_golden_test.dart test/ui/ui_baseline_screenshot_test.dart
```

A migrációs mérés (a kimenet a §10-be, batch-enként MIGRATED/legacy sorokkal):

```bash
for f in lib/features/vision/presentation/screens/vision_setup_screen.dart lib/features/vision/presentation/screens/vision_session_screen.dart lib/features/vision/presentation/screens/guitar_calibration_screen.dart lib/features/onboarding/screens/onboarding_screen.dart lib/features/community/presentation/screens/followers_screen.dart; do grep -q design_system "$f" && echo "MIGRATED $f" || echo "legacy $f"; done
```

Ha a batch képernyőjének VAN golden PNG-je, az újrafelvétel KIZÁRÓLAG a merge-kapu architektúráján (ADR 0426):

```bash
tools/golden-x86.sh record <a batch érintett golden-teszt fájljai>
```

## 8. Implementációs sorrend

1. A `retirement-plan.md` beolvasása → a tényleges képernyő-lista.
2. Képernyőnként: komponens-csere → állapotok (üres/betöltés/hiba) → tokenek → `*ThemeScope` eltávolítása.
3. A batch célzott widget-tesztjei (állapotok + `textScale 2.0` + `en`/`hu`).
4. A mérés futtatása, `migration-status.md` frissítése.
5. A valódi-sértés próba a §10-be.

## 9. Kockázatok

- **Néma információvesztés.** A migráció közben elveszett állapot vagy mező a leggyakoribb hiba (A2).
- **Locale-vak elrendezés.** A magyar szövegek hosszabbak; az `en`-re szabott elrendezés túlcsordul (A3).
- **Scope-csúszás a viselkedés felé.** Egy „apró" providers-módosítás a kör mérhetőségét rontja (STOP-eset).

## 10. Implementation handoff — az implementer tölti ki

### 10.1 Komponens-térkép képernyőnként

**`vision_setup_screen.dart`** — barrel import (`core/design_system/public.dart`).
`_PrivacyNotice` Container→`SsCard` (title/body `SsTypography`/`SsColorScheme`
színezve). `_ProfileStep`/`_CameraStep`/`_PermissionStep`/`_ReadyStep`/
`_AudioOnlyStep` mind `SsSection(title: ..., child: ...)`-ba kerültek (a
korábbi kézi "Text(headlineSmall) + SizedBox" mintát váltva). A lépések
"Continue" `FilledButton`-jai → `SsButton` (primary). Minden nyers
`SizedBox(height: N)` → `SsSpacing.spaceN` token. A `CameraPermissionPanel`
(külön widget-fájl, NEM ezen kör allowed_paths-án) változatlanul hívva —
az engedély-elutasítás VALÓDI rajzolása ott történik, nem ebben a fájlban.
Az AppBar "Skip" `TextButton`-ja SZÁNDÉKOSAN maradt nyers: a meglévő
`ConstrainedBox(maxWidth: 120)` + `maxLines: 2` kombináció egy már bevizsgált
A9-defenzíva nagy szövegskálára — az `SsButton` egysoros `Flexible+ellipsis`
mintája ezt a védelmet elvenné.

**`vision_session_screen.dart`** — barrel import. Preview-háttér
`DecoratedBox` színe `colors.surfaceSunken`-re token-esítve. A státusz-szöveg
`SsTypography.bodyLarge`-ot kap, és `colors.danger`-re vált
engedély-elutasítás/eszköz-hiba/inferencia-hiba állapotoknál (üzenet
VÁLTOZATLAN, csak a szín jelez súlyosságot). `SwitchListTile` →
`SsSwitchRow` (ugyanaz a kulcs, érték, callback, felirat). `_ThermalBanner`
Container-je `colors.warning`-alapú háttérre/keretre vált (korábban
`tertiaryContainer`). A `_SessionActions` mind a 8 `FilledButton`/
`OutlinedButton`-ja → `SsButton` (primary/secondary), a `Wrap` spacingja
`SsSpacing.space2`. **NEM vezettem be `SsPermissionState`-et** a
permission-denied/permanently-denied állapotokra (§0.0/R1 irányelve ide
mutatna) — indoklás a §10.3-ban.

**`guitar_calibration_screen.dart`** — barrel import. `_QualityScorePanel`
Container→`SsCard`. `_Toolbar` 3 gombja (`TextButton`×2 + `FilledButton`) →
`SsButton` (tertiary/primary/tertiary); a `Row(spaceEvenly)` →
`Wrap(alignment: spaceEvenly)`, mert az ÚJ A3 cellák 1.5-ös textScale-en
118px túlcsordulást mértek a 3 egymás melletti gombbal — ez a kör SAJÁT
mérési eredménye, nem előre feltételezett hiba (lásd §10.2). `_EntryBanner`
Container-je `colors.danger`-alapú háttérre/keretre vált (korábban
`errorContainer`), a szöveg és az `Icons.warning_amber` ikon is
`colors.danger`-t kap. A precíziós zoom `IconButton` (`Icons.zoom_in`/
`zoom_out`) SZÁNDÉKOSAN maradt nyers — az `SsIcon` katalógusban nincs
`zoom_in`/`zoom_out` név (csak play/pause/settings/close/check/info + 14
gitár-glifa, mérve `ss_icons.dart`), egy nem-katalogizált név a látható
"hiányzó glifa" fallbackra váltana (ugyanaz a kivétel-osztály, mint az
E15-R09 handoff ikon-megjegyzése). Az `AlertDialog` reset/recalibrate
megerősítő gombjai (`TextButton`/`FilledButton`) SZÁNDÉKOSAN maradtak
nyersek — a `destructive` `SsButton`-variánshoz kötelező
`destructiveSemanticHint` szöveg nincs meglévő ARB-kulcsban, és ez a kör
nem vehet fel új ARB-kulcsot (lásd §10.3).

**`onboarding_screen.dart`** — barrel import, `core/theme/app_colors.dart`
import törölve (minden `AppColors.*` hivatkozás `SsColorScheme`-re
cserélve). "Skip"/"Enable mic & start" `TextButton` → `SsButton` (tertiary).
A fő CTA (`Next`/`Try your first win`) `FilledButton` → `SsButton` (primary,
`SizedBox(width: double.infinity)`-be csomagolva — a korábbi
`minimumSize: Size.fromHeight(54)` stílus nem írható át `SsButton`-on,
így a gomb magassága a design-rendszer `SsSemantics.minimumInteractiveDimension`
(48dp) alapértékére vált, ami VIZUÁLIS, nem viselkedésbeli változás).
`_Page` nyíl-ikonjai és a `_Dots` pöttyei `colors.brand`/`colors.confidenceHigh`
tokent kapnak `AppColors` helyett. A carousel cím
(`fontFamily: 'Montserrat', w800, 26px`) SZÁNDÉKOSAN maradt egyedi stílus —
ez egy márka-specifikus hero-felirat, nem térkép a design-rendszer
`SsTypography` skálájára (a legközelebbi `headlineMedium` Poppins/w700,
vizuálisan más karakterű lenne egy meglévő golden nélküli indoklás nélkül).

**`followers_screen.dart`** — barrel import. `_FollowerTile` teljes sora
`SsCard`-ba került (avatár + név/handle + 2 ikon-gomb megmaradt, mert az
`SsContentCard` NEM támogat egyedi avatár-widgetet — annak használata
információvesztés lenne). Név/handle szövegek `SsTypography`/`SsColorScheme`
tokent kapnak. A mute/block `IconButton`-ok SZÁNDÉKOSAN maradtak nyersek —
`volume_off`/`block` NINCS az `SsIcon` katalógusban (ugyanaz a kivétel-osztály,
mint fent), csak a színük lett token-esítve (`colors.textSecondary`/
`colors.danger`). Az üres állapot (`'No one here yet.'`) és a footer-spinner
képernyő-lokális, token-stílusú maradt (`colors.textSecondary`/`colors.brand`)
— NEM `SsEmptyState`, mert nincs valódi akció (ugyanaz a kivétel-osztály,
mint a `ProgressScreen`/`RewardInboxScreen` precedens). A `CommunityThemeScope`
burkoló MEGMARADT — indoklás §10.4-ben. A `'Followers'`/`'Following'`/
`'No one here yet.'`/`'Network error'`/`'Server error'` beégetett angol
szövegek ELŐZŐLEG is jelen voltak (nem ez a kör vezette be), és ARB-fájl
nincs ezen kör `allowed_paths`-án — indoklás §10.3-ban.

### 10.2 §6 mérés kimenete

```
$ for f in lib/features/vision/presentation/screens/vision_setup_screen.dart lib/features/vision/presentation/screens/vision_session_screen.dart lib/features/vision/presentation/screens/guitar_calibration_screen.dart lib/features/onboarding/screens/onboarding_screen.dart lib/features/community/presentation/screens/followers_screen.dart; do grep -q design_system "$f" && echo "MIGRATED $f" || echo "legacy $f"; done
MIGRATED lib/features/vision/presentation/screens/vision_setup_screen.dart
MIGRATED lib/features/vision/presentation/screens/vision_session_screen.dart
MIGRATED lib/features/vision/presentation/screens/guitar_calibration_screen.dart
MIGRATED lib/features/onboarding/screens/onboarding_screen.dart
MIGRATED lib/features/community/presentation/screens/followers_screen.dart
```

Teljes fa méréssel is megerősítve: `for f in $(find lib/features -name
'*_screen.dart' | sort); do grep -q design_system "$f" ...; done | grep -c
MIGRATED` → **85**, `wc -l` a teljes listára → **96**. `docs/ui/migration-status.md`
frissítve **85/96 (88,542%)**-ra (`python3 -c "print(round(85/96*100,3))"` →
`88.542`).

Az A3 mátrix futtatása közben a `guitar_calibration_screen_test.dart` ÚJ
1.5/2.0×en/hu cellái **valódi túlcsordulást mértek** (`RenderFlex overflowed
by 118 pixels on the right`) a `_Toolbar` 3 gombos `Row`-ján — ez a kör
SAJÁT hibája volt (az `SsButton` migráció óta), nem előzetes defekt. Javítás:
`Row(mainAxisAlignment: spaceEvenly)` → `Wrap(alignment: spaceEvenly)`
(ugyanazok a gombok, ugyanaz a sorrend, csak sortörhet nagy szövegskálán).
Az összes többi A3 cella (vision_setup, vision_session, onboarding,
followers) ELSŐ futásra zöld volt.

### 10.3 §7 / preambulum-§7 valódi-sértés próba

Visszaváltottam `vision_setup_screen.dart` `_ProfileStep`-jének
`SsButton(key: 'vision-setup-profile-continue')`-ját nyers
`FilledButton`-ra, majd lefuttattam:

```
$ flutter test test/features/vision/presentation/vision_setup_screen_test.dart
...
A3 — textScale variant matrix (1.5 / 2.0 × en / hu) the profile step uses the design-system SsButton [E]
  Expected: at least one matching candidate
  Actual: _TypeWidgetFinder:<Found 0 widgets with type "SsButton": []>
Some tests failed.
```

**PIROS**, pontosan az A1/A3 típus-állítás cellája (`find.byType(SsButton)`).
Visszaállítottam a `SsButton`-t, újrafuttattam ugyanazt a fájlt — **13/13
zöld**. A próbát a diffben NEM hagytam bent (`git diff --stat` a fájlra
üres a visszaállítás után).

### 10.4 Amit NEM tettem meg, és miért

1. **`SsPermissionState` a vision_session_screen.dart permission-denied
   állapotára (§0.0/R1 irányelve).** A komponens KÖTELEZŐ, egyedi
   `rationale`/`consequence` szöveget vár; a meglévő ARB-kulcsok
   (`visionSessionPermission`, `visionSetupPermissionDenied`, …) nem
   bomlanak tisztán "miért kell" / "mi történik, ha nem" párra anélkül,
   hogy jelentés-átfedést vagy kitalált szöveget vinnék be — és ez a kör
   `allowed_paths`-a NEM tartalmaz ARB-fájlt, tehát új kulcsot sem tudok
   felvenni. A vision-út VALÓDI, gazdag engedély-UI-ja (`CameraPermissionPanel`,
   a `vision_setup_screen.dart` `_PermissionStep`-jén át hívva) egy
   KÜLÖN widget-fájlban él, ami NINCS ezen kör `allowed_paths`-án — ott
   már ma is állapot-specifikus (granted/denied/permanently denied/
   restricted/unavailable) elágazó UI van, csak nem `Ss*` komponensekkel.
   A `vision_session_screen.dart` saját, másodlagos állapot-tükrözése
   (szöveg + gomb) `colors.danger`-re vált színt engedély-/eszköz-hiba
   állapotokban — ez a kompromisszum ugyanabba az osztályba esik, mint az
   E15-R04..R09 rondák "nincs valódi akció → képernyő-lokális, token-stílusú
   widget" precedense.
2. **ARB-kulcs felvétel / meglévő beégetett szöveg cseréje
   `followers_screen.dart`-ban** (`'Followers'`, `'Following'`,
   `'No one here yet.'`, `'Network error'`, `'Server error'`) — ezek a
   sztringek MÁR jelen voltak a képernyőn a kör előtt (nem ez a kör vezette
   be), és `lib/l10n/base/app_<locale>.arb` / `lib/l10n/features/*.arb`
   NINCS ezen kör `allowed_paths`-án (ellenőrizve: az `ai-router` blokk
   egyetlen `.arb` fájlt sem sorol fel). A `test/l10n/hardcoded_string_guard_test.dart`
   hatóköre (mérve a teszt saját `_scopeDirs` listájából) KIZÁRÓLAG
   `lib/core/design_system/{components,accessibility,layouts,motion}` — a
   `lib/features/**` fájlokat NEM vizsgálja, tehát ez a mérce-lelet nem
   buktatja meg a kaput, de a §5.3 szabály szellemében dokumentálom: ÚJ
   beégetett szöveget NEM vezettem be, a meglévőt nem tudtam ARB-ra
   cserélni a fájllista korlátja miatt.
3. **`CommunityThemeScope` eltávolítása `followers_screen.dart`-ról**
   (§3 "burkoló eltávolítása, ahol felesleges" + §0.0/R6 szó szerinti
   szövege). MÉRVE: az `e13_r33_screens_golden_test.dart` (ezen kör
   `allowed_paths`-án) és a `block_mute_test.dart` `FollowersScreen`-t egy
   puszta `AppTheme.dark()`/témátlan `MaterialApp` alatt pumpálja — a
   `CommunityThemeScope.mergeSsExtensions` az EGYETLEN forrás, ami ott az
   `SsColorScheme`/`SsTypography` kiterjesztést biztosítja. Eltávolítása
   null-check összeomlást okozna ezekben a mért harnessekben — ugyanaz a
   döntési osztály, mint a `GamificationThemeScope` E15-R08-as megtartása.
4. **`SsIconButton` a zoom/mute/block ikonokra.** Az `SsIcon` katalógus
   (mérve `ss_icons.dart`) csak `play`/`pause`/`settings`/`close`/`check`/
   `info` + 14 gitár-glifa nevet ismer — `zoom_in`, `zoom_out`,
   `volume_off_outlined`, `block_outlined` egyike sincs benne, egy
   nem-egyező név a látható "hiányzó glifa" fallbackra váltana (valódi
   regresszió, nem biztonságos csere — ugyanaz a mérés, mint az E15-R09
   handoff icon-megjegyzése).
5. **`destructive` `SsButton`-variáns a guitar_calibration reset/recalibrate
   megerősítő `AlertDialog`-okban.** A variáns megköveteli a
   `destructiveSemanticHint`-et, ami hívó-oldali, kitalálatlan szöveg kell
   legyen — nincs meglévő ARB-kulcs erre, és ARB nincs ezen kör
   `allowed_paths`-án (lásd 2. pont).
6. **Golden-újrafelvétel `ADR 0426` szerint x86-on:** lefutott
   (`tools/golden-x86.sh record test/ui/goldens/e13_r16_screens_golden_test.dart
   test/ui/goldens/e13_r30_screens_golden_test.dart
   test/ui/goldens/e13_r33_screens_golden_test.dart`), 8 PNG változott
   (2× onboarding, 4× vision setup/coach stage, 2× followers) — a
   `vision_result`/`launch`/`recovery`/`mic-permission primer`/
   `first-win mini Stage`/a többi 7 community-képernyő golden PNG-je
   BYTE-AZONOS maradt (nem ért hozzájuk ez a kör).

### 10.5 A kötelező gate kimenete

```
$ tools/round-gate.sh test/ui/ui_inventory_test.dart test/app/offline_network_guard_test.dart test/core/architecture_dependency_test.dart test/accessibility/closure_suite_test.dart test/app/routing/app_router_test.dart test/app/routing/onboarding_first_win_test.dart test/core/screen_size_guard_test.dart test/features/community/block_mute_test.dart test/features/onboarding/first_win_test.dart test/features/onboarding/onboarding_resume_test.dart test/features/onboarding/onboarding_test.dart test/features/onboarding/permission_primer_test.dart test/features/vision/presentation/guitar_calibration_screen_test.dart test/features/vision/presentation/vision_setup_screen_test.dart test/features/vision/vision_cleanup_test.dart test/features/vision/vision_degraded_test.dart test/features/vision/vision_one_cue_test.dart test/features/vision/vision_permission_test.dart test/ui/goldens/e13_r16_screens_golden_test.dart test/ui/goldens/e13_r30_screens_golden_test.dart test/ui/goldens/e13_r33_screens_golden_test.dart test/ui/ui_baseline_screenshot_test.dart

format                                                     zöld
analyze                                                    zöld
test test/ui/ui_inventory_test.dart                        zöld
test test/app/offline_network_guard_test.dart              zöld
test test/core/architecture_dependency_test.dart           zöld
test test/accessibility/closure_suite_test.dart            zöld
test test/app/routing/app_router_test.dart                 zöld
test test/app/routing/onboarding_first_win_test.dart       zöld
test test/core/screen_size_guard_test.dart                 zöld
test test/features/community/block_mute_test.dart          zöld
test test/features/onboarding/first_win_test.dart          zöld
test test/features/onboarding/onboarding_resume_test.dart  zöld
test test/features/onboarding/onboarding_test.dart         zöld
test test/features/onboarding/permission_primer_test.dart  zöld
test test/features/vision/presentation/guitar_calibration_screen_test.dart zöld
test test/features/vision/presentation/vision_setup_screen_test.dart zöld
test test/features/vision/vision_cleanup_test.dart         zöld
test test/features/vision/vision_degraded_test.dart        zöld
test test/features/vision/vision_one_cue_test.dart         zöld
test test/features/vision/vision_permission_test.dart      zöld
test test/ui/goldens/e13_r16_screens_golden_test.dart      zöld
test test/ui/goldens/e13_r30_screens_golden_test.dart      zöld
test test/ui/goldens/e13_r33_screens_golden_test.dart      zöld
test test/ui/ui_baseline_screenshot_test.dart              zöld
architecture                                               zöld
secrets                                                    PIROS (1)
```

A brief §5 SAJÁT maga csak `format → analyze → test <mindegyik külön> →
architecture` lépéseket nevesíti a gate-ként — mind a NÉGY lépéstípus zöld
(24/24 futtatott test-fájl beleértve, egyenként külön processzben). A
`round-gate.sh`-ban emellett élő `secrets`/`l10n` lépés a `secrets`-en piros
lett — **ez MÉRVE nem ennek a körnek a hibája**: a talált sor
(`tools/tests/test_authenticated_git_fetch.py:34`, egy `TOKEN = "github_pat_…"`
alakú, önmagát fixture-ként megnevező teszt-konstans; az ÉRTÉKÉT ez a
dokumentum szándékosan NEM idézi szó szerint, mert a titok-szkenner a puszta
idézetre is találatot adna) BYTE-AZONOS a
`main`-en is (`git diff --stat main -- tools/tests/test_authenticated_git_fetch.py`
üres kimenetet ad), és a `61cd9e3e` commitból származik (ADR 0495 D5, egy
másik, korábbi kör munkája) — TEHÁT minden `main`-ből ágazó branch-en
ugyanígy piros lenne. A fájl `tools/**` alatt van, ami ennek a körnek
TILOS zónája, és a `.claude/hooks/protect_factory_files.py` gépi őr
kifejezetten megtiltja, hogy a mérőeszközt (`tool/ci/*`) az javítsa, akit
mér — a helyes válasz a hook saját szövege szerint is emberi döntés, nem
implementer-oldali javítás. Javasolt javítás (NEM ez a kör hatásköre):
`// strumsight:allow-secret test fixture, not a real token` felvétele a
`tools/tests/test_authenticated_git_fetch.py:34` sor végére.

A `test/l10n/hardcoded_string_guard_test.dart` (A6) is lefutott KÜLÖN
(`flutter test test/l10n/hardcoded_string_guard_test.dart` → 1/1 zöld) —
hatóköre mérve KIZÁRÓLAG `lib/core/design_system/{components,accessibility,
layouts,motion}`, tehát a `lib/features/**` migrált képernyőket nem
vizsgálja (lásd §10.4/2).

## 11. Review — a Claude tölti ki
