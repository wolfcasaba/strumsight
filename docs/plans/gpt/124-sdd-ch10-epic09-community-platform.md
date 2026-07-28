---
id: 124
topic: SDD Ch10 / Epic 9 — Community Platform: 32 kör (public UUID+handle, follow/block, feed, aszinkron challenge, verified leaderboard, moderation, modular monolith backend)
tags: [sdd, epic9, community, backend, privacy, moderation, leaderboard, feed]
status: active
depends_on: [105, 111]
canonical_target: docs/sdd/10-epic-09-community-platform.md
as_built: docs/sdd/10-epic-09-community-platform.md (E01-R01, r207)
verify: block azonnal érvényesül minden útvonalon + verified receipt anti-replay tesztek + offline learning érintetlen
source: chatgpt-plan 2026-07-28 (Codex Execution Pack, batch 2)
---

# StrumSight Software Design Document

## Chapter 10 — Epic 9: Community Platform

**Dokumentumverzió:** 1.0  
**Státusz:** fejlesztésre kész specifikáció  
**Repository:** `wolfcasaba/strumsight`  
**Elsődleges kliens:** Flutter, Android-first  
**Backend:** FastAPI modular monolith, PostgreSQL, opcionális Redis és objektumtár  
**Tervezési alapelv:** privacy-first, learning-first, asynchronous-first, safety-by-design  
**Közösségi alapelv:** a tanulás és a támogató kapcsolatok fontosabbak a népszerűségnél  
**Kapcsolódó fejezetek:** Chapter 2 Core Platform, Chapter 3 Practice Engine, Chapter 4 Song Trainer, Chapter 5 AI Guitar Teacher, Chapter 6 Computer Vision, Chapter 7 Audio Analysis 2.0, Chapter 8 AI Practice Generator, Chapter 9 Gamification  
**Végrehajtó:** Codex  
**Végrehajtási mód:** külön branchben vagy külön, önálló commitban végzett kis fejlesztési körök

---

# 1. Az Epic célja

Az Epic 9 célja egy biztonságos, támogató és tanulásközpontú közösségi platform létrehozása a StrumSightban.

A Community nem lehet egy általános közösségi hálózat gitáros témával. A rendszernek a gyakorlást, a fejlődés megosztását, a pozitív visszajelzést, a közös kihívásokat és a zenei felfedezést kell támogatnia anélkül, hogy a felhasználókat követőszám, állandó összehasonlítás vagy végtelen feed alapján értékelné.

A fejezet végeredménye egy olyan közösségi réteg, amely:

- opcionális, és kijelentkezett állapotban sem korlátozza az offline tanulási funkciókat;
- nem küld nyers audio-, video-, vision- vagy practice adatot automatikusan a szerverre;
- csak kifejezetten kiválasztott tartalmat tesz közzé;
- a belső e-mail és numerikus user ID helyett nyilvános, stabil azonosítókat használ;
- támogatja a nyilvános vagy korlátozott profilt;
- támogatja a követést, tiltást és eltávolítást;
- időrendi, magyarázható feedet biztosít;
- támogatja a gyakorlási eredmények, dalrészletek, kihívások és eredménykártyák megosztását;
- kezeli a reakciókat, kommenteket és könyvjelzőket;
- támogatja az aszinkron baráti és közösségi kihívásokat;
- csak ellenőrzött, összehasonlítható eredményt enged kompetitív ranglistára;
- támogat kisebb klubokat és tanulócsoportokat;
- rendelkezik report, block, moderation és appeal folyamattal;
- ellenáll a spamnek, replaynek, XP-manipulációnak és automatizált visszaélésnek;
- offline outboxszal és determinisztikus konfliktuskezeléssel működik;
- accessibility, localization és reduced-motion szempontból teljes értékű;
- moduláris monolitként indul, és nem hoz létre idő előtt külön mikroszolgáltatásokat.

Az Epic nem a maximális engagementre optimalizál. A siker mércéje az, hogy a közösségi funkciók segítik-e a felhasználót a gyakorlásban, visszatérésben és tanulásban, miközben a biztonsági és adatvédelmi kockázatokat kontroll alatt tartják.

---

# 2. Termékvízió

## 2.1 Felhasználói ígéret

A kívánt élmény:

> Befejezted a heti ritmusgyakorlatodat. Készíthetsz egy adatvédelmi szempontból biztonságos eredménykártyát, megoszthatod a barátaiddal, és meghívhatod őket ugyanarra az aszinkron kihívásra. A posztból nem derül ki több adat, mint amit közzététel előtt látsz és jóváhagysz.

A nem kívánt élmény:

> A rendszer automatikusan feltöltötte a teljes felvételedet, nyilvánossá tette a gyenge pontszámodat, és egy globális ranglistán ismeretlen játékosokkal hasonlít össze.

## 2.2 Learning-first közösség

A Community feladata:

- megkönnyíteni az eredmények önkéntes megosztását;
- társas támogatást adni a gyakorláshoz;
- közös, elérhető célokat kínálni;
- segíteni jó gyakorlatok és eredeti tanulási tartalmak felfedezését;
- lehetővé tenni a fejlődés ünneplését;
- közösségi kontextust adni a kihívásoknak és mastery mérföldköveknek;
- biztonságos kapcsolatot biztosítani barátok, tanulók és opcionálisan mentorok között.

A Community nem:

- határozza meg a szakmai skill score-t;
- írja felül a Practice Generator tervét;
- számol újra audio- vagy vision-metrikát;
- teszi kötelezővé a versenyt;
- jutalmazza a követőszámot tanulási XP-vel;
- árul láthatóságot vagy ranglistapozíciót;
- használ dark patternt a feedben;
- támogat anonim privát üzenetet az Epic részeként;
- enged automatikus médiafeltöltést;
- közöl pontos helyadatot vagy e-mail címet.

## 2.3 Asynchronous-first

Az első Community verzió aszinkron.

Támogatott:

- poszt és komment;
- követés;
- eredménymegosztás;
- aszinkron challenge;
- klubcél;
- értesítési inbox;
- opcionális, rövid késleltetésű event-frissítés.

Nem része ennek az Epicnek:

- live audio jam;
- videóhívás;
- peer-to-peer stream;
- privát chat;
- typing indicator;
- állandó online presence;
- valós idejű multiplayer score race.

Ezek külön threat modelt, gyermekvédelmi tervet, folyamatos moderációt és jelentősen nagyobb infrastruktúrát igényelnek.

## 2.4 Privacy-first megosztás

Minden megosztási folyamatban a felhasználónak közzététel előtt látnia kell:

- a poszt előnézetét;
- a célközönséget;
- a megosztott mezőket;
- azt, hogy tartalmaz-e felvételt;
- azt, hogy tartalmaz-e pontszámot;
- azt, hogy a tartalom bekerülhet-e challenge-be vagy ranglistába;
- a tartalom törölhetőségének és lejáratának állapotát.

A rendszer alapértelmezése az adatminimalizálás.

## 2.5 Egészséges társas összehasonlítás

A Community külön kezeli:

- a személyes fejlődést;
- a társas aktivitást;
- a versenyeredményt;
- a népszerűséget.

A követőszám, like és komment nem növelhet learning XP-t vagy skill masteryt.

A ranglista:

- opt-in;
- időszakos;
- összehasonlítható challenge eredményből épül;
- verified státuszt használ;
- baráti vagy kisebb cohort nézetet részesít előnyben;
- lehetővé teszi a teljes elrejtést;
- nem mutat gyenge teljesítményt szégyenítő módon.

## 2.6 Sikerdefiníció

Az Epic sikeres, ha:

- a felhasználó önkéntesen, pontosan kontrollálhatja a megosztott adatokat;
- a feed használható végtelen görgetés nélkül;
- blokk után a két fél tartalma és interakciója azonnal elválik;
- ugyanaz a lokális poszt retry esetén sem duplikálódik;
- a komment és reakció optimista UI mellett konzisztens marad;
- a kihívás replay nem ad kétszer eredményt;
- nem ellenőrzött lokális XP nem kerül globális ranglistára;
- report után a tartalom a bejelentő számára azonnal elrejthető;
- a felhasználó letöltheti és törölheti saját közösségi adatait;
- account-disabled állapotban a Community nem indít hálózati kérést;
- a tanulási és audio funkciók Community nélkül változatlanul működnek.

---

# 3. Kapcsolat a jelenlegi kódbázissal

## 3.1 Meglévő account backend

A repository jelenleg tartalmaz:

- FastAPI alkalmazást;
- `User` adatmodellt belső numerikus ID-val;
- e-mail alapú regisztrációt és bejelentkezést;
- JWT bearer tokent;
- bcrypt jelszókezelést;
- egy-egy kapcsolatú `UserSettings` modellt;
- opcionális cloud settings syncet;
- rate limitert;
- diagnosztikai végpontokat;
- SQLite fejlesztői és opcionális PostgreSQL konfigurációt.

A Community nem használhatja az e-mail címet nyilvános identitásként. A belső numerikus adatbázis-ID sem kerülhet API response-ba stabil publikus user ID-ként.

## 3.2 Meglévő Flutter auth réteg

A kliens tartalmaz:

- `AuthRepository` implementációt;
- secure token storage-ot;
- `AuthUser` modellt;
- auth provider réteget;
- login képernyőt;
- opcionális account feature flaget.

A Community kizárólag bejelentkezett és community-enabled állapotban inicializálható. Az offline gitártanulás account nélkül továbbra is teljes értékű marad.

## 3.3 Meglévő Share feature

A Share feature már rendelkezik:

- heti recap modellel;
- share preview képernyőkkel;
- Strum Card és Wrapped Card widgetekkel;
- rendszer share sheet integrációval;
- renderelhető, kontrollált vizuális kártyákkal.

Ez jó alap a `CommunityShareArtifact` létrehozásához. A Community poszt ne másolja be közvetlenül más feature belső modelljét, hanem verziózott, minimális share artifactot használjon.

## 3.4 Meglévő Progress, Practice és Gamification adatok

A korábbi fejezetek létrehozzák vagy meghatározzák:

- canonical learning eventeket;
- idempotens reward ledgert;
- verified és unverified reward státuszt;
- Practice session resultot;
- Song performance resultot;
- Analysis insightokat;
- Computer Vision evidence-et;
- achievementeket, questeket és challenge-eket;
- local outboxot;
- stabil event ID-ket.

A Community ezekből kizárólag exportált, közlésre alkalmas nézetet használhat. Nem olvashat nyers DSP frame-et, teljes analysis dokumentumot, nyers video landmarkot vagy belső reward ledgert.

## 3.5 Meglévő Songs és Setlists

A projekt már tartalmaz lokális dalokat és setlisteket. A Chapter 4 ezt SongDocument V2 rendszerre bővíti.

Community szempontból külön kell választani:

- a felhasználó saját eredeti dalát;
- a nyilvánosan megosztható akkordmenetet vagy gyakorlatsablont;
- a személyes könyvtári bejegyzést;
- a szerzői jog által védett dal metaadatát;
- a jogtulajdonos engedélye nélkül nem publikálható teljes tabot, backing tracket vagy audioanyagot.

A Community nem tehet automatikusan nyilvánossá lokális SongDocumentet.

## 3.6 Azonosított technikai adósságok

Az Epic során rendezendő:

1. Nincs publikus profilazonosító és egyedi handle.
2. Az `AuthUser` nem rendelkezik community profile projectionnel.
3. Nincs privacy és audience domain.
4. Nincs social graph.
5. Nincs block vagy mute.
6. Nincs community outbox és idempotency szerződés.
7. Nincs poszt- és feedmodell.
8. Nincs cursor pagination.
9. Nincs komment, reakció vagy bookmark.
10. Nincs media upload infrastruktúra.
11. Nincs report és moderation workflow.
12. Nincs challenge invitation backend.
13. Nincs verified leaderboard projection.
14. Nincs notification inbox.
15. Nincs account data export és community deletion workflow.
16. Nincs public API boundary a Share és Gamification feature-ek felé.
17. A backend schema még nem használ Communityhez szükséges Alembic migrációkat.
18. Nincs szerveroldali idempotency key tárolás.
19. Nincs spam- és abuse-rate limiting policy.
20. Nincs Community feature flag vagy kill switch.

---

# 4. Kapcsolat a korábbi SDD-fejezetekkel

## 4.1 Chapter 2 — Core Platform

Kötelezően újrahasználandó:

- `AppResult` és `AppFailure`;
- `Clock`;
- konfiguráció és feature flag;
- közös Dio/API kliens;
- secure storage;
- local outbox mintázat;
- strukturált logging és redaction;
- Alembic;
- liveness és readiness;
- CI architecture guard.

## 4.2 Chapter 3 — Practice Engine

A Practice Engine exportálhat:

- session summaryt;
- durationt;
- gyakorolt skill tageket;
- pontossági sávot;
- personal bestet;
- share-safe progress delta értéket;
- stabil session ID-t.

A Community nem férhet hozzá a Practice Engine belső scoreréhez vagy audio frame-jeihez.

## 4.3 Chapter 4 — Song Trainer

A Song Trainer exportálhat:

- song title vagy display label;
- section label;
- completion state;
- tempo és score sávot;
- saját eredeti arrangement share artifactot;
- challenge-compatible performance resultot.

Szerzői jogi státusz nélkül teljes tab, teljes dalszöveg, backing track vagy védett audio nem publikálható.

## 4.4 Chapter 5 — AI Guitar Teacher

Az AI Tutor:

- javasolhat közösségi kihívást;
- megfogalmazhat posztvázlatot;
- összefoglalhat megosztható eredményt;
- nem tehet közzé automatikusan;
- nem küldhet kommentet a felhasználó nevében megerősítés nélkül;
- nem férhet hozzá privát feedhez modellprovideren keresztül explicit adatkezelési engedély nélkül.

## 4.5 Chapter 6 — Computer Vision

Vision adatból alapértelmezetten csak:

- aggregált, share-safe technikai insight;
- confidence sáv;
- user-approved snapshot vagy klip

használható.

Nyers landmark stream, arcazonosító vagy háttérből származó személyes adat nem kerül Community payloadba.

## 4.6 Chapter 7 — Audio Analysis 2.0

Az Analysis exportálhat verziózott `AnalysisShareSummary` nézetet.

Nem megosztható automatikusan:

- teljes waveform;
- nyers audio;
- részletes technikai diagnosztika;
- eszközazonosító;
- fájlrendszerútvonal;
- rejtett confidence vagy debug adat.

## 4.7 Chapter 8 — AI Practice Generator

A tervből megosztható:

- sablon;
- cél;
- blokklista;
- időtartamsáv;
- szükséges eszköz;
- skill tag;
- szerző és forrás.

A felhasználó személyes evidence-e és gyenge pontjai nem kerülhetnek bele más által importálható tervbe.

## 4.8 Chapter 9 — Gamification

A Gamification biztosítja:

- stable challenge ID-t;
- verified receiptet;
- achievement share artifactot;
- XP és level projectiont;
- integrity státuszt.

Közösségi like, follow és posztaktivitás nem generál learning XP-t. A Community ranglista csak server-verified challenge receiptből épülhet.

---

# 5. Hatókör

## 5.1 Az Epic része

- community feature flag és account gate;
- nyilvános community UUID;
- egyedi handle és display name;
- profil, avatar, bio és skill interest;
- privacy és audience beállítás;
- follow, unfollow, follower removal;
- block és mute;
- profilkeresés;
- feed és cursor pagination;
- share artifactból létrehozott poszt;
- szöveges poszt limitált formában;
- reakció, komment és bookmark;
- report és moderation queue;
- aszinkron challenge meghívás;
- challenge eredmény és verified leaderboard;
- club/group alapfunkció;
- notification inbox és push abstraction;
- offline outbox;
- optimistic UI és rollback;
- médiafeltöltési szerződés és opcionális rövid klip;
- content retention és delete;
- adat export;
- anti-spam és anti-cheat;
- audit és observability;
- localization és accessibility;
- teljes backend és Flutter tesztstratégia.

## 5.2 Nem része ennek az Epicnek

- privát üzenet és chat;
- hang- vagy videóhívás;
- live jam session;
- nyilvános pontos helymegosztás;
- marketplace;
- fizetett promóció;
- reklámrendszer;
- tipping vagy creator payment;
- követővásárlás;
- anonim poszt;
- automatikus arcfelismerés;
- background contact upload;
- telefonszám alapú friend discovery;
- teljes zenei streaming;
- jogtulajdonos engedélye nélküli tab vagy backing track terjesztés;
- szerveroldali újraszámított audio scoring;
- komplex professzionális coach marketplace;
- földrajzi közelség szerinti ismeretlen-felfedezés.

---

# 6. Kötelező termék- és biztonsági invariánsok

1. Kijelentkezett állapotban a Community nem inicializál hálózati klienst.
2. Account létrehozása nem kötelező az alapvető tanulási funkciókhoz.
3. E-mail cím soha nem nyilvános profilmező.
4. Belső adatbázis-ID nem kerül publikus API-ba.
5. Megosztás csak explicit felhasználói művelettel történik.
6. Nyers audio vagy video nem töltődik fel automatikusan.
7. A poszt célközönsége közzététel előtt látható.
8. A blokk minden olvasási és írási útvonalon érvényesül.
9. A törölt poszt nem maradhat feed cache-ben tartósan.
10. Follow és reaction nem ad learning XP-t.
11. Globális ranglistára csak verified receipt kerülhet.
12. Replayelt challenge result nem hozhat létre új helyezést.
13. A feednek van vége és manuális folytatása; nincs kötelező végtelen görgetés.
14. A moderation döntés auditálható.
15. A reportoló személye nem kerül a jelentett felhasználóhoz.
16. A felhasználó saját posztját és kommentjét törölheti.
17. A felhasználó a nyilvános profilját deaktiválhatja.
18. A felhasználó letilthatja a ranglistás részvételt.
19. Push értesítés alapértelmezetten minimális és kategóriánként kikapcsolható.
20. Community hiba nem ronthatja el a lokális practice session mentését.

---

# 7. Célarchitektúra

## 7.1 Flutter feature szerkezet

```text
lib/features/community/
├── domain/
│   ├── entities/
│   │   ├── community_profile.dart
│   │   ├── community_post.dart
│   │   ├── community_comment.dart
│   │   ├── community_reaction.dart
│   │   ├── community_challenge.dart
│   │   ├── community_club.dart
│   │   ├── notification_item.dart
│   │   └── moderation_state.dart
│   ├── value_objects/
│   │   ├── public_user_id.dart
│   │   ├── community_handle.dart
│   │   ├── audience.dart
│   │   ├── cursor_page.dart
│   │   └── content_id.dart
│   ├── repositories/
│   └── policies/
├── application/
│   ├── controllers/
│   ├── use_cases/
│   ├── mappers/
│   ├── outbox/
│   └── providers/
├── data/
│   ├── api/
│   ├── dto/
│   ├── local/
│   ├── repositories/
│   └── sync/
├── presentation/
│   ├── screens/
│   ├── widgets/
│   ├── dialogs/
│   └── routes/
└── public.dart
```

## 7.2 Backend szerkezet

```text
backend/app/community/
├── models/
├── schemas/
├── repositories/
├── services/
├── policies/
├── moderation/
├── feed/
├── notifications/
├── routers/
└── tasks/
```

A backend kezdetben modular monolith. A Community ugyanabban a deployban működik, de saját modul- és adatboundaryval.

## 7.3 Függőségi szabály

```text
Flutter Presentation → Application → Domain
Flutter Data ───────────────────────→ Domain

FastAPI Router → Service → Repository → SQLAlchemy
                         ↘ Policy
```

Tiltott:

- Community domain → Flutter;
- Community domain → Dio;
- feed service → FastAPI request object;
- SQLAlchemy model közvetlen visszaadása API response-ként;
- más Flutter feature belső data rétegének importálása;
- Community → raw DSP vagy camera engine;
- routerben üzleti policy implementálása.

## 7.4 Modular monolith döntés

Az első verzióban nem készül külön:

- feed service;
- moderation service;
- notification service;
- media service.

Ezek modulok ugyanazon backenden belül. Külön szolgáltatás csak mérés alapján indokolt.

---

# 8. Nyilvános identitás és profil domain

## 8.1 PublicUserId

A nyilvános user azonosító:

- UUIDv7 vagy más időrendbarát, nem kitalálható UUID;
- soha nem e-mail;
- soha nem belső integer primary key;
- változtathatatlan;
- API-ban stringként jelenik meg.

```dart
extension type const PublicUserId(String value) {}
```

## 8.2 Handle

A handle:

- egyedi;
- kis- és nagybetűtől független összehasonlítású;
- 3–24 karakter;
- normalizált Unicode kezelésű;
- megengedett karakterkészlete dokumentált;
- tiltott szólistát használ;
- reserved namespace-t véd;
- változtatása rate-limited;
- korábbi handle rövid ideig redirectként fenntartható;
- nem árul el e-mailt vagy telefonszámot.

Példa:

```text
@wolfcasaba
```

## 8.3 Display name

A display name:

- nem egyedi;
- 1–40 karakter;
- Unicode-kompatibilis;
- moderálható;
- nem használható belépési azonosítóként.

## 8.4 Profilmezők

```dart
final class CommunityProfile {
  const CommunityProfile({
    required this.userId,
    required this.handle,
    required this.displayName,
    required this.visibility,
    required this.avatar,
    required this.bio,
    required this.skillInterests,
    required this.badges,
    required this.relationship,
    required this.createdAt,
  });
}
```

Támogatott mezők:

- avatar;
- rövid bio;
- stílusérdeklődések;
- gitártípus vagy hangszerérdeklődés;
- opcionálisan kiválasztott mastery badge-ek;
- nyilvános challenge statisztika;
- opcionális időzóna helyett csak széles régió vagy semmi;
- account created date durva formában.

Nem támogatott nyilvános mezők:

- e-mail;
- pontos születési dátum;
- pontos cím;
- valós idejű hely;
- eszközazonosító;
- teljes practice history;
- belső AI profil;
- sérülési vagy egészségügyi jegyzet;
- nyers technikai gyengeséglista.

## 8.5 Profil visibility

```dart
enum ProfileVisibility {
  private,
  followers,
  public,
}
```

`private` esetén:

- minimális handle és avatar placeholder megjelenhet kapcsolatkezeléshez;
- posztok nem kereshetők;
- követés request-alapú lehet;
- leaderboard részvétel alapértelmezetten tiltott.

---

# 9. Audience és adatvédelmi policy

## 9.1 Audience típus

```dart
enum CommunityAudience {
  onlyMe,
  followers,
  club,
  public,
}
```

A `club` audience külön club ID-t igényel.

## 9.2 Alapértelmezés

Új account esetén:

- profil: `private` vagy termékdöntés alapján `followers`, de nem automatikusan public;
- poszt audience: az utoljára választott biztonságos érték, első alkalommal `followers`;
- leaderboard: kikapcsolt;
- kereshetőség: kikapcsolt vagy minimális;
- push: csak security és közvetlen challenge invite, további kategóriák opt-in.

## 9.3 Field-level sharing

A share composer külön kapcsolókat adhat:

- score megjelenítése;
- duration megjelenítése;
- streak megjelenítése;
- XP/level megjelenítése;
- song title megjelenítése;
- audio clip csatolása;
- video clip csatolása;
- device/gear megjelenítése.

A kapcsolók alapértelmezetten konzervatívak.

## 9.4 Privacy enforcement

A privacy policy szerveroldali.

A kliens elrejthet UI-elemeket, de nem tekinthető biztonsági határnak.

Minden read query ellenőrzi:

- profile visibility;
- post audience;
- follow kapcsolat;
- club membership;
- block kapcsolat;
- moderation state;
- deletion state.

---

# 10. Social graph

## 10.1 Follow modell

Az alapkapcsolat irányított follow.

```text
A follows B
```

Private profilnál request lifecycle:

```text
requested → accepted | declined | cancelled
```

Public profilnál:

```text
none → following
```

## 10.2 Baráti nézet

A „friends” fogalom kölcsönös followból származtatható. Nem szükséges külön friendship tábla az első verzióban.

## 10.3 Follower removal

A profil tulajdonosa eltávolíthat követőt anélkül, hogy blockolná.

Private profilnál az eltávolított user elveszíti a follower-only tartalomhoz való hozzáférést.

## 10.4 Mute

A mute:

- csak a mutoló személy nézetét befolyásolja;
- nem értesíti a másik felet;
- elrejti a feed posztot és opcionálisan az értesítést;
- nem szünteti meg a follow kapcsolatot.

## 10.5 Block

A block szimmetrikus láthatósági hatású:

- egyik fél sem látja a másik profilját, posztját vagy kommentjét;
- follow kapcsolatok törlődnek;
- pending invite törlődik vagy invalidálódik;
- közös klubban a tartalom minimalizált placeholderként vagy teljesen rejtve jelenik meg;
- challenge nem indítható;
- értesítések törlődnek vagy elrejtődnek;
- keresés nem adja vissza a felhasználót.

Block feloldás nem állítja vissza automatikusan a korábbi follow kapcsolatot.

## 10.6 Social graph invariánsok

- Self-follow tiltott.
- Self-block tiltott.
- Dupla follow rekord tiltott.
- Pending request egyedi párra.
- Block elsőbbséget élvez minden audience szabállyal szemben.
- A kapcsolatmutációk idempotensek.

---

# 11. Poszt és share artifact domain

## 11.1 CommunityPost

```dart
final class CommunityPost {
  const CommunityPost({
    required this.id,
    required this.author,
    required this.audience,
    required this.body,
    required this.artifact,
    required this.media,
    required this.createdAt,
    required this.editedAt,
    required this.moderationState,
    required this.viewerState,
    required this.counts,
  });
}
```

## 11.2 Poszttípusok

Első verzió:

- practice summary;
- song performance summary;
- analysis improvement;
- achievement;
- challenge result;
- practice-plan template;
- original song vagy progression;
- rövid szöveges update;
- club announcement.

## 11.3 Share artifact

```dart
sealed class CommunityShareArtifact {
  const CommunityShareArtifact({
    required this.schemaVersion,
    required this.sourceId,
    required this.createdAt,
  });

  final int schemaVersion;
  final String sourceId;
  final DateTime createdAt;
}
```

Minden artifact:

- minimális;
- immutable;
- verziózott;
- explicit mezőkkel rendelkezik;
- nem tartalmaz belső repository objektumot;
- nem tartalmaz tokeneket vagy fájlútvonalat;
- szerveroldalon validálható;
- a forrásevent törlése után is kezelhető adatvédelmi policy szerint.

## 11.4 Body szabály

- maximum hossz dokumentált;
- plain text vagy szűk markdown subset;
- script és HTML tiltott;
- linkek safe redirecten vagy plain textként;
- mention parser szerveroldalon validál;
- hashtag csak későbbi discovery indexhez;
- edit history auditált, de nem feltétlenül publikus.

## 11.5 Törlés és szerkesztés

Szerkeszthető:

- body;
- audience szigorítható vagy lazítható policy szerint;
- kiválasztott share mezők;
- alt text.

Nem módosítható úgy, hogy:

- más challenge result kerüljön ugyanazon post ID mögé;
- más authorra váltson;
- verified receipt kicserélődjön.

Törlés soft-delete-del indul, majd retention policy után hard-delete következhet.

---

# 12. Médiafeltöltés

## 12.1 MVP médiahatár

A Community MVP működjön médiafeltöltés nélkül is, renderelt share carddal.

A rövid audio/video klip külön feature flag mögött vezethető be.

## 12.2 Upload folyamat

Javasolt:

1. kliens media metadata requestet küld;
2. backend validálja a jogosultságot, típust és limitet;
3. backend signed upload URL-t ad;
4. kliens közvetlenül objektumtárba tölt;
5. backend finalization endpoint ellenőrzi a checksumot és metaadatot;
6. scan/transcode/moderation állapot indul;
7. a poszt csak `ready` médiát jelenít meg.

## 12.3 Médiakorlátok

Konfigurálható:

- audio maximum időtartam;
- video maximum időtartam;
- maximum fájlméret;
- codec allowlist;
- felbontás;
- frame rate;
- napi upload quota;
- account age vagy trust gate.

## 12.4 Biztonság

- MIME sniffing;
- extensionre nem támaszkodó validáció;
- vírus- vagy malware scanning;
- metadata stripping;
- EXIF és location eltávolítás;
- audio/video transcode;
- content hash;
- signed URL lejárat;
- bucket private by default;
- CDN csak tokenizált vagy policy-ellenőrzött hozzáféréssel;
- orphan upload cleanup.

## 12.5 Copyright és jogosultság

A composer világosan jelzi, hogy a felhasználó csak olyan médiát tölthet fel, amelyhez joga van.

A rendszer:

- ne csatoljon automatikusan backing tracket;
- ne töltse fel automatikusan az importált dal teljes audioját;
- támogasson copyright report kategóriát;
- tárolja a takedown auditot;
- tegye lehetővé repeat infringement policy későbbi bevezetését;
- ne állítsa automatikusan, hogy jogi megfelelőség garantált; jogi felülvizsgálat szükséges a publikus indulás előtt.

---

# 13. Feed architektúra

## 13.1 Feed típusok

Első verzió:

- Following feed;
- Club feed;
- saját profil feed;
- opcionális Explore feed feature flag mögött.

## 13.2 Following feed

A Following feed alapértelmezetten időrendi, korlátozott minőségi szabályokkal:

- követett profilok posztjai;
- saját posztok opcionálisan;
- block és mute szűrés;
- audience ellenőrzés;
- moderation szűrés;
- cursor pagination.

Nem használ engagement-maximalizáló fekete doboz rangsort.

## 13.3 Explore feed

Explore csak későbbi rolloutban aktív.

Rangsortényezők lehetnek:

- frissesség;
- tartalomtípus-diverzitás;
- felhasználó által választott skill interest;
- content quality gate;
- report rate;
- ismétlődő szerzők korlátozása.

Nem lehet elsődleges tényező:

- követőszám;
- fizetés;
- agresszív engagement;
- személyes gyenge pontokból levont érzékeny profil.

A rangsor verziózott és auditálható.

## 13.4 Cursor pagination

Offset pagination helyett opaque cursor.

A cursor tartalmazhat:

- sort key;
- stable post ID;
- feed version;
- signed integrity érték.

A kliens nem értelmezi a cursort.

## 13.5 Feed consistency

- Duplikált post ID nem jelenhet meg egy sessionben.
- Törölt poszt cache invalidálódik.
- Block azonnal érvényesül.
- Új post refreshre vagy explicit prepend eventre kerül a listába.
- Feed refresh nem mozdítja el kontrollálatlanul a scroll pozíciót.
- End-of-feed egyértelmű.

## 13.6 Tudatos használat

A feed:

- nem indul automatikusan videóval és hanggal;
- nem végtelen autoplay;
- rendelkezik „Ennyi volt mára” vagy end state nézettel;
- a gyakorlás indítása láthatóbb lehet, mint a további görgetés;
- értesítési badge nem használ megtévesztő számlálót.

---

# 14. Reakciók, kommentek és könyvjelzők

## 14.1 Reakciók

Kezdeti allowlist:

- support;
- celebrate;
- inspiring;
- helpful.

A negatív downvote nem része az első verziónak.

Egy user reakciója posztonként egy érték, amely cserélhető vagy eltávolítható.

## 14.2 Kommentek

- egy szintű reply támogatás vagy maximum dokumentált depth;
- plain text;
- mention;
- edit window;
- delete;
- report;
- author és post owner moderation jog;
- rate limit;
- blocked relation enforcement.

A végtelenül mély thread tiltott.

## 14.3 Bookmark

A bookmark:

- privát;
- nem számít publikus engagementnek;
- practice-plan és song-template import belépési pontja lehet;
- törölt tartalom esetén tombstone-t kezel;
- account exportban szerepel.

## 14.4 Count consistency

A reaction és comment count lehet eventually consistent, de:

- nem lehet negatív;
- viewer state legyen azonnal konzisztens;
- retry ne növelje duplán;
- moderált vagy törölt komment csökkentése determinisztikus;
- a count nem tekinthető pénzügyi vagy tanulási igazságnak.

---

# 15. Kihívások és verseny

## 15.1 Challenge típusok

- baráti aszinkron challenge;
- club challenge;
- napi community challenge;
- időszakos globális challenge;
- személyes eredmény megdöntése, megosztható formában.

## 15.2 ChallengeDefinition

```dart
final class CommunityChallengeDefinition {
  const CommunityChallengeDefinition({
    required this.id,
    required this.version,
    required this.type,
    required this.contentRef,
    required this.metric,
    required this.difficulty,
    required this.startsAt,
    required this.endsAt,
    required this.eligibility,
    required this.verificationPolicy,
  });
}
```

## 15.3 Invite lifecycle

```text
draft → sent → accepted | declined | expired | cancelled
accepted → active → completed | forfeited | expired
```

Minden transition szerveroldali policyvel történik.

## 15.4 Comparable result

Versenyeredmény csak akkor összehasonlítható, ha egyezik:

- challenge definition ID és version;
- scorer/model version vagy elfogadott kompatibilitási sáv;
- difficulty;
- tempo vagy tempo band;
- metric;
- completion policy;
- integrity requirement.

## 15.5 Verified receipt

A kliens feltölti a minimális result payloadot és a canonical event/receipt azonosítót.

A backend ellenőrzi:

- auth user;
- idempotency;
- challenge window;
- eligible client/app version;
- score range;
- duration és timestamp plauzibilitás;
- receipt signature vagy server-issued nonce;
- replay;
- optional attestation status.

A backend nem állítja, hogy a csalás teljesen lehetetlen. Trust tier és anomaly state szükséges.

## 15.6 Leaderboard

Támogatott scope:

- friends;
- club;
- challenge global;
- opcionális régió, csak önkéntes széles régióval.

Rendezés:

- challenge metric;
- tie-breaker dokumentált;
- stable rank;
- saját helyezés külön lekérhető;
- cursor pagination.

Nincs all-time total XP global leaderboard az első verzióban.

## 15.7 Fairness

- külön difficulty band;
- optional experience cohort;
- accessibility mód nem okozhat automatikus kizárást;
- device performance eltérés vizsgálandó;
- low-confidence eredmény nem kerül verified ranglistára;
- a felhasználó mindig gyakorolhat ranglista nélkül.

---

# 16. Klubok és tanulócsoportok

## 16.1 Club célja

A klub kisebb, témaközpontú közösség:

- kezdő akkordváltás;
- blues improvizáció;
- fingerstyle;
- baráti zenekar;
- tanár által létrehozott tanulócsoport.

## 16.2 Club visibility

```dart
enum ClubVisibility {
  private,
  discoverable,
  public,
}
```

## 16.3 Szerepkörök

- owner;
- moderator;
- member.

A szerepkörök permission mátrixa explicit és szerveroldali.

## 16.4 Club funkciók

- profil és leírás;
- tags;
- tagság request/invite;
- club feed;
- pinned post;
- club challenge;
- tag eltávolítás;
- member removal;
- leave;
- ownership transfer;
- report.

## 16.5 Club limit

Az első verzió dokumentált limiteket használ:

- maximum tagság userenként;
- maximum tag klubonként;
- maximum napi invite;
- maximum pinned post;
- maximum active challenge.

A számok konfigurációból érkeznek.

## 16.6 Biztonsági korlát

A club nem ad privát chatet. A komment és poszt ugyanazt a moderation rendszert használja, mint a nyilvános Community.

---

# 17. Notification rendszer

## 17.1 Notification inbox

Minden közösségi értesítés először tartós inbox item.

Típusok:

- follow request;
- follow accepted;
- reaction summary;
- comment;
- mention;
- challenge invite;
- challenge completed;
- club invite;
- moderation decision;
- security alert.

## 17.2 Push

A push csak delivery channel, nem elsődleges adatforrás.

A payload minimális:

- notification ID;
- type;
- route-safe entity ID;
- localization key vagy szerver által nem érzékeny preview;
- sem token, sem teljes komment, sem privát adat.

## 17.3 Preference

Kategóriánként:

- in-app;
- push;
- disabled.

Kötelező vagy erősen javasolt security értesítés külön kategória.

## 17.4 Aggregation

Több reakció aggregálható:

> 5 ember reagált a gyakorlási eredményedre.

Nem szükséges öt külön push.

## 17.5 Quiet hours

A kliens helyi quiet hourt használhat push presentationhöz. A backend nem következtet pontos helyre.

---

# 18. Moderation és safety

## 18.1 Moderation state

```dart
enum ModerationState {
  visible,
  limited,
  pendingReview,
  removed,
  authorOnly,
}
```

## 18.2 Report kategóriák

- harassment;
- hate or abusive conduct;
- sexual content;
- dangerous content;
- spam;
- impersonation;
- privacy violation;
- copyright;
- self-harm concern;
- other.

A kategóriák lokalizáltak és jogi/safety felülvizsgálatot igényelnek publikus indulás előtt.

## 18.3 User report flow

1. user kiválasztja az objektumot;
2. kategóriát választ;
3. opcionális leírást ad;
4. dönthet az azonnali hide/block felől;
5. report idempotensen mentődik;
6. tartalom a reportoló számára azonnal elrejthető;
7. moderation queue-ba kerül;
8. döntés auditált;
9. szükség esetén appeal elérhető.

## 18.4 Automated moderation

Automatikus eszköz használható:

- spam prioritásra;
- tiltott linkre;
- ismétlődő tartalomra;
- kockázati triage-ra;
- media scanningre.

Az automatikus modell:

- nem lehet az egyetlen végleges döntéshozó súlyos account actionnél;
- verziózott;
- confidence-et ad;
- auditált;
- fellebbezhető folyamatba illeszkedik;
- nem kap több személyes adatot a szükségesnél.

## 18.5 Enforcement lépcsők

- content warning;
- visibility limit;
- content removal;
- feature cooldown;
- temporary community suspension;
- permanent community suspension;
- account-level action csak dokumentált policy alapján.

Learning data ne törlődjön automatikusan community suspension miatt.

## 18.6 Block és safety shortcut

Minden profil- és tartalomképernyőn elérhető:

- mute;
- block;
- report.

A report soha nem követeli, hogy a user továbbra is lássa a tartalmat.

## 18.7 Kiskorúak és korhatár

A publikus indulás előtt külön jogi és product döntés szükséges a minimum korhatárról és a kiskorúak kezeléséről.

Amíg nincs validált gyermekvédelmi rendszer:

- privát üzenet nincs;
- pontos hely nincs;
- contact discovery nincs;
- profilmezők minimalizáltak;
- sensitive targeting nincs;
- age-specific discovery nincs.

---

# 19. Anti-spam, abuse és integritás

## 19.1 Rate limit rétegek

Külön limit:

- account;
- IP/network;
- endpoint;
- entity pair;
- device/session;
- trust tier.

Példák:

- follow request/nap;
- comment/perc;
- post/nap;
- mention/post;
- challenge invite/nap;
- media upload/nap;
- report/óra.

## 19.2 Idempotency

Minden create/mutation támogat kliens által generált idempotency keyt.

Kötelező:

- create post;
- comment;
- reaction set/remove;
- follow request;
- challenge result;
- club invite;
- report.

A backend a keyt user + operation scope-ban tárolja dokumentált retentionnel.

## 19.3 Spam signal

- account age;
- request velocity;
- ismétlődő body hash;
- link density;
- block/report rate;
- failed upload;
- invite acceptance ratio;
- anomalous graph growth.

Ezek moderációs signalok, nem publikus score-ok.

## 19.4 Anti-cheat

- challenge nonce;
- server time window;
- receipt deduplication;
- model/scorer version;
- impossible score validation;
- app integrity signal opcionálisan;
- anomaly review;
- verified/unverified tier;
- server-authoritative leaderboard projection.

Nem szabad a kliens által küldött `rank`, `xp` vagy `verified=true` értéket elfogadni.

## 19.5 Sybil-korlát

Az account létrehozás maradjon hozzáférhető, de magas kockázatú community actionhöz fokozatos trust gate használható.

Nem kötelező valós személyazonosság vagy telefonszám. A gate lehet:

- account age;
- verified e-mail későbbi bevezetése;
- normál tanulási aktivitás;
- alacsony abuse signal;
- rate limit.

---

# 20. Backend adatmodell

## 20.1 Fő táblák

Javasolt PostgreSQL táblák:

```text
community_profiles
community_handle_history
community_privacy_settings
community_follows
community_follow_requests
community_blocks
community_mutes
community_posts
community_post_media
community_comments
community_reactions
community_bookmarks
community_reports
community_moderation_actions
community_notifications
community_clubs
community_club_members
community_club_invites
community_challenges
community_challenge_participants
community_challenge_results
community_leaderboard_entries
community_idempotency_records
community_outbox_events
community_audit_events
```

## 20.2 Profil

Fontos mezők:

```text
id                BIGINT internal PK
public_id         UUID UNIQUE NOT NULL
user_id           FK users.id UNIQUE NOT NULL
handle_normalized UNIQUE NOT NULL
handle_display    NOT NULL
display_name      NOT NULL
bio               nullable
avatar_media_id   nullable
visibility        NOT NULL
status            NOT NULL
created_at
updated_at
```

## 20.3 Follow

Unique constraint:

```text
(follower_profile_id, followed_profile_id)
```

Check:

```text
follower_profile_id != followed_profile_id
```

## 20.4 Post

Fontos mezők:

```text
public_id
profile_id
audience
club_id nullable
body nullable
artifact_type nullable
artifact_schema_version nullable
artifact_payload JSONB nullable
moderation_state
created_at
edited_at nullable
deleted_at nullable
```

JSONB kizárólag verziózott, validált artifacthoz használható. Alapvető kapcsolati adat ne legyen kontrollálatlan JSONB-ben.

## 20.5 Reakció

Unique:

```text
(post_id, profile_id)
```

A reaction type update-ként változik.

## 20.6 Komment

- parent ID maximum egy támogatott depth szerint;
- post ID;
- author ID;
- body;
- moderation state;
- edit timestamp;
- delete timestamp.

## 20.7 Challenge result

Tárolja:

- challenge ID és version;
- participant ID;
- result ID;
- source event ID;
- metric value;
- secondary tie-breaker;
- verification state;
- integrity signals minimalizált formában;
- submitted/verified timestamp;
- disqualification reason code.

## 20.8 Indexek

Kötelező indexek mérés alapján:

- profile handle normalized;
- post author + created_at;
- post audience + created_at;
- follow follower/followed;
- comment post + created_at;
- notification recipient + read state + created_at;
- challenge status + end date;
- leaderboard challenge + metric;
- moderation queue state + priority + created_at;
- idempotency user + operation + key.

## 20.9 Migráció

Minden schema változás Alembic.

Követelmények:

- forward migration;
- legalább dokumentált rollback stratégia;
- nagy tábla módosításnál lock kockázat;
- backfill külön lépés;
- nullable → backfill → not null minta;
- production `create_all` tiltott.

---

# 21. API szerződés

## 21.1 Általános szabályok

- verziózott prefix: `/v1/community`;
- JWT auth;
- public UUID;
- ISO-8601 UTC timestamp;
- opaque cursor;
- idempotency header vagy body field;
- stabil error code;
- request ID;
- Pydantic response schema;
- SQLAlchemy model nem kerül közvetlenül response-ba.

## 21.2 Profil endpointok

```text
POST   /v1/community/profile
GET    /v1/community/profile/me
PATCH  /v1/community/profile/me
GET    /v1/community/profiles/{public_user_id}
GET    /v1/community/handles/{handle}
GET    /v1/community/search/profiles?q=...
```

## 21.3 Social graph

```text
POST   /v1/community/profiles/{id}/follow
DELETE /v1/community/profiles/{id}/follow
POST   /v1/community/follow-requests/{id}/accept
POST   /v1/community/follow-requests/{id}/decline
DELETE /v1/community/followers/{id}
POST   /v1/community/profiles/{id}/block
DELETE /v1/community/profiles/{id}/block
POST   /v1/community/profiles/{id}/mute
DELETE /v1/community/profiles/{id}/mute
```

## 21.4 Feed és post

```text
GET    /v1/community/feed/following
GET    /v1/community/feed/club/{club_id}
GET    /v1/community/profiles/{id}/posts
POST   /v1/community/posts
GET    /v1/community/posts/{post_id}
PATCH  /v1/community/posts/{post_id}
DELETE /v1/community/posts/{post_id}
```

## 21.5 Interakció

```text
PUT    /v1/community/posts/{post_id}/reaction
DELETE /v1/community/posts/{post_id}/reaction
GET    /v1/community/posts/{post_id}/comments
POST   /v1/community/posts/{post_id}/comments
PATCH  /v1/community/comments/{comment_id}
DELETE /v1/community/comments/{comment_id}
PUT    /v1/community/posts/{post_id}/bookmark
DELETE /v1/community/posts/{post_id}/bookmark
```

## 21.6 Challenge és leaderboard

```text
GET    /v1/community/challenges
POST   /v1/community/challenges/{id}/invite
POST   /v1/community/challenge-invites/{id}/accept
POST   /v1/community/challenge-invites/{id}/decline
POST   /v1/community/challenges/{id}/results
GET    /v1/community/challenges/{id}/leaderboard
GET    /v1/community/challenges/{id}/me
```

## 21.7 Club

```text
POST   /v1/community/clubs
GET    /v1/community/clubs/{id}
PATCH  /v1/community/clubs/{id}
POST   /v1/community/clubs/{id}/join
POST   /v1/community/clubs/{id}/leave
POST   /v1/community/clubs/{id}/invites
PATCH  /v1/community/clubs/{id}/members/{member_id}
DELETE /v1/community/clubs/{id}/members/{member_id}
```

## 21.8 Moderation

```text
POST   /v1/community/reports
GET    /v1/community/moderation/cases
POST   /v1/community/moderation/cases/{id}/actions
POST   /v1/community/moderation/actions/{id}/appeal
```

Moderation endpoint csak megfelelő admin/moderator authnál elérhető.

## 21.9 Data rights

```text
POST   /v1/community/data-export
GET    /v1/community/data-export/{job_id}
POST   /v1/community/deactivate
DELETE /v1/community/profile
```

## 21.10 Hibakódok

Példák:

```text
community_disabled
profile_required
handle_unavailable
profile_private
relationship_blocked
post_not_found
post_not_visible
invalid_audience
rate_limited
content_rejected
challenge_expired
challenge_not_eligible
result_duplicate
result_unverified
club_permission_denied
moderation_action_required
```

A kliens lokalizált üzenetet választ a stabil kód alapján.

---

# 22. Offline outbox és szinkron

## 22.1 Offline-first határ

A Community hálózatot igényel, de az alkalmazás offline tanulási része nem.

Offline állapotban támogatott:

- korábban cache-elt saját profil és feed olvasása egyértelmű offline jelzéssel;
- draft készítése;
- poszt sorba állítása;
- reakció sorba állítása;
- bookmark sorba állítása;
- komment draft;
- challenge result sorba állítása, ha az eligibility és időablak policy megengedi.

## 22.2 Outbox item

```dart
final class CommunityMutation {
  const CommunityMutation({
    required this.id,
    required this.type,
    required this.entityId,
    required this.payload,
    required this.createdAt,
    required this.attemptCount,
    required this.state,
  });
}
```

## 22.3 Idempotency

A mutation ID egyben idempotency key lehet.

Ugyanaz a mutation:

- retry esetén ugyanazt az eredményt adja;
- app restart után folytatható;
- siker után tombstone vagy compacted record formában maradhat a dedup időablakig.

## 22.4 Konfliktusok

Policy:

- reaction: last intended viewer state wins;
- bookmark: last intended viewer state wins;
- follow: server relationship state az elsődleges, block felülír;
- post create: idempotens;
- post edit: version vagy ETag szükséges;
- comment edit: version szükséges;
- profile edit: field-level vagy whole-resource version;
- challenge result: first valid submission vagy challenge policy szerinti best result;
- delete: általában elsőbbséget élvez későbbi editnél.

## 22.5 Optimistic UI

Optimistic mutáció megengedett:

- reaction;
- bookmark;
- follow public profilnál;
- local post draft/send állapot.

A UI mutassa:

- pending;
- failed;
- retry;
- conflict;
- removed by policy.

Hiba esetén ne veszítse el a felhasználó által beírt szöveget.

---

# 23. Cache és adatmegőrzés

## 23.1 Kliens cache

Cache-elhető:

- profil summary;
- feed page;
- saját post;
- notification inbox;
- challenge definition;
- leaderboard page rövid TTL-lel.

Nem cache-elhető tartósan védelem nélkül:

- signed media URL;
- moderation admin adat;
- token;
- más felhasználó törölt privát tartalma.

## 23.2 Cache invalidation

Események:

- post delete;
- audience változás;
- block;
- follow acceptance;
- profile visibility;
- moderation removal;
- media state;
- club membership.

## 23.3 Retention

Külön retention policy:

- aktív poszt;
- soft-deleted poszt;
- report evidence;
- moderation audit;
- idempotency record;
- notification;
- orphan media;
- security log;
- data export artifact.

A pontos időtartamokat jogi, product és üzemeltetési felülvizsgálat után konfigurációban kell rögzíteni.

## 23.4 Saját adat törlése

Community profile törlésekor:

- profil deaktiválódik;
- posztok és kommentek policy szerint törlődnek vagy anonimizálódnak;
- media deletion job indul;
- follow graph törlődik;
- leaderboard entry kezelése dokumentált;
- moderation audit jogszerűen szükséges része elkülönítve maradhat;
- lokális learning history nem törlődik automatikusan, hacsak a teljes account törlés ezt nem kéri.

---

# 24. Notification és optional realtime transport

## 24.1 Polling alap

Az első stabil verzió használhat:

- app launch refresh;
- pull-to-refresh;
- periodikus foreground inbox syncet;
- push-triggered refresh-et.

## 24.2 WebSocket/SSE

Opcionális későbbi transport:

- új notification;
- challenge state változás;
- moderation state;
- post count refresh.

Nem szállít teljes feedet vagy médiafolyamot.

## 24.3 Reconnect

- exponential backoff;
- jitter;
- foreground-only vagy lifecycle-aware;
- token refresh;
- resume cursor/event ID;
- duplicate event dedup;
- hálózati hiba nem okoz végtelen reconnect loopot.

## 24.4 Kill switch

Remote vagy environment feature flag letilthatja:

- explore feedet;
- media uploadot;
- leaderboardot;
- club creationt;
- realtime transportot;
- teljes Community write-ot;
- teljes Community feature-t.

A tanulási funkciók ettől tovább működnek.

---

# 25. UI és navigáció

## 25.1 Fő navigáció

A Community nem feltétlenül kap azonnal elsődleges bottom-nav helyet. Rollout döntés:

- Home/More belépési pont;
- később külön tab, ha használat és biztonság indokolja.

Képernyők:

```text
Community Gate / Create Profile
Following Feed
Profile
Edit Profile
Followers / Following
Search
Post Composer
Post Detail
Comments
Notifications
Challenges
Leaderboard
Clubs
Club Detail
Bookmarks
Privacy & Safety
Blocked / Muted users
Report flow
Data export / Deactivation
```

## 25.2 Composer flow

1. forrás kiválasztása vagy share action;
2. share artifact előnézet;
3. mezők kapcsolása;
4. szöveg;
5. alt text média esetén;
6. audience;
7. copyright/consent jelzés szükség szerint;
8. végső preview;
9. publish;
10. pending/success/failure állapot.

## 25.3 Feed card

Megjeleníti:

- szerző;
- timestamp;
- audience jelzés saját posztnál;
- artifact;
- body;
- opcionális media kontrolláltan;
- reakció és komment;
- overflow safety menü;
- moderation placeholder.

## 25.4 Médiavezérlés

- autoplay alapértelmezetten kikapcsolt;
- hang némítva vagy explicit play;
- captions/alt text;
- reduced motion;
- data saver;
- Wi-Fi-only media opció;
- sensitive content warning, ha releváns.

## 25.5 Empty és error state

A feed üres állapota ne kényszerítsen contact uploadra.

Javasolhat:

- handle alapján keresést;
- klub felfedezést;
- első eredmény megosztását;
- visszatérést a gyakorláshoz.

---

# 26. Accessibility és localization

## 26.1 Accessibility

Kötelező:

- teljes screen reader label;
- logikus traversal order;
- minimum touch target;
- 2.0 text scale;
- kontraszt;
- reduced motion;
- autoplay tiltás;
- reaction ikonhoz szöveges label;
- leaderboard sor értelmes felolvasása;
- progress ne csak színnel;
- moderation state érthető;
- media alt text;
- captions mező támogatása.

## 26.2 Localization

Minden user-facing szöveg ARB-ban:

- relationship állapot;
- audience;
- privacy;
- moderation;
- report kategória;
- challenge lifecycle;
- notification;
- error;
- accessibility label.

Magyar és angol parity kötelező.

## 26.3 User-generated content

A user-generated content nem automatikusan fordítandó az első verzióban.

A platform UI és moderation kategóriák lokalizáltak. AI fordítás csak későbbi explicit funkcióként, forrásnyelv jelzéssel vezethető be.

---

# 27. Observability és analytics

## 27.1 Strukturált backend event

Példák:

- community_profile_created;
- post_created;
- post_create_failed;
- follow_requested;
- block_created;
- report_created;
- moderation_action_applied;
- challenge_result_verified;
- challenge_result_rejected;
- outbox_retry;
- media_scan_failed.

## 27.2 Redaction

Tilos logolni:

- JWT;
- e-mail;
- teljes post body;
- teljes komment;
- média bytes;
- signed URL;
- pontos IP tartósan indokolatlanul;
- nyers audio/video;
- report érzékeny leírása normál application logban.

## 27.3 Product analytics

Mérhető aggregáltan, megfelelő consent és adatminimalizálás mellett:

- profil létrehozási funnel;
- share composer completion;
- challenge acceptance;
- feed → practice conversion;
- block/report rate;
- notification opt-out;
- moderation turnaround;
- offline outbox failure.

Nem elsődleges siker KPI:

- session time a feedben;
- kontrollálatlan scroll depth;
- követőszám maximalizálása.

## 27.4 SLO javaslat

Első production célok méréssel véglegesítendők:

- profil/feed read rendelkezésre állás;
- post create success;
- notification delivery;
- moderation queue latency;
- media processing latency;
- challenge verification latency.

---

# 28. Tesztelési stratégia

## 28.1 Domain unit tesztek

- handle normalizálás;
- audience policy;
- follow state machine;
- block precedence;
- post edit policy;
- challenge lifecycle;
- leaderboard ordering;
- club permission;
- moderation state;
- outbox conflict.

## 28.2 Property-based tesztek

Invariánsok:

- self-follow soha;
- block után visibility false;
- idempotent create nem duplikál;
- reaction count nem negatív;
- cursor lapok nem duplikálnak;
- challenge rank stabil;
- delete elsőbbség;
- private post nem kerül public feedbe;
- leaderboard csak verified resultot tartalmaz.

## 28.3 Backend integration

PostgreSQLlel:

- migration;
- unique constraint;
- transaction race;
- permission query;
- cursor pagination;
- block query;
- idempotency;
- moderation;
- data deletion;
- challenge submit;
- leaderboard.

SQLite-only teszt nem elegendő a Community production viselkedéséhez.

## 28.4 Flutter repository teszt

- DTO mapping;
- error mapping;
- ETag conflict;
- offline cache;
- outbox replay;
- optimistic update;
- rollback;
- feature flag;
- logout cleanup.

## 28.5 Widget és golden

- feed card típusok;
- composer;
- private profile;
- block state;
- moderation placeholder;
- comment thread;
- leaderboard;
- club role;
- offline state;
- 2.0 text scale;
- dark/light;
- magyar/angol.

## 28.6 Security teszt

- IDOR;
- audience bypass;
- block bypass;
- forged author ID;
- forged verified flag;
- replay;
- XSS/HTML;
- path traversal;
- upload MIME mismatch;
- signed URL reuse;
- rate limit;
- admin endpoint auth;
- report identity leak.

## 28.7 Load teszt

Mérés:

- following feed fan-out;
- celebrity-like nagy follower count szélső eset;
- comment burst;
- challenge leaderboard;
- notification burst;
- media finalization;
- moderation queue.

A backend csak mérés alapján kap Redis cache-t vagy worker queue-t.

---

# 29. Codex végrehajtási szabályok

Minden körben:

1. Olvasd el az `AGENTS.md`, a kapcsolódó SDD-fejezeteket és az érintett teszteket.
2. Csak az adott kört implementáld.
3. Ne vezesd be a következő kör API-ját indokolatlanul.
4. Minden backend schema változás Alembic migráció.
5. Minden create mutáció idempotens legyen.
6. Minden read útvonalon teszteld az audience és block policyt.
7. Ne logolj user-generated contentet teljes szöveggel.
8. Ne adj learning XP-t közösségi engagementért.
9. Ne fogadj el kliens által állított verified vagy rank értéket.
10. Ne tölts fel médiafájlt explicit user action nélkül.
11. Ne implementálj privát chatet vagy live jamet ebben az Epicben.
12. Ne hozz létre új mikroszolgáltatást benchmark nélkül.
13. Futtasd külön a Flutter- és backendteszteket.
14. Frissítsd a `HANDOFF.md` és az Epic completion státuszát.
15. A kör végén adj módosított fájllistát, teszteredményt, kockázatot és elhalasztott feladatot.

---

# 30. Fejlesztési körök


---

# Kör 1 — Community baseline, ADR-ek és feature flag

## Cél

A Community fejlesztés biztonsági, adatvédelmi és architekturális kereteinek rögzítése alkalmazáskód-változtatás nélkül.

## Feladatok

- Hozd létre a `docs/sdd/10-epic-09-community-platform.md` fájlt és frissítsd az SDD indexet.
- Készíts ADR-t az asynchronous-first Communityről, a privát üzenet és live jam elhalasztásáról.
- Készíts ADR-t a modular monolith backendről és a nyilvános UUID használatáról.
- Készíts threat modelt: identity, IDOR, audience bypass, block bypass, spam, media upload, challenge replay, moderation abuse.
- Adj `communityEnabled`, `communityWritesEnabled`, `communityMediaEnabled`, `communityLeaderboardEnabled` és `communityClubsEnabled` feature flaget.
- Dokumentáld a backend és mobil rollout kill switch viselkedését.
- Készíts baseline leltárt a jelenlegi auth, share, progress, gamification és backend modulokról.

## Fő érintett fájlok

```text
docs/adr/00xx-community-asynchronous-first.md
docs/adr/00xx-community-modular-monolith.md
docs/security/community-threat-model.md
lib/app/config/feature_flags.dart
backend/app/config.py
```

## Kötelező tesztek

- AppConfig development/lab/production feature flag teszt
- Production default community-disabled teszt
- Dokumentációs linkellenőrzés

## Elfogadási feltételek

- [ ] A Community productionben explicit engedély nélkül nem indul.
- [ ] A threat model legalább az összes kötelező invariánst lefedi.
- [ ] Nincs új hálózati kérés és nincs funkcionális regresszió.

## Javasolt commit

```text
docs(community): establish privacy and architecture baseline
```

---

# Kör 2 — Backend Community modul és Alembic alap

## Cél

A Community backend moduláris határának és első adatbázis-migrációjának létrehozása.

## Feladatok

- Hozd létre a `backend/app/community` modul szerkezetét router, service, repository, policy és schema réteggel.
- Adj `community_profiles` és `community_privacy_settings` táblát Alembic migrációval.
- A meglévő `users` táblához egy-egy community profile kapcsolat tartozzon, de profil csak explicit létrehozáskor készüljön.
- Használj public UUID-t és belső bigint primary keyt.
- Adj community readiness ellenőrzést, amely productionben PostgreSQL kompatibilitást és migration headet ellenőriz.
- Ne regisztráld a routert, ha a Community feature flag kikapcsolt.
- Készíts factory-alapú dependency override-olható tesztalkalmazást.

## Fő érintett fájlok

```text
backend/app/community/__init__.py
backend/app/community/models/profile.py
backend/app/community/schemas/profile.py
backend/app/community/routers/profile.py
backend/alembic/versions/*_community_profile.py
```

## Kötelező tesztek

- Alembic upgrade üres adatbázison
- Community router hiánya disabled módban
- Public UUID uniqueness
- User–profile one-to-one constraint
- Readiness migration mismatch

## Elfogadási feltételek

- [ ] Productionben nincs `create_all` alapú Community schema.
- [ ] A profile tábla nem szivárogtat belső user ID-t API-ba.
- [ ] A modul önálló dependency boundaryval rendelkezik.

## Javasolt commit

```text
feat(community): add backend module and profile schema
```

---

# Kör 3 — Public identity és handle policy

## Cél

Biztonságos publikus identitás, handle-normalizálás és névfoglalás megvalósítása.

## Feladatok

- Implementáld a public UUID generálást injektálható ID generatorral.
- Implementáld a handle Unicode-normalizálást, case-foldingot, hossz- és karaktervalidációt.
- Készíts reserved és blocked handle policyt konfigurálható katalógussal.
- Adj adatbázis-szintű egyediséget a normalizált handle-re.
- Implementáld az availability endpointot rate limittel; ne legyen user enumerationre alkalmas tömeges API.
- Adj handle change cooldownt és handle history táblát rövid redirect időablakkal.
- Biztosítsd, hogy e-mailből ne keletkezzen automatikus nyilvános handle.

## Fő érintett fájlok

```text
backend/app/community/policies/handle_policy.py
backend/app/community/services/identity_service.py
backend/app/community/models/handle_history.py
backend/app/community/routers/handles.py
```

## Kötelező tesztek

- Unicode normalization property teszt
- Case-insensitive collision
- Reserved handle
- Concurrent handle claim
- Cooldown
- E-mail leak regresszió

## Elfogadási feltételek

- [ ] Két vizuálisan/normalizáltan azonos handle nem foglalható le.
- [ ] A public ID stabil és nem kitalálható szekvenciális integer.
- [ ] Az availability API nem ad érzékeny account információt.

## Javasolt commit

```text
feat(community): implement public identity and handle policy
```

---

# Kör 4 — Profil privacy, audience és szerveroldali policy

## Cél

A profil- és audience-hozzáférési döntések központi, tesztelt policy rétegének létrehozása.

## Feladatok

- Implementáld a `ProfileVisibility` és `CommunityAudience` backend és Flutter enumokat stabil wire értékkel.
- Készíts `CommunityAccessPolicy` szolgáltatást minden profile/post readhez.
- Private profilnál csak minimális relationship-safe summary legyen elérhető.
- Adj privacy settings endpointot optimistic concurrency vagy resource version mezővel.
- Alapértelmezett profil ne legyen automatikusan public.
- Adj leaderboard opt-in, search discoverability és mention permission beállítást.
- Készíts policy matrix dokumentumot viewer/owner/follower/blocked/club member kombinációkra.

## Fő érintett fájlok

```text
backend/app/community/policies/access_policy.py
backend/app/community/schemas/privacy.py
backend/app/community/routers/privacy.py
docs/security/community-access-matrix.md
```

## Kötelező tesztek

- Audience policy paraméterezett tesztek
- Private profile read
- Follower-only read
- Blocked override
- Stale privacy update conflict

## Elfogadási feltételek

- [ ] A szerver minden readnél policyt alkalmaz.
- [ ] Block mindig felülírja a follow- és club-jogosultságot.
- [ ] A kliens UI elrejtése nem az egyetlen védelem.

## Javasolt commit

```text
feat(community): enforce profile and audience privacy policies
```

---

# Kör 5 — Flutter Community domain és public API

## Cél

Flutter-oldali, framework-független Community domain és stabil feature boundary létrehozása.

## Feladatok

- Hozd létre a Chapter 7-ben meghatározott feature mappastruktúrát.
- Implementáld a public ID, handle, audience, profile summary, relationship és cursor page value objectokat.
- Készíts repository interfészeket profile, social graph, feed, post, challenge, club és notification területre.
- Használj immutable state-et és explicit `copyWith`/equality szabályt.
- Exportálj kizárólag stabil típusokat a `public.dart` fájlból.
- Adj architecture guardot, amely tiltja más feature Community data/presentation importját és fordítva.
- Ne adj még hálózati implementációt vagy teljes UI-t.

## Fő érintett fájlok

```text
lib/features/community/domain/**
lib/features/community/public.dart
test/features/community/domain/**
tool/check_architecture.dart
```

## Kötelező tesztek

- Value object validáció
- Serialization wire enum
- Cursor opacity
- Architecture dependency teszt
- Domain Flutter-import tiltás

## Elfogadási feltételek

- [ ] A domain nem importál Fluttert, Dio-t vagy SharedPreferences-t.
- [ ] Más feature csak a Community public API-t használhatja.
- [ ] Minden wire enum ismeretlen értéket kontrolláltan kezel.

## Javasolt commit

```text
feat(community): establish Flutter domain and public boundary
```

---

# Kör 6 — Profil létrehozás, szerkesztés és Community gate UI

## Cél

A felhasználó kontrolláltan hozhasson létre és szerkeszthessen közösségi profilt.

## Feladatok

- Implementáld a Community belépési gate-et: disabled, logged-out, profile-missing és ready állapot.
- Készíts profile repository Dio implementációt a közös API klienssel.
- Készíts handle availability debounced ellenőrzést és lokális validációt.
- Készíts profil létrehozó és szerkesztő képernyőt avatar placeholderrel, display name-mel, bio-val és interest tagekkel.
- A privacy beállítás legyen a létrehozó flow explicit lépése.
- Hiba esetén őrizd meg a formadatot; dupla submitot blokkolj.
- Logoutkor töröld a Community személyes cache-t és pending érzékeny draftot policy szerint.

## Fő érintett fájlok

```text
lib/features/community/data/repositories/profile_repository_impl.dart
lib/features/community/application/controllers/profile_controller.dart
lib/features/community/presentation/screens/community_gate_screen.dart
lib/features/community/presentation/screens/edit_profile_screen.dart
```

## Kötelező tesztek

- Logged-out gate
- Feature-disabled gate
- Handle debounce
- Duplicate submit
- Validation localization
- Logout cache cleanup
- 2.0 text scale widget teszt

## Elfogadási feltételek

- [ ] Community profil csak explicit user actionre készül.
- [ ] A privacy alapérték látható és módosítható.
- [ ] Hálózati hiba nem veszti el a kitöltött profilt.

## Javasolt commit

```text
feat(community): add profile onboarding and editing flow
```

---

# Kör 7 — Follow és follow request social graph

## Cél

Idempotens, privacy-kompatibilis követési rendszer implementálása.

## Feladatok

- Adj `community_follows` és `community_follow_requests` migrációt egyedi constrainttel.
- Implementáld public profilnál az azonnali follow-t, private profilnál a request lifecycle-t.
- Implementáld accept, decline, cancel, unfollow és follower removal műveleteket.
- Minden mutáció kapjon idempotency keyt és stabil response state-et.
- Készíts follower/following cursor pagination endpointot.
- Kliensen optimistic follow csak public profilnál legyen; private requestnél pending state jelenjen meg.
- Race esetekben adatbázis constraint és tranzakció biztosítsa az invariánst.

## Fő érintett fájlok

```text
backend/app/community/models/social_graph.py
backend/app/community/services/follow_service.py
backend/app/community/routers/social_graph.py
lib/features/community/application/controllers/relationship_controller.dart
```

## Kötelező tesztek

- Self-follow
- Duplicate follow
- Concurrent request
- Private accept/decline
- Follower removal
- Cursor pagination
- Optimistic rollback

## Elfogadási feltételek

- [ ] Duplikált kapcsolat nem keletkezik retry vagy versenyhelyzet miatt.
- [ ] Private tartalom csak elfogadott kapcsolat után látszik.
- [ ] Follower removal nem igényel blockot.

## Javasolt commit

```text
feat(community): implement privacy-aware follow graph
```

---

# Kör 8 — Block, mute és safety kapcsolatkezelés

## Cél

A felhasználó azonnal és megbízhatóan megszakíthassa a nem kívánt interakciókat.

## Feladatok

- Adj block és mute táblákat egyedi pair constrainttel.
- Block létrehozásakor tranzakcióban töröld a follow kapcsolatot, requestet és pending challenge invite-ot.
- Alkalmazd a block policyt profile, search, feed, comments, clubs, notifications és challenge querykben.
- Implementáld a mute feed- és notification-szűrését a másik fél értesítése nélkül.
- Adj Blocked users és Muted users beállítási képernyőt.
- Block feloldás ne állítsa vissza a korábbi relationshipet.
- Készíts regressziós tesztet minden Community read endpoint ellen.

## Fő érintett fájlok

```text
backend/app/community/models/safety_relationships.py
backend/app/community/services/block_service.py
backend/app/community/policies/query_filters.py
lib/features/community/presentation/screens/safety_relationships_screen.dart
```

## Kötelező tesztek

- Block transaction
- Search exclusion
- Feed exclusion
- Comment exclusion
- Club shared context
- Notification cleanup
- Unblock no-refollow

## Elfogadási feltételek

- [ ] Block után nincs további közvetlen interakció vagy felfedezhetőség.
- [ ] Mute lokális nézetváltozás marad.
- [ ] Egy új Community endpoint sem kerülhet block-filter nélkül CI-be.

## Javasolt commit

```text
feat(community): enforce blocking and muting across community
```

---

# Kör 9 — Profilkeresés és biztonságos discovery

## Cél

Handle és érdeklődés alapján kereshető, privacy-t tiszteletben tartó profilfelfedezés.

## Feladatok

- Implementáld exact handle lookupot és prefix keresést dokumentált minimum query hosszal.
- Adj PostgreSQL keresési indexet; ne használj teljes táblaszkennelést.
- Szűrd private/non-discoverable és blocked profilokat.
- Ne adj contact uploadot, e-mail keresést vagy pontos hely szerinti discoveryt.
- Adj rate limitet és abuse monitoringot a keresésre.
- Készíts Flutter search képernyőt debounce-szal, recent search lokális és törölhető listával.
- Explore javaslat csak explicit interest tagekből és feature flag mögött készüljön.

## Fő érintett fájlok

```text
backend/app/community/repositories/profile_search_repository.py
backend/app/community/routers/search.py
lib/features/community/presentation/screens/community_search_screen.dart
```

## Kötelező tesztek

- Blocked profile hidden
- Non-discoverable hidden
- Exact handle
- Unicode query
- Rate limit
- Empty state
- Search history delete

## Elfogadási feltételek

- [ ] E-mail vagy telefonszám alapján nincs keresés.
- [ ] A keresés nem kerüli meg a privacy policyt.
- [ ] A recent search kizárólag helyi és felhasználó által törölhető.

## Javasolt commit

```text
feat(community): add privacy-safe profile discovery
```

---

# Kör 10 — Share artifact szerződések

## Cél

A Practice, Song, Analysis, Tutor, Vision és Gamification eredményeinek minimalizált, verziózott Community exportja.

## Feladatok

- Definiálj külön artifact típust practice summary, song result, analysis improvement, achievement, challenge, plan template és original progression számára.
- Minden source feature saját mapperrel exportáljon a Community public contractba.
- Tiltsd nyers audio, video, waveform, landmark, belső score debug és teljes learner profile beemelését.
- Adj schema versiont, content hash-t és source ID-t.
- Implementálj backend Pydantic discriminated union validációt.
- Készíts share preview modelt field-level kapcsolókkal.
- Dokumentáld az artifact backward compatibility és deprecation szabályait.

## Fő érintett fájlok

```text
lib/features/community/domain/entities/share_artifact.dart
lib/features/community/application/mappers/**
backend/app/community/schemas/artifacts.py
docs/contracts/community-share-artifacts.md
```

## Kötelező tesztek

- Artifact round trip
- Unknown version
- Sensitive field absence
- Pydantic discriminator
- Source mapper golden fixture
- Field toggle

## Elfogadási feltételek

- [ ] A Community nem importál más feature belső modelljét.
- [ ] Minden artifact minimális és explicit.
- [ ] A szerver elutasít ismeretlen vagy manipulált artifactot.

## Javasolt commit

```text
feat(community): define versioned share artifact contracts
```

---

# Kör 11 — Post backend CRUD és audience enforcement

## Cél

Biztonságos poszt létrehozás, olvasás, szerkesztés és törlés implementálása.

## Feladatok

- Adj post táblát public ID-val, audience-szal, optional club ID-val, artifacttal és moderation state-tel.
- Implementáld create/get/patch/delete endpointokat Pydantic validációval.
- A create endpoint használjon idempotency keyt és szerveroldali author ID-t.
- Validáld body limitet, markdown subsetet, mention limitet és artifact schema-t.
- Minden get/patch/delete ellenőrizze audience, block, owner és moderation policyt.
- Implementáld soft delete-et és cache invalidation eventet.
- Adj resource versiont/ETag-et a lost-update elkerülésére.

## Fő érintett fájlok

```text
backend/app/community/models/post.py
backend/app/community/schemas/post.py
backend/app/community/services/post_service.py
backend/app/community/routers/posts.py
```

## Kötelező tesztek

- Forged author ignored
- Idempotent create
- Audience matrix
- Block bypass
- Stale edit
- Soft delete
- HTML/script rejection
- Club audience

## Elfogadási feltételek

- [ ] Ugyanaz a create retry nem duplikál posztot.
- [ ] Nem látható poszt ID ismeretében sem olvasható.
- [ ] Törölt poszt nem tér vissza normál endpointból.

## Javasolt commit

```text
feat(community): implement audience-safe post lifecycle
```

---

# Kör 12 — Flutter post composer, draft és outbox

## Cél

Megbízható, adatvédelmi előnézetet biztosító posztkészítés online és offline állapotban.

## Feladatok

- Készíts composer state machine-t source, body, fields, audience, media, preview, sending, success és failure állapotokkal.
- Implementáld a field-level share kapcsolókat és végső preview-t.
- Adj lokális, verziózott draft repositoryt user scope-pal.
- Adj Community outbox mutációt stabil mutation/idempotency ID-val.
- Offline publish pending állapotot mutasson, ne hamis sikert.
- App kill és restart után a draft és pending post álljon helyre.
- Logoutkor kérdezett vagy dokumentált policy szerint kezelje a ki nem küldött draftot.

## Fő érintett fájlok

```text
lib/features/community/application/controllers/post_composer_controller.dart
lib/features/community/data/local/community_draft_store.dart
lib/features/community/application/outbox/community_outbox.dart
lib/features/community/presentation/screens/post_composer_screen.dart
```

## Kötelező tesztek

- Draft restore
- Offline queue
- Double tap
- Audience preview
- Sensitive field default off
- Restart recovery
- Send failure retry
- Logout behavior

## Elfogadási feltételek

- [ ] Közzététel előtt pontos preview látható.
- [ ] Offline retry nem hoz létre dupla posztot.
- [ ] A felhasználó szövege hiba esetén megmarad.

## Javasolt commit

```text
feat(community): add privacy-aware post composer and outbox
```

---

# Kör 13 — Following feed és cursor pagination backend

## Cél

Időrendi, determinisztikus és privacy-safe követési feed létrehozása.

## Feladatok

- Implementáld a following feed queryt audience, accepted follow, block, mute, moderation és deletion szűréssel.
- Használj stable sortot `created_at DESC, id DESC` vagy megfelelő kulccsal.
- Adj signed opaque cursort feed versionnel.
- Biztosíts snapshot-szerű lapozást vagy dokumentált consistency modellt új posztok érkezésekor.
- Adj maximum page size-t és query timeout védelmet.
- Kerüld az N+1 profile/count queryt eager/batched projectionnel.
- Készíts explain-plan baseline-t PostgreSQLen.

## Fő érintett fájlok

```text
backend/app/community/feed/following_feed.py
backend/app/community/schemas/feed.py
backend/app/community/routers/feed.py
backend/tests/community/test_feed_query_plan.py
```

## Kötelező tesztek

- No duplicate pages
- Stable cursor
- Blocked/muted hidden
- Deleted hidden
- Follower-only visibility
- Malformed cursor
- Page limit
- N+1 guard

## Elfogadási feltételek

- [ ] A feed időrendi és magyarázható.
- [ ] A cursor kliens számára opaque.
- [ ] Egy poszt nem jelenik meg kétszer normál lapozásban.

## Javasolt commit

```text
feat(community): add deterministic following feed pagination
```

---

# Kör 14 — Feed UI, cache és tudatos használat

## Cél

Reszponzív, hozzáférhető feed kialakítása offline cache-sel és végtelen engagement minták nélkül.

## Feladatok

- Készíts feed controller state-et initial/loading/content/refreshing/paging/offline/error/end állapotokkal.
- Implementálj lokális, user-scope-olt, bounded feed cache-t.
- Pull-to-refresh őrizze meg a scroll pozíciót, és külön jelezze az új posztokat.
- Adj explicit „Továbbiak betöltése” vagy kontrollált pagination viselkedést.
- Ne legyen autoplay; media csak user interactionre induljon.
- Adj end-of-feed nézetet és látható „Gyakorlás indítása” CTA-t.
- Készíts feed card registryt artifact típusonként, ismeretlen típus fallbackkel.

## Fő érintett fájlok

```text
lib/features/community/application/controllers/feed_controller.dart
lib/features/community/data/local/feed_cache.dart
lib/features/community/presentation/screens/following_feed_screen.dart
lib/features/community/presentation/widgets/feed_card_registry.dart
```

## Kötelező tesztek

- Offline cached feed
- Refresh scroll preservation
- Duplicate suppression
- Unknown artifact fallback
- End state
- Autoplay absence
- Large text golden

## Elfogadási feltételek

- [ ] A feed hálózati hiba esetén sem omlik össze.
- [ ] A cache nem keveredik accountok között.
- [ ] Nincs automatikus hang- vagy videólejátszás.

## Javasolt commit

```text
feat(community): build cached and mindful following feed UI
```

---

# Kör 15 — Reakciók és optimista konzisztencia

## Cél

Pozitív, idempotens reakciórendszer backenddel és optimista Flutter UI-val.

## Feladatok

- Adj reaction táblát `(post_id, profile_id)` unique constrainttel.
- Implementáld a reaction set és remove endpointot idempotensen.
- Csak allowlistelt supportive reaction típust fogadj el.
- A post projection tartalmazza a viewer reactiont és aggregált countokat.
- Flutterben optimistic update legyen mutation ID-val és rollbackkel.
- Gyors reakcióváltásnál a legutolsó user intent nyerjen.
- Community reaction ne bocsásson ki learning reward eventet.

## Fő érintett fájlok

```text
backend/app/community/models/reaction.py
backend/app/community/services/reaction_service.py
lib/features/community/application/controllers/reaction_controller.dart
lib/features/community/presentation/widgets/reaction_bar.dart
```

## Kötelező tesztek

- Duplicate set
- Replace reaction
- Remove twice
- Concurrent toggle
- Count nonnegative property
- Rollback
- No gamification event

## Elfogadási feltételek

- [ ] Retry nem növeli kétszer a countot.
- [ ] A viewer state azonnal és végül konzisztens.
- [ ] A reakció nem befolyásolja XP-t vagy masteryt.

## Javasolt commit

```text
feat(community): add idempotent supportive reactions
```

---

# Kör 16 — Kommentek, reply és mention

## Cél

Moderálható, korlátozott mélységű kommentrendszer biztonságos mentionnel.

## Feladatok

- Adj comment táblát, maximum reply depth policyt és resource versiont.
- Implementáld list/create/edit/delete endpointokat cursor paginationnel.
- Validáld a body hosszát, Unicode-t, tiltott HTML-t, link- és mention limitet.
- Mention csak létező, látható és nem blocked profilhoz készülhet.
- Adj comment owner, post owner és moderator jogosultságokat külön policyben.
- Készíts Flutter comment sheet/detail nézetet draft megőrzéssel.
- Optimistic create temp ID-t használjon, szerver response után atomikusan cserélje.

## Fő érintett fájlok

```text
backend/app/community/models/comment.py
backend/app/community/services/comment_service.py
backend/app/community/policies/comment_policy.py
lib/features/community/presentation/screens/comments_screen.dart
```

## Kötelező tesztek

- Depth limit
- Blocked mention
- Private post comment
- Edit conflict
- Delete permission
- Temp ID replacement
- Comment pagination
- XSS strings

## Elfogadási feltételek

- [ ] Nincs végtelen threadmélység.
- [ ] A mention nem kerülheti meg a block/privacy szabályt.
- [ ] Hálózati hiba nem veszti el a kommentdraftot.

## Javasolt commit

```text
feat(community): implement safe comments and mentions
```

---

# Kör 17 — Bookmark, mentett tartalom és biztonságos import

## Cél

Privát mentés és share artifactból kontrollált Practice/Song importfolyamat.

## Feladatok

- Adj bookmark táblát és idempotens set/remove API-t.
- Készíts Bookmarks képernyőt cursor paginationnel és törölt-content tombstone kezeléssel.
- Plan template vagy original progression artifactnál jelenjen meg explicit Import action.
- Import előtt validáld a schema versiont, dependencyket, licenc/meta státuszt és lokális ütközést.
- Import mindig új lokális példányt készítsen source attributionnel; ne mutálja a community postot.
- Ismeretlen vagy deprecated artifactnál read-only fallback jelenjen meg.
- A bookmark count maradjon privát és ne kerüljön publikus post projectionbe.

## Fő érintett fájlok

```text
backend/app/community/models/bookmark.py
backend/app/community/routers/bookmarks.py
lib/features/community/presentation/screens/bookmarks_screen.dart
lib/features/community/application/use_cases/import_share_artifact.dart
```

## Kötelező tesztek

- Bookmark idempotency
- Private count
- Deleted post tombstone
- Import schema validation
- Duplicate local title
- Source attribution
- Deprecated fallback

## Elfogadási feltételek

- [ ] Bookmark aktivitás nem nyilvános.
- [ ] Import nem írja felül a felhasználó meglévő lokális tartalmát.
- [ ] Védett teljes dalanyag nem importálható jogosultsági metadata nélkül.

## Javasolt commit

```text
feat(community): add private bookmarks and controlled imports
```

---

# Kör 18 — Média upload contract és objektumtár integráció

## Cél

Feature flaggel védett, közvetlen objektumtáras és biztonságos médiafeltöltési pipeline alapja.

## Feladatok

- Válassz S3-kompatibilis object storage interfészt vendor-semleges adapterrel.
- Adj media recordot upload state, owner, MIME, size, duration, checksum és retention mezőkkel.
- Implementáld upload intent, signed URL és finalize endpointot.
- A signed URL rövid életű, content-length és content-type korlátozott legyen.
- Finalization ellenőrizze object existence, checksum, size és ownership adatot.
- Adj orphan upload cleanup jobot és quota policyt.
- Flutter uploader lifecycle-aware, cancelálható és progress-t mutató legyen.

## Fő érintett fájlok

```text
backend/app/community/models/media.py
backend/app/community/services/media_upload_service.py
backend/app/community/storage/object_store.py
lib/features/community/data/api/community_media_uploader.dart
```

## Kötelező tesztek

- Feature flag off
- Signed URL expiry
- Wrong MIME
- Oversize
- Checksum mismatch
- Foreign finalize
- Cancel upload
- Orphan cleanup

## Elfogadási feltételek

- [ ] A backend nem tartja memóriában a teljes médiafájlt.
- [ ] A bucket private by default.
- [ ] A média csak explicit user actionre kerül feltöltésre.

## Javasolt commit

```text
feat(community): add gated secure media upload pipeline
```

---

# Kör 19 — Média feldolgozás, privacy és moderation state

## Cél

A feltöltött média biztonságos transcode-, metadata-strip- és review-folyamatának megvalósítása.

## Feladatok

- Adj media processing state machine-t: uploaded, scanning, transcoding, review, ready, rejected, deleted.
- Távolítsd el az EXIF/location metaadatot és dokumentáld a megőrzött technikai metadata-t.
- Korlátozd codecet, durationt, resolutiont és frame rate-et.
- Készíts adaptert malware scan és opcionális content moderation providerhez.
- Automatikus modell csak triage-ot végezzen súlyos account action előtt emberi review szükséges.
- Post media csak ready állapotban renderelhető; pending placeholder jelenjen meg.
- Adj signed playback URL-t rövid TTL-lel és audience ellenőrzéssel.

## Fő érintett fájlok

```text
backend/app/community/tasks/media_processing.py
backend/app/community/services/media_access_service.py
backend/app/community/moderation/media_moderation.py
lib/features/community/presentation/widgets/community_media_player.dart
```

## Kötelező tesztek

- EXIF stripped fixture
- Pending not playable
- Rejected state
- Audience playback authorization
- Expired URL
- Metadata leak
- Reduced-data media UI

## Elfogadási feltételek

- [ ] Pontos helymetaadat nem marad a publikált médiában.
- [ ] Nem ready media nem elérhető közvetlen URL-lel.
- [ ] A moderation döntés és provider version auditált.

## Javasolt commit

```text
feat(community): process and moderate shared media safely
```

---

# Kör 20 — Notification inbox és push abstraction

## Cél

Tartós, kategorizált közösségi értesítések és opcionális push delivery létrehozása.

## Feladatok

- Adj notification táblát recipient, type, actor, entity, read state és dedup key mezővel.
- Implementáld inbox list, unread count, mark-read és mark-all-read endpointokat.
- Aggregáld a reaction burst eseményeket dokumentált időablakban.
- Adj provider-semleges push gateway interfészt; a push csak notification ID-t és minimális route adatot tartalmazzon.
- Készíts category preference és local quiet-hours támogatást.
- Kliensen az inbox az elsődleges truth, a push csak refresh trigger.
- Block/mute és content deletion frissítse vagy rejtse az érintett inbox itemet.

## Fő érintett fájlok

```text
backend/app/community/models/notification.py
backend/app/community/notifications/notification_service.py
backend/app/community/notifications/push_gateway.py
lib/features/community/presentation/screens/community_notifications_screen.dart
```

## Kötelező tesztek

- Dedup
- Aggregation
- Read state
- Blocked actor hidden
- Deleted entity
- Push payload redaction
- Preference off
- Unread count race

## Elfogadási feltételek

- [ ] Push payload nem tartalmaz érzékeny teljes szöveget.
- [ ] Több reaction nem okoz értesítési vihart.
- [ ] Az inbox internetes újracsatlakozás után konzisztens.

## Javasolt commit

```text
feat(community): add persistent notification inbox and push gateway
```

---

# Kör 21 — Community challenge és invite lifecycle

## Cél

Aszinkron kihívás-meghívások és résztvevői állapotgép implementálása.

## Feladatok

- Adj challenge, participant és invite táblákat versionnel, időablakkal és verification policyvel.
- Implementáld a draft/sent/accepted/declined/expired/cancelled transitionöket.
- Csak compatible Gamification/Practice challenge definition használható.
- Block, eligibility, feature availability és invite rate limit szerveroldali ellenőrzésű.
- Adj challenge list és detail Flutter képernyőt, offline cache-sel.
- Accepted challenge indítása deep linkkel a megfelelő Practice/Song flow-ba történjen.
- Challenge lejárat background job nélkül is helyesen számítható legyen szerveridőből.

## Fő érintett fájlok

```text
backend/app/community/models/challenge.py
backend/app/community/services/challenge_invite_service.py
backend/app/community/routers/challenges.py
lib/features/community/presentation/screens/community_challenges_screen.dart
```

## Kötelező tesztek

- Invalid transition
- Expired accept
- Blocked invite
- Duplicate invite
- Cancel race
- Deep link compatibility
- Timezone-independent expiry

## Elfogadási feltételek

- [ ] A lifecycle explicit és auditálható.
- [ ] Ugyanaz a meghívás retry esetén nem duplikálódik.
- [ ] A challenge nem követel nem elérhető feature-t.

## Javasolt commit

```text
feat(community): add asynchronous challenge invitations
```

---

# Kör 22 — Verified result submission és anti-cheat

## Cél

Challenge eredmények szerveroldali, idempotens ellenőrzése és trust állapotának rögzítése.

## Feladatok

- Adj challenge result submit endpointot stabil source event ID-val és server-issued nonce-szal.
- Validáld challenge versiont, időablakot, participant állapotot, metric range-et és scorer compatibilityt.
- Ne fogadj el kliens által küldött rankot vagy verified flaget.
- Implementálj replay deduplicationt és first/best submission policyt challenge típusonként.
- Adj verification state-et: pending, verified, unverified, rejected, review.
- Anomaly signal legyen reason code-os és ne tartalmazzon szükségtelen nyers audioadatot.
- Kliensen pending verification különüljön el a practice session saját sikerétől.

## Fő érintett fájlok

```text
backend/app/community/services/challenge_verification_service.py
backend/app/community/models/challenge_result.py
backend/app/community/policies/integrity_policy.py
lib/features/community/application/controllers/challenge_result_controller.dart
```

## Kötelező tesztek

- Replay
- Forged verified
- Impossible score
- Expired nonce
- Wrong version
- Best result policy
- Pending UI
- Session success despite upload failure

## Elfogadási feltételek

- [ ] Globális versenybe csak server-verified eredmény kerül.
- [ ] Community verification hiba nem törli a lokális gyakorlási eredményt.
- [ ] A döntés auditálható reason code-dal.

## Javasolt commit

```text
feat(community): verify challenge results and prevent replay
```

---

# Kör 23 — Leaderboards és opt-in versenynézet

## Cél

Verified, összehasonlítható és privacy-kompatibilis challenge ranglista létrehozása.

## Feladatok

- Implementáld a leaderboard projectiont kizárólag verified resultból.
- Dokumentáld metric directiont, tie-breakert, cohortot és difficulty bandet.
- Adj friends, club és challenge-global scope-ot; all-time total XP global lista ne készüljön.
- A felhasználó külön opt-in nélkül ne jelenjen meg public scope-ban.
- Adj saját rank endpointot és cursor paginationt.
- Készíts Flutter leaderboardot accessible rank sorral és verified badge magyarázattal.
- Disqualification vagy delete után a projection determinisztikusan frissüljön.

## Fő érintett fájlok

```text
backend/app/community/services/leaderboard_service.py
backend/app/community/models/leaderboard.py
backend/app/community/routers/leaderboards.py
lib/features/community/presentation/screens/leaderboard_screen.dart
```

## Kötelező tesztek

- Only verified
- Tie order
- Opt-out hidden
- Friends scope
- Pagination stable
- Disqualification rebuild
- Large text semantics

## Elfogadási feltételek

- [ ] Nem ellenőrzött lokális XP nem jelenik meg globális listán.
- [ ] A ranglista szabálya magyarázható.
- [ ] A user ranglista nélkül is teljesen használhatja a challenge-et.

## Javasolt commit

```text
feat(community): add verified opt-in challenge leaderboards
```

---

# Kör 24 — Klub domain, tagság és szerepkörök

## Cél

Kisebb, témaközpontú tanulócsoportok és explicit permission rendszer létrehozása.

## Feladatok

- Adj club, member és invite táblákat public ID-val, visibilityvel és role-lal.
- Implementáld create/read/update/join/leave/invite/member-remove/role-change lifecycle-t.
- Készíts explicit permission mátrixot owner, moderator és member szerepkörre.
- Ownership transfer szükséges owner leave/delete előtt.
- Adj membership és invite limiteket konfigurációból.
- Block policy közös klubban is érvényesüljön.
- Készíts Flutter club list, detail, create és member management képernyőt.

## Fő érintett fájlok

```text
backend/app/community/models/club.py
backend/app/community/policies/club_permissions.py
backend/app/community/services/club_service.py
lib/features/community/presentation/screens/clubs/**
```

## Kötelező tesztek

- Owner leave
- Permission matrix
- Duplicate join
- Private invite
- Member removal
- Blocked members
- Club limits
- Ownership transfer

## Elfogadási feltételek

- [ ] Role mutation szerveroldali jogosultságot használ.
- [ ] Owner nélkül nem maradhat aktív klub.
- [ ] A klub nem nyit privát chat csatornát.

## Javasolt commit

```text
feat(community): implement clubs and role-based membership
```

---

# Kör 25 — Club feed, pinned post és club challenge

## Cél

A klubok számára ugyanazon biztonságos post- és challenge-infrastruktúra újrahasznosítása.

## Feladatok

- Implementáld a club audience post policyt membership ellenőrzéssel.
- Adj club feed cursor paginationt a közös post projection újrahasznosításával.
- Adj pinned post relationt maximum konfigurált darabszámmal.
- Club moderator pin/unpin és post moderation jogát policy határozza meg.
- Adj club challenge create/activate/end műveletet compatibility validációval.
- Flutter club detail tabok: Feed, Challenges, Members, About.
- Club elhagyása után a cache-ből azonnal tűnjön el a csak-club tartalom.

## Fő érintett fájlok

```text
backend/app/community/feed/club_feed.py
backend/app/community/services/club_content_service.py
lib/features/community/presentation/screens/club_detail_screen.dart
```

## Kötelező tesztek

- Nonmember denied
- Leave cache purge
- Pin permission
- Pin limit
- Club challenge eligibility
- Block in club
- Feed pagination

## Elfogadási feltételek

- [ ] A club feed nem duplikál külön post rendszert.
- [ ] Tagság megszűnése azonnal visszavonja a hozzáférést.
- [ ] Moderator jog nem terjed túl a saját klubján.

## Javasolt commit

```text
feat(community): add club feed and group challenges
```

---

# Kör 26 — Felhasználói report és azonnali safety flow

## Cél

Könnyen elérhető report, hide, mute és block folyamat létrehozása minden releváns tartalomnál.

## Feladatok

- Adj report táblát target type/ID, category, optional detail, reporter és dedup mezőkkel.
- Implementáld report endpointot úgy, hogy a reporter személye ne kerüljön a target response-aiba.
- Készíts Flutter report bottom sheetet lokalizált kategóriával és safety shortcutokkal.
- Report után a user azonnal elrejtheti a tartalmat, mute-olhat vagy blockolhat.
- Ugyanazon target/category ismételt submit legyen idempotens vagy kontrolláltan összevont.
- Adj copyright és privacy kategóriához külön szükséges metadata mezőt minimalizáltan.
- Self-harm concern kategóriánál csak jóváhagyott safety copy és routing használható.

## Fő érintett fájlok

```text
backend/app/community/models/report.py
backend/app/community/services/report_service.py
backend/app/community/routers/reports.py
lib/features/community/presentation/dialogs/report_content_sheet.dart
```

## Kötelező tesztek

- Reporter identity hidden
- Duplicate report
- Blocked after report
- Deleted target
- Invalid category
- Rate limit
- Accessibility focus

## Elfogadási feltételek

- [ ] Report maximum néhány lépésből elérhető.
- [ ] A felhasználónak nem kell tovább látnia a jelentett tartalmat.
- [ ] A target nem tudja meg a reporter személyét.

## Javasolt commit

```text
feat(community): add accessible reporting and safety actions
```

---

# Kör 27 — Moderation queue, enforcement és appeal

## Cél

Auditálható, szerepkör-alapú moderációs backend és fellebbezési folyamat.

## Feladatok

- Adj moderation case és action táblát immutable audit eventekkel.
- Implementáld queue priorityt report signal, automation triage és account history alapján dokumentáltan.
- Adj moderator/admin auth scope-ot; normál JWT user ne érje el az endpointot.
- Implementáld visible/limited/pending/removed/author-only state transitionöket.
- Súlyos account action előtt követelj emberi megerősítést, kivéve sürgős technikai spam containmentet dokumentált policyvel.
- Adj appeal submissiont, state-et és független review lehetőségét.
- Készíts egyszerű belső admin UI-t vagy API-first eszközt; ne kerüljön normál mobil buildbe.

## Fő érintett fájlok

```text
backend/app/community/models/moderation.py
backend/app/community/moderation/case_service.py
backend/app/community/routers/moderation.py
docs/operations/community-moderation-runbook.md
```

## Kötelező tesztek

- Unauthorized admin
- State machine
- Immutable audit
- Appeal once
- Automation cannot permanent-ban alone
- Removed content visibility
- Reporter privacy

## Elfogadási feltételek

- [ ] Minden enforcement döntés reason code-dal és actorral auditált.
- [ ] Fellebbezés elérhető dokumentált esetekben.
- [ ] A learning history nem törlődik community suspension miatt.

## Javasolt commit

```text
feat(community): add auditable moderation and appeals
```

---

# Kör 28 — Privacy center, adat export és törlés

## Cél

A felhasználó közösségi adatainak áttekintése, exportja, deaktiválása és törlése.

## Feladatok

- Készíts Community Privacy & Safety képernyőt visibility, discoverability, leaderboard, notifications, block és mute beállításokkal.
- Implementáld az export jobot profil, poszt, komment, reaction, bookmark, follow, club, challenge és moderation-user-facing adattal.
- Az export artifact legyen titkosított vagy rövid életű signed download, auditált hozzáféréssel.
- Implementáld Community deactivate flow-t és külön full profile delete-et megerősítéssel.
- Indíts media deletion és cache invalidation jobot.
- Dokumentáld, mely audit/security rekord maradhat szükséges retention miatt; jogi felülvizsgálat kötelező.
- Account törlés és Community törlés legyen külön, egyértelmű művelet.

## Fő érintett fájlok

```text
backend/app/community/services/data_rights_service.py
backend/app/community/routers/data_rights.py
lib/features/community/presentation/screens/community_privacy_screen.dart
lib/features/community/presentation/screens/community_data_screen.dart
```

## Kötelező tesztek

- Export authorization
- Expired export URL
- Deactivate visibility
- Delete idempotency
- Media cleanup queued
- Learning data preserved
- Cross-account export denial

## Elfogadási feltételek

- [ ] A user saját Community adatait exportálhatja.
- [ ] Community törlés nem törli véletlenül az offline practice historyt.
- [ ] A törlés és retention viselkedés dokumentált és tesztelt.

## Javasolt commit

```text
feat(community): add privacy controls export and deletion
```

---

# Kör 29 — Offline sync, konfliktuskezelés és outbox hardening

## Cél

Minden Community mutáció megbízható, restart-biztos és idempotens szinkronizálása.

## Feladatok

- Egységesítsd a post, reaction, comment, bookmark, follow és challenge result outbox rekordokat.
- Adj per-user encrypted vagy megfelelően védett local store-t és bounded retentiont.
- Implementálj dependency orderinget: media finalize → post create, post create → comment.
- Adj retry policyt network, auth, validation, conflict és permanent failure kategóriára.
- Token lejáratkor a sync várjon auth recoveryre, ne dobja el a payloadot.
- Implementálj ETag/version conflict resolver UI-t profile/post/comment edithez.
- Készíts dead-letter/failed mutations képernyőt szerkesztés, retry és discard lehetőséggel.

## Fő érintett fájlok

```text
lib/features/community/application/outbox/community_sync_engine.dart
lib/features/community/data/local/community_outbox_store.dart
lib/features/community/presentation/screens/failed_mutations_screen.dart
```

## Kötelező tesztek

- App kill mid-sync
- Dependency order
- 401 pause/resume
- Permanent validation failure
- Conflict UI
- Duplicate replay
- Account switch isolation
- Queue bound

## Elfogadási feltételek

- [ ] Egyetlen retry sem duplikál szerveroldali entitást.
- [ ] Accountváltás nem küld más user outboxából adatot.
- [ ] Permanent failure esetén a user visszakapja és javíthatja a tartalmat.

## Javasolt commit

```text
refactor(community): harden offline mutation synchronization
```

---

# Kör 30 — Rate limit, observability és security hardening

## Cél

A Community productionbiztonságának, mérhetőségének és abuse-védelmének megerősítése.

## Feladatok

- Implementálj endpoint- és action-specifikus rate limit policyt közös store adapterrel; multi-worker productionben ne legyen process-local.
- Adj request ID-t, strukturált audit eventet és redacted application logot.
- Készíts abuse signal aggregátort account age, velocity, duplicate hash és report/block rate alapján.
- Végezz IDOR, forged author, forged verified, audience bypass és admin auth tesztet.
- Adj security headers és request body limitet a Community route-okra.
- Készíts metrics dashboard specifikációt post success, feed latency, moderation queue, outbox failure és result verification számára.
- Adj emergency write-disable és media-disable runbookot.

## Fő érintett fájlok

```text
backend/app/community/security/rate_limits.py
backend/app/community/security/abuse_signals.py
backend/app/community/observability.py
docs/operations/community-incident-runbook.md
```

## Kötelező tesztek

- Distributed rate limit adapter
- IDOR suite
- Forged fields
- Body size
- Redaction
- Kill switch
- Moderator scope
- Replay burst

## Elfogadási feltételek

- [ ] Production multi-worker környezetben közös rate-limit store használható.
- [ ] Érzékeny UGC nem kerül normál logba.
- [ ] A Community write emergency mód tanulási leállás nélkül aktiválható.

## Javasolt commit

```text
fix(community): harden security abuse protection and observability
```

---

# Kör 31 — Accessibility, localization és UX polish

## Cél

A teljes Community funkció hozzáférhető, lokalizált és kontrollálható használati élményének biztosítása.

## Feladatok

- Készíts magyar és angol ARB parity ellenőrzést minden Community kulcsra.
- Auditáld screen reader traversal, semantics, touch target és focus return viselkedést.
- Teszteld 2.0 text scale-en a feedet, profile-t, composer-t, commentet, leaderboardot, clubot és report flow-t.
- Implementáld reduced-motion és autoplay-off viselkedést.
- Adj media alt text/caption mezőt és playback semanticsot.
- Készíts offline, loading, empty, private, blocked, removed és error state-eket egységes design systemből.
- Adj notification intensity és media data-saver beállítást.

## Fő érintett fájlok

```text
lib/l10n/app_en.arb
lib/l10n/app_hu.arb
test/features/community/accessibility/**
test/features/community/goldens/**
```

## Kötelező tesztek

- Localization parity
- Semantics labels
- 2.0 text scale
- Reduced motion
- No autoplay
- Keyboard/focus
- RTL smoke test ha támogatott

## Elfogadási feltételek

- [ ] Nincs levágott kritikus szöveg nagy betűméretnél.
- [ ] Minden safety action screen readerrel elérhető.
- [ ] A Community média nem indul automatikusan.

## Javasolt commit

```text
fix(community): complete accessibility localization and UX states
```

---

# Kör 32 — Teljes integráció, load evaluation és release readiness

## Cél

Az Epic lezárása teljes regresszióval, PostgreSQL terhelésméréssel, manuális safety teszttel és rollout tervvel.

## Feladatok

- Futtasd a teljes Flutter és backend tesztcsomagot, architecture guardot és migrációtesztet.
- Készíts PostgreSQL load tesztet feed, comment burst, challenge leaderboard és notification burst útvonalra.
- Ellenőrizd account-disabled és community-disabled állapotban a nulla Community requestet.
- Végezz két accountos manuális tesztet follow, private, block, report, challenge és delete folyamatra.
- Végezz offline/online, app kill, token expiry és account switch tesztet.
- Készíts moderation és incident tabletop tesztet.
- Készíts staged rollout tervet belső → kis beta → opt-in beta → production fázissal és rollback feltételekkel.
- Hozd létre az `epic-09-completion-report.md` dokumentumot maradék kockázatokkal.

## Fő érintett fájlok

```text
docs/sdd/epic-09-completion-report.md
docs/operations/community-rollout-plan.md
backend/tests/load/**
test/features/community/integration/**
```

## Kötelező tesztek

- Full Flutter suite
- Full backend PostgreSQL suite
- Load baseline
- Two-account E2E
- Offline replay
- Block/report E2E
- Data delete E2E
- Kill switch

## Elfogadási feltételek

- [ ] Minden CI zöld és a known risk lista explicit.
- [ ] A feed és mutációk elérik a dokumentált baseline-t.
- [ ] Rollback lehetséges adatvesztés nélkül.
- [ ] A Community nem regresszálja a Practice, Song, Analysis vagy Gamification funkciókat.

## Javasolt commit

```text
docs(community): close Epic 9 release readiness
```

---

# 31. Epic 9 végső Definition of Done

Az Epic csak akkor tekinthető késznek, ha minden alábbi állítás igaz.

## Architektúra

- [ ] A Community külön Flutter feature és külön backend modul.
- [ ] A Flutter domain nem importál Fluttert, Dio-t vagy storage plugint.
- [ ] Más feature csak a Community `public.dart` exportját használja.
- [ ] A backend router nem tartalmaz üzleti policyt.
- [ ] Minden adatbázis-változás Alembic migráció.
- [ ] A Community modular monolith marad; nincs indokolatlan mikroszolgáltatás.
- [ ] A feature flag és kill switch működik read és write szinten.
- [ ] Community-disabled állapotban nincs Community network request.

## Identitás és profil

- [ ] A publikus user ID nem belső integer és nem e-mail.
- [ ] A handle normalizált és adatbázisban egyedi.
- [ ] A handle policy kezeli a reserved és tiltott neveket.
- [ ] A display name nem használható login azonosítóként.
- [ ] A profil alapértelmezése nem automatikusan public.
- [ ] E-mail, pontos hely és belső learner profile nem nyilvános.
- [ ] Profil szerkesztési konfliktus kontrollált.
- [ ] Profil deaktiválható és törölhető.

## Privacy és audience

- [ ] Minden profile, post, comment, feed és media read szerveroldali policyt alkalmaz.
- [ ] A block felülír minden follow, audience és club hozzáférést.
- [ ] Private és followers-only tartalom közvetlen ID-val sem olvasható jogosultság nélkül.
- [ ] Közzététel előtt a user látja a célközönséget és a megosztott mezőket.
- [ ] A leaderboard külön opt-in.
- [ ] Kereshetőség külön szabályozható.
- [ ] Audience változás cache invalidationt vált ki.
- [ ] Accountváltás nem kever cache-t vagy outboxot.

## Social graph

- [ ] Self-follow és self-block tiltott.
- [ ] Follow/request mutációk idempotensek.
- [ ] Private follow request explicit elfogadást igényel.
- [ ] Follower eltávolítható block nélkül.
- [ ] Mute nem értesíti a másik felet.
- [ ] Block törli vagy invalidálja a kapcsolódó kapcsolatokat és invite-okat.
- [ ] Unblock nem állítja vissza automatikusan a follow-t.
- [ ] Search nem ad vissza blocked vagy non-discoverable profilt.

## Poszt és feed

- [ ] A post create idempotens.
- [ ] A post author szerveroldali authból származik.
- [ ] A share artifact verziózott és minimalizált.
- [ ] Nyers DSP, waveform, landmark vagy learner profile nincs artifactban.
- [ ] A post edit resource versiont használ.
- [ ] A soft delete és retention dokumentált.
- [ ] A Following feed időrendi és magyarázható.
- [ ] A feed cursor opaque és stabil.
- [ ] Lapozáskor nincs normál esetben duplikált post.
- [ ] A feed nem használ automatikus audio/video lejátszást.
- [ ] Létezik end-of-feed vagy kontrollált továbblépés.
- [ ] Offline cache egyértelműen jelzett.

## Reakció, komment és bookmark

- [ ] Reakció retry nem dupláz countot.
- [ ] Csak allowlistelt supportive reaction használható.
- [ ] Reakció, follow és like nem ad learning XP-t.
- [ ] Komment mélysége korlátozott.
- [ ] Komment mention nem kerülheti meg a privacy/block policyt.
- [ ] Kommentdraft hálózati hiba esetén megmarad.
- [ ] Bookmark privát.
- [ ] Bookmark count nem publikus.
- [ ] Artifact import új lokális példányt készít source attributionnel.
- [ ] Törölt tartalom bookmarkja biztonságos tombstone-t kezel.

## Média

- [ ] A Community teljesen használható médiafeltöltés nélkül.
- [ ] Média upload külön feature flag mögött van.
- [ ] A backend nem olvassa memóriába a teljes feltöltést.
- [ ] Signed URL rövid életű és korlátozott.
- [ ] Ownership, checksum, MIME és méret validált.
- [ ] EXIF és helymetaadat eltávolított.
- [ ] Nem ready média nem játszható le.
- [ ] Playback audience-ellenőrzött.
- [ ] Orphan upload cleanup működik.
- [ ] Backing track vagy importált teljes dal nem töltődik fel automatikusan.
- [ ] Copyright report és takedown audit rendelkezésre áll.

## Challenge és leaderboard

- [ ] Challenge lifecycle explicit state machine.
- [ ] Invite retry nem duplikál.
- [ ] Blockolt user nem hívható meg.
- [ ] Result submission idempotens.
- [ ] Replay nem hoz létre második eredményt.
- [ ] A backend nem fogad kliens által állított rankot vagy verified flaget.
- [ ] A verification reason code-os és auditált.
- [ ] Community upload failure nem törli a lokális session eredményét.
- [ ] Leaderboard csak verified resultot tartalmaz.
- [ ] Leaderboard difficulty/scorer kompatibilitás dokumentált.
- [ ] Global leaderboard opt-in.
- [ ] Nincs all-time total XP globális lista az első verzióban.

## Klubok

- [ ] Club visibility és tagság szerveroldali.
- [ ] Owner, moderator és member permission mátrix tesztelt.
- [ ] Owner nélkül nem maradhat aktív klub.
- [ ] Club leave azonnal visszavonja a private content hozzáférést.
- [ ] Club feed a közös post rendszert használja.
- [ ] Club challenge a közös verified result rendszert használja.
- [ ] Klub nem ad privát chatet ebben az Epicben.
- [ ] Membership és invite limitek konfigurálhatók.

## Notification

- [ ] Minden notification tartós inbox itemből származik.
- [ ] Push csak delivery channel.
- [ ] Push payload minimális és redacted.
- [ ] Reaction burst aggregált.
- [ ] Kategóriánként kikapcsolható push.
- [ ] Block/mute érvényesül notificationnél.
- [ ] Unread count versenyhelyzetben is konzisztens.
- [ ] Notification deep link route argumentuma validált.

## Moderation és safety

- [ ] Report minden releváns tartalomról és profilról elérhető.
- [ ] Reporter személye nem szivárog a targethez.
- [ ] Report után a tartalom azonnal elrejthető.
- [ ] Block és mute safety shortcutként elérhető.
- [ ] Moderation state machine tesztelt.
- [ ] Minden enforcement action auditált.
- [ ] Súlyos account action nem kizárólag automatikus modell döntése.
- [ ] Appeal folyamat létezik dokumentált esetekben.
- [ ] Community suspension nem törli a learning historyt.
- [ ] Moderation admin endpoint normál user számára elérhetetlen.
- [ ] Kiskorúakkal kapcsolatos minimum korhatár és jogi policy publikus indulás előtt felülvizsgált.

## Offline és sync

- [ ] Post, reaction, comment, bookmark, follow és result outboxosítható.
- [ ] Outbox restart-biztos.
- [ ] Outbox user-scope-olt.
- [ ] Dependency ordering működik.
- [ ] 401 után a payload nem vész el.
- [ ] Permanent failure javítható vagy eldobható a user által.
- [ ] Optimistic rollback tesztelt.
- [ ] ETag/version konfliktusnak van UX-e.
- [ ] Delete és edit konfliktus policy dokumentált.
- [ ] Retry nem duplikál entitást.

## Adatkezelés

- [ ] A user saját Community adatait exportálhatja.
- [ ] Export más accounttal nem érhető el.
- [ ] Export link rövid életű vagy megfelelően védett.
- [ ] Community profile külön deaktiválható.
- [ ] Community profile külön törölhető.
- [ ] Media cleanup elindul törléskor.
- [ ] Retention kategóriánként dokumentált.
- [ ] Community törlés nem törli automatikusan a lokális tanulási adatokat.
- [ ] Signed media URL nem kerül tartós logba.

## Security és anti-abuse

- [ ] IDOR tesztcsomag zöld.
- [ ] Audience bypass teszt zöld.
- [ ] Forged author teszt zöld.
- [ ] Forged verified/rank teszt zöld.
- [ ] Request body limit aktív.
- [ ] Endpoint-specifikus rate limit aktív.
- [ ] Multi-worker productionben a rate limit közös store-t használ.
- [ ] Idempotency rekordok retentionje dokumentált.
- [ ] Challenge nonce és replay védelem működik.
- [ ] Application log nem tartalmaz teljes UGC-t, e-mailt, tokent vagy media URL-t.
- [ ] Emergency write-disable és media-disable tesztelt.

## Accessibility és UX

- [ ] A Community teljes fő folyamata screen readerrel használható.
- [ ] A safety actionök megfelelő focus orderrel rendelkeznek.
- [ ] 2.0 text scale-en nincs kritikus overflow.
- [ ] Reduced motion tiszteletben tartott.
- [ ] Autoplay alapértelmezetten nincs.
- [ ] Media rendelkezik alt text/caption lehetőséggel.
- [ ] Reaction nem csak színnel vagy ikonnal kommunikált.
- [ ] Leaderboard sor érthetően felolvasható.
- [ ] Offline, private, blocked, removed és error state külön megjelenik.
- [ ] Magyar és angol localization parity zöld.

## Tesztelés és CI

- [ ] Flutter unit tesztek zöldek.
- [ ] Flutter widget/golden tesztek zöldek.
- [ ] Property-based invariáns tesztek zöldek.
- [ ] Backend unit tesztek zöldek.
- [ ] PostgreSQL integration tesztek zöldek.
- [ ] Alembic migration tesztek zöldek.
- [ ] Security tesztcsomag zöld.
- [ ] Architecture guard zöld.
- [ ] Load baseline dokumentált.
- [ ] Kétaccountos E2E teszt zöld.
- [ ] Block/report/delete E2E teszt zöld.
- [ ] Completion report elkészült.

---

# 32. Kötelező végső ellenőrző parancsok

Flutter:

```bash
flutter pub get

dart format --output=none --set-exit-if-changed lib test tool

flutter analyze lib/ test/ tool/

flutter test

flutter test test/property

dart run tool/check_architecture.dart
```

Backend:

```bash
cd backend

python -m ruff check app tests

python -m ruff format --check app tests

python -m pytest -q

alembic upgrade head
```

PostgreSQL Community integration:

```bash
python -m pytest -q tests/community tests/integration/community
```

A pontos load tool a projekt által választott eszköztől függően:

```bash
# Példa; a tényleges scriptet a repository dokumentálja.
python -m pytest -q tests/load/community
```

Manuális eszközteszt legalább két accounttal:

- Community disabled és account disabled;
- profil létrehozás;
- private profil;
- follow request, accept, decline és follower removal;
- block és unblock;
- mute;
- profile search;
- online és offline post;
- app kill pending post közben;
- reaction gyors váltása;
- komment draft és retry;
- bookmark és artifact import;
- media upload cancel, ha engedélyezett;
- challenge invite és lejárat;
- challenge result replay;
- leaderboard opt-in és opt-out;
- club join/leave és role policy;
- report, hide és block;
- moderation removal placeholder;
- notification aggregation;
- data export;
- Community deactivate és delete;
- account switch pending outbox mellett;
- token lejárat sync közben;
- 2.0 text scale;
- screen reader;
- reduced motion;
- offline cached feed;
- Community write kill switch.

---

# 33. Rollout stratégia

## 33.1 Internal alpha

Engedélyezett:

- profil;
- follow;
- private/followers audience;
- following feed;
- share card post;
- reaction;
- comment;
- block/report;
- notification inbox.

Média, Explore, leaderboard és club creation alapértelmezetten kikapcsolt.

Kilépési feltétel:

- nincs kritikus privacy bypass;
- block regresszió nincs;
- post idempotency stabil;
- moderation runbook kipróbált;
- data delete tesztelt.

## 33.2 Zárt beta

Fokozatosan engedélyezhető:

- challenge invite;
- friends leaderboard;
- club;
- media kis trust tiernek;
- push kategóriánként.

Kilépési feltétel:

- abuse és report mennyiség kezelhető;
- notification nem okoz spamtüskét;
- media processing stabil;
- challenge verification false rejection kontrollált;
- load baseline megfelel.

## 33.3 Nyilvános opt-in beta

- Community külön opt-in;
- public profile és public post opcionális;
- global challenge leaderboard csak verified és opt-in;
- Explore csak külön kill switch mögött;
- folyamatos moderation kapacitás biztosított.

## 33.4 Production

Production csak akkor:

- jogi/adatvédelmi review kész;
- korhatár és child-safety döntés kész;
- moderation staffing/runbook kész;
- incident response kész;
- media/copyright process kész, ha média aktív;
- export/delete működik;
- SLO és rollback terv dokumentált.

---

# 34. Az Epic eredménye

A Chapter 10 végére a StrumSight rendelkezik egy teljes, de kontrollált Community Platformmal, amely:

- opcionális account-rétegként működik;
- nem csökkenti az offline tanulási képességet;
- publikus UUID-t és biztonságos handle-t használ;
- privacy-first profilokat és audience-t kezel;
- támogatja a követést, eltávolítást, mute-ot és blockot;
- időrendi Following feedet biztosít;
- verziózott share artifactból készít posztot;
- idempotensen kezeli a reakciót, kommentet és bookmarkot;
- biztonságosan képes rövid média kezelésére külön feature flag mögött;
- aszinkron challenge-et és verified ranglistát biztosít;
- klubokat és tanulócsoportokat támogat;
- tartós notification inboxszal rendelkezik;
- report, moderation és appeal folyamattal védi a felhasználót;
- offline outboxszal és konfliktuskezeléssel működik;
- támogatja az adat exportot és törlést;
- nem jutalmazza learning XP-vel a népszerűséget;
- nem vezeti be idő előtt a privát chat és live multiplayer kockázatait;
- készen áll a későbbi Offline AI és végső integrációs fejezetekre.

A következő fejezet:

```text
Chapter 11 — Epic 10: Offline AI
```
