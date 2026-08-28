# Program baseline — StrumSight

**Mérés SHA-ja:** `main @ 92576977` (`chore(pipeline): a Chapter 12 sáv AKTIVÁLÁSA …`, 2026-08-28 01:42:55 +0200).
**Mérte:** E12-R01 implementer (Claude Sonnet 5), a kör munkapéldányában
(`/home/ubuntu/ss-sonnet-impl-e12-r01`), 2026-08-28. A méréshez vezető
egyetlen köztes commit (`8132ed01`, docs-only, csak
`docs/rounds/e12-r01-...md`-t érinti) egyetlen itt idézett tényt sem mozdít —
lásd `git show --stat 8132ed01`.

Minden állítás alakja `<állítás> — <fájl>:<sor>` vagy `<állítás> — <parancs>
kimenete`, a §5.1 kötött formája szerint (E12-R01 brief). A GitHub
Releases-leltárt igénylő állítások kivételt képeznek: azokat az implementer
nem futtatta újra (a brief §7 tiltja a `gh` hívását), a forrásuk az
orchestrátor pre-flight mérése — ezt minden ilyen helyen külön jelölöm.

## 1. Alkalmazás-azonosság

| Tulajdonság | Érték | Bizonyíték |
|---|---|---|
| Csomagnév (pubspec) | `strumsight` | `grep -n "^name:" pubspec.yaml` kimenete → `pubspec.yaml:1` `name: strumsight` |
| Verzió | `1.0.0+1` | `grep -n "^version:" pubspec.yaml` kimenete → `pubspec.yaml:5` `version: 1.0.0+1` |
| Android `namespace` | `com.wolfcasaba.strumsight` | `android/app/build.gradle.kts:73` |
| Android `applicationId` | `com.wolfcasaba.strumsight` (azonos a namespace-szel) | `android/app/build.gradle.kts:89` |
| Package ID eredete | ADR 0051 (StrumSight application identifiers) | `docs/adr/0051-strumsight-application-identifiers.md` (fájl létezik) |

A projekt **a mérés pillanatáig egyszer sem emelt build numbert** egy
publikus kiadáshoz: a `pubspec.yaml:5` build-száma ma is `1` (`1.0.0+1`),
miközben 26 GitHub Release és 27 git tag létezik (lásd
`release-history-audit.md`). A `build-NN` tagnevek a projekt SDD előtti
belső kör-számozását hordozzák, NEM a pubspec build számát — ez a két tény
csak együtt értelmezhető, külön-külön ellentmondásnak tűnnének.

## 2. CI-kapuk — `.github/workflows/`

**10 workflow fájl** — `ls .github/workflows/ | wc -l` kimenete → `10`;
`ls .github/workflows/` kimenete:

| Fájl | Trigger | Cél (1 sor a fájl fejlécéből/tartalmából) |
|---|---|---|
| `backend-ci.yml` (49 sor) | `workflow_dispatch` + push a `backend/**`-re | Backend (FastAPI) CI — `.github/workflows/backend-ci.yml:1-9` |
| `build-apk.yml` | `workflow_dispatch` | Teljes mérce-lánc + release APK build, ADR 0086 szerint csak dispatch, nincs automatikus `main`-push trigger — `.github/workflows/build-apk.yml:1-19` |
| `chord-train.yml` (119 sor) | `workflow_dispatch` + push a `ml/chords/**`-re | ML chord-modell tréning x86 CI-n — `.github/workflows/chord-train.yml:1-19` |
| `dsp-probe.yml` (48 sor) | `workflow_dispatch` | Valós-audio DSP próba SoundCloud korpuszon — `.github/workflows/dsp-probe.yml:1-11` |
| `full-gate.yml` | `workflow_dispatch` | A teljes mérce-lánc APK-build NÉLKÜL (ADR 0171 §3) — `.github/workflows/full-gate.yml:1-19` |
| `lab-apk.yml` (41 sor) | push a `lab_build.json`-ra + `workflow_dispatch` | „Lab mode" diagnosztikai APK build — `.github/workflows/lab-apk.yml:1-19` |
| `ml-train.yml` (79 sor) | `workflow_dispatch` | Strum-irány honest-measurement sweep x86 CI-n — `.github/workflows/ml-train.yml:1-9` |
| `release-apk.yml` (174 sor) | `workflow_dispatch` | Production Android APK, fail-closed signing — részletezve alább (§3) — `.github/workflows/release-apk.yml:1-11` |
| `router-ci.yml` (69 sor) | `workflow_dispatch` + path-filtered push | A `tools/round-gate.sh`-t hívó MiniMax-router saját Python teszt-sávja (ADR 0088) — `.github/workflows/router-ci.yml:1-13` |
| `tutor-eval.yml` (41 sor) | `workflow_dispatch` + path-filtered push | AI-tutor safety/claim-provenance/eval merge-gate (E04-R23) — `.github/workflows/tutor-eval.yml:1-9` |

`release-apk.yml` sorszáma külön mérve: `wc -l .github/workflows/release-apk.yml` kimenete → `174 .github/workflows/release-apk.yml`.

## 3. Production release build — `release-apk.yml`

- **`signing-prerequisites` job** (`.github/workflows/release-apk.yml:9-36`):
  `ANDROID_KEYSTORE_BASE64`, `ANDROID_STORE_PASSWORD`, `ANDROID_KEY_ALIAS`,
  `ANDROID_KEY_PASSWORD` — bármelyik hiányzik, a job `exit 1`-gyel bukik
  (`.github/workflows/release-apk.yml:29-35`). A `release-apk` és `coverage`
  job mindkettő `needs: signing-prerequisites`
  (`.github/workflows/release-apk.yml:39`, `:153`) — tehát a teljes futás
  fail-closed a hiányzó production signing secretekre.
- **`<version>+<build>` alak kényszerítve regexszel**:
  `.github/workflows/release-apk.yml:88` —
  `^([0-9A-Za-z][0-9A-Za-z._-]*)\+([0-9]+)$`; ha nem illeszkedik, a job
  `::error::`-ral bukik (`.github/workflows/release-apk.yml:89-90`).
- **Az artifact-név mintája**: `strumsight-<version>-<build>-<7 karakteres SHA>-production.apk`
  (`.github/workflows/release-apk.yml:95`).
- **`STRUMSIGHT_REQUIRE_RELEASE_SIGNING=true`** a build lépésen
  (`.github/workflows/release-apk.yml:119`) — ez a Gradle oldali kényszert
  (lásd §4) is bekapcsolja ugyanabban a futásban.

**Ebből következik:** a Kör 6/7 (production signing / secret hardening,
`docs/execution/pipeline-queue.tsv:503`, `E12-R07`) **nem nulláról indul** —
a workflow-oldali fail-closed kényszer már megvan; ami hiányzik, az a
tényleges GitHub secretek megléte (ezt ez a kör, `gh` hívása nélkül, NEM
tudja igazolni — lásd `blockers.md` R-SIGN-01).

## 4. Android release signing — `build.gradle.kts`

- **`releaseSigningRequired`** env-vezérelt kapcsoló
  (`android/app/build.gradle.kts:58-63`): ha igaz és nincs
  `releaseSigningValues`, `GradleException("Production release signing
  configuration is required.")` (`:61-63`).
- **Hiányos konfig**: `completeSigningValues()` `GradleException`-t dob, ha a
  4 kötelező mező (`storeFile`, `storePassword`, `keyAlias`, `keyPassword`)
  bármelyike hiányzik (`android/app/build.gradle.kts:26-34`).
- **Üres/hiányzó keystore fájl**: külön `GradleException`
  (`android/app/build.gradle.kts:66-70`).
- **Helyi `android/key.properties` NINCS jelen** ebben a munkapéldányban —
  `ls -la android/key.properties` kimenete → `No such file or directory`.
  Ez önmagában NEM blocker (a CI env-alapú konfigot használ, lásd §3), de azt
  jelenti, hogy **ez a munkapéldány lokálisan nem tud production APK-t
  buildelni** signing nélkül — csak a `.github/workflows/release-apk.yml`
  CI-futás rendelkezik a szükséges secretekkel, HA azok konfigurálva vannak
  (lásd `blockers.md` R-SIGN-01).

## 5. Backend — adatbázis-migrációk

- **21 migráció** — a helyes mérő a `*.py` glob, NEM a puszta könyvtárlistázás:
  `ls backend/alembic/versions/*.py | wc -l` kimenete → `21`.
  `e01_r12_0001_initial_account_schema.py` … `e09_r27_0020_community_moderation.py`.
- **MÉRÉSI CSAPDA (dokumentálva, de ebben a munkapéldányban NEM reprodukálódott):**
  a brief (§0.0.A) szerint `ls backend/alembic/versions/ | wc -l` **22**-t ad
  egy olyan checkoutban, ahol a gitignore-olt `__pycache__` már létrejött
  (pl. korábbi `pytest` futás után). Ebben a friss munkapéldányban
  `backend/alembic/versions/` nem tartalmaz `__pycache__`-t (`ls -la
  backend/alembic/versions/ | grep -i pycache` kimenete üres), ezért a puszta
  `ls | wc -l` itt is `21`-et ad — de a **kanonikus, `__pycache__`-független
  mérő** a `*.py` glob, ez a baseline. Ne a puszta `ls | wc -l`-re hivatkozz.
- **A séma-történet lineáris**: minden fájlnév `<epic>_<round>_<sorszám>_<leírás>.py`
  alakú, a sorszámok `0001`-től `0020`-ig folytonosak (21 fájl, mert az
  `0019` sorszám két fájlon oszlik meg: `e09_r25_0019_community_club_pinned_posts.py`
  és `e09_r26_0019_community_report.py` — `ls backend/alembic/versions/*.py`
  kimenete).

## 6. ADR-számozás

- **Legmagasabb létező ADR-fájl: `0426`** — `ls docs/adr/ | grep -oE
  '^[0-9]{4}' | sort -n | tail -3` kimenete → `0424 0425 0426`.
- **Az `0427`–`0442` tartomány foglalt, de Íratlan** — az Epic 10 (Local AI)
  batch előre kiosztott ADR-számai; egyik sem létezik fájlként:
  `ls docs/adr/ | grep -oE '^0(42[7-9]|4[3][0-9]|44[0-2])' | wc -l` kimenete
  → `0`. A hozzájuk tartozó körök mind `hold` státuszúak:
  `grep -n "^E10" docs/execution/pipeline-queue.tsv` kimenete (részlet) →
  `E10-R12 … 0427 hold`, `E10-R13 … 0428 hold`, …, `E10-R20 … 0434 hold`.
- **Az első szabad szám: `0443`** — ezt a Chapter 12 batch osztja ki, a
  Kör 2-től (`E12-R02`): `grep -n "^E12-R02" docs/execution/pipeline-queue.tsv`
  kimenete → `E12-R02 docs/rounds/e12-r02-sdd-index-and-dependency-graph.md
  sonnet-impl 0443 pending`.
- **Ez a kör (E12-R01) NEM oszt ki és NEM ír ADR-t** — a pipeline-queue sora:
  `grep -n "^E12-R01" docs/execution/pipeline-queue.tsv` kimenete →
  `E12-R01 docs/rounds/e12-r01-program-baseline-and-release-history-audit.md
  sonnet-impl nincs pending`.

## 7. Chapter 12 (Release Roadmap) terv-lefedettség

- **36 tervezett kör** (`E12-R01`…`E12-R36`), mind `pending` státuszú a
  méréskor: `awk -F'\t' 'NR>=497 && NR<=532' docs/execution/pipeline-queue.tsv
  | wc -l` kimenete → `36`.
- A `docs/execution/pipeline-queue.tsv` 497–532. sorai sorolják fel a teljes
  Chapter 12 sávot, brief-fájlonként, motoronként, ADR-számmal és
  státusszal.

## 8. Kormányzási release-checklist állapota

- **`docs/governance/04-release-checklist.md`** (49 sor) létezik, de **minden
  sora pipálatlan** — `grep -c '\[ \]' docs/governance/04-release-checklist.md`
  kimenete → `30`; `grep -c '\[x\]' docs/governance/04-release-checklist.md`
  kimenete → `0`.
- A dokumentum forrása `docs/plans/gpt/121-gov-04-release-checklist.md`
  (`canonical_target: docs/governance/04-release-checklist.md`,
  `as_built: … (E01-R01, r207)` — a plan fájl fejléce).
- A checklist 6 szakasza (Build identity, Quality, Offline és privacy,
  Security, Store, Rollout) egy-az-egyben megfeleltethető a Chapter 12
  körtervnek (§7) — ezt a megfeleltetést a [blockers.md](blockers.md) építi
  tovább.

Lásd még: [release-history-audit.md](release-history-audit.md) (a publikus
kiadás-történet) és [blockers.md](blockers.md) (a fentiekből következő
release-blokkolók).

## 9. `docs/release/` — a mérés pillanatában

`ls -d docs/release` kimenete a mérés pillanatában (a jelen kör ELSŐ lépése
előtt) → `No such file or directory`. Ez a három fájl
(`program-baseline.md`, `release-history-audit.md`, `blockers.md`) az
első tartalma.

## 10. Gate-teszt jelenléte (a kör saját regresszió-őre)

`ls -l test/app/config/feature_flags_test.dart` kimenete → a fájl létezik,
7666 bájt. Ez a kör nem módosítja, csak a `tools/round-gate.sh` bemeneteként
futtatja (lásd a kör-brief §7 és a jelen kör §10-es handoffja).
