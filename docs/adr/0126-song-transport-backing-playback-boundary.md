# ADR 0126 — SongTransport és backing playback adapter határa

**Státusz:** elfogadva (E03-R18 pre-flight, 2026-08-04, tervezési baseline
`main` @ `f6b2a04`). Épít az [ADR 0125](0125-song-trainer-setup-configuration-boundary.md)
setup-config határára (a backing-rate ott `honest-pending`; ez a kör hozza a
tényleges realizációt) és az R03 SongTimeMap idő-térképére. Kör-brief:
[`docs/rounds/e03-r18-transport-backing-playback.md`](../rounds/e03-r18-transport-backing-playback.md).

## Kontextus

Az E03-R18 hozza be a Song Trainer scoring- és UI-mentes transport-magját: egy
monoton, explicit állapotgépet (prepare/play/pause/seek/restart/finish/stop) és
egy cserélhető backing-audio player adaptert lifecycle-safe szinkronnal. A
pre-flight mért állapot behatárolja a döntéseket:

- **A megosztott `AudioSessionCoordinator` kizárólag mikrofon-erőforrás.** A
  `lib/core/audio/lifecycle/audio_session_coordinator.dart` doc-commentje és az
  `AudioOwner` enum (`lib/core/audio/lifecycle/audio_session_lease.dart`:
  `live, tuner, analyzeRecorder, latencyCalibration, diagnostics`) szerint a
  lease „the right to use the microphone", egyszerre pontosan egy tulajdonossal.
  A mic lease-t ma egyetlen hely szerzi meg: `mic_capture.dart:82`
  (`_coordinator.acquire(...)`). A backing player audio-**kimenet**, nem
  mikrofon-fogyasztó; nincs playback `AudioOwner` érték, és az enum a kör
  **tilos zónájában** van.
- **A monoton óra új absztrakció.** A meglévő
  `ClockSupplier = DateTime Function()` (`song_trainer_providers.dart:61`)
  fal-óra (wall time), amit a §5.2 kötött döntés kizár master clockként. A
  transport master órája új `song_transport_clock.dart` (Stopwatch-alapú
  monoton), amely nem a fal-óra és nem a player pozíció-streamje.
- **A konkrét playback-csomag az `audioplayers ^6.8.0`** (a `pubspec.yaml`
  egyetlen playback-plugin — ma tuner referencia-hang / metronóm-kattintás).
  Az `AudioPlayer` felülete lefedi az adapter-kontraktust:
  `onPositionChanged` (`Stream<Duration>`), `onPlayerComplete` (`Stream<void>`),
  `play/pause/resume/stop/seek(Duration)/setPlaybackRate(double)/`
  `setSourceDeviceFile(String)/dispose`.
- **Az app-lifecycle mechanizmus olvasható és megosztott.** Az
  `AppLifecycleEvents` (`lib/core/platform/app_lifecycle.dart`) publikus
  interfész `addListener/removeListener` + `isBackgroundLifecycleState(...)`
  segédfüggvénnyel, és már ki van vezetve `appLifecycleEventsProvider`-ként
  (`audio_providers.dart`). Az `AudioLifecycleGuard` ezt használja a mikrofon
  háttérbe-tételes leállításához — ugyanez a diszciplína a backing playerhez is
  additív, olvasás-only fogyasztással elérhető.

## Döntés

1. **A transport tiszta állapotgép explicit parancsokkal, exact átmenet-pártáblával.**
   Az engedélyezett `(előző phase, command) → (új phase, effect)` párokat tételes
   tábla rögzíti; a tranzitív reachability nem elégséges mérce (§5.1). Minden
   engedélyezett ÉS minden tiltott pár tesztelt (acceptance #1); a chained command
   a bejárt `phasePath`-ot mérhetővé teszi.

2. **Az aktív pozíció kizárólag a monoton óra horgonyából származik.** Sem a
   dokumentum wall-time metaadata, sem a UI frame, sem az `audioplayers`
   pozíció-stream nem master clock (§5.2). A player-stream csak drift-**mérésre**
   és resync-döntésre szolgál, nem az igazság forrása. Az idő↔beat leképezés az
   R03 `SongTimeMap` (`timeAt/positionAt/durationBetween`) fölött történik.

3. **A backing player külön, auditált lifecycle-t kap — NEM a mic lease-t.** A
   player saját `audioplayers.AudioPlayer` handle-t birtokol, saját
   dispose/interruption-életciklussal. **Nem** szerez `AudioSessionCoordinator`
   mic lease-t: az (a) az out-of-scope `audio_session_lease.dart` módosítását
   követelné egy új `AudioOwner`-hez, és (b) hamisan kizárólagossá tenné a
   playbacket a mic-capture-rel, holott a scoring-kör (R19+) egyszerre igényli
   mindkettőt. A „közös audio lifecycle" a háttérbe-tételes leállítási
   **diszciplína** újrahasznosítása: a production wiring
   (`song_trainer_providers.dart`, az engedélyezett listán) a read-only
   `appLifecycleEventsProvider`-t figyeli és háttérnél `pause`-t vált — auto
   hangos resume nélkül (acceptance #5). Ez egyszerre teljesíti a §2 „közös
   lifecycle kötelező" és a §9 „a player lease külön, auditált lifecycle" előírást.

4. **A `BackingAudioPlayer` explicit `PlaybackCapabilities`-t hirdet.** A
   capability (támogatott rate-tartomány, seek, codec) explicit érték, nem
   futásidőben kitalált; az adapter a `honest-pending`/`unsupported` esetet
   stabil state+effect-tel jelzi, nem silent no-op-pal. Ez firmálja fel az
   ADR 0125 §4 backing-rate `honest-pending` állapotát tényleges, mérhető
   képességgé.

5. **A drift-küszöb kizárólag dokumentált benchmarkból származik.** Benchmark
   nélkül a küszöb hamis stabilitást adna → STOP (§9). A
   `docs/baseline/epic-03-backing-drift-benchmark.md` rögzíti a mérési
   módszert és a kötött küszöböt; a `backing_drift_test.dart` a
   `threshold−ε / threshold / threshold+ε` cellákat tolerál / kötött-boundary /
   safe-resync viselkedésre méri.

6. **Stop idempotens; minden más invalid transition stabil, megkülönböztethető
   failure.** A dupla stop no-op idempotens, de egy tiltott átmenet (pl.
   `playing → setSpeed`) kontrollált failure-effektet ad, nem néma elnyelést
   (§5.3).

7. **Speed csak `ready`/`paused` fázisban; interruption → biztonságos pause,
   explicit user resume.** Lejátszás közbeni rate-váltás az első verzióban
   tilos (scope §3); az interruption (háttér/route/audio) a player/subscription/
   timer lezárását vagy paused-ba állítását váltja ki, automatikus hangos resume
   nélkül (§5.4, acceptance #5).

## Elutasított alternatívák

- **A backing player a mic `AudioSessionCoordinator` lease-én keresztül:** új
  `AudioOwner` értéket követelne az out-of-scope enumban (tilos zóna), és
  hamisan kizárólagossá tenné a playbacket a mic-capture-rel — közvetlenül
  sértve a §9 „külön, auditált lifecycle" kockázat-döntést.
- **A player pozíció-streamje mint master clock:** az `audioplayers` stream
  eszközfüggő ütemű és dispose után késői eventet adhat (§9 kockázat); master
  clockként nem monoton és nem determinisztikus fake-kel.
- **A meglévő `ClockSupplier` (wall-óra) újrahasznosítása transport-clockként:**
  a fal-óra ugrálhat (NTP, kézi állítás), sérti a §5.2 monotonicitást.
- **Találomra rögzített drift-küszöb benchmark nélkül:** a §9 kifejezetten
  STOP-ot ír elő; hamis stabilitást adna.
- **Lejátszás közbeni rate-váltás az első verzióban:** scope-on kívül (§3),
  a boundary-menedzsment (anchor-újraszámolás rate alatt) külön kört érdemel.

## Következmények

- A kör-brief `allowed_paths` listája változatlan marad: a backing player a
  read-only `appLifecycleEventsProvider`-t **fogyasztja** (nem módosít
  core fájlt), a mic-coordinator és az `AudioOwner` enum érintetlen.
- Az ADR 0125 §4 backing-rate `honest-pending` állapota R18 után tényleges
  `PlaybackCapabilities` képességgé firmálható; a setup-réteg későbbi köre
  ezt fogyaszthatja.
- Ez az ADR transport- és playback-viselkedést vezet be, de scoring-ot és
  mikrofon-megfigyelést NEM — azok az R19+ köre.
