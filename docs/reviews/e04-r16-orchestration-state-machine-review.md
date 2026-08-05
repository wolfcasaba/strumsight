# Review — E04-R16: Tutor orchestration state machine + output validator

- **Kör:** E04-R16 · **Branch:** `codex/e04-r16-orchestration-state-machine`
- **Implementer motor:** Codex (`gpt-5.6-terra`) · **Reviewer:** Claude (Opus 4.8)
- **Review-alap:** implementer commit `31c1268` + orchestrátor brief-korrekció `069f4e6`
- **ADR:** [0174](../adr/0174-ai-tutor-orchestration-state-machine.md)
- **Verdikt:** **APPROVED** — 0 BLOCKER, 0 MAJOR, 1 MINOR (follow-up R18-ra), 1 NOTE.

## 1. Jelzés + handoff

`.codex-round-status`: az implementer eredetileg `blocked`-ot jelzett — de a
blokk oka **nem kódhiba**, hanem a friss munkapéldányból hiányzó, gitignore-olt
generált `lib/l10n/app_localizations.dart` (754 pre-existing l10n analyze-hiba a
teljes analyze lépésen). Az orchestrátor a `tools/prepare-flutter-generated.sh`
scripttel helyreállította a generált előfeltételt (pipeline-prompt §5.5), utána a
gate ZÖLD. `scope_audit=ok`, `scope_audit_changed=8`. A handoff (brief §10)
kitöltve.

## 2. Gate-újrafuttatás (izolált)

- **Orchestrátor kézi gate** a munkapéldányban a generált l10n helyreállítása után:
  `tools/round-gate.sh test/features/ai_tutor/application` → **GATE_EXIT=0**;
  minden lépés ZÖLD (format, analyze, test, architecture, secrets, l10n).
- **Router CI** külön blokkolt (lásd §5, feloldva) — a `069f4e6` merge-SHA-n a
  hiteles exact-SHA evidencia a CI (full-gate + router-ci), a záró rituálék előtt
  ellenőrizve.
- Read-only review izolált klónban: `/tmp/review-e04-r16` (branch-checkout),
  scope-audit + kódolvasás + falszifikációs elemzés ott készült; próbatesztet a
  közös working tree-ben NEM futtattam.

## 3. Scope-audit

`git diff --stat origin/main...069f4e6` — 9 fájl, mind az `allowed_paths`-on belül:
ADR 0174 (pre-flight, orchestrátor), brief (pre-flight + korrekció, orchestrátor),
5 lib fájl (`controller/{state,command,effect}`, `orchestration/{orchestrator,
output_validator}`), 2 teszt. A `public.dart` **érintetlen** (nincs a diffben) →
az `ai_tutor_boundary_test.dart` üres-boundary invariánsa nem sérül. **Nulla
listán kívüli fájl.**

## 4. Acceptance criteria — tételes bizonyíték

Mind scripted fake-kel, determinisztikusan (`tutor_orchestrator_test.dart`):

| Kritérium | Teszt | Bizonyíték |
|---|---|---|
| happy path | `happy path completes…` | `status == completed` |
| retrieval-empty | ua. | `state.sources isEmpty`, mégis completed (üres retrieval legális) |
| tool-call | `executes a scripted read-only tool call…` | tool → visszatér streaming → completed |
| repair success | `repairs one invalid output…` | `repairCount == 1`, completed a javító válasszal |
| **repair failure → fallback** | `falls back after the bounded repair…` | `status == fallback`, `repairCount == 1`, **`starts == 2`** |
| cancel + late no-op | `cancel and late delta…` | `status == cancelled`, `responseText isEmpty` |
| concurrent-send | `rejects a concurrent send…` | `transition.isRejected`, requestId marad `request-1` |
| consent-revoked | `short-circuits revoked consent…` | `status == consentRevoked`, **`gatewayCalls == 0`** (start ELŐTT) |
| usage-limit | `maps the owned usage-limit gateway code…` | `FakeGatewayError('tutor.usage_limit')` → `status == usageLimit` |

**Validator** (`tutor_output_validator_test.dart`): grounded claim elfogadva;
**nem-alátámasztott knowledge-claim blokkolt** (`unsupportedClaimEvidence`);
malformed action-schema (`invalidActionSchema`) + lejárt action-proposal
(`invalidAction`) egyszerre blokkolva.

### Falszifikáció (a szövegesen előírt viselkedés gépi mércéje)

- **repair-cap = 1.** A `falls back…` teszt `expect(starts, 2, reason: 'The
  state-owned repair cap forbids a third start.')`. **Elemzés:** ha a reducer
  `if (state.repairCount < 1)` őrét eltávolítjuk (korlátlan repair), a 2. invalid
  output 3. `gatewayForAttempt` hívást indítana → `starts == 3` és a state nem
  `fallback` → a teszt PIROS. A mutáció-guard tehát valódi (megfelel a brief §6
  „reviewer eldobható mutációval pirosra váltja" előírásnak).
- **usage-limit kód-tulajdon.** A `tutorUsageLimitCode` konstans az
  orchestration-fájlban él (`tutor_orchestrator.dart:24`), NEM a gateway-rétegben
  → az ADR 0174 §5 tilos-zóna-előírása teljesül (mérve: a gateway-fájlok
  érintetlenek).
- **consent start ELŐTT.** `gatewayCalls == 0` bizonyítja, hogy a consent-revoked
  rövidzár a `gateway.start()` ELŐTT történik (nincs árva provider-request).

## 5. Router-CI blokk — feloldva (orchestrátor, tilos zóna nélkül)

A Router CI a `31c1268`-on PIROS volt:
`tools/tests/test_pipeline_throughput.py::test_real_epic_four_rounds_are_correctly_rejected`
(`AssertionError: [] is not true`). **Gyökérok:** a teszt hardkódoltan elvárja,
hogy az E04-R15 és E04-R16 briefek a `public.dart`-on ütközzenek. Az eredeti
pre-flight §0.0 SZŰKÍTÉS (a `public.dart` kivétele) megszüntette a konfliktust →
`paths_conflict == []`. A `tools/` a §4 **tilos zóna** (a mércét nem módosíthatja,
akit mér). **Feloldás (nem `tools/`-módosítás):** a §0.0 szűkítés visszavonva — a
`public.dart` visszakerült az `allowed_paths`-ba (R15 precedens), az export R18-ra
halasztva, a fájl érintetlen marad. Mérve: throughput+adr-numbering suite **46/46
OK** a korrekció után (`069f4e6`). A boundary-invariáns így is zöld (a fájl üres).

## 6. Leletek

| # | Súly | Fájl:sor | Lelet | Javasolt irány |
|---|---|---|---|---|
| 1 | **MINOR** | `tutor_orchestrator.dart:181-188, 292-299` | A `TutorPipelineFailed` (belső-hiba) terminális út `status: failed`-re zár, de — az összes többi terminállal (completed/fallback/consentRevoked/usageLimit/cancelled) ellentétben — **nem szabadítja fel a `_subscription`-t és a `_gateway`-t**. Elérhető pl. tool-hiba útján (`_executeTool` → `TutorPipelineFailed`, miközben a model-stream még feliratkozott). Az állapotgép LEZÁR (nincs végtelen loop, `failed` terminális), de egy VALÓDI gateway-nél árva provider-request maradhatna (az R15 „no-orphan" invariáns osztálya). **Ma nincs valódi kockázat** (R16 fake-only, nincs bekötött valódi gateway; a `dispose()` felszabadít). | A `failed` átmenet (vagy az `_apply` `TutorPipelineFailed` ága) kapjon subscription+gateway cancel-t, ahogy a többi terminál. **Follow-up: R18 (valódi gateway bekötése) ELŐTT kötelező** — a brief előfeltétele lesz. |
| 2 | NOTE | `tutor_output_validator.dart:54-68` | A `_groundedClaimTypes` és `_actionTypes` string-konstansok a modell output-schema stringjei (nem a domain enumok) — ha a `TutorOutputSchema` bővül, kézi szinkron kell. Ma konzisztens. | Egy jövőbeli körben a schema-forrásból származtatható. |

**Egyik lelet sem BLOCKER/MAJOR** → a merge-bar (nulla nyitott BLOCKER/MAJOR) teljesül.
A MINOR internal defenzív úton van, valódi kockázat nélkül ma, `dispose()`-zal
mitigálva; follow-upként rögzítve (nem hizlaljuk a diffet egy fake-only út
kedvéért — review-skill: „MINOR … különben follow-up").

## 7. Architektúra + termékhatárok

- **Provider-boundary (ADR 0131):** nincs provider-SDK import; a gateway-t
  interfészen át hívja. ✓
- **Grounding (ADR 0132/0174):** repair-cap 1 → deterministic fallback; nincs
  korlátlan loop. ✓
- **`public.dart` contract:** érintetlen, üres. ✓
- **Lifecycle:** `dispose()` minden erőforrást lezár; a `failed`-úti hézag a
  MINOR-1 (follow-up). A többi terminál minden útvonalon cancel-t emit. ✓
- **Pure reducer:** `reduceTutorTurn` mellékhatás-mentes; az effektek egyszeriek,
  request-id-korreláltak (`_apply` guard: `_state.requestId != effect.requestId`
  → drop). ✓

## 8. Zöld kapu (ADR 0052) — a merge feltétele

format + analyze + architecture + teljes CI-suite + randomizált property **mind
zöld** a `069f4e6` merge-SHA-n (full-gate.yml), **ÉS** a Router CI `success`
ugyanazon a SHA-n. Exact-SHA ellenőrzés a merge előtt. Bármi piros → merge tilos.
