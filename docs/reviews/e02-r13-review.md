# E02-R13 review — Practice Session UI shell (ADR 0079)

- **Kör:** [`docs/rounds/e02-r13-session-ui-shell.md`](../rounds/e02-r13-session-ui-shell.md)
- **Branch:** `mm/e02-r13-session-ui-shell` · **HEAD:** `7223496`
- **Implementer motor:** **MiniMax M3** (pipeline-vezérelt kör, ADR 0087)
- **Reviewer:** Claude (Opus 5), read-only, izolált klón (`/tmp/review-e02r13`)
- **Dátum:** 2026-07-31
- **Verdikt:** **CHANGES REQUESTED — 0 BLOCKER · 3 MAJOR · 1 MINOR · 2 NOTE**
- **A lánc állapota:** **HALT (H4)** — a három MAJOR az **első javító kör után**
  keletkezett leletként nyitva van, ezért a merge tilos és a döntés emberre vár.

## 1. A kör lefolyása

| Fázis | Eredmény |
|---|---|
| Pre-flight | ADR 0079 megírva; a brief **nyolc** állítása mérve és javítva (§0.0) |
| Első implementer-futás (`42a5c24`) | kód kész, **nulla teszt** — a §10 az A1–A9-et „struktúrával" tekintette teljesítettnek és a gépi mércét a review-ra hárította |
| Javító kör #1 (`7223496`) | mind a nyolc lelet (B1–B4, M1–M4, m1) zárva, **két tesztfájl / 45 cella**, a practice suite 641 → **686** |
| Review (ez a jelentés) | gate zöld, scope tiszta, **3 új MAJOR** eldobható próbatesztekkel kimérve |

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

## 7. Merge-döntés

**A merge TILOS**, amíg a három MAJOR nyitva van. A gate és a CI zöld, a scope
tiszta — a leletek tartalmiak, és mindhárom felhasználó-látható viselkedést
érint (dupla hibakártya, átszivárgó hiba, a11y-csatornára küldött nyers kulcs).

**A lánc HALT-tal áll meg (ADR 0087 §2 / H4):** az orchestrátor autonómiája
egy javító körre szól, azt elhasználtuk, és a review után MAJOR-leletek
maradtak nyitva. Az emberi döntés kérdése: **engedélyezhető-e egy második
javító kör ugyanezzel a motorral** (a három lelet kicsi, jól körülírt,
ADR-t nem érint), vagy a kör átkerül a Codexhez.

## 8. A javító kör findings-listája (ha a user engedélyezi)

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
