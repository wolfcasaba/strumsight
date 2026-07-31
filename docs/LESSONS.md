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
