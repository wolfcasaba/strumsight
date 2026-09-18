# Navigációs audit — 2026-09-16

**Kiváltó ok:** tulajdonosi hibajelentés valós eszközön (fejlesztői APK,
`build-apk` run 35071659469; adaptive shell + Practice V2 + Song Trainer V2 +
community BE): *„Ha megnyitok egy menüpontot, nem tudok visszacsúsztatni és
nincs vissza-nyíl. Ez navigációs hiba."*

**Vizsgált felület:** `lib/app/routing/` (`app_router.dart`, `app_route.dart`,
`adaptive_shell_routes.dart`, `route_guards.dart`), `lib/app/home_shell.dart`,
`lib/app/strumsight_app.dart`, a `core/design_system` layout-primitívek
(`ss_adaptive_scaffold.dart`, `ss_stage_scaffold.dart`),
`android/app/src/main/AndroidManifest.xml`, valamint minden olyan képernyő,
amely a Today / Practice / Profile / Coach hubról, az alsó navigációból vagy a
Settings listából elérhető.

> Megjegyzés: a navigációs forrás a repóban **`lib/app/routing/`** (nem
> `lib/app/navigation/`); a teszt-oldali megfelelője viszont
> `test/app/navigation/`.

---

## 1. Gyökérok egy mondatban

Minden hub-belépő **`context.go(...)`**-val navigált. A `go` a go_router
teljes útvonal-veremét **lecseréli**, így a megnyitott képernyő alatt nem
maradt lap:

- `Navigator.canPop() == false` → az `AppBar` nem rajzol automatikus
  `leading` vissza-nyilat, és a `SsStageScaffold`-os képernyők (Tuner,
  Metronome) saját `if (Navigator.canPop(context))` mögé tett vissza-gombja
  sem jelenik meg;
- az Android vissza-gesztusnak/gombnak nincs mit poppolnia → **kilép az
  alkalmazásból**.

Ez pontosan a jelentett tünetpár. Nem `PopScope`-hiba, nem manifest-hiba,
nem `MaterialApp.router` konfigurációs hiba (lásd §4).

---

## 2. Belépőnkénti tábla

Jelölések: **Nav** = navigáció módja a javítás ELŐTT → UTÁN. „shell-branch" =
`StatefulShellRoute.indexedStack` egyik ágában regisztrált útvonal;
„top-level" = a shellen kívüli `GoRoute`.

### 2.1 Today Hub (`/today`, shell-branch 0) — `today_hub_screen.dart`

| Képernyő | Belépési pont | Navigáció módja | Vissza-nyíl | Rendszer-vissza | Verdikt | Javítás |
| --- | --- | --- | --- | --- | --- | --- |
| `PracticeAreaHubScreen` (`/practice`) | elsődleges CTA (`today-hub-primary-cta`), :91 | `go` → `go` | nincs (és nem is kell) | fül-váltás | **OK** | nincs — ez shell-destináció (fül), a `go` a helyes |
| `ProgressDashboardScreen` (`/profile/progress`) | „View progress", :123 | `go` → **`push`** | nem volt → **van** (AppBar) | kilépett → **visszalép** | **HIBA** | push |
| `VisionSetupScreen` / `VisionSessionScreen` | Vision kártya CTA, :288 | `go` → **`push`** | nem volt → **van** (AppBar) | kilépett → **visszalép** | **HIBA** | push (flag mögött: `visionEnabled`) |

### 2.2 Practice Area Hub (`/practice`, shell-branch 1) — `practice_area_hub_screen.dart`

| Képernyő | Belépési pont | Navigáció módja | Vissza-nyíl | Rendszer-vissza | Verdikt | Javítás |
| --- | --- | --- | --- | --- | --- | --- |
| `PracticeSetupScreen` (`/practice/setup?id=`, top-level) | „Start recommended practice", :71 | `go` → **`push`** | volt (saját explicit `BackButton`) | kilépett → **visszalép** | **HIBA** (csak rendszer-vissza) | push + `_readArgs` javítás (§3.3) |
| `LiveScreen` (`/practice/live`, top-level, Stage) | Quick tool „Live", :95 | `go` → **`push`** | nincs (Stage: „Finish" a kilépő) | kilépett → **visszalép** | **HIBA** | push; a `_finish()` már `canPop`-ra popol |
| `TunerScreen` (`/practice/tuner`, shell-branch 1) | Quick tool „Tuner", :100 | `go` → **`push`** | **nem volt** (`Navigator.canPop` false) → **van** | kilépett → **visszalép** | **HIBA** | push |
| `MetronomeScreen` (`/practice/metronome`, shell-branch 1) | Quick tool „Metronome", :105 | `go` → **`push`** | **nem volt** → **van** | kilépett → **visszalép** | **HIBA** | push |
| `ChordLibraryScreen` (`/practice/chords`, shell-branch 1) | Quick tool „Chord library", :110 | `go` → **`push`** | nem volt → **van** (AppBar) | kilépett → **visszalép** | **HIBA** | push |
| `PracticeSetupScreen` (`/practice/setup`, id nélkül) | kategória-chipek, :136 | `go` → **`push`** | volt | kilépett → **visszalép** | **HIBA** | push |

### 2.3 Profile Hub (`/profile`, shell-branch 4) — `profile_hub_screen.dart`

| Képernyő | Belépési pont | Navigáció módja | Vissza-nyíl | Rendszer-vissza | Verdikt | Javítás |
| --- | --- | --- | --- | --- | --- | --- |
| `GamificationHubScreen` (`/gamification`, top-level) | „Achievements", :64 | `go` → **`push`** | nem volt → **van** | kilépett → **visszalép** | **HIBA** | push |
| `UnifiedLibraryScreen` (`/profile/library`, shell-branch 4) | „Library", :89 | `go` → **`push`** | nem volt → **van** | kilépett → **visszalép** | **HIBA** | push |
| `SettingsScreen` (`/profile/settings`, shell-branch 4) | „Settings", :94 | `go` → **`push`** | **nem volt és nem is lehetett** | kilépett → **visszalép** | **HIBA + hiányzó app bar** | push + útvonal-szintű `Scaffold`+`AppBar` (§3.2) |
| `LoginScreen` (`/login`, top-level) | „Sign in", :148 (csak `accountEnabled` esetén) | `go` → **`push`** | nem volt → **van** | kilépett → **visszalép** | **HIBA** | push; a `login_screen.dart` doc-komment maga dokumentálta ezt a hibát |

### 2.4 Coach (`/coach`, shell-branch 3) — `tutor_home_screen.dart`

| Képernyő | Belépési pont | Navigáció módja | Vissza-nyíl | Rendszer-vissza | Verdikt | Javítás |
| --- | --- | --- | --- | --- | --- | --- |
| `TutorChatScreen` (`/tutor/chat`, top-level) | „Start" CTA, :81 | `go` → **`push`** | nem volt → **van** | kilépett → **visszalép** | **HIBA** | push |

### 2.5 Settings-lista és egyéb detail-belépők

| Képernyő | Belépési pont | Navigáció módja | Vissza-nyíl | Rendszer-vissza | Verdikt | Javítás |
| --- | --- | --- | --- | --- | --- | --- |
| `ProgressScreen`/`ProgressDashboardScreen` (`/progress`) | Settings lista, `settings_screen.dart:67` | `go` → **`push`** | nem volt → **van** | kilépett → **visszalép** | **HIBA** | push |
| `LatencyCalibrationScreen` (`/calibrate`) | Settings lista, :224 | `push` | van | visszalép | **OK** | — |
| `LoginScreen` | Settings „Sign in", :361 | `push` | van | visszalép | **OK** | — (ez volt a helyes minta) |
| `PrivacyCenterScreen`, `ModelManagerScreen` | Settings kártyák, :84/:100 | `Navigator.push` + `MaterialPageRoute` | van | visszalép | **OK** | — (nincs route, szándékos) |
| `/progress` a Streak-ből | `streak_screen.dart:44` | `go` → **`push`** | nem volt → **van** | kilépett → **visszalép** | **HIBA** | push |
| `/live` a Streak napi kihívásból | `streak_screen.dart:172` | `go` → **`push`** | — (Stage) | kilépett → **visszalép** | **HIBA** | push |
| `AnalysisMetricDetailScreen` / `AnalysisTimelineScreen` | `analysis_overview_screen.dart:67/119/137` | `go` → **`push`** | nem volt → **van** | kilépett → **visszalép** | **HIBA** (flag mögött: `audioAnalysisV2Enabled`, jelenleg KI) | push |
| `PracticeSetupScreen` / `PlanSetupScreen` a legacy hubról | `practice/presentation/screens/practice_hub_screen.dart:150/154` | `go` → **`push`** | volt / van | kilépett → **visszalép** | **HIBA** | push |
| `LessonListScreen` belépői, `LibraryScreen` session-detail, Song Trainer, Chord detail, Community, Share | `context.push` ill. `Navigator.push` | — | van | visszalép | **OK** | — már helyes volt |

### 2.6 Shell-fülek (szándékosan nincs vissza-nyíl)

`/today`, `/practice`, `/songs`, `/coach`, `/profile` (adaptive shell) és
`/live`, `/analyze`, `/learn`, `/library`, `/settings` (legacy `HomeShell`) —
ezek destináció-gyökerek. `AdaptiveHomeShell.onDestinationSelected` =
`navigationShell.goBranch`, a legacy shellé `context.go(shellTabs[i])`. Ez a
helyes szemantika, **nem változott**.

---

## 3. Mért mellékleletek (nem a fő tünet, de ugyanazon a hibaláncon)

### 3.1 A Stage-képernyők vissza-gombja `Navigator.canPop`-ra van kötve

`tuner_screen.dart:126` és `metronome_screen.dart:186` a vissza-`IconButton`-t
`if (Navigator.canPop(context))` mögé teszi. Ez önmagában helyes (fülként
nyitva nem kell vissza-nyíl), de `go`-val nyitva ez tette a hibát
*láthatatlanná*: a gomb nem hiányzott, hanem sosem renderelődött. A `push`
mindkettőt megoldja.

### 3.2 `SettingsScreen`-nek nincs saját `Scaffold`/`AppBar`

`settings_screen.dart` `SettingsThemeScope(SafeArea(ListView(...)))`-t ad
vissza — shell-testnek íródott. Push után a lap a shell `Scaffold`-ján KÍVÜL
renderelődik, így (a) nem lenne `Material` ős a `ListTile`/`SwitchListTile`
alatt, (b) nem lenne hova tenni a vissza-nyilat.

A javítás **egy helyen**, a kompozíciós gyökérben történt
(`app_router.dart`, `/profile/settings` builder):
`Scaffold(appBar: AppBar(), body: SettingsScreen())`. Szándékosan NEM a
képernyőben: négy golden-suite (`e13_r35`, `e13_r36`, `e15_r01`, `e15_r13`)
rögzíti a `SettingsScreen` widget-fáját `Scaffold(body: SettingsScreen())`
alakban, és a képernyőnek saját nagy „Settings" címe van (ezért az app bar
címtelen — csak a leading vissza-gombot adja).

Nincs a repóban olyan design-system app bar komponens (`SsAppBar`-szerű),
amely a `leading`-et elnyomná; sehol nincs `automaticallyImplyLeading: false`
és sehol nincs `leading: null` felülírás — ez tehát NEM volt oka a hibának.

### 3.3 `PracticeSetupScreen._readArgs` a `push` első frame-jén elvesztette a `?id=`-t

`_readArgs` a `routeInformationProvider.value.uri`-t olvasta. Ezt a Flutter
`Router` csak **post-frame** callbackben frissíti, így egy `context.push` utáni
ELSŐ buildnél még az ELŐZŐ location-t tartalmazza — `go`-nál nem, mert ott a
provider értéke a build ELŐTT frissül. A CTA `push`-ra váltása így némán a
„nincs definíció-id" hibaágra vitte volna a Setupot (és elvitte volna az e2e
walkthrough-t is). Javítás: `GoRouterState.of(context).uri` — go_router egy
imperatív push `GoRouterState`-jét a pusholt location saját match-listájából
építi, tehát `go`-ra és `push`-ra egyaránt helyes.

### 3.4 `_backToHub` most popol

`practice_setup_screen.dart` „vissza" ága `canPop` esetén `pop`-ol, és csak
üres verem esetén esik vissza `go(practiceHub)`-ra (deep link / `onException`).

---

## 4. Amit megvizsgáltunk és NEM volt hibás

| Gyanúsított | Mérés | Verdikt |
| --- | --- | --- |
| `PopScope(canPop: false)` / `WillPopScope` elnyeli a rendszer-vissza gombot | `WillPopScope` **sehol** nincs a fában. `PopScope` három helyen: `ss_stage_scaffold.dart:84` (`canPop: !hasUnsavedSession`), `song_editor_screen.dart:155` (`canPop: !state.isDirty` + megerősítés), `plan_preview_screen.dart:87` (`canPop: true`, explicit). Egyik sem tiltja a popot a jelentett menüpontokon. | tiszta |
| `MaterialApp.router` `backButtonDispatcher` / `onPopPage` ütközés | `strumsight_app.dart:30` csak `routerConfig`-ot ad át; nincs saját dispatcher, nincs `onPopPage`, nincs `onGenerateRoute`. | tiszta |
| `automaticallyImplyLeading: false` / `leading: null` valamelyik app barban | egyetlen találat sincs `lib/`-ben. | tiszta |
| Route-literál szivárgás | `test/tooling/route_literal_guard_test.dart` szimulálva a javítás után: 0 sértés (minden új hívás `AppRoutes`-konstans vagy `Uri.toString()`). | tiszta |
| Predictive back | a manifestben **nem volt** `android:enableOnBackInvokedCallback`. | lásd §5 |

---

## 5. Predictive back (manifest)

`android/app/src/main/AndroidManifest.xml` `<application>` eleme megkapta az
`android:enableOnBackInvokedCallback="true"` attribútumot. A feltétel, amit a
feladat szabott, teljesül: a fában **nincs `WillPopScope`** (amit a predictive
back elront) — minden vissza-kapu a modern
`PopScope`/`onPopInvokedWithResult` API, épp az, amire a keretrendszer
`OnBackInvokedCallback`-et regisztrál.

**Maradék kockázat:** ez eszköz-oldali viselkedésváltás (vissza-animáció),
amit ebben a konténerben nem lehet mérni — a végső elfogadás a tulajdonos
valós APK-tesztje. Ha bármi furcsa: az attribútum egyetlen sor, visszavonható.
Fontos: a jelentett hibát **nem** ez okozta és **nem** ez javítja — a
gesztus maga a `push` nélkül is működött, csak nem volt mit poppolni.

---

## 6. Regressziós fedezet (`test/app/navigation/hub_back_navigation_test.dart`)

- **N1 — forrás-szintű őr (ez fogta volna meg a hibát).** Végigolvassa az
  ÖSSZES `lib/features/**/screens/**` fájlt: egy képernyő csak elsődleges
  navigációs destinációra (`AppRoutes.adaptiveShellDestinations`) `go`-hat,
  minden más `push` kell legyen. Az útvonal-katalógust magából az
  `app_route.dart`-ból parszolja, így nem tud elcsúszni tőle, és a még nem
  létező képernyőkre is érvényes. Két dokumentált kivétel van
  (`live_screen.dart` üres-verem fallback, `practice_setup_screen.dart`
  session-átadás), és egy második cella őrzi, hogy a kivételek ne
  maradjanak bennragadva elavultan.
- **N2 — hubonkénti UI-cellák.** Nyolc belépő (Today→Progress;
  Practice→Setup/Tuner/Metronome/Chord library; Profile→Achievements/
  Library/Settings): koppintás után van vissza-affordancia
  (`BackButton` vagy a Stage `Icons.arrow_back` gombja), `router.canPop()`
  igaz, és `tester.pageBack()` visszavisz a hubra (`router.state.uri.path`
  == hub, a detail képernyő eltűnik).
- **N3 — router-szintű, katalógusból paraméterezve.** A hub-forrásokból
  kiolvasott `AppRoutes.*` célok ∩ az ÉLŐ router regisztrált útvonalai −
  destinációk − paraméteres útvonalak; minden ilyen útvonalra: `push` után
  `canPop()` igaz, `pop()` után visszaáll a hub. Új detail-útvonal így
  automatikusan fedezetet kap.

Az `e2e/full_app_walkthrough_test.dart` állításai **nem** váltak hamissá
(koppint-és-vár mintát használ, nem verem-alakot), ezért nem módosult.

---

## 7. Nyitva maradt (tudatosan, külön körre)

1. **`PracticeSetupScreen` → `/practice/session` `go`-val** indul
   (`practice_setup_screen.dart:214`), és a session befejeztével a
   `practice_effect_listener.dart:119` `router.go('/practice/result')`-ot hív.
   Így a session/eredmény képernyőről a rendszer-vissza továbbra is kiléphet
   az appból. Ez viszont Stage-flow-szemantika (saját `PopScope`-megerősítés,
   ADR 0276/0079), külön kör és külön elfogadási mátrix — nem ez a jelentett
   tünet, és a mostani minimál-javítás nem nyúl hozzá.
2. **`LiveScreen`-nek nincs látható vissza-nyila** (Stage, a „Finish" a
   kilépő). Push után a rendszer-vissza már működik. Nyíl hozzáadása a
   Stage-fejlécet és a hozzá tartozó goldeneket érintené.
3. **Kereszt-ág push** (`/today` → `/profile/progress`): mindkét lehetséges
   go_router-renderelési modellben (gyökér-navigátor fölé, ill. a cél-ág
   navigátorába) van vissza-nyíl és működik a rendszer-vissza; a különbség
   csak annyi, hogy a vissza HOVA visz. A tesztek mindkettőre zöldek.
   Az eszközön ez a pontos viselkedés a tulajdonos APK-tesztjén mérhető.
