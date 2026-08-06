# E05-R05 — Review

Brief: `docs/rounds/e05-r05-camera-session-coordinator-and-lifecycle.md`
Diff: `git diff origin/main...codex/e05-r05-camera-session-coordinator-and-lifecycle`
Reviewer: Claude Sonnet 5 (orchestrátor) · Dátum: 2026-08-06
Verdikt: **APPROVED**

## Összegzés

BLOCKER: 0 · MAJOR: 0 · MINOR: 0 · NOTE: 5 (2 saját + 3 dedikált security-reviewer)

Az implementer (Terra) pontosan a §4 engedélyezett fájllistán belül dolgozott
(7 fájl, 0 pre-existing fájl érintve), a mikrofon lease-precedenst (ADR 0056)
szerkezetileg hűen másolta camera-oldalra, és a §6 acceptance criteria
mindegyike mérve teljesült. A gate-eket saját kézhez, izolált
`/tmp/review-e05-r05` klónban futtattam újra — mind zöld. A §6 „valódi-sértés
próbát" **saját kézzel, függetlenül megismételtem** (nem fogadtam el az
implementer §10 önbevallását bizonyítéknak) — lásd lent. Dedikált
security-reviewer (a brief `risk = "high"`): **PASS**, 0 BLOCKER/MAJOR/MINOR,
3 NOTE (hardening-javaslat R06-ra, nem ebbe a körbe tartozik).

## Acceptance criteria

| # | Kritérium | Teljesült | Bizonyíték |
|---|---|---|---|
| 1a | Két egyidejű `acquire` → 1 siker + 1 `cameraSessionBusy` | ✅ | `camera_session_coordinator_test.dart:16-33`; saját mutáció-kill próba (lent) igazolja, hogy a teszt valóban őrzi az invariánst |
| 1b | `acquire` közbeni cancel | ✅ | `...test.dart:35-62` — a revoke az owner folyamatban lévő `capture.start()`-ját szakítja meg (`FailureCode.cancelled`); l. „Megállapítások" F1 az interpretáció megjegyzésével |
| 1c | `close` + `close` | ✅ | `...test.dart:64-75`, idempotens, `activeOwner` null marad |
| 1d | `close` közbeni `acquire` | ✅ | `...test.dart:77-101` — a versengő `acquire` `cameraSessionBusy`-t kap, amíg a teardown be nem fejeződik (a §10 szerint ez volt az egyetlen RED→GREEN a fejlesztés alatt) |
| 1e | interruption alatt `close` | ✅ | `...test.dart:103-133` — `teardownCalls==1`, pontosan egyszeri teardown egyidejű `revokeActive`+`release` mellett |
| 1f | revoke közbeni frame-esemény | ✅ | `...test.dart:135-170` — utolsó frame revoke előtt kézbesül, `emitFrame` revoke után `cameraClosed`-ot ad; l. F2 megjegyzés a lefedettség pontos hatóköréről |
| 2 | Lifecycle-mátrix mind az 5 `AppLifecycleState`, külön cella | ✅ | `camera_lifecycle_guard_test.dart:35-80` — `paused/hidden/detached` → revoke (3 külön teszt), `inactive/resumed` → sem revoke, sem auto-start (2 külön teszt) |
| 3 | Route-leave fake adapterrel, nincs írás dispose után | ✅ | route-leave: `...coordinator_test.dart:135-170`; dispose-biztonság: `...guard_test.dart:82-102` (guard dispose) és `104-132` (Riverpod container dispose) |
| 4 | Valódi-sértés próba: foglalás az első `await` mögé → (a) PIROS → visszaáll | ✅ | Implementer önbevallás (§10) **és** saját, független reprodukció (lásd lent) — mindkettő ugyanazt a kizárólagos RED-et adta |
| 5 | `test/core/audio` változatlanul zöld | ✅ | saját futtatás izolált klónban: 37/37 zöld |

## Scope-audit

Engedélyezett fájlokon kívüli változás: **nincs.**

`git diff origin/main...HEAD --stat` (izolált klón) pontosan a §4 hét
bejegyzését adja vissza: `camera_session_coordinator.dart`,
`camera_session_lease.dart`, `camera_lifecycle_guard.dart`,
`camera_providers.dart`, két új teszt, a round-brief doc (§10 handoff). A
korábbi körök fájljai (`camera_capture.dart`, `camera_frame.dart`,
`camera_failure.dart`, `fake_camera_capture.dart`, `camera_permission.dart`,
`app_failure.dart`) **egy bájtot sem** változtak (`git diff --stat` üres
ezekre) — a coordinator a meglévő `CameraFailureKind.busy` /
`FailureCode.cameraSessionBusy` és `FailureCode.cancelled` konstansokat
használja újra, nem vezet be újat. A gépi `scope_audit=ok` (`.codex-round-status`,
`scope_audit_changed=7`, base `779286e`) egyezik a kézi mérésemmel.

## Saját, független mutáció-kill próba

A §6 negyedik acceptance-pontját NEM az implementer §10 leírásából fogadtam
el — izolált `/tmp/review-e05-r05` klónban saját kézzel megismételtem:

```
_active = lease; →
await Future<void>.delayed(Duration.zero); // mutáció
_active = lease;
```

`flutter test test/core/camera/camera_session_coordinator_test.dart`
eredmény: **pontosan** az „two overlapping acquires…" cella PIROS (2×
`Success` az elvárt 1 siker + 1 busy helyett), a másik **7** teszt zöld
maradt. A mutációt ezután `git checkout --` -sal visszaállítottam, a klón
tiszta. Ez önmagában bizonyítja, hogy a szinkron check-and-take valóban
terhelt invariáns, nem díszlet-teszt.

## Megállapítások

### F1 — NOTE — „acquire közbeni cancel" cella (1b) interpretációja

- **Fájl:** `test/core/camera/camera_session_coordinator_test.dart:35-62`
- **Megfigyelés:** a brief §6 (b) cellája szó szerint „`acquire` közbeni
  cancel"-t ír elő. Mivel a coordinator `acquire`-jában nincs `await` (l. a
  mutáció-próbát), egy in-flight `acquire`-t ténylegesen nem lehet
  megszakítani — a Future már a hívás pillanatában lezárt. Az implementer
  ezért azt tesztelte, amit a szerződés valójában megenged: a **revoke** az
  owner folyamatban lévő `capture.start()`-ját szakítja meg
  (`FakeCameraCapture.start()` `startGate`-je, E05-R03 precedens). Ez a
  releváns race — a szó szerinti „acquire cancel" üres teszt volna.
- **Hatás:** nincs — a mögöttes viselkedés helyesen és mérve tesztelt.
- **Kötelező javítás:** nincs, dokumentáció-jellegű észrevétel a jövőbeli
  olvasónak.
- **Státusz:** WONTFIX (a megfelelő teszt már megvan, csak a cella-címke
  szó szerinti olvasata térne el).

### F2 — NOTE — „revoke közbeni frame-esemény" cella (1f) hatóköre

- **Fájl:** `test/core/camera/camera_session_coordinator_test.dart:135-170`
- **Megfigyelés:** a teszt a revoke ELŐTTI utolsó sikeres frame-et és a
  revoke UTÁNI elutasított frame-et méri (határeset mindkét oldalon), nem
  egy ténylegesen a revoke `await onRevoke?.call()` ablakával versengő
  `emitFrame()` hívást. Mivel a frame-eket a teszt explicit hívja (nincs
  háttérben pörgő frame-forrás, ami a coordinator állapotával versenyezne),
  és a frame-érvényesség (`assertValid`/`invalidate`) már az E05-R03
  `CameraFrame` szerződés szintjén, a callback szinkron törzsére korlátozva
  bizonyított — a coordinator réteg maga nem kapuz frame-eket, csak a
  lease-t. A választott teszt így a coordinator saját felelősségi körét
  helyesen fedi; egy szó szerinti „during" próba a `CameraCapture`
  szerződés, nem a coordinator tesztje volna.
- **Hatás:** nincs — nincs hiányzó védelem, csak a cella-címke pontosítható.
- **Kötelező javítás:** nincs.
- **Státusz:** WONTFIX.

### F3–F5 — NOTE — dedikált security-reviewer hardening-javaslatok (nem ebbe a körbe tartoznak)

A security-reviewer (`risk = "high"`, teljes jelentés a PR-leírásban / session
logban) **PASS**-t adott, 3 non-blocking NOTE-tal, mindegyik explicit R06
(production adapter) hatókörű, nem R05:

- **NOTE-1:** `test/core/camera/camera_lifecycle_guard_test.dart` a
  `FakeAppLifecycleEvents`-et `test/support/fake_audio.dart`-ból importálja,
  ami tranzitíve az egész audio-stacket behúzza a teszt-fordításba. Nem ADR
  0182-sértés (a production kód audio-mentes, grep igazolta), de egy jövőbeli
  auditornak megnehezíti a „független-e" kérdés gyors megválaszolását.
  **Javasolt irány:** `FakeAppLifecycleEvents` kiemelése egy semleges
  `test/support/fake_lifecycle.dart`-ba — follow-up, nem merge-gát.
- **NOTE-2:** a `_log` `reason` paramétere `String` típusú, ma minden hívó
  helyen literál vagy `enum.name` — konvencióval, nem típusrendszerrel védett.
  **Javasolt irány:** R06-nál fontolja meg a típus szűkítését.
- **NOTE-3:** `await onRevoke?.call()` időkorlát nélküli; ma nincs valódi
  `onRevoke`, így nem reprodukálható e körben, de R06 valódi adapterénél egy
  beragadt `close()` véglegesen zárva tarthatná a lease-t. **Javasolt irány:**
  R06 vezessen be timeoutot a teardown-ra.

Egyik sem érinti az E05-R05 diffet — mindhárom explicit R06-ra (production
camera adapter) irányuló follow-up, dokumentálva a HANDOFF-ban is.

## Architektúra és termékhatárok (AGENTS.md §5–§6)

- **Domain-tisztaság:** `camera_session_lease.dart` nulla importtal tiszta
  Dart; `camera_session_coordinator.dart` csak `app_result`/`app_logger`/
  `camera_failure`/`camera_session_lease`-t importál — Flutter/Riverpod
  mentes. `camera_lifecycle_guard.dart` `flutter/widgets.dart`-ot importál
  kizárólag az `AppLifecycleState` típusért — pontosan az
  `AudioLifecycleGuard` precedens mintája.
- **Core nem importál feature-t:** egyik új fájl sem hivatkozik
  `lib/features/`-re.
- **Audio/camera függetlenség (ADR 0182):** grep `audio` a
  `lib/core/camera/`-ban (production fájlok) 0 találat.
- **§5 termékhatárok:** nincs nyers kép/audio a logban (mezőnként igazolva),
  nincs rejtett hálózati hívás (a diff egyáltalán nem érint hálózati kódot),
  a kamera egyszerre egy owner-é (mérve, mutáció-próbával igazolva).
- **Lifecycle-erőforrás minden útvonalon felszabadul** (§7): explicit
  release, revoke, hibás teardown, dupla release, késői release — mind
  tesztelve, l. acceptance 1a-1e.

## Gate-bizonyíték ellenőrzése

| Gate | Állított eredmény | Ellenőrizve |
|---|---|---|
| format | implementer: zöld | ✅ saját futtatás, izolált klón |
| analyze | implementer: „No issues found" | ✅ saját futtatás, izolált klón |
| test test/core/camera | implementer: 47 teszt zöld | ✅ saját futtatás, izolált klón, 47/47 |
| test test/core/audio (acceptance #5) | implementer: 37 teszt zöld | ✅ saját futtatás, izolált klón, 37/37 |
| architecture | implementer: zöld | ✅ saját futtatás, izolált klón (12 allowlistelt eltérés, változatlan) |
| secrets | implementer: nem közölt külön | ✅ saját futtatás — 1811 fájl, 0 lelet |
| l10n | implementer: nem közölt külön | ✅ saját futtatás — en→hu, 913 üzenet, parity OK |
| scope-audit (gépi) | `scope_audit=ok`, 7 fájl | ✅ egyezik a kézi `git diff --stat`-tal |
| security-reviewer (`risk=high`) | — | ✅ dedikált agent, PASS, 0 BLOCKER/MAJOR/MINOR |
| CI — Full Gate (no APK) | — | ✅ [31092976636](https://github.com/wolfcasaba/strumsight/actions/runs/31092976636) success, exact head `6683d6f` |
| CI — Router CI | — | ✅ [31092973394](https://github.com/wolfcasaba/strumsight/actions/runs/31092973394) success, exact head `6683d6f` |

## Merge-döntés

ADR 0052 szerint: minden gate zöld ÉS nincs nyitott BLOCKER/MAJOR/MINOR →
**merge.** Mindkét CI-run a pontos, lokális HEAD-del megegyező SHA-n
(`6683d6f`) zöld; nincs javító kör.
