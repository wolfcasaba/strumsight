# ADR 0492 — A capability-rollout döntés BIZONYÍTÉKHOZ kötött, a nem-production alapértelmezés a döntés hordozója, és a GA-besorolás forrása változatlanul a `ga-scope.md`

- **Státusz:** elfogadva (2026-09-03)
- **Kontextus:** ADR 0197 (a rollout-határ áthelyezése és a belépési pont mint a
  rollout része), ADR 0065 (Practice V2 párhuzamos rollout availability-flagek
  mögött), ADR 0220 (Audio Analysis V1/V2 rollout-határ, a kilenc Epic 6 flag
  OFF), ADR 0491 D2 (a Practice Generator `nonProd` rollout-határa),
  ADR 0489 (GA-scope besorolás és contract-freeze), ADR 0446 (flag-katalógus és
  vész-kikapcsoló), ADR 0467 D9 (a zsugorodás-őr elve), `docs/LESSONS.md`
  [L534](../LESSONS.md#l534) (egy globális flag-alapértelmezés átbillentése a
  TESZT-alapértelmezést is átbillenti), kör `E16-R03`
- **Döntéshozó:** Claude (Sonnet 5) orchestrátor, az E16-R03 pre-flight mérése
  alapján
- **Megjegyzés a számozásról:** a `docs/execution/pipeline-queue.tsv` E16-R03
  sora `0492`-t hordoz. A szám MÉRTEN szabad: nincs a lemezen
  (`docs/adr/` a `0491` után a `0494`-gyel folytatódik), nincs egyetlen ág
  ADR-fájljában sem (`tools/round-slots.py` `branch_adr_numbers` → `492 ∉`), és
  nem volt foglalási markere. Az ADR ezen a számon él, `O_EXCL` markerrel
  (`.pipeline/inflight/adr/0492` → `round=E16-R03`). A
  `tools/round-slots.py reserve-adr` a `0503`-at adta ki, mert a foglaló
  `max(used) + 1`-et számol és RÉSEKET SOSEM tölt ki — a `0503` markert ezért
  felszabadítottam, nehogy egy soha ki nem írt szám tartósan foglalt maradjon.
  (Az E16-R02 esete NEM ez volt: ott a brief `0491`-e valóban merge-elve a
  lemezen élt, ezért kellett a foglaló száma — ADR 0500 fejléc.)

## Kontextus — a mért állapot

Az E16-R03 pre-flightja a `main @ d7014b9d` fán a következőket **mérte** (a
mérés a `tool/release/verify_ga_scope.py` SAJÁT, fail-closed
`forEnvironment`-olvasójával futott, nem szemre):

| Mért parancs | Eredmény |
|---|---|
| `_extract_for_environment_field_assignments(feature_flags.dart)` | **40** mező |
| ebből `nonProd` | **8**: `diagnosticsEnabled`, `labModeAvailable`, `practiceEngineV2Enabled`, `migratedLearnEnabled`, `practiceDetailedHistoryEnabled`, `songTrainerV2Enabled`, **`practiceGeneratorEnabled`**, `adaptiveShellEnabled` |
| ebből `false` minden környezetben | **26** (tutor 2 + `plannerAssistEnabled` + vision **11** + analysis **9** + recognition 3) |
| ebből `const bool.fromEnvironment(...)` | **5** community flag |
| ebből hívó-adta átmenő érték | **1** (`accountEnabled`) |
| `ls docs/release/` | `ga-scope.md` és `rollout-decision.md` MÁR LÉTEZIK; `capability-rollout.md` nem |
| `grep -n "forEnvironment" tool/release/verify_ga_scope.py` | a `ga-scope.md` `production_default` oszlopát a tool a `feature_flags.dart`-ból **méri**, fail-closed parserrel |
| `grep -rln "forEnvironment" test/` | **24** tesztfájl hivatkozik rá közvetlenül |

**A brief eredeti §2-je három ponton MÉRTEN téves volt** (a §0.0 revízió
javítja): a `practiceGeneratorEnabled` nem „KI", hanem `nonProd` (ADR 0491 D2,
E15-R07 óta); a vision flagek száma 11, nem 10; az analysis flageké 9, nem 10.

## Döntés

### D1 — A „BE" besorolás BIZONYÍTÉKHOZ kötött, nem készültség-érzethez

Egy capability csak akkor kap alapértelmezett `nonProd` értéket, ha mind a négy
kritérium — (a) migrált és elérhető felület, (b) valós adatot adó kompozíciós
réteg, (c) zöld saját mérce-sáv, (d) nem igényel a felhasználónál hiányzó külső
erőforrást — a döntési táblában **fán feloldható hivatkozással** szerepel.

**NEM elfogadható gyengítés:** „elkészült, tehát menjen". Az Epic 6 saját
zárójelentése nyitott release-blokkolót rögzít (ADR 0220 Következmények), az
Epic 5 vision-sávja pedig kamerát igényel — mindkettő (d) vagy (c) alapján bukik.

### D2 — Két dokumentum, két hatókör: a `capability-rollout.md` a NEM-PRODUCTION döntés, a GA-besorolás marad a `ga-scope.md`

A kör új dokumentuma a **nem-production** (development/lab) alapértelmezésekről
dönt. A GA/production besorolás egyetlen normatív forrása változatlanul a
`docs/release/ga-scope.md` (ADR 0489, zárt `ga|preview|disabled|postponed`
készlet, 16 flag-kulcs, géppel visszaellenőrzött `production_default` oszlop).

Ebből két kötelezettség következik:

1. a `capability-rollout.md` a production alapértelmezésről **nem tesz saját
   állítást** — arra hivatkozik (`ga-scope.md`), különben két igazságforrás
   keletkezne ugyanarra a mezőre;
2. a dokumentum nevében és fejlécében ki kell mondani, hogy ez **nem** a
   `docs/release/rollout-decision.md` (E12-R32, staged százalékos rollout-csomag,
   `tool/release/verify_rollout_decision.py` őrzi) — a két fájl neve hasonló, a
   tárgyuk nem.

### D3 — A `forEnvironment` visszatérési törzse a NÉGY gépileg felismert alak egyikét tartja

A `tool/release/verify_ga_scope.py` fail-closed parsere pontosan ezeket ismeri:
`nonProd` · `true` · `false` · `const bool.fromEnvironment(...)` · a mező saját
nevével azonos átmenő érték. **Bármi más — például
`environment == AppEnvironment.lab` vagy `nonProd && x` — `VerifyError`**, ami a
`test/tooling/ga_scope_test.dart`-ot pirosra viszi. Az a fájl a kör
`allowed_paths`-án KÍVÜL van, tehát egy ilyen alak H3-at csinálna egy egyébként
helyes döntésből.

**Következmény:** ha egy capability rollout-döntése nem fejezhető ki ezzel a négy
alakkal (pl. „csak lab-ben"), az a döntés ebben a körben **PREVIEW**, és a
feloldó kör nevesítve kerül a táblába — nem a parser alakját tágítjuk.

### D4 — Flip ELŐTT hatósugár-mérés; a lista tágítása helyett `stopped`

Az `appConfigProvider` alapértéke maga
`FeatureFlags.forEnvironment(AppEnvironment.development, …)`, ezért egy
`false → nonProd` flip minden olyan widget-teszt konfigurációját elmozdítja,
amely a valódi `StrumSightApp`-ot pumpálja (L534: egyetlen sor **53 bukást**
okozott **19 fájlban**, és az E15-R02 emiatt H3-mal állt meg
implementer-dispatch NÉLKÜL).

Ezért minden tervezett flip előtt kötelező a hatósugár mérése (flip + teljes
suite, majd ugyanaz flip nélkül; a KÜLÖNBSÉG az oksági hatás). Ha a különbség a
kör `allowed_paths`-án kívüli fájlt tesz pirosra, a kimenet a **`stopped`
jelzés** — nem a lista tágítása (ADR 0087 §2 H3), és nem is
`appConfigProvider`-override-dal elrejtett alapértelmezés (ADR 0467 D9: az
elrejtett alapértelmezés kivonja magát a mérce alól).

### D5 — Külső erőforrást igénylő capability PREVIEW marad

Backendet, API-kulcsot, kamerát vagy letöltendő modellt igénylő ág nem lehet
alapértelmezés, amíg az erőforrás nincs a felhasználónál. **NEM elfogadható
gyengítés:** bekapcsolás „úgyis hibaállapotot mutat" indoklással — az hibás
alapélményt szállít.

### D6 — A core offline út sérthetetlen

A `test/e2e/first_practice_offline_test.dart` útja a rollout után is végigjárható
hálózat nélkül, és a network guard nem trippelhet. **NEM elfogadható gyengítés:**
a core út feltételessé tétele bármely új capabilityre.

### D7 — Minden nem-„BE" besorolás NEVESÍTI a feloldó feltételt

„Később" önmagában nem besorolás. Minden PREVIEW/KI sor vagy egy kört
(`EXX-RYY`), vagy egy nevesített, fán feloldható blokkolót hordoz — ez teszi a
táblát a következő körök bemenetévé ahelyett, hogy szándéknyilatkozat maradna.

### D8 — A production alapértelmezés ebben a körben VÁLTOZATLAN

A GA-scope döntés a Chapter 12 Kör 28 hatásköre (ADR 0489). A kör egyetlen
production alapértelmezést sem mozdít; ezt a `feature_flags_test.dart`
production-cellái és — függetlenül, gépileg — a `ga-scope.md`
`production_default` oszlopát visszamérő `verify_ga_scope.py` együtt őrzi.

## Következmények

- A `capability-rollout.md` a következő körök (E16-R04, E16-R05) bemenete: a
  PREVIEW sorok feloldó körei onnan olvashatók ki.
- A kör `gate_tests` listája a pre-flightban BŐVÜLT (szigorítás, nem tágítás) a
  `ga_scope_test.dart`, az `analysis_rollout_flags_test.dart` és az
  `app_config_test.dart` őrökkel — ezek mérik gépileg a D3, D8 és D4
  kikötéseket a célzott kapun, nem csak a teljes CI-ban.
- Az ADR nem módosít egyetlen merge-elt döntést sem: az ADR 0220, ADR 0395,
  ADR 0489 és ADR 0491 kikötései változatlanul érvényesek, ez az ADR a rájuk
  épülő **rollout-eljárást** rögzíti.
