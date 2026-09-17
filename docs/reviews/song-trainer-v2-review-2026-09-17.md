# Song Trainer V2 — funkcionális átnézés (fejlesztői APK, `songTrainerV2Enabled=true`)

**Dátum:** 2026-09-17 · **Ág:** `claude/workflow-production-readiness-r1866i` @ `df28814f`
**Kérdés:** „átnéznéd a dal trainer hogy működik" — mit tud MA végigcsinálni egy felhasználó.
**Módszer:** forrásolvasás + meglévő tesztek (nincs lokális Flutter SDK; futtatott gate nincs).
**Scope:** csak elemzés — `lib/`, `test/`, `HANDOFF.md` érintetlen.

---

## 0. Összefoglaló verdikt

| # | Terület | Verdikt | Egymondatos indok |
|---|---------|---------|-------------------|
| 1 | Felhasználói út (library → trainer → eredmény) | **HIBÁS** | A `Start` gomb a setup képernyőn süket: a route nem ad `onComplete`-et, így a session-route **elérhetetlen**. |
| 2 | Adatmodell (`SongDocument`, séma-kapu) | **MŰKÖDIK** | Teljes, verziózott, CI-ben hash-pinnelt séma, körbejáró export/import teszttel. |
| 3 | Transport / playhead | **VÁZ** | Az állapotgép kész, de a playhead csak backing-audio esemény hatására lép; audio nélkül a highway áll. |
| 4 | Felismerés bekötése (strum/akkord → pontozás) | **RÉSZBEN** | A lánc a Practice motoron át valós és tesztelt, de a UI-ból nem indítható; mic-megtagadás néma skeleton. |
| 5 | Editor | **RÉSZBEN** | Ment/betölt/undo/redo/konfliktus rendben, de nyers űrlap: nincs szekció-létrehozás, a strum-minta hardkódolt. |
| 6 | Perzisztencia & migráció | **RÉSZBEN** | A fájl-repó és a recovery erős; a legacy → V2 migráció **soha nem fut** éles indításkor. |
| 7 | Tesztek & bizonyíték | **RÉSZBEN** | Nagyon sok egység/widget-teszt, de mind **injektált állapottal** — a route-szintű bekötést egy teszt sem járja végig. |

**A lényeg egy mondatban:** a Song Trainer V2 motorja lényegében készen áll, de a **prezentációs
bekötés hiányzik** — a `/songs` fül ma egy üres könyvtárat, egy szerkesztőt és egy zsákutcás
setup-képernyőt ad; a tényleges gyakorlás a *legacy* `/songs/own` → Learn úton érhető el.

---

## 1. Felhasználói út — **HIBÁS**

### 1.1 A mért útvonal

| Lépés | Mi történik | Hivatkozás |
|-------|-------------|------------|
| `/songs` fül | `SongLibraryScreen` (V2), friss telepítésen üres | `lib/app/routing/app_router.dart:763-767` |
| Üres állapot | Csupasz szöveg, **nulla CTA** | `song_library_screen.dart:333-363` |
| Import (FAB) | `SongImportScreen` `MaterialPageRoute`-on | `song_library_screen.dart:88-94` |
| Import siker | `SongImportSucceededEffect` **senki nem hallgatja** → néma siker, nincs pop, nincs visszajelzés | `song_import_controller.dart:202` vs. `song_import_screen.dart:31` |
| Dal megnyitása | Tap → **Editor** (ha menthető), csak read-only dal megy Overview-ra | `song_library_screen.dart:220`, `:230` |
| Overview → Setup | `context.push(songTrainerSetup)` — él | `song_overview_screen.dart:105-111` |
| Setup → **Start** | `widget.onComplete?.call(config)` — a route **nem ad** `onComplete`-et → **semmi nem történik** | `trainer_setup_screen.dart:79-80` vs. `app_router.dart:647-650` |
| Session | `/song-trainer/session/:songId` — a `lib/`-ben **egyetlen hívó sincs** | `app_router.dart:652-656` |
| Result | `/song-trainer/result/:songId` — szintén hívó nélkül | `app_router.dart:659-662` |

> **P0-BLOKKOLÓ:** a `songTrainerSession` és `songTrainerResult` route-ra a teljes `lib/` fában
> nincs `context.push`/`go`. A dal-trainer session **nem nyitható meg** a fejlesztői APK-ban.

### 1.2 Süket vezérlők, no-op callbackek

| Hely | Tünet | Hatás |
|------|-------|-------|
| `song_trainer_screen.dart:313` | `Slider(..., onChanged: null)` a sebesség-csúszkán, **akkor is, ha** `backingRateSupported == true` | a lassítás sosem állítható a session közben |
| `song_trainer_screen.dart:349-353` | `isPlaying: true`, `onPlay: () {}` | a play gomb `isPlaying`-re amúgy is `null` → letiltva; a no-op ártalmatlan, de félrevezető |
| `transport_controls.dart:60-65` | a seek-gomb **fixen** `onSeek(Duration.zero)` | nincs scrub/keresés, csak „ugrás az elejére" |
| `song_trainer_screen.dart:302` | `onABClear ?? () {}` | route-ról jőve az A–B törlés no-op |
| `song_result_screen.dart:54-66` | `onRetry` / `onNextSection` a route-on `null` | **két halott gomb** az eredményképernyőn |
| `trainer_setup_screen.dart:216-224` | `trainer-backing-rate-pending` — mindig letiltott ListTile | tartós „hamarosan" jellegű placeholder |
| `song_library_screen.dart:305-330` | `_LibraryError`: ikon + „Újra" — **hibaüzenet nélkül** | a felhasználó nem tudja, mi romlott el |
| `setlist_list_screen_v2.dart`, `setlist_session_screen.dart` | **egyik sincs route-olva** (752 sor holtkód); a `/songs/setlists` a legacy képernyőt nyitja | a V2 setlist-folyam nem létezik a felhasználónak |

`TODO` / `UnimplementedError` / „coming soon" ARB-kulcs a `song_trainer` fában **nincs** — a
hiányok nem jelölve vannak, hanem csendben bekötetlenek. Ez rosszabb: a UI késznek látszik.

---

## 2. Adatmodell — **MŰKÖDIK**

| Elem | Állapot | Hivatkozás |
|------|---------|------------|
| `SongDocument` | `schemaVersion`, `id`, `revision`, `metadata`, `source`, `assets`, `markers`, `tracks`, `sections`, `measures`, `tempoMap`, `meterMap`, `keyMap` | `song_document.dart:65-172` |
| Séma-verzió | `songDocumentSchemaVersion = 1`, régebbi doksi konstrukciókor elutasítva | `song_document.dart:56`, `:98` |
| Események | `SongChordEvent` / `SongStrumEvent` (`at`, `direction?`, `accent`, `muted`, `targetChordId`) / `SongNoteEvent` (string+fret, technikák, tie) / lyric / marker | `song_event.dart:69`, `:136`, `:194`, `:342`, `:387` |
| Hangolás / capo | `SongMetadata.tuning` + `capo` (tartomány-ellenőrzött), `SongInstrument.tuning`, setlist-szintű `capoOverride` | `song_metadata.dart:112-117`, `song_setlist.dart:44-45` |
| Séma-kapu | 6 forrásfájl SHA256-snapshotja, CI-ben kötelező lépés | `tool/ci/check_song_schema.dart:18-49`; `.github/workflows/build-apk.yml:37`, `full-gate.yml:43` |
| Export/import round-trip | identitás- és dokumentum-egyezésre tesztelve | `test/.../native_json_exporter_test.dart:52`, `native_json_importer_test.dart:56-61` |

Megjegyzés: a séma-kapu a **kódot** pinneli (hash), nem a JSON-kimenetet — egy szándékos
formátumváltás kényszerű hash-frissítést kér, ami jó jelzés, de nem fixture-alapú.

---

## 3. Transport / playhead — **VÁZ**

**Ami kész:** a `SongTransport` valódi, soros parancssorú állapotgép (prepare / start /
count-in / pause / resume / seek / speed / restart / finish / stop), stopper-alapú órával,
grid-offset formulával, backing-drift policy-val és életciklus-megszakítás kezeléssel
(`song_transport.dart:29-110`, `:452-470`). Éles összeállításban valódi `LocalBackingAudioPlayer`
(audioplayers) van mögötte (`song_trainer_providers.dart:352-370`).

**Ami hiányzik / hibás:**

| Megfigyelés | Bizonyíték | Következmény |
|---|---|---|
| **Nincs saját tick-forrás.** A `song_trainer` fában egyetlen `Timer.periodic`/`Ticker` sincs; állapot csak `BackingPositionEvent`-re megy ki. | `song_transport.dart:452-466` | Backing audio nélkül a `activePosition` **végig 0** marad. |
| A transport csak akkor indul, ha `_backingPrepared` (van audio asset). | `song_trainer_controller.dart:352-362`, `:322-327` | Kézzel épített / importált (audio nélküli) dalnál a transport `idle`-ben áll. |
| A highway viewportja `state.transportState.activePosition`-ból származik. | `song_trainer_screen.dart:288-297` | **A highway nem mozog** olyan dalnál, aminek nincs backing sávja — márpedig az import **nem fogad audiót**. |
| Szünetben a `StrumLane` **fix** 0–4 s ablakot kap, nem a szünet pozícióját. | `song_trainer_screen.dart:402-405` | Szünetnél a sáv a dal elejét mutatja, miközben fölötte a pontos ms-pozíció látszik → ellentmondás. |
| Metronóm: a `metronomeEnabled` a Practice configba megy, a Song Trainer nem szólaltat saját kattintást. | `song_practice_compiler.dart:277-278` | Pontozott módban van kattintás (Practice-tulajdon), playback-only módban nincs időzítő jel. |
| Count-in: állapot + overlay létezik, számláló nélküli statikus szöveg. | `song_trainer_screen.dart:222-233` | Nincs visszaszámlálás („3-2-1"). |
| Tempó-skálázás (lassítás) a setupban beállítható, de futás közben nem. | `trainer_setup_screen.dart:200-215` vs. `song_trainer_screen.dart:313` | Speed builder csak indítás előtt. |

`StrumLane` maga helyes, de **stateless viewport-widget**: `Expanded(flex: at.inMicroseconds)`
alapú elrendezés, saját animáció nélkül (`strum_lane.dart:52-86`). Vagyis a mozgás teljesen a
beérkező állapot-frissítések frekvenciájától függ — ami ma a fenti okból nulla lehet.

---

## 4. Felismerés bekötése — **RÉSZBEN**

**A lánc valós és megosztott a Practice móddal:**
`strumEngineProvider` → `LivePracticeObservationGateway` (`practice_observation_gateway_provider.dart:29-31`)
→ `PracticeSessionController` → `SongTrainerController` (`song_trainer_controller.dart:397-404`).
A Song Trainer szándékosan **nem** importál gateway-t vagy mikrofon-koordinátort — a Practice
birtokolja (`song_trainer_controller.dart:26-32`).

| Kérdés | Válasz | Hivatkozás |
|---|---|---|
| Eseményenkénti pontozás | `PracticeEvent(position, chord, direction)` a fordítóból; időablakok `perfect 50 ms` / `good 120 ms` / `match` | `song_practice_compiler.dart:100-124`; `practice/domain/model/scoring_profile.dart:71-72` |
| Szekció/ütem statisztika | `SongResultMapper` az `eventReferences`-szel ütem- és szekció-koordinátára képez | `song_trainer_controller.dart:379-384`; `song_result_mapper.dart` |
| Per-strum élő visszajelzés | `practiceStrumFeedback` → `StrumBurstOverlay` a sávon | `song_trainer_screen.dart:113-117`, `:326-334` |
| „Practice mode vs performance mode" | **Van:** pontozott (Practice sessionnel) vs. **playback-only** (`compilation.isPlaybackOnly`, mikrofon nélkül) | `song_practice_compiler.dart:33`; `song_trainer_providers.dart:395-404` |
| Playback-only lezárás | Nem szintetizál pontszámot, őszinte „csak lejátszás" állapot | `song_trainer_screen.dart:432-444` |
| Offline | A teljes lánc on-device; hálózat nem szükséges | — |
| **Mic megtagadva** | `SongTrainerStatus.permissionRequired` a képernyőn a **loading skeletonra** van képezve | `song_trainer_screen.dart:161-166` |

> **P1-HIBA:** mikrofon-megtagadásnál a felhasználó **örökké pörgő skeletont** lát, magyarázat és
> engedélykérő CTA nélkül. Ugyanez igaz a `ready` állapotra: a képernyő **soha nem hívja** a
> `controller.prepare()` / `start()` metódust (a `_SongTrainerScreenState` csak feliratkozik,
> `song_trainer_screen.dart:107-137`) — vagyis még ha a route elérhető is lenne, a session
> magától nem indulna el.

---

## 5. Editor — **RÉSZBEN**

| Képesség | Állapot | Hivatkozás |
|---|---|---|
| Új dal | 1 ütem, 120 BPM, 4/4, `createdInApp` forrás | `song_editor_screen.dart:120-142` |
| Undo / redo | Van, állapotvezérelt | `song_editor_screen.dart:167-179` |
| Mentés | `isLoaded && canPersist` mellett; a read-only forrás csak „másolatként" menthető | `:180-186`, `:305-325` |
| Konfliktus / validációs hiba / mentési hiba | Mind külön, nevesített hibaüzenet, a draft nem vész el | `:264-303` |
| Kilépés-védelem | `PopScope` + marad/eldob/ment dialógus | `:155-163`, `:203-240` |
| Akkord bevitel | **Szabad szöveges** `TextFormField`, nincs akkord-választó, nincs beviteli validáció | `song_event_editor.dart:56-72` |
| Strum-minta | **Hardkódolt** `[down, up]`, nincs mintaválasztó | `song_event_editor.dart:73-79` |
| Hang / tempó / ütemmutató | Nyers számmezők (MIDI pitch számként!) | `song_event_editor.dart:81-120` |
| Szekciók | **Csak átrendezés** — nincs létrehozás, átnevezés, törlés | `song_section_editor.dart:14`, `:26-50` |
| Ütemek | Beszúrás / törlés | `song_editor_screen.dart:336-341` |
| Backing audio | `BackingAssetEditor` létezik (audio ide csatolható, importból nem) | `backing_asset_editor.dart` |

**Tud-e egy kezdő 3 akkordos dalt összerakni 2 perc alatt?** Formálisan igen (ütem hozzáadás →
ütem választás → akkord beírás × 3 → Mentés), de: MIDI-szám mezővel, hardkódolt le-fel mintával,
akkord-választó nélkül és — a legfontosabb — **utána nincs hová vinni**, mert a gyakorlás
indítása a 1.1 pont miatt zsákutca. Gyakorlatilag: **nem**.

---

## 6. Perzisztencia & migráció — **RÉSZBEN**

| Elem | Állapot | Hivatkozás |
|---|---|---|
| Tár | `getApplicationSupportDirectory()/songs`, atomikus író | `song_trainer_providers.dart:105`, `atomic_file_writer.dart` |
| Mentés / betöltés / törlés | Kuka + UNDO a könyvtárban | `song_library_screen.dart:255-272` |
| Index-sérülés | `SongRepositoryErrorCode.corruptIndex`, recovery újraépítéssel és karanténnal | `file_song_repository.dart:198`; `song_repository_recovery.dart:55`, `:236` |
| Sérülés UI-ja | A könyvtár csak ikon+Retry-t mutat, a `failureCode` **nem jelenik meg** | `song_library_screen.dart:305-330` |
| `K-E12R23-01` | Ismert P2: sérült legacy dokumentum után üres könyvtár (adat a lemezen marad) | `docs/release/known-issues.md:65` |
| Resume checkpoint | `_InMemorySongResumeRepository` — „a fájl-alapú réteg az R22 körben" (nem készült el) | `song_trainer_providers.dart:430-434` |
| Legacy → V2 migráció | Teljes, restart-biztos, checkpointolt migrátor | `song_storage_migrator.dart:1-29` |
| Migráció **futtatása** | `songMigrationOutcomeProvider`-t a `lib/`-ben **senki nem olvassa** — csak két teszt | `song_trainer_providers.dart:345-350`; `song_storage_migrator_wiring_test.dart:139`, `:185` |

> **P1:** a doc-komment azt írja, „a boot path pontosan egyszer hívja" — **nem hívja.**
> Következmény: a `/songs/own` alatti legacy dalok soha nem jelennek meg a V2 könyvtárban,
> és a felhasználónak két, egymást nem látó dalgyűjteménye van.

---

## 7. Tesztek & bizonyíték — **RÉSZBEN**

**Ami le van fedve (erősen):** ~60 song_trainer teszt — importerek (MIDI/MusicXML/MXL, malformed +
biztonsági suite), repo + recovery + codec, normalizer/validator/time-map, transport életciklus és
időzítési paritás, editor-kontroller és history, progress/committer, setlist session, hozzáférhetőség,
teljesítmény (hosszú dal), 3 property-teszt (`test/property/song_*`), és 14 golden PNG
(library / overview / editor / import / preview / result / trainer stage).

**Ami NINCS lefedve — és pontosan ezért láthatatlan a fenti P0:**

| Rés | Bizonyíték |
|---|---|
| A trainer widget-tesztek **injektált** `state:`-tel és eseménylistákkal futnak, nem a route-on át | `song_trainer_screen_test.dart:73`, `:112` |
| Nincs teszt, ami a `TrainerSetupScreen` `Start`-ját **a routeren keresztül** nyomná meg | nincs ilyen fájl |
| Nincs teszt, ami bizonyítaná, hogy a `songTrainerSession` route egyáltalán elérhető | `grep`: nulla `push(songTrainerSession)` |
| Az e2e walkthrough a `/songs` fület **nem járja be**; a Library V2 szakasz épp azt rögzíti, hogy a song-repó nincs bekötve a harnessbe | `test/e2e/full_app_walkthrough_test.dart:250-271` |
| A navigációs teszt csak azt nézi, hogy a fül a `SongLibraryScreen`-t rendereli — tovább nem megy | `test/app/navigation/songs_tab_v2_test.dart` |
| Nincs teszt a migráció **bootstrap-hívására** (csak a provider működésére) | `song_storage_migrator_wiring_test.dart` |

Tanulság: minden teszt zöld lehet, miközben a funkció elérhetetlen — a hiányzó mérce a
**route-szintű, end-to-end „library → gyakorlás → eredmény" séta**.

---

## 8. Hiánylista rangsorolva

| # | Prio | Hiány | Legkisebb javítás |
|---|------|-------|-------------------|
| H1 | **P0** | A setup `Start`-ja süket → a session-route elérhetetlen | A route adja át az `onComplete`-et: fordítson `TrainerConfig`-ot `SongTrainerControllerInputs`-szá (`SongPracticeCompiler`) és `push`-oljon a session-route-ra (`app_router.dart:647-656`) |
| H2 | **P0** | A session-képernyő sosem hívja a `prepare()`/`start()`-ot | `initState`-ben (ill. az `inputs` megérkezésekor) `unawaited(controller.prepare())` majd `start()` (`song_trainer_screen.dart:107-137`) |
| H3 | **P0** | A route nem ad át `chordEvents` / `strumEvents` / `noteEvents` / `sections` / `onPause` / `onSeek`-et → üres sávok, halott vezérlők | A route a `compilation`-ből (vagy a betöltött dokumentumból) töltse fel a listákat és kösse a callbackeket a controllerre |
| H4 | **P0** | Friss telepítésen nincs egyetlen dal sem, az üres állapot CTA nélküli | 2–3 beépített, jogtiszta gyakorló-dal a `assets/`-ből első indításkor + `SsEmptyState` „Importálj" / „Építs dalt" gombokkal (`song_library_screen.dart:333-363`) |
| H5 | **P1** | Audio nélküli dalnál a playhead nem mozog | A transportnak saját tick-forrás kell (pl. 60 Hz-es `Ticker`), ami backing nélkül is emittál pozíciót (`song_transport.dart:452`) |
| H6 | **P1** | Mic-megtagadás = örök skeleton | A `permissionRequired` ágat válasszuk le a loadingról: magyarázó szöveg + „Engedély kérése" gomb (`song_trainer_screen.dart:161-166`) |
| H7 | **P1** | A legacy → V2 migráció soha nem fut | A bootstrap egyszer olvassa a `songMigrationOutcomeProvider`-t (`lib/app/bootstrap/…`) |
| H8 | **P1** | Az import sikere néma, a könyvtár nem frissül | A `SongImportScreen` figyelje a `SongImportSucceededEffect`-et: `pop()` + SnackBar, a könyvtár pedig `load()`-oljon visszatéréskor (`song_import_screen.dart:31`) |
| H9 | **P1** | Az eredményképernyő két gombja halott | A route adjon `onRetry` / `onNextSection` implementációt, vagy amíg nincs, ne rendereljük őket (`song_result_screen.dart:54-66`) |
| H10 | **P2** | A könyvtár tapja szerkesztőt nyit, nem gyakorlást | A `SongSummaryTile`-ba „Play" gomb → Overview; a tap maradhat a szerkesztőn (`song_summary_tile.dart:44-63`) |
| H11 | **P2** | `_LibraryError` üzenet nélkül | A `failureCode` megjelenítése a Retry fölött (`song_library_screen.dart:305-330`) |
| H12 | **P2** | Futás közbeni sebesség-csúszka letiltva | Kössük a `SetSongTransportSpeed` parancsra, ha `backingRateSupported` (`song_trainer_screen.dart:305-316`) |
| H13 | **P2** | Szünetben a strum-sáv a dal elejét mutatja | A `viewportStart` legyen `state.transportState.activePosition` (`song_trainer_screen.dart:402-405`) |
| H14 | **P2** | A seek csak az elejére ugrik | Scrub-slider a jelenlegi ikon helyett (`transport_controls.dart:60-65`) |
| H15 | **P2** | Resume checkpoint csak memóriában | Fájl-alapú `SongResumeRepository` (`song_trainer_providers.dart:430-434`) |
| H16 | **P2** | V2 setlist-képernyők route nélküli holtkód (752 sor) | Vagy route-olni, vagy törölni és a HANDOFF-ban jelölni |
| H17 | **P2** | Editor: nincs szekció-létrehozás, hardkódolt strum-minta, szabad szöveges akkord | Akkord-választó (a `progressions.dart` készletéből) + minta-választó a `strum_patterns.dart`-ból |

---

## 9. Ajánlott következő kör — „A dal-trainer legyen járható"

**Kör azonosító (javaslat):** E16-R01 · **Cél:** egy kezdő **import nélkül**, fájlkezelés nélkül
el tudjon indítani egy dal-gyakorlást a `/songs` fülről, és lásson eredményt a végén.

**Engedélyezett fájlok (javasolt lista):**

- `lib/app/routing/app_router.dart` (setup→session→result bekötés)
- `lib/features/song_trainer/presentation/screens/song_trainer_screen.dart` (prepare/start, permission ág)
- `lib/features/song_trainer/presentation/screens/song_library_screen.dart` (empty-state CTA, hibaüzenet)
- `lib/features/song_trainer/presentation/widgets/song_summary_tile.dart` (Play gomb)
- `lib/features/song_trainer/application/song_trainer_providers.dart` (seed-katalógus provider)
- `assets/songs/*.strumsight-song.json` (2–3 saját szerzésű gyakorló-dal) + `pubspec.yaml`
- `lib/l10n/app_en.arb`, `lib/l10n/app_hu.arb`
- `test/features/song_trainer/presentation/*`, `test/app/navigation/songs_tab_v2_test.dart`, új `test/e2e/song_trainer_walkthrough_test.dart`

**Elfogadási cellák:**

| Cella | Mérce |
|-------|-------|
| **A1** | Friss (üres) tárral a `/songs` fül **legalább 2 beépített dalt** listáz, és az üres állapot (ha mégis üres) kattintható CTA-t ad. |
| **A2** | Route-szintű teszt: `/songs` → dal Play → Overview → Setup → **Start** → a router a `songTrainerSession`-ön áll, és a controller `prepare()`+`start()` meghívódott. |
| **A3** | A session-képernyő a valódi dal akkord- és strum-eseményeit rendereli (a sávok nem üresek), és a `pause`/`resume` a controllerre hat. |
| **A4** | Backing audio **nélkül** is mozog a playhead: 1 s szimulált idő után az `activePosition > 0` és a viewport elmozdult. |
| **A5** | Mic-megtagadásnál a képernyő nevesített magyarázatot + engedélykérő gombot mutat, **nem** skeletont. |

**Kockázatok:**

1. **Erőforrás-életciklus.** A session-route mikrofont és wakelockot birtokol — az E13-R08-ban
   mért csapda (shell-ágban élve maradó erőforrás) miatt a session **top-level route** kell
   maradjon; a `_SongTrainerScreenState.dispose` kilépési útját nem szabad megbontani.
2. **Seed-dalok jogtisztasága.** Csak saját szerzésű / public domain anyag; a
   `tool/ci/check_song_fixture_licenses.dart` kapu érvényes marad rájuk.
3. **Séma-kapu.** Ha a seed betöltés a codec-et érinti, a `check_song_schema.dart` hash-eket
   ugyanabban a commitban kell frissíteni, indoklással.
4. **Tick-forrás és akkumulátor.** A saját ticker 60 Hz-en fut; háttérbe kerüléskor a meglévő
   életciklus-megszakításnak le kell állítania (`song_transport.dart` lifecycle ág).
5. **Golden-pergés.** A `e13_r25_song_trainer_stage_*` goldenek nem üres sávokkal fognak
   renderelni — az újrarögzítést a kör része kell legyen.

**Mit hagyjunk ki ebből a körből:** editor-ergonómia (H17), V2 setlist (H16), fájl-alapú resume
(H15), scrub-slider (H14). Ezek a következő körre valók, miután az út járható.
