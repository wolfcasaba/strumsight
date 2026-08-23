# E09-R21 — Community challenge és invite lifecycle

- **Státusz:** PREPARED (előre megírva 2026-08-22, kód olvasva: `main @ db6293f4`) → pre-flight revideálva 2026-08-23, kód újra-olvasva `main @ 77c42cf8`
- **Típus:** Chapter 10 (Epic 9 — Community Platform), Kör 21
- **Kör-azonosító:** `E09-R21`
- **Branch:** `<motor>/e09-r21-challenge-and-invite-lifecycle`
- **Előfeltétel:** `E09-R20` merge-elve
- **Brief szerzője:** Claude (Opus 5); pre-flight revízió: Claude Sonnet 5
- **Előre kiosztott ADR:** ~~`ADR 0410`~~ **`ADR 0415`** — a `0410` MÁR foglalt (`docs/adr/0410-media-upload-contract-and-object-store.md`, E09-R18). `tools/round-slots.py reserve-adr --round E09-R21` friss számot adott. Lásd [ADR 0415](../adr/0415-community-challenge-invite-lifecycle.md) a teljes döntéskörért.

**Kockázat = high, indoklás:** a kör egy szerveroldali, biztonság-releváns
állapotgépet vezet be (invite accept/decline/cancel), amelynek egyik
elsődleges kockázata pontosan az, hogy egy blockolt fél meghívást
küldhessen/fogadhasson (safety-regresszió a Kör 8 block-invariánshoz képest,
ADR 0402), egy másik pedig egy egyidejű accept+cancel race determinisztikus
kimenete (adatintegritás). Egyik `allowed_paths` fájl sem egyezik szó szerint
a router `high_risk_path_fragments` listájával, de a kockázat ettől
függetlenül valós — safety+concurrency, nem forma szerinti kulcsszó-egyezés.

## 0.0a Javító addendum (2026-08-23 23:00, `stopped` jelzés után, Claude Sonnet 5)

Az implementer `stopped`-ot jelzett: az `app_en.arb`/`app_hu.arb`-ba írt
ÚJ kulcsok a gate `l10n` lépésén (`dart run tool/ci/check_l10n_parity.dart`,
ami a `tool/gen_l10n_segments.dart` frissességi ellenőrzését hívja) piroson
buktak, mert ezek a fájlok **ADR 0307 §4 szerint GENERATED fájlok** — a
tényleges kézzel szerkesztett forrás a `lib/l10n/features/<feature>_<locale>.arb`
fragmentum, az aggregátumot a `dart run tool/gen_l10n_segments.dart --write`
állítja elő determinisztikusan a fragmentumokból. Mérve:
`tools/round-slots.py` `GENERATED_PATHS` halmaza pontosan `lib/l10n/app_en.arb`
és `lib/l10n/app_hu.arb`-ot tartalmazza (93-98. sor) — ezek a scope-audit
alól KIVÉTELEK, tehát nem is kellett volna felvenni őket az `allowed_paths`-ra.

**Javítás:** az `allowed_paths`-ra felkerül a tényleges kézzel szerkesztett
forrás: `lib/l10n/features/community_en.arb`/`lib/l10n/features/community_hu.arb`
(ez a feature MÁR rendelkezik ilyen fragmentum-fájlokkal, korábbi Community
körökből — az implementer az ÚJ `communityChallenge*` kulcsokat EZEKBE írja,
nem az aggregátumba). Az aggregátumot a `dart run
tool/gen_l10n_segments.dart --write` regenerálja — ez a lépés a §7 gate elé
kerül, az implementer promptjában explicit lépésként.

**0.0b javítás (2026-08-23 23:11, MÁSODIK `stopped` jelzés után):** a fenti
0.0a javítás TÉVESEN vette ki az `app_en.arb`/`app_hu.arb`-ot az
`allowed_paths`-ból — a `tools/round-slots.py` `GENERATED_PATHS` halmaza
KIZÁRÓLAG a párhuzamos kör-ütemezés slot-ütközés-detektálásából veszi ki
ezt a két fájlt, a ténylegesen futó `tools/scope-audit.py`-nak NINCS
generated-path kivétele (`grep -n "GENERATED" tools/scope-audit.py` → 0
találat) — a scope-audit minden, a diffben ténylegesen módosult fájlt az
`allowed_paths` ellen mér, függetlenül attól, hogy kézzel írták-e vagy
generálták. Az implementer helyesen futtatta a `--write`-ot, de ez a
`scope_audit=VIOLATION` jelzést váltotta ki (`path outside allowed scope:
lib/l10n/app_en.arb`/`app_hu.arb`). **Végleges javítás:** mindkét fájl-pár
szerepel az `allowed_paths`-on — a fragmentum (kézzel szerkesztett forrás)
ÉS az aggregátum (a `--write` által legálisan, a kör saját diffjeként
módosított generált kimenet).

## 0.0 Pre-flight brief-revízió (2026-08-23, Claude Sonnet 5)

A teljes mért-tény alapú indoklás [ADR 0415](../adr/0415-community-challenge-invite-lifecycle.md)
Kontextus szakaszában. Összefoglalva:

1. **A nyitó figyelmeztetés törölve/javítva.** `ChallengeV2` NEM létezik
   sehol a repóban (`grep -rn "ChallengeV2" . --include="*.py" --include="*.dart"`
   → 0 találat). A gamifikáció E08-R19 "Challenge V2" egy egyjátékos, eszközön
   futó napi kihívás-generátor (`DailyChallengeType`), strukturálisan
   összeegyeztethetetlen ezzel a körrel. A TÉNYLEGES, MÁR élő kompatibilis
   kontraktus a Community saját E09-R05 domainje: `ChallengeInviteState`
   (byte-azonos a lenti §5.1 állapotgéppel), `ChallengeType`,
   `CommunityChallengeDefinition`, `CommunityChallengeRepository`
   (`lib/features/community/domain/**`, ADR 0399, exportálva `public.dart`-ban).
   Ez a kör ezt a kontraktust implementálja, NEM a gamifikációt hívja.
2. **`allowed_paths` bővítve** (§1 pre-flight szabály 2. pontja — erőforrás-
   tulajdonlás mérve a tényleges hívási láncon: a screen önmagában nem
   fordulna, nincs mit `ref.watch`-olni):
   - `lib/features/community/data/repositories/challenge_repository_impl.dart` (ÚJ) — a Kör 5 `CommunityChallengeRepository` ELSŐ implementációja, a Kör 7 `relationship_repository_impl.dart` mintáját követve (provider a fájl alján).
   - `lib/features/community/application/controllers/challenge_controller.dart` (ÚJ) — a screen ezen keresztül éri el a repository-t, a Kör 20 `notification_controller.dart` mintáját követve.
   - `test/ui/ui_inventory_test.dart` — screen-számláló 74→75 (L420/L422 visszatérő drift-osztály, proaktív zárás ugyanabban a commitban).
   - ~~`lib/l10n/app_en.arb`, `lib/l10n/app_hu.arb`~~ **`lib/l10n/features/community_en.arb`, `lib/l10n/features/community_hu.arb`** (0.0a javítva — ezek a tényleges forrás-fragmentumok, ADR 0307 §4; az aggregátum GENERATED, `dart run tool/gen_l10n_segments.dart --write` állítja elő) — ÚJ `communityChallenge*` névtér (a gamifikáció MEGLÉVŐ `challenge*` kulcsaitól elkülönítve).
3. **Újrahasznosítandó, MÉRT minták (ne találj ki újat):**
   - Block-ellenőrzés: `query_filters.py::is_blocked_pair(db, profile_id_a=, profile_id_b=)` write-side hívás (mint `post_service.py`), NEM a `block_service.py` bővítése (ADR 0402 §D3 horog, lásd ADR 0415 D3).
   - Rate-limit: `backend/app/ratelimit.py::RateLimiter` (mint `routers/search.py`/`routers/handles.py`), `reset_rate_limiters()` teszt-hook.
   - Idempotency: DB unique constraint + előzetes olvasás + `IntegrityError` → rollback + újraolvasás (mint `post_service.py::_existing_post_by_idempotency_key`).
   - A5 cancel race: feltételes `UPDATE ... WHERE state IN (...)` + rowcount-ellenőrzés, NEM `SELECT ... FOR UPDATE` (nulla precedens a kódbázisban erre). A race-teszt `threading.Barrier`-je a PONTOS SQL-döntési pont elé kerül (egy `_before_transition` seam, mint a Kör 20 `_before_commit`-ja), NEM a szál belépési pontjára — L421 mérése szerint az utóbbi 10-ből 7-szer nem reprodukálja a race-t.
4. **Scope-szűkítés:** nincs publikus "challenge definíció létrehozása" HTTP
   endpoint ebben a körben (a §8 router-lépés csak invite/accept/decline/cancel-t
   sorol, egyik A1-A7 cella sem teszteli a létrehozást) — a tesztek a
   challenge-definíció sorokat közvetlenül a service/model rétegen keresztül
   hozzák létre. `club` challenge-típus strukturálisan elfogadott
   (`club_id` nullable oszlop), validáció/FK nélkül (Kör 24 horog, ADR 0402 §D4 mintája).
5. **NEM ez a kör dolga:** a `NOTIFICATION_TYPE_ALLOWLIST` MÁR tartalmazza
   a `challenge_invite`/`challenge_completed` értékeket
   (`backend/app/community/models/notification.py`), de az élő
   notification-bekötés (a `notifications/notification_service.py` hívása)
   ki van zárva az `allowed_paths`-ból — egy jövőbeli kör dolga, ugyanúgy,
   ahogy a Kör 20 sem kötötte be a reaction/comment/follow eseményeket.

```ai-router
schema_version = 1
risk = "high"
allowed_paths = [
  "backend/app/community/models/challenge.py",
  "backend/app/community/services/challenge_invite_service.py",
  "backend/app/community/routers/challenges.py",
  "backend/alembic/versions/e09_r21_0015_community_challenge.py",
  "lib/features/community/data/repositories/challenge_repository_impl.dart",
  "lib/features/community/application/controllers/challenge_controller.dart",
  "lib/features/community/presentation/screens/community_challenges_screen.dart",
  "backend/tests/community/test_challenge_invite_service.py",
  "test/features/community/presentation/community_challenges_test.dart",
  "test/ui/ui_inventory_test.dart",
  "lib/l10n/features/community_en.arb",
  "lib/l10n/features/community_hu.arb",
  "lib/l10n/app_en.arb",
  "lib/l10n/app_hu.arb",
  "docs/rounds/e09-r21-challenge-and-invite-lifecycle.md",
]
gate_tests = [
  "test/features/community/presentation/community_challenges_test.dart",
  "test/ui/ui_inventory_test.dart",
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

Aszinkron kihívás-meghívások és résztvevői állapotgép — a lejárat szerveridőből, timezone-független, minden átmenet szerveroldali policyvel.

## 2. Jelenlegi állapot — mért tények

- **JAVÍTVA (§0.0):** a gamifikáció E08-R19 "Challenge V2"-je egy egyjátékos
  napi kihívás-generátor, STRUKTURÁLISAN NEM kompatibilis ezzel a körrel —
  a valódi, MÁR élő kompatibilis kontraktus a Community saját E09-R05 domainje
  (`ChallengeInviteState`/`ChallengeType`/`CommunityChallengeDefinition`/
  `CommunityChallengeRepository`, `lib/features/community/domain/**`, ADR 0399).
  Ez a kör EZT implementálja — nincs implementáció, nincs provider, nincs
  backend model/service/router még.
- A Kör 8 block-szűrő (`query_filters.py::is_blocked_pair`, write-side hívás)
  és a Kör 20 notification-infrastruktúra (allowlist MÁR tartalmazza a
  challenge-típusokat, de az élő bekötés NEM ennek a körnek a dolga) MA
  készen áll az invite-hoz.
- A rate-limit primitívum (`backend/app/ratelimit.py::RateLimiter`) és az
  idempotency-key minta (`post_service.py::_existing_post_by_idempotency_key`)
  MA élő, újrahasznosítandó precedensek.

## 3. Scope

**Benne van:** challenge, participant, invite tábla version + időablak + verification policy · draft/sent/accepted/declined/expired/cancelled átmenetek · a Community SAJÁT (E09-R05, ADR 0399) challenge-definíció-kontraktusának ELSŐ implementációja · block, eligibility, feature-availability, invite rate-limit szerveroldali ellenőrzés · challenge list/detail Flutter képernyő offline cache-sel (repository-impl + controller + screen) · accepted challenge indítása deep linkkel a megfelelő Practice/Song flow-ba · timezone-független lejárat-számítás szerveridőből.

**NINCS benne (tilos):**

- A tényleges eredmény-beküldés és anti-cheat — Kör 22.
- Leaderboard — Kör 23.
- Publikus "challenge definíció létrehozása" HTTP endpoint (§0.0 pont 4) — a tesztek a definíciót közvetlenül a service/model rétegen át hozzák létre.
- Élő notification-bekötés (`notifications/notification_service.py` hívása) — a hely megvan (allowlist), a bekötés nem ez a kör.
- `docs/adr/**` — az ADR 0415-öt a Claude írja.

## 4. Engedélyezett fájlok

| Útvonal | Indok |
|---|---|
| `backend/app/community/models/challenge.py` | ÚJ |
| `backend/app/community/services/challenge_invite_service.py` | ÚJ |
| `backend/app/community/routers/challenges.py` | ÚJ |
| `backend/alembic/versions/e09_r21_0015_community_challenge.py` | ÚJ, `down_revision = "e09_r20_0014"` |
| `lib/features/community/data/repositories/challenge_repository_impl.dart` | ÚJ (§0.0 pont 2) — a Kör 5 `CommunityChallengeRepository` ELSŐ implementációja |
| `lib/features/community/application/controllers/challenge_controller.dart` | ÚJ (§0.0 pont 2) — a screen ezen keresztül éri el a repository-t |
| `lib/features/community/presentation/screens/community_challenges_screen.dart` | ÚJ |
| `backend/tests/community/test_challenge_invite_service.py` | ÚJ — a §6 cellái |
| `test/features/community/presentation/community_challenges_test.dart` | ÚJ |
| `test/ui/ui_inventory_test.dart` | screen-számláló 74→75 (§0.0 pont 2, L420/L422) |
| `lib/l10n/features/community_en.arb`, `lib/l10n/features/community_hu.arb` | ÚJ `communityChallenge*` kulcsok a fragmentumban (§0.0a) |
| `lib/l10n/app_en.arb`, `lib/l10n/app_hu.arb` | GENERATED — `dart run tool/gen_l10n_segments.dart --write` regenerálja a fragmentumokból; a `scope-audit.py`-nak NINCS generated-kivétele, tehát explicit listaelem kell (§0.0b) |

**Tilos zóna:** `lib/features/community/domain/**` (csak-hívás, a kontraktus MÁR él, ADR 0399) · `lib/features/gamification/**` belső fájljai (csak `public.dart`) · `lib/features/practice/**`/`lib/features/songs/**` belső fájljai · `backend/app/community/policies/**` és `backend/app/community/services/block_service.py` (csak-hívás, ADR 0402 §D3, lásd ADR 0415 D3) · `docs/adr/**` · `tools/**` · `.github/**`

## 5. Kötött architekturális döntések (ADR 0415)

### 5.1 A lifecycle EXPLICIT állapotgép, minden átmenet szerveroldali policyvel

`draft → sent → accepted | declined | expired | cancelled`, majd `accepted → active → completed | forfeited | expired` — érvénytelen átmenet a szerveren elutasított.

**NEM elfogadható gyengítés:** egy kliensoldali állapotváltás, ami "optimistán" előreugorja az állapotgépet a szerver megerősítése előtt, majd csendben visszaáll hiba esetén — ez inkonzisztens UI-t és versenyhelyzetet okozna.

### 5.2 A lejárat SZERVERIDŐBŐL számítható, timezone-független

Az `endsAt` UTC timestamp; a lejárat-ellenőrzés a szerver óráján megy, nem a kliens helyi idején.

### 5.3 Ugyanaz a meghívás retry esetén NEM duplikálódik

Az invite-létrehozás idempotens, ugyanazzal az idempotency-key-mintával, mint a Kör 11 post-create (DB `UNIQUE(challenge_id, inviter_profile_id, invitee_profile_id, idempotency_key)` + előzetes olvasás + `IntegrityError` → rollback + újraolvasás — ADR 0415 D4).

### 5.4 A block-ellenőrzés a meglévő `is_blocked_pair`-t hívja (ADR 0415 D3)

`challenge_invite_service.py` invite-létrehozáskor és accept-kor
`query_filters.py::is_blocked_pair(db, profile_id_a=, profile_id_b=)`-t hívja
közvetlenül — a `block_service.py` (tilos zóna) NEM bővül.

### 5.5 A5 cancel race: feltételes UPDATE, NEM pesszimista lock (ADR 0415 D5)

Minden átmenet egyetlen `UPDATE ... WHERE id = :id AND state IN
(:megengedett_forrás_állapotok)` + a módosított sorok számának ellenőrzése.
Nincs `SELECT ... FOR UPDATE` — nulla precedens rá a kódbázisban. A §10
race-teszt `threading.Barrier`-je egy `_before_transition` seam-en, KÖZVETLENÜL
a feltételes `UPDATE` előtt szinkronizál, NEM a szál belépési pontján (L421 —
az utóbbi 10-ből 7-szer nem reprodukálja a race-t).

## 6. Acceptance criteria

| # | Kritérium | Bizonyíték |
|---|---|---|
| A1 | Invalid transition (pl. `declined → accepted`) elutasított | `test_challenge_invite_service.py` |
| A2 | Lejárt invite accept-je elutasított | `test_challenge_invite_service.py` |
| A3 | Blockolt fél nem hívható meg és nem hívhat meg | `test_challenge_invite_service.py` |
| A4 | Duplikált invite retry nem hoz létre második rekordot | `test_challenge_invite_service.py` |
| A5 | Cancel race (egyidejű accept + cancel) determinisztikusan dől el | `test_challenge_invite_service.py` |
| A6 | Deep link csak kompatibilis Practice/Song flow-ra mutat | `community_challenges_test.dart` |
| A7 | A lejárat-számítás timezone-független (szerveridő) | `test_challenge_invite_service.py` |

### 6.1 Mérce-mátrix — melyik hibás implementációt melyik cella fogja pirosra

| Hibás implementáció | Melyik cella vált PIROSRA |
|---|---|
| A `declined` állapotból `accepted`-be lehet lépni | A1 |
| Egy lejárt invite accept-je sikeres marad | A2 |
| Egy blockolt user meghívása átmegy a policy-n | A3 |
| Két retry két külön invite-rekordot hoz létre | A4 |
| Az accept+cancel race mindkét ága sikeres UPDATE-et ír (rowcount-ellenőrzés nélkül) | A5 |
| A kliens helyi ideje alapján dől el a lejárat | A7 |

**Valódi-sértés próba #1 (KÖTELEZŐ, §10-ben dokumentálva):** vedd ki az idempotency-key ellenőrzést az invite-create hívásból, futtasd a backend pytest-et két egymást követő azonos kéréssel → az **A4** cellának PIROSNAK kell lennie (két invite jön létre) → állítsd vissza.

**Valódi-sértés próba #2 (KÖTELEZŐ, §10-ben dokumentálva, ADR 0415 D5):** a race-tesztben cseréld a feltételes `UPDATE ... WHERE state IN (...)`-t egy feltétel nélküli `UPDATE`-re (rowcount-ellenőrzés nélkül) → az **A5** cellának PIROSNAK kell lennie (mindkét konkurens ág sikeresen ír, inkonzisztens végállapot) → állítsd vissza. A `threading.Barrier`-t a `_before_transition` seam-be tedd, ne a szál elejére (L421) — a review a próbát izolált klónban 10-15×-ösen újrafuttatja elfogadás előtt.

## 7. Kötelező ellenőrzések

```bash
tools/round-gate.sh test/features/community/presentation/community_challenges_test.dart test/ui/ui_inventory_test.dart
```

A backend oldal külön, önálló parancs (NEM láncolva):

```bash
cd backend && python -m pytest tests/community/test_challenge_invite_service.py -q
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

1. Migráció: `community_challenges`, `community_challenge_participants`, `community_challenge_invites` (`down_revision = "e09_r20_0014"`).
2. `challenge.py` modell — a `ChallengeInviteState`/`ChallengeType` string-enumok byte-azonosak a MÁR élő `community_challenge.dart` wire-értékeivel (§0.0 pont 1, ADR 0415 D1) — NEM a gamifikációból származnak.
3. `challenge_invite_service.py` — az állapotgép feltételes `UPDATE`-tel (ADR 0415 D5), `is_blocked_pair`-t hívó block-ellenőrzéssel, `RateLimiter`-t hívó rate-limittel, idempotency-key mintával (ADR 0415 D4).
4. `challenges.py` router — invite/accept/decline/cancel endpointok (nincs create-definíció endpoint, §0.0 pont 4).
5. `challenge_repository_impl.dart` + `challenge_controller.dart` — a Kör 5 kontraktus implementációja (§0.0 pont 2).
6. `community_challenges_screen.dart` — lista, detail, offline cache, deep link; `ui_inventory_test.dart` számláló frissítve.
7. A két valódi-sértés próba §10-be; a §7 mindkét parancsa KÜLÖN futtatva.

## 9. Kockázatok

- **Az optimista állapotgép-ugrás.** Egy kliensoldali "előreugrás" versenyhelyzetben inkonzisztens állapotot hagyna (A1/A5).
- **A kliens-idő alapú lejárat.** Egy rosszul beállított eszközóra meghosszabbítaná vagy lerövidítené a challenge-ablakot (A7).
- **A blockolt fél meghívása.** Ez közvetlen safety-regresszió lenne a Kör 8 invariánshoz képest (A3).
- **A cancel race pesszimista lockkal "megoldva".** A kódbázisban nincs `SELECT ... FOR UPDATE` precedens (ADR 0415 D5) — egy ilyen bevezetés eltérne a mért mintától; a feltételes `UPDATE` + rowcount ugyanazt a garanciát adja új mechanizmus nélkül.

## 10. Implementation handoff — az implementer tölti ki

### 10.1 Javító kör (2026-08-23, `stopped` után) — l10n forrás-korrekció

**Probléma:** az előző implementer a 17 új `communityChallenge*` kulcsot az
`app_en.arb` / `app_hu.arb` aggregátumba írta, holott ADR 0307 §4 szerint
ezek GENERATED fájlok — a `dart run tool/gen_l10n_segments.dart` határozza
meg a tartalmukat a `lib/l10n/features/community_<locale>.arb` fragmentumokból.
A gate `l10n` lépése emiatt `aggregátum elavult` hibát jelzett.

**Megoldás:**
1. A 17 kulcs (`communityChallengeTitle`, `…Empty`, `…ListHeader`,
   `…Accept`, `…Decline`, `…Cancel`, `…InviteAction`, `…DeepLinkPractice`,
   `…DeepLinkSong`, `…MetricLabel` (placeholder: `metric:String`),
   `…WindowLabel` (placeholders: `startsAt:String`, `endsAt:String`),
   `…ErrorNetwork`, `…ErrorSessionExpired`, `…ErrorForbidden`,
   `…ErrorRateLimited`, `…ErrorConflict`, `…ErrorInvalidInput`)
   átkerült a `lib/l10n/features/community_en.arb` és `…_hu.arb`
   fragmentumok VÉGÉRE — a meglévő `communityNotificationSecurityAlertTitle`
   bejegyzés után, azonos formázással (két szóköz indent, üres sor a
   bejegyzések között, utolsó blokkon nincs vessző).
2. `dart run tool/gen_l10n_segments.dart --write` deterministikusan
   újraírta az aggregátumot a fragmentumokból (most már 17 kulcs × 2
   locale = 34 bejegyzés, és a kulcs-sorrend ismét alfabetikus).
3. `dart run tool/gen_l10n_segments.dart --check` → `[en] aggregátum
   naprakész`, `[hu] aggregátum naprakész`.
4. `dart run tool/ci/check_l10n_parity.dart` → `L10n parity OK
   (en → hu, 1808 message(s))`.

**Plusz gate-oldali auto-fix:** a round-gate első futásakor a `backend ruff
check` 2 hibát jelzett a `backend/tests/community/test_challenge_invite_service.py`
fájlban (F401 unused import `ChallengeInviteRateLimited`, I001 import-sorrend)
— mindkettő a `--fix` kapcsolóval automatikusan javítva lett; a második
gate-futtatás minden lépése zöld.

**Végső gate (10 lépés, mind ZÖLD):**
- format · analyze · community_challenges_test.dart (8/8) ·
  ui_inventory_test.dart (1/1) · architecture · secrets · l10n ·
  backend ruff format · backend ruff check · backend pytest (teljes suite).

**Módosított fájlok:**
- `lib/l10n/features/community_en.arb` (+68 sor)
- `lib/l10n/features/community_hu.arb` (+68 sor)
- `lib/l10n/app_en.arb` (GENERATED, regenerálva)
- `lib/l10n/app_hu.arb` (GENERATED, regenerálva)
- `backend/tests/community/test_challenge_invite_service.py` (ruff --fix)
- `docs/rounds/e09-r21-challenge-and-invite-lifecycle.md` (ez a §10)

**Kimaradt (a CI-ra bízva, ADR 0053):** randomizált property gate, teljes
`flutter test` suite, release APK — ezeket a `gh workflow run build-apk.yml`
futtatja, és a merge-bar zöld kapujához tartoznak.

## 11. Review — a Claude tölti ki
