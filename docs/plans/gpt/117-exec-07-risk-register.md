---
id: 117
topic: Risk Register — 22 kockázat (R-001 synth→real gap, R-002 mic leak, R-008 doku-drift, R-020 scope creep...) mitigációkkal
tags: [execution, risk, governance]
status: active
depends_on: []
canonical_target: docs/execution/07-risk-register.md
verify: epic-nyitáskor/záráskor review
source: chatgpt-plan 2026-07-28 (Codex Execution Pack, 58-file manifest)
---

# Risk Register

Skála: valószínűség és hatás `Low / Medium / High / Critical`.

| ID | Kockázat | Valószínűség | Hatás | Korai jel | Mitigáció | Owner | Státusz |
|---|---|---|---|---|---|---|---|
| R-001 | Valós gitáron gyengébb DSP/ML pontosság, mint szintetikus fixture-ön | High | Critical | magas synthetic score, gyenge user clip | real-audio corpus, device APK gate, confidence calibration | Audio/ML | Open |
| R-002 | Mikrofon nem szabadul fel navigáció vagy hiba után | Medium | Critical | Android mic indicator aktív marad | exclusive coordinator, lifecycle/property tests | Mobile | Open |
| R-003 | Low-end eszközön latency, thermal vagy OOM | High | High | frame drop, throttling, process kill | device tier, benchmark, graceful degradation | Platform | Open |
| R-004 | Offline AI modell túl nagy vagy lassú | High | High | TTFT/token rate cél alatt | runtime bake-off, quantization, smaller tier, fallback | AI Runtime | Open |
| R-005 | Kamera exact fret/string felismerése nem elég pontos | High | High | calibration drift, false feedback | experimental flag, evidence threshold, ne legyen kötelező score | Vision | Open |
| R-006 | Storage migráció felhasználói adatot veszít | Medium | Critical | decode/migration error | versioned schema, idempotent migration, backup fixture | Mobile Data | Open |
| R-007 | Cross-feature függőség új monolitot hoz létre | Medium | High | belső feature importok nőnek | public API, architecture gate, csökkenő allowlist | Architecture | Open |
| R-008 | README/CLAUDE/HANDOFF elavult és ellentmond az SDD-nek | High | Medium | más package, régi roadmap | authority policy, migration plan, baseline audit | Tech Lead | Open |
| R-009 | Debug signinggal kerül ki production build | Medium | Critical | release workflow debug keystore | production signing gate, separate channels | Release | Open |
| R-010 | Secret vagy diagnostics token commitba kerül | Medium | Critical | lab config változás, log leak | secret scan, GitHub secrets, rotation, redaction | Security | Open |
| R-011 | Backend SQLite/create_all nem skálázódik productionban | High | High | lock, schema drift | PostgreSQL, Alembic, readiness | Backend | Open |
| R-012 | Community moderáció elégtelen | Medium | Critical | abuse/report backlog | report/block, moderation SLA, staged rollout | Trust & Safety | Planned |
| R-013 | XP/leaderboard csalható vagy duplán könyvel | Medium | High | replay, offline duplication | idempotent ledger, verified event, server authority | Gamification | Planned |
| R-014 | Modell/dataset licence nem engedi shippinget | Medium | Critical | hiányzó licence/provenance | licence register, legal gate, model card | ML/Product | Open |
| R-015 | Guitar Pro támogatás jogi/technikai zsákutca | Medium | Medium | parser/licence bizonytalan | decision spike, MusicXML/MIDI first, capability gate | Song | Planned |
| R-016 | Cloud AI költség kontrollálatlan | Medium | High | token/user gyorsan nő | quotas, caching, compact context, offline routing | AI/FinOps | Planned |
| R-017 | AI hallucination rossz technikai tanácsot ad | Medium | High | unsupported claim | curated RAG, tool evidence, safety eval, uncertainty | AI Tutor | Planned |
| R-018 | Hálózati funkció megsérti offline ígéretet | Medium | Critical | startup request logged out | network guard integration test, feature flags | Platform | Open |
| R-019 | CI túl lassú vagy instabil, ezért megkerülik | Medium | High | flaky tests, long queue | test pyramid, cache, nightly heavy eval | DevEx | Open |
| R-020 | Egyetlen fejlesztő/Codex túl nagy programot nem tud követni | High | High | scope creep, handoff drift | one-round rule, traceability, completion report | Program | Open |
| R-021 | API/schema verzióütközés régi klienssel | Medium | High | 4xx/deserialize spike | versioned contract, backward compatibility, rollout | Backend | Planned |
| R-022 | Privacy/terms nem fedi cloud/community/AI adatfolyamot | Medium | Critical | release review blocker | data inventory, consent, retention, legal review | Product/Legal | Planned |

## Review cadence

- Minden Epic elején és végén.
- Minden release candidate előtt.
- Critical trigger esetén azonnal.
- A lezárt kockázat megtartandó lezárási bizonyítékkal.
