# ADR 0086 — A `build-apk.yml` csak dispatch-re fut; a naprakészség zárja a rést

**Státusz:** elfogadva (explicit user-döntés, 2026-07-31).
Pontosítja az [ADR 0052](0052-ci-apk-automerge-session-per-round.md) §1-et és az
[ADR 0053](0053-ci-full-test-suite.md) gate-elosztását; folyamat-ADR (0050+ sáv).
**A merge kapuja NEM változik.**

## Kontextus — mérés

A user 2026-07-31-én azt kérdezte, muszáj-e minden körben CI-t futtatni, vagy
elég lenne epicenként. A döntés előtt megmértük, mire megy el a kör ideje:

| | mért érték |
|---|---|
| kör átfutása (merge→merge) | R05→R06 1h41 · R06→R07 2h13 · R08→GOV-01 2h35 · GOV-01→R09 4h22 |
| egy `build-apk.yml` futás | 9–10 perc (12 futás mintája, mind `success`) |
| `build-apk.yml` futás **körönként** | **3** |

A három futás körönként:

1. a kör-branchre `workflow_dispatch`-elt futás — **ez a kötelező evidencia**
   (ADR 0052 §1),
2. automatikus `push` a `main`-re a squash-merge után,
3. automatikus `push` a `main`-re a `docs(handoff)` / brief-commitra.

Vagyis a CI a kör átfutásának **~8%-a**, és annak is csak a harmada kapu. A
tényleges szűk keresztmetszet az implementer → review → javítás soros lánc, nem
a CI.

## Döntés

### 1. Az epicenkénti gate ELUTASÍTVA

A teljes suite + property gate + APK **marad körönként**. Indok: az Epic 2
hátralévő körei szigorú láncot alkotnak (R10 → R11 → R12 → R13 → R14; a briefek
§ „Előfeltétel" pontjai szerint mindegyik az előző merge-ét igényli), így egy
R11-ben keletkezett regresszió az epic végén, öt egymásra épülő kör alatt
eltemetve derülne ki. A megtakarítás ~10 perc/kör (a fenti 8%), az ára a
lánc visszabontása — rossz csere. A HORIZON-szabály (`synthetic green ≠ done`)
és az ADR 0053 kockázat-szakasza változatlanul él.

### 2. A két felesleges futás megszűnik

A `build-apk.yml` `push` triggere törölve — a workflow **csak
`workflow_dispatch`-re** fut, `concurrency: build-apk-${{ github.ref }}` +
`cancel-in-progress` mellett.

Ez a fenti 2. és 3. futást szünteti meg. A 3. tiszta pazarlás volt (docs-only
commit egyetlen buildbe kerülő bájtot sem érint). A 2. normál esetben **nulla
információt** adott: a squash-merge azt a fát állítja elő, amit a branch-futás
percekkel korábban már végiggate-elt.

**A rés, amit a 2. futás fedett**, és amit ezért ki kell váltani: ha a `main` a
dispatch UTÁN mozdul (ezen a boxon egy másik autonóm kör-driver is merge-el), a
squash eredménye eltér a gate-elt fától. Ezért a merge feltétele kiegészül:

> A merge előtt a kör-branch legyen naprakész az `origin/main`-nel, és ha a
> `main` a CI-dispatch óta mozdult, a merge előtt **újra kell dispatch-elni** —
> az evidencia a friss run linkje.

Ellenőrzés a merge előtt (a driver skill 5. lépésében):

```bash
git fetch origin main
git rev-parse origin/main            # egyezzen a dispatch idejekor látottal
gh run list --workflow build-apk.yml --branch <kör-branch> --limit 1
```

## Következmények

- Körönként 3 helyett **1** `build-apk.yml` futás (~20 perc Actions-perc
  megtakarítás körönként), a kapu tartalma változatlan.
- `main`-re nincs többé automatikus build. Ha valaha kell (pl. release-előkészítés),
  kézzel: `gh workflow run build-apk.yml --ref main`. A production útvonal
  változatlan (`release-apk.yml`, ADR 0062 — az eddig is dispatch-only volt).
- A `backend-ci.yml`, `lab-apk.yml`, `chord-train.yml`, `dsp-probe.yml`,
  `ml-train.yml` triggerei **nem változnak** — ezek nem a kör-kapu részei.
- Az ADR 0052 §1 és §2 szövege érvényben marad; a §2 „a branchre dispatchelt
  CI-build success" feltétele mostantól a fenti naprakészség-ellenőrzéssel
  együtt értendő.
- Kockázat: ha a naprakészség-ellenőrzés elmarad, egy drift-eset gate nélkül
  jut `main`-re. Enyhítés: az ellenőrzés a driver skill merge-lépésébe került
  parancsokkal, nem prompt-szövegként.

## Elutasított alternatívák

- **Nightly build a `main`-en** a törölt push-trigger pótlására: változatlan fán
  ismételne buildet, tehát ugyanazt a pazarlást hozná vissza időzítve.
- **`paths-ignore` a docs-ra, push-trigger megtartásával:** csak a 3. futást
  vágta volna ki, a 2. (nulla információjú) duplikátumot nem.
- **Párhuzamos második projekt a MiniMax M3-mal** (a gyorsítás másik felvetett
  útja): a user 2026-07-31-én elvetette — **csak a gitáros app** fejlődik. Az
  Epic 2-n belüli párhuzamosítás R14-ig amúgy is kizárt a fenti lánc miatt; az
  első valódi párhuzamos ablak R15 ∥ R16 ∥ R17 (az R16 briefje kimondja, hogy
  „az R15 nem előfeltétel").
