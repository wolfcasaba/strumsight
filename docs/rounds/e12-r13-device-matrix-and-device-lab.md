# E12-R13 — Device matrix és device lab nyilvántartás

- **Státusz:** PREPARED (előre megírva 2026-08-27, kód olvasva: `main @ 9ca4a0dc`)
- **Típus:** Chapter 12 (Release Roadmap, Sprint Planning & Final Integration), Kör 13
- **Kör-azonosító:** `E12-R13`
- **Branch:** `<motor>/e12-r13-device-matrix-and-device-lab`
- **Előfeltétel:** `E12-R01` merge-elve (a baseline sorolja fel a mai eszköz-bizonyítékokat)
- **Brief szerzője:** Claude (Opus 5)
- **Előre kiosztott ADR:** nincs — a kör nyilvántartást és riportot szállít, kötött architekturális döntés nélkül (a tier-szerződést az [ADR 0196](../adr/0196-vision-device-tier-performance-and-thermal-contract.md) MÁR rögzíti).

**Visszakeresett előzmény:** `node tools/knowledge-rag.mjs --corpus lessons,halts,adr --top 5 "device matrix tier capability manual device test report"` → **[ADR 0196](../adr/0196-vision-device-tier-performance-and-thermal-contract.md)** (Vision device-tier benchmark, degradation ladder, thermal adapter szerződés — a tier-fogalom MÁR definiált) és **[ADR 0187](../adr/0187-vision-automatic-guitar-geometry-detection.md)**. A mátrix ezekre a MÉRT tier-ekre épül, nem újakat vezet be.

> ⚠ **Pre-flight (indítás előtt KÖTELEZŐ):** olvasd újra a `docs/manual-testing/` MEGLÉVŐ eszköz-mátrixait (a megíráskor: `practice-engine-device-matrix.md`, `vision-device-matrix.md`, `gov-05-shipping-device-run.md`, `analysis-eval-matrix.md`) és a `lib/features/vision/domain` tier-enumját (`test/features/vision/domain/vision_device_tier_test.dart` pinneli). A kör EGYESÍTI ezeket, nem ír melléjük harmadikat.

## 0.0 Mi az, ami valóban új

A fán négy, egymástól független manuális eszköz-dokumentum él, mind más formában. Ami hiányzik: (a) egy géppel olvasható eszköz-nyilvántartás (`device-matrix.yaml`), (b) az a szabály, hogy MELYIK GA-capabilityhez KELL legalább egy release-blokkoló eszköz, (c) egy riport-generátor, ami a manuális futások eredményét beolvassa. A kör ezt a hármat adja.

```ai-router
schema_version = 1
risk = "normal"
allowed_paths = [
  "docs/testing/device-matrix.yaml",
  "docs/testing/device-lab.md",
  "tool/device_report.py",
  "test/tooling/device_matrix_test.dart",
  "docs/rounds/e12-r13-device-matrix-and-device-lab.md",
]
gate_tests = [
  "test/tooling/device_matrix_test.dart",
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

**STOP-protokoll:** ha a mátrix egy GA-capabilityhez EGYETLEN elérhető eszközt sem talál, az nem a szabály lazításának, hanem a `stopped` jelzésnek az esete — a döntés (scope-vágás vagy eszköz beszerzése) a useré.

## 1. Cél

Evidence-alapú eszköztámogatási döntés: melyik készülék-tier melyik capabilityt blokkolja, és melyik csak informál.

## 2. Jelenlegi állapot — mért tények

- `docs/manual-testing/` **négy** eszköz-dokumentumot tartalmaz, mind Markdown, mind kézi kitöltésű, gépi séma nélkül.
- A Vision tier-fogalom kódban ÉL (`vision_device_tier_test.dart`, ADR 0196), az Offline AI tier viszont MÉG NEM (az Epic 10 sáv `hold`-on áll — a mátrix ezért az Offline AI oszlopot „nem GA scope" jelöléssel viszi).
- `docs/testing/` a Kör 11/12 után létezik (`e2e-harness.md`, `release-fixture-corpus.md`).
- `tool/` MA egy Python fájlt tartalmaz a Kör 3 után (`audit_repository_policy.py`) — a `device_report.py` a második.
- A user valódi eszköze a MÉRT végső elfogadási kapu (a `HANDOFF.md` és az AGENTS.md szerint a valós gitáros APK-teszt) — a mátrixnak ezt az eszközt NÉVVEL kell tartalmaznia.

## 3. Scope

**Benne van:** `docs/testing/device-matrix.yaml` — eszközönként: OS-verzió, RAM, ABI, audio-képesség, kamera-képesség, AI-tier, `release_blocking: true|false`, és a kötelező tesztcsomag tier-enként · `docs/testing/device-lab.md` (hogyan fut egy manuális kör, mit kell rögzíteni) · `tool/device_report.py` (a manuális eredmények beolvasása és riport-generálás; hiányzó kötelező futás → nem-nulla kilépés) · `test/tooling/device_matrix_test.dart` (séma-validáció + a „minden GA-capabilityhez legalább egy blocking eszköz" invariáns).

**NINCS benne (tilos):**

- A `docs/manual-testing/` meglévő dokumentumainak törlése vagy átírása (hivatkozni szabad).
- Új tier-fogalom bevezetése a kódban.
- `docs/adr/**`.

## 4. Engedélyezett fájlok

| Útvonal | Indok |
|---|---|
| `docs/testing/device-matrix.yaml` | ÚJ — a géppel olvasható nyilvántartás |
| `docs/testing/device-lab.md` | ÚJ — a manuális kör leírása |
| `tool/device_report.py` | ÚJ — riport-generátor |
| `test/tooling/device_matrix_test.dart` | a §6 cellái |

**Tilos zóna:** `docs/manual-testing/**` · `lib/**` · `.github/**` · `docs/adr/**` · `tools/**`

## 5. Kötött architekturális döntések

Nincs ADR; két, a briefből következő KÖTELEZŐ szabály:

### 5.1 Minden GA-capabilityhez legalább egy `release_blocking` eszköz tartozik

**NEM elfogadható gyengítés:** a capability „informational" fokozatba sorolása azért, mert nincs rá eszköz — a hiány a `stopped` jelzés esete, a döntés a useré.

### 5.2 Az Offline AI hiánya NEM jelent core-inkompatibilitást

Egy eszköz, ami a helyi AI-t nem bírja, továbbra is TÁMOGATOTT a core tanulási útra. **NEM elfogadható gyengítés:** globális „nem támogatott" jelölés egyetlen opcionális capability miatt.

## 6. Acceptance criteria

| # | Kritérium | Bizonyíték |
|---|---|---|
| A1 | A `device-matrix.yaml` séma-valid (kötelező mezők minden eszközre) | `device_matrix_test.dart` |
| A2 | Minden GA-scope capabilityhez van legalább egy `release_blocking: true` eszköz | `device_matrix_test.dart` |
| A3 | Az Offline AI-t nem bíró eszköz a core capabilityre TÁMOGATOTT marad | `device_matrix_test.dart` |
| A4 | `tool/device_report.py` hiányzó kötelező futásra nem-nulla kóddal lép ki | a §7 parancs kimenete a §10-ben |
| A5 | A user valódi tesztkészüléke névvel szerepel a mátrixban, `release_blocking: true` értékkel | a YAML |
| A6 | A mátrix hivatkozza a `docs/manual-testing/` meglévő futásait, és egyiket sem írja felül | a dokumentum + `git diff --stat` |

### 6.1 Mérce-mátrix — melyik hibás implementációt melyik cella fogja pirosra

| Hibás implementáció | Melyik cella vált PIROSRA |
|---|---|
| Egy GA-capability csak `release_blocking: false` eszközökkel szerepel | A2 |
| Az Offline AI hiánya „unsupported" globális jelölést kap | A3 |
| A riport-generátor hiányzó futásra 0-val lép ki (csak figyelmeztet) | A4 |
| A YAML-ból hiányzik az ABI vagy a RAM mező egy eszközön | A1 |

**Valódi-sértés próba (KÖTELEZŐ, a §10-ben dokumentálva):** állítsd az egyik GA-capability összes eszközét `release_blocking: false`-ra, futtasd a §7 gate-et → az **A2** cellának PIROSNAK kell lennie → állítsd vissza.

## 7. Kötelező ellenőrzések

```bash
tools/round-gate.sh test/tooling/device_matrix_test.dart
```

A riport-generátor közvetlen futtatása (kimenet a §10-be):

```bash
python3 tool/device_report.py --matrix docs/testing/device-matrix.yaml --check
```

## 8. Implementációs sorrend

1. A négy meglévő manuális dokumentum MÉRÉSE (milyen eszköz, milyen futás szerepel bennük).
2. `docs/testing/device-matrix.yaml`.
3. `test/tooling/device_matrix_test.dart` (séma + invariánsok).
4. `tool/device_report.py`.
5. `docs/testing/device-lab.md` + a valódi-sértés próba a §10-be.

## 9. Kockázatok

- **A mátrix kitalálása.** Nem létező eszközök felsorolása látszat-lefedettséget ad; csak a MÉRT (a manuális dokumentumokban szereplő) eszközök kerülhetnek be.
- **A capability-oszlop elavulása.** Az Epic 10 `hold`-on áll: az Offline AI oszlop „nem GA scope" jelölése MA igaz, és a sáv indulásakor felül kell vizsgálni.
- **A user eszközének kihagyása.** A valós elfogadási kapu készüléke nélkül a mátrix a tényleges döntési pontot nem írja le (A5).

## 10. Implementation handoff — az implementer tölti ki

## 11. Review — a Claude tölti ki
