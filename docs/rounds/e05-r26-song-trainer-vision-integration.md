# E05-R26 — Song Trainer vision integráció

- **Státusz:** PREPARED (előre megírva 2026-08-05, kód olvasva: main @ `5d082dc`)
- **SDD-kör:** [`docs/sdd/06-epic-05-computer-vision.md`](../sdd/06-epic-05-computer-vision.md) Kör 26; §26
- **Branch:** `codex/e05-r26-song-trainer-vision-integration`
- **Előfeltétel:** **E05-R24, E05-R25 merge**
- **Brief szerzője:** Claude (batch) · **Implementáció:** Codex (Terra)

```ai-router
schema_version = 1
risk = "high"
allowed_paths = [
  "lib/features/vision/domain/integration/vision_song_contract.dart",
  "lib/features/vision/application/vision_cadence_policy.dart",
  "lib/features/song_trainer/services/song_vision_adapter.dart",
  "lib/features/song_trainer/models/song_vision_summary.dart",
  "lib/features/song_trainer/public.dart",
  "lib/features/vision/public.dart",
  "lib/l10n/app_en.arb",
  "lib/l10n/app_hu.arb",
  "test/features/song_trainer/song_vision_adapter_test.dart",
  "test/features/song_trainer/transport_timing_parity_test.dart",
  "test/features/vision/application/vision_cadence_policy_test.dart",
  "docs/rounds/e05-r26-song-trainer-vision-integration.md",
]
gate_tests = [
  "test/features/song_trainer",
  "test/features/vision",
]
native_gate = false
```

> ⚠ **Pre-flight (KÖTELEZŐ):** `origin/main` + E05-R24/R25 merge; olvasd újra a
> Song Trainer transport/loop szolgáltatásait (`lib/features/song_trainer/services/`)
> és a section/loop azonosítók mai alakját. **A transport timing nem változhat.**
> Nincs ÚJ ADR (0165 végrehajtása). PREPARED→PLANNING, brief commit előbb.

## 0. Kör-jelzés és STOP-protokoll

```bash
tools/codex-signal.sh progress "<egy sor>" ; tools/codex-signal.sh done "<egy sor>"
tools/codex-signal.sh stopped "<egy sor>" ; tools/codex-signal.sh blocked "<egy sor>"
```

Lezáró jelzés nélkül a kör bukott. Listán kívüli fájl → `stopped`.

## 0.0 Tervezési baseline és pre-flight revízió

**PREPARED.** Nincs előre kiosztott ADR.

## 1. Cél

Szakasz- és loop-szintű vision-összegzés a Song Trainerben, **teljesítményvédett**
módban: a dal lejátszása és pontozása elsőbbséget élvez, a vision cadence
igazodik, thermal állapotban pedig audio-only módra vált **a dal megszakítása
nélkül**.

## 2. Jelenlegi állapot (mért, `5d082dc`)

- A Song Trainer V2 él (`lib/features/song_trainer/`: `models/`, `services/`,
  `repositories/`, `public.dart`), backing playbackkel, A–B loopokkal és
  pitch-alapú pontozással (Epic 3, E03-R17…R22).
- A `songTrainerV2Enabled` és a `visionSongIntegrationEnabled` flag is OFF.
- Az R24 adja a vision sessiont; a cadence-szabályozás **még nincs** —
  ez a kör vezeti be (a device tier finomhangolása az R29).

## 3. Scope

**Benne:** `VisionSongContract`, `SongVisionAdapter` közös session/section/loop
ID-kkal, loop-iterációnkénti aggregáció (stroke consistency, hand travel),
posture drift **csak hosszabb szakaszon**, `VisionCadencePolicy` (a vision
futási gyakorisága a rendelkezésre álló keret szerint), thermal/terhelés
esetén **audio-only átváltás** a dal megszakítása nélkül, és a result-UI
loop-onkénti vision-quality jelzése.

**Kívül — TILOS:** a transport/timing bármely módosítása, a pontozás
megváltoztatása, device tier benchmark (R29), persistence (R28), Tutor (R27).

## 4. Engedélyezett fájlok

| Útvonal | Állapot | Miért |
|---|---|---|
| `.../vision/domain/integration/vision_song_contract.dart` | ÚJ | szűk vision API |
| `.../vision/application/vision_cadence_policy.dart` | ÚJ | cadence-szabályozás |
| `.../song_trainer/services/song_vision_adapter.dart` | ÚJ | fogyasztó-oldali adapter |
| `.../song_trainer/models/song_vision_summary.dart` | ÚJ | loop/section összegzés |
| `lib/features/song_trainer/public.dart`, `lib/features/vision/public.dart` | meglévő | additív export |
| `lib/l10n/app_*.arb` | meglévő | **csak additív** kulcs |
| `test/features/song_trainer/*`, `test/features/vision/*` | ÚJ | adapter + parity + cadence |
| `docs/rounds/e05-r26-*.md` | meglévő | §10 handoff |

**Tilos zóna:** minden más song_trainer fájl; `lib/core/audio/`; DSP.
Listán kívül → `stopped`.

## 5. Kötött architekturális döntések

1. **A transport timing nem regresszálhat** (ADR 0165: audio-elsőbbség).
   **NEM elfogadható:** a backing playback vagy a scheduling bármely
   módosítása vision miatt — még „egy kis puffer" sem.
2. **Thermal/terhelés esetén audio-only átváltás a dal megszakítása nélkül.**
   A váltás **állapotváltás**, nem hibaág; a felhasználó a dalt végigjátssza.
   **NEM elfogadható:** session-megszakítás vagy modális hibaüzenet.
3. **A vision loop-onként jelzi a saját minőségét** — a result UI megmondja,
   melyik loopban volt elég vision-quality. **NEM elfogadható:** a hiányzó
   loopok csendes kihagyása az aggregátumból magyarázat nélkül.
4. **Posture drift csak a dokumentált minimum szakaszhossz fölött** fut
   (költséges és rövid loopon értelmetlen).
5. **Low-tier eszközön nincs kényszerített vision:** a cadence policy
   `visionDisabled` állapotot is adhat, és ez **nem hiba**.
6. **A Song Trainer nem importál vision-belsőt** — csak `vision/public.dart`.

## 6. Acceptance criteria

- [ ] **Transport-timing parity fixture (a kör kulcsbizonyítéka):** rögzített dal
      + loop-terv → az esemény-idővonal és a pontozás **bitre azonos** vision
      ON és OFF mellett. Tolerancia **nincs** (azonosság), mert a vision nem
      nyúlhat az ütemezéshez.
- [ ] **Loop-aggregáció teszt:** N iteráció → iterációnként egy összegzés,
      a hiányzó quality-jű iterációk **jelölve**, nem eldobva.
- [ ] **Thermal-fake mátrix:** normál / meleg / forró — a második cadence-t
      csökkent, a harmadik audio-only; **egyik sem** szakítja meg a dalt
      (a lejátszás állapota assertálva).
- [ ] **Cadence-teszt:** a policy kimenete determinisztikus a bemeneti
      terhelés-jelzésre, és a **határok két oldala** külön cella.
- [ ] **Posture-küszöb:** a minimum szakaszhossz **alatt / rajta / fölött** —
      az „alatt" cellában a posture drift **nem** fut (hívásszámláló 0).
- [ ] **Architektúra-őr** zöld, allowlist nem bővült; **lokalizációs paritás** zöld.
- [ ] **Valódi-sértés próba (§10):** a cadence policy megkerülése (fix magas
      cadence) → a thermal-mátrix „forró" cellája PIROS → visszaállítás.

## 7. Kötelező ellenőrzések

```bash
tools/round-gate.sh test/features/song_trainer test/features/vision
```

Külön processzek, nincs `&&`/pipe/`tail`. Az 5 perces valós eszközös
loop-benchmark a device-mátrix **PENDING** sora.

## 8. Implementációs sorrend

1. RED: transport-parity fixture + thermal-mátrix.
2. `VisionCadencePolicy` (determinisztikus).
3. `SongVisionAdapter` + loop-aggregáció.
4. Result-jelzés + ARB; gate.

## 9. Kockázatok

- **A vision munka a fő szálon** észrevétlenül tolja a transportot — a
  parity-fixture azonosságot követel, nem toleranciát.
- **A hiányzó loopok csendes kihagyása** hamis „konzisztens vagy" képet ad;
  a jelölés kötelező.

**STOP:** transport-módosítás, kényszerített vision low-tier eszközön vagy a
parity-tolerancia bevezetése helyett dokumentált brief-revízió.

## 10. Implementation handoff — az implementer tölti ki

_(üres)_

## 11. Review — a független reviewer tölti ki

Tervezett review: `docs/reviews/e05-r26-song-trainer-vision-integration-review.md`.
Merge csak exact-SHA zöld CI, §4-en belüli diff és nulla OPEN BLOCKER/MAJOR után.
