# Branch protection — elvárt beállítások és manuális döntési pontok

- **Kör:** `E12-R03` — GitHub delivery workflow, branch protection és review policy
- **Normatív döntés:** [ADR 0444](../adr/0444-delivery-workflow-and-repository-policy.md) D1
- **Hatály:** `main` branch GitHub-oldali védettsége.

## 1. A kötött korlát — a merge kapuja nem változik

Ez a dokumentum **nem ad hozzá** és **nem javasol** új merge-feltételt. A
merge egyetlen kapuja változatlanul a zöld CI (ADR 0052): a `full-gate` /
`build-apk` és a `router-ci` required status check. A repó autonóm
kör-pipeline-ja (`tools/round-pipeline.sh`) a PR-t maga nyitja és
squash-merge-eli, amint ez a kapu zöld — emberi jóváhagyó a merge útjában
nincs, és az [ADR 0050](../adr/0050-branch-per-round-pr-workflow.md)
„Szóló-fejlesztői adaptációk" 1. pontja szerint nem is lehet.

## 2. Automatizálható és kötelező: a required status check

| Beállítás | Elvárt érték | Ki dönt |
|---|---|---|
| Required status check | a merge-gate workflow (`full-gate` vagy `build-apk`, a kör `native_gate` mezőjétől függően) + `router-ci` | automatizálható, kötelező |
| Branch, amire vonatkozik | `main` | automatizálható, kötelező |
| Force-push tiltása `main`-re | igen | automatizálható, kötelező |
| Branch törlésének tiltása | igen | automatizálható, kötelező |

Ez a négy sor **automatán bekapcsolható** GitHub Administration-jogú
tokennel vagy a repó Settings felületén, és nem fagyasztja be a
kör-pipeline-t: egyik sem vár emberi cselekvésre a squash-merge előtt.

## 3. A user OPCIONÁLIS döntése: a review-mező

A GitHub branch protection UI-ja egy `approving review szám` mezőt is felkínál.
Ez a repóban **NEM automatizálható kötelezővé** — az ADR 0050 „Szóló-fejlesztői
adaptációk" 1. pontja szerint az egyszemélyes projektben ez a mező
szerkezetileg nem tölthető ki úgy, hogy a pipeline ne fagyjon be. A
kötelező second-eye ehelyett az **ügynöki reviewer** (Claude review-köre,
`docs/reviews/`), a user saját GitHub-review-ja pedig **opció marad**: ha a
user él vele, az a normál GitHub-folyamat, de a mező bekapcsolása **user
hatáskör**, nem ennek a dokumentumnak vagy egy automatizált scriptnek a
döntése.

Az [ADR 0050](../adr/0050-branch-per-round-pr-workflow.md) „Szóló-fejlesztői
adaptációk" 2. pontja szerint a `main` tényleges GitHub-oldali védettsége is
addig **dokumentált elvárás** marad, amíg a használt token nem kap
Administration jogot — ez a korlát itt van kimondva, nem elfedve.

## 4. Amit a CODEOWNERS ehhez hozzátesz

A `.github/CODEOWNERS` (ADR 0444 D1) a felelős terület **jelölésére és
GitHub-értesítésre** szolgál öt területen (audio, backend, security, model,
release) — nem hoz létre és nem is hozhat létre saját jóváhagyási
feltételt. A CODEOWNERS és a branch protection egymástól függetlenül
konfigurálható; egyik sem teszi a másikat a merge feltételévé.

## 5. Live ellenőrzés — operátori lépés, nem script-ág

A `tool/audit_repository_policy.py --dry-run` a fenti táblázatot **statikusan**
auditálja (a dokumentum tartalmát, nem a GitHub API élő állapotát — ADR
0444 D2). A tényleges élő állapot lekérdezéséhez szükséges parancsot a
script **kiírja, de nem futtatja**:

```bash
gh api repos/wolfcasaba/strumsight/branches/main/protection
```

Ezt a parancsot Administration-jogú tokennel az operátor futtatja, amikor a
tényleges GitHub-oldali beállítást akarja bekapcsolni vagy ellenőrizni — az
implementer és az automatizált audit egyaránt csak dokumentál, hálózatot nem
hív.
