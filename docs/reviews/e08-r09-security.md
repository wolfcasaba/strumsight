# E08-R09 — Security review

Brief: `docs/rounds/e08-r09-legacy-progress-adapter-and-backfill.md`
Diff: `git diff dfbdb277..ba09c683`
Reviewer: független GPT-5.6 Sol security-reviewer · Dátum: 2026-08-20
Verdikt: **CHANGES REQUIRED**

## Összegzés

CRITICAL: 0 · BLOCKER: 1 · MAJOR: 1 · MINOR: 0 · NOTE: 1

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
- **Státusz:** OPEN

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
- **Státusz:** OPEN

### S3 — NOTE — A publikus adapter/migrátor nem őrzi a 400-as legacy capet

- **Fájl:** `lib/features/gamification/data/migration/legacy_practice_adapter.dart:15`,
  `lib/features/gamification/data/migration/gamification_migrator.dart:47`
- **Megfigyelés:** a normál Progress repository 400-ra capel, de a publikus
  caller-supplied API tetszőleges listát elfogad. Az első implementáció ledger
  full-document rewrite-ja miatt ez különösen drága volt.
- **Javaslat:** a revideált A9 szerint pontosan 400 elfogadott, 401 explicit
  `ArgumentError`.
- **Státusz:** OPEN NOTE (a javító körben olcsón zárható)

## Pozitív evidenciák

- Scope-audit: `dfbdb277..ba09c683` OK, 6 path, 0 sértés.
- Hivatalos kör-gate: format/analyze/12 célzott teszt/architecture/secrets/l10n
  mind zöld, exit 0.
- A forrásmapping, Progress public boundary és exact-duplikátum ordinal
  alapmechanikája helyes.

## Merge-döntés

S1 BLOCKER és S2 MAJOR nyitva: **merge tilos**. Terra javító kör, majd friss
security re-review és exact-SHA CI kötelező.
