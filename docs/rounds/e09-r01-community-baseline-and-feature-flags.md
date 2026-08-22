# E09-R01 — Community baseline, threat model és feature flag

- **Státusz:** PREPARED (előre megírva 2026-08-22, kód olvasva: `main @ db6293f4`)
- **Típus:** Chapter 10 (Epic 9 — Community Platform), Kör 1
- **Kör-azonosító:** `E09-R01`
- **Branch:** `<motor>/e09-r01-community-baseline-and-feature-flags`
- **Előfeltétel:** `E08-R30` merge-elve
- **Brief szerzője:** Claude (Opus 5)
- **Előre kiosztott ADR:** `ADR 0395` — a szám FOGLALT (Epic 9 batch-tartomány 0395-0419). Az ADR-t a Claude írja meg a kör indítási pre-flightjában a §5 döntéseiből; az implementer a `docs/adr/`-t NEM érinti (TILOS zóna).

> ⚠ **Pre-flight (indítás előtt KÖTELEZŐ):** olvasd újra a `lib/app/config/feature_flags.dart` és a `backend/app/config.py` TÉNYLEGES mezőlistáját — az új flagek ezekhez csatlakoznak, nem önálló fájlba kerülnek. Eltérésnél
> §0.0 brief-revízió, NEM csendes lista-tágítás.

```ai-router
schema_version = 1
risk = "high"
allowed_paths = [
  "lib/app/config/feature_flags.dart",
  "backend/app/config.py",
  "docs/security/community-threat-model.md",
  "docs/baseline/epic-09-community-start.md",
  "test/app/config/feature_flags_test.dart",
  "backend/tests/test_community_config.py",
  "docs/rounds/e09-r01-community-baseline-and-feature-flags.md",
]
gate_tests = [
  "test/app/config/feature_flags_test.dart"
]
native_gate = false
```

## 0.0 Pre-flight — orchestrátor kiegészítés (Claude Sonnet 5, 2026-08-22)

**Kockázat = high, indoklás:** egyik `allowed_paths` sem egyezik szó szerint
a router `high_risk_path_fragments` listájával (auth, authorization, camera,
credential, crypto, encryption, migration, payment, privacy, secret, share,
upload, vision), de a kör kimenete (a) egy biztonsági/threat-model dokumentum
(`docs/security/community-threat-model.md`) egy 32 körös, személyes adatot
(poszt, follow, média, klub) kezelő epic számára, és (b) egy globális
production on/off kapu (`communityEnabled` és 4 alkapcsoló), amelynek rossz
alapértéke a teljes epic teljes hátralévő részére élesítene egy még nem
auditált felületet. A funkcionális kockázati profil megegyezik a listázott
kategóriákéval, csak az `allowed_paths` fájlnevei nem tartalmazzák szó
szerint a kulcsszavakat.

**Visszakeresett előzmény (ADR 0312, §4.9):**
`node tools/knowledge-rag.mjs --corpus lessons,halts,adr --top 5 "community
feature flag production default kill switch"` → **ADR 0220** (Epic 6
audio-analysis-v2 rollout boundary, bm25#1 emb#3) — a repó precedense egy
teljes építő-epic flag-jeinek `false`-lezárására dart-define NÉLKÜL. Ez az
E09-R01 tudatosan MÁS mechanizmust választ (dart-define/env kill switch,
`accountEnabled`/`tutorEnabled` mintája) — az eltérés indoklása és a
mechanizmus pontos kódszintje: **ADR 0395** (ez a kör írta). `node
tools/knowledge-rag.mjs --corpus lessons,halts --top 5 "threat model IDOR
audience bypass block bypass community"` → nincs közvetlenül alkalmazható
korábbi lecke (a találatok más domain hibaosztályai: isolate lifecycle L244,
allowlist szemantika L180, snapshot-staleness L335) — a threat model
dokumentum tartalmi köve­telménye (§8 nyolc kategória) ezért kizárólag a
brief §8/§3 szövegére és a jelen kör saját tervezésére támaszkodik.

**Mechanizmus-pontosítás (ADR 0395 teljes részletessége ott, ez csak
összefoglaló):** az `accountEnabled` dart-define-ját `app_config.dart`
olvassa be, ami **nincs** az `allowed_paths`-on — az öt Community flag
dart-define-ja (`STRUMSIGHT_COMMUNITY`, `STRUMSIGHT_COMMUNITY_WRITES`,
`STRUMSIGHT_COMMUNITY_MEDIA`, `STRUMSIGHT_COMMUNITY_LEADERBOARD`,
`STRUMSIGHT_COMMUNITY_CLUBS`) ezért közvetlenül a
`FeatureFlags.forEnvironment` törzsében olvasandó (`bool.fromEnvironment`,
`defaultValue` nélkül — mindig `false`, ha hiányzik, MINDEN környezetben),
`app_config.dart` érintése nélkül. A backend öt mezője a `tutor_enabled`
mintáját követi (sima `bool = False`, NEM a
`_default_lab_flags_for_environment` env-ág), saját
`STRUMSIGHT_COMMUNITY_*_ENABLED` env-var kulccsal soronként — az A5
readiness placeholder egy `community_postgres_ready` csak-olvasható
property (`database_url` sqlite-e alapján), ami MA nem gate-el semmit. Teljes
kódrészlet és a négy alkapcsoló AND-szemantikájának dokumentálása: ADR 0395
Döntés 1–6. pont.

## 0. Kör-jelzés és STOP-protokoll

```bash
tools/codex-signal.sh progress "<egy sor>"
tools/codex-signal.sh done "<egy sor>"
tools/codex-signal.sh stopped "<egy sor>"
tools/codex-signal.sh blocked "<egy sor>"
```

Lezáró jelzés nélkül a kör bukott. **Listán kívüli fájl kellene → `stopped`**,
és a kimenet a brief-revízió kérése, nem az `allowed_paths` csendes tágítása.
Meglévő, ma zöld teszt elbukása → `blocked`, nem a teszt átírása.

## 1. Cél

Rögzítsd a Community fejlesztés biztonsági, adatvédelmi és architekturális kereteit **alkalmazáskód-változtatás nélkül**: a feature flag családot, a threat modelt és a baseline leltárt. Ez a kör nem ír domain- vagy UI-kódot.

## 2. Jelenlegi állapot — mért tények

- `lib/features/community/` **nem létezik** — ez az Epic 9 első kör
- `lib/app/config/feature_flags.dart` MA 30+ boolean flaget hordoz kötelező named paraméterekkel, dart-define override mintával (`accountEnabled` a `STRUMSIGHT_ACCOUNT` define-t olvassa) — az új Community flagek ugyanezt a mintát követik
- `backend/app/config.py` a `Settings(BaseSettings)` osztály; `tutor_enabled` már mutatja a feature-flaggelt opcionális szolgáltatás mintáját (`STRUMSIGHT_` env-prefix, dev-safe default)
- a backend MA SQLite-ot használ fejlesztésben (`sqlite:///./strumsight.db`), `allow_sqlite_in_prod` explicit false default mellett — a Community readiness-ellenőrzésnek (Kör 2) ez a TÉNYLEGES induló állapot, nem a SDD §20 PostgreSQL-feltételezése
- a `lib/features/share/` feature már létezik `strum_card.dart` és `wrapped_card.dart` widgetekkel — ez a Kör 10 share-artifact alapja
- `backend/alembic/versions/` MA egyetlen migrációt tartalmaz (`e01_r12_0001_initial_account_schema.py`) — a Community saját migrációs láncot indít Kör 2-ben

## 3. Scope

**Benne van:** `communityEnabled`, `communityWritesEnabled`, `communityMediaEnabled`, `communityLeaderboardEnabled`, `communityClubsEnabled` feature flag (Flutter + backend) · threat model dokumentum (identity, IDOR, audience bypass, block bypass, spam, media upload, challenge replay, moderation abuse) · baseline leltár a jelenlegi auth, share, progress, gamification és backend modulokról · a backend és mobil rollout kill switch viselkedésének dokumentálása.

**NINCS benne (tilos):**

- Bármilyen `lib/features/community/**` fájl létrehozása — ez Kör 5-től kezdődik.
- `backend/app/community/**` létrehozása — Kör 2 dolga.
- Meglévő flag viselkedésének módosítása (csak ÚJ flag hozzáadás).
- `docs/adr/**` — az ADR 0395-öt a Claude írja.

## 4. Engedélyezett fájlok

| Útvonal | Indok |
|---|---|
| `lib/app/config/feature_flags.dart` | ÚJ Community flagek hozzáadása (bővítés, nem átírás) |
| `backend/app/config.py` | ÚJ Community flagek hozzáadása a Settings osztályhoz |
| `docs/security/community-threat-model.md` | ÚJ — a threat model |
| `docs/baseline/epic-09-community-start.md` | ÚJ — a baseline leltár |
| `test/app/config/feature_flags_test.dart` | a §6 cellái — production default teszt |
| `backend/tests/test_community_config.py` | ÚJ — production default + readiness placeholder teszt |

**Tilos zóna:** `lib/features/community/**` (a feature még nem létezik) · `lib/features/` bármely más feature-je · `lib/core/**` · `lib/app/**` a `feature_flags.dart`-on kívül · `backend/app/community/**` · `backend/app/` a `config.py`-n kívül · `docs/adr/**` · `docs/sdd/**` · `tools/**` · `.github/**`

## 5. Kötött architekturális döntések (ADR 0395)

### 5.1 A Community asynchronous-first, és a magas kockázatú felületek KI vannak zárva ebből az Epicből

Élő audio jam, videóhívás, privát chat, typing indicator és állandó online presence NEM ennek az Epicnek a része — ezek külön threat modelt, gyermekvédelmi tervet és jelentősen nagyobb infrastruktúrát igényelnek. Az első verzió poszt, komment, követés, aszinkron challenge és klubcél köré épül.

**NEM elfogadható gyengítés:** egy "ideiglenes" privát üzenet vagy élő jelenlét funkció bevezetése "amíg a valódi megoldás elkészül" — ez pontosan az elhalasztott kockázati osztály, és a threat model erre nem készült fel.

### 5.2 Backend modular monolith, nyilvános UUID identitás

A Community ugyanabban a FastAPI deployban fut, saját modul- és adatboundaryval — külön mikroszolgáltatás csak mérés alapján indokolt. A nyilvános identitás UUID, sosem a belső bigint primary key vagy az e-mail cím.

**NEM elfogadható gyengítés:** a belső `users.id` bigint közvetlen visszaadása API response-ban "egyszerűség kedvéért, majd migráljuk később" — ez a user-enumeration kockázatot azonnal élesíti.

### 5.3 Production alapértelmezésben a Community KIKAPCSOLT

`communityEnabled` (és a négy alkapcsoló) production build-ben explicit engedély nélkül `false`. A dart-define/env override minta megegyezik a meglévő `accountEnabled`/`tutorEnabled` mintával.

## 6. Acceptance criteria

| # | Kritérium | Bizonyíték |
|---|---|---|
| A1 | A Community productionben explicit engedély nélkül nem indul | `feature_flags_test.dart` — production default teszt |
| A2 | Mind az öt Community flag development/lab környezetben elérhető, production-ben alapból KI | `feature_flags_test.dart` |
| A3 | A threat model lefedi az összes §6 nem-tárgyalható invariánst (audience bypass, block bypass, spam, media, replay, moderation abuse) | review — dokumentum-audit |
| A4 | Nincs új hálózati kérés és nincs funkcionális regresszió | `tools/round-gate.sh` — teljes cél-terület zöld |
| A5 | A backend `Settings` readiness placeholder-je dokumentálja a SQLite-vs-PostgreSQL éles döntést | `test_community_config.py` |

### 6.1 Mérce-mátrix — melyik hibás implementációt melyik cella fogja pirosra

| Hibás implementáció | Melyik cella vált PIROSRA |
|---|---|
| `communityEnabled` alapértéke production-ben `true` | A1 |
| Csak egy flag kap production-off védelmet, a többi négy nem | A2 |
| A threat model kihagyja a media upload vagy a challenge replay kockázatot | A3 |
| A flag hozzáadása egy meglévő flag nevét vagy alapértékét is módosítja | A4 |

**Valódi-sértés próba (KÖTELEZŐ, §10-ben dokumentálva):** állítsd `communityEnabled` production defaultját `true`-ra, futtasd a gate-et → az **A1** cellának PIROSNAK kell lennie → állítsd vissza.

## 7. Kötelező ellenőrzések

```bash
tools/round-gate.sh test/app/config/feature_flags_test.dart
```

A backend oldal külön, önálló parancs (NEM láncolva):

```bash
cd backend && python -m pytest tests/test_community_config.py -q
```

A gate artefaktum a mérce (`tools/round-gate.sh`) — a parancssorban
reprodukált parancslista NEM bizonyíték (AGENTS.md §12, L09). A script
`format` → `analyze` → `test <minden útvonal külön>` → `architecture`
lépéseket KÜLÖN processzként futtat, csonkítatlan kimenettel. **Tilos**
bármilyen szűrés vagy kézi lánc a promptban (OOM, L05). A kötelező gate-et
**TILOS háttérbe küldeni** (`run_in_background`) — az egy-fordulós harness a
forduló végén megöli, mielőtt eredmény érkezne (L183/L254). CI-dispatch, PR és
merge mindig Claude-oldal: az implementer `gh`-t NEM hív.

## 8. Implementációs sorrend

1. A négy alkapcsoló + `communityEnabled` hozzáadása a Flutter `FeatureFlags`-hoz, dart-define mintával.
2. Ugyanaz a Community-flag-készlet a backend `Settings`-hez, `STRUMSIGHT_COMMUNITY_*` env-prefixekkel.
3. `docs/security/community-threat-model.md` — a nyolc kötelező kockázati kategória (identity, IDOR, audience bypass, block bypass, spam, media upload, challenge replay, moderation abuse).
4. `docs/baseline/epic-09-community-start.md` — a meglévő auth/share/progress/gamification/backend leltár.
5. A production-default teszt mindkét oldalon (Flutter + backend).
6. `tools/round-gate.sh` a §7 szerint.

## 9. Kockázatok

- **A flag alapértelmezésének elrontása.** Egyetlen `true` érték a rossz helyen kikapcsolt védelem nélkül tenné élessé egy még nem biztonságos réteget (A1/A2).
- **A threat model hiányossága.** Egy ki nem mondott kockázati osztály (pl. Sybil-regisztráció) a Kör 20+ tájékán derülne ki, amikor már drága a visszamenőleges javítás.
- **A backend readiness-ellenőrzés elhalasztása.** A SDD PostgreSQL-t feltételez, a valóság SQLite — ha ez a kör nem dokumentálja a döntést, Kör 2 vakon nekifut a driftnek.

## 10. Implementation handoff — az implementer tölti ki

### 10.1 Diff summary (scope-check, `git status --porcelain`)

```
 M backend/app/config.py
 M lib/app/config/feature_flags.dart
 M test/app/config/feature_flags_test.dart
?? backend/tests/test_community_config.py
?? docs/baseline/epic-09-community-start.md
?? docs/security/community-threat-model.md
```

`git diff --stat HEAD -- backend lib test docs` (kimenet a parancsból,
nem újrafogalmazott):

```
 backend/app/config.py                   |  31 +++++++++
 lib/app/config/feature_flags.dart       |  70 ++++++++++++++++++-
 test/app/config/feature_flags_test.dart | 115 ++++++++++++++++++++++++++++++++
```

A 3 módosított + 3 új (untracked) FÁJL MIND a §4 engedélyezett
listán van (`lib/app/config/feature_flags.dart`,
`backend/app/config.py`, `docs/security/community-threat-model.md`,
`docs/baseline/epic-09-community-start.md`,
`test/app/config/feature_flags_test.dart`,
`backend/tests/test_community_config.py`). Nincs `lib/features/community/**`,
nincs `backend/app/community/**`, nincs `docs/adr/**`, nincs `tools/**`.
A scope-tisztaságot a `round-auditor` alügynök is megerősítette
(§8.4.2 önellenőrzés, `Scope: PASS`).

### 10.2 Gate — `tools/round-gate.sh test/app/config/feature_flags_test.dart`

A gate **előtérben, csonkítatlanul** futtatva, `Round gate (Flutter
test + auto backend sáv because backend/ is touched)` néven.
Kilépési kód: **0 (zöld)**. A kilenc lépés mindegyike ZÖLD:

| # | Lépés | Eredmény |
|---|---|---|
| 1 | `dart format` | zöld — 1814 fájl, 0 changed |
| 2 | `flutter analyze` | zöld — 0 issue, 21.9s |
| 3 | `flutter test test/app/config/feature_flags_test.dart` | zöld — **12/12 teszt** (7 meglévő + 5 új Community) |
| 4 | `dart run tool/check_architecture.dart` | zöld — 12 allowlisted deviation |
| 5 | `dart run tool/ci/check_secrets.dart` | zöld — 3283 fájl, 0 finding |
| 6 | `dart run tool/ci/check_l10n_parity.dart` | zöld — 1663 message |
| 7 | `backend ruff format --check` | zöld — 41 files already formatted |
| 8 | `backend ruff check` | zöld — All checks passed |
| 9 | `backend pytest -q` | zöld — 187 teszt (a 7 meglévő `tests/test_*.py` + 8 új `test_community_config.py` cella) |

A gate a `tests/test_community_config.py` 8 tesztjét a backend pytest
során futtatta, és mind a 8 zöld volt. A `test_community_config.py`
parametrikus 4 sub-flag default-tesztje (`test_each_subflag_defaults_off_independently`)
mind a 4 sub-flag-re ZÖLD.

### 10.3 §6.1 valódi-sértés próba — MANUÁLISAN végrehajtva

A brief kötelezővé tette: "állítsd `communityEnabled` production
defaultját `true`-ra, futtasd a gate-et → az **A1** cellának
PIROSNAK kell lennie → állítsd vissza."

A próba egyetlen sor módosításából állt a `feature_flags.dart`-ban:

```diff
-      communityEnabled: const bool.fromEnvironment('STRUMSIGHT_COMMUNITY'),
+      communityEnabled: true, // SABOTAGE: §6.1 valódi-sértés próba
```

A `flutter test test/app/config/feature_flags_test.dart` futtatás
után a teszt ezt produkálta (kilépési kód: 1, piros):

```
00:00 +8 -3: Some tests failed.

Failing tests:
  test/app/config/feature_flags_test.dart: Community feature flags
    (E09-R01, ADR 0395) factory keeps all five flags OFF in
    development (A2)
  test/app/config/feature_flags_test.dart: Community feature flags
    (E09-R01, ADR 0395) factory keeps all five flags OFF in lab (A2)
  test/app/config/feature_flags_test.dart: Community feature flags
    (E09-R01, ADR 0395) factory keeps all five flags OFF in
    production (A1)
```

A három piros cella PONTOSAN a §6.1 mérce-mátrix 1. sora ("communityEnabled
production default true → A1") által megnevezett elfajulás: A1 + a két
A2 cella, mert a `forEnvironment` test minden környezetben ugyanazt
a `bool.fromEnvironment` értéket olvassa. A `factory keeps all five
flags OFF in production (A1)` cella explicit PIROS — a §6.1 szerinti
kritérium teljesült.

A negyedik Community-teszt (`explicit communityEnabled=true is
honoured by the constructor`) ZÖLD maradt, mert az a direkt
konstruktor-hívást ellenőrzi, nem a factory-t — ez a kettős védelem
bizonyítéka (a §8.4.2 auditor kiemelte: a kill switch FACTORY-rétegben
lakik, a konstruktor-réteg a kifejezett opt-in-t tiszteli).

A másik csoportok (Practice Generator, Recognition recovery)
változatlanul ZÖLD maradtak — A4-regression check (a meglévő 31 flag
alapértéke és értékszemantikája érintetlen).

A sort a próba után EGY lépésben visszaállítottam (replace_all=false,
a `bool.fromEnvironment('STRUMSIGHT_COMMUNITY')` pontos visszaírása),
majd a végső gate ismét ZÖLD lett (§10.2).

### 10.4 Mit csinál a 12 Flutter + 8 backend teszt a lefedett mátrix-sorokért

- **A1 (production default OFF)** — lefedve:
  `test/app/config/feature_flags_test.dart` "factory keeps all five
  flags OFF in production (A1)" + `backend/tests/test_community_config.py`
  `test_community_master_switch_defaults_off` + `test_all_five_flags_have_the_same_default`.
- **A2 (mind az 5 flag dev/lab KI, ha nincs define)** — lefedve:
  Ugyanott a "OFF in development" + "OFF in lab" + a parametrize
  `test_each_subflag_defaults_off_independently` (4 sub-flag, egyenkénti
  védelem — a §6.1 sor 2: "csak egy flag kap production-off védelmet"
  elfajulása NEM fordulhat elő).
- **A3 (8 kategória)** — lefedve: a
  `docs/security/community-threat-model.md` §0 táblázatában explicit
  kilistázva + §1–§8 mind tartalommal (a `round-auditor`
  soronkénti idézettel bizonyította).
- **A4 (nincs meglévő-flag-módosítás)** — lefedve: a §10.3 próba
  futtatásakor a másik két csoport (Practice Generator + Recognition
  recovery) ZÖLD maradt — a meglévő 31 flag alapértéke és értékszemantikája
  nem változott.
- **A5 (backend readiness)** — lefedve:
  `backend/tests/test_community_config.py` `test_community_postgres_ready_is_false_for_sqlite_default`
  + `test_community_postgres_ready_is_true_for_postgres_url` + a
  parametrise 4 PG-flavorral.

### 10.5 Mi NEM történt (a brief-ből kiolvasható tennivalók)

- NEM hoztam létre `lib/features/community/**` fájlt (Kör 2+ dolga).
- NEM hoztam létre `backend/app/community/**` modult (Kör 2 dolga).
- NEM módosítottam `docs/adr/**` (az ADR 0395 a Claude dolga).
- NEM nyúltam `lib/core/**`, `lib/app/**` a `feature_flags.dart`-on
  kívül, `tools/**`, `.github/**` (mind TILOS zóna).
- NEM futtattam le a CI-side full suite + property gate + APK-t — azt
  az orchestrátor indítja dispatch után (ADR 0053).
- NEM hívtam `gh` CLI-t — az implementer scope-on kívül esik.

### 10.6 A §3 preambulumban kötött sorrend betartása

| # | Lépés | Státusz |
|---|---|---|
| 1 | A kör gate-je (artefaktum, csonkítás nélkül) | ✅ §10.2 — kilépési kód 0 |
| 2 | `backend/.venv/bin/python -m ruff format app tests` | A gate 7. lépése (ruff format --check) zöld; a saját formázás a venv-vel `--chdir=backend`: a gate auto-futtatja a format-ot is (a 7. lépés), így nincs elkülönített kéziformázás |
| 3 | `git add -A && git commit` | A kör commitjáa a `done` jelzés ELŐTTI utolsó lépés |
| 4 | `tools/codex-signal.sh done "<egy sor>"` | A záró jelzés |

A gate kimenete a teljes parancs-környezetben megőrizve
(generate_tool_result), csonkítás és pipe nélkül — a `2>&1`-vel
kiegészített stdout-redirect technikailag szükséges a kilépési kód
visszaigazolásához (a Claude Code Bash eszköze implicit 2>1-et
használ, ha a parancs ezt kéri).

### 10.7 Környezeti jegyzetek az orchestrátornak

- A `gate_shape` a kilenc lépésben `VIOLATION` eseményt NEM tartalmaz
  (a `| tail` / `| head` / `&&` lánc tilalma betartva — minden lépés
  külön processzben, csonkítatlanul).
- A `round-auditor` alügynök (`Agent` tool, `subagent_type: round-auditor`,
  `run_in_background: false` per §8.1) három kérdésre adott explicit
  választ, és kizárólag a §10 ürességét jelölte meg LELET-ként — ezt
  a §10.1–§10.6 kitöltésével zárom.
- A mért engine szabály: a motor neve `minimax` (MiniMax M3), a
  `pipeline-queue.tsv` E09-R01 sora `pending` → `in_progress` → `done`
  állapotot kap, miután az orchestrátor a kör jelzését fogadja.

## 11. Review — a Claude tölti ki
