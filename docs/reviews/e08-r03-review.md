# E08-R03 — Review

Brief: docs/rounds/e08-r03-reward-ledger-and-idempotency.md
Diff: `git diff main...codex/e08-r03-reward-ledger-and-idempotency` (base `2fedc773`, head `9386b990`)
Reviewer: Claude (Sonnet 5) · Dátum: 2026-08-19
Verdikt: **APPROVED**

## Összegzés

BLOCKER: 0 · MAJOR: 0 · MINOR: 0 · NOTE: 1

Ez a kör **második nekifutása** (az első 21:25 UTC-kor H6-tal állt meg egy
infrastruktúra-hibán — hiányzó generált Flutter l10n egy `git worktree
add`-dal nyitott munkapéldányban —, amit egy self-heal PR #338 már javított
a burkoló scripteken). Ez a futás egy friss `git clone`-ból indult, a
korábbi két félkész, commitolatlan munkapéldányt (`ss-codex-e08-r03`,
`ss-codex-e08-r03-impl`) — mindkettő jelöletlen, uncommitolt állapotban —
nem használtam fel, a brief §0.2 „félkész, jelöletlen munka → indíts
tisztán" szabálya szerint.

## Acceptance criteria

| # | Kritérium | Teljesült | Bizonyíték |
|---|---|---|---|
| A1 | Azonos `sourceEventId` kétszeri hozzáfűzése egy bejegyzést ad | ✅ | `reward_ledger_repository_test.dart:14-28`; gate `test`: `+0: A1 ...` zöld |
| A2 | Párhuzamos (`Future.wait`) kettős hozzáfűzés is EGY bejegyzést ad | ✅ | `reward_ledger_repository_test.dart:30-48`; **saját mutációs próbával megerősítve** (lásd lent) |
| A3 | Nincs `update`/`delete` a repository felületén | ✅ | `reward_ledger_repository_test.dart:50-61` — regex-forrásvizsgálat mindkét fájlon; kézzel is ellenőrizve: `reward_ledger_repository.dart` és `local_reward_ledger_repository.dart` interfésze csak `appendIfAbsent`/`hasProcessedEvent`/`readPage` |
| A4 | Ismeretlen schema-verziójú bejegyzés megmarad újraírás után | ✅ | `reward_ledger_repository_test.dart:63-92` — bájt-egyenlőség (`jsonEncode` összevetés) egy `schemaVersion+1` rekordra; a mechanizmus a kódban: `local_reward_ledger_repository.dart:96-110` (`_rawEntries` mindig frissül, a tipizált `_entries` csak sikeres parse-nál) |
| A5 | Policy-verzió, XP-komponensek, `RewardReason` kódok round-trip | ✅ | `reward_ledger_repository_test.dart:94-117` — friss repository-példány UGYANARRÓL a store-ról olvas vissza |
| A6 | Részleges írás/crash után a főkönyv konzisztens | ✅ | `reward_ledger_repository_test.dart:119-139`, a megosztott `InMemoryKeyValueStore.failingKeys` (pre-existing teszt-infra, ~8 másik repository-teszt is ezt használja) valódi `StorageException`-t vált ki a `JsonDocumentStore.write()` catch-ágában (`json_document_store.dart:103-128`) — a teszt egy ÚJ repository-példánnyal olvas vissza, valódi újraindulást szimulálva |
| A7 | Lapozás stabil, teljes, a küszöb-hármas minden cellája | ✅ | `reward_ledger_repository_test.dart:143-188` — `limit=0` → `ArgumentError` (alatt), `limit=1` háromszor egymás után teljes és sorrendtartó (rajta), `limit=4` egy 3-elemű főkönyvre egy lapon, kurzor nélkül (fölött) |
| A8 | `RewardReason` kódok stabil enum-értékek | ✅ | `reward_ledger_repository_test.dart:191-207` + `reward_reason.dart` — 12 névvel felsorolt enum, szabad szöveg sehol |

Extra teszt (nem acceptance-cella, de a policy-Kör 6 felé fontos): `RewardLedgerEntry`
konstruktor-validáció (üres ID, negatív komponens, `totalXp ≠ base+bonus`) —
`reward_ledger_repository_test.dart:210-223`.

## Scope-audit

`tools/scope-audit.py --repo <klón> --brief docs/rounds/e08-r03-reward-ledger-and-idempotency.md --base 2fedc773f25d3f331881812ecf787a3e68ac27e5`
→ **`Legacy scope audit OK (2fedc773f25d..9386b9900621, 7 changed path(s), 0 generated/ignored)`**.
Mind a 7 megváltozott fájl a brief §4 engedélyezett listáján van. A
`public.dart` diffje **kizárólag export-sor** (3 sor, csak `+`), a brief §4
előírása szerint — és helyesen NEM exportálja a konkrét
`LocalRewardLedgerRepository` implementációt, csak az interfészt +
domain-típusokat.

Engedélyezett fájlokon kívüli változás: **nincs**.

## Megállapítások

### N1 — NOTE — `gate_shape=VIOLATION` a jelzésfájlban: mért hamis pozitív

- **Fájl:** `.codex-round-status` (a munkapéldányban, gitignore-olt)
- **Megfigyelés:** a `codex-round.sh` `verify_claim()` őre (289-336. sor) a
  naplóban `round-gate\.sh[^\n]*(\| *(tail|head)|&&)` mintát keresve
  `VIOLATION`-t írt, holott a brief §7 tiltását az implementer betartotta.
- **Gyökérok (megmérve, nem feltételezve):** a `codex exec` induló hívása a
  TELJES preambulum+prompt szöveget egyetlen log-sorba írja (a log 22402.
  sora), és ez a szöveg szó szerint tartalmazza mind a
  `tools/round-gate.sh ...` idézetet, mind — egy MÁSIK, a preambulumból
  származó példában — a `git add -A && git commit` mintát. A regex sortörés
  nélkül keres, ezért a két, egymással nem összefüggő idézet ugyanazon a
  (nagyon hosszú) log-soron egyetlen találatnak látszik. Az összes TÉNYLEGES
  végrehajtás (`grep -n "round-gate\.sh" /tmp/codex-e08-r03-run2.log` → hét
  `/bin/bash -lc 'tools/round-gate.sh test/features/gamification/data/
  reward_ledger_repository_test.dart'` sor) csővezeték/lánc NÉLKÜLI, önálló
  hívás.
- **Hatás:** nem blokkoló — a review a gate-et saját kézzel, izolált
  `/tmp`-klónban újrafuttatta (lásd lent), ami a hiteles bizonyíték, nem a
  jelzésfájl. De ez a guard éppen az anti-hallucináció védelem egyik rétege
  — egy valódi csővezeték-csalást is elfedhetne egy ilyen hamis pozitív
  mellett, ha a reviewer vakon a `gate_shape` mezőre hagyatkozna.
  **Nem javaslom soron kívüli tools/-javításnak** (a `tools/` ezen a körön
  kívül esik, és a hiba ritka/ártalmatlan előfordulású), de érdemes
  follow-up self-heal candidate-nek jelölni, ha újra előfordul: a regexet a
  log SOR-onkénti bontás helyett a shell-hívás rekordjára (`/bin/bash -lc
  '...'` idézett string) kellene szűkíteni.
- **Státusz:** OPEN (nem blokkoló, dokumentálva)

## Saját, eldobható próbateszt (review-mérés, nem commitolva)

A `local_reward_ledger_repository.dart` `appendIfAbsent`-jét a `/tmp/review-e08-r03`
izolált klónban ideiglenesen egy `hasProcessedEvent` + `await Future.delayed(Duration.zero)`
+ feltétlen append párra cseréltem (a §5.2 által tiltott, szét nem
szerializált minta), majd csak az A2 tesztet futtattam:

```
00:00 -1: Reward ledger — append-only idempotency A2: concurrent appends of one source event create one ledger entry [E]
  Expected: an object with length of <1>
    Actual: WhereIterable<bool>:[true, true]
```

**PIROS**, pontosan az implementer §10-ben dokumentált mintával egyezően.
Visszaállítás után (`git checkout --`) **ZÖLD**. Ez önállóan (nem az
implementer bemondására hagyatkozva) igazolja, hogy az A2 teszt valóban a
szerializációt méri, nem egy véletlenül átmenő esetet.

## Architektúra + termékhatárok

- `test/core/architecture_dependency_test.dart` a gate `architecture`
  lépésében ZÖLD (12 allowlisted deviation, változatlan szám) — a
  „gamification domain stays framework-free" csoport rekurzív listázása
  miatt az új `domain/rewards/` alkönyvtár automatikusan ellenőrzött, a
  teszt módosítása nélkül (brief §0.0.5 állítása megerősítve).
- Nincs `presentation/`/UI-kód ebben a körben — a §5.4 „UI nem írhat a
  főkönyvbe" tiltás emiatt jelenleg nem megkerülhető, mert semmi nem éri el
  a repository-t a domain/data rétegen kívülről.
- Durability-őszinteség (brief §0.0.4, [[L28]]): a `RewardLedgerRepository.
  appendIfAbsent` doc-commentje explicit kimondja: „Its local disk write
  follows the existing best-effort storage contract” — NEM ígér erősebb
  perzisztenciát, mint amit a megosztott `JsonDocumentStore.write()`
  ténylegesen teljesít (StorageException → logol, nem dob). Az L28
  hibaosztály itt nem ismétlődött meg.
- `JsonDocumentStore` (nem `JsonCollectionStore`) minta, nincs `capRecords`/
  `maxItems` — az append-only invariáns nem sérülhet néma eviction miatt
  (ADR 0301 4. pont, brief §0.0.3 indoklása megerősítve a tényleges kódban).

## Gate-bizonyíték ellenőrzése

Mindkét futás **saját kézzel, izolált `/tmp/review-e08-r03` klónban** (a
brief branch-éből, nem a közös working tree-ből):

| Gate | Állított eredmény (implementer) | Ellenőrizve (reviewer, saját futás) |
|---|---|---|
| format | zöld | ✅ `Formatted 1684 files (0 changed)` |
| analyze | zöld | ✅ `No issues found!` |
| test (célzott) | `+9: All tests passed!` | ✅ `+9: All tests passed!` (A1–A8 + validáció, névvel egyezően) |
| architecture | zöld, 12 allowlisted deviation | ✅ `Architecture dependencies OK (12 allowlisted deviation(s))` |
| secrets | zöld | ✅ `Secret scan OK (2979 file(s) scanned, 0 finding(s))` |
| l10n | (a gate 6. lépése, az implementer nem idézte) | ✅ `L10n parity OK (en → hu, 1405 message(s))` |
| CI (`full-gate.yml`, teljes suite + property + coverage) | — | dispatch-elve a review lezárásakor, run: lásd PR |
| Router CI (`router-ci.yml`, a `docs/rounds/**` path-trigger miatt kötelező) | — | auto-triggerelt a push-ra, run: lásd PR |

## Merge-döntés

0 BLOCKER, 0 MAJOR, 0 MINOR nyitott — az ADR 0052 zöld kapuja a CI (full-gate
+ router-ci) zöld visszaigazolására vár. Ha mindkettő zöld a merge SHA-n:
**squash-merge**, külön jóváhagyás nélkül.
