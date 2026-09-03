# E15-R11 — kör-review (ADR 0055)

- **Kör:** `E15-R11` — Vision, onboarding és a maradék közösségi képernyő migrálása
- **Branch:** `sonnet-impl/e15-r11-vision-onboarding-community-migration`
- **Review HEAD:** `6461d8bb` (upstream-szinkron merge után, `origin/main = d0e21add`)
- **Implementer motor:** `sonnet-impl` (Claude Code harness)
- **Reviewer:** Claude (Opus 5), orchestrátor — READ-ONLY, izolált klón: `/tmp/e15r11-review`
- **Dátum:** 2026-09-03
- **Kötelező ügynökök (`risk = "high"`):** `flutter-reviewer`, `flutter-devil-advocate`,
  `security-reviewer` — mindhárom lefuttatva.

## 0. Gépi mércék a review HEAD-jén

| Mérce | Eredmény |
|---|---|
| `tools/scope-audit.py --base d0e21add` | **ok** — 27 fájl, 0 sértés |
| `tools/round-gate.sh <a §7 lista>` | **MINDEN GATE ZÖLD** (format, analyze, 22 teszt-fájl külön processzben, architecture, secrets, l10n) |
| `router-ci.yml` @ `6461d8bb` | **success** (`33739760525`) |
| `full-gate.yml` @ `6461d8bb` | dispatch-elve (`33739838255`) |

Megjegyzés: az implementer §10.5-ben `secrets PIROS (1)` szerepel — az a lelet a
`tools/tests/test_authenticated_git_fetch.py` fixture-literálja volt, amit az
`origin/main`-en azóta merge-elt `[HEAL E15-R10]` (`d0e21add`) javított. Az
upstream-szinkron (§0.3) után a `secrets` lépés a review HEAD-jén **zöld** —
a kör nem hordoz nyitott titok-leletet.

## 1. Verdikt

**CHANGES REQUESTED** — 0 BLOCKER, **3 MAJOR**, 2 MINOR, 4 NOTE.

A kör gerince rendben van: a scope tiszta, a viselkedés mérhetően változatlan
(kulcs-, `l10n`-, callback- és életciklus-halmazok bitre azonosak), a kipinnelt
cellák közül egyet sem töröltek, `skip`-eltek vagy lazítottak, és a §0.0 R1–R8
pre-flight mérései helytállóak. A három MAJOR **ugyanannak a hibaosztálynak** a
két oldala: az A3 mércéje három képernyőn nem méri azt, amit ígér, és emiatt egy
valódi szövegvágás átcsúszott rajta.

## 2. MAJOR leletek

### MAJOR-1 — az onboarding fő CTA-ja levágja a feliratát a KÖTELEZŐ A3-küszöbön

`lib/features/onboarding/screens/onboarding_screen.dart:231-238` — a fő CTA
(`onboardNext` / `onboardFirstWin`) `FilledButton(child: Text(...))`-ról
`SsButton`-ra váltott.

MÉRVE (`lib/core/design_system/components/actions/ss_button.dart:66-70`):

```dart
Flexible(child: Text(label, overflow: TextOverflow.ellipsis)),
```

Az `SsButton` a feliratot **egy sorra** vágja. A régi `FilledButton` `Text`-je
tördelt, tehát a teljes szöveg olvasható maradt. A `hu` „Próbáld ki az első
győzelmed — 30 mp" felirat a `2.0`-s (KÖTELEZŐ, inkluzív) szövegskálán a gomb
teljes szélességét meghaladja telefon-szélességen, tehát a szöveg jelentős
része rejtve marad — **információvesztés a legelső képernyőn, amit egy új
felhasználó lát**.

Ez a repóban **már eldöntött** hibaosztály:
`lib/features/gamification/presentation/screens/streak_detail_screen.dart:117-126`
szó szerint ezt az indoklást hordozza (E15-R08 review M3), és
`test/features/gamification/presentation/streak_detail_screen_test.dart:182`
`didExceedMaxLines` cellával pinneli. Az E15-R11 ugyanezt a cserét egy HOSSZABB
feliraton végzi el, ilyen cella nélkül.

**Elvárás:** vagy a dokumentált-kivétel út (nyers `FilledButton` + `Text`, a
kódban hivatkozva erre a review-ra), vagy marad az `SsButton`, de akkor egy
COMMITOLT cella bizonyítja `didExceedMaxLines == false`-ként `hu` × `2.0`-n,
**telefon-szélességű felületen**. Bármelyik út, a mércét cella tartja.

### MAJOR-2 — három A3 variáns-mátrix 800×600-on fut, tehát nem is láthatja a túlcsordulást

MÉRVE (`grep -c physicalSize`):

```
test/features/onboarding/onboarding_test.dart                          0
test/features/community/block_mute_test.dart                           0
test/features/vision/vision_one_cue_test.dart                          0
test/features/vision/presentation/vision_setup_screen_test.dart        2   (Size(412,915))
test/features/vision/presentation/guitar_calibration_screen_test.dart  1   (Size(412,915))
```

A `flutter_test` alapértelmezett felülete 800×600 — **szélesebb, mint bármelyik
telefon**. Az a két fájl, amelyik telefon-szélességet állít, ebben a körben
valódi hibát fogott (§10.2: `RenderFlex overflowed by 118 pixels` a kalibrációs
eszköztáron); az a három, amelyik nem, elsőre zöld volt — köztük az onboarding,
ami a MAJOR-1-et hordozza. A cellák ráadásul csak
`expect(tester.takeException(), isNull)`-t állítanak
(`onboarding_test.dart:176`, `block_mute_test.dart:297`,
`vision_one_cue_test.dart:283`), az ellipszis pedig pontosan az a mechanizmus,
ami a túlcsordulás-kivételt ELNYOMJA. Így az A3 bizonyítéka erre a három
képernyőre nem áll fenn.

**Elvárás:** a három variáns-harness telefon-szélességen fusson
(`tester.view.physicalSize = const Size(412, 915)`, `devicePixelRatio = 1.0`,
`addTearDown(tester.view.reset)`), és a mátrix futtatása után a MÉRT eredmény
kerüljön a §10-be. Ha ettől bármelyik cella pirosra vált, a **képernyőt** kell
javítani, nem a cellát (§0.0, A4).

### MAJOR-3 — a `followers_screen` betöltés-állapota nyers `CircularProgressIndicator` maradt

`lib/features/community/presentation/screens/followers_screen.dart:305` — a
diff csak a színt token-esítette (`valueColor: … colors.brand`).

A brief §5.2 ezt **szó szerint** nevesíti nem elfogadható gyengítésként:
„betöltés → a design-rendszer betöltés-komponense. **NEM elfogadható
gyengítés:** nyers `CircularProgressIndicator` … meghagyása". Az A2 minden
migrált képernyő üres/betöltés/hiba állapotára design-rendszer-komponenst
követel.

Itt nincs komponens-API akadály: az `SsSkeleton`
(`lib/core/design_system/components/feedback/ss_skeleton.dart`) csak
`width`/`height`-ot vár — se ARB-kulcs, se callback. Az implementer §10.1
indoklása az ÜRES állapotra vonatkozik, a betöltésre nem.

**Elvárás:** a footer-betöltés a design-rendszer betöltés-komponensére vált, és
egy cella állítja a típusát (`expect(find.byType(SsSkeleton), findsWidgets)`
vagy azzal egyenértékű) a `block_mute_test.dart`-ban.

## 3. MINOR leletek

### MINOR-1 — `ui_baseline_screenshot_test.dart` látensen törött a merge után

`test/ui/ui_baseline_screenshot_test.dart:197` a `const OnboardingScreen()`-t a
`_directCaptureApp` (`:212`, `theme: AppTheme.dark()`) alatt pumpolja, ami NEM
hordoz `SsColorScheme`/`SsTypography` kiterjesztést. A migrált képernyő
`SsButton`-ja mindkettőt `!`-tel oldja fel → null-check összeomlás. A cella ma
csak azért zöld, mert az egész teszt `skip: !_captureBaseline` (`:203`,
`bool.fromEnvironment('CAPTURE_UI_BASELINE')`). A fájl **ezen a kör
`allowed_paths`-án van**, a javítás egysoros (`theme: SsDarkTheme.data()`), és
pontosan az L593 (E15-R09 BLOCKER-1) hibaosztálya.

### MINOR-2 — a followers-avatár elveszti a kontrasztját az új kártyán

`followers_screen.dart:238`: `CircleAvatar(backgroundColor: …surfaceContainer)`
→ `colors.surfaceRaised`, miközben a sor egy `SsCard`-ba került, ami maga is
emelt felület. A kör SAJÁT újrafelvett goldenjéből mérve
(`test/ui/goldens/goldens/e13_r33_followers_compact.png`): kártya `#211F21`,
avatár `#191719` → **1,089:1** kontraszt (korábban 1,157:1 + eltérő
színárnyalat). A kezdőbetű olvasható marad, tehát nem információvesztés —
`surfaceSunken` vagy `border` viszont visszaadná az élt.

## 4. NOTE

1. **Mély `design_system` importok a MÓDOSÍTOTT teszt-fájlokban**
   (`onboarding_test.dart:4`, `block_mute_test.dart:22-23`,
   `vision_one_cue_test.dart:15-16`, `vision_setup_screen_test.dart:13-14`,
   `guitar_calibration_screen_test.dart:16-17`). MÉRVE: a
   `tool/check_architecture.dart:412-416` a barrel-szabályt csak `lib/`-re
   alkalmazza, és a minta a fában előzményes
   (`test/core/screen_size_guard_test.dart:42`) — tehát **nem szabálysértés**.
   A `public.dart` mindhárom típust exportálja, így a barrel-import
   következetesebb lenne. Nem blokkol.
2. **Token-igazítások** (`SizedBox(height: 14)` → `SsSpacing.space3` = 12;
   `BorderRadius.circular(4)` → `SsRadius.xs` = 6; a CTA magassága 54 →
   `SsSemantics.minimumInteractiveDimension` = 48). Mind dokumentált a
   §10.1-ben, mind kizárólag megjelenés.
3. **Akadálymentességi NYERESÉG:** az `SsSection` `Semantics(header: true)`-t
   ad a lépés-címekhez, amit a korábbi kézi `headlineSmall` `Text` nem adott.
   Érdemes a §10-ben nyereségként rögzíteni.
4. **A `vision_session_screen.dart:71-76` `colors.danger` árnyalata** additív (a
   szöveg VÁLTOZATLAN), tehát nem sérti az „állapotot ne csak szín jelezze"
   szabályt.

## 5. Amit MÉRTEM és rendben van (nem lelet)

- **Nincs elveszett kulcs.** Az öt képernyő `Key('…')`/`ValueKey('…')`
  literál-halmaza a diff előtt és után bitre azonos.
- **Nincs elveszett üzenet.** Az `l10n.*` hivatkozás-halmaz képernyőnként
  azonos; ARB-kulcs nem törlődött, ÚJ beégetett szöveg nem került be.
- **Nincs viselkedés-változás.** A `lib/` diffben az összes
  `onPressed`/`onChanged`/`setState`/`ref.*` sor ugyanaz a kifejezés
  újratördelve; `initState`/`dispose`/`mounted` sor nem változott; a letiltott
  állapot megmaradt (`state.canSave ? onSave : null`).
- **Nincs teszt-gyengítés.** A cellaszám fájlonként csak NŐTT (`block_mute`
  2→4, `onboarding` 5→7, `guitar_calibration` 4→6, `vision_setup` 8→10,
  `vision_one_cue` 5→7); `skip:` 0→0 minden érintett fájlban;
  `git diff | grep '^-.*expect('` ÜRES. A téma-hozzáadások mind
  `SsLightTheme.data()`/`SsDarkTheme.data()` (§0.0/R2).
- **Barrel-only a `lib/`-ben.** Mind az öt képernyő a `public.dart`-ot
  importálja; `lib/features/**` alatt nincs mély import.
- **Scope tiszta.** Minden változott útvonal az (R8-cal revideált)
  `allowed_paths`-on van; pontosan a felsorolt 8 golden PNG változott;
  `application/`/`domain/`/`data/`/`providers/` fájl nem változott; új
  `*ThemeScope` nincs.
- **A7 független újraszámolás:** `MIGRATED=85 TOTAL=96` → `88.542%` — egyezik a
  `docs/ui/migration-status.md:4` értékével. A szám nem „csak át lett írva".
- **A §10.4 hat indoklása mind HELYTÁLL** (külön-külön kimérve): az
  `SsPermissionState` `rationale`/`consequence` kötelező és nincs ARB a
  scope-ban; a beégetett `followers` szövegek a kör ELŐTT is ott voltak és a
  `hardcoded_string_guard_test.dart:18-23` `_scopeDirs`-e csak a
  `lib/core/design_system/**`-ot fedi; a `CommunityThemeScope` VALÓBAN
  teherhordó (`e13_r33_screens_golden_test.dart:569` `AppTheme.dark()` alatt
  pumpol, ami nem hordoz Ss-kiterjesztést); a `zoom_in`/`zoom_out`/`volume_off`/
  `block` ikonnevek VALÓBAN hiányoznak az `ss_icons.dart:86-93`
  katalógusból (a `resolveByName` látható hiányzó-glifára esne vissza); a
  `destructive` `SsButton` VALÓBAN kötelező `destructiveSemanticHint`-et vár
  (`ss_button.dart:36-41`); és pontosan 8 golden PNG változott.

## 6. Javító kör — a leletlista

| # | Súly | Teendő |
|---|---|---|
| MAJOR-1 | MAJOR | onboarding fő CTA: dokumentált-kivétel VAGY `didExceedMaxLines`-cella `hu` × `2.0`, telefon-szélességen |
| MAJOR-2 | MAJOR | a 3 A3-mátrix (`onboarding_test`, `block_mute_test`, `vision_one_cue_test`) telefon-szélességű felületen fusson |
| MAJOR-3 | MAJOR | `followers_screen` betöltés-állapota design-rendszer-komponensre, típus-cellával |
| MINOR-1 | MINOR | `ui_baseline_screenshot_test.dart` `_directCaptureApp` témája `SsDarkTheme.data()` |
| MINOR-2 | MINOR | followers-avatár kontraszt (`surfaceSunken`/`border`) — opcionális, ha a golden újrafelvétele nem nő túl |

A javító kör ugyanazon a branchen, ugyanazzal a motorral (`sonnet-impl`) megy; a
munkát a branchre kell commitolni. A javítás után a §7 gate ÚJRA fut, a golden
PNG-k szükség szerint újrafelvéve (ADR 0426, `tools/golden-x86.sh record`), és a
teljes CI-kapu (Full Gate + Router CI) az ÚJ merge SHA-n zöld kell legyen.
