# ADR 0414 — Notification inbox és push abstraction

- **Státusz:** Elfogadva (E09-R20 pre-flight, 2026-08-23)
- **Kör:** E09-R20 — Notification inbox és push abstraction
- **Implementer motor:** MiniMax M3 — az ADR-t az orchesztrátor (Claude Sonnet 5)
  írta a pre-flightban (ADR 0055).
- **Epic:** Chapter 10 — Epic 9 (Community Platform), Kör 20 (a 32 kör közül a huszadik)
- **Kontext-ADR-ek:** [0402](0402-block-mute-and-safety-relationships.md)
  (Kör 8 — `query_filters.py::is_blocked_pair`, csak-hívás tilos zóna),
  [0399](0399-flutter-community-domain-and-public-api.md) (Kör 5 —
  `CommunityNotificationRepository`/`CommunityNotificationItem`/
  `CommunityNotificationKind` MÁR él a `domain/**`-ban, tilos zóna),
  [0407](0407-comment-reply-and-mention.md) (Kör 16 — D7: a Kör 15/16
  service-réteg-only precedens, HTTP router nélkül), [0396](0396-community-backend-module-and-first-migration.md)
  (Kör 2 — `build_community_router` csak `profile.router`-t köt be, és MAGA
  a factory sincs élesben `create_app()`-ba kötve — a teljes Community
  backend, R02–R19, kizárólag `backend/tests/community/conftest.py` önálló
  test-appján keresztül él).
- **Sorszám-jegyzet:** a pipeline-prompt E09-R20-hoz `0409`-et adott előre
  kiosztott ADR-ként, de a `.pipeline/inflight/adr/0409` marker MÁR foglalt
  (`round=E13-R06`, 2026-08-2x) — az a kör végül `ADR 0274`-et használta, a
  `0409` marker stale/orphaned maradt, de a `tools/round-slots.py` atomi
  foglalása ettől függetlenül a KÖVETKEZŐ szabad számot adja, nem 0409-et
  újra. A `tools/round-slots.py reserve-adr --round E09-R20` friss számot
  adott: **`0414`**. A stale `0409` marker törlése nem ennek a körnek a
  hatásköre (megosztott `.pipeline/inflight` állapot); a kör ADR-je innentől
  0414.
- **Visszakeresés (ADR 0312, pre-flight §4.9):** `node
  tools/knowledge-rag.mjs --corpus lessons,halts,adr --top 5 "notification
  inbox push gateway payload redaction"` → **ADR 0372** (gate-edit policy,
  nem közvetlenül releváns), **E09-R18** (média-upload, adjacent privacy
  mintázat). `node tools/knowledge-rag.mjs --corpus lessons,halts --top 5
  "unread count race condition mark-read aggregation"` → **L421**
  (`threading.Thread`-alapú konkurens-írás próba szinkronizáció NÉLKÜL NEM
  determinisztikus — a `Barrier`-t a PONTOS SQL-döntési pontnál kell tenni,
  nem a szál-indítás előtt; 10 futtatásból 7 piros/3 zöld szinkronizáció
  nélkül) — **közvetlenül alkalmazandó az A3 valódi-sértés próbájára**, lásd
  D4. `node tools/knowledge-rag.mjs --top 5 "notification inbox push
  gateway community_notifications.py alembic"` → a MÁR élő
  `notification_repository.dart`/`notification_item.dart` (Kör 5, ADR 0399
  §1) — a kontextus 2. pontja.

## Kontextus

**Mért 2026-08-23-én, a pre-flightban:**

1. `lib/features/community/domain/repositories/notification_repository.dart`
   és `domain/entities/notification_item.dart` **MÁR léteznek** (Kör 5, ADR
   0399 §1) — `CommunityNotificationRepository` (inboxPage/markRead/
   markAllReadUpTo/preferences/updatePreference) és
   `CommunityNotificationItem`/`CommunityNotificationKind` (tíz rögzített
   wire-érték: `follow_request`, `follow_accepted`, `reaction_summary`,
   `comment`, `mention`, `challenge_invite`, `challenge_completed`,
   `club_invite`, `moderation_decision`, `security_alert`). A `domain/**` a
   Kör 5 óta tilos zóna — a brief `community_notifications_screen.dart`-ja
   ez ELLEN a MÁR rögzített kontraktus ellen épül, nem újat talál ki.
   Konkrét kontraktus-tények: `inboxPage` cursor-lapozott
   (`CommunityPage<CommunityNotificationItem>`), `markRead`/
   `markAllReadUpTo` idempotencia-kulcsot vár, `preferences()`/
   `updatePreference` a §5.3 kategória-preferencia UI-t szolgálja.
2. `grep -rln "CommunityNotificationRepository" lib/` **egyetlen** találat
   (maga az interfész-fájl) — nincs data-layer implementáció, nincs
   provider, nincs controller. A Kör 14 (`feed_controller.dart`) és Kör 16
   (`comment_controller.dart`) precedense szerint ez a NORMÁL állapot egy
   UI-kört megelőzően: a controller a domain-interfészre injektálva épül, a
   widget-teszt fake/preview implementációval override-olja, a valódi
   HTTP-kötésű data-layer egy KÉSŐBBI kör dolga (D2).
3. `backend/app/community/__init__.py::build_community_router` **csak** a
   `routers/profile.py`-t köti be, ÉS ez a factory saját docstringje szerint
   sincs élesben `create_app()`-ba kötve — "Wiring the router into
   create_app() ... is a future round's job". `grep -rn "include_router"
   backend/app/` megerősíti: `main.py` NEM regisztrál semmilyen Community
   routert. A teljes Epic-9 backend (R02–R19) kizárólag
   `backend/tests/community/conftest.py` önálló test-appján keresztül
   tesztelt.
4. `grep -rln "from.*reaction_service import\|from.*comment_service import"
   backend/ --include=*.py` (tesztkönyvtárak nélkül) **0 találat** — sem
   `reaction_service.py`, sem `comment_service.py` funkcióit nem hívja
   ÉLŐ router-kód, KIZÁRÓLAG a `backend/tests/community/test_reaction_
   service.py`/`test_comment_service.py`. `follow_service.py`-t a
   `social_graph.py` router MEGHÍVJA (`from ..services.follow_service
   import`), de a `follow()`/`accept_follow_request()` függvényeknek NINCS
   `on_invalidate`-szerű esemény-callback paraméterük (szemben a
   `reaction_service.set_reaction`/`comment_service.create_comment`
   `Callable[[XInvalidationEvent], None] | None` szignatúrájával) — a
   follow-eseményhez ma nincs kész integrációs seam SEM.
5. A brief tilos zónája a három service-fájlt (`reaction_service.py`,
   `comment_service.py`, `follow_service.py`) "csak HÍVÁS az esemény végén"
   megjegyzéssel zárja ki — de EGYIK sincs olyan élő hívási láncban
   (router), amit ez a kör érhetne. A `routers/social_graph.py` (az egyetlen
   ÉLŐ router-hívó a hármasból) NINCS ezen kör `allowed_paths`-án.
6. `backend/app/community/policies/query_filters.py::is_blocked_pair(db, *,
   profile_id_a, profile_id_b) -> bool` (a Kör 8 block-predikátum) az A4
   ("Blocked actor eseménye rejtett az inboxban") mérési eszköze — importon
   keresztül hívható, a fájl NEM módosítható (tilos zóna változatlan).
7. `test/ui/ui_inventory_test.dart` `hasLength(73)` — a MÁR kétszer (E09-R14
   F1, E09-R16 §0.0.1) megismételt "új `*_screen.dart` → screen-count drift"
   hibaosztály HARMADSZORI megelőzése: ez a brief PROAKTÍVAN felveszi az
   `allowed_paths`-ba, review-vezérelt javító kör NÉLKÜL (D5).
8. Brief-lint S7: az `allowed_paths` egyik útvonala sem tartalmazza a router
   `high_risk_path_fragments` listájának egyik szavát sem szó szerint
   (`privacy`, `secret`, stb.), ezért a `risk = "high"` indoklása explicit
   sor kell — lásd D6.

## Döntés

### D1 — A push payload kizárólag notification ID + type + route-safe entity ID — SOSEM tartalom

A `push_gateway.py` interfész payload-típusa (`PushPayload` vagy ezzel
ekvivalens dataclass) legfeljebb négy mezőt hordoz: `notification_id`,
`type` (a `CommunityNotificationKind` wire-értékei közül), `route_entity_id`
(opcionális), és egy lokalizációs KULCS (nem szöveg). **NEM elfogadható
gyengítés:** a teljes komment-szöveg, a reagáló felhasználó neve vagy bármely
szerver-oldali "szebb preview" a payloadban — ez az SDD §17.2 invariáns
közvetlen megsértése, és a push-szolgáltatón (egy 3rd-party rendszeren)
keresztül szivárogna. A §6.1 valódi-sértés próba (`commentBody` mező
hozzáadása → A1 piros → visszaállítás) ezt a döntést közvetlenül méri.

### D2 — Ez a kör service-réteg-only, HTTP router NÉLKÜL — a Kör 15/16 precedens (ADR 0407 D7) folytatása

A 3–4. kontextus-pont mérése szerint SEM `reaction_service.py`, SEM
`comment_service.py` nincs router mögé kötve élesben, és a `follow_service.py`
router-hívója (`social_graph.py`) nincs ezen kör `allowed_paths`-án. A
`notification_service.py` ezért ebben a körben **kizárólag közvetlenül hívott
funkciókészlet** — `backend/tests/community/test_notification_service.py`
a §6 minden backend-cellát (A1–A5, A7) közvetlen függvényhívással mér, HTTP
réteg nélkül, ugyanúgy, ahogy a `test_comment_service.py`/
`test_reaction_service.py` teszi. **NEM elfogadható gyengítés:** egy ÚJ
`routers/notifications.py` hozzáadása ebben a körben — nincs az
`allowed_paths`-on, és a `backend/app/community/__init__.py::
build_community_router` (3. kontextus-pont) mintája szerint egy router
hozzáadása önmagában úgysem kötné be élesben a `create_app()`-ot.
Az esemény-generáló hívás (a `reaction_service.set_reaction`/
`comment_service.create_comment`/`follow_service.follow` sikeres ága UTÁN
egy `notification_service.create(...)` hívás) egy KÉSŐBBI kör dolga, amikor
ezek a service-ek maguk is router mögé kerülnek — ez konzisztens azzal, hogy
a brief tilos zónája MA úgyis kizárja mindhárom service-fájl szerkesztését.

### D3 — A reaction-burst aggregáció dokumentált időablaka: 15 perc, csúszó, recipient+entity kulcsú

A §17.4 "5 ember reagált" mintát egy `(recipient_id, entity_id, entity_type)`
kulcsú, 15 perces csúszó ablak valósítja meg: az első reakció létrehoz egy
`reaction_summary` notification-itemet `aggregate_count=1`-gyel; minden
következő reakció UGYANARRA az entitásra UGYANANNAK a recipientnek, amíg az
első item `created_at`-je + 15 perc még nem telt le, NEM hoz létre új sort,
hanem az `aggregate_count`-ot növeli és az item `updated_at`/`created_at`-jét
frissíti (az inbox rendezése "legutóbbi aktivitás" szerint, nem "első
aktivitás" szerint). A 15 perc lejárta UTÁNI reakció ÚJ item-et nyit. **NEM
elfogadható gyengítés:** entity-kulcs nélküli, csak recipient-szintű
aggregáció — az összemosná a két különböző poszt reakcióit egyetlen
összegző mondatba.

### D4 — Az unread-count race valódi-sértés próbája: `threading.Barrier` a PONTOS SQL update-nél, NEM a szál-indítás előtt

L421 (E09-R07, 10/10 mérés: szinkronizáció nélkül 7 piros/3 zöld) közvetlen
alkalmazása: az A3 konkurens `test_mark_read` próba két `threading.Thread`-et
indít, de a `threading.Barrier(2)` a `mark_read`/`mark_all_read_up_to`
implementáció **BELSEJÉBEN**, közvetlenül az unread-count UPDATE (vagy a
read-state módosító UPDATE) elé injektálva vár be — nem a szál-indítás előtt.
Ez determinisztikusan kikényszeríti, hogy mindkét szál a "olvasás → döntés →
írás" ablakban legyen egyszerre, amikor a race egyáltalán megfigyelhető. A
teszt a service-funkciónak egy opcionális, teszt-only szinkronizációs hookot
ad át (pl. `_before_commit: Callable[[], None] | None = None`), ugyanúgy,
ahogy a `reaction_service`/`comment_service` `on_invalidate` callballt kapnak
— ez a MÁR bevett mintát követi, nem új mechanizmust vezet be. **NEM
elfogadható gyengítés:** a race-tesztet szinkron (nem-threaded) hívásokkal
"szimulálni" — az L421 tanulsága szerint ez épp azt az ablakot hagyja ki,
ahol a hiba egyáltalán jelentkezhet.

### D5 — Proaktív `allowed_paths` bővítés Flutter-oldalon: controller + l10n + ui_inventory (a Kör 14/16 drift-osztály megelőzése)

A brief eredeti `allowed_paths`-a csak a `community_notifications_screen.dart`-ot
sorolta fel — a Kör 14 (F1 javító kör) és Kör 16 (§0.0.1 javító kör)
UGYANEZT a hibaosztályt kétszer egymás után futtatta végig review-n:
ÚJ `*_screen.dart` → `test/ui/ui_inventory_test.dart` hardcode-olt
számlálója elavul → MAJOR lelet → külön javító kör. Ez a kör ELŐRE felveszi:

- `lib/features/community/application/controllers/notification_controller.dart`
  (ÚJ — a Kör 14 `feed_controller.dart`/Kör 16 `comment_controller.dart`
  Riverpod `Notifier`-mintája, a domain-interfészre injektálva, widget-teszt
  fake-kel override-olva; a valódi HTTP-kötésű data-layer későbbi kör dolga,
  2. kontextus-pont)
- `lib/l10n/features/community_en.arb` / `community_hu.arb` (az inbox
  cím/leírás lokalizációs kulcsok és a preferencia/quiet-hours UI szövegek)
- `lib/l10n/app_en.arb` / `app_hu.arb` (a `tool/gen_l10n_segments.dart
  --write` GENERÁLT, de git-be commitolt aggregátuma — mechanikus
  velejáró, nem kézzel szerkesztett tartalom)
- `test/ui/ui_inventory_test.dart` (KIZÁRÓLAG a `hasLength(73)` →
  `hasLength(74)` egysoros bumpolása)

**NEM elfogadható gyengítés:** a screen l10n-mentesen, hardcode-olt angol
szöveggel leszállítva "hogy a lint ne akadjon ki" — pontosan ez volt a Kör
14/16 MAJOR leletének tartalma.

### D6 — Kockázat = high, indoklás

A brief `risk = "high"` besorolása annak ellenére indokolt, hogy az
`allowed_paths` egyik útvonala sem tartalmaz szó szerinti
`high_risk_path_fragments` egyezést: a kör egy **privacy-érzékeny adatszivárgási
felületet** (push-payload redakció, D1) ÉS egy **keresztfelhasználós
láthatósági szabályt** (blocked actor inbox-rejtés, A4, `is_blocked_pair`
hívás) implementál. Egy hibás payload-redakció vagy egy hibás block-szűrés
mindkettő valódi adatvédelmi incidens — ugyanaz az indoklási osztály, mint a
Kör 18 média-feltöltés (E09-R18 ADR 0410) vagy a Kör 19 privacy/moderation
kör (E09-R19), amelyek szintén `risk = "high"`-ot kaptak tartalom-érzékenység
miatt, útvonal-fragment egyezés nélkül.

## Elutasított alternatívák

- **HTTP router hozzáadása ebben a körben** (`routers/notifications.py`).
  Elvetve: nincs az `allowed_paths`-on, és a 3. kontextus-pont szerint egy
  router önmagában úgysem kötné be élesben a Community modult — a Kör 2 óta
  fennálló, dokumentált rés (D2).
- **A `reaction_service.py`/`comment_service.py`/`follow_service.py`
  szerkesztése egy közvetlen `notification_service.create(...)` hívás
  beszúrásával.** Elvetve: egyik sincs élő router mögött (4. kontextus-pont),
  a brief tilos zónája ma is kizárja őket — a valódi integráció egy
  későbbi, e három fájlt saját `allowed_paths`-ban listázó kör dolga (D2).
- **A race-tesztet szál-indítás előtti `Barrier`-rel vagy szinkron hívással
  írni.** Elvetve: L421 mérten 7/10 arányban NEM reprodukálja a race-t (D4).
- **Recipient-only aggregáció-kulcs (entity nélkül).** Elvetve: két
  különböző poszt reakcióit összemosná egyetlen "5-en reagáltak" mondatba,
  ami félrevezető route-linket eredményezne (D3).
- **A screen l10n nélkül, a Kör 14/16 javító kör UTÁN pótolva.** Elvetve:
  MÉRT, kétszer megismételt hibaosztály — a pre-flight a legolcsóbb hely a
  megelőzésre (D5).

## Következmények

- A notification-eseményeket ebben a körben KIZÁRÓLAG a
  `test_notification_service.py` hívja közvetlenül — nincs élő "egy komment
  létrehozása automatikusan generál egy notification-itemet" viselkedés
  addig, amíg egy jövőbeli kör a `reaction_service.py`/`comment_service.py`/
  `follow_service.py` sikeres ágát a `notification_service.create(...)`
  hívással köti össze (D2 visszavonási feltétele).
- A Flutter `notification_controller.dart` a domain-interfészre épül, valódi
  HTTP data-layer nélkül — ugyanaz a dokumentált rés, mint a
  `feed_controller.dart`/`comment_controller.dart` (2. kontextus-pont).
- A `_before_commit` teszt-only hook (D4) a `notification_service.py`
  publikus szignatúráján marad látható, amíg egy jövőbeli refaktor
  eltávolítja vagy általánosítja — ugyanaz a minta, mint az `on_invalidate`
  a `reaction_service`/`comment_service`-ben.

## A visszavonás feltétele

Felülvizsgálandó, ha egy jövőbeli kör (a) HTTP routert köt a Community
modul elé és élesben regisztrálja a `create_app()`-ban (D2 előfeltétele), és
(b) a `reaction_service.py`/`comment_service.py`/`follow_service.py`
sikeres ágait ténylegesen összeköti a `notification_service.create(...)`
hívással — ekkor ezek a fájlok saját `allowed_paths`-sort kapnak, és a "csak
HÍVÁS az esemény végén" tilos-zóna megjegyzés első alkalommal ténylegesen
gyakorolhatóvá válik.
