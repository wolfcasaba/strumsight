# E18-R01 — Kézi tesztterv Android-EMULÁTORON (VS Code + Claude Code a laptopon)

> **Kinek:** a laptopon futó Claude Code sessionnek (és a felhasználónak).
> **Mit:** a `claude/song-editor-chord-audio-tbkokz` ág (E18-R01, ADR 0535) —
> akkord-meghallgatás a dalszerkesztőben + menet-előnézet.
> **Hol:** Android-emulátor, NEM valódi telefon. A hang az emulátorból a
> laptop hangszóróján szól (a `audioplayers` az emulátorban működik).
> Mikrofon ehhez a körhöz NEM kell: a meghallgatás csak lejátszás.
> **Végső mérce továbbra is** a felhasználó valódi gitáros APK-tesztje
> (CLAUDE.md), ez a terv az emulátoros elő-ellenőrzés.

## 0. Előkészítés (a laptopon)

```bash
cd /home/ubuntu/music-theory            # a repó valódi otthona
git fetch origin
git checkout claude/song-editor-chord-audio-tbkokz
git pull origin claude/song-editor-chord-audio-tbkokz
flutter pub get
flutter emulators                        # válassz egy Pixel-profilt (API 34 ajánlott)
flutter emulators --launch <emulator-id>
flutter devices                          # emulator-5554 legyen a listában
```

VS Code-ban: a Flutter-bővítménnyel válaszd az emulátort a státuszsorban, majd
`Run → Start Debugging` (vagy terminálból `flutter run -d emulator-5554`).
A laptop hangereje legyen felhúzva; az emulátor „Extended controls → Settings →
Audio" ne legyen némítva.

**Tilos ezen a boxon:** `flutter analyze && flutter test` láncolva (OOM); a
`tools/**` és `.github/workflows/**` módosítása; a `hold` queue-sorok
átírása. Ha bármi bukik: JELENTS, ne javíts csendben (ADR 0055 — a javítás a
következő javító kör dolga; a jelentés helye lent, §4).

## 1. Automata kapu ELŐSZÖR (kb. 15 perc)

```bash
tools/round-gate.sh test/core/audio/plucked_string_synth_test.dart test/core/music/chord_voicing_test.dart test/features/learn/ test/features/songs/ test/features/song_trainer/presentation/ test/features/chords/ test/features/tuner/ test/core/architecture_dependency_test.dart test/ui/goldens/e15_r13_full_variant_matrix_test.dart test/ui/goldens/e13_r24_screens_golden_test.dart test/core/screen_size_guard_test.dart test/app/routing/app_router_test.dart test/features/songs/import/editor_draft_test.dart test/tooling/placeholder_wiring_test.dart
```

Elvárt: minden lépés zöld (a CI-n a `476b01d` HEAD-en már zöld volt:
https://github.com/wolfcasaba/strumsight/actions/runs/34386737962).

**Falszifikációs próbák (brief §6.1) — mindhárom PIROSAT kell adjon, utána
visszaállítani (`git checkout -- <fájl>`):**

| # | Mutáció | Melyik cellának kell pirosra váltania |
|---|---|---|
| P1 | `lib/core/audio/synth/plucked_string_synth.dart` → `strumOnsets`-ben cseréld fel a `downstroke ? i : count - 1 - i` ágat | `plucked_string_synth_test.dart` A2 (le/fel irány) |
| P2 | `lib/features/learn/audio/chord_audition.dart` → a `hasKnownQuality` kapu kikommentezése | `chord_audition_test.dart` „UNKNOWN quality is silence" |
| P3 | `lib/features/songs/application/song_preview_player.dart` → a záró `stop()` helyett `Timer(_delay(totalSec - schedule.last.timeSec), stop)` (a régi, dupla-várakozó változat) | `song_preview_player_test.dart` „the bar advances… stops on its own" |

## 2. Kézi teszt az emulátoron — a legacy dalszerkesztő (Songs → New song)

Navigáció: az app `Songs` fülén (vagy a `/songs` útvonalon) `New song`.

| # | Lépés | Elvárt | Eredmény |
|---|---|---|---|
| E1 | Indítás, konzol figyelése (`flutter run` kimenet) | nincs kivétel, nincs `MissingPluginException`, nincs `RenderFlex overflowed` | |
| E2 | „Add a chord" alatt koppints a `C` chipre | HALLHATÓ egy lepengetett C-dúr (5 húr, mély→magas söprés, gitárszerű, kb. 1,5 s kicsengés); a `C` chip megjelenik a menetben | |
| E3 | Koppints a menetben lévő `C` chip CÍMKÉJÉRE (ne az ×-re) | újra szól; a menet NEM duplázódik és nem törlődik | |
| E4 | Koppints a chip `×`-ére | a chip eltűnik, NEM szól semmi | |
| E5 | Adj hozzá `E`, `Am`, `G`, `F#m` chipeket egymás után | mindegyik a SAJÁT fogásával szól (E = 6 húr, F#m = barré, magasabb) — füllel eltérő hangzás | |
| E6 | Gyorsan (0,2 s-onként) koppints 8-10 chipre | nincs fagyás/kivétel; az új pengetés levágja az előzőt | |
| E7 | Menet: `C G Am F`, minta: a default (↓ minden ütésre), tempó 90 → nyomd meg a ▶ ikont a „Chord progression" fejlécsorában | a menet ütemenként szól (4 ↓ ütemenként, 90 BPM ≈ 0,67 s-onként); a SZÓLÓ ütem chipje kiemelt (`selected`); az ikon ■-re vált, tooltipje „Stop preview" | |
| E8 | Hagyd végigfutni | az utolsó (F) ütem kicsengése után az ikon MAGÁTÓL ▶-re vált; NEM vár egy plusz ütemet (kb. 10,7 s a 4 ütemre @90) | |
| E9 | ▶, majd 2 ütem után ■ | azonnali csend, kiemelés eltűnik | |
| E10 | ▶ közben válts mintát (preset chip), vagy tempót, vagy 3/4-re | az előnézet LEÁLL (nem játszik elavult ütemtervet); ▶ újra indítható | |
| E11 | Minta: `Eighths` preset (↓↑ nyolcadok) + ▶ | fel-pengetéskor a söprés iránya megfordul (magas→mély), füllel érzékelhető | |
| E12 | ▶ közben lépj vissza (back) a Songs listára | AZONNALI csend; visszalépve a szerkesztőbe minden újra működik | |
| E13 | Menet üres → ▶ ikon | tiltott (szürke) | |
| E14 | Emulátor: Settings → Display → Font size = legnagyobb, Display size = legnagyobb; nyisd meg újra a szerkesztőt | a fejlécsor (CHORD PROGRESSION · ▶ · Suggest) NEM csordul túl (nincs sárga-fekete csík / overflow a konzolban) | |
| E15 | Mentsd a dalt, nyisd meg Learn-ben (Play) | a jam-mód pad HANGJA VÁLTOZATLAN (lágy szinusz-pad, nem a pengetett hang) — a kör ezt nem érinti | |

## 3. Kézi teszt — a V2 szerkesztő (Song library V2 → új dal)

| # | Lépés | Elvárt | Eredmény |
|---|---|---|---|
| V1 | Chord mező: `Dm` → `Add chord` | HALLHATÓ a Dm fogás; a chord trackben egy esemény | |
| V2 | `Ebm` → `Add chord` | szól (nincs fogás → akkordhangok C3 körül, 3 hang, vékonyabb) | |
| V3 | `Cdim` → `Add chord` | NEM szól (ismeretlen utótag → csend, nem dúr-találgatás); az esemény attól még létrejön | |
| V4 | `Zz9` → `Add chord` | nem szól, nincs kivétel | |
| V5 | Nézd meg a képernyőt | NINCS külön „Hear chord" gomb — szándékos (pixel-golden, E18-R02) | |
| V6 | Undo/Redo, mentés | változatlanul működik, hang csak Add-nál | |

## 4. Megfigyelések, amiket KÉRÜNK feljegyezni (nem bukás-kritérium)

- Az első koppintás késleltetése (szintézis a UI szálon, ~0,6 M művelet): érezhető-e jank az emulátoron? (Valódi eszközön külön mérendő.)
- Előnézet közben az app háttérbe küldése (Home): szól-e tovább? (A kör csak a route elhagyásánál hallgattat el — jegyezd fel a viselkedést, follow-up döntés.)
- Hangerő/torzítás: a pengetett hang csúcsa `amp = 0,6` — túl halk/hangos?

## 5. Jelentés

Írd az eredményt a `docs/reviews/e18-r01-emulator-report.md` fájlba (a fenti
táblák PASS/FAIL oszloppal, a konzol releváns sorai, emulátor-profil és API
szint), commitold és pushold ugyanerre az ágra:

```bash
git add docs/reviews/e18-r01-emulator-report.md
git commit -m "docs(E18-R01): emulator test report"
git push origin claude/song-editor-chord-audio-tbkokz
```

Ha bármely cella FAIL: a jelentésbe pontosan mi történt (lépés, elvárt,
tapasztalt, konzol-kivonat) — a javítás a következő kör dolga.

## 6. Egyéb teendők ugyanebben a sessionben (a HANDOFF szerint)

```bash
git push origin --delete claude/e18-r01-diag claude/e18-diag-a1 claude/e18-diag-a2 claude/e18-diag-a3 claude/e18-diag-b1 claude/e18-diag-b2 claude/e18-diag-b3 claude/e18-diag-c1 claude/e18-diag-d1
git fetch origin 'refs/notes/*:refs/notes/*' || true
git notes add -f -m "round=E18-R01 verdict=pass tests=10272 lesson=ci-log-cap-bisect-on-throwaway-branches" $(git rev-parse HEAD)
git push origin 'refs/notes/*'
```

---

# B. rész — A FELISMERŐ RENDSZER és a teljes app emulátoros ellenőrzése

> A kör (E18-R01) nem nyúlt a detektorhoz, de a merge előtt az egész appnak
> működnie kell. Ez a rész a felismerés (akkord + pengetésirány), a tuner, a
> Learn-pontozás, az Analyze, a kalibráció és a hordozó képernyők
> emulátoros ellenőrzése. A mérce: `AGENTS.md` §5 (nyers audio nem hagyja el
> az eszközt; egy mikrofon-tulajdonos; gyenge konfidencia sosem biztos
> állítás) és a `docs/release/full-app-verification.md`.

## 7. Hang BE az emulátorba — mikrofon-beállítás

Az emulátornak nincs saját mikrofonja; a laptopét kapja meg:

1. Emulátor ablak → `⋯` (Extended controls) → **Microphone** → kapcsold be a
   **„Virtual microphone uses host audio input"** kapcsolót.
2. Az app első mikrofonkérésekor az Android-dialógusban **Allow** (a
   „megtagadás" ágat a §8 külön méri).
3. Ellenőrzés: `adb shell dumpsys audio | grep -i "input"` mutasson aktív
   bemenetet, amíg a Live képernyő hallgat.

**Hangforrások, erősségi sorrendben:**

| Forrás | Mire jó | Megjegyzés |
|---|---|---|
| **Valódi gitár a laptop mikrofonja mellett (20–40 cm)** | akkord + pengetésirány — EZ az igazi mérce | a felhasználó játszik; a session utasítja, melyik akkordot/irányt |
| YouTube „open C major chord guitar" típusú videó a laptop hangszóróján, a mikrofon előtt | akkordfelismerés füstteszt, ha nincs kéznél gitár | a hangszóró→mikrofon út színezi a jelet; a pengetésirány itt nem mérhető megbízhatóan |
| Laptop belső visszacsatolás (PipeWire/Pulse „Monitor of …" mint bemenet, Windows: VB-Cable) | determinisztikus lejátszás fájlból | opcionális; ha beállítod, jegyezd fel a jelentésbe |

## 8. Onboarding, engedély, First-Win (E17-R01 útja)

Friss telepítéssel indítsd (`adb uninstall com.strumsight.app` vagy az app
adatainak törlése), hogy az onboarding fusson.

| # | Lépés | Elvárt | Eredmény |
|---|---|---|---|
| O1 | Welcome → Next → engedély-primer → „Enable mic & start" → Android-dialógus: **Allow** | a First-Win állomás VALÓS konfidenciát mutat („Listening…" NEM ragad be; pengetés nélkül nulla/alacsony, pengetéskor mozog) | |
| O2 | Játssz egy tiszta Em-et vagy G-t | a küszöb (0,60, inkluzív) átlépésekor a Continue/siker-ág megjelenik | |
| O3 | „Not now" | ELHAGYJA az állomást (nem ragad ott), a pontozott mini-lecke jön | |
| O4 | Friss telepítés újra, az Android-dialógusban **Deny** | a hiba KIMONDVA jelenik meg (`micPermissionBody` + „Open settings"), a továbblépés elérhető, nincs néma „Listening…" | |
| O5 | Onboarding vége | a shell `/today`-on vagy `/live`-on landol (jegyezd fel, melyiken — a `full-app-verification.md` L2 nyitott tétel) | |

## 9. Live — akkord + pengetésirány felismerés (a moat)

Navigáció: Practice fül → Live (vagy `/live`). Gitárral, a laptop mikrofonjánál.

| # | Lépés | Elvárt | Eredmény |
|---|---|---|---|
| L1 | Képernyő megnyitása | „Listening"/„Starting…" majd „Play a chord…"; az input-szint kijelző mozog a beszédre/pengetésre | |
| L2 | Pengesd le lassan, tisztán: **C, G, D, Em, Am, E, A, Dm** (mindegyiket 2–3 s-ig tartva) | a nagy akkordcímke ≤ 1 s-on belül a JÓ akkordot mutatja, a konfidencia-% a beállított küszöb (Settings → Confidence threshold, default) fölött; 8-ból legalább 7 helyes | |
| L3 | Ugyanaz, de le-pengetés (↓) ötször, majd fel-pengetés (↑) ötször | a nyíl iránya a pengetéssel egyezik legalább 8/10-szer; egy pengetés = EGY nyíl (nincs fantom második onset ~0,6 s-mal később — E14-R19 lelet) | |
| L4 | Egyetlen akkord kitartása 3 s-ig pengetés nélkül | NEM jelenik meg új nyíl a kicsengésre | |
| L5 | Csend / beszéd a mikrofonba | nincs akkordcímke, a „No chord detected yet" / „Weak signal — move closer" jelenik meg — SOHA nem magabiztos hamis akkord | |
| L6 | Tompított, zavaros pengetés (tenyérrel lefogva) | a „miért nem sikerült" banner az egyik hat okot mondja (`Not quite clear` / `Still settling` / `Signal too weak` …), és MELLETTE nem jelenik meg az általános „Weak signal" szöveg (E14-R13) | |
| L7 | Pause → Resume | pause alatt semmi nem frissül; resume után újra felismer | |
| L8 | Settings → Capo: 2. bund, vissza Live-ra, játssz egy D-fogást | a címke a FOGÁST mutatja (D), a „Capo 2" jelzés látszik | |
| L9 | Settings → Confidence threshold felhúzása magasra, vissza Live | több pengetés „unsure"/bizonytalan, nem hamis-biztos | |
| L10 | Live hallgat közben nyisd meg a Tunert (Live „Tuner" gomb vagy fül-váltás) | NINCS néma holt stream: vagy szabályos átadás, vagy kimondott „foglalt" hiba; visszalépve a Live újra hallgat | |
| L11 | Live hallgat → Home gomb (háttér) → vissza | a mikrofon elengedve a háttérben (`dumpsys audio` bemenet megszűnik), és NEM indul újra magától; a képernyő Resume/újraindítást kínál | |
| L12 | 5 perc folyamatos hallgatás | nincs memória-növekedés jele (`adb shell dumpsys meminfo <pkg>` elején/végén ±20 %-on belül), nincs jank a konzolban | |

## 10. Tuner

| # | Lépés | Elvárt | Eredmény |
|---|---|---|---|
| T1 | Nyisd meg, pengesd az üres E2 (6.) húrt | az E2 chip világít, a cent-mutató a hangolás állapotát követi; ±5 cent zöld | |
| T2 | Sorban A2 D3 G3 B3 E4 | mindig a JÓ húr chipje világít (log-távolság alapján a legközelebbi) | |
| T3 | Fütty / ének | egyetlen chip sem világít, ha 5 félhangnál messzebb (őszinte, nem találgat) | |
| T4 | Húr pinnelése + referencia-hang gomb | a pin-nelt húr referenciahangja szól ~1,5 s; képernyő elhagyásakor AZONNAL elhallgat | |
| T5 | Settings → Tuning reference 432 Hz → vissza | a mutató eltolódik (a 440-es húr most „magas"); Drop D tuning választásakor a 6. húr D2 | |

## 11. Learn — play-along + pontozás + streak

| # | Lépés | Elvárt | Eredmény |
|---|---|---|---|
| P1 | Learn → „First Strums" (Em/G, 70 BPM) → Play | egy ütem count-in (4 villanás), a highway jobbról balra fut, az ütésvonalnál pulzál | |
| P2 | Játssz a nyilakkal együtt (↓ az ütésekre) | Hit/„Nice! ↓↑" villan, combo nő; szándékos ↑ egy ↓-helyen → „Wrong way!"; kihagyás → „Miss" | |
| P3 | Lecke vége | Score-összegző (hits/total, best combo), ≥70 % → „Passed! 🎉"; a Streak képernyő „Practised today ✓"-ra vált | |
| P4 | Jam mode be | a chord-pad szól minden ütem első ütésén (lágy szinusz — NEM a pengetett audition-hang), nincs pontozás, a mikrofon el van engedve | |
| P5 | Easy mode + Speed 0.75 | csak on-beat ↓ nyilak; lassabb highway | |
| P6 | Metronome be a leckében | kattanás az ütéseken, a highway-jal szinkronban (nem drift-el 1 percig — ADR 0274) | |
| P7 | Songs → egy saját dal → Play | ugyanaz a Learn-futás a saját menettel/mintával; 3/4-es dal esetén 3 ütéses count-in | |

## 12. Analyze — felvétel → akkord-idővonal (az E18-R02 alapja)

| # | Lépés | Elvárt | Eredmény |
|---|---|---|---|
| A1 | Analyze → Record, játssz 10–15 s-ot: C (4 ütem) → G (4 ütem) → Am → F | „Playing — StrumSight is listening…", Stop → „Analysing…" → idővonal: a 4 akkord a jó sorrendben, a ↓/↑ összegzés („N down · M up") a valósághoz közeli | |
| A2 | Save | „Saved to Library"; Library → a felvétel megnyitható, átnevezhető, törölhető | |
| A3 | Record 5 s csend → Stop | „No chords detected. Try again…" — nincs kitalált akkord | |
| A4 | Felvétel közben Home (háttér) | a felvétel leáll/elengedi a mikrofont, nincs crash | |
| A5 | Egy mentett felvétel → Share (Strum Card) | a kártya és a reel megjelenik, a pengetésnyilak a felvétel szerint | |

## 13. Kalibráció (Settings/Practice → Timing calibration)

| # | Lépés | Elvárt | Eredmény |
|---|---|---|---|
| K1 | Audio mód → Start → 8 koppintás a kattanásra | „Your delay: N ms" (emulátoron tipikusan 20–120 ms), Save → „Calibration saved", a Settings mutatja az offsetet | |
| K2 | Szándékosan rendszertelen koppintás | „Taps were inconsistent — try again" — nem ment el rossz értéket | |
| K3 | Visual mód | ugyanaz a villanásra | |

## 14. Hordozó képernyők — füstteszt (mindegyik: megnyílik, nincs kivétel, vissza)

| # | Képernyő | Mit nézz |
|---|---|---|
| H1 | Today hub | új felhasználónak „Let's get started" + CTA; a CTA a Practice-be visz |
| H2 | Practice area hub → Setup → Session → Result | a V2 practice-motor (nonProd-ban be van kapcsolva): egy 1 perces session lefut mikrofonnal, az eredmény-képernyő számai nem NaN/üresek |
| H3 | Chord library | tap-to-hear: a PAD szól (változatlan, nem a pengetett hang — ADR 0535 D5); Settings → Left-handed → a diagramok tükröződnek |
| H4 | Metronome | Start/Stop, Tap tempo, 3/4 és 4/4, hangsúly az 1-en; a kattanás egyenletes 1 percig |
| H5 | Unified Library | a mentett Analyze-felvétel és a saját dal is látszik; törlés megerősítéssel |
| H6 | Progress dashboard, Profile hub, Streak, Gamification hub/quests/inbox | megnyílnak, a számok a ma játszott leckét tükrözik |
| H7 | Settings | nyelvváltás en↔hu azonnal (minden szöveg, a ▶/■ tooltip is: „Előnézet"/„Előnézet leállítása"), Appearance világos/sötét/rendszer, Daily reminder kapcsoló |
| H8 | Song Trainer V2 (ha a dev build mutatja): Import → `test/fixtures/song_trainer/musicxml/chord_chart_44.musicxml` (adb push-sal az emulátorra) | preview → import → a dal a könyvtárban; `corrupt.musicxml` → kimondott hiba, nem crash; a session (transport, count-in, loop) lefut |
| H9 | Kijelentkezett, diagnostics-off állapot | `adb logcat | grep -iE "http|socket"` — NINCS rejtett hálózati kérés a képernyők bejárása alatt (AGENTS §5) |
| H10 | Elforgatás (landscape) a Live-on, a Learn-en, a builderben | nincs overflow, a hallgatás/lejátszás nem szakad meg |

## 15. Automata teljes-app ellenőrzés a laptopon (SDK-val, egyenként futtatva)

```bash
flutter analyze lib/ test/ tool/
flutter test                                  # TELJES suite, EGYEDÜL (~15 perc, sose láncold az analyze-zal)
PROPERTY_SEED=$RANDOM flutter test test/property   # randomizált property-kapu, jegyezd fel a seedet
flutter test test/tooling/real_audio_dsp_baseline_test.dart   # valós-audio DSP alapvonal
flutter test test/e2e/full_app_walkthrough_test.dart
dart run tool/check_screen_reachability.dart --format json | head -5
flutter build apk --debug && adb install -r build/app/outputs/flutter-apk/app-debug.apk
adb logcat -c; adb logcat | grep -iE "flutter|exception|error|StrumSight" | head -200   # a §8–§14 bejárás közben
```

Elvárt: minden zöld; a reachability `unreachable` száma ne nőjön a HANDOFF-ban
mérthez képest; a logcat-ben nincs `Exception`/`RenderFlex`.

## 16. Jelentés bővítése

A `docs/reviews/e18-r01-emulator-report.md`-be a §2–§3 mellé a §8–§14 táblái
is PASS/FAIL-lel, plusz: emulátor-profil, API-szint, host OS, hangforrás
(gitár/videó/loopback), a §15 parancsok kimenetének utolsó sorai, a property
seed. Bukásnál lépés + elvárt + tapasztalt + konzol-kivonat — javítás nélkül
(a javítás a következő kör dolga, ADR 0055).
