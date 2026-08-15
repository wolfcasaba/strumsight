# E07-R04 — Review

Brief: `docs/rounds/e07-r04-generation-request-and-draft-persistence.md`  
Diff: `2d65f862..d6c5430a`  
Reviewer: Codex (orchestrator fallback) · Dátum: 2026-08-15  
Verdikt: CHANGES REQUIRED

## Összegzés

BLOCKER: 0 · MAJOR: 1 · MINOR: 0 · NOTE: 0

## Acceptance criteria

| # | Kritérium | Teljesült | Bizonyíték |
|---|---|---|---|
| A1–A5 | Request round-trip, stabil seed/hash, kulcssorrend, schema-migráció és future-version elutasítás | ✅ | `generation_request_serializer_test.dart`, 9/9 zöld |
| A6 | Sérült/séma-sértő draft kontrollált hiba | ❌ | F1: hibás beágyazott mező csendes adatvesztést okoz |
| A7–A8 | Külön draft-kulcs, aktív terv izolációja, idempotens törlés | ✅ | `generation_draft_repository_test.dart`, 8/8 zöld |
| A9 | Nincs tiltott domain-függőség | ✅ | implementer grep, diff-audit |

## Scope-audit

`python3 tools/scope-audit.py --repo /tmp/review-e07-r04 --brief docs/rounds/e07-r04-generation-request-and-draft-persistence.md --base 2d65f862` → `OK`, 7 changed path, 0 generated/ignored. Engedélyezett fájlokon kívüli implementer-változás nincs.

## Megállapítások

### F1 — MAJOR — A részlegesen sérült draft csendben adatot veszít

- **Fájl:** `lib/features/practice_generator/data/local/generation_request_serializer.dart:303-321`
- **Probléma:** A `goal.targetDate` nem-string értéke `null`-lá válik ahelyett, hogy `GenerationRequestSerializerException` keletkezne. Ugyanez a minta a többi opcionális, strukturált mezőnél is részben alkalmazott.
- **Hatás:** Egy megmaradt, de sérült wizard-draft sikeresnek látszik, miközben a felhasználó céldátuma eltűnik. Ez sérti az ADR 0259 §4 és a brief A6 szabályát: a séma-sértő draft kontrollált `AppResult.failure`, nem best-effort adatvesztés.
- **Bizonyíték:** Eldobható review-proba a serializer tesztjében `targetDate = 42` mellett `GenerationRequestSerializerException`-t várt; a tényleges hívás `PracticeGenerationRequest`-tel tért vissza. A teszt szándékosan PIROS volt, utána el lett távolítva a `/tmp` review-klónból.
- **Kötelező javítás:** A dekóder minden opcionális mezőn különböztesse meg a hiányzó `null`-t a hibás típustól; hibás típus vagy hibás beágyazott alak esetén stabil `GenerationRequestSerializerException`-t adjon. A draft repository ezt változatlanul `StorageFailure`-ré képezze le.
- **Ellenőrzés:** Tartós teszt: `targetDate = 42` → serializer controlled exception; az ugyanez a mentett draftra → `Failure(StorageFailure)`. A célzott gate-et futtasd újra.
- **Státusz:** OPEN

## Gate-bizonyíték ellenőrzése

| Gate | Állított eredmény | Ellenőrizve |
|---|---|---|
| format | zöld | ✅ izolált klón gate |
| analyze | zöld | ✅ izolált klón gate, `No issues found` |
| célzott tesztek | 17/17 zöld | ✅ serializer 9/9, repository 8/8 az izolált klónban |
| architektúra/secrets/l10n | zöld | ✅ izolált klón teljes gate-folyamata |
| CI (teljes suite + property + APK) | még nincs dispatch | ❌ a review-lelet miatt helyesen nincs merge-evidencia |

## Merge-döntés

Az ADR 0052 szerint a nyitott F1 MAJOR miatt a merge tiltott. A következő lépés ugyanazon `sonnet-impl` motor javító köre, kizárólag F1 lezárására.
