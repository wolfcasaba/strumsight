# E12-R31 — Kör-review (ADR 0055)

- **Kör:** `E12-R31` — Production deployment és internal production cohort
- **Ág:** `sonnet-impl/e12-r31-production-deployment-and-internal-cohort`
- **Review-zott HEAD:** `279d977f`
- **Implementer:** `sonnet-impl` (Claude Sonnet 5, `--effort high`)
- **Reviewer:** Claude (Opus 5, orchestrátor) + `security-reviewer` ügynök
  (a brief `risk = "high"` miatt KÖTELEZŐ)
- **Módszer:** read-only. A `security-reviewer` a munkapéldányon mért,
  reprodukáló szondákkal (lokális stub-szerverek, mutáció-kill próbák); az
  orchestrátor a két MAJOR-t a forráskód SAJÁT olvasásával külön is
  megerősítette (a subagent-lelet adat, nem tekintély).

## Verdikt: **CHANGES REQUESTED** — 3 MAJOR, 4 MINOR, 2 NOTE (BLOCKER: nincs)

A kör terméke érdemben jó: a füst-csomag stdlib-only, fail-closed hálózati
ágakkal, TLS-verify bekapcsolva, a jelszó strukturálisan nem kerülhet argv-be,
a fingerprint-ellenőrzés minden ágon fail-closed, és a hitelesített végpontok
body-ja soha nem kerül a kimenetbe. **Három lelet viszont a kör SAJÁT kötött
szabályát (§5.1, §5.2) teszi vakká vagy megkerülhetővé** — ezek a mércét
érintik, ezért javító kör előzi meg a merge-öt.

## Scope és gépi kapuk

| Kapu | Eredmény |
|---|---|
| `scope_audit` | `ok` — 6 változott fájl, pontosan az engedélyezett lista (5 új + a brief §10) |
| `gate_shape` | `ok` |
| Tilos zóna | tiszta — `lib/**`, `backend/app/**`, `backend/tests/test_hardening.py`, `.github/**`, `docs/adr/**`, `tools/**` érintetlen |
| Munkapéldány | tiszta (a jelzéskori `dirty_files=1` a záró commit előtti pillanatkép volt; a fa a `done` után üres `git status`-t ad) |

---

## MAJOR-1 — A Lab-route ellenőrzés `/download` lába FAIL-OPEN (a §5.2 közvetlen sértése)

**Hely:** `tool/release/production_smoke.py:289–305` (`:297`), a cél oldalán
`backend/app/main.py:246–251`.

A `/download` handler **regisztrálva is** `404`-et ad, ha a
`STRUMSIGHT_APK_PATH` nincs beállítva vagy nem fájlra mutat
(`raise HTTPException(status_code=404, detail="no APK staged")`). A check
kizárólag a státuszkódot méri (`if resp.status_code != 404`), ezért **nem tudja
megkülönböztetni a „nincs regisztrálva" (kívánt) és a „él, csak nincs staged
APK" (SÉRTÉS) állapotot**. Prod-profilú appon `STRUMSIGHT_APK_DOWNLOAD_ENABLED=true`
mellett a füst-csomag ezt írja ki és 0-val lép ki:

```
[PASS] lab_routes_absent: all three Lab routes 404 (POST /diagnostics, GET /diagnostics/health, GET /download)
```

…miközben a `/download` a regisztrált útvonalak közt van, és kiszolgálja a
`strumsight-lab.apk`-t abban a pillanatban, amint a `STRUMSIGHT_APK_PATH`
fájlra mutat.

**Miért nem fogja meg a kör saját mércéje:** a kötelező valódi-sértés próba
(`backend/tests/test_production_smoke_contract.py:218–245`) mindkét env-flaget
bekapcsolja, de **csak a két `/diagnostics` útvonalra állít** (`:242–245`) — az
aggregátum azok miatt pirosodik. Nincs cella, amely CSAK az APK-letöltő
felületet kapcsolná be, így a `/download` láb fail-open volta mérhetetlen.

**Javítás iránya (a security-reviewer kimérte, működik):** két HTTP-szintű
diszkriminátor létezik, route-introspekció nélkül —

```
apk_download_enabled=False: GET /download -> 404 {"detail":"Not Found"}     | POST -> 404
apk_download_enabled=True : GET /download -> 404 {"detail":"no APK staged"} | POST -> 405 (Method Not Allowed)
```

…tehát vagy a 404 body `detail` mezőjét kell megkövetelni, vagy egy
rossz-metódusú próbát kell hozzáadni (`POST /download` → 405 ⇒ a route létezik
⇒ FAIL). **Plusz egy külön contract-cella, ami CSAK a
`STRUMSIGHT_APK_DOWNLOAD_ENABLED=true`-t kapcsolja be** — enélkül a javítás
maga is mérhetetlen marad.

## MAJOR-2 — Az egyetlen titok-szivárgási cella nem tud pirosra váltani (a §5.1 mércéje vak)

**Hely:** `test/tooling/production_readiness_test.dart:24`
(`_unreachableBaseUrl = 'http://127.0.0.1:1'`) + a sentinel-cella `:78–99`.

A cella a `127.0.0.1:1` porton futtat, ahol a kapcsolat azonnal elutasításra
kerül — a `POST /auth/login` **soha nem megy ki**, és a sikeres-válasz ág
(`production_smoke.py:239–256`, az EGYETLEN hely, ahol a jelszó vagy a bearer
token egyáltalán kimenetre kerülhetne) le sem fut.

**Mutáció-kill próba (mérve):** a sikerág elejére beszúrt
`print(f"[DEBUG] logged in as {email} with {password} -> {token}")` mellett a
cella pontos argv-jével a teszt **ZÖLD marad** (exit≠0 az elérhetetlen URL
miatt, a sentinel nem jelenik meg); ugyanez a mutáns egy 200-at válaszoló
lokális socket ellen viszont kiírja a jelszót ÉS a tokent.

A cella tehát pontosan azon az úton inoperábilis, ahol a szivárgás
megtörténhet. A backend contract-teszt sem tartalmaz egyetlen „a titok nem
jelenik meg" állítást sem, és a **bearer tokenre** egyáltalán nincs sentinel.

**Javítás iránya:** a sentinel-cella futtassa a füst-eszközt egy lokálisan
indított, 200-at válaszoló stub-szerver ellen
(`HttpServer.bind(InternetAddress.loopbackIPv4, 0)`), és állítson a jelszó- ÉS
a token-sentinel hiányára a **végigfutott** kimeneten. A jelenlegi elérhetetlen-URL-es
cella maradhat, de „nincs hálózati kísérlet env-var nélkül" próbaként.

## MAJOR-3 — Nincs `https` kikényszerítés: `http://` célon a cohort-jelszó tisztán megy ki

**Hely:** `tool/release/production_smoke.py:408` (`--base-url`, semmilyen
validáció), `:136`; az operátori utasítás
`docs/release/internal-production-checklist.md:36–40` (`--base-url <production-URL>`
— a `https` sehol nincs kikötve).

Az eszköz komoly gondot fordít arra, hogy a jelszó ne kerüljön argv-be és
logba — majd **titkosítatlan csatornán is elküldi**, ha az operátor `http://`-t
ír be. Nyers TCP-elfogással mérve a `POST /auth/login` bodyja tisztán
tartalmazza a jelszót, és ugyanez igaz a rákövetkező `Authorization: Bearer …`
fejlécekre. A védelem jelenleg kizárólag az operátor fegyelmén múlik, miközben
a kör egész §5.1-e a hitelesítő adat higiéniájáról szól.

**Javítás iránya:** `main()`-ben fail-closed séma-ellenőrzés
(`urlsplit(args.base_url).scheme != "https"` → exit 2, opcionális
`--allow-insecure-http` kapcsolóval a lokális próbákhoz), a checklist §2-es
sora írja elő a `https://` prefixet, és egy cella mérje a nem-https cél exit-2-jét.

---

## MINOR-ok (követő körbe utalhatók, de MINOR-3 egy soros)

| # | Hely | Lényeg |
|---|---|---|
| MINOR-1 | `production_smoke.py:142–151` | `urllib` **nem** csupaszítja le az `Authorization` fejlécet host-váltó redirecten (a `requests`/`httpx` igen) — mérve: a token idegen hostra kerül, a check mégis `[PASS] settings: ok`. Enyhítő: `302` POST-on eldobja a bodyt (jelszó nem megy át), `307` fail-closed 307-ként. Javítás: redirectet tiltó `HTTPRedirectHandler`. |
| MINOR-2 | `production_smoke.py:272–286` | `[PASS] community_feed: reachable and correctly gated (status 404)` egy **be sem kötött** routerről (a mai fán a Community router nincs `include_router`-elve) — a 404 pozitív elérhetőségi állításként fogalmazódik meg. A handoff §10.1 becsületesen kimondja; a probléma az operátornak megjelenő string. |
| MINOR-3 | `production_smoke.py:5` | A modul-docstring „prints one **masked** PASS/FAIL line"-t állít, holott **semmilyen maszkolási réteg nincs** (a valós — és helyes — tulajdonság: a body-t sosem írja ki). Ez az implementer-prompt §8 („doc-commentben csak tesztelt állítás") sértése, és félrevezetheti a jövőbeli szerkesztőt. |
| MINOR-4 | `test_production_smoke_contract.py:1` | Elkerülhető fájl-szintű `strumsight:allow-secret-file` marker (ADR 0448 D7): a 3 érintett literál bizonyítottan szintetikus, de a marker a TELJES fájlt kiveszi a titok-scan alól minden jövőbeli szerkesztésre is. Egy `fake-` prefixű literál nulla markerrel átment volna. |

## NOTE-ok

- **NOTE-1** `production_smoke.py:142` — séma nélküli `--base-url` esetén a
  `Request(...)` `ValueError: unknown url type`-ot dob, amit a `_request`
  `except` ága nem fog el → nyers traceback. Mérve rendben: a kilépési kód
  nem-nulla (fail-closed irány), és a sentinel-jelszó **nem** jelenik meg a
  tracebackben. A MAJOR-3 séma-validációja ezt amúgy is lefedné.
- **NOTE-2 — KIMÉRVE ÉS RENDBEN** (nem „nem találtam"): TLS-tanúsítvány
  ellenőrzés bekapcsolva és fail-closed (önaláírt cert ellen mérve:
  `CERTIFICATE_VERIFY_FAILED`); a fingerprint-ellenőrzés teljes egyenlőséget
  mér (prefix-egyezés FAIL, üres/hiányzó/nem-string/rossz JSON mind FAIL);
  jelszó a parancssorban strukturálisan lehetetlen (nincs `--password`
  kapcsoló, hiányzó env → exit 2 hálózati kísérlet nélkül); felhasználói adat
  nem kerül a kimenetbe (a `/settings`, `/auth/me`, `/community/feed` bodyja
  soha; a `/health/ready` 503 `reason`-je három fix kódra korlátozott);
  minden check fail-closed hálózati hibán; stdlib-only, nincs új dependency,
  nincs fájlírás/`subprocess`/`eval`; a két új dokumentum titok-mentes (csak
  env-változó NEVEK és `<…>` helykitöltők), és a checklist 16 pontja
  6 GÉPI / 10 EMBERI bontású (§5.3 teljesül).

---

## Acceptance criteria — állapot a javító kör ELŐTT

| # | Állapot | Indoklás |
|---|---|---|
| A1 | ⚠ részben | A füst-csomag titok nélkül, paraméteres célon fut (mérve rendben), de az egyetlen szivárgás-cella vak (MAJOR-2), és `http://` célon a titok tisztán megy ki (MAJOR-3). |
| A2 | ⚠ részben | A `/diagnostics` két lába mérve és fail-closed; a `/download` láb **fail-open és mérhetetlen** (MAJOR-1). |
| A3 | ✅ | A kliens production profil dev-host/dev-token cellái zöldek, a meglévő `app_config_test` mellett. |
| A4 | ✅ | Minden ág fail-closed, a normalizálás nem tesz egyenlővé két különböző lenyomatot (kimérve). |
| A5 | ✅ | 16 pont, 6 GÉPI / 10 EMBERI, cellával mérve. |
| A6 | ✅ | A sablon az SDD §26.1 mind a kilenc elemét tartalmazza. |

## Javító kör — a leletlista

**Kötelező (merge előtt):** MAJOR-1, MAJOR-2, MAJOR-3, MINOR-3.
**Nem kötelező, de olcsó:** MINOR-1, MINOR-2, MINOR-4.

A javító kört UGYANAZ a motor (`sonnet-impl`) viszi, ugyanazon az ágon, az
engedélyezett-fájllista változatlanul. A javítás után a review frissül, és a
teljes CI-kapu ÚJRA fut a friss HEAD-en (exact-SHA, ADR 0086 §2).
