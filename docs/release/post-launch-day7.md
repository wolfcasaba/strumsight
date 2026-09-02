# Post-launch stabilizációs riport — 7. nap

- **Kör:** E12-R34 (ADR 0490 D8)
- **GA-alap:** Kör 33 (`docs/release/ga-record.md`)
- **Ablak:** a GA production-dispatchtól számított 7. nap.

**Ez a dokumentum VÁZ.** A mezőket a user + support tölti ki a GA utáni
valós adatokból — ez a kör NEM generál, NEM becsül és NEM talál ki crash-
számot, migrációs eredményt, akku- vagy audio-metrikát, sem support-jegyszámot.
Egy kitöltetlen váz nem stabilizáció; a kitöltés hiánya azt jelenti, hogy a
7. napi review MÉG NEM történt meg — nem azt, hogy minden rendben.

## Kötelező mezők

### Crash

- **Crash-mentes felhasználói arány (crash-free rate):** `<TBD — support/monitoring adat>`
- **Top crash-ok (ha van):** `<TBD>`
- **Trend az előző héthez képest:** `<TBD>`

### Migráció (migration)

- **Adatbázis/séma migrációk lefutása:** `<TBD — sikeres/sikertelen, hibaüzenet>`
- **Rollback szükségessége:** `<TBD>`

### Akkumulátor (battery)

- **Háttérben mért akkufogyasztás (battery drain) a detektálás alatt:** `<TBD>`
- **Felhasználói panaszok akkufogyasztásra:** `<TBD>`

### Audio

- **Audio-pipeline hibajelentések (audio dropout, latencia, mikrofon-hozzáférés):** `<TBD>`
- **DSP-detekciós pontosság éles környezetben (ha mérhető):** `<TBD>`

### Support

- **Nyitott support jegyek száma (open support tickets):** `<TBD>`
- **Legyakoribb panasz-kategóriák:** `<TBD>`
- **Bezárt hotfixek (ha volt) az [`operations/postmortems/`](../operations/postmortem-template.md) alapján:** `<TBD>`

## Döntés

- **Stabilizáció állapota:** `<TBD>` (stabil / megfigyelés alatt / hotfix szükséges)
- **Következő review:** 14. nap ([`post-launch-day14.md`](post-launch-day14.md))
