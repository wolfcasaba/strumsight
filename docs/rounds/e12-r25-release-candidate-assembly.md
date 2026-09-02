# E12-R25 — Release Candidate assembly workflow

- **Státusz:** READY (pre-flight 2026-09-02, `main @ 9ff28f4c` — §0.0.B R1–R6)
- **Típus:** Chapter 12 (Release Roadmap, Sprint Planning & Final Integration), Kör 25
- **Kör-azonosító:** `E12-R25`
- **Branch:** `<motor>/e12-r25-release-candidate-assembly`
- **Előfeltétel:** `E12-R06`, `E12-R07`, `E12-R16` és `E12-R18` merge-elve (manifest/SBOM, signing, AI-riport, security-scan — mind bemenet)
- **Brief szerzője:** Claude (Opus 5)
- **Előre kiosztott ADR:** `ADR 0488` — a `tools/round-slots.py reserve-adr --round E12-R25` foglalótól MÉRVE (a brief eredeti `0463` értéke elavult, lásd §0.0.B R1).

**Visszakeresett előzmény:** `node tools/knowledge-rag.mjs --corpus lessons,halts,adr --top 5 "release candidate assembly workflow approval artifact checksum"` → **[ADR 0062](../adr/0062-ci-gate-chain-and-fail-closed-release-signing.md)** (teljes CI gate-sor és fail-closed release signing). Az RC-workflow ezt a gate-sort HÍVJA, nem duplikálja.

> ⚠ **Pre-flight (indítás előtt KÖTELEZŐ):** olvasd újra a `.github/actions/flutter-gates/action.yml` composite lépéseit és a `full-gate.yml` / `build-apk.yml` MÉRT szerkezetét — az RC-workflow ugyanazt a composite actiont használja, hogy a mérce ne csússzon szét (a `full-gate.yml` fejléce ezt a szabályt kimondja).

## 0.0 A workflow VÉDETT zóna — a kör a workflow-t JAVASLATKÉNT és az összeállítót KÓDKÉNT szállítja

A `.github/workflows/**` a `protect_factory_files.py` `PROTECTED_GLOBS` listáján van (ADR 0321), és az ADR 0372 álló felhatalmazásának fájlja (`.claude/gate-edit-policy`) a fán MA NEM létezik — a pre-flight ezt MÉRTE (`tools/gateguard-scan.py`). Egy implementer-session tehát `H-GATEGUARD`-dal állna meg az első workflow-íráson.

A kör ezért így oszlik:

1. **A kör szállítja** a teljes `release-candidate.yml` tartalmát JAVASLATKÉNT (`docs/release/workflows/release-candidate.proposal.yml`), az `assemble_rc.py` összeállítót, az RC-ellenőrzőlistát és a lokálisan futtatható mércét. A javaslat YAML-validitását, a composite-action hívást és a jóváhagyási kapu HELYÉT gépi cella méri.
2. **Orchesztrátor/emberi lépés a merge UTÁN:** a javaslat beillesztése `.github/workflows/release-candidate.yml` néven, majd KÉT dispatch — egy ZÖLD és egy BIZONYÍTOTT PIROS (hiányzó jóváhagyás vagy hiányzó AI-riport). A linkek a §11 review-jegyzetbe kerülnek.

```ai-router
schema_version = 1
risk = "high"
allowed_paths = [
  "docs/release/workflows/release-candidate.proposal.yml",
  "tool/release/assemble_rc.py",
  "docs/release/rc-checklist.md",
  "test/tooling/rc_assembly_test.dart",
  "docs/rounds/e12-r25-release-candidate-assembly.md",
]
gate_tests = [
  "test/tooling/rc_assembly_test.dart",
  "test/tooling/release_manifest_test.dart",
]
native_gate = false
```

**Kockázat = high, indoklás:** a kör a kiadási artefaktum előállításának útját építi (aláírás, provenance, feltöltés) — egy hibás ág aláíratlan vagy nem auditált csomagot engedne ki. A `security-reviewer` futtatása a review-ban KÖTELEZŐ.

## 0.0.B Pre-flight revíziók (Claude, 2026-09-02) — ütközésnél EZ a szöveg érvényes

A brief 2026-08-27-én készült, `main @ 9ca4a0dc` állapotra. A pre-flight a fán
ÚJRAMÉRT minden hivatkozott interfészt (`main @ 9ff28f4c`). Hat revízió:

### R1 — Az ADR száma **0488**, nem 0463

A `tools/round-slots.py reserve-adr --round E12-R25` foglaló **0488**-at adott
(a lemezen a legmagasabb ADR ma `0487`). A brief §0.0/§3/§5 „ADR 0463" említései
tehát az **`docs/adr/0488-release-candidate-assembly-and-approval-gate.md`** fájlt
jelentik. A queue `adr` oszlopa (`0463`) az előre kiosztott, elavult érték — ugyanez
a mintázat mérve az előző két körnél is: `E12-R22` queue `0461` → tényleges ADR `0486`;
`E12-R23` queue `0462` → tényleges ADR `0487`. A foglaló a mérce
(pipeline-prompt §1.0.1), az `ls docs/adr | tail` tilos. Az ADR-t az orchesztrátor
már megírta — **az implementer nem írja át, és `docs/adr/**`-hoz nem nyúl.**

### R2 — A `--dry-run` szemantikája, és miért NEM-NULLA a §7 lokális futása

Az [ADR 0488 D4](../adr/0488-release-candidate-assembly-and-approval-gate.md) köti:
a `--dry-run` feloldja és kiírja a bemeneti tervet (mely kötelező bemenet van meg,
mely hiányzik), csomagot NEM ír, és hiányzó kötelező bemenet esetén **nem-nulla**
kóddal lép ki. Egy tiszta munkafán — ahol egyetlen release-artefaktum sincs
megépítve — a §7-beli

```bash
python3 tool/release/assemble_rc.py --profile development --dry-run
```

ezért **várhatóan nem-nulla kóddal áll meg, a hiányzó bemenetek felsorolásával**.
Ez nem hiba: ez a D4 (és az A3 cella) élő bizonyítéka, és így — a tényleges
kimenettel és a kilépési kóddal együtt — kerül a §10-be. A `--profile` értékkészlete
a testvér `generate_sbom.py`-val EGYEZZEN: `production` | `development`.

### R3 — A gépi cellák két KÖTELEZŐ tulajdonsága (L566, L563)

1. **Fail-closed parszer.** A javaslat YAML-jét ebben a tesztfájlban élő,
   korlátozott részhalmaz-parszer olvassa (`package:yaml` importálása TILOS: csak
   tranzitív függőség, az import a `depend_on_referenced_packages` linttel pirosra
   váltaná az analyze-t). Minden nem illeszkedő sor → `FormatException` a sor
   számával; néma eldobás TILOS. Ezen felül a cella **kösse a parszolt elemek
   számát a nyers előfordulások számához** (job-fejlécek és `- name:` lépések nyers
   `RegExp`-találatai), és a „nem tartalmazza a rosszat" alakú állításokat cserélje
   **pontos egyezésre**. Mért ok: [`docs/LESSONS.md` L566](../LESSONS.md) — a
   sor-parszerre épülő őr alapértelmezésben fail-OPEN, a tiltott állapot vákuumban
   „teljesíti" az elvárást. Precedens-parszer, amit bővíts (job-szint kell hozzá):
   `test/tooling/signing_policy_test.dart` (`parseSteps`) és
   `test/tooling/release_manifest_test.dart` (`parseWorkflowSteps`).
2. **Minden cella a saját javítása ELŐTTI eszközzel PIROS.** Mért ok:
   [`docs/LESSONS.md` L563](../LESSONS.md) — a „belefér a régi ablakba" degenerált
   fixture nem mérce. A §6.1 mátrix minden sorára gondolj úgy: *ha a hibás
   implementációt beírom, PONTOSAN ez a cella vált pirosra?*

### R4 — A hivatkozott eszközök MÉRT interfészei (ne találj ki flageket)

| Eszköz | Mért CLI |
|---|---|
| `tool/release/generate_sbom.py` | `--profile {production,development}` · `--pubspec-lock` · `--pub-cache` · `--output-sbom` (alap `build/sbom.json`) · `--output-notices` (alap `THIRD_PARTY_NOTICES.md`) |
| `tool/release/verify_artifacts.py` | `--manifest` (kötelező) · `--previous` · `--base-dir` |
| `tool/release/build_ai_report.py` | `--profile` (kötelező) · `--scope-file` (kötelező) |
| `tool/release/security_scan.py` | `--root` · `--threat-model` · `--exceptions` · `--requirements` · `--today` · `--only {guards,exceptions,dependencies,secrets}` · `--format {text,json}` |
| `tool/generate_release_manifest.dart` | `dart run tool/generate_release_manifest.dart` |

A közös mérce-lánc composite action **mért** lépéssora
(`.github/actions/flutter-gates/action.yml`): `flutter pub get` → `dart format
--output=none --set-exit-if-changed lib test tool` → `flutter analyze lib/ test/ tool/`
→ `dart run tool/check_architecture.dart` → `dart run tool/ci/check_secrets.dart` →
`dart run tool/ci/check_l10n_parity.dart` → `dart run tool/ci/check_assets.dart` →
`flutter test` → `flutter test test/property`. **Egyetlen lépését sem másolod be** — a
javaslat `uses: ./.github/actions/flutter-gates` alakban hívja (A5).

A production signing út **mért** env-szerződése (`.github/workflows/release-apk.yml`):
`STRUMSIGHT_RELEASE_STORE_FILE`, `STRUMSIGHT_RELEASE_STORE_PASSWORD`,
`STRUMSIGHT_RELEASE_KEY_ALIAS`, `STRUMSIGHT_RELEASE_KEY_PASSWORD`,
`STRUMSIGHT_REQUIRE_RELEASE_SIGNING: 'true'`, a négy `ANDROID_*` secret előzetes
jelenlét-ellenőrzésével. A backend teszt-sáv **mért** alakja
(`.github/workflows/backend-ci.yml`): `python -m ruff check app tests` → `ruff format
--check` → `python -m pytest -q` → `python -m alembic upgrade head`, `working-directory:
backend`, Python 3.12.

**AAB:** a fán MA egyetlen workflow sem épít app bundle-t. Az ADR 0488 nyitott pontja
szerint az APK a **kötelező** artefaktum; az AAB opcionális, azonos env-szerződésű
lépésként írható le, de acceptance-cella NEM méri.

### R5 — A `.github/workflows/**` védettsége MA is fennáll

Mérve: `.claude/gate-edit-policy` **nem létezik** a fán, a `PROTECTED_GLOBS` (ADR 0321)
pedig tartalmazza a `.github/workflows/**`-ot. A §0.0 felosztása tehát érvényes: a kör
kimenete a **javaslat-fájl**, és a `.github/` alá a kör egyetlen bájtot sem ír. A
javaslat kiterjesztése `.yml` (nem `.md`, mint a két korábbi javaslatnál), mert ez
**teljes új workflow-dokumentum**, nem meglévőbe illesztendő fragment.

### R6 — A csomag alakja és a checksum-manifest terjedelme

Az `assemble_rc.py` kimenete egy csomag-könyvtár (alapértelmezés: `build/rc/`), benne a
kötelező bemenetek másolatával és egy determinisztikus, útvonal szerint **rendezett,
időbélyeg-mentes** checksum-manifesttel (sha256), amely a csomag MINDEN fájlára kiterjed
— nem csak az APK-ra (ADR 0488 D5). Az `--verify` út a manifestet a csomag TÉNYLEGES
fájllistájához köti: hiányzó, megváltozott ÉS többlet fájl egyaránt nem-nulla kilépés.
A kimeneti könyvtár félkészen nem maradhat hátra, ha egy kötelező bemenet hiányzik (D4).

## 0. Kör-jelzés és STOP-protokoll

```bash
tools/codex-signal.sh progress "<egy sor>"
tools/codex-signal.sh done "<egy sor>"
tools/codex-signal.sh stopped "<egy sor>"
tools/codex-signal.sh blocked "<egy sor>"
```

**STOP-protokoll:** ha a munkához a `build-apk.yml` vagy a `full-gate.yml` (a MERGE-kapu) módosítása kellene, a kimenet a `stopped` jelzés — az RC-workflow ÚJ fájl, és a meglévő kaput nem írja át.

## 1. Cél

Egyetlen, manuálisan jóváhagyható workflow, amely tiszta checkoutból, minden release-kaput lefuttatva állít elő auditálható RC-csomagot.

## 2. Jelenlegi állapot — mért tények

- `.github/workflows/`: `build-apk.yml` (merge-kapu + APK), `full-gate.yml` (mérce APK nélkül), `release-apk.yml` (production APK fail-closed signinggal), `backend-ci.yml`, `lab-apk.yml`, + 5 ML/eval workflow.
- `.github/actions/flutter-gates/action.yml` — a KÖZÖS mérce-lánc composite action.
- `tool/release/` a Kör 6/7/16/18 után: `generate_sbom.py`, `verify_artifacts.py`, `verify_signing_policy.py`, `build_ai_report.py`, `security_scan.py`.
- `release-candidate.yml` és `assemble_rc.py` **nem létezik**; `docs/release/rc-checklist.md` sem.
- A repó egyetlen `environment:`-alapú manuális jóváhagyást SEM használ ma — az RC-workflow lesz az első.

## 3. Scope

**Benne van:** `docs/release/workflows/release-candidate.proposal.yml` — a JAVASOLT RC-workflow teljes tartalma: `workflow_dispatch` + `environment:` alapú MANUÁLIS jóváhagyás; tiszta checkout; a `flutter-gates` composite futtatása; backend teszt-sáv; a Kör 16 AI-riport és a Kör 18 security-scan hívása; AAB/APK build a production signing úton; a Kör 6 manifest + SBOM + notices csomagolása; checksum-audit · `tool/release/assemble_rc.py` (az artefaktumok összegyűjtése, checksum-manifest, hiányzó bemenet → nem-nulla kilépés) · `docs/release/rc-checklist.md` · `test/tooling/rc_assembly_test.dart` (az `assemble_rc.py` cellái lokálisan, fixture-artefaktumokkal).

**NINCS benne (tilos):**

- **Bármely `.github/workflows/**` fájl írása** (a §0.0 szerint: védett mérce-zóna).
- Store-feltöltés vagy publikálás.
- A gate-lépések DUPLIKÁLÁSA a composite action helyett.
- `docs/adr/**` — az ADR 0488-at a Claude írja (§0.0.B R1).

## 4. Engedélyezett fájlok

| Útvonal | Indok |
|---|---|
| `docs/release/workflows/release-candidate.proposal.yml` | ÚJ — az RC-workflow JAVASLATA (a telepítés emberi lépés) |
| `tool/release/assemble_rc.py` | ÚJ — az összeállító |
| `docs/release/rc-checklist.md` | ÚJ — az RC-ellenőrzőlista |
| `test/tooling/rc_assembly_test.dart` | a §6 lokális cellái |

**Tilos zóna:** `.github/workflows/**` (MIND, a §0.0 szerint) · `.github/actions/**` · `lib/**` · `backend/app/**` · `docs/adr/**` · `tools/**`

## 5. Kötött architekturális döntések (ADR 0488)

### 5.1 Az RC a KÖZÖS composite gate-et hívja

**NEM elfogadható gyengítés:** a lépések bemásolása az RC-workflow-ba — a két mérce garantáltan szétcsúszik (a `full-gate.yml` fejléce ugyanezt az elvet rögzíti).

### 5.2 Jóváhagyás nélkül nincs artefaktum-feltöltés

A manuális `environment` gate a build ELŐTT áll. **NEM elfogadható gyengítés:** „építsük meg, és csak a publikálás legyen jóváhagyás-köteles".

### 5.3 Hiányzó bemenet = megállás

Ha az AI-riport, a security-scan vagy a manifest hiányzik, az `assemble_rc.py` nem-nulla kóddal lép ki. **NEM elfogadható gyengítés:** részleges csomag „legalább valami" alapon.

## 6. Acceptance criteria

| # | Kritérium | Bizonyíték |
|---|---|---|
| A1 | A javaslatban a jóváhagyási kapu (`environment:`) a build/upload lépések ELŐTT áll | `rc_assembly_test.dart` (YAML-parse + lépés-sorrend cella) |
| A2 | Az `assemble_rc.py` a teljes csomagot állítja össze (artefaktum, manifest, SBOM, notices, AI-riport, security-riport, teszt-riport), fixture-bemeneten | `rc_assembly_test.dart` |
| A3 | Hiányzó bemenet esetén az `assemble_rc.py` nem-nulla kóddal lép ki | `rc_assembly_test.dart` |
| A4 | A csomag checksum-manifestje minden fájlra kiterjed, és eltérésre PIROS | `rc_assembly_test.dart` |
| A5 | Az RC a `flutter-gates` composite actiont hívja (nem másolt lépéseket) | a workflow forrása + `rc_assembly_test.dart` statikus cellája |
| A6 | A javaslatban minden upload-lépés a gate-lépések SIKERÉTŐL függ (`needs:` / `if: success()`), tehát piros gate mellett nem futhat | `rc_assembly_test.dart` függőség-cella |

### 6.1 Mérce-mátrix — melyik hibás implementációt melyik cella fogja pirosra

| Hibás implementáció | Melyik cella vált PIROSRA |
|---|---|
| A jóváhagyási kapu a build UTÁN áll | A1 |
| A workflow bemásolja a gate-lépéseket a composite helyett | A5 |
| Hiányzó AI-riport mellett az összeállító figyelmeztet és folytat | A3 |
| A checksum-manifest csak az APK-ra terjed ki | A4 |

**Valódi-sértés próba (KÖTELEZŐ, a §10-ben dokumentálva):** vedd ki az `assemble_rc.py`-ból a kötelező-bemenet ellenőrzést, futtasd a §7 gate-et → az **A3** cellának PIROSNAK kell lennie → állítsd vissza.

## 7. Kötelező ellenőrzések

```bash
tools/round-gate.sh test/tooling/rc_assembly_test.dart test/tooling/release_manifest_test.dart
```

Az összeállító lokális, fixture-alapú futtatása (kimenet a §10-be):

```bash
python3 tool/release/assemble_rc.py --profile development --dry-run
```

A javaslat telepítése és a KÉT dispatch (zöld + bizonyított piros) orchesztrátor/emberi lépés a merge UTÁN — az implementer sem `.github/`-ot nem ír, sem `gh`-t nem hív.

## 8. Implementációs sorrend

1. `tool/release/assemble_rc.py` (a kötelező bemenetek ellenőrzésével).
2. `test/tooling/rc_assembly_test.dart`.
3. `docs/release/workflows/release-candidate.proposal.yml` — a composite action hívásával és a manuális kapuval.
4. `docs/release/rc-checklist.md`.
5. A valódi-sértés próba a §10-be; a telepítés és a két dispatch-link az orchesztrátoré (merge után).

## 9. Kockázatok

- **A mérce szétcsúszása.** Másolt gate-lépések (A5).
- **Jóváhagyás megkerülése.** Egy `workflow_dispatch` input „skip_approval" néven pontosan ezt tenné (A1).
- **Védett zóna érintése.** Bármely `.github/workflows/**` írása `H-GATEGUARD` halt (§0.0) — a javaslat-fájl az egyetlen megengedett kimenet.

## 10. Implementation handoff — az implementer tölti ki

## 11. Review — a Claude tölti ki
