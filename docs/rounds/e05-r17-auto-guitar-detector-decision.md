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

A §5.2 átfordítási küszöbeit a `--self-test` szintetikus bemenetén kell mérni,
a küszöb **alatt / pontosan rajta / fölötte**. Az ADR 0187 Döntés 2/4. pontja
a mean anchor error küszöböt **0.030**-ban rögzíti, `step=0.001`-gyel
(`python3 -c "print(round(0.03-0.001,3)); print(round(0.03+0.001,3))"` →
`0.029` / `0.031`), a másik két feltételt (failure_rate, minimum-korpusz)
végig teljesülő értéken tartva a szintetikus sweep alatt:

| Cella | Bemenet (mean anchor error, normalizált) | Elvárt döntés |
|---|---|---|
| alatt | **0.029** | `experimental` |
| rajta | **0.030** | `experimental` (a határ a **szigorúbb** oldalhoz tartozik — pontosan a küszöbön még nem jobb, mint a rendszer saját maga) |
| fölött | **0.031** | `production-candidate` (a másik két feltétel — p95 ≤ 0.050, failure_rate ≤ 0.05 — a self-testben teljesül) |

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

_(üres)_

## 11. Review — a független reviewer tölti ki

Tervezett review: `docs/reviews/e05-r17-auto-guitar-detector-decision-review.md`.
Merge csak exact-SHA zöld CI, §4-en belüli diff és nulla OPEN BLOCKER/MAJOR után.
