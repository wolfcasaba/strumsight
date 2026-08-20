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
   naplót.

2. **Az esemény-ID a teljes stabil wire-fingerprint és a fingerprinten belüli
   determinisztikus occurrence ordinal párja.** A fingerprint része a `day`,
   `source`, `seconds`, `strokes`, `chords` és a nullable
   `directionAccuracy`, kanonikus, locale-független kódolással. Az ordinal
   kizárólag az ugyanilyen fingerprint korábbi előfordulásait számlálja a
   rögzített `newestLast` snapshotban. Nem globális számláló és nem véletlen
   UUID. Így ugyanaz a snapshot ugyanazt az ID-sorozatot adja, miközben az
   exact duplikátumok sem vesznek el.

3. **A három legacy forrás explicit mapping.** `live` →
   `ActivitySource.live`, `analyze` → `ActivitySource.analyze`, `learn` →
   `ActivitySource.learn`. Az ismeretlen wire forrás nem egy új negyedik ág:
   a merge-elt Progress decoder szerződése szerint előbb `live`-ra degradál.
   Negatív időtartam/számláló nem gyárthat kanonikus eseményt.

4. **A backfill nulla retroaktív XP-t ad, de auditálható receiptet és teljes
   reportot készít.** Minden elfogadott legacy eseményhez a ledger
   `appendIfAbsent` útján nulla-XP receipt tartozik (`baseXp = bonusXp =
   totalXp = 0`, üres reason-lista). A migrátor visszatérési reportja a teljes
   snapshot kanonikus eseményeit és aggregált rekordszám/idő/stroke/chord
   baseline-ját adja. A meglévő legacy log változatlanul a történeti UI
   forrása; a profile XP baseline ettől nem nő.

5. **A checkpoint az első fel nem dolgozott index.** A
   `GamificationMigrationState.processedCount` defaultja `0`, monoton, és
   minden sikeres `appendIfAbsent` után perzisztálódik. Az `already present`
   ugyanúgy siker: a ledger dedupja bizonyítja, hogy az esemény már megvan. A
   `checkpoint = 2` esetén az 1-es index már kész, a 2-es az első feldolgozandó,
   a 3-as későbbi. Félbeszakadás nem tekeri vissza a state-et.

6. **A migráció idempotenciája két, egymást erősítő őr.** Normál retrynál a
   checkpoint kihagyja a kész prefixet. Ha a checkpoint hiányzik vagy
   újraépül, a determinisztikus source-event ID + ledger
   `appendIfAbsent` továbbra is megakadályozza a dupla receiptet. Ezért a
   determinisztikus ID nem helyettesíthető a checkpointtal, és fordítva.

7. **A séma-bővítés szűk és visszafelé kompatibilis.** Az R09 kizárólag a
   `GamificationMigrationState` checkpoint mezőjét és JSON round-tripjét
   bővíti. A másik három R08 dokumentum, a négy storage-kulcs és a
   `migrationStateMaxBytes` változatlan. Ismeretlen schema version továbbra is
   explicit hiba.

## Következmények

**Pozitív.** A migráció restart- és replay-biztos, nem ad ellenőrizetlen XP-t,
nem veszít exact duplikátumot, és nem vesz át storage-tulajdonlást a Progress
feature-től. Az idempotenciát a checkpoint elvesztése sem teszi kizárólag egy
mutable index függvényévé.

**Ár és korlát.** Az occurrence ordinal a migráció indulásakor átadott,
rögzített `newestLast` snapshothoz tartozik. A migrátor nem vállal élő
Progress-log lease-et; a caller felelőssége egy konzisztens snapshot átadása.
A nulla-XP receipt nem helyettesíti a legacy statisztikai rekordot, ezért a
legacy log törlése továbbra is tilos.

## Mérce

Az E08-R09 brief A1–A11 cellái. Kötelező mutációs próba: az ID-képzést
újrafuttatásonként növekvő globális számlálóra cserélve az A1/A2 teszt piros,
majd visszaállítás után a teljes kör-gate zöld.
