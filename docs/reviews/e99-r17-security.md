# E99-R17 — Security review

Reviewer: security-reviewer, isolated clone · Dátum: 2026-08-19  
Diff: `f00e872f..cfceee26`  
Verdikt: PASS WITH MINOR

## Eredmény

- CRITICAL/BLOCKER: 0
- Command injection, hálózati kijutás, secret-kitettség és JSON/path traversal:
  nem talált.
- Az angol és magyar aggregátum JSON-mapje a migráció előtti tartalommal
  halmazszinten egyezik.

## F1 — MINOR — cross-fragment metadata ownership

Ugyanaz a lelet, mint a független review F1-e:
`tool/gen_l10n_segments.dart:96` a korábbi fragmentum üzenetéhez egy későbbi
fragmentum `@key` metaadatát elfogadja. A javításnak szegmens-lokális
metaadat-ownershipet és regressziós tesztet kell adnia.

## Ellenőrzött bizonyítékok

- `dart run tool/gen_l10n_segments.dart --check` — zöld.
- célzott Flutter-tesztek — 18 passed.
- `python3 -m pytest tools/tests/test_round_slots_generated_paths.py -q` — 6 passed.
- scope-audit a dokumentált `f00e872f` bázistól — OK (11 engedélyezett út).

Megjegyzés: `a113cfc7`-től a scope-audit a D2 védett gate-fájlját jelölné; ez
a pre-flight előtt, külön emberi engedéllyel került a körágra, nem a jelen
implementáció scope-sértése.
