# E13-R08 review — Adaptive scaffold és primary navigation

- **Kör:** `E13-R08` · **PR:** [#432](https://github.com/wolfcasaba/strumsight/pull/432)
- **Branch:** `sonnet-impl/e13-r08-adaptive-scaffold-and-navigation`
- **Reviewelt HEAD:** `f1add05c` (implementáció) a `6f35030b` pre-flight fölött
- **Implementer:** `sonnet-impl` (Claude Sonnet 5) · **Reviewer:** Claude (Opus 5)
- **Dátum:** 2026-08-23
- **Verdikt:** **CHANGES REQUESTED** — 1 MAJOR, 1 MINOR, 2 NOTE

---

## 1. Jelzés és handoff

`.codex-round-status`: `status=done`, `head=f1add05c`, `dirty_files=1`.

A `dirty_files=1` **kivizsgálva**: a jelzés pillanatában a brief §10 handoff
írása volt folyamatban; a `git status --short` a jelzés után **üres**, és a
brief-változás (114 sor) benne van az `f1add05c` commitban. Nincs elveszett
munka.

A brief §10 handoffja kitöltött, és a §6.3 mindkét valódi-sértés próbáját
dokumentálja. **Bemondásra semmit nem fogadtam el** — a gate-et és a leleteket
saját kézzel mértem.

## 2. Gate — saját újrafuttatás izolált klónban

```
git clone --branch sonnet-impl/e13-r08-… https://github.com/wolfcasaba/strumsight.git /tmp/review-e13-r08
tools/round-gate.sh test/app/navigation/adaptive_scaffold_test.dart test/app/navigation/legacy_route_redirect_test.dart test/app/navigation/tab_state_restoration_test.dart
```

```
    format                                                     zöld
    analyze                                                    zöld
    test test/app/navigation/adaptive_scaffold_test.dart       zöld
    test test/app/navigation/legacy_route_redirect_test.dart   zöld
    test test/app/navigation/tab_state_restoration_test.dart   zöld
    architecture                                               zöld
    secrets                                                    zöld
    l10n                                                       zöld
```

**Kilépési kód 0.** A gate zöld — és pontosan ezért érdemes emlékezni a
protokoll alapelvére: *a zöld gate nem bizonyíték*. Az alábbi MAJOR-t a gate,
a CI és a kör mind a nyolc cellája átengedte.

## 3. Scope-audit

```
$ python3 tools/scope-audit.py --repo /home/ubuntu/ss-sonnet-impl-e13-r08 \
    --brief docs/rounds/e13-r08-adaptive-scaffold-and-navigation.md --base 6f35030b
Legacy scope audit OK (6f35030bc867..f1add05c8bd4, 11 changed path(s), 0 generated/ignored)
```

**OK** — mind a tizenegy útvonal az `allowed_paths` listán belül. A tiltott
zónához (`lib/features/**`, `lib/l10n/**`, `test/app/routing/**`, `tools/**`,
`.github/**`, `docs/adr/**`) a kör **nem nyúlt** — a `lib/l10n/**` kísértését
az implementer helyesen a D10 meglévő öt ARB kulcsával oldotta fel.

## 4. Acceptance criteria — tételesen

| # | Kritérium | Bizonyíték | Verdikt |
|---|---|---|---|
| A1 | Öt destination + 11 alútvonal a flag BE ágán, path-onként egyszer; flag defaultból KI, mind a HAT bővülési ponton | `adaptive_scaffold_test.dart:117–259` — külön cella a bare-konstruktor defaultra, a `forEnvironment`-re minden környezetben, az `==`/`hashCode` részvételre és a `toString()`-re; + „each destination path is registered exactly once" | ✅ |
| A2 | 11 legacy redirect, query + fragment megőrizve | `legacy_route_redirect_test.dart:151–217` — mind a 11 route a cél-adapterre resolvál; `/library?tab=sessions&sort=recent#top` → path `/profile/library`, query és fragment változatlan; + a „nincs query" tiszta eset | ✅ |
| A3 | A kiválasztott tab stackje túléli a tabváltást | `tab_state_restoration_test.dart` — push `/practice/chords` → tabváltás **a valódi nav-gombbal** → vissza → még mindig a `ChordLibraryScreen`-en, és a `pageBack()` normálisan popol | ✅ |
| A4 | Stage-halmazon nincs primary navigation | `adaptive_scaffold_test.dart:261–377` — predikátum-cella a kipinnelt halmazra **és** a produkciós `AdaptiveHomeShell` widget közvetlen felpumpálása | ✅ (de lásd NOTE-1) |
| A5 | A redirect-térkép a D7 négy szerződését teljesíti | `legacy_route_redirect_test.dart:117–149` — `k != v`; `values ∩ keys == ∅`; a kulcshalmaz pontosan a pinnelt 11; a pinnelt térkép 1:1 a produkcióssal; `/songs` NEM kulcs | ✅ |
| A6 | Minden breakpointon a helyes navigációs forma | `adaptive_scaffold_test.dart:378–470` — a §6.2 **hat** cellája (599/600/839/840/1199/1200) + widget-szintű ellenőrzés compact/medium/expanded/wide szélességeken | ✅ |
| A7 | A flag KI ágán a mai navigáció változatlan | a `HomeShell` diffje érintetlen; a redirect `if (!adaptiveShellEnabled) return null`; a `test/app/routing/**` **módosítatlan** és zöld; a reviewer legacy-referencia próbája is zöld (§5) | ✅ |

A `modeForWidth` **kizárólag** `SsBreakpoints` tokenekből számol — `600`,
`840`, `1200` literál nincs a production kódban (D3 ✅). A design-system
határőr zöld: az `ss_adaptive_scaffold.dart` nem importál feature-t, és a
`home_shell.dart` a `public.dart`-on át ér el hozzá (D4 ✅).

## 5. Próbatesztek (eldobhatók — merge előtt törölve)

`/tmp/review-e13-r08/test/app/navigation/zz_reviewer_probe_test.dart`, három
cella. A kérdés, amit a kör egyetlen cellája sem tesz fel: **az új shell alatt
mi történik egy erőforrás-birtokló képernyővel, ha a felhasználó másik
destinationre vált?**

A mérce a **legacy referencia**, amit a `lib/app/home_shell.dart` doc-commentje
szó szerint kimond: *„switching tabs disposes the previous screen (so the Live
engine + wakelock stop when you leave Live)"*.

```
00:01 +1: LEGACY REFERENCE (flag OFF): leaving Live disposes LiveScreen and releases the screen wakelock
        → ZÖLD: /live → /analyze után LiveScreen findsNothing, wakelock.isHeld == false

PROBE offstage LiveScreen instances after tab switch: 2
PROBE wakelock.isHeld after tab switch: true (enableCalls=2, disableCalls=0)
        → PIROS: NEW SHELL (flag ON), /today → „Song library" tabváltás

PROBE /practice/live offstage instances after tab switch: 1
PROBE /practice/live wakelock.isHeld: true
        → PIROS: NEW SHELL (flag ON), /practice/live → „Song library" tabváltás
```

A legacy cella **zöld** — az invariáns valós és mérhető. Az új shell alatt
mindkét cella **piros**. Ez a MAJOR-1 bizonyítéka.

## 6. Leletek

### MAJOR-1 — az új shell nem engedi el a mikrofont és a képernyő-wakelockot destination-váltáskor

**Hol:** `lib/app/routing/app_router.dart:361–455` (a `StatefulShellRoute.indexedStack`
öt branch-e), különösen a `today` branch (`app_router.dart:368–375`) és a
`practiceLive` route (`app_router.dart:385–388`).

**Mit mértem.** `StatefulShellRoute.indexedStack` — helyesen, az A3 miatt —
`IndexedStack`-ben **életben tartja** minden meglátogatott branch navigátorát.
A `LiveScreen` viszont erőforrás-birtokló képernyő:

- `live_screen.dart:58–62` — `initState()` → `_wakelock.enable()`;
- `live_screen.dart:165` — `build()` → `ref.watch(liveFrameProvider)`, ami egy
  `StreamProvider.autoDispose<LiveFrame>` (`live_providers.dart:19`), tehát a
  **mikrofon-stream addig él, amíg valaki figyeli**;
- `live_screen.dart:90–108` — `dispose()` → `_wakelock.disable()`.

A tabváltás után a `LiveScreen` **nem** unmountol, tehát sem a `dispose()`, sem
az `autoDispose` nem fut le: a mikrofon-stream és a képernyő-wakelock **aktív
marad, miközben a felhasználó egy másik területen van**. Mérve:
`enableCalls=2, disableCalls=0`, `isHeld == true`.

**Két, egymástól független manifesztáció:**

1. **Retenció.** Bármely branch, amelyben `LiveScreen` van, a meglátogatása
   után is mountolva marad.
2. **Kettőzés.** A `LiveScreen` **két** branchben van regisztrálva — `/today`
   (D6 tábla) és `/practice/live` —, ezért a próba **2** offstage példányt mért.
   Két `LiveScreen` State egyszerre kezeli ugyanazt a wakelockot és ugyanazt az
   `autoDispose` stream-et; a lifecycle-hookok (`didChangeAppLifecycleState`,
   `ref.invalidate(liveFrameProvider)`) párban futnak.

**Miért MAJOR.** (a) Dokumentált invariánst tör meg, amit a legacy shell
szándékosan tartott; (b) a Ch13 §7.4 kifejezetten előírja, hogy a
*„mikrofon/kamera ownership route lifecycle-hoz kötött"*; (c) **adatvédelmi
dimenziója is van** — a mikrofon aktív marad olyan képernyőn, ahol a
felhasználó nem számít rá; (d) a kör egyetlen cellája sem méri, és a teljes
gate + CI zöld mellett csúszott át.

**Enyhítő körülmény:** a flag defaultból KI, tehát ma nincs felhasználói
hatás. A hiba **latens**, nem éles.

**A brief felelőssége.** A §0.0 D6 táblája rendelte a `/today` adapterének a
`LiveScreen`-t (nincs Today képernyő) — a kettőzést tehát a brief okozta, nem
az implementer önkénye. Ettől a lelet nem kevésbé valós.

**Javasolt irány (NEM kész patch), a fix-kör választhat:**

- a `/today` adaptere legyen erőforrás-mentes képernyő (a `LessonListScreen`
  vagy a `ProgressScreen` kézenfekvő), hogy a kettőzés megszűnjön; **és**
- a `/practice/live` vagy kerüljön ki a shell-branchből (a session-route-okhoz
  hasonlóan top-level, ahol a mai dispose-szemantika érvényben marad), vagy
  kapjon látható/nem-látható jelzést (`navigationShell.currentIndex` vs. a saját
  branch indexe), amire a `LiveScreen` elengedi az erőforrásait.
- **Kötelező mérce:** a javításhoz tartozzon cella, ami a MOSTANI állapotot
  PIROSRA fogja — a reviewer próbájának két piros cellája közvetlenül
  átemelhető a `test/app/navigation/`-be.

### MINOR-1 — az adaptív shell megkerüli két másik feature rollout-flagjét

**Hol:** `app_router.dart:378–382` (`practiceHub` a Practice branchben) és
`app_router.dart:425–430` (`coachHome` a Coach branchben).

A `StatefulShellRoute` egésze **csak** az `adaptiveShellEnabled`-tól függ, ezért
a flag bekapcsolása elérhetővé teszi a `PracticeHubScreen`-t akkor is, ha
`practiceEngineV2Enabled == false`, és a `TutorHomeScreen`-t akkor is, ha
`aiTutorEnabled == false`. A legacy ágon mindkettő a saját flagje mögött van
(`app_router.dart:292`, `:456`).

**Bizonyíték a kör SAJÁT tesztjéből:** a `tab_state_restoration_test.dart`
flag-halmaza csak `adaptiveShellEnabled: true`-t állít (a
`practiceEngineV2Enabled` a konstruktor-defaulton `false` marad), és a teszt
mégis sikeresen navigál `/practice`-re, ahol `PracticeHubScreen`-t talál.

Egy navigációs flag nem billenthet át két termék-rollout kaput. **Javasolt
irány:** a két branch-route kapja meg a saját `if (practiceEnabled)` /
`if (aiTutorEnabled)` őrét (a destination maradhat, csak a hub-route essen ki,
vagy a destination is — ez termékdöntés, a legszűkebb változat a route-őr).
Kétsoros javítás, a fix-körben elfér.

### NOTE-1 — az `isStageRoute` produkciós hívási úton ma nem érhető el stage-lokációval

A három stage route (`/practice/session`, `/song-trainer/session/:songId`,
`/vision/session`) a shellen **kívül** van regisztrálva, ezért az
`AdaptiveHomeShell` sosem rendereli őket — a primary navigation elrejtése ma
szerkezetileg valósul meg, nem a predikátumon át. Ez **nem hiba**: a brief
§0.0 D13 pontosan ezt írta elő (a Stage-esítés a Kör 9 dolga), és az
anti-vakuum követelmény teljesült — az A4 widget-cellája a produkciós
`AdaptiveHomeShell`-t közvetlenül pumpálja fel stage-lokációval, tehát a mérce
valódi. Nyilvántartva, hogy a Kör 9 tudja: a predikátum kész, a bekötés ott
válik élővé.

### NOTE-2 — `isStageRoute('/song-trainer/session/')` igazat ad üres `songId`-ra

`adaptive_shell_routes.dart:39–41`: a prefix utáni üres maradék nem tartalmaz
`/`-t, tehát a predikátum `true`-t ad. Ilyen URL a gyakorlatban nem áll elő
(a `GoRoute` sem illesztené), a felszín kozmetikai. Nem blokkol.

## 7. Amit külön ellenőriztem, és rendben van

- **D6 hurok-csapda.** A `legacyRedirects` mind a 11 célja regisztrált a flag BE
  ágán — a próbám nem tudott `onException` → `/live` oda-vissza hurkot
  előidézni; az „all eleven legacy routes resolve to their target adapter"
  cella `tester.takeException()`-nel is méri.
- **Duplikált path.** A legacy `/practice` és `/songs` regisztráció
  `!adaptiveShellEnabled` mögé került, és az implementer **szándékosan** a
  feltételes blokkok UTÁN deklarálta a `StatefulShellRoute`-ot, hogy egy jövőbeli
  hiányzó őr a first-match miatt megfigyelhető legyen. Ez jó mérnöki döntés.
- **`goBranch`, nem `context.go`** (D9) — az A3 cella a valódi nav-gombot
  koppintja, tehát a `context.go`-ra visszaesés pirosra váltana.
- **`uri.replace(path:)`** (D8) — nem string-konstans, a query és a fragment is
  átmegy; külön cella méri mindkettőt.
- **ARB** — nincs új kulcs, az öt címke meglévő kulcsokból jön, a kötött
  `TODO(E13-R16)` komment a helyén.

## 8. Biztonsági megjegyzés (risk = "high")

A brief `risk = "high"`, de a §0.0 indoklása szerint ez **hatókör-kockázat**,
nem adatvédelmi/hálózati: a `.ai/router.toml` `high_risk_path_fragments`
listájából egyetlen töredék sem illeszkedik, és a diff nem érint hálózatot,
tárolást, hitelesítést, engedélykérést, AI-provider hívást, importált fájlt
vagy felhasználói adatot — tisztán navigáció. Külön security-reviewer futtatása
ezért nem indokolt; az **egyetlen** adatvédelmi vonatkozású felszín a
**MAJOR-1 mikrofon-retenciója**, amit ez a jelentés fent kezel.

## 9. Merge-döntés

**CHANGES REQUESTED.** A MAJOR-1 nyitva → merge tilos. A javító kör a lánc
normál útja: ugyanaz a motor (`sonnet-impl`), a fenti leletlistával.

A fix-kör után: a gate + a CI **újra** dispatch-elendő (a kód változik), és
ez a jelentés leletenként frissítendő.
