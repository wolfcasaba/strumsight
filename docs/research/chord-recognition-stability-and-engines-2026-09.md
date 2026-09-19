# Akkordfelismerés: stabilitás és a „jobb motor” kérdése — kutatási jegyzet (2026-09-09)

> A felhasználó kérése: *„ne ugráljon egy leütött akkordnál más hangokra…
> kutass, hogy kell jól megcsinálni, tölts le munkákat, motorokat, ha jobbak
> mint a miénk, nézz utána a technológiának."* Ez a jegyzet a remote
> konténerből elérhető forrásokra épül (arxiv.org és több egyetemi tárhely a
> proxy által **blokkolt**; a GitHub-összefoglalók és a webkeresés mentek).
> A döntéseket az [ADR 0539](../adr/0539-live-recognition-stability-stabilized-hero-and-onset-guard.md)
> rögzíti.

## 1. Mi a miénk ma (mért, a kódból)

| Réteg | Mit csinál | Paraméter |
|---|---|---|
| Kroma | NNLS-transzkripció (Chordino-elv), bass+treble 24-dim, 16384-es ablak (~370 ms), 4096 hop (93 ms) | `DspConfig.nnlsWindow/Hop` |
| Döntés | Online Viterbi a szótár felett, **önátmenet-bónusz 0.22** (a kihívónak ennyivel kell jobbnak lennie ÉS kitartania) | `selfBonus` |
| Onset-igazítás | onset után **2 keretre a bónusz ×0.25** — „váltson a pengetésen, legyen stabil között” | `_onsetBoostFrames=2`, `_onsetBonusScale=0.25` |
| Jelenlét-kapu | EMA-simított match-konfidencia Schmitt-trigger: 0.54 fel / 0.22 le, 4 keret tartás | `chordConfRise/Release/ReleaseHoldFrames` |
| UI-stabilizátor | `RecognitionStabilizer`: egy ÚJ címke 3 (free) / 5 (guided) egybehangzó ~15 Hz keret után mozdítja el a megerősítettet | ADR 0518 |
| Hős | **nyers** `frame.current` (a stabilizátor csak az időszalagot védte) | — |

Ez architektúrailag a klasszikus kroma + HMM/Viterbi-simítás recept — ugyanaz,
amit a valós idejű HMM-alapú akkordbecslés irodalma ajánl (Cho–Bello, ICMC 2009;
Stark–Plumbley, ICMC 2009). A baj nem a recept, hanem **két ablak ütközése**
(§2).

## 2. A tünet mechanizmusa („C → más → C”, minden akkordnál)

1. Pengetés → onset → a dekóder 186 ms-ra lazít (×0.25 bónusz).
2. Ugyanebben a 186 ms-ban a kroma a legrosszabb: attack-tranziens (szélessávú),
   plusz az előző akkord lecsengése a 370 ms-os ablakban → egy másik profil
   nyerhet 1–2 keretre → a dekóder **átvált** (ez a chunk 016 r142 „latch”
   kockázata, addig szintetikus reprodukció nélkül).
3. A stabilizátor 3 keretet kér; a 186 ms 2–3 emittált keret → **megerősíti**
   a téves címkét → a kártya átvált → a sustain visszahozza a C-t → újabb 3
   keret → vissza. A hős ezt a nyers keretből azonnal mutatta.

A szakirodalom ugyanerre a két gyógymódra mutat: **(a)** a döntést ne az
attack-on, hanem a sustain-en hozd (onset-szinkron, de késleltetett ablak;
az onset-tranziens külön kezelése), **(b)** a címke-simítás legyen elég hosszú
ahhoz, hogy egy onset-hosszú blip ne legyen „evidencia” (HMM önátmenet /
mód-szűrő / tartási idő — a frame-szintű „fluttering” ellen).

## 3. Mit tettünk most (UI-/döntési réteg, DSP-konstans nélkül)

- **Stabilizált hős** (ADR 0539 D1): a nagy akkord-felirat a megerősített
  címkét mutatja; a jelenlétet továbbra is a nyers kapu dönti.
- **Onset-tranziens őr** (D2): az onset utáni 0.2 s keretei nem számítanak az
  elmozdításba. Egy valódi váltás ~0.4 s alatt erősödik meg (volt ~0.2 s).
- **Kártya-lejárat** (D3, E18-R01 F2/F3): nincs kint konfidencia, amit a keret
  már nem hord.

Mind gépi cellával + randomizált property-vel. **Valós gitárral még nem mért.**

## 4. Javaslat a dekóder oldalára (E18-R05, a felhasználó boxán)

**Hipotézis:** a boost-ablakot egy akkord-kerettel el kell tolni — az onset
utáni **1. keret** (0–93 ms, attack + lecsengés) teljes bónusszal, a **2.–3.**
(93–279 ms, korai sustain) csökkentettel. „A sustain-en váltson, ne az
attack-on.” Alternatíva: a boost alatt a kihívónak **két egymást követő**
keretben kell nyernie.

**Mérési protokoll (kötelező, AGENTS.md §9):**
1. Fixture: az E18-R01 emulátor-jelentés loopback-módszere, de **WAV-val**
   (nem 64 kbps MP3) — C, G, D, E, A, Am, Em akkordok, mindegyik 8× ismételve
   ugyanazon az akkordon (a tünet az ISMÉTELT pengetés), és 4 valódi váltás.
2. Mérőszám: a `RecognitionStabilizer.flipRate` és a „téves megerősített
   címke / pengetés” arány (cél: 0 ismételt pengetésnél), plusz a valódi
   váltás megerősítési késése (cél: ≤ 450 ms).
3. A/B: a mai decoder vs. az eltolt ablak, ugyanazon a fixture-ön; property-
   cella a `viterbi_decoder_test.dart` „onset” csoportjába.
4. Valós gitár a telefon mikrofonjával — a HORIZON végső mérce.

## 5. A „jobb motor” térkép — mit találtunk, mi használható

| Motor / munka | Mi az | Eszközön futtatható? | Használhatóság nekünk |
|---|---|---|---|
| **Chordino / NNLS chroma** (c4dm, Vamp, GPL) | Amit lényegében már leképeztünk Dartban (kroma + HMM/Viterbi) | igen (C++) | Referencia a paraméterekhez (önátmenet β); nem „jobb", ugyanaz az osztály |
| **BTC — Bi-directional Transformer for Chord recognition** (ISMIR 2019, MIT) | 89 % vs. CNN-kroma 80 % (Isophonics stb.) | **nem valós idejű**: kétirányú, teljes szekvenciát néz; előtanított súly NINCS a repóban, az adatok szerzői jogvédettek | Az Analyze (offline) oldalra, nem a Live-ra; betanítás kellene |
| **Chord-CNN-LSTM / BTC-SL / BTC-PL** (ChordMini, 301 címke) | Python/Flask backend, nagy szótár | szerveroldal; TFLite/ONNX export nincs dokumentálva | Eszközön NEM; szerver sértené az offline határt (ADR 0536) |
| **2E1D dual-encoder + pszeudo-címkézés / tudásdesztilláció** (arXiv 2602.19778) | BTC-nél gyorsabb, kompaktabb | elvben exportálható, de nincs kész mobil artefaktum | Kutatási irány a saját CRNN utódjához |
| **Joint strumming-direction + chord transcription** (arXiv 2508.07973) | PONT a mi feladatunk: irány + akkord együtt, akusztikus gitár | a cikk a proxyn blokkolt; súly/kód ismeretlen | Elsőként ELOLVASANDÓ a boxon (adatkészlet! a mi CRNN-jeinkhez) |
| **Szintetikus tanítóadat akkordfelismeréshez** (arXiv 2508.05878) | Generált audión tanított modellek | — | A mi `tool/` szintézis-útvonalunk (Karplus–Strong, ADR 0535) ugyanez az elv — tanítóadat-bővítés |
| **Chord ai** (kereskedelmi) | Eszközön futó saját DL-modell, „beyond human” pontosság; mikrofonból és fájlból | igen, zárt | Termék-referencia: a döntés eszközön marad, a felhasználó fájlja a második forrás (= ADR 0536) |
| **Yousician** | FFT-alapú hangerő/hang-detektálás keretenként, késleltetés-kalibráció | zárt | UX-referencia: kalibráció és „tiszta hang” útmutató, nem motor |
| **Moises chord finder** | szerveroldali stem-szétválasztás + akkord | szerver | Offline határ miatt nem |

**Következtetés:** nincs olyan letölthető, eszközön futó, nyílt, előtanított
motor, ami a mi Live-feladatunkra (valós idejű, causal, mikrofon, ~80 ms) ma
közvetlenül jobb lenne — a nyílt SOTA (BTC-család) **offline, kétirányú**,
súlyok nélkül. A Live-on a nyereség a **döntési rétegben** van (§2–§4), az
Analyze-on a BTC-osztály offline dekóder lehet egy később betanított modell
(a chunk 016 kutatási sorába illeszkedik). A saját CRNN (`chord_crnn.bin`)
újratanítása a 2508.07973 adatkészletével + szintetikus bővítéssel a
legígéretesebb „jobb motor” út — külön fejezet.

## Források

- Cho, Bello: Real-Time Implementation of HMM-Based Chord Estimation in Musical Audio (ICMC 2009) — https://www.researchgate.net/publication/268299859_Real-Time_Implementation_of_HMM-Based_Chord_Estimation_in_Music_Audio
- Stark, Plumbley: Real-Time Chord Recognition for Live Performance (ICMC 2009) — https://www.researchgate.net/publication/228716866_Real-Time_Chord_Recognition_for_Live_Performance
- Adam Stark: Chord-Detector-and-Chromagram — https://github.com/adamstark/Chord-Detector-and-Chromagram
- c4dm: NNLS Chroma / Chordino — https://github.com/c4dm/nnls-chroma , https://code.soundsoftware.ac.uk/projects/nnls-chroma/
- Park et al.: A Bi-directional Transformer for Musical Chord Recognition (ISMIR 2019) — https://arxiv.org/pdf/1907.02698 ; repo: https://github.com/jayg996/BTC-ISMIR19
- Enhancing Automatic Chord Recognition via Pseudo-Labeling and Knowledge Distillation (2E1D) — https://arxiv.org/pdf/2602.19778
- Joint Transcription of Acoustic Guitar Strumming Directions and Chords — https://arxiv.org/pdf/2508.07973
- Training chord recognition models on artificially generated audio — https://arxiv.org/html/2508.05878
- ChordMini (Chord-CNN-LSTM, BTC-SL/PL) — https://github.com/ptnghia-j/ChordMiniApp
- Chirp Group Delay based Onset Detection in Instruments with Fast Attack — https://arxiv.org/pdf/2408.13734
- Chord ai — https://www.chordai.net/next-level-chord-recognition/ , https://chordai.net/
- Yousician support: Guitar sound recognition issues — https://support.yousician.com/hc/en-us/articles/201576782-Guitar-sound-recognition-issues
- Moises chord finder — https://moises.ai/features/chord-finder/
