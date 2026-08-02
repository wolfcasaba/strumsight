# E03-R08/H4 — Review

Heal branch: `heal/E03-R08-H4-1`  
Diff: `git diff origin/main...heal/E03-R08-H4-1`  
Reviewer: Codex / GPT-5.6 Terra (orchestrator-fallback; isolated clone)  
Date: 2026-08-02  
Verdict: APPROVED — CI evidence pending

## Összegzés

BLOCKER: 0 · MAJOR: 0 · MINOR: 0 · NOTE: 0

## Acceptance criteria

| # | Kritérium | Teljesült | Bizonyíték |
|---|---|---|---|
| 1 | A teljes SongDocument struktúra read-back után megmarad | ✅ | `song_document_codec_test.dart` „preserves the complete structural timeline” |
| 2 | A H4 tényleges legacy-adapter kimenete value-equal marad | ✅ | `song_document_codec_test.dart` „H4 regression: preserves the measured legacy migration document” |
| 3 | Hibás jelen lévő strukturális JSON nem némán normalizálódik | ✅ | `song_document_codec_test.dart` „decode rejects a malformed present structural field” |
| 4 | Régi, strukturális mező nélküli dokumentumok olvashatók | ✅ | A decoder csak hiányzó kulcsnál használja a korábbi üres/konstans defaultot; minden új írás explicit mezőket tartalmaz. |

## Scope-audit

Az izolált `/tmp/review-e03-r08-h4` klónban a diff öt fájlt érintett:
codec, codec-teszt, ADR 0090 jelölt módosítási blokk, LESSONS és HANDOFF.
Nincs scope-on kívüli production változás, teszt-törlés vagy gate-gyengítés.

## Próbatesztek

Az izolált klónban ideiglenesen eltávolítottam a codec `sections`, `measures`,
`tempoMap`, `meterMap` és `keyMap` encoder-kulcsait. A célteszt RED lett:

- `preserves the complete structural timeline`
- `H4 regression: preserves the measured legacy migration document`

A patch visszaállítása után a fájl ismét GREEN volt (14 teszt), a review-klón
`git diff --exit-code` ellenőrzése tiszta.

## Gate-bizonyíték ellenőrzése

| Gate | Ellenőrizve |
|---|---|
| format | ✅ — izolált clone gate |
| analyze | ✅ — izolált clone gate, `flutter gen-l10n` után |
| célzott tesztek | ✅ — `data/local` és `data/migration` sávok |
| architecture | ✅ — izolált clone gate |
| CI (teljes suite + property + APK) | ⏳ — PR/dispatch után kötelező |

## Merge-döntés

Nincs nyitott BLOCKER vagy MAJOR. Az ADR 0052 szerinti squash-merge csak az
exact-head SHA-hoz tartozó teljes CI-suite, property gate és APK-build zöld
eredménye után megengedett.
