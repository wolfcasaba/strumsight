# E12-R25 — Release Candidate assembly workflow

- **Státusz:** PREPARED (előre megírva 2026-08-27, kód olvasva: `main @ 9ca4a0dc`)
- **Típus:** Chapter 12 (Release Roadmap, Sprint Planning & Final Integration), Kör 25
- **Kör-azonosító:** `E12-R25`
- **Branch:** `<motor>/e12-r25-release-candidate-assembly`
- **Előfeltétel:** `E12-R06`, `E12-R07`, `E12-R16` és `E12-R18` merge-elve (manifest/SBOM, signing, AI-riport, security-scan — mind bemenet)
- **Brief szerzője:** Claude (Opus 5)
- **Előre kiosztott ADR:** `ADR 0463` — a szám FOGLALT (Chapter 12 batch-tartomány).

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
- `docs/adr/**` — az ADR 0463-at a Claude írja.

## 4. Engedélyezett fájlok

| Útvonal | Indok |
|---|---|
| `docs/release/workflows/release-candidate.proposal.yml` | ÚJ — az RC-workflow JAVASLATA (a telepítés emberi lépés) |
| `tool/release/assemble_rc.py` | ÚJ — az összeállító |
| `docs/release/rc-checklist.md` | ÚJ — az RC-ellenőrzőlista |
| `test/tooling/rc_assembly_test.dart` | a §6 lokális cellái |

**Tilos zóna:** `.github/workflows/**` (MIND, a §0.0 szerint) · `.github/actions/**` · `lib/**` · `backend/app/**` · `docs/adr/**` · `tools/**`

## 5. Kötött architekturális döntések (ADR 0463)

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
