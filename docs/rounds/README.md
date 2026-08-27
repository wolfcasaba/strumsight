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

## Chapter 12 — Release Roadmap & Final Integration előkészített batch

**Tervezési baseline:** 2026-08-27, `main` @ `9ca4a0dc`. **36 brief** (`E12-R01`–`E12-R36`),
mind `PREPARED`. ADR-tartomány: **0443–0465** (az Epic 10 batch 0442-ig kiosztott
számai érintetlenek). Queue: 36 `hold` sor az E13 blokk után.

**User-döntés 2026-08-27:** a sáv a teljes UI (Chapter 13) elkészülte UTÁN indul,
**2 párhuzamos sloton**, Opus 5 orchestrátorral és Claude Sonnet 5 (`--effort high`)
implementerrel; az **Epic 10 (Offline AI) marad utolsónak**.

**A fejezet 36 kört tartalmaz**, nem 42-t — a `docs/sdd/00-index.md` értéke MÉRT hiba,
amit az `E12-R02` gépi ellenőrzéssel javít (`tool/check_sdd_index.dart`).

| Fázis | Körök | Tárgy |
|---|---|---|
| I — Program- és repository-alapok | E12-R01–R05 | baseline és blocker-lista, SDD-index + dependency graph, delivery workflow, környezet-izoláció, feature flag registry |
| II — Kiadási artefaktum és backend | E12-R06–R08 | versioning/provenance/SBOM, production signing, staging + migráció + recovery |
| III — Integráció és mérce | E12-R09–R16 | esemény-katalógus, idempotens outbox, e2e harness, fixture-korpusz, device-mátrix, performance budget, erőforrás-koegzisztencia, AI release gate |
| IV — Privacy, security, minőség | E12-R17–R21 | adat-leltár + consent enforcement, threat model + scan, telemetria/SLO, a11y + l10n audit, tartalom-katalógus |
| V — Béta és RC | E12-R22–R26 | béta-terjesztés + feedback, legacy migráció RC, store/legal csomag, RC-összeállítás, rollback-gyakorlat |
| VI — Rollout és zárás | E12-R27–R36 | Closed Beta, scope cut, Open Beta, feature freeze, production cohort, staged rollout, GA, post-launch + hotfix, adósság-takarítás, program-zárójelentés |

**Emberi kapu:** az `E12-R27`, `R29`, `R31`, `R32` és `R33` körök tényleges INDÍTÁSA
(tesztelő-meghívás, deploy, rollout-százalék, GA) user-művelet — ugyanaz a kapu-típus,
mint a valós gitáros APK-teszt. Ezek briefjei ezért eszközt, ellenőrzőlistát és
döntési sémát szállítanak, nem magát a műveletet; a §0.0 mindegyikben kimondja a határt.
