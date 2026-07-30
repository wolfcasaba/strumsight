# E01-R15 — Backend és ML CI

Státusz: **PLANNING** (pre-flight elvégezve 2026-07-30, kód újraolvasva: `main` @ `ac9a943`)
SDD: docs/sdd/02-epic-01-core-platform.md § „Kör 15 — Backend és ML CI"
Branch: `codex/epic-01-round-15-backend-ml-ci`
Brief szerzője: Claude · Implementáció: Codex
**Előfeltétel: az R12 merge-ölve** (a backend CI `alembic upgrade head` gate-je az
R12-es migrációkra épül). ✅ **Teljesül:** R12 (PR #17), R13 (PR #18) és R14
(PR #19) mind merge-ölve, SDD-sorrendben.

> ✅ **Pre-flight kész (2026-07-30):** a `backend/` fa (R12+R13 eredménye), a
> `.github/workflows/` (R14 eredménye — **új**: `release-apk.yml`) és a
> `test/tooling/` újraolvasva; a §2 ehhez igazítva, a tilos zóna (§4) az R14
> által létrehozott fájlokkal kiegészítve, és az R14-review MINOR-jainak kezelése
> a §12-ben rögzítve.

## 1. Cél

A backendnek ma **semmilyen CI-je nincs** (a 29 pytest csak lokálisan fut), és a
4 shippelt ML-bináris asset mögött **nincs manifest**: egy némán kicserélt vagy
sérült `.bin` fájlt semmi nem fogna meg merge előtt. A kör kimenete: önálló
**backend CI** (pytest + Ruff + migráció-gate), **requirements-szétválasztás**,
rögzített Python-verzió, **ML asset manifest SHA-256 checksumokkal** + az azt
kikényszerítő guard-teszt, és a modellcsere-szabály gépi fedezete.

## 2. Jelenlegi állapot

Ténylegesen elolvasott kód (**2026-07-30, `main` @ `ac9a943` — R12+R13+R14 UTÁN**):

- **Backend CI továbbra sincs.** `.github/workflows/` alatt hat fájl:
  `build-apk.yml`, **`release-apk.yml` (ÚJ — R14)**, `lab-apk.yml`, `chord-train.yml`,
  `ml-train.yml`, `dsp-probe.yml` — egyik sem futtat pytestet. A backend 64 tesztje
  **csak lokálisan** fut.
- **Ruff nincs bevezetve**: se dependency, se config (`backend/pyproject.toml`
  nem létezik); a kód formázottsága Ruff szerint **ellenőrizetlen** (várhatóan ad diffet).
- **`backend/requirements.txt`** — prod és dev dependency EGY fájlban, a
  `# dev / test` kommenttel elválasztva (`pytest>=8,<9`, `httpx>=0.27,<0.29`);
  **`alembic>=1.18,<1.19` már benne van** (R12). `backend/requirements-dev.txt`
  nem létezik. `backend/pytest.ini` létezik.
- **Python-verzió:** a `backend/.venv` **3.12.3**; a `chord-train.yml`/`ml-train.yml`
  3.11-et pinnel; a backend sehol nem rögzít verziót.
- **Backend fa (R12+R13 után):** `app/{config,database,deps,main,models,ratelimit,
  schemas,security}.py` + `app/routers/{auth,diagnostics,settings}.py`;
  `alembic/` (env.py + `versions/e01_r12_0001_initial_account_schema.py`);
  `tests/{conftest,test_auth,test_diagnostics,test_hardening,test_migrations,
  test_settings}.py` → **64 passed** (HANDOFF, R13). A Ruff-formázás tehát 8+3
  app-modult és 5 tesztfájlt érint.
- **ML assetek:** `assets/ml/{chord_crnn,strum_crnn,strum_crnn_live,strum_crnn_live_3c}.bin`
  — mind a négy a `pubspec.yaml` `assets:` blokkjában deklarálva (48–63. sor);
  **manifest nincs**, checksum-gate nincs. A Python→Dart **parity már fedett**
  Dart-teszttel (CQT parity 5e-7, ChordCrnn parity 6.1e-7 — a `flutter test`
  részeként a CI-ben futnak); az export a `ml/chords/export_chord_dart.py`.
- **`test/tooling/` (a guard-tesztek helye, ide jön az új teszt):** `check_assets_test.dart`,
  `diagnostics_storage_separation_test.dart`, `dio_factory_guard_test.dart`,
  `legacy_identifier_guard_test.dart`, `preferences_plugin_import_guard_test.dart`,
  `route_literal_guard_test.dart` — a minta adott, az új manifest-teszt ebbe a sorba áll be.
- **`tool/ci/check_assets.dart`** (R14) ellenőrzi, hogy minden pubspec-deklarált
  asset létezik és az ML-binárisok nem üresek — de **üres deklarációs halmazon
  némán zöld** (R14-review MINOR-1). Ezt e kör manifestje zárja le (§5.7), a
  `check_assets.dart` **módosítása nélkül**.
- **Training workflow-k** (`chord-train.yml`: dispatch + path-filter push;
  `ml-train.yml`: dispatch) — a teljes training már most sem fut PR-onként ✓;
  ez a kör nem nyúl hozzájuk.
- **A `flutter test` gate-sor MINDKÉT APK-workflow-ban fut** (`build-apk.yml` és
  `release-apk.yml` szó szerint azonos kilenc lépéssel — R14-review MINOR-2), ezért
  az új manifest-teszt **automatikusan mindkettőt** gate-eli; e kör nem hoz létre
  drift-et a fejlesztői és a production build között.

## 3. Scope

**Benne:**

- **`.github/workflows/backend-ci.yml`** (ÚJ): checkout → Python 3.12 setup →
  `pip install -r requirements.txt -r requirements-dev.txt` → külön lépésekben:
  `python -m ruff check app tests` · `python -m ruff format --check app tests` ·
  `python -m pytest -q` · `alembic upgrade head` (ideiglenes, izolált DB-URL-lel).
  Trigger: `workflow_dispatch` + push a `backend/**` és a workflow-fájl pathra.
- **`backend/requirements.txt`** (prod: fastapi, uvicorn, SQLAlchemy, pydantic*,
  email-validator, PyJWT, bcrypt, python-multipart, alembic) +
  **`backend/requirements-dev.txt`** (ÚJ: pytest, httpx, ruff).
- **Ruff bevezetése:** `backend/pyproject.toml` (ruff szekció, line-length és
  szabálykészlet a meglévő kódstílushoz igazítva) + a kód **egyszeri, viselkedés-
  azonos** formázása külön committal, hogy zöld legyen a `--check`.
- **Python-verzió rögzítése:** 3.12 a CI-ben + `backend/README.md`-ben.
- **`assets/ml/model_manifest.json`** (ÚJ) — modellenként: fájlnév, SHA-256,
  formátumverzió, input shape, output classes, training-run / model-card
  azonosító, export-script verzió, létrehozás dátuma.
- **`ml/make_manifest.py`** (ÚJ): a manifest generátora (a kézzel szerkesztett
  checksum tilos — a scriptet futtatjuk újra modellcserénél).
- **`test/tooling/ml_asset_manifest_test.dart`** (ÚJ): minden pubspec-deklarált
  `assets/ml/*.bin`-nek van manifest-bejegyzése, a SHA-256 egyezik, a manifest
  nem tartalmaz nem-létező fájlt. Mivel a `flutter test` a CI-gate része, a
  checksum-gate ezzel automatikusan a merge-bar része.
  **A teszt NEM lehet vákuumban zöld** (R14-review MINOR-1): a manifest a
  **névvel nevezett alsó korlát** — a négy bejegyzésből kiindulva állítja, hogy a
  fájl létezik, a checksum egyezik ÉS a `pubspec.yaml` deklarálja. Így a pubspec
  `assets:` blokkjának törlése/elgépelése is PIROS, nem némán zöld.
- Modellcsere-szabály (SDD 15.6) gépi része: a manifest-teszt miatt bináris nem
  cserélhető manifest-frissítés nélkül. (A model-card/honest-eval kötelezettség
  dokumentálása Claude-oldali — ADR/execution-doksi, nem e kör kódja.)

**Kívül (ebben a körben TILOS):**

- Training workflow-k átalakítása (`chord-train.yml`, `ml-train.yml`, `dsp-probe.yml`).
- Új modell tanítása/cseréje; bármely `.bin` tartalmának módosítása.
- Backend viselkedésváltozás — a Ruff-formázáson túl `backend/app/**` logika nem
  változhat (a formázó-commit diffje csak whitespace/idézőjel/importrend lehet).
- Postgres bevezetése a CI-be (SQLite teszt-DB elég — a §12.4 prod-szabálya nem CI-kérdés).
- `build-apk.yml` **és `release-apk.yml`** módosítása (R14 területe — az ML-manifest
  teszt magától bekerül mindkettő `flutter test` lépése alá).
- `tool/ci/check_assets.dart` módosítása — az R14-review MINOR-1-et a manifest-teszt
  zárja le (§5.7), nem a meglévő gate átírása („egy gate-hely, egy igazság").
- **Az R14-review MINOR-2 (gate-sor duplikáció → composite action) és MINOR-3
  (CI-idő 11m → coverage külön jobba)** — mindkettő a lezárt APK-workflow-fájlokat
  írná át, ezért **E01-R16**, lásd §12.

## 4. Engedélyezett fájlok

Csak az alábbi útvonalak módosíthatók. Bármi más → **MEGÁLLÁS és jelentés**.

| Útvonal | Miért |
|---|---|
| `.github/workflows/backend-ci.yml` | ÚJ — backend minőségkapu |
| `backend/requirements.txt` | prod-dependencyk (dev kikerül) |
| `backend/requirements-dev.txt` | ÚJ — pytest, httpx, ruff |
| `backend/pyproject.toml` | ÚJ — ruff konfiguráció |
| `backend/app/**`, `backend/tests/**` | CSAK a Ruff-formázás diffje (külön commit) |
| `backend/README.md` | Python-verzió, CI, requirements-használat |
| `assets/ml/model_manifest.json` | ÚJ — asset manifest |
| `ml/make_manifest.py` | ÚJ — manifest-generátor |
| `test/tooling/ml_asset_manifest_test.dart` | ÚJ — checksum guard |
| `docs/rounds/e01-r15-backend-and-ml-ci.md` | **csak a 10. szekció** |

**Tilos zóna:** `lib/**`, `test/**` (a fenti egy új tesztfájlon kívül),
`assets/ml/*.bin`, `pubspec.yaml`, `tool/**` (beleértve `tool/ci/check_assets.dart`),
`.github/workflows/{build-apk,release-apk,lab-apk,chord-train,ml-train,dsp-probe}.yml`,
`ml/**` (a fenti egy új scripten kívül), `docs/**` (a fenti fájl §10-én kívül),
`HANDOFF.md`, ADR-ek, `backend/alembic/**`, `backend/pytest.ini`.

> A `backend/pytest.ini` és a `backend/alembic/**` szándékosan zárt: ha a Ruff-konfig
> vagy a CI működéséhez elkerülhetetlen a módosításuk, az **MEGÁLLÁS és jelentés**
> (dokumentált brief-revízió), nem csendes scope-tágítás.

## 5. Kötött architekturális döntések

Előre kiosztott ADR-szám: **`0063`** — az ADR-t Claude írja.

1. **A manifest generált, nem kézzel írt.** `ml/make_manifest.py` állítja elő;
   a guard-teszt a fájl ellen méri a valóságot. Modellcserénél a script
   újrafuttatása kötelező — kézi checksum-szerkesztés review-ban elutasítandó.
2. **A checksum-gate a `flutter test`-en át érvényesül** (test/tooling minta —
   ugyanaz az elv, mint a legacy-identifier és a dio-factory guard), NEM külön
   workflow-lépésként: egy gate-hely, egy igazság.
3. **Ismeretlen eredetű legacy modellnél** a training-run mező `origin:
   pre-manifest` értéket kap a rekonstruálhatatlanság explicit jelzésére —
   kitalált run-azonosító tilos; a checksum/shape/classes viszont MÉRT érték,
   ott placeholder nincs.
4. **Ruff-formázás viselkedés-azonos és külön committal** megy (az R02
   formatter-migráció mintája): a review a logikai diffet a formázástól
   elválasztva látja.
5. **Python 3.12** az egységes verzió (a box venvje ez); a training workflow-k
   3.11-e NEM változik e körben (más toolchain, más kör dolga, ha egyáltalán).
6. **A backend-CI teszt-DB-je izolált** (temp SQLite URL env-ből) — a repo-fába
   CI-futás nem írhat DB-fájlt.
7. **A manifest a névvel nevezett alsó korlát** (ez zárja le az R14-review
   MINOR-1-jét): a guard-teszt a manifest bejegyzéseiből indul (nem a pubspec
   deklarációiból), így üres/hiányos pubspec `assets:` blokkon PIROS. A meglévő
   `tool/ci/check_assets.dart` érintetlen marad.
8. **A Ruff scope-ja `app` + `tests`** — a `backend/alembic/**` (generált env.py +
   migrációk) és a `.venv` **kimarad** (a pyproject `exclude`-ja is ezt tükrözze),
   így a migrációs fájlok stílusa nem lesz a CI függvénye.

## 6. Acceptance criteria

- [ ] A kör-branchen dispatchelt `backend-ci.yml` ZÖLD: ruff check + format-check
      + pytest + `alembic upgrade head` mind külön lépésben.
- [ ] Bizonyított piros út: (a) egy szándékos Ruff-sértés, (b) egy kézzel
      elrontott bájt az egyik `.bin`-ben, és (c) **egy eldobható fixture-ön a
      pubspec `assets:` blokk ML-bejegyzésének törlése** (MINOR-1 non-vakuitás)
      → a megfelelő gate piros (futás-link / lokális tesztkimenet a §10-ben),
      majd mindhárom visszavonva, `git status` tiszta.
- [ ] `assets/ml/model_manifest.json` mind a 4 bin-t fedi, minden kötelező
      mezővel; `python ml/make_manifest.py` idempotens (újrafuttatva üres diff).
- [ ] `flutter test test/tooling` zöld, benne az új manifest-teszt.
- [ ] `pip install -r requirements.txt` (dev-fájl nélkül) elegendő a backend
      FUTTATÁSÁHOZ (uvicorn boot smoke — a §10-ben dokumentálva).
- [ ] A Ruff-formázó commit diffje nem tartalmaz logikai változást (review-állítás).
- [ ] Mind a meglévő backend- és Flutter-teszt zöld — a backend baseline
      **64 passed** (R13), a kör után ennél kevesebb nem lehet; `git diff --stat main...`
      csak a §4 tábláját tartalmazza.

## 7. Kötelező ellenőrzések

Külön parancsokként (`AGENTS.md` §12):

```bash
cd backend
python -m ruff check app tests
python -m ruff format --check app tests
python -m pytest -q
```

```bash
python ml/make_manifest.py
~/flutter/bin/flutter test test/tooling
~/flutter/bin/dart format --output=none --set-exit-if-changed test
~/flutter/bin/flutter analyze test/
```

A workflow-dispatchek (backend-ci a kör-branchre + a szokásos build-apk gate)
**Claude-oldal** (ADR 0052) — a Codex ne hívjon `gh`-t.

## 8. Implementációs sorrend

1. `requirements` szétválasztás + `pyproject.toml` (ruff-konfig).
2. Ruff-formázás KÜLÖN commitban (check + format zöldre lokálisan).
3. `backend-ci.yml` megírása (izolált DB-URL-lel az alembic-lépéshez).
4. `ml/make_manifest.py` + `assets/ml/model_manifest.json` generálása.
5. `test/tooling/ml_asset_manifest_test.dart` + valódi-sértés próba
   (bin-bájt elrontása → piros → visszaállítás).
6. README (Python 3.12, CI, requirements) → §10 kitöltése.

## 9. Kockázatok

- **A Ruff-diff mérete.** Ha a formázó nagy diffet ad, a külön commit kötelező
  (5.4) — nélküle a review nem tudja szétválasztani a logikát a whitespace-től.
- **R12-függés.** `alembic upgrade head` R12 nélkül nem létezik — a kör NEM
  indítható az R12 merge-je előtt.
- **Manifest-metaadat felkutatása.** A 3 strum-bin training-run azonosítója a
  `ml/` történetéből nem biztosan rekonstruálható — ilyenkor a `pre-manifest`
  jelölés a helyes (5.3), NEM a kutatásba fulladás: a kör értéke a checksum-gate.
- **Bináris fájl olvasása Dart-tesztből.** A tesztek CWD-je a repo-gyökér —
  az asset-elérési utat ehhez kell kötni (a meglévő parity-tesztek mintája),
  különben CI-n másik CWD-vel hasal.
- **`ml/make_manifest.py` és a dátummező.** Az idempotencia-követelmény miatt a
  `created_at` csak akkor frissülhet, ha a checksum változott — különben minden
  futás diffet ad.

## 10. Implementation handoff — a Codex tölti ki

- Fájlonkénti összefoglaló.
- Futtatott parancsok + TÉNYLEGES kimenet.
- A piros-út bizonyítékok (ruff-sértés, bin-rontás) kimenete.
- Eltérések a tervtől és okuk.
- Nem futtatott ellenőrzések és okuk (várhatóan: a CI-dispatchek — Claude-oldal).
- Follow-up issue-k.

## 11. Review — a Claude tölti ki

Link: `docs/reviews/e01-r15-review.md`

## 12. Az R14-review MINOR-jainak kezelése (pre-flight döntés, 2026-07-30)

A `docs/reviews/e01-r14-review.md` három MINOR-t adott át „E01-R15/R16" jelöléssel.
A szétosztás:

| MINOR | Tartalom | Hova | Miért |
|---|---|---|---|
| **MINOR-1** | az asset-gate üres deklarációs halmazon némán zöld | **EBBE a körbe** | a checksum-manifest természeténél fogva alsó korlát; a §3 + §5.7 + §6 piros-út (c) pontja zárja le — a `check_assets.dart` érintése nélkül |
| **MINOR-2** | a gate-sor duplikálva `build-apk.yml` ↔ `release-apk.yml` (drift-kockázat) | **E01-R16** | composite action / `workflow_call` refaktor a **lezárt** APK-workflow-fájlokban; e kör nem hoz drift-et, mert a manifest-teszt a közös `flutter test` alatt fut |
| **MINOR-3** | a CI-idő 9m → 11m (coverage), küszöb fölött | **E01-R16** | ugyanazok a lezárt fájlok; e kör backend-CI-je **külön workflow**, tehát a Flutter-gate kritikus útját nem növeli |

**Tervezői önkötés (E01-R14 tanulsága):** az engedélyezett-fájllista a briefírót is
köti — nem írható elő olyan kötelező változás, amelynek a fájlja a §4-ben zárt.
Ezért a MINOR-2/3 itt kifejezetten **nem** acceptance criteria, hanem az R16
pre-flightjának bemenete.
