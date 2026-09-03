# E15-R12 — Review (Claude / orchestrátor, ADR 0055)

- **Kör:** `E15-R12` — A Community/Gamification backend bekötése és a teljes végponti lefedés
- **Brief:** [`docs/rounds/e15-r12-backend-mounting-and-end-to-end.md`](../rounds/e15-r12-backend-mounting-and-end-to-end.md)
- **ADR:** [`0497`](../adr/0497-community-router-mounting-and-client-contract-parity.md)
- **Motor:** `sonnet-impl` · **Ág:** `sonnet-impl/e15-r12-backend-mounting-and-end-to-end`
- **Review dátuma:** 2026-09-03
- **Kockázat:** `high` → a `security-reviewer` futtatása KÖTELEZŐ volt, és megtörtént.

> **A kör előzménye:** az implementer-session az API 529-kimaradása alatt
> (2026-09-03 13:31–14:30) megszakadt; a munkája `c18510c4` „WIP megőrzés"
> commitként maradt fenn, jelzés nélkül. A jelen review ezt az állapotot méri.
> A brief §10 (implementation handoff) emiatt **kitöltetlen** — lásd N3.

## 1. VÉGSŐ DÖNTÉS: **CHANGES REQUESTED** — merge tilos

2 BLOCKER, 2 MAJOR, 2 MINOR, 3 NOTE. A BLOCKER-ek gyökere közös: az
aggregátor **hitelesítés nélküli írási felületet** csatol fel a production
appra, és a kör saját A2 cellája ezt nem fogja meg.

## 2. Mit mértem (parancs → kimenet)

| Mérés | Eredmény |
|---|---|
| `ruff check app tests` | **zöld** — All checks passed |
| `ruff format --check app tests` | **zöld** — 139 files already formatted |
| `pytest -q` (TELJES backend suite) | **zöld** — 872 teszt, exit 0 (A7 igazolva: a `backend/tests/community/**` és a `conftest.py` MÓDOSÍTÁS NÉLKÜL zöld) |
| `tools/round-gate.sh test/app/app_config_test.dart test/app/config/feature_flags_test.dart` | **PIROS** — `secrets` lépés, exit 10 (B3) |
| `tools/scope-audit.py --base origin/main` | 8 fájl; egyetlen „sértés" a `docs/adr/0497-*.md`, amit az orchestrátor írt a pre-flightban (ADR 0087 §2) — **valódi scope-sértés nincs** |
| `tools/round-ci-plan.py` | `dispatch = ["full-gate.yml"]`, `router_ci_expected = true` (+ a `backend/**` diff miatt a `backend-ci.yml` is a zöld kapu része, ADR 0497 Következmények) |
| Upstream-szinkron (§0.3) | `origin/main` (`a303589a`) beépítve `47b65063`-ként, ancestor-próba zöld |

**Route-szintű auth-leltár** (`create_app()` minden flaggel BE, minden route
`dependant`-fája rekurzívan bejárva — a reprodukáló szkript a §5-ben):

```
total community route-methods: 48
AUTHLESS: 8
   GET  /community/handles/availability
   GET  /community/handles/{handle:str}
   GET  /community/ping
   GET  /community/privacy/{profile_public_id}
   GET  /community/profiles/{public_id}
   POST /community/handles/change
   POST /community/handles/claim
   PUT  /community/privacy/{profile_public_id}
```

Futásidejű megerősítés: egy `Authorization` fejléc NÉLKÜLI
`PUT /community/privacy/{uuid}` **nem 401/403-mal tér vissza**, hanem eljut a
handler adatbázis-lekérdezéséig (`sqlite3.OperationalError: no such table:
community_privacy_settings` a lekérdezés végrehajtásakor) — vagyis semmilyen
hitelesítési kapu nem áll az útjában.

## 3. Leletek

### B1 (BLOCKER) — A `privacy` router hitelesítés nélküli írási felületet nyit más felhasználó adatvédelmi beállítására

`backend/app/community/__init__.py:152` (`aggregate.include_router(privacy_router)`)

`GET` **és** `PUT /community/privacy/{profile_public_id}` egyaránt auth
nélkül elérhető: egy anonim hívó kiolvashatja és **át is írhatja** egy másik
felhasználó láthatósági beállítását (`private` → `public`). A router saját
docstringje (`backend/app/community/routers/privacy.py:5-9`) kimondja, hogy
„deliberately unmounted from `build_community_router`", a `:194-201` pedig,
hogy az authz-policy „out of scope".

**Súlyosbító:** az ADR 0497 Következmények szakasza maga rögzíti, hogy a
`privacy.py` authz „továbbra is nyitott tartozás" — és a diff ennek ellenére
felcsatolja. Az indoklás („az a kör tilos zónája") fordítva helyes: a
**nem-felcsatolás** teljes egészében az `allowed_paths`-on van.

**Javítás iránya (allowed_paths-on belül):** ne kerüljön be a `privacy_router`
az aggregátumba, amíg nincs tulajdonos-ellenőrzése.

### B2 (BLOCKER) — A `handles` router hitelesítés nélküli handle-átvételt enged, belső PK-ra

`backend/app/community/__init__.py:147` (`aggregate.include_router(handles_router)`)

`POST /community/handles/claim` és `POST /community/handles/change` auth nélkül
hívható, és a `profile_id` bemenet a nyers `community_profiles.id` **belső
egész PK** — amit a válasz vissza is ad. A router docstringje
(`handles.py:16-19`, `:95`, `:239-241`) explicit: „mounted by the test app
through a separate fixture", „auth lands in Kör 6", „internal endpoint, **not
yet exposed** to the mobile client".

A `docs/contracts/client-backend-endpoints.json` **egyetlen** `/community/handles`
bejegyzést sem tartalmaz — a kliens nem is hívja: a felcsatolása tiszta
támadásifelület-növelés, funkcionális haszon nélkül.

**Javítás iránya:** ne kerüljön be a `handles_router` az aggregátumba.

**Mérve, hogy a javítás NEM igényli a tilos zóna feloldását:** a
`backend/tests/community/**` suite a `handles`/`privacy` routereket a SAJÁT
fixture-jeiben csatolja fel (`tests/community/test_handle_policy.py:126`,
`test_block_query_regression.py:127-128`), **nem** a factory-n keresztül; a
`tests/community/conftest.py` egyáltalán nem hivatkozik rájuk. A két
`include_router` sor eltávolítása tehát az A7-et nem sérti.

### B3 (BLOCKER) — A kötelező gate PIROS: secret-scan lelet a kör saját tesztjében

`backend/tests/test_community_mounting.py:236`

```
Secret scan failed (4250 file(s) scanned, 1 finding(s)).
- backend/tests/test_community_mounting.py:236: credential assigned a long literal
    → [6] secrets: PIROS (kilépési kód 1)
Gate-összegzés: format zöld · analyze zöld · test zöld · architecture zöld · secrets PIROS (1)
```

A `_deploy_settings()` fix `secret_key=` értéke. Ez bizonyítottan teszt-fixture,
tehát a `# strumsight:allow-secret <indok>` sorvégi jelölő a helyes feloldás —
de jelölő nélkül a kör **H7 felé megy**, és a CI is pirosra fut.

### M1 (MAJOR) — Az A2 cella vak: 5 route-ot próbál 48-ból, és a nevében hedge-el

`backend/tests/test_community_mounting.py:128-134`, `:148`

Az `_AUTH_REQUIRED_PROBES` öt route-ot mér (`profile`, `feed`, `safety`,
`search`, `moderation`) — mind az öt véletlenül hitelesített —, a teszt neve
pedig `..._and_authenticated_ones_require_auth`, tehát a **8 hitelesítetlen
route-metódus mellett is zöld marad**. A brief §6.1 mérce-mátrixa szerint az
A2-nek épp azt a hibás implementációt kellene pirosra vinnie, ami itt átment.

**Javítás iránya:** az A2 cella sorolja fel a felcsatolt community route-okat
**kimerítően** a `app.routes` fából, és követelje meg mindegyiken az auth-ot,
egy RÖVID, tételesen indokolt kivétel-listával (pl. `GET /community/ping`).
Így a cella a valódi rést fogja meg, nem egy mintát.

### M2 (MAJOR) — Anonim de-anonimizációs lánc: `private` profil kiolvasása

`backend/app/community/routers/profile.py:117` (`GET /community/profiles/{public_id}`)

A route auth nélkül elérhető, és nem nézi a `community_privacy_settings.visibility`
értékét; a `handles` resolverrel láncolva egy `private` profil `display_name`-je
és `created_at`-je anonim módon kiolvasható, miközben a HITELESÍTETT keresés
ugyanarra a profilra helyesen `403`-at ad.

A B2 javítása (a `handles` le-csatolása) a láncot megtöri (a `public_id` UUID
önmagában kitalálhatatlan), a **maradék** authless olvasási felület viszont
marad. A `docs/contracts/client-backend-endpoints.json` szerint a kliens ezt a
route-ot **nem hívja** — a paraméteres olvasó kihagyása az aggregátumból tehát
nem okoz kliens-driftet.

**Javítás iránya:** vagy maradjon ki az aggregátumból (a szűrés az
`allowed_paths`-on belül van), vagy — ha a kimaradás bármelyik tilos-zónás
tesztet pirosra viszi — maradjon bent, de az M1 kivétel-listáján, **mért
indoklással** és az ADR 0497 nyitott-tartozás listájára felvéve.

### N1 (MINOR) — A runbook mért állítása téves a block/mute írásokról

`docs/operations/device-backend-runbook.md:40-43` és `:119`

A doksi azt állítja, `community_writes_enabled=false` mellett a „blocking/muting"
írások is eltűnnek. Mérve: `POST/DELETE /community/profiles/{public_id}/block`
és `/mute` **jelen van** — a `safety` router nincs a writes-kapun (ezt a
`__init__.py:96-99` docstringje helyesen le is írja; a runbook mond ellent
neki). Egy üzemeltető azt hiheti, kikapcsolta ezeket az írásokat.

### N2 (MINOR) — Belső PK a lapozó kurzorban

`backend/app/community/routers/bookmarks.py:195` — az „opak" kurzor base64-elt
JSON, benne a belső row `id`. **Tilos zóna, pre-existing**, a kör nem okozza;
azért kerül ide, mert a modul A2-kontraktusa („never leaks the internal `id`")
így nem áll maradéktalanul. Nyitott tartozásként rögzítendő, nem ebben a körben
javítandó.

### N3 (NOTE) — A brief §10 (implementation handoff) kitöltetlen

A 529-kimaradás miatt az implementer nem jutott el a §10-ig. A javító körnek ezt
ki kell töltenie (a §6.1 valódi-sértés próba dokumentálásával együtt — a próba
KÓDBAN megvan: `test_a5_real_violation_probe_missing_route_is_caught`, de a
briefben nincs leírva).

### N4 (NOTE) — A brief §0.0 R3 / A8 árnyékolási iránya fordítva volt mérve

A brief R3 azt írja, hogy a `search.py` paraméteres `/community/profiles/{handle}`
útvonala árnyékolhatja a `profile.py` `/community/profiles/me` literálját.
Mérve ez **nem áll**: a `search.py`-nak (`prefix="/community/profiles"`) egyetlen
route-ja van, a LITERÁL `/search` (`search.py:151`), a paraméteres gyűjtő pedig a
`profile.py` `/profiles/{public_id}`-ja (`profile.py:117`). A valódi kockázat
tehát fordított irányú, és az implementáció **helyesen** oldotta meg (`search`
a `profile` ELŐTT, `__init__.py:155-159`), a tesztje pedig
(`test_a8_search_literal_route_is_not_shadowed_by_profile_param_route`) a valódi
irányt pinneli. **Nem lelet az implementáción** — a brief szövegét javítottam
(§0.0 R9), az ADR 0497 D3 megfogalmazásával együtt.

### N5 (NOTE) — A runbook LAN-expozíciója felerősíti a B1/B2-t

`device-backend-runbook.md:19,32`: `--host 0.0.0.0` + `STRUMSIGHT_COMMUNITY_ENABLED=true`
mellett a `cors_origins` default `["*"]` (`backend/app/config.py:64`), tehát az
azonos Wi-Fi-n lévő BÁRMELY eszköz eléri a B1/B2 hitelesítetlen írásait. A B1/B2
javítása ezt megszünteti; a runbook egyébként helyesen jelzi, hogy a leírt
felállás `dev`/`lab` build. `allow_sqlite_in_prod`-ot és prod-expozíciót nem
javasol — ezekben tiszta.

## 4. Amit végignéztem, és TISZTA (bizonyítékkal)

- **`moderation` authz:** mind a 6 route-on `CurrentUser`, 5-ön `_require_moderator`
  (`moderation.py:172-186`) → 403; a 6. (`post_appeal`) szándékosan a bejelentő
  útja, saját tulajdonos-őrrel (`:370-410`). Az `is_moderator` allowlist-tábla,
  fail-closed (`moderation/case_service.py:316-328`).
- **`_reads_only()` (`__init__.py:69-77`):** writes BE = 48, KI = 40
  route-metódus; pontosan a 8 írás-metódus esik ki, egyetlen GET sem tűnik el,
  és egyetlen túlélő route dependency-fája / `response_model`-je / `status_code`-ja
  / `tags`-e sem változik. Írás-hatású GET nem marad bent.
- **`feed`, `posts`, `reports`, `search`, `safety`, `bookmarks`, `challenges`,
  `leaderboards`, `social_graph`:** mind a 42 route-metóduson ott a
  `get_current_user`.
- **`/health/ready` community ág** (`main.py:113-123` + `community_readiness_failure`):
  fail-closed sorrend, a base-check UTÁN fut (nem árnyékol), `prod` + community +
  `not community_postgres_ready` → `community_requires_postgres`. Az A4 cella a
  brief §0.0 R5 szerint élesítve van, és a negatív párja
  (`test_a4_community_disabled_prod_sqlite_readiness_is_unaffected`) is megvan.
- **A5 / szerződés-artefaktum:** 34 bejegyzés, 31 `mounted` + 3 `known_gap`;
  a `known_gap` állítás igazolva (`challenges.py`-ban tényleg csak
  `POST`/`DELETE` van, listázó/detail GET nincs). Minden bejegyzés `source`
  mezője létező `lib/**` fájlra mutat (34/34). A `known_gap` kanári-teszt
  megakadályozza az elavulást, a valódi-sértés próba
  (`test_a5_real_violation_probe_missing_route_is_caught`) pedig bizonyítja,
  hogy az A5 falszifikálható, nem üres.
- **A6 / runbook:** a `10.0.2.2` emulátor-alias → LAN-IP → tűzfal → `STRUMSIGHT_API_URL`
  → ellenőrző hívás lánc végigvezet; az N1 pontatlanságtól eltekintve mért és
  használható. A §7 kimondja a 3 ismert klienshiányt.
- **Flag-default:** `community_enabled = False` (`config.py:101`) — a sérülékeny
  felület alapból nem él. A B1/B2 súlyosságának ENYHÍTŐJE, nem feloldója: a kör
  célja épp a bekapcsolhatóvá tétel, és a runbook a bekapcsolást tanítja.
- **Titkok:** a diff `api_key|secret|token|password` szűrése a B3 teszt-fixture-ön
  és egy eldobható runbook-példa jelszón (`:111`) kívül nem ad találatot.

## 5. Reprodukció

```bash
# auth-leltár (48 route-metódus, 8 authless)
cd /home/ubuntu/ss-sonnet-impl-e15-r12/backend
/home/ubuntu/music-theory/backend/.venv/bin/python /tmp/verify_authless.py

# a három backend-CI lépés
/home/ubuntu/music-theory/backend/.venv/bin/python -m ruff check app tests
/home/ubuntu/music-theory/backend/.venv/bin/python -m ruff format --check app tests
/home/ubuntu/music-theory/backend/.venv/bin/python -m pytest -q      # 872 passed

# a kötelező gate (PIROS a secrets lépésen)
cd /home/ubuntu/ss-sonnet-impl-e15-r12
tools/round-gate.sh test/app/app_config_test.dart test/app/config/feature_flags_test.dart
```

## 6. A javító kör teendői (prioritási sorrendben)

1. **B1 + B2** — a `privacy_router` és a `handles_router` NE kerüljön be a
   `build_community_router()` aggregátumába; az elhagyás indoklása a
   docstringbe (a routerek saját „not yet exposed / auth lands later"
   docstringjére hivatkozva).
2. **B3** — `# strumsight:allow-secret <indok>` a
   `backend/tests/test_community_mounting.py:236` sor végére.
3. **M1** — az A2 cella legyen KIMERÍTŐ: a felcsatolt community route-ok
   mindegyikén követelje meg az auth-ot, rövid és tételesen indokolt
   kivétel-listával; a B1/B2 visszavétele ezt a cellát pirosra kell vigye.
4. **M2** — mérd ki, kimaradhat-e a `GET /community/profiles/{public_id}` az
   aggregátumból a tilos-zónás suite pirosra vitele nélkül; ha igen, maradjon
   ki, ha nem, kerüljön az M1 kivétel-listájára mért indoklással.
5. **N1** — a runbook block/mute állításának javítása a mért viselkedésre.
6. **N3** — a brief §10 kitöltése (a valódi-sértés próba dokumentálásával).
7. A §7 HÁROM backend-parancsa + a `tools/round-gate.sh` újrafuttatása, mindkettő
   zölden.

## 7. Újra-review után

Ez a szakasz a javító kör utáni második mérés eredményét kapja.
