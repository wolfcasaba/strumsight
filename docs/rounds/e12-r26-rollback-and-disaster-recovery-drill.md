# E12-R26 — Rollback és disaster recovery rehearsal

- **Státusz:** PREPARED (előre megírva 2026-08-27, kód olvasva: `main @ 9ca4a0dc`)
- **Típus:** Chapter 12 (Release Roadmap, Sprint Planning & Final Integration), Kör 26
- **Kör-azonosító:** `E12-R26`
- **Branch:** `<motor>/e12-r26-rollback-and-disaster-recovery-drill`
- **Előfeltétel:** `E12-R08` és `E12-R25` merge-elve (staging recovery alap; RC-artefaktum, amire visszaállni lehet)
- **Brief szerzője:** Claude (Opus 5)
- **Előre kiosztott ADR:** nincs — a kör GYAKORLATOT és ellenőrző eszközt szállít; a szerződéseket az ADR 0449 (staging/recovery) és ADR 0446 (kill switch) rögzíti.

**Visszakeresett előzmény:** `node tools/knowledge-rag.mjs --corpus lessons,halts,adr --top 5 "rollback disaster recovery drill restore recovery time"` → nincs release-domain előzmény (a találatok — ADR 0352, [L68](../LESSONS.md#l68) — más terület recovery-fogalmai); a kör a Kör 8 saját runbookjaira épül, és ez a projekt ELSŐ rollback-gyakorlata.

> ⚠ **Pre-flight (indítás előtt KÖTELEZŐ):** olvasd újra a Kör 8-ban készült `docs/operations/backend-deploy.md` és `database-recovery.md` lépéseit, valamint a Kör 5 kill-switch útjait (`docs/release/kill-switches.md`). A gyakorlat EZEKET futtatja végig — ha egy lépés a valóságban nem elvégezhető, az LELET.

## 0.0 Mi gyakorolható itt, és mi nem

Felhő-infrastruktúra nincs a boxon, tehát a gyakorlat LOKÁLIS: konténer-image visszaállítás, adatbázis-restore ideiglenes célra, feature-flag kikapcsolás hatásának mérése, modell-verzió visszaállítás. A tényleges production rollback (élő forgalom mellett) a Kör 31–33 operátori lépése. A kör értéke a MÉRT recovery-idő és a runbook-hibák felfedezése.

```ai-router
schema_version = 1
risk = "high"
allowed_paths = [
  "tool/release/verify_rollback.py",
  "docs/operations/disaster-recovery-drill.md",
  "backend/tests/test_rollback_drill.py",
  "test/tooling/rollback_policy_test.dart",
  "docs/rounds/e12-r26-rollback-and-disaster-recovery-drill.md",
]
gate_tests = [
  "test/tooling/rollback_policy_test.dart",
  "test/core/feature_flags/feature_flag_registry_test.dart",
]
native_gate = false
```

**Kockázat = high, indoklás:** a gyakorlat adatbázis-visszaállítást futtat; egy hibás script fejlesztői adatot semmisíthet meg, és a Kör 8 §5.2 `--force` szabályát is próbára teszi. A `security-reviewer` futtatása a review-ban KÖTELEZŐ.

## 0. Kör-jelzés és STOP-protokoll

```bash
tools/codex-signal.sh progress "<egy sor>"
tools/codex-signal.sh done "<egy sor>"
tools/codex-signal.sh stopped "<egy sor>"
tools/codex-signal.sh blocked "<egy sor>"
```

**STOP-protokoll:** ha egy runbook-lépés MÉRHETŐEN nem elvégezhető, a kimenet a `stopped` jelzés és jelentés — a runbook „elméleti" javítása (a lépés átírása anélkül, hogy lefutott volna) TILOS.

## 1. Cél

Bizonyítani, hogy a kritikus visszaállítási lépések nem csak dokumentáltak, hanem MÉRT idővel és adat-ellenőrzéssel végrehajthatók.

## 2. Jelenlegi állapot — mért tények

- `docs/operations/`: a Kör 8 után `backend-deploy.md`, `database-recovery.md`, valamint a Community moderation runbook.
- `backend/scripts/{backup,restore}.py` a Kör 8 terméke; `tool/release/verify_rollback.py` **nem létezik**.
- A kill-switch utak a Kör 5 `docs/release/kill-switches.md`-ben; a flag-katalógus tesztje `test/core/feature_flags/feature_flag_registry_test.dart`.
- A modell-asset visszaállítás mai támpontja az `assets/ml/model_manifest.json` + `test/tooling/ml_asset_manifest_test.dart`.
- Gyakorlat (drill) dokumentum **nem létezik** — ez az első.

## 3. Scope

**Benne van:** `tool/release/verify_rollback.py` — a visszaállítás UTÁNI állapot ellenőrzése (migrációs fej, rekordszámok, flag-profil, modell-verzió), MÉRT idővel · `backend/tests/test_rollback_drill.py` (restore → ellenőrzés → előző kliens-API kompatibilitás füst-cellája) · `test/tooling/rollback_policy_test.dart` (kill-switch kikapcsolás NEM töröl adatot; a flag-cache lejárata után a kikapcsolás érvényre jut) · `docs/operations/disaster-recovery-drill.md` (a LEFUTTATOTT gyakorlat jegyzőkönyve: lépés, mért idő, eredmény, felfedezett runbook-hiba).

**NINCS benne (tilos):**

- Éles/felhő rollback végrehajtása.
- A Kör 8 scriptjeinek átírása (mérni szabad; hibát jelenteni kell).
- `lib/**` módosítás.
- `docs/adr/**`.

## 4. Engedélyezett fájlok

| Útvonal | Indok |
|---|---|
| `tool/release/verify_rollback.py` | ÚJ — a visszaállítás-ellenőrző |
| `docs/operations/disaster-recovery-drill.md` | ÚJ — a gyakorlat jegyzőkönyve |
| `backend/tests/test_rollback_drill.py` | a backend-oldali §6 cellák |
| `test/tooling/rollback_policy_test.dart` | a kliens-oldali §6 cellák |

**Tilos zóna:** `backend/scripts/**` · `backend/app/**` · `lib/**` · `.github/**` · `docs/operations/{backend-deploy,database-recovery}.md` · `docs/adr/**`

## 5. Kötött architekturális döntések

Nincs ADR. Két kötelező szabály:

### 5.1 A gyakorlat jegyzőkönyve MÉRT időt tartalmaz

Minden lépéshez tényleges, mért időtartam tartozik. **NEM elfogadható gyengítés:** becsült („kb. 5 perc") érték.

### 5.2 A kill switch NEM töröl adatot — ez a gyakorlat egyik mércéje

**NEM elfogadható gyengítés:** a takarítás „a tiszta állapot érdekében" (a Kör 5 §5.2 szabálya).

## 6. Acceptance criteria

| # | Kritérium | Bizonyíték |
|---|---|---|
| A1 | Backup → restore → `verify_rollback.py` után a migrációs fej és a rekordszámok egyeznek | `test_rollback_drill.py` |
| A2 | Az előző kliens-verzió API-hívásai a visszaállított sémán működnek (füst-cella) | `test_rollback_drill.py` |
| A3 | A kill switch kikapcsolás után az adat MEGMARAD | `rollback_policy_test.dart` |
| A4 | A flag-cache lejárata után a távoli kikapcsolás érvényre jut | `rollback_policy_test.dart` |
| A5 | A jegyzőkönyv minden lépéshez MÉRT időt és eredményt rögzít | `docs/operations/disaster-recovery-drill.md` |
| A6 | A gyakorlat során talált runbook-hibák LELETKÉNT szerepelnek (nem csendben javítva) | a jegyzőkönyv + `git diff --stat` |

**Küszöb-cellahármas a flag-cache lejáratra** (a MÉRT cache-élettartam `T`; a határ INKLUZÍV, azaz pontosan `T` elteltével a friss érték érvényes): a küszöb **alatt** (`T-1` perc) → a régi érték él; **pontosan rajta** (`T`) → az új (kikapcsolt) érték él; a küszöb **fölött** (`T+1`) → az új érték él.

### 6.1 Mérce-mátrix — melyik hibás implementációt melyik cella fogja pirosra

| Hibás implementáció | Melyik cella vált PIROSRA |
|---|---|
| A restore után csak a kapcsolat ellenőrzött, a migrációs fej nem | A1 |
| A kill switch takarít (adatot töröl) | A3 |
| A flag-cache soha nem jár le, a kikapcsolás nem hat | A4 (küszöb-cellahármas) |
| A jegyzőkönyv becsült időket tartalmaz | A5 |

**Valódi-sértés próba (KÖTELEZŐ, a §10-ben dokumentálva):** állítsd a `verify_rollback.py` migrációs fej ellenőrzését figyelmeztetésre, futtasd a §7 gate-et → az **A1** cellának PIROSNAK kell lennie → állítsd vissza.

## 7. Kötelező ellenőrzések

```bash
tools/round-gate.sh test/tooling/rollback_policy_test.dart test/core/feature_flags/feature_flag_registry_test.dart
```

Backend sáv (külön processzként):

```bash
cd backend && python -m pytest tests/test_rollback_drill.py -q
```

## 8. Implementációs sorrend

1. `tool/release/verify_rollback.py`.
2. `backend/tests/test_rollback_drill.py` (restore + kompatibilitás).
3. `test/tooling/rollback_policy_test.dart` (kill switch + cache-küszöb).
4. A gyakorlat LEFUTTATÁSA és a jegyzőkönyv írása MÉRT időkkel.
5. A valódi-sértés próba a §10-be.

## 9. Kockázatok

- **Adatvesztés a gyakorlat közben.** A restore ideiglenes célra menjen; a Kör 8 `--force` szabálya itt élesben próbálódik.
- **Papír-gyakorlat.** Mért idő nélkül a jegyzőkönyv nem bizonyíték (A5).
- **Csendes runbook-javítás.** A talált hiba elrejtése értékesebb információt semmisít meg, mint amennyit a javítás ér (A6).

## 10. Implementation handoff — az implementer tölti ki

## 11. Review — a Claude tölti ki
