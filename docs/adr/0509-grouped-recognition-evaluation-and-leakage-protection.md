# ADR 0509 — Csoportosított felismerési kiértékelés: a leakage hiba, a párosítás maximális, a metrika a definíciójával utazik

- **Státusz:** Elfogadva
- **Kör:** `E14-R08` (Chapter 14 — Recognition Accuracy & Useful UI Recovery, Kör 8)
- **Dátum:** 2026-09-04
- **Implementer motor:** `sonnet-impl` (Claude Sonnet 5, `--effort high`)
- **Kapcsolódó:** [ADR 0249](0249-analysis-evaluation-dataset-governance.md)
  (a CI kis szintetikus fixture-ön fut, a valós korpusz külső és kézi;
  típusos parser-hiba minta), [ADR 0354](0354-recognition-baseline-manifest-and-evidence-index.md)
  (determinisztikus, bájtazonos mérési artefaktum),
  [ADR 0359](0359-recognition-annotation-contract-and-agreement.md)
  (az annotációs szerződés, amit ez a harness olvas; D6: a minta másolható, a
  kereszt-feature FÜGGÉS nem)

## Kontextus — a pre-flight MÉRT tényei (2026-09-04, `main @ 62e0dce6`)

- **Az előre kiosztott `0360` szám elavult.** A `docs/adr/0360-*.md` **nem
  létezik** (`ls docs/adr | grep ^0360` → nulla találat), a fán a legmagasabb
  szám `0505`, és a foglaló (`tools/round-slots.py reserve-adr --round E14-R08`)
  a **`0509`** számot adta. A brief 2026-08-20-i `0360` foglalása azóta
  tárgytalanná vált; a foglaló az O_CREAT|O_EXCL markerrel a lemezen lévő ÉS a
  már foglalt számok fölé megy, ezért ez a szám az érvényes (a `ls … | tail`
  alak kifejezetten tiltott sorszám-választásra).
- **A Dart-oldali felismerési split/leakage kód nem létezik.** A
  `lib/features/live/domain/evaluation/` ma egyetlen fájlt tart
  (`recognition_annotation.dart`, E14-R07), a `data/evaluation/` szintén egyet
  (`recognition_annotation_parser.dart`). Split, fold, leakage vagy
  felismerési metrika típus a fában **nincs**.
- **A `ml/honest_eval.py` a TANÍTÓ oldal saját mérése** (fejléc, 1–18. sor:
  three-way split, leave-one-guitarist-out CV, cluster-bootstrap CI,
  multi-seed sweep, kalibráció+ECE), és `ml/data/klangio` fölött, TensorFlow-val
  fut. Ez a kör a SZÁLLÍTOTT felismerési út Dart-oldali harness-ét építi, és a
  Python-oldalt **nem módosítja** — a két mérés nem ugyanaz a bemenet és nem
  ugyanaz a futtatókörnyezet.
- **A repó bevált harness-alakja mérhető:**
  `tool/audio_analysis_evaluate.dart` (fixture-default `--manifest`
  felülírással, `stdout`-ra determinisztikus JSON, `stderr` + nem nulla exit a
  hibáknak) és `lib/features/audio_analysis/**/evaluation/`. Ez a kör ugyanezt
  az alakot követi a felismerési oldalon.
- **A maximális párosítás már mért követelmény, nem ízlés.** Az
  `EvaluationRunner.matchEvents` (`…/data/evaluation/evaluation_runner.dart:227`)
  és az `AnnotationAgreementCalculator._matchEvents`
  (`…/domain/evaluation/recognition_annotation.dart:284`) egyaránt Kuhn-féle
  maximális párosítást futtat, mert az E06-R29 review két rövid ellenpéldával
  reprodukálta, hogy a mohó „legközelebbi szabad pár" NEM maximalizál
  (`docs/LESSONS.md` L269: várt `50, 90`, detektált `0, 55`, 50 ms tolerancia →
  mohó 1 TP, maximális 2 TP).
- **A kereszt-feature import szabálya gépi:** `tool/check_architecture.dart:774`
  („cross-feature imports must target public.dart"). A `live` feature nem
  importálhatja az `audio_analysis` evaluation kódját.
- **A `live` barrel nem generált:** `lib/features/live/public/` fragment-könyvtár
  nem létezik, a `public.dart` kézzel írott, ezért új `domain/`/`data/` fájl nem
  teszi elavulttá (ugyanaz a mérés, mint ADR 0359-ben; az E14-R07 merge-elt
  fájllistája ezt igazolja: 10 fájl, `public.dart` nem érintve).
- **Az `OnsetMetrics` név FOGLALT:** `tool/benchmarks/real_audio_dsp_baseline.dart:30`.
  A `RecognitionSplit*`, `SplitStrategy`, `LeakageDetector`, `LeakageViolation`,
  `RecognitionMetrics*`, `GroupKey`, `RecognitionCase` nevekre nulla találat.
- **Az ECE binelés meglévő mintája egyenlő SZÉLESSÉGŰ:**
  `CalibrationFitter` (`…/data/evaluation/calibration_fitter.dart:132-141`)
  `lowerBound: i / binCount`, `upperBound: (i + 1) / binCount`, a bin
  `[lower, upper)` félig nyitott, az utolsó zárt.

## Döntés

### D1 — A leakage-detektor fail-closed

Ha ugyanaz a csoportkulcs (player/device/guitar/room) egy split két
különböző foldjában is előfordul — azaz a tanító és a kiértékelő oldal
ugyanazt a játékost, telefont, gitárt vagy szobát látja —, a futtató **típusos
hibát dob és megáll**. Nem figyelmeztet, nem javít, nem dob el csendben
duplikált csoportot. A hibaüzenet **megnevezi az ütköző csoportkulcsot** és a
két érintett foldot.

Elutasítva: „warning + folytatás" (a szivárgott mérés optimista számot ad, és a
figyelmeztetés a log-zajban elvész), valamint a duplikált csoport néma
eldobása (a foldok uniója így már nem a teljes halmaz, amit senki nem mond ki).

### D2 — Hiányzó csoportkulcs hiba, az `unknown` nem csoportkulcs

Ha egy felvételhez a kért split stratégia csoportkulcsa (player/device/
guitar/room) hiányzik vagy üres, a stratégia **típusos hibát** ad. Tilos
`unknown` nevű gyűjtő-foldba sorolni: az `unknown` fold pontosan azt a
szivárgást hozná vissza, amit a D1 tilt — egymással semmilyen kapcsolatban nem
álló felvételek egyetlen „csoportnak" látszanának, és a leakage-detektor
zölden átengedné őket.

### D3 — A metrika a definíciójával együtt utazik

Minden metrika mellé a report **beleírja a definícióját**: a toleranciát, a
párosítási szabályt, valamint a számláló és a nevező megnevezését. Egy szám
definíció nélkül később nem olvasható vissza — ez a visszavont BPM-mérce
(GOV-06b, E99-R05) mért tanulsága.

A definíció **a jelentés része, nem csak doc-comment**: a szám és a
jelentése együtt utazik, mert a kettő szétcsúszása pont az a hibaosztály,
amit a `docs/LESSONS.md` L549 és L577 mért (a gépi őr a SZÁMOT védte, a
jelentését nem).

### D4 — Az irány a metrika része: `higherIsBetter`

Minden metrika a report-ban **kimondja, melyik irány a jobb**. Az onset/irány/
akkord F1, az accepted accuracy és a coverage **magasabb = jobb**; az ECE, a
Brier-score, a false visible event/min és a latencia p50/p95 **alacsonyabb =
jobb**. Mért indok: a `docs/LESSONS.md` L173 szerint egy hiba-metrikára
(alacsonyabb = jobb) generikus „magasabb = jobb" sablonból konkretizált
összehasonlítás **csendben megfordítja** a döntést, és a self-test zöldsége
ekkor nem bizonyíték. Az irány típusban van, nem az olvasó fejében.

### D5 — A párosítás maximális kardinalitású, nem mohó

Az onset- és akkord-párosítás **maximális kardinalitású, egy-az-egyhez
párosítás** (Kuhn-féle augmentáló út), determinisztikus élsorrenddel: a
jelöltek legkisebb-eltérés-először, index-döntetlennel. A lokálisan
legközelebbi mohó párosítás **elutasítva** — nem maximalizál, és a kapott TP
alulbecsült (`docs/LESSONS.md` L269, E06-R29 BLOCKER).

A tolerancia-határ **inkluzív** (`<=`): a toleranciával pontosan egyenlő
eltérés még párosít, csak a szigorúan nagyobb nem. Ez az ADR 0359 D4
határkezelésével azonos, hogy a két felismerési mérce ne mondjon mást
ugyanarról az élről.

### D6 — Determinisztikus report

Ugyanaz a manifest **bájtra ugyanazt** a JSON-t adja: kanonikus kulcsrend,
csoportkulcs szerint rendezett foldok (nem hash-sorrend, nem beolvasási
sorrend), semmilyen `DateTime.now()`, véletlen vagy környezetfüggő érték a
report belsejében. A nulla nevezőjű hányados `null`, **soha nem `0`-ra
kényszerített** — a „nincs mit mérni" és a „mértük, nulla" két különböző
állítás (ADR 0359 mintája).

### D7 — Az ECE binjei egyenlő SZÉLESSÉGŰEK

A kalibrációs binelés `binCount` darab, egyenlő **szélességű**
(`[i/binCount, (i+1)/binCount)`, az utolsó zárt) bin — nem egyenlő
darabszámú kvantilis-bin. Mért ok: a repó meglévő, review-zott mintája ez
(`calibration_fitter.dart:132-141`), és a két binelés **különböző** ECE-t ad
ugyanarra az adatra, tehát a választás nem szabadságfok, hanem szerződés.

### D8 — Nincs kereszt-feature függés: a minta másolható, a függés nem

A felismerési harness **nem importálja** az `audio_analysis` evaluation
kódját. Az algoritmus-minta (párosítás, PRF1, ECE) átmásolható, de a
kereszt-feature import csak `public.dart` barrelt célozhat
(`tool/check_architecture.dart:774`), és ezek a típusok nem publikus
szerződés, hanem mérőeszköz — a `live` barreljébe sem kerülnek. Ezért a
típusnevek **saját, ütközésmentes** nevek (`Recognition…` előtaggal); az
`OnsetMetrics` név foglalt (`tool/benchmarks/real_audio_dsp_baseline.dart:30`),
tehát nem használható.

### D9 — A CI fixture kicsi és szintetikus; a valós korpusz külső marad

A CI-fixture nem tartalmaz valós felvételt és nem hivatkozik ilyenre; a valós
korpusz külső manifesttel, kézi futtatással mérhető (`--manifest`). Ez az
ADR 0249 kettősségének öröklése, nem új szabály.

### D10 — A `ml/honest_eval.py` érintetlen

A Python-oldali tanító mérés nem módosul, és ez a kör nem állítja, hogy a két
oldal ugyanazt a számot adja. Ha a két oldal definíciója eltér, azt a review
mondja ki dokumentumban — nem a kód „hangolja össze" csendben.

## Következmények

- A felismerési mérés csoportosított és szivárgás-mentes lesz: egy játékos,
  telefon vagy gitár nem szerepelhet egyszerre a két oldalon, és ha mégis, a
  futtató megáll ahelyett, hogy optimista számot adna.
- A riport önmagában olvasható marad: minden szám mellett ott a definíciója és
  az iránya, tehát egy későbbi kör nem fordíthatja meg némán az
  összehasonlítást.
- Ára: a hiányzó csoportkulcs kemény hiba, tehát a hiányos manifestet a
  futtatás előtt ki kell javítani — ez szándékos, mert a szivárgó mérés
  drágább, mint egy megállított futás.
- Határ: ez a kör mérőeszközt ad, nem hangol küszöböt és nem cserél modellt; a
  dashboard/HTML megjelenítés az `E14-R09` köre.
