# E06-R28 — Biztonsági / adatvédelmi review

Brief: `docs/rounds/e06-r28-cache-performance-and-model-lifecycle.md` (ai-router `risk = "high"` → AGENTS.md §15.1 szerint KÖTELEZŐ, a tartalmi review-tól független)
Diff: `git diff 0efa1906..adbe8eee` (izolált klón: `/tmp/review-e06-r28`, branch `codex/e06-r28-cache-performance-and-model-lifecycle`)
Reviewer: Claude (security-reviewer, READ-ONLY) · Dátum: 2026-08-13
ADR: `docs/adr/0248-analysis-cache-key-and-performance-budget.md`

**Verdikt: APPROVED** — 0 CRITICAL · 0 BLOCKER · 0 MAJOR.
Merge-tiltó lelet NINCS. A leletek MINOR/NOTE osztályúak, mindegyik **latens**:
a cache-nek ma **nulla hívója van** az egész fában (mérve, lásd §4/N0), az
`audioAnalysisV2Enabled` és minden al-flag `false` (`lib/app/config/feature_flags.dart:32,83`).

## Összegzés

BLOCKER: 0 · MAJOR: 0 · MINOR: 5 · NOTE: 5

A kör négy új production fájlja **nem tartalmaz** hálózati hívást, logolást,
analitikát, secret-tárolást, engedélykérést és külső tartalom-parse-olást a
saját JSON-jain kívül. A path-traversal **bizonyítottan zárt**. A fingerprint
**bizonyítottan nem hordoz fájlnevet/elérési utat/eszközazonosítót**, és a
kimenetéből valós hosszúságú audio **nem rekonstruálható**. A leletek két
csoportba esnek: (a) a lemezes cache erőforrás-viselkedése a saját ADR-jében
rögzített 50 MiB-os határon (mért), (b) jövőbeli hívó számára nyitva hagyott,
ma elérhetetlen élek (jogosultsági/fail-closed hézagok, teszt-őrök rigora).

**Minden lelet ugyanabba az egy irányba mutat: a bekötő (wiring) kör előtt kell
lezárni őket.** A §6 „Kötelező előfeltételek a bekötő körnek" blokk ezt tételesen
felsorolja — ez a jelentés fő üzenete a következő körnek.

---

## 1. A megrendelt hét mérés — tételes eredmény

| # | Kérdés | Verdikt | Bizonyíték (mért) |
|---|---|---|---|
| 1 | A fingerprint nem rekonstruálja a nyers audiot, nem azonosít felhasználót | ✅ **igazolva** | `p4_fingerprint.dart` + adatfolyam-követés — lásd §2 |
| 2 | `<cacheId>.json` path-traversal-biztos | ✅ **igazolva** | `p1_paths.dart`: 1000 ellenséges kulcs → 0 nem-hex `cacheId`; a `../../../../../../etc/passwd` komponensű kulcs fájlja a cache-könyvtárban maradt |
| 3 | A payload nem tárol tokent/érzékeny diagnosztikát | ⚠️ **NOTE-3** | `AnalysisCache.put()` nyers `Uint8List`-et fogad, tartalmi korlátozás nincs; ma nincs hívó → jövőbeli hívó felelőssége |
| 4 | Cache ↔ mentett dokumentum fájlrendszeri elkülönülés | ✅ + ⚠️ **MINOR-2** | konstansok külön (`analysis` vs `analysis_cache`), de az elkülönülést KIZÁRÓLAG a wiring garantálja, az osztály nem |
| 5 | `storage_keys.dart` additív-e | ✅ **igazolva** | a diff csak hozzáad (`+7 sor`), egyetlen kulcs sem átnevezve/törölve; `secureAuthToken` továbbra sincs az `all` listában |
| 6 | Nincs rejtett hálózati hívás / új engedély | ✅ **igazolva** | a négy új fájl importjai: `dart:async/convert/io/typed_data`, `package:crypto`, belső domain — semmi más; `AndroidManifest.xml` nincs a diffben |
| 7 | A brief §0.0 állítása az R27 `AnalysisCachePort`-ról igaz-e | ✅ **igazolva** | `git diff --name-only 0efa1906..adbe8eee` — `delete_analysis_use_case.dart` NINCS a 15 fájl között; a portnak ma sincs adaptere (0 találat) |

---

## 2. Mit mértem a fingerprintnél (1. pont, részletesen)

**Bemenet-audit.** `AudioFingerprint.compute()`
(`lib/features/audio_analysis/data/cache/audio_fingerprint.dart:15-45`) négy
named paramétert fogad: `samples`, `sampleRate`, `channelCount`,
`preprocessingVersion`. **Fájlnév/elérési út/eszközazonosító paraméter nem
létezik** — a tulajdonság szerkezeti, nem konvenció. A hashbe pontosan ez kerül:
20 bájt fejléc (mintaszám u64 | sampleRate u32 | csatornaszám u32 |
verzió-hossz u32) + a verzió UTF-8 bájtjai + a 16-bitre kvantált PCM.

- **Kanonikus, hossz-prefixelt kódolás** → nincs határ-elcsúszásos ütközés.
  Mérve (`p4` 2.): `("AA", 1 minta)` ≠ `("A", 2 minta)`.
- **A fejléc tényleg részt vesz** (mérve, `p4` 1.): 44100↔48000, mono↔sztereó,
  `preprocess-v1`↔`v2` mind más digestet ad. (Erre **nincs teszt** → NOTE-5.)
- **Nem-véges minta fail-closed**: `NaN`/`±Infinity` → `ArgumentError`
  (`audio_fingerprint.dart:38-40`), és a hibaüzenet csak a szabálytalan értéket
  („NaN") tartalmazza, audio-tartalmat nem (§5.3 tiszta).
- **Rekonstruálhatóság — mért határ.** A „nem visszafejthető" állítás nem
  szerkezeti, hanem keresési-tér-alapú, ezért kimértem: **1 mintás** digestből a
  minta brute-force-szal visszanyerhető (`p4` 6.: 65 535 próbából 1 találat,
  a helyreállított kvantum `q=13805` = az eredeti). N mintára a tér `65536^N`,
  azaz **N=4 (≈90 µs 44.1 kHz-es audio) már 2^64** — bármely valós klipnél a
  tulajdonság tartható. Az ADR Döntés 2 állítása ezzel **igaz**, a pontos
  megfogalmazása „gyakorlatilag visszafejthetetlen valós hosszúságú bemenetre".
- **Sózatlan → megerősítő orákulum.** Aki birtokol egy jelölt hangfájlt, egy
  kiszivárgott fingerprintből meg tudja erősíteni, hogy a felhasználó azt
  elemezte. Ez **ma zárt**: az R27 export-szerződés kifejezetten kizárja a
  fingerprintet az eszközt elhagyó payloadból
  (`domain/export/analysis_export.dart:14-16`, `domain/export/redaction_policy.dart:36-38`),
  és a repo-szintű grep szerint a fingerprintnek nincs más egress-útja
  (csak a helyi `analysis_document_codec.dart:103,130`).
- **A hívási lánc is tiszta**: ma az egyetlen production `inputFingerprint`-előállító
  a `legacy_analyze_adapter.dart:94` — `'legacy-session:${session.id}'`, ahol a
  `session.id` egy `microsecondsSinceEpoch` időbélyeg
  (`features/analyze/screens/analyze_screen.dart:64`). **Nincs benne fájlnév,
  útvonal, eszköz-ID.**

---

## 3. Megállapítások

### MINOR-1 — A cache minden művelete O(teljes cache-méret), és a mért baseline-számok 4 bájtos payloadról származnak

**Hely:** `lib/features/audio_analysis/data/cache/analysis_cache.dart:169-190`
(`_readEntries`), hívói: `put`→`_evictToLimits` (139), `entryCount` (150),
`totalBytes` (153), `invalidate` (128), `purge` (135), `openAtDirectory`→`_largestAccessOrdinal` (66).

`_readEntries()` **minden** bejegyzést beolvas és **base64-dekódol** — akkor is,
ha csak a bejegyzésszámra vagy a hozzáférési sorrendre van szükség —, és az
összes payloadot **egyszerre** tartja a visszaadott listában.

**Failure scenario (mért, `p3_lru_memory.dart`, ADR-beli 50 MiB cap-en, 20×2,5 MiB):**

```
entries=20 payload=50.0 MiB (cap 50.0 MiB)
on-disk bytes for a 50.0 MiB "50 MiB cap" cache = 66.7 MiB
entryCount() on a full cache  : 616 ms   (rss 256.8 MiB, maxRss 271.6 MiB, baseline 179.6)
put(16 bytes) into full cache : 609 ms
invalidate(unknown id)        : 611 ms
```

Azaz egy **16 bájtos** bejegyzés kiírása 0,61 s és ~90 MiB tranziens allokáció
egy 4 CPU-s aarch64 szerveren; közepes Android eszközön rosszabb. A körrel
együtt commitolt baseline (`docs/baseline/epic-06-analysis-performance.md`)
`missMicroseconds: 30589 / hitMicroseconds: 5317` értékeket dokumentál — ezek
**4 bájtos** payloadról származnak (`tool/audio_analysis_benchmark.dart:70-72`),
tehát a cap közelében ~20× optimistábbak a valóságnál. A dokumentum általános
kitétele („nem teljes V2 pipeline teljesítményígéret") ezt a nagyságrendi
eltérést nem fedi le.

Járulékos, mért tény: a **„50 MiB cap" valójában 66,7 MiB lemezt jelent**
(base64 1,33×). A `totalBytes()` doc-comment ezt jelzi, az ADR Döntés 4
szövege („50 MiB (52 428 800 bájt)") viszont lemez-büdzsének olvasható.

**Sértett szabály:** SDD Ch7 §22.7 (performance budget) / ADR 0248 Döntés 4 és 11
mérési hitelessége. Nem termékhatár-sértés → nem BLOCKER; hívó nélkül nem
elérhető → nem MAJOR.

**Javasolt irány:** metaadat-sidecar vagy fájlnév-be kódolt access-ordinal, hogy
az LRU-könyvelés ne dekódolja a payloadokat; a baseline-számokat a cap közeli
payloadmérettel is fel kell venni, mielőtt bárki budget-döntést hoz rájuk.

### MINOR-2 — A cache a könyvtára MINDEN `*.json` fájlját sajátjának tekinti és törli, még olvasónak látszó API-ból is

**Hely:** `analysis_cache.dart:169-190` (`_readEntries` → `_discard` a
`FormatException` ágon), `analysis_cache.dart:193-198` (`_discard`).

**Failure scenario (mért, `p1_paths.dart` P3):** egy idegen könyvtárban létrehoztam
egy `index.json`-t (pontosan az R21 repository index-fájlneve,
`file_analysis_repository.dart:62`), majd ott nyitottam egy `AnalysisCache`-t és
meghívtam a **`entryCount()`**-ot — a *read-only nevű* API-t:

```
P3 foreign index exists     = true
P3 entryCount() on foreign  = 0
P3 foreign index after read = false      <-- törölve
```

Ma ez **nem elérhető**: a wiring két különböző konstanst használ
(`analysis_providers.dart:44`, `:74` vs `:43`, `:62`), a `purge()` pedig a saját
alkönyvtárában marad (a kör tesztje ezt igazolja is —
`analysis_cache_test.dart` „purging cache leaves saved analysis sessions untouched").
A kockázat mégis valós, mert az ADR Döntés 6 („cache és mentett dokumentum
élettartama független") garanciáját **kizárólag a wiring** hordozza, az osztály
maga nem: bármely jövőbeli hívó/teszt, amely egy megosztott könyvtárat ad át,
adatvesztést okoz. Növeli a felületet, hogy a kör az osztályt a **feature
public barrelbe is exportálja** (`public.dart:29-31`), így minden feature
elérheti.

**Javasolt irány:** a scan és a `_discard` csak a `^[0-9a-f]{64}\.json$` mintára
illeszkedő fájlokat vegye figyelembe (ez egyben a NOTE-1 symlink-élt is zárja),
plusz egy negatív teszt: idegen `.json` a könyvtárban túléli a `purge()`-öt.

### MINOR-3 — A fingerprint némán levágja a tartományon kívüli mintát → bizonyított ütközés (két különböző audio, azonos cache-kulcs)

**Hely:** `audio_fingerprint.dart:48-51` (`_quantize` → `sample.clamp(-1.0, 1.0)`).

**Failure scenario (mért, `p4_fingerprint.dart` 3.):**

```
[2.0, 3.5, -9.0]  -> 5ab92cd37c9461aebc444c56...
[1.0, 1.0, -1.0]  -> 5ab92cd37c9461aebc444c56...
out-of-range inputs collide = true
```

Két **különböző** minta-sorozat azonos fingerprintet, tehát azonos
`cacheId`-t ad → egy jövőbeli cache-hit **egy másik bemenet elemzési eredményét**
adhatja vissza, „biztos" eredményként (§5.5, gyenge/téves állítás biztosként).
A függvény nem-véges mintára **dob** (fail-closed), tartományon kívülire viszont
**némán csonkol** — ez az aszimmetria a lelet magja. A `[-1,1]` előfeltételt csak
a doc-comment („normalized PCM") rögzíti, kód nem kényszeríti; float32 WAV
bemenet legitim módon meghaladhatja az ±1.0-t.

Ma nem elérhető (nincs hívó). **Javasolt irány:** `throw ArgumentError` a
tartományon kívüli mintára (a `!isFinite` ág mintájára), vagy a clamping
explicit szerződésbe emelése az ADR Döntés 2-ben.

### MINOR-4 — `put()` / `getOrCompute()` kivételt propagál a hívónak, az ADR Döntés 5 záró tagmondatával szemben

**Hely:** `analysis_cache.dart:92` (`fileFor(key).writeAsString(...)` try nélkül),
`analysis_cache.dart:113-122` (`getOrCompute` → `put`).

**Failure scenario (mért, `p5_contract.dart`; a cache-könyvtár `chmod 500`,
azaz „megtelt lemez / írásjog nincs" modell):**

```
put()          -> THREW PathAccessException: ... (OS Error: Permission denied, errno = 13)
getOrCompute() -> THREW PathAccessException: ...
```

A `getOrCompute()` esetében a `compute()` **már sikeresen lefutott** — a hívó
mégis kivételt kap az eredmény helyett, azaz egy egyébként sikeres elemzés
bukik el egy cache-írási hibán. ADR 0248 Döntés 5 záró tagmondata: „a cache
**soha** nem propagál kivételt a hívó felé". (Mérlegelve: a Döntés 5 címe a
*sérült bejegyzésre* szűkít, ezért a szöveg olvasata vitatható — emiatt MINOR,
nem MAJOR; a `get()` ág egyébként helyesen fail-safe.) Kapcsolódó él ugyanitt:
a `get()` egyetlen `try`-ba fogja az olvasást ÉS a hozzáférés-idő visszaírását,
így egy írási hiba a `_discard`-on át egy **érvényes** bejegyzést töröl.
Mellékesen a propagált üzenet a teljes abszolút app-privát útvonalat tartalmazza
(tartalmat nem — a fájlnév hash).

**Javasolt irány:** a `put()` írása és az `_evictToLimits` `try/catch (FileSystemException)`-be;
a `getOrCompute()` a kiszámolt értéket akkor is adja vissza, ha a perzisztálás nem sikerült.

### MINOR-5 — `AudioFingerprint.compute()` ~12× tranziens memóriát allokál a bemenet PCM-méretéhez képest

**Hely:** `audio_fingerprint.dart:41-45` — `crypto.sha256.convert(<int>[...header, ...versionBytes, ...pcm])`
egy **boxolt `List<int>`-be** másolja a teljes PCM-et (64 biten 8 bájt/elem),
a `ByteData` mellé.

**Failure scenario (mért, `p2_cost.dart` A):**

```
 2 s mono (  88 200 minta, 0.2 MiB pcm):   45 ms, rss 178.3 -> 180.6 MiB
30 s mono (1 323 000 minta, 2.5 MiB pcm):  208 ms, rss 195.9 -> 252.4 MiB
180 s mono (7 938 000 minta, 15.1 MiB pcm): 1040 ms, rss 425.1 -> 612.4 MiB
```

Egy 3 perces mono klip fingerprintje **~187 MiB tranziens heapet** és ~1 s CPU-t
kér. Ez pont az a függvény, amelyet az ADR minden elemzési futás
cache-kulcs-bemenetének jelöl ki, és a bemeneti hossz importált fájlból
felhasználó-vezérelt (a WAV-kapu 64 MiB-ig enged). Közepes Android eszközön ez
OOM-kockázat. Ma nem elérhető (nincs hívó).

**Javasolt irány:** `startChunkedConversion` / `Uint8List`-alapú inkrementális
hash (a `ByteData` pufferek közvetlen átadása másolás nélkül).

---

### NOTE-1 — symlink-aszimmetria: a scan nem követi, a `put()`/`get()` igen

`_readEntries` helyesen `directory.list(followLinks: false)`-t használ — mérve
(`p1` P2): egy `aaaa.json` néven elhelyezett, kifelé mutató symlinket kihagy, a
külső fájl sértetlen. A `fileFor()` viszont nem ellenőrzi a link-mivoltot, ezért
egy **pontosan `<cacheId>.json` néven előre elhelyezett symlinken az írás
átmegy** — mérve (`p3` vége): a `victim.txt` tartalma a cache-bejegyzés JSON-ja
lett (`victim is now a cache entry? true`). Előfeltétel: a támadó már tud írni az
app-privát tárolóba (root) — ezért **hardening**, nem kihasználható út. A
MINOR-2 javasolt fájlnév-mintaszűrője ezt is zárja.

### NOTE-2 — a byte-cap csak az írás UTÁN érvényesül

`put()` előbb kiír, majd `_evictToLimits`-t hív; per-bejegyzés méretellenőrzés
nincs. Mérve (`p1` P4): 1 KiB-os cap-be írt 8 MiB payload → **10,7 MiB tranziens
fájl** a lemezen, majd 0 bejegyzés. A kör tesztje ezt a viselkedést rögzíti is
(„byte cap ... one above the cap"). Alacsony tárhelyű eszközön egy nagy payload
átmenetileg megtöltheti a lemezt, mielőtt kilakoltatásra kerülne.

### NOTE-3 — a payload tartalmi politikája teljes egészében a jövőbeli hívóé + a hely backup-jogosult

`put(key, Uint8List payload)` semmilyen tartalmi korlátozást nem kényszerít, így
az SDD Ch7 §23.2 tiltólistájának (auth token, érzékeny diagnosztika) betartása a
majdani hívón múlik. **Ma nincs hívó → nem BLOCKER**, de a bekötő körnek explicit
szerződést kell adnia (mit szabad cache-elni; nyers PCM-et semmiképp).
Hely-kockázat: `getApplicationSupportDirectory()` Androidon `context.filesDir`
(igazolva: `path_provider_android-2.3.1/lib/src/path_provider_android_real.dart:28-33`),
a manifest pedig se `android:allowBackup="false"`-t, se `dataExtractionRules`-t,
se `fullBackupContent`-et nem állít → a derived cache tartalma **Android Auto
Backup-jogosult** (felhő). Egy cache helye ezért inkább `getTemporaryDirectory()`
(`cacheDir`, backupból kizárt) vagy backup-kizárási szabály lenne. Ma a könyvtár
üres, sőt létre sem jön (nincs provider-fogyasztó).

### NOTE-4 — a „hat komponens együttesen kötelező" 4/6-ra van kikényszerítve

`analysis_cache_key.dart:23-38`: a négy String komponensre van üresség-ellenőrzés,
de `modelManifestIds: []` és `featureFlagSnapshot: {}` elfogadott. Mérve (`p3`):
két kulcs **üres flag-snapshottal azonos**, függetlenül a tényleges futásidejű
flag-állapottól (`true`). Az egyetlen mai production provenance-előállító
(`legacy_analyze_adapter.dart:110-118`) pontosan üres `modelManifestIds`-t és üres
`featureFlagSnapshot`-ot ad. Ha egy jövőbeli kör ilyen provenance-ból épít kulcsot,
az ADR Döntés 1 „bármelyik komponens változása = miss" garanciája elvész a flag-
és modell-dimenzióban (stale eredmény más flag-állapot alatt).

### NOTE-5 — teszt-őrök rigora (az adatvédelmi állítást igazoló teszt tautológia)

`test/features/audio_analysis/data/audio_fingerprint_test.dart` „content
fingerprint has no filename input" **kétszer ugyanazokkal az argumentumokkal**
hívja a `compute()`-ot és egyenlőséget vár — ez szó szerint a determinizmus-teszt
másolata, **soha nem tud pirosra váltani**, tehát a nevében szereplő adatvédelmi
tulajdonságot nem bizonyítja (a tulajdonság igaz, de az API-alakból, nem ebből a
tesztből). Hiányzó negatív őrök ugyanitt: (a) semmi nem rögzíti a **`cacheId`**
hex-karakterkészletét (a tényleges fájlnevet — a fingerprintre van ilyen assert,
a kulcsra nincs); (b) nincs traversal-teszt (`../` komponensű kulcs → a fájl a
cache-könyvtárban marad); (c) nincs teszt arra, hogy `sampleRate`/`channelCount`/
`preprocessingVersion` változása más digestet ad (mérve: mindhárom részt vesz —
egy regresszió, amely elhagyja a fejlécet, zölden átmenne).

---

## 4. Amit végignéztem és NEM találtam leletet (az üres jelentés is bizonyíték)

- **N0 — Bekötetlenség.** `grep -rn "analysisCacheBootProvider|analysisCacheProvider|analysisCacheProductionRootResolverProvider|analysisCacheClockProvider|analysisCacheStorageKey|analysisCacheRootDirectoryName" lib/ test/ tool/` a definíciós fájlon kívül **0 találat**. A cache-könyvtár futásidőben létre sem jön. Az `analysisCacheProvider` alapértelmezésben `StateError`-t dob (fail-closed override-pont).
- **Path traversal (2. pont).** `p1_paths.dart`: a `../../../../../../etc/passwd`,
  `..\..\windows`, `/absolute/evil`, `\n../..\r`, `%2e%2e%2fetc`, `a/../b`
  komponensekből álló kulcs `cacheId`-je `d8a96005…3977` (64 hex), a fájl a
  `<tmp>/analysis_cache/` alatt maradt, a teljes temp-fa két bejegyzést tartalmazott.
  1000 randomizált ellenséges kulcson **0 nem-hex** `cacheId`. A védelem szerkezeti:
  a fájlnév a `sha256(kanonikus JSON)` hexje, nem a nyers komponens.
- **Titok/log/diagnosztika.** A négy új fájlban nincs `print`, `log`, `debugPrint`,
  analytics, `SecureStore`, `KeyValueStore`, `Dio`, `http`. A hibaüzenetek csak
  konfigurációs értéket (`maxEntries`, `preprocessingVersion`, manifest-ID lista)
  vagy a szabálytalan skalárt (`NaN`) tartalmazzák — audio-mintát, tokent nem.
- **`storage_keys.dart` (5. pont).** Kizárólag hozzáadás: `analysisCache = 'ss.analysis.cache'`
  + egy sor az `all` listában. Nincs átnevezés/törlés → meglévő installon nincs
  adatvesztés. A guard-teszt (`test/core/storage/key_value_store_test.dart:192-201`)
  változatlanul kikényszeríti az egyediséget, az `ss.` névteret és azt, hogy a
  `secureAuthToken` **ne** legyen a listában — a kör ezt nem sértette.
- **Ellátási lánc.** Új dependency nincs: a `crypto: ^3.0.7` már közvetlen függőség
  (`pubspec.yaml:46`) és 14 helyen használt. Új asset nincs.
- **Prompt injection / külső tartalom.** A kör nem érint AI-providert, tudásbázist,
  tool-callingot, importált zenei fájlt. A cache saját JSON-jának dekódolása
  fail-closed (típusonkénti ellenőrzés + `FormatException`/`FileSystemException`
  → miss), és a `get()` ellenőrzi, hogy a fájlban tárolt `cacheId` egyezik-e a
  kért kulccsal (bejegyzés-csere elleni kötés).
- **Engedélyek.** `AndroidManifest.xml` nincs a diffben; új platform-permission nincs.
- **R27-port (7. pont).** `delete_analysis_use_case.dart` nincs a diffben; az
  `AnalysisCache` nem `implements AnalysisCachePort`, adapter nem készült — a brief
  §0.0 és az ADR Döntés 9 állítása pontos.

---

## 5. Scope-audit (biztonsági szemmel)

A 15 megváltozott fájl mind az ai-router `allowed_paths` listáján van. Listán
kívüli változás: **nincs**. Külön ellenőrizve: a V1 `lib/features/analyze/**`
tiltott zóna érintetlen; a feature-flag fájl érintetlen; a manifest érintetlen.

## 6. Kötelező előfeltételek a bekötő (wiring) körnek

Ez a kör mergelhető, de a következő kör, amely a cache-t **élesbe köti**, ne
induljon ezek lezárása nélkül:

1. Explicit, ADR-be írt szerződés arról, **mit szabad** a cache-be tenni — nyers
   PCM/audio semmiképp (NOTE-3), és a hely újraértékelése backup-jogosultság
   szempontjából (`cacheDir` vagy backup-kizárás).
2. MINOR-4 lezárása: a cache ne dobjon a hívóra (`put`/`getOrCompute`).
3. MINOR-2 lezárása: fájlnév-mintaszűrő a scanben/`_discard`-ban (egyben NOTE-1).
4. MINOR-3 lezárása: tartományon kívüli minta elutasítása vagy a clamping
   szerződésbe emelése — különben egy cache-hit idegen bemenet eredményét adhatja.
5. MINOR-1/MINOR-5 újramérése a cap közeli payloadmérettel és valós klip-hosszal,
   **mielőtt** bárki a jelenlegi baseline-számokra budget-döntést épít.
6. A cache-purge bekötése a törlési útvonalba (`AnalysisCachePort` adapter),
   hogy a `ss.analysis.cache` katalógus-bejegyzés valódi törölhetőséget takarjon.

## 7. Reprodukció

A mérések izolált klónon, tiszta Dart VM-mel futnak (Flutter nem kell):

```bash
dart run --packages=/tmp/review-e06-r28/.dart_tool/package_config.json \
  /tmp/r28probe/p1_paths.dart        # path traversal, symlink-scan, idegen index.json, cap-utáni írás
dart run --packages=... /tmp/r28probe/p2_cost.dart          # fingerprint- és put/get-költség
dart run --packages=... /tmp/r28probe/p3_lru_memory.dart    # 50 MiB cap, degenerált kulcs, symlink-átírás
dart run --packages=... /tmp/r28probe/p4_fingerprint.dart   # fejléc, ütközés, preimage-határ
dart run --packages=... /tmp/r28probe/p5_contract.dart      # kivétel-propagáció (chmod 500)
```
