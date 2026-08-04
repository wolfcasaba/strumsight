# E04-R21 — Song Trainer debrief és range action integráció

- **Státusz:** PREPARED (előre megírva 2026-08-04, kód olvasva: main @ `fbe1e82`)
- **SDD-kör:** [`docs/sdd/05-epic-04-ai-guitar-teacher.md`](../sdd/05-epic-04-ai-guitar-teacher.md) Kör 21; §35
- **Branch:** `codex/e04-r21-song-trainer-debrief-range-actions`
- **Előfeltétel:** Epic 3 (E03-R22) lezárva; **E04-R10, R20 merge**
- **Brief szerzője:** Claude (batch) · **Implementáció:** Codex (Terra)

```ai-router
schema_version = 1
risk = "high"
allowed_paths = [
  "lib/features/ai_tutor/application/context/adapters/song_result_context_adapter.dart",
  "lib/features/ai_tutor/application/tools/song_tutor_tools.dart",
  "lib/features/ai_tutor/presentation/widgets/song_tutor_entry_card.dart",
  "lib/l10n/app_en.arb",
  "lib/l10n/app_hu.arb",
  "lib/features/ai_tutor/public.dart",
  "test/features/ai_tutor/application/song_result_context_adapter_test.dart",
  "test/features/ai_tutor/application/song_tutor_tools_test.dart",
  "test/features/ai_tutor/presentation/song_tutor_entry_card_test.dart",
  "docs/rounds/e04-r21-song-trainer-debrief-range-actions.md",
]
gate_tests = [
  "test/features/ai_tutor/application",
  "test/features/ai_tutor/presentation",
]
native_gate = false
```

> ⚠ **Pre-flight (KÖTELEZŐ):** `origin/main` + E04-R10/R20 merge; olvasd újra
> `AGENTS.md`, Chapter 1/4/5, `HANDOFF.md`. Nincs ÚJ ADR (R01 0132/0133 bővítése).
> `rg`: a Song Trainer **public** felülete (`lib/features/song_trainer/public.dart`)
> — a `SongPracticeResult`/capability/revision + range mai alakja; a backing-audio +
> teljes lyrics **soha** nem kerül model-contextbe. **ARB gen** a gate előtt.
> PREPARED→PLANNING, brief commit az implementer ELŐTT.

## 0. Kör-jelzés és STOP-protokoll

```bash
tools/codex-signal.sh progress "<egy sor>" ; tools/codex-signal.sh done "<egy sor>"
tools/codex-signal.sh stopped "<egy sor>" ; tools/codex-signal.sh blocked "<egy sor>"
```

Lezáró jelzés nélkül a kör bukott. Listán kívüli fájl/contract → `stopped`.

## 0.0 Tervezési baseline és pre-flight revízió

**PREPARED — a mért §0.0-t az élesedő pre-flight tölti ki.** Nincs előre kiosztott ADR.

## 1. Cél

Section-/measure-szintű dalgyakorlási segítség, validált **A–B loop** és **Speed
Builder** proposal — capability- és revision-aware, audio-feltöltés nélkül.

## 2. Jelenlegi állapot

- Nincs Song-tutor integráció. Az Epic 3 Song Trainer (`song_trainer/public.dart`)
  strukturált eredményt + problémás measure/section adatot ad; R10 tool-rendszer +
  R20 belépő-minta kész.
- **Backing audio + teljes lyrics** soha nem mehet model-contextbe (SDD Kör 21/5).

## 3. Scope

**Benne:** `SongPracticeResult` capability+revision-aware adapter, `getSongSections`
+ `getSongPracticeDetail` tool (R10 read-only), problem-range proposal, rhythm-only/
chord-only/pitch/Speed-Builder action (ahol capability engedi), stale-revision blokk,
missing-asset alternate proposal, exact-range setup-megnyitás confirm után, setlist
per-song context selection.

**Kívül — TILOS:** audio/lyrics model-contextbe, capability-hazugság, stale action
futása, source-belső import.

## 4. Engedélyezett fájlok

| Útvonal | Állapot | Miért |
|---|---|---|
| `.../application/context/adapters/song_result_context_adapter.dart` | ÚJ | Song→context |
| `.../application/tools/song_tutor_tools.dart` | ÚJ | getSections/getDetail tool |
| `.../presentation/widgets/song_tutor_entry_card.dart` | ÚJ | belépő kártya |
| `lib/l10n/app_en.arb`, `app_hu.arb` | meglévő | stringek (additív) |
| `lib/features/ai_tutor/public.dart` | előző körökből | additív export |
| `test/features/ai_tutor/{application,presentation}/*` | ÚJ | adapter/tool/card tesztek |
| `docs/rounds/e04-r21-*.md` | meglévő | §10 handoff |

**Tilos zóna:** minden más fájl, a Song Trainer **belső** contractja, `docs/rag`,
más kör briefje. Listán kívül → `stopped`.

## 5. Kötött architekturális döntések

1. **Backing audio + teljes lyrics soha nem kerül model-contextbe** (ADR 0132).
   **NEM elfogadható:** lyrics/audio részleges átengedése „context céljából".
2. A **capability őszinte** — pitch-scoring nélkül nincs pitch-action; **stale revision
   blokkolja az actiont**.
3. Az action **exact range-gel** nyitja a Song Trainer setupot confirm után (R11).
4. Missing-asset → **alternate proposal**, nem néma hiba.

## 6. Acceptance criteria

- [ ] section-debrief; measure-range; **revision-stale** blokk; missing-asset alternate;
      **unsupported-pitch** (capability=false → nincs pitch-action); speed-action;
      **lyrics-redaction** (audio/lyrics nincs contextben); setlist-selection; route-params exact.
- [ ] **Lyrics/audio redaction:** teszt bizonyítja, hogy a context nem tartalmaz
      backing-audiót/teljes lyricset; reviewer eldobható mutációval (lyrics átengedése)
      pirosra váltja.

## 7. Kötelező ellenőrzések

```bash
tools/round-gate.sh test/features/ai_tutor/application test/features/ai_tutor/presentation
```

Külön processzek, nincs `&&`/pipe/`tail`. ARB-nál `flutter gen-l10n` a gate előtt.
CI = orchestrátor exact-SHA.

## 8. Implementációs sorrend

1. RED redaction + stale + unsupported-capability + exact-range tesztek.
2. Song context-adapter + read-only toolok.
3. entry-card + ARB.
4. `flutter gen-l10n`; gate.

## 9. Kockázatok

- Lyrics/audio szivárgás contextbe (privacy + jog) — redaction-teszt kötelező.
- Capability-hazugság (pitch-action pitch-scoring nélkül) — capability-gate.

**STOP:** audio/lyrics context, capability-hazugság vagy stale-action-futás helyett
dokumentált brief-revízió.

## 10. Implementation handoff — az implementer tölti ki

_(üres)_

## 11. Review — a független reviewer tölti ki

Tervezett review: `docs/reviews/e04-r21-song-trainer-debrief-range-actions-review.md`.
Merge csak exact-SHA zöld CI, §4-en belüli diff és nulla OPEN BLOCKER/MAJOR után.
