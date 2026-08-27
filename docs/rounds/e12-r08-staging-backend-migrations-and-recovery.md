# E12-R08 — Staging backend, migrations és recovery alap

- **Státusz:** PREPARED (előre megírva 2026-08-27, kód olvasva: `main @ 9ca4a0dc`)
- **Típus:** Chapter 12 (Release Roadmap, Sprint Planning & Final Integration), Kör 8
- **Kör-azonosító:** `E12-R08`
- **Branch:** `<motor>/e12-r08-staging-backend-migrations-and-recovery`
- **Előfeltétel:** `E12-R04` merge-elve (a zárt `env` értékkészlet és a staging fogalma onnan jön)
- **Brief szerzője:** Claude (Opus 5)
- **Előre kiosztott ADR:** `ADR 0449` — a szám FOGLALT (Chapter 12 batch-tartomány).

**Visszakeresett előzmény:** `node tools/knowledge-rag.mjs --corpus lessons,halts,adr --top 5 "backend staging deploy docker alembic migration readiness backup restore"` → **[ADR 0060](../adr/0060-alembic-schema-source-and-injected-engine-lifecycle.md)** (score 3.00): az Alembic az EGYETLEN production séma-forrás, az engine-életciklus injektált. A readiness-gate és a migration-before-start ezt a döntést KÖVETI — `create_all` bevezetése tilos.

> ⚠ **Pre-flight (indítás előtt KÖTELEZŐ):** számold újra a `backend/alembic/versions/` migrációit (a megíráskor **21**, `e01_r12_0001` … `e09_r27_0020`) és olvasd el a `backend/app/main.py` jelenlegi indulási/health útvonalait. A `backend/README.md` futtatási parancsait a §7 a MÉRT alakban idézze.

## 0.0 Mit jelent itt a „staging deploy"

Ezen a boxon nincs futó staging infrastruktúra. A kör TERMÉKE a reprodukálható artefaktum és a bizonyíthatóan működő eljárás: Dockerfile, deploy-leírók, migration-before-start readiness gate, backup/restore script és a hozzájuk tartozó, LOKÁLISAN futtatható pytest-cellák (SQLite/ideiglenes DB felett). A valódi felhő-deploy operátori (user-) lépés, és a §6 egyik cellája sem függ tőle.

```ai-router
schema_version = 1
risk = "high"
allowed_paths = [
  "backend/Dockerfile",
  "backend/deploy/staging.env.example",
  "backend/deploy/README.md",
  "backend/app/main.py",
  "backend/scripts/backup.py",
  "backend/scripts/restore.py",
  "backend/tests/test_readiness_and_recovery.py",
  "docs/operations/backend-deploy.md",
  "docs/operations/database-recovery.md",
  "docs/rounds/e12-r08-staging-backend-migrations-and-recovery.md",
]
gate_tests = [
  "test/app/config/feature_flags_test.dart",
]
native_gate = false
```

**Kockázat = high, indoklás:** a diff az adatbázis-migráció és a mentés/visszaállítás útját érinti — egy hibás restore-script felhasználói adatot semmisíthet meg, egy hiányos readiness-gate pedig migrálatlan sémán indítaná a szolgáltatást. A `security-reviewer` futtatása a review-ban KÖTELEZŐ.

## 0. Kör-jelzés és STOP-protokoll

```bash
tools/codex-signal.sh progress "<egy sor>"
tools/codex-signal.sh done "<egy sor>"
tools/codex-signal.sh stopped "<egy sor>"
tools/codex-signal.sh blocked "<egy sor>"
```

**STOP-protokoll:** ha a munkához ÚJ Alembic migráció vagy a `backend/app/models.py` módosítása kellene, a kimenet a `stopped` jelzés és brief-revízió kérése — ez a kör séma-változást NEM hoz.

## 1. Cél

Production-szerű staging: reprodukálható konténer-build, migráció-vezérelt indulás, bizonyított mentés/visszaállítás és dokumentált rollback.

## 2. Jelenlegi állapot — mért tények

- `backend/Dockerfile` és `backend/deploy/` **nem létezik**; a futtatás ma közvetlen `uvicorn` a `backend/README.md` szerint.
- `backend/alembic/versions/`: **21** migráció, lineáris lánc (`e01_r12_0001` → `e09_r27_0020`). ADR 0060: az Alembic az egyetlen séma-forrás.
- `backend/app/config.py`: `database_url` alapértelmezés `sqlite:///./strumsight.db`, `allow_sqlite_in_prod` flag létezik.
- `backend/tests/test_migrations.py` **létezik** — a migrációs lánc regresszió-őre; **átírása a zöldért TILOS**.
- `backend/scripts/` **nem létezik**; `docs/operations/` MA egyetlen Community moderation runbookot tartalmaz.
- A `tools/round-gate.sh` ismer backend-sávot (ADR 0173), tehát a Python-cellák a gate-en belül is futnak.

## 3. Scope

**Benne van:** `backend/Dockerfile` (rögzített base image digest, nem-root user, determinisztikus `requirements` telepítés) · `backend/deploy/staging.env.example` + `deploy/README.md` (külön DB és media-cél; production titok TILOS a staging profilban) · migration-before-start és `/readyz` readiness gate a `main.py`-ban: **migrálatlan séma → NOT READY**, a szolgáltatás nem fogad forgalmat · `backend/scripts/backup.py` és `restore.py` (konzisztens dump + visszatöltés friss adatbázisba, ellenőrző összesítéssel) · `backend/tests/test_readiness_and_recovery.py` · `docs/operations/backend-deploy.md` (deploy, rollback, secret-rotáció lépések) és `docs/operations/database-recovery.md` (RTO/RPO, ellenőrzési lépések).

**NINCS benne (tilos):**

- ÚJ Alembic migráció vagy `models.py` változás.
- `create_all` vagy bármely, az Alembicet megkerülő séma-létrehozás (ADR 0060).
- Valódi felhő-deploy, DNS, TLS vagy titok-kiosztás.
- `docs/adr/**` — az ADR 0449-et a Claude írja.

## 4. Engedélyezett fájlok

| Útvonal | Indok |
|---|---|
| `backend/Dockerfile` | ÚJ — reprodukálható image |
| `backend/deploy/staging.env.example` | ÚJ — staging profil (titok NÉLKÜL) |
| `backend/deploy/README.md` | ÚJ — deploy-lépések |
| `backend/app/main.py` | migration-before-start + `/readyz` |
| `backend/scripts/backup.py` | ÚJ — mentés |
| `backend/scripts/restore.py` | ÚJ — visszaállítás |
| `backend/tests/test_readiness_and_recovery.py` | a §6 cellái |
| `docs/operations/backend-deploy.md` | ÚJ — üzemeltetési runbook |
| `docs/operations/database-recovery.md` | ÚJ — recovery runbook |

**Tilos zóna:** `backend/alembic/**` · `backend/app/models.py` · `backend/app/config.py` · `backend/app/routers/**` · `lib/**` · `.github/**` · `docs/adr/**`

## 5. Kötött architekturális döntések (ADR 0449)

### 5.1 A readiness a MIGRÁCIÓS FEJRE mér, nem a kapcsolatra

`/readyz` akkor zöld, ha az adatbázis elérhető ÉS az alkalmazott revízió az `alembic heads` értéke. **NEM elfogadható gyengítés:** „a DB válaszol, tehát ready" — pontosan ez engedné migrálatlan sémán a forgalmat.

### 5.2 A restore SOHA nem ír felül létező adatbázist megerősítés nélkül

A `restore.py` alapértelmezésben ÚJ célra tölt vissza; meglévő cél felülírásához explicit `--force` és a cél nevének megismétlése kell. **NEM elfogadható gyengítés:** csendes felülírás „ez a szokásos eset" indoklással.

### 5.3 A staging profil production titkot nem fogadhat el

A staging `.env` mintában nincs production titok, és a betöltés hibázik, ha production-jelölésű titkot kap. **NEM elfogadható gyengítés:** „ugyanaz a titok, csak más DB".

## 6. Acceptance criteria

| # | Kritérium | Bizonyíték |
|---|---|---|
| A1 | Migrálatlan sémán a `/readyz` NOT READY, és a szolgáltatás nem szolgál ki üzleti végpontot | `test_readiness_and_recovery.py` |
| A2 | `alembic upgrade head` után a `/readyz` READY | `test_readiness_and_recovery.py` |
| A3 | `backup.py` → friss DB → `restore.py` után a rekordszámok és a migrációs fej egyeznek | `test_readiness_and_recovery.py` |
| A4 | `restore.py` létező célra `--force` nélkül nem-nulla kóddal, adat-módosítás NÉLKÜL lép ki | `test_readiness_and_recovery.py` |
| A5 | A staging profil production-jelölésű titokkal indulási hibát ad | `test_readiness_and_recovery.py` |
| A6 | A `Dockerfile` rögzített base-image digestet használ és nem-root userrel fut | `test_readiness_and_recovery.py` statikus cellája |
| A7 | A meglévő `backend/tests/test_migrations.py` VÁLTOZATLANUL zöld | a §7 backend futtatás |

### 6.1 Mérce-mátrix — melyik hibás implementációt melyik cella fogja pirosra

| Hibás implementáció | Melyik cella vált PIROSRA |
|---|---|
| A readiness csak DB-kapcsolatot ellenőriz | A1 |
| A restore alapértelmezésben felülírja a célt | A4 |
| A backup nem menti a migrációs fejet, csak a táblákat | A3 |
| A `Dockerfile` `latest` taget használ | A6 |
| A staging profil elfogadja a production `secret_key`-t | A5 |

**Valódi-sértés próba (KÖTELEZŐ, a §10-ben dokumentálva):** cseréld a readiness-ellenőrzést puszta `SELECT 1`-re, futtasd a backend cellákat → az **A1** cellának PIROSNAK kell lennie → állítsd vissza.

## 7. Kötelező ellenőrzések

Backend sáv (külön processzként, a `tools/round-gate.sh` backend-ága szerint):

```bash
cd backend && python -m pytest tests/test_readiness_and_recovery.py tests/test_migrations.py -q
```

A Flutter-oldali érintetlenség bizonyítéka a gate artefaktumon:

```bash
tools/round-gate.sh test/app/config/feature_flags_test.dart
```

## 8. Implementációs sorrend

1. `backend/app/main.py` — readiness a migrációs fejre.
2. `backend/tests/test_readiness_and_recovery.py` — A1/A2 cellák (RED-ből).
3. `backend/scripts/backup.py` + `restore.py` — A3/A4.
4. `backend/Dockerfile` + `deploy/` — A5/A6.
5. A két `docs/operations/` runbook.
6. A valódi-sértés próba a §10-be.

## 9. Kockázatok

- **Adatvesztés a restore úton.** A legsúlyosabb: csendes felülírás (A4).
- **Az Alembic megkerülése.** Egy „gyors" `create_all` a tesztekhez ADR 0060-at sértene, és a staging/production séma szétcsúszna.
- **A meglévő migrációs teszt regressziója.** A `main.py` indulási sorrendjének átrendezése könnyen elmozdítja (A7).

## 10. Implementation handoff — az implementer tölti ki

## 11. Review — a Claude tölti ki
