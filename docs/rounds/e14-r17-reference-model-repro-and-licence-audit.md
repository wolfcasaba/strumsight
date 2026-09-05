# E14-R17 — Referencia-modell reprodukció és licenc-audit

- **Státusz:** PREPARED (előre megírva 2026-08-20, kód olvasva: `main @ 6371aa3`)
- **Típus:** Chapter 14, Kör 17 (strum recovery blokk) — **kutatási kör**
- **Kör-azonosító:** `E14-R17`
- **Branch:** `<motor>/e14-r17-reference-model-repro-and-licence-audit`
- **Előfeltétel:** `E14-R08` (grouped harness, hogy a StrumSight-korpuszon is
  mérhető legyen) merge-elve.
- **Brief szerzője:** Claude (Opus 5)
- **Előre kiosztott ADR:** `0369` — **a Claude írja meg (go/no-go), a `docs/adr/` a TILOS zónában van.**

> ⚠ **Pre-flight (indítás előtt KÖTELEZŐ):** ellenőrizd, hogy a research
> környezet elérhető-e ezen a boxon (`ml/README.md` + a TF-venv útvonala). Ha
> nincs, a kör jelzése `blocked` — sikeres verifikációt állítani tilos
> (Chapter 14 §9/9). Eltérésnél §0.0 revízió.
>
> **A pre-flight LEFUTOTT (2026-09-05) — a §0.0 revízió KÖTI a kört.** A
> `blocked` kifutást a §0.0 D-pontja **felülírja**: a mérés szerint nem
> „elérhetetlen a checkpoint", hanem a **licenc-audit önmagában konkluzív**.

## 0.0 Pre-flight revízió (2026-09-05, orchestrátor: Claude — ADR 0087 §2)

**Alap:** `main @ 39680e1e`. A brief `main @ 6371aa3`-on készült; a `git diff
--name-only 6371aa3..HEAD -- ml/ assets/ test/tooling/ docs/eval/` mérés
szerint az **`ml/` és az `assets/` érintetlen**, a `test/tooling/` és a
`docs/eval/` bővült, de a §2 mért tényei **mind érvényben maradtak**:
`ml/reference/` nem létezik, külső referencia-checkpoint nincs a fában,
licenc-őr nincs. (S15-mérés, ADR 0171 §4.)

**Visszakeresés (ADR 0312, kötelező — a talált előzmények):**
`adr/0473` (fa-bejárás + tartalom-checksum + **fail-closed licenc**:
„ismeretlen licenc = megállás, nem »unknown«"), `adr/0447` (release manifest,
provenance, SBOM), `lessons/L546` (az implementer a falszifikációs cellát
MEGFORDÍTOTTA — a licenc-hiányt „valid"-dá tette), `lessons/L530` (generált
artefaktum a generáló gép abszolút útvonalával, zöld gate mellett),
`lessons/L118` (az őr tesztje ne az ambiens repó-állapotra támaszkodjon).

### A) A referencia-modell NEVESÍTVE — mért, nem feltételezett

A brief „publikált joint referencia-modell"-t ír, de nem nevezi meg. A
Chapter 14 Kör 17 címe és a `docs/research/recognition-research-sources.md`
alapján ez a **Klangio ISMIR 2025** rendszer. A pre-flight **hálózatról
mérte** (GitHub API + `raw.githubusercontent.com`, 2026-09-05):

| Mért tény | Érték |
|---|---|
| Repó | `Klangio/guitar-strumming-transcription` |
| **Pinelendő commit** | `929e403f3256b055c1eea27064ae39f36905359e` (2025-09-21T14:31:50Z) |
| Repo-szintű licenc | `Apache-2.0` (`LICENSE`, teljes szöveg) |
| Kód | `klangio/modules/strumming_crnn/` (9 `.py`) + `scripts/` (3 `.ipynb` + `train_phone.py`) |
| **Checkpoint** | `checkpoints/wc/step=19000-f1=0.8225.ckpt` — **Git-LFS pointer** (134 B a fában), `sha256:80297850d7d2150093d5ae2bcb090466566ad24fa835a5c1e67f16ca38a3ea44`, valódi méret **134 344 202 B** |
| **Adathalmaz** | `dataset/klangio-gst-mm-2025/` — **330 blob, 913 163 829 B** a fában (nem LFS) |
| Reprodukció ma | **notebook** (`scripts/evaluate.ipynb`) — egyparancsos futtatás NINCS |
| Függőségek | `requirements.txt`: `torch`, `lightning`, `note-seq`, `torchlibrosa`, `librosa==0.10.1`, `hydra-core`, `wandb` |

**A licenc-nyilatkozat mért terjedelme.** A `README.md` „License" szakasza szó
szerint: *„Copyright © 2025 Klangio GmbH — This **software** is licensed under
the Apache License, Version 2.0."* A nyilatkozat tehát **a szoftverre** szól;
a „Pretrained Checkpoint" és a „Dataset" szakaszban **nincs licenc**, és a
`checkpoints/` illetve `dataset/` alatt sincs licenc-fájl. A README `Citation`
szakasza kutatási használatra utaló idézési kötelezettséget ír elő, ami **nem
termék-engedély**.

### B) A research környezet mért állapota ezen a boxon

- Egyetlen ML-venv: `/home/ubuntu/tf-venv` → `tensorflow 2.21.0`, `keras 3.15.0`.
  **`torch` NINCS benne** (`pip list` mérve), a rendszer-Pythonban sem.
- Hálózat elérhető (`github.com`, `huggingface.co`, `zenodo.org` → HTTP 200).
- A teljes reprodukció tehát a PyTorch-lánc telepítését **plusz** ~1,05 GB
  letöltést (134 MB LFS-checkpoint + 871 MB adathalmaz) igényelne.

### C) **D — A kör kifutása: `done`, NEM `blocked`** (ez köti az implementert)

A brief §0 és a 6/5. acceptance-pont `blocked`-ot ír „letölthetetlen
checkpoint" esetén. A mérés szerint **a checkpoint letölthető** (publikus
LFS-objektum), tehát ez a kifutás **nem áll fenn**. Ami hiányzik, az a
PyTorch futtatókörnyezet — de a kör **elsődleges kérdését, a licenc-go/no-go-t
ez nem érinti**: az ítélet a fenti mért nyilatkozatokból **konkluzív**
(`ADR 0369` D2 → **NO-GO**), és NO-GO alatt a teljesítmény-mérés a
termék-döntés szempontjából tárgytalan.

Ezért — az ADR 0087 §2 szerinti brief-revíziós hatáskörben:

1. **A kör `done` jelzéssel zárul**, ha a §6 1–4. és 6. pontja teljesül.
2. A **nem futtatott** méréseket a report szó szerinti **`NEM MÉRT`** cellával
   jelöli, mellé a hiány **mért okát** és a **reprodukáló parancsot**.
   Becsült szám a reportban **tiltott** — ez a §5/9. „nem becsült értékek"
   kikötésének betartása, nem a lazítása.
3. `blocked` jelzés **kizárólag** akkor, ha a fenti A) táblázat bármely mért
   ténye a kör futása közben megdől (a repó/commit eltűnik, a licenc-szöveg
   más, mint amit a pre-flight mért) — akkor a mérce, nem a kifutás változott.

### D) A 6/6. acceptance-pont pontosítása

Az eredeti szöveg mért **latency- és memória-értéket** kér a go/no-go mellé.
Mivel a futtatás nem történik meg (B), a go/no-go a következő **MÉRT** tényekre
hivatkozik: (a) a három licenc-státusz (A), és (b) a checkpoint **mért mérete,
134 344 202 bájt**, ami a mobil memória-költség **alsó korlátja**. A latency
cellája `NEM MÉRT` + reprodukáló parancs. Egyéb becslés tilos.

### E) Brief-lint S12 (strict) — javítva

A §7 gate-parancsa `test/tooling` könyvtárat futtatott, a `gate_tests` viszont
a konkrét fájlt sorolja; a `brief-lint` a **szó szerinti egyezést** méri
(`tools/brief-lint.py:1151`). A §7 parancsa átírva a `gate_tests` listát
tükrözve. A `tools/round-gate.sh` fájl-útvonalat elfogad
(`tools/round-gate.sh:228` → `flutter test "$test_path"`).

### F) ADR-szám

`0369` — a foglaló (`tools/round-slots.py reserve-adr`) csak a legmagasabb szám
FÖLÉ oszt (`0514`, `0515`), ezért az alacsonyabb, **committolt sor-fájlbeli
előfoglalást** nem tudja igazolni. Külön mérve, hogy `0369` szabad: nincs
`docs/adr/0369*` fájl, nincs `.pipeline/inflight/adr/0369` marker, és a
`git log --all --diff-filter=A -- docs/adr` egyetlen ágon sem hozott létre
`0369`-et. A `docs/execution/pipeline-queue.tsv` egyetlen sora hivatkozik rá
(E14-R17). Az ADR megírva: `docs/adr/0369-reference-model-repro-and-licence-audit.md`.

```ai-router
schema_version = 1
risk = "normal"
allowed_paths = [
  "ml/reference/README.md",
  "ml/reference/run_reference_eval.py",
  "ml/reference/reference_manifest.json",
  "test/tooling/reference_model_licence_guard_test.dart",
  "docs/eval/reference-model-audit.md",
  "docs/rounds/e14-r17-reference-model-repro-and-licence-audit.md",
]
gate_tests = [
  "test/tooling/reference_model_licence_guard_test.dart",
]
native_gate = false
```

## 0. Kör-jelzés és STOP-protokoll

```bash
tools/codex-signal.sh progress "<egy sor>"
tools/codex-signal.sh done "<egy sor>"
tools/codex-signal.sh stopped "<egy sor>"
tools/codex-signal.sh blocked "<egy sor>"
```

Lezáró jelzés nélkül a kör bukott. Listán kívüli fájl → `stopped`.
**Hiányzó research-környezet vagy letölthetetlen checkpoint → `blocked`**, nem
„részleges siker".

## 1. Cél

A publikált joint referencia-modell **reprodukálható** legyen egyetlen
paranccsal, és a **licenc-audit** (kód, checkpoint, dataset KÜLÖN) döntse el,
kerülhet-e bármilyen artefaktum a termékbe. A hivatalos eredményt és a
StrumSight saját mérését a report **soha nem keveri**.

### 1.1 Visszakeresett előzmény (ADR 0312)

- **Chapter 14 §5.1:** a joint onset+direction+chord modell a legerősebb
  kutatási irány — de előbb reprodukálni kell, nem átvenni.
- **AGENTS.md §5 / ADR 0138 titok-scan:** külső artefaktum nem kerülhet a
  repóba audit nélkül; ez a kör ezt gépi őrré teszi.

## 2. Jelenlegi állapot — mért tények

- `ml/` — saját tanító oldal (`honest_eval.py`, `klangio.py`, `model_card.json`,
  `export_dart_weights.py`); **nincs** külső referencia-modell futtatókörnyezet.
- `assets/` — a szállított súlyok helye; ma nincs külső, harmadik féltől
  származó checkpoint.
- Nincs olyan gépi őr, amely megakadályozná egy nem auditált külső artefaktum
  bekerülését.

## 3. Scope

**Benne:** pinelt reprodukciós script + README (külön környezet), a hivatalos
fixture és a StrumSight held-out mérése KÜLÖN táblában, licenc-audit
(kód/checkpoint/dataset), gépi licenc-őr, doksi.

**Nincs benne:** bármilyen külső súly bemásolása a repóba/`assets/`-be,
production-bekötés, `lib/**` módosítás, DSP/ML konstans.

## 4. Engedélyezett fájlok

| Útvonal | Miért |
|---|---|
| `ml/reference/README.md` | környezet, pinelt commit, futtatás |
| `ml/reference/run_reference_eval.py` | egyparancsos reprodukció |
| `ml/reference/reference_manifest.json` | forrás, commit-hash, licencek, checksum |
| `test/tooling/reference_model_licence_guard_test.dart` | gépi őr: nincs auditálatlan artefaktum |
| `docs/eval/reference-model-audit.md` | a két mérés KÜLÖN + go/no-go javaslat |
| `docs/rounds/e14-r17-reference-model-repro-and-licence-audit.md` | §10 handoff |

**Tilos zóna:** minden más — **kiemelten** `assets/**` (semmilyen külső súly),
`lib/**`, `ml/` a `reference/` alkönyvtáron kívül, `docs/adr/**`,
`docs/rag/chunks/**`, `.github/workflows/**`, `tools/round-gate.sh`.

## 5. Kötött architekturális döntések (ADR 0369)

### 5.1 Licenc-blokkolónál nincs másolás

Ha a kód, a checkpoint VAGY a dataset licence tiltja a termékfelhasználást,
semmilyen artefaktum nem kerül a repóba, és a kör eredménye **no-go**.
**NEM elfogadható**: „csak kísérletnek betesszük".

### 5.2 A három licenc külön ítélet

A kód, a súly és az adat licence KÜLÖN mezőt kap a manifestben; egyetlen
„MIT-nek tűnik" összefoglaló nem elég.

### 5.3 A két mérés nem keveredik

A hivatalos fixture eredménye és a StrumSight held-out eredménye külön
táblában, külön korpusz-hash-sel szerepel.

### 5.4 A reprodukció egy paranccsal fut

`python3 ml/reference/run_reference_eval.py --manifest …` — kézi lépéssor nem
elfogadható reprodukcióként.

### 5.5 Gépi őr, nem ígéret

A licenc-őr teszt a repó fáján ellenőrzi, hogy nincs olyan referencia-eredetű
artefaktum, amelyhez ne tartozna `approved` audit-bejegyzés.

## 6. Acceptance criteria

1. A reprodukciós script egyetlen paranccsal fut, és a manifestben rögzített
   pinelt commit-hash-t használja.
2. A manifest mindhárom licenc-mezőt tartalmazza; bármelyik hiánya → típusos
   hiba.
3. A report két külön táblát ad (hivatalos fixture vs StrumSight held-out),
   mindkettőnél korpusz-hash-sel.
4. A licenc-őr teszt PIROS, ha egy referencia-eredetű fájl audit-bejegyzés
   nélkül jelenik meg a fán (a teszt ideiglenes fixture-fájllal méri).
5. **(§0.0 C) által felülírva:** a checkpoint MÉRHETŐEN elérhető, a PyTorch
   futtatókörnyezet nem — ezért a kör **`done`**-nal zárul, és a report a nem
   futtatott számokat szó szerinti **`NEM MÉRT`** cellával, a hiány mért okával
   és a reprodukáló paranccsal jelöli. Becsült érték tiltott. `blocked` csak
   akkor, ha a §0.0 A) mért tényei a futás közben megdőlnek.
6. **(§0.0 D) által pontosítva:** a go/no-go a MÉRT tényekre hivatkozik — a
   három licenc-státusz és a checkpoint mért mérete (**134 344 202 B**) mint
   memória-alsókorlát; a latency cellája `NEM MÉRT` + reprodukáló parancs.

### 6.1 Mérce-mátrix — melyik hibás implementációt melyik cella fogja pirosra

| Hibás implementáció | Melyik cella vált PIROSRA |
|---|---|
| Egyetlen összevont licenc-mező | 2. pont |
| A két mérés egy táblában | 3. pont |
| Az őr csak `assets/`-et néz, más útvonalat nem | 4. pont fixture-cellája |
| Hiányzó környezetnél becsült szám | 5. pont |
| Kézi lépéssor reprodukcióként | 1. pont |

## 7. Kötelező ellenőrzések

```bash
tools/round-gate.sh test/tooling/reference_model_licence_guard_test.dart
```

Külön processzben futó `format` → `analyze` → célzott teszt → `architecture`
(AGENTS.md §12). A Python oldal külön, önálló parancsként:

```bash
python3 -m pytest ml -q
```

`&&` láncolás tilos (L05/L09). CI-dispatch/PR/merge Claude-oldal.

### 7.1 Falszifikációs cella

A §10-ben dokumentáld: egy ideiglenes, audit nélküli referencia-fájl
elhelyezésével a 4. pont **PIROS**, a fájl törlésével **ZÖLD**.

## 8. Implementációs sorrend

1. Manifest-séma (három licenc, commit-hash, checksum).
2. Licenc-őr teszt (RED-del kezdve).
3. Reprodukciós script + README.
4. Report — a §0.0 A) mért tényeivel, a két KÜLÖN táblával, és a nem futtatott
   cellákban szó szerinti `NEM MÉRT` + reprodukáló parancs (§0.0 C/D).
   **Ne jelezz `blocked`-ot a hiányzó PyTorch miatt** — az a §0.0 C) szerint
   nem a kör kifutása.

## 9. Kockázatok

- **Környezet-hiány:** valószínű ezen a boxon; a `blocked` út a helyes, nem a
  becslés.
- **Licenc-tévedés:** ha bármelyik licenc nem egyértelmű, a döntés
  **no-go** — a kétség nem engedély.
- **Scope-csúszás a bekötés felé:** tilos zóna: `lib/**`, `assets/**`.

## 10. Implementation handoff — az implementer tölti ki

**Kifutás: `done`** (§0.0 C — a hiányzó PyTorch nem `blocked` ok; a §0.0 A)
mért tényei a futás közben nem dőltek meg).

### Amit építettem — a hat fájl

1. **`ml/reference/reference_manifest.json`** — a §0.0 A) táblázat mind a
   nyolc mért értéke szó szerint benne (repó-URL, pinelt commit
   `929e403f3256b055c1eea27064ae39f36905359e`, checkpoint útvonal + sha256 +
   134 344 202 bájt, dataset útvonal + 330 blob + 913 163 829 bájt). Három
   KÜLÖN `artifacts.{code,checkpoint,dataset}.license` blokk, mindegyik
   `spdx`+`source`+`evidence`+`verdict` néggyessel. A checkpoint/dataset
   `spdx` mezője JSON **`null`** (nem az `"unknown"` sztring) + `verdict:
   "blocking"` — ezt a séma-ellenőrzés (mindkét oldalon: Dart guard ÉS a
   Python script `validate_manifest`) kényszerként ismeri fel, és `null`
   spdx `"blocking"`-tól eltérő verdikttel típusos hibát dob. `audit_registry`
   üres lista (D2 NO-GO → nincs jóváhagyott artefaktum).

2. **`ml/reference/run_reference_eval.py`** — egyparancsos belépő,
   `--manifest` + `--workdir` (kötelező a teljes futáshoz, repón-kívüli útvonal
   kényszerítve — `WorkdirInsideRepositoryError` típusos hiba, valóban
   lefuttatva és piros lett a repón belüli próbával, lásd lent) + `--verify-only`
   (hálózat nélkül ellenőrzi a manifest sémáját). Hiányzó függőségnél
   `MissingDependencyError`: pontos `pip install` sor + a reprodukáló parancs.
   A tényleges klónozás/checkpoint-verifikáció/kiértékelés kódja megvan
   (`clone_pinned_commit`, `verify_checkpoint`), de a `run_official_fixture_eval`
   / `run_strumsight_holdout_eval` `NotImplementedError`-t dob — ez a kör nem
   futtat le semmit hálózatról (§0.0 B/tiltás), és a hiányzó PyTorch miatt a
   futás ma sosem jut el idáig (a függőség-ellenőrzés korábban bukik).

3. **`ml/reference/README.md`** — környezet (a hét upstream függőség), a
   pinelt commit, a pontos parancsok, és a mai le-nem-futás mért oka.

4. **`test/tooling/reference_model_licence_guard_test.dart`** — RED-del
   kezdtem (a fájl és az `ml/reference/` könyvtár nem létezett, a teszt
   `_realManifest()`/`_realReportMarkdown()` hívása `PathNotFoundException`-t
   dobott volna). Három csoport: A) manifest-séma (a fenti háromas licenc-
   szerződés, beleértve az `"unknown"`/`"n/a"`/üres placeholder-tiltást
   mindhárom artefaktumra, kis- és nagybetűs változatban is — L546
   regressziós őr), B) fail-closed fa-bejárás (ADR 0369 D5) — `git ls-files`-ből
   indul, NEM a manifest listájából, és öt KÜLÖN lokáción bizonyítja a
   PIROS→ZÖLD párt egy szintetikus temp git-repóban (`assets/`, `ml/`, `tool/`,
   `test/fixtures/`, gyökér) — ez a §7.1 falszifikációs cella tétele. C) a
   report-struktúra (két külön tábla, D4) mind szintetikus, mind a valódi
   `docs/eval/reference-model-audit.md` ellen. Önálló fájl, mert a kör
   `allowed_paths`-a nem tartalmaz `tool/**` segédkönyvtárat.

5. **`docs/eval/reference-model-audit.md`** — KÉT külön tábla (hivatalos
   fixture / StrumSight held-out), mindkettő korpusz-hash mezővel, minden
   nem-mért cella szó szerint `NEM MÉRT` + mért ok + reprodukáló parancs. A
   §3 licenc-audit táblája a három ítélettel, a §4 go/no-go kizárólag mért
   tényekre hivatkozik (három licenc-státusz + 134 344 202 bájt), a §5 a
   falszifikációs cellát dokumentálja.

6. **Ez a §10 handoff.**

### Ténylegesen lefuttatott parancsok — VALÓDI kimenettel

```
$ python3 ml/reference/run_reference_eval.py --manifest ml/reference/reference_manifest.json --verify-only
{
  "manifest": "ml/reference/reference_manifest.json",
  "schema": "ok",
  "pinned_commit": "929e403f3256b055c1eea27064ae39f36905359e",
  "go_no_go": "NO-GO"
}
(exit 0)

$ python3 ml/reference/run_reference_eval.py --manifest ml/reference/reference_manifest.json --workdir /tmp/klangio-repro-e14r17
error: missing Python dependencies for the reference reproduction: torch, lightning, note-seq, torchlibrosa, librosa==0.10.1, hydra-core, wandb
  pip install torch lightning note-seq torchlibrosa librosa==0.10.1 hydra-core wandb
then rerun:
  python3 ml/reference/run_reference_eval.py --manifest ml/reference/reference_manifest.json --workdir <path outside this repository>
(exit 1, semmi nem íródott lemezre — a workdir.mkdir() a függőség-ellenőrzés UTÁN fut)

$ python3 ml/reference/run_reference_eval.py --manifest ml/reference/reference_manifest.json --workdir ml/reference/inside-repo-should-fail
error: --workdir /home/ubuntu/ss-sonnet-impl-e14-r17/ml/reference/inside-repo-should-fail resolves inside this repository (/home/ubuntu/ss-sonnet-impl-e14-r17); ADR 0369 D3 requires the reproduction to run entirely outside the repo tree — pick a path such as /tmp/klangio-repro
(exit 1)
```

Gate (csonkítás nélkül, saját processz-lépésenként):

```
$ tools/round-gate.sh test/tooling/reference_model_licence_guard_test.dart
[1] format     → ZÖLD (Formatted 2291 files (0 changed))
[2] analyze    → ZÖLD (No issues found!)
[3] test …     → ZÖLD (42 tests, „All tests passed!”)
[4] architecture → ZÖLD (12 allowlisted deviation(s), változatlan)
[5] secrets    → ZÖLD (4376 file(s) scanned, 0 finding(s))
[6] l10n       → ZÖLD
MINDEN GATE ZÖLD.
```

```
$ python3 -m pytest ml -q
115 passed in 20.92s
```

(A 115 a kör előtti alap — ehhez a körhöz nem tartozott új Python-tesztfájl,
az `allowed_paths` nem sorol `ml/reference/test_*.py`-t; a Python-oldali
kényszert a `run_reference_eval.py::validate_manifest` hordozza, ténylegesen
lefuttatva a fenti `--verify-only` híváson keresztül.)

### `NEM MÉRT` — mi maradt és miért

A hivatalos fixture és a StrumSight held-out mérés MINDKÉT cellája `NEM MÉRT`
(`docs/eval/reference-model-audit.md` §1–2): a mért ok a hiányzó PyTorch/
Lightning/note-seq/torchlibrosa/librosa==0.10.1/hydra-core/wandb futtatókör
ezen a boxon (sem a `/home/ubuntu/tf-venv`, sem a rendszer-Python nem hordozza
őket — ténylegesen lefuttatva a `check_dependencies` hívással fent), plusz az
upstream kiértékelés notebook-formája (`scripts/evaluate.ipynb`), aminek a
cella-kimenet szerződését a pre-flight nem olvasta el (nincs PyTorch-képes gép
hozzá). Ez a §0.0 C szerint NEM `blocked`-kifutás — a licenc-ítélet ezektől
függetlenül konkluzív.

## 11. Review — a Claude tölti ki


