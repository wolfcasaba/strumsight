# Epic 1 baseline — a program kiinduló állapota

**Felvéve:** 2026-07-28 (E01-R01, round 207) · **Commit-alap:** lásd a kör commitját
**Box:** linux_arm64 (Oracle), a fejlesztés CI-vel buildel APK-t (lokálisan nem)

## Verziók

| Eszköz | Verzió | Terv-elvárás | Egyezik? |
|---|---|---|---|
| Flutter | 3.44.2 stable (rev c9a6c48423) | 3.44.2 | ✅ |
| Dart | 3.12.2 stable | ^3.12.2 | ✅ |
| Python | 3.12.3 | 3.11 ajánlott | ⚠ 3.12 van a boxon — működik (backend 29 teszt zöld); CI-ben rögzítendő (E01-R15) |
| Java/JDK | CI-ben 17 | 17 | ✅ (lokál APK-build nincs) |

## Kódbázis-számok

- Dart forrásfájl (`lib/`): **168**
- Dart tesztfájl (`test/`): **163**
- Backend tesztfájl (`backend/tests/`): **6** (29 teszt)
- SDD: **Ch1–12 TELJES** a `docs/sdd/` alatt (Ch8 a 3. feltöltési batchben érkezett)

## Fő feature-ök (mind működik, 204 kör terméke)

live (REAL mic detektálás + r185 chord timeline), analyze (+ r197 ML-flag Lab),
learn, tuner, metronome, chords, songs+setlists, progress, streak, settings,
onboarding, share (Strum Card / Wrapped), auth (opcionális), diagnostics (Lab),
library — plusz pure-Dart DSP (chroma/Viterbi/SuperFlux/YIN) és CRNN inference.

## CI workflow-k

`build-apk.yml` (APK artifact), `lab-apk.yml`, `chord-train.yml`, `dsp-probe.yml`,
`ml-train.yml`. **Nincs még:** külön backend-CI, format gate, architecture gate,
production signing (E01-R14/15 hozza).

## Baseline ellenőrzések (2026-07-28, külön parancsokként)

| Parancs | Eredmény |
|---|---|
| `flutter pub get` | ✅ OK (32 csomagnak van újabb, constraint-en kívüli verziója — nem hiba) |
| `flutter analyze lib/ test/` | ✅ **No issues found** (a kör záró mérése: 5.5s) |
| `flutter test` (teljes suite) | ✅ **700 passed / 2 skipped** (14:38, exit 0) — a kör záró, újramért értéke; a 159 tesztfájl ~680 statikus `test(`/`testWidgets(` deklarációjával konzisztens |
| `flutter test test/features/live/` | ✅ **171 passed / 2 skipped** (a piros baseline javítása után) |
| `flutter test test/property` | ✅ zöld (a teljes futásban benne; PROPERTY_SEED nélkül = seed 42) |
| `backend: pytest` | ✅ **29 passed** (7.3s; friss `backend/.venv` — a boxon nem volt, létrehozva) |
| `dart format --set-exit-if-changed` | ⏳ NEM futott — a formázási állapot felmérése az E01-R14 format-gate köréhez tartozik; most futtatása tömeges, körön kívüli diffet okozna |
| valós eszközös audio gate | ⏳ NEM futtatható a boxon — a user telefonos APK-tesztje a végső kapu (CI-buildelt APK-val) |

**Piros baseline → minimális javítás a körben:** a baseline-futtatás EGY piros tesztet talált —
`test/features/live/live_lab_panel_test.dart` még a régi `~30 s` gombfeliratot várta, miközben az
l10n a r201 óta `~60 s`-ot szállít (string-drift, nem viselkedési hiba). A forrás-igazság az l10n
string, ezért a **teszt** lett hozzáigazítva (`'~30 s'` → `'~60 s'`), `lib/` nem módosult; a kör
lezárásakor a Live-részhalmaz és a teljes suite zöld.

## Ismert technikai adósságok (a terv Ch2 §3.4 listája — MIND MEGERŐSÍTVE)

1. Package név `music_theory`; azonosítók `com.musictheory.music_theory`
   (`android/app/build.gradle.kts:8,22`) → E01-R02.
2. **Release build debug kulccsal íródik alá** (`build.gradle.kts:35`) → E01-R14.
3. Backend `create_all` indításkor (`backend/app/main.py:40`) → E01-R12.
4. Nincs egységes AppResult/AppFailure/strukturált logging → E01-R04.
5. SharedPreferences közvetlen provider-használat → E01-R05/06/07.
6. Cross-feature belső importok; nincs architecture guard → E01-R10.
7. Statikus `String.fromEnvironment` konfiguráció → E01-R03.
8. Nincs backend-CI / format gate → E01-R14/15.

## Dokumentációs eltérések (E01-R01 1.5 feladat — feljegyzés, javítás az E01-R16 körben)

- `README.md` „Status (v0.2.0)" — a `pubspec.yaml` **1.0.0+1**; verzió-igazságforrás rendezendő (E01-R02 2.4).
- README „Analyze/Library 🔜 v2 (placeholders)" — valójában rég KÉSZ (batch chord timeline,
  Library, Lab-diagnosztika, ML-flag). A README a v0.2-es állapotot tükrözi, a repo a 204. körnél jár.
- README nem említi: Learn/Practice, Songs/Setlists, Streak, Share, Metronome, Lab mód.
- `CLAUDE.md` a Supabase-t "unconfigured → mock mode"-ként említi; valójában FastAPI backend van (r14 döntés).
- A HANDOFF hosszú történeti napló — egyszerűsítés az E01-R16 16.6 szerint (archívummal).

## Nem futtatható ellenőrzések és indoklás

- **APK build lokálisan:** a box nem tud APK-t buildelni (memória/toolchain) — CI végzi
  (`build-apk.yml`), a kész APK GitHub Release linkként megy a usernek.
- **ML training:** külön workflow (`ml-train.yml`, `chord-train.yml`), nem fut fejlesztési körben.
- **Valós gitár / mikrofon / thermal tesztek:** csak a user telefonján lehetségesek.
