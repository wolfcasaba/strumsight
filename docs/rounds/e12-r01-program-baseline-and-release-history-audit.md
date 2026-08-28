# E12-R01 — Program baseline és release history audit

- **Státusz:** READY (pre-flight LEFUTVA 2026-08-28, `main @ 92576977` — lásd §0.0.A; előre megírva 2026-08-27, kód olvasva: `main @ 9ca4a0dc`)
- **Típus:** Chapter 12 (Release Roadmap, Sprint Planning & Final Integration), Kör 1
- **Kör-azonosító:** `E12-R01`
- **Branch:** `<motor>/e12-r01-program-baseline-and-release-history-audit`
- **Előfeltétel:** `E13-R36` merge-elve (user-döntés: a teljes UI ELŐSZÖR — a Chapter 12 sáv csak utána indul)
- **Brief szerzője:** Claude (Opus 5)
- **Előre kiosztott ADR:** nincs — ez mérési/dokumentációs baseline-kör, kötött architekturális döntés nélkül.

**Visszakeresett előzmény:** `node tools/knowledge-rag.mjs --corpus lessons,halts,adr --top 5 "release baseline audit version package id release history blocker"` → a legerősebb találat a `halts/round-status-E09-R01` (epic-nyitó baseline-kör, ami *alkalmazáskód-változás nélkül* szállított mérést + threat modelt) és az [L67](../LESSONS.md#l67) (a perzisztált baseline csak a legelső indításkor rögzül — egy később commitolt pre-flight nem írja felül). Mindkettő ugyanazt mondja ennek a körnek: a baseline ÉRTÉKE a mérés pillanatához kötött, ezért a dokumentumnak a mérés SHA-ját is hordoznia kell.

> ⚠ **Pre-flight (indítás előtt KÖTELEZŐ):** olvasd újra a `pubspec.yaml` `version:` sorát (a megíráskor `1.0.0+1`), az `android/app/build.gradle.kts` applicationId-ját és a `.github/workflows/` TÉNYLEGES listáját (a megíráskor 10 workflow). Az E13/E14 sáv körei ezeket elmozdíthatták — a §2 minden számát újra kell mérni, nem átvenni.

## 0.0.A Pre-flight brief-revízió — MÉRVE (2026-08-28, orchestrátor: Claude Opus 5)

**Mérés SHA-ja:** `main @ 92576977` (`chore(pipeline): a Chapter 12 sáv AKTIVÁLÁSA …`, 2026-08-28 01:42:55 +0200).
**Brief-lint (strict):** `nincs lelet` — nincs `B*`/`S*` javítandó.
**Hagyaték-szonda (ADR 0112):** `ÁLLAPOT: NINCS` — a kör tisztán indul.

### P1 — A §2 minden száma ÚJRAMÉRVE, mind HELYES

| §2 állítás | Mérő parancs | Mért érték | Verdikt |
|---|---|---|---|
| `name: strumsight`, `version: 1.0.0+1` | `grep -n "^name:\|^version:" pubspec.yaml` | `pubspec.yaml:1` `name: strumsight` · `pubspec.yaml:5` `version: 1.0.0+1` | **VÁLTOZATLAN** |
| `.github/workflows/` 10 workflow | `ls .github/workflows/ \| wc -l` | `10` — `backend-ci`, `build-apk`, `chord-train`, `dsp-probe`, `full-gate`, `lab-apk`, `ml-train`, `release-apk`, `router-ci`, `tutor-eval` | **VÁLTOZATLAN** |
| `release-apk.yml` 174 sor | `wc -l .github/workflows/release-apk.yml` | `174` | **VÁLTOZATLAN** |
| `backend/alembic/versions/` 21 migráció | `ls backend/alembic/versions/*.py \| wc -l` | `21`, `e01_r12_0001_initial_account_schema.py` … `e09_r27_0020_community_moderation.py` | **VÁLTOZATLAN** |
| ADR-fájlok `0426`-ig | `ls docs/adr/ \| grep -oE '^[0-9]{4}' \| sort -n \| tail -3` | `0424 0425 0426` | **VÁLTOZATLAN** |
| `docs/release/` nem létezik | `ls -d docs/release` | `No such file or directory` | **VÁLTOZATLAN** |
| gate-teszt létezik | `ls -l test/app/config/feature_flags_test.dart` | létezik (7666 bájt) | **VÁLTOZATLAN** |

**Új mért tény (a §2 nem tartalmazta):** a package ID `com.wolfcasaba.strumsight` —
`android/app/build.gradle.kts:73` (`namespace`) és `:89` (`applicationId`), a kettő azonos.

> **MÉRÉSI CSAPDA — kötelezően így mérd.** `ls backend/alembic/versions/ | wc -l` **22**-t ad,
> mert a könyvtárban ott a gitignore-olt `__pycache__` is. A migrációk száma **21**; a
> `*.py` glob a helyes mérő (`ls backend/alembic/versions/*.py | wc -l`). A baseline-be a
> **21** megy, a `*.py`-s parancs kíséretében.

### P2 — Feloldott brief-ütközés: a §7 `gh`-tilalma vs. a §3 Releases-auditja

A §7 kimondja: „az implementer `gh`-t nem hív" — a §3 viszont a **GitHub Releases-ből
bizonyítható** artefaktumok auditját kéri. A tilalom szándéka a **CI-dispatch / PR / merge**
művelet orchesztrátor-oldali tartása, nem egy read-only lekérdezés megtiltása; a betű szerinti
olvasat viszont fölösleges `stopped`-ot okozna. **Feloldás:** az orchestrátor a pre-flightban
elvégezte a mérést, és az eredményt ITT adja át hiteles bemenetként. Az implementer **nem hív
`gh`-t** — a §3 audit-tábláját ebből a mért leltárból építi, a mérő parancsokat pedig
bizonyítékként hivatkozza.

**Mért kiadás-leltár (`gh release list --limit 100`, 2026-08-28):**

- **26 GitHub Release** — `gh release list --limit 100 --json tagName --jq 'length'` → `26`
- **27 git tag** — `git tag | wc -l` → `27`
- **Delta = pontosan 1 tag-only ref: `build-81`** (van tag, nincs hozzá Release) —
  `for t in $(git tag); do gh release view "$t" >/dev/null 2>&1 || echo "$t"; done` → `build-81`
- Legrégebbi: `v0.1.0` — 2026-07-05T22:14:07Z · legfrissebb (`isLatest`): `gov-05-shipping` — 2026-08-09T18:30:53Z

| Tag | Létrehozva (UTC) | Cím |
|---|---|---|
| `gov-05-shipping` | 2026-08-09T18:30:53Z | GOV-05 shipping rollout — Practice V2 + Song Trainer V2 + Learn V2 (development APK) |
| `e02-r08` | 2026-07-31T07:57:09Z | E02-R08 — Observation gateway (development APK) |
| `e01-r16` | 2026-07-30T07:31:10Z | E01-R16 — Epic 1 zárókör (development APK) |
| `build-175` | 2026-07-14T00:38:31Z | StrumSight — no-strum reject live (r175) |
| `build-112` | 2026-07-11T11:41:17Z | StrumSight build-112 — round 112 (15-lesson curriculum, metre-aware count-in) |
| `build-66` | 2026-07-10T12:10:41Z | StrumSight build-66 — moat + game-feel + glowing highway |
| `build-64` | 2026-07-10T08:58:32Z | StrumSight build-64 — moat hardened + game-feel |
| `build-58` | 2026-07-10T04:49:51Z | StrumSight build-58 — Songwriting suite: build songs, setlists, metronome & progress |
| `build-48` | 2026-07-09T14:00:40Z | StrumSight build-48 — Strum Reel, Jam mode, more lessons |
| `build-45` | 2026-07-09T13:30:37Z | StrumSight build-45 — more chords, a barre lesson, left-handed mode |
| `build-43` | 2026-07-09T13:07:36Z | StrumSight build-43 — Chord diagrams everywhere + chord library |
| `build-41` | 2026-07-09T12:11:35Z | StrumSight build-41 — Learn: chord diagrams + slow-down practice |
| `build-39` | 2026-07-09T10:58:15Z | StrumSight build-39 — Learn: chord grading + quality-of-life |
| `build-37` | 2026-07-09T10:20:36Z | StrumSight build-37 — Learn: metronome + practice your own recordings |
| `build-35` | 2026-07-09T09:26:22Z | StrumSight build-35 — Learn: full curriculum + shareable scores |
| `build-33` | 2026-07-09T07:33:44Z | StrumSight build-33 — Learn mode: play-along + scoring |
| `build-31` | 2026-07-09T06:48:25Z | StrumSight build-31 — Growth pack: Share, Streaks, Onboarding |
| `build-29` | 2026-07-09T05:11:30Z | StrumSight build-29 — Share your Strum Card (growth) |
| `build-28` | 2026-07-08T14:39:11Z | StrumSight build-28 — Chord dictionary + Viterbi (extended chords, 7ths) |
| `build-25` | 2026-07-07T08:03:12Z | StrumSight build-25 — Chordino-class chord engine (NNLS) |
| `build-24` | 2026-07-07T06:27:36Z | StrumSight build-24 — tuner & Live reject voice/noise |
| `build-23` | 2026-07-07T05:57:00Z | StrumSight build-23 — Analyze + Library work; clean UI |
| `build-22` | 2026-07-07T05:45:56Z | StrumSight build-22 — Analyze + Library now work |
| `build-19` | 2026-07-06T11:50:52Z | StrumSight build-19 — tuning A4 + account sync |
| `v0.2.0` | 2026-07-05T22:57:41Z | StrumSight v0.2.0 — real on-device detection |
| `v0.1.0` | 2026-07-05T22:14:07Z | StrumSight v0.1.0 — v1 UI (mock engine) |

> **A `build-NN` tag NEM a pubspec build numbere.** A tagnevek a projekt korábbi,
> SDD előtti belső kör-számozását hordozzák (`build-175` = r175), miközben a
> `pubspec.yaml:5` **ma is `1.0.0+1`**. A §2 „a projekt még SOSEM emelt build numbert egy
> publikus kiadáshoz" állítása ezzel bizonyított — az auditnak ezt **ki kell mondania**,
> mert enélkül a 26 Release és a `+1` build number ellentmondásnak látszik.

### P3 — ADR: ez a kör NEM oszt és NEM ír ADR-t

A pipeline-prompt fejléce a `nincs` ADR-hez az általános sablonszöveget adja („te írod meg
a pre-flightban"), a brief §3 viszont a `docs/adr/**`-ot **kifejezetten tilos zónába** teszi,
és a §9 csak a `0443` szabadságának ELLENŐRZÉSÉT kéri. A queue-sor is `nincs`.
**Döntés (a kör saját, még nem merge-elt artefaktuma → ADR 0087 §2 szerint az én hatásköröm):**
ez a kör ADR nélkül fut. **Indok:** (a) baseline-mérés, kötött architekturális döntés nélkül;
(b) precedens — 30+ lezárt kör futott `nincs` ADR-rel (`docs/execution/pipeline-queue.tsv`,
pl. `E02-R20`, `E03-R02`…`E03-R20`, mind `done`); (c) egy fölöslegesen lefoglalt szám
ütközne az **E12-R02-nek előre kiosztott `0443`**-mal. **A `0443` szabad** — a lemezen a
legmagasabb `0426`, a `0427`…`0442` az Epic 10 batch előre kiosztott sávja.

### P4 — Visszakeresés (ADR 0312) — MEGTÖRTÉNT

Szűkítve, majd a teljes korpuszon (`node tools/knowledge-rag.mjs`):

- **[ADR 0376](../adr/0376-ui-baseline-inventory-contract.md)** (`--corpus lessons,halts,adr`, `emb#1`) — az E13-R01
  **read-only baseline-kör** szerződése: „`lib/**` nem módosul; a talált hibák javítása későbbi
  kör feladata". Ez ennek a körnek a közvetlen precedense; az **A5** cella ugyanezt gépiesíti.
- **[L487](../LESSONS.md#l487)** (`--corpus lessons,halts`, `bm25#1`) — **az e kör legfontosabb kockázata:**
  az implementer egy **le nem futott** mérésre hivatkozott bizonyítékként, és a következtetése
  történetesen igaz volt — a doksi ettől még hazudott. Egy docs-only körben ez a legvalószínűbb
  néma bukás. Ellenszere az alábbi **A7** cella.
- **[L67](../LESSONS.md#l67)** — a briefben már hivatkozva (a baseline a mérés pillanatához kötött → §5.2).
- A teljes korpuszos futás a saját briefet és a `docs/plans/gpt/121-gov-04-release-checklist.md`
  tervet hozta — utóbbi a Chapter 12 későbbi köreinek bemenete, **ebben a körben nem célfájl**.

### P5 — ÚJ acceptance-cella (A7) az L487 hibaosztálya ellen

A §6 táblázat kiegészül; a §5.1 alakot ez teszi gépiesen ellenőrizhetővé:

| # | Kritérium | Bizonyíték |
|---|---|---|
| A7 | Minden `<parancs> kimenete` alakú állítás mellett ott a **szó szerint futtatható parancs**, és a leírt szám a parancs ÚJRAfuttatásakor reprodukálódik | a reviewer eldobható próbája: kimásolja a dokumentumból a parancsokat, lefuttatja, és a kimenetet a leírt számhoz méri |

**Mérce-mátrix bővítés:** *„a dokumentum egy le nem futtatott mérésre hivatkozik bizonyítékként
(pl. `21 migráció` a `__pycache__`-t is számoló `ls … | wc -l` mellé írva)"* → **A7** PIROS.

**Ez szigorítás, nem tágítás:** az engedélyezett-fájllista és a tilos zóna VÁLTOZATLAN.

## 0.0.B Miért nem kód-kör

A Chapter 12 első köre a program TÉNYLEGES kiinduló állapotát rögzíti. A SDD Kör 1 kifejezetten tiltja a production kód módosítását: a baseline értéke pontosan az, hogy egyetlen állítása sem terv, hanem a repóból kimért tény. Az összes további Chapter 12 kör (blocker-lista, RC-összeállítás, GA-döntés) EBBŐL a dokumentumból hivatkozik vissza.

```ai-router
schema_version = 1
risk = "normal"
allowed_paths = [
  "docs/release/program-baseline.md",
  "docs/release/release-history-audit.md",
  "docs/release/blockers.md",
  "docs/rounds/e12-r01-program-baseline-and-release-history-audit.md",
]
gate_tests = [
  "test/app/config/feature_flags_test.dart",
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

**STOP-protokoll:** ha a §3 scope-jához olyan fájl kellene, ami a §4 listáján nincs rajta, a kimenet a `stopped` jelzés és brief-revízió kérése — a lista csendes tágítása TILOS ([L478](../LESSONS.md#l478)).

## 1. Cél

A tényleges kiinduló állapot, a publikus release history és minden release-blokkoló bizonyítható, egyetlen helyről hivatkozható dokumentálása — alkalmazáskód-változás nélkül.

## 2. Jelenlegi állapot — mért tények

- `docs/release/` **nem létezik** — ez a kör hozza létre az első három fájlját.
- `pubspec.yaml` → `name: strumsight`, `version: 1.0.0+1` (a projekt még SOSEM emelt build numbert egy publikus kiadáshoz).
- `.github/workflows/` **10 workflow**: `backend-ci`, `build-apk`, `chord-train`, `dsp-probe`, `full-gate`, `lab-apk`, `ml-train`, `release-apk`, `router-ci`, `tutor-eval`.
- `.github/workflows/release-apk.yml` (174 sor) MÁR fail-closed a production signing secretekre (`signing-prerequisites` job), és a `pubspec` `<version>+<build>` alakját regexszel kényszeríti — tehát a Kör 6/7 NEM nulláról indul.
- `android/app/build.gradle.kts` MÁR dob `GradleException`-t hiányos release signing konfigra (`releaseSigningRequired`).
- `backend/alembic/versions/` **21 migráció** (`e01_r12_0001` … `e09_r27_0020`) — a séma-történet teljes és lineáris.
- ADR-fájlok a `docs/adr/`-ban `0426`-ig; az előre kiosztott (még nem írt) számok az Epic 10 batchben `0442`-ig futnak. **Az első szabad szám: `0443`** (ezt a Chapter 12 batch a Kör 2-től osztja ki).
- Publikus store-jelenlét **nincs**; a kiadott artefaktumok eddig CI-artifactok és GitHub Release-ek voltak.

## 3. Scope

**Benne van:** `docs/release/program-baseline.md` (verzió, package ID, környezetek, CI-kapuk, backend, modell-assetek, migrációk mért állapota, mindegyik fájl+sor bizonyítékkal és a mérés SHA-jával) · `docs/release/release-history-audit.md` (minden korábbi APK/AAB/Release artefaktum, ami a repóból vagy a GitHub Releases-ből bizonyítható, és explicit „nincs store history" állítás) · `docs/release/blockers.md` (release-blocker lista: azonosító, severity P0–P3, owner, érintett Chapter, bizonyíték-link, zárási feltétel).

**NINCS benne (tilos):**

- **Bármilyen `lib/`, `backend/app/`, `android/` kódváltozás** — a SDD Kör 1 explicit tiltása.
- ADR írása (`docs/adr/**`) — ez a kör nem hoz kötött döntést.
- A blocker-lista alapján bármit MEGJAVÍTANI — a javítás a saját körének a dolga.

## 4. Engedélyezett fájlok

| Útvonal | Indok |
|---|---|
| `docs/release/program-baseline.md` | ÚJ — a mért kiinduló állapot |
| `docs/release/release-history-audit.md` | ÚJ — a kiadás-történet auditja |
| `docs/release/blockers.md` | ÚJ — a blocker-nyilvántartás |
| `docs/rounds/e12-r01-program-baseline-and-release-history-audit.md` | a §10 handoff kitöltése |

**Tilos zóna:** `lib/**` · `test/**` · `backend/**` · `android/**` · `.github/**` · `docs/adr/**` · `tools/**` · `pubspec.yaml`

## 5. Kötött architekturális döntések

Nincs ADR. Két, a briefből következő KÖTELEZŐ forma:

### 5.1 Minden állítás bizonyíték-hivatkozást hordoz

Egy állítás alakja `<állítás> — <fájl>:<sor>` vagy `<állítás> — <parancs> kimenete`. **NEM elfogadható gyengítés:** „a CI lefedi a release-t" típusú, hivatkozás nélküli összefoglaló, akkor sem, ha igaz — a baseline értéke a visszakereshetőség, nem a helyesség.

### 5.2 A baseline a mérés SHA-ját hordozza

A `program-baseline.md` fejlécében ott a `main @ <sha>` és a dátum. **NEM elfogadható gyengítés:** „aktuális állapot" felirat SHA nélkül ([L67](../LESSONS.md#l67) hibaosztálya: egy baseline, aminek nincs időbélyege, később megkülönböztethetetlen a friss méréstől).

## 6. Acceptance criteria

| # | Kritérium | Bizonyíték |
|---|---|---|
| A1 | A három dokumentum létezik, és mindegyik fejléce hordozza a mérés SHA-ját + dátumát | a fájlok fejléce |
| A2 | A `program-baseline.md` minden állítása fájl+sor vagy parancs-kimenet hivatkozású | a dokumentum átolvasása a §5.1 alakja szerint |
| A3 | A `release-history-audit.md` kimondja, hogy publikus store-history NINCS (vagy felsorolja, ha a pre-flight mást mér) | a dokumentum |
| A4 | A `blockers.md` minden sora hordoz azonosítót, severityt (P0–P3), ownert, Chaptert és zárási feltételt | a dokumentum táblázata |
| A5 | `git diff --stat` a §4 listán KÍVÜL 0 fájlt mutat — nincs alkalmazáskód-változás | `git diff --stat main...HEAD` |
| A6 | Minden hivatkozott belső link létező fájlra mutat | a §7 link-ellenőrzés |
| A7 | Minden `<parancs> kimenete` alakú állítás mellett ott a **szó szerint futtatható parancs**, és a leírt szám a parancs ÚJRAfuttatásakor reprodukálódik (§0.0.A P5, [L487](../LESSONS.md#l487)) | a reviewer kimásolja és lefuttatja a dokumentum parancsait |

### 6.1 Mérce-mátrix — melyik hibás implementációt melyik cella fogja pirosra

| Hibás implementáció | Melyik cella vált PIROSRA |
|---|---|
| A baseline „a jelenlegi állapot" felirattal, SHA nélkül készül | A1 |
| Egy állítás („a release CI zöld") bizonyíték-hivatkozás nélkül marad | A2 |
| A blocker-sor owner vagy zárási feltétel nélkül kerül a listára | A4 |
| A kör „menet közben" megjavít egy talált blokkolót a `lib/`-ben | A5 |
| A dokumentum egy nem létező `docs/release/rc-checklist.md`-re hivatkozik (későbbi kör terméke) | A6 |
| A dokumentum le nem futtatott mérésre hivatkozik bizonyítékként (pl. „21 migráció" a `__pycache__`-t is számoló `ls … \| wc -l` mellé írva) | A7 |

**Falszifikációs próba (KÖTELEZŐ, a §10-ben dokumentálva):** vedd ki egy tetszőleges blocker-sorból az owner-mezőt, és futtasd a §7 link/mező-ellenőrzést → az **A4** cellának PIROSNAK kell lennie → állítsd vissza. Docs-only kör lévén a próba a reviewer eldobható ellenőrzésével is megismételhető: a `program-baseline.md` fejléc-SHA sorának törlése teszi az **A1** cellát bizonyíthatatlanná.

## 7. Kötelező ellenőrzések

A gate artefaktum a mérce (AGENTS.md §12) — a kör nem ír Dart kódot, de a regresszió-őr futtatása bizonyítja, hogy a fa érintetlen:

```bash
tools/round-gate.sh test/app/config/feature_flags_test.dart
```

Link- és mező-ellenőrzés (a kör saját, eldobható ellenőrzése, a §10-be másolt kimenettel):

```bash
grep -oE '\]\([^)]+\.md[^)]*\)' docs/release/program-baseline.md docs/release/release-history-audit.md docs/release/blockers.md
```

CI-dispatch, PR és merge kizárólag orchesztrátor-oldal — az implementer `gh`-t nem hív.

## 8. Implementációs sorrend

1. Mérés: `pubspec`, `android/app/build.gradle.kts`, `.github/workflows/`, `backend/alembic/versions/`, `docs/adr/` — minden szám a fáról.
2. `docs/release/program-baseline.md`.
3. `docs/release/release-history-audit.md`.
4. `docs/release/blockers.md` — a §2 mérésből következő P0/P1 tételek.
5. Link-ellenőrzés + a falszifikációs próba a §10-be.

## 9. Kockázatok

- **A baseline „tervnek" íródik a mérés helyett.** A leggyakoribb hibaosztály: az SDD szövegét másolja a repó állapota helyett. Az A2 cella pontosan ezt fogja.
- **Scope-csúszás javítás felé.** Egy talált P0 blokkoló megjavítása ebben a körben elrejtené, hogy a baseline mit mért (A5).
- **ADR-szám ütközés.** A `0443` szabadságát a pre-flight ellenőrizze újra: az Epic 10 batch előre kiosztott számai driftelhetnek.

## 10. Implementation handoff — az implementer tölti ki

**Kész.** A három dokumentum elkészült a §4 engedélyezett listája szerint,
kódváltoztatás nélkül. Mérés SHA-ja mindhárom fejlécében: `main @ 92576977`.

### Mit mértem, és mit fedeztem fel a §2/§0.0.A-n felül

A §0.0.A minden száma reprodukálódott ebben a munkapéldányban (`1.0.0+1`, 10
workflow, `release-apk.yml` 174 sor, 21 migráció a `*.py` globgal, ADR-max
`0426`, `docs/release` hiánya, a gate-teszt jelenléte). A `*.py`-mentes
`ls backend/alembic/versions/ | wc -l` **ebben a friss munkapéldányban 21-et**
adott, NEM 22-t (nincs `__pycache__`, mert még nem futott itt `pytest`) — ezt
`program-baseline.md` §5 külön dokumentálja, hangsúlyozva, hogy a kanonikus
mérő ettől függetlenül a `*.py` glob.

Új, a briefben nem szereplő tényeket is mértem és bizonyítékkal
dokumentáltam: a `docs/governance/04-release-checklist.md` mind a 30 sora
pipálatlan (`program-baseline.md` §8); nincs `android/key.properties` ebben a
munkapéldányban (§4); a `docs/execution/pipeline-queue.tsv` teljes Chapter 12
sávja (36 sor, `E12-R01`…`E12-R36`) mind `pending` (§7); nincs store-metaadat
vagy `.aab` a repóban (`release-history-audit.md` §5). Ezekből építettem a
`blockers.md` 10 sorát, mindegyiket egy konkrét, `pending` Chapter 12
owner-körhöz kötve.

Egy saját hibámat a munka közben találtam meg és javítottam: a
`docs/governance/04-release-checklist.md` pipálatlan sorainak számát elsőre
becsültem (`24`), majd a `grep -c '\[ \]'` tényleges lefuttatásával `30`-ra
javítottam — ez pontosan az A7 kritérium által tiltott hibaosztály, amit a
saját dokumentumomban időben elkaptam (lásd alább, „A7 önellenőrzés").

### A7 önellenőrzés — minden idézett parancsot ténylegesen lefuttattam

A három dokumentumban szereplő ~35 db `<parancs> kimenete` alakú állítás
mindegyikét egyenként lefuttattam és a doksiban szereplő számmal
összevetettem (lásd a kör session-transzkriptjét): `pubspec.yaml` grep-ek,
`.github/workflows/` listázás és soronkénti `wc -l`, `release-apk.yml` és
`build.gradle.kts` konkrét sor-tartományainak `sed -n` kiolvasása, a
migráció-glob és a `0019` duplikáció listája, az ADR-tartomány grep-jei, a
`pipeline-queue.tsv` sorai, a governance checklist `[ ]`/`[x]` számlálása, a
`git tag`/`git log` parancsok. A GitHub Releases-táblázatot (26 sor) **nem
futtattam újra** — az implementer nem hív `gh`-t (brief §7) —, ezt a
`release-history-audit.md` fejléce és §1/§3 külön, explicit módon jelöli;
a helyi, `gh`-t nem igénylő tag-adatokat (27 tag, `build-81` benne van)
viszont igen, és kereszt-ellenőriztem velük a pre-flight delta-állítását
(§2).

### Falszifikációs próba (KÖTELEZŐ, §6.1)

Két próbát futtattam, mindkettőt visszaállítottam utána (`diff -q` a
mentett másolattal → azonos):

1. **A4 (blockers.md)** — kivettem az `R-SIGN-01` sor Owner-mezőjét
   (`[E12-R07](../rounds/e12-r07-...)` → üres cella). Hatás: a sor Owner
   nélkül bizonyíthatatlan (nincs konkrét kör, ami zárná) — **A4 PIROS
   lett volna**. Mellékhatás: a §7 link-számláló `19`-ről `18`-ra esett
   (eggyel kevesebb `](...)`-link). Visszaállítva: `cp
   /tmp/blockers.md.bak docs/release/blockers.md`, `diff -q` egyezett.
2. **A1 (program-baseline.md)** — töröltem a fejléc `**Mérés SHA-ja:** ...`
   sorát (`sed -i '3d'`). Hatás: a dokumentumban nincs `main @ <sha>` —
   **A1 PIROS lett volna** (§5.2 tiltott gyengítése: „aktuális állapot"
   SHA nélkül). Visszaállítva: `cp /tmp/program-baseline.md.bak
   docs/release/program-baseline.md`, `diff -q` egyezett.

### Gate

```
tools/round-gate.sh test/app/config/feature_flags_test.dart
```

Csonkítás nélküli kimenet — mind a 6 lépés ZÖLD: `format`, `analyze`,
`test test/app/config/feature_flags_test.dart` (12/12 teszt PASS),
`architecture`, `secrets`, `l10n`. Összegzés: „MINDEN GATE ZÖLD."

### Link-ellenőrzés (§7)

```
grep -oE '\]\([^)]+\.md[^)]*\)' docs/release/program-baseline.md docs/release/release-history-audit.md docs/release/blockers.md
```

19 db `](*.md)` hivatkozás, mindegyiket egyenként ellenőriztem
(`dirname`+relatív útvonal feloldás) — mind a 19 létező fájlra mutat: a
három `docs/release/*.md` egymásra hivatkozása, `../governance/
04-release-checklist.md`, és 9 db `../rounds/e12-r*.md` owner-kör brief.

### Scope (A5)

`git diff --stat origin/main...HEAD` (ez a munkapéldány nem tart lokális
`main` ágat, csak `origin/main`-t) a jelen kör commitja előtt kizárólag a
pre-flight `docs/rounds/e12-r01-...md` módosítását mutatta (1 fájl, a §0.0.A
brief-revízió — ezt az orchestrátor commitolta a kör indítása előtt). A jelen
kör saját commitja a §4 négy engedélyezett fájlját érinti: a három ÚJ
`docs/release/*.md` és ennek a §10-nek a kitöltése — `lib/`, `backend/`,
`android/`, `.github/`, `docs/adr/`, `tools/`, `pubspec.yaml` egyike sem
módosult.

## 11. Review — a Claude tölti ki
