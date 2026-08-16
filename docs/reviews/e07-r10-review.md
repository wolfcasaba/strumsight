# E07-R10 — Review

Brief: docs/rounds/e07-r10-adaptive-practice-plan-domain.md
Diff: `git diff de060337...5a3c3454` (`origin/main` @ pre-flight → `terra/e07-r10-adaptive-practice-plan-domain` HEAD)
Reviewer: Claude (Sonnet 5) · Dátum: 2026-08-16
Verdikt: CHANGES REQUESTED (egyetlen MINOR, körben javítandó — nincs BLOCKER/MAJOR)

## Összegzés

BLOCKER: 0 · MAJOR: 0 · MINOR: 1 · NOTE: 0

## Acceptance criteria

| # | Kritérium | Teljesült | Bizonyíték |
|---|---|---|---|
| A1 | Revízió-szám szigorúan monoton; azonos/csökkenő → hiba | ✅ | `plan_revision.dart:46-52` (`number <= previous.number` → `ArgumentError`); `plan_revision_test.dart` 3 cella (alatta/határon/fölötte), független gate-futásban zöld |
| A2 | Rögzített revízió módosítási kísérlete → hiba | ✅ | `plan_revision.dart:56-63` minden mező `final`, nincs setter/`copyWith`; implementer valódi-sértés próbája (§10) + saját, független valódi-sértés próbám (lásd lent) mindkettő PIROS→visszaállítás |
| A3 | Revízió TELJES pillanatképet hordoz, az aktuális változása nem hat rá | ✅ | `plan_revision.dart:62` `snapshot` típusa `AdaptivePracticePlan` (teljes érték, nem diff/pointer) — a §5.2 tiltott mintája strukturálisan lehetetlen; `plan_revision_test.dart` „keeps a full immutable snapshot…” |
| A4 | `completed` blokk/nap módosítása → hiba, nem néma felülírás | ✅ | `practice_block.dart:129-133`, `practice_day.dart:90-92` (`replaceContent` guard); **saját, független valódi-sértés próbám** a block oldalon: a guard ideiglenes eltávolítása → a teszt PIROSRA vált (lásd lent), majd visszaállítva |
| A5 | Érvénytelen státusz-átmenet → hiba | ✅ | `practice_block.dart:78-102`, `practice_day.dart:40-64` — a §0.0 pinnelt 8-állapotú táblája szó szerint; `adaptive_practice_plan_test.dart` mind a 8 állapot LEGÁLIS (ahol van) ÉS TILTOTT célját is teszteli, block+day külön (32 teszt) — kézzel átfuttatva a `legalTargets`/`forbiddenTargets` térképet a pinnelt táblával, minden bejegyzés egyezik |
| A6 | Change set strukturált, megnevezi az okot | ✅ | `plan_change_set.dart` — `PlanChange.reason: PlanChangeReason` (stabil kódú enum, nem szabad szöveg), `before`/`after: Map<String,Object?>`; `plan_change_set_test.dart` |
| A7 | Terv JSON verziózott, round-trip veszteségmentes | ✅ | `adaptive_practice_plan.dart` `schemaVersion` mező + teljes `toJson`/`fromJson`; `adaptive_practice_plan_test.dart` „round-trips a versioned plan…” — `decoded == original` |
| A8 | Summary DTO nem tartalmaz szabad szöveges megjegyzést | ✅ | `adaptive_practice_plan.dart:79-88,176-207` `PracticePlanSummary` nem tartalmazza a `goals`/`userNote` mezőt; teszt a `plan_fixtures.dart`-beli `'private note'` poison-pillel igazolja a hiányát |

## Scope-audit

Engedélyezett fájlokon kívüli változás: **nincs**. Géppel mérve, kétszer:

- Az implementer wrapper saját auditja: `scope_audit=ok`, `scope_audit_changed=11`, bázis `63b3c1ec` (a pre-flight+addendum utáni HEAD).
- Saját, független futtatás izolált klónban: `python3 tools/scope-audit.py --repo /tmp/review-e07-r10 --brief docs/rounds/e07-r10-adaptive-practice-plan-domain.md --base 63b3c1ec` → `Legacy scope audit OK (63b3c1ec..5a3c34542251, 11 changed path(s), 0 generated/ignored)`.

A 11 fájl pontosan a §4 (a §0.0.1 addendummal bővített) engedélyezett lista: 5 ÚJ domain-modell, `public.dart` bővítés, 3 teszt, `plan_fixtures.dart` (§0.0.1-ben engedélyezve), a round-brief §10 handoff.

## §0.0/§0.0.1 pre-flight döntések — végrehajtás ellenőrizve

- **§0.0 (`PracticeItemStatus`):** pontosan a pinnelt 8 érték, pontosan `practice_block.dart`-ban (NEM `plan_enums.dart`-ban), `practice_day.dart` importálja onnan. A pinnelt átmenet-tábla (planned/ready/inProgress legális éleivel, öt terminális állapottal) **szó szerint** leképezve mindkét `canTransitionTo` switch-ben, azonos alakban.
- **Kötelező mintakövetés** (`PracticeGoalStatus`/`PracticeGoal.canTransitionTo`/`transitionTo`): mindkét osztály (`PracticeBlock`, `PracticeDay`) pontosan ezt a bool-predikátum + `StateError`-t dobó, új-példányt-visszaadó formát követi.
- **§0.0.1 (`plan_fixtures.dart` engedélyezése):** a fájl kizárólag a három teszt közös builderét tartalmazza (nincs benne production-viselkedés), a `test/fixtures/<feature>/<terület>/<név>_fixtures.dart` mért konvenciót követi — nincs scope-tágítás azon túl, amit az addendum engedélyezett.
- **SDD §16.7 audit-log-os korrekció kivétele** (explicit KÍVÜL a körön): nincs ilyen override-út a kódban — helyesen kihagyva.

## Megállapítások

### F1 — MINOR — `PlanChangeType` nem stabil-kódú, a `toJson()` a Dart `.name`-et perzisztálja

- **Fájl:** `lib/features/practice_generator/domain/model/plan_change_set.dart:6,62`
- **Probléma:** `enum PlanChangeType { added, removed, updated, moved, statusChanged }` — nincs `code` mező, nincs `fromCode()`. A `PlanChange.toJson()` a `type.name`-et írja (`'type': type.name`), miközben a VELE EGY FÁJLBAN élő `PlanChangeReason` (és a domain MINDEN MÁS enumja: `PlanStatus`, `BlockKind`, `PracticeItemStatus`, `PracticeGoalStatus`, `PlanRevisionReason` stb.) explicit `code`+`fromCode()` mintát követ — a `plan_enums.dart` fejléc-kommentje ezt szó szerint indokolja: „Every enum persists a fixed string `code`, never the Dart identifier (`.name`): renaming a Dart enum value must not corrupt saved data."
- **Hatás:** ma nulla aktív kockázat — a `PlanChangeSet`-nek nincs `fromJson`-ja, semmi nem perzisztálja/dekódolja még (a repository Kör 19). DE amint egy jövőbeli kör perzisztálja (ami ADR 0256 §4 explicit célja — a change setek a modell-javaslatok hatásának mérésére szolgálnak, tehát idővel BIZTOSAN tárolásra kerülnek), egy ártatlan Dart-identifier átnevezés (pl. `moved` → `reordered`) csendben eltérő JSON-t termel a régi rekordokhoz képest — pontosan az a hibaosztály, amit a domain többi enumja explicit véd.
- **Kötelező javítás:** `PlanChangeType`-ot alakítsd a domain többi enumjával egyező stabil-kódú mintára (`code` mező + `fromCode()`, a meglévő `PlanChangeReason`/`_decodeEnumCode`-stílust követve ugyanabban a fájlban), és a `PlanChange.toJson()`-t `'type': type.code`-ra.
- **Ellenőrzés:** a meglévő `plan_change_set_test.dart` bővíthető egy `expect(changeSet.toJson()['changes'].single['type'], 'updated')` (vagy a választott stabil string) assertióval, hogy a jövőbeli `.name`-re való visszacsúszást a teszt maga fogja meg.
- **Státusz:** OPEN — javító kör indítva ugyanazzal a motorral (terra), a diff triviális (~10 sor), nem hizlalja érdemben a kört.

## Próbatesztek (eldobható, dokumentálva, nem commitolva)

1. **A2 (implementer saját próbája, dokumentálva a brief §10-ében):** `PlanRevision.snapshot` ideiglenesen nem-`final` → az A2 teszt PIROS lett (a dinamikus assignment egy `AdaptivePracticePlan`-t adott vissza a várt `NoSuchMethodError` helyett) → visszaállítva.
2. **A4 (saját, független próba, `/tmp/review-e07-r10`-ben):** `practice_block.dart` `replaceContent()`-ből ideiglenesen eltávolítva a `status == PracticeItemStatus.completed` guard → `flutter test … --plain-name "rejects silently replacing a completed block"` PIROSRA vált (`Expected: throws StateError / Actual: returned PracticeBlock instance`) → `git checkout --` a fájlra, újrafuttatva → zöld. A guard tehát valóban a mért viselkedést kényszeríti ki, nem csak a doc-comment állítja.

## Gate-bizonyíték ellenőrzése

| Gate | Állított eredmény (implementer) | Ellenőrizve (saját, izolált `/tmp/review-e07-r10` klón) |
|---|---|---|
| format | zöld | ✅ zöld (`Formatted 1552 files (0 changed)`) |
| analyze | zöld, „No issues found" | ✅ zöld |
| test `plan_revision_test.dart` | zöld | ✅ zöld, 5/5 |
| test `adaptive_practice_plan_test.dart` | zöld | ✅ zöld, 34/34 |
| test `plan_change_set_test.dart` | zöld | ✅ zöld, 1/1 |
| architecture | zöld | ✅ zöld (12 allowlisted deviation, nincs új) |
| secrets | — (nem a brief gate-parancsa, de a round-gate.sh belefuttatja) | ✅ zöld (0 finding) |
| l10n | — | ✅ zöld (en→hu paritás) |
| scope-audit | `ok`, 11 changed | ✅ függetlenül reprodukálva, azonos szám |
| gate_shape (nincs `\| tail`/`&&`) | `ok` | ✅ a log-ban a gate-hívás csonkítatlan, a végén „MINDEN GATE ZÖLD" |

A **teljes** `flutter test` + randomizált property gate + APK a CI-ban fut (ADR 0053) — a merge előtti dispatch ezután következik, a `tools/round-ci-plan.py` kimenete szerint.

## Merge-döntés

Az ADR 0052 szerint: minden gate zöld ÉS nincs nyitott BLOCKER/MAJOR → merge — ez a feltétel gate-oldalon MÁR teljesül. Az egyetlen nyitott MINOR (F1) nem blokkolja a merge-et a szabálytábla szerint, de mivel a javítása trivális és nem hizlalja a diffet, egy rövid javító kör következik előbb; utána ez a jelentés APPROVED-ra frissül a javító commit SHA-jával.
