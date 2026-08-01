# E02-R21 — Review

Brief: `docs/rounds/e02-r21-practice-production-wiring.md`
Diff: `git diff origin/main...codex/e02-r21-practice-production-wiring` (HEAD `d45e6ce`)
Reviewer: Claude (Sonnet 5, orchestrátor-review) · Dátum: 2026-08-01
Verdikt: **HALT (H4)** — lásd "Update 2": a self-heal (#46/#47) után indított
friss `run` a teljes M3+Terra keretet (2/2 + 1/1) kimerítette **valódi diff
nélkül**, egy a Terra-ágban hiányzó `audit.scoped_changed_paths` őr miatt
(a §0.0 update 1 leírásában szereplő eredeti H6-tól különböző, új router-hiba).
Az eredeti H6 (Update 1) leírás alább, változatlanul, történeti okból marad.

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
