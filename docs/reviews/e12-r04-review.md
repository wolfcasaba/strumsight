# E12-R04 — kör-review (ADR 0055)

- **Kör:** `E12-R04` — Environment és channel konfiguráció lezárása
- **Branch:** `sonnet-impl/e12-r04-environment-and-channel-isolation`
- **PR:** [#488](https://github.com/wolfcasaba/strumsight/pull/488)
- **Implementer motor:** `sonnet-impl` (Claude Sonnet 5, `--effort high`)
- **Reviewer:** Claude (Opus 5, orchestrátor) + `security-reviewer` ügynök
  (KÖTELEZŐ, mert a brief `risk = "high"`)
- **Review-alap:** `05eadcfbb290..4b066a8d` (7 fájl), majd a javító kör
- **Dátum:** 2026-08-28

## 1. Scope-audit

`scope_audit=ok` (`scope_audit_base=05eadcfbb290`, `scope_audit_changed=7`) — a
gépi audit a brief `allowed_paths` blokkja ellen futott le a wrapperben.

A 7 megváltozott fájl mind az engedélyezett listán van:

| Fájl | |
|---|---|
| `backend/app/config.py` | zárt `env` értékkészlet + alias + staging-őr |
| `backend/tests/test_settings.py` | A1–A4 cellák ÚJ osztályokban |
| `lib/app/config/app_config.dart` | feltétlen staging-host tiltás |
| `lib/app/config/app_environment.dart` | doc-comment + alias-tábla |
| `test/app/app_config_test.dart` | A5 cellák bővítése |
| `docs/release/environment-matrix.md` | ÚJ |
| `docs/rounds/e12-r04-…md` | §10 |

A tilos zóna érintetlen: a `git diff --name-only` egyetlen sora sem esik
`backend/app/main.py`, `backend/app/community/**`,
`backend/tests/test_hardening.py`, `backend/alembic/**`, `lib/app/routing/**`,
`.github/**`, `docs/adr/**` vagy `tools/**` alá.

## 2. Az első kör leletei

### BLOCKER B1 — az ÚJ validátorok titkot szivárogtatnak a hibaüzenetbe

**Fájl:sor:** `backend/app/config.py:128-133` (`mode="before"` validátor
`raise ValueError`) és `:142-173` (`_guard_staging` négy `raise ValueError`-ja).
**Sértett szabály:** AGENTS.md §5 / 3. nem tárgyalható határ (titok nem kerülhet
hibaüzenetbe vagy logba).

Az `security-reviewer` jelentette, és az orchestrátor **külön, saját méréssel
reprodukálta** a munkapéldányon (`4b066a8d`):

```
$ SK="9f3c1a7be24d05f8a1b6c0d3e7f2a894"                        # strumsight:allow-secret kitalált 32-hex canary, csak a szivárgás-reprodukcióhoz
$ DB="postgresql+psycopg://app:Pg-Pa55w0rd@db.internal/ss"     # strumsight:allow-secret kitalált DB-jelszó, csak a szivárgás-reprodukcióhoz
$ cd backend && env -i PATH=/usr/bin:/bin HOME=/home/ubuntu \
    STRUMSIGHT_ENV="Prod-uction" \
    STRUMSIGHT_SECRET_KEY="$SK" \
    STRUMSIGHT_DATABASE_URL="$DB" \
    python -c "from app.config import Settings; Settings()"

1 validation error for Settings
  Value error, STRUMSIGHT_ENV='Prod-uction' is not a recognized environment
  (expected one of ['dev', 'lab', 'prod', 'staging'], or the aliases
  development/production).
  [type=value_error, input_value={'env': 'Prod-uction', 's...a55w0rd@db.internal/ss'},
   input_type=dict]
```

A DB-jelszó (`Pg-Pa55w0rd`) és a belső DB-host szó szerint megjelenik. A pydantic
model-szintű validátorból dobott hiba `input_value`-ja a TELJES settings-szótár,
fej ~25 + tail ~22 karakterre csonkolva — a tail-ablak a deklarációs sorrendben
utolsó beállított mezőre esik (rutinszerűen `secret_key`, `database_url` vagy
`tutor_api_key`). A sink valós: a `backend/app/main.py:221` modul-szinten hívja a
`create_app()`-ot, tehát a hiba uvicorn/gunicorn import-time tracebackként a
boot-logba kerül.

**Ezt a kör vezette be:** a base (`git show 05eadcfbb290:backend/app/config.py`)
egyetlen model-szintű validátora sem dobott, a mező-szintű hibák `input_value`-ja
pedig csak az adott mező értékére terjed ki.

### MAJOR B2 — a staging-őr elfogadja az ÜRES `secret_key`-t

`backend/app/config.py:151-155` csak az egyenlőséget nézi
(`self.secret_key == dev_secret`), miközben a közvetlenül alatta lévő
`diag_token` ág (`:161-167`) `.strip()`-pel az ürest is fogja. Mérve:

```python
Settings(env="staging", secret_key="",
         cors_origins=["https://staging.strumsight.app"],
         allow_sqlite_in_prod=True)   # → példányosul
```

Üres HS256 aláíró kulccsal a JWT triviálisan hamisítható. A `_guard_prod`
(`backend/app/main.py:41`) ugyanezt a rést hordozza, de az **tilos zóna** — a
production-oldali szigorítás az `E12-R07` köré tartozik; a kör SAJÁT, új őrét
viszont javítani kell.

### MINOR B3 — a staging-őr nem fedi a tutor provider-kulcsot

`backend/app/config.py:142-173` négy ellenőrzést végez, a production-őr
(`backend/app/main.py:63-69`) ötödikként a `tutor_enabled` + dev/üres
`tutor_api_key` esetet is elutasítja. Az `ADR 0445 D4` taxatív listája négy
ellenőrzést ír elő, tehát a KÓD ADR-konform — a lelet dokumentációs: az
`environment-matrix.md` ne olvastassa erősebbnek a staging-őrt, mint amilyen.

### MINOR B4 — a validátor átnevezése doksi-drift merge-elt ADR-rel

A `_default_lab_flags_for_environment` → `_normalize_environment_and_default_lab_flags`
átnevezés után négy MERGE-ELT dokumentum (`docs/adr/0395-…md:47,114`,
`docs/baseline/epic-09-community-start.md:144,169`,
`docs/security/community-threat-model.md:379`, `docs/rounds/e09-r01-…md:71`)
nem létező szimbólumnevet hivatkozik. A fájlok tilos zónában vannak, tehát a
javítás a kód doc-commentjében történik (a korábbi név kimondása), nem
visszanevezéssel.

### NOTE (nem javítandó, tudatosan)

- A `mode="before"` validátor nem-dict bemenetre kihagyja az értékkészlet-
  ellenőrzést (`Settings.model_validate(Settings.model_construct(env="qa"))`) —
  a repóban nincs ilyen hívóhely, latens.
- A kliens `staging` részlánc-tiltása heurisztika (`stg.`, `pre-prod.` átmegy) —
  az `ADR 0445 D5` ezt explicit vállalja.

## 3. Amit a review MÉRT és rendben talált

| Ellenőrzés | Eredmény |
|---|---|
| Csendes visszaesés az env-normalizálásban (`getattr(...,"dev")`, `or "dev"`, `try/except`) | **NINCS** — az ismeretlen érték `raise ValueError` (`config.py:128-133`); mérve `"qa"`, `"prod uction"`, `"PRODUCTION!"`, `"Prod-uction"` |
| `_guard_prod` szerződése regresszió-mentes | **IGEN** — `_guard_staging` első utasítása `if self.env != "staging": return self`; `Settings(env="prod", cors_origins=["*"])` példányosul, a hiba a `create_app()`-on keletkezik |
| A kliens `resolve()` fail-closed ágai megmaradtak | **IGEN** — `git diff -- lib/app/config/app_config.dart \| grep "^-[^-]"` pontosan 2 törölt sort ad, mindkettő doc-comment; a HTTPS-, loopback-, dev-token- és Lab-mód-tiltás a helyén |
| A staging titok-tiltás a repóbeli dev-alapértelmezéseket fogja, `model_fields`-ből | **IGEN** — `type(self).model_fields["secret_key"].default`, nincs újra beírt literál (a `main.py:29-31` mintája) |
| A staging-host tiltás feltétlen productionben, és nem sül el lab/development alatt | **IGEN** — önálló `if` az `else if (isProd)` ágban (`app_config.dart:153`); az `AppEnvironment` enum nem bővült |
| A `prod` literál nem lett átnevezve (§0.0 R1) | **IGEN** — a `main.py:39,114` és `community/__init__.py:93` fogyasztók változatlanok |
| A zárt értékkészlet nem tör el meglévő fogyasztót | **IGEN** — a `backend/` fában előforduló `env=` értékek: `prod` (18), `staging` (5), `dev` (4), `production` (1), `"STAGING "` (1) — mind érvényes a normalizálás után |
| Meglévő teszt törlése / `skip`-je / gyengítése | **NINCS** — a `test_settings.py` diffje tisztán additív, a `test_hardening.py` nincs a diffben |

## 4. A javító kör

A B1–B4 leletlistával ugyanaz a motor (`sonnet-impl`) kapta vissza a kört
(a `docs/reviews/**` nem az implementer scope-ja; a leletek a
`/tmp/round-prompt-e12-r04-fix.md` promptban mentek át).

A javító kör implementer-futása a `sonnet-impl` motor **3600 s abszolút
időkorlátjába** futott bele (`status=timeout`, `head=4b066a8d`,
`dirty_files=3`, `gate_shape=ok`, `scope_audit=ok`,
`scope_audit_changed=3`) — a kód-munka ekkorra elkészült, de commitolatlanul
állt a munkapéldányban. Ez a motor EGY halála `stalled/timeout` állapotban,
tehát nem H6 (az H6 küszöbe kettő).

Az orchestrátor ezért NEM indított új implementer-futást: a scope-auditált
diffet átnézte, a mérce-próbákat **maga futtatta le** (alább, §5), és a munkát
a `8e832a21` commitban rögzítette, a mért bizonyítékokat pedig a brief
§10.5-ébe. A mérce nem gyengült — minden szám egy ténylegesen futtatott parancs
kimenete, és ugyanez a HEAD megy végig a teljes CI-kapun.

## 5. Újramérés a javító kör után (`0b9c52e7`)

### 5.1 B1 lezárva — a titok-szivárgás megszűnt

`backend/app/config.py:30` — `hide_input_in_errors=True` a
`SettingsConfigDict`-ben. Az orchestrátor SAJÁT reprodukciója, ugyanazzal a
paranccsal, ami a §2-ben a DB-jelszót kiszivárogtatta:

```
1 validation error for Settings
  Value error, STRUMSIGHT_ENV='Prod-uction' is not a recognized environment
  (...). [type=value_error]
LEAK secret_fragment: False | LEAK db_password: False
```

Az üzenet SZÖVEGE változatlan, tehát a `pytest.raises(..., match=...)` cellák
zöldek maradtak.

**Falszifikációs próba (EXACT-RED, az orchestrátor futtatta):** a
`hide_input_in_errors=True` sor ideiglenes eltávolítása után

```
$ cd backend && python -m pytest tests/test_settings.py -q -p no:randomly
FAILED …::TestSecretsNeverLeakIntoErrors::test_unknown_env_error_does_not_leak_secret_key
FAILED …::TestSecretsNeverLeakIntoErrors::test_unknown_env_error_does_not_leak_database_url
FAILED …::TestSecretsNeverLeakIntoErrors::test_staging_guard_error_does_not_leak_database_url
```

mindhárom új őr-cella pirosra váltott → a sor visszaállítva. Az őr tehát valódi
regresszió-őr, nem tautológia.

### 5.2 B2 lezárva

`backend/app/config.py:161` — `if not self.secret_key.strip() or self.secret_key == dev_secret:`.
Falszifikációs próba (a `.strip()`-es rész ideiglenes visszavétele):

```
FAILED …::TestStagingIsolation::test_empty_or_blank_secret_key_refuses_to_instantiate[]
FAILED …::TestStagingIsolation::test_empty_or_blank_secret_key_refuses_to_instantiate[   ]
```

→ visszaállítva.

### 5.3 B3 és B4 lezárva

- B3: `docs/release/environment-matrix.md` 1. táblázata új
  „Tutor provider-kulcs (`tutor_api_key`)" sort kapott, plusz a §2 kimondja,
  hogy a staging-őr négy, a production-őr öt ellenőrzést végez, és hogy a
  staging-őr NEM olvasható a production-őr azonos szintű megfelelőjeként
  (E12-R07 hatáskör).
- B4: a `_normalize_environment_and_default_lab_flags` doc-commentje kimondja a
  korábbi nevet (`_default_lab_flags_for_environment`) és azt, hogy az ADR 0395
  és a community-threat-model erre hivatkozik — a grep-elhetőség helyreállt.

### 5.4 Új NOTE a javításból

A `hide_input_in_errors=True` a `str(exc)` alakot redaktálja, de a
pydantic-core `ValidationError.errors()` `include_input` paraméterének
alapértéke `True` marad, tehát a **strukturált** alak továbbra is tartalmazza a
bemeneti szótárat. Az implementer ezt a tesztek docstringjében kimondja, és a
`grep -rn "\.errors(" app/` alapján a repóban nincs olyan in-scope hívó, amely a
`Settings` `ValidationError`-ját `errors()`-szel szerializálná. A valós sink (a
boot-log traceback) tehát zárva van; a strukturált út latens marad —
felvéve az E12-R07 kör kontextusába.

### 5.5 Gate-ek és CI

| Mérce | Eredmény |
|---|---|
| `tools/round-gate.sh test/app/app_config_test.dart test/app/config/feature_flags_test.dart` (implementer, első kör, `4b066a8d`) | MINDEN GATE ZÖLD |
| `cd backend && python -m ruff check app tests` (orchestrátor, javítás után) | `All checks passed!` |
| `cd backend && python -m ruff format --check app tests` | `131 files already formatted` |
| `cd backend && python -m pytest tests -q` (teljes suite, javítás után) | zöld |
| Full Gate (no APK), Backend CI, Router CI a merge SHA-n | lásd §6 |

## 6. Végső döntés

**APPROVED** — a B1 (BLOCKER), B2 (MAJOR), B3 és B4 (MINOR) leletek lezárva,
mindkét blokkoló javítás mögött falszifikációval igazolt gépi őr áll. Nyitott
BLOCKER/MAJOR nincs. A merge feltétele változatlanul a teljes zöld kapu a merge
SHA-n (Full Gate + Backend CI + Router CI).
