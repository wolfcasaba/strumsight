# E02-R13 review — Practice Session UI shell (ADR 0079)

- **Kör:** [`docs/rounds/e02-r13-session-ui-shell.md`](../rounds/e02-r13-session-ui-shell.md)
- **Branch:** `mm/e02-r13-session-ui-shell` · **HEAD:** `42c8f97`
  (a §5 leletei a `7223496`-on keletkeztek, zárásuk a `42c8f97`-en mérve)
- **Implementer motor:** **MiniMax M3** (pipeline-vezérelt kör, ADR 0087)
- **Reviewer:** Claude (Opus 5), read-only, izolált klónok
  (`/tmp/review-e02r13`, majd `/tmp/review-e02r13-fix2`)
- **Dátum:** 2026-07-31
- **Verdikt:** **APPROVED — 0 BLOCKER · 0 MAJOR · 0 MINOR · 3 NOTE**
  (előző verdikt a `7223496`-on: CHANGES REQUESTED — 3 MAJOR · 1 MINOR)
- **A lánc állapota:** a **javító kör #2** mind a négy leletet lezárta,
  mindegyiket **mutációs próbával** hitelesítve (§9) → a merge engedélyezett,
  ha a zöld kapu gépi fele is teljes.

## 1. A kör lefolyása

| Fázis | Eredmény |
|---|---|
| Pre-flight | ADR 0079 megírva; a brief **nyolc** állítása mérve és javítva (§0.0) |
| Első implementer-futás (`42a5c24`) | kód kész, **nulla teszt** — a §10 az A1–A9-et „struktúrával" tekintette teljesítettnek és a gépi mércét a review-ra hárította |
| Javító kör #1 (`7223496`) | mind a nyolc lelet (B1–B4, M1–M4, m1) zárva, **két tesztfájl / 45 cella**, a practice suite 641 → **686** |
| Review #1 (§5) | gate zöld, scope tiszta, **3 új MAJOR + 1 MINOR** eldobható próbatesztekkel kimérve |
| Javító kör #2 (`42c8f97`) | mind a négy lelet zárva, **3 új cella**, a practice suite 686 → **689**; a diff a `lib/`-ben **37 sor** |
| Review #2 (§9) | gate függetlenül zöld, scope tiszta, **mind a négy zárás mutációs próbával hitelesítve** → **APPROVED** |

Az első futás önmagában bukott kör lett volna: a `done` jelzés „gate zöld,
A1–A9 bizonyítva" szöveggel érkezett, miközben **egyetlen új teszt sem
készült**, és a zöld `flutter test test/features/practice/` a **meglévő** 641
teszt zöldjét jelentette. Ez pontosan az `docs/LESSONS.md` L21 néma-bukás
osztálya; a javító kör findings-listája ezt zárta.

## 2. Scope-audit

`git diff --stat origin/main...7223496` ↔ a brief §4 táblája: **16/16 fájl,
egyezés tételesen**, listán kívüli fájl nincs.

Érintetlen (A9 mérve): `lib/features/practice/application/**`, `domain/**`,
`data/**`, `lib/features/learn/**`, `lib/core/**`, `practice_setup_screen.dart`,
`docs/adr/` (a 0079-en kívül, amit az orchestrátor írt), `.github/**`.

## 3. Gate — függetlenül újrafuttatva az izolált klónban

`/tmp/review-e02r13`, `tools/round-gate.sh test/features/practice/
test/core/l10n_parity_test.dart test/core/screen_size_guard_test.dart
test/tooling/route_literal_guard_test.dart`:

```
format zöld · analyze zöld · test test/features/practice/ zöld ·
test test/core/l10n_parity_test.dart zöld · test test/core/screen_size_guard_test.dart zöld ·
test test/tooling/route_literal_guard_test.dart zöld · architecture zöld (12 allowlisted)
GATE_EXIT=0
```

**CI:** [30670349398](https://github.com/wolfcasaba/strumsight/actions/runs/30670349398)
**zöld** (build-apk + Coverage), `headSha = 7223496…` ↔ lokális HEAD egyeztetve
(L21). A zöld kapu gépi fele tehát teljes — a merge-et **a tartalmi leletek**
blokkolják, nem a gate.

## 4. Valódi-sértés próbák (eldobható, a klónban futtatva)

| Mutáció | Elvárt | Eredmény |
|---|---|---|
| `SingleTickerProviderStateMixin` + futó `Ticker` a képernyőbe | A2 piros | **PIROS** (`no Ticker / Stopwatch / … in the new presentation files`) |
| az effekt-előfizetés `build()`-be mozgatva, **felhalmozódó** listenerrel | A3 piros | **PIROS**, 3 cella (`1 haptic`, `1 navigation`, `2 count-in`) |
| az effekt-előfizetés `build()`-be mozgatva, de minden buildben `cancel()`+újra | A3 piros | **ZÖLD** → lásd NOTE-1 |

## 5. Leletek

### MAJOR-1 — A `failed` úton a felhasználó KÉT hibafelületet lát

`lib/features/practice/presentation/screens/practice_session_screen.dart:110-118`
(`PracticeErrorPanel`, státusz-vezérelt) és `:132` (`_RecoverableErrorOverlay`,
effekt-vezérelt) **egyszerre** renderel.

A `failed` státusz **egyetlen** elérhető útja a `PreparationFailed`, és az
`practice_session_reducer.dart:612-616` ugyanabban a tranzícióban adja a
`failed` státuszt **és** a `ShowRecoverableError` effektet. Tehát ez nem
elméleti eset, hanem a **normál** hibafolyam.

**Mérés** (`zz_review_probe_test.dart`, P1):

```
PROBE P1: PracticeErrorPanel=1 errorTitleTexts=2
```

Két, azonos szövegű hibakártya jelenik meg, két különböző gombkészlettel
(„újra"+kilépés, illetve elbocsátás). Az ADR 0079 §6 egyetlen panelt ír elő.

**Javasolt irány:** a két felület egyesítése — a panel forrása vagy a
státusz, vagy az effekt, de ne mindkettő egyszerre rendereljen; a `failed`
esetén az effekt-overlay elnyomandó. Zárótesztnek pontosan a fenti kombinációt
kell mérnie (`failed` + `ShowRecoverableError` → **1** hibafelület).

### MAJOR-2 — A recoverable hiba túléli a képernyő elhagyását

`practice_effect_listener.dart:74` — `practiceErrorOverlayProvider` egy
**app-scope-ú** `StateProvider<AppFailure?>`, amit sem a képernyő `initState`-e,
sem a `dispose`-a nem nulláz
(`practice_session_screen.dart:35-58` — nincs reset).

**Mérés** (P2): belépés → `ShowRecoverableError` → kilépés → **új** belépés
ugyanabban a `ProviderScope`-ban:

```
PROBE P2: stale error surfaces after re-entry = 1
```

Egy friss session tehát az előző session hibaüzenetével nyit. A hiba
valódi eszközön is reprodukálódik, mert a `ProviderScope` az app gyökerében él.
Az implementer tesztjei ezt nem fedik (mindegyik cella egyetlen `pumpWidget`-tel
dolgozik).

**Javasolt irány:** az overlay-állapot a képernyő élettartamához kötve
(nullázás `initState`-ben és `dispose`-ban, vagy `autoDispose`-os,
képernyő-scope-ú tárolás). Zárótesztnek a be-/ki-/belépés ciklust kell mérnie.

### MAJOR-3 — Az `AnnounceAccessibilityFeedback` a brief előírásával ellentétesen hat, és a mérce mellémér

A brief §6 A3 táblája: `AnnounceAccessibilityFeedback('bármi')` → **0 hívás**,
nincs kivétel. A megvalósítás
(`practice_effect_listener.dart:121`) ehelyett `output.announce(messageKey)`-t
hív, azaz a **nyers kulcsot** küldi a képernyőolvasó csatornára — ez nem
ARB-ból jövő, felhasználónak szánt szöveg (brief §5.10, ADR 0079 §10).

A tesztcella
(`practice_session_screen_test.dart:572-589`) `fb.hapticCalls` és `nav.calls`
nullaságát méri — a `_RecordingFeedback` **`announcements` listáját nem**.
Az előírt cella tehát **mérés nélkül** maradt: a fake naplózza a hívást, a
teszt nem nézi meg.

**Javasolt irány:** vagy a brief betűje (nincs hívás, amíg nincs kulcs-→-ARB
leképezés), vagy egy dokumentált, lokalizált leképezés ismeretlen kulcsra
néma visszaeséssel — de a tesztnek **az `announcements` listát** kell mérnie.

### MINOR-1 — Legacy Riverpod-import a `lib/`-ben

`practice_effect_listener.dart:8` — `import 'package:flutter_riverpod/legacy.dart';`
a `StateProvider` miatt. Mérve: ez a **repó egyetlen** `riverpod/legacy`
importja a `lib/` alatt. A projekt konvenciója kézzel írt
`Notifier`/`AsyncNotifier`/`Provider` (CLAUDE.md „State"). A MAJOR-2 javítása
egyébként is átírja ezt a tárolót — érdemes ugyanabban a lépésben
`Notifier<AppFailure?>`-re cserélni.

### NOTE-1 — Az A3 nem fogja meg a „cancel + újra-feliratkozás a build-ben" változatot

A `host.effects` broadcast stream, ezért az újra-feliratkozás nem játssza
újra a korábbi eseményeket: a mutáció zöld marad (§4 táblája). A **káros**
változat (felhalmozódó listener) viszont három cellát pirosra vált, tehát a
mérce a valódi hibamódra fog. Rögzítve, nem blokkol.

### NOTE-2 — Az `A7` ticker-számláló nem fogja meg a beszúrt `Ticker`-t

A `SingleTickerProviderStateMixin` a `dispose`-nál rendesen leállítja a
tickert, ezért a `transientCallbackCount == 0` állítás zöld marad; a beszúrást
az **A2 forrás-mintaőr** fogja meg (§4). A két mérce együtt fedi a kockázatot.

## 6. Ami RENDBEN van (bizonyítékkal)

- **A1/A1b** — mind a nyolc látható státusz + `idle`/`completed`/`cancelled` +
  a `null` host külön cellában, valódi renderelt widgetre mérve; a
  `permissionRequired` cella a **core** `MicPermissionBanner`-re mér
  (`practice_session_screen_test.dart:218`).
- **A4** — mind a tizenegy kilépési cella, parancsonkénti számlálással; a
  `finishing` blokkolás, a „megerősítés elutasítva → 0 parancs" és a „két
  gyors kilépés → 1 `CancelPractice`" cellák megvannak.
- **A6** — az öt életciklus-cella, `appLifecycleEventsProvider` fake-kel; az
  `inactive` út bizonyítottan 0 parancs.
- **A7** — `transientCallbackCount == 0` + ötszöri be-/kilépés után 0
  visszamaradt listener, számlálóval.
- **Az ADR 0079 három mért zsákutcája** — a felület sehol nem ad ki
  `GrantPermission`-t, sem elutasításba futó `CancelPractice`-t; a
  `permissionRequired` akció a `PreparePractice`
  (`practice_controls.dart:52-66`), a kilépési táblák a mért
  `allowedTransitions`-t tükrözik.
- **A9** — nulla sor a legacy úton és az application/domain/data rétegekben.

## 7. Merge-döntés a `7223496`-on (történeti)

**A merge TILOS volt**, amíg a három MAJOR nyitva volt. A gate és a CI zöld, a
scope tiszta — a leletek tartalmiak voltak, és mindhárom felhasználó-látható
viselkedést érintett (dupla hibakártya, átszivárgó hiba, a11y-csatornára
küldött nyers kulcs).

A lánc ekkor **HALT-tal állt meg (H4)**, mert az akkori ADR 0087 §2 az
orchestrátor autonómiáját **egy** javító körre korlátozta. A user
**2026-07-31-i döntése** (`679ce4c`, `16f776f`) a küszöböt **három** javító
körre emelte, és a negyediket a Codexhez rendelte — a HALT feloldva, a javító
kör #2 ezen a szabályon indult. **Az aktuális merge-döntés a §9-ben.**

## 8. A javító kör #2 findings-listája (a promptban kiadva)

1. **MAJOR-1** — egy hibafelület a `failed` + `ShowRecoverableError`
   kombinációra; zárótesztnek ezt a kombinációt kell mérnie.
2. **MAJOR-2** — az overlay-állapot a képernyő élettartamához kötve;
   záróteszt: be-/ki-/belépés után 0 örökölt hibafelület.
3. **MAJOR-3** — az `AnnounceAccessibilityFeedback` a brief A3 cellája
   szerint, és a teszt a `_RecordingFeedback.announcements` listát mérje.
4. **MINOR-1** — `StateProvider` → kézzel írt `Notifier`, a legacy import
   megszűnésével.

Az engedélyezett fájllista **változatlan** (brief §4); a fenti négy tétel
mind azon belül zárható.

---

## 9. Review #2 — a javító kör (`42c8f97`) zárás-ellenőrzése

**Klón:** `/tmp/review-e02r13-fix2` (`git clone --branch mm/e02-r13-session-ui-shell`),
read-only review, production kód nem íródott.

### 9.1 Gate — függetlenül újrafuttatva

```
tools/round-gate.sh test/features/practice/ test/core/l10n_parity_test.dart \
  test/core/screen_size_guard_test.dart test/tooling/route_literal_guard_test.dart
```

```
format zöld · analyze zöld · test test/features/practice/ zöld (+689) ·
test test/core/l10n_parity_test.dart zöld · test test/core/screen_size_guard_test.dart zöld (+39) ·
test test/tooling/route_literal_guard_test.dart zöld · architecture zöld
GATE_EXIT=0
```

A practice suite **686 → 689** (a három új záró cella). Mért reviewer-tanulság:
a friss klónban a **generált l10n hiányzik** (gitignore), ezért az `analyze` 490
hibával pirosat ad, amíg le nem fut a `flutter gen-l10n` — ez klón-artefaktum,
nem a kör hibája (a fenti zöld futás a generálás UTÁN készült).

### 9.2 Scope-audit

`git diff --stat 2e38606..42c8f97`: **4 fájl** — a két érintett `lib/`
presentation-fájl (**37 sor**), a `practice_session_screen_test.dart` és a
brief. A brief diffje a **383. sortól** kezdődik, ami pontosan a `## 10.
Implementation handoff` első sora → a **§1–§9 (a szerződés) érintetlen**.
Listán kívüli fájl nincs; törölt tesztcella nincs
(`git diff … | grep -E "^-\s*(testWidgets|test)\("` → üres).

### 9.3 Mutációs próbák — a zárások hitelesítése

A kérdés nem az, hogy zöld-e, hanem hogy a **záróteszt pirosra váltana-e** a
hiba visszaállításakor. Mindhárom mutáció a klónban futott, utána visszaállítva
(`git status --short` üres).

| # | Mutáció | Elvárt piros cella | Eredmény |
|---|---|---|---|
| M1 | a `if (_state.status != failed)` őr eltávolítása az `_RecoverableErrorOverlay` elől | `failed + ShowRecoverableError renders one panel and one error title` | **PIROS — pontosan ez az egy cella** |
| M2 | `case AnnounceAccessibilityFeedback(:final messageKey): output.announce(messageKey);` visszaállítása | `A3 … AnnounceAccessibilityFeedback("anything") → 0 calls, no throw` | **PIROS — pontosan ez az egy cella** |
| M3 | `NotifierProvider.autoDispose` → sima `NotifierProvider` | `leave and re-enter in the same ProviderScope shows no stale error` | **PIROS — pontosan ez az egy cella** |

Mindhárom mutáció **egyetlen**, a lelethez tartozó cellát vált pirosra — a
mérce célzott, nem véletlen kollaterális.

### 9.4 Leletenkénti zárás

- **MAJOR-1 — zárva.** `practice_session_screen.dart:116` — az effekt-vezérelt
  overlay `failed` alatt el van nyomva, a státusz-vezérelt `PracticeErrorPanel`
  marad az egyetlen felület. **Nem nyit új lyukat:** a reducerben egyetlen hely
  állít `status: failed`-et (`practice_session_reducer.dart:612`), és ugyanaz a
  `copyWith` tölti a `recoverableFailure`-t (`:613`) — tehát `failed` mellett a
  státusz-vezérelt panel **mindig** rendelkezésre áll. Mérve: M1 mutáció.
- **MAJOR-2 — zárva.** `practice_effect_listener.dart:73-88` — a `StateProvider`
  helyén kézzel írt `PracticeErrorOverlayController extends Notifier<AppFailure?>`
  `NotifierProvider.autoDispose` mögött: a képernyő elhagyásakor az utolsó
  figyelő is elmegy, a tároló eldobódik, az új belépés friss állapottal nyit.
  Mérve: a be-/ki-/belépés cella + M3 mutáció.
- **MAJOR-3 — zárva.** `practice_effect_listener.dart:129-132` — az ág
  dokumentáltan elnyeli az effektet (nyers kulcs nem megy a képernyőolvasó
  csatornára), a `PlatformPracticeFeedbackOutput.announce` implementációja
  (M2-lelet zárása) érintetlen. A cella most a `_RecordingFeedback.announcements`
  **listát** méri (`isEmpty`), nem csak a haptikát. Mérve: M2 mutáció.
- **MINOR-1 — zárva.** `grep -rn "flutter_riverpod/legacy" lib/` → **üres**, és
  egy guard-cella (`no flutter_riverpod legacy import remains under lib`) tartja
  is így.

### 9.5 Új NOTE

**NOTE-3 — a `running` úton érkező recoverable hiba mérése közvetett.** A
javító kör #1 M3-előírása („`running` alatt érkező `ShowRecoverableError` →
panel látszik, státusz változatlan, **nulla parancs**") ma nem külön cellában
él: a panel megjelenését a be-/ki-/belépés cella méri (`running` státuszban
emittált effekt → hibacím megjelenik), a „státusz változatlan / 0 parancs"
felet viszont egyik cella sem állítja explicit. A **viselkedés** helyes — a
listener `ShowRecoverableError` ágán semmilyen parancs-kiadás nincs, és a
listenernek nincs is host-referenciája parancsküldéshez —, ezért ez
**coverage-hiány, nem hiba**: nem blokkol, follow-upként az E02-R14 körben
egy dedikált cellával zárható.

### 9.6 Merge-döntés

**APPROVED.** Nulla nyitott BLOCKER/MAJOR/MINOR. A gate mind a hét lépése
függetlenül zöld, a scope tiszta, mind a négy zárás mutációval hitelesítve.
A merge a zöld kapu (ADR 0052) gépi felének teljesülésekor mehet: a
CI-run a `42c8f97`-en, `headSha` ↔ lokális HEAD egyeztetve (L21).
