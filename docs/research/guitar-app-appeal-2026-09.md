# Mitől szeretik a gitáros appokat — piaci kutatás (2026-09-15)

- **Készült:** 2026-09-15, a tulajdonos „úgy készítsd el az appot, hogy mindenkinek
  tetsszen" kérésére, a fejlesztési irány kijelöléséhez.
- **Módszer:** webes kutatás (App Store / Play áruházi értékelés-aggregátorok,
  Trustpilot, Guitar World / Guitar.com / Guitar Chalk / American Songwriter
  tesztek, gyártói súgók, fórumok). A Reddit a keresőnek zárt, onnan csak
  másodkézből (idéző oldalak) van adat. Több tesztoldal a kimenő proxyn
  blokkolt volt — azok tartalma keresési kivonatból származik.
- **Vizsgált appok:** Yousician, Simply Guitar, Fender Play, Chordify, Ultimate
  Guitar, JustinGuitar, GuitarTuna, Songsterr, Moises, Gibson App.

## 1. Amit mindenki szeret (rangsorolva)

1. **Azonnali, őszinte, hangonkénti visszajelzés zöld/piros színnel** — a
   Yousician legdicsértebb tulajdonsága („megmondja, ha tompítasz egy húrt").
2. **Dal-először: „percek alatt igazi dalt játszol"** — Simply Guitar: kvíz →
   választott dal → első ülésben pengetsz; minden dal a következőt oldja fel.
3. **Rövid (5–10 perces) leckék**, amik „munka között vagy lefekvés előtt"
   beférnek (Simply Guitar, JustinGuitar napi 10 perces gyakorlatok).
4. **Mérhető mikro-cél: az „egyperces váltások"** — 60 mp alatt hány
   akkordváltás; „az egész kezdő kurzus kulcsleckéje" (JustinGuitar).
5. **A sorozat (streak) tanulási elvként, nem trükként** — „a napi gyakorlás a
   haladás legfőbb meghatározója", heti kihívások, 1–3 csillag dalrészenként.
6. **Ingyenes, strukturált, fokozatos út (Grade 1–9) fizetőfal nélkül** —
   JustinGuitar rendre „jobb, mint a fizetős versenytársak".
7. **Nem büntető javítás** (Gibson „Audio Augmented Reality"): jó húr, jó idő,
   rossz bund → az app a helyes hangot játssza le zörgés helyett; „minden
   hibáért lehúzni a kezdőt demoralizáló".
8. **Felvétel utáni értékelés hőtérképpel a kottán** (Fender Feedback Mode):
   hangmagasság / ritmus / hosszúság külön pontozva, a hibás ütem kiemelve —
   szándékosan nem élő „Guitar Hero"-zaklatás.
9. **Lassítás / ismétlés / transzponálás / capo bármely dalon**, szólam-
   szétválasztás, kísérőzene (Moises, Songsterr, UG Pro).
10. **Nulla súrlódású belépés: nincs bejelentkezés, nincs e-mail** — a
    Songsterr ingyenes tabjait és lejátszását „bármiféle bejelentkezés nélkül"
    külön dicsérik.
11. **Gyors, pontos hangoló, nagy mutatóval, automatikus húrfelismeréssel** —
    ezért 4,5★ a GuitarTuna a reklámok ellenére.
12. **Tömör napi/heti „edzői jelentés"** (Gibson AI-összefoglaló 5 lecke után:
    mi javult, mit gyakorolj) — a tesztelők csak hosszabbat kívánnak.

Késleltetés-elvárás: valós idejű zenei visszajelzésnél ≤50 ms „elfogadható",
~20 ms ideális, >100 ms már „késik"; a Yousician pont ezért kalibrálja a
mikrofont az első indításkor.

## 2. Hat panasz, amit kerülni kell

1. **Előfizetés-nyaggatás, zsugorodó ingyenes szint** (Yousician napi
   időkorlát, Chordify „régen több dal volt ingyen", UG teljes képernyős
   reklám fizetőknek is, GuitarTuna kivett korábban fizetett funkciókat).
2. **Hazudó felismerés** — Simply Guitar: „rosszat mond, amikor tudom, hogy jó,
   és jót, amikor rossz", visszhangban/zajban rosszabb; a Chordify a 7/sus/dim
   akkordokat sima hármasokra lapítja. A felhasználó a kihagyást megbocsátja,
   a hamis pozitívot nem.
3. **Játékosított, de sekély** — „gyakorlási segédeszköz, nem tanulási
   program"; szigorú időzítés magyarázat nélkül, hogy *miért* buktál.
4. **Zsúfolt kezdőképernyő / eldugott eszközök** (GuitarTuna).
5. **Számlázási csapdák** — automatikus megújítás, a lemondás nem lemond; a
   Trustpilot első számú témája a Yousiciannál és az UG-nél.
6. **Semmi a középhaladóknak** — Simply Guitar a kezdő dalok után kifullad, a
   felhasználók elmennek, amint az alapok ülnek.

## 3. 2025–2026-os trendek

Az AI-alapú valós idejű javítás alapfelszereltség lett (Fender Feedback Mode,
Gibson AR, Yousician); az új panasz a „lapos tanulási út" → adaptív nehézség;
dal-alapú tanulás a drillek helyett; kísérőzene / szólam-szétválasztás (Moises
70 M felhasználó); a „guitar learning app" Google Trends 2025 decemberében
történelmi csúcson.

## 4. Öt ajánlás a StrumSightnak (offline, ingyenes, eszközön futó)

1. **Az „első siker" legyen 90 másodperces, forgatókönyvezett út:** indítás →
   egy húr behangolása → egy akkord (E-moll) → zölden telik, amikor tisztán
   szól → 3 pengetés iránynyilakkal → „Most játszottad az első riffedet" +
   opcionális sorozat-indítás. A Simply Guitar-féle kvíz (cél-dal, szint)
   a siker UTÁN jöjjön, fiók egyáltalán ne kelljen.
2. **A pengetésirány — az egyedi eszközünk — legyen „egyperces váltás"-szerű
   pontszám:** „Le-le-fel-fel-le-fel 60 mp alatt: 22 helyes minta", napi
   legjobbal. Mérhető, offline, és egyetlen versenytárs sem pontozza a
   pengetésirányt — ez a címlapos megkülönböztető. **→ E18-R23-ban leszállítva
   (`lib/features/strum_challenge/`).**
3. **Őszinte, de kedves visszajelzés:** zöld/piros akkordonként ÉS
   pengetésenként; mikrofon-kalibráció + zaj-ellenőrzés első használatkor
   (elkerüli a „hazudott nekem" értékeléseket); bizonytalanság-jelző, ha a
   DSP nem biztos, hamis „rossz" helyett; Fender-stílusú ülés utáni áttekintés,
   melyik ütem ment félre.
4. **Az adatvédelem/offline legyen FUNKCIÓ a kezdőképernyőn és a bolti
   leírásban:** „Nincs fiók. Nincs internet. Nincs reklám. A hangod nem hagyja
   el a telefont." A piac kimerült a számlázási csapdáktól — ez a legolcsóbb
   marketing-nyereség. A választható fiók kizárólag szinkronra, soha
   kapuzásra. **→ E18-R23-ban leszállítva (Today hub kártya).**
5. **Adaptív, rövid ülések tömör edzői kártyával:** 5–10 perces gyakorlás,
   ami a legrosszabb friss pontosságú akkordváltást / pengetésmintát választja
   (adaptív nehézség), szelíd „2 napnál tartasz — holnap 3" emlékeztető, heti
   egybekezdéses összefoglaló (Gibson-stílus) — mind eszközön, a meglévő
   haladás-adatokból. Lassítás/ismétlés a könyvtár dalain a Moises/Songsterr
   „gyakorlóeszköz"-elvárás fedésére, felhő nélkül.

## Források

guitarchalk.com/yousician-review · trustpilot.com/review/yousician.com ·
americansongwriter.com/simply-guitar-review · stringshock.com/simply-guitar-app-review ·
equipboard.com/posts/fender-play-vs-yousician · play-support.fender.com (Feedback Mode) ·
guitarworld.com/reviews/justinguitar-review · justinguitar.com (one-minute changes) ·
guitarchalk.com/chordify-review · singularsound.com (Songsterr vs UG) ·
stemsplit.io/blog/moises-ai-review · americansongwriter.com/best-guitar-tuner-apps ·
slashgear.com (Gibson App) · trophy.so/blog/yousician-gamification-case-study ·
guitarsrepublic.com (AI guitar apps 2026) · sweetwater.com (latency tips)
