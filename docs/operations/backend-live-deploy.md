# Élő backend-telepítés — `casaba.app/strumsight` (2026-09-05)

> **Mit vált ki:** a Lab-mód **cloudflared quick-tunnelét**. Az alagút
> URL-je minden újraindításkor változott, ezért a `lab_build.json`-t (és vele
> egy APK-t) újra kellett gyártani. Helyette állandó, TLS-terminált útvonal áll.
>
> Ez a dokumentum a MÉRT, reprodukált telepítést rögzíti. A general-purpose
> deploy-szekvencia változatlanul a
> [`backend-deploy.md`](backend-deploy.md) (ADR 0449); az ott szereplő
> „There is no running staging infrastructure on this box today" mondat
> 2026-09-05 óta ELAVULT erre a boxra.

## 1. Topológia

```
telefon ──HTTPS──▶ casaba.app (Caddy, Let's Encrypt)
                     ├── /auth/*, /casaba.apk, ...  → a Casaba/Messenger felületek
                     ├── handle_path /strumsight/*  → 127.0.0.1:8010  (StrumSight API)
                     └── handle (catch-all)         → 127.0.0.1:8000  (Supabase Kong)
                                                          │
                     StrumSight compose-stack ────────────┘ (külön hálózat)
                       ├── api  strumsight-backend-deploy  (uvicorn, nem-root)
                       └── db   postgres:17-alpine         (dedikált volume)
```

**A Postgres SZÁNDÉKOSAN dedikált.** A boxon fut a Casaba/Messenger Supabase
stackje is; ha a StrumSight fiókok abban laknának, annak életciklusa
(leállás, backup-visszaállítás) magával vinné őket. Külön volume, külön
docker-hálózat, a `db`-t csak az `api` éri el.

**A `handle_path` LEVÁGJA a prefixet:** a backend a saját gyökerén kapja a
kérést (`/health`, `/auth/login`, `/settings`), ezért a Flutter-oldali
`STRUMSIGHT_API_URL=https://casaba.app/strumsight` bázis-URL elé semmit nem
kell fűzni. A blokk a catch-all ELŐTT áll — mögötte a Kong nyelné el.

## 2. Miért útvonal-prefix, és nem aldomain

A `casaba.app` DNS-e GoDaddy-nál van, és a boxon nincs hozzá API-kulcs, ezért
egy `strumsight.casaba.app` A-rekord **kézi** művelet lenne. Az útvonal-prefix
DNS-változtatás nélkül működik.

**Ha később mégis aldomain kell:** egy `A strumsight → 130.61.34.141` rekord
a GoDaddy-panelen, majd a Caddyfile-ban egy önálló site-blokk
(`strumsight.casaba.app { reverse_proxy 127.0.0.1:8010 }`) — a `handle_path`
blokk ilyenkor törölhető, és a `STRUMSIGHT_API_URL` az aldomainre áll.

## 3. Az artefaktumok

| Hol | Mi |
|---|---|
| `/home/ubuntu/strumsight-api` | a repó deploy-checkoutja (image-forrás) |
| `/home/ubuntu/strumsight-deploy/docker-compose.yml` | a stack (api + db) |
| `/home/ubuntu/strumsight-deploy/runtime.env` | futásidejű profil, **0600, NEM verziókövetett** |
| `/home/ubuntu/strumsight-deploy/Dockerfile.deploy` | a repó image-e + a Postgres driver |
| `/etc/caddy/Caddyfile` | a `handle_path /strumsight/*` blokk |

A `runtime.env` a repó `backend/deploy/staging.env.example` mintáját követi.
Titkai `openssl rand`-dal generáltak, és **soha nem kerülnek kimenetbe vagy
commitba** (AGENTS.md §5). Csere: új érték a fájlba, majd §5 újraindítás.

### 3.1 Miért van külön deploy-image

A `backend/Dockerfile` SZÁNDÉKOSAN nem tartalmazza a psycopg-t
(`backend/README.md`: "the driver is intentionally not a mandatory local/test
dependency"). A `Dockerfile.deploy` a repó digest-pinelt image-ére húz rá egy
`psycopg[binary]` réteget, és visszaállítja a nem-root felhasználót.

## 4. A telepítés mért lépései

```bash
# 1. image a repó Dockerfile-jából
cd /home/ubuntu/strumsight-api/backend && docker build -t strumsight-backend:<sha> .

# 2. deploy-image a driverrel
cd /home/ubuntu/strumsight-deploy && docker build -t strumsight-backend-deploy:<sha> -f Dockerfile.deploy .

# 3. stack indítása (a db healthcheckje kapuzza az api-t)
docker compose --env-file runtime.env up -d

# 4. readiness — a traffic gate ezt a predikátumot használja
curl -s http://127.0.0.1:8010/health/ready     # {"status":"ready"}
```

Az image `CMD`-je futtatja az `alembic upgrade head`-et az uvicorn előtt
(migration-before-start), a traffic gate pedig a második, mindig aktív
réteg: fej-eltérés esetén minden üzleti végpont `503 not_ready`.

## 5. Üzemeltetés

```bash
cd /home/ubuntu/strumsight-deploy
docker compose --env-file runtime.env ps          # állapot
docker compose --env-file runtime.env logs -f api # naplók
docker compose --env-file runtime.env restart api # újraindítás
docker compose --env-file runtime.env down        # leállítás (a volume MEGMARAD)
```

Újraindulás-állóság: a konténerek `restart: unless-stopped` policyvel futnak,
a `docker.service` pedig `enabled` — a stack a box újraindulása után magától
feláll.

### 5.1 A megbízható proxy-hop beállítása (R14)

**A probléma (mért, audit §5.4):** a login/register throttle (10/perc,
5/perc) a kliens IP-jére számol, de a Caddy → `127.0.0.1:8010` topológiában a
konténer MINDEN hívót ugyanazon a címen lát, ezért a keret az összes
felhasználóra közös; a 429 az appban „hálózati hiba"-ként jelenik meg. A
javítás az `X-Forwarded-For` első hopja — de KIZÁRÓLAG akkor, ha a közvetlen
socket-peer egy kimondottan megbízhatónak jelölt cím
(`backend/app/client_ip.py`); a fejlécet feltétel nélkül elhinni annyi, mint
a throttle-t megszüntetni (bárki választhatna magának vödröt).

**1. Mérd meg a hopot** (ne tippeld — hálózati módtól függ):

```bash
cd /home/ubuntu/strumsight-deploy
# a) a konténer által látott forráscím a naplóból (bármely hibás belépés után):
docker compose --env-file runtime.env logs api | grep auth.login_failed | tail -3
#    -> "... client=172.18.0.1 ..." — bridge módban a docker-átjáró címe

# b) ugyanez a hálózat felől, hívás nélkül:
docker network inspect "$(docker compose --env-file runtime.env ps -q api \
  | xargs docker inspect -f '{{range $k,$v := .NetworkSettings.Networks}}{{$k}}{{end}}')" \
  -f '{{ (index .IPAM.Config 0).Gateway }}'
```

Publikált porton (`ports: 127.0.0.1:8010:8000`) a docker-proxy NAT-ol, ezért
a bridge-átjáró címe látszik; `network_mode: host` esetén `127.0.0.1`.

**2. Írd be a `runtime.env`-be** (JSON-lista, mint a CORS-nál; üres *string*
bootoláskor JSON-hiba, ezért vagy hagyd ki a kulcsot, vagy `[]`):

```
STRUMSIGHT_TRUSTED_PROXY_IPS=["172.18.0.1"]
```

Ugyanez az érték megy az uvicorn `--forwarded-allow-ips` kapcsolójába is (a
`backend/Dockerfile` `CMD`-je alakítja át vesszős listává), így az ASGI- és
az alkalmazásréteg nem tud egymásnak ellentmondani. Csak konkrét címek —
tartomány és `*` soha.

**3. A Caddy ÍRJA FELÜL a fejlécet.** A `reverse_proxy` alapból HOZZÁFŰZI a
peer címét a hívó által küldött `X-Forwarded-For`-hoz, tehát felülírás nélkül
a hívó elé tudná tenni a saját, hamis első hopját:

```
handle_path /strumsight/* {
    reverse_proxy 127.0.0.1:8010 {
        header_up X-Forwarded-For {remote_host}
    }
}
```

`sudo caddy validate --config /etc/caddy/Caddyfile && sudo systemctl reload caddy`.
Ha ez a sor nincs meg, NE vegyél fel megbízható hopot: a közös vödrű throttle
kisebb baj, mint a bárki által megkerülhető.

**4. Indíts újra és ellenőrizd** — a `runtime.env` változása új konténert
igényel (a `restart` a régi környezettel indulna):

```bash
docker compose --env-file runtime.env up -d
curl -s http://127.0.0.1:8010/health/ready              # {"status":"ready"}
docker compose --env-file runtime.env logs --since 5m api | grep auth.login_failed
#    -> a "client=" mező már a TELEFON címe, nem a docker-átjáróé
```

### 5.2 Bejelentkezési hibák olvasása (R14)

A `401` szándékosan egyforma az ismeretlen e-mailre és a rossz jelszóra (a
regisztrált címek halmaza nem szivároghat). Az ok a szerver naplójában van,
e-mail és jelszó NÉLKÜL — az e-mail helyett egy egyirányú ujjlenyomat
(`sha256(kisbetűs e-mail)` első 12 hexa jegye):

```bash
docker compose --env-file runtime.env logs --since 1h api | grep auth.
# auth.login_failed reason=unknown_email client=203.0.113.7 email_hash=0748ebb7f38a
# auth.login_failed reason=bad_password  client=203.0.113.7 email_hash=1c9a…
# auth.register_conflict reason=email_exists client=203.0.113.7 email_hash=1c9a…
```

`reason=unknown_email` → ilyen fiók nincs (a felhasználó másik címmel
regisztrált, vagy elgépelte); `reason=bad_password` → a fiók megvan, a jelszó
nem egyezik; `register_conflict` → a cím már foglalt. Egy gyanított címet így
lehet a naplóhoz kötni (a napló maga sosem tartalmazza):

```bash
printf '%s' 'valaki@example.com' | sha256sum | cut -c1-12
```

## 6. Mért eredmény (2026-09-05)

| Mérés | Eredmény |
|---|---|
| `alembic current` | `e09_r27_0020 (head)`, Postgres 17 |
| táblák száma | 29 |
| `GET /strumsight/health` | `{"status":"ok","version":"0.1.0"}` |
| `GET /strumsight/health/ready` | `{"status":"ready"}` |
| `POST /strumsight/auth/register` | `201`, JWT (141 bájt) |
| `GET /strumsight/auth/me` | `200`, a regisztrált fiók |
| `PUT /strumsight/settings` → `GET` | az írt érték visszaolvasva (`theme_mode=dark`, `tuning_a4=442`) |
| a Messenger felületei a változás után | `casaba.app/auth/reset` → `200` (sértetlen) |

A próba-fiók a mérés után törölve; a `POST /auth/login` vele `401`-et ad.

## 7. Amit ez a telepítés NEM kapcsol be

- **`STRUMSIGHT_COMMUNITY_ENABLED=false`** — a community routerek nincsenek
  felcsatolva. A Flutter-oldali repository-k (`E17-R08`..`E17-R11`) azóta
  elkészültek, a bekapcsolás pontos lépéssora a lenti **§7.1**.
- **`STRUMSIGHT_TUTOR_ENABLED=false`** — az AI tutor útvonalai
  (`/tutor/capability`, `/tutor/stream`, `/tutor/turn`) nincsenek felcsatolva,
  a kliens 404-et kap. A bekapcsolás pontos lépéssora a lenti **§7.2**; ez az
  EGYETLEN felület, amelyhez harmadik fél (a modellszolgáltató) is hozzájut
  adathoz, ezért külön kulcsot ÉS külön adatvédelmi döntést igényel.
- **`STRUMSIGHT_DIAGNOSTICS_ENABLED=false`** és
  **`STRUMSIGHT_APK_DOWNLOAD_ENABLED=false`** — a Lab-felületek sötétek.
  A diagnosztika bekapcsolása nem-alapértelmezett `STRUMSIGHT_DIAG_TOKEN`-t is
  követel, különben a folyamat nem bootol.
- **A detektálás továbbra is 100%-ban on-device.** Ez a szolgáltatás fiókot és
  beállítás-szinkront ad; hangot sosem lát, és az app kijelentkezve teljesen
  használható.

### 7.1 A community felület bekapcsolása — pontos lépéssor

Titok nem kell hozzá, csak kapcsolók. A kapcsolók függetlenek egymástól
(`backend/app/community/__init__.py`): a mester-kapcsoló nélkül egyik
al-kapcsoló sem csatol fel semmit.

**1. Kulcsok a `runtime.env`-be** (a fájl `0600`, nem verziókövetett):

```
STRUMSIGHT_COMMUNITY_ENABLED=true              # mester: a 15 router felcsatolása
STRUMSIGHT_COMMUNITY_WRITES_ENABLED=true       # poszt/komment/social-graph írás
STRUMSIGHT_COMMUNITY_CLUBS_ENABLED=true        # a clubs router (mind-vagy-semmi)
STRUMSIGHT_COMMUNITY_LEADERBOARD_ENABLED=true  # a leaderboards router
STRUMSIGHT_COMMUNITY_MEDIA_ENABLED=false       # a média-router; a lépéssor: §7.3
```

`STRUMSIGHT_ENV=prod` mellett a community readiness Postgres-t követel
(`community_requires_postgres`); ez a stack Postgres-en fut, tehát teljesül.
A `handles` és a `privacy` router szándékosan felcsatolatlan marad (ADR 0497
D6, hitelesítés nélküli írás-felület) — ezeket ez a kapcsoló SEM hozza fel.

**2. Újraindítás** — módosított env új konténert igényel:

```bash
cd /home/ubuntu/strumsight-deploy
docker compose --env-file runtime.env up -d
```

**3. Készenlét és felcsatolás-ellenőrzés** (a `/health/ready` a community
migrációs fejét is nézi, ha a mester-kapcsoló be van kapcsolva):

```bash
curl -s http://127.0.0.1:8010/health/ready
# {"status":"ready"}   — nem-ready esetén a "reason" mondja meg, mi hiányzik
#                        (community_requires_postgres | migration_mismatch | …)

# felcsatolt-e a router? token nélkül 403 = FEL van csatolva, 404 = NINCS
# (mérve: a bekapcsolás előtt mind a négy 404, utána mind 403)
for p in /community/profiles/me /community/feed /community/clubs \
         /community/leaderboards/00000000-0000-0000-0000-000000000000; do
  printf '%s -> ' "$p"
  curl -s -o /dev/null -w '%{http_code}\n' "http://127.0.0.1:8010$p"
done
# a leaderboards útvonalnak KELL az id: a csupasz /community/leaderboards
# bekapcsolva is 404 — az al-kapcsoló állapotát a fenti, id-s út mutatja

# ugyanez kívülről, a Caddy útvonalán:
curl -s -o /dev/null -w '%{http_code}\n' https://casaba.app/strumsight/community/profiles/me
```

**4. Mit mutat a Flutter development APK.** A `build-apk.yml` csak
`STRUMSIGHT_ENV=development`-et ad, és a `FeatureFlags.forShippedBuild`
development alatt a community felületeket (írás, klubok, ranglista) BE-re
oldja fel — a kliensoldali kapu tehát már ma nyitva van, a szerver volt
zárva:

| | Közösség fül a development APK-ban |
|---|---|
| **Flip előtt** (`STRUMSIGHT_COMMUNITY_ENABLED=false`) | „Community is not enabled on this server yet" kártya + Retry (R12, `community_availability.dart`): minden `/community/**` a FastAPI csupasz 404-ét adja, mert a router fel sem csatolódik |
| **Flip után** | a valódi kapu-lánc: kijelentkezve „Sign in to use Community", belépve, profil nélkül „Create your Community profile", profillal a feed/klub/ranglista képernyők élő adattal |

A Retry gomb szándékosan újrapróbál — a flip után a KÖVETKEZŐ hívás már
sikerül, új APK nem kell. Ha a flip után is az „on this server yet" kártya
jön, a router nem csatolódott fel: a 3. lépés `curl`-je 404-et ad, és a
`/health/ready` `reason` mezője mondja meg, miért.

**Visszakapcsolás** ugyanígy: a kulcsokat `false`-ra, `up -d`, és a kliens
visszaesik az „on this server yet" kártyára — adat nem vész el, csak a
felület tűnik el.

### 7.2 Az AI tutor provider bekapcsolása — pontos lépéssor

**R23 előtt ez a kapcsoló félrevezető volt:** a `main.py` FELTÉTEL NÉLKÜL
`FakeProviderGateway()`-t épített, tehát a tutor bekapcsolva is konzervdobozos
választ adott, akárhogy állt a `STRUMSIGHT_TUTOR_PROVIDER`. R23 óta a
composition root (`backend/app/main.py::_build_tutor_gateway`) a konfigurált
adaptert építi, a `fake` pedig az alapértelmezés és a visszaesési út marad.

**Négy kulcsot kell állítani, és mind a négy kötelező** — bármelyik hiánya
bootolás közben elhasal (`_guard_tutor_provider`), nem futásidőben, nem
csendben:

| Kulcs | Érték | Miért |
|---|---|---|
| `STRUMSIGHT_TUTOR_PROVIDER` | `anthropic` (vagy `openai`) | melyik ADAPTER épül; `fake` az alapértelmezés |
| `STRUMSIGHT_TUTOR_MODEL` | `claude-sonnet-5` | a konkrét modell-azonosító |
| `STRUMSIGHT_TUTOR_ALLOWED_PROVIDERS` | `{"anthropic": ["claude-sonnet-5"]}` | a JSON allowlist — a registry ehhez validál |
| `STRUMSIGHT_TUTOR_API_KEY` | a szolgáltató kulcsa | a szerveren marad, a kliens SOSEM látja |

A provider és az allowlist szándékosan KÉT külön kulcs: az első azt mondja meg,
melyik adapter létezik, a második azt, mi van engedélyezve. Az allowlist
alapértéke `{"fake": ["fake-model"]}` marad — egy elgépelt provider- vagy
modellnév tehát nem „majdnem működik", hanem meg sem indul.

**1. Kulcsok a `runtime.env`-be** (a fájl `0600`, nem verziókövetett):

```
STRUMSIGHT_TUTOR_PROVIDER=anthropic
STRUMSIGHT_TUTOR_MODEL=claude-sonnet-5
STRUMSIGHT_TUTOR_ALLOWED_PROVIDERS={"anthropic": ["claude-sonnet-5"]}
STRUMSIGHT_TUTOR_API_KEY=…            # a titokkezelőből, sosem kézzel ide
STRUMSIGHT_TUTOR_ENABLED=true
```

A négy kulcs egyetlen `up -d`-ben megy fel; ha mégis lépésenként haladsz,
**a kulcs + a provider + az allowlist megy előbb, és a
`STRUMSIGHT_TUTOR_ENABLED=true` legutoljára.** A veszélyes köztes állapot az
`ENABLED=true` + `PROVIDER=anthropic` **kulcs nélkül**: ilyenkor a
`_guard_tutor_provider` `RuntimeError`-t dob, a folyamat el sem indul, és mivel
a `docker compose up -d` a régi konténert már leállította, nem „csak a tutor"
esik ki, hanem a bejelentkezés is. (Az `ENABLED=true` önmagában, még `fake`
providerrel, ártalmatlan: a konzervdobozos válasz jön fel.)

**2. Újraindítás** — módosított env új konténert igényel:

```bash
cd /home/ubuntu/strumsight-deploy
docker compose --env-file runtime.env up -d
docker compose --env-file runtime.env logs --since 2m api | tail -20
```

Ha a folyamat nem jön fel, a napló utolsó sora MEGMONDJA, melyik kulcs
hiányzik — a hibaüzenetek a kulcs NEVÉT írják ki, az ÉRTÉKÉT soha.

**3. Ellenőrzés — a capability-végpont most őszintén válaszol:**

```bash
curl -s http://127.0.0.1:8010/tutor/capability
# {"enabled":true,"version":"v1","streaming":false,
#  "provider":"anthropic","model":"claude-sonnet-5"}
#
# flip ELŐTT: 404 (a router fel sem csatolódik)
# flip UTÁN, de fake providerrel: "provider":"fake","model":"fake-model"
```

A válasz a kulcsot **nem** tartalmazza, és nem is tartalmazhatja: a
`TutorCapabilityResponse` egy zárt allowlist-séma, a kulcs egyetlen mezőjének
sem forrása. A `provider`/`model` nem titok — pont attól használható a flip
ellenőrzésére kívülről is:

```bash
curl -s https://casaba.app/strumsight/tutor/capability
```

Egy valódi turn hitelesítést kíván (`POST /tutor/stream`, bearer JWT), tehát a
végponti füst-próba a telefonról vagy egy próba-fiókkal megy — a
`tool/release/live_backend_smoke.py` szándékosan kihagyja a tutort.

**4. Ha a provider hibázik: mit mond a napló.** A kliens felé minden
provider-hiba UGYANAZ marad (`502` / `provider_error` SSE-keret, időtúllépésnél
`504` / `provider_timeout`) — a hibatest, a kulcs és a prompt SOSEM megy ki és
naplóba sem kerül. Az operátor viszont osztályozva látja, mi történt:

```bash
docker compose --env-file runtime.env logs api | grep 'Tutor provider call failed'
# Tutor provider call failed (classification=configuration, http_status=401)
```

| `classification` | Mi váltja ki | Teendő |
|---|---|---|
| `configuration` | HTTP `401`/`403` (kulcs rossz vagy visszavont), `404` (rossz modell-azonosító vagy base URL), illetve az `authentication_error`/`permission_error`/`not_found_error`/`billing_error` stream-keretek | operátori hiba — újrapróbálás NEM segít; ellenőrizd a kulcsot és a `STRUMSIGHT_TUTOR_MODEL`-t |
| `busy` | HTTP `429`, `529` és minden `5xx`, illetve a `rate_limit_error`/`overloaded_error`/`api_error` keret | átmeneti — a felhasználó újrapróbálhatja; ha tartós, a provider-oldali kvótát nézd |
| `invalid_request` | HTTP `400`/`413`/`422`, illetve `invalid_request_error`/`request_too_large` | a kérés alakja/mérete — a lenti 5. pont limitkulcsait nézd |
| `timeout` | `STRUMSIGHT_TUTOR_TIMEOUT_SECONDS` letelt, vagy a provider `timeout_error` keretet küldött | emeld a timeoutot vagy csökkentsd a `MAX_OUTPUT_BYTES`-t |
| `transport` | kapcsolat/TLS/protokoll hiba (a cél-URL-t tartalmazó kivételszöveg eldobva) | hálózat/DNS a konténerből |
| `malformed_response` / `incomplete_response` | nem SSE-válasz, hibás JSON-keret, vagy `message_stop` nélkül záruló stream | a csonka válasz zárt hibával esik el, nem rövid válaszként megy ki |

A `http_status=None` azt jelenti, hogy HTTP-státusz nem is született (időtúllépés,
kapcsolat-hiba), nem azt, hogy elveszett.

**5. Költség és korlátok.** A meglévő kapuk a providertől függetlenül élnek, és
a flip után VALÓDI pénzt védenek — érdemes a bekapcsolással egy menetben
átnézni őket:

| Kulcs | Alapérték | Mit korlátoz |
|---|---|---|
| `STRUMSIGHT_TUTOR_MAX_OUTPUT_BYTES` | `2000` | a válasz hossza; ebből számolódik a provider `max_tokens` értéke is (~4 bájt/token, tehát 500 token) |
| `STRUMSIGHT_TUTOR_MAX_REQUEST_BYTES` | `4000` | egy üzenet mérete |
| `STRUMSIGHT_TUTOR_MAX_HISTORY_MESSAGES` | `20` | a felküldött előzmény hossza |
| `STRUMSIGHT_TUTOR_MAX_CONTEXT_BYTES` | `8000` | az összeállított kontextus mérete |
| `STRUMSIGHT_TUTOR_RATE_LIMIT_MAX` / `_WINDOW` | `30` / `60` | kérés/perc felhasználónként |
| `STRUMSIGHT_TUTOR_DAILY_TOKEN_LIMIT` | `50000` | napi token-budget felhasználónként |
| `STRUMSIGHT_TUTOR_TIMEOUT_SECONDS` | `30.0` | a provider-hívás időkorlátja (túllépve zárt hibával, `provider_timeout` SSE-kerettel esik el) |

A limiterek **folyamat-lokálisak** (ugyanaz a mérés, mint az auth-throttle-nál,
`backend/README.md`): több worker esetén nem osztoznak a számlálón, tehát a
tényleges napi plafon ~worker-számszor nagyobb. Egyetlen workerre méretezz,
vagy tedd a limitet közös tárba, mielőtt a számla ezt méri meg helyetted.
A tényleges provider-oldali `output_tokens` minden turn után egy INFO sorba
kerül (`Tutor provider stream completed (output_tokens=…)`) — szám, semmi más:

```bash
docker compose --env-file runtime.env logs api | grep 'Tutor provider stream'
```

**6. Adatvédelem — mi hagyja el a szervert.** Ez a flip a StrumSight EGYETLEN
olyan útvonala, ahol felhasználói szöveg harmadik félhez kerül. A
`docs/privacy/data-inventory.yaml` `tutor_stream` sora írja le, mi megy fel a
kliensről: a tanuló szabadszöveges üzenete + a prompt-építő által
összeállított, redaktált kontextus-pillanatkép, `legal_basis: consent`, a
kliensoldali kapu a `TutorConsent.modelUseGranted`. A szerver ezt a két dolgot
adja tovább a providernek — a kontextus a Messages API `system` mezőjében, az
üzenet és az előzmény a `messages` tömbben —, semmi mást: nincs benne
felhasználó-azonosító, e-mail, eszközazonosító vagy hangadat (a detektálás
100%-ban on-device marad, §7).

A backend a prompt-tartalmat SEHOL nem naplózza (a napló csak a felhasználó
azonosítóját és token-számokat lát), és a provider hibatestje sosem kerül sem
naplóba, sem a kliens felé — a `ProviderError`/`ProviderTimeoutError`
provider-semleges, redaktált kivétel, amit a router `502`/`504`-re, a
stream-transzport pedig `provider_error`/`provider_timeout` SSE-keretre képez.

> **Nyitott tétel a flip előtt (R23 lelet, NEM ebben a körben javítva):** az
> adat-leltár `tutor_stream` sorának `storage` mezője ma még csak
> „backend (the configured STRUMSIGHT_API_URL host)"-ot mond. Amint a
> `STRUMSIGHT_TUTOR_PROVIDER` nem `fake`, ez hiányos: a harmadik fél
> (modellszolgáltató) mint adatfeldolgozó és a nála érvényes megőrzés
> hiányzik a sorból. A `docs/privacy/**` szerkesztése ezen a körön kívül
> esett — a flip ELŐTT a leltárt ki kell egészíteni, különben a beleegyezési
> szöveg nem fedi a valóságot.

**Visszakapcsolás:** `STRUMSIGHT_TUTOR_ENABLED=false`, `up -d` — a routerek
eltűnnek, a kliens a `/tutor/capability` 404-jéből tudja, hogy nincs
felhő-tutor, és a helyi stub-ra esik vissza. A providert visszaállítani
`fake`-re önmagában is elég ahhoz, hogy egyetlen bájt se hagyja el a szervert.

### 7.3 Community média-feltöltés bekapcsolása — pontos lépéssor

**A kapcsoló R27 előtt ÜRESEN állt.** A `STRUMSIGHT_COMMUNITY_MEDIA_ENABLED`
a Kör 1 óta létezett, de nem csatolt fel semmit: a Kör 18/19 aláírt-URL-es
szolgáltatás (`services/media_upload_service.py`) sosem kapott routert, és a
hozzá képzelt objektum-tároló nem része ennek a deploynak. R27 óta a kapcsoló
egy VALÓDI felületet kapuz — `POST/GET/DELETE /community/media` —, amely a
bájtokat közvetlenül a backendbe tölti, ott újrakódolja és egy helyi köteten
tárolja.

**A két alapértelmezés SZÁNDÉKOSAN fail-closed.** A flag felkapcsolása
önmagában NEM tesz elfogadhatóvá egyetlen feltöltést sem:

| kapcsoló | alapértelmezés | mit csinál |
|---|---|---|
| `STRUMSIGHT_MEDIA_SCANNER` | `disabled` | a *disabled* adapter MINDEN feltöltést elutasít (`scanner_not_configured`). Nincs átengedő („pass-through") adapter: egy vírusirtó, ami ránézés nélkül mond tisztát, rosszabb a semminél, mert a sor, az üzemeltető és az audit onnantól azt olvassa, hogy a bájtokat átvizsgálták. |
| `STRUMSIGHT_MEDIA_AUDIO_TRANSCODER` | `disabled` | minden HANG-feltöltés elutasítva (`audio_transcoder_unavailable`). A kép újrakódolása a folyamaton belül, Pillow-val történik (kemény függőség); a hanghoz külső kódoló kell, amit ez a repó nem szállít. |

Kép-feltöltéshez tehát clamd KELL. Hang-feltöltéshez clamd ÉS egy `ffmpeg`.

**1. Kötet és clamd** (a kötet a konténeren kívül él, hogy egy image-csere ne
vigye el a felhasználók tartalmát):

```bash
# a) a médiakötet — csak a szolgáltatás felhasználója olvassa
sudo install -d -o 10001 -g 10001 -m 0700 /srv/strumsight/media

# b) clamd UNIX socketen (hálózati kitettség nélkül); a socketet
#    ugyanabba a névtérbe kell bekötni, ahol az api fut
sudo apt-get install -y clamav-daemon && sudo freshclam
sudo systemctl enable --now clamav-daemon
ls -l /var/run/clamav/clamd.ctl        # ennek léteznie kell
```

**2. Kulcsok a `runtime.env`-be:**

```
STRUMSIGHT_COMMUNITY_ENABLED=true
STRUMSIGHT_COMMUNITY_WRITES_ENABLED=true
STRUMSIGHT_COMMUNITY_MEDIA_ENABLED=true        # a media router felcsatolása
STRUMSIGHT_MEDIA_ROOT=/srv/strumsight/media    # a tartalom-címzett tároló gyökere
STRUMSIGHT_MEDIA_SCANNER=clamd                 # a fail-closed alapértelmezés feloldása
STRUMSIGHT_MEDIA_SCANNER_SOCKET=/var/run/clamav/clamd.ctl   # ha üres: host/port
# STRUMSIGHT_MEDIA_SCANNER_HOST / _PORT        # csak ha nincs UNIX socket
# STRUMSIGHT_MEDIA_SCANNER_TIMEOUT_SECONDS=10
# STRUMSIGHT_MEDIA_MAX_IMAGE_BYTES=8388608     # 8 MiB
# STRUMSIGHT_MEDIA_MAX_AUDIO_BYTES=20971520    # 20 MiB — csak transcoderrel él
# STRUMSIGHT_MEDIA_MAX_ITEMS_PER_PROFILE=50    # fiókonkénti élő sor-kvóta
# STRUMSIGHT_MEDIA_UPLOAD_RATE_LIMIT_MAX=20    # IP-nkénti csúszóablak…
# STRUMSIGHT_MEDIA_UPLOAD_RATE_LIMIT_WINDOW=3600  # …másodpercben
# STRUMSIGHT_MEDIA_IMAGE_MAX_DIMENSION=2048    # a hosszabb él az újrakódolás után
# STRUMSIGHT_MEDIA_IMAGE_QUALITY=82
# STRUMSIGHT_MEDIA_REVIEW_REQUIRED=false       # true: a kész sor `review`-ban parkol
# STRUMSIGHT_MEDIA_AUDIO_TRANSCODER=ffmpeg     # csak ha van ffmpeg a konténerben
# STRUMSIGHT_MEDIA_FFMPEG_PATH=ffmpeg
# STRUMSIGHT_MEDIA_AUDIO_MAX_DURATION_SECONDS=180
```

A compose-fájlban a kötetet és a socketet is be kell kötni:

```yaml
    volumes:
      - /srv/strumsight/media:/srv/strumsight/media
      - /var/run/clamav/clamd.ctl:/var/run/clamav/clamd.ctl
```

**3. Migráció, majd újraindítás** — az `e09_r28_0021` revízió hozza létre a
`community_media_uploads` táblát:

```bash
cd /home/ubuntu/strumsight-deploy
docker compose --env-file runtime.env run --rm api alembic upgrade head
docker compose --env-file runtime.env up -d
curl -s http://127.0.0.1:8010/health/ready     # {"status":"ready"}
```

**4. Felcsatolás- és fail-closed-ellenőrzés.** A kapu REGISZTRÁCIÓS: flip
előtt az útvonal nem is létezik, tehát a csupasz 404 és a hitelesítési 403
különbsége mondja meg az állapotot.

```bash
# felcsatolt-e? token nélkül 403 = FEL van csatolva, 404 = NINCS
curl -s -o /dev/null -w '%{http_code}
' -X POST http://127.0.0.1:8010/community/media

# a fail-closed alapértelmezés PRÓBÁJA (csináld meg, MIELŐTT a scanner=clamd
# sort beteszed): a válasz 201, a törzsben state=rejected +
# rejection_code=scanner_not_configured — ez a helyes, biztonságos állapot,
# nem hiba
curl -s -H "Authorization: Bearer $TOKEN" \
     -F 'file=@/tmp/probe.jpg' http://127.0.0.1:8010/community/media

# clamd bekapcsolása után ugyanez: state=ready, és a bájtok visszakérhetők
curl -s -o /dev/null -w '%{http_code}\n' -H "Authorization: Bearer $TOKEN" \
     http://127.0.0.1:8010/community/media/$PUBLIC_ID
```

**Amit a felület a bájtokkal tesz** (a három korábban nyitott threat-model
tétel, `docs/security/community-threat-model.md` §6.2):

1. **méret** — a kaput a ténylegesen beolvasott bájtok döntik el, nem a
   `Content-Length` fejléc;
2. **magic-byte** — a fájlnév és a multipart `Content-Type` SEMMIT nem
   befolyásol; nyolc engedélyezett formátum van, minden más elutasítva, és az
   SVG/HTML külön kódot kap;
3. **vírusirtó** — clamd `INSTREAM` az EREDETI bájtokon (nem az újrakódolt
   kimeneten: azt a támadó sosem küldte);
4. **újrakódolás** — a tárolt bájt az `enkóder` kimenete, tehát EXIF/GPS,
   ICC, XMP és a fájl végére fűzött „polyglot" függelék nem éli túl;
5. **tárolás** — tartalom-címzett (`<sha256[0:2]>/<sha256[2:4]>/<sha256>`),
   így egyetlen kérés-mező sem lesz útvonal-szegmenssé.

**Visszakapcsolás.** `STRUMSIGHT_COMMUNITY_MEDIA_ENABLED=false`, `up -d` — az
útvonalak eltűnnek, a kliens visszaesik a szöveg-only szerkesztőre. A
`STRUMSIGHT_MEDIA_ROOT` kötetet **ne töröld**: a migráció visszavonása (`alembic
downgrade -1`) is csak a TÁBLÁT ejti, a felhasználók fájljait szándékosan
érintetlenül hagyja, hogy egy újra-felhúzás a bájtokat a helyükön találja.

## 8. Egy MÉRT hibaosztály, amit ez a telepítés tárt fel

Az első Postgres-indítás elhasalt:

```
psycopg.errors.DatatypeMismatch: column "is_read" is of type boolean
but default expression is of type integer
```

Három community-migráció `sa.text("0")` / `sa.text("1")` alakot használt
`sa.Boolean()` oszlopon — SQLite-on jó, Postgresen nem. Mivel MINDEN meglévő
migrációs teszt SQLite-on fut, a zöld CI a Postgres-útról semmit nem
bizonyított. Javítás + a hibaosztályt mérő statikus őr: PR #589.

**Tanulság:** egy „ajánlott" adatbázis, amin sosem futott a migráció, nem
ajánlás, hanem feltételezés.
