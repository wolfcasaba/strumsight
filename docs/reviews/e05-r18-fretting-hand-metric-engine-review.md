# E05-R18 — Review

Brief: `docs/rounds/e05-r18-fretting-hand-metric-engine.md`
Diff: `git diff origin/main...116b63e` (branch `minimax/e05-r18-fretting-hand-metric-engine`, workspace `/home/ubuntu/ss-mm-e05-r18`, review klón `/tmp/review-e05-r18`)
Reviewer: Claude Sonnet 5 (orchestrátor) · Dátum: 2026-08-08
Verdikt: **CHANGES REQUESTED**

## Összegzés

BLOCKER: 1 · MAJOR: 3 · MINOR: 3 · NOTE: 1

A gate a saját, izolált `/tmp/review-e05-r18` klónban (GitHubról fetch-elve —
lásd a §„Klón-forrás" megjegyzést) függetlenül újrafuttatva **6/6 zöld**
(`tools/round-gate.sh test/features/vision`, 208/208 teszt), a scope-audit
(`tools/scope-audit.py`) a 9 változott útvonalra **OK**. A gate zöldsége
azonban **nem terjed ki a tartalmi hűségre**: a hat metrika közül az egyik
(`readyPositionTime`) két, egymástól független, empirikusan bizonyított
hibát tartalmaz — az egyik a kör két legkötöttebb architekturális szabályát
(§5.3, §5.5) sérti meg csendben (BLOCKER), a másik a metrika saját,
SDD-definiált jelentését számítja rosszul (MAJOR). Emellett a brief §6 három
tételes acceptance-pontjához (típus/határ/degenerált eset metrikánként,
mirror/left-handed paritás, valódi-sértés próba) **nincs bizonyíték** a
szállított diffben.

## Klón-forrás — mért csapda a review-oldalon

Az első review-klónomat a helyi, megosztott `/home/ubuntu/music-theory`
fáról készítettem (`git clone --branch ... /home/ubuntu/music-theory ...`) —
ennek a lokális branch-referenciája a pre-flight commitnál (`23cc248`)
ÁLLT, mert az implementer a saját, különálló munkapéldányából
(`/home/ubuntu/ss-mm-e05-r18`) közvetlenül a GitHub originre pusholt, a
megosztott fa lokális branch-mutatóját senki nem frissítette. Az első
gate-futás emiatt a metrika-fájlok NÉLKÜL futott (199 teszt, nem 208) —
véletlenül is zöld volt, mert a hiányzó fájlok miatt a gate egyszerűen nem
látta az új teszteket. Újra-klónoztam közvetlenül
`https://github.com/wolfcasaba/strumsight.git`-ról (a `HEAD`
`116b63e`-re állt) — ez a review innentől erre az, a CI által is látott,
hiteles állapotra vonatkozik.

## Acceptance criteria

| # | Kritérium | Teljesült | Bizonyíték |
|---|---|---|---|
| 1 | Metrikánként külön unit teszt (6 metrika), mindegyikhez tipikus/határ/degenerált eset | ❌ | `fretting_metric_engine_test.dart` 7 tesztje metrikánként **egyetlen tipikus esetet** ad; nincs dedikált határ-/degenerált-eset teszt egyik metrikára sem (a megosztott visibility/lost/role tesztek nem metrika-specifikusak). Ld. F3 MAJOR. |
| 2 | Visibility-mátrix metrikánként (alatt/rajta/fölött) | ⚠️ Részleges | Az „alatt" cella egyetlen metrikára (`fingerSpreadProxy`) tesztelt (`fretting_metric_engine_test.dart:76-80`) — a másik öt metrikára nincs. `readyPositionTime`-ra a gate MAGA a kapu hiányzik (F1 BLOCKER), tehát ott az „alatt" cella a valóságban **nem is létezik**. |
| 3 | Katalógus-teszt (minden definíció teljes szerződéssel) | ✅ | `metric_definition_test.dart:6-13`, `FrettingMetrics.isValid` valódi (nem csak `assert`) futásidejű ellenőrzés — ld. F6 MINOR a konstruktor-szintű assert-only résről. |
| 4 | Mirror / left-handed paritás (4 cella) | ❌ | Nincs egyetlen teszt sem, ami `leftHanded`/kamera-irányt variál. Ld. F4 MAJOR. |
| 5 | `lost`-geometria teszt (hívásszámláló: a számítás nem fut le) | ✅ | `fretting_metric_engine_test.dart:82-88` + kódolvasás (`fretting_metric_engine.dart:73,92,116,200`): mind a négy gitárrelatív metrika a **legelső sorban** tér vissza `notObservable`-lel `geometryLost=true`-ra, számítás előtt. |
| 6 | NaN/Infinity guard a teljes fixture-mátrixon | ⚠️ Részleges | Szerkezetileg garantált (minden metrika `_valueWithConfidence` → `MetricObservation.observable` — `metric_observation.dart:17-19` — feltétel nélkül `notObservable`-re vált nem-véges értékre), de ez EGYETLEN, megosztott tesztponton (`metric_definition_test.dart:15-23`) igazolt, nem metrikánként — a brief „teljes fixture-mátrixon" kitétele nem teljesül szó szerint. |
| 7 | Valódi-sértés próba (§10): visibility-kapu kiiktatása → PIROS → visszaállítás | ❌ | A §10 handoff nem dokumentál ilyen próbát. A reviewer saját, eldobható mutációval (lásd lent) igazolta, hogy a kapu VALÓBAN load-bearing — de ez a review pótolta, nem az implementer. Ld. F5 MAJOR. |

## Scope-audit

```
$ python3 tools/scope-audit.py --repo /tmp/review-e05-r18 \
    --brief docs/rounds/e05-r18-fretting-hand-metric-engine.md --base origin/main
Legacy scope audit OK (origin/main..116b63ef9330, 9 changed path(s), 0 generated/ignored)
```

A 9 fájl mind a brief §4 listáján van (4 új domain fájl, `public.dart`
additív export, 2 új teszt-fájl, 1 fixture, a round-brief §10 önmaga).
Egyezik az implementer saját `scope_audit=ok` jelzésével.

## Megállapítások

### F1 — BLOCKER — `readyPositionTime` megkerüli a szerep- és visibility-kaput

- **Fájl:** `lib/features/vision/domain/metrics/fretting_metric_engine.dart:86-110`
- **Probléma:** a másik öt metrika mindegyike a `_usable()` helperen
  (`fretting_metric_engine.dart:217-223`) keresztül szűr — ez a helper
  egyszerre érvényesíti a `role == HandRole.fretting` (§5.5) ÉS a
  `minimumVisibility` (§5.3) kaput. A `readyPositionTime` (86-110. sor)
  **nem hívja a `_usable()`-t**: a `before` lista (95-98. sor) kizárólag
  `timestamp <= target.timestamp` alapján szűr, majd a 99-108. sorban
  MINDEN ilyen mintát megvizsgál a pozíció-közelségre, szerepre és
  visibility-re tekintet nélkül.
- **Hatás (empirikusan bizonyítva, eldobható próbateszttel — lásd lent):**
  (a) egy KIZÁRÓLAG `HandRole.picking` (pengető kéz) mintából álló bemenet
  `observable` értéket ad; (b) egy KIZÁRÓLAG `visibility=0.10` (a metrika
  0.65-ös küszöbe alatt) mintából álló bemenet szintén `observable` értéket
  ad. Mindkettő pontosan az a viselkedés, amit a brief §5.3/§5.5 és a §9
  „STOP: … a visibility-kapu lazítása helyett dokumentált brief-revízió"
  mondata kifejezetten tilt.
- **Kötelező javítás:** a `before` listát a többi metrikához hasonlóan
  `_usable(samples.where((s) => s.timestamp <= target.timestamp), id)`-n
  (vagy ezzel ekvivalens, `_usable()`-t ténylegesen meghívó) úton kell
  előállítani, mielőtt a pozíció-közelség vizsgálat lefut.
- **Ellenőrzés:** a mellékelt próbateszt (lásd „Próbatesztek" szakasz) mindkét
  esetben `notObservable`-t kell adjon javítás után; vegyél fel ERRE a két
  esetre (picking-only, low-visibility-only) állandó regressziós tesztet a
  szállított `fretting_metric_engine_test.dart`-ba.
- **Státusz:** OPEN

### F2 — MAJOR — `readyPositionTime` a minta-rés hosszát méri, nem a valódi „ready" időt

- **Fájl:** `lib/features/vision/domain/metrics/fretting_metric_engine.dart:99-108`
- **Probléma:** a ciklus `before.reversed`-en fut (legkésőbbitől a
  legkorábbi felé) és az ELSŐ (azaz a targethez legközelebbi) illeszkedő
  mintánál azonnal visszatér. Ha a kéz TÖBB egymást követő mintán át a
  zónában marad a target előtt (a valós, tipikus eset — nem egyetlen
  pillanatra ér oda), a visszaadott érték `target.timestamp − (legutolsó
  minta időbélyege)` — vagyis nagyjából a mintavételi köz —, NEM
  `target.timestamp − (a zónába ÉRKEZÉS időbélyege)`. Az SDD §19.1 szó
  szerinti definíciója („Az audio target esemény előtt **mennyi idővel
  kerül** a kéz a következő stabil zónába") az érkezési időt kéri.
- **Hatás (empirikusan bizonyítva):** egy 4 mintás fixture-rel — kéz a
  zónán kívül t=0-nál, a zónába ér t=100ms-nél és OTT MARAD t=300ms-ig,
  target t=500ms-nél — a helyes „ready idő" 500−100=**400 000 µs**, a kód
  **200 000 µs**-t ad (a t=300ms-es utolsó minta és a target közti rés).
  A meglévő szállított teszt (`fretting_metric_engine_test.dart:65-74`)
  ezt nem kapja el, mert ott KIZÁRÓLAG egyetlen minta esik a zónába — egy
  egymintás bemeneten „legutolsó illeszkedő minta" és „érkezési idő"
  matematikailag egybeesik, tehát a teszt nem tudja megkülönböztetni a két
  algoritmust.
- **Kötelező javítás:** a ciklusnak a legkésőbbi zónán-belüli mintától
  VISSZAFELÉ kell folytatódnia, amíg a minták FOLYAMATOSAN a zónában
  maradnak, és a folytonos szakasz ELSŐ (legkorábbi) mintáját kell
  visszaadnia — nem az elsőt, ami illeszkedik.
- **Ellenőrzés:** a mellékelt próbateszt (400 000 µs elvárt) javítás után
  zöld; vedd fel állandó regressziós tesztként.
- **Státusz:** OPEN

### F3 — MAJOR — hiányzó metrikánkénti típus/határ/degenerált teszt-mátrix

- **Fájl:** `test/features/vision/domain/fretting_metric_engine_test.dart` (egésze)
- **Probléma:** a brief §6 első pontja kifejezetten „**Metrikánként külön**
  unit teszt (6 metrika), mindegyikhez **legalább**: tipikus eset · határeset
  · degenerált eset"-et ír elő — azaz minimum 18 esetet. A szállított fájl
  7 tesztet tartalmaz, ebből metrikánként pontosan EGY „tipikus" eset; nincs
  metrika-specifikus határeset (pl. a visibility pontosan a küszöbön) vagy
  geometriai degenerált eset (pl. egybeeső wrist/middleMcp pont a
  `wristDeviationProxy`-nál, egyetlen mintás `chordChangeTravel`/
  `positionStability` bemenet stb.) egyik metrikára sem.
- **Hatás:** a §6 acceptance-pont formálisan nyitva marad; a hiányzó
  degenerált-eset lefedettség pontosan az a hézagosztály, ami F1/F2-t
  átengedte zölden.
- **Kötelező javítás:** metrikánként legalább egy határeset (a definíció
  `minimumVisibility`-jén PONTOSAN) és egy geometriai degenerált eset
  (egybeeső pontok / 0-1 elemű bemenet) — mind `notObservable`-t vagy
  véges, dokumentált eredményt várva.
- **Ellenőrzés:** a bővített teszt-fájl futása; a `round-gate.sh` marad
  a záró artefaktum.
- **Státusz:** OPEN

### F4 — MAJOR — hiányzó mirror/left-handed paritás teszt

- **Fájl:** `test/features/vision/domain/fretting_metric_engine_test.dart` (hiányzik)
- **Probléma:** a brief §6 negyedik pontja explicit 4 cellás
  (`leftHanded` be/ki × front/back kamera) paritás-tesztet ír elő —
  „azonos fizikai mozgásra azonos metrikaérték". A szállított tesztkészlet
  ezt egyáltalán nem érinti.
- **Hatás:** a `FrettingMetricEngine` API-ja maga nem is fogad
  `leftHanded`/kamera-irány paramétert — algebrailag valószínűsíthető
  (a szögszámítás és a távolságszámítás tükrözés-invariáns, a guitar-space
  `(u,v)` pedig az R15 §5.5 szerint már tükrözés-mentes), de a brief
  „jól működik" alapon ezt kifejezetten NEM fogadja el bizonyítéknak —
  ez egy explicit, kipipálandó acceptance-cella, dokumentált teszt nélkül.
- **Kötelező javítás:** egy teszt, ami ugyanazt a fizikai kéz-trajektóriát
  (1) balkezes+front, (2) balkezes+back, (3) jobbkezes+front, (4)
  jobbkezes+back beállítás mellett szimulálja (a `role`/`(u,v)` már
  R13/R15-ben normalizált bemenetként) és igazolja, hogy mind a hat metrika
  kimenete azonos (toleranciával).
- **Ellenőrzés:** az új teszt futása.
- **Státusz:** OPEN

### F5 — MAJOR — elmaradt valódi-sértés próba a §10 handoffban

- **Fájl:** `docs/rounds/e05-r18-fretting-hand-metric-engine.md` §10
- **Probléma:** a brief §6 utolsó pontja kötelezővé teszi: „a minimum
  visibility ellenőrzés kiiktatása → a visibility-mátrix „alatt" cellája
  PIROS → visszaállítás", dokumentálva. A szállított §10 handoff ezt nem
  tartalmazza (sem magát a próbát, sem az eredményét).
- **Hatás:** a review-nak kellett pótolnia (lásd „Próbatesztek" szakasz) —
  ez pontosan az a fajta „a gate zöld, de a garancia bizonyítatlan" eset,
  amit ez az acceptance-pont ki akar zárni.
- **Kötelező javítás:** a §10-be kerüljön be a mutáció (fájl:sor, mit
  változtattál) + a bukott teszt neve + a visszaállítás ténye.
- **Ellenőrzés:** a review reprodukálta (lásd lent) — a javító körnek csak
  dokumentálnia kell, nem újra elvégeznie.
- **Státusz:** OPEN

### F6 — MINOR — `MetricDefinition` konstruktor csak `assert`-tel validál

- **Fájl:** `lib/features/vision/domain/metrics/metric_definition.dart:23-25`
- **Probléma:** a három invariáns (`minimumVisibility ∈ [0,1]`,
  `window > 0`, `confidenceFormula` nem üres) kizárólag `assert`-ben él —
  ez release buildben stripped (pontosan az a hibaosztály, amit az R16
  fix-round F2 MINOR-ja `GeometryConfidence`-nál `assert`→`throw`-ra
  javított, `geometry_confidence.dart:70-76` doc-kommentje szerint).
- **Hatás:** alacsony — a `frettingMetricDefinitions` lista compile-time
  fixált literál (`fretting_metric_engine.dart:252-274`), nem futásidejű
  bemenetből épül, ÉS van egy különálló, valódi (nem assert) `isValid`
  getter, amit a katalógus-teszt ténylegesen meghív
  (`metric_definition_test.dart:8-9`) — tehát a gyakorlati kockázat
  alacsony, de a minta inkonzisztens a kódbázis saját, dokumentált
  precedensével.
- **Kötelező javítás (opcionális ebben a körben, ajánlott):** a konstruktor
  `assert`-jei mellé/helyett feltétel nélküli `throw ArgumentError`, VAGY
  a `frettingMetricDefinitions`-t magát fedje egy `assert(FrettingMetrics.isValid)`
  a modul betöltésekor.
- **Státusz:** OPEN (nem blokkolja a merge-et, ha a javító kör más okból
  úgyis módosítja a fájlt — akkor vigye magával).

### F7 — MINOR — `_confidence()` más mintahalmazon fut, mint a `_points()`

- **Fájl:** `lib/features/vision/domain/metrics/fretting_metric_engine.dart:82,105,130,205`
- **Probléma:** `chordChangeTravel`/`readyPositionTime`/`positionStability`/
  `handToNeckDistance` mindegyike a **szűretlen** `samples`/`input`/`before`
  paramétert adja át a `_confidence()`-nek, miközben az érték maga a
  `_usable()`-lel **szűrt** ponthalmazból számol. A dokumentált
  `confidenceFormula` („mean(minimum landmark confidence)") ezt a
  hatókör-eltérést nem jelzi.
- **Hatás:** a jelentett confidence a ténylegesnél ALACSONYABB lehet (a
  kiszűrt, alacsony-visibility minták is belekerülnek az átlagba) — ez a
  biztonságos irányba téved (nem túlbecsül), tehát nem sérti a §5 alapelvet,
  de pontatlan és a dokumentált formulának nem felel meg szó szerint.
- **Kötelező javítás (opcionális):** `_confidence()` a `_usable()`-lel már
  szűrt mintahalmazt kapja mindenhol, ne az eredetit.
- **Státusz:** OPEN (MINOR — nem blokkol, follow-up is elfogadható).

### N1 — NOTE — használaton kívüli fixture + duplikált §10 fejléc

- **Fájl:** `test/fixtures/vision/fretting/proxy_paths.json`;
  `docs/rounds/e05-r18-fretting-hand-metric-engine.md:212-214`
- **Probléma:** a `proxy_paths.json` fixture-t egyetlen teszt sem tölti be
  (`grep -rn proxy_paths test lib` nulla találat) — a brief §8 1. lépése
  („Fixture-készlet … + RED mátrixok") és §9 kockázata („minden metrikához
  kell legalább egy zajos fixture is") szerint a fixture-nek ténylegesen a
  teszteket kellene hajtania, nem árva JSON-ként léteznie. A round-brief
  §10 szakasza emellett duplán tartalmazza a „## 10. Implementation
  handoff" fejlécet (212. és 214. sor).
- **Hatás:** nincs futásidejű hatás, kizárólag karbantarthatósági/
  dokumentációs pontosság.
- **Státusz:** OPEN (nem blokkol; a javító kör érintheti, ha kényelmes).

## Próbatesztek (eldobhatók, ebben a review-ban futtatva, a merge előtt törölve)

Mindhárom a `/tmp/review-e05-r18` klónban futott, a szállított kódon
(mutáció nélkül, kivéve ahol jelezve), majd törölve/visszaállítva:

1. **F1 bizonyítása** —
   `test/features/vision/domain/_probe_ready_position_gate_test.dart`
   (ideiglenes): egy KIZÁRÓLAG `HandRole.picking` mintából álló és egy
   KIZÁRÓLAG `visibility=0.10` mintából álló bemenet is `observable`-t adott
   `readyPositionTime`-ra — mindkettőnek `notObservable`-nek kellene lennie.
2. **F2 bizonyítása** —
   `test/features/vision/domain/_probe_ready_position_test.dart`
   (ideiglenes): a 4 mintás dwell-fixture-ön a kód `200000.0`-t adott a
   helyes `400000.0` (valódi érkezési idő) helyett.
3. **Valódi-sértés próba (F5 pótlása)** — `fretting_metric_engine.dart:222`
   `.where((s) => _visibility(s, id) >= definitionFor(id).minimumVisibility)`
   sort ideiglenesen `.where((s) => true)`-ra cserélve: a
   `visibility below the metric threshold is not observable` teszt
   (`fretting_metric_engine_test.dart:76-80`) **PIROSRA** vált (`Expected:
   notObservable, Actual: observable`), a másik 6 teszt zöld marad; a fájl
   ezután byte-azonosra visszaállítva (`git diff` üres a próba után).

## Gate-bizonyíték ellenőrzése

| Gate | Állított eredmény (implementer) | Ellenőrizve (reviewer, `/tmp/review-e05-r18`, GitHub HEAD `116b63e`) |
|---|---|---|
| format | zöld | ✅ zöld (`Formatted 1130 files (0 changed)`) |
| analyze | zöld | ✅ zöld |
| test test/features/vision | zöld, 208 teszt | ✅ zöld, 208/208 („All tests passed!”) |
| architecture | zöld | ✅ zöld (12 allowlisted deviation) |
| secrets | zöld | ✅ zöld (0 finding) |
| l10n | zöld | ✅ zöld |
| CI (teljes suite + property + APK) | — | még nem dispatch-elve (javító kör előtt nem érdemes) |

A gate-bizonyíték hiteles — az implementer önjelentése és a független
újrafuttatás egyezik. A review BLOCKER/MAJOR leletei egyike sem a
gate-kimenetben látszik: mind tartalmi (a metrikák számítási helyessége),
amit csak célzott, eldobható próbateszt fog meg — pontosan az AGENTS.md
elve, amiért ez a review lépés kötelező.

## Merge-döntés

**Merge TILOS** (ADR 0052 + a fenti F1 BLOCKER, F2–F5 MAJOR). Javító kör
szükséges, ugyanazon a motoron (MiniMax, első javító kör — user-döntés
2026-08-01 küszöb). A javító kör után a gate-eket friss `/tmp` klónban újra
lefuttatom, és ezt a jelentést frissítem APPROVED-ra vagy ismételt CHANGES
REQUESTED-re.
