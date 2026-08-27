# E12-R06 — Versioning, provenance, SBOM és release manifest

- **Státusz:** PREPARED (előre megírva 2026-08-27, kód olvasva: `main @ 9ca4a0dc`)
- **Típus:** Chapter 12 (Release Roadmap, Sprint Planning & Final Integration), Kör 6
- **Kör-azonosító:** `E12-R06`
- **Branch:** `<motor>/e12-r06-versioning-provenance-and-sbom`
- **Előfeltétel:** `E12-R01` merge-elve (a release-history audit adja a verziószám-stratégia kiindulópontját)
- **Brief szerzője:** Claude (Opus 5)
- **Előre kiosztott ADR:** `ADR 0447` — a szám FOGLALT (Chapter 12 batch-tartomány). A SDD `docs/adr/versioning.md` fájlnevet ír; a repó konvenciója a SORSZÁMOZOTT ADR, ezért a döntés az `ADR 0447` fájlba kerül, és azt a Claude írja.

**Visszakeresett előzmény:** `node tools/knowledge-rag.mjs --corpus lessons,halts,adr --top 5 "versioning build number provenance SBOM release manifest third party license"` → **[ADR 0063](../adr/0063-generated-ml-manifest-and-backend-ci.md)** (generált ML asset manifest — a repó MÁR ismeri a „generált manifest + checksum + CI-ellenőrzés" mintát) és **[ADR 0135](../adr/0135-tutor-knowledge-governance.md)** (tudás-csomag governance). A release-manifest ezekre épül, nem mellettük.

> ⚠ **Pre-flight (indítás előtt KÖTELEZŐ):** olvasd újra a `.github/workflows/release-apk.yml` „Read APK metadata from pubspec" lépését (a megíráskor: regex kényszeríti a `<version>+<build>` alakot, az artefaktum-név `strumsight-<ver>-<build>-<sha7>-production.apk`) és a `tool/` MÉRT ML-manifest eszközeit. A kör BŐVÍTI ezeket.

## 0.0 A workflow-fájl a MÉRCE VÉDETT zónája — a kör JAVASLATOT ír, nem workflow-t

A `.github/workflows/**` a `protect_factory_files.py` `PROTECTED_GLOBS` listáján van (ADR 0321), és az ADR 0372 álló felhatalmazásának FÁJLJA (`.claude/gate-edit-policy`) a fán MA NEM létezik — a pre-flight ezt MÉRTE (`tools/gateguard-scan.py`). Egy implementer-session tehát strukturálisan nem tudná megírni: a kör `H-GATEGUARD`-dal állna meg.

Ezért a kör a workflow-változást **javaslatként** szállítja (`docs/release/workflows/…`), teljes, bemásolható YAML-részlettel és a beillesztés pontos helyével. A tényleges `.github/workflows/` szerkesztés és a dispatch **orchesztrátor/emberi lépés**, a kör merge-e UTÁN — ugyanaz a határ, amit az ADR 0112 §3 az egyetlen emberi kapuként tart fenn. A kör saját mércéje ettől nem gyengül: a javaslat YAML-validitását és a hivatkozott lépések meglétét gépi cella méri.

```ai-router
schema_version = 1
risk = "normal"
allowed_paths = [
  "lib/app/build_info.dart",
  "tool/generate_release_manifest.dart",
  "tool/release/generate_sbom.py",
  "tool/release/verify_artifacts.py",
  "docs/release/workflows/release-apk-provenance.proposal.md",
  "THIRD_PARTY_NOTICES.md",
  "docs/release/supply-chain.md",
  "test/tooling/release_manifest_test.dart",
  "docs/rounds/e12-r06-versioning-provenance-and-sbom.md",
]
gate_tests = [
  "test/tooling/release_manifest_test.dart",
  "test/tooling/ml_asset_manifest_test.dart",
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

**STOP-protokoll:** ha a munkához a `build-apk.yml` vagy a `full-gate.yml` (a MERGE-kapu) módosítása kellene, a kimenet a `stopped` jelzés és brief-revízió kérése — a gate-workflow változtatása ADR 0052/0053 hatálya alatti külön kör ([L478](../LESSONS.md#l478)).

## 1. Cél

Minden kiadott artefaktum (app, backend, modell, tudáscsomag) legyen commitig visszakövethető, verzió-monoton és supply-chain szempontból leírt.

## 2. Jelenlegi állapot — mért tények

- `pubspec.yaml`: `version: 1.0.0+1` — a build number MÉG SOHA nem emelkedett.
- `.github/workflows/release-apk.yml` (174 sor) MA: fail-closed signing-secret ellenőrzés, `pubspec` verzió-regex, `strumsight-<ver>-<build>-<sha7>-production.apk` artefaktum-név, keystore materializálás + törlés. **Manifest, SBOM és license-bundle NINCS.**
- `lib/app/build_info.dart` **nem létezik** — a verzió/SHA ma nem jelenik meg a felületen.
- `tool/build_tutor_knowledge_manifest.dart` és a `test/tooling/ml_asset_manifest_test.dart` MÁR mutatják a „generált manifest + checksum" mintát (ADR 0063) — a release-manifest ezt követi.
- `THIRD_PARTY_NOTICES.md` és `docs/release/supply-chain.md` **nem létezik**; `tool/release/` **nem létezik**.
- A `pubspec.lock` verziókövetett — a Flutter/Dart dependency-inventory determinisztikusan előállítható belőle.

## 3. Scope

**Benne van:** `lib/app/build_info.dart` (compile-time `String.fromEnvironment` alapú build-metaadat: verzió, build number, rövid SHA, channel — a `main`/bootstrap NEM módosul, a megjelenítés későbbi kör dolga) · `tool/generate_release_manifest.dart` (determinisztikus JSON: app verzió, build, SHA, channel, ML-modell-manifest hivatkozás, tudáscsomag-verzió, artefaktum-checksumok) · `tool/release/generate_sbom.py` (Flutter/Dart a `pubspec.lock`-ból, backend a `requirements*.txt`-ből; license-mező hiánya → nem-nulla kilépés) · `tool/release/verify_artifacts.py` (checksum-audit egy artefaktum-könyvtáron) · `THIRD_PARTY_NOTICES.md` (generált) · `docs/release/supply-chain.md` · `docs/release/workflows/release-apk-provenance.proposal.md` — a `release-apk.yml`-hez JAVASOLT lépések (manifest + SBOM + notices artefaktum-feltöltés) teljes YAML-részletként, a beillesztés helyének megnevezésével.

**NINCS benne (tilos):**

- **Bármely `.github/workflows/**` fájl módosítása** (a §0.0 szerint: védett mérce-zóna; a kör javaslatot ír).
- A verzió/SHA UI-megjelenítése (`lib/features/settings/**`) — külön kör.
- `pubspec.yaml` verzió-emelés.
- `docs/adr/**` — az ADR 0447-et a Claude írja.

## 4. Engedélyezett fájlok

| Útvonal | Indok |
|---|---|
| `lib/app/build_info.dart` | ÚJ — compile-time build-metaadat |
| `tool/generate_release_manifest.dart` | ÚJ — a release manifest generátor |
| `tool/release/generate_sbom.py` | ÚJ — SBOM + license report |
| `tool/release/verify_artifacts.py` | ÚJ — checksum-audit |
| `docs/release/workflows/release-apk-provenance.proposal.md` | ÚJ — a workflow-lépések JAVASLATA (a beillesztés emberi lépés) |
| `THIRD_PARTY_NOTICES.md` | ÚJ — generált notice-bundle |
| `docs/release/supply-chain.md` | ÚJ — a supply-chain leírás |
| `test/tooling/release_manifest_test.dart` | a §6 cellái |

**Tilos zóna:** `.github/workflows/**` (MIND, a §0.0 szerint) · `.github/actions/**` · `pubspec.yaml` · `lib/features/**` · `lib/app/bootstrap/**` · `docs/adr/**` · `tools/**`

## 5. Kötött architekturális döntések (ADR 0447)

### 5.1 A manifest determinisztikus: azonos bemenet → bájtazonos kimenet

Rendezett kulcsok, nincs időbélyeg a manifest TESTÉBEN (a build-idő külön, explicit mező, amit a determinizmus-teszt kizár). **NEM elfogadható gyengítés:** „a generálás ideje" beírása a fő objektumba, majd a teszt lazítása a mező kihagyásával.

### 5.2 A build number monoton, és a csökkenés HIBA

A `verify_artifacts.py` a korábbi publikált manifesthez méri. **NEM elfogadható gyengítés:** figyelmeztetés kilépési kód nélkül.

### 5.3 Hiányzó license vagy checksum BLOKKOL

A generátor nem-nulla kóddal lép ki. **NEM elfogadható gyengítés:** „unknown" license-érték beírása és továbbmenetel.

## 6. Acceptance criteria

| # | Kritérium | Bizonyíték |
|---|---|---|
| A1 | A manifest kétszeri generálása bájtazonos | `release_manifest_test.dart` |
| A2 | Hiányzó license-mezőjű függőség esetén az SBOM-generátor nem-nulla kóddal lép ki | `release_manifest_test.dart` (fixture-alapú) |
| A3 | Csökkenő build number esetén a `verify_artifacts.py` nem-nulla kóddal lép ki | `release_manifest_test.dart` |
| A4 | A manifest hivatkozza az ML-modell-manifestet és a tudáscsomag-verziót, checksummal | `release_manifest_test.dart` |
| A5 | A javaslat-fájl YAML-részlete önmagában valid, megnevezi a beillesztés helyét, és a manifest/SBOM/notices artefaktumot mind a hárommal feltölti | `release_manifest_test.dart` (YAML-parse + kötelező lépés-cellák) |
| A6 | A meglévő `ml_asset_manifest_test.dart` VÁLTOZATLANUL zöld | a §7 gate |

**Küszöb-cellahármas a build numberre** (a határ az EGYENLŐSÉG, ami TILOS — a korábbival azonos build number újrafelhasználás): a küszöb **alatt** (új build < publikált) → PIROS; **pontosan rajta** (új build == publikált) → PIROS; a küszöb **fölött** (új build > publikált) → ZÖLD.

### 6.1 Mérce-mátrix — melyik hibás implementációt melyik cella fogja pirosra

| Hibás implementáció | Melyik cella vált PIROSRA |
|---|---|
| A manifest generálási időbélyeget tesz a fő objektumba | A1 |
| A license-hiány „unknown" értékkel csúszik át | A2 |
| Az egyenlő build number elfogadott | a küszöb-cellahármas „pontosan rajta" cellája |
| A modell-manifest hivatkozás kimarad a release manifestből | A4 |

**Valódi-sértés próba (KÖTELEZŐ, a §10-ben dokumentálva):** vedd ki a manifest-generátorból a kulcs-rendezést, futtasd a §7 gate-et → az **A1** cellának PIROSNAK kell lennie → állítsd vissza.

## 7. Kötelező ellenőrzések

```bash
tools/round-gate.sh test/tooling/release_manifest_test.dart test/tooling/ml_asset_manifest_test.dart
```

Az eszközök közvetlen futtatása (kimenet a §10-be):

```bash
dart run tool/generate_release_manifest.dart --output build/release-manifest.json
python3 tool/release/generate_sbom.py --profile production
```

A javaslat tényleges beillesztése és a dispatch orchesztrátor/emberi lépés a kör merge-e UTÁN — az implementer sem `.github/`-ot nem ír, sem `gh`-t nem hív.

## 8. Implementációs sorrend

1. `lib/app/build_info.dart`.
2. `tool/generate_release_manifest.dart` (determinisztikus JSON).
3. `tool/release/generate_sbom.py` + `THIRD_PARTY_NOTICES.md` generálás.
4. `tool/release/verify_artifacts.py` (checksum + monotonitás).
5. `test/tooling/release_manifest_test.dart` — benne a küszöb-cellahármas.
6. `docs/release/workflows/release-apk-provenance.proposal.md`.
7. `docs/release/supply-chain.md` + a valódi-sértés próba a §10-be.

## 9. Kockázatok

- **A védett zóna érintése.** Bármely `.github/workflows/**` írása `H-GATEGUARD` halttal állítja meg a kört (§0.0) — a javaslat-fájl az egyetlen megengedett kimenet.
- **Nem-determinisztikus manifest.** Időbélyeg vagy rendezetlen map → a checksum minden buildben más (A1).
- **A license-adat hiánya.** A `pubspec.lock` nem tartalmaz license-mezőt minden csomagra; a generátornak ezt HIBÁNAK kell jeleznie, nem kitalálnia (A2).

## 10. Implementation handoff — az implementer tölti ki

## 11. Review — a Claude tölti ki
