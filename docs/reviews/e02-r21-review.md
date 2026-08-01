# E02-R21 — Review

Brief: `docs/rounds/e02-r21-practice-production-wiring.md`
Diff: `git diff origin/main...codex/e02-r21-practice-production-wiring` (HEAD `b3c4cc4`)
Reviewer: Claude (Sonnet 5, orchestrátor-review) · Dátum: 2026-08-01
Verdikt: **HALT (H6)** — a router task-állapota `BLOCKED`-ba futott a javító kör
(`resume`) közben, mielőtt bármit mérni lehetett volna a 2. M3-kísérletről.

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
1. `tools/ai_router/router.py:702-703` — a "csinált-e valamit az M3"
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
