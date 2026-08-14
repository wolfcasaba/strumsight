# ADR 0220 — Audio Analysis V1/V2 parallel rollout boundary

- **Státusz:** Elfogadva (E06-R01 pre-flight, 2026-08-11)
- **Kör:** E06-R01 — Analyze V1 baseline, mérés és ADR-ek
- **Implementer motor:** Terra — az ADR-t az orchesztrátor (Claude Sonnet 5)
  írta a pre-flightban (ADR 0055).
- **Epic:** [Chapter 7 — Epic 6: Audio Analysis 2.0](../sdd/07-epic-06-audio-analysis-2.md)
  Kör 1; §30 (Rollout stratégia, teljes szakasz: §30.1-30.4) — a batch
  harmadik, keresztmetsző kiegészítése (a brief §0.0 szerint az SDD Kör 1
  három ADR-t nevez meg; ez a batch-bővítés egyike)
- **Kontext-ADR-ek:** [0197](0197-song-trainer-shipping-rollout-boundary.md)
  (Practice V2 + Song Trainer V2 shipping rollout, GOV-05a — a legutóbbi,
  ténylegesen végrehajtott két-fázisú rollout precedens), [0198](0198-learn-migration-rollout-boundary.md)
  (Learn migráció ugyanerre a mintára)
- **Sorszám-jegyzet:** lásd [ADR 0215](0215-analysis-document-versioning.md)
  fejléce — a teljes hatos blokk 0200–0205-ről 0215–0220-ra tolódott.

## Kontextus

**Mért 2026-08-11-én:**

1. Az SDD Ch7 §30.1 hét feature flaget javasol:
   `audioAnalysisV2Enabled`, `analysisBeatGridEnabled`,
   `analysisPitchEnabled`, `analysisTechniqueProxiesEnabled`,
   `analysisComparisonEnabled`, `analysisAudioRetentionEnabled`,
   `analysisExperimentalFusionEnabled`. §30.2 hét rollout-szintet ír le
   (unit teszt → developer-only → Lab mode → internal dogfood → opt-in
   beta → default-on → legacy Analyze eltávolítása). §30.3 (Shadow mode)
   és §30.4 (Rollback) a V1 párhuzamos, sértetlen futtatását követeli meg
   a teljes átmenet alatt.
2. **A `lib/app/config/feature_flags.dart` mai állapota (a HITELES forrás,
   nem a brief leírása):** `FeatureFlags.forEnvironment` egy `nonProd =
   environment != AppEnvironment.production` változót számol, és a
   Practice V2 / migrated Learn / Song Trainer V2 flageket ERRE állítja
   (`practiceEngineV2Enabled: nonProd`, `migratedLearnEnabled: nonProd`,
   `songTrainerV2Enabled: nonProd`, sor 57-60). A `songTrainerV2Enabled`
   doc-commentje (sor 98-102) kimondja: „the default constructor remains
   OFF… The flag has no dart-define override." **A `nonProd`-igaz érték
   NEM az induló állapot** — a Song Trainer V2 teljes E03 építő-epicje
   (7 kör) alatt a flag defaultja `false` maradt (a konstruktor
   alapértéke), és csak a KÜLÖN, később futó GOV-05a rollout-kör
   ([ADR 0197](0197-song-trainer-shipping-rollout-boundary.md)) kapcsolta
   `nonProd`-igazra a `FeatureFlags.forEnvironment` factoryban. A `songTrainerV2Enabled`
   precedens tehát KÉTFÁZISÚ: (1) építő epic — flag off mindenhol, csak a
   konstruktor default; (2) külön GOV-rollout-kör — a factory bekapcsolja
   nonProd-ban.
3. **Dart-define override egyik meglévő V2-rollout flagnek sincs** —
   `accountEnabled` az egyetlen, amelyiknek van (`STRUMSIGHT_ACCOUNT`
   define, feature_flags.dart sor 36-38 doc-comment); a Practice V2/
   Learn-migráció/Song Trainer V2 egyike sem force-olható be production
   buildben dart-define-nal. Ez a MECHANIZMUS-szintű precedens, amit ez
   az ADR átvesz.
4. **Epic 6 a mai napon (2026-08-11) indul először** (`chore(queue): Epic 6
   FELOLDVA` — a queue mind a 30 sora `hold`→`pending`) — azaz jelenleg
   az 1. fázisban vagyunk (SDD §30.2 „1. unit és fixture teszt"), a
   `songTrainerV2Enabled` építő-epic-fázisának pontos analógjában.
5. A HANDOFF §2 és a `CLAUDE.md` egyaránt rögzíti: a V1 Analyze **ma
   szállított, éles út**, amit a felhasználó minden környezetben használ —
   ez nem cserélhető le egy 30 körös epic KÖZBEN.

## Döntés

1. **`audioAnalysisV2Enabled` (+ SDD §30.1 al-flagek:
   `analysisBeatGridEnabled`, `analysisPitchEnabled`,
   `analysisTechniqueProxiesEnabled`, `analysisComparisonEnabled`,
   `analysisAudioRetentionEnabled`, `analysisExperimentalFusionEnabled`)
   default `false` MINDEN környezetben — beleértve `nonProd`-ot is —
   **a teljes Epic 6 építő-fázisa alatt** (a 30 kör mindegyike alatt).**
   Ez a `songTrainerV2Enabled` PONTOS analógja a saját építő-epicjének
   (E03) 7 köre alatt, NEM a mai (GOV-05a utáni) `nonProd`-igaz értéke —
   lásd [Kontextus] 2. pont. Egy KÜLÖN, jövőbeli GOV-rollout-kör (a
   GOV-05a mintájára) dönt majd a `nonProd`-bekapcsolásról, csak az Epic 6
   lezárása UTÁN.
2. **Nincs dart-define override egyik audio-analysis-v2 flagre sem** — a
   `songTrainerV2Enabled`/Practice-flagek mechanizmus-szintű precedense
   szerint. Egy production build soha nem tudja force-olni a V2 utat.
3. **A V1 Analyze a teljes Epic 6 alatt a shipping út marad.** A meglévő
   `lib/features/analyze/`, `lib/features/library/` kód és a mögöttük álló
   tesztek **nem törölhetők, nem cserélhetők, nem írhatók át a zöldért**
   — egy elbukó meglévő V1 teszt **megállás és jelentés**, nem a teszt
   gyengítése vagy törlése (a brief §5 pont 6 szó szerinti előírása).
4. **Rollout-lépcső a SDD §30.2 hét szintje szerint**, ugyanabban a
   sorrendben, mint a Song Trainer V2/Learn migráció: unit/fixture teszt
   (ma) → developer-only → Lab mode → internal dogfood → opt-in beta →
   default-on → legacy Analyze eltávolítása. Minden lépcső **külön,
   emberi jóváhagyást igénylő GOV-kör** — a §30.2 nem azt jelenti, hogy
   ez a kör vagy bármelyik Epic 6 építő-kör automatikusan lépteti a
   szintet.
5. **Shadow mode (SDD §30.3) csak Lab környezetben, csak diagnosztikai
   célra** — a V1 user-facing eredmény a shadow-futás alatt is
   változatlan; a V2 kimenet kizárólag Lab-diagnosztikában látható.
6. **Rollback garancia (SDD §30.4):** a feature flag-gel a V1-re
   visszaállás mindig lehetséges; a V2 storage-formátum megléte nem teszi
   irreverzibilissé a V1-re váltást; a Library mindkét dokumentum-verziót
   olvasni tudja a migráció teljes ideje alatt.

**NEM elfogadható:** `audioAnalysisV2Enabled` (vagy bármely al-flag)
`nonProd`-igaz alapértelmezéssel bevezetése egy Epic 6 építő-körben (a
GOV-05a-mintájú bekapcsolás KÜLÖN, jövőbeli kör dolga); dart-define
override hozzáadása bármelyik V2 flaghez; a meglévő V1 Analyze/Library
teszt módosítása vagy törlése azért, hogy egy V2-t érintő diff zöld
gate-et kapjon; a V1 és V2 storage-formátum közötti irreverzibilis
migráció egyetlen körben.

## Következmények

**E06-R30 (2026-08-13):** megerősítve: mind a kilenc Epic 6 flag OFF minden környezetben, a V1 shipping út változatlan; a V2 shadow szerződés hívó nélkül tesztelt.

- Minden Epic 6 építő-kör (E06-R02…R30) a `lib/app/config/feature_flags.dart`-ot
  **tilos zónaként** kezeli, hacsak a brief kifejezetten nem sorolja fel az
  `allowed_paths`-on — a flag hozzáadása/bekapcsolása explicit, dedikált
  döntés.
- A V2 kód a teljes építő-fázis alatt **hívó/wiring nélkül** épül (az Epic 3
  Song Trainer V2 és az Epic 5 Vision épp követett mintája: „hívó UI/
  provider nincs, production viselkedés változatlan") — production
  viselkedés bitre azonos marad minden Epic 6 körön át, amíg a GOV-rollout
  kör másképp nem dönt.
- A rollout-szintek (SDD §30.2) egy jövőbeli GOV-kör lánc dolga, a
  GOV-05a/05c mintájára — ez a kör csak a HATÁRT rögzíti, nem a
  rollout ütemezését.

## Elutasított alternatívák

- **`audioAnalysisV2Enabled: nonProd` már most, hogy a fejlesztők korán
  láthassák.** Elvetve: a `songTrainerV2Enabled` KÉTFÁZISÚ precedense
  ([Kontextus] 2. pont) kifejezetten azt mutatja, hogy a korai
  bekapcsolás egy félkész, 30 körön át épülő domain-t tenne láthatóvá
  nonProd buildekben — pontosan azt a hibaosztályt kockáztatva, amit a
  Vision rollout (HANDOFF §3, GOV-05d) mért: a flag bekapcsolása egy
  zsákutcába futó UI-t tenne láthatóvá félkész funkcionalitással.
- **Dart-define override hozzáadása gyors QA-teszteléshez.** Elvetve: a
  meglévő flagek egyikének sincs ilyen mechanizmusa (a `songTrainerV2Enabled`
  doc-comment explicit kizárja); egy kivétel ezen a feature-ön
  inkonzisztens mintát vinne a repóba, amit a review MAJOR-ként fogna el.
- **A V1 Analyze azonnali deprecation-jelölése ebben a körben** (pl.
  `@Deprecated` annotáció a kódban). Elvetve: a V1 a teljes Epic 6 alatt
  éles, elsődleges út marad — egy deprecation-jelzés félrevezető lenne,
  és a brief §3 „TILOS: bármilyen lib/ változtatás" szabályát is sértené.

## A visszavonás feltétele

Felülvizsgálandó, ha az Epic 6 építése közben (bármelyik E06-RXX körben)
egy MÉRT indok mutatja, hogy a teljes-epic-alatt-off szabály gyakorlati
akadályt jelent (pl. egy köztes körnek valós eszközön kellene tesztelnie
a V2 utat egy hívó nélkül) — ekkor a kivétel egy dedikált, dokumentált
GOV-mikro-kör dolga, explicit ADR-felülvizsgálattal, nem egyetlen építő-kör
csendes flag-bekapcsolásával. A rollout-szintek (SDD §30.2) elérésekor
(Epic 6 lezárása után) ez az ADR a GOV-05a mintájú rollout-kör
ELŐFELTÉTELE marad, nem a rollout maga.
