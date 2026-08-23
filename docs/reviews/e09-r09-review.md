# E09-R09 — Review

Brief: docs/rounds/e09-r09-profile-search-and-discovery.md
Diff: `git diff 2e8c3810...minimax/e09-r09-profile-search-and-discovery` (2e8c3810 = pre-flight commit, already on `main`)
Reviewer: Claude Sonnet 5 · Dátum: 2026-08-23
Verdikt: CHANGES REQUIRED

## Összegzés

BLOCKER: 1 · MAJOR: 0 · MINOR: 1 · NOTE: 1

## Acceptance criteria

| # | Kritérium | Teljesült | Bizonyíték |
|---|---|---|---|
| A1 | E-mail/telefon alapján nincs keresés | ✅ | `test_a1_search_accepts_only_q_handle_prefix`, `test_a1_search_router_source_does_not_reference_contact_keys` (AST-scan) — `backend/tests/community/test_profile_search.py:217,271` |
| A2 | Blocked + non-discoverable (PRIVATE) kimarad | ✅ (backend) / ❌ (UI — lásd F1) | `test_a2_private_profile_excluded_from_results`, `test_a2_followers_visibility_profile_kept`, `test_a2_blocked_profile_excluded_from_results` — a szűrés helyes, DE a találatok a UI-n megjelenítve nem az adott profilt azonosítják (F1) |
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
- **Státusz:** OPEN

### F2 — MINOR — A 422 (túl rövid query) válasz docstring-je hamisan állítja, hogy nem fogyaszt rate-limit slotot

- **Fájl:** `backend/app/community/routers/search.py:168-186` (`search_profiles_endpoint`).
- **Probléma:** a docstring (154-156. sor: *"422 — query shorter than MIN_QUERY_LENGTH (no DB touch, no rate-limit slot consumed)"*) és egy inline kommentár (181-183. sor: *"the rate-limit slot is not consumed"*) azt állítja, hogy a túl rövid query nem fogyaszt rate-limit slotot. A tényleges sorrend a kódban: `_search_limiter.allow(...)` (168. sor) FUTNI FOG, MIELŐTT a hossz-ellenőrzés (180. sor) egyáltalán lefutna — a `RateLimiter.allow()` pedig minden híváskor rögzít egy attemptet (`backend/app/ratelimit.py:31-38`), függetlenül attól, hogy utána 422 vagy 200 lesz a válasz. Tehát a túl rövid query IS fogyaszt egy slotot, ellentétben a dokumentált állítással.
- **Hatás:** nem biztonsági regresszió (a tényleges viselkedés a KONZERVATÍVABB irányba téved — több kérés kerül limitálásra, nem kevesebb), de a téves dokumentáció félrevezetheti egy jövőbeli kört, ami erre a viselkedésre építene (pl. egy kliens retry-stratégia, ami feltételezi, hogy a 422 "ingyenes").
- **Kötelező javítás:** vagy a docstring/kommentár igazítása a tényleges sorrendhez, vagy — ha a szándék valóban az volt, hogy a túl rövid query ne fogyasszon slotot — a hossz-ellenőrzés a rate-limit check ELÉ mozgatása.
- **Ellenőrzés:** egy teszt, ami egy túl rövid query-t küld N-szer, majd megméri, hogy ez csökkentette-e a rendelkezésre álló burst-kvótát a következő érvényes kéréseknél.
- **Státusz:** OPEN

### F3 — NOTE — Holt import + öncélú `_ = x` lint-elhallgattatás

- **Fájl:** `backend/app/community/routers/search.py:57` (`import uuid`), `62-64` (`lookup_active_profile_id` import), `226-228` (`_ = uuid; _ = lookup_active_profile_id`).
- **Megfigyelés:** a modul egy jövőbeli ("exact-handle lookup endpoint") funkcióra hivatkozva tart életben két, ma nem használt importot, mesterséges `_ = x` hozzárendeléssel elhallgattatva a linter figyelmeztetését. A CLAUDE.md elve szerint ("ne tervezz hipotetikus jövőbeli igényekre") ez felesleges — ha egy jövőbeli kör szüksége lesz rá, ott importálja. Nem blokkoló, kozmetikai.
- **Státusz:** OPEN (follow-up, nem kell ebben a körben javítani)

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
| backend pytest | 420 zöld | ⚠️ első futás 1 PIROS (`test_follow_service.py::test_swap_unique_constraint_breaks_a2`), 2. futás 420/420 zöld — 10×-es izolált rerun 9/10 zöld, a `main` bázison is reprodukálható flakiness. **A kör SAJÁT diffje ezt a fájlt nem érinti** (a scope-audit ezt igazolja) — ez a Kör 7 (E09-R07) `docs/LESSONS.md` L421 által már dokumentált, thread-timing-alapú, nem-determinisztikus valódi-sértés próba, NEM ehhez a körhöz tartozó regresszió. Nem blokkoló erre a körre nézve, de a lánc L421-nek egy erősebb szinkronizációt (vagy a próba kiváltását egy nem-threading alapú determinisztikus technikára) érdemes felvennie egy jövőbeli körben. |
| CI (`full-gate.yml`, exact-SHA `d680e5e7`) | — | run 32612083350, dispatch-elve, folyamatban a review írásakor — a merge ELŐTT kötelezően zöldnek kell lennie |
| security-reviewer (risk=high) | — | dedikált agent dispatch-elve, folyamatban a review írásakor |

## Merge-döntés

**Merge TILOS amíg F1 (BLOCKER) nyitva.** F2/F3 (MINOR/NOTE) nem blokkolnak,
de F2 érdemes egy sorban javítani a javító körrel együtt, mivel ugyanabban a
fájlban van, amit F1 amúgy is módosít.

A javító kör a leletlistával (F1 kötelező, F2 ajánlott egy sorban) a MEGLÉVŐ
`minimax/e09-r09-profile-search-and-discovery` branch-en fut, ugyanazzal a
motorral (MiniMax M3, egy javító kör a jóváhagyott motor-eszkaláció szerint).
