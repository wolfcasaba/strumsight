# E99-R03 (GOV-05c) — Review

Brief: `docs/rounds/e99-r03-gov-05c-learn-migration-rollout.md`
ADR: `docs/adr/0198-learn-migration-rollout-boundary.md`
Diff: `git diff 69ecc661...42f54b33` (`origin/main` at dispatch time `...codex/e99-r03-gov-05c-learn-migration-rollout`)
Reviewer: Claude Sonnet 5 · Dátum: 2026-08-09
Verdikt: **APPROVED**

## Összegzés

BLOCKER: 0 · MAJOR: 0 · MINOR: 0 · NOTE: 1

Az implementáció (Terra, 2 commit: `8cc9eccf` feat + `42f54b33` docs-handoff)
pontosan a brief §8 sorrendjét követi, a hét engedélyezett fájlon belül marad,
és mind a tíz acceptance-pontot teljesíti mérhető bizonyítékkal. A reviewer
SAJÁT, izolált `/tmp/review-e99-r03` klónjában futtatta újra a teljes
kijelölt gate-et (10/10 lépés zöld) és egy SAJÁT valódi-sértés próbát —
mindkettő az implementer állításától függetlenül reprodukálta a zöld,
illetve a várt piros eredményt.

## Acceptance criteria

| # | Kritérium | Teljesült | Bizonyíték |
|---|---|---|---|
| A1 | Három külön környezet-cella (nem ciklus) | ✅ | `test/app/feature_flags_test.dart:96-129` — `'Migrated Learn rollout boundary'` csoport, három külön `test(...)`: development/lab `isTrue`, production `isFalse`. Reviewer-futtatás: mindhárom zöld (`flutter test test/app/feature_flags_test.dart` → 11/11 zöld a saját klónban, lásd próba alább). |
| A2 | Default konstruktor változatlan | ✅ | `lib/app/config/feature_flags.dart:16` — `this.migratedLearnEnabled = false,` érintetlen. `test/app/app_config_test.dart` „new constructor fields are optional…” tesztje diff-mentes. |
| A3 | Mind a négy őr átirányítva, egyik sem törölve | ✅ | `git diff --stat` — mind a négy fájl (`app_config_test.dart`, `feature_flags_test.dart`, `learn_migration_parity_test.dart`, `learn_rollback_test.dart`) érintett; egyikben sincs törölt `test`/`group`, mindegyikben megmaradt egy `AppEnvironment.production` → `isFalse` állítás (soronként ellenőrizve, lásd Scope-audit melletti diff-olvasat). |
| A4 | Az A7-nevű teszt neve és mérése egyezik | ✅ | `test/features/learn/learn_migration_parity_test.dart:307` — `AppEnvironment.development` → `AppEnvironment.production`, a teszt neve változatlanul „production default stays OFF”. |
| A5 | `AppConfig.resolve` problems-mentes mind a három környezetben | ✅ | `test/app/app_config_test.dart:222-233` — új teszt, `for (environment in AppEnvironment.values) expect(() => _resolve(environment: environment), returnsNormally)`. Forráskód-ellenőrzés: `AppConfig.resolve` (`lib/app/config/app_config.dart:168`) `throw ConfigurationException(problems)`-t dob, ha `problems.isNotEmpty` — a teszt tehát valódi, nem vacuous: a `migratedLearnEnabled requires practiceEngineV2Enabled` szabály (115-116. sor) egyik környezetben sem sülhet el, mert mindkét flag ugyanazt a `nonProd` értéket kapja. |
| A6 | Kerítés: a többi rollout-flag nem mozdult | ✅ | `feature_flags_test.dart` „keeps unrelated rollout flags disabled…” tesztje továbbra is `aiTutorEnabled`/`aiTutorCloudEnabled`/`visionEnabled`-t méri (a `migratedLearnEnabled` sor KIKERÜLT belőle, mert saját A1-mátrixot kapott — helyes, nem lyuk). `vision_offline_regression_test.dart` a tiltott listán van, nem módosult (`git diff --name-only` nem tartalmazza). |
| A7 | Rollback-őr flag-OFF ága szó szerint változatlan | ✅ | `test/features/learn/learn_rollback_test.dart` diffje kizárólag a 131-146. sori A8 flag-határ tesztet érinti (ciklus → egyetlen production-cella + névváltás); a `'A8 — flag OFF renders the same Play control as the legacy build'` (90. sor) és a `'A8 — flag OFF leaves the V1 store and lesson-progress untouched'` (104. sor) tesztek `grep`-pel megerősítve jelen vannak, diff-mentesek. |
| A8 | Nulla production Dart-változás a flagen kívül | ✅ | Reviewer-saját futtatás: `git diff --name-only 69ecc661...HEAD \| grep '^lib/'` → kizárólag `lib/app/config/feature_flags.dart`. |
| A9 | Device-mátrix frissítve, PENDING cellákkal | ✅ | `docs/manual-testing/practice-engine-device-matrix.md` §2.3 — cím „PENDING készülékes ellenőrzés”, mind a hét sor `Eredmény`/`Pass/Fail` cellája `PENDING`. |
| A10 | A gate zöld, egyetlen artefaktum-hívással | ✅ | Lásd „Gate-bizonyíték ellenőrzése” — reviewer saját, izolált futtatása 10/10 zöld. |

## Scope-audit

Engedélyezett fájlokon kívüli változás: **nincs.**

```
$ git diff --stat 69ecc661...42f54b33
docs/manual-testing/practice-engine-device-matrix.md        |  23 ++--
docs/rounds/e99-r03-gov-05c-learn-migration-rollout.md      | 121 ++++++++++--
lib/app/config/feature_flags.dart                           |   9 +-
test/app/app_config_test.dart                                |  17 ++-
test/app/feature_flags_test.dart                             |  30 ++++-
test/features/learn/learn_migration_parity_test.dart         |   2 +-
test/features/learn/learn_rollback_test.dart                 |  16 ++-
7 files changed, 176 insertions(+), 42 deletions(-)
```

Pontosan a brief `allowed_paths` hét bejegyzése, egy sem kívül. A gépi
scope-audit is megerősíti: `.codex-round-status` → `scope_audit=ok`,
`scope_audit_changed=7`.

## Megállapítások

### N1 — NOTE — a `dirty_files=1` jelzés az implementer köztes állapotában, nem hiba

- **Fájl:** N/A (jelzésfájl-megfigyelés)
- **Probléma:** a `done` jelzés `dirty_files=1`-et jelentett; a review-időpontban a munkapéldány (`/home/ubuntu/ss-codex-e99-r03`) `git status --short` szerint TISZTA, és a második commit (`42f54b33`, a handoff-dokumentáció) a jelzés pillanatában készülhetett.
- **Hatás:** nincs — a végállapot tiszta, mindkét commit a branchen van, a scope-audit ezt már a tiszta állapoton mérte.
- **Kötelező javítás:** nincs, csak dokumentálás.
- **Ellenőrzés:** `git -C /home/ubuntu/ss-codex-e99-r03 status --short` → üres kimenet.
- **Státusz:** WONTFIX (nem hiba, csak időzítési megfigyelés).

## Reviewer saját valódi-sértés próbája (a brief §6.1 mellett, attól függetlenül)

Az implementer §6.1 próbáját a reviewer **megismételte SAJÁT, izolált
klónban**, hogy az állítás ne csak bemondás legyen:

```
$ sed -i 's/migratedLearnEnabled: nonProd,/migratedLearnEnabled: true,/' \
    lib/app/config/feature_flags.dart
$ flutter test test/app/feature_flags_test.dart
...
00:00 +6: Migrated Learn rollout boundary remains disabled in production
00:00 +6 -1: Migrated Learn rollout boundary remains disabled in production [E]
  Expected: false
    Actual: <true>
  test/app/feature_flags_test.dart 126:7  main.<fn>.<fn>
00:00 +11 -1: Some tests failed.
Failing tests:
  test/app/feature_flags_test.dart: Migrated Learn rollout boundary remains disabled in production
```

Pontosan az A1 production-cella, és **kizárólag** az bukott (10 másik teszt
zöld maradt) — a mérce valóban a production-határra mér, nem egy tágabb vagy
szűkebb feltételre. Visszaállítva (`git checkout --`), a fa újra tiszta.

## Gate-bizonyíték ellenőrzése

| Gate | Állított eredmény | Ellenőrizve |
|---|---|---|
| format | ZÖLD (implementer) | ✅ reviewer saját futása is ZÖLD (1214 fájl, 0 változás) |
| analyze | ZÖLD (implementer) | ✅ reviewer saját futása is ZÖLD (No issues found) |
| test/app | 201 teszt zöld, 1 skip | ✅ reviewer: `+201 ~1: All tests passed!` |
| test/features/learn | zöld | ✅ reviewer: `+401: All tests passed!` |
| test/core | zöld | ✅ reviewer: `+160 ~2: All tests passed!` |
| test/features/live | zöld | ✅ reviewer: `+49: All tests passed!` |
| test/features/songs | zöld | ✅ reviewer: `+49: All tests passed!` |
| architecture | zöld (12 allowlisted) | ✅ reviewer: azonos (12 allowlisted deviation) |
| secrets | zöld | ✅ reviewer: 2090 fájl, 0 lelet |
| l10n | zöld | ✅ reviewer: en→hu, 1019 üzenet, parity OK |
| CI (teljes suite + property + APK) | dispatch alatt | ⏳ lásd HANDOFF/PR — orchesztrátor a review után dispatch-eli, merge előtt zöldnek kell lennie |

A reviewer futtatása **teljesen független** munkapéldányban történt
(`/tmp/review-e99-r03`, friss `git clone --branch
codex/e99-r03-gov-05c-learn-migration-rollout`), nem a közös/implementer
munkafán — így a párhuzamosan futó GOV-06 pre-flight (69ecc661) vagy bármely
más session nem tudta befolyásolni a mérést.

## Architektúra + termékhatárok (AGENTS.md §5/§6)

A diff kizárólag `lib/app/config/feature_flags.dart`-ot érinti a `lib/` fán
belül (egy meglévő, nem-domain konfigurációs osztály egyetlen mezőjének
factory-értéke + két doc-comment), a többi hét fájl teszt/dokumentum. Nincs
domain-, audio-, hálózat-, mic-ownership- vagy secret-érintettség — a §5/§6
ellenőrzőlista egyetlen pontja sem releváns erre a körre. A `tool/
check_architecture.dart` (12 allowlisted, 0 új) ezt gépileg is megerősíti.

## Merge-döntés

ADR 0052 szerint: minden gate zöld ÉS nincs nyitott BLOCKER/MAJOR → **merge
engedélyezett**, a CI (Build APK + Router CI) zöld futása után a merge SHA-n.
