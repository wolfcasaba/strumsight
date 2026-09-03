# Device Backend Runbook — running the account/Community API against a real phone

- **Round:** E15-R12, [ADR 0497](../adr/0497-community-router-mounting-and-client-contract-parity.md)
- **Audience:** whoever wants to see the Community screens against a live
  backend on an actual Android device (not the emulator, where
  `10.0.2.2` already works out of the box per the backend README).

This is the missing step between "the backend runs on my laptop" and "the
phone in my hand can talk to it" — `10.0.2.2` is an **emulator-only**
loopback alias; a physical device on the same Wi-Fi needs the laptop's real
LAN IP, and `uvicorn`'s default bind (`127.0.0.1`) only accepts connections
from the laptop itself.

## 1. Start the backend, bound to the LAN, not just localhost

```bash
cd backend
.venv/bin/python -m alembic upgrade head
.venv/bin/uvicorn app.main:app --host 0.0.0.0 --port 8000
```

`--host 0.0.0.0` is the load-bearing flag — without it, `uvicorn` only
accepts connections from `127.0.0.1` and every request from the phone times
out with no server-side log line at all (the connection never reaches the
process).

To enable the Community surface, set the flags **before** starting
(`Settings` reads them once at process boot, ADR 0395 — the `dart-define`
kill-switch parity applies backend-side too):

```bash
export STRUMSIGHT_COMMUNITY_ENABLED=true
export STRUMSIGHT_COMMUNITY_WRITES_ENABLED=true     # optional: content writes
export STRUMSIGHT_COMMUNITY_LEADERBOARD_ENABLED=true # optional: leaderboards
```

Both flags default to `false` (ADR 0395/0497 D1/D2) — with `community_enabled`
left unset, every `/community/**` route stays unregistered (404), exactly as
in production, and the phone's Community screens will look "empty" for the
same reason a disabled deploy does. `community_writes_enabled=false` still
mounts every Community router, but the write-method routes on `posts` and
`social_graph` (create a post, follow, block, …) are absent too (ADR 0497 D2)
— reads work, writes 404 — so flip it on if you want to exercise those flows
from the phone.

## 2. Find the laptop's LAN IP

```bash
# Linux
ip -4 addr show | grep -oP '(?<=inet\s)\d+(\.\d+){3}' | grep -v '^127\.'
# macOS
ipconfig getifaddr en0
```

Pick the address on the same Wi-Fi network the phone is on (not a Docker /
VPN interface). Example: `192.168.1.42`.

## 3. Make sure the phone can actually reach it

- Phone and laptop must be on the **same** Wi-Fi network (not phone-hotspot
  routing the laptop through a different subnet, and not a "guest" SSID that
  isolates clients from each other — many routers block client-to-client
  traffic on guest networks by default).
- The laptop's firewall must allow inbound TCP on the chosen port (`8000`
  above). On Linux with `ufw`: `sudo ufw allow 8000/tcp`.
- Quick reachability check from the phone's browser (not the app):
  `http://192.168.1.42:8000/health` should return
  `{"status":"ok","version":"..."}`.

## 4. Point the Flutter build at it via `STRUMSIGHT_API_URL`

`AppConfig.apiUrlDefine` (`lib/app/config/app_config.dart`) reads this
dart-define; the default (`AppConfig.devApiBaseUrl`, `http://10.0.2.2:8000`)
is emulator-only and must be overridden for a physical device:

```bash
flutter run \
  --dart-define=STRUMSIGHT_API_URL=http://192.168.1.42:8000 \
  --dart-define=STRUMSIGHT_ACCOUNT=true \
  --dart-define=STRUMSIGHT_COMMUNITY=true
```

`STRUMSIGHT_ACCOUNT` gates the login/settings-sync layer client-side
(`FeatureFlags.forEnvironment`, ADR 0395's Flutter-side counterpart); without
it the app never constructs the Dio client the Community repositories share
(`communityApiClientProvider` watches `accountApiClientProvider`, which is
`null` when the account layer is off — every Community repository call then
returns `ConfigurationFailure` locally, without ever reaching the network).
`STRUMSIGHT_COMMUNITY` is the client-side Community kill switch — see
`docs/adr/0395-community-baseline-feature-flags-and-threat-model-scope.md`.
A **production** build additionally requires `https` and rejects a loopback
or `staging`-labelled host (`AppConfig.resolve`, §3.3) — the plain-`http`
LAN address above is a `dev`/`lab` build only.

## 5. Verify end-to-end

1. Register an account from the phone (Login screen → Sign up). A
   successful `201` from `POST /auth/register` confirms the phone can reach
   the backend and the base account layer is wired.
2. Open the Community tab / onboarding gate. With `community_enabled=true`
   server-side and `STRUMSIGHT_COMMUNITY=true` client-side, the gate calls
   `GET /community/profiles/me` — `404 profile_missing` routes to onboarding
   (expected for a fresh account), any other 4xx/5xx or a stuck spinner means
   the wiring is still broken somewhere in steps 1–4.
3. Curl-level cross-check from the laptop (bypasses the UI entirely — useful
   to isolate "backend problem" from "client problem"):
   ```bash
   curl -s http://192.168.1.42:8000/health/ready
   curl -s -X POST http://192.168.1.42:8000/auth/register \
     -H 'Content-Type: application/json' \
     -d '{"email":"device-check@strumsight.app","password":"sixstrings"}'
   ```

## 6. What must be enabled to see the full Community surface

| Server flag (env var) | Client dart-define | Unlocks |
|---|---|---|
| `STRUMSIGHT_COMMUNITY_ENABLED` | `STRUMSIGHT_COMMUNITY` | the module at all — profiles, follow/block/mute, search, feed, posts (read), bookmarks (read), challenges (invite lifecycle), reports, moderation, handles, privacy |
| `STRUMSIGHT_COMMUNITY_WRITES_ENABLED` | *(client-side sub-flag, same ADR 0395 shape)* | creating a post, following/unfollowing, blocking/muting — everything under `posts`/`social_graph` that isn't a `GET` (ADR 0497 D2) |
| `STRUMSIGHT_COMMUNITY_LEADERBOARD_ENABLED` | *(client-side sub-flag)* | the whole `leaderboards` router — off means `404`, not an empty list |
| `STRUMSIGHT_COMMUNITY_MEDIA_ENABLED` | *(client-side sub-flag)* | media upload (self-gated inside `services/media_upload_service.py` — see that module, not the router table) |
| `STRUMSIGHT_COMMUNITY_CLUBS_ENABLED` | *(client-side sub-flag)* | reserved — no clubs router exists in the backend yet, so this flag has no server-side effect today |

Both sides default to `false` everywhere (ADR 0395 D1–D3, ADR 0497 D1/D2) —
this is a deliberate kill switch, not a bug: the module is un-audited and
must be an explicit, per-deployment opt-in.

## 7. Known, pre-existing client↔server gaps (measured, not fixed by this round)

`docs/contracts/client-backend-endpoints.json` (this round's machine-checked
artifact, `backend/tests/test_client_contract_parity.py`) flags client calls
that have **no** backend route yet — a real device test against these will
404 regardless of flags:

- `GET /community/challenges`, `GET /community/challenges/{id}`,
  `GET /community/challenges/{id}/me` — the Flutter challenge-list/detail/
  participation calls were written ahead of a server-side listing surface
  that was never built (`backend/app/community/routers/challenges.py` only
  has invite-lifecycle + result-submission routes). Outside this round's
  `allowed_paths`; tracked for a future round.
