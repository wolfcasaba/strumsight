# E03-R18 — SongTransport és backing playback

- **Státusz:** **PREPARED** (2026-08-01, tervezési baseline: `main` @ `eeb4f6d`)
- **SDD-kör:** [`docs/sdd/04-epic-03-song-trainer.md`](../sdd/04-epic-03-song-trainer.md) Kör 18; §19–20
- **Branch:** `codex/e03-r18-transport-backing-playback`
- **Előfeltétel:** E03-R17 merge
- **Brief szerzője:** Codex · **Implementáció:** Codex vagy a pre-flightban kijelölt agent

```ai-router
schema_version = 1
risk = "high"
allowed_paths = [
  "lib/features/song_trainer/application/trainer/song_transport.dart",
  "lib/features/song_trainer/application/trainer/song_transport_state.dart",
  "lib/features/song_trainer/application/trainer/song_transport_command.dart",
  "lib/features/song_trainer/application/trainer/transport_effect.dart",
  "lib/features/song_trainer/application/trainer/song_transport_clock.dart",
  "lib/features/song_trainer/data/playback/backing_audio_player.dart",
  "lib/features/song_trainer/data/playback/playback_capabilities.dart",
  "lib/features/song_trainer/data/playback/local_backing_audio_player.dart",
  "lib/features/song_trainer/data/playback/fake_backing_audio_player.dart",
  "lib/features/song_trainer/application/song_trainer_providers.dart",
  "docs/baseline/epic-03-backing-drift-benchmark.md",
  "test/features/song_trainer/application/trainer/song_transport_test.dart",
  "test/features/song_trainer/application/trainer/song_transport_lifecycle_test.dart",
  "test/features/song_trainer/data/playback/backing_audio_player_test.dart",
  "test/features/song_trainer/data/playback/backing_drift_test.dart",
  "docs/rounds/e03-r18-transport-backing-playback.md",
]
gate_tests = [
  "test/features/song_trainer/application/trainer/song_transport_test.dart",
  "test/features/song_trainer/application/trainer/song_transport_lifecycle_test.dart",
  "test/features/song_trainer/data/playback",
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

- R03 SongTimeMap és R17 range/config rendelkezésre áll.
- Közös audio lifecycle/session coordinator használata kötelező; concrete package pre-flight auditált.
- Driftküszöb benchmark nélkül nem rögzíthető találomra.

A pre-flight minden állítást újramér. Eltérésnél itt rögzíti a mért tényt, a
feloldást és indokát. Üres vagy implicit revízióval nincs `PLANNING` státusz.

## 1. Cél

Scoring- és UI-mentes, monotonic, explicit transport state machine és cserélhető backing player adapter lifecycle-safe szinkronnal.

## 2. Jelenlegi állapot

- R03 SongTimeMap és R17 range/config rendelkezésre áll.
- Közös audio lifecycle/session coordinator használata kötelező; concrete package pre-flight auditált.
- Driftküszöb benchmark nélkül nem rögzíthető találomra.

## 3. Scope

**Benne:**

- transport phase/state/command/effect/reducer/controller
- monotonic clock és fake clock
- BackingAudioPlayer/Capabilities, concrete adapter és fake
- grid offset, position sample, drift report/resync, interruption cleanup

**Kívül — ebben a körben TILOS:**

- scoring és microphone observation
- trainer lane/UI
- lejátszás közbeni rate change az első verzióban
- automatikus hangos resume interruption után

## 4. Engedélyezett fájlok

| Útvonal | Állapot | Miért |
|---|---|---|
| `lib/features/song_trainer/application/trainer/song_transport.dart` | ÚJ | orchestration |
| `lib/features/song_trainer/application/trainer/song_transport_state.dart` | ÚJ | explicit phase/state |
| `lib/features/song_trainer/application/trainer/song_transport_command.dart` | ÚJ | commands |
| `lib/features/song_trainer/application/trainer/transport_effect.dart` | ÚJ | effects |
| `lib/features/song_trainer/application/trainer/song_transport_clock.dart` | ÚJ | monotonic clock |
| `lib/features/song_trainer/data/playback/backing_audio_player.dart` | ÚJ | adapter contract |
| `lib/features/song_trainer/data/playback/playback_capabilities.dart` | ÚJ | explicit capability |
| `lib/features/song_trainer/data/playback/local_backing_audio_player.dart` | ÚJ | plugin adapter |
| `lib/features/song_trainer/data/playback/fake_backing_audio_player.dart` | ÚJ | deterministic fake |
| `lib/features/song_trainer/application/song_trainer_providers.dart` | R17-ből | production wiring |
| `docs/baseline/epic-03-backing-drift-benchmark.md` | ÚJ | threshold evidence |
| `test/features/song_trainer/application/trainer/song_transport_test.dart` | ÚJ | transition/effect |
| `test/features/song_trainer/application/trainer/song_transport_lifecycle_test.dart` | ÚJ | dispose/interruption |
| `test/features/song_trainer/data/playback/backing_audio_player_test.dart` | ÚJ | adapter/capability |
| `test/features/song_trainer/data/playback/backing_drift_test.dart` | ÚJ | boundary matrix |
| `docs/rounds/e03-r18-transport-backing-playback.md` | meglévő | §10 handoff |

**Tilos zóna:** minden más fájl, más feature belső contractja, más kör briefje
és nem felsorolt CI/docs artefaktum. Új fixture/helper is fájl; listán kívül
→ `stopped`. Cross-feature fájl csak a táblában jelzett publikus boundary
additív exportjára módosítható, a pre-flight exact symbol auditja után.

## 5. Kötött architekturális döntések

1. Engedélyezett transition exact pártábla; tranzitív reachability nem elégséges mérce.
2. Active position kizárólag monotonic clock anchor; wall time metadata, UI frame és player stream nem master clock.
3. Stop idempotens; más invalid transition stabil failure, nem silent no-op.
4. Speed csak ready/paused; interruption safe pause, explicit user resume.

E döntések nem lazíthatók azért, hogy egy teszt zöld legyen.

## 6. Acceptance criteria

- [ ] Minden Chapter 4 transition-pár és minden tiltott pár tesztelt; chained command a bejárt `phasePath`-ot mérhetővé teszi.
- [ ] Prepare/play/pause/seek/restart/finish/stop-stop/dispose determinisztikus fake clockkal.
- [ ] Missing asset, unsupported codec/rate, prepare/decode hiba stabil state+effect, leak nélkül.
- [ ] Grid offset és drift alatta/rajta/fölötte benchmarkolt resync policyt ad.
- [ ] Background/route/audio interruption után player/subscription/timer lezár vagy paused; nincs auto loud resume.

### Kötelező megkülönböztető mátrix

| Előző phase | Command | Várt phase/effect |
|---|---|---|
| idle | prepare | preparing / prepare asset |
| ready | start | countIn vagy playing |
| playing | seek | seeking / pause+seek+anchor |
| paused | setSpeed | paused / rate+anchor |
| playing | setSpeed | controlled failure |
| stopping/idle | stop | idle, egyszeri vagy no-op idempotens |

| Származtatott `abs(sample-master)` | Várt |
|---:|---|
| threshold−ε | tolerál |
| threshold | kötött boundary policy |
| threshold+ε | safe resync |

A reviewer legalább egy központi invariánst eldobható mutációval vagy független
reference-számítással pirosra vált; bemásolt zöld output nem önálló evidencia.

## 7. Kötelező ellenőrzések

```bash
tools/round-gate.sh test/features/song_trainer/application/trainer/song_transport_test.dart test/features/song_trainer/application/trainer/song_transport_lifecycle_test.dart test/features/song_trainer/data/playback
```

Ez az egyetlen lokális záró gate: format → analyze → célzott test →
architecture külön processzekben; nincs `&&`, pipe, `tail` vagy csonkítás.
A full suite + randomizált property + APK CI-t az orchestrátor exact branch
`headSha`-ra indítja. Valódi audio/device mércét CI nem helyettesít.

## 8. Implementációs sorrend

1. Mérd a backing adapter capabilityt/driftet és dokumentáld a baseline-t.
2. Írd meg az exact transition-pártábla, phasePath és lifecycle RED teszteket.
3. Implementáld a pure state/effect/clock magot.
4. Implementáld a fake és concrete playback adaptert, majd grid/drift policyt.
5. Kösd be production providerrel, futtasd a gate-et és device evidence-t jelöld külön.

Javasolt commit: `feat(song-transport): add deterministic playback and backing sync`.

## 9. Kockázatok

- Playback package streamje late eventet ad dispose után; operation/generation guard kell.
- Benchmark nélküli threshold hamis stabilitást ad; STOP.
- A player lease ownership összekeveredhet a mic lease-szel; külön, auditált lifecycle.

**STOP:** listán kívüli javítás, bizonyítatlan fallback, belső cross-feature
import vagy gyengített mérce helyett dokumentált brief-revízió szükséges.

## 10. Implementation handoff — az implementer tölti ki

A kör még nem indult; nincs implementációs vagy tesztsiker-állítás. Végrehajtáskor
ide kerül a fájlonkénti összefoglaló, tényleges parancs/kimenet, eltérés,
nem futtatott ellenőrzés és follow-up. Minden viselkedési állításhoz konkrét
teszt vagy mérés tartozik.

## 11. Review — a független reviewer tölti ki

Tervezett review: `docs/reviews/e03-r18-transport-backing-playback-review.md`.
Merge csak exact-SHA zöld CI, §4-en belüli diff és nulla OPEN BLOCKER/MAJOR után.
