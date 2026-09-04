# E14-R03 — kör-review (ADR 0055)

- **Reviewer:** Claude Opus 5 (orchestrátor, read-only review)
- **Implementer:** Claude Sonnet 5 (`sonnet-impl`)
- **Ág:** `sonnet-impl/e14-r03-model-activation-telemetry`
- **Review-alap:** `a143e603` (pre-flight) → `9da47c0a` (a kör csúcsa)
- **Brief:** `docs/rounds/e14-r03-model-activation-telemetry.md` (§0.0 R1–R12)
- **ADR:** `docs/adr/0355-fail-visible-model-activation-telemetry.md`
- **Biztonsági review** (`risk = "high"`, AGENTS.md §15.1):
  `docs/reviews/e14-r03-security.md` — **CLEAN** (0 CRITICAL/BLOCKER/MAJOR)

## 1. VERDIKT

**APPROVED** (a fix1 után — a §9 a végső döntés).

*Első kör verdiktje: CHANGES REQUESTED* — 0 BLOCKER, 0 MAJOR, **4 MINOR**, 4 NOTE.

A kör tartalmi magja helyes és MÉRVE van (lásd §3–§4). A négy MINOR egyetlen,
koherens hibaosztály: a `strumModelId` **dokumentált szerződése ma nem igaz és
nincs kipinnelve**. Mivel a kör tétje épp egy adatvédelmi-megfigyelhetőségi
szerződés (`risk = "high"`), és a javítás ~10 sor a MÁR engedélyezett
fájlokban, egy szűk javító kör indul; a merge bar (BLOCKER/MAJOR = 0)
ettől függetlenül teljesül.

## 2. Kötelező ellenőrzések (mérve, nem bemondásra)

### 2.1 Jelzés + handoff

```
status=done
branch=sonnet-impl/e14-r03-model-activation-telemetry
head=9da47c0a
dirty_files=1
```

A `dirty_files=1` **kivizsgálva** (a prompt §3 kötelező ellenőrzése): a jelzés
kiírásának pillanatában a `.codex-round-status` maga volt a piszkos fájl; a
`git status --short` közvetlenül utána ÜRES, tehát a kör diffje hiánytalanul
commitolva van. Nem veszett el munka.

A §10 handoff nem bemondás: konkrét falszifikációs mutációt (`crnnActivation.model`
→ `crnnActivation.model!`) és a hozzá tartozó 4 bukott cellát dokumentálja.

### 2.2 Scope-audit (ADR 0138)

A jelzésfájl nem hordozott `scope_audit=` kulcsot → **nem bizonyíték**, ezért
kézzel futtatva:

```
$ python3 tools/scope-audit.py --repo /home/ubuntu/ss-sonnet-impl-e14-r03 \
    --brief docs/rounds/e14-r03-model-activation-telemetry.md --base a143e603
Legacy scope audit OK (a143e603e988..9da47c0a8879, 9 changed path(s), 0 generated/ignored)
```

**OK** — a 9 érintett útvonal mind az `allowed_paths` listán van. Tilos zóna
érintetlen (`pubspec.yaml`, `assets/**`, `ml/**`, `real_strum_engine.dart`,
`strum_engine.dart`, `.github/**`, `tools/**`, `lib/core/feature_flags/**`).

### 2.3 Gate — ÚJRAFUTTATVA izolált `/tmp` klónban

```
$ git clone --branch sonnet-impl/e14-r03-model-activation-telemetry \
    /home/ubuntu/ss-sonnet-impl-e14-r03 /tmp/review-e14-r03
$ bash /tmp/review-e14-r03/tools/prepare-flutter-generated.sh      # exit 0
$ tools/round-gate.sh test/features/live/model_activation_test.dart \
    test/features/live/recognition_runtime_info_test.dart test/features/live
```

Kilépési kód: **0**. Összegzés (csonkítatlan, saját futás):

```
format                                                     zöld
analyze                                                    zöld
test test/features/live/model_activation_test.dart         zöld
test test/features/live/recognition_runtime_info_test.dart zöld
test test/features/live                                    zöld
architecture                                               zöld
secrets                                                    zöld   (4303 fájl, 0 lelet)
l10n                                                       zöld   (en→hu, 2304 üzenet)
```

## 3. Próbatesztek (eldobhatók, merge előtt törölve)

### 3.1 Legacy-referencia paritás — a kör KÖZPONTI ígérete, bitre mérve

A §5.1 / 3. acceptance-pont („a fallback VISELKEDÉSE bitre marad") a kör saját
cellájában csak gyengén van mérve (`frames.any((f) => f.latestStrum != null)`).
Ezért írtam egy eldobható próbát, amely a `LivePipeline` **teljes frame-sorát**
ujjlenyomatolja (chord label, irány, konfidencia 9 tizedesig, bpm, inputLevel,
strumSeq, latestStrumTime, engineTimeSec, tuningHz, listening, a teljes 8 slotos
bar), három súly-úton (nincs súly / szemét súly / valódi `strum_crnn_live_3c.bin`),
két egymást átfedő strumból álló jelen — és lefuttattam a **tiszta `main`**
klónon (`4f293403`) ÉS a kör-ágon:

```
$ sha256sum /tmp/probe-main.txt /tmp/probe-round.txt
bd90fdc0c8e1dbf748cb3c7ad4c5cb7d67ca9573a3a5127dce26d083aeb2b414  /tmp/probe-main.txt
bd90fdc0c8e1dbf748cb3c7ad4c5cb7d67ca9573a3a5127dce26d083aeb2b414  /tmp/probe-round.txt
$ diff /tmp/probe-main.txt /tmp/probe-round.txt   # exit 0
```

**63 frame, bitre azonos.** A viselkedés-változatlanság így MÉRT tény, nem
állítás. (Próbafájl: `test/features/probe_frame_parity_test.dart`, mindkét
klónban törölve.)

### 3.2 Valódi-sértés próba a redakciós kanárira (L260)

A kanári-cella csak akkor mérce, ha egy tényleges ÉRTÉK-oldali szivárgást
pirosra visz. Ideiglenesen az `assetMissing` ágat úgy írtam át, hogy
`strumModelId: path`-t adjon:

```
00:00 +11 -1: 4. redaction canary — ... [E]
  Expected: false
    Actual: <true>
  test/features/live/model_activation_test.dart 194:7
```

**PIROS**, pontosan a kanárin. Visszaállítva zöld. A cella tehát valódi őr —
nem a L260-ban mért, konstrukció szerint mindig igaz alak.

### 3.3 Valódi-sértés próba a 6. acceptance-pontra (additív barrel)

A 6.1 mátrix „a meglévő export eltűnésének cellája" sorához nincs dedikált
teszt, ezért megmértem, mi fogja meg. A `public.dart`-ból kivettem egy
KORÁBBI exportot (`export 'model/live_frame.dart';`):

```
$ flutter analyze lib/
error • Undefined class 'LiveFrame' • lib/features/practice/data/live_practice_observation_gateway.dart:202:21
error • The name 'LiveFrame' isn't a type ... :45:22
error • Undefined class 'LiveFrame' • :255:5
3 issues found.
```

A 6. pont tehát **a kör SAJÁT kapujának 2. lépésében** (analyze) mechanikusan
őrzött — nem csak a teljes CI-ban. Visszaállítva. Az új export oldalát a
`recognition_runtime_info_test.dart` fedi, amely szándékosan KIZÁRÓLAG a
barrelen keresztül importál, tehát hiányzó export esetén nem fordul le.

## 4. Acceptance criteria — tételesen

| # | Kritérium | Bizonyíték | Verdikt |
|---|---|---|---|
| 1 | valós asset → `activated`, 3 osztály, mért id/hash | `model_activation_test.dart:23-36` — `nClasses == 3`, `strumModelId == 'strum_crnn_live_3c.bin'`, `strumModelSha256` a TESZTBEN újraszámolt `crypto.sha256`-tal egyezik, `strumModelVersion == 1`, `fallbackReason == null` | ✅ |
| 2 | mind az 5 hibakódra cella, stabil kód | `:56-129` — `assetMissing` (nem létező fájl), `assetUnreadable` (könyvtár), `parseFailed` ×2 (rossz magic ÉS rossz verzió), `shapeMismatch` (ép fejléc + nullázott tömbszám), `disabledByFlag` (gyártófüggvény) | ✅ |
| 3 | fallback esetén a pipeline TOVÁBBRA IS verdiktet ad | `:132-177` + a §3.1 legacy-paritás próba (63 frame bitre azonos) + a §10 falszifikáció (4 cella PIROS a rontással) | ✅ |
| 4 | JSON round-trip, nincs abszolút út / token / audio | `recognition_runtime_info_test.dart:35-57` + `model_activation_test.dart:179-201` kanári + a §3.2 valódi-sértés próba | ✅ (MINOR-2 réssel) |
| 5 | `LiveLabState` hordozza; activated ≠ fallback | `recognition_runtime_info_test.dart:82-129` — alapállapot `null`, `reportRuntimeInfo` megkülönböztet, `null`-ra visszaállít | ✅ |
| 6 | `public.dart` additív, meglévő export nem tűnik el | diff: +1 export, −0; a §3.3 valódi-sértés próba szerint az `analyze` lépés fogja meg | ✅ |

## 5. Leletek

### MINOR-1 — a `strumModelId` doc-szerződése nem igaz a live úton

`lib/features/live/model/recognition_runtime_info.dart:82-84`:

> „The activated model's asset FILENAME only — no directory, never a full
> path — or `'none'` while [fallbackReason] is set."

A live (izolátum) úton az érték `'live-crnn'`
(`lib/features/live/engine/dsp/live_pipeline.dart:41`) — **aktivált** állapotban,
tehát sem fájlnév, sem `'none'`. A §10 handoff ezt kimondja, de a doc-comment
maga hamis állítást tesz, amit teszt nem cáfol. A kör-prompt §5 előírása: „a
doc-commentbe csak tesztben bizonyított állítás kerülhet".

**Javasolt irány:** a `strumModelId` doc-comment mondja ki a harmadik,
legális alakot (izolátum-határon átjövő bájtok → nevesített konstans, pl.
`RecognitionRuntimeInfo.isolateLiveModelId = 'live-crnn'`), és a
`live_pipeline.dart` erre a konstansra hivatkozzon a sztring-literál helyett.

### MINOR-2 — a kanári nem éri el az út-származtatást (a security review S2-je)

`test/features/live/model_activation_test.dart:179-201`: a kanári egy NEM LÉTEZŐ
fájlt aktivál, ezért a `strum_crnn.dart:43-50` `PathNotFoundException` ágon tér
vissza — a `:61-65` `modelId: path.split('/').last` **le sem fut**. Az
`expect(result.info.strumModelId, 'none')` így konstrukció szerint igaz: ez
maga a L260 hibaosztálya, csak egy szinttel beljebb.

**Javasolt irány:** egy második kanári-cella, amely SIKERES aktiváláson méri az
alapnév-vágást — a valódi assetet egy egyedi szegmensű temp-könyvtárba másolva
aktiválja, és azt méri, hogy a `toString()`/`toJson()` értékei sem a
temp-szegmenst, sem a könyvtár-részt nem tartalmazzák (csak a fájlnevet).

### MINOR-3 — az alapnév-vágás elválasztó-függő (a security review S1-e)

`lib/features/live/engine/ml/strum_crnn.dart:63` — `path.split('/').last`.
Mérve:

```
$ python3 -c "p=r'C:\Users\Kovacs Csaba\models\m.bin'; print(p.split('/')[-1])"
C:\Users\Kovacs Csaba\models\m.bin
```

A TELJES út átmegy a `strumModelId`-be, szemben a mező saját „never a full
path" szerződésével. Ma **elérhetetlen** production hívási útról (a security
review mérése: `lib/` alól nulla hívó, minden hívás teszt/tool fix relatív
asset-úttal), ezért MINOR és nem MAJOR — de a szerződést a kód nem tartja.

**Javasolt irány:** mindkét elválasztóra vágni (`split(RegExp(r'[\\/]')).last`),
és a MINOR-2 cellájával kipinnelni.

### MINOR-4 — a `ModelActivation` invariánsai csak `assert`-tel élnek

`lib/features/live/engine/ml/model_activation.dart:16-19, 28-31`: release
buildben az `assert` eltűnik, tehát előállítható `activated(model, fallbackInfo)`
(`isActivated == true` **és** `fallbackReason != null`), illetve
`fallback(assetMissing, parseFailedInfo)` — utóbbi MÁS kódot közöl, mint amit
kértek. Ez az `ADR 0271` `UNKNOWN > CONFIDENTLY WRONG` elvével feszül.

Ma minden konstrukciós hely feature-en belüli és konzisztens, a típus nincs a
`public.dart` barrelben — ezért MINOR.

**Javasolt irány:** a `fallback` gyártófüggvény SZÁRMAZTASSA az infót a
`reason`-ból (ne fogadjon el eltérőt), vagy az `isActivated` a `model != null &&
info.fallbackReason == null` konjunkcióra épüljön, hogy a hazug pár ne
állhasson elő release-ben sem.

## 6. NOTE-ok (nem blokkolnak, nem kérnek javítást)

- **NOTE-1 — perf (§9):** a `crypto.sha256` az 1,46 MB-os asseten
  konstrukciónként EGYSZER fut, a `LivePipeline` `factory` konstruktorában; a
  per-frame útvonalra semmi nem került. A `clip_analyzer.dart:115` súly NÉLKÜL
  konstruál, tehát az Analyze utat nem terheli. A §3.1 paritás-próba szerint a
  kimenet változatlan. A §9 „ha CPU-növekedést mutat, az blokkoló" kikötése
  teljesül.
- **NOTE-2 — a `disabledByFlag`-nek és a `reportRuntimeInfo`-nak nincs
  production hívója.** Szándékos és a briefben (R3/R8) előre kimondott
  halasztás az `E14-R04`-re; a §10 „Amit szándékosan NEM tettünk meg" fel is
  sorolja. A kör mérhető része (típus + kód + állapot) él és tesztelt.
- **NOTE-3 — `live_pipeline.dart` most tranzitíven `dart:io`-t húz** (a
  `strum_crnn.dart`-on át). Az `architecture` gate zöld, az Analyze út már
  korábban is így importálta a `strum_crnn.dart`-ot; mobil célon nincs
  következménye.
- **NOTE-4 — a `fromJson` `Error`-t dob** hibás alaknál (`byName`,
  `as` cast), nem `Exception`-t. Egy `on Exception` őrből kiszökne. Ma nincs
  külső JSON-forrása.

## 7. Merge-előfeltételek állapota a jelentés írásakor

- Gate (saját, izolált futás): **zöld**, exit 0.
- Scope-audit: **OK**.
- Biztonsági review (`risk = "high"`): **CLEAN**.
- Full Gate CI + Router CI a merge SHA-n: a javító kör utáni SHA-n
  ÚJRA dispatch-elve — a merge kizárólag az akkori exact-SHA zöldön történhet
  (ADR 0086 §2).

## 8. Javító kör (fix1) után — leletenkénti zárás

**Javító commit:** `a866a3d7` — „E14-R03 fix1: strumModelId contract +
ModelActivation invariants (4 MINOR)". Motor: ugyanaz (`sonnet-impl`).
Scope-audit a javításra:

```
$ python3 tools/scope-audit.py --repo /home/ubuntu/ss-sonnet-impl-e14-r03 \
    --brief docs/rounds/e14-r03-model-activation-telemetry.md --base 804568cc
Legacy scope audit OK (804568ccf1ed..a866a3d7632d, 6 changed path(s), 0 generated/ignored)
```

| Lelet | Zárás | Van-e teszt, ami a HIBÁT pirosra fogta volna |
|---|---|---|
| MINOR-1 | `recognition_runtime_info.dart:82-90` — a doc-comment mind a HÁROM legális alakot felsorolja, és új nevesített konstans: `isolateLiveModelId = 'live-crnn'`; a `live_pipeline.dart:44` erre hivatkozik a sztring-literál helyett | igen — a live-út `strumModelId`-jét mostantól cella pinneli a konstanshoz |
| MINOR-2 | ÚJ kanári a SIKERES aktiválási úton: a valódi asset egyedi szegmensű temp-könyvtárba másolva, onnan aktiválva; a cella az út-származtatást TÉNYLEGESEN lefuttatja | igen — a régi kanári a `PathNotFoundException` ágon tért vissza, az újat a `path.split` viselkedése dönti el |
| MINOR-3 | `strum_crnn.dart:61` — `path.split(RegExp(r'[\\/]')).last`, elválasztó-független | igen — szintetikus Windows-alakú úton mért cella |
| MINOR-4 | `model_activation.dart` — az `assert`-ek **valódi `throw`-ra** cserélve (`ArgumentError.value`), az `isActivated` a `model != null && info.fallbackReason == null` **konjunkcióra** épül, és a `fallback` gyártófüggvényből **eltűnt a külön `reason` paraméter** (az `info` az egyetlen igazságforrás, tehát a „hazug pár" már szerkezetileg sem állítható elő) | igen — a hazug párt mérő cellák release-szemantikával is fognak |

A MINOR-4 zárása **erősebb**, mint amit a review javasolt: a redundáns `reason`
paraméter megszüntetésével a divergencia nem „ellenőrzött", hanem
**megfogalmazhatatlan** lett. A hozzá tartozó hívói egyszerűsítés
(`strum_crnn.dart` ×4, `live_pipeline.dart` ×2) tisztán mechanikus.

### 8.1 Upstream-szinkron (§0.3) — a `main` KÖZBEN mozdult

A javítás közben az `E14-R02` landolt (`478a2f64`), tehát a kör-ág már nem
tartalmazta az aktuális `origin/main`-t:

```
$ git merge-base --is-ancestor origin/main HEAD   # NO
$ git merge --no-ff origin/main                   # konfliktus NÉLKÜL
$ git diff --check                                # tiszta
$ git merge-base --is-ancestor origin/main HEAD   # YES
```

A két kör fájlhalmaza mérten diszjunkt volt (R12), ezért a merge mechanikus.
Publikus ág-történet nem íródott át, force-push nem történt.

### 8.2 A gate és a paritás ÚJRAMÉRVE a KOMBINÁLT HEAD-en (`cc911fb5`)

Friss izolált klón a merge utáni ágról, `prepare-flutter-generated.sh` után:

```
$ tools/round-gate.sh test/features/live/model_activation_test.dart \
    test/features/live/recognition_runtime_info_test.dart test/features/live
```

Kilépési kód **0**:

```
format                                                     zöld
analyze                                                    zöld
test test/features/live/model_activation_test.dart         zöld
test test/features/live/recognition_runtime_info_test.dart zöld
test test/features/live                                    zöld
architecture                                               zöld
secrets                                                    zöld
l10n                                                       zöld
```

A §3.1 legacy-paritás próba **újrafuttatva** ugyanazon a `main`-referencián
(`/tmp/probe-main.txt`, `4f293403`):

```
$ diff /tmp/probe-main.txt /tmp/probe-round2.txt   # exit 0
bd90fdc0c8e1dbf748cb3c7ad4c5cb7d67ca9573a3a5127dce26d083aeb2b414  /tmp/probe-main.txt
bd90fdc0c8e1dbf748cb3c7ad4c5cb7d67ca9573a3a5127dce26d083aeb2b414  /tmp/probe-round2.txt
```

**A fix1 sem mozdította el a fallback viselkedését** — 63 frame, három
súly-úton, bitre azonos. Mindkét próbaklón tiszta állapotban maradt, a
próbafájl törölve.

### 8.3 Összegzés

| Mérés | Eredmény |
|---|---|
| `tools/round-gate.sh` (izolált klón, `cc911fb5`) | **zöld**, exit 0 |
| legacy-paritás (`main` ↔ kör-ág, 3 súly-út, 63 frame) | **bitre azonos** |
| scope-audit (implementáció + fix1) | **OK**, 0 listán kívüli útvonal |
| biztonsági review (`risk = "high"`) | **CLEAN** — a fix1 az S1/S2/S3-at is zárja |
| BLOCKER / MAJOR | **0 / 0** |
| MINOR | 4 → **mind zárva** (fix1, `a866a3d7`) |

## 9. VÉGSŐ DÖNTÉS: **APPROVED**

Nincs nyitott BLOCKER, MAJOR vagy MINOR lelet. A kör a mérce minden elemét
teljesíti, és a központi ígéretét (a fallback viselkedése bitre változatlan)
NEM állítja, hanem **méri** a legacy referenciával szemben.

A merge feltétele változatlanul a **zöld kapu az exact merge SHA-n**: Full Gate
+ Router CI `success` — ez a jelentés a kód-oldali mércéről szól, a CI-oldalit
nem helyettesíti (ADR 0086 §2).

### 9.1 Átadás a következő körnek (`E14-R04`)

A kör kimondottan elhalasztott két bekötést, mindkettőt az `E14-R04` scope-jába:

1. **Izolátum → Lab átvitel.** A `LivePipeline.runtimeInfo` és a
   `LiveLabController.reportRuntimeInfo` létezik és tesztelt, de production
   hívó nincs — a `real_strum_engine.dart` / `strum_engine.dart` ennek a
   körnek tilos zónája volt (R3).
2. **A live `strumModelId` valódi asset-neve.** Ma a nevesített
   `RecognitionRuntimeInfo.isolateLiveModelId` konstans megy át, mert az
   izolátum-határ csak bájtokat hordoz; a 2 és 3 osztályos live asset így ma
   nem különböztethető meg id alapján (a `strumModelSha256` viszont igen).
3. **A `disabledByFlag` flag-olvasása** (`lib/core/feature_flags/**`, R8).
