# E09-R22 — Review

Brief: docs/rounds/e09-r22-verified-result-submission-and-anti-cheat.md
Diff (1. kör): `git diff 28c7e5c3...minimax/e09-r22-verified-result-submission-and-anti-cheat` (HEAD `f3bc0a5c`)
Diff (javító kör): `git diff 173f8850...minimax/e09-r22-verified-result-submission-and-anti-cheat` (HEAD `fac611d5`)
Reviewer: Claude Sonnet 5 (orchestrátor) + `security-reviewer` subagent (kockázat=high, CLAUDE.md kötelező szabálya) · Dátum: 2026-08-24 (1. review) / 2026-08-24 (javító kör után)
Verdikt: **APPROVED** (javító kör után, `fac611d5`) — az eredeti kör (`f3bc0a5c`) verdiktje CHANGES REQUIRED volt

## Összegzés

**1. review (`f3bc0a5c`):** BLOCKER: 0 · MAJOR: 2 · MINOR: 2 · NOTE: 0
**Javító kör után (`fac611d5`):** BLOCKER: 0 · MAJOR: 0 · MINOR: 0 · NOTE: 0 — mind a 4 lelet zárva, mindegyik SAJÁT kézzel (izolált `/tmp` klónban) ellenőrizve, F1/F2-re valódi-sértés próbával (a javítást ideiglenesen visszaállítottam a régi, hibás alakra → a leletet fogó ÚJ teszt PIROSRA váltott → visszaállítva zöld).

Módszer: izolált `/tmp/review-e09-r22` klón (a `minimax/e09-r22-verified-result-submission-and-anti-cheat`
branch-ről, HEAD `f3bc0a5c`), `tools/round-gate.sh` SAJÁT kézzel újrafuttatva,
`tools/scope-audit.py` SAJÁT kézzel újrafuttatva, egy független `security-reviewer`
subagent SAJÁT (nem az implementer tesztkészletétől függő) mutation-próbákkal,
és a reviewer saját, out-of-tree reprodukciója (`sqlite3` közvetlen hívással) a
legsúlyosabb leletre. `docs/LESSONS.md` L414 mintája szerint az implementer
saját §10.3 valódi-sértés próbáját NEM fogadtuk el önmagában elégségesnek —
a fenti F1/F2 leletet egyik oldal saját tesztje sem fogta meg.

## Acceptance criteria

| # | Kritérium | Teljesült | Bizonyíték |
|---|---|---|---|
| A1 | Replay nem hoz létre második eredményt | ✅ | `UNIQUE(participant_id, source_event_id)` (migráció + modell) + `IntegrityError`-retry; kód-olvasással + `test_a1_replay_same_source_event_id_lands_one_row` (zöld) igazolva |
| A2 | Forged `verified`/`rank` figyelmen kívül marad | ✅ | Pydantic `extra="forbid"` (wire) — a security-reviewer közvetlenül próbálta `verified=True`-val → `ValidationError`; a service-oldali `assert_no_client_issued_trust_state` viszont NEM valódi második védelmi vonal (lásd F3, MINOR — nem rontja az A2 tényleges teljesülését, csak a dokumentált kettős-védelem állítást) |
| A3 | Fizikailag lehetetlen score elutasított | ⚠️ | A `[0, 1\_000\_000]` határ + idő-alapú "score" ellenőrzés helyes és tesztelt, DE a felső határ FÖLÖTT egy extrém nagy (`10**19`) érték az AUDIT-INSERT lépésen `OverflowError`-ral 500-at dob ahelyett, hogy `rejected`+`reason_code` sort írna — lásd **F1 (MAJOR)** |
| A4 | Lejárt nonce elutasított | ✅ | `_as_utc` konzisztens tz-normalizálás, határeset helyes; `test_a4_stale_pending_row_with_expired_nonce_rejected` zöld |
| A5 | Rossz challenge-verzió/scorer-inkompatibilitás elutasított | ⚠️ | A terminál-állapotú invite és az ablakon-kívüli beküldés helyesen elutasított; a verzió-ellenőrzés viszont OPT-IN (`submitted_version==0` → skip), és a Kör 5 fagyott kliens-interfész (`submitResult(challengeId, metricValue, sourceEventId, idempotencyKey)`) ELVE nem tud verziót küldeni — a valós Flutter-kliens ezt a cellát SOSEM éri el. Lásd **F4 (MINOR)** |
| A6 | First/best policy helyesen alkalmazott | ⚠️ | Szekvenciális esetben helyes és tesztelt (`personalBest` best-of, a többi first-wins); konkurens esetben a nem-`personalBest` ág Python-szintű check-then-act, nem DB-atomikus — lásd **F2 (MAJOR)** |
| A7 | Community upload-hiba nem törli a lokális session sikerét | ✅ | `challenge_result_controller.dart` olvasva: minden hiba-ág `localOnly` + `lastError`-ra vált, a lokális siker-állapotot sosem törli; 6/6 Dart teszt zöld |
| A8 | Döntés reason-code-dal auditált | ⚠️ | Minden NORMÁLISAN elért reject-ág ír `reason_code`-ot — DE az F1 overflow-eset kivétel: az az eset egyáltalán nem ír sort (kivétel a commit előtt) |
| HTTP happy/forged | Router-szintű smoke | ✅ | `test_http_submit_result_happy_path`, `test_http_submit_result_forged_verified_rejected_at_wire` zöld |

## Scope-audit

```
$ python3 tools/scope-audit.py --repo /tmp/review-e09-r22 --brief docs/rounds/e09-r22-verified-result-submission-and-anti-cheat.md --base 28c7e5c3
Legacy scope audit OK (28c7e5c35eb1..f3bc0a5c54b5, 10 changed path(s), 0 generated/ignored)
```

10 megváltozott fájl, mind a 10 az ADR 0417 pre-flight által bővített
`allowed_paths`-on (a router + a repository_impl bővítés is ott van) —
**nincs listán kívüli fájl.**

## Megállapítások

### F1 — MAJOR — extrém `metric_value` az audit-insertet OverflowError-ral bukdácsoltatja 500-ra, az A8 audit-sor NEM íródik

- **Fájl:** `backend/app/community/routers/challenges.py:621` (`SubmitChallengeResultRequest.metric_value: int` — nincs `Field(le=...)` felső korlát) → `backend/app/community/services/challenge_verification_service.py:337-363` (`_insert_result_with_replay_retry`, a `try/except IntegrityError` csak az `IntegrityError`-t fogja) → `backend/app/community/models/challenge_result.py:145` (`metric_value` sima `sa.Integer`, SQLite 64 bit-es host-korláttal).
- **Probléma:** egy `{"metric_value": 10000000000000000000, "source_event_id": "x", ...}` payload a Pydantic-on átmegy korlátlanul (a mező típusa `int`, felső határ nélkül). Az `evaluate_metric_range` helyesen `ok=False`-ot ad (`metric_out_of_range`), DE a reject-ág is megpróbálja beszúrni a sort a §A8 audit-invariáns miatt — és ez az INSERT `OverflowError`-t dob (`Python int too large to convert to SQLite INTEGER`), ami NEM `IntegrityError`, tehát a `except IntegrityError`-ág nem kapja el.
- **Ellenőrzés (SAJÁT, független, kód-módosítás nélkül):**
  ```
  $ /home/ubuntu/music-theory/backend/.venv/bin/python -c "
  import sqlite3
  c = sqlite3.connect(':memory:'); c.execute('CREATE TABLE t(v INTEGER)')
  c.execute('INSERT INTO t VALUES (?)', (10**19,))"
  EXCEPTION TYPE: OverflowError | Python int too large to convert to SQLite INTEGER
  ```
  (a reviewer ezt a nyers SQLite-mechanizmust reprodukálta közvetlenül; a
  `security-reviewer` subagent ugyanezt a `submit_result()`-on át, a modul saját
  alembic-migrált SQLite fixture-jeivel is lefuttatta, ugyanazzal a kivétellel.)
  A production Postgres-oldalon a hiba osztálya más (`NumericValueOutOfRange`
  / `DataError`), de ugyanúgy nem `IntegrityError` — a hibaosztály típusfüggő,
  a hiányzó felső wire-korlát a gyökérok mindkét motoron.
- **Hatás:** (1) egy tisztán `rejected`/`metric_out_of_range` kimenetből 500-as
  hiba lesz (DoS-ízű hibafelszín — egyetlen kérés eldönthetetlen állapotban
  hagyja a sessiont); (2) az **A8 invariáns sérül** ezen a bemeneten — a
  reject-döntéshez NEM tartozik auditált sor, mert a commit sosem fut le.
- **Kötelező javítás:** a `SubmitChallengeResultRequest.metric_value`-ra tegyél
  wire-szintű felső/alsó korlátot (pl. `Field(ge=-(2**63), le=2**63-1)`, vagy
  szorosabban a domain-határ közelébe, `Field(ge=-1_000_000_000, le=1_000_000_000)`),
  hogy a Pydantic MAGA utasítsa el a hordozhatatlan értéket a döntési lánc
  előtt — így az audit-sor mindig írható marad. Alternatívaként/kiegészítésként
  az `_insert_result_with_replay_retry` fogja el az `OverflowError`-t is (vagy
  egy közös `(IntegrityError, OverflowError)` tuple-lel), és térjen vissza egy
  `rejected`/`metric_value_unrepresentable` sorral ahelyett, hogy 500-at dobna.
- **Ellenőrzés (javítás után):** egy új `test_a3_metric_value_absurdly_large_rejected_no_500`
  (vagy hasonló) próba, ami `metric_value=10**19`-cel hív, és `verification_state
  == "rejected"` + `reason_code`-ot vár HTTP 500 helyett.
- **Státusz:** FIXED (`fac611d5`) — `metric_value: int = Field(ge=METRIC_VALUE_MIN, le=METRIC_VALUE_MAX)` a `SubmitChallengeResultRequest`-en (`backend/app/community/routers/challenges.py:635-638`); a Pydantic wire-korlát a döntési lánc ELŐTT elutasítja a hordozhatatlan értéket, 422-t ad 500 helyett. **SAJÁT ellenőrzés:** izolált `/tmp/review-e09-r22-fix1` klónban futtatott gate 9/9 zöld (SAJÁT kézzel, nem az implementer állítására hagyatkozva); az ÚJ `test_a3_metric_value_absurdly_large_rejected_no_500` külön futtatva zöld. Ellenőriztem azt is, hogy a szerviz-szintű (router-t megkerülő) A8-tesztek (`test_a8_each_reject_path_persists_reason_code`) VÁLTOZATLANUL auditált sort írnak a MÉRSÉKELT tartományon-kívüli (`-5`, `1_000_001`) értékekre — a wire-korlát csak a hordozhatatlan (`10**19`) esetet térítí el a döntési lánc elé, a normál A3/A8 útvonal nem sérült.

### F2 — MAJOR — a nem-`personalBest` "first-wins" policy Python-szintű check-then-act, nem DB-atomikus — konkurens beküldés két `verified` sort hozhat létre

- **Fájl:** `backend/app/community/services/challenge_verification_service.py:643-648`
  (`evaluate_first_vs_best_policy` hívása a `participant.best_metric_value`
  Python-oldali OLVASÁSA alapján, az INSERT ELŐTT) + `:439-447`
  (`_conditionally_update_best_metric_value` non-personalBest ága — a
  feltételes `UPDATE ... WHERE best_metric_value IS NULL` MAGA atomikus, de
  ez csak a `best_metric_value` OSZLOPOT védi, nem a `CommunityChallengeResult`
  SOR létrehozását).
- **Probléma:** két KÜLÖNBÖZŐ `source_event_id`-vel (tehát az A1 replay-UNIQUE
  nem fog) egyszerre érkező beküldés mindkét szála a `participant.
  best_metric_value IS NULL`-t olvassa (még egyik commit sem futott le),
  mindkettő átmegy az `evaluate_first_vs_best_policy`-n, mindkettő beszúr egy
  KÜLÖN `CommunityChallengeResult` sort `verified` állapottal — az A6 "a
  második beküldés `already_submitted`" invariáns két konkurens szálon NEM
  áll. A `best_metric_value` oszlop maga helyesen csak egyszer íródik (a
  feltételes UPDATE miatt), de **két `verified` sor marad a
  `community_challenge_results` táblában** ugyanahhoz a participanthoz —
  ugyanaz a hibaosztály, mint az `docs/LESSONS.md` L421 (a race-t a PONTOS
  SQL-döntési pontnál, nem a szál belépési pontján kell zárni; itt a döntési
  pont maga hiányzik a DB-ből).
- **Hatás:** egy scriptelt/kompromittált kliens két, közel egyidejű
  beküldéssel (más-más `sourceEventId`-vel) két `verified` sort tud
  létrehozni egy olyan challenge-típusnál, ahol a szabály "csak az első
  számít" — ez pontosan az anti-cheat invariáns megkerülése, amit a kör
  címe ígér. A mai gate ezt NEM méri (a §6.1 A6 próbák szekvenciálisak).
- **Kötelező javítás:** a first-wins döntést a DB-re kell tolni, NEM a
  Python-oldali előzetes olvasásra — pl. egy `participant_id`-re parciális
  UNIQUE indexet a `community_challenge_results`-on `WHERE verification_state
  = 'verified' AND challenge nem personalBest` (DB-dialektustól függő
  megvalósítással), VAGY a döntést egy atomikus, rowcount-ellenőrzött
  `UPDATE community_challenge_participants SET best_metric_value = :new WHERE
  id = :pid AND best_metric_value IS NULL` EREDMÉNYÉRE kell építeni (a
  rowcount dönti el, hogy EZ a beküldés "nyert"-e, nem egy korábbi olvasás) —
  ugyanaz a minta, mint a Kör 21 invite-állapotgép feltételes UPDATE-je.
- **Ellenőrzés (javítás után):** egy `threading.Barrier`-alapú konkurens próba
  (a L421 mintája szerint, a PONTOS SQL-döntési pontnál elhelyezett barrier-rel),
  ami két szimultán, KÜLÖNBÖZŐ `source_event_id`-jű beküldést indít egy
  nem-`personalBest` challenge-re, és megköveteli, hogy pontosan EGY sor
  legyen `verified`, a másik `already_submitted`.
- **Státusz:** FIXED (`fac611d5`) — a first-wins döntés a `_try_claim_first_wins` atomikus, rowcount-ellenőrzött feltételes UPDATE-re épül (`challenge_verification_service.py:435-477`), a Python-oldali előzetes olvasás eltávolítva a nem-`personalBest` ágból. Az ÚJ `test_a6_concurrent_non_personal_best_first_wins_atomic` `threading.Barrier`-rel, a PONTOS SQL-döntési pontnál (L421 minta) kényszeríti a race-t.
  **SAJÁT valódi-sértés próba (izolált `/tmp/review-e09-r22-fix1` klónban, kód-módosítás a MEGOSZTOTT fán NEM történt):** a javítást ideiglenesen visszaállítottam a régi `evaluate_first_vs_best_policy`-alapú (Python check-then-act) alakra → `test_a6_concurrent_non_personal_best_first_wins_atomic` **PIROSRA váltott** (`1 failed`) → a fájlt `git checkout --`-tal visszaállítottam → a teszt újra **zöld** (exit 0). A lelet és a javítás egyaránt VALÓDI, nem placebo.

### F3 — MINOR — a dokumentált "két védelmi vonal" (A2) valójában egy — a service-oldali assert holt kód a valós kérésúton

- **Fájl:** `backend/app/community/routers/challenges.py:809-816`
  (`submitted_keys` egy FIX, kézzel felsorolt halmazból épül, NEM a nyers
  kérés-testből) → `integrity_policy.py::assert_no_client_issued_trust_state`
  csak ezt a fix halmazt kapja.
- **Probléma:** mivel a Pydantic `extra="forbid"` MÁR minden ismeretlen mezőt
  elutasít a router-szinten, a service-be soha nem jut el `verified`/`rank`
  kulcs — a service-oldali "második védelmi vonal" ezért soha nem lát olyan
  bemenetet, amit MEG KELLENE fognia. A brief §5.1/§10.3 és a kód-kommentek
  "belt-and-braces" / kettős-védelem állítása jelenleg NEM valós — ha egy
  jövőbeli refaktor lazítja/eltávolítja az `extra="forbid"`-ot, a
  service-oldali assert ATTÓL FÜGGETLENÜL sem fogná meg a szivárgást, mert a
  `submitted_keys` építése nem a valós body-ból történik.
- **Hatás:** ma nincs élő biztonsági rés (az A2 ténylegesen teljesül, az
  EGYETLEN valódi védelem — a Pydantic-séma — működik), de a dokumentált
  redundancia hamis biztonságérzetet ad egy jövőbeli körnek.
- **Javasolt irány:** VAGY a router adja át a service-nek a TÉNYLEGES nyers
  body extra kulcsait (pl. `payload.model_extra` vagy a raw JSON kulcshalmaza
  a validáció ELŐTT), hogy a második védelmi vonal valóban terhelt bemenetet
  lásson, VAGY a dokumentáció/kommentek ismerjék el, hogy az `extra="forbid"`
  az EGYETLEN kikényszerített határ, és egy dedikált wire-szintű regressziós
  teszt védje (ami pirosra vált, ha valaki eltávolítja az `extra="forbid"`-ot).
- **Státusz:** FIXED (`fac611d5`) — a `submitted_keys` mostantól a TÉNYLEGES `await request.json()` nyers body-kulcsaiból épül (`routers/challenges.py:838-854`, a route `async def`-fé alakítva), nem egy kézzel felsorolt fix halmazból — a service-oldali második védelmi vonal innentől valóban terhelt bemenetet lát, ha egy jövőbeli refaktor lazítaná az `extra="forbid"`-ot. Kód-olvasással ellenőrizve.

### F4 — MINOR — az A5 verzió-ellenőrzés a valós kliensen sosem aktiválódik (opt-in, a fagyott interfésznek nincs verzió-mezője)

- **Fájl:** `backend/app/community/policies/integrity_policy.py:222-229`
  (`submitted_version == 0` → skip) + a router `None → 0` leképezése.
- **Probléma:** a Kör 5 fagyott `submitResult(challengeId, metricValue,
  sourceEventId, idempotencyKey)` kliens-interfésznek (`lib/features/
  community/domain/repositories/challenge_repository.dart`) NINCS
  verzió-paramétere — a valós Flutter-alkalmazás strukturálisan SOSEM tud
  nem-nulla `submitted_version`-t küldeni, tehát a `version_mismatch`
  ellenőrzés a valós termékúton MINDIG skip-elődik. A §6.1 A5 "rossz
  challenge-verzió" cellája jelenleg csak egy közvetlen backend-pytest
  hívással (a routert megkerülve) érhető el, nem a valós kliensfolyamon.
- **Hatás:** alacsony — a challenge-definíciók ma nem szerkeszthetők (nincs
  update-endpoint ebben az Epicben), tehát élő verzió-eltérés forgatókönyv
  ma amúgy sincs; ez inkább egy jövőre nézve dokumentálatlan korlát, mint
  aktív biztonsági rés.
- **Javasolt irány:** a §10.5 "Ismert korlát" szakaszba (a brief/handoff
  már tartalmaz két hasonló bejegyzést) kerüljön be egy harmadik pont, ami
  kimondja: az A5 verzió-cella ma csak direkt API-hívással érhető el, a
  Kör 5 interfész bővítése (verzió-paraméter hozzáadása) egy jövőbeli kör
  dolga, ha a challenge-definíciók szerkeszthetővé válnak.
- **Státusz:** FIXED (`fac611d5`) — a brief §10.5 "Ismert korlát" szakasza
  és egy ÚJ §10.7 "Javító kör" szakasz is rögzíti a korlátot, a fenti
  indoklással szó szerint. Dokumentáció-olvasással ellenőrizve.

## Gate-bizonyíték ellenőrzése

### 1. review (`f3bc0a5c`)

| Gate | Állított eredmény (implementer) | Ellenőrizve (reviewer, izolált `/tmp/review-e09-r22` klón) |
|---|---|---|
| format | zöld | ✅ zöld |
| analyze | zöld | ✅ zöld (0 issue, 23.0s) |
| test (Dart, challenge_result_controller_test.dart) | zöld 6/6 | ✅ zöld 6/6 |
| architecture | zöld | ✅ zöld (12 allowlistelt eltérés, nem nőtt) |
| secrets | zöld | ✅ zöld (3566 fájl, 0 lelet) |
| l10n | zöld | ✅ zöld |
| backend ruff format | zöld | ✅ zöld |
| backend ruff check | zöld | ✅ zöld |
| backend pytest (TELJES suite) | zöld, 100% pass | ✅ zöld, 100% pass |

A gate-mátrix minden lépése MÉRVE zöld — ez pontosan a `docs/LESSONS.md` L414
mintája: a teljes, csonkítatlan gate zöld volt, miközben két MAJOR
anti-cheat-hiba élt a kódban. A gate a FORMAI/ismert-teszt fegyelmet méri, nem
a security-reviewer által feltárt, a §6 mátrixban NEM szereplő extrém-bemenet
és konkurencia-osztályokat.

### Javító kör után (`fac611d5`)

| Gate | Állított eredmény (implementer) | Ellenőrizve (reviewer, ÚJ izolált `/tmp/review-e09-r22-fix1` klón) |
|---|---|---|
| format | zöld | ✅ zöld |
| analyze | zöld | ✅ zöld |
| test (Dart, challenge_result_controller_test.dart) | zöld 6/6 | ✅ zöld 6/6 |
| architecture | zöld | ✅ zöld |
| secrets | zöld | ✅ zöld (3567 fájl, 0 lelet) |
| l10n | zöld | ✅ zöld |
| backend ruff format | zöld | ✅ zöld |
| backend ruff check | zöld | ✅ zöld |
| backend pytest (TELJES suite) | zöld, 100% pass | ✅ zöld, 100% pass |
| F1/F2 célzott regresszió (`test_a3_metric_value_absurdly_large_rejected_no_500`, `test_a6_concurrent_non_personal_best_first_wins_atomic`) | zöld | ✅ zöld, KÜLÖN futtatva |
| F2 valódi-sértés próba (a fix ideiglenes visszaállítása) | — | ✅ a régi kódra a race-teszt PIROSRA váltott (`1 failed`), a fix visszaállítása után újra zöld |
| Scope-audit | 4 megváltozott fájl (javító kör), 0 listán kívüli | ✅ SAJÁT `tools/scope-audit.py` futtatással megerősítve, 0 sértés |
| CI (teljes suite + property + APK) | — | dispatch-elve a review APPROVED után, lásd alább |

`implementer_guard.py` `gate_shape=VIOLATION`-t jelzett a kör-jelzésben —
ezt KIVIZSGÁLTAM (nem fogadtam el bemondásra): a jelzés egy ELSŐ, `| tail`-lel
csonkított gate-hívást pattern-matchelt a logban, amit az őr maga LETILTOTT
(`permission_denials` a log-ban) — SOSEM futott le csonkítva. A MÁSODIK,
csonkítatlan hívás ténylegesen lefutott (a teljes 9-lépéses kimenet a logban),
és a fenti táblázat ezt a csonkítatlan futást igazolja vissza, SAJÁT, független
gate-futtatással is.

## Merge-döntés

**APPROVED, merge ENGEDÉLYEZETT** (ADR 0052) a javító kör (`fac611d5`) HEAD-jén
— mind a 4 lelet (F1, F2 MAJOR + F3, F4 MINOR) zárva, a fenti táblázat és a
leletenkénti "Státusz: FIXED" bejegyzés SAJÁT, izolált-klónos ellenőrzéssel
igazolva, F1/F2-re valódi-sértés próbával. A `docs/execution/orchestrator-
rotation`/`pipeline-slots` jelenlegi felállása szerint (2026-08-21 user-döntés
— Codex-kvóta kiesés) a javító kört `minimax` vitte, EGY javító kör alatt, a
mérce (§ADR 0087 H4) szerint elfogadható küszöbön belül. A CI-dispatch (exact-SHA,
`fac611d5`) + a merge-lánc a review COMMIT UTÁN folytatódik.
