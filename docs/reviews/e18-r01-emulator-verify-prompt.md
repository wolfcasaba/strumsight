# E18-R01 javító kör — ELLENŐRZŐ PROMPT a laptopos AI-sessionnek (emulátor)

> Ezt a szöveget kell bemásolni a laptopon futó Claude Code / Codex sessionbe.
> A remote session (a javító kör szerzője) a §5 szerinti jelentést fogja
> feldolgozni — a szerkezetet NE változtasd meg.

---

Te a StrumSight repó `claude/optimistic-bohr-vpaxh4` ágát ellenőrzöd a
laptopon, Android-emulátoron. Az ág az E18-R01 emulátoros jelentés
(`docs/reviews/e18-r01-emulator-report.md`, „FEJLESZTENDŐ" szakasz, F1–F13)
javító köre. A javítások listája és a szerzői indoklás:
`docs/reviews/e18-r01-emulator-fixes.md`; a felismerés-stabilitás döntései:
`docs/adr/0539-live-recognition-stability-stabilized-hero-and-onset-guard.md`.
Olvasd el mindkettőt, MIELŐTT mérsz. A HANDOFF.md tetején van a kör
állapota.

**Szereped: ELLENŐRZŐ, nem javító (ADR 0055).** A `lib/**` és a `test/**`
alatt SEMMIT nem módosítasz, goldent nem regenerálsz, konstanst nem
hangolsz. Ha hibát találsz, DOKUMENTÁLOD a §5 szerint; a javítás a következő
kör dolga. Kivétel: a §6 két házimunka-parancsa (ág-törlés, git-note), amit a
remote session a proxy miatt nem tudott megtenni.

## 1. Előkészítés

```bash
git fetch origin && git checkout claude/optimistic-bohr-vpaxh4 && git pull
git log --oneline -3          # a HEAD 2d258e08 vagy újabb legyen
flutter pub get
```

Emulátor: ugyanaz a profil, mint az E18-R01 jelentésben (Pixel-osztályú AVD,
`-allow-host-audio`). **Friss telepítés** (`adb uninstall com.strumsight.app`),
mert az F5 és az F1 első indításnál látszik.

Hang be az emulátorba: az E18-R01 jelentés §7b loopback-lánca (Stereomix +
`-allow-host-audio`), DE **WAV-val, nem 64 kbps MP3-mal** — a jelentés saját
tanulsága szerint az MP3 önmagában rontotta a találati arányt. Ha csak MP3
érhető el, azt a §5 profil-táblában KÖTELEZŐ kimondani.

## 2. Automata kapu ELŐSZÖR (nem a teljes suite — az a CI-ban már zöld)

A CI-bizonyíték a `3521c210` SHA-n zöld (build-apk 34431041159: 10317 teszt,
0 piros; full-gate 34431039782). Itt CSAK a kör által érintett útvonalakat
futtasd, a boxon mért szabályok szerint: **külön processzben, csővezeték
nélkül** (`| tail` TILOS, `analyze && test` lánc TILOS — OOM):

```bash
tools/round-gate.sh test/features/live test/features/practice_hub test/features/practice test/accessibility test/app/bootstrap test/features/songs test/features/ai_tutor/data test/property
```

Ha a gate piros: a §5-ben a cella TELJES kimenetét idézd (nem a végét), és
folytasd a kézi méréssel — a piros nem állít meg, csak lelet.

Golden-eltérés esetén (`test/ui/goldens/**`): a jelentésbe a diff-százalék és
a `failures/` mappa képei kerülnek; NEM regenerálsz.

## 3. Kézi ellenőrzés az emulátoron — a 11 javított lelet, egyenként

Minden sorhoz: végezd el a lépést, írd le, mit LÁTTÁL (nem azt, amit vártál),
és adj PASS / FAIL / PARTIAL / BLOCKED ítéletet. Képernyőkép minden FAIL-hez,
és minden Live-mérési cellához. A képernyőképek helye:
`docs/reviews/assets/e18-r01-verify/<id>.png` (`adb exec-out screencap -p >`).

| ID | Lépés | Elvárt (a javítás szerint) |
|---|---|---|
| V-F1 | Friss indítás → AI tutor (Learn/Tutor) → bármely kérdés, ami a tudásanyagra támaszkodik; ÉS `unzip -l build/app/outputs/flutter-apk/app-debug.apk \| grep tutor_knowledge` | a tudásanyag (`assets/tutor_knowledge/en/`, `hu/`) BENNE van az APK-ban, a tutor nem „nincs tudásanyag" választ ad |
| V-F2 | Live → loopback: egy akkord 6 pengetés, majd 3 s CSEND | a hős-kártya a csend alatt HÁTRÁL a történetbe, a helyén a „Pengess egy akkordot…" prompt jelenik meg; nem ragad be |
| V-F3 | ugyanaz, közben a konfidencia és az irány figyelése | a konfidencia-szám és a nyíl ELTŰNIK a csend alatt (nem áll 87 %-on); pengetés után az irány ~2 s-on belül lejár, ha nincs új onset |
| V-F4 | Practice hub → Metronome / Chord library / Tuner / Live gomb → **rendszer-back**; majd Profile → Library → rendszer-back; majd egy eszközről a Practice tab ÚJRA-koppintása | mind a 4 eszközről + a Library-ről a hubra tér vissza (az app NEM lép ki); a tab újra-koppintása a hub gyökerére visz |
| V-F5 | Profile → Library (friss telepítésen, kijelentkezve) | a Library betölt (üres állapot vagy dalok), NINCS „Couldn't load your library" |
| V-F6 | Practice hub → „Browse by goal" → Chords / Warm-up / Rhythm / Scales / Technique | Chords → Setup a `builtin.gToDChanges.v1`-gyel; Warm-up → `quarterDownstrokes`; Rhythm → `rhythmOnlyQuarters`; Scales és Technique → SnackBar „No practice for this goal yet." és NINCS navigáció; SOHA „Practice unavailable" |
| V-F7 | Practice session indítása, majd a mikrofon elvétele közben (emulátor: Extended controls → Microphone kapcsoló ki, vagy `adb shell pm revoke com.strumsight.app android.permission.RECORD_AUDIO` futás közben) | a session `failed` állapotba megy, HIBAPANEL látszik konkrét üzenettel + Retry gomb; NEM ugrik üres eredmény-képernyőre; Retry a mikrofon visszaadása után újraindítja a count-int |
| V-F8 | Songs tab AppBar | van egy `songs-entry-song-trainer` ikon (Song Trainer), ami a `/song-trainer` könyvtárra visz; onnan rendszer-back a Songs tabra |
| V-F10 | Live, loopback szint 70 % → majd 30 % → majd csend | a bemeneti szint-jelző FOKOZATOS (nem 0 % / 100 % ugrás): −45 dBFS alatt 0, −6 dBFS fölött tele; csendben lecseng |
| V-F11 | Songs → New song → néhány chip → Play (előnézet) → közben rendszer-back | az előnézet a pop PILLANATÁBAN elhallgat, nincs „még egy ütés" a következő képernyőn |
| V-CI-A | Live, KESKENY ablak: az emulátort forgasd fekvőbe, vagy 320 dp széles AVD-n | a „Pengess egy akkordot…" prompt a hős-helyen tördelődik/zsugorodik, NINCS sárga-fekete overflow-csík |
| V-CI-B | Practice → Setup képernyő; Beállítások → betűméret a legnagyobbra (textScale ≈ 2.0) | a „Scoring profile" sor azonosítója tördelődik, NINCS overflow-csík; normál betűméretnél a sor ugyanúgy néz ki, mint eddig (az id jobbra, a címke balra) |

**Amit NEM várunk javítva** (ne jelentsd hibaként, csak mérd, ha érinted):
F9 találati arány (szándékosan nem hangolt, lásd §4), F12 Windows-suite
(dokumentálva), F13 bannerek mennyisége (termékdöntés).

## 4. A felismerés stabilitása (ADR 0539) — mérés, nem benyomás

A felhasználó panasza: „leütött C-nél egyszer jól mutatja, a következő C-nél
elugrik más akkordra és vissza — minden akkordnál". A javítás a DÖNTÉSI
rétegen történt (stabilizált hős-címke, 0,2 s onset-őr, kártya-lejárat); a
dekóder konstansai NEM változtak.

Protokoll (a kutatási jegyzet §4 nyomán, WAV loopbackkel):

1. Akkordok: **C, G, D, E, A, Am, Em**. Mindegyiket **8× ismételve** pengesd
   ugyanazon az akkordon (~1 pengetés/s), majd **4 valódi váltás**
   (C→G, G→D, D→Em, Em→C).
2. Mérőpont: a `uiautomator` akadálymentességi fa `"<X> chord diagram"`
   node-ja (mint a §7b-ben) = a HŐS által mutatott címke; ÉS a diagnosztika-
   panel nyers `frame.current` értéke, ha elérhető (Settings → Diagnostics).
3. Számold akkordonként: **téves hős-címke / 8 pengetés** (cél: 0), és a
   valódi váltásnál az **onset → hős-váltás késés** (cél: ≤ 450 ms; mérd a
   logcat időbélyegéből vagy képernyőfelvételből).
4. Külön jegyezd, ha a NYERS címke elugrik, de a hős NEM — ez a javítás
   várt viselkedése, és egyben az **E18-R05 alapmérése**
   (`docs/rounds/e18-r05-decoder-attack-window-real-guitar-ab.md` §7 „0.
   lépés"). Írd bele a §5 táblába akkordonként.

Ez loopback-mérés, NEM a valós gitáros végső mérce — a jelentésben ezt
mondd ki. A valós gitáros mérés a felhasználóé.

## 5. Jelentés — KÖTELEZŐ szerkezet

Fájl: `docs/reviews/e18-r01-emulator-verify-report.md`. Csak ez a fájl és a
`docs/reviews/assets/e18-r01-verify/` képek kerülnek a commitba. Szakaszok
ebben a sorrendben, ezekkel a címekkel:

```markdown
# E18-R01 javító kör — emulátoros ELLENŐRZŐ jelentés (<dátum>)

## 0. Profil
| Elem | Érték |
| ág / HEAD | claude/optimistic-bohr-vpaxh4 @ <sha> |
| emulátor | <AVD, API, felbontás/dp, -allow-host-audio igen/nem> |
| hangforrás | <WAV/MP3, bitráta, forrás> |
| Flutter / Dart | <flutter --version első két sora> |
| build | debug/release, flutter run vagy adb install |

## 1. Automata kapu
<a tools/round-gate.sh PARANCS és a TELJES záró kimenete; piros cellánként a teljes hibablokk>

## 2. Ítélet-tábla
| ID | Ítélet | Amit láttam (1–2 mondat) | Bizonyíték |
| V-F1 | PASS/FAIL/PARTIAL/BLOCKED | ... | assets/…png, logcat-sor, uiautomator node |
... (V-F1 … V-F11, V-CI-A, V-CI-B — MIND a 13 sor, üres nem maradhat)

## 3. Felismerés-stabilitás (§4)
| Akkord | téves hős-címke / 8 | nyers elugrás / 8 | megjegyzés |
| C | 0 | 2 | a nyers G-re ugrott a 3. és 6. pengetésnél, a hős maradt |
... (7 sor) + a 4 váltás késése ms-ban

## 4. Leletek — MINDEN FAIL/PARTIAL-hoz egy blokk
### V-n — <egy mondatos cím>
- **Súlyosság:** P1 (a felhasználót közvetlenül éri, blokkoló) / P2 (látható, nem blokkoló) / P3 (kisebb) / P4 (termékkérdés)
- **Regresszió vagy új?** regresszió az E18-R01 javításhoz képest / az eredeti F-lelet NEM javult / új, korábban nem látott
- **Reprodukálás:** számozott lépések, friss telepítéstől, az utolsó lépés a hiba
- **Elvárt:** <a §3 táblából>
- **Tapasztalt:** <pontosan, számokkal>
- **Bizonyíték:** képernyőkép útvonala; a logcat releváns 5–20 sora SZÓ SZERINT (`adb logcat -d | grep -iE "flutter|exception|error|StrumSight"`); ha kivétel: a teljes stack első 15 sora
- **Gyanított hely:** fájl(ok) a lib/ alatt, ha a stackből vagy a fixes-jelentésből látszik — ha nem, „nem tudom", NEM találgatás
- **Determinisztikus?** hányszor próbáltad, hányszor jött elő

## 5. Megfigyelések (nem bukás)
<amit láttál, de nem a kör hatóköre: jank, szöveg, hiányzó fordítás — röviden>

## 6. Nem mért cellák és okuk
<BLOCKED sorok indoka: környezeti akadály, mivel próbáltad>

## 7. Összegzés a remote sessionnek
- PASS: n/13, FAIL: n, PARTIAL: n, BLOCKED: n
- P1 leletek: <ID-k>, P2: <ID-k>
- A felismerés-stabilitás: <egy mondat: a hős elugrik-e még; a nyers igen/nem>
- E18-R05 hold: <feloldható-e a §3 tábla alapján: „a nyers még elugrik, a hős nem" / „semmi sem ugrik" / „a hős is ugrik">
```

Szabályok a jelentéshez:

- Minden állításhoz bizonyíték (kép, logsor, node). „Működik" bizonyíték
  nélkül = nem mért, tehát BLOCKED.
- A NEGATÍV eredményt is pontosan írd le — „elugrott, de csak egyszer" is
  adat.
- Ne javíts, ne javasolj kódot a jelentésben; a „Gyanított hely" elég.
- A képernyőképek PNG-k, max 1 MB egyenként; ne commitolj videót vagy
  hangfájlt.

Commit és push (CSAK a jelentés és a képek):

```bash
git add docs/reviews/e18-r01-emulator-verify-report.md docs/reviews/assets/e18-r01-verify/
git commit -m "review(E18-R01): emulator verification report — <PASS n/13, FAIL n>"
git push origin claude/optimistic-bohr-vpaxh4
```

## 6. Házimunka ugyanebben a sessionben (a remote proxy nem engedte)

```bash
git push origin --delete claude/e18-fixes-diag claude/e18-diag-a claude/e18-diag-b claude/e18-diag-c
git notes add -m "round=E18-R01-fixes verdict=pass tests=10317 lesson=ci-log-tail-5000-slice-branches-and-golden-pixel-identity" 22a06e25 && git push origin 'refs/notes/*'
```

A négy `claude/e18-*diag*` ág eldobható diagnosztikai szelet — SOHA nem
mergelendő. Írd a jelentés §7-be, hogy a törlés és a note-push sikerült-e.

## 7. Időkeret és STOP

Kb. 2–3 óra. Ha a loopback nem áll össze 30 perc alatt: a §3 V-F2/F3/F10 és
a §4 BLOCKED, a többit mérd meg, és a §6-ban írd le, mit próbáltál. Ha
bármi ellentmond ennek a promptnak a kód valóságával (pl. egy képernyő
máshol van), a jelentésbe írd, a promptot ne „javítsd" csendben.
