# E10-R10 — Aktiválás, rollback és tárhelykvóta

- **Státusz:** PREPARED (előre megírva 2026-08-22, kód olvasva: `main @ 194b48c4`)
- **Típus:** Chapter 11 (Epic 10 — Offline AI), Kör 10
- **Kör-azonosító:** `E10-R10`
- **Branch:** `<motor>/e10-r10-activation-rollback-and-storage-quota`
- **Előfeltétel:** `E10-R09` merge-elve
- **Brief szerzője:** Claude (Opus 5)
- **Előre kiosztott ADR:** `ADR 0425` — a szám FOGLALT (Epic 10 batch-tartomány, driftre számítva).

**Visszakeresett előzmény:** `node tools/knowledge-rag.mjs --corpus lessons,halts,adr --top 5 "atomic pointer swap rollback storage quota"` → nincs releváns előzmény (a találatok más domain hibaosztályai) — ez a kör a projekt ELSŐ ilyen jellegű infrastruktúrája, a §5/§9 saját tervezésére támaszkodik.

> ⚠ **Pre-flight (indítás előtt KÖTELEZŐ):** olvasd újra a Kör 9 `model_download_repository.dart`/`offline_package_importer.dart` TÉNYLEGES kimeneti típusait — az aktiválás ezekre épül. Eltérésnél §0.0 brief-revízió.

```ai-router
schema_version = 1
risk = "normal"
allowed_paths = [
  "lib/core/ai/model_registry.dart",
  "lib/features/offline_ai/data/local_model_registry.dart",
  "lib/features/offline_ai/application/model_activation_service.dart",
  "test/features/offline_ai/model_registry/",
  "docs/rounds/e10-r10-activation-rollback-and-storage-quota.md",
]
gate_tests = [
  "test/features/offline_ai/model_registry/",
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

A model registry kezelje az installed, active, previous-known-good és quarantined verziókat ATOMIKUSAN — félállapot semmilyen crash-forgatókönyvben sem maradhat.

## 2. Jelenlegi állapot — mért tények

- A Kör 2 `lib/core/ai/model_registry.dart` interfészt már definiálta — ez a kör az IMPLEMENTÁCIÓT adja (`local_model_registry.dart`).
- A Kör 8 verifiere és a Kör 9 letöltő/importer szállítja a staging csomagot — ez a kör az AKTIVÁLÁS lépését végzi a staging→installed átmenetre.
- A projekt `lib/core/storage/json_document_store.dart` már ad egy verziózott document-store mintát (E01-R07) — az `local_model_registry.dart` ezt a mintát követi az atomikus pointer-cseréhez, NEM saját fájlrendszeri tranzakciót épít a nulláról.

## 3. Scope

**Benne van:** verziózott `ModelRegistry` repository · aktiválás CSAK sikeres verifier + runtime smoke test után · atomikus active-pointer csere · previous-known-good megőrzés, ha a tárhelypolicy engedi · rollback + automatikus rollback ismételt load-crash után · staging+installed+rollback headroom tárhely-kalkuláció · unload kötelező törlés előtt, aktív használat alatt törlés tiltott · a knowledge package és a model package kvótája külön.

**NINCS benne (tilos):**

- A "runtime smoke test" VALÓDI natív végrehajtása — ez a kör egy INJEKTÁLHATÓ smoke-test callbacket vár (fake runtime a tesztekben, valós a Kör 13 natív rétegétől, amikor az elkészül).
- `docs/adr/**` — az ADR 0425-öt a Claude írja.

## 4. Engedélyezett fájlok

| Útvonal | Indok |
|---|---|
| `lib/core/ai/model_registry.dart` | a Kör 2 interfész BŐVÍTÉSE (nem újraírása) |
| `lib/features/offline_ai/data/local_model_registry.dart` | ÚJ — az implementáció |
| `lib/features/offline_ai/application/model_activation_service.dart` | ÚJ — az aktivációs orchestráció |
| `test/features/offline_ai/model_registry/` | a §6 cellái |

**Tilos zóna:** `lib/features/offline_ai/data/model_download_repository.dart` (Kör 9 fájlja, csak importálja) · `docs/adr/**` · `tools/**` · `.github/**` · `android/**`

## 5. Kötött architekturális döntések (ADR 0425)

### 5.1 Aktiválás atomikus — sikeres verifier ÉS smoke test EGYÜTT, vagy egyik sem

A staging→installed átmenet egyetlen atomikus műveletként történik (rename + pointer-frissítés); a köztes állapot (fájlok átmásolva, de a pointer még a régire mutat, VAGY fordítva) crash esetén sem érhető el kívülről.

**NEM elfogadható gyengítés:** egy "gyors" implementáció, ami előbb frissíti a pointert, majd másolja a fájlokat "mert úgyis gyors" — pontosan ez a race, amit az atomikus rename-minta kizár.

### 5.2 Legalább egy previous-known-good verzió megmarad, ha a tárhelypolicy engedi

Rollback nélkül egy hibás új verzió aktiválása után a felhasználó a régi, működő verzióhoz nem tudna visszatérni.

## 6. Acceptance criteria

| # | Kritérium | Bizonyíték |
|---|---|---|
| A1 | Aktiválás közbeni szimulált crash után VAGY a régi, VAGY az új verzió aktív — félállapot soha | `local_model_registry_test.dart` |
| A2 | Rollback a previous-known-good verzióra visszaállít | `local_model_registry_test.dart` |
| A3 | Ismételt (3×) load-crash után automatikus rollback indul | `model_activation_service_test.dart` |
| A4 | Aktív modell törlése tiltott — előbb unload kötelező | `model_activation_service_test.dart` |
| A5 | A tárhely-kalkuláció staging+installed+rollback headroomot számol, elégtelenség esetén az aktiválás ELŐTT hibát ad | `local_model_registry_test.dart` |
| A6 | A model package és a knowledge package kvótája függetlenül számolt | `local_model_registry_test.dart` |

### 6.1 Mérce-mátrix — melyik hibás implementációt melyik cella fogja pirosra

| Hibás implementáció | Melyik cella vált PIROSRA |
|---|---|
| A pointer-csere ELŐBB fut, mint a fájl-rename | A1 (a crash-szimuláció köztes állapotot talál) |
| A rollback nem tartja meg a previous-known-good-ot, csak törli a régit aktiválás után | A2 |
| A crash-számláló nem nullázódik sikeres load után, és 3 független, egymástól független első-crash összeadódik | A3 |
| A törlés unload nélkül is végrehajtható | A4 |

**Valódi-sértés próba (KÖTELEZŐ, §10-ben dokumentálva):** cseréld fel a pointer-frissítés és a fájl-rename sorrendjét, szimulálj crash-t köztük → az **A1** cellának PIROSNAK kell lennie → állítsd vissza.

## 7. Kötelező ellenőrzések

```bash
tools/round-gate.sh test/features/offline_ai/model_registry
```

## 8. Implementációs sorrend

1. `local_model_registry.dart` — installed/active/previous/quarantined állapotok.
2. Atomikus pointer-csere (a `json_document_store.dart` mintáját követve).
3. `model_activation_service.dart` — verifier+smoke-test orchestráció, injektálható smoke-test callback.
4. Rollback + automatikus rollback crash-számlálóval.
5. Tárhely-kalkuláció, kvóta-szétválasztás.
6. A valódi-sértés próba §10-be.

## 9. Kockázatok

- **A félállapot.** A legdrágább hibaosztály — egy sikertelen aktiválás után az app teljesen elveszítheti a működő modellt (A1).
- **A rollback hiánya.** Egy hibás új verzió a felhasználót modell nélkül hagyná, amíg nem tölt le egy másikat (A2).
- **A kvóta-összemosás.** Ha a model és knowledge package egy közös kvótát oszt meg, egy nagy modell letöltése blokkolhatná a knowledge frissítést.

## 10. Implementation handoff — az implementer tölti ki

## 11. Review — a Claude tölti ki
