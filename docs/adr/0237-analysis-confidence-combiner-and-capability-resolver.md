# ADR 0237 — Analysis confidence combiner and capability resolver

- **Státusz:** Elfogadva (E06-R19 pre-flight, 2026-08-12)
- **Kör:** E06-R19 — Confidence calibration és capability resolver
- **Implementer motor:** Terra — az ADR-t az orchesztrátor (Claude Sonnet 5)
  írta a pre-flightban (ADR 0055).
- **Epic:** [Chapter 7 — Epic 6: Audio Analysis 2.0](../sdd/07-epic-06-audio-analysis-2.md)
  Kör 19; §7.5 (Publikációs szabály), §19.1–19.6 (Confidence és kalibráció)
- **Kontext-ADR-ek:** [0216](0216-analysis-confidence-calibration-and-abstention.md)
  (confidence/kalibráció/abstention szerződés — **ez a kör implementálja**),
  [0219](0219-analysis-capability-aware-publication.md) (capability-aware
  publikációs szerződés — **ez a kör implementálja**), [0218](0218-analysis-metric-id-and-version-governance.md)
  (metrika-verzió kormányzás — a `thresholdsVersion` emelési szabálya innen jön)
- **Sorszám-jegyzet:** a kör briefje (`docs/rounds/e06-r19-confidence-calibration-capability-resolver.md`,
  írva 2026-08-07) §0.0/§1/§5-ben „ADR 0201”, „ADR 0204” és „ADR 0203”
  hivatkozásokat visel. Ezek a számok **elavultak**: az R01 pre-flight
  (2026-08-11) a teljes hatos ADR-blokkot 0200–0205-ről 0215–0220-ra
  tolta, és ezt mindkét célzott ADR fejléce önmaga dokumentálja (lásd
  [0216](0216-analysis-confidence-calibration-and-abstention.md) és
  [0219](0219-analysis-capability-aware-publication.md) „Sorszám-jegyzet"
  sora). A helyes megfeleltetés: 0201→0216, 0204→0219, 0203→0218. A
  brief §0.0 revíziója (lásd a brief-fájlban) ezt javítja; ez az ADR a
  javított számokra hivatkozik.

## Kontextus

**Mért 2026-08-12-én, `main` @ `cc8faca1`** (a brief mérési baseline-je
`a6e6f3d`, 192 commit renonszanciával — a pre-flight ezért újramérte a
brief minden konkrét állítását a kódban, nem csak elfogadta őket):

1. **A capability-domainmodell (E06-R02) változatlan és a brief állítása
   pontos:** `lib/features/audio_analysis/domain/analysis_capability.dart`
   — `AnalysisCapability` **14** érték, `CapabilityStatus` **4** érték
   (`available`/`degraded`/`unavailable`/`notApplicable`),
   `CapabilityUnavailableReason` **13** érték, `CapabilityReport` már
   value-osztályként létezik (`confidence ∈ [0,1]` konstruktor-guard,
   `unavailable` ⇒ kötelező `reason`). Egyik szám sem tért el a brieftől.
2. **Három szórt kapu létezik, de csak kettő dönt ma ténylegesen
   `CapabilityStatus`-t:** `MetricGate` (`engine/metrics/metric_gate.dart`,
   R14) **csak bool küszöböt** ad (`isAvailable`/`isStreakAvailable`), nem
   épít `CapabilityReport`-ot. `DynamicsGate`
   (`engine/metrics/dynamics_gate.dart`, R16) és `PitchCapabilityGate`
   (`engine/pitch/pitch_capability_gate.dart`, R17) viszont **mindketten
   önállóan konstruálnak** `CapabilityStatus`/`CapabilityReport`-ot saját,
   a saját fájljukban élő küszöbökkel — ez pontosan az a párhuzamos
   kapu-döntés, amit a brief §5 pont 1 kizár.
3. **Egyik fájl sem éri el a kör `allowed_paths`-át:** a `dynamics_gate.dart`
   a brief §4 explicit tilos zónájában él (`.../engine/metrics/**`), a
   `pitch_capability_gate.dart` pedig `.../engine/pitch/**` alatt van, ami
   nincs az engedélyezett listán ÉS nincs a tilos zóna felsorolásában sem
   — egyik oldalról sem hozzáférhető ebben a körben új fájllista-bővítés
   nélkül.
4. **Az ARB-ekben nincs egyetlen `CapabilityUnavailableReason`-specifikus
   kulcs sem** (`grep -n "clipTooShort\|insufficientEvents\|…" lib/l10n/app_en.arb`
   nulla találat) — a 13 kulcs hozzáadása valóban tisztán additív, nincs mit
   felülírni vagy migrálni.
5. **A `confidenceThreshold` beállítás (`settings/providers/confidence_threshold_provider.dart`)
   kizárólag a Live útvonalon fogyasztott** (`settings_sync.dart`), az
   Analyze-ot nem érinti — a brief állítása pontos, ez egy különálló
   tengely, nem ennek a körnek a bemenete.

## Döntés

1. **Egyetlen belépő, ahogy a brief §5 pont 1 kimondja:** `CapabilityResolver`
   (`engine/confidence/capability_resolver.dart`) az egyetlen hely, ami
   `CapabilityStatus`-t és publikált `confidence`-et rendel egy
   capabilityhez. Bemenete jelminőség, eseményszám, modell-confidence,
   target elérhetőség, illesztési minőség, mód és modell-elérhetőség —
   állapotmentes, determinisztikus (ADR 0216 Döntés 2, ADR 0219 Döntés 2).
2. **`ConfidenceCombiner`** (`engine/confidence/confidence_combiner.dart`):
   geometriai átlag a FÜGGETLEN tényezőkön (signal quality, model
   confidence, alignment quality) `max(ε, x)` alsó vágással (`ε = 1e-6`),
   majd `min` a KEMÉNY kapukkal (eseményszám elég? modell elérhető?) — a
   brief OD-02 alapértelmezése, dokumentáltan ADR 0216 Döntés 2
   (aggregátum, nem nyers modellkimenet) végrehajtása.
3. **`CalibrationTable`** (`engine/confidence/calibration_table.dart`):
   verziózott, monoton nemcsökkenő leképezés nyers score → kalibrált
   confidence. A V1 tábla `identity.v1` — **nem** valódi kalibráció,
   explicit jelöléssel (ADR 0216 Döntés 1: „nyers score ≠ publikált
   confidence", de kalibrációs dataset hiányában az identitás-leképezés
   az egyetlen őszinte induló állapot).
4. **`CapabilityThresholds`** (`engine/confidence/capability_thresholds.dart`):
   a szórt küszöbök egy helyen, `thresholdsVersion` mezővel — küszöb-
   módosítás metric-version emelést von maga után (ADR 0218). A
   degraded/available határ a brief OD-03 alapértelmezése: `[0.4, 0.7)` →
   degraded (0.4 inkluzív), `≥ 0.7` → available (0.7 inkluzív), `< 0.4` →
   unavailable/`confidenceTooLow`.
5. **Ez a kör ÚJ, önálló, be nem kötött modult szállít** — az Epic 6
   mind a 17 eddigi körének mintáját követve (R02 domainmodell, R07
   quality-stage, R14 `MetricGate`, R16 `DynamicsGate`, R17
   `PitchCapabilityGate` mind flag/hívó nélkül szállított). A
   `CapabilityResolver`-t **semmi nem hívja** ebben a körben — ez
   szándékos, nem hiány.
6. **A brief §8 lépéssor 6. pontja („A metrika-modulok kapu-hívásainak
   átvezetése") KIVÉVE ebből a körből.** A [Kontextus] 2–3. pontjában mért
   ok: a `DynamicsGate`/`PitchCapabilityGate` retrofitja a saját fájljuk
   módosítását igényelné, ami vagy a tilos zóna feloldása
   (`dynamics_gate.dart`), vagy a fájllista bővítése
   (`pitch_capability_gate.dart`) lenne — egyik sem összeegyeztethető egy
   „egyetlen új modult szállító" körrel. **Egyik acceptance criterion sem
   igényli ezt a retrofitot** (mindegyik a resolvert közvetlenül,
   szintetikus bemenettel hívja). A brief §6 „Egyetlen döntési pont"
   kritériumát ezért **strukturálisan, az ÚJ modulra szűkítve** kell
   mérni: a teszt azt bizonyítja, hogy az `engine/confidence/**` fájlok
   között pontosan egy hely dönt `CapabilityStatus`-ról (statikus
   forrásolvasó vagy hívásszámlálós seam a brief saját megfogalmazása
   szerint — ez már eleve megengedte ezt az olvasatot), **nem** azt, hogy
   a teljes repóban (a már merge-elt R16/R17 kódot is beleértve) sehol
   máshol nem dől el capability-státusz. A retrofit egy jövőbeli bekötő
   kör feladata marad (HANDOFF §3 follow-up).

## Következmények

- `lib/features/audio_analysis/engine/confidence/` négy új fájlja + a
  `domain/analysis_capability.dart` additív bővítése (ha az implementáció
  új `details`-kulcsot vagy hasonlót igényel) + `public.dart` export +
  ARB additív kulcsok — a teljes diff a brief `allowed_paths` listáján
  belül marad.
- `DynamicsGate` és `PitchCapabilityGate` **változatlanok maradnak**, és
  ezért **továbbra is önállóan döntenek** `CapabilityStatus`-ról a saját
  hívási útvonalukon — ez egy MÉRT, dokumentált, nyitva hagyott
  párhuzamosság, nem regresszió (mindkettő ma is bekötetlen, `false`
  flag mögött). Egy jövőbeli kör feladata a retrofit; a HANDOFF §3-ban
  rögzítve.
- A `docs/manual-testing/analysis-eval-matrix.md` fájlt ez a kör **nem**
  módosítja — nincs az `allowed_paths`-on, és a kalibrációs dataset/
  reliability-diagram munka explicit R29 scope (brief §3 „Kívül —
  TILOS").

## Elutasított alternatívák

- **Számtani átlag az overall confidence-hez.** Elvetve — ADR 0216
  Kontextus/Döntés + a brief §6 „nincs átlag" mérce-cellája explicit
  PIROSra teszi.
- **A `DynamicsGate`/`PitchCapabilityGate` azonnali retrofitolása ebben a
  körben** (fájllista-bővítéssel vagy a tilos zóna feloldásával). Elvetve:
  egyik file sem éri el az `allowed_paths`-at a jelen brief szerint, a
  bővítés önmagában egy külön, nagyobb kockázatú döntés lenne (a tilos
  zóna pontosan azért véd, mert az R14–R18 terület metrikaszámítást
  hordoz), és egyik acceptance criterion sem igényli — a brief §9 saját
  maga ezt nevezi meg legvalószínűbb pre-flight leletként, résre nyitott
  feloldással (`stopped` + brief-revízió a fájllista bővítéséről **VAGY**
  a lépés kihagyása). Az utóbbit választottuk, mert olcsóbb, kisebb
  kockázatú, és semmilyen acceptance criteriont nem gyengít.
- **A brief `allowed_paths`-ának bővítése a stale ADR-hivatkozások
  miatt.** Nem szükséges — a hivatkozás-javítás dokumentum-szintű
  (a brief saját szövegében, §0.0-ban), nem igényel új fájlt.

## A visszavonás feltétele

Felülvizsgálandó, ha egy jövőbeli bekötő kör azt méri, hogy a
`CapabilityResolver` bemeneti szerződése nem elég kifejező a
`DynamicsGate`/`PitchCapabilityGate` tényleges retrofitjához (pl. hiányzó
bemeneti dimenzió) — ekkor a resolver kontraktusát ADR-felülvizsgálattal,
nem hallgatólagosan kell bővíteni.
