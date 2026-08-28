# ADR 0444 — Delivery workflow, ownership és repository policy: jelölő CODEOWNERS, offline policy-audit

- **Státusz:** Elfogadva (E12-R03 pre-flight, 2026-08-28)
- **Kör:** `E12-R03` — GitHub delivery workflow, branch protection és review policy
- **Implementer motor:** `sonnet-impl` (Claude Sonnet 5, `--effort high`)
- **Epic / fejezet:** [Chapter 12 — Release Roadmap, Sprint Planning & Final
  Integration](../sdd/12-release-roadmap-final-integration.md) Kör 3
- **Az ADR-t az orchestrátor (Claude Opus 5) írta a pre-flightban**, a
  [`docs/rounds/e12-r03-delivery-workflow-and-branch-protection.md`](../rounds/e12-r03-delivery-workflow-and-branch-protection.md)
  brief §5 kötött döntéseinek normatív forrásaként.

## Kontextus — a MÉRT állapot és a MÉRT hibaosztály

A repó **autonóm kör-pipeline-nal** dolgozik (`tools/round-pipeline.sh`,
`docs/execution/pipeline-queue.tsv`): a PR-t a kör orchesztrátora nyitja, és
zöld gate mellett **maga squash-merge-eli**. Emberi jóváhagyó a merge útjában
nincs — és nem is lehet, mert az [ADR 0050](0050-branch-per-round-pr-workflow.md)
„Szóló-fejlesztői adaptációk" 1. pontja kimondja: a „legalább 1 review" szabály
egyszemélyes projektben **nem teljesíthető betű szerint**, helyette a kötelező
second-eye az **ügynöki reviewer**, a user review-ja pedig **opció**.

A pre-flight mérése (`main @ f20ceec2`, 2026-08-28):

```
.github/pull_request_template.md   LÉTEZIK  (11 szakasz, köztük MÁR "## Rollback")
.github/ISSUE_TEMPLATE/            NEM LÉTEZIK
.github/CODEOWNERS                 NEM LÉTEZIK
docs/process/                      NEM LÉTEZIK
tool/                              csak .dart fájlok + tool/ci, tool/benchmarks, …
```

A hibaosztály, amit ez a kör el akar kerülni, kettő, és mindkettő **mért
precedensre** épül:

1. **A pipeline befagyasztása.** Egy CODEOWNERS-alapú
   `required_approving_review_count ≥ 1` szabály DEADLOCK-ba vinné az autonóm
   láncot: a merge-re várna egy emberi jóváhagyó, aki az ADR 0050 szerint
   szándékosan nincs a merge útjában. Ez nem „szigorúbb mérce" lenne, hanem a
   lánc leállása.
2. **A néma no-op ág.** Egy „ha van token, hívjuk a GitHub API-t" feltételes
   ág CI-ban **csendben kihagyódna**, és pontosan úgy nézne ki, mint egy
   sikeres audit. Ez ugyanaz a hibaosztály, amit a repó a `try/catch`-elt
   cloud-írás tanulságából (CLAUDE.md „Cloud writes swallowed by `try/catch`")
   és az [L260](../LESSONS.md#l260) vakon zöld redakciós tesztből már ismer.

## Döntés

### D1 — A CODEOWNERS **jelöl**, nem kapuz

A `.github/CODEOWNERS` szerepe a felelős terület megjelölése és az értesítés.
Sem a CODEOWNERS, sem a `docs/process/branch-protection.md` **nem írhat elő
emberi jóváhagyást a merge feltételeként**.

**NEM elfogadható gyengítés:** „a biztonság kedvéért" bevezetett
`required_approving_review_count ≥ 1` ajánlás a `branch-protection.md`-ben,
miközben a kör-pipeline squash-merge-öl. A dokumentum azt írja le, ami az
ADR 0050 adaptációjából következik: a **required status check** (a zöld kapu:
`full-gate` / `build-apk` + `router-ci`) automatizálható és kötelező, a
**required human approval** pedig a user manuális, opcionális döntése.

A merge kapuja változatlanul az [ADR 0052](0052-ci-green-gate.md) zöld kapuja.

### D2 — A policy-audit **statikus és offline**; a hálózati ág nem „opcionális", hanem TILOS

A `tool/audit_repository_policy.py` a repó **FÁJLJAIT** olvassa: az
issue-sablonokat, a `config.yml`-t, a `.github/CODEOWNERS`-t, a
`.github/pull_request_template.md`-t és a `docs/process/branch-protection.md`-t.
Hálózatot **nem hív**, `gh`-t nem futtat, tokent nem olvas.

**NEM elfogadható gyengítés:** GitHub API-hívás beépítése „ha van token"
feltétellel — a tokenes ág néma no-op lenne (D1 kontextus 2. pontja).

Az SDD Ch12 Kör 3 „Adj scriptet a branch protection elvárt beállításainak
auditálására, **ahol API jogosultság elérhető**" feladata ezzel teljesül és
nem sérül: a script a **dokumentált elvárt beállításokat** auditálja
(léteznek-e, ellentmondásmentesek-e, nem sértik-e a D1-et), és a live
verifikációhoz szükséges `gh api` parancsot **kiírja, de nem futtatja** — az
Administration-jogú ellenőrzés operátori lépés, nem script-ág.

A `--dry-run` az **alapértelmezés**: a script sosem ír a repóba. Hiányzó
kötelező mezőre, fantom CODEOWNERS-útvonalra vagy D1-sértő sorra **nem-nulla
kilépési kóddal** áll meg.

### D3 — A Dart guard SAJÁT, szűkített, sor-alapú parsert használ; `package:yaml` TILOS

**Mérve a pre-flightban** (ugyanaz a mérés, mint
[ADR 0443](0443-sdd-index-machine-checkable-contract.md) D3): a `yaml` csomag a
`pubspec.lock`-ban `dependency: transitive` (`pubspec.lock:1261-1264`), a
`pubspec.yaml`-ben **nincs** deklarálva, és a `flutter_lints`
`depend_on_referenced_packages` szabálya miatt egy `import 'package:yaml/yaml.dart'`
**pirosra váltaná a `flutter analyze`-t**. A `pubspec.yaml` a kör tilos zónáján
van, tehát a dependency deklarálása **H3**.

Az öt issue-sablon ezért egy **szándékosan szűkített GitHub issue-form
YAML-részhalmazban** íródik, amit a `test/tooling/repository_policy_test.dart`
saját, **hibára beszédes** sor-alapú parserrel olvas. A szűkített alakot a
parser doc-commentje és a hibaüzenete is kimondja.

**Két, egymástól független mérés — szándékosan:** a Dart guard a CI-kapu (a
szűkített részhalmazt méri, `package:yaml` nélkül), a
`tool/audit_repository_policy.py` pedig operátor-oldalon a **teljes**
YAML-érvényességet méri `PyYAML`-lel (mérve: `PyYAML 6.0.1` elérhető ezen a
boxon). A Python-oldal `import yaml`-je **kemény**: hiányzó PyYAML esetén a
script hangosan elszáll, nem esik vissza csendben egy gyengébb ellenőrzésre.

### D4 — Fantom-útvonal tilalom: minden CODEOWNERS-minta a MÉRT fára mutat

Egy nem létező könyvtárra írt CODEOWNERS-minta **némán semmit nem fed** — a
fájl érvényes, a szabály hatástalan. A guard-teszt ezért minden mintához
megköveteli, hogy a repóban létező útvonalra illeszkedjen.

A pre-flight MÉRTE a lefedendő öt terület tényleges útvonalait:

| Terület | MÉRT, létező útvonalak |
|---|---|
| audio | `lib/core/audio/`, `lib/features/audio_analysis/`, `lib/features/live/`, `lib/features/tuner/` |
| backend | `backend/` |
| security | `lib/features/auth/`, `lib/core/storage/`, `lib/core/network/`, `docs/security/` |
| model | `lib/core/ml/`, `assets/ml/` |
| release | `.github/workflows/`, `android/`, `docs/release/` |

`assets/models/` **NEM létezik** (a mért név `assets/ml/`) — pontosan az a
fantom-minta, amit a D4 tilt.

A CODEOWNERS `.github/workflows/`-ra írt **mintája** nem a workflow-fájlok
módosítása: a tilos zóna a `.github/workflows/**` fájljainak *tartalma*, nem a
rájuk hivatkozó ownership-sor.

### D5 — A PR-sablon BŐVÜL, nem íródik újra

**Mérve:** a `.github/pull_request_template.md` MÁR tartalmaz `## Rollback`
szakaszt. A kör tényleges hozzáadása tehát a **release-evidence blokk**, plusz
az SDD Ch12 Kör 3 „Tiltsd a release asset változás magyarázat nélküli
merge-ét" feladatának megfelelő, kötelezően kitöltendő release-asset sor.

A meglévő szakaszok elvesztése **regresszió**, amit gépi cella mér: a guard a
sablon MINDEN mért szakasz-fejlécét megköveteli, nem csak az újakat.

### D6 — A guard logikája top-level, tartalom-paraméteres; a hibás bemenetet fixture adja

A `repository_policy_test.dart` cellái olyan bemenetekre is mérnek (hiányzó
kötelező mező, fantom CODEOWNERS-útvonal, D1-sértő `branch-protection.md`
sor), amiket a repó valódi tartalmán nem lehet előállítani. A parser és a
szabály-ellenőrzők ezért **top-level, tartalom-paraméteres** függvények,
amiket a teszt fixture-szöveggel is meg tud hívni — nem a fájlrendszerre
drótozott, csak `main()`-ből futtatható logika.

Az [L476](../LESSONS.md#l476) tanulsága kötelezően érvényes: egy sor-alapú
guard szerkezetileg vak lehet arra az alakra, amit a valóság előállít — ezért
a §6 valódi-sértés próbája nem elhagyható.

## Következmények

- A `main` védettsége a `docs/process/branch-protection.md`-ben **dokumentált
  elvárás** marad, amíg a token nem kap Administration jogot (ADR 0050
  „Szóló-fejlesztői adaptációk" 2. pont) — a dokumentum ezt a korlátot
  kimondja, nem elfedi.
- Az autonóm kör-pipeline **nem lassul és nem fagy be**: a kör egyetlen
  merge-feltételt sem ad hozzá a zöld kapuhoz.
- Az öt issue-sablon kötelező mezői (Chapter, kör, acceptance, teszt,
  rollback, privacy) a `docs/release/blockers.md` P0–P3 severity-skálájával
  közös nyelvet kapnak a `docs/process/backlog-policy.md`-ben.
- A `tool/` fa első Python-fájlját kapja. A `tools/round-gate.sh` `format` és
  `analyze` lépése Dart-only (`dart format … lib test tool`,
  `flutter analyze lib/ test/ tool/`), tehát a `.py` fájlt nem méri; a
  `backend/` ruff-sávja pedig a `backend/` fára van kötve — a `tool/` fa
  ruff-ellenőrzése **nem ennek a körnek a dolga**.

## Alternatívák, amiket elvetettünk

| Alternatíva | Miért nem |
|---|---|
| `required_approving_review_count ≥ 1` a branch-protection ajánlásban | DEADLOCK az autonóm kör-pipeline-nal; szemben az ADR 0050 adaptációjával (D1) |
| GitHub API-hívás „ha van token" feltétellel az auditban | Néma no-op ág CI-ban — a mért `try/catch`-elt cloud-írás hibaosztálya (D2) |
| `package:yaml` a sablonok olvasásához | Transitive dependency; `depend_on_referenced_packages` → piros `flutter analyze`; a `pubspec.yaml` a tilos zónán (H3) → D3 |
| Csak a Python audit, Dart guard nélkül | A CI-kapu Dart-oldali; a Python script nem fut a `round-gate.sh`-ban, tehát nem tudna pirosra váltani |
| Csak a Dart guard, Python audit nélkül | Az SDD Ch12 Kör 3 nevesíti a `tool/audit_repository_policy.py`-t; a teljes YAML-érvényesség független mérése is elveszne (D3) |
| A PR-sablon újraírása | A mért 11 szakasz elvesztése regresszió (D5) |
| `.github/workflows/**` hozzáigazítása (required check nevek) | ADR 0052/0053 hatálya, külön kör; a kör tilos zónája |

## Hivatkozások

- [ADR 0050](0050-branch-per-round-pr-workflow.md) — „Szóló-fejlesztői
  adaptációk" 1. és 2. pont (D1)
- [ADR 0052](0052-ci-green-gate.md) — a zöld kapu, ami a merge egyetlen
  feltétele marad
- [ADR 0443](0443-sdd-index-machine-checkable-contract.md) D3 — ugyanaz a
  `package:yaml` mérés (D3)
- [`docs/sdd/12-release-roadmap-final-integration.md`](../sdd/12-release-roadmap-final-integration.md) Kör 3
- [`docs/release/blockers.md`](../release/blockers.md) — a P0–P3 severity-skála
  forrása
- [`docs/execution/05-branch-and-pr-rules.md`](../execution/05-branch-and-pr-rules.md)
  — a branch/commit/PR szabályok, amikre a kör hivatkozik (nem másolja)
- [L260](../LESSONS.md#l260), [L476](../LESSONS.md#l476) — vakon zöld guard
  hibaosztályok (D2, D6)
