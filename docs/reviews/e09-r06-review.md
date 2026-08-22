# E09-R06 — Review

Brief: docs/rounds/e09-r06-profile-onboarding-and-editing.md
ADR: docs/adr/0400-profile-onboarding-service-and-community-gate-ui.md
Diff: `git diff b89561f6...22862b18` (pre-flight commit → implementer HEAD; javító kör: `2da487c7...9592638e`)
Reviewer: Claude Sonnet 5 · Dátum: 2026-08-22
Verdikt: CHANGES REQUIRED (F1/F2 fixed; F9/F10 a CI-dispatch fedte fel, javító kör 2 folyamatban)

## Összegzés

Első kör: BLOCKER: 1 · MAJOR: 1 · MINOR: 3 · NOTE: 2.
Javító kör 1 (`9592638e`) után: F1 és F2 FIXED, ellenőrizve. Az ELSŐ
exact-SHA CI-dispatch (`full-gate.yml`, head `f312ad54`) PIROS lett — a
teljes suite 2 ÚJ, gate-en-kívüli MAJOR leletet (F9, F10) fedett fel.
MINOR/NOTE (F3/F4/F6/F7/F8) nyitva maradt, nem blokkol.

Gate zöld (saját, izolált `/tmp/review-e09-r06` klónban, csővezeték nélkül,
lásd lent). A gate ZÖLDsége NEM bizonyíték a két nyitott leletre — mindkettő
olyan defektust ír le, amit a jelenlegi tesztkészlet (fake repository a
Flutter oldalon, service-szintű unit tesztek a backend oldalon) szerkezetileg
nem tud megfogni.

## Acceptance criteria

| # | Kritérium | Teljesült | Bizonyíték |
|---|---|---|---|
| A1 | Community profil csak explicit user actionre készül | ✅ | `community_gate_test.dart::A1` — a gate build()-je 0 `createProfile` hívást indít |
| A2 | A privacy alapérték látható és módosítható a flow-ban | ✅ | `profile_onboarding_test.dart::default visibility is followers, not public` |
| A3 | Hálózati hiba nem veszti el a kitöltött profilt | ✅ | `profile_onboarding_test.dart::failed submit keeps the entered text` |
| A4 | Logged-out és feature-disabled gate helyesen jelenik meg | ✅ | `community_gate_test.dart` — 3 állapot-renderelés |
| A5 | Handle debounce és dupla submit blokkolva | ✅ | `profile_onboarding_test.dart::rapid double-tap fires createProfile exactly once` + valódi-sértés próba (PIROS→ZÖLD, dokumentálva a §10-ben) |
| A6 | Logoutkor a Community cache törlődik | ⚠️ RÉSZBEN | Nincs dedikált widget teszt; a `CommunityProfileController.build()` `ref.watch(authControllerProvider)`-re épül (autoDispose AsyncNotifier) — logout → provider újraépül → nincs stale profil. Kód-szinten helyes, teszttel NEM bizonyított (MINOR, lásd F3) |
| A7 | 2.0 text scale mellett nincs kritikus overflow | ⚠️ RÉSZBEN | `SingleChildScrollView` + `RadioListTile` a layoutban, de nincs golden/text-scale teszt (MINOR, lásd F4) |
| A8 | Backend `create_profile` DB-uniqueness-re épül, payload `user_id`/`profile_id` `extra="forbid"`-dal elutasítva | ✅ | `backend/tests/community/test_profile_service.py` — 15 teszt-függvény, köztük a konkurens-create és a smuggled-identity cellák; valódi-sértés próba (PIROS→ZÖLD, dokumentálva) |

A1–A5, A8 mérve, ZÖLD. A6/A7 kód-szinten indokolt, de a brief §6 saját
bizonyíték-oszlopát ("Bizonyíték: ...test.dart") szó szerint nem teljesíti —
MINOR, nem blokkol (lásd F3/F4).

## Scope-audit

`tools/scope-audit.py --repo /tmp/review-e09-r06 --brief
docs/rounds/e09-r06-profile-onboarding-and-editing.md --base b89561f6`:

Első futás (a §0.0.1 addendum ELŐTT): **FAILED**, 3 listán kívüli fájl —
`lib/core/foundation/app_failure.dart`, `lib/l10n/app_en.arb`,
`lib/l10n/app_hu.arb`. Mindhárom kicsi, additív, tartalmilag helyes (az
`app_failure.dart` a MEGLÉVŐ per-feature `FailureCode` konvenciót követi; az
ARB-aggregátumot `dart run tool/gen_l10n_segments.dart --check` frissnek
mérte). Az orchesztrátor a §0.0.1 brief-revízióval (ADR 0087 §2, saját, még
nem merge-elt brief) mindhárom fájlt felvette az `allowed_paths`-ra — ez a
pont ZÁRVA, a javító körnek nem kell hozzányúlnia.

**Folyamat-eltérés (NOTE, lásd F5):** a brief §0 STOP-protokollja szerint egy
listán kívüli fájl esetén az implementernek `stopped`-ot kellett volna
jeleznie, nem csendben írnia rá — ez esetben a tartalom helyesnek bizonyult,
de a mintázat kockázatos, ha legközelebb nem az.

## Megállapítások

### F1 — BLOCKER — hiányzó `GET /community/profiles/me` backend endpoint

- **Fájl:** `lib/features/community/data/repositories/profile_repository_impl.dart:97-112` (hívás) · `backend/app/community/routers/profile.py` (hiányzó route)
- **Probléma:** `HttpCommunityProfileRepository.fetchMyProfile()` egy `GET /community/profiles/me` HTTP hívást indít. A backend router-ben (`routers/profile.py`) EZ AZ ÚTVONAL NEM LÉTEZIK — csak `POST`/`PUT /profiles/me` (E09-R06) és `GET /profiles/{public_id}` (E09-R02, nem alkalmas "a saját profilom" lekérdezésre, mert a hívónak előre kellene ismernie a saját `public_id`-ját). `grep -n "@router.get" backend/app/community/routers/profile.py` → csak `/ping` és `/profiles/{public_id}`.
- **Hatás:** a Community gate ÁLLAPOTGÉPE (`disabled`/`loggedOut`/`profileMissing`/`ready`) a `fetchMyProfile()` eredményén dönt. Éles backenddel szemben MINDEN hívás 404-re fut (nem létező route), amit a repository `null`-ra képez le — a `ready` állapot (van már profilod) SOHA nem érhető el, még egy sikeresen létrehozott profil után sem. Ez a kör FŐ acceptance-céljának (A4, "a gate helyesen jelenik meg") gyökeres, néma sérülése, amit a jelenlegi tesztkészlet nem fog meg, mert mind a Flutter widget tesztek (fake repository), mind a backend service tesztek (nem HTTP-n át hívnak) megkerülik a valós útvonalat.
- **Eredet:** ADR 0400 §2–3 (az orchesztrátor saját pre-flight terve) csak az ÍRÓ végpontokat specifikálta, a `fetchMyProfile()` olvasó útját nem — ez az orchesztrátor tervezési hiánya, amit az implementer nem jelzett STOP-pal, hanem egy nem-létező route-ra hivatkozva silently áthidalt.
- **Kötelező javítás:** `GET /community/profiles/me` hozzáadása `routers/profile.py`-hoz, a `CurrentUser`/`DbSession` mintát követve (mint a `create_my_profile`/`update_my_profile`), a MEGLÉVŐ `_serialize_profile` segédfüggvény újrahasznosításával, 404 ha a hívónak nincs profilja (`profile_missing`, ugyanaz a kód, mint a PUT 404-nél).
- **Ellenőrzés:** ÚJ backend teszt — auth-olt `GET /community/profiles/me` (a) 404 ha nincs profil, (b) 200 + a helyes `handle`/`display_name` mező ha van. ÚJ vagy bővített Flutter widget teszt, ami a `HttpCommunityProfileRepository`-t valódi (mock HTTP szerver vagy Dio interceptor) hívással teszteli, NEM csak a fake repository-t — legalább egyet, ami a route-nevet pinneli (`/community/profiles/me`, GET), hogy a jövőben egy hasonló drift azonnal pirosra váltson.
- **Státusz:** FIXED (`9592638e`) — `GET /profiles/me` hozzáadva, a `{public_id}` dinamikus route ELÉ (route-ordering, FastAPI a legelső illeszkedő útvonalat választja). 4 új teszt: `test_get_my_profile_returns_404_when_no_profile_exists`, `test_get_my_profile_returns_200_after_create_round_trips`, `test_get_my_profile_requires_auth`, `test_get_my_profile_is_scoped_to_caller`. Önállóan újra lefuttatva izolált `/tmp/review-e09-r06-fix1` klónban: ZÖLD (`backend pytest` 349 teszt, gate teljes lánc zöld).

### F2 — MAJOR — a `handle_policy.validate()` NFKC-normalizált visszatérési értéke eldobva

- **Fájl:** `backend/app/community/services/profile_service.py:119-142` (kb. — `create_profile` teste)
- **Probléma:** `create_profile` meghívja `validate(handle)`-t (`handle_policy.py`), ami a bemenet NFKC-normalizált + casefold + strip formáját adja VISSZA (`n = normalize(raw); ...; return n`). A service ELDOBJA ezt a visszatérési értéket, majd az `assign_handle(...)` hívásnak egy SAJÁT, hiányos normalizációt ad át: `handle.strip().casefold()` — NFKC-lépés NÉLKÜL.
- **Mérve, reprodukálva** (`backend/.venv/bin/python3`):
  ```python
  import unicodedata
  raw_nfd = unicodedata.normalize('NFD', 'café')  # e + combining acute
  raw_nfc = unicodedata.normalize('NFC', 'café')  # composed é
  raw_nfd.strip().casefold() == raw_nfc.strip().casefold()   # False — a service normalizációja MEGKÜLÖNBÖZTETI őket
  unicodedata.normalize('NFKC', raw_nfd).casefold().strip() == unicodedata.normalize('NFKC', raw_nfc).casefold().strip()  # True — a policy normalize() EGYESÍTI őket
  ```
- **Hatás:** két, vizuálisan és szemantikailag AZONOS handle (csak az alapul szolgáló Unicode-kódpont-szekvencia tér el — ez gyakori, pl. macOS NFD vs. a legtöbb más platform NFC) két KÜLÖNBÖZŐ `handle_normalized` DB-értéket kap. Ez pont az az invariáns, amit `handle_policy.normalize()` doc-kommentje kifejezetten garantálni ígér ("the same character string spelled with precomposed vs decomposed Unicode always maps to the same normalized value") és amit ADR 0397 §5.1 A1-ként mér — de csak a `handles.py`/`identity_service.py` úton, NEM ezen az új service-úton. Következmény: (a) az uniqueness-védelem non-ASCII handle-öknél megkerülhető (két "ugyanolyan" handle mindkettő sikeresen létrejöhet), (b) a jövőbeli router-mounting kör `handles.py` `resolve_handle`/`lookup_active_profile_id` hívásai (amik a KORREKT `normalize()`-t használják) NEM találják meg az ezen az úton, hibás normalizációval tárolt sort — csendes, később nehezen visszakövethető inkonzisztencia.
- **Megerősítve, függetlenül, a dedikált `security-reviewer` agenttal** (lásd lent) — ÉLESEBB támadási szöget adott: user1 regisztrálja `handle="abcde"`, user2 `handle="Ａbcde"` (fullwidth A, U+FF21). A policy szerint a kettő UGYANAZ a handle (mindkettő NFKC-normalizáltan `"abcde"`), de a service hibás normalizációja miatt mindkét `create_profile` hívás SIKERES — két, a policy szerint azonos handle-t viselő profil él egyszerre. Közösségi funkcióban ez egy confusable-karakteres megszemélyesítési (impersonation) vektor, nem csak egy elméleti Unicode-édge-case.
- **Kötelező javítás:** `normalized = validate(handle)` — a visszatérési értéket kell átadni `assign_handle(db, profile.id, handle.strip(), normalized)`-nek, NEM újraszámolni.
- **Ellenőrzés:** ÚJ backend teszt — két profil-létrehozási kísérlet ugyanazon handle NFD/NFC (vagy fullwidth/ASCII) formájával → a MÁSODIK 409 `handle_taken`-t kapjon (jelenleg mindkettő sikerülne).
- **Státusz:** FIXED (`9592638e`) — `normalized = validate(handle)` most átadva `assign_handle`-nek. 2 új teszt: `test_unicode_equivalent_handle_is_rejected_as_taken` (a security-reviewer PONTOS fullwidth/ASCII forgatókönyve — user A `"Ａbcde"`, user B `"abcde"` → 409 `handle_taken`) és `test_unicode_normalization_matches_in_service_layer` (NFD/NFC pár, service-szinten, `pytest.raises(HandleAlreadyClaimed)`). Önállóan újra lefuttatva izolált klónban: ZÖLD.

### F6 — MINOR — hiányzó `Authorization` fejléc 403-at ad, nem 401-et

- **Fájl:** `backend/app/deps.py:19` (`HTTPBearer(auto_error=True)`)
- **Probléma:** hiányzó `Authorization` fejléc → FastAPI/Starlette `HTTPBearer` automatikusan 403-at ad ("Not authenticated"); csak egy JELEN LÉVŐ, de érvénytelen token ad 401-et. A brief/ADR 0400 401-et vár minden auth-hiányos hívásra. A shipped teszt ezt elfedi (`status_code in (401, 403)`).
- **Hatás:** alacsony — mindkét kód elutasít, nincs biztonsági rés, csak HTTP-szemantikai pontatlanság (403 = "ismerlek, de nem engedlek be"; 401 = "nem tudom, ki vagy" — itt az utóbbi lenne pontos).
- **Kötelező javítás:** NEM blokkoló ebben a körben (a projekt SOK MÁS endpointja ugyanezt a `CurrentUser`/`HTTPBearer(auto_error=True)` mintát használja — ez egy projektszintű, nem e körre szűkíthető konvenció; egy pontos fix a `deps.py`-t módosítaná, ami TILOS zóna ezen a körön). Follow-up tétel egy jövőbeli, `deps.py`-t érintő körnek.
- **Státusz:** OPEN, nem blokkol

### F7 — NOTE — nyers SQL paraméterezett, nincs injection

`security-reviewer` independently confirmed: `routers/profile.py::_serialize_profile` és az `identity_service.py` összes raw-SQL hívása `text()` + bound param (`:id` stb.) — nincs string-interpolációs injection-felület.

### F8 — NOTE — `CommunityProfileCreate.handle` séma `max_length=64`, a policy `MAX_LEN=24`

A séma csak durva előszűrő (a policy `validate()` az érdemi kapu, ami mindig lefut) — nem hiba, csak megfigyelés.

### F3 — MINOR — A6 (logout cache-clear) nincs dedikált widget teszttel bizonyítva

- **Fájl:** `test/features/community/presentation/community_gate_test.dart`
- **Probléma:** a §6 Bizonyíték-oszlopa `community_gate_test.dart`-ot ír A6-hoz, de a fájlban nincs explicit logout-szcenárió; a handoff is elismeri ("KONTROLLER SZINTEN GARANTÁLT... de a scenario komplex Riverpod mocking-ot igényelne").
- **Hatás:** alacsony — a `ref.watch(authControllerProvider)` + `autoDispose` minta kód-szinten helyes és a projekt bevett mintáját követi, de egy jövőbeli regresszió (pl. valaki `ref.read`-re cseréli a `watch`-ot) NEM bukna pirosra.
- **Kötelező javítás:** NEM blokkoló ebben a körben — follow-up tétel. Ha a javító kör úgyis a repository-t módosítja (F1 miatt), egy `ProviderContainer`-szintű teszt (auth override cseréje logout-ra, majd `container.read(...).future` újra-awaitolása) olcsón hozzáadható, de nem kötelező.
- **Státusz:** OPEN, nem blokkol

### F4 — MINOR — A7 (2.0 text scale) nincs golden/layout teszttel bizonyítva

- **Fájl:** `lib/features/community/presentation/screens/community_gate_screen.dart`, `edit_profile_screen.dart`
- **Probléma:** a §6 Bizonyíték-oszlopa golden tesztet ír elő; a handoff explicit elismeri, hogy nem készült ("review-tétel").
- **Hatás:** alacsony — a layout `SingleChildScrollView` + `RadioListTile` választása strukturálisan overflow-ellenálló, de nincs mérve.
- **Kötelező javítás:** NEM blokkoló; follow-up.
- **Státusz:** OPEN, nem blokkol

### F5 — NOTE — a scope-túllépésnél a STOP-protokoll helyett csendes írás történt

- **Fájl:** N/A (folyamat-megfigyelés)
- **Probléma:** a brief §0 kifejezetten előírja: "Listán kívüli fájl kellene → `stopped`". Az implementer 3 fájlt (F0, lásd Scope-audit) írt a listán kívül anélkül, hogy jelzett volna — ezúttal a tartalom helyesnek bizonyult, és az orchesztrátor utólag legitimálta, de a mintázat kockázatos.
- **Kötelező javítás:** nincs ebben a körben (a lelet nem blokkol); a jövőbeli MiniMax-promptokban érdemes megerősíteni a STOP-kötelezettséget.
- **Státusz:** NOTE, nem blokkol

## Security review (dedikált, risk=high)

`security-reviewer` agent futtatva, izolált worktree-ben, saját próbatesztekkel
(22/22 shipped teszt + 5 független próba futtatva, utólag törölve). Verdikt:
**nincs BLOCKER**, egy MAJOR (= F2, függetlenül megerősítve, élesebb
impersonation-szöggel), egy MINOR (= F6), két NOTE (= F7/F8). Az
auth-scoping (`extra="forbid"`, `filter_by(user_id=current_user.id)`),
uniqueness-enforcement (DB-szintű, konkurens-create próba) és a
401/404/409 elkülönítés (a 403-nuansz kivételével) mind PASS.

## Gate-bizonyíték ellenőrzése

**Első kör (head `22862b18`), saját izolált `/tmp/review-e09-r06` klón:**

| Gate | Állított eredmény | Ellenőrizve |
|---|---|---|
| format | zöld | ✅ |
| analyze | zöld | ✅ |
| test community_gate_test.dart | zöld | ✅ |
| test profile_onboarding_test.dart | zöld | ✅ |
| architecture | zöld | ✅ |
| secrets | zöld | ✅ |
| l10n (parity + aggregate freshness) | zöld | ✅ — `dart run tool/gen_l10n_segments.dart --check` is önállóan lefuttatva, "aggregátum naprakész" |
| backend ruff format/check | zöld | ✅ |
| backend pytest | zöld (213 teszt) | ✅ |

**Javító kör 1 UTÁN (head `9592638e`), FRISS, saját izolált
`/tmp/review-e09-r06-fix1` klón (a fenti klóntól független, új `git clone` +
`prepare-flutter-generated.sh`):**

| Gate | Állított eredmény | Ellenőrizve |
|---|---|---|
| scope-audit (`tools/scope-audit.py --base 2da487c7`) | OK, 4 changed path, 0 violation | ✅ |
| format | zöld | ✅ |
| analyze | zöld | ✅ |
| test community_gate_test.dart | zöld | ✅ |
| test profile_onboarding_test.dart | zöld | ✅ |
| architecture | zöld | ✅ |
| secrets | zöld | ✅ |
| l10n | zöld | ✅ |
| backend ruff format/check | zöld | ✅ |
| backend pytest | zöld (349 teszt, +6 F1/F2 regresszió) | ✅ |
| F1 kód-ellenőrzés (`grep -n "@router.get" routers/profile.py`) | `/profiles/me` A `{public_id}` ELŐTT | ✅ közvetlenül olvasva |
| F2 kód-ellenőrzés (`grep -n "normalized = validate\|assign_handle("`) | a `validate()` visszatérési értéke átadva | ✅ közvetlenül olvasva |
| CI `full-gate.yml` (első dispatch, head `f312ad54`) | PIROS | ❌ run [32595342705](https://github.com/wolfcasaba/strumsight/actions/runs/32595342705) — 2 hiba a TELJES suite-ból (F9/F10, lásd lent), amit a célzott `round-gate.sh` nem futtat |

### F9 — MAJOR (gate) — `ui_inventory_test.dart` elavult screen-számláló

- **Fájl:** `test/ui/ui_inventory_test.dart:15`
- **Probléma:** `expect(first.screenPaths, hasLength(64))` egy dinamikusan felderített production-screen-számot pinnel; a kör 2 ÚJ screent ad (`community_gate_screen.dart`, `edit_profile_screen.dart`), a valós szám 66.
- **Kötelező javítás:** `hasLength(64)` → `hasLength(66)`.
- **Ellenőrzés:** a teszt önmaga a mérce (dinamikus felderítés, nincs külön próba szükséges).
- **Státusz:** OPEN → javító kör 2 (lásd lent)

### F10 — MAJOR (gate) — `dio_factory_guard_test.dart` false positive egy doc-kommenten

- **Fájl:** `lib/features/community/data/dto/profile_dto.dart:11`
- **Probléma:** a regex-alapú Dio-őr (`\bDio\s*\(`) egy doc-komment szövegére üt ("...dart:convert / Dio (architecture-dependency guard...") — nem valódi `Dio()` konstruktor-hívás.
- **Kötelező javítás:** a komment átfogalmazása úgy, hogy ne tartalmazzon "Dio (" mintát.
- **Ellenőrzés:** `dio_factory_guard_test.dart` önmaga a mérce.
- **Státusz:** OPEN → javító kör 2 (lásd lent)

Mindkettő `test`/`lib` fájl, amit a célzott `round-gate.sh` (csak a brief
`gate_tests`-ét futtatja) NEM fedett le — csak a TELJES CI-suite fogta meg
(ADR 0053 pontosan ezért kötelező). `test/ui/ui_inventory_test.dart`
felkerült az `allowed_paths`-ra (§0.0.2 addendum); a
`dio_factory_guard_test.dart` maga nem változik, a `profile_dto.dart`
(már allowed) komment-javítása oldja fel.

## Merge-döntés

**F1 (BLOCKER) és F2 (MAJOR) FIXED és independently ellenőrizve.** F9/F10
(mindkettő MAJOR — CI-t pirosra állítanak, tehát az ADR 0052 zöld-kapu
alatt blokkolnak) a javító kör 2-ben javítandó, utána ÚJRA-dispatch
kötelező (exact-SHA, ADR 0086 §2). A nyitva maradt MINOR/NOTE-ok
(F3/F4/F6/F7/F8) nem blokkolnak; F3/F4 (A6/A7 tesztlefedettség) follow-up
tétel, F6 (403 vs 401) `deps.py`-t érintene (tilos zóna ezen a körön),
follow-up. A javító köröket ugyanaz a motor (`minimax`) vitte/viszi, a
findings-listával a promptban — ez a lánc normál útja, nem megállási ok
(user-döntés 2026-07-31).
