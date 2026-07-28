---
id: 112
topic: Implementation Order — fázisok A–E, első 12 konkrét kör (E01-R01..R12), párhuzamosítási és gate-szabályok
tags: [execution, order, phases, rounds]
status: active
depends_on: [103]
canonical_target: docs/execution/01-implementation-order.md
verify: fázisváltás csak completion report után
source: chatgpt-plan 2026-07-28 (Codex Execution Pack, 58-file manifest)
---

# Implementation Order

## Cél

Ez a dokumentum meghatározza a StrumSight SDD végrehajtási sorrendjét. A Chapter-sorrend terméklogikát mutat; a tényleges megvalósítás függőségi kapuk alapján történik.

## Fázis A — Platform foundation

1. Chapter 2, Kör 1–16.
2. A platform foundation csak akkor zárható le, ha:
   - package és platformazonosítók rendezettek;
   - config, storage, network és failure contract stabil;
   - mikrofon ownership tesztelt;
   - backend migráció és CI működik;
   - production signing nem debug alapú.

## Fázis B — Learning core

3. Chapter 3, Practice Engine, teljesen.
4. Chapter 7, Audio Analysis 2.0, legalább a domain/pipeline/evidence contract körei.
5. Chapter 4, Song Trainer.
6. Chapter 7 fennmaradó evaluation, library és integrációs körei.

A Practice és Song nem készíthet saját, egymással inkompatibilis score vagy evidence modellt. Az Audio Analysis adja a közös részletes mérési dokumentumot.

## Fázis C — Intelligence

7. Chapter 5, AI Guitar Teacher cloud/abstract gateway és RAG/tool contractjai.
8. Chapter 6, Computer Vision — először capability spike, majd csak mérhető képességek.
9. Chapter 8, AI Practice Generator.
10. Chapter 11, Offline AI — kizárólag a Chapter 5 stabil `TutorModelGateway` contractjára.

## Fázis D — Engagement

11. Chapter 9, Gamification — canonical activity event és idempotens reward ledger után.
12. Chapter 10, Community — csak production backend, moderation és privacy alapok után.

A skill mastery nem azonos az XP-vel. Community leaderboard csak verified, szerveroldalon ellenőrzött eredményt használhat.

## Fázis E — Release és integráció

13. Chapter 12 governance körei már korán alkalmazhatók: backlog schema, branch protection, environment, quality gate.
14. Beta/RC/GA körei csak az érintett feature-ek Definition of Done-ja után.

## Első 12 konkrét kör

1. E01-R01 Repository baseline.
2. E01-R02 Projektazonosítók.
3. E01-R03 App bootstrap.
4. E01-R04 Failure/result/logging.
5. E01-R05 Storage infrastruktúra.
6. E01-R06 Settings migráció.
7. E01-R07 User content storage.
8. E01-R08 Network/auth hardening.
9. E01-R09 Audio lifecycle.
10. E01-R10 Közös music/audio domain.
11. E01-R11 Routing.
12. E01-R12 Backend config és migráció.

## Párhuzamosíthatóság

Párhuzamos munka csak akkor megengedett, ha:

- külön fájl- és contractterületen dolgozik;
- nincs közös schema vagy public API módosítás;
- külön branchek és külön PR-ok;
- előre rögzített merge-sorrend;
- az integrációs owner futtatja a teljes gate-et.

Jellemzően párhuzamosítható:

- dokumentáció és fixture előkészítés;
- backend route és Flutter UI, ha az OpenAPI contract már befagyott;
- evaluation harness és production adapter;
- accessibility audit és nem funkcionális tesztek.

Nem párhuzamosítható kontroll nélkül:

- storage schema migráció;
- canonical event contract;
- audio session ownership;
- public domain model;
- model asset és Dart inference;
- database migration ugyanazon táblákon.

## Gate szabály

A következő fázisba lépéshez az előző fázis completion reportja kötelező. Részleges előrelépés csak dokumentált feature flaggel és dependency waiver ADR-rel történhet.

---
