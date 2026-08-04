# E03-R17 — Song Overview, track/range választás és setup

- **Státusz:** **PLANNING** (pre-flight lezárva 2026-08-04, tervezési baseline: `main` @ `4c51009`; eredeti PREPARED 2026-08-01 @ `eeb4f6d`)
- **ADR:** [`0125`](../adr/0125-song-trainer-setup-configuration-boundary.md) — Song Trainer setup configuration boundary (a pre-flightban írva)
- **SDD-kör:** [`docs/sdd/04-epic-03-song-trainer.md`](../sdd/04-epic-03-song-trainer.md) Kör 17; §23–24, §27.4, §27.6
- **Branch:** `codex/e03-r17-overview-track-range-setup`
- **Előfeltétel:** E03-R16 merge
- **Brief szerzője:** Codex · **Implementáció:** Codex vagy a pre-flightban kijelölt agent

```ai-router
schema_version = 1
risk = "normal"
allowed_paths = [
  "lib/features/song_trainer/domain/models/trainer_range.dart",
  "lib/features/song_trainer/domain/models/loop_config.dart",
  "lib/features/song_trainer/domain/models/trainer_config.dart",
  "lib/features/song_trainer/application/trainer/song_trainer_setup_controller.dart",
  "lib/features/song_trainer/application/trainer/song_trainer_setup_state.dart",
  "lib/features/song_trainer/presentation/screens/song_overview_screen.dart",
  "lib/features/song_trainer/presentation/screens/trainer_setup_screen.dart",
  "lib/features/song_trainer/presentation/widgets/song_section_list.dart",
  "lib/features/song_trainer/presentation/widgets/song_track_picker.dart",
  "lib/features/song_trainer/presentation/widgets/trainer_range_picker.dart",
  "lib/features/song_trainer/presentation/widgets/tuning_capo_reminder.dart",
  "lib/app/routing/app_route.dart",
  "lib/app/routing/app_router.dart",
  "lib/l10n/app_en.arb",
  "lib/l10n/app_hu.arb",
  "test/features/song_trainer/domain/trainer_range_test.dart",
  "test/features/song_trainer/application/trainer/song_trainer_setup_controller_test.dart",
  "test/features/song_trainer/presentation/song_overview_screen_test.dart",
  "test/features/song_trainer/presentation/trainer_setup_screen_test.dart",
  "docs/rounds/e03-r17-overview-track-range-setup.md",
]
gate_tests = [
  "test/features/song_trainer/domain/trainer_range_test.dart",
  "test/features/song_trainer/application/trainer/song_trainer_setup_controller_test.dart",
  "test/features/song_trainer/presentation/song_overview_screen_test.dart",
  "test/features/song_trainer/presentation/trainer_setup_screen_test.dart",
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

- R05 capability report és R15 Library/R16 Editor navigation rendelkezésre áll.
- A trainer controller még nem indul; setup immutable configot ad át a későbbi R19-nek.
- Missing asset javítás csak belépési pont, teljes repair workflow nem tágíthatja a kört.

A pre-flight minden állítást újramér. Eltérésnél itt rögzíti a mért tényt, a
feloldást és indokát. Üres vagy implicit revízióval nincs `PLANNING` státusz.

### Pre-flight revízió (mért 2026-08-04, baseline `main` @ `4c51009`, orchestrátor: Claude/Opus 4.8)

**R1 — Hiányzó route-katalógus owner (scope-javítás).** Az Overview és a
Trainer Setup képernyő két új GoRouter route-ot igényel. A
`test/tooling/route_literal_guard_test.dart` gépi őr **minden** route-string-
literált tilt a `lib/app/routing/app_route.dart` katalóguson kívül; a route-
konstansok (`AppRoutes`) itt élnek. Az eredeti allowlist csak az
`app_router.dart` wiringet engedte, a katalógust nem — így a két új route nem
regisztrálható a `route_literal_guard` pirosra váltása nélkül. **Feloldás:**
pontosan a mért, architektúra által kényszerített `lib/app/routing/app_route.dart`
felvétele az `allowed_paths`-ba (ADR 0125 §Következmények). Ez az E03-R14/R15/R16
pre-flight owner-kiegészítés mintája; lista-tágítás helyett a hiányzó
kötelező owner pótlása. Az implementer a két konstanst (`songTrainerOverview`,
`songTrainerSetup`, mindkettő `:songId` path-paraméterrel) az `AppRoutes`
katalógusba írja, a route-okat a meglévő `if (songTrainerEnabled)` blokkba.

**R2 — Provider-elhelyezés (nincs scope-tágítás).** A song_trainer controller-
providerek konvenció szerint a `song_trainer_providers.dart`-ban központosulnak
(`songImportControllerProvider`, `songLibraryControllerProvider`,
`songEditorControllerProvider`). Mért tény: a `tool/check_architecture.dart` csak
a core→feature és a cross-feature-public-API szabályt kényszeríti (NEM a
provider-központosítást), és a presentation már ma is közvetlenül importál
application-controllert (`song_editor_screen.dart` → `song_editor_controller.dart`).
**Döntés:** a `songTrainerSetupControllerProvider` a saját, engedélyezett
`song_trainer_setup_controller.dart`-ban co-located. **A capability nem
provider-injektált** — a `SongValidator` és a `SongCapabilityResolver`
tiszta, `const`-konstruálható domain service (`const SongValidator()`,
`const SongCapabilityResolver()`), amelyet a controller **közvetlenül
példányosít**; ezekhez nincs és nem is kell provider. A controller EGYETLEN
provider-függősége a **már létező** `songRepositoryProvider`, amelyet
intra-feature importtal olvas és `repository.get(SongId)`-vel tölti be a
`SongDocument`-et, majd `SongValidator().validate(doc)` →
`SongCapabilityResolver().resolve(report:, profile: SongCapabilityProfile.trainer)`
láncon számol capabilityt. A `song_trainer_providers.dart` NEM módosul — annak
szerkesztése listán kívüli → `stopped`. (Feloldva az E03-R17 első
implementer-STOP-ját, `36059ad`: az eredeti R2 megfogalmazás félreérthetően
„resolver providert" említett; nincs ilyen provider, és nem is kell.)

**R3 — Capability-modell mért alakja (unreachable-status szabály).** A
`SongCapabilityReport` (ADR 0114) ma **csak** `chord` + `pitch` scoring-tengelyt
hordoz, plusz `canPersist/canImportPreview/canExport/canTrain`. Nincs rhythm/strum
scoring-mező és nincs backing playback-rate capability-mező. Következmények a §6
mátrixra, a mért előállító inputokkal:
- `chord` oszlop: `report.chord.scoring` — hamis ⟺ `SongValidationCode.chordUnsupported`
  warning. Enabled ⟺ nincs ilyen warning.
- `pitch` oszlop mono/poly: `report.pitch.scoring` / `isMonophonic` — hamis ⟺
  `SongValidationCode.notePolyphonic` warning (polyphonic → `disabled+reason`).
- „rhythm enabled" (strum/chord/note): **strukturális**, a sealed track-altípus
  jelenléte (`ChordTrack`/`StrumTrack`/`NoteTrack`) + `canTrain` adja; nincs
  capability-warning, ami lefokozná. A track-kind olvasása NEM „nyers eventből
  következtetés" (kötött döntés 1) — a track-altípus explicit szerkezeti jelzés.
- „backing/speed (playback-rate)" oszlop: a „supported" állapotnak **nincs
  előállító inputja** R17-ben (backing-rate capability = R18). Ezért minden
  playback-rate kontroll feltétel nélkül `honest-unavailable/pending`
  (kötött döntés 3). A cél-speed **érték** (SDD §10.5, **50%–150%**) mint
  konfig felvehető; a backing tényleges rate-realizációja R18-ig nem
  hirdethető támogatottként.
- „missing backing asset": különálló jelzés — feloldatlan `BackingAudioTrack.assetId`
  a repositoryn; scoringot nem töröl, csak a backing-kontrollt tiltja + a
  javítási flow belépési pontját adja (teljes repair NEM tágít).

**R4 — Erőforrás-tulajdonlás (rule #2): N/A ebben a körben.** Nincs
lease/lock/handle/subscription megszerzés — a trainer controller nem indul
(transport/playback/mic = R18+, scope-on kívül). A setup csak olvas
(repository) és egyetlen immutábilis `TrainerConfig`-ot ad tovább. Mérve:
egyetlen R17 rétegre sincs `.acquire(`/mic/transport tulajdonlás rendelve.

**R5 — Range-határok (mért).** `SongSection.startMeasure` /
`endMeasureExclusive` (end **exclusive**, `endMeasureExclusive > startMeasure`
validált); `SongMeasure.index ≥ 0`; a measure-szám =
`SongDocument.measures.length`. A TrainerRange full/section/measure az inkluzív
UI-kijelölést exclusive domain-végre képezi és `[0, measures.length)` közé
zárja; az utolsó measure csak `end == measures.length` esetén kerül bele
(off-by-one a §9 kockázat — explicit mapping-cellák).

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
| `lib/app/routing/app_route.dart` | meglévő | overview/setup route-konstans (`route_literal_guard` kényszer) |
| `lib/app/routing/app_router.dart` | meglévő | overview/setup route regisztráció |
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

**Állapot: IMPLEMENTED (2026-08-04).**

- **Domain:** `TrainerRange` full/section/measure/bookmark választást kezel;
  a UI inkluzív vége exclusive domain-véggé alakul, dalhatáron kívüli vagy
  revízióban elavult bookmark nem fogadható el. `LoopConfig` és
  `TrainerConfig` egyetlen immutábilis handoff értéket ad, a tuning és capo
  beállításával együtt.
- **Application:** a co-located setup controller kizárólag
  `songRepositoryProvider`-t olvas. A lánc ténylegesen
  `repository.get(id)` → `SongDocument` → `const SongValidator().validate` →
  `const SongCapabilityResolver().resolve(...trainer)`; a `SongDocument` nem
  kerül a state-be és nem módosul. A chord/rhythm/pitch mátrix capability-,
  illetve explicit track-altípus alapon dönt; backing-rate minden esetben
  honest `pending`.
- **Presentation és route:** elkészült az Overview, a Setup, section/track/
  range/tuning-capo widgetek és a két flag-gated `AppRoutes` route. A missing
  backing entry csak jelzés + repair CTA; teljes repair és playback nem része
  a körnek. A Resume CTA producer hiányában rejtett marad.
- **Localization/accessibility:** minden új UI-copy EN/HU ARB-ból jön;
  RadioGroup kezeli a fókusz- és billentyűzetes választást, tiltott módok
  indokot kapnak, a Setup `ListView` 200% text scale mellett scrollozható.
- **RED bizonyíték:** a kezdeti `trainer_range_test.dart` a hiányzó domain
  contracttal piros volt; a controller és widget tesztek az akkor még hiányzó
  model/controller/screen importokkal pirosak voltak. A bookmark revision
  regresszió a hiányzó `matchesSong` contracttal szintén RED volt.
- **Futtatott ellenőrzések:** `tools/prepare-flutter-generated.sh`,
  `flutter gen-l10n`, célzott `flutter test` (8 teszt zöld), `flutter analyze`
  (No issues found), `git diff --check` (tiszta). A teljes CI/property/APK és
  az exact-head dispatch az orchestrátor feladata; lokális APK build nem
  futott (a kör szabálya tiltja).
- **Záró gate:** a §7 pontos `tools/round-gate.sh …` hívása a végső source/test
  diffre lefutott: format 787 fájl / 0 változás, analyze `No issues found`, a
  négy teszt-útvonal zöld, architecture zöld (exit 0).

## 11. Review — a független reviewer tölti ki

Tervezett review: `docs/reviews/e03-r17-overview-track-range-setup-review.md`.
Merge csak exact-SHA zöld CI, §4-en belüli diff és nulla OPEN BLOCKER/MAJOR után.
