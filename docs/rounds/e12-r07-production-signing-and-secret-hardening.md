# E12-R07 — Production signing és secret hardening

- **Státusz:** PREPARED (előre megírva 2026-08-27, kód olvasva: `main @ 9ca4a0dc`)
- **Típus:** Chapter 12 (Release Roadmap, Sprint Planning & Final Integration), Kör 7
- **Kör-azonosító:** `E12-R07`
- **Branch:** `<motor>/e12-r07-production-signing-and-secret-hardening`
- **Előfeltétel:** `E12-R06` merge-elve (a certificate fingerprint a provenance manifest mezője lesz)
- **Brief szerzője:** Claude (Opus 5)
- **Előre kiosztott ADR:** `ADR 0448` — a szám FOGLALT (Chapter 12 batch-tartomány).

**Visszakeresett előzmény:** `node tools/knowledge-rag.mjs --corpus lessons,halts,adr --top 5 "production signing keystore secret debug certificate release build"` → **[ADR 0062](../adr/0062-ci-gate-chain-and-fail-closed-release-signing.md)** (score 2.94) — a fail-closed release signing MÁR eldöntött és implementált; ez a kör a MEGLÉVŐ mechanizmust egészíti ki a debug-tanúsítvány explicit elutasításával, a fingerprint-rögzítéssel és a kulcs-runbookkal, és nem tervezi újra.

> ⚠ **Pre-flight (indítás előtt KÖTELEZŐ):** olvasd újra az `android/app/build.gradle.kts` `releaseSigningRequired` / `GradleException` ágait (a megíráskor: hiányos konfigra és üres keystore-ra is dob) és a `release-apk.yml` `signing-prerequisites` jobját. Ami MÁR fail-closed, azt nem kell újra megírni — a §2 méri, mi hiányzik.

## 0.0 Pre-flight brief-revízió (orchesztrátor, 2026-08-28, `main @ eccf89cf`)

**Ahol a §0.0 és bármely későbbi szakasz eltér, a §0.0 nyer.** A normatív
forrás a pre-flightban megírt
[`docs/adr/0448-production-signing-policy-and-secret-hardening.md`](../adr/0448-production-signing-policy-and-secret-hardening.md).

**Visszakeresés (ADR 0312):** `--corpus lessons,halts,adr` →
[ADR 0062](../adr/0062-ci-gate-chain-and-fail-closed-release-signing.md) (a
„debug-signing fallback, ha nincs secret" alternatíva MÁR elutasítva: „egy
»release« nevű, debug kulcsú artifact rosszabb, mint a hiányzó artifact") ·
[L528](../LESSONS.md#l528) (E12-R04: egy szigorítást szolgáló ág MAGA echózta a
titkokat a logba — ez a kör legközelebbi rokona) · `--corpus lessons,halts` →
[L38](../LESSONS.md#l38) (a „csinált-e valamit a modell" ≠ scope-audit) ·
teljes korpusz → nincs további releváns előzmény.

### R1 — „Production `buildType`" a fán NEM létezik; a diszkriminátor a `STRUMSIGHT_REQUIRE_RELEASE_SIGNING`

MÉRVE: `android/app/build.gradle.kts:107–117` egyetlen `release` buildType-ot
definiál; `production`/`lab` buildType, flavor vagy dimenzió nincs. Ugyanezt a
`release` buildType-ot építi mind a három APK-workflow:
`release-apk.yml:113–121` (négy `STRUMSIGHT_RELEASE_*` env **+**
`STRUMSIGHT_REQUIRE_RELEASE_SIGNING: 'true'`), `lab-apk.yml:36` és
`build-apk.yml:63` (signing env **nélkül** → debug fallback).

A §3/§5.3 „production `buildType`" fordulata ezért **buildType-alapon nem
implementálható**: vagy semmit nem véd, vagy a Lab APK-t is megállítja. A
szigorítás horgonya az **ADR 0448 D1** szerint a
`STRUMSIGHT_REQUIRE_RELEASE_SIGNING` kapcsoló (és a ténylegesen megadott
signing értékek), nem a buildType neve. Az **A1** és **A3** cella ezt méri.

### R2 — A fingerprint SIDECAR fájlba megy; a release manifest sémája NEM változik

MÉRVE: `tool/generate_release_manifest.dart` (E12-R06) manifest-objektuma
`schemaVersion` · `app{version,buildNumber,shortSha,channel}` · `modelPackage` ·
`knowledgePackage` · `artifacts[]` — **certificate/signing mező nincs**. A
generátor a kör **tilos zónája** (nincs az engedélyezett listán), a
`schemaVersion` emelése pedig az E12-R06 determinizmus-szerződését érintené.

Az **A5** ezért így értendő (ADR 0448 D4): a javasolt lépés a fingerprintet a
**`dist/signing-certificate.json`** sidecarba írja (fingerprint + kulcs-alias,
titok soha), és a MEGLÉVŐ, ismételhető **`--artifact dist/signing-certificate.json`**
flaggel (`tool/generate_release_manifest.dart:57–58`) köti a manifesthez — a
manifest `artifacts[]` listája így névvel, úttal és sha256-tal hordozza. A
„manifest sémájának megfelelő mező" kifejezés **nem** új manifest-mezőt jelent.

### R3 — Az A2/A4 workflow-oldala OLVASÁS; a mai mért állapot már fail-closed

MÉRVE `.github/workflows/release-apk.yml`: a `signing-prerequisites` job
(9–36. sor) a négy secret meglétét `::error::`-rel kényszeríti a build ELŐTT;
`Materialize production keystore` `umask 077` mellett `$RUNNER_TEMP`-be dekódol;
`Remove production keystore` `if: always()` mellett törli; **jelszó- vagy
kulcsanyag-echo egyetlen lépésben sincs.** Az A2/A4 tehát **regresszió-őr** a
meglévő viselkedésre, nem új funkció — a `verify_signing_policy.py` a
workflow-t OLVASSA. A `.github/workflows/**` írása strukturálisan lehetetlen:
`.claude/gate-edit-policy` a fán nem létezik (`tools/gateguard-scan.py`).

### R4 — Az audit KÉTIRÁNYÚ, fixture-vezérelt; az egyirányú cella nem elfogadható

ADR 0448 D6: a `verify_signing_policy.py` a mérendő fájlok útvonalát
**paraméterben** kapja, hogy fixture-ön is futhasson. A cella (i) a valós
fájlokon exit 0-t, (ii) egy fixture-ön — amelyből az elutasító ág hiányzik,
vagy amely `androiddebugkey`-t rendel production ághoz — **nem-nulla**
kilépést vár, a megsértett szabály nevével. Csak-zöld, „string van-e a
fájlban" alakú cella a mérés hiányát mutatná zöldnek
([L220](../LESSONS.md#l220) hibaosztálya).

A Python eszköz **kizárólag stdlib**; a Dart cella `Process.runSync('python3', …)`
alakban hívja (ADR 0447 D5 precedense), és `python3` hiányában **PIROS**, néma
skip nincs. A javaslat YAML-jét a tesztfájlban élő **korlátozott
részhalmaz-parser** ellenőrzi — `package:yaml` a fán csak tranzitív
(ADR 0444 D3).

### R5 — A §6.1 valódi-sértés próbája a KÖTELEZŐ alak

A próba: távolítsd el a D2 szerinti elutasító ágat a valós
`android/app/build.gradle.kts`-ből → `flutter test test/tooling/signing_policy_test.dart`
→ az **A1** cellának PIROSNAK kell lennie (a bukó cella nevével és a hibaüzenet
első sorával a §10-ben) → állítsd vissza. A §6.1 „fixture aliasát
`androiddebugkey`-re" próbája ezen felül, második próbaként dokumentálandó.
A „visszaállítottam" önmagában nem bizonyíték — a kimenet kell.

## 0.0.1 Két korlát: nincs Android SDK, és a workflow VÉDETT

**(a)** Ezen a boxon nincs Android SDK, a release-build a CI-ban fut — a signing-viselkedés lokális bizonyítéka ezért a Gradle-fájl statikus auditja (`verify_signing_policy.py`), a futásidejű bizonyíték a CI-é.

**(b)** A `.github/workflows/**` a `protect_factory_files.py` `PROTECTED_GLOBS` listáján van (ADR 0321), és az ADR 0372 álló felhatalmazásának fájlja (`.claude/gate-edit-policy`) a fán MA NEM létezik — a pre-flight ezt MÉRTE (`tools/gateguard-scan.py`). Az implementer-session tehát a workflow-t strukturálisan nem írhatja (`H-GATEGUARD`). A fingerprint-lépés ezért **javaslatként** készül (`docs/release/workflows/…`), és a beillesztés + dispatch orchesztrátor/emberi lépés a merge UTÁN. A Gradle-oldal (`android/app/build.gradle.kts`) NEM védett, azt a kör maga írja.

```ai-router
schema_version = 1
risk = "high"
allowed_paths = [
  "android/app/build.gradle.kts",
  "docs/release/workflows/release-apk-fingerprint.proposal.md",
  "tool/release/verify_signing_policy.py",
  "docs/security/signing-key-runbook.md",
  "test/tooling/signing_policy_test.dart",
  "docs/rounds/e12-r07-production-signing-and-secret-hardening.md",
]
gate_tests = [
  "test/tooling/signing_policy_test.dart",
  "test/tooling/check_secrets_test.dart",
]
native_gate = true
```

**Kockázat = high, indoklás:** a diff az aláírási kulcsok és CI-titkok kezelésén dolgozik; egy elrontott ág debug-aláírású artefaktumot engedne production csatornára, vagy kulcsanyagot szivárogtatna a logba. A `security-reviewer` futtatása a review-ban KÖTELEZŐ.

## 0. Kör-jelzés és STOP-protokoll

```bash
tools/codex-signal.sh progress "<egy sor>"
tools/codex-signal.sh done "<egy sor>"
tools/codex-signal.sh stopped "<egy sor>"
tools/codex-signal.sh blocked "<egy sor>"
```

**STOP-protokoll:** ha a munkához a `build-apk.yml` / `lab-apk.yml` vagy bármely kulcsanyag repóba helyezése kellene, a kimenet a `stopped` jelzés — a lista tágítása és titok commitolása TILOS.

## 1. Cél

A debug-aláírású production artefaktum lehetőségének megszüntetése, a kulcskezelés dokumentált védelme és a tanúsítvány-ujjlenyomat provenance-hoz kötése.

## 2. Jelenlegi állapot — mért tények

- `android/app/build.gradle.kts`: `key.properties` VAGY környezeti változók a forrás; hiányos konfigra `GradleException` („Incomplete release signing configuration"), `releaseSigningRequired` mellett kötelező konfig, üres/hiányzó keystore-fájlra szintén kivétel. **A debug-tanúsítvány EXPLICIT elutasítása nincs** — a jelenlegi védelem a konfiguráció MEGLÉTÉT követeli, nem a tanúsítvány mibenlétét.
- `.github/workflows/release-apk.yml`: `signing-prerequisites` job hiányzó secretre `::error::`-rel áll meg; a keystore materializálás után `Remove production keystore` lépés törli a kulcsot.
- `test/tooling/check_secrets_test.dart` **létezik** — a secret-scan regresszió-őre ([L220](../LESSONS.md#l220): a fixture-literálnak tartalmaznia kell a scanner placeholder-szavait, különben a teszt némán semmit nem mér).
- `docs/security/` MA két Community-dokumentumot tartalmaz; `signing-key-runbook.md` **nem létezik**.
- `tool/release/` a Kör 6 után létezik (`generate_sbom.py`, `verify_artifacts.py`).

## 3. Scope

**Benne van:** a Gradle release-ág kiegészítése a **debug keystore explicit elutasításával** (a jól ismert `~/.android/debug.keystore` és a `androiddebugkey` alias production ágon kivételt dob) · a dev/Lab és production signing config SZÉTVÁLASZTÁSA úgy, hogy a Lab build továbbra is dev kulccsal működik · `tool/release/verify_signing_policy.py` (a Gradle-fájl és a workflow statikus auditja: van-e olyan ág, ami production `buildType`-ra debug signing configot rendel; kerülhet-e kulcsanyag a logba) · `docs/release/workflows/release-apk-fingerprint.proposal.md` — a certificate fingerprint provenance manifestbe írásának JAVASOLT workflow-lépése (a fingerprintet a keystore-ból olvassa, jelszót nem echóz, `::add-mask::`-kal) · `docs/security/signing-key-runbook.md` (backup, rotáció, hozzáférés, elvesztés esetén követendő lépések).

**NINCS benne (tilos):**

- **Bármilyen kulcsanyag, jelszó vagy keystore fájl commitolása** — beleértve a teszt-fixture-t is: a fixture kizárólag SZINTETIKUS, nem valódi kulcs.
- `build-apk.yml` / `full-gate.yml` / `lab-apk.yml` módosítása.
- Store-feltöltés vagy tényleges kulcsrotáció végrehajtása.
- `docs/adr/**` — az ADR 0448-at a Claude írja.

## 4. Engedélyezett fájlok

| Útvonal | Indok |
|---|---|
| `android/app/build.gradle.kts` | debug-tanúsítvány elutasítás + config szétválasztás |
| `docs/release/workflows/release-apk-fingerprint.proposal.md` | ÚJ — a fingerprint-lépés JAVASLATA (a beillesztés emberi lépés) |
| `tool/release/verify_signing_policy.py` | ÚJ — statikus signing-policy audit |
| `docs/security/signing-key-runbook.md` | ÚJ — kulcs-runbook |
| `test/tooling/signing_policy_test.dart` | a §6 cellái |

**Tilos zóna:** `.github/workflows/**` (MIND, a §0.0/b szerint) · `android/key.properties` (és bármely keystore) · `lib/**` · `backend/**` · `docs/adr/**` · `tools/**`

## 5. Kötött architekturális döntések (ADR 0448)

### 5.1 A production ág a TANÚSÍTVÁNYT utasítja el, nem csak a hiányzó configot

A védelem tárgya a debug-alias/debug-keystore használata, nem a konfiguráció megléte. **NEM elfogadható gyengítés:** a jelenlegi „van-e konfig" ellenőrzés elegendőnek nyilvánítása — egy `key.properties`, ami a debug keystore-ra mutat, ma átmenne.

### 5.2 Titok SOSEM kerül logba és repóba

A fingerprint-kiolvasás jelszót nem echóz; a workflow `::add-mask::`-ol minden titkot. **NEM elfogadható gyengítés:** „csak debug célból" ideiglenesen kiírt érték.

### 5.3 A Lab build dev kulccsal működőképes marad

A szigorítás kizárólag a production `buildType`-ra vonatkozik. **NEM elfogadható gyengítés:** globális tiltás, ami a Lab APK-t is megállítja (a Lab APK a user napi diagnosztikai eszköze).

## 6. Acceptance criteria

| # | Kritérium | Bizonyíték |
|---|---|---|
| A1 | Production ág + debug alias/keystore → build hiba (nem figyelmeztetés) | `signing_policy_test.dart` (Gradle-fájl statikus cellája) + `verify_signing_policy.py` |
| A2 | Production signing secret hiányában a CI a build ELŐTT megáll — a MEGLÉVŐ `signing-prerequisites` job MÉRT viselkedése, a kör ezt nem gyengíti | `verify_signing_policy.py` statikus cellája a workflow-n (OLVASÁS) |
| A3 | A Lab build dev kulccsal továbbra is konfigurálható | `signing_policy_test.dart` |
| A4 | A workflow egyetlen lépése sem írja ki a keystore jelszót vagy a kulcsanyagot | `verify_signing_policy.py` + `check_secrets_test.dart` |
| A5 | A javaslat-lépés YAML-je valid, a fingerprintet a manifest sémájának megfelelő mezőbe írja, és jelszót nem ír ki | `signing_policy_test.dart` (YAML-parse + maszkolás-cella) |
| A6 | `docs/security/signing-key-runbook.md` megadja a backup, rotáció, hozzáférés és kulcs-elvesztés lépéseit, felelőssel | a dokumentum |
| A7 | A repóban nincs valódi kulcsanyag; a fixture szintetikus | `check_secrets_test.dart` |

### 6.1 Mérce-mátrix — melyik hibás implementációt melyik cella fogja pirosra

| Hibás implementáció | Melyik cella vált PIROSRA |
|---|---|
| A debug-alias ellenőrzés figyelmeztetést ír, de nem dob | A1 |
| A tiltás a `buildType`-tól függetlenül él → a Lab ág is elhasal | A3 |
| A fingerprint-lépés `echo`-zza a jelszót vagy a teljes `keytool` kimenetet | A4 |
| A fixture valódi keystore-t tartalmaz | A7 |

**Valódi-sértés próba (KÖTELEZŐ, a §10-ben dokumentálva):** állítsd a szintetikus fixture aliasát `androiddebugkey`-re a production ágon, futtasd a §7 gate-et → az **A1** cellának PIROSNAK kell lennie → állítsd vissza.

## 7. Kötelező ellenőrzések

```bash
tools/round-gate.sh test/tooling/signing_policy_test.dart test/tooling/check_secrets_test.dart
```

A statikus policy-audit közvetlen futtatása (kimenet a §10-be):

```bash
python3 tool/release/verify_signing_policy.py --strict
```

## 8. Implementációs sorrend

1. `tool/release/verify_signing_policy.py` — a statikus mérce ELŐSZÖR (RED).
2. `test/tooling/signing_policy_test.dart` — az A1/A3/A4 cellák.
3. `android/app/build.gradle.kts` — debug-tanúsítvány elutasítás + Lab-ág megőrzése.
4. `docs/release/workflows/release-apk-fingerprint.proposal.md` — fingerprint a manifestbe, maszkolással.
5. `docs/security/signing-key-runbook.md`.
6. A valódi-sértés próba a §10-be.

## 9. Kockázatok

- **A Lab APK elvesztése.** A globális szigorítás a user napi diagnosztikai buildjét állítaná meg (A3).
- **Titok-szivárgás a logba.** A fingerprint-kiolvasás a legkockázatosabb új lépés (A4).
- **Hamis biztonság.** Egy statikus audit, ami csak a fájl LÉTÉT nézi, zöld lenne debug-aláírás mellett is (A1).

## 10. Implementation handoff — az implementer tölti ki

**Érintett fájlok (mind az engedélyezett listán):**

- `android/app/build.gradle.kts` — production ág (`releaseSigningRequired`
  mellett) elutasítja a debug keystore-t (fájlnév `debug.keystore` VAGY a
  `~/.android/debug.keystore` alapértelmezett út, mindkettő
  kis/nagybetű-érzéketlen) és a `androiddebugkey` aliast, `throw
  GradleException`-nel — a hibaüzenet az aliast/útvonalat nevezi meg,
  jelszót soha. Második, független védelem a `buildTypes.release` blokkban
  (defense-in-depth, ma elérhetetlen ág, mert a fenti már korábban dob).
  A `releaseSigningValues == null` ág (Lab/dev fallback a debug configra)
  változatlan — `STRUMSIGHT_REQUIRE_RELEASE_SIGNING` hiányában a
  `lab-apk.yml`/`build-apk.yml` parancssora érintetlen (A3, ADR 0448 D3).
- `tool/release/verify_signing_policy.py` (ÚJ) — stdlib-only statikus audit,
  `--gradle`/`--workflow`/`--strict` paraméterekkel. Hét szabály:
  `debug-keystore-rejected`, `debug-alias-rejected`,
  `lab-fallback-preserved` (Gradle) · `secrets-checked-before-build`,
  `keystore-not-echoed`, `keystore-cleanup-present` (workflow, OLVASÁS —
  regresszió-őr a MÁR fail-closed `release-apk.yml` fölött, R3).
- `test/tooling/signing_policy_test.dart` (ÚJ) — 23 teszt, A1/A3/A4/A5/A6/A7
  csoportok, `Process.runSync('python3', …)` alakban hívja az auditot valós
  fájlokon ÉS `Directory.systemTemp` fixture-ökön (kétirányú mérés, ADR 0448
  D6) — saját, korlátozott GH Actions YAML-parser (nincs `package:yaml`
  import, nincs `rg`/`grep`/`jq`/`gh` shell-kihívás, ADR 0447 D5 precedens).
- `docs/release/workflows/release-apk-fingerprint.proposal.md` (ÚJ) — a
  fingerprint-lépés javaslata: `keytool -storepass:env` (SOHA nyílt
  parancssori jelszó), a nyers `keytool` kimenet sehol nem íródik ki, a
  jelszó `::add-mask::`-olva a felhasználás ELŐTT, a sidecar
  (`dist/signing-certificate.json`) kizárólag `keyAlias` +
  `sha256Fingerprint` mezőt hordoz. A fingerprintet a MEGLÉVŐ
  `--artifact dist/signing-certificate.json` flaggel köti a release
  manifesthez (R2/D4 — nincs új manifest-mező, `schemaVersion` érintetlen).
  A beillesztés `.github/workflows/release-apk.yml`-be merge utáni
  orchesztrátor/emberi lépés (védett zóna, R3/§0.0.1.b).
- `docs/security/signing-key-runbook.md` (ÚJ) — backup (offline, a GitHub
  secret-en kívül), rotáció (jelszó-rotáció `keytool -storepasswd`/
  `-keypasswd`-vel a store-aláírás folytonosságának megőrzésével; a
  kulcs-fájl cseréje store-oldali App Signing-folyamat, nem CI-oldali),
  hozzáférés (ma a repó tulajdonosára korlátozva, csapat-bővüléskor
  environment-protection-rules a következő kör dolga), kulcs-elvesztés
  (offline backup megléte esetén nincs incidens; teljes elvesztés esetén
  store-szintű key-upgrade vagy új `applicationId`+új kulcs) — mindegyik
  szakasz felelőssel (`kcsabi176@gmail.com`, egyszemélyes projekt).

**Kötelező ellenőrzések kimenete (§7):**

```
$ python3 tool/release/verify_signing_policy.py --strict
signing policy: all rules satisfied
  gradle: android/app/build.gradle.kts
  workflow: .github/workflows/release-apk.yml
exit=0
```

```
$ tools/round-gate.sh test/tooling/signing_policy_test.dart test/tooling/check_secrets_test.dart
[1] format: ZÖLD · [2] analyze: ZÖLD ·
[3] test test/tooling/signing_policy_test.dart: ZÖLD (23/23) ·
[4] test test/tooling/check_secrets_test.dart: ZÖLD (13/13) ·
[5] architecture: ZÖLD · [6] secrets: ZÖLD · [7] l10n: ZÖLD
MINDEN GATE ZÖLD.
```

**Valódi-sértés próba (KÖTELEZŐ, R5/§7 alakja szerint, mindkettő
végrehajtva és visszaállítva):**

1. **A valós fájlból eltávolítva az elutasító ágat** (a `// ADR 0448 D2: …`
   kommenttől az `android {` blokkig terjedő szakasz kivágva
   `android/app/build.gradle.kts`-ből) →
   `flutter test test/tooling/signing_policy_test.dart` → az **A1** cella
   (`the real android/app/build.gradle.kts + release-apk.yml pass with exit
   0`) PIROSRA váltott:
   ```
   Expected: <0>
     Actual: <1>
   verify_signing_policy: debug-keystore-rejected: no case-insensitive
   comparison against "debug.keystore" found — the production signing
   branch does not reject the debug keystore filename
   ```
   (a `A4 — … the real workflow passes with exit 0` cella is vele bukott,
   mert ugyanazt a `--gradle` alapértelmezést használja — várt
   mellékhatás). A fájl ezután `cp` a mentett másolatból visszaállítva;
   `git diff --stat android/app/build.gradle.kts` üres, a
   `verify_signing_policy.py --strict` közvetlen újrafuttatása exit 0.
2. **A szintetikus fixture aliasát `androiddebugkey`-re állítva a
   production ágon**, elutasító ág NÉLKÜL (ez pontosan a suite-ban élő
   `a fixture that assigns the debug key alias to the production signing
   branch … fails with debug-alias-rejected` teszt fixture-alakja) —
   közvetlen `verify_signing_policy.py --strict --gradle <fixture>` futtatás:
   ```
   exit: 1
   VIOLATION debug-keystore-rejected: no case-insensitive comparison
   against "debug.keystore" found — the production signing branch does
   not reject the debug keystore filename
   VIOLATION debug-alias-rejected: no case-insensitive comparison against
   "androiddebugkey" found
   ```
   A fixture csak `/tmp`-ben létezett a próba idejére, nem került a fába
   (ADR 0448 D7).

**Ismert korlátok (a §10-be rögzítve, nem javító kör tárgya ebben a
körben):**

- A `debug-keystore-rejected` szabály a `~/.android/debug.keystore`
  alapértelmezett-út alternatívát csak GLOBÁLIS jelenlét-ellenőrzéssel
  (`.android/debug.keystore` substring) méri, nem ugyanazzal a
  gate-ablakos logikával, mint a fájlnév-ágat — ez elegendő a kör mért
  fixture-eihez, de egy jövőbeli finomítás tárgya lehet, ha a Gradle-oldal
  szerkezete változik.
- A fingerprint-javaslat `keytool` elérhetősége a runner image-en nem mért
  ezen a boxon (nincs Android SDK/JDK) — a futásidejű bizonyíték a CI-é
  (§0.0.1.a), ugyanúgy, ahogy az E12-R06 SBOM/manifest javaslatoknál.

**Jelzés:** `done`.

---

### 10.1 Javító kör (2026-08-28) — F1 + F2 (review: `docs/reviews/e12-r07-review.md`, CHANGES REQUESTED — 2 MAJOR)

A review mindkét leletet ugyanabban a szabályban mérte (`keystore-not-echoed`,
`tool/release/verify_signing_policy.py:207–209`): **F1** hamis pozitív (a kör
saját, ADR 0448 D5 által kötelezővé tett `::add-mask::` idiómáját
szivárgásnak minősítette), **F2** hamis negatív (a `${{ secrets.NAME }}` /
`${{ env.NAME }}` GitHub Actions interpolációs alakot átengedte).

**Javítás.** A `_ECHO_OF_SECRET` egyetlen regexét egy sor-alapú
`_line_echoes_secret` függvény váltotta:

- `_MASK_DIRECTIVE_OF_SECRET_ONLY` — szigorúan a `echo "::add-mask::$NAME"`
  TELJES sorra illeszkedik (horgonyzott eleje-vége), semmi szélesebbre; ha ez
  illeszkedik, a sor NEM sértés.
- `_SECRET_SHELL_VAR_REFERENCE` — a korábbi `$NAME`/`${NAME}` shell-hivatkozás,
  változatlan lefedettséggel.
- `_SECRET_ACTIONS_INTERPOLATION` (ÚJ) — `${{ secrets.NAME }}` / `${{
  env.NAME }}`, csak a jelszó-nevekre (`_SECRET_ENV_NAMES`); az
  `ANDROID_KEYSTORE_BASE64` nincs ebben a listában, ezért a valós workflow
  legitim `base64 --decode` pipe-ja (`release-apk.yml:106–107`) továbbra sem
  pirosít.

Két új gépi cella a `test/tooling/signing_policy_test.dart` A4 csoportjában
(a teljes suite ezután 27/27, a korábbi 23 változatlan marad):

1. „F1 (review) — the fingerprint proposal fragment … passes with exit 0" —
   a `release-apk-fingerprint.proposal.md` valódi YAML-fragmentjét (benne a
   `echo "::add-mask::$STRUMSIGHT_RELEASE_STORE_PASSWORD"` sorral) egy
   egyébként szabálykövető fixture workflow-ba illesztve az audit exit 0.
2. „F1 (review) — … prefix stripped … still fails with keystore-not-echoed" —
   ugyanez a fixture a maszkoló prefix nélkül (`echo
   "$STRUMSIGHT_RELEASE_STORE_PASSWORD"`) nem-nulla kilépést ad,
   `keystore-not-echoed`-dal — a kizárás nem szélesebb a kanonikus idiómánál.
3. „F2 (review) — a fixture workflow that echoes the canonical GitHub Actions
   secrets-interpolation form … fails with keystore-not-echoed" — a review
   `leak.yml` alakja (`echo "${{ secrets.ANDROID_STORE_PASSWORD }}"`)
   nem-nulla kilépést ad, `keystore-not-echoed`-dal.
4. „F2 (review) — the real release-apk.yml stays exit 0" — a valós
   `release-apk.yml` (benne az `${{ secrets.ANDROID_KEYSTORE_BASE64 }}` |
   `base64 --decode` pipe) továbbra is exit 0.

**Kötelező ellenőrzések kimenete:**

```
$ python3 tool/release/verify_signing_policy.py --strict
signing policy: all rules satisfied
  gradle: android/app/build.gradle.kts
  workflow: .github/workflows/release-apk.yml
exit=0
```

```
$ tools/round-gate.sh test/tooling/signing_policy_test.dart test/tooling/check_secrets_test.dart
[1] format: ZÖLD · [2] analyze: ZÖLD ·
[3] test test/tooling/signing_policy_test.dart: ZÖLD (27/27) ·
[4] test test/tooling/check_secrets_test.dart: ZÖLD (13/13) ·
[5] architecture: ZÖLD · [6] secrets: ZÖLD · [7] l10n: ZÖLD
MINDEN GATE ZÖLD.
```

**Valódi-sértés próba a javításra (mindkettő végrehajtva és visszaállítva,
kimenettel):**

1. Az `::add-mask::` kizárás kivéve (`_MASK_DIRECTIVE_OF_SECRET_ONLY.match`
   hívása ideiglenesen `False`-ra kényszerítve) →
   `flutter test --plain-name "F1 (review) — the fingerprint proposal fragment"`
   PIROSRA vált:
   ```
   Expected: <0>
     Actual: <1>
   verify_signing_policy: keystore-not-echoed: a signing password env var
   appears to be echoed/printed/catted
   ```
   Visszaállítva; `git diff` a fájlon üres.
2. Az interpolációs alak kezelése kivéve
   (`_SECRET_ACTIONS_INTERPOLATION.search` hívása ideiglenesen `False`-ra
   kényszerítve) →
   `flutter test --plain-name "F2 (review) — a fixture workflow that echoes the canonical"`
   PIROSRA vált:
   ```
   Expected: not <0>
     Actual: <0>
   ```
   Visszaállítva; `git diff` a fájlon üres.

**Jelzés:** `done`.

## 11. Review — a Claude tölti ki
