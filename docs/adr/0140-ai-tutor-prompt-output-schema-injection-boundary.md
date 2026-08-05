# ADR 0140 — AI Tutor prompt-építés, output-schema és injection boundary

- **Státusz:** Elfogadva (E04-R12 pre-flight, 2026-08-05)
- **Kör:** E04-R12 — Prompt templatek, output schema és injection boundary
- **Implementer motor:** Codex (`gpt-5.6-terra`, örökölt kézi override, `codex-round.sh`)
- **Epic:** [Chapter 5 — Epic 4: AI Guitar Teacher](../sdd/05-epic-04-ai-guitar-teacher.md) Kör 12; §35
- **Szülő/kontext-ADR-ek:** [0131](0131-ai-tutor-provider-boundary.md) (provider boundary),
  [0132](0132-ai-tutor-privacy-and-consent.md) (privacy/consent, redakció),
  [0137](0137-ai-tutor-readonly-tool-contract.md) (read-only tool contract),
  [0139](0139-ai-tutor-action-proposal-confirmation.md) (action confirm)

## Kontextus

Az AI Tutor eddigi körei megépítették a **prompt-bemeneteket**, de még nincs
prompt-réteg, ami ezekből determinisztikus, verziózott modell-inputot állít:

- **R05** a redaktált kontextust (`TutorContextSnapshot`,
  `lib/features/ai_tutor/application/context/tutor_context_snapshot.dart`) adja —
  section-onként redaktált, `RedactionReport`-tal, nyers audio/token/secret nélkül.
- **R07** a trusted-tudás forrás-referenciáját (`TutorSourceRef`,
  `lib/features/ai_tutor/domain/models/tutor_source_ref.dart`; `chunkId`,
  `chunkHash`, `knowledgeVersion`) adja.
- **R10** a read-only tool-szerződést (`TutorToolSchema.toJson()` →
  `{name, input:{type,properties,required,additionalProperties}}`) és az
  allowlistet (`TutorToolRegistry.schemasForTurn(TutorToolTurnPolicy)`, ami már
  ma is CSAK a `policy.allowedToolNames ∩ policy.allowedPermissions` metszetre ad
  sémát) adja.

Ezek külön-külön redaktáltak/allowlistelt-ek, de a promptba fűzésük ma
strukturálatlan volna. A fő kockázat: **prompt injection** — importált vagy
felhasználói (untrusted) tartalom a trusted knowledge/utasítás szakaszba
szivárogva tool-permissiont emelhetne vagy felülírhatná a rendszer-utasítást.

## Döntés

1. **Verziózott, determinisztikus prompt-építés.** Minden prompt-build explicit
   `PromptVersion`-t stampel; azonos bemenetre bit-azonos szöveg (snapshot-gate).
2. **Trusted és untrusted tartalom fizikailag külön szakasz, egyértelmű
   delimiterekkel.** A trusted szakasz: system-utasítás (angol) + `TutorSourceRef`
   citációk. Az untrusted szakasz: felhasználói üzenet és importált tartalom.
   **Untrusted tartalom trusted szakaszba olvasztása nem elfogadható** — ez az
   elsődleges injection-vektor, delimiter-teszttel és adversarial fixture-rel mérve.
3. **A builder KIZÁRÓLAG redaktált kontextust fogad.** A bemenet a
   `TutorContextSnapshot` (R05); nyers audio/token/secret/PII soha nem érhet a
   promptba (ADR 0132 megerősítése). Nyers context átadása fordítási/típus-szinten
   kizárt (a builder nem fogad nyers forrás-típust).
4. **Tool-schema injection csak az engedélyezett toolokra — az allowlistet a
   registry birtokolja, nem a builder.** A builder a
   `TutorToolRegistry.schemasForTurn(policy)` kimenetét fűzi be (R10 mérve: az
   allowlist-metszés ott történik); a builder nem vezet be saját, párhuzamos
   allowlistet. Adversarial input NEM emelhet tool-permissiont.
5. **Nincs chain-of-thought kérés; az output strukturált schema v1.** A modell
   válasza a `tutor_output_schema.dart` v1 szerinti strukturált forma; a prompt
   nem kér belső gondolatmenet-kifejtést.
6. **Nincs gateway/cloud hívás ebben a körben.** A prompt-réteg tiszta,
   provider-független szöveg- és séma-építés (ADR 0131); a tényleges modellhívás
   R13+.

## Következmények

- A diff a `lib/features/ai_tutor/application/prompts/` alatt épül + `assets/tutor_prompts/`
  intentenkénti template-ek + `pubspec.yaml` additív asset-bejegyzés + a
  `test/features/ai_tutor/prompts/` snapshot/injection/trusted-untrusted tesztek.
- A snapshot-gate a **szerkezeti** szerződést rögzíti; az injection-fixture a
  **viselkedést**. A reviewer eldobható mutációval (delimiter elhagyása,
  untrusted→trusted olvasztás, nem engedélyezett tool sémája) pirosra váltja —
  a döntés nem lazítható azért, hogy egy teszt zöld legyen.
- A prompt-réteg nem importál más feature belső contractot; a bemenetek az
  R05/R07/R10 public felületei (ADR 0131 boundary).
