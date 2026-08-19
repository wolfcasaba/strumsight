# ADR 0301 — Reward ledger: append-only főkönyv és szerializált idempotencia

- **Státusz:** elfogadva
- **Dátum:** 2026-08-19
- **Kör:** `E08-R03` (Chapter 9, Kör 3)
- **Kapcsolódó:** [`0290`](0290-compassionate-streaks-and-idempotent-claims.md)
  (§2 — a beváltás idempotens, a felület nem számít jutalmat; ez a kör teszi
  ezt technikailag kikényszerítetté), [`0329`](0329-canonical-activity-event-contracts.md)
  (a hívó-adta, stabil `eventId` — a ledger `sourceEventId`-je erre a
  stabilitásra épül), [`0257`](0257-planner-typed-ids-and-stable-enum-codes.md)
  (stabil enum-kódok precedense a `RewardReason`-höz)

## Kontextus

Az ADR 0290 §2 elvi szinten kimondta: a jutalom beváltása idempotens, és a
felület nem számol jutalmat. Elvi kimondás technikai kikényszerítés nélkül
nem blokkolja a dupla jutalmat — egy offline sorból visszatérő, vagy egy
UI-újranyitás miatt kétszer beérkező esemény duplikálna, ha a tárolás nem
maga zárja ki ezt. Ez a kör hozza létre az egyetlen auditálható igazságforrást
(a `RewardLedgerEntry` főkönyvet), amelyben ez technikailag lehetetlen.

A projekt már megmérte ugyanezt a hibaosztályt máshol: egy `contains` +
utána `append` kettéválasztás versenyhelyzetben téves eredményt ad, mert az
`await` bármely pontján átadható a vezérlés — ez NEM Dart-specifikus
biztonsági háló hiánya, hanem alapvető aszinkron-szemantika (`test/core/
store_race_sweep_test.dart` és `test/features/progress/
practice_log_race_test.dart` a **kapcsolódó, de más** hibaosztályt őrzi —
lásd a Mérce szakaszt).

## Döntés

1. **A főkönyv append-only.** A `RewardLedgerEntry` immutable, a repository
   felülete nem tartalmaz `update`/`delete` műveletet. Javítás módja
   kompenzáló bejegyzés, nem visszamenőleges átírás.

2. **Az `appendIfAbsent` egyetlen, a repository-példányon belül
   SZERIALIZÁLT művelet — nem „ellenőrzés, majd írás" két lépésben.** A
   repository egy belső, példány-szintű Future-lánccal (tail-chaining sor)
   futtatja minden hozzáfűzését: az adott hívás csak azután olvassa a friss
   állapotot, ellenőrzi a `sourceEventId` jelenlétét és írja vissza a listát,
   hogy az ELŐZŐ hozzáfűzés (ha volt) már lezárult. Ez zárja ki, hogy két
   konkurens hívás ugyanarra a „még hiányzik" pillanatképre írjon vissza. A
   projektben már van bevett minta erre — `SongTransport._commandTail`
   (`lib/features/song_trainer/application/trainer/song_transport.dart:52,
   68-70`): egy `Future<void>` tail-mező, amit minden hívás a sajátjával
   `.then()`-el láncol tovább, a hibát a TAIL-en elnyelve (hogy egy bukott
   hívás ne mérgezze örökre a sort), miközben a HÍVÓ saját future-je a valódi
   eredményt/hibát kapja. Ugyanez az idióma a ledgerben is: nincs szükség
   külső csomagra vagy új absztrakcióra.
   **Nem elfogadható gyengítés:** külső `contains()` hívás a caller oldalán,
   amit egy feltételes `append()` követ — a két hívás közötti `await`
   pillanatban a másik hívás already befuthat.

3. **Ismeretlen schema-verziójú bejegyzés érintetlen marad újraíráskor.** A
   `streak_repository.dart` már bevett mintáját követve: a nem dekódolható
   vagy jövőbeli verziójú bejegyzés nem törlődik és nem íródik felül — a
   főkönyv újraírásakor a nyers, dekódolatlan alakjában marad a listában.

4. **A tárolás a nyers `JsonDocumentStore` felületre épül, NEM a
   `JsonCollectionStore<T>` wrapperre.** Mérve (`lib/core/storage/
   json_document_store.dart`): a `JsonCollectionStore.write()` minden íráskor
   `capRecords`-ot hív, ami a dokumentált `maxItems` fölött **eldobja a
   legrégebbi bejegyzéseket**. Ez a streak/songs/setlists/library „legutóbbi
   N elem" szemantikájának helyes és szándékos — de egy auditálható,
   soha-nem-veszít főkönyvnek pontosan az ellenkezője kellene: a §5.5 lapozás
   is azért létezik, hogy egy több ezer bejegyzéses főkönyvet **veszteség
   nélkül** lehessen kezelni, nem azért, hogy a régi bejegyzéseket eldobja.
   A `local_reward_ledger_repository.dart` ezért a `JsonDocumentStore.
   readBody()`/`.write()` nyers envelope-felületét hívja közvetlenül, saját
   listakezeléssel, cap NÉLKÜL.

5. **A `JsonDocumentStore.write()` whole-envelope csere öröklődik crash-
   védelemként — nincs külön journal-fájl.** A store már ma is
   quarantine-copy → új dokumentum → legacy-kulcs törlése sorrendben ír
   (lásd a fájl saját dokumentációját); minden hozzáfűzés a TELJES,
   frissített listát írja vissza egyetlen `write()` hívással, ugyanúgy, ahogy
   minden más kollekció (streak, songs, setlists, library) teszi ma. A §8.6
   „journal vagy tranzakciós írás" lépése ebből következően **a meglévő
   whole-document write újrafelhasználása**, nem új mechanizmus — bespoke
   journal-fájl bevezetése ezen a körön kívüli, indokolatlan komplexitás
   lenne.

6. **A `RewardReason` zárt `enum`, nem szabad szöveg.** Az `ActivitySource`/
   `EvidenceTrust` (E08-R02) mintáját követi: bare Dart `enum`, a wire-alak a
   `.name` (E08-R02 review NOTE — explicit kódtérkép nélkül elfogadott
   precedens). A lokalizáció a prezentációs rétegben történik majd, az
   enum-értékre kulcsolva — ez a réteg ezen a körön kívül esik.

7. **A domain réteg (`domain/rewards/`) Flutter- és óra-mentes marad — ezt a
   meglévő guard MÁR méri, brief-bővítés nélkül.** A `test/core/
   architecture_dependency_test.dart` „gamification domain stays
   framework-free" csoportja `lib/features/gamification/domain`-t
   REKURZÍVAN listázza — egy új `rewards/` alkönyvtár automatikusan a scope
   része, a teszt módosítása nélkül. Ebből következik: a `RewardLedgerEntry`
   bármely időbélyege csak hívó-adott lehet, nem a konstruktorban hívott
   `DateTime.now()` — ugyanaz az elv, amit az ADR 0329 3. pontja az
   `eventId`-re már kimondott.

8. **A UI nem írhat a főkönyvbe.** A repository írási felülete az
   application-rétegnek szól; a `presentation/` rétegből érkező írás az ADR
   0290 §2 megsértése volna.

## Következmények

**Pozitív.** A dupla jutalom technikailag blokkolt, nem csak konvencióval
tiltott. A crash-helyreállítás nem igényel új tárolási mechanizmust — a
meglévő, más kollekciók által is bizonyított `JsonDocumentStore` szerződést
örökli. A főkönyv soha nem veszít bejegyzést egy régebbi buildre
visszalépéskor sem.

**Negatív / ár.** A szerializált írási sor azt jelenti, hogy sok konkurens
hozzáfűzés torlódhat egy repository-példányon — ez a jutalom-mennyiség
mellett elhanyagolható, de tudatos döntés: nem egy lock-mentes, optimista
séma. A cap nélküli tárolás azt jelenti, hogy a főkönyv mérete korlátlanul nő
— a Kör 7 projekciója és egy jövőbeli archiválási/kompakciós kör felelőssége,
nem ezé.

**Amit ez a döntés TILT.** `update`/`delete` műveletet a repository
felületén; `contains` + `append` szétválasztást; `JsonCollectionStore`
(cap-elő) felület újrafelhasználását a ledgerhez; nem dekódolható bejegyzés
kihagyását újraíráskor; `DateTime.now()`/`Random` hívást a domain rétegben.

## Mérce

Az E08-R03 §6/§6.1 acceptance- és falszifikációs mátrixa (A1–A8), a §6.1
küszöb-hármassal a lapozás `limit` paraméterére. A KÖTELEZŐ valódi-sértés
próba: az atomikus `appendIfAbsent`-et `contains` + `append` párra cserélve a
párhuzamos (A2) cellának pirosra kell váltania, majd visszaállítás után
zöldre.

**Pontosítás a hivatkozott precedens-tesztekről (mérve a pre-flightban):** sem
a `test/features/progress/practice_log_race_test.dart`, sem a `test/core/
store_race_sweep_test.dart` nem `Future.wait`-alapú konkurens dupla-írást
tesztel — mindkettő a „hideg indulás után az azonnali írás nem törli a
tárolt előzményt" hibaosztályt őrzi (E01-R07 óta szerkezetileg megszűnt
hibaosztály, a teszt regresszióként maradt). A ledger A2 cellája ezért ÚJ
mintát vezet be a projektben: két konkurens `Future.wait([repo.
appendIfAbsent(e), repo.appendIfAbsent(e)])` hívás UGYANAZZAL a
`sourceEventId`-vel, és az elvárás, hogy a végállapot egy bejegyzést
tartalmazzon.
