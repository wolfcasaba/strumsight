# E07-R05 — Review

Brief: `docs/rounds/e07-r05-skill-evidence-normalisation.md`
Diff: `c4497773..1b1148f9`
Reviewer: Codex (orchestrator fallback) · Dátum: 2026-08-15
Verdikt: APPROVED

## Összegzés

BLOCKER: 0 · MAJOR: 0 nyitott · MINOR: 0 · NOTE: 0

## Acceptance criteria

| # | Kritérium | Teljesült | Bizonyíték |
|---|---|---|---|
| A1 | Nincs nyers média az evidence-ben | ✅ | `DiscomfortReport` csak kategóriát tárol; a data-URI regresszió bizonyítja, hogy a transient note nem tárolódik vagy logolódik. |
| A2–A3 | Outcome-ID deduplikáció | ✅ | `evidence_aggregator_test.dart`, 3 dedup-cella. |
| A4 | Discomfort elkülönül | ✅ | `skill_evidence_test.dart`, performance/discomfort külön value object. |
| A5 | Érzékeny szöveg nincs logban | ✅ | Gyűjtő loggeres tesztek; valódi-sértés próba alább. |
| A6–A7 | Időbélyeg- és confidence-validáció | ✅ | 8 célzott domain-cella. |
| A8–A9 | Elévülés és bounded query | ✅ | 9 repository-cella, inkluzív határral. |

## Scope-audit

`python3 tools/scope-audit.py --repo /home/ubuntu/ss-sonnet-impl-e07-r05 --brief docs/rounds/e07-r05-skill-evidence-normalisation.md --base c4497773` → **OK**, 8 changed path, 0 generated/ignored. A review-artefaktum a szabály szerinti generált/mentesített útvonal.

## Megállapítások

### F1 — MAJOR — Szabad discomfort-szöveg exportálható evidence-ben — FIXED (`8bff05c3`)

Az első review `DiscomfortReport.note` publikus `String` mezőjét találta: ez data URI-t, base64 hangot vagy fájlútvonalat is perzisztálhatott volna. A javító commit eltávolította a mezőt; az aggregátor `discomfortNote` bemenete tranzitív és azonnal eldobott. A regressziós cella data-URI-szerű bemenettel igazolja, hogy nincs storage-, serialization-, log- vagy exception-leak.

### Valódi-sértés próba (A5)

Az izolált klónban az `EvidenceAggregator` logmezőihez ideiglenesen hozzáadtam `note: discomfortNote`-ot. A `flutter test test/features/practice_generator/evidence/evidence_aggregator_test.dart` **exit 1**-gyel bukott: a három A5-cella és az F1 data-URI-cella egyaránt érzékeny-szöveg-szivárgást jelzett. A sort visszaállítottam; a klón tiszta és a teljes round gate zöld.

## Gate-bizonyíték ellenőrzése

| Gate | Ellenőrizve |
|---|---|
| format + analyze | ✅ izolált `/tmp/review-e07-r05-fix.CffiP3` klónban |
| 3 célzott tesztfájl | ✅ 7 + 13 + 9 teszt zöld |
| architecture, secrets, l10n | ✅ teljes `tools/round-gate.sh` összegzés zöld |
| CI | ⏳ a review-jelentés commitjának exact SHA-jára újra-dispatch szükséges |

### C1 — CI architecture guard — FIXED (`1b1148f9`)

Full Gate `31907084609` egyetlen hibája a domain-documentationben szereplő
tiltott `DateTime.now(` szövegliterál volt; a guard ezt helyesen észlelte. A
javítás csak a comment átírása, a viselkedés változatlan. Az implementer
célzott round gate-je zöld; a review-artefaktum új SHA-jára ismét CI szükséges.

## Merge-döntés

Nincs nyitott BLOCKER vagy MAJOR. Merge csak a review-commit exact SHA-ján zöld Full Gate és Router CI után engedett.
