# Kör-review — E04-R04 (Skill taxonomy, evidence & reducer)

- **Branch:** `codex/e04-r04-skill-taxonomy-evidence-reducer`
- **Implementer commit:** `5a657a7` (`feat(ai-tutor-domain): add skill taxonomy evidence and reducer`)
- **Pre-flight commit:** `b472fab` (§0.0 baseline, allowlist-szűkítés)
- **Implementer motor:** Codex (`gpt-5.6-terra`, örökölt kézi override)
- **Reviewer:** Claude Opus 4.8 — független, read-only, izolált `/tmp/review-e04-r04` klón
- **Baseline:** `origin/main @ 3dc7f5a`
- **Verdikt:** **APPROVED** — 0 BLOCKER, 0 MAJOR, 0 MINOR, 1 NOTE

## 1. Jelzés + handoff

`.codex-round-status`: `status=done`, `head=5a657a7`, gate zöld, coverage 98.68%.
`dirty_files=1` a jelzés pillanatában — kivizsgálva: a round-status fájl saját
írása; a working tree a commit után **tiszta** (`git status --short` üres). A brief
§10 handoff kitöltve, a §0.0 érintetlen.

## 2. Gate-újrafuttatás (saját kézzel, izolált klón)

`tools/round-gate.sh test/features/ai_tutor/domain` a `/tmp/review-e04-r04`
klónban — **MINDEN GATE ZÖLD**:

- format: zöld (889 fájl, 0 változás)
- analyze: `No issues found!`
- test: **75 passed**
- architecture: `Architecture dependencies OK (12 allowlisted deviation(s)).`

## 3. Scope-audit

`git diff --stat origin/main...HEAD` — 7 fájl, mind a §0.0 utáni engedélyezett
listán: 4 domain fájl + 2 tesztfájl + a brief (§10 handoff). **`public.dart` és a
lezárt E04-R01 `ai_tutor_boundary_test.dart` érintetlen** (a §0.0 REVÍZIÓ 1
szűkítés helyesen tartva). Listán kívüli fájl: nincs.

## 4. Acceptance criteria — tételes bizonyíték

| Kritérium | Bizonyíték | Verdikt |
|---|---|---|
| Determinizmus (shuffle → azonos becslés; stable tie-break literálisan) | Committolt seedelt shuffle-teszt (4 seed, equality+hashCode) + literál `stableGroupTieBreak` konstans. **Reviewer-próba:** 200 permutáció **egyenlő group-timestamppel** → bit-azonos output (trend=declining, score=4500, ids=[c,d,a,b]); a súlyozott átlag kézzel ellenőrizve (gA=5000, gB=4000, mean=4500). | ✅ |
| Trend csak ≥2 groupból; 0/1/2 mátrix | `comparable-group matrix` group: 0→insufficient/conf 0, 1→insufficient/conf 2000, 2→trend/score 6000/improving/conf 4000; declining+stable megkülönböztetve. | ✅ |
| Verzió nélküli evidence fail-loud | `SkillEvidence` ctor `_requiredVersion` null→`schemaVersionMissing`, <1→`…OutOfRange`; stabil kódú teszt. | ✅ |
| Domain purity zöld; ≥90% coverage | Kör-lokális `group('Domain purity')` scanner zöld. **Reviewer-próba:** `import 'package:flutter/material.dart'` injektálva a `skill_node.dart`-ba → purity-teszt **RED** (`+7 -1 [E]`, „ai_tutor domain purity violations"), visszaállítva. Coverage 300/304 = **98.68%**. | ✅ |

### Súlyozott-átlag reference (pinned 6857) — független ellenőrzés
session-1 = (8000·10000 + 0·4000) / 14000 = 5714; session-2 = 8000;
trend-score = (5714 + 8000) / 2 = **6857**. Egyezik a committolt teszttel. ✅

## 5. Real-violation próbák (eldobható, futtatva + törölve)

1. **Group tie-break mutáns** (`_compareGroups` id-tie-break elhagyva) → 18/18
   PASS. **Nem** red — mert az upstream `_deduplicate` determinisztikus rendezés
   önmagában is fedi.
2. **Dedup-sort mutáns** (`_deduplicate` rendezés elhagyva) → 18/18 PASS — mert a
   downstream group/partition/within-group rendezés + a tie-break önmagában fedi
   (a shuffle-teszt adatai amúgy is disztinkt timestampűek).
3. **200-permutációs egyenlő-timestamp próba** (reviewer által írt) → bit-azonos.
   A determinizmus tehát **két független mechanizmusból** (defense-in-depth) fakad.
4. **Purity real-violation** (forbidden import) → RED, ahogy fent.

## 6. Architektúra + termékhatárok

- Domain tiszta: nincs Flutter/riverpod/dio/storage import, nincs `DateTime.now()`
  / `Random(` / `Stopwatch(` / `print(` a `lib/`-ben (az idő paraméter, a scale/
  weight egész-konstans). Purity-scanner igazolja.
- Reducer **pure**: nincs I/O, óra, véletlen, lebegőpont; belül egész-aritmetika,
  `~/` osztás. `_weightedScore` osztója sosem 0 (a `SkillEvidenceSource` zárt enum
  minden ágának súlya pozitív konstans: 10000/4000/2000).
- Value-egyenlőség stabil (`observedAt.microsecondsSinceEpoch`, `Object.hash`),
  listák `unmodifiable`. `SkillEstimate._validate` a státusz-invariánsokat
  kényszeríti (insufficient⇒≤1 group/score null/trend null; trend⇒≥2/score+trend).
- `public.dart` üres marad — a provider-boundary (ADR 0131) és a lezárt boundary-
  invariáns sértetlen. Nincs UI/cloud/plugin/source-belső import.

## 7. Leletek

| Azon. | Osztály | Fájl:sor | Leírás |
|---|---|---|---|
| N-1 | NOTE | `skill_evidence_reducer.dart:199` / `:127` | A group-tie-break és az upstream dedup-rendezés redundáns (defense-in-depth). Egyik sem *izoláltan* tesztelt: mindkét egyszeres mutáns zöld maradt. A determinizmus **valósan teljesül** (200-perm reviewer-próba), ezért ez kizárólag teszt-izolációs megjegyzés — **nem blokkol**, nem hizlalandó a diff a körben. Opcionális follow-up: egyenlő-timestamp tie-break eset a committolt tesztsorba. |

## 8. Merge-döntés

Zöld gate (izolált klón) + tiszta scope + minden acceptance bizonyítva + 0
BLOCKER/MAJOR/MINOR ⇒ **APPROVED**. Merge feltétele az ADR 0052 zöld kapu:
exact-SHA (`5a657a7`) `build-apk.yml` siker a kör-branchen, és mozdulatlan
`origin/main` (dispatch-kori `3dc7f5a`).
