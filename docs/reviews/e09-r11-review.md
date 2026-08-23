# E09-R11 — Review

Brief: docs/rounds/e09-r11-post-crud-and-audience-enforcement.md
Diff: `git diff 47438824...fe03fa0f` (`main` → `minimax/e09-r11-post-crud-and-audience-enforcement`)
Reviewer: Claude Sonnet 5 · Dátum: 2026-08-23
Verdikt (javító kör 1 után, `e0bbbaad`, 2026-08-23): **APPROVED**

## Javító kör 1 zárása (`e0bbbaad`)

Mind a 4 lelet zárva — a Claude saját maga futtatta újra a gate-et és a
scope-auditot egy FRISS, izolált `/tmp/review-e09-r11-fix1` klónban
(`git clone --branch minimax/e09-r11-post-crud-and-audience-enforcement`),
nem az implementer önjelentésére hagyatkozva:

| Lelet | Zárás | Igazolás |
|---|---|---|
| F1 BLOCKER | FIXED (`1ca7909d`) | `patch_post` a `soft_delete_post` 537. sorával azonos owner-check-et kapott; ÚJ `test_patch_by_non_owner_returns_404` a body-t is asserteli (`"mine"`, nem `"DEFACED"`) — a Claude a diffet sor szerint elolvasta, a check pontosan a `_evaluate_visibility` UTÁN, a resource_version-ellenőrzés ELŐTT van. |
| F2 BLOCKER | FIXED (`15db1b62`) | Új `_resolve_public_id_by_profile_id(db, post.profile_id)` helper; GET/PATCH mindkettő ezt hívja `_row_to_out`-hoz, NEM a hívó saját id-ját. `test_audience_matrix_owner_and_public_viewer` kibővítve `author_public_id == author.public_id` + `!= viewer.public_id` asszerciókkal. |
| F3 MINOR | FIXED (`a17870cd`) | `deleted_at IS NULL` filter a lookupban + a DB-szintű UNIQUE-constraint ütközésre a tombstone `idempotency_key`-jét NULL-ra állítja, majd a fresh INSERT lefut (a tombstone audit-trailje megmarad). ÚJ `test_create_after_soft_delete_with_same_idempotency_key` a tombstone ÉS az új sor állapotát is asserteli. |
| F4 MINOR | WONTFIX ebben a körben (dokumentálva) | A brief §10.1 rögzíti az indoklást (Kör 4 `privacy.py` öröklött precedens, owner-only felszín, alacsony konkurencia-kockázat) — elfogadom: a review már explicit engedélyezte a dokumentált WONTFIX-utat, ha a diff hizlalása nem éri meg. Follow-up a HANDOFF §10.6-ba felvéve (feltételes-UPDATE egységesítés egy jövőbeli körben). |
| F5/F6 NOTE | nem blokkoló, nem igényelt módosítást | változatlan |

**Független újramérés (Claude, NEM az implementer önjelentésére hagyatkozva):**
- `python3 tools/scope-audit.py --repo /tmp/review-e09-r11-fix1 --brief
  docs/rounds/e09-r11-post-crud-and-audience-enforcement.md --base
  47438824` → `Legacy scope audit OK (47438824055e..e0bbbaad6d09, 8
  changed path(s), 1 generated/ignored)`.
- `tools/round-gate.sh test/core/architecture_dependency_test.dart` egy
  FRISS izolált klónban → MINDEN GATE ZÖLD (format, analyze, célzott
  Dart-teszt, architecture, secrets, l10n, backend ruff format/check,
  backend pytest).
- `python -m pytest tests/community/test_post_service.py -v` → **20
  passed** (ugyanaz a klón, közvetlenül futtatva, nem az implementer
  logjából másolva).
- A diffet fájlonként, sorban elolvastam (`git diff fe03fa0f e0bbbaad --
  backend/app/community/services/post_service.py backend/app/community/routers/posts.py`
  + a teszt-diff) — az F1/F2/F3 javítások pontosan a review §Kötelező
  javítás celláiban leírt mintát követik, nem kozmetikus vagy a
  tünetet elfedő megoldás.

Merge-döntés: **engedélyezett** — minden BLOCKER/MAJOR zárva, a gate és a
scope-audit független újramérése tiszta.

---

## Eredeti review (javítás előtt, `fe03fa0f`) — a fenti záró szakasz felülírja a verdiktet, a lelet-részletek alább változatlanul megmaradnak dokumentációként

Eredeti verdikt: CHANGES REQUIRED

## Összegzés

BLOCKER: 2 · MAJOR: 0 · MINOR: 2 · NOTE: 2

Gate: MINDEN ZÖLD (`/tmp/review-e09-r11`, izolált klón, `tools/round-gate.sh
test/core/architecture_dependency_test.dart`). Scope-audit: OK, 7 changed
path(s), 0 violation (izolált újramérés a pre-flight `47438824` bázison).
Dedikált `security-reviewer` agent (a brief `risk = "high"` miatt
kötelező, ADR 0055/AGENTS.md) FÜGGETLENÜL futott, és a BLOCKER-1-et saját
reprodukcióval erősítette meg — a leletei alább be vannak dolgozva.

**A zöld gate ezúttal is elrejtette a hibát** — mindkét BLOCKER azért
maradt fedetlen, mert a tesztek kizárólag a TULAJDONOS felhasználóval
hívják a PATCH-et és a GET-et; a "nem-tulajdonos olvas/ír" ágra nincs
regressziós teszt (a `test_delete_by_non_owner_returns_404` a DELETE-re
igen, a PATCH-re nincs párja).

## Acceptance criteria

| # | Kritérium | Teljesült | Bizonyíték |
|---|---|---|---|
| A1 | Forged author a kérésben figyelmen kívül marad | ✅ | `schemas/post.py:117` `extra="forbid"`, nincs `author_id` mező; `test_create_forged_author_ignored` |
| A2 | Idempotens create, retry nem duplikál | ✅ | `UNIQUE(profile_id, idempotency_key)` migráció+ORM, `IntegrityError`→re-read minta (`post_service.py:367-384`); `test_create_idempotency_retry_returns_same_post` + §6.1 valódi-sértés próba |
| A3 | Audience-mátrix (owner/follower/blocked/public) | ✅ | `test_audience_matrix_*` 3 teszt |
| A4 | Blocked user nem olvashat közvetlen ID-vel | ✅ | `is_blocked_pair` a helyes direkt-pár helper (`post_service.py:243`); `test_blocked_viewer_cannot_read_post` |
| A5 | Stale edit elutasítva | ⚠️ részben | 409 a szekvenciális esetre igen (`test_stale_resource_version_rejected`); a védelem read-compare-write, nem DB-szintű CAS — ld. MINOR-2 |
| A6 | Soft delete nem tér vissza normál endpointból | ⚠️ részben | GET-en helyesen 404 (`test_soft_delete_hides_post_from_subsequent_gets`); DE a create-idempotencia-retry visszahozza a törölt sort — ld. MINOR-1 |
| A7 | HTML/script body elutasítva | ✅ | reject-only regex, `test_html_body_rejected_at_parse_time` + `test_html_rejected_in_patch_too`; bypass-lehetőségek dokumentálva, ld. NOTE-1 |

## Scope-audit

Engedélyezett fájlokon kívüli változás: **nincs** a committed diffben.

`python3 tools/scope-audit.py --repo /tmp/review-e09-r11 --brief
docs/rounds/e09-r11-post-crud-and-audience-enforcement.md --base
47438824` → `Legacy scope audit OK (47438824055e..fe03fa0f3d4c, 7 changed
path(s), 0 generated/ignored)`.

Megjegyzés: az implementer futása közben a munkapéldányban két NEM
committolt, gitignore-hézagba eső SQLite-fájl keletkezett
(`strumsight.db` a repo gyökerén, `backend/strumsight.db` — ez utóbbi a
`backend/.gitignore`-ban van, az előbbi nem), és a `wait-for-round.sh`
ezt `dirty_files=2` / `scope_audit=VIOLATION`-ként jelezte. Ez NEM
kódhiba — a `test_post_service.py::session_factory` fixture minden
teszthez saját `tmp_path`-alapú SQLite URL-t állít be
(`STRUMSIGHT_DATABASE_URL` monkeypatch), a stray fájlok egy MÁSIK,
env-override nélküli futásból (a §7 önálló `pytest`-hívásból) maradtak a
munkafán. Törölve a review előtt, az izolált klónban a scope-audit
tisztán fut.

## Megállapítások

### F1 — BLOCKER — `patch_post` nem ellenőrzi a tulajdonost: bárki szerkesztheti bárki látható posztját

- **Fájl:** `backend/app/community/services/post_service.py:416-501` (`patch_post`), hívó: `backend/app/community/routers/posts.py:264-323`
- **Probléma:** A `soft_delete_post` a 537. sorban explicit tulajdonos-ellenőrzést végez (`if post.profile_id != viewer_profile_id: raise PostNotFound`). A `patch_post`-ban ez HIÁNYZIK — az egyetlen kapu a `_evaluate_visibility` (462. sor), ami egy OLVASÁSI láthatóság-ellenőrzés (deleted → moderation → blocked → audience), NEM írási jogosultság-ellenőrzés. Egy `PUBLIC` audience-ű posztra `evaluate_content_access(PUBLIC, non-blocked)` MINDIG `True`-t ad, függetlenül attól, hogy a néző a tulajdonos-e — tehát bármely nem-blokkolt, hitelesített felhasználó átjut a kapun és módosíthatja a `body`/`audience`/`artifact` mezőket. A router SAJÁT docstringje ("owner-only update", 10-12. és 271. sor) és a brief §3 ("get/patch/delete: audience, block, **owner**, moderation policy ellenőrzés") explicit tulajdonos-ellenőrzést ír elő, amit a kód nem valósít meg.
- **Hatás:** Bármely hitelesített, nem blokkolt felhasználó felülírhatja MÁSVALAKI PUBLIC (vagy általa követett FOLLOWERS-audience) posztjának tartalmát, audience-ét vagy artifact-ját — identitás- és tartalom-integritás sérülés, a brief §5.1/§6.1 IDOR-mércéjének írási oldali ellenpéldája. A dedikált `security-reviewer` agent EZT a hibát a migráció-alapú sémán ÉLESBEN reprodukálta: `profile_id=2` felülírta `profile_id=1` PUBLIC posztjának body-ját `"DEFACED BY ATTACKER"`-re, `patch_post` sikerrel (nem `PostNotFound`-dal) tért vissza.
- **Kötelező javítás:** `patch_post`-ban a `_evaluate_visibility` UTÁN, a resource-version ellenőrzés ELŐTT, add hozzá pontosan a `soft_delete_post` 537. soréval azonos mintát: `if post.profile_id != viewer_profile_id: raise PostNotFound("post not found")` — a D7 egységes 404 megőrzésével (a tulajdonos-hiány nem szivároghat 403-ként).
- **Ellenőrzés:** ÚJ regressziós teszt — egy MÁSODIK (nem-tulajdonos) felhasználó PATCH-hívása egy PUBLIC posztra helyes `resource_version`-nel → 404 (a `test_delete_by_non_owner_returns_404` PATCH-párja). A javítás UTÁN a security-reviewer reprodukciós szkriptje (`/tmp/.../scratchpad/repro_patch_authz.py`, a security-agent jelentésében hivatkozva) `PostNotFound`-ot kell adjon.
- **Státusz:** FIXED (`1ca7909d`) — a Claude a diffet elolvasta, a `test_patch_by_non_owner_returns_404` teszt lefutott és zöld egy független újra-klónozott, izolált gate-futásban.

### F2 — BLOCKER — GET/PATCH válaszban a `author_public_id` a NÉZŐ saját public_id-ja, nem a poszt tényleges szerzőjéé

- **Fájl:** `backend/app/community/routers/posts.py:234-249` (`get_post_endpoint`), `:278-318` (`patch_post_endpoint`), a segédfüggvény `_row_to_out` (136-156. sor)
- **Probléma:** A `_row_to_out(post, author_public_id)` második paramétere a `PostOut.author_public_id` mezőt tölti. A `get_post_endpoint` viszont a HÍVÓ (`current_user.id`-ből feloldott) `viewer_public_id`-t adja át (`_resolve_author_public_id(db, current_user.id)`, 238. sor), NEM a poszt `profile_id`-jából feloldott tényleges szerző public_id-ját. Ugyanez a minta a `patch_post_endpoint`-ban (282. és 318. sor). A create endpoint helyes (ott a hívó VALÓBAN a szerző, mert a create maga hozza létre a sort), de a GET/PATCH minden olyan hívásnál hibás, ahol a néző NEM a tulajdonos.
- **Hatás:** Minden olyan GET, ahol a néző mást olvas (a szolgáltatás ELSŐDLEGES használati módja egy közösségi tartalom-felszínen — pl. bárki PUBLIC posztjának megtekintése), a válasz a nézőt tünteti fel szerzőként. Egy kliens UI, ami erre a mezőre épít ("posted by X"), MINDEN idegen posztot a saját felhasználójának tulajdonítana — adatintegritás-hiba a válasz-szerződés kritikus mezőjén. Az F1-gyel kombinálva (nem-tulajdonos sikeres PATCH-e) ez a hiba még elfedi is a jogosulatlan írást: a válasz hamisan a támadó saját magát mutatja szerzőként, holott a sor ténylegesen az áldozaté maradt.
- **Miért csúszott át:** az egyetlen teszt, ami nem-tulajdonos GET-et hív (`test_audience_matrix_owner_and_public_viewer::r_viewer`), KIZÁRÓLAG a `public_id` mezőt ellenőrzi, az `author_public_id`-t nem — pontosan az a hézag-osztály, amit a brief §S2 falszifikációs cellája kér számon, de itt egyetlen A-cella sem fedi le explicit módon (a bug nem a brief §6 acceptance criteria egyikét sem bukja pirosra közvetlenül, csak a válasz-szerződés implicit helyességét).
- **Kötelező javítás:** `get_post_endpoint`-ban és `patch_post_endpoint`-ban a poszt TÉNYLEGES szerzőjének public_id-ját kell feloldani és átadni — pl. `post.profile_id`-ből egy `SELECT public_id FROM community_profiles WHERE id = :pid` lekérdezéssel (vagy a szolgáltatás-réteg adja vissza a szerző public_id-t a sorral együtt), NEM a hívó saját azonosítóját.
- **Ellenőrzés:** `test_audience_matrix_owner_and_public_viewer::r_viewer` bővítése: `assert r_viewer.json()["author_public_id"] == author.public_id` (vagy ezzel ekvivalens) — a javítás előtt ennek PIROSRA kell váltania (a néző saját id-ját kapná vissza).
- **Státusz:** FIXED (`15db1b62`) — `_resolve_public_id_by_profile_id` helper, a diff pontosan a kért mintát követi.

### F3 — MINOR — Törölt poszt visszatér a create-idempotencia-retry útvonalon

- **Fájl:** `backend/app/community/services/post_service.py:183-203` (`_existing_post_by_idempotency_key`), hívva `326-333` és `374-378`
- **Probléma:** Az idempotencia-lookup NEM szűr `deleted_at IS NULL`-ra. Ha a szerző `idempotency_key=K`-val posztot hoz létre, soft-deleteli, majd UGYANAZZAL a kulccsal újra create-et hív, a `create_post` a "meglévő sor" ágra fut, és a törölt sort adja vissza `201`-gyel (a válasz a törölt tartalmat és egy nem-null `deleted_at`-et hordoz).
- **Hatás:** Kizárólag a SAJÁT tulajdonos érintett (a kulcs `profile_id`-re van szűkítve, tehát nem cross-user szivárgás), de ellentmond a §5.3 szellemének ("törölt tartalom nem tér vissza normál endpointból") és egy hamis `201`-et ad egy ténylegesen nem-létrehozott sorra.
- **Kötelező javítás:** az idempotencia-lekérdezéshez add hozzá a `CommunityPost.deleted_at.is_(None)` feltételt (mindkét helyen — a pre-insert olvasás ÉS az `IntegrityError` utáni újraolvasás), vagy kezeld törölt találatnál friss create-ként (új sor, a régi kulcs "elfogyott").
- **Ellenőrzés:** teszt — create → delete → ugyanazzal a kulccsal create → VAGY új sor jön létre, VAGY a válasz explicit hibát ad, de a törölt tartalom NEM térhet vissza élőként.
- **Státusz:** FIXED (`a17870cd`) — a lookup `deleted_at IS NULL`-t szűr ÉS a DB-szintű UNIQUE-ütközésre a tombstone kulcsát felszabadítja; `test_create_after_soft_delete_with_same_idempotency_key` mindkét sort (tombstone + új) asserteli.

### F4 — MINOR — A PATCH optimista-konkurencia read-compare-write, nem DB-szintű compare-and-swap

- **Fájl:** `backend/app/community/services/post_service.py:464-494`
- **Probléma:** A verzió-ellenőrzés az in-memory `post.updated_at`-en fut (`if _as_utc(payload["resource_version"]) != _as_utc(post.updated_at)`), majd egy FELTÉTEL NÉLKÜLI `UPDATE` következik. Nem egy `UPDATE ... WHERE updated_at = :expected` (vagy `SELECT ... FOR UPDATE` + rowcount-ellenőrzés). Két egyidejű PATCH, ami mindkettő `V0`-t olvas, mindkettő átjut az ellenőrzésen — valós RDBMS-en a később commitoló csendben felülírja a korábbit, pontosan az a lost-update, amit a token megelőzni hivatott.
- **Hatás:** Csak a TULAJDONOS saját magával versenyző konkurens írása érintett (owner-only felszín); az A5 teszt csak a szekvenciális esetet fedi. Ez a `routers/privacy.py` (Kör 4) meglévő, elfogadott mintájával KONZISZTENS — nem regresszió, hanem a precedens öröklött korlátja.
- **Kötelező javítás (opcionális ebben a körben, follow-up is elfogadható):** feltételes `UPDATE ... WHERE updated_at = :expected` és `rowcount == 0` → `StalePostUpdateError`.
- **Ellenőrzés:** egy egyidejűségi teszt (két session, mindkettő `V0`-t lát, csak az egyik nyerjen).
- **Státusz:** WONTFIX ebben a körben (dokumentálva a brief §10.1-ben) — elfogadva; follow-up a HANDOFF §10.6-ba felvéve.

### F5 — NOTE — A HTML-elutasító regex bypass-olható (nem kihasználható EBBEN a körben)

- **Fájl:** `backend/app/community/schemas/post.py:60` (`r"<[a-zA-Z/!]"`)
- **Megfigyelés:** `<script>`/`<SCRIPT>` helyesen elutasítva, de `< script>` (szóköz), `<\nscript>` (sortörés), HTML-entitások (`&lt;script&gt;`) és full-width Unicode (`＜script＞`) átjutnak. Ma NEM kihasználható — nincs HTML/markdown-renderer a projektben (D5 megerősítve), a body JSON-ban, verbatim string-ként tér vissza. **Előretekintő kockázat:** egy jövőbeli kör, ami a body-t HTML-ként renderelné (vagy entitást dekódolna renderelés előtt), a sink-en KELL output-encode-oljon — ez a reject-regex nem XSS-határ, csak tartalom-szabály.
- **Státusz:** nem blokkol, follow-up jegyzet a HANDOFF-ba.

### F6 — NOTE — Az anonim (`viewer_profile_id=None`) olvasási ág jelenleg elérhetetlen, fail-closed

- **Megfigyelés:** a `get_post`/`_evaluate_visibility` támogatja az anonim nézőt (csak PUBLIC, block-ellenőrzés nélkül — nincs profil, ami blokkolható lenne), de a router SOSEM hívja ezzel az értékkel (`CurrentUser` `auto_error=True`, `_resolve_internal_profile_id` 404-et ad, mielőtt a poszt megnézésre kerülne). Holt ág ma, fail-closed. Ha egy jövőbeli kör bekötné az anonim olvasást, a block-kihagyás helyes egy VALÓDI anonim hívóra, de nem szabad hitelesített hívóra újrahasznosítani.
- **Státusz:** nem blokkol, informatív.

## Gate-bizonyíték ellenőrzése

| Gate | Állított eredmény (implementer, §10.2) | Ellenőrizve (Claude, izolált `/tmp/review-e09-r11` klón) |
|---|---|---|
| format | zöld | ✅ zöld |
| analyze | zöld | ✅ zöld |
| `test/core/architecture_dependency_test.dart` | zöld | ✅ zöld |
| architecture | zöld | ✅ zöld |
| secrets | zöld | ✅ zöld |
| l10n | zöld | ✅ zöld |
| backend ruff format | zöld | ✅ zöld |
| backend ruff check | zöld | ✅ zöld |
| backend pytest (teljes backend suite) | zöld, 18 db `test_post_service.py` teszt | ✅ zöld, teljes backend suite (community + egyéb modulok) is zöld |
| scope-audit | (nincs implementer-oldali állítás) | ✅ OK, 0 violation (a stray SQLite-fájlok törlése után) |
| security-reviewer (risk=high, kötelező) | — | ✅ lefutott, FÜGGETLEN reprodukcióval erősítette F1-et |

## Merge-döntés (eredeti, javítás előtt)

**Merge TILOS** — 2 nyitott BLOCKER (F1, F2). A javító kört UGYANAZ a motor
(`minimax`) viszi, a leletlistával (F1-F4 kötelező javítás, F5-F6
informatív/nem blokkoló). A javítás után a gate-eket ÉS a scope-auditot
ÚJRA, friss izolált klónban futtatom, és ezt a jelentést frissítem
(APPROVED vagy újra CHANGES REQUESTED).

**A tényleges, ÉRVÉNYES verdikt a fájl tetején (Javító kör 1 zárása,
`e0bbbaad`) — APPROVED.** Lásd ott a részletes zárási táblázatot és a
független újramérés parancslistáját.
