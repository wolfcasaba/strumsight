# Review — E04-R09 · PracticePlanDraft, validator és compiler

- **Verdikt:** **APPROVED** (0 BLOCKER, 0 MAJOR, 0 MINOR, 3 NOTE)
- **Branch:** `codex/e04-r09-practice-plan-draft-validator-compiler`
- **Reviewed head:** `c100b27`
- **Implementer motor:** Codex (`gpt-5.6-terra`, örökölt kézi override)
- **Reviewer:** Claude Opus 4.8 (független, read-only)
- **Metódus:** izolált `/tmp/review-e04r09` klón, saját `tools/round-gate.sh`
  újrafuttatás, scope-audit, mutáció-próbák.

## 1. Jelzés + handoff

`.codex-round-status`: `status=done`, `head=c100b27`, `dirty_files` a `done`
jelzéskor 1 volt (a gitignore-olt generált l10n), a commit utáni working tree
**tiszta** (`git status --short` üres). Nem fogadtam el bemondásra — minden
állítást a saját klónomban mértem.

## 2. Gate-újrafuttatás (saját, izolált klón)

`tools/round-gate.sh test/features/ai_tutor/domain test/features/ai_tutor/application`
a friss klónban (`prepare-flutter-generated.sh` után):

```
format      zöld
analyze     zöld   (No issues found!, 3 items)
test test/features/ai_tutor/domain        zöld
test test/features/ai_tutor/application    zöld
architecture zöld  (Architecture dependencies OK, 12 allowlisted deviation — NEM nőtt)
GATE_EXIT=0
```

A teljes suite + randomizált property + APK a CI-ban (ADR 0053) — lásd §6.

## 3. Scope-audit

`git diff --name-status origin/main...c100b27` — mind a 7 fájl a brief §4 /
`allowed_paths` listáján belül:

| Fájl | Státusz | Engedélyezett |
|---|---|---|
| `docs/rounds/e04-r09-...md` | M (pre-flight §0.0) | ✓ |
| `lib/.../domain/models/practice_plan_draft.dart` | A | ✓ |
| `lib/.../domain/models/practice_plan_block.dart` | A | ✓ |
| `lib/.../domain/services/practice_plan_validator.dart` | A | ✓ |
| `lib/.../application/planning/practice_plan_compiler.dart` | A | ✓ |
| `test/.../domain/practice_plan_validator_test.dart` | A | ✓ |
| `test/.../application/practice_plan_compiler_test.dart` | A | ✓ |

`lib/features/ai_tutor/public.dart` **érintetlen** (üres marad — D2 tiszteletben
tartva). **§0.0 D1 mérve:** a compiler imports = `core/foundation`,
`core/music/strum`, `features/practice/public.dart`, `features/songs/public.dart`
+ saját domain — **nulla `song_trainer`-belső import** (`grep` üres). A Song
Trainer-belső compiler nem szivárgott be. **Nincs listán kívüli fájl.**

## 4. Acceptance criteria — tételes bizonyíték

| Kritérium | Bizonyíték | Verdikt |
|---|---|---|
| Duration-mátrix 5/10/20/30, összeg == keret (alatta/rajta/fölötte) | `deterministicTemplate` = [1,3,1]/[2,5,3]/[3,7,7,3]/[5,10,10,5]; a validator `totalDuration != targetDuration` → `durationMismatch`; teszt under/exact/over mind a négy keretre | ✓ |
| Unsupported/tempo/missing-song/tuning/user-avoid/capability/skill → invalid, stabil kóddal | `PracticePlanValidationCode` zárt kód-készlet; `'uses stable codes for every blocked input'` teszt mind a 7 kódot lefedi | ✓ |
| invalid-draft-cannot-launch | `PracticePlanCompiler.compile` a validáció után `Failure`-t ad invalid draftra; `'cannot compile or launch an invalid draft'` teszt + **mutáció-próba** (§5 P1) | ✓ |
| Compiler-parity Practice + song adapter (`compilePracticeTarget` bit-stabil) | mindkét adapter a **közös publikus** `compilePracticeTarget`-en fordul; a két parity-teszt a `compiledTarget`-et a közvetlen `compilePracticeTarget` kimenetével egyenlőségre méri | ✓ |
| user-edit után újravalidál | `'revalidates a user edit instead of retaining the earlier result'` teszt (`copyWith` tempo 301 → `tempoOutOfRange`) | ✓ |
| offline-runnable pontos (asset-hiány → false) | `isOfflineRunnable = blocks.every(assetAvailableLocally)`; `'marks a valid asset-missing plan as not offline-runnable'` teszt | ✓ |

## 5. Mutáció-próbák (eldobható, a klónban, visszaállítva)

- **P1 — invalid-draft kapu (a brief §6 által kötelezően kért próba).**
  `practice_plan_compiler.dart`: `if (!validation.isValid)` → `if (false)`.
  Eredmény: `PracticePlanCompiler cannot compile or launch an invalid draft`
  **RED** (`+3 -1`). A kapu load-bearing; „invalid mégis compile-ol" nem
  csúszhat át.
- **P2 — duration-mismatch invariáns.** `practice_plan_validator.dart`:
  `if (totalDuration != draft.targetDuration)` → `if (false)`. Eredmény: mind a
  4 duration-keret under/exact/over tesztje **RED**. A duration-egzaktság
  gépi mérce.

Mindkét mutáció visszaállítva; a klón working tree tiszta a próbák után.

## 6. CI / zöld kapu

- `build-apk.yml` a `c100b27` exact head-en: az orchestrátor dispatch-elte —
  a merge-evidencia run-linkje a PR-törzsben és a HANDOFF-ban (a merge exact-SHA
  zöldjén dől el; piros/eltérő SHA → nincs merge).
- Router CI: a diff érinti a `docs/rounds/**`-ot → a Router CI zöldje a merge
  SHA-n kötelező (L113).

## 7. NOTE-ok (nem blokkolnak, follow-up)

- **N1.** `_definitionForSong` minden bar chord-eseményéhez a `pattern[0]`
  irányt köti (a bar-kezdő slot), a slot-loop 1-től indul — konzisztens az
  „egy bart átfogó, ismétlődő strum pattern" modellel; a parity-teszt valós
  `Song`-gal zöld. Ha R11/R19 finomabb bar-belső chord-timinget igényel, ott
  bővíthető.
- **N2.** A `deterministicTemplate` blokk-típusai fixek (warmup/technique/
  rhythm/reflection); a user-avoid/capability szűrés a validátoron át, futásidőben
  történik — a generátor szándékosan nem context-érzékeny (pure, determinisztikus).
- **N3.** `PracticePlanSource.aiSuggestion|deterministicTemplate|userEdited`
  provenance rögzítve, de e körben nem ágazik el rá viselkedés — az AI-suggested
  vs template megkülönböztetést az R12/R16 prompt-kör fogja fogyasztani.

## 8. Architektúra + termékhatárok

- Domain-purity zöld; az `application/planning` réteg csak más feature
  **publikus barrel**-jeit importálja (megengedett kereszt-feature minta, a
  `SongPracticeCompiler` precedense). Nincs új architecture-allowlist bejegyzés
  (a `tool/check_architecture.dart` érintetlen, tilos zóna).
- Nincs lifecycle-erőforrás (lease/lock/mic/hálózat) — pure domain + pure
  compiler-adapter (§0.0 §1.2 N/A megerősítve).
- `ai_tutor/public.dart` üres → a boundary-invariáns zöld; e körnek nincs
  hívója (launch R11, UI R19).

**Összegzés:** a kör a brief minden mérhető előírását teljesíti, a két központi
invariáns mutáció-verifikált, a scope tiszta, a §0.0 D1 (nincs source-belső
import) tartva. **APPROVED** — merge a zöld kapu (exact-SHA CI + Router CI)
után.
