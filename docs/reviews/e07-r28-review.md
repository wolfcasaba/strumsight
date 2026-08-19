# E07-R28 — Review

Brief: docs/rounds/e07-r28-planner-assist-gateway.md
Diff: `git diff e95bd937...a1a6da38` (branch `codex/e07-r28-planner-assist-gateway`)
Reviewer: Claude (Sonnet 5) · Dátum: 2026-08-19
Verdikt: **APPROVED**

## Összegzés

BLOCKER: 0 · MAJOR: 0 · MINOR: 0 · NOTE: 3

## Acceptance criteria

| # | Kritérium | Teljesült | Bizonyíték |
|---|---|---|---|
| A1 | A modell javaslata NEM aktivál tervet | ✅ | `PlannerAssistProposal` (`application/port/planner_assist_gateway.dart:121-151`) egyetlen lifecycle-értéke `awaitingConfirmation` (:149-150), nincs aktiváló metódus. A séma az EGYETLEN konstruáló hely, és `requiresLearnerConfirmation: true`-t hardcode-olva ad át (`data/ai/planner_assist_schema.dart:118`) — a válasz mezőiből SOSEM olvassa ki ezt az értéket. A konstruktor futásidőben is `ArgumentError`-t dob `false`-ra (`:133-139`). |
| A2 | Ismeretlen/kitalált ID → elutasítás, nem fuzzy egyezés | ✅ | `planner_assist_schema.dart:94-103`. **Saját valódi-sértés próbával mérve** (nem csak az implementer önbevallását fogadtam el): a `candidateIds`/`blocks` allowlist-ellenőrzést `if (false)`-ra gyengítve `flutter test .../planner_assist_schema_test.dart` PIROSRA vált (`A2` teszt `PlannerAssistAccepted`-et kapott `PlannerAssistRejected` helyett), visszaállítás után 4/4 zöld. |
| A3 | Séma-sértő válasz elutasítva, nem részlegesen felhasználva | ✅ | `validate()` egyetlen `null`-check-lánca (`:75-83`) az ÖSSZES mezőt megköveteli, mielőtt bármi elfogadásra kerül — nincs részleges early-return. Teszt: `planner_assist_schema_test.dart:34-50` (`blocks` mező eltávolítva → teljes elutasítás). |
| A4 | Timeout / rate limit / hálózati hiba → determinisztikus tartalék | ✅ | `remote_planner_assist_gateway.dart:36-79` minden hibaágon (`TimeoutException`, `PlannerAssistRateLimitException`, `PlannerAssistNetworkException`, generikus `catch`) kizárólag `PlannerAssistFallback`-ot ad ki. Tesztek: `planner_assist_gateway_test.dart:41-116`. |
| A5 | Felhő-hiba nem veszít draftot | ✅ | `planner_assist_gateway_test.dart:42-61`: timeout után a hívó-tulajdonú `draft` (a `PlannerAssistRequest`) bizonyítottan változatlan (`expect(draft, buildPlannerAssistRequest())`). A gateway sosem ír a hívó bemenetébe. |
| A6 | Prompt-injection kísérlet a felhasználói szövegben hatástalan | ✅ | `PlannerAssistPrompt` (`application/port/planner_assist_gateway.dart:83-117`) a fix `instructions` konstanst és a `untrustedLearnerNote`-ot KÜLÖN mezőként adja `toWire()`-ban — a tanuló szövege sosem kerül az instrukció-mezőbe. Teszt: `planner_assist_schema_test.dart:71-83` (`prompt.instructions` NEM tartalmazza az injection-stringet). |
| A7 | `plannerAssistEnabled = false` mellett minden alapfunkció megy | ✅ (ld. N1) | `FakePlannerAssistGateway.disabled()` (`data/ai/fake_planner_assist_gateway.dart:11-13,28-32`) hálózati hívás NÉLKÜL determinisztikus fallback-et ad. Teszt: `planner_assist_gateway_test.dart:118-135`. |
| A8 | A Tutor-vázlat leképezése típusos, validált | ✅ | `tutor_plan_proposal_adapter.dart` — a §0.0 pre-flight revízió szerinti SAJÁT `TutorPlanOutline` típusból épít `PlannerAssistRequest`-et, `ai_tutor` import nélkül (mérve: `grep -rn "ai_tutor" lib/features/practice_generator/` → 0 találat). Teszt: `planner_assist_gateway_test.dart:137-164`. |

## Scope-audit

```
python3 tools/scope-audit.py --repo /tmp/review-e07-r28 --brief docs/rounds/e07-r28-planner-assist-gateway.md --base e95bd937
→ Legacy scope audit OK (e95bd937..a1a6da38e8da, 10 changed path(s), 0 generated/ignored)
```

Engedélyezett fájlokon kívüli változás: **nincs** — a 10 módosított útvonal
pontosan a brief §4 tízes listája (5 új lib fájl, `public.dart` bővítés, 2 új
teszt, 1 új fixture, a brief saját §0.0/§10 revíziója).

## §0.0 pre-flight revízió — függetlenül újramérve

A brief §0.0 azt állítja, hogy `lib/features/ai_tutor/public.dart` fagyasztott
üres (`test/features/ai_tutor/ai_tutor_boundary_test.dart` őrzi), ezért az
adapter nem importálhatja az `ai_tutor` domain típusait. Függetlenül
ellenőrizve:

```
cat lib/features/ai_tutor/public.dart → csak "library;" + doc-comment, 0 export/import
grep -c "^## 0.0 Pre-flight" docs/rounds/e07-r28-planner-assist-gateway.md → 1
dart run tool/check_architecture.dart → "Architecture dependencies OK (12 allowlisted deviation(s))" — VÁLTOZATLAN 12, nincs új allowlist-bejegyzés
grep -rn "ai_tutor" lib/features/practice_generator/ → 0 találat
```

A revízió és az implementáció konzisztens; az `architectureAllowlist` mérete
nem nőtt.

## Megállapítások

### N1 — NOTE — Az A7 „disabled" ág a gateway saját reprezentációját teszteli, nem az élő `plannerAssistEnabled` flaget

- **Fájl:** `test/features/practice_generator/assist/planner_assist_gateway_test.dart:118-135`
- **Megfigyelés:** a teszt `FakePlannerAssistGateway.disabled()`-t hív
  közvetlenül; nincs olyan kód ebben a körben, ami a valódi
  `lib/app/config/feature_flags.dart` `plannerAssistEnabled` mezőjét egy
  gateway-választáshoz kötné. Ez STRUKTURÁLISAN elkerülhetetlen — a
  `feature_flags.dart` a brief tilos zónája —, és összhangban van az Epic 7
  eddigi köreinek (R23/R24/R26) hívó-táplált, wiring-et későbbre halasztó
  mintájával.
- **Kötelező javítás:** nincs, ebben a körben. A jövőbeli wiring-körnek kell
  majd egy olyan cellát írnia, ami a VALÓDI flag-olvasás → gateway-választás
  utat méri (nem csak a gateway saját `.disabled()` konstruktorát).
- **Státusz:** OPEN (dokumentált follow-up, nem blokkoló).

### N2 — NOTE — `remote_planner_assist_gateway.dart` generikus `catch (_)` minden hibát hálózati hibaként jelent

- **Fájl:** `lib/features/practice_generator/data/ai/remote_planner_assist_gateway.dart:61-66`
- **Megfigyelés:** a specifikus `TimeoutException`/`PlannerAssistRateLimitException`/
  `PlannerAssistNetworkException` ágak után egy `catch (_)` MINDEN egyéb
  kivételt (pl. egy jövőbeli transport-implementáció programozási hibáját is)
  csendben `networkFailure` fallback-ké alakít. Ez A4/A5 szándékos
  következménye ("bármilyen felhő-hiba → tartalék, sosem crash"), de a
  jövőbeli valódi transport-bekötésnél elfedhet egy valódi buget fejlesztés
  közben.
- **Kötelező javítás:** nincs, ebben a körben — a szándékos defenzív minta
  helyes egy OPCIONÁLIS rétegnél. A wiring-körnek érdemes lehet egy
  debug-only naplózást fontolóra vennie az általános ágon.
- **Státusz:** OPEN (dokumentált follow-up, nem blokkoló).

### N3 — NOTE — `_containsUnsafeContent` egy másodlagos heurisztika, triviálisan megkerülhető

- **Fájl:** `lib/features/practice_generator/data/ai/planner_assist_schema.dart:174-179`
- **Megfigyelés:** az `"ignore previous instructions"` pontos-substring
  keresés whitespace-variánssal vagy más nyelvű megfogalmazással megkerülhető.
  Ez NEM a fő védelem — az A2/A6 elleni tényleges gát az EXACT allowlist és a
  szerkezeti (instruction vs. untrusted-data mező) elkülönítés, ami a válasz
  TARTALMÁTÓL függetlenül tartja. A biztonsági review-t kifejezetten erre a
  kérdésre is kértem (résztezhetőség, coverage-igény a doc-commentekhez
  képest) — annak eredménye legyen az irányadó ezen a ponton.
- **Kötelező javítás:** lásd a security review jelentését.
- **Státusz:** átadva a biztonsági review-nak (nem duplikálva).

## Gate-bizonyíték ellenőrzése

| Gate | Állított eredmény | Ellenőrizve |
|---|---|---|
| format | zöld | ✅ saját futtatás, izolált `/tmp/review-e07-r28` klón |
| analyze | zöld (0 issue) | ✅ saját futtatás |
| test `planner_assist_gateway_test.dart` | zöld (6/6) | ✅ saját futtatás |
| test `planner_assist_schema_test.dart` | zöld (4/4) | ✅ saját futtatás; valódi-sértés próbával (A2) is igazolva |
| architecture | zöld, 12/12 változatlan | ✅ saját futtatás |
| secrets | zöld (0 finding) | ✅ saját futtatás |
| l10n | zöld | ✅ saját futtatás |
| CI (teljes suite + property + APK) | — | pending — merge előtti orchestrátor-lépés |

**Operatív megjegyzés (nem kód-lelet):** az implementer wrapper jelzése
`gate_shape=VIOLATION`-t és `dirty_files=1`-et is mutatott. Mindkettőt
kivizsgáltam: a `gate_shape` egy regex-alapú HAMIS POZITÍV — a naplóban
`sed -n '1,260p' tools/round-gate.sh && git status …` (a gate SAJÁT
forráskódjának `sed`-es beolvasása, `&&`-lánccal chain-elt, nem-kapcsolódó
git-inspekcióval) illesztette a mintát, a TÉNYLEGES gate-hívások
(`tools/round-gate.sh test/...`) mindig önállóan, csonkítás nélkül futottak
(`/tmp/e07-r28-round-gate.json`: `exit_code=0, outcome=pass`, teljes napló
mind a 7 lépéssel). A `dirty_files=1` egy jelzés-időpontbeli tranziens állapot
volt — a tényleges HEAD-en (`a1a6da38`) `git status --short` üres. **A
`codex-round.sh` wrapper NEM push-ol automatikusan** — az implementer
commitja csak a lokális `ss-codex-e07-r28` munkapéldányban létezett, az
orchestrátor push-olta originre a review ELŐTT (enélkül a review egy elavult
branch-fejet klónozott volna — [[L325]] rokona, de itt a push teljesen
hiányzott, nem csak a lokális ref volt elavult).

## Merge-döntés

Az ADR 0052 szerint: minden gate zöld ÉS nincs nyitott BLOCKER/MAJOR → merge
engedélyezett, a CI (teljes suite + property + APK) zöld futása UTÁN.
