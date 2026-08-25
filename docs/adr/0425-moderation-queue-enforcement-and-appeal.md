# ADR 0425 — Moderation queue, enforcement és appeal

- **Státusz:** Elfogadva (E09-R27 pre-flight, 2026-08-24)
- **Kör:** E09-R27 — Moderation queue, enforcement és appeal
- **Implementer motor:** MiniMax M3 — az ADR-t az orchesztrátor (Claude Sonnet 5,
  `--effort high`) írta a pre-flightban (ADR 0055).
- **Epic:** Chapter 10 — Epic 9 (Community Platform), Kör 27 (a 32 kör közül a
  huszonhetedik)
- **Kontext-ADR-ek:** [0407](0407-comment-reply-and-mention.md) §D2 (Kör 16 —
  `comment_policy.py::can_delete(is_moderator: bool)`, a HÍVÓ-adta,
  DB-mentes moderator-jelzés mintája, és az EXPLICIT megjegyzés, hogy a
  valódi forrást "a Kör 26/27 admin-auth kör" dönti el — ez a kör az),
  [0412](0412-media-processing-privacy-and-moderation-state.md) §D5 (Kör 19 —
  `media_moderation.py::triage()`/`resolve_review()` szétválasztás: az
  automatika sosem írhat közvetlenül súlyos végállapotot, csak egy
  emberi-hívású függvény — ez a kör ugyanezt a mintát viszi a case-szintre),
  [0422](0422-user-report-and-immediate-safety-flow.md) (Kör 26 —
  `community_reports` tábla + `reporter_profile_id` retaliation-határa, amit
  ez a kör csak OLVAS, nem módosít).
- **Sorszám-jegyzet:** a brief fejléce `0415`-öt adott előre kiosztott
  ADR-ként, de azt közben egy másik kör foglalta el
  (`0415-community-challenge-invite-lifecycle.md`, MÁR MERGE-ELVE) — a
  `tools/round-slots.py reserve-adr --round E09-R27` friss számot adott
  (`0425`; `0423`-`0424` már más köröké). A brief §0.0 D1 rögzíti a
  korrekciót.

## Kontextus

**Mért 2026-08-24-én, a pre-flightban (`main @ 4222800f`):**

1. `grep -rn "role\|moderator\|is_staff\|is_admin" backend/app/models.py
   backend/app/community/models/profile.py` → **0 találat**. A `User`
   modell (`backend/app/models.py:15-29`) mindössze `id, email,
   hashed_password, created_at`; a `CommunityProfile`
   (`backend/app/community/models/profile.py:40-90`) `id, public_id,
   user_id, display_name, created_at`. Egyik modellen SINCS
   role/admin/staff/scope mező. Az egyetlen `role` oszlop a
   `community_clubs` klub-tagsági szerepkör (`club.py:98-355`,
   `CLUB_ROLE_MODERATOR`), ami egyetlen klubra korlátozott és NEM
   sitewide admin-jogosultság — nem tévesztendő össze ezzel a körrel.
2. A `comment_policy.py::can_delete` (Kör 16, ADR 0407 §D2) **explicit
   kimondja**: az `is_moderator: bool` HÍVÓ-adta, DB-mentes paraméter,
   mert "a Kör 26/27 admin-auth kör" dönti el a valódi forrást (DB-mező,
   külön tábla, vagy JWT-claim) — a `comment_service.py` MA mindig
   `is_moderator=False`-t ad át, mert nincs élő admin-auth felület
   (`comment_policy.py:9-27`). **Ez a kör az, amit az ADR 0407 §D2 előre
   jelzett** — a moderator-identitás valódi forrását ITT kell rögzíteni.
3. `backend/app/deps.py::get_current_user`/`CurrentUser` az EGYETLEN
   auth-primitíva a backend egészében (`deps.py:22-36`) — a JWT payload
   kizárólag `sub` (user id), `iat`, `exp` claimeket hordoz
   (`security.py:41-49`), NINCS `scope`/`role` claim. `require_scope`
   vagy `Security()` (FastAPI scope-tudatos wrapper) sehol a repóban.
4. A brief `allowed_paths`-a **NEM tartalmazza** a
   `backend/app/models.py`, `backend/app/deps.py`, `backend/app/security.py`
   vagy `backend/app/community/models/profile.py` fájlokat — mindegyik a
   §4 "Tilos zóna" alá esik (a lista fölöttük hallgat, ami az ADR 0087 §2
   H3 értelmében tilos zóna). A moderator-identitás forrásának tehát
   TELJES EGÉSZÉBEN az ÚJ `backend/app/community/models/moderation.py`
   fájlon belül kell élnie, `User`/`CommunityProfile`/`deps.py`/
   `security.py` módosítása NÉLKÜL (D1).
5. A Kör 19 `media_moderation.py` triage/resolve_review szétválasztása
   (ADR 0412 §D5) élő, mért precedens ugyanarra a mintára, amit a brief
   §5.1 a case-szinten megismétel: az automatika `triage()`-e SOHA nem ír
   `processing_state='rejected'`-et, kizárólag `resolve_review()` (ember
   hívja). Ez a kör ugyanezt a szétválasztást a moderation-case
   állapotgépre és az account-enforcementre vetíti (D4).
6. `backend/app/community/models/report.py` (Kör 26) már felkészített
   olvasási felületet hordoz erre a körre: `(target_type, target_id,
   created_at, id)` composite index kifejezetten "a Kör 27 moderation
   queue cursor-paginated read path"-jára épült (`report.py:52-54`), és a
   `reporter_profile_id` retaliation-határa (ADR 0422 D2) rögzíti: ez az
   oszlop SOHA nem kerülhet egy target-néző vagy moderator-néző válasz-
   sémába — ez a kör is öröklve tartja (D7).
7. `docs/sdd/10-epic-09-community-platform.md` §18.1 rögzíti az öt-értékű
   `ModerationState` Dart enumot
   (`visible/limited/pendingReview/removed/authorOnly`) — ez a brief §3
   "visible/limited/pending-review/removed/author-only" felsorolásának
   forrása; Python oldalon snake_case string-értékek (D3).
8. Az alembic-lánc feje `e09_r26_0019` (`alembic/versions/e09_r26_0019_community_report.py:67-68`)
   — az új migráció `down_revision="e09_r26_0019"`, `revision="e09_r27_0020"`
   (a brief `allowed_paths` fájlneve már ezt a sorszámot viseli).
9. `node tools/knowledge-rag.mjs --corpus lessons,halts,adr --top 5
   "moderation queue enforcement appeal admin scope"` → **ADR 0407 §D2**
   (bm25#2 emb#13) — lásd 2. pont, ez a döntő találat. `node
   tools/knowledge-rag.mjs --corpus lessons,halts --top 5 "immutable audit
   event chain admin authorization scope new"` → nincs közvetlenül ide
   vágó lecke a `community_moderation_actions` append-only mintára; a
   legközelebbi analóg a Kör 19 audit-oszlopok mintája (6. pont), ami
   ADR-szinten már dokumentált — nincs külön lecke-hivatkozás.

## Döntés

### D1 — Moderator-identitás forrása: ÚJ `community_moderators` tábla, NEM `User`/`CommunityProfile` mező

`backend/app/community/models/moderation.py` (engedélyezett, ÚJ fájl) egy
`CommunityModerator` táblát vezet be:

```python
class CommunityModerator(Base):
    __tablename__ = "community_moderators"
    id: BigInteger/Integer(sqlite) PK
    user_id: Integer, ForeignKey("users.id", ondelete="CASCADE"), unique=True, nullable=False
    granted_at: DateTime(timezone=True), nullable=False
    granted_by_user_id: Integer, nullable=True  # audit — ki adta a jogosultságot; NULL = seed/migráció
```

A router (`moderation.py`) a MEGLÉVŐ, VÁLTOZATLAN `CurrentUser`
függőséget importálja (`from ...deps import CurrentUser` — import, nem
fájlmódosítás), majd `db.query(CommunityModerator).filter_by(user_id=
current_user.id).one_or_none()`-lel dönt: `None` → `403`. Ez a Kör
26/27 admin-auth döntés, amit az ADR 0407 §D2 előre jelzett — a "külön
tábla" opciót választja a három felkínált közül (DB-mező a `User`-en,
külön tábla, JWT-claim), mert **a másik kettő tilos zónát sértene**: egy
`User.role`/`CommunityProfile.is_admin` mező a `backend/app/models.py`/
`backend/app/community/models/profile.py`-t módosítaná (H3), egy
JWT-claim pedig a `security.py::create_access_token` és a `deps.py`
módosítását igényelné (szintén H3) ÉS minden MA élő tokent
érvénytelenítene újrakiadás nélkül.

**NEM elfogadható gyengítés:** `User`/`CommunityProfile` mező hozzáadása
vagy a JWT payload bővítése — mindkettő a §4 tilos zónát sértené
(`backend/app/models.py`, `backend/app/deps.py`, `backend/app/security.py`,
`backend/app/community/models/profile.py` egyike sincs az
`allowed_paths`-on). A `granted_by_user_id` audit-mező NEM FK (nincs
garantált élő `User`-sor-egyezés-kényszer szükséges — a mező tisztán
audit-célú, hasonlóan a `resolve_review`-beli `reviewer_id` mintájához,
ADR 0412 §D5).

### D2 — Case-target linkelés: `(target_type, target_id)` pár, NEM FK a `CommunityReport`-ra

`community_moderation_cases` a `community_reports`
`(target_type, target_id)` mintáját ismétli (plain `String` oszlopok, NEM
FK — a target lehet post/comment/profile/media, a Kör 26 mintája szerint).
Egy case attól függetlenül létezhet, hogy van-e hozzá kapcsolódó
`CommunityReport` sor — az automatikus triage (pl. a Kör 19
`media_moderation.py` egy jövőbeli hívása) is nyithat case-t report
nélkül. **Egy `(target_type, target_id)` párhoz legfeljebb EGY NYITOTT
(`state != removed` ÉS `state != author_only` ÉS nincs appeal-upheld
lezárás) case tartozhat** — a `case_service.py` `get_or_create_case`
függvénye ezt a `UniqueConstraint("target_type", "target_id",
"is_open")` mintával (egy `is_open: bool` redundáns, de indexelhető
oszloppal) vagy service-rétegbeli lekérdezéssel kényszeríti; az implementer
választja a mechanizmust, de az invariáns kötelező (több egyidejűleg
NYITOTT case ugyanarra a targetre duplikálná a queue-t és szétforgácsolná
az audit-láncot).

### D3 — Case state: öt snake_case string érték, a §18.1 Dart enum tükre

`community_moderation_cases.state` (String, NOT NULL, default
`"visible"`) — `MODERATION_CASE_STATE_VISIBLE = "visible"`,
`..._LIMITED = "limited"`, `..._PENDING_REVIEW = "pending_review"`,
`..._REMOVED = "removed"`, `..._AUTHOR_ONLY = "author_only"`, modul-szintű
`frozenset` allowlist (ADR 0398 §1 projekt-szintű plain-`String` minta,
ugyanaz mint a `CommunityComment.moderation_state`, ADR 0407 §D5 — de ITT
mind az öt érték él, mert ez a case-szintű állapotgép, nem a komment
kétértékű tükre). **NEM elfogadható gyengítés:** DB-szintű enum/CHECK
(migráció nélkül bővíthetetlen, ADR 0398 §1 ellen menne).

Engedélyezett átmenetek (a §3 "visible→limited→pending-review→
removed/author-only" lánc explicit gráfja, `case_service.py`-ban egy
modul-szintű `dict[str, frozenset[str]]`-ként):

| Honnan | Hová (engedélyezett) |
|---|---|
| `visible` | `limited`, `pending_review` |
| `limited` | `visible`, `pending_review`, `removed`, `author_only` |
| `pending_review` | `visible`, `limited`, `removed`, `author_only` |
| `removed` | `visible` (KIZÁRÓLAG appeal-upheld emberi döntésen keresztül, D6) |
| `author_only` | `visible`, `removed` |

Bármely más pár `ValidationError`-t (vagy ezzel ekvivalens explicit
kivételt) dob, a sor nem változik (A2 mérce-mátrix cella).

### D4 — Automatika kontra ember: a Kör 19 triage/resolve_review-minta a case-szinten (A4 kötelező gát)

Két különálló service-függvény, a `media_moderation.py::triage()`/
`resolve_review()` mintáját követve:

```python
def record_automation_signal(
    db, case, *, confidence: float, provider: str, provider_version: str, now,
) -> CommunityModerationCase:
    """Kizárólag {limited, pending_review} felé mozdíthatja a case-t.
    actor_type='automation', actor_user_id=None mindig. SOSE ír
    'removed'/'author_only'-t, és SOSE hoz létre account-suspension
    enforcement actiont."""

def apply_moderator_decision(
    db, case, *, to_state: str, moderator_user_id: int, reason: str, now,
) -> CommunityModerationCase:
    """Az EGYETLEN út 'removed'/'author_only' felé, és az EGYETLEN út
    bármilyen account-level enforcement action-höz. moderator_user_id
    KÖTELEZŐ és a CommunityModerator táblával ellenőrzött (D1) — ha a
    hívó nem moderátor, TriageError/PermissionError, a case NEM
    változik."""
```

`record_automation_signal` szignatúrájában **nincs `to_state`
paraméter** — a célállapot a függvény belsejében fixen `pending_review`
(vagy a hívó által jelzett súlyosságtól függően `limited`, de a
lehetséges célok halmaza kódszinten `{limited, pending_review}`-ra
korlátozott, nem a hívó dönti el szabadon). Ez a §6.1 kötelező
valódi-sértés próba pontos alanya: az implementer ideiglenesen bővíti a
célállapot-halmazt `removed`-del, lefuttatja a pytest-et, megméri hogy az
**A4 cella PIROSRA vált**, majd visszaállítja (§10-ben dokumentálva) —
pontosan a brief §6.1 előírása szerint, a Kör 19 ADR 0412 §D5 mérési
mintáját követve.

**NEM elfogadható gyengítés:** egy `record_automation_signal(...,
to_state=str)` szabad paraméterezés, ami a hívóra bízná a célállapotot —
ez pontosan az a gyengítés, amit az A4 mérce-mátrix cella tetten kell
hogy érjen.

### D5 — Immutable audit: `community_moderation_actions` kizárólag INSERT, a `case_service.py` nem ír UPDATE/DELETE-et rá

```python
class CommunityModerationAction(Base):
    __tablename__ = "community_moderation_actions"
    id: BigInteger/Integer(sqlite) PK
    public_id: Uuid, unique, default=uuid.uuid4
    case_id: FK("community_moderation_cases.id", ondelete="CASCADE")
    action_type: String(32)  # "automation_signal" | "moderator_decision" | "appeal_submitted" | "appeal_resolved"
    from_state: String(32) | None
    to_state: String(32) | None
    actor_type: String(16)  # "automation" | "human_moderator"
    actor_user_id: Integer | None  # NULL amikor actor_type="automation"
    reason: Text | None
    created_at: DateTime(timezone=True), NOT NULL, default=_utcnow
```

Nincs `updated_at` oszlop (A3 — a hiányzó oszlop strukturálisan jelzi: a
sor sosem frissül). A3 mérce-mátrix próbája: egy explicit UPDATE-kísérlet
a `test_moderation_case_service.py`-ban vagy hibát dob (ha a service
réteg egyáltalán nem exportál update-függvényt az action-ökre, a próba
magát a service-API hiányát méri: `hasattr(case_service, "update_action")
is False` egy célzott cellaként), vagy — ha a teszt közvetlen SQLAlchemy
UPDATE-et futtat a service megkerülésével — a `case_service.py` publikus
felülete demonstrálhatóan sosem hívja azt. Az implementer választja a
konkrét mérési formát, de az invariáns kötelező: **a `case_service.py`
egyetlen függvénye sem módosít vagy töröl egy már beszúrt action-sort**.

### D6 — Appeal: egyszeri beadás case-enként, `appeal_state` mező + action-lánc

`community_moderation_cases.appeal_state` (String, nullable, default
`NULL`) — `NULL` (nincs appeal) → `"submitted"` → `"resolved"`. Az
`submit_appeal(db, case, *, submitted_by_user_id, reason, now)` függvény
`ValidationError`-t dob, ha `case.appeal_state is not None` (A5 — egyszeri
beadás case-enként). A beadás és a lezárás egy-egy
`CommunityModerationAction` sort ír (`action_type="appeal_submitted"` /
`"appeal_resolved"`), a lezárás verdiktje (`upheld`/`overturned`) a
`reason` mezőben vagy egy külön `verdict` oszlopban rögzített — az
implementer választja, de a verdiktnek AUDITÁLTNAK kell lennie (D5).

**A "független review lehetőség" (brief §3) ebben a körben
DOKUMENTÁLT ÜZEMELTETÉSI szabály, NEM kódba zárt kényszer:** az
acceptance-tábla A5 cellája kizárólag az "egyszeri beadás"-t méri, nem az
appeal-t elbíráló moderátor és az eredeti enforcement-döntést hozó
moderátor szükségszerű különbözőségét. Mivel minden action sor rögzíti az
`actor_user_id`-t (D5), az üzemeltetési szabály ("más moderátor bírálja
el az appealt, mint aki az enforcementet hozta") utólag auditálható és a
`docs/operations/community-moderation-runbook.md`-ban dokumentálandó — a
kódba zárt kényszerítés egy jövőbeli kör döntése, ha a mért igény
felmerül. **NEM elfogadható gyengítés:** appeal nélküli végleges
enforcement, vagy appeal, ami a case state-et a moderátor jóváhagyása
nélkül automatikusan visszaállítja.

### D7 — Tartalom-láthatóság (A6): tiszta függvény, NEM routing-integráció ebben a körben

A `case_service.py` egy DB-mentes, tiszta segédfüggvényt exportál:

```python
def content_visibility_for_state(state: str, *, viewer_is_author: bool) -> str:
    """Visszaadja: 'full' | 'limited' | 'hidden_except_author'."""
```

`visible` → `full` minden nézőnek; `limited` → `limited` (a §18.1 Dart
enum "korlátozott" jelentésének megfelelően, pl. warning-banner a
kliensen — a KLIENS-oldali jelentés ezen körön kívül esik); `removed` →
`hidden_except_author` ha `viewer_is_author`, egyébként `hidden` (a
tartalom NEM törlődik a DB-ből, csak a láthatósága szűkül — a §18.1
"nem teljesen törölt" kikötése); `author_only` → `hidden_except_author`
minden nézőnek a szerzőn kívül; `pending_review` → `full` (a review alatt
álló tartalom a döntésig továbbra is látható, hacsak a moderátor nem
mozdítja explicit `limited`-re — a §5.1 "súlyos action ELŐTT emberi
megerősítés" nem jelenti azt, hogy a tartalom addig is rejtve legyen).

Ez a kör **NEM köti be** a `content_visibility_for_state`-et a
`feed.py`/`posts.py`/`comment_service.py` tényleges válasz-útjaiba —
egyik fájl sincs az `allowed_paths`-on (tilos zóna, `lib/**` is tiltott,
a §3 "API-first, nincs mobil UI" kikötése szerint). Ugyanaz a
deferred-wiring minta, mint a `media_moderation.py` triage-seam (ADR 0412)
vagy az `object_store.py` port (ADR 0410) — a szerződés ma él és tesztelt,
a tényleges route-bekötés egy jövőbeli "wiring kör" dolga. A6 mérce-cella
a tiszta függvényt közvetlenül hívja, DB/HTTP nélkül.

### D8 — Queue priority: dokumentált formula, HÁROM rögzített bemeneti jel, a súlyok az implementer választása

A brief §3 "queue priority: report-signal + automation-triage +
account-history, dokumentáltan" kikötése — mivel egyik acceptance
criteria cella (§6) sem méri számszerűen a priority-t, ez NEM S3
numerikus-küszöb kötelezettség (nincs cellahármas). A `case_service.py`
egy `priority_score: int` oszlopot tart a case-en, amit `get_or_create_case`
és `record_automation_signal` frissít, a BEMENETEK rögzítettek (a
KIMENETI súlyozás az implementer mérnöki döntése,
`docs/operations/community-moderation-runbook.md`-ban dokumentálva):

1. **report-signal** — a target-re beérkezett `CommunityReport` sorok
   száma (a case_service OLVASSA a `community_reports` táblát a
   `(target_type, target_id)` páron, de SOHA nem olvassa vissza a
   `reporter_profile_id`-t egy válasz-sémába, D2/ADR 0422 D2 öröklve).
2. **automation-triage** — a legutóbbi `record_automation_signal` hívás
   `confidence` értéke, ha van.
3. **account-history** — a target tulajdonos-profiljához (ha a
   `target_type` szerint feloldható, pl. `post`/`comment` szerzője) tartozó
   korábban `removed`/`author_only` állapotba LEZÁRT case-ek száma; ha a
   tulajdonos-profil nem oldható fel (pl. ismeretlen `target_type`), a jel
   `0`.

**NEM elfogadható gyengítés:** egy negyedik, dokumentálatlan bemeneti jel
hozzáadása, vagy a report-signal/triage-confidence/account-history
bármelyikének kihagyása — a §3 mindhármat névvel nevezi.

### `**Kockázat = high, indoklás:**`

A `risk = "high"` besorolás nem egy `high_risk_path_fragments` kulcsszóra
illeszkedő `allowed_paths` elemből fakad (a brief-lint S7 ezt jelezte),
hanem a funkcionális tartalomból: ez a kör vezeti be az ELSŐ site-wide
admin/moderator jogosultsági réteget (D1), és egy súlyos, visszavonhatatlan
account-enforcement audit-láncot épít (D4/D5) — mindkettő közvetlen
biztonsági/jogosultsági kockázat (jogosulatlan hozzáférés a moderation
queue-hoz, vagy egy automatika által meghozott végleges enforcement-döntés),
ami a kötelező `security-reviewer` subagent bevonását indokolja
(AGENTS.md §15 risk=high sor). A kockázat forrása a DOMAIN
(authorization + irreverzibilis enforcement), nem egy fájlnév-minta.

## Elutasított alternatívák

- **`User.role` vagy `CommunityProfile.is_admin` mező.** Elvetve (D1): a
  `backend/app/models.py`/`backend/app/community/models/profile.py` a
  brief tilos zónájában van — a bevezetés H3 lenne.
- **JWT `scope`/`role` claim.** Elvetve (D1): a `security.py`/`deps.py`
  módosítását igényelné (tilos zóna) ÉS minden ma élő tokent
  érvénytelenítene újrakiadás nélkül — ellentétben a különálló táblával,
  ami visszamenőleg, migrációval bővíthető anélkül, hogy a meglévő
  session-eket megszakítaná.
- **`record_automation_signal(to_state=str)` szabad paraméterezés.**
  Elvetve (D4): ez pontosan az a gyengítés, amit az A4 mérce-mátrix
  cellának tetten kell érnie — egy szabad `to_state` a hívóra tolná a
  human-review-gate kikényszerítését, ami a Kör 19 ADR 0412 §D5 mért
  precedense szerint bukásra ítélt minta (a `triage()` sosem kap
  `to_state` paramétert).
- **Kódba zárt "más moderátor bírálja el az appealt" kényszer.** Elvetve
  (D6): nincs hozzá mérce-cella a §6 acceptance táblában, és a kényszer
  bevezetése (pl. egy `_original_actor_id != resolver_id` assert) olyan
  edge case-eket nyitna (egyetlen élő moderátor esete), amit a brief nem
  tárgyal — dokumentált üzemeltetési szabály marad, auditálható adatokkal.
- **Case state közvetlen bekötése a `feed.py`/`posts.py` válasz-útjaiba.**
  Elvetve (D7): egyik fájl sincs az `allowed_paths`-on — a bekötés H3
  lenne; a deferred-wiring minta (ADR 0410/0412) ezt már kétszer
  bevált mintaként rögzítette.

## Következmények

- A `community_moderators` tábla (D1) az ELSŐ site-wide admin-auth
  primitíva a repóban — egy jövőbeli kör, amely további admin-funkciót
  vezet be (pl. account-suspension más domainre), ugyanezt a táblát
  hivatkozhatja `user_id`-n keresztül, nem kell újra feltalálnia a
  forrást.
- A `comment_policy.py::can_delete(is_moderator=...)` (ADR 0407 §D2) egy
  KÖVETKEZŐ kör dolga bekötni a `community_moderators` táblára — ez a
  kör NEM módosítja a `comment_service.py`-t (nincs az `allowed_paths`-on),
  csak a forrást teremti meg, amit egy jövőbeli kör hivatkozhat.
- A `content_visibility_for_state` (D7) szerződése a jövőbeli
  feed/post-routing wiring kör bemenete — az a kör NEM írhatja újra ezt a
  függvényt, csak HÍVJA a meglévő route-okból.
- A `priority_score` (D8) három bemeneti jele rögzített — egy jövőbeli
  kör, amely a súlyozást hangolja, ezt az ADR-t hivatkozhatja, nem kell
  újratárgyalnia a bemeneteket.

## A visszavonás feltétele

Felülvizsgálandó, ha egy jövőbeli admin-felület (pl. moderátor
kinevezés/visszavonás UI) azt találja, hogy a `community_moderators`
tábla `granted_by_user_id` audit-mezője nem elég egy teljes
jogosultság-történethez (pl. visszavonás-időbélyeg is kell) — ekkor egy
külön migráció bővíti a táblát, a `user_id` alapú lookup-szerződés
változatlan marad. Szintén felülvizsgálandó, ha a D6 "dokumentált
üzemeltetési szabály" helyett kódba zárt kényszer válik szükségessé — ekkor
egy jövőbeli kör bővítheti `submit_appeal`/az appeal-lezáró függvényt egy
`resolver_user_id != original_actor_user_id` ellenőrzéssel.
