# Review — E04-R12: Prompt templatek, output schema és injection boundary

- **Kör:** E04-R12
- **Branch:** `codex/e04-r12-prompts-output-schema-injection-boundary`
- **Implementer motor:** Codex (Terra, örökölt kézi override, `codex-round.sh`)
- **Reviewer:** Claude Opus 4.8 (orchestrátor, független read-only)
- **Diff:** `862dc43..9eaccce` (16 changed path, +969/-1)
- **Verdikt:** **APPROVED** — 0 BLOCKER, 0 MAJOR, 0 MINOR, 2 NOTE
- **ADR:** [0140](../adr/0140-ai-tutor-prompt-output-schema-injection-boundary.md) (pre-flight)

## 1. Jelzés + handoff

`.codex-round-status`: `status=done`, `head=9eaccce`, `dirty_files=1`. A dirty fájl
a **gitignore-olt** `.codex-round-status` maga (`git check-ignore` megerősítve);
a `git status --short` tiszta. Nem fogadtam el bemondásra: a gate-et magam futtattam.

## 2. Gate-újrafuttatás (izolált `/tmp/review-e04-r12` klón)

`tools/round-gate.sh test/features/ai_tutor/prompts` — **minden lépés ZÖLD**:
format · analyze (No issues) · test · architecture · secrets (1625 fájl, 0 finding) ·
l10n (en→hu 720 üzenet). A teljes suite + property + APK a CI-ban (ADR 0053).

## 3. Scope-audit

`tools/scope-audit.py --base 862dc43`: **OK, 16 path, 0 generated/ignored, mind az
`allowed_paths`-on belül.** A codex-round.sh gépi auditja is lefutott. Diff:
6 asset (`assets/tutor_prompts/*.json`), 4 lib (`application/prompts/*.dart`),
`public.dart` (additív export), `pubspec.yaml` (additív asset), 3 teszt, brief §10.

## 4. Acceptance criteria — tételes bizonyíték

| Kritérium | Bizonyíték |
|---|---|
| Layer-order | `tutor_prompt_builder_test.dart` `orderedEquals` a 10 szakaszra (PRODUCT→SAFETY→PEDAGOGY→TOOL→CONTEXT→TRUSTED→UNTRUSTED×3→OUTPUT) |
| Explicit response-locale | system-template `locale=='en'` kényszerítve; `Response locale: hu-HU.` a promptban tesztelt |
| Redaction (no-secret/no-raw-audio) | builder-teszt: `accessToken`/`pcmSamples` az R05 assembleren át redaktálva → `should-never-leave-device` és `[0,1,-1]` NINCS a promptban; untrusted regex-redakció külön tesztelt (`[REDACTED_UNTRUSTED_CONTENT]`) |
| Tool-allowlist (mérési szabály #2) | „uses the registry turn-policy intersection without a builder allowlist" — `notAllowed` (computeLocal) kiesik a `schemasForTurn(policy)` metszésen; a builder NEM vezet be saját allowlistet |
| Untrusted-delimiter | injection-teszt: injektált `<<<TRUSTED_KNOWLEDGE>>>` pontosan 1×; `<`/`>` escape megakadályozza a szakaszkitörést |
| No chain-of-thought | `step-by-step`/`chain-of-thought`/`reasoning` NINCS az outputban/sémában |
| schema-version | v1 stamp (`promptVersion`, `templateVersion`, `outputSchemaVersion`, `toolRegistryVersion`) tesztelt |
| Deterministic snapshot / intent | `prompt_snapshot_test.dart` bit-stabil full-text fixture mind a 6 `ContextPurpose`-ra |

## 5. Próbatesztek (eldobható, merge előtt törölve)

**Injection-védelem valódi-sértés próba** (a klónban): a
`_redactAndEscapeUntrusted` `<`/`>` escape-jét eltávolítva az injection-teszt
**PIROSRA váltott** (`Expected: <1>  Actual: <2>` — az injektált delimiter kétszer
jelent meg, azaz szakaszkitörés). Visszaállítás után zöld. → a delimiter-forgery
védelem **ténylegesen mért**, nem díszlet. A klón törölve.

## 6. Architektúra + termékhatárok

- **Redacted-only boundary (ADR 0132):** a builder `TutorContextSnapshot`-ot fogad
  (nem nyers forrás-típust); a `_redactedSnapshot()` teszt bizonyítja, hogy a
  secret/PCM már az assembleren redaktálódik. ✔
- **Allowlist-tulajdonlás (ADR 0140 D4):** `TutorToolRegistry.schemasForTurn` birtokolja. ✔
- **Nincs cloud/gateway, nincs UI, nincs CoT** (ADR 0140 D5/D6). ✔
- **`public.dart`:** csak a prompt-réteg additív exportja; nincs más feature belső import. ✔
- **Trusted template guard:** `PromptTemplate` elutasít `<<<`/`>>>`-t tartalmazó
  templatet és a nem-`en` locale-t. ✔

## 7. Leletek

| # | Osztály | Fájl:sor | Leírás |
|---|---|---|---|
| N1 | NOTE | `tutor_prompt_builder.dart:212` | Az untrusted-redakció regex `token`-je tág (over-redaction) — a védelem irányában biztonságos, nem blokkol. |
| N2 | NOTE | `tutor_output_schema.dart` | A v1 séma az array-elemek belső alakját még nem rögzíti (csak `type:array`) — R13+ finomíthatja, ebben a körben nem elvárt. |

**Nincs nyitott BLOCKER/MAJOR/MINOR. Merge engedélyezett** exact-SHA zöld CI
(build-apk + router-ci `success` a `9eaccce` head-en) és a merge-SHA router-ci
sikere után.
