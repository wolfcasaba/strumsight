# E07-R08 — Független review

- **Első review SHA:** `8c9df8c4597533b1fc0c1a85ff5503f42f6b0c67`
- **Javító kör #1 SHA:** `b3a311653790` (a review-commit `86bc9cca` fölött)
- **Pre-flight bázis:** `19836c652afc9203c7d6014fbe4524c4449661a0`
- **Reviewer:** Claude (Sonnet 5) orchestrátor, izolált klónok:
  `/tmp/review-e07-r08` (első pass), `/tmp/review-e07-r08-fix1` (javítás
  utáni pass) — forrás mindkétszer `/home/ubuntu/ss-terra-e07-r08`, a branch
  még nincs origin-en
- **Verdikt:** **APPROVED** (javító kör #1 után)

## Bizonyíték

- Scope audit (`tools/scope-audit.py --repo /tmp/review-e07-r08 --brief
  docs/rounds/e07-r08-practice-catalog-adapter.md --base 19836c65...`) →
  `OK`, 9 módosított út, 0 generált/ignorált — pontosan a brief `allowed_paths`
  listája (8 fájl + a brief maga).
- Független gate izolált `/tmp` klónban (a megosztott munkapéldány/hub
  érintése nélkül): format, analyze, mindkét célzott teszt (3+5 eset),
  architecture, secrets, l10n → **mind zöld**.
- Eldobható review-próba (`test/_review_probe_capability_test.dart`, a merge
  előtt törölve) négy dolgot mért:
  1. `requiresMicrophone`/`supportsTempo`/`supportsLoop` értéke mindkét
     adapter kimenetén → **mindhárom `unsupported`** minden előállított
     jelöltre (ld. F1).
  2. `PracticeCatalogSnapshot` konstruktor két, azonos `source`+`exerciseId`
     (eltérő `contentRevision`) jelöltre → `ArgumentError` dob, a duplikáció-
     őr valóban működik.
  3. Üres jelölt- és figyelmeztetés-lista nem dob kivételt.
- A §10 handoff valódi-sértés próbáját (A6: hiányzó `prerequisites` default
  `['default']`-dal pótolva → piros, majd visszaállítva) a handoff-leírás
  konzisztens a kódban látott guard-struktúrával (`_missingMetadataWarning`
  minden konstrukció ELŐTT fut, `continue`-val zár — nincs olyan út, ahol egy
  hiányos bejegyzésből mégis `ExerciseCandidate` épülne).

## Acceptance criteria

| # | Kritérium | Teljesült | Bizonyíték |
|---|---|---|---|
| A1 | Minden jelölt létező forrásra mutat | ✅ | mindkét adapter kizárólag hívó-táplált `PracticeDefinition`/`Lesson` értékből épít; nincs konstrukciós út enélkül |
| A2 | Nem támogatott capability explicit `unsupported` | ✅ (struktúrálisan) | `_completeCapabilities` `ArgumentError`-t dob hiányzó kulcsra — de ld. F1: a TARTALOM egy része hamis, nem hiányzó |
| A3 | Pillanatkép katalógus- ÉS tartalom-revíziót hordoz | ✅ | `practice_catalog_snapshot_test.dart:23-32`, mindkét mező kötelező konstruktor-param |
| A4 | Revízió-eltérés detektált | ✅ | `mismatchesAgainst`, `practice_catalog_snapshot_test.dart:34-50` |
| A5 | Rendezés két futásban bitre azonos | ✅ | `practice_catalog_snapshot_test.dart:53-84`, `sortKey` string-alapú, nincs `hashCode`/Map-iteráció a döntésben |
| A6 | Hiányzó kötelező metaadat → kimarad + figyelmeztetés | ✅ | `practice_engine_catalog_adapter_test.dart:94-137` + handoff valódi-sértés próba |
| A7 | Offline elérhetőség metaadatból, nem találgatásból | ✅ | `entry.offlineAvailable` 100%-ban hívó-táplált; egyik adapter sem importál `Connectivity`/`Platform`/hálózati csomagot |
| A8 | Adapter csak `public.dart`-on át ér más feature-t | ✅ | `practice_engine_catalog_adapter.dart:4` → `practice/public.dart`; `legacy_lesson_candidate_adapter.dart:4` → `learn/public.dart`; `tool/check_architecture.dart` zöld |

Mind a nyolc írott acceptance-pont teljesül. F1 az ADR 0262 **szándékát**
sérti (capability-IGAZSÁG), nem egy konkrét A-pont betűjét — ezért MAJOR, nem
BLOCKER, de nyitva tartja a merge-et, mert a kör saját céljának lényegi része.

## Scope-audit

Engedélyezett fájlokon kívüli változás: **nincs** (9/9 a listán, ld. fent).

## Megállapítások

### F1 — MAJOR — `requiresMicrophone`/`supportsTempo`/`supportsLoop` hamisan `unsupported` minden jelöltre

- **Fájl:** `lib/features/practice_generator/data/adapter/practice_engine_catalog_adapter.dart:59-74`,
  `lib/features/practice_generator/data/adapter/legacy_lesson_candidate_adapter.dart:62-65`
- **Probléma:** mindkét adapter `allCapabilitiesUnsupported()`-ból indul, és
  csak a `supportsDirectionScoring`/`supportsChordScoring`/`supportsOffline`
  kulcsokat írja felül ténylegesen mért jellel — a `requiresMicrophone`,
  `supportsTempo`, `supportsLoop` (és a Legacy adapterben a scoring-kulcsok
  is) a default `unsupported` értéken marad. Mérve (eldobható próba, 2 teszt):
  mindkét forrásból származó minden jelöltre `requiresMicrophone =
  CapabilitySupport.unsupported` és `supportsTempo = unsupported`. Ez NEM
  „nincs bizonyíték" eset: mindhárom jel **determinisztikusan ismert** az
  adapter saját bemenetéből — a Practice V2 / Learn lecke-tartalom 100%-a élő
  mikrofonos detektálással megy (`HANDOFF.md` §2: „Detektálás (100%
  on-device): Live... DSP + CRNN ML"), és a `PracticeSessionConfig.
  effectiveTempo`/`loopCount` (`lib/features/practice/domain/model/
  practice_session_config.dart:14-16`) minden `PracticeDefinition`-re
  egyaránt elérhető, definíciófüggetlen tulajdonság — nincs olyan Practice V2
  session, ami NE engedné a tempó- vagy loop-módosítást. A `supportsTempo` az
  ADR 0262 Kontextus/Döntés 2 SAJÁT, kiemelt példája („Ha egy gyakorlat NEM
  támogat pl. tempó-vezérlést…") — pontosan ez a mező marad hamisan
  `unsupported` minden egyes jelöltre, kivétel nélkül.
- **Hatás:** egy jövőbeli tervező (Kör 12/13) a `requiresMicrophone=
  unsupported` jelet „nem igényel mikrofont"-ként olvasná (ADR 0262 §2: „A
  hiányzó/hamis jelet a tervező megpróbálná használni") — pl. egy jövőbeli
  „nincs mikrofon-engedély" fallback-terv tévesen ajánlhatna mikrofon-igényes
  tartalmat. A `supportsTempo`/`supportsLoop` hamis `unsupported`-ja miatt a
  tervező sosem ajánlana tempó- vagy ismétlésszám-alapú adaptációt, holott az
  minden jelöltre elérhető lenne.
- **Kötelező javítás:** a Practice Engine adapterben és a Legacy adapterben
  is állítsd `CapabilitySupport.supported`-ra a `requiresMicrophone`-t
  (mindkét forrás 100%-ban mikrofonos detektálású), és a Practice Engine
  adapterben a `supportsTempo`/`supportsLoop`-ot (a `PracticeSessionConfig`
  szerződés univerzális, definíciófüggetlen mezői). A Legacy adapternél a
  `supportsTempo`/`supportsLoop` kérdés valódi forrás-mérést igényelne (a
  `Lesson` modellnek nincs session-config megfelelője) — ha nincs mérhető jel,
  maradhat `unsupported`, de ezt a §10 handoffban dokumentáld explicit
  döntésként, ne hallgatólagos alapértékként. Ha bármelyik capability
  szándékosan marad `unsupported` (pl. mert a kör nem vállalja a
  `PracticeSessionConfig`-mérést), a §10 handoff mondja ki ezt indoklással —
  a jelenlegi handoff „teljes, stabil capability-vokabulár"-ként írja le a
  mezőt, ami a mért tartalom fényében túlállítás.
- **Ellenőrzés:** a `practice_engine_catalog_adapter_test.dart` A2-csoportjába
  (`marks source-unsupported capabilities explicitly unsupported`) vegyél fel
  pozitív asserttet `requiresMicrophone`/`supportsTempo`/`supportsLoop`-ra
  (`CapabilitySupport.supported`), és a Legacy teszt csoportba hasonlót
  `requiresMicrophone`-ra — ezek híján a mostani teszt csak a NEGATÍV
  (`requiresCamera`/`requiresBackingTrack`) oldalt fogja, a pozitív oldal
  bizonyítatlan marad.
- **Státusz:** **FIXED** (`b3a31165`) — a Practice Engine adapter mindhárom
  kulcsot `supported`-ra állítja; a Legacy adapter a `requiresMicrophone`-t
  `supported`-ra, a `supportsTempo`/`supportsLoop`-ot explicit,
  megindokolt `unsupported`-on hagyja (§10 „Javító kör #1": nincs
  session-config megfelelő a `Lesson`-on). Mindkét pozitív állítás tesztelt
  (`practice_engine_catalog_adapter_test.dart` diffje). Saját, eldobható
  próbateszttel (`/tmp/review-e07-r08-fix1/test/_review_probe_fix1_test.dart`,
  törölve) függetlenül megerősítve: mindhárom Practice Engine kulcs
  `supported`, a negatív kulcsok (pl. `requiresCamera`) változatlanul
  `unsupported` — nincs regresszió.

### F2 — MINOR — Az új value-típusok nem implementálnak `operator==`/`hashCode`-ot

- **Fájl:** `lib/features/practice_generator/domain/model/exercise_candidate.dart`
  (`ExerciseCandidate`, `SupportedDurations`, `DifficultyRange`,
  `ExerciseLoadProfile`), `lib/features/practice_generator/domain/model/
  practice_catalog_snapshot.dart` (`PracticeCatalogSnapshot`,
  `CandidateExclusionWarning`)
- **Probléma:** a kör összes új domain value-típusa mezőnkénti egyenlőség
  nélkül, azonosság-alapú (`==`) marad. Ez eltér a projekt bevett
  konvenciójától — `PracticeDefinition`, `ScoringProfile`,
  `PracticeSessionConfig` és a többi Epic 7 modell (pl. `SkillEstimate`,
  `PracticeGoal`) mind kézzel írt `operator==`/`hashCode`-ot implementál.
- **Hatás:** ma egyetlen teszt sem hasonlít össze két `ExerciseCandidate`-ot
  értékegyenlőséggel (mind mezőnkénti assertet használ), tehát nincs élő
  regresszió — de egy jövőbeli dedup-, diff- vagy widget-teszt csendben
  azonosság-alapú összehasonlításra esne vissza, és valós tartalmi eltérést
  hamis egyezésként (vagy fordítva) jelezhetne.
- **Kötelező javítás:** adj hozzá mezőnkénti `operator==`/`hashCode`-ot a hat
  típushoz, a `practice_value_equality.dart`-hoz hasonló segédekkel (list/map
  hash), a Practice feature meglévő mintáját követve.
- **Ellenőrzés:** egy egyszerű `expect(candidateA, candidateA_copy)` /
  `expect(candidateA, isNot(candidateB))` teszt-pár típusonként.
- **Státusz:** **FIXED** (`b3a31165`) — mind a hat típus (`ExerciseCandidate`,
  `SupportedDurations`, `DifficultyRange`, `ExerciseLoadProfile`,
  `PracticeCatalogSnapshot`, `CandidateExclusionWarning`) mezőnkénti
  `operator==`/`hashCode`-ot kapott (lista/capability-map összevetés saját
  lokális helperrel, konzisztensen a Practice feature `listEquals`/`listHash`
  szellemével). Saját, eldobható próbateszttel függetlenül megerősítve:
  két, mezőnként azonos `ExerciseCandidate` egyenlő és azonos hash-t ad, egy
  eltérő `exerciseId`-jú nem egyenlő; a `PracticeCatalogSnapshot` mezőnkénti
  egyezése is helyesen egyenlőséget ad.

### N1 — NOTE — `missingPrerequisite` kód három különböző hiányzó mezőre újrahasznosítva

- **Fájl:** mindkét adapter `_missingMetadataWarning` metódusa
- **Megfigyelés:** a `skillTargets`/`prerequisites`/`loadProfile` hiánya is
  `CandidateExclusionReason.missingPrerequisite`-et kap — csak a szabad
  szöveges `detail` mező különbözteti meg őket. Ez az SDD Ch8 §14.6 zárt
  kódkészletének korlátja (nincs specifikusabb kód „missingLoadProfile"-ra
  vagy „missingSkillTarget"-re), nem implementációs hiba — a `detail` mező
  ténylegesen hordozza a pontos okot. Nem blokkol; egy jövőbeli SDD-bővítés
  fontolhatja saját kódok hozzáadását.

## Gate-bizonyíték ellenőrzése (első pass)

| Gate | Állított eredmény (handoff) | Ellenőrizve (saját, izolált klón) |
|---|---|---|
| format | zöld | ✅ `dart format --output=none --set-exit-if-changed lib test tool` → 0 changed |
| analyze | zöld | ✅ `flutter analyze lib/ test/ tool/` → No issues found |
| `practice_catalog_snapshot_test.dart` | zöld, 3/3 | ✅ 3/3 |
| `practice_engine_catalog_adapter_test.dart` | zöld, 5/5 | ✅ 5/5 |
| architecture | zöld | ✅ `tool/check_architecture.dart` → OK (12 allowlisted deviation, változatlan) |
| secrets | (nem állította, a gate maga futtatja) | ✅ 0 finding |
| l10n | (nem állította, a gate maga futtatja) | ✅ OK |

## Javító kör #1 és lezáró ellenőrzés

- A javító kör (`b3a31165`) a review-jelentést nem érintette (csak olvasta).
  `gate_shape=VIOLATION` jelzést kapott a `.codex-round-status`-ban — a log
  ellenőrzése után **hamis pozitívnak** bizonyult: a heurisztika a
  `round-gate.sh` FORRÁSÁT `sed`-del kiolvasó, más (git status/diff)
  parancsokkal `&&`-lánccal összekötött diagnosztikai lépésre ütött
  (`/tmp/codex-e07-r08-fix1.log:7847`), NEM magára a gate-FUTTATÁSRA — a
  tényleges, önálló `tools/round-gate.sh` hívás (log:7081) és a hozzá tartozó
  teljes, csonkítatlan kimenet (log:8496-8722) tiszta, láncolás nélküli
  futást mutat, mind a hét lépés ZÖLD.
- Scope audit a javító kör után (`tools/scope-audit.py --repo
  /tmp/review-e07-r08-fix1 --brief docs/rounds/e07-r08-practice-catalog-adapter.md
  --base 86bc9cca`) → `OK`, 7 módosított út, 0 generált/ignorált.
- Független gate friss `/tmp/review-e07-r08-fix1` klónban: format, analyze,
  `practice_catalog_snapshot_test.dart` 9/9, `practice_engine_catalog_adapter_test.dart`
  5/5, architecture, secrets, l10n → **mind zöld**.
- Eldobható review-próba (`test/_review_probe_fix1_test.dart`, törölve) F1-et
  és F2-t is közvetlenül, a shipped teszteken kívül újra megmérte (ld. F1/F2
  Státusz sorok fent) — mindkettő megerősítve.
- A `dirty_files=1` mindkét jelzésben (első forduló és javító kör is) egy
  jóindulatú időzítési műtermék: a `codex-signal.sh done` a `git status
  --porcelain`-t a jelzésfájl `mv`-je ELŐTT méri, közvetlenül a záró commit
  után — mindkét esetben a workdir `git status --short` a jelzés után
  azonnal ellenőrizve **tiszta** volt, és a commit tartalma teljes/koherens
  volt a diff-stattal.

F1 és F2 javítva; N1 nem igényel akciót. Új BLOCKER vagy MAJOR nincs.

## Merge-döntés

ADR 0052 szerint: minden gate zöld ÉS nincs nyitott BLOCKER/MAJOR → merge.
Mind a hét gate-lépés zöld (első pass ÉS javító kör után is, két független
`/tmp` klónban), a scope-audit mindkétszer `OK`, F1/F2 zárva, N1
informális. **Merge engedélyezett.**
