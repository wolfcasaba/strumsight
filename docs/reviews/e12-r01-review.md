# Review — E12-R01: Program baseline és release history audit

- **Kör:** `E12-R01` · **Branch:** `sonnet-impl/e12-r01-program-baseline-and-release-history-audit`
- **Implementer:** `sonnet-impl` (Claude Sonnet 5, `--effort high`) · commit `302b4a1a`
- **Reviewer:** Claude Opus 5 (orchestrátor), READ-ONLY — a review alatt production fájl NEM módosult
- **Brief:** [`docs/rounds/e12-r01-program-baseline-and-release-history-audit.md`](../rounds/e12-r01-program-baseline-and-release-history-audit.md)
- **Dátum:** 2026-08-28
- **Review-klón:** `/tmp/review-e12-r01` (`git clone --branch <kör-branch>`, HEAD `302b4a1a`)

## VÉGSŐ DÖNTÉS: **APPROVED**

**BLOCKER: 0 · MAJOR: 0 · MINOR: 0 · NOTE: 2**

Javító kör nem szükséges.

---

## 1. Jelzés és handoff

`.codex-round-status`:

```
status=done
summary=E12-R01 kész: program-baseline.md, release-history-audit.md, blockers.md (10 sor) létrehozva, gate zöld, A5/A6/A7 önellenőrizve, 2 falszifikációs próba lefutott és visszaállítva, commit 302b4a1a
branch=sonnet-impl/e12-r01-program-baseline-and-release-history-audit
head=302b4a1a
dirty_files=1
signalled_at=2026-08-28T00:04:40+00:00
```

**`dirty_files=1` kivizsgálva (kötelező ellenőrzés, `docs/LESSONS.md` L21).**
A jelzés utáni mérés `git status --short` → **üres kimenet**, a fa tiszta; a
`git log --oneline origin/main..HEAD` pontosan két commitot ad (`8132ed01`
pre-flight + `302b4a1a` implementáció). A számláló a jelzés pillanatában mért
tranziens volt (a `.codex-round-status` maga készült ekkor). **Nem lelet.**

**`scope_audit=` mező HIÁNYZIK a jelzésfájlból** — a prompt §1.1 táblázata
szerint ez „nem bizonyíték", ezért kézzel futtattam (L177 hibaosztálya, ott
pontosan ez a mulasztás volt a lelet):

```
$ python3 tools/scope-audit.py --repo /home/ubuntu/ss-sonnet-impl-e12-r01 \
    --brief docs/rounds/e12-r01-program-baseline-and-release-history-audit.md --base 8132ed01
Legacy scope audit OK (8132ed01ffd4..302b4a1a7fc9, 4 changed path(s), 0 generated/ignored)   [exit 0]

$ python3 tools/scope-audit.py --repo /home/ubuntu/ss-sonnet-impl-e12-r01 \
    --brief docs/rounds/e12-r01-program-baseline-and-release-history-audit.md --base origin/main
Legacy scope audit OK (9257697718af..302b4a1a7fc9, 4 changed path(s), 0 generated/ignored)   [exit 0]
```

Mindkét bázisról **OK**, 0 sértés.

## 2. Gate — SAJÁT kézzel, izolált `/tmp` klónban

```
$ cd /tmp/review-e12-r01 && tools/round-gate.sh test/app/config/feature_flags_test.dart
    format                                                     zöld
    analyze                                                    zöld
    test test/app/config/feature_flags_test.dart               zöld     (12/12 PASS)
    architecture                                               zöld     (12 allowlisted deviation)
    secrets                                                    zöld     (3926 fájl, 0 finding)
    l10n                                                       zöld     (en→hu, 2289 message)
MINDEN GATE ZÖLD.
GATE_EXIT=0
```

Csonkítatlan, saját futás — nem az implementer bemásolt kimenete.

## 3. Acceptance criteria — tételesen, saját méréssel

| # | Verdikt | Bizonyíték (a reviewer SAJÁT futása) |
|---|---|---|
| **A1** | ✅ | Mindhárom dokumentum létezik, és mindhárom 3. sora `**Mérés SHA-ja:** \`main @ 92576977\` (…, 2026-08-28 01:42:55 +0200)`. A SHA a kör indulási `main`-je. |
| **A2** | ✅ | A `program-baseline.md` 10 szakaszának minden állítása `<fájl>:<sor>` vagy `<parancs> kimenete` alakú. A ~35 idézett parancsból **15 kulcsértéket + 11 sor-tartományt** magam futtattam újra — mind egyezik (részletek a §4-ben). Egyetlen összefoglaló-jellegű mondat maradt (NOTE-1). |
| **A3** | ✅ | `release-history-audit.md` §5: „**NINCS publikus store-jelenlét**", négy független bizonyítékkal. Saját ellenőrzés: `find . -iname "*fastlane*" -not -path "./.git/*"` → 0 találat; `find . -iname "*.aab" …` → 0 találat; `grep -n "^E12-R24" docs/execution/pipeline-queue.tsv` → 520. sor, `pending`; a checklist `## Store` szakasza (35–41. sor) mind az 5 sora `[ ]`. |
| **A4** | ✅ | `blockers.md` **10 sora**, mindegyik hordoz ID-t (`R-…-01`), severityt (1×P0, 5×P1, 4×P2), Ownert (konkrét `pending` Ch12 kör-brief linkje), Chaptert (`Ch12`), Bizonyítékot és Zárási feltételt. Egyetlen üres cella sincs. |
| **A5** | ✅ | `scope-audit.py` **OK** mindkét bázisról, 4 érintett útvonal, mind a §4 listán. `git diff --stat origin/main...HEAD`: `docs/release/{blockers,program-baseline,release-history-audit}.md` + a kör-brief. `lib/**`, `test/**`, `backend/**`, `android/**`, `.github/**`, `docs/adr/**`, `tools/**`, `pubspec.yaml` **egyike sem** módosult. |
| **A6** | ✅ | A §7 parancs szó szerint: **19** db `](*.md)` hivatkozás (`program-baseline` 3 · `blockers` 14 · `release-history-audit` 2) — az implementer 19-es száma pontos. **Mind a 19 létező fájlra mutat** (saját `dirname`-alapú feloldás, 0 `MISSING`), köztük a 10 db `../rounds/e12-r*.md` owner-kör brief és a `../governance/04-release-checklist.md`. |
| **A7** (ÚJ, §0.0.A P5) | ✅ | Lásd §4 — a dokumentumból kimásolt parancsokat lefuttattam, **mind a 26 ellenőrzött érték reprodukálódott**. |

## 4. A7 reprodukció — a dokumentumból kimásolt parancsok saját futása

Az L487 hibaosztálya (le nem futott mérésre hivatkozás) ellen. Minden sor a
`/tmp/review-e12-r01` klónban futott:

| Doksiban állított | Saját mérés | ✓ |
|---|---|---|
| `grep -n "^name:" pubspec.yaml` → `pubspec.yaml:1 name: strumsight` | azonos | ✅ |
| `grep -n "^version:" pubspec.yaml` → `pubspec.yaml:5 version: 1.0.0+1` | azonos | ✅ |
| `ls .github/workflows/ \| wc -l` → `10` | `10` | ✅ |
| `wc -l .github/workflows/release-apk.yml` → `174` | `174` | ✅ |
| `ls backend/alembic/versions/*.py \| wc -l` → `21` | `21` | ✅ |
| `ls docs/adr/ \| grep -oE '^[0-9]{4}' \| sort -n \| tail -3` → `0424 0425 0426` | azonos | ✅ |
| ADR `0427`–`0442` fájlként nem létezik → `0` | `0` | ✅ |
| `grep -c '[ ]' docs/governance/04-release-checklist.md` → `30`; `[x]` → `0` | `30` / `0` | ✅ |
| a checklist 49 soros, 6 szakasszal | `49`; `## Build identity/Quality/Offline és privacy/Security/Store/Rollout` | ✅ |
| Ch12 sáv = a TSV 497–532. sora, 36 sor, mind `pending` | `36` sor, mind `E12-`, státusz-halmaz = `{pending}` | ✅ |
| `git tag \| wc -l` → `27`; `build-81` benne | `27`, `build-81` jelen | ✅ |
| `ls -la android/key.properties` → `No such file or directory` | azonos | ✅ |
| `ls docs/privacy/` → egyetlen `practice-planning-data.md` | azonos | ✅ |
| `ls docs/security/` → `community-access-matrix.md`, `community-threat-model.md` | azonos | ✅ |
| `docs/adr/0051-…identifiers.md` létezik | létezik | ✅ |
| `pipeline-queue.tsv:503` = `E12-R07 … 0448 pending` | azonos | ✅ |
| alembic sorszámok `0001`…`0020` folytonosak; az `0019` KÉT fájlon oszlik meg | `0001..0020` hiánytalan; `e09_r25_0019_…` + `e09_r26_0019_…` | ✅ |

**Sor-tartomány hivatkozások** (`sed -n` a klónban) — mind pontos:
`android/app/build.gradle.kts:26-34` (`Incomplete release signing configuration`),
`:58-63` (`releaseSigningRequired` + `GradleException("Production release signing configuration is required.")`),
`:66-70` (üres/hiányzó keystore) ·
`.github/workflows/release-apk.yml:29-35` (`exit 1` hiányzó secretre),
`:39` és `:153` (`needs: signing-prerequisites`),
`:88` (a `^([0-9A-Za-z][0-9A-Za-z._-]*)\+([0-9]+)$` regex), `:89-90`, `:95`
(artifact-név minta), `:119` (`STRUMSIGHT_REQUIRE_RELEASE_SIGNING: 'true'`) ·
`04-release-checklist.md:6, :15, :16, :24, :29-33, :37-41, :46, :47-48` — mind
szó szerint az idézett szöveg.

**A `build-apk.yml` trigger-állítás is igaz:** a fájl fejléce kimondja, hogy a
`main`-push trigger az ADR 0086 miatt megszűnt, és az `on:` blokk valóban csak
`workflow_dispatch`.

## 5. Valódi-sértés próbák (eldobhatók, merge előtt visszaállítva)

### P1 — az A7 cella nem díszlet

A klónban a `program-baseline.md` §5 migráció-számát `21` → `22`-re rontottam,
majd lefuttattam a doksi SAJÁT mérőparancsát:

```
doksi állítja:  ls backend/alembic/versions/*.py | wc -l  kimenete → `22`
tényleges:      21
```

Eltérés → **A7 PIROS**. Visszaállítva (`git diff --stat` üres). A cella tehát
valódi hibát fog, nem csak formát ellenőriz.

### P2 — a §2 halmaz-állítás független újramérése

A `release-history-audit.md` §2 kritikus állítása: a 27 helyi tag **pontosan** a
§3 tábla 26 tag-neve PLUSZ `build-81`. Saját halmazművelet (a táblát a doksiból
parszolva):

```
$ comm -23 <(git tag | sort) <(a §3 tábla tag-oszlopa | sort)
build-81
$ comm -13 <(git tag | sort) <(a §3 tábla tag-oszlopa | sort)
(üres)
```

**A halmaz-egyenlőség IGAZ** — a delta pontosan egy elem, `build-81`. Ez az a
pont, ahol a `gh`-mentes implementer a pre-flight bemenetét keresztellenőrizte;
a keresztellenőrzés helytálló.

### P3 — az implementer két saját falszifikációs próbája (§10) ellenőrizve

A brief §6.1 két próbáját az implementer dokumentálta (A4: owner-mező
eltávolítása → a §7 link-számláló `19`→`18`; A1: a fejléc-SHA sor törlése). A
`19`-es kiindulóértéket **magam is megmértem** (`grep -oE … | wc -l` → `19`),
tehát a leírt mellékhatás számszerűen ellenőrizhető. A fa a próbák után tiszta
(`git status --short` üres).

## 6. Architektúra és termékhatárok (AGENTS.md §5–§6)

**Nem alkalmazható, bizonyítottan:** a kör diffje **kizárólag** négy Markdown
fájl (`scope-audit` fenti kimenete). Nincs Dart/Python/Kotlin változás, tehát
nincs domain-függetlenségi, `core↛feature`, `public.dart`-contract, UI↛plugin,
audio/hálózat/mikrofon/secret vagy lifecycle-erőforrás érintés. A `secrets`
gate-lépés ettől függetlenül lefutott: **0 finding 3926 fájlon**.

## 7. Leletek

### NOTE-1 — egyetlen összefoglaló-jellegű mondat a §5.1 alakon kívül

`docs/release/program-baseline.md:153-156`: „A checklist 6 szakasza (Build
identity, Quality, Offline és privacy, Security, Store, Rollout) **egy-az-egyben
megfeleltethető** a Chapter 12 körtervnek (§7)".

Ez a dokumentum egyetlen olyan mondata, amely nem `<fájl>:<sor>` vagy
`<parancs> kimenete` alakú. **Nem hamis** — a 6 szakasz létezését magam mértem
(`grep -n '^## '` → pontosan az a hat), és a megfeleltetést a `blockers.md`
tételesen fel is építi. **Pontatlan viszont az „egy-az-egyben":** a hat
szakaszból **öthöz** rendel a `blockers.md` owner-kört; a **Quality** szakaszhoz
szándékosan nem, és ezt a `blockers.md` „Miért pont ezek — módszertan" szakasza
ki is mondja („ez már MOST is zöld, csak a checklist-doksi nincs frissítve").
A mondat tehát a saját dokumentum-párjában fel van oldva.

**Miért nem MINOR:** az A2 cella a `program-baseline.md`-re szól, és az állítás
ott is ellenőrizhető (a §7-re hivatkozik, ami mért). A javítás egy szó
(„lényegében megfeleltethető, a Quality kivételével") — a diffet nem éri meg
egy javító körrel hizlalni. **Follow-up:** a Chapter 12 következő köre, amelyik
ezt a fájlt amúgy is nyitja.

### NOTE-2 — sorszám-adat aszimmetria a workflow-táblában

`docs/release/program-baseline.md:38-49`: a 10 workflow közül **nyolcnál** ott a
`(N sor)` adat, a `build-apk.yml`-nél és a `full-gate.yml`-nél nincs. Minden sor
hordoz `<fájl>:<sortartomány>` bizonyítékot, tehát az **A2 nem sérül** — ez
kizárólag megjelenítési egyenetlenség. Nem blokkol, javítást nem igényel.

## 8. Amit külön kiemelek (nem lelet)

- **Az implementer saját hibáját megtalálta és jelentette.** A §10 handoff
  rögzíti, hogy a checklist pipálatlan sorainak számát elsőre **becsülte**
  (`24`), majd a `grep -c` tényleges futtatásával **`30`**-ra javította. Ez
  pontosan az A7 által célzott hibaosztály (L487), és az implementer a saját
  munkájában kapta el. A végleges szám az én mérésemmel is egyezik (`30`).
- **A `gh`-korlát helyes kezelése.** A `release-history-audit.md` fejléce, §1 és
  §3 **külön-külön jelöli**, mely adat származik a pre-flight orchestrátor-
  mérésből és mit futtatott újra maga az implementer. A §5 utolsó bekezdése
  kifejezetten **nem állítja**, hogy mind a 26 Release APK-t tartalmaz, mert az
  asset-lista `gh`-t igényelne. Ez a „hiányzó bemenet sosem álcázható sikeres
  eredménynek" elv (ADR 0271 §1) helyes alkalmazása egy dokumentációs körre.
- **A `21` vs `22` migráció-csapda kezelése.** A §0.0.A P1 a fő fában mért `22`-t
  (gitignore-olt `__pycache__`) írta le; a friss klónban a puszta `ls | wc -l`
  is `21`-et ad. Az implementer **nem hallgatta el az eltérést**, hanem
  `program-baseline.md:102-109`-ben dokumentálta, hogy a csapda ebben a
  munkapéldányban nem reprodukálódott, és kimondta, hogy a kanonikus mérő
  ettől függetlenül a `*.py` glob.

## 9. Merge-előfeltételek

| Feltétel | Állapot |
|---|---|
| Review APPROVED, 0 nyitott BLOCKER/MAJOR/MINOR | ✅ |
| `tools/round-gate.sh` zöld, saját futás izolált klónban | ✅ (§2) |
| `scope-audit.py` OK mindkét bázisról | ✅ (§1) |
| `full-gate.yml` `success` a merge SHA-ján | a §10-ben rögzítve |
| `router-ci.yml` `success` a merge SHA-ján (a diff érinti a `docs/rounds/**`-ot) | a §10-ben rögzítve |

## 10. CI-evidencia (exact-SHA, ADR 0086 §2)

A `tools/round-ci-plan.py` terve: `dispatch = ["full-gate.yml"]`,
`apk_required = false`, `router_ci_expected = true`
(`router_ci_paths_hit = ["docs/rounds/e12-r01-…md"]`) — a diff nem érint
natív/release-útvonalat.

| Workflow | Run | head SHA | Eredmény |
|---|---|---|---|
| `full-gate.yml` | [33128544155](https://github.com/wolfcasaba/strumsight/actions/runs/33128544155) | `302b4a1a` | ✅ `completed success` (`tools/wait-for-ci.sh 33128544155` → exit 0) |
| `router-ci.yml` | [33128535423](https://github.com/wolfcasaba/strumsight/actions/runs/33128535423) | `302b4a1a` | ✅ `completed success` (`tools/wait-for-ci.sh 33128535423` → exit 0) |

**Exact-SHA újra-dispatch a review-commit után.** A jelen review-jelentés
commitja megmozdítja a branch HEAD-jét, ezért a fenti két zöld futás a
**merge SHA-ján** már nem érvényes (ADR 0086 §2). Mindkét workflow-t
újradispatch-eltem a review-commitot tartalmazó HEAD-en; az eredmény alább.
A `docs/reviews/**` nem Router-CI trigger-útvonal, ezért a `router-ci.yml`-t
kézzel kellett dispatch-elni — a push önmagában nem indította volna el, a
merge-kapu viszont a `docs/rounds/**` érintettsége miatt továbbra is megköveteli.

| Workflow | Run | head SHA (merge SHA) | Eredmény |
|---|---|---|---|
| `full-gate.yml` | RUN_FG_URL | HEAD_SHA | RES_FG |
| `router-ci.yml` | RUN_RC_URL | HEAD_SHA | RES_RC |
