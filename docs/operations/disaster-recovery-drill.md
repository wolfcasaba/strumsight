# Disaster recovery drill — E12-R26 (a LEFUTTATOTT gyakorlat jegyzőkönyve)

> Ez a gyakorlat TÉNYLEGESEN LEFUTOTT ezen a boxon 2026-09-02-én. Minden
> parancs és minden időtartam ebben a dokumentumban egy valós, mért futás
> eredménye, nem egy előzetesen felírt szám (brief §5.1). A gépi mérce:
> [`test/tooling/rollback_policy_test.dart`](../../test/tooling/rollback_policy_test.dart)
> (A5/A6) beolvassa EZT a fájlt és pirosra vált, ha egy lépéshez nem tartozik
> szigorú numerikus időtartam, vagy ha bizonytalanságot jelző szó kerül bele.

## 1. Keret és forrás

A forgatókönyv az [SDD §26.3](../sdd/12-release-roadmap-final-integration.md)
rollback-sorrendjéből az itt, felhő-infrastruktúra NÉLKÜL elvégezhető részre
szűkítve (round brief §0.0): kill-switch hatás, modellcsomag-ellenőrzés,
adat-helyreállítás. A runbookok, amiket ez a gyakorlat végigfuttat:
[`backend-deploy.md`](backend-deploy.md) §3 (rollback),
[`database-recovery.md`](database-recovery.md) (backup/restore),
[`../release/kill-switches.md`](../release/kill-switches.md) (kill-switch
utak). Az ellenőrző eszköz: [`tool/release/verify_rollback.py`](../../tool/release/verify_rollback.py)
(E12-R26, ÚJ ebben a körben).

A restore célja mindvégig egy **ideiglenes** SQLite fájl `/tmp` alatt — a
fejlesztői `backend/strumsight.db`-t a gyakorlat egy pontban sem érintette.

## 2. Lépés 1 — kockázatos feature flag kikapcsolása

A `communityEnabled` / `communityWritesEnabled` / `communityMediaEnabled`
flageket választottuk (`docs/release/kill-switches.md` — `high` risk, valódi
dart-define kill-switch úttal). A kikapcsolás HATÁSÁT a resolver
mechanizmusán mértük (a round-trip és a küszöb-viselkedés), a JELENLEGI
production-alapértéket pedig közvetlenül a `FeatureFlags.forEnvironment`
kiértékelésén.

| # | Parancs | Mért idő | Eredmény |
|---|---|---|---|
| 1 | `flutter test test/tooling/rollback_policy_test.dart --plain-name "A3 —"` | 3.676s | ZÖLD — kikapcsolás után az adat érintetlen; a forrás visszabillentése UTÁN (ugyanazon resolver-példányon) ugyanaz az adat ismét elérhető (round-trip, ADR 0446 D7) |
| 2 | `flutter test test/tooling/rollback_policy_test.dart --plain-name "A4 —"` | 3.656s | ZÖLD — a vész-kikapcsolás a rákövetkező `resolve()` hívásnál (a küszöb-index `k`, inkluzív határ) azonnal érvényre jut; egy memoizáló resolver ezen a cellán megbukna |
| 3 | `dart run` egy ideiglenes szkripten: `FeatureFlags.forEnvironment(AppEnvironment.production, accountEnabled: false)` mezőinek kiolvasása | 0.366s | ZÖLD — megfigyelt profil: `{communityEnabled: false, communityWritesEnabled: false, communityMediaEnabled: false}`, egyezik a `docs/release/kill-switches.md` szerinti biztonságos (kikapcsolt) alapállapottal |

**Mi történt az adattal:** a resolver-szintű mérés (1. sor) explicit
bizonyítja, hogy a kikapcsolás nem érinti az idegen adattárat (a teszt egy
független `userData` listát figyel a kikapcsolás/visszakapcsolás körül,
byte-for-byte egyezéssel) — ez a `verify_rollback.py` flag-profil dimenziójának
előfeltétele: a kikapcsolt állapot ELLENŐRIZHETŐ anélkül, hogy adatot kellene
helyreállítani utána.

## 3. Lépés 2 — modellcsomag rollback-ellenőrzés

| # | Parancs | Mért idő | Eredmény |
|---|---|---|---|
| 4 | `tool.release.verify_rollback.check_model_manifest(".")` (importált mag, izoláltan) | 0.005s | ZÖLD — 4 modell (`chord_crnn.bin`, `strum_crnn.bin`, `strum_crnn_live.bin`, `strum_crnn_live_3c.bin`), mindegyik `sha256` egyezik a lemezen lévő fájllal |

## 4. Lépés 3 — adat-helyreállítás (Kör 8 runbookja szerint)

Forrás- és cél-DB mindvégig `/tmp/e12-r26-drill/*.db` — ideiglenes, a
fejlesztői adatbázistól független fájlok.

| # | Parancs | Mért idő | Eredmény |
|---|---|---|---|
| 5 | `cd backend && PYTHONPATH=. python3 -m alembic upgrade head` (forrás DB, `STRUMSIGHT_DATABASE_URL=sqlite:////tmp/e12-r26-drill/source.db`) | 1.559s | ZÖLD — a forrás a `e09_r27_0020` fejre migrálva |
| 6 | ORM-seed: 1 `users` sor + 1 `user_settings` sor a forrásba | 0.541s | ZÖLD |
| 7 | `PYTHONPATH=. python3 scripts/backup.py --database-url sqlite:////tmp/e12-r26-drill/source.db --output /tmp/e12-r26-drill/backup.json` | 0.823s | ZÖLD — `revision=e09_r27_0020, users=1, user_settings=1` (+ minden Community tábla `0` sorral) |
| 8 | `PYTHONPATH=. python3 scripts/restore.py --database-url sqlite:////tmp/e12-r26-drill/target.db --input /tmp/e12-r26-drill/backup.json --target-name e12-r26-drill-target` (ÚJ, addig nem létező cél) | 1.554s | ZÖLD — `revision=e09_r27_0020, users=1, user_settings=1` |
| 9 | `python3 tool/release/verify_rollback.py --database-url sqlite:////tmp/e12-r26-drill/target.db --backup /tmp/e12-r26-drill/backup.json --expected-flag-profile <2.lépés profilja> --observed-flag-profile <2.lépés profilja> --json` | 0.852s | ZÖLD, mind a 4 dimenzió PASS: `migration_head` 0.011s (`head=e09_r27_0020`), `record_counts` 0.003s (2 tábla egyezik), `model_manifest` 0.006s (4 modell), `flag_profile` 0.000008s (3 flag egyezik) |
| 10 | A2 füst-teszt a VISSZAÁLLÍTOTT DB-n: `create_app(Settings(database_url=<target>))` + `TestClient`: `POST /auth/register` → `POST /auth/login` → hitelesített `GET /settings` | 0.513s | ZÖLD — `201` / `200` / `200`, mind a három hívás sikeres |

**RTO ezen a boxon, mérve:** az 5–10. lépés (migráció, seed, backup, restore,
ellenőrzés, kliens-füstteszt) mért időtartamainak összege `1.559s + 0.541s +
0.823s + 1.554s + 0.852s + 0.513s = 5.842s` — ez a `docs/operations/database-recovery.md`
§5 RTO-fogalmának SQLite-alapú, mért felső korlátja ezen a boxon; egy valódi
Postgres-célon a runbook szerint a domináns tényező a sor-soronkénti `INSERT`
lenne, amit ez a gyakorlat nem tud mérni (nincs Postgres ezen a boxon).

## 5. Valódi-sértés próba (brief §6, KÖTELEZŐ)

A `verify_rollback.py` `check_migration_head` függvényét IDEIGLENESEN úgy
mutáltuk, hogy fej-eltérésre `FAIL` helyett `PASS`-t adjon vissza (a részletes
diff a round brief §10-ében). A cél: bizonyítani, hogy az **A1** mérce-cella
(`backend/tests/test_rollback_drill.py::test_verify_rollback_fails_on_migration_head_mismatch`)
TÉNYLEG méri azt, amit állít — nem csak véletlenül zöld.

| # | Parancs | Mért idő | Eredmény |
|---|---|---|---|
| 11 | `python3 -m pytest backend/tests/test_rollback_drill.py` (mutált `check_migration_head` mellett) | 7.25s | PIROS — `1 failed, 5 passed`; a bukott cella pontosan `test_verify_rollback_fails_on_migration_head_mismatch` |
| 12 | ugyanaz a parancs, a mutáció VISSZAÁLLÍTÁSA után | 7.07s | ZÖLD — `6 passed` |

A visszaállított állapot bizonyítéka: a 12. sor futása után `git diff
tool/release/verify_rollback.py` üres (a fájl bájtra egyezik a mutáció előtti,
commitolt állapottal).

## 6. Amit ezen a boxon NEM lehetett elvégezni

- **Élő cohort-rollout leállítása.** Nincs futó staging/production
  infrastruktúra ezen a boxon (round brief §0.0) — a `docs/release/`
  cohort-rollout gépezete csak élesben, a Kör 30–33 operátori lépéseként
  gyakorolható.
- **Backend endpoint korlátozása éles forgalommal.** A `backend-deploy.md` §3
  traffic-gate rollbackje a `staging`/`prod` környezet éles kérésfolyamára
  épül; ezen a boxon csak a `TestClient`-alapú, szintetikus forgalom
  elérhető (amit a Kör 8 `test_readiness_and_recovery.py`-je már mér).
- **App release rollback (store/APK terjesztés).** Sem Play Store, sem
  App Store, sem eszközflotta nem érhető el innen — az App release rollback
  (RC visszavonás, korábbi build újra-terjesztése) a Kör 25 RC-folyamatának
  operátori, ezen a boxon nem reprodukálható lépése.

## 7. Felfedezett runbook-hibák

**Egy hibát találtunk, mérve, nem javítva** (`docs/operations/database-recovery.md`
tiltott zóna ebben a körben — a §0.0.1 STOP-protokoll szerint LELET, nem
csendes javítás):

- `docs/operations/database-recovery.md` §2/§3 a `backup.py`/`restore.py`
  szkripteket **közvetlen fájlútvonalként** dokumentálja
  (`.venv/bin/python scripts/backup.py ...`), a repó minden MÁS
  parancssori példája (`backend/README.md`: `alembic`, `ruff`, `pytest`)
  viszont következetesen `-m` modul-formát használ. A kettő NEM
  egyenértékű: CPython a fájlútvonal-alakú indításnál a szkript SAJÁT
  könyvtárát (`backend/scripts/`) teszi a `sys.path[0]`-ra, a
  meghívás könyvtárát (`backend/`) NEM — ezért az `app` csomag
  (`backend/app/`) importja MÉRHETŐEN elbukik, FÜGGETLENÜL attól, van-e
  aktivált virtualenv:

  ```
  $ cd backend && python3 scripts/backup.py --database-url ... --output ...
  Traceback (most recent call last):
    File ".../backend/scripts/backup.py", line 35, in <module>
      from app import models as _models  # noqa: F401 -- registers ORM metadata
  ModuleNotFoundError: No module named 'app'
  ```

  A gyakorlat 7–8. lépése (fent) csak `PYTHONPATH=.` előtaggal futott le
  sikeresen. A `database-recovery.md` dokumentált parancsa, PONTOSAN ahogy le
  van írva, egy friss checkout-on ezt a hibát adná — ezt a fájlt ez a kör nem
  módosíthatja (tiltott zóna), a javítás egy jövőbeli kör dolga.

Ezen felül **nem találtunk** más eltérést a Kör 8 futtatott runbookjai
(`backend-deploy.md`, `database-recovery.md`) és a tényleges, mért viselkedés
között — a `backup.py`/`restore.py` kettős-megerősítés (`--force` +
`--confirm-target`), a `restore.py` séma-vissza-nem-léptetés ellenőrzése és a
migrációs fej rögzítése mind a dokumentált módon viselkedett.
