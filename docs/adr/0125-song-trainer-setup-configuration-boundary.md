# ADR 0125 — Song Trainer setup configuration boundary

**Státusz:** elfogadva (E03-R17 pre-flight, 2026-08-04, tervezési baseline
`main` @ `4c51009`). Épít az [ADR 0114](0114-song-capability-model.md)
capability-modelljére és az [ADR 0123](0123-song-trainer-presentation-activation-boundary.md)
V2 presentation-aktivációs határára. Kör-brief:
[`docs/rounds/e03-r17-overview-track-range-setup.md`](../rounds/e03-r17-overview-track-range-setup.md).

## Kontextus

A Song Trainer setup az a réteg, ahol a felhasználó egy már perzisztált
`SongDocument`-ből kiválasztja a gyakorlási tartományt (full / section / measure
range / bookmark), a track/mód-kombinációt és a session-paramétereket
(speed, count-in, metronome, loop, tuning/capo reminder). A pre-flight mért
állapot ezt behatárolja:

- A capability-modell (`SongCapabilityReport`, ADR 0114) ma **kizárólag két
  scoring-tengelyt** hordoz: `chord` (`SongChordCapability{display, scoring,
  hasUnsupportedChord}`) és `pitch` (`SongPitchCapability{display, scoring,
  isMonophonic}`), plusz a dokumentum-szintű `canPersist / canImportPreview /
  canExport / canTrain` roll-upokat. **Nincs** külön rhythm/strum scoring-mező
  és **nincs** backing-audio playback-rate capability-mező.
- A `chord.scoring` hamis pontosan akkor, ha egy `chordUnsupported` warning
  szerepel a `SongValidationReport`-ban; a `pitch.scoring`/`isMonophonic` hamis
  pontosan akkor, ha egy `notePolyphonic` warning szerepel. Ez a két input a
  §6 megkülönböztető mátrix egyetlen mért kapcsolója a chord- és a
  pitch-tengelyen.
- A transport/playback (SongTransport, backing playback adapter) az E03-R18+
  köre; R17-ben nem indul trainer controller és nem szerződik le mikrofon-,
  audio- vagy transport-erőforrás.
- A route-katalógus (`AppRoutes`, `lib/app/routing/app_route.dart`) az egyetlen
  hely, ahol GoRouter route-literál élhet — a `route_literal_guard`
  architektúra-teszt minden máshol elhelyezett route-string-literált pirosra
  vált.

## Döntés

1. **A setup egyetlen, immutábilis `TrainerConfig`-ot állít elő** (tartomány,
   track-kiválasztás, mód-kapcsolók és session-paraméterek), amelyet a későbbi
   R19+ practice-indító fogyaszt. A setup a `SongDocument`-et **soha nem
   mutálja**; a dokumentum egyenlősége a setup után változatlan.

2. **A scoring-mód engedélyezés forrása a capability-report a chord- és a
   pitch-tengelyen** (ADR 0114 kötött döntés 1): a widget nem következtet nyers
   eventből. A `report.chord.scoring` és a `report.pitch.scoring` /
   `isMonophonic` közvetlenül vezérli a chord- és a pitch-mód kontrollokat.

3. **A rhythm/strum-mód engedélyezés strukturális, nem capability-mező.** Mivel a
   capability-report ma nem hordoz rhythm-tengelyt, a rhythm/strum-scoring
   elérhetőségét a **sealed track-altípus jelenléte** (`ChordTrack` /
   `StrumTrack` / `NoteTrack`) és a dokumentum-szintű `canTrain` adja. A
   track-altípus olvasása nem „nyers eventből következtetés" — a track-kind a
   modell explicit, immutábilis szerkezeti jelzése. Rhythm-scoringot a jelenlegi
   capability-modell egyetlen warningja sem tudja lefokozni.

4. **A backing-audio playback-rate „supported" állapotnak R17-ben nincs
   előállító inputja.** Mivel nincs backing-rate capability-mező (R18 vezeti be),
   minden playback-rate-hez kötött kontroll (backing rate-váltás) feltétel
   nélkül **honest-unavailable/pending** indoklással jelenik meg. A cél-speed
   érték (SDD §10.5, 50%–150%) mint konfigurációs érték felvehető, de a
   backing-audio tényleges rate-realizációja R18-ig nem hirdethető
   támogatottként.

5. **A missing-backing-asset jelzés különálló a capabilitytől:** egy
   `BackingAudioTrack.assetId`, amit a repository nem tud fájllá feloldani, a
   scoringot nem törli, csak a backing-kontrollt tiltja és a javítási flow
   **belépési pontját** adja (teljes repair workflow nem tágítja a kört).

6. **Range end exclusive, dalhatáron validált.** A UI inkluzív measure-kijelölése
   a domainben exclusive végre képződik le; a tartomány `[0, measures.length)`
   közé záródik, az utolsó measure csak `end == measures.length` esetén kerül
   bele. A setup a mappinget explicit cellákkal teszteli (off-by-one a §9
   megnevezett kockázata).

7. **Provider-elhelyezés co-located.** A setup controller providerét a saját,
   engedélyezett `song_trainer_setup_controller.dart` deklarálja (a
   `song_trainer_providers.dart` NEM módosul); a függőségeket (repository,
   `SongCapabilityResolver`) intra-feature importtal olvassa. Mért indok: a
   `tool/check_architecture.dart` csak a core→feature és a cross-feature-public-
   API szabályokat kényszeríti, a provider-központosítást nem, és a presentation
   már ma is közvetlenül importál application-controllert.

## Elutasított alternatívák

- **Rhythm-scoring hamis capability-mezővel:** a capability-modell R17-ben nem
  hordoz rhythm-tengelyt; kitalált mező hazug „supported" állapotot adna.
- **Backing-rate „supported"-ként hirdetése R17-ben:** a playback adapter (R18)
  hiányában nincs olyan input, amely ezt igazolná — a pre-flight
  unreachable-status szabálya tiltja.
- **SongDocument mutálása setupból** (pl. track enable-flag mentése): kilépne a
  kör scope-jából és sértené a dokumentum-egyenlőség acceptance-t.
- **Route-literál az `app_router.dart`-ban** a katalógus helyett: a
  `route_literal_guard` architektúra-teszt pirosra váltana.
- **`song_trainer_providers.dart` megnyitása** a setup provider miatt: felesleges
  scope-tágítás, a co-located provider architekturálisan megengedett.

## Következmények

- A kör-brief `allowed_paths` listája a mért, architektúra által kényszerített
  `lib/app/routing/app_route.dart` route-katalógus-ownerrel egészül ki
  (§0.0 revízió); a route-wiring (`app_router.dart`) enélkül nem hajtható végre
  a `route_literal_guard` teszt megsértése nélkül.
- A feature-flag (`songTrainerV2Enabled`) alapértéke OFF marad; a két új route
  (overview, setup) a meglévő `songTrainerEnabled` blokkba kerül.
- Ez az ADR nem vezet be hálózati vagy transport-viselkedést; a setup tisztán
  lokális, olvasó réteg, amely egyetlen immutábilis konfigurációt ad tovább.
