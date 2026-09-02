# E12-R34 — független review (ADR 0055)

- **Kör:** `E12-R34` — Post-launch stabilization, hotfix és incident automation
- **Branch:** `sonnet-impl/e12-r34-post-launch-stabilization-and-hotfix`
- **Mért HEAD:** `02e4e49a` (implementer commit), pre-flight bázis `54eccb63`
- **Implementer:** Claude Sonnet 5 (`sonnet-impl`)
- **Reviewer:** Claude Opus 5 (orchestrátor) + `security-reviewer` ügynök
  (a brief §0.0 `risk = "high"` miatt KÖTELEZŐ)
- **Mérési identitás:** izolált klón `/tmp/review-e12-r34`, exact HEAD `02e4e49a`,
  a gate a klón MUNKAKÖNYVTÁRÁBÓL futtatva (L363)
- **Dátum:** 2026-09-02

## 1. Kör #1 — VERDIKT: **CHANGES REQUESTED** (4 MAJOR)

### 1.1 Ami rendben van

**Gépi kapuk (izolált klón, `02e4e49a`):**

```
tools/round-gate.sh test/tooling/hotfix_policy_test.dart test/tooling/rc_assembly_test.dart
    format                                                     zöld
    analyze                                                    zöld
    test test/tooling/hotfix_policy_test.dart                  zöld
    test test/tooling/rc_assembly_test.dart                    zöld
    architecture                                               zöld
    secrets                                                    zöld
    l10n                                                       zöld
```

- **Scope:** `scope_audit=ok`, `scope_audit_changed=8` — a diff pontosan a brief
  §4 engedélyezett listáján marad, tilos zónába nem nyúlt. A `gate_shape=ok`.
- **A SZÁLLÍTOTT javaslat-dokumentum maga helyes:** a scan- és signing-lépés
  feltétel nélküli, PONTOSAN egy job hordoz `environment:` kulcsot, a job-gráf
  a Kör 25 RC-precedensét követi (jóváhagyás → gate → build), a composite a
  `uses: ./.github/actions/flutter-gates` hívással megy, a keystore-higiénia
  (umask 077, `env:`-en át adott base64, `if: always()` törlés) megegyezik a
  precedenssel.
- **A tesztfájl fegyelmezett:** A1–A7 csoportok, a §6.1 mátrix minden sorára
  mutációs próba, a §6.3 numerikus cellahármas (1/1/0), meta-csoport a D7
  fail-closed garanciákra, `package:yaml` nincs importálva, `python3` az
  egyetlen külső bináris. A §6.2 valódi-sértés próba elvégezve és dokumentálva.
- **Adatvédelem:** a postmortem-sablon és a két post-launch riport csak
  aggregált metrikákat kér, nyers felhasználói tartalmat nem — nincs lelet.

### 1.2 A lelet magja

**A kör terméke maga az ŐR — és az őr három valódi kapu-gyengítést átenged.**
A javaslat-dokumentum jó; a `verify_hotfix.py` statikus módja viszont nem tartja
azt a szerződést, amit az ADR 0490 D1/D3 és a brief A2/A6 cellái ígérnek.
Egy `risk = "high"` körben, amelynek KIMONDOTT indoklása „ha megkerülhetővé
válik a security/signing kapu, az a teljes release-védelmet üresíti ki", ez a
kör érdemi hibája: ma zöld, holnap — az első valódi hotfix-sürgősségben —
hamis zöldet ad arra a gyengítésre, ami ellen épült.

Minden lelet REPRODUKÁLVA, a valódi javaslatból származtatott fixtúrán.

---

### MAJOR-1 — A statikus mérce vak a JOB-szintű `if:`-re és `continue-on-error:`-ra

**Hol:** `tool/release/verify_hotfix.py:321-350` (a `static_check` csak
`step.if_condition` / `step.continue_on_error` mezőt néz — kizárólag
lépés-szinten).

**Miért számít:** a brief §6.1 mátrix ELSŐ sora — „A javaslat
`if: inputs.skip_scan != true` ágat kap → **A2** PIROSRA" — a gyengítést
lépés-szinten fogja meg. Ugyanaz a gyengítés egy indent-szinttel feljebb,
job-szinten, ÁTMEGY. A GitHub Actions egy `continue-on-error: true` jobot a
`needs:` szempontjából nem-blokkolónak tekint, tehát a **bukott** security scan
után a signing lefut — pontosan az a megkerülés, amit a D1 tilt.

**Reprodukció (job-szintű `continue-on-error`):**

```
$ python3 tool/release/verify_hotfix.py --workflow /tmp/r34probe/job-level-coe.yml
verify_hotfix (static mode): ok — /tmp/r34probe/job-level-coe.yml
exit=0
```

(A fixtúra a VALÓDI javaslat, egyetlen sorral kiegészítve: `continue-on-error: true`
a `security-scan:` job fejlécében.)

**Reprodukció (job-szintű `if:` semleges nevű inputtal):** a `skip|emergency`
névminta megkerülhető egy `fast_track` nevű inputtal, és az `if:` a job fejlécére
kerül:

```
$ python3 tool/release/verify_hotfix.py --workflow /tmp/r34probe/job-level-if.yml
verify_hotfix (static mode): ok — /tmp/r34probe/job-level-if.yml
exit=0
```

**Elvárt:** exit 1 mindkettőre. A `static_check` a scan/sign lépést TARTALMAZÓ
job `fields`-jét is vizsgálja `if` / `continue-on-error` kulcsra, és a
`_SKIP_INPUT_NAME_PATTERN`-től FÜGGETLENÜL tiltsa a scan/sign jobot feltételessé
tevő bármely `if:`-et.

---

### MAJOR-2 — A mérce a lépés NEVÉT nézi, a tartalmát soha

**Hol:** `tool/release/verify_hotfix.py:283-284, 314-350` — a
`_SECURITY_SCAN_STEP_NAME` / `_SIGNING_STEP_NAME` regex a `step.name`-re
illeszkedik; a `run:` törzset a szkript egyetlen ponton sem vizsgálja.

**Miért számít:** egy „Release security scan" nevű lépés, amelynek törzse
`echo 'skipping scan for speed'`, teljesíti az egész D1 scan-követelményt. A
kapu neve megmarad, a kapu maga eltűnik — és a mérce ezt nem látja.

**Reprodukció:**

```
$ python3 tool/release/verify_hotfix.py --workflow /tmp/r34probe/decoy-scan.yml
verify_hotfix (static mode): ok — /tmp/r34probe/decoy-scan.yml
exit=0
```

(A fixtúra a VALÓDI javaslat, benne az egyetlen csere:
`python3 tool/release/security_scan.py --format json > …` → `echo 'skipping scan for speed'`.)

**Elvárt:** exit 1. A scan-lépésre kötelező tartalmi állítás: a `run:` törzse
hívja a `tool/release/security_scan.py`-t. A signing-lépésre ugyanígy: a törzs
vagy a lépés `env:`-je kösse a production signing előfeltételeit
(`STRUMSIGHT_REQUIRE_RELEASE_SIGNING`, illetve `flutter build apk --release`).

---

### MAJOR-3 — A D3 jóváhagyás-ellenőrzés DENYLISTÁRA épül, nem allowlistára

**Hol:** `tool/release/verify_hotfix.py:285` —
`_RELEASE_VERB = re.compile(r"build|sign|assembl|upload", re.IGNORECASE)`, és
`:364-369`: az a job, amelynek egyetlen lépés-neve/`uses:`-a sem illeszkedik a
mintára, a tranzitív `needs:` ellenőrzés alól **kimarad** (`continue`).

**Miért számít:** a D3 azt ígéri, hogy „minden építő / aláíró / összeállító /
feltöltő job tranzitívan `needs:`-eli a jóváhagyót". A denylistás
megvalósításban egy productionbe **publikáló** job, amelynek a lépés-nevei
kívül esnek a négy szón, `needs:` NÉLKÜL is átmegy.

**Reprodukció:** a VALÓDI javaslat kiegészítve egy `publish-hotfix` jobbal
(`needs:` nélkül, „Publish to Play Store" lépéssel):

```
$ python3 tool/release/verify_hotfix.py --workflow /tmp/r34probe/no-needs-publish.yml
verify_hotfix (static mode): ok — /tmp/r34probe/no-needs-publish.yml
exit=0
```

**Elvárt:** exit 1. Fordítsd meg a logikát **fail-closed allowlistre**: a
jóváhagyó jobon kívül MINDEN job tranzitívan `needs:`-elje a jóváhagyót, kivéve
egy szűk, kimondott, ártalmatlan halmazt (pl. tisztán olvasó lint-job).
Ismeretlen job = sértés, nem kivétel.

---

### MAJOR-4 — A javaslat `${{ inputs.* }}`-ot interpolál `run:` törzsbe (GHA script injection)

**Hol:** `docs/release/workflows/hotfix.proposal.yml:82, 85, 86, 164, 188`.

**Miért számít:** a GitHub Actions a `${{ }}` kifejezést **szövegesen** helyettesíti
a shell-szkriptbe, még a végrehajtás előtt. Egy `incident_id` vagy `summary`
érték, amely idézőjelet és `;`-t tartalmaz, kitör a stringből és tetszőleges
parancsot futtat. A `:164` a `build-hotfix` jobban van, amelynek a checkoutja
(`:149`) MEGELŐZI, és amelynek későbbi lépései a production keystore-t és a
signing titkokat kezelik — telepítés után ez valós kiszivárogtatási út. A `:188`
(`--build-name=${{ inputs.version }}`) ráadásul idézőjel nélkül áll.

**A repó SAJÁT precedense ezt kerüli:** a
`docs/release/workflows/release-candidate.proposal.yml` és a
`.github/workflows/release-apk.yml` egyetlen `run:` törzsbe SEM interpolál
`inputs`/`github.event` értéket (mérve: a tíz telepített workflow közül
egyedül a `ml-train.yml:57` teszi, az viszont nem release/signing útvonal, és
nem ennek a körnek a terméke). A titkokat mindkettő `env:`-en át köti és
shell-változóként hivatkozza — ugyanez a helyes alak az inputokra is.

**Elvárt javítás:** minden input `env:` blokkon át kötve, a törzsben idézett
shell-változóként (`"$INCIDENT_ID"`), a `--build-name="$VERSION"` alakkal együtt.

---

### MINOR-1 — `1.2` → `1.2.0` emelésnek számít

**Hol:** `tool/release/verify_hotfix.py:387-391, 405` — a tuple-összehasonlítás
szerint `(1,2) < (1,2,0)`, tehát a `--previous-version 1.2 --version 1.2.0`
átmegy, holott szemantikailag ugyanaz a verzió. Kis kockázat (a
`pubspec.yaml` mindig háromtagú), de a `_parse_version` normalizálhatna azonos
hosszra. Nem blokkoló.

### NOTE-ok (nem javítandók ebben a körben)

1. A monotonitás az operátor által megadott `--previous-version`-re épül, nem a
   `pubspec.yaml`-ból mért valóságra — a kérés-mód így az operátor őszinteségét
   feltételezi. A telepítés utáni körben érdemes a `pubspec`-hez kötni.
2. A verzió-elemzés elfogad vezető nullát (`01.2.3`).
3. A `_SIGNING_STEP_NAME` (`sign`) illeszkedik a „design" szóra is — ez
   SZIGORÍT (több lépésre követeli meg a feltétel-nélküliséget), tehát nem hiba.
4. A `permissions: contents: read` minimális — helyes.

## 2. A javító kör tennivalói

1. **MAJOR-1** — job-szintű `if:` és `continue-on-error:` tiltása a scan/sign
   lépést tartalmazó jobokon, a bemenet nevétől függetlenül.
2. **MAJOR-2** — tartalmi állítás a scan- és signing-lépésre (`run:` törzs,
   illetve `env:`), nem csak névillesztés.
3. **MAJOR-3** — a D3 ellenőrzés fail-closed allowlistre fordítása.
4. **MAJOR-4** — `${{ inputs.* }}` kivezetése a `run:` törzsekből, `env:`-kötés
   és idézett shell-változók.
5. **MINOR-1** — verzió-hossz normalizálása (opcionális, de olcsó).

Minden javításhoz **mutációs cella** kell a `hotfix_policy_test.dart`-ban: a
fenti négy fixtúra-alak mindegyike fordítsa PIROSRA a saját celláját. A
mutációs próbák a fixtúrákon fussanak, ne a valódi fájlon.

## 3. Kör #2 — a javító kör után — VERDIKT: **APPROVED**

- **Mért HEAD:** `7d31c868` (a javító commit `1dcc16c0` + az `origin/main`
  `70eefdf4` upstream-merge, ADR 0086 §2)
- **Mérési identitás:** friss izolált klón `/tmp/review-e12-r34b`, exact HEAD,
  a gate a klón munkakönyvtárából
- **Scope:** `scope_audit=ok`, `scope_audit_changed=4` — a javító kör a
  `verify_hotfix.py`, a `hotfix.proposal.yml`, a `hotfix_policy_test.dart` és a
  brief §10 fájlokat érintette, mind az engedélyezett listán.

### 3.1 Leletenkénti zárás — a kör #1 fixtúrái ÚJRAFUTTATVA a javított mércén

Minden lelet ugyanazon a fixtúrán mérve, amelyen a kör #1-ben hamis zöldet adott:

| Lelet | Kör #1 | Kör #2 | A javított mérce üzenete |
|---|---|---|---|
| MAJOR-1 (job-szintű `continue-on-error`) | `exit=0` ❌ | **`exit=1`** ✅ | `security-scan-unconditional: job "security-scan" carries "continue-on-error:" — forbidden (ADR 0490 D1)` |
| MAJOR-1 (job-szintű `if:`, semleges nevű input) | `exit=0` ❌ | **`exit=1`** ✅ | `security-scan-unconditional: job "security-scan" carries an "if:" condition — forbidden (ADR 0490 D1)` |
| MAJOR-2 (névben megmaradó, tartalmában üres scan) | `exit=0` ❌ | **`exit=1`** ✅ | `security-scan-content: job "security-scan" has no step whose "run:" body invokes tool/release/security_scan.py — a step name alone is not the gate (ADR 0490 D1)` |
| MAJOR-3 (`publish-hotfix` job `needs:` nélkül) | `exit=0` ❌ | **`exit=1`** ✅ | `approval-gate-transitive: … fail-closed: every job other than the approval gate itself must need it, not only jobs whose steps happen to match a build/sign/upload verb (ADR 0490 D3)` |
| MAJOR-4 (GHA script injection) | 5 találat ❌ | **0 találat** ✅ | egyetlen `run:` törzs sem tartalmaz `${{ }}`-t (mérve a javaslaton; a `hotfix_policy_test.dart:709,739` gépi cellát is visel rá) |
| MINOR-1 (`1.2` → `1.2.0`) | `exit=0` ❌ | **`exit=1`** ✅ | `version-strictly-greater: --version "1.2.0" is not strictly greater than --previous-version "1.2"` |

### 3.2 ÚJ, a javításra nem illesztett próbák — a fix általános, nem fixtúra-szabott

A javító kör promptja négy fixtúra-alakot nevezett meg. Két olyan próbát is
futtattam, amit **nem** kapott meg — mindkettőt megfogja:

| Új próba | Eredmény |
|---|---|
| a signing tartalma kiürítve, a NEVE megtartva (a MAJOR-2 tükörképe a signing oldalon) | **`exit=1`** — `production-signing-content: job "build-hotfix" has no step whose "env:" binds STRUMSIGHT_REQUIRE_RELEASE_SIGNING and whose "run:" body calls "flutter build apk --release"` |
| job-szintű `if:` a **build** jobon (nem a scan jobon, amit a fixtúra használt) | **`exit=1`** — `production-signing-unconditional: job "build-hotfix" carries an "if:" condition` |

A valódi javaslat mindeközben zöld: `verify_hotfix (static mode): ok`, és a
kérés-mód a `0 / 0 / 1` mintát adja (§6.3 „fölötte/alatta/rajta").

### 3.3 Gépi kapuk a javító HEAD-en (`/tmp/review-e12-r34b`, `7d31c868`)

```
tools/round-gate.sh test/tooling/hotfix_policy_test.dart test/tooling/rc_assembly_test.dart
    format                                                     zöld
    analyze                                                    zöld
    test test/tooling/hotfix_policy_test.dart                  zöld
    test test/tooling/rc_assembly_test.dart                    zöld
    architecture                                               zöld
    secrets                                                    zöld
    l10n                                                       zöld
```

A `hotfix_policy_test.dart` 37 cellát visel (kör #1: 34 → +7 új mutációs cella,
a csoport-átrendezéssel együtt).

### 3.4 Nyitott lelet

**Nincs.** A négy MAJOR és az egy MINOR mind zárva, mindegyik a saját,
független reprodukciójával mérve. A NOTE-ok (a `--previous-version` operátori
bemenet, vezető nulla) továbbra is előremutató megjegyzések, nem e kör
kötelezettségei — a javaslat telepítése utáni körben érdemes a `pubspec.yaml`-hoz
kötni a monotonitást.

## VÉGSŐ DÖNTÉS: **APPROVED**
