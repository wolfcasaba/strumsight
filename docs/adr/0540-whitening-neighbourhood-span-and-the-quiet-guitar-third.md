# ADR 0540 — A whitening-szomszédság szélessége és a halk gitárterc

**Státusz:** javasolt (2026-09-11, az E18-R01 leletek javító köre)

**Hatókör:** `lib/features/live/engine/dsp/nnls_chroma.dart` — egyetlen
konstans (`whiteningHalfSemitones`: ±6 → ±3 félhang) és a mértékegysége.
Érinti mind a Live, mind az Analyze utat, mert a `NnlsChroma` közös.
**Nem** nyúl a szótárhoz, a dekóderhez, a konfidencia-formulához vagy
bármely kapuküszöbhöz.

Kapcsolódik: [ADR 0539](0539-live-recognition-stability-stabilized-hero-and-onset-guard.md)
(a stabilizálási kör — ez a kör a MÖGÖTTE lévő jelet javítja, nem a
megjelenítést), [ADR 0516](0516-live-chord-decision-wiring.md) (a keret-döntés
egyetlen helye — változatlan), [ADR 0354](0354-recognition-baseline-manifest-and-evidence-index.md)
(az alapvonal-manifest), `AGENTS.md` §9 (fixture + property + valós audio),
`docs/rag/chunks/012-chord-dictionary-viterbi.md` („Whitening SPAN" szakasz),
`docs/reviews/e18-r01-emulator-report.md` F9 lelet.

## Kontextus — a MÉRT tünet

Az E18-R01 emulátoros kör F9 lelete: *„Találati arány 2/5. C és A helyes, G, D
és E egyáltalán nem ismerte fel. Téves állítás nem volt."* A lelet helyesen
állapította meg, hogy a hiány a **recall** oldalán van.

Hét címkézett, valós gitárfelvételen, a teljes `LivePipeline`-on átvezetve
(emulátor és mikrofon nélkül) a kiindulás:

| | címke | döntés |
|---|---|---|
| C, A, F, B | helyes | konfirmál |
| **D** | **helyes** | **soha nem konfirmál** (56 keret `lowConfidence`) |
| **G** | **`Bm`** / `Dsus4` | — |
| **E** | **`Bsus4`** | — |

## A gyökér — mérve, nem sejtve

A nyers spektrum szerint a felvételek nem hibásak, a dekóder jól hallja őket:

- **E**: E3=1.00, B2=0.97, **G#3=0.12** — a nagyterc a leghalkabb szóló hang.
- **G**: D3=1.00, B2=0.84, **G2=0.02** — `x20033` fogás, a basszus a B.
- Az E „F#"-je: F#4=0.19, de **F#3=0.00** — F#4 = 370 Hz = B2 (123.47 Hz)
  pontos 3. harmonikusa, tehát fantom, nincs saját alaphangja.

A `Bsus4` és a `Dsus4` nem véletlen hiba: mindkettő **kizárólag a valódi akkord
hangos gyökére és kvintjére** épülő profil, amelyben az akkord saját terce
láthatatlan. Ugyanaz a hibaosztály, amiért a 26. körben a power-5 és a sus2
kimaradt a szótárból („egy `[gyök, kvint]` profilnak nincs terce, amit
megcáfolhatna, ezért ellop minden hármast, amelynek halk a terce") — csak a
kvintre épülő sus4 újrateremti, mert `Xsus4 = {X, X+5, X+7}` az X = kvint
választással éppen `{kvint, gyök, szekund}`, és az a szekund pontosan oda esik,
ahová a kvint saját 3. harmonikusa.

**A mögöttes ok a spektrális whitening szomszédságának szélessége.** A
`_whiten` minden bint elosztja a ±szomszédsága RMS-ével: a szélesség dönti el,
**mihez képest mérjük, hogy valami hangos**. Széles ablaknál egy bin csaknem egy
oktávhoz normalizálódik, így egy halk hang halk marad a hangos szomszédjai
mellett; szűk ablaknál minden lokális csúcs a **saját** szomszédságához
normalizálódik, tehát a csúcsok egy közös szintre húzódnak.

Gitárnál ez dönti el az akkordot, mert **a gitárfekvés nem szintlapos: a kvint
két-három húron duplázódik, a terc pontosan egyszer van lefogva** — a kvalitást
meghatározó hang tehát rendszeresen a jel leghalkabb eleme.

## Döntés

**D1.** A `whiteningHalfSemitones` értéke **±3.0 félhang** (volt: ±6.0).

**D2.** A konstans **félhangban** tárolódik, nem bin-számban. A derivált
bin-szám egyszer, a konstruktorban áll elő.

**D3.** Semmi más nem változik: se szótár, se Occam-bias, se `chordConfRise`,
se stabilizátor, se `bassWeight`. Egyetlen konstans.

## Miért ±3 — a szélesség KÉT oldalról kötött

A szűkítés, ami a halk tercet láthatóvá teszi, **a gyök szint-dominanciáját is
erodálja** — és a basszus-chromának nincs más fogása a gyök megnevezésére. A
70. kör ugyanezt az exponens oldaláról már látta („a teljes whitening erodálja a
gyök dominanciáját"); a szélesség oldaláról is elérhető.

A hatásos ablak a bin-rácsra kvantált (`round(félhang × binsPerSemitone)`),
ezért a mérés bin-ben értelmes:

| hatásos fél-ablak | valós 7: helyes / konfirmál | `dsp_property_test.dart` (42/7/123/2026/31337) |
|---|---|---|
| 7 bin (±2.2, ±2.4) | 7/7 / 7/7 | **BUKIK 5-ből 4-en** |
| 8 bin (±2.5…±2.8) | 7/7 / 7/7 | zöld |
| **9 bin (±3.0)** | **7/7 / 7/7** | **zöld** |
| 12 bin (±4.0) | 6/7 | zöld |
| 15–18 bin (±5, ±6) | 4/7 | zöld |

A 7 binen jelentkező property-bukások mély fekvésű dominánsszeptimek, amelyek a
**saját tercükre épülő szűkített hármasra** esnek össze — `B7` → `D#dim`,
`A#7` → `Ddim`, vagyis az akkord a gyöke nélkül. Pontosan így néz ki egy
elvesztett gyök.

±3.0 (9 bin) **két binnel a property-szakadék fölött** (8 bin is mindent átvisz)
és a valós-audió platón belül. ±3 félhang egyúttal a **kisterc** — az a
szomszédság, amelyet a normalizáló még átfoghat anélkül, hogy egy akkordhangot
egy másikkal átlagolna össze.

A 70. kör burkoló-védőesetei (telefon-mikrofon mélyvágás, testrezonancia) a
**teljes** sweep-en tartják magukat, tehát nem a szélesség volt a thin-mic
javítása, hanem a `whiteningExponent` — a szélesség így szabadon választható a
fenti két kritérium szerint.

## Elvetett alternatívák

- **`binsPerSemitone: 5`.** Ez látszott először javításnak (5/7 → 7/7), de a
  kontroll megcáfolta: bins 5 a szélességet ±6-on TARTVA (30 bin) **5/7** — a
  felbontás semmit nem ad. A látszat abból jött, hogy a konstans bin-számban
  volt tárolva, és 18 bin öt bin/félhangnál ±3.6 félhang. Ezért D2.
- **±2.0 félhang.** A valós hét felvételen ez is 7/7, és a szintetikus
  fixture-ömnek ez kellett — de 6 binen a `dsp_property_test.dart` mély
  dominánsszeptimjei elbuknak. Elvetve: a randomizált, több seedes property
  erősebb bizonyíték hét felvételnél.
- **A sus4 Occam-bias emelése** (0.04 → 0.08). Mérve: a G nyers címkéje
  `Dsus4` → `Dm`-re váltott, azaz továbbra is D-gyökerű és továbbra is rossz.
  Nem ez a fogantyú; a konstans visszaállítva.
- **A konfidencia-margó közös gyökű riválisainak kihagyása** (a D
  `lowConfidence`-ére). Elvetve mérés előtt: egy magányos kitartott hangnál épp
  a közös gyökű profilok a riválisok, tehát ez fantomakkordot csinálna — amit a
  `voice_rejection_test.dart` tilt és az `AGENTS.md` §5 kizár. A D végül
  magától konfirmál, mert a tisztább króma megnöveli a margóját.
- **Fordítás-tudatos basszus** (a `G/B` kezelésére). Offline mérve működik
  (G: `Bm` 0.7921 → `G` 0.8291, a többi hat győztese változatlan), de a
  szélesség-javítás után **nem szükséges** — ezért nem került be (AGENTS §4:
  nincs mellékes bővítés). Follow-upként megtartva.

## Bizonyíték

**Fixture (audió nélkül, determinisztikus) — és ameddig elér.**
`test/features/live/dsp/spectral_whitening_test.dart`. Egyetlen cella
reprodukálja a leszállított javítást audió nélkül: az **open E 0.08-as terccel**
±6-on NEM `E`, ±3-on `E`. A csoport többi cellája nem-regresszió: valódi Dsus4
marad `Dsus4`, valódi A7 marad `A7`, az open Em 0.08-ig helyes, és egy moll
egyetlen tercszinten sem olvasható dúrként.

**Amit a szintetikus harness NEM tud megmutatni, és ezt nyíltan kell kimondani.**
A szintetikus hangmodell (1/h sorozat, hat harmonikus) nem oda teszi az
energiát, ahová egy valódi húr, és a szélesség szondájaként **nem monoton**. A
mért visszanyerési padló (a leghalkabb még helyes terc):

| fekvés | ±6.0 | ±4.0 | ±3.5 | **±3.0** | ±2.5 | ±2.0 |
|---|---|---|---|---|---|---|
| open E | 0.12 | 0.16 | 0.08 | **0.08** | 0.03 | 0.03 |
| open G | 0.30 | *egyik sem* | 0.30 | **0.30** | 0.08 | 0.03 |
| open Am | 0.12 | 0.22 | 0.22 | **0.22** | 0.12 | 0.03 |

Az open G ±4.0-on **egyetlen** tercszinten sem helyes, miközben ±6.0-on és
±3.5-en 0.30-nál igen. Ez egy döntési határon álló jel jellemzője, nem sima
mérés — ezért a szintetikus padlók nem követik a valós felvételek viselkedését,
és a javulás bizonyítéka a valós mérés, nem a szintetikus. A korábbi
változatomban szerepelt egy komparatív állítás („a leszállított szélesség
szigorúan halkabb tercet visz át, mint ±6") — **ez ±3.0-nál nem igaz**, ezért
kivettem, nem pedig addig gyengítettem, míg átmegy.

Megjegyzésre érdemes, hogy a szintetikus modell **először egyáltalán nem
reprodukálta** a hibát (lapos 1/h sorozattal az E minden szélességen helyes
volt). A reprodukcióhoz a valódi **szint**-aszimmetria kellett — a duplázott
kvinthez képest lehúzott terc —, és épp ez azonosította a mechanizmust.

## A változás MÉRT költsége

Az `open Am` szintetikus fekvésnél a visszanyerési padló **0.12 → 0.22-re
romlik**: a 0.12–0.16 sávban a címke `Esus4` lesz — profil az akkord saját
kvintjére, vagyis ugyanaz a hibaosztály, amit ez a változás máshol javít. A
teszt a tartott 0.22-es padlót rögzíti, hogy a további erózió kiderüljön; a
veszteséget itt dokumentálom, nem a tesztben elrejtve.

Kontextus, ami mérsékli, de nem tünteti el: az `open Em` és `open Dm` fekvés
**mindkét szélességen, minden tercszinten helyes** (0.08-ig), tehát ez nem
rendszerszintű moll-regresszió, hanem egy határon álló szonda. És a hét valós
felvétel **mind dúr** — valódi moll felvételem nincs, tehát a mollokat valós
audión nem igazoltam.

**Valós audio.** A hét címkézett felvétel a teljes `LivePipeline`-on:
**7/7 helyes címke és mind a hét `confirmed`** (volt: 4/7 helyes, a D soha nem
konfirmált). A szonda: `test/tooling/live_chord_wav_probe_test.dart`,
`LIVE_WAV_DIR` nélkül kihagyja magát.

**Property.** `test/property/dsp_property_test.dart` zöld a dokumentált 42, 7,
123, 2026 és 31337 seeden.

## Amit ez a kör NEM bizonyít — nyíltan

- **A 82 felvételes / 11 767 eseményes korpusz nincs megmérve.** Az
  `evaluation/recognition/baseline_manifest.json` akkord-pontossága (0.6707,
  5ceed22d app-commit) a `ml/data/klangio` korpuszon készült, ami a repón
  **kívül**, a mérőgépen él — ezen a boxon nem futtatható. Ez a szám tehát az
  új szélességre **IGAZOLATLAN**, és bármilyen release-állítás előtt újra kell
  futtatni a `tool/benchmarks/real_audio_dsp_baseline.dart`-ot.
- **Hét felvétel kevés.** A mechanizmus elvi és a szintetikus reprodukció
  független tőle, de a 7/7 önmagában kis minta.
- **Valódi gitáros A/B nem történt** (ADR 0539 D4 / E18-R05 még nyitott). Ez a
  kör felvételeket mért, nem a felhasználó hangszerét.
- **Moll akkord valós audión nincs mérve.** Mind a hét felvétel dúr. A mollokról
  csak szintetikus adat van, és abban van egy mért romlás (lásd „A változás MÉRT
  költsége").

## Amit a változás FELTÁRT, de nem okozott

A basszus-chroma a `bassMaxMidi` alatti mindent összehajt **mélység szerinti
súlyozás nélkül**, tehát azt mondja, hogy „ezek a hangosztályok mélyen
szólnak", azt soha, hogy „a C mélyebben van, mint az E". Az egyetlen teljesen
szimmetrikus akkordkvalitásnál (bővített: `{C,E,G#}` egyszerre Caug, Eaug ÉS
G#aug) a gyök ezért mérési véletlenen áll: a régi `Caug` fixture C3-E3-G#3-at
szólaltatott, és **C 0.72 vs E 0.69** döntötte el. A fixture most mindhárom
elfordítást a gyökével egyedül a basszus-ablakban szólaltatja, és a teljes
±1…±6 sávon átmegy — tehát a mechanizmust rögzíti, nem a konstanst.

Ugyanez a mélység-vakság a ±3 alsó korlátjának valódi oka: ha a gyök
szint-dominanciája elfogy, a basszus-chromának nincs mivel megnevezze a gyököt.

**Follow-up (nem ez a kör):** mélység-súlyozott basszus-chroma. Ez egyszerre
adna szilárd alapot a bővített hármas gyökének, feloldaná a szélesség alsó
korlátját, és elvi utat nyitna a fordításokhoz / slash-akkordokhoz (`G/B`).

## Utólagos MÉRÉS — a ±3 alsó korlátjának egyik indoka megszűnt (E18-R12, 2026-09-11)

A „Miért ±3" szakasz az alsó korlátot részben a **gyök-erózióra** alapozta: ha a
szomszédság szűkül, a csúcsszintek kiegyenlítődnek, és a basszus-chromának nincs
mivel megnevezze a gyököt. Az E18-R12 a whitening **kernelt** lapos dobozról
normált **Hamming-súlyozásra** váltotta (ADR 0542), és ezt az eróziót megmérte
újra, 40–47 MIDI gyökökön, nyolc mély domináns szeptimen:

```
kernel    span   mélység-vak veszteség   mélység-súlyozott
box       ±2      2/8                     0/8
box       ±1.5 … ±0.5   0/8               0/8
hamming   ±2 … ±0.5     0/8               0/8
```

Két dolog derült ki, és egyik sem az, amit ez az ADR feltételezett:

1. **A Hamming-kernellel az erózió egyáltalán nem jelentkezik** — egyetlen
   szeptim sem veszik el ±2-nél, sőt ±0.5-ig sem. Tehát az alsó korlátnak EZ az
   indoka a szállított kernellel már nem áll.
2. **Az erózió a dobozzal sem monoton a spanban**: ±2-nél 2/8, de ±1.5 és lejjebb
   0/8. Vagyis a ±2 egy konkrét törésponti eset volt, nem egy trend kezdete —
   amit ez az ADR „alsó korlátként" írt le, az egy pontszerű jelenség.

**Amit ez NEM jelent.** A ±3 döntése nem dől meg: a szélesség FELSŐ korlátja
(a halk terc elnyomása) érintetlen, és azt ez a kör nem mérte újra a span
tengelyén. A mélység-súlyozás (ADR 0541) sem válik feleslegessé — a „gyök és terc
is mély" cellájában továbbra is az nevezi meg a gyököt, és ott a kontroll a
szállított kernellel is kontrasztos. Csak az az EGY érv esett ki, hogy a szűk span
eróziója alulról kötné a szélességet.

**Őrteszt:** `test/features/live/dsp/register_windows_test.dart` — a régi
kontroll (`blindLosses > 0`) mostantól a DOBOZ kernelre van kötve, ahol a
jelenség valóban létezik, és egy új cella rögzíti, hogy a Hamming-kernel
megszünteti. A kontrollt nem lazítottuk fel azért, hogy zöld legyen.
