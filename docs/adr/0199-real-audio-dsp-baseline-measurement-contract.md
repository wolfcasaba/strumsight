# ADR 0199 — A valós-audio DSP baseline mérési szerződése

- **Státusz:** Elfogadva (GOV-06 pre-flight, 2026-08-09)
- **Kör:** GOV-06 / `E99-R04` — Valós-audio DSP baseline mérés
  (governance-kör, nem SDD-fejezet)
- **Implementer motor:** Terra (Codex CLI, `tools/codex-round.sh`) — az ADR-t
  az orchesztrátor (Claude Opus 5) írta a pre-flightban.
- **User-döntés, amit végrehajt:** 2026-08-07 `HANDOFF.md` §6 „Kötelező
  sorrend" 4. pont — valós audio mérés az Epic 6 ELŐTT.

## Kontextus

**Mért a pre-flightban 2026-08-09-én, `main @ 66e545db`:**

1. **A termék központi állítására egyetlen valós-audio szám létezik**
   (`HANDOFF.md` §3): CRNN pengetés-irány 86,7% vs heurisztika 38,9%
   (r164 A/B). **Akkord-pontosságra valós felvételen nincs szám**, onsetre és
   BPM-re sincs.

2. **A korpusz megvan és címkézett.** `ml/data/klangio/`: **82 `.wav`**
   telefonos gitárfelvétel + **82 `.strums`** címkefájl, 423 MB. A címke
   soronként `idő(mp) \t irány(D/U) \t akkord`, összesen **11 767 esemény**.
   Ez egyszerre onset-, irány- és akkord-ground-truth.

3. **A korpusz NINCS verziókövetve:** `git ls-files ml/data/klangio/` → **0
   fájl**. Csak ezen a boxon létezik.

4. **A címke-eloszlás erősen dúr-torzított** (mérve, mind a 82 fájlon):

   | Címke | Esemény | Címke | Esemény |
   |---|---|---|---|
   | G-major | 2216 | B-major | 860 |
   | C-major | 1982 | F#-major | 408 |
   | D-major | 1804 | Bb-major | 284 |
   | A-major | 1546 | C#-major | 138 |
   | E-major | 1283 | **B-minor** | **124** |
   | F-major | 1024 | **A-minor** | **98** |

   **Mindössze 222 moll esemény a 11 767-ből (1,9%).** Irány: 7228 `D` /
   4539 `U`.

5. **A szállított DSP Dart, és offline futtatható.**
   `lib/features/analyze/engine/clip_analyzer.dart:65` —
   `AnalyzeResult analyze(List<double> pcm, int sampleRate)`, szinkron, pure,
   determinisztikus; a doc-comment szerint „Runs the REAL Live DSP over a
   recorded PCM clip". A visszaadott `AnalyzeResult` tartalmaz `bpm`-et,
   `TimelineChord` szegmenseket (`label`, `startSec`, `endSec`) és
   `TimelineStrum` eseményeket (`direction`, `timeSec`, `confidence`).
   Van wav-dekóder (`lib/features/analyze/engine/wav_decoder.dart`), és van
   precedens önálló Dart mérőeszközre
   (`tool/benchmarks/song_trainer_pitch_benchmark.dart`).

6. **A meglévő kiértékelők a MODELLT mérik, Pythonban**
   (`ml/chords/eval_real_sessions.py` — librosa közelítő referencia,
   `ml/chords/eval_guitarset.py` — GuitarSet valódi címkékkel). Egyik sem a
   szállított Dart DSP-t futtatja.

7. **A korpuszban nincs BPM-metaadat** (`strums_list.txt` puszta fájllista).

## Döntés

### Döntés 1 — A mérés a SZÁLLÍTOTT Dart DSP-t futtatja

A harness `tool/benchmarks/` alatt él, és a valódi `ClipAnalyzer`-t hívja a
dekódolt PCM-en. **Python-oldali újraimplementáció NEM elfogadható mérés:** az
azt mérné, amit a Python csinál, nem azt, amit a felhasználó telefonján futó
kód. A meglévő `ml/chords/eval_*.py` szkriptek érintetlenül maradnak — más
kérdést válaszolnak (modell vs modell), és a kör nem írja felül őket.

### Döntés 2 — Akkord-pontosság a ground-truth pengetés-időpontokban mintavételezve

A `.strums` eseményenként ad akkordot, a `ClipAnalyzer` szegmenseket. Az
összevetés: **minden ground-truth eseményre** megkeressük, melyik jósolt
szegmens fedi az adott időpontot, és annak a címkéjét hasonlítjuk. Ez
esemény-súlyozott (nem idő-súlyozott) pontosság, és megegyezik azzal, ahogy az
app is pontoz — a felhasználó pengetéskor kap visszajelzést.

Ha egy eseményt semelyik szegmens nem fed, az **hibás találat**, nem kihagyott
minta. A „nincs predikció → ne számítson" könyvelés a mérce lazítása.

### Döntés 3 — A címke-normalizálás kipinnelt, és nem lazítható

A ground-truth `C-major` / `B-minor` alakot majmin gyökérre + minőségre
normalizáljuk, és a jósolt címkét ugyanarra. Enharmonikus azonosság
(`Bb` ≡ `A#`, `C#` ≡ `Db`) **elfogadott**; minden más lazítás — a minőség
elhagyása („C-major ≈ Cm"), a bővített/sus/7 akkordok gyökérre csonkolása a
ground-truth oldalán, a „közeli" akkordok részleges pontozása — **tilos**.

Ha a jósolt címke olyan minőséget hordoz, ami a ground-truth szótárában nem
szerepel (pl. `Csus4`, `C7`), az **hibás találat**. A ground-truth 12 címkéje
a teljes megengedett céltér.

### Döntés 4 — Az aggregált szám önmagában NEM elfogadható kimenet

A korpusz 98%-ban dúr (Kontextus 4). Ezért a riportnak **kötelezően**
tartalmaznia kell:

1. **osztályonkénti bontást** (mind a 12 címkére: támogatás, precision,
   recall);
2. a **többségi-osztály baseline**-t (a leggyakoribb címke konstans jóslása —
   a mérés szerint G-major, 2216/11767 ≈ **18,8%**);
3. a **moll-részhalmaz** külön számát (222 esemény).

Egy aggregált akkord-pontosság a baseline és a bontás nélkül félrevezető
állítás, nem mérés. **A riport nem fogadható el nélkülük.**

### Döntés 5 — Az onset-metrika tűréshatára paraméter, és mátrixszal mérendő

Onset precision / recall / F1 a ground-truth és a jósolt `TimelineStrum`
időpontok kétoldali, mohó párosításával, egy **tűréshatár** paraméterrel.
Egy ground-truth esemény legfeljebb egy jósolt eseménnyel párosítható és
fordítva (nincs újrafelhasználás — az inflálná a recall-t).

A tűréshatárt a riport **több értéken** közli (a szokásos MIR-gyakorlat
50 ms-ja mellett legalább egy szigorúbb és egy megengedőbb ponton), hogy a
szám ne egyetlen, kényelmesen megválasztott ponton álljon.

### Döntés 6 — A BPM-hiba SZÁRMAZTATOTT, és annak is kell látszania

A korpuszban nincs BPM-metaadat (Kontextus 7). A ground-truth BPM a
ground-truth onsetek közötti időkülönbségekből származtatható, ami **feltételezi,
hogy a pengetések egyenletes rácson ülnek** — ez nem minden felvételre igaz.

Ezért: a BPM-hiba **származtatott, közelítő metrikaként** jelenik meg, a
feltételezés kimondásával, és a riport közli a rács-szabályosság mérőszámát
(pl. az inter-onset intervallumok szórása a mediánhoz képest) felvételenként.
Azok a felvételek, ahol a rács nem szabályos, **kizárhatók a BPM-aggregátumból
— de a kizárás tényét és darabszámát a riportnak ki kell írnia.** A néma
szűrés a mérce lazítása.

### Döntés 7 — Ez MÉRÉSI kör: a DSP nem változik

A kör **nem hangol** paramétert, nem cserél modellt, nem módosítja a
`ClipAnalyzer` viselkedését. Ha a harness futtatásához a szállított kódot
kellene változtatni, az **önmagában lelet** (a DSP nem futtatható offline),
és jelentendő, nem megkerülendő.

A hangolás a mérés UTÁN, külön körben történik, és a `docs/rag/chunks/`
frissítésével jár (CLAUDE.md „DSP tuning").

### Döntés 8 — Az eredmény elkötelezett riport, NEM CI-kapu

A korpusz nincs a gitben (Kontextus 3), tehát a CI nem tudja futtatni a
mérést. A kör kimenete ezért a `docs/eval/` alá elkötelezett riport, amely
tartalmazza a futtatott parancsot, a korpusz **checksumját** és
darabszámát, hogy a szám azonosítható és későbbi futással összevethető legyen.

**Nincs küszöb és nincs kapu ebben a körben.** A baseline megállapítása a cél;
egy küszöb bevezetése azelőtt, hogy tudnánk, hol áll a rendszer, önbecsapás.

A korpusz verziókövetése (Git LFS / külön adat-repó / külső hivatkozás +
checksum) **nevesített follow-up**, nem e kör hatóköre — de a riportnak ki
kell mondania, hogy emiatt a mérés ma nem reprodukálható a boxon kívül.

## Következmények

**Pozitív**

- Az Epic 6 harminc köre végre mért alapra épülhet, nem feltételezésre.
- Ha az alap gyenge, az most derül ki — nem harminc kör után.
- A riport osztályonkénti bontása megmutatja, MELYIK akkordokon gyenge a DSP,
  ami a későbbi hangoló kör bemenete.

**Negatív / kockázat**

- **A mérés ma nem reprodukálható a boxon kívül** (Döntés 8). Ez ismert és
  kimondott korlát, nem elhallgatott.
- A korpusz egyetlen forrásból (telefonos felvételek) származik, és
  98%-ban dúr. A számok erre a disztribúcióra érvényesek — nem
  általánosíthatók minden gitárhangzásra. A riportnak ezt is ki kell mondania.
- A BPM-metrika származtatott (Döntés 6), tehát gyengébb bizonyíték, mint az
  akkord- és onset-számok.
