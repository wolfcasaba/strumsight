# Review-jelentés — E09-R20 (Notification inbox és push abstraction)

- **Reviewer:** Claude Sonnet 5 (orchesztrátor), READ-ONLY
- **Branch:** `minimax/e09-r20-notification-inbox-and-push-abstraction`
- **Review HEAD:** `24f40314` (implementer saját commitjai, alap `4e611d1e` — a pre-flight
  ADR 0414 + brief-revízió commitja)
- **ADR:** [0414](../adr/0414-notification-inbox-and-push-abstraction.md) · **Risk:** high
- **Verdikt:** **CHANGES REQUESTED** — 1 MAJOR (a dedikált security review zárta ki, §7),
  0 BLOCKER, 1 MINOR follow-up (nem blokkoló, §5)

## 1. Jelzés + handoff

`.codex-round-status` a munkapéldányban `status=done`, `dirty_files=1` —
kivizsgálva: a jelzés pillanatában mért érték, a `git status --short` a
végleges HEAD-en (`24f40314`) TISZTA (nincs untracked/uncommitted fájl). A
brief §10 Implementation handoff kritériumonként (A1–A7 + A6 Flutter)
alátámasztott, futtatott parancsokra hivatkozva, nem csonkolt bemondás.

## 2. Gate-újrafuttatás (izolált klón, saját kézzel)

Közvetlenül GitHubról (`origin`) klónozva, `/tmp/review-e09-r20`:

```
tools/round-gate.sh test/features/community/presentation/community_notifications_test.dart test/ui/ui_inventory_test.dart
```
```
format                                                     zöld
analyze                                                    zöld
test test/features/community/presentation/community_notifications_test.dart zöld
test test/ui/ui_inventory_test.dart                        zöld
architecture                                               zöld
secrets                                                    zöld
l10n                                                       zöld
backend ruff format                                        zöld
backend ruff check                                         zöld
backend pytest                                             zöld
MINDEN GATE ZÖLD.
```
(Flutter: 4/4 új widget-teszt zöld — A6 preference toggle ×2, markRead
controller-path, empty-state. Backend: teljes suite 591 teszt, 0 hiba, a
12 új notification-teszttel együtt.)

## 3. Scope-audit

```
tools/scope-audit.py --repo /tmp/review-e09-r20 --brief docs/rounds/e09-r20-notification-inbox-and-push-abstraction.md --base 4e611d1e
```
```
Legacy scope audit OK (4e611d1e722d..24f40314510b, 14 changed path(s), 0 generated/ignored)
```

Mind a 14 megváltozott fájl az `allowed_paths` §0.0 D5-bővített listáján
(a §0.0 D5 négy proaktív fájlja — `notification_controller.dart`,
`community_{en,hu}.arb`, `app_{en,hu}.arb`, `ui_inventory_test.dart` — mind
felhasználva, pontosan a tervezett minimális diffel). **Külön ellenőrizve
(ADR 0414 D2 kikényszerítése):** `git diff --stat 4e611d1e..24f40314` NEM
tartalmazza a `reaction_service.py`, `comment_service.py`,
`follow_service.py`, `backend/app/community/routers/**` egyikét sem — a
service-réteg-only szerződés tartott.

## 4. Acceptance criteria — tételesen

| # | Kritérium | Bizonyíték | Verdikt |
|---|---|---|---|
| A1 | Push payload nem tartalmaz érzékeny teljes szöveget | `PushPayload` zárt `@dataclass(frozen=True)` (6 mező), `__post_init__` allowlist-validáció + `_assert_payload_is_minimal` struktúrális őr; **valódi-sértés próba** (`test_a1_real_violation_probe_adds_field_to_payload`) egy `_LeakyPayload(commentBody: str)` throwaway subclasst épít, `AssertionError` PIROSRA vált, a production dataclass változatlan marad zöld | PASS |
| A2 | Reaction-burst aggregált, nem N külön push | `test_a2_...`: 5 egymást követő reakció → 1 sor, `aggregate_count=5`, pontosan 1 `gateway.send`; külön teszt a 15 perces ablak lejártára (16 perc → 2 sor, 2 push) | PASS |
| A3 | Read state helyes és versenyhelyzetben is konzisztens | `threading.Barrier(2)` a `_before_commit` seamnél, a döntő UPDATE ELŐTT (L421 minta) — mind `mark_read`, mind `mark_all_read_up_to` saját threaded teszttel; végállapot `unread_count == 0` minden sorra | PASS |
| A4 | Blocked actor eseménye rejtett az inboxban | `list_inbox` minden sorra `is_blocked_pair`-t hív (import, nem módosítás); teszt: blockolt actor_a + látható actor_b + system(NULL actor) → inbox 2 sort mutat, actor_a kizárva | PASS (lásd 5. §, MINOR-1 lapozási él) |
| A5 | Törölt entitásra mutató notification kezelt | `get_related_content_id`: soft-delete után a sor MARAD az inboxban, a deep-link `None`-ra vált | PASS |
| A6 | Kategóriánként kikapcsolható push | 4 widget-teszt: `updatePreference` wire-string + idempotency-key, 10 wire-kind render, `markRead` id-passthrough, empty-state | PASS |
| A7 | Dedup-kulcs megakadályozza a duplikált notification-itemet | UNIQUE `(recipient, dedup_key)`; retry → `IntegrityError` elkapva, meglévő sor visszaadva, MÁSODIK push NEM tűz; **valódi-sértés próba** (`test_a7_real_violation_probe_drops_unique_constraint`) a UNIQUE-ot eltávolítva 2 sort mér, majd visszaállítja a sémát | PASS |

## 5. MINOR-1 — `list_inbox` lapozás alul-tölthet blockolt sorok miatt

**Mért tény.** `list_inbox` (`notification_service.py` ~660–751. sor) a
`limit + 1` sort lekérdezi, MAJD Python-oldalon szűri ki a blockolt actorú
sorokat (`is_blocked_pair`), és a `has_more`/`next_cursor` a SZŰRÉS UTÁNI
`filtered` listából számol (`has_more = len(filtered) > limit`). Ha a
lekérdezett `limit+1` ablakban több blockolt-actorú sor van, a végeredmény
lap **kevesebb, mint `limit`** elemet ad VISSZA úgy, hogy `has_more = False`
— miközben a táblában, a lekérdezett ablakon TÚL, lehetnek további látható
notification-ök. Ez korai lapozás-megszakadást okoz (a kliens nem kap
"Továbbiak betöltése" jelet, pedig lenne mit betölteni).

**Miért nem BLOCKER/MAJOR.** (1) A §6 acceptance-mátrix egyetlen cellája sem
méri a több-oldalas lapozást blockolt sorokkal keverve — az A4 teszt egy
egyoldalas, kis mintán fut. (2) A kör service-réteg-only (ADR 0414 D2): nincs
élő HTTP-végpont, tehát ma senki nem tapasztalhatja. (3) A kódbázis MEGLÉVŐ
lapozó implementációi (`follow_service.list_followers`,
`comment_service.list_comments`, `block_service.list_blocked`) egyike sem
végez utólagos szűrést a `limit+1` lekérdezés UTÁN — a `list_inbox` az ELSŐ
hely, ahol ez a minta megjelenik, tehát nincs megtört, korábban jó precedens.

**Javasolt irány** (nem kész patch): vagy egy over-fetch-és-újra-lekérdezés
ciklus (amíg a szűrt lap betelik vagy a forrás kimerül), vagy a blockolt
profil-id-halmaz előzetes lekérdezése (`list_block_pairs_for_viewer`, MÁR
létezik a Kör 8 `query_filters.py`-ban) és annak a WHERE-klauzulába
építése SQL-szinten — az utóbbi egy lépésben oldaná meg a lapozási
korrektséget ÉS a jelenlegi soronkénti `is_blocked_pair`-hívás N+1-jét is.
Egy jövőbeli kör dolga, amikor a `list_inbox` élő HTTP mögé kerül.

## 6. Architektúra + termékhatárok

- `domain/**` (Kör 5, ADR 0399, tilos zóna) **változatlan** — a controller a
  MEGLÉVŐ `CommunityNotificationRepository`/`CommunityNotificationItem`
  kontraktusra épül, nem talál ki újat (`grep -rln
  "CommunityNotificationRepository" lib/` → 2 találat: az interfész + az ÚJ
  controller, mindkettő a domain-t IMPORTÁLJA, nem módosítja).
- `communityNotificationRepositoryProvider` alapértelmezetten
  `UnimplementedError`-t dob — helyesen, a Kör 14/16 precedens szerint (a
  valódi HTTP data-layer egy KÉSŐBBI kör dolga), a widget-teszt fake-kel
  override-olja.
- `tool/check_architecture.dart` zöld (12 allowlistelt eltérés, nem nőtt).
- Erőforrás-lifecycle: nincs mic/camera/network-streaming ezen a köri
  felületen, nem releváns.

## 7. Kockázat = high — a dedikált security review

A brief `risk = "high"` (ADR 0414 D6 indoklás) miatt a `security-reviewer`
ágens **KÖTELEZŐ, külön** review-t futtatott, izolált `/tmp` klónban,
read-only. Az eredmény: lásd
[`docs/reviews/e09-r20-security.md`](e09-r20-security.md) — **1 MAJOR-t**
talált, MÉRVE (reprodukált, a fát tisztán hagyva):

**MAJOR-1 — `get_unread_count` NEM alkalmazza az A4 block-szűrőt.**
`notification_service.py:754–776` a `list_inbox`-tól (713–740. sor) eltérően
NEM hívja az `is_blocked_pair`-t — egy blockolt actor eseménye az inboxból
eltűnik (`list_inbox` helyesen 0 sort ad), de az unread-badge MÉGIS
számolja (`get_unread_count` 1-et ad). A brief §10 handoffja az A4-et PASS-nak
jelentette a `list_inbox`-only teszt alapján — a count-útvonalra NINCS mérő
cella. Ez ugyanaz az A4-invariáns, csak egy testvér-olvasási úton
megsértve — badge-desync és alacsony-fokú "egy blockolt személy tett
valamit" szivárgás. A biztonsági review "latens"-nek minősíti (a kör
service-réteg-only, ADR 0414 D2, ma nincs élő hívó), de a kódban ÍRVA van, és
az A4 PASS-állítás túlterjeszkedik a ténylegesen mért felületen — ezért MAJOR,
nem NOTE.

A biztonsági review 3 további NOTE-ot rögzít (A1 kulcs-vs-érték redakciós rés
egy jövőbeli hívóra nézve, A5 csak `post`-ra fedett, `set_preference`
kategória fail-open) — egyik sem blokkoló ebben a körben, mindegyik
dokumentált forward-guard a security review §-ában.

## 8. Összegzés

**CHANGES REQUESTED.** 1 MAJOR (§7, `get_unread_count` A4-rés — a security
review zárta ki, javító kör szükséges). 1 MINOR (§5, lapozási alul-töltés
blockolt sorokkal keveredve) — a javító körben javítható, ha nem hizlalja a
diffet, különben follow-up. A javító kör leletlistája:

1. **MAJOR-1 (kötelező):** `get_unread_count` kapjon `is_blocked_pair`
   (vagy materializált block-halmaz) szűrést, UGYANAZZAL a predikátummal,
   mint a `list_inbox`. Új mérce-cella: `unread_count == visible_unread` egy
   blockolt actor eseménye mellett (valódi-sértés próba: a szűrés
   ideiglenes eltávolítása → a cella PIROS → visszaállítás).
2. **MINOR-1 (ajánlott, ha belefér):** `list_inbox` lapozás — a
   `has_more`/`next_cursor` a szűrés UTÁNI listából számol, ami blockolt
   sorok jelenlétében korai lapozás-megszakadást okozhat. Javasolt irány:
   a Kör 8 `list_block_pairs_for_viewer` előzetes lekérdezése és
   WHERE-klauzulába építése (egyszerre oldja a lapozást és az N+1-et).
