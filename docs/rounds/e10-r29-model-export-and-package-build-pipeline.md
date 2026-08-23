# E10-R29 — Reprodukálható export, kvantálás és package build pipeline

- **Státusz:** PREPARED (előre megírva 2026-08-22, kód olvasva: `main @ 194b48c4`) — **`hold`: valódi modell-súlyokat, GPU/compute erőforrást és licenc-döntést igényel**
- **Típus:** Chapter 11 (Epic 10 — Offline AI), Kör 29
- **Kör-azonosító:** `E10-R29`
- **Branch:** `<motor>/e10-r29-model-export-and-package-build-pipeline`
- **Előfeltétel:** `E10-R07` (runtime ADR) VALÓS döntéssel lezárva
- **Brief szerzője:** Claude (Opus 5)
- **Előre kiosztott ADR:** nincs — a pipeline maga a Kör 7/22 ADR-jeit implementálja, nem köt új döntést.

**Visszakeresett előzmény:** `node tools/knowledge-rag.mjs --corpus lessons,halts,adr --top 5 "reproducible export pinned revision signing separation"` → nincs releváns előzmény (a találatok más domain hibaosztályai) — ez a kör a projekt ELSŐ ilyen jellegű infrastruktúrája, a §5/§9 saját tervezésére támaszkodik.

## 0.0 MIÉRT `hold`

Ez a kör VALÓDI, letöltött modell-súlyokat (a Kör 7 ADR-jében kiválasztott modellcsalád tényleges checkpointjait), GPU/compute erőforrást (kvantáláshoz, export-hoz) és egy VÉGLEGES emberi licenc-jóváhagyást igényel (kereskedelmi felhasználásra megfelelő licenc, redisztribúciós jog — SDD §16.2). Egyik sem áll rendelkezésre a batch-prep pillanatában, és egyik sem szimulálható hitelesen: egy LLM-implementer nem tud licenc-jogi döntést hozni, és nem tud valós modell-súlyt "kitalálni" anélkül, hogy megsértené a "no demos — real functionality" elvet.

**Mi oldja fel:** a Kör 7 ADR-je (végleges runtime-választás), a Kör 6 bake-off-ban ténylegesen mért modelljelölt, ÉS egy ember által jóváhagyott licenc-döntés.

```ai-router
schema_version = 1
risk = "high"
allowed_paths = [
  "local_ai/export/",
  "local_ai/requirements-lock.txt",
  "local_ai/configs/quantization_profiles.yaml",
  "docs/rounds/e10-r29-model-export-and-package-build-pipeline.md",
]
gate_tests = [
  "test/app/config/feature_flags_test.dart",
]
native_gate = false
```

**Kockázat = high, indoklás:** a `local_ai/export/**` valós modell-súlyokkal, licenc-attribúcióval és signing-előkészítéssel dolgozik — a `licence`/`credential`-rokon kockázati kategóriával egyezik (a private signing key nem kerülhet ide, lásd 5.3).

## 0. Kör-jelzés és STOP-protokoll

```bash
tools/codex-signal.sh progress "<egy sor>"
tools/codex-signal.sh done "<egy sor>"
tools/codex-signal.sh stopped "<egy sor>"
tools/codex-signal.sh blocked "<egy sor>"
```

**Ha ezt a kört mégis dispatch-elnék valós modell/licenc-döntés nélkül:** az implementer ELSŐ lépése annak ellenőrzése, hogy létezik-e egy emberi jóváhagyású licenc-döntési dokumentum. Ha nincs, AZONNAL `tools/codex-signal.sh blocked "nincs jóváhagyott modell-licenc döntés — emberi közreműködés szükséges"`.

## 1. Cél

A kiválasztott modell mobilartifactja egyetlen dokumentált, pinned és ellenőrizhető pipeline-ból készüljön — a signing lépés külön, védett release job.

## 2. Jelenlegi állapot — mért tények

- A Kör 5 `candidate_models.yaml` PLACEHOLDER-e és a Kör 6/7 VALÓS bake-off/ADR adja a modellcsalád-döntést.
- A Kör 8 manifest-sémája és verifiere a kimeneti formátum-elvárás.

## 3. Scope

**Benne van:** locked Python környezet (opcionális container) · pinned-revision + checksum forrás-download · runtime-specifikus export + kvantálási profilok · tokenizer/chat-template/generation-defaults/tool-schema/license/model-card generálás · reference/quantized parity evaluation (a Kör 26 aggregációs logikájával) · unsigned package + manifest generálás · verifier CLI (a Kör 8 sémalogikáját újrahasználva) · signing KÜLÖN, védett release job · nagy artifact NEM kerül normál Gitbe.

**NINCS benne (tilos):**

- A private signing key generálása vagy repóba/kliensbe kerülése — ez SOSEM megengedett, semelyik körben.

## 4. Engedélyezett fájlok

| Útvonal | Indok |
|---|---|
| `local_ai/export/` | ÚJ — export/kvantálás/build szkriptek |
| `local_ai/requirements-lock.txt` | ÚJ — pinned Python dependency |
| `local_ai/configs/quantization_profiles.yaml` | ÚJ — kvantálási profilok |

**Tilos zóna:** a signing kulcs generálása/tárolása bármilyen formában · `.github/workflows/**` (a CI-pipeline egy KÜLÖN, human-gated governance-kör dolga)

## 5. Kötött architekturális döntések

### 5.1 A build NEM közvetlenül publikál — a signing külön, védett lépés

**NEM elfogadható gyengítés:** egy "egyszerűsített" pipeline, ami a build végén azonnal aláír, "mert úgyis ugyanaz a gép" — a signing environment-nek KÜLÖN, védett hozzáférésűnek kell lennie.

### 5.2 Minden build pontosan visszavezethető egy pinned bemenetre

## 6. Acceptance criteria

| # | Kritérium | Bizonyíték |
|---|---|---|
| A1 | Ugyanaz a pinned bemenet mindig bájtra ugyanazt a manifestet adja (a nem-determinisztikus időbélyeg-mezők kivételével) | `local_ai/tests/test_export_reproducibility.py` |
| A2 | A tokenizer-hash a package részeként rögzített | ugyanott |
| A3 | Reference/quantized parity report elkészül minden buildhez | ugyanott |
| A4 | A verifier CLI ugyanazt a logikát futtatja, mint a kliens (Kör 8) | ugyanott |
| A5 | Nincs signing key a build-artifactok között | ugyanott — kulcsszó-scan |
| A6 | Nagy bináris NEM kerül a normál git-historyba | review — `git log --stat` audit |

### 6.1 Mérce-mátrix — melyik hibás implementációt melyik cella fogja pirosra

| Hibás implementáció | Melyik cella vált PIROSRA |
|---|---|
| A build ugyanabban a lépésben aláír, mint amiben exportál | A5 (a kulcsszó-scan megtalálja a kulcsot a build-jobban) |
| A pinned revision nincs rögzítve a manifestben | A1 |
| A verifier CLI eltérő logikát futtat, mint a kliens | A4 |

## 7. Kötelező ellenőrzések

```bash
cd local_ai && python3 -m pytest tests/test_export_reproducibility.py -q
```

A `gate_tests` regresszió-őre (Kör 1 óta stabil feature-flag teszt) a `tools/round-gate.sh`-on át bizonyítja, hogy a Python export-eszköz nem érintett véletlenül Flutter-oldali kódot:

```bash
tools/round-gate.sh test/app/config/feature_flags_test.dart
```

## 8. Implementációs sorrend

1. Emberi licenc-döntés ellenőrzése — hiányában `blocked`.
2. Locked Python env + pinned source download.
3. Export + kvantálás a Kör 7 runtime-jához.
4. Manifest/model-card/license generálás.
5. Parity evaluation.
6. Verifier CLI (Kör 8 logikájának Python-oldali tükre).
7. A signing lépés KÜLÖN dokumentálva, NEM implementálva ebben a körben (védett release job, emberi jóváhagyással).

## 9. Kockázatok

- **A signing key szivárgása.** A legsúlyosabb lehetséges biztonsági incidens ebben a projektben — ezért a signing SOSEM lehet automatikus lépés egy fejlesztői körben.
- **A licenc-jogi kockázat.** Egy rosszul választott licenc kereskedelmi/jogi problémát okozna.
- **A nem-reprodukálható build.** Ha a pipeline nem determinisztikus, a supply-chain-integritás (Kör 8) egésze aláásott lenne (A1).

## 10. Implementation handoff — az implementer tölti ki (emberi licenc-döntés után)

## 11. Review — a Claude tölti ki
