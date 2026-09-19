# ADR 0547 — A napi hurok: a kurzus a mai terv, és a kör mozdítja a sorozatot

- **Státusz:** elfogadva
- **Dátum:** 2026-09-12
- **Kör:** E18-R18
- **Kapcsolódó:** ADR 0543 (a kör evidenciává válik), ADR 0544, ADR 0277 §2
  (offline nem hibaállapot), `docs/LESSONS.md` L269 (egy segéd, egy definíció)

## Kontextus

A user kérése az volt, hogy **minden lefejlesztett dolgot kössünk be**. A feltárás
két, élesen különböző csoportot talált.

**1. Szándékos rollout-kapuk, nem elfelejtett munka.** 15 képernyőt semmi nem
konstruál (közösségi felület, elemzés-felvétel, AI-tutor terv-előnézet,
setlist-session). Ezek a `FeatureFlags` alatt élnek, ami kifejezetten
*„availability switches, not user preferences"*, és az indokok a fájlban vannak —
például a fiók azért van kikapcsolva, mert *„there is no hosted backend; a Sign-in
button that always fails is worse than none."* A közösségi felületnek ráadásul
**egyáltalán nincs route-ja**. Ezek felkapcsolása rollout-döntés egy nem létező
backend fölött, nem bekötés; ez a kör nem nyúl hozzájuk, és a HANDOFF megnevezi őket.

**2. Egy valódi, várakozó illesztés.** A `TodayPlanRepository` doksija szó szerint
azt írta, hogy a produkció `UnavailableTodayPlanRepository`-t olvas *„until a future
round wires the real plan source"*. Közben a tananyag pontosan tudta, hol áll a
tanuló, és ezt a feature-én kívül semmi nem kérdezhette meg. A Today hub tehát egy a
létra közepén járó tanulót azzal fogadott, hogy **„még nincs terved"**, és az elsődleges
gombja egy generikus hubra vitte.

## Döntés

### D1 — A mai terv a SZÁLLÍTOTT kurzus, és a függés iránya a hub felé mutat

`CurriculumTodayPlanRepository` a `today` feature-ben él és a
`curriculum/public.dart`-on át olvas. Szándékosan ebbe az irányba: a Today hub
aggregátor, tehát ismerheti a tananyagot; a tananyag nem ismerhet egy hubot, ami őt
megjeleníti.

### D2 — Egy definíció arra, hogy melyik rung a következő

`curriculumNextStep(course, estimates:)`, a tananyag domainjében, **két fogyasztóval**:
a hub elsődleges gombja és a létra „ez következik" jelölése. Két implementáció
előbb-utóbb más rungot nevezne meg, és a tanuló azt látná, hogy a hub egyet ígér, a
létra másra mutat — ugyanaz a duplikáció, amit az L269 a párosító segédekről rögzít.

**A definíció:** *az első rung, létra-sorrendben, ami nyitva van és még nem nyitotta
ki azt, ami utána jön.* Formálisan: az első küldetés, aminek a készség-kapuja
teljesül, és ami olyan készséget tanít, amire egy még zárt későbbi küldetésnek
szüksége van.

Azért ez, mert **nem kell hozzá második küszöb**. A két kézenfekvő alternatíva elbukik,
és ez mérve van:

- *„a legtávolabbi nyitott rung"* átlépi a tanítási sorrendet. A jobbkéz-rung
  megszerzése után az E-moll (3. rung) ÉS a le-fel nyolcadok (6. rung) is kinyílik; a
  legtávolabbi a 6., miközben a kurzus kutatott sorrendje az alakzatot teszi előbbre.
- *„az első nyitott rung, amire nincs kör"* EGY kör után abbahagyja az ajánlást, pedig
  a mért kapu kettőt kér (`curriculum_progress_test.dart`).

A létra tetején semmi nem zárt, tehát az utolsó nyitott rung a válasz: nincs mi mögé
célozni.

### D3 — A készülék-képesség SZÁNDÉKOSAN nincs megkérdezve

A `curriculumDeviceCapabilities` azt válaszolja meg, „mi mérhető, amíg audio
érkezik" — ez egy gyakorló munkamenet tulajdonsága, nem a tanuló létra-pozíciójának.
A Today hubon nem érkezik audio. `microphoneListening: false` mellett minden pontozott
rung „nem mérhető" lenne, és a hub **örökké hangolást ajánlana**; `true` mellett egy
képességet állítanánk bizonyíték nélkül, amit a `device_capabilities.dart`
kifejezetten visszautasít.

Ezért a terv azt válaszolja meg, amit őszintén meg tud: meddig ér a tanuló saját
evidenciája. Azt, hogy EZ a készülék meg tudja-e mérni az adott rungot, ott dől el,
ahol tudható — a létrán és a gyakorló képernyőn —, és mindkettő szavakkal ki is mondja.

### D4 — A terv AZONOSÍTÓT hordoz, nem feliratot

A `TodayPlanSnapshot` új `recommendedMissionId` mezőt kapott. Egy feliratot ez a
projekció nem tölthet ki, mert nincsenek benne lokalizációk: angol prózát tett volna
egy magyar tanuló elé, és az l10n parity gate **soha nem vette volna észre**, mert az
arb-fájlokból nem hiányzott volna semmi. A nevet a felület oldja fel
(`curriculumMissionName`). Ugyanez az azonosító az, amitől az elsődleges gomb **azt** a
rungot folytatja: egy „folytatás" feliratú gomb, ami máshová megy, a hub hazugsága
arról, amit épp kínált.

### D5 — Egy feladat, nem kitalált lista

`totalTaskCount: 1`. A kurzus egy következő lépést nevez meg; egy több elemű napi
tervet állítani, amit a kurzus nem definiál, kitalálás lenne. A
`completedTaskCount` csak akkor 1, ha **arra** a rungra ugyanazon a HELYI napon
rögzült kör — ettől jelent az `isDayCompleted` azt, hogy „a mai lépést már
gyakoroltad", nem azt, hogy „befejezted a kurzust". Helyi nap, mert a „ma" a tanuló
napja, és egy UTC-határ rossz időzónában este véget vetne a gyakorlónapjának.

Egy készséget nem tanító rung „nem gyakorolta ma"-ként olvasódik, mert olyan
evidencia nincs, amit termelhetett volna — a nem tudható befejezés őszinte
megjelenítése a befejezetlen, nem a gratuláció.

### D6 — A sorozat a JÁTÉKRA jár, nem a pontszámra

A kör rögzítése krediteli a gyakorló sorozatot, ha **legalább egy megerősített
pengetés** volt (`heard > 0`) — és nem akkor, ha „evidencia íródott". A kettő egy
fedettségi padló alatti körnél eltér, és a különbség mindkét irányban számít:

- Csak írott evidenciára kreditálni elvonná a sorozatot attól, aki játszott egy
  szobában, amit a mikrofon nem hallott elég jól. Ez a jel hiányát a játékos
  hibájaként bünteti — épp az a szabály, ami ellen az egész design épül.
- Befejezett körre kreditálni viszont annak adna sorozatot, aki megnyitotta a
  képernyőt, hagyta lefutni, és nem játszott semmit.

A sorozat **szokást** mér, nem teljesítményt, tehát a léc az, hogy „gyakoroltál-e", nem
az, hogy „elég jól-e ahhoz, hogy pontozzuk".

### D7 — Az „új felhasználó" jel újraalapozva, mert a régi megszűnt jel lenni

A hub `isNewUser` feltétele tartalmazta, hogy `!snapshot.hasPlan`. A szállított kurzus
azonban **mindenkinek** ad tervet az első indítástól, tehát ez a tag konstans igazzá
tette volna a „nem új" oldalt, és a nulla-állapot üdvözlése **elérhetetlenné** vált
volna: a hub azt mondta volna egy soha nem játszott embernek, hogy „folytasd".

Amit továbbra is a tanulóról mond: a saját története (nincs munkamenet, nincs
sorozat), plusz hogy a TERV mutat-e korábbi aktivitást — a ma már beszámolt munka az,
és egy szinkronból érkezett terv is, ami csak akkor létezik, ha valamit beállítottak.
Egy terv puszta jelenléte nem.

## Következmények

- A `streak/public.dart` most exportálja a `StreakData`-t. A `streakProvider`
  `NotifierProvider<StreakController, StreakData>`, tehát egy fogyasztó a
  `streak.current`-et következtetésből olvasni tudta, de a típust megnevezni nem —
  hiányos publikus API, nem szándékos határ.
- A `curriculum/public.dart` exportálja a `curriculumMissionName`-et, mert most egy a
  feature-ön KÍVÜLI felület jelenít meg rungot, és nem nyomtathatja ki a
  perzisztencia-azonosítót (E18-R14).
- A `UnavailableTodayPlanRepository` megmarad őszinte tartaléknak, és a tesztek
  továbbra is azt használják az offline-cached / sync-pending állapotokhoz — amiket a
  kurzus-forrás **sosem** állít elő, mert nincs mit szinkronizálnia. A terv
  `ready` vagy `unavailable`, és az `offlineCached` ráfogása szervert találna ki, amiből
  „cache-elve" lett.
