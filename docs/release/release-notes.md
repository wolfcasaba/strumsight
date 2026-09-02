# Release notes — StrumSight

**Kör:** `E12-R33`. **Forrás:** [`ga-record.md`](ga-record.md) (build-,
verzió- és flag-profil-mezők, a manifest deklarált bemeneteiből
recomputálva) és [`known-issues.md`](known-issues.md) (nyitott hibák, teljes
lista). Ez a jegyzet **determinisztikus**: nem tartalmaz generálási
időbélyeget vagy más, futásfüggő adatot — csak a fent nevezett két forrásból
MÉRT tényeket ismétli meg, tömörebb, felhasználó-orientált formában.

## Build

- Verzió: `1.0.0+1` (`pubspec.yaml`)
- ML modellcsomag: séma v1, 4 modell (`assets/ml/model_manifest.json`)
- Tudáscsomag (AI Tutor): séma v1, 10 dokumentum
  (`assets/tutor_knowledge/manifest.json`)

## Elérhetőségi állapot

`ga_status: not-yet` — lásd [`ga-record.md`](ga-record.md) §1: a
lépcsőzött rollout mindhárom lépcsője (`stage-1`/`stage-5`/`stage-20`)
`pending`, és nyitva van egy P0 + öt P1 blocker
([`blockers.md`](blockers.md)). A teljes, 16 kulcsos flag-profil
pillanatkép ugyanott, §3 — az egyetlen `ga`-besorolású capability
(`practiceEngineV2Enabled`) production alapértelmezése ma `false`.

## Ismert hibák

A teljes, mért, nyitott hibalista: [`known-issues.md`](known-issues.md).
Ez a jegyzet nem másolja be a táblát — a duplikált másolat elavulna, a
hivatkozás nem.

## Rollback-készenlét

A GA UTÁN is fennálló rollback-cél és a hozzá tartozó, ténylegesen
lefuttatott gyakorlat: [`ga-record.md`](ga-record.md) §5,
[`docs/operations/disaster-recovery-drill.md`](../operations/disaster-recovery-drill.md).

## Közzététel

A store-oldali közzététel (rollout-százalék, GA-jelölés) EMBERI művelet —
lásd [`ga-record.md`](ga-record.md) §8.
