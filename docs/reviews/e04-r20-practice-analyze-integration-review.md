# Review — E04-R20 Practice & Analyze post-session tutor-integráció

- **Kör:** E04-R20 · **Branch:** `codex/e04-r20-practice-analyze-integration`
- **Implementer:** Codex (Terra, `gpt-5.6-terra`) · **Reviewer:** Claude (Opus 4.8)
- **Implementációs commit:** `eac1aad` (base `7b0f6c8` = pre-flight + §0.0-R1 revízió)
- **Verdikt:** **APPROVED** — nincs nyitott BLOCKER/MAJOR
- **Dátum:** 2026-08-06

## 1. Jelzés + handoff

`.codex-round-status`: `status=done`, head `eac1aad`. A `dirty_files=1` a
commit-előtti pillanatkép volt; a végleges fa TISZTA (`git status --short` üres).
Kör-jelzés lezárva. A §0.0-R1 revízió (public.dart scope-narrowing) az
orchestrátor döntése volt egy helyes implementer-`stopped` nyomán — lásd lentebb.

## 2. Gate-újrafuttatás (izolált /tmp klón)

`git clone --branch codex/e04-r20-… → /tmp/review-e04-r20`, majd
`tools/prepare-flutter-generated.sh` (l10n gen), végül:

```
tools/round-gate.sh test/features/ai_tutor/application test/features/ai_tutor/presentation
```

- `[1] format: ZÖLD`
- `[2] analyze: No issues found! (14.2s) → ZÖLD`
- `[3] test test/features/ai_tutor/application: All tests passed! (72) → ZÖLD`
- `[4] test test/features/ai_tutor/presentation: ZÖLD` (lásd §6 futás)
- `[5] architecture: ZÖLD`

## 3. Scope-audit

`tools/scope-audit.py --base 7b0f6c8`: **Legacy scope audit OK (9 changed
path(s), 0 generated/ignored).** Minden érintett fájl a (revideált) §4
`allowed_paths` listán belül; **nincs** `ai_tutor/public.dart` módosítás (a
boundary-teszt tiszteletben tartva), nincs result-UI érintés.

Változott fájlok: 2 új adapter, 1 belépő-kártya, 2 ARB, 3 teszt, a brief.

## 4. §0.0-R1 döntés igazolása (scope-narrowing)

A brief eredetileg `ai_tutor/public.dart` additív exportot engedélyezett; a
mért valóság ezt megcáfolta: az `ai_tutor_boundary_test.dart` (E04-R01, merge
`814388a`) ÜRESRE fagyasztja a boundaryt. Az implementer helyesen `stopped`-ot
jelzett. A feloldás **lista-SZŰKÍTÉS** (ADR 0087 §2, orchestrátor-hatáskör) —
a public.dart kikerült, a kör export nélkül teljes; a boundary-teszt lezárt kör
őre, ezért TILOS volt módosítani (H2 lett volna). Helyes döntés.

## 5. Acceptance criteria — tételes bizonyíték

| Kritérium | Bizonyíték | Verdikt |
|---|---|---|
| Practice-result entry | `practice_result_context_adapter_test` „creates a versioned immutable reference" | ✅ |
| Analyze capability-aware entry | `analyze_result_context_adapter_test` `mlDiagnosticsAvailable==false`, `isNot(contains('mlAgreement'))` | ✅ |
| Consent-flow (cloud/off) | card-teszt „uses deterministic debrief when cloud consent is unavailable" | ✅ |
| deleted-result / version-mismatch | card-teszt „shows controlled deleted and version-mismatch states" | ✅ |
| deterministic-fallback | ua. + enum `deterministicFallback` ág | ✅ |
| practice-action (suggested) | card-teszt: `suggestedPracticeStarts==1` a practice-gombra | ✅ |
| **No streak on chat** | statikus őr `isNot(contains('recordPracticeToday'))` + szerkezeti tény (a kártyának nincs streak-csatornája); falszifikációs próba §7 | ✅ |
| Adapter csak public API-t fogyaszt | statikus import-őr mindkét adapter-tesztben (`everyElement … public.dart`) | ✅ |
| Unsupported metric nem claim | analyze-teszt `isNot(contains('mlAgreement'))` | ✅ |

API-ellenőrzés: `downCount`/`upCount` (analyze_result.dart:149–150) és
`TimelineChord.label` (:24) publikus getterek — az adapter csak public felületet olvas.

## 6. Architektúra + termékhatárok

- **public.dart contract:** tiszteletben tartva (nincs export; boundary-teszt zöld). ✅
- **domain-függetlenség / core↛feature:** az adapterek csak `features/{practice,analyze}/public.dart`-ot
  importálnak + intra-feature `tutor_context_snapshot`. Statikus őr méri. ✅
- **Streak-tulajdonlás (ADR 0132 / §0.0):** a streak-írás a deterministic result-úton
  marad (`practice_session_recording.dart:183`, `analyze_providers.dart:226`); az új
  kód sehol nem hív `recordPracticeToday`-t (grep üres az `ai_tutor/`-ban). ✅
- **Lifecycle:** a kártya `TextEditingController`-je `dispose()`-ban felszabadul. ✅
- **Provenance-őr:** `_hasVersion` → verzió nélkül `null` (mindkét adapter tesztelve). ✅

## 7. Falszifikációs próba (valódi-sértés)

Cél: a „no streak on chat" őr tényleg pirosra vált-e egy chat-nyitáskori
streak-mutációra. Próba: a `session_tutor_entry_card.dart`-ba ideiglenesen
`recordPracticeToday` hívást injektálva a statikus őr-teszt
(`entry card cannot mutate practice streaks itself`) PIROSRA vált →
visszaállítva ZÖLD. (Részletes futás alább, a próba a klónban, nem a közös fán.)

## 8. Leletek

| # | Osztály | Fájl:sor | Lelet | Javaslat |
|---|---|---|---|---|
| 1 | MINOR | `practice_result_context_adapter.dart:14`, `analyze_…:15` | Az empty-id (`id.trim().isEmpty → null`) deleted-result guard adapter-szinten TESZTELETLEN (a deleted-result a kártya enum-ágán van fedve). | Follow-up: 1-1 cella üres id-ra `isNull`. |
| 2 | MINOR | `practice_result_context_adapter.dart:23`, `analyze_…:33` | Capability-„jelen" ágak fedetlenek: `highestStableTempoBpm` present és `diagnostics != null → mlDiagnosticsAvailable==true`. | Follow-up: present-branch cellák. |
| 3 | NOTE | `session_tutor_entry_card_test.dart` „chat entry does not change streak" | A `streak==7` widget-assert tautologikus (a kártyának nincs streak-csatornája); a valós őr a statikus source-teszt. | Nincs teendő; a NOTE dokumentálja. |

Egyik lelet sem blokkol (nincs BLOCKER/MAJOR). A MINOR-ok tiszta
teszt-lefedettségi hézagok, korrektségi hibát nem takarnak; follow-up körre
valók, a diffet nem hizlalják itt.

## 9. Verdikt

**APPROVED.** Scope tiszta, acceptance bizonyítva, gate zöld, boundary
tiszteletben. A zöld kapu további elemei (CI exact-SHA) az orchestrátornál.
