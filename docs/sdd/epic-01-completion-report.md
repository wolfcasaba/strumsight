# Epic 1 — Core Platform: zárójelentés

Dátum: 2026-07-30 · Zárókör: E01-R16 · Készítette: Claude (verifikáció,
dokumentáció) + Codex (implementáció) + **user (valódi eszközös tesztek — §6)**
SDD: [`02-epic-01-core-platform.md`](02-epic-01-core-platform.md) · Állapot-pillanatkép: [`HANDOFF.md`](../../HANDOFF.md) · Történet: [`docs/handoff-archive.md`](../handoff-archive.md)

## 1. Elkészült körök

| Kör | Téma | PR | ADR |
|---|---|---|---|
| E01-R01 | Repository baseline (AGENTS.md, SDD, execution docs) | — (`860bbc5`) | 0001–0004 |
| E01-R01b | Branch-per-round + squash-merge PR-workflow | #1 | 0050 |
| E01-R02 | Projektazonosítók (`strumsight`) + verziókezelés | #2 | 0051 |
| E01-R03 | Validált, fail-closed AppConfig-bootstrap | #3 | — |
| (process) | CI-APK, auto-merge, session-per-round szabályok | #4 | 0052, 0053 |
| E01-R04 | Egységes `AppResult`/`AppFailure` + redakciós logging | #5 | — |
| E01-R05 | Storage-infrastruktúra (KeyValueStore, migrátor, SecureStore) | #6 | — |
| E01-R06 | Settings/core preference-migráció (schema 1–16) | #7 | — |
| E01-R07 | Verziózott user-content dokumentumok + karantén (schema 17–22) | #9 | 0054 |
| E01-R08 | Hálózati kliens + auth hardening (DioFactory, 401, no-retry) | #11 | — |
| E01-R09 | Mikrofon- és audio-lifecycle (owner+lease, guard) | #10 | 0056 |
| E01-R10 | Közös zenei/audio domain + architecture guard (A+B) | #12+#13 | 0057, 0058 |
| (process) | Ágensszerep-protokoll (brief → implement → review) | #14 | 0055 |
| (process) | Codex kör-jelzés + stall/timeout watchdog | #15 | 0064 |
| E01-R11 | Routing + app-shell stabilizálás (route-katalógus) | #16 | 0059 |
| E01-R12 | Backend konfiguráció + Alembic-migráció, health-endpointok | #17 | 0060 |
| E01-R13 | Backend security + Lab-elkülönítés (prod 404, streaming upload) | #18 | 0061 |
| E01-R14 | Flutter CI gate-sor + fail-closed release signing | #19 | 0062 |
| E01-R15 | Backend CI + generált ML asset manifest | #20 | 0063 |
| E01-R16 | Zárókör: offline guard, CI-dedup, dokumentáció, e jelentés | #21 | — |

A körök részletes története (verifikációs kimenetekkel, tanulságokkal):
[`docs/handoff-archive.md`](../handoff-archive.md). Az SDD Ch2 16 körre volt
vágva; a Kör 15 (ML CI) és a backend-CI összevontan futott az R15-ben.

## 2. Kihagyott / elhalasztott feladatok (nyitott follow-upok)

Tudatos, dokumentált halasztások — egyik sem Epic-1 DoD-tétel:

1. **R13 NOTE-3:** prodban engedélyezett `/download` token nélküli — tokenesítés,
   ha a Lab-APK publikus prod-URL-re kerül (`docs/reviews/e01-r13-review.md`).
2. **`build-apk.yml` `pull_request` trigger** nincs — ADR 0062 §1 szándékos;
   branch-protection kérdéssel együtt döntendő (Ch12).
3. **R15 NOTE-2:** kézzel írt SHA-256 a manifest-tesztben — `crypto` csomag
   felvételekor cserélendő.
4. **Coverage-küszöb nincs:** `config` 79,66%, `foundation` 76,19% a Ch2 §14.8
   90%-os célja alatt (kritikus modulok együtt 88,07%) — küszöbösítés későbbi kör.
5. **R15 NOTE-3/4:** hardcode-olt training-run azonosítók (szándékos súrlódás);
   `backend-ci.yml` push-trigger branch-szűrés nélkül.
6. **R13 NOTE-1/2:** `STRUMSIGHT_DIAG_MAX_BYTES` per-request env-olvasás;
   `_unique_session_path` TOCTOU több workernél (ma single-process).
7. **R12 NOTE-1:** `/health/ready` kérésenként olvassa az alembic script dir-t.
8. **R04 follow-up:** 62 `catch (_)` a `lib/`-ben — a mérőszám nem lett lenyomva
   (a 3 production üres catch indoklása: §10 Hibakezelés).
9. **R10 follow-upok:** `WavDecoder`-t a `lib/`-ből semmi nem hívja („importáld
   a saját audiódat" út későbbi epicé); `public.dart` exportok `show`-listásítása;
   az `analyze → live/engine` allowlist felszámolása a DSP-boundary költözésekor;
   `@Deprecated` shimek törlése.
10. **Auth-rétegen:** nincs jelszó-reset / e-mail-verifikáció / refresh token
    (14 napos JWT); mid-session token-lejárat interceptor Riverpod-reentrancia
    miatt szándékosan halasztva. Login-backend nincs hosztolva.
11. **iOS build** Mac nélkül nem lehetséges.

## 3. Architekturális változások (ADR 0050–0064)

0050 branch-per-round PR-workflow · 0051 StrumSight-azonosítók + verzió-forrás ·
0052 CI-APK + zöld-kapus auto-merge + session-per-round · 0053 teljes suite a
CI-ben · 0054 verziózott user-content dokumentumok · 0055 ágensszerep-protokoll ·
0056 exkluzív mikrofon-session · 0057 közös zenei domain + feature public API ·
0058 közös WAV codec + gépi architecture guard (fájl az R16-ban pótolva) ·
0059 központi route-katalógus + validált navigáció · 0060 Alembic schema-forrás +
injektált engine-életciklus · 0061 Lab-route izoláció + hardened diagnosztika ·
0062 CI gate-sor + fail-closed release signing · 0063 generált ML manifest +
backend CI · 0064 Codex CI-átadás code-complete-nél (fájl az R16-ban pótolva).

Az Epic-1 alapelvei (0003 pure-Dart DSP first, 0004 inkrementális refaktor)
végig betartva: a DSP/ML paraméterek az Epic alatt nem változtak (AGENTS.md §9).

## 4. Teszteredmények (E01-R16 záró regresszió, 2026-07-30)

**Lokál (külön hívásokként):**

| Ellenőrzés | Eredmény |
|---|---|
| `dart format --set-exit-if-changed lib test tool` | 450 fájl, 0 changed |
| `flutter analyze lib/ test/ tool/` | No issues found |
| `flutter test test/app` | 41 passed (39 + 2 új offline guard) |
| `dart run tool/check_architecture.dart` | OK (12 allowlisted deviation) |
| backend `ruff check` + `format --check` | tiszta (20 fájl) |
| backend `pytest -q` (sima + `STRUMSIGHT_ALLOW_SQLITE=true`) | 64 passed mindkét futásban |

**CI a kör-branchen (`codex/epic-01-round-16-final-regression`):**

| Workflow | Eredmény |
|---|---|
| `backend-ci.yml` | ✅ zöld — [run 30521933758](https://github.com/wolfcasaba/strumsight/actions/runs/30521933758) |
| `release-apk.yml` secret nélkül (fail-closed próba, a composite-refaktor UTÁN) | ✅ elvárt failure — [run 30521935406](https://github.com/wolfcasaba/strumsight/actions/runs/30521935406): `signing-prerequisites` fail → release-apk és Coverage **skipped**, **0 artifact** |
| `build-apk.yml` (teljes suite + randomizált property + coverage-job + APK) | ✅ zöld — [run 30521932327](https://github.com/wolfcasaba/strumsight/actions/runs/30521932327): **1035 passed / 10 skipped** teljes suite · property gate **23 passed** friss seeddel · Coverage-job párhuzamosan zöld (ugyanaz az 1035) · development APK artifact |

Az offline network guard **érzékenység-próbája** (ideiglenesen beinjektált
kérés → `[1, 1]` piros, visszavonva → zöld) a kör-brief §10-ében dokumentált,
valódi kimenettel.

## 5. Teljesítmény-baseline

A számszerű, eszközön mért profilozás (cold start, Live-start latency, CPU,
memória 10 perces session után, dropped frames, akku) **ezen a fejlesztő-boxon
nem mérhető** — nincs fizikai Android-eszköz. A §16.4 szerinti baseline a user
készülékes menetéből töltendő fel ide:

| Metrika | Érték | Megjegyzés |
|---|---|---|
| App cold start | ⏳ user-mérés | |
| Live start ideje | ⏳ user-mérés | |
| Feldolgozási latency (érzet) | ⏳ user-mérés | |
| CPU / memória / dropped frames | nem mérhető eszköz nélkül | profilozó-futás későbbi körben |
| Melegedés / akku (szubjektív) | ⏳ user-mérés | |

Viszonyítási pont: a DSP-pipeline szintetikus jelen ~15 Hz LiveFrame-rátára
méretezett (README architektúra-szekció); regressziót a property gate őriz.

## 6. Valódi eszközös audio-regresszió (§16.3) — **PENDING, a kör ezzel zárul**

A HORIZON-szabály szerint a szintetikus zöld nem „done" — az Epic-1 zárás
végső elfogadási predikátuma a user valódi-gitáros APK-tesztje. A lista:
Live start/stop · Live→Settings · Live→Tuner · háttérbe küldés · képernyőzár ·
permission-megtagadás majd engedélyezés · hosszú session · mic-indikátor
kialszik a session végén. **Eredmény (user):** ⏳ — a visszajelzés után ez a
szekció tételes OK / hibalistával frissítendő.

## 7. Ismert kockázatok

- **Készülék-diverzitás:** az audio-stack (mic-latency, sample-rate, AGC)
  gyártónként eltér; egyetlen eszközös menet nem reprezentatív minta.
- **Coverage-rés a config/foundation modulokban** (§2.4) — a hibakezelő út
  egy része csak közvetve fedett.
- **A backend nincs éles környezetben hosztolva** — a prod-hardening tesztek
  (fail-closed secret, Lab-404) gépiek, éles smoke-teszt még nem futott.
- **Compute-többlet a CI-ben:** a coverage-job a teljes suite-ot másodszor
  futtatja (wall-clock nyereségért) — runner-perc árban jelentkezik.
- **Egyetlen fejlesztő-box:** a lokális gate-ek egy gépen futnak; a CI a
  hiteles referencia (ADR 0053).

## 8. Dependency-allowlist állapota

- **Architektúra-allowlist:** 12 tétel (`tool/check_architecture.dart`), mind
  `analyze → live/engine/{dsp,ml}` — „csak csökkenhet" policy, az elavult
  bejegyzés is pirosít (ADR 0058). Az Epic alatt **nem nőtt**; feloldása a
  DSP-boundary `core/`-ba költözésekor esedékes.
- **Pub-függőségek:** 18 csomag + 2 SDK (`dependencies`), 2 dev-függőség —
  mindegyik indokolt (a pubspec kommentjei tételesek); `flutter_secure_storage`
  v10-re pinelve (ONE win32 major szabály). `crypto` szándékosan nincs (§2.3).
- **`assets/ml/model_manifest.json` szándékosan nem Flutter-asset** — build/
  guard-idejű metaadat, a tooling `File()`-lal olvassa (ADR 0063).

## 9. Epic 2 (Practice Engine) előfeltételei

Mind teljesül: közös zenei domain (`core/music`) feature-független ✅ ·
audio-session koordináció újrafelhasználható (owner+lease) ✅ · storage
verziózott, migrálható (új dokumentumtípus felvehető) ✅ · route-katalógus
bővíthető ✅ · CI-gate-sor és property-minta kész az új körökhöz ✅ · agent-
protokoll és kör-sablonok élnek ✅. Indulás: `docs/sdd/03-epic-02-practice-engine.md`,
első kör ÚJ sessionben, kör-brieffel.

## 10. SDD Ch2 §10 DoD checklista — evidenciával

### Kódszerkezet
- [x] AGENTS.md létezik és érvényes — repo-gyökér, doc-priority lánc.
- [x] SDD a repositoryban — `docs/sdd/00-index.md` … `12-*.md`.
- [x] ADR-ek — `docs/adr/0001–0004, 0050–0064` (hiánytalanul; 0058/0064 az R16-ban pótolva).
- [x] Dart package neve `strumsight` — `pubspec.yaml:1`.
- [x] Platformazonosítók StrumSight-specifikusak — ADR 0051 +
      `test/tooling/legacy_identifier_guard_test.dart` (grep `music_theory`: 0 találat).
- [x] `main.dart` csak bootstrappel — `test/app/app_bootstrap_test.dart`.
- [x] AppConfig validált és tesztelhető — `test/app/app_config_test.dart`.
- [x] Core szolgáltatások DI-vel — Riverpod providerek (`lib/core/*/…_providers.dart`).
- [x] Core nem importál feature-t — `tool/check_architecture.dart` (CI-gate R14 óta).
- [x] Domain nem importál Fluttert — `tool/check_architecture.dart` (CI-gate).

### Hibakezelés
- [x] AppResult — `lib/core/foundation/app_result.dart`.
- [x] AppFailure — `lib/core/foundation/app_failure.dart`.
- [x] DioException nem jut a UI-ba — `lib/core/network/network_failure_mapper.dart`
      + `test/core/network/network_failure_mapper_test.dart`.
- [x] Platform exception nem automatikus siker — a `PlatformException` az
      `AppResult`/`AppFailure` határon képződik le (`lib/core/foundation/`) +
      `test/core/storage/{key_value_store,secure_store}_test.dart`.
- [x] Nincs üres catch az érintett production kódban — 3 dokumentált, indokolt
      kivétel: `chord_audio.dart:150` + `metronome.dart:55` (best-effort
      player-dispose — a dispose-hiba nem akcionálható) és `live_screen.dart:115`
      (haptika, off-device/tesztben no-op). Egyik sem nyel el backend-írást vagy
      üzleti hibát (a „silent no-op" osztály nem érintett).
- [x] Felhasználói hibaüzenetek lokalizáltak — ARB (`lib/l10n/app_en.arb`, `app_hu.arb`).

### Storage
- [x] Feature-ök nem importálnak SharedPreferences-t —
      `test/tooling/preferences_plugin_import_guard_test.dart`.
- [x] Secure storage közös interfész — `lib/core/storage/secure_store.dart`
      (`abstract interface class SecureStore`).
- [x] Storage schema verziózott — `lib/core/storage/storage_migrator.dart` + ADR 0054.
- [x] Régi kulcsok migrálódnak — `test/core/storage/preference_migration_test.dart`.
- [x] Migráció idempotens — `test/core/storage/storage_migrator_test.dart`.
- [x] Sérült rekord nem okoz adatvesztést —
      `test/core/storage/persisted_record_validation_test.dart` (karantén, ADR 0054).

### Hálózat
- [x] DioFactory az egyetlen production Dio-forrás —
      `test/tooling/dio_factory_guard_test.dart`.
- [x] Account-disabled → nincs account request —
      `test/app/offline_network_guard_test.dart` (R16): teljes boot + 8 fő
      képernyő, `[factory-létrehozás, request] == [0, 0]`, érzékenység-próbával.
- [x] Diagnostics-disabled → nincs diagnostics request — ugyanott
      (`diagnosticsApiClientProvider == null` a valódi production úton).
- [x] Token/jelszó/nyers audio nincs logban —
      `lib/core/network/redacted_log_interceptor.dart` +
      `test/core/logging/log_redactor_test.dart`.
- [x] 401 → kontrollált session-invalidáció (session-generációval védve) —
      `lib/core/network/auth_interceptor.dart` + `test/features/auth/auth_repository_test.dart`.
- [x] POST nem kap veszélyes automatikus retryt —
      `test/core/network/dio_factory_test.dart` („POST transport failure is
      attempted exactly once").

### Audio
- [x] Egy mic owner — ADR 0056 + `test/core/audio/audio_session_coordinator_test.dart`.
- [x] Route-elhagyáskor mic felszabadul — `test/core/audio/audio_lifecycle_guard_test.dart`.
- [x] Background → mic felszabadul — `test/features/live/live_background_test.dart`.
- [x] Start/stop race tesztelt — `test/core/audio/mic_capture_test.dart` (single-flight).
- [x] autoDispose regresszió-védett — `test/features/live/live_screen_test.dart`,
      `test/features/analyze/cancel_on_leave_test.dart`.
- [x] DSP parity változatlan — randomizált property gate (CI, friss seed) +
      AGENTS.md §9 tilalom; az Epic alatt DSP-paraméter nem változott.
- [x] ML asset parity változatlan — generált manifest + kétirányú gate (ADR 0063).
- [ ] **Készülékes regresszió (§16.3) — PENDING (user), lásd §6.** A gépi
      fedettség teljes; a valódi-eszközös menet az Epic-zárás utolsó kapuja.

### Backend
- [x] Alembic kezeli a schema-migrációt — ADR 0060, `backend/alembic/`.
- [x] Prod nem futtat automatikus `create_all`-t — spy-teszt + subprocess-teszt (R12).
- [x] Liveness endpoint — `/health/live` (R12).
- [x] Readiness endpoint — `/health/ready` (SELECT 1 + alembic head + config; R12).
- [x] Prod secret-validáció fail-closed — R12/R13 boot-guardok (SQLite-escape-hatch
      csak explicit `STRUMSIGHT_ALLOW_SQLITE=true`-val).
- [x] Lab route-ok prodban nem regisztráltak — ADR 0061 (prodban 404, tesztelve).
- [x] Diagnosztikai upload streaming + méretkorlátos — R13 (szkriptelt-receive
      teszt bizonyítja a korai megszakítást; atomikus `os.replace`).
- [x] bcrypt 72 byte validált — R13 (422 az új regisztrációnál).
- [x] Backend tesztek CI-ben — `backend-ci.yml`; friss zöld:
      [run 30521933758](https://github.com/wolfcasaba/strumsight/actions/runs/30521933758).

### CI és release
- [x] Format gate aktív — `.github/actions/flutter-gates` (mindkét workflow).
- [x] Analyze gate aktív — ugyanott (lib + test + tool).
- [x] Flutter test gate aktív — ugyanott (teljes suite).
- [x] Property test gate aktív — randomizált seed (`PROPERTY_SEED=run_id`), hard gate.
- [x] Architecture gate aktív — `check_architecture.dart` a gate-sorban.
- [x] Backend pytest gate aktív — `backend-ci.yml`.
- [x] Backend Ruff gate aktív — ugyanott (lint + format-check).
- [x] Model checksum gate aktív — generált ML manifest + asset gate (ADR 0063).
- [x] Prod release nem használ debug signingot — `release-apk.yml` fail-closed;
      a composite-refaktor UTÁN újra bizonyítva:
      [run 30521935406](https://github.com/wolfcasaba/strumsight/actions/runs/30521935406)
      (első job failure → minden downstream skipped, 0 artifact) + gradle
      `STRUMSIGHT_REQUIRE_RELEASE_SIGNING` kettős védelem.
- [x] Build artifact verziózott és azonosítható —
      `strumsight-<ver>-<build>-<sha>-<env>.apk` (ADR 0051/0062).

**Összegzés:** 51/52 tétel evidenciával kipipálva; az egyetlen nyitott tétel a
user készülékes menete (§6) — a HORIZON-szabály szerint ez az Epic-zárás végső,
nem megkerülhető kapuja.
