# E09-R03 — Review

Brief: `docs/rounds/e09-r03-public-identity-and-handle-policy.md`
Diff: `git diff c1324292..9ad6cb3a -- backend/` (round branch `minimax/e09-r03-public-identity-and-handle-policy`, worktree `/home/ubuntu/ss-mm-e09-r03`)
Reviewer: Claude (Sonnet 5, orchestrátor) + `security-reviewer` subagent (risk=high) · Dátum: 2026-08-22
Verdikt: **APPROVED** (javító kör után, `6d354812`)

## Előzmény

A kör két implementer-fordulóban készült:

1. `d03268db` pre-flight (ADR 0397) → `08ffcd3b`…`3cca3ddd` implementáció. Az
   implementer helyesen `stopped`-ot jelzett: saját migrációja
   (`e09_r03_0003.down_revision = e09_r02_0002`) 3, `allowed_paths`-on kívüli
   cross-round tesztet tört el (`docs/LESSONS.md` L413 — az L411 minta egy
   láncszemmel mélyebben).
2. Self-heal `HEAL E09-R03/H3` (PR #411, `2359b808`) bővítette az
   `allowed_paths`-t a két érintett teszt-fájlra, és lánc-toleráns javítási
   utasítást hagyott a brief §0.1-ben.
3. Ez az orchestrátor-session szinkronizálta a kör-ágat a friss `main`-nel
   (`0a47dcff`), majd resume-olta a felfüggesztett minimax implementert, ami
   `9ad6cb3a`-ban lánc-toleránsan javította mindhárom tesztet + ruff cleanup.

## Összegzés

Első kör: BLOCKER: 0 · MAJOR: 1 (F1) · MINOR: 3 (F2, F3, F4) · NOTE: 2.
Javító kör (`6d354812`) után: **F1 és F2 zárva**, F3/F4 follow-up-ként nyitva
maradnak (nem blokkolók — lásd az egyes leletek Státusz sorát).

A MAJOR és az egyik MINOR a security-reviewer subagent önálló, kód-szintű
próbájából jön (lásd `docs/reviews/e09-r03-security-review.md`); a másik két
MINOR ennek a review-nak a saját mutation-probe-jaiból.

## Acceptance criteria

| # | Kritérium | Teljesült | Bizonyíték |
|---|---|---|---|
| A1 | Két vizuálisan/normalizáltan azonos handle nem foglalható le | ✅ (DB-szinten mérve) | `test_unicode_collision_rejected_by_unique_index`, `test_collision_rejected_even_when_display_looks_different` — DB unique index a normalizált oszlopon; lásd F1 (MINOR) a végpont-szintű lefedettségről |
| A2 | A public ID stabil és nem kitalálható szekvenciális integer | ✅ | `community_profiles.public_id` default `uuid.uuid4()` (Kör 2, `os.urandom`-alapú), `test_public_id_not_derived_from_internal_id`. Az új `PublicIdGenerator`/`_secrets_uuid4` jelenleg nincs bekötve egy write-útvonalba sem (lásd security review N3) — a §5.2-t a MEGLÉVŐ oszlop-default elégíti ki, nem az új gépezet |
| A3 | Az availability API nem ad érzékeny account információt és rate-limitált | ⚠️ RÉSZBEN | Válasz-alak: ✅ (`test_availability_response_does_not_leak_account_info`). Rate-limit: ❌ — lásd F2/MAJOR (spoofolható kulcs) |
| A4 | Reserved/blocked handle nem regisztrálható | ✅ | `test_reserved_handle_rejected_by_validate` (parametrizált), `test_blocked_handle_rejected_by_validate`, `test_claim_endpoint_rejects_reserved` |
| A5 | Concurrent handle-claim csak az egyik felet engedi át | ✅ (DB-constraint, dokumentáltan szekvenciális-tranzakciós szimuláció, nem valódi szál-race) | `test_concurrent_claim_db_constraint_blocks_second_writer`, `test_concurrent_change_does_not_lose_a_writer`; a `HandleAlreadyClaimed` valóban a DB `IntegrityError`-ból jön, nem app-szintű előzetes SELECT-ből |
| A6 | Handle-change cooldown érvényesül; a régi handle rövid ideig redirectel | ✅ funkcionálisan, ⚠️ TOCTOU a cooldown-ellenőrzésben | `test_cooldown_blocks_immediate_change`, `test_old_handle_redirects_inside_window`; lásd F4 (MINOR, security review m2) a race-ablakról |
| A7 | E-mailből nem keletkezik automatikus nyilvános handle | ✅ | `test_email_is_not_a_default_handle_source`, `test_assign_handle_is_explicit_only` |

### §6.1 mérce-mátrix

A hat hibás-implementáció cella mindegyikéhez van dedikált teszt (ellenőrizve
kódolvasással: `test_unique_index_is_on_normalized_not_display`,
`test_public_id_factory_default_uses_secrets_entropy`,
`test_availability_accepts_only_a_single_handle`,
`test_is_reserved_and_is_blocked_are_stable`,
`test_concurrent_claim_db_constraint_blocks_second_writer`,
`test_cooldown_blocks_immediate_change`). A küszöb-hármas (alatt/rajta/fölött)
jelen van, de lásd F3 (MINOR) — a teszt a `MIN_LEN`/`MAX_LEN` KONSTANSOKBÓL
származtatja a bemenetet, nem a brief literál 2/3/24/25 értékeiből.

## Scope-audit

```
Legacy scope audit OK (0a47dcff5390..9ad6cb3a0dd, 8 changed path(s), 0 generated/ignored)
```

Engedélyezett fájlokon kívüli változás: **nincs**. A `docs/rounds/e09-r03-*.md`
saját brief-fájl (engedélyezett), a hét backend fájl mind az eredeti vagy a
self-heal által bővített `allowed_paths`-on belül van. `backend/app/community/
models/profile.py` **nincs** a diffben — a tilos zóna (handle-oszlop kivételes
bevezetése rajta) betartva, a §10.6/4 megoldás (`Table.append_column` a
`handle_history.py`-ban) ezt kerüli meg tisztán.

## Megállapítások

### F1 — MAJOR — Az availability rate-limit kulcsa spoofolható (`X-Forwarded-For`)

- **Fájl:** `backend/app/community/routers/handles.py:92-107` (`_client_key`), felhasználva `:131`, `:256`, `:304`
- **Probléma:** a rate-limit kulcs az ügyfél által szabadon küldött
  `X-Forwarded-For` fejlécből jön, trusted-proxy-konfiguráció nélkül. A
  security-reviewer reprodukálta: 60 egymást követő `GET .../availability`
  hívás, mindegyik más `X-Forwarded-For` értékkel → **0/60** `rate_limited`
  válasz.
- **Hatás:** a §5.3 "rate-limitált" kontrollja jelen formájában
  megkerülhető — bármely hívó tetszőleges kulcsot választhat magának. Az
  éles kockázatot csökkenti, hogy a router **ebben a körben nincs bekötve**
  `app/main.py`-ba (`build_community_router()` csak a `profile.router`-t adja
  vissza) — de a kör §10 handoffja és a docstringek úgy állítják be a
  végpontot, mintha a kontroll már élesen működne, és egy jövőbeli bekötő kör
  ezt változtatás nélkül örökölné.
- **Kötelező javítás:** `_client_key` NE bízzon a kliens által küldött
  `X-Forwarded-For`-ban trusted-proxy-konfiguráció nélkül — a jelen körben
  (nincs auth, nincs ismert proxy-lánc) essen vissza kizárólag
  `request.client.host`-ra.
- **Ellenőrzés:** egy teszt, amely a fenti reprodukciót (N különböző
  `X-Forwarded-For` ugyanarról a TestClient-ről) PIROSRA váltja a javítás
  előtt és ZÖLDRE utána (a limiter tényleg 30/perc után `rate_limited`-et ad).
- **Státusz:** **FIXED** (`6d354812`) — `_client_key` kizárólag
  `request.client.host`-ot ad vissza, az `X-Forwarded-For` olvasás törölve.
  Regressziós teszt: `test_rate_limit_key_is_socket_peer_not_xff` (35 hívás
  rotáló hamis `X-Forwarded-For`-fal, elvárt `rate_limited` 30 után). A
  reviewer a javítás ELŐTTI kódra visszaállítva függetlenül reprodukálta a
  piros állapotot (`AssertionError: ... did not rate-limit after 35 calls`),
  majd a javítással zöldre igazolta.

### F2 — MINOR — `POST /claim` és `/change` 500-at ad 409 helyett duplikált handle-re

- **Fájl:** `backend/app/community/routers/handles.py:262-266`, `:311-317`;
  gyökérok `backend/app/community/services/identity_service.py:184-210`,
  `:262-291`
- **Probléma:** SQLite-on az UNIQUE-index-sértés az `UPDATE` `execute()`
  hívásakor dobódik, nem a `commit()`-nál. Az `assign_handle`/`change_handle`
  ezt elkapja és `HandleAlreadyClaimed`-re fordítja — de a router csak a
  `commit_with_uniqueness_check` hívást csomagolja `try/except
  HandleAlreadyClaimed`-be, magát az `assign_handle`/`change_handle` hívást
  nem. A kivétel emiatt a router szintjén kezeletlen marad → 500, nem a
  dokumentált 409.
- **Hatás:** funkcionális hiba, nem adatszivárgás (a FastAPI generikus
  `Internal Server Error` testet ad, `str(exc)` nem jut vissza a hívóhoz). A
  DB-szintű egyediség maga TARTJA az invariánst — csak a hibaválasz rossz.
- **Kötelező javítás:** egyetlen elkapási pont — vagy az `assign_handle`/
  `change_handle` hívást is vond be a router `try/except
  HandleAlreadyClaimed → 409` blokkjába, vagy a service-oldali `except
  IntegrityError` ágakat távolítsd el és hagyd a kivételt a
  `commit_with_uniqueness_check`-ig futni.
- **Ellenőrzés:** kliens-szintű teszt, amely megismétli a `POST /claim`
  duplikációt és `409`-et vár `500` helyett.
- **Státusz:** **FIXED** (`6d354812`) — mindkét végpontban (`claim_handle`,
  `change_profile_handle`) egyetlen közös `try/except HandleAlreadyClaimed`
  fedi az `assign_handle`/`change_handle` HÍVÁST is, nem csak a
  `commit_with_uniqueness_check`-et. Regressziós teszt:
  `test_duplicate_claim_returns_409_not_500`. A reviewer a javítás előtti
  kódra visszaállítva függetlenül reprodukálta az 500-at (kezeletlen
  `HandleAlreadyClaimed`), majd a javítással 409-re igazolta.

### F3 — MINOR — A küszöb-hármas teszt a saját konstansból, nem a brief literál értékeiből származtat

- **Fájl:** `backend/tests/community/test_handle_policy.py:722-745`
  (`test_threshold_below_min_length_rejected` stb.)
- **Probléma:** a brief §6.1 kifejezetten literál példákat ad
  (`"ab"` = 2 karakter, `"abc"` = pontosan 3, egy pontosan 24 karakteres
  handle, `"a"*25` = 25 karakter), pontosan azért, hogy egy véletlen
  `MIN_LEN`/`MAX_LEN`-módosítás PIROSRA váltsa a tesztet. A tényleges teszt
  `"a" * (MIN_LEN - 1)` / `"a" * MIN_LEN` alakot használ — önreferens a
  konstanshoz képest.
- **Mérve (saját próba):** `MIN_LEN`-t 3→5, `MAX_LEN`-t 24→20-ra állítva a
  négy threshold-teszt változatlanul ZÖLD maradt; a hibát csak a
  reserved/blocked-szótár néhány rövid szava (`help`, `mod`, …) fogta meg
  MELLÉKESEN. `MIN_LEN`-t 3→2-re állítva a
  `test_threshold_on_min_length_accepted` PIROSRA váltott, de a
  `_HANDLE_RE` regex implicit 3-as alsó korlátja miatt, nem azért, mert a
  teszt a 3-as értéket direktben pinnelte.
- **Hatás:** alacsony — a gyakorlatban a legtöbb reális mutáció valamilyen
  járulékos úton elbukik, de a brief saját, explicit regresszió-védelmi
  szándéka (a 3/24 literál pinnelése) nem valósul meg közvetlenül.
- **Javasolt irány (nem kötelező ebben a körben):** cseréld a threshold
  teszteket a brief szó szerinti bemeneteire (`"ab"`, `"abc"`, 24 és 25
  karakteres literálok), és adj egy külön `assert MIN_LEN == 3` /
  `assert MAX_LEN == 24` sort a konstansok saját pinneléséhez.
- **Státusz:** OPEN — follow-up, nem blokkolja ezt a kört.

### F4 — MINOR — Nincs végpont-szintű (HTTP) teszt az A1 Unicode-ütközésre; a cooldown-ellenőrzés TOCTOU

- **F4a (saját próba):** a `test_unicode_collision_rejected_by_unique_index`
  és `test_collision_rejected_even_when_display_looks_different` az
  `assign_handle`-t KÖZVETLENÜL, már normalizált stringgel hívja — nem a
  `/claim` végponton, RAW Unicode bemenettel. Mérve: a `normalize()`
  függvény identity-függvényre cserélése (NFKC/casefold eltávolítva) a teljes
  `test_handle_policy.py` suite-ot ZÖLDEN hagyta — egyetlen teszt sem méri,
  hogy a valós HTTP-belépési pont ténylegesen normalizál. A `validate()`
  hívás megléte más úton (reserved-lista) igazolt (a `validate()` eltávolítása
  a routerből 1 tesztet buktat), de a specifikusan Unicode-normalizációs
  viselkedés a HTTP-úton nincs pinnelve.
- **F4b (security review m2):** `identity_service.py:237-251` — a cooldown
  ellenőrzés app-szintű SELECT-majd-WRITE, DB-szintű zár/constraint nélkül.
  Két konkurens `change_handle` a cooldown lejártának pillanatában mindkettő
  átmehet (egyszeri, korlátozott túllövés — utána megint 14 napra zár), a
  hatás korlátozott, de nem nulla.
- **Javasolt irány (nem kötelező ebben a körben):** F4a — egy
  `test_claim_endpoint_rejects_unicode_collision(client, ...)` a `/claim`
  végponton két különböző Unicode-formával; F4b — feltételes UPDATE
  (`WHERE last_change_at <= threshold`) vagy dokumentált ismert korlátozás.
- **Státusz:** OPEN — follow-up, nem blokkolja ezt a kört.

## Gate-bizonyíték ellenőrzése

Minden gate a reviewer SAJÁT, izolált klónjaiban futott (friss
`python3.12 -m venv` + `pip install -r requirements.txt
-r requirements-dev.txt` mindkét fordulóban), a közös munkapéldánytól
függetlenül. Első forduló: `/tmp/gate-e09-r03` (head `9ad6cb3a`). Javító kör
utáni forduló: `/tmp/gate-e09-r03-fix1` (head `6d354812`).

| Gate | Állított eredmény | Ellenőrizve |
|---|---|---|
| `tools/round-gate.sh test/core/architecture_dependency_test.dart` (mindkét forduló) | MINDEN GATE ZÖLD (format/analyze/test/architecture/secrets/l10n) | ✅ — reviewer saját futása, csonkítatlan kimenet |
| `backend: ruff check app tests` (mindkét forduló) | 0 hiba | ✅ — reviewer saját futása |
| `backend: ruff format --check app tests` (mindkét forduló) | 52 fájl már formázott | ✅ — reviewer saját futása |
| `backend: pytest -q` (teljes suite, javító kör utáni head) | **282 passed**, 0 failed (280 + 2 új F1/F2 regressziós teszt) | ✅ — reviewer saját futása |
| Scope-audit (`tools/scope-audit.py`, javító kör diffje) | OK, 2 changed path (`handles.py` + teszt), 0 violation | ✅ — reviewer saját futása |
| F1/F2 regresszió — visszaállított (buggy) kódon | mindkét új teszt PIROS a javítás nélküli kódra visszaállítva | ✅ — reviewer saját mutation-próbája |
| CI: Router CI (branch, head `6d354812`) | success | ✅ run 32582836086 (manuális `workflow_dispatch`, mivel a fix diffje nem érintett router-ci path-et) |
| CI: Backend CI (branch, head `6d354812`) | success | ✅ run 32582680577 (push-triggerelt) |
| CI: Full Gate (no APK) (branch, head `6d354812`) | success | ✅ run 32582804396 |

## Merge-döntés

**MEHET a squash-merge** (ADR 0052): F1 (MAJOR) és F2 (MINOR) zárva egy
javító körben (`6d354812`, a minimax ELSŐ javító köre — nem kellett Codex-
eszkaláció), mindkettő saját, a reviewer által függetlenül visszaállítva-és-
igazolva regressziós teszttel védve. Minden gate zöld a javító kör utáni
pontos fejen (`6d354812`): format, analyze, architecture, secrets, l10n,
backend ruff, backend pytest (282/282), Router CI, Backend CI, Full Gate —
mind a reviewer saját, izolált futásában VAGY a merge SHA-n zöld CI-runban.
Nincs nyitott BLOCKER/MAJOR. F3/F4 dokumentált, nem-blokkoló follow-up a
LESSONS/backlog számára.
