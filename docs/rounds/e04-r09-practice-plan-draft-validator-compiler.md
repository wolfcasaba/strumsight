# E04-R09 — PracticePlanDraft, validator és compiler

- **Státusz:** PLANNING (pre-flight mérve 2026-08-05, main @ `92fc3ad`; §0.0 kitöltve)
- **SDD-kör:** [`docs/sdd/05-epic-04-ai-guitar-teacher.md`](../sdd/05-epic-04-ai-guitar-teacher.md) Kör 9; §35
- **Branch:** `codex/e04-r09-practice-plan-draft-validator-compiler`
- **Előfeltétel:** Epic 3 (E03-R22) lezárva; **E04-R03 + E04-R04 merge**
- **Brief szerzője:** Claude (batch) · **Implementáció:** Codex (Terra)

```ai-router
schema_version = 1
risk = "high"
allowed_paths = [
  "lib/features/ai_tutor/domain/models/practice_plan_draft.dart",
  "lib/features/ai_tutor/domain/models/practice_plan_block.dart",
  "lib/features/ai_tutor/domain/services/practice_plan_validator.dart",
  "lib/features/ai_tutor/application/planning/practice_plan_compiler.dart",
  "test/features/ai_tutor/domain/practice_plan_validator_test.dart",
  "test/features/ai_tutor/application/practice_plan_compiler_test.dart",
  "docs/rounds/e04-r09-practice-plan-draft-validator-compiler.md",
]
gate_tests = [
  "test/features/ai_tutor/domain",
  "test/features/ai_tutor/application",
]
native_gate = false
```

> ⚠ **Pre-flight (KÖTELEZŐ):** `origin/main` + E04-R03/R04 merge; olvasd újra
> `AGENTS.md`, Chapter 1/5, `HANDOFF.md`. Nincs ÚJ ADR (R01 0133 tool-confirmation
> bővítése). `rg`: a Practice + Song Trainer **public** compiler/definition felülete
> (`lib/features/{practice,song_trainer}/public.dart`) — a compiler csak publikus
> API-ra épít. PREPARED→PLANNING, brief commit az implementer ELŐTT.

## 0. Kör-jelzés és STOP-protokoll

```bash
tools/codex-signal.sh progress "<egy sor>" ; tools/codex-signal.sh done "<egy sor>"
tools/codex-signal.sh stopped "<egy sor>" ; tools/codex-signal.sh blocked "<egy sor>"
```

Lezáró jelzés nélkül a kör bukott. Listán kívüli fájl/contract → `stopped`.

## 0.0 Tervezési baseline és pre-flight revízió

**Mérve az orchestrátor pre-flightban (main @ `92fc3ad`, E04-R08 merge után;
a brief eredetileg `fbe1e82` ellen íródott).** Előfeltétel teljesül: E04-R03
(`06ae3f7`) + E04-R04 (`0d7ab1b`) merge-elve. Négy mért döntés:

**D1 — Compiler-reachability + parity (a §1.2 „tényleges hívási lánc" mérés).**
A brief §3/§5.3 „Practice + Song Trainer compiler-adapter, bit-stabil parity a
Practice/**Song** compilerrel" azt feltételezi, hogy MINDKÉT compiler publikus.
**Mérve — hamis a Song oldalra:**
- Publikus compiler CSAK a Practice: `lib/features/practice/public.dart` →
  `compilePracticeTarget({required PracticeDefinition definition, required
  PracticeSessionConfig config}) → AppResult<CompiledPracticeTarget>`
  (+ `PracticeDefinition`, `PracticeEvent`, `Tempo`, `Meter`,
  `PracticeSessionConfig`, `PracticeMode`).
- A Song Trainer compilere **source-internal**: `song_trainer/public.dart`
  KIZÁRÓLAG két screent exportál; `SongPracticeCompiler`, `SongDocument`,
  `TrainerConfig` az `application/trainer/`, `domain/models/` alatt zárt.
  **A compiler ezekre nem épülhet — kívülre esés `stopped`** (§9 megerősítve).
- A publikusan elérhető „song" a **`songs` feature** `songs/public.dart` →
  `Song` (id/name/`chords` bar-onként/`pattern` strum/`bpm`/`beatsPerBar`/
  `toLesson()`).

**Feloldás (nem lista-tágítás, §1 szabály):** MINDKÉT block-adapter — a
Practice-target- és a song-block — a **közös publikus** `compilePracticeTarget`-en
át fordul (a `SongPracticeCompiler` mintáját követve, amely maga is csak
`practice/public.dart`-ot importál). A song-block a publikus `Song`-ból épít
`PracticeDefinition`-t, majd ugyanazon a publikus compileren fordul. A
**compiler-parity = bit-stabil egyenlőség a `compilePracticeTarget` kimenetével**
mindkét block-fajtára — NEM egy második, Song-Trainer-belső compiler ellen.
`missing song` = a hivatkozott `Song` id nincs a publikus katalógusban → invalid,
stabil kóddal. Az offline-runnable jelzés a `Song` lokalitásából adódik (a
publikus `Song`-nak nincs külső assetje ⇒ true; asset-hiányos block ⇒ false).

**D2 — Engedélyezett-lista SZŰKÍTÉS (ADR 0087 §2, autonómián belül).**
A `lib/features/ai_tutor/public.dart` **eltávolítva** az engedélyezett listáról
és a TOML `allowed_paths`-ból; **ÜRESEN MARAD**. Ok: a lezárt E04-R01
`ai_tutor_boundary_test.dart` **nulla-export invariánsa** bármely exporttól
pirosra váltana, és e körnek **nincs hívója** (a launch R11, az UI R19
fogyasztja). Precedens: R02–R08 mind ezt tette. A compiler a más-feature
`public.dart`-jait IMPORTÁLJA (megengedett kereszt-feature minta) — ez nem
export az `ai_tutor` boundaryn.

**D3 — Nincs ÚJ ADR.** A kör az **ADR 0133** (tool-confirmation:
write/launch action csak preview+confirm után; „invalid draft nem indíthat
sessiont") + SDD §35 realizálása. A legmagasabb ADR 0136; szám-infláció
elkerülése a R03–R08 precedens szerint. Az „invalid-draft-cannot-launch" kapu =
a compiler érvénytelen draftból NEM állít elő indítható compilationt.

**§1.1 input→státusz (greenfield validator).** `invalid`-ot produkál: listán
kívüli block-type / tempo tartományon kívül / hiányzó song id / tuning-mismatch
/ user-avoid ütközés / capability-skill kapu — mind **stabil kóddal**. Minden
ellenőrzés zöld ⇒ `valid`; **csak `valid` draft fordítható/indítható.**

**§1.2 erőforrás-tulajdonlás: N/A** — pure validator + pure compiler-adapter,
nincs lease/lock/handle/`.acquire()` (mérve: `grep -rn "\.acquire(" lib/features/ai_tutor/` üres, nincs mic/audio a scope-ban).

## 1. Cél

AI által **javasolható**, de teljesen **validált és végrehajtható** gyakorlási terv
domain — invalid draft soha nem indíthat navigációt.

## 2. Jelenlegi állapot

- Nincs tutor practice-plan domain (SDD §3.2/9); a Practice/Song compiler a
  `public.dart`-on át elérhető (E02-R06 target-compiler, E03-R19 song-compiler).
- R03 után van user avoid-lista/goal, R04 után skill-becslés — a validáció bemenete.

## 3. Scope

**Benne:** `PracticePlanDraft` + `PracticePlanBlock`, támogatott block-type allowlist,
idő/tempo/tuning/skill/capability-validáció, determinisztikus template-generátor
(5/10/20/30 perc), Practice + Song Trainer compiler-adapter, invalid-draft-nem-indít
kapu, stabil validációs kódok, user-edit utáni újravalidálás, offline-runnable jelzés.

**Kívül — TILOS:** UI (R19), cloud, tényleges launch (R11), source-belső import.

## 4. Engedélyezett fájlok

| Útvonal | Állapot | Miért |
|---|---|---|
| `.../domain/models/practice_plan_draft.dart` | ÚJ | plan modell |
| `.../domain/models/practice_plan_block.dart` | ÚJ | block modell + allowlist |
| `.../domain/services/practice_plan_validator.dart` | ÚJ | pure validator |
| `.../application/planning/practice_plan_compiler.dart` | ÚJ | Practice/Song adapter (§0.0 D1: közös publikus `compilePracticeTarget`) |
| `test/features/ai_tutor/{domain,application}/*` | ÚJ | validator/compiler tesztek |
| `docs/rounds/e04-r09-*.md` | meglévő | §10 handoff |

**Tilos zóna:** minden más fájl, más feature belső contractja, `docs/rag`,
más kör briefje. Listán kívül → `stopped`.

## 5. Kötött architekturális döntések

1. **Invalid draft nem fordítható/indítható** — a compiler csak validált tervet
   ad tovább (ADR 0133). **NEM elfogadható:** „figyelmeztetéssel mégis indít".
2. A validator **pure**; a block-type **allowlist** zárt.
3. A plan teljes ideje **egzakt** a kért időkeretre; a compiler-parity a
   **közös publikus** `compilePracticeTarget` kimenetével bit-stabil (§0.0 D1 —
   Song Trainer-belső compiler NINCS a scope-ban, kívülre esés `stopped`).
4. Az offline-runnable jelzés **pontos** (minden asset lokális ⇒ true).

## 6. Acceptance criteria

- [ ] **Duration mátrix:** 5/10/20/30 perc → a blokkok összege pontosan a keret
      (alatta/rajta/fölötte cellák, géppel számítva).
- [ ] Unsupported block / tempo out-of-range / missing song / tuning mismatch /
      user-avoid → **invalid**, stabil kóddal; **invalid draft cannot launch** teszt.
- [ ] Compiler-parity: mindkét block-adapter (Practice-target + song) a közös
      publikus `compilePracticeTarget` kimenetével **bit-stabil** (§0.0 D1);
      user-edit után újravalidál.
- [ ] Offline-runnable jelzés pontos (asset-hiány → false).

A reviewer az invalid-draft-kaput eldobható mutációval (invalid mégis compile-ol)
pirosra váltja.

## 7. Kötelező ellenőrzések

```bash
tools/round-gate.sh test/features/ai_tutor/domain test/features/ai_tutor/application
```

Külön processzek, nincs `&&`/pipe/`tail`. CI = orchestrátor.

## 8. Implementációs sorrend

1. RED duration-mátrix + invalid-launch + parity tesztek.
2. Draft/block modellek + allowlist.
3. Pure validator + compiler-adapterek.
4. Additív export; gate.

Javasolt commit: `feat(ai-tutor-plans): add validated practice plan generation contracts`.

## 9. Kockázatok

- A compiler csábítható source-belső típusra — csak public API; kívülre esés `stopped`.
- Duration-kerekítés: egész-perc blokk-összeg egzakt a kerettel (E02-R06 egyszeri-
  kerekítés minta).

**STOP:** invalid-launch, source-belső import vagy mércegyengítés helyett
dokumentált brief-revízió.

## 10. Implementation handoff — az implementer tölti ki

### Megvalósítás

- `practice_plan_draft.dart`: immutable draft és determinisztikus 5/10/20/30
  perces sablonok, pontos blokk-összeggel.
- `practice_plan_block.dart`: zárt block-type allowlist, adapter-referencia,
  capability-, skill-, tuning- és asset-adatok; a domain csak stabil ID-ket és
  primitív értékeket tart.
- `practice_plan_validator.dart`: pure, stabil kódos validáció időkeretre,
  típusra, tempóra, hivatkozott Practice-target/song ID-ra, tuningra,
  avoid-listára, capabilityre és skillre.
- `practice_plan_compiler.dart`: application-szintű context feloldja a publikus
  Practice-targetot és `Song`-ot, majd mindkét adapter a publikus
  `compilePracticeTarget(...)` híváson fordul. A hibás draftból nincs compiled
  plan; az asset-hiányos, egyébként valid terv offline jelzője `false`.
- A két új tesztfájl a duration-mátrixot, stabil validációs kódokat,
  user-edit utáni revalidációt, invalid-launch kaput, mindkét adapter
  compiler-parityjét és offline jelzőt méri.

### Futtatott ellenőrzések

- `flutter gen-l10n` — lefutott; a generált, gitignore-olt l10n fájlok
  build-előfeltételként készültek.
- RED: `flutter test test/features/ai_tutor/domain/practice_plan_validator_test.dart test/features/ai_tutor/application/practice_plan_compiler_test.dart`
  — a még hiányzó contractok miatt piros.
- GREEN: ugyanez a célzott teszt — `14` teszt zöld.
- `tools/round-gate.sh test/features/ai_tutor/domain test/features/ai_tutor/application`
  — exit `0`; format, analyze, domain+application tesztek és architecture zöld.

### Eltérés és nem futtatott ellenőrzések

- A domain-purity gate miatt a más-feature publikus típusainak feloldása az
  application compilerbe került; a domain nem importál cross-feature contractot.
  Ez megőrzi a §0.0 D1 közös publikus compiler-hívását.
- Teljes suite, property gate és APK build nem futott lokálisan: ezek a brief
  szerint CI/orchestrátor feladatai.

## 11. Review — a független reviewer tölti ki

Tervezett review: `docs/reviews/e04-r09-practice-plan-draft-validator-compiler-review.md`.
Merge csak exact-SHA zöld CI, §4-en belüli diff és nulla OPEN BLOCKER/MAJOR után.
