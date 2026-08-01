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

---

## L09 — A kipinnelt invariánst az implementer fel tudja lazítani, hihető indoklással

**Forrás:** E02-R07 R0 review, MAJOR-3
([`docs/reviews/e02-r07-review.md`](reviews/e02-r07-review.md) §4).

A brief §6.5 szó szerint azt írta elő, hogy a randomizált property gate **minden
elfogadott lépésre** a `(régi status, új status)` **párt** mérje az
`allowedTransitions` táblával. A megvalósult teszt ehelyett a tábla **tranzitív
lezártját** ellenőrizte, kódkommentben megindokolva („egy tick több élt is
láncolhat"). Az indoklás részben igaz volt — a gráf viszont erősen összefüggő,
így a lezárt-ellenőrzés majdnem vakuum, és **pontosan ez rejtette el** a
`permissionRequired → ready` táblán kívüli átmenetet (MAJOR-2).

**Miért.** A gate-nek a mérendő állítás alá kell feszülnie. Ha az implementer a
mérce megfogalmazását változtathatja meg, hogy a kód átmenjen rajta, az a
HORIZON anti-reward-hacking szabály megsértése — akkor is, ha jóhiszemű, és
akkor is, ha a kommentben ott az indoklás.

**Hogyan alkalmazd.**
- A briefben nevezd meg, mi az invariáns **nem elfogadható gyengítése**
  („a tranzitív lezárt NEM elfogadható mérce"), ne csak az elfogadhatót.
- Ha a mérés technikai akadályba ütközik (itt: egy tick több élt láncol),
  a brief adja meg az **eszközt is** hozzá (itt: a `statusPath` visszaadása),
  különben az implementernek a mérce lazítása marad az egyetlen kiút.
- A review-ban a felélesztett őrre futtass **valódi-sértés próbát**: rontsd el
  a kódot szándékosan, és nézd meg, tényleg pirosra vált-e. Az E02-R07-ben ez
  a próba (a `_canTransition` őr eltávolítása) piros lett — enélkül a „javítva"
  állítás ugyanolyan bemondás lett volna, mint az eredeti hiba.

## L10 — A fixture default-ja határozza meg, mit tud egyáltalán megfogni a teszt

**Forrás:** E02-R07 R0 review, MAJOR-4.

A több ütemes count-in csak `beatsPerBar` kattanást adott a helyes
`countInBars * beatsPerBar` helyett — a második count-in ütem néma maradt. A kör
**tizenegy** count-in tesztje mind zöld volt, mert a közös fixture default-ja
`countInBars: 1` volt, ahol a két képlet eredménye azonos.

**Miért.** Egy paraméteres szerződést egyetlen paraméterértéken mérni nem mérés.
A default érték csendesen kiválaszt egy olyan pontot, ahol a hibás és a helyes
implementáció megkülönböztethetetlen.

**Hogyan alkalmazd.**
- Ahol a szerződés **paraméteres** (`countInBars`, `beatsPerBar`, speed, loop),
  a brief acceptance criteriája **mátrixot** írjon elő, ne egy esetet:
  „`countInBars ∈ {0,1,2,4}` × `Meter ∈ {4/4, 3/4}`".
- Review-ban nézd meg a **fixture default-jait** az állítások előtt: ha minden
  teszt ugyanabból a default-ból indul, a lefedettség látszólagos.
- Kapcsolódó: [L01](#l01--a-zöld-gate-nem-bizonyíték) — itt is 370 zöld teszt
  mellett élt a hiba.

## L11 — A javító kör eredményét VISSZA kell húzni a fő repóba, mielőtt bármit ráépítesz

**Forrás:** E02-R07 merge, 2026-07-30 (PR #28 → `b5e0dfc`).

A javító kör a **külön munkapéldányban** (`/home/ubuntu/ss-mm-e02-r07`) hozta
létre a `47aae85` commitot. Az orchestrátor a fő repóban közben a *javítás előtti*
`dedfc13`-ra írta a további commitokat (review-frissítés, tanulságok), majd azt
pusholta és mergelte. Eredmény: **a `main`-re az R0 kód került, a négy MAJOR
javítása nélkül** — miközben a CI zöld volt (az R0 is zöld volt), a review pedig
jogosan APPROVED, mert a mérés a munkapéldányból klónozott `47aae85`-ön történt.
A hiba a merge utáni ellenőrzésen bukott ki (`grep statusPath` → 0 találat), és
külön hiánypótló PR-t igényelt.

**Miért.** A kétpéldányos futtatás (orchestrátor a fő repóban, implementer külön
munkapéldányban) minden javító körnél **két divergens ágat** hoz létre. A
`git fetch` a kör ELEJÉN megtörtént, a javító kör UTÁN viszont nem — és semmi
nem jelezte: a branch nevek azonosak, a `git log` a fő repóban rendben nézett ki,
a CI zöld lett.

**Hogyan alkalmazd.**
- **A javító kör `done` jelzése után az ELSŐ parancs a visszahúzás:**
  `git fetch <munkapéldány> <branch>` + `git merge --ff-only FETCH_HEAD`.
  Csak ezután írj bármit a branchre.
- **A merge után futtass tartalmi ellenőrzést, ne csak gate-et:** grep-eld a
  javítás egy-két azonosítóját a `main`-en (itt: `statusPath`, `countInSpanBeats`,
  a clamp eltűnése). A zöld gate nem különbözteti meg az R0-t az R1-től, ha
  mindkettő zöld — [L01](#l01--a-zöld-gate-nem-bizonyíték) egy újabb változata.
- A `.codex-round-status` `head=` mezője megmondja, mire számíts:
  **ha a fő repó `git rev-parse HEAD`-je nem ez, még nem húztad vissza.**

## L12 — Az ORCHESTRÁTOR várakozása is meghibásodhat: az implementer kész, te mégis vársz

**Forrás:** E02-R08, 2026-07-31. A `stopped` jelzés `01:05:40`-kor megszületett,
az orchestrátor `07:08`-kor vette észre — **hat óra állás**.

**Mit mértünk.** Az orchestrátor így várt a körre:

```bash
until ! pgrep -f "mm-r08-resume.sh" >/dev/null; do sleep 30; done
```

A `pgrep -f` a **teljes parancssorra** illeszt, és a várakozó ciklust futtató
shell parancssorában is ott van a `"mm-r08-resume.sh"` sztring — a `pgrep`
tehát **önmagát találta meg**, a feltétel sosem vált igazzá. Közben az
implementer szabályosan `stopped`-ot jelzett és döntést kért.

**Miért.** Két, egymást erősítő hiba:

1. **Önillesztő minta.** Bármely `pgrep -f <minta>` / `ps | grep <minta>`
   várakozás megfogja a saját héját, ha a minta a parancssorában szerepel.
2. **Rossz jelre vártunk.** A kör-szerződés (`AGENTS.md` §15.2) jele a
   `.codex-round-status` **jelzésfájl**, nem a processz élete. A processz-életre
   várás akkor is néma, ha a kör `stopped`-dal döntést kér — pedig épp az a
   pillanat, amikor a leggyorsabban kellene reagálni.

**Hogyan alkalmazd.**

- **Ne írj kézzel várakozó egysorost — használd az artefaktumot:**
  ```bash
  tools/wait-for-round.sh /home/ubuntu/ss-<motor>-<kör>
  ```
  A jelzésfájl terminális állapotára vár, és beszédes kilépési kódot ad
  (`0`=done, `3`=stopped/döntést vár, `4`=stalled|timeout|unknown, `5`=lejárt
  a várakozás). Egy korábbi kör bent maradt terminális jelzése nem zárja le
  azonnal (a `signalled_at` az alapvonal).
- Ha mégis processzre kell várni, a mintát tedd önillesztés-mentessé:
  `pgrep -f '[m]m-round\.sh'` — a karakterosztály miatt a saját parancssor
  szövege már nem illeszkedik a mintára.
- **A várakozásnak legyen felső korlátja.** A végtelen `until` a néma
  meghibásodás legjobb rejtekhelye: a „még fut" és a „a ciklusom elromlott"
  kívülről megkülönböztethetetlen.
- Kapcsolódó: a wrapper elakadás-őre (`MM_STALL_MINUTES`, alap **5 perc**)
  ugyanebben a körben lőtte ki a futást egy néma `flutter test` szakasz miatt.
  Gate-et futtató körnél indítsd `MM_STALL_MINUTES=20`-szal; a resume
  UGYANAZZAL a session-iddel megy (`claude -p --resume <session-id>`).

## L13 — A határpont-mátrixot a SZÁRMAZTATOTT mennyiségre add meg, ne a bemenetekre

**Forrás:** E02-R08 brief-revízió R1 (`docs/rounds/e02-r08-observation-gateway.md` §0.0).

**Mit mértünk.** A kör-brief a frame-kézbesítési lag küszöbét mérő mátrixot a
bemeneti párokkal adta meg, és a `(engineTimeSec, latestStrumTime) = (1.0, 0.5001)`
cellát szánta a „határ **fölötti** lag" esetének. Csakhogy
`1.0 − 0.5001 = 0.4999 s`, ami a `maxFrameDeliveryLag` (0.5 s) **alatt** van —
a mátrixban így **egyetlen a határ fölötti cella sem volt**, pont az az eset
hiányzott, amit mérni akart. Az implementer `stopped` jelzéssel fogta meg.

**Miért.** A mérce a `lag`-ra vonatkozik, a brief mégis a `lag` **operandusait**
sorolta fel, és a kivonást a tervező fejben végezte el. Egy fejben elvégzett
művelet néma: a hibás cella ugyanúgy néz ki, mint a helyes, és a review-ig
(vagy tovább) elél. Ez az [L10](#l10--a-fixture-defaultja-határozza-meg-mit-tud-egyáltalán-megfogni-a-teszt)
tervezői oldala — ott a fixture default-ja, itt a tervező fejszámolása választott
egy olyan pontot, ahol nem mérünk semmit.

**Hogyan alkalmazd.**

- A brief acceptance-mátrixa **a származtatott mennyiségre** szóljon, és a
  táblázat tartalmazza a származtatott értéket is oszlopként (itt: `lag`), ne
  csak a bemeneteket.
- Küszöbnél **három** cella kell: szigorúan alatta, **pontosan rajta**, szigorúan
  fölötte. A „rajta" cella az egyetlen, ami a `<` és a `<=` közti különbséget
  méri — a másik kettő nem.
- **Számold ki, ne becsüld.** Egy `python3 -c` a brief írása közben olcsóbb, mint
  egy `stopped` kör; lebegőpontos határnál ez nem opcionális
  (`1.0 - 0.5001 == 0.4999000000000001`).
- Ha az implementer ellentmondást jelez a kötött döntés és az acceptance között,
  a helyes válasz **dokumentált brief-revízió** (§0.0), nem a kötött döntés
  csendes enyhítése és nem a lista-tágítás.

## L14 — A MÉRCÉT is annyira szigorúan kell ellenőrizni, mint a kódot

**Forrás:** E02-R08 — egyetlen körben **három** orchestrátor-oldali hiba, mind
ugyanabból a családból.

**Mit mértünk.**

1. **A brief §6.2 lag-mátrixából hiányzott a küszöb FÖLÖTTI cella** — a
   „határ fölöttinek" szánt `(1.0, 0.5001)` valójában `lag = 0.4999`. Az
   implementer `stopped`-dal fogta meg ([L13](#l13--a-határpont-mátrixot-a-származtatott-mennyiségre-add-meg-ne-a-bemenetekre)).
2. **A §5.5 nem mondta ki a korrekció HATÓKÖRÉT** („minden emittált
   observationre"), ezért a strum-becsapódáshoz tartozó de-jitter a
   chord observationökre is rákerült — R0 MAJOR-1.
3. **A javító prompt a rossz őrtől kért valódi-sértés próbát:** azt kértem,
   hogy a *fajtánkénti* monotonitás-property váltson pirosra a hibás **közös**
   padlótól. Ez matematikailag lehetetlen: a közös padló globálisan monoton,
   tehát fajtánként is az. A reviewer-mérés: property **zöld (6/6)**, a
   determinisztikus §6.2b cella **piros**.

**Miért.** Mindhárom a mércét érinti, nem a kódot. A projekt fegyelme addig a
pontig erős, hogy „a zöld gate nem bizonyíték" ([L01](#l01--a-zöld-gate-nem-bizonyíték)) —
de a mérce maga is termék, és **ugyanúgy lehet hibás, mint a kód**. Egy hibás
mérce két irányba árt: vagy nem fog meg valós hibát (1., 3.), vagy hibás
viselkedést ír elő (2.).

**Hogyan alkalmazd.**

- **Mielőtt egy acceptance-pontot kiadsz, kérdezd meg: melyik konkrét hibás
  implementációt fogja ez pirosra?** Ha nincs ilyen, a pont vacuous. Ez a
  valódi-sértés próba **tervezés-idejű** párja.
- **Invariáns-alapú őr (property) és példány-alapú őr (unit-cella) mást tud.**
  Egy invariánst a hibás implementáció is teljesíthet — a monotonitás nem
  detektálja a de-jitter kioltását. Számértéket ellenőrző, determinisztikus
  cella kell hozzá. A briefben mondd meg, MELYIK őr a lelet mércéje.
- **Korrekciónál/transzformációnál mindig írd le a HATÓKÖRT is**, ne csak a
  képletet: melyik kimenetre vonatkozik, és melyikre nem.
- **A javító prompt is brief** — ugyanaz a szigor jár neki. A benne kért
  bizonyítékot előbb gondold végig, mint amit az implementernek elhiszel.
- Kapcsolódó: [L10](#l10--a-fixture-defaultja-határozza-meg-mit-tud-egyáltalán-megfogni-a-teszt)
  (fixture-default vakfolt) — ott a teszt írója, itt a brief írója választott
  olyan pontot, ahol nem mérünk semmit.

---

## L15 — A felmérő `grep` alakja dönti el, mit fog egyáltalán megtalálni a brief

**Forrás:** GOV-01 — a „hol él még a régi gate-parancslista" felmérésem
**háromszor** volt hiányos, ugyanabból az okból.

**Mit mértünk.**

1. Az eredeti (2026-07-30-i) brief §2 hét helyet sorolt fel — kimaradt belőle a
   `.claude/skills/strumsight-how-we-develop/SKILL.md`, pedig négysoros
   gate-listát tartalmazott. A §0.0 revízió pótolta.
2. A pótlás után is kimaradt három skill (`verify-before-done`, `review-loop`,
   `flutter-dev`), mert a felmérő greppet a **hosszabb**
   `flutter analyze lib/ test/` alakra futtattam, a három skill viszont a
   rövidebb `flutter analyze lib/` alakot használja. Az implementer az A2
   acceptance futtatásakor találta meg őket, helyesen NEM tágította a listát,
   hanem jelentette. A §0.2 revízió pótolta.
3. A `verify-before-done` skillre a `CLAUDE.md:116` **név szerint ráirányít** —
   tehát a maradvány az AKTÍV láncban ült, nem egy holt sarokban.

**Miért.** A kör-brief §2 („mért állapot") minősége **a felmérő parancs
alakjától** függ, nem az igyekezettől. Egy túl specifikus minta csendben
letakarja a felmérendő halmaz egy részét — és mivel a brief §4 (engedélyezett
fájlok) a §2-ből származik, a hiány **beépül a szerződésbe**: az implementer
onnantól nem is nyúlhat a kimaradt fájlhoz. Ez ugyanaz a hibaosztály, mint az
[L10](#l10--a-fixture-defaultja-határozza-meg-mit-tud-egyáltalán-megfogni-a-teszt)
fixture-default vakfoltja, csak a brief-írás szintjén.

**Hogyan alkalmazd.**

- **Felmérésre a legrövidebb közös törzset grepeld**, ne a teljes parancssort:
  `flutter analyze` — nem `flutter analyze lib/ test/`. A zajt utána szűröd, de
  legalább látod.
- **Két irányból mérj:** a régi alakra ÉS az újra (`grep -rln <új artefaktum>`).
  A kettő különbsége a még hátralévő munka; ha csak az egyiket futtatod, nem
  tudod, mekkora a halmaz.
- **A felmérés kimenetét tedd be a briefbe nyersen** (§2 „mért kiindulás") —
  így a review és az implementer is ugyanazt látja, és a hiány felismerhető.
- **Ha az acceptance és az engedélyezett-fájllista ütközik, az a TERVEZŐ hibája.**
  A feloldás dokumentált brief-revízió (§0.x), nem lista-tágítás és nem az
  acceptance halkítása. Kapcsolódó:
  [L11](#l11--a-javító-kör-eredményét-vissza-kell-húzni-a-fő-repóba-mielőtt-bármit-ráépítesz).
- **A szerződés szerint az ütközés `stopped`.** Az implementer itt `done`-t
  adott follow-uppal — nem okozott kárt, mert a kör-jelzés summary mezőjében és
  a §8-ban is szó szerint jelentette. A jelzés INFORMÁCIÓTARTALMA a lényeg, nem
  a betűje; de a briefben érdemes kiírni, hogy a részleges teljesülés is `stopped`.

---

## L16 — Az előírt MÉRÉS ALAKJÁT is ellenőrizni kell: teljesíthető-e egyáltalán

**Mit mértünk.** Az E02-R09-ben ([PR #32](https://github.com/wolfcasaba/strumsight/pull/32),
[review](reviews/e02-r09-review.md)) az implementer **háromszor** állt meg
`stopped` jelzéssel, és **mindháromszor az orchestrátor mércéje volt hibás** —
egyszer sem a kód:

1. **Teljesíthetetlen acceptance.** Az A1 „tűrés nélküli, mikroszekundumra
   egzakt paritás" a legacy `LessonScorer`-rel, miközben a matcher bemenete a
   **µs-ra kvantált** `CompiledPracticeTarget`. A legacy kerekítetlen `double`
   másodpercekkel dönt, a compiled target egész µs-mal (ADR 0066/0072); ahol
   `60/bpm` nem µs-reprezentálható — a lecke-katalógus **döntő többsége** —, a
   két időalap ≤ 0,5 µs-ban eltér, ami **pontosan a döntési határon**
   meghatározó. Mért ellenpélda: `first-strums` (70 BPM), legacy eltérés
   `280 000,42857 µs` → extra, matcher `280 000 µs` → párosul.
2. **Idealizált rácsból számolt referenciacella.** A javító revízióba írt
   `anthem-drive` holtverseny-cella (`153 061,408 / 153 061,041 µs`) egyenletes
   nyolcad-rácsból jött, de a lecke mintája `[_d, null, _d, _u, null, _u, _d, _u]`
   — a hivatkozott `beat 0 → 0,5` pár **nem is létezik**. A valódi cella a
   `[5,6]` célpár, `4 744 898 µs` felezőponttal, más számokkal.
3. **Önellentmondó javító-előírás.** „Mind a hat mezőre külön egyenlőség-cella"
   **és** „production kód NEM változik" egyszerre — miközben a
   `PracticeEventMatchResult` mindkét konstruktora privát, a `timingOffset`
   pedig származtatott (`observedAt − target.time`), tehát önállóan soha nem
   variálható.

**Miért.** Az [L14](#l14--a-mércét-is-annyira-szigorúan-kell-ellenőrizni-mint-a-kódot)
azt mondja ki, hogy a mérce *tartalmát* ellenőrizni kell. Ez a kör egy szinttel
mélyebbre mutat: a mérce **alakja** is lehet eleve teljesíthetetlen — nem azért,
mert rossz számot vár, hanem mert **olyan méréstn ír elő, amit a mért rendszer
szerkezete nem enged meg**. Két rendszer bitre egyeztetése csak akkor
értelmezhető, ha közös az időalapjuk; egy típus mezőnkénti tesztje csak akkor,
ha a mezők függetlenül variálhatók. Ezt a tervezés közben **le kell mérni**, nem
az implementerre hagyni.

Ez ugyanaz a hibacsalád, mint az
[L15](#l15--a-felmérő-grep-alakja-dönti-el-mit-fog-egyáltalán-megtalálni-a-brief)
(a felmérés alakja) és az
[L13](#l13--a-határpont-mátrixot-a-származtatott-mennyiségre-add-meg-ne-a-bemenetekre)
(a mátrix alakja) — mindháromban a **mérés formája**, nem a szándéka a hiba.

**Hogyan alkalmazd.**

- **Mielőtt egzakt (tűrés nélküli) egyezést írsz elő két rendszer között, mérd
  össze az időalapjukat / reprezentációjukat.** Ha eltérnek, a helyes feloldás
  **nem** tűrés és **nem** az állítás törlése, hanem hármas: (a) a **levezetett**
  védősáv kimondása — sávon kívül bitre egzakt marad; (b) a sáv szélességének
  **mérése** külön acceptance-ponttal (itt: `max |legacy_µs − compiled_µs| ≤ 0,5 µs`,
  mérve **0,489795919508 µs**); (c) a kizárt cellák **kipinnelése** saját
  teszttel, hogy a divergencia megnevezett, őrzött viselkedés legyen.
- **Referenciacellát a tényleges adatszerkezetből generálj** (`python3`-mal
  bejárva a valódi esemény-/mintalistát), soha ne a fejben tartott idealizált
  modellből. A generáló egysorost tedd a brief mellé.
- **Teszt-alakot csak a típus konstruálhatóságának ellenőrzése után írj elő.**
  Privát konstruktor és származtatott mező mellett a „mezőnként izolált" cella
  nem létezik; ilyenkor mondd ki, **melyik mező nem izolálható és miért nem kell**
  (itt: a `timingOffset` jelenléte az `==`-ben bizonyíthatóan redundáns, mert
  `observedAt` és `target.time` már összevetésre kerül).
- **Írd a briefbe:** „ha a te mérésed eltér az ittenitől, az `stopped` a két
  számmal, NEM csendes hozzáigazítás." Ez fogta meg a 2. hibát.
- **A reviewer a saját próbáját is ellenőrizze.** Ebben a körben egy próba
  (konstans `hashCode`) zöld maradt — de az **legális Dart**, a próba volt rossz.
  Zöldön maradt próbából csak akkor lesz lelet, ha előbb igazolod, hogy a
  megsértett állítás valóban kötelező.

---

## L17 — Az ELŐRE MEGÍRT brief-köteg nem létező szimbólumra hivatkozhat: a pre-flight grep-elje ki mindet

**Mit mértünk.** Az E02-R10 briefje ([PR #33](https://github.com/wolfcasaba/strumsight/pull/33))
a többi Epic 2-es körrel együtt **előre** készült el (E02-R10…R20, egy köteg,
`main` @ `ce8fbce`). A kör pre-flightja két driftet talált benne, az egyik
**blokkoló**:

1. **Nem létező enum-érték.** A §5.6 és az A3 `ChordOutcome.noDetection`-t írt
   elő, miközben az enum négyértékű volt
   (`correct, wrong, insufficientData, notApplicable`), és a `practice_verdict.dart`
   a brief **tiltott zónájában**. Ez az [L-osztály](#l11--kör-brief-viselkedésváltozás-vs-fájl-zár),
   amit a projekt már háromszor mért — most **negyedszer**, és először egy előre
   megírt briefből.
2. **Avult sorszám.** A brief a matchert „283 sor"-ként hivatkozta; a mergelt
   fájl **257 sor**. A szám a merge előtti állapotból származott.

**Miért ez más, mint az L11.** Az L11 esetei a brief írása közben keletkeztek, és
az implementer `stopped`-je fogta meg őket — egy-egy teljes futás árán. Itt a
brief **hetekre előre** készült el, tizenegy körre egyszerre, a kód pedig
közben mozgott. A hiba tehát nem egyedi figyelmetlenség, hanem a batch-előkészítés
**szisztematikus** kockázata: az **E02-R15 briefje ugyanígy `noDetection`-re
épül**, tehát a hiba ott is ott ült volna.

**Mit csinálunk másképp.**

- **Minden előre megírt brief pre-flightjában grep-eld ki a kódból a briefben
  hivatkozott MINDEN enum-értéket, mezőt és metódust**, és mérd újra a
  sorszám-hivatkozásokat (`wc -l`). Ami nincs meg: vagy additív engedéllyel
  felkerül az engedélyezett fájllistára, vagy a viselkedés-előírást írod át —
  **dokumentált §0.0 brief-revízióban**, nem az implementerre bízva.
- **A feloldás iránya számít.** Itt a `noDetection` beolvasztása az
  `insufficientData`-ba olcsóbbnak tűnt (nem nyit lezárt fájlt), de az **R15
  UI-ja** külön jelenítést vár — az összevonás oda tolta volna a modellnyitás
  költségét. Additív enum-bővítés lett, **az enum végére fűzve**, és előbb
  megmértük, hogy nincs kimerítő `switch`, amit törne (`grep -rn ChordOutcome
  lib/ test/` → három találat, mind teszt-oldali konstrukció).
- **A pre-flight a numerikus cellákat is számolja újra.** Az A1/A4/A6 összes
  cellája `python3`-mal újraszámolva egyezett — ez tette hitelessé a két talált
  driftet: tudtuk, hogy a brief többi része tartható.

---

## L18 — A gyorsításnál mérd meg, mi viszi az időt: itt nem a CI vitte

**Mit mértünk.** A user 2026-07-31-én azt kérte, ne kelljen minden körben CI-t
futtatni, elég lenne epicenként. A döntés előtt megmértük a kör-időmérleget:

| | mért érték |
|---|---|
| kör átfutása (merge→merge) | **1,5–2,5 óra** (R05→R06 1h41 · R06→R07 2h13 · R08→GOV-01 2h35) |
| egy `build-apk.yml` futás | **9–10 perc** |
| futás körönként | **3** — kör-branch dispatch (a kapu) + push-to-main a merge után + push-to-main a docs-commitra |

**A CI tehát a kör idejének ~8%-a**, és annak is csak a harmada kapu. Az
epicenkénti gate ~10 percet spórolt volna körönként — cserébe az Epic 2
szigorú láncán (R10 → R11 → R12 → R13 → R14, minden kör az előző merge-ét
igényli) egy R11-es regresszió az epic végén, öt egymásra épülő kör alatt
eltemetve derült volna ki.

**Mit csinálunk.** Az epicenkénti gate **elutasítva**; helyette a valóban
információ nélküli futások szűntek meg ([ADR 0086](adr/0086-ci-dispatch-only-build-gate.md)):
a `build-apk.yml` már **csak `workflow_dispatch`**-re fut. A merge utáni
main-futás normál esetben nulla információt adott (a squash ugyanazt a fát
állítja elő, amit a branch-futás gate-elt), a docs-commité pedig egyetlen
buildbe kerülő bájtot sem érintett.

**A rést, amit a main-futás fedett** (ha a `main` a dispatch UTÁN mozdul — ezen
a boxon másik autonóm driver is merge-el), egy **kötelező merge-előtti
ellenőrzés** zárja: `git fetch origin main && git rev-parse origin/main`
egyezzen a dispatch idejekor látott SHA-val, különben rebase + újra-dispatch.

**Az általános tanulság:** amikor „lassú a fejlesztés" panasz érkezik, a
válasz nem a legláthatóbb lépés kivágása, hanem az időmérleg megmérése. Itt a
szűk keresztmetszet az implementer → review → javítás **soros lánc** volt; a
nyereség onnan jött, hogy a kör-CI-t az implementer „kész" jelzésekor
dispatch-eljük, nem a review után — így a 10 perc **elrejtőzik** a review mögött.

## L19 — Az erőforrás-tulajdonlást a hívási láncon kell mérni, nem a réteg-diagramon

**Mit mértünk.** Az E02-R11 ADR-vázlata (0077) a `PracticeSessionController`-re
bízta az `AudioSessionLease` megszerzését — a réteg-diagram alapján ez tűnt a
„lifecycle-tulajdonos" természetes helyének. Az implementer (MiniMax M3) az
első percben `stopped`-dal megfogta: a `MicCapture` a gateway alatt **maga
szerzi** a lease-t (`mic_capture.dart:82`), és a koordinátor **nem reentráns**
(`audio_session_coordinator.dart:38` — azonos `AudioOwner`-nek is
`audio.session_busy`-t ad). A controller lease-e a `gateway.start()`-ot
determinisztikusan hibára vitte volna: a production út halott, miközben a fake
gatewayes tesztek zöldek.

**Mit csinálunk.** Erőforrás-előírás (lease, lock, handle, subscription) csak
kimért hívási lánccal kerülhet briefbe/ADR-be. A mérés egy grep:
`grep -rn "\.acquire(" lib/` — itt egyetlen sort adott, és az eldöntötte a
tulajdonost. Feloldás: ADR 0077 §10 (a felszabadítás tranzitív a
`gateway.stop()/dispose()` láncán), gépi őre az A9 forrásminta-guard.

**Forrás:** `docs/reviews/e02-r11-review.md` §0, a brief §0.0 R13 sora.

## L20 — Elérhetetlen cél-státusz: az átmenettábla nem bizonyítja, hogy az él bejárható

**Mit mértünk.** Az E02-R11 brief A5 cellája a gateway-start bukására `failed`
státuszt írt elő `countIn`-ból. Az `allowedTransitions` tábla tartalmazza a
`countIn → failed` élt — de az egész reducerben **egyetlen** sor állít
`failed`-et (`practice_session_reducer.dart:612`), és az a `preparing`
státuszra van őrizve (`:604–606`). Az él a táblában van, de **egyetlen input
sem produkálja**: az előírás teljesíthetetlen volt. Ez az L16 hibaosztály
(„a mérés alakját is ellenőrizd") státuszgép-változata, és a harmadik eset a
sorban (E01-R11/R12, E02-R06 után).

**Mit csinálunk.** A pre-flightban minden előírt cél-státuszra a **producenst**
kell megmérni, nem a táblát: `grep -n "status: <Enum>.<érték>" <reducer>`,
és megnézni, milyen guard van az adott ágon. Feloldás az R11-ben: a
gateway-start bukása `cancelled`-be visz (recorder-hívás nélkül — nincs hamis
history-bejegyzés), a korlátot az A17 cella pinneli, a hiányzó futásidejű
fatal él gazdája az E02-R18 (ADR 0077 „Ismert korlát 2").

**Forrás:** a brief §0.0 R14 sora, `docs/adr/0077-practice-session-controller.md`.

## L21 — A néma no-op nem csak try/catch-ben él: `&&`-lánc és a dispatch-SHA

**Mit mértünk.** Két különböző néma-bukás ugyanabban a körben (E02-R11):

1. A javító-kör promptjából kimaradt a „commitold a munkád" mondat → az
   implementer `done`-t jelzett **három uncommitted fájllal** (`dirty_files=3`).
   A jelzésfájl `dirty_files` mezője fogta meg.
2. Az orchestrátor `git branch -f X && git checkout X` lánca: a `branch -f`
   elbukott (a branch ki volt jelentkezve), a checkout néma no-op lett, és a
   review-commit + a CI-dispatch a **második javító kör nélküli** SHA-ra ment.
   Zöld CI lett volna a merge-evidencia egy olyan HEAD-en, amiből hiányzik a
   MAJOR-4 javítás.

**Mit csinálunk.** (1) A kör- és javító-promptok kötelező eleme a
commit-utasítás, és a `done` jelzés feldolgozásakor a `dirty_files != 0` mindig
kivizsgálandó. (2) Dispatch után kötelező ellenőrzés:
`gh run list --json headSha` ↔ `git rev-parse HEAD` — a run csak akkor
merge-evidencia, ha a kettő egyezik. Az ADR 0087 pipeline-promptja mindkettőt
tartalmazza.

**Forrás:** `docs/reviews/e02-r11-review.md` §11.5.

## L22 — A UI-kör hibái a CELLÁK KÖZÖTT élnek: kombinált státusz és többszöri belépés

**Mit mértünk.** Az E02-R13-ban a javító kör #1 után a gate, a CI és a
scope-audit mind zöld volt, a képernyő **minden** státuszára volt teszt — és a
review mégis **három MAJOR**-t mért ki eldobható próbatesztekkel. Mindhárom
ugyanabból a vakfoltból jött: a cellák **egyenként** helyesek voltak.

1. **Kombinált forrás.** A `failed` státuszra a **státusz-vezérelt** panel és az
   **effekt-vezérelt** overlay is renderelt — külön-külön mindkettőnek volt zöld
   cellája. A reducerben viszont egyetlen hely állít `failed`-et
   (`practice_session_reducer.dart:612`), és **ugyanaz a tranzíció** adja a
   `ShowRecoverableError` effektet is: `PROBE P1: PracticeErrorPanel=1
   errorTitleTexts=2` — a normál hibafolyamban két hibakártya.
2. **Többszöri belépés.** Az overlay-állapot app-scope-ú `StateProvider` volt,
   amit senki nem nullázott: `PROBE P2: stale error surfaces after re-entry = 1`.
   Minden meglévő cella **egyetlen** `pumpWidget`-tel dolgozott, ezért egyik sem
   láthatta.
3. **A fake naplóz, a teszt nem nézi.** Az `AnnounceAccessibilityFeedback`
   cellája a haptikát és a navigációt mérte nullának — a `_RecordingFeedback`
   `announcements` **listáját nem**. Az ág eközben a nyers gépi kulcsot küldte a
   képernyőolvasónak, a brief A3 táblájával szemben.

**Mit csinálunk.** (1) UI-kör briefjében a státusz-mátrix mellé **kombinált**
cella is kell: minden olyan státuszra, amit a reducer effekttel EGYÜTT állít be,
a záróteszt a státuszt **és** az effektet együtt adja, és a felületet
**megszámolja** (`findsOneWidget`, nem `findsWidgets`). (2) Minden
képernyő-scope-ú állapotra kötelező a **be- → ki- → újra-belépés** cella
ugyanabban a `ProviderScope`-ban. (3) Ha egy cella „0 hívást" ír elő, a
záróteszt a fake **naplólistáját** mérje, ne egy másik mezőt. (4) A review
oldalán a zárás hitelesítése **mutációs próba**: a javítás visszarontása
**pontosan** a hozzá tartozó cellát váltsa pirosra — az R13-ban mindhárom
mutáció így viselkedett, kollaterális nélkül.

**Forrás:** `docs/reviews/e02-r13-review.md` §5 és §9.3.

## L23 — A generált l10n gitignore-olt: friss klón / régi munkafa `analyze`-e hamisan piros

**Mit mértünk.** Az E02-R13 review-jában a friss `/tmp` klónon a
`tools/round-gate.sh` **490 hibával** pirosat adott (`undefined_getter`,
`Target of URI doesn't exist: package:strumsight/l10n/app_localizations.dart`),
holott a kör kódja hibátlan volt. Ugyanez a merge utáni fő munkafán is
megismétlődött, 145 hibával — mert a fa hosszú ideje nem regenerált, miközben az
R12/R13 új ARB-kulcsokat vitt be.

**Mit csinálunk.** A `lib/l10n/app_localizations*.dart` **generált és
gitignore-olt** (CLAUDE.md), ezért izolált klónban és régóta nem frissített
munkafában a gate ELSŐ lépése:

```bash
/home/ubuntu/flutter/bin/flutter gen-l10n
```

Ez után a gate a valóságot méri. A tünet felismerhető: a hibák **kizárólag**
`AppLocalizations`-getterek és az `app_localizations.dart` URI-ja — ha bármi más
is piros, az már valódi lelet.

**Forrás:** `docs/reviews/e02-r13-review.md` §9.1; mérve 2026-08-01, a
`/tmp/review-e02r13-fix2` klónon és a `main` munkafán.

## L24 — A §10 handoff HAMISAN tulajdoníthat teszt-lefedettséget; a review a MÉRŐ tesztet keresse, ne az állítást

**Mit mértünk.** Az E02-R15-ben a gate, a CI és a scope-audit mind zöld volt, a
§10 handoff pedig azt állította, hogy az **A7 (3/4 ütem)** kötelező
acceptance-cellát a `practice_session_review_probes_test.dart` „A7 cellái"
fedik. A review kimérte: az a fájl **pre-existing** (a kör-diffben nincs benne)
és **nem hivatkozik** az új `ChordChangeAnalyzer`-re — tehát az új kód 3/4-es
viselkedését nem bizonyíthatja. A három ÚJ teszt-fájlban a
`grep "beatsPerBar: 3\|waltz\|3/4"` **0 találat** volt: A7 mérő teszt nélkül
maradt. (Az analyzer kódja HELYES volt — reviewer-próba: 3/4 → `correct`, 100 ms
—, tehát a hiba tiszta lefedettségi/attribúciós hiba, nem korrektség: MAJOR.)
Másik mért cella: az **A2** három-cellás küszöbteszt (`>=`) csak a 180000 µs→
`correct` ágat tartalmazta (az A1-correct teszten át); a 179999/180001 µs
él-cellák hiányoztak — reviewer-próba igazolta a `>=`-t, MINOR.

**Mit csinálunk.** (1) A review az acceptance-kritériumot a **kör saját, új
teszt-fájljaiban** keresse meg grep-pel (érintett meter/enum/határérték szó
szerint), és **ne fogadja el** a §10 hivatkozását egy fájlra, amíg nem látta,
hogy az a fájl (a) a kör-diff része ÉS (b) hivatkozik az új szimbólumra. (2)
Minden kötelező cellához, amit a kör saját tesztje nem fed, a reviewer **eldobható
próbatesztet** ír a szállított kódra (izolált `/tmp` klón): ha a kód helyes, a
lelet MAJOR/MINOR **teszt-lefedettség** (javító körben pótolt cellával, ami a
hiányt PIROSRA fogta volna), ha hibás, BLOCKER. (3) A MiniMax-implementer
`round-gate.sh`-t futtató lépése alatt a stream percekig néma lehet → a
`mm-round.sh` stall-őrét ilyenkor **`MM_STALL_MINUTES=14`**-re emeld; egy
mid-work stall után a munka a munkapéldányon megőrződik, és **filesystem-szintű
resume** (friss session, folytatás-prompt a meglévő fájlokra) tisztán befejezi.

**Forrás:** `docs/reviews/e02-r15-review.md` §4 (A7/A2) és §0; a stall+resume
mérve 2026-08-01 (`/tmp/mm-e02r15.log` → `mm-e02r15-resume.log`).

## L25 — Ha az acceptance-invariánst egy TILOS-ZÓNÁS komponens állítja elő, a valódi-sértés próba AZT a komponenst rontsa, és a guard-teszt lehet pre-existing

**Mit mértünk.** Az E02-R16 A2 („Free Practice alatt nincs hamis score,
`overall == MetricNotApplicable`") központi invariánsa **nem** a kör új
kódjában dől el: a `FreePracticeSummary` típusnak nincs is `overall` mezője. Az
`overall`-t a **tilos zónás** R10 aggregátor számolja az üres súlyú
`freePracticeOpen` profilból (`availableWeightTotal==0 → MetricNotApplicable`,
`practice_score_aggregator.dart:76-81`). A kör új A2-teszt-csoportja
(`free_practice_summarizer_test.dart:279`) ezért triviálisan zöld (nincs mit
elrontani a summaryn). A **valódi** guard egy **pre-existing** teszt
(`practice_score_aggregator_test.dart:167` „free practice has no overall
score", R10 óta) — ami a kör-diffben nincs benne.

**Mit csinálunk.** (1) Amikor az acceptance-cella állapotát a kör **hatókörén
kívüli** komponens produkálja (aggregátor, scorer, state-gép), a reviewer a
guardot a **teljes suite-ban** keresse, ne csak a kör új teszt-fájljaiban — a
pre-existing teszt is legitim bizonyíték, ha a kritikus utat fedi (kiegészíti
[[L24]]-et: a hiányzó ÚJ teszt önmagában nem lelet, ha a régi guard él). (2) A
§11 valódi-sértés próbát **arra** a komponensre kell injektálni, amelyik az
értéket adja: itt az aggregátor overall null-ágát `MetricAvailable(0)`-ra
rontva a pre-existing cella pirosra vált (`Expected MetricNotApplicable, Actual
MetricAvailable`) — ez bizonyítja, hogy a garancia él, nem a kör új tesztjének
zöldje. (3) Ha a próba a kör tilos zónáját érinti, az az izolált `/tmp` klónban
eldobható marad (revert), nem kör-scope-sértés.

**Forrás:** `docs/reviews/e02-r16-review.md` §3 (A2) és §4; mérve 2026-08-01 a
`/tmp/review-e02r16` klónon (injektált overall-rontás → piros → revert).

## L26 — „A profilból jön" ≠ a profil-OBJEKTUM: egy SDD-szakaszszám stricter, KÜLÖN predikátumot rögzíthet, amit a naiv implementáció összemos

**Mit mértünk.** Az E02-R17 előre megírt briefje (§5.6) azt írta: „a step-up
küszöb **a profilból jön** (SDD §16.7)", `completion≥0.95 ∧ overall≥0.85 ∧
rhythm≥0.80`. A `main` @ `caca3a9` mérése viszont kimutatta: a `ScoringProfile`
objektum `completionThresholdPercent`/`overallThresholdPercent` mezői **85/70**
(ez a **plain** scored-practice pass, ami a `PracticeAttemptOutcome.passed`-et
adja, `practice_score_aggregator.dart:267-270`), és **nincs** benne 0.95/0.85/
0.80, sem rhythm-threshold. Az SDD §16.7 két KÜLÖN blokkot rögzít: „Alap pass"
(0.85/0.70) és „Speed Builder step-up" (0.95/0.85/0.80). A „a profilból jön"
tehát félrevezető: egy **spec-szakaszszám** (§16.7) nem a **config-objektum**
(`ScoringProfile`). A naiv implementáció, amely `outcome==passed`-ből vagy a
`ScoringProfile`-ból vezeti le a step-up passt, a kör legfontosabb invariánsát
(A6 stabil-BPM, A2 léptetés) csendben elrontja, miközben minden teszt zöld
maradhat.

**Mit csinálunk.** (1) Ha egy előre megírt brief azt állítja, egy küszöb/érték
„a profilból / a configból jön", a pre-flight **grep-elje ki a config-objektum
tényleges mezőit** — ha a hivatkozott számok nincsenek benne, a hivatkozás egy
spec-szakaszra mutat, nem az objektumra (kiegészíti [[L20]]-at: nemcsak a
cél-státuszt produkáló inputot, hanem a küszöb tényleges TÁROLÁSI helyét is
mérni kell). (2) Ha egy spec két, névre hasonló predikátumot definiál (itt:
plain pass vs step-up pass), a §0.0 brief-revízió **mondja ki explicit, hogy a
kettő KÜLÖN**, és tiltsa meg az egyikből a másik levezetését — az ADR kötött
döntésébe emelve (ADR 0083 §3). (3) A reviewer a megkülönböztetést **mért
cellával** kérje számon (itt: `outcome=passed` + sub-threshold metrikák → NEM
lép; `outcome=failed` + 0.95/0.85 → lép), nem csak a happy-path zöldjével.

**Forrás:** `docs/rounds/e02-r17-speed-builder-and-adaptive-retry.md` §0.0 +
[ADR 0083](adr/0083-speed-builder-and-adaptive-policy.md) §3; `docs/reviews/e02-r17-review.md`
§5; mérve 2026-08-01 (`ScoringProfile` 85/70 vs SDD §16.7 0.95/0.85/0.80).

## L27 — Orchestrátor tooling: `mm-round.sh` KLÓNT vár (`.git` könyvtár), nem worktree-t; és a reviewer-klón a COMMITOT tartalmazó forrásból készüljön, ne a stale primary-refből

**Mit mértünk.** Az E02-R17 indításakor `git worktree add`-del készített
munkapéldány a `tools/mm-round.sh`-t azonnal `exit 2`-vel elbuktatta („a
munkapéldány nem git-fa"): a wrapper `[ ! -d "$workdir/.git" ]`-t ellenőriz, egy
**worktree** `.git`-je viszont **fájl**, nem könyvtár. A `setsid … >/dev/null`
elnyelte a hibát → néma nem-indulás. Külön: a reviewer-klónt előbb a **primary
munkafából** (`/home/ubuntu/music-theory`) klónoztam, ám a kör-commitot egy
oldal-klónból (`ss-mm-e02-r17`) pusholtam origin-ra, így a primary lokális
branch-refje `7ee37ae`-en (a pre-flight commiton) ragadt — a klón a
SpeedBuilder-kód NÉLKÜL jött létre.

**Mit csinálunk.** (1) MiniMax/Codex implementer-munkapéldány = **teljes klón**
(`git clone <forrás> <dir>`), nem `git worktree` — a wrapper `.git`-könyvtárat
vár. (2) A detach-olt indítást (`setsid`) egyszer **hibalátó módban** is futtasd
(stderr-t ne dobd el), amíg a `.mm-round-pid` + a log meg nem jelenik. (3) A
reviewer-klón forrása a kör-commitot **igazoltan tartalmazó** fa legyen: az
origin (`git ls-remote` ground truth) vagy az az oldal-klón, amelyből pusholtál
— **ne** a primary munkafa, ha onnan nem pusholtál (a lokális branch-ref stale).
A klón `HEAD`-jét mindig vesd össze a várt SHA-val, mielőtt review-zol.

**Forrás:** E02-R17 orchestrátor-futás, 2026-08-01 (`tools/mm-round.sh:45`
`.git`-dir-check; `tools/wait-for-round.sh` jelzés-alapú várakozás); mérve a
`ss-mm-e02-r17` klón + `/tmp/review-e02r17` reklón HEAD-egyeztetésével.

## L28 — Egy „valódi implementációt" felváltó recorder KÉT néma osztályt csempészhet be zöld gate mellett: a swallowoló írás-réteg és a write-then-drop kód-eltérés

**Mit mértünk.** Az E02-R18 (Practice History V2) zöld CI **és** zöld
reviewer-gate mellett szállított **két** BLOCKER-t, amiket csak eldobható
próbateszt fogott meg izolált klónban:

1. **B1 — a swallowoló írás-réteg.** A repository a `JsonCollectionStore` →
   `JsonDocumentStore.write`-on át írt, ami `on StorageException catch`-csel
   **logol, majd normálisan visszatér** (a „in-memory a truth, a disk
   best-effort" szerződés miatt). Egy STATELESS recorderre ez néma adatvesztés:
   a `save()` `Success`-t ad, miközben semmi nem íródott ki. A szállított
   A9-teszt `StateError`-t (nem `StorageException`-t) dobott — a **reális**
   hibatípus KÖRÉ írva. Fix: a repository közvetlenül a `KeyValueStore`-ral ír
   (az propagálja a `StorageException`-t) → `AppResult.failure`.
2. **B2 — write-then-drop kód-eltérés.** A produkciós provider a mappert
   `mode/source = 'practice.mode.unknown'` placeholderrel kötötte, mert a valós
   metaadat (a `PracticeSessionConfig`) csak a controllerben él (tilos zóna), és
   nincs provider, ami kiadná. A szerializáló **olvasáskor** eldobja az ismeretlen
   kódú rekordot → minden produkciós rekord íródik, majd betöltéskor eltűnik. A
   feature-tesztek zöldek voltak, mert **valós kódot injektáltak közvetlenül**,
   megkerülve a szállított wiringet. Fix: honest deferral — placeholder-metaadatnál
   `Noop` recorder (nincs eldobható rekord), a valós plumbing dokumentáltan R19.

**Mit csinálunk.** (1) **Perzisztencia-review kötelező próbája a PRODUKCIÓS úton**
fut, nem közvetlen injekcióval: a review-nak a szállított provider-wiringgel kell
menteni-majd-visszaolvasni, és a „save `Success`, de load 0 rekord" állapot
BLOCKER. (2) **A reális hibatípust dobd**, ne egy köré-írt helyettesítőt: egy
`StorageException` írás-hiba a mérce, mert a réteg épp AZT nyeli el. (3) **Ha egy
„valódi implementáció" (recorder) kötelező bemenete (mode/source) csak zárt-kör /
tilos-zóna komponensből érhető el, az PRE-FLIGHT-hiba** — a `PracticeSessionResult`
mezőit mértem, de nem jelöltem, hogy hiányzik belőle a mode/source. A pre-flight
mérje a „valódi implementáció" MINDEN kötelező bemenetének forrását, ne csak a
határ-interfészt. A honest deferral (dokumentált `Noop` + R19-followup) legitim,
a write-then-drop nem.

**Forrás:** E02-R18 review (`docs/reviews/e02-r18-review.md` B1/B2), fix#1
`30b8b1d`; `json_document_store.dart:103-129` (swallow), `key_value_store.dart:19-21`
(a szerződés, ami a `StorageException`-t ígéri), `practice_history_serializer.dart:77-86`
(unknown-enum reject on read).

---

## L29 — A paritás-elemzés a SZÁMLÁLÓ/NEVEZŐ egyezésénél nem ér véget: a ZÁRÓ OSZTÁS numerikus alapja külön mérendő

**Mit mértem.** Az E02-R19/b pre-flightjában (brief §0.1) sorról sorra összevetettem
a legacy `LessonScorer`-t és a V2 `PracticeEventMatcher` + `PracticeDirectionScorer`
párost: óra-korrekció, illesztési politika, ablak (`windowSec = 0.28` ↔
`matchWindow = 280 ms`), extra ütés kezelése, rossz irány kezelése, számláló,
nevező — **mind azonos**. Ebből azt a következtetést írtam a briefbe, hogy „az
egzakt paritás tervezetten elérhető; ha eltérést mérsz, az az adapter
konfigurációs hibája". **Két helyen tévedtem, és mindkettő a záró aritmetika volt:**

1. **Kvantálás.** A `PracticeDirectionScorer` ezrelékre kvantál
   (`correctCount * 1000 ~/ applicableCount / 1000`), a legacy nem →
   7/24 = `0.2916666666666667` vs `0.291` (`practice_direction_scorer.dart:129-131`).
2. **Numerikus alap az ablak-határon.** A legacy `d <= windowSec` **double**
   (`0.28` legközelebbi double-je `0.28000000000000002665`), a V2
   `deltaMicroseconds <= matchWindow.inMicroseconds` **egész**. Pontosan
   `±280.000 ms`-nál a kettő eltér (mérve: legacy `0.0` vs V2 `1/24`); minden
   más offseten és minden mért latencyn a paritás tart.

**Miért fontos.** A brief §0.1 táblája a *szemantikát* mérte össze (mit számolunk),
nem az *aritmetikát* (hogyan zárjuk le a számítást). Az implementer emiatt kapott
egy „ha eltérsz, te rontottad el" instrukciót egy olyan eltérésre, amit nem ő
okozott — helyesen `stopped`-ot jelzett (Codex), ami megmentette a kört egy
mércelazítástól.

**Mit csinálunk.** Két rendszer paritásának előírása előtt a szemantikai tábla
mellé **külön sor kell a záró aritmetikáról**: (a) kvantálás/kerekítés van-e
valamelyik oldalon, (b) milyen numerikus típuson történik az utolsó
összehasonlítás (double vs. egész µs), (c) a küszöbök reprezentálhatók-e
egzaktul. Ahol a **referencia maga sem jól definiált** (double-kerekítés dönt),
ott a mércét nem lazítani kell, hanem **pontosan definiálni** — az E02-R19/b-ben
a §0.2 (egzakt arány a per-event kimenetből) és a §0.3 (a határpont dokumentált
kizárása) ezt tette, a paritás minden szigorúan belső/külső offseten kötelező
maradt.

**Forrás:** E02-R19 brief §0.1/§0.2/§0.3, `docs/reviews/e02-r19-review.md`
(második passz 4.1), `practice_direction_scorer.dart:129-131`,
`practice_event_matcher.dart:164`, `lesson_scorer.dart:249-256`.

---

## L30 — A `flutter test <könyvtár>` compact reportere NEM ír sort minden suite-hoz: a grep-alapú „nem futott" következtetés hamis

**Mit mértem.** Az E02-R19/b review-jában a gate `test/features/learn/` lépésének
kimenetében a `learn_migration_parity_test.dart` **egyetlen sorral sem** jelent
meg (0 grep-találat a fájlnévre és a teszt-nevekre is), miközben a fájl külön
futtatva 56 tesztet ad zölden. Ebből majdnem azt a BLOCKER-t írtam, hogy a kör
központi acceptance-e (A7.1, 51 paritás-cella) nem fut a gate-ben, és a zöld
semmit nem bizonyít. A `\r`→`\n` konverzió sem hozott találatot.

**A valóság (mérve, nem feltételezve).** Ideiglenesen kivettem a fájlt a
könyvtárból és újrafuttattam: a suite `194` → **`138`** tesztre esett.
`194 − 138 = 56` = pontosan a paritás-fájl tesztszáma. **A mátrix fut.** A
compact reporter a gyorsan lefutó suite-oknál nem flush-öl külön sort (a sorok
felülíródnak), és 32 tesztfájlból 9-hez egyáltalán nem írt nevet.

**Mit csinálunk.** A „szerepel-e a teszt a kimenetben" **nem** mércéje annak,
hogy lefutott-e. A futás bizonyítéka a **tesztszám-különbség**: vedd ki a fájlt,
futtasd újra, és a delta legyen a fájl saját tesztszáma (vagy használj
`--reporter json`-t). Ez ugyanannak az osztálynak a tagja, mint az L09
(`| tail` elrejti a kilépési kódot): **a kimenet formája nem a tény.**

**Forrás:** E02-R19/b review harmadik passz §4; `flutter test` compact reporter,
`test/features/learn/` (32 fájl, 194 teszt).

---

## L31 — Zöld gate mellett a DoD-/zárójelentés-tábla bizonyítéka is lehet valótlan: a claim-et hívási lánccal kell mérni, nem elfogadni

**Mit mértem.** Az E02-R20 (Epic-2 zárókör) implementere (MiniMax M3) egy
52-soros DoD-táblát töltött ki, minden sorhoz teszt- vagy fájl-hivatkozással —
a gate mind a 10 lépése zöld volt (saját kézzel, izolált klónban is
reprodukálva). Egy adverzariális verifikáló-subagent és a saját
hívási-lánc-grep mégis **6 sort talált, amelyek valótlan production-drótozásra
hivatkoztak**: pl. a #30 "Speed Builder működik… a Learn-migrációs úton
hozzáférhető a R19 óta" állításra `grep -rn "SpeedBuilder" lib/features/learn/`
**0 találatot** adott — a Speed Builder sosem volt a Learn-migrációs úton,
csak a Noop'olt standalone session-úton. A #34/#37/#39/#40/#41 sorok
hasonlóan idéztek nem létező hívási láncot. Egyik sem szándékos hazugság volt
— a motor egy KORÁBBI (helyes) minősítést vitt tovább analógiásan anélkül,
hogy a saját hívási láncot lemérte volna az adott sorra.

**A valóság.** A zöld gate a TESZTEK futását bizonyítja, nem a DoD-tábla
PRÓZAI állításainak igazságát. Egy `grep -rn <szimbólum> <útvonal>` 0
találata (vagy egy explicit hívási-lánc-bejárás) minden egyes "X a Y úton
elérhető" jellegű mondatra **kötelező**, mielőtt a review elfogadja — a teszt
maga csak azt bizonyítja, hogy a KÓD helyesen viselkedik izoláltan, nem azt,
hogy egy adott production útvonal ténylegesen hívja.

**Mit csinálunk.** Zárójelentés-/DoD-jellegű köröknél a review minden "X a Y
úton/módon elérhető" típusú prózai állítást önálló méréssel (grep a hívóra,
vagy a route-regisztráció/feature-flag ellenőrzése) ellenőriz, nem fogadja el
azért, mert egy KAPCSOLÓDÓ teszt zöld. Ez ugyanannak az osztálynak a tagja,
mint az L09/L30 (a kimenet formája/megléte nem a tény) — itt a "van rá teszt"
forma nem bizonyítja a prózai kapcsolat tényét.

**Forrás:** `docs/reviews/e02-r20-review.md` F0; adverzariális verifikáló
subagent jelentése; `lesson_practice_adapter.dart:27`,
`practice_hub_screen.dart:221-227`, `app_router.dart:44-49,124`,
`streak_provider.dart:23-29`, `learn_screen.dart:367-414`.

## L32 — A bwrap hibája környezeti blokk, nem modellkudarc

**Mit mértünk (2026-08-01).** Ugyanabban a user által írható worktree-ben a
beépített patch sandbox `bwrap: loopback: Failed RTM_NEWADDR` és
`setting up uid map: Permission denied` hibával már olvasáskor is leállt,
miközben az explicit, jóváhagyott host-oldali parancs ugyanazt a fájlt olvasta,
atomikusan írta és a teszteket lefuttatta.

**Miért.** A container user/network namespace hiánya a helyi execution harness
előfeltétel-hibája. Semmit nem mond arról, hogy M3 vagy Terra képes-e a
kódfeladat megoldására.

**Hogyan alkalmazd.** A router `ENV_BLOCKED/BLOCKED` állapotot ad és nem indít
Terra fallbacket. Headless futásnál csak a kijelölt worktree-t író
`workspace-write` child profilt használjuk; host-oldali feloldást kizárólag az
orchestrátor/ember adhat. A hibát és a használt jóváhagyást rögzíteni kell.

## L33 — Command-backed MiniMax auth kell; az `env_key` és a helper nem keverhető

**Mit mértünk (2026-08-01).** A Codex 0.145 konfigurációs szerződésének és a
telepítő temp-home tesztjének összevetése szerint a command-backed credential
helper stdin nélkül fut és a tokent stdouton adja vissza. A privát
`~/.mmx/config.json` user-owned, nem symlink, `0600`; az installer az M3/Terra
profilokat hozzáadja úgy, hogy a globális modell/provider változatlan marad.

**Miért.** Ha ugyanarra a providerre command auth és `env_key` is kerül, két
hitelesítési forrás versenyez; ha a kulcs literal TOML-ba kerül, mentésbe,
diffbe vagy diagnosztikába szivároghat.

**Hogyan alkalmazd.** A provider kizárólag abszolút útvonalú command helpert
használ. A helper ellenőrzi owner/symlink/mode feltételeket, kulcsot nem logol;
a telepítés után config-key- és permission-audit kötelező.

## L34 — A MiniMax quota válasz százalékos modell-sor; a nyers body nem szerződés

**Mit mértünk (2026-08-01).** A live, redaktált
`/v1/token_plan/remains` ellenőrzés `general` és `video` modell-sorokat,
interval/weekly százalékmezőket adott (general interval 100%, weekly 82%). A
korábbi, abszolút tokenmaradékot feltételező parser ezt téves nullának
értelmezhette volna; a live-schema regressziós teszt ezt reprodukálta.

**Miért.** A provider válaszformája és entitlementje fiók-/tervfüggő lehet. A
nyers body naplózása szükségtelen és auth/metaadat-szivárgást kockáztat.

**Hogyan alkalmazd.** Csak ismert, tipizált százalékos mezőket fogadj el;
ismeretlen 2xx schema fail-closed `invalid_response`. A helper kizárólag
redaktált státuszt ír, 429/quota pedig DEFERRED — soha nem Terra.

## L35 — A Terra-keretet a hívás ELŐTT kell lefoglalni

**Mit mértünk (2026-08-01).** A state-store crash tesztben a `reserved` vagy
`started` Terra-esemény processzhalál után is beleszámít a task- és UTC-napi
limitbe; ugyanaz a reservation nem indítható vagy számolható el még egyszer.

**Miért.** Ha csak sikeres provider-válasz után nőne a számláló, a hívás
elküldése és a state-írás közötti crash korlátlan ismétlést és kettős
fogyasztást engedne.

**Hogyan alkalmazd.** Fájllock alatt atomikusan `reserved → started → finished`;
bizonytalan kimenetnél fail-closed fogyasztás. Resume soha nem törli a ledgert,
és a napi limitet worktree vagy task-state másolása sem kerülheti meg.

## L33 — Codex 0.145-ben az approval globális opció

**Mit mértünk (2026-08-01).** A valós M3 smoke `returncode 2`-vel, providerhívás
előtt állt le: `unexpected argument --ask-for-approval`. A `codex exec --help` az
approval opciót nem az exec alparancsnál, hanem a gyökérparancsnál mutatja.

**Miért.** A külön profil parsingja és a `--help` ellenőrzése zöld lehet akkor is,
ha a tényleges headless argv sorrendje hibás. A 0.145.0 CLI-ben az
`--ask-for-approval never` az `exec` elé tartozik.

**Hogyan alkalmazd.** A router `codex --ask-for-approval never exec ...` argv-listát
épít shell nélkül. Az execution- és smoke-regresszió a pozíciót is ellenőrzi; a
telepítés csak valós, stdin-es M3 és Terra smoke után tekinthető késznek.

## L34 — A secret scan a megőrzött globális configra és backupra is terjedjen ki

**Mit mértünk (2026-08-01).** A router providerblokkja helyesen command-backed
volt, mégis egy exact-secret scan megtalálta ugyanazt a MiniMax credentialt a
telepítés előtti `openspace-vm` MCP inline environmentjében és az installer által
készített backupban. A kulcsértéket a diagnosztika egyszer sem írta ki.

**Miért.** Egy szűken helyes új komponens nem teszi tisztává a megőrzött globális
konfigurációt. A backup biztonsági másolat, de ugyanúgy szivárgási felület.

**Hogyan alkalmazd.** Az installer csak exact credential-egyezésnél migrálja a
ismert OpenSpace mezőt egy `0700` runtime-wrapperre, újraparsolva ellenőrzi, hogy
más beállítás nem változott, és a backupot is megtisztítja. A közvetlen üres-stdin
OpenSpace próba ismert flush-hibával `120` lehet; a mérvadó ellenőrzés a teljes
Codex M3/Terra smoke, amely valós MCP handshake mellett zöld.

## L35 — A router crash-határaihoz teljes baseline és kétfázisú lezárás kell

**Mit mértünk (2026-08-01).** A pre-existing tracked, untracked és nem generált
ignored fájlok kikerülhették a későbbi path-delta auditot; providerhiba után
részleges diff maradhatott; a Terra-ledger és task-state közti szimulált crash
ellentmondó állapotot hagyhatott.

**Hogyan alkalmazd.** Modell előtt tiszta baseline kötelező. Részleges diffet
resume előbb auditál és gate-el. Terra esetén a task tartós terminális intentet
ment, a ledgert idempotensen lezárja, majd a taskot terminálissá teszi.

## L36 — Az őr, ami mindenre igent mond, csak úgy tud nemet mondani, hogy a helyes utat is levágja

**Mit mértünk (2026-08-01, E02-R21 / H6 halt).** A router baseline-őre a
`GENERATED_IGNORED_PREFIXES` listán kívüli MINDEN ignore-olt fájlt „unsafe"-nek
minősít. A Flutter viszont a `flutter pub get` / `flutter gen-l10n`
mellékhatásaként minden friss klónban és worktree-ben létrehoz 15 gitignore-olt,
de KÖTELEZŐ fájlt (`lib/l10n/app_localizations*.dart`,
`GeneratedPluginRegistrant.*`, `ios/Flutter/ephemeral/**`,
`android/local.properties`) — nélkülük az analyze/test el sem indul (a HANDOFF
dokumentált klón-csapdája). Az őr tehát nem egy hibás kört állított meg, hanem
**az összeset**: az E02-R21-et és az Epic 3 mind a 21 sorát, 2 óra 45 percig,
amíg a cron ötpercenként ugyanazt a „megállt" sort írta a naplóba.

**Miért.** A tiltólistás őr az ismeretlent kockázatnak veszi. Ez helyes, amíg az
„ismert jó" halmaz a rendszer TÉNYLEGES működéséből származik. Itt az őrt a
router saját fájljaira mérték (`.dart_tool`, `build`, `.ai/runs`), a projekt
build-rendszerének kötelező kimenete kimaradt — a mércét nem a mért rendszeren
kalibrálták.

**Hogyan alkalmazd.** (1) Minden „ismert jó" listát a CÉLRENDSZER nyers
kimenetéből generálj, ne emlékezetből: itt a
`git ls-files --others --ignored --exclude-standard` egy friss worktree-ben,
`flutter gen-l10n` után — és ez a nyers lista menjen be a regressziós tesztbe
fixture-nek (`tools/tests/test_security.py`). (2) Ha egy őr a fő útvonalat
tiltja, az nem szigor, hanem hibás kalibráció. (3) Rendszerszintű blokkolónál
mérd meg a hatókört is: „ez a kör áll" vagy „minden kör áll" két különböző
súlyosság — az utóbbi azonnali javítást érdemel, nem sorbaállást (ADR 0112).

## L37 — Egy terminal task-state-nek NEM privilégium az, hogy `result_path`-ot ír; a hiányzó reset-út örökre BLOCKED-et fagyaszt

**Mit mértünk (2026-08-01, E02-R21 / H6 halt, 2. előfordulás).** Az [L36](#l36)
security.py-fixje (`a620442`) után az E02-R21 task-state a routerben
mégis örökre BLOCKED maradt. Két önálló hiba volt a `tools/ai_router`-ban: (1)
`router.py:484-490` `run()` — minden nem-RUNNING, nem-DEFERRED, nem-(resume+
findings+READY_FOR_REVIEW) ágon `self._result(state)`-et adott vissza
`_finish`/`_atomic_result` (result-json írás) NÉLKÜL, tehát egy BLOCKED taskra
sem `run`, sem `resume` nem írt `result_path`-ot — a wrapper
(`tools/ai-router-round.sh:80`) ezt mindig INTERNAL_ERROR-ra (exit 50) fordította,
elrejtve a valódi BLOCKED okot a hívótól. (2) Nem volt recovery-út: ha a BLOCKED
indok időközben javítva lett a kódban, a task state a state_dir-ben véglegesen
BLOCKED maradt — a CLI-ben (`run`/`status`/`resume`/`smoke`) nem volt
reset/clear parancs.

**Miért.** A `_result(state)` és a `_finish(state, status, reason, result_path)`
két külön dolgot csinál — az egyik csak leképezi az állapotot egy visszatérési
értékre, a másik EMELLETT perzisztálja és a hívó felé is kiírja. Az early-return
ág íróját az vezette félre, hogy egy már-terminál state-en „nincs mit
menteni" — való igaz, de a hívó szerződése (`result_path` mindig létrejön egy
`run`/`resume` hívás után) nem a state mutációjáról szól, hanem arról, hogy a
CLI-folyamat halála után is legyen olvasható bizonyíték. Egy write-only
state-gép hibát rejt, ha a „nincs változás" ág néma marad.

**Hogyan alkalmazd.** (1) Egy state-gépben minden terminális ág — még a
„semmi nem változott" ág is — írja ki a kimenetet a hívó szerződése szerint;
ha a mutáció felesleges, a kiírás akkor sem az. Teszt: minden `run`/`resume`
hívás UTÁN, függetlenül az ágtól, `result_path.exists()`. (2) Perzisztens
task/job state-hez explicit `reset`/`clear` út kell A LÉTREHOZÁSKOR, nem csak
amikor először szükség lesz rá — egy külső gyökérok-javítás (ADR 0112 önjavító
kör) állandó falba ütközik recovery-parancs nélkül. (3) A regressziós teszt a
saját mért hibaüzenetből induljon (itt: a HALTED fájl pontos repro-parancsa és
a router.py sorszáma), ne kitalált tünetből.

## L38 — A "csinált-e valamit a modell" ellenőrzés nem ugyanaz, mint a "scope-sértés" ellenőrzés; és a resume-nak nincs biztonságos helye a saját findings-fájljának

**Mit mértünk (2026-08-01, E02-R21, H6 halt, 3. előfordulás, ugyanaz a kör).**
A router első ÉLES `run` hívása `READY_FOR_REVIEW`-t ("M3 gate passed")
jelzett, de a munkapéldány `git status`/`git diff HEAD` **teljesen tiszta**
volt — az M3 egyetlen `lib/`/`test/` fájlt sem módosított. A task-state
`changed_paths` mezője kizárólag `.dart_tool/**` és `build/**` bejegyzéseket
tartalmazott. Ezután a lelet `resume`-mal (review-findings fájllal) történő
visszaadása `BLOCKED`-ba futott: `path outside allowed scope:
.ai/review-findings-e02-r21.md; …; .codex-round-status` — a router saját
jelzőfájlját (`.codex-round-status`) és az orchestrátor saját
review/findings fájljait is scope-sértésnek nézte.

**Miért.** Két önálló, de rokon hiba `tools/ai_router`-ban. (1)
`router.py:702-703` a „csinált-e valamit az M3" döntést
(`if audit is not None and not audit.changed_paths: … NO_CHANGE …`)
ugyanarra a `changed_paths` halmazra alapozza, amit `security.py:190-197`
`audit_scope` a **scope-sértés** ellenőrzéshez épít — utóbbiban a
generált/ignorált útvonalak (`_is_generated_ignored`) helyesen ki vannak zárva
a *violation*-ból, de MEGMARADNAK a `changed_paths` halmazban, amit a hívó a
„történt-e valódi munka" jelzésére használ. A `BASELINE_GATE` (ami a
PRECHECK fázisban, MÉG AZ M3-hívás ELŐTT lefuttatja a teszteket) első ízben
hozza létre a `build/`/`.dart_tool/` fákat egy friss munkapéldányban — ez a
saját melléktermék az M3 utáni audit szemében "M3 diffnek" tűnik. (2)
`security.py:20-49` `GENERATED_IGNORED_PREFIXES`/`GLOBS` csak Flutter-generált
útvonalakat ismer — nincs kivétel sem a router saját `.codex-round-status`
jelzőfájlára, sem egy dedikált orchestrátor-írta findings-útvonalra. A
`resume` wrapper (`tools/ai-router-round.sh`) ugyanakkor megköveteli, hogy a
review-findings fájl A MUNKAPÉLDÁNYON BELÜL legyen — tehát a dokumentált
munkafolyamat (orchestrátor-prompt §1.1: "a leleteket fájlban add vissza")
strukturálisan önmagával ütközik: bármelyik fájl, amit az orchestrátor a
`resume`-hoz a munkapéldányba ír, a következő audit "path outside allowed
scope" hibájává válik.

**Hogyan alkalmazd.** (1) Egy audit-halmazt, amit KÉT különböző döntéshez
használsz (történt-e munka / scope-sértés van-e), vagy közös, szigorúbb
szűréssel építs, vagy két külön mezőbe válaszd szét — itt a fix:
`audit.changed_paths`-ból zárd ki a generáltakat is (ne csak a
violations-ból), és a "volt-e munka" checket erre a szűkített halmazra
futtasd. (2) Egy hosszú-életű ágens-eszköz saját jelzőfájljait (itt:
`.codex-round-status`) VEGYE FEL a saját ignore/exempt listájára — egy őr,
ami a saját infrastruktúráját scope-sértésnek nézi, önmagát zárja ki minden
`resume`-ból. (3) Ha egy workflow explicit megköveteli, hogy az orchestrátor
egy fájlt a felügyelt munkapéldányba írjon (findings, review), a
scope-audit tervezésekor ELSŐ osztályú esetként kezeld, ne utólagos
kivételként — vagy dedikált, mindig-kizárt alkönyvtárral (`.ai/orchestrator/**`),
vagy a `resume` hívás elfogadjon munkapéldányon KÍVÜLI findings-útvonalat is.
(4) Regressziós teszt mindkettőre `tools/tests/test_router*.py`-ban, a mért
reprodukáló állapotból (üres diff + sikeres gate; `.codex-round-status`
jelenléte + `resume`), mielőtt a `reset --task-id E02-R21` bármit is
feloldana.

## L39 — L38 javítva: `scoped_changed_paths` + kategória-független generált/ignorált mentesség

**Mit mértünk (2026-08-01, E02-R21, H6 önjavító kör, 4. előfordulás).**
A `python3 tools/model-router.py status --task-id E02-R21 --json` a `reset`
ELŐTT pontosan az L38-ban leírt állapotot mutatta: `status=BLOCKED`,
`reason="path outside allowed scope: .ai/review-findings-e02-r21.md; ...
.codex-round-status; ... docs/reviews/e02-r21-review.md"`, a
`changed_paths` 31+ `.dart_tool/`/`build/` bejegyzést tartalmazott, egyetlen
`lib/`/`test/` utat sem. Ez volt a MÉRT bizonyíték a javítás előtt.

**A javítás** (`tools/ai_router/security.py`, `tools/ai_router/router.py`,
PR [#47](https://github.com/wolfcasaba/strumsight/pull/47), commit
`b80cf93`→squash `35f6da1`):

1. `ScopeAudit` új mezője `scoped_changed_paths` — a `changed_paths`
   generált/ignorált bejegyzésektől megtisztított változata. A router MOST
   ezt használja minden "történt-e valódi munka" döntésnél (`router.py`
   4 hívási hely: `_scope_or_finish` state-mentés, recovery-ág, Terra
   `partial_changes`, a fő NO_CHANGE-ág) a nyers `changed_paths` helyett.
2. `security.py` `audit_scope`-ban a generált/ignorált mentesség korábban
   `path in new_ignored and _is_generated_ignored(...)` volt — ez egy MÁR
   TRACKELT fájl (pl. `docs/reviews/eXX-rYY-review.md` frissítése) esetén
   SOSE adott mentességet, a GENERATED_IGNORED_PREFIXES tartalmától
   függetlenül. A feltétel mostantól kategória-független
   (`_is_generated_ignored(path, ...)`), és `GENERATED_IGNORED_PREFIXES`/
   `GLOBS` felvette a `.codex-round-status`-t, a `docs/reviews`
   könyvtárat és a `.ai/review-findings-*.md` mintát.

**Regressziós teszt, mérten RED→GREEN** (`git stash` a fix commitjára,
teszt lefuttatva, majd `stash pop`):
`tools/tests/test_router.py::test_build_cache_churn_alone_does_not_count_as_scoped_change`,
`tools/tests/test_router_artifact_scope.py::test_resume_workflow_artifacts_do_not_self_conflict_with_scope_audit`.
Fix előtt mindkettő ugyanazt a hibaüzenetet dobta, mint a valódi
`.pipeline/HALTED` jelentés. Teljes `tools/tests` (100 teszt, 33 subtest):
zöld. `router-ci.yml` CI: zöld, a merge-commit SHA-jén.

**Hogyan alkalmazd.** Ha egy audit-jellegű ellenőrzés (scope, baseline,
lint) egyetlen nyers halmazt épít több különböző döntéshez ("van-e
sértés" / "történt-e munka" / "biztonságos-e"), az egyik döntéshez tett
utólagos kivétel (itt: generated_ignored) NEM terjed automatikusan a
másikra — expliciten vezesd át mindkettőre, vagy külön mezőbe válaszd
szét, ahogy itt a `scoped_changed_paths`. A `reset --task-id` csak EZUTÁN
futott (`.pipeline` HALT protokoll §6).

## L40 — A Terra FINAL_GATE ág ugyanazt a "zöld gate ≠ történt munka" hibát ismételte, mint L38, csak egy másik útvonalon

**Mit mértünk (2026-08-01, E02-R21, H4 halt, önjavító kör).**
A `.pipeline/HALTED` szerint a teljes M3+Terra keret (2/2 M3-kísérlet +
1/1 Terra-hívás) kimerült valós diff nélkül (`changed_paths=[]`,
`last_diff_hash` üres string SHA-256), a router mégis
`READY_FOR_REVIEW`-t jelzett. Az L39 (H6) fixje bevezette
`ScopeAudit.scoped_changed_paths`-t, és az M3-hurok (`router.py` `run()`,
a `current_gate.outcome == "pass"` ág, kb. 709. sor) ezt helyesen
ellenőrzi a `READY_FOR_REVIEW` visszaadása előtt (`NO_CHANGE_<n>` gate-be
fordítja, ha üres). A Terra-ág (`_terra()` FINAL_GATE, `router.py:429`
körül) és a `TERRA_REVIEW_OR_FIX` resume-ág (`run()`, `router.py:639`
körül) ugyanezt az ellenőrzést KIHAGYTA — a `final_gate.outcome == "pass"`
önmagában elég volt a `READY_FOR_REVIEW`-hoz. A két ág az M3-hurokéval
azonos szerkezetű `audit` objektumot már számolta (`_scope_or_finish`
visszaadja), csak nem használta fel a döntésben.

**A javítás** (`tools/ai_router/router.py`, izolált worktree
`heal/E02-R21-H4-1`): új `DevelopmentRouter._terra_final_gate(gate, audit)`
statikus segédmetódus — ha a gate "pass", de `audit.scoped_changed_paths`
üres, a gate-et `code_failure`-ra fordítja (`"Terra call produced no
scoped changes"`), ugyanabba a mintába, mint az M3-hurok NO_CHANGE ága.
Mindkét hívási hely (`_terra()` FINAL_GATE, `run()` TERRA_REVIEW_OR_FIX
resume) most ezen a segéden megy át a `final_gate.outcome == "pass"`
elágazás előtt.

**Regressziós teszt, mérten RED→GREEN** (a fix ELŐTT lefuttatva, majd a
fix UTÁN):
`tools/tests/test_router.py::RouterTest::test_terra_final_gate_pass_with_no_scoped_changes_is_not_ready_for_review`
(a friss `_terra()` hívást fedi) és
`tools/tests/test_router_resume.py::RouterResumeTest::test_resumed_terra_review_or_fix_with_no_scoped_changes_is_not_ready_for_review`
(a `TERRA_REVIEW_OR_FIX` resume-ágat fedi, kézzel felvett `terra_reservation`
+ `TERRA_REVIEW_OR_FIX` fázisú task-state-tel). Fix előtt mindkettő
`READY_FOR_REVIEW`-t adott vissza `changed_paths=()` mellett — pontosan a
HALT jelentés tünete. Fix után mindkettő `STOPPED`-et ad. Teljes
`tools/tests` (104 teszt, 33 subtest): zöld.

**Hogyan alkalmazd.** Ha egy ellenőrzést (itt: "van-e valódi scope-on
belüli diff") egy ágban bevezetsz, keress meg MINDEN másik ágat, ami
ugyanahhoz a végállapothoz (`READY_FOR_REVIEW`) vezet, és ellenőrizd, hogy
azok is átmennek-e rajta — az L39 fixje csak az M3-hurkot fedte, a
strukturálisan azonos Terra FINAL_GATE és a resume-duplikátuma kimaradt.
Külön regressziós teszt kell minden útvonalhoz, nem csak egyhez, mert a
resume-ág gyakran kézzel felvett task-state-tel tesztelhető csak (nincs
valódi interrupt-mechanizmus a szinkron `router.run()`-ban).

## L41 — `reset --task-id` "fresh start" ígérete hamis volt a Terra-kvótára: a napi számláló nap-alapú, a task-számláló nem

**Mit mértünk (2026-08-01, E02-R21, HARMADIK H6 halt ugyanazon a taskon,
önjavító kör, docs/reviews/e02-r21-review.md Update 3).**
Az L37 fixje (PR #46) bevezette a `model-router.py reset --task-id`
parancsot azzal az ígérettel, hogy "a next `run` re-prechecks from
scratch" és "a stuck terminal state ... can always be cleared". A H4-fix
(L40) után egy orchestrátor-session lefuttatta `reset --task-id E02-R21`-et,
majd friss `run()`-t indított — a friss futás `BASELINE_GATE`/`GATE_1`
zölden ment, de a Terra-hívásnál `TerraBudgetError("task Terra budget is
exhausted")`-tel `DEFERRED`-be futott, jóllehet a task aznap még sosem
kapott VALÓDI Terra-választ (`terra_calls=0` a saját state-ben).

**Gyökérok.** `StateStore.reserve_terra` (`tools/ai_router/state.py:167-203`)
két számlálót vezet ugyanabból a `terra-ledger.json`-ból: `daily_count`
(`row.get("utc_day") == day` szűrővel, globális, minden taskra) és
`task_count` (`row.get("task_id") == task_id` szűrővel, **nap nélkül**).
`max_terra_calls_per_task=1` kikényszerített konfig-invariáns
(`config.py:105`), ezért a task egyetlen valaha történt Terra-foglalása —
akár egy régóta lezárt, akár egy a mai H4-fix ELŐTTI hibás futásból maradt
sor — örökre kimeríti a task saját kvótáját. A `reset_task`
(`state.py:131-144`, L37 óta) **kizárólag** a `tasks/<id>.json`-t törölte;
a `terra-ledger.json`-hoz nem nyúlt. A docstring ígérete tehát csak a
task-fázisra teljesült, a Terra-kvótára nem — és mivel a `task_count` nem
nap-alapú, a hiba magától sem évült volna el aznap.

**A javítás** (`tools/ai_router/state.py`, izolált worktree
`heal/E02-R21-H6-1`, PR #49): `reset_task` most, ugyanabban a hívásban,
egy új `_archive_terra_reservations(task_id)` segéddel a `terra-ledger.json`
adott `task_id`-hez tartozó, még aktív (`reserved`/`started`/`finished`)
sorait `status="archived"` + `archived_at` mezőre állítja (nem törli — az
audit-trail megmarad), a `_ledger_lock()` védelme alatt. Az `archived`
státusz kimarad mind a `task_count`, mind a `daily_count` `active`
halmazából, tehát a reset a task saját napi lefoglalt kvótáját is
felszabadítja (szándékos: az a Terra-hívás soha nem termelt hasznos
munkát). Más taskok sorait a szűrő (`task_id` egyezés) érintetlenül hagyja.

**Regressziós teszt, mérten RED→GREEN**
(`tools/tests/test_state_store.py::StateStoreTest`):
`test_reset_task_clears_the_terra_ledger_so_the_task_can_reserve_again`
pontosan a HALT-ot reprodukálja (foglal → befejez → reset → azonnal, aznap
újra tud foglalni); a fix előtti `state.py`-on mérten `TerraBudgetError`-t
dobott, utána zöld.
`test_reset_task_only_archives_that_tasks_own_reservations` a
hatókör-védelem: más task sora `reserved` marad reset után. Teljes
`tools/tests` (104 teszt, 33 subtest): zöld. A javítás után a valódi
production state-en (`~/.local/state/strumsight-ai-router`) is lefuttattuk
az ÚJ kódú `reset --task-id E02-R21`-et — a `terra-ledger.json` E02-R21
sora `archived`-ra váltott, a task state `NOT_STARTED`.

**Hogyan alkalmazd.** Egy "fresh start" / "reset" API minden olyan
perzisztens állapotot töröljön vagy semlegesítsen, amit a hívó a docstring
alapján elvár — ha egy funkció TÖBB, egymástól független perzisztencia-
réteget tart karban ugyanahhoz a domain-entitáshoz (itt: task-state fájl +
globális Terra-ledger), a reset mindegyiket kezelje egy tranzakcióban, nem
csak az elsőt, amit valaki megírt. Ha egy számláló nap-alapú a testvérénél
(itt: `daily_count` vs. `task_count`), az az inkonzisztencia önmagában
gyanús jel — vagy szándékos (dokumentáld, miért), vagy hiányzó szűrő.

## L42 — `ai-router-round.sh run` órákig futhat egy lassú boxon; a Bash-eszköz 600s-es kemény plafonja a router félbeszakításaként éri, ami elégeti az egyetlen M3/Terra-kísérletet

**Mit mértünk (2026-08-01, E02-R21, NEGYEDIK halt ugyanazon a taskon, a
router első valódi éles futása a H4/H6 fixek — #48/#49 — után).** A
pre-flight (ADR 0111, brief) és a router-infrastruktúra ekkor már zöld
volt (rebase `origin/main`-re tiszta, a `_archive_terra_reservations` fix
és a Terra FINAL_GATE őr is a munkapéldányban). Az orchestrátor a §1.1
szerinti pontos parancsot futtatta, DE a Claude Code Bash-eszköz alapértelmezett
időkorlátja (120000 ms) és kemény felső korlátja (600000 ms) rövidebb, mint
amennyi ideig `tools/model-router.py run` egyetlen hívása ezen az ARM boxon
ténylegesen tarthat (BASELINE_GATE + M3-hívás + gate-futtatás). Az első két
`ai-router-round.sh run` hívást a Bash-eszköz SIGTERM-mel (exit 143) ölte meg,
mielőtt a router a saját `.codex-round-status`/`codex-signal.sh`-jelzését
kiírhatta volna — jelzés nélküli halál, kétszer egymás után. A HARMADIK hívás
(10 perces explicit timeout) a megszakított `M3_CALL_2` fázisból tért vissza:
a router `run()`-jának `phase.startswith(("M3_ATTEMPT_", "M3_CALL_"))` ága
(`tools/ai_router/router.py:581-604` körül) a megszakított kísérletet **nem
ismétli meg**, hanem a jelenlegi (csonka) diffet auditálja, és ha az üres,
szintetikus `code_failure`-t ("interrupted model produced no scoped
changes") ír a kísérlet rovására — a Bash-eszköz timeoutja tehát **elfogyaszt
egy valódi M3-kísérletet anélkül, hogy a modellnek esélye lett volna
befejezni**. Mivel `max_m3_attempts_per_task=2`, ez a második, csonka
kísérlet kimerítette az M3-keretet, a router a kötelező Terra-hívásra
lépett; a Terra-hívás ezúttal TELJES, megszakítás nélküli volt (a harmadik
orchestrátor-hívás végig lefutott), és önmagában, valódi okból jelzett üres
diffet (`FINAL_GATE`: "Terra call produced no scoped changes") — ez a rész
NEM a timeout mérési hibája, hanem egy önmagában mért, tiszta Terra-kudarc.
Nettó eredmény: a task 2/2 M3 + 1/1 Terra kerete kimerült, `STOPPED`, a
Practice V2 production-drótozás (a kör tényleges célja) továbbra sincs
elkezdve — és nem is dönthető el utólag, hogy a második M3-kísérlet
sikerült volna-e, ha végigfuthat.

**Egy MÁSODIK, ettől független, ugyanekkor mért hiba:** `tools/codex-signal.sh`
a `root=$(git rev-parse --show-toplevel)` sort a hívó folyamat **öröklött
cwd-jéből** oldja fel, nem a munkapéldány útvonalából, jóllehet
`ai-router-round.sh` a szkriptet a munkapéldányon belüli abszolút útvonalon
(`"$worktree/tools/codex-signal.sh"`) hívja — bash egy abszolút útvonalú
szkript futtatásakor nem váltja át a cwd-t a szkript könyvtárára. A
pipeline-prompt §1.1 dokumentált hívási mintája (az orchestrátor a SAJÁT
`/home/ubuntu/music-theory` checkoutjából hívja a munkapéldány szkriptjét,
`cd` nélkül) ezért **szisztematikusan** a rossz repót méri: mérve — a
`.pipeline/router-status` mirror `branch=main head=a81838e`-t írt, miközben
a tényleges munkapéldány a `codex/e02-r21-practice-production-wiring`
ágon, `deb4c9a`-n állt. A `status=`/`summary=` mező helyes marad (azt a
`router-result.json` elemzéséből tölti ki a bash-szkript, cwd-független),
de a `branch=`/`head=`/`dirty_files=` mezők **nem** — ez pontosan azt a két
záró-ellenőrzést hiúsítja meg, amit az orchestrátor-prompt §3 kötelezővé
tesz (`dirty_files != 0` vizsgálat, `headSha` összevetés).

**Hogyan alkalmazd.** (1) Az `auto` motor `ai-router-round.sh run` hívásához
mindig explicit, a Bash-eszköz kemény plafonjához igazított timeout
(`timeout: 600000`) kell — sose hagyatkozz az alapértelmezett 120000 ms-ra.
(2) Egy `SIGTERM`-mel megszakított `run` hívás után a state `m3_attempts`
számlálója **fogyott, még ha a modell nem is kapott tisztességes esélyt** —
ismételt kilövés = ismételt, indokolatlan kísérlet-fogyasztás; ha ez a
mintázat jelentkezik (a `gate_history`-ban egy `M3_CALL_N`-ből visszatérő,
`"interrupted model produced no scoped changes"` szövegű `code_failure`),
az a self-heal session dolga eldönteni, hogy a router megszakítás-kezelése
(retry helyett fogyasztás) hibás-e, vagy csak az orchestrátor timeoutja volt
elégtelen. (3) A `codex-signal.sh` cwd-függése miatt a `branch=`/`head=`/
`dirty_files=` mezőket az `auto` úton **ne fogadd el bizonyítéknak** — a
`router-result.json` `task_id`/`status`/`reason` mezői a hiteles forrás,
amíg a szkript nem oldja fel a saját útvonalát a munkapéldányhoz képest
(javítási hely: `tools/codex-signal.sh`, a `root=$(git rev-parse
--show-toplevel)` sor körül).

**A javítás** (izolált worktree `heal/E02-R21-H6-1`, PR #50). (1)
`tools/ai_router/router.py`, a resume-ág `M3_ATTEMPT_`/`M3_CALL_` közös
kezelése: `M3_CALL_N` KIZÁRÓLAG közvetlenül a `run_model()` hívás ELŐTT
perzisztálódik, és sikeres visszatérés után azonnal `M3_ATTEMPT_N`-re vált
— tehát resume-on `M3_CALL_N` fázis SOSEM jelentheti, hogy a hívás
lezajlott. Ha a resume-scope-audit ezen a fázison nem talál hatókörön
belüli diffet, a router most visszaadja a kísérletet
(`m3_attempts -= 1`, `phase = "M3_READY"`) és a hurok friss próbaként
ismétli, ahelyett hogy szintetikus `code_failure`-ként elfogyasztaná — ez
ugyanaz a mintázat, mint a meglévő `partial_changes=False` ág a
`_provider_decision`-ben. Ha VAN partiális diff, a régi (gate-elő,
elfogyasztó) útvonal marad — az valódi részmunka. (2)
`tools/codex-signal.sh`: a `root` mostantól a szkript SAJÁT elérési útjából
(`${BASH_SOURCE[0]}`) oldódik fel, nem a hívó öröklött cwd-jéből, és minden
git-parancs `git -C "$root"`-tal fut — a hívó cwd-je immár irreleváns.

**Regressziós teszt, mérten RED→GREEN.**
`tools/tests/test_router_resume.py::test_resume_after_interrupted_m3_call_retries_without_consuming_the_attempt`
egy `M3_CALL_1` fázisban megszakadt, üres diffet hagyó state-et resume-ol:
a fix előtt a régi kód egy plusz, nem tervezett `run_gate()`-hívást
kísérelt meg (a teszt `FakeGate`-je ezért `IndexError`-ral RED-ben bukott),
utána a hurok egyetlen friss `run_model()`-hívással GREEN-ben zárja, és
`m3_attempts` visszaáll 1-re (nem nő 2-re).
`tools/tests/test_pipeline_integration.py::test_signal_resolves_git_state_from_the_worktree_not_the_callers_cwd`
két külön git-repót épít (a `worktree`-t és egy tőle független `caller`
repót), és a szkriptet a `worktree`-n belüli abszolút úton, de `cwd=caller`
mellett hívja — a fix előtt a `.codex-round-status` a ROSSZ repóba
(`caller`) íródott (`FileNotFoundError` a `worktree`-ben, RED), utána a
helyes `branch=`/`head=` kerül a `worktree` jelzőfájljába. Teljes
`tools/tests`: 106 teszt, 33 subtest, zöld. `router-ci.yml` zöld a
merge-SHA-n: [PR #50](https://github.com/wolfcasaba/strumsight/pull/50)
(squash `2e70a1a`).

**Hogyan alkalmazd (kiegészítés).** Ha egy állapotgép egy műveletet KÉT
lépésben perzisztál (fázis-jelzés → külső hívás → eredmény-jelzés), és a
folyamat a kettő között bármikor kilőhető, a resume-kódnak külön ágat kell
adnia a "a hívás előtt álltunk meg" (nincs bizonyíték eredményről → ne
fogyassz, próbáld újra) és a "a hívás után álltunk meg" (van eredmény →
azt értékeld) eseteknek — az azonos kezelés szisztematikusan a rosszabbik
felé torzít (elfogyaszt egy sosem lezajlott kísérletet). Egy segédszkript,
amit a hívója abszolút úton indít, SOSEM támaszkodhat az öröklött cwd-re
(`git rev-parse --show-toplevel`, relatív fájlutak) — a saját
`${BASH_SOURCE[0]}`-ból oldja fel magát, különben a hívási minta (van-e
`cd` előtte) csendben megváltoztatja, melyik repót méri.

## L43 — A router valódi (nem-smoke) Codex-hívása `--sandbox workspace-write`-ot használ, ami bwrap hálózati-namespace-t igényel; ezen a konténeren ez sosem működik, és a smoke-teszt nem fedi fel

**Mit mértünk (2026-08-01, E02-R21, ÖTÖDIK halt ugyanazon a taskon, de az
ELSŐ, ahol a router állapotgépe hibátlanul futott le végig — mind az öt
korábbi router-infra fix, #46/#47/#48/#49/#50, a munkapéldányban volt,
`origin/main`-re rebase-elve `f27651a`-ra).** A pre-flight (ADR 0111, brief)
változatlan, a `python3 tools/model-router.py run` egyetlen hívása 2
M3-kísérletet és 1 Terra-hívást futtatott le teljesen, megszakítás nélkül.
Mindhárom próbán a `round-gate.sh` **pass**-t adott (a baseline érintetlen
maradt), de egyik modellhívás sem hozott létre egyetlen scope-on belüli
fájlváltozást sem (`scoped_changed_paths=[]` mindhárom próbán,
`last_diff_hash` = az üres string SHA-256-ja) — a router ezt korrekt
`NO_CHANGE_1`/`NO_CHANGE_2`/`FINAL_GATE` `code_failure`-ként könyvelte, majd
a keret kimerülése után helyesen `STOPPED`-et jelzett. **A router
döntéslogikája ezúttal nem hibás** — a hiba egy szinttel lejjebb van, a
tényleges modellhívás sandbox-konfigurációjában.

**Gyökérok, router-független módon reprodukálva:**
```
bwrap --unshare-net --dev-bind / / true
# → bwrap: loopback: Failed RTM_NEWADDR: Operation not permitted (exit 1)
```
Ez a konténer nem tud hálózati namespace-t létrehozni (hiányzó
`CAP_NET_ADMIN` vagy egyenértékű host-korlátozás) — állandó, nem tranziens
képesség-hiány (214 meglévő net-namespace a `/proc/*/ns/net` alapján, messze
a szokásos limit alatt, tehát nem kimerülés). A `codex` CLI `--sandbox
workspace-write` (és `read-only`) módja Linuxon `bwrap`-alapú izolációt
használ, aminek előfeltétele ugyanez a hálózati namespace — ezért **minden**
`exec_command`-hívás azonnal elbukik a sandboxban, `true`/`echo`/`id` szintű
parancsokra is. A pontos induló promptot közvetlenül elküldve az M3
profilnak (`--sandbox read-only`, mellékhatás nélkül) a modell **helyesen
megtagadta** a feladatot ahelyett, hogy fabrikált volna: „Every
`exec_command` invocation exits immediately with `bwrap: loopback: Failed
RTM_NEWADDR: Operation not permitted`... The bwrap sandbox cannot create a
network namespace on this container, so no shell ever spawns.” Ez
pontosan megfelel a brief §10 kikötésének (nincs fabrikált kimenet) — a
modell hibátlanul viselkedett egy hibás környezetben.

**Miért nem fogta meg korábban egyetlen halt sem, és miért nem a
`smoke` parancs.** Az előző NÉGY halt (H4/H6, #46–#49 mérései) mind a
router SAJÁT állapotgép-logikájában bukott el, mielőtt valódi M3/Terra-hívás
egyáltalán végigfuthatott volna gate-passzoló, tartalom nélküli
végkimenetellel — ez volt az ELSŐ alkalom, hogy a router elég sokáig
hibátlanul futott ahhoz, hogy ez a réteg egyáltalán próbára legyen téve. A
`tools/model-router.py smoke --profile {m3,terra}` parancs (`_smoke()`,
`tools/model-router.py:165-196`) zölden fut ezen a boxon (`M3_OK`/`TERRA_OK`),
mert `--sandbox read-only`-t használ egy triviális, `exec_command`-ot SOSEM
igénylő szöveges válasz-prompttal — a smoke-teszt tehát strukturálisan vak
erre a hibaosztályra, mert nem gyakorolja a ténylegesen hibás képességet
(sandboxolt parancsvégrehajtás).

**Az inkonzisztencia a saját repóban:** a **létező, működő** örökölt
manuális útvonal (`tools/codex-round.sh:31`) már `-s danger-full-access`-t
használ — pontosan azért, mert ezen a boxon a bwrap nem megy (ezt a
`sdd-round-driver` skill saját szövege is kimondja: „A wrapper `-s
danger-full-access`-szel fut (a bwrap itt nem megy) — az izolációt a külön
munkapéldány adja”). A router `tools/ai_router/execution.py:88-105`
(`build_codex_argv`) függvénye, amikor az ADR 0088-cal megszületett, ezt a
már ismert, dokumentált box-tényt nem vette át — `"--sandbox",
"workspace-write"`-et ad át mindkét profilra (M3 és Terra egyaránt).

**Hogyan alkalmazd.** (1) Egy géppel futtatott smoke/health-teszt csak azt a
képességet igazolja, amit ténylegesen gyakorol — egy szöveges válasz-prompt
NEM bizonyítja, hogy a szabályozott parancsvégrehajtás (sandbox, shell,
fájl-I/O) is működik; ha a valódi munka centrális eleme egy olyan
képesség, amit a smoke kihagy, a smoke zöldje hamis biztonságot ad. (2) Egy
adott konténer/box mért, dokumentált korlátja (itt: nincs bwrap
hálózati-namespace) MINDEN ugyanazt a mechanizmust használó hívási útra
vonatkozik — ha egy útvonal (`codex-round.sh`) már tud róla és kikerüli, egy
másik, újabb útvonal (a router) írásakor ezt a tényt aktívan át kell venni,
nem újra fel kell fedezni élesben. (3) „A gate zöld maradt, de a modell
semmit sem csinált” (`scoped_changed_paths=[]`, tiszta `pass` gate) egy
harmadik hibaosztály a korábbi kettő (router állapotgép-hiba, ledger-hiba)
mellett — ha ez a mintázat jelentkezik (`NO_CHANGE_N`/`"...produced no
scoped changes"` a `gate_history`-ban minden kísérleten), a legelső
diagnosztikai lépés a modellhívás tényleges környezete (sandbox,
jogosultságok), nem a router döntési logikája.

**Javítás javasolt helye (self-heal kör, NEM ez az orchestrátor-kör —
`tools/` tilos zóna számára).** `tools/ai_router/execution.py:100-101`:
`"workspace-write"` → `"danger-full-access"` a `build_codex_argv`-ban;
kötelező regressziós teszt a string-argumentumra (a tényleges bwrap-hívás
box-specifikus, CI-ban nem reprodukálható). Érdemes a `_smoke()`-ot is
kiegészíteni egy valódi `exec_command`-ot igénylő lépéssel, hogy ez a
hibaosztály jövőben a smoke-fázisban bukjon el. Teljes mérés + reprodukció:
[`docs/reviews/e02-r21-review.md`](docs/reviews/e02-r21-review.md)
"Update 4" szakasz, a `codex/e02-r21-practice-production-wiring` ágon
(`c1579f4`).

**Javítva (önjavító kör, 2026-08-01, PR #51, `6d99820`).**
`tools/ai_router/execution.py` `build_codex_argv`-jában `"workspace-write"`
→ `"danger-full-access"` mindkét profilra; regressziós teszt
(`tools/tests/test_execution.py`) a `--sandbox` argumentumra, RED
`workspace-write`-on, GREEN utána. `python3 -m pytest tools/tests -q`: 107
passed, 33 subtests passed. `router-ci.yml` zölden futott a merge-elt
SHA-n. A production task-state (`E02-R21`, `STOPPED`,
`m3_attempts=2/2`/`terra_calls=1/1`, mind sandbox-hibával kimerítve)
`reset --task-id E02-R21`-lel törölve → `NOT_STARTED`, a lánc szabadon
újraindulhat. A `_smoke()` valódi `exec_command`-dal kiegészítése (a fenti
(2) pont) szándékosan KIMARADT ebből a javításból — a gyökérokot nem
érinti, külön, tartalmi (nem heal-) kör dolga volna, ha egyáltalán kell.
