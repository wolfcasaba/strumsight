# Mi maradt fejlesztendő — mérve 2026-09-05

Minden szám ebben a dokumentumban FUTTATOTT mérésből származik, nem
becslésből. A parancsok a szakaszok mellett állnak.

---

## P0 — A közösségi felület MA ÖSSZEOMLANA

**Négy provider dob a szállított kompozícióban** (mérve: override nélküli
`ProviderContainer`, mind a négy `ProviderException`-t ad):

| Provider | Mit tör el |
|---|---|
| `feedCacheProvider` | a **feed** megnyitása |
| `communityPostRepositoryProvider` | a **szerkesztő** és a **kommentek** |
| `communityKeyValueStoreProvider` | a szerkesztő piszkozat-mentése |
| `communityLoggerProvider` | a szerkesztő |

Ez azt jelenti, hogy a most kiadott teszt-APK-ban a Közösség megnyitása után
a feed **hibára fut**. A route-ok és a backend készen állnak; a kompozíciós
gyökér hiányzik alóluk.

Háromnak triviális a bekötése (a `FeedCache.open(...)`, az app
`keyValueStoreProvider`-e és az `appLoggerProvider`). A negyedik valódi
munka — l. a P1-et.

**Miért nem fogta meg a meglévő őr:** a
`production_repository_wiring_test.dart` a REPOSITORY-providereket méri, a
cache-t, a tárolót és a loggert nem. Az őrt ki kell terjeszteni ugyanarra a
mintára, különben ez a hibaosztály visszatér.

---

## P0 — A közösségi képernyők közt NINCS navigáció

Mérve: a `lib/features/community/presentation/screens/` fában **három**
navigációs hívás van összesen, és mindhárom a profilszerkesztőre vagy a
klub-tagkezelőre mutat.

A Profil hub „Közösség megnyitása" gombja a kapu-képernyőre visz — onnan
viszont **csak a profilszerkesztés nyílik**. A feed, a klubok, az
értesítések, a keresés, a könyvjelzők, a kihívások, a ranglista, a
biztonsági lista és a szerkesztő **route-tal rendelkezik, de a felületről
elérhetetlen**.

Ez a különbség a „13 képernyő elérhető" mérés és a „a felhasználó
használni tudja" valóság között.

**Ugyanez a fában összesen:** a 87 útvonal-konstansból **39-re semmi nem
navigál** a router-fájlokon kívül (community 12, hangelemzés 3,
gyakorlástervező 5, gamification 6, tutor 4, egyéb 9).

```bash
for c in $(grep -o "static const String [a-zA-Z]*" lib/app/routing/app_route.dart | awk '{print $4}'); do
  n=$(grep -rn "AppRoutes\.$c\b" lib/ --include=*.dart | grep -v "app_route.dart:\|app_router.dart:" | wc -l)
  [ "$n" = "0" ] && echo "$c"
done
```

---

## P1 — Két hiányzó Flutter-repository (19 metódus)

| Repository | Metódus | Backend |
|---|---|---|
| `CommunityPostRepository` | 10 | **kész** (posts, comments, reactions, bookmarks) |
| `CommunityClubRepository` | 9 | **kész** (clubs, feed, pinned) |

A szerződés és a végpontok megvannak; a Dio-implementáció hiányzik. Ez
oldja fel a `communityPostRepositoryProvider` és a
`communityClubRepositoryProvider` dobását, és ezzel a szerkesztő, a
kommentek és a három klub-képernyő valódi adatot kap.

---

## P1 — A mérce vakfoltjai

1. **A `check_screen_reachability` a REGISZTRÁCIÓT méri, nem az
   elérhetőséget.** Egy `GoRoute` „elérhetőnek" számít akkor is, ha semmi
   nem navigál oda. Az `Unreachable: 0` cél így teljesíthető úgy, hogy a
   felhasználó semmit nem lát belőle. **Javasolt:** egy cella, ami az
   útvonal-konstansok BEJÖVŐ hivatkozásait számolja.

2. **A populáció hiányos:** 96 képernyőt mér, a fában **99** van. A
   `SetlistListScreenV2`-t semmi nem hivatkozza, és a detektor
   osztálynév-mintája nem fogja a `V2` utótagot.

---

## P2 — A két utolsó elérhetetlen képernyő

Mindkettő olyan folyamatra épülne, ami maga sincs bekötve:

* **`setlist_session_screen`** — a `SetlistItemRunner` typedefnek nincs éles
  implementációja, és a dal-tréner munkamenet-útvonalára sem navigál semmi
  a fában. A félbehagyott tétel ábrázolása viszont KÉSZ
  (`SetlistItemResultStatus.partial`).
* **`ai_tutor/practice_plan_preview_screen`** — a teljes tutor tervezési
  útvonal hivatkozatlan: sem a `PracticePlanCompiler`-t, sem a
  `PracticePlanDraft.deterministicTemplate`-et nem hívja semmi, és a
  `PracticePlanTargetInput`-nak nincs előállítója.

---

## P2 — Backend-rések

**Három szerződés-rés** (`docs/contracts/client-backend-endpoints.json`),
mind ugyanaz az ok: a `routers/challenges.py`-nak **nincs egyetlen GET
route-ja sem** — a kihívás-lista, a részletek és a saját részvétel
lekérdezése hiányzik.

**Az értesítés-kibocsátás egy hiánya:** nyílt profil közvetlen követésére
nincs megengedett típus. A `follow_accepted` az ELLENKEZŐ irányt jelenti,
arra használva a címzett azt hinné, az ő kérelmét fogadták el. Egy
`follow_started` típus felvétele séma- és allowlist-bővítés.

---

## P3 — Kisebb, de valódi

* **A hang-importálásnak nincs folyamata** (se képernyő, se útvonal). A
  felvételi kezdőlap gombja ma kimondja a hiányt egy üzenetben — ez
  őszinte, de nem funkció.
* **A `profilePosts` végpont hiányzik**: se route, se service. A
  láthatósági szűrés (közönség + blokk + némítás) sosem készült el. A
  Flutter-oldal ezért hibát dob, nem üres oldalt — az azt állítaná, hogy
  a profilnak nincs posztja.
* **A klub-posztolás nem használható kliensről:** a `POST /community/posts`
  `club_id` mezője BELSŐ egész szám, a klub-felület viszont csak
  `public_id`-t ad ki.
* **A `review` besorolás hiánya a tervezőben:** a generálási bemenet
  minden jelöltet `newMaterial`-nak jelöl, mert a bizonyíték-olvasás
  aszinkron, a seam viszont szinkron. Következménye mérhető: a beosztó
  ismétlés-aránya az első generáláson nem érvényesül.

---

## Ami KÉSZ és mérve

| | |
|---|---|
| Elérhetetlen képernyők | 23 → **2** |
| Community backend-routerek | 13 → **17** (+20 végpont) |
| Értesítés-kibocsátás | 5 esemény, korábban SEMMI nem hívta |
| Golden variáns-mátrix | 72 → **93 képernyő**, 1488 cella |
| Élő backend | community végpontok 404 → 403 (élnek) |

A variáns-mátrix bővítése **négy valódi UI-hibát** fogott meg 2.0-s
szöveg-méretnél (kapu 8px, felvétel 64px, értesítés-beállítások 2310px,
biztonsági lista teljes sorszélesség) — mind javítva.
