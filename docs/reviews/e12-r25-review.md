# E12-R25 — Review (Claude, orchestrátor/reviewer)

- **Kör:** `E12-R25` — Release Candidate assembly workflow
- **Branch:** `sonnet-impl/e12-r25-release-candidate-assembly`
- **Implementer:** `sonnet-impl` (Claude Sonnet 5, `--effort high`)
- **Review-alap:** `4e6bb96d` (pre-flight) → `9e271ed8` (implementáció)
- **ADR:** [0488](../adr/0488-release-candidate-assembly-and-approval-gate.md) (D1–D8)
- **Dátum:** 2026-09-02
- **Kockázat:** `high` → `security-reviewer` KÖTELEZŐ, lefuttatva (lásd §4)

## 1. Mit mértem, hol

Read-only review izolált klónban (`/tmp/rc-review-e12-r25`, a munkapéldányból klónozva,
`prepare-flutter-generated.sh` után). A gate-et ÚJRAFUTTATTAM, és négy független
valódi-sértés próbát futtattam (mutate → mérj → állítsd vissza).

### Diff

```
 docs/release/rc-checklist.md                       |  89 ++
 docs/release/workflows/release-candidate.proposal.yml | 199 +++
 docs/rounds/e12-r25-release-candidate-assembly.md  | 105 +++
 test/tooling/rc_assembly_test.dart                 | 937 +++++++++++++++
 tool/release/assemble_rc.py                        | 245 ++++
 5 files changed, 1575 insertions(+)
```

**Scope:** `scope_audit=ok` (a wrapper gépi auditja, base `4e6bb96d`, 5 változott fájl).
Saját ellenőrzés: mind az 5 fájl a brief §4 engedélyezett listáján van; `.github/` alá
NULLA bájt került (`git diff --stat` nem tartalmaz `.github/` útvonalat) — a §0.0 /
ADR 0488 D1 védett-zóna szabálya tartva.

### Gate (izolált klón, csonkítatlanul)

```
$ tools/round-gate.sh test/tooling/rc_assembly_test.dart test/tooling/release_manifest_test.dart
    format                                                     zöld
    analyze                                                    zöld
    test test/tooling/rc_assembly_test.dart                    zöld
    test test/tooling/release_manifest_test.dart               zöld
    architecture                                               zöld
    secrets                                                    zöld
    l10n                                                       zöld
gate exit=0
```

## 2. Valódi-sértés próbák (a cellák MÉRNEK-e? — L563)

A zöld gate nem bizonyíték. Négy mutációt futtattam a klónban, mindegyiket visszaállítva:

| # | Mutáció | Várt piros cella | MÉRT eredmény |
|---|---|---|---|
| P1 | `assemble_rc.py`: a kötelező-bemenet ellenőrzés „figyelmeztet és folytat"-ra cserélve | A3 | **PIROS** — `+18 -8`, mind a 8 bukó cella A3 (a hét egyenkénti hiány + az „összes hiányzik" mátrixsor) |
| P2 | `proposal.yml`: `uses: ./.github/actions/flutter-gates` helyett bemásolt `run: flutter analyze lib/ test/ tool/` | A5 | **PIROS** — `+32 -2`, mindkét A5 cella (a composite-hívás ÉS a „nem másol gate-parancsot") |
| P3 | `proposal.yml`: a két gate-job `needs: approve-release-candidate` éle törölve (a jóváhagyás így nem előzi meg a buildet) | A1 | **PIROS** — `+33 -1`, az A1 tranzitív-`needs` cella |
| P4 | a kész csomagba egy többletfájl **alkönyvtárba** ejtve, majd `--verify` | A4 | **ZÖLD** ← **ez a lelet, lásd F1** |

A1/A3/A5 tehát valódi mérce. Az A6-ot a fájl saját mutációs próbája fedi (`needs`
pontos egyezés üres listával szemben), az A7 pedig a parszer fail-closed voltát és a
darabszám-kötést méri (L566 ellenszere: a parszolt job-/lépés-szám a nyers `RegExp`
előfordulásokhoz kötve, `package:yaml` nincs importálva, `python3` az egyetlen külső
bináris, `skip:` sehol).

## 3. Leletek

### F1 — MAJOR: a `--verify` FAIL-OPEN az alkönyvtárba csempészett többletfájlra

**Hol:** `tool/release/assemble_rc.py:159-161` (`verify_package`).

```python
actual_names = {
    item.name for item in package_dir.iterdir() if item.name != CHECKSUM_MANIFEST_NAME and item.is_file()
}
```

Az `iterdir()` NEM rekurzív, és az `is_file()` a könyvtárakat kiszűri — a csomag
alkönyvtáraiba tett fájlok tehát **nem léteznek** a verifikáló számára. Nem hibásak:
NEM LÉTEZNEK. Pontosan a [L566](../LESSONS.md) hibaosztály, csak fájlrendszeren.

**Reprodukció (mérve):**

```
$ python3 tool/release/assemble_rc.py --profile development --output-dir /tmp/rcprobe/out …
assemble_rc: package written to /tmp/rcprobe/out (7 file(s)).

$ mkdir -p /tmp/rcprobe/out/extra && echo "smuggled payload" > /tmp/rcprobe/out/extra/evil.apk
$ python3 tool/release/assemble_rc.py --verify --output-dir /tmp/rcprobe/out
assemble_rc: /tmp/rcprobe/out matches its checksum manifest exactly.
verify exit=0                                    ← FAIL-OPEN

$ rm -rf /tmp/rcprobe/out/extra; echo "smuggled" > /tmp/rcprobe/out/evil.apk   # kontroll: LAPOS
$ python3 tool/release/assemble_rc.py --verify --output-dir /tmp/rcprobe/out
  - present in package but not in the checksum manifest: evil.apk
verify exit=1                                    ← helyesen piros
```

**Miért MAJOR és nem MINOR:** a javasolt workflow a TELJES fát tölti fel
(`proposal.yml:185-190`, `path: dist/rc`, `actions/upload-artifact@v4`) — a becsempészett
fájl tehát benne lenne a kiadott RC-csomagban, miközben a csomag saját checksum-audit
lépése (`proposal.yml:182-184`) „matches its checksum manifest exactly" üzenettel
zöldet jelent. A kör A4 acceptance-kritériuma („a checksum-manifest minden fájlra
kiterjed, és eltérésre PIROS") és az ADR 0488 D5 („többlet fájl is eltérés") ezen a
bemeneten NEM teljesül.

**Javítás iránya:** az `actual_names` halmazt rekurzívan, a csomag gyökeréhez képest
RELATÍV útvonalakkal képezd (`package_dir.rglob('*')`, csak fájlok, POSIX-relatív
útvonal), és az `assemble_package` ugyanezt a relatív-útvonal alakot írja a manifestbe.
Kelljen hozzá cella, amely PONTOSAN a fenti alkönyvtáras bemeneten piros.

### F2 — MINOR: az `--output-dir` `rmtree`-je megsemmisítheti magukat a bemeneteket, elkapatlan tracebackkel

**Hol:** `tool/release/assemble_rc.py:107-120` (`assemble_package`), a `main:222`
`resolve_inputs` hívása UTÁN.

A bemenetek jelenlétét a `resolve_inputs` igazolja, de a `shutil.rmtree(output_dir)`
csak ezután fut. Ha az `--output-dir` valamelyik bemenet ŐSKÖNYVTÁRA, a törlés a
bemeneteket is elviszi, a `copyfile` pedig **elkapatlan** `FileNotFoundError`-rel száll el.

**Reprodukció (mérve):**

```
$ ls /tmp/rcprobe2/build
THIRD_PARTY_NOTICES.md ai-report.json app-release.apk lcov.info release-manifest.json sbom.json security-report.json
$ python3 tool/release/assemble_rc.py --profile development --output-dir /tmp/rcprobe2/build \
    --apk /tmp/rcprobe2/build/app-release.apk … --test-report /tmp/rcprobe2/build/lcov.info
Traceback (most recent call last):
  File "…/assemble_rc.py", line 120, in assemble_package
    shutil.copyfile(source, destination)
FileNotFoundError: [Errno 2] No such file or directory: '/tmp/rcprobe2/build/app-release.apk'
exit=1
$ ls -A /tmp/rcprobe2/build
(üres)
```

A modul-docstring ígérete („the output directory is left untouched — no half-built
package (D4)") ezen az úton nem tartható, és a felhasználó bemenetei megsemmisülnek.

**Miért MINOR:** az `--output-dir` operátor-vezérelt (a javasolt workflow a fix
`dist/rc`-t adja meg, ami egyik bemenetnek sem őse), tehát nem támadói felület —
de valódi adatvesztési csapda és hamis doc-comment-állítás.

**Javítás iránya:** a `rmtree` ELŐTT utasítsd el, ha az `output_dir` (feloldva) bármely
jelen lévő bemenet szülőláncában van, `AssembleError`-rel; és a `copyfile` hívást fogd
`OSError`-re `AssembleError`-be. Kelljen hozzá cella.

### F3 — NOTE: a `--verify` konzisztenciát bizonyít, nem hitelességet

`verify_package` a csomagot a SAJÁT `checksum-manifest.json`-jához köti; egy egyszerre
lecserélt fájl+manifest pár önkonzisztens marad. Ez tervezett scope (a hitelesség
horgonya az APK aláírása és a `release-manifest.json`), és az ADR 0488 D5 ki is mondja,
hogy a manifest önmagát nem hasheli — javítást nem kérek, de a §11-be és az
rc-checklistbe érdemes kimondottan beleírni, ha még nincs ott.

### F4 — NOTE: a jóváhagyási kapu ereje repo-beállításban él

`proposal.yml:48` — `environment: release-candidate-approval`. A `needs`-gráf helyes
(A1/A6 méri), de a tényleges blokkolás azon múlik, hogy a repo Settings-ben az
environmenthez be van-e állítva required reviewer. Ez a **telepítési lépés** (ADR 0488 D8)
ellenőrzési pontja, nem a diffé — a merge utáni két dispatch pontosan ezt bizonyítja.

## 4. security-reviewer (kötelező, `risk = high`)

Lefuttatva a teljes diffen. Verdikt: **nincs BLOCKER**, egy MINOR (= a fenti F2, függetlenül
megtalálva) és két NOTE (= F3, F4). Amit kifejezetten átnézett és rendben talált:

- **titok-kezelés:** a keystore-lépések bájtszinten a fán MÁR MŰKÖDŐ `release-apk.yml`
  mintáját követik (`umask 077`, `printf '%s' | base64 --decode`, `$RUNNER_TEMP`,
  `$GITHUB_OUTPUT`-ba csak útvonal, jelszavak lépés-szintű `env:`-ben,
  `if: always()` törlés) — titok logba nem kerül;
- **`upload-artifact` felület:** a keystore a workspace-en KÍVÜL (`$RUNNER_TEMP`) él, a
  `dist/rc`-t az assembler frissen építi közvetlenül a `--verify` és az upload előtt,
  és csak a 7 nevesített bemenetet + a manifestet másolja — az egyetlen rés az F1;
- **kapu-megkerülés:** `on: workflow_dispatch:` NULLA inputtal, egyetlen `environment:`,
  nincs `if:` bypass-ág;
- **path traversal:** `destination = output_dir / source.name` — a `Path.name` basename,
  így `--sbom ../../etc/x` is a csomagon belül landol; név-ütközésre fail-closed;
- **prompt-injection:** a riportok tartalmát az assembler SEHOL nem parszolja, csak
  másolja és hasheli;
- **gate-gyengítés:** nincs — a `quality-gates` a közös composite-ot hívja (D2).

## 5. Első verdikt

**CHANGES REQUESTED** — 1 MAJOR (F1) + 1 MINOR (F2). Mindkettő a kör saját, engedélyezett
fájljaiban javítható (`tool/release/assemble_rc.py`, `test/tooling/rc_assembly_test.dart`),
tehát javító kör következett, nem halt.

---

## 6. Javító kör (fix1, `1aa77d0c`) — a leletek zárása, függetlenül újramérve

Motor: `sonnet-impl`, ugyanaz a munkapéldány, a fenti leletlistával.
`scope_audit=ok` (base `f7072258`, 3 változott fájl: `assemble_rc.py`,
`rc_assembly_test.dart`, a brief §10-e — mind az engedélyezett listán).

### F1 — ZÁRVA

Javítás: a `verify_package` az `iterdir()` + `is_file()` lapos halmaz helyett
`package_dir.rglob('*')`-ot használ, csomag-gyökérhez képest **relatív, POSIX-alakú**
útvonalakkal; az `assemble_package` ugyanezt az alakot írja a manifest `path` mezőjébe.

**Független újramérés (friss klón, `/tmp/rc-review-e12-r25b`):**

```
$ python3 tool/release/assemble_rc.py --profile development --output-dir /tmp/rcprobe3/out …
assemble_rc: package written to /tmp/rcprobe3/out (7 file(s)).
$ mkdir -p /tmp/rcprobe3/out/extra && echo "smuggled payload" > /tmp/rcprobe3/out/extra/evil.apk
$ python3 tool/release/assemble_rc.py --verify --output-dir /tmp/rcprobe3/out
assemble_rc: package at /tmp/rcprobe3/out deviates from its checksum manifest:
  - present in package but not in the checksum manifest: extra/evil.apk
nested-extra verify exit=1                       ← a fail-open bezárva, a relatív út megnevezve
```

### F2 — ZÁRVA

Javítás: a `rmtree` ELŐTT feloldott (`resolve()`) útvonalakon ancestor-guard fut
(`resolved_output in source.resolve().parents` → `AssembleError`, megnevezve az
érintett bemenetet); a `shutil.copyfile` `OSError`-re `AssembleError`-be fordítva.

**Független újramérés:**

```
$ python3 tool/release/assemble_rc.py --profile development --output-dir /tmp/rcprobe4/build \
    --apk /tmp/rcprobe4/build/app-release.apk … --test-report /tmp/rcprobe4/build/lcov.info
assemble_rc: --output-dir /tmp/rcprobe4/build is the (or an ancestor) directory of the
  APK artifact (/tmp/rcprobe4/build/app-release.apk) — refusing to delete a mandatory input
ancestor-output exit=1
$ ls -A /tmp/rcprobe4/build
THIRD_PARTY_NOTICES.md ai-report.json app-release.apk lcov.info release-manifest.json sbom.json security-report.json
                                                 ← MIND a hét bemenet megvan, traceback nincs
```

### A két ÚJ cella valódi mérce (L563) — a JAVÍTÁS ELŐTTI eszközzel PIROS

```
$ git checkout f7072258 -- tool/release/assemble_rc.py     # a fix1 ELŐTTI assembler
$ flutter test test/tooling/rc_assembly_test.dart
00:01 +34 -2: Some tests failed.
Failing tests:
  … A2/F2 — an --output-dir that is the mandatory inputs' own parent directory is refused
     BEFORE the rmtree, naming the endangered input, and every input file survives the run
  … A4/F1 — an extra file smuggled into a package SUBDIRECTORY after assembly … is STILL
     a non-zero --verify exit, naming its manifest-relative path
```

Pontosan a két új cella bukik, más nem — tehát mindkettő a saját javítását méri, nem
egy tágabb ablakot. (A restore után `git status --short` üres: a próba nem hagyott nyomot.)

### Gate a fix1 után (izolált klón, csonkítatlanul)

```
$ tools/round-gate.sh test/tooling/rc_assembly_test.dart test/tooling/release_manifest_test.dart
    format / analyze / test rc_assembly / test release_manifest / architecture / secrets / l10n
    → mind ZÖLD          gate exit=0
```

### F3 / F4 (NOTE)

Javítást nem kértek, és nem is történt. Az F4 (a required reviewer beállítása a
`release-candidate-approval` environmenthez) a merge UTÁNI telepítési lépés ellenőrzési
pontja — a §11-be kerülő két dispatch pontosan ezt bizonyítja.

## 7. VÉGSŐ DÖNTÉS: **APPROVED**

Nyitott BLOCKER/MAJOR/MINOR: **nincs**. A hat acceptance-kritérium (A1–A6) mindegyike
mögött gépi cella áll, és a cellák mérő voltát négy + két valódi-sértés próba igazolta.
A merge feltétele változatlanul a teljes zöld kapu a merge SHA-n (Full Gate + Router CI).
