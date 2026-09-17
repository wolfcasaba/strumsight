# YouTube-integráció StrumSightban — jogi és technikai megvalósíthatóság

**Kutatási kérdés (termék-tulajdonos szavaival):** „Hogyan tudna működni legálisan és jól a
YouTube-integráció?"

**A vizsgált termékötlet:** a felhasználó a StrumSightban nyit meg egy YouTube-videót egy dalról;
az app lejátssza, és mellette szinkronban futó akkord-/pengetéssávot mutat. Az akkordok forrása
vagy (a) valós idejű MIKROFONOS hallgatás — a felhasználó gitárja és a videó zenéje együtt szól a
szobában, és ahol a felhasználó akkordja EGYEZIK a felismerttel, ott az adott időbélyegen rögzül
(„lock") az akkord —, vagy (b) felhasználói/közösségi idővonalak, amiket a videó-azonosító kulcsol.
A termék-tulajdonos kifejezetten el akarja kerülni, hogy a felhasználónak zenefájlt kelljen
feltöltenie/importálnia.

**Státusz: KUTATÁSI JEGYZET, NEM JOGI TANÁCS.** Ez a dokumentum nyilvános forrásokból összeállított
mérnöki-termékdöntési háttéranyag. A store-kiadás előtt minden itt írt jogi állítást ügyvédnek kell
megerősítenie (lásd §7.5 — az öt kérdés).

**Forrás-korlát (őszinteség első):** ebben a konténerben a kimenő HTTPS-t policy-proxy szűri, és a
`developers.google.com`, `youtube.com`, `net.jogtar.hu`, `njt.jog.gov.hu`, `en.wikipedia.org`,
`web.archive.org`, `labs.polsys.net`, `youtubehelp.fandom.com` hostok mind **403-mal blokkoltak**
(`EGRESS_BLOCKED`). Az elsődleges dokumentumokat tehát **nem tudtam közvetlenül letölteni**, csak
keresőmotor-összefoglalókon keresztül olvasni. Ezért minden szakasz-számozás és szó szerinti idézet
**„ELLENŐRIZENDŐ"** jelölést kap; szakaszszámot sehol nem találtam ki. Részletek a §10-ben.

---

## 1. YouTube API Services ToS + Developer Policies — mi KÖTELEZŐ, mi TILOS

### 1.1 A szerződéses réteg felépítése

Négy dokumentum köt egyszerre, és mind a négyre hivatkozni kell:

| Dokumentum | Mit szabályoz |
|---|---|
| YouTube ToS (`youtube.com/t/terms`) | a végfelhasználói/általános réteg — a Szolgáltatás és a Tartalom használata |
| YouTube API Services ToS (EMEA-verzió köt minket, EU-s fejlesztőként) | a fejlesztői szerződés |
| YouTube API Services — Developer Policies | a részletes viselkedési szabályok |
| Required Minimum Functionality (RMF) | a beágyazott lejátszóra vonatkozó minimumkövetelmények |

### 1.2 Ami KÖTELEZŐ

- **Csak hivatalos lejátszó.** A lejátszásnak a YouTube beágyazott lejátszóján (IFrame Player API,
  illetve a hivatalos mobil player-helperek) kell történnie. Harmadik fél lejátszójába vezetett
  stream tilos. *(Developer Policies / RMF — pontos szakaszszám ELLENŐRIZENDŐ.)*
- **Minimális lejátszóméret.** A beágyazott lejátszó viewportja legalább **200 × 200 px**; ha a
  vezérlők látszanak, a lejátszónak elég nagynak kell lennie, hogy a vezérlők teljesen kiférjenek
  anélkül, hogy a viewport a minimum alá csökkenne. 16:9-es lejátszónál az ajánlás **legalább
  480 × 270 px**. Lejátszást indító előnézeti kép (thumbnail) legalább **120 × 70 px**.
  *(RMF — forrás: keresőösszefoglaló, oldal ELLENŐRIZENDŐ.)*
- **A lejátszó látható és szabad.** Tilos overlay-t, keretet vagy bármilyen vizuális elemet a
  lejátszó bármely része elé tenni, beleértve a lejátszóvezérlőket is, és tilos bármilyen vizuális
  elemmel eltakarni a lejátszó bármely részét. *(RMF / Developer Policies — ELLENŐRIZENDŐ.)*
- **Egyszerre egy automatikusan induló lejátszó** egy képernyőn. *(RMF — ELLENŐRIZENDŐ.)*
- **Attribúció és branding.** A YouTube Brand Features használata a Branding Guidelines szerint
  kötelező. Az app NEVÉBEN nem szerepelhet „YouTube", „YT", „You-Tube" vagy származéka, és a
  YouTube-logót nem lehet az app nevével összevonva használni. Három logóváltozat létezik
  („developed with YouTube", a sima YouTube-logó, és a YouTube ikon).
  *(Branding Guidelines — ELLENŐRIZENDŐ.)*
- **Kvóta és megfelelőségi audit.** Az alap Data API kvóta **10 000 egység/nap**; ennél több csak
  **API Compliance Audit** sikeres teljesítése után adható. A YouTube emellett **időszakos
  auditokat** tart a ToS-megfelelés ellenőrzésére. A kvótakorlátok megkerülése vagy túllépése tilos.
  *(Quota and Compliance Audits — ELLENŐRIZENDŐ.)*
- **Playback integrity.** A YouTube kifejezetten nevesíti, hogy a lejátszás integritása (hogyan
  szolgálódik ki a tartalom és a hirdetés, hogyan indul a lejátszás, hogyan lép interakcióba a
  felhasználó) kritikus, mert az alkotók monetizációját védi. *(Developer Policies — ELLENŐRIZENDŐ.)*

### 1.3 Ami TILOS — ez a lista a mi ötletünk szempontjából a lényeg

- **Letöltés, importálás, backup, cache-elés, tárolás.** „You and your API Clients must not
  download, import, backup, cache, or store copies of YouTube audiovisual content" a YouTube
  előzetes írásbeli engedélye nélkül. *(Developer Policies — a hivatkozott szakaszszám a
  publikus diskurzusban gyakran „III.E Additional Prohibitions"; a szó szerinti szakaszjelölés
  ELLENŐRIZENDŐ, mert a `developers.google.com` blokkolt.)*
- **Hang és kép szétválasztása.** „You and your API Clients must not separate, isolate, or modify
  the audio or video components of any YouTube audiovisual content made available as part of, or in
  connection with, YouTube API Services." Ez az a klauzula, ami a **csak-hang (audio-only)
  lejátszást** ellehetetleníti, és amit a „Complying with YouTube's Developer Policies" útmutató is
  külön példával nevesít („using YouTube's API to separate or isolate video or audio components").
  *(ELLENŐRIZENDŐ szakaszszám.)*
- **Háttérlejátszás.** Tilos a YouTube-lejátszó háttérben futtatása — konkrétan „allowing videos to
  play when your API service window is closed or minimized". *(Developer Policies guide —
  ELLENŐRIZENDŐ.)*
- **Hirdetések módosítása / blokkolása / helyettesítése**, illetve a lejátszásba avatkozás.
- **Megkerülés.** Tilos a földrajzi vagy egyéb korlátozások (pl. IP-alapú) megkerülése,
  hatástalanítása; tilos olyan szolgáltatás, amit kifejezetten arra terveztek, hogy a YouTube
  korlátozásait megkerülje.
- **„Stream ripping".** A fenti letöltési/szétválasztási tilalmak együtt lefedik.

### 1.4 A végfelhasználói YouTube ToS

A `youtube.com/t/terms` „Permissions and Restrictions" szakasza kimondja, hogy a felhasználó
megtekintheti/meghallgathatja a Tartalmat személyes, nem kereskedelmi célra, és **megjelenítheti a
videót a beágyazható YouTube-lejátszón keresztül**; ugyanakkor tilos „access, reproduce, download,
distribute, transmit, broadcast, display, sell, license, alter, modify or otherwise using any part
of the Service or any Content", kivéve (a) amit a Szolgáltatás kifejezetten engedélyez, vagy (b) a
YouTube és adott esetben a jogtulajdonosok előzetes írásbeli engedélyével.
*(Az oldal blokkolt; a szövegrészlet keresőösszefoglalóból — ELLENŐRIZENDŐ.)*

**Fontos következtetés:** a beágyazott lejátszó használata a ToS által KIFEJEZETTEN megengedett út.
A jogi kockázat nem az embed, hanem minden, ami a stream mellé nyúl.

### 1.5 A Content ID irrelevanciája

A Content ID a YouTube **saját platformján** belüli jogkezelő rendszer: azt oldja meg, hogy egy
YouTube-ra FELTÖLTÖTT videóban felismert zene után a jogtulajdonos monetizáljon vagy blokkoljon.
Semmit nem mond arról, hogy egy harmadik fél appja mit tehet a lejátszott tartalommal, és **nem ad
licencet** semmire. Az a gyakori laikus érv, hogy „ha a videó fent van és nincs letiltva, akkor
minden rendben", jogilag üres: a videó fennmaradása nem a mi felhasználásunkra vonatkozó engedély.

---

## 2. A mikrofonos hallgatás reprodukciónak minősül-e?

Ez a termék-tulajdonos ötletének (B opció) sarokköve. Két oldalról érdemes nézni.

### 2.1 Érvek amellett, hogy NEM reprodukció (és nem is API-ToS-sértés)

1. **Az app nem nyúl a streamhez.** A YouTube API ToS tilalmai a „YouTube audiovisual content made
   available as part of, or in connection with, YouTube API Services" objektumra — a bitfolyamra —
   vonatkoznak. A mikrofon a **szoba levegőjét** veszi fel: egy fizikai hangteret, amiben a
   telefonhangszóró, a gitár és a szoba zaja együtt van. Ez nem a stream másolata.
2. **Shazam-analógia.** A mikrofonos zenefelismerés (Shazam, ACR) bevett gyakorlat: a felvett hangot
   azonnal lenyomattá alakítja, és nem a hang, hanem a **kód** utazik tovább. StrumSightban ennél is
   kevesebb történik: a kromagram/CRNN azonnal akkordcímkét számol, és a PCM-et eldobja.
3. **Tranziens elemzés vs. tárolás.** Az InfoSoc 2001/29 **5. cikk (1)** a KÖTELEZŐ kivétel:
   átmeneti vagy járulékos, egy műszaki folyamat szerves és lényeges részét képező többszörözés,
   amelynek egyetlen célja a mű jogszerű felhasználásának lehetővé tétele, és önálló gazdasági
   jelentősége nincs. Egy pár száz ms-os ring buffer, amiből csak kromagram lesz, pontosan ilyen
   alakú. **(Érvelés, nem eldöntött jogkérdés — ELLENŐRIZENDŐ ügyvéddel.)**
4. **A származtatott adat nem a felvétel.** Az akkord-idővonal (`t → akkordcímke`) nem a felvétel
   másolata, hanem **transzkripció**, azaz a zeneMŰ származéka. Ez jogi-alanyi eltolódás: elszakad a
   hangfelvétel-előállítói és a YouTube-ot érintő jogoktól, és a **zeneműkiadói** oldalra kerül
   (§3). A YouTube nem jogosultja a zeneműkiadói jognak.

### 2.2 Érvek amellett, hogy KOCKÁZATOS

1. **A ToS többet tilt, mint a szerzői jog.** A YouTube ToS „access… or otherwise using any part of
   the Service or any Content" fordulata szerződéses tilalom, ami nem függ attól, hogy szerzői jogi
   értelemben történt-e többszörözés. Egy funkció, ami kizárólag azért létezik, hogy egy YouTube-ban
   szóló hangból strukturált adatot nyerjen, a szerződés szellemével szemben áll, még ha a betűjét
   elkerüli is.
2. **„Rendeltetésellenes hozzáférés" vád.** A YouTube „playback integrity" fogalma explicit: az a
   szándék, hogy a YouTube-lejátszás kimeneteit az app saját céljára hasznosítsa, megalapozhatja a
   „circumvention/interference" értelmezést — ez API-kulcs-visszavonással járhat, ami terméket öl,
   nem pert.
3. **Precedens: Riffstation.** A Fender 2018-ban leállította a web/iOS verziót, majd 2019-re
   teljesen, azzal az indoklással, hogy „while we work with labels and publishers on a paid
   Riffstation service, Riffstation will no longer be available on the web or mobile devices" — a
   sajtókommentár szerint a Fender nem akart kitenni magát copyright-igényeknek. Ez a konkrét
   kategória (YouTube-ról akkordot fejtő gitártanuló app) élő üzleti kockázatot mutat.

### 2.3 Az `AudioPlaybackCapture` (Android) — technikailag megy, policy-szerűen valószínűleg TILOS

Androidon (API 29+) az `AudioPlaybackCaptureConfiguration` + `MediaProjection` lehetővé teszi más
appok lejátszásának felvételét; a **saját app saját hangja** ennél triviálisan könnyebb eset
(azonos UID, `ALLOW_CAPTURE_BY_SELF` policy mellett is engedett) — tehát az app **el tudná kapni a
saját beágyazott WebView-ja YouTube-hangját** mikrofon nélkül, tökéletesen tiszta jelként, a szoba
és a gitár zaja nélkül. *(Az `ALLOW_CAPTURE_BY_SELF` pontos szemantikája a WebView-ra
ELLENŐRIZENDŐ — a `developer.android.com` blokkolt volt.)*

**Ettől függetlenül ezt NEM szabad megcsinálni.** Ez pontosan az a művelet, amit a Developer
Policies tilt: a videó hangkomponensének **elkülönítése** („separate, isolate… the audio or video
components"), és amint a puffer több mint tranziens, **tárolása/cache-elése** is. Az, hogy technikai
akadály nincs, jogi engedélyt nem teremt — és ez a legkönnyebben bizonyítható szabálysértés is,
mert a `MediaProjection` engedélykérés és a `RECORD_AUDIO` + capture-konfiguráció a manifestből és a
kódból egyértelműen kiolvasható egy store-review vagy egy YouTube-audit során. **Verdikt: soha.**

A mikrofon és az `AudioPlaybackCapture` közti különbség nem szőrszálhasogatás: az egyik a szobát
hallgatja (amiben a felhasználó gitárja is benne van, és a funkció épp ettől működik), a másik a
stream hangsávját csapolja meg.

---

## 3. Zeneműkiadói jogok: akkordtáblák és idővonalak

### 3.1 Az akkordtábla jogi természete

Két, egymással feszülő igazság van, és mindkettőt ismerni kell:

- **A jogtulajdonosi álláspont:** a tabulatúra/akkordtábla a zenemű **származékos műve**
  (derivative work), és mint ilyen a szerző kizárólagos jogában áll. 2006-ban az NMPA és az MPA
  cease-and-desist leveleket és DMCA-takedownokat küldött tabulatúra-oldalaknak (köztük az Ultimate
  Guitarnak), pontosan erre a US Copyright Act §106 szerinti származékosmű-jogra hivatkozva.
- **A bírósági trend a puszta akkordmenetre:** a `Gray v. Perry` („Dark Horse", 2020 JMOL, 2022
  9th Cir.) ügyben a bíróság kimondta, hogy a közhelyes akkordmenetek, tempók és zenei
  építőkövek önmagukban nem élveznek szerzői jogi védelmet — „these building blocks belong in the
  public domain".

Ez a két állítás nem mond ellent egymásnak: **egy G–D–Em–C menet önmagában nem védett**, de egy
teljes dal akkord- és ritmus-transzkripciója időbélyegekkel, ami a dal kottájának helyettesítője,
már a mű származéka lehet. A gyakorlati határvonal ott van, hogy a kimenet **mennyire alkalmas
arra, hogy a hivatalos kotta helyett használják.**

### 3.2 Hogyan kezelik ezt a piac szereplői

| Szereplő | Modell | Jogi megoldás |
|---|---|---|
| **Ultimate Guitar** | UGC tabok | 2006-os takedown-hullámot túlélte (orosz hosting), **2010. április 10-én licencszerződés a Harry Fox Agencyvel** (lyrics-megjelenítés, cím-keresés, tab-megjelenítés letöltéssel/nyomtatással); a HFA 44 000+ kiadója opt-in alapon csatlakozhat |
| **Songsterr** | UGC tabok, US-cég (Guitar Tabs LLC) | saját állítása szerint „100% legal": licencek a kiadókkal, és a bevétel közel felét royaltyként fizeti ki |
| **Chordify** | automata akkordfelismerés + **YouTube/SoundCloud embed** | **nem licencel**; nyilvános álláspontja, hogy az akkordmenet önmagában nem eredeti/nem védhető; emellett **retract@chordify.net** opt-out-ot ad jogtulajdonosoknak (notice-and-takedown de facto) |
| **Yousician** | licencelt katalógus | kiadói szerződések dalonként; a támogatás országonként és időben változik, mert a licenc lejárhat (pl. Metallica 2022, Billie Eilish `Hit Me Hard and Soft` teljes album) |
| **Moises** | a felhasználó SAJÁT feltöltött fájlja | a felhasználóra tolja a felelősséget („only process music you have the legal right to modify"); **kifejezetten NEM fogad el streaming-URL-t** (Spotify, Apple Music, YouTube, SoundCloud stb.), mert a DRM és a licencfeltételek tiltják, és a stemek kinyerése engedély nélküli származékos mű lenne |
| **Chord ai** | on-device deep learning; forrás: saját fájl, SoundCloud, **YouTube WebView-ban**, és élő mikrofon | a YouTube-ág úgy van bemutatva, hogy a felhasználó a WebView-ban szabadon böngészik, iOS-en egy koppintás indítja az elemzést; a mikrofonos ág „bármely a közeledben szóló dal" |
| **Capo** | a felhasználó saját zenei könyvtára, minden feldolgozás lokálisan | nincs harmadik fél streamje |
| **Riffstation** | YouTube-ból akkord | **2018–2019-ben leállt**; a Fender „labels and publishers"-szel tárgyalt fizetős szolgáltatásról — a nyilvános magyarázat szerint licenc- és copyright-kockázat miatt |

**Ebből három tanulság.** (1) A YouTube-ra épülő akkordfelismerés PIACON VAN (Chordify, Chord ai) —
tehát nem eleve lehetetlen. (2) A legnagyobb tőkével rendelkező szereplő (Fender) épp ebből a
kategóriából LÉPETT KI. (3) Aki licencelt (UG, Songsterr, Yousician), az nyugodtan alszik, de
fizet — és a licenc katalógus-korlátot hoz.

### 3.3 EU: nincs US-style fair use

Az EU-ban **nincs nyitott fair use**; zárt kivételrendszer van (InfoSoc 2001/29 **5. cikk**), amiből
csak az 5(1) (átmeneti többszörözés) kötelező, a többi ~20 opcionális, és mindegyikre vonatkozik az
**5(5) háromlépcsős teszt** (különleges eset; nem ütközik a mű rendes felhasználásával; nem sérti
indokolatlanul a jogosult jogos érdekeit). Releváns opcionális kivételek: magáncélú másolás
(5(2)(b) — a CJEU szerint **csak jogszerű forrásból**), idézés, paródia.

A **DSM-irányelv (2019/790) 17. cikke** akkor lép be, ha a StrumSight közösségi idővonalakat
FOGAD és TESZ HOZZÁFÉRHETŐVÉ — ilyenkor „online content-sharing service provider" (OCSSP) lehet
belőle, ami elsődleges felelősséget jelent a felhasználók feltöltötte védett tartalomért. Két
mentesítő szál: az **17(4)** szerinti best-efforts + notice-and-takedown, illetve a **17(6)**
könnyítés az új szolgáltatókra (EU-ban 3 évnél rövidebb ideje elérhető ÉS **10 M EUR alatti éves
árbevétel**) — ekkor elég a 17(4)(a) (engedélyszerzési best effort) plus a kellően megalapozott
értesítésre való gyors eltávolítás.

### 3.4 Magyarország: Szjt.

- **Szjt. 29. §** — az átdolgozás joga: a szerző kizárólagos joga, hogy a művét átdolgozza, illetve
  erre másnak engedélyt adjon. Átdolgozás a mű fordítása, színpadi, **zenei feldolgozása**, filmre
  való átdolgozása, és minden más olyan megváltoztatás, amelynek eredményeképpen az eredeti műből
  **származó más mű** jön létre. *(Szöveg keresőösszefoglalóból; a `net.jogtar.hu` blokkolt —
  ELLENŐRIZENDŐ.)*
- **Szjt. 33. §** — a szabad felhasználás keretei: a felhasználás díjtalan és engedély nélküli, de
  csak **nyilvánosságra hozott** művön, csak annyiban, amennyiben **nem sérelmes a mű rendes
  felhasználására**, és nem károsítja indokolatlanul a szerző jogos érdekeit, továbbá megfelel a
  tisztesség követelményeinek (a háromlépcsős teszt magyar alakja).
- **Szjt. 34. §** — idézés: a mű részlete átvehető a forrás és a szerző megjelölésével, az
  átvevő mű jellege és célja által indokolt terjedelemben.
- **Szjt. 35. § (1)** — magáncélú másolás: természetes személy magáncélra készíthet másolatot, ha az
  **nem irányul jövedelemszerzésre vagy jövedelemfokozásra** (közvetve sem). Külön korlát: **teljes
  könyv, folyóirat, napilap** csak kézírással/írógéppel; és **KOTTA magáncélra REPROGRÁFIAI úton nem
  másolható**. Ez a „kotta"-korlát figyelmeztető jelzés: a magyar jog a kottát kiemelt védelemben
  részesíti, és egy akkord-idővonal funkcionálisan kottaszerű termék.
- **Artisjus** — a mechanikai és nyilvános előadási jogokat kezeli, DE: az Artisjus saját tájékoztató
  oldala („Mire nem adhat engedélyt az Artisjus?") kimondja, hogy az **átdolgozás olyan speciális
  forma, amelyre NEM az Artisjus, hanem közvetlenül a jogosult ad egyedi, írásbeli engedélyt.**
  Ez a StrumSight szempontjából döntő: **ha egy akkord-idővonal átdolgozásnak minősül, azt nem lehet
  közös jogkezelőtől „megvenni" — kiadónként kell szerződni.** Ezért nincs olcsó magyar
  „egyablakos" licenc erre a funkcióra.

### 3.5 Közösségi (UGC) idővonalak

Ha a felhasználók által készített idővonalakat a StrumSight backendje tárolja és másoknak
kiszolgálja, akkor a StrumSight **tárhelyszolgáltató** lesz, és legalább:

- **DSA (EU 2022/2065, 2024. február 17-től teljes hatállyal minden tárhelyszolgáltatóra):**
  **16. cikk** notice-and-action mechanizmus (bárki bejelenthet jogellenes tartalmat, indokolt
  magyarázattal, pontos URL-lel, bejelentői névvel/e-maillel, jóhiszeműségi nyilatkozattal),
  **17. cikk** indokolási kötelezettség (statement of reasons) minden moderálási döntésre,
  **18. cikk** bűncselekmény-gyanú bejelentése. A **mikro- és kisvállalkozások** egyes
  kötelezettségek (pl. a 20–22. cikk online platform-specifikus terhei) alól mentesülnek — de a
  notice-and-action alól **nem**. *(A konkrét mentesség-lista ELLENŐRIZENDŐ.)*
- **DSM 17. cikk:** lásd §3.3 — a 17(6) könnyítés reálisan alkalmazható lesz az induláskor.
- Gyakorlati minimum: `retract@` típusú takedown-cím (a Chordify mintájára), moderálási napló,
  és az idővonalak **videó-azonosítóhoz** kötése, hogy egy bejelentés célzottan kiszolgálható legyen.

---

## 4. Play Store / App Store policy

### 4.1 Google Play

- **Device and Network Abuse:** tilos az eszközhöz, hálózathoz, API-hoz, más apphoz vagy **bármely
  Google-szolgáltatáshoz** való jogosulatlan hozzáférés vagy beavatkozás. A policy kifejezetten
  nevesíti: az appok nem tölthetnek le, nem monetizálhatnak és nem férhetnek hozzá
  YouTube-videókhoz olyan módon, ami sérti a YouTube ToS-t. *(Play Console Help — ELLENŐRIZENDŐ.)*
- **Intellectual Property:** a más jogait sértő appokat eltávolítják.
- **Valós eset:** a `PierfrancescoSoffritti/android-youtube-player` könyvtár #192-es issue-ja
  „Violation of Device and Network Abuse policy" címmel fut — azaz a Play policy-motor **még a
  beágyazott-lejátszó könyvtárakat használó appokat is megfigyeli**, és a Play Developer
  Community-ban is van szál „Device and Network Abuse policy warning YouTube API keys" témában.
  Tanulság: a YouTube API-kulcs jelenléte önmagában triggerel vizsgálatot. *(A GitHub issue
  tartalmát nem tudtam elolvasni — a session csak a `wolfcasaba/strumsight` repót éri el.
  ELLENŐRIZENDŐ.)*

### 4.2 Apple App Store

- **Guideline 5.2.3:** az appok nem könnyíthetik meg az illegális fájlmegosztást, és nem
  tartalmazhatják harmadik fél forrásaiból (kifejezetten nevesítve: Apple Music, **YouTube**,
  SoundCloud, Vimeo) származó média mentésének, konvertálásának vagy letöltésének képességét az adott
  forrás **kifejezett engedélye** nélkül. Sőt: „streaming of audio/video content may also violate
  Terms of Use, so check before your app accesses those services", és **dokumentációt kérhetnek.**
- **Gyakorlati rejection-minta:** fejlesztők a HIVATALOS YouTube embed player használatával is kaptak
  5.2.1 / 5.2.2 elutasítást azzal, hogy az app „potenciálisan jogosulatlan hozzáférést nyújt
  harmadik fél audio/video streaming-, katalógus- és felfedező szolgáltatásaihoz". Ilyenkor az App
  Review Information mezőben **okirati bizonyítékot** kérnek a jogokról.
- **Guideline 4.2.2 (Minimum Functionality):** ha az app lényegében egy mobil webböngészés-élmény
  kevés natív funkcióval, elutasítható.

### 4.3 Amit ebből el kell kerülni

1. Ne legyen „YouTube-kliens" látszata: **ne** legyen általános YouTube-böngésző/kereső fő
   navigációként, **ne** legyen „letöltés"/„offline" gomb semmilyen formában, **ne** legyen
   playlistkezelés, feliratkozás, csatornabrowse.
2. A belépési pont legyen **link-beillesztés / megosztásból érkező videó**, ne katalógusböngészés.
   A saját tartalom (akkordsáv, gyakorlásmetrika, pengetésirány) domináljon a képernyőn — ez
   egyszerre 4.2.2-védelem és annak bizonyítéka, hogy nem YouTube-klón.
3. Készüljön elő a **review-válasz csomag**: mit csinál pontosan az app, miért nem tölt le semmit,
   milyen lejátszót használ, mi az adatáramlás. Az Apple ezt kérni fogja.

---

## 5. Adatvédelem / GDPR

### 5.1 A ténykérdés

A YouTube-beágyazás **Google-szkripteket tölt be** és **azonosítókat ír** a böngésző/WebView
tárolójába. A `youtube-nocookie.com` („privacy-enhanced mode") **nem old meg mindent**: a kutatott
források egybehangzóan azt írják, hogy a `CONSENT` süti már lejátszás nélkül is megjelenhet, és a
lejátszó **localStorage/IndexedDB** bejegyzéseket ír már betöltéskor (`yt-remote-device-id`,
`ytidb::LAST_RESULT_ENTRY_KEY`), ami eszközszintű azonosító. A pontosabb leírás: „delayed cookies",
nem „no cookies". Jogi keretként a `Fashion ID` (C-40/17, 2019. július 29.) ügy releváns: a
beágyazó oldal üzemeltetője **közös adatkezelő** lehet a beágyazott szolgáltatóval az embed által
kiváltott adatgyűjtésre és -továbbításra nézve. *(Minden forrás keresőösszefoglalóból —
ELLENŐRIZENDŐ.)*

### 5.2 Következmény a StrumSightra

Ma az app legfontosabb adatvédelmi állítása (a `docs/legal/privacy-policy-draft.md` §2-ben):
„A StrumSight detektáló motorja hálózati kérést nem indít — kijelentkezve, fiók nélkül az app
**mérten nulla hálózati kérést** küld." **A YouTube-beágyazás ezt az állítást megszünteti** a
funkció bekapcsolt állapotában. Ez a kör legnagyobb, nem jogi hanem TERMÉK-költsége.

### 5.3 Konkrét deltalista (mit kell módosítani, fájlonként)

**`docs/privacy/data-inventory.yaml`** — új egress route (a meglévő séma szerint: `id`, `source`,
`file`, `wired`, `gate`, `consent_switch`, `fields[]`, mezőnként `purpose`, `legal_basis`,
`retention`, `storage`, `leaves_device`):

- új route `youtube_embed` — `source`: a YouTube IFrame WebView; `gate`: feature flag; 
  `consent_switch`: külön, alapból KI, fail-closed opt-in (a `diagnosticsConsentProvider` mintájára);
  mezők: `youtube_player_request (video id, IP-cím, user agent, eszköz/nyelvi fejlécek)` —
  `legal_basis: consent`, `leaves_device: true`; `youtube_device_identifier (localStorage /
  IndexedDB azonosítók a WebView-ban)` — `legal_basis: consent`, `storage: device (WebView) +
  Google`, `leaves_device: true`.
- ha közösségi idővonal is lesz: új route `community_timeline_repository` a meglévő
  `account_api_community_*` mintára, mezők: `timeline_chords (video id + t→akkord lista)`,
  `timeline_author_attribution` — `leaves_device: true`.
- **Figyelem a leltár deklarált hatóköréről:** a fájl fejlécében rögzítve van, hogy ez EGRESS-leltár,
  nem on-device tárolás-leltár. A WebView által ÍRT eszközazonosító on-device tárolás IS — ezt
  érdemes kivételként külön kommentben nevesíteni, nem elhallgatni.

**`docs/store/data-safety.yaml`** — a fájl gépi kétirányú ellenőrzés alatt áll
(`test/tooling/store_package_test.dart`): minden `leaves_device: true` mezőnek KELL legyen
kategóriája. Tehát új kategóriák: `youtube_playback_request` és (ha lesz) `community_timeline_content`,
mindkettő `references[]`-szel a fenti route.id/field.name párokra. A Play Data Safety
nyilatkozatban ez „App activity" és „Device or other IDs" kategóriákat érint, és
**harmadik felekkel való megosztásként** kell bejelenteni.

**`docs/legal/privacy-policy-draft.md`** — három konkrét változás:
1. §2 („SOSEM hagyja el") — kiegészítés: a mikrofonjel továbbra sem hagyja el az eszközt, DE a
   YouTube-lejátszó bekapcsolása esetén a lejátszás a Google szervereivel kommunikál.
2. Új §-ok: „YouTube-beágyazás (opcionális)" — mi megy a Google felé (IP, user agent, video id,
   eszközazonosító), jogalap: hozzájárulás, hivatkozás a Google adatkezelési tájékoztatójára,
   és hogy a funkció kikapcsolható/visszavonható.
3. §6 („Amit MA NEM gyűjtünk") frissítése, mert az „egyetlen byte sem megy" állítás megváltozik.

**A mikrofon** már deklarált (`docs/store/permissions-rationale.md`), tehát ott nincs új engedély —
de a SZÖVEG változik: eddig „a saját játékodat hallgatjuk", ezután „a szobában szóló zenét is".
Ez a data-safety szempontból nem új kategória (a jel nem hagyja el az eszközt), de a
felhasználói tájékoztatásban őszintén meg kell mondani.

---

## 6. Technikai megfelelőségi terv

### 6.1 Lejátszó-választás

| Opció | Értékelés |
|---|---|
| **`youtube_player_iframe`** | a hivatalos IFrame Player API Flutter-portja (Android/iOS/macOS/web), a `YoutubePlayerController.getCurrentPositionStream()` pozíciófolyamot ad. **Ez az ajánlott.** |
| `youtube_player_flutter` | szintén a hivatalos iFrame Player API-ra épül, de a `youtube_player_iframe` fedi le teljesebben az API-t |
| nyers WebView | kézzel vezetett `postMessage`; több a hibalehetőség, semmi előnye — kerülendő |

Amit **soha**: `yt-dlp`/`youtube_explode` típusú stream-URL-kinyerés, natív `ExoPlayer`/`AVPlayer`
YouTube-streammel, `AudioPlaybackCapture` a saját embed hangjára.

### 6.2 Layout-szabályok (a §1.2 követelmények kódra fordítva)

- A lejátszó **a képernyő tetején**, fix 16:9 aránnyal, **soha kisebb, mint 200×200 px logikai
  pixel** — a kis telefonokra írjunk explicit `min` korlátot, és golden tesztet rá.
- Az akkord-/pengetéssáv **a lejátszó ALATT**, külön rétegben. **Semmi nem lóghat a lejátszó fölé**
  — sem overlay, sem tooltip, sem snackbar, sem a meglévő trainer HUD. Ez tesztelhető: golden +
  widget-teszt, ami a lejátszó `Rect`-jét metsző overlay-re bukik.
- Nincs teljes képernyős „csak akkordsáv" mód, amíg a videó szól (ez audio-only-vá tenné).
- Nincs második, automatikusan induló lejátszó a képernyőn.
- A YouTube-attribúció/branding a Branding Guidelines szerint látható.

### 6.3 Életciklus

A `SongTransport` **már ma helyesen viselkedik**: a konstruktora `lifecycleEvents`-re iratkozik, és
`_onLifecycleStateChanged` → `isBackgroundLifecycleState(...)` esetén
`handleInterruption(SongTransportInterruptionReason.appBackground)`-ot hív, ami szünetel
(`lib/features/song_trainer/application/trainer/song_transport.dart:496–502`). Ezt a YouTube-ág
**örökli**, feltéve hogy a YouTube-lejátszót ugyanaz a transport vezérli — tehát a háttér-lejátszás
tilalma nem új munka, hanem a meglévő út újrahasználata. Ezt ugyanakkor **külön cellával kell
lezárni**, mert regresszióként némán elromolhat.

### 6.4 Pozíció-szinkron — hogyan illeszkedik a meglévő transportba

A `SongTransport` egy `BackingAudioPlayer` interfészt vezérel
(`lib/features/song_trainer/data/playback/backing_audio_player.dart`):
`prepare / play / pause / seek / setRate / setVolume / stop` + `Stream<BackingPlaybackEvent> events`.
A transport az események közül a **`BackingPositionEvent(position)`**-t fogyasztja
(`song_transport.dart:507–522`): minden mintánál kiszámolja a mester-pozíciót
(`backingPositionFor(_activePositionNow())`), lefuttatja a `BackingDriftPolicy`-t a player
`capabilities`-e alapján, kiadja a `BackingDriftEffect`-et, és `hardResync` esetén `player.seek()`-el.
Van `backingSampleGrace = 250 ms` is: amíg friss backing-minta jön, a belső tick-source nem szól bele.

**Ebből következik a tiszta illesztés:** a YouTube-ág egy **`YoutubeBackingPlayer implements
BackingAudioPlayer`** adapter, ami

- `getCurrentPositionStream()`-ből **4–10 Hz**-en `BackingPositionEvent`-et emittál,
- a `play/pause/seek/setRate` hívásokat az IFrame API megfelelőire képezi,
- a `capabilities`-ben őszintén bevallja, amit az IFrame API nem tud pontosan (a YouTube-pozíció
  szemcsézettsége és a WebView-átvitel késleltetése miatt a drift-tolerancia lazább kell legyen,
  mint egy lokális dekóderé),
- `prepare()`-ben **nem tölt le semmit** — csak video id-t állít be.

Így **nulla új szinkron-architektúra kell**: a K1 kör által épített backing-út fogadja a YouTube-ot
is. A `setVolume`/`setRate` korlátait a `capabilities`-ben kell jelezni (az IFrame API
sebességkészlete diszkrét).

### 6.5 Mikrofon-latencia kalibráció

Ha a mikrofonos egyeztetés (B opció) bekapcsol, három késleltetés adódik össze: hangszóró→levegő→mik
(útidő + eszköz-buffer, tipikusan 20–120 ms), a WebView pozíciójelentés késése, és a DSP
elemzési ablak (kb. fél hop). Terv:
1. **Kalibrációs lépés** indításkor: rövid kattintás/impulzus a hangszórón, felvétel a mikrofonon,
   keresztkorreláció → eszközspecifikus konstans offset, eltárolva.
2. A rögzített („lock") akkordot **ne** a nyers `t`-re tegyük, hanem a meglévő
   `docs/rag/chunks/020-beat-grid-tempo-curve.md` beat-rácsára **kvantálva** — a beat-re illesztés
   elnyeli a maradék jitter nagy részét, és zeneileg helyesebb kimenetet ad.
3. A `reduced-motion` paritás kötelező: a sáv animációja nélkül is működjön minden.

### 6.6 Offline eset

Nincs hálózat vagy nincs videó → a funkció **eltűnik**, nem hibázik: a trainer a már meglévő
lokális/importált dalokkal (K1/K3-út) működik változatlanul. Fontos, hogy a YouTube-ág egy
**opcionális díszítés** legyen, ne a Song Trainer alapja — ez egyszerre termék- és jogi
kockázatcsökkentés (ha a YouTube holnap elzárja a kulcsot, nem hal meg a termék).

---

## 7. Opció-mátrix és javaslat

### 7.1 A mátrix

| # | Opció | Jogi kockázat | Termékérték | Ráfordítás | Verdikt |
|---|---|---|---|---|---|
| **A** | IFrame embed + közösségi/felhasználói idővonalak | **Közepes** (embed engedett; UGC-idővonal = DSA/DSM + kiadói származékosmű-kérdés) | Magas — hozza a „bármelyik dal" élményt | Közepes (adapter + backend + moderálás) | **SZÁLLÍTANI**, feature flag mögött |
| **B** | A + valós idejű mikrofonos egyeztetés-lock | **Közepes-magas** (ToS-szellem, precedens: Riffstation) | Nagyon magas — ez a StrumSight EGYEDI ötlete | Magas (kalibráció + jelfeldolgozás + UX) | **PILOTÁLNI** zászló mögött, előbb CI-mérés |
| **C** | A + `AudioPlaybackCapture` a saját embed hangjára | **Magas** — a „separate/isolate the audio component" tilalom közvetlen sértése | Magas (tiszta jel) | Közepes | **SOHA** |
| **D** | Szerveroldali hangkinyerés a videóból | **Nagyon magas** — letöltés + tárolás + szétválasztás, mindhárom tilos; Play/Apple eltávolítás | Magas | Magas | **SOHA** |
| **E** | Licencelt katalógus-partner (Hooktheory API, kiadói licencek) YouTube nélkül | **Alacsony** | Közepes (katalógus-korlát) | Magas (üzletfejlesztés, nem kód) | **KÉSŐBB** — ha a termék eljut a fizetős szintre |
| **F** | Csak a felhasználó saját fájljai | **Legalacsonyabb** | Közepes | **Már kész** (K1/K3) | **MEGTARTANI** alapnak |

### 7.2 Javaslat: mit szállítsunk

1. **F marad az alap.** A K1/K3 út (saját hangfájl → piszkozat-dal) a termék gerince; a
   YouTube-ág ezt kiegészíti, nem váltja ki.
2. **A-t szállítsuk** — de szűkítve: link-beillesztés vagy megosztásból érkező videó, NEM
   YouTube-böngésző; `youtube_player_iframe`; a lejátszó mindig látható és szabad; sáv alatta;
   háttérben szünet; nulla cache. Kezdetben **csak a saját, manuálisan szerkesztett idővonal**
   (a felhasználó a saját eszközén rakja össze) — a közösségi megosztás egy KÉSŐBBI kör, mert az
   hozza be a DSA/DSM-terhet.
3. **B-t pilotáljuk** zászló mögött, és **először CI-mérésként, UI nélkül** (§8/mérési terv). Ha a
   szintetikus keverékeken az egyeztetési jel nem elég erős, a funkció meg sem éri a jogi
   expozíciót.
4. **C és D: soha.** Ne legyen sem kód, sem prototípus, sem „csak kísérlet" branch — egy
   `MediaProjection` engedélykérés a manifesten hónapokra megmérgezi a store-történetet.
5. **E** jegyezve marad a roadmapen arra az esetre, ha a termék monetizál.

### 7.3 Mit kell a design-ban rögzíteni (nem alku tárgya)

- A YouTube-ág **kikapcsolható**, alapból KI, fail-closed hozzájárulással — a meglévő
  `diagnosticsConsentProvider` mintájára, mert a §5 szerint ez egress-esemény.
- A közösségi idővonalakra **takedown-cím + moderálási napló** az első naptól.
- Az akkord-idővonal a felületen mindig **„piszkozat / közösségi hozzájárulás"**-ként jelenik meg,
  soha nem „a dal hivatalos akkordjaiként" — ez a §3.1 származékosmű-kockázat csökkentése is
  (nem a hivatalos kotta helyettesítője), és összhangban van a K3 kör már bevezetett
  őszinteség-normájával.
- **Nulla cache**: se hangbuffer perzisztálás, se thumbnail-mentés YouTube-CDN-ről, se
  videómetaadat-adatbázis, ami a YouTube API-adatok engedélyezett tárolási idejét túllépi
  *(a megengedett API-adat-cache időtartama ELLENŐRIZENDŐ a Developer Policiesből)*.

### 7.4 Amiről a store-review előtt döntés kell

- Melyik piacokon jelenünk meg (EU-fókusz esetén az EMEA API ToS és a DSA a mérce).
- A közösségi idővonal bekapcsolása előtt: vállalkozási forma, árbevétel (a DSM 17(6) és a DSA
  kkv-mentességek küszöbei miatt).

### 7.5 Az öt kérdés az ügyvédnek

1. **Minősül-e többszörözésnek vagy átdolgozásnak** (Szjt. 29. §, InfoSoc 2. cikk) az, hogy az app
   mikrofonnal hallgatja a szobában szóló, YouTube-ról lejátszott zenét, és abból tranziens
   elemzéssel akkordcímkéket számol, amiket azután időbélyeggel eltárol? Ha igen: melyik mozzanat —
   a hallgatás, vagy a tárolt idővonal?
2. **Az akkord-idővonal önmagában származékos mű-e** a magyar és az uniós jog szerint, vagy a
   `Gray v. Perry`-féle „nem védhető építőkövek" kategóriába esik? Van-e olyan megjelenítési forma
   (pl. csak akkordnév + időbélyeg, ritmuskép nélkül, dalszöveg nélkül), ami a kockázatot érdemben
   csökkenti?
3. **Sérti-e a YouTube API Services ToS-t vagy a Developer Policiest** a mikrofonos hallgatás a
   saját beágyazott lejátszónk mellett — és ha a válasz „nem egyértelműen", megéri-e a kockázatot,
   tekintve, hogy a szankció (API-kulcs visszavonás, Play-eltávolítás) szerződéses, nem bírósági?
4. **A közösségi idővonal-megosztással OCSSP-vé válik-e a StrumSight** a DSM 17. cikk értelmében,
   és ha igen, alkalmazható-e a 17(6) könnyítés? Milyen minimális notice-and-action és
   statement-of-reasons folyamat elégíti ki a DSA 16–17. cikkét egy kisvállalkozásnál?
5. **Kell-e Artisjus- vagy kiadói engedély**, és ha az Artisjus az átdolgozásra nem adhat engedélyt
   (saját tájékoztatása szerint), akkor mi a reális licencút — kiadónkénti szerződés, HFA-típusú
   opt-in modell (mint UG 2010), vagy a Chordify-féle opt-out/takedown gyakorlat elfogadható
   kockázatszinten?

---

## 8. Mérési terv a (B) opcióhoz — UI előtt, CI-ben

Mielőtt egyetlen képernyő is elkészülne, a mikrofonos egyeztetés-lock jelét **offline, szintetikus
keverékeken** kell megmérni, a meglévő infrastruktúrával. A `ml/corpus/` már tartalmazza a valós
zenei klipeket és a determinisztikus negatívokat (`make_voice_negatives.py`), a
`ml/data/klangio/recording_*_phone.wav` pedig a 82 valódi gitáros telefonfelvételt. A kísérlet: a
két forrást **különböző jel-zaj arányokon keverjük** (a „zene a hangszóróból + gitár a szobában"
szituáció szimulációja, opcionálisan szobaimpulzus-válasszal és a §6.5 szerinti szintetikus
latencia-eltolással), majd a keveréket átfuttatjuk a SZÁLLÍTOTT DSP-n a
`test/tools/real_audio_probe_test.dart` harness mintájára (`DSP_PROBE=1`, `LivePipeline` +
`ClipAnalyzer`). A mért mennyiség az **egyeztetési jel**: azokon a frame-eken, ahol a gitár a
zenével azonos akkordot játszik, mennyivel emelkedik a kromagram-illeszkedés és a
`docs/rag/chunks/003-chromagram.md` szerinti tonalness/musical-presence kapu kimenete a nem-egyező
frame-ekhez képest — vagyis van-e elkülöníthető küszöb, ami a „lock"-ot kiváltja anélkül, hogy a
keverék egyszerűen az egyik forrást elnyomná. Siker-kritérium: statisztikailag stabil szeparáció
legalább két SNR-szinten, és a `PROPERTY_SEED`-es randomizált tulajdonság-kapuval nem-flaky
küszöb. Ha ez a szám nem jön ki, a (B) opciót **el kell ejteni** — a jogi expozíciót csak egy
bizonyítottan működő élmény indokolja.

---

## 9. Összefoglaló

Az embed maga a jogszerű út: a YouTube ToS kifejezetten engedi a beágyazható lejátszót, és a piac
(Chordify, Chord ai) évek óta ezen a sínen fut. A tiltott zóna éles: **letöltés, cache, tárolás, a
hangsáv leválasztása, harmadik fél lejátszója, háttérlejátszás, a lejátszó eltakarása.** A
mikrofonos ötlet pont a határvonalon van — technikailag nem nyúl a streamhez, ezért jó eséllyel
védhető, de a YouTube szerződéses tilalmai szélesebbek a szerzői jognál, és a Riffstation-precedens
azt mutatja, hogy ebben a kategóriában a kockázatot komoly szereplők is kerülték. A legnagyobb,
legkevésbé nyilvánvaló teher nem is a YouTube, hanem a **zeneműkiadói oldal** (Szjt. 29. §
átdolgozás, amire az Artisjus saját közlése szerint nem adhat engedélyt) és a **közösségi
idővonalak** DSA/DSM-terhe.

---

## 10. Források

**Letöltési státusz.** **Egyetlen külső forrás oldalát sem sikerült közvetlenül letölteni** — a
`developers.google.com`, `www.youtube.com`, `net.jogtar.hu`, `njt.jog.gov.hu`, `en.wikipedia.org`,
`web.archive.org`, `labs.polsys.net`, `youtubehelp.fandom.com`, `news.ycombinator.com` mind
`EGRESS_BLOCKED` (403), és a `curl` is 403-mal elesett a CONNECT-tunnelen. Minden alábbi forrást
**keresőmotor-összefoglalón keresztül** olvastam; a store-kiadás előtt ezeket az oldalakat **egy
hálózatilag nyitott gépen újra kell olvasni**.

### YouTube / Google (mind CSAK-KERESŐ)
- YouTube API Services Terms of Service — https://developers.google.com/youtube/terms/api-services-terms-of-service
- YouTube API Services Terms of Service (EMEA) — https://developers.google.com/youtube/terms/api-services-terms-of-service-emea
- YouTube API Services — Developer Policies — https://developers.google.com/youtube/terms/developer-policies
- Complying with YouTube's Developer Policies — https://developers.google.com/youtube/terms/developer-policies-guide
- YouTube API Services — Required Minimum Functionality — https://developers.google.com/youtube/terms/required-minimum-functionality
- YouTube API Services — Branding Guidelines — https://developers.google.com/youtube/terms/branding-guidelines
- Quota and Compliance Audits — https://developers.google.com/youtube/v3/guides/quota_and_compliance_audits
- YouTube IFrame Player API — https://developers.google.com/youtube/iframe_api_reference
- YouTube Embedded Players and Player Parameters — https://developers.google.com/youtube/player_parameters
- YouTube Terms of Service — https://www.youtube.com/t/terms
- Capturing Audio in Android Q (Android Developers Blog) — https://android-developers.googleblog.com/2019/07/capturing-audio-in-android-q.html
- Capture video and audio playback (Android) — https://developer.android.com/media/platform/av-capture

### Store policy (mind CSAK-KERESŐ)
- Google Play — Device and Network Abuse — https://support.google.com/googleplay/android-developer/answer/16559646
- Google Play Developer Policy Center — https://play.google/developer-content-policy/
- Play Developer Community — „Device and Network Abuse policy warning YouTube API keys" — https://support.google.com/googleplay/android-developer/thread/293702620
- `android-youtube-player` #192 — „Violation of Device and Network Abuse policy" — https://github.com/PierfrancescoSoffritti/android-youtube-player/issues/192
- Apple Developer Forums — „Guideline 5.2.3 — Legal — Intellectual Property — Audio/Video Downloading" — https://developer.apple.com/forums/thread/765340
- Apple Developer Forums — „Rejected app for embed Youtube video" — https://developer.apple.com/forums/thread/111383
- Apple Developer Forums — 4.2.2 Minimum Functionality — https://developer.apple.com/forums/thread/82714

### Zeneműkiadói jog / piac (mind CSAK-KERESŐ)
- HFA + Ultimate Guitar sajtóközlemény (2010-04-06) — https://www.scoringnotes.com/wp-content/uploads/2023/12/HFAUltimateGuitar_20100406_Final.pdf
- Ultimate Guitar — https://en.wikipedia.org/wiki/Ultimate-Guitar
- „Guitar Tabs, Fair Use, and the Internet" (William & Mary Law Review) — https://scholarship.law.wm.edu/cgi/viewcontent.cgi?article=1166&context=wmlr
- Chordify — „Does this not infringe copyright?" — https://support.chordify.net/hc/en-us/articles/360001420738
- Chordify — Terms and Conditions — https://chordify.net/pages/terms-and-conditions/
- Songsterr — About / Help — https://www.songsterr.com/about · https://www.songsterr.com/help
- Yousician Support — „Why can't I find a popular song in Yousician" — https://support.yousician.com/hc/en-us/articles/360000758937
- Moises — „How do streaming services work, and why can't we accept their URL links on Moises?" — https://help.moises.ai/hc/en-us/articles/18322457396508
- Moises — Terms of Service — https://help.moises.ai/hc/en-us/articles/7401394754962-Terms-of-Service
- Chord ai — „How do I select a song?" — https://www.chordai.net/faq/how-do-i-select-a-song/
- Chord ai — https://www.chordai.net/
- Capo (SuperMegaUltraGroovy) — https://supermegaultragroovy.com/products/capo/features/get-chords/
- Riffstation leállása — https://diaryofdennis.com/2018/05/17/here-are-the-alternatives-to-the-fender-riffstation/ · https://songsurgeon.com/page/riffstation_alternative.html
- Gray v. Perry (Loeb & Loeb) — https://www.loeb.com/en/insights/publications/2022/03/gray-v-perry
- Gray v. Perry / „Dark Horse" (Irwin IP) — https://irwinip.com/2022/03/chord-progression-katy-perry-found-to-have-copied-deemed-uncopyrightable/
- Hooktheory Trends API dokumentáció — https://www.hooktheory.com/api/trends/docs

### EU / magyar jog (mind CSAK-KERESŐ)
- InfoSoc irányelv 2001/29/EK — https://eur-lex.europa.eu/eli/dir/2001/29/oj/eng
- DSM irányelv (EU) 2019/790 — https://eur-lex.europa.eu/eli/dir/2019/790/oj/eng
- Bizottsági iránymutatás a 17. cikkhez (COM(2021) 288) — https://eur-lex.europa.eu/legal-content/EN/TXT/HTML/?uri=CELEX%3A52021DC0288
- DSA 16. cikk — https://www.eu-digital-services-act.com/Digital_Services_Act_Article_16.html
- DSA hatály és kötelezettségek (Ropes & Gray) — https://www.ropesgray.com/en/insights/viewpoints/102j0f0/reminder-eu-digital-services-act-applies-beyond-very-large-online-service-prov
- Szjt. — 1999. évi LXXVI. törvény — https://net.jogtar.hu/jogszabaly?docid=99900076.tv · https://njt.jog.gov.hu/jogszabaly/1999-76-00-00.29
- Artisjus — „Mire nem adhat engedélyt az Artisjus?" — https://www.artisjus.hu/felhasznaloknak/mas-felhasznalas/mire-nem-adhat-engedelyt-az-artisjus/
- Artisjus — Átdolgozások — https://www.artisjus.hu/szerzoknek/mubejelentes/atdolgozasok/
- „Szerzői jog mindenkinek" (Tempus Közalapítvány, Szjt. 35. § ismertetés) — https://tka.hu/docs/palyazatok/szerzOi_jog_mindenkinek_v2.pdf

### GDPR / beágyazás (mind CSAK-KERESŐ)
- „Are YouTube Embeds GDPR Compliant?" — https://consently.net/blog/is-youtube-embed-gdpr-compliant
- „youtube-nocookie.com Explained" — https://swarmify.com/blog/what-is-youtube-nocookie/
- „Embed YouTube videos without cookies" (Axbom) — https://axbom.com/embed-youtube-videos-without-cookies/
- YouTube nocookie és GDPR — https://www.flowconsent.com/en/blog/youtube-nocookie-embed-videos-without-cookies-gdpr

### Flutter
- `youtube_player_iframe` — https://pub.dev/packages/youtube_player_iframe (CSAK-KERESŐ)
- `youtube_player_flutter` — https://pub.dev/packages/youtube_player_flutter (CSAK-KERESŐ)

### Repón belüli hivatkozások (LETÖLTVE / helyben olvasva)
- `lib/features/song_trainer/application/trainer/song_transport.dart` (életciklus: 496–502; pozíció/drift: 507–522)
- `lib/features/song_trainer/data/playback/backing_audio_player.dart` (`BackingAudioPlayer`, `BackingPositionEvent`)
- `docs/privacy/data-inventory.yaml` · `docs/store/data-safety.yaml` · `docs/legal/privacy-policy-draft.md`
- `ml/corpus/README.md` · `test/tools/real_audio_probe_test.dart` · `docs/rag/chunks/003-chromagram.md` · `docs/rag/chunks/020-beat-grid-tempo-curve.md`
