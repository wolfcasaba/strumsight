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
| 1 | `flutter test test/tooling/rollback_policy_test.dart --plain-name "A3 —"` | 3.693s | ZÖLD — kikapcsolás után az adat érintetlen; a forrás visszabillentése UTÁN (ugyanazon resolver-példányon) ugyanaz az adat ismét elérhető (round-trip, ADR 0446 D7) |
| 2 | `flutter test test/tooling/rollback_policy_test.dart --plain-name "A4 —"` | 3.703s | ZÖLD — a vész-kikapcsolás a rákövetkező `resolve()` hívásnál (a küszöb-index `k`, inkluzív határ) azonnal érvényre jut; egy memoizáló resolver ezen a cellán megbukna |
| 3 | `dart run` egy ideiglenes szkripten: `FeatureFlags.forEnvironment(AppEnvironment.production, accountEnabled: false)` mezőinek kiolvasása | 0.360s | ZÖLD — megfigyelt profil: `{communityEnabled: false, communityWritesEnabled: false, communityMediaEnabled: false}`, egyezik a `docs/release/kill-switches.md` szerinti biztonságos (kikapcsolt) alapállapottal |

**Mi történt az adattal (javítva, MINOR-5 — a review mérte, hogy az eredeti
mondat túlállított):** az A3 cella azt bizonyítja, amit TÉNYLEGESEN
mér — a **feloldás-round-trip**-et. A `userData` egy TESZT-LOKÁLIS Dart lista
(`test/tooling/rollback_policy_test.dart:77`), amelyhez a vizsgált
`FeatureFlagResolver.resolve` nem fér hozzá (nincs paraméterként átadva, nincs
globális állapotban) — a két `expect(userData, originalSnapshot)` állítás
ezért szerkezetileg NEM bizonyítja, hogy a kikapcsolás nem érinti az idegen
adattárat; egy szándékosan „takarító" resolver-implementáció is zölden
átmenne ezen a két asszerción. Amit az A3 VALÓBAN mér: `emergencyOff` → a
forrás visszabillentése → `local`, UGYANAZON a resolver-példányon — egy
„latch-elő" (a vész-kikapcsolást beragasztó, memoizáló) implementáció ezen
elbukna (a review P1 valódi-sértés próbája ezt igazolta: egy memoizáló
resolver mind az A3, mind az A4 cellát pirosra váltja). A §6.1 mátrix „a
kill switch takarít (adatot töröl) → A3 piros" sora EZEN A RÉTEGEN nem
teljesíthető — a resolvernek nincs adathozzáférése, tehát nem is takaríthat;
az adat-megmaradás valódi mércéje a backend-oldali **A1 lánc** (a
rekordszám-egyezés restore után, `backend/tests/test_rollback_drill.py` —
ld. §4, ahol ez a lánc most, MAJOR-1 javítása után, a valós fedezeti rést is
megmutatja).

## 3. Lépés 2 — modellcsomag rollback-ellenőrzés

| # | Parancs | Mért idő | Eredmény |
|---|---|---|---|
| 4 | `tool.release.verify_rollback.check_model_manifest(".")` (importált mag, izoláltan) | 0.006s | ZÖLD — 4 modell (`chord_crnn.bin`, `strum_crnn.bin`, `strum_crnn_live.bin`, `strum_crnn_live_3c.bin`), mindegyik `sha256` egyezik a lemezen lévő fájllal |

## 4. Lépés 3 — adat-helyreállítás (Kör 8 runbookja szerint)

Forrás- és cél-DB mindvégig `/tmp/e12-r26-drill-fix1/*.db` — ideiglenes, a
fejlesztői adatbázistól független fájlok. (A javító körben a könyvtárnevet
`-fix1` jelöli, hogy a mérés a javított `verify_rollback.py`-hoz tartozzon;
a fájlok tartalma és a parancsok egyébként azonosak az eredeti gyakorlattal.)

| # | Parancs | Mért idő | Eredmény |
|---|---|---|---|
| 5 | `cd backend && PYTHONPATH=. python3 -m alembic upgrade head` (forrás DB, `STRUMSIGHT_DATABASE_URL=sqlite:////tmp/e12-r26-drill-fix1/source.db`) | 1.571s | ZÖLD — a forrás a `e09_r27_0020` fejre migrálva, **29 tábla** (`sqlite3 source.db "select count(*) from sqlite_master where type='table'"` → `29`; ld. §7 A6 runbook-lelet) |
| 6 | ORM-seed: 1 `users` sor + 1 `user_settings` sor a forrásba | 0.659s | ZÖLD |
| 7 | `PYTHONPATH=. python3 scripts/backup.py --database-url sqlite:////tmp/e12-r26-drill-fix1/source.db --output /tmp/e12-r26-drill-fix1/backup.json` | 0.832s | ZÖLD — kimenet PONTOSAN: `backup written to /tmp/e12-r26-drill-fix1/backup.json (revision=e09_r27_0020, users=1, user_settings=1)`. A dump kulcsai KIZÁRÓLAG `['user_settings', 'users']` — **egyetlen Community tábla SEM szerepel benne** (a korábbi, e sorban itt állt „+ minden Community tábla 0 sorral" zárójeles állítás MÉRHETŐEN HAMIS volt — MAJOR-2 javítva; a gyökérok: §7 A6 runbook-lelet, MAJOR-1) |
| 8 | `PYTHONPATH=. python3 scripts/restore.py --database-url sqlite:////tmp/e12-r26-drill-fix1/target.db --input /tmp/e12-r26-drill-fix1/backup.json --target-name e12-r26-drill-fix1-target` (ÚJ, addig nem létező cél) | 1.561s | ZÖLD — `revision=e09_r27_0020, user_settings=1, users=1`; a cél séma a TELJES 29 táblás fejre migrálva (az `alembic upgrade` mindig a teljes migrációs láncot futtatja, függetlenül attól, mit tartalmaz a dump) |
| 9 | `python3 tool/release/verify_rollback.py --database-url sqlite:////tmp/e12-r26-drill-fix1/target.db --backup /tmp/e12-r26-drill-fix1/backup.json --expected-flag-profile expected.json --observed-flag-profile observed.json --json` (a két fájl tartalma EGYEZIK a 3. sor mért profiljával, de két KÜLÖN, önállóan felépített fájl — nem ugyanaz a fájlútvonal mindkét kapcsolóra, MINOR-7) | 0.455s | **PIROS** — `migration_head` PASS (0.011s, `head=e09_r27_0020`); **`record_counts` FAIL** (0.002s, 26 Community tábla „present in the live database but not covered by the backup dump" — MAJOR-1: a `backup.py` a 29 élő táblából csak 2-t dumpol); `model_manifest` PASS (0.006s, 4 modell); `flag_profile` PASS (0.000007s, 3 flag egyezik); `OVERALL: FAIL`, `EXIT=1` |
| 9b | UGYANAZ, de `--observed-flag-profile` egy ELTÉRŐ tartalmú fájlra mutat (`communityWritesEnabled: true`, negatív ág — MINOR-7: a flag_profile dimenzió falszifikáló próbája, nem csak az önmagával-egyező eset) | 0.426s | PIROS — `flag_profile` **FAIL**: `communityWritesEnabled: expected=False observed=True`; a többi dimenzió változatlan (`record_counts` továbbra is FAIL); `OVERALL: FAIL`, `EXIT=1` |
| 10 | A2 füst-teszt a VISSZAÁLLÍTOTT DB-n: `create_app(Settings(database_url=<target>))` + `TestClient`: `POST /auth/register` → `POST /auth/login` → hitelesített `GET /settings` | 1.413s | ZÖLD — `201` / `200` / `200`, mind a három hívás sikeres — a `users`/`user_settings` táblák a restore-ban MEGVANNAK, hiába hiányzik 26 Community tábla a dumpból; az A2 cella csak az account-utat méri, nem a Community-adatok megmaradását |

**RTO ezen a boxon, mérve:** az 5–10. lépés (migráció, seed, backup, restore,
ellenőrzés, kliens-füstteszt) mért időtartamainak összege `1.571s + 0.659s +
0.832s + 1.561s + 0.455s + 1.413s = 6.491s` — ez a `docs/operations/database-recovery.md`
§5 RTO-fogalmának SQLite-alapú, mért felső korlátja ezen a boxon; egy valódi
Postgres-célon a runbook szerint a domináns tényező a sor-soronkénti `INSERT`
lenne, amit ez a gyakorlat nem tud mérni (nincs Postgres ezen a boxon). **Ez
az RTO-szám az elvégzett MŰVELETEK idejét méri, nem a helyreállítás
teljességét** — a 9. sor PIROS eredménye pontosan azt mutatja, hogy a mai
`backup.py`-alapú lánc (MAJOR-1 gyökéroka, §7) egy 6.491s alatt lefutó, de
27/29 táblát elvesztő „helyreállítást" adna éles Community adatra; a
`verify_rollback.py` (E12-R26 terméke, e körben javítva) pontosan ezt a
különbséget teszi számszerűvé és fail-closeddá.

## 5. Valódi-sértés próba (brief §6, KÖTELEZŐ)

A `verify_rollback.py` `check_migration_head` függvényét IDEIGLENESEN úgy
mutáltuk, hogy fej-eltérésre `FAIL` helyett `PASS`-t adjon vissza (a részletes
diff a round brief §10-ében). A cél: bizonyítani, hogy az **A1** mérce-cella
(`backend/tests/test_rollback_drill.py::test_verify_rollback_fails_on_migration_head_mismatch`)
TÉNYLEG méri azt, amit állít — nem csak véletlenül zöld.

| # | Parancs | Mért idő | Eredmény |
|---|---|---|---|
| 11 | `python3 -m pytest backend/tests/test_rollback_drill.py` (mutált `check_migration_head` mellett) | 8.03s | PIROS — `1 failed, 14 passed`; a bukott cella pontosan `test_verify_rollback_fails_on_migration_head_mismatch` |
| 12 | ugyanaz a parancs, a mutáció VISSZAÁLLÍTÁSA után | 8.14s | ZÖLD — `15 passed` |

(A javító körben a cellaszám 6-ról 15-re nőtt — a review MAJOR/MINOR
leletei miatt hozzáadott új cellák; a próba módszertana és a mért PIROS/ZÖLD
kontraszt változatlan.)

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

**Két hibát találtunk, mérve, nem javítva** (`backend/scripts/**` és
`docs/operations/database-recovery.md` tiltott zóna ebben a körben — a §0.0.1
STOP-protokoll szerint LELET, nem csendes javítás):

- **(A6, MAJOR-1 gyökéroka) `backend/scripts/backup.py` a 29 élő táblából
  csak 2-t ment el — a dump NEM teljes adatmentés.** A szkript `from app
  import models as _models; from app.database import Base` importot használ,
  ami a `Base.metadata`-t kizárólag a KÖZVETLENÜL importált ORM-modellekre
  (`users`, `user_settings`) szűkíti. A 27 Community tábla
  (`community_profiles`, `community_posts`, `community_moderation_cases`
  stb.) raw-DDL Alembic-migrációkban jön létre, ORM-modell NÉLKÜL — ezért a
  `backup.py` dump-ja ŐKET SOHA nem tartalmazza, függetlenül attól, mennyi
  adat van bennük élesben. Reprodukálva, mérve:

  ```
  $ cd backend && python3 -c "from app import models; from app.database import Base; print(len(Base.metadata.tables), sorted(Base.metadata.tables))"
  2 ['user_settings', 'users']

  $ STRUMSIGHT_DATABASE_URL=sqlite:////tmp/e12-r26-drill-fix1/source.db PYTHONPATH=. python3 -m alembic upgrade head
  $ sqlite3 /tmp/e12-r26-drill-fix1/source.db "select count(*) from sqlite_master where type='table'"
  29

  $ PYTHONPATH=. python3 scripts/backup.py --database-url sqlite:////tmp/e12-r26-drill-fix1/source.db --output /tmp/e12-r26-drill-fix1/backup.json
  backup written to /tmp/e12-r26-drill-fix1/backup.json (revision=e09_r27_0020, users=1, user_settings=1)
  ```

  Ez azt jelenti, hogy egy PRODUKCIÓS `backup.py` futás — akárhány
  Community-sor van élesben — mindig csak a fiók-táblákat menti el; egy
  visszaállítás utáni Community-adatvesztés a mai runbookkal ÉSZREVÉTLEN
  maradna, ha a `verify_rollback.py` nem hasonlítaná össze az ÉLŐ
  tábla-halmazt is a dumpéval (ez a MAJOR-1 javítása ebben a körben — ld. §4,
  9. sor: a mai lánc mérve PIROS). A javítás (a `backup.py`-t is bejáróvá
  tenni az élő séma MINDEN táblájára, pl. `inspect(engine).get_table_names()`
  alapján, nem `Base.metadata`-ra) `backend/scripts/**`-t érintené — tiltott
  zóna ebben a körben; egy jövőbeli kör dolga.

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
között — a `restore.py` séma-vissza-nem-léptetés ellenőrzése (8. sor: a cél
mindig a backup revíziójára migrál, nem tovább) és a migrációs fej rögzítése
mind a dokumentált módon viselkedett.

**Javítva (MINOR-7):** a korábbi verzió itt azt is állította, hogy „a
`--force` + `--confirm-target` kettős megerősítés … a dokumentált módon
viselkedett" — ez az állítás NEM ebből a gyakorlatból következett. Ennek a
körnek egyetlen parancsában sem szerepel `--force` vagy `--confirm-target`
(a fenti 8. sor mindig ÚJ, üres célra restore-ol, ahol az ADR 0449 D4 kapu
tervezetten nem is aktiválódik — nincs mit felülírni). A kettős megerősítés
tényleges, mért bizonyítéka a Kör 8
`test_readiness_and_recovery.py::test_restore_refuses_to_overwrite_existing_data_without_double_confirmation`
cellája, NEM ez a gyakorlat.
