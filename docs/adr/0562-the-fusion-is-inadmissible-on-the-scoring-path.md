# ADR 0562 — A fúzió a PONTOZÓ úton megengedhetetlen: a rácsot a rácshoz hasonlítaná, és pont azt a leletet tünteti el, amiért az app létezik

- **Státusz:** elfogadva — **felülírja az ADR 0558 D1-et és D2-t**
- **Dátum:** 2026-09-12
- **Kör:** E18-R39
- **Kapcsolódó:** ADR 0557 D4 (a kötő szabály), ADR 0558 (a mért fúziós szabály), ADR 0556
  (a nyíl), `lib/features/curriculum/domain/rhythm_grading.dart`, `docs/LESSONS.md` L677

## Kontextus

A bekötés következő lépését kerestem — és a `gradeRhythm`-ot találtam meg, ami **már** a
fogyasztó, és **már** tartalmazza a teljes kontraktust:

```
  gradeRhythm(grid, strokes, startUs, bars, toleranceUs) -> RhythmAttempt
```

- `DetectedStroke { atUs, direction, isConfirmed }` — a felismert ütés;
- `startUs` = „amikor a 0. ütem 0. rése esedékes, a `DetectedStroke.atUs` **ugyanazon az
  óráján**" + `grid.onsetUs(...)` → **ismert fázisú rács**, pont amit az ADR 0560 kért;
- **1. szabály, kimondva a fájl fejében:** *„A párosítás IDŐT használ, SOHA nem irányt. …
  Párosíts idő szerint, aztán ítélj irányt"* — ugyanaz a megoldókulcs-védelem, amit az
  ADR 0557 D4-ben magam is levezettem, csak itt már kód;
- `RhythmSlotOutcome.unclear` — a tartózkodás, ami **semmit nem állít**;
- `extraConfirmedStrokes` — a ghost-résre leütött ütés;
- és `RhythmSlotOutcome.wrongDirection`, amiről a kód ezt írja:
  **„this is the thing only this app can tell a learner"**.

## A döntő megfigyelés

A `gradeRhythm` a `stroke.direction`-t a **rács** `expected` irányához hasonlítja. Ebből lesz
a `credited` vagy a `wrongDirection`.

Ha a metrikus csatorna előírását **beolvasztom a `DetectedStroke.direction`-be**, akkor a
grader **a rácsot a ráccsal** hasonlítja össze. A `wrongDirection` nullára megy, és az app
**minden tanulónak azt mondja, hogy a pengető keze hibátlan.**

És ez nem elvont veszély, hanem **már megmért szám**: az ADR 0558 táblájában az inga-sértő
ütéseken a fúzió a pontosságot **0,5000 → 0,2500**-ra viszi a letisztult tieren. Azok a
sértő ütések **pontosan a `wrongDirection` esetek**. A fúzió tehát **felére csökkenti** annak
az egyetlen leletnek az észlelését, amiért a ritmus-pillér létezik — és én ezt a sort
„a sértő részhalmazon jelentkező kár"-ként írtam le, anélkül hogy összekötöttem volna a
`wrongDirection`-nel.

## Döntés

### D1 — A `DetectedStroke.direction` NEM kaphat metrikus csatornát. Soha.

A pontozó úton az irány **csak akusztikus**, tartózkodással (`unclear`). A `gradeRhythm` ezt
már feltételezi; a fúzió bevezetése nem javítás lenne, hanem **a mérés elpusztítása**.

### D2 — Az ADR 0558 D1 ELLENTMONDOTT az ADR 0557 D4-nek, és én azt írtam, hogy egybeesnek

Ez a kör legfontosabb tétele, mert a hibám **nem egy szám volt, hanem egy állítás**.

- **ADR 0557 D4 rule 2:** „a pontozás az **akusztikus csatornát** veszi, tartózkodással. Ez a
  csatorna a tartózkodás lécét **mozdíthatja**; a hívást **soha nem fordítja át**."
- **ADR 0558 D1** a „csak döntetlen" szabályt szállíthatónak mondta: *„az akusztikus dönt, ha
  a margója meghaladja `t`-t, **a metrikus hívás dönt `t` alatt**"* — vagyis `t` alatt a
  metrikus csatorna **átfordítja** a hívást.

Az ADR 0558 D1 szövegében ez áll: *„Ez egybeesik az ADR 0557 D4-gyel"*. **Nem esik egybe: a
D1 megsérti a D4-et.** A `c* = 0,000` mérés igaz, de egy olyan metrikán (irány-macro-F1 az
igazsághoz), ami **nem kérdezi meg**, hogy a grader képes-e még észlelni egy minta-sértést.

Ez L670 a legerősebb formájában: azt a tengelyt mértem, amit javítani akartam, és nem azt,
amelyre a bukás a költséget átterheli.

### D3 — A NYÍL fúziója is megengedhetetlen, tehát az ADR 0558 D2 is elesik

Ezt végig akartam vinni funkció-kapu mögött. Nem megy: ha a nyíl **fúziót** mutat, a grader
pedig **csak akusztikust**, akkor a kettő **szerkezetileg ellentmond egymásnak pontosan a
sértő ütéseken** — a tanuló azt a nyilat látja, amit a minta kért, majd az ütem után azt
olvassa, hogy a másik irányba ütött. Ez az ADR 0556 D2 tilalma („ne mérj olyan ellen, amit a
tanuló nem látott"), csak visszafelé.

### D4 — Ami NEM kell a csatornához, mert már megvan

| amit a csatornához terveztem | ami már létezik |
|---|---|
| „az egyet nem értés a pedagógiai kimenet" | `RhythmSlotOutcome.wrongDirection` |
| tartózkodás, ha az akusztikus bizonytalan | `RhythmSlotOutcome.unclear` |
| a ghost-résre leütött ütés mint lelet | `extraConfirmedStrokes` |
| a megoldókulcs-védelem | a párosítás **időt használ, soha nem irányt** (1. szabály) |
| ismert fázisú rács | `startUs` + `grid.onsetUs(...)` |

A post-bar „a pengető kezed kiesett az ingából" üzenethez tehát **nem kell** metrikus
csatorna: a rács és a `wrongDirection` elég.

### D5 — Ami MEGMARAD a csatornának, őszintén: nem tanulónak szóló funkció

1. **Mérőeszköz.** Az ADR 0557 lelete áll, és magyaráz: a korpuszokon a pozíció 0,98-cal
   jelzi az irányt, tehát a korpusz-alapú irány-számok **optimisták**, és ez adja a take-ID
   orákulum AUC 0,7386-ját is. Ez tudás, nem feature.
2. **Adat-kiválasztás (telemetria).** Azok a menetek, ahol a két csatorna **sokat nem egyezik**,
   épp a kívánt tanító adat jelöltjei — az inga-sértő ütések, amikből a korpuszban 8 van.
   Nem tanulónak szóló út, és külön döntés.

**Ezért a `StrumMetricChannel` marad a repóban, bekötés nélkül**, és a doksija kimondja, hogy
a pontozó útra nem kerülhet. Nem dobom el: a Python mérés Dart-párja, paritás-fixtúrával, és
a D5/2 útnak kell.

## Következmények

- Az **ADR 0558 D1 és D2 felülírva**; a D3 (a „konzervatív" szabályom rosszabb volt a gyors
  tieren) és a D4 (a 11→8 ütéses korlát) **mérésként érvényben marad**.
- A bekötési sorrend **elesik**: nincs mit bekötni. A `settledTier` marad **sötét**, mert az
  egyetlen indoka a D1 fúzió volt.
- A `gradeRhythm` útja **nem változik** — és ez most már **mért indok**, nem alapállapot.

## Amit NEM állítunk

- A `settledTier` **önmagában** (fúzió nélkül) még mindig javíthatja a pontozást: a letisztult
  akusztikus verdikt macro-F1-je 0,6061 vs a gyors 0,5262, **rács nélkül**. Ez **független** a
  fúziótól, és **külön kör** lehet — de a költsége (ütésenként egy második forward) akkor is
  profile-build mérést kíván.
- Nem azt állítjuk, hogy a metrikus információ elvileg használhatatlan. Azt, hogy **a
  jelenlegi termék-kontraktusban** (a grader a rácshoz hasonlít) nincs olyan út, amin ne
  rombolná a saját mérését.
