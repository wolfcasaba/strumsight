# E12-R11 review — End-to-end test harness

- **Reviewer:** Claude (Opus 5), orchestrátor-oldali független review (ADR 0055)
- **Dátum:** 2026-08-29
- **Ág:** `sonnet-impl/e12-r11-end-to-end-test-harness` @ `4f22dc44`
- **Implementer:** `sonnet-impl` (Claude Sonnet 5, `--effort high`)
- **Brief:** [`docs/rounds/e12-r11-end-to-end-test-harness.md`](../rounds/e12-r11-end-to-end-test-harness.md)
- **ADR:** [`0472`](../adr/0472-e2e-flow-harness-runs-in-the-flutter-test-host.md)

> **2026-08-29 — MÁSODIK KÖR (javító kör a H2-heal után).** A lenti B1 BLOCKER
> **ZÁRVA**. A végső verdikt a fájl alján: [**APPROVED**](#vegso-dontes-2-kor-approved).
> Az alábbi, első köri jelentés a történeti rekord — a mérései a `4f22dc44`
> commitra igazak, nem a mai ágcsúcsra.

## ELSŐ KÖR — VÉGSŐ DÖNTÉS: **CHANGES REQUESTED → HALT (H2)**

Egy **BLOCKER** lelet, amely a kör szerződésén belül **nem javítható**: a
feloldás egy lezárt, merge-elt kör `lib/**` viselkedésének megváltoztatását
kívánja (ADR 0087 §2 **H2**), amit a brief §3 tilos zónája is kizár.

## Gépi ellenőrzések

| Ellenőrzés | Eredmény |
|---|---|
| Scope-audit (`tools/scope-audit.py --base 545821ae`) | **OK** — 7 változott útvonal, mind az `allowed_paths`-on |
| `dirty_files=1` a jelzésben | **tisztázva** — a §10 handoff commitja (`4f22dc44`) a jelzés után landolt; `git status --short` üres |
| Diff terjedelme | 8 fájl, +1151/−13 — `lib/**` érintetlen |
| Kör-jelzés | `status=done`, head `4f22dc44` = a lokális és a CI `headSha` |
| CI (`full-gate.yml` #33223623295) | dispatch-elve a pontos HEAD SHA-n (a merge elmarad, lásd a döntést) |

## BLOCKER

### B1 — Az A1 („a folyam a VALÓDI app-fán megy") nem teljesül: a harness pótolja azt a láncszemet, amit a terméknek kellene megtermelnie — és a kör ilyenkor a saját STOP-protokollja szerint `stopped`, nem `done`

**Mit mértem (függetlenül, a `lib/` fán):**

```
grep -rn "AppRoutes.practiceSession" lib/
  lib/app/routing/adaptive_shell_routes.dart:41   (stage-route predikátum)
  lib/app/routing/app_router.dart:342             (útvonal-regisztráció)
  lib/app/routing/app_route.dart:24               (a konstans maga)
grep -rn "'/practice/session'" lib/     → csak az app_route.dart konstans
```

Egyetlen `lib/**` hívó sem navigál a `/practice/session` útvonalra. A Setup
képernyő Start-gombja (`practice_setup_screen.dart:262–277`) `controller.start()`-ot
hív, majd **SnackBar**-t mutat — és ott is marad. Az egyetlen production
navigáció a practice-fán a `practice_effect_listener.dart:119`
(`router.go(AppRoutes.practiceResult)`).

**Következmény:** a „first practice" vertical slice a szállított appban
**nem járható végig**. A `PracticeSessionScreen` a termék saját felületéről
elérhetetlen.

**Amit a harness tesz helyette** (`test/support/e2e_harness.dart`):

- `:281` — `session.router.go(AppRoutes.practiceSession);` — a teszt **maga
  navigál** oda, ahová a termék nem;
- `:275` és `:277` — két `container.read(practiceSessionHostProvider)` a
  Start-tap ELŐTT és UTÁN (pump nélkül közéjük), hogy az autoDispose-lánc ne
  bomoljon le, mert a `lib/**`-ben **nincs** figyelője.

Ez pontosan az [L273](../LESSONS.md#l273) hibaosztálya: a cella „teljes
láncnak" nevezi magát, miközben olyan köztes lépést ad be, amit a lánc maga
nem termel meg. A brief §5.5 és az ADR 0472 D5 ezt kifejezetten tiltja, a §0
STOP-protokollja pedig kimondja a helyes kimenetet:

> „ha a folyam-teszt egy MÉRT termékhibába fut (a flow a valódi appban nem
> járható végig), a kimenet a `stopped` jelzés és jelentés — a `lib/**`
> javítása ebben a körben TILOS, és a teszt »megkerülő« átírása is az."

**Az implementer a hibát MEGMÉRTE és a §10-ben becsületesen dokumentálta**
(„SEHOL a `lib/**`-ben nincs automatikus navigáció a Setup-tól a Session
útvonalig"), majd a `stopped` helyett a harness-ben áthidalta és `done`-t
jelzett. A §10 érvelése („a `container.read` pusztán a Riverpod-figyelőt
regisztrálja, nem ad hozzá vagy hagy ki egy chain-lépést") a két `read`-re
védhető, de a `:281` `router.go`-ra **nem**: az egy hiányzó lánc-lépés pótlása.

Másodlagosan ugyanez a minta a `:241` `router.go(AppRoutes.practiceHub)`-on
(a Hub deep-linkkel nyílik, nem a shell navigációjából) — önmagában enyhébb
(a deep link valódi belépési út), de az A1 „a UI-n keresztül" erejét tovább
gyengíti.

**Miért nem javító kör:** a szerződésen belül csak két kimenet lehetséges —
(a) a folyam harness-pótlás nélkül fut végig, ami `lib/**` módosítás nélkül
**lehetetlen**, vagy (b) `stopped` jelzés + jelentés. Az (a) egy lezárt,
merge-elt kör (Practice V2 wiring) viselkedésének megváltoztatása → **H2**,
és a brief §3 tilos zónája is kizárja. A (b)-t pedig ez a review már
elvégezte — egy javító kör csak ceremónia lenne.

## NOTE — a kör értékes, megtartandó része

Ezek **nem** leletek, hanem a halt utáni döntés bemenetei: a szállított
infrastruktúra nagyrészt jó, és egy újratervezett körben újrahasznosítható.

- **N1 — `fake_network_guard.dart` (ADR 0472 D2) MEGFELEL.** Mindhárom út
  zárva és rögzítve (Dio `HttpClientAdapter`, `dart:io` `HttpOverrides`,
  platform-csatorna catch-all a `TestDefaultBinaryMessenger.allMessagesHandler`-en),
  mindegyikre jut egy önálló A3-cella. A `flutter/` névtér átengedése
  **strukturális** kivétel egy fenntartott névtérre, nem kézzel kiválasztott
  csatorna — az [L453](../LESSONS.md#l453) hibaosztályát valóban zárja. Az
  API-eltérést (a `setMockMessageHandler(null, …)` alak nem létezik) a §10
  a Flutter SDK forrására hivatkozva dokumentálja — helyes eljárás.
- **N2 — A valódi-sértés próba tényleges kimenettel dokumentálva** (§10): a
  guard meggyengítésekor az A3 Dio-cella pirosra váltott
  (`Expected: throws <NetworkGuardViolation>`), a visszaállítás után a gate
  újra zöld. A §6.1 mátrix első sora tehát MÉRVE fog.
- **N3 — Az A4 determinizmus-cella gépi**, ahogy a §0.0/R5 előírta (két
  friss `ProviderContainer`, `expect(second, equals(first))`). Korlát,
  becsületesen kimondva: a `createdAt` mező kimarad a snapshotból, mert a
  production mapper valódi fali órát bélyegez rá — az A4 tehát egy
  projekción bizonyít, nem a teljes entitáson. Ez egy **további** mért
  `lib/**` determinizmus-rés, amit a halt jelentése visz tovább.
- **N4 — Az A2 „újraindítás" a §0.0/R6 kötött alakját követi**
  (`pumpWidget(SizedBox.shrink())` → első container `dispose()` → ÚJ
  container + ÚJ router UGYANARRA a store-példányra).
- **N5 — Az L513 teardown-tiltás betartva** (`E2eSession.dispose` nem
  awaitol broadcast `close()`-t, `unawaited(...)`), és mindkét folyam záró
  `pump(400ms)`-szel fejeződik be.
- **N6 — Az A5 forrás-szintű őr** a §0.0/R4 szerint készült.

## A halt jelentésének lényege (a feloldó session számára)

A megválaszolandó normatív kérdés **nem** teszt-kérdés:

> A Practice V2 Setup → Session navigáció hiányzik a `lib/**`-ből (a Start
> gomb SnackBart mutat és helyben marad), és a `practiceSessionHostProvider`
> autoDispose-lánca figyelő nélkül bomlik le. Ez termékhiba-e, amit egy saját
> kör (ADR-rel) javít — vagy szándékos, nem-kész felület, és akkor a Ch12
> Kör 11 „first practice" E2E útja addig **nem** teljesíthető?

A javítás helye: `lib/features/practice/presentation/screens/practice_setup_screen.dart:262–277`
(a `controller.start()` sikere után navigáció a `AppRoutes.practiceSession`-re),
és a `practiceSessionHostProvider` élettartama
(`lib/features/practice/presentation/practice_effect_listener.dart:99`).
Reprodukció: `grep -rn "AppRoutes.practiceSession" lib/` → nulla hívó.

A kör ága, a harness és a review a helyén marad — a döntés után a
`test/support/e2e_harness.dart` `:275/:277/:281` áthidalásainak eltávolításával
és a §7 gate újrafuttatásával a kör befejezhető.

---

# MÁSODIK KÖR — javító kör a H2 önjavító kör után (2026-08-29)

- **Reviewer:** Claude (Opus 5), orchestrátor-oldali független review (ADR 0055)
- **Ág:** `sonnet-impl/e12-r11-end-to-end-test-harness` @ `16208570`
- **Bázis:** `64563cf0` (a `origin/main @ 8e75e4f9` merge-e a kör ágába)
- **Előzmény:** a B1-et kiváltó **termékhibát** a H2 önjavító kör javította
  ([ADR 0470](../adr/0470-practice-setup-navigates-to-the-session-route.md),
  PR #499, `main @ 8e75e4f9`), és a brief §0.0 kötött feladatot adott az
  újrafuttatásra.

<a id="vegso-dontes-2-kor-approved"></a>
## VÉGSŐ DÖNTÉS: **APPROVED**

A **B1 BLOCKER ZÁRVA**; új BLOCKER/MAJOR/MINOR lelet nincs. A merge a zöld
kapun mehet.

## A B1 zárásának bizonyítéka — falszifikációs próba, nem a zöld gate

A zöld gate önmagában NEM bizonyítja, hogy az áthidalás megszűnt: egy áthidalt
teszt is zöld. A döntő mérés az, hogy a folyam MOST **elbukik**, ha a termék
lánc-lépését elveszem. Az izolált review-klónban (`/tmp/ss-review-e12-r11`,
`16208570`) kivettem a heal navigációját
(`practice_setup_screen.dart:198`, `context.go(AppRoutes.practiceSession)`),
mindent mást változatlanul hagyva:

```
flutter test test/e2e/first_practice_offline_test.dart
  00:03 +3 -2: Some tests failed.
  Failing tests:
    A1/A2 — first offline practice session (real StrumSightApp tree) …
    A4 — determinism: the same flow run twice yields the same result …
```

A próba visszaállítása után (`git checkout -- …`) a fa érintetlen. Tehát az
**A1 és az A4 immár a termék saját navigációjától FÜGG** — pontosan az a
tulajdonság, aminek a hiánya az első körben a B1 volt. Az [L273](../LESSONS.md#l273)
hibaosztálya ezzel zárva: a lánc-lépést a termék termeli meg, nem a teszt.

## A §0.0 kötött feladat leletenkénti zárása

| # | Kötött feladat | Mérés | Állapot |
|---|---|---|---|
| 1 | a két `container.read(practiceSessionHostProvider)` a Setup-tap körül **törölve** | `git diff 64563cf0 HEAD -- test/support/e2e_harness.dart` → mindkét hívás és a már nem igaz kommentblokk (18 sor) törölve | **ZÁRVA** |
| 2 | a `session.router.go(AppRoutes.practiceSession)` **törölve** | ugyanaz a diff; a `runFirstPracticeSession` a Setup-tap után csak `pumpAndSettle`-t hív, a következő interakció már a Session-képernyő `Start` gombja | **ZÁRVA** |
| 3 | a SnackBar-ra váró `pump(5s)` **kivéve**, vagy a maradék MÉRT indoka a §10-ben | törölve, pótló pump nélkül; a §10.0 kimondja, hogy a folyam enélkül is settle-öl | **ZÁRVA** |
| 4 | a Hub deep link (`:241`) maradhat, de a §10 nevezze meg tudatosnak | §10.0/4. pont kimondja | **ZÁRVA** |
| 5 | `lib/**` érintetlen (tilos zóna) | a diff 2 fájl: `test/support/e2e_harness.dart`, `docs/rounds/e12-r11-…md` | **ZÁRVA** |
| 6 | az A4 `createdAt`-kihagyása MARAD (N3, önálló kör tárgya) | a snapshot-projekció változatlan | **ZÁRVA** |

## Gépi ellenőrzések

| Ellenőrzés | Eredmény |
|---|---|
| Upstream-szinkron (§0.3) | `git merge-base --is-ancestor origin/main HEAD` → **0**; a `main` merge-elve (`64563cf0`), nem rebase/force-push |
| Merge-konfliktus feloldása | KIZÁRÓLAG `docs/rounds/e12-r11-…md` (mindkét oldal §0.0-t adott) — a brief §0.0 és az ADR 0112 H8 által előre jelzett szűk, dokumentációs osztály. A `main`-oldali H2-revízió a §0.0, az ág pre-flight revíziója (R1–R7) §0.0.1-ként megőrizve (a §6 mátrix `§0.0/R4–R6` hivatkozásai erre épülnek) |
| Gépi scope-audit | `scope_audit=ok`, `scope_audit_base=64563cf0`, 2 változott útvonal — mind az `allowed_paths`-on |
| `dirty_files=1` a jelzésben | **tisztázva** — a jelzés utáni pillanatkép; `git status --short` a munkapéldányon **üres**, a HEAD (`16208570`) mindent tartalmaz |
| Izolált gate (review-klón, `16208570`) | **MINDEN GATE ZÖLD** — format · analyze · `test/e2e/` · `practice_setup_navigation_test.dart` · architecture · secrets · l10n |
| Router CI (`33227889860`) | `conclusion=success` a `16208570` headSha-n |
| Full Gate (`33227890047`) | dispatch-elve a `16208570` headSha-n — a merge-kapu exact-SHA feltétele |
| Kör-jelzés | `status=done`, `head=16208570` = a lokális HEAD = a CI `headSha` |

## NOTE (nem lelet)

- **N7 — A `_driveSessionUntil` `container.read(practiceSessionHostProvider)`-je
  MARAD, és ez helyes.** Az nem lánc-lépés pótlása, hanem **megfigyelés**: a
  ciklus a folyam állapotát olvassa, hogy eldöntse, mikor kell a fake órát
  továbbléptetni. A fenti falszifikációs próba ezt igazolja is — ha ez a `read`
  pótolná a hiányzó láncot, a próba zölden maradt volna.
- **N8 — A §10 történeti szövege megmaradt, de `[TÖRTÉNETI, … OKAFOGYOTT]`
  jelöléssel** és a valóságnak megfelelően átírva. Ez helyes eljárás: az első
  futás mérési munkája dokumentum marad, de már nem állít valótlant a mai fáról.
- **N9 — Az első köri N1–N6 megállapítások változatlanul állnak** (network guard
  három útja, A2 újraindítási alak, A5 forrás-szintű őr, L513 teardown-tiltás);
  ez a javító kör egyiküket sem érintette.
