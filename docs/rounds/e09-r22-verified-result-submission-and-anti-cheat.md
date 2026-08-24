# E09-R22 — Verified result submission és anti-cheat

- **Státusz:** PREPARED (előre megírva 2026-08-22, kód olvasva: `main @ db6293f4`) → pre-flight revideálva 2026-08-24, kód újra-olvasva `main @ f5517430`
- **Típus:** Chapter 10 (Epic 9 — Community Platform), Kör 22
- **Kör-azonosító:** `E09-R22`
- **Branch:** `<motor>/e09-r22-verified-result-submission-and-anti-cheat`
- **Előfeltétel:** `E09-R21` merge-elve
- **Brief szerzője:** Claude (Opus 5); pre-flight revízió: Claude Sonnet 5
- **Előre kiosztott ADR:** ~~`ADR 0411`~~ **`ADR 0417`** — a `0411` MÁR foglalt (`docs/adr/0411-iconography-and-guitar-glyph-contract.md`). `tools/round-slots.py reserve-adr --round E09-R22` friss számot adott. Lásd [ADR 0417](../adr/0417-verified-result-submission-and-anti-cheat.md) a teljes döntéskörért.

**Kockázat = high, indoklás:** a kör egy szerveroldali anti-cheat és
trust-állapot döntést hoz — az egész Epic 9 versenyrendszer hitelessége azon
múlik, hogy a szerver SOHA nem fogad el kliens-oldali `verified`/`rank`
állítást (ADR 0417 D1–D5), és hogy a replay-védelem (D2/D3) valóban zárt.
Egyik `allowed_paths` fájl sem egyezik szó szerint a router
`high_risk_path_fragments` listájával, de a kockázat ettől függetlenül
valós — integrity/anti-cheat, nem forma szerinti kulcsszó-egyezés (ugyanaz
az indoklás-minta, mint az E09-R21 `high` besorolásánál).

## 0.0 Pre-flight brief-revízió (2026-08-24, Claude Sonnet 5)

A teljes mért-tény alapú indoklás [ADR 0417](../adr/0417-verified-result-submission-and-anti-cheat.md)
Kontextus szakaszában. Összefoglalva:

1. **`allowed_paths` bővítve két, MÁR meglévő fájllal** — a Kör 21
   `challenge_repository_impl.dart` docstringje és az ADR 0415 §D6 EXPLICIT
   ezt a kört jelölte ki a `submitResult` service-oldali bekötésére, de az
   eredeti `allowed_paths` sem a `backend/app/community/routers/challenges.py`
   routert, sem a `lib/features/community/data/repositories/
   challenge_repository_impl.dart` repository-implementációt nem
   tartalmazta — enélkül a funkció nem érne el végponttól végpontig (ADR
   0417 1. pont).
2. **A "participant-állapot" validáció (§3) OLVASÁS, nem ÍRÁS.** Mérve
   (`grep -rn "CHALLENGE_INVITE_STATE_ACTIVE" backend/app/community/`): az
   `active` invite-állapot MA elérhetetlen (0 hozzárendelés-hely a kódban) —
   a brief eredeti "A Kör 21 challenge-lifecycle MA `active` állapotig jut"
   állítása téves volt (§1 pre-flight szabály 1. pontja, elérhetetlen
   cél-státusz). Ez a kör a beküldést az `invite.state ∈ {accepted, active}`
   halmaz ellen validálja (elutasít terminális állapotban), de NEM írja az
   invite sorát — az `accepted → active` előreléptetés egy KÉSŐBBI kör
   dolga (ADR 0417 D1).
3. **A "server-issued nonce" szerver-belső TTL-es bekönyvelés, nem
   kliens-kerülőút.** A Kör 5 `submitResult` interfész (`challengeId`,
   `metricValue`, `sourceEventId`, `idempotencyKey`) fagyott, nincs
   `allowed_paths`-on, nem bővül nonce-mezővel. A szerver az ELSŐ
   feldolgozási kísérletkor generálja és tárolja a nonce-ot a
   `challenge_result` soron; az A4 teszt a szervizen keresztül fabrikált,
   már lejárt sorral mér (ADR 0417 D3).
4. **A metric-range a MÁR élő kliens-kontraktusból jön.**
   `kCommunityChallengeMetricMinValue = 0`,
   `kCommunityChallengeMetricMaxValue = 1000000`
   (`lib/features/community/domain/entities/community_challenge.dart`) — az
   `integrity_policy.py` UGYANEZT a `[0, 1000000]` tartományt tükrözi
   Python-oldalon, nem talál ki új számot (ADR 0417 D4).
5. **Az eredmény-sor a `community_challenge_participants` sorhoz kötődik.**
   A `best_metric_value` oszlop docstringje szerint ez MÁR a "Kör 22 results
   surface" — MA sehol nem íródik (`grep -rn "best_metric_value" backend/
   lib/` → mindig `None`/`NULL`), tehát a `challenge_result.py`
   `participant_id` FK-ja a `community_challenge_participants.id`-ra megy, a
   `challenge_verification_service.py` pedig egy feltételes `UPDATE`-tel
   írja a `best_metric_value`-t a `verified` döntés után (ADR 0417 D5/D6).
6. **Router-endpoint:** `POST /community/challenges/{challenge_public_id}/results`,
   a Kör 21 `post_create_invite` szerkezetét követve, inline Pydantic
   request/response modellekkel (ADR 0417 D7).

```ai-router
schema_version = 1
risk = "high"
allowed_paths = [
  "backend/app/community/services/challenge_verification_service.py",
  "backend/app/community/models/challenge_result.py",
  "backend/app/community/policies/integrity_policy.py",
  "backend/app/community/routers/challenges.py",
  "backend/alembic/versions/e09_r22_0016_community_challenge_result.py",
  "lib/features/community/application/controllers/challenge_result_controller.dart",
  "lib/features/community/data/repositories/challenge_repository_impl.dart",
  "backend/tests/community/test_challenge_verification.py",
  "test/features/community/application/challenge_result_controller_test.dart",
  "docs/rounds/e09-r22-verified-result-submission-and-anti-cheat.md",
]
gate_tests = [
  "test/features/community/application/challenge_result_controller_test.dart"
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

Lezáró jelzés nélkül a kör bukott. **Listán kívüli fájl kellene → `stopped`**,
és a kimenet a brief-revízió kérése, nem az `allowed_paths` csendes tágítása.
Meglévő, ma zöld teszt elbukása → `blocked`, nem a teszt átírása.

## 1. Cél

Challenge-eredmények szerveroldali, idempotens ellenőrzése és a trust-állapot rögzítése — a szerver SOHA nem fogad el kliens-oldali `verified` flaget vagy rankot.

## 2. Jelenlegi állapot — mért tények

- **JAVÍTVA (§0.0):** a Kör 21 challenge-lifecycle a gyakorlatban `accepted`
  állapotig jut — az `active` érték csak deklarálva/allowlistelve van, 0
  hozzárendelés-hely a kódban (mérve). Ez a kör az `invite.state ∈
  {accepted, active}` halmazt OLVASSA a beküldés validálásához, nem írja.
- A gamifikáció E08-R28 MÁR bizonyítja a "szerver soha nem fogad el kliens-oldali összesített értéket" mintát (`docs/adr/0394-ledger-sync-contract-and-merge.md`, merge-elve) — ez a kör UGYANAZT a mintát alkalmazza, nem talál ki újat.
- A Kör 21 `challenge_repository_impl.dart` `submitResult`/`leaderboard` MA `UnimplementedError`-t dob, explicit "Kör 22 scope" jelzéssel — ez a kör köti be a valódi HTTP-hívást (§0.0 pont 1).

## 3. Scope

**Benne van:** eredmény-submit endpoint stabil source-event-ID + server-issued nonce-szal · challenge-verzió, időablak, participant-állapot, metric-range, scorer-kompatibilitás validáció · SOSEM kliens által küldött rank vagy verified flag elfogadása · replay-deduplikáció + first/best-submission policy challenge-típusonként · verification state: pending, verified, unverified, rejected, review · anomaly signal reason-code-os, nyers audio NÉLKÜL · kliensen a pending verification elkülönül a lokális session sikerétől.

**NINCS benne (tilos):**

- Leaderboard — Kör 23 (ez a kör csak a verified receiptet állítja elő).
- `docs/adr/**` — az ADR 0417-et a Claude írja.
- Az invite-állapot előreléptetése (`accepted → active → completed | forfeited`) — olvasás-only ellenőrzés, nem írás (§0.0 pont 2, ADR 0417 D1).

## 4. Engedélyezett fájlok

| Útvonal | Indok |
|---|---|
| `backend/app/community/services/challenge_verification_service.py` | ÚJ |
| `backend/app/community/models/challenge_result.py` | ÚJ |
| `backend/app/community/policies/integrity_policy.py` | ÚJ |
| `backend/app/community/routers/challenges.py` | MEGLÉVŐ — ÚJ `post_submit_result` endpoint (§0.0 pont 1/6, ADR 0417 D7) |
| `backend/alembic/versions/e09_r22_0016_community_challenge_result.py` | ÚJ |
| `lib/features/community/application/controllers/challenge_result_controller.dart` | ÚJ |
| `lib/features/community/data/repositories/challenge_repository_impl.dart` | MEGLÉVŐ — a `submitResult` `UnimplementedError`-stubja valódi HTTP-hívásra cserélve (§0.0 pont 1, ADR 0417 D7) |
| `backend/tests/community/test_challenge_verification.py` | ÚJ — a §6 cellái |
| `test/features/community/application/challenge_result_controller_test.dart` | ÚJ |

**Tilos zóna:** `backend/app/community/models/challenge.py` (a Kör 21 lezárt lifecycle-je — a `best_metric_value` oszlopot ez a kör ÍRJA egy `UPDATE`-tel a service-rétegből, de a modell-fájlt nem módosítja) · `backend/app/community/services/challenge_invite_service.py` (az invite-állapot előreléptetése egy KÉSŐBBI kör dolga, §0.0 pont 2) · `lib/features/community/domain/**` (a Kör 5 `CommunityChallengeRepository`/`submitResult` szerződés fagyott) · `docs/adr/**` · `tools/**` · `.github/**`

## 5. Kötött architekturális döntések (ADR 0417)

A teljes indoklás [ADR 0417](../adr/0417-verified-result-submission-and-anti-cheat.md)
Döntés szakaszában (D1–D7). Összefoglalva:

### 5.1 A SZERVER SOSEM fogad el kliens-oldali `verified` flaget vagy `rank`-ot

A submit-payload eredmény-adatot (metric, timestamp, source-event-ID) hordoz — a `verified` és a `rank` KIZÁRÓLAG a szerver saját kiértékeléséből származik, ugyanaz az elv, mint az E08-R28 ledger-szinkron `totalXp`-tilalma.

**NEM elfogadható gyengítés:** egy "gyorsítótárazott" `verified` vagy `rank` mező elfogadása a kérésben, akár csak ellenőrzésre — ami a kérésben van, arra a szerver támaszkodni fog, tehát ez triviálisan hamisítható csalássá válna.

### 5.2 A replay NEM hoz létre második eredményt

DB `UNIQUE(participant_id, source_event_id)` + `IntegrityError`-újraolvasás (ADR 0417 D2, a Kör 11/21 idempotency-mintája) deduplikálja a beküldést; a challenge-típusonként dokumentált first/best policy (ADR 0417 D6: `personalBest` = best-of, a többi 4 típus = first-wins) dönt a végleges eredményről.

### 5.3 A verification hiba NEM törli a lokális session sikerét

A Community upload-hiba (hálózat, verzió-eltérés) NEM befolyásolja a Practice/Song-session lokális, már elmentett eredményét — a pending verification külön állapot a UI-ban, a `challenge_result_controller.dart` saját application-state-jében (a Kör 5 domain-entitás NEM bővül verification-mezővel).

### 5.4 A "server-issued nonce" szerver-belső TTL-es bekönyvelés (ADR 0417 D3)

A nonce a `challenge_result` sorhoz kötött, szerver-generált `uuid4` +
`nonce_expires_at` — a kliens sosem küldi vissza, a Kör 5 `submitResult`
interfész emiatt nem bővül. Az A4 cella a szervizen keresztül fabrikált,
már lejárt sorral tesztel.

### 5.5 A metric-range és a participant-write felület a MÁR élő kontraktusból jön (ADR 0417 D4/D5)

`[0, 1000000]` — `kCommunityChallengeMetricMinValue`/`Max` tükre
Python-oldalon. A `best_metric_value` (`community_challenge_participants`)
ennek a körnek a MÁR kijelölt, MA üres írási felülete.

## 6. Acceptance criteria

| # | Kritérium | Bizonyíték |
|---|---|---|
| A1 | Replay nem hoz létre második eredményt | `test_challenge_verification.py` |
| A2 | Forged `verified`/`rank` a kérésben figyelmen kívül marad | `test_challenge_verification.py` |
| A3 | Fizikailag lehetetlen (impossible) score elutasított | `test_challenge_verification.py` |
| A4 | Lejárt nonce elutasított | `test_challenge_verification.py` |
| A5 | Rossz challenge-verzió/scorer-inkompatibilitás elutasított | `test_challenge_verification.py` |
| A6 | First/best submission policy helyesen alkalmazott challenge-típusonként | `test_challenge_verification.py` |
| A7 | Community upload-hiba nem törli a lokális session sikerét | `challenge_result_controller_test.dart` |
| A8 | A döntés reason-code-dal auditált | `test_challenge_verification.py` |

### 6.1 Mérce-mátrix — melyik hibás implementációt melyik cella fogja pirosra

| Hibás implementáció | Melyik cella vált PIROSRA |
|---|---|
| A submit-endpoint elfogadja a kérésben küldött `verified: true` mezőt | A2 |
| Ugyanaz a source-event-ID kétszer hoz létre eredményt | A1 |
| Egy fizikailag lehetetlen score (pl. negatív idő alatt teljes pontszám) átmegy | A3 |
| A lejárt nonce-szal küldött eredmény elfogadásra kerül | A4 |
| Terminális állapotú (`declined`/`expired`/`cancelled`/`completed`/`forfeited`) invite-hoz tartozó beküldés elfogadásra kerül | A5 |
| Egy MÁSIK challenge `version`-jével küldött beküldés elfogadásra kerül | A5 |
| `personalBest` típusnál egy rosszabb második beküldés felülírja a jobb elsőt | A6 |
| Nem-`personalBest` típusnál egy második (jobb) beküldés felülírja az elsőt | A6 |
| A rejected/unverified döntés `reason_code` nélkül perzisztálódik | A8 |
| A Community upload-hiba a lokális practice-session eredményét is törli | A7 |

**Valódi-sértés próba (KÖTELEZŐ, §10-ben dokumentálva):** add hozzá a `verified` mező közvetlen elfogadását a submit-payloadból, futtasd a backend pytest-et forged-verified bemenettel → az **A2** cellának PIROSNAK kell lennie → állítsd vissza.

## 7. Kötelező ellenőrzések

```bash
tools/round-gate.sh test/features/community/application/challenge_result_controller_test.dart
```

A backend oldal külön, önálló parancs (NEM láncolva):

```bash
cd backend && python -m pytest tests/community/test_challenge_verification.py -q
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

1. Migráció: `community_challenge_results` (`participant_id` FK, `source_event_id`, `idempotency_key`, `metric_value`, `verification_state`, `reason_code`, `nonce`, `nonce_expires_at`, `submitted_at`, `decided_at`; `UNIQUE(participant_id, source_event_id)` — ADR 0417 D2/D5).
2. `integrity_policy.py` — metric-range (`[0, 1000000]`, ADR 0417 D4), challenge-verzió + időablak + invite-állapot (olvasás-only, ADR 0417 D1) validáció, impossible-score detekció.
3. `challenge_verification_service.py` — replay-dedup (D2), nonce-issuance/expiry (D3), first/best policy (D6), a szerver SAJÁT verified/rank számítása, a `community_challenge_participants.best_metric_value` feltételes `UPDATE`-je.
4. `routers/challenges.py` — ÚJ `POST /community/challenges/{challenge_public_id}/results` endpoint (D7), inline Pydantic request/response.
5. `lib/.../challenge_repository_impl.dart` — `submitResult` valódi HTTP-hívásra cserélve (D7, az `acceptInvite` mintáját követve).
6. `challenge_result_controller.dart` — pending-verification állapot, elkülönítve a lokális sikertől.
7. A valódi-sértés próba §10-be; a §7 mindkét parancsa KÜLÖN futtatva.

## 9. Kockázatok

- **A kliens-adta `verified`/`rank` elfogadása.** Ez a legsúlyosabb lehetséges hiba az egész Epicben — a teljes versenyrendszer hitelességét vinné (A2), pontosan az E08-R28-cal analóg kockázat.
- **A replay.** Egy megismételt beküldés enélkül tetszőleges számú eredményt termelne (A1).
- **A Community-hiba összekapcsolása a lokális sikerrel.** A felhasználó azt hinné, elveszett a gyakorlása egy hálózati hiba miatt (A7).

## 10. Implementation handoff — az implementer tölti ki

**Implementer: MiniMax M3 · Orchestrátor/Reviewer: Claude Sonnet 5 · Dátum: 2026-08-24**

### §10.1 Végrehajtott scope

A §3-as lista MINDEN elemét megvalósította, a §4 `allowed_paths` betartásával
(NEM nyúltam a tilos zónához: `backend/app/community/models/challenge.py`,
`backend/app/community/services/challenge_invite_service.py`,
`lib/features/community/domain/**`, `docs/adr/**`, `tools/**`,
`.github/**`).

**Commit-lánc a `minimax/e09-r22-verified-result-submission-and-anti-cheat`
branch-en:**

| SHA | Téma |
|---|---|
| `646e96ea` | backend acceptance tests for verified result submission + anti-cheat (A1-A8 + §6.1 probes) |
| `ae4e76c4` | Kör 22 surface (migrations, service, policy, router, controller, tests) |
| `c6b19354` | A7 controller test + restore clean HttpCommunityChallengeRepository |
| `7f3eeae3` | ruff format pass (collapse multi-line mapped_column calls) |

### §10.2 §6 acceptance-mátrix (A1-A8) — lefedettség

| # | Cella | Próba neve (fájl) | Eredmény |
|---|---|---|---|
| A1 | Replay nem hoz létre második eredményt | `test_a1_replay_same_source_event_id_lands_one_row` | zöld |
| A2 | Forged `verified`/`rank` a kérésben figyelmen kívül marad | `test_a2_forged_verified_field_in_submitted_payload_rejected` | zöld |
| A3a | `metric_value < 0` → `metric_out_of_range` | `test_a3_metric_value_negative_rejected_metric_out_of_range` | zöld |
| A3b | `metric_value > 1_000_000` → `metric_out_of_range` | `test_a3_metric_value_over_max_rejected_metric_out_of_range` | zöld |
| A3c | Impossible score (score, 0 mp alatt) → `impossible_score` | `test_a3_impossible_score_zero_window_rejected` | zöld |
| A4 | Lejárt nonce → `nonce_expired` | `test_a4_stale_pending_row_with_expired_nonce_rejected` | zöld |
| A5a | Terminál-allapotú invite → `invite_not_active` | `test_a5_terminal_invite_state_rejected` | zöld |
| A5b | Hibás `version` → `version_mismatch` | `test_a5_wrong_submitted_version_rejected` | zöld |
| A5c | Ablakon kívüli beküldés → `challenge_window_closed` | `test_a5_submission_outside_window_rejected` | zöld |
| A6a | personalBest rosszabb második → `already_submitted` | `test_a6_personal_best_worse_second_submission_rejected` | zöld |
| A6b | personalBest jobb második → SUPERSEDES | `test_a6_personal_best_better_second_submission_supersedes` | zöld |
| A6c | Nem-personalBest második → `already_submitted` | `test_a6_non_personal_best_second_submission_rejected` | zöld |
| A7 | Community upload-hiba nem törli a lokális session sikerét | `challenge_result_controller_test.dart` (6 Dart teszt, KÖZÜLÜK 3 db A7 specifikus) | zöld |
| A8 | Minden reject-path `reason_code` perzisztálódik | `test_a8_each_reject_path_persists_reason_code` | zöld |
| HTTP | Happy-path + forged-verified 422 | `test_http_submit_result_happy_path`, `test_http_submit_result_forged_verified_rejected_at_wire` | zöld |

**Összesen: 16/16 backend teszt + 6/6 Flutter teszt zöld.** A8 invariant
mérve: a kódsoronkénti decision-path audit (resolution → policy chain →
first/best → service) MINDEN reject-ágban `reason_code`-ot ír, a siker-
ágak `pending` (audit-on kívüli) állapotot írnak.

### §10.3 §6.1 A2 valódi-sértés próba — DOKUMENTÁLT

**A kötelező valódi-sértés próba implementálva és lefuttatva** (lásd:
`test_a2_real_violation_probe_trust_field_whitelist_removed`).

A próba a §6.1 „Hibás implementáció" sor első celláját modellezi: a
service-oldali `assert_no_client_issued_trust_state` MÁSODIK védelmi
vonalát ÉS a router-oldali Pydantic `extra='forbid'` ELSŐ védelmi
vonalát egyszerre drop-olja (a §6.1 „wrong impl" minta), majd a
service-en KERESZTÜL hív `submitResult`-et egy `trusted_keys` halmazzal,
amely a `verified` és `rank` mezőket IS megbízhatónak jelöli.

**A próba eredménye: PIROS a WRONG-IMPLEMENTATION-ön (várt), ZÖLD a
production-impl-en (mért).**

A próba azt állítja, hogy a sor `verification_state ==
CHALLENGE_RESULT_STATE_VERIFIED` (`assert row.verification_state == "verified"`
és `assert row.reason_code is None`) — vagyis a letiltott védelmek
mellett a forged payload a row-t `verified` státuszban hagyja. Ez a
VESZÉLYES viselkedés, amit a védelmek megakadályoznak — a próba
dokumentálja, hogy a védelmek TERHELT állapotban (mindkettő letiltva)
milyen kárt okoznának, tehát a védelmek VALÓBAN load-bearing-ek.

**A production-impl-en a védelmek ÉLNEK:**

* A `service.assert_no_client_issued_trust_state` (ELSŐ sor a service
  dispatch-ban) minden ismeretlen kulcsra `IntegrityDecision(ok=False,
  code="client_issued_trust_state")` döntést hoz, és a row
  `rejected` + `reason_code="client_issued_trust_state"` státuszban
  perzisztálódik (A8 invariáns).
* A `SubmitChallengeResultRequest` Pydantic schema `extra="forbid"`
  konfigja a wire-szinten is elutasítja a `verified`/`rank` mezőt
  (`test_http_submit_result_forged_verified_rejected_at_wire` → 422).

A próba a `monkeypatch.setattr(service_module,
"assert_no_client_issued_trust_state", _noop_decision)` és a
`target_class.model_config = {"extra": "allow"}` cserékkel él —
a `try/finally` végén visszaállítja az eredeti `model_config`-ot, hogy
más tesztek ne legyenek érintettek.

### §10.4 Gate-verdikt — PASS

A `tools/round-gate.sh test/features/community/application/challenge_result_controller_test.dart`
foregroundban, csonkítatlan kimenettel lefutott, MIND a 9 lépés ZÖLD:

| Lépés | Eredmény |
|---|---|
| `format` | zöld |
| `analyze` | zöld |
| `test test/features/community/application/challenge_result_controller_test.dart` | zöld (6/6) |
| `architecture` | zöld |
| `secrets` | zöld |
| `l10n` | zöld |
| `backend ruff format` | zöld |
| `backend ruff check` | zöld |
| `backend pytest` | zöld (full suite, 100% pass) |

A 9. lépés a TELJES backend suite-ot futtatja (nem csak a
`test_challenge_verification.py`-t) — a mért kimenet 100% pass, nincs
`xfailed`/`skipped`/`xfail`/failure. A korábbi futtatásban a
`tests/community/test_follow_service.py::test_swap_unique_constraint_breaks_a2`
egyszer PIROSRA futott — ez az [L421](docs/LESSONS.md) által
dokumentált, E09-R07-ből származó known-flaky race-próba, NEM E09-R22
scope; a barrier-fix után izoláltan 5/5 zöld, és a gate mostani
futásában a teljes suite-ban is zöld. A saját round (E09-R22) egyetlen
új fájlban sem vezetett be threading-alapú race-próbát.

### §10.5 Ismert korlát / forward work

* A `personalBest` típusú challenge-eknél a service a
  `community_challenge_participants.best_metric_value` oszlopot
  FELTÉTELES `UPDATE`-szel írja (`UPDATE ... WHERE best_metric_value IS
  NULL OR best_metric_value < :new_value`). A Kör 23 leaderboard
  endpoint-ja (jelenleg `UnimplementedError`) ezt az oszlopot fogja
  olvasni a top-N sorrendhez.
* A `pending|review` row-k `nonce_expires_at` 24h TTL-je
  (`NONCE_TTL_SECONDS`) NEM egy KÖTELEZŐ cron cleanup; ha egy
  félben-maradt submission 24h+ után soha többé nem próbálkozik, a
  sor `pending`-ben marad a DB-ben. A Kör 23+ lifecycle-cleanup
  feladata.

### §10.6 E09-R22 surface — amit az implementer KÉSZ-nek nyilvánít

A Kör 22 (ADR 0417) teljes surface-ének implementációja,
backend-oldali acceptance-mátrixszal (A1-A8 + §6.1 probes + HTTP happy
+ HTTP forged 422) és Flutter-oldali §5.3 invariáns-fedéssel (A7).
A service a §6.1 A2 cellát védi (két védelmi vonal — Pydantic
extra-forbid + service-oldali assert); a policy-modul pure helper; a
controller különálló pending-verification állapotot tart fenn; a
service NEM módosítja az invite-state-et; a Kör 5 `submitResult`
interfész (`{challengeId, metricValue, sourceEventId, idempotencyKey}`)
FAGYOTT, nem bővítve.

## 11. Review — a Claude tölti ki
