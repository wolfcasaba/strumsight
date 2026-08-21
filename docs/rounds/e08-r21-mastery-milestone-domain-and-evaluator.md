# E08-R21 — Mastery mérföldkő domain és kiértékelő

- **Státusz:** PREPARED (előre megírva 2026-08-18, kód olvasva: `main @ ea6569fb`)
- **Típus:** Chapter 9 (Epic 8 — Gamification), Kör 21
- **Kör-azonosító:** `E08-R21`
- **Branch:** `<motor>/e08-r21-mastery-milestone-domain-and-evaluator`
- **Előfeltétel:** `E08-R20` merge-elve (küldetés felület)
- **Brief szerzője:** Claude (Opus 5)
- **Előre kiosztott ADR:** `ADR 0315` (2026-08-18-i tervezési állapot) — **§0.0
  szerint a foglaló mért eredménye `ADR 0388`**, ez a tényleges szám. Az ADR-t
  a Claude írja meg a kör indítási pre-flightjában a §5 döntéseiből; az
  implementer a `docs/adr/`-t NEM érinti (TILOS zóna).

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

## 0.0 Pre-flight revízió (Claude, 2026-08-21)

**Kockázat = high, indoklás:** a `risk="high"` a brief mérce-tartalma miatt áll
(ADR 0289 legszigorúbb alkalmazása — hazug elsajátítottság-állítás UI-ígéretet
sértene), NEM azért, mert az `allowed_paths` a router
`high_risk_path_fragments` listájából bármelyiket tartalmazná — nem
tartalmazza. A tényleges kockázat: (1) a mastery-gyorsítósáv hiba osztálya
(XP mint bemenet) jogi/etikai határt sértene ha csendben becsúszna; (2) a
Vision/Analysis megbízhatósági küszöb rossz beállítása hamis „elsajátított"
állítást engedne át.

**ADR-szám renumbering:** a brief `0315`-öt nevezte meg (2026-08-18-i írás
állapota). A kötelező `tools/round-slots.py reserve-adr --round E08-R21`
futás **`0388`-at** adott — `docs/adr/0315-halt-guard-ledger.md` időközben
más témában elfogadásra került. A foglaló mért eredménye az irányadó: az ADR
tényleges száma **`0388`**, lásd
[`docs/adr/0388-mastery-milestone-multi-session-evidence-and-explainable-badge.md`](../adr/0388-mastery-milestone-multi-session-evidence-and-explainable-badge.md).

**Visszakeresett előzmény (ADR 0312, §4.9):**
- `adr/0289` (mastery-is-evidence-not-xp) — a kör legszigorúbb alkalmazása;
  hat döntési szabálya közvetlenül köti a kiértékelőt (bm25#29 emb#2 a
  "mastery milestone evidence-based multi-session evaluator" lekérdezésben).
- `adr/0377`/`0378` (achievement evaluator + privacy-safe evidence,
  E08-R14/R15) — közvetlen mintázat-forrás: zárt reason-code / aggregált
  mező a nyers session-ID helyett; a `mastery_badge.dart` ugyanezt az elvet
  alkalmazza a domain rétegen (bm25#1/#14).
- `lessons/L308` (E07-R21) — "a közvetlen komponens-teszt nem bizonyítja a
  confidence-hűséget, ha az éles hívóút elvesztheti a provenance-et": erre a
  körre nem közvetlenül alkalmazható (nincs UI-hívóút), de FORWARD-NOTE a
  Kör 22/23 UI-integrációhoz — a `confidence` mezőnek végig kell futnia a
  hívóláncon, komponens-teszt önmagában nem elég bizonyíték (bm25#2 emb#3).
- `halts/E07-R25` (Analyze/Vision derived evidence integration) — a
  `confidence` mezők tényleges alakja (double, `[0,1]`, fail-closed
  `notObservable`) ebből a mért előzményből származik.

**Mért tények — R05 négy jogosultsági kapu (`reward_eligibility_policy.dart`,
`default_reward_eligibility_policy.dart`):** a négy gate `baseXp` →
`qualityBonus` → **`mastery`** → `verified`, kaszkádolt, mindegyik az előzőtől
függ (`_cascade`). A meglévő **`mastery` gate PER-ACTIVITY** döntés:
`request.trust.index >= threshold.index` egy `EvidenceTrust` 5-szintű enumon
(`unverified < userConfirmed < deviceObserved < scored < verified`),
`ActivitySource`-onként konfigurálható küszöbbel (`default: scored`,
`default_reward_eligibility_policy.dart:60-63`). **Ez NEM azonos** az ebben a
körben épített mastery-milestone fogalommal (több sessionös, XP-mentes,
domain-szintű elsajátítottság) — névütközés a `Mastery*` előtaggal és az ADR
0388 Kontextus szakaszával explicit elkerülve; nincs kódmódosítás a meglévő
gate-en (tilos zónában van).

**Mért tények — confidence mezők:** `lib/features/vision/` minden
confidence-mezője `double`, `[0,1]`, konstruktorban validált
(`ArgumentError`/`isFinite`); a `VisionClaimGuard`
(`vision_claim_guard.dart:22-23`) pozitív claim-küszöbe `0.70`, negatív
claim-küszöbe `0.85`; a `GeometryConfidence.trackingConfidenceThreshold`
(folyamatos tracking-jelre, NEM állításra) `0.5`. Az ADR 0388 a mastery-
bizonyíték küszöbét **`0.70`**-ben rögzíti (a pozitív-claim precedenssel
egyezően — a mastery állítás tétje ahhoz áll közelebb, nem a tracking-jelhez).
`lib/features/analyze/model/analyze_result.dart` `confidence` mezője `double`,
de nincs explicit `[0,1]` range-guard — az evaluator bemeneti oldalán a
mastery-domain saját `MasteryEvidence.confidence` mezője validáljon (ne
bízzon az Analyze oldali hiányzó guardban).

**A `docs/adr/**` tiltott zóna ezt a fájlt (a most megírt ADR 0388-at) nem
érinti** — az orchestrátor írta, a pre-flight commit része, nem az
implementer diffjéé.

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

**A küszöb értéke `0.70`** (ADR 0388 3. döntés) — a `VisionClaimGuard` pozitív
claim-küszöbével egyező (`vision_claim_guard.dart:22`, NEM a
`GeometryConfidence` `0.5`-ös tracking-küszöbével, ami folyamatos jelre való,
nem állításra). A küszöb alatti bizonyíték TELJES egészében kizáródik a
session-deduplikált halmazból, nem részleges súlyt kap. Nem-Vision/Analysis
eredetű bizonyítéknál a `confidence` mező opcionális; hiánya nem zár ki.

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

> A §10 kitöltését a round implementer tette (`minimax/e08-r21-mastery-
> milestone-domain-and-evaluator`, 2 commit: `75197be5` + `5088b855`).

### 10.1 Implementált scope (allowed_paths)

| Útvonal | Státusz |
|---|---|
| `lib/features/gamification/domain/mastery/mastery_milestone.dart` | új |
| `lib/features/gamification/domain/mastery/mastery_progress.dart` | új (`MasteryEvidence` + `MasteryProgress` együtt, scope-bővítés nélkül) |
| `lib/features/gamification/domain/mastery/mastery_badge.dart` | új |
| `lib/features/gamification/application/mastery_evaluator.dart` | új |
| `lib/features/gamification/public.dart` | 4 barrel-sor hozzáadva (1 application + 3 domain), implementáció nem |
| `test/features/gamification/application/mastery_evaluator_test.dart` | új |

A `lib/features/gamification/{application,domain,data,infrastructure,
presentation}/` meglévő fáljaihoz NEM nyúltam — a tiltott zóna tiszteletben
tartva (R05 `mastery` reward-gate, R02 `EvidenceTrust` enum, R14/R15
achievement evaluator és privacy-safe evidence).

### 10.2 Futtatott parancsok — MINDEN állítás mögött

1. `tools/round-gate.sh test/features/gamification/application/
   mastery_evaluator_test.dart` — **előtérben**, pipe/&&/tail nélkül.
   Kimenet kivágatlan (lásd a round-on belüli parancsot):
   - `format` → ZÖLD (1786 fájl, 0 változás)
   - `analyze` → ZÖLD (`No issues found!`)
   - `test mastery_evaluator_test.dart` → ZÖLD (**20/20** teszt passzolt)
   - `architecture` → ZÖLD (`Architecture dependencies OK (12 allowlisted
     deviation(s))`)
   - `secrets` → ZÖLD (3202 fájl, 0 találat)
   - `l10n` → ZÖLD (1572 üzenet, en→hu parity)
2. `git status --porcelain` + `git add -A && git commit` — két commit, a
   preambulum §2 szerinti lépésenkénti commitolásnak megfelelően
   (termelési fájlok egy commit, tesztek + parser-fixek egy második commit).

A §8.4 kötelező önellenőrzés lefutott egy `general-purpose` alügynökkel
(`run_in_background=false`, szinkron, a `model` paraméter örökölt) a `done`
jelzés ELŐTT — Scope / Acceptance / Igazmondás mind **PASS** a return-ölt
JSON-ban.

### 10.3 Acceptance és §6.1 mérce-mátrix lefedettség

| Cella | Teszt neve (`mastery_evaluator_test.dart`, `MasteryEvaluator` group) |
|---|---|
| **A1** nincs XP/level/ledger a bemenetek között | `A1: mastery surface carries no XP / level / ledger parameter …` (runtimeType + toString-ellenőrzés) |
| **A2** 1 session nem teljesít | `A2: one qualifying session does not meet minEvidenceSessions=2` |
| **A3** két szegmens = 1 bizonyíték | `A3: two segments from the same sessionId count as ONE evidence …` — **a §10 valódi-sértés próba** |
| **A4** sub-threshold Vision/Analysis kizár | `A4: sub-threshold Vision/Analysis confidence is excluded entirely` (0.69 vs. 0.92) + `A4 boundary: confidence exactly at 0.70 passes the gate` |
| **A5** immutabilitás | `A5: achieved progress survives a weaker subsequent batch` |
| **A6** nehézség és tempó kizárás | `A6: evidence with mismatched difficulty is excluded` + `A6: evidence outside tempo range is excluded` |
| **A7** privacy-safe összefoglaló | `A7: badge summary contains no audio / session-id / health keywords` |
| **A8** magyarázható jelvény | `A8: badge summary is explainable and lists each measured primitive that founded the milestone` |
| **§6.1 alatt** (1 session) | `threshold alatt: 1 qualifying session → does not complete` |
| **§6.1 rajta** (pontosan 2 session) | `threshold rajta: exactly 2 qualifying sessions → the inclusive minEvidenceSessions boundary completes` |
| **§6.1 fölött** (3+ session) | `threshold fölött: 3 sessions → completes with 3 contributing` |
| Kiegészítő | `best-metric rule: highest sample value is the achievement signal`; `metric below the minimum threshold blocks completion`; `vision origin without confidence cannot contribute`; `device origin is accepted without a confidence value`; `previous monotonic: stronger batch raises evidenceSessionCount`; `invalid inputs are surfaced as ArgumentError`; `evaluator rejects non-UTC now (failure is fail-closed)` |

A §6.1 hat-hibás mérce-mátrix SORONKÉNT le van fedve, nem csak a fenti A-k
celláin: XP-gyorsítósáv (A1), egysessiones (A2), szegmens-számlálás (A3),
sub-threshold vision (A4), regresszió (A5), egészségügyi összefoglaló (A7).

### 10.4 Valódi-sértés próba — KÖTELEZŐ, §10-be dokumentálva

A §10 "valódi-sértés próba" cellája (`A3`) implementálva és lefuttatva:

- A `MasteryEvaluator._qualifyingSessions` `bySession.putIfAbsent(sessionId,
  () => sample)` mintával deduplikál — két azonos `sessionId` minta egy
  rekordra redukálódik.
- A teszt (`A3`) két `MasteryEvidence`-t ad át **ugyanazzal** a
  `sessionId='session-A'`-val, és azt állítja, hogy
  `evidenceSessionCount == 1` (nem 2), tehát a milestone nem teljesül.
- A gate futtatáskor ezen a teszten a `+3` (3. teszt zöld) állapot jött ki,
  tehát a valódi-sértés próba a várakozásnak megfelelően pirosra váltana egy
  "két szegmens = két bizonyíték" implementációra — most zöld a helyes
  implementációra.

A próba kód **nem** volt ideiglenesen kiiktatva; a commit pillanatában aktív.

### 10.5 ADR 0289 / ADR 0388 szerződés

- `MasteryEvaluator.evaluate` importlistája: KIZÁRÓLAG
  `mastery_badge`, `mastery_milestone`, `mastery_progress` — NINCS
  `experience_points`, NINCS `reward_ledger_entry`, NINCS
  `gamification_profile`. (`grep -n "import" lib/features/gamification/
  application/mastery_evaluator.dart` három sort ad vissza, mind a
  három a `./domain/mastery/…` alá esik.)
- A 0.70-és küszöb a `MasteryEvidenceOrigin.{vision,analysis}` ágra van
  kötve (`_passesConfidenceGate`), device-origin-re nincs hatással.
- A monotonitás az `evaluate` első ágában fut le: ha a kapott `previous`
  már elért (`isAchieved == true`), a friss bizonyíték csak
  `evidenceSessionCount`-et maximalizál (előző érték alá sosem megy); az
  `achievedAt` és a `badge` érintetlen.
- A jelvény `toSummary()`-ja zárt kulcskészlettel tér vissza
  (`milestoneId, skill, metric, difficulty, tempoBpmMin, tempoBpmMax,
  contributingSessionCount, achievedAt`) — nincs `sessionId`, nincs `audio`,
  nincs `rawAudio`, nincs `waveform`, nincs `freeText`, nincs `posture`,
  nincs `pain`, nincs `injuryRisk`, nincs `medical`. Az A7 teszt ezt az
  alábbiakkal fogja: kulcsnév-reject + stringified-érték-reject
  (`flat.toLowerCase()`).

### 10.6 Kérdés a review-hoz

- A `MasteryTempoRange.contains(num bpm)` metódus a `minBpm == maxBpm`
  egyenlőséget is elfogadja (inkluzív mindkét végén) — szándékos, hogy egy
  "konkrét tempó" milestone (pl. 100 BPM) definiálható legyen
  `MasteryTempoRange(minBpm: 100, maxBpm: 100)`-szal. Ha a review más
  szemantikát szeretne (pl. minimum 1 BPM szélesség), az a
  `MasteryTempoRange` egy sora, de most nem bántottam.

## 11. Review — a Claude tölti ki
