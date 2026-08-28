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

**Benne van:** `adaptiveShellEnabled: nonProd` a `forEnvironment`-ben (production továbbra is KI, amíg a GA-scope nem dönt) · a `live_screen.dart` stat-sorának javítása (a `Row` gyermekei `Expanded`/`Flexible`, vagy a sor görgethető) · a `permission_primer_screen.dart` véglegesen-elutasított ágának `SingleChildScrollView`-ba burkolása (a retryable ág MÁR így csinálja) · a MÉRŐ cellák átfordítása: a négy `_ExcludedCell` és a closure-cella mostantól „NINCS túlcsordulás"-t állít · a három navigációs őr és a két flag-teszt frissítése az új alapértelmezéshez · `docs/ui/legacy-backlog.md` §1 lezárása (a két tétel dátummal, a javítás hivatkozásával).

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

**Tilos zóna:** `lib/app/routing/**` (a router logikája NEM változik, csak a flag) · `lib/features/**` egyéb képernyői · `test/ui/goldens/goldens/**` · `docs/adr/**` · `tools/**`

## 5. Kötött architekturális döntések (ADR 0467)

### 5.1 A shell alapértelmezés, de production KI marad

**NEM elfogadható gyengítés:** a production ág bekapcsolása „úgyis ugyanaz a kód" alapon — a GA-scope-ot a Chapter 12 Kör 28 dönti el.

### 5.2 A javítás a MÉRŐ cellát fordítja át, nem törli

**NEM elfogadható gyengítés:** az `_ExcludedCell` vagy a closure-cella eltávolítása — a törléssel a hiba visszatérése észrevétlen maradna (a zsugorodás-őr elve, [L180](../LESSONS.md#l180)).

### 5.3 A legacy belépési pont megmarad átirányításként

A `/live` és a többi legacy útvonal továbbra is működik, a `legacyRedirects` táblán át. **NEM elfogadható gyengítés:** a régi útvonalak megszüntetése — a mentett mélylinkek és a widget-tesztek is ezeken jönnek.

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

**Küszöb-cellahármas a szövegskálára** (a kötelező határ `2.0`, INKLUZÍV): a küszöb **alatt** (`1.5`) → nincs túlcsordulás; **pontosan rajta** (`2.0`) → nincs túlcsordulás — EZ az A5/A6 feltétele; a küszöb **fölött** (`2.5`) → nem követelmény, a mátrix nem méri, és a `2.0` teljesítése nem hivatkozhat rá.

### 6.1 Mérce-mátrix — melyik hibás implementációt melyik cella fogja pirosra

| Hibás implementáció | Melyik cella vált PIROSRA |
|---|---|
| A flag `nonProd` helyett mindenhol `true` lesz (production is) | A1 production-cellája |
| A stat-sor javítása csak `en` locale-ra elég (a hosszabb `hu` címkék tovább csordulnak) | A5 `hu` cellái |
| A primer javítása a retryable ágra kerül (ami már jó volt), a véglegesen-elutasítottra nem | A6 |
| A javítás után a mérő cella törlődik ahelyett, hogy átfordulna | A5/A6 (a cella hiánya a §7 gate-en a teszt-szám csökkenéseként látszik) |

**Valódi-sértés próba (KÖTELEZŐ, a §10-ben dokumentálva):** állítsd vissza a `live_screen.dart` stat-sorát a javítás ELŐTTI alakra, futtasd a §7 gate-et → az **A5** négy cellájának PIROSNAK kell lennie → állítsd vissza a javítást.

## 7. Kötelező ellenőrzések

```bash
tools/round-gate.sh test/app/config/feature_flags_test.dart test/app/feature_flags_test.dart test/app/navigation/adaptive_scaffold_test.dart test/app/navigation/tab_state_restoration_test.dart test/app/navigation/legacy_route_redirect_test.dart test/ui/goldens/e13_r36_variant_matrix_test.dart test/accessibility/closure_suite_test.dart test/app/offline_network_guard_test.dart test/app/routing/app_router_test.dart test/app/routing/shell_lifecycle_test.dart test/features/ai_tutor/presentation/tutor_home_screen_test.dart test/features/live/live_stage_test.dart test/features/practice/presentation/practice_routing_test.dart test/features/today/hub_navigation_test.dart test/features/onboarding/onboarding_resume_test.dart test/features/onboarding/permission_primer_test.dart
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

## 11. Review — a Claude tölti ki
