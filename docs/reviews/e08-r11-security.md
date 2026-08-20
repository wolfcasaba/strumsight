# E08-R11 — High-risk security és abuse review

Brief: `docs/rounds/e08-r11-qualified-day-planned-rest-and-recovery.md`
Diff: `cca0c4d3..0df3c6f8`
Reviewer: Codex Sol (`gpt-5.6-sol`) · Dátum: 2026-08-20
Verdikt: **APPROVED — security szempontból**

## Összegzés

CRITICAL: 0 · BLOCKER: 0 · MAJOR: 0 · MINOR: 0 · NOTE: 1

Az új policy tiszta, lokális és determinisztikus. Nem olvas hálózatot,
storage-ot vagy rendszerórát; nem ír reward ledgert; nincs logolás, secret,
felhasználói szöveg vagy nyers audio. A cross-feature függőség kizárólag a
Practice Generator publikus barreljén keresztül történik.

## Ellenőrzött határok

- Canonical event `epochDay` és activity-day eltérés fail-closed
  `ArgumentError`.
- Negatív request-nap, negatív duration policy és fordított recovery-küszöb
  fail-closed.
- Recovery rövidítés csak explicit caller-bemenettel nyílik meg.
- Planned rest typed publikus reasonből jön; nincs belső feature-import.
- Nincs XP-levonás, ledger-mutation, hálózat, file IO, clock read vagy secret.
- A scope-audit OK; `check_secrets` 0 finding.

## Megfigyelés

### S1 — NOTE — A service belső, megbízható caller-contractot feltételez

`weeklySchedule` és `qualifiedDayHistory` mérete nincs külön korlátozva. A
shipping Practice Generator egy hetes, belső contractot ad, ezért ez nem
külső támadási felület és nem merge-blokkoló. Ha a contract később importált
vagy hálózati adatot közvetlenül fogad, a boundary adapternek méret- és
schema-korlátot kell alkalmaznia.

## Merge-hatás

Security finding nem blokkol. A correctness review F1 MAJOR lelete ettől
függetlenül `0df3c6f8`-ban lezárult; a security verdikt változatlanul APPROVED.
