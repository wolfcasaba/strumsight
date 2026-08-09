# ADR 0198 — A Learn migráció rollout-határa: a Practice Engine V2 kiszolgálja a Learn-t `production`-ön kívül

- **Státusz:** Elfogadva (GOV-05c pre-flight, 2026-08-09)
- **Kör:** GOV-05c / `E99-R03` — Learn migráció a Practice Engine V2-re
  (governance-kör, nem SDD-fejezet)
- **Implementer motor:** Terra (Codex CLI, `tools/codex-round.sh`) — az ADR-t
  az orchesztrátor (Claude Opus 5) írta a pre-flightban
  ([ADR 0055](0055-agent-role-protocol.md)).
- **Kontext-ADR-ek:** [0111](0111-practice-production-wiring.md)
  (a Practice V2 éles providerei, E02-R21),
  [0197](0197-song-trainer-shipping-rollout-boundary.md) (a testvér-kör,
  GOV-05a — ugyanez a rollout-alak a Song Trainerre)
- **User-döntés, amit végrehajt:** 2026-08-07 `HANDOFF.md` §6 „Kötelező
  sorrend" 3. pont, valamint 2026-08-09 „mehet a 3. 4. pont".

## Kontextus

**Mért a pre-flightban 2026-08-09-én, `main @ 458eddc6`** — minden állítás
futtatott parancsból, nem a dokumentációból:

1. **A migrált út KÉSZ és be van drótozva.** A `migratedLearnEnabled` öt
   elágazást kapcsol a `lib/features/learn/screens/learn_screen.dart`-ban
   (187, 253, 303, 313, 326. sor): V2 megfigyelés-gyűjtés, a mikrofon-rés
   zárása pause/finish előtt, a `scoreLessonV2` pontozás, és a rögzítés a
   `_recordLearnMomentV2` úton. Ez utóbbi a
   `practiceSessionRecordingProvider`-t használja, amely **teljesen
   drótozott** (`practice_session_recording.dart:199–208`: eligibility +
   streak + practiceLog + `now`), nem dob.

2. **Sehol nincs `UnimplementedError`** a `lib/features/practice/` és a
   `lib/features/learn/` fában — tehát ez a kör **nem** ütközik abba a
   hiányzó-production-drótozás hibaosztályba, ami az AI Tutort blokkolja
   (`HANDOFF.md` §3) és amit a Practice V2-nél az E02-R21 pótolt.

3. **Az `AppConfig` validáció kielégül.** `app_config.dart:115–116`:
   `migratedLearnEnabled` megköveteli a `practiceEngineV2Enabled`-t. Mivel az
   utóbbi már `nonProd`, a `migratedLearnEnabled: nonProd` értékkel a két flag
   **azonos** minden környezetben — a validáció konstrukció szerint nem tud
   elhasalni.

4. **Két meglévő őr méri a migrációt.** A
   `test/features/learn/learn_migration_parity_test.dart` egy **51 cellás
   paritás-mátrixot** futtat flag-ON állapotban (17 lecke × alakok), plusz
   rossz irányok / kihagyások / páratlan extrák / szigorúan a
   tűréshatáron belüli és kívüli időeltolások / azonos nem-nulla input
   latency mindkét úton. A `learn_rollback_test.dart` a flag-OFF ág
   viselkedés-azonosságát és a V1 tároló érintetlenségét méri.

5. **A tényleges sugár MÉRVE, nem becsülve.** Egy `/tmp` próba-klónban
   átbillentettem a flaget `nonProd`-ra, és lefuttattam az
   [`docs/LESSONS.md`](../LESSONS.md) **L203** szerinti KÉT réteg unióját —
   a flag hívóit (4 tesztfájl) ÉS a `LearnScreen` teszt-pumpolóit (14
   tesztfájl):

   | Futtatott halmaz | Eredmény |
   |---|---|
   | `test/features/learn` + `test/app` | **260-ból 4 bukás** (1 skip) |
   | `test/core` + `test/features/live` + `test/features/songs` | **610/610 zöld** |

   A négy bukás **mindegyike flag-kikötő állítás**, nem viselkedési
   regresszió:

   - `test/app/app_config_test.dart:196` — „environment defaults match the
     guarded rollout table" (a `migratedLearnEnabled` `isFalse` cellái
     `development`-re és `lab`-ra)
   - `test/app/feature_flags_test.dart` — a GOV-05a-ban írt A4 kerítés
     (`migratedLearnEnabled` `false` minden környezetben)
   - `test/features/learn/learn_migration_parity_test.dart:303` — „A7 — the
     V2 ON flag production default stays OFF"
   - `test/features/learn/learn_rollback_test.dart:133` — „A8 —
     `FeatureFlags.migratedLearnEnabled` default is OFF in every env"

   **A tizenhárom, `appConfigProvider`-t NEM kikötő Learn-képernyő-teszt
   mind ZÖLD maradt a V2 úton** (`expected_chord_hint`, `hit_burst`,
   `learn_screen`, `live_scoring_jitter`, `next_lesson_cta`,
   `review_r100_fixes`, `setlist_expected_hint`, `visual_offset`,
   `waltz_count_in`, `onboarding_first_win`, `screen_size_guard`,
   `expected_hint_cleared_on_live`, `setlist_flow`). Ez a legerősebb
   bizonyíték a migráció biztonságosságára: a legacy viselkedést mérő tesztek
   a V2 motoron is teljesülnek — pontosan azt igazolják, amit a 51 cellás
   paritás-mátrix ígér.

## Döntés

### Döntés 1 — `migratedLearnEnabled: nonProd`

A `FeatureFlags.forEnvironment` a `migratedLearnEnabled` értékét a `nonProd`
predikátumból származtatja — ugyanaz az alak, mint a
`practiceEngineV2Enabled`, `practiceDetailedHistoryEnabled` és (GOV-05a óta) a
`songTrainerV2Enabled`. Az alapértelmezett konstruktor paramétere
**változatlanul `false`** marad.

Nem vezetünk be dart-define override-ot, sem külön rollout-stage enumot, sem
felhasználói kapcsolót: ez **availability**-flag, nem preferencia.

### Döntés 2 — A négy őr átirányítása, nem törlése

Mind a négy piros állítás a **production-határra** irányítandó át. Ami
megmarad: `migratedLearnEnabled == false` `AppEnvironment.production`-ben, és
`false` az alapértelmezett konstruktorban. Ami változik: `development` és
`lab` cellája `true`-ra.

**Nem elfogadható feloldás:** bármelyik teszt vagy `group` törlése,
`skip`-elése, vagy olyan átírása, amely után nem marad
`AppEnvironment.production`-re szóló állítás. A rollout-határ nem szűnt meg —
elmozdult, tehát az őrnek is el kell mozdulnia, nem eltűnnie.

### Döntés 3 — A rollback egyetlen sor marad

A `learn_rollback_test.dart` flag-OFF ága **érintetlen** marad, és továbbra is
azt méri, hogy a `migratedLearnEnabled: false` a legacy viselkedést és a V1
tárolót adja. Ez a visszaút gépi garanciája: a rollout visszavonása a factory
egyetlen sorának visszaírása `false`-ra, és az őr bizonyítja, hogy az vissza
is állítja a régi viselkedést.

### Döntés 4 — A Learn UI nem változik

A kör **nem** nyúl a `learn_screen.dart`-hoz, a `lesson_list_screen.dart`-hoz,
sem semmilyen más UI-hoz. Nincs új belépési pont, nincs új string, nincs
„V2" jelölés a felületen. A migráció definíció szerint **láthatatlan** a
felhasználónak: ugyanaz a Learn, más motorral. Ha a felületen bármi
megváltozna, az regresszió, nem funkció.

Ez a kör ezért **eltér** a GOV-05a alakjától (ott a belépési pont a rollout
része volt), mert a Learn **már ma is elérhető** a héj harmadik füléről — nem
elérhetőségi, hanem motor-csere kérdés.

## Következmények

**Pozitív**

- A Learn `development`/`lab` buildben a Practice Engine V2-n fut: zárt
  mikrofon-rés pause/finish előtt (A9), `scoreLessonV2` pontozás, és a
  kanonikus rögzítési út (streak-kapu + napi cél + V1 bejegyzés-alak azonos
  minden más Practice hívási hellyel).
- A `HANDOFF.md` §3 „a Learn ma is a legacy ágon fut" tétele lezárul.
- A rollback egy sor, gépi őrrel bizonyítva.

**Negatív / kockázat**

- A migrált út **valós eszközön még sosem futott**. A szintetikus zöld — még
  egy 51 cellás paritás-mátrixszal is — nem „done" (HORIZON-szabály). A
  készülékes bizonyíték a device-mátrix migrated-Learn sorain gyűlik, és a
  user tölti ki.
- A `development` környezet is átáll, tehát minden fejlesztői és CI dev-build
  a V2 Learn-t futtatja. Szándékos: a `nonProd` a projekt bevett
  rollout-alakja, és a production-határt négy őr méri.
- A pontozás motorja megváltozik (`scoreLessonV2`), tehát a **lecke-csillagok
  és a Progress irány-pontossága elvileg más értéket adhat** ugyanarra a
  játékra. A paritás-mátrix ezt méri, de valós hangon még nincs
  visszaigazolva — ez a GOV-06 valós-audio mérés egyik nyitott kérdése.
