# E08-R09 — Review

Brief: `docs/rounds/e08-r09-legacy-progress-adapter-and-backfill.md`
Diff: `git diff dfbdb277..ba09c683` (pre-flight → implementer HEAD)
Reviewer: Codex (GPT-5.6 Sol) · Dátum: 2026-08-20
Verdikt: **CHANGES REQUIRED**

## Összegzés

BLOCKER: 1 · MAJOR: 2 · MINOR: 0 · NOTE: 1

## Acceptance criteria

| # | Kritérium | Teljesült | Bizonyíték |
|---|---|---|---|
| A1 | Stabil, exact duplikátumot megőrző, opaque event ID | ❌ | Determinizmus/ordinal zöld (`legacy_practice_migration_test.dart:7-29`), de az ID plaintextben hordozza az összes gyakorlási mezőt — F2 |
| A2 | Két migráció után is változatlan ledger | ❌ | Az implementáció minden első futáskor nulla-XP receiptet ír (`gamification_migrator.dart:68-73`), és konstruktorfüggősége a ledger — a revideált §0.2/§5.5 szerint tilos |
| A3 | Nulla retroaktív XP, report megmarad | ❌ | A report aggregátumai helyesek, de a migrátor reward-ledger receiptet ír; a revideált szerződés szerint nulla XP = nulla ledger side effect |
| A4 | `live/analyze/learn` mapping | ✅ | `legacy_practice_adapter.dart:66-70`; A4 forrásmátrix zöld |
| A5 | Restart a checkpointtól, adatvesztés nélkül | ❌ | Fake exception happy path zöld, de valós best-effort ledger write mellett a checkpoint túlhalad a nem perzisztált receipten — F1 |
| A6 | Progress history érintetlen | ✅ | Scope-audit 0 sértés; `lib/features/progress/**` diff nincs; A6 input-lista változatlan |
| A7 | Új esemény továbbra is kaphat XP-t | ✅ | A7 pozitív receiptet ír ugyanabba a fake ledgerbe a migration után; a kör nem módosított reward policyt |
| A8 | Egyetlen valid legacy rekord sem vész el | ❌ | Snapshoton belüli darabszám/duplikátum zöld, de F1 restart után elveszít egy canonical receiptet a checkpoint mögött |
| A9 | 400 rekordos cap | ✅ | A9: report/events/ledger 400/400/400 az első implementációban |
| A10 | Ismeretlen source → `live` | ✅ | `PracticeEntry.fromJson` + adapter A10 zöld |
| A11 | Negatív/extrém rekord containment | ❌ | Negatív seconds zöld, de `day=-1` eseményt gyárt, `day=1 << 40` pedig `RangeError`-t dob — F3 |

## Scope-audit

```text
python3 tools/scope-audit.py --repo /tmp/review-e08-r09.Gkq070 \
  --brief docs/rounds/e08-r09-legacy-progress-adapter-and-backfill.md \
  --base dfbdb277cc2c3a9858b32996e61e61c605002f1c
→ Legacy scope audit OK (dfbdb277cc2c..ba09c68311a0, 6 changed path(s),
  0 generated/ignored)
```

Engedélyezett implementer-fájlokon kívüli változás: **nincs**.

## Megállapítások

### F1 — BLOCKER — A checkpoint tartósan túlhaladhat egy elutasított ledger-íráson

- **Fájl:** `lib/features/gamification/data/migration/gamification_migrator.dart:68-73`
- **Probléma:** a migrátor `appendIfAbsent()` után külön dokumentumban írja a
  checkpointot. A production `LocalRewardLedgerRepository` dokumentált
  szerződése szerint a `true` csak az in-memory session állapotba kerülést
  jelenti; a `JsonDocumentStore.write()` best-effort hibát logol és elnyel.
  Emiatt a ledger write visszautasítható úgy, hogy a checkpoint-write sikerül.
- **Mért bizonyíték:** eldobható review-tesztben
  `InMemoryKeyValueStore.failingKeys` csak a
  `LocalRewardLedgerRepository.storageKey` írását utasította el. A migráció
  visszatért és `processedCount=1` state-et írt; új `LocalRewardLedgerRepository`
  példány ugyanazon store felett `hasProcessedEvent(eventId) == false` értéket
  adott. A próba várt `true` értéke ténylegesen `false` lett.
- **Hatás:** restart után a canonical backfill rekord hiányzik, de a checkpoint
  késznek jelöli; ez néma, tartós adatvesztés és megszegi A5/A8-at.
- **Kötelező javítás:** a revideált brief §0.2 és ADR 0350 D4 szerint a migrátor
  egyáltalán ne függjön `RewardLedgerRepository`-tól és ne írjon receiptet.
  Csak a tiszta reportot és a `GamificationRepository` checkpointot tartsa meg.
- **Ellenőrzés:** állandó A2 forrásőr (`gamification_migrator.dart` nem
  tartalmaz `RewardLedgerRepository`/`appendIfAbsent`/`RewardLedgerEntry`) és
  olyan teszt, amely egy előzetesen feltöltött ledger bejegyzésszámát az első
  és második migráció előtt/után változatlannak méri.
- **Státusz:** OPEN

### F2 — MAJOR — Az esemény-ID plaintextben szivárogtatja a gyakorlási rekordot

- **Fájl:** `lib/features/gamification/data/migration/legacy_practice_adapter.dart:51-64`
- **Probléma:** a `_fingerprint` nem digest, hanem a `day:source:seconds:
  strokes:chords:directionAccuracy` nyers string; az `eventId` ezt szó szerint
  perzisztálja a ledgerben és továbbadja minden jövőbeli ID-fogyasztónak.
- **Mért bizonyíték:** a review-probe egy `day=20400, learn, 45s, 30 stroke,
  4 chord, 0.8` rekordra ezt kapta:
  `legacy-practice/v1/20400:learn:45:30:4:0.8/0`.
- **Hatás:** egy azonosítónak szánt mezőből visszaolvasható a felhasználó
  gyakorlási napja, módja, időtartama és teljesítményadata; ez indokolatlan
  privacy-kitettség és hosszú, változó alakú kulcs.
- **Kötelező javítás:** kanonikus tartalom UTF-8 bájtjainak SHA-256 digestje;
  az ID csak verzió-prefix + 64 lowercase hex + occurrence ordinal legyen.
- **Ellenőrzés:** A1 assertálja a digest regexet és azt, hogy a nyers mezősor
  nem substringje az ID-nak; determinisztikus és exact-duplikátum cellák
  változatlanul zöldek.
- **Státusz:** OPEN

### F3 — MAJOR — Decoder-valid extrém epoch-day kezeletlen `RangeError`-ral megállítja a teljes migrációt

- **Fájl:** `lib/features/gamification/data/migration/legacy_practice_adapter.dart:31-49`
- **Probléma:** `accepts()` egyáltalán nem validálja a `day` mezőt. A legacy
  decoder a közös `requireInt` max (`1 << 40`) értékét elfogadja, de ennek
  milliszekundumos DateTime-konverziója kívül esik a Dart támogatott
  tartományán. A negatív, közvetlenül konstruált day szintén átmegy.
- **Mért bizonyíték:** `PracticeEntry.fromJson({'day': 1 << 40, 'src':'live',
  'sec':1})` sikerült, majd `adapt()`
  `RangeError (millisecondsSinceEpoch)` kivételt dobott. `day=-1` esetén az
  adapter eseményt adott az elvárt üres lista helyett.
- **Hatás:** egyetlen strukturálisan decoder-valid, de időtartományon kívüli
  legacy rekord leállítja a teljes backfillt; ez tartalom-alapú lokális DoS és
  megakadályozza a többi ép rekord migrációját.
- **Kötelező javítás:** explicit `day >= 0` és DateTime-max epoch-day guard a
  konverzió előtt; a hibás rekord ugyanúgy maradjon ki, mint a negatív duration.
- **Ellenőrzés:** A11 permanens cellák `day=-1` és `day=1 << 40` bemenettel:
  nincs throw, nincs esemény.
- **Státusz:** OPEN

### N1 — NOTE — A wrapper `gate_shape=VIOLATION` lelete történeti HANDOFF-szövegre illeszkedő false positive

- **Bizonyíték:** a wrapper regexének egyetlen két találata a logban a HANDOFF
  L357 történeti magyarázata volt (`round-gate.sh ... && nélkül`, illetve a
  regexet leíró `pipe/tail/head/&&` sor). A tényleges végrehajtások mind
  önálló `tools/round-gate.sh test/...` parancsok voltak. Az izolált reviewer
  gate ugyanezzel a tiszta alakkal zöld.
- **Státusz:** OPEN NOTE; nem a kör production diffjének hibája. Closingkor
  LESSONS-be emelendő, külön governance follow-upként.

## Valódi-sértés és eldobható próbák

- **Kötelező ID-mutáció:** `_fingerprint` ideiglenesen globális számláló lett.
  A shipped suite A1/A2/A5 cellái pirosak lettek, majd a változtatás
  visszaállítva; reviewer klón tiszta.
- **Adatvesztés-próba:** ledger-key write refusal + sikeres state write után
  restartolt repository elvesztette a receiptet (F1).
- **Privacy/range próba:** plaintext ID, `day=1 << 40` RangeError és `day=-1`
  elfogadás egyetlen eldobható tesztben reprodukálva (F2/F3).

## Gate-bizonyíték ellenőrzése

Izolált klón: `/tmp/review-e08-r09.Gkq070`, HEAD `ba09c683`.

| Gate | Eredmény | Ellenőrizve |
|---|---|---|
| format | 1715 fájl, 0 változott | ✅ |
| analyze | 0 lelet | ✅ |
| célzott teszt | 12/12 zöld | ✅ |
| architecture | OK, 12 allowlistelt eltérés | ✅ |
| secrets | 3044 fájl, 0 lelet | ✅ |
| l10n | en/hu 1405 üzenet, parity OK | ✅ |
| CI teljes suite + property | dispatch elindítva | ⏳ javító commit után újra kötelező |

## Merge-döntés

F1 BLOCKER és F2/F3 MAJOR nyitva: **merge tilos**. A brief/ADR saját
artefaktum-revíziója commitolandó, majd ugyanaz a Terra motor kap egy javító
kört. Utána friss izolált klónban teljes gate + minden probe újramérése,
security re-review és exact-SHA CI szükséges.
