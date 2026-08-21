# ADR 0387 — Challenge V2: legacy strum-pattern wrap, single-reward replay, catalog-version pinning

**Státusz:** elfogadva (E08-R19 pre-flight, 2026-08-21, orchestrátor: Claude
Sonnet 5, `--effort high`). Formalizálja a
[`docs/rounds/e08-r19-challenge-v2-and-legacy-migration.md`](../rounds/e08-r19-challenge-v2-and-legacy-migration.md)
§5 kötött döntéseit. Előfeltétele [ADR 0382](0382-quest-objective-and-lifecycle-contract.md)
(típusos quest-életciklus) és [ADR 0384](0384-deterministic-capability-safe-daily-quest-generation.md)
(caller-fed, capability-safe napi generálás — a jelen kör ugyanazt a mintát
követi a napi kihívásra).

**Számozási megjegyzés:** a brief eredetileg `ADR 0314`-et tüntette fel
előre kiosztottként (2026-08-18-i pre-flight-becslés). A tényleges foglalás
(`tools/round-slots.py reserve-adr --round E08-R19`, ADR 0171 §4.0.1) ezen a
napon **0387**-et adott — a 0314-es szám időközben (0314-gate-step-taxonomy.md)
egy másik, régebbi kör alatt lefoglalódott. A foglaló a hiteles forrás, nem a
brief előre írt száma (`ls docs/adr | tail` tilos, lásd a brief-lint és az
`AGENTS.md` §12 pre-flight szabálya) — ez a kör tehát **0387**-en fut, a
brief §0.0 revíziója ezt dokumentálja.

## Kontextus

A `lib/features/streak/daily_challenge.dart` (63 sor) egy determinisztikus,
epoch-nap-alapú pengetési-minta generátor, szerver nélkül; a
`test/features/streak/daily_challenge_test.dart` MA zöld és a kör alatt
VÁLTOZATLAN marad (tilos zóna, A2/A8). A kör négy új, tipizált
kihívás-típussal bővíti a napi kihívást (akkordváltás, ritmus, dal-szakasz,
időzítés), a legacy pengetés-mintát pedig **legacy szolgáltatóként**
csomagolja be — nem írja át, nem másolja. A meglévő `daily_quest_generator.dart`
és `weekly_quest_generator.dart` (R16/R17/R18) már bevezette a caller-fed,
`QuestSchedule.catalogVersion` + `generationEpochDay` + `profileSnapshotKey`
mintát a tipizált quest-katalógusra — ez a kör ugyanezt a mintát követi a
napi kihívásra, nem talál ki újat.

A pre-flight kimérte:

1. Az epoch-nap-küszöb szemantikája (a brief §6.1 táblájának hivatkozása) a
   `StreakLogic.epochDayOf` (`lib/features/streak/streak_logic.dart:18`)
   **helyi éjfél** alapú képlete — NEM a `daily_challenge.dart` fájlban él
   (az csak a `DailyChallenge.forDay(epochDay)` bemenetét fogadja), hanem a
   streak feature-ben, ahonnan minden hívó (`streak_provider.dart`,
   `streak_screen.dart`, `progress_screen.dart`, stb.) ugyanazt az
   `epochDayOf`-ot hívja. [[L362]] mérten figyelmeztet: egy UTC-only
   képzés pozitív időzónában hamis küszöb-ágat rejt — az adapter és a
   szolgáltatás ezért a **hívó-adta epoch-napot** fogadja bemenetként (nem
   maga számol `DateTime.now()`-ból), byte-azonos a shipping helyi-midnight
   képlettel, a hívó (application/presentation réteg, ezen a körön kívül)
   felelőssége az `epochDayOf` meghívása.
2. A jutalom-főkönyv (`RewardLedgerRepository.appendIfAbsent`,
   `data/reward_ledger_repository.dart:7`) a `RewardLedgerEntry.sourceEventId`
   alapján dedupol — ez a meglévő „append-if-absent” elsődleges kulcs, amit a
   brief §5.2 hivatkoz.
3. [[L384]] mérten figyelmeztet: egy ismétlődő katalóguselem receiptje a
   PÉLDÁNYT azonosítsa, ne csak a definíciót — két különböző napi generálás
   ugyanarra a definícióra ne ossza a receiptjét.

**Visszakeresett előzmény:** `lessons/L362` (helyi-midnight epoch-nap
képzés — közvetlenül alkalmazva a küszöb-hármasra), `lessons/L384`
(ismétlődő katalóguselem receipt-identitása — közvetlenül alkalmazva az A3
idempotencia-kulcsra), `adr/0116` (legacy adapter HÍVJA, nem reprodukálja a
forrást — ugyanaz a minta, mint az §5.1). Ellentétes elfogadott döntést egyik
találat sem mutatott.

## Döntés 1 — A legacy adapter HÍVJA a `DailyChallenge.forDay`-t, nem reprodukálja

`LegacyDailyChallengeAdapter` (a kör §4 engedélyezett listáján ÚJ) egy
vékony, adapter-lokális típus, aminek egyetlen felelőssége a
`DailyChallenge.forDay(epochDay)` visszatérési értékét (`pattern`, `name`,
`glyphs`) a Challenge V2 doménbe leképezni (`ChallengeInstance`/
`ChallengeDefinition` egy `legacyStrumPattern` típusú tagjaként vagy
egyenértékű konstrukcióval). A generálási `math.Random(epochDay & 0x7fffffff)`
algoritmus **kizárólag** a meglévő `daily_challenge.dart`-ban él; az adapter
importálja és hívja.

**Indoklás:** ADR 0116 Döntés 1 ugyanezt a mintát rögzítette a
Song/Setlist migrációra — egy adapter a forrás API-ját HÍVJA, nem a
belső logikáját másolja át. A brief §5.1 és a kockázat-lista (§9) explicit
kimondja: „a két másolat az első javításnál elcsúszik, és a felhasználó
mintája megváltozik” — ez mérhető az A1 bitre-azonosság cellával (30 napra)
és a §6.1 valódi-sértés próbával (a logika átmásolása → A1 pirosra vált).

**Nem elfogadható gyengítés:** a `math.Random` szekvencia vagy a névlista
bármilyen újraírása „konzisztencia” vagy „tesztelhetőség” címén az új
fájlban — ez pontosan a tiltott másolás.

## Döntés 2 — A napi kihívás-példány azonosítója `type|generationEpochDay|catalogVersion`, a jutalom-kulcs ebből származik

A generált napi példány (`ChallengeInstance` vagy egyenértékű) stabil
azonosítót kap a meglévő quest-minta szerint:
`'${challengeType}|${generationEpochDay}|${catalogVersion}'` (a
`daily_quest_generator.dart`/`weekly_quest_generator.dart` már bevezetett
`generationEpochDay|profileSnapshotKey|catalogVersion` sémájának analógja,
`profileSnapshotKey` nélkül — a napi kihívás nem profil-specifikus tartalmat
választ, csak elérhetőség-szűrt katalógus-elemet). A jutalom
`RewardLedgerEntry.sourceEventId` erre az azonosítóra épül (pl.
`'daily_challenge:completion:$instanceId'`), a `RewardLedgerRepository
.appendIfAbsent` hívásán át.

**Indoklás:** [[L384]] mérten mutatta, hogy a puszta definíció-ID (itt: a
kihívás-típus) NEM elég egyedi kulcs két különböző napi generálás között — a
`generationEpochDay` és a `catalogVersion` együtt teszi a receiptet
példány-specifikussá, összhangban a Döntés 3-mal (a katalógus-verzió
rögzítése a példányban).

**Nem elfogadható gyengítés:** a jutalom-kulcs puszta `challengeType`-ra
szűkítése — ez másnap ugyanazt a típust választva hamis „már teljesítve”
állapotot adna, vagy fordítva, elveszítené az egyszeres jutalom garanciáját
katalógus-váltás után.

## Döntés 3 — A napi példány a generáláskori `catalogVersion`-t tárolja; a lekérdezés ezt olvassa vissza, nem a legfrissebbet

`DailyChallengeService` a napi példányt (`instanceId`, `challengeType`,
`generationEpochDay`, `catalogVersion`, `completedAt`) perzisztálja a
generáláskor. Egy későbbi lekérdezés **ugyanazon az epoch-napon** a tárolt
példányt adja vissza változatlanul, akkor is, ha a hívó időközben magasabb
`catalogVersion`-t ad át — az új verzió csak a KÖVETKEZŐ epoch-naptól hatásos.

**Indoklás:** a brief §5.3 és a kockázat-lista explicit kimondja: egy
app-frissítés a nap közepén nem cserélheti ki a már megkezdett kihívást — ez
elveszett haladásnak látszana a felhasználó számára. Ez pontosan az A5
acceptance-cella.

**Nem elfogadható gyengítés:** a szolgáltatás minden hívásnál újragenerál a
hívó-adta legfrissebb `catalogVersion`-nel, és csak a teljesítés-flag-et
őrzi meg — ez A5-öt pirosra vinné (a kihívás TARTALMA cserélődne, csak a
progress maradna).

## Döntés 4 — Az elérhetőség-szűrés a katalógus-belépés SAJÁT felelőssége, a generátor csak a szűrt halmazból választ

`ChallengeDefinition` minden típusa (akkordváltás, ritmus, dal-szakasz,
időzítés) egy `bool isAvailable(AvailableContentSnapshot snapshot)` vagy
egyenértékű, hívó-adta elérhetőségi bemenetet fogadó predikátumot hordoz (a
`daily_quest_generator.dart` `_isAvailable(entry, snapshot)` mintájának
analógja). A `DailyChallengeService` a napi generáláskor kizárólag az
elérhető definíciók közül választ; nem elérhető dal- vagy
gyakorlat-azonosítót SOHA nem választhat, offline állapotban is teljes
értékű kihívást ad (a legacy pengetés-minta változat mindig elérhető,
tartalom-azonosító nélkül — ez a fallback, ha semmi más típus nem elérhető).

**Indoklás:** a brief §5.4 és A6 — a generátor nem választhat olyan tartalmat,
ami az eszközön nincs meg; ADR 0384 ugyanezt a capability-safe mintát vezette
be a heti/napi questekre, ez a kör ugyanazt a hívó-adta elérhetőségi
snapshotot alkalmazza a kihívás-katalógusra.

**Nem elfogadható gyengítés:** egy `try/catch` a lejátszás idején, ami néma
üres/hibás kihívást ad nem elérhető tartalomra — a szűrésnek a GENERÁLÁS
pillanatában, típusos bemeneten kell megtörténnie, nem futásidőben elkapva.

## Következmény

- A legacy `daily_challenge.dart` és tesztje ÉRINTETLEN marad (A2, A8) — a
  Challenge V2 réteg kizárólag ÚJ fájlokban él, a `lib/features/streak/**`
  tilos zónájának megfelelően.
- A napi példány azonosítója és a jutalom-kulcs a meglévő quest-minta
  (`generationEpochDay|catalogVersion`) analógja — nincs harmadik,
  divergens azonosítási séma a gamification feature-ben.
- A küszöb-hármas (§6.1) mérése a hívó-adta epoch-napon dől el, nem a
  szolgáltatás saját órájából — a `StreakLogic.epochDayOf` helyi-midnight
  szemantikáját a hívó (ezen a körön kívüli réteg) alkalmazza, a szolgáltatás
  csak a kapott `int`-et használja.
- Katalógus-verzió váltás csak a KÖVETKEZŐ epoch-naptól hatásos — a tárolt
  napi példány a generáláskori verziót őrzi.

Ezen döntések feloldása „zöldre javításként” nem elfogadható; valódi
ellentmondás esetén ez az ADR egy módosítási blokkal bővítendő, nem
csendben felülírandó.
