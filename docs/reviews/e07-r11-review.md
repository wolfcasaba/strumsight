# E07-R11 — független review

**Verdikt:** CHANGES REQUESTED

**Review baseline:** `20d7499d..13a70949`  
**Implementer:** Sonnet 5 (`sonnet-impl`)  
**Reviewer:** Codex / Terra, izolált `/tmp/review-e07-r11` klón

## Mért ellenőrzések

- Scope audit: `Legacy scope audit OK (20d7499d..13a7094989c8, 9 changed path(s), 0 generated/ignored)`.
- Független gate: `tools/round-gate.sh test/features/practice_generator/validation/plan_validator_test.dart test/features/practice_generator/validation/plan_repairer_test.dart test/property/planner_repair_property_test.dart` — zöld (format, analyze, mindhárom teszt, architecture, secrets, l10n).
- A kötelező valós-sértés próba az iterációs korlátra dokumentálva és a handoff szerint pirosra váltott.

## Leletek

| Súlyosság | Hely | Lelet | Bizonyíték és javítási irány |
|---|---|---|---|
| MAJOR | `lib/features/practice_generator/domain/service/plan_validator.dart:_validateCompletedHistory` | A completed-history guard csak azt vizsgálja, hogy a **teljes előző nap** `completed` volt-e; egy aktív napban már `completed` blokk tartalmának módosítása átcsúszik fatal nélkül. Ez sérti ADR 0263 §6 / brief A6 „completed múlt” szabályát. | Eldobható review-próba: egy előző snapshotban `day.1.block.1` `completed`, a következő snapshotban azonos block-ID-val 6→7 percre módosítva. `flutter test test/review_e07_r11_completed_block_test.dart` exit 1: `Expected true, Actual false` a `result.hasFatal` állításon. Hasonlítsd össze az előző snapshot minden `completed` blokkját ID és teljes érték alapján; eltérés vagy hiány esetén `completedHistoryModified` fatal. Tegyél tartós A6 regressziós tesztet a megengedett validator tesztfájlba. |

## Következő lépés

Egy javító implementer-kör szükséges ugyanazzal a motorral. Merge tilos, amíg a MAJOR nem zárul le és a független re-review zöld.
