# E03-R17 — Song Overview, track/range választás és setup

- **Státusz:** **PREPARED** (2026-08-01, tervezési baseline: `main` @ `eeb4f6d`)
- **SDD-kör:** [`docs/sdd/04-epic-03-song-trainer.md`](../sdd/04-epic-03-song-trainer.md) Kör 17; §23–24, §27.4, §27.6
- **Branch:** `codex/e03-r17-overview-track-range-setup`
- **Előfeltétel:** E03-R16 merge
- **Brief szerzője:** Codex · **Implementáció:** Codex vagy a pre-flightban kijelölt agent

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

- R05 capability report és R15 Library/R16 Editor navigation rendelkezésre áll.
- A trainer controller még nem indul; setup immutable configot ad át a későbbi R19-nek.
- Missing asset javítás csak belépési pont, teljes repair workflow nem tágíthatja a kört.

A pre-flight minden állítást újramér. Eltérésnél itt rögzíti a mért tényt, a
feloldást és indokát. Üres vagy implicit revízióval nincs `PLANNING` státusz.

## 1. Cél

A dal és capabilityk érthető áttekintése, valid track/range/config kiválasztás és scoringot őszintén kapuzó Trainer Setup létrehozása.

## 2. Jelenlegi állapot

- R05 capability report és R15 Library/R16 Editor navigation rendelkezésre áll.
- A trainer controller még nem indul; setup immutable configot ad át a későbbi R19-nek.
- Missing asset javítás csak belépési pont, teljes repair workflow nem tágíthatja a kört.

## 3. Scope

**Benne:**

- TrainerRange, LoopConfig alap és TrainerConfig value object
- setup controller/state validáció
- Overview, section list, track picker és Trainer Setup UI
- speed/count-in/metronome/loop/mode/tuning/capo/resume/missing-asset entry

**Kívül — ebben a körben TILOS:**

- transport és playback
- Practice session/scoring
- A–B live loop interaction és Result UI
- SongDocument módosítása setupból

## 4. Engedélyezett fájlok

| Útvonal | Állapot | Miért |
|---|---|---|
| `lib/features/song_trainer/domain/models/trainer_range.dart` | ÚJ | full/section/measure/bookmark |
| `lib/features/song_trainer/domain/models/loop_config.dart` | ÚJ | setup loop alap |
| `lib/features/song_trainer/domain/models/trainer_config.dart` | ÚJ | immutable config |
| `lib/features/song_trainer/application/trainer/song_trainer_setup_controller.dart` | ÚJ | capability/config validation |
| `lib/features/song_trainer/application/trainer/song_trainer_setup_state.dart` | ÚJ | setup state |
| `lib/features/song_trainer/presentation/screens/song_overview_screen.dart` | ÚJ | overview |
| `lib/features/song_trainer/presentation/screens/trainer_setup_screen.dart` | ÚJ | setup |
| `lib/features/song_trainer/presentation/widgets/song_section_list.dart` | ÚJ | section picker |
| `lib/features/song_trainer/presentation/widgets/song_track_picker.dart` | ÚJ | track/capability |
| `lib/features/song_trainer/presentation/widgets/trainer_range_picker.dart` | ÚJ | range |
| `lib/features/song_trainer/presentation/widgets/tuning_capo_reminder.dart` | ÚJ | reminder |
| `lib/app/routing/app_router.dart` | meglévő | overview/setup route |
| `lib/l10n/app_en.arb` | meglévő | EN copy |
| `lib/l10n/app_hu.arb` | meglévő | HU copy |
| `test/features/song_trainer/domain/trainer_range_test.dart` | ÚJ | range invariáns |
| `test/features/song_trainer/application/trainer/song_trainer_setup_controller_test.dart` | ÚJ | capability/config |
| `test/features/song_trainer/presentation/song_overview_screen_test.dart` | ÚJ | overview states |
| `test/features/song_trainer/presentation/trainer_setup_screen_test.dart` | ÚJ | widget/a11y |
| `docs/rounds/e03-r17-overview-track-range-setup.md` | meglévő | §10 handoff |

**Tilos zóna:** minden más fájl, más feature belső contractja, más kör briefje
és nem felsorolt CI/docs artefaktum. Új fixture/helper is fájl; listán kívül
→ `stopped`. Cross-feature fájl csak a táblában jelzett publikus boundary
additív exportjára módosítható, a pre-flight exact symbol auditja után.

## 5. Kötött architekturális döntések

1. Capability report az egyetlen scoring-mode enablement forrás; widget nem következtet nyers eventből.
2. Range end exclusive és measure/song határon validált; setup nem mutál documentet.
3. Speed tartomány Chapter 4 szerint, backing rate capability csak R18 után erősíthető, addig őszinte unavailable/pending.
4. Polyphonic note track pitch scoring disabled, rhythm/display fallback magyarázattal.

E döntések nem lazíthatók azért, hogy egy teszt zöld legyen.

## 6. Acceptance criteria

- [ ] Full song, section, inclusive UI→exclusive domain measure range és bookmark validálható.
- [ ] Chord-only, strum, monophonic, polyphonic, backing és missing-asset konfigurációk helyes control állapotot adnak.
- [ ] Unsupported mode disabled és indokolt; valid setup egyetlen immutable configot ad.
- [ ] Tuning/capo reminder és resume CTA feltételesen, szemantikailag helyesen jelenik meg.
- [ ] 200% text scale, landscape/fókusz és HU/EN zöld; setup után SongDocument equality változatlan.

### Kötelező megkülönböztető mátrix

| Track/capability | Chord/rhythm | Pitch | Backing/speed |
|---|---|---|---|
| chord-only supported | enabled | disabled | asset szerint |
| strum-only | rhythm enabled | disabled | asset szerint |
| monophonic notes | rhythm + pitch enabled | enabled | asset szerint |
| polyphonic notes | rhythm/display | disabled+reason | asset szerint |
| missing backing asset | scoring marad | capability szerint | disabled+repair |
| unsupported codec/rate | scoring marad | capability szerint | play/rate külön disabled |

A reviewer legalább egy központi invariánst eldobható mutációval vagy független
reference-számítással pirosra vált; bemásolt zöld output nem önálló evidencia.

## 7. Kötelező ellenőrzések

```bash
tools/round-gate.sh test/features/song_trainer/domain/trainer_range_test.dart test/features/song_trainer/application/trainer/song_trainer_setup_controller_test.dart test/features/song_trainer/presentation/song_overview_screen_test.dart test/features/song_trainer/presentation/trainer_setup_screen_test.dart
```

Ez az egyetlen lokális záró gate: format → analyze → célzott test →
architecture külön processzekben; nincs `&&`, pipe, `tail` vagy csonkítás.
A full suite + randomizált property + APK CI-t az orchestrátor exact branch
`headSha`-ra indítja. Valódi audio/device mércét CI nem helyettesít.

## 8. Implementációs sorrend

1. Írd meg a range/config és capability matrix RED tesztjeit.
2. Írd meg a combined widget/re-entry/a11y RED teszteket.
3. Implementáld a pure modelleket és setup controllert.
4. Implementáld az Overview/Setup widgeteket capability-driven állapottal.
5. Kösd be route/l10n réteget és futtasd a gate-et.

Javasolt commit: `feat(song-ui): add song overview and trainer setup`.

## 9. Kockázatok

- Inclusive UI range off-by-one-ja utolsó measure-t elveszíthet; explicit mapping cellák kellenek.
- R18 playback capability még nincs; pre-flight nem találhat ki támogatást.
- Resume producer csak R21-ben készülhet; addig injektált optional contract vagy hidden CTA.

**STOP:** listán kívüli javítás, bizonyítatlan fallback, belső cross-feature
import vagy gyengített mérce helyett dokumentált brief-revízió szükséges.

## 10. Implementation handoff — az implementer tölti ki

A kör még nem indult; nincs implementációs vagy tesztsiker-állítás. Végrehajtáskor
ide kerül a fájlonkénti összefoglaló, tényleges parancs/kimenet, eltérés,
nem futtatott ellenőrzés és follow-up. Minden viselkedési állításhoz konkrét
teszt vagy mérés tartozik.

## 11. Review — a független reviewer tölti ki

Tervezett review: `docs/reviews/e03-r17-overview-track-range-setup-review.md`.
Merge csak exact-SHA zöld CI, §4-en belüli diff és nulla OPEN BLOCKER/MAJOR után.
