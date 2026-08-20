# E08-R04 — Security and product-boundary review

Brief: `docs/rounds/e08-r04-activity-outbox-and-reliable-processing.md`
Reviewed implementation: `0e6c4472`
Reviewer: independent security reviewer · Dátum: 2026-08-20
Verdikt: APPROVED

## Összegzés

CRITICAL: 0 · BLOCKER: 0 · MAJOR: 0 · MINOR: 0 · NOTE: 0

A diff nem vezet be hálózati hívást, nyers audio-/kameraadat-kezelést vagy
érzékeny payloadot kiíró logot. A perzisztens sor kizárólag explicit
`KeyValueStore`-t használ; nincs új platform-erőforrás vagy UI-kötés.

## Lezárt megállapítások

| ID | Lelet | Státusz |
|---|---|---|
| S1 | Karantén restart után nem tartós | FIXED `1a429d72` |
| S2 | Pending→karantén két írása crash adatvesztést okozhat | FIXED `0e6c4472`: egyesített snapshot |
| S3 | `capacity`/`maxAttempts` csak debug asserttal validált | FIXED `0e6c4472`: runtime `ArgumentError.value` |

S2-t a reviewer valódi-sértés próbával is ellenőrizte: az egyesített snapshot
karanténmezőjének ideiglenes elhagyása restart után piros A6/A7 cellákat adott.
S3 őrének kiiktatása a release-szemantikát mérő Validation cellát pirosra
váltotta. Mindkét próbát visszaállítás és zöld célteszt követte.

## Scope és kapu

Az izolált scope-audit a javító commiton két engedélyezett változott útvonalat
és nulla listán kívüli fájlt mért. A célzott `round-gate` format, analyze,
test, architecture, secrets és l10n lépései zöldek.

## Merge-döntés

Nincs nyitott security vagy product-boundary lelet. A kötelező exact-SHA CI
evidencia után merge-elhető.
