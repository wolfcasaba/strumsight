# LESSONS — mért fejlesztési tanulságok

> A globális együttműködési szabályzat erre a fájlra hivatkozik; az E02-R02 review
> NOTE-3 leletéig nem létezett. **Létrehozva 2026-07-30**, user-döntésre (ezzel a
> HANDOFF §6.4 governance-kérdés lezárva: létrehozás, nem a hivatkozás kivezetése).
>
> **Mi kerül ide:** olyan tanulság, amit egy KONKRÉT kör MÉRT — hivatkozható
> forrással (kör, PR, review-fájl, sor). Ami csak jó ötlet vagy általános elv,
> annak az [`AGENTS.md`](../AGENTS.md) vagy egy ADR a helye, nem ez a fájl.
>
> **Mi NEM kerül ide:** a kódszerkezet (azt a kód mondja meg), a kör-történet
> (az a [`docs/handoff-archive.md`](handoff-archive.md)), a kötött döntések
> (azok az ADR-ek), a napi állapot (az a [`HANDOFF.md`](../HANDOFF.md)).
>
> **Formátum:** egy tanulság = egy szakasz, benne *Mit mértünk* / *Miért* /
> *Hogyan alkalmazd*. Új bejegyzés a saját köre commitjában, a lista végére.

---

## L01 — A zöld gate nem bizonyíték

**Mit mértünk.** Az E02-R04-ben **három MAJOR**, az E02-R05-ben **három MINOR**
hiba csúszott át úgy, hogy a `format`, az `analyze` és a teljes tesztsuite zöld
volt. Mindegyiket a review fogta meg, **eldobható próbateszttel, a legacy
referenciával szembe mérve** — nem szemrevételezéssel. A legdrágább eset: egy
hibátlan Analyze-klip idővonala némán kétszer olyan hosszú lett
([`docs/reviews/e02-r05-review.md`](reviews/e02-r05-review.md),
[`docs/reviews/e02-r04-review.md`](reviews/e02-r04-review.md)).

**Miért.** A gate-ek azt mérik, hogy a kód *lefordul és nem mond ellent a
meglévő teszteknek* — nem azt, hogy a kiszámolt érték *helyes*. Ha egy új
számításhoz nem írt senki referencia-tesztet, a hibája definíció szerint zöld
marad.

**Hogyan alkalmazd.**
- Reviewerként: minden ÚJ számított kimenetre írj eldobható próbatesztet a
  legacy/referencia implementációval szemben, és futtasd izolált klónban. A
  „minden zöld" jelentést soha ne fogadd el bemondásra.
- Brief-íróként: minden szövegesen leírt tartalmi előírás mellé adj **gépi
  mércét** (kipinnelt szekvencia, tételes ID-lista, µs-pontos várt érték),
  különben a review-nak kell kézzel elolvasnia az adatot.
- Implementerként: az éleket teszteld, ne a boldog utat — nem-nulla kezdet,
  határra eső utolsó elem, a nem-4/4 meter, a szélső paraméterértékek.

---

## L02 — Ne írj elő viselkedést lezárt fájlra (három variáns)

**Mit mértünk.** Háromszor futott meg ugyanaz az osztály, mindháromszor az
implementáció ELŐTT, `stopped` jelzéssel:

| Kör | Variáns | Az ütköző rögzítés |
|---|---|---|
| E01-R11 | a **kód** rögzíti a mai viselkedést | `mounted`-őr az `await` utáni first-win úton |
| E01-R12 | a **meglévő teszt** rögzíti | `test_prod_with_real_config_boots` |
| E02-R06 | **elérhetetlen állapot** | `PracticeDefinition.validate()` minden `totalBeats <= 0`-t elutasít, a brief mégis erre az esetre írt elő sikeres fordítást |

**Miért.** Az engedélyezett-fájllista jó eszköz a scope-tágulás ellen, de a
brief-író ugyanúgy hibázhat vele, mint az implementer: ha a kör viselkedést
változtat, az azt MA rögzítő fájl (kód vagy teszt) nem maradhat zárva; ha pedig
egy él-esetre ír elő kimenetet, előbb bizonyítani kell, hogy az a bemenet a
lezárt validációk mellett **egyáltalán előállítható**.

**Hogyan alkalmazd.**
- Brief-íráskor futtass egy „ki állítja ma az ellenkezőjét?" grep-et a **tesztfán
  is**, ne csak a `lib/`-en.
- Minden határérték-kritériumnál grep-eld ki az érintett mező validációját.
- A mellékesnek tűnő **zárójeles megjegyzés is szerződés** — ha nem mérted ki,
  ne írd le.
- Ha a kör már fut és kiderül az ütközés: **dokumentált brief-revízió**
  (revíziójegyzet + új kötött döntés + új kritérium), commit a kör-branchre, és
  az újraindító promptban erősítsd meg, hogy a megállás jó döntés volt — soha ne
  csendes scope-tágítás.

---

## L03 — A STOP-klauzula olcsó, a némán megkerült brief drága

**Mit mértünk.** Az E02-R06 első futása **~2 perc és 115k token** alatt állt meg
`stopped` jelzéssel, nulla kóddiffel, és pontosan megnevezte a brief hibás sorát
és az ütköző forrást (fájl + sorszám). Összehasonlításul: az E01-R11 ugyanilyen
helyes megállása egy teljes baseline tesztfutásba (~230k token) került, mert a
jelzés csak három megerősítő audit UTÁN jött.

**Miért.** A megállás nem kudarc, hanem a lánc legolcsóbb hibajavítási pontja.
A drágaság nem a megállásból jön, hanem a **késleltetett jelzésből** — addig az
orchestrátor vakon vár.

**Hogyan alkalmazd.** A promptban szó szerint szerepeljen: „probléma esetén a
jelzés az ELSŐ lépés, nem az utolsó" + a STOP-klauzula + hogy a `stopped` akkor
is helyes válasz, ha másodszor fordul elő. Orchestrátorként a jelzés után
**először a `.codex-round-status` fájlt** olvasd, csak utána a logot.

---

## L04 — Az engedélyezett-fájllista a tervezőt is köti

**Mit mértünk.** Az E01-R14-ben a Codex scope-auditja **Claude saját**
§4-sértését fogta meg — a tervező írt olyan fájlba, amit maga zárt le.
A feloldás **rebase** volt, nem lista-tágítás.

**Miért.** A lista objektív mérce (`git diff --stat` vs. lista); ha a tervező
kivételt csinál magának, a mérce elveszti az értelmét, és a review-nak nincs
mihez mérnie.

**Hogyan alkalmazd.** A brief-commit is a kör-branchre megy, és a §4 listának a
saját doc-fájljait is tartalmaznia kell. Ütközésnél rebase vagy dokumentált
revízió — nem utólagos lista-bővítés.

---

## L05 — Ezen a boxon az `analyze && test` lánc OOM-ol

**Mit mértünk.** A `flutter analyze` és a `flutter test` egyetlen shell-hívásban
láncolva elfogyasztja a memóriát ezen a gépen. Külön hívásként mindkettő lefut.
(Mért igazság; a [`CLAUDE.md`](../CLAUDE.md) build-gotcha szekciója ezért írja
felül a többi doksit.)

**Miért.** Két Dart VM/analyzer példány egyszerre.

**Hogyan alkalmazd.** Minden briefben és promptban KÜLÖN parancsként szerepeljen
a `format`, az `analyze` és a `test`, kifejezett tiltással a `&&`-re. A teljes
suite + property gate + APK amúgy is CI-oldali
([ADR 0053](adr/0053-ci-full-test-suite.md)) — a lokális futás a kör által
érintett könyvtárra szűkül.

---

## L06 — Az elnyelt hiba néma no-op

**Mit mértünk.** A settings-sync köre (17.) úgy jelzett sikert, hogy a
felhőbe írás `try/catch`-ben elhalt — a szerkesztés elveszett, a UI mégis
„mentve" állapotot mutatott.

**Miért.** Az optimista UI + elnyelt kivétel kombinációja a felhasználó felől
megkülönböztethetetlen a sikertől.

**Hogyan alkalmazd.** Az állapot csak a szerver visszaigazolása UTÁN jelölhető
szinkronizáltnak, a bukott push-t újra kell próbálni, és a perzisztenciát
teszttel kell bizonyítani. Általánosítva: **minden csendes fallback gyanús** —
a clamp, az alapértelmezésre esés és a kihagyott elem legyen kontrollált hiba
vagy legalább naplózott, sosem néma.

---

## L07 — Érzékeny körnél a motorválasztás user-döntés

**Mit mértünk.** Az E02-R06 indításakor az orchestrátor magától választott
Codexet az [ADR 0069](adr/0069-two-engine-implementer-pool.md) §15.6 besorolása
alapján; a user rákérdezett, és kikötötte, hogy érzékeny körnél **előre**
kérdezzünk (2026-07-30).

**Miért.** A szűkös erőforrás a **Codex heti kvótája**, nem a MiniMax tokenje —
és a kvóta pillanatnyi állását az orchestrátor nem tudja lekérdezni. Tehát ez
tényleg nem gépi döntés.

**Hogyan alkalmazd.** A brief elkészülte után, az implementer indítása ELŐTT
kérdezz, ha a kör az ADR 0069 §15.6 „érzékeny" sorába esik (DSP-hangolás,
baseline-érzékeny scorer/matcher, teljesítménykritikus út, felderítő feladat) —
és a kérdésben nevezd meg **konkrétan**, melyik befagyasztott artefaktumhoz ér
hozzá a kör. Nem-érzékeny kör (jól specifikált domain/model/teszt, adapter,
katalógus, i18n, mechanikus refaktor) mehet kérdés nélkül az alapértelmezett
motorral.

---

## L08 — A review kérése is lehet hiányos; „meglévő teszt" ≠ „a kör saját tesztje"

**Mit mértünk.** Az E02-R06 review egy valós MINOR-t fogott (ugyanaz a zenei
pillanat két különböző időt kapott), de a javítási kérése **hiányos** volt: a
`totalDuration` egyszeri konverzióját kérte anélkül, hogy végiggondolta volna,
hogy egész mikroszekundum mellett ez ütközik a „részek összege = egész"
állítással. Az implementer a javító körben megmérte és megállt
(`lesson.first-strums.v1`: 20 571 429 vs 20 571 428 µs).

A javító prompt „meglévő tesztet ne írj át" kitétele ráadásul **túl tág** volt: az
implementer emiatt a **saját, ugyanabban a körben írt** tesztjét is
érinthetetlennek vette. A második megállás így részben a review hibája volt, nem
az implementeré.

**Miért.** A reviewer ugyanúgy tervez, amikor javítási irányt ír elő, mint a
brief-író — és ugyanúgy elronthatja (lásd [L02](#l02--ne-írj-elő-viselkedést-lezárt-fájlra-három-variáns)).
A „ne írd át a meglévő tesztet" szabály célja a **befagyasztott** referencia
védelme; ha a kör saját, aznap írt tesztjeire is kiterjed, akkor a szerződés
jogos változásakor is megbénítja a javítást.

**Hogyan alkalmazd.**
- Javítási irány előírásakor **számold ki a következményt**, ne csak a hibát
  nevezd meg. Ha két invariáns versenyezhet, mondd ki, melyik nyer — vagy jelöld
  meg explicit tervezői kérdésként.
- A teszt-zárat mindig **nevesítve** add meg: „a befagyasztott
  `practice_baseline_scenarios.dart` / `legacy_scorer_baseline.json` / korábbi
  körök tesztjei zártak; a kör saját tesztjei a szerződés változásakor
  igazíthatók". A blanket „meglévő teszt" megfogalmazás kétértelmű.
- Ha a javítás tervezői döntést igényel, az **ADR-be** kerüljön (nem a prompt
  szövegébe), és az implementer a frissített ADR-re kapjon hivatkozást.

**A kör tartalmi hozadéka** (ADR 0072 §1.1, az egész Practice Engine időmodellje):
egész mikroszekundum mellett *pillanat pontos, időtartam származtatott* — minden
abszolút pillanat a nullponttól vett tickszám egyetlen konverziója, minden
időtartam két pillanat különbsége. Így a kompozíció pontos ÉS minden pillanat
bitre egyezik a legacy egyszeri képlettel.
