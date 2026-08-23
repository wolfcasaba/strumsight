# ADR 0415 — Community challenge és invite lifecycle

- **Státusz:** Elfogadva (E09-R21 pre-flight, 2026-08-23)
- **Kör:** E09-R21 — Community challenge és invite lifecycle
- **Implementer motor:** MiniMax M3 — az ADR-t az orchesztrátor (Claude Sonnet 5)
  írta a pre-flightban (ADR 0055).
- **Epic:** Chapter 10 — Epic 9 (Community Platform), Kör 21 (a 32 kör közül a huszonegyedik)
- **Kontext-ADR-ek:** [0399](0399-flutter-community-domain-and-public-api.md)
  (Kör 5 — `CommunityChallengeRepository`/`CommunityChallengeDefinition`/
  `ChallengeInviteState`/`ChallengeType` MÁR élnek a `domain/**`-ban, tilos
  zóna, csak-hívás), [0402](0402-block-mute-and-safety-relationships.md)
  (Kör 8 — `query_filters.py::is_blocked_pair`, a §"D3 horog" explicit erre
  a körre bízta a döntést), [0414](0414-notification-inbox-and-push-abstraction.md)
  (Kör 20 — idempotency/`IntegrityError`-újraolvasás minta, `RateLimiter`
  process-local primitívum precedens).
- **Sorszám-jegyzet:** a pipeline-prompt E09-R21-hez `0410`-et adott előre
  kiosztott ADR-ként, de ez a szám MÁR foglalt — `docs/adr/0410-media-upload-contract-and-object-store.md`
  (E09-R18, elfogadva 2026-08-23). A `tools/round-slots.py reserve-adr --round E09-R21`
  friss számot adott: **`0415`**.
- **Visszakeresés (ADR 0312, pre-flight §4.9):**
  `node tools/knowledge-rag.mjs --corpus lessons,halts,adr --top 5 "challenge
  invite lifecycle state machine idempotency block eligibility"` →
  **ADR 0402 §"A visszavonás feltétele"** — a block-tranzakció §D3 horga
  EXPLICIT módon erre a körre bízza a döntést, hogy `block_service.py`-t
  bővíti-e vagy önálló listenert épít (lásd D3 lent) — **közvetlenül
  alkalmazandó**. `node tools/knowledge-rag.mjs --corpus lessons,halts --top 5
  "server-side expiry timezone independent race condition accept cancel
  concurrent"` → **L421** (`threading.Thread`-alapú konkurens próba
  szinkronizáció NÉLKÜL nem determinisztikus, E09-R07, 10 futásból 7 piros
  szinkronizáció nélkül; a `Barrier`-t a PONTOS SQL-döntési pontnál kell
  elhelyezni) — **közvetlenül alkalmazandó az A5 valódi-sértés próbájára**,
  lásd D5. `node tools/knowledge-rag.mjs --top 5 "challenge invite lifecycle
  community_challenges backend/app/community"` → a MÁR élő
  `community_challenge.dart`/`challenge_repository.dart` (Kör 5, ADR 0399) —
  lásd D1.

## Kontextus

**Mért 2026-08-23-án, a pre-flightban (ez a §0.0 hordozza a teljes
tényellenőrzést, a brief eredeti szövege felülíródik):**

1. **A brief nyitó figyelmeztetése téves célra mutat.** `grep -rn
   "ChallengeV2" . --include="*.py" --include="*.dart"` → **0 találat** a
   teljes repóban, docs/adr és docs/sdd alatt is. A brief címben és a Kör 19
   ADR-jének fájlnevében ("0387-challenge-v2-legacy-wrap-and-single-reward-instance.md")
   szereplő "Challenge V2" egy **egyjátékos, eszközön futó napi
   gamifikációs kihívás-generátor** neve
   (`lib/features/gamification/domain/quests/challenge_definition.dart`:
   `enum DailyChallengeType { strumPattern, chordChange, rhythm,
   songSection, timing }`, `sealed class DailyChallengeDefinition`) —
   tartalom-referenciákkal (`fromChordId`, `songId/sectionId`, `targetBpm`),
   NEM egy szociális/versengő szerződés. A brief eredeti "Community csak
   kompatibilis Gamification challenge-definíciót fogadhat el" cellája
   **elérhetetlen cél-státusz** volt (§1 pre-flight szabály 1. pontja): nincs
   olyan input, ami ezt a kompatibilitást értelmessé tenné, mert a két
   domain vokabuláriuma diszjunkt.
2. **A TÉNYLEGES kompatibilitási felület MÁR létezik — a Community saját
   E09-R05 domain-kontraktusa, nem a gamifikáció.**
   `lib/features/community/domain/entities/community_challenge.dart` (Kör 5,
   ADR 0399, `git log` szerint `79865233`, PR #414) definiálja:
   - `enum ChallengeInviteState { draft, sent, accepted, declined, expired,
     cancelled, active, completed, forfeited }` — **byte-azonos** a brief
     §5.1 állapotgépével (`draft → sent → accepted | declined | expired |
     cancelled`, majd `accepted → active → completed | forfeited |
     expired`).
   - `enum ChallengeType { friends, club, dailyCommunity, periodicGlobal,
     personalBest }` — explicit `wireValue` sztringekkel.
   - `final class CommunityChallengeDefinition` (id, version, type, metric,
     difficulty, startsAt, endsAt, authorId, clubId — a `clubId` nullable,
     csak `ChallengeType.club`-hoz).
   - `final class CommunityChallengeParticipantState` (challengeId,
     participantId, inviteState, bestMetricValue — az utóbbi Kör 22 dolga,
     ebben a körben mindig `null` marad).
   `lib/features/community/domain/repositories/challenge_repository.dart`
   definiálja az `abstract interface class CommunityChallengeRepository`-t 9
   metódussal (`listChallenges`, `fetchDefinition`, `fetchMyParticipation`,
   `invite`, `acceptInvite`, `declineInvite`, `cancelInvite`, `submitResult`,
   `leaderboard`). Mindkét fájl **nulla importot** visz a
   `gamification/`-ból (`grep import` ellenőrizve), és mindkettő exportálva
   van a `lib/features/community/public.dart`-ban (34., 46. sor). **Nincs
   még implementáció** — nincs `data/repositories/challenge_repository_impl.dart`,
   nincs provider-bekötés, nincs backend model/service/router.
3. **A block-ellenőrzés meglévő, write-side mintája újrahasználható.**
   `backend/app/community/policies/query_filters.py::is_blocked_pair(db, *,
   profile_id_a, profile_id_b)` (44. sor) — szimmetrikus (bármelyik irányú)
   block-predikátum, self-pair mindig `False`. Valódi hívási lánc:
   `post_service.py` (252., 440. sor) és `comment_service.py` (362. sor) a
   WRITE-oldali (létrehozás előtti) kapuként hívja — ez a Kör 21-nek releváns
   minta, NEM a `notification_service.py::list_inbox` LIST-oldali
   `list_block_pairs_for_viewer` mintája (ami egy egész oldalt szűr egy
   lekérdezéssel, olvasáshoz optimalizálva).
4. **ADR 0402 §D3 horog: a döntés kifejezetten erre a körre van bízva.**
   "Szintén felülvizsgálandó, ha a Kör 21 challenge-invite implementációja
   azt találja, hogy a block-tranzakciónak NEM elég a §"D3 horog" — ekkor a
   Kör 21 brief-je dönti el, hogy `block_service.py`-t bővíti-e, vagy önálló,
   a challenge-service saját block-listenerét építi." Ez a kör a második utat
   választja (D3 lent) — a `block_service.py`-t NEM bővíti (tilos zónán
   kívül esne, `allowed_paths`-on nincs), hanem a meglévő
   `query_filters.py::is_blocked_pair`-t hívja közvetlenül a saját
   `challenge_invite_service.py`-ból, ugyanúgy, ahogy `post_service.py` teszi.
5. **Az idempotency-key minta (Kör 11, `post_service.py`) DB-szintű unique
   constraint, nem app-szintű cache.** `_existing_post_by_idempotency_key`
   (183. sor) előzetesen olvas, `IntegrityError` esetén rollback + újraolvasás
   (380–409. sor). A Kör 21 invite-létrehozása ugyanezt a mintát követi:
   unique index `(inviter_profile_id, challenge_id, idempotency_key)`-n.
6. **Nincs pesszimista lockolás a teljes backend community modulban.**
   `grep -rn "with_for_update(\|SELECT.*FOR UPDATE" backend/` → 0 találat a
   teszteken kívül. Az egységes minta optimista: DB `UNIQUE` constraint +
   `IntegrityError` elkapás + feltételes `UPDATE ... WHERE state IN
   (<forrás-állapotok>)` és a módosított sorok számának ellenőrzése —
   `follow_service.py` (9 előfordulás), `identity_service.py` (8),
   `profile_service.py` (7) ugyanezt teszi. A Kör 21 A5 "cancel race"
   cellája ugyanezt a mintát követi, NEM `SELECT ... FOR UPDATE`-et (lásd
   D5).
7. **A rate-limit primitívum már létezik és újrahasználható.**
   `backend/app/ratelimit.py::RateLimiter` — process-local, ugyanaz a
   primitívum, mint `routers/search.py::_search_limiter` és
   `routers/handles.py::_availability_limiter/_change_limiter`, mindkettő
   `reset_rate_limiters()` teszt-hookkal. A Kör 21 `challenges.py` routere
   ugyanígy importálja (`from ...ratelimit import RateLimiter`), nem épít
   saját mechanizmust.
8. **A `NOTIFICATION_TYPE_ALLOWLIST` MÁR tartalmazza a releváns típusokat.**
   `backend/app/community/models/notification.py:108-121` — a 10 engedélyezett
   érték között MÁR ott van `"challenge_invite"` és `"challenge_completed"`.
   Ez a kör **nem nyúl** a notification-integrációhoz (a
   `backend/app/community/notifications/notification_service.py` NINCS az
   `allowed_paths`-on) — az élő bekötés egy jövőbeli kör dolga, ugyanúgy,
   ahogy a Kör 20 sem kötötte be a reaction/comment/follow eseményeket
   (service-réteg-only, ADR 0414 D2 folytatása). Ez a kör csak azt méri fel,
   hogy a HELY megvan, ha egy jövőbeli kör élesíteni akarja.
9. **Nincs "challenge definíció létrehozása" HTTP endpoint ebben a körben.**
   A brief §8 implementációs sorrendje a `challenges.py` routerhez csak
   "invite/accept/decline/cancel endpontokat" ír elő — nincs `POST
   /challenges` a listán. A §6 acceptance-kritériumok (A1–A7) mind az
   invite-állapotgépről szólnak, egyikük sem egy publikus
   létrehozás-endpointról. Lásd D6.
10. **A `club` challenge-típusnak nincs élő club-tábla, amihez validálni
    lehetne.** ADR 0402 §D4: "A klub-domain a Kör 24-ben épül meg — nincs
    élő club-endpoint." A Dart `CommunityChallengeDefinition.clubId` nullable
    String (nem típusos FK) — a backend modell ugyanezt tükrözi: nullable
    string oszlop, DB-szintű FK-kényszer nélkül, validáció nélkül. Lásd D7.

## Döntés

### D1 — A backend enum-készlet 1:1 tükrözi a MÁR élő Flutter domain-kontraktust, nem a gamifikációt

A `backend/app/community/models/challenge.py` két string-enumja
(`ChallengeInviteState`, `ChallengeType`) pontosan a
`community_challenge.dart` wire-értékeit adja vissza:
`draft/sent/accepted/declined/expired/cancelled/active/completed/forfeited`
és `friends/club/dailyCommunity/periodicGlobal/personalBest`. A
`challenges.py` router JSON-válaszai ezeket a sztringeket adják vissza
változatlanul — a Flutter oldal `challengeInviteStateFromWire`/
`challengeTypeFromWire` dekódere ismeretlen értéknél `null`-t ad (a Kör 5
kontraktus A3-cellája), tehát a backend oldalán bármely jövőbeli új érték
bővítés, nem törés.

**NEM elfogadható gyengítés:** egy saját, a gamifikációból másolt vagy attól
eltérő enum-készlet — ez a §1.0 "elérhetetlen cél-státusz" hibaosztályt
reprodukálná egy szinttel lejjebb (a backend és a MÁR élő Flutter domain
divergálna).

### D2 — A Flutter oldal a MEGLÉVŐ domain-kontraktust hívja, application-réteg controlleren keresztül

`lib/features/community/data/repositories/challenge_repository_impl.dart`
(ÚJ, felvéve az `allowed_paths`-ra) implementálja a Kör 5
`CommunityChallengeRepository` interfészt Dio-hívásokkal, a Kör 7
`relationship_repository_impl.dart` mintáját követve (provider a fájl
alján, `final communityChallengeRepositoryProvider = Provider<
CommunityChallengeRepository>((ref) => ...)`).
`lib/features/community/application/controllers/challenge_controller.dart`
(ÚJ, felvéve az `allowed_paths`-ra) egy Riverpod `AsyncNotifier`, ami a
repository-t fogyasztja — a képernyő SOSEM hívja a repository-t közvetlenül
(ugyanaz a minta, mint a Kör 20 `notification_controller.dart`-ja: a screen
csak a controllert olvassa/hívja). `community_challenges_screen.dart` a
controllert `ref.watch`/`ref.read`-eli.

**Miért nem elég a puszta screen fájl (a brief eredeti listája szerint):**
a Kör 5 óta a `CommunityChallengeRepository` interfész és a domain-modellek
élnek, de **nincs implementáció, nincs provider** — egy screen-only diff
fordítási hibával állna meg (nincs mit `ref.watch`-olni). Ez a §1 pre-flight
szabály 2. pontja ("erőforrás-tulajdonlás — mérd ki a tényleges hívási
láncon") szerinti hiányzó láncszem.

### D3 — A block-ellenőrzés a meglévő `query_filters.py::is_blocked_pair`-t hívja, NEM bővíti a `block_service.py`-t

`challenge_invite_service.py` invite-létrehozáskor (és accept-kor, a
biztonság kedvéért duplán) közvetlenül hívja
`is_blocked_pair(db, profile_id_a=inviter_id, profile_id_b=invitee_id)`-t,
a `post_service.py`/`comment_service.py` write-side mintáját követve. A
`block_service.py` (tilos zóna, nincs az `allowed_paths`-on) **változatlan**
marad — ADR 0402 §D3 horog második ága (önálló hívás a challenge-service-ből,
nem a block_service bővítése), mert a challenge-invite tranzakció NEM a
`community_follows`/`community_follow_requests` táblákat írja, tehát nem
tartozik a §D1 block-tranzakció hatókörébe — egy SAJÁT, csak-olvasó
ellenőrzés, ami nem indokolja a block_service tranzakciós felületének
bővítését.

### D4 — Idempotency: DB unique constraint, a Kör 11 post-create mintája

`community_challenge_invites` tábla: `UNIQUE(challenge_id,
inviter_profile_id, invitee_profile_id, idempotency_key)`. A service
előzetesen olvas (`_existing_invite_by_idempotency_key` helper, a
`post_service.py::_existing_post_by_idempotency_key` mintájára), majd INSERT;
`IntegrityError`-ra rollback + újraolvasás. A §10 kötelező valódi-sértés
próba (idempotency-check kivétele → két egymást követő azonos kérés → két
sor) pontosan ezt a konstruktumot mutatja meg pirosnak.

### D5 — A5 "cancel race": feltételes UPDATE + rowcount-ellenőrzés, a race-teszt Barrier-je a PONTOS SQL-döntési pontnál

Minden állapotátmenet (`accept`, `decline`, `cancel`) egyetlen feltételes
SQL `UPDATE`: `UPDATE community_challenge_invites SET state = :new_state,
... WHERE id = :id AND state IN (:megengedett_forrás_állapotok)`, majd a
módosított sorok számának ellenőrzése (0 sor → a state már elmozdult,
`409`/domain-hiba, NEM `SELECT`-then-`UPDATE`). Ez a kódbázis egységes,
mért mintája (§Kontextus 6. pont) — nincs `SELECT ... FOR UPDATE`, ezt a
kör NEM vezeti be.

A brief §10 kötelező A5 "cancel race" próbájának szinkronizációja **L421
szabálya szerint** a szál BELÉPÉSI pontja helyett a TÉNYLEGES SQL-döntési
pont elé kerül: a service egy `_before_transition` (vagy hasonló nevű,
tesztből monkey-patchelhető) hook-ot ad közvetlenül a feltételes `UPDATE`
elé — ugyanaz a minta, mint a Kör 20 `notification_service.py`
`_before_commit` seam-je. A review a race-tesztet **izolált klónban, 10–15×
egymás után** futtatja újra elfogadás előtt (L421 review-mérce) — egyetlen
zöld implementer-jelentés nem elég bizonyíték egy nem-determinisztikus
konstrukcióra.

**NEM elfogadható gyengítés:** `threading.Barrier` a szálak elején (a
`writer()`/`transition()` függvény BELÉPÉSEKOR) — L421 mérése szerint ez
10 futásból 7-szer nem reprodukálja a race-t, mert az egyik szál a másik
indítása előtt már végigfut a teljes existence-check→UPDATE→commit láncon.

### D6 — Nincs publikus "challenge definíció létrehozása" endpoint ebben a körben

A `challenges.py` router csak invite/accept/decline/cancel endpontokat ad
(a brief §8 saját implementációs sorrendje szerint). A tesztek
(`test_challenge_invite_service.py`) a challenge-definíció sorokat
közvetlenül a service/model rétegen keresztül hozzák létre (test-fixture
vagy egy NEM-publikus, csak a service modulon belüli helper), nem egy HTTP
endpointon át. Egy publikus létrehozás-endpoint (jogosultság: ki hozhat
létre challenge-et milyen típussal) egy külön, ebben a körben nem
budgetezett policy-döntés lenne — egyik A1–A7 acceptance-cella sem teszteli
a létrehozást, mindegyik egy MEGLÉVŐ challenge-invite állapotátmenetéről
szól.

### D7 — `club` challenge-típus: strukturálisan elfogadott, validáció nélkül (Kör 24 horog)

A backend `community_challenges.club_id` nullable string oszlop, DB FK
kényszer és eligibility-validáció NÉLKÜL — ugyanaz a "horgot hagyunk, stub
nélkül" minta, mint ADR 0402 §D3/§D4. Egyetlen A1–A7 cella sem teszteli a
`club` típust; a mező jelenléte csak azt garantálja, hogy a Kör 24
klub-integráció ne igényeljen sémaváltozást.

## Elutasított alternatívák

- **Új, párhuzamos challenge-vokabulárium bevezetése a backendben, a
  gamifikáció `DailyChallengeType`-ját "adaptálva".** Elvetve: a brief
  eredeti feltevése (gamifikáció-kompatibilitás) tényellenőrzésen megbukott
  (Kontextus 1. pont) — a két domain vokabuláriuma strukturálisan
  összeegyeztethetetlen (tartalom-referenciák vs. szociális állapotgép), és
  egy ilyen adapter csak látszat-kompatibilitást adna.
- **`block_service.py` bővítése egy challenge-invite-specifikus
  tranzakciós lépéssel.** Elvetve: ADR 0402 §D3 horog kifejezetten erre a
  körre bízta a választást, és a challenge-invite create/accept egy
  csak-olvasó block-ellenőrzés, nem egy block-tranzakció írása — a
  `block_service.py` (tilos zóna) bővítése indokolatlan felületnövelés
  lenne.
- **`SELECT ... FOR UPDATE` pesszimista lock az A5 cancel race-hez.**
  Elvetve: nulla precedens a kódbázisban (Kontextus 6. pont) — a feltételes
  `UPDATE` + rowcount-ellenőrzés ugyanazt a garanciát adja, kevesebb
  új mechanizmussal, és konzisztens marad a `follow_service.py`/
  `identity_service.py` mintájával.
- **Publikus "challenge létrehozása" endpoint felvétele a scope-ba, hogy a
  brief §3 "challenge tábla" megfogalmazása szó szerint teljesüljön.**
  Elvetve: a brief §8 saját router-lépése nem sorolja fel, egyik
  acceptance-cella sem méri, és egy jogosultsági policy-döntést nyitna
  (ki hozhat létre milyen típusú challenge-et) ami túlnő a kör
  "high risk" indoklásán.

## Következmények

- A `CommunityChallengeRepository` (Kör 5, ADR 0399) ELSŐ implementációja
  ebben a körben landol — a 9 metódusból ez a kör 4-et köt be élesben
  (`invite`, `acceptInvite`, `declineInvite`, `cancelInvite`); `listChallenges`/
  `fetchDefinition`/`fetchMyParticipation` a lista/detail képernyőhöz kell,
  `submitResult`/`leaderboard` Kör 22/23 hatásköre marad (a repository
  interfészen implementálva, de a service-oldal `NotImplementedError`-t vagy
  helyőrző választ adhat rájuk, ha a brief screen-je nem hívja őket).
- A `test/ui/ui_inventory_test.dart` screen-számláló 74→75-re nő — ez a
  fájl az `allowed_paths`-ra kerül, hogy a Kör implementer ugyanabban a
  commitban zárja, ne a teljes CI-suite fogja meg később (L420/L422
  visszatérő drift-osztály, harmadszori megelőzés a Kör 20 precedense
  szerint).
- Két új ARB-kulcs-namespace (`communityChallenge*`) kerül a
  `lib/l10n/app_en.arb`/`app_hu.arb`-ba — explicit elkülönítve a
  gamifikáció MEGLÉVŐ `challenge*` kulcsaitól (pl. `challengeDailyTitle`,
  `challengeTitle`), hogy a két domain UI-string-tere ne ütközzön.
- Egy jövőbeli kör (Kör 22 eredmény-beküldés) a §D6 horgot használja: a
  `submitResult` repository-metódus MÁR definiálva van, csak a service-oldali
  bekötés hiányzik.

## A visszavonás feltétele

Felülvizsgálandó, ha a Kör 24 (klub) élő club-endpointot ad — ekkor a §D7
`club_id` mező FK-kényszert és eligibility-validációt kaphat. Felülvizsgálandó,
ha egy jövőbeli kör a challenge-invite eseményeket élő notification-hívásra
köti (a §"Kontextus" 8. pontja szerint a hely megvan, a bekötés nem ennek a
körnek a dolga).
