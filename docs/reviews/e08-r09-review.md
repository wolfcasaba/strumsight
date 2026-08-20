# E08-R09 — Review

Brief: `docs/rounds/e08-r09-legacy-progress-adapter-and-backfill.md`
Round HEAD: `2268aaad` (upstream sync after fix/re-review commits)
Reviewer: Codex (GPT-5.6 Sol) · Dátum: 2026-08-20
Verdikt: **APPROVED**

## Összegzés

BLOCKER: 0 nyitott · MAJOR: 0 nyitott · MINOR: 0 · NOTE: 1 nyitott

Az első review F1 BLOCKER + F2/F3 MAJOR leleteit a `415a795a` javító commit
lezárta. A későbbi security review S4 MAJOR checkpoint-indexhibáját a
`9821d00b` javította, a `766a2bcd` és `3a702692` review-commitok függetlenül
lezártnak minősítették. A jelen passz a friss `origin/main` beépítése után,
izolált klónban újramérte a scope-ot, a kör-gate-et és az S4 mutációs őrt.

## Acceptance criteria

| # | Kritérium | Teljesült | Bizonyíték |
|---|---|---|---|
| A1 | Stabil, exact duplikátumot megőrző, opaque event ID | ✅ | SHA-256 + fingerprinten belüli ordinal; A1 zöld |
| A2 | A migráció nem módosít reward ledgert | ✅ | Nincs ledger dependency/side effect; A2 zöld |
| A3 | Nulla retroaktív XP, a statisztikai report megmarad | ✅ | A3 totals/zero-receipt cella zöld |
| A4 | `live/analyze/learn` mapping | ✅ | Forrásmátrix zöld |
| A5 | Restart az eredeti snapshot checkpointjától | ✅ | A5 + S4a–S4d zöld |
| A6 | Progress history érintetlen | ✅ | Implementer commit-tartományok scope-auditja OK; `lib/features/progress/**` diff nincs |
| A7 | Új esemény továbbra is kaphat XP-t | ✅ | A7 pozitív receipt zöld |
| A8 | Minden valid legacy rekord megmarad | ✅ | Exact duplikátum és darabszám cellák zöldek |
| A9 | 400 rekord elfogadott, 401 elutasított | ✅ | A9 zöld |
| A10 | Ismeretlen source → `live` | ✅ | Decoder + adapter cella zöld |
| A11 | Negatív/extrém rekord izolálódik | ✅ | `day=-1`, `day=1 << 40` és negatív mezők zöldek |

## Scope-audit

Az upstream-szinkron commit (`2268aaad`) két, `origin/main`-ről érkező közös
dokumentumot (`HANDOFF.md`, `docs/LESSONS.md`) hozott be, az ADR 0350 pedig
orchestrátor-owned pre-flight artefaktum. Ezért a teljes merge-HEAD-et egyetlen
implementer-base ellen auditálni hamis pozitív lenne. A három tényleges
implementer-tartomány külön, a hozzájuk tartozó induló SHA-val mérve:

```text
dfbdb277..ba09c683 → Legacy scope audit OK (6 path, 0 ignored)
d2b26710..415a795a → Legacy scope audit OK (3 path, 0 ignored)
415a795a..9821d00b → Legacy scope audit OK (2 path, 0 ignored)
```

Engedélyezett implementer-fájlokon kívüli változás: **nincs**. A review- és
pre-flight dokumentumok az orchestrátor/reviewer saját artefaktumai.

## Leletek lezárása

### F1 — BLOCKER — checkpoint egy nem tartós ledger-írás mögött

**CLOSED (`415a795a`).** A migrátor nem függ `RewardLedgerRepository`-tól,
nem ír receiptet, csak tiszta reportot és migrációs checkpointot állít elő.
A2 állandó forrásőr és ledger-darabszám cella védi.

### F2 — MAJOR — plaintext gyakorlási adatok az esemény-ID-ben

**CLOSED (`415a795a`).** Az ID a kanonikus wire-tartalom SHA-256 digestjét és
az exact duplikátum ordinalját tartalmazza; A1 a hex alakot és a plaintext
hiányát is ellenőrzi.

### F3 — MAJOR — extrém epoch-day `RangeError`

**CLOSED (`415a795a`).** Az adapter a negatív és DateTime-tartományon kívüli
napokat konverzió előtt elutasítja; A11 vegyes listán bizonyítja az izolációt.

### S4 — MAJOR — checkpoint a szűrt eseménylistát indexelte

**CLOSED (`9821d00b`).** A checkpoint és a write-loop az eredeti `entries`
snapshot indexterében halad. Az S4a–S4d állandó cellák az invalid rekord
checkpoint alatti/rajta/fölötti helyét és a teljes futást lefedik.

### N1 — NOTE — wrapper `gate_shape=VIOLATION` történeti false positive

Nyitott, nem blokkoló governance follow-up. A jelzés regexe korábbi HANDOFF-
magyarázat szövegére illeszkedett; a tényleges gate-hívások önálló, helyes
artefaktumhívások voltak.

## Valódi-sértés próba

Friss izolált klónban (`/tmp/review-e08-r09-sol.mvG5ta`, HEAD `2268aaad`) a
checkpoint és a ciklushatár ideiglenesen `entries.length` helyett a szűrt
`events.length` értéket kapta. A célzott teszt a várt módon piros lett:

- S4a/S4b/S4c: `Expected [3, 4], Actual [3]`;
- S4d: `Expected [1, 2, 3, 4, 5], Actual [1, 2, 3]`.

A mutáció visszaállítása után ugyanaz a 17 teszt zöld, a reviewer klón tiszta.

## Gate-bizonyíték

Friss izolált klón, HEAD `2268aaad`:

| Gate | Eredmény |
|---|---|
| format | 1715 fájl, 0 változott |
| analyze | 0 lelet |
| célzott teszt | 17/17 zöld |
| architecture | OK, 12 allowlistelt eltérés |
| secrets | 3046 fájl, 0 lelet |
| l10n | en/hu 1405 üzenet, parity OK |

## Merge-döntés

Nyitott BLOCKER/MAJOR nincs; correctness és security review **APPROVED**.
Merge akkor engedélyezett, ha a jelen review-commit utáni exact-SHA Full Gate
és Router CI is `success`, és a branch a dispatch óta nem maradt le a
`origin/main` mögött.
