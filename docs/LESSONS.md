
## L677 — Azt írtam, hogy a mért szabály „egybeesik" az etikai korláttal, miközben megsértette; és a metrika, amin mértem, nem tudta megkérdezni a termék kérdését (E18-R39, 2026-09-12)

### 1. A hiba nem szám volt, hanem egy állítás

Az **ADR 0557 D4** korlátja: *„a pontozás az akusztikus csatornát veszi, tartózkodással. Ez a
csatorna a tartózkodás lécét mozdíthatja; a hívást **soha nem fordítja át**."*

Az **ADR 0558 D1** szabálya: *„az akusztikus dönt, ha a margója meghaladja `t`-t, **a metrikus
hívás dönt `t` alatt**"* — vagyis `t` alatt **átfordítja** a hívást.

És az ADR 0558 D1-be ezt írtam: *„Ez egybeesik az ADR 0557 D4-gyel."* **Nem esett egybe: a D1
megsértette a D4-et.** Sőt, egy bekezdéssel lejjebb még azt is kiírtam, hogy „ez egybeesés,
nem levezetés" — vagyis az egybeesés **gyanússágát** éreztem, és a választ mégsem
ellenőriztem le a korlát **szövegén**.

Azért lett ilyen könnyű, mert a `c* = 0,000` mérés **valódi** volt. Egy erős szám mellé
odaírtam egy kényelmes mondatot a korlátról, és a szám hitelessége átszivárgott a mondatra.

**A szabály, amit megtartok.** Amikor egy mért szabályról azt állítom, hogy megfelel egy
korábbi korlátnak, a korlát **szövegét** kell odatennem és szóról szóra összevetnem — nem a
szellemét felidéznem. Egy korlát, aminek a betűjét nem ellenőriztem, nem korlát, hanem
szándék. *Az „egybeesik" a legdrágább szó, amit mérés mellé írhatok, mert úgy viselkedik,
mintha mérés lenne.*

### 2. És a metrika nem tudta megkérdezni a termék kérdését

A fúziót **irány-macro-F1-en** mértem az igazsághoz. Az jól mérte azt, hogy *milyen gyakran
helyes a jelentett irány*. Amit **nem** tudott megkérdezni: *képes-e a pontozó még észlelni
egy minta-sértést?*

Pedig a `gradeRhythm` a felismert irányt **a rács előírt irányához** hasonlítja, és ebből lesz
a `wrongDirection` — amiről maga a kód azt írja: **„this is the thing only this app can tell a
learner"**. Ha a rács előírását beolvasztom a felismert irányba, a grader **a rácsot a ráccsal**
hasonlítja: a `wrongDirection` nullára megy, és az app **minden tanulónak azt mondja, hogy a
pengető keze hibátlan**.

A szám ott volt a táblámban: az inga-sértő ütéseken a fúzió **0,5000 → 0,2500**. Azok a sértő
ütések **pontosan a `wrongDirection` esetek**. Leírtam „a sértő részhalmazon jelentkező
kár"-nak, és **nem kötöttem össze a termék kimenetével** — pedig egy körrel korábban (L670)
épp azt a szabályt vettem fel, hogy a bukási mód tengelyét kell mérni.

A különbség L670-hez: ott a tengelyt nem mértem. **Itt megmértem, és nem olvastam el.** Egy
számot kiírni nem ugyanaz, mint megérteni, mire vonatkozik.

**A szabály.** Egy termék-metrikának **meg kell tudnia kérdezni, amiért a termék létezik**. Ha
a differenciátor „észrevesszük, hogy rossz irányba ütöttél", akkor a mérésnek **közvetlenül
ezt** kell riportálnia (hány sértést észlel a rendszer), nem egy átlagos helyességet, amiben a
sértések 1,5%-ot nyomnak. *A célmetrika megválasztása terméki döntés, nem mérési kényelem.*

### 3. Negyedszer: a repó már tartalmazta a teljes kontraktust

Az [[L676]]-ban mintázatként nevezte meg magát, és a következő körben **azonnal** megismétlődött
— nagyobban. A `gradeRhythm` már tartalmazta:

| amit a csatornához terveztem | ami már ott volt |
|---|---|
| a megoldókulcs-védelem | **1. szabály: „a párosítás IDŐT használ, SOHA nem irányt"** |
| „az egyet nem értés a pedagógiai kimenet" | `RhythmSlotOutcome.wrongDirection` |
| tartózkodás | `RhythmSlotOutcome.unclear` |
| ghost-résre ütött ütés | `extraConfirmedStrokes` |
| ismert fázisú rács | `startUs` + `grid.onsetUs(...)` |

Az L676 szabályát (fogalom nevére keresni `lib/` egészében) **ebben a körben alkalmaztam is**,
és ezért találtam meg — tehát a szabály működik. Amit hozzáteszek: **a megtalált fájl
fej-kommentárját végig kell olvasni, mielőtt bármit tervezek**, mert a döntései ott vannak
kimondva. A `gradeRhythm` három „fork"-ja a fájl fejében van, és az első pont az én D4-em.

### 4. Amit ez megvédett

A kör **nem épített semmit**, és visszavont két korábbi döntést (ADR 0558 D1 és D2). A haszna:
ha bekötöm, a ritmus-pillér **saját differenciátorát** tüntettem volna el — és zöld teszt,
zöld kapu, mért `c* = 0,000` mellett tettem volna.

*Egy mérés, ami a rossz kérdésre felel, pontosan annyira megnyugtató, mint egy jó mérés — és
ez a baj vele.*

Lásd még [[L670]], [[L673]], [[L676]], ADR 0557, ADR 0558, ADR 0562.
