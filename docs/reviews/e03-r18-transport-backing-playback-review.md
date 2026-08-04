# Review — E03-R18 SongTransport és backing playback

- **Verdict:** **CHANGES REQUESTED** (1 MAJOR)
- **Branch:** `codex/e03-r18-transport-backing-playback`
- **Reviewed HEAD:** `e573deb`
- **Engine:** codex (gpt-5.6-terra) · **Reviewer:** Claude (Opus 4.8), read-only
- **Dátum:** 2026-08-04
- **Brief:** [`docs/rounds/e03-r18-transport-backing-playback.md`](../rounds/e03-r18-transport-backing-playback.md) · **ADR:** [0126](../adr/0126-song-transport-backing-playback-boundary.md)

## 1. Gate — független újrafuttatás (izolált `/tmp` klón)

`git clone --branch codex/e03-r18-... → /tmp/review-e03-r18`, majd a gitignore-olt
generált l10n helyreállítása (`tools/prepare-flutter-generated.sh`) UTÁN:

```
tools/round-gate.sh test/.../trainer/song_transport_test.dart \
  test/.../trainer/song_transport_lifecycle_test.dart test/.../data/playback
→ format ZÖLD · analyze ZÖLD · test(×3) ZÖLD · architecture ZÖLD · GATE_EXIT=0
```

Megjegyzés: a klón ELSŐ gate-futása 700 `AppLocalizations`/l10n hibával pirosolt,
mert a friss klón nem tartalmazza a gitignore-olt generált l10n-t; ez klón-setup,
NEM R18-kódhiba. A `prepare-flutter-generated.sh` után a gate zöld. A teljes
suite + property + APK a CI-ban (`build-apk.yml`, run 30903001263, `headSha=e573deb`).

## 2. Scope-audit

`git diff --stat 28166fe...e573deb` — mind a 16 érintett fájl a brief §4
engedélyezett listáján. Listán kívüli fájl: **nincs**. Tilos zóna (audio
coordinator, `AudioOwner` enum, más feature belső contractja): **érintetlen**
(`grep` a playback+trainer kódon: nincs `AudioSessionCoordinator`/`.acquire(`/
`AudioOwner`). ✓

## 3. Acceptance criteria — tételes

| # | Kritérium | Bizonyíték | Állapot |
|---|---|---|---|
| 1 | Minden transition-pár + tiltott pár tesztelt; `phasePath` mérhető | `song_transport_test.dart:37-97` minden (from,to) párt explicit halmaz ellen mér; `phasePath` több teszten ellenőrizve | ✓ |
| 2 | prepare/play/pause/seek/restart/finish/stop-stop/dispose fake clockkal | `song_transport_test.dart:99-155` teljes szekvencia; stop-stop idempotens (`stopCalls==1`) | ✓ |
| 3 | Missing asset / unsupported codec+rate / prepare hiba stabil state+effect, leak nélkül | prepare-failure teszt (`:209-229`); `local_backing_audio_player.dart` unsupportedFormat/missingAsset/unsupportedRate/unsupportedSeek | ✓ |
| 4 | Grid offset + drift alatta/rajta/fölötte benchmarkolt resync | `backing_drift_test.dart` threshold−ε/threshold/threshold+ε (51 ms = 3×17 ms); benchmark-doc citálja az audioplayers `FramePositionUpdater`-t | ⚠ **részleges — MAJOR-01: csak speed=1-en helyes** |
| 5 | Background/route/audio interruption → pause/lezár, nincs auto loud resume | `song_transport_lifecycle_test.dart:29-67` háttér→paused, foreground nem resume-ol (playCalls marad 1); route/audio interruption→paused, `microphoneLeaseRequests==0` | ✓ |

## 4. Leletek

### MAJOR-01 — az aktív/master pozíció nem skálázódik `speed`-del (nem-egységnyi tempónál a drift/musical pozíció hibás)

- **Hol:** `lib/features/song_trainer/application/trainer/song_transport.dart:498-503`
  (`_activePositionNow`): `return _anchorPosition + (clock.elapsed - _anchorElapsed);`
- **Mi:** az aktív pozíció (song/musical idő) a monoton óra deltájából **speed-faktor
  nélkül** származik. `speed != 1` esetén a song-idő fal-óra ütemben halad, miközben a
  backing média-pozíció `speed×` ütemben — így (a) a `state.activePosition` és a
  `state.musicalPosition` (`timeMap.positionAt(activePosition)`) hibás, és (b) egy
  tökéletesen szinkron backing minta a `_onPlayerEvent` drift-számításában hamis, nagy
  driftként jelenik meg és **minden position eventnél `hardResync`-et vált ki** →
  a backing audiót folyamatosan előre seek-eli, tönkretéve a lejátszást.
- **Miért számít:** az R17 setup a backing playback-**rate** capabilityt őszinte
  `pending`-ként jelöli; e kör célja (HANDOFF §6) épp ennek felerősítése. A 0.5–1.5×
  tempó az R17 támogatott konfigurációs értéke, amely a transportba folyik
  (`SetSongTransportSpeed` → `player.setRate`). A pozíció/drift a kör KÖZPONTI
  deliverable-je (§5.2 „active position … monotonic clock anchor", §6 acc. #4).
- **Mérés (eldobható próba, izolált klónban, jelentés után törölve):** prepare →
  `SetSongTransportSpeed(0.5)` (ready) → start → `clock.advance(1s)`:
  - `state.activePosition` — **elvárt 500 ms, MÉRT 1000 ms** (RED)
  - `player.emitPosition(500ms)` (0 grid offset, tökéletes szinkron) → drift action —
    **elvárt `tolerate`, MÉRT `hardResync`** (RED)
  Mindkét próba pirosra váltott a jelenlegi kódon; a bug valós, nem elméleti.
- **Miért csúszott át a gate-en:** egyetlen teszt sem lépteti az órát nem-egységnyi
  speed alatt playing fázisban — a pozíció/drift összes `clock.advance` ellenőrzése
  (`song_transport_test.dart:122-123,235-237,256-258`, `backing_drift_test.dart:83`)
  speed=1. Zöld gate ≠ tartalmi hűség (`docs/LESSONS.md` L21).
- **Javasolt irány (NEM kész patch):** a `_activePositionNow` deltáját skálázd
  `_state.speed`-del (`(clock.elapsed - _anchorElapsed) * _state.speed`); a re-anchor
  `_setSpeed`/pause/seek pontokon már megvan. **Adj GUARD tesztet**, amely a hibát
  pirosra fogta volna: nem-egységnyi speed melletti `activePosition` és egy szinkron
  minta `tolerate` drift-actionja. A speed=1 tesztek a fix után is zöldek maradnak (×1).

## 5. Architektúra / termékhatárok

- **Audio-erőforrás (ADR 0126 döntés 3):** a backing player saját
  `audioplayers.AudioPlayer` handle-t birtokol; **nem** szerez mic lease-t. A
  `songTransportProvider` (autoDispose) a read-only `appLifecycleEventsProvider`-t
  fogyasztja, és `onDispose`-ban lezárja a transportot/playert. ✓
- **Master clock:** `StopwatchSongTransportClock` (monoton); a player pozíció-stream
  kizárólag drift-mérésre, nem master clock (§5.2). ✓
- **Dispose/late-event guard:** minden `await` után `_disposed` ellenőrzés;
  `_emitEffect`/`_setState` guardolt; a lifecycle-teszt bizonyítja, hogy dispose után
  egy késői position event nem mutálja a state-et. ✓
- **Benchmark-metodológia (§0.0/b):** a baseline-doc a `positionPrecision=17 ms`-t az
  audioplayers `FramePositionUpdater` forrás-soraival citálja, a küszöböt annak 3×-ában
  vezeti le, és az on-device jittert EXPLICIT `pending`-ként jelöli. ✓ nincs fabrikáció.

## 6. MINOR / NOTE

- **NOTE:** `_setSpeed` `ready` fázisban nem re-anchorol — helyes, mert a `ready`
  órája nem fut és az activePosition 0; a fix után is korrekt marad.
- **NOTE:** a transition-tábla teszt exact pár-halmaz ellen mér (nem tranzitív) — a
  §5.1 kötött döntést pontosan tükrözi.

## 7. Merge-döntés

MAJOR-01 nyitva → **merge TILOS**. Javító kör ugyanezzel a motorral (codex), a
findings-listával; a fix után a review frissül és a CI újra-dispatchelődik (kód
változott). A záró zöld kapu (format+analyze+architecture+full CI+property+APK)
és a nulla OPEN BLOCKER/MAJOR feltétel változatlan.
