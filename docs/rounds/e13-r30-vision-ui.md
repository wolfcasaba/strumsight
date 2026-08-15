# E13-R30 — Vision Setup, Coach és Result UI

- **Státusz:** PREPARED (előre megírva 2026-08-15, kód olvasva: `main @ 0f7afd9a`)
- **Típus:** Chapter 13 (UI/UX Design System), Kör 30
- **Kör-azonosító:** `E13-R30`
- **Branch:** `<motor>/e13-r30-vision-ui`
- **Előfeltétel:** `E13-R29` merge-elve (coach/tutor)
- **Brief szerzője:** Claude (Opus 5)
- **Előre kiosztott ADR:** [`0288`](../adr/0288-camera-frames-stay-on-device-and-one-cue.md)
  — **a Claude írja meg a kör indításakor; a `docs/adr/` a TILOS zónában van.**

> ⚠ **Pre-flight (indítás előtt KÖTELEZŐ):** mérd meg, hogy a vision modell-
> bináris és a képkocka-forrás TÉNYLEGESEN elérhető-e ezen a build-en (a
> projekt korábban mérte, hogy a vision rollout hiányzó modell-binárison
> BLOKKOLT). Ha nincs, a kör a **fake képkocka-folyamra** épül, és ezt a §10
> rögzíti. Eltérésnél §0.0 revízió.

```ai-router
schema_version = 1
risk = "high"
allowed_paths = [
  "lib/features/vision/",
  "lib/l10n/app_en.arb",
  "lib/l10n/app_hu.arb",
  "test/features/vision/vision_permission_test.dart",
  "test/features/vision/vision_one_cue_test.dart",
  "test/features/vision/vision_cleanup_test.dart",
  "test/features/vision/vision_degraded_test.dart",
  "docs/rounds/e13-r30-vision-ui.md",
]
gate_tests = [
  "test/features/vision/vision_permission_test.dart",
  "test/features/vision/vision_one_cue_test.dart",
  "test/features/vision/vision_cleanup_test.dart",
  "test/features/vision/vision_degraded_test.dart",
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

Az UI-45–UI-47 kamera-, kalibrációs, élő-jelzés és eredmény-felülete
**adatvédelmi és hő-védelemmel** (SDD Ch13 Kör 30).

## 2. Jelenlegi állapot — mért tények

- Az R09 StageScaffoldja, az R10 engedély-állapotai és az R29 coach-akciói
  készen állnak.
- A kamera a mikrofonnál is érzékenyebb bemenet: a képkocka a felhasználó
  otthonáról készül.
- A vision képesség **eszközfüggő** — a nem támogatott készüléknek is kell út.

## 3. Scope

**Benne van:** a Vision beállítás engedély-primerrel, elhelyezési útmutatóval,
előnézettel és kalibrációs készenléttel · a Vision coach **egy-jelzéses** Stage
elrendezése gyenge fény / takarás / követés elvesztése / hő / csak-hang
állapotokkal · az eredmény követés-minőség, technikai mérőszám és korrekciós
elrendezése · **labor-only** hibakereső csontváz flag mögött, productionben
rejtve · kamera- és mikrofon-jelzés, route-takarítás és **képkocka-megőrzés**
státusz · fake képkocka-folyamon és hő-állapoton alapuló determinisztikus
tesztek.

**NINCS benne (tilos):** a vision modell vagy a képfeldolgozás módosítása
(AGENTS.md §9) · a képkockák alapértelmezett mentése · a hibakereső csontváz
production útvonalon · `docs/adr/**`, `tools/**`, `.github/**`.

## 4. Engedélyezett fájlok

| Útvonal | Indok |
|---|---|
| `lib/features/vision/` | a három felület |
| `lib/l10n/app_{en,hu}.arb` | a vision-szövegek |
| `test/features/vision/*_test.dart` (4) | a §6 cellái |
| `docs/rounds/e13-r30-…md` | a §10 handoff |

**Tilos zóna:** `lib/features/**` a `vision/` KIVÉTELÉVEL · a vision modell és
a képfeldolgozás · `lib/core/design_system/**` · `docs/adr/**` ·
`docs/sdd/**` · `tools/**` · `.github/**`.

## 5. Kötött architekturális döntések (ADR 0288)

### 5.1 A kamera CSAK explicit felhasználói akció után indul

Nem a képernyő megnyitásakor, nem előnézet céljából. Az ADR 0276 elve a
legérzékenyebb bemenetre.

**NEM elfogadható gyengítés:** „az előnézet a beállítás megnyitásakor indul,
hogy gyorsabb legyen". Az a felhasználó otthonáról készít képet kérés nélkül.

### 5.2 A képkocka ALAPBÓL nem mentődik

A feldolgozás a készüléken, memóriában történik. Mentés csak explicit
felhasználói döntésre, és a státusz végig látható (az ADR 0285 §1 elve a
képre).

### 5.3 EGYSZERRE EGY prioritásos jelzés

Játék közben több egyidejű korrekciós jelzés használhatatlan. A felület mindig
a legfontosabbat mutatja — ez acceptance-cella (A3), nem stílus.

**NEM elfogadható gyengítés:** három jelzés egymás alatt, „mert mindegyik
hasznos". Játék közben egyik sem lesz feldolgozható.

### 5.4 Az alacsony megbízhatóság NEM kategorikus

Az ADR 0283 §1 alkalmazása a technikai mérőszámokra.

### 5.5 A nem támogatott eszköz CSAK-HANG alternatívát kap

Nem üres képernyőt és nem „a készüléked nem alkalmas" zsákutcát.

### 5.6 A hibakereső csontváz LABOR-ONLY

Flag mögött, production útvonalon nem elérhető (az R02 §5.4 mintája).

## 6. Acceptance criteria

| # | Kritérium | Bizonyíték |
|---|---|---|
| A1 | A kamera csak explicit akció után indul | `vision_permission_test.dart` |
| A2 | A képkocka alapból nem mentődik, és a státusz látható | ugyanott |
| A3 | Egyszerre pontosan egy prioritásos jelzés látszik | `vision_one_cue_test.dart` |
| A4 | Alacsony megbízhatóságnál az eredmény nem kategorikus | `vision_degraded_test.dart` |
| A5 | Hő-korlát és követés-vesztés külön, kimondott állapot | ugyanott |
| A6 | Nem támogatott eszköz csak-hang alternatívát kap | `vision_permission_test.dart` |
| A7 | A kamera és a mikrofon minden kilépési úton felszabadul | `vision_cleanup_test.dart` |
| A8 | A hibakereső csontváz productionben nem elérhető | `vision_one_cue_test.dart` |

### 6.1 Mérce-mátrix — melyik hibás implementációt melyik cella fogja pirosra

| Hibás implementáció | Melyik cella vált PIROSRA |
|---|---|
| A kamera a képernyő megnyitásakor indul | **A1** |
| A képkockák naplózásra mentve | **A2** |
| Két jelzés egyszerre | **A3** |
| Kategorikus technikai pontszám gyenge követésnél | A4 |
| A hő-korlát néma lassulásként | A5 |
| A kamera nyitva marad háttérbe kerüléskor | **A7** |
| A csontváz production route-on | A8 |

**A jelzés-prioritás három kötelező cellája** (a küszöb: egyidejű jelzések száma):

| Cella | Bemenet | Elvárt |
|---|---|---|
| a küszöb alatt | nincs korrekciós lelet | **0** jelzés — a Stage tiszta |
| rajta (a küszöbön) | **1** lelet | 1 jelzés |
| a küszöb fölött | 3 egyidejű lelet | **1** jelzés — a legmagasabb prioritású |

**Valódi-sértés próba (KÖTELEZŐ, §10-ben dokumentálva):** jeleníts meg két
jelzést egyszerre → az **A3** cellának PIROSNAK kell lennie → állítsd vissza.

## 7. Kötelező ellenőrzések

```bash
tools/round-gate.sh test/features/vision/vision_permission_test.dart test/features/vision/vision_one_cue_test.dart test/features/vision/vision_cleanup_test.dart test/features/vision/vision_degraded_test.dart
```

Külön processzek, csonkítatlan kimenet. **Tilos** `| tail`, `| head`,
`&&`-lánc vagy bármilyen szűrés (L09); a `flutter analyze` és `flutter test`
kézi láncolása OOM-ot ad (L05). A kötelező gate-et **TILOS háttérbe küldeni**
(`run_in_background`) — az egy-fordulós harness a forduló végén megöli (L254).

> **Review-megjegyzés:** ez a kör kamerát és adatmegőrzést érint, ezért a
> review-ban a `security-reviewer` ügynök futtatása kötelező.

## 8. Implementációs sorrend

1. A beállítás engedély-primerrel — kamera CSAK explicit akcióra.
2. A képkocka-megőrzés státusza, alapból mentés nélkül.
3. Az egy-jelzéses Stage + a három prioritás-cella.
4. Gyenge fény / takarás / követés-vesztés / hő / csak-hang állapotok.
5. Az eredmény-felület, nem kategorikus alacsony megbízhatósággal.
6. Kamera- és mikrofon-takarítás minden kilépési úton; labor-only csontváz.
7. A valódi-sértés próba, §10-be dokumentálva.
8. `tools/round-gate.sh` a §7 szerint.

## 9. Kockázatok

- **Az „azonnali" előnézet.** Gyorsabbnak hat, és kérés nélkül kapcsolja be a
  kamerát a felhasználó otthonában (A1).
- **A három egyidejű jelzés.** Mindegyik hasznosnak tűnik, és együtt
  használhatatlanok játék közben (A3).
- **A hibakeresés kedvéért mentett képkocka.** A legérzékenyebb adat, és a
  fejlesztői kényelem viszi ki (A2).

## 10. Implementation handoff — az implementer tölti ki

## 11. Review — a Claude tölti ki
