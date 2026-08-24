# ADR 0417 — Verified result submission és anti-cheat

- **Státusz:** Elfogadva (E09-R22 pre-flight, 2026-08-24)
- **Kör:** E09-R22 — Verified result submission és anti-cheat
- **Implementer motor:** MiniMax M3 — az ADR-t az orchesztrátor (Claude Sonnet 5)
  írta a pre-flightban (ADR 0055).
- **Epic:** Chapter 10 — Epic 9 (Community Platform), Kör 22 (a 32 kör közül a huszonkettedik)
- **Kontext-ADR-ek:** [0399](0399-flutter-community-domain-and-public-api.md)
  (Kör 5 — `CommunityChallengeRepository.submitResult`,
  `CommunityChallengeParticipantState`, `kCommunityChallengeMetricMinValue`/
  `kCommunityChallengeMetricMaxValue` MÁR élnek a `domain/**`-ban, tilos zóna,
  csak-hívás), [0415](0415-community-challenge-invite-lifecycle.md) (Kör 21 —
  `CommunityChallenge`/`CommunityChallengeParticipant`/`CommunityChallengeInvite`
  modellek, a §D6 explicit erre a körre bízta a `submitResult` service-oldali
  bekötését, a `challenge_repository_impl.dart` docstringje ugyanezt
  megerősíti), [0394](0394-ledger-sync-contract-and-merge.md) (Epic 8 — "a
  szerver soha nem fogad el kliens-oldali összesített értéket" precedens,
  amit ez a kör ugyanúgy alkalmaz a challenge-eredményre).
- **Sorszám-jegyzet:** a pipeline-prompt E09-R22-höz `0411`-et adott előre
  kiosztott ADR-ként, de ez a szám MÁR foglalt —
  `docs/adr/0411-iconography-and-guitar-glyph-contract.md`. A
  `tools/round-slots.py reserve-adr --round E09-R22` friss számot adott:
  **`0417`**.
- **Visszakeresés (ADR 0312, pre-flight §4.9):**
  `node tools/knowledge-rag.mjs --corpus lessons,halts,adr --top 5 "verified
  result submission anti-cheat server never trusts client verified rank"` →
  **L414** (E09-R03: egy 282/282-zöld teszt-suite mellett is élt egy MAJOR
  biztonsági hiba, amit csak a reviewer SAJÁT, a jelentett tesztkészlettől
  FÜGGETLEN mutation-próbája fogott meg) — **közvetlenül alkalmazandó**: a
  brief §6.1 saját "valódi-sértés próbája" (A2-re, forged `verified`) a
  MINIMÁLIS védelem, a review-nak L414 mintája szerint saját, független
  mutation-próbát is kell futtatnia, nem elég az implementer sajátját
  elfogadni. `node tools/knowledge-rag.mjs --corpus lessons,halts --top 5
  "replay deduplication nonce idempotent submission migration alembic"` →
  nincs közvetlenül alkalmazható találat a nonce-mechanizmusra (a
  kódbázisban ez az ELSŐ nonce-fogalom, lásd D3 lent), de az `E09-R02`
  (Community backend modul + első Alembic migráció) és a Kör 21 idempotency-
  mintája (`post_service.py::_existing_post_by_idempotency_key`, DB unique +
  `IntegrityError`-újraolvasás) közvetlenül átvehető a replay-dedupra (D2).
  `node tools/knowledge-rag.mjs --top 5 "verified result submission
  anti-cheat challenge_verification_service integrity_policy nonce replay"` →
  a kör saját SDD-fejezete (`docs/sdd/10-epic-09-community-platform.md`
  "Kör 22" szakasz) és a `19.4 Anti-cheat` szakasz — a brief §3/§5 ezt hűen
  tükrözi, nincs eltérés.

## Kontextus

**Mért 2026-08-24-én, a pre-flightban (ez a §0.0 hordozza a teljes
tényellenőrzést, a brief eredeti szövege felülíródik):**

1. **A `challenges.py` router és a `challenge_repository_impl.dart` HIÁNYZIK
   a brief eredeti `allowed_paths`-ából, de a feature nélkülük nem valódi.**
   A Kör 21 `challenge_repository_impl.dart` docstringje szó szerint
   rögzíti: *"The 2 result / leaderboard methods (`submitResult` /
   `leaderboard`) raise `UnimplementedError` — Kör 22 / 23 scope, the Kör 21
   `allowed_paths` does not include their wire surfaces (the §0.0 D6 / ADR
   0415 §D6 scope-shrink)."* — az ADR 0415 §D6 pedig explicit kimondja:
   *"Egy jövőbeli kör (Kör 22 eredmény-beküldés) a §D6 horgot használja: a
   `submitResult` repository-metódus MÁR definiálva van, csak a
   service-oldali bekötés hiányzik."* A `challenges.py` router MA csak
   invite/accept/decline/cancel endpointokat ad
   (`grep -n "^@router\." backend/app/community/routers/challenges.py` →
   4 találat, mind invite-lifecycle). Ha ez a kör csak a
   service/policy/model réteget építi meg HTTP endpoint és kliens-hívás
   nélkül, a "verified result submission" funkció nem érhető el
   végponttól-végpontig — ez a `no-demos-real-functionality` elv sérelme
   lenne. **`allowed_paths` bővítve** (lásd lent) mindkét fájllal; a
   bővítés indoka MÉRT hívási-lánc hiány, nem feltételezés (§1 pre-flight
   szabály 2. pontja).
2. **A "participant-állapot" validáció (§3) OLVASÁS, nem ÍRÁS — az `active`
   invite-állapot ma elérhetetlen.** `grep -rn "CHALLENGE_INVITE_STATE_ACTIVE"
   backend/app/community/` → az érték csak DEKLARÁLVA és az allowlistben
   szerepel, **0 hozzárendelés-hely** van a kódban (`accept_invite` az
   `accepted` állapotba visz, onnan `active`-ba SENKI nem viszi tovább). A
   brief eredeti "A Kör 21 challenge-lifecycle MA `active` állapotig jut"
   állítása **elérhetetlen cél-státusz** volt (§1 pre-flight szabály 1.
   pontja) — TÉVES. Egyik A1–A8 acceptance-cella sem teszteli az
   invite-állapot előrehaladtatását (`active`/`completed`/`forfeited`
   írását) — ez egy KÉSŐBBI kör dolga (feltehetően a Kör 23 leaderboard-
   lezárás). Ez a kör tehát a beküldést az `invite.state ∈ {accepted,
   active}` halmaz ellen validálja (forward-compatible: az `active` benne
   marad az ellenőrzésben, még ha ma sosem is fordul elő), és
   **elutasítja**, ha az invite terminális állapotban van
   (`declined`/`expired`/`cancelled`/`completed`/`forfeited`) — de NEM ír az
   invite-sorba. Lásd D1.
3. **A "server-issued nonce" nem kliens-kerülőút, hanem szerver-belső
   bekönyvelés — a Kör 5 `submitResult` interfész NEM bővül.**
   `lib/features/community/domain/repositories/challenge_repository.dart`
   `submitResult` szignatúrája (`challengeId`, `metricValue`,
   `sourceEventId`, `idempotencyKey`) **fagyott** (Kör 5, ADR 0399, nincs az
   `allowed_paths`-on) — nincs benne kliens-oldali nonce-mező, és nem is
   lesz: a "server-issued nonce" a szerver SAJÁT, a `challenge_result` sorhoz
   kötött, TTL-lel ellátott bekönyvelő tokenje, amit a szerver az ELSŐ
   feldolgozási kísérletkor generál és tárol — a kliens sosem látja/küldi
   vissza. Az A4 cella ("lejárt nonce elutasított") ezért a szerviz-rétegen,
   közvetlenül fabrikált, már lejárt `nonce_expires_at`-tal rendelkező sorral
   tesztelendő, NEM egy HTTP round-trippel. Lásd D3.
4. **A metric-range mérete a MÁR élő kliens-kontraktusból jön, nem
   feltételezésből.** `lib/features/community/domain/entities/
   community_challenge.dart`: `kCommunityChallengeMetricMinValue = 0`,
   `kCommunityChallengeMetricMaxValue = 1000000` — a
   `CommunityChallengeParticipantState` konstruktor MA is ezt kényszeríti ki
   kliens-oldalon. Az `integrity_policy.py` metric-range ellenőrzése
   UGYANEZT a `[0, 1000000]` tartományt alkalmazza szerver-oldali
   védelemként (a kliens-oldali kényszer megkerülhető, a szerveré nem) —
   nem talál ki új számot. Lásd D4.
5. **Az eredmény-sor a `community_challenge_participants` sorhoz kötődik,
   nem közvetlenül az invite-hoz.** A Kör 21 `CommunityChallengeParticipant.
   best_metric_value` oszlop docstringje szó szerint: *"the Kör 22 results
   surface — NULL until the participant submits a verified result."*
   (`grep -n "best_metric_value" backend/app/community/models/challenge.py`)
   — ez a MÁR kijelölt írási felület, `grep -rn "best_metric_value"
   backend/ lib/` szerint MA sehol nem íródik (mindig `None`/`NULL`), tehát
   ennek a körnek nincs írási-tulajdon ütközése. A `challenge_result`
   táblának `participant_id` FK-t kell vezetnie a
   `community_challenge_participants.id`-ra (NEM az invite-ra) — a
   `participant_profile_id`/`challenge_id` innen már elérhető. Lásd D5.

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

## Döntés

### D1 — A "participant-állapot" ellenőrzés olvasás-only; a szerver az `invite.state ∈ {accepted, active}` halmazt kényszeríti, nem ír bele

A `challenge_verification_service.py` a beküldő profilhoz és a
`challenge_id`-hoz tartozó `CommunityChallengeInvite` sort OLVASSA (a
`community_challenge_participants` sor létezése MÁR bizonyítja, hogy volt
egy `accepted` állapotú invite — a `accept_invite` service hozza létre
mindkettőt egy tranzakcióban). Ha az invite állapota terminális
(`declined`/`expired`/`cancelled`/`completed`/`forfeited`), a beküldés
elutasított, `reason_code="invite_not_active"`. A szolgáltatás NEM módosítja
az `invite.state`-et — az `accepted → active → completed | forfeited`
átmenetek egy KÉSŐBBI kör (feltehetően Kör 23) dolga, `challenge_invite_
service.py` nincs az `allowed_paths`-on.

### D2 — Replay-dedup: DB unique constraint `(participant_id, source_event_id)`, a Kör 11/21 idempotency-mintája

A `community_challenge_results` táblán `UNIQUE(participant_id,
source_event_id)`. A service előbb megpróbál INSERT-elni; `IntegrityError`
esetén rollback + újraolvasás a meglévő sor alapján (mint
`post_service.py::_existing_post_by_idempotency_key` és az ADR 0415 D4) — ez
az A1 cella bizonyítéka. A `idempotency_key` (a Dart interfészből érkező
mező) a HTTP-szintű retry-biztonságot adja (ugyanaz a kérés kétszer
elküldve ugyanazt a választ kapja), a `source_event_id` a domain-szintű
replay-dedupot (ugyanaz a lokális gyakorlás-esemény nem hoz létre két
eredményt) — a kettő KÜLÖNBÖZŐ tengely, mindkettő a request-payloadból jön.

### D3 — A "server-issued nonce" szerver-belső TTL-es bekönyvelés a `challenge_result` soron, nem kliens-kerülőút

A `community_challenge_results` tábla vezet egy `nonce` (szerver-generált
`uuid4`) és egy `nonce_expires_at` oszlopot. A szerver az ELSŐ feldolgozási
kísérletkor (az INSERT pillanatában) generálja és tárolja — a nonce célja
nem a kliens hitelesítése (arra az auth-JWT szolgál), hanem egy belső
bekönyvelési ablak, ami után egy FÉLBEN maradt (pl. anomáliavizsgálatra
váró) beküldés véglegesen elutasítottá válik, ha a döntés nem születik meg
időben — ez véd az ellen, hogy egy `pending`/`review` állapotú sor
korlátlan ideig blokkolja az adott `(challenge, participant)` pár
`first`-policy-jú újrapróbálkozását. Az A4 teszt közvetlenül a szervizen
keresztül fabrikál egy már lejárt `nonce_expires_at`-tal rendelkező sort, és
a nonce-lejárat utáni újrapróbálkozást méri.

### D4 — Metric-range: a MÁR élő kliens-kontraktus `[0, 1000000]` tartománya, nem új szám

Az `integrity_policy.py` a `kCommunityChallengeMetricMinValue`/
`kCommunityChallengeMetricMaxValue` (`community_challenge.dart`) Python-oldali
tükreként `METRIC_VALUE_MIN = 0`, `METRIC_VALUE_MAX = 1_000_000` konstansokat
vezet be (ugyanaz a szám, két nyelven, dokumentált eredettel a
kommentben). Az A3 "impossible score" cella emellett egy MÁSODIK,
idő-alapú ellenőrzést is végez (a metric és az eltelt idő aránya fizikailag
lehetetlen — pl. egy `durationSeconds` metrikájú challenge-nél
`metric_value < 0` vagy egy `score` metrikájú challenge-nél a maximumot
nulla idő alatt elérő beküldés) — ez utóbbi arány-küszöböt az implementer
a §6.1 S3-mintája szerint (alatta/rajta/fölötte cellahármas) a
`test_challenge_verification.py`-ban rögzíti, konkrét `python3 -c`
számítással dokumentálva.

### D5 — `challenge_result.py`: `participant_id` FK a `community_challenge_participants.id`-ra, a `best_metric_value` írása ehhez a körhöz tartozik

A `community_challenge_results` tábla oszlopai: `id`, `public_id` (uuid),
`participant_id` (FK `community_challenge_participants.id`, CASCADE),
`source_event_id` (string), `idempotency_key` (string), `metric_value`
(int), `verification_state` (`pending|verified|unverified|rejected|review`,
CHECK constraint, a §3 5 értéke), `reason_code` (nullable string, audit),
`nonce` (uuid), `nonce_expires_at` (datetime), `submitted_at`, `decided_at`
(nullable). `UNIQUE(participant_id, source_event_id)` (D2). A
`challenge_verification_service.py` a `verified` döntés után egy
feltételes `UPDATE community_challenge_participants SET best_metric_value =
:new WHERE id = :participant_id AND (best_metric_value IS NULL OR :policy)`
hívással írja a personal-best felületet (a `challenge.py` modell-fájlt nem
kell módosítani, csak a MÁR létező oszlopot írni egy másik service-ből) — a
`:policy` az A6 first/best cella challenge-típusonkénti ága (D6).

### D6 — First/best policy: `personalBest` típus = best-of, a többi típus = first-wins

A brief `metric` mezője szabad szöveg, a `type` (`friends`, `club`,
`dailyCommunity`, `periodicGlobal`, `personalBest`) az 5 ismert érték
(D1, ADR 0415). Az SDD 19.4/22.1 "personal bestet" külön nevesíti — a
`personalBest` típusú challenge-nél egy újabb, jobb (a `metric` szemantikája
szerint magasabb VAGY alacsonyabb — a challenge definíció egy jövőbeli
`higher_is_better` mezőn dönt, amíg az nincs, a policy MINDIG "magasabb jobb"
feltevéssel dolgozik, dokumentálva a service docstringjében) beküldés
felülírja a korábbi `best_metric_value`-t. A többi 4 típusnál (verseny egy
konkrét, lezáruló eseményhez kötve) az ELSŐ verified beküldés dönt, a
további beküldések `verification_state="rejected"`,
`reason_code="already_submitted"` választ kapnak — ez az A6 cella két ága.

### D7 — Router: `POST /community/challenges/{challenge_public_id}/results`, a Kör 21 minta folytatása

A `challenges.py` router egy ÚJ `post_submit_result` endpointot kap, a Kör
21 `post_create_invite` szerkezetét követve (session/commit helperek
újrafelhasználva, `CurrentUser` DI, inline Pydantic `SubmitChallengeResult
Request`/`ChallengeResultOut`). A `lib/.../challenge_repository_impl.dart`
`submitResult` az `acceptInvite` mintáját követi
(`_client.post(url, data: {...})`, `Failure` → rethrow).

## Elutasított alternatívák

- **Kliens-oldali nonce round-trip** (a submit interfészt bővítve egy
  `nonce` paraméterrel) — elutasítva: a Kör 5 `submitResult` interfész
  fagyott, nincs az `allowed_paths`-on, és egy kétlépéses "kérj nonce-ot,
  majd küldd vissza" flow egy teljesen új endpointot igényelne, amit egyik
  acceptance-cella sem indokol.
- **Az invite-állapot előreléptetése ebben a körben** (`accepted → active →
  completed`) — elutasítva: `challenge_invite_service.py` nincs az
  `allowed_paths`-on, és egyik A1–A8 cella sem teszteli ezt az átmenetet;
  a scope-bővítés indokolatlan lenne.
- **Új `challenge_result_schemas.py` fájl a Pydantic request/response
  modelleknek** — elutasítva: a Kör 21 `challenges.py` a saját
  request/response modelljeit inline tartja (`CreateChallengeInviteRequest`,
  `ChallengeInviteOut`), a konzisztencia ezt a mintát folytatja.

## Következmények

- A `challenges.py` router és a `challenge_repository_impl.dart`
  bekerül az `allowed_paths`-ba — a kör MOST már valódi, végponttól
  végpontig működő funkciót szállít, nem csak egy izolált service-réteget.
- A `community_challenge_participants.best_metric_value` ELSŐ írója ez a
  kör — a Kör 23 leaderboard erre a mezőre épülhet olvasás-only módon.
- Az invite-állapot előreléptetése (`active`/`completed`/`forfeited`)
  nyitva marad egy jövőbeli kör számára — dokumentált hiány, nem hallgatólagos.

## A visszavonás feltétele

Felülvizsgálandó, ha egy jövőbeli kör (feltehetően Kör 23) az invite-állapot
`accepted → active → completed | forfeited` átmeneteit megépíti — ekkor a D1
"olvasás-only" korlátozása feloldható, és a "participant-állapot" ellenőrzés
szigorítható a ténylegesen aktív állapotra. Felülvizsgálandó, ha a
`personalBest` challenge-definíció egy explicit `higher_is_better` mezőt
kap (D6 feltevése ekkor kódba írható konfigurációvá válik).
