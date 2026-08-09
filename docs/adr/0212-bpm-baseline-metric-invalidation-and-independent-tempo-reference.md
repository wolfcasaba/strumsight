# ADR 0212 — A GOV-06 BPM-metrika visszavonása és független tempó-referencia

- **Státusz:** Elfogadva (GOV-06b pre-flight, 2026-08-09)
- **Kör:** GOV-06b / `E99-R05` — a valós-audio DSP baseline **BPM-metrikájának
  javítása** (governance-kör)
- **Implementer motor:** Terra · az ADR-t az orchesztrátor (Claude Opus 5) írta
- **Felülírja:** [ADR 0199](0199-real-audio-dsp-baseline-measurement-contract.md)
  **Döntés 6** (a származtatott BPM-metrika). Az ADR 0199 minden más döntése
  érvényben marad.
- **User-jelzés:** 2026-08-09 „a gov 6 javítani kell".

## Kontextus

A GOV-06 (`E99-R04`, PR #207, `docs/eval/real-audio-dsp-baseline.md`) három
számot közölt. Kettő érvényes, **egy nem**:

| Metrika | Érték | Állapot |
|---|---|---|
| Akkord-pontosság | 67,069% (baseline 18,832%) | **érvényes** — a ground-truth esemény-időpontokban mintavételezve, valódi címkékkel |
| Onset F1 @50 ms | 67,391% | **érvényes** — a `.strums` onsetek valódi ground-truth |
| **BPM MAE** | **45,067 BPM** | **ÉRVÉNYTELEN — visszavonandó** |

### Miért érvénytelen a BPM-szám (mérve 2026-08-09, a riport saját adataiból)

Az ADR 0199 Döntés 6 a BPM ground-truth-ot így definiálta:
`60 / medián pozitív ground-truth inter-onset intervallum`, és **kimondta** a
feltételezést, hogy „a pengetések egyenletes rácson ülnek". A kör azonban
**soha nem validálta ezt a feltételezést** — és a feltételezés hamis.

**1. mérés — a származtatott ground truth önmagában implauzibilis.**
A 82 felvétel `.strums` fájljaiból számolva:

| Statisztika | Származtatott BPM |
|---|---|
| medián | **161,5** |
| p25 / p75 | 103,4 / 198,8 |
| min / max | 49,7 / **369,1** |
| 200 BPM felett | **20 felvétel** |

Pengetett akusztikus gitárgyakorlás **nem 369 BPM-en zajlik**. A `.strums`
események **nem ütemek, hanem pengetések** — a korpuszban 7228 lefelé és 4539
felfelé irányuló pengetés van, ami tipikus nyolcad-alapú le-fel mintázatra
utal. A „ground truth" tehát nem tempót mér, hanem **pengetés-sűrűséget**.

**2. mérés — a DSP ugyanazt a rossz metrikai szintet követi.**
A riport felvételenkénti adataiból a `predictedBpm / groundTruthBpm` arány:

| Statisztika | Arány |
|---|---|
| medián | **1,028** |
| p25 / p75 | 0,889 / 1,276 |
| min / max | 0,515 / 3,657 |

A medián ~1,0: a DSP nagyjából ugyanoda áll be, mint a származtatott „ground
truth". Vagyis **a 45,067 BPM MAE nem a DSP tempó-hibáját méri, hanem két
pengetés-sűrűség-becslés egyezetlenségét** — egyik sem validált tempó.

**3. mérés — még metrikai-szint toleranciával sem jó.**
±4% tűréssel, a szokásos MIR-gyakorlat szerint az 1/3, 1/2, 2/3, 1, 3/2, 2, 3
szorzókat elfogadva:

| Egyezés | Felvétel | Arány |
|---|---|---|
| szigorú (±4%) | 15/82 | 18,3% |
| metrikai-szint toleráns (±4%) | 22/82 | 26,8% |

Tehát a szám még akkor sem menthető, ha az oktáv-hibákat megbocsátjuk — de ez
sem a DSP ellen szól, mert a referencia maga sem tempó.

**Ez orchesztrátor-hiba, nem implementer-hiba.** A GOV-06 implementere pontosan
azt építette, amit az ADR 0199 Döntés 6 és a brief §5.6 előírt, és a
feltételezést a riportban is kimondta. A hiba a mércében volt.

## Döntés

### Döntés 1 — A 45,067 BPM-szám visszavonva

A `docs/eval/real-audio-dsp-baseline.md` BPM-szakasza **átírandó**: a szám
visszavonva, mint nem interpretálható, a fenti három méréssel indokolva. A
szám **nem törlendő** — visszavont értékként, a visszavonás okával együtt
marad benne, mert a törlés elfedné, hogy egyszer állítottuk.

**Tilos** a 45,067-et úgy hagyni, mintha a DSP tempó-hibája lenne, és tilos
egy „javított" számmal csendben lecserélni magyarázat nélkül.

### Döntés 2 — Független tempó-referencia, nem ugyanabból az eseménylistából

Az új BPM ground truth **nem származhat a `.strums` eseményekből** — az volt
az eredeti hiba. A referencia egy **független beat-tracker**: librosa
(`~/audio-venv`, mérve elérhető: librosa 0.11.0, numpy 1.26.4), a repó
bevett gyakorlata szerint (`ml/chords/eval_real_sessions.py` már ma is
librosa-referenciát használ közelítő ground-truth-ként).

A referencia **közelítő, és annak is kell látszania**: a riport mondja ki,
hogy egy beat-tracker becslés, nem kézzel annotált igazság.

### Döntés 3 — Három szám, nem egy

A BPM-szakasz ezentúl **mindhármat** közli:

1. **szigorú egyezés** (±4% tűrés) a független referenciához;
2. **metrikai-szint toleráns egyezés** (1/3, 1/2, 2/3, 1, 3/2, 2, 3 szorzók,
   ±4%) — MIR-szokvány, mert a tempó-oktávhiba más hibaosztály, mint a
   „teljesen mellé";
3. **a pengetés-sűrűség egyezés** (a régi, `.strums`-alapú szám) —
   **kifejezetten NEM tempóként címkézve**, hanem annak, ami: a DSP
   onset-sűrűség-becslésének egyezése a ground-truth pengetés-sűrűséggel.

Egyetlen aggregált BPM-szám önmagában **nem elfogadható kimenet** — ugyanaz a
szabály, amit az ADR 0199 Döntés 4 az akkord-pontosságra kimondott.

### Döntés 4 — Ha a referencia sem megbízható, azt is ki kell mondani

Ha a librosa-referencia és a származtatott pengetés-sűrűség egymásnak
ellentmond olyan mértékben, hogy a tempó a korpuszon **nem mérhető**, akkor a
riport helyes kimenete: **„a BPM ezen a korpuszon nem mérhető, mert nincs
validált tempó-annotáció"**, a szükséges lépés megnevezésével (kézi
tempó-annotáció egy részhalmazon).

Ez **érvényes kimenet**, nem kudarc. Egy megbízhatatlan szám rosszabb, mint a
hiánya — az Epic 6 tempó-görbe és timing-rétege épp erre épülne.

### Döntés 5 — Az akkord- és onset-szám NEM változik

Azok a ground-truth `.strums` eseményekre épülnek, ahol az esemény MAGA a
ground truth — nincs metrikai-szint feltételezés. A kör hozzájuk **nem nyúl**,
és nem futtatja újra őket. Ha a re-run mégis eltérő számot adna, az önmagában
lelet (nem determinisztikus mérés).

### Döntés 6 — A DSP továbbra sem változik

Mérési javító kör. Az ADR 0199 Döntés 7 érvényben: a `lib/` alatt nulla
változás. A tempó-becslés esetleges javítása külön, KÉSŐBBI kör, és csak
azután, hogy van érvényes mércénk.

## Következmények

**Pozitív**

- Az Epic 6 nem egy értelmezhetetlen tempó-számra épül.
- A metrikai-szint toleráns bontás megmutatja, hogy a DSP tempó-hibája
  oktáv-jellegű-e (javítható heurisztikával) vagy szórt (mélyebb probléma).
- Rögzül a tanulság: **kimondott feltételezés nem validált feltételezés.**

**Negatív / kockázat**

- A librosa-referencia maga is közelítő; a számok noisy-k maradnak.
- A librosa a `~/audio-venv`-ben él, ami **nincs verziókövetve** — ugyanaz a
  reprodukálhatósági korlát, mint a korpusznál (ADR 0199 Döntés 8). A
  riportnak ezt is ki kell mondania.
- Lehet, hogy a helyes kimenet a „nem mérhető" (Döntés 4). Ezt előre
  elfogadjuk.
