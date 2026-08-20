# E08-R10 — Review

Brief: `docs/rounds/e08-r10-streak-v2-domain-and-legacy-migration.md`  
Implementer diff: `a2d5239e..f2e368b3`  
Round HEAD reviewed: `dd50edba`  
Reviewer: Codex (GPT-5.6 Sol) · Dátum: 2026-08-20  
Verdikt: **APPROVED**

## Összegzés

BLOCKER: 0 · MAJOR: 0 · MINOR: 0 · NOTE: 0

Az implementáció a legacy streak öt mezőjét veszteség nélkül fordítja a V2
domainre, a teljes shipping átmeneti logikát reprodukálja, és mindkét legacy
forrást kizárólag olvassa. Production kódot a review nem módosított.

## Acceptance criteria

| # | Kritérium | Teljesült | Bizonyíték |
|---|---|---|---|
| A1 | Az öt legacy érték változatlan | ✅ | `streak_policy_test.dart` mezőnkénti cella; reviewer parity-próba több mint 4 000 állapotkombinációval |
| A2 | Kétszeri migráció idempotens mindkét forrásból | ✅ | idempotencia- és envelope/raw-ekvivalencia cellák |
| A3 | Mindkét forrás érintetlen, write-log üres | ✅ | byte-azonos source assertion + `writeLog isEmpty`; a migrátorban nincs write/remove hívás |
| A4 | A teljes legacy átmeneti mátrix megmarad | ✅ | 4 policy-cella + reviewer legacy↔V2 paritáspróba |
| A5 | Tiszta, óra- és IO-mentes policy | ✅ | forrásőr, import-audit és architecture gate |
| A6 | Minden átmenet reason code-ot ad | ✅ | első nap, azonos nap, clock-skew, gap 1, freeze és reset cellák |
| A7 | A legacy streak suite változatlanul zöld | ✅ | független gate: 20/20 teszt |
| A8 | `lib/features/streak/**` érintetlen | ✅ | implementer scope-audit és diff |
| A9 | Ismeretlen raw mező ignorált; envelope/raw azonos | ✅ | két állandó migrációs cella |
| A10 | Az ötmezős legacy projekció feature-import nélkül készül | ✅ | projekciós assertion + architecture gate |

## Scope-audit

```text
python3 tools/scope-audit.py --repo <izolált klón> \
  --brief docs/rounds/e08-r10-streak-v2-domain-and-legacy-migration.md \
  --base a2d5239e
→ Legacy scope audit OK (a2d5239e..f2e368b3, 7 changed path(s), 0 generated/ignored)
```

Az upstream-szinkron `dd50edba` csak az aktuális `origin/main` közös
dokumentumait hozta be. Az ADR 0351 és a §0.0 brief-revízió orchestrátor-owned
pre-flight artefaktum; az implementer engedélyezett fájljain kívüli változás
nincs.

## Független próbák

- Eldobható parity-teszt: a legacy `StreakLogic.applyPractice` és a V2
  `StreakPolicy.applyQualifiedDay` `current/longest/last/freezes/total`
  kimenete több mint 4 000 kombinációban mezőazonos; 1/1 teszt zöld.
- Kötelező valódi-sértés próba: a `gap == 2 && freezes > 0` ág ideiglenes
  hatástalanítása után az A4 cella piros lett (`Expected: 5`, `Actual: 1`,
  exit 1). A mutáció visszaállítva; a reviewer klón utána tiszta.

## Gate-bizonyíték

Izolált `/tmp` klón, HEAD `dd50edba`:

| Gate | Eredmény |
|---|---|
| format | 1720 fájl, 0 változott |
| analyze | 0 lelet |
| V2 streak policy teszt | 11/11 zöld |
| legacy streak suite | 20/20 zöld |
| architecture | OK, 12 allowlistelt eltérés |
| secrets | 3052 fájl, 0 lelet |
| l10n | en/hu 1405 üzenet, parity OK |
| CI | dispatch még hátravan; exact-SHA success a merge feltétele |

## Merge-döntés

Nyitott BLOCKER/MAJOR nincs; correctness és security review jóváhagyott.
Merge csak a review-commit utáni exact-SHA workflow és Router CI `success`,
valamint az aktuális `origin/main`-ősiség újramérése után engedélyezett.
