# ADR 0193 — Song Trainer vision integration contract and `vision` domain-safe barrel

- **Státusz:** Elfogadva (E05-R26 pre-flight, 2026-08-08)
- **Kör:** E05-R26 — Song Trainer vision integráció
- **Implementer motor:** Terra (Codex CLI, `~/.codex-terra`, `gpt-5.6-terra`,
  `tools/codex-round.sh`) — az ADR-t az orchesztrátor (Claude Sonnet 5) írta a
  pre-flightban (ADR 0055, pipeline-prompt §0 — nincs előre kiosztott ADR).
- **Epic:** [Chapter 6 — Epic 5: Computer Vision](../sdd/06-epic-05-computer-vision.md) Kör 26; §26
- **Kontext-ADR-ek:** [0182](0182-vision-audio-priority-degradation.md)
  (audio-elsőbbség — a brief tévesen „ADR 0165"-ként hivatkozza, ld. Kontextus
  1. pont), [0176](0176-cross-feature-public-barrel-recognition.md) (nested
  `public.dart` barrel elismerése — ez a döntés egy ÚJ nested barrelt vezet be
  ugyanazon a mechanizmuson), [0178](0178-vision-privacy-by-default.md)
  (raw-media-mentes vision eredmény), [0192](0192-practice-vision-integration-contract.md)
  (Practice-oldali testvér-kör, E05-R25 — a Song Trainer-oldali kontraktus
  ugyanazt a mintát követi, és ennek a körnek a security-review MINOR-1
  lelete indokolja az itt bevezetett barrel-szűkítést).

## Kontextus

Az SDD Ch6 §26 szakasz- és loop-szintű vision-összegzést ír elő a Song
Trainerhez, teljesítményvédett (audio-elsőbbség) módban. A kör-brief
2026-08-05-i batch-írásakor nem kapott ADR-számot (`nincs`); a pipeline-prompt
§0 táblája explicit „te írod meg a pre-flightban" — `tools/round-slots.py
reserve-adr --round E05-R26` → **0193**.

**Mért rések a pre-flightban** (pipeline-prompt §1 mérési szabályai — minden
brief-hivatkozott ADR-számot, útvonalat és típust ki kell grep-elni, nem a
rétegdiagramból feltételezni):

1. **A brief „ADR 0165"-re hivatkozik kétszer (§5 pont 1, §0 fejléc) egy nem
   létező fájlra.** `find docs/adr -iname '*0165*'` → 0 találat;
   repo-szintű `grep -rln "0165"` → az egyetlen hivatkozó a saját brief és az
   E05-R29 brief (ugyanaz a hiba, más kör, javítatlanul hagyva — nem ennek a
   körnek a scope-ja). A ténylegesen leírt „audio-elsőbbség" döntés (romló
   audio-deadline esetén a vision degradál, sosem az audio) szó szerint az
   **ADR 0182** ("Vision audio-priority degradation", elfogadva E05-R01
   pre-flight) — tartalmilag egyezik a brief §5 pont 1 leírásával. A
   brief-revízió (§0.0) mindenütt 0182-re javítja a hivatkozást.
2. **`vision/public.dart` barrel-szimbólum-rés** (mérve E05-R25 dedikált
   security-review MINOR-1, [`docs/LESSONS.md`](../LESSONS.md) L190; a
   `HANDOFF.md` §3 KÉTSZER explicit előírja, hogy ezt „E05-R26 pre-flightja
   ELŐTT" kell zárni). Mérés: `lib/features/vision/public.dart` (77 sor) a
   domain-safe aggregátumok (`VisionSessionResult`, `VisionQualitySummary`,
   `VisionPracticeContract` stb.) MELLETT nyers landmark/pose/geometry/
   koordináta típusokat, landmark-provider osztályokat ÉS UI-screeneket is
   exportál (teljes, tételes lista lent, Döntés 3). A
   `tool/check_architecture.dart:236-239` (`_isFeaturePublicBarrel`) kizárólag
   azt nézi, hogy a célfájl `/public.dart`-ra végződik-e — szimbólum-szintű
   korlát NINCS. Ez a kör nyitja meg a MÁSODIK `<feature> → vision/public.dart`
   élt (`practice → vision` volt az első, E05-R25); a `song_trainer` új
   fájljai anélkül a wide barrel teljes felületét örökölnék, hogy bármelyik
   gépi őr ezt jelezné.
3. **`lib/features/song_trainer/public.dart` prezentációs barrel, nem
   domain-kontraktus.** Mérve: a fájl teljes tartalma két screen-export
   (`song_import_screen.dart`, `song_library_screen.dart`), fejléc-kommentje
   szerint „Public presentation boundary for flag-gated Song Trainer V2
   routes." A song_trainer feature ÉLŐ, cross-feature DOMAIN-boundaryja a
   különálló, nested `lib/features/song_trainer/domain/public.dart` (ADR 0089
   §Döntés 1, elismerve ADR 0176 által). E kör új `SongVisionSummary`/
   `SongVisionAdapter` fájljait ebben a körben KIZÁRÓLAG a song_trainer
   feature-ön belül fogyasztják (nincs más feature, ami ebben a körben
   song_trainer-t importálna) — tehát egyik song_trainer-oldali barrel sem
   igényel új exportot EBBEN a körben. A brief `allowed_paths`-ában a
   root `public.dart` így is megmarad (ártalmatlan, nem kötelező felhasználású
   engedély), de a §0.0 ezt explicit dokumentálja, nehogy az implementer
   kényszerítve érezze magát rá.
4. **A brief pre-flight-pointere (`lib/features/song_trainer/services/`) nem
   létező útvonal.** Mérve: `find lib/features/song_trainer -iname '*service*'`
   → kizárólag `domain/services/` (E03 domain-szolgáltatások: validator,
   normalizer, capability-resolver, time-map, note-track-analyzer — nincs
   közük a transporthoz). A tényleges transport/loop implementáció:
   `application/trainer/{song_transport,song_transport_clock,
   song_transport_command,song_transport_state,transport_effect}.dart` +
   `domain/models/loop_config.dart` + a prezentációs
   `presentation/widgets/{transport_controls,loop_controls,
   song_loop_feedback}.dart`. A brief-revízió (§0.0) ezt a mért listát adja
   a „nem változhat" transport-terület pontos definíciójaként.
5. **`CadenceLimitedPoseLandmarkProvider` már létezik** (`data/landmarks/
   pose_landmark_provider.dart:70`) — ez egy DATA-réteg, provider-szintű
   inference-ütemező (a tényleges landmark-hívások gyakoriságát korlátozza),
   NEM a Kör 26 által bevezetendő application-szintű DÖNTÉSI szolgáltatás
   (melyik cadence-SZINTET kell futtatni a terhelés alapján). A kettő
   kiegészíti egymást, de e kör `VisionCadencePolicy`-ja nem nyúl a
   provider-rétegbe (a device-tier-alapú tényleges FPS/felbontás-huzalozás
   Kör 29 dolga, kizárva §3 szerint) — csak a DÖNTÉST hozza meg és adja
   vissza tiszta, determinisztikus adatként.

## Döntés

1. **ADR-szám: 0193.** A brief minden `nincs`/pre-flight ADR-hivatkozása ide
   mutat; minden „ADR 0165" szöveg „ADR 0182"-re javítva (Kontextus 1. pont).
2. **`VisionSongContract` / `SongVisionAdapter` / `SongVisionSummary` a
   Practice-mintát követi (ADR 0192 testvér-döntése):** közös session/
   section/loop-azonosítók, loop-iterációnkénti aggregáció (stroke
   consistency, hand travel), posture drift csak a dokumentált minimum
   szakaszhossz fölött, thermal degradation esetén audio-only átváltás **a
   dal megszakítása nélkül** — ez az ADR 0182 audio-elsőbbség elvének
   Song Trainer-oldali alkalmazása (a transport/timing e kör alatt
   bizonyítottan nem regresszálhat, ld. §7 parity-fixture).
3. **`VisionCadencePolicy`** (`lib/features/vision/application/
   vision_cadence_policy.dart`, ÚJ): tiszta, determinisztikus
   application-szolgáltatás. Bemenet: egy Terra által definiált, explicit
   terhelés/thermal-jelzés típus **legalább három** megkülönböztethető
   szinttel (normál/meleg/forró, illesztve a brief §6 thermal-mátrixához).
   Kimenet: **legalább három** megkülönböztethető cadence-állapot (teljes /
   csökkentett / audio-only-vision-kikapcsolva), és a low-tier-forced-off
   eset (§5 pont 5 a briefben) `visionDisabled`-ként reprezentálható, ami
   **nem hiba**. A küszöbök mindkét oldalát külön teszt-cella bizonyítja
   (nincs „elérhetetlen" határeset — pipeline-prompt §1 1. mérési szabálya).
   A device-tier-alapú finomhangolás (Kör 29, `VisionDeviceTier`, már létező
   enum a `data/landmarks/hand_landmark_provider.dart:125`-ben) kívül esik —
   a policy bemenete ebben a körben KIZÁRÓLAG a thermal-fake jelzés, nem
   valós platform-API.
4. **Barrel-boundary fix: új, szűk, domain-safe nested barrel.**
   `lib/features/vision/domain/integration/public.dart` (ÚJ fájl). A
   `tool/check_architecture.dart` **módosítása nélkül** legális cél-boundary,
   mert `_isFeaturePublicBarrel` már ma is elfogad bármely, a feature alatt
   élő, `/public.dart`-ra végződő fájlt (ADR 0176 nested-barrel elismerése —
   ugyanaz a mechanizmus, amit a `song_trainer/domain/public.dart` már
   használ). A fájl re-exportálja:
   - a meglévő `domain/integration/vision_practice_contract.dart`-ot
     (szimmetria/jövőbeli Practice-migráció előkészítése — ld. Döntés 6);
   - az új `domain/integration/vision_song_contract.dart`-ot;
   - az új `application/vision_cadence_policy.dart`-ot;
   - a fenti három fájl publikus szignatúráiban ténylegesen hivatkozott,
     MEGLÉVŐ domain-safe aggregátum típusokat — implementer méri ki
     (grep-eld ki, melyik ténylegesen kell): jelölt bázis
     `domain/vision_session_result.dart`, `domain/quality/
     vision_quality_summary.dart`, `domain/quality/vision_frame_quality.dart`,
     `domain/vision_setup_profile.dart`, `domain/metrics/{metric_definition,
     picking_metrics,posture_metrics,fretting_metrics}.dart` — egyik sem esik
     a tiltott könyvtárak alá (lásd Döntés 5).
5. **Szigorú tiltólista a szűk barrelre (könyvtár/fájl-prefix alapú, NEM
   szimbólum-név alapú — egyszerűbb és robusztusabb egy jövőbeli új
   osztállyal szemben is):** a szűk barrel `export` direktívája egyike sem
   célozhat az alábbi könyvtár/fájl-prefixek egyikét sem:
   - `domain/landmarks/` (pl. `HandLandmarks`, `PoseLandmarks`, `HandTrack`,
     `HandTrackAssigner`, `LandmarkSmoothingFilter`, `PostureBaseline`,
     `TrackContinuity` — teljes osztálylista mérve, ld. lent);
   - `domain/geometry/` (pl. `GuitarLandmarkMapper`, `GuitarRegion`,
     `GeometryConfidence`, `GeometryObservation`);
   - `data/landmarks/` (pl. `HandLandmarkProvider`, `NativeHandLandmarkProvider`,
     `RecordedHandLandmarkProvider`, `PoseLandmarkProvider`,
     `NativePoseLandmarkProvider`, `RecordedPoseLandmarkProvider`,
     `CadenceLimitedPoseLandmarkProvider`, `VisionImage`, `VisionDeviceTier`);
   - `presentation/` (a négy screen/overlay: `VisionSetupScreen`,
     `GuitarCalibrationScreen`, `VisionSessionScreen`, `VisionPreviewOverlay`);
   - `../../core/camera/camera_coordinate_space.dart` (`NormalizedPoint`,
     `NormalizedRect`).

   Mért, teljes osztály/enum-lista a négy domain/data könyvtárban (grep
   `^(final |abstract |sealed |base )*class |^enum ` minden exportált
   fájlon): `HandLandmarkId`, `Handedness`, `HandLandmarkPoint`,
   `HandObservation`, `HandLandmarkObservability`, `HandRole`, `TrackStatus`,
   `HandTrack`, `HandTrackFrameState`, `HandTrackAssigner`, `SmoothingProfile`,
   `LandmarkSmoothingFilter`, `PoseLandmarkId`, `PoseLandmarkPoint`,
   `PoseObservability`, `PoseLandmarks`, `RawPoseLandmark`,
   `PostureBaselineConfig`, `PostureBaseline`, `PostureObservation`,
   `PostureBaselineCollector`, `TrackContinuity`,
   `GuitarLandmarkMappingFailure`, `MappedHandLandmark`,
   `GuitarLandmarkMapperSetupFailure`, `GuitarLandmarkMapper`,
   `GuitarLandmarkMapperSetupException`, `GuitarRegion`,
   `GuitarRegionThresholds`, `GuitarRegionClassifier`, `GeometryConfidence`,
   `FrameObservation`, `GeometryObservation`, `VisionPixelFormat`,
   `VisionImage`, `HandLandmarkTimestamp`, `HandModelConfig`,
   `VisionDeviceTier`, `HandLandmarkProvider`, `NativeHandLandmarkProvider`,
   `RecordedHandLandmarkProvider`, `PoseModelConfig`,
   `CadenceLimitedPoseLandmarkProvider`, `PoseLandmarkProvider`,
   `NativePoseLandmarkProvider`, `RecordedPoseLandmarkProvider`,
   `NormalizedPoint`, `NormalizedRect`.
6. **A Song Trainer ÚJ vision-fogyasztó fájljai (`song_vision_adapter.dart` és
   bármely más új song_trainer fájl, ami vision-szimbólumot importál)
   KIZÁRÓLAG az új szűk barrelt (`vision/domain/integration/public.dart`)
   importálják — a wide `lib/features/vision/public.dart`-ot NEM.** A wide
   barrel és a Practice (E05-R25) meglévő importja **változatlan marad**
   ebben a körben; migrálásuk a szűk barrelre külön, jövőbeli kör follow-upja
   (nem blokkolja ezt a kört — a wide barrel importja ma sem sért egyetlen
   gépi őrt, és R25 kódja bizonyítottan nem használ nyers szimbólumot).
7. **Gépi őr, forrás-szöveg-alapú, NEM szemantikai (könyvtár-prefix
   assertion, egyszerűbb és robusztusabb, mint egy azonosító-tiltólista):**
   új teszt `test/features/vision/domain/integration/
   vision_integration_barrel_boundary_test.dart` alatt, két cellával:
   (a) a szűk barrel fájl `export` direktíváinak egyike sem oldható fel a
   Döntés 5 tiltott könyvtár/fájl-prefixei alá (a teszt maga olvassa be és
   reguláris kifejezéssel elemzi az `export '...'` sorokat — nem importálja
   a `tool/check_architecture.dart`-ot, mert annak segédfüggvényei privátok);
   (b) a song_trainer új vision-fogyasztó fájljainak import-sorai NEM
   tartalmazzák a `features/vision/public.dart` (wide) célt. Mindkét cella
   RED egy szándékosan visszaállított hibás állapoton (wide import vagy
   tiltott export vissza), GREEN a helyes állapoton — a brief §6 „Valódi-sértés
   próba" mintáját követi.

**NEM elfogadható:** a `tool/check_architecture.dart` módosítása (a shared
mérce-eszköz — bár technikailag nincs a `.claude/hooks/protect_factory_files.py`
tiltott glob-jai között, egy szimbólum-szintű ellenőrzés hozzáadása minden
jövőbeli körre kiható, dedikált architektúra-kör dolga, ld. Elutasított
alternatívák); a wide `vision/public.dart` meglévő exportjainak törlése vagy
szűkítése (regresszió a vision saját prezentációs hívóinak); a Practice
(E05-R25) meglévő importjának migrálása (a practice fájlok nincsenek ezen kör
`allowed_paths`-án — H3 kockázat); a transport/timing bármely módosítása
(a brief §5 pont 1, változatlan); a `VisionDeviceTier` valós platform-API-ra
kötése (Kör 29 dolga).

## Következmények

- `lib/features/vision/domain/integration/vision_song_contract.dart` — új,
  szűk, Song Trainer felé nyitott vision-kontraktus.
- `lib/features/vision/application/vision_cadence_policy.dart` — új,
  determinisztikus cadence-döntési szolgáltatás.
- `lib/features/vision/domain/integration/public.dart` — ÚJ, szűk,
  domain-safe nested barrel (Döntés 4–5).
- `lib/features/song_trainer/data/vision/song_vision_adapter.dart` — új,
  fogyasztó-oldali adapter (a Practice/R25 mintája), a szűk barrelt importálja.
- `lib/features/song_trainer/domain/models/song_vision_summary.dart` — új,
  loop/section vision-összegzés domain modell.
- `test/features/vision/domain/integration/vision_integration_barrel_boundary_test.dart` —
  új, a Döntés 7 gépi őre.
- A wide `lib/features/vision/public.dart` és a Practice E05-R25 importja
  **bájtra változatlan** marad.

## Elutasított alternatívák

- **Szimbólum-szintű negatív guard a shared `tool/check_architecture.dart`-ban**
  (a security-review MINOR-1 (a) fix-iránya, szó szerint). Elvetve ERRE a
  körre: a shared mérce-eszköz módosítása minden jövőbeli kör futására
  kihat, a teljes repo ellenőrzését igényelné az új szabály bevezetése előtt
  (nincs-e máshol már meglévő, ma nem sértő, de az új szabály alatt piros
  eset), és ez egy önálló, dedikált architektúra-kör terjedelme, nem egy
  Song Trainer feature-kör mellékterméke. A nested-barrel-alapú megoldás
  (Döntés 4) ugyanazt a biztonsági garanciát adja az ÚJ konzumensre nézve,
  nulla módosítással a shared eszközön. Follow-up: `docs/LESSONS.md`
  bejegyzés jelöli a szisztematikus (minden jelenlegi és jövőbeli konzumensre
  kiterjedő) fix igényét egy dedikált kör számára.
- **Teljes barrel-szétválasztás az ÖSSZES meglévő fogyasztó (Practice)
  egyidejű migrálásával.** Elvetve: a Practice fájljai nincsenek ezen kör
  `allowed_paths`-án; a migrálás más feature production kódjának
  módosítását igényelné, ami H3 (tilos zóna) kockázat lenne egy Song
  Trainer-kör alatt.
- **A cadence policy bemenetének valós thermal/battery platform-API-ra
  kötése.** Elvetve: a brief §3 explicit kizárja a device-tier benchmarkot
  (Kör 29 dolga), és a `VisionDeviceTier` enum már létezik, de detektorja
  nincs — egy ezen kör alatti valós API-integráció megelőzné és
  megkerülné Kör 29 saját scope-ját.
- **A `lib/features/song_trainer/public.dart` (root) kényszerített bővítése,
  hogy „kihasználja" az allowed_paths engedélyt.** Elvetve: a Kontextus 3.
  pontban mért állapot szerint egyik új song_trainer fájlt sem fogyasztja
  másik feature ebben a körben — a kényszerített export élő hívó nélküli,
  felesleges publikus felület lenne.
