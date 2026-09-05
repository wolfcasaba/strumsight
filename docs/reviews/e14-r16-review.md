# E14-R16 review — Onset-detektor variáns-szeám és A/B mérés (ADR 0524)

- **Reviewer:** Claude (Opus 5), orchestrátor — read-only review, izolált klónban
  (`/tmp/rev-e14-r16`, a kör-ág `0ff08ead` HEAD-jéről)
- **Implementer:** `sonnet-impl` (Claude Sonnet 5)
- **Dátum:** 2026-09-05
- **Diff:** 5 fájl, +1665 sor (`git diff --stat d03b5aac..0ff08ead`)
- **Scope-audit:** `scope_audit=ok` (5 változott fájl, mind az `allowed_paths`-on)

## 1. Amit ELLENŐRIZTEM (mért, nem bemondás)

| Ellenőrzés | Eredmény |
|---|---|
| `tools/round-gate.sh test/tooling/onset_ab_benchmark_test.dart` izolált klónban | `format`, `analyze`, a célzott teszt (**9/9 PASS**), `architecture`, `secrets`, `l10n`, backend `ruff`/`pytest` — **ZÖLD** |
| production konstansok mozdultak-e | **NEM**: a diff 5 fájlja között `superflux_onset_detector.dart` és `dsp_config.dart` **nincs** (`git diff --stat`) |
| a pontozás delegált-e | **IGEN**: `scoreCases` az egyetlen pontozó belépő, `computeRecognitionMetrics`-et hív; a fájl nem deklarál tűrést, párosítást, P/R/F1-et (`grep`-elve: nincs saját `tolerance`-konstans, nincs párosító hurok) |
| a `current` a szállított detektor-e | **IGEN**: `_CurrentVariant` a `SuperFluxOnsetDetector`-t példányosítja és delegál; a 2. acceptance-cella elemre azonos onset-listát mér |
| kézi tükör helyessége | a `_PeakPicker.confirm` sorról sorra egyezik a szállított `processFrame` megerősítő állapotgépével (medián-ablak, `_postFrames` local-max, `_peakRatio*_fluxPeak`, min-IOI, release-hiszterézis, history-trim `_dropped`-del, visszatérés `absC * hop / sampleRate`) |
| gate-alak | a burkoló `gate_shape=VIOLATION`-t jelzett (a naplóban csővezetékes gate-hívás szerepel) → **ezért futtattam újra magam**, izolált klónban, csonkítatlanul |

## 2. Leletek

### MAJOR-1 — a négy variáns EGYETLEN abszolút `delta`-val fut, így a keresztvariáns pontosság-összevetés skála-konfundált; a doksi mégis „melyik flux-definíció teljesít jobban"-ként írja le

**A mérés** (eldobható review-próba a kör-ágon, `test/tooling/zz_probe_scale_test.dart`,
NEM commitolva; ugyanaz a szintetikus 4-strum minta minden variánsnak):

```
PROBE current:              expected 4 strums, detected 4
PROBE canonicalSuperFlux24: expected 4 strums, detected 7
PROBE complexDomain:        expected 4 strums, detected 10
PROBE spectralFlux:         expected 4 strums, detected 15
```

A bemenet **0,1-szeresére halkítva** (−20 dB) ugyanaz a mérés:

```
PROBE(-20 dB) current:              4     (változatlan)
PROBE(-20 dB) canonicalSuperFlux24: 14    (7 → 14)
PROBE(-20 dB) complexDomain:        5     (10 → 5)
PROBE(-20 dB) spectralFlux:         3     (15 → 3)
```

**Miért lelet.** A `_PeakPicker` küszöbe `delta + lambda * median(flux)`, és a
`delta = 12,0` a szállított detektor **log-power** flux-egységeiben értelmezett
konstans (a szállított fájl doc-commentje kifejezetten erre hivatkozik: „log
difference is a power ratio", ezért amplitúdó-invariáns). A `spectralFlux` és a
`complexDomain` viszont **lineáris magnitúdó** egységekben számol, a
`canonicalSuperFlux24` pedig ~200 sávon összegez 64 helyett — ugyanaz az
abszolút `delta` tehát mindegyiknél MÁS szigorúságot jelent, és a fenti mérés
szerint a detektálás-szám a bemenet erősítésétől is függ. Egy valós korpuszon
kapott F1-sor emiatt NEM az ODF minőségét méri, hanem a küszöb–skála
illesztetlenséget.

**Miért MAJOR és nem NOTE.** A `docs/eval/onset-detector-ab.md` „Korlátok"
szakasza ma ezt írja: *„ez SZÁNDÉKOS: az A/B azt méri, hogy a MEGLÉVŐ hangolás
mellett melyik flux-definíció teljesít jobban"* — ez pontosan az a nem
validált értelmezés, amit a GOV-06b/`L173` osztály tilt: a szám a definíciója
nélkül félrevezet, és a következő kör ebből ADR-t írna („a SuperFlux mérhetően
jobb, mint az egyszerű flux"), miközben a mérés ezt nem bizonyítja.

**Amit kérek (mind az `allowed_paths`-on belül):**

1. a determinisztikus riport variánsonként hordozza az **ODF-skála
   diagnosztikáját** (a variáns fluxának mediánja és p95-e a teljes
   esethalmazon, plusz az effektív küszöb mediánja) — a konfundot MÉRNI kell,
   nem csak leírni;
2. **gépi cella** a fenti mérésre: ugyanaz a jel 0,1-szeresére halkítva a
   `current` detektálás-számát változatlanul hagyja, míg legalább egy ÚJ
   variánsét megváltoztatja → a harness saját, reprodukálható bizonyítéka a
   gain-függésre (a review eldobható próbája ezzel állandó őrré válik);
3. a `docs/eval/onset-detector-ab.md` mondja ki **mérve**, hogy a
   keresztvariáns pontosság-összevetés a skála-illesztett küszöb megszületéséig
   **NEM érvényes** — a fenti számokkal együtt —, és hogy a skála-illesztés egy
   KÉSŐBBI kör döntése (ADR 0524 D8).

Az ADR 0524-be a **D8** döntést a review-val egy menetben felvettem (az ADR a
kör saját, még nem merge-elt artefaktuma, az orchestrátor hatásköre — ADR 0087
§2).

### MINOR-1 — a `_PeakPicker.confirm` doc-commentje ROSSZ képletet állít

`onset_detector_variant.dart:180-182`: „returns the confirmed onset time
(seconds, `(frameIndex * hop + window) / sampleRate` referenced to the PEAK
frame…)", a kód viszont `absC * hop / sampleRate`-et ad vissza (helyesen — a
szállított detektor keret-KEZDET konvenciója). A `+ window` a *döntés*
pillanatának képlete (a benchmark késleltetés-számítása), nem a visszatérési
értéké. A kör előírása: doc-commentben csak bizonyított állítás.

### MINOR-2 — `microsPerAudioSecond` nulla hosszú korpuszon `0`-t ad, nem „nem mért"-et

`onset_ab_benchmark.dart:272-273`: `audioSeconds == 0 ? 0 : …`. A ház
konvenciója (ADR 0509 D6, és a kör 7. acceptance-pontja) a nulla nevezőre
`null` („nem mért"), sosem kényszerített `0`. A `main()` üres korpuszon
kifejezetten kiír egy riportot, tehát az ág elérhető.

### NOTE-1 — a §7.1 második falszifikációs próbája a TESZT saját segédjét cserélte ki

A handoff 2. próbája nem a benchmark útját rontotta el, hanem a teszt
`cellFor` helperjében szimulált egy exkluzív matchert. Ez a cella érzékenységét
igazolja, a delegálás megkerülhetetlenségét nem — utóbbit viszont a 3.
acceptance-pont (`matchingRule` Kuhn-szöveg) érdemben méri, ezért nem kérek
javítást, csak rögzítem.

### NOTE-2 — az `<stem>.onsets.json` sidecar ÚJ formátum

Indokolt (a `.strums` chord-eseményeket hordoz), dokumentált a doksiban és a
§10-ben. Nincs commitolt korpusz, tehát a formátum első valódi fogyasztója egy
későbbi kör lesz — ott kell majd parszer-cellát kapnia.

## 3. Verdikt (1. forduló)

**CHANGES REQUESTED** — 1 MAJOR (skála-konfundált összevetés + nem validált
értelmezés a doksiban), 2 MINOR. A gate és a scope zöld, a kör architektúrája
(delegált pontozás, érintetlen production út, két kimeneti csatorna) helyes.

## 4. Verdikt (2. forduló — a javító kör után, `7e7cecf8`)

Leletenként ellenőrizve:

| Lelet | Zárás | Mérve |
|---|---|---|
| **MAJOR-1** | **ZÁRVA** | (a) `OnsetDetectorVariant.lastFlux` + `OnsetOdfScaleDiagnostics` (`fluxMedian`, `fluxP95`, `effectiveThresholdMedian`) a **determinisztikus** riportban, variánsonként (`odfScale` kulcs); (b) **11. cella**: 0,1× bemeneten a `current` detektálás-száma változatlan, legalább egy ÚJ variánsé megváltozik — reláció-alapú, nem darabszám-pinnelt; (c) a `docs/eval/onset-detector-ab.md` „Korlátok" szakasza a nem validált „melyik flux-definíció teljesít jobban" értelmezést **kimondottan visszavonja**, a mért 4/7/10/15 és −20 dB-es 4/14/5/3 táblázattal, és a „Javaslat" 2–3. pontja is skála-illesztés-feltételes lett |
| **MINOR-1** | **ZÁRVA** | a `_PeakPicker.confirm` doc-commentje most `absC * hop / sampleRate`-et (keret-KEZDET) állít, és külön mondja ki, hogy a `+ window`-os képlet a benchmark `decisionMs`-e |
| **MINOR-2** | **ZÁRVA** | `microsPerAudioSecond` `double?`, üres korpuszon `null`; új cella pinneli, hogy a JSON-ban nem jelenik meg `"microsPerAudioSecond": 0` |
| NOTE-1 / NOTE-2 | rögzítve | nem igényelt javítást |

A 7. cella szűkítése (a `0.0000`-tiltás mostantól a P/R/F1 **táblázatsorokra**
vonatkozik, nem az egész Markdownra) **nem** mércegyengítés: a csendre mért
flux-medián valódi, mért nulla, nem definiálatlan arány — az ADR 0509 D6 a
nulla nevezőjű arányokat védi, és azokat a cella változatlanul `null`-ként
követeli.

**Mért kapuk a javító kör HEAD-jén (`7e7cecf8`):**

- `tools/round-gate.sh test/tooling/onset_ab_benchmark_test.dart` **friss,
  izolált klónban** (`/tmp/rev2-e14-r16`): `format`, `analyze`, a célzott
  teszt (**12/12 PASS**), `architecture`, `secrets`, `l10n`, backend
  `ruff format`/`ruff check`/`pytest` — **MINDEN GATE ZÖLD** (`gate_exit=0`);
- `full-gate.yml` run `33969923831` → `conclusion=success`, `headSha=7e7cecf8`;
- `router-ci.yml` → `success`, `headSha=7e7cecf8`;
- scope-audit: `ok` (5 fájl, mind az `allowed_paths`-on); `gate_shape=ok`.

### VÉGSŐ DÖNTÉS: APPROVED

Nyitott BLOCKER/MAJOR/MINOR nincs. A merge a `main` elmozdulása miatt
rebase-elt HEAD-en, ÚJRA dispatch-elt exact-SHA CI-vel történik (ADR 0086 §2).
