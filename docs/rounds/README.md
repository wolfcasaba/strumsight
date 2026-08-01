# Kör-briefek

Körönként egy fájl: `eXX-rYY-<slug>.md`.

A brief a Claude tervezői kimenete és a Codex implementációs szerződése — a
kör indítása ELŐTT commitolva. Sablon és szabály:
[`docs/execution/08-round-brief.md`](../execution/08-round-brief.md).
Protokoll: [ADR 0055](../adr/0055-agent-role-protocol.md), `AGENTS.md` §15.

Az E01-R01…R09 körök még a brief bevezetése előtt futottak; a történetük a
`HANDOFF.md`-ben és a PR-okban van.

## Státuszok

`PREPARED` → `PLANNING` → `IN PROGRESS` → `IN REVIEW` → `DONE`.

A **`PREPARED`** egy előre, batchben megírt brief: a „Jelenlegi állapot" a
megírás pillanatának `main`-jét tükrözi, ezért minden ilyen brief fejlécében ott
a ⚠ **pre-flight** blokk — indítás előtt az orchestrátor újraolvassa az érintett
kódot, javítja a driftet, megírja az előre kiosztott számú ADR-t, majd
`PLANNING`-re állítja és a **kör-branchre** commitolja (ADR 0055: a brief a kör
indítása ELŐTT commitolva).

**Előre megírt batch (2026-07-31, `main` @ `ce8fbce`):** E02-R10…R20, ADR
0076–0085 kiosztva; az első szabad ADR-szám utána **0086**. A körök közti
függőségek és az összefoglaló tábla: `HANDOFF.md` §6.

## Epic 3 — Song Trainer előkészített batch

**Tervezési baseline:** 2026-08-01, `main` @ `eeb4f6d`.

**Főterv:**
[`docs/superpowers/plans/2026-08-01-epic-03-song-trainer.md`](../superpowers/plans/2026-08-01-epic-03-song-trainer.md)

Az alábbi 22 brief mind `PREPARED`: nem indított kör és nem végrehajtási
engedély. E03-R01 csak E02-R20 merge-je után indulhat. Ezután minden egyes kör
előtt kötelező a friss `main`, a közvetlen elődkör, a tényleges contractok,
state producerek, erőforrás-tulajdonosok, numerikus határok és az engedélyezett
fájllista pre-flight auditja. Az esetleges ADR-ek tényleges sorszámát csak ez
az audit osztja ki; a planning batch az aktív Epic 2 mellett nem foglal számot.

| Fázis | Körök | Briefek |
|---|---|---|
| I — Domainalapok | E03-R01–R05 | [R01](e03-r01-baseline-and-boundaries.md), [R02](e03-r02-song-document-identity-metadata.md), [R03](e03-r03-song-structure-and-time-map.md), [R04](e03-r04-tracks-events-monophonic-analysis.md), [R05](e03-r05-validator-normalizer-capabilities.md) |
| II — Migráció, storage, natív import | E03-R06–R10 | [R06](e03-r06-legacy-song-setlist-adapters.md), [R07](e03-r07-song-repository-asset-store.md), [R08](e03-r08-persistent-v2-migration.md), [R09](e03-r09-native-json-import-export.md), [R10](e03-r10-import-flow-security-boundary.md) |
| III — Külső formátumok | E03-R11–R14 | [R11](e03-r11-musicxml-mxl-importer.md), [R12](e03-r12-midi-importer.md), [R13](e03-r13-guitar-pro-feasibility.md), [R14](e03-r14-guitar-pro-path.md) |
| IV — Tartalomkezelés és transport | E03-R15–R18 | [R15](e03-r15-song-library-import-ui.md), [R16](e03-r16-song-editor-v2.md), [R17](e03-r17-overview-track-range-setup.md), [R18](e03-r18-transport-backing-playback.md) |
| V — Trainer, progress, Epic-zárás | E03-R19–R22 | [R19](e03-r19-practice-compiler-chord-rhythm.md), [R20](e03-r20-pitch-observation-note-scoring.md), [R21](e03-r21-trainer-ui-loop-speed-results.md), [R22](e03-r22-setlist-progress-epic-closure.md) |

Az R13 döntési kör: production GP parserkódot nem szállít. Az R14 két teljes,
egymást kizáró útból indul; a pre-flight az R13 elfogadott ADR-je alapján
pontosan egyet aktivál, a másikat tiltott zónává teszi. Az R19 csak a Practice
feature tényleges publikus contractján keresztül indulhat; belső Practice import
nem használható a hiányzó boundary megkerülésére.
