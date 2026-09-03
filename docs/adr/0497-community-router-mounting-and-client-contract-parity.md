# ADR 0497 — A Community felület regisztráció-szintű felcsatolása, önálló al-flagekkel, és a kliens↔szerver szerződés gépi egyeztetése

- **Státusz:** elfogadva (2026-09-03)
- **Kontextus:** ADR 0395 (Community program-keret), ADR 0396 (Community
  backend modulhatár — a `main.py`-bekötést KIMONDOTTAN egy jövőbeli körre
  halasztja), ADR 0400 (profil-onboarding; a „router-mounting kör" tételes
  listája), ADR 0061 (regisztráció-szintű route-elkülönítés), ADR 0449
  (readiness-vezérelt traffic gate)
- **Kör:** `E15-R12` — ez az a jövőbeli kör, amelyet az ADR 0396 és az ADR 0400
  előre nevesített.
- **Döntéshozó:** Claude (orchestrátor), a `docs/rounds/e15-r12-backend-mounting-and-end-to-end.md` briefje alapján

## Kontextus — a mért hiány

A `backend/app/main.py` `create_app()`-ja ma **négy** routert regisztrál:
`auth`, `settings`, `diagnostics` (flag mögött) és `tutor` (flag mögött)
(`backend/app/main.py:183-224`). A Community modul ezzel szemben **13
router-modult** hordoz (`backend/app/community/routers/`) és 20 Alembic
migrációt, de a `build_community_router()` factory közülük **csak a
`profile`-t** adja vissza, és a production alkalmazásban **egyetlen hívója
sincs** — az egyetlen fogyasztó a `backend/tests/community/conftest.py`
saját teszt-appja.

Ez nem véletlen adósság, hanem kimondott halasztás: az ADR 0396
Következmények 3. pontja és a `build_community_router()` docstringje is
rögzíti, hogy az élesítés „a future round's job". Az ADR 0400
Következmények szakasza tételesen fel is sorolja a hiányzó
„router-mounting kört". Ennek a következménye MÉRHETŐ a felhasználó
oldalán: az Epic 9 teljes szerver-oldali felülete elérhetetlen, ezért a
kliens Community-képernyői üresek vagy hibásak maradnak, akárhogy is
néznek ki.

## Döntés

### D1 — A felcsatolás REGISZTRÁCIÓ-szintű, nem futásidejű tiltás

Kikapcsolt modul mellett a Community route-ok **létre sem jönnek**: a
kliens `404`-et kap, nem `403`-at. Ez az ADR 0061 mintája, és a `main.py`
meglévő `if settings.diagnostics_enabled:` / `if settings.tutor_enabled:`
alakjával azonos; a `_traffic_gate` docstringje (`backend/app/main.py:115-126`)
mérten ugyanezért nem middleware.

**Kimondottan NEM elfogadható gyengítés:** mindig regisztrált route,
futásidejű `403`-mal. Egy ilyen felület a hitelesítési és adatvédelmi
kapukat egyetlen `if` mögé helyezné, és a „letiltott" állapot már nem
lenne a route-tábla ellenőrizhető tulajdonsága.

### D2 — Az al-flagek ÖNÁLLÓAN kapuznak

A `community_writes_enabled`, `community_media_enabled`,
`community_leaderboard_enabled` és `community_clubs_enabled`
(`backend/app/config.py:101-105`) a fő flagtől függetlenül kapuz: a
`community_enabled=true` önmagában **nem** nyitja meg az írási, média-,
ranglista- és klub-ágakat. A kapuzás fokozata azonos D1-gyel — a kikapcsolt
al-ág route-jai nem regisztrálódnak.

**Kimondottan NEM elfogadható gyengítés:** „a `community_enabled` mindent
bekapcsol". Ez a fokozatos, telepítés-szintű megnyitást — az egyetlen
eszközt, amivel az un-auditált felület részlegesen élesíthető — semmisítené
meg.

### D3 — Az aggregátor egyetlen, DETERMINISZTIKUS sorrendű felület

A 13 router prefixei mérten **átfedők**: `profile`, `feed`, `reports`,
`safety` és `social_graph` mind a `/community` prefixen ül, a `search` pedig
a `/community/profiles`-on. FastAPI-ban az **első illeszkedő** route nyer,
ezért a paraméteres útvonalak árnyékolhatják a literálokat, ha előbb
regisztrálódnak.

**Az árnyékolás MÉRT iránya (helyesbítve a review-ban, 2026-09-03 — az ADR
első szövege és a brief §0.0 R3 fordítva mérte):** a `search` routernek
egyetlen route-ja van, a **literál** `/community/profiles/search`
(`routers/search.py:151`); a paraméteres gyűjtő a `profile` routeré
(`/community/profiles/{public_id}`, `routers/profile.py:117`). A `profile`
routeren BELÜL a `/profiles/me` literál helyesen a `{public_id}` ELŐTT van
deklarálva, tehát ott nincs kockázat. A tényleges kockázat a **routerek
közötti** sorrend: `profile` előbb regisztrálva elnyelné a
`/community/profiles/search`-öt `public_id="search"`-ként.

Az aggregátor sorrendje ezért a szerződés része: a **literál-útvonalú
routerek előbb, a paraméteres-gyűjtő routerek utóbb** kerülnek be — konkrétan
`search` a `profile` ELŐTT, a `profile` pedig utolsóként —, és ezt a
sorrendet a kör tesztje pinneli
(`test_a8_search_literal_route_is_not_shadowed_by_profile_param_route`).

### D4 — A readiness a bekapcsolt modulra a Community-gate-et is lefuttatja

Bekapcsolt Community mellett a `/health/ready` a meglévő
`community_readiness_failure()` gate-et is meghívja
(`backend/app/community/__init__.py`), és annak hibakódját adja vissza. A
gate **önálló** mérési értéke a `community_requires_postgres` ág: prod
környezetben, SQLite-on futó, bekapcsolt Community modul NOT READY, még
akkor is, ha a migrációs fej egyébként egyezik és az
`allow_sqlite_in_prod` szökési út nyitva van.

**Kimondottan NEM elfogadható gyengítés:** a modul bekapcsolása
readiness-ellenőrzés nélkül; illetve az A4 cella olyan megfogalmazása, amit
a MÁR meglévő `_readiness_failure()` migration-mismatch ága önmagában
kizöldít — a cellának a `community_requires_postgres` kódra kell mérnie,
különben nem méri az új viselkedést.

### D5 — A kliens↔szerver szerződés gépi, nem prózai

A kliens által hívott végpontok listája egy verziózott artefaktum
(`docs/contracts/client-backend-endpoints.json`), és egy teszt
(`backend/tests/test_client_contract_parity.py`) minden listázott végpontot
az app **OpenAPI sémája** ellen mér. A drift („a képernyő üres marad") így
nem futásidejű tünet, hanem piros cella.

A lista a kliens MÉRT hívásaiból készül, nem a kívánságlistából; a mérce
falszifikálhatóságát a brief §6.1 valódi-sértés próbája adja (egy szerver
oldali route átnevezése az A5 cellát pirosra kell vigye).

### D6 — A felcsatolás fail-closed: hitelesítetlen router NEM kerül az aggregátumba

*(Hozzáadva a review után, 2026-09-03 — a mérés a D1–D5 hiányzó feltételét
tárta fel.)*

A 13 router közül a `handles` és a `privacy` **nem** hitelesít: a
`POST /community/handles/claim|change` és a
`GET|PUT /community/privacy/{profile_public_id}` `Authorization` fejléc
nélkül is elér a handlerig (mérve: 48 community route-metódusból 8 authless).
Mindkét router saját docstringje kimondja, hogy szándékosan nincs
felcsatolva, és hogy az authz egy későbbi kör dolga
(`routers/handles.py:16-19,95,239-241`, `routers/privacy.py:5-9,194-201`).

**Döntés:** az aggregátum csak olyan routert vehet fel, amelynek MINDEN
route-ja hitelesítést követel; a `handles` és a `privacy` ezért kimarad,
amíg az authz-uk (ADR 0400 Következmények (c) pont) meg nem születik. A
kliens egyiket sem hívja — a `docs/contracts/client-backend-endpoints.json`
egyetlen ilyen bejegyzést sem tartalmaz —, tehát a kimaradás nem okoz
kliens-driftet.

**Kimondottan NEM elfogadható gyengítés:** „a modul alapból ki van kapcsolva,
tehát a hitelesítetlen route nem baj". A `community_enabled=False` default
enyhítő, nem feloldó: a kör célja épp a bekapcsolhatóvá tétel, és a
`docs/operations/device-backend-runbook.md` a bekapcsolást tanítja.

**A gépi mércéje:** az A2 cella nem mintát próbál, hanem a felcsatolt
community route-okat **kimerítően** sorolja fel az `app.routes` fából, és
mindegyiken megköveteli az auth-ot — rövid, tételesen indokolt
kivétel-listával.

## Következmények

- A `backend/app/main.py` mostantól **öt** feltételes/feltétlen router-blokkot
  tartalmaz; a Community blokk ugyanazt a `dependencies=_gated` mintát
  használja, mint a többi üzleti router (ADR 0449 D1–D3).
- A `build_community_router()` a továbbiakban **nem** csak a `profile`-t adja
  vissza; a `backend/tests/community/conftest.py` teszt-appja ezzel a teljes
  Community felületet kapja meg. Ez a suite **változatlanul zöld kell
  maradjon** — ha nem hozható zöldre a tesztek módosítása NÉLKÜL, az a kör
  `stopped` jelzése, nem a tilos zóna feloldása (a `backend/tests/community/**`
  nincs az `allowed_paths`-on).
- **Séma NEM változik.** Ha bármely router bekötése ÚJ Alembic migrációt
  igényelne, a kör `stopped`-ot jelez: ez a kör meglévő modult csatol fel.
- Az ADR 0400 Következmények szakaszában nevesített router-mounting tételekből
  ez a kör az (a) pontot **részlegesen** (11 router a 13-ból, D6) és a (d)
  pontot teljesen zárja. A (b) TOCTOU-rés és a (c) `privacy.py` authz
  **továbbra is nyitott tartozás** — azok a `backend/app/community/`
  moduljait írnák át, ami ennek a körnek a tilos zónája. **Amíg a (c) nyitott,
  a `privacy` és a `handles` router a D6 szerint felcsatolatlan marad**; a
  bekötésük a (b)/(c) pontot záró jövőbeli kör dolga, és a D6 A2-cellája
  gépileg akadályozza meg a korábbi, hitelesítés nélküli élesítést.
- Nyitott tartozásként rögzítve (tilos zóna, a kör nem okozza, de a mérés
  feltárta): a `routers/bookmarks.py:195` „opak" lapozó kurzora base64-elt
  JSON, benne a belső row `id` — a modul „never leaks the internal `id`"
  kontraktusa (ADR 0396 §1) itt nem áll maradéktalanul.
- A flagek alapértelmezése **változatlanul `False`** minden környezetben: a
  bekapcsolás telepítési döntés marad, és ezt a kör nem érinti.
- A backend-oldali mérce a `backend-ci.yml` workflow-ban fut (ruff lint, ruff
  format, `pytest -q`), amely a `backend/**` útvonalra triggerel — a kör
  zöld kapujának ez is része, nem csak a Flutter-oldali Full Gate.

## A visszavonás feltétele

Felülvizsgálandó, ha egy jövőbeli kör mérten azt találja, hogy a 13 router
egyetlen aggregátoron át való felcsatolása a prefix-átfedések miatt nem
tartható determinisztikusan (D3) — ekkor a routerek `main.py`-ból való,
egyenkénti `include_router` felvétele a helyes lépés, a modulhatár
(ADR 0396) újratárgyalásával együtt.

## Hivatkozások

- `docs/rounds/e15-r12-backend-mounting-and-end-to-end.md`
- [ADR 0395](0395-community-baseline-feature-flags-and-threat-model-scope.md) ·
  [ADR 0396](0396-community-backend-module-boundary-and-first-migration.md) ·
  [ADR 0400](0400-profile-onboarding-service-and-community-gate-ui.md) ·
  [ADR 0061](0061-lab-route-isolation-and-hardened-diagnostics.md) ·
  [ADR 0449](0449-staging-readiness-traffic-gate-and-recovery.md)
