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

## 0.0 Mi az, amit a kör NEM tud lokálisan bizonyítani

Ezen a boxon nincs Android SDK, és a release-build a CI-ban fut. A signing-viselkedés bizonyítéka ezért kettős: (a) Gradle-konfigurációs szintű, lokálisan futtatható egység-cella a `verify_signing_policy.py`-n keresztül, és (b) az orchesztrátor által dispatch-elt CI-futás a `release-apk.yml`-en. Az implementer `gh`-t nem hív.

```ai-router
schema_version = 1
risk = "high"
allowed_paths = [
  "android/app/build.gradle.kts",
  ".github/workflows/release-apk.yml",
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

**Benne van:** a Gradle release-ág kiegészítése a **debug keystore explicit elutasításával** (a jól ismert `~/.android/debug.keystore` és a `androiddebugkey` alias production ágon kivételt dob) · a dev/Lab és production signing config SZÉTVÁLASZTÁSA úgy, hogy a Lab build továbbra is dev kulccsal működik · `tool/release/verify_signing_policy.py` (a Gradle-fájl és a workflow statikus auditja: van-e olyan ág, ami production `buildType`-ra debug signing configot rendel; kerülhet-e kulcsanyag a logba) · a certificate fingerprint beírása a Kör 6 provenance manifestjébe (a workflow-lépés a fingerprintet a keystore-ból olvassa, és NEM logolja a jelszót) · `docs/security/signing-key-runbook.md` (backup, rotáció, hozzáférés, elvesztés esetén követendő lépések).

**NINCS benne (tilos):**

- **Bármilyen kulcsanyag, jelszó vagy keystore fájl commitolása** — beleértve a teszt-fixture-t is: a fixture kizárólag SZINTETIKUS, nem valódi kulcs.
- `build-apk.yml` / `full-gate.yml` / `lab-apk.yml` módosítása.
- Store-feltöltés vagy tényleges kulcsrotáció végrehajtása.
- `docs/adr/**` — az ADR 0448-at a Claude írja.

## 4. Engedélyezett fájlok

| Útvonal | Indok |
|---|---|
| `android/app/build.gradle.kts` | debug-tanúsítvány elutasítás + config szétválasztás |
| `.github/workflows/release-apk.yml` | fingerprint-kiolvasás a provenance manifesthez |
| `tool/release/verify_signing_policy.py` | ÚJ — statikus signing-policy audit |
| `docs/security/signing-key-runbook.md` | ÚJ — kulcs-runbook |
| `test/tooling/signing_policy_test.dart` | a §6 cellái |

**Tilos zóna:** `.github/workflows/{build-apk,full-gate,lab-apk}.yml` · `android/key.properties` (és bármely keystore) · `lib/**` · `backend/**` · `docs/adr/**` · `tools/**`

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
| A2 | Production signing secret hiányában a CI a build ELŐTT megáll | orchesztrátor által dispatch-elt futás linkje a §10-ben |
| A3 | A Lab build dev kulccsal továbbra is konfigurálható | `signing_policy_test.dart` |
| A4 | A workflow egyetlen lépése sem írja ki a keystore jelszót vagy a kulcsanyagot | `verify_signing_policy.py` + `check_secrets_test.dart` |
| A5 | A certificate fingerprint bekerül a provenance manifestbe | a manifest sémája + a dispatch-elt futás artefaktuma |
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
4. `.github/workflows/release-apk.yml` — fingerprint a manifestbe, maszkolással.
5. `docs/security/signing-key-runbook.md`.
6. A valódi-sértés próba a §10-be.

## 9. Kockázatok

- **A Lab APK elvesztése.** A globális szigorítás a user napi diagnosztikai buildjét állítaná meg (A3).
- **Titok-szivárgás a logba.** A fingerprint-kiolvasás a legkockázatosabb új lépés (A4).
- **Hamis biztonság.** Egy statikus audit, ami csak a fájl LÉTÉT nézi, zöld lenne debug-aláírás mellett is (A1).

## 10. Implementation handoff — az implementer tölti ki

## 11. Review — a Claude tölti ki
