# E99-R17 — Review

Brief: `docs/rounds/e99-r17-gov-11-l10n-parallel-safety.md`  
Diff: `f00e872f..cfceee26`  
Reviewer: Codex (Terra), isolated clone · Dátum: 2026-08-19  
Verdikt: CHANGES REQUESTED

## Összegzés

BLOCKER: 0 · MAJOR: 0 · MINOR: 1 · NOTE: 0

## Acceptance criteria

| # | Kritérium | Teljesült | Bizonyíték |
|---|---|---|---|
| 1 | D1–D4, tuner pilot és generált aggregátum | ✅ | `tool/gen_l10n_segments.dart`; `lib/l10n/{base,features}/`; `dart run tool/gen_l10n_segments.dart --check` zöld |
| 2 | A §4 hat mérce-cellája tesztelt | ✅ | 18 célzott Flutter-teszt + 6 slot-teszt; D4 őr kiszedésekor 4/6 teszt pirosra váltott |
| 3 | Kör-gate zöld | ✅ | izolált `/tmp/review-e99-r17.lAc61A`: a 7 lépéses `tools/round-gate.sh …` teljesen zöld |
| 4 | `python3 -m pytest tools/tests -q` zöld | ✅ | 591 passed, 1 skipped, 567 subtests passed |

## Scope-audit

`python3 tools/scope-audit.py --repo /tmp/review-e99-r17.lAc61A --brief … --base f00e872f`:
`OK` — 11 megváltozott, engedélyezett út; 0 generated/ignored.

## Megállapítások

### F1 — MINOR — Fragmentumok közötti metaadat-hozzárendelés

- **Fájl:** `tool/gen_l10n_segments.dart:96`
- **Probléma:** egy későbbi fragmentum `@foo` metaadata elfogadható, ha a
  `foo` üzenetet egy korábbi fragmentum adta; ezzel a feature-fragmentum
  megváltoztathatja más szegmens codegen-metaadatát.
- **Hatás:** localization codegen-szemantika megváltozhat duplikált üzenetkulcs
  hiba nélkül.
- **Kötelező javítás:** a metaadatot csak ugyanabban a `Segment`-ben levő
  üzenethez engedd, és adj elutasító regressziós tesztet.
- **Ellenőrzés:** célzott Flutter-teszt egy cross-fragment `@foo` esetre.
- **Státusz:** OPEN

## Gate-bizonyíték ellenőrzése

| Gate | Ellenőrizve |
|---|---|
| format / analyze / célzott Flutter-tesztek / architecture / secrets / l10n | ✅ izolált round-gate |
| teljes tools pytest | ✅ 591 passed, 1 skipped |
| CI (teljes suite + property) | ⏳ Full Gate `32314498894`, exact `cfceee26` (javítás után újraindítandó) |

## Merge-döntés

Nincs nyitott BLOCKER vagy MAJOR, de F1 kis diffű, a kör scope-ján belüli
integritási javítás; javító implementáció és újra-review következik.
