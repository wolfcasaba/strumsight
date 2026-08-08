# E05-R30 — Review

Brief: `docs/rounds/e05-r30-dataset-evaluation-and-epic-closure.md`
Diff: `git diff bbb57fd8...codex/e05-r30-dataset-evaluation-and-epic-closure` (12 files, +1034/−4)
Reviewer: Claude Sonnet 5 · Dátum: 2026-08-08
Verdikt: **APPROVED — javító kör nélkül**

## Összegzés

BLOCKER: 0 · MAJOR: 0 · MINOR: 1 (reviewer saját próbájával lezárva) · NOTE: 3

Független `tools/round-gate.sh test/features/vision test/core test/tooling`
saját `/tmp/review-e05-r30` klónban: **MINDEN GATE ZÖLD** (format, analyze,
test×3, architecture, secrets, l10n — 8/8). `dart run tool/check_architecture.dart`
a mérgezetlen 12 allowlisted deviation-t jelenti, nincs új váratlan sértés.

## Acceptance criteria (brief §6)

| # | Kritérium | Teljesült | Bizonyíték |
|---|---|---|---|
| 1 | Architektúra-guard valódi-sértés próba (raw-frame) | ✅ | `test/core/architecture_dependency_test.dart:319,348` két ÚJ, fixture-alapú próba (`rejects raw frame payloads from vision persistence`, `rejects raw pixel buffers from vision provider state`); mindkettő zöld a független gate-ben. |
| 1b | Architektúra-guard valódi-sértés próba (practice→vision belső fájl) | ⚠️ részben | A brief SZÓ SZERINT ezt a feature-párt nevezi meg; a diff nem tartalmaz ilyen nevű próbát. A MECHANIZMUS maga már létezik és tesztelt (`allows public APIs and core while blocking feature internals` — 252. sor, `analyze`/`live`/`tuner` párral; `allows nested public.dart barrels but blocks feature internals` — 284. sor, `ai_tutor`/`song_trainer` párral) — generikus, feature-név-független szabály. **Reviewer saját, eldobható próbája** (lásd „Próbatesztek") a KONKRÉT `practice`↔`vision` párra is megerősítette: zöld. Lásd F1 (MINOR). |
| 2 | Model-integritás teszt (checksum/schema/license → PIROS; jó eset zöld) | ✅ | `test/tooling/vision_model_integrity_test.dart` — 4 teszt (jó manifest zöld, rossz checksum/schema/hiányzó licenc PIROS), mind zöld a gate-ben. |
| 3 | Vision-off paritás fixture (bitre azonos) | ✅ | `test/features/vision/vision_offline_regression_test.dart` — pinned JSON projekció Practice/Song/Analyze/Tutor kimenetre, `AppEnvironment.production`, mind a 11 flag `false`. |
| 4 | Evaluation harness (`--self-test` zöld, adat nélkül `NO_DATA`, szintetikus fixture) | ✅ | `ml/vision/evaluate_vision_metrics.py --self-test` — 4/4 cella (`no-data`, 0%, 1%, 2%) `passed=True`; önállóan újrafuttatva (lásd lent) egyezik. |
| 5 | Completion report tartalma (DoD-pontok, production-supported vs experimental, PENDING tételesen, hátralévő CI-munka nevesítve) | ✅ | `docs/sdd/epic-05-completion-report.md` — a 86 PENDING előfordulás (81 sor + 5 magyarázó) tételes bontása **egyezik** a reviewer saját, független `grep -c PENDING` számlálásával (44 a device-matrixban, 42 a benchmarkban = 86); governance-munka nevesítve (`## Remaining governance work`). |
| 6 | Flag-audit (mind a 11 flag `false` minden környezetben) | ✅ | `vision_offline_regression_test.dart` — `AppEnvironment.values` (development/lab/production) mindegyikén 11/11 flag `false`; `FeatureFlags.forEnvironment`-ben nincs dart-define override egyikre sem (reviewer saját grep-je is megerősítette). |
| 7 | `git diff --stat` nem tartalmaz `.github/`, `tool/ci/`, `lib/` fájlt | ✅ | `git diff --stat bbb57fd8..HEAD` — pontosan a brief §4 12 engedélyezett fájlja, semmi más. `scope_audit=ok`, `scope_audit_changed=12` (a wrapper gépi audit). |
| 6.1 | Küszöb-mátrix (alatt/rajta/fölött → PASS/PASS/experimental) | ✅ | 1% inkluzív küszöb, dokumentálva `ml/vision/dataset_manifest.md` §6.1-ben ÉS a brief §10-ben `python3 -c` kimenettel (`below=0.00 at=0.01 above=0.02`); a harness self-testje ugyanezt a három cellát futtatja és igazolja. |

## Scope-audit

Engedélyezett fájlokon kívüli változás: **nincs.** `git diff --stat` pontosan
a brief §4 12 sorát fedi (`tool/check_architecture.dart`,
`ml/vision/evaluate_vision_metrics.py`, `ml/vision/dataset_manifest.md`,
`docs/sdd/epic-05-completion-report.md`, `docs/runbooks/vision-rollout.md`,
`docs/manual-testing/vision-device-matrix.md`,
`docs/manual-testing/vision-performance-benchmark.md`, `README.md`,
`test/core/architecture_dependency_test.dart`,
`test/tooling/vision_model_integrity_test.dart`,
`test/features/vision/vision_offline_regression_test.dart`,
`docs/rounds/e05-r30-dataset-evaluation-and-epic-closure.md`).
A gépi scope-audit (`.codex-round-status`: `scope_audit=ok`,
`scope_audit_base=5b66a06c…`, `scope_audit_changed=12`) egyezik.

## Próbatesztek (reviewer saját, eldobható, `/tmp/review-e05-r30`-ban futtatva, nem commitolva)

1. **Gate-újrafuttatás saját kézzel, izolált klónban:** `git clone --branch
   codex/e05-r30-dataset-evaluation-and-epic-closure` → friss
   `flutter pub get`/`gen-l10n` → `tools/round-gate.sh test/features/vision
   test/core test/tooling` → **8/8 lépés zöld** (format, analyze, 3×test,
   architecture, secrets, l10n).
2. **A hiányzó „practice → vision belső fájl" próba pótlása** (F1 lezárása):
   `test/core/_probe_practice_vision_import_test.dart` — egy szintetikus
   `lib/features/practice/domain/service/practice_vision_probe.dart` fixture,
   amely importálja a `lib/features/vision/data/landmarks/
   hand_landmark_provider.dart`-ot (nem `public.dart`-on keresztül). Futás:
   `flutter test test/core/_probe_practice_vision_import_test.dart` →
   **PIROS lett volna a védelem hiányában, de a MEGLÉVŐ generikus szabály
   ZÖLDEN elkapta** (`report.unexpectedViolations` tartalmazza a várt kulcsot).
   A próba nincs commitolva, csak a `/tmp` klónban élt.
3. **Real-file grep-egyeztetés a completion reporttal:** `grep -n PENDING
   docs/manual-testing/vision-device-matrix.md | wc -l` → 44,
   `vision-performance-benchmark.md` → 42, összesen 86 — egyezik a
   completion report „86 PENDING occurrences" állításával (81+5 bontás is
   stimmel).
4. **Allowlist-tartalom ellenőrzés:** a `tool/check_architecture.dart` diffje
   NEM nyúl a 12 elemű `architectureAllowlist` `Set`-hez (csak új enum-értéket,
   új szabály-függvényt és egy leíró-switch ágat ad hozzá) — a gate
   architecture lépése is ugyanazt a 12-t jelenti vissza, tehát az allowlist
   ténylegesen nem bővült (brief §5 pont 1 tiltása betartva).
5. **Perzisztencia-réteg valódisága:** `lib/features/vision/data/persistence/`
   öt, nem-triviális fájlt tartalmaz (codec/repository/export, ~33 KB); egyik
   sem hivatkozik a tiltott típusokra — az architecture-lépés zöldje tehát nem
   üres könyvtáron trivializálódik.

## Architektúra + termékhatárok

- `AGENTS.md` §6 domain-függetlenség: a diff nem érint `lib/`-et, tehát nincs
  új domain/framework-csatolás.
- `AGENTS.md` §5 termékhatárok: az új Python harness kizárólag helyi JSONL
  fixture-t olvas (stdlib-only: `argparse`/`json`/`sys`/`dataclasses`/
  `pathlib`/`typing`), nincs hálózati vagy kamera-hozzáférés a kódban.
- Raw-frame-persistence tilalom (ADR 0183 folytonossága): most már gépi őr
  is védi, nem csak konvenció.

## Megállapítások

### F1 — MINOR — A brief §6 „practice → vision belső fájl" próbája nem szerepel a diffben, csak a mögöttes generikus szabály

- **Fájl:** `test/core/architecture_dependency_test.dart` (a brief §6 1. acceptance sora)
- **Probléma:** a brief szó szerint egy `practice → vision belső fájl` importtal futtatott próbát ír elő. A diff csak a ÚJ raw-frame szabályra ad próbát; a cross-feature-import szabályra (amely már régebb óta létezik és generikusan működik) nem ad ÚJ, vision-nevesített próbát — csak a meglévő, más feature-párokkal (analyze/live/tuner, ai_tutor/song_trainer) írt tesztek bizonyítják a mechanizmust közvetve.
- **Hatás:** nincs valódi termékkockázat — a reviewer saját, eldobható próbája (lásd fent, 2. próbateszt) igazolta, hogy a meglévő `crossFeatureImportsMustUsePublicApi` szabály a konkrét `practice`/`vision` párra is helyesen PIROSAT ad. A hiány pusztán az acceptance-bizonyíték specifikussága, nem a védelem hiánya.
- **Kötelező javítás:** nem blokkoló; javasolt (nem kötelező) follow-up: egy ~20 soros permanens teszt hozzáadása a meglévő minta szerint (`_write` fixture `lib/features/practice/...` → import `lib/features/vision/data/...` → `expect(...unexpectedViolations...)`), hogy az acceptance-kritérium szó szerint is dokumentált maradjon a jövőbeli olvasóknak.
- **Ellenőrzés:** a reviewer saját próbája zöld volt (ld. fent) — ez az érdemi bizonyíték a merge-döntéshez.
- **Státusz:** OPEN (nem blokkoló, follow-up-ra hagyva; a reviewer independent próbája már lezárta az érdemi kockázatot).

### N1 — NOTE — `_rawVisionPayloadTypes` azonosító-egyezés trivális elrejtéssel megkerülhető

- **Fájl:** `tool/check_architecture.dart:192-199` (`_containsIdentifier`, szó-határos regex).
- **Megfigyelés:** a szabály sztring/azonosító-szintű egyezést keres (`\bVisionImage\b` stb.) a trivia-mentesített forráson. Egy jövőbeli szerző egy type-alias-szal (`typedef RawFrame = Uint8List;`) vagy egy wrapper-osztállyal triviálisan megkerülhetné anélkül, hogy a tiltott azonosító szó szerint megjelenne a persistence-fájlban. Ez a guard-generáció ismert, elfogadott korlátja (ugyanez igaz a meglévő `crossFeatureImportsMustUsePublicApi` import-alapú szabályra is) — nem ennek a körnek a hibája, csak dokumentálandó belátás.
- **Javaslat:** nem blokkoló; egy jövőbeli, mélyebb (típusgráf-alapú) architektúra-ellenőrzés következő körben mérlegelhető, ahogy a `HANDOFF.md` §3 már nevesíti a hasonló tranzitív-gráf rést a `vision/public.dart` wide-barrelnél.

### N2 — NOTE — A Tutor-projekció `isNull` assertje áttételesen bizonyít

- **Fájl:** `test/features/vision/vision_offline_regression_test.dart:189` (`_tutorProjection`).
- **Megfigyelés:** a `const TutorVisionContextAdapter().adapt(vision)` hívás azért ad `null`-t, mert a konstruktor `schemaVersion`/`scorerVersion` nélkül épül (`_hasVersion == false`), NEM azért, mert egy vision-flag ki van kapcsolva — az adapter maga nem olvas flaget. A fő paritás-bizonyíték a `_preVisionTutorProjection` pinned JSON (amely nem tartalmaz vision mezőt), ez az assert csak kiegészítő. Nem hibás, csak a névből („vision off ⇒ null") elsőre több derül ki, mint amit ténylegesen bizonyít.
- **Javaslat:** nem blokkoló; egy jövőbeli kör pontosíthatná a teszt-kommentet, hogy a null-oksága a hiányzó version-metaadat, nem a flag-állapot.

### N3 — NOTE — A completion report `1.0` verziószáma és a „Rounds: E05-R01–R30” tartalmaz egy még-nem-merge-elt kört

- **Fájl:** `docs/sdd/epic-05-completion-report.md:3`.
- **Megfigyelés:** a report saját magát (E05-R30) is a lezárt tartományba sorolja, miközben a report ÍRÁSAKOR a kör még nincs merge-elve. Ez szokásos, önhivatkozó mintázat (a kör a saját lezárását dokumentálja) — más E05 zárókörök (pl. epic-02-completion-report.md) is így tették —, csak megjegyzésre érdemes, hogy a state a merge UTÁN válik ténylegesen igazzá.
- **Javaslat:** nem blokkoló, nincs teendő.

## Gate-bizonyíték

```
tools/round-gate.sh test/features/vision test/core test/tooling   (/tmp/review-e05-r30, branch tip 9b993f81)
  [1] format        zöld
  [2] analyze        zöld
  [3] test test/features/vision   zöld
  [4] test test/core zöld
  [5] test test/tooling zöld
  [6] architecture   zöld (12 allowlisted deviation(s), 0 unexpected)
  [7] secrets        zöld (2082 file(s) scanned, 0 finding(s))
  [8] l10n           zöld (en → hu, 1019 message(s))
```

## Következő lépés

Biztonsági review (risk=high, `security-reviewer` ágens) párhuzamosan folyamatban
— külön jelentés: `docs/reviews/e05-r30-dataset-evaluation-and-epic-closure-security.md`.
CRITICAL/BLOCKER esetén a verdikt itt is CHANGES REQUIRED-ra vált. Addig:
exact-SHA CI dispatch (`full-gate.yml` + `router-ci.yml`, mindkettő a
`9b993f81` SHA-n) folyamatban.
