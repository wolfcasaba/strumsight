# E01-R13 — Review

Brief: `docs/rounds/e01-r13-backend-security-and-diagnostics.md`
Diff: `git diff 4012f2d..9da5bde` (branch `codex/epic-01-round-13-backend-security`)
Reviewer: Claude · Dátum: 2026-07-29
Verdikt: **APPROVED**

## Összegzés

BLOCKER: 0 · MAJOR: 0 · MINOR: 0 · NOTE: 3

A kör mindent szállított, amit a brief kért, és a kritikus állítások itt is
**viselkedési tesztekkel** vannak bizonyítva: a streaming limit korai
megszakítását egy szkriptelt `receive`-számláló méri (reads == 2, a stream
SOHA nem fogy el), a félbeszakadt feltöltés takarítását valódi
`http.disconnect` üzenet, a prod Lab-route-hiányt tényleges 404, a token-guard
hibaüzenetének szivárgásmentességét explicit assert. A TDD-fegyelem
dokumentált (RED-kimenetek a §10-ben), a kötelező valódi guard-sértés próba
megtörtént (feltétel rontása → 401≠404 piros → visszaállítás → zöld). Mindhárom
R12 MINOR follow-up rendezve.

## Acceptance criteria — tételesen

| # | Kritérium | Bizonyíték | Áll |
|---|---|---|---|
| 1 | Prod default: `/diagnostics`, `/diagnostics/health`, `/download` 404; dev-ben él | `test_prod_defaults_do_not_register_lab_routes` (3×404), `test_lab_routes_default_on_in_dev_and_off_in_prod`, `test_diagnostics_dev_default_token_remains_usable` (dev zero-setup változatlan) | ✅ |
| 2 | Prod + enabled + dev-default/üres token → boot-hiba | `test_prod_enabled_diagnostics_refuses_insecure_token` (parametrizált: dev-default + üres; a hibaüzenet a tokent NEM tartalmazza — assertálva) | ✅ |
| 3 | `hmac.compare_digest`; token se logban, se válaszban | kód: `diagnostics.py` compare_digest bytes-okon; `test_diagnostics_rejects_bad_token` a 401 body-ra mindkét tokent (szerver+kliens) asszertálja; a diffben nincs token-logolás | ✅ |
| 4 | 413 a body végigolvasása NÉLKÜL | `test_diagnostics_stops_reading_when_stream_exceeds_limit`: szkriptelt receive, `reads == 2`, StopIteration-őr bizonyítja hogy a stream nem fogyott el; endpoint-szintű 413 külön tesztben | ✅ |
| 5 | Félbeszakadt upload → nincs árva temp | `test_diagnostics_disconnect_removes_partial_temp_file`: menet közben létező `.tmp` assertálva, `ClientDisconnect` után `tmp_path` ÜRES | ✅ |
| 6 | Traversal soha nem ír a data-dir-en kívül; ütközésnél mindkét feltöltés megmarad | parametrizált traversal (`../`, abszolút, URL-encoded) + `rglob` a szülő-könyvtáron; `test_diagnostics_collision_keeps_both_uploads` (fagyasztott `strftime`, két külön session-név, mindkét payload megvan) | ✅ |
| 7 | 72 bájt Unicode jelszó regisztrál+belép; 73 bájt (≤72 char) → 422 | `test_register_and_login_accept_72_utf8_byte_password` (36×"é"), `test_register_rejects_73_utf8_byte_password`; plusz `hash_password` ValueError-őr és legacy `verify_password` kompat-teszt valódi csonkolt hash-sel | ✅ |
| 8 | Ismeretlen e-mail / rossz jelszó válasza bájtra azonos | `test_unknown_email_and_wrong_password_responses_are_byte_identical` (`.content ==`) | ✅ |
| 9 | MINOR-1: néma flag → log; readiness változatlan | `main.py`: `_logger.exception(...)`, a flag törölve (`not hasattr` assert); `test_dev_schema_initialization_failure_is_logged` caplog-gal; readiness ok-kódok érintetlenek | ✅ |
| 10 | MINOR-2: README kimondja az unstamped-dev 503-at | README: „Until an existing dev database is explicitly stamped, `/health/ready` remains `503 migration_mismatch`" + `stamp head` teendő | ✅ |
| 11 | MINOR-3: prod-SQLite teszt env-független | `monkeypatch.delenv("STRUMSIGHT_ALLOW_SQLITE", raising=False)` bekerült; teljes suite `STRUMSIGHT_ALLOW_SQLITE=true` env-vel zöld | ✅ |
| 12 | Meglévő tesztek zöldek; diff csak a §4 tábla | függetlenül újrafuttatva: **64 passed** (44 régi + 20 új) sima ÉS `STRUMSIGHT_ALLOW_SQLITE=true` futásban is; `diff --stat`: 11 fájl, mind a §4 listán, a brief-fájl diffje tisztán additív a §10-ben (0 törölt sor) | ✅ |

## Gate-bizonyíték (függetlenül újrafuttatva ezen a boxon)

| Gate | Eredmény |
|---|---|
| `.venv/bin/python -m pytest -q` (friss clone, friss venv) | **64 passed**, exit 0 |
| `STRUMSIGHT_ALLOW_SQLITE=true .venv/bin/python -m pytest -q` | **64 passed**, exit 0 |
| Baseline a kör előtt ugyanitt | 44 passed (a pre-flight mérte) |
| Valódi guard-sértés (Codex, §10) | diagnostics-regisztráció feltétele rontva → 404-teszt PIROS (401), visszaállítva zöld |

## Megállapítások

### NOTE-1 — a `STRUMSIGHT_DIAG_MAX_BYTES` maradt per-request env-olvasás

A token és a data-dir a `Settings`-be került (a brief ezt kérte), a méretlimit
nem. Dokumentált eltérés (§10), wire/dev viselkedése változatlan, és a
Settings-seam tesztje épp azt bizonyítja, hogy a token/dir env-je már NEM hat
(`test_diagnostics_rejects_bad_token` env-set mellett is a Settings-értéket
használja). Ha egyszer minden diag-konfig egy helyre kerül, a limit is
átemelhető — nem e kör dolga.

### NOTE-2 — a session-név-ütközés feloldása process-lokálisan atomikus

A `_unique_session_path` exists-ellenőrzése és az `os.replace` között nincs
`await`, így egyetlen event-loopon nem interleave-elhet (a docstring ki is
mondja); több workernél elvi TOCTOU maradna. A backend deklaráltan
single-process (README, rate-limiter ugyanígy) — konzisztens a kör 5.6
döntésével.

### NOTE-3 — a prodban engedélyezett `/download` továbbra is token nélküli

Az `apk_download_enabled=true` + prod kombináció tokent nem követel (a
boot-guard csak a diagnosztikára terjed ki) — a route eredeti designja szerint
a „already-authorized tunnel" mögé való. A brief ezt nem kérte másképp; ha a
Lab-APK valaha publikus prod-URL-re kerülne, érdemes lesz tokenesíteni vagy
signed-URL-t adni. Follow-up-jelölt, nem hiba.

## Scope és architektúra

- 11 fájl, +782/−92 — minden útvonal a §4 tábláján; tilos zóna (alembic,
  database.py, models.py, Flutter-fa, CI, ADR-ek) érintetlen; a
  `CODEX_ROUND_PROMPT.md` untracked maradt, a commitban nincs.
- A wire contract változatlan (ADR 0061 §1): dev-token default él, a sikeres
  válasz mezői azonosak; az `index_status: "failed"` kizárólag hibaágon,
  additívan jelenik meg — a Flutter-kliens érintetlen.
- A `hash_password` ValueError-ja az API felől elérhetetlen (a `UserCreate`
  422-je előbb fut) — helyes defense-in-depth, nem duplikált hibaút.
- A caplog-teszt Alembic-`fileConfig` logger-semlegesítése jól dokumentált
  tesztizolációs lépés, production-kódot nem érintett.

## Verdikt

**APPROVED.** BLOCKER, MAJOR és MINOR nincs; a három NOTE közül a NOTE-3
(prod `/download` tokenesítése) jelölt későbbi körre, ha a Lab-deploy publikussá
válik. Merge az ADR 0052 zöld-kapus szabálya szerint, a CI-run megvárásával.
