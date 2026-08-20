# ADR 0344 — Gamification repository: verziózott dokumentumok, atomikus csere, réteg-tiszta tárolás

- **Státusz:** elfogadva
- **Dátum:** 2026-08-20
- **Kör:** `E08-R08` (Chapter 9, Kör 8)
- **Kapcsolódó:** [`0054`](0054-versioned-user-content-documents.md) (a
  verziózott envelope + `JsonDocumentStore` mintája, amit ez a kör négy új
  dokumentumra alkalmaz), [`0301`](0301-reward-ledger-append-only-idempotency.md)
  (§4 — mikor NEM szabad `JsonCollectionStore`-t használni a cap-elése miatt;
  ez a kör az ELLENTÉTES esetet, a postaládát dokumentálja, ahol a cap-elés a
  kívánt viselkedés), [`0328`](0328-measured-gamification-baseline-contract.md)
  (a baseline-first fegyelem, amivel a jövőbeli migrációs kör az itt csak
  hely-fenntartásként bevezetett migrációs-állapot dokumentumot ki fogja
  tölteni)

## Kontextus

Az R03 (reward ledger), R04 (activity outbox) és R07 (profile projection) már
három, egymástól független perzisztencia-utat épített a `JsonDocumentStore`
felett, mindegyik a saját fájljában definiálva a storage-kulcsát. A
gamifikáció negyedik és ötödik állapota — a **cache-elt profil-pillanatkép**
(hogy az alkalmazás-indítás ne kényszerüljön minden alkalommal újralejátszani
a teljes ledgert a `ProfileProjector.rebuild()`-en át) és a **jutalom-
postaláda** (függőben lévő, UI-nak szánt értesítések, pl. szintlépés) — még
sehol nem él, és egy hatodik és hetedik állapot, a **katalógus-verzió** és a
**migrációs állapot** könyvvezetése is hiányzik. Négy külön hely helyett ez a
kör egyetlen sémafájlban (`gamification_storage_schema.dart`) rögzíti mind a
négyet, hogy az A8 kritérium ("a gamifikációs kulcsok EGY helyen") ne csak a
négy ÚJ kulcsra, hanem a jövőbeli kulcsok hozzáadási helyére is igaz legyen.

Mért tények, amik a döntéseket megalapozzák (pre-flight, `main @ f2d98204`):

- `lib/core/storage/json_document_store.dart`: a `JsonDocumentStore.write()`
  quarantine-copy → új envelope → legacy-kulcs törlése sorrendben ír; egy
  megszakítás a MEGELŐZŐ envelope-ot érintetlenül hagyja, mert az új kulcs
  írása egyetlen `store.writeString()` hívás (ADR 0301 §5 ugyanezt a
  tulajdonságot már kihasználta a ledgerhez).
- `JsonCollectionStore<T>.write()` minden íráskor `capRecords`-ot hív, ami a
  dokumentált `maxItems` FÖLÖTT eldobja a legrégebbi elemet, `maxItems`-en (a
  küszöbön) és alatta MINDENT megtart (`lib/core/storage/
  json_document_store.dart:294-300`) — ez pontosan az E08-R08 brief §6.1
  küszöb-hármasának inkluzív szemantikája. Az ADR 0301 §4 ezt a wrappert a
  ledgerhez KIZÁRTA (a ledger soha nem veszíthet bejegyzést); a postaláda
  esetén viszont ez a kívánt viselkedés — a postaláda egy korlátos várólista,
  nem auditnapló.
- `test/core/architecture_dependency_test.dart` `_gamificationImportUriMarkers`
  listája (694. sor) MÁR tartalmazza a `package:shared_preferences/`-t, és a
  hozzá tartozó `_forbiddenGamificationDomainMarkerOffenders` helper MÁR
  comment-/string-literal-tudatos (a `_withoutTrivia` közös infrastruktúrán
  át) — de a hívó csoport (`gamification domain stays framework-free`, E08-R02)
  ma KIZÁRÓLAG a `lib/features/gamification/domain` könyvtárt járja be. Sem
  az `application/`, sem egy jövőbeli `presentation/` réteg nincs lefedve
  (mérve: nulla találat sima `SharedPreferences` literálra a teszt fájlban) —
  a brief §5.3/A5 által kért guard tehát valóban hiányzik, nem ismételt munka.
- A mai `lib/features/gamification/application/*.dart` (mind a négy fájl:
  `activity_event_ingestor.dart`, `profile_projector.dart`,
  `reward_eligibility_policy.dart`, `reward_policy_engine.dart`) egyetlen
  framework-importot sem tartalmaz — a `_gamificationImportUriMarkers` lista
  ezért módosítás nélkül, közvetlenül újrafelhasználható az `application/`
  (és a még nem létező `presentation/`) ellenőrzésére is, nem csak a
  `SharedPreferences`-tagre szűkítve.
- `GamificationProfile.progress` (`LevelProgress`) kizárólag
  `LevelCurve.progressForTotalXp(totalXp)`-ból számítható
  (`lib/features/gamification/domain/levels/level_curve.dart:49-75`) — a
  domain modell NEM hordoz saját `toJson`/`fromJson`-t, és a
  `lib/features/gamification/domain/**` ebben a körben tilos zóna. A
  pillanatkép ezért nem a domain típust perzisztálja: egy saját, a
  sémafájlban élő DTO-t ír, ami csak `schemaVersion` + `totalXp`-t hordoz — a
  `progress` a curve-ből mindig újraszámolható, sosem tárolt derivált állapot.

## Döntés

1. **Négy külön dokumentum, egy sémafájlban definiált kulcsokkal.** A
   profil-pillanatkép, a katalógus-verzió, a postaláda és a migrációs állapot
   NÉGY különálló `JsonDocumentStore`-kulcs (nem egy közös blob) — az
   írási/olvasási mintázatuk eltérő gyakoriságú (a profil minden XP-nél
   változik, a katalógus-verzió csak app-frissítésnél, a postaláda
   olvasás-domináns, a migrációs állapot ritkán) — de mind a négy kulcsuk
   EGYETLEN helyen, a `gamification_storage_schema.dart`-ban van felsorolva
   (A8), a R03/R04 szórt mintájával szemben, amit ez a kör nem bánt, csak nem
   ismétel.

2. **A pillanatkép-csere ATOMIKUS, mert egyetlen `JsonDocumentStore.write()`
   hívás.** Nincs külön töröl+ír pár egyik dokumentumra sem. A meglévő
   envelope-write öröklődik crash-védelemként (ADR 0301 §5 ugyanezt tette a
   ledgerrel) — NEM új mechanizmus. A kötelező valódi-sértés próba (brief
   §6.1): az atomikus cserét törlés+írás párra cserélve az A1 cellának
   pirosra kell váltania.

3. **Sérült bájt nem íródik felül; explicit „sérült" jelzést ad, nem csendes
   alapértelmezést.** A `streak_repository.dart` mintáját követi: dekódolási
   hiba → a hívó `null`/explicit sérülés-jelzést kap, a `JsonDocumentStore` a
   nyers bájtokat a következő íráskor karanténba teszi
   (`StorageKeys.quarantineOf`). **Nem elfogadható gyengítés:**
   `catch (_) { return Default(); }` — ez a projekt MÉRT néma no-op
   hibaosztálya (CLAUDE.md, Critical build gotchas).

4. **Minden dokumentum verziózott; ismeretlen verzió explicit hibát ad.** A
   `JsonDocumentStore._decodeEnvelope` ezt már a burkológép szinten
   kikényszeríti (`future_version` → a bájtok karanténba kerülnek, a body
   `null`) — ez a döntés csak megerősíti, hogy egyik új dokumentum sem kerüli
   ki ezt egyedi, verzió nélküli JSON-alakkal.

5. **A profil-pillanatkép a domain `GamificationProfile`-tól FÜGGETLEN DTO,
   csak `schemaVersion` + `totalXp`.** A `progress` (currentLevel/nextLevel/
   xpIntoCurrentLevel/xpToNextLevel) sosem tárolt — a hívó a saját
   `LevelCurve`-jével számolja újra `progressForTotalXp(totalXp)`-vel. Ez
   elkerüli, hogy a data réteg a domain `LevelCurve` policy-objektumtól
   függjön, és elkerüli az elavult/inkonzisztens tárolt `progress` kockázatát
   egy curve-frissítés után (ezt épp a katalógus-verzió dokumentum jelzi a
   hívónak).

6. **A postaláda a meglévő `JsonCollectionStore<T>` wrappert használja,
   `maxItems: inboxRetentionLimit`-tel.** A `capRecords` már bizonyított,
   inkluzív-a-küszöbön szemantikája (lásd Kontextus) pontosan a brief §6.1
   hármasát adja — nincs szükség egyedi nyesési logikára. (Kontraszt az ADR
   0301 §4-gyel: ott a cap-elés volt a hiba, itt a helyes viselkedés — a
   postaláda egy korlátos várólista, nem auditálható főkönyv.)

7. **A migrációs állapot dokumentum ebben a körben csak HELY-fenntartás, nem
   szerződés.** A tényleges migrációs mezőket a Kör 9/10 (ADR 0328
   baseline-first fegyelme szerint) tölti ki; itt egy minimális, verziózott,
   olvasható/írható placeholder elég — új migrációs SZEMANTIKA bevezetése
   ezen a körön kívül esik (brief §3 „NINCS benne").

8. **`SharedPreferences` guard: a MEGLÉVŐ `_gamificationImportUriMarkers` +
   `_forbiddenGamificationDomainMarkerOffenders` pár újrafelhasználása, ÚJ
   csoportban, az `application/` könyvtárra (kötelezően létezik) és
   feltételesen a `presentation/`-re (csak ha létezik — a gamification
   feature-nek ma nincs UI rétege).** Nem új marker-lista, nem új
   comment-parser — a meglévő, már comment-/string-tudatos helper közvetlen
   újrafelhasználása (mérve: egyetlen mai `application/*.dart` sem importál
   Flutter/Riverpod-ot, tehát a teljes lista — nem csak a
   `shared_preferences` tag — kockázat nélkül alkalmazható).

9. **A repository interfész nem szivárogtat tárolási típust (A4).** A
   gamification repository a séma DTO-it és sima Dart típusokat ad
   vissza/fogad, sosem `JsonDocumentStore`-t, `KeyValueStore`-t vagy nyers
   `Map`-et a publikus felületén — ugyanaz az elv, mint a
   `RewardLedgerRepository`/`ActivityOutboxRepository` interfészeken.

## Következmények

**Pozitív.** Négy, korábban tervezetlen gamification-dokumentum egyetlen,
következetes, már bizonyított mintára (`JsonDocumentStore`/
`JsonCollectionStore`) épül; egyik sem igényel új tárolási primitívet vagy
egyedi crash-védelmi logikát. A `SharedPreferences`-guard bővítése a meglévő
helpert használja újra, ezért a diff kockázata alacsony.

**Negatív / ár.** Négy külön kulcs négy külön `write()` hívást jelent — egy
logikai "gamification állapot mentése" művelet, ami több dokumentumot is
érint (pl. profil + postaláda egyszerre), NEM egy tranzakcióban íródik. Ez a
kör nem vezet be kereszt-dokumentum tranzakciót; egy hívónak, ami többet ír
egyszerre, tudnia kell, hogy részleges siker lehetséges (ugyanaz a korlát, ami
a projekt MINDEN többdokumentumos írására már ma is igaz).

**Amit ez a döntés TILT.** Egyedi, a `JsonDocumentStore`-t megkerülő
fájl-I/O-t; a postaláda cap-elésének kézi újraimplementálását
`JsonCollectionStore` helyett; a profil `progress`-ének perzisztálását; a
migrációs állapot dokumentum tényleges migrációs mezőinek kitalálását ebben a
körben; `catch (_) { return Default(); }`-et bármelyik olvasó útvonalon.

## Mérce

Az E08-R08 brief §6/§6.1 acceptance- és falszifikációs mátrixa (A1–A8), a
§6.1 küszöb-hármassal az `inboxRetentionLimit`-re. A KÖTELEZŐ valódi-sértés
próba: az atomikus pillanatkép-cserét törlés+írás párra cserélve az A1
cellának pirosra kell váltania, majd visszaállítás után zöldre.
