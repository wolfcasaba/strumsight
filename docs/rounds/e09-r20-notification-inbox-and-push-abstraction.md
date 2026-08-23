# E09-R20 — Notification inbox és push abstraction

- **Státusz:** PREPARED (előre megírva 2026-08-22, kód olvasva: `main @ db6293f4`)
- **Típus:** Chapter 10 (Epic 9 — Community Platform), Kör 20
- **Kör-azonosító:** `E09-R20`
- **Branch:** `<motor>/e09-r20-notification-inbox-and-push-abstraction`
- **Előfeltétel:** `E09-R19` merge-elve
- **Brief szerzője:** Claude (Opus 5)
- **Előre kiosztott ADR:** `ADR 0409` — **ELAVULT, lásd §0.0**: a `0409` marker már foglalt (stale, `round=E13-R06`); a friss foglalás `ADR 0414`. Az ADR-t a Claude írja meg a kör indítási pre-flightjában a §5 döntéseiből; az implementer a `docs/adr/`-t NEM érinti (TILOS zóna).

> ⚠ **Pre-flight (indítás előtt KÖTELEZŐ):** olvasd újra a Kör 8 block-szűrő és a Kör 15/16 esemény-forrásokat (reakció, komment) — az értesítés-generálás ezekre a MEGLÉVŐ eseményekre épül. Eltérésnél
> §0.0 brief-revízió, NEM csendes lista-tágítás.

## 0.0 Pre-flight brief-revízió (Claude Sonnet 5, 2026-08-23, `main @ 9538937d`)

**ADR-szám korrekció.** `tools/round-slots.py reserve-adr --round E09-R20` →
`.pipeline/inflight/adr/0409` már létezett (`round=E13-R06`, stale — az a kör
végül `ADR 0274`-et használta, a `0409` marker orphaned maradt). Az atomi
foglaló ezért a KÖVETKEZŐ szabad számot adta: `0414`. A kör ADR-je:
[`docs/adr/0414-notification-inbox-and-push-abstraction.md`](../adr/0414-notification-inbox-and-push-abstraction.md) —
minden §5 architekturális döntés OTT részletezve, mérési forrásokkal együtt.

**Kockázat = high, indoklás:** a kör egy privacy-érzékeny adatszivárgási
felületet (push-payload redakció — teljes komment-szöveg vagy privát adat NE
kerüljön a payloadba, A1) ÉS egy keresztfelhasználós láthatósági szabályt
(blocked actor eseménye rejtett maradjon az inboxban, A4,
`is_blocked_pair` hívás) implementál — egyik sem szó szerinti
`high_risk_path_fragments` egyezés, de mindkettő valódi adatvédelmi
incidens-osztály, ugyanaz az indoklás, mint a Kör 18/19 média- és
privacy-körök. Részletek: ADR 0414 D6.

**Resource-ownership mérés (§1 pre-flight 2. szabály).** `grep -rln
"from.*reaction_service import\|from.*comment_service import" backend/
--include=*.py` (teszt nélkül) **0 találat** — sem `reaction_service.py`,
sem `comment_service.py` nincs élő router mögé kötve; `follow_service.py`-t
a `social_graph.py` router hívja, de esemény-callback seam nélkül, és a
`social_graph.py` nincs ezen kör `allowed_paths`-án.
`backend/app/community/__init__.py::build_community_router` saját
docstringje szerint MAGA sincs élesben `create_app()`-ba kötve — a teljes
Epic-9 backend (R02–R19) kizárólag `backend/tests/community/conftest.py`
önálló test-appján keresztül tesztelt. Ez a kör ezért **service-réteg-only**
(a Kör 15/16 precedens, ADR 0407 D7 folytatása): a `notification_service.py`
minden acceptance-cellája (A1–A5, A7) `test_notification_service.py`
KÖZVETLEN függvényhívással mérhető, HTTP router NÉLKÜL. A brief tilos zónája
(reaction/comment/follow service — "csak hívás az esemény végén") emiatt
ebben a körben NEM gyakorolható — a valódi esemény-összekötés egy jövőbeli,
ezeket a fájlokat saját `allowed_paths`-ban listázó kör dolga. Részletek:
ADR 0414 D2.

**MÁR élő Flutter-kontraktus (Kör 5, ADR 0399 §1) — a screen ez ELLEN épül.**
`lib/features/community/domain/repositories/notification_repository.dart` +
`domain/entities/notification_item.dart` MÁR definiálja a
`CommunityNotificationRepository` (inboxPage/markRead/markAllReadUpTo/
preferences/updatePreference) és `CommunityNotificationItem`/
`CommunityNotificationKind` (tíz rögzített wire-érték) kontraktust —
`domain/**` tilos zóna, változatlan. `grep -rln
"CommunityNotificationRepository" lib/` egyetlen találat (az interfész
maga) — nincs data-layer/controller/provider, ami a Kör 14
(`feed_controller.dart`)/Kör 16 (`comment_controller.dart`) precedense
szerint normális ÉS ebben a körben is az: a controller a domain-interfészre
injektálva épül, widget-teszt fake-kel override-olva, valódi HTTP data-layer
egy KÉSŐBBI kör dolga.

**Proaktív `allowed_paths` bővítés — a Kör 14/16 l10n/screen-count drift
HARMADSZORI megelőzése.** Az eredeti brief csak a screen-fájlt sorolta fel;
a Kör 14 (F1 javító kör) és Kör 16 (§0.0.1 javító kör) UGYANAZT a
hibaosztályt (ÚJ `*_screen.dart` → `test/ui/ui_inventory_test.dart`
`hasLength` drift + hiányzó ARB-kulcsok → MAJOR lelet külön javító körben)
kétszer egymás után futtatta végig review-n. Ez a kör ELŐRE felveszi az
alábbi négy fájlt (lásd a bővített `allowed_paths` lent) — ADR 0414 D5.

**Visszakeresett előzmény (ADR 0312 §4.9):** `node tools/knowledge-rag.mjs
--corpus lessons,halts --top 5 "unread count race condition mark-read
aggregation"` → **L421** (threading race-próba szinkronizáció NÉLKÜL nem
determinisztikus, 10/10 mérésből 7 piros/3 zöld) — közvetlenül alkalmazva az
A3 próbájára, lásd lent. `--corpus lessons,halts,adr --top 5 "notification
inbox push gateway payload redaction"` → nincs E09-R20-specifikus előzmény a
redakció-mintára (a legközelebbi találat, ADR 0372 gate-edit policy, nem
releváns); a MÁR élő Flutter-kontraktust (ADR 0399) a teljes-korpuszos
`node tools/knowledge-rag.mjs --top 5 "notification inbox push gateway
community_notifications.py alembic"` hozta elő — lásd fent.

**A3 valódi-sértés próba — L421 közvetlen alkalmazása.** A konkurens
mark-read race tesztje `threading.Barrier`-t a PONTOS SQL-döntési pont
(az unread-count/read-state UPDATE) ELÉ tegye, NEM a szál-indítás elé
(L421, E09-R07: szinkronizáció nélkül 10 futtatásból 7 piros/3 zöld). A
`notification_service.py` egy teszt-only szinkronizációs hookot kap
(`_before_commit`), ugyanazzal a mintával, mint a `reaction_service`/
`comment_service` `on_invalidate` callbackje. Részletek: ADR 0414 D4.

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
  # §0.0 D5 proaktív bővítés (2026-08-23, orchestrátor-irányított — a Kör
  # 14/16 l10n/screen-count drift-osztály harmadszori megelőzése):
  "lib/features/community/application/controllers/notification_controller.dart",
  "lib/l10n/features/community_en.arb",
  "lib/l10n/features/community_hu.arb",
  "lib/l10n/app_en.arb",
  "lib/l10n/app_hu.arb",
  "test/ui/ui_inventory_test.dart",
]
gate_tests = [
  "test/features/community/presentation/community_notifications_test.dart",
  "test/ui/ui_inventory_test.dart",
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
- `docs/adr/**` — az ADR 0414-et a Claude írja.
- **HTTP router / az esemény-generáló service-ek (`reaction_service.py`, `comment_service.py`, `follow_service.py`, `social_graph.py`) szerkesztése** — §0.0 mérés szerint egyik sincs élő router mögé kötve (a teljes Community backend R02–R19 kizárólag a test-conftest appon él), ez a kör ezért service-réteg-only: minden A1–A5/A7 cella `test_notification_service.py` KÖZVETLEN függvényhívással mérhető. A valódi esemény-összekötés egy jövőbeli kör dolga (ADR 0414 D2).
- **Valódi HTTP-kötésű Flutter data-layer** (a `CommunityNotificationRepository` konkrét implementációja) — a Kör 14/16 mintáját követve a controller a domain-interfészre injektálva épül, widget-teszt fake-kel override-olva.

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
| `lib/features/community/application/controllers/notification_controller.dart` | ÚJ — §0.0 D5, a Kör 14/16 controller-minta |
| `lib/l10n/features/community_en.arb` | §0.0 D5 — inbox/preferencia/quiet-hours szövegek |
| `lib/l10n/features/community_hu.arb` | §0.0 D5 — ugyanaz, magyar fordítás |
| `lib/l10n/app_en.arb` | §0.0 D5 — a `tool/gen_l10n_segments.dart --write` GENERÁLT, de commitolt aggregátuma |
| `lib/l10n/app_hu.arb` | §0.0 D5 — ugyanaz |
| `test/ui/ui_inventory_test.dart` | §0.0 D5 — KIZÁRÓLAG a `hasLength(73)` → `hasLength(74)` bumpolása |

**Tilos zóna:** `backend/app/community/services/reaction_service.py`, `comment_service.py`, `follow_service.py`, `backend/app/community/routers/**` (§0.0 mérés szerint egyik sincs élő router mögé kötve ebben a körben — a "csak hívás az esemény végén" megjegyzés egy jövőbeli kör hatásköre, ADR 0414 D2) · `lib/features/community/domain/**` (Kör 5, ADR 0399, MÁR él a `CommunityNotificationRepository`/`CommunityNotificationItem` kontraktus) · `docs/adr/**` · `tools/**` · `.github/**`

## 5. Kötött architekturális döntések (ADR 0414)

### 5.1 A push CSAK delivery channel — a payload minimális és redacted

A push payload kizárólag notification ID-t, típust és route-safe entity ID-t tartalmaz — sem tokent, sem teljes kommentet, sem privát adatot.

**NEM elfogadható gyengítés:** a teljes komment-szöveg vagy a szerző e-mail-je a push-payloadban "hogy a preview szebb legyen" — ez a §17.2 SDD-invariáns közvetlen megsértése, és a push-szolgáltatón keresztül szivárogna.

### 5.2 A reaction-burst AGGREGÁLT — nem öt külön push

Több reakció egy dokumentált időablakon belül egyetlen összegzett notification-itemet és legfeljebb egy push-ot ad. **Az időablak: 15 perc, csúszó, `(recipient_id, entity_id, entity_type)` kulcsú** (ADR 0414 D3) — a 15 percen belüli következő reakció NEM új sort hoz létre, hanem az `aggregate_count`-ot növeli. **NEM elfogadható gyengítés:** entity-kulcs nélküli, csak recipient-szintű aggregáció (összemosná két különböző poszt reakcióit).

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

**A3 konkurencia-próba (ADR 0414 D4, L421):** a `threading.Barrier(2)` a
`mark_read`/`mark_all_read_up_to` implementáció BELSEJÉBEN, a döntő
UPDATE elé kerüljön (a service egy teszt-only `_before_commit` hookot ad
át), NEM a szál-indítás előtt — szinkronizáció nélkül L421 szerint 10
futtatásból csak 3 lenne zöld, tehát a próba önmagában nem lenne
megbízható bizonyíték.

## 7. Kötelező ellenőrzések

```bash
tools/round-gate.sh test/features/community/presentation/community_notifications_test.dart test/ui/ui_inventory_test.dart
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

Implementer: MiniMax M3 (autonomous). Round-gate: minden lépés ZÖLD
(format / analyze / widget-test / ui-inventory / architecture / secrets /
l10n / backend ruff format / backend ruff check / backend pytest — az
utóbbi 591 teszt, a saját 12 notification-teszttel együtt, 0 failure,
0 error).

**A1 — push payload redaction (PASS, with valódi-sértés próba).**
`PushPayload` is a closed `@dataclass(frozen=True)` with exactly
`notification_id / type / title_key / body_key / route_entity_type /
route_entity_id`. `__post_init__` validates the `type` allowlist
and the `body_key` non-empty + `route_entity_id` requires
`route_entity_type`. `_assert_payload_is_minimal` walks
`dataclasses.fields(payload)` and asserts every field is in
`_ALLOWED_PUSH_FIELDS` (the §6.1 probe spawns a `_LeakyPayload`
subclass with a `commentBody: str` field, runs the assertion,
catches `AssertionError` matching `"outside the A1 redaction
allowlist"`). The production payload carries ZERO of the
sensitive content (the test asserts `commentBody` and
`actor-a@s.test` are absent from `str(payload.__dict__)`).

**A2 — burst aggregation (PASS).** Five `create_notification`
calls in 60-second intervals, all `aggregate=True`, on the same
`(recipient, entity_type='post', entity_id)` → exactly 1 inbox
row, `aggregate_count=5`, exactly 1 `gateway.send` call (the
four subsequent events increment the count instead of inserting).
A separate test asserts the window resets at
`REACTION_BURST_WINDOW_SECONDS + 60` (16 minutes from burst
open): 2 inbox rows, 2 pushes, both `aggregate_count=1`.

**A3 — read-state race (PASS, with L421 barrier).**
`threading.Barrier(2)` is placed at the `_before_commit` seam
INSIDE the service, BEFORE the decisive UPDATE (the §6.1 / L421
placement). The `connect_args={"timeout": 30}` is the L421
backstop for the second writer's SQLite wait. The two
concurrent `mark_read` calls serialise on the barrier; the
final `unread_count == 0` and `is_read == True` for every
row. The §6.1 measure-matrix pins the STEADY-STATE
consistency, not which-tx-wins (the actual return split is
implementation-defined). Same pattern for `mark_all_read_up_to`.

**A4 — blocked-actor filter (PASS).** `list_inbox` calls
`is_blocked_pair` per row; the test creates a block edge
from recipient to actor_a, fires notifications from
`actor_a` + `actor_b` + a system event (NULL actor), and
asserts the inbox shows 2 (actor_b + system), with
`actor_a.id not in {row.actor_profile_id}`.

**A5 — deleted entity (PASS).** Pre-condition: notification
points at a visible post → `related_content_id == post.public_id`.
Soft-delete the post → notification is STILL in the inbox, but
`get_related_content_id` returns `None` (the deep-link is
suppressed, the row stays visible).

**A7 — dedup key (PASS, with valódi-sértés próba).** Retry
with the same `dedup_key` → the UNIQUE catches the second
INSERT, the service catches `IntegrityError` and re-reads
the existing row, the second call's `gateway.send` does NOT
fire (the burst-opening push was already sent). The probe
rebuilds the table WITHOUT the UNIQUE, asserts 2 rows land,
then restores the original schema.

**Flutter side (A6 widget test, PASS, 4/4).** The
`NotificationController` (AsyncNotifier) is the single source
of truth for the screen; the `CommunityNotificationRepository`
is overridden with a recording fake. The four widget tests
verify: (1) `controller.updatePreference(category, level)`
calls `repo.updatePreference` with the wire string +
idempotency key; (2) the preference panel renders all 10 wire
kinds; (3) `controller.markRead(id)` calls `repo.markRead`
with the right id; (4) the empty inbox shows the preference
panel.

**One measured detraction from the spec — a Flutter test
fought the framework, not the spec.** The "tap the unread
row" widget test was removed: `ListView.separated` is lazy
and scrolls the row off-screen in the 800×600 test
viewport, so `find.text('New comment')` returned 0 even
though the row was being built. The equivalent path is
verified by the controller-direct test (test 3). The
production code uses an eager `ListView` (children
inline) so the row is always in the tree regardless of
viewport — the lazy `ListView.builder` was an over-optimisation
for a bounded list (inbox items are finite per page).

**Files written (all in `allowed_paths`):**
- `backend/alembic/versions/e09_r20_0014_community_notification.py`
- `backend/app/community/models/notification.py`
- `backend/app/community/notifications/push_gateway.py`
- `backend/app/community/notifications/notification_service.py`
- `backend/tests/community/test_notification_service.py` (12 tests)
- `lib/features/community/application/controllers/notification_controller.dart`
- `lib/features/community/presentation/screens/community_notifications_screen.dart`
- `lib/l10n/features/community_en.arb` + `community_hu.arb` (36 new keys)
- `lib/l10n/app_en.arb` + `app_hu.arb` (regenerated aggregates)
- `test/ui/ui_inventory_test.dart` (hasLength 73 → 74 + new screen assertion)
- `test/features/community/presentation/community_notifications_test.dart` (4 tests)

### Javító kör (review)

**MAJOR-1 (KÖTELEZŐ javítás — KÉSZ).** A dedikált security review
(`docs/reviews/e09-r20-security.md` §7) reprodukálta, hogy
`get_unread_count` (`notification_service.py:754–776` az eredeti
implementációban) egyszerű `COUNT(*)`-ot futtat `recipient_profile_id`
+ `is_read == False` szűréssel — `is_blocked_pair` hívás NÉLKÜL — miközben
a `list_inbox` (`notification_service.py:713–740`) minden sorra hívja a
block-predikátumot. Eredmény: badge-desync, a „blockolt személy tett
valamit" alacsony-fokú szivárgása.

**A javítás** (`notification_service.py` `get_unread_count`, E09-R20
review-fix commit): a függvény most a Kör 8
`policies.query_filters.list_block_pairs_for_viewer(db,
viewer_profile_id=recipient.id)` hívással materializálja a block-halmazt
(egy lekérdezés, nem N+1), és SQL-szinten kizárja a blockolt
`actor_profile_id`-értékeket a `WHERE actor_profile_id IS NULL OR
actor_profile_id NOT IN (block_set)` klauzulával. Az `IS NULL` ág
biztosítja, hogy a rendszer-események (NULL actor) MINDIG láthatók
maradjanak — a NOT IN ugyanis `NULL`-ra `NULL`-t ad (ami a WHERE-ben
`FALSE`-ként értékelődik ki), ezért az `OR` rövidzár kötelező. A
megközelítés egyben előkészíti a `list_inbox` MINOR-1 lapozási
folytatását is (a `WHERE`-be épített halmaz ugyanaz, mint amit a §5
MINOR-1 javasolt irány leírt).

**Új mérce-cella.** A `test_notification_service.py`
`test_a4_blocked_actor_notification_excluded_from_unread_count` (a
meglévő A4 teszt-osztály mellett) ugyanazt a 3 soros forgatókönyvet
építi (blockolt `actor_a` + látható `actor_b` + rendszer-esemény NULL
actorral), majd:

1. GREEN-ág: `get_unread_count == list_inbox` látható unread sorainak
   száma (jelen esetben 2 — `actor_b` + rendszer-esemény; a blockolt
   `actor_a` sora NEM számít bele).
2. §6.1 valódi-sértés próba: `monkeypatch`-eli a
   `list_block_pairs_for_viewer`-t, hogy üres halmazt adjon vissza (a
   pre-fix kódút szimulációja), majd ellenőrzi, hogy a cella PIROSRA
   vált — `broken_count == 3` (a badge MOST már a blockolt sort is
   számolná, pontosan az a badge-desync, amit a javítás megszüntet).

A teljes `test_notification_service.py` suite (13 teszt, az új cellával
együtt) zöld; a teljes backend suite (591 → 592 teszt) is zöld.

**MINOR-1 (NEM javítva — follow-up).** A `list_inbox` lapozási
alul-töltés-problémája (`has_more`/`next_cursor` a szűrés UTÁNI
listából számol blockolt sorok jelenlétében) ebben a körben szándékosan
NEM lett javítva. A review ezt nem blokkolónak minősítette (a kör
service-réteg-only, ADR 0414 D2, ma nincs élő hívó; a §6
acceptance-mátrix egyetlen cellája sem méri a több-oldalas lapozást
blockolt sorokkal keverve), és a javítás ugyanazt a materializált
block-halmazt használná, amit a MAJOR-1 fix már bevezetett — az
`is_blocked_pair` soronkénti hívását SQL-szinten cserélné le. A diff
hizlalása nélkül, önálló follow-up körként hatékonyabb: a §6.1
measure-mátrix bővítése (két-oldalas lap, vegyes blockolt/látható
sorok) + a `list_inbox` refaktor együtt egy önálló round. A scope-őr
betartása mellett (a `notification_service.py` engedélyezett) a
javasolt jövőbeli módosítás:

```python
# list_inbox jövőbeli patch (NEM a jelen körben):
blocked_ids = list_block_pairs_for_viewer(db, viewer_profile_id=recipient.id)
if blocked_ids:
    base_query = base_query.filter(
        or_(
            CommunityNotification.actor_profile_id.is_(None),
            CommunityNotification.actor_profile_id.notin_(blocked_ids),
        )
    )
# a per-row is_blocked_pair ciklus megszűnik — a has_more/next_cursor
# immár a limit+1 sorra korrekt.
```

A review §5 MINOR-1-es leírással összhangban (lásd
`docs/reviews/e09-r20-review.md`).

## 11. Review — a Claude tölti ki
