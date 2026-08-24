# ADR 0418 — Leaderboards és opt-in versenynézet

- **Státusz:** Elfogadva (E09-R23 pre-flight, 2026-08-24)
- **Kör:** E09-R23 — Leaderboards és opt-in versenynézet
- **Implementer motor:** MiniMax M3 — az ADR-t az orchesztrátor (Claude Sonnet 5)
  írta a pre-flightban (ADR 0055).
- **Epic:** Chapter 10 — Epic 9 (Community Platform), Kör 23 (a 32 kör közül a huszonharmadik)
- **Kontext-ADR-ek:** [0417](0417-verified-result-submission-and-anti-cheat.md)
  (Kör 22 — `community_challenge_results.verification_state` 5-értékű
  allowlist, `verified` a pontos wire-string, `challenge_verification_service.py`
  MOST tilos zóna, csak-olvasás), [0415](0415-community-challenge-invite-lifecycle.md)
  (Kör 21 — `CommunityChallenge`/`CommunityChallengeParticipant` modellek,
  `club_id` Kör 24-re fenntartva, `best_metric_value` a Kör 22 írási felülete),
  [0399](0399-flutter-community-domain-and-public-api.md) (Kör 5 —
  `CommunityChallengeRepository.leaderboard()` MÁR deklarálva, `Object`
  placeholder visszatérési típussal, a `challenge_repository_impl.dart`
  docstringje ezt a kört jelöli ki a bekötésre).
- **Sorszám-jegyzet:** a pipeline-prompt E09-R23-hoz `0412`-t adott előre
  kiosztott ADR-ként, de ez a szám MÁR foglalt —
  `docs/adr/0412-media-processing-privacy-and-moderation-state.md`. A
  `tools/round-slots.py reserve-adr --round E09-R23` friss számot adott:
  **`0418`**.
- **Visszakeresés (ADR 0312, pre-flight §4.9):**
  `node tools/knowledge-rag.mjs --corpus lessons,halts,adr --top 5 "leaderboard
  verified only opt-in privacy"` → ADR 0417 "A visszavonás feltétele" sora
  ("egy jövőbeli kör — feltehetően Kör 23 — az invite-állapot előrehaladtatását
  megépíti") NEM erre a körre vonatkozik ténylegesen (a leaderboard nem az
  invite-state gráfot bővíti, ld. lent) — jegyezve, hogy elkerüljük a téves
  alkalmazást. `node tools/knowledge-rag.mjs --corpus lessons,halts --top 5
  "cursor pagination duplicate rows deterministic tie-breaker leaderboard
  rank"` → **E09-R13** (Following feed és cursor pagination backend, ADR 0406)
  közvetlenül átvehető minta az A5 stabil lapozásra (2 javító kör zárt egy
  index-guard hamis-zöld hibát — a leaderboard cursor-tesztnek VALÓS,
  többoldalas fixture-adatot kell mérnie, nem csak egy 1-oldalas happy-patht);
  **L109** (determinizmus-mérés: egyenlő tie-break-kulcsú sokpermutációs
  próba, nem egyszeres mutáns) közvetlenül alkalmazandó az A2 cellára.
  `node tools/knowledge-rag.mjs --top 5 "leaderboard verified opt-in friends
  club challenge-global scope"` → a kör saját SDD-fejezete
  (`docs/sdd/10-epic-09-community-platform.md` "Kör 23" szakasz, §15.6,
  §20.1/20.7/20.8, §21.6) — a brief §3/§5 nagyrészt hűen tükrözi, de a §2
  "Jelenlegi állapot" egy mért ponton TÉVES (lásd Kontextus 2.).

## Kontextus

**Mért 2026-08-24-én, a pre-flightban (ez a §0.0 hordozza a teljes
tényellenőrzést, a brief eredeti szövege felülíródik):**

1. **A `challenge_repository.dart` és a `challenge_repository_impl.dart`
   HIÁNYZIK a brief eredeti `allowed_paths`-ából, de a Flutter képernyő
   nélkülük nem valódi.** A `challenge_repository_impl.dart` docstringje szó
   szerint rögzíti: *"The 2 result / leaderboard methods (`submitResult` /
   `leaderboard`) raise `UnimplementedError` — [...] `leaderboard`)
   [...] Kör 23 scope"*
   (`lib/features/community/data/repositories/challenge_repository_impl.dart:17-20`).
   A `CommunityChallengeRepository.leaderboard()` metódus MÁR deklarálva van
   a Kör 5 interfészen (`Future<CommunityPage<Object>> leaderboard({required
   ContentId challengeId, required Object cursor, required int limit})`,
   `challenge_repository.dart:74-78`) — a visszatérési típus szándékosan
   `Object` placeholder, mert Kör 5 még nem ismerte a leaderboard-sor alakját.
   Ha ez a kör csak a backend service/model/router réteget építi meg, a
   Flutter képernyő nem tud valódi adatot mutatni — ez a
   `no-demos-real-functionality` elv sérelme lenne (ugyanaz a hibaosztály,
   mint az ADR 0417 Kontextus 1. pontja a `challenges.py` routerre). Az
   **`allowed_paths` bővítve** (lásd lent) mindkét fájllal, de **a `leaderboard()`
   metódus SZIGNATÚRÁJA (paraméterlista, visszatérési típus külső alakja)
   NEM változik** — két MÁS, e körön kívüli teszt-fájl
   (`test/features/community/application/challenge_result_controller_test.dart`,
   `test/features/community/presentation/community_challenges_test.dart`)
   SAJÁT fake-implementációt ad a `CommunityChallengeRepository`
   interfészre; egy interfész-szintű bővítés (pl. új kötelező metódus vagy
   megváltozott visszatérési generikus) ott fordítási hibát okozna, ami e
   kör `allowed_paths`-án KÍVÜLI fájlok módosítását igényelné. A megoldás:
   a `leaderboard()` metódus BELSEJE (a HTTP-hívás + JSON-dekódolás) egy ÚJ
   `LeaderboardEntry` domain-osztályt épít és ad vissza — a `CommunityPage<
   LeaderboardEntry>` Dart-kovariancia miatt érvényes visszatérési érték a
   deklarált `CommunityPage<Object>` típusra, tehát a hívó fél (a Kör 23
   `leaderboard_screen.dart`, típuscastal/típusellenőrzéssel olvasva az
   `items`-et) valódi, típusos adatot kap anélkül, hogy az interfész
   szignatúrája módosulna. Lásd D1.
2. **A brief §2 "A Kör 4 privacy-policy MA rendelkezik `leaderboard opt-in`
   mezővel" állítása MÉRVE TÉVES — elérhetetlen cél-státusz (§1 pre-flight
   szabály 1. pontja).** `grep -rln "leaderboardOptIn|leaderboard_opt_in"
   --include="*.dart" --include="*.py" .` → **0 találat** a teljes fában.
   A `CommunityPrivacySettings` modell (`backend/app/community/models/
   profile.py:105-149`, Kör 4, `e09_r04_0004_community_privacy_fields`
   migráció) KIZÁRÓLAG `visibility` és `audience_default` mezőt hordoz —
   nincs leaderboard-specifikus oszlop. A `profile.py` és a Kör 4 migráció
   NINCS ezen kör `allowed_paths`-án, és a `visibility`/`audience_default`
   újrahasznosítása fogalmilag rossz védelmet adna (a §15.6 SDD explicit
   MÁS tengelyt ír le: "leaderboard részvétel alapértelmezetten tiltott" — ez
   FÜGGETLEN a profil publikus láthatóságától, egy user lehet publikusan
   látható profillal, mégis leaderboard-optout, és fordítva). **Megoldás:**
   az opt-in állapotot egy ÚJ, önálló, KIZÁRÓLAG e kör tulajdonában lévő
   tábla hordozza (`community_leaderboard_opt_ins`), amit a MÁR
   `allowed_paths`-on lévő `models/leaderboard.py` deklarál és a MÁR
   `allowed_paths`-on lévő `backend/alembic/versions/
   e09_r23_0017_community_leaderboard.py` migráció épít fel — a Kör 4
   `community_privacy_settings` táblát a kör NEM módosítja, `allowed_paths`
   bővítés nélkül. Lásd D2.
3. **"Disqualification/delete" nem elérhető input MA — a service-réteg
   `verified` állapota terminális, profil hard-delete nem létezik.**
   `grep -n "_terminal_state" backend/app/community/services/
   challenge_verification_service.py` → `verified` BENNE van a terminális
   halmazban (315-322. sor) — a service-en belül NINCS olyan kódút, ami egy
   `verified` sort átminősítene. `grep -n "^def " backend/app/community/
   services/profile_service.py` → csak `create_profile`/`update_profile`
   létezik, hard-delete NINCS. A `challenge_verification_service.py` ezen a
   körön TILOS ZÓNA (csak-olvasás), tehát egy admin/mod "disqualify" endpoint
   megépítése ebben a körben SCOPE-SÉRTÉS lenne. **Megoldás:** az A6 cella a
   "disqualification/delete" hatását KÖZVETLEN teszt-szintű DB-mutációval
   szimulálja (egy MÁR verified `CommunityChallengeResult` sor
   `verification_state`-jét vagy a hozzá tartozó `CommunityChallengeParticipant`
   sort a teszt közvetlenül törli/módosítja az adatbázisban — ez egy jövőbeli
   admin/mod kör által kiváltható állapotváltozást modellez), majd a
   leaderboard-service újraszámítást hív és méri, hogy a projekció
   DETERMINISZTIKUSAN tükrözi az új állapotot (nincs stale cache, nincs
   maradék rangsor-bejegyzés). A kritérium ÍGY azt bizonyítja, hogy a
   projekció NEM tartalmaz cache-hibát — nem azt, hogy egy "disqualify"
   FUNKCIÓ létezik (az egy jövőbeli kör dolga, dokumentált hiány). Lásd D5.
4. **Metric-direction: a MÁR élő "higher-is-better" feltevés öröklése, nem
   új döntés.** `grep -n "higher_is_better" backend/app/community/services/
   challenge_verification_service.py` → *"A `personalBest` típusú
   challenge-nél egy újabb, jobb (`higher_is_better` = True a jelenlegi
   contract) beküldés FELÜLÍRJA a korábbi `best_metric_value`-t"*
   (`integrity_policy.py::evaluate_first_vs_best_policy` docstring). A
   leaderboard rangsorolása UGYANEZT a feltevést követi MINDEN challenge-
   típusra (nem csak `personalBest`-re) — magasabb `metric_value` jobb
   helyezést jelent — mert a `best_metric_value` mező, amire a leaderboard
   épül, MÁR ezzel a feltevéssel íródik. Egy ellentétes irányú rangsorolás
   inkonzisztens lenne az ADR 0417 D6-tal. Lásd D3.
5. **"Friends/club/challenge-global scope" NEM kliens-választható paraméter
   — a célzott challenge `type` mezője dönt, a leaderboard per-challenge
   endpoint.** A brief `challenge_repository.dart` `leaderboard()` metódusa
   `challengeId`-t vár, nem egy külön "scope" enumot — és a §6 acceptance-
   tábla A1–A6 bizonyítéka mind `test_leaderboard_service.py` (backend-only),
   A4 (friends-scope) SEM a Flutter tesztre mutat. A `CommunityChallenge.type`
   (`friends|club|dailyCommunity|periodicGlobal|personalBest`, ADR 0415 D1)
   MÁR eldönti, egy adott challenge melyik "versenynézet" — a leaderboard
   endpoint mindig EGY konkrét challenge-hez kötött (`GET .../{challenge_id}
   /leaderboard`, SDD §21.6 minta), a friends-típusú challenge-nél pedig egy
   TOVÁBBI, viewer-relatív szűrés fut (a megjelenítendő sorokat a
   `community_follows` gráf ellen is le kell szűrni, mert egy invite
   címzettje nem feltétlenül a viewer közvetlen followja — ld. Kör 21
   invite-küldés, ami bármely usert megcélozhat). Ez a Flutter oldalon NEM
   igényel scope-választó UI-t. Lásd D4.
6. **"Saját rank endpoint" ebben a körben KIZÁRÓLAG backend-felület — a
   Flutter oldal nem köti be.** A §6 acceptance-tábla egyik cellája sem
   igényel egy dedikált "saját helyezés" UI-elemet (A7 a lista-sorok
   felolvashatóságáról szól, nem egy külön widgetről). A meglévő
   `fetchMyParticipation()` / `CommunityChallengeParticipantState`
   (`entities/community_challenge.dart`) NINCS ezen kör `allowed_paths`-án,
   bővítése új mezővel (rank) ugyanazt az interfész-kaszkád kockázatot
   hordozná, mint az 1. pontban — ezért az "own rank" a router/service
   rétegben épül fel és a `test_leaderboard_service.py`-ban bizonyított,
   Flutter-bekötése egy KÉSŐBBI kör dolga (dokumentált hiány, nem
   hallgatólagos).

```ai-router
schema_version = 1
risk = "high"
allowed_paths = [
  "backend/app/community/services/leaderboard_service.py",
  "backend/app/community/models/leaderboard.py",
  "backend/app/community/routers/leaderboards.py",
  "backend/alembic/versions/e09_r23_0017_community_leaderboard.py",
  "lib/features/community/domain/repositories/challenge_repository.dart",
  "lib/features/community/data/repositories/challenge_repository_impl.dart",
  "lib/features/community/presentation/screens/leaderboard_screen.dart",
  "backend/tests/community/test_leaderboard_service.py",
  "test/features/community/presentation/leaderboard_screen_test.dart",
  "docs/rounds/e09-r23-leaderboards-and-opt-in-competition.md",
]
gate_tests = [
  "test/features/community/presentation/leaderboard_screen_test.dart"
]
native_gate = false
```

**Kockázat = high, indoklás:** a kör privacy-érzékeny adatot (opt-in
láthatóság, follow-graph-alapú szűrés) vetít ki egy versenynézetbe — a
`brief-lint` S7 leletének megfelelően rögzítve: az `allowed_paths` a
`privacy` fragmentumot közvetlenül nem tartalmazza, de az A3 acceptance
("opt-out felhasználó nem jelenik meg public scope-ban") és a D2 (önálló
opt-in tábla) pontosan ez a felületet érinti — a `high` besorolás indoka a
privacy-szivárgás kockázata, nem egy `allowed_paths` string-egyezés.

## Döntés

### D1 — `leaderboard()` metódus TESTE bekötve, SZIGNATÚRÁJA fagyott; a válasz-alak egy új `LeaderboardEntry` osztály a `challenge_repository.dart`-ban

A `CommunityChallengeRepository.leaderboard({required ContentId challengeId,
required Object cursor, required int limit}) -> Future<CommunityPage<Object>>`
metódus paraméterlistája és deklarált visszatérési típusa VÁLTOZATLAN marad
(a két, e körön kívüli fake-implementer teszt-fájl ettől nem törik). A
`challenge_repository.dart` egy ÚJ, a domain-interfésszel kolokált
`LeaderboardEntry` osztályt kap (public_id, rank, displayName/handle,
metricValue, verifiedBadge — a pontos mezőlista az implementer dolga, a §6.1
A7 accessibility-igényéhez igazítva). A `HttpCommunityChallengeRepository.
leaderboard()` a `/v1/community/leaderboards/{challenge_public_id}` GET
endpointot hívja és `CommunityPage<LeaderboardEntry>`-t épít — ez érvényes
visszatérési érték a deklarált `CommunityPage<Object>` szignatúrára (Dart
generikus kovariancia). A `leaderboard_screen.dart` az `items`-et
`LeaderboardEntry`-ként olvassa (a `Object`-listát a repository-import
oldja fel típusosan). A `DisabledCommunityChallengeRepository.leaderboard()`
VÁLTOZATLAN marad (`throw _disabled.error`).

### D2 — Az opt-in állapot önálló, e kör tulajdonában lévő tábla (`community_leaderboard_opt_ins`), a Kör 4 `community_privacy_settings`-t nem módosítja

`backend/app/community/models/leaderboard.py` egy `CommunityLeaderboardOptIn`
ORM-osztályt vezet be: `profile_id` (FK `community_profiles.id`, CASCADE,
UNIQUE — egy sor per profil), `opted_in_at` (datetime, nullable — a sor
LÉTE jelenti az opt-in-t, `opted_in_at` az audit-időbélyeg; alternatívaként
egy `is_opted_in` bool + `updated_at` is elfogadható, az implementer dönt a
`leaderboard_service.py`-ban konzisztensen). A `backend/alembic/versions/
e09_r23_0017_community_leaderboard.py` migráció ÚJ táblá(ka)t hoz létre
(`community_leaderboard_opt_ins`, és ha a D5 materializált projekciót választ,
`community_leaderboard_entries` is) — a `community_privacy_settings` táblát
NEM módosítja, NEM ad hozzá oszlopot. A `leaderboards.py` router egy
opt-in/opt-out endpointot ad (pl. `PUT /v1/community/leaderboards/opt-in`),
alapból (sor hiánya) a felhasználó KI van zárva a public scope-ból (A3).

### D3 — Metric-direction: globálisan "higher-is-better", az ADR 0417 D6 feltevésének öröklése

A leaderboard rangsorolása minden challenge-típusra `metric_value DESC`
sorrendet alkalmaz — ugyanaz a feltevés, amit a `challenge_verification_
service.py::evaluate_first_vs_best_policy` MÁR alkalmaz a `personalBest`
best-of döntésnél. A `leaderboard_service.py` docstringje ezt a függőséget
explicit dokumentálja (egy jövőbeli `higher_is_better` mező a challenge
definíción MINDKÉT helyet — verification és leaderboard — egyszerre kell
frissítse, hogy konzisztens maradjon).

### D4 — Tie-breaker és scope: `(metric_value DESC, submitted_at ASC, id ASC)`; a scope a `challenge.type` + follow-graph szűrés, NEM kliens-paraméter

A determinisztikus sorrend: elsődleges kulcs `metric_value DESC` (D3),
másodlagos `submitted_at ASC` (a korábbi elérés jobb helyezést kap egyenlő
metrikánál — a project-wide cursor-minta `(created_at, id)` tükre), harmadlagos
`id ASC` (végső, garantáltan egyedi tie-break). A leaderboard endpoint egy
KONKRÉT `challenge_id`-hez kötött (`GET .../leaderboard`); a challenge saját
`type` mezője (`friends|club|dailyCommunity|periodicGlobal|personalBest`)
dönti el a "versenynézet" jellegét — nincs külön kliens-választható scope
enum. `friends` típusú challenge-nél a leaderboard-service a visszaadott
sorokat TOVÁBB szűri: csak azok a résztvevők jelennek meg, akik a viewer
`community_follows` gráfjában szerepelnek (`follower_profile_id = viewer`),
FÜGGETLENÜL attól, hogy a challenge saját invite-listája szélesebb kört ért
el (A4). `club`/`dailyCommunity`/`periodicGlobal`/`personalBest` típusnál
nincs további follow-graph szűrés (a `club_id` Kör 24-re fenntartva — a
club-tagság ellenőrzése egy jövőbeli kör dolga, itt a challenge saját
participant-listája a forrás).

### D5 — A6 "disqualification/delete": teszt-szintű DB-mutáció + újraszámítás determinizmus-próba, nem admin endpoint

A `test_leaderboard_service.py` A6 cellája: (1) legalább 2 verified eredmény
beszúrása, (2) a leaderboard-service lekérdezése, bizonyítva mindkettő
szerepel, (3) KÖZVETLEN adatbázis-mutáció — az egyik verified sor
`verification_state`-jét `rejected`-re állítja VAGY törli a sort (a teszt
választja, dokumentálva melyiket méri és miért), (4) a leaderboard-service
ÚJRA lekérdezve/újraszámítva, és az asszerció: a törölt/diszkvalifikált
bejegyzés HIÁNYZIK, a maradék rangsor rések nélkül, determinisztikusan
frissül. Ha a `leaderboard_service.py` materializált projekciót választ
(`community_leaderboard_entries` tábla, a SDD §20.1 javaslata), a szolgáltatás
egy explicit `rebuild_leaderboard(db, challenge_id)` függvényt exportál, amit
a teszt közvetlenül hív a mutáció UTÁN — ha query-time (nem materializált)
projekciót választ, a 4. lépés egyszerűen egy újabb `get_leaderboard_page()`
hívás. Mindkét tervezési választás elfogadható, az implementer dönt és a
`leaderboard_service.py` docstringje rögzíti a választást és az indokot.

### D6 — Router: `backend/app/community/routers/leaderboards.py`, önálló `/v1/community/leaderboards` prefix, a Kör 21/22 minta folytatása

A router SAJÁT `_session_factory`/`_commit_via`/`CurrentUser` DI mintát követ
(a `challenges.py` privát helperei nem exportáltak, minden router-fájl saját
másolatot tart — Kör 21/22 precedens). Endpointok: `GET /v1/community/
leaderboards/{challenge_public_id}` (paged leaderboard, cursor pagination,
Kör 11/16/21 minta), `GET /v1/community/leaderboards/{challenge_public_id}/me`
(saját rank, Kontextus 6.), `PUT /v1/community/leaderboards/opt-in` (D2).
A pontos response-séma (Pydantic, inline a router-fájlban, a Kör 21 mintát
követve) az implementer dolga.

## Elutasított alternatívák

- **A `leaderboard()` interfész szignatúrájának bővítése egy explicit
  `scope` paraméterrel** — elutasítva: két, e körön kívüli teszt-fájl saját
  fake-implementációt ad az interfészre, egy szignatúra-bővítés ott
  fordítási hibát okozna, ami `allowed_paths`-on kívüli módosítást
  igényelne (Kontextus 1.). A scope a challenge `type` mezőjéből ÉS a
  follow-graph szűrésből adódik, nem kliens-bemenetből (D4).
- **A Kör 4 `community_privacy_settings` tábla bővítése egy
  `leaderboard_opt_in` oszloppal** — elutasítva: a `profile.py` és a Kör 4
  migráció nincs `allowed_paths`-on, és egy ilyen bővítés egy MÁS,
  szélesebb hatókörű (minden profil-fogyasztó) táblát módosítana egyetlen
  feature kedvéért. Az önálló `community_leaderboard_opt_ins` tábla (D2)
  ugyanazt a garanciát adja, izoláltan.
- **Egy admin/mod "disqualify" endpoint megépítése ebben a körben** —
  elutasítva: `challenge_verification_service.py` tilos zóna (csak-olvasás),
  és egyik A1–A7 cella sem igényel admin-felületet — a D5 teszt-szintű
  DB-mutáció ugyanazt a determinizmus-garanciát bizonyítja admin-endpoint
  nélkül.
- **Az "own rank" Flutter-bekötése ebben a körben** — elutasítva:
  `entities/community_challenge.dart` nincs `allowed_paths`-on, egy új mező
  hozzáadása (rank) ugyanazt az interfész-kaszkád kockázatot hordozná, mint
  a leaderboard() bővítése — a backend felület (D6) elég a scope "saját rank
  endpoint" bullet teljesítéséhez, a Flutter UI egy jövőbeli kör dolga.

## Következmények

- A `challenge_repository.dart` és a `challenge_repository_impl.dart`
  bekerül az `allowed_paths`-ba — a `leaderboard()` metódus MOST már valódi,
  végponttól végpontig működő adatot szállít, nem csak a backend
  service-réteget.
- Egy önálló `community_leaderboard_opt_ins` tábla születik — a Kör 4
  privacy-settings táblát a kör nem érinti, a két koncepció (profil-
  láthatóság vs. verseny-részvétel) explicit szétválik.
- Az "own rank" Flutter-bekötése és a club-tagság alapú szűrés (Kör 24
  függőség) nyitva marad egy jövőbeli kör számára — dokumentált hiány, nem
  hallgatólagos.

## A visszavonás feltétele

Felülvizsgálandó, ha egy jövőbeli kör a `CommunityChallengeParticipantState`-et
(vagy egy dedikált leaderboard-repository interfészt) egy explicit `rank`
mezővel bővíti — ekkor a D6 "own rank" backend-only korlátozása feloldható,
és a Flutter oldal közvetlenül bekötheti. Felülvizsgálandó, ha a Kör 24 club
domain megépül — ekkor a D4 "nincs club-tagság szűrés" feltevése
szigorítható a tényleges tagságra. Felülvizsgálandó, ha a challenge
definíció egy explicit `higher_is_better` mezőt kap (D3 feltevése ekkor
kódba írható konfigurációvá válik, ugyanúgy, ahogy az ADR 0417 D6 is jelzi).
