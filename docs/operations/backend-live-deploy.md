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

- **`STRUMSIGHT_COMMUNITY_ENABLED=false`** — a 13 community router nincs
  felcsatolva. A bekapcsolás az `E17-R13` tárgya, a Flutter-oldali
  repository-k (`E17-R08`..`E17-R11`) elkészülte UTÁN.
- **`STRUMSIGHT_DIAGNOSTICS_ENABLED=false`** és
  **`STRUMSIGHT_APK_DOWNLOAD_ENABLED=false`** — a Lab-felületek sötétek.
  A diagnosztika bekapcsolása nem-alapértelmezett `STRUMSIGHT_DIAG_TOKEN`-t is
  követel, különben a folyamat nem bootol.
- **A detektálás továbbra is 100%-ban on-device.** Ez a szolgáltatás fiókot és
  beállítás-szinkront ad; hangot sosem lát, és az app kijelentkezve teljesen
  használható.

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
