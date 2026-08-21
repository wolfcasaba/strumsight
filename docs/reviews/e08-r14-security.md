# E08-R14 — Security review

Brief: `docs/rounds/e08-r14-achievement-evaluator-and-projection.md`  
Reviewed head: `ae703918`
Reviewer: független Codex / `gpt-5.6-sol` security reviewer · 2026-08-21  
Verdikt: **PASS**

## Összegzés

CRITICAL: 0 · BLOCKER: 0 · MAJOR: 0 · MINOR: 0 · NOTE: 2

S1–S5 a Terra javítócommitjában, S6 az exact `ae703918` H4 self-heal
commitban lezárult. A backfill a 10 001. nyers elemnél, még dátumszűrés és
rebuild előtt fail-fast `ArgumentError`-t ad; a független mutációs próba az őr
nélkül célzottan piros, restore után zöld.

## Leletek

### S1 — BLOCKER — Ledger namespace collision forged completiont enged

`achievement_evaluator.dart:223,274` prefix alapján completionnek fogad sort,
de nem ellenőrzi a `ledgerId`, zero-XP és `achievementUnlocked` invariánst.
A canonical activity event ID csak non-blank, a normál receipt ezt használja
source ID-ként, ezért prefix-ütközés valós inputból is létrejöhet.

**Státusz:** RESOLVED (`11fb1ac2`).

### S2 — BLOCKER — Párhuzamos külön trigger duplikált unlock receiptet ír

`achievement_evaluator.dart:223,237,304`: a pre-check és append külön, a dedup
kulcs triggerenként eltér. A local repository csak exact source ID-t zár ki,
így két bejegyzés sikeresen bekerülhet.

**Státusz:** RESOLVED (`11fb1ac2`).

### S3 — MAJOR — Duplicate history event progresszt inflál

`achievement_evaluator.dart:336,396`: count és sequence lista-előfordulást
számol, stabil event ID dedup nélkül.

**Státusz:** RESOLVED (`11fb1ac2`).

### S4 — MAJOR — A backfill future eventet és rendezetlen timestampet elfogad

`achievement_evaluator.dart:170-180`: csak a cutoff előtti eventet szűri; az
anchor utáni event eligible. `rebuild` a caller sorrendjét használja, így future
vagy rendezetlen input nem az első valódi completion timestampjét rögzítheti.

**Státusz:** RESOLVED (`11fb1ac2`).

### S5 — MAJOR — Caller-history CPU/allocation denial-of-service út

`achievement_evaluator.dart:131-139,271-287`: növekvő prefixmásolás és ismételt
full-ledger scan; az index `achievement_index.dart:14` csak event kind szerint
épül. Darabszám-hard-cap nélkül egy nagy importált/local history kvadratikus
munkát okozhat.

**Státusz:** RESOLVED (`11fb1ac2`).

### S6 — MAJOR — A backfill nyers input capje dátumszűréssel megkerülhető

`achievement_evaluator.dart:193-211,487-497`: a 10 000-es limit csak a
szűrés után továbbadott `retained` listára fut. Egy caller ezért 10 001 vagy
több ablakon kívüli rekordot adhat át; a függvény az összeset feldolgozza,
majd sikerrel tér vissza. Az izolált reviewer-cella 10 001 egyedi lejárt
eventre `ArgumentError` helyett `AchievementEvaluationResult`-ot kapott.

**Státusz:** RESOLVED (`ae703918`). A 9 999/10 000/10 001 permanens cella a
nyers historyt méri, és az őr a dátumszűrés előtt fut. Az őr eltávolításakor a
10 001 lejárt esemény ismét sikeresen átjutott, tehát a regresszió valóban
megkülönbözteti a hibás implementációt.

### N1 — NOTE — Privacy/network

Nincs új hálózati kliens, logolás, secret, raw-audio vagy kamera-kezelés.

### N2 — NOTE — Scope

A diff kizárólag a brief engedélyezett útvonalait érinti; a worktree tiszta.

## Kötelező re-review

Az exact-source concurrency, malformed receipt, duplicate ID, future-window,
lineáris receipt-index és raw-backfill-cap regressziók az exact `ae703918`
detached klónban 11/11 zöldek. A scope-audit 2 engedélyezett útvonalat mért,
a teljes round-gate 6/6 zöld, új security lelet nincs. Verdikt: **PASS**.
