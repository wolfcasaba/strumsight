# E05-R25 — Practice Engine vision integráció

- **Státusz:** PLANNING (pre-flight lezárva 2026-08-08, kód mérve: main @ `1d5888f`)
- **SDD-kör:** [`docs/sdd/06-epic-05-computer-vision.md`](../sdd/06-epic-05-computer-vision.md) Kör 25; §25
- **Branch:** `codex/e05-r25-practice-vision-integration`
- **Előfeltétel:** **E05-R22, E05-R23, E05-R24 merge** (mindhárom zöld, `main`-en; ellenőrizve)
- **Brief szerzője:** Claude (batch, 2026-08-05) · **Pre-flight revízió:**
  Claude Sonnet 5 (2026-08-08) · **Implementáció:** Codex (Terra)

> ✅ **Pre-flight ELVÉGEZVE (2026-08-08).** Eredmény lásd §0.0 és
> [ADR 0192](../adr/0192-practice-vision-integration-contract.md). Rövid
> összefoglaló: `PracticeSessionResult`-nak **nincs** saját JSON-kódja (a
> perzisztencia `PracticeHistoryEntry`-n át fut, ami `allowed_paths`-on
> kívül esik és R28 dolga), ezért a §6 negyedik cellája ("deszerializációs
> teszt") a mért valósághoz igazítva **revideálva** (ld. §0.0/2 és §6). A
> `practice → vision/public.dart` cross-feature import mindkét gépi őrrel
> (architektúra + domain-purity) mérve legális, allowlist-bővítés nélkül. A
> három pilot gyakorlat **nem** `BuiltinPracticeCatalog`-bejegyzés (az a
> fájl nincs `allowed_paths`-on) — a kör saját új fájljain belüli adat.

```ai-router
schema_version = 1
risk = "high"
allowed_paths = [
  "lib/features/vision/domain/integration/vision_practice_contract.dart",
  "lib/features/practice/data/vision/practice_vision_adapter.dart",
  "lib/features/practice/domain/model/practice_session_result.dart",
  "lib/features/practice/public.dart",
  "lib/features/vision/public.dart",
  "lib/features/practice/presentation/widgets/practice_vision_dimension.dart",
  "lib/l10n/app_en.arb",
  "lib/l10n/app_hu.arb",
  "test/features/practice/data/practice_vision_adapter_test.dart",
  "test/features/practice/domain/practice_session_result_vision_test.dart",
  "test/features/practice/presentation/practice_vision_dimension_test.dart",
  "docs/adr/0192-practice-vision-integration-contract.md",
  "docs/rounds/e05-r25-practice-vision-integration.md",
]
gate_tests = [
  "test/features/practice",
  "test/features/vision",
]
native_gate = false
```

> ⚠ **Pre-flight (KÖTELEZŐ) — ELVÉGEZVE, ld. a ✅ dobozt fent és §0.0.**
> Eredeti instrukció (történeti, a `nincs ÚJ ADR` rész időközben elavult —
> ld. ADR 0192): `origin/main` + E05-R22/R23/R24 merge; olvasd újra
> `lib/features/practice/domain/model/practice_session_result.dart` **mai
> mezőit és minden hívóhelyét** (`rg -n "PracticeSessionResult" lib test | wc -l`),
> valamint a `practice/public.dart` exportjait. **A meglévő audio-pontozás
> viselkedése nem változhat.**

## 0. Kör-jelzés és STOP-protokoll

```bash
tools/codex-signal.sh progress "<egy sor>" ; tools/codex-signal.sh done "<egy sor>"
tools/codex-signal.sh stopped "<egy sor>" ; tools/codex-signal.sh blocked "<egy sor>"
```

Lezáró jelzés nélkül a kör bukott. Listán kívüli fájl → `stopped`.

## 0.0 Tervezési baseline és pre-flight revízió

**PLANNING.** A pipeline-prompt §1 két kötelező mérési szabálya (elérhetetlen
cél-státusz / erőforrás-tulajdonlás) szerint, plusz a brief saját pre-flight
feladata (a §-fejléc figyelmeztetése: `PracticeSessionResult` mai mezői és
hívóhelyei, `practice/public.dart` exportjai). Teljes indoklás: [ADR
0192](../adr/0192-practice-vision-integration-contract.md) Kontextus
szakasza — itt csak az összefoglaló és a brief-re gyakorolt hatás.

`tools/round-slots.py reserve-adr --round E05-R25` → **0192** (a brief eredeti
`nincs` mezője szerint az ADR-t az orchesztrátor írja a pre-flightban).

1. **`PracticeSessionResult`-nak nincs saját szerializációja — a §6 negyedik
   cellája revideálva.** `grep -n "toJson\|fromJson\|Json"
   lib/features/practice/domain/model/practice_session_result.dart` nulla
   találat. A ténylegesen perzisztált alak `PracticeHistoryEntry`
   (`data/practice_session_result_history_mapper.dart` `toHistoryEntry()`),
   ami **nincs** az `allowed_paths`-on és a §3 explicit „persistence (R28)"
   kizárásának tárgya — nincs mit deszerializálni, mert e kör semmilyen új
   kódolást nem hoz létre. **A §6 negyedik cellája lecserélve** (ld. lent) —
   a revideált verzió három, ténylegesen futtatható próba: konstrukciós
   kompatibilitás (mind a 12 meglévő hívóhely — 1 production
   `application/practice_session_controller.dart:483` + 11 teszt, grep-
   számolva — a `vision` paraméter nélkül is fordul), egyenlőség-regresszió
   (`vision: null` mellett a bővített `operator==`/`hashCode` nem tér el a
   mai szemantikától), és a mapper-érintetlenség, ami már az első
   (audio-parity) cella RÉSZE. Részletek: ADR 0192 Döntés 2.
2. **A `practice/domain/ → vision/public.dart` cross-feature import
   mechanikusan legális — nincs allowlist-bővítés.** `tool/check_architecture.dart`
   `_isFeaturePublicBarrel` bármely `lib/features/<f>/.../public.dart` célt
   elfogad (ADR 0176 mintája — ugyanez engedte a `song_trainer/domain/public.dart`
   nested barrelt E04-R21-nél), és `test/features/practice/domain/domain_purity_test.dart`
   kizárólag az adott fájl saját, közvetlen import-sorát reguláris
   kifejezéssel vizsgálja, nem tranzitívan a célfájl exportjait. Mindkettőt
   elolvasva mérve: a tervezett import egyik gépi őrt sem sérti. **Ismert,
   dokumentált — nem javítandó — határ:** a `vision/public.dart` UI-
   screeneket is exportál, tehát a practice-domain fordítási gráfja
   tranzitívan függővé válik a Fluttertől; ez a mai (nem-tranzitív) scanner-
   kontraktus határa, nem e kör regressziója, és a scannerek módosítása
   (`tool/check_architecture.dart`, `test/core/`) kívül esik ezen a körön.
   Részletek: ADR 0192 Döntés 3.
3. **A három pilot gyakorlat NEM `BuiltinPracticeCatalog`-bejegyzés.**
   `grep -rln BuiltinPracticeCatalog lib/features/practice/` →
   `data/builtin_practice_catalog.dart`, ami **nincs** az `allowed_paths`-on;
   az E02-R04 (ADR 0070) tíz beépített gyakorlata között egyik sem „Small
   Strum Motion" / „Down/Up Symmetry" / „Chord Change Economy". A három
   pilot a kör SAJÁT új fájljain (`vision_practice_contract.dart` /
   `practice_vision_adapter.dart`) belüli adat, stabil `vision.pilot.<slug>`
   jellegű névtér alatt — új katalógus-bejegyzés vagy meglévő módosítása
   TILOS zóna (H3). A `requiredCapabilities` a három meglévő,
   feature-lokális capability-enumra épül (`FrettingCapability`,
   `PickingCapability`, `PostureCapability` — `lib/features/vision/domain/metrics/*.dart`),
   nem önkényes új szótárra. Részletek: ADR 0192 Döntés 4.
4. **A §6 vision-állapot mátrix (`unavailable`/`degraded`/`good`) a
   `VisionQualitySummary.overall`-ból származik determinisztikusan**
   (`good→good`, `needsImprovement→degraded`, `notObservable`/nincs session
   `→unavailable`), nem három egymástól független kézi fixture. Ez teszi a
   mátrixot egy valós termelő jel ellen falszifikálhatóvá (pipeline-prompt
   §1 1. szabálya). Részletek: ADR 0192 Döntés 5.
5. **`VisionSessionResult`-nak nincs érték-egyenlősége** (identitás-alapú
   `==`/`hashCode`, a fájl amúgy sincs `allowed_paths`-on) — a
   `PracticeSessionResult` bővített `operator==`-ja a `vision` mezőn sima
   delegálást használ, nem kap egyedi érték-egyenlőséget. Összhangban a
   típus egyetlen-aggregátum tervezési szándékával (E05-R24). Részletek:
   ADR 0192 Döntés 6.
6. **A „session-summary vision-dimenzió UI" ebben a körben az izolált
   `practice_vision_dimension.dart` widget + saját widget-teszt —
   `practice_result_screen.dart`-ba drótozás KÖVETKEZŐ kör dolga** (a fájl
   nincs `allowed_paths`-on). Ugyanaz a minta, mint az Epic 3 Song Trainer
   sorozat minden eddigi köre. Nulla regressziós kockázat. Részletek: ADR
   0192 Döntés 7.
7. **Erőforrás-tulajdonlás (pipeline-prompt §1/2): nem releváns.** A brief
   egyetlen acceptance-cellája sem rendel lease/lock/handle/subscription-t
   egy réteghez; a `PracticeVisionAdapter` tisztán adat-leképezés
   (`VisionSessionResult` → vision-dimenzió + capability-gate döntés), nincs
   `.acquire(`-hívása vagy erőforrás-tulajdonlása.
8. **Utólagos javítás — az ADR-fájl saját útvonala hiányzott az
   `allowed_paths`-ból az első pre-flight-commitban, pótolva.** Az implementer
   (Terra) az első dispatch-en helyesen `stopped`-ot jelzett, mert
   `docs/adr/0192-practice-vision-integration-contract.md` nem szerepelt a
   §4 listán, jóllehet a fájl az orchesztrátor SAJÁT, dispatch előtti
   pre-flight-commitjának része (a gépi scope-audit ezt nem is auditálja —
   `scope_base` a dispatch-kori HEAD —, de az `allowed_paths` a teljes
   PR-diffet dokumentálja, és a review is efelé auditál). Precedens:
   [ADR 0191](../adr/0191-feedback-policy-and-cue-budget.md) brief-je
   (E05-R23) explicit listázta a saját `docs/adr/0191-…md` útvonalát —
   ugyanaz a minta most pótolva. **Ez nem lista-tágítás az implementer
   számára** (nem kap új jogot semmilyen ÚJ fájlhoz), kizárólag egy már
   ELKÉSZÜLT, saját pre-flight-artefaktum korrekt dokumentálása — a
   pipeline-prompt §2 „a `nincs` ADR-t, amit ebben a pre-flightban te írtál"
   és „ezt a kör-briefet (dokumentált §0.0 revízióval)" pontjai alá esik,
   nem H3. Terra saját, uncommitolt munkája (11 fájl, mind a §4 eredeti
   listáján) a megállás pillanatában ellenőrizve **helyes és teljes** volt —
   a folytatás a meglévő munka commitolásával indul, nem újraírással.

## 1. Cél

**Opcionális** vision-bizonyíték hozzáadása kiválasztott Practice gyakorlatokhoz
úgy, hogy az audio-pontozás **bitre változatlan** marad, és vision nélkül nincs
semmilyen regresszió.

## 2. Jelenlegi állapot (mért, `5d082dc`)

- A Practice Engine V2 él (`lib/features/practice/`), a `PracticeSessionResult`
  a `domain/model/` alatt; az eredmény ma **kizárólag audio** alapú.
- A cross-feature import szabálya: **csak `public.dart`** (architektúra-őr);
  a `check_architecture` allowlist **nem bővülhet**.
- A `visionPracticeIntegrationEnabled` flag OFF (E05-R03).

## 3. Scope

**Benne:** `VisionPracticeContract` (a vision oldal exportált, szűk API-ja),
`PracticeVisionAdapter` a Practice `data/` rétegében (a **fogyasztó** oldalon,
SDD §8 `lib/integrations/` helyett — ADR-döntés E05-R01 §5.7), a
`PracticeSessionResult` **additív, opcionális** vision-referenciája, három
pilot gyakorlat capability-gate-elve (**Small Strum Motion**, **Down/Up
Symmetry**, **Chord Change Economy** — a kör saját új fájljain belüli adat,
NEM `BuiltinPracticeCatalog`-bejegyzés, ld. §0.0/3), a session-summary
vision-dimenzió **önálló, nem bekötött widget** (`practice_vision_dimension.dart`
+ saját teszt — a `practice_result_screen.dart`-ba drótozás következő kör
dolga, ld. §0.0/6), és a degradált/hiányzó vision melletti audio-only
visszaesés.

**Kívül — TILOS:** az audio-pontozás bármely számítása, Speed Builder
vision-gate élesítése (flag mögött, de **default OFF** és nem e kör tárgya a
hangolása), Song Trainer (R26), Tutor (R27), persistence (R28).

## 4. Engedélyezett fájlok

| Útvonal | Állapot | Miért |
|---|---|---|
| `.../vision/domain/integration/vision_practice_contract.dart` | ÚJ | szűk vision API |
| `.../practice/data/vision/practice_vision_adapter.dart` | ÚJ | fogyasztó-oldali adapter |
| `.../practice/domain/model/practice_session_result.dart` | meglévő | **additív, opcionális** mező |
| `lib/features/practice/public.dart`, `lib/features/vision/public.dart` | meglévő | additív export |
| `.../practice/presentation/widgets/practice_vision_dimension.dart` | ÚJ | summary-dimenzió |
| `lib/l10n/app_*.arb` | meglévő | **csak additív** kulcs |
| `test/features/practice/*` | ÚJ | adapter + parity + widget |
| `docs/rounds/e05-r25-*.md` | meglévő | §10 handoff |

**Tilos zóna:** minden más practice-fájl; `lib/features/live/`; DSP;
`docs/rag`. Listán kívül → `stopped`.

## 5. Kötött architekturális döntések

1. **Az audio-pontozás nem változik.** A vision **külön dimenzió**, sosem
   módosítja az audio score-t. **NEM elfogadható:** kombinált „összpontszám",
   sem az audio score súlyozása vision-adattal.
2. **Vision nélkül nulla regresszió:** `visionPracticeIntegrationEnabled = false`
   vagy hiányzó kamera esetén a Practice viselkedése **bitre azonos** a maival.
   Ezt **parity-fixture** méri, nem szemrevételezés.
3. **A Practice nem ismeri a camera-implementációt** — csak a
   `VisionPracticeContract`-ot a `vision/public.dart`-on át. **NEM elfogadható:**
   `lib/features/vision/` belső import a practice-ből (az architektúra-őr
   allowlistje nem bővülhet).
4. **Rossz vision-quality → a gyakorlat audio-only módra vált**, a session
   megszakítása nélkül, és ezt a summary **jelzi** (nem tesz úgy, mintha
   megfigyelte volna).
5. **A pilot gyakorlatok capability-gate-eltek:** ha a szükséges capability
   hiányzik, a gyakorlat **elérhető marad** audio-only módban.
6. **A vision referencia opcionális, implicit-null mező** a resultban — a
   mai 12 hívóhely (1 production + 11 teszt) `vision` nélkül is fordul, és a
   `PracticeHistoryEntry`-perzisztencia (R28 dolga, `allowed_paths`-on
   kívül) e körben nem lát a mezőből semmit (ld. §0.0/1, ADR 0192 Döntés 2
   — **nem** klasszikus JSON deszerializáció, mert `PracticeSessionResult`-nak
   nincs saját kódja).
7. **A három pilot gyakorlat a kör saját új fájljain belüli adat, NEM
   `BuiltinPracticeCatalog`-bejegyzés** (az a fájl nincs `allowed_paths`-on).
   A `requiredCapabilities` a meglévő `FrettingCapability`/`PickingCapability`/
   `PostureCapability` enumokra épül. Ld. §0.0/3, ADR 0192 Döntés 4.
8. **A session-summary vision-dimenzió UI ebben a körben az izolált
   `practice_vision_dimension.dart` widget + saját widget-teszt** —
   `practice_result_screen.dart`-ba drótozás (a fájl nincs
   `allowed_paths`-on) egy következő kör dolga, ugyanaz a minta, mint az
   Epic 3 Song Trainer sorozatban. Ld. §0.0/6, ADR 0192 Döntés 7.

## 6. Acceptance criteria

- [ ] **Audio-parity fixture (a kör kulcsbizonyítéka):** rögzített practice
      session bemenet → az audio score, a metrikák és a history-bejegyzés
      **bitre azonos** vision ON és OFF mellett is. A teszt a teljes result
      szerializált alakját hasonlítja (a vision mezőt kivéve).
- [ ] **Vision-állapot mátrix:** `unavailable / degraded / good` —
      determinisztikusan a `VisionQualitySummary.overall`-ból származtatva
      (`good→good`, `needsImprovement→degraded`, `notObservable`/nincs
      session `→unavailable`; ld. §0.0/4, ADR 0192 Döntés 5) — mindhárom
      cellában a gyakorlat **befejezhető**, az audio score azonos, és a summary
      vision-dimenziója rendre: nincs / részleges + magyarázat / teljes.
- [ ] **Capability-gate teszt** a három pilot gyakorlatra: hiányzó capability →
      audio-only, de **nem** letiltott gyakorlat.
- [ ] **Visszamenőleges API-kompatibilitás (revideálva, ld. §0.0/1, ADR 0192
      Döntés 2 — `PracticeSessionResult`-nak nincs saját JSON-kódja, tehát
      klasszikus deszerializációs teszt nem építhető):** (a) mind a 12 meglévő
      `PracticeSessionResult(…)` hívóhely `vision` paraméter nélkül is fordul;
      (b) `vision: null` mellett a bővített `operator==`/`hashCode` nem tér el
      a mai szemantikától (egyenlőség-regresszió); (c) az első cella
      (audio-parity fixture) igazolja, hogy `PracticeSessionResultHistoryMapper.toHistoryEntry()`
      kimenete a `vision` értékétől függetlenül bitre azonos.
- [ ] **Architektúra-őr:** `test/core/architecture_dependency_test.dart` zöld,
      az allowlist **nem bővült** (a diff ezt mutatja).
- [ ] **Lokalizációs paritás** zöld.
- [ ] **Valódi-sértés próba (§10):** az audio score megszorzása egy
      vision-tényezővel → az audio-parity fixture PIROS → visszaállítás.

## 7. Kötelező ellenőrzések

```bash
tools/round-gate.sh test/features/practice test/features/vision
```

Külön processzek, nincs `&&`/pipe/`tail`. A valós eszközös pilot-gyakorlat a
device-mátrix **PENDING** sora.

## 8. Implementációs sorrend

1. RED: audio-parity fixture (ez a mérce) + vision-állapot mátrix.
2. `VisionPracticeContract` + adapter.
3. Result additív mező (`vision`) + `operator==`/`hashCode` bővítés — **nincs
   új kódolás/szerializáció** (ld. §0.0/1).
4. Pilot gyakorlatok + summary-dimenzió + ARB; gate.

## 9. Kockázatok

- **A result-modell bővítése** sok hívóhelyet érint (a pre-flight `rg`
  számolása kötelező); ha meglévő teszt elbukik → **megállás és jelentés**.
- **A „kombinált pontszám" kísértése** — a §5.1 tiltása és a parity-fixture
  az egyetlen őr.

**STOP:** audio-score módosítás, belső vision-import vagy allowlist-bővítés
helyett dokumentált brief-revízió.

## 10. Implementation handoff — az implementer tölti ki

### Implementáció

- `lib/features/vision/domain/integration/vision_practice_contract.dart` —
  `VisionPracticeContract` és a három, `vision.pilot.*` azonosítójú pilot;
  a `requiredCapabilities` pontos alakja `VisionPracticeCapabilities`, amely
  külön `Set<FrettingCapability>`, `Set<PickingCapability>` és
  `Set<PostureCapability>` mezőkben tartja meg a meglévő Vision-enumokat.
  A `VisionPracticeContracts.pilots` nem érinti a `BuiltinPracticeCatalog`-ot.
- `lib/features/practice/data/vision/practice_vision_adapter.dart` — a
  capability-hiány mindig elérhető, `audioOnly` gyakorlatot ad; egyébként a
  `visionPracticeQualityFor(session)` eredményét használja, és csak `good`
  állapotban választ `audioAndVision` módot.
- `lib/features/practice/domain/model/practice_session_result.dart` —
  additív, implicit-null `VisionSessionResult? vision` mező; az
  `operator==` és a `hashCode` a meglévő Vision-session identitás-szemantikát
  delegálja. Audio mező vagy történeti mapper nem változott.
- `lib/features/practice/presentation/widgets/practice_vision_dimension.dart`
  — önálló summary-widget: `unavailable` esetén nincs dimenzió,
  `degraded` részleges megfigyelés + kamera-igazítási magyarázat, `good`
  teljes megfigyelés. A `practice_result_screen.dart` érintetlen.
- `lib/features/practice/public.dart`, `lib/features/vision/public.dart` és
  az angol/magyar ARB-k — kizárólag additív exportok és lokalizált szövegek.
- A három új teszt a determinisztikus `VisionQualitySummary.overall`
  leképezést, a capability-gate audio-only fallbackjét, a null-vision
  egyenlőségi kompatibilitását, a history-mapper/audio-paritást és a widget
  három állapotát fedi le.

### Valódi-sértés próba

„a doubled `scorePoints` próba helyesen pirosra fordította a parity fixture-t,
majd visszaálltál”

### Futtatott ellenőrzések

- `git status --short` — pontosan a folytatási promptban felsorolt 11
  engedélyezett módosítás; listán kívüli fájl nincs.
- `git diff --check` — kilépési kód 0, kimenet nélkül.
- `tools/round-gate.sh test/features/practice test/features/vision` — első
  futás: a `format` zöld, az `analyze` 2 unused-import figyelmeztetéssel
  piros volt; a scope-on belüli importok eltávolítása után a teljes gate újra
  futott és kilépési kód 0-val zárult:
  - `format`: `Formatted 1178 files (0 changed)`;
  - `analyze`: `No issues found!`;
  - `test test/features/practice`: `All tests passed!`;
  - `test test/features/vision`: `All tests passed!`;
  - `architecture`: `Architecture dependencies OK (12 allowlisted deviation(s)).`;
  - `secrets`: `Secret scan OK (2024 file(s) scanned, 0 finding(s)).`;
  - `l10n`: `L10n parity OK (en → hu, 1001 message(s)).`.

### Eltérés a brieftől

Nincs tartalmi eltérés. A két nem használt import eltávolítása a gate által
jelzett, scope-on belüli statikus ellenőrzési javítás volt.

## 11. Review — a független reviewer tölti ki

Tervezett review: `docs/reviews/e05-r25-practice-vision-integration-review.md`.
Merge csak exact-SHA zöld CI, §4-en belüli diff és nulla OPEN BLOCKER/MAJOR után.
