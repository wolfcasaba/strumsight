# E18-R01 emulátor-jelentés — javító kör végrehajtási jelentése (2026-09-10)

> **Forrás:** [`e18-r01-emulator-report.md`](e18-r01-emulator-report.md)
> „FEJLESZTENDŐ” szakasz, F1–F13; plusz a felhasználó 2026-09-09-i kérése a
> felismerés „elugrálásáról” (minden akkordnál).
> **Ág:** `claude/optimistic-bohr-vpaxh4` (az E18-R01 ágról, `bc81bc5f`-ről
> indítva — a jelentés és az F11 kódja csak ott él).
> **Környezet:** remote Claude Code konténer — **nincs Flutter SDK**, a gépi
> bizonyíték a CI-futás (lent). Minden kód-sor pontosan 80 oszlopon belül
> tartva kézzel; a `dart format` a CI `format` lépésében mér.

## Eredmény-tábla

| # | Lelet | Státusz | Javítás | Mérce (új/módosított teszt) |
|---|---|---|---|---|
| F1 | Tutor-tudásanyag nem kerül az APK-ba | **JAVÍTVA** | `pubspec.yaml`: `assets/tutor_knowledge/en/` + `hu/` külön sor (a könyvtár-deklaráció nem rekurzív) | `test/features/ai_tutor/data/bundled_knowledge_assets_test.dart` — a LEFORDÍTOTT bundle-t olvassa (`rootBundle`), nem a lemezt; a repository `loadIndex()` fallback-kód nélkül |
| F2 | A Live akkord-kártya beragad | **JAVÍTVA** | `ChordTimeline.hasCurrent`: kapu elengedésekor a hős a történetbe hátrál, a prompt visszatér; `reduceChordTimeline` 2. szabály: lejárt pengetés → irány + konfidencia törölve helyben (`ChordEvent.withoutStrum`) | `chord_timeline_test.dart` (+1), `live_stage_test.dart` A2b (2 cella), `test/property/chord_timeline_property_test.dart` (randomizált invariáns + determinisztikus cella) |
| F3 | Irány/konfidencia beragad 87 %-on | **JAVÍTVA (a beragadás)** + **MÉRT TÉNY** | A beragadás az F2 mechanizmusa. A 87 % maga nem UI-alapérték: `LiveCrnnClassifier.calibrate` felső csomópontja `(1.00, 0.87)` — a le/fel tömegre újranormált, túlbiztos háló szinte minden pengetésre a plafont adja. Kalibráció-újrahangolás valós adat nélkül tilos (AGENTS §9) → E18-R05 | az F2 cellái; a kalibráció változatlan |
| F4 | Rendszer-back kilépteti az appot | **JAVÍTVA** | Practice hub gyors eszközök + CTA + cél-chipek, Profil hub (Library, Settings, Rewards, Login): `context.go` → `context.push`; ugyanarra a tabra koppintás a branch gyökerére visz (`goBranch(initialLocation: …)`); a Setup „back” pop-ol, ha van mire | `test/features/practice_hub/practice_area_hub_back_test.dart` — a VALÓDI adaptív routeren, az OS `popRoute`-jával (`handlePopRoute`): Tuner/Metronome/Chords/Live + tab-újrakoppintás + Profile→Library |
| F5 | A Library nem tölt be | **JAVÍTVA** | `main.dart` csak a dal-tárat kötötte; `analysisRepositoryProvider` és `setlistRepositoryProvider` SOHA nem volt bekötve → `libraryV2SourcesProvider` `StateError`, amit a Riverpod `AsyncError`-be nyelt (ezért nem volt kivétel a konzolon). Új `lib/app/bootstrap/production_repository_overrides.dart` | `test/app/bootstrap/production_repository_overrides_test.dart` — a VALÓDI forrás-listát olvassa a production override-okon át (+ negatív cella: nélkülük dob) |
| F6 | Cél-alapú belépő „Practice unavailable” | **JAVÍTVA** | A chipek üres `/practice/setup`-ra mentek (id nélkül). Új tiszta feloldó `resolvePracticeGoals` (mód → cél: bemelegítés/akkordok/ritmus; a MÓD-találat megelőzi a skill-tag találatot — a CI fogta meg, hogy a „rhythm” tag-es nyolcad-gyakorlat előzte a ritmus-only gyakorlatot; skála/technika skill-tag szerint). Kiszolgált cél → `?id=…`; nem kiszolgált (Scales, Technique — nincs ilyen tartalom) → helyben SnackBar („No practice for this goal yet.”), nem zsákutca. Az 5 chip megmarad (az `e13_r17` pixel-golden csak a boxon generálható újra) | `practice_area_hub_goal_test.dart` (4 cella), `test/features/practice/domain/practice_goal_resolver_test.dart` (5 cella), ARB: `practiceAreaHubGoalUnavailable` (base + generált aggregátum, en/hu) |
| F7 | Mikrofon-hiba néma, üres eredményre visz | **JAVÍTVA** | Új `ObservationCaptureFailed` jel: `countIn/running/finishing → failed` a hibával; a controller a stream-hibát erre vezeti (a gateway csak STOP, nem dispose → újrapróbálható); `RetryPractice` tényleg újra-előkészít (eddig `preparing`-ben ragadt); a `PracticeErrorPanel` a konkrét hibát nevezi (mikrofon-szöveg), Retry-val — a Tuner mintája | `practice_session_integration_test.dart` (átírt stream-hiba cella + 2 új: nincs eredmény-navigáció, Retry újraindít), `practice_session_screen_test.dart` (+1: mikrofon-szöveg + Retry → `RetryPractice`) |
| F8 | V2 dalszerkesztő elérhetetlen | **JAVÍTVA (belépő)** | Songs tab AppBar: flag-kapuzott belépő (`songs-entry-song-trainer`) → `push(/song-trainer)`. A reachability-mérő továbbra is kód-hivatkozást mér (dokumentált korlát) — külön kör | `test/features/songs/song_trainer_entry_test.dart` (flag be/ki) |
| F9 | Találati arány 2/5 | **NEM HANGOLVA — szándékosan** | A jelentés saját utasítása: valós gitárral újramérni MIELŐTT bárki hangol (64 kbps MP3 loopback torzít). DSP-konstans érintése itt tilos (AGENTS §9, nincs mikrofon/SDK). Protokoll: kutatási jegyzet §4 | — |
| F10 | Bemeneti szint 0 % / 100 % | **JAVÍTVA** | `rms * 8` (14 dB-es ablak) → `InputLevelMeter`: dBFS-skála −45 → 0, −6 → 1, pillanatnyi attack + 0.7×/keret release; a gyenge-jel küszöb (0.12) ≈ −40 dBFS = az analizátor `quietRmsDbfs` vonala. Csak kijelzés, a csend-kapu a nyers RMS-t olvassa | `input_level_meter_test.dart` (fix cellák + randomizált property), `live_pipeline_test.dart` (+2: közép-skála, release); `docs/rag/chunks/010` frissítve |
| F11 | Előnézet a képernyő elhagyása után is pengeti | **JAVÍTVA** | `SongBuilderScreen`: `PopScope.onPopInvokedWithResult` → `preview.stop()` a pop PILLANATÁBAN (a dispose csak a kilépő animáció után jött) | `song_builder_audition_test.dart` (+1, a 300 ms-os átmenet KÖZEPÉN mér) |
| F12 | Windows-on a suite 203 piros | **NEM JAVÍTVA — dokumentálva** | Windows-box nélkül nem verifikálható; a platform-érzékenyítés (POSIX-mód cellák, backslash-útvonal, linux-goldenek) külön kör. Az ékezetes repó-útvonal (`gitár trainer`) analyzer-összeomlása: fejlesztői setup-jegyzet alább | — |
| F13 | Bannerek mennyisége (termékdöntés) | **NEM VÁLTOZTATVA** | Szándékos viselkedés (terv §9/L5–L6, AGENTS §5). Az F2 javítása részben orvosolja: jel nélkül eltűnik a kártya, nincs mit magyarázni. Döntés a felhasználóé | — |

### F12 — fejlesztői setup-jegyzet (Windows)

- A repót **ékezet és szóköz nélküli** útvonalra klónozd (pl. `C:\dev\strumsight`):
  az `flutter analyze` analysis servere az ékezetes útvonalon (`gitár trainer`)
  255-ös kóddal összeomlott (mért, E18-R01 jelentés).
- A teljes `flutter test` Windows-on nem zöld (203 piros: POSIX fájlmód/symlink
  cellák, backslash-illesztés, linuxon generált pixel-goldenek) — a mérce a
  CI (Linux), lásd ADR 0053.

## Felismerés-stabilitás (a felhasználó 2026-09-09-i kérése) — ADR 0539

**Tünet:** egy leütött akkordnál (mindegyiknél) a kijelző „elugrik” egy másik
akkordra, majd vissza. **Azonosított mechanizmus** (kódból; valós gitárral
még nem mérve): a dekóder onset utáni 186 ms-os „lazított” ablaka pont az
attack-tranziensre esik; a téves címke 2–3 ~15 Hz-es keretet fed, a
stabilizátor 3 kereten megerősíti; a nagy hős ráadásul a NYERS keretet
mutatta.

**Szállítva (DSP-konstans érintése nélkül):**
1. a Stage hős — és az akadálymentes bejelentés — a STABILIZÁLT címkét
   mutatja/mondja (ADR 0539 D1; az E13-R18 A5 throttle-cellák megerősített
   váltásokat küldenek);
2. onset-tranziens őr a stabilizátorban: az onset utáni 0.2 s keretei nem
   számítanak elmozdításnak (D2) — valódi váltás ~0.4 s alatt erősödik meg;
3. a kártya lejár a kapuval (D3 = F2).

Mérce: `recognition_stabilizer_onset_guard_test.dart` (3 cella + property),
`live_stage_test.dart` A2c. **A dekóder attack-ablakának eltolása** (a
legvalószínűbb gyökérok) valós gitáros A/B-t kér → E18-R05 javaslat, protokoll
a kutatási jegyzetben.

**„Jobb motor” kutatás:** [`docs/research/chord-recognition-stability-and-engines-2026-09.md`](../research/chord-recognition-stability-and-engines-2026-09.md)
— nincs letölthető, eszközön futó, nyílt, előtanított motor, ami a valós
idejű Live-feladatra ma közvetlenül jobb (a nyílt SOTA BTC-család offline,
kétirányú, súlyok nélkül); a nyereség a döntési rétegben van; az Analyze
oldalra a BTC-osztály és a 2508.07973 adatkészlet (irány + akkord) a kutatási
irány.

## CI-kör — a távoli konténerből nem futtatható suite gépi bizonyítéka

A remote konténerben nincs Flutter SDK, ezért a teljes suite CSAK a
dispatchelt `full-gate.yml`-en fut. A GitHub log-API az utolsó 5000 sort adja
(≈4500 teszt), a 10 300-as suite első fele láthatatlan — a rejtett piros
cellákat **eldobható szelet-ágakkal** tettem láthatóvá (`claude/e18-fixes-diag`,
`claude/e18-diag-a/b/c`: a suite egy-egy része, a többi tesztfájl törölve;
**soha nem mergelendők, a user boxáról törlendők**: `git push origin --delete
claude/e18-fixes-diag claude/e18-diag-a claude/e18-diag-b claude/e18-diag-c`).

| CI-kör | Piros | Ok | Javítás |
|---|---|---|---|
| 1 | format gate, 10 fájl | nincs helyi `dart format` | kézzel a tall-stílus szabályai szerint |
| 2 | 9 cella | cél-feloldó tag-előny a mód helyett; a bejelentés nyers címkét követett; Riverpod `ProviderException`; szint-padló | mód > tag; stabilizált bejelentés (ADR 0539 D1); `throwsA(anything)`; padló 0.05 |
| 3 | 3 rejtett cella | a log-tail mögött | szelet-ágak (fent) |
| 3/a | `live_stage_test` A2b: `RenderFlex overflowed by 2.5 px` (`chord_timeline.dart:94`) | az üres-prompt a hős-helyen NEM-flex `FittedBox`-ként ült, a szövege 288 px-es sávon 290,5 px | a prompt laza `Flexible` (3:1 a történettel), 200 px-es tördelési szélesség, `scaleDown` |
| 3/b | `release_flow_text_scale_test` en+hu @2.0: `practice_setup_screen.dart:424` 43 px | az E12-R20 ismert kivétel SORSZÁMRA volt tűzve (`:418`); az F4 `_backToHub`-javítása 6 sort tolt → a tolerancia elavult → a cella (helyesen) piros | **a hibát javítottam, nem a tűt mozgattam**: `_ScoringProfileReadout` azonosítója a sor 60 %-ára korlátozva tördelődik (`LayoutBuilder` + `ConstrainedBox`, `textAlign: end`; természetes szélességnél a pixel-golden változatlan — az első, `Flexible`-alapú próbálkozás az `e13_r21_practice_setup_compact` goldent 0,9 %-kal elmozdította, ezért lett cserélve); a bejegyzés kikerült a `knownOverflows` tükörből és a `known-exceptions.yaml`-ból (zsugorodó registry, A6 őr); `release-audit.md` + `known-issues.md` frissítve |

## Nem futtatott ellenőrzések és okuk

- `tools/round-gate.sh` / `flutter analyze` / `flutter test` **lokálisan nem
  futott**: a remote konténerben nincs Flutter/Dart SDK (mért képességtérkép:
  `docs/execution/remote-container-environment.md`). A gépi bizonyíték a
  kör-branchre dispatchelt CI (`build-apk.yml` — a `pubspec.yaml` érintett →
  ADR 0171 natív kapu), linkje a HANDOFF-ban.
- Pixel-goldenek: egyetlen golden-képernyő kimenete sem változott szándékosan
  (a hub 5 chipje megmaradt; a Songs AppBar-ikon nem golden-képernyő; a Live
  golden keret akkordot hord).
- Valós gitáros mérés: a felhasználó boxán (HORIZON végső mérce).
