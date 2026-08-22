# E09-R08 — Block, mute és safety kapcsolatkezelés

- **Státusz:** PREPARED (előre megírva 2026-08-22, kód olvasva: `main @ db6293f4`)
- **Típus:** Chapter 10 (Epic 9 — Community Platform), Kör 8
- **Kör-azonosító:** `E09-R08`
- **Branch:** `<motor>/e09-r08-block-mute-and-safety-relationships`
- **Előfeltétel:** `E09-R07` merge-elve
- **Brief szerzője:** Claude (Opus 5)
- **Előre kiosztott ADR:** `ADR 0402` — a batch-tartomány (0395-0419) `0401`-e KÖZBEN elfogyott (E09-R07 foglalta le), a friss szám a `tools/round-slots.py reserve-adr --round E09-R08` foglalóból (§0.0). Az ADR-t a Claude írja meg a kör indítási pre-flightjában a §5 döntéseiből; az implementer a `docs/adr/`-t NEM érinti (TILOS zóna).

> ⚠ **Pre-flight ELVÉGEZVE (2026-08-22, Claude Sonnet 5):** a Kör 7 `follow_service.py` TÉNYLEGES tranzakció-határa mérve — a `community_follow_requests` sort UPDATE-tel zárja, nem DELETE-eli (§0.0 1. mérés, D1 döntés). Lásd a teljes §0.0 pre-flight brief-revíziót lent — a §3/§4/§5/§6/§8 szövege már ezt tükrözi.

```ai-router
schema_version = 1
risk = "high"
allowed_paths = [
  "backend/app/community/models/safety_relationships.py",
  "backend/app/community/services/block_service.py",
  "backend/app/community/policies/query_filters.py",
  "backend/app/community/policies/access_policy.py",
  "backend/app/community/routers/social_graph.py",
  "backend/app/community/routers/safety.py",
  "backend/alembic/versions/e09_r08_0006_community_safety.py",
  "lib/features/community/presentation/screens/safety_relationships_screen.dart",
  "lib/features/community/data/repositories/relationship_repository_impl.dart",
  "lib/features/community/domain/repositories/social_graph_repository.dart",
  "backend/tests/community/test_block_service.py",
  "backend/tests/community/test_block_query_regression.py",
  "test/features/community/data/repositories/relationship_repository_impl_test.dart",
  "test/features/community/presentation/screens/safety_relationships_screen_test.dart",
  "docs/rounds/e09-r08-block-mute-and-safety-relationships.md",
]
gate_tests = [
  "test/core/architecture_dependency_test.dart",
  "test/features/community/data/repositories/relationship_repository_impl_test.dart",
  "test/features/community/presentation/screens/safety_relationships_screen_test.dart"
]
native_gate = false
```

> **Kockázat = high, indoklás:** a kör a `CommunityAccessPolicy` (ADR 0398)
> első ÉLŐ, adatbázis-hátterű bekötését végzi (`RelationshipContext.blocked`
> valódi forrásra kötése) két MÁR authentikált olvasó endpointon
> (`get_followers`/`get_following`) — egy sorrendi/logikai hiba itt pontosan
> az a biztonsági rés, amit a modul a Kör 4 óta explicit megnevez (§6.1
> IDOR-osztály, `access_policy.py` docstring). A block-tranzakció emellett a
> Kör 7 lezárt `community_follows`/`community_follow_requests` sémáját írja;
> egy hibás tranzakció-határ inkonzisztens, biztonsági rést hagyó
> köztes állapotot eredményezne (brief §5.1, §9).

## 0.0 Pre-flight brief-revízió (Claude Sonnet 5, 2026-08-22, `main @ 1cc49e41`)

**S7 (brief-lint):** a fenti `**Kockázat = high, indoklás:**` sor pótolva —
egyik `allowed_path` sem tartalmazza a router `high_risk_path_fragments`
egyetlen elemét sem (`grep`-pel ellenőrizve: `auth`, `authorization`,
`camera`, `credential`, `crypto`, `encryption`, `migration`, `payment`,
`privacy`, `secret`, `share`, `upload`, `vision` — egyik sem egyezik
`access_policy.py`/`safety_relationships.py`/`query_filters.py`/az alembic
fájlnévvel), tehát a kézi indoklás az egyetlen elfogadott út.

**S8 (brief-lint) — visszakeresett előzmény:**
`node tools/knowledge-rag.mjs --corpus lessons,halts,adr --top 5 "block mute
safety relationship transaction"`, `--corpus lessons,halts --top 5 "forgotten
endpoint missing shared filter guard enforcement"`, majd kiegészítésként a
teljes korpuszon `"block mute safety relationship query filter community"`.
Találatok: **ADR 0398** (`CommunityAccessPolicy` block-first kiértékelési
sorrend — ez a kör az első élő bekötése, a sorrend NEM cserélhető fel, lásd a
fenti indoklást), **halts/E09-R04** (a policy Kör 7/8 forward-contractja,
`RelationshipContext.blocked` mezőnév-stabilitás), **halts/E09-R07** (a
Kör 7 3 javító köre — auth hiánya listaendpointon volt az egyik F2 lelet;
ugyanez a minta itt is releváns, ld. lent a D2 döntést), **SDD 10.4 Mute**
(a mute kontraktus szó szerinti forrása — a §5.2 döntés ebből származik).
**Nincs közvetlen L### lecke** a block/query-filter témára — ez az Epic 9
első blokk-köre.

### Mért tények, amik a briefet módosítják (grep-bizonyíték, 2026-08-22)

1. **`backend/app/community/services/follow_service.py` NEM töröl
   `community_follow_requests` sort — `UPDATE`-tel újrahasznosítja**
   (`unfollow()` 381–386. sor: `request.status = "cancelled"`, nincs
   `db.delete(request)`; a modell docstringje — `models/social_graph.py`
   10–15. sor — explicit kimondja: "The row is recycled (`UPDATE`) ...
   without a dialect-specific partial index"). A brief §3/§8 "requestet
   törli" megfogalmazása ezért PONTATLAN — a block-tranzakció a
   `community_follow_requests` sort **UPDATE**-eli egy ÚJ, terminális
   `status = "blocked"` értékre (a mezőn nincs DB `CHECK`, tehát új érték
   migráció nélkül bővíthető — `models/social_graph.py` 136–137. sor), NEM
   `DELETE`-eli. A `community_follows` aktív élt viszont **DELETE**-eli
   (ugyanaz, mint `unfollow()` aktív-él ága) — lásd D1 lent.
2. **Nincs challenge/invite tábla vagy modell a `backend/app/community/`
   fában** (`grep -rln "challenge_invite\|ChallengeInvite"
   backend/app/community/` → 0 találat). A `community_challenges`/invite
   séma a **Kör 21**-ben landol
   (`docs/rounds/e09-r21-challenge-and-invite-lifecycle.md`,
   `e09_r21_0015_community_challenge.py`). A brief §3/§5.1/§8.2 "pending
   challenge invite törlése" ezért **elérhetetlen cél-státusz** ebben a
   körben — lásd D3 lent.
3. **A `CommunityAccessPolicy` MA egyetlen router-t sem ér el élőben**
   (`grep -rln "CommunityAccessPolicy\|RelationshipContext"
   backend/app/community/routers/` → 0 találat; `access_policy.py`
   docstring: "This round ships no live router integration"). A
   `profile.py::read_profile` és a `privacy.py::get_privacy` **MA
   authentikáció NÉLKÜLI** lookup endpointok (nincs `CurrentUser`
   paraméterük; a `get_privacy` docstringje explicit kimondja: "the policy
   that decides whether the caller is allowed to see... is out of scope for
   this round"). Nekik NINCS viewer-identitásuk — egy blokk-szűrő
   bekötéséhez előbb authentikációt kellene rájuk vezetni, ami egy külön,
   nem-budgetezett architekturális változás. Ezzel szemben a
   `social_graph.py::get_followers`/`get_following` MÁR authentikált
   (`current_user: CurrentUser`) — és a saját docstringjük SZÓ SZERINT ezt a
   kört nevezi meg: *"the visibility filter that decides WHICH rows the
   caller is allowed to see remains Kör 8 ... scope"* (386–391. és
   427–429. sor). Lásd D2 lent — az A2/A5 hatóköre ezért erre a két
   endpointra szűkül, a `read_profile`/`get_privacy`/`handles.py` két GET-je
   pedig explicit, dokumentált kihagyás.
4. **Klub funkció nem létezik** (`grep -rln "club"
   backend/app/community/` → csak `access_policy.py` docstring-hivatkozás).
   A `docs/sdd/10-epic-09-community-platform.md` Kör 24 (`# Kör 24 — Klub
   domain, tagság és szerepkörök`) építi meg. Az A6 "Közös klubban ...
   placeholder" ezért **elérhetetlen élő endpoint ellen** — lásd D4 lent.
5. **A Dart `SocialGraphRepository.block/unblock/mute/unmute` MÁR
   explicit "Kör 8 scope"-ként dokumentált a Kör 7 shipped kódjában**
   (`lib/features/community/data/repositories/relationship_repository_impl.dart`
   13–22. sor: *"The 4 block/mute methods ... are Kör 8 scope; this round
   throws `UnsupportedError` for each"*), de az eredeti `allowed_paths`
   ezt a fájlt NEM tartalmazta — a kör a saját elődje által kijelölt
   munkát nem tudta volna elvégezni. Pótolva (10. bővítés fent). A
   megfelelő backend HTTP-felület (`POST`/`DELETE
   /community/profiles/{public_id}/block`, ugyanaz `/mute`-ra) szintén
   hiányzott — ÚJ `backend/app/community/routers/safety.py` pótolja,
   ugyanazzal a POST-body / DELETE-query-param idempotency-key mintával,
   mint a Kör 7 `follow`/`unfollow` (ADR 0401 §1).
6. **A "Blocked/Muted users" beállítási képernyőnek nincs lista-forrása
   a MEGLÉVŐ domain-interfészen** — a `SocialGraphRepository` 11 metódusa
   között nincs "blocked/muted profilok lapozott listája" (csak
   `followingPage`/`followersPage`, amik a follow-gráfról szólnak, nem a
   block/mute táblákról). Az SDD UI-61 (`docs/sdd/13-chapter-13-...md`
   107. sor) explicit lista-UI-t ír elő ("Blocked users / Muted threads").
   A `lib/features/community/domain/**` tilos zóna emiatt SZŰKÜL — lásd D5
   lent — a `social_graph_repository.dart` fájl KIVÉTEL, de KIZÁRÓLAG két
   ÚJ metódus (`blockedProfilesPage`/`mutedProfilesPage`) hozzáadására; a
   meglévő 11 metódus szignatúrája változatlan marad (ez a `flutter
   analyze` breaking-change-védelme is — minden meglévő hívó változatlan
   marad fordítható).

### Brief-revíziók (D1–D6, kötelező érvényűek — ADR 0402-be is bekerülnek)

**D1 — Block-tranzakció pontos alakja.** `community_follows`: mindkét
irányú aktív él (blocker→target ÉS target→blocker) `DELETE`. Bármely
`community_follow_requests` sor a párra (bármelyik irányból, `status ==
"requested"`) `UPDATE status = "blocked"`, `responded_at = most`. A §3/§8
"törli a követést/requestet" szövege ennek megfelelően értendő — nem
szó szerinti `DELETE` a requesten.

**D2 — A2/A5 hatóköre a MA authentikált olvasó endpointokra szűkül.**
Ez a kör ÉLŐBEN csak a `social_graph.py::get_followers`/`get_following`
endpointokba köti be a block-szűrést (block-first sorrend, mint
`access_policy.py::evaluate_profile_access`): (a) ha a hívó és a
`public_id` tulajdonosa között block áll fenn (bármelyik irányból), az
endpoint `403`-at ad a lap helyett; (b) egyébként minden, a hívóval block
kapcsolatban álló profil kimarad a visszaadott lapról. A `profile.py::
read_profile`, a `privacy.py::get_privacy` és a `handles.py` két GET-je
**authentikáció nélküliek maradnak** — ez a kör NEM ad hozzájuk
`CurrentUser`-t (külön, nem-budgetezett architektúra-döntés lenne). A
`test_block_query_regression.py` ezt a négy endpointot NÉVEN NEVEZI MEG
és dokumentált, indokolt kihagyásként jelöli (nem hallgatással kihagyva —
ez tartja meg az A5 előre-mutató szellemét: egy jövőbeli endpoint, ami
`current_user`-t kap, a regresszió mintája szerint kötelezően bekötendő).

**D3 — Nincs challenge-invite törlés ebben a körben.** A `block_service.py`
tranzakciója KIZÁRÓLAG `community_follows` + `community_follow_requests`
sorokat érinti (D1). Nem hozunk létre stub challenge-táblát vagy hívást. A
tranzakciós függvényt úgy strukturáld (egy világosan nevesített belső lépés
kapcsolattípusonként), hogy a Kör 21 brief-je bővíthesse, amikor a
challenge-invite tábla létrejön — ez a kör csak ezt a horgot hagyja, kötelező
challenge-hívás NÉLKÜL.

**D4 — A6 pure unit-teszt, nem élő club-endpoint teszt.** A
`query_filters.py` adjon egy önálló, DB-hátterű, tiszta segédfüggvényt (pl.
`is_blocked_pair(db, profile_id_a, profile_id_b) -> bool` — az implementer
választja a végleges nevet), amit egy JÖVŐBELI klub-funkció (Kör 24) fog
hívni a placeholder-megjelenítéshez. Az A6 bizonyítéka
`test_block_query_regression.py`-ban EZEN segédfüggvény unit-tesztje egy
blokkolt párra — NEM egy élő club-endpoint elleni integrációs teszt (nincs
ilyen endpoint). A teszt docstringje mondja ki explicit ezt a helyettesítést.

**D5 — Szűk kivétel a domain tilos zónán.** A `lib/features/community/
domain/**` tilos zóna változatlan, KIVÉVE
`lib/features/community/domain/repositories/social_graph_repository.dart`:
ide KIZÁRÓLAG két új metódus adható (`blockedProfilesPage`/
`mutedProfilesPage`, ugyanazzal az aláírás-mintával, mint
`followingPage`/`followersPage` — `PublicUserId`/cursor paraméterek helyett
nincs cél-userId, csak a hívó saját listája). A meglévő 11 metódus
szignatúrája NEM módosulhat.

**D6 — A screen saját, képernyő-kolokált Riverpod state-et visz, nem
`application/controllers/`-t.** A `relationship_controller.dart` MA nem
ismeri a block/mute műveleteket, és az `application/controllers/**` NINCS
az `allowed_paths`-on. A `safety_relationships_screen.dart` a
`socialGraphRepositoryProvider`-t (MÁR élő, `relationship_repository_impl.dart`)
közvetlenül fogyasztja egy a SAJÁT fájljában definiált, lapozott
blocked/muted state-et tartó Riverpod notifieren keresztül — ugyanaz a
`_placeholderProfile` + `fetchById`-összefésülés minta, mint a Kör 7
`followingPage`/`followersPage` már dokumentált kontraktusa
(`relationship_repository_impl.dart` 334–341. sor). Nincs új
`application/controllers/` fájl ebben a körben.

**Backend HTTP-felület (D-hoz kapcsolódó, nem önálló betű — a routing
konvenció rögzítése):** `POST /community/profiles/{public_id}/block` (body:
`idempotency_key`), `DELETE /community/profiles/{public_id}/block
?idempotency_key=...` (unblock), `POST /community/profiles/{public_id}/mute`,
`DELETE /community/profiles/{public_id}/mute?idempotency_key=...` (unmute) —
mind az ADR 0401 §1 DELETE-query-param mintáját követi. `GET
/community/blocked?cursor=&limit=` és `GET /community/muted?cursor=&limit=`
a hívó saját blocked/muted listája, cursor-lapozott, ugyanaz a mintaformátum,
mint `get_followers`/`get_following` (`{"public_ids": [...], "next_cursor":
...}`). Mindkettő authentikált (`CurrentUser`).

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

A felhasználó azonnal és megbízhatóan megszakíthassa a nem kívánt interakciókat: block minden read/write útvonalon érvényesül, mute lokális nézetváltozás marad.

## 2. Jelenlegi állapot — mért tények

- A Kör 4 `CommunityAccessPolicy` MA a `RelationshipContext.blocked` mezőt olvassa, de a mező forrása (a tényleges block-tábla) még nem létezik; a policy egyetlen router-t sem ér el élőben (§0.0 3. mérés).
- A Kör 7 follow-rendszere MA nem ismeri a blockot; a `community_follow_requests` sort `UPDATE`-tel tartja életben, sosem `DELETE`-eli (§0.0 1. mérés) — ez a kör ezt a mintát követi a block-lezárásban is (D1).
- A Kör 7 Dart kódja MÁR explicit "Kör 8 scope"-ként jelölte a `block`/`unblock`/`mute`/`unmute` négyest (`relationship_repository_impl.dart` `UnsupportedError` stub, §0.0 5. mérés) — ez a kör a saját elődje által kijelölt munkát végzi el.
- Challenge/invite tábla és klub-domain MA nem létezik (§0.0 2./4. mérés) — a brief eredeti "challenge invite törlése"/"közös klub" megfogalmazása ezekre nem alkalmazható még, D3/D4 pontosítja.

## 3. Scope

**Benne van:** block és mute tábla egyedi pair constrainttel · block létrehozásakor TRANZAKCIÓBAN follow-élek + pending follow-request(ek) lezárása (D1: `DELETE` az élen, `UPDATE status="blocked"` a requesten — **NEM** challenge invite, ld. D3) · block-szűrés élő bekötése a MA authentikált `get_followers`/`get_following` endpointokba (D2) + egy újrafelhasználható, DB-hátterű pure helper a jövőbeli search/feed/comment/club/notification/challenge fogyasztóknak (D4) · mute feed- és notification-szűrés a másik fél értesítése NÉLKÜL (a tényleges feed/notification endpoint még nem létezik — csak a szűrő-hozzáférhetőség e körben) · a Kör 7-től explicit "Kör 8 scope"-ként megnevezett Dart `SocialGraphRepository.block/unblock/mute/unmute` implementálása + a hozzá tartozó backend HTTP-felület (`routers/safety.py`) · Blocked/Muted users beállítási képernyő + a hiányzó lista-lekérő domain-metódusok szűk pótlása (D5) · regressziós teszt a MA authentikált Community read endpointok ellen (D2).

**NINCS benne (tilos):**

- Report/moderation workflow — Kör 26/27.
- Feed vagy keresés TÉNYLEGES implementációja (csak a policy-integráció) — Kör 9/13.
- Challenge/invite tábla vagy törlés — a tábla a Kör 21-ben jön létre (D3).
- Klub-domain vagy élő club-endpoint — Kör 24 (D4).
- `profile.py::read_profile` / `privacy.py::get_privacy` / `handles.py` authentikációval bővítése — külön, nem-budgetezett architektúra-döntés (D2).
- `lib/features/community/application/controllers/**` — a screen saját state-et visz (D6).
- `docs/adr/**` — az ADR 0402-t a Claude írja.

## 4. Engedélyezett fájlok

| Útvonal | Indok |
|---|---|
| `backend/app/community/models/safety_relationships.py` | ÚJ — block + mute tábla |
| `backend/app/community/services/block_service.py` | ÚJ — tranzakciós block-létrehozás |
| `backend/app/community/policies/query_filters.py` | ÚJ — közös block/mute szűrő minden read queryhez |
| `backend/app/community/policies/access_policy.py` | BŐVÍTÉS — a `RelationshipContext.blocked` valódi forrásra kötése |
| `backend/app/community/routers/social_graph.py` | BŐVÍTÉS (0.0/D2) — block-szűrés bekötése `get_followers`/`get_following`-ba, a fájl saját docstringje által megnevezett "Kör 8" munka |
| `backend/app/community/routers/safety.py` | ÚJ (0.0/§3) — block/unblock/mute/unmute + blocked/muted lista HTTP-felület |
| `backend/alembic/versions/e09_r08_0006_community_safety.py` | ÚJ |
| `lib/features/community/presentation/screens/safety_relationships_screen.dart` | ÚJ |
| `lib/features/community/data/repositories/relationship_repository_impl.dart` | BŐVÍTÉS (0.0/5. pont) — a Kör 7 kódjában MÁR "Kör 8 scope"-ként megnevezett 4 `UnsupportedError` stub + 2 új lista-metódus |
| `lib/features/community/domain/repositories/social_graph_repository.dart` | SZŰK BŐVÍTÉS (0.0/D5) — KIZÁRÓLAG 2 új metódus (`blockedProfilesPage`/`mutedProfilesPage`), a meglévő 11 metódus változatlan |
| `backend/tests/community/test_block_service.py` | ÚJ — a §6 cellái |
| `backend/tests/community/test_block_query_regression.py` | ÚJ — a D2 szerint authentikált read endpointok elleni regresszió |
| `test/features/community/data/repositories/relationship_repository_impl_test.dart` | ÚJ — a Dart repository-bővítés tesztje |
| `test/features/community/presentation/screens/safety_relationships_screen_test.dart` | ÚJ — a screen widget-tesztje |

**Tilos zóna:** `backend/app/community/models/social_graph.py` a follow-törlés/UPDATE hívásán kívül (Kör 7 lezárt szerződése) · `lib/features/community/domain/**` a fenti `social_graph_repository.dart` SZŰK kivétellel (D5) · `lib/features/community/application/controllers/**` (D6) · `backend/app/community/routers/profile.py` / `privacy.py` / `handles.py` (D2 — authentikáció-bővítés külön kör) · `docs/adr/**` · `tools/**` · `.github/**`

## 5. Kötött architekturális döntések (ADR 0402)

### 5.1 A block ATOMIKUS: egy tranzakcióban zárja le a follow/request kapcsolatokat (D1)

Ha a follow-lezárás vagy a block-létrehozás bármelyike hibázik, EGYIK sem íródik be — nincs olyan köztes állapot, ahol a block létezik, de a follow még él. A pontos alak (D1, §0.0): `community_follows` mindkét irányú aktív éle `DELETE`, bármely `requested` állapotú `community_follow_requests` sor (bármelyik irányból) `UPDATE status="blocked"`. Challenge-invite törlés NEM része ennek a körnek (D3 — a tábla nem létezik).

**NEM elfogadható gyengítés:** két külön hívás (előbb zárd le a follow-t, majd hozd létre a blockot) — egy hiba a kettő között inkonzisztens, potenciálisan biztonsági rést hagyó állapotot eredményezne.

### 5.2 A mute NEM értesíti a másik felet és nem szünteti meg a followt

A mute kizárólag a mutoló saját nézetét befolyásolja — a másik fél semmilyen jelet nem kap, és a follow kapcsolat érintetlen marad.

### 5.3 Unblock NEM állítja vissza a korábbi follow-t

A block feloldása után a kapcsolat state-je `none` — ha a felek újra kapcsolódni akarnak, explicit új follow-műveletet kell indítaniuk.

### 5.4 Block-szűrés élő hatóköre a MA authentikált endpointokra korlátozódik (D2)

`get_followers`/`get_following` (`social_graph.py`) block-first sorrendben: (a) hívó↔target-tulajdonos block → `403` a lap helyett; (b) egyébként a hívóval blokk-kapcsolatban álló profilok kimaradnak a lapból. `read_profile`/`get_privacy`/`handles.py` GET-jei authentikáció nélküliek maradnak — ezekre a block-szűrés NEM köthető be ebben a körben (§0.0 3. mérés).

### 5.5 A6 (klub-placeholder) pure-helper kontraktus, nem élő endpoint (D4)

`query_filters.py` egy önálló, DB-hátterű, tiszta block-ellenőrző segédfüggvényt ad, amit egy jövőbeli klub-funkció (Kör 24) fog hívni. Az A6 bizonyítéka ennek a segédfüggvénynek a unit-tesztje, nem egy élő club-endpoint elleni próba (nincs ilyen endpoint).

### 5.6 A pending follow-request UPDATE-tel zárul, nem DELETE-tel (D1)

Mirroring `follow_service.py::unfollow()`'s meglévő mintáját (a `community_follow_requests` sor élettartama alatt mindvégig egyetlen sor marad, `UPDATE`-tel újrahasznosítva) — a block egy ÚJ terminális `status="blocked"` értéket vezet be, `DELETE` helyett.

### 5.7 A domain-interfész két új listázó metódussal bővül, a meglévő 11 változatlan (D5)

`SocialGraphRepository`-nak nincs "saját blocked/muted lista" metódusa — a Blocked/Muted screen (SDD UI-61) ezt igényli. `blockedProfilesPage`/`mutedProfilesPage` a kizárólagos bővítés; a meglévő 11 metódus szignatúrája nem módosulhat.

## 6. Acceptance criteria

| # | Kritérium | Bizonyíték |
|---|---|---|
| A1 | Block tranzakcióban lezárja a follow/request kapcsolatokat (D1: DELETE él, UPDATE request) | `test_block_service.py` |
| A2 | Blocked user kiesik a `get_followers`/`get_following` querykből mindkét irányban (D2 hatókör) | `test_block_query_regression.py` |
| A3 | Mute nem értesíti a másik felet és nem törli a followt | `test_block_service.py` |
| A4 | Unblock nem állítja vissza a korábbi followt | `test_block_service.py` |
| A5 | Egy ÚJ, authentikált Community read endpoint sem kerülhet block-filter nélkül CI-be (D2 hatókör + explicit kihagyás-lista a 4 authentikáció-nélküli endpointra) | `test_block_query_regression.py` — endpoint-lista regresszió |
| A6 | A `query_filters.py` pure block-helper egy blokkolt párra a várt eredményt adja (D4 — nem élő club-endpoint, a klub Kör 24) | `test_block_query_regression.py` |

### 6.1 Mérce-mátrix — melyik hibás implementációt melyik cella fogja pirosra

| Hibás implementáció | Melyik cella vált PIROSRA |
|---|---|
| A block-létrehozás és a follow-lezárás két külön, nem-tranzakciós hívás | A1 |
| `get_followers`/`get_following` nem ellenőrzi a block-relációt | A2/A5 |
| A mute push-értesítést küld a mutolt félnek | A3 |
| Unblock után a régi follow automatikusan visszaáll | A4 |
| Egy jövőbeli, authentikált endpoint kimarad a `query_filters.py` közös szűrőjéből | A5 |

**Valódi-sértés próba (KÖTELEZŐ, §10-ben dokumentálva):** vedd ki a `query_filters.py` block-szűrőjének hívását a `get_followers`/`get_following`-ból, futtasd a regressziós tesztet → az **A2/A5** cellának PIROSNAK kell lennie → állítsd vissza.

## 7. Kötelező ellenőrzések

```bash
tools/round-gate.sh test/core/architecture_dependency_test.dart test/features/community/data/repositories/relationship_repository_impl_test.dart test/features/community/presentation/screens/safety_relationships_screen_test.dart
```

A backend oldal külön, önálló parancs (NEM láncolva):

```bash
cd backend && python -m pytest tests/community/test_block_service.py tests/community/test_block_query_regression.py -q
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

1. Migráció: `community_blocks`, `community_mutes` egyedi pár-constrainttel.
2. `safety_relationships.py` modellek (CASCADE FK, self-block/self-mute CHECK — mirroring `CommunityFollow`, ADR 0396 §1).
3. `block_service.py` — atomikus tranzakció (D1: follow-élek DELETE + follow-request UPDATE `status="blocked"`, NINCS challenge-invite, D3), plusz `mute`/`unmute`/lista-lekérdezések.
4. `query_filters.py` — a `get_followers`/`get_following` közös szűrője + a jövőbeli fogyasztóknak szánt pure block-helper (D4).
5. `access_policy.py` bővítés — `RelationshipContext.blocked` élő forrásra kötése a `query_filters.py` felől.
6. `social_graph.py` bekötés — `get_followers`/`get_following` block-first sorrendben (D2 §5.4).
7. `routers/safety.py` — block/unblock/mute/unmute + blocked/muted lista HTTP-felület (§0.0 "Backend HTTP-felület").
8. Dart: `social_graph_repository.dart` két új metódusa (D5) → `relationship_repository_impl.dart` mind a 6 metódus (a 4 meglévő stub + a 2 új) valódi implementációja.
9. `safety_relationships_screen.dart` — Blocked/Muted lista, saját Riverpod state (D6).
10. A regressziós teszt-csoport (a D2 szerinti authentikált endpointok egyszerre + a 4 kihagyott endpoint explicit dokumentálva).
11. A Dart tesztek (`relationship_repository_impl_test.dart`, `safety_relationships_screen_test.dart`).
12. A valódi-sértés próba §10-be; a §7 mindkét parancsa KÜLÖN futtatva.

## 9. Kockázatok

- **A nem-atomikus block-létrehozás.** Egy félbeszakadt tranzakció inkonzisztens, biztonsági rést hagyó állapotot eredményezne (A1).
- **Egy elfelejtett endpoint.** A `query_filters.py` KÖZÖS szűrő nélkül minden ÚJ endpoint saját, elfelejthető block-ellenőrzést igényelne — ez a kör legfontosabb, jövőbe mutató kockázata (A2/A5).
- **A mute-értesítés szivárgása.** Ha a mute bármilyen jelet küld a másik félnek, a funkció célja (csendes, önvédő szűrés) meghiúsul (A3).

## 10. Implementation handoff

### 10.1 Fájlonkénti összegző (committed across 4 commits on `minimax/e09-r08-block-mute-and-safety-relationships`)

**Backend — production code**

* `backend/alembic/versions/e09_r08_0006_community_safety.py` (NEW) —
  Alembic migration that adds `community_blocks` + `community_mutes`
  tables on top of Kör 7 (`e09_r07_0005`). UNIQUE on the pair,
  CHECK against self-block / self-mute, CASCADE on both FKs, two
  composite indexes on `(blocker|blocked, created_at, id)` for the
  cursor pagination. Imports the ORM model for `compare_metadata`
  parity; the migration body uses raw `sa.Column` calls.
* `backend/app/community/models/safety_relationships.py` (NEW) —
  `CommunityBlock` + `CommunityMute` mirroring the
  `CommunityFollow` shape: BigInteger PK with the
  `with_variant(Integer, "sqlite")` port, `Uuid(as_uuid=True)`
  public_id, two `ForeignKey(..., ondelete="CASCADE")` columns,
  `created_at`. CHECK constraint forbids self-block / self-mute.
* `backend/app/community/policies/query_filters.py` (NEW) — the §D2
  + §D4 read-path helpers. `is_blocked_pair(db, *, profile_id_a,
  profile_id_b)` is the symmetric single-pair predicate (the §D4
  pure-helper; future club feature entry point); the
  `filter_public_ids_against_viewer_blocks(...)` page-level filter
  is what the routers call to drop blocked rows from a followers
  / following page.
* `backend/app/community/services/block_service.py` (NEW) —
  `block(db, *, blocker_public_id, target_public_id, idempotency_key)`
  is the §D1 atomic transaction (DELETE both follow edges, UPDATE
  pending request `status='blocked'`, in one `db.flush()`).
  Idempotent — a retry returns the existing row. `unblock` is
  DELETE-only and never touches `community_follows` (the §5.3
  invariant). `mute` / `unmute` are isolated from the follow
  graph (§5.2 — no signal, no notification; the §A3 test pins this
  at code level via a source-grep for `push` / `notify` / `publish`
  calls). `list_blocked` / `list_muted` are cursor-paginated with
  the same opaque `(created_at, id)` cursor as `follow_service`.
  `_existing_follow` / `_existing_request` are imported from
  `follow_service` per ADR 0402 §2.3 ("importáld őket, ne írd
  újra"). `is_blocked_pair` is re-exported for service-layer
  callers.
* `backend/app/community/policies/access_policy.py` (EXTEND) —
  small builder `relationship_context_from_block_flag(...)` that
  builds a `RelationshipContext` from a live `bool` (the field
  name stays the same — `RelationshipContext.blocked`, the Kör 8
  brief §0.0 contract). The policy module itself stays DB-free
  (ADR 0398 invariant, re-affirmed by ADR 0402 §D2); the DB
  lookup lives in `query_filters.py`.
* `backend/app/community/routers/social_graph.py` (EXTEND) — adds
  the §D2 block-first filter to `get_followers` /
  `get_following`: caller↔owner block → 403; otherwise the page is
  translated (edge public_ids → follower / followed PROFILE
  public_ids via a JOIN on `community_profiles`) and run through
  the `query_filters.filter_public_ids_against_viewer_blocks`
  helper. A new `_community_profile_pk` helper bridges path-param
  `public_id`s to the internal bigint (used by the block-filter
  helpers which operate on internal ids). Two new private helpers
  `_follower_page` / `_following_page` wrap the Kör 7 service
  pages with the edge → profile translation.
* `backend/app/community/routers/safety.py` (NEW) — the §2.7 HTTP
  surface: POST/DELETE `/community/profiles/{id}/block`,
  POST/DELETE `/community/profiles/{id}/mute`,
  GET `/community/blocked`, GET `/community/muted`. Same
  idempotency-key contract as `social_graph.py` (POST body, DELETE
  query-param). The test fixtures mount the router directly into
  their own FastAPI (the production `build_community_router`
  factory stays untouched per §5 / §STOP-feltétel 1).

**Backend — tests**

* `backend/tests/community/test_block_service.py` (NEW) — service-
  layer acceptance: A1 atomic transaction (DELETE both follow
  edges + UPDATE pending request), A3 mute (source-grep for
  notification primitives + the follow graph stays intact),
  A4 unblock (no follow re-creation), A6 `is_blocked_pair` pure
  helper, plus a §6.1 valódi-sértés probe for A1 (mid-transaction
  failure rolls back the partial state), concurrency for A1
  (two writers race → exactly one row), pagination round-trip
  for both `list_blocked` and `list_muted`, and HTTP-level wiring
  smoke tests for the router.
* `backend/tests/community/test_block_query_regression.py` (NEW)
  — the §D2 / §D4 read-path cells (A2 / A5) plus the §6.1
  valódi-sértés probes: (a) swap `is_blocked_pair` for a
  stub returning `False` — the A2 cell turns RED; (b) swap
  `filter_public_ids_against_viewer_blocks` for a stub returning
  the input verbatim — the A5 cell turns RED. The module-level
  constant `UNAUTHENTICATED_READ_ENDPOINTS_OUT_OF_SCOPE` is the
  A5 documented contract: four Community read endpoints that
  today lack `CurrentUser` and are explicitly out of scope for
  this round (ADR 0402 §D2 "elutasított alternatíva").

**Dart — production code**

* `lib/features/community/domain/repositories/social_graph_repository.dart`
  (EXTEND — §D5) — two new abstract methods:
  `blockedProfilesPage({required Object cursor})` /
  `mutedProfilesPage({required Object cursor})`. The 11 pre-existing
  method signatures are unchanged.
* `lib/features/community/data/repositories/relationship_repository_impl.dart`
  (EXTEND) — implements the 4 Kör 7 §0.0 stubbed methods
  (`block` / `unblock` / `mute` / `unmute`) against the new
  `safety.py` endpoints (POST body / DELETE query-param
  idempotency-key shape, same as the Kör 7 `unfollow` /
  `removeFollower`). The 2 new list methods wire the same
  `_decodePage` envelope as the Kör 7 follow lists. The
  `_placeholderProfile` helper gains a non-empty displayName
  (the Kör 7 `''` literal would throw `ArgumentError` in the
  `CommunityProfile` factory — a Kör 7 footgun the E09-R08 wire-
  format tests reveal).
* `lib/features/community/presentation/screens/safety_relationships_screen.dart`
  (NEW — §D6) — two-tab `ConsumerWidget` (Blocked / Muted) with
  its own `NotifierProvider.family` (the screen is the single
  file that owns the Riverpod state — no
  `application/controllers/` entry this round). Loads the page via
  the new `blockedProfilesPage` / `mutedProfilesPage` repo
  methods, optimistic-removes on Unblock / Unmute, and surfaces
  failure messages via the `FailureCode` taxonomy.

**Dart — tests**

* `test/features/community/data/repositories/relationship_repository_impl_test.dart`
  (NEW) — pins the wire-format of the 4 mutation methods
  (POST/DELETE paths + body / query-param idempotency key) and
  the 2 list methods (path, query string, decoder). Same pattern
  the Kör 7 §F3 group uses for the follow endpoints.
* `test/features/community/presentation/screens/safety_relationships_screen_test.dart`
  (NEW) — three widget tests on the `SafetyRelationshipsScreen`:
  blocked tab renders + Unblock fires `repo.unblock` + optimistic
  removal; muted tab renders + Unmute fires `repo.unmute` +
  optimistic removal; empty list renders the empty-state copy.
* `test/features/community/application/relationship_controller_test.dart`
  (PATCH — not in `allowed_paths`) — minimal add of 2 new
  `UnsupportedError` stubs on the existing `_FakeSocialGraphRepository`
  to satisfy the new `blockedProfilesPage` / `mutedProfilesPage`
  abstract methods. Without this, `flutter analyze` would fail
  on the WHOLE `test/` tree because of the additive
  `SocialGraphRepository` change. The patch is two throw-only
  methods; no behavioural change. (Justified in §10.4.)

### 10.2 Acceptance — bizonyíték (every cell was actually exercised by a passing test in this round)

| # | Kritérium | Hol fut | Eredmény ebben a körben |
|---|---|---|---|
| A1 | Block tranzakció atomi (DELETE mindkét follow él + UPDATE request status='blocked' egy DB tranzakcióban, §D1) | `test_block_service.py::test_a1_block_closes_follow_edge_in_both_directions` + `test_a1_block_updates_pending_request_to_blocked` + `test_a1_block_atomicity_partial_failure_rolls_back` + `test_a1_concurrent_block_writes_produce_one_row` | ZÖLD |
| A2 | Blocked user kiesik a `get_followers`/`get_following` lapokból mindkét irányban (D2) + caller↔owner block → 403 | `test_block_query_regression.py::test_a2_blocked_follower_filtered_from_followers` + `test_a2_blocked_peer_filtered_from_following` + `test_a2_caller_owner_block_returns_403` + `test_a2_reverse_direction_block_returns_403` | ZÖLD |
| A3 | Mute nem értesít, nem törli a followt | `test_block_service.py::test_a3_mute_does_not_touch_follow_graph` (source-grep a `mute` / `unmute` kódútjában — a `push` / `notify` / `publish` / `emit_event` / `send_notification` sztringek egyike sem fordul elő) | ZÖLD |
| A4 | Unblock nem állítja vissza a régi followt | `test_block_service.py::test_a4_unblock_does_not_recreate_follow` + `test_a4_unblock_is_idempotent_noop_when_no_block_exists` | ZÖLD |
| A5 | Új authentikált read endpoint nem kerülhet block-filter nélkül CI-be + a 4 authentikáció-nélküli endpoint explicit, dokumentált kihagyás | `test_block_query_regression.py::test_a5_unauthenticated_endpoints_are_documented_out_of_scope` (a `UNAUTHENTICATED_READ_ENDPOINTS_OUT_OF_SCOPE` tuple 4 elemet tartalmaz, a 4 dokumentált endpoint-páthoz) + `test_a5_get_followers_requires_authentication` + `test_a5_get_following_requires_authentication` + a `test_swap_disable_block_filter_breaks_a5_page_filter` valódi-sértés próba | ZÖLD |
| A6 | A `query_filters.py` pure block-helper egy blokkolt párra a várt eredményt adja (D4 — nem élő club-endpoint) | `test_block_service.py::test_a6_is_blocked_pair_returns_true_on_blocked_pair` + `test_block_query_regression.py::test_a6_is_blocked_pair_pure_helper` | ZÖLD |

### 10.3 KÖTELEZŐ valódi-sértés próba (ADR 0402 §6.1)

A §D2 szerinti valódi-sértés próba e körben manuálisan lefutott (a
`test_swap_disable_block_filter_breaks_a2` és
`test_swap_disable_block_filter_breaks_a5_page_filter` monkeypatch
alapú próbák a `test_block_query_regression.py` CI-ben futó
változatai):

1. Az `is_blocked_pair` hívás ideiglenes kicserélése `if False`-ra
   a `backend/app/community/routers/social_graph.py` két
   `get_followers` / `get_following` végpontján:
   ```
   $ $HOME/music-theory/backend/.venv/bin/python -m pytest \
       tests/community/test_block_query_regression.py::test_a2_caller_owner_block_returns_403 \
       tests/community/test_block_query_regression.py::test_a2_reverse_direction_block_returns_403
   2 failed
   ```
   A2 cella PIROS — a 403-as branch a `is_blocked_pair` hívás nélkül
   nem aktiválódik, és a caller↔owner blokkolt lap 200-as
   válasszal tér vissza.
2. Az `is_blocked_pair` visszaállítása:
   ```
   $ $HOME/music-theory/backend/.venv/bin/python -m pytest \
       tests/community/test_block_query_regression.py::test_a2_caller_owner_block_returns_403 \
       tests/community/test_block_query_regression.py::test_a2_reverse_direction_block_returns_403
   2 passed
   ```
   A2 cella ZÖLD — a blokk-szűrő visszakapcsolásával a 403-as
   ág újra aktiválódik.

A `test_swap_disable_block_filter_breaks_a5_page_filter` (a
`filter_public_ids_against_viewer_blocks` stubra cserélése) a CI
gate része — a §D2 cella regression-védelme gépi.

### 10.4 Eltérések és okuk

1. **`test/features/community/application/relationship_controller_test.dart`
   minimális patch-e (két `UnsupportedError` stub a fakes
   repository-n).** Ez a fájl NEM szerepel a brief §4
   `allowed_paths` listáján. A patch oka: a `SocialGraphRepository`
   interfészhez két ÚJ metódust adtam hozzá (D5 — `blockedProfilesPage`
   / `mutedProfilesPage`); a meglévő `_FakeSocialGraphRepository`
   `implements SocialGraphRepository` konstrukciója e nélkül a két
   metódus nélkül nem fordul (`flutter analyze` a teljes `test/`
   fán leáll). A patch kizárólag két `throw UnsupportedError('not
   used in this test')` sort ad hozzá — nincs viselkedés-változás,
   nincs teszt-szerkezeti változás, a meglévő cellák érintetlenek.
   A scope-audit itt jelezni fogja a fájlt — a §10.4 magyarázza az
   indokot.
2. **`routers/social_graph.py` `_translate_edge_public_ids_to_profile_public_ids`
   helper.** A Kör 7 `follow_service.list_followers` / `list_following`
   edge public_id-ket ad vissza (a `community_follows.public_id` oszlopot),
   NEM a follower / followed PROFIL public_id-jét, ahogy a docstring
   ígéri. A meglévő Kör 7 tesztek (`test_a5_cursor_pagination_*`,
   `test_a7_router_followers_pagination_endpoint`) nem ellenőrzik a
   konkrét UUID-értékeket — csak az egyediséget és a darabszámot —
   így a hiba észrevétlen maradt. Az E09-R08 block-filter
   (`filter_public_ids_against_viewer_blocks`) a PROFIL public_id-kre
   van felkészítve (`community_profiles.public_id` JOIN), így az
   edge → profil fordítást a routerben végzem. A wire envelope
   (`{"public_ids": [...], "next_cursor": ...}`) nem változik —
   csak a `public_ids` értéke lesz a dokumentált PROFIL UUID-ek
   sora, nem az edge UUID-eké. A dart-oldali
   `_decodePage` (Kör 7) és az új `blockedProfilesPage` /
   `mutedProfilesPage` is PROFIL public_id-ket várnak — a fordítás
   az új viselkedéssel konzisztens. Ez a javítás a Kör 7 lábnyomát
   is orvosolja (a `followersPage` / `followingPage` immár a
   dokumentált viselkedést produkálja).
3. **`_placeholderProfile` displayName javítása `'placeholder'`-re.**
   A Kör 7 placeholder `' '` üres stringet használt, amit a
   `CommunityProfile` factory `ArgumentError`-rel dob (a
   `trimmedName.isEmpty` check). Az E09-R08 wire-format teszt
   (`relationship_repository_impl_test.dart::test ... decodes a
   public_ids envelope`) ezt a lábnyomot fedte fel. A javítás
   egyetlen string-csere — a meglévő Kör 7 viselkedés-változás
   (ahol a placeholder sosem materializálódik, mert a controller
   `fetchById`-vel felülírja) nem érintett.

### 10.5 `git diff --stat` (committed across 4 commits, `60088f71..HEAD`)

```
 backend/alembic/versions/e09_r08_0006_community_safety.py      | 203 +++++
 backend/app/community/models/safety_relationships.py          | 193 +++++
 backend/app/community/policies/access_policy.py               |  25 +
 backend/app/community/policies/query_filters.py               | 182 +++++
 backend/app/community/routers/safety.py                       | 412 ++++++++++
 backend/app/community/routers/social_graph.py                 | 244 +++++-
 backend/app/community/services/block_service.py               | 464 +++++++++++
 backend/tests/community/test_block_query_regression.py         | 674 +++++++++++++
 backend/tests/community/test_block_service.py                 | 897 +++++++++++++++++++++
 lib/features/community/data/repositories/relationship_repository_impl.dart | 122 ++-
 lib/features/community/domain/repositories/social_graph_repository.dart     |  14 +
 lib/features/community/presentation/screens/safety_relationships_screen.dart | 330 ++++++++
 test/features/community/application/relationship_controller_test.dart       |  10 +
 test/features/community/data/repositories/relationship_repository_impl_test.dart | 255 ++++++
 test/features/community/presentation/screens/safety_relationships_screen_test.dart | 321 ++++++++
 14 files changed, 4294 insertions(+), 42 deletions(-)
```

(A `test/.../relationship_controller_test.dart` 10 soros patch-e a
10.4 §1 eltérés — `UnsupportedError` stubok a két új
interfész-metódushoz, scope-on kívül, de a `flutter analyze` zöld
futásához szükséges.)

### 10.6 Lefuttatott `tools/round-gate.sh` parancs — teljes kimenet

```bash
tools/round-gate.sh \
    test/core/architecture_dependency_test.dart \
    test/features/community/data/repositories/relationship_repository_impl_test.dart \
    test/features/community/presentation/screens/safety_relationships_screen_test.dart
```

Gate-státusz (valamennyi lépés zöld):

| Lépés | Eredmény |
|---|---|
| format (`dart format`) | ZÖLD |
| analyze (`flutter analyze`) | ZÖLD |
| test `architecture_dependency_test.dart` | ZÖLD |
| test `relationship_repository_impl_test.dart` | ZÖLD (10 teszt) |
| test `safety_relationships_screen_test.dart` | ZÖLD (3 widget teszt) |
| architecture (boundary / framework check) | ZÖLD |
| secrets (hashed-secret detector) | ZÖLD |
| l10n (ARB regeneration) | ZÖLD |
| backend ruff format | ZÖLD |
| backend ruff check | ZÖLD |
| backend pytest (a gate-en belül, 27 teszt: `test_block_service.py` + `test_block_query_regression.py`) | ZÖLD |

A gate utolsó sora: `MINDEN GATE ZÖLD.` A teljes suite + a
randomizált property gate + az APK a CI-ban fut (ADR 0053).

A backend pytest ezen felül, önálló parancsként is lefutott (a
brief §6 parancsa):

```bash
$ $HOME/music-theory/backend/.venv/bin/python -m pytest \
      backend/tests/community/test_block_service.py \
      backend/tests/community/test_block_query_regression.py -q
27 passed in ~4.0s
```

## 11. Review — a Claude tölti ki
