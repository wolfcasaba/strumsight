# ADR 0546 — A „10 hasznos perc" lánc: hangolás → gyakorlat → rövid eredmény

**Státusz:** elfogadva (2026-09-09) · **Kör:** E14-R36 · **Csomag:** PKG-C ·
**Épít rá:** ADR 0275 (adaptív shell), ADR 0277 (Today hub offline-szabály),
ADR 0508 (`entryLocationFor`, ajánlás-feloldás) · **Nem érinti:** ADR 0055
szerepek, semmilyen DSP-küszöb

## Kontextus (mért)

- A `TodayHubScreen` (E13-R17) **kész**: egyetlen elsődleges CTA (audit L1),
  streak/napi cél, `TodayPlanSnapshot` empty/loading/error ágakkal,
  `practiceCatalogProvider` const-lookup. Új felhasználó 2 tapon belül indít.
- **A nevesített LÁNC hiányzott.** Ma a CTA a
  `/practice/setup?id=<ajánlás>`-ra megy, a hangoló pedig külön sziget
  (`/practice/tuner`). Semmi nem köti össze a hármat, és semmi nem tudja,
  hogy a felhasználó félbehagyta.
- `PracticeEntry` (a `practiceLog` eleme) **nap-granularitású**
  (`PracticeEntry.day` = epoch-nap) — nincs időbélyege. „Gyakorolt-e a
  felhasználó azóta, hogy elindította a láncot?" tehát a naplóból NEM
  válaszolható meg pontosan. Ami mozog: a
  `dailyGoalActiveSecondsProvider(today)` másodperc-számláló.
- `/practice/result` a routerben `PracticeResultFallback`, azaz a „nincs
  megjeleníthető eredmény" képernyő, hacsak a gyakorló-munkamenet maga nem
  tolt rá egyet. A Today felől odanavigálni zsákutca lenne.
- `StorageKeys` (`lib/core/storage/storage_keys.dart`) **nem PKG-C
  tulajdona**, tehát ebben a körben nem születhet új perzisztens kulcs.

## Döntés

### D1 — A kompozíció SZABÁLY, nem táblázat

`TenMinutePlan` a hangolás (2 perc) és a rövid eredmény (1 perc) fix
belépő/kilépő költségét rögzíti, a gyakorlás pedig **a maradék**. Így
`tune + play + review == total` konstrukció szerint teljesül minden
elfogadott totálra — nem csak 10 percre —, és a teszt tetszőleges totálra
állítja.

Az a totál, amiből nem jön ki legalább `minimumPlayBudget` (1 perc) valódi
játék, **elutasításra kerül** (`fits()` → false, `TenMinutePlan.of()` dob).
Egy „10 perces gyakorlás", amiben 30 másodperc gitározás van, nem az a dolog,
amit a képernyő ígér (Ch14 §9).

### D2 — A lánc OPT-IN, és soha nem rontja el az audit-L1 CTA-t

Az L1 javítás (E13-R17) mért eredménye: az első CTA az **ajánlott gyakorlat
setup-útvonalára** megy, nem a hubra. Ezt a kör nem írja felül. A lánc
indítása **másodlagos** (outlined) akció; amíg fut, **az elsődleges CTA a
lánc következő lépése** — így a képernyőn továbbra is pontosan EGY kitöltött
gomb van (A1).

A lánc `play` lépésének célja **ugyanaz az URI**, amit a hétköznapi CTA
használ: a szabály egyetlen helyen él
(`practiceStartLocation`, `domain/ten_minute_flow_destinations.dart`), így a
kettő nem tud szétcsúszni.

### D3 — A `review` lépésnek NINCS saját route-ja

A recap a Today-kártyán jelenik meg. A `/practice/result` a Today felől
`PracticeResultFallback` lenne (üres állapot recap-nek öltöztetve), a valódi
`practice_result_screen` pedig továbbra is az, amin a gyakorló-munkamenet
véget ér — azt a kör nem veszi el és nem duplázza. `tenMinuteStepLocation`
ezért `String?`-ot ad: a `null` azt jelenti, „ez a lépés helyben renderelődik".

### D4 — A `play` lépés befejezését MÉRT idő zárja le, nem egy megnyitott képernyő

A lánc indulásakor eltároljuk a `dailyGoalActiveSecondsProvider(today)`
pillanatnyi értékét (`baselineActiveSeconds`). A `play` lépés csak akkor
lép tovább a recapra, ha ez a számláló **átlépte** a baseline-t. A setup
képernyő megnyitása önmagában nem bizonyíték arról, hogy bárki játszott.

A recap a **mért** perceket mondja (`measuredMinutes`), nem a tervezett
büdzsét. 59 másodperc nem „1 perc gyakorlás", és a lecsökkent számláló
(törölt napló) nem negatív állítás, hanem 0.

### D5 — A hangolás lépését CSAK a játékos zárja le

A hangoló nem következtet arra, hogy a gitár hangolva van: egy húr in-tune
lockja nem bizonyíték a másik ötről. A `tuner-ten-minute-continue` gomb az
egyetlen átadási pont, és az rögtön a gyakorlatra visz (nem vissza a
Today-ra), hogy a lánc egyetlen vezetett folyam legyen.

### D6 — A megszakítás szabálya: 2 órás resume-ablak, TISZTA feloldással

`resolveTenMinuteFlow` **nem ír** semmit — ezért futhat widget-`build`-ben.
Két szabálya:

1. a `resumeWindow` (2 óra) letelte után, illetve visszafelé lépő órán, a
   tárolt lánc `null`-ra oldódik fel (a hub visszatér a hétköznapi CTA-ra);
2. a `play` lépés a D4 szerinti mért bizonyítékkal `review`-ra oldódik fel.

Az állapotot kizárólag explicit felhasználói akció írja
(`start` / `advance` / `abandon`).

### D7 — Session-scope, kimondva; a cross-launch resume NEM készült el

A lánc a `TenMinuteFlowController` Riverpod-notifierben él: túléli a
képernyő elhagyását és a visszatérést (ez a kör tárgya), de **nem éli túl a
process halálát**. Ehhez `StorageKeys`-bejegyzés kellene, ami nem PKG-C
tulajdona. Amíg az nem landol, egy kilőtt app **őszintén nulláról indul**,
nem tesz úgy, mintha emlékezne. A javasolt patch a kör-brief §10-ben.

## Ami MÉRVE van és ami NINCS

**Mérve (teszt-cellával rögzítve):** a kompozíciós szabály összeg-invariánsa
tetszőleges totálra; az elutasított rövid totál; a lánc lépés-sorrendje; a
resume-ablak három határesete (belül, pont a határon, egy másodperccel
utána, visszafelé lépő óra); a mért játék-bizonyíték három cellája; a
kétérintéses indulás; hogy a lánc célja valódi, regisztrált route (valódi
`routerProvider`, `TunerScreen` mountolva); hogy a lánc `play` célja
karakterre az L1 CTA URI-ja.

**Nincs mérve itt:** semmilyen futtatás — ezen a boxon nincs Dart SDK, tehát
egyetlen cella sem futott le. A mérce a CI (`full-gate.yml`) és a valós
APK-teszt. Nincs mérve továbbá, hogy a 2 / 7 / 1 perces felosztás
*pedagógiailag* a helyes arány — ez terméki döntés, nem mérés; a szabály
azért paraméteres, hogy egy jövőbeli kör mérés alapján cserélje.
