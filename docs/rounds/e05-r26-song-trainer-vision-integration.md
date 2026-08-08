# E05-R26 — Song Trainer vision integráció

- **Státusz:** PLANNING (pre-flight lezárva 2026-08-08, kód olvasva: main @ `7c474fa`)
- **SDD-kör:** [`docs/sdd/06-epic-05-computer-vision.md`](../sdd/06-epic-05-computer-vision.md) Kör 26; §26
- **Branch:** `codex/e05-r26-song-trainer-vision-integration`
- **Előfeltétel:** **E05-R24, E05-R25 merge** — teljesült (mindkettő `main`-en).
- **ADR:** [0193](../adr/0193-song-trainer-vision-integration-contract.md) (a
  pre-flightban foglalva és megírva — a brief eredetileg `nincs ÚJ ADR`-t
  írt elő, ld. §0.0 1. pont, miért változott ez).
- **Brief szerzője:** Claude (batch, 2026-08-05) + Claude (pre-flight-revízió,
  2026-08-08) · **Implementáció:** Codex (Terra)

```ai-router
schema_version = 1
risk = "high"
allowed_paths = [
  "lib/features/vision/domain/integration/vision_song_contract.dart",
  "lib/features/vision/domain/integration/public.dart",
  "lib/features/vision/application/vision_cadence_policy.dart",
  "lib/features/song_trainer/data/vision/song_vision_adapter.dart",
  "lib/features/song_trainer/domain/models/song_vision_summary.dart",
  "lib/features/song_trainer/public.dart",
  "lib/features/vision/public.dart",
  "lib/l10n/app_en.arb",
  "lib/l10n/app_hu.arb",
  "test/features/song_trainer/data/song_vision_adapter_test.dart",
  "test/features/song_trainer/performance/transport_timing_parity_test.dart",
  "test/features/vision/application/vision_cadence_policy_test.dart",
  "test/features/vision/domain/integration/vision_integration_barrel_boundary_test.dart",
  "docs/rounds/e05-r26-song-trainer-vision-integration.md",
  "docs/adr/0193-song-trainer-vision-integration-contract.md",
]
gate_tests = [
  "test/features/song_trainer",
  "test/features/vision",
]
native_gate = false
```

> ⚠ **Pre-flight (KÖTELEZŐ, lezárva 2026-08-08 — ld. §0.0 a teljes mért
> listáért):** `origin/main` + E05-R24/R25 merge — teljesült. A Song Trainer
> transport/loop szolgáltatásai **mérve**: `lib/features/song_trainer/
> application/trainer/{song_transport,song_transport_clock,
> song_transport_command,song_transport_state,transport_effect}.dart` +
> `domain/models/loop_config.dart` + `presentation/widgets/
> {transport_controls,loop_controls,song_loop_feedback}.dart` (a brief
> eredeti `.../services/` pointere nem létező útvonalra mutatott — az
> egyetlen `services/` a `domain/services/`, E03 domain-szolgáltatások,
> nincs köze a transporthoz). **A transport timing nem változhat.** **ÚJ ADR
> [0193](../adr/0193-song-trainer-vision-integration-contract.md)** (a
> brief eredeti „Nincs ÚJ ADR (0165 végrehajtása)" állítása felülbírálva —
> az „ADR 0165" sosem létezett fájl; a helyes hivatkozás **ADR 0182**, és a
> pre-flight egy második, önálló döntést is hozott, ld. §0.0 2. pont).
> PREPARED→PLANNING, brief commit megtörtént.

## 0. Kör-jelzés és STOP-protokoll

```bash
tools/codex-signal.sh progress "<egy sor>" ; tools/codex-signal.sh done "<egy sor>"
tools/codex-signal.sh stopped "<egy sor>" ; tools/codex-signal.sh blocked "<egy sor>"
```

Lezáró jelzés nélkül a kör bukott. Listán kívüli fájl → `stopped`.

## 0.0 Tervezési baseline és pre-flight revízió

**Pre-flight lezárva 2026-08-08, orchesztrátor: Claude Sonnet 5.** Az
eredeti (2026-08-05-i) brief két hivatkozása mérve elavultnak bizonyult, és a
HANDOFF.md §3 egy, ezt a kört explicit érintő MINOR biztonsági rést jelölt
meg pre-flight-bemenetként. Teljes indoklás: [ADR 0193](../adr/0193-song-trainer-vision-integration-contract.md).

1. **„ADR 0165" nem létező fájl.** `find docs/adr -iname '*0165*'` → 0
   találat. A brief §5 pont 1 által leírt „audio-elsőbbség" döntés
   ténylegesen **ADR 0182** ("Vision audio-priority degradation", elfogadva
   E05-R01). Minden „ADR 0165" hivatkozás ebben a brief-ben 0182-re javítva.
   (Az E05-R29 brief ugyanezt a hibát tartalmazza — az NEM ezen kör
   scope-ja, follow-up-ként hagyva.)
2. **`vision/public.dart` barrel-szimbólum-rés zárása (E05-R25 dedikált
   security-review MINOR-1, `docs/LESSONS.md` L190, HANDOFF.md §3 — kétszer
   explicit „E05-R26 pre-flightja ELŐTT javítandó").** A wide root barrel
   (`lib/features/vision/public.dart`) domain-safe aggregátumok MELLETT
   nyers landmark/geometry/provider típusokat és UI-screeneket is exportál;
   egyik gépi őr sem korlátozza, MELYIK szimbólumot importálja a fogyasztó.
   Ez a kör nyitja meg a MÁSODIK `<feature> → vision/public.dart` élt
   (`practice → vision` volt az első, E05-R25) — **scope-bővítés, ADR 0193
   Döntés 4–7:** új, szűk, domain-safe nested barrel
   (`lib/features/vision/domain/integration/public.dart`, allowed_paths-hoz
   adva), amit a `song_trainer` új fájljai importálnak a wide barrel
   HELYETT, plusz egy dedikált, forrás-szöveg-alapú regressziós teszt
   (`test/features/vision/domain/integration/
   vision_integration_barrel_boundary_test.dart`, allowed_paths-hoz adva) —
   lásd a bővített §4/§6/§8 lent. A `tool/check_architecture.dart`
   **módosítása NEM része ennek a körnek** (ADR 0193 „Elutasított
   alternatívák" — a nested-barrel mechanizmus már ma is legális cél, ADR
   0176 szerint, nulla módosítással a shared eszközön).
3. **A `lib/features/song_trainer/services/` pre-flight-pointer nem létező
   útvonal volt** — javítva a fenti fejléc-dobozban a mért, tényleges
   transport/loop fájllistára.
4. **ADR-szám: 0193** (`tools/round-slots.py reserve-adr --round E05-R26`).

## 1. Cél

Szakasz- és loop-szintű vision-összegzés a Song Trainerben, **teljesítményvédett**
módban: a dal lejátszása és pontozása elsőbbséget élvez, a vision cadence
igazodik, thermal állapotban pedig audio-only módra vált **a dal megszakítása
nélkül**.

## 2. Jelenlegi állapot (mért, `5d082dc`)

- A Song Trainer V2 él (`lib/features/song_trainer/`: `domain/{models,repositories,
  services}`, `application/{trainer,library,editor,import,migration,progress,setlists}`,
  `data/{audio,playback,importers,local,migration}`, `presentation/`, `public.dart`),
  backing playbackkel, A–B loopokkal és pitch-alapú pontozással (Epic 3,
  E03-R17…R22). A tesztfa tükrözi ezt:
  `test/features/song_trainer/{domain,application,data,presentation,performance,integration,security,baseline}`.
- A `songTrainerV2Enabled` és a `visionSongIntegrationEnabled` flag is OFF.
- Az R24 adja a vision sessiont; a cadence-szabályozás **még nincs** —
  ez a kör vezeti be (a device tier finomhangolása az R29).

## 3. Scope

**Benne:** `VisionSongContract`, `SongVisionAdapter` közös session/section/loop
ID-kkal, loop-iterációnkénti aggregáció (stroke consistency, hand travel),
posture drift **csak hosszabb szakaszon**, `VisionCadencePolicy` (a vision
futási gyakorisága a rendelkezésre álló keret szerint), thermal/terhelés
esetén **audio-only átváltás** a dal megszakítása nélkül, a result-UI
loop-onkénti vision-quality jelzése, **és (pre-flight §0.0 2. pont bővítése) a
`vision/public.dart` barrel-szimbólum-rés zárása egy új, szűk, domain-safe
nested barrellel a Song Trainer felé.**

**Kívül — TILOS:** a transport/timing bármely módosítása, a pontozás
megváltoztatása, device tier benchmark (R29), persistence (R28), Tutor (R27),
a wide `lib/features/vision/public.dart` meglévő exportjainak törlése/
szűkítése, a Practice (E05-R25) meglévő vision-importjának migrálása,
`tool/check_architecture.dart` bármely módosítása (ADR 0193 „Elutasított
alternatívák" — nem szükséges és nem is ezen kör scope-ja).

## 4. Engedélyezett fájlok

| Útvonal | Állapot | Miért |
|---|---|---|
| `.../vision/domain/integration/vision_song_contract.dart` | ÚJ | szűk vision API |
| `.../vision/domain/integration/public.dart` | ÚJ | **(pre-flight bővítés)** szűk, domain-safe nested barrel — ADR 0193 Döntés 4–5; a `song_trainer` EZT importálja, nem a wide `vision/public.dart`-ot |
| `.../vision/application/vision_cadence_policy.dart` | ÚJ | cadence-szabályozás |
| `.../song_trainer/data/vision/song_vision_adapter.dart` | ÚJ | fogyasztó-oldali adapter (az R25 practice-mintája) |
| `.../song_trainer/domain/models/song_vision_summary.dart` | ÚJ | loop/section összegzés |
| `lib/features/song_trainer/public.dart`, `lib/features/vision/public.dart` | meglévő | additív export — **mérve (§0.0): egyik sem szükséges ténylegesen ebben a körben** (ld. ADR 0193 Kontextus 3. pont), az engedély megmarad, de nem kötelező felhasználni |
| `lib/l10n/app_*.arb` | meglévő | **csak additív** kulcs |
| `test/features/song_trainer/*`, `test/features/vision/*` | ÚJ | adapter + parity + cadence |
| `test/features/vision/domain/integration/vision_integration_barrel_boundary_test.dart` | ÚJ | **(pre-flight bővítés)** gépi őr a szűk barrel + a song_trainer import-célja felett — ADR 0193 Döntés 7 |
| `docs/rounds/e05-r26-*.md` | meglévő | §10 handoff |
| `docs/adr/0193-song-trainer-vision-integration-contract.md` | ÚJ | ezt a pre-flightot rögzíti (L188 tanulság: az orchesztrátor-saját ADR-fájlnak KÖTELEZŐ szerepelnie a listán) |

**Tilos zóna:** minden más song_trainer fájl; `lib/core/audio/`; DSP;
`tool/check_architecture.dart`; bármely `lib/features/practice/` fájl (a
wide-barrel migráció NEM ezen kör dolga). Listán kívül → `stopped`.

## 5. Kötött architekturális döntések

1. **A transport timing nem regresszálhat** (ADR 0182: audio-elsőbbség —
   a brief eredeti „ADR 0165" hivatkozása mérve tévesnek bizonyult, nincs
   ilyen fájl; ld. §0.0 1. pont).
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
6. **A Song Trainer nem importál vision-belsőt** — csak `vision/public.dart`
   **VAGY (pre-flight §0.0 2. pont, kötelező ebben a körben) a szűkebb**
   `vision/domain/integration/public.dart` **nested barrel — az ÚJ
   vision-fogyasztó fájlok (`song_vision_adapter.dart` és bármely más új,
   vision-szimbólumot használó song_trainer fájl) KIZÁRÓLAG az utóbbit
   importálják.** ADR 0193 Döntés 5 tételes tiltólistája (könyvtár-prefix
   alapú): a szűk barrel exportja NEM célozhat `domain/landmarks/`,
   `domain/geometry/`, `data/landmarks/`, `presentation/` alá eső fájlt, sem
   a `core/camera/camera_coordinate_space.dart` nyers koordináta-típusait
   (`NormalizedPoint`/`NormalizedRect`). **NEM elfogadható:** a wide
   `vision/public.dart` importja az ÚJ song_trainer fájlokban.

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
- [ ] **(pre-flight bővítés, ADR 0193 Döntés 7) Vision-barrel-boundary őr:**
      `vision_integration_barrel_boundary_test.dart` két cellája —
      (a) az új szűk barrel (`vision/domain/integration/public.dart`)
      `export` direktíváinak egyike sem oldható fel a tiltott könyvtár-
      prefixek (`domain/landmarks/`, `domain/geometry/`, `data/landmarks/`,
      `presentation/`, `core/camera/camera_coordinate_space.dart`) alá;
      (b) a song_trainer új vision-fogyasztó fájljainak import-sorai NEM
      tartalmazzák a `features/vision/public.dart` (wide) célt. **Valódi-sértés
      próba:** egy tiltott export vagy egy wide-barrel import ideiglenes
      visszaállítása → a megfelelő cella PIROS → visszaállítás.

## 7. Kötelező ellenőrzések

```bash
tools/round-gate.sh test/features/song_trainer test/features/vision
```

Külön processzek, nincs `&&`/pipe/`tail`. Az 5 perces valós eszközös
loop-benchmark a device-mátrix **PENDING** sora.

## 8. Implementációs sorrend

1. **(pre-flight bővítés) Szűk vision barrel + boundary-őr ELŐSZÖR:** hozd
   létre `vision/domain/integration/public.dart`-ot (ADR 0193 Döntés 4–5
   tételes re-export/tiltólistája), és a RED boundary-tesztet
   (`vision_integration_barrel_boundary_test.dart`) — ez a lépés még önmagában
   is zöldre fut (a barrel ma helyesen üres/szűk), és attól kezdve minden
   további song_trainer vision-import ezen keresztül megy.
2. RED: transport-parity fixture + thermal-mátrix.
3. `VisionCadencePolicy` (determinisztikus).
4. `SongVisionAdapter` + loop-aggregáció — importja a szűk barrelt (1. lépés),
   NEM a wide `vision/public.dart`-ot.
5. Result-jelzés + ARB; gate.

## 9. Kockázatok

- **A vision munka a fő szálon** észrevétlenül tolja a transportot — a
  parity-fixture azonosságot követel, nem toleranciát.
- **A hiányzó loopok csendes kihagyása** hamis „konzisztens vagy" képet ad;
  a jelölés kötelező.
- **(pre-flight bővítés) A szűk barrel akaratlan visszaszűkülése.** Ha a
  `SongVisionAdapter`-nek olyan típusra van szüksége, ami ma csak a wide
  barrelen át érhető el, és az implementer emiatt visszavált a wide importra:
  ez **nem** brief-sértés automatikusan, de a boundary-teszt (b) cellája
  ezt PIROSRA fogja fordítani — a helyes válasz a hiányzó típus felvétele a
  szűk barrelbe (ha domain-safe), nem a wide import visszaállítása. Ha a
  szükséges típus NEM domain-safe (a tiltólistán van): STOP, dokumentált
  brief-revízió kell, ne kerülő megoldás.

**STOP:** transport-módosítás, kényszerített vision low-tier eszközön vagy a
parity-tolerancia bevezetése helyett dokumentált brief-revízió.

## 10. Implementation handoff — az implementer tölti ki

_(üres)_

## 11. Review — a független reviewer tölti ki

Tervezett review: `docs/reviews/e05-r26-song-trainer-vision-integration-review.md`.
Merge csak exact-SHA zöld CI, §4-en belüli diff és nulla OPEN BLOCKER/MAJOR után.
