# E99-R22 — Review

Brief: `docs/rounds/e99-r22-gov-16-halt-guard-ledger.md`
Reviewed round diff: `7267fe6d8b02..05c2828d8296`
Reviewer: Codex Sol (`gpt-5.6-sol`) · Dátum: 2026-08-20
Verdikt: **APPROVED**

## Összegzés

BLOCKER: 0 · MAJOR: 0 · MINOR: 0 · NOTE: 0.

A review friss, originről klónozott `/tmp/review-e99-r22-tRUREp`
példányban futott. A review közben az `origin/main` `8687ea61` → `7267fe6d`
SHA-ra mozdult; az upstream három, fájl-diszjunkt E99-R23 pre-flight fájlját
normál `--no-ff` merge építette be. Ezután a teljes scope- és gate-review
megismétlődött egy második friss klónban
(`/tmp/review-e99-r22-sync-9dj7JA`) a kombinált `05c2828d` HEAD-en.
Production vagy implementációs fájlt a reviewer nem írt; csak eldobható
mutációkat végzett, majd bájtra visszaállította őket.

## Acceptance criteria

| # | Kritérium | Teljesült | Bizonyíték |
|---|---|---|---|
| D1 | READ-ONLY CLI Markdown/JSON kimenettel, mindig sikeres valid futás | ✅ | `tools/halt-ledger.py`; célzott 7/7 teszt; valós korpuszos smoke mindkét formátummal, exit 0 |
| D2 | Csak a legalább két előfordulású, őr nélküli osztály figyelmeztet | ✅ | `test_warning_threshold_is_one_two_and_five_occurrences`; `>= 2` → `>= 1` mutáció piros |
| D3 | Halt utáni lecke gépi őrtesztet vagy kimondott hiányt rögzít | ✅ | `docs/execution/pipeline-orchestrator-prompt.md` záró rituálé 3. pont; `test_an_explicit_no_guard_decision_counts_as_covered` |
| D4 | Mindkét új `tools/` útvonal indít Router CI-t | ✅ | `.github/workflows/router-ci.yml` meglévő `tools/**` globja; workflow-módosítás nem szükséges |
| M1 | A brief §4 hat cellája és az 1/2/5 hármas hermetikus | ✅ | `tools/tests/test_halt_ledger.py`: 7 passed; minden fixture saját temp könyvtárat használ |
| M2 | `H3` nem kap fedést `H30`-ból | ✅ | `test_a_similar_halt_code_does_not_cover_the_class`; szóhatár → részszöveg mutáció piros |
| M3 | Az élő halt-korpusz olvasható és nem módosul | ✅ | smoke: H-GATEGUARD=2, H-INDEP=4, H3=2, H8=1, H-NOSIGNAL=1; reviewer munkafa tiszta |

## Scope-audit

Wrapper-jelzés: `scope_audit=ok`, base `7f361816`, 4 implementer által
változtatott útvonal. A végső, upstream-szinkron utáni kézi audit:

```text
Legacy scope audit OK (7267fe6d8b02..05c2828d8296, 5 changed path(s), 1 generated/ignored)
```

Az implementáció mind a négy változott útvonala szerepel a brief
`allowed_paths` listáján. A review-jelentés az ADR 0138 szerinti
generated/ignored reviewer-artefaktum.

A `.codex-round-status` `dirty_files=1` értékét külön kivizsgáltuk:
`git status --short` a terminális jelzés után üres volt, az implementációs
commit négy útvonalat tartalmazott. Nincs elfogadatlan munkafa-diff.

## Falszifikációs próbák

1. `_mentions_halt` ideiglenesen egyszerű `halt in text` keresés lett.
   `test_a_similar_halt_code_does_not_cover_the_class` piros:
   `fedett != hiányzik`. Restore után 1/1 zöld.
2. A figyelmeztetési küszöb ideiglenesen `occurrences >= 1` lett.
   `test_warning_threshold_is_one_two_and_five_occurrences` piros:
   `hiányzik != nem jelölt` az egyetlen előfordulásnál. Restore után a teljes
   célzott fájl 7/7 zöld.

## Gate-bizonyíték ellenőrzése

| Gate | Független eredmény |
|---|---|
| `tools/round-gate.sh test/tooling/architecture_allowlist_guard_test.dart` | ✅ 6/6 lépés zöld: format, analyze, teszt, architecture, secrets, l10n |
| `python3 -m pytest tools/tests -q` | ✅ végső kombinált HEAD: 688 passed, 2 skipped, 606 subtests passed (343.72 s); az első reviewed HEAD is zöld volt (604 subtest) |
| `python3 -m pytest tools/tests/test_halt_ledger.py -q` | ✅ 7 passed (restore után) |
| `git diff --check` | ✅ nincs hiba |
| Scope-audit | ✅ 4 engedélyezett útvonal, 0 sértés |
| Exact-SHA teljes CI + property | ⏳ a review után dispatch-eli az orchestrátor |

Security-review nem kötelező: `risk = "normal"`, és a diff egyetlen útvonala
sem illeszkedik a `.ai/router.toml` `high_risk_path_fragments` listájára.

## Merge-döntés

A `05c2828d` kombinált HEAD correctness- és scope-review szempontból
**APPROVED**, nyitott lelet nincs. Merge csak az exact-SHA Full Gate és Router
CI sikeres lezárása, a friss `origin/main` ellenőrzése és a landoló kapujának
zöld eredménye után.
