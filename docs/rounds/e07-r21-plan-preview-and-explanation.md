# E07-R21 — Plan preview, explanation és kézi szerkesztés

- **Státusz:** PREPARED → **revideálva** (ADR 0112 önjavító kör, H2,
  2026-08-18 — a §0.0 rögzíti a mért gyökérokot és a feloldást; eredetileg
  előre megírva 2026-08-15, kód olvasva: `main @ 135ef4af`)
- **Típus:** Epic 7 (AI Practice Generator), SDD Ch8 Kör 21
- **Kör-azonosító:** `E07-R21`
- **Branch:** `<motor>/e07-r21-plan-preview-and-explanation`
- **Előfeltétel:** `E07-R20` merge-elve (setup wizard)
- **Brief szerzője:** Claude (Opus 5)
- **Előre kiosztott ADR:** nincs — a határokat az ADR 0264 (faktoronkénti
  indoklás), 0263 (validáció mint kapu) és 0266 rögzíti. **Pontosítás
  (§0.0, 2026-08-18):** a 0266 az ATOMICITÁSRÓL szól (megszakítás után nincs
  írás, RÉSZLEGES terv nem aktiválódik) — nem arról, hogy egy TELJES, sikeres
  generálás emberi megerősítés nélkül aktiválódjon-e. Ez a brief korábbi
  „nincs automatikus aktiválás" glosszája téves volt.

> ⚠ **Pre-flight (indítás előtt KÖTELEZŐ):** olvasd újra az R12
> `SkillPriority` faktor-listáját (a magyarázat ebből épül) és az R11
> `PlanValidationIssue` súlyossági szintjeit. Eltérésnél §0.0 revízió.
>
> **H2 self-heal revízió után (§0.0, 2026-08-18):** a `PlanPreviewController`
> ebben a körben NEM hívja a `GenerationOrchestrator`-t/
> `PlanGeneratorController`-t — a §5.1 „csak explicit megerősítésre aktivál"
> mandátum a MEGLÉVŐ, már publikus `GenerationPlanActivation` és
> `PlanValidator` szerződéseken át, kizárólag engedélyezett
> `presentation/**` fájlokból teljesíthető. A merge-elt R18/R19 egyetlen
> sora sem módosul, `allowed_paths` byte-for-byte változatlan — a kör ÚJRA
> dispatch-elhető.

```ai-router
schema_version = 1
risk = "high"
allowed_paths = [
  "lib/features/practice_generator/presentation/screens/plan_preview_screen.dart",
  "lib/features/practice_generator/presentation/widgets/plan_day_card.dart",
  "lib/features/practice_generator/presentation/widgets/plan_block_card.dart",
  "lib/features/practice_generator/presentation/widgets/plan_reason_sheet.dart",
  "lib/features/practice_generator/presentation/controller/plan_preview_controller.dart",
  "lib/l10n/app_en.arb",
  "lib/l10n/app_hu.arb",
  "lib/features/practice_generator/public.dart",
  "test/features/practice_generator/presentation/plan_preview_screen_test.dart",
  "test/features/practice_generator/presentation/plan_reason_sheet_test.dart",
  "docs/rounds/e07-r21-plan-preview-and-explanation.md",
]
gate_tests = [
  "test/features/practice_generator/presentation/plan_preview_screen_test.dart",
  "test/features/practice_generator/presentation/plan_reason_sheet_test.dart",
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

## 0.0 Pre-flight revízió — H2 self-heal, feloldva (ADR 0112, 2026-08-18)

**Mért gyökérok.** Az első dispatch (orchestrátor=Terra, implementer=minimax,
session `pipeline-E07-R21-fallback`) H2-vel halt: mérése szerint a §5.1
„csak explicit felhasználói megerősítésre aktivál" mandátum ütközik a
merge-elt E07-R18 tényleges implementációjával, és ezt a briefben tiltott
application-rétegen kívül nem lehet feloldani
(`.pipeline/HALTED`, halted_at=2026-08-18T15:58:08+00:00). A self-heal
(3/3. kísérlet) reprodukálta és megerősítette a mérést:

1. `rg -n -C 3 'final activePlan = plan.copyWith\(status: PlanStatus.active\)|await activation.activate\(activePlan\)' lib/features/practice_generator/application/service/generation_orchestrator.dart`
   → 150–154. sor: `GenerationOrchestrator._run()` a validálás/javítás után
   **egyetlen, megszakítás nélküli lépésben** épít egy `PlanStatus.active`
   másolatot és hívja `activation.activate(activePlan)`-t, mielőtt a
   `generate()` hívónak egyáltalán visszatérne — nincs olyan checkpoint,
   ami egy validált, de MÉG NEM aktív tervet adna vissza.
2. A már merge-elt, zöld `generation_orchestrator_test.dart` ezt a
   szerződést AKTÍVAN méri: `A2 late`/`A5`/`A6` mindhárom cellája
   `activation.calls == 1`-et és `plan.status == PlanStatus.active`-et vár
   el egy SIKERES `generate()` hívás után — ezen a szerződésen bármi
   módosítás ezt a három, R21 `allowed_paths`-án KÍVÜLI tesztet pirosra
   váltaná.
3. A brief saját frontmatterje az ADR 0266-ot „nincs automatikus aktiválás"-
   ként glosszázta — de az ADR tényleges 2. döntése („Részleges terv soha
   nem aktiválódik") kizárólag a MEGSZAKÍTOTT/hibás futásra vonatkozik.
   R18 azon döntése, hogy egy TELJES, sikeres generálást a `generate()`
   saját záró hatásaként azonnal aktivál, az ADR 0266 keretein BELÜLI
   implementációs választás volt, nem annak tiltása. A brief korábbi
   glosszája ezért téves premisszára épült.

**A halt saját elemzése két utat ajánlott** — R18 aktivációs határának
módosítása külön körben/ADR-rel, vagy R21 scope-jának csökkentése egy nem
integrált preview-komponensre. A második út **teljes egészében elérhető a
jelenlegi `allowed_paths`-on belül**, ugyanazzal az elvvel, amit az
E07-R19/H3 self-heal is rögzített (`tools/tests/test_e07_r19_repository_contract_scope.py`,
[[L302]]): meglévő, már publikus típusokat kell újrahasználni, nem tilos
zónát nyitni.

**Feloldás.** A `PlanPreviewController` (és rá épülő `plan_preview_screen`/
`plan_day_card`/`plan_block_card`/`plan_reason_sheet`) ebben a körben:

- **Nem importálja és nem hívja** a `GenerationOrchestrator`-t vagy a
  `PlanGeneratorController`-t. Egy már összeállított `AdaptivePracticePlan`-t
  és a hozzá tartozó `PlanValidationContext`-et kap paraméterként (teszthez:
  fixture; a valódi előállítás — vagyis hogy a `GenerationOrchestrator`
  hogyan adjon egy MÉG NEM aktivált tervet a preview elé — egy KÉSŐBBI,
  még ki nem osztott „production wiring" kör dolga, ld. alább).
- Minden szerkesztés után a MEGLÉVŐ, változatlan
  `PlanValidator.validate(plan, context)`-et hívja (mindkettő már publikus a
  `public.dart`-on) — nem repair-t, csak validálást (§5.2: a kézi
  szerkesztés nem automatikusan javított, csak újra megmért).
- A „megerősítés" (confirm) a MEGLÉVŐ, `generation_orchestrator.dart:28`-on
  deklarált `abstract interface class GenerationPlanActivation`
  (`Future<void> activate(AdaptivePracticePlan plan)`) egy injektált
  példányát hívja — UGYANAZT a típust, amit R18 is használ, nem egy új,
  presentation-lokális típust. A controller a hívás ELŐTT maga építi a
  `plan.copyWith(status: PlanStatus.active)` másolatot (pontosan a
  `generation_orchestrator.dart:150` mintáját követve), és csak akkor hívja
  `activation.activate(...)`-ot, ha nincs `error`-szintű lelet — a `warning`
  eset explicit áttekintést kényszerít ki (A4), de nem blokkol.
- A teszteléshez (A1/A3/A8) egy `_RecordingActivation`-szerű fake injektálható
  — pontosan a R18 saját tesztjében (`generation_orchestrator_test.dart`)
  már bevált idióma —, ami a `calls` számlálóval bizonyítja: kilépés/hibás
  lelet mellett `0`, explicit megerősítés után `1`.

**Ami emiatt EXPLICIT nem ennek a körnek a scope-ja** (dokumentált
follow-up, `HANDOFF.md`-ben is jelölve): a valódi, éles bekötés — hogy a
`GenerationOrchestrator.generate()` egy MÉG NEM aktivált, csak validált
checkpointot adjon vissza a preview elé, mielőtt a saját belső aktivációs
lépése lefutna — a mai fúzionált (`assemble → validate → repair → activate`
egyetlen hívásban) szerződéssel STRUKTURÁLISAN nem megoldható, függetlenül
attól, melyik jövőbeli kör próbálná meg. Ez azt jelenti, hogy egy
KÉSŐBBI, még ki nem osztott kör(ök)nek külön kell szétválasztania a
`generate()` aktivációs lépését egy explicit, elkülönített hívássá, mielőtt
ez a preview-képernyő valódi generálási folyamatra köthető. Ez a döntés
NEM ennek a körnek a acceptance criteria-ját (§6) bővíti — A1–A8 mindegyike
teljesíthető és mérhető a fenti, önmagában álló komponenssel.

Ez a revízió a kör §2 „önállóan dönthetsz… ezt a kör-briefet (dokumentált
§0.0 revízióval)" hatáskörébe tartozik: `allowed_paths` **byte-for-byte
változatlan**, 0 új production fájl a §4 listán túl, és a §6 acceptance
criteria sem tágul — kizárólag azt mondja meg, MELYIK meglévő, publikus
típuson át teljesíthető a §1 „Cél" anélkül, hogy a tilos application-réteget
érintené. Regressziós őr:
`tools/tests/test_e07_r21_activation_boundary_scope.py`.

## 1. Cél

A generált terv teljes, átlátható előnézete **mentés és aktiválás előtt**
(SDD Ch8 Kör 21).

## 2. Jelenlegi állapot — mért tények

- Az R12 prioritásai **faktoronként** bonthatók (ADR 0264 §1) — a magyarázat
  ebből épül, nem külön szöveg-generálásból.
- Az R11 validátora `info`/`warning`/`error`/`fatal` leletet ad; `error`
  mellett a terv nem aktiválható (ADR 0263 §1).
- Az offline-first elv (SDD Ch8 §2.4): az előnézet és a magyarázat hálózat
  nélkül működik.

## 3. Scope

**Benne van:** napok és blokkok renderelése · **reason code alapján
lokalizált** magyarázat · idő-, nap-, blokk- és preferencia-szerkesztés ·
**minden szerkesztés után újravalidálás** · figyelmeztetés esetén explicit
áttekintés · aktiválás **csak** felhasználói megerősítésre.

**NINCS benne (tilos):** automatikus mentés vagy aktiválás · a validátor
megkerülése · a domain módosítása · flag `true`-ra állítása · hálózati hívás ·
`docs/adr/**`, `tools/**`, `.github/**`.

## 4. Engedélyezett fájlok

| Útvonal | Indok |
|---|---|
| `presentation/screens/plan_preview_screen.dart` | **ÚJ** — az előnézet |
| `presentation/widgets/plan_day_card.dart` | **ÚJ** |
| `presentation/widgets/plan_block_card.dart` | **ÚJ** |
| `presentation/widgets/plan_reason_sheet.dart` | **ÚJ** — a magyarázat |
| `presentation/controller/plan_preview_controller.dart` | **ÚJ** — szerkesztés + újravalidálás |
| `lib/l10n/app_en.arb`, `app_hu.arb` | reason code → szöveg |
| `public.dart` | a barrel bővítése |
| `test/…/presentation/*_test.dart` (2 db) | a §6 cellái |
| `docs/rounds/e07-r21-…md` | a §10 handoff |

**Tilos zóna:** `lib/app/config/feature_flags.dart` · a generátor domain- és
application-rétege · más `lib/features/**` · `docs/adr/**` · `tools/**`.

## 5. Kötött architekturális döntések

### 5.1 NINCS rejtett automatikus mentés vagy aktiválás

A terv csak explicit felhasználói megerősítésre válik aktívvá. Az előnézetből
való kilépés nem aktivál.

**NEM elfogadható gyengítés:** „ha megnézte, nyilván akarja".

### 5.2 Minden szerkesztés UTÁN újravalidálás

A kézi módosítás ugyanazon a validátoron megy át, mint a generált terv
(ADR 0263 §1). `error` mellett az aktiválás tiltott — a kézi szerkesztés nem
kerülőút.

### 5.3 A magyarázat REASON CODE-ból lokalizált, nem szabad szöveg

A backend faktorokat és kódokat ad; a szöveg az ARB-ből jön. Így a magyarázat
két nyelven ugyanazt mondja, és offline is működik.

### 5.4 Az evidence-lap NEM állít többet, mint a confidence

Ha a becslés bizonytalan, a magyarázat ezt **kimondja** — nem sugall
bizonyosságot. Az ADR 0261 §3 UI-oldali betartása.

**NEM elfogadható gyengítés:** „a mérés szerint gyenge vagy" olyan adatból,
ami egyetlen bizonytalan mérés.

### 5.5 Az előnézet OFFLINE működik

Nincs hálózati hívás a rendereléshez vagy a magyarázathoz.

### 5.6 Figyelmeztetés esetén EXPLICIT áttekintés

`warning` szintű lelet mellett az aktiválás előtt a felhasználónak látnia
kell a figyelmeztetést — nem elrejtve egy részletek-panelben.

## 6. Acceptance criteria

| # | Kritérium | Bizonyíték |
|---|---|---|
| A1 | Az előnézetből kilépés NEM aktivál és NEM ment | `plan_preview_screen_test.dart` |
| A2 | Minden szerkesztés után újravalidálás fut | ugyanott |
| A3 | `error` lelet mellett az aktiválás tiltott, kézi szerkesztés után is | ugyanott |
| A4 | `warning` mellett explicit megerősítés kell | ugyanott |
| A5 | A magyarázat reason code-ból, ARB-ből jön (hu + en) | `plan_reason_sheet_test.dart` |
| A6 | Bizonytalan becslésnél a magyarázat ezt kimondja | ugyanott |
| A7 | Az előnézet hálózat nélkül működik | ugyanott |
| A8 | Az aktiválás csak explicit megerősítésre történik | `plan_preview_screen_test.dart` |

### 6.1 Mérce-mátrix — melyik hibás implementációt melyik cella fogja pirosra

| Hibás implementáció | Melyik cella vált PIROSRA |
|---|---|
| Kilépéskor automatikus mentés | **A1** |
| A kézi szerkesztés kihagyja a validátort | **A3** |
| A warning egy összecsukott panelben | A4 |
| Hard-kódolt magyarázó szöveg | A5 |
| A magyarázat bizonyosságot sugall bizonytalan adatból | **A6** |
| Hálózati hívás a magyarázathoz | A7 |

**A lelet-súlyosság három kötelező cellája** (a küszöb: az aktiválhatóság):

| Cella | Bemenet | Elvárt |
|---|---|---|
| a küszöb alatt | csak `info` lelet | aktiválható, külön megerősítés nélkül |
| rajta (a küszöbön) | `warning` lelet | aktiválható, de **explicit áttekintés** után |
| a küszöb fölött | `error` lelet | **nem aktiválható** |

**Valódi-sértés próba (KÖTELEZŐ, §10-ben dokumentálva):** engedd a kézi
szerkesztést újravalidálás nélkül → az **A3** cellának PIROSNAK kell lennie →
állítsd vissza.

## 7. Kötelező ellenőrzések

```bash
tools/round-gate.sh test/features/practice_generator/presentation/plan_preview_screen_test.dart test/features/practice_generator/presentation/plan_reason_sheet_test.dart
```

Külön processzek, csonkítatlan kimenet. **Tilos** `| tail`, `| head`,
`&&`-lánc vagy bármilyen szűrés (L09); a `flutter analyze` és `flutter test`
kézi láncolása OOM-ot ad (L05). A kötelező gate-et **TILOS háttérbe küldeni**
(`run_in_background`) — az egy-fordulós harness a forduló végén megöli (L254).

## 8. Implementációs sorrend

1. ARB reason-code kulcsok (hu + en).
2. `plan_preview_controller.dart` — szerkesztés + kötelező újravalidálás.
3. `plan_day_card.dart`, `plan_block_card.dart`.
4. `plan_reason_sheet.dart` — faktorokból épített, confidence-hű magyarázat.
5. `plan_preview_screen.dart` — megerősítéshez kötött aktiválás.
6. Tesztek a §6.1 három súlyossági cellájával.
7. A valódi-sértés próba, §10-be dokumentálva.
8. `tools/round-gate.sh` a §7 szerint.

## 9. Kockázatok

- **A „kényelmes" automatikus mentés.** Kevesebb kattintás, és a tanuló olyan
  tervet kap, amit nem hagyott jóvá (A1).
- **A kézi szerkesztés mint kerülőút.** A felhasználó „tudja, mit csinál" —
  és érvénytelen tervet aktiválna (A3).
- **A túlbeszélő magyarázat.** Egy bizonytalan mérésből határozott ítélet:
  a felhasználó bizalmát rombolja, amikor kiderül (A6).

## 10. Implementation handoff — az implementer tölti ki

## 11. Review — a Claude tölti ki
