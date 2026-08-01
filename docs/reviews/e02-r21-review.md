# E02-R21 — Review

Brief: `docs/rounds/e02-r21-practice-production-wiring.md`
Diff: `git diff origin/main...codex/e02-r21-practice-production-wiring` (HEAD `4381be8`, rebase-elve `f27651a`-ra)
Reviewer: Claude (Sonnet 5, orchestrátor-review) · Dátum: 2026-08-01
Verdikt: **HALT (H4)** — lásd "Update 4": az ÖTÖDIK futás, az ÖSSZES korábbi
router-infra fix (#46/#47/#48/#49/#50) UTÁN, a router állapotgépe hibátlanul
lefutott, de mind a 2 M3-kísérlet és az 1 Terra-hívás **valódi diff nélkül**
`STOPPED`-be futott — a gyökérok a `codex exec --sandbox workspace-write`
bwrap-alapú izolációja, ami ezen a konténeren nem tud hálózati namespace-t
létrehozni (`bwrap: loopback: Failed RTM_NEWADDR: Operation not permitted`,
router-független reprodukcióval igazolva). A korábbi Update 1–3 leírások
(H6/H4/H6, mind router-állapotgép-hiba, mind javítva) alább, változatlanul,
történeti okból maradnak.

## Összegzés

BLOCKER: 1

A router (`tools/ai_router`) az **első éles futásán** `READY_FOR_REVIEW`-t
(`"M3 gate passed"`) jelzett, de a munkapéldány `git status`/`git diff HEAD`
**teljesen tiszta** — az M3 implementer **egyetlen production vagy teszt
fájlt sem hozott létre vagy módosított** a §4 engedélyezett listából. A §10
implementation handoff szakasz kitöltetlen (sablon-placeholder). Egyetlen
acceptance criteria (A1–A7) sem teljesült.

## Gyökérok (mért, nem feltételezett)

A router `changed_paths` audit-ja (`tools/ai_router/router.py:233` körüli
`_scope_or_finish`, ténylegesen `tools/ai_router/security.py:61-232`
`ScopeAudit`) a **baseline manifestet a PRECHECK fázisban, a BASELINE_GATE
lefutása ELŐTT** rögzíti (`router.py:530-535`, a `capture_manifest` hívás a
`baseline_gate` hívás (`router.py:549`) ELŐTT fut). A `BASELINE_GATE` viszont
ténylegesen lefuttatja `flutter test`-et az 5 gate-útvonalon, ami elsőként
létrehozza/módosítja a `.dart_tool/` és `build/` fákat (build-cache,
asset-manifestek, hook-runner metaadatok). Amikor az M3-hívás UTÁN
(`router.py:683`) a scope-audit a **jelenlegi fát** a **BASELINE_GATE előtti**
manifesthez hasonlítja, ezt a build-cache churn-t (nem az M3 modell által írt
fájlokat) látja "changed"-nek — mérve, a task-state `changed_paths` mezője
(`~/.local/state/strumsight-ai-router/tasks/E02-R21.json`) **kizárólag**
`.dart_tool/**` és `build/**` bejegyzéseket tartalmaz, egyetlen `lib/` vagy
`test/` útvonal SEM szerepel benne:

```
"changed_paths": [
  ".dart_tool/flutter_build/dart_plugin_registrant.dart",
  ".dart_tool/hooks_runner/objective_c/0c894306e9/...",
  "build/native_assets/linux/native_assets.json",
  "build/unit_test_assets/AssetManifest.bin",
  ... (31 elem, mind .dart_tool/ vagy build/ alatt)
]
```

Ez a lista **azért nem üres** (ami a `router.py:703` `NO_CHANGE_*` ágát
váltotta volna ki, és egy újabb M3-kísérletet adott volna automatikusan),
hanem mert a BASELINE_GATE saját build-artifact melléktermékét téveszti
M3-diffnek. **Ez azt jelenti, hogy a router jelenlegi audit-sorrendje
strukturálisan minden M3-választ "sikeresnek" fog jelezni, függetlenül attól,
hogy a modell írt-e bármit** — a build-cache churn minden gate-futás után
újratermelődik.

**Reprodukáló parancs** (a jelen munkapéldányban):

```bash
cd /home/ubuntu/ss-auto-e02-r21
python3 tools/model-router.py status --task-id E02-R21 --json | python3 -m json.tool | grep -A3 '"changed_paths"'
git status --short   # üres — nincs valódi diff
```

**Javítás javasolt helye:** `tools/ai_router/router.py:530-535` — a
`capture_manifest(worktree)` hívást a `baseline_gate` (`router.py:549`) UTÁNRA
kell mozgatni (vagy a `ScopeAudit`-ot `security.py`-ban a brief
`allowed_paths` prefixére kell szűkíteni, ne a teljes fára). Ez a `tools/`
könyvtárban van, **nem** a jelen kör engedélyezett-fájllistáján
(`docs/rounds/e02-r21-practice-production-wiring.md` §4) — az orchestrátor
ezt nem javíthatja ebben a körben (H3 tilos zóna).

## Döntés

A router még nem merítette ki a keretét (`m3_attempts=1/2`, `terra_calls=0/1`)
— a protokoll szerint (orchestrátor-prompt §1.1) a lelet visszaadható
`resume`-mal ugyanannak a tasknak, mielőtt a router-hiba HALT-ot indokolna
(H4 csak a router `STOPPED` UTÁN nyitott BLOCKER/MAJOR esetén, vagy ha az
M3 + Terra keret is kimerül anélkül, hogy valódi diff született volna). Az
orchestrátor **saját kézzel auditálja a diffet a router önjelentése helyett**
minden további kísérlet után is (§3 kötelező ellenőrzés) — a router
"M3 gate passed" jelzése önmagában **nem elfogadható bizonyíték**, amíg ez a
gyökérok fennáll.

Ha a 2. M3-kísérlet (vagy az ezt követő Terra-hívás) UTÁN is üres marad a
valódi `lib/`/`test/` diff, ez a lelet **H4**-ként HALT-ol, és a router
`capture_manifest`/`ScopeAudit` sorrend-hibájának javítása az önjavító kör
(ADR 0112) feladata.

## Update — a `resume` kísérlet H6 HALT-ba futott (2026-08-01 19:41)

A fenti döntés szerint a leletet `resume`-mal adtam vissza
(`tools/ai-router-round.sh resume … .ai/review-findings-e02-r21.md`), a
`docs/rounds/e02-r21-practice-production-wiring.md` §10-be szánt formában. A
router **`BLOCKED`**-ot jelzett:

```
reason: path outside allowed scope: .ai/review-findings-e02-r21.md;
        path outside allowed scope: .codex-round-status;
        path outside allowed scope: docs/reviews/e02-r21-review.md
```

**Második, ettől független gyökérok** (`tools/ai_router/security.py:174-236`
`audit_scope`): a `resume` parancs (`tools/ai-router-round.sh`) a
review-findings fájlt **a munkapéldányon BELÜLRE** kényszeríti (exit 50, ha
kívül van), de a router saját `audit_scope`-ja a `baseline_head`-hez képest
**minden** új untracked/ignored fájlt a brief `allowed_paths` ellenőrzésnek
vet alá — beleértve az orchestrátor saját, a `resume` híváshoz szükséges
findings-fájlját, a review-jelentést, **és a router saját
`.codex-round-status` jelzőfájlját is** (ami a router/`codex-signal.sh` írja,
nem az M3 modell). A `GENERATED_IGNORED_PREFIXES`
(`security.py:20-40`) csak `.dart_tool`/`build`/Flutter-generált útvonalakat
zár ki — nincs kivétel sem a `.ai/**` (a `.ai/runs` alkönyvtáron kívül), sem a
`.codex-round-status` mintára. **Eredmény: a dokumentált `resume` +
review-findings munkafolyamat (orchestrátor-prompt §1.1, "a leleteket
fájlban add vissza") strukturálisan összeütközik a scope-audittal, valahányszor
az orchestrátor a findings-fájlt a munkapéldányba írja — pontosan ahogy az
utasítás előírja.**

Mindkét M3-kísérlet (2/2) elfogyott: az 1. kísérlet eredménye a fenti
build-cache-audit hiba miatt nem mérhető (lásd fent), a 2. kísérlet valódi
kimenetét ez a scope-hiba elfedte, mielőtt a gate lefuthatott volna rá. A
Terra-keret (0/1) érintetlen, de a task-állapot **BLOCKED** (terminal) —
`run`/`resume` további hívása a `reset` CLI nélkül ugyanezt a BLOCKED
eredményt adja vissza. A `reset` a task-számlálókat (m3_attempts,
terra_calls, gate_history) is nullázná, ami a jelen bizonytalan
kimenetel (1. kísérlet mérhetetlen, 2. kísérlet elfedve) mellett új,
tiszta 2+1 keretet adna anélkül, hogy a mögöttes két hiba javítva lenne —
ez a döntés (mikor/hogyan induljon újra a task) a saját hatáskörömön (a kör
saját, engedélyezett fájllistáján) túlmutat, és `tools/ai_router` módosítása
nélkül ismét ugyanoda vezethet.

**HALT — H6**, az önjavító kör feladata:
1. `tools/ai_router/router.py:702-703` — a "csinálta-e valamit az M3"
   ellenőrzés (`audit.changed_paths`) szűrje ki a generált/ignorált
   útvonalakat (a violation-check már helyesen kizárja őket, a
   "volt-e valódi diff" check ma nem).
2. `tools/ai_router/security.py:20-49` `GENERATED_IGNORED_PREFIXES`/`GLOBS` —
   vegye fel a `.codex-round-status`-t és egy dedikált, orchestrátor-írta
   findings-útvonalat (pl. `.ai/orchestrator/**`), hogy a `resume` +
   review-findings munkafolyamat ne ütközzön önmagával.
3. Kötelező regressziós teszt mindkettőre (`tools/tests/test_router*.py`
   már meglévő minták szerint) — reprodukálva: sikeres M3-gate futtatás
   **valódi forrásváltozás nélkül** ne adjon `READY_FOR_REVIEW`-t; egy
   `.codex-round-status`-t tartalmazó munkapéldányon a `resume` ne adjon
   `BLOCKED`-ot.
4. A jelen task-state (`~/.local/state/strumsight-ai-router/tasks/E02-R21.json`,
   `status=BLOCKED`) `reset --task-id E02-R21`-gyel oldható, **csak a fenti
   két javítás UTÁN**, majd a kör friss `run`-nal indítható (a brief/ADR
   pre-flight már kész, nem kell újraírni).

## Update 2 — a self-heal (#46/#47) UTÁNI friss `run` is HALT-ba futott, ÚJ gyökérokkal (2026-08-01 20:16)

A fenti két hiba javítva lett (`72cea1c`, `35f6da1`, PR #46/#47, zöld
`Router CI`), a task-state `reset --task-id E02-R21`-gyel `NOT_STARTED`-re
állt, a HANDOFF a láncot a következő firingen friss `run`-ra jelölte. Ez a
session (Pipeline E02-R21, új futás) a branchet `origin/main`-re rebase-elte
(hogy a self-heal fixek benne legyenek a munkapéldányban is,
`d45e6ce06c7e4602fd6b67b2f82dfb25235d5e90`), majd elindította a friss `run`-t.

**Mérve, mi történt** (a `~/.local/state/strumsight-ai-router/tasks/E02-R21.json`
`gate_history`-ja és a végállapot):

```
BASELINE_GATE          pass
GATE_1                 pass
NO_CHANGE_1             code_failure  "model produced no scoped changes"   <- az #1 javítás ITT helyesen fogta meg (nem regresszió)
RECOVERED_M3_ATTEMPT_2 pass  (de audit.scoped_changed_paths üres -> code_failure-ra konvertálva, router.py:603-610)
FINAL_GATE             pass  (Terra hívás után)
```

Végállapot: `status=READY_FOR_REVIEW`, `reason="final gate passed"`,
`m3_attempts=2` (kimerítve), `terra_calls=1` (kimerítve),
**`changed_paths=[]`**, `last_diff_hash` = az ÜRES string SHA-256-a
(`e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855`).

**Az orchestrátor önkezű auditja** (a §3 kötelező ellenőrzés — a router
önjelentése soha nem elfogadható bizonyíték önmagában):

```bash
cd /home/ubuntu/ss-auto-e02-r21
git status --short      # üres
git diff HEAD --stat    # üres
```

**A `READY_FOR_REVIEW` jelzés HAMIS** — a munkapéldányban egyetlen fájl sem
változott, egyetlen A1–A7 acceptance criteria sem teljesült, a §10
implementation handoff kitöltetlen maradt.

### Gyökérok (mért, nem feltételezett) — ÚJ, a H6-tól különböző hiba

Az M3-kísérleti ág (`router.py:709-721`, a `while` ciklusban) helyesen zárja ki
az "sikeres gate, de nincs valódi scope-diff" esetet:

```python
if current_gate.outcome == "pass":
    if audit is not None and not audit.scoped_changed_paths:
        current_gate = GateRun("code_failure", "model produced no scoped changes", ...)
        self._record_gate(state, f"NO_CHANGE_{attempt}", current_gate)
        ...
        continue
```

A **Terra-ág** (`_terra()`, `router.py:426-432`) **NEM tartalmazza ugyanezt az
őrt**:

```python
final_gate = self.run_gate(worktree, brief.metadata.gate_tests, brief.metadata.native_gate)
self._record_gate(state, "FINAL_GATE", final_gate)
self.state.save_task(brief.task_id, state)
if final_gate.outcome == "pass":
    return self._finish_terra(
        state, RouterStatus.READY_FOR_REVIEW, "final gate passed", result_path
    )
```

Itt `final_gate.outcome == "pass"` önmagában elég a `READY_FOR_REVIEW`-hoz —
az `audit.scoped_changed_paths`-t (amit a `_scope_or_finish` hívás a 416-425.
sorban már kiszámolt és elérhető) **nem nézi meg**. Ha a Terra-modell nem ír
semmit, a triviálisan zöld gate (semmi nem változott, minden meglévő teszt
továbbra is fut) `READY_FOR_REVIEW`-t jelez.

**Ugyanez a hiányzó őr megismétlődik a `TERRA_REVIEW_OR_FIX` resume-ágban is**
(`router.py:635-645`, a `RECOVERED_FINAL_GATE` mérés) — folyamat-megszakítás
utáni `run` esetén ugyanígy nem ellenőrzi az `audit.scoped_changed_paths`-t,
mielőtt `READY_FOR_REVIEW`-t adna vissza.

**Javítás javasolt helye:** `tools/ai_router/router.py:429` és `:639` — egy,
az M3-ág 709-710. sorával **azonos mintájú** őr: `final_gate.outcome ==
"pass"` ÉS `audit is not None` ÉS `audit.scoped_changed_paths` **együtt**
szükséges a `READY_FOR_REVIEW`-hoz; üres diff esetén a Terra-hívás (mivel ez
a task teljes, kimerített kerete — 2/2 M3 + 1/1 Terra) `BLOCKED`-ot vagy
`STOPPED`-ot kell jelezzen, nem `READY_FOR_REVIEW`-t. Kötelező regressziós
teszt (`tools/tests/test_router*.py` mintájára): sikeres Terra-gate futtatás
**valódi forrásváltozás nélkül** ne adjon `READY_FOR_REVIEW`-t — sem a
`_terra()` direkt ágon, sem a `TERRA_REVIEW_OR_FIX` resume-ágon.

**Reprodukáló parancs** (a jelen munkapéldányban, a task-state még érintetlen
a HALT pillanatában):

```bash
python3 tools/model-router.py status --task-id E02-R21 --json | python3 -m json.tool | grep -A2 'changed_paths\|terra_calls\|m3_attempts\|status'
cd /home/ubuntu/ss-auto-e02-r21 && git status --short && git diff HEAD --stat
```

### Döntés

A router teljes kerete kimerült (2/2 M3-kísérlet, 1/1 Terra-hívás) **valódi
diff nélkül** — ez pontosan az a forgatókönyv, amit az Update 1 Döntés
szakasza előre jelzett: *"Ha a 2. M3-kísérlet (vagy az ezt követő Terra-hívás)
UTÁN is üres marad a valódi lib/test diff, ez a lelet H4-ként HALT-ol."*
`resume`-mal való visszaadás itt értelmetlen (a `state.status=READY_FOR_REVIEW`
és a teljes keret elfogyott — a router `_terra()` `STOPPED`-ot adna vissza
egy újabb `run`-ra a "task Terra budget is exhausted" üzenettel, findings
nélkül is). Az A1–A7 egyike sem teljesült, a Practice V2 production-drótozás
(a kör tényleges célja) **továbbra sincs elkezdve**.

**HALT — H4.** Az önjavító kör feladata:
1. `tools/ai_router/router.py:429` (`_terra()`) és `:639`
   (`TERRA_REVIEW_OR_FIX` resume) — vegye fel az M3-ág 709-710. sorával
   azonos `audit.scoped_changed_paths` őrt a `READY_FOR_REVIEW` visszaadása
   előtt.
2. Kötelező regressziós teszt mindkét ágra.
3. A task-state (`status=READY_FOR_REVIEW`, de a keret kimerült) `reset
   --task-id E02-R21`-gyel oldható, **csak a fenti javítás UTÁN**, majd a kör
   friss `run`-nal indítható (a brief/ADR pre-flight változatlanul kész).
4. **Megfontolandó** (nem kötelező ebben a körben): mivel ez már a MÁSODIK,
   szerkezetileg különböző "üres diff mégis READY_FOR_REVIEW" hiba
   ugyanabban a task-ban, az önjavító kör mérlegelheti egy harmadik,
   közös helyen (`_finish`/`_finish_terra` előtt, minden READY_FOR_REVIEW
   visszatérési útra) elhelyezett egyetlen véd-pontot ahelyett, hogy minden
   egyes ágba külön-külön kerülne be ugyanaz az ellenőrzés.

## Update 3 — a self-heal (#48, H4 fix) UTÁNI friss `run` DEFERRED-be futott, HARMADIK, a ledger-perzisztencia hibájából (2026-08-01 21:00)

A H4 javítás (`ec81ef8`, PR #48, `_terra()` FINAL_GATE + `TERRA_REVIEW_OR_FIX`
resume-ág `audit.scoped_changed_paths` őrrel) zöld `Router CI`-vel landolt
`main`-en. Ez a session (Pipeline E02-R21, harmadik önjavítás utáni friss
futás) a branchet rebase-elte `origin/main`-re
(`7bdc175`, tartalmazza `ec81ef8`-at), majd:

```bash
python3 tools/model-router.py reset --task-id E02-R21
# → {"schema_version": 1, "status": "NOT_STARTED", "task_id": "E02-R21"}
```

utána friss `run`-t indított. **Mérve, mi történt:**

```
BASELINE_GATE            pass
GATE_1                   pass
NO_CHANGE_1               code_failure  "model produced no scoped changes"
RECOVERED_M3_CALL_2      pass   (m3_attempts kimerítve, 2/2)
→ Terra hívás szükséges → DEFERRED "task Terra budget is exhausted"
```

Végállapot: `status=DEFERRED`, `phase=DEFERRED`, `reason="task Terra budget is
exhausted"`, `m3_attempts=2`, `terra_calls=0` (a task saját `state.json`
számlálója **soha nem jutott el** a Terra hívásig — a `reserve_terra()` a
hívás ELŐTT dobja a hibát).

**Orchestrátor önkezű audit** (§3 kötelező ellenőrzés):

```bash
cd /home/ubuntu/ss-auto-e02-r21
git status --short && git diff HEAD --stat   # mindkettő üres — nincs valódi diff, ahogy a router is jelezte (helyesen, ezúttal)
```

### Gyökérok (mért, nem feltételezett) — HARMADIK, a H4/H6-tól különböző router-hiba

`reset --task-id` (`tools/model-router.py:252-256` → `StateStore.reset_task`,
`tools/ai_router/state.py:131-144`) **kizárólag** a
`~/.local/state/strumsight-ai-router/tasks/<task-id>.json` fájlt törli. A
docstring explicit ígéretet tesz: *"Clear a persisted task state so the next
`run` re-prechecks from scratch. […] a stuck terminal state […] can always be
cleared."* — ez az ígéret **nem teljesül** a Terra-kvótára.

A Terra-hívás foglalása (`StateStore.reserve_terra`,
`tools/ai_router/state.py:167-203`) egy **külön, nem törölt** perzisztens
naplóból (`~/.local/state/strumsight-ai-router/terra-ledger.json`) dönt:

```python
daily_count = sum(1 for row in reservations
                   if row.get("utc_day") == day and row.get("status") in active)   # NAP-hoz kötött
task_count = sum(1 for row in reservations
                  if row.get("task_id") == task_id and row.get("status") in active) # ÖRÖKRE, nap nélkül!
...
if daily_count >= daily_limit:
    raise TerraBudgetError("automatic Terra daily budget is exhausted")
if task_count >= task_limit:                # <-- itt: task_limit=1 (config.py:105 kikényszerítve)
    raise TerraBudgetError("task Terra budget is exhausted")
```

A `daily_count` szűr `utc_day`-re, a `task_count` **nem** — a
`terra-ledger.json`-ban az E02-R21 taskhoz a **mai H4-előtti** futásból egy
`"status": "finished"` bejegyzés maradt (`reservation_id=6ef544b9…`,
`reserved_at=2026-08-01T20:24:01Z`). Mivel `max_terra_calls_per_task=1`
(`config.py:105-106`, kényszerített invariáns), ez az egyetlen, réges-régi
bejegyzés **örökre** kimeríti az E02-R21 task Terra-kvótáját — a
`reset --task-id` a `tasks/E02-R21.json`-t törli, de a
`terra-ledger.json` sorait NEM, ezért a "fresh start" ígéret hamis, amint a
taskhoz valaha is történt egyetlen Terra-foglalás.

**Reprodukáló parancs** (a jelen munkapéldányban):

```bash
python3 -c "
import json
d = json.load(open('/home/ubuntu/.local/state/strumsight-ai-router/terra-ledger.json'))
print([r for r in d['reservations'] if r['task_id'] == 'E02-R21'])
"
# → egy 'finished' bejegyzés a mai napról, a H4-fix ELŐTTI futásból
python3 tools/model-router.py reset --task-id E02-R21   # "sikeres" reset
# ... friss run() 2 M3-kísérlet után Terra-hívást próbál:
# reserve_terra() -> task_count(1) >= task_limit(1) -> TerraBudgetError("task Terra budget is exhausted")
# -> DEFERRED, exit 30, .pipeline/router-status: status=blocked reason="task Terra budget is exhausted"
```

**Javítás javasolt helye (kettő közül egy, az önjavító kör választ):**
1. `tools/ai_router/state.py:184-188` — a `task_count` szűrőjéhez vegye fel a
   `daily_count`-tal azonos `row.get("utc_day") == day` feltételt, ha a
   szándék "1 Terra-hívás/task/nap" (konzisztens a `max_automatic_terra_calls_per_utc_day`
   napi-kvóta névvel és a `daily_count` mintájával); VAGY
2. `tools/ai_router/state.py:131-144` (`reset_task`) — a task-state törlésével
   egyidejűleg (ugyanabban a `_ledger_lock()`-ban) jelölje archívnak/távolítsa
   el a `terra-ledger.json` adott `task_id`-hez tartozó sorait, hogy a
   docstring "re-prechecks from scratch" ígérete a Terra-kvótára is
   teljesüljön.
   Kötelező regressziós teszt mindkét esetre (`tools/tests/test_router*.py`
   mintájára): `reset --task-id` UTÁN egy korábban Terra-t felhasznált task
   ismét tudjon Terra-t foglalni (1. javításnál csak másnap / eltérő
   `utc_day`-jel, 2. javításnál azonnal).

### Döntés

Ez router-infrastruktúra hiba (`tools/ai_router/state.py`), a jelen kör
engedélyezett-fájllistáján (`docs/rounds/e02-r21-practice-production-wiring.md`
§4) kívül — az orchestrátor ezt nem javíthatja (H3 tilos zóna). A DEFERRED
állapot a strukturált leképezés szerint (orchestrátor-prompt §1.1) `blocked`
kör-jelzés, HALT — de a kvóta **nem** fog "magától" helyreállni, mert a
`task_count` szűrő nem nap-alapú: a self-heal javítása nélkül az E02-R21 task
Terra-kvótája **véglegesen** kimerült marad, függetlenül attól, hány `reset`
történik. A Practice V2 production-drótozás (a kör tényleges célja)
**továbbra sincs elkezdve** — ez a HARMADIK önjavító kör ugyanezen a taskon,
mindhárom alkalommal router-infrastruktúra hibával, nem a briefben vagy az
implementáció tartalmában.

**HALT — H6** (a router `DEFERRED` eredménye a strukturált leképezés szerint
`blocked` kör-jelzés). Az önjavító kör feladata:
1. A fenti két javítási lehetőség egyike `tools/ai_router/state.py`-ban,
   kötelező regressziós teszttel.
2. A `terra-ledger.json` jelen E02-R21 sorának kezelése a javítás
   természetétől függően (1. javításnál nem kell bántani, másnap magától
   elévül; 2. javításnál a `reset --task-id E02-R21` újrafuttatása törli).
3. A brief/ADR pre-flight változatlanul kész (`4eb331f`/`ec81ef8` utáni
   rebase, `7bdc175`) — nem kell újraírni.

## Update 4 — az első ÉLES `run` (a H4/H6 #48/#49/#50 fixek UTÁN) STOPPED-be futott, ÖTÖDIK halt, de ELSŐ olyan, ahol a router-infrastruktúra maga mérve HIBÁTLAN (2026-08-01 22:34)

**Ez NEM router-infrastruktúra hiba** — ez az első alkalom, hogy a router
(minden korábbi H4/H6 javítással: #46/#47/#48/#49/#50) hibátlanul, elejétől
végig lefutott: `python3 tools/model-router.py run` a munkapéldányon
(rebase-elve `origin/main`-re, `f27651a`-ra, mind az öt korábbi fix benne)
2 M3-kísérletet + 1 Terra-hívást futtatott, a gate-előzmény (`state.py`
task-fájlja) mind a hármat helyesen látta: a `round-gate.sh` mindháromszor
**pass**-t adott (a repo baseline-ja zöld maradt), de **egyik modellhívás sem
hozott létre egyetlen scope-on belüli fájlváltozást sem**
(`scoped_changed_paths=[]`, `last_diff_hash` = az üres string SHA-256-ja
mind a három próbán). A router ezt helyesen `NO_CHANGE_1` / `NO_CHANGE_2` /
`FINAL_GATE: "Terra call produced no scoped changes"` `code_failure`-ként
könyvelte el, és a teljes keret kimerülése után korrekt `STOPPED`-et jelzett
(§1.1 táblázat szerint `stopped` kör-jelzés) — **a router döntéslogikája ezen
a ponton mérve helyes**.

### Gyökérok (mért, reprodukálva, nem feltételezett) — a `codex exec` sandbox módja inkompatibilis ezzel a konténerrel

A modellek (M3 ÉS Terra egyaránt) nem hibáztak — **nem tudtak dolgozni**.
Diagnosztikai lépések (mindegyik ÚJRA lefuttatva, a jelen munkapéldányban,
mellékhatás nélkül):

1. `python3 tools/model-router.py smoke --profile m3 --worktree <munkapéldány>`
   → `M3_OK` (exit 0); ugyanígy `--profile terra` → `TERRA_OK` (exit 0). A
   profilok, a hitelesítés és a CLI-integráció **hibátlanok** — de a smoke
   próba `--sandbox read-only`-val és egy triviális szöveges válasszal
   (`_smoke()`, `tools/model-router.py:165-196`) SOSEM hív `exec_command`-ot,
   ezért nem fedi fel a valódi hibát.
2. A pontos induló promptot (`DevelopmentRouter._initial_prompt`,
   `tools/ai_router/router.py:347-360`) újra elküldve `--sandbox read-only`
   móddal az M3 profilnak: a modell **helyesen megtagadta** a végrehajtást, és
   pontos diagnózist adott vissza (`item.completed`/`agent_message`, teljes
   szöveg a jelen review commit mellékleteként a `.ai/runs/E02-R21/` alatt
   NEM tárolt, de a stderr-ben mérve):
   > „Every `exec_command` invocation exits immediately with `bwrap:
   > loopback: Failed RTM_NEWADDR: Operation not permitted`, including
   > `true`, `echo`, `id`, `printenv|. The bwrap sandbox cannot create a
   > network namespace on this container, so no shell ever spawns.”
3. **Közvetlen, router-független reprodukció** (a konténer bwrap-képessége
   önmagában, `codex` nélkül):
   ```
   bwrap --unshare-net --dev-bind / / true
   # → bwrap: loopback: Failed RTM_NEWADDR: Operation not permitted (exit 1)
   ```
   Ez a **pontosan ugyanaz** a hiba, konzisztensen, kódex/modell nélkül —
   tehát ez a konténer NEM tud hálózati namespace-t létrehozni (hiányzó
   `CAP_NET_ADMIN` vagy egyenértékű host-korlátozás), ami a `bwrap`
   alapértelmezett hálózat-izolációjának előfeltétele. Ez nem tranziens
   erőforrás-kimerülés (214 meglévő net-namespace a `/proc/*/ns/net`
   alapján, messze a szokásos limit alatt) — **állandó, ma is
   reprodukálható** konténer-képesség-hiány.
4. **A hívási lánc, ahol ez becsapódik:**
   `tools/ai_router/execution.py:88-105` (`build_codex_argv`) a router
   VALÓDI (nem-smoke) modellhívásaihoz `"--sandbox", "workspace-write"`-et
   ad át — ez a `codex` CLI-ben `bwrap`-alapú izolációt igényel Linuxon,
   ami ezen a boxon nem működik. Ezzel szemben a **létező, működő**
   örökölt manuális útvonal (`tools/codex-round.sh:31`) már
   `-s danger-full-access`-t használ, pontosan ezért — a
   `sdd-round-driver` skill saját dokumentációja is kimondja: „A wrapper
   `-s danger-full-access`-szel fut (a bwrap itt nem megy) — az izolációt
   a külön munkapéldány adja.” A router `execution.py`-ja ezt a mért,
   dokumentált box-tényt SOSEM vette át, amikor a `build_codex_argv`
   megszületett (ADR 0088) — ez az ELSŐ alkalom, hogy ez ténylegesen
   próbára lett téve, mert az előző négy halt mind korábban, a router
   saját állapotgép-logikájában bukott el, mielőtt valódi M3/Terra-hívás
   egyáltalán megtörténhetett volna gate-passzoló, de tartalom nélküli
   végkimenetellel.

**Miért nem fogta meg a baseline/smoke gate:** a `BASELINE_GATE` és a
`round-gate.sh` a MEGLÉVŐ (változatlan) kódot futtatja — egy zöld baseline
zöld marad akkor is, ha a modell soha nem ér hozzá egyetlen fájlhoz sem. A
`smoke` parancs pedig szándékosan `read-only` sandboxot és egy
`exec_command`-ot sosem igénylő promptot használ — így strukturálisan vak
erre a hibaosztályra.

**Javítás javasolt helye (az önjavító kör dolga, ez a session nem nyúlhat a
`tools/`-hoz):**
1. `tools/ai_router/execution.py:100-101` — `"workspace-write"` cseréje
   `"danger-full-access"`-ra a `build_codex_argv`-ban (mindkét profilra,
   M3-ra és Terra-ra egyaránt; az izolációt — a `codex-round.sh` mintájával
   konzisztensen — a külön munkapéldány adja, nem a bwrap-sandbox).
2. Érdemes a `_smoke()` (`tools/model-router.py:165-196`) próbát is
   kiegészíteni egy valódi `exec_command`-ot igénylő lépéssel (pl. `echo
   SMOKE_EXEC_OK` futtatása a modellel), hogy ez a hibaosztály jövőben a
   smoke-fázisban bukjon el, NEM a teljes M3+Terra keret felégetésével.
3. Kötelező regressziós teszt (`tools/tests/test_router*.py` mintájára): a
   `build_codex_argv` sandbox-argumentuma `danger-full-access`, nem
   `workspace-write` — string-szintű assert elég, mert a tényleges bwrap-hívás
   ezen a boxon nem tesztelhető CI-ban (más konténer-környezet).
4. A production task-state (`E02-R21`) `reset --task-id`-t igényel a fix
   UTÁN, mielőtt a lánc újra `run`-t próbál — az M3 (2/2) és Terra (1/1)
   kerete jelenleg kimerült egy sandbox-hibával, nem tartalmi okkal.

### Döntés

**HALT — H4** (`auto` engine, a router `STOPPED`-et jelzett, §1.1 táblázat
szerint `stopped` kör-jelzés → azonnali HALT, további modellhívás tilos). Ez
egy ÖTÖDIK önjavító/halt kör ugyanezen a taskon, de az ELSŐ, ahol a hiba nem
a router állapotgépében (`tools/ai_router/router.py`/`state.py`) van, hanem
a `execution.py` sandbox-választásában — egy a boxra vonatkozó, a
`codex-round.sh`-ban már ismert és kezelt tény, amit a router saját
Codex-hívása nem vett át. A Practice V2 production-drótozás (a kör tényleges
célja) **továbbra sincs elkezdve** — a munkapéldány `git diff HEAD` üres.
Reprodukálva, mérve, a javítás pontos helyével — a self-heal kör bemenete
kész.
