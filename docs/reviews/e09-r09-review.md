# E09-R09 — Review

Brief: docs/rounds/e09-r09-profile-search-and-discovery.md
Diff: `git diff 2e8c3810...minimax/e09-r09-profile-search-and-discovery` (2e8c3810 = pre-flight commit, already on `main`)
Reviewer: Claude Sonnet 5 · Dátum: 2026-08-23
Verdikt: APPROVED (javító kör 1 után, `7145eacc`)

## Összegzés

BLOCKER: 2 (F1 UI placeholder, F4 cursor block-filter leak) — MINDKETTŐ FIXED `7145eacc`-ban · MAJOR: 0 · MINOR: 1 (F2, FIXED) · NOTE: 2 (F3 FIXED mellékesen, CI-completeness saját mulasztás pótolva)

Dedikált `security-reviewer` agent (risk=high) is lefutott — a jelentése a
saját BLOCKER-t hozott (F4 lent). CI (`full-gate.yml` run 32612083350) PIROS
volt: a `Run Flutter quality gates` és a `Coverage` lépés is elbukott a
MEGLÉVŐ, körön kívüli `test/ui/ui_inventory_test.dart:14` hardcode-olt
production-screen-számláló driftjén (68→69) — a kör saját ÚJ
`community_search_screen.dart` fájlja miatt, UGYANAZ a mintázat, mint az
E09-R06 F9 / E09-R07 3. javító köre / E09-R08 CI-only fixe.

**Saját mulasztás mérve (§3.0 tervező helyett `full-gate.yml`-t hívtam
csak):** a `backend-ci.yml` munkafolyamat (`backend/**` útvonalakra
triggerel) EBBEN a dispatch-ben NEM futott le — a `round-ci-plan.py` kimenete
csak a `full-gate.yml`/`build-apk.yml` párost nevezi meg, a `backend-ci.yml`-t
nem. A kör diffje `backend/app/community/**` + `backend/tests/community/**`
fájlokat érint, tehát ez a workflow is a zöld kapu RÉSZE (ugyanaz az elv, mint
a `router-ci.yml`-nél: a merge SHA-ján `success` kell legyen). A javító kör
utáni exact-SHA dispatch-nek mindhármat (`full-gate.yml`, `backend-ci.yml`, és
— ha a diff érinti — `router-ci.yml`) le kell fednie merge előtt.

## Acceptance criteria

| # | Kritérium | Teljesült | Bizonyíték |
|---|---|---|---|
| A1 | E-mail/telefon alapján nincs keresés | ✅ | `test_a1_search_accepts_only_q_handle_prefix`, `test_a1_search_router_source_does_not_reference_contact_keys` (AST-scan) — `backend/tests/community/test_profile_search.py:217,271` |
| A2 | Blocked + non-discoverable (PRIVATE) kimarad | ✅ (javító kör 1 után) | `public_ids`/`hits` szűrés + F1 valós UI-adat + F4 opak, kept-set-alapú cursor mind zöld; `test_f4_cursor_omits_blocked_profile_handle_and_pk` a security-reviewer pontos forgatókönyvét pinneli |
| A3 | Index-alapú terv, nincs full scan | ✅ | `test_a3_query_plan_uses_handle_normalized_index` (EXPLAIN QUERY PLAN), `test_a3_query_plan_index_present_in_schema` — `profile_search_repository.py:280-314` |
| A4 | Rate limit érvényesül | ✅ | `test_a4_rate_limit_blocks_burst_above_max`, `test_a4_rate_limit_resets_on_window_pass` — `search.py:75-83`; ld. F2 (MINOR) a doc/kód eltérésről |
| A5 | Recent-search lokális, törölhető | ✅ | `recent_search_store.dart` (SharedPreferences-only, `clear`/`remove`), 2 widget test a "no server call" assertióval |
| A6 | Unicode normalizáció | ✅ | `test_a6_unicode_precomposed_vs_decomposed_match`, `test_a6_casefold_equivalence` |
| §6.1 | Valódi-sértés próba (A2, block-filter kivétele) | ✅ | `test_valodi_sertes_a2_block_filter_required` — `filter_public_ids_against_viewer_blocks` monkeypatch-elve identitásra, a blocked profil megjelenik, majd visszaállítva |

## Scope-audit

```
tools/scope-audit.py --repo <klón> --brief docs/rounds/e09-r09-profile-search-and-discovery.md --base 2e8c3810
→ Legacy scope audit OK (2e8c3810099a..d680e5e7e609, 8 changed path(s), 0 generated/ignored)
```

Engedélyezett fájlokon kívüli változás: **nincs.** Mind a 8 érintett fájl a
brief `allowed_paths`-ában szerepel (a §0.0/D4 szerint bővített lista
tartalmazza a `profile_repository_impl.dart`-ot). `docs/adr/**`, `tools/**`,
`.github/**`, `lib/features/community/domain/**` érintetlen.

## Megállapítások

### F1 — BLOCKER — A keresési találatok minden sora azonos, fabrikált placeholder-adatot jelenít meg, nem a valós egyező profilt

- **Fájl:** `lib/features/community/data/repositories/profile_repository_impl.dart:295-315` (`_placeholderProfile`), hívva a `_decodePage` metódusból (261-271. sor); megjelenítve `lib/features/community/presentation/screens/community_search_screen.dart:380-392` (`_ResultsList` — `profile.displayName`, `profile.handle.value`).
- **Probléma:** a backend `GET /community/profiles/search` válasza kizárólag `public_ids` listát ad vissza (`search.py:190-196`) — se handle-t, se display name-et. A Dart repository ezt a hiányt egy **konstans, fix stringű** placeholderral tölti ki:
  ```dart
  CommunityProfile _placeholderProfile(PublicUserId userId) {
    return CommunityProfile(
      userId: userId,
      handle: CommunityHandle('placeholder-x1'),
      displayName: 'placeholder',
      ...
  ```
  A `_decodePage` MINDEN `public_id`-re ugyanezt a factory-t hívja — a `userId` mező az egyetlen, ami valóban az adott találatot azonosítja. A repository-fájl saját docstringje (`profile_repository_impl.dart:277-283`) azt állítja, hogy *"the controller follow-up-fetches each entry through the canonical fetchById path"* — ez a screen kódjában NEM történik meg: a `_ResultsList.itemBuilder` közvetlenül `items[index].displayName` / `.handle.value`-t renderel (380-392. sor), az `onTap` egy dokumentáltan no-op stub (`_noopOnTap`, 407-414. sor), és sehol nincs per-item `fetchById` hívás a screen-ben.
- **Hatás:** egy felhasználó, aki pl. `"alice"`-ra keres, egy N elemű listát kap, amiben MINDEN sor `"placeholder"` névvel és `"@placeholder-x1"` handle-lel jelenik meg — a találatok vizuálisan megkülönböztethetetlenek egymástól és a keresett névtől. A funkció a §1 célt ("Handle és érdeklődés alapján kereshető... profilfelfedezés") ténylegesen nem szolgálja ki — a backend logika (szűrés, block, index, rate limit) helyes, de a felhasználó számára a funkció használhatatlan.
- **Miért nem fogta meg egyetlen zöld teszt sem:** a widget teszt (`test/features/community/presentation/community_search_test.dart:119-167`) egy `_FakeCommunityProfileRepository`-t használ, ami VALÓDI, megkülönböztethető `CommunityProfile`-okat ad vissza (`CommunityHandle('alice-$suffix')`, `displayName: 'Alice $suffix'`) — tehát a screen renderelő logikáját helyesen teszteli, de sosem futtatja át a valódi `HttpCommunityProfileRepository._decodePage`/`_placeholderProfile` útvonalat. A backend teszt (`test_profile_search.py`) csak a `public_ids` listát ellenőrzi, sosem a UI-n megjelenő nevet. A két oldal saját zöld tesztje között pontosan az a varrat maradt fedetlen, amit a `docs/LESSONS.md` E08-R28 F1 mintája ("wire-szerződés két fele külön diffben szétcsúszik, még akkor is, ha ugyanaz a kör írja mindkettőt") már megnevez.
- **Kötelező javítás (irány, NEM kész patch):** vagy (a) a backend `search.py` válasza bővül `handle`/`display_name` (esetleg `avatar_url`) mezőkkel — a legegyszerűbb, mert egy keresési index tipikusan ezt adja vissza, és a repository `_decodePage`-je ezekből építi a valódi `CommunityProfile`-t placeholder helyett; vagy (b) a screen/controller a kapott `public_id`-ket egy batch/soronkénti `fetchById`-lal ténylegesen feloldja megjelenítés előtt, és a placeholder csak egy rövid, explicit "loading" átmeneti állapot (nem a végleges renderelt érték). Bármelyik irányt választja a javító kör, a widget tesztnek EZUTÁN a valódi `HttpCommunityProfileRepository`-n (vagy egy azt hűen tükröző fake wire-decode-on) kell átfutnia, nem csak a jelenlegi, kézzel épített `_FakeCommunityProfileRepository`-n — különben a javítás ugyanígy fedetlen maradhat.
- **Ellenőrzés:** egy ÚJ teszt, ami a `HttpCommunityProfileRepository.searchProfiles`-t egy mock Dio/HTTP-adapteren keresztül hívja (a valódi JSON dekódolási úton, ahogy pl. `profile_onboarding_test.dart` teszi a create/update útvonalon), és azt állítja, hogy KÉT különböző `public_id`-jű találat KÉT különböző `displayName`/`handle` értékkel tér vissza.
- **Státusz:** FIXED (`7145eacc`) — a backend válasz `hits` tömbbel bővült (`public_id`+`handle`[`handle_display`]+`display_name`+`created_at`), a `_placeholderProfile` teljesen törölve, `_hitToProfile` valódi, validált decode-ot végez. Saját ellenőrzés: friss `/tmp` klónban ELOLVASVA a diffet (nem csak a signal-t) — a `HttpCommunityProfileRepository` a MEGLÉVŐ `handle_display` oszlopot használja (mérve, Kör 3 migráció, `backend/alembic/versions/e09_r03_0003_community_handle.py:63`), nem fabrikált mező. ÚJ teszt: `test/features/community/presentation/community_search_test.dart:466-530` (`_F1Group`, scriptelt Dio-adapter) — két különböző hit két különböző `displayName`/`handle`-lel dekódolva, explicit `isNot('placeholder')` asszerció.

### F4 — BLOCKER — A `next_cursor` a block-szűrt (láthatatlannak szánt) profil handle-jét és belső PK-ját szivárogtatja (dedikált `security-reviewer` agent leletje)

- **Fájl:** `backend/app/community/repositories/profile_search_repository.py:212-258` (`search_profiles`).
- **Probléma:** a §D2 block-szűrés (`filter_public_ids_against_viewer_blocks`) a PYTHON oldalon, a nyers kandidát-SQL UTÁN fut. A `next_cursor` viszont a NYERS `rows[-1]`-ből épül (212-214. sor: `last_h, last_id = rows[-1][1], rows[-1][2]`) — ez a sor lehet egy BLOCKOLT profil sora, amit a `public_ids` válaszlistából már kiszűrt a block-filter, de a cursor-ba MÉGIS belekerül. A `_encode_cursor` egyszerű, titkosítatlan base64-JSON (`{"h": handle_normalized, "id": internal_pk}`) — triviálisan dekódolható.
- **Reprodukálva (a security-reviewer agent által, eldobható próbateszttel):** viewer blokkolja a `testp-aaa` (pk 2) profilt, `?q=testp&limit=1` keresés. A `public_ids` helyesen NEM tartalmazza — de a dekódolt cursor: `{'h': 'testp-aaa', 'id': 2}`, pontos egyezés a blokkolt profillal. `limit=1`-gyel egy támadó laponként végigjárva megszerzi MINDEN nem-private találat `handle_normalized` értékét ÉS belső integer PK-ját, BELEÉRTVE azokat a profilokat is, amik ŐT blokkolták (a block szimmetrikus — ez pont azt fedi fel, amit a D2 el akar rejteni: kik blokkolták a viewert, akikről a viewernek nincs is tudomása).
- **Hatás:** a belső integer PK (`id`) MINDEN lapozott válaszban szivárog, blokk-állapottól függetlenül — szekvenciális-PK enumerációs/user-count oracle (a brief §9-ben és a review-instrukció #5 pontjában explicit megnevezett kockázat-osztály). Ez a wire-adaton közvetlenül megfigyelhető (`curl`-lal is), a Flutter-oldali placeholder-hiba (F1) NEM fedi el.
- **Kötelező javítás (irány, NEM kész patch):** a cursor legyen opak — szerver-oldali titokkal HMAC-elt vagy titkosított, hogy a `handle_normalized`/`id` ne legyen kliens-oldalon olvasható; ÉS a cursort a BLOCK-SZŰRT, ténylegesen visszaadott utolsó sorból (nem a nyers kandidátából) származtassa, hogy egy blokkolt profil sora sose kerülhessen bele a folytonossági kulcsba.
- **Ellenőrzés:** a security-reviewer próbájának megfelelő regressziós teszt — viewer blokkol egy profilt, `limit=1` lapozás, a dekódolt/megfejtett cursor NEM tartalmazhatja a blokkolt profil handle-jét vagy PK-ját egyik lapon sem.
- **Státusz:** FIXED (`7145eacc`) — a cursor mostantól HMAC-SHA256-tal aláírt (`<base64url(json)>.<base64url(sig)>`, `_sign_cursor`/`_verify_cursor`), az alkalmazás `secret_key`-jével; hamisítás/módosítás a jelaláírás-ellenőrzésen bukik el (`_verify_cursor` `None`-t ad, a hívó friss első laphoz esik vissza). A cursor emellett a BLOCK-SZŰRT `kept_rows` utolsó eleméből épül, sosem a nyers `rows[-1]`-ből — ha az adott lapon az EGYETLEN nyers sor blokkolt, `next_cursor` most `None` (nincs folytatás-token a szivárgó adatból). ÚJ regressziós teszt: `backend/tests/community/test_profile_search.py:770-848` (`test_f4_cursor_omits_blocked_profile_handle_and_pk`) — a security-reviewer PONTOS forgatókönyve (viewer blokkolja `testp-aaa`-t, `limit=1`), asszertálja `next_cursor is None`. Kiegészítő tesztek: `:850` (opacitás — nem sima base64-JSON), `:905` (round-trip valódi titokkal), `:974` (hamisított cursor → friss első lap). Saját ellenőrzés: a diffet ELOLVASVA (`profile_search_repository.py:212-410` köre) — a `cursor_clause` az eredeti kódban ORDER BY UTÁN lett fűzve (érvénytelen SQL lett volna, ha valaha éles cursor-lapozást próbál valaki futtatni éles adatbázison — a javítás ezt is korrigálta, a WHERE blokkon belülre helyezve).
- **Kockázat, amit a fix nyitva hagy (NEM blokkoló, follow-up):** ha egy TELJES lap (limit méretű nyers kandidáta-halmaz) mindegyike blokkolt, `next_cursor` `None` lesz, és a lapozás "véget ér", holott lehet további, nem-blokkolt találat a query-térben túl ezen a ponton. A javító kör saját tesztje (`test_f4_cursor_omits_blocked_profile_handle_and_pk` docstringje) EZT EXPLICIT, szándékos, biztonság-elsőbbségi kompromisszumként dokumentálja ("MUST NOT generate a cursor" amikor a kept-set üres) — a lapozás korai leállása a szivárgás megakadályozásának ára. Elfogadható ebben a körben (nincs olyan A-kritérium, amit sértene), de egy jövőbeli kör, ha ez élességben problémát okoz (sokat blokkoló viewer csonka találati listát lát), külön oldhatja fel (pl. a repository belsőleg lapozzon tovább, amíg legalább 1 kept-row nem kerül elő vagy a nyers kandidáták el nem fogynak).

### F2 — MINOR — A 422 (túl rövid query) válasz docstring-je hamisan állítja, hogy nem fogyaszt rate-limit slotot

- **Fájl:** `backend/app/community/routers/search.py:168-186` (`search_profiles_endpoint`).
- **Probléma:** a docstring (154-156. sor: *"422 — query shorter than MIN_QUERY_LENGTH (no DB touch, no rate-limit slot consumed)"*) és egy inline kommentár (181-183. sor: *"the rate-limit slot is not consumed"*) azt állítja, hogy a túl rövid query nem fogyaszt rate-limit slotot. A tényleges sorrend a kódban: `_search_limiter.allow(...)` (168. sor) FUTNI FOG, MIELŐTT a hossz-ellenőrzés (180. sor) egyáltalán lefutna — a `RateLimiter.allow()` pedig minden híváskor rögzít egy attemptet (`backend/app/ratelimit.py:31-38`), függetlenül attól, hogy utána 422 vagy 200 lesz a válasz. Tehát a túl rövid query IS fogyaszt egy slotot, ellentétben a dokumentált állítással.
- **Hatás:** nem biztonsági regresszió (a tényleges viselkedés a KONZERVATÍVABB irányba téved — több kérés kerül limitálásra, nem kevesebb), de a téves dokumentáció félrevezetheti egy jövőbeli kört, ami erre a viselkedésre építene (pl. egy kliens retry-stratégia, ami feltételezi, hogy a 422 "ingyenes").
- **Kötelező javítás:** vagy a docstring/kommentár igazítása a tényleges sorrendhez, vagy — ha a szándék valóban az volt, hogy a túl rövid query ne fogyasszon slotot — a hossz-ellenőrzés a rate-limit check ELÉ mozgatása.
- **Ellenőrzés:** egy teszt, ami egy túl rövid query-t küld N-szer, majd megméri, hogy ez csökkentette-e a rendelkezésre álló burst-kvótát a következő érvényes kéréseknél.
- **Státusz:** FIXED (`7145eacc`) — a hossz-ellenőrzés a rate-limit check ELÉ került (`search.py:216-229` a hívás előtt fut a `_search_limiter.allow`), a docstring/kommentár is igazítva. ÚJ teszt: `backend/tests/community/test_profile_search.py:1074` (`test_f2_tampered_cursor_422_does_not_consume_rate_limit_slot`) — 70 rövid+hamisított query után egy érvényes kérés még átmegy.

### F3 — NOTE — Holt import + öncélú `_ = x` lint-elhallgattatás

- **Fájl:** `backend/app/community/routers/search.py:57` (`import uuid`), `62-64` (`lookup_active_profile_id` import), `226-228` (`_ = uuid; _ = lookup_active_profile_id`).
- **Megfigyelés:** a modul egy jövőbeli ("exact-handle lookup endpoint") funkcióra hivatkozva tart életben két, ma nem használt importot, mesterséges `_ = x` hozzárendeléssel elhallgattatva a linter figyelmeztetését. A CLAUDE.md elve szerint ("ne tervezz hipotetikus jövőbeli igényekre") ez felesleges — ha egy jövőbeli kör szüksége lesz rá, ott importálja. Nem blokkoló, kozmetikai.
- **Státusz:** FIXED (`7145eacc`, mellékesen) — a javító kör a `search.py`-t úgy írta át, hogy a holt `import uuid`/`lookup_active_profile_id` és az öncélú `_ = x` sorok is eltűntek (`ruff check` zöld maradt enélkül is).

## Gate-bizonyíték ellenőrzése

| Gate | Állított eredmény (§10.4) | Ellenőrizve (saját `/tmp` klón, `d680e5e7`) |
|---|---|---|
| format | zöld | ✅ |
| analyze | zöld | ✅ |
| test `community_search_test.dart` | 7/7 zöld | ✅ |
| architecture | zöld (12 allowlistelt eltérés) | ✅ |
| secrets | zöld | ✅ |
| l10n | zöld | ✅ |
| backend ruff format/check | zöld | ✅ |
| backend pytest | — | **javító kör 1 UTÁN, saját `/tmp` klón (`7145eacc`):** teljes `round-gate.sh` rerun MINDEN lépés zöld, beleértve a backend pytest-et (az F1-es futáskori `test_follow_service.py::test_swap_unique_constraint_breaks_a2` L421-flakiness ezen a futáson nem jelentkezett). |
| CI (`full-gate.yml`, exact-SHA `7145eacc`) | — | run 32613741715, dispatch-elve, **folyamatban** a jelentés írásakor — a merge ELŐTT kötelezően zöldnek kell lennie |
| CI (`backend-ci.yml`, exact-SHA `7145eacc`) | — | run 32613743111, dispatch-elve (a saját korábbi mulasztás pótolva), **folyamatban** a jelentés írásakor |
| security-reviewer (risk=high) | — | lefutott az 1. review-fordulóban, 1 BLOCKER-t talált (F4), egyébként PASS — a javító kör F4-fixét a reviewer NEM futtatta újra (a saját, kiegészített regressziós tesztje és a Claude-oldali kód-olvasás igazolja a zárást, ld. F4 Státusz) |

## Merge-döntés

**Mindkét BLOCKER (F1, F4) FIXED, saját kód-olvasással és a javító kör
regressziós tesztjeivel igazolva.** F2/F3 szintén zárva, mellékesen. A
`ui_inventory_test.dart` számláló-bump megtörtént (68→69).

**Merge a `full-gate.yml` (32613741715) és a `backend-ci.yml` (32613743111)
exact-SHA (`7145eacc`) zöld lezárása UTÁN mehet** — mindkettő a jelentés
írásakor még folyamatban; az orchesztrátor a merge ELŐTT mindkettőt
kötelezően ellenőrzi (ADR 0052). `router_ci_expected=false` a jelenlegi
diffre (`round-ci-plan.py`), tehát a Router CI-t nem kell megvárni.
