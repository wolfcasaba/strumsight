# E09-R29 — Offline sync, konfliktuskezelés és outbox hardening

- **Státusz:** PREPARED (előre megírva 2026-08-22, kód olvasva: `main @ db6293f4`)
- **Típus:** Chapter 10 (Epic 9 — Community Platform), Kör 29
- **Kör-azonosító:** `E09-R29`
- **Branch:** `<motor>/e09-r29-offline-sync-conflict-and-outbox-hardening`
- **Előfeltétel:** `E09-R28` merge-elve
- **Brief szerzője:** Claude (Opus 5)
- **Előre kiosztott ADR:** `ADR 0417` — a szám FOGLALT (Epic 9 batch-tartomány 0395-0419). Az ADR-t a Claude írja meg a kör indítási pre-flightjában a §5 döntéseiből; az implementer a `docs/adr/`-t NEM érinti (TILOS zóna).

> ⚠ **Pre-flight (indítás előtt KÖTELEZŐ):** olvasd újra a Kör 12 `community_outbox.dart` TÉNYLEGES mutation-típusait — ez a kör EGYSÉGESÍTI a post-outboxot a reakció/komment/bookmark/follow/challenge-result mutációkkal, nem ír felül egy meglévő szerződést. Eltérésnél
> §0.0 brief-revízió, NEM csendes lista-tágítás.

```ai-router
schema_version = 1
risk = "high"
allowed_paths = [
  "lib/features/community/application/outbox/community_sync_engine.dart",
  "lib/features/community/data/local/community_outbox_store.dart",
  "lib/features/community/presentation/screens/failed_mutations_screen.dart",
  "test/features/community/application/community_sync_engine_test.dart",
  "docs/rounds/e09-r29-offline-sync-conflict-and-outbox-hardening.md",
]
gate_tests = [
  "test/features/community/application/community_sync_engine_test.dart"
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

Minden Community mutáció megbízható, restart-biztos és idempotens szinkronizálása — egyetlen retry sem duplikál szerveroldali entitást.

## 2. Jelenlegi állapot — mért tények

- A Kör 12 post-outbox MA létezik — ez a kör kiterjeszti minden mutáció-típusra egy egységes szerződéssé
- A Kör 15/16/17/7/22 (reakció/komment/bookmark/follow/challenge-result) MA külön-külön hívja a saját endpointjukat közvetlenül — ez a kör vezeti be az egységes outbox-réteget alattuk

## 3. Scope

**Benne van:** egységes outbox-rekord post/reaction/comment/bookmark/follow/challenge-result mutációkra · per-user védett lokális store, bounded retention · dependency-ordering: media-finalize → post-create, post-create → comment · retry-policy kategóriánként: network, auth, validation, conflict, permanent failure · token-lejáratkor a sync VÁR az auth-recoveryre, nem dobja el a payloadot · ETag/version conflict-resolver UI profil/post/comment edithez · dead-letter/failed-mutations képernyő szerkesztés/retry/discard lehetőséggel.

**NINCS benne (tilos):**

- Bármely endpoint TÉNYLEGES üzleti logikájának módosítása — ez a kör kizárólag a kliensoldali szinkron-réteget hardeneli.
- `docs/adr/**` — az ADR 0417-et a Claude írja.

## 4. Engedélyezett fájlok

| Útvonal | Indok |
|---|---|
| `lib/features/community/application/outbox/community_sync_engine.dart` | ÚJ |
| `lib/features/community/data/local/community_outbox_store.dart` | ÚJ |
| `lib/features/community/presentation/screens/failed_mutations_screen.dart` | ÚJ |
| `test/features/community/application/community_sync_engine_test.dart` | ÚJ — a §6 cellái |

**Tilos zóna:** `lib/features/community/data/repositories/**` (csak HÍVÁS, nem átírás) · `backend/**` · `docs/adr/**` · `tools/**` · `.github/**`

## 5. Kötött architekturális döntések (ADR 0417)

### 5.1 A retry SOSEM duplikál szerveroldali entitást, egyik mutáció-típusnál sem

Minden mutáció-típus (post/reaction/comment/bookmark/follow/challenge-result) a saját idempotency-kulcsával megy — az outbox csak a KÉZBESÍTÉST garantálja, az idempotencia forrása minden esetben a mögöttes endpoint (Kör 7/11/15/16/17/22).

**NEM elfogadható gyengítés:** egy "univerzális" outbox-szintű dedup, ami a mutáció tartalmát hasheli össze — ez törékeny, és nem egyezik meg a mögöttes endpointok saját, már bizonyított idempotency-kulcs-mintájával.

### 5.2 Token-lejáratkor a sync VÁR, nem dob el payloadot

Egy 401-es válasz a mutációt `paused` állapotba teszi az auth-recovery-ig — nem törli és nem jelöli véglegesen sikertelennek.

### 5.3 Account-váltás TELJESEN izolálja az outboxot

A régi user pending mutációi SOSEM küldődnek el az új user sessionjében, és fordítva.

## 6. Acceptance criteria

| # | Kritérium | Bizonyíték |
|---|---|---|
| A1 | Egyetlen retry sem duplikál szerveroldali entitást (mind a hat mutáció-típusra) | `community_sync_engine_test.dart` |
| A2 | Dependency-ordering helyes (media-finalize → post-create → comment) | `community_sync_engine_test.dart` |
| A3 | 401 után a mutáció `paused`, nem elveszett | `community_sync_engine_test.dart` |
| A4 | Permanent validation failure a felhasználóhoz kerül szerkeszthető/eldobható formában | `failed_mutations_screen` teszt |
| A5 | Accountváltás nem küld más user outboxából adatot | `community_sync_engine_test.dart` |
| A6 | Az outbox mérete korlátozott (bounded queue) | `community_sync_engine_test.dart` |
| A7 | App kill mid-sync után a mutáció konzisztens állapotból folytatódik | `community_sync_engine_test.dart` |

### 6.1 Mérce-mátrix — melyik hibás implementációt melyik cella fogja pirosra

| Hibás implementáció | Melyik cella vált PIROSRA |
|---|---|
| Egy 401-es válasz törli a pending mutációt | A3 |
| Account-váltás után a régi user mutációja elküldődik az új session alatt | A5 |
| A komment elküldése a post-create befejezése előtt indul | A2 |
| Az outbox korlátlanul nő, nincs bounded retention | A6 |
| App-kill közben félbeszakadt mutáció duplán küldődik újraindítás után | A1/A7 |

**Valódi-sértés próba (KÖTELEZŐ, §10-ben dokumentálva):** állítsd a sync-engine-t úgy, hogy egy 401-es válaszra törölje a pending mutációt, futtasd a tesztet → az **A3** cellának PIROSNAK kell lennie → állítsd vissza.

## 7. Kötelező ellenőrzések

```bash
tools/round-gate.sh test/features/community/application/community_sync_engine_test.dart
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

1. `community_outbox_store.dart` — per-user, védett, bounded lokális store.
2. `community_sync_engine.dart` — dependency-ordering, retry-kategóriák, 401-pause/resume.
3. A meglévő hat mutáció-típus (Kör 7/11/15/16/17/22) bekötése az egységes outboxba.
4. ETag/version conflict-resolver UI.
5. `failed_mutations_screen.dart` — szerkesztés/retry/discard.
6. A valódi-sértés próba §10-be.

## 9. Kockázatok

- **A payload-elvesztés token-lejáratkor.** A felhasználó órákig írt tartalma tűnne el egy egyszerű újra-bejelentkezés miatt (A3).
- **Az account-keveredés.** Egy megosztott eszközön ez különösen súlyos adatvédelmi hiba lenne (A5).
- **A duplikáció app-kill közben.** A legnehezebben reprodukálható, de leggyakoribb valós hibaosztály mobil környezetben (A1/A7).

## 10. Implementation handoff — az implementer tölti ki

## 11. Review — a Claude tölti ki
