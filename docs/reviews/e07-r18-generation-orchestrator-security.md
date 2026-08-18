# E07-R18 — Security / privacy / prompt-injection review

Brief: `docs/rounds/e07-r18-generation-orchestrator.md` (`risk = "high"` — a
kötelező trigger a `security-reviewer` agent bevetésére)
Diff: `git diff 585a1c62..34db7a6f`, izolált klón `/tmp/review-E07-R18`
Reviewer: `security-reviewer` agent (dispatch-elve a Claude orchestrátor
által) · Dátum: 2026-08-18
Verdikt: **PASS**

## Összegzés

CRITICAL: 0 · BLOCKER: 0 · MAJOR: 0 · MINOR: 0 · NOTE: 4 (mind előre-tekintő,
egy jövőbeli kör felé)

## Verdikt-indoklás

A kör tisztán in-memory, alkalmazás-szintű orchestráció: a már meglévő
evidence/estimate/priority/candidate/time-budget/scheduling/review-queue/
validator/repairer domain-szolgáltatásokat fűzi össze, majd egyetlen,
**ebben a körben implementálatlan** `GenerationPlanActivation.activate(plan)`
seamet hív. Mért tények:

- **Nincs sink.** `grep -nE "print|log|Logger|dart:io|dio|http|File\(|toJson|jsonEncode|SecureStorage|SharedPreferences|analytics|debugPrint|stderr"` a 3 új lib-fájlon: **0 találat.**
- **Nincs bekötve.** `GenerationOrchestrator`/`PlanGeneratorController`/`GenerationPlanActivation`-nek **nincs** hívója a `lib/`-en belül az új fájlokon + barrelen kívül; `activate()`-nek nincs valódi implementációja, csak teszt-dupék.
- **Prompt-injection N/A:** nincs AI-provider hívás, nincs tool-calling, nincs KB-lekérdezés, nincs fájl/MXL/MIDI import, nincs promptépítés ebben a körben.
- A brief `risk="high"`-ja a **korrektségi** kockázatra vonatkozik (részleges/
  korrupt terv eljut a tanulóhoz, §5.2) — ezt a kód strukturálisan
  kikényszeríti (egyetlen, pipeline-vég `activate` hívás, fail-closed
  catch-all, kikényszerített immutable állapotgép). A biztonsági/adatvédelmi
  támadási felület minimális.

## Ellenőrzött kérdések

**1. Érzékeny/user-note adat log/crash-report/export felé?** Nincs
reprodukálható szivárgás ebben a körben.
- A `goals: input.request.goals` (`generation_orchestrator.dart:201`) a
  `PracticeGoal` szabad szöveges `userNote`/`songReference` mezőit
  tranzitívan hordozza (`adaptive_practice_plan.dart:236`), de a plan-objektum
  az **implementálatlan** `activation.activate` seamnél végződik (:154);
  semmi nem szerializálja/logolja. A presentation-safe `toSummary()` (:79-88)
  kihagyja a note-okat. → **NOTE-1**.
- `UnknownFailure(cause: error, stackTrace: stackTrace)` (:161): minden
  ezen az ágon dobható hiba (`ArgumentError.value` az assembly-ben,
  `StateError('No catalog candidate matches ...')` :304) katalógus-
  azonosítókat/összeépített ID-ket/időtartamokat hordoz — **soha** nem
  `userNote`/`songReference`/`discomfort` self-report szöveget (grep = 0
  találat az új fájlokban). Az `AppFailure.toString()` explicit KIZÁRJA a
  `cause`-t (`app_failure.dart:112-115`), a logolás a redaktáló loggeren
  megy át — ez a projekt bevett, jóváhagyott mintája. → **NOTE-2**
  (maradék kockázat: egy jövőbeli hívó, aki `failure.cause.toString()`-ot
  renderelne a redaktáló logger helyett, katalógus-azonosítókat tenne
  láthatóvá — ma ilyen hívó nincs).

**2. AGENTS.md §5 termékhatárok.** Nem érintett. Nincs audio, kamera,
secret/token, engedélykérés, hálózat, storage ebben a körben (grep-mérve).
100% eszközön belüli, in-memory; az offline élményt nem rontja (nincs cloud
útvonal, amit ronthatna).

**3. §5.1 prompt-injection / külső tartalom útvonalként-fájlnévként.**
Prompt-injection N/A. `DayId('${input.planId.value}.day.${decision.date}')`
(:217) és `BlockId('${dayId.value}.block.$order')` (:274) **fail-closed**:
az ID-konstruktorok `^[A-Za-z0-9._:-]+$`-t kényszerítenek
(`planner_ids.dart:158-174`), rossz karakterre dobnak (→ elkapva →
`UnknownFailure`). Az ütközés is fail-closed, nem néma korrupció:
`AdaptivePracticePlan._requireUnique(days)` dob duplikált dátumra
(`adaptive_practice_plan.dart:42-43`), a `PracticeDay` maga is újra-
validálja az egyedi block-ID-kat (`practice_day.dart:26-29`). → **NOTE-3**
(csak jövőbeli megerősítés: a `.` egyszerre szeparátor és legális ID-karakter,
tehát a lapos string-grammatika nem bizonyíthatóan injektív tetszőleges
`planId`-ra — de a valódi ütközést már ma is elkapja a rendszer).

**4. `GenerationPlanActivation` kontraktus egy jövőbeli implementációra
nézve.** A `Future<void> activate(AdaptivePracticePlan plan)` (:28-30) nem
dokumentál (a) idempotenciát — egy retry a MÁR aktivált `plan.id`-ra ismét
hívná `activate()`-et; (b) atomicitást — a "nincs részleges aktiválás" csak
a seam FELETT kényszerített, egy jövőbeli, több lépéses, nem-atomikus write
alatta még mindig részlegesen perzisztálhatna; (c) authz/owner-ellenőrzést.
Ma nincs reprodukálható hiba (az implementáció hiányzik), de ez a
legérdemibb NOTE. → **NOTE-4**: dokumentáld idempotencia + atomicitás +
"az implementáció felelős az authz-ért" elvárást ezen az interfészen,
MIELŐTT a Kör 19 megírja a repository-t.

**5. Belesült secret/API-kulcs/valós user-adat?** Nincs. Secret-mintázat
scan a teljes diffen (`api_key|secret|token|password|bearer|AKIA…|sk-…|ghp_…|eyJ…|-----BEGIN`)
= **0 találat**. Mindkét új tesztfájl szintetikus ID-kat használ
(`request.1`, `plan.1`, `plan.controller`, `revision.1`); a `buildGoal()`
fixture nem ültet `userNote`-ot vagy más PII-t.

## Megállapítások

| # | Súlyosság | Fájl:sor | Leírás | Irány |
|---|---|---|---|---|
| NOTE-1 | NOTE | `generation_orchestrator.dart:201` → `adaptive_practice_plan.dart:236` | Az összeállított terv tranzitívan hordozza a szabad szöveges `userNote`/`songReference`-t. Ártalmatlan ma (az implementálatlan `activate`-nél végződik). | Kör 19+ (repository-write) / jövőbeli export-út `toSummary()`-t vagy redaktort használjon minden eszközön-kívüli/AI sinkhez. |
| NOTE-2 | NOTE | `generation_orchestrator.dart:161`; `app_failure.dart:106-115` | `UnknownFailure.cause` nyers hibát hordoz (katalógus-azonosítók, NEM PII); biztonságos, mert a `toString()` kizárja és a redaktáló logger kezeli. | Tartsd meg a mai mintát — csak a redaktáló loggeren át renderelj. |
| NOTE-3 | NOTE | `generation_orchestrator.dart:217,274`; `planner_ids.dart:158-174` | A lapos ID-grammatika nem bizonyíthatóan injektív, de minden valódi ütközést fail-closed elkap. | Opcionális jövőbeli hardening: dedikált szeparátor/hossz-prefix, ha a `planId` valaha külső forrásból jönne. |
| NOTE-4 | NOTE | `generation_orchestrator.dart:28-30,291` | Az aktivációs interfész nem dokumentál idempotenciát/atomicitást/authz-t; az `evidenceRefs` a `scheduled.identity`-t nyers formában hordozza egy jövőbeli JSON-sinkbe. | Kör 19 ELŐTT dokumentáld a három elvárást az interfészen. |

## Merge-döntés (biztonsági szempontból)

A biztonsági/adatvédelmi/prompt-injection dimenzió **nem blokkolja** a
merge-et — mind a 4 lelet NOTE, jövőbeli körnek szóló, nem ennek a körnek a
hibája. A tényleges merge-blokkoló lelet(ek) a fő review-jelentésben vannak:
[`e07-r18-generation-orchestrator-review.md`](e07-r18-generation-orchestrator-review.md)
(F1 BLOCKER, F2 MAJOR).
