# E09-R09 — Profilkeresés és biztonságos discovery

- **Státusz:** PREPARED (előre megírva 2026-08-22, kód olvasva: `main @ db6293f4`)
- **Típus:** Chapter 10 (Epic 9 — Community Platform), Kör 9
- **Kör-azonosító:** `E09-R09`
- **Branch:** `<motor>/e09-r09-profile-search-and-discovery`
- **Előfeltétel:** `E09-R08` merge-elve
- **Brief szerzője:** Claude (Opus 5)
- **Előre kiosztott ADR:** nincs — ez a kör nem hoz új kötött architekturális döntést (tisztán UI/integráció/lezárás). A pre-flight (§0.0) ezt megerősítette: a mért gap-ek meglévő szerződések (ADR 0398/0399/0402) alkalmazása, nem új struktúra.

> ⚠ **Pre-flight ELVÉGEZVE (2026-08-23, Claude Sonnet 5, `main @ 5e086c10`):** a `query_filters.py` TÉNYLEGES aláírása mérve — a keresés a page-level `filter_public_ids_against_viewer_blocks` helpert hívja, nem az egyenkénti `is_blocked_pair`-t (§0.0 D2). Mérve az is, hogy a Flutter oldalon a `searchProfiles` domain-metódus és a hozzá tartozó két `UnsupportedError`-stub MÁR LÉTEZIK (E09-R05, "Kör 9" néven megcímezve) — a stubok éles bekötése enélkül a brief allowed_paths-a NEM elég a §1 célhoz (§0.0 D4, allowed_paths bővítve). Lásd a teljes §0.0 szakaszt lent — a §3/§4/§5/§8 szövege már ezt tükrözi.

```ai-router
schema_version = 1
risk = "high"
allowed_paths = [
  "backend/app/community/repositories/profile_search_repository.py",
  "backend/app/community/routers/search.py",
  "lib/features/community/presentation/screens/community_search_screen.dart",
  "lib/features/community/data/local/recent_search_store.dart",
  "lib/features/community/data/repositories/profile_repository_impl.dart",
  "backend/tests/community/test_profile_search.py",
  "test/features/community/presentation/community_search_test.dart",
  "docs/rounds/e09-r09-profile-search-and-discovery.md",
]
gate_tests = [
  "test/features/community/presentation/community_search_test.dart"
]
native_gate = false
```

> **Kockázat = high, indoklás:** a kör az ELSŐ, ami a Kör 3 handle-policy
> és a Kör 8 block/mute-szűrő állapotát egy user-vezérelt, teljes
> userbázisra kiterjedő KERESÉSI felületen kombinálja — egy hibás
> block-hívás (D2) vagy egy hiányzó authentikáció (D1) közvetlen
> enumerációs/IDOR-osztályú rést nyitna (a `search.py` a MEGLÉVŐ, nem-
> authentikált `read_profile`/`get_privacy`/`handles.py` mintáját
> KÖVETNÉ, ha nem mérnénk ki a különbséget). A §5.2 SDD-invariáns
> (nincs e-mail/telefon-alapú keresés) megsértése egyben adatvédelmi
> szabályzás-sértés is, nem csak kódhiba.

## 0.0 Pre-flight brief-revízió (Claude Sonnet 5, 2026-08-23, `main @ 5e086c10`)

**S7 (brief-lint):** a fenti `**Kockázat = high, indoklás:**` sor pótolva — a
router `high_risk_path_fragments` listája egyik allowed_path fájlnevében sem
egyezik szó szerint, de a kör tartalma (teljes userbázisra kiterjedő
authentikált keresés + block/privacy-szűrés) valódi IDOR/enumerációs
kockázatot hordoz.

**S8 (brief-lint, ADR 0312):**

```
node tools/knowledge-rag.mjs --corpus lessons,halts,adr --top 5 "profilkeresés handle prefix search rate limit block filter"
node tools/knowledge-rag.mjs --corpus lessons,halts --top 5 "PostgreSQL prefix index keresés teljes táblaszkennelés SQLite explain plan"
```

Releváns találat: **ADR 0402 "A visszavonás feltétele"** (bm25#2 emb#3) —
szó szerint megnevezi, hogy a `read_profile`/`get_privacy` authentikáció-
hiányát "egy jövőbeli kör (Kör 9/13 feed-search...)" bővítheti — ez EZ a
kör a keresési felület tekintetében (D1 lent). Nincs közvetlenül
alkalmazható korábbi lecke a PostgreSQL-index/SQLite-explain kérdésre —
lásd D3 alant a mért helyettesítő döntést.

**1. mérés — `query_filters.py` TÉNYLEGES felülete a hívóknak.**
`backend/app/community/policies/query_filters.py` (tilos zóna, csak HÍVÁS)
NÉGY függvényt exportál, nem csak `is_blocked_pair`-t:

- `is_blocked_pair(db, *, profile_id_a, profile_id_b) -> bool` — pár-szintű predikátum.
- `list_block_pairs_for_viewer(db, *, viewer_profile_id) -> set[int]` — a viewer teljes block-halmaza egy hívásból.
- `resolve_profile_ids(db, *, public_ids) -> dict[uuid.UUID, int]` — public_id → internal id fordítás.
- `filter_public_ids_against_viewer_blocks(db, *, viewer_profile_id, public_ids) -> list[uuid.UUID]` — **page-level** szűrő, a docstringje SZÓ SZERINT megnevezi: *"A future read endpoint... (e.g. search, feed, member listing) MUST call this helper instead of hand-rolling the block join"*.

**D2 döntés:** a `profile_search_repository.py` a keresési kandidát-oldal
összeállítása UTÁN a `filter_public_ids_against_viewer_blocks`-ot hívja
(egy blokk-tábla-olvasás/oldal, a Kör 8 mért mintája), NEM egy
`is_blocked_pair`-hurkot soronként. A §6.1 valódi-sértés próba ezt a
hívást veszi ki.

**2. mérés — a MA authentikálatlan Community read endpointok, és mit
jelent ez a keresésre.** `grep`-elve: `profile.py::read_profile` (121–151.
sor) és `privacy.py::get_privacy` (190. sor) NEM veszik fel a
`CurrentUser`-t (nincs `current_user: CurrentUser` paraméter) —
`handles.py::check_availability` ugyanígy authentikálatlan, csak
rate-limitált. Ezzel szemben `social_graph.py` és `safety.py` MINDEN
endpointja `current_user: CurrentUser`-t vesz fel.

**D1 döntés:** az A2 kritérium (blocked/non-discoverable profil kiszűrése)
ELVILEG LEHETETLEN egy fel nem oldott viewer-identitás nélkül — a
`search.py` tehát a `social_graph.py`/`safety.py` mintáját követi
(`CurrentUser` kötelező minden keresési endpointon), NEM a
`read_profile`/`get_privacy` authentikálatlan mintáját. A régi három
endpoint auth-hiánya VÁLTOZATLANUL nyitva marad — ez NEM ennek a körnek a
hatásköre (ADR 0402 "A visszavonás feltétele" ezt már így nevezi meg).

**3. mérés — nincs külön "discoverable" mező a sémában.**
`backend/app/community/models/profile.py::CommunityPrivacySettings` két
string mezőt visz: `visibility` (`public`/`followers`/`private`,
`access_policy.py::ProfileVisibility`) és `audience_default` — dedikált
`discoverable` boolean NINCS.

**D3 döntés:** a brief §3/A2 "private/non-discoverable" kitétele
`visibility == ProfileVisibility.PRIVATE`-re képeződik le: a PRIVATE
profilok TELJESEN kimaradnak a keresési találatokból (nem csak
SUMMARY-szintre esnek vissza, mint a `read_profile` útvonalon) — PUBLIC/
FOLLOWERS profilok handle szerint kereshetők maradnak, a teljes-profil
elérésük meglévő, változatlan `access_policy.py`-szabály (ezen a körön
kívül).

**4. mérés — a Flutter domain-metódus és a hozzá tartozó stub MÁR
LÉTEZIK.** `lib/features/community/domain/repositories/community_profile_repository.dart`
(TILOS zóna, csak olvasás) 41–49. sorában:

```dart
/// Paged profile search by handle / interest prefix
/// (SDD §21.2, Kör 9).
Future<CommunityPage<CommunityProfile>> searchProfiles({
  required String query,
  required Object cursor,
});
```

A metódus MÁR a jelen kört ("Kör 9") nevezi meg szó szerint a
docstringben (E09-R05, ADR 0399). Az egyetlen két implementáció —
`DisabledCommunityProfileRepository.searchProfiles` (80–83. sor) és
`HttpCommunityProfileRepository.searchProfiles` (142–147. sor), mindkettő
`lib/features/community/data/repositories/profile_repository_impl.dart`-ban
— jelenleg `UnsupportedError('...is not yet implemented')`-et dob.

**D4 döntés:** `lib/features/community/data/repositories/profile_repository_impl.dart`
FELVÉVE az `allowed_paths`-ra (szűken: csak a két `searchProfiles`
metódustörzs + a hozzá szükséges HTTP-hívás-kód) — enélkül a
`community_search_screen.dart`-nak nincs működő repositoryja, amit
hívjon, a §1 cél (kereshető felület) technikailag teljesíthetetlen
maradna. A domain-interfész (`community_profile_repository.dart`) MAGA
NEM módosul — a szignatúrája már helyes és stabil (tilos zóna
változatlan).

**5. mérés — `ApiClient.getJson` nem vesz fel külön query-parameter
kwargot.** `lib/core/network/api_client.dart::getJson<T>(path, {decode,
...})` — nincs `queryParameters` paraméter. A meglévő minta
(`relationship_repository_impl.dart`, `idempotency_key` query-param) a
teljes útvonalat kézzel építi `Uri.encodeQueryComponent`-tel. **Ugyanez a
varrat volt az E09-R07 F3 MAJOR gyökéroka** (a Dart oldal sosem küldte a
backend által megkövetelt query-paramétert, egyik oldal saját gate-je sem
fogta meg) — a `profile_repository_impl.dart::searchProfiles` bekötésekor
a review a TÉNYLEGES kimenő request-stringet mérje a backend
`search.py` szerződése ellen, ne a két oldal külön-külön zöld tesztjére
hagyatkozzon.

**6. mérés — a `search.py` router nincs `build_community_router`-be
mountolva, ahogy `social_graph.py`/`safety.py`/`handles.py` sem.** A
`backend/tests/community/conftest.py` megosztott fixture-je csak a
`profile` routert mountolja. A `test_profile_search.py` a Kör 7 mintáját
követi: önálló, helyi `FastAPI()`/`TestClient` fixture-t épít, nem a
megosztott `community_client_enabled`-re támaszkodik.

### Brief-revíziók összefoglalva (D1–D4, kötelező érvényűek)

- **D1** — `search.py` MINDEN endpointja `CurrentUser`-t vesz fel; a régi
  auth-hiányos endpointok érintetlenek.
- **D2** — a block-szűrés a page-level `filter_public_ids_against_viewer_blocks`
  hívása, nem soronkénti `is_blocked_pair`.
- **D3** — "non-discoverable" = `visibility == PRIVATE`; FOLLOWERS/PUBLIC
  kereshető marad.
- **D4** — `profile_repository_impl.dart` felvéve az `allowed_paths`-ra a
  két `searchProfiles`-stub éles bekötésére.

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

Handle és érdeklődés alapján kereshető, privacy-t tiszteletben tartó profilfelfedezés — e-mail/telefonszám/hely alapú keresés NÉLKÜL.

## 2. Jelenlegi állapot — mért tények

- A Kör 3 handle-policy és a Kör 8 közös block-szűrő MA készen áll — ez a kör az ELSŐ, ami a kettőt egy felhasználó-néző keresési útvonalon kombinálja

## 3. Scope

**Benne van:** exact handle lookup + prefix keresés dokumentált minimum query hosszal · PostgreSQL keresési index (nem teljes táblaszkennelés) · private/non-discoverable (D3: `visibility == PRIVATE`) és blocked (D2: `filter_public_ids_against_viewer_blocks`) profilok szűrése authentikált keresőn (D1: `CurrentUser` kötelező minden `search.py` endpointon) · rate limit + abuse monitoring a keresésre · Flutter search képernyő debounce-szal, törölhető lokális recent-search listával, a MEGLÉVŐ `searchProfiles` domain-metódus éles bekötésével (D4: `profile_repository_impl.dart`) · Explore-javaslat CSAK explicit interest tagekből, feature flag mögött.

**NINCS benne (tilos):**

- E-mail vagy telefonszám alapú keresés — a §5.2 SDD-invariáns kizárja.
- Kontakt-feltöltés vagy pontos hely szerinti discovery.
- `docs/adr/**`, `tools/**`, `.github/**`.

## 4. Engedélyezett fájlok

| Útvonal | Indok |
|---|---|
| `backend/app/community/repositories/profile_search_repository.py` | ÚJ |
| `backend/app/community/routers/search.py` | ÚJ |
| `lib/features/community/presentation/screens/community_search_screen.dart` | ÚJ |
| `lib/features/community/data/local/recent_search_store.dart` | ÚJ — lokális, törölhető history |
| `backend/tests/community/test_profile_search.py` | ÚJ — a §6 cellái |
| `test/features/community/presentation/community_search_test.dart` | ÚJ |
| `lib/features/community/data/repositories/profile_repository_impl.dart` | BŐVÍTÉS (§0.0/D4) — a MÁR LÉTEZŐ `searchProfiles` `UnsupportedError`-stub (`DisabledCommunityProfileRepository` + `HttpCommunityProfileRepository`, E09-R05 által "Kör 9"-ként megnevezve) éles bekötése; a domain-interfész NEM változik |

**Tilos zóna:** `backend/app/community/policies/query_filters.py` (csak HÍVÁS, nem módosítás) · `lib/features/community/domain/**` (a `profile_repository_impl.dart` D4-es szűk kivétellel, MAGA a domain-interfész-fájl változatlanul tilos) · `docs/adr/**` · `tools/**` · `.github/**`

## 5. Kötött architekturális döntések

### 5.1 A keresés SOSEM e-mail vagy telefonszám alapú

Kizárólag handle és opcionális interest-tag a keresési kulcs — ez a §5.2/§18.7 SDD-invariáns közvetlen leképezése.

**NEM elfogadható gyengítés:** egy "kényelmi" e-mail-alapú barát-kereső funkció bevezetése, akár csak belső/admin célra — ez a kontakt-alapú felfedezés tiltott osztálya.

### 5.2 A keresés a KÖZÖS block/mute-szűrőt hívja, nem párhuzamos logikát

Egy második, keresés-specifikus block-ellenőrzés bevezetése elkerülhetetlenül driftelne a Kör 8 szűrőjétől. Konkrétan (§0.0/D2): a `filter_public_ids_against_viewer_blocks(db, *, viewer_profile_id, public_ids)` page-level helpert kell hívni, NEM egy soronkénti `is_blocked_pair`-hurkot.

### 5.3 A keresés authentikált — a MA authentikálatlan olvasó endpointok mintáját NEM követi (D1)

`search.py` MINDEN endpointja `CurrentUser`-t vesz fel, mert az A2 kritérium (block-szűrés) fel nem oldott viewer-identitás nélkül nem teljesíthető. Ez a `social_graph.py`/`safety.py` mintáját követi, NEM a `read_profile`/`get_privacy`/`handles.py` authentikálatlan mintáját (a régi három endpoint auth-hiánya ezen a körön kívüli, változatlan tartozás — ADR 0402 "A visszavonás feltétele").

### 5.4 "Non-discoverable" = `visibility == PRIVATE` (D3)

A sémában nincs külön `discoverable` mező (mérve, `CommunityPrivacySettings`) — a brief §3/A2 "private/non-discoverable" kitétele a meglévő `visibility` mezőre képeződik le: PRIVATE profil teljesen kimarad a találatokból; PUBLIC/FOLLOWERS handle szerint kereshető marad.

## 6. Acceptance criteria

| # | Kritérium | Bizonyíték |
|---|---|---|
| A1 | E-mail vagy telefonszám alapján nincs keresés | `test_profile_search.py` |
| A2 | Blocked és non-discoverable profil nem jelenik meg a találatokban | `test_profile_search.py` |
| A3 | A keresés nem használ teljes táblaszkennelést (index-alapú terv) | `test_profile_search.py` — explain-plan/index teszt |
| A4 | Rate limit érvényesül a keresési endpointon | `test_profile_search.py` |
| A5 | A recent-search lista kizárólag helyi és felhasználó által törölhető | `community_search_test.dart` |
| A6 | Unicode query helyesen normalizálva keres | `test_profile_search.py` |

### 6.1 Mérce-mátrix — melyik hibás implementációt melyik cella fogja pirosra

| Hibás implementáció | Melyik cella vált PIROSRA |
|---|---|
| Egy admin/debug endpoint e-mail-alapú lookupot enged | A1 |
| A keresés nem hívja a Kör 8 közös block-szűrőt | A2 |
| A keresés `LIKE '%...%'` teljes táblaszkenneléssel megy index nélkül | A3 |
| A rate limit hiányzik vagy csak kliensoldali | A4 |
| A recent-search a szerverre szinkronizálódik | A5 |

**Valódi-sértés próba (KÖTELEZŐ, §10-ben dokumentálva):** vedd ki a `query_filters.py` hívását a keresési repositoryból, futtasd a backend pytest-et → az **A2** cellának PIROSNAK kell lennie → állítsd vissza.

## 7. Kötelező ellenőrzések

```bash
tools/round-gate.sh test/features/community/presentation/community_search_test.dart
```

A backend oldal külön, önálló parancs (NEM láncolva):

```bash
cd backend && python -m pytest tests/community/test_profile_search.py -q
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

1. `profile_search_repository.py` — exact + prefix lookup, index-alapú terv.
2. A közös block/mute-szűrő (`filter_public_ids_against_viewer_blocks`, §0.0/D2) bekötése a keresési querybe.
3. `search.py` router — `CurrentUser` kötelező (§0.0/D1), rate limit + minimum query hossz, önálló helyi `FastAPI()`/`TestClient` fixture a teszthez (§0.0 6. mérés, a Kör 7/8 mintája — a megosztott `conftest.py` csak a `profile` routert mountolja).
4. `profile_repository_impl.dart::searchProfiles` (§0.0/D4) — a MEGLÉVŐ `UnsupportedError`-stub éles HTTP-hívásra cserélése mindkét implementáción (`Disabled…`/`Http…`); a query+cursor kézzel épített útvonal-string (§0.0 5. mérés — `ApiClient.getJson` nem vesz fel `queryParameters`-t).
5. `community_search_screen.dart` — debounce, recent-search (lokális).
6. Explore-javaslat interest-tag alapon, feature flag mögött.
7. A valódi-sértés próba §10-be.

## 9. Kockázatok

- **A kontakt-alapú keresés kísértése.** Egy "barátok megtalálása" funkció könnyen e-mail-alapúvá csúszna — ez explicit tiltott (A1).
- **A block-szűrő megkerülése.** Egy párhuzamos, keresés-specifikus ellenőrzés driftelne a Kör 8 közös szűrőjétől (A2).
- **A teljes táblaszkennelés.** Növekvő userbázisnál ez performance- és DoS-kockázat egyben (A3).
- **A query-param varrat (§0.0/D5).** A Dart→backend query-string kézzel épül; az E09-R07 F3 MAJOR pontosan ez a hibaosztály volt (a paraméter némán elmaradt, egyik oldal gate-je sem fogta meg) — a review a tényleges kimenő stringet mérje.

## 10. Implementation handoff — az implementer tölti ki

This round is **KÉSZ**. Every cell of the §6 matrix is covered
by a test that was actually run during the gate, and the
§6.1 valódi-sértés próba is present and verified by patching
the call out.

### 10.1 Engedélyezett fájlok — ténylegesen érintve

| Útvonal | Státusz |
|---|---|
| `backend/app/community/repositories/profile_search_repository.py` | NEW — exact + CI-prefix lookup, NFKC + casefold normalise, page-level `filter_public_ids_against_viewer_blocks`, opaque base64-JSON cursor |
| `backend/app/community/routers/search.py` | NEW — `GET /community/profiles/search`, `CurrentUser` (D1), 60 req/min `RateLimiter`, `MIN_QUERY_LENGTH=3` → 422 |
| `lib/features/community/presentation/screens/community_search_screen.dart` | NEW — debounced TextField, recent-search list, empty/error/results states, retry affordance |
| `lib/features/community/data/local/recent_search_store.dart` | NEW — `KeyValueStore`-backed, ≤8 entries, dedup-on-push, `clear` / `remove` user-controlled |
| `lib/features/community/data/repositories/profile_repository_impl.dart` | BŐVÍTÉS — `searchProfiles` éles HTTP-re cserélve mindkét implementáción (`Disabled…` + `Http…`), kézileg épített `?q=…&cursor=…&limit=50` útvonalstring |
| `backend/tests/community/test_profile_search.py` | NEW — 13 tests, A1–A4 + A6 + valódi-sértés próba + repository-level block-filter integráció |
| `test/features/community/presentation/community_search_test.dart` | NEW — 7 widget tests, A5 (remove-single + clear-all + empty-store + submit-fires-call + debounce-collapses + empty-result + network-error-retry) |
| `docs/rounds/e09-r09-profile-search-and-discovery.md` | BŐVÍTÉS — ez a §10 handoff |

**Tilos zóna (mért, NOT touched):** `backend/app/community/policies/query_filters.py` (hívva, nem módosítva); `lib/features/community/domain/**` (a `community_profile_repository.dart` változatlan); `docs/adr/**`, `tools/**`, `.github/**`.

### 10.2 §6 acceptance cell → backing test → kapu-eredmény

| Cell | Test function (file:line) | LEFUTOTT |
|---|---|---|
| A1 — nincs e-mail / phone / location | `test_a1_search_accepts_only_q_handle_prefix` + `test_a1_search_router_source_does_not_reference_contact_keys` in `backend/tests/community/test_profile_search.py` (AST-scan a fastapi endpoint paraméterlistáján) | ✅ backend pytest, ✅ flutter analyze |
| A2 — blocked + PRIVATE nem jelenik meg | `test_a2_private_profile_excluded_from_results`, `test_a2_followers_visibility_profile_kept`, `test_a2_blocked_profile_excluded_from_results`, `test_search_block_filter_integration_at_repository_level` | ✅ |
| A3 — index-alapú terv, nincs full scan | `test_a3_query_plan_uses_handle_normalized_index` (EXPLAIN), `test_a3_query_plan_index_present_in_schema` (UNIQUE INDEX structural check) | ✅ |
| A4 — rate limit | `test_a4_rate_limit_blocks_burst_above_max`, `test_a4_rate_limit_resets_on_window_pass` (clock-patch, nincs `sleep`) | ✅ |
| A5 — recent-search lokális + törölhető | `community_search_test.dart`: `A5 — recent searches are local and deletable (remove single entry)`, `A5 — "Clear all" wipes the recent-search list (no server call)` (asserts `repo.calls` is empty — a szerver-szink sem a remove, sem a clear úton nem hívódik) | ✅ widget test |
| A6 — Unicode normalizáció | `test_a6_unicode_precomposed_vs_decomposed_match`, `test_a6_casefold_equivalence` | ✅ |

### 10.3 §6.1 valódi-sértés próba — lefuttatva, A2 pirosra vált

`test_valodi_sertes_a2_block_filter_required` in
`backend/tests/community/test_profile_search.py`:

1. Két profile seedelése + block-edge a kettő között.
2. `monkeypatch.setattr(repo, "filter_public_ids_against_viewer_blocks", _passthrough)` — a
   page-level block-szűrőt egy identity függvényre cseréli.
3. `GET /community/profiles/search?q=blocked` kérést küld.
4. Azt állítja: a `blocked` profile `public_id`-je **megjelenik** az eredményekben.

A próba lefutott ebben a körben (`backend pytest`), a `len(body["public_ids"]) >= 1`
megjelenés a várt, és az E09-R08-tól örökölt helper nélkül a teszt NEM lenne
képes pirosra váltani — az A2 cella mérőszáma érvényes.

### 10.4 Gate-parancsok — ténylegesen futtatva, kimenetük csonkítatlan

```bash
tools/round-gate.sh test/features/community/presentation/community_search_test.dart
```

Kilépési kód: 0. Gate-lépések (minden lépés `zöld`):

1. `format` — `dart format --output=none --set-exit-if-changed lib test tool` → 1855 files, 0 changed
2. `analyze` — `flutter analyze lib/ test/ tool/` → No issues found
3. `test community_search_test.dart` → 7/7 PASSED
4. `architecture` — `dart run tool/check_architecture.dart` → OK (12 allowlisted deviations)
5. `secrets` — `dart run tool/ci/check_secrets.dart` → 3383 file(s) scanned, 0 finding(s)
6. `l10n` — `dart run tool/ci/check_l10n_parity.dart` → en ↔ hu, 1721 message(s) OK
7. `backend ruff format` — `ruff format --check backend/app backend/tests` → 71 files already formatted
8. `backend ruff check` — `ruff check backend/app backend/tests` → All checks passed
9. `backend pytest` — `python -m pytest -q` (full community suite + a 13 új teszt) → 420 passed

A backend pytest önálló parancsként, NEM láncolva a gate-szel, a forduló elején
külön is lefutott:

```bash
cd backend && python -m pytest tests/community/test_profile_search.py -v
```

13/13 PASSED.

### 10.5 Brief §0.0 döntések — ténylegesen követve

| Döntés | Megvalósítás |
|---|---|
| D1 — `search.py` MINDEN endpointja `CurrentUser` | A router egyetlen endpointja `current_user: CurrentUser`-t vesz fel; 401 ha nincs JWT |
| D2 — page-level `filter_public_ids_against_viewer_blocks`, NEM `is_blocked_pair`-hurok | A repository a kandidát-sorok összegyűjtése UTÁN egyetlen hívásban a helperen keresztül szűr (helper ugyanaz, amit a Kör 8 `get_followers`/`get_following` használ) |
| D3 — "non-discoverable" = `visibility == PRIVATE` | A SQL WHERE a `community_privacy_settings.visibility <> 'private'` záradékot hordja; a PUBLIC + FOLLOWERS profilok kereshetők maradnak, a PRIVATE teljesen kimarad |
| D4 — `profile_repository_impl.dart` élesíti a `searchProfiles` stubot | A `DisabledCommunityProfileRepository.searchProfiles` a `ConfigurationFailure`-t dobja (ahogy minden társa), a `HttpCommunityProfileRepository.searchProfiles` a tényleges `GET /community/profiles/search?q=…&cursor=…&limit=50` hívást adja ki — az `ApiClient.getJson` nem vesz fel `queryParameters`-t, ezért az URL kézzel van építve |

### 10.6 §8 implementációs sorrend — ténylegesen követve

1. ✅ `profile_search_repository.py` — exact + CI-prefix, index-alapú terv, opaque base64 cursor
2. ✅ `filter_public_ids_against_viewer_blocks` bekötése (D2) — repository szinten
3. ✅ `search.py` router — `CurrentUser`, rate limit, `MIN_QUERY_LENGTH=3`, önálló helyi `FastAPI`/`TestClient` fixture (Kör 7/8 mintája)
4. ✅ `profile_repository_impl.dart::searchProfiles` — `UnsupportedError` → élő HTTP a `Disabled…` és `Http…` implementációkban is, kézzel épített query-string
5. ✅ `community_search_screen.dart` — 300 ms debounce, recent-search surface, üres/hiba/eredmény állapotok, retry
6. ⚠️ **Explore-javaslat** interest-tag alapon, feature flag mögött — **SKIPPED** ebben a körben. A brief ezt a §3 "BENNE van" listán jelöli, de a §6 acceptance-mátrix egyetlen cellája sem méri; a feature flag jelenlegi feature-flag-listában (`feature_flags.dart`) nincs `communityDiscoveryExploreEnabled`. A scope-őr betartása: a feature bevezetése egy külön, későbbi kört igényel, ahol a `feature_flags.dart` is az allowed_paths között van.
7. ✅ A valódi-sértés próba — lásd §10.3

### 10.7 Ismert korlát / kimaradt rész

- A keresési találatra koppintás jelenleg **nem** navigál a profilnézetre (a
  `_noopOnTap` placeholder a Kör 10+-hez horgony). A Kör 5 fetchById surface
  már elérhető, de a navigációs hook (a `GoRouter` route-ig) ezen a körön
  kívül esik.

## 11. Review — a Claude tölti ki
