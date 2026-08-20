# E08-R09 — Security review

Brief: `docs/rounds/e08-r09-legacy-progress-adapter-and-backfill.md`
Diff: `git diff d2b26710..415a795a`
Reviewer: független GPT-5.6 Sol security-reviewer · Dátum: 2026-08-20
Verdikt: **CHANGES REQUIRED**

## Összegzés

CRITICAL: 0 · BLOCKER: 0 · MAJOR: 1 · MINOR: 0 · NOTE: 0

## Megállapítások

### S1 — BLOCKER — Nem tartós ledger receipt mögé tartós checkpoint kerülhet

- **Fájl:** `lib/features/gamification/data/migration/gamification_migrator.dart:66-73`
- **Probléma:** a migrátor minden `appendIfAbsent` után checkpointot ír. A
  local ledger előbb memóriába teszi a receiptet, majd a best-effort
  `JsonDocumentStore.write()`-ot várja; az utóbbi `StorageException`-t elnyel.
  A checkpoint külön dokumentuma ettől még sikeresen perzisztálódhat.
- **Mért bizonyíték:** valódi `LocalRewardLedgerRepository` és
  `LocalGamificationRepository`, csak a ledger-key írását elutasító
  `InMemoryKeyValueStore`: `migrate()` nem dobott, restart után ledger 0 elem,
  `processedCount=1`. Egy második próba cap-shiftnél is reprodukálta a
  pozicionális checkpoint veszélyét.
- **Hatás:** a restart tartósan átugorhat hiányzó canonical rekordot.
- **Kötelező javítás:** a revideált ADR 0350 D4 szerint a nulla-XP backfill ne
  írjon ledgerbe és ne függjön `RewardLedgerRepository`-tól. A mapping/report
  side-effectmentes; checkpoint-vesztés vagy snapshot-shift így legfeljebb
  ártalmatlan újraszámítás.
- **Státusz:** CLOSED (`415a795a`) — a migrátor contractjából és forrásából
  eltűnt a ledger dependency és minden ledger-side effect.

### S2 — MAJOR — Decoder-valid extrém epoch-day migrációs DoS

- **Fájl:** `lib/features/gamification/data/migration/legacy_practice_adapter.dart:31-49`
- **Probléma:** `accepts()` nem validál `day`-t, miközben a legacy decoder
  `1 << 40` értéket elfogad; a DateTime-konverzió erre `RangeError`-t dob.
- **Mért bizonyíték:** `PracticeEntry.fromJson({'day': 1 << 40,
  'src':'live'})` sikeres; az adapter ezután `RangeError`-ral leállt.
- **Hatás:** egyetlen crafted/corrupt, de decoder-valid rekord blokkolja a
  teljes lokális backfillt.
- **Kötelező javítás:** reprezentálható, nem negatív epoch-day guard; vegyes
  invalid+valid lista esetén az invalid rekord izolálódjon, a valid migrálódjon.
- **Státusz:** CLOSED (`415a795a`) — a DateTime-határ guardolt; az extrém
  rekord izolálódik, a szomszédos valid rekordok megmaradnak.

### S3 — NOTE — A publikus adapter/migrátor nem őrzi a 400-as legacy capet

- **Fájl:** `lib/features/gamification/data/migration/legacy_practice_adapter.dart:15`,
  `lib/features/gamification/data/migration/gamification_migrator.dart:47`
- **Megfigyelés:** a normál Progress repository 400-ra capel, de a publikus
  caller-supplied API tetszőleges listát elfogad. Az első implementáció ledger
  full-document rewrite-ja miatt ez különösen drága volt.
- **Javaslat:** a revideált A9 szerint pontosan 400 elfogadott, 401 explicit
  `ArgumentError`.
- **Státusz:** CLOSED (`415a795a`) — 400 elfogadott, 401 explicit
  `ArgumentError` az adapter és migrátor publikus belépési pontján is.

### S4 — MAJOR — A checkpoint a szűrt event-listát indexeli, nem az eredeti snapshotot

- **Fájl:** `lib/features/gamification/data/migration/gamification_migrator.dart:53-75`,
  különösen `:69-73`
- **Probléma:** az adapter az invalid rekordokat eldobja, majd `_checkpointFor`
  az `events.length` értéket és a `for` ciklus az `events` indexeit használja.
  A perzisztált `processedCount` szerződése ezzel szemben az eredeti,
  caller-supplied snapshot első még feldolgozatlan indexe. Invalid rekord a
  prefixben vagy középen eltolja a két indexteret.
- **Mért bizonyíték:** eldobható teszt `processedCount=2` és eredeti snapshot
  `[valid(day=20000), invalid(day=-1), valid(day=20002), valid(day=20003)]`
  bemenettel az eredeti index-szemantika szerinti `[3, 4]` checkpoint-írások
  helyett csak `[3]`-at mért; a végső `processedCount=3`, miközben az eredeti
  snapshot hossza 4. A próba 4 másik security cellája zöld volt, ez az egy
  piros.
- **Hatás:** a checkpoint nem jelenti az ADR 0350 D5 és brief §5.3 szerinti
  első feldolgozatlan eredeti rekordot. A jelenlegi mapping ugyan minden
  reportot tisztán újraszámol, de a perzisztált restart-contract hamis, és egy
  későbbi side-effectes fogyasztó rekordot ugorhat át vagy egy helyes,
  eredeti-indexű state-et `checkpoint exceeds` hibával elutasíthat.
- **Kötelező javítás:** a checkpoint ciklusa az eredeti `entries` indexein
  haladjon; az invalid rekordot feldolgozott/elutasított rekordként lépje át,
  hogy az utána álló valid rekord eredeti indexe megmaradjon. Állandó
  regressziós cella: invalid a checkpoint alatt, pontosan rajta és fölötte,
  valamint teljes futás után `processedCount == entries.length`.
- **Státusz:** OPEN

## Pozitív evidenciák

- Scope-audit: `d2b26710..415a795a` OK, 3 path, 0 sértés.
- Hivatalos kör-gate: format/analyze/13 célzott teszt/architecture/secrets/l10n
  mind zöld, exit 0.
- Eldobható security próba: ledger dependency/side effect, opaque és stabil
  SHA-256 ID, exact duplikátum, DateTime szélsőérték, illetve 400/401 cap zöld;
  az eredeti-index checkpoint cella piros (`Expected [3,4], Actual [3]`).
- A re-review izolált klónja a próba törlése után tiszta maradt.

## Merge-döntés

S1–S3 lezárva, de S4 MAJOR nyitva: **merge tilos**. Terra javító kör, majd
friss security re-review és exact-SHA CI kötelező.
