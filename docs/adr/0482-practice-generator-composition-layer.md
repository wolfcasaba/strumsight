# ADR 0482 — A Practice Generator kompozíciós rétege: EGY gyökér, valódi tár, mechanikusan generált barrel

- **Státusz:** elfogadva
- **Dátum:** 2026-09-01
- **Kör:** `E15-R14` (Chapter 15, beszúrt előkészítő kör)
- **Implementer motor:** `sonnet-impl` (Claude Sonnet 5, `--effort high`)
- **Kapcsolódó:**
  [`0255`](0255-deterministic-first-practice-planning.md) (a generátor
  determinisztikus szerződése — ez a kör NEM nyúl hozzá),
  [`0260`](0260-skill-evidence-privacy-and-deduplication.md) (a bizonyíték
  „megváltoztathatatlan múlt", a lejárat lekérdezés-idejű; a `deleteForPlan` a
  szűk kivétel),
  [`0479`](0479-privacy-data-inventory-and-consent-enforcement.md) (adat-leltár:
  a leltár EGRESS-felület, a fából mérve — lásd D5),
  [`0471`](0471-screen-reachability-is-measured-not-assumed.md) (az elérhetőség
  MÉRT tulajdonság — a kör után a 6 terv-képernyő továbbra is `unreachable`),
  [`0306`](0306-plan-preview-presentation-activation-boundary.md) (a preview
  aktiválási határa),
  [`0002`](0002-feature-first-clean-architecture.md) (feature-first rétegek,
  kézzel írt Riverpod providerek, codegen nélkül)

## Kontextus — a pre-flight MÉRT tényei (2026-09-01, `main @ 26753c6f`)

Az `E15-R07` `stopped` jelzésének gyökéroka ([L561](../LESSONS.md)) az volt,
hogy a Practice Generator 6 terv-képernyője mögött **nincs kompozíció**. Az
önjavító kör mérése ezen a körön újra reprodukálódott:

| Mérés | Parancs | Eredmény (`main @ 26753c6f`) |
|---|---|---|
| Riverpod-provider a feature alatt | `grep -rln "Provider<\|NotifierProvider\|ChangeNotifierProvider" lib/features/practice_generator` | **ÜRES** (exit 1) — nulla provider |
| Konkrét `PracticeEvidenceRepository` | `grep -rn "implements PracticeEvidenceRepository" lib/` | **EGY** találat: `domain/repository/practice_evidence_repository.dart:107` — az `InMemoryPracticeEvidenceRepository` **teszt-fake** |
| A Setup-varázsló vége | `plan_setup_screen.dart:96–99` | a step-4 „Befejezés" gomb kizárólag `controller.next()`-et hív |

A motor MEGVAN: `GenerationOrchestrator` (`application/service/generation_orchestrator.dart:62`),
`LocalPracticePlanRepository implements GenerationPlanActivation` (`:139`),
`RevisePracticePlan` (`PlanRevisionProposal`-t termel, `:54`), a kontrollerek
mind léteznek. Ami hiányzik, az az **összeszerelés** és **egy darab valódi
repository**.

### További, a döntéseket megkötő mérések

1. **A `KeyValueStore`-nak NINCS kulcs-felsorolása.** A contract
   (`lib/core/storage/key_value_store.dart:22`) `read*`/`write*`/`remove`/
   `contains` felületet ad, `keys()`-t nem. A planner ezt már MEGOLDOTTA egy
   perzisztens **manifesttel** (`local_practice_plan_repository.dart:168`,
   `manifestKey`, „F1 fix… hydration is the only way to make delete-all /
   export-all restart-stable").
2. **A `SkillEvidence`-nek NINCS szerializációja.** `grep -n "toJson\|fromJson"
   lib/features/practice_generator/domain/model/skill_evidence.dart` üres, és a
   `data/` fában sincs evidence-serializer (csak `*_evidence_adapter.dart`
   fájlok, amik forrás-adatból KÉPEZNEK `SkillEvidence`-t, nem tárolnak).
3. **A `public.dart` GENERÁLT fájl.** `tool/gen_public_barrel.dart` a
   `public/*.dart` fragmenseket fűzi össze fájlnév-sorrendben, és
   `tool/check_architecture.dart:760` (`_checkGeneratedBarrels`) **code_failure**-t
   ad elavult barrelre: „run: dart run tool/gen_public_barrel.dart --write".
4. **A `docs/privacy/data-inventory.yaml` EGRESS-leltár.** A fájl saját fejléce
   (MINOR-5 hatóköri kimondás): „this document inventories EGRESS routes — data
   that LEAVES the device… `lib/core/storage/storage_keys.dart` declares 56
   persisted keys; NONE of them are inventoried here, on purpose". A checker
   (`tool/check_data_inventory.dart:431`, `discoverEgressRoutes`) kizárólag
   `Dio`/`ApiClient`/`SharePlus`/direkt-HTTP osztályokat talál a fában, és
   `wired: true` sorra, amit a fa nem termel, **violationt** ad (`:825`).

## Döntés

### D1 — EGY kompozíciós gyökér

A 6 terv-képernyő MINDEN kötelező konstruktor-függősége EGYETLEN fájlból
(`lib/features/practice_generator/presentation/providers/practice_generator_providers.dart`)
oldódik fel, kézzel írt Riverpod 3 providerekkel, codegen nélkül. Ez a fa mért
konvenciója: `lib/features/{practice,ai_tutor,vision,gamification}/presentation/providers/`
— négy rétegzett feature, mind ott tartja (a mért minta:
`ai_tutor/presentation/providers/tutor_providers.dart`, amely maga is közvetlenül
importálja a `core/storage/key_value_store.dart`-ot).

Képernyőnként külön, egymásra nem hivatkozó összeszerelés **tilos** — az pontosan
oda vinné vissza a bekötést, ahonnan az `E15-R07` kiment.

### D2 — A törlés TÉNY: a fake soha nem kerül a production-kompozícióba

A `PracticeEvidenceRepository` production-implementációja **perzisztens**, és a
`deleteForPlan` után az érintett bizonyíték **egy ÚJ repository-példányról,
ugyanarra a store-ra nyitva sem** olvasható vissza.

Az `InMemoryPracticeEvidenceRepository` bekötése „amíg a valódi elkészül"
**nem elfogadható**: a doc-commentje szerint „Keeps every evidence ever saved;
`query` filters, it never forgets" — mögé kötve a `PlanPrivacyScreen`
törlés-gombja hamis consent-felület lenne (CLAUDE.md „silent no-op" csapda,
[L06](../LESSONS.md), [L28](../LESSONS.md), ADR 0479).

Az ADR 0260 tulajdonlás-szerződése változatlan: a törlés a **rögzített
tulajdonlás** (`sourcePlanId`) alapján megy; ismeretlen tulajdonlású rekord
NEM törlődik (a hiányzó tulajdonlás elutasítás, nem joker).

### D3 — Saját kulcs-névtér + saját manifest, a szerializáció a repository fájljában

- Az új tár a planner tervkulcsaitól **elkülönült** névtérben él
  (`ss.practice_generator.evidence…`), soha nem ír a
  `ss.practice_generator.plan.*` vagy a `GenerationDraftRepository.draftStorageKey`
  kulcsokra. Az elkülönített névtér teszi strukturálisan lehetetlenné, hogy egy
  rossz evidence-írás az aktív tervet felülírja (ADR 0259 §3 mért mintája).
- Mivel a `KeyValueStore` nem sorolja fel a kulcsokat, a tár **saját
  manifesztet** vezet a `LocalPracticePlanRepository` mért mintájára — enélkül a
  `deleteForPlan` egy friss példányon nem tudná, mit kell törölnie, és a törlés
  néma no-op lenne (D2 sértése).
- A `SkillEvidence` JSON-képe a repository fájljában él. **Nem** jön létre külön
  serializer-fájl: a kör engedélyezett-listája egy `data/local/` fájlt ad, és a
  szerializáció ennek a tárnak a belső részlete (a `GenerationRequestSerializer`
  külön fájl-precedense azért más, mert azt két hívó — repo és export — osztja).
- Hibakezelés a `GenerationDraftRepository` mért mintája: sérült/olvashatatlan
  payload `AppResult.failure(StorageFailure)`, soha nem dobott kivétel és soha
  nem csendben eldobott rekord.

### D4 — Nincs no-op `GenerationPlanActivation`

A `PlanPreviewController.activation` a MÉRT, konkrét
`LocalPracticePlanRepository`-t kapja (`:139`). Egy `_NoopActivation`, amitől a
„Megerősítés" gomb aláír, de semmi nem aktiválódik, ugyanaz a hibaosztály, mint
a D2-é.

### D5 — Az on-device bizonyíték-tár NEM kerül az EGRESS adat-leltárba

A `docs/privacy/data-inventory.yaml` **kibocsátási** felületet leltároz (a fenti
4. mérés). Az új tár kizárólag eszközön belüli perzisztencia: nem termel
`discoverEgressRoutes` szerinti utat, tehát sorral bővíteni a leltárt vagy
gate-sértés (`wired: true` + nem talált forrás), vagy — `wired: false`-szal —
szemantikailag hamis bejegyzés egy kimondottan EGRESS-hatókörű dokumentumban,
amit a fájl saját fejléce tilt („Do not add a route here that the tree does not
also produce").

**A határ tehát kimondott, nem elhallgatott:** az on-device tár-leltár a
`docs/privacy/consent-enforcement.md` „What this document does not cover"
szakaszában már deklarált, önálló, még el nem kezdett feladat; ez az ADR ezt
megerősíti, és a jelen kör mércéje az, hogy a `test/tooling/data_inventory_test.dart`
**változatlanul zöld** (nem-regresszió), nem az, hogy a leltár bővül.

### D6 — A generált barrel újragenerálása a fragment-szerkesztés mechanikus következménye

A `public/{data,application,presentation}.dart` fragmensek szerkesztése után a
`lib/features/practice_generator/public.dart` barrelt a **generátorral** kell
frissíteni (`dart run tool/gen_public_barrel.dart --write`), mert a
`tool/check_architecture.dart` elavult barrelre code_failure-t ad, és a
`round-gate.sh` `architecture` lépése ezt méri. A barrel kézi szerkesztése tilos;
a fragmens a forrás, a barrel a derivátum.

### D7 — A kör NEM tesz elérhetővé képernyőt

A `dart run tool/check_screen_reachability.dart` verdiktje a 6 terv-képernyőre a
kör UTÁN is `unreachable` (ADR 0471). Route, `AppRoutes`-konstans, `app_router.dart`
és feature-flag mozdítása az `E15-R07 / F1` dolga; a fázissorrend kötött, mert a
flag-kapu biztonsági indoklása oda tartozik.

### D8 — Erőforrás-tartó provider `dispose`-ol

A `GenerationOrchestrator` broadcast `StreamController`-t tart
(`generation_orchestrator.dart:74`). Az őt építő provider `ref.onDispose`-ban
zárja le a tartott erőforrást (a repó mért `liveFrameProvider`-precedense: egy
erőforrást tartó providert figyelő provider maga is eldobható kell legyen,
különben az erőforrás bekapcsolva marad).

## Következmények

- Az `E15-R07 / F1` bekötése ezek után valóban „route + flag" méretű: a
  képernyők függőségei egyetlen `ProviderScope`-ból felépülnek.
- A `PlanPrivacyScreen` törlés/export gombja az első bekötés pillanatától
  **valódi** adatműveletet takar.
- A kör felületet nem ír, ARB-kulcsot nem mozdít, a `ui_inventory` egzakt
  darabszáma (96) változatlan.
- Egy jövőbeli, on-device tár-leltár (D5) az itt bevezetett kulcs-névteret és
  manifesztet készen találja.
