# E09-R20 — Notification inbox és push abstraction

- **Státusz:** PREPARED (előre megírva 2026-08-22, kód olvasva: `main @ db6293f4`)
- **Típus:** Chapter 10 (Epic 9 — Community Platform), Kör 20
- **Kör-azonosító:** `E09-R20`
- **Branch:** `<motor>/e09-r20-notification-inbox-and-push-abstraction`
- **Előfeltétel:** `E09-R19` merge-elve
- **Brief szerzője:** Claude (Opus 5)
- **Előre kiosztott ADR:** `ADR 0409` — a szám FOGLALT (Epic 9 batch-tartomány 0395-0419). Az ADR-t a Claude írja meg a kör indítási pre-flightjában a §5 döntéseiből; az implementer a `docs/adr/`-t NEM érinti (TILOS zóna).

> ⚠ **Pre-flight (indítás előtt KÖTELEZŐ):** olvasd újra a Kör 8 block-szűrő és a Kör 15/16 esemény-forrásokat (reakció, komment) — az értesítés-generálás ezekre a MEGLÉVŐ eseményekre épül. Eltérésnél
> §0.0 brief-revízió, NEM csendes lista-tágítás.

```ai-router
schema_version = 1
risk = "high"
allowed_paths = [
  "backend/app/community/models/notification.py",
  "backend/app/community/notifications/notification_service.py",
  "backend/app/community/notifications/push_gateway.py",
  "backend/alembic/versions/e09_r20_0014_community_notification.py",
  "lib/features/community/presentation/screens/community_notifications_screen.dart",
  "backend/tests/community/test_notification_service.py",
  "test/features/community/presentation/community_notifications_test.dart",
  "docs/rounds/e09-r20-notification-inbox-and-push-abstraction.md",
]
gate_tests = [
  "test/features/community/presentation/community_notifications_test.dart"
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

Tartós, kategorizált közösségi értesítések és opcionális push delivery — a push CSAK delivery channel, az inbox az elsődleges igazság-forrás.

## 2. Jelenlegi állapot — mért tények

- A Kör 7 (follow), Kör 15 (reakció), Kör 16 (komment/mention) MA generál eseményeket, de egyik sem hoz létre tartós notification-itemet
- a projekt MA NEM rendelkezik push-gateway absztrakcióval

## 3. Scope

**Benne van:** notification tábla: recipient, type, actor, entity, read state, dedup key · inbox list, unread count, mark-read, mark-all-read endpoint · reaction-burst aggregáció dokumentált időablakban · provider-semleges push gateway interfész; a payload CSAK notification ID + minimális route-adat · kategória-preferencia + lokális quiet-hours támogatás · kliensen az inbox az elsődleges igazság, a push csak refresh-trigger · block/mute és content-deletion frissíti vagy rejti az érintett inbox itemet.

**NINCS benne (tilos):**

- Tényleges push-szolgáltató (FCM/APNs) bekötése — ez a kör csak az absztrakciót és egy mock/no-op adaptert ad.
- Challenge/club-specifikus notification típus — Kör 21/24 adja hozzá a saját típusát.
- `docs/adr/**` — az ADR 0409-et a Claude írja.

## 4. Engedélyezett fájlok

| Útvonal | Indok |
|---|---|
| `backend/app/community/models/notification.py` | ÚJ |
| `backend/app/community/notifications/notification_service.py` | ÚJ |
| `backend/app/community/notifications/push_gateway.py` | ÚJ — interfész + no-op adapter |
| `backend/alembic/versions/e09_r20_0014_community_notification.py` | ÚJ |
| `lib/features/community/presentation/screens/community_notifications_screen.dart` | ÚJ |
| `backend/tests/community/test_notification_service.py` | ÚJ — a §6 cellái |
| `test/features/community/presentation/community_notifications_test.dart` | ÚJ |

**Tilos zóna:** `backend/app/community/services/reaction_service.py`, `comment_service.py`, `follow_service.py` (csak HÍVÁS az esemény végén, nem átírás) · `docs/adr/**` · `tools/**` · `.github/**`

## 5. Kötött architekturális döntések (ADR 0409)

### 5.1 A push CSAK delivery channel — a payload minimális és redacted

A push payload kizárólag notification ID-t, típust és route-safe entity ID-t tartalmaz — sem tokent, sem teljes kommentet, sem privát adatot.

**NEM elfogadható gyengítés:** a teljes komment-szöveg vagy a szerző e-mail-je a push-payloadban "hogy a preview szebb legyen" — ez a §17.2 SDD-invariáns közvetlen megsértése, és a push-szolgáltatón keresztül szivárogna.

### 5.2 A reaction-burst AGGREGÁLT — nem öt külön push

Több reakció egy dokumentált időablakon belül egyetlen összegzett notification-itemet és legfeljebb egy push-ot ad.

### 5.3 Az inbox az ELSŐDLEGES igazság — a push csak trigger

A kliens az inboxot olvassa vissza igazságforrásként; a push elvesztése (pl. offline device) nem okoz információvesztést, csak késleltetett frissülést.

## 6. Acceptance criteria

| # | Kritérium | Bizonyíték |
|---|---|---|
| A1 | Push payload nem tartalmaz érzékeny teljes szöveget | `test_notification_service.py` |
| A2 | Reaction-burst aggregált, nem N külön push | `test_notification_service.py` |
| A3 | Read state helyes és versenyhelyzetben is konzisztens (unread count race) | `test_notification_service.py` |
| A4 | Blocked actor eseménye rejtett az inboxban | `test_notification_service.py` |
| A5 | Törölt entitásra mutató notification kezelt (nem broken deep link) | `test_notification_service.py` |
| A6 | Kategóriánként kikapcsolható push | `community_notifications_test.dart` |
| A7 | Dedup-kulcs megakadályozza a duplikált notification-itemet | `test_notification_service.py` |

### 6.1 Mérce-mátrix — melyik hibás implementációt melyik cella fogja pirosra

| Hibás implementáció | Melyik cella vált PIROSRA |
|---|---|
| A push payload tartalmazza a teljes komment-szöveget | A1 |
| Öt egymást követő reakció öt külön push-ot generál | A2 |
| Két konkurens mark-read hívás inkonzisztens unread-countot hagy | A3 |
| Egy blockolt user reakciója mégis megjelenik az inboxban | A4 |
| A dedup-kulcs hiányzik, retry duplikált itemet hoz létre | A7 |

**Valódi-sértés próba (KÖTELEZŐ, §10-ben dokumentálva):** adj hozzá egy `commentBody` mezőt a push-payloadhoz, futtasd a backend pytest redaction-tesztjét → az **A1** cellának PIROSNAK kell lennie → állítsd vissza.

## 7. Kötelező ellenőrzések

```bash
tools/round-gate.sh test/features/community/presentation/community_notifications_test.dart
```

A backend oldal külön, önálló parancs (NEM láncolva):

```bash
cd backend && python -m pytest tests/community/test_notification_service.py -q
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

1. Migráció: `community_notifications` (recipient, type, actor, entity, read_state, dedup_key).
2. `notification_service.py` — create + aggregation-időablak + mark-read/mark-all-read.
3. `push_gateway.py` — provider-semleges interfész, no-op default adapter, minimális payload.
4. Bekötés a Kör 7/15/16 szolgáltatások esemény-kibocsátási pontjára.
5. `community_notifications_screen.dart` — lista, kategória-preferencia, quiet-hours (lokális).
6. A valódi-sértés próba §10-be; a §7 mindkét parancsa KÜLÖN futtatva.

## 9. Kockázatok

- **A push-payload túlírása.** A "jobb előnézet" csábítása a legkönnyebb út egy adatvédelmi incidenshez (A1).
- **Az értesítési vihar.** Egy vírusszerűen terjedő poszt reakció-burstje enélkül elárasztaná a felhasználót (A2).
- **Az unread-count race.** Két eszköz egyidejű mark-read hívása hibás, negatív vagy ragadt számot hagyhat (A3).

## 10. Implementation handoff — az implementer tölti ki

## 11. Review — a Claude tölti ki
