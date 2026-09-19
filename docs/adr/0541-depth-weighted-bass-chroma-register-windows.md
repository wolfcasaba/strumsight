# ADR 0541 — Mélység-súlyozott basszus-króma: regiszter-ablakok kemény vágás helyett

**Státusz:** javasolt (2026-09-11, E18-R07)

**Hatókör:** `lib/features/live/engine/dsp/nnls_chroma.dart` — a 12 binre
hajtás regiszter-súlyozása. Érinti a Live és az Analyze utat is (közös
`NnlsChroma`). **Nem** nyúl a szótárhoz, a dekóderhez, a konfidencia-formulához,
a whitening szélességéhez vagy bármely kapuküszöbhöz.

Kapcsolódik: [ADR 0540](0540-whitening-neighbourhood-span-and-the-quiet-guitar-third.md)
(a whitening-szélesség — ez a kör annak a **follow-upját** szállítja, amit ott
nyitottként hagytam), kutatási jegyzet:
[`docs/research/chordino-reference-parameters-2026-09.md`](../research/chordino-reference-parameters-2026-09.md),
`docs/rag/chunks/012-chord-dictionary-viterbi.md`, `AGENTS.md` §9.

## Kontextus — a MÉRT hiány

A basszus-króma dolga a **gyök** megnevezése. A fold kemény vágással ment:

```dart
if (midi <= bassMaxMidi) lastBassChroma[pc] += a;   // bassMaxMidi = 52 (E3)
```

Minden mély hang **egyenlően** számított, tehát a basszus-króma azt tudta
mondani, hogy „ezek a hangosztályok mélyen szólnak", azt soha, hogy **„a C
mélyebben van, mint az E"**. Két mért következmény:

1. **A bővített hármas gyöke érmefeldobás volt.** A `{C,E,G#}` hangkészlet
   egyszerre Caug, Eaug és G#aug, tehát kizárólag a basszus nevezheti meg a
   gyököt. A `Caug` fixture C3-E3-G#3-at szólaltatott egy szinten, és a
   kimenetet **basszus C 0.68 vs E 0.73** döntötte el → `Eaug`. Az ADR 0540
   körében ez azért derült ki, mert a whitening szélességének változtatása
   átfordította ezt a 0.05-ös különbséget.
2. **Ez adta a whitening-ablak ALSÓ korlátját.** A szűkebb ablak a csúcs-
   szinteket egy szintre húzza — ami a halk tercet láthatóvá teszi (ADR 0540) —,
   de ezzel a gyök hangosságát is elveszi, és a basszus-krómának nem maradt más
   jelzése. Mért: ±2 félhangnál a mély dominánsszeptimek a **saját tercükre
   épülő szűkített hármasra** esnek (`B7` → `D#dim`, `A#7` → `Ddim`).

## A referencia nem vág — súlyoz

A Chordino / NNLS-Chroma a félhang-spektrumot sima emelt-koszinusz
regiszter-ablakokkal **szorozza** a 12 binre hajtás előtt
(`Chordino.cpp:412-413`). A félhang-index 0 = MIDI 21 (A0). A `basswindow` egy
púp a MIDI 21–57 (A0–A3) sávon, csúcsa MIDI 39 (E♭2, ~78 Hz) körül, és A3-nál
nullába fut. Gitárhangokra: **E2 = 0.995, E3 = 0.222** — a mély E négy és
félszer annyit számít.

> **Licenc.** A referencia **GPL-2+**, a StrumSight privát app. A referencia
> kódját és betáblázott konstansait **nem másoltam**: a publikált módszert
> (emelt-koszinusz ablak megadott félhang-tartományon) implementáltam, és a
> kinyomtatott táblához csak ellenőrzésként hasonlítottam — a Hann-alak a
> `treblewindow`-t 5e-07-ig, a `basswindow`-t 2e-02-ig adja vissza. Részletek a
> kutatási jegyzetben.

## Döntés

**D1.** A basszus- és treble-króma fold **sima regiszter-súlyokkal** megy, nem
kemény vágással. A basszus-súly a mélységgel monoton csökken és A3 felett nulla.

**D2.** A kemény vágás viselkedése megmarad elérhetőnek
(`referenceRegisterWindows: false`), hogy a tesztek ki tudják mondani, **mit
tett** a régi út — nem csak azt, hogy az új mit tesz. A `bassMaxMidi` /
`trebleMinMidi` ezt a tartalék utat definiálja.

**D3.** A **treble**-ablakot NEM vettem át. A referencia a harmóniát D4 körül
csúcsosítja és a széleken elhalkítja; a miénk E2–E6 között lapos marad. Ez
önálló mérést igényel, és ez a kör egy dolgot változtat.

**D4.** A whitening szélessége marad **±3 félhang** (ADR 0540), noha a
mélység-súlyozás az alsó korlátot megszüntette (±1.5-nél is 8/8). ±3 a
referencia saját értéke; ennél szűkebbre menni e kör mérései alapján
túlillesztés lenne. A felszabadult fejtér **külön kör** kérdése.

## Bizonyíték

| mérés | kemény vágás | mélység-súlyozás |
|---|---|---|
| hét címkézett valós felvétel (offline pontozó) | 7/7 helyes, latch 6/7 | **7/7 helyes, latch 7/7** |
| ugyanaz a teljes `LivePipeline`-on | 7/7 | **7/7** |
| `Caug` zárt fekvés (C3 E3 G#3) | `Eaug` (bass C 0.68 / E 0.73) | **`Caug`** (bass **C 0.87 / E 0.47**) |
| mély dom7 E2–B2, whitening ±3 | 8/8 | 8/8 |
| mély dom7 E2–B2, whitening **±2** | **6/8** (`A#→Ddim`, `B→D#dim`) | **8/8** |
| mély dom7 E2–B2, whitening ±1.5 | 8/8 | 8/8 |

**Fixture:** `test/features/live/dsp/register_windows_test.dart` — a
mélység-ORDERING közvetlenül (teszt-szem: `debugBassWeightForMidi`, monoton
E2-től A3-ig, C4 felett nulla), a zárt fekvésű `Caug`, és a ±2-es
whitening-ablaknál tartott dominánsszeptimek. Minden cella a kemény vágás
viselkedését is kimondja, tehát bukik, ha a súlyozás visszakerül vágásra.
`dim_aug_chord_test.dart` visszakapta az eredeti zárt fekvésű `Caug` celláját,
mert az most **becsületesen** átmegy — a gyök geometriából jön, nem 0.05-ös
különbségből.

**Property:** `test/property/dsp_property_test.dart` zöld a dokumentált 42, 7,
123, 2026, 31337 seeden.

**Kapu:** format, analyze, `test/features/live` (122), `test/property`,
`test/features/analyze`, `test/features/audio_analysis`, `test/core/music`,
`test/features/practice`, `test/features/learn`, `test/accessibility`,
`test/features/songs`, `test/features/chords`, `test/app/bootstrap`,
`test/features/ai_tutor/data`, architecture, secrets, l10n — mind zöld.

**Költség:** a fold egy tábla-kereséssel és egy szorzással jár hang/keret
helyett egy összehasonlítással; a táblák a konstruktorban egyszer állnak elő.
Elhanyagolható.

## Amit ez NEM bizonyít

- **A 82 felvételes / 11 767 eseményes korpusz nincs megmérve.** A
  `ml/data/klangio` a repón kívül él; a `baseline_manifest.json` 0.6707-es
  akkord-pontossága erre a változásra is **igazolatlan**, és release-állítás
  előtt újra kell futtatni a `tool/benchmarks/real_audio_dsp_baseline.dart`-ot.
- **Moll akkord valós audión továbbra sincs mérve** — mind a hét felvétel dúr
  (ld. ADR 0540 „A változás MÉRT költsége": a szintetikus open Am 0.12–0.16
  sávja `Esus4`-re esik; ezt a mélység-súlyozás nem célozta és nem mértem újra
  utána).
- **Valódi gitáros A/B nem történt** (ADR 0539 D4 / E18-R05).
- A `basswindow` pontos generáló formuláját nem fejtettem meg (2e-02 az
  illesztési hiba); a forma és a tartomány biztos, a finomszerkezet nem.

## Follow-up

A kutatási jegyzet §4-e egy nagyobb, még nem szállított eltérést azonosít: a
referencia a whiteningnél **kivonja a futó átlagot és félhullámban
egyenirányít** (`(x − mean) > 0 ? (x − mean)/std^w : 0`), míg mi átlag-kivonás
nélkül RMS-sel osztunk. Ez lokális kontraszt-operátorrá teszi a whiteninget, és
épp a fantom-energiát célozza (pl. az E felvétel B2 3. harmonikusából származó
F#4-jét, amelynek nincs saját alaphangja). Ez a whitening átírása, nem
konstans-hangolás — önálló kör, önálló fixture + property + valós mérés.
