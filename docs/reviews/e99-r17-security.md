# E99-R17 — Security review

Reviewer: security-reviewer, isolated clone · Dátum: 2026-08-20
Diff: `5ca4aee5` (F1 re-review)
Verdikt: PASS WITH NOTE

## Eredmény

- CRITICAL/BLOCKER/MAJOR: 0
- Az F1 javítás a cross-fragment `@key` metaadatot explicit hibára váltja,
  és a generált aggregátumot nem engedi létrejönni.
- Nem került be subprocess-/shell-hívás, interpolált parancs, új fájlút-építés
  vagy hálózati hozzáférés; command injection, path traversal és secret-kitettség
  nem azonosítható.

## F1 — FIXED — cross-fragment metadata ownership

- **Fájl:** `tool/gen_l10n_segments.dart:100-120`
- **Javítás:** a `seenFrom[messageKey]` tulajdonosának és az aktuális
  `Segment.label`-nek egyeznie kell; eltéréskor a merge hibával, aggregátum
  nélkül tér vissza.
- **Ellenőrzés:** `test/tooling/gen_l10n_segments_test.dart:121-203` két
  regressziós esete; `flutter test test/tooling/gen_l10n_segments_test.dart`
  — 11 passed.

## NOTE — címkeazonosság szintetikus hívóknál

Az ownership `Segment.label` sztringet hasonlít, ezért két külön, azonos címkéjű
szintetikus `Segment` megkerülhetné a guardot. A támogatott production útvonal
(`generateLocale` → `loadSegment`) teljes fájlút-címkéket ad, ezek egyediek;
security-hatás nincs. Ha a `mergeSegments` publikus, általános célú API-vá válna,
path/object identity alapú tulajdonlás külön hardeningként megfontolandó.
