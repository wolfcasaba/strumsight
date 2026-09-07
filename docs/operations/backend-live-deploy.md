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
STRUMSIGHT_COMMUNITY_MEDIA_ENABLED=false       # marad KI: nincs média-tárhely döntés
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
