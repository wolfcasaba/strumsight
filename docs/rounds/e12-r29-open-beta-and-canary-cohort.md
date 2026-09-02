# E12-R29 — Open Beta és canary cohort

- **Státusz:** READY (pre-flight ÚJRAMÉRVE 2026-09-02, `main @ 16638dc6` — lásd §0.0; az előre megírt változat 2026-08-27, `main @ 9ca4a0dc`)
- **Típus:** Chapter 12 (Release Roadmap, Sprint Planning & Final Integration), Kör 29
- **Kör-azonosító:** `E12-R29`
- **Branch:** `<motor>/e12-r29-open-beta-and-canary-cohort`
- **Előfeltétel:** `E12-R28` merge-elve (a GA-scope és a befagyasztott contractok)
- **Brief szerzője:** Claude (Opus 5)
- **Előre kiosztott ADR:** nincs — a kör kapacitás- és cohort-eljárást szállít; a rate-limit és moderation szerződések már léteznek.

**Visszakeresett előzmény:** `node tools/knowledge-rag.mjs --corpus lessons,halts,adr --top 5 "open beta canary cohort rate limit moderation capacity cost"` → **[L34](../LESSONS.md#l34)** (a secret scan a megőrzött globális configra és backupra is terjedjen ki) és a `halts/round-status-E09-{18,21}` (média- és challenge-körök). A kapacitás-nézetnek tehát a MEGŐRZÖTT konfigurációra és a média-tárolásra is ki kell terjednie.

> ⚠ **Pre-flight (indítás előtt KÖTELEZŐ):** ellenőrizd a `backend/app/ratelimit.py` MÉRT korlátait és a Community moderation runbookot (`docs/operations/community-moderation-runbook.md`). A kapacitás-terv EZEKRE a mért értékekre épül.

## 0.0 Pre-flight revízió (orchestrátor, 2026-09-02, `main @ 16638dc6`)

A brief `PREPARED` állításait a fán ÚJRAMÉRTEM. Az alábbi P1–P8 a brief
KÖTELEZŐ része: ahol a mérés mást mond, mint a törzsszöveg, a **mérés** győz.
ADR nincs és nem is lesz — a §5 így dönt, és a `docs/adr/**` a tilos zónában
van (a `tools/round-slots.py reserve-adr` ezért nem futott).

**Visszakeresés (ADR 0312, szűkítve előbb):**
`--corpus lessons,halts,adr` → `halts/round-status-E12-R27`, `E12-R28`,
`adr/0489`; `--corpus lessons,halts` → **[L571](../LESSONS.md#l571)** (a
kétrétegű őr második rétege `continue`-val fail-OPEN lett),
**[L548](../LESSONS.md#l548)** (a lefedettségi cella nem mérte a lefedettség
TARTALMÁT), **[L575](../LESSONS.md#l575)** (a `- [ ]` alakra épült őr pont a
kipipáláskor némult el). Mindhárom ugyanazt mondja: **a dokumentumot mérő
cella nem ugorhat át hiányzó szakaszt** — lásd P6.

### P1 — A4 mért útvonala: a bejelentés NEM nyit magától moderációs ügyet

Mérve: `grep -n "case_service\|get_or_create_case\|ModerationCase"
backend/app/community/services/report_service.py` → **0 találat**. A
`submit_report()` sort ír a `community_reports` táblába, de moderációs ügyet
nem nyit. A sor (queue) MÉRT olvasó útvonala:

- `backend/app/community/moderation/case_service.py:997`
  `list_open_cases(db, *, limit: int = 100)` — a nyitott ügyek listája;
- `case_service.py:496` `get_or_create_case(db, *, target_type, target_id, now)`
  — az ügyet ez nyitja (`state=visible`, `is_open=True`), és a
  `compute_priority_score()`-on át a `case_service.py:400 _report_signal()`
  MÉRI a célpont ellen beérkezett `CommunityReport` sorok számát.

**Az A4 cella ezért így mérendő** (a §6 A4 szövege ennek megfelelően pontosítva):
`submit_report` → a `community_reports` sor lekérdezhető → `get_or_create_case`
után a célpont ügye **megjelenik a `list_open_cases()` kimenetében**, ÉS az ügy
`priority_score`-ja a bejelentés-jel figyelembevételével számolt (két bejelentés
esetén a jel `2`). Azt állítani, hogy „a bejelentés a moderációs sorba kerül",
az ügynyitás hívása nélkül **hamis** lenne.

### P2 — a MÉRT korlátok (a `capacity-review.md` SZÁMOLT plafonjának bemenete)

| Korlát | MÉRT érték | Forrás (fájl:sor) | Elérhető-e a mountolt appban |
|---|---|---|---|
| login | 10 / 60 s | `backend/app/routers/auth.py:16` | **IGEN** (`create_app`) |
| register | 5 / 60 s | `backend/app/routers/auth.py:17` | **IGEN** |
| profil-kereső | 60 / 60 s | `backend/app/community/routers/search.py:87-88` | NEM (lásd P3) |
| handle-elérhetőség | 30 / 60 s | `backend/app/community/routers/handles.py:56-57` | NEM |
| handle-változtatás | 5 / 3600 s | `backend/app/community/routers/handles.py:63-64` | NEM |
| kihívás-meghívó | 30 / 60 s | `backend/app/community/services/challenge_invite_service.py:176-177` | NEM |
| bejelentés | **12 / 3600 s** reporterenként | `report_service.py:93-94` (`REPORT_RATE_LIMIT_MAX`) | NEM |
| feltöltés mérete | **104 857 600 B (100 MiB)** | `media_upload_service.py:133` (`MAX_UPLOAD_BYTES`) | NEM |
| élő feltöltés / profil | 10 | `media_upload_service.py:154` | NEM |
| tesztelő-plafon (Kör 27) | `internal` 12, `closed_beta` 50 | `docs/beta/cohort-profiles.yaml` | — |

A `RateLimiter.allow()` szemantikája (`backend/app/ratelimit.py:29-42`): a
számláló az **append ELŐTT** hasonlít (`len(q) >= max_attempts`), tehát az
`N`-edik kérés MÉG átmegy, az `N+1`-edik bukik — a §6 küszöb-cellahármasa
helyesen írja le a mért viselkedést.

### P3 — a Community router NINCS mountolva a fő appban

Mérve: `grep -n "community" backend/app/main.py` → **0 találat**. A Community
végpontokat (kereső, handle, bejelentés, média) a `create_app()` **nem**
szolgálja ki; a mountolást a `backend/tests/community/conftest.py` saját,
minimális `FastAPI()` példánya végzi. Következmény a kör számára:

- a **HTTP-szintű** rate-limit cella (A2) csak az `/auth/*` korlátokon
  mérhető a mountolt appon;
- az A3/A4 cellák a **szolgáltatás-rétegen** mérendők (precedens:
  `backend/tests/community/test_media_upload.py`,
  `.../test_report_service.py` — saját `create_engine` + `alembic upgrade head`
  fájl-alapú SQLite, router nélkül).

### P4 — a `backend/tests/community/conftest.py` fixtúrái NEM látszanak a kör tesztfájljából

A kör tesztfájlja `backend/tests/test_capacity_guards.py`, azaz a `tests/`
csomag gyökerében van; a `tests/community/conftest.py` fixtúrái (`session_factory`,
`community_enabled`, `community_auth_headers`) a `community/` alkönyvtárra
szűkülnek — a kör fájljából **nem hivatkozhatók**. Ami látszik: a
`backend/tests/conftest.py` `client` és `auth_headers` fixtúrája, valamint az
autouse `_fresh_rate_limits` (login/register limiter reset). A Community
oldali cellák tehát **saját** engine-t/sessiont építenek a P3-ban nevezett
precedens szerint. Ez nem scope-tágítás: a fájl az engedélyezett listán van.

### P5 — A2 „elfogadva" ≠ HTTP 200

A `/auth/login` a küszöb alatt is **401**-et ad (nem létező felhasználó); az
„elfogadva" jelentése: **nem 429**. A cellahármas mért alakja
(`login_limiter.max_attempts == 10`):

| Cella | Kérés sorszáma | Elvárt |
|---|---|---|
| küszöb alatt | 9. | `401` (nem 429) |
| pontosan a küszöbön | 10. | `401` (nem 429) |
| küszöb fölött | 11. | **`429`**, `Retry-After` fejléccel |

A számokat a `login_limiter.max_attempts`-ból SZÁMOLD (`N-1`, `N`, `N+1`), ne
írd be kézzel a 9/10/11-et — a hardkódolt szám a korlát változásakor némán
hazudik.

### P6 — a dokumentumot mérő Dart-cella nem ugorhat át hiányzó szakaszt (L571/L575)

Az `open-beta-launch.md` canary-profilja a `canary_cohort_test.dart` MÉRT
bemenete. A parszolás minden lépése **fail-CLOSED**: ha a canary-blokk, a
flag-tábla vagy az emberi kapu markere hiányzik, a cella **PIROS**, nem
„nincs mit mérni → átugrom". A canary-blokk gépi formátuma legyen egyértelmű
(pl. egy ```` ```yaml ```` kódblokk egy nevesített marker-sor mögött), és a
teszt a marker hiányát külön cellában bizonyítsa (temp-fixture, precedens:
`test/tooling/beta_profile_test.dart:60-84` `_tempCopy`).

### P7 — miért TILOS a `cohort-profiles.yaml` átírása (gépi ok, nem stílus)

`test/tooling/ga_scope_test.dart:49-56` MÉRI, hogy a `docs/release/ga-scope.md`
pontosan a `cohort-profiles.yaml` **16** flag-kulcsát sorolja be. Egy új
flag-kulcs a profilfájlban tehát azonnal PIROSRA váltja a `ga_scope_test`-et,
ami a kör §7 gate-jének része. A canary-profil ezért az
`open-beta-launch.md`-ben él. A canary-flagek kulcsai a MÉRT katalógusból
valók: `lib/core/feature_flags/feature_flag_registry.dart` (**40**
`FeatureFlagDefinition` bejegyzés) — kitalált kulcs tilos, és a
`canary_cohort_test.dart` ezt cellával bizonyítja.

### P8 — a backend sáv magától fut a gate-ben

`tools/round-gate.sh:46-57,247-255`: ha a kör a `backend/`-hez ért, a gate
`ruff format --check` → `ruff check` → **teljes** `pytest -q` lépést futtat
(nem csak a kör fájlját). A §7 külön pytest-parancsa ezért kiegészítés, nem
helyettesítés; a `.github/workflows/backend-ci.yml` ugyanezt méri CI-ban.

## 0.0.1 EMBERI KAPU

Az Open Beta megnyitása (szélesebb cohort engedése) **user-döntés**. Az implementer terméke: a canary-cohort konfiguráció, a kapacitás- és költség-guard mérése, a rate-limit és moderation füst-cellák, valamint az indítási csomag. A kör NEM nyit cohortot.

```ai-router
schema_version = 1
risk = "normal"
allowed_paths = [
  "docs/beta/open-beta-launch.md",
  "docs/operations/capacity-review.md",
  "backend/tests/test_capacity_guards.py",
  "test/tooling/canary_cohort_test.dart",
  "docs/rounds/e12-r29-open-beta-and-canary-cohort.md",
]
gate_tests = [
  "test/tooling/canary_cohort_test.dart",
  "test/tooling/ga_scope_test.dart",
]
native_gate = false
```

## 0. Kör-jelzés és STOP-protokoll

```bash
tools/codex-signal.sh progress "<egy sor>"
tools/codex-signal.sh done "<egy sor>"
tools/codex-signal.sh stopped "<egy sor>"
tools/codex-signal.sh blocked "<egy sor>"
```

**STOP-protokoll:** ha a kapacitás-mérés a MÉRT backend-korlátok mellett nem elégséges a tervezett cohort-méretre, a kimenet a `stopped` jelzés — a korlátok felemelése külön, üzemeltetési döntés.

## 1. Cél

A szélesebb cohort megnyitása legyen kapacitás- és moderáció-oldalról mérten előkészített, cohort-izolációval és bizonyított költség-guarddal.

## 2. Jelenlegi állapot — mért tények

- `backend/app/ratelimit.py` **létezik** — a MÉRT rate-limit forrás; `backend/tests/test_hardening.py` fedi.
- Community moderation: `e09_r27_0020_community_moderation` migráció + `docs/operations/community-moderation-runbook.md`.
- `docs/beta/`: a Kör 22/27 után `enrollment.md`, `tester-consent.md`, `feedback-triage.md`, `closed-beta-launch.md`, `cohort-profiles.yaml`, `daily-triage-template.md`.
- Költség-guard MA nincs implementálva (a Chapter 12 §23.3 kéri) — a kör MÉRÉST és eljárást ad, nem szolgáltatói integrációt.

## 3. Scope

**Benne van:** `docs/beta/open-beta-launch.md` — a canary-cohort profilja és a nyitási lépcsők (a Kör 27 `cohort-profiles.yaml` fájlját a kör NEM írja át; a canary-profil ebben a dokumentumban él, és a `canary_cohort_test.dart` méri az izolációját) · `docs/operations/capacity-review.md` (MÉRT rate-limit, tárolási és moderációs kapacitás, és a belőle következő MAXIMÁLIS cohort-méret) · `backend/tests/test_capacity_guards.py` (rate-limit füst, oversized upload, moderation-queue füst) · `test/tooling/canary_cohort_test.dart` (cohort-izoláció: a canary flag-profil nem szivárog a stabil cohortba).

**NINCS benne (tilos):**

- Cohort tényleges megnyitása vagy tesztelő-meghívás.
- `backend/app/**` és `lib/**` módosítás.
- A Kör 27 `cohort-profiles.yaml` átírása (kiegészítés csak akkor, ha az nem ütközik a Kör 27 mércéjével).
- `docs/adr/**`.

## 4. Engedélyezett fájlok

| Útvonal | Indok |
|---|---|
| `docs/beta/open-beta-launch.md` | ÚJ — canary-profil és lépcsők |
| `docs/operations/capacity-review.md` | ÚJ — mért kapacitás és cohort-plafon |
| `backend/tests/test_capacity_guards.py` | a backend-oldali §6 cellák |
| `test/tooling/canary_cohort_test.dart` | a kliens-oldali §6 cellák |

**Tilos zóna:** `backend/app/**` · `lib/**` · `docs/beta/cohort-profiles.yaml` · `.github/**` · `docs/adr/**`

## 5. Kötött architekturális döntések

Nincs ADR. Két kötelező szabály:

### 5.1 A cohort-plafon MÉRT korlátokból SZÁMOLT

**NEM elfogadható gyengítés:** kerek szám („1000 tesztelő") mérés nélkül.

### 5.2 A canary-profil nem szivároghat a stabil cohortba

**NEM elfogadható gyengítés:** közös flag-forrás cohort-megkülönböztetés nélkül.

## 6. Acceptance criteria

| # | Kritérium | Bizonyíték |
|---|---|---|
| A1 | A `capacity-review.md` a MÉRT rate-limit értékekből számolja a cohort-plafont, forrás-hivatkozással | a dokumentum + `canary_cohort_test.dart` |
| A2 | Rate-limit füst: a korlát fölötti kérés elutasított — a mountolt `/auth/login`-on, a `login_limiter.max_attempts`-ból SZÁMOLT cellahármassal (§0.0 P5) | `test_capacity_guards.py` |
| A3 | Oversized upload elutasított: `create_upload_intent(size=MAX_UPLOAD_BYTES+1)` → `MediaSizeExceeded`, a határ INKLUZÍV (`MAX-1`, `MAX` átmegy) — szolgáltatás-rétegen (§0.0 P3/P4) | `test_capacity_guards.py` |
| A4 | Moderation-queue füst a MÉRT úton (§0.0 P1): `submit_report` sora lekérdezhető, `get_or_create_case` után a célpont ügye megjelenik a `list_open_cases()`-ben, és a bejelentés-jel a `priority_score`-ban számít | `test_capacity_guards.py` |
| A5 | A canary flag-profil izolált: a stabil cohort értékei nem változnak | `canary_cohort_test.dart` |
| A6 | A dokumentum kimondja, hogy a cohort megnyitása EMBERI döntés | a dokumentum |

**Küszöb-cellahármas a rate-limitre** (a MÉRT korlát `N` kérés/ablak; a határ INKLUZÍV, azaz az `N`-edik kérés MÉG átmegy): a küszöb **alatt** (`N-1`) → elfogadva; **pontosan rajta** (`N`) → elfogadva; a küszöb **fölött** (`N+1`) → elutasítva (429).

### 6.1 Mérce-mátrix — melyik hibás implementációt melyik cella fogja pirosra

| Hibás implementáció | Melyik cella vált PIROSRA |
|---|---|
| A cohort-plafon becsült szám | A1 |
| A rate-limit cella csak a korlát alatti esetet méri | a küszöb-cellahármas „fölött" cellája |
| A canary flagek a stabil cohortra is hatnak | A5 |
| A dokumentum indítottnak írja le az Open Betát | A6 |
| A canary-blokk hiányzik/elnevezése elromlik, és a teszt „nincs mit mérni" alapon átugorja (L571/L575 fail-OPEN) | a §0.0 P6 marker-hiány cellája (temp-fixture) |
| A rate-limit cellahármas hardkódolt 9/10/11-gyel megy, és a korlát változásakor néma marad | a §0.0 P5 SZÁMOLT cellája (`login_limiter.max_attempts`) |
| A A4 cella „a bejelentés a sorba kerül"-t a `community_reports` sorral igazolja, ügynyitás nélkül | az A4 `list_open_cases()` cellája (§0.0 P1) |

**Valódi-sértés próba (KÖTELEZŐ, a §10-ben dokumentálva):** állítsd a canary-profil egyik flagjét a stabil cohortra is érvényesre a teszt-fixture-ben, futtasd a §7 gate-et → az **A5** cellának PIROSNAK kell lennie → állítsd vissza.

## 7. Kötelező ellenőrzések

```bash
tools/round-gate.sh test/tooling/canary_cohort_test.dart test/tooling/ga_scope_test.dart
```

Backend sáv (külön processzként):

```bash
cd backend && python -m pytest tests/test_capacity_guards.py tests/test_hardening.py -q
```

## 8. Implementációs sorrend

1. A MÉRÉS: `ratelimit.py` korlátai, média-tárolási korlátok, moderation-sor viselkedése.
2. `backend/tests/test_capacity_guards.py` — a küszöb-cellahármassal.
3. `docs/operations/capacity-review.md` — a SZÁMOLT plafon.
4. `test/tooling/canary_cohort_test.dart`.
5. `docs/beta/open-beta-launch.md` (emberi kapuval) + a valódi-sértés próba a §10-be.

## 9. Kockázatok

- **Becsült kapacitás.** Egy kerek szám az első terhelésnél kiderül (A1).
- **Profil-szivárgás.** A canary-flagek stabil cohortra hatása valódi felhasználói kárt okoz (A5).
- **Moderációs terhelés.** A sor füst-cellája nem mér emberi kapacitást — a dokumentum ezt mondja ki, nem hallgatja el.

## 10. Implementation handoff — az implementer tölti ki

**Motor:** `sonnet-impl` (Claude Sonnet 5), `--effort medium`.

**Szállított fájlok** (a §4 engedélyezett listával egyezően, semmi más nem
módosult a `docs/rounds/e12-r29-open-beta-and-canary-cohort.md` §10-en kívül):

- `backend/tests/test_capacity_guards.py` — ÚJ, 7 teszt-eset (A2 3×
  paraméterezett küszöb-cellahármas a `login_limiter.max_attempts`-ból
  számolva; A3 3× paraméterezett méret-küszöb `create_upload_intent`-en; A4
  1 eset a §0.0 P1 mért útvonalon).
- `docs/operations/capacity-review.md` — ÚJ. A számított plafon:
  `canary_max_testers = closed_beta.maxTesters (50, docs/beta/cohort-profiles.yaml)
  × (register_limiter.max_attempts (5) / login_limiter.max_attempts (10))
  = 25`. A szűk keresztmetszet kimondva: a `register_limiter` (a szigorúbb a
  két mountolt admissziós kapu közül) — nem egy fizikai kapacitáskorlát,
  mert §3 megméri, hogy a per-key rate limitek NEM adnak globális
  fejszám-plafont; a 25 egy, a mért konstansokból reprodukálható, óvatossági
  operatív plafon. A moderációs kapacitás (§5 a dokumentumban) kimondottan
  NEM méri az emberi kapacitást. A settings-sync végponton mért rés (nincs
  rate limiter) is dokumentálva (§3).
- `docs/beta/open-beta-launch.md` — ÚJ. Gépileg parszolható
  `<!-- canary-cohort-profile:begin/end -->` blokk (`id: canary`,
  `maxTesters: 25`, 16 flag-kulcs a mért 40-es katalógusból), explicit
  `<!-- human-gate:begin/end -->` blokk ("has NOT launched" / "human
  decision"), és egy kimondott, nem javított rés (§4: settings-sync
  rate-limiter hiánya).
- `test/tooling/canary_cohort_test.dart` — ÚJ, 14 teszt-eset: A1 (3, a
  plafon 3-utas konzisztenciája: `capacity-review.md` marker ↔
  `open-beta-launch.md` canary `maxTesters` ↔ friss újraszámítás
  `auth.py` + `cohort-profiles.yaml`-ból), A5 (2, benne a §10 KÖTELEZŐ
  valódi-sértés próba), A6 (1), P6 fail-closed (5, hiányzó canary-blokk /
  yaml-fence / flags-szekció / human-gate-marker / capacity-review-marker),
  P7 (2, a canary flag-kulcsok a mért regisztry-ből valók).

**Kötelező záró ellenőrzés — tényleges kimenet:**

```
tools/round-gate.sh test/tooling/canary_cohort_test.dart test/tooling/ga_scope_test.dart
```

`MINDEN GATE ZÖLD`: format, analyze, `test test/tooling/canary_cohort_test.dart`
(14/14), `test test/tooling/ga_scope_test.dart` (23/23), architecture, secrets,
l10n, backend ruff format, backend ruff check, **backend pytest** (teljes
suite, `.................. [100%]`, 0 hiba).

Célzott backend-futtatás (§7 kiegészítés):

```
cd backend && /home/ubuntu/music-theory/backend/.venv/bin/python -m pytest tests/test_capacity_guards.py tests/test_hardening.py -q
```

→ 24/24 zöld.

**A KÖTELEZŐ valódi-sértés próba (§6.1, §10) — tényleges kimenet, nem ígéret:**

1. `docs/beta/cohort-profiles.yaml` `closed_beta` cohortjának
   `migratedLearnEnabled: false` sorát ideiglenesen `migratedLearnEnabled: true`-ra
   állítottam (`sed`, egyetlen occurrence, a `internal` cohort sora
   érintetlen maradt).
2. Lefuttattam: `flutter test test/tooling/canary_cohort_test.dart --plain-name
   "the real tree — internal and closed_beta match the E12-R27/R28 baseline exactly"`
   → **PIROS**, a tényleges hibaüzenet: `Which: at location
   ['migratedLearnEnabled'] is <true> instead of <false>` — pontosan az A5
   cella bukott, a szimulált szivárgást elkapva.
3. `git checkout -- docs/beta/cohort-profiles.yaml` — visszaállítva; `git
   status --porcelain docs/beta/cohort-profiles.yaml` üres (nincs diff), a
   fájl a tilos zónában változatlan maradt.
4. Ugyanaz a teszt a visszaállítás után újra lefuttatva → **ZÖLD**
   (`All tests passed!`).

**Doc-comment fegyelem (§5):** minden "korlát N" / "plafon M" állítás a
`capacity-review.md`-ben fájl:sor hivatkozással mért; a settings-sync
rate-limiter HIÁNYA és a moderációs emberi kapacitás MÉRÉS NÉLKÜLI állapota
explicit ki van mondva, nem hallgatva el.

**Kör-jelzés:** `tools/codex-signal.sh done` a commit után.

### 10.1 Javító kör — review-leletek zárása (2026-09-02)

A review (`docs/reviews/e12-r29-review.md`) CHANGES REQUESTED, 1 MAJOR + 1
MINOR. Mindkettő kizárólag `docs/operations/capacity-review.md` §6
„Bemenetek" blokkját érintette.

- **MAJOR-1 zárva:** a `closed_beta.maxTesters = 50` bemenet leírása mostantól
  **konfigurációs precedensként** hivatkozik rá (a Kör 27 által rögzített,
  emberi kapura váró cohort-méret), és kimondja, hogy üzemi tapasztalat
  NINCS mögötte, mert a Closed Beta MÉRTEN nem indult el
  (`docs/beta/closed-beta-launch.md:3,5`). A hamis „ténylegesen ki lett
  osztva és incidens nélkül futott" állítás és a fel nem oldható
  `docs/HANDOFF.md` hivatkozás (helyesen: gyökér `HANDOFF.md`) törölve —
  ugyanez a hamis „bizonyítottan biztonságos" megfogalmazás a §6 alsó
  bekezdésében is javítva. `docs/beta/open-beta-launch.md`-ban nem volt
  hasonló állítás, azt nem módosítottam.
- **MINOR-1 zárva:** a §6-hoz új bekezdés került, kimondva, hogy a képlet a
  `register_limiter.max_attempts` BIZTONSÁGI konstansát köti a tesztelői
  fejszámhoz, hogy egy jövőbeli biztonsági szigorítás (5→4) mechanikusan
  20-ra mozgatná a plafont, és hogy egy ilyen drift esetén a helyes válasz a
  plafon szándékos újragondolása, nem a küszöb visszalazítása. A képlet és a
  25-ös plafon változatlan.
- NOTE-1/NOTE-2: nincs teendő (a review is így jelölte).
- `test/tooling/canary_cohort_test.dart`, `backend/tests/test_capacity_guards.py`,
  a tilos zóna: érintetlen.

**Kötelező záró ellenőrzés — tényleges kimenet:**

```
tools/round-gate.sh test/tooling/canary_cohort_test.dart test/tooling/ga_scope_test.dart
```

`MINDEN GATE ZÖLD`: format, analyze, `test test/tooling/canary_cohort_test.dart`
(14/14 „All tests passed!"), `test test/tooling/ga_scope_test.dart` (24/24 „All
tests passed!"), architecture, secrets, l10n, backend ruff format, backend
ruff check, backend pytest (teljes suite, 100%, 0 hiba).

**Kör-jelzés:** `tools/codex-signal.sh done` a commit után.

### 10.2 2. javító kör — MINOR-2 zárása (2026-09-02)

A review MINOR-2 leletet talált: `docs/beta/open-beta-launch.md:42-44` a
három `preview`-besorolású canary flaget úgy idézte, mint amit
`docs/release/ga-scope.md` §2 „proven"-nek listáz az `internal` cohortban.
A `ga-scope.md` MÉRTEN csak konfigurációt mond (`internal: true`,
`closed_beta: false`, „progressive, internal-dogfood-only rollout today"),
nem üzemi bizonyítékot — és egyetlen cohort sem indult el eddig
(`docs/beta/closed-beta-launch.md:3`), tehát „proven" állítás mögött nincs
mérés.

- **MINOR-2 zárva:** a mondat átfogalmazva — a három flag a `ga-scope.md`
  szerint `preview`-besorolású és a cohort-profil konfigurációjában
  `internal: true`/`closed_beta: false`, ez konfigurációs tény, nem
  operatív bizonyíték, mert egyik cohort sem futott ténylegesen. A „proven"
  szó és minden ezzel egyenértékű állítás eltávolítva.
- Egyedül `docs/beta/open-beta-launch.md` módosult (egy bekezdés); a canary
  yaml-blokk, `maxTesters: 25`, a marker-sorok, `capacity-review.md`, a
  tesztfájlok és a tilos zóna (`backend/app/**`, `lib/**`,
  `docs/beta/cohort-profiles.yaml`, `.github/**`, `docs/adr/**`, `tools/**`)
  érintetlen.

**Kötelező záró ellenőrzés — tényleges kimenet:**

```
tools/round-gate.sh test/tooling/canary_cohort_test.dart test/tooling/ga_scope_test.dart
```

`MINDEN GATE ZÖLD`: format, analyze, `test test/tooling/canary_cohort_test.dart`
(14/14 „All tests passed!"), `test test/tooling/ga_scope_test.dart` (24/24
„All tests passed!"), architecture, secrets, l10n, backend ruff format,
backend ruff check, backend pytest (teljes suite, 100%, 0 hiba).

**Kör-jelzés:** `tools/codex-signal.sh done` a commit után.

## 11. Review — a Claude tölti ki
