# E12-R01 — Program baseline és release history audit

- **Státusz:** PREPARED (előre megírva 2026-08-27, kód olvasva: `main @ 9ca4a0dc`)
- **Típus:** Chapter 12 (Release Roadmap, Sprint Planning & Final Integration), Kör 1
- **Kör-azonosító:** `E12-R01`
- **Branch:** `<motor>/e12-r01-program-baseline-and-release-history-audit`
- **Előfeltétel:** `E13-R36` merge-elve (user-döntés: a teljes UI ELŐSZÖR — a Chapter 12 sáv csak utána indul)
- **Brief szerzője:** Claude (Opus 5)
- **Előre kiosztott ADR:** nincs — ez mérési/dokumentációs baseline-kör, kötött architekturális döntés nélkül.

**Visszakeresett előzmény:** `node tools/knowledge-rag.mjs --corpus lessons,halts,adr --top 5 "release baseline audit version package id release history blocker"` → a legerősebb találat a `halts/round-status-E09-R01` (epic-nyitó baseline-kör, ami *alkalmazáskód-változás nélkül* szállított mérést + threat modelt) és az [L67](../LESSONS.md#l67) (a perzisztált baseline csak a legelső indításkor rögzül — egy később commitolt pre-flight nem írja felül). Mindkettő ugyanazt mondja ennek a körnek: a baseline ÉRTÉKE a mérés pillanatához kötött, ezért a dokumentumnak a mérés SHA-ját is hordoznia kell.

> ⚠ **Pre-flight (indítás előtt KÖTELEZŐ):** olvasd újra a `pubspec.yaml` `version:` sorát (a megíráskor `1.0.0+1`), az `android/app/build.gradle.kts` applicationId-ját és a `.github/workflows/` TÉNYLEGES listáját (a megíráskor 10 workflow). Az E13/E14 sáv körei ezeket elmozdíthatták — a §2 minden számát újra kell mérni, nem átvenni.

## 0.0 Miért nem kód-kör

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

### 6.1 Mérce-mátrix — melyik hibás implementációt melyik cella fogja pirosra

| Hibás implementáció | Melyik cella vált PIROSRA |
|---|---|
| A baseline „a jelenlegi állapot" felirattal, SHA nélkül készül | A1 |
| Egy állítás („a release CI zöld") bizonyíték-hivatkozás nélkül marad | A2 |
| A blocker-sor owner vagy zárási feltétel nélkül kerül a listára | A4 |
| A kör „menet közben" megjavít egy talált blokkolót a `lib/`-ben | A5 |
| A dokumentum egy nem létező `docs/release/rc-checklist.md`-re hivatkozik (későbbi kör terméke) | A6 |

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

## 11. Review — a Claude tölti ki
