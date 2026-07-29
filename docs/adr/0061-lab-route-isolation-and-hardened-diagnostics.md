# ADR 0061 — Lab-route-ok regisztráció-szintű elkülönítése és hardened diagnosztika

- **Státusz:** elfogadva (2026-07-29, E01-R13)
- **Kontextus:** SDD Chapter 2, Kör 13; kör-brief
  `docs/rounds/e01-r13-backend-security-and-diagnostics.md`
- **Kapcsolódó:** [ADR 0060](0060-alembic-schema-source-and-injected-engine-lifecycle.md)
  (create_app(settings) minta, readiness-kontraktus),
  [ADR 0052](0052-ci-apk-automerge-session-per-round.md) (zöld gate),
  [ADR 0055](0055-agent-role-protocol.md) (ágensszerepek)

## Kontextus

A production account API és a fejlesztői Lab-infrastruktúra egyetlen appban,
feltétel nélkül él együtt: a diagnostics router és a `GET /download`
(APK-kiszolgálás) minden környezetben regisztrálódik; a diag-token dev-defaulttal
(`strumsight-lab-dev`) fut és `!=`-vel hasonlítódik; az upload a teljes payloadot
memóriába olvassa (`await request.body()`), a méret-ellenőrzés a beolvasás UTÁN
fut; a session-írás nem atomikus és azonos másodpercen belüli azonos kliens-id
némán felülír; a bcrypt-hash előtt a jelszó `encode("utf-8")[:72]` bájt-csonkolást
kap, amit a karakter-alapú pydantic `max_length=72` nem véd ki (többbájtos
karakterek). A round-120-as prod-guard (dev-secret, wildcard-CORS, R12 óta
prod-SQLite) a diag-felületre nem terjed ki.

## Döntés

1. **A wire contract nem változik.** A Flutter-uploader (X-Diag-Token header,
   gzip body, 201 + `{status, session, bytes}`) módosítás nélkül működik tovább
   a Lab-env backenddel; minden hardening szerveroldali.
2. **Regisztráció-szintű elkülönítés, nem 403.** `Settings`-flagek
   (`diagnostics_enabled`, `apk_download_enabled`) vezérlik, hogy a `create_app`
   egyáltalán felépíti-e a Lab-felületet; prod env-ben a default **False** —
   a route prodban nem „tiltott", hanem **nem létezik** (404). Egy nem létező
   felület nem támadható és nem szivárogtat létezés-információt sem.
3. **Fail-closed token.** `diagnostics_enabled=true` + `env=prod` mellett a
   dev-default vagy üres diag-token **boot-hiba** (a `_guard_prod` mintájára);
   az összehasonlítás `hmac.compare_digest`; a token se logba, se válaszba nem
   kerül. Dev-ben a zero-setup default marad — a boxon futó Lab-pipeline nem
   törhet.
4. **Streaming limit a beolvasás KÖZBEN.** Az upload `request.stream()`-mel,
   chunkolt olvasással megy; a limit átlépésekor az olvasás megszakad és 413
   megy vissza — a döntéshez tilos a teljes body felolvasása. Az írás temp-fájlba
   történik és sikerkor `os.replace`-szel (atomikusan) kerül a végleges névre;
   hibaágon (`ClientDisconnect` is) a temp `finally`-ban törlődik. Session-id
   ütközésnél egyedi suffix — néma felülírás nincs; a fájlok 0o600 joggal
   jönnek létre; az `index.jsonl` írási hibája kezelt (a session-fájl megmarad).
5. **Jelszó-csonkolás: regisztrációnál tilos, verifikációnál kompat.** A
   `UserCreate` UTF-8 **bájthosszra** is validál: >72 bájt → 422 (a 8 karakteres
   minimum és a 72-es karakter-cap megmarad mellette). A `verify_password`
   bájt-levágása megmarad, hogy a korábban csonkolt jelszóval regisztrált userek
   beléphessenek — ez a security.py-ban dokumentált kompatibilitási döntés.
6. **Rate limiter marad process-lokális.** A célkörnyezet egyetlen
   uvicorn-process; a korlát (multi-workernél nem megosztott) README-ben
   dokumentált tény, nem új infrastruktúra.
7. **R12-adósságok rendezése minimál-diffel.** A dev-`create_all` néma
   hiba-flagje helyett `logging` (stderr) — a readiness ok-kódjai NEM változnak
   (R12 tesztelt kontraktus); a README kimondja a nem stampelt dev DB tartós
   `503 migration_mismatch`-át és a teendőt; a prod-SQLite tiltó teszt
   `delenv`-vel env-független.

## Következmények

- Prod deploy alapból **account-API-only**; a Lab-felület publikus kitételéhez
  explicit flag + valódi token kell (fail-closed).
- A diag-upload memóriahasználata a chunk-mérethez kötött, nem a payloadhoz;
  túlméretes vagy félbeszakadt feltöltés nem hagy szemetet.
- Új regisztrációnál a 72 bájtot meghaladó jelszó explicit 422 — a néma
  csonkolás megszűnik; a régi userek belépése változatlan.
- A boxon futó dev Lab-pipeline (uvicorn + cloudflared) viselkedése változatlan:
  dev-ben a route-ok élnek, a dev-token default marad.

## Alternatívák

- **403/feature-gate a meglévő route-okon** — elutasítva: a felület létezése
  önmagában felderíthető és támadható; a regisztráció-szintű hiány erősebb és
  tesztben is egyértelműbb (404).
- **User-auth a diagnosztikára** — elutasítva: a Lab-upload opt-in telemetria,
  a token spam-gate elég; a user-auth a wire contractot törné.
- **A `verify_password` csonkolásának eltávolítása** — elutasítva: a meglévő,
  csonkolt jelszóval regisztrált fiókok kizáródnának; a rés az új
  regisztrációk 422-jével záródik.
- **Megosztott rate-limit store (Redis)** — elutasítva ebben a körben: nincs
  multi-worker célkörnyezet; dokumentált korlát, nem infrastruktúra.
