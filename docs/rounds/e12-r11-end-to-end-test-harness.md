# E12-R11 — End-to-end test harness

- **Státusz:** PREPARED (előre megírva 2026-08-27, kód olvasva: `main @ 9ca4a0dc`)
- **Típus:** Chapter 12 (Release Roadmap, Sprint Planning & Final Integration), Kör 11
- **Kör-azonosító:** `E12-R11`
- **Branch:** `<motor>/e12-r11-end-to-end-test-harness`
- **Előfeltétel:** `E12-R05` merge-elve (a flag-katalógus adja a determinisztikus bootstrap-profil kapcsolóit)
- **Brief szerzője:** Claude (Opus 5)
- **Előre kiosztott ADR:** `ADR 0452` — a szám FOGLALT (Chapter 12 batch-tartomány).

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

## 0.0 Miért `test/e2e/` és nem `integration_test/`

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
- `docs/adr/**` — az ADR 0452-t a Claude írja.

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

## 5. Kötött architekturális döntések (ADR 0452)

### 5.1 Az E2E sáv a `flutter test` gazdában fut; az eszköz-szintű út külön kör

**NEM elfogadható gyengítés:** az `integration_test` csomag felvétele „majd később futtatjuk" indoklással — a repó mért tanulsága szerint a nem futtatott mérce hamis biztonságot ad, és a `pubspec` bővítése a win32-pin miatt önmagában is kockázat.

### 5.2 A hálózat-tiltás GLOBÁLIS, nem csatorna-specifikus

A guard minden HTTP-kliens és platform-csatorna útját zárja, és a teszt ELBUKIK, ha a flow bármelyiken kimenne. **NEM elfogadható gyengítés:** egyetlen `Dio` interceptor mockolása ([L453](../LESSONS.md#l453) hibaosztálya).

### 5.3 Az óra egyetlen forrás

A fake óra ugyanazt a `now`-t adja a szinkron kódnak és a stream-listenerben felfegyverzett timernek ([L122](../LESSONS.md#l122)). **NEM elfogadható gyengítés:** `DateTime.now()` maradéka bárhol a harness-útvonalon.

## 6. Acceptance criteria

| # | Kritérium | Bizonyíték |
|---|---|---|
| A1 | Az offline első-gyakorlás folyam végigfut a VALÓDI `StrumSightApp` fán, hálózat nélkül | `first_practice_offline_test.dart` |
| A2 | A folyam eredménye perzisztál, és app-újraindítás után visszaáll | `returning_user_restart_test.dart` |
| A3 | A hálózati kísérlet BÁRMELY csatornán a tesztet PIROSSÁ teszi | `fake_network_guard` cellája |
| A4 | Kétszeri futtatás azonos eredményt ad (determinizmus: rögzített óra és mag) | mindkét e2e teszt kétszeri futtatása a §7-ben |
| A5 | A harness nem használ `DateTime.now()`-t és valódi `Random()`-ot | statikus cella a harness-fájlokra |
| A6 | A meglévő `offline_network_guard_test.dart` VÁLTOZATLANUL zöld | a §7 gate |

### 6.1 Mérce-mátrix — melyik hibás implementációt melyik cella fogja pirosra

| Hibás implementáció | Melyik cella vált PIROSRA |
|---|---|
| A guard csak a `Dio` klienst tiltja, a platform-csatornát nem | A3 |
| A fake óra csak a szinkron ágon él, a timer valódi időt lát | A4 (a második futás eltér) |
| A teszt a folyam helyett közvetlenül a repository-t hívja (nem a valódi fán megy) | A1 |
| A perzisztencia in-memory marad, és az „újraindítás" ugyanazt a példányt használja | A2 |

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

## 11. Review — a Claude tölti ki
