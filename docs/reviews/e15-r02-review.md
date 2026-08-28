# E15-R02 — review (ADR 0055)

- **Kör:** `E15-R02` — Az adaptív shell alapértelmezetté tétele és a két mért túlcsordulás javítása
- **Branch:** `sonnet-impl/e15-r02-adaptive-shell-default-and-overflow-fixes`
- **Reviewelt HEAD:** `59d0bc50` (base `bbe86b1a` = `origin/main` a dispatch idején)
- **Implementer:** `sonnet-impl` (Claude Sonnet 5, `--effort high`), 1 alapkör + 1 javító kör
- **Reviewer:** Claude (Opus 5), orchestrátor — READ-ONLY, production kódot nem írtam
- **Dátum:** 2026-08-28

## 1. Mit mértem

| Mérés | Eredmény |
|---|---|
| Scope-audit (a diff a brief `allowed_paths`-ához képest) | **31 fájl, 0 listán kívüli** ✅ |
| Teszt-cellaszám minden érintett teszt-fájlban (base → head) | **egyik sem csökkent**; `feature_flags_test` 15→18, `feature_flag_audit_test` 18→20 ✅ |
| `expect(` darabszám fájlonként (base → head) | két csökkenés: `shell_lifecycle_test` 6→5, `live_stage_test` 20→18 → **MAJOR-1**, **NOTE-1** |
| Új `skip:` bevezetése | **nincs** ✅ |
| Új `appConfigProvider`-override a tesztekben | **egy** (`library_test.dart`) → **BLOCKER-1** |
| `--update-goldens` nyoma / aarch64-en felvett PNG | **nincs**; a két elmozdult PNG az `e697c194`-ben `tools/golden-x86.sh record` úton ✅ |
| A `_ExcludedCell` lista ürítése cella-törlés-e | **nem** — a mátrix cellái a `excluded == null` ágon élnek tovább, a lista kivétel-lista volt ✅ |

**A `.codex-round-status` `dirty_files=1` mezőjét kivizsgáltam** (kötelező, `docs/LESSONS.md` L21): a
jelzés írásának pillanatában a státuszfájl maga volt a különbség; a `git status --short` a jelzés
után **üres**, a munkafa tiszta. A `scope_audit=` kulcsot a wrapper ebben a futásban nem írta ki,
ezért a scope-auditot a fenti sorban **kézzel** végeztem el a commitolt brief `allowed_paths`
blokkjával szemben — 0 sértés.

**Gate:** a §7 gate zöldjét az implementer futtatta (39 lépés). A merge-kapu bizonyítéka a
**Full Gate** és a **Router CI** futása a merge SHA-n (exact-SHA szabály, ADR 0086 §2) — a
review a lokális gate-kimenetet nem tekinti merge-evidenciának.

## 2. Ami helyes (nem panaszkodás nélküli lista)

- **`live_screen.dart`** — a stat-sor két `_ActionButton`-ja `Expanded`-be került. A javítás a
  §6.1 valódi-sértés próbájával bizonyítva: a javítás visszavonásával **pontosan a négy**
  landscape+`textScale 2.0` cella pirosodik (12 px `en`, 34 px `hu`), a maradék 188 zöld marad.
- **`permission_primer_screen.dart`** — a `SingleChildScrollView` a **véglegesen elutasított**
  (`!retryable`) ágra került, a retryable ág változatlan. Pontosan a §6.1 „a javítás a már jó ágra
  kerül" hibás implementációjának ellentéte.
- **A mérő cellák átfordítása törlés nélkül.** A `_excludedCells` üresre írása NEM cella-törlés: a
  fájl STALE-őre miatt egy javított, de bent hagyott bejegyzés PIROS lenne, a kivétel kivétele
  pedig a normál „nincs túlcsordulás" ágra teszi a négy cellát. A `closure_suite_test` primer-cellája
  `isTrue`→`isFalse` fordulattal, megtartott `reason`-nel él tovább.
- **A1 (`feature_flags_test.dart`)** — három külön cella `development`/`lab`/`production`-re. A
  §6.1 „mindenhol `true`" hibás implementációját a production-cella most valóban pirosra váltja
  (a javító kör előtt egyetlen `adaptiveShell` hivatkozás sem volt a két flag-tesztben — ez volt az
  F1 lelet).
- **A11 (`feature_flag_audit_test.dart`)** — két új cella a `killSwitchPath` prózára; a §0.0/c 2.
  lelete (a prózát semmi nem méri) ezzel gépi mércét kapott.
- **A mért bukások igazítása** (`live_stage`, `screen_size_guard`, `widget_test`,
  `onboarding_first_win`, settings- és analyze-fájlok) az ÚJ viselkedéshez történt — router-navigáció
  a `legacyRedirects` céljaira, `/today` belépési pont, erősebb (specifikusabb) elvárásokkal. Ez a
  §5.4 által előírt irány.

## 3. Leletek

### BLOCKER-1 — `library_test.dart`: a szállított alapértelmezés elrejtése `appConfigProvider`-override-dal

`test/features/library/library_test.dart:82-131` — az egyetlen widget-cella (`Library tab lists a
saved session`) a flip után `appConfigProvider.overrideWithValue(...)`-szal **kikapcsolja a
shellt**, és „LEGACY REFERENCE (adaptive shell off — the still-shipped production default)" névre
keresztelődött át.

Ez pontosan az a minta, amit a brief §5.4 (ADR 0467 D9) tilt és a §6.1 mérce-mátrix
utolsó előtti sora **BLOCKER**-ként nevesít: a cella tárgya **nem** a kikapcsolt konfiguráció, hanem
a legacy `LibraryScreen` + `libraryRepositoryProvider` bekötése — az override tehát a régi
állítást tartja életben ahelyett, hogy a szállított új viselkedéshez igazodna.

**Enyhítő körülmény, amit MÉRTEM** (és ezért nem „a mérce eltűnt", hanem „elcserélődött"): a
production tényleg shell-KI marad (D2), tehát a legacy ág valóban szállított konfiguráció; és az
ÚJ alapértelmezés library-útja sem méretlen — az `adaptive_scaffold_test` A2-cellája pinneli a
`Profile → UnifiedLibraryScreen` destination-típust, a `legacy_route_redirect_test` a
`/library → /profile/library` élt, a `library_v2/item_routing_test` és `corrupt_item_test` pedig a
V2 képernyőt. **A hiányzó darab konkrétan ez:** a fájl a *default* konfiguráció alatt már semmit
nem mér, holott a cellaszám változatlan maradt — a coverage nem nőtt, hanem átterelődött.

**A kért javítás (minimális, scope-on belül):** a legacy-referencia cella **maradhat** (a
D2-indoklás valós, és a magyarázó komment jó), de a fájl kapjon **egy MÁSODIK cellát**, amely
ugyanazt a felhasználói célt a **szállított alapértelmezés alatt** (override NÉLKÜL) méri: a
mentett session a shell library-útján (`/profile/library`, illetve a `/library` legacy útról oda
átirányítva) látható. Ha a V2 képernyő más repository-provideren áll, azt a providert kell
felkötni — a cél a default-út mérése, nem a régi állítás átmentése.

### MAJOR-1 — `shell_lifecycle_test.dart`: a „Tuner back" cella elveszítette a felhasználói vissza-utat ÉS egy `expect`-et

`test/app/routing/shell_lifecycle_test.dart:84-101` — a cella két ponton gyengült:

1. `await tester.pageBack();` → `rig.container.read(routerProvider).pop();` — a teszt neve
   („Tuner **back** returns to the existing Live route") a **felhasználói** vissza-affordanciáról
   szól; a router közvetlen `pop()`-ja ezt megkerüli.
2. `expect(navigationBar.selectedIndex, 0)` **törölve**.

A 2. pontra a kommentben adott indoklás **elfogadható** (a `/practice/live` Stage-útvonal a shell
`indexedStack`-jén KÍVÜL van, tehát nincs `NavigationBar`, amin a kijelölést mérni lehetne) — ezt
a `app_router.dart` Stage-útvonal-definíciója alátámasztja.

Az 1. pont indoklása viszont **nincs megmérve**. A komment szerint a `pageBack()` a
`Navigator.canPop(context)`-tól függő affordanciát keresi — a `tuner_screen.dart:127-133`
tényleg `if (Navigator.canPop(context))` mögé teszi az `IconButton`-t (arrow_back +
`backButtonTooltip`), viszont a Tuner ide `context.push(AppRoutes.tuner)`-rel érkezik
(`live_screen.dart:413`), ami a gyökér-navigátoron push-ol, tehát a `canPop` **várhatóan igaz**, és
a `pageBack()` a tooltip alapján megtalálná a gombot.

**A kért javítás:** vagy állítsd vissza a `tester.pageBack()`-et (ez a preferált — a vissza-út a
cella tárgya), vagy — ha tényleg nem működik — tedd be a brief §10-be a **TÉNYLEGES mérést** (a
`pageBack()` bukásának szó szerinti kimenetét), és a kommentben erre hivatkozz. Bemondás nem
elég.

### MINOR-1 — `feature_flag_registry.dart`: az `adr` mező átírása a felhatalmazáson kívül esik

`lib/core/feature_flags/feature_flag_registry.dart:488` — `adr: '0275'` → `adr: '0467'`. A brief §4
felhatalmazása ehhez a fájlhoz szó szerint: „**KIZÁRÓLAG** az `adaptiveShellEnabled` bejegyzés
`killSwitchPath` **prózája** (ADR 0467 D8)". Az `adr` mező nem a `killSwitchPath` prózája; ráadásul
a csere **elveszíti a 0275 proveniensét** (az ADR 0467 a 0275-öt módosítja, nem váltja le — a flag
eredeti döntése továbbra is a 0275).

**A kért javítás:** `adr: '0275'` visszaállítása (a `killSwitchPath` próza amúgy is nevesíti az
ADR 0467 D1/D8-at), vagy — ha a mező tényleg a legfrissebb döntést hordozza — a brief §0.0
revíziójában dokumentált indoklás. Scope-sértés ez nem H3, mert a fájl a listán van, de a
felhatalmazás szűkebb volt, mint a diff.

### MINOR-2 — a §10 két helyen MÁS teljes-suite összesítőt mond

A brief §10.3 mérése `+7330 ~15 -15`, a §10.4 A10-sora ugyanarra a futásra `+8562 -15`. Egy
bizonyíték, két szám — az egyik hibás. **A kért javítás:** a ténylegesen mért összesítő
mindkét helyen, egyezően.

### NOTE-1 — `live_stage_test.dart`: a Finish-cella elhagyta a „session tényleg véget ért" állításokat

A cella (a „Finish fallback target is the app entry route" csoportban) helyesen fordult át az ÚJ
viselkedésre (`/today`-ra navigál), de a régi három állítás (nincs `finishing` marker, a transport
`liveResume` tooltipre vált, a Finish gomb megmarad) elveszett — ezért a fájl `expect`-száma 20→18.
Ez részben elkerülhetetlen (a LiveScreen a navigáció után már nincs a fában), de a session-vég
tényét a navigáció ELŐTTI pumpában még lehetne mérni. Nem blokkoló.

### NOTE-2 — `screen_size_guard_test.dart`: címke-tapintás helyett router-navigáció

A képernyő-bejárás `tester.tap(find.text(tab))`-ról `router.go(target)`-re váltott. A fájl tárgya
(elrendezés különböző méreteknél) sértetlen, és a bejárt képernyők ugyanazok — de a bottom-nav
címkék elérhetőségét ez a fájl már nem méri. Az `adaptive_scaffold_test` A2-cellái fedik. Nem
blokkoló.

## 4. Acceptance-cellák állapota

| # | Állapot | Megjegyzés |
|---|---|---|
| A1 | ✅ | három új cella, `production` → `false` |
| A2 | ✅ | `adaptive_scaffold_test` változatlanul zöld, cellaszám 24 |
| A3 | ✅ | `legacy_route_redirect_test` érintetlen és zöld |
| A4 | ✅ | `tab_state_restoration_test` érintetlen és zöld |
| A5 | ✅ | négy cella átfordítva + valódi-sértés próba (12/34 px) |
| A6 | ✅ | `closure_suite_test` primer-cellája `isFalse`-ra fordítva |
| A7 | ✅ | `legacy-backlog.md` §1 lezárva |
| A8 | ⚠ | a tizenegy őr zöld és cellát nem vesztett, **de** a `shell_lifecycle_test` egy `expect`-et igen → MAJOR-1 |
| A9 | ✅ | `e13_r18` x86-on újrafelvéve; `e13_r16` MÉRVE változatlan (a golden a retryable ágat rendereli — a javítás a másik ágon van) |
| A10 | ⏳ | lokálisan zöld a mért ARM↔x86 driften kívül; a **merge-evidencia a Full Gate futása a merge SHA-n** |
| A11 | ✅ | két új gépi cella a prózára |

## 5. Verdikt

**CHANGES REQUESTED** — 1 BLOCKER, 1 MAJOR, 2 MINOR, 2 NOTE.

A kör tartalmi munkája erős (a két elrendezési javítás bizonyítottan valódi, a mérő cellák
szabályosan fordultak át, a 19 mért bukás igazítása a §5.4 irányát követi). A blokkoló egyetlen
fájlra szűkül: a `library_test.dart` a szállított alapértelmezés helyett a kikapcsolt
konfigurációt méri, ami az ADR 0467 D9 kifejezett tilalma.

## 6. Újra-ellenőrzés a javító kör után

*(a javító kör után tölti ki a reviewer)*
