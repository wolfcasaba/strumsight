# E12-R15 review — Audio, camera és local AI resource coexistence

- **Reviewer:** Claude (Opus 5), orchestrátor-szék
- **Dátum:** 2026-08-29
- **Kör:** `E12-R15`, ág `sonnet-impl/e12-r15-resource-coexistence-policy`
- **Review-lt HEAD:** `1e4fb889` (pre-flight base: `c771dd8d`)
- **Motor:** `sonnet-impl` (Claude Sonnet 5, `--effort high`)
- **Módszer:** read-only review izolált klónban (`/tmp/ss-review-e12-r15`,
  `1e4fb889`-re checkoutolva), eldobható próbatesztekkel
  (`test/core/resources/zz_review_probe_test.dart`, a review után törölve).

## Gépi előfeltételek

| Ellenőrzés | Mért érték |
|---|---|
| `scope_audit` (jelzésfájl) | `ok`, base `c771dd8d`, 8 változott fájl — mind az `allowed_paths` listáról |
| `dirty_files` a jelzéskor | `1` — kivizsgálva: a `git status --short` a jelzés után **üres**, a `HEAD` (`1e4fb889`) egyezik a jelzésfájl `head=` mezőjével; tranziens, nincs elveszett munka |
| `gate_shape` | `ok` |
| CI-terv (`round-ci-plan.py`) | `dispatch = [full-gate.yml]`, `apk_required = false`, `router_ci_expected = true` |

## VÉGSŐ DÖNTÉS (1. kör): CHANGES REQUESTED — 2 MAJOR

A kör váza helyes, és a legnehezebb dolgot jól csinálja: az arbiternek
**fizikailag nincs referenciája** egyik koordinátorra sem (D7), ezért a
lease-elvétel nem is kifejezhető benne — az ADR 0476 D2 nem szövegszerű ígéret,
hanem szerkezeti tulajdonság. Az A2/A3 cellák VALÓDI `AudioSessionCoordinator`
/ `CameraSessionCoordinator` példányon mérnek (nem mockolt csatornán, L453), és
az A3 sima `test()`-ben fut, elkerülve az L513 fagyás-csapdát. A §10
valódi-sértés próba dokumentált és hihető.

A két MAJOR ugyanabból a mintázatból jön, mint a kör előtti
[L549](../LESSONS.md#l549): **a mechanizmus MEGLÉTE ki van kényszerítve, a
JELENTÉSE nincs.**

---

### F1 (MAJOR) — a szerződés-dokumentum olyan mérést állít, ami nem létezik

`docs/contracts/resource-coexistence.md:48-50` szó szerint:

> „Ez NEM `cancel` — egy fogyasztó, amelyik a felfüggesztést `cancel`-lel
> valósítja meg, sérti a szerződést (`resource_arbiter_test.dart` A5 méri)."

**Mérve: az A5 ezt NEM méri.** Az A5 cella a `_FakeConsumer`-t használja,
amelynek a `pauseForHigherPriority()`-ja a TESZT saját kódja — a cella tehát
azt bizonyítja, hogy az **arbiter** `pause`-t hív `release` helyett, nem azt,
hogy egy **fogyasztó** megőrzi a munkáját.

Eldobható próba (`zz_review_probe_test.dart` P4, a `1e4fb889`-en futtatva):

```dart
class _CancellingFake extends _Fake {
  @override
  Future<void> pauseForHigherPriority() async {
    state = '';                       // cancel, nem pause — D3 megsértése
    await super.pauseForHigherPriority();
  }
}
```

Eredmény: **`00:00 +3 -1`** — a P4 **ZÖLDEN átment**, azaz a szerződést nyíltan
sértő fogyasztót az arbiter és a teszt-készlet szó nélkül elfogadja. A §6.1
mérce-mátrix „a `pauseForHigherPriority` valójában `cancel`-t hív → A5" sora
tehát csak az arbiter-oldali olvasatra igaz; a fogyasztó-oldalira nem.

Ez azért MAJOR, és nem NOTE: a kör terméke **maga a fogyasztói szerződés**, a
`ResourceConsumer` implementálói pedig későbbi körök (Epic 10 Kör 12, a vision-
és mic-bekötés) lesznek — pontosan az a réteg, amit ez a mondat védeni ígér.

**Kért javítás (a listán belül, két elfogadható út közül az egyik):**

1. **Gépi őr** — `resource_arbiter_test.dart`-ba egy újrahasznosítható
   szerződés-konformancia cella-készlet (pl. `void
   runResourceConsumerContract(String name, ResourceConsumer Function() make)`),
   amely bármely implementációra méri, hogy `pauseForHigherPriority()` után az
   `isActive` igaz marad, a fogyasztó `resume`-olható, és a megőrzendő állapot
   megvan; **plusz egy önvédő cella, amely bizonyítja, hogy egy szándékosan
   `cancel`-ként megírt fogyasztó ezen a készleten PIROS**. Ezután a
   contract-doksi mondata igaz lesz.
2. **Vagy** a doksi-mondat javítása arra, amit a cella ténylegesen mér („az A5
   azt méri, hogy az ARBITER `pause`-t hív, nem `release`-t; a fogyasztó-oldali
   megőrzésre ebben a körben nincs gépi őr — ezt a bekötő kör hozza"), és a
   §6.1 mátrix sorának megfelelő pontosítása.

Az 1. út a jobb (a mérce erősödik), de a 2. is elfogadható — amit NEM fogadok
el, az a jelenlegi állapot: **mért állítás nélküli mondat egy szerződésben.**

---

### F2 (MAJOR) — a felfüggesztésből nincs visszaút: a kör saját céljában nevesített „néma elakadás"

A brief §1 célja szó szerint: „prioritási szerződés … **leak és néma elakadás
nélkül**". Mérve: az arbiter felfüggeszt, de **soha, semmilyen úton nem
folytat**. A `ResourceArbiter` felülete `register` / `unregister` / `request` /
`onMemoryPressure` — nincs belépési pont, amin megtudná, hogy egy magasabb
prioritású fogyasztó befejezte a munkáját, és a `resume()`-ot sem hívja sehol.

Eldobható próba (`zz_review_probe_test.dart` P1 és P2, mindkettő **ZÖLD** a
`1e4fb889`-en):

- **P1** — `backgroundAi` aktív → `liveAudio` kér → `background` felfüggesztve →
  `live.release()` (az egyetlen befejezési út, amit a szerződés kínál) → a
  `background` **továbbra is `isSuspended == true`, `resumeCalls == 0`**.
  Örökre felfüggesztve marad.
- **P2** — egyetlen aktív `liveAudio` fogyasztó + `onMemoryPressure()` → a
  **LIVE** fogyasztó felfüggesztődik (az A4 „repeated pressure" cellája ezt
  szándékos viselkedésként rögzíti is), `resumeCalls == 0` — a felhasználó
  éppen futó gyakorlása áll le némán, visszaút nélkül.

A jelenség sem az ADR 0476-ban, sem a contract-doksi „Amit ez a kör NEM köt be"
listájában (`resource-coexistence.md:101-110`) nincs megemlítve — pedig az a
lista pontosan a tudatos kihagyások helye. Így ma nem *elhalasztott döntés*,
hanem *észrevétlen lyuk* a szerződésben.

**Kért javítás (a listán belül):**

- Az arbiter kapjon belépési pontot, amin megtudja, hogy egy fogyasztó
  befejezte (pl. `Future<void> notifyReleased(ResourceConsumer)` vagy a
  `release`-t is az arbiteren átvezetve), és ekkor **folytassa a legmagasabb
  prioritású felfüggesztett fogyasztót, amelyet már egyetlen aktív fogyasztó sem
  előz** — a D2 (nem lopunk) és a D1 (rendezettség) sérelme nélkül;
- ehhez cella `resource_arbiter_test.dart`-ban, amely a P1 forgatókönyvet
  méri, és amely a mai kódon PIROS lenne;
- a `docs/contracts/resource-coexistence.md` írja le a visszaút szabályát,
  **és** a memória-nyomás alatti `liveAudio`-felfüggesztés visszaútját is.

Ha a bekötő kör körébe tartozónak ítéled a mechanizmust, az **elfogadható
alternatíva**: akkor viszont a contract-doksi „Amit ez a kör NEM köt be"
listájára KELL kerülnie kimondottan („a felfüggesztett fogyasztó folytatásáért
ma a fogyasztó tulajdonosa felel; az arbiter-vezérelt visszaút a bekötő kör
dolga"), és a §1 cél „néma elakadás nélkül" megfogalmazását a brief §10-ben
korlátozni kell arra, amit a kör ténylegesen bizonyít.

---

### F3 (MINOR) — `register()` `==`-szel dedupel, a `request()` `identical`-lel

`resource_arbiter.dart:59` `_consumers.contains(consumer)` (`==`), míg a
`request`/`onMemoryPressure` szűrői `identical`-t használnak. Egy `==`-t
felülíró fogyasztó-implementáció regisztrációkor eltűnhet.

**Mérve viszont: észlelhető rossz viselkedést ma NEM okoz.** A próba P3 cellája
pont ezt akarta megfogni, és **megbukott a saját hipotézisében**: a D1
döntetlen-szabály akkor is életbe lép, ha a második példány nincs
regisztrálva, mert a `request` a MÁR regisztrált, azonos prioritású aktív
fogyasztót látja (`ResourceDenied(equalPriorityActive)`). A lelet ezért MINOR
és konzisztencia-jellegű: egyetlen identitás-szemantikát használj (`identical`),
hogy a viselkedés ne függjön a jövőbeli implementációk `==`-ától.

### F4 (MINOR) — `_AudioBackedConsumer.acquire()` elnyeli a hibát

`resource_arbiter_test.dart:272-275`: `lease = result.valueOrNull;` — ha a
koordinátor BUSY-t ad, a `lease` némán `null` marad, és az `isActive` `false`
lesz anélkül, hogy bármi jelezné. Teszt-belső adapter, ezért MINOR, de pont ez
a projekt mért „silent no-op" osztálya. Egy `expect(result.isSuccess, isTrue)`
az adapteren belül elég.

### F5 (NOTE) — duplikált §11 fejléc

`docs/rounds/e12-r15-resource-coexistence-policy.md` végén a
`## 11. Review — a Claude tölti ki` sor **kétszer** szerepel. A review-szakaszt
én töltöm, a duplikátumot a javító kör törölje.

### F6 (NOTE) — a memória-nyomás ugyanazt a `pauseForHigherPriority()`-t hívja

A §10 3. pontja ezt tudatos döntésként rögzíti, és a `ResourceConsumer`
doc-commentje is kimondja („or because of memory pressure"), ezért nem lelet —
de érdemes tudni: a fogyasztó nem tudja megkülönböztetni a „adj helyet egy
magasabb prioritásúnak" és a „szabadíts fel memóriát" okot, holott a helyes
válasz eltérhet (az utóbbinál cache-eldobás is kellhet, ami épp a megőrzendő
állapot ellen hat). Ha a bekötő körben ez fájni fog, ott kap okot a metódus.

---

## Amit külön ellenőriztem, és RENDBEN van

- **ADR 0476 D2 — lease-elvétel:** `grep -n "revokeActive\|\.release()"
  lib/core/resources/` → az arbiterben egyetlen `revokeActive` és egyetlen
  fogyasztó-`release()` hívás sincs. Szerkezetileg kizárt.
- **D5 — nincs új `FailureCode`:** az arbiter nem importálja az
  `app_failure.dart`-ot; a `ResourceDenialReason` enum
  `lib/core/resources`-lokális.
- **D7 — architektúra:** az arbiter és a szerződés `lib/features/**`-et nem
  importál; a `round-gate.sh` `architecture` lépése (a §10 szerint) zöld.
- **A6 — a meglévő koordinátor-tesztek:** a diff egyetlen sort sem érint
  `lib/core/audio/**` vagy `lib/core/camera/**` alatt (`git diff --stat
  c771dd8d..1e4fb889`).
- **A4 rendezettség:** a `reduce`-ban a `>=` a legnagyobb `index`-et
  (= legalacsonyabb prioritást) választja; megfordítva az A4 pirosra vált.

## 2. kör — a javítás utáni ellenőrzés (HEAD `237fd604`)

- **Motor:** `sonnet-impl`, 1 javító kör (a MiniMax-eszkalációs küszöb alatt).
- **`scope_audit`:** `ok`, base `3f76c313`, 5 változott fájl — mind a listáról.
- **`dirty_files=1` a jelzéskor:** kivizsgálva, a `git status --short` üres, a
  `HEAD` egyezik a jelzés `head=` mezőjével. Nincs elveszett munka.
- **Módszer:** friss izolált klón (`/tmp/ss-review2-e12-r15`, `237fd604`),
  eldobható próba (`zz_review2_probe_test.dart`, Q1–Q5), a review után törölve.

### Leletenkénti zárás

| Lelet | Állapot | Mérés |
|---|---|---|
| **F1** (MAJOR) | **ZÁRVA** | `runResourceConsumerContract` / `checkResourceConsumerContract` újrahasznosítható készlet + **önvédő cella**: `expectLater(checkResourceConsumerContract(make: () => _CancellingFakeConsumer(...)), throwsA(isA<TestFailure>()))` — ZÖLD, tehát a készlet ténylegesen MEGFOGJA a cancel-fogyasztót. A contract-doksi mondata most a valódi őr nevére hivatkozik, és külön kimondja, hogy az A5 csak az arbiter-oldalt méri. |
| **F2** (MAJOR) | **ZÁRVA** | `releaseConsumer()` + `onMemoryPressureRelieved()` + `_resumeNoLongerOutranked()` (legmagasabb prioritástól lefelé). Saját próba **Q1 ZÖLD**: `releaseConsumer(live)` után `background.isSuspended == false`, `resumeCalls == 1`. **Q3 ZÖLD**: a részleges visszaút helyes — a `camera` folytatódik, a `background` felfüggesztve marad, amíg a `camera` aktív. **Q5 ZÖLD**: a memória-nyomás oda-vissza útja zárt. |
| **F3** (MINOR) | **ZÁRVA** | `register`/`unregister` `identical`-re egységesítve (`resource_arbiter.dart:59-66`). |
| **F4** (MINOR) | **ZÁRVA** | `_AudioBackedConsumer` / `_CameraBackedConsumer` adapterek `expect(result.isSuccess, isTrue)` őrt kaptak. |
| **F5** (NOTE) | **ZÁRVA** | a duplikált `## 11.` fejléc törölve. |
| **F6** (NOTE) | tudomásul véve | a §10 3. pontja tudatos döntésként rögzíti; nem igényel változtatást. |

### Két ÚJ mérés a javítás fölött (egyik sem lelet)

- **Q4 (ZÖLD):** a visszaút **nem támaszt fel** egy már teljesen elengedett
  fogyasztót — `releaseConsumer(background)` után a `releaseConsumer(live)`
  pass `resumeCalls == 0`-t hagy rajta. Ez fontos, mert a `_resumeNoLongerOutranked`
  az `isActive && isSuspended` szűrőn megy, és az elengedett fogyasztó
  `isActive == false`.
- **Q2 (ZÖLD) — dokumentált maradvány, NOTE:** ha egy fogyasztó **közvetlenül**
  hívja a saját `release()`-ét (megkerülve az arbitert), a felfüggesztett
  társai továbbra is felfüggesztve maradnak. Ez ma **kimondott** — a
  contract-doksi a `releaseConsumer` sorában nevesíti a két utat („a korábbi
  közvetlen `consumer.release()` helyett EZT hívja, ha azt akarja, hogy az
  arbiter a visszautat is elintézze"), és az A3 e2e cella szándékosan a
  közvetlen utat járja (a kamera route-leave a koordinátort méri, nem az
  arbitert). A bekötő körnek ezt tudnia kell: **az arbiter csak akkor tud a
  visszaútról, ha a befejezés rajta megy keresztül.** Nem BLOCKER és nem MAJOR,
  mert nincs bekötött hívó, és a szerződés kimondja.

### Saját futtatás (izolált klón, `237fd604`)

```
flutter test test/core/resources/ test/e2e/resource_coexistence_test.dart
00:00 +18: All tests passed!
```

(13 kör-cella + 5 eldobható próba-cella.)

## VÉGSŐ DÖNTÉS: APPROVED

Nyitott BLOCKER/MAJOR/MINOR: **0**. A két MAJOR gépi őrrel zárult, nem
szöveggel — az F1 önvédő cellája és az F2 Q1/Q3 próbája egyaránt a MÉRT
viselkedést bizonyítja.

**Merge-feltétel (a review-tól függetlenül kötelező):** a `full-gate.yml` és a
`router-ci.yml` `success` a merge SHA-ján. Az első CI-futás (`33240406764`, a
javítás ELŐTTI `1e4fb889` SHA-n) **piros** volt, de **nem a kör diffje miatt**:
a randomizált HARD property-lépés
(`PROPERTY_SEED=33240406764`) bukott a `test/property/dsp_property_test.dart:438`
„a strum must merge into ONE onset" celláján (`Expected: >= 18 / Actual: 17`, 20
próbából). A kör diffje kizárólag `lib/core/resources/**`, `test/core/resources/**`,
`test/e2e/**` és dokumentum — DSP onset-összevonásra nincs ráhatása. Ez a
mért, seed-függő flakiness a kör előtti kódban él.
