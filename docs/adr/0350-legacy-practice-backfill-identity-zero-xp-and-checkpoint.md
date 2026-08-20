# ADR 0350 — Legacy practice backfill: stabil identitás, nulla XP és perzisztált checkpoint

- **Státusz:** elfogadva
- **Dátum:** 2026-08-20
- **Kör:** `E08-R09` (Chapter 9, Kör 9)
- **Kapcsolódó:** [`0289`](0289-mastery-is-evidence-not-xp.md),
  [`0301`](0301-reward-ledger-append-only-idempotency.md),
  [`0328`](0328-measured-gamification-baseline-contract.md),
  [`0344`](0344-gamification-storage-schema-versioned-documents-and-layer-purity.md)

## Kontextus

A legacy Progress napló legfeljebb 400, `newestLast` sorrendű
`PracticeEntry` rekordot tárol. A rekordnak nincs eseményazonosítója és csak
epoch-napot, forrást, időtartamot, stroke/chord számlálókat és opcionális
direction accuracyt hordoz. A gamification ledger viszont stabil
`sourceEventId` alapján deduplikál, az R08 repository pedig már fenntart egy
verziózott migrációs-state dokumentumot.

A pre-flight a tényleges kódban mérte:

- `progress/public.dart` exportálja a `PracticeEntry` contractot, ezért nincs
  szükség cross-feature belső importra;
- az ismeretlen persistált `src` a legacy decoderben szándékosan `live`-ra
  degradál, a negatív numerikus mező rekord-szintű decode-hiba;
- a checkpoint egyetlen sanctioned tulajdonosa a
  `GamificationRepository.readMigrationState()` /
  `replaceMigrationState()` pár, a local implementációban egy
  `JsonDocumentStore.write()`-tal;
- a merge-elt R08 teszt nulla-argumentumos
  `const GamificationMigrationState()` konstruktort vár, ezért az új mezőnek
  kompatibilis default kell.

Puszta tartalom-hash nem elég: két byte-azonos legacy rekord legitim módon
külön gyakorlási alkalom lehet, mégis azonos hash-t adna. Puszta sorszám sem
elég: újrafuttatáskor más identitást gyárthatna. A döntésnek mind a stabil
replayt, mind a rekordszám megőrzését biztosítania kell.

## Döntés

1. **Az adapter csak publikus, caller-supplied bemenetet kap.** A
   `legacy_practice_adapter.dart` a `progress/public.dart`-ból importált
   `PracticeEntry` listát alakítja kanonikus eseményekké. Nem nyit Progress
   repositoryt, storage plugint vagy Riverpod providert, és nem írja a legacy
   naplót. A mért legacy cap 400: pontosan 400 rekord elfogadott, 401 vagy több
   explicit `ArgumentError`, nem korlátlan in-process munka.

2. **Az esemény-ID a teljes stabil wire-fingerprint opaque SHA-256 digestje és
   a fingerprinten belüli determinisztikus occurrence ordinal párja.** A
   digest bemenete a `day`, `source`, `seconds`, `strokes`, `chords` és a
   nullable `directionAccuracy` kanonikus, locale-független kódolása. A nyers
   mezők nem jelenhetnek meg az ID-ban. Az ordinal
   kizárólag az ugyanilyen fingerprint korábbi előfordulásait számlálja a
   rögzített `newestLast` snapshotban. Nem globális számláló és nem véletlen
   UUID. Így ugyanaz a snapshot ugyanazt az ID-sorozatot adja, miközben az
   exact duplikátumok sem vesznek el.

3. **A három legacy forrás explicit mapping és szűk input-validáció.** `live` →
   `ActivitySource.live`, `analyze` → `ActivitySource.analyze`, `learn` →
   `ActivitySource.learn`. Az ismeretlen wire forrás nem egy új negyedik ág:
   a merge-elt Progress decoder szerződése szerint előbb `live`-ra degradál.
   Negatív időtartam/számláló vagy negatív/DateTime-ként nem reprezentálható
   epoch-day nem gyárthat kanonikus eseményt és nem állíthatja le a teljes
   migrációt. A decoder-valid `day = 1 << 40` kötelező szélsőérték-cella.

4. **A backfill nulla retroaktív XP-t ad: a reward ledgerhez egyáltalán nem
   nyúl.** A migrátor visszatérési reportja a teljes snapshot kanonikus
   eseményeit és aggregált rekordszám/idő/stroke/chord baseline-ját adja. A
   meglévő legacy log változatlanul a történeti UI forrása; a profile XP
   baseline ettől nem nő. `RewardLedgerRepository` nem része a migrátor
   contractjának.

5. **A checkpoint az első fel nem dolgozott index.** A
   `GamificationMigrationState.processedCount` defaultja `0`, monoton, és
   minden sikeresen leképezett rekord után perzisztálódik. A `checkpoint = 2`
   esetén az 1-es index már kész, a 2-es az első feldolgozandó, a 3-as későbbi.
   Félbeszakadás nem tekeri vissza a state-et. Ha maga a best-effort
   checkpoint-írás nem perzisztál, a következő futás legfeljebb tiszta mappinget
   ismétel; ledger- vagy statisztikai adat nem veszhet el.

6. **A migráció idempotenciája side-effect minimalizálásból ered.** Normál
   retrynál a checkpoint kihagyja a kész prefixet. Ha a checkpoint hiányzik
   vagy újraépül, a determinisztikus mapping/report újraszámítása nem ír
   rewardot és nem módosítja a legacy logot; ezért a replay önmagában ártalmatlan.

7. **A séma-bővítés szűk és visszafelé kompatibilis.** Az R09 kizárólag a
   `GamificationMigrationState` checkpoint mezőjét és JSON round-tripjét
   bővíti. A másik három R08 dokumentum, a négy storage-kulcs és a
   `migrationStateMaxBytes` változatlan. Ismeretlen schema version továbbra is
   explicit hiba.

## Következmények

**Pozitív.** A migráció restart- és replay-biztos, nem ad ellenőrizetlen XP-t,
nem veszít exact duplikátumot, és nem vesz át storage-tulajdonlást a Progress
feature-től. A ledger és checkpoint közötti cross-document részleges siker
lehetősége megszűnik, mert a migrátor nem ír ledgerbe.

**Ár és korlát.** Az occurrence ordinal a migráció indulásakor átadott,
rögzített `newestLast` snapshothoz tartozik. A migrátor nem vállal élő
Progress-log lease-et; a caller felelőssége egy konzisztens snapshot átadása.
A report nem helyettesíti a legacy statisztikai rekordot, ezért a legacy log
törlése továbbra is tilos.

## Mérce

Az E08-R09 brief A1–A11 cellái. Kötelező mutációs próba: az ID-képzést
újrafuttatásonként növekvő globális számlálóra cserélve az A1 teszt piros,
majd visszaállítás után a teljes kör-gate zöld. A2 külön forrásőrrel bizonyítja,
hogy a migrátornak nincs ledger side effectje.
