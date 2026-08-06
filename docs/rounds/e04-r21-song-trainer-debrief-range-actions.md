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
> `rg`: a Song Trainer **public** felülete (`lib/features/song_trainer/domain/public.dart`)
> — **struktúra + capability** (`SongDocument`/`SongSection`/`SongMeasure`/
> `SongCapabilityReport`); a backing-audio + teljes lyrics **soha** nem kerül
> model-contextbe. **ARB gen** a gate előtt. PREPARED→PLANNING, brief commit az
> implementer ELŐTT.
>
> 🔧 **ÖNJAVÍTVA (ADR 0112 önjavító kör, 2026-08-06 — halt H3):** az eredeti brief
> központi bemenete (publikus practice-**result** + `TrainerRange` + range-fogadó
> setup-route) **nem létezik** a public boundaryn, és az `allowed_paths` egyetlen
> song_trainer fájlt sem tartalmaz → a §6 9 pontjából 6 nem építhető a TILOS zóna
> (song_trainer belső contract + app routing) érintése nélkül. A kör a §0.0
> döntése szerint a **már-publikus struktúra + capability + redaction** szeletre
> szűkül; a halasztott 6 pont a prerekvizit körhöz kerül (lásd §0.0).

## 0. Kör-jelzés és STOP-protokoll

```bash
tools/codex-signal.sh progress "<egy sor>" ; tools/codex-signal.sh done "<egy sor>"
tools/codex-signal.sh stopped "<egy sor>" ; tools/codex-signal.sh blocked "<egy sor>"
```

Lezáró jelzés nélkül a kör bukott. Listán kívüli fájl/contract → `stopped`.

## 0.0 Tervezési baseline és pre-flight revízió

**ÖNJAVÍTÓ SCOPE-REVÍZIÓ (ADR 0112, 2026-08-06 — halt H3).** Mért gyökérok
(`grep -n export lib/features/song_trainer/public.dart
lib/features/song_trainer/domain/public.dart`; `grep -rn "SongPracticeResult" lib test`
→ 0 találat; `grep -rn "songTrainerSetup\|TrainerSetupScreen(" lib/app/routing`
→ csak `songId`): a public boundary **struktúrát + capabilityt** exportál
(`SongDocument`, `SongSection`, `SongMeasure`, `SongTrack`, `SongCapabilityReport`),
de **semmilyen practice-resultot/range-et nem**. A valódi result/range/setlist
típusok (`SongTrainerResult`, `SongPracticeRecord`, `TrainerRange`/`MeasureRange`,
`SongSetlist`) csak a feature **belsejében** léteznek, és az `allowed_paths` egyetlen
song_trainer fájlt sem enged — kitételük a TILOS zónát (song_trainer belső contract
+ app routing) érintené, amit a §4/§5 kifejezetten tilt.

**Döntés:** az R21 a **már-publikus, source-belső import nélkül építhető** szeletre
szűkül (§6): (1) struktúra-debrief section/measure szinten a publikus
`SongDocument`-ből, (2) capability-gate (`SongCapabilityReport` — nincs pitch/chord
scoring → nincs az adott axis action), (3) lyrics/backing **redaction**. Nincs ÚJ ADR.

**Halasztva (prerekvizit kör kell — song_trainer-oldali additív export + ADR):**
practice-result debrief, measure-range A–B loop, revision-stale-on-result,
missing-asset alternate, exact-range setup-route (routing-változás), setlist-selection.
Ezek addig **nem** épülnek, amíg egy külön kör a song_trainer public boundaryn
additívan ki nem teszi a result/range/setlist felületet (saját ADR-rel a
song_trainer oldalon). A jelen re-scope-ot a `tools/tests/test_r21_brief_public_boundary.py`
mért regressziós teszt zárolja.

## 1. Cél

Section-/measure-szintű **struktúra-debrief** dalgyakorláshoz, **capability-őszinte**
tutor-context és szigorú **lyrics/backing-redaction** — a Song Trainer **publikus
struktúra + capability** felületéből, source-belső import és audio-feltöltés nélkül.

## 2. Jelenlegi állapot

- Nincs Song-tutor integráció. Az Epic 3 Song Trainer publikus domain-boundaryja
  (`song_trainer/domain/public.dart`) **struktúrát** (`SongDocument`/`SongSection`/
  `SongMeasure`/`SongTrack`) + **capabilityt** (`SongCapabilityReport`) ad; R10
  tool-rendszer + R20 belépő-minta kész. A `SongTrainerContextAdapter`
  doc-commentje kimondja: „Song Trainer exposes no scoring result publicly" →
  a practice-result/range felület **nem** publikus (lásd §0.0 halt H3).
- **Backing audio + teljes lyrics** soha nem mehet model-contextbe (SDD Kör 21/5).

## 3. Scope

**Benne:** capability-aware **struktúra**-adapter a publikus `SongDocument`-ből
(`SongSection`/`SongMeasure` debrief), `getSongSections` read-only tool (R10),
capability-gate (`SongCapabilityReport` pitch/chord scoring=false → nincs pitch/
chord-action), lyrics/backing **redaction** a contextből, belépő-kártya.

**Kívül — TILOS:** audio/lyrics model-contextbe, capability-hazugság, source-belső
import; **továbbá** (halt H3 miatt, prerekvizit körig halasztva): practice-result
debrief, measure-range/A–B loop, revision-stale, missing-asset alternate,
exact-range setup-route, setlist-selection.

## 4. Engedélyezett fájlok

| Útvonal | Állapot | Miért |
|---|---|---|
| `.../application/context/adapters/song_result_context_adapter.dart` | ÚJ | Song→context |
| `.../application/tools/song_tutor_tools.dart` | ÚJ | `getSongSections` read-only tool (struktúra) |
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
2. A **capability őszinte** — pitch-scoring nélkül nincs pitch-action, chord-scoring
   nélkül nincs chord-action (`SongCapabilityReport`).
3. **Csak a publikus struktúra + capability** felület fogyasztható; source-belső
   import TILOS. A practice-result/range/route felület halt H3 miatt halasztva (§0.0).

## 6. Acceptance criteria

- [ ] **section-debrief** a publikus `SongDocument`-ből (section/measure struktúra,
      scoring-result nélkül); **unsupported-pitch** (`SongCapabilityReport.pitch.scoring`
      =false → nincs pitch-action); **unsupported-chord** (chord scoring=false → nincs
      chord-action); **lyrics-redaction** (audio/lyrics nincs a contextben).
- [ ] **Lyrics/audio redaction:** teszt bizonyítja, hogy a context nem tartalmaz
      backing-audiót/teljes lyricset; reviewer eldobható mutációval (lyrics átengedése)
      pirosra váltja.
- [ ] **Halasztva (prerekvizit körig, §0.0):** measure-range/A–B loop, revision-stale,
      missing-asset alternate, speed-action, setlist-selection, exact route-params —
      ezek **nem** épülnek ebben a körben.

## 7. Kötelező ellenőrzések

```bash
tools/round-gate.sh test/features/ai_tutor/application test/features/ai_tutor/presentation
```

Külön processzek, nincs `&&`/pipe/`tail`. ARB-nál `flutter gen-l10n` a gate előtt.
CI = orchestrátor exact-SHA.

## 8. Implementációs sorrend

1. RED redaction + unsupported-pitch/chord capability-gate + struktúra-debrief tesztek.
2. Publikus-struktúra context-adapter + `getSongSections` read-only tool.
3. entry-card + ARB.
4. `flutter gen-l10n`; gate.

## 9. Kockázatok

- Lyrics/audio szivárgás contextbe (privacy + jog) — redaction-teszt kötelező.
- Capability-hazugság (pitch-action pitch-scoring nélkül) — capability-gate.

**STOP:** audio/lyrics context, capability-hazugság vagy stale-action-futás helyett
dokumentált brief-revízió.

## 10. Implementation handoff — az implementer tölti ki

- **Szállítva:** `SongResultContextAdapter` a Song Trainer domain publikus
  struktúrájából section/measure debrief-contextet készít; a capability report
  alapján csak a ténylegesen score-olható chord/pitch javaslatokat teszi bele.
  A context és a `getSongSections` read-only tool nem ad át lyrics-, backing
  audio-, asset-, source- vagy track-event adatot. A `SongTutorEntryCard`
  strukturális összefoglalót mutat, és a nem score-olható axishez nem renderel
  actiont.
- **Acceptance → teszt:** `song_result_context_adapter_test.dart` méri a
  section/measure-projekciót, a pitch/chord capability gate-et, a lyric/backing
  redactiont és a kizárólagos public-domain importot. `song_tutor_tools_test.dart`
  méri a kizárólag strukturális `getSongSections` outputot, az invalid-input
  elutasítását és a public-domain importot. `song_tutor_entry_card_test.dart`
  méri a score-olhatatlan actionök hiányát, a támogatott axisek megjelenését és
  a presentation redactiont.
- **Futtatva:** `flutter gen-l10n`; a három új célzott teszt együtt → 10 zöld;
  `tools/round-gate.sh test/features/ai_tutor/application
  test/features/ai_tutor/presentation` → format, analyze, mindkét célzott
  test-suite és architecture zöld.
- **Eltérés / nem futtatott ellenőrzés:** a teljes CI `flutter test`, property
  gate és exact-SHA CI workflow az orchestrátor feladata. A §0.0-ban halasztott
  practice-result/range/route/setlist felülethez nem készült implementáció.

## 11. Review — a független reviewer tölti ki

Tervezett review: `docs/reviews/e04-r21-song-trainer-debrief-range-actions-review.md`.
Merge csak exact-SHA zöld CI, §4-en belüli diff és nulla OPEN BLOCKER/MAJOR után.
