# E03-R21 — Trainer UI, loop, Speed Builder és result

- **Státusz:** **PREPARED** (2026-08-01, tervezési baseline: `main` @ `eeb4f6d`)
- **SDD-kör:** [`docs/sdd/04-epic-03-song-trainer.md`](../sdd/04-epic-03-song-trainer.md) Kör 21; §23–24, §27.7–27.10, §28
- **Branch:** `codex/e03-r21-trainer-ui-loop-speed-results`
- **Előfeltétel:** E03-R20 merge
- **Brief szerzője:** Codex · **Implementáció:** Codex vagy a pre-flightban kijelölt agent

```ai-router
schema_version = 1
risk = "high"
allowed_paths = [
  "lib/features/song_trainer/application/trainer/song_progress_committer.dart",
  "lib/features/song_trainer/application/trainer/song_resume_repository.dart",
  "lib/features/song_trainer/application/trainer/song_trainer_controller.dart",
  "lib/features/song_trainer/application/trainer/song_trainer_state.dart",
  "lib/features/song_trainer/presentation/screens/song_trainer_screen.dart",
  "lib/features/song_trainer/presentation/screens/song_result_screen.dart",
  "lib/features/song_trainer/presentation/widgets/chord_lane.dart",
  "lib/features/song_trainer/presentation/widgets/strum_lane.dart",
  "lib/features/song_trainer/presentation/widgets/note_lane.dart",
  "lib/features/song_trainer/presentation/widgets/tablature_lane.dart",
  "lib/features/song_trainer/presentation/widgets/transport_controls.dart",
  "lib/features/song_trainer/presentation/widgets/loop_controls.dart",
  "lib/features/song_trainer/presentation/widgets/measure_heatmap.dart",
  "lib/features/song_trainer/presentation/widgets/song_loop_feedback.dart",
  "lib/features/song_trainer/application/song_trainer_providers.dart",
  "lib/features/practice/public.dart",
  "lib/app/routing/app_router.dart",
  "lib/l10n/app_en.arb",
  "lib/l10n/app_hu.arb",
  "test/features/song_trainer/application/trainer/song_progress_committer_test.dart",
  "test/features/song_trainer/application/trainer/song_resume_repository_test.dart",
  "test/features/song_trainer/presentation/song_trainer_screen_test.dart",
  "test/features/song_trainer/presentation/song_result_screen_test.dart",
  "test/features/song_trainer/presentation/song_trainer_accessibility_test.dart",
  "test/features/song_trainer/integration/song_trainer_lifecycle_test.dart",
  "docs/rounds/e03-r21-trainer-ui-loop-speed-results.md",
]
gate_tests = [
  "test/features/song_trainer/application/trainer/song_progress_committer_test.dart",
  "test/features/song_trainer/application/trainer/song_resume_repository_test.dart",
  "test/features/song_trainer/presentation",
  "test/features/song_trainer/integration/song_trainer_lifecycle_test.dart",
]
native_gate = false
```

> ⚠ **Pre-flight (indítás előtt KÖTELEZŐ):** ellenőrizd az `origin/main` és az
> elődkör merge-jét; olvasd újra az `AGENTS.md`, Chapter 1/3/4,
> `HANDOFF.md`, a releváns ADR-eket és a `docs/LESSONS.md` fájlt. `rg`-vel
> igazold minden útvonal, public symbol, state producer, recorder-input,
> resource owner és numerikus cella mai állapotát. Drift esetén dokumentáld
> §0.0-ban, javítsd a scope/fájllistát, majd commitold a `PLANNING` briefet
> a körbranchre az implementer előtt. A `PREPARED` brief nem futtatható vakon.

## 0. Kör-jelzés és STOP-protokoll

```bash
tools/codex-signal.sh progress "<egy sor>"
tools/codex-signal.sh done "<egy sor>"
tools/codex-signal.sh stopped "<egy sor>"
tools/codex-signal.sh blocked "<egy sor>"
```

Lezáró jelzés nélkül a kör bukott. Az implementer nem hív `gh`-t, nem pushol
és nem nyit PR-t. Listán kívüli fájl, hiányzó public contract/fixture/device,
ellentmondó acceptance vagy megkülönböztetésre alkalmatlan teszt esetén
`stopped`; nincs néma scope-tágítás vagy mércegyengítés.

## 0.0 Tervezési baseline és pre-flight revízió

- R19 chord/rhythm és R20 note scoring, R18 transport rendelkezésre áll.
- Progress végleges repository/Setlist integráció R22-ben zárul; R21 idempotens commit/resume contractot ad.
- Practice Speed Builder csak publikus contracton használható.

A pre-flight minden állítást újramér. Eltérésnél itt rögzíti a mért tényt, a
feloldást és indokát. Üres vagy implicit revízióval nincs `PLANNING` státusz.

## 1. Cél

Windowolt, accessible teljes Song Trainer felület, section/A–B loop, publikus Speed Builder, result/heatmap/problem retry és idempotens resume/progress commit.

## 2. Jelenlegi állapot

- R19 chord/rhythm és R20 note scoring, R18 transport rendelkezésre áll.
- Progress végleges repository/Setlist integráció R22-ben zárul; R21 idempotens commit/resume contractot ad.
- Practice Speed Builder csak publikus contracton használható.

## 3. Scope

**Benne:**

- Trainer/result screen és chord/strum/note/tab lane
- transport, section/measure/A–B loop és per-loop feedback
- Speed Builder, heatmap, problem retry, next section
- idempotens progress adapter és resume checkpoint

**Kívül — ebben a körben TILOS:**

- Setlist V2
- teljes progress/history dashboard átalakítása
- saját Speed Builder policy vagy full-song eager render
- feature flag production rollout

## 4. Engedélyezett fájlok

| Útvonal | Állapot | Miért |
|---|---|---|
| `lib/features/song_trainer/application/trainer/song_progress_committer.dart` | ÚJ | idempotent commit boundary |
| `lib/features/song_trainer/application/trainer/song_resume_repository.dart` | ÚJ | checkpoint contract |
| `lib/features/song_trainer/application/trainer/song_trainer_controller.dart` | R20-ból | loop/result orchestration |
| `lib/features/song_trainer/application/trainer/song_trainer_state.dart` | R19-ből | UI/session state |
| `lib/features/song_trainer/presentation/screens/song_trainer_screen.dart` | ÚJ | trainer shell |
| `lib/features/song_trainer/presentation/screens/song_result_screen.dart` | ÚJ | result |
| `lib/features/song_trainer/presentation/widgets/chord_lane.dart` | ÚJ | windowed chord |
| `lib/features/song_trainer/presentation/widgets/strum_lane.dart` | ÚJ | windowed rhythm |
| `lib/features/song_trainer/presentation/widgets/note_lane.dart` | R20-ból | windowed note |
| `lib/features/song_trainer/presentation/widgets/tablature_lane.dart` | ÚJ | known fret/string |
| `lib/features/song_trainer/presentation/widgets/transport_controls.dart` | ÚJ | controls |
| `lib/features/song_trainer/presentation/widgets/loop_controls.dart` | ÚJ | A–B/section |
| `lib/features/song_trainer/presentation/widgets/measure_heatmap.dart` | ÚJ | accessible result |
| `lib/features/song_trainer/presentation/widgets/song_loop_feedback.dart` | ÚJ | non-blocking feedback |
| `lib/features/song_trainer/application/song_trainer_providers.dart` | R20-ból | wiring |
| `lib/features/practice/public.dart` | R19-ből | Speed Builder public contract, auditált |
| `lib/app/routing/app_router.dart` | meglévő | trainer/result route |
| `lib/l10n/app_en.arb` | meglévő | EN copy |
| `lib/l10n/app_hu.arb` | meglévő | HU copy |
| `test/features/song_trainer/application/trainer/song_progress_committer_test.dart` | ÚJ | idempotency |
| `test/features/song_trainer/application/trainer/song_resume_repository_test.dart` | ÚJ | checkpoint |
| `test/features/song_trainer/presentation/song_trainer_screen_test.dart` | ÚJ | state/lane/a11y |
| `test/features/song_trainer/presentation/song_result_screen_test.dart` | ÚJ | heatmap/CTA |
| `test/features/song_trainer/presentation/song_trainer_accessibility_test.dart` | ÚJ | large/landscape/reduced |
| `test/features/song_trainer/integration/song_trainer_lifecycle_test.dart` | ÚJ | mic/player/re-entry |
| `docs/rounds/e03-r21-trainer-ui-loop-speed-results.md` | meglévő | §10 handoff |

**Tilos zóna:** minden más fájl, más feature belső contractja, más kör briefje
és nem felsorolt CI/docs artefaktum. Új fixture/helper is fájl; listán kívül
→ `stopped`. Cross-feature fájl csak a táblában jelzett publikus boundary
additív exportjára módosítható, a pre-flight exact symbol auditja után.

## 5. Kötött architekturális döntések

1. Lane csak viewport+buffer windowt renderel; teljes dal widgetlistája tilos.
2. Minden loop külön attempt ID/result; terminal callback és progress commit idempotency key alapján egyszeri.
3. Heatmap szín mellett label/icon/text semanticsot ad; screen-reader live feedback throttled.
4. Resume biztonságos időközönként és pause/stopkor; scoring state nem állítható vissza fél attemptként.

E döntések nem lazíthatók azért, hogy egy teszt zöld legyen.

## 6. Acceptance criteria

- [ ] Count-in/playing/paused/completed/error és loop `2/5` állapotok helyes lane/control/effect kombinációt adnak.
- [ ] Section és valid A–B loop működik; invalid range nem indul; loop attempt elkülönül.
- [ ] Backing rate capability hiányában speed disabled indoklással; különben publikus Speed Builder policy fut.
- [ ] Chord/direction/note verdict, accessible measure heatmap, problem range retry és next section működik.
- [ ] Duplicate finalize/re-entry egyszer commitol; resume stabil; route leave/dispose után 0 mic/player/subscription.
- [ ] Left-handed, landscape, 200% text, reduced motion és reader throttling zöld.

### Kötelező megkülönböztető mátrix

| Phase/effect | Loop | Capability | Várt UI/owner |
|---|---|---|---|
| countIn | off | scoring | overlay, mic policy szerint |
| playing | 2/5 | backing rate yes | lanes+loop index+speed |
| paused | A–B | rate no | seek engedett, speed disabled reason |
| completed duplicate callback | any | any | egy result+egy commit |
| route leave/background | any | mic+player | safe pause/close |
| re-entry resume | saved | revision match/mismatch | resume vagy explicit invalidation |

A reviewer legalább egy központi invariánst eldobható mutációval vagy független
reference-számítással pirosra vált; bemásolt zöld output nem önálló evidencia.

## 7. Kötelező ellenőrzések

```bash
tools/round-gate.sh test/features/song_trainer/application/trainer/song_progress_committer_test.dart test/features/song_trainer/application/trainer/song_resume_repository_test.dart test/features/song_trainer/presentation test/features/song_trainer/integration/song_trainer_lifecycle_test.dart
```

Ez az egyetlen lokális záró gate: format → analyze → célzott test →
architecture külön processzekben; nincs `&&`, pipe, `tail` vagy csonkítás.
A full suite + randomizált property + APK CI-t az orchestrátor exact branch
`headSha`-ra indítja. Valódi audio/device mércét CI nem helyettesít.

## 8. Implementációs sorrend

1. Írd meg progress/resume idempotency és lifecycle RED teszteket.
2. Írd meg kombinált UI state, windowing és accessibility RED teszteket.
3. Implementáld a commit/resume boundaryt és controller loop/result state-et.
4. Implementáld a windowolt lane/control/result widgeteket és public Speed Builder integrációt.
5. Kösd be route/l10n, futtasd a gate-et és device lifecycle checklistet.

Javasolt commit: `feat(song-trainer): add loops speed building results and coaching UI`.

## 9. Kockázatok

- Terminal callback több producerből érkezhet; egyetlen authoritative commit owner kell.
- Windowing teszt csak kis dallal nem különbözteti meg eager rendert; long-song child-count mérés szükséges.
- Semantics túl gyakori update-je használhatatlanná teszi a screen readert.

**STOP:** listán kívüli javítás, bizonyítatlan fallback, belső cross-feature
import vagy gyengített mérce helyett dokumentált brief-revízió szükséges.

## 10. Implementation handoff — az implementer tölti ki

A kör még nem indult; nincs implementációs vagy tesztsiker-állítás. Végrehajtáskor
ide kerül a fájlonkénti összefoglaló, tényleges parancs/kimenet, eltérés,
nem futtatott ellenőrzés és follow-up. Minden viselkedési állításhoz konkrét
teszt vagy mérés tartozik.

## 11. Review — a független reviewer tölti ki

Tervezett review: `docs/reviews/e03-r21-trainer-ui-loop-speed-results-review.md`.
Merge csak exact-SHA zöld CI, §4-en belüli diff és nulla OPEN BLOCKER/MAJOR után.
