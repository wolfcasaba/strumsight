# E08-R14 — Security review

Brief: `docs/rounds/e08-r14-achievement-evaluator-and-projection.md`  
Reviewed head: `997a52a0176d7ec411accd7691569eeed880170c`  
Reviewer: független Codex / `gpt-5.6-sol` security reviewer · 2026-08-21  
Verdikt: **FAIL**

## Összegzés

CRITICAL: 0 · BLOCKER: 2 · MAJOR: 3 · MINOR: 0 · NOTE: 2

Legalább egy BLOCKER van, ezért merge tilos.

## Leletek

### S1 — BLOCKER — Ledger namespace collision forged completiont enged

`achievement_evaluator.dart:223,274` prefix alapján completionnek fogad sort,
de nem ellenőrzi a `ledgerId`, zero-XP és `achievementUnlocked` invariánst.
A canonical activity event ID csak non-blank, a normál receipt ezt használja
source ID-ként, ezért prefix-ütközés valós inputból is létrejöhet.

### S2 — BLOCKER — Párhuzamos külön trigger duplikált unlock receiptet ír

`achievement_evaluator.dart:223,237,304`: a pre-check és append külön, a dedup
kulcs triggerenként eltér. A local repository csak exact source ID-t zár ki,
így két bejegyzés sikeresen bekerülhet.

### S3 — MAJOR — Duplicate history event progresszt inflál

`achievement_evaluator.dart:336,396`: count és sequence lista-előfordulást
számol, stabil event ID dedup nélkül.

### S4 — MAJOR — A backfill future eventet és rendezetlen timestampet elfogad

`achievement_evaluator.dart:170-180`: csak a cutoff előtti eventet szűri; az
anchor utáni event eligible. `rebuild` a caller sorrendjét használja, így future
vagy rendezetlen input nem az első valódi completion timestampjét rögzítheti.

### S5 — MAJOR — Caller-history CPU/allocation denial-of-service út

`achievement_evaluator.dart:131-139,271-287`: növekvő prefixmásolás és ismételt
full-ledger scan; az index `achievement_index.dart:14` csak event kind szerint
épül. Darabszám-hard-cap nélkül egy nagy importált/local history kvadratikus
munkát okozhat.

### N1 — NOTE — Privacy/network

Nincs új hálózati kliens, logolás, secret, raw-audio vagy kamera-kezelés.

### N2 — NOTE — Scope

A diff kizárólag a brief engedélyezett útvonalait érinti; a worktree tiszta.

## Kötelező re-review

S1–S5 javítása után exact-source concurrency, malformed receipt, duplicate ID,
future/backfill cap és lineáris munka regressziós celláit újra kell futtatni.
CRITICAL/BLOCKER nyitva maradása merge-tilalom.
