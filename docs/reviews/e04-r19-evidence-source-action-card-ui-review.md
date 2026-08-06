# Review — E04-R19 Evidence, source & action card UI

- **Branch:** `minimax/e04-r19-evidence-source-action-card-ui`
- **Implementer commit:** `751f1e0` (base `e8ae7ee`)
- **Implementer motor:** MiniMax M3 (`minimax` legacy override, ADR 0069)
- **Reviewer:** Claude (Opus 4.8), orchestrátor — READ-ONLY, izolált `/tmp/review-e04-r19` klón
- **Verdikt:** **APPROVED** — 0 BLOCKER / 0 MAJOR / 0 MINOR

## 1. Jelzés + handoff

`.codex-round-status`: `status=done`, gate zöld (format/analyze/test/architecture/
secrets/l10n), `scope_audit=ok` (9 fájl). A stalled első futás után egy folytató
dispatch fejezte be és commitolt (a driver crash-protokollja szerint, ugyanaz a
munkapéldány). A `done` jelzésbeli `dirty_files=1` a `flutter gen-l10n` tranziens
gitignore-olt kimenete volt — a review-klónban a working tree tiszta.

## 2. Scope-audit

`git diff --name-only e8ae7ee...751f1e0` mind a 10 útvonala a brief
`allowed_paths` listáján belül. `public.dart` engedélyezett volt, de érintetlen
(rendben — az additív export opcionális). Listán kívüli fájl: nincs.

## 3. Acceptance criteria — tételes bizonyíték

Az izolált klónban `flutter test test/features/ai_tutor/presentation` → **41/41 zöld**
(a 27 örökölt R18-teszt + a 14 új R19-cella). Cellánként:

| Acceptance-cella | Bizonyíték |
|---|---|
| evidence-sheet (measured detail + reference) | `tutor_evidence_source_test.dart` „evidence sheet exposes measured detail…" |
| source-mapping (jóváhagyott mezők, nyers út nélkül) | „source sheet maps approved source fields without raw path" — `<b>`, `sha256:private-hash` **nem** renderel |
| inference-warning | „inference sheet shows a warning…" |
| confirm (typed executor) | `tutor_action_card_test.dart` „confirm executes typed action" — `identical(executor.actions.single, action)` |
| reject | „reject leaves the typed executor untouched" — executor üres |
| **stale** | „stale proposal is visible and never reaches executor" — `expired` → `blocked`, executor üres |
| double-tap idempotens | GateExecutor + két tap → 1 action |
| invalid-action | `TutorRawRouteActionProposal` → blocked, nincs confirm-gomb, executor üres |
| plan-edit | „editing a block uses copyWith…" → `PracticePlanSource.userEdited`, targetDuration újraszámolva |
| large-text | textScale=3 mindhárom felületen, `takeException()==null` |
| semantics | chip/card/screen mind Semantics-label |
| **provenance-mátrix** | measured/trend/knowledge/inference **mind** text+ikon+szín — cellánként (`backgroundColor` a scheme-színnel egyenlő) |
| typed-executor-only | executor interfész `TutorActionExecutor.execute(TutorAction)` — nyers string architekturálisan lehetetlen; a raw-route proposal pre-execution blocked |

## 4. Falszifikációs próba (reviewer, eldobható, visszaállítva)

A sanitizert a `/tmp` klónban `return value;`-re rontottam → az injection-érzékeny
cellák **pirosra váltottak** (`action card shows exact preview fields` és `source
sheet maps approved source fields without raw path` bukott). A guard tehát valódi,
nem dekoratív. A rontást visszaállítottam (`git checkout --`).

## 5. Kötött döntések (brief §5) — mind teljesül

1. **Exact action-preview + csak typed executor (ADR 0133):** a kártya kizárólag
   `ActionConfirmationService.propose/confirm/reject`-en át hív; `preview.fields`
   exact értékek jelennek meg; nincs nyers route/URL/string végrehajtás.
2. **Model-label sosem kerüli meg a localizationt/sanitizert (ADR 0132):** minden
   felhasználói string `AppLocalizations`-on át; a model-eredetű értékek
   `sanitizeTutorDisplayText`-en át (control-char + bidi-override strip, `<`/`>`
   semlegesítés, whitespace-collapse).
3. **Provenance text+ikon+szín (a11y):** `TutorEvidenceChip` mindhárom csatornát adja.
4. **Stale proposal nem fut:** `_confirmOnce` újra-validál; a lejárt proposal a
   service-en át nem éri el az executort.

## 6. Architektúra + termékhatárok

- Nincs új action/plan domain-logika — a UI a meglévő R09/R11 típusokat és
  service-eket használja (`ActionConfirmationService`, `PracticePlanValidator`,
  `TutorActionValidator`).
- `TutorEvidenceKind` prezentációs enum a widget-rétegben; a domain-fogalmakra
  (`DebriefFactProvenance`, `TutorSourceRef`, `StudentProfileFieldProvenance`)
  tiszta függvényekkel képez.
- `source-belső import` tilalom megtartva — `chunkHash` (privát) sosem renderel;
  csak a publikus `chunkId`.
- Lifecycle: `TutorActionCard` `confirm`-je `mounted`-őrrel ír state-et.

## 7. Döntés

**APPROVED.** A zöld kapu (exact-SHA full-gate + Router CI) teljesülése az
orchestrátor merge-előfeltétele; a tartalmi hűség fent mérve. Nincs nyitott
BLOCKER/MAJOR/MINOR.
