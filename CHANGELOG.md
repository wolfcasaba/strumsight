# Changelog — StrumSight

Ez a fájl a release-történetet rögzíti. A gépileg parszolható fejléc-blokk
(alább) a `pubspec.yaml` verzió/build mezőit és a release-manifest
séma-verzióját köti össze — a `tool/release/verify_freeze.py` ezt a blokkot
a mért forrásokkal veti össze, és determinisztikusnak követeli meg (nincs
benne generálási időbélyeg vagy dátum, ADR 0447 D1). A soronkénti,
kör-szintű történet a [`HANDOFF.md`](HANDOFF.md)-ben és a
[`docs/handoff-archive.md`](docs/handoff-archive.md)-ben él — ez a fájl a
Chapter-szintű mérföldköveket és a jelen release-előkészítő szakaszt sorolja,
kizárólag MÉRT állításokkal (§0.0 P4).

<!-- release-header:begin -->
version: 1.0.0
build: 1
schema_version: 1
<!-- release-header:end -->

## [1.0.0+1] — Unreleased (Release Candidate előkészítés alatt)

**Állapot:** a build ma **NEM** GA-kész — lásd
[`docs/release/ga-scope.md`](docs/release/ga-scope.md) („NEM KÉSZ (NOT
READY)") és [`docs/release/known-issues.md`](docs/release/known-issues.md) a
nyitott hibákért. A verzió/build-szám (`1.0.0+1`) a `pubspec.yaml:5`-ből
mért érték — ez a kör nem emeli (a build-szám emelése `blocker-fix`
osztályú termékváltozás lenne, ami ennek a körnek tilos zónája,
[`docs/release/feature-freeze.md`](docs/release/feature-freeze.md)).

### Chapter-szintű mérföldkövek (forrás: `docs/sdd/00-index.md` fejezet-tábla)

- **Chapter 1–2 — Architecture principles & Core Platform** — Epic 1 lezárva
  (zárókör `E01-R16`, `docs/sdd/epic-01-completion-report.md`).
- **Chapter 3 — Practice Engine** — Epic 2 lezárva (zárókör `E02-R20`,
  2026-08-01, `docs/sdd/epic-02-completion-report.md`).
- **Chapter 4 — Song Trainer** — Epic 3, implementation evidence recorded;
  release blockerek nyitva (`docs/sdd/epic-03-completion-report.md`).
- **Chapter 5 — AI Guitar Teacher** — Epic 4, specifikálva.
- **Chapter 6 — Computer Vision** — Epic 5, specifikálva.
- **Chapter 7 — Audio Analysis 2.0** — Epic 6, implementation evidence
  recorded; rollout shadow módban, release blockerek nyitva
  (`docs/sdd/epic-06-completion-report.md`).
- **Chapter 8 — AI Practice Generator** — Epic 7, specifikálva.
- **Chapter 9 — Gamification** — Epic 8, specifikálva.
- **Chapter 10 — Community Platform** — Epic 9, specifikálva.
- **Chapter 11 — Offline AI** — Epic 10, specifikálva.
- **Chapter 12 — Release Roadmap, Sprint Planning & Final Integration** —
  folyamatban, indult `E12-R01` (PR #485, squash `ae058f88`, 2026-08-28); a
  jelen bejegyzés záró köre `E12-R30` (feature freeze és final regression).
- **Chapter 13/14** — cross-cutting UI/UX design system és recognition
  accuracy sávok, specifikálva/folyamatban, e release-en kívül esnek.

### Chapter 12 — Release Roadmap kör-összefoglaló (a teljes lista: `HANDOFF.md`)

A Chapter 12 sáv `E12-R01`-től `E12-R29`-ig 29 KÉSZ kört szállított a
release-előkészítés teljes vertikumán: program-baseline és blocker-leltár
(`E12-R01`), environment/channel izoláció (`E12-R04`), versioning/provenance/
SBOM (`E12-R06`), production signing hardening (`E12-R07`), staging backend
és migrációk (`E12-R08`), device matrix (`E12-R13`), privacy adat-leltár és
consent (`E12-R17`), threat model és security scan (`E12-R18`),
privacy-safe observability/SLO (`E12-R19`), accessibility/localization audit
(`E12-R20`), content catalog leltár (`E12-R21`), béta-terjesztés és consent
(`E12-R22`), legacy migration release candidate (`E12-R23`), store listing és
legal package (`E12-R24`), RC assembly workflow javaslat (`E12-R25`),
rollback és disaster recovery drill (`E12-R26`), Closed Beta launch és
monitoring (`E12-R27`), Beta stabilization és GA-scope/contract-freeze
(`E12-R28`), Open Beta és canary cohort (`E12-R29`). Minden kör PR-linkje és
squash SHA-ja a `HANDOFF.md` saját fejezetében él.

### Ez a kör (`E12-R30` — Feature freeze és final regression)

- Hozzáadva: [`docs/release/feature-freeze.md`](docs/release/feature-freeze.md)
  — a freeze bázisa (`freeze_base_sha: 4ac78365`) és a zárt, három elemű
  változás-osztály (`documentation` / `release-tooling` / `blocker-fix`).
- Hozzáadva: [`tool/release/verify_freeze.py`](tool/release/verify_freeze.py)
  — a freeze utáni diff osztályozása, a `known-issues.md` és e fájl
  fejléc-blokkjának fail-closed ellenőrzése (kilépő kód 0/1/2).
- Hozzáadva: [`docs/release/known-issues.md`](docs/release/known-issues.md)
  — a `blockers.md` tíz sorának MAI, soronkénti mérése, a Kör 25
  RC-workflow soha-nem-futott ténye, és hat gazdátlan, korábban mért nyitott
  lelet (`E12-R20`/`R21`/`R23`/`R24`/`R29`).
- Hozzáadva: ez a fájl, a release-fejléc gépi mércéjével.
