# E08-R21 — Mastery mérföldkő domain és kiértékelő

- **Státusz:** PREPARED (előre megírva 2026-08-18, kód olvasva: `main @ ea6569fb`)
- **Típus:** Chapter 9 (Epic 8 — Gamification), Kör 21
- **Kör-azonosító:** `E08-R21`
- **Branch:** `<motor>/e08-r21-mastery-milestone-domain-and-evaluator`
- **Előfeltétel:** `E08-R20` merge-elve (küldetés felület)
- **Brief szerzője:** Claude (Opus 5)
- **Előre kiosztott ADR:** `ADR 0315` — a szám FOGLALT. Az ADR-t a Claude írja meg a
  kör indítási pre-flightjában a §5 döntéseiből; az implementer a `docs/adr/`-t
  NEM érinti (TILOS zóna).

> ⚠ **Pre-flight (indítás előtt KÖTELEZŐ):** olvasd újra az R05 négy jogosultsági kapuját (különösen a mastery kaput) és az `EvidenceTrust` értékeit; valamint a `lib/features/analyze/` és `lib/features/vision/` confidence-mezőit — a bizonyíték-küszöb ezekre épül. Eltérésnél
> §0.0 brief-revízió, NEM csendes lista-tágítás.

```ai-router
schema_version = 1
risk = "high"
allowed_paths = [
  "lib/features/gamification/domain/mastery/mastery_milestone.dart",
  "lib/features/gamification/domain/mastery/mastery_progress.dart",
  "lib/features/gamification/domain/mastery/mastery_badge.dart",
  "lib/features/gamification/application/mastery_evaluator.dart",
  "lib/features/gamification/public.dart",
  "test/features/gamification/application/mastery_evaluator_test.dart",
  "docs/rounds/e08-r21-mastery-milestone-domain-and-evaluator.md",
]
gate_tests = [
  "test/features/gamification/application/mastery_evaluator_test.dart",
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

Lezáró jelzés nélkül a kör bukott. **Listán kívüli fájl kellene → `stopped`**,
és a kimenet a brief-revízió kérése, nem az `allowed_paths` csendes tágítása.
Meglévő, ma zöld teszt elbukása → `blocked`, nem a teszt átírása.

## 1. Cél

Válaszd el élesen az XP-haladást a **több sessionnel igazolt** készség-mérföldkövektől.
Ez az [`ADR 0289`](../adr/0289-mastery-is-evidence-not-xp.md) legszigorúbb alkalmazása:
az elsajátítottság mért teljesítményből származik, nem XP-ből.

## 2. Jelenlegi állapot — mért tények

- Az R05 külön mastery-kaput adott a jogosultságban; az R02 `EvidenceTrust` szintet.
- `lib/features/gamification/domain/mastery/` **nem létezik**.
- A `lib/features/analyze/` és `lib/features/vision/` eredményei confidence-értéket hordoznak — alacsony megbízhatóság mellett NEM használhatók bizonyítékként.
- Az `ADR 0289` §2: a bizonyíték auditálható — minden állítás mögött konkrét, megnyitható session áll.

## 3. Scope

**Benne van:** a skill-címke, metrika, nehézség, tempó-tartomány és bizonyíték-darabszám követelmények ·
**több sessionös** megerősítés kötelezővé tétele · az össze nem hasonlítható sessionök kezelése ·
Vision és Analysis bizonyíték CSAK megfelelő megbízhatóság mellett · a mastery-teljesítés
**immutable** · privacy-safe bizonyíték-összefoglaló.

**NINCS benne (tilos):**

- XP felhasználása mastery-forrásként (ADR 0289) — abszolút tilos.
- Bármilyen egészségügyi/orvosi állítás (pl. „sérülésmentes technika”) — abszolút tilos.
- Felület (Kör 22/23), hálózat.
- `docs/adr/**` — az ADR 0315-öt a Claude írja.

## 4. Engedélyezett fájlok

| Útvonal | Indok |
|---|---|
| `lib/features/gamification/domain/mastery/mastery_milestone.dart` | **ÚJ** — a mérföldkő követelményei |
| `lib/features/gamification/domain/mastery/mastery_progress.dart` | **ÚJ** — a haladás |
| `lib/features/gamification/domain/mastery/mastery_badge.dart` | **ÚJ** — a jelvény (magyarázható) |
| `lib/features/gamification/application/mastery_evaluator.dart` | **ÚJ** — a kiértékelő |
| `lib/features/gamification/public.dart` | barrel-bővítés — CSAK export-sor |
| `test/features/gamification/application/mastery_evaluator_test.dart` | a §6 cellái |

**Tilos zóna:** `lib/features/` MINDEN más feature-e · `lib/core/**` · `lib/app/**` · `docs/adr/**` · `docs/sdd/**` · `tools/**` · `.github/**` · `backend/**`

## 5. Kötött architekturális döntések (ADR 0315)

### 5.1 A MASTERY SOHA NEM XP-BŐL SZÁRMAZIK

A kiértékelő bemenete kizárólag mért teljesítmény (pontosság, tempó, ismételhetőség)
— az XP, a szint és a főkönyv egyenlege NEM bemenet.

**NEM elfogadható gyengítés:** „XP-küszöb mint gyorsítósáv” a mastery-hez. Az ADR 0289
pontosan ezt a hazugságot tiltja: az XP a részvételt méri.

### 5.2 TÖBB SESSION kell — egyetlen jó futás nem elég

A mérföldkő minimum bizonyíték-darabszáma **legalább 2**, és a bizonyítékoknak
külön sessionökből kell származniuk. Egyetlen szerencsés futás nem elsajátítottság.

**NEM elfogadható gyengítés:** ugyanazon session több szegmensének külön bizonyítékként
számolása. A darabszám SESSION-szintű.

### 5.3 ALACSONY MEGBÍZHATÓSÁGÚ bizonyíték nem számít

A Vision és Analysis eredmény csak a megbízhatósági küszöb fölött használható
bizonyítékként. Alatta a session továbbra is ad alap-XP-t (R05), de mastery-hez nem járul hozzá.

### 5.4 A TELJESÍTÉS IMMUTABLE — nem regresszálhat

A megszerzett mérföldkő nem vehető vissza egy későbbi gyengébb teljesítmény miatt.
A rossz nap nem törli a bizonyított tudást.

### 5.5 NINCS ORVOSI ÁLLÍTÁS, és a bizonyíték PRIVACY-SAFE

Az összefoglaló nem tartalmaz nyers hangot, azonosítható session-részletet, és
semmilyen egészségügyi következtetést (testtartás, sérülés-kockázat). A jelvény
**magyarázható**: megmondja, mely mért eredmények alapján járt.

## 6. Acceptance criteria

| # | Kritérium | Bizonyíték |
|---|---|---|
| A1 | A kiértékelő bemenetei között NINCS XP, szint vagy főkönyv-egyenleg | `mastery_evaluator_test.dart` + review |
| A2 | Egyetlen session bizonyítékával a mérföldkő NEM teljesül | `mastery_evaluator_test.dart` — a bizonyíték-hármas alsó cellája |
| A3 | Ugyanazon session több szegmense EGY bizonyítéknak számít | `mastery_evaluator_test.dart` |
| A4 | Megbízhatósági küszöb alatti Vision/Analysis bizonyíték nem járul hozzá | `mastery_evaluator_test.dart` — megbízhatóság-mátrix |
| A5 | A megszerzett mérföldkő későbbi gyengébb teljesítménytől NEM vész el | `mastery_evaluator_test.dart` — immutabilitás-cella |
| A6 | Az össze nem hasonlítható sessionök (más tempó-tartomány/nehézség) nem keverednek | `mastery_evaluator_test.dart` |
| A7 | A bizonyíték-összefoglaló nem tartalmaz nyers audiót és semmilyen egészségügyi állítást | `mastery_evaluator_test.dart` + review |
| A8 | A jelvény magyarázható: visszaadja, mely mért eredmények alapozták meg | `mastery_evaluator_test.dart` |

### 6.1 Mérce-mátrix — melyik hibás implementációt melyik cella fogja pirosra

| Hibás implementáció | Melyik cella vált PIROSRA |
|---|---|
| XP-küszöb bekerül a mastery feltételei közé | **A1** — az ADR 0289 megsértése |
| Egy session elég a teljesítéshez | **A2** |
| A szegmensek külön bizonyítékként számolnak | **A3** |
| Alacsony megbízhatóságú Vision-eredmény bizonyítékként számít | **A4** |
| Gyengébb teljesítmény visszaveszi a mérföldkövet | **A5** |
| Az összefoglaló testtartás-értékelést közöl | **A7** |

**A küszöb három kötelező cellája** (a bizonyíték-darabszám (`minEvidenceSessions`, a specifikáció szerint legalább 2)):

| Cella | Bemenet | Elvárt |
|---|---|---|
| a küszöb **alatt** | 1 session bizonyítéka | a mérföldkő **NEM teljesül** — egyetlen szerencsés futás nem elsajátítottság |
| **rajta** (a küszöbön) | pontosan `minEvidenceSessions` (2) különböző session | **TELJESÜL** — a küszöb a TELJESÍTŐ oldalhoz tartozik (inkluzív) |
| a küszöb **fölött** | 3 vagy több session | teljesül; a további bizonyíték nem von le és nem ad hozzá |

A hármas tömören: **alatt** → elutasít · **rajta** → az §6.1 tábla dönti el · **fölött** → elfogad.

A határ **a **rajta** cellához tartozik (inkluzív) — a fenti táblázat „rajta” sora mondja ki, melyik oldal nyer**.

**Valódi-sértés próba (KÖTELEZŐ, §10-ben dokumentálva):** engedd meg, hogy egyetlen session két szegmense két bizonyítéknak számítson,
futtasd a gate-et → az **A3** cellának PIROSNAK kell lennie → állítsd vissza.

## 7. Kötelező ellenőrzések

```bash
tools/round-gate.sh test/features/gamification/application/mastery_evaluator_test.dart
```

A gate artefaktum a mérce (`tools/round-gate.sh`) — a parancssorban
reprodukált parancslista NEM bizonyíték (AGENTS.md §12, L09). A script
`format` → `analyze` → `test <minden útvonal külön>` → `architecture`
lépéseket KÜLÖN processzként futtat, csonkítatlan kimenettel. **Tilos**
bármilyen szűrés vagy kézi lánc a promptban (OOM, L05). A kötelező gate-et
**TILOS háttérbe küldeni** (`run_in_background`) — az egy-fordulós harness a
forduló végén megöli, mielőtt eredmény érkezne (L183/L254). CI-dispatch, PR és
merge mindig Claude-oldal: az implementer `gh`-t NEM hív.

## 8. Implementációs sorrend

1. `mastery_milestone.dart` — skill-címke, metrika, nehézség, tempó-tartomány, bizonyíték-darabszám.
2. `mastery_progress.dart` — a haladás, session-szintű bizonyíték-számlálással.
3. `mastery_evaluator.dart` — a kiértékelő, XP-mentes bemenetekkel.
4. A megbízhatósági küszöb érvényesítése a Vision/Analysis bizonyítékra.
5. Az össze nem hasonlítható sessionök szétválasztása.
6. `mastery_badge.dart` — magyarázható, privacy-safe jelvény.
7. A `public.dart` export-sorai; a valódi-sértés próba §10-be.
8. `tools/round-gate.sh` a §7 szerint.

## 9. Kockázatok

- **Az XP „gyorsítósáv”.** A legkézenfekvőbb egyszerűsítés, és pontosan az ADR 0289 által tiltott hazugság (A1).
- **A szegmens-szintű számlálás.** Technikailag több adatpont, valójában EGY session — hamis elsajátítottság (A3).
- **Az orvosi állítás.** A testtartás-elemzésből könnyen csúszik ki „sérülés-kockázat” megfogalmazás; ez jogi és etikai határ (A7).

## 10. Implementation handoff — az implementer tölti ki

## 11. Review — a Claude tölti ki
