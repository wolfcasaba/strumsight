# E03-R14 — Review

Brief: `docs/rounds/e03-r14-guitar-pro-path.md`
Diff: `git diff origin/main...codex/e03-r14-guitar-pro-path`
Reviewer: Terra fallback, isolated clone · Dátum: 2026-08-03
Verdikt: APPROVED

## Összegzés

BLOCKER: 0 · MAJOR: 0 · MINOR: 0 · NOTE: 0

Az ADR 0122 szerinti C út marad az egyetlen aktív út: nincs GP parser,
dependency, registrybeli támogatott extension vagy hálózati konverzió. A
korábbi F1 MAJOR javítása csak az exact GP-extensionre és a `FICHIER GUITAR
PRO` headerre korlátozza a dedikált választ; egy támogatott, `Guitar Pro`
szöveget tartalmazó MusicXML-fájlnév ismét eljut a content importerhez.

## Acceptance criteria

| # | Kritérium | Teljesült | Bizonyíték |
|---|---|---|---|
| 1 | ADR 0122 C út, félkész GP támogatás nélkül | ✅ | `importer_registry.dart:16-25, :72-76`; nincs parser/dependency diff |
| 2 | GP input stable unsupported, 0 importer-probe/commit; support-lista négyes | ✅ | `guitar_pro_unsupported_test.dart` 6/6; `song_trainer_providers.dart` provider-lista változatlan |
| 3 | Guidance HU/EN, screen-readerrel használható és offline | ✅ | `guitar_pro_conversion_guidance_test.dart` 2/2; ARB-k :817-822, illetve :751-756 |
| 4 | User guide nem automatizál vagy linkel konvertert, fidelityt sem ígér | ✅ | `docs/user-guide/guitar-pro-conversion.md:1-16` |
| 5 | A/B parser/dependency/fixture nem került a diffbe | ✅ | scope-audit, 9 implementációs/pre-flight útvonal; csak a jelen review-artifact plusz |

## Scope-audit

Az engedélyezett fájlokon kívüli változás nincs. A `review`-fájl a brief §0.0,
§4 és `ai-router.allowed_paths` explicit, reviewer-only kivétele; ezt a
merge-előtti H3-heal metadata-regressziója is védi.

## Megállapítások

### F1 — MAJOR — filename-substring false positive blocks supported imports

- **Fájl:** `lib/features/song_trainer/data/importers/importer_registry.dart:143-147`
- **Probléma:** a korábbi változat a `guitar pro`/`guitar-pro` névrészletet is
  GP-fájlnak vette, ezért egy érvényes MusicXML/MXL/MIDI fájl nem jutott el a
  content importerhez.
- **Ellenőrzés:** a review isolated-clone próbája ezt mutatta; a javítás után
  `a supported source whose display name contains Guitar Pro reaches an importer`
  zöld, míg a GP extension/header 0-probe cellák változatlanul zöldek.
- **Státusz:** FIXED (`728d0d0`).

Nincs nyitott BLOCKER vagy MAJOR.

## Gate-bizonyíték ellenőrzése

| Gate | Állított eredmény | Ellenőrizve |
|---|---|---|
| format/analyze/célzott test/architecture | `tools/round-gate.sh` az izolált clone-ban zöld | ✅ (format 745 fájl, analyze: No issues found) |
| célzott tesztek | 8/8 zöld | ✅ saját futás, izolált clone |
| valódi-sértés próba | GP-extension guard ideiglenes kiiktatása 1/6 teszttel piros, majd visszaállítva | ✅ izolált clone |
| diff-integritás | `git diff --check reviewer/main...HEAD` zöld | ✅ |
| CI (teljes suite + property + APK) | exact head dispatch szükséges | függőben |

## Merge-döntés

Az ADR 0052 szerint a review APPROVED, de merge csak az exact branch-headre
futott zöld teljes CI-suite, randomizált property gate és APK után engedett.
