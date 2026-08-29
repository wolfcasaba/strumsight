# E12-R11 — End-to-end test harness

- **Státusz:** READY (pre-flight elvégezve 2026-08-28, `main @ 8bdcfff9` — lásd §0.0)
- **Típus:** Chapter 12 (Release Roadmap, Sprint Planning & Final Integration), Kör 11
- **Kör-azonosító:** `E12-R11`
- **Branch:** `<motor>/e12-r11-end-to-end-test-harness`
- **Előfeltétel:** `E12-R05` merge-elve (a flag-katalógus adja a determinisztikus bootstrap-profil kapcsolóit)
- **Brief szerzője:** Claude (Opus 5)
- **A kör ADR-je:** [`ADR 0472`](../adr/0472-e2e-flow-harness-runs-in-the-flutter-test-host.md) — a foglaló adta (§0.0/R1). Az előre írt `0452` NEM kerül felhasználásra.

**Visszakeresett előzmény:** `node tools/knowledge-rag.mjs --corpus lessons,halts,adr --top 5 "integration test harness fake clock network storage deterministic bootstrap"` → **[L122](../LESSONS.md#l122)** (szinkron fake-óra + aszinkron `StreamController`: a listenerben felfegyverzett timer a ROSSZ `now`-hoz köt) és **[L453](../LESSONS.md#l453)** (egy csatorna-specifikus mock handler csak azt az EGY csatornát bizonyítja — az „ez a widget nem nyit erőforrást" invariáns hozzá kevés). Mindkettő a harness fake-jeinek tervezési kényszere.

> ⚠ **Pre-flight (indítás előtt KÖTELEZŐ):** nézd meg, hogy a `pubspec.yaml` `dev_dependencies` blokkja TARTALMAZZA-e az `integration_test`-et (a megíráskor NEM: csak `flutter_test` és `flutter_lints`), és mérd meg a `test/support/` MEGLÉVŐ fake-készletét (a megíráskor 12 fájl: `fake_audio.dart`, `fake_auth.dart`, `fake_settings.dart`, `fake_practice_session_clock.dart`, …). A harness ezekre ÉPÜL.

## 0.0 Revízió — H2 önjavító kör (ADR 0112), 2026-08-29

Az első futás **H2**-vel megállt: a „first practice" folyam a valódi appban nem
volt végigjárható, mert a `lib/**`-ben **egyetlen hívó sem** navigált a
`/practice/session` útvonalra (a Setup Start-gombja `PreparePractice`-t küldött,
majd SnackBart mutatott és helyben maradt). Az implementer ezt a hiányzó
lánc-lépést a harnessben pótolta — [L273](../LESSONS.md#l273) —, a review pedig
BLOCKER-rel állította meg (`docs/reviews/e12-r11-review.md`, B1).

**Az önjavító kör eldöntötte a normatív kérdést:** ez **termékhiba** volt, nem
szándékosan nem-kész felület — az E02-R12 halasztásának címzett köre (E02-R13)
fájl-szinten ki volt zárva a lezárásából, és utána egyetlen kör allowlistjére
sem került fel ([ADR 0470](../adr/0470-practice-setup-navigates-to-the-session-route.md),
[L541](../LESSONS.md#l541)).

**Ami a `main`-en MEGVÁLTOZOTT az újrafuttatás előtt** (heal PR, ADR 0470):

- a Setup Start-ja érvényes konfiguráció mellett `context.go(AppRoutes.practiceSession)`-nel
  **navigál**, és a korábbi „command sent" SnackBar **megszűnt** (a
  `practiceSetupStarted` ARB-kulcs a helyén maradt, de a képernyő már nem
  használja);
- a Start-kezelő a `start()` előtt és közvetlenül utána olvassa a
  `practiceSessionHostProvider`-t — ez az auto-dispose aktiválási lánc
  élettartam-szerződése, a **termékben** (ADR 0470 D3);
- őrteszt a fán:
  `test/features/practice/presentation/practice_setup_navigation_test.dart`.

**Kötött feladat az újrafuttatásra:**

1. A harness `test/support/e2e_harness.dart` **három áthidalását távolítsd el** —
   a Setup-tap köré tett két `container.read(practiceSessionHostProvider)`-t és
   a `session.router.go(AppRoutes.practiceSession)` hívást. A folyam ezek nélkül
   megy végig; ha nem megy, az ÚJ mérés, és a §0 STOP-protokollja érvényes.
2. A Setup-tap után a SnackBar-ra váró `pump(5s)` **feleslegessé vált** (nincs
   több SnackBar) — ha a folyam enélkül is settle-öl, vedd ki; ha nem, mérd meg,
   mi tartja, és a §10-ben írd le.
3. A Hub-ra vitt `router.go(AppRoutes.practiceHub)` (a review másodlagos
   megjegyzése) **maradhat**: a deep link valódi belépési út. A §10-ben nevezd
   meg, hogy tudatos.
4. Az A4 determinizmus-cella `createdAt`-kihagyása **marad** — az a
   `PracticeSessionResultHistoryMapper` valódi fali órája (E12-R11 review N3),
   önálló kör tárgya, ebben a körben NEM javítod.

Az `allowed_paths` **változatlan**: a `lib/**` továbbra is tilos zóna ebben a
körben.

**Az első kísérlet ága ÉL és újrahasznosítandó:**
`sonnet-impl/e12-r11-end-to-end-test-harness` @ `d7bdb695` — a harness (8 fájl,
+1151/−13) és a review (`docs/reviews/e12-r11-review.md`) rajta van, és a review
N1–N6 szerint a szállított infrastruktúra nagyrészt jó. Ne írd újra a nulláról.

⚠ Az ág a heal ELŐTTI `main`-ről indult, ezért **ez a brief-fájl mindkét oldalon
változott** — pontosan az a szűk, dokumentációs history-konfliktus, amit az
ADR 0112 H8 szakasza ír le. Ha újrahasznosítod az ágat:

```bash
git -C <kör-worktree> merge --no-ff origin/main   # NEM rebase + force-push
```

A konfliktust úgy oldd fel, hogy **ennek a fájlnak a `main`-oldali változatát
őrzöd meg** (az tartalmazza ezt a revíziót); a régi §10 handoff-szöveget alá
írod, nem fölé. Ha a konfliktus nem kizárólag ez az egy fájl, `stopped` jelzés
és jelentés — ne alkalmazz generikus feloldást.

## 0.0.1 Pre-flight brief-revízió (Claude, 2026-08-28, `main @ 8bdcfff9`) — a §0.0/R# hivatkozások ide mutatnak

A `brief-lint` (strict) **nem adott leletet**. Az alábbi revíziók a §1 két mérési
szabályából (elérhetetlen cél-státusz · erőforrás-tulajdonlás a TÉNYLEGES hívási
láncon) születtek, mind kimért paranccsal.

**Visszakeresés (ADR 0312, szűkítve → teljes):** `lessons,halts,adr` →
**[L513](../LESSONS.md#l513)** (a `testWidgets` fake-clock zónája alatt egy
broadcast `StreamController.close()` awaitolása SOSEM tér vissza),
**[L122](../LESSONS.md#l122)** (szinkron fake-óra + aszinkron stream: a
listenerben felfegyverzett timer a ROSSZ `now`-hoz köt),
**[L453](../LESSONS.md#l453)** (egy csatorna-specifikus mock handler csak azt az
EGY csatornát bizonyítja), **[L273](../LESSONS.md#l273)** (a „teljes lánc" cella
nem bizonyított, ha a teszt olyan köztes artefaktumot injectál, amit a lánc maga
nem termel meg); `lessons,halts` → **[L443](../LESSONS.md#l443)** (a csak tiszta
predikátumot hívó küszöb-cella a TILTOTT implementáción is zöld marad),
**[L142](../LESSONS.md#l142)** (a randomizált property-gate boundary-flaky lehet
— körtől független bukás nem halt); teljes korpusz → `sdd/12-…#17.1` (a Kör 11
kötelező E2E útjainak forrás-szövege).

| # | Mért állítás (paranccsal) | Revízió |
|---|---|---|
| **R1** | A brief `ADR 0452`-t írt elő; a kötelező foglaló (`tools/round-slots.py reserve-adr --round E12-R11`, ADR 0171 §1.0.1) **`0472`**-t adott (a fán a legmagasabb `0469`; a `0452` sosem került kiosztásra). Ugyanez a minta az előző körben: az E12-R10 queue-sora `0451`, a merge-elt ADR `0469`. | A kör ADR-je **[0472](../adr/0472-e2e-flow-harness-runs-in-the-flutter-test-host.md)**. A `0452` szám nem kerül felhasználásra. |
| **R2** | `sed -n '/^dev_dependencies:/,/^[a-z]/p' pubspec.yaml` → **csak** `flutter_test` + `flutter_lints ^6.0.0`; `ls test/e2e/` → nem létezik; `ls docs/testing/` → nem létezik; `ls test/support/` → **12 fájl**; `ls test/app/offline_network_guard_test.dart` → létezik. | A §2 minden mért állítása **VÁLTOZATLANUL igaz**; a brief indulhat. |
| **R3** | `grep -rln "StrumSightApp(" test/` → **20+ cella** pumpolja a valódi app-fát (`test/app/routing/onboarding_first_win_test.dart`, `test/app/offline_network_guard_test.dart`, a Ch13 készlet). A `test/features/practice/presentation/practice_routing_test.dart` a `practiceHub → practiceSetup` utat VALÓDI routeren, `PracticeCatalogRepository`-override-dal járja végig. | Az **A1** folyam elérhető: a minta a fán MÉRT. Az e2e cellák EZT a mintát követik (valódi `StrumSightApp` + valódi `routerProvider`), nem újat találnak ki. |
| **R4** | Az **A5** eredeti szövege („a harness nem használ `DateTime.now()`-t és valódi `Random()`-ot") **viselkedésből nem mérhető**: egy elrejtett valódi idő a zöld futásból nem látszik. Az [L453](../LESSONS.md#l453) őr-mintája (forrás-szintű cella) viszont igen. | Az **A5** cellája a harness FORRÁSÁT olvassa (`File(...).readAsStringSync()` a három `test/support/` fájlra) és `DateTime.now()` / `Random(` mintára illeszt. Lásd §6 A5. |
| **R5** | Az **A4** eredeti bizonyítéka („mindkét e2e teszt kétszeri futtatása a §7-ben") **kézi összevetés**, tehát az [L443](../LESSONS.md#l443) hibaosztálya: gépi őr nélkül a tiltott implementáción is „zöld". | Az **A4** cellája GÉPI: a folyam ugyanabban a fájlban KÉTSZER fut le (két friss `ProviderContainer`), és a két futás által termelt eredmény-artefaktumot `expect(second, equals(first))` veti össze. A §7 második gate-hívása ezen FELÜL marad, nem helyette. |
| **R6** | Az „app-újraindítás" (A2) megkerülhető ugyanazzal a példánnyal (§6.1 4. sora). A mért minta: az `InMemoryKeyValueStore` (`test/support/preference_store.dart`) példány TÚLÉLI a containert. | Az **A2** „újraindítás"-a kötelezően: `tester.pumpWidget(const SizedBox.shrink())` → az ELSŐ `ProviderContainer` `dispose()` → **ÚJ** `ProviderContainer` + **ÚJ** router UGYANARRA a store-példányra → a valódi `StrumSightApp` újbóli `pumpWidget`-je. |
| **R7** | [L513](../LESSONS.md#l513): a `testWidgets` fake-async zónája alatt egy broadcast `StreamController.close()` Future-je nem ütemeződik ki — a cella a `flutter test` saját időkorlátjáig FAGY (nem bukik). A §9 `flutter_animate` teardown-timere ehhez jön. | A harness lezárása **nem awaitol** ilyen Future-t (`unawaited(...)` vagy szinkron `close()`), és minden folyam záró `await tester.pump(const Duration(milliseconds: 400))`-zel fejeződik be. Ez az ADR 0472 D6. |

A kör kötött döntéseit az [`ADR 0472`](../adr/0472-e2e-flow-harness-runs-in-the-flutter-test-host.md)
rögzíti (D1–D6). A §5 alábbi pontjai annak a rövidítései.

## 0.0.2 Miért `test/e2e/` és nem `integration_test/`

A SDD Kör 11 `integration_test/` könyvtárat ír elő. A MÉRT környezet: ezen a boxon **nincs Android SDK**, a CI-ban pedig ma **nincs emulátoros job** — egy `integration_test/` csomag tehát olyan mércét telepítene, amit sem a fejlesztői loop, sem a merge-kapu nem futtat. A repó mért igazsága szerint a NEM FUTTATOTT mérce rosszabb a hiányzónál. Ezért a kör a teljes-app, determinisztikus folyam-teszteket a `flutter test` gazdában futó `test/e2e/` sávra teszi (ugyanaz a `pumpWidget` a valódi `StrumSightApp`-pal, valódi routerrel, fake adapterekkel), és az eszköz-szintű `integration_test` utat egy KÉSŐBBI, capability-igazolt kör dolgává teszi (a Kör 13 device-mátrixa után). A §5.1 ezt köti meg.

```ai-router
schema_version = 1
risk = "normal"
allowed_paths = [
  "test/support/e2e_harness.dart",
  "test/support/fake_clock.dart",
  "test/support/fake_network_guard.dart",
  "test/e2e/first_practice_offline_test.dart",
  "test/e2e/returning_user_restart_test.dart",
  "docs/testing/e2e-harness.md",
  "docs/rounds/e12-r11-end-to-end-test-harness.md",
]
gate_tests = [
  "test/e2e/first_practice_offline_test.dart",
  "test/e2e/returning_user_restart_test.dart",
  "test/app/offline_network_guard_test.dart",
]
native_gate = false
```

## 0. Kör-jelzés és STOP-protokoll

```bash
tools/codex-signal.sh progress "<egy sor>"
tools/codex-signal.sh done "<egy sor>"
tools/codex-signal.sh stopped "<egy sor>"
tools/codex-signal.sh blocked "<egy sor>"
```

**STOP-protokoll:** ha a folyam-teszt egy MÉRT termékhibába fut (a flow a valódi appban nem járható végig), a kimenet a `stopped` jelzés és jelentés — a `lib/**` javítása ebben a körben TILOS, és a teszt „megkerülő" átírása is az.

## 1. Cél

A fő vertical slice-ok (offline első gyakorlás, visszatérő felhasználó újraindítás után) determinisztikus, CI-ban reprodukálható futtatása a VALÓDI alkalmazás-fán.

## 2. Jelenlegi állapot — mért tények

- `integration_test/` **nem létezik**, és a `pubspec.yaml` `dev_dependencies` blokkja NEM tartalmazza az `integration_test` csomagot (csak `flutter_test`, `flutter_lints ^6.0.0`).
- `test/support/` **12 fake** fájlt tartalmaz (audio, auth, settings, engines, practice clock/recorder/tick source, preference store, synth, baseline scenarios) — a harness ezekből épít profilt, nem újakat ír melléjük.
- `test/app/offline_network_guard_test.dart` **létezik** — az offline-guard regresszió-őre; ez a kör a `gate_tests`-ben tartja.
- A Chapter 13 sáv MÁR pumpolja a teljes appot widget-tesztben (E13-R16…R34 körök), tehát a teljes-app teszt mintája a fán MÉRT és működik.
- `docs/testing/` **nem létezik** (a manuális eszköz-mátrixok a `docs/manual-testing/` alatt élnek).

## 3. Scope

**Benne van:** `test/support/e2e_harness.dart` — determinisztikus bootstrap-profil (rögzített óra, rögzített véletlen-mag, memória-storage, hálózat-tiltás, flag-profil) · `fake_clock.dart` az [L122](../LESSONS.md#l122) hibaosztálya ellen (a fake óra és az aszinkron stream ugyanazt a `now`-t lássa) · `fake_network_guard.dart`, ami MINDEN kimenő csatornát tilt, nem csak egyet ([L453](../LESSONS.md#l453)) · két folyam-teszt: (1) friss telepítés → onboarding → első offline gyakorlás → eredmény perzisztál; (2) visszatérő felhasználó → app-újraindítás → az állapot visszaáll · `docs/testing/e2e-harness.md` (mit fed a harness, mit NEM, és mi marad az eszköz-szintű útra).

**NINCS benne (tilos):**

- `pubspec.yaml` módosítása (az `integration_test` csomag felvétele) — a §5.1 döntése.
- `.github/workflows/**` új job (emulátoros e2e) — capability-igazolás nélkül tilos.
- `lib/**` bármely módosítása.
- Hibánál készülő képernyőkép-mechanizmus, ami a golden-fát érinti (a Ch13 golden-készlete tilos zóna).
- `docs/adr/**` — az [ADR 0472](../adr/0472-e2e-flow-harness-runs-in-the-flutter-test-host.md)-t a Claude írta a pre-flightban.

## 4. Engedélyezett fájlok

| Útvonal | Indok |
|---|---|
| `test/support/e2e_harness.dart` | ÚJ — a determinisztikus profil |
| `test/support/fake_clock.dart` | ÚJ — szinkron/aszinkron konzisztens óra |
| `test/support/fake_network_guard.dart` | ÚJ — teljes csatorna-tiltás |
| `test/e2e/first_practice_offline_test.dart` | ÚJ — 1. folyam |
| `test/e2e/returning_user_restart_test.dart` | ÚJ — 2. folyam |
| `docs/testing/e2e-harness.md` | ÚJ — a harness leírása és HATÁRAI |

**Tilos zóna:** `pubspec.yaml` · `lib/**` · `.github/**` · `test/ui/goldens/**` · `test/support/` meglévő fájljai · `docs/adr/**`

## 5. Kötött architekturális döntések (ADR 0472)

### 5.1 Az E2E sáv a `flutter test` gazdában fut; az eszköz-szintű út külön kör

**NEM elfogadható gyengítés:** az `integration_test` csomag felvétele „majd később futtatjuk" indoklással — a repó mért tanulsága szerint a nem futtatott mérce hamis biztonságot ad, és a `pubspec` bővítése a win32-pin miatt önmagában is kockázat.

### 5.2 A hálózat-tiltás GLOBÁLIS, nem csatorna-specifikus

A guard minden HTTP-kliens és platform-csatorna útját zárja, és a teszt ELBUKIK, ha a flow bármelyiken kimenne. **NEM elfogadható gyengítés:** egyetlen `Dio` interceptor mockolása ([L453](../LESSONS.md#l453) hibaosztálya).

### 5.3 Az óra egyetlen forrás

A fake óra ugyanazt a `now`-t adja a szinkron kódnak és a stream-listenerben felfegyverzett timernek ([L122](../LESSONS.md#l122)). **NEM elfogadható gyengítés:** `DateTime.now()` maradéka bárhol a harness-útvonalon.

### 5.4 A teardown a fake-async zóna szabályai szerint készül (ADR 0472 D6)

A harness lezárása **nem awaitolhat** broadcast `StreamController.close()`
Future-t — az a `testWidgets` fake-clock zónája alatt SOSEM tér vissza, és a
cella nem bukik, hanem a `flutter test` saját időkorlátjáig FAGY
([L513](../LESSONS.md#l513)). Minden folyam záró
`await tester.pump(const Duration(milliseconds: 400))`-zel fejeződik be (a
`flutter_animate` függőben maradó teardown-timere, §9).

### 5.5 A folyamat a VALÓDI fán megy, köztes artefaktum injektálása nélkül

A cella a UI-n keresztül halad (`tester.tap` / `pumpAndSettle`), és nem injektál
olyan köztes artefaktumot, amit a lánc maga termelne meg
([L273](../LESSONS.md#l273)). Fixture-t csak a lánc BEMENETÉN (katalógus-definíció,
store kezdőállapot) szabad megadni — a `practice_routing_test.dart`
`PracticeCatalogRepository`-override mintája szerint.

## 6. Acceptance criteria

| # | Kritérium | Bizonyíték |
|---|---|---|
| A1 | Az offline első-gyakorlás folyam végigfut a VALÓDI `StrumSightApp` fán, hálózat nélkül | `first_practice_offline_test.dart` |
| A2 | A folyam eredménye perzisztál, és app-újraindítás után visszaáll. Az „újraindítás" kötelezően: `pumpWidget(SizedBox.shrink())` → az első `ProviderContainer.dispose()` → **ÚJ** container + **ÚJ** router UGYANARRA az `InMemoryKeyValueStore`-**példányra** → a valódi `StrumSightApp` újbóli pumpolása (§0.0/R6) | `returning_user_restart_test.dart` |
| A3 | A hálózati kísérlet BÁRMELY csatornán a tesztet PIROSSÁ teszi. A guard mindhárom utat zárja és RÖGZÍTI: Dio `HttpClientAdapter`, `dart:io` `HttpOverrides`, és a platform-csatornák (`setMockMessageHandler` mindenre, nem egy nevesítettre) | `fake_network_guard` három cellája — csatornánként EGY |
| A4 | Kétszeri futtatás azonos eredményt ad (determinizmus: rögzített óra és mag). **GÉPI cella:** a folyam ugyanabban a fájlban kétszer fut le két friss `ProviderContainer`-rel, és a két futás eredmény-artefaktumát `expect(second, equals(first))` veti össze (§0.0/R5) | mindkét e2e teszt saját „kétszer futtatva azonos" cellája **+** a §7 második gate-hívása |
| A5 | A harness nem használ `DateTime.now()`-t és valódi `Random()`-ot. **FORRÁS-SZINTŰ őr:** a cella a három `test/support/` harness-fájlt `File(...).readAsStringSync()`-kel olvassa, és a `DateTime.now()` / `Random(` mintára illeszt (§0.0/R4) | statikus cella a harness-fájlokra |
| A6 | A meglévő `offline_network_guard_test.dart` VÁLTOZATLANUL zöld | a §7 gate |

### 6.1 Mérce-mátrix — melyik hibás implementációt melyik cella fogja pirosra

| Hibás implementáció | Melyik cella vált PIROSRA |
|---|---|
| A guard csak a `Dio` klienst tiltja, a platform-csatornát nem | A3 (a platform-csatorna cellája) |
| A guard csak a platform-csatornát tiltja, a `dart:io` `HttpClient`-et nem | A3 (a `HttpOverrides` cellája) |
| A fake óra csak a szinkron ágon él, a timer valódi időt lát ([L122](../LESSONS.md#l122)) | A4 (a két futás artefaktuma eltér) |
| A harness-ben marad egy `DateTime.now()`, de a futás véletlenül egyezik | A5 (forrás-szintű őr — a viselkedési cella ezt NEM fogja meg, §0.0/R4) |
| A teszt a folyam helyett közvetlenül a repository-t hívja (nem a valódi fán megy, [L273](../LESSONS.md#l273)) | A1 |
| A perzisztencia in-memory marad, és az „újraindítás" ugyanazt a container-példányt használja | A2 |
| A harness lezárása awaitolja a broadcast `StreamController.close()`-t | egyik cella sem — **FAGYÁS** a `flutter test` időkorlátjáig ([L513](../LESSONS.md#l513), ADR 0472 D6); ezért §5.4 normatív tiltás |

**Valódi-sértés próba (KÖTELEZŐ, a §10-ben dokumentálva):** engedélyezz egyetlen kimenő hívást a guardban, futtasd a §7 gate-et → az **A3** cellának PIROSNAK kell lennie → állítsd vissza.

## 7. Kötelező ellenőrzések

```bash
tools/round-gate.sh test/e2e/first_practice_offline_test.dart test/e2e/returning_user_restart_test.dart test/app/offline_network_guard_test.dart
```

Determinizmus-ismétlés (második, önálló hívás — a kimenetek összevetése a §10-be):

```bash
tools/round-gate.sh test/e2e/
```

## 8. Implementációs sorrend

1. `fake_clock.dart` és `fake_network_guard.dart`.
2. `e2e_harness.dart` — a bootstrap-profil a MEGLÉVŐ fake-ekre építve.
3. `first_practice_offline_test.dart`.
4. `returning_user_restart_test.dart`.
5. `docs/testing/e2e-harness.md` — a HATÁROK kimondásával.
6. A valódi-sértés próba a §10-be.

## 9. Kockázatok

- **Flaky teljes-app teszt.** A `flutter_animate` mért csapdája (függőben maradó teardown-timer) záró `pump` nélkül szivárgó timert hagy — a harness ezt kezelje.
- **Rejtett valódi idő.** Egyetlen `DateTime.now()` a láncban elveszi a determinizmust (A5).
- **Termékhiba felfedezése.** Ha a flow nem járható végig, az a `stopped` jelzés esete — a teszt „megkerülő" átírása tilos.

## 10. Implementation handoff — az implementer tölti ki

**Amit szállítottam** (a §4 engedélyezett listája szerint, mind ÚJ fájl):

- `test/support/fake_clock.dart` — `HarnessClock`: a MEGLÉVŐ `FakePracticeSessionClock` + `FakePracticeTickSource` (test/support/, nem szerkesztve) egyetlen `tick(tester, duration)` hívásba zárva, hogy a szinkron clock és az aszinkron tick-forrás sose essen szét (L122).
- `test/support/fake_network_guard.dart` — `FakeNetworkGuard`: Dio `HttpClientAdapter` (dob + rögzít), `dart:io` `HttpOverrides` (dob + rögzít), és egy folyamat-szintű platform-csatorna catch-all a `TestDefaultBinaryMessenger.allMessagesHandler`-en keresztül (NEM `setMockMessageHandler(null, …)` — ez az API nem létezik ilyen alakban a Flutter SDK-ban, lásd alább). A catch-all a `flutter/`-prefixű motor-saját csatornákat (pl. `flutter/platform` — a `MaterialApp`/`Title` widget minden boot alkalmával hívja) a delegate-nek engedi át; minden más (bármely plugin-csatorna) rögzítve és eldobva.
- `test/support/e2e_harness.dart` — determinisztikus bootstrap (`bootE2eApp`/`restartE2eApp`), a két folyam megosztott lépései (`walkOnboardingViaSkip`, `runFirstPracticeSession`), és a history-snapshot segédek (`loadPracticeHistory`, `snapshotHistoryEntry`).
- `test/e2e/first_practice_offline_test.dart` — A1/A2 fő cella, A4 (kétszeri futtatás, saját fájlon belül) és A3 (három önálló csatorna-cella).
- `test/e2e/returning_user_restart_test.dart` — A2 (restart), A4 (kétszeri futtatás) és A5 (forrás-szintű őr).
- `docs/testing/e2e-harness.md` — a lefedettség és a HATÁROK.

**Mért, dokumentált eltérés a brief eredeti API-feltételezésétől:** a `TestDefaultBinaryMessenger` API-ja (`/home/ubuntu/flutter/packages/flutter_test/lib/src/test_default_binary_messenger.dart`) `setMockMessageHandler(String channel, …)`-t definiál — a `channel` paraméter NEM nullázható, tehát a `setMockMessageHandler(null, handler)` „minden csatornára" minta, amit a kutatásom kezdetben feltételezett, nem fordul. A tényleges, dokumentált catch-all mechanizmus a `TestDefaultBinaryMessenger.allMessagesHandler` mező (l. a fájl 138. sora: „Handler that intercepts and responds to outgoing messages, pretending to be the platform, for all channels."). A guard ezt használja — ADR 0472 D2 szövege ez alapján teljesül, csak a konkrét API más.

**Mért, dokumentált tény a Practice V2 production wiringról (NEM `lib/**` hiba a mai scope-ban, hanem a harnessnek kellett kezelnie):** `practiceSessionHostProvider` (`lib/features/practice/presentation/practice_effect_listener.dart:99`) egy sima (nem autoDispose) `Provider`, ami `ref.watch`-ol egy autoDispose láncot (`practiceActiveSessionInputsProvider` → `practiceSessionControllerProvider(inputs)` család). A Setup képernyő Start-kezelője és a prepare sink (`practice_setup_controller.dart` `_activateSessionSink`) mindkettő `ref.read`-et használ, ami NEM tartja életben az autoDispose-t; és `grep -rn "AppRoutes.practiceSession\b" lib/` szerint SEHOL a `lib/**`-ben nincs automatikus navigáció a Setup-tól a Session útvonalig. Emiatt a `practiceSessionHostProvider`-t NEM figyelő teszt (vagy egy ma létező, valódi felhasználó) az aktivált munkamenetet elveszíti, mielőtt a Session képernyő megjelenne. A harness ezt a `container.read(practiceSessionHostProvider)` két, pontosan időzített hívásával hidalja át (`runFirstPracticeSession`, a Start-tap ELŐTT és UTÁN, pump nélkül közéjük) — ugyanaz a művelet, amit a `practice_production_wiring_test.dart` is végez a `PreparePractice` előtt/után, csak a Setup-képernyő tap-jéhez igazítva. Ez NEM „megkerülő" tesztátírás (L273): a UI-n keresztül halad (`tester.tap`/`pumpAndSettle`), a `container.read` pusztán a Riverpod-figyelőt regisztrálja, nem ad hozzá vagy hagy ki egy chain-lépést. Dokumentálva a §10-ben, hogy egy KÉSŐBBI kör (amely a Setup→Session navigációt production kódban megépíti) tudja, hogy ez a pontos race a mai állapot.

**Két mért fagyás-csapda kezelése:**
- L513/ADR 0472 D6: `E2eSession.dispose` sosem awaitol broadcast `StreamController.close()`-t — a saját fake engine-jeinket `unawaited(...)`-tel zárjuk, a `ProviderContainer.dispose()` maga szinkron, a `PracticeSessionController.dispose()` belső `await`-jei (amiket a `ref.onDispose` indít) leválasztva futnak.
- flutter_animate teardown-timer: mindkét e2e teszt fő cellája `await tester.pump(const Duration(milliseconds: 400))`-zel zár.

**A gate — szó szerint, csonkítás nélkül, kétszer, önálló hívásokkal:**

1. `tools/round-gate.sh test/e2e/first_practice_offline_test.dart test/e2e/returning_user_restart_test.dart test/app/offline_network_guard_test.dart` → **MINDEN GATE ZÖLD** (format, analyze, mindhárom teszt-lépés — 5+3+4 cella —, architecture, secrets, l10n).
2. Determinizmus-ismétlés, önálló hívás: `tools/round-gate.sh test/e2e/` → **MINDEN GATE ZÖLD** (8 cella a két e2e fájlban).
3. `test/app/offline_network_guard_test.dart` (A6) VÁLTOZATLAN — nem szerkesztve, a gate mindkét futtatásban zöld.

**Valódi-sértés próba (KÖTELEZŐ, §6.1 alja) — tényleges kimenet:**

Ideiglenesen meggyengítettem `test/support/fake_network_guard.dart` `_GuardedHttpClientAdapter.fetch`-jét, hogy egy kimenő Dio-hívást átengedjen (ne dobjon), majd lefuttattam `flutter test test/e2e/first_practice_offline_test.dart --plain-name "Dio HttpClientAdapter"`:

```
00:00 +0: A3 — fake_network_guard blocks every channel, one cell per path Dio HttpClientAdapter.fetch is blocked and recorded
00:00 +0 -1: A3 — fake_network_guard blocks every channel, one cell per path Dio HttpClientAdapter.fetch is blocked and recorded [E]
  Expected: throws <Instance of 'NetworkGuardViolation'>
    Actual: <Closure: () => Future<ResponseBody>>
     Which: returned a Future that emitted <Instance of 'ResponseBody'>

  package:matcher                                    expectLater
  package:flutter_test/src/widget_tester.dart 507:8  expectLater
  test/e2e/first_practice_offline_test.dart 78:13    main.<fn>.<fn>

00:00 +0 -1: Some tests failed.
```

Az A3 Dio-cella a vártnak megfelelően PIROSRA váltott. Ezután `git diff` üres eredményt adott a fájlra (a visszaállítás pontos volt), és a fenti §7 gate mindkét hívása újra ZÖLD lett a visszaállítás után.

**Amit NEM mértem, és miért:**

- Valódi mikrofon / valódi DSP — a harness deklarált határa (docs/testing/e2e-harness.md), eszköz-szintű kör dolga.
- A `practiceHapticsEnabledProvider`/`practiceFeedbackOutputProvider` valódi (nem no-op) útja — szándékosan platform-határ fake, ugyanaz a minta, mint a `fakeAudioOverrides()`.
- A Daily Challenge kártya / `PracticeHubScreen`'s `now` paraméter valódi `DateTime.now()`-ja — a folyam a Quick Start kártyát használja (nem függ `now`-tól), ezért ez nem érinti az A4/A5 determinizmust; dokumentálva, nem javítva (lib/** tiltott zóna).
- A `PracticeAreaHubScreen` (adaptive shell változat) — a harness `adaptiveShellEnabled: false`-t állít be (a `FeatureFlags` default konstruktora), így a legacy `PracticeHubScreen`-t járja be, ugyanazt a mintát követve, mint `practice_routing_test.dart`.

## 11. Review — a Claude tölti ki
