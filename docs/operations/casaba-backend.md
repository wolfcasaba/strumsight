# A hosztolt backend: `casaba.app` — amit megmértünk, és amit nem szabad feltételezni

**Mérés dátuma:** 2026-09-12 (E18-R19). Minden szám alább kívülről, a futó
példányról van leolvasva, nem a repó feltételezéseiből.

A build profil: [`casaba_build.json`](../../casaba_build.json).

```bash
flutter build apk --dart-define-from-file=casaba_build.json
```

## A döntő tény: az API NEM a host gyökerén van

```
$ curl -sI https://casaba.app/health
HTTP/1.1 401 Unauthorized
Server: kong/3.9.1
Via: 1.1 Caddy
Www-Authenticate: Basic realm="service"
X-Kong-Response-Latency: 0
```

A `casaba.app` **minden** útvonala — `/`, `/health`, `/docs`, `/api/*`, `/v1/*` —
401-et ad HTTP Basic kihívással, és a Kong válasz-latenciája **0**, tehát semmi nem
ér el egyetlen upstreamet sem.

A StrumSight backend a **`/strumsight`** prefix alatt van felcsatolva, és az a
útvonal nincs Basic mögött:

```
$ curl -s https://casaba.app/strumsight/health
{"status":"ok","version":"0.1.0"}

$ curl -s https://casaba.app/strumsight/health/ready
{"status":"ready"}

$ curl -s https://casaba.app/strumsight/auth/me
{"detail":"Not authenticated"}        # 403 — a FastAPI SAJÁT válasza

$ curl -s https://casaba.app/strumsight/community/ping
{"module":"community"}
```

Az `/auth/me` válasza a bizonyíték arra, hogy a kérés **az app backendjéhez** ér el,
nem a gatewayhez: a Kong 401-et adna Basic kihívással, a FastAPI 403-at adott a saját
`detail` mezőjével. A `community/ping` pedig azt mutatja, hogy a közösségi modul
**szerveroldalon be van kapcsolva** — ez nem flag-kérdés a kliensen.

`/strumsight/openapi.json`: **58 útvonal**, `StrumSight Account API 0.1.0`.

## Miért load-bearing a prefix, és miért van rá őrteszt

Ez az első `STRUMSIGHT_API_URL`, ami **útvonalat** hordoz — minden korábbi érték
origin volt (`http://10.0.2.2:8000`, egy tunnel-host). Az RFC 3986 feloldás szerint
egy absztolút útvonal **lecseréli** a base útvonalát, ami az `/auth/me`-t
`https://casaba.app/auth/me`-vé tenné — amire a gateway 401-et ad. Az app ekkor
„bejelentkezés sikertelen"-t mutatna egy **működő, healthy** backend ellen, és a hiba
hitelesítési problémának látszana.

Megmérve (`test/core/network/api_base_url_prefix_test.dart`): a kliens **megőrzi** a
prefixet —

```
https://casaba.app/strumsight + /auth/login -> https://casaba.app/strumsight/auth/login
https://casaba.app/strumsight + /auth/me    -> https://casaba.app/strumsight/auth/me
https://casaba.app/strumsight + /settings   -> https://casaba.app/strumsight/settings
```

A cella azért marad a repóban, hogy egy jövőbeli kliens-frissítés **itt** bukjon el,
ne a terepen.

## Mit tud kiszolgálni, és mit nem — az app hívásaihoz mérve

Az app 25 API-hívásából **20 ki van szolgálva** a futó példányon. **Öt nincs:**

| Az app hívja | Állapot a futó példányon |
|---|---|
| `GET /community/challenges` | **nincs** (lista) |
| `GET /community/challenges/{id}` | **nincs** (részletek) |
| `GET /community/challenges/{id}/me` | **nincs** (saját nevezés) |
| `POST /diagnostics` | **nincs** (a példányon a diagnosztika ki van kapcsolva) |
| `DELETE /community/profiles/{owner}/followers/{id}` | megvan |

A kihívások **létrehozása és eredmény-beküldése** megvan
(`/community/challenges/{id}/results`, `/invites`, `/leaderboards/{id}`) — ami
hiányzik, az a **lista és a részletek**, vagyis épp az, ahonnan egy felhasználó
eljutna egy ranglistáig. A `CommunityChallengesScreen` ezért **nem tud működni**, amíg
a szerver nem kapja meg ezt a három útvonalat.

A `/diagnostics` hiánya nem hiba: a backend a saját beállítása mögé kapuzza, és egy
prod kliens build amúgy sem kapcsolja be a diagnosztikát (`diagnosticsEnabled` csak
nem-prod környezetben igaz).

## Amit a profil nem szolgál ki

Az app kódjában szerepelnek `/profile`, `/profile/library`, `/profile/progress`,
`/profile/rewards`, `/profile/settings` literálok. Ezek **in-app GoRouter útvonalak**,
nem API-hívások — a beállítás-szinkron valódi endpointja a `/settings`, ami megvan.

## Amit szándékosan NEM kapcsoltunk be

- **`STRUMSIGHT_COMMUNITY_MEDIA`** — a futó példány **egyetlen** media- vagy
  upload-útvonalat sem expose-ol (az `openapi.json`-ból mérve). Bekapcsolva a tanuló
  kapna egy feltöltés-gombot, aminek nincs hova feltöltenie.
- **`STRUMSIGHT_DIAG_TOKEN`** — nincs `/diagnostics`, tehát nincs mit hitelesíteni.
  És ez a fájl **commitolva van**: titok nem kerül bele.

## Ha a gateway Basic-auth kerülne a `/strumsight` elé is

Akkor az app **egyetlen** kérése sem jutna át, beleértve a `/auth/login`-t, mert a
kliens **bearer JWT**-t küld (`auth_interceptor.dart`), Basic credentialt nem. A
javítás ilyenkor a gatewayen van (engedje át a `/strumsight/*`-ot, és hagyja a backend
saját JWT-jére a hitelesítést) — **nem** az appban: Basic credentialt az appba tenni
azt jelentené, hogy egy titok a binárisba kerül, amit a `check_secrets` kapu
joggal utasítana vissza.
