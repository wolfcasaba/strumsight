# ADR 0541 — Chord release-kapu sorok, a chord-sáv rolloutja és a nem ábrázolható kapuk

**Státusz:** elfogadva (2026-09-09) · **Kör:** E14-R33 · **Épít rá:** ADR 0537 (fokozatok és clamp), ADR 0511 (fail-closed kapu), ADR 0521 (sávos false-visible ráták)

## Kontextus (mért)

- A kapu-fájl három chord-sort hordoz (weighted accuracy 0,80 · macro-F1 0,70
  · N.C./unknown F1 0,88). A Ch14 §7.4 további három sort kér (leggyengébb
  támogatott chord recall 0,55 · confirmed chord accepted accuracy 0,88 ·
  chord transition p50 ≤ 350 ms · false confident chord ≤ 2/perc), a §7.5
  pedig a Beta célokat.
- A metrika-készletben **van** `falseVisibleChordEventsPerMinute` (ADR 0521
  D1) és **van** per-label chord blokk a `chordMacroF1`-ben — a „leggyengébb
  támogatott chord recall” tehát új mérés nélkül **származtatható**.
- **Nincs** viszont `confirmed`-re szűkített accepted accuracy és nincs
  chord-transition latency metrika.
- A baseline chord accuracy 0,671 — a kapu ma is piros.

## Döntés

### D1 — A §7.5 Beta chord-sorok bekerülnek, MIND letiltva

Öt sor `stage: "beta"`, `band: "chord"`, `enabled: false`: weighted accuracy
≥ 0,86 · macro-F1 ≥ 0,78 · N.C./unknown F1 ≥ 0,92 · leggyengébb támogatott
recall ≥ 0,65 · false confident chord ≤ 1/perc. Informatívak (ADR 0537 D3):
sem nem buktatnak, sem nem engedélyeznek.

### D2 — Új, SZÁRMAZTATOTT metrika-út: `chordMacroF1.weakestSupportedRecall`

A `chordMacroF1.perLabel` blokkból a minimum recall, kihagyva (a) a
fenntartott `noChord`/`unknown` címkéket — ezeket a saját metrikájuk pontozza
—, és (b) a nulla supportú osztályokat: egy nem szereplő akkord nem
„0 recall”, hanem nincs róla mérés. Ha egyetlen támogatott osztálynak sincs
supportja, az érték `null`, tehát a kapu **fail-closed**.

### D3 — A §7.4 két újonnan ábrázolható Alpha sora MOST NEM kerül be

A leggyengébb recall (0,55) és a false confident chord (≤ 2/perc) mostantól
ábrázolható lenne, de hozzáadásuk **megváltoztatná az élő Alpha kaput**. Ezt
a kör szándékosan nem teszi meg (ADR 0537 D2: az Alpha sorok változatlanok);
a hozzáadás a legközelebbi chord-mérési kör első teendője, ott, ahol a
korpusz is megjelenik.

### D4 — Ami nem ábrázolható, az NEM kap hamis metrika-utat

Nincs kapu-sor a „confirmed chord accepted accuracy”-ra, a „chord transition
p50/p95”-re és az „event finalization flip”-re, mert egyik mögött sincs
metrika a `recognition_metrics.dart`-ban. Egy nem létező `metricPath` a
kapuban tipizált hiba (ADR 0511), és egy közelítő út (pl. a verdikt-latency
odabiggyesztése a chord-transition helyére) pontosan a „confidently wrong”
osztály lenne. A hiány dokumentált:
`docs/eval/release-gate-stages.md` §4.

### D5 — A chord-rollout ugyanazon a clampen megy át

`clampRolloutStage(band: RecognitionGateBand.chord, …)`
(`rollout_licence.dart`) a `chord` és a `shared` sorokat nézi. Ebből következik, hogy a strum-sáv bukása (pl. onset
F1) **nem** fogja a chord-rolloutot, de minden megosztott sor (accepted
accuracy, coverage, latency, false visible event) igen. A mező neve `chordModelRolloutStage`
(`FeatureFlags`, PKG-D tulajdona; itt csak név), a létra pedig a PKG-D-oldali
`RecognitionRolloutStage` (`off → shadow → alpha → beta → ga`).

### D6 — A legacy NNLS út egy release-ig marad

A chord-CRNN élő bekötése (E14-R26) shadow-ágon történik, és amíg a
chord-sáv effektív rollout-fokozata `off` vagy `shadow`, a felhasználó a
legacy NNLS eredményét látja. A visszaváltás tehát nem igényel új release-t: a
rollout-zászló levétele elég.

## Ami MÉRVE van és ami NINCS

**Mérve:** a Beta chord-sorok jelenléte és letiltottsága, a származtatott
recall-út viselkedése (fenntartott címkék és nulla support kihagyása,
`null` → FAIL), a chord-sáv clampjének band-szűrése.

**NINCS mérve:** minden chord-szám a valós korpuszon; a device-mátrix; a
rollback-gyakorlat. A §7.4 Alpha chord-kapu ma **piros** (0,671 < 0,80), és
ez a kör ezen nem változtatott.
