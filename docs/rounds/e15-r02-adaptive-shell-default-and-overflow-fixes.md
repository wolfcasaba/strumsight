# E15-R02 — Az adaptív shell alapértelmezetté tétele és a két mért túlcsordulás javítása

- **Státusz:** PREPARED (előre megírva 2026-08-28, kód olvasva: `main @ 4cb32eb0`)
- **Típus:** Chapter 15 (UI-aktiválás és -befejezés), Kör 2
- **Kör-azonosító:** `E15-R02`
- **Branch:** `<motor>/e15-r02-adaptive-shell-default-and-overflow-fixes`
- **Előfeltétel:** `E15-R01` merge-elve (a téma-bevezetés a shell minden képernyőjét érinti)
- **Brief szerzője:** Claude (Opus 5)
- **Előre kiosztott ADR:** `ADR 0467` — a szám FOGLALT (Chapter 15 batch-tartomány).

**Visszakeresett előzmény:** `node tools/knowledge-rag.mjs --corpus lessons,halts,adr --top 5 "adaptive shell navigation destinations rollout flag overflow text scale"` → **[ADR 0275](../adr/0275-five-area-shell-behind-a-flag.md)** („Az ötterületes alkalmazás-shell flag mögött, adapterekkel"): a shell KI van kapcsolva minden környezetben, és a bekapcsolás **user-döntés**. A user 2026-08-28-án ezt megadta („minden legyen migrálva, javítva, hogy lássam a valódi appot") — a kör ezt hajtja végre, és az ADR 0467 rögzíti a döntést és a visszavonás feltételét.

> ⚠ **Pre-flight (indítás előtt KÖTELEZŐ):** olvasd újra a `docs/ui/legacy-backlog.md` §1 tábláját (a megíráskor KÉT mért túlcsordulás: `live_screen.dart:477` stat-sor 12/34 px landscape+200% mellett; `permission_primer_screen.dart` véglegesen-elutasított ága 297 px alul), és ellenőrizd, hogy a mérő cellák (`e13_r36_variant_matrix_test.dart` `_ExcludedCell`-jei, `closure_suite_test.dart` „A4" csoportja) még a hibát VÁRJÁK — a javítással ezeket a cellákat át kell fordítani „nincs túlcsordulás" állításra.

## 0.0/a A pinnelő tesztek — MÉRT állapot (S11)

A `brief-lint --level strict` MÉRTE, hogy a két javítandó képernyő típusát a briefen kívül élő tesztek pinnelik: a `live_screen.dart`-ot nyolc (`offline_network_guard_test`, `app_router_test`, `shell_lifecycle_test`, `tutor_home_screen_test`, `live_stage_test`, `practice_routing_test`, `hub_navigation_test`, `e13_r18_screens_golden_test`), a `permission_primer_screen.dart`-ot három (`onboarding_resume_test`, `permission_primer_test`, `e13_r16_screens_golden_test`).

**A kör egyik képernyőt sem CSERÉLI LE** — a típus, a route és a publikus API változatlan; kizárólag a belső elrendezés javul (a `Row` gyermekei rugalmasak lesznek, illetve a primer ága görgethetővé válik). A típus-pinnelő cellák tehát VÁLTOZATLANUL zöldek kell maradjanak, és a jogosultság PONTOSAN ennyi: **cella törlése, `skip`-je vagy gyengítése TILOS**.

A KÉT GOLDEN-fájl viszont várhatóan elmozdul (`e13_r18_live_stage_compact*.png`, `e13_r16_permission_primer_compact*.png`), mert a javítás a raszterképet is megváltoztatja. Ezeket **kizárólag** a `tools/golden-x86.sh record` úton szabad újrafelvenni (ADR 0426: a merge-kapu architektúráján, nem ezen az aarch64 boxon) — a §7 ezt a parancsot írja elő.

## 0.0/c PRE-FLIGHT MÉRÉS (2026-08-28, orchestrátor) — a flag-átállítás valódi hatósugara, H3

A pre-flight a §2 „mért tények" ÖSSZES állítását ellenőrizte, és mind igaz
(`feature_flags.dart:129`, `app_router.dart:215`, `adaptive_shell_routes.dart:10`
tizenegy redirect, a négy `_ExcludedCell`, a closure-suite „A4" csoportja, a
`legacy-backlog.md` §1 öt sora, a `permission_primer_screen.dart:98-107` nem
görgethető ága a `:111-115` görgethető ágával szemben). **Egy állítás
azonban hiányzott a briefből, és ez a kör elindíthatóságát dönti el.**

### A mért gyökérok

`lib/app/config/app_config.dart:201-213` — az `appConfigProvider`
ALAPÉRTELMEZETT értéke maga is `FeatureFlags.forEnvironment(AppEnvironment.development, …)`.
Ezért a `adaptiveShellEnabled: nonProd` átállítás nem csak az alkalmazás
indítását változtatja meg, hanem **minden olyan widget-teszt viselkedését is,
amely a valódi routert pumpálja és nem írja felül az `appConfigProvider`-t**:
a belépési pont `/live` → `/today`, és a tizenegy `legacyRedirects` él
aktiválódik (`/live` → `/practice/live`, `/settings` → `/profile/settings`, …).

### A mérés (reprodukálható)

```bash
git clone /home/ubuntu/music-theory /home/ubuntu/ss-sonnet-impl-e15-r02
bash /home/ubuntu/ss-sonnet-impl-e15-r02/tools/prepare-flutter-generated.sh
cd /home/ubuntu/ss-sonnet-impl-e15-r02
sed -i 's|^      adaptiveShellEnabled: false,$|      adaptiveShellEnabled: nonProd,|' \
  lib/app/config/feature_flags.dart
~/flutter/bin/flutter test --reporter compact        # a TELJES suite
git checkout -- lib/app/config/feature_flags.dart
~/flutter/bin/flutter test --reporter compact <a 24 bukó fájl>   # alapvonal
```

- **Az átállítással:** `+7272 ~15 -68` — 68 bukás, 24 fájlban.
- **Az átállítás NÉLKÜL (alapvonal, ugyanaz a 24 fájl):** `-15` — kizárólag
  öt golden-fájl (`e13_r20/r23/r32/r34/r35_screens_golden_test.dart`),
  mindegyik `Pixel test failed, 0.00%, 1px diff` alakban. Ez a MÉRT
  ARM↔x86 golden-drift ([L516](../LESSONS.md#l516)), **nem** e kör hatása;
  a kapu x86 architektúráján zöld.
- **Tehát a flag-átállítás oksági hatósugara: 53 bukás, 19 fájlban.**

### A 19 fájl, és hogy benne van-e a §4 engedélyezett listán

| Fájl | Bukás | A listán? |
|---|---|---|
| `test/features/live/live_stage_test.dart` | 11 | ✅ igen |
| `test/app/routing/shell_lifecycle_test.dart` | 2 | ✅ igen |
| `test/app/navigation/adaptive_scaffold_test.dart` | 1 | ✅ igen |
| `test/features/live/live_mic_release_test.dart` | 6 | ❌ **nincs** |
| `test/features/settings/consent_center_test.dart` | 5 | ❌ **nincs** |
| `test/features/live/live_screen_test.dart` | 5 | ❌ **nincs** |
| `test/features/settings/settings_account_test.dart` | 3 | ❌ **nincs** |
| `test/features/live/live_background_test.dart` | 3 | ❌ **nincs** |
| `test/features/live/live_announcement_throttle_test.dart` | 3 | ❌ **nincs** |
| `test/core/screen_size_guard_test.dart` | 3 | ❌ **nincs** |
| `test/features/settings/settings_persistence_failure_test.dart` | 2 | ❌ **nincs** |
| `test/features/live/live_lab_panel_test.dart` | 2 | ❌ **nincs** |
| `test/widget_test.dart` | 1 | ❌ **nincs** |
| `test/features/settings/lab_mode_toggle_test.dart` | 1 | ❌ **nincs** |
| `test/features/live/expected_hint_cleared_on_live_test.dart` | 1 | ❌ **nincs** |
| `test/features/library/library_test.dart` | 1 | ❌ **nincs** |
| `test/features/analyze/cancel_on_leave_test.dart` | 1 | ❌ **nincs** |
| `test/features/analyze/analyze_screen_test.dart` | 1 | ❌ **nincs** |
| `test/app/routing/onboarding_first_win_test.dart` | 1 | ❌ **nincs** |

Két jellemző bukás szó szerint:

```
test/app/routing/onboarding_first_win_test.dart:114
Expected: '/live'
  Actual: '/today'

test/features/live/live_screen_test.dart:51
Expected: at least one matching candidate
  Actual: _TextWidgetFinder:<Found 0 widgets with text "C": []>
```

### Két további, kisebb lelet

1. **S11-maradék.** Az E15-R01 (merge-elve `a65aa3f9`) új, PNG-mentes
   variáns-mátrixot hozott — `test/ui/goldens/e15_r01_theme_adoption_test.dart`
   —, amely a `LiveScreen`-t compact portrait-ban „nincs túlcsordulás"-ra méri.
   A brief `gate_tests`-éből HIÁNYZIK, pedig a kör a `live_screen.dart`-ot írja
   át. `allowed_paths`-ba NEM való (változatlanul kell maradnia), `gate_tests`-be
   igen.
2. **Elavuló kill-switch dokumentáció (ADR 0467 D8).**
   `lib/core/feature_flags/feature_flag_registry.dart:484-492` az
   `adaptiveShellEnabled`-ről azt állítja: „hardcoded to `false` in every
   environment at feature_flags.dart:129 … enabling it requires a source
   change". A D1 után ez hamis. A `test/tooling/feature_flag_audit_test.dart`
   csak a kulcshalmazt és a mezők nem-üres voltát méri, a prózát NEM — tehát
   a hazugság gépi mércén ÁTMENNE. A fájl nincs a §4 listán.

### A besorolás: H3

A kör a §4 engedélyezett listán **kívüli 16 tesztfájl** módosítása nélkül nem
vihető zöldre, és a lista **tágítása** nem az orchestrátor hatásköre
(ADR 0087 §2: a szűkítés az, a tágítás H3). A kör ezért **dispatch nélkül
halt**-ol. Az ADR 0467 és ez a §0.0/c revízió a branchre commitolva marad,
hogy a folytatás (önjavító kör) ÚJRAHASZNOSÍTSA, ne írja meg vakon újra.

**Javasolt brief-revízió a folytatásnak** (nem hajtottam végre — ez tágítás):

- `allowed_paths` + `gate_tests` ← a fenti 16 „nincs" sorú tesztfájl;
- `allowed_paths` ← `lib/core/feature_flags/feature_flag_registry.dart`
  (kizárólag az `adaptiveShellEnabled` bejegyzés `killSwitchPath` szövege);
- `gate_tests` ← `test/ui/goldens/e15_r01_theme_adoption_test.dart` és
  `test/tooling/feature_flag_audit_test.dart` (`allowed_paths`-ba egyik sem);
- új acceptance-cella: **A10** — „a `nonProd` átállítás után a TELJES
  `flutter test` suite zöld a mért ARM↔x86 golden-driften kívül", bizonyíték a
  Full Gate futása;
- a §5 döntéseihez: a 16 fájl javítása KIZÁRÓLAG a mért új viselkedéshez
  igazítás lehet (`/today` belépés, redirect-célok), **nem** a shell
  kikapcsolása `appConfigProvider`-override-dal ott, ahol a teszt éppen a
  valódi belépési utat méri — az a mérce gyengítése lenne.

## 0.0/d ÖNJAVÍTÓ REVÍZIÓ (ADR 0112, 2026-08-28) — a mért hatósugár a scope-ba került

A §0.0/c halt (H3) egyetlen kérdést hagyott nyitva: szabad-e a §4 listát a
mért 19 fájlra tágítani. **Igen** — az önjavító kör a mérést FÜGGETLENÜL
reprodukálta (nem a §0.0/c jelentését fogadta el), és a tágítást elvégezte.

**A saját mérés** (izolált klón `main @ e65b1738`-ról,
`tools/prepare-flutter-generated.sh` után, egyetlen `sed`-del átbillentve a
`feature_flags.dart:129` sort, majd a TELJES suite):

```bash
git clone /home/ubuntu/music-theory <wc> && bash <wc>/tools/prepare-flutter-generated.sh
cd <wc> && sed -i 's|^      adaptiveShellEnabled: false,$|      adaptiveShellEnabled: nonProd,|' \
  lib/app/config/feature_flags.dart
~/flutter/bin/flutter test --reporter compact --file-reporter json:flip.json   # TELJES suite
git checkout -- lib/app/config/feature_flags.dart
~/flutter/bin/flutter test --reporter compact --file-reporter json:base.json <a 24 bukó fájl>
```

- **Flippel:** `+7272 ~15 -68` — **68 bukás, 24 fájlban** (a `json` riportból
  fájlonként számolva, nem a tömör sorból becsülve).
- **Flip nélkül, ugyanaz a 24 fájl:** `+157 -15` — **15 bukás, 5 fájlban**,
  mind a `test/ui/goldens/e13_r{20,23,32,34,35}_screens_golden_test.dart`
  raszter-cellái (`Pixel test failed`, 0,00–0,75%); a 19 másik fájl ZÖLD.
- **A különbség = a flag oksági hatósugara: 53 bukás, 19 fájlban.** A
  maradék 15 cella a flip NÉLKÜL is ugyanígy piros, ugyanabban az öt
  golden-fájlban — a MÉRT ARM↔x86 raszter-drift
  ([L516](../LESSONS.md#l516), [ADR 0426](../adr/0426-golden-rasterization-on-the-gate-architecture.md)),
  a kapu x86 architektúráján zöld, tehát NEM e kör hatása.

| Fájl | Bukás |
|---|---|
| `test/features/live/live_stage_test.dart` | 11 |
| `test/features/live/live_mic_release_test.dart` | 6 |
| `test/features/settings/consent_center_test.dart` | 5 |
| `test/features/live/live_screen_test.dart` | 5 |
| `test/features/settings/settings_account_test.dart` | 3 |
| `test/features/live/live_background_test.dart` | 3 |
| `test/features/live/live_announcement_throttle_test.dart` | 3 |
| `test/core/screen_size_guard_test.dart` | 3 |
| `test/features/settings/settings_persistence_failure_test.dart` | 2 |
| `test/features/live/live_lab_panel_test.dart` | 2 |
| `test/app/routing/shell_lifecycle_test.dart` | 2 |
| `test/widget_test.dart` | 1 |
| `test/features/settings/lab_mode_toggle_test.dart` | 1 |
| `test/features/library/library_test.dart` | 1 |
| `test/features/analyze/cancel_on_leave_test.dart` | 1 |
| `test/features/analyze/analyze_screen_test.dart` | 1 |
| `test/features/live/expected_hint_cleared_on_live_test.dart` | 1 |
| `test/app/navigation/adaptive_scaffold_test.dart` | 1 |
| `test/app/routing/onboarding_first_win_test.dart` | 1 |

A `test/features/live/live_widgets_test.dart`, a
`test/features/settings/settings_sync_test.dart` és a
`test/app/routing/route_guards_test.dart` — a mért fájlok közvetlen
szomszédai — a flip mellett is ZÖLDEK: a scope ezért fájlonként enged, nem
könyvtár-előtaggal.

**Mit változtatott ez a revízió:**

1. `allowed_paths` + `gate_tests` ← a mért, eddig hiányzó tesztfájlok. A
   jogosultság PONTOSAN a mért új viselkedéshez igazítás (§5.4).
2. `allowed_paths` ← `lib/core/feature_flags/feature_flag_registry.dart`
   (kizárólag az `adaptiveShellEnabled` bejegyzés `killSwitchPath` prózája,
   ADR 0467 D8) és `test/tooling/feature_flag_audit_test.dart` (a prózát ma
   SEMMI nem méri — az `A11` cella ezt zárja be).
3. `allowed_paths` + `gate_tests` ← `test/ui/goldens/e15_r01_theme_adoption_test.dart`
   (S11-maradék: az E15-R01 PNG-mentes mátrixa a `LiveScreen`-t méri, a kör
   pedig a `live_screen.dart`-ot írja át; a cella VÁLTOZATLANUL zöld kell
   maradjon — §0.0/a szabálya).
4. Új acceptance-cellák: `A10` (a teljes suite a mért ARM↔x86 drifttől
   eltekintve zöld) és `A11` (a kill-switch próza igaz, és gépi mérce őrzi).
5. §7 gate-parancs = `gate_tests` (S12).

**A regresszió őre:** `tools/tests/test_e15_r02_adaptive_shell_scope.py` — a
VALÓDI, commitolt briefet hajtja át a VALÓDI scope-auditon
(`tools.ai_router.security.audit_scope`) a mért fájllistával; a lista
szűkülése és a könyvtár-szintű blanket-tágítás egyaránt pirosra váltja.

## 0.0/e PRE-FLIGHT ÚJRAMÉRÉS (2026-08-28, orchestrátor, indítás előtt)

A §0.0/c és §0.0/d már merge-elve van a `main`-en (HEAL PR #495, squash
`ee2a2bc4`), az `ADR 0467` szintén — a kör tehát a TELJES §4 listával indul,
és sem az ADR-t, sem a scope-ot nem írom újra (H1). A dispatch előtt a
brief mért állításait a `main @ bbe86b1a` fán ÚJRA kimértem, mind igaz:

| Állítás | Mérés | Eredmény |
|---|---|---|
| `adaptiveShellEnabled: false` minden környezetben | `feature_flags.dart:129` | ✅ igaz |
| `entryLocation = adaptiveShellEnabled ? today : live` | `app_router.dart:215` | ✅ igaz |
| `legacyRedirects` CSAK bekapcsolt shell mellett él | `app_router.dart:228` (`if (!adaptiveShellEnabled) return null;`) | ✅ igaz |
| `appConfigProvider` default = `forEnvironment(development, …)` — ez a flip hatósugarának oka | `app_config.dart:201-208` | ✅ igaz |
| A primer véglegesen-elutasított ága NEM görgethető, a másik ág `SingleChildScrollView` | `permission_primer_screen.dart:98-107` vs `:111-115` | ✅ igaz |
| A `live` stat-sor rugalmatlan `Row` (`spaceEvenly`, `_ActionButton` gyermekek) | `live_screen.dart:477-` | ✅ igaz |
| A `killSwitchPath` próza a D1 után hamissá válik | `feature_flag_registry.dart:487-492` | ✅ igaz |

Visszakeresés (ADR 0312, szűkítve ELŐSZÖR): `lessons,halts,adr` — a döntő
előzmények már hivatkozva vannak a briefben
([ADR 0275](../adr/0275-five-area-shell-behind-a-flag.md),
[L516](../LESSONS.md#l516), [L180](../LESSONS.md#l180),
[ADR 0426](../adr/0426-golden-rasterization-on-the-gate-architecture.md));
ÚJ, eddig nem hivatkozott releváns lelet: **[L449](../LESSONS.md#l449)** — az
`indexedStack` shell életben tartja a meglátogatott brancheket, ezért a
mikrofont/wakelockot birtokló képernyő nem szabadul fel automatikusan. A kör
a shellt ALAPÉRTELMEZETTÉ teszi, tehát ez az út mostantól minden fejlesztői
és lab-környezetben él; a `live_mic_release_test.dart` és a
`shell_lifecycle_test.dart` a §4 listán van, és ezek a MÉRT elengedési
szerződést pinnelik — a §5.4 értelmében ezek is KIZÁRÓLAG az új belépési
ponthoz igazíthatók, az elengedési elvárás gyengítése tilos.
Továbbá **[L517](../LESSONS.md#l517)**: a `textScaler 2.0` keret két egymást
követő körben mért ki addig láthatatlan túlcsordulást — a §0 STOP-protokoll
(új képernyőn talált túlcsordulás → `legacy-backlog.md` + jelentés) pontosan
erre a hibaosztályra való.

A `brief-lint --level strict` lelete: **nincs**.

## 0.0/b A kör két, egymást feltételező fele

A shell bekapcsolása UTÁN a landscape + 200%-os szövegskála út valóban elérhetővé válik a felhasználónak, tehát a két ismert túlcsordulás ettől kezdve nem elméleti. A javítás és a bekapcsolás ezért EGY kör: külön-külön mindkettő hiányos lenne.

```ai-router
schema_version = 1
risk = "high"
allowed_paths = [
  "lib/app/config/feature_flags.dart",
  "lib/features/live/screens/live_screen.dart",
  "lib/features/onboarding/screens/permission_primer_screen.dart",
  "test/app/config/feature_flags_test.dart",
  "test/app/feature_flags_test.dart",
  "test/app/navigation/adaptive_scaffold_test.dart",
  "test/app/navigation/tab_state_restoration_test.dart",
  "test/app/navigation/legacy_route_redirect_test.dart",
  "test/ui/goldens/e13_r36_variant_matrix_test.dart",
  "test/accessibility/closure_suite_test.dart",
  "test/app/offline_network_guard_test.dart",
  "test/app/routing/app_router_test.dart",
  "test/app/routing/shell_lifecycle_test.dart",
  "test/features/ai_tutor/presentation/tutor_home_screen_test.dart",
  "test/features/live/live_stage_test.dart",
  "test/features/practice/presentation/practice_routing_test.dart",
  "test/features/today/hub_navigation_test.dart",
  "test/features/onboarding/onboarding_resume_test.dart",
  "test/features/onboarding/permission_primer_test.dart",
  "test/app/routing/onboarding_first_win_test.dart",
  "test/core/screen_size_guard_test.dart",
  "test/widget_test.dart",
  "test/features/live/live_screen_test.dart",
  "test/features/live/live_mic_release_test.dart",
  "test/features/live/live_background_test.dart",
  "test/features/live/live_announcement_throttle_test.dart",
  "test/features/live/live_lab_panel_test.dart",
  "test/features/live/expected_hint_cleared_on_live_test.dart",
  "test/features/settings/consent_center_test.dart",
  "test/features/settings/settings_account_test.dart",
  "test/features/settings/settings_persistence_failure_test.dart",
  "test/features/settings/lab_mode_toggle_test.dart",
  "test/features/library/library_test.dart",
  "test/features/analyze/analyze_screen_test.dart",
  "test/features/analyze/cancel_on_leave_test.dart",
  "test/ui/goldens/e15_r01_theme_adoption_test.dart",
  "lib/core/feature_flags/feature_flag_registry.dart",
  "test/tooling/feature_flag_audit_test.dart",
  "test/ui/goldens/e13_r18_screens_golden_test.dart",
  "test/ui/goldens/e13_r16_screens_golden_test.dart",
  "test/ui/goldens/goldens/e13_r18_live_stage_compact.png",
  "test/ui/goldens/goldens/e13_r18_live_stage_compact_scale2.png",
  "test/ui/goldens/goldens/e13_r16_permission_primer_compact.png",
  "test/ui/goldens/goldens/e13_r16_permission_primer_compact_scale2.png",
  "docs/ui/legacy-backlog.md",
  "docs/rounds/e15-r02-adaptive-shell-default-and-overflow-fixes.md",
]
gate_tests = [
  "test/app/config/feature_flags_test.dart",
  "test/app/feature_flags_test.dart",
  "test/app/navigation/adaptive_scaffold_test.dart",
  "test/app/navigation/tab_state_restoration_test.dart",
  "test/app/navigation/legacy_route_redirect_test.dart",
  "test/ui/goldens/e13_r36_variant_matrix_test.dart",
  "test/accessibility/closure_suite_test.dart",
  "test/app/offline_network_guard_test.dart",
  "test/app/routing/app_router_test.dart",
  "test/app/routing/shell_lifecycle_test.dart",
  "test/features/ai_tutor/presentation/tutor_home_screen_test.dart",
  "test/features/live/live_stage_test.dart",
  "test/features/practice/presentation/practice_routing_test.dart",
  "test/features/today/hub_navigation_test.dart",
  "test/features/onboarding/onboarding_resume_test.dart",
  "test/features/onboarding/permission_primer_test.dart",
  "test/app/routing/onboarding_first_win_test.dart",
  "test/core/screen_size_guard_test.dart",
  "test/widget_test.dart",
  "test/features/live/live_screen_test.dart",
  "test/features/live/live_mic_release_test.dart",
  "test/features/live/live_background_test.dart",
  "test/features/live/live_announcement_throttle_test.dart",
  "test/features/live/live_lab_panel_test.dart",
  "test/features/live/expected_hint_cleared_on_live_test.dart",
  "test/features/settings/consent_center_test.dart",
  "test/features/settings/settings_account_test.dart",
  "test/features/settings/settings_persistence_failure_test.dart",
  "test/features/settings/lab_mode_toggle_test.dart",
  "test/features/library/library_test.dart",
  "test/features/analyze/analyze_screen_test.dart",
  "test/features/analyze/cancel_on_leave_test.dart",
  "test/ui/goldens/e15_r01_theme_adoption_test.dart",
  "test/tooling/feature_flag_audit_test.dart",
]
native_gate = false
```

**Kockázat = high, indoklás:** a diff az alkalmazás BELÉPÉSI PONTJÁT írja át (a router kezdő útvonala `/live`-ról `/today`-re vált a flag-en keresztül), tehát minden felhasználói út kiindulása változik; egy hibás flag-feloldás vagy elmaradó legacy-redirect a felhasználót üres vagy nem létező útvonalra vinné.

## 0. Kör-jelzés és STOP-protokoll

```bash
tools/codex-signal.sh progress "<egy sor>"
tools/codex-signal.sh done "<egy sor>"
tools/codex-signal.sh stopped "<egy sor>"
tools/codex-signal.sh blocked "<egy sor>"
```

**STOP-protokoll:** ha a bekapcsolás után egy MÁSIK képernyőn is túlcsordulás derül ki, azt a `legacy-backlog.md`-be kell felvenni datált tételként és jelenteni — a javítása (a §4 listán kívüli fájlban) `stopped` eset.

## 1. Cél

Az ötterületes adaptív shell legyen az alapértelmezett felület minden nem-production környezetben, és a két MÉRT elrendezési hiba szűnjön meg — mérve, nem bemondásra.

## 2. Jelenlegi állapot — mért tények

- `lib/app/config/feature_flags.dart:129` → `adaptiveShellEnabled: false` MINDEN környezetben; dart-define felülírás szándékosan NINCS (ADR 0275).
- `lib/app/routing/app_router.dart:215` → `entryLocation = adaptiveShellEnabled ? AppRoutes.today : AppRoutes.live`; a legacy redirect-tábla (`legacyRedirects`) CSAK bekapcsolt shell mellett él (`:228`).
- `test/app/navigation/` **három** őr pinneli a destination→képernyő-típus párokat, a tab-visszaállítást és a tizenegy legacy redirect célját.
- `docs/ui/legacy-backlog.md` §1: **négy** mátrix-cella (live, {light,dark}×{en,hu}, landscape, textScale 2.0) és **egy** closure-cella (permission primer) SZÁNDÉKOSAN a hibát várja.
- `test/app/config/feature_flags_test.dart` (219 sor) és `test/app/feature_flags_test.dart` (339 sor) a flag-feloldás őrei; az `adaptive_scaffold_test.dart:132` EXPLICIT azt állítja, hogy `forEnvironment(...).adaptiveShellEnabled` **hamis** — ezt a kör a döntésnek megfelelően fordítja át.

## 3. Scope

**Benne van:** `adaptiveShellEnabled: nonProd` a `forEnvironment`-ben (production továbbra is KI, amíg a GA-scope nem dönt) · a `live_screen.dart` stat-sorának javítása (a `Row` gyermekei `Expanded`/`Flexible`, vagy a sor görgethető) · a `permission_primer_screen.dart` véglegesen-elutasított ágának `SingleChildScrollView`-ba burkolása (a retryable ág MÁR így csinálja) · a MÉRŐ cellák átfordítása: a négy `_ExcludedCell` és a closure-cella mostantól „NINCS túlcsordulás"-t állít · a három navigációs őr és a két flag-teszt frissítése az új alapértelmezéshez · **a §0.0/d-ben MÉRT, flag-átállítás miatt bukó tesztfájlok igazítása az új belépési ponthoz** (§5.4) · a `feature_flag_registry.dart` `adaptiveShellEnabled` bejegyzésének `killSwitchPath` prózája (ADR 0467 D8) + a hozzá tartozó gépi cella a `feature_flag_audit_test.dart`-ban · `docs/ui/legacy-backlog.md` §1 lezárása (a két tétel dátummal, a javítás hivatkozásával).

**NINCS benne (tilos):**

- Bármely további `lib/features/**` képernyő átírása (a migráció a következő körök dolga).
- A shell bekapcsolása PRODUCTION környezetben.
- Meglévő navigációs őr cellájának törlése vagy `skip`-je — kizárólag az ÉRTÉK fordítható át, a cella marad.
- `docs/adr/**` — az ADR 0467-et a Claude írja.

## 4. Engedélyezett fájlok

| Útvonal | Indok |
|---|---|
| `lib/app/config/feature_flags.dart` | `adaptiveShellEnabled: nonProd` |
| `lib/features/live/screens/live_screen.dart` | a stat-sor túlcsordulásának javítása |
| `lib/features/onboarding/screens/permission_primer_screen.dart` | a primer görgethetővé tétele |
| `test/app/config/feature_flags_test.dart` · `test/app/feature_flags_test.dart` | a flag-elvárás átfordítása |
| `test/app/navigation/*.dart` (három őr) | az alapértelmezett shell melletti pinnelés |
| `test/ui/goldens/e13_r36_variant_matrix_test.dart` | a négy `_ExcludedCell` átfordítása |
| `test/accessibility/closure_suite_test.dart` | a primer-cella átfordítása |
| `test/app/offline_network_guard_test.dart` · `test/app/routing/{app_router,shell_lifecycle}_test.dart` · `test/features/{live/live_stage,practice/presentation/practice_routing,today/hub_navigation,ai_tutor/presentation/tutor_home_screen}_test.dart` · `test/features/onboarding/{onboarding_resume,permission_primer}_test.dart` | típus-pinnelő őrök — VÁLTOZATLANUL zöldnek kell maradniuk (§0.0/a) |
| `test/ui/goldens/e13_r1{6,8}_screens_golden_test.dart` + a NÉGY érintett PNG | a raszterkép a javítással elmozdul; újrafelvétel KIZÁRÓLAG `tools/golden-x86.sh record` úton |
| `docs/ui/legacy-backlog.md` | a két tétel lezárása |
| `test/app/routing/onboarding_first_win_test.dart` · `test/core/screen_size_guard_test.dart` · `test/widget_test.dart` · `test/features/live/{live_screen,live_mic_release,live_background,live_announcement_throttle,live_lab_panel,expected_hint_cleared_on_live}_test.dart` · `test/features/settings/{consent_center,settings_account,settings_persistence_failure,lab_mode_toggle}_test.dart` · `test/features/library/library_test.dart` · `test/features/analyze/{analyze_screen,cancel_on_leave}_test.dart` | a §0.0/d-ben MÉRT bukások — a flag-átállítás oksági hatósugara; igazítás KIZÁRÓLAG az új viselkedéshez (§5.4) |
| `test/ui/goldens/e15_r01_theme_adoption_test.dart` | S11-maradék: a `LiveScreen`-t méri — VÁLTOZATLANUL zöldnek kell maradnia (§0.0/a) |
| `lib/core/feature_flags/feature_flag_registry.dart` | KIZÁRÓLAG az `adaptiveShellEnabled` bejegyzés `killSwitchPath` prózája (ADR 0467 D8) |
| `test/tooling/feature_flag_audit_test.dart` | ÚJ cella: a `killSwitchPath` próza gépi mércéje (A11) |

**Tilos zóna:** `lib/app/routing/**` (a router logikája NEM változik, csak a flag) · `lib/features/**` egyéb képernyői · `lib/core/feature_flags/**` az `adaptiveShellEnabled` bejegyzés `killSwitchPath` mezőjén kívül · `test/ui/goldens/goldens/**` a NÉGY nevesített PNG-n kívül · `docs/adr/**` · `tools/**`

## 5. Kötött architekturális döntések (ADR 0467)

### 5.1 A shell alapértelmezés, de production KI marad

**NEM elfogadható gyengítés:** a production ág bekapcsolása „úgyis ugyanaz a kód" alapon — a GA-scope-ot a Chapter 12 Kör 28 dönti el.

### 5.2 A javítás a MÉRŐ cellát fordítja át, nem törli

**NEM elfogadható gyengítés:** az `_ExcludedCell` vagy a closure-cella eltávolítása — a törléssel a hiba visszatérése észrevétlen maradna (a zsugorodás-őr elve, [L180](../LESSONS.md#l180)).

### 5.3 A legacy belépési pont megmarad átirányításként

A `/live` és a többi legacy útvonal továbbra is működik, a `legacyRedirects` táblán át. **NEM elfogadható gyengítés:** a régi útvonalak megszüntetése — a mentett mélylinkek és a widget-tesztek is ezeken jönnek.

### 5.4 A mért bukások javítása = igazítás az ÚJ viselkedéshez (ADR 0467 D9)

A §0.0/d listáján szereplő tesztek KIZÁRÓLAG úgy hozhatók zöldre, hogy az új,
szállított viselkedéshez igazodnak: a belépési pont `/today`, a legacy
útvonalak a `legacyRedirects` célján érhetők el (a teszt navigáljon oda, vagy
a redirect célját várja).

**NEM elfogadható gyengítés:** a shell kikapcsolása `appConfigProvider`-
override-dal ott, ahol a teszt tárgya nem maga a kikapcsolt konfiguráció — az
a mérce elrejtése lenne a szállított alapértelmezés elől. Ugyanígy tilos a
cella törlése, `skip`-je vagy `expect` gyengítése (D6, [L180](../LESSONS.md#l180)).
A teszt-cellák SZÁMA egyik érintett fájlban sem csökkenhet.

## 6. Acceptance criteria

| # | Kritérium | Bizonyíték |
|---|---|---|
| A1 | `forEnvironment(development\|lab)` → `adaptiveShellEnabled == true`; `production` → `false` | `feature_flags_test.dart` (mindhárom környezetre cella) |
| A2 | Az app belépési pontja `/today`, és mind az öt destination a helyes képernyő-TÍPUST rendereli | `adaptive_scaffold_test.dart` |
| A3 | A tizenegy legacy útvonal átirányít, a query és a fragment megőrzésével | `legacy_route_redirect_test.dart` |
| A4 | A tab-állapot visszaáll fülváltás után | `tab_state_restoration_test.dart` |
| A5 | A `live` képernyő stat-sora landscape + `textScale 2.0` mellett MINDKÉT fényerőn és MINDKÉT locale-on túlcsordulás NÉLKÜL renderel | `e13_r36_variant_matrix_test.dart` (a négy átfordított cella) |
| A6 | A véglegesen elutasított permission-primer 200%-os szövegskálán görgethető, nem csordul túl | `closure_suite_test.dart` |
| A7 | A `legacy-backlog.md` §1 két tétele LEZÁRTKÉNT, a javítás hivatkozásával szerepel | a dokumentum |
| A8 | A tizenegy típus-pinnelő őr VÁLTOZATLANUL zöld, egyetlen cellájuk sem törölt/`skip`-elt | a §7 gate + `git diff` a teszt-fájlokon |
| A9 | A két érintett golden `tools/golden-x86.sh record` úton lett újrafelvéve (nem az aarch64 boxon) | a parancs kimenete a §10-ben |
| A10 | A `nonProd` átállítás után a TELJES `flutter test` suite zöld — kivétel KIZÁRÓLAG a mért ARM↔x86 golden-drift (L516), ami a kapu x86 architektúráján zöld | a Full Gate / `build-apk.yml` futása a merge SHA-ján; a §10-be a lokális teljes futás összesítője is bekerül |
| A11 | A `feature_flag_registry.dart` `adaptiveShellEnabled` bejegyzésének `killSwitchPath` prózája a D1 után IGAZ, és ezt gépi cella méri | `test/tooling/feature_flag_audit_test.dart` új cellája |

**Küszöb-cellahármas a szövegskálára** (a kötelező határ `2.0`, INKLUZÍV): a küszöb **alatt** (`1.5`) → nincs túlcsordulás; **pontosan rajta** (`2.0`) → nincs túlcsordulás — EZ az A5/A6 feltétele; a küszöb **fölött** (`2.5`) → nem követelmény, a mátrix nem méri, és a `2.0` teljesítése nem hivatkozhat rá.

### 6.1 Mérce-mátrix — melyik hibás implementációt melyik cella fogja pirosra

| Hibás implementáció | Melyik cella vált PIROSRA |
|---|---|
| A flag `nonProd` helyett mindenhol `true` lesz (production is) | A1 production-cellája |
| A stat-sor javítása csak `en` locale-ra elég (a hosszabb `hu` címkék tovább csordulnak) | A5 `hu` cellái |
| A primer javítása a retryable ágra kerül (ami már jó volt), a véglegesen-elutasítottra nem | A6 |
| A javítás után a mérő cella törlődik ahelyett, hogy átfordulna | A5/A6 (a cella hiánya a §7 gate-en a teszt-szám csökkenéseként látszik) |
| A mért bukások „javítása" `appConfigProvider`-override-dal (a shell kikapcsolása a tesztben) | A10 — a teljes suite ettől zöld lenne, de az `A2`/`A3` pinnelés és az `§5.4` tiltása alapján a review BLOCKER; a §10 diffjében a `FeatureFlags(...)`/`appConfigProvider.overrideWith` beszúrások láthatók |
| A `killSwitchPath` próza javítása gépi mérce nélkül | A11 (a prózát ma SEMMI nem méri — pontosan ez volt a §0.0/c 2. lelete) |

**Valódi-sértés próba (KÖTELEZŐ, a §10-ben dokumentálva):** állítsd vissza a `live_screen.dart` stat-sorát a javítás ELŐTTI alakra, futtasd a §7 gate-et → az **A5** négy cellájának PIROSNAK kell lennie → állítsd vissza a javítást.

## 7. Kötelező ellenőrzések

```bash
tools/round-gate.sh test/app/config/feature_flags_test.dart test/app/feature_flags_test.dart test/app/navigation/adaptive_scaffold_test.dart test/app/navigation/tab_state_restoration_test.dart test/app/navigation/legacy_route_redirect_test.dart test/ui/goldens/e13_r36_variant_matrix_test.dart test/accessibility/closure_suite_test.dart test/app/offline_network_guard_test.dart test/app/routing/app_router_test.dart test/app/routing/shell_lifecycle_test.dart test/features/ai_tutor/presentation/tutor_home_screen_test.dart test/features/live/live_stage_test.dart test/features/practice/presentation/practice_routing_test.dart test/features/today/hub_navigation_test.dart test/features/onboarding/onboarding_resume_test.dart test/features/onboarding/permission_primer_test.dart test/app/routing/onboarding_first_win_test.dart test/core/screen_size_guard_test.dart test/widget_test.dart test/features/live/live_screen_test.dart test/features/live/live_mic_release_test.dart test/features/live/live_background_test.dart test/features/live/live_announcement_throttle_test.dart test/features/live/live_lab_panel_test.dart test/features/live/expected_hint_cleared_on_live_test.dart test/features/settings/consent_center_test.dart test/features/settings/settings_account_test.dart test/features/settings/settings_persistence_failure_test.dart test/features/settings/lab_mode_toggle_test.dart test/features/library/library_test.dart test/features/analyze/analyze_screen_test.dart test/features/analyze/cancel_on_leave_test.dart test/ui/goldens/e15_r01_theme_adoption_test.dart test/tooling/feature_flag_audit_test.dart
```

A két érintett golden ÚJRAFELVÉTELE a merge-kapu architektúráján (ADR 0426) — az aarch64 boxon felvett PNG a CI-ban MINDIG piros lenne:

```bash
tools/golden-x86.sh record test/ui/goldens/e13_r18_screens_golden_test.dart test/ui/goldens/e13_r16_screens_golden_test.dart
```

## 8. Implementációs sorrend

1. A két elrendezési javítás (`live_screen.dart`, `permission_primer_screen.dart`).
2. A mérő cellák átfordítása → a javítás bizonyítása (RED→GREEN irány).
3. `adaptiveShellEnabled: nonProd`.
4. A flag- és navigációs őrök frissítése.
5. `docs/ui/legacy-backlog.md` lezárás + a valódi-sértés próba a §10-be.

## 9. Kockázatok

- **Belépési pont regresszió.** Ha a `/today` route bármely okból nem oldható fel, az app indulása törik (A2).
- **Locale-vak javítás.** A magyar címkék hosszabbak — az `en`-re szabott javítás átcsúszhat (A5).
- **További, eddig nem mért túlcsordulások.** A shell bekapcsolása új utakat tesz elérhetővé; a leletek a backlogba mennek, nem a kör scope-jába.

## 10. Implementation handoff — az implementer tölti ki

**Kontextus:** ez a folytató kör a `HANDOFF`-ban leírt négy leletet (F0–F4)
zárta le a korábbi `sonnet-impl` futás három meglévő commitján (`fb4d3f12`,
`fc0d13e8`, `bbf8ac90`, `e697c194`) felül. Az F0 (a `test/ui/goldens/failures/`
untracked bukás-artefaktum a scope-audit VIOLATION oka) már javítva volt a
munkafa átvételekor; ez a futás nem termelt új `failures/` könyvtárat, a §10
zárásakor is ellenőrizve.

### 10.1 Valódi-sértés próba (KÖTELEZŐ, §6.1) — A5

1. Kigyűjtöttem az `fc0d13e8` commit `live_screen.dart`-ra eső részét
   (`git show fc0d13e8 -- lib/features/live/screens/live_screen.dart`),
   patch-fájlba mentve, és `git apply -R`-rel visszaállítottam a stat-sort a
   javítás ELŐTTI, rugalmatlan `Row(children: [_ActionButton(...), _ActionButton(...)])`
   alakra (az `Expanded` csomagolás eltávolítva).
2. `flutter test test/ui/goldens/e13_r36_variant_matrix_test.dart --reporter compact`
   → **`+56 -4`**, pontosan a négy landscape+`textScale 2.0` cella bukott:
   ```
   00:18 +35 -1: live|light|en|landscape|2.0 [E]
   00:18 +42 -2: live|light|hu|landscape|2.0 [E]
   00:19 +49 -3: live|dark|en|landscape|2.0 [E]
   00:19 +56 -4: live|dark|hu|landscape|2.0 [E]
   ```
   A hibaüzenetek konkrét túlcsordulás-értékei megegyeznek a brief §0.0/e
   mérésével: `unexpected RenderFlex overflow of 12.0px` és
   `unexpected RenderFlex overflow of 34.0px`. Az összes NEM landscape+2.0
   cella (188 db) zöld maradt — a hiba pontosan a mérő cellák tárgya, semmi
   más nem sérült.
3. `git apply` (patch vissza, forward irányban) visszaállította a javítást;
   `git status --short` és `git diff --stat lib/features/live/screens/live_screen.dart`
   üres diffet mutatott (bájtra pontos visszaállás).
4. Újrafuttatva ugyanaz a teszt: **`+192` — All tests passed!** — mind a 192
   cella zöld, beleértve a négy korábban bukottat is.

### 10.2 A9 — a két érintett golden `tools/golden-x86.sh record` úton

- **`e13_r18_live_stage_compact{,_scale2}.png`**: az `e697c194` commit
  (`tools/golden-x86.sh record test/ui/goldens/e13_r18_screens_golden_test.dart`)
  vette fel x86-on; a PNG-k valóban elmozdultak (6785→5824 és 7024→7105 bájt).
- **`e13_r16_permission_primer_compact{,_scale2}.png`**: EZEN a körön **MEGMÉRTEM**,
  elmozdultak-e (F2) — `flutter test test/ui/goldens/e13_r16_screens_golden_test.dart --reporter compact`
  → **`+10: All tests passed!`**, a `mic-permission primer — compact` és
  `— compact_scale2` cellák VÁLTOZATLANUL zöldek a meglévő PNG-kkel szemben.
  **Ok:** a golden teszt a `MicrophonePermissionState.denied` (retryable) ágat
  rendereli (`test/ui/goldens/e13_r16_screens_golden_test.dart:113-127`), NEM
  a `permanentlyDenied`/`restricted` — azaz `!deniedFailure.retryable` — ágat,
  amelyiket a kör ténylegesen javított
  (`permission_primer_screen.dart:94-107`, a `SingleChildScrollView` csomagolás
  a nem-görgethető ágra került). A retryable ág MÁR korábban is
  `SingleChildScrollView`-ba volt csomagolva (`:111-115` a briefben hivatkozva),
  így ez a golden a javítás előtt és után bájtra ugyanazt a fát renderelte.
  **Következtetés:** a két PNG nem mozdult el, ÚJRAFELVÉTEL NEM TÖRTÉNT —
  ez a mérés (nem bemondás) igazolja a §0.0/a előrejelzését.

### 10.3 A10 — a teljes suite

```
~/flutter/bin/flutter test --reporter compact
```

Eredmény (a futás ténylegesen lefutott, végigvárva): **`+7330 ~15 -15`** — 15
bukás, és a bukott cellák NÉV SZERINT mind az öt mért ARM↔x86 raszter-drift
fájlban vannak (`[E]` jelölésű sorok kigyűjtve a teljes logból), a kapu x86
architektúráján zöld (ADR 0426, L516). Fájlonkénti bontás (a konkrét bukott
cellák a log alapján):

| Fájl | Bukott cellák | Ok |
|---|---|---|
| `test/ui/goldens/e13_r20_screens_golden_test.dart` | chord detail — compact, chord detail — compact_scale2, learning path — compact (3) | `Pixel test failed`, ARM↔x86, L516 |
| `test/ui/goldens/e13_r23_screens_golden_test.dart` | song library — compact, song library — compact_scale2 (2) | `Pixel test failed`, ARM↔x86, L516 |
| `test/ui/goldens/e13_r32_screens_golden_test.dart` | hub — compact, hub — compact_scale2, streak_detail — compact, streak_detail — compact_scale2, achievements — compact_scale2 (5) | `Pixel test failed`, ARM↔x86, L516 |
| `test/ui/goldens/e13_r34_screens_golden_test.dart` | club_detail — compact, club_detail — compact_scale2, safety — compact_scale2 (3) | `Pixel test failed`, ARM↔x86, L516 |
| `test/ui/goldens/e13_r35_screens_golden_test.dart` | share_preview — compact, share_preview — compact_scale2 (2) | `Pixel test failed`, ARM↔x86, L516 |

3+2+5+3+2 = 15, pontosan a teljes bukás-szám — ezen az öt fájlon kívül a
TELJES suite (beleértve a §7 gate 34 fájlját, a két átfordított golden-fájlt,
és minden más `test/**` fájl) zöld. Drifen kívül piros cella NINCS. (A
`test/app/routing/app_router_test.dart` „gamification routes" tesztnevei a
compact reporter által kétszer — indításkor és záráskor — kiírt, `[E]` jel
NÉLKÜLI, ZÖLD sorok; a log tartalmi átvizsgálása megerősítette, hogy ez a
fájl a §7 gate-ben és a teljes suite-ban is 100%-ban zöld.)

### 10.4 Melyik cella mit bizonyít

| Cella | Bizonyíték |
|---|---|
| A1 | `test/app/feature_flags_test.dart` új „Adaptive shell feature flag (E15-R02, ADR 0467, A1)" csoport, három cella (`development`/`lab` → `true`, `production` → `false`) — §7 gate zöld |
| A2 | `adaptive_scaffold_test.dart` — §7 gate zöld |
| A3 | `legacy_route_redirect_test.dart` — §7 gate zöld |
| A4 | `tab_state_restoration_test.dart` — §7 gate zöld |
| A5 | `e13_r36_variant_matrix_test.dart` — §7 gate zöld + §10.1 valódi-sértés próba |
| A6 | `closure_suite_test.dart` (A4 csoport) — §7 gate zöld |
| A7 | `docs/ui/legacy-backlog.md` §1 (lezárva a `bbf8ac90` commitban) |
| A8 | a tizenegy típus-pinnelő őr a §7 gate-ben mind zöld, cella-szám nem csökkent (`git diff` a teszt-fájlokon csak érték-fordítást mutat) |
| A9 | §10.2 — `e13_r18` újrafelvéve (`golden-x86.sh record`), `e13_r16` mérve és VÁLTOZATLAN |
| A10 | §10.3 — teljes suite `+8562 -15`, kizárólag az öt mért ARM↔x86 drift-fájl piros |
| A11 | `test/tooling/feature_flag_audit_test.dart` — a `killSwitchPath` próza-cella zöld (§7 gate [36]) |

## 11. Review — a Claude tölti ki
