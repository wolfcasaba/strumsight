# A gitár-motor pontos beállításai — a referencia-implementáció és a miénk

**Dátum:** 2026-09-11 · **Kör:** E18-R07 · **Kérés:** „nézz utána a gitár motor
pontos beállításának"

**Mit vizsgáltam.** A `NnlsChroma` + `ChordDictionary` + `ViterbiChordDecoder`
lánc a Chordino / NNLS-Chroma (Mauch & Dixon, *Approximate Note Transcription
for the Improved Identification of Difficult Chords*, ISMIR 2010) portja. A
`docs/rag/chunks/012` a paramétereket a cikk és a plugin-dokumentáció alapján
rögzítette; ebben a körben a **tényleges forráskódot** vetettem össze a
miénkkel.

**Forrás:** [`c4dm/nnls-chroma`](https://github.com/c4dm/nnls-chroma) —
`chromamethods.h`, `NNLSBase.cpp`, `Chordino.cpp`, `NNLSChroma.cpp`.

> **LICENC — fontos határ.** A referencia **GPL-2+** (`chromamethods.h`
> fejléc: „This file copyright 2008-2010 Matthias Mauch and QMUL… GNU General
> Public License… version 2 or later"). A StrumSight privát app (`publish_to:
> 'none'`), nincs GPL-kompatibilis licence. **A referencia kódját és a
> betáblázott konstansait nem másoltam és nem is szabad átmásolni.** Amit
> tettem: a publikált *módszert* implementáltam (emelt-koszinusz ablak megadott
> félhang-tartományon), és a referencia kinyomtatott táblájához csak
> *ellenőrzésként* hasonlítottam. A repó `test/tooling/reference_model_licence_guard_test.dart`-ja
> mutatja, hogy ez a projekt komolyan veszi a referencia-licenceket.

## 1. Ami EGYEZIK

| paraméter | referencia | nálunk |
|---|---|---|
| log-frekvencia felbontás | `nBPS = 3` bin/félhang | `binsPerSemitone = 3` |
| NNLS szótár harmonikus-lecsengés | geometriai | `spectralShape = 0.7` |
| NNLS használata | `m_useNNLS = 1.0` | mindig |
| hangolásbecslés | `m_tuneLocal = 0.0` (globális az alapérték) | EMA-simított, `tuningSmoothing = 0.2` |
| no-chord boost | `m_boostN = 0.1` | `noChordScore = 0.55` (más realizáció, ld. lent) |
| spectral roll-on | `m_rollon = 0.0` (ki) | nincs implementálva — egyezik |
| króma-normalizálás | `m_doNormalizeChroma = 0` | L2 a fold után |

## 2. A whitening ablakszélessége — itt volt a ma javított hiba

```c
// NNLSBase.cpp:368
// make hamming window of length 1/2 octave
int hamwinlength = nBPS * 6 + 1;      // = 19 bin
```

A referencia whitening-kernele **19 bin = 6 félhang TELJES szélesség**, azaz
**±3 félhang fél-ablak**.

A mi kódunkban ez így állt:

```dart
this.whiteningHalfWindow = 18, // ±half octave at 3 bins/semitone
```

**18 bin mint FÉL-ablak**, azaz ±6 félhang — a referencia „fél oktáv" *teljes*
ablakát fél-ablakként olvasta valaki, és ezzel **megduplázta**. A ma végzett
mérés (E18-R01 F9, ADR 0540) függetlenül, a hét címkézett valós felvételről
±3 félhangra jutott: **pontosan a referencia értéke**. Két irányból ugyanaz a
szám.

Tanulság, amit a kód már tükröz: a konstans **félhangban** tárolódik, nem
bin-számban, különben a `binsPerSemitone` csendben elmozdítja a zenei
jelentést (ez egyszer már félrevezetett — ld. ADR 0540 „Elvetett alternatívák").

## 3. A regiszter-szétválasztás — ez volt a NAGY eltérés (ADR 0541)

A referencia **nem vág**; a félhang-spektrumot sima emelt-koszinusz
regiszter-ablakokkal szorozza a 12 binre hajtás előtt
(`Chordino.cpp:412-413`):

```c
chroma[iSemitone % 12]      += currval * treblewindow[iSemitone];
basschroma[iSemitone % 12]  += currval * basswindow[iSemitone];
```

A félhang-index 0 = **MIDI 21 (A0)** (`minMIDI = 21 + minoctave*12 - 1`,
`minoctave = 0`). Mért alak a kinyomtatott táblákból:

| ablak | hossz | nem nulla | csúcs |
|---|---|---|---|
| `basswindow` | 84 bejegyzés | index 0–36 → **MIDI 21–57 (A0–A3)** | index 18 → **MIDI 39 ≈ E♭2, 78 Hz** |
| `treblewindow` | 84 bejegyzés | 0–83 → MIDI 21–104 | index 41 → **MIDI 62 ≈ D4, 294 Hz** |

Mindkettő Hann-alak. Illesztve: `treblewindow` = `0.5 − 0.5·cos(2π(i+0.5)/84)`
**5e-07**-ig (a 6 jegyű nyomtatás pontossága), `basswindow` = ugyanez 37-es
hosszon **2e-02**-ig (tehát a forma és a tartomány biztos, a pontos generáló
formula nem — nem is kell, ld. a licenc-határt).

Guitár-hangokra lefordítva a basszus-ablak:

| hang | referencia súly | a mi kemény vágásunk |
|---|---|---|
| E2 (40) | 0.995 | 1.0 |
| G2 (43) | 0.944 | 1.0 |
| B2 (47) | 0.625 | 1.0 |
| C3 (48) | 0.542 | 1.0 |
| D3 (50) | 0.375 | 1.0 |
| E3 (52) | **0.222** | 1.0 |
| G3 (55) | 0.056 | **0** |

**A referenciában E2 ~4.5×-ét számít E3-nak.** A miénk `midi <= bassMaxMidi`
kemény vágással mindet egyenlően súlyozta, tehát a basszus-króma azt tudta
mondani, hogy „ezek a hangosztályok mélyen szólnak", azt soha, hogy „a C
mélyebben van, mint az E". Ez okozta:

- a bővített hármas gyökének érmefeldobását (mért: `Caug` zárt fekvésnél
  basszus C 0.68 vs E 0.73 → **`Eaug`**; súlyozva C 0.87 vs E 0.47 → `Caug`);
- a whitening-ablak **alsó** korlátját: ha a csúcs-szinteket kiegyenlítjük, a
  gyöknek nem marad más jelzése. Mért: ±2 félhangnál a mély dominánsszeptimek
  **6/8**-ra esnek (`A#→Ddim`, `B→D#dim`), mélység-súlyozással **8/8** még
  ±1.5-nél is.

A treble oldalon is van eltérés, amit **nem** vettem át: a referencia a
harmóniát D4 körül csúcsosítja és a széleken elhalkítja, a miénk E2–E6 között
lapos. Ennek átvétele önálló mérést igényel, nem csomagoltam ide.

## 4. A whitening ARITMETIKÁJA — eltérés, amit NEM vettem át

Referencia (`Chordino.cpp:333-345`):

```c
runningmean = SpecialConvolution(spec, hw);            // Hamming-súlyozott futó átlag
runningstd[i] = (spec[i] - runningmean[i])^2;
runningstd    = SpecialConvolution(runningstd, hw);
runningstd[i] = sqrt(runningstd[i]);
spec[i] = (spec[i] - runningmean[i]) > 0
        ? (spec[i] - runningmean[i]) / pow(runningstd[i], m_whitening)
        : 0;                                          // félhullámú egyenirányítás
```

A miénk: `_s[j] /= pow(max(localRMS, 1e-4·maxS), whiteningExponent)`.

Négy érdemi különbség:

1. **A referencia kivonja a futó átlagot**, a miénk nem. Ezzel a referencia
   *lokális kontraszt*-operátor: egy csúcsnak meg kell haladnia a környezetét.
2. **Félhullámú egyenirányítás**: ami a lokális átlag alatt van, az **nulla**.
   Ez a zajpadlót és az erős csúcsok „szoknyáját" sokkal keményebben elnyomja,
   mint az RMS-sel osztás.
3. **Kernel**: a referencia normált **Hamming** (a 3 félhangra lévő szomszéd
   kevesebbet számít), a miénk lapos box (prefix-szumma).
4. **Exponens**: a referencia alapértéke `m_whitening = 1.0`; a miénk 0.7. A
   referenciában **van egy kikommentelt preset éppen 0.7-tel**
   (`NNLSBase.cpp:308`), tehát a 0.7 ismert referencia-variáns, nem a mi
   kitalálásunk — és a 70. kör mérte, hogy nálunk 1.0 erodálja a gyököt. Az
   viszont elképzelhető, hogy a mi 0.7-ünk a **hiányzó átlag-kivonást**
   kompenzálja; ez külön kör kérdése.

**Ezt a négyet szándékosan nem nyúltam meg.** A 2. pont (átlag-kivonás +
egyenirányítás) a legígéretesebb következő lépés, mert éppen a fantom-energiát
(pl. az E felvétel B2-ből származó F#4-jét) célozza — de ez a whitening
átírása, nem konstans-hangolás, és önálló fixture + property + valós mérés kell
hozzá.

## 5. A szótár és a dekóder

A szótárunk (maj, min, 7, maj7, m7, sus4, dim, aug + N.C.) és a Viterbi
önátmenet-bónusza (`selfBonus = 0.22`) a referencia szellemét követi, de nem a
betűjét: a referencia `chordDictionary()`-je és HMM-je más felépítésű. A
no-chord kezelés is más realizáció — ott `m_boostN = 0.1` *additív* boost a
HMM-ben, nálunk `noChordScore = 0.55` *padló* a koszinuszon. Mindkettő ugyanazt
a célt szolgálja; az ekvivalenciájukat nem mértem, és nem is állítom.

**Egy eltérés, amit érdemes megjegyezni:** a referencia `sus4`-et tart a
szótárban Occam-handicap nélkül, de van HMM-je a szekvencia fölött. Nálunk a
sus4 0.04-es handicapot kapott (181. kör), mert a mi onlineViterbink kevésbé
véd. A mai mérés szerint a `kvintre épülő sus4` hibaosztály nem a handicappal
oldható meg (0.04 → 0.08 a G nyers címkéjét `Dsus4`→`Dm`-re vitte, továbbra is
rosszul), hanem a whitening szélességével volt — ld. ADR 0540.

## 6. Amit ebből szállítottam, és amit nem

**Szállítva:**
- whitening fél-ablak ±6 → **±3 félhang** (a referencia értéke) — ADR 0540;
- **mélység-súlyozott regiszter-ablakok** a kemény vágás helyett — ADR 0541.

**Nem szállítva, mérve vagy azonosítva:**
- a whitening átlag-kivonása + félhullámú egyenirányítása (§4.1–4.2) — a
  legígéretesebb következő lépés;
- Hamming- helyett lapos kernel (§4.3);
- a treble-ablak csúcsosítása D4 körül (§3 vége);
- a referencia tágabb elemzési sávja (A0–G#7 vs a mi E2–E6-unk);
- `m_whitening` 1.0 vs 0.7 újramérése az átlag-kivonás bevezetése UTÁN.

**Amit továbbra sem tudunk:** a 82 felvételes / 11 767 eseményes
`ml/data/klangio` korpusz a repón kívül él, ezen a gépen nem futtatható — a
`baseline_manifest.json` 0.6707-es akkord-pontossága tehát mindkét mai
változásra **igazolatlan**, és release-állítás előtt újra kell futtatni a
`tool/benchmarks/real_audio_dsp_baseline.dart`-ot. Valódi gitáros A/B sem
történt (ADR 0539 D4 / E18-R05).

## Hivatkozások

- Mauch & Dixon, „Approximate Note Transcription for the Improved
  Identification of Difficult Chords", ISMIR 2010.
- [`c4dm/nnls-chroma`](https://github.com/c4dm/nnls-chroma) (GPL-2+) —
  `chromamethods.h`, `NNLSBase.cpp`, `Chordino.cpp`.
- [Chordino and NNLS Chroma, Isophonics](https://isophonics.net/nnls-chroma) —
  plugin-paraméterek leírása.
