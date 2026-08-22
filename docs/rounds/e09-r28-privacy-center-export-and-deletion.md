# E09-R28 — Privacy center, adat export és törlés

- **Státusz:** PREPARED (előre megírva 2026-08-22, kód olvasva: `main @ db6293f4`)
- **Típus:** Chapter 10 (Epic 9 — Community Platform), Kör 28
- **Kör-azonosító:** `E09-R28`
- **Branch:** `<motor>/e09-r28-privacy-center-export-and-deletion`
- **Előfeltétel:** `E09-R27` merge-elve
- **Brief szerzője:** Claude (Opus 5)
- **Előre kiosztott ADR:** `ADR 0416` — a szám FOGLALT (Epic 9 batch-tartomány 0395-0419). Az ADR-t a Claude írja meg a kör indítási pre-flightjában a §5 döntéseiből; az implementer a `docs/adr/`-t NEM érinti (TILOS zóna).

> ⚠ **Pre-flight (indítás előtt KÖTELEZŐ):** olvasd újra a Kör 4 privacy-settings TÉNYLEGES mezőit és a `settings_sync.dart` account-deaktiválási/törlési mintáját (ha van ilyen a fő Settings feature-ben) — a Community adat-jogok UI ugyanazt a konzisztencia-elvárást követi. Eltérésnél
> §0.0 brief-revízió, NEM csendes lista-tágítás.

```ai-router
schema_version = 1
risk = "high"
allowed_paths = [
  "backend/app/community/services/data_rights_service.py",
  "backend/app/community/routers/data_rights.py",
  "lib/features/community/presentation/screens/community_privacy_screen.dart",
  "lib/features/community/presentation/screens/community_data_screen.dart",
  "backend/tests/community/test_data_rights_service.py",
  "test/features/community/presentation/community_data_screen_test.dart",
  "docs/rounds/e09-r28-privacy-center-export-and-deletion.md",
]
gate_tests = [
  "test/features/community/presentation/community_data_screen_test.dart"
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

Lezáró jelzés nélkül a kör bukott. **Listán kívüli fájl kellene → `stopped`**,
és a kimenet a brief-revízió kérése, nem az `allowed_paths` csendes tágítása.
Meglévő, ma zöld teszt elbukása → `blocked`, nem a teszt átírása.

## 1. Cél

A felhasználó közösségi adatainak áttekintése, exportja, deaktiválása és törlése — a Community-törlés NEM törli automatikusan a lokális tanulási történetet.

## 2. Jelenlegi állapot — mért tények

- A Kör 1-27 MOST már a teljes Community adatfelszínt lefedi (profil, poszt, komment, reakció, bookmark, follow, klub, challenge, moderation) — ez a kör az ELSŐ, ami mindezt egy export-jobban egyesíti

## 3. Scope

**Benne van:** Community Privacy & Safety képernyő (visibility, discoverability, leaderboard, notifications, block, mute beállítások) · export job: profil, poszt, komment, reaction, bookmark, follow, klub, challenge, moderation-user-facing adat · az export artifact titkosított vagy rövid életű signed download, auditált hozzáféréssel · Community deactivate flow + KÜLÖN teljes profile delete megerősítéssel · media-deletion + cache-invalidation job indítása törléskor · dokumentáció: mely audit/security rekord marad meg retention miatt · account-törlés és Community-törlés KÜLÖN, egyértelmű művelet.

**NINCS benne (tilos):**

- A teljes account (auth) törlésének módosítása — csak a Community-specifikus törlési útvonal.
- `docs/adr/**` — az ADR 0416-ot a Claude írja.

## 4. Engedélyezett fájlok

| Útvonal | Indok |
|---|---|
| `backend/app/community/services/data_rights_service.py` | ÚJ |
| `backend/app/community/routers/data_rights.py` | ÚJ |
| `lib/features/community/presentation/screens/community_privacy_screen.dart` | ÚJ |
| `lib/features/community/presentation/screens/community_data_screen.dart` | ÚJ |
| `backend/tests/community/test_data_rights_service.py` | ÚJ — a §6 cellái |
| `test/features/community/presentation/community_data_screen_test.dart` | ÚJ |

**Tilos zóna:** `backend/app/routers/auth.py` és a teljes-account-törlés útvonala (csak dokumentált KAPCSOLÓDÁS, nem módosítás) · `docs/adr/**` · `tools/**` · `.github/**`

## 5. Kötött architekturális döntések (ADR 0416)

### 5.1 Community-törlés NEM törli automatikusan a lokális tanulási történetet

A Community profile törlése a közösségi adatokra (poszt, follow, klub-tagság stb.) korlátozódik — a Practice/Song/Analysis lokális előzmény külön, csak a TELJES account-törlés keretében szűnik meg.

**NEM elfogadható gyengítés:** egy "kényelmi" egyesített törlés-gomb, ami a Community törlésével együtt a teljes lokális tanulási adatot is törli — ez a §6/23.4 SDD-invariáns közvetlen megsértése.

### 5.2 Az export más accounttal NEM érhető el, és rövid életű/védett

Az export-job kizárólag a KÉRŐ felhasználó saját JWT-jével indítható és tölthető le; a letöltési link rövid TTL-lel vagy titkosítással védett.

### 5.3 Account-törlés és Community-törlés KÜLÖN, egyértelmű művelet

A felhasználó két külön, világosan megkülönböztetett megerősítő flow-t lát — nincs egyetlen gomb, ami mindkettőt elvégzi.

## 6. Acceptance criteria

| # | Kritérium | Bizonyíték |
|---|---|---|
| A1 | A user saját Community adatait exportálhatja | `test_data_rights_service.py` |
| A2 | Export más accounttal NEM érhető el | `test_data_rights_service.py` — cross-account denial |
| A3 | Lejárt export-URL elutasított | `test_data_rights_service.py` |
| A4 | Deactivate után a profil nem látható másoknak | `test_data_rights_service.py` |
| A5 | Delete idempotens (kétszeri hívás nem hibázik) | `test_data_rights_service.py` |
| A6 | Media-cleanup job elindul törléskor | `test_data_rights_service.py` |
| A7 | A lokális tanulási adat MEGMARAD Community-törlés után | `test_data_rights_service.py` — regresszió |

### 6.1 Mérce-mátrix — melyik hibás implementációt melyik cella fogja pirosra

| Hibás implementáció | Melyik cella vált PIROSRA |
|---|---|
| Egy másik user JWT-jével letölthető az export | A2 |
| A lejárt export-link továbbra is működik | A3 |
| A Community-törlés törli a lokális Practice-history rekordokat is | A7 |
| A második delete-hívás hibát dob ahelyett, hogy no-op lenne | A5 |
| A media-cleanup job nem indul el törléskor | A6 |

**Valódi-sértés próba (KÖTELEZŐ, §10-ben dokumentálva):** kapcsold be a Community-delete flow-ban a lokális tanulási adat törlését is, futtasd a backend pytest-et → az **A7** regressziós cellának PIROSNAK kell lennie → állítsd vissza.

## 7. Kötelező ellenőrzések

```bash
tools/round-gate.sh test/features/community/presentation/community_data_screen_test.dart
```

A backend oldal külön, önálló parancs (NEM láncolva):

```bash
cd backend && python -m pytest tests/community/test_data_rights_service.py -q
```

A gate artefaktum a mérce (`tools/round-gate.sh`) — a parancssorban
reprodukált parancslista NEM bizonyíték (AGENTS.md §12, L09). A script
`format` → `analyze` → `test <minden útvonal külön>` → `architecture`
lépéseket KÜLÖN processzként futtat, csonkítatlan kimenettel. **Tilos**
bármilyen szűrés vagy kézi lánc a promptban (OOM, L05). A kötelező gate-et
**TILOS háttérbe küldeni** (`run_in_background`) — az egy-fordulós harness a
forduló végén megöli, mielőtt eredmény érkezne (L183/L254). CI-dispatch, PR és
merge mindig Claude-oldal: az implementer `gh`-t NEM hív.

## 8. Implementációs sorrend

1. `data_rights_service.py` — export-job (aggregáció minden Community-táblából), deactivate, delete.
2. `data_rights.py` router — cross-account denial, signed/rövid-TTL export-link.
3. `community_privacy_screen.dart` — a hat beállítás-kategória.
4. `community_data_screen.dart` — export/deactivate/delete, KÉT külön megerősítő flow.
5. A media-cleanup és cache-invalidation job bekötése törléskor.
6. A valódi-sértés próba §10-be; a §7 mindkét parancsa KÜLÖN futtatva.

## 9. Kockázatok

- **Az egyesített törlés-gomb.** A legkönnyebb UX-csábítás, de véletlenül törölné a felhasználó teljes tanulási történetét (A7).
- **A cross-account export-szivárgás.** Egy hiányzó ownership-ellenőrzés más felhasználó teljes adatkészletét szolgáltatná ki (A2).
- **A media-cleanup elmaradása.** Törölt profil médiafájljai árvaként, feleslegesen tárolva maradnának (A6).

## 10. Implementation handoff — az implementer tölti ki

## 11. Review — a Claude tölti ki
