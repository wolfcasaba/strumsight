# E18-R01 javító kör — emulátoros ELLENŐRZŐ jelentés (2026-09-10)

> Szerep: ELLENŐRZŐ (ADR 0055). A `lib/**` és `test/**` alatt semmi nem
> módosult, golden nem lett regenerálva, konstans nem lett hangolva.
> A prompt: [`e18-r01-emulator-verify-prompt.md`](e18-r01-emulator-verify-prompt.md).

## 0. Profil

| Elem | Érték |
|---|---|
| ág / HEAD | `claude/optimistic-bohr-vpaxh4` @ `2eee1091` (a prompt „2d258e08 vagy újabb" feltétele teljesül) |
| emulátor | AVD `Pixel_3a_API_34_extension_level_7_x86_64`, Android 14 / API 34, 1080×2220 @ 440 dpi = **392 dp széles**, `-allow-host-audio` **igen** |
| hangforrás | **WAV**, 44,1 kHz mono 16 bit PCM — a Wikimedia Commons közkincs, valódi akusztikus gitár felvételeiből (`A-major.ogg` … `G-major.ogg`, „The chord of X major played on an acoustic guitar"), az EREDETI OGG Vorbisból `libsndfile`-lel dekódolva. **NEM a 64 kbps MP3-transzkódból.** Csúcsra normalizálva (0,89) — indoklás a §5-ben. |
| loopback | Windows felvevő alapeszköz = Stereomix (Realtek), felvétel 70 %, lejátszás 70 %, kimenet Speaker (Realtek) |
| Flutter / Dart | `Flutter 3.44.2 • channel stable`, revízió `c9a6c48423`; Dart 3.12.2 |
| build | **debug**, `flutter build apk --debug` + `adb install` (friss telepítés) |
| gazdagép | Windows 11 Home 25H2 (10.0.26200); a repó ékezetmentes worktree-ben: `C:\src\ss-e18` (az ékezetes útvonal az analyzert 255-tel összeomlasztja — E18-R01 F12) |

**Eltérés a prompttól (nem javítottam, jelentem):** a prompt §1 és §3 a
`com.strumsight.app` csomagnevet írja. A valódi `applicationId`
`com.wolfcasaba.strumsight` (`android/app/build.gradle.kts`); az
`adb uninstall com.strumsight.app` `Failure [DELETE_FAILED_INTERNAL_ERROR]`-t
ad. A friss telepítés a helyes névvel történt. Ugyanez a hiba az E18-R01
tervben is szerepelt (S4).

## 1. Automata kapu

```
tools/round-gate.sh test/features/live test/features/practice_hub \
  test/features/practice test/accessibility test/app/bootstrap \
  test/features/songs test/features/ai_tutor/data test/property
```

Külön processzben, csővezeték nélkül (`FLUTTER_BIN`/`DART_BIN` a
`C:\src\flutter` felé). Záró kimenet:

```
    → [1] format: ZÖLD
    → [2] analyze: ZÖLD
    → [3] test test/features/live: ZÖLD
    → [4] test test/features/practice_hub: ZÖLD
    → [5] test test/features/practice: ZÖLD
    → [6] test test/accessibility: ZÖLD
    → [7] test test/app/bootstrap: ZÖLD
    → [8] test test/features/songs: ZÖLD
    → [9] test test/features/ai_tutor/data: PIROS (kilépési kód 1)
GATE_EXIT=10

═══ Gate-összegzés
    format                                                     zöld
    analyze                                                    zöld
    test test/features/live                                    zöld
    test test/features/practice_hub                            zöld
    test test/features/practice                                zöld
    test test/accessibility                                    zöld
    test test/app/bootstrap                                    zöld
    test test/features/songs                                   zöld
    test test/features/ai_tutor/data                           PIROS (1)
```

A kapu a 9. lépésnél kilépett, ezért a **10. lépés (`test/property`) külön
futott** — zölden:

```
PROPERTY_SEED=2793
00:59 +123: All tests passed!
PROPERTY_EXIT=0
```

### A piros cella TELJES hibablokkja — `test/features/ai_tutor/data`

Végösszeg: `00:18 +116 -3: Some tests failed.` — **116 zöld, 3 piros**.
A három piros mind a `knowledge_manifest_test.dart`-ban van:

```
00:07 +37 -1: .../knowledge_manifest_test.dart: buildTutorKnowledgeManifest writes a bit-identical manifest when built twice [E]
  KnowledgeManifestException(tutorKnowledge.manifest.missingLicense, path: C:\Users\kcsab\AppData\Local\Temp\strumsight-knowledge-test-5b2ecddb/tutor_knowledge\manifest.json)
  tool\build_tutor_knowledge_manifest.dart 52:7                    buildTutorKnowledgeManifest
  test\features\ai_tutor\data\knowledge_manifest_test.dart 187:5   _KnowledgeFixture.build
  test\features\ai_tutor\data\knowledge_manifest_test.dart 128:15  main.<fn>.<fn>

00:07 +37 -2: .../knowledge_manifest_test.dart: buildTutorKnowledgeManifest the committed manifest is locked to its content and chunk hashes [E]
  KnowledgeManifestException(tutorKnowledge.manifest.missingLicense, path: assets/tutor_knowledge\manifest.json)
  tool\build_tutor_knowledge_manifest.dart 52:7                   buildTutorKnowledgeManifest
  test\features\ai_tutor\data\knowledge_manifest_test.dart 138:9  main.<fn>.<fn>

00:07 +37 -3: .../knowledge_manifest_test.dart: buildTutorKnowledgeManifest the committed pack covers every required topic in both locales [E]
  KnowledgeManifestException(tutorKnowledge.manifest.missingLicense, path: assets/tutor_knowledge\manifest.json)
  tool\build_tutor_knowledge_manifest.dart 52:7                   buildTutorKnowledgeManifest
  test\features\ai_tutor\data\knowledge_manifest_test.dart 154:7  main.<fn>.<fn>
```

**Értékelés (nem javítottam):** a hibaüzenet útvonala **kevert
elválasztójelű** — `assets/tutor_knowledge\manifest.json`. Ez a Windows
path-join műtermék, amit az E18-R01 jelentés **F12**-ként dokumentált (a
203 Windows-piros egyike; a mérce a linuxos CI, ADR 0053). Ugyanez a
tesztfájl az E18-R01 mérésben is piros volt ugyanezzel a mintával.
**Nem regresszió, és nem az F1 javítás mércéje.**

**Az F1 javítás SAJÁT két cellája ZÖLD** ugyanebben a futásban:

```
00:00 +1: .../bundled_knowledge_assets_test.dart: every document the on-disk manifest lists is readable from the COMPILED asset bundle
00:00 +2: .../bundled_knowledge_assets_test.dart: the production repository loads the full index from the bundle — no fallback code
```

## 2. Ítélet-tábla

| ID | Ítélet | Amit láttam | Bizonyíték |
|---|---|---|---|
| V-F1 | **PASS** | Az APK mind a 11 tudás-fájlt tartalmazza (manifest + 5 en + 5 hu); az E18-R01-ben csak a `manifest.json` volt benne. Friss telepítés + indítás után **0** `tutor.knowledge_index.load_failed` / `assetReadFailure` a naplóban (korábban minden indításnál jött). | `unzip -l` kimenete lent (§4-mentes, PASS); `adb logcat -d \| grep -icE "tutor.knowledge_index.load_failed\|assetReadFailure"` → `0` |
| V-F2 | **PASS** | 6 pengetés C-re: hős-kártya a helyes `x32010` fogásábrával. 3 s csend után a kártya **eltűnt**, a hős helyén a **„Play a chord…" prompt**, a `C` kis szürke címkeként a történet-sávba hátrált. Négy egymást követő csend-mintában végig így. | `assets/e18-r01-verify/V-F2-silence-prompt.png`, `V-F2-strum-card.png` |
| V-F3 | **PASS** | Csendben **nincs konfidencia-szám és nincs nyíl** a hős-helyen. Pengetés közben 87 % látszik — de ez nem beragadás: a §4 mérésben a konfidencia **változik** (66 %, 72 %, 73 %, 83 %, 86 %, 87 %), tehát jelfüggő. A 87 %-os plafon a fixes-jelentés F3 pontjában dokumentált kalibrációs csomópont. | `V-F3-direction-expiry-timing.png` (t=+0,40 / +1,29 / +2,08 / +2,96 / +3,84 s), `S4-stab_C.png`, `S4-stab_A.png` |
| V-F4 | **PASS** | Metronome → back → **Practice hub**; Chord library → back → **Practice hub**; Tuner → back → **Practice hub**; Live → back → **Practice hub**; Profile → Library → back → **Profile**. Az app egyik esetben sem lépett ki (`dumpsys window` 16–18 találat végig). | a11y `content-desc` az egyes lépések előtt/után + `dumpsys window \| grep -c MainActivity` |
| V-F5 | **PASS** | Friss telepítésen, kijelentkezve a Library **betölt**: fülek All/Practice/Analysis/Song/Setlist, üres állapot „Nothing here yet" + Refresh. A „Couldn't load your library" szöveg **0-szor** fordul elő, kivétel 0. | a11y node-lista; `grep -ci "Couldn't load your library"` → `0` |
| V-F6 | **PASS** | Chords → Setup **„G ↔ D chord changes"**; Warm-up → **„Quarter downstrokes"**; Rhythm → **„Rhythm only — quarters"**; Scales és Technique → **SnackBar „No practice for this goal yet."**, navigáció nélkül (a hubon maradtunk). „Practice unavailable" **0-szor**. | `V-F6-scales-snackbar.png`; a Technique SnackBar-ja szintén elkapva (azonos szöveg) |
| V-F7 | **PARTIAL** | A hibapanel és a Retry-út MŰKÖDIK: a session „StrumSight needs the microphone to hear your guitar. Audio never leaves the device." üzenetet mutat, **„Open settings"** és **„Prepare again"** gombbal — **nem** üres eredmény-képernyő. A „Prepare again" valóban újra-előkészít (visszajön az engedélykérés), nem ragad `preparing`-ben. Engedély megadása után a session ismét indítható. **Amit nem tudtam mérni:** a *futás közbeni* mikrofon-elvétel (lásd §4 lelet). | `V-F7-mic-denied.png`; logcat: `practice_observation_capture_started` a start után |
| V-F8 | **PASS** | A Songs tab AppBar-jában megjelent a **„Song Trainer"** ikon ([816,77]–[948,209]); megnyitja a V2 „Song library"-t (Create song / Source / Sort / „No songs yet. Import a file to start your library." / Import); rendszer-back → vissza a „My songs"-ra, app előtérben. | a11y node-lista mindkét képernyőn |
| V-F10 | **PARTIAL** | A fokozatosság MEGVAN: lejátszás 70 % → **4/5** sáv, 30 % → **3/5** sáv, pengetés-csúcs → **5/5**. A 0 %/100 % ugrás megszűnt. **De:** csendben a méter **3/5-nél megáll** — és ugyanígy 3/5-öt mutat némított kimenettel (digitális csend a Stereomixbe) ÉS valódi mikrofonnal csendes szobában. A „−45 dBFS alatt 0 / csendben lecseng" fél nem reprodukálódott. | `V-F10-level-70-30-silence.png`, `V-F10-floor-muted-vs-quietmic.png` |
| V-F11 | **PASS** | Előnézet `C G Am F`-en, 0,66 s-onkénti ütések. `KEYCODE_BACK` **19:24:47.573**; az utolsó pengetés **19:24:47.255** (a back ELŐTT), és utána **egyetlen új `requestAudioFocus` sem** — pedig az ütemterv szerint ~47,92-kor jött volna a következő. Az E18-R01-ben itt +396 ms-mal még egy ütés szólt. | logcat onset-időbélyegek (lent, §4-mentes) |
| V-CI-A | **PASS** | 320 dp széles ablakban (`wm size 720x1280`, `wm density 360`) a Live „Play a chord…" prompt a hős-helyen elfér, a „Signal too weak…" banner két sorba tördel, a BPM ellipszissel rövidül. **0** `RenderFlex`/`overflowed` a konzolon, nincs sárga-fekete csík. | `V-CI-A-live-320dp.png`; `grep -ciE "RenderFlex\|overflowed"` → `0` |
| V-CI-B | **PASS** | `font_scale 2.0`: a „Scoring profile" két sorba tördel, az azonosító `chordChangeDefa / ult`-ként tördelődik; a sor magassága 55 px → **203 px**. **0** overflow. Normál méretnél a sor egysoros (55 px), az id jobbra. | `V-CI-B-setup-scale2.png`; a11y bounds `[55,1813][1025,1868]` (1.0) vs `[55,1665][1025,1868]` (2.0) |

## 3. Felismerés-stabilitás (§4)

Protokoll: akkordonként **8 pengetés ~2,0 s-onként** (a prompt ~1/s-t kér; a
mérőpont-korlát miatt 2,0 s — lásd §6), minden pengetés után 0,9 s-mal
képernyőkép. Az akkordok között 6 s csend, hogy az előző kártya lejárjon
(ADR 0539 D3). A „hős" = a nagy akkord-kártya címkéje.

| Akkord | téves hős-címke / 8 | nyers elugrás / 8 | megjegyzés |
|---|---|---|---|
| C | **0** (7 kártya mind `C`, 1 pengetésnél még nem erősödött meg) | **nem mérhető** | konfidencia 73–87 % között változik |
| G | **5 / 5 megerősített kártya** (3-nál nem született kártya) | **nem mérhető** | minden kártya `Bm`, soha nem `G` — STABIL, de következetesen téves; konfidencia végig 87 % |
| D | **0 téves — de 0 felismerés is**: a 8 pengetés alatt egyetlen kártya sem jelent meg | **nem mérhető** | néma marad (nem állít hamisat) |
| E | **6 / 7 megerősített kártya** | **nem mérhető** | `Bsus4` ×6, `E` ×1 — a hős **ugrál**: Bsus4 → E → Bsus4; konfidencia 66 % és 87 % |
| A | **0** (7 kártya mind `A`, 1 nem erősödött meg) | **nem mérhető** | konfidencia 72–87 % |
| Am | **BLOCKED** | — | nincs címkézett, valódi gitáros forrás (§6) |
| Em | **BLOCKED** | — | ugyanaz (§6) |

**A „nyers elugrás" oszlop egyik akkordnál sem mérhető** — indoklás a §6-ban.

### Váltások — onset → hős-váltás késés

A protokoll C→G, G→D, D→Em, Em→C váltásokat kér. Ebből:

| Váltás | Mért késés | Beállt hős-címke | Megjegyzés |
|---|---|---|---|
| **C→G** (protokoll) | **2,44–3,20 s** | **`Bm`** (nem `G`) | a hős: `C` → üres (0,43/1,12/1,75 s) → **`C` ÚJRA** 2,44 s-nál → `Bm` 3,20 s-tól |
| **G→D** (protokoll) | **nem értelmezhető** | — | a `D` egyetlen pengetésre sem ad címkét (lásd fent), így nincs mire váltania |
| **D→Em**, **Em→C** (protokoll) | **BLOCKED** | — | nincs `Em` forrás (§6) |
| **C→A** (helyettesítő) | **1,21–2,00 s** | **`A`** (helyes) | a hős: `C` → üres (0,50/1,21 s) → `A` 2,00 s-tól. Ez az EGYETLEN váltás, ahol mindkét oldal helyesen felismert, tehát valódi késés-szám. |

A mintavételi felbontás **~0,75 s** (egy `screencap`+`pull` ciklus), ezért a
késés intervallumként van megadva. **Mindkét mért késés jóval a §4 ≤ 450 ms
célja fölött van.**

Megjegyzés az ADR 0539 D1-hez: a döntés szerint valódi váltásnál a hős „az
előző megerősített akkordot mutatja" a megerősítésig. A mérésben a hős
NEM ezt tette: **üresre váltott** (a prompt jelent meg), majd az új címkére.
Ez a `hasCurrent` kapu (D3) és a D1 „tartsd az utolsó értéket" viselkedés
együtthatása — a jelentés ezt tényként rögzíti, értékelés nélkül.

**Ez loopback-mérés, NEM a valós gitáros végső mérce.** A hangforrás valódi
akusztikus gitár felvétele, de digitális loopbacken, több erősítési fokozaton
és emulátoros újramintavételezésen át jut a mikrofonba. A HORIZON végső
mércéje a felhasználó valós gitáros tesztje.

## 4. Leletek

### V-F7 — a futás közbeni mikrofon-elvétel nem mérhető a szállított eszközökkel

- **Súlyosság:** P3 (kisebb) — a mérési út hiánya, nem termékhiba
- **Regresszió vagy új?** új (mérési korlát); az eredeti F7 lelet a mérhető
  részén JAVULT
- **Reprodukálás:**
  1. Friss telepítés, mikrofon-engedély megadva
  2. Practice hub → „Start recommended practice" → „Start practice" → „Start"
  3. `adb shell pm revoke com.wolfcasaba.strumsight android.permission.RECORD_AUDIO`
  4. 5 s múlva: `adb shell ps -A | grep -c strumsight` → **0**
- **Elvárt:** a session `failed` állapotba megy, hibapanel + Retry
- **Tapasztalt:** az Android 14 a futásidejű engedély visszavonásakor
  **megöli az app folyamatát**, mielőtt az bármit renderelhetne. A prompt
  másik javaslata (Extended controls → Microphone kapcsoló) gazdagép-oldali
  Qt-UI vezérlő, amelynek nincs `adb`/emulátor-konzol megfelelője (ez már az
  E18-R01 sessionben is mérve lett).
- **Bizonyíték:** logcat a revoke előtt/után:

```
09-10 19:36:16.078 29065 29065 I flutter : [debug] audio.session.acquired {owner=live}
09-10 19:36:16.087 29065 29065 I flutter : [info] practice_observation_capture_started
=== REVOKING mic now ===
=== app process alive? 0 ===
```

- **Helyettesítő mérés (elvégezve):** ugyanaz a hibaút úgy, hogy az engedély
  MÁR INDULÁSKOR hiányzik → az app életben marad, és a hibapanel megjelenik:
  „StrumSight needs the microphone to hear your guitar. Audio never leaves the
  device." + „Open settings" + **„Prepare again"**. A „Prepare again"
  ténylegesen újra-előkészít (visszatér az engedélykérés), nem ragad
  `preparing`-ben. Engedély megadása után a képernyő a „Start" készenléti
  állapotba tér vissza.
- **Eltérés a prompt szövegétől:** a gomb felirata **„Prepare again"**, nem
  „Retry"; és megadott engedély után NEM indult el magától a count-in, hanem
  a „Start" készenléti állapot jött vissza (egy további koppintás kell).
- **Gyanított hely:** nem tudom (a mérési korlát platformoldali; a helyettesítő
  mérés a javítást megerősíti)
- **Determinisztikus?** 1 próbából 1 (a folyamat-halál); a helyettesítő mérés
  1 próbából 1

### V-F10 — a szint-jelző nem esik 3/5 sáv alá, semmilyen csendben

- **Súlyosság:** P2 (látható, nem blokkoló)
- **Regresszió vagy új?** az eredeti F10 lelet RÉSZBEN javult — a 0 %/100 %
  ugrás megszűnt, a skála alsó vége viszont nem érhető el
- **Reprodukálás:**
  1. Friss telepítés, mikrofon megadva, Live megnyitva, Stereomix loopback
  2. C-dúr WAV lejátszás 70 %-on → a méter **4/5** sáv
  3. Lejátszás 30 %-ra → a méter **3/5** sáv
  4. Lejátszás leállítva, 5 s csend → a méter **3/5** sáv
  5. `Set-AudioDevice -PlaybackMute $true` (digitális csend a Stereomixbe),
     7 s → a méter **3/5** sáv
  6. Windows felvevő eszköz átállítva a valódi „Microphone Array"-re,
     csendes szoba, 9 s → a méter **3/5** sáv
- **Elvárt:** „−45 dBFS alatt 0 … csendben lecseng"
- **Tapasztalt:** a méter a mért öt állapotból háromban (csend, némított
  kimenet, valódi mikrofon csendben) **pontosan 3 sávot** mutat az 5-ből;
  a megfigyelt teljes tartomány **3/5 … 5/5**, azaz három megkülönböztethető
  fokozat. A banner ilyenkor helyesen „No chord detected yet".
- **Bizonyíték:** `assets/e18-r01-verify/V-F10-level-70-30-silence.png`
  (sorrend: vol70 ×2, vol30 ×2, silence ×2),
  `V-F10-floor-muted-vs-quietmic.png` (sorrend: némított loopback, valódi
  mikrofon csendben ×2 — mindhárom 3/5)
- **Gyanított hely:** nem tudom. A fixes-jelentés F10 sora „padló 0.05"-öt
  említ a CI 2. körében, de a mért 3/5 kitöltés (≈0,6) ennél nagyságrenddel
  nagyobb; azt sem tudom kizárni, hogy az emulátor virtuális mikrofonja
  állandó, ~−22 dBFS körüli zajt ad — a vendégoldali dBFS-t nem tudom
  függetlenül mérni.
- **Determinisztikus?** 3 különböző csend-forrásból 3-szor ugyanaz

### V-STAB — a hős-címke E-nél még mindig elugrik, G-t következetesen Bm-nek látja, D-t nem ismeri fel

- **Súlyosság:** P2 (látható, nem blokkoló) — a felhasználó eredeti panasza
  („elugrik más akkordra és vissza") **E-n reprodukálódott**
- **Regresszió vagy új?** az eredeti panasz RÉSZBEN javult: C-n és A-n a hős
  8/8 stabil és helyes; E-n viszont továbbra is ugrál
- **Reprodukálás:**
  1. Friss telepítés, mikrofon megadva, Live megnyitva, Stereomix loopback,
     WAV források
  2. `E-major.wav` lejátszása 8×, 2,0 s-onként
  3. Minden pengetés után 0,9 s-mal képernyőkép
- **Elvárt (§4):** téves hős-címke / 8 = **0**
- **Tapasztalt:**
  - **E:** `Bsus4` (87 %) → `E` (87 %) → `Bsus4` (87 %) → `Bsus4` (66 %) →
    `Bsus4` (87 %) → `Bsus4` (87 %) → 1 kártya nélküli. **6 téves / 7
    megerősített**, és a címke oda-vissza vált.
  - **G:** 5 megerősített kártya, **mind `Bm`**, konfidencia végig 87 % —
    stabil, de következetesen téves.
  - **D:** 8 pengetésből **0 kártya** — néma.
  - **C:** 7/7 `C`. **A:** 7/7 `A`.
- **Bizonyíték:** `assets/e18-r01-verify/S4-stab_E.png`, `S4-stab_G.png`,
  `S4-stab_D.png`, `S4-stab_C.png`, `S4-stab_A.png`,
  `S4-tr_C_G.png`, `S4-tr_C_A.png`
- **Gyanított hely:** nem tudom megerősíteni méréssel. A fixes-jelentés és az
  ADR 0539 D4 a dekóder onset utáni „lazított" ablakát nevezi meg a
  legvalószínűbb gyökérokként, és a javítást az E18-R05-re halasztja; a mért
  téves címkék (`G`→`Bm`, `E`→`Bsus4`) mindkét esetben **két közös hangot**
  osztanak az igazival, ami inkább a dekóder/kroma oldalára mutat, mint a
  stabilizátoréra.
- **Determinisztikus?** akkordonként 1 futás × 8 pengetés; E-n a váltás a 8-ból
  többször is előjött (Bsus4→E→Bsus4), G és D 8/8-ban azonos viselkedés

### V-GATE — `knowledge_manifest_test.dart` 3 piros cella Windows-on

- **Súlyosság:** P3 (kisebb) — gazdagép-műtermék, a mérce a linuxos CI
- **Regresszió vagy új?** NEM regresszió; az E18-R01 F12 alatt már
  dokumentált Windows-lelet, ugyanez a fájl, ugyanez a minta
- **Reprodukálás:** `tools/round-gate.sh … test/features/ai_tutor/data` a
  Windows worktree-ből
- **Elvárt:** zöld (a CI-n `3521c210`-en 10317/0 piros)
- **Tapasztalt:** `+116 -3`; a kivétel útvonala kevert elválasztójelű
  (`assets/tutor_knowledge\manifest.json`)
- **Bizonyíték:** a §1 teljes hibablokkja
- **Gyanított hely:** `tool/build_tutor_knowledge_manifest.dart:52` (a
  stackből); az útvonal-összefűzés platformfüggő
- **Determinisztikus?** 1 futásból 1, mindhárom cella

## 5. Megfigyelések (nem bukás)

- **A `uiautomator` nem tudja kidumpolni a Live képernyőt:**
  `ERROR: could not get idle state` (a `--compressed` változat is). A képernyő
  a folyamatos szint-animáció miatt sosem lesz „idle". Ez a prompt §4 által
  előírt mérőpontot (`"<X> chord diagram"` node) elérhetetlenné teszi — a
  méréseket képernyőképekből végeztem. Az E18-R01 sessionben ugyanez a dump
  MŰKÖDÖTT, amikor a méter be volt ragadva (nem animált).
- **A WAV-források csúcsszintje erősen szórt** a Commons-felvételeken:
  D 0,137 · E 0,157 · G 0,164 · C 0,209 · A 0,268 · F 0,393 · B 0,427.
  Épp a három leghalkabb (D, E, G) az, amit az E18-R01 loopback-mérés nem
  ismert fel. Ezért **azonos csúcsra normalizáltam** (0,89; RMS −16,6 …
  −21,0 dBFS) — hogy a forrás-hangerő ne legyen rejtett változó. A mostani
  mérésben D és G így is hibás/néma maradt, tehát a szint önmagában nem
  magyarázza az E18-R01 F9-et.
- **A konfidencia nem konstans**: 66 / 72 / 73 / 83 / 86 / 87 % értékeket
  mértem. A 87 % gyakori, de nem kizárólagos — összhangban a fixes-jelentés
  F3 magyarázatával (kalibrációs plafon).
- A logcat-ben a futás egésze alatt **0** `RenderFlex`/`overflowed`, **0**
  kezeletlen kivétel, **0** `capture_failed`. Az egyetlen ismétlődő warning az
  Android médiaszkennerétől jön a saját képernyőkép-fájljaimra
  (`ModernMediaScanner: Trouble scanning /storage/emulated/0/s.png`) — a
  mérőeszköz műterméke, nem az appé.
- A Live „Pause" gombjára adott koppintásom nem váltott ki állapotváltozást
  (a méter és a banner változatlan maradt); nem üldöztem tovább, mert nem
  szerepel a 13 cellában.

## 6. Nem mért cellák és okuk

| Tétel | Ok |
|---|---|
| §4 „nyers elugrás / 8" oszlop, mind a 7 akkordnál | A szállított app a nyers `frame.current`-et **nem teszi ki** semmilyen felületre: `grep` a `lib/features/live/` alatt nem talál keretenkénti akkord-naplózást, és az `app_route.dart`-ban nincs lab/diagnosztika útvonal, ahol a nyers címke látszana (a prompt „Settings → Diagnostics"-ot említ — ilyen képernyőt nem találtam). A hős-oldali stabilizált címke mérhető, a nyers nem. **Ez blokkolja a prompt §4/4. pontját**, vagyis azt a megkülönböztetést, hogy „a nyers elugrik, de a hős nem". |
| §4 `Am` és `Em` akkordok | Nincs címkézett, valódi gitáros, szabadon letölthető moll-felvétel. A Commons-on a címkézett készlet csak a hét dúrból áll (`A-major.ogg` … `G-major.ogg`); a keresés `intitle:minor`, „minor chord acoustic guitar” és a közvetlen `A-minor.ogg`/`E-minor.ogg`/`D-minor.ogg` próbákra sem adott találatot. Generált (szintetizált) hangot szándékosan nem használtam — a felhasználó kifejezett kérése valódi felvétel. |
| §4 `D→Em` és `Em→C` váltás | Ugyanaz az ok (nincs `Em` forrás). |
| §4 `G→D` váltás | A `D` egyetlen pengetésre sem ad hős-címkét, így nincs megfigyelhető váltás. |
| V-F7 futás közbeni mikrofon-elvétel | Lásd a §4 leletet: a `pm revoke` megöli a folyamatot; az emulátor Extended controls Microphone kapcsolójának nincs `adb`-megfelelője. |
| V-F1 „AI tutor kérdés" fele | Az `aiTutorEnabled` flag a `FeatureFlags.forEnvironment`-ben **`false` minden környezetben** (`lib/app/config/feature_flags.dart`), ezért tutor-beszélgetés a buildben nem indítható. A cella másik két fele (APK-tartalom, betöltési hiba hiánya) mérve és zöld. |
| §4 késés ≤ 450 ms alatti feloldása | A mintavételi ciklus (`screencap` + `pull`) ~0,75 s, ezért a késés csak intervallumként adható meg. Finomabb mérés képernyőfelvételt (`screenrecord`) és videó-dekódolást igényelne; a gazdagépen nincs videó-dekóder (nincs `ffmpeg`), és a prompt tiltja videó commitolását. |

## 7. Összegzés a remote sessionnek

- **PASS: 11/13**, FAIL: **0**, PARTIAL: **2** (V-F7, V-F10), BLOCKED: **0**
  (a 13 cellából egyik sem maradt teljesen mérés nélkül; a részleges okok a §6-ban)
- **P1 leletek: nincs.** **P2: V-F10, V-STAB.** P3: V-F7 (mérési korlát), V-GATE.
- **A felismerés-stabilitás egy mondatban:** a hős C-n és A-n 8/8 stabil és
  helyes, D-n néma, G-n stabilan `Bm`, **E-n viszont továbbra is oda-vissza
  ugrál** (`Bsus4` ↔ `E`) — a felhasználó eredeti panasza E-n reprodukálódott.
- **E18-R05 hold:** a §3 tábla alapján a válasz **„a hős is ugrik"** —
  legalább E-nél. A „nyers elugrik, a hős nem" megkülönböztetés ezen a
  buildön **nem eldönthető**, mert a nyers címke nincs kitéve semmilyen
  felületre (§6). A hold feloldásához vagy a nyers címke megfigyelhetővé
  tétele kell, vagy a valós gitáros A/B (E18-R05 §7 „0. lépés").
- **A §6 házimunka:** lásd lent.

### A §6 házimunka eredménye — MINDKETTŐ SIKERÜLT

**1. A négy eldobható szelet-ág törölve** (mind a négy létezett az `origin`-on):

```
To https://github.com/wolfcasaba/strumsight.git
 - [deleted]           claude/e18-diag-a
 - [deleted]           claude/e18-diag-b
 - [deleted]           claude/e18-diag-c
 - [deleted]           claude/e18-fixes-diag
```

**2. A git-note felvéve a `22a06e25`-re és felpusholva:**

```
$ git notes show 22a06e25
round=E18-R01-fixes verdict=pass tests=10317 lesson=ci-log-tail-5000-slice-branches-and-golden-pixel-identity

$ git push origin 'refs/notes/*'
   b401bb23..b33c3c36  refs/notes/commits -> refs/notes/commits
```

(A `22a06e25` = „docs(E18-R01): CI-green evidence on 3521c210 — build-apk
fully green (10317 tests), full-gate job green".)
