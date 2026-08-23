# E10-R15 — Tokenizer, chat template és generation profile

- **Státusz:** PREPARED (előre megírva 2026-08-22, kód olvasva: `main @ 194b48c4`)
- **Típus:** Chapter 11 (Epic 10 — Offline AI), Kör 15
- **Kör-azonosító:** `E10-R15`
- **Branch:** `<motor>/e10-r15-tokenizer-and-generation-profiles`
- **Előfeltétel:** `E10-R14` merge-elve
- **Brief szerzője:** Claude (Opus 5)
- **Előre kiosztott ADR:** nincs — a generation profile-ok konfigurációs adatok, nem új architekturális kényszer.

**Visszakeresett előzmény:** `node tools/knowledge-rag.mjs --corpus lessons,halts,adr --top 5 "tokenizer chat template parity fixture sampling profile"` → nincs releváns előzmény (a találatok más domain hibaosztályai) — ez a kör a projekt ELSŐ ilyen jellegű infrastruktúrája, a §5/§9 saját tervezésére támaszkodik.

> ⚠ **Pre-flight (indítás előtt KÖTELEZŐ):** olvasd újra a Kör 8 `model_package_manifest.dart` tokenizer-hash mezőjét — a parity-teszt erre validál. Eltérésnél §0.0 brief-revízió.

## 0.0 Hardver/scope-korlát — miért PENDING

A SDD §24 (Codex végrehajtási szabály #6) explicit előírja: "Használj tiny fixture modellt vagy fake runtime-ot CI-ben" — ez a kör pontosan ezt teszi. A tokenizer-fixture-ök egy KICSI, git-be commitolható tesztfájl (nem egy valódi, több GB-os modell tokenizere) — a parity-teszt a fixture ELVÁRT tokenizálását ellenőrzi, nem valódi modell-inference-t.

```ai-router
schema_version = 1
risk = "normal"
allowed_paths = [
  "lib/features/offline_ai/domain/generation_profile.dart",
  "lib/features/offline_ai/data/model_chat_template.dart",
  "local_ai/evaluation/tokenizer_fixtures/",
  "test/features/offline_ai/domain/generation_profile_test.dart",
  "test/features/offline_ai/data/model_chat_template_test.dart",
  "docs/rounds/e10-r15-tokenizer-and-generation-profiles.md",
]
gate_tests = [
  "test/features/offline_ai/domain/generation_profile_test.dart",
  "test/features/offline_ai/data/model_chat_template_test.dart",
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

## 1. Cél

A modellcsomaghoz tartozó tokenizer és chat-template legyen parity-tesztelt (FIXTURE-en), a sampling pedig termékprofilhoz kötött, felhasználó által nem felülírható productionben.

## 2. Jelenlegi állapot — mért tények

- `lib/features/offline_ai/data/` a Kör 9 óta létezik (`model_download_repository.dart` stb.) — ez a kör bővíti.
- A Kör 8 `ModelPackageManifest` tokenizer-hash mezőt hordoz — ez a kör ezt HASZNÁLJA a verzió-handshake-hez.
- A projektnek MA nincs semmilyen tokenizer-kódja — ez teljesen ÚJ.

## 3. Scope

**Benne van:** package tokenizer és chat-template betöltése (absztrakt loader interfész, a Kör 13 natív rétege tölti majd ki valós adattal) · FIXTURE tokenization referencia (magyar ékezetek, angol szöveg, tool JSON, special tokenek) · `groundedBrief`, `tutorExplain`, `clarification`, `structuredTool` generation profile-ok · profilonként max output/temperature/top-p/top-k/repetition/stop-sequence · felhasználó NEM állíthat korlátlan contextet/outputot productionben · capability-negotiation nem támogatott sampling paraméterre · prompt template version handshake a package és app között.

**NINCS benne (tilos):**

- Valódi, teljes méretű modell tokenizerének letöltése vagy futtatása.
- `docs/adr/**`, `tools/**`, `.github/**`, `android/**`.

## 4. Engedélyezett fájlok

| Útvonal | Indok |
|---|---|
| `lib/features/offline_ai/domain/generation_profile.dart` | ÚJ — a négy profil + sampling paraméterek |
| `lib/features/offline_ai/data/model_chat_template.dart` | ÚJ — tokenizer/template betöltés + parity |
| `local_ai/evaluation/tokenizer_fixtures/` | ÚJ — FIXTURE tokenization referenciák |
| `test/features/offline_ai/domain/generation_profile_test.dart` | a §6 cellái |
| `test/features/offline_ai/data/model_chat_template_test.dart` | a §6 cellái |

**Tilos zóna:** `android/**` · `lib/core/ai/**` (csak importálja a Kör 2 interfészeit) · `docs/adr/**` · `tools/**` · `.github/**`

## 5. Kötött architekturális döntések

### 5.1 Nincs ÚJ kötött döntés — a tokenizer a csomag forrása-of-truth, ez a SDD §11.1 alkalmazása

**NEM elfogadható gyengítés:** karakterhossz-alapú token-becslés bárhol, ahol PONTOS token count szükséges (pl. context-budget) — csak a package tokenizerének tényleges kimenete számít token countnak.

## 6. Acceptance criteria

| # | Kritérium | Bizonyíték |
|---|---|---|
| A1 | A magyar ékezetes FIXTURE tokenizálása megegyezik a referenciával | `model_chat_template_test.dart` |
| A2 | A tool JSON tokenizálása megőrzi a struktúra-jelző special tokeneket | `model_chat_template_test.dart` |
| A3 | Ismeretlen/nem támogatott sampling paraméter kontrollált capability-negotiation hibát ad, nem crash-t | `generation_profile_test.dart` |
| A4 | A felhasználó nem tud productionben korlátlan max-outputot beállítani egyik profilon sem | `generation_profile_test.dart` |
| A5 | Template-verzió mismatch a package és az app között explicit hibát ad | `model_chat_template_test.dart` |
| A6 | Mind a négy generation profile (groundedBrief, tutorExplain, clarification, structuredTool) rendelkezik explicit stop-sequence-szel | `generation_profile_test.dart` |

### 6.1 Mérce-mátrix — melyik hibás implementációt melyik cella fogja pirosra

| Hibás implementáció | Melyik cella vált PIROSRA |
|---|---|
| A tokenizer karakterhossz-alapú becslést használ ékezetes szövegen | A1 |
| A profil validáció nem korlátozza a max output felhasználói módosítását | A4 |
| A template-verzió mismatch csendben a régi template-tel próbálkozik | A5 |
| Egy profil stop-sequence nélkül marad | A6 |

**Valódi-sértés próba (KÖTELEZŐ, §10-ben dokumentálva):** engedd a felhasználói max-output paramétert korlátlanul productionben, futtasd a tesztet → az **A4** cellának PIROSNAK kell lennie → állítsd vissza.

## 7. Kötelező ellenőrzések

```bash
tools/round-gate.sh test/features/offline_ai/domain/generation_profile_test.dart test/features/offline_ai/data/model_chat_template_test.dart
```

## 8. Implementációs sorrend

1. FIXTURE tokenization referenciák (hu ékezet, en, tool JSON, special tokenek).
2. `model_chat_template.dart` — betöltés + parity-ellenőrzés + verzió-handshake.
3. `generation_profile.dart` — a négy profil, sampling korlátokkal.
4. A capability-negotiation hibaút.
5. A valódi-sértés próba §10-be.

## 9. Kockázatok

- **A karakterhossz-alapú token-becslés csendes bevezetése.** Egy "gyorsítás" kísértés lenne, de a §11.1 SDD-szabályt sértené (A1).
- **A korlátlan felhasználói output.** Kontextus-túlcsordulást vagy OOM-ot okozhatna productionben (A4).
- **A template-verzió csendes toleranciája.** Egy inkompatibilis template alkalmazása rossz minőségű vagy hibás generálást eredményezne felismerhetetlenül (A5).

## 10. Implementation handoff — az implementer tölti ki

## 11. Review — a Claude tölti ki
