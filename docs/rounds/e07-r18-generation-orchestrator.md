# E07-R18 — GenerationOrchestrator, progress és cancellation

- **Státusz:** PREPARED (előre megírva 2026-08-15, kód olvasva: `main @ 5cdd7472`)
- **Típus:** Epic 7 (AI Practice Generator), SDD Ch8 Kör 18
- **Kör-azonosító:** `E07-R18`
- **Branch:** `<motor>/e07-r18-generation-orchestrator`
- **Előfeltétel:** `E07-R17` merge-elve (ismétlés-sor)
- **Brief szerzője:** Claude (Opus 5)
- **Előre kiosztott ADR:** [`0266`](../adr/0266-generation-orchestration-and-no-partial-activation.md)
  — **MÁR MEGÍRVA, a `docs/adr/` a TILOS zónában van.**

> ⚠ **Pre-flight (indítás előtt KÖTELEZŐ):** olvasd újra a **meglévő**
> `AnalysisPipeline` cancellation-mintáját (`lib/features/audio_analysis/engine/
> analysis_cancellation.dart`) — a projekt már megoldotta ezt a problémát,
> kövesd, ne találj ki újat. Eltérésnél §0.0 revízió.

```ai-router
schema_version = 1
risk = "high"
allowed_paths = [
  "lib/features/practice_generator/application/model/generation_state.dart",
  "lib/features/practice_generator/application/service/generation_orchestrator.dart",
  "lib/features/practice_generator/application/controller/plan_generator_controller.dart",
  "lib/features/practice_generator/public.dart",
  "test/features/practice_generator/application/generation_orchestrator_test.dart",
  "test/features/practice_generator/application/plan_generator_controller_test.dart",
  "docs/rounds/e07-r18-generation-orchestrator.md",
]
gate_tests = [
  "test/features/practice_generator/application/generation_orchestrator_test.dart",
  "test/features/practice_generator/application/plan_generator_controller_test.dart",
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

A teljes generálási folyamat alkalmazásszintű, **megszakítható**, állapotgéppel
vezérelt futtatása (SDD Ch8 Kör 18).

## 2. Jelenlegi állapot — mért tények

- Az R05–R17 minden építőeleme kész (evidence, becslés, katalógus, prioritás,
  jelöltek, idő, ütemezés, adaptáció, ismétlés).
- **A projekt már megoldotta a megszakítást**: az `AnalysisPipeline`
  cancellation-tokene és a részleges eredmény tiltása (GOV-30c). Ezt kell
  követni, nem újat kitalálni.
- A determinizmus kötelező (ADR 0255 §1).

## 3. Scope

**Benne van:** a folyamat lépései (stage-ek) · **immutable állapotgép** ·
haladás-események és megszakítás · azonos kérés párhuzamos futásának kezelése ·
**részleges eredmény tiltása** · minden hiba `AppFailure`-re képezve.

**NINCS benne (tilos):** repository-írás (Kör 19) · UI (Kör 20-tól) · a
tervező-algoritmusok módosítása · Flutter widget · `Random` · más
`lib/features/**`, `docs/adr/**`, `tools/**`.

## 4. Engedélyezett fájlok

| Útvonal | Indok |
|---|---|
| `application/model/generation_state.dart` | **ÚJ** — immutable állapotgép |
| `application/service/generation_orchestrator.dart` | **ÚJ** — a futtató |
| `application/controller/plan_generator_controller.dart` | **ÚJ** — a vezérlő |
| `public.dart` | a barrel bővítése |
| `test/…/application/*_test.dart` (2 db) | a §6 cellái |
| `docs/rounds/e07-r18-…md` | a §10 handoff |

**Tilos zóna:** más `lib/features/**` · `lib/app/**` · `docs/adr/**` ·
`docs/sdd/**` · `tools/**` · `.github/**`.

## 5. Kötött architekturális döntések (ADR 0266)

### 5.1 Megszakítás után NINCS írás

A `cancel()` után a folyamat **semmilyen** perzisztens írást nem végez.
Az ADR 0254 §5.4 (megszakított futás nem ad részleges dokumentumot)
megismételve a tervezőre.

**NEM elfogadható gyengítés:** „a részeredményt elmentjük, hátha jó lesz".

### 5.2 RÉSZLEGES eredmény soha nem aktiválódik

Ha bármely lépés hibázik vagy megszakad, a terv **nem** válik aktívvá.
A félkész terv rosszabb, mint a semmilyen: a tanuló hiányos napokat kapna.

### 5.3 Az állapotgép IMMUTABLE, az átmenetek kikényszerítettek

Minden állapot új példány; érvénytelen átmenet hiba. Az UI ebből olvas, nem
mutálódó objektumból.

### 5.4 Azonos kérés párhuzamos futása KONTROLLÁLT

Ugyanarra a kérésre indított második generálás nem indít második futást
(vagy megszakítja az elsőt) — nem futnak versenyben, mert az eredmény
kiszámíthatatlan lenne.

### 5.5 A hosszú számítás NEM blokkolja a UI-t

A nehéz lépések a UI szálon kívül futnak, az `AnalysisPipeline` mintájára.

### 5.6 Minden hiba `AppFailure`-re képezve

Nincs nyers kivétel a határon. A hívó egységes hibatípust lát.

## 6. Acceptance criteria

| # | Kritérium | Bizonyíték |
|---|---|---|
| A1 | `cancel()` után NINCS repository-írás | `generation_orchestrator_test.dart` |
| A2 | Bármely lépésnél megszakítható | ugyanott — lépésenkénti cella |
| A3 | Részleges eredmény nem aktiválódik | ugyanott |
| A4 | Lépés-hiba `AppFailure`-t ad, nem nyers kivételt | ugyanott |
| A5 | Újrapróbálás TISZTA futást indít (nincs örökölt részállapot) | ugyanott |
| A6 | Azonos kérés párhuzamos indítása kontrollált | ugyanott |
| A7 | Az állapot-átmenetek kikényszerítettek | `plan_generator_controller_test.dart` |
| A8 | A hosszú számítás nem blokkolja a UI szálat | ugyanott |

### 6.1 Mérce-mátrix — melyik hibás implementációt melyik cella fogja pirosra

| Hibás implementáció | Melyik cella vált PIROSRA |
|---|---|
| A részeredmény mentése cancel után | **A1** |
| Csak az első lépésnél megszakítható | A2 |
| Hibás lépés után is aktiválódik a terv | **A3** |
| Nyers kivétel propagál | A4 |
| Retry örökli az előző részállapotot | **A5** |
| Két párhuzamos futás versenyben | A6 |
| Mutálódó állapot-objektum | A7 |

**A megszakítás három kötelező cellája** (a határ: az utolsó lépés vége):

| Cella | Bemenet | Elvárt |
|---|---|---|
| korán | cancel az első lépés alatt | nincs írás, nincs aktiválás |
| a határon | cancel az **utolsó** lépés alatt, az aktiválás ELŐTT | **nincs írás, nincs aktiválás** |
| későn | cancel a sikeres aktiválás UTÁN | a terv aktív marad, a cancel no-op |

**Valódi-sértés próba (KÖTELEZŐ, §10-ben dokumentálva):** ments el
részeredményt megszakításkor → az **A1** cellának PIROSNAK kell lennie →
állítsd vissza.

## 7. Kötelező ellenőrzések

```bash
tools/round-gate.sh test/features/practice_generator/application/generation_orchestrator_test.dart test/features/practice_generator/application/plan_generator_controller_test.dart
```

Külön processzek, csonkítatlan kimenet. **Tilos** `| tail`, `| head`,
`&&`-lánc vagy bármilyen szűrés (L09); a `flutter analyze` és `flutter test`
kézi láncolása OOM-ot ad (L05). A kötelező gate-et **TILOS háttérbe küldeni**
(`run_in_background`) — az egy-fordulós harness a forduló végén megöli (L254).

## 8. Implementációs sorrend

1. `generation_state.dart` — immutable állapotok, kikényszerített átmenetek.
2. `generation_orchestrator.dart` — lépések, megszakítás, `AppFailure`-képzés.
3. `plan_generator_controller.dart` — a UI-nak szánt vezérlő.
4. Tesztek a §6.1 három megszakítás-cellájával.
5. A valódi-sértés próba, §10-be dokumentálva.
6. `tools/round-gate.sh` a §7 szerint.

## 9. Kockázatok

- **A „hátha jó lesz" részeredmény.** Segítőkésznek hat, és hiányos tervet ad
  a tanulónak (A1, A3).
- **A retry szennyezett állapota.** Az újrapróbálás a legnehezebben
  észrevehető hibaforrás: örökölt részállapot mellett a második futás más
  eredményt ad (A5).
- **Az új cancellation-minta.** A projektben már van bevált; egy második,
  eltérő minta karbantartási teher és új hibaforrás (§2).

## 10. Implementation handoff — az implementer tölti ki

## 11. Review — a Claude tölti ki
