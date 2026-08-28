# E12-R08 review — Staging backend, migrations és recovery alap

- **Kör:** `E12-R08` · **Ág:** `sonnet-impl/e12-r08-staging-backend-migrations-and-recovery`
- **Implementer motor:** `sonnet-impl` (Claude Sonnet 5, `--effort high`)
- **Reviewer:** Claude (orchestrátor), read-only + eldobható próbatesztek
- **Brief:** [`docs/rounds/e12-r08-staging-backend-migrations-and-recovery.md`](../rounds/e12-r08-staging-backend-migrations-and-recovery.md)
  (a §0.0 pre-flight revízió R1–R4 a mérvadó)
- **ADR:** [`0449`](../adr/0449-staging-readiness-traffic-gate-and-recovery.md)
- **Kockázat:** `high` → a `security-reviewer` futtatása KÖTELEZŐ volt, megtörtént.

## Verdikt

**VÉGSŐ DÖNTÉS: APPROVED** — 0 nyitott BLOCKER/MAJOR/MINOR. A javító kör (1.)
mind a négy leletet lezárta, és a lezárást leletenként ÚJRAMÉRTEM.

## 1. Scope és mérce

| Ellenőrzés | Eredmény |
|---|---|
| Scope-audit (`tools/scope-audit.py --base 60160050`) | `Legacy scope audit OK (6016005026ef..6e004ae8ef27, 10 changed path(s), 0 generated/ignored)` |
| Tilos zóna (`test_migrations.py`, `conftest.py`, `config.py`, `alembic/**`, `.github/**`, `tools/**`) | érintetlen — a diff 10 útvonala mind a brief §4 listáján van |
| `tools/round-gate.sh test/app/config/feature_flags_test.dart` (implementer HEAD `8e71679b`) | **9/9 ZÖLD** (format, analyze, test, architecture, secrets, l10n, backend ruff format, backend ruff check, backend pytest) |
| `tools/round-gate.sh …` (javító kör HEAD `6e004ae8`) | 9/9 ZÖLD (implementer-jelzés `status=done`, saját ruff/pytest újramérés zöld) |
| `dirty_files=1` a `done` jelzésnél | **kivizsgálva** — a jelzés kiírásakor keletkezett átmeneti állapot; a `git status --short` a jelzés után üres, elveszett munka nincs |

## 2. Az implementer megoldásának ellenőrzése (§0.0 R1–R4)

- **R1 (nincs új útvonal):** a diff nem vezet be `/readyz`-t; a
  `test_openapi_contract_is_deterministic` egyenlőség-cellája változatlanul
  zöld — a nyitott útvonalak halmaza nem mozdult.
- **R2 (a kör ÚJ tartalma a forgalmi kapu):** `_traffic_gate` per-router
  `Depends`, nem middleware. Az implementer indoklása mért: middleware esetén a
  nem regisztrált Lab-útvonal 503-at kapna 404 helyett, ami a meglévő
  `test_hardening.py::test_prod_defaults_do_not_register_lab_routes` cellát
  törte volna (a `8e71679b` commit pontosan ezt javítja).
- **R3 (deploy-környezetre szűkített kapu):** `_TRAFFIC_GATE_ENVIRONMENTS =
  {"staging", "prod"}`; a `conftest.py` `create_all`-alapú fixture-jén álló
  meglévő cellák zöldek maradtak (gate 9/9) — az A7 tartható.
- **R4 (A5 az eldönthetőt méri):** a `config.py` érintetlen; a cella a
  `_guard_staging` meglévő őrét használja + a profil-minta statikus vizsgálatát.

## 3. Leletek és lezárásuk

### MAJOR-1 (security review, M1) — LEZÁRVA

*Lelet:* a `backup.py` dumpja `email` + bcrypt `hashed_password` oszlopokat
tartalmaz, a `database-recovery.md` §2 példaparancsa a **trackelt** `backend/`
könyvtárba írta (`git check-ignore` nincs találat), és a fájl a default
umaskkal (0644) jött létre. A repo titok-scannere a JSON `"hashed_password":`
alakra nem illeszkedik.

*Javítás (`6e004ae8`):* a `write_backup` `os.open(..., O_CREAT|O_WRONLY|O_TRUNC,
0o600)`-val ír — nincs „írás, majd chmod" ablak; a docstring kimondja a
PII/hash-tartalmat; a runbook minden példaparancsa a repófán KÍVÜLRE ír, és
kimondja a nem-commitolható / titkosított tárolás / megőrzési idő operatív
szabályt. A `backend/.gitignore` **nincs** az engedélyezett listán, ezért a
javítás szándékosan az engedélyezett két fájlban történt.

### MAJOR-2 (Claude review) — LEZÁRVA, ÚJRAMÉRVE

*Lelet (mérve):* a `staging.env.example` a `# strumsight:allow-secret-file`
marker miatt ki van véve a repo titok-scanneréből, tehát az A5 cella az
EGYETLEN őre. A cella `_SECRET_LIKE_KEY = (SECRET|TOKEN|_KEY)` mintája viszont
a `STRUMSIGHT_DATABASE_URL` kulcsra nem illeszkedik: a `<db-password>`
helyőrzőt valódi jelszóra cserélve a cella **ZÖLD maradt** — a legvalószínűbb
hitelesítő-vektor őrizetlen volt.

*Javítás (`6e004ae8`):* a cella az `URL`/`PASSWORD`/`PASS`/`DSN` jellegű
kulcsokra is illeszkedik, és bármely érték `séma://user:jelszó@host`
userinfo-részét is vizsgálja.

*Reviewer újramérés (eldobható próba, izolált másolat):* ugyanaz a
valódi-jelszós behelyettesítés most **PIROS**
(`FAILED …::test_staging_env_example_carries_no_real_secret`).

### MINOR-1 (security review, N2) — LEZÁRVA

*Lelet:* `command.upgrade(config, backup_revision)` nem lép vissza; újabb sémán
álló célra régebbi mentést visszatöltve a séma némán a saját feje mögött
maradt volna (adatvesztés nincs — a delete+insert egy tranzakcióban van).

*Javítás:* a `restore_database` a séma-építés ELŐTT megméri a cél aktuális
fejét, és eltérés esetén `RestoreRejected` (írás nélkül). Új A4b cella
(`test_restore_rejects_target_schema_newer_than_backup`) méri.

### MINOR-2 — LEZÁRVA

A brief §10 handoff kitöltve, a KÖTELEZŐ valódi-sértés próbák tényleges
kimenetével.

### NOTE-ok (nem blokkolók, nem igényelnek javító kört)

- **N3a (security review):** a `Dockerfile` `chown -R strumsight:strumsight /app`
  írási jogot ad a futtató usernek a saját kódjára. Elterjedt minta;
  szigorítása (read-only kód-mount) üzemeltetési döntés.
- **N3b (security review + Claude):** a `_traffic_gate` staging/prod alatt
  minden üzleti kérésnél `SELECT 1`-et futtat ÉS lemezről olvassa az alembic
  heads-et. Fail-closed és helyes, de per-request DB+FS költség; a
  `ScriptDirectory` fejei image-en belül állandók, tehát később
  memoizálhatók.
- **N-C1 (Claude):** az új A4b őr a fordított irányt (cél a mentésnél
  RÉGEBBI fejen) is elutasítja, holott az előre-upgrade működne. Fail-closed
  irányba szigorúbb a szükségesnél; a runbook friss célt ír elő, ezért
  megtartható.
- **N-C2 (Claude):** a `scripts/` nem kerül be az image-be, tehát a
  mentés/visszaállítás a konténerből nem futtatható — a runbookok a fán futó
  hívást írják, így ez ma következetes.

## 4. Reviewer eldobható próbatesztjei (valódi-sértés, izolált másolaton)

| Próba | Elvárt | Mért |
|---|---|---|
| A forgalmi kapu predikátuma → puszta `SELECT 1` | A1 PIROS | `FAILED …test_traffic_gate_blocks_business_endpoint_on_migration_mismatch[staging]` és `[prod]` (`assert 401 == 503`) |
| `restore.py`: `force and confirm_target == target_name` → `force` | A4 PIROS | `FAILED …test_restore_refuses_to_overwrite_existing_data_without_double_confirmation` |
| `staging.env.example`: `STRUMSIGHT_DIAG_TOKEN` valódi értékre | A5 PIROS | `FAILED …test_staging_env_example_carries_no_real_secret` |
| `staging.env.example`: `<db-password>` valódi jelszóra (**javítás ELŐTT**) | A5 PIROS | **ZÖLD** → MAJOR-2 lelet |
| Ugyanaz (**javítás UTÁN**) | A5 PIROS | `FAILED …test_staging_env_example_carries_no_real_secret` |

## 5. Acceptance-teljesítés

| # | Állapot | Bizonyíték |
|---|---|---|
| A1 | ✅ | `test_traffic_gate_blocks_business_endpoint_on_migration_mismatch[staging|prod]` + a reviewer `SELECT 1` próbája |
| A2 | ✅ | `test_traffic_gate_allows_normal_behavior_once_migrated` (401, nem 503 — a túl-blokkolás kizárva) |
| A2b | ✅ | `test_health_routes_stay_reachable_while_gate_is_active` |
| A3 | ✅ | `test_backup_then_restore_round_trip` (`target_snapshot == source_snapshot`, a fejjel együtt) |
| A4 | ✅ | `test_restore_refuses_to_overwrite_existing_data_without_double_confirmation` (3 elutasító ág + változatlan cél) |
| A4b | ✅ | `test_restore_rejects_target_schema_newer_than_backup` (fix-kör MINOR-1) |
| A5 | ✅ | `test_staging_env_example_carries_no_real_secret` (URL-userinfo fedéssel) + `test_staging_settings_reject_dev_default_secret_key` |
| A6 | ✅ | `test_dockerfile_pins_base_image_by_digest_and_runs_as_non_root` |
| A7 | ✅ | gate `backend pytest` ZÖLD változatlan `test_migrations.py`/`conftest.py` forrással |
