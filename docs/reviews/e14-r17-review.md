# E14-R17 — Review (Claude, ADR 0055 · read-only)

- **Kör:** `E14-R17` — Referencia-modell reprodukció és licenc-audit
- **Ág:** `sonnet-impl/e14-r17-reference-model-repro-and-licence-audit`
- **Implementer:** `sonnet-impl` (Claude Sonnet 5, `--effort high`)
- **Reviewed HEAD:** `6a8dcded` (pre-flight base: `ba6c901f`)
- **Dátum:** 2026-09-05

## 0. Gépi előfeltételek

| Ellenőrzés | Eredmény |
|---|---|
| Scope-audit (`tools/scope-audit.py --base ba6c901f`) | **OK** — 6 megváltozott útvonal, mind az `allowed_paths`-on, 0 generált/ignorált |
| `dirty_files` a `done` jelzésnél | `1` — **kivizsgálva**: a jelzés pillanatában a §10 handoff commit még folyamatban volt; a futás után `git status --short` **üres** |
| Brief-lint (strict) a revideált briefen | nincs lelet (S12 javítva a pre-flightban) |
| Tilos zóna | érintetlen: `lib/**`, `assets/**`, `ml/` a `reference/`-en kívül, `docs/adr/**`, `.github/**`, `tools/**` — **nulla** külső bájt a fában (ADR 0369 D3 teljesül) |

## 1. Amit a kör helyesen old meg

- **A licenc-ítélet a mért nyilatkozatból következik, nem feltételezésből.** A
  manifest a `checkpoint`/`dataset` `spdx` mezőjét `null` + `verdict:
  "blocking"` alakban hordozza, és az `evidence` mező szó szerint idézi, hogy a
  README grantja a **„software"-re** szűkül. Ez pontosan az ADR 0369 D1/D2, és
  az [L546](../LESSONS.md#l546) inverziója **nem** történt meg: a
  `_validateManifestSchema` a `null` spdx-et CSAK `blocking` verdikttel fogadja
  el (`nullSpdxWithoutBlockingVerdict` cella), az `"unknown"`/`"n/a"`/`""`
  sztringeket pedig mind a három artefaktumra, hat változatban elutasítja.
- **Az őr a FÁT járja, nem a manifest listáját** (ADR 0369 D5 / ADR 0473 D1
  minta): `git ls-files` + tartalom-sha256, az `audit_registry` `approved`
  bejegyzésével mint menekülőúttal. Az öt falszifikációs cella (`assets/`,
  `ml/`, `tool/`, `test/fixtures/`, gyökér) bizonyítja, hogy **nem** korlátozódik
  `assets/`-re — ez a §6.1 mátrix „az őr csak `assets/`-et néz" sorának valódi
  ellenpróbája.
- **A teszt nem az ambiens fára támaszkodik ott, ahol az eredmény megfordulhat**
  ([L118](../LESSONS.md#l118)): a PIROS→ZÖLD párokat a teszt SAJÁT, ideiglenes
  git-repóban méri (`_newTempRepo` + `addTearDown`), nem kézzel elhelyezett
  fájllal. A `git ls-files` hibája `StateError` — a bizonyíthatatlan kapu piros,
  nem zöld.
- **A két mérés szétválasztása gépi cella, nem ígéret** (D4): a C csoport külön
  fejlécet ÉS saját korpusz-hash mezőt követel, és pirosra vált egy olyan
  táblasorra, amely mindkét mérést megnevezi.
- **Nincs abszolút gép-útvonal a kimeneten** ([L530](../LESSONS.md#l530)): a
  script minden jelentett útvonalat a `--workdir`-hez képest relativizál.
- **A report `NEM MÉRT` cellái mellett ott a mért ok és a reprodukáló parancs**,
  becsült szám sehol (D6). A go/no-go a checkpoint **mért** méretére
  (134 344 202 B) hivatkozik; az `assets/ml/*.bin` összehasonlító állítást
  ellenőriztem: a szállított súlyok 894 725–1 456 887 bájt, tehát a „néhány száz
  KB–néhány MB" **igaz**.

## 2. Leletek

### MAJOR-1 — az őr kiterjesztés-halmaza SZŰKEBB, mint a manifest által pinelt upstream artefaktum-formátumok

`test/tooling/reference_model_licence_guard_test.dart:611`

```dart
const _referenceCheckpointExtensions = <String>{'ckpt','pt','pth','safetensors'};
```

A pinelt upstream commit `.gitattributes`-a (`929e403f`, a pre-flight mérte)
**hat** formátumot tart LFS alatt:

```
*.pth  *.pt  *.ckpt  *.cpkt  *.h5  *.pkl
```

A `cpkt`, a `h5` és a `pkl` **kimarad** az őrből. Ez nem elméleti rés: az
upstream `README.md` szerint a `scripts/prepare_data_for_training.ipynb`
„creates the **`.h5`** files required for training" — vagyis a
licenc-blokkolt adathalmazból származtatott, legvalószínűbben a fába
tévedő artefaktum PONTOSAN az, amit az őr ma nem ismer fel. Ugyanez a `.pkl`-re.
A `cpkt` az upstream saját elgépelés-variánsa, amit ők maguk is védenek.

Az ADR 0369 D5 „fail-closed" ígérete így megkerülhető egy olyan úton, amit a
manifest maga dokumentál. **Javítás:** vedd fel a `cpkt`, `h5`, `pkl`
kiterjesztéseket a halmazba, és adj a B csoporthoz egy falszifikációs cellát a
`.h5`-re (pl. `ml/scratch/prepared_dataset.h5`). **Mérve, hogy a javítás nem
visz pirosra semmit:** `git ls-files | grep -Ei '\.(h5|pkl|cpkt)$'` a fán
**nulla** találat, tehát a valós-fa cella (`B` csoport első teszt) zöld marad.

### MINOR-1 — a manifest `requirements` listája az upstream `requirements.txt` 7/16-os részhalmaza, miközben gépi szerződésként fogyasztódik

`ml/reference/reference_manifest.json:69` · `ml/reference/run_reference_eval.py:190`

Az upstream `requirements.txt` (mérve, pinelt commit) **16** sort tartalmaz:
`librosa==0.10.1, numpy, numba, resampy, mir-eval, tqdm, torch, pandas,
note-seq, scipy, scikit-learn, h5py, hydra-core, lightning, wandb,
torchlibrosa`. A manifest ebből **7**-et sorol. A manifest a pinelt forrás
**gépi leírása**, és a `check_dependencies()` pontosan ezt a listát futtatja
végig — a hiányzó kilenc csomag ma nem derülne ki a fail-fast ellenőrzésen.

*A gyökérok részben a kör briefjében van:* a §0.0 A) táblázat „Függőségek"
sora maga is rövidített felsorolást adott. A javítás a manifest oldalán van.

Ugyanitt: a `_IMPORT_NAME_OVERRIDES` (`run_reference_eval.py:48`) a
`scikit-learn` → `sklearn` leképezést nem tartalmazza, tehát a lista
kiegészítése után a `scikit_learn` import **hamis „hiányzik" leletet** adna.
A kettőt EGYÜTT kell javítani.

### MINOR-2 — a `git` / `git lfs` alfolyamat hibája nem a szerződés szerinti típusos hiba, hanem nyers traceback

`ml/reference/run_reference_eval.py:222,243` · `:378`

A modul-docstring azt ígéri: *„A missing Python dependency or a missing on-disk
artifact is a typed, speaking error."* A `clone_pinned_commit` és a
`verify_checkpoint` viszont `subprocess.run(..., check=True)`-t hív, és a
`main()` `except` ága csak `(MissingArtifactError, NotImplementedError)`-t fog:

- nincs telepítve `git-lfs` → `FileNotFoundError`,
- hálózati hiba / elérhetetlen remote a `git clone`-on → `CalledProcessError`,

mindkettő **kezeletlenül** buborékol fel. Épp az a két hibaosztály, amit a
README a „fails fast with a typed error" mondattal ígér a felhasználónak.
**Javítás:** fogd be a `subprocess.CalledProcessError`/`OSError`-t, és fordítsd
`MissingArtifactError`-rá a hiány nevével + az újrafuttató paranccsal.

### MINOR-3 — a report jelen időben állít olyat a scriptről, ami ma nem igaz

`docs/eval/reference-model-audit.md:65`

> „**Reprodukáló parancs:** ugyanaz, mint fent — a script mindkét mérést egy
> futásban **állítja elő**, de KÜLÖN struktúrában…"

A `run_official_fixture_eval` és a `run_strumsight_holdout_eval` ma
`NotImplementedError`-t dob. A `ml/reference/README.md:80` ezt **kimondja és
megnevezi a folytatást** — a report, ami a kör NYILVÁNOS deliverable-je, nem.
Egy olvasó a reportból azt viszi el, hogy egy PyTorch-os gépen a parancs
azonnal számot ad. **Javítás:** a report §1/§2-be is kerüljön be ugyanaz a
kimondás, amit a README már tartalmaz (a két evaluátor ma stub, a notebook
cella-kimenet szerződésének kiolvasása a következő, PyTorch-képes kör dolga).

> **Megjegyzés a besoroláshoz:** magát a stub-állapotot NEM minősítem
> BLOCKER/MAJOR-nak. A 6/1. acceptance-pont egyparancsos futást és a **pinelt
> commit-hash használatát** kéri — ezt a script teljesíti (klón → pontos
> checkout → eltérésnél típusos hiba → LFS-pull → sha256-ellenőrzés). A mérés
> `NEM MÉRT` státuszát a brief §0.0 C/D kifejezetten engedi, az ADR 0369 D6
> pedig **tiltja** a nem ellenőrizhető nbconvert-kiolvasás vaktában
> megírását. A lelet ezért a **kommunikáció** pontatlansága, nem a szállított
> viselkedésé.

### NOTE-1 — egy ideiglenes teszt-repó takarítás nélkül marad

`test/tooling/reference_model_licence_guard_test.dart:212`

A `'a clean synthetic tree with no reference-origin artifact passes'` cella
`_newTempRepo()`-t hív **`addTearDown` nélkül** — a fájlban ez az egyetlen
ilyen hely, minden más temp-repós cella takarít. Futásonként egy ottfelejtett
könyvtár a `/tmp`-ben.

## 3. Verdikt

**CHANGES REQUESTED** — 1 MAJOR (MAJOR-1), 3 MINOR, 1 NOTE.

A kör tartalmi gerince — a három külön licenc-ítélet, a NO-GO, a fa-bejáró
fail-closed őr, a két mérés szétválasztása és a becslés-mentes report —
**helyes és jól mért**. A MAJOR-1 egy konkrét, a manifest által saját maga
dokumentált megkerülési út az őrön; a javítása kicsi és mérten nem visz
semmit pirosra. Javító kör indul a fenti leletlistával.

## 4. Javító kör utáni újra-ellenőrzés

*(a javító kör után töltendő)*
