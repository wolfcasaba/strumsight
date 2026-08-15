# E07-R25 — Analyze és Computer Vision evidence integráció

- **Státusz:** PREPARED (előre megírva 2026-08-15, kód olvasva: `main @ 19b30557`)
- **Típus:** Epic 7 (AI Practice Generator), SDD Ch8 Kör 25
- **Kör-azonosító:** `E07-R25`
- **Branch:** `<motor>/e07-r25-analysis-and-vision-evidence`
- **Előfeltétel:** `E07-R24` merge-elve (dal-integráció)
- **Brief szerzője:** Claude (Opus 5)
- **Előre kiosztott ADR:** nincs — a határokat az ADR 0260 (nyers média
  tilalma, discomfort külön), 0261 (`unknown`) és 0262 (capability) rögzíti.

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
  "docs/rounds/e07-r25-analysis-and-vision-evidence.md",
]
gate_tests = [
  "test/features/practice_generator/evidence_integration/analysis_evidence_adapter_test.dart",
  "test/features/practice_generator/evidence_integration/vision_evidence_adapter_test.dart",
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
elkülönítése a **készség-hibától** · több forrás közti konfliktus fixture-je.

**NINCS benne (tilos):** **nyers frame vagy nyers audio bármilyen formában** ·
flag `true`-ra állítása · az Analyze/Vision feature-ök módosítása · más
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

**Tilos zóna:** `lib/features/audio_analysis/**` és `lib/features/vision/**`
tartalma · `lib/app/config/feature_flags.dart` · `docs/adr/**` · `tools/**`.

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
tools/round-gate.sh test/features/practice_generator/evidence_integration/analysis_evidence_adapter_test.dart test/features/practice_generator/evidence_integration/vision_evidence_adapter_test.dart
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

## 10. Implementation handoff — az implementer tölti ki

## 11. Review — a Claude tölti ki
