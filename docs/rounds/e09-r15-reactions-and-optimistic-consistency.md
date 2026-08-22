# E09-R15 — Reakciók és optimista konzisztencia

- **Státusz:** PREPARED (előre megírva 2026-08-22, kód olvasva: `main @ db6293f4`)
- **Típus:** Chapter 10 (Epic 9 — Community Platform), Kör 15
- **Kör-azonosító:** `E09-R15`
- **Branch:** `<motor>/e09-r15-reactions-and-optimistic-consistency`
- **Előfeltétel:** `E09-R14` merge-elve
- **Brief szerzője:** Claude (Opus 5)
- **Előre kiosztott ADR:** nincs — ez a kör nem hoz új kötött architekturális döntést (tisztán UI/integráció/lezárás).

> ⚠ **Pre-flight (indítás előtt KÖTELEZŐ):** olvasd újra a Kör 11 post-projekció TÉNYLEGES mezőit — a viewer-reaction és az aggregált count itt egészül ki, nem egy külön endpointban. Eltérésnél
> §0.0 brief-revízió, NEM csendes lista-tágítás.

```ai-router
schema_version = 1
risk = "normal"
allowed_paths = [
  "backend/app/community/models/reaction.py",
  "backend/app/community/services/reaction_service.py",
  "backend/alembic/versions/e09_r15_0009_community_reaction.py",
  "lib/features/community/application/controllers/reaction_controller.dart",
  "lib/features/community/presentation/widgets/reaction_bar.dart",
  "backend/tests/community/test_reaction_service.py",
  "test/features/community/application/reaction_controller_test.dart",
  "docs/rounds/e09-r15-reactions-and-optimistic-consistency.md",
]
gate_tests = [
  "test/features/community/application/reaction_controller_test.dart"
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

Pozitív, idempotens, allowlistelt reakciórendszer backenddel és optimista Flutter UI-val — retry nem duplikál, gyors váltásnál a legutolsó szándék nyer.

## 2. Jelenlegi állapot — mért tények

- A Kör 11 post-projekció MA nem hordoz reaction-mezőt — ez a kör adja hozzá
- A gamifikáció E08-R26 cross-feature adaptere MÁR bizonyítja a mintát: "közösségi engagement nem ad learning XP-t" — ez a kör ugyanezt az elvet alkalmazza a saját reakciójára

## 3. Scope

**Benne van:** reaction tábla `(post_id, profile_id)` unique constrainttel · reaction set/remove endpoint idempotensen · allowlistelt típusok: support, celebrate, inspiring, helpful · post-projekció: viewer reaction + aggregált count · optimista Flutter update mutation-ID-vel + rollback · gyors váltásnál a legutolsó user-szándék nyer · SEMMILYEN learning reward-event kibocsátása.

**NINCS benne (tilos):**

- Negatív/downvote reakció — a §14.1 SDD kizárja az első verzióból.
- Komment — Kör 16.
- `docs/adr/**`, `tools/**`, `.github/**`.

## 4. Engedélyezett fájlok

| Útvonal | Indok |
|---|---|
| `backend/app/community/models/reaction.py` | ÚJ |
| `backend/app/community/services/reaction_service.py` | ÚJ |
| `backend/alembic/versions/e09_r15_0009_community_reaction.py` | ÚJ |
| `lib/features/community/application/controllers/reaction_controller.dart` | ÚJ |
| `lib/features/community/presentation/widgets/reaction_bar.dart` | ÚJ |
| `backend/tests/community/test_reaction_service.py` | ÚJ — a §6 cellái |
| `test/features/community/application/reaction_controller_test.dart` | ÚJ |

**Tilos zóna:** `lib/features/gamification/**` (a kör NEM importálja, csak elvben követi a no-XP mintát) · `lib/features/community/domain/**` · `docs/adr/**` · `tools/**` · `.github/**`

## 5. Kötött architekturális döntések

### 5.1 Nincs ÚJ kötött döntés — a Kör 1 no-live-realtime és a §6/10.4 no-XP invariáns alkalmazása

Ez a kör nem vezet be új architekturális szerződést; a reakció idempotenciája a Kör 11 post-create mintáját követi, és a "közösségi engagement nem ad learning XP-t" a §6 kötelező invariáns közvetlen alkalmazása, nem új szabály.

**NEM elfogadható gyengítés:** egy "kis motivációs bónusz" bevezetése reakció fogadásáért — ez a §6/10.4 SDD-invariáns megsértése lenne, akkor is, ha nem önálló ADR-t igényelne.

## 6. Acceptance criteria

| # | Kritérium | Bizonyíték |
|---|---|---|
| A1 | Retry (duplicate set) nem növeli kétszer a countot | `test_reaction_service.py` |
| A2 | Reaction-típus csere update-ként megy, nem új rekordként | `test_reaction_service.py` |
| A3 | Remove kétszer hívva sem hibázik és nem megy negatívba a count | `test_reaction_service.py` |
| A4 | Concurrent toggle mellett a viewer state végül konzisztens | `test_reaction_service.py` |
| A5 | A count property-invariánsként sosem negatív | `test_reaction_service.py` — property teszt |
| A6 | Optimista update rollback hálózati hiba esetén (Flutter) | `reaction_controller_test.dart` |
| A7 | A reakció NEM bocsát ki learning reward-eventet | `test_reaction_service.py` — regresszió |

### 6.1 Mérce-mátrix — melyik hibás implementációt melyik cella fogja pirosra

| Hibás implementáció | Melyik cella vált PIROSRA |
|---|---|
| A duplicate set egy második rekordot hoz létre a `(post_id, profile_id)` unique nélkül | A1 |
| A remove a countot negatívba engedi menni | A5 |
| A reakció-módosítás egy learning-reward hívást indít | A7 |
| A gyors kettős tap eltérő végállapotot ad a valódi user-szándéktól | A4 |

**Valódi-sértés próba (KÖTELEZŐ, §10-ben dokumentálva):** vedd ki a `(post_id, profile_id)` unique constraintet, futtasd a backend pytest-et duplicate-set szimulációval → az **A1** cellának PIROSNAK kell lennie → állítsd vissza.

## 7. Kötelező ellenőrzések

```bash
tools/round-gate.sh test/features/community/application/reaction_controller_test.dart
```

A backend oldal külön, önálló parancs (NEM láncolva):

```bash
cd backend && python -m pytest tests/community/test_reaction_service.py -q
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

1. Migráció: `community_reactions` unique constraint + allowlist enum.
2. `reaction_service.py` — set (upsert), remove, aggregált count a post-projekcióban.
3. `reaction_controller.dart` — optimista update, rollback, legutolsó-szándék szabály.
4. `reaction_bar.dart` — allowlistelt ikonok, accessible label.
5. A property-invariáns teszt (count sosem negatív).
6. A valódi-sértés próba §10-be; a §7 mindkét parancsa KÜLÖN futtatva.

## 9. Kockázatok

- **A duplikált reakció-rekord.** Enélkül a count manipulálhatóvá válik (A1).
- **A learning-XP-vel való összekötés kísértése.** "Csak egy kis bónusz" a reakciókért — pontosan az, amit a §6/§10.4 SDD kizár (A7).
- **A negatív count.** Egy rossz sorrendű remove-hívás alatt megjelenő átmeneti negatív érték UX-hibaként látszana (A5).

## 10. Implementation handoff — az implementer tölti ki

## 11. Review — a Claude tölti ki
