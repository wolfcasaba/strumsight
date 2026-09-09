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
