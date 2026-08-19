# E07-R25 — Review

Brief: `docs/rounds/e07-r25-analysis-and-vision-evidence.md`  
Diff: `0585083e..62db0425`  
Reviewer: Codex / gpt-5.6-terra  
Date: 2026-08-19  
Verdict: CHANGES REQUIRED

## Összegzés

BLOCKER: 0 · MAJOR: 1 · MINOR: 0 · NOTE: 0

The isolated gate and machine scope audit pass, but the Vision adapter does
not enforce its own `ObservationState` safety contract. The default reader is
safe today; the public port is not guaranteed to be.

## Acceptance criteria

| # | Kritérium | Teljesült | Bizonyíték |
|---|---|---|---|
| A1 | Nyers média nem lép át | ✅ | Both adapter serialization tests; narrow barrel export list. |
| A2 | Vision nélkül teljes értékű | ✅ | `vision_evidence_adapter_test.dart` empty-result cell. |
| A3 | Alacsony confidence nem agresszív | ✅ | Analysis adapter / weight-policy cells. |
| A4 | Jelminőség nem skill-ítélet | ✅ | Analysis adapter setup-advisory cells. |
| A5 | Csak allowlisted Vision proxy | ✅ | `metricNotAllowed` cell. |
| A6 | Konfliktus bizonytalanságot ad | ✅ | Analysis adapter conflict cells. |
| A7 | Capability-hiány explicit | ❌ | F1: a port által átadott `notObservable` fact nem védett. |
| A8 | Csak public API | ✅ | Architecture gate; adapter imports nested Vision barrel only. |

## Scope-audit

`tools/scope-audit.py --repo /tmp/review-e07-r25-2 --brief docs/rounds/e07-r25-analysis-and-vision-evidence.md --base 0585083e` → `OK` (13 changed path, 0 ignored).

## Megállapítások

### F1 — MAJOR — A `notObservable` Vision fact skill evidence-é válhat

- **Fájl:** `lib/features/practice_generator/data/adapter/vision_evidence_adapter.dart:149-182`
- **Probléma:** A doc-contract `observed`/`inferred` állapotot ír elő, de a
  loop csak az allowlistet ellenőrzi és az `experimental` confidence-ét
  korlátozza. Egy `VisionEvidenceReader` implementáció ezért átadhat egy
  allowlisted `VisionEvidenceFact(state: ObservationState.notObservable)`
  értéket, amelyből az adapter teljes `SkillEvidence`-et képez.
- **Bizonyíték:** A saját teszt `StubVisionEvidenceReader`-e direkt
  `VisionEvidenceFact` listát ad vissza (`vision_evidence_adapter_test.dart:32-43`),
  tehát ez a port-szintű bemenet ma reprezentálható. A meglévő A7 cella csak
  üres fact-lista melletti, előre gyártott warningot vizsgál (223-242), ezért
  a hibás adapter zöld maradna.
- **Hatás:** A kamera/capability hiánya hibásan negatív vagy pozitív
  skill-jelként léphet be a prioritásba, megsértve brief §5.2/§5.4 és A7
  degradációs szerződését.
- **Kötelező javítás:** Az adapterben fail-closed módon skipeld a
  `notObservable` facteket és adj stabil, raw-mentes warningot. A meglévő
  adapter-tesztben legyen olyan cella, amely egy stub-readeren át átadott,
  allowlisted `notObservable` factre **nulla evidence-et** és a warningot
  követel. Az `experimental` ceiling-viselkedés maradjon változatlan.
- **Ellenőrzés:** A javított `vision_evidence_adapter_test.dart` legyen piros
  a state-gate eltávolításakor, majd futtasd a brief négy célzott tesztjét a
  `tools/round-gate.sh` artefaktummal.
- **Státusz:** OPEN

## Gate-bizonyíték ellenőrzése

| Gate | Ellenőrizve |
|---|---|
| format | ✅ isolated clone, 0 changed files |
| analyze | ✅ no issues |
| célzott tesztek | ✅ 4/4 green |
| architecture / secrets / l10n | ✅ green |
| scope audit | ✅ `OK` |
| CI (full suite + property + workflow) | függőben — javítás után dispatch |

## Merge-döntés

F1 MAJOR nyitott, ezért merge tilos. Egy MiniMax javító kör szükséges ugyanazon
branch-en.
