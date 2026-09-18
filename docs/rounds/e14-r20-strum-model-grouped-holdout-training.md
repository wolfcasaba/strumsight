# E14-R20 — Strum modell tanítás grouped holdouttal

- **Fejezet:** Chapter 14 (Recognition Accuracy & Useful UI Recovery), Kör 20
  (`docs/sdd/14-chapter-14-recognition-ui-recovery.md` §Kör 20)
- **Státusz:** **ELŐKÉSZÍTVE, NEM indítható** — a §0.0 STOP-feltételei nyitottak.
  A queue-ba (`docs/execution/pipeline-queue.tsv`) SZÁNDÉKOSAN nem került be:
  a driver csak adattal rendelkező kört indíthat, és a completion-matrix
  (`program_completion_test` A1) egy `prepared` sort is számolna.
- **Terv szerzője:** Claude, 2026-09-15 (a tanulói-hurok 1–5. kör után)

## 0.0 Pre-flight — mért tények és STOP-feltételek (`claude/sdd-plans-quality-clarity-5ydqyy @ 7b1cff1`)

| Mérés | Eredmény | Következmény |
|---|---|---|
| `find ml/corpus -type f \| wc -l` | **4** (README, két fetch-szkript, egy negatív-generátor) — **nincs verziózott valós corpus a repóban** | a tanítás bemenete ma NEM létezik a fán |
| `ls ml/` | `train.py`, `train_live_3c.py`, `augment.py` (R19 recept, manifestelt), `honest_eval.py`, `make_model_card.py`, `export_live_weights.py`, `joint_prototype/` (R18) | a recept és az eszközlánc MEGVAN, csak adat nincs |
| `ml/live_3c_threshold.json` (saját eval) | irány-pontosság **80,68 %** a valódi pengetéseken | ez a javítandó szám |
| `docs/release/` | **0** dokumentált valós gitáros menet | nincs holdout „játékos"-csoport |
| R06 (Accuracy Lab, engedélyezett rögzítés) | a rögzítő ÚT kész, de a rögzítések a KÉSZÜLÉKEN maradnak (diagnosztika-feltöltés az alap buildben nem hosztolt) | az adat begyűjtése emberi lépés |

**STOP-feltételek (mindhárom kell az indításhoz):**

1. **Valós tesztjegyzőkönyv** a `docs/manual-testing/learner-loop-device-run.md`
   8. szakaszával kitöltve (irány: „hány jó a 20-ból", akkord-recall soronként).
   Ez adja a **célértéket** és a **hibaosztály-térképet** (le/fel tévesztés vs.
   onset-hiány vs. akkord-tévesztés) — a Chapter 14 §7.2 Alpha-kapu ehhez mér.
2. **Csoportosított corpus** legalább 3 játékos × 2 gitár × 2 helyiség
   bontásban (R06 Accuracy Lab rögzítés + R07 annotáció), verziózott
   manifesttel (`ml/make_manifest.py`) és hash-sel. Egy játékosra tanítani
   TILOS (Ch14 §9/4).
3. **Holdout-séma rögzítve** az R08 harness szerint (`grouped evaluation`,
   ADR 0509): a test-csoport játékosa/eszköze/gitárja NEM szerepel a
   train/validation csoportban; a küszöb a validation-on hangolható, a
   test-seten SOHA.

## 1. Cél

Egy **reprodukálható** strum (down/up/no-strum) modell-jelölt, csoportosított
holdouton mérve, model carddal, amely a Ch14 §7.2 Strum Alpha kaput
**mérten** közelíti — és **app assetbe nem kerül** gate nélkül (Kör 22–24).

## 2. Scope

**Benne:** `ml/train_live_3c.py` futtatása az R19 receptjével (`augment_pcm_configurable`
+ `balance_indices`) a csoportosított corpuson; checkpoint + `config`, `seed`,
dependency lock, git SHA, dataset hash, per-group metrikák; `ml/make_model_card.py`
kimenete ismert gyengeségekkel; a `ml-train.yml` (x86 CI trainer) futása mint
bizonyíték.

**Kívül:** app-oldali bekötés (`assets/ml/**`, `lib/**`), küszöb-hangolás a
test-seten, bármilyen Live UI-változás.

## 3. Engedélyezett fájlok

- `ml/train_live_3c.py`, `ml/honest_eval.py`, `ml/make_model_card.py`,
  `ml/model_card.json` (kimenet), `ml/corpus/README.md` (manifest-leírás)
- `docs/rounds/e14-r20-strum-model-grouped-holdout-training.md` (§10 handoff)
- **Tilos:** `assets/**`, `lib/**`, `.github/workflows/**`, `ml/live_3c_threshold.json`

## 4. Kötött döntések

- **D1** Early-stopping fő metrika: end-to-end **macro F1** (down/up/no-strum);
  másodlagos: conditional accuracy és coverage (abstention után).
- **D2** A run minden bemenete hash-elve a model cardban; ugyanaz a seed →
  bitazonos metrika-JSON (L631: a SZÁLLÍTOTT belépési pont mérje).
- **D3** `null ≠ 0` (ADR 0509): hiányzó csoport-metrika `null`, nem nulla.
- **D4** A jelölt neve `strum_3c_grouped_<datasetHash8>_<sha8>`; a `live_3c_threshold.json`
  ebben a körben VÁLTOZATLAN.

## 5. Acceptance criteria (gépi cellák)

- **A1** `ml/test_pipeline.py`-ba új cella: a train belépési pont ugyanazzal a
  seed-del és corpus-hash-sel kétszer futtatva azonos metrika-JSON-t ad.
- **A2** Per-group metrika-tábla létezik minden holdout-csoportra; egyetlen
  csoport sem hiányzik (vagy `null`-ként jelölt).
- **A3** A model card tartalmazza: dataset hash, split-séma, seed, git SHA,
  lock-hash, ismert gyengeségek (legalább a jegyzőkönyv 8.8 hibaosztálya).
- **A4** Falszifikáció: a test-set küszöbhangolás egy szándékos próbadiffje
  (küszöb a test-metrikából) PIROSRA váltja az A1/A2 cellát.
- **A5** Nincs változás `assets/ml/**` alatt (git diff üres).

## 6. Kockázatok

- A corpus kicsi marad → a per-group szórás nagyobb, mint a javulás: ekkor a
  kör `candidate`-ként zár, nem `accepted`-ként (ADR 0525 D6 minta).
- A jegyzőkönyv azt mutatja, hogy a hibaosztály az **onset** (nem az irány):
  akkor a kör helyett a Kör 16 (SuperFlux A/B) eredményét kell előrevenni —
  ezt a §0.0/1 jegyzőkönyv dönti el, ezért nem indítható előtte.

## 10. Implementation handoff — az implementer tölti ki

(üres — a kör nem indult)

## 11. Review — a Claude tölti ki

(üres)
