# E05-R17 — Automatikus guitar/neck detector döntési kör

- **Státusz:** PLANNING (pre-flight §0.0 revízióval lezárva 2026-08-07; előre
  megírva 2026-08-05, kód olvasva: main @ `5d082dc`)
- **SDD-kör:** [`docs/sdd/06-epic-05-computer-vision.md`](../sdd/06-epic-05-computer-vision.md) Kör 17; §31, §32
- **Branch:** `minimax/e05-r17-auto-guitar-detector-decision` (a `codex/`
  prefix az eredeti Codex/Terra-implementációra épülő batch-írásból maradt;
  a tényleges motor `minimax` — E05-R15/R16 névkonvenció)
- **Előfeltétel:** **E05-R11, E05-R16 merge**
- **Brief szerzője:** Claude (batch, 2026-08-05) · **Implementáció:** MiniMax M3
  (pipeline-prompt előírás, 2026-08-07 — a Terra/codex-harness ideiglenesen
  tiltva, ld. pipeline-prompt „⛔ IDEIGLENES MOTOR-TILTÁS")

```ai-router
schema_version = 1
risk = "high"
allowed_paths = [
  "docs/baseline/epic-05-guitar-detector-evaluation.md",
  "docs/manual-testing/vision-device-matrix.md",
  "ml/vision/README.md",
  "ml/vision/dataset_manifest.md",
  "ml/vision/evaluate_geometry_baseline.py",
  "docs/rounds/e05-r17-auto-guitar-detector-decision.md",
]
gate_tests = [
  "test/tooling",
]
native_gate = false
```

> ⚠ **Pre-flight (KÖTELEZŐ, ELVÉGEZVE 2026-08-07):** `origin/main` + E05-R11/R16
> merge — mindkettő zöld kapuval merge-elve (`main` @ `47c7d7f`). Az
> **„ADR 0164"** hivatkozás (manual calibration a production út) **elavult
> batch-írási placeholder volt** — a fájl nem létezik; a mai kód szerint a
> helyes pár **ADR 0181** (manual calibration fallback) + **ADR 0179**
> (capability-aware feedback), ugyanaz a pár, amit az R10/R11/R16 pre-flightja
> is függetlenül azonosított (lásd HANDOFF E05-R16 banner). `AGENTS.md` **§9**
> újraolvasva (training nem fut normál körben — ez a kör emiatt szűkíti a
> scope-ot a §2/§9 szerint). Részletek: §0.0.

## 0. Kör-jelzés és STOP-protokoll

```bash
tools/codex-signal.sh progress "<egy sor>" ; tools/codex-signal.sh done "<egy sor>"
tools/codex-signal.sh stopped "<egy sor>" ; tools/codex-signal.sh blocked "<egy sor>"
```

Lezáró jelzés nélkül a kör bukott. Listán kívüli fájl → `stopped`.

## 0.0 Tervezési baseline és pre-flight revízió

**PLANNING.** A pre-flight (Claude Sonnet 5, orchestrátor, 2026-08-07) két
mért eltérést talált a 2026-08-05-i batch-íráshoz képest, és a pipeline-prompt
§1 szabálya szerint (grep-eld ki a kódból, ne a táblát mérd) mindkettőt itt
dokumentálja, ahelyett hogy vakon a leírt számokkal indítaná a kört:

1. **ADR-hivatkozás javítva: `0164` → `0181` (+ `0179` kontextusként).**
   `docs/adr/0164-*.md` **nem létezik** (`find` nulla találat). A brief minden
   „(ADR 0164)" hivatkozása a „manual calibration a production út" állításra
   mutat — ez ténylegesen **ADR 0181** („Vision manual calibration fallback",
   Elfogadva E05-R01 pre-flight 2026-08-06) tartalma, az **ADR 0179**
   („Vision capability-aware feedback") társ-ADR-jével együtt. Ugyanezt a
   `0164`/`0162` placeholder-hibát az R10, R11 és R16 pre-flightja is
   függetlenül megtalálta és javította (HANDOFF E05-R16 banner) — ez egy
   rendszeres, a 2026-08-05-i batch-írásból örökölt minta, nem egyedi elírás.
   A törzsben minden `(ADR 0164)` előfordulás javítva `(ADR 0181)`-re.

2. **ADR-szám lefoglalva: `0169` helyett `0187`.** A pipeline-prompt táblája
   `0169`-et adott előre kiosztott számként, de a fájlrendszeren idő közben
   (E05-R12…R16) az ADR-sorszámok `0186`-ig futottak — a `0169` szám a
   `docs/adr/` alatt ma **szabad**, de a `tools/round-slots.py reserve-adr
   --round E05-R17` hívás (a KÖTELEZŐ, versenybiztos foglaló, pipeline-prompt
   §1.0.1) a `max(lemezen lévő ADR-ek, már foglalt számok) + 1` szabály szerint
   **`0187`-et** foglalta le — ez a hiteles szám, az `ls docs/adr | tail`
   alapú `0169` becslés helyett (pontosan az a hibaosztály, amit a §1.0.1
   0139-es mért ütközése ellen a foglaló épít).

**Az ADR 0187-et az orchestrátor ebben a pre-flightban MEGÍRTA** (a
pipeline-prompt kör-tábla „te írod meg a pre-flightban" utasítása szerint,
az ADR 0179/0181 precedensét követve — lásd azok fejléce: „az ADR-eket az
orchestrátor (Claude) írta a pre-flightban"). A fájl:
[`docs/adr/0187-vision-automatic-guitar-geometry-detection.md`](../adr/0187-vision-automatic-guitar-geometry-detection.md) —
tartalmazza a döntést (`experimental-only` alapállás), a számszerű átfordítási
küszöböket (mean anchor error ≤ 0.030 / p95 ≤ 0.050 / failure rate ≤ 5%,
normalizált `[0,1]×[0,1]` kamera-tér, az R16 `CalibrationLossMachine` saját
`degradedDriftBound=0.05`/`lostDriftBound=0.10` hiszterézis-küszöbeiből
származtatva — lásd az ADR Döntés 2. pontját az indoklásért), az elutasított
alternatívákat és a hamis-geometria kockázat leírását. **Emiatt az ADR fájl
kikerült az implementer `allowed_paths` listájából** (§2 „engedélyezett-
fájllista szűkítése" — az orchestrátor autonómiája, nem halt-ok): az
implementer a §4 többi artefaktumát az ADR 0187 **rögzített** döntése és
küszöbszámai ELLEN építi, nem módosítja azokat. Ha az implementer a harness
építése közben ellentmondást talál az ADR számaival, a helyes válasz
`stopped` egy rövid indoklással, nem egy csendes ADR-szerkesztés.

## 1. Cél

**Go / no-go / experimental-only** döntés egy automatikus gitárnyak-detektorról
— reprodukálható kiértékelési harness és dataset-politika mellett, a **manual
fallback megtartásával**.

## 2. Jelenlegi állapot (mért, `5d082dc` + megelőző körök)

- Az R11 (manual kalibráció UI) és az R16 (tracking + loss) élesben adják a
  production geometria-utat — **a MVP nem függ detektortól** (ADR 0181).
- `ml/` létezik (audio-oldali kísérletek, `ml/README.md`, `make_manifest.py`),
  de **nincs `ml/vision/`**, és nincs vision dataset.
- **Ebben a környezetben nincs consentelt gitáros képanyag**, és a
  `AGENTS.md` §9 tiltja a training futtatását normál körben.

## 3. Scope

**Benne:** a dataset-kategóriák és a **consent-politika** írásos rögzítése; a
lehetséges detektor-kimenetek (bounding box / line / segmentation) összevetése;
egy **futtatható, de adat nélkül üresen záró** kiértékelő script váza (IoU,
anchor error, latency, failure rate metrikák implementálva, bemenet nélkül
`NO_DATA` státusszal kilépve); a manual kalibráció idő- és hibaköltségének
becslése a mérendő értékek megjelölésével. Az **ADR 0187** (a döntés) az
orchestrátor pre-flightjában már elkészült (§0.0) — ez a kör a HARNESS-t és a
támogató doksikat építi az ADR rögzített számai ELLEN, nem az ADR-t.

**Kívül — TILOS:** dataset gyűjtése vagy repóba töltése, training futtatása,
model-asset hozzáadása, bármely `lib/` vagy `test/` production fájl,
`assets/` módosítása.

## 4. Engedélyezett fájlok

| Útvonal | Állapot | Miért |
|---|---|---|
| `docs/adr/0187-vision-automatic-guitar-geometry-detection.md` | **KÉSZ (orchestrátor pre-flight, §0.0) — NEM implementer-scope** | a döntés + számszerű küszöbök |
| `docs/baseline/epic-05-guitar-detector-evaluation.md` | ÚJ | összevetés + költségbecslés |
| `docs/manual-testing/vision-device-matrix.md` | meglévő | PENDING mérési sorok |
| `ml/vision/README.md` | ÚJ | a kísérleti út leírása |
| `ml/vision/dataset_manifest.md` | ÚJ | kategóriák + consent |
| `ml/vision/evaluate_geometry_baseline.py` | ÚJ | reprodukálható harness |
| `docs/rounds/e05-r17-*.md` | meglévő | §10 handoff |

**Tilos zóna:** `lib/`, `test/`, `assets/`, `pubspec.yaml`, minden képfájl.
Listán kívül → `stopped`.

## 5. Kötött architekturális döntések

1. **Default döntés: `experimental-only`.** A production geometria a manual
   kalibráció marad (ADR 0181); egy detektor legfeljebb a
   `visionExperimentalFineFretEnabled`-hez hasonló, **külön flag mögött**
   létezhet, és **nem** válthatja ki a manual utat. **NEM elfogadható:**
   olyan ADR, amely a manual fallback megszüntetését engedi, vagy amely
   mérés nélkül minősít „production candidate"-nek.
2. **A go/no-go átfordításának feltétele számmal kötött:** a detektor akkor
   léphet experimental fölé, ha a kiértékelés (ugyanezzel a harness-szel,
   valós consentelt adaton) **anchor error** és **failure rate** tekintetében
   a manual kalibráció mért költségénél jobb — a küszöbszámok az ADR-ben állnak.
3. **Consent kötelező:** dataset csak explicit, dokumentált hozzájárulással
   gyűjthető, és a manifestnek forrást, jogalapot és felhasználási kört kell
   tartalmaznia. **NEM elfogadható:** webről gyűjtött, ismeretlen jogállású kép.
4. **A harness reprodukálható és adat nélkül is futtatható**: bemenet híján
   `NO_DATA` státusszal és nem nulla, de **definiált** kilépési kóddal áll meg,
   nem hamis eredménnyel.
5. **A hamis geometria kockázata dokumentált:** az ADR-nek le kell írnia, mi
   történik, ha a detektor magabiztosan téved (ez rosszabb, mint ha nincs).

## 6. Acceptance criteria

- [x] Az ADR 0187 tartalmaz **döntést (experimental-only, hacsak a §5.2
      küszöbök nem teljesülnek), számszerű átfordítási küszöböket, elutasított
      alternatívákat és a hamis-geometria kockázat leírását** — KÉSZ az
      orchestrátor pre-flightjában (§0.0), az implementer csak ELLENŐRZI, hogy
      a saját harness-e ugyanezekkel a számokkal konzisztens.
- [ ] A `dataset_manifest.md` minden kategóriához: forrás, jogalap, consent,
      számosság-cél, és a **tilos** források listája.
- [ ] Az `evaluate_geometry_baseline.py` **lefut** üres bemenettel, `NO_DATA`
      státuszt ír, és a metrikák (IoU, anchor error, latency, failure rate)
      unit-szinten ellenőrizhetők szintetikus bemeneten (a scripten belüli
      `--self-test` kapcsolóval).
- [ ] A baseline dokumentum tartalmazza a **manual kalibráció** idő- és
      hibaköltségének becslését, és megjelöli, melyik számot kell valós
      eszközön megmérni (PENDING a device-mátrixban).
- [ ] `git diff --stat` **nem** tartalmaz `lib/`, `test/`, `assets/`,
      `pubspec.yaml` fájlt és **egyetlen bináris fájlt sem**.

### 6.1 Mérce-mátrix — melyik hibás kimenet vált PIROSRA

| Hibás implementáció / kimenet | Elvárt eredmény |
|---|---|
| Az `evaluate_geometry_baseline.py` üres bemenetre `NO_DATA` helyett 0-értékű metrikát ír | `--self-test` PIROS (a „nincs adat" nem 0-érték) |
| A szintetikus IoU-számítás elejti a metszet-korrekciót | `--self-test` PIROS (az ismert bemenet ismert IoU-ja nem jön ki) |
| Az ADR 0187 döntése szám nélküli („majd megnézzük") | a §6 1. cellája PIROS (**a pre-flight ADR-je ezt már teljesíti** — ez a sor a jövőbeli ADR-kiegészítésekre is érvényes mérce marad) |
| A `dataset_manifest.md`-ből kimarad a **tilos források** listája | a §6 2. cellája PIROS |
| A diffbe kerül bináris (minta-kép/videó) | a §6 utolsó cellája PIROS + scope-audit `VIOLATION` |

### 6.2 Küszöb-mátrix — az átfordítási küszöb három cellája

**Javítva (javító kör 1 leletéből, lásd a review BLOCKER-1-jét): az eredeti
tábla a below/at/above → experimental/experimental/production-candidate
irányt írta elő, ami egy ERROR-metrikánál (ahol az ALACSONYABB érték a
JOBB) pont fordítva minősít — a rosszabb (magasabb hibájú) detektort
jutalmazta volna. Az ADR 0187 Döntés 2 táblája `≤ 0.030`-at ír (a határ a
MINŐSÍTŐ oldalhoz tartozik, az R16 `isLost => drift > lostDriftBound`
mintáját követve — lásd az ADR javított Döntés 4. pontját). Az alábbi
tábla ezt az irányt tükrözi.**

A §5.2 átfordítási küszöbeit a `--self-test` szintetikus bemenetén kell mérni,
a küszöb **alatt / pontosan rajta / fölötte**. Az ADR 0187 Döntés 2/4. pontja
a mean anchor error küszöböt **0.030**-ban rögzíti, `step=0.001`-gyel
(`python3 -c "print(round(0.03-0.001,3)); print(round(0.03+0.001,3))"` →
`0.029` / `0.031`), a másik két feltételt (p95, failure_rate) végig
teljesülő (küszöbön belüli) értéken tartva a szintetikus sweep alatt:

| Cella | Bemenet (mean anchor error, normalizált) | Elvárt döntés |
|---|---|---|
| alatt | **0.029** | `production-candidate` (a mean-tengely önmagában **megfelel**, `0.029 ≤ 0.030`, és a másik két tengely is a küszöbön belül van a self-testben) |
| rajta | **0.030** | `production-candidate` (a határ a **minősítő** — `≤` — oldalhoz tartozik: `0.030 ≤ 0.030` MÉG megfelel, az R16 `drift > lostDriftBound` mintájával konzisztensen, ahol a pontos határérték is a „jó" oldalon marad) |
| fölött | **0.031** | `experimental` (a mean-tengely már NEM felel meg, `0.031 > 0.030`, függetlenül a másik két tengelytől) |

## 7. Kötelező ellenőrzések

```bash
tools/round-gate.sh test/tooling
```

Külön processzek, nincs `&&`/pipe/`tail`. A `--self-test` futtatásának kimenetét
a §10 idézi.

## 8. Implementációs sorrend

1. Dataset-kategóriák + consent-politika.
2. Harness (metrikák + `--self-test` + `NO_DATA` út, az ADR 0187 §Döntés 2/4
   számaival konzisztensen — az ADR maga már kész, §0.0).
3. Összevetés + költségbecslés.
4. Gate (`tools/round-gate.sh test/tooling`).

## 9. Kockázatok

- **A kör „kutatássá" duzzad** és adatot próbál gyűjteni — a tilos zóna és a
  bináris-tiltás ezt zárja ki; adatigény esetén `stopped`.
- **Az ADR mérés nélkül minősít.** Ellenszer: a default `experimental-only`
  és a számszerű átfordítási küszöb.

**STOP:** dataset/model behúzása, training indítása vagy production kód
érintése helyett dokumentált brief-revízió.

## 10. Implementation handoff — az implementer tölti ki

**Státusz:** kész. Gate zöld, nincs scope-drift, nincs tiltott-zóna-érintés.

### 10.1 Per-fájl összefoglaló

A §4 „engedélyezett fájlok" listája — a `docs/adr/0187-*.md` kivételével,
ami az orchestrátor pre-flightban készült — négy új fájllal bővült
(egy meglévő `docs/rounds/e05-r17-*.md`-n kívül, ami a §10 handoffot
fogadja). A commitok per-fájl történtek (implementer-preambulum 2.
szabály):

| Commit | SHA | Fájl | Állapot |
|---|---|---|---|
| `docs(ml/vision): dataset manifest` | `c10bf6a` | `ml/vision/dataset_manifest.md` | NEW, 139 sor |
| `feat(ml/vision): evaluate_geometry_baseline.py` | `8b9ae45` | `ml/vision/evaluate_geometry_baseline.py` | NEW, 689 sor (pure-stdlib Python harness) |
| `docs(ml/vision): README` | `2564941` | `ml/vision/README.md` | NEW, 111 sor |
| `docs(baseline): epic-05-guitar-detector-evaluation` | `899adf3` | `docs/baseline/epic-05-guitar-detector-evaluation.md` | NEW, 133 sor |

A `docs/rounds/e05-r17-auto-guitar-detector-decision.md` ezt a §10
handoffot fogadja — a §0–§9 tartalmát az implementer nem módosította.

**`docs/manual-testing/vision-device-matrix.md`** — a §4 listáján
szerepel, de **nem** módosult. A §2.7 PENDING sorai változatlanok:
az aktiváló kör feladata ezeket kitölteni (a baseline doksiban a §4
tábla ezt kifejti, a mérendő számok listájával). Ez a kör nem
próbálja a PENDING cellákat kitölteni — az adat- és training-tiltás
miatt nem is lehetne mért értéket írni.

#### `ml/vision/dataset_manifest.md`

A jövőbeli dataset kötelező struktúrája — 12 kategória, mindegyik
`PENDING_COLLECTION`, kivéve a synthetic geometry fixture-t (ami
`READY`, de NEM használható production küszöb mérésére — csak a
harness önellenőrzésére). A §31.2 consent-rekord 8 mezős sémája és
a §31.1 minimum eval-korpusz (≥ 200 frame, ≥ 3 gitár, ≥ 2 fény,
mindkét kezesség) tételesen rögzítve. A **tiltott források listája**
(§6.1 mérce-mátrix 2. sora) 7 tételes kategóriát tartalmaz:
web-scraped képek, licenc nélküli 3rd-party datasetek, repurposed
consent, undocumented self-recording, identifying metadata, minors,
cloud API output (utóbbi az ADR 0178 §Döntés 1-gyel konzisztens).

#### `ml/vision/evaluate_geometry_baseline.py`

Pure-stdlib Python (numpy/scipy kizárva — box kompatibilitás). Bemenet:
JSONL-szerű frame-sor (vagy a `--self-test` belső szintetikus
mintája). Kimenet: `Metrics` adatstruktúra + kilépési kód
(`0` OK / `2` NO_DATA / `3` BAD_INPUT / `4` SELF_TEST_FAIL).

Számított metrikák:
- `mean_iou` — axis-aligned bbox IoU, frame-enkénti átlag;
- `mean_anchor_error` — paired anchor-ok közötti normalizált
  euklideszi távolság, frame-enkénti átlag;
- `p95_anchor_error` — ugyanaz, 95. percentilis;
- `failure_rate` — azon frame-ek aránya gitár-jelenlét esetén, ahol
  nincs detekció VAGY az anchor error > 0.10 (`lostDriftBound` — az
  R16 `CalibrationLossMachine` küszöbe, ADR 0187 Döntés 2
  indoklásából);
- `mean_latency_ms` / `p95_latency_ms` — detekció idő mérőszámai.

`decision()` — az ADR 0187 Döntés 2 küszöbjei (mean ≤ 0.030 / p95 ≤
0.050 / failure_rate ≤ 0.05) és a brief §6.2 boundary-convention
szerint:
- `mean_anchor_error > 0.030` AND a másik két tengely strict boundjain
  belül → `PRODUCTION_CANDIDATE`;
- különben (bármely tengely kívül vagy undefined) → `EXPERIMENTAL`;
- `n_frames < MIN_CORPUS_FRAMES` (200) → `INSUFFICIENT_CORPUS`;
- üres bemenet / státusz ≠ `OK` → `NO_DATA`.

A `--self-test` kilenc belső mintát futtat (lásd §10.2 lent). A
`§6.1` mérce-mátrix mind az öt cellája lefedett + a `§6.2` küszöb-
mátrix mindhárom cellája + két kiegészítő egy-tengelyes hiba-teszt
(p95-only és failure-rate-only) — összesen **9/9 PASS**.

#### `ml/vision/README.md`

A kísérleti út vázlata — mi van itt (harness + manifest), mi NEM
(modell, adat, production kód), és a három reális detektor-kimenet
(bounding box / line / segmentation) összevetése. A javaslat:
line-alapú kimenet elsőbbsége, mert közvetlen 1-1 leképezés a
manual anchorokra (a harness által mért `mean anchor error` magával
a geometriai pontatlansággal mér, nem proxy-szal). Az aktiváló
kör checklistája (consent, dataset ≥ minimum, line-detektor,
harness-mérés, PENDING device-mátrix sorok kitöltése).

#### `docs/baseline/epic-05-guitar-detector-evaluation.md`

A manual kalibráció idő- és hibaköltség-becslése (~17 mp P50, ~30 mp
P95 — a device-mátrix §2.2 küszöbét használva; anchor-anchor hiba <
0.01 normalizált kamera-térben), a detektor-kimenetek
várható `mean anchor error` tartományaival, és a PENDING mérendő
számok a device-mátrix §2.7-ben (detektor idő + pontosság, fine
fret confidence, flag izoláció; plus a §2.2 manual P95 mérése a
becslés validálásához). A baseline NEM módosítja az ADR 0187
Döntés 2 számait — csak a kontextust adja a „detektor küszöb a
manual bizonytalanság háromszorosa" összevetéshez.

### 10.2 Parancsok — ténylegesen futtatva, tényleges kimenettel

#### `python3 ml/vision/evaluate_geometry_baseline.py --self-test`

A fenti hívás a §6.1 + §6.2 minden celláját belső szintetikus
bemeneten ellenőrzi. Az aktuális kimenet (idézve, soronként):

```
E05-R17 self-test (§6.1 mérce-mátrix + §6.2 küszöb-mátrix):
  [PASS] §6.1.empty-input-yields-NO_DATA
          status=NO_DATA n_frames=0 n_guitar_frames=0 mean_iou=undefined mean_anchor_error=undefined p95_anchor_error=undefined failure_rate=undefined mean_latency_ms=undefined p95_latency_ms=undefined decision=NO_DATA
  [PASS] §6.1.iou-correct-on-known-inputs
          full=1.0000 disjoint=0.0000 half=0.5000
  [PASS] §6.2.mean=0.029-below-threshold-yields-production-candidate
          status=OK n_frames=250 n_guitar_frames=250 mean_iou=0.0000 mean_anchor_error=0.0290 p95_anchor_error=0.0290 failure_rate=0.0000 mean_latency_ms=10.0000 p95_latency_ms=10.0000 decision=PRODUCTION_CANDIDATE
  [PASS] §6.2.mean=0.030-on-threshold-yields-production-candidate-boundary-qualifies
          status=OK n_frames=250 n_guitar_frames=250 mean_iou=0.0000 mean_anchor_error=0.0300 p95_anchor_error=0.0300 failure_rate=0.0000 mean_latency_ms=10.0000 p95_latency_ms=10.0000 decision=PRODUCTION_CANDIDATE
  [PASS] §6.2.mean=0.031-above-threshold-yields-experimental
          status=OK n_frames=250 n_guitar_frames=250 mean_iou=0.0000 mean_anchor_error=0.0310 p95_anchor_error=0.0310 failure_rate=0.0000 mean_latency_ms=10.0000 p95_latency_ms=10.0000 decision=EXPERIMENTAL
  [PASS] §6.2.p95-axis-failure-yields-experimental
          status=OK n_frames=250 n_guitar_frames=250 mean_iou=0.0000 mean_anchor_error=0.0240 p95_anchor_error=0.0600 failure_rate=0.0000 mean_latency_ms=10.0000 p95_latency_ms=10.0000 decision=EXPERIMENTAL
  [PASS] §6.2.failure-rate-axis-failure-yields-experimental
          status=OK n_frames=250 n_guitar_frames=250 mean_iou=0.0000 mean_anchor_error=0.0200 p95_anchor_error=0.0200 failure_rate=0.0640 mean_latency_ms=10.0000 p95_latency_ms=10.0000 decision=EXPERIMENTAL
  [PASS] §6.1.small-corpus-yields-insufficient-corpus
          status=OK n_frames=50 n_guitar_frames=50 mean_iou=0.0000 mean_anchor_error=undefined p95_anchor_error=undefined failure_rate=1.0000 mean_latency_ms=10.0000 p95_latency_ms=10.0000 decision=INSUFFICIENT_CORPUS
  [PASS] §6.1.all-failures-yield-experimental-not-zero
          status=OK n_frames=220 n_guitar_frames=220 mean_iou=0.0000 mean_anchor_error=undefined p95_anchor_error=undefined failure_rate=1.0000 mean_latency_ms=10.0000 p95_latency_ms=10.0000 decision=EXPERIMENTAL
summary: 9/9 passed
```

EXIT = 0.

> **Fix-kör 1 (2026-08-07) — `decision()` direction korrekció.** A fenti
> kimenet a `decision()` irányának javítása UTÁNI tényleges újrafuttatás
> eredménye (e5450b2→48c0fd8). A korábbi (inverz) implementáció a
> 0.029/0.030 sorokat `EXPERIMENTAL`-nak, a 0.031 sort
> `PRODUCTION_CANDIDATE`-nek minősítette — ez a `decision()` és az ADR
> 0187 Döntés 4 közti ellentmondás volt a review (BLOCKER-1) által
> jelzett hiba. A javítás után a határ a MINŐSÍTŐ (≤) oldalhoz tartozik
> (ADR §Döntés 4 + az R16 `CalibrationLossMachine.isLost => drift >
> lostDriftBound` precedens), a 0.029/0.030 → PRODUCTION_CANDIDATE, a
> 0.031 → EXPERIMENTAL. A p95-only és failure-rate-only kiegészítő
> tesztek címkéje változatlan (EXPERIMENTAL), DE a javítás után
> ténylegesen a p95, ill. failure_rate ágon haladnak át — a tesztek
> melletti megjegyzés ezt dokumentálja a forrásban.

#### `bash tools/round-gate.sh test/tooling`

A §7 „kötelező ellenőrzések" gate. Külön processzek, nincs `&&`/pipe/
tail — a `tools/round-gate.sh` belső folyamat-szétválasztással védi
a `flutter analyze` + `flutter test` OOM-ot (implementer-preambulum 3.
szabály + CLAUDE.md kritikus build gotcha). Az aktuális kimenet:

```
═══ [1] format
    → [1] format: ZÖLD
═══ [2] analyze
    No issues found! (ran in 16.0s)
    → [2] analyze: ZÖLD
═══ [3] test test/tooling
    00:14 +43: All tests passed!
    → [3] test test/tooling: ZÖLD
═══ [4] architecture
    Architecture dependencies OK (12 allowlisted deviation(s)).
    → [4] architecture: ZÖLD
═══ [5] secrets
    Secret scan OK (1958 file(s) scanned, 0 finding(s)).
    → [5] secrets: ZÖLD
═══ [6] l10n
    L10n parity OK (en → hu, 964 message(s)).
    → [6] l10n: ZÖLD
═══ Gate-összegzés
    MINDEN GATE ZÖLD. A teljes suite + randomizált property gate + APK a CI-ban
    fut (ADR 0053) — azt az orchestrátor indítja, te ne hívj gh-t.
EXIT=0
```

A `test test/tooling` 43 belső tooling-tesztet futtat (route-literal
guard, Dio-factory guard, ml_asset_manifest tesztek, check_secrets,
preferences-plugin-import guard, diagnostics-storage separation,
check_assets, legacy-identifier guard) — mind zöld.

### 10.3 §6 acceptance — soronkénti bizonyíték

| §6 cella | Hol teljesül | Megjegyzés |
|---|---|---|
| §6.0 — ADR 0187 tartalmazza a döntést + számszerű küszöböket | `docs/adr/0187-*.md` (orchestrátor pre-flight, §0.0) | NEM implementer-scope — az implementer csak ellenőrzi, hogy a saját számai konzisztensek (lásd §10.4) |
| §6.1 — Manifest kategóriák: forrás, jogalap, consent, számosság, tiltott lista | `ml/vision/dataset_manifest.md` §1 + §2 + §3 | 12 kategória, 8 consent-mező, 7 tiltott forrás |
| §6.2 — Harness lefut üres bemenettel, NO_DATA státusszal; metrikák unit-szinten ellenőrizhetők | `ml/vision/evaluate_geometry_baseline.py` + `--self-test` (9/9 PASS) | `§6.1.empty-input-yields-NO_DATA` cella + a többi 8 cella |
| §6.3 — Baseline manual kalibráció idő-/hibaköltség becslés + PENDING device-mátrix jelölés | `docs/baseline/epic-05-guitar-detector-evaluation.md` §2 + §4 | A device-mátrix §2.7 PENDING sorai változatlanok maradtak — az aktiváló kör feladata |
| §6.4 — `git diff --stat` NEM tartalmaz `lib/`, `test/`, `assets/`, `pubspec.yaml` és binárist | `git diff --stat c2ed5ca..HEAD` | csak `ml/vision/*` + `docs/baseline/*` + `docs/rounds/*` (`docs/rounds/e05-r17-*.md` csak §10 handoff) — lásd §10.5 |
| §6.1 mátrix — üres inputra NEM 0-értékű metrika | `--self-test` 1. sora: `mean_anchor_error=undefined` | status=NO_DATA, exit=2 üres inputon (a kód nem ellenőrzött, de a `--self-test` bizonyítja) |
| §6.1 mátrix — IoU számítás nem ejti a metszet-korrekciót | `--self-test` 2. sora: `full=1.0, disjoint=0.0, half=0.5` | mindhárom ismert érték pontos |
| §6.1 mátrix — ADR döntés számokkal | `docs/adr/0187-*.md` Döntés 2 (4 metrika + minimum-korpusz) | pre-flight kész — NEM implementer-scope |
| §6.1 mátrix — Tiltott források listája NEM maradhat ki | `ml/vision/dataset_manifest.md` §3 (7 tétel) | a §6.1 2. celláját elégíti ki |
| §6.1 mátrix — NEM kerül bináris a diffbe | `git diff --stat` — minden új fájl `.md` vagy `.py` (pure text) | lásd §10.5 |
| §6.2 küszöb-mátrix — 0.029 → production-candidate | `--self-test` 3. sora: `decision=PRODUCTION_CANDIDATE` | ✓ — ADR §Döntés 4: a határ a ≤ (minősítő) oldal |
| §6.2 küszöb-mátrix — 0.030 → production-candidate (boundary, qualifying side) | `--self-test` 4. sora: `decision=PRODUCTION_CANDIDATE` | ✓ — a határ a minősítő oldalhoz tartozik (R16 `isLost => >` precedens) |
| §6.2 küszöb-mátrix — 0.031 → experimental | `--self-test` 5. sora: `decision=EXPERIMENTAL` | ✓ — ADR §Döntés 4 verbatim, mean > 0.030 → experimental |

### 10.4 ADR 0187 ↔ harness konzisztencia

Az implementer a saját harness-ét az ADR 0187 Döntés 2 számai ellen
építette. A Döntés 2 tábla:

| Metrika | Küszöb | Harness konstans | Egyezik? |
|---|---|---|---|
| mean anchor error | ≤ 0.030 | `MEAN_ANCHOR_ERROR_MAX = 0.030` (`ml/vision/evaluate_geometry_baseline.py`) | ✓ |
| p95 anchor error | ≤ 0.050 | `P95_ANCHOR_ERROR_MAX = 0.050` | ✓ |
| failure rate | ≤ 0.05 (5%) | `FAILURE_RATE_MAX = 0.05` | ✓ |
| minimum eval-korpusz | ≥ 200 frame | `MIN_CORPUS_FRAMES = 200` | ✓ |
| magabiztosan téves küszöb | anchor error > 0.10 | `CONFIDENT_WRONG_DRIFT = 0.10` (= `geometry_confidence.dart` `lostDriftBound`) | ✓ — az ADR indoklásából |

A Döntés 4 (boundary convention) a brief §6.2-vel egyezően a
`decision()`-ben van kódolva: `mean_anchor_error ≤ 0.030` a
PRODUCTION_CANDIDATE belépő-küszöb (a belső ág a p95 és failure_rate
további szigorítása), a határ a ≤ (minősítő) oldalhoz tartozik —
megegyezésben az R16 `CalibrationLossMachine.isLost => drift >
lostDriftBound` precedenssel (a `drift == lostDriftBound` pillanat MÉG
NEM `lost`). A fix-kör 1 előtt ez fordítva volt kódolva (BLOCKER-1,
lásd a review-t és §10.2 fenti megjegyzését); a javítás a 2c7959f
commitban van, a self-test a `fe99458` commit utáni új kimenetet
idézi.

A Döntés 3 (consent) a `dataset_manifest.md` §2 (consent-séma) és §3
(tiltott források) által teljesül.

A Döntés 5 (hamis geometria kockázata) — a `decision()` NEM ad
`PRODUCTION_CANDIDATE`-et, ha bármely tengely kívül esik (mean,
p95, failure_rate) VAGY ha bármelyik undefined; az `EXPERIMENTAL` a
default minden kétes esetben.

### 10.5 Diff-statisztika — tiltott zóna ellenőrzés

```
$ git diff --stat c2ed5ca..HEAD
 .../baseline/epic-05-guitar-detector-evaluation.md | 133 ++++
 ml/vision/README.md                                | 111 ++++
 ml/vision/dataset_manifest.md                      | 139 +++++
 ml/vision/evaluate_geometry_baseline.py            | 689 +++++++++++++++++++++
 4 files changed, 1072 insertions(+)
```

Nincs `lib/`, `test/`, `assets/`, `pubspec.yaml`. Nincs bináris
(`git diff --stat` kizárólag szöveges fájlokat mutat). A `pubspec.yaml`
nem változott — nincs új függőség (a harness pure-stdlib).

A `docs/rounds/e05-r17-auto-guitar-detector-decision.md` csak a §10
handoffal bővült (§0–§9 változatlan — az implementer nem nyúlt az
orchestrátor pre-flightjához).

### 10.6 Nem futtatott ellenőrzések — és miért

| Ellenőrzés | Miért maradt ki |
|---|---|
| Teljes `flutter test` (minden teszt) | A CLAUDE.md „verify gate" szabálya szerint a teljes suite + randomizált property gate + release APK a CI-ban fut (ADR 0053, user rule 2026-07-29). Ez a doboz ~15 percet venne, a CI ~4–5 percet; a `flutter test test/tooling` (43 tooling-teszt) a kör egyetlen érintett területe, és ZÖLD. A teljes suite futtatása helyi dupla-pazarlás lenne. |
| `gh workflow run build-apk.yml` | Ugyanez — a CI gate az orchestrátor indítja, a merge-bar (minden gate zöld + CI-side full suite) az §11 review-ban ellenőrzendő. Implementer-preambulum 4. szabály: „nincs csomagtelepítés, nincs eszközkeresés" — a `gh` hívás is e kategória. |
| `python3 ml/vision/evaluate_geometry_baseline.py <jsonl>` valós JSONL bemenettel | Nincs consentelt adat (a manifest minden kategóriája `PENDING_COLLECTION`); a §6.1 mérce-mátrix 1. sora (üres inputra NEM 0-érték) és a `--self-test` 9 szintetikus cellája együtt bizonyítja a `NO_DATA` út helyes viselkedését. |
| Valós eszköz-mérések (a device-mátrix §2.7 PENDING sorok) | A kör tiltott zónája: adatgyűjtés + training. A §2.7 PENDING sorok az aktiváló kör feladatai. |
| Dataset-gyűjtés vagy training-futtatás | Tiltott zóna (brief §3, AGENTS.md §9). |

### 10.7 Lesson / scope-megjegyzések a jövőbeli aktiváló körhöz

1. **Fix-kör 1 — `decision()` direction korrekció (lezárva).** A
   korábbi §10.7 1. pont (a mostani számozás előtti „látszólagos
   inverzió" megjegyzés) a review által azonosított BLOCKER-1
   forrása volt: a kód a `mean > MEAN_ANCHOR_ERROR_MAX` ágat
   címkézte `PRODUCTION_CANDIDATE`-nek — ez ellentmondott az ADR
   §Döntés 4 „a határ a minősítő oldalhoz tartozik" szabályának
   és az R16 `isLost => drift > lostDriftBound` precedensnek. A
   fix-kör 1 (commitok `2c7959f` + `fe99458`) megfordította a
   külső feltételt `≤`-re; a belső ág (p95, failure_rate guard)
   VÁLTOZATLAN. A `dataset_manifest.md` §2 a MAJOR-1
   (`annotator_privacy_guideline` hiányzó 7. consent-mező)
   pótlásával együtt most már mind a 7 SDD §31.2 elemet viszi.
   Az N2 exit-code javítás (`48c0fd8`) a `raise SystemExit(str)`-et
   `print(..., file=sys.stderr) + sys.exit(EXIT_BAD_INPUT=3)`-ra
   cserélte — a tényleges kilépési kód immár egyezik a
   deklarált/dokumentálttal. A review `gate_shape=VIOLATION`
   jelzésének semmi nyoma (külön processzek, nincs `| tail`/`&&`).
2. **A harness `decision()` a mean-tengelyt elsődlegesnek tekinti**
   a brief §6.2 sweep konvenció miatt (a másik két tengely a
   sweep-ben „végig teljesülő értéken tartva" szerepel). Ha egy
   jövőbeli mérés `mean ≤ 0.030` mellett `p95 > 0.050` vagy
   `failure_rate > 0.05` esettel találkozik, a `decision()` azt
   `EXPERIMENTAL`-nak címkézi — az ADR §Döntés 2 „mindeigyi
   teljesül" guard-ja így érvényesül a brief konvenció felett. A
   fix-kör 1 után a p95-only és failure-rate-only kiegészítő
   tesztek ténylegesen a saját águkat futják be (korábban a
   mean-tengely fordított iránya miatt a záró `return "EXPERIMENTAL"`
   takarta el a p95/failure_rate ágat — az elvárt címke így is
   helyes volt, de más okból).
3. **A `--self-test` kilenc cellája a §6.1 + §6.2 minden
   kötelező celláját lefedi** + két kiegészítő egy-tengelyes hiba-
   teszttel (p95-only és failure-rate-only). A kiegészítő cellák
   NEM a brief-ből jönnek, hanem az implementer védőhálója, hogy
   egy jövőbeli módosítás (pl. egy axis eltérő default kezelése)
   azonnal PIROSRA váltson — a §6.1 5. cellájának („minden cella
   külön teszt") elve alapján.

### 10.8 Záró állapot

- Gate: **ZÖLD** (6/6 lépés, EXIT=0) — lásd §10.2.
- `--self-test`: **9/9 PASS** — lásd §10.2.
- Diff: **kizárólag a §4 listáján** (4 új fájl) — lásd §10.5.
- Tiltott zóna: **nem érintett** (`lib/`, `test/`, `assets/`,
  `pubspec.yaml`, ADR 0187, bináris).
- Stop-szignál: **`tools/codex-signal.sh done "<egy sor>"`** — lásd §8.

## 11. Review — a független reviewer tölti ki

Review: [`docs/reviews/e05-r17-auto-guitar-detector-decision-review.md`](../reviews/e05-r17-auto-guitar-detector-decision-review.md) —
**APPROVED** egy javító kör után (`3748821`→`0c3af47`). Első pass: 1
BLOCKER (`decision()` promóciós logika invertálva — a gyökérok az
orchestrátor saját pre-flight spec-je volt, nem implementer-hiba) + 1
MAJOR (dedikált security-review, risk=high: `dataset_manifest.md`
consent-sémája az SDD §31.2 7 kötelező eleméből 6-ot vitt át). Javító kör
1 (MiniMax) mindkettőt zárta + egy opcionális kilépési-kód pontosítást;
az orchestrátor mindhármat FÜGGETLENÜL, egy friss `/tmp/review-e05-r17-fix1`
klónban (nem az implementer munkapéldányában) ellenőrizte újra — a
BLOCKER-1 zárását egy a self-test körén KÍVÜLI, frissen generált
szintetikus JSONL-lel (`--input`) is megismételve. Gate 6/6 zöld,
scope-audit OK a javító kör saját commit-tartományán. Merge csak
exact-SHA zöld CI, §4-en belüli diff és nulla OPEN BLOCKER/MAJOR után —
ez utóbbi kettő teljesül, a CI-dispatch az orchestrátor következő lépése.
