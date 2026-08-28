# E12-R03 — GitHub delivery workflow, branch protection és review policy

- **Státusz:** READY (pre-flight újramérve 2026-08-28, `main @ f20ceec2` — lásd **§0.0.A**; az előre megírt változat 2026-08-27, `main @ 9ca4a0dc`)
- **Típus:** Chapter 12 (Release Roadmap, Sprint Planning & Final Integration), Kör 3
- **Kör-azonosító:** `E12-R03`
- **Branch:** `<motor>/e12-r03-delivery-workflow-and-branch-protection`
- **Előfeltétel:** `E12-R01` merge-elve (a blocker-nyilvántartás mezői az issue-sablonok mezőinek forrása)
- **Brief szerzője:** Claude (Opus 5)
- **Előre kiosztott ADR:** `ADR 0444` — a szám FOGLALT (Chapter 12 batch-tartomány).

**Visszakeresett előzmény:** `node tools/knowledge-rag.mjs --corpus lessons,halts,adr --top 5 "issue template pull request template CODEOWNERS branch protection required check"` → **[ADR 0050](../adr/0050-branch-per-round-pr-workflow.md) „Szóló-fejlesztői adaptációk"** (score 3.00): a „legalább 1 emberi review" szabály ebben a projektben NEM teljesíthető betű szerint, helyette az ügynöki second-eye review kötelező, a branch-protection formális beállítása pedig a user hatásköre. Ez a kör tehát NEM vezethet be olyan required reviewert, ami az autonóm kör-pipeline-t befagyasztaná.

> ⚠ **Pre-flight (indítás előtt KÖTELEZŐ):** olvasd újra a `.github/pull_request_template.md` TÉNYLEGES szakaszait (a megíráskor: SDD requirement/kör, cél és nem-cél, fő változások, migration/API hatás, tesztek pontos parancsokkal, evidence) — a kör BŐVÍTI, nem újraírja. Ellenőrizd az ADR 0050 „Szóló-fejlesztői adaptációk" szakaszának hatályát is; ha időközben változott, a §5.1 döntést újra kell indokolni.

## 0.0 A kör legfőbb korlátja — a pipeline nem fagyhat be

A repó autonóm kör-pipeline-nal dolgozik (`tools/round-pipeline.sh`, `docs/execution/pipeline-queue.tsv`): a PR-t a kör orchesztrátora nyitja és squash-merge-eli zöld gate mellett. Egy „required human reviewer" CODEOWNERS-szabály ezt DEADLOCK-ba vinné. A kör ezért a CODEOWNERS-t **jelölő** (notification/ownership) szerepben vezeti be, és a `docs/process/branch-protection.md` írja le, mely beállítás követel emberi jóváhagyást (ezek a user manuális döntései), és melyik automatizálható.

```ai-router
schema_version = 1
risk = "normal"
allowed_paths = [
  ".github/ISSUE_TEMPLATE/feature.yml",
  ".github/ISSUE_TEMPLATE/bug.yml",
  ".github/ISSUE_TEMPLATE/security.yml",
  ".github/ISSUE_TEMPLATE/migration.yml",
  ".github/ISSUE_TEMPLATE/release.yml",
  ".github/ISSUE_TEMPLATE/config.yml",
  ".github/CODEOWNERS",
  ".github/pull_request_template.md",
  "docs/process/backlog-policy.md",
  "docs/process/branch-protection.md",
  "tool/audit_repository_policy.py",
  "test/tooling/repository_policy_test.dart",
  "docs/rounds/e12-r03-delivery-workflow-and-branch-protection.md",
]
gate_tests = [
  "test/tooling/repository_policy_test.dart",
]
native_gate = false
```

## 0.0.A Pre-flight — MÉRT revízió (orchestrátor, Claude Opus 5, 2026-08-28, `main @ f20ceec2`)

**Ahol ez a szakasz mást állít, mint a brief régebbi szövege, EZ az irányadó.**
A brief 2026-08-27-én, `main @ 9ca4a0dc` állapotra készült; az alábbiakat a
kör indítása előtt újramértem.

### P1 — A PR-sablonban a `## Rollback` szakasz MÁR LÉTEZIK

```
$ grep -n '^## ' .github/pull_request_template.md
2:## SDD requirement / kör          16:## Tesztek (pontos parancsok …)
6:## Cél és nem-cél                 24:## Evidence
11:## Fő változások                 29:## Privacy / security hatás
13:## Migration / API hatás         33:## Rollback
                                    37:## Follow-up
```

A §3 „a PR-sablon bővítése **rollback + release-evidence** blokkal" tehát
pontosítva: a tényleges hozzáadás a **release-evidence blokk** (+ a P5 szerinti
release-asset sor). A `## Rollback` szakasz **megmarad, változatlan szereppel**;
elvesztése az A4 cellán regresszió. Az A4 bizonyítéka az, hogy a fenti **11
szakasz-fejléc MINDEGYIKE** megvan a kör után is, nem csak az új blokk.

### P2 — `package:yaml` TILOS (ADR 0444 D3)

```
$ grep -n '^  yaml' pubspec.yaml        → nincs találat (nem közvetlen függőség)
$ grep -n -A1 '^  yaml:' pubspec.lock   → 1262:    dependency: transitive
```

A `flutter_lints` `depend_on_referenced_packages` szabálya miatt egy
`import 'package:yaml/yaml.dart'` **pirosra váltaná a `flutter analyze`-t**, a
`pubspec.yaml` viszont a tilos zónán van → **H3**. Az öt issue-sablon ezért
**szándékosan szűkített GitHub issue-form YAML-részhalmazban** íródik, amit a
Dart guard SAJÁT, sor-alapú, hibára beszédes parsere olvas. A szűkített alakot
mondd ki a parser doc-commentjében ÉS a hibaüzenetében.

**Az A1 cella szövege ezzel pontosítva:** „parse-olható YAML" =
(a) a szűkített részhalmaznak megfelel és a Dart guard parsere hiba nélkül
olvassa (**ez a CI-kapu**), ÉS (b) a `tool/audit_repository_policy.py`
`PyYAML`-lel teljes YAML-ként is beolvassa (**operátor-oldali, független
mérés** — mérve: `PyYAML 6.0.1` elérhető). Az `import yaml` a Python-oldalon
**kemény**: hiányzó PyYAML esetén a script hangosan elszáll, nem esik vissza
csendben gyengébb ellenőrzésre.

### P3 — A CODEOWNERS öt területének MÉRT útvonalai

Létezés-ellenőrzéssel (`[ -e "$p" ]`) mérve, 2026-08-28:

| Terület | LÉTEZIK | NEM létezik |
|---|---|---|
| audio | `lib/core/audio/`, `lib/features/audio_analysis/`, `lib/features/live/`, `lib/features/tuner/` | — |
| backend | `backend/` | — |
| security | `lib/features/auth/`, `lib/core/storage/`, `lib/core/network/`, `docs/security/` | — |
| model | `lib/core/ml/`, `assets/ml/` | **`assets/models/`** |
| release | `.github/workflows/`, `android/`, `docs/release/` | — |

`assets/models/` NEM létezik — a mért név `assets/ml/`. Ez pontosan az a
fantom-minta, amit az A3 cellának pirosra kell váltania (ADR 0444 D4).
A `.github/workflows/`-ra írt CODEOWNERS-**minta** megengedett: a tilos zóna a
workflow-fájlok *tartalmának* módosítása, nem a rájuk hivatkozó ownership-sor.

### P4 — A severity-skála forrása `docs/release/blockers.md`, NEM `docs/execution/blockers.md`

A §3 „a `blockers.md` P0–P3 skálájával egyezően" hivatkozás mért útvonala
[`docs/release/blockers.md`](../release/blockers.md) „Severity-skála" szakasza
(P0/P1/P2 használatban, P3 fenntartva). A `docs/execution/blockers.md`
**nem létezik**. A `backlog-policy.md` ezt a négy szintet veszi át, a
`docs/release/blockers.md` szövegének átírása NÉLKÜL (az a fájl a tilos zónán van).

### P5 — ÚJ acceptance-cella: A7 (SDD Ch12 Kör 3 nyolcadik feladata)

A fejezet-szöveg feladatlistájának utolsó pontja — **„Tiltsd a release asset
változás magyarázat nélküli merge-ét"** — a brief §6-jából hiányzott. Pótolva
A7-ként (lásd §6); a fájllistát NEM tágítja, mert a PR-sablonban és a
`backlog-policy.md`-ben teljesül.

### P6 — Visszakeresés (ADR 0312)

- `--corpus lessons,halts,adr "issue template CODEOWNERS pull request template branch protection repository policy audit"`
  → **[ADR 0050](../adr/0050-branch-per-round-pr-workflow.md) „Szóló-fejlesztői
  adaptációk"** (score 3.00, `bm25#1 emb#1`) — a §5.1/D1 normatív alapja.
- `--corpus lessons,halts "YAML parser Dart teszt fixture nélküli külső csomag guard teszt statikus audit script"`
  → **[L260](../LESSONS.md#l260)** (kulcsnév-listára épülő teszt vakon zöld),
  **[L110](../LESSONS.md#l110)** (`Process.run('rg', …)` a boxon zöld, CI-n
  piros → a guard **tiszta Dart fájlolvasás** legyen, ne shell-eljen ki),
  **[L476](../LESSONS.md#l476)** (sor-alapú guard szerkezetileg vak).
- Teljes korpusz: a top-5 a kör SAJÁT briefjét és scope-audit-részleteket
  hozott — **nincs további releváns előzmény**.

**A három lecke kötelező következménye erre a körre:** (1) a guard NEM hívhat
külső binárist (`rg`, `python3`, `gh`) — tiszta `dart:io` fájlolvasás (L110);
(2) a kötelező mezők ellenőrzése nem merülhet ki egy kulcsnév-lista
`contains`-ében, a cellának a **hiányzó mezőt** kell pirosra mérnie fixture-ből
(L260); (3) a §6 valódi-sértés próbája nem hagyható el (L476).

## 0. Kör-jelzés és STOP-protokoll

```bash
tools/codex-signal.sh progress "<egy sor>"
tools/codex-signal.sh done "<egy sor>"
tools/codex-signal.sh stopped "<egy sor>"
tools/codex-signal.sh blocked "<egy sor>"
```

**STOP-protokoll:** ha a §3 scope-jához olyan fájl kellene, ami a §4 listáján nincs rajta (különösen `.github/workflows/**`), a kimenet a `stopped` jelzés és brief-revízió kérése — a lista csendes tágítása TILOS ([L478](../LESSONS.md#l478)).

## 1. Cél

Egységes backlog-, PR-evidence- és ownership-szabály, gépileg auditálható repository-policy — az autonóm kör-pipeline befagyasztása nélkül.

## 2. Jelenlegi állapot — mért tények

- `.github/pull_request_template.md` **létezik** és MÁR tartalmazza az SDD-kör, cél/nem-cél, migration/API, „tesztek pontos parancsokkal (soha `&&`)" és evidence szakaszokat. A kör ezt **bővíti** (rollback + release-evidence blokk), nem cseréli.
- `.github/ISSUE_TEMPLATE/` **nem létezik**; `.github/CODEOWNERS` **nem létezik**; `docs/process/` **nem létezik**.
- `.github/workflows/` 10 workflow; a merge-kaput a `build-apk.yml` / `full-gate.yml` pár adja (`tools/round-ci-plan.py` választ közöttük a brief `native_gate` mezőjéből).
- A folyamat-szabályok ma `docs/execution/05-branch-and-pr-rules.md`-ben és az ADR 0050-ben élnek — a kör ezekre HIVATKOZIK, nem másolja őket.
- `tool/` Python-eszközt ma nem tartalmaz (csak `.dart` fájlokat + `tool/ci`, `tool/benchmarks` könyvtárat); a `tool/audit_repository_policy.py` az első ilyen. A backend Python-konvenciója (`ruff`) a `backend/` fára van kötve — a `tool/` fa ruff-ellenőrzése NEM ennek a körnek a dolga.

## 3. Scope

**Benne van:** öt issue-sablon (feature, bug, security, migration, release) kötelező mezőkkel (Chapter, kör, privacy-hatás, rollback, teszt, acceptance) · `config.yml` a blank-issue tiltásához · `.github/CODEOWNERS` audio/backend/security/model/release területekre, **jelölő** szerepben · a PR-sablon bővítése rollback + release-evidence blokkal · `docs/process/backlog-policy.md` (label- és severity-rendszer, a `blockers.md` P0–P3 skálájával egyezően) · `docs/process/branch-protection.md` (elvárt beállítások, és melyik igényel manuális user-döntést) · `tool/audit_repository_policy.py` (a sablonok és a CODEOWNERS statikus auditja, `--dry-run` alapértelmezéssel, GitHub API-hívás NÉLKÜL) · `test/tooling/repository_policy_test.dart` (a sablonok kötelező mezőit és a CODEOWNERS mintáit fixture-ként méri).

**NINCS benne (tilos):**

- **`.github/workflows/**` bármely fájljának módosítása** — a merge-gate workflow változtatása külön, ADR 0052/0053 hatálya alatti kör.
- Tényleges GitHub branch-protection API-hívás vagy `gh` futtatása az implementer részéről.
- Olyan CODEOWNERS/branch-protection szabály, ami emberi review-t tesz a merge FELTÉTELÉVÉ (a §5.1 tiltja).
- `docs/adr/**` — az ADR 0444-et a Claude írja.

## 4. Engedélyezett fájlok

| Útvonal | Indok |
|---|---|
| `.github/ISSUE_TEMPLATE/{feature,bug,security,migration,release}.yml` | ÚJ — az öt sablon |
| `.github/ISSUE_TEMPLATE/config.yml` | ÚJ — blank issue tiltása |
| `.github/CODEOWNERS` | ÚJ — jelölő ownership |
| `.github/pull_request_template.md` | BŐVÍTÉS — rollback + release evidence |
| `docs/process/backlog-policy.md` | ÚJ — label/severity policy |
| `docs/process/branch-protection.md` | ÚJ — elvárt beállítások + manuális döntési pontok |
| `tool/audit_repository_policy.py` | ÚJ — statikus policy-audit |
| `test/tooling/repository_policy_test.dart` | a §6 cellái |

**Tilos zóna:** `.github/workflows/**` · `.github/actions/**` · `docs/execution/**` · `docs/adr/**` · `lib/**` · `backend/**` · `tools/**`

## 5. Kötött architekturális döntések (ADR 0444)

> A normatív forrás: [`docs/adr/0444-delivery-workflow-and-repository-policy.md`](../adr/0444-delivery-workflow-and-repository-policy.md)
> (D1–D6), amit az orchestrátor a pre-flightban írt. **Ezt a fájlt az
> implementer NE módosítsa** (a `docs/adr/**` a tilos zónán van). Az alábbi
> §5.1/§5.2 a D1 és a D2 rövidített alakja.

### 5.1 A CODEOWNERS jelöl, nem kapuz

A CODEOWNERS célja a felelős terület megjelölése és az értesítés. **NEM elfogadható gyengítés:** „a biztonság kedvéért" bevezetett `required_approving_review_count ≥ 1` ajánlás a `branch-protection.md`-ben úgy, hogy közben a kör-pipeline squash-merge-öl — az ADR 0050 adaptációja szerint az emberi review a user OPCIÓJA, a kötelező second-eye pedig az ügynöki reviewer. A dokumentum ezt írja le, nem mást.

### 5.2 A policy-audit statikus és offline

Az `audit_repository_policy.py` a repó FÁJLJAIT olvassa; hálózatot nem hív. **NEM elfogadható gyengítés:** GitHub API-hívás beépítése „ha van token" feltétellel — a tokenes ág néma no-op lenne CI-ban, és pontosan az a hibaosztály, amit a repó `try/catch`-elt cloud-írás tanulsága tilt.

## 6. Acceptance criteria

| # | Kritérium | Bizonyíték |
|---|---|---|
| A1 | Mind az öt issue-sablon a §0.0.A P2 szűkített issue-form YAML-részhalmazának megfelel (a Dart guard parsere hiba nélkül olvassa), ÉS MINDEGYIK tartalmazza a kötelező mezőket (Chapter, kör, acceptance, teszt, rollback, privacy). A teljes YAML-érvényesség független, operátor-oldali mérése az A5 (PyYAML). | `repository_policy_test.dart` — a hiányzó mezőt **fixture-ből** kell pirosra mérni, nem kulcsnév-lista `contains`-szel ([L260](../LESSONS.md#l260)) |
| A2 | Blank issue tiltott (`config.yml` `blank_issues_enabled: false`) | `repository_policy_test.dart` |
| A3 | A CODEOWNERS mintái a MÉRT fa útvonalaira illeszkednek (audio, backend, security, model, release), és egyik sem hivatkozik nem létező könyvtárra | `repository_policy_test.dart` |
| A4 | A PR-sablon rollback ÉS release-evidence szakaszt tartalmaz, a meglévő szakaszok elvesztése nélkül | `repository_policy_test.dart` |
| A5 | `tool/audit_repository_policy.py --dry-run` hálózat nélkül fut le, és hiányzó kötelező mezőre nem-nulla kóddal lép ki | a §7 parancs kimenete a §10-ben |
| A6 | Sem a CODEOWNERS, sem a `branch-protection.md` nem ír elő emberi jóváhagyást a merge feltételeként | `repository_policy_test.dart` tiltott-minta cellája |
| A7 | **(ÚJ — §0.0.A P5)** A release asset változása magyarázat nélkül nem mehet be: a PR-sablon kötelezően kitöltendő release-asset sort tartalmaz, és a `backlog-policy.md` kimondja a szabályt | `repository_policy_test.dart` (a sablon-szakasz megléte) |
| A8 | **(ÚJ — §0.0.A P6)** A guard tiszta `dart:io` fájlolvasással dolgozik: nincs benne `Process.run` / `Process.runSync` külső binárisra (`rg`, `python3`, `gh`) — ez a boxon zöld / CI-n piros hibaosztály ([L110](../LESSONS.md#l110)) | `repository_policy_test.dart` önvédő cellája a saját forrására |

### 6.1 Mérce-mátrix — melyik hibás implementációt melyik cella fogja pirosra

| Hibás implementáció | Melyik cella vált PIROSRA |
|---|---|
| Egy sablonból kimarad a `rollback` mező | A1 |
| A CODEOWNERS `lib/audio/**` mintát ír (a fán `lib/core/audio/**` van) | A3 |
| A PR-sablon átírásakor eltűnik a „tesztek pontos parancsokkal" szakasz | A4 |
| A `branch-protection.md` „legalább 1 approving review kötelező" sort tartalmaz | A6 |
| Az audit script hálózatot hív, ha talál tokent | A5 (a teszt hálózat nélkül futtatja) |
| A CODEOWNERS `assets/models/**` mintát ír (a fán `assets/ml/` van — §0.0.A P3) | A3 |
| A PR-sablonból kimarad a kötelező release-asset sor | A7 |
| A guard `Process.run('rg', …)`-gal keresi a mezőket | A8 (a boxon zöld lenne, CI-n piros — L110) |
| Az issue-sablon a Dart parser által NEM olvasható alakot használ (pl. inline flow-map) | A1 (a parser hangosan hibázik, nem csendben átugorja) |

**Valódi-sértés próba (KÖTELEZŐ, a §10-ben dokumentálva):** vedd ki a `bug.yml`-ből a `rollback` mezőt, futtasd a §7 gate-et → az **A1** cellának PIROSNAK kell lennie → állítsd vissza.

## 7. Kötelező ellenőrzések

```bash
tools/round-gate.sh test/tooling/repository_policy_test.dart
```

A policy-audit közvetlen futtatása (a kimenet a §10-be):

```bash
python3 tool/audit_repository_policy.py --dry-run
```

CI-dispatch, PR és merge kizárólag orchesztrátor-oldal — az implementer `gh`-t nem hív.

## 8. Implementációs sorrend

1. `docs/process/backlog-policy.md` — a label/severity rendszer (a `blockers.md` skálájához kötve).
2. Az öt issue-sablon + `config.yml`.
3. `.github/CODEOWNERS` a MÉRT fa útvonalaira.
4. PR-sablon bővítés.
5. `tool/audit_repository_policy.py`.
6. `test/tooling/repository_policy_test.dart` — a §6 A1–A8 cellái + a §6.1
   mátrix MINDEN sora + a valódi-sértés próba a §10-be.
7. `docs/process/branch-protection.md` — a §5.1 korlátjával.

## 9. Kockázatok

- **A pipeline befagyasztása.** A legsúlyosabb kockázat: egy required-review szabály a squash-merge-öt blokkolná (A6).
- **A CODEOWNERS fantom-útvonalai.** Nem létező könyvtárra írt minta némán semmit nem fed — ugyanaz a hibaosztály, amit a brief-lint S13 mér a briefekre (A3).
- **A PR-sablon regressziója.** Az átírás könnyen elveszti a meglévő, mért értékű szakaszokat (A4).

## 10. Implementation handoff — az implementer tölti ki

## 11. Review — a Claude tölti ki
