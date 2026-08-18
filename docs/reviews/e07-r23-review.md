# E07-R23 — Review

Brief: docs/rounds/e07-r23-plan-compiler-and-execution.md
Diff: `git diff 4eb098d8..4bb62a62` (branch `codex/e07-r23-plan-compiler-and-execution`, synced onto `origin/main`@`9e47122f` before dispatch)
Reviewer: Claude (Opus 5, orchestrátor) · Dátum: 2026-08-18
Verdikt: CHANGES REQUIRED

## Összegzés

BLOCKER: 0 · MAJOR: 1 · MINOR: 1 · NOTE: 2

## Acceptance criteria

| # | Kritérium | Teljesült | Bizonyíték |
|---|---|---|---|
| A1 | Technikai hiba NEM csökkenti a becslést, nem vált ki regressziót | ✅ | `plan_execution_coordinator_test.dart` "A1" — `contributesSkillEvidence`/`requestsRegression` false; kódszinten `contributesSkillEvidence` kizárólag `completionState == completed`-nél igaz (`plan_execution_coordinator.dart:144-146`). Valódi-sértés próba a §10 handoffban dokumentálva (a szerző elvégezte, saját kézzel NEM ismételtem meg, mert a logika egyértelműen a leírt módon fut). |
| A2 | Elavult revíziójú blokk nem indul | ✅ | `plan_compiler_test.dart` "A2" — `staleContentRevision` → `UnavailablePlanStep`. `plan_compiler.dart:143-149`. |
| A3 | Hiányzó capability esetén a blokk nem indul | ✅ | `plan_compiler_test.dart` "A3". `plan_compiler.dart:151-163`. |
| A4 | Az eredmény idempotens (kétszeri visszatérés) | ✅ | `plan_execution_coordinator_test.dart` "A4" — replay `isDuplicate=true`, `replay.outcome` **same instance** mint az első; a második hívás bemenete (`CancelledPracticeOutcome`) eldobva — first-write-wins bizonyítva. |
| A5 | A session-konfig pontosan a recept szerinti | ⚠️ részleges | A `PlanCompiler` oldal (megőrzés) tesztelt: `plan_compiler_test.dart` "A5". A `PlanExecutionCoordinator._validateLaunch` **hiba-ág** (eltérő sessionConfig → `ArgumentError`) — **NINCS teszt rá**. Lásd F1. |
| A6 | A megszakított session részleges, nem sikertelen | ✅ | `plan_execution_coordinator_test.dart` "A6" — `interrupted` → `partial`, `contributesSkillEvidence=false`, `requestsRegression=false`. |
| A7 | `blockExecutionId` egyedi és visszakereshető | ✅ | `plan_execution_coordinator_test.dart` "A7" — két hívás különböző ID, és a plan/revision/day/block eredet megőrződik. |

## Scope-audit

Engedélyezett fájlokon kívüli változás: **nincs**.

Hiteles eszközzel mérve (nem a `.codex-round-status` bemondására hagyatkozva):
```
$ python3 tools/scope-audit.py --repo /tmp/review-e07-r23 --brief docs/rounds/e07-r23-plan-compiler-and-execution.md --base 4eb098d8
Legacy scope audit OK (4eb098d8..4bb62a622fa0, 8 changed path(s), 0 generated/ignored)
```
8 megváltozott útvonal = a 3 új `lib/` fájl + `public.dart` + 2 tesztfájl + 1 fixture fájl + a round-brief handoff-szekció — mind az `allowed_paths`-on belül.

**Megjegyzés a review-folyamatról:** az első klónozási kísérletem (`git clone --branch ... /home/ubuntu/music-theory ...`) egy elavult, a dispatch ELŐTTI helyi remote-tracking refre hivatkozott (`9c2aa9bb`, hiányzó implementáció) — ez a saját hibám volt, nem a kör hibája; a helyes eredményhez közvetlenül originból (`https://github.com/wolfcasaba/strumsight`) kellett újraklónozni. A lenti gate-eredmények a HELYES, `4bb62a62` HEAD-en futottak.

## Megállapítások

### F1 — MAJOR — A5 hiba-ága (session-config pontos egyezés) nincs tesztelve; adversarial mutációval bizonyítva, hogy jelenleg SEMMI nem fogná meg a regresszióját

- **Fájl:** `lib/features/practice_generator/application/service/plan_execution_coordinator.dart:178-188` (`_validateLaunch` exact-match ág)
- **Probléma:** a brief §5.4 ("Amit a tervező előírt… az megy át a végrehajtóhoz — nem „körülbelül". Eltérés esetén hiba, nem csendes igazítás.") és a §6.1 mérce-mátrix explicit sora ("„Körülbelüli" session-konfig → A5 PIROS") megköveteli, hogy egy eltérő `sessionConfig`-gal induló `start()` hívás hibázzon, és hogy ezt egy teszt PIROSRA fogja, ha a védelem sérül. A jelenlegi 2 tesztfájl egyetlen `coordinator.start()` hívása sem ad át eltérő `sessionConfig`-ot — mindegyik a `matchingSessionConfig()` fixture-t használja. Az `A5` teszt (`plan_compiler_test.dart`) kizárólag a `PlanCompiler` kimenetét ellenőrzi, a koordinátor validációját sosem hívja.
- **Bizonyíték (valódi-sértés próba, elvégezve, majd visszaállítva):** a `_validateLaunch` exact-match `if`-ágát (178-188. sor) egy no-op kommentre cseréltem az izolált `/tmp/review-e07-r23` klónban, majd lefuttattam mindkét célzott tesztfájlt:
  ```
  $ flutter test test/features/practice_generator/execution/plan_compiler_test.dart \
                  test/features/practice_generator/execution/plan_execution_coordinator_test.dart
  00:00 +7: All tests passed!
  ```
  Mind a 7 teszt zöld maradt a védelem teljes eltávolítása után is — a mérce-mátrix saját elvárása (A5 PIROS) NEM teljesül. A fájlt ezután visszaállítottam az eredeti tartalomra (`git diff` üres a próba után).
- **Hatás:** egy jövőbeli, jóhiszemű refaktor (pl. a `_validateLaunch` egyszerűsítése vagy a mezőlista bővítése) észrevétlenül meglazíthatja vagy törölheti ezt az ADR 0268 4. pontjához kötött védelmet — a teljes célzott gate zöld maradna, és csak éles használatban derülne ki (a tanuló más tempón/hosszon gyakorol, mint amit a terv előírt, és a mérés emiatt értelmét veszti — pontosan a brief §9 saját kockázat-listájának első tétele).
- **Kötelező javítás:** egy teszteset a `plan_execution_coordinator_test.dart`-ba, amely `matchingSessionConfig()`-ot egyetlen mezőn (pl. `loopCount` vagy `sessionTimeout`) eltérő értékre módosítva adja át `coordinator.start()`-nak, és `throwsArgumentError`-t (vagy a konkrét üzenetet) vár. Egy fixture-függvény (`mismatchedSessionConfig()`) hozzáadása az `execution_fixtures.dart`-hoz elegendő — mindkét fájl már az `allowed_paths`-on van, nincs scope-bővítés.
- **Ellenőrzés:** az új teszt a mutált (védelem nélküli) kódon PIROS, az eredeti kódon ZÖLD — ugyanaz a valódi-sértés módszertan, amit a szerző az A1-hez már elvégzett.
- **Státusz:** OPEN

### F2 — MINOR — A koordinátor több más védő `throw`-ága (blockId-eltérés, `PracticeSessionConfig.validate()` hiba, outcome-context eltérés) sem tesztelt

- **Fájl:** `plan_execution_coordinator.dart:164-170, 171-177, 191-204`
- **Probléma:** ezek a generikus bemenet-validáló ágak (nem a brief egyetlen névre szólóan megnevezett mérce-cellája) szintén nincsenek lefedve — se pozitív, se negatív próbateszt.
- **Hatás:** alacsonyabb, mint F1 — ezek általános defenzív guardok, nem egy külön ADR-döntéshez kötött, névre szólóan megkövetelt mérce-cella.
- **Kötelező javítás:** nem blokkoló ebben a körben; érdemes egy jövőbeli körben (vagy az F1-javítással egy csapásra) legalább egy-egy cellával lefedni.
- **Ellenőrzés:** —
- **Státusz:** OPEN (follow-up, nem merge-blokkoló)

### N1 — NOTE — `PlanCompiler` két extra védőágat is visz a brief két névre szólóan megkövetelt ágán felül

- **Fájl:** `plan_compiler.dart:129-135` (`unsupportedSource`), `136-142` (`wrongExercise`)
- **Megfigyelés:** a brief csak A2 (elavult revízió) és A3 (hiányzó capability) ágat kér, de az implementáció két további defenzív ellenőrzést is hozzáad (forrás típusa, exercise-azonosság). Ez összhangban van a §5.2 szellemével és nem lép túl az engedélyezett fájlokon — nem hiba, csak dokumentálva a jövőbeli olvasónak.

### N2 — NOTE — `contributesSkillEvidence` a `partial` állapotot is kizárja az evidence-ből, nem csak a büntetéstől

- **Fájl:** `plan_execution_coordinator.dart:144-146`
- **Megfigyelés:** a brief §5.5 csak azt írja elő, hogy a megszakított session "nem büntet" — a kód ennél szigorúbban jár el: a `partial` állapot SOSEM járul hozzá evidence-hez (sem pozitív, sem semleges súllyal), csak a `completed` állapot. Ez egy konzervatívabb, biztonságosabb értelmezés (ADR 0265 "bounded influence" szellemével összhangban), nem ellentmondás — dokumentálva, mert egy jövőbeli kör (adaptáció-bekötés) számíthat rá.

## Gate-bizonyíték ellenőrzése

Minden gate-et **saját kézzel, izolált `/tmp/review-e07-r23` klónban** futtattam újra (eredetileg `/home/ubuntu/music-theory`-ból klónozva, ami elavult helyi refre mutatott — utána közvetlenül originból újraklónozva, ld. fent), a `tools/prepare-flutter-generated.sh` előkészítés után.

| Gate | Állított eredmény (implementer) | Ellenőrizve |
|---|---|---|
| format | zöld | ✅ (saját `tools/round-gate.sh` futás, ld. `/tmp/claude-1001/.../scratchpad/gate-e07-r23-final.log`) |
| analyze | zöld | ✅ |
| `plan_compiler_test.dart` | zöld | ✅ |
| `plan_execution_coordinator_test.dart` | zöld | ✅ |
| architecture | zöld | ✅ (12 allowlistázott eltérés, változatlan a kör előtt is) |
| secrets | (nem állította, de a gate futtatja) | ✅ 0 lelet |
| l10n | (nem állította, de a gate futtatja) | ✅ en→hu parity |
| scope-audit (`tools/scope-audit.py`) | `scope_audit=ok` (`.codex-round-status`) | ✅ függetlenül megerősítve, 0 generated/ignored |
| CI (teljes suite + property + APK) | — | ⏳ ez a review NEM tartalmazza — az orchestrátor a review után dispatch-eli |

## Merge-döntés

**Merge TILOS, amíg az F1 (MAJOR) nyitva van** (ADR 0052 + a review-sablon súlyossági táblája). Az F1 javítása kicsi (egy fixture-függvény + egy teszteset, mindkettő már engedélyezett fájlban) — javasolt egy rövid javító kör ugyanazzal a motorral (`codex`), a leletlistával a promptban.
