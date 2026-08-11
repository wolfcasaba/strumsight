# E07-R01 — Practice Generator baseline, ADR-ek és feature flagek

- **Státusz:** PREPARED (batch előre megírva **2026-08-11**, kód olvasva:
  `main` @ `b4387ac1`; az Epic 6 ekkor FUTOTT — a pre-flight kötelező)
- **SDD-kör:** [`docs/sdd/08-epic-07-ai-practice-generator.md`](../sdd/08-epic-07-ai-practice-generator.md)
  **Kör 1** (2936–2981. sor)
- **Batch-index:** [`epic-07-batch-index.md`](epic-07-batch-index.md)
- **Branch:** `codex/e07-r01-planner-baseline-and-adrs`
- **Előfeltétel:** **Epic 6 lezárva** (E06-R30 merge) — a batch `hold`-ja
  addig áll
- **Brief szerzője:** Claude (Opus 5, batch) · **Implementáció:** a queue
  `engine` oszlopa dönti el
- **Előre kiosztott ADR:** **`0221`** és **`0222`** — a kör **KETTŐT** ír
  (§5.1). A tartomány `0221`–`0232`, ld. batch-index.

```ai-router
schema_version = 1
risk = "high"
allowed_paths = [
  "lib/app/config/feature_flags.dart",
  "docs/adr/0221-deterministic-first-practice-planning.md",
  "docs/adr/0222-practice-plan-revisions.md",
  "docs/sdd/epic-07-baseline.md",
  "test/app/feature_flags_test.dart",
  "test/core/architecture_dependency_test.dart",
  "docs/rounds/e07-r01-planner-baseline-and-adrs.md",
]
gate_tests = [
  "test/app",
  "test/core",
]
native_gate = false
```

> **Két ÚJ ADR-fájl + egy ÚJ baseline-doksi** (`docs/sdd/epic-07-baseline.md`).
> Ez a kör kivétel a szokás alól: az SDD Kör 1 feladatlistája **kifejezetten
> előírja**, hogy az ADR-eket ez a kör rögzítse. Minden más új fájl
> scope-sértés.

## 0. Kör-jelzés és STOP-protokoll

```bash
tools/codex-signal.sh progress "<egy sor>" ; tools/codex-signal.sh done "<egy sor>"
tools/codex-signal.sh stopped "<egy sor>"  ; tools/codex-signal.sh blocked "<egy sor>"
```

Lezáró jelzés nélkül a kör bukott. Listán kívüli fájl → `stopped`.

## 0.0 ⚠ KÖTELEZŐ pre-flight (a brief ELŐRE készült)

Ez a brief **2026-08-11-én** íródott, amikor az Epic 6 még futott. Az élesedés
előtt **mérd újra**, és `§0.0 revízió`-ként dokumentáld az eltérést:

1. `lib/app/config/feature_flags.dart` — a §2.1 flag-tábla még érvényes-e
   (az Epic 6 saját flageket vezetett be).
2. `dart run tool/check_architecture.dart` — az allowlist mérete (a §2.2
   szerint **12**; a lista **csak szűkülhet**).
3. A §2.3 legacy forrás-fájlszámok.
4. A ténylegesen szabad ADR-számok (`ls docs/adr/`) — ha a 0221/0222 közben
   elkelt, a batch-index tartományából vegyél másikat, és **javítsd az
   `allowed_paths`-t is**.

## 1. Cél

A Practice Generator fejlesztési **határainak** rögzítése — alkalmazáslogika
módosítása **nélkül**. Ez baseline-kör: két architekturális döntést ír le,
bevezet két kikapcsolt feature flaget, és dokumentálja, melyik legacy
forrásokból fog a tervező bizonyítékot gyűjteni.

**Viselkedésváltozás NEM történhet.**

## 2. Jelenlegi állapot (mérve 2026-08-11, `main @ b4387ac1`)

### 2.1 A flag-felület

`FeatureFlags.forEnvironment` (`lib/app/config/feature_flags.dart`) mai
értékei — `nonProd = environment != AppEnvironment.production`:

| Flag | Érték |
|---|---|
| `diagnosticsEnabled`, `labModeAvailable` | `nonProd` |
| `practiceEngineV2Enabled` | `nonProd` |
| `migratedLearnEnabled` | `nonProd` (GOV-05c óta) |
| `practiceDetailedHistoryEnabled` | `nonProd` |
| `songTrainerV2Enabled` | `nonProd` (GOV-05a óta) |
| `aiTutorEnabled`, `aiTutorCloudEnabled` | `false` |
| 11 db `vision*` | `false` |

Dart-define override egyetlen rollout-flagre sincs. A default konstruktor
minden opcionális flaget `false`-on hagy.

### 2.2 Az architektúra-őr

`dart run tool/check_architecture.dart` → **„Architecture dependencies OK
(12 allowlisted deviation(s))"**. A `tool/check_architecture.dart` 6. sori
doc-commentje: *„This allowlist may only shrink. Adding an entry requires a
written…"* — **a lista bővítése tilos.**

### 2.3 A legacy bizonyíték-források (amit a tervező majd olvas)

| Feature | Dart fájl |
|---|---|
| `lib/features/learn` | 24 |
| `lib/features/progress` | 8 |
| `lib/features/streak` | 8 |
| `lib/features/songs` | 15 |
| `lib/features/analyze` | 14 |

Ezek MA is léteznek és lezárt epicekhez tartoznak — ez a kör **csak
dokumentálja** őket, nem nyúl hozzájuk.

## 3. Scope

**Benne:**

1. `practiceGeneratorEnabled` és `plannerAssistEnabled` flag bevezetése,
   **mindkettő `false` minden környezetben** (§5.2).
2. **ADR 0221** — deterministic-first tervezés: a modell nem hozhat létre
   közvetlenül végrehajtható tervet (§5.3).
3. **ADR 0222** — revision-alapú immutable múlt (§5.4).
4. `docs/sdd/epic-07-baseline.md` (ÚJ) — a §2.3 legacy adapterforrások
   tételes dokumentálása + a baseline teszt/build-állapot.
5. A flag-kerítés tesztje és az architektúra-teszt frissítése, **ha** a
   dependency-szabály bővül (§5.5).
6. A brief §10 handoff.

**Kívül (ebben a körben TILOS):**

- **Bármilyen alkalmazáslogika.** A kör nem hoz létre `lib/features/practice_generator/`
  könyvtárat, nem ír domain-típust — az a Kör 2 dolga.
- A §2.3 legacy feature-ek bármely fájlja.
- Az architektúra-allowlist **bővítése** (§2.2 — csak szűkülhet).
- Új hálózati hívás bárhol.
- Bármely más flag értékének megváltoztatása.
- `.github/`, `tools/`, `assets/`, `lib/l10n/`.

## 4. Engedélyezett fájlok

| Útvonal | Miért |
|---|---|
| `lib/app/config/feature_flags.dart` | a két ÚJ flag |
| `docs/adr/0221-deterministic-first-practice-planning.md` | **ÚJ** ADR |
| `docs/adr/0222-practice-plan-revisions.md` | **ÚJ** ADR |
| `docs/sdd/epic-07-baseline.md` | **ÚJ** baseline-dokumentáció |
| `test/app/feature_flags_test.dart` | a flag-kerítés |
| `test/core/architecture_dependency_test.dart` | a dependency-szabály |
| `docs/rounds/e07-r01-planner-baseline-and-adrs.md` | §10 handoff |

**Tilos zóna:** `lib/features/**` (MINDEN), `lib/app/` a `config/feature_flags.dart`
kivételével, `lib/l10n/`, `tool/`, `tools/`, `.github/`, `assets/`, `backend/`,
`docs/adr/` a két nevesített ÚJ fájlon kívül.

## 5. Kötött architekturális döntések

### 5.1 A kör KETTŐ ADR-t ír — ez kivétel

A projekt szokása szerint az ADR-t az orchesztrátor írja a pre-flightban. Az
SDD Kör 1 feladatlistája viszont **kifejezetten a kör feladatává teszi**
(„Rögzítsd ADR-ben…"), ezért itt az implementer írja, a §5.3/§5.4-ben
megadott Döntés-tartalommal. A szám (`0221`, `0222`) kötött.

### 5.2 A két flag `false` MINDEN környezetben

Nem `nonProd`. Indok: a tervező 30 körön át épül; egy félkész generátor
dev-buildben is félrevezető tervet adna. A rollout az Epic 7 **zárókörének**
döntése lesz, a GOV-05a mintájára (flag + belépési pont EGYÜTT).

A default konstruktor paramétere is `false`.

### 5.3 ADR 0221 — deterministic-first: a modell NEM tervez

A generált terv **determinisztikus motorból** származik (priority engine,
candidate selector, time-budget allocator). Egy nyelvi modell szerepe
legfeljebb **javaslat és magyarázat** (`plannerAssistEnabled`), és a
kimenetét **validátornak kell átengednie** (Kör 11), mielőtt terv lesz belőle.

**Nem elfogadható:** modell által közvetlenül előállított, végrehajtható
`AdaptivePracticePlan`; a validátor megkerülése „mert a modell úgyis jót ad".

### 5.4 ADR 0222 — a múlt immutable, a változás revízió

Egy már kiadott terv **nem módosul helyben**. A változás **új revíziót** hoz
létre, a régi megmarad. Indok: a felhasználó gyakorlási előzménye
bizonyíték-forrás — ha visszamenőleg átírható, a mérés értelmét veszti.

**Nem elfogadható:** in-place mutáció; a régi revízió törlése; „csak a
metaadatot írjuk át" kivétel.

### 5.5 Az architektúra-allowlist csak SZŰKÜLHET

Ha a kör dependency-szabályt bővít (új cross-feature import tiltása), az
**szigorítás** — az allowlist elemszáma nem nőhet a mért **12** fölé. Ha
nőnie kellene → `stopped`.

### 5.6 Nyitott döntések (ADR 0138)

```yaml
open_decisions:
  - id: OD-01
    question: Hova kerüljön a baseline-dokumentáció?
    blocking: false
    resolution_policy: use_default
    default: >
      `docs/sdd/epic-07-baseline.md` — az epic-completion-report mintájára,
      a `docs/sdd/` alá. NEM a `docs/rounds/` alá: az a kör-briefek helye.

  - id: OD-02
    question: A `plannerAssistEnabled` függjön-e az `aiTutorEnabled`-től?
    blocking: false
    resolution_policy: use_default
    default: >
      NEM, ebben a körben nincs `AppConfig.resolve` megkötés közöttük. A
      planner-assist a tervező SAJÁT kapcsolója; a Tutorral való kapcsolat
      a Kör 28 tárgya, és az fogja eldönteni, kell-e függőségi szabály.

  - id: OD-03
    question: Mi legyen, ha a pre-flight szerint a 0221/0222 elkelt?
    blocking: false
    resolution_policy: use_default
    default: >
      Vedd a batch-index 0221-0232 tartományának első két szabad számát,
      és javítsd az `allowed_paths` két ADR-útvonalát is. Dokumentáld a
      §0.0 revízióban.
```

## 6. Acceptance criteria

- [ ] **A1 — A két ÚJ flag `false` mind a három környezetben.** Külön
  cellaként (nem `AppEnvironment.values` ciklus):

  | `AppEnvironment` | `practiceGeneratorEnabled` | `plannerAssistEnabled` |
  |---|---|---|
  | `development` | `false` | `false` |
  | `lab` | `false` | `false` |
  | `production` | `false` | `false` |

- [ ] **A2 — A default konstruktor is `false`-on hagyja** mindkettőt
  (`const FeatureFlags(accountEnabled: false, diagnosticsEnabled: false,
  labModeAvailable: false)`).

- [ ] **A3 — Kerítés: egyetlen MEGLÉVŐ flag értéke sem változott.** Mind a
  három környezetre a §2.1 tábla szerinti értékek. Ez a cella fogja meg, ha
  a kör „menet közben" hozzányúl a rollout-flagekhez.

- [ ] **A4 — Nulla viselkedésváltozás:** a `git diff --name-only origin/main...HEAD`
  a `lib/` alatt **kizárólag** `lib/app/config/feature_flags.dart`-ot ad.

- [ ] **A5 — Az architektúra-allowlist NEM NŐTT.**
  `dart run tool/check_architecture.dart` kimenete legfeljebb **12**
  allowlisted deviation. Ha kevesebb: az szigorítás, elfogadott.

- [ ] **A6 — Mindkét ADR létezik és tartalmazza a kötött Döntést.**
  A 0221 kimondja, hogy a modell nem állíthat elő közvetlenül végrehajtható
  tervet, és hogy a validátor megkerülhetetlen; a 0222 kimondja, hogy a
  kiadott terv nem módosul helyben, a változás új revízió.

- [ ] **A7 — A baseline-doksi tételesen megnevezi a legacy adaptereket**
  (`learn`, `progress`, `streak`, `songs`, `analyze`), a §2.3 fájlszámokkal
  vagy azok pre-flight-frissített értékével.

- [ ] **A8 — Nincs új hálózati kérés.** A diff nem vezet be `Dio`, `http`,
  `HttpClient` hívást; gépi mérce: `git diff origin/main...HEAD -- lib/ | grep -cE '^\+.*(Dio|http\.|HttpClient)'` → **0**.

- [ ] **A9 — A gate zöld** a §7 szerinti egyetlen artefaktum-hívással.

> **Miért nincs numerikus cellahármas:** a kör egyetlen acceptance-pontja sem
> mér számértékre — minden mérce logikai (flag-érték, fájl érintettsége,
> szöveg megléte). Az A5 elemszám-korlát nem numerikus mérce, hanem monoton
> szigorítási szabály: a lista **csak szűkülhet**, tehát nincs „alatta/rajta/
> fölötte" háromsága — minden növekedés egyformán tilos.

### 6.1 Mérce-mátrix — melyik hibás implementációt melyik cella fogja pirosra

| Hibás implementáció | Melyik cella vált PIROSRA |
|---|---|
| A flag `nonProd`-ra állítva `false` helyett | **A1** `development`/`lab` cellák |
| A default konstruktor `true`-ra írva | **A2** |
| A kör „menet közben" bekapcsol egy meglévő flaget | **A3** |
| Domain-kód íródik `lib/features/practice_generator/` alá | **A4** |
| Az allowlist bővül egy új kivétellel | **A5** |
| Az ADR csak említi, de nem mondja ki a validátor megkerülhetetlenségét | **A6** (reviewer eldobható próbája: a Döntés-szakasz grepje) |
| A baseline-doksi csak általánosságban ír „legacy forrásokról" | **A7** |
| Hálózati hívás kerül be | **A8** |

**Valódi-sértés próba (kötelező, §10-ben dokumentálandó):** írd át
ideiglenesen a `practiceGeneratorEnabled` sorát `false`-ról `nonProd`-ra →
az **A1 `development` cellájának PIROSNAK kell lennie** → állítsd vissza, és
idézd a nyers kimenetet.

## 7. Kötelező ellenőrzések

```bash
tools/round-gate.sh test/app test/core
```

Külön processzek, csonkítatlan kimenet. **Tilos** `| tail`, `| head`,
`&&`-lánc vagy bármilyen szűrés (`docs/LESSONS.md` L09); az `analyze` és a
`test` kézi láncolása ezen a gépen OOM-ot ad (L05).

## 8. Implementációs sorrend

1. **RED először:** `feature_flags_test.dart` — A1 három környezet-cellája
   mindkét flagre, A2, A3 kerítés.
2. A két flag bevezetése a `FeatureFlags` konstruktorba és a factoryba,
   `false` értékkel.
3. ADR 0221 és 0222 megírása (§5.3, §5.4 kötött tartalommal).
4. `docs/sdd/epic-07-baseline.md` — a legacy források tételes listája.
5. Ha dependency-szabály bővül: `architecture_dependency_test.dart`
   **szigorítás**, az allowlist elemszámának növelése nélkül.
6. Gate.
7. A §6.1 valódi-sértés próba + visszaállítás.
8. Záró gate + §10 handoff + `done`.

## 9. Kockázatok

1. **Az Epic 6 közben saját flageket vezetett be** — a §2.1 tábla avulhat.
   Ezért kötelező a §0.0 pre-flight.
2. **Az ADR-számok elkelhetnek** (OD-03).
3. **A kör csábít a „kezdjük is el a domaint" irányba** — az a Kör 2. Az A4
   gépi mércéje ezt fogja meg.

## 10. Implementation handoff — a Codex tölti ki

- Fájlonkénti összefoglaló.
- Futtatott parancsok + **TÉNYLEGES, csonkítatlan** kimenet.
- A §6.1 valódi-sértés próba nyers kimenete + visszaállítás.
- Az **A4/A5/A8** gépi mércéinek tényleges kimenete.
- A §0.0 pre-flight mérései és az esetleges revízió.
- Eltérések és okuk; nem futtatott ellenőrzések és okuk; follow-upok.

> Állítás teszt nélkül = bemondás.

## 11. Review — a Claude tölti ki

Link: `docs/reviews/e07-r01-planner-baseline-and-adrs-review.md`
