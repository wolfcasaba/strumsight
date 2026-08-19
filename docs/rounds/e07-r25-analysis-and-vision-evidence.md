# E07-R25 — Analyze és Computer Vision evidence integráció

- **Státusz:** PREPARED — self-heal E07-R25/H3 brief-bővítés után (2026-08-19, `main @ 90df4d04`)
- **Típus:** Epic 7 (AI Practice Generator), SDD Ch8 Kör 25
- **Kör-azonosító:** `E07-R25`
- **Branch:** `<motor>/e07-r25-analysis-and-vision-evidence`
- **Előfeltétel:** `E07-R24` merge-elve (dal-integráció)
- **Brief szerzője:** Claude (Opus 5)
- **Pre-flight ADR:** [ADR 0319](../adr/0319-vision-evidence-provenance-and-safe-boundary-prerequisite.md)

## 0.0 Pre-flight revízió — HALT H3

**Mérés (2026-08-19, `main @ 90df4d04`).** A brief régi alapja
`19b30557` volt. A jelenlegi `lib/app/config/feature_flags.dart:24-43` és
`80-99` szerint minden Vision- és Audio Analysis V2 flag továbbra is `false`,
tehát a degradációs elv helyes. Az Audio Analysis root `public.dart`-ja
létezik, de túl széles: data-, engine-, presentation- és raw-közeli típusokat
is exportál (`lib/features/audio_analysis/public.dart:28-126`). A Vision root
barrelje ugyanezt a problémát hordozza (`lib/features/vision/public.dart:9-85`);
az ADR 0193 által bevezetett szűk `vision/domain/integration/public.dart`
viszont a jelen kör prioritás-mappingjához nem ad át numerikus, skillhez kötött
performance-értéket.

**Blokkoló szerződési rés.** A planner `SkillEvidence.source` mezője a
`lib/features/practice_generator/domain/model/skill_evidence.dart:17-21`
alapján csak `learn`, `progress`, `analyzeV2` és `selfReport` lehet. A Vision
evidence-et ezért csak hibás provenance-nal lehetne `analyzeV2`-nek címkézni,
vagy a jelen brief tilos zónáját áttörve kellene a közös evidence-modellt és
tesztjeit bővíteni. Egyik sem elfogadható. A jelen scope nem tartalmazza sem
a hiteles Vision-forrást, sem a `vision` source-értéket, ezért a §1 cél és
A5/A6/A8 korrektül nem teljesíthető.

**Döntés.** A kör nem dispatch-elhető. A következő, új briefnek explicit
engedélyeznie kell (1) a provenance-megőrző Vision source-változatot és annak
regressziós tesztjeit a Practice Generator evidence-modellben, valamint (2) a
Visionből kizárólag származtatott, skillhez rendelt, numerikus evidence-et
átadó szűk publikus contractot és annak boundary-őrét. A wide public barrel
vagy bármely raw/internal Vision típus használata nem alternatíva. L308,
L190, ADR 0193 és ADR 0260 releváns előzmény; a RAG index friss volt
(`90df4d04`, 2026-08-19T00:26:21Z).

### 0.0.1 Önjavító kör (ADR 0112, E07-R25/H3) — a follow-up brief bővítése

**Mérés (self-heal, 2026-08-19, izolált worktree `main @ 90df4d04`-ről).** Az
ADR 0319 döntése helyes, de a saját megnevezett fájllistája hiányos volt egy
MÁSODIK, tőle független szerződési rés miatt: az `EvidenceWeightPolicy.
sourceReliability` (`lib/features/practice_generator/domain/policy/
evidence_weight_policy.dart:66-71`) egy `default` ág NÉLKÜLI, kimerítő
`switch (source)`-t futtat a 4 jelenlegi `EvidenceSource` értéken. Egy ötödik
(`vision`) érték hozzáadása `skill_evidence.dart`-hoz enélkül nem HALT-ot,
hanem egy MÁSIK, kevésbé olvasható hibát adna: `flutter analyze` non-
exhaustive-switch hibával állna le egy olyan fájlban, amit a brief továbbra
sem engedne módosítani. Ez a self-heal ezt a második rést is bezárja, a
javítás egyetlen — az ADR 0319-cel egyenrangú — brief-bővítés.

A második fél (a Vision-oldali narrow contract) helye: `lib/features/vision/
domain/evidence/public.dart` — ÚJ fájl, az ADR 0193/[[L193]] már bevált
mintáját követve (egy meglévő wide barrel MÓDOSÍTÁSA helyett egy önálló, szűk
NESTED `public.dart`, amit az `ADR 0176`
`tool/check_architecture.dart:_isFeaturePublicBarrel` guardja módosítás
nélkül, bármely `/public.dart`-ra végződő fájlként már ma legális
cross-feature határnak fogad el). Ez a fájl KIZÁRÓLAG a már meglévő, mért
raw-media-mentes fúziós kimenetet exportálhatja:
`VisionEvidence`/`ObservationState` (`domain/evidence/vision_evidence.dart`),
`EvidenceMetric`/`EvidenceMetricFamily` (`domain/evidence/
vision_observation.dart` — a `VisionEvidence.metric` mező típusa) és
`EvidenceProvenance`/`EvidenceWindow`/`GeometrySource`
(`domain/evidence/evidence_provenance.dart` — verziózott/minőségi metaadat,
nem mérési nyersadat). A `domain/evidence/` könyvtár TÖBBI fájlja
(`vision_observation.dart` teljes `VisionObservation` típusa,
`confidence_model.dart`) és minden landmark/geometry/provider/presentation
típus **kívül marad** — a kontraktus nem a könyvtár, csak ez az egy ÚJ fájl.

**A follow-up implementernek tilos** ebből a fájlból bármilyen kamera-
koordinátát, landmarköt, frame-et vagy fájlútvonalat exportálnia; az A1
valódi-sértés próba (§6.1) erre a fájlra is vonatkozik.

`allowed_paths` és `gate_tests` az alábbi öt bejegyzéssel bővül (az ADR 0319
által feltételezett kilenc eredeti bejegyzés változatlan):

```
lib/features/practice_generator/domain/model/skill_evidence.dart
lib/features/practice_generator/domain/policy/evidence_weight_policy.dart
lib/features/vision/domain/evidence/public.dart
test/features/practice_generator/evidence/skill_evidence_test.dart
test/features/practice_generator/skill_estimate/evidence_weight_policy_test.dart
```

Regressziós védelem (a jelen self-healnél, nem a follow-up implementernél):
`tools/tests/test_e07_r25_vision_evidence_scope.py` — méri az
`EvidenceSource`/`sourceReliability` jelenlegi (4-értékű, kimerítő) alakját,
a három újranyitott Vision-típus raw-mentességét, és hogy `allowed_paths`
pontosan ezzel az öt bejegyzéssel bővült, egyetlen szomszédos fájl vagy
könyvtár SEM esik bele járulékosan.

**Visszakeresett előzmény** (`node tools/knowledge-rag.mjs --top 5 "vision
evidence provenance narrow public contract EvidenceSource skill evidence"`,
self-heal, 2026-08-19): a legjobb találatok a §0.0.1 döntést megerősítik, nem
ellentmondanak neki — az SDD Ch8 evidence-checklist
(`docs/sdd/08-epic-07-ai-practice-generator.md#369`) explicit kimondja, hogy
minden evidence provenance-t/confidence-et/verziót hordozzon és hogy nyers
audio/videó sosem kerül a generátor domainbe; a `vision_evidence.dart`
találat ugyanazt a fúziós kimenetet mutatja, amit a §0.0.1 exportálni kíván.
Nincs ellentmondó vagy korábban figyelmen kívül hagyott lecke.

> ⚠ **Pre-flight (indítás előtt KÖTELEZŐ):** mérd meg az Audio Analysis V2
> **tényleges** `public.dart` felületét és a **flagek állását** — a GOV-30c óta
> a lánc futtatható, de minden flag OFF. A vision flagek szintén OFF. A
> generátornak **mindkettő nélkül is teljesen működnie kell**. Eltérésnél
> §0.0 revízió.

```ai-router
schema_version = 1
risk = "high"
allowed_paths = [
  "lib/features/practice_generator/application/port/analysis_evidence_reader.dart",
  "lib/features/practice_generator/application/port/vision_evidence_reader.dart",
  "lib/features/practice_generator/data/adapter/analysis_evidence_adapter.dart",
  "lib/features/practice_generator/data/adapter/vision_evidence_adapter.dart",
  "lib/features/practice_generator/public.dart",
  "test/features/practice_generator/evidence_integration/analysis_evidence_adapter_test.dart",
  "test/features/practice_generator/evidence_integration/vision_evidence_adapter_test.dart",
  "test/fixtures/practice_generator/evidence_integration/",
  "docs/rounds/e07-r25-analysis-and-vision-evidence.md",
  "lib/features/practice_generator/domain/model/skill_evidence.dart",
  "lib/features/practice_generator/domain/policy/evidence_weight_policy.dart",
  "lib/features/vision/domain/evidence/public.dart",
  "test/features/practice_generator/evidence/skill_evidence_test.dart",
  "test/features/practice_generator/skill_estimate/evidence_weight_policy_test.dart",
]
gate_tests = [
  "test/features/practice_generator/evidence_integration/analysis_evidence_adapter_test.dart",
  "test/features/practice_generator/evidence_integration/vision_evidence_adapter_test.dart",
  "test/features/practice_generator/evidence/skill_evidence_test.dart",
  "test/features/practice_generator/skill_estimate/evidence_weight_policy_test.dart",
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

Lezáró jelzés nélkül a kör bukott. Listán kívüli fájl → `stopped`.

## 1. Cél

Az elemzés és a gépi látás **származtatott, confidence-aware** jeleinek
bekötése a terv-prioritásba (SDD Ch8 Kör 25).

## 2. Jelenlegi állapot — mért tények

- Az Audio Analysis V2 a GOV-30c óta **futtatható**, de **minden flagje OFF**.
  A vision flagek szintén OFF.
- Az ADR 0260 §1: **nyers audio/videó soha nem kerül evidence-be** — ez a kör
  a legveszélyesebb pont, mert itt van a legtöbb kísértés.
- Az ADR 0261 §2: az `unknown` nem gyengeség.
- Az R05 evidence-modellje már hordozza a forrást és a confidence-t.

## 3. Scope

**Benne van:** időzítés-, tempóstabilitás-, ütés-egyensúly-, akkord- és
hotspot-evidence leképezése · **csak engedélyezett** vision-proxyk · a
capability-hiány és az alacsony bizonyosság kezelése · a **jelminőség-hiba**
elkülönítése a **készség-hibától** · több forrás közti konfliktus fixture-je ·
(self-heal E07-R25/H3, §0.0.1) egy hiteles `EvidenceSource.vision` érték +
regressziós teszt, és egy Vision-owned, szűk, raw-mentes `public.dart`
contract a `domain/evidence/` alatt, kizárólag a §0.0.1-ben megnevezett
típusokkal.

**NINCS benne (tilos):** **nyers frame vagy nyers audio bármilyen formában** ·
flag `true`-ra állítása · az Analyze/Vision feature-ök módosítása (a §0.0.1
egyetlen, névre szólóan engedélyezett ÚJ Vision-fájl kivételével) · más
feature belső importja · `docs/adr/**`, `tools/**`, `.github/**`.

## 4. Engedélyezett fájlok

| Útvonal | Indok |
|---|---|
| `application/port/analysis_evidence_reader.dart` | **ÚJ** — port |
| `application/port/vision_evidence_reader.dart` | **ÚJ** — port |
| `data/adapter/analysis_evidence_adapter.dart` | **ÚJ** |
| `data/adapter/vision_evidence_adapter.dart` | **ÚJ** |
| `public.dart` | a barrel bővítése |
| `test/…/evidence_integration/*_test.dart` (2 db) | a §6 cellái |
| `docs/rounds/e07-r25-…md` | a §10 handoff |
| `domain/model/skill_evidence.dart` | **(§0.0.1)** `EvidenceSource.vision` érték |
| `domain/policy/evidence_weight_policy.dart` | **(§0.0.1)** a kimerítő switch új ága — enélkül nem fordul |
| `vision/domain/evidence/public.dart` | **(§0.0.1) ÚJ** — szűk, raw-mentes Vision→skill contract |
| `test/…/evidence/skill_evidence_test.dart` | **(§0.0.1)** a `vision` érték regressziós teszt |
| `test/…/skill_estimate/evidence_weight_policy_test.dart` | **(§0.0.1)** az új reliability-ág teszt |

**Tilos zóna:** `lib/features/audio_analysis/**` és `lib/features/vision/**`
tartalma **a fenti, §0.0.1 alatt névre szólóan engedélyezett EGY ÚJ fájl
kivételével** · `lib/app/config/feature_flags.dart` · `docs/adr/**` ·
`tools/**`. A `vision/domain/evidence/` könyvtár minden MÁS fájlja (a
meglévő `vision_evidence.dart`, `vision_observation.dart`,
`evidence_provenance.dart`, `confidence_model.dart`) továbbra is tilos —
azokból csak EXPORTÁLNI szabad az új `public.dart`-on át, tartalmuk nem
módosítható.

## 5. Kötött architekturális döntések

### 5.1 NYERS média SOHA nem lép át a határon

Sem hangminta, sem képkocka, sem fájlútvonal. Az ADR 0260 §1 és az ADR 0254 §2
együttes betartása. **Az ellenőrzés a szerializált evidence-en történik**, nem
a típusokon — a szivárgás típusszinten nem látszik.

### 5.2 Vision NÉLKÜL a generátor TELJESEN működik

A vision opcionális jel. Ha a flag OFF vagy a capability hiányzik, a tervezés
zavartalanul fut — csak kevesebb bemenettel.

**NEM elfogadható gyengítés:** a vision-adapter hiánya hibát vagy üres tervet
okoz.

### 5.3 Az ALACSONY bizonyosság nem vált ki agresszív fókuszt

Egy bizonytalan mérésből nem lesz intenzív drill. Az ADR 0261 §3
(konfliktus → bizonytalanság) folytatása a bemeneti oldalon.

### 5.4 A JELMINŐSÉG-hiba nem készség-hiba

Ha a felvétel zajos vagy a kamera nem látta a kezet, az **nem** azt jelenti,
hogy a tanuló rosszul játszott. Ilyenkor **beállítási/felmérési** javaslat
indokolt, nem nehezítés vagy könnyítés.

**NEM elfogadható gyengítés:** rossz jelminőségből gyenge teljesítményt
következtetni. Ez az ADR 0268 (technikai hiba ≠ skill-hiba) rokona.

### 5.5 Csak ENGEDÉLYEZETT vision-proxyk

A vision-jelek közül csak a kifejezetten engedélyezett, származtatott proxyk
használhatók. Nincs „ha már látjuk, használjuk" bővítés.

### 5.6 A több forrás közti konfliktus BIZONYTALANSÁGOT ad

Ha az audio és a vision ellentmond, az eredmény magasabb bizonytalanság — nem
az egyik önkényes preferálása (ADR 0261 §3).

### 5.7 A Vision-owned `public.dart` contract kizárólag fúziós kimenetet exportál (self-heal E07-R25/H3, §0.0.1)

Az ÚJ `lib/features/vision/domain/evidence/public.dart` csak a §0.0.1-ben
névre szólóan felsorolt típusokat (`VisionEvidence`, `ObservationState`,
`EvidenceMetric`, `EvidenceMetricFamily`, `EvidenceProvenance`,
`EvidenceWindow`, `GeometrySource`) exportálhatja. Landmark, pose, frame,
kamera-koordináta, provider vagy presentation típus ezen a fájlon **soha** —
ez ugyanaz a szabály, mint az 5.1, csak a Vision-oldali kilépési pontra
alkalmazva (ADR 0193/[[L193]] mintája).

## 6. Acceptance criteria

| # | Kritérium | Bizonyíték |
|---|---|---|
| A1 | **Nyers média nem lép át** — a szerializált evidence vizsgálata | mindkét adapter-teszt |
| A2 | Vision nélkül a generátor teljes értékű | `vision_evidence_adapter_test.dart` |
| A3 | Alacsony bizonyosság NEM vált ki agresszív fókuszt | `analysis_evidence_adapter_test.dart` |
| A4 | Jelminőség-hiba → beállítás/felmérés, nem készség-ítélet | ugyanott |
| A5 | Csak engedélyezett vision-proxyk kerülnek be | `vision_evidence_adapter_test.dart` |
| A6 | Forrás-konfliktus → magasabb bizonytalanság | `analysis_evidence_adapter_test.dart` |
| A7 | Capability-hiány explicit kezelve | mindkettő |
| A8 | Az adapterek csak publikus API-t használnak | architektúra-őr + diff |

### 6.1 Mérce-mátrix — melyik hibás implementációt melyik cella fogja pirosra

| Hibás implementáció | Melyik cella vált PIROSRA |
|---|---|
| Fájlútvonal vagy minta az evidence-ben | **A1** |
| A vision hiánya hibát okoz | **A2** |
| Alacsony bizonyosságból intenzív drill | A3 |
| Rossz jelminőségből gyenge teljesítmény | **A4** |
| Nem engedélyezett vision-proxy használata | A5 |
| Konfliktusnál az egyik forrás önkényes preferálása | A6 |

**A bizonyosság három kötelező cellája** (a küszöb: a használhatósági határ):

| Cella | Bemenet | Elvárt |
|---|---|---|
| a küszöb alatt | nagyon alacsony confidence | az evidence **bekerül**, de nem vált ki fókuszt |
| rajta (a küszöbön) | pontosan a határon | bekerül, mérsékelt hatással |
| a küszöb fölött | magas confidence | teljes súllyal hat |

**Valódi-sértés próba (KÖTELEZŐ, §10-ben dokumentálva):** tegyél nyers
minta-hivatkozást az evidence-be → az **A1** cellának PIROSNAK kell lennie →
állítsd vissza.

## 7. Kötelező ellenőrzések

```bash
tools/round-gate.sh test/features/practice_generator/evidence_integration/analysis_evidence_adapter_test.dart test/features/practice_generator/evidence_integration/vision_evidence_adapter_test.dart test/features/practice_generator/evidence/skill_evidence_test.dart test/features/practice_generator/skill_estimate/evidence_weight_policy_test.dart
```

Külön processzek, csonkítatlan kimenet. **Tilos** `| tail`, `| head`,
`&&`-lánc vagy bármilyen szűrés (L09); a `flutter analyze` és `flutter test`
kézi láncolása OOM-ot ad (L05). A kötelező gate-et **TILOS háttérbe küldeni**
(`run_in_background`) — az egy-fordulós harness a forduló végén megöli (L254).

## 8. Implementációs sorrend

1. A két port (`analysis_evidence_reader`, `vision_evidence_reader`).
2. `analysis_evidence_adapter.dart` — leképezés, jelminőség szétválasztása.
3. `vision_evidence_adapter.dart` — csak engedélyezett proxyk, hiány-tolerancia.
4. Konfliktus-fixture a két forrás közé.
5. Tesztek a §6.1 három bizonyosság-cellájával.
6. A valódi-sértés próba, §10-be dokumentálva.
7. `tools/round-gate.sh` a §7 szerint.

## 9. Kockázatok

- **A nyers média szivárgása.** Ez a kör a legveszélyesebb pontja: a
  legkönnyebb „csak egy referencia a felvételre" — és az evidence
  perzisztálódik (A1).
- **A vision mint feltétel.** Ha a tervezés elvárja, a funkció flag mögött
  ragad (A2).
- **A jelminőség mint készség.** Zajos felvételből gyenge tanuló — a rendszer
  a saját méréshibáját rója fel a felhasználónak (A4).
- **(§0.0.1) Kimerítő switch csapda.** `EvidenceWeightPolicy.
  sourceReliability` `default` ág nélküli `switch`; az új `vision` ág
  hozzáadása nélkül `flutter analyze` non-exhaustive-switch hibával áll le.

## 10. Implementation handoff — az implementer tölti ki

## 11. Review — a Claude tölti ki
