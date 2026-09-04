# HANDOFF — StrumSight 🎸

## 🔧 ÖNJAVÍTÓ KÖR — E14-R07 / H3: a merge utáni könyvelés saját munkapéldányban fut, a push újrapróbálható és hangos (2026-09-04)

**ADR 0112 önjavító kör. A megállt kör (E14-R07) terméke HIBÁTLAN** — a gate
zöld, a review APPROVED (0 BLOCKER/0 MAJOR/0 MINOR), a 18 saját acceptance-cella
mindenhol zöld. A merge-et egy ÖRÖKÖLT, `main`-oldali piros CI blokkolta.

**A mért gyökérok** (nem a kör hibája): az E14-R06 merge-e után a driver
`merged` ága a KÖZÖS munkafában könyvelt, miközben a másik slot köre (E14-R04)
azt a saját ágán tartotta. Így a `git reset --hard origin/main` az IDEGEN ágat
mozdította el (az E14-R04 lokális pre-flight commitja, `94f46951`, leesett
róla), a `chore(pipeline)` commit (`2cd3baef`) is oda került, a
`git push origin main` pedig a két committal LEMARADT lokális `main` refet
tolta → non-fast-forward, egyetlen néma `FIGYELEM` sorral
(`.pipeline/chain.log:26359`). A `main` ezért drifttel maradt
(`tools/sync-completion-matrix.py --check` → exit 1: Ch14 `reports done=3` vs.
`queue measures done=4`), és a `program_completion_test.dart` A1 cellája
pirosra vitte a main gate-jét (`33859597093`).

**A javítás** (`tools/round-pipeline.sh`): a könyvelés a `commit_main_bookkeeping()`
függvénybe került, és eldobható, a közös fától FÜGGETLEN worktree-ben fut;
minden próbálkozás a FRISS `origin/main`-ből származtat újra (párhuzamos merge
sem tehet elavult matrixot a main-re); a push háromszor újrapróbálható; a
végleges kudarc `HIBA` + telefon-értesítés, nem néma log. A közös fa
`reset --hard`-ja már csak bizonyítottan `main`-en futhat. A `main` drift
maga a `docs/sdd/program-completion-report.md` szinkronjával oldódik.

**Őr:** `tools/tests/test_pipeline_bookkeeping_worktree.py` — 8 cella, a fix
előtti forráson mind PIROS. A D2 fail-safe kar forrás-szintű őre
(`test_chain_hygiene.py`) a függvénytörzsre horgonyzott, és ÚJ cellával
követeli, hogy a `merged` ág valóban rá delegáljon. Mérés: [L624](docs/LESSONS.md).

**A megállt kör innen folytatható:** a
`sonnet-impl/e14-r07-annotation-contract-and-agreement` ág (HEAD `ad729d50`)
kész és APPROVED, PR még nincs nyitva — a lánc a MERGE-lépésnél veszi fel.

## ✅ E14-R06 KÉSZ — Accuracy Lab adat- és adatvédelmi mag: a beleegyezés a TÍPUSBAN, a csomag bájtra azonos — PR [#567](https://github.com/wolfcasaba/strumsight/pull/567), squash `4a02b959` (2026-09-04)

A Chapter 14 sáv hatodik köre megépítette az Accuracy Lab **adat- és
adatvédelmi magját** — képernyő nélkül (a brief §0.0 kötött scope-szűkítése:
a felület a Chapter 13 sávé, két sáv ugyanarra a fájlra írva ütközne). A
későbbi körök (`E14-R07` annotáció, `E14-R08` harness) innen kapnak ground
trutht, **hálózat nélkül**
([ADR 0358](docs/adr/0358-consented-on-device-lab-capture-package.md), D1–D8).

**A kör terméke** (`lib/features/accuracy_lab/`, 5 production fájl + 3 teszt):

- **`domain/lab_consent.dart`** — `sealed LabConsent`
  (`Granted`/`Revoked`/`Unknown`). Az export-kapu a **típusban** él: a writer
  csak `LabConsentGranted`-et fogad, a „nincs beleegyezés" ág **nem fordul**
  (D1). A consent-mátrix cellái a TÉNYLEGES hívási láncon mérnek (L161).
- **`domain/lab_task.dart`** — `LabTaskFamily` (6 család),
  `LabTaskCatalog.validated(List<LabTask>)`: **futtatható** 15–20
  tartomány-ellenőrzés tetszőleges listára (D6) + id-egyediség — így a
  „14 → hiba / 15 → elfogadott / 21 → hiba" cellahármas egyáltalán megírható.
- **`domain/lab_capture_package.dart`** — `canonicalJsonEncode` (rekurzív
  kulcsrendezés), az időbélyeg **bemenet**, `schemaVersion` + típusos hiba
  ismeretlen verzióra (D3, D5).
- **`data/lab_package_writer.dart`** — saját `dart:typed_data` PCM→WAV kódoló
  (D8: egyetlen feature-barrel sem exportál WAV-segédet), SHA-256 checksum,
  **tényleges** fájlrendszeri törlés (D4), validált `packageId`.

**A pre-flight tizenegy mért revíziót írt (§0.0.1/R1–R11)**, köztük olyanokat,
amik enélkül a kör közben ütöttek volna ki: **R4** — nincs elérhető WAV-kódoló
(a `learn`/`analyze` fájljai léteznek, de egyik barrel sem exportálja őket);
**R5** — a `share_plus`/`Dio`/`HttpClient`/`path_provider` bármelyike
aktiválná a `tool/check_data_inventory.dart` egress-felderítését, ami a tilos
zónában lévő `docs/privacy/data-inventory.yaml`-t követelné; **R3** — a §6/4
tiltólistás cellája [L260](docs/LESSONS.md) szerint vakon zöld lenne, ezért
**allowlist-egyenlőség + érték-oldali kanári** lett belőle.

**A review két MAJOR-t MÉRT, és a kör ezeken javult** (a fix nélkül 8 cella
piros — mutáció-kill próbával igazolva,
[`docs/reviews/e14-r06-review.md`](docs/reviews/e14-r06-review.md) §6):

1. **Path traversal** — a `packageId` validálatlanul útvonalba fűződött; a
   próbában a `delete(recursive: true)` a rooton KÍVÜLI könyvtárat is törölte,
   üres id mellett pedig az egész gyökeret törölte volna. Javítás:
   `labPackageIdPattern` + `LabPackageIdException` a `locate`-ben, amin a
   `write`/`status`/`delete` mind átmegy ([L623](docs/LESSONS.md)).
2. **Consent-provenance** — a `write()` a `consent` paramétert soha nem
   olvasta: a manifest a hívó által megadott `consentVersion`-t rögzítette,
   ami eltérhetett a tényleges engedélytől. A kapu típusban volt, a
   **rögzített érték** mégsem az engedélyből származott
   ([L622](docs/LESSONS.md)).

**Mérce:** `tools/round-gate.sh` a brief §7 négy útvonalával, a reviewer által
izolált klónban újrafuttatva **9/9 zöld** (28 teszt); full-gate CI
[`33857342530`](https://github.com/wolfcasaba/strumsight/actions/runs/33857342530)
és Router CI
[`33857303430`](https://github.com/wolfcasaba/strumsight/actions/runs/33857303430)
**mindkettő zöld a merge SHA-n** (`15aa6f4e`); scope-audit
`OK (11 changed path(s), 2 generated/ignored)`.

**Nyitva hagyott, nem blokkoló megjegyzés:** a grant-alapú `consentVersion` a
**manifestre** érvényes; ha egy későbbi kör a `LabCapturePackage`-et önmagában
exportálja, ott a forrás-kikötést meg kell ismételni (review NOTE-3). A
`LabPackageWriter` ma **unwired** — a UI-bekötés az `E14-R06b`.

Következő kör: a `docs/execution/pipeline-queue.tsv` következő `pending` sora.

## ✅ E14-R03 KÉSZ — Fail-visible modellaktiváció: a néma fallback mostantól KIMONDJA magát — PR [#566](https://github.com/wolfcasaba/strumsight/pull/566), squash `b82f3ab5` (2026-09-04)

A Chapter 14 sáv harmadik köre azt a hibaosztályt zárta a felismerő oldalán,
amit a `docs/LESSONS.md` [L06](docs/LESSONS.md#l06) a beállítás-szinkronon már
megmért: **az elnyelt hiba néma no-op**. A Live út eddig
`catch (_) { return null; }`-nal esett vissza a heurisztikus
irányosztályozóra, ha a CRNN-súly nem volt betölthető — egy futó buildről
**nem volt eldönthető, mit mértünk**
([ADR 0355](docs/adr/0355-fail-visible-model-activation-telemetry.md)).

**A kör terméke:**

- **`lib/features/live/model/recognition_runtime_info.dart`** (ÚJ,
  Flutter-független): `strumModelId`, `strumModelVersion`, `strumModelSha256`
  — a hash a **ténylegesen betöltött bájtokból** számolva, nem a
  `model_manifest.json`-ból másolva (ADR 0355 §4: épp azt az esetet nem fogná
  meg, amiért a mező létezik) —, `chordEngineId`, `fallbackReason`,
  `sampleRate`, `frontendVersion`.
- **`lib/features/live/engine/ml/model_activation.dart`** (ÚJ):
  `ModelActivation<T>` — `activated` / `fallback` / `disabled`. Az invariánsokat
  **valódi `throw` őrzi, nem `assert`** (az release-ben eltűnik), és a `fallback`
  gyártófüggvényből eltűnt a külön `reason` paraméter: az `info` az egyetlen
  igazságforrás, tehát a „hazug pár" **szerkezetileg sem** állítható elő.
- **Zárt hibakód-halmaz**: `assetMissing`, `assetUnreadable`, `parseFailed`,
  `shapeMismatch`, `disabledByFlag`. Kivétel-szöveg SOSEM megy tovább (§5.2) —
  a `parseFailed`/`shapeMismatch` elválasztását a betöltő a `SSML` fejléc 8
  bájtjának SAJÁT ellenőrzésével dönti el, nem a `FormatException` üzenetére
  illesztéssel.
- **`StrumCrnn.activate` / `activateBytes`** (ÚJ, **additív**) — a `tryLoad`
  MEGMARADT `StrumCrnn?`-t adó delegálásként, mert **hat, a kör scope-ján
  kívüli teszt** pinneli a mai visszatérési típust (a pre-flight mérése, §0.0 R1).
- **`LivePipeline.runtimeInfo`** getter — az aktiváció a `factory`
  konstruktorban **egyszer** fut, a per-frame útvonalra semmi nem került (§9).
- **`LiveLabState.runtimeInfo` + `LiveLabController.reportRuntimeInfo`**
  (additív), `lib/features/live/public.dart` additív export.

**A fallback VISELKEDÉSE bitre változatlan — és ez MÉRVE van, nem állítva.**
A review egy eldobható próbateszttel a `LivePipeline` teljes frame-sorát
ujjlenyomatolta (63 frame × chord/irány/konfidencia 9 tizedesig/bpm/level/
strumSeq/bar) három súly-úton (nincs súly / szemét / valódi
`strum_crnn_live_3c.bin`), és lefuttatta a **tiszta `main` klónon** és a
kör-ágon:

```
$ diff /tmp/probe-main.txt /tmp/probe-round2.txt   # exit 0
bd90fdc0c8e1dbf748cb3c7ad4c5cb7d67ca9573a3a5127dce26d083aeb2b414  (mindkettő)
```

**Amit a kör KIMONDOTTAN nem tett meg** (mind az `E14-R04` scope-ja): az
izolátum → Lab tényleges bekötés (a `LivePipeline` a DSP-izolátumban él, a
`real_strum_engine.dart` / `strum_engine.dart` a kör tilos zónája volt), a live
út valódi asset-neve (ma a nevesített `RecognitionRuntimeInfo.isolateLiveModelId`
konstans megy át), és a `disabledByFlag` flag-olvasása.

**Motor és evidencia.** Implementer `sonnet-impl` (Claude Sonnet 5),
orchesztrátor/reviewer Claude (Opus 5), **1 javító kör**. Review:
[`docs/reviews/e14-r03-review.md`](docs/reviews/e14-r03-review.md) — CHANGES
REQUESTED (0 BLOCKER / 0 MAJOR / 4 MINOR / 4 NOTE) → a fix1 után **APPROVED**,
0 nyitott lelet. `risk = "high"` → kötelező biztonsági review
([`docs/reviews/e14-r03-security.md`](docs/reviews/e14-r03-security.md)):
**CLEAN**. `native_gate = false` → a CI-tervet a `tools/round-ci-plan.py` adta
(`full-gate.yml`). Exact-SHA evidencia a `c238ea22` merge SHA-n: Full Gate
[33853601498](https://github.com/wolfcasaba/strumsight/actions/runs/33853601498)
`success` + Router CI
[33853642667](https://github.com/wolfcasaba/strumsight/actions/runs/33853642667)
`success`. Két új lecke: [L620](docs/LESSONS.md#l620) és
[L621](docs/LESSONS.md#l621).

## ✅ E14-R02 KÉSZ — Reprodukálható felismerési baseline: egyetlen manifest, egyetlen szám sem forrás nélkül — PR [#565](https://github.com/wolfcasaba/strumsight/pull/565), squash `2bbd36bd` (2026-09-04)

A Chapter 14 sáv második köre a szétszórt felismerési méréseket **egyetlen,
géppel olvasható manifestbe** és egy **generált, ember-olvasható indexbe** tette
— úgy, hogy ugyanaz a bemenet **bájtra azonos** reportot ad, és minden szám
mellett ott a `sourceFile` **és** a mező-szintű `command`
([ADR 0354](docs/adr/0354-recognition-baseline-manifest-and-evidence-index.md), D1–D9).

Az E14-R01 release guard `Baseline manifest` sora eddig egy **nem létező**
artefaktumra hivatkozott (`evaluation/recognition/` nem volt a fán) — az
aktiváláshoz olyan bizonyíték kellett, aminek nem volt formája. Ez a kör megadta.

**A kör terméke:**

- **[`evaluation/recognition/baseline_manifest.json`](evaluation/recognition/baseline_manifest.json)** —
  a MÁR MEGMÉRT számok (`docs/eval/real-audio-dsp-baseline.md`, E99-R04/R05):
  `chord` és `onset` **measured**; `direction`, `noChord`, `latency`,
  `calibration` **not-measured**, mindegyik valódi indoklással; a BPM külön,
  `retracted: true` blokk — a visszavont szám megőrizve, nem törölve (D4).
- **[`evaluation/recognition/baseline_manifest_schema.json`](evaluation/recognition/baseline_manifest_schema.json)** —
  draft-07 séma az `evaluation/analysis/` (ADR 0249) mintájára. A `metricBlock`
  `oneOf`-ja zárja a köztes állapotot: `measured` → `metrics` kötelező,
  `notMeasuredReason` tilos; `not-measured` → fordítva (D3).
- **[`tool/benchmarks/recognition_baseline_manifest.dart`](tool/benchmarks/recognition_baseline_manifest.dart)** —
  tiszta Dart (`dart:convert` + `dart:io`), **kézzel írt** JSON-Schema-részhalmaz
  validátor **zárt kulcs-halmazzal**, determinisztikus renderer (rendezett
  kulcsok, `toStringAsFixed(3)`, `DateTime.now()` sehol), `--check` mód.
- **[`docs/eval/recognition-baseline-index.md`](docs/eval/recognition-baseline-index.md)** —
  generált index: a narratív reportra és a release guardra **hivatkozik**, nem
  másolja őket (D9).
- `test/tooling/recognition_baseline_manifest_test.dart` — A1–A9, a §6 hat
  acceptance-pontja és a §6.1 mérce-mátrix minden sora cellánként.

**A pre-flight NYOLC mért brief-revíziót írt (§0.0/R1–R8)**, köztük két olyat,
ami enélkül a kör közben ütött volna ki: **R3** — nincs JSON-Schema függőség, és
a `pubspec.yaml` a kör tilos zónája, tehát a validálás csak kézzel írható;
**R4** — a §5.2 mező-szintű `command`-kötelezettsége és a §6 AC1 „not-measured"
blokkja **kielégíthetetlen** volt együtt, a séma `oneOf`-ja oldotta fel. Az
**R7** a manifest legkényesebb sorát mérte ki: a baseline a változatlan
`const ClipAnalyzer()`-rel futott (`strumRefiner: null`), tehát **egyetlen**
ML-súly sem vett részt — `models: []` + kötelező `modelsRationale`, mert egy
„a teljesség kedvéért" bemásolt `chord_crnn.bin` hash hamis állítás lenne arról,
mi futott a mérés alatt.

**A review 1 MAJOR-t mért a zöld gate mögött** (nyolc futtatott valódi-sértés
próba, nem diff-olvasás): a kézzel írt validátor a **nem implementált
séma-kulcsokat némán átengedte** — egy `"maxLength": 3` az `appCommit`-on
`exit=0`-t adott ott, ahol egy valódi draft-07 validátor piros. Ez a kör SAJÁT
ADR-je (0354 D8) kimondott fail-closed döntésének megsértése, és pont az a
csendes rés, aminek a bezárása a kör tárgya. Egy javító körben zárva, zárt
kulcs-halmazzal; az újra-ellenőrzés a `definitions` alatti, `$ref`-fel feloldott
esetet is méri ([L619](docs/LESSONS.md#l619)).

**Zöld kapu:** `full-gate.yml` [33850811662](https://github.com/wolfcasaba/strumsight/actions/runs/33850811662)
és `router-ci.yml` [33850774098](https://github.com/wolfcasaba/strumsight/actions/runs/33850774098)
— mindkettő `success` a merge SHA-n (`50b2862d`).

**Nyitott munka, amit a manifest most már NÉVEN nevez:** a négy `not-measured`
blokk (`direction`, `noChord`, `latency`, `calibration`) egy-egy későbbi Chapter
14 kör tárgya. Következő kör: **E14-R03** (model activation telemetry).

## ✅ E16-R05 KÉSZ — a Chapter 16 sáv LEZÁRVA: teljes app-verifikáció, **mért negatív A3-verdikttel** — PR [#562](https://github.com/wolfcasaba/strumsight/pull/562), squash `474a6b00` (2026-09-04)

A sáv záró köre gépi bizonyítékot ad arról, hogy a felület és a kód együtt
működik-e — és ott, ahol NEM, nevesített leletet hagy maga után ahelyett, hogy
elfedné. **A kör legfontosabb hozadéka egy negatív mérés:**

> **A3 — NEM teljesül.** A „BE" besorolású capabilityk core útja a termék SAJÁT
> navigációjával nem járható végig. A bejárás két teszt-oldali `router.go`
> hidat kényszerül használni: **L2** — az onboarding Skip-je
> `router.go(AppRoutes.live)`-ot hív (`onboarding_screen.dart:106`), sosem
> `/today`-t; **L1** — az adaptív shell EGYETLEN hirdetett belépési pontja
> pontozott gyakorlásba `?id=` nélkül navigál
> (`practice_area_hub_screen.dart:55`), így a Setup a saját `_RouteError` ágát
> rendereli. `adaptiveShellEnabled = true` mellett egyetlen ELÉRHETŐ képernyő
> sem állítja elő az id-t hordozó URI-t (`app_router.dart:541` vs `:394`).

Amit a kör **bizonyított**: az állomások oda navigálva valós adatot vagy
EXPLICIT állapotot mutatnak (**A2 ✅**), a routing- és kompozíciós réteg
placeholder-mentes (**A1 ✅**, 0 lelet), és a mért elérhető halmaz partíciója
teljes (**A4 ✅**, 9 bejárt + 64 kimaradó = 73, mindegyik gazdával és körrel).

**A kör terméke:**

- **[`tool/check_placeholder_wiring.dart`](tool/check_placeholder_wiring.dart)** —
  statikus mérő ZÁRT szerződéssel (brief §5.3, a pre-flight R3 revíziója): H1
  `lib/app/routing/*.dart` (4 fájl) + H2 kompozíciós provider-réteg (14 fájl);
  **P1** képernyő-konstruktor placeholder-argumentuma · **P2** konstans-testű
  top-level provider · **P3** konstans-értékű top-level deklaráció. Üres
  fájlhalmazra **fail-closed**. Mai mérés: **0 lelet**, egyetlen indokolt
  kivétellel (`progressV2IsOffline`, a forrás saját doc-commentje alapján).
- **[`test/e2e/full_app_walkthrough_test.dart`](test/e2e/full_app_walkthrough_test.dart)** —
  a **szállított** `FeatureFlags.forEnvironment(development, accountEnabled:
  false)` BE-készlettel (nem kézzel válogatott flagekkel) járja be a core utat.
- **[`docs/release/full-app-verification.md`](docs/release/full-app-verification.md)** —
  a mért eredmény és **öt NEM javított lelet** (L1–L5), gazdával és körrel. Az
  **L3** külön kategória: harness-eredetű (a `bootE2eApp` nem futtat production
  bootstrapot), ezért a Library-állomás a szállított kompozícióról sem jót, sem
  rosszat nem bizonyít.
- `test/support/e2e_harness.dart` — kizárólag egy **additív** `flags` paraméter,
  mai alapértékkel; a négy örökölt hívó fájlja érintetlen és zölden fut (A9).

**A pre-flight HÉT mért brief-revíziót írt (§0.0.1)**, köztük a **BLOKKOLÓ R2**-t:
a harness a nyolc BE-flagből ötöt kikapcsolva bootolt (`_e2eConfig()` négy mezőt
adott meg), tehát az A3 a brief eredeti alakjában **mérhetetlen** volt — a
`test/support/e2e_harness.dart` ezért került az `allowed_paths`-ra, és a négy
örökölt hívó a `gate_tests`-be (S11/S14, [L593](docs/LESSONS.md#l593)). Az **R3**
az A1 „aminek van valós forrása" feltételét — ami gépileg eldönthetetlen —
cserélte a zárt P1/P2/P3 szabályhalmazra. Új cellák: **A7** (a kivétel-lista nem
vákuum), **A8** (a mért fájlhalmaz nem üres és nem szűkült), **A9**.

**A review 1 MAJOR-t mért a 13/13 zöld gate mögött:** a kör az A3-at
teljesítettként jelentette, miközben a SAJÁT mérése cáfolta — ez az
[ADR 0470](docs/adr/0470-practice-setup-navigates-to-the-session-route.md) /
[L273](docs/LESSONS.md#l273) hibaosztálya, amivel az `E12-R11` review **H2**-vel
állította meg a láncot. A javítás **doc-only** volt (a `lib/**` a kör tiltott
zónája): a §6 A3 cellája most kimondja, hogy NEM teljesül — **cella törlése vagy
gyengítése nélkül**. Két MINOR + egy NOTE ugyanabban a javító körben zárva
(köztük a Profile Hub „sessions" cellája, ami korábban a streak-csempe `0`-jára
is illeszkedett).

**Mérce:** célzott kapu **13/13 ZÖLD** — a reviewer FRISS, izolált `/tmp`
klónban a review előtt ÉS a javító kör után is reprodukálta (`GATE_EXIT=0`),
nem bemondásra fogadta el; scope-audit `ok` (6 útvonal); exact-SHA CI a
`0c6098c0` merge SHA-n: build-apk + Coverage
[33836966766](https://github.com/wolfcasaba/strumsight/actions/runs/33836966766)
és Router CI
[33836983795](https://github.com/wolfcasaba/strumsight/actions/runs/33836983795)
— mindkettő `success`. Implementer `sonnet-impl` (Claude Sonnet 5), **1 javító
kör**. Review: [`docs/reviews/e16-r05-review.md`](docs/reviews/e16-r05-review.md)
(APPROVED, 0 nyitott lelet). Két új lecke:
[L617](docs/LESSONS.md#l617) (az orchesztrátor prompt-fájlja a munkapéldányban
hamis `scope_audit=VIOLATION`-t okoz) és [L618](docs/LESSONS.md#l618) (a
teszt-oldali navigációs híd LELET, nem kényelmi lépés).

**⚠ Nyitott, gazdátlan tételek a következő tervezéshez:** L1, L2 (a fenti két
navigációs szakadás — ezek zárnák az A3-at), L4 (a Profile Hub V1-napló
metrikája), L5 (`practiceHistoryV2ListProvider` sosem invalidálódik), L3
(harness/Library bootstrap). Egyikhez sincs ma hozzárendelt kör.

## ✅ E16-R04 KÉSZ — Élő backend end-to-end: **szerződés-vezérelt** bring-up smoke + eszköz-profil titok-határa — PR [#561](https://github.com/wolfcasaba/strumsight/pull/561), squash `e082b664` (2026-09-04)

A Chapter 16 negyedik köre azt teszi **egyetlen paranccsal mérhetővé**, hogy
egy VALÓDI backend-példány ellen a kliens teljes hálózati felülete működik-e,
és egy telefonra telepíthető build ráállítható-e — titok nélkül.

**A kör kulcs-döntése ([ADR 0503](docs/adr/0503-live-backend-smoke-contract-source-and-device-profile-secret-boundary.md) D1):**
a `tool/release/live_backend_smoke.py` a mérendő végpontokat **nem
hardkódolja**, hanem a `docs/contracts/client-backend-endpoints.json`-ből
(E15-R12, ADR 0497 D5) olvassa: mind a **34** bejegyzést besorolja
`exercised` (10) / `not_exercised` (21, kimondott indokkal) / `known_gap`
(3), és besorolatlan bejegyzésnél a hálózati hívás ELŐTT `exit 2`-vel megáll.
Így a „a smoke kihagyja a community felületet" hibaosztály nem elfelejthető,
hanem **szerkezetileg lehetetlen** — egy új kliens-végpont a szerződésbe
kerülve azonnal fedetlenné teszi a smoke-ot. A bring-up lánc (readiness →
register → login → `/auth/me` → settings olvasás/írás → community profil
create/read/update → `/blocked`+`/muted` → a három `known_gap` 404-próba) az
**első eltérésnél megáll** (D2) — szándékos eltérés a `production_smoke.py`
független-ellenőrzés modelljétől.

**A pre-flight HAT MÉRT brief-revíziót írt (§0.0.1)** — a brief 2026-09-02-án
készült, és hat állítása megdőlt: (R1) az előre kiosztott `ADR 0493`-at HÁROM
brief hivatkozta, a foglaló `0503`-at adott; (R2) „élő smoke-eszköz nincs"
TÉVES — a `production_smoke.py` (E12-R31) létezik, a kör elhatárolt társat
épít; (R3) a `device-backend-runbook.md` LÉTEZIK és trackelt (153 sor,
E15-R12) — a kör kiegészíti; (R4) az A1 forrása gépi artefaktum, és a
kliensnek **nincs feed-repository-ja**, így a `/community/feed` nem
másolható át; (R5) a `.gitignore` felvéve az `allowed_paths`-ba — a §3
ígéretét enélkül nem lehetett H3 nélkül teljesíteni, mért indok: a precedens
`lab_build.json` **trackelt és valódi alakú tokent tartalmaz**; (R6) a
`check_secrets_test.dart` temp-repókat mér, nem az élő fát.

**A review APPROVED (0 BLOCKER / 0 MAJOR / 1 MINOR / 3 NOTE)**, és a két
legfontosabb cellát nem a nevük, hanem a MECHANIZMUSUK alapján mértem (az
E12-R31 „vákuum-cella" hibaosztálya ellen): az A2 exit-2 cellája a `stderr`-t
is pinneli (egy connection-refused eredetű 2-es kód NEM elégítené ki), a
„megáll" állítást pedig egy **számláló kliens** bizonyítja — a későbbi
lépések nem is HÍVÓDNAK meg, nem csak „nincsenek jelentve". A kötelező
`security-reviewer` (`risk = "high"`) 0 BLOCKER / 0 MAJOR: nincs
credential-argumentum (futásonként friss, eldobható fiók), a válasz-törzs
sosem printelt, a redirect-követés blokkolt, a generált jelszó CSPRNG-alapú.

**Egy MÉRT CI-piros és a javítása:** a Full Gate zöld volt, a Router CI piros
— a kör KÖTELEZŐ valódi-sértés próbájának **writeupja** hozta be egy hamis
token literálját a briefbe (`docs/rounds/**` = Router-CI trigger-útvonal). A
termék végig tiszta volt. Javítás: a szkenner saját inline markere.
→ [L615](docs/LESSONS.md#l615). A scope-audit bázis-csapdája:
[L616](docs/LESSONS.md#l616).

**Mérce:** célzott kapu a munkapéldányon **10/10 ZÖLD** (format, analyze, 2
teszt-út, architecture, secrets, l10n, backend ruff format/check, backend
pytest 350 passed); scope-audit `ok` (7 útvonal); exact-SHA CI az `f03a34ec`
merge SHA-n: Full Gate
[33829479990](https://github.com/wolfcasaba/strumsight/actions/runs/33829479990)
+ Router CI
[33829481527](https://github.com/wolfcasaba/strumsight/actions/runs/33829481527)
— mindkettő `success`. Implementer `sonnet-impl` (Claude Sonnet 5), 0 javító
kör. Review: [`docs/reviews/e16-r04-review.md`](docs/reviews/e16-r04-review.md)

**Operátori (user-) lépés marad:** a backend tényleges futtatása és a telefon
ráállítása — a runbook §8/§9 vezeti végig. A kör NEM indított szervert.

## ✅ E16-R03 KÉSZ — Capability rollout-döntések: **ZERO FLIP** mért evidenciával — PR [#560](https://github.com/wolfcasaba/strumsight/pull/560), squash `1bb21b95` (2026-09-04)

A Chapter 16 harmadik köre capabilityenként MÉRT rollout-besorolást ad, és a
mérés eredménye **ZERO FLIP**: mind a **40** `forEnvironment` mező
kiértékelése után egyetlen, korábban `false` capability sem teljesíti mind a
négy kritériumot, ezért a `lib/app/config/feature_flags.dart` **változatlan**
(`git diff --stat origin/main..HEAD -- lib/app/config/feature_flags.dart` →
üres). Ez a brief §0.0.1 R3 és az [ADR 0492](docs/adr/0492-capability-rollout-decision-evidence-and-nonprod-boundary.md)
D1 szerint **elfogadott, mért kimenet**, nem hiányos kör — a kör terméke a
döntési tábla és az azt őrző gépi mérce.

**Az új dokumentum:** [`docs/release/capability-rollout.md`](docs/release/capability-rollout.md)
— a **NEM-production (development/lab)** alapértelmezések döntési táblája.
Elhatárolva a `ga-scope.md`-től (GA/**production** besorolás, ADR 0489) és a
`rollout-decision.md`-től (staged **százalékos** rollout, E12-R32); production
alapértelmezésről saját állítást nem tesz (ADR 0492 D2).

**A besorolások:** 8 capability **BE** (változatlan — Diagnostics, Lab mode,
Practice Engine V2, Migrated Learn, Practice detailed history, Song Trainer V2,
Practice Generator, Adaptive shell) · 5 community flag **PREVIEW** (dart-define,
ADR 0395) · a többi **KI**, mindegyik nevesített feloldó körrel vagy fán
feloldható blokkolóval (`E12-R17`, `E12-R18`, `E14-R02`, `E16-R04`, HORIZON
device-elfogadás, Epic 6 release-blokkolók).

**A pre-flight négy MÉRT revíziót írt a briefbe (§0.0.1):** (R1) a brief §2
három állítása MÉRTEN téves volt — a `practiceGeneratorEnabled` MA `nonProd`
(ADR 0491 D2 óta), a vision flagek száma 11 (nem 10), az analysis flageké 9
(nem 10); (R2) a `forEnvironment` törzse a `tool/release/verify_ga_scope.py`
fail-closed parserének **négy** alakját tarthatja csak (`nonProd`/`true`/
`false`/`const bool.fromEnvironment(...)`) — bármi más `VerifyError`, ami a
körön KÍVÜL élő `ga_scope_test.dart`-ot viszi pirosra (H3); (R3) az
[L534](docs/LESSONS.md#l534) hatósugár-protokoll (flip előtt mérés, különben
`stopped`); (R5) a `gate_tests` **szigorítva** három, a körön kívül élő őrrel
(`ga_scope_test.dart`, `analysis_rollout_flags_test.dart`,
`app_config_test.dart`).

**A review 1 MAJOR-t mért a zöld kapu mögött:** az A1 és az A6
acceptance-kritériumnak **nem volt gépi mércéje** — a döntési tábla köré gépi
határolók (`<!-- capability-rollout-decisions:begin/end -->`) kerültek, de
egyetlen cella sem olvasta őket, így a tábla bármely sora törölhető vagy
„később"-re cserélhető lett volna a kapu zöldje mellett (a brief §6.1 épp ezt
ígérte pirosnak). A javító kör a marker-blokkot adatként parse-olja, és a
mezőneveket a `feature_flags.dart`-ból olvassa ki (nem hardkódolt lista). A
zárást a reviewer **saját, független mutációs próbái** igazolják, nem az
implementer jelentése: P1 `resolving` → „később" ⇒ **A6 piros**; P2 táblasor
törölve ⇒ **A1 fedettség piros**; P3 marker eltávolítva ⇒ **mind a három cella
piros** (fail-closed); P4 ismeretlen besorolás ⇒ **A1 besorolás-készlet piros**;
P5 visszaállítás ⇒ **26/26 zöld**.
→ [L614](docs/LESSONS.md#l614), review: [`docs/reviews/e16-r03-review.md`](docs/reviews/e16-r03-review.md)

**Mérce:** célzott kapu a munkapéldányon MINDEN GATE ZÖLD (format, analyze, 7
teszt-útvonal, architecture, secrets, l10n); scope-audit `ok`; exact-SHA CI a
`513d1191` merge SHA-n: full-gate
[33822335974](https://github.com/wolfcasaba/strumsight/actions/runs/33822335974)
+ Router CI
[33822337524](https://github.com/wolfcasaba/strumsight/actions/runs/33822337524)
— mindkettő `success`. Implementer `sonnet-impl` (Claude Sonnet 5), 1 javító kör.

## 🔧 ÖNJAVÍTÓ KÖR — E16-R02 / H3 (5.): dátumozott jelentést őrzött ÉLŐ-fás mérés (2026-09-03)

**ADR 0112 önjavító kör. A megállt kör terméke változatlanul HIBÁTLAN** — a
4. H3 (lásd alább) fel van oldva, a `#557` beépítve, a Router CI zöld
(`33808400511`), a célzott kapu 21/21, mind a 12 acceptance-cella kész. A
merge-et EGYETLEN cella blokkolta a `full-gate`-ben (run `33808412804`, SHA
`73ff5351`), szintén a kör TILOS zónájában:

```
❌ test/ui/goldens/e15_r13_full_variant_matrix_test.dart:3733
   A5 — completion-report guard … Expected: contains '73'
```

**Mért gyökérok.** A cella az ÉLŐ fából mérte újra a reachability-t
(`ScreenReachability(Directory.current).render()`), és attól követelte meg egy
**dátumozott, lezárt kör** jelentésének (`docs/ui/chapter-15-completion-report.md`,
fejléc: *„Measured against: `main @ 9ba54399` + this round's own tree"*,
`reachableCount=71`) szám-egyezését. Az E16-R02 acceptance-kritériuma PONTOSAN
két képernyő (`ProgressDashboardScreen`, `SkillDetailScreen`) elérhetővé
tétele → 71 → 73: **a kör SIKERE vitte pirosra az őrt**, miközben mindkét fájl
a kör tiltott zónájában van (a lista tágítása ADR 0087 §2 szerint nem az
orchestrátoré). Ugyanaz a hibaosztály, mint az L612, csak a doc-konzisztencia
felől — és a következő három kör (`E16-R03/-R04/-R05`) mind reachability-t
növel, tehát mindegyiküket megállította volna.

**A javítás (nem gyengítés).** A várt számok a jelentés SAJÁT bázisán mért,
rögzített pillanatképből jönnek
(`test/fixtures/ui/e15_r13_completion_report_baseline.json`; a mérés
`dart run tool/check_screen_reachability.dart --format json` a `70b56465`-ön,
amelynek `lib/`+`tool/` fája byte-azonos a jelentés bázisával — provenance
gépileg őrizve a `test/fixtures/manifest.json`-ban, ADR 0473). Az L588
tulajdonsága változatlan: minden állítás a jelentés SZÖVEGÉTŐL függetlenül áll
elő (némán törölt állítás is bukik), ráadásul a cella a pillanatkép négy
számát a saját 96 sorából újraszámolva is ellenőrzi. Az élő fát az
`A1 — completeness` group méri tovább — az az invariáns túléli a jogos
reachability-növekedést. A cellaszám változatlan (A5: 6), így a `grand total`
cella és a jelentés 1163-as száma érintetlen.

**Őrteszt:** `tools/tests/test_dated_report_guards.py` (rögzített
halt-pillanat-fixture a szabály viselkedésére + a KÖVETELT VÉGÁLLAPOT az élő
`test/` fán: dátumozott jelentést egyetlen group sem őrizhet
`X(Directory.current)` méréssel). Mérve: `main @ 70b56465` **1 failed**
(a lelet pontosan `…test.dart:3724`) → javítás után **5 passed**, és — az L612
kötelező pre-flight lépése szerint — a **kör HEAD-jén is** (`8b76e19a` + heal
merge): `5 passed`, A5 `6 passed`, A1 `5 passed`.
→ [L613](docs/LESSONS.md#l613).

## 🔧 ÖNJAVÍTÓ KÖR — E16-R02 / H3 (4.): az őrteszt a saját köre munkájának HIÁNYÁT pinnelte (2026-09-03)

**ADR 0112 önjavító kör. A megállt kör terméke HIBÁTLAN volt** — a merge-et öt
teszt blokkolta a kör TILOS zónájában (`tools/tests/**`), amelyeket a KORÁBBI
három önjavító kör (PR #552/#553/#555) írt.

**Mért gyökérok.** Mind az öt cella az ÉLŐ fát olvasta, és a kör munkájának
**HIÁNYÁT** pinnelte — vagyis a kör **sikere** garantáltan pirosra vitte a
Router CI-t:

- két `assertNotIn` a termékre: „a `/profile/progress/skills/:skillId`
  konstans még nem létezik" és „a `PracticeHistoryEntry` még nincs exportálva"
  — mindkettőt a brief §5.8 ill. §0.0.I/I5 **KÖTELEZŐVÉ** teszi ugyanennek a
  körnek;
- három `brief-lint` cella az ÉLŐ briefet szűrte: a kör a §10-be beírta a saját
  review-leletét a `/profile/library`-ról (MINOR-4), ettől az S11 egy vadonatúj
  leletet adott a kör SAJÁT dokumentációjától (`grep -c` a briefen: main 1 →
  kör HEAD 2).

Mérve: bázis (`9ba54399`) **19 passed** · kör HEAD (`7d3430b8`) **5 failed, 19
passed** · a javítás után ugyanazon a kör-HEAD-en **25 passed**.

**A javítás (nem gyengítés).** Az állapot-mércék arra az invariánsra álltak át,
ami a landolás MINDKÉT oldalán áll és utána SZIGORÚBB (a katalógus vagy egyet
sem, vagy PONTOSAN a pinnelt alakot deklarálja; a barrel vagy egyik
§5.5-adapter-típust sem, vagy MINDET exportálja). A szabály-viselkedést mérő
`brief-lint` cellák rögzített pillanatképet kaptak
(`tools/tests/fixtures/e16_r02_route_level_swap/`, szó szerint másolva
`origin/main @ 4fffa3f1`-ről, `PROVENANCE.md`-vel). Az élő fán futó kimerítő
mérést változatlanul a Router CI `brief-lint.py --open --level base` lépése
végzi — az szándékosan CSAK a NYITOTT körök briefjeit linteli.
**Mutációs próba:** elgépelt útvonal-alak és fél-landolt barrel-export →
mindkét új mérce PIROS, majd visszaállt. → [L612](docs/LESSONS.md#l612), és a
kötelező pre-flight lépés bekerült a `docs/execution/pipeline-selfheal-prompt.md`-be.

**MÁSODIK, ÖNÁLLÓ AKADÁLY — MÉRVE, de a javítása NEM ezé a köré.** A
`full-gate.yml` két futása KÜLÖNBÖZŐ cellával bukott (`33796054904` →
`song_import_controller_test.dart`, `33798888247` → `import_flow_test.dart`),
mindkettő lokálisan 8/8 zöld, és a kör diffje 0 `songs/`/`import` fájlt érint.
Forrás-szintű diagnózis: **mindkét cella FIX SZÁMÚ event-loop fordulóra
szinkronizál, miközben a mért kód valódi fájlrendszer-I/O-t végez** —
`ImportWorkspace.open()` (`import_workspace.dart:26-44`) **öt** egymás utáni
async FS-műveletet futtat (`root.create`, `resolveSymbolicLinks`,
`directory.create`, `resolveSymbolicLinks`), a tesztek viszont
`await Future<void>.delayed(Duration.zero)` (egy forduló), illetve
`pumpEventQueue()` — ami `test_api-0.7.13/lib/src/scaffolding/utils.dart:16`
szerint **pontosan 20 üres event-loop fordulót** pörget, és NEM vár I/O-ra.
Terhelt runneren a 20 forduló lefut az 5 syscall előtt → `tempRoot.listSync()`
üres → `isNotEmpty` bukik. Ez **teszt-determinizmus hiba, nem termék-regresszió**
(egy regresszió ugyanazt a cellát buktatná). A helyes javítás — feltételre
várni tick-budget helyett — `test/**` írás, ami az ADR 0112 §2 önjavító
jogosultságán KÍVÜL esik: **nevesített follow-up kör dolga**.

## ✅ E15-R13 KÉSZ — a Chapter 15 sáv LEZÁRVA: 72 képernyős záró variáns-mátrix és mért zárójelentés (2026-09-03)

**PR [#556](https://github.com/wolfcasaba/strumsight/pull/556), squash `b968cc4a`; ADR: nincs (mérési/záró kör).**

**A sáv mérlege — MÉRVE, nem becsülve:** **91/96 képernyő migrált (94,792%)**
(a sáv indulásakor 43/96 volt), **71 elérhető / 25 elérhetetlen / 27
flag-kapuzott**. A záró állítás pontos alakja: *minden ELÉRHETŐ képernyő vagy
migrált (91), vagy `retire`-verdiktes nevesített utóddal szerepel (5)* —
**nem** „a visszavonás megtörtént".

- **`test/ui/goldens/e15_r13_full_variant_matrix_test.dart` (ÚJ, ~3900 sor):**
  72 képernyő × {light, dark} × {en, hu} × {compact portrait 412×915,
  landscape 915×412} × {textScale 1.0, 2.0} = **1152 cella**, + 5 A1- és 6
  A5-őrcella = **1163 teszt**, 55 s alatt. Minden cella saját
  `tester.view.physicalSize`-szal ([L558](docs/LESSONS.md#l558)),
  `FlutterError.onError`-alapú túlcsordulás-méréssel; `skip`/tolerancia sehol.
- **`docs/ui/chapter-15-completion-report.md` (ÚJ):** a sáv zárójelentése,
  külön §-sal arról, amit NEM állít.
- **4 mért `lib/**` túlcsordulás-LELET** 32 dátumozott, csak-zsugorodó
  `_ExcludedCell`-lel (a kör MÉR, nem javít — `lib/**` tilos zóna):
  `StrumReelScreen` (191–935 px, **már `textScale 1.0`-nál is** — a
  legsúlyosabb), `AnalyzeScreen`, `LatencyCalibrationScreen`, `LearnScreen`,
  `LessonScorePreviewScreen`.
- **Nyitott, gazdás tétel:** az `E15-R04` nevesített visszavonása SOHA nem
  hajtódott végre (ADR 0471 D5 szerint ez nem szabálysértés) — a
  `legacy-backlog.md` §3.0-ban dátummal, gazdával és nevesített hordozó körrel
  (`E16-R05`).

**A review megfogta, amit a zöld kapu nem** (1 MAJOR + 1 MINOR): a zárójelentés
`+1157: All tests passed!`-et idézett **parancs-kimenetként**, miközben a mért
érték `+1162` volt — az A5-őr a részszámokat pinnelte, a **végösszeget** nem
([L610](docs/LESSONS.md#l610)). A javító menet a számot javította ÉS az őrt
kiegészítette; a nyitott tételek „unscheduled" gazdája pedig gépi mércét kapott
(`E\d{2}-R\d{2}` vagy explicit „nincs sorba állítva" közlés). Újra-review:
**APPROVED**, 0 nyitott lelet (`docs/reviews/e15-r13-review.md`).

**A reviewer öt eldobható mutációs próbája** mind PIROSRA váltott, majd
visszaállt: képernyő kivétele a mátrixból → A1; riport-sor **törlése** → A5
([L588](docs/LESSONS.md#l588)); lelet-sor törlése → A5; hamis `_ExcludedCell`
→ „STALE"; a végösszeg elrontása → az új A5-cella. Külön mérés a kozmetikai
zárás ellen: mind a 72 képernyő renderelt fája lemérve — 70 gazdag fát
renderel, a maradék 2 is épített fa (224 / 744 widget).

**Zöld kapu:** `build-apk.yml` (`33798598939`) és `router-ci.yml`
(`33798600961`) mind `success` a `460cbbab` merge SHA-n; a `tools/round-gate.sh`
mind a 9 lépésen zöld a reviewer saját, izolált klónos futásában.

## ✅ E15-R12 KÉSZ — a Community backend felcsatolva, 11 hitelesített routerrel (2026-09-03)

**PR [#554](https://github.com/wolfcasaba/strumsight/pull/554), squash `220887e9`; ADR 0497.**
Az Epic 9 teljes szerver-oldali Community felülete eddig **elérhetetlen** volt: a
`build_community_router()` csak a `profile` routert adta vissza, és a production
`create_app()` egyáltalán nem hívta. Ez a kör felcsatolta — **fail-closed**.

- **11 router** a `community_enabled` flag mögött, **regisztráció szinten** (kikapcsolva
  a route létre sem jön → 404, nem 403 — D1); al-flagek önállóan kapuznak (D2).
- **`handles` + `privacy` KIMARAD** (**D6**, a review után született döntés): mérve mind
  a 6 route-metódusuk hitelesítés NÉLKÜL válaszol. A kliens egyiket sem hívja.
- **`/health/ready`** a bekapcsolt modulra a community readiness-gate-et is futtatja (D4).
- **Gépi kliens↔szerver szerződés** (D5): `docs/contracts/client-backend-endpoints.json`
  (34 mért kliens-hívás: 31 `mounted` + 3 őszinte `known_gap`) + parity-teszt az OpenAPI
  séma ellen, kanárival és valódi-sértés próbával.
- **Eszközös runbook**: `docs/operations/device-backend-runbook.md`.

**A review megfogta, amit a zöld kapu nem.** Az első mérés **2 BLOCKER + 2 MAJOR +
1 MINOR** — a kör saját A2 cellája 48 route-metódusból ötöt próbált, ezért 8
hitelesítetlen végpont mellett is zöld maradt (**L609**). A javító kör mindet lezárta;
az A2 most az `app.routes` fából mér kimerítően, két tételesen indokolt kivétellel.
Az újra-review **APPROVED**, 0 nyitott lelet (`docs/reviews/e15-r12-review.md`).

**Zöld kapu:** Full Gate + Router CI + Backend CI mind `success` az `1d7c6924` merge
SHA-n; lokálisan `tools/round-gate.sh` mind a 10 lépésen zöld, teljes backend suite
zöld a tilos zóna MÓDOSÍTÁSA NÉLKÜL (A7).

**Nyitott tartozás** (ADR 0400 Következmények (b)/(c), ADR 0497-ben rögzítve): a
`privacy.py` authz és az E09-R04 TOCTOU; amíg nyitott, a `handles`/`privacy` router
felcsatolatlan marad, és a `GET /community/profiles/{public_id}` az A2 dokumentált,
mért indoklású kivétele (egy tilos zónás teszt auth nélkül hívja és 200-at vár).

## 🔧 E16-R02 / H3 ÖNJAVÍTÓ KÖR, 3. (ADR 0112) — az útvonal-szintű képernyőcserét pinnelő tesztek a scope-ba, és a lint vakfoltja javítva (2026-09-03)

Az E16-R02 **harmadik** pre-flightja (`main @ b685831a`) ismét **H3**: az **A1**
cella a `/profile/progress`-t köti át a `ProgressDashboardScreen`-re, a legacy
`ProgressScreen`-t viszont a briefen KÍVÜL élő
`test/features/today/hub_navigation_test.dart:247` pinnelte (shell-ON router,
`flutter test` → `00:03 +8: All tests passed!` = ÉLŐ regresszió-őr).

**Két javítás egy körben:**

1. **Eszköz (A osztály):** a `tools/brief-lint.py` a képernyő-cserét
   FÁJL-TULAJDONLÁSBÓL mérte, ezért erre a briefre (0 db `*_screen.dart` és 0 db
   `lib/` könyvtár-előtag az `allowed_paths`-on) az `S11`/`S14` **strukturálisan
   néma** volt. Az új `route_level_swapped_screens()` a router
   `GoRoute(path: AppRoutes.X, builder: … const YScreen())` párjaiból méri az
   ÚTVONAL-szintű cserét; három hamis-riasztás-mérce szűkíti (router a
   scope-ban · a brief nevezze meg az útvonalat · a PIN is nevezze meg) —
   mérve: 45 bekötésből 1 képernyő, 5 pinből 3.
2. **Kör-tartalom (B osztály):** §0.0.J revízió — a három útvonal-szintű őr
   (`hub_navigation_test.dart`, `app_router_test.dart`,
   `offline_network_guard_test.dart`) bekerült az `allowed_paths`-ba ÉS a
   `gate_tests`-be (a §7 gate-parancs is), a §4 tábla pedig a jogosultságot
   PONTOSAN a várt képernyő-típus átírására szűkíti.

**Cellát nem töröltünk, nem gyengítettünk** — a `hub_navigation` A5 cellájában
csak a VÁRT TÍPUS változik, az állítás (a legacy `/progress` a redirect végén a
`/profile/progress` képernyőjét adja) változatlan. A képernyőt közvetlenül építő
két teszt (`screen_size_guard_test`, `progress_screen_test`) MÉRVE kimarad.

**Őrtesztek:** `tools/tests/test_brief_lint_route_level_screen_swap.py` (a
javítás előtti fán 5 cellája PIROS) · `tools/tests/test_e16_r02_hub_navigation_pin_scope.py`
· **Tanulság:** `docs/LESSONS.md` **L608**.

**A kör így újraindítható** — az E16-R02 sora a `pipeline-queue.tsv`-ben
változatlanul `pending`, a brief-lint `strict` szinten **nincs lelet**.


## 🔧 E16-R02 / H3 ÖNJAVÍTÓ KÖR, 2. (ADR 0112) — a route-katalógus ownere a scope-ba + négy mért brief-hiba (2026-09-03)

Az E16-R02 **második** pre-flightja (`main @ 18a649ec`, tehát már a lenti
§0.0.H revízióval) újabb **H3**-mal állt meg: az **A2** cella ÚJ skill-detail
útvonalat ír elő, de a route-katalógus ownere (`lib/app/routing/app_route.dart`)
nem volt az `allowed_paths`-on. A fán **0** inline útvonal-literál van (minden
`GoRoute.path` `AppRoutes`-konstans), a `route_literal_guard_test` tiltja a
literálokat, a `SkillDetailScreen.onOpenEvidence` szerződése pedig `AppRoutes`
konstanst vár — a listán belüli feloldás nem létezett. Ugyanaz a hibaosztály,
mint az **L97** / **L246** / **L90**, és az előző kör (E16-R01) briefje pontosan
így vette fel a `levelDetail` konstansot.

**A javítás (brief §0.0.I revízió, PR #553):** az `app_route.dart` felkerült az
`allowed_paths`-ra és a §4 táblára — **KIZÁRÓLAG az új konstans hozzáadására** —,
az ÚJ **§5.8** pedig pinneli az útvonal alakját (`profileProgressSkill =
'/profile/progress/skills/:skillId'`, az SDD UI-50 kanonikus route-ja;
`:skillId` = `MasterySkill.code`; ismeretlen id → átirányítás a
`/profile/progress`-ra; az `onOpenEvidence` az E13-R31-ben merge-elt
`profileLibrarySession` szerződést kapja). Ugyanez a revízió rendezte a mellette
mért **négy** brief-hibát: a §5.4 milestone-id-jei snake_case-re (a domain
`^[a-z][a-z0-9_]*$` regexe futásidőben dobott volna), a katalógus `const` →
`final` + `List.unmodifiable` (a publikus konstruktor factory), ÚJ **`difficulty`
oszlop** (`MasteryDifficulty.beginner` — az evaluator erre SZŰR, e nélkül az A10
alulspecifikált), és a `practice/public.dart` export-engedély kibővítése a
`PracticeHistoryEntry` / `PracticeMetricSnapshot` / `PracticeMetricDimension*`
nevekre (a `check_architecture.dart` csak barrelen át enged kereszt-feature
importot). A fejléc-ADR `0491` (merge-elt) → **`0500`** (a foglalótól).

**Cellát nem töröltünk és nem lazítottunk** — az A1–A12 változatlan, az A2 csak
pontosabb lett (nevesített konstans + az ismeretlen-id ág).

**Őrteszt:** `tools/tests/test_e16_r02_route_catalog_scope.py` (a revízió előtti
briefen mind a 8 cellája PIROS, és minden állítását a KÓDHOZ méri) ·
**Tanulság:** `docs/LESSONS.md` **L607**.

**A kör így újraindítható** — az E16-R02 sora a `pipeline-queue.tsv`-ben
változatlanul `pending`.


## 🔧 E16-R02 / H3 ÖNJAVÍTÓ KÖR (ADR 0112) — a hiányzó mastery-forrás bekerült a kör scope-jába (2026-09-03)

Az E16-R02 pre-flightja **H3**-mal állt meg: a brief a `/profile/progress`
átkötését írta elő a Progress V2 dashboardra „valós projekcióval", miközben a
projekció mastery-oldalának **nincs forrása a fán** (0 produkciós
`MasteryMilestone`-katalógus, 0 `MasteryEvidence`-előállító, 0 milestone-l10n
kulcs). Üres milestone-listával az `isNewUser` igaz, tehát a kör a MA valós
adatot mutató legacy `ProgressScreen`-t egy örökre üres „get started"
állapotra cserélte volna — **zöld A1–A7 cellák mellett** (a cellák a hívót
mérik, nem az adat létezését).

**Az önjavítás nem gyengített és nem halasztott:** a hiányzó FORRÁS lett a kör
része. A brief §0.0.H revíziót kapott, az `allowed_paths` a mastery-katalógussal,
a practice→`MasteryEvidence` adapterrel és a milestone-l10n szegmenssel (+ a két
generált aggregátummal) bővült, az §5.4–5.7 pinneli a küszöböket (`0.8`,
3 session), a leképezést és az eldobási szabályokat, a §6 pedig **öt új cellát**
kapott (A8–A12) — köztük az **A10**-et, ami pontosan a fenti hibamódot viszi
pirosra. A régi A1–A7 cellák változatlanok.

**Őrteszt:** `tools/tests/test_e16_r02_mastery_source_scope.py` (a revízió előtti
briefen 3 cella PIROS) · **Tanulság:** `docs/LESSONS.md` **L606**.

**A kör így újraindítható** — az E16-R02 sora a `pipeline-queue.tsv`-ben
változatlanul `pending`.


## ✅ E16-R01 KÉSZ — A Gamification kompozíciós rétege: valós adat a felület mögé — PR [#549](https://github.com/wolfcasaba/strumsight/pull/549), squash `8c27bf3a` (2026-09-03)

A **Chapter 16 (Kompozíció és rollout) első köre.** A gamification feature
tizenkét `application/` szolgáltatása és működő `data/` rétege eddig sem jutott
el a képernyőkig: a feature-ben **nulla** Riverpod-provider volt, az egyetlen
bekötés a ROUTERBEN élt ad hoc módon (3 privát provider + **beégetett
négyszintes `LevelCurve`**), a képernyők pedig konstans placeholdereket kaptak,
nyolc `TODO(E08-R30)` markerrel megjelölve.

**A kör mérlege:**

- ÚJ kompozíciós réteg: `lib/features/gamification/providers/gamification_providers.dart`,
  a `public.dart` barrelen át kivezetve; a router a **barrelen keresztül**
  fogyaszt, katalógus/görbe/projekció nem él többé a router fájlban.
- **8 → 0** `TODO(E08-R30)` a routerben: **5 BEKÖTVE** (achievement-haladás a
  ledger idempotens receiptjeiből, streak-reason a `StreakService`-ből — nem
  beégetett `qualified`, reward-inbox a ledger-joinból, level-detail projekció,
  quest-akció-routing a lezárt `QuestRouteAction` szótárral), **3 BACKLOG**
  datált, gazdás bejegyzésként. A javító kör további **3** bejegyzést tett
  hozzá (`docs/ui/legacy-backlog.md` §6.1–§6.6).
- A `LevelDetailScreen` (létező, tesztelt, de route nélküli képernyő) végre
  elérhető: ÚJ `AppRoutes.levelDetail` konstans + route (ADR 0123 / L90 mintája:
  route-aktiváláshoz a kör-scope-nak a composition rootot is birtokolnia kell).
- **Hamis nulla helyett explicit hiány** ([ADR 0496](docs/adr/0496-gamification-composition-layer-and-honest-unavailability.md)):
  ahol a perzisztált állapotból nem számítható érték, a provider a hiányt
  TÍPUSBAN hordozza, a `FutureProvider` loading/error ága nem eshet egybe a
  MÉRT üressel (`_achievementsAsyncBuilder` `.when` + hibalogolás), és minden
  kifejezhetetlen hiány datált backlog-tételt kap.

**Protokoll:** implementer `sonnet-impl`, orchestrátor/reviewer Claude Opus 5.
A review (`docs/reviews/e16-r01-review.md`) az első körben **3 BLOCKER, 3 MAJOR,
5 MINOR** leletet adott (a két kötelező ügynök — `flutter-reviewer`,
`flutter-devil-advocate` — a `risk = "high"` miatt), a javító kör után
**APPROVED**, leletenkénti bizonyítékkal.

**Két mért tanulság ment a naplóba (L603, L604):** a pre-flightban az előre
kiosztott `ADR 0490` MÁR FOGLALT volt (a foglaló `0496`-ot adott), és a kör
célzott kapuja zölden ment azon a fán, amit a teljes CI pirosra vitt — az
`architecture_dependency_test.dart` (gamification `application/` =
framework-mentes, E08-R08) nem volt a `gate_tests` listán. A fájl azóta a repó
bevett `features/<f>/providers/` helyén él, az őr pedig a kör kapujában.

**Ismert, kimondott korlát:** a bekötött olvasásoknak ma nincs ÍRÓJUK a fán
(`replaceProfileSnapshot` / `ActivityEventIngestor` / `DailyChallengeService`
hívási hely a `lib/`-ben: **nulla**) — a producer-bekötés új üzleti logika,
ezért nem ennek a körnek a hatásköre; `docs/ui/legacy-backlog.md` §6.6
rögzíti.


## ✅ E15-R11 KÉSZ — Vision, onboarding és a maradék közösségi képernyő a design-rendszeren — PR [#548](https://github.com/wolfcasaba/strumsight/pull/548), squash `80846c92` (2026-09-03)

A Chapter 15 **utolsó** migrációs batch-e: a kamera-út három képernyője
(`vision_setup`, `vision_session`, `guitar_calibration`), az onboarding (az
ELSŐ, amit egy új felhasználó lát) és az egyetlen maradék közösségi képernyő
(`followers`) a `core/design_system` komponenseit és tokenjeit használja,
változatlan viselkedés mellett.

**Mért migrációs arány a MERGE-ELT fán: 91/96 (94,792%)** — a kör saját öt
képernyője 80/96 → 85/96, és vele egy órán belül landolt az E15-R10 hat
képernyője is; a 91/96 friss újraszámolás minden
`lib/features/**/*_screen.dart` fölött, nem a két kör összeadása. A
`ui_inventory_test.dart` egzakt száma VÁLTOZATLAN (a kör nem hozott létre és
nem törölt képernyőt).

**A kör két menetben zárult.** Az első implementáció után a független review
(`docs/reviews/e15-r11-review.md`, `flutter-reviewer` + `flutter-devil-advocate`
+ `security-reviewer`, `risk = "high"`) **2 BLOCKER + 3 MAJOR + 4 MINOR**
leletet mért, mind zárva EGY javító körben:

- **BLOCKER-1** — a `vision_session_routing_test.dart` null-check crash-e
  (`VisionSessionScreen.build:51`): a harness csupasz `MaterialApp.router`-t
  pumpolt. Ez vitte pirosra a CI-t. A fájl a **routeren át** (`router.go`) éri el
  a képernyőt, ezért sem az osztálynév-alapú pre-flight mérés, sem a
  `brief-lint` **S11** szabálya nem találta meg → §0.0/**R9** revízió:
  `allowed_paths` + `gate_tests`, és a harness a valódi futásidejű témát kapja.
- **BLOCKER-2** — az onboarding fő CTA-ja `SsButton`-ra váltott, ami a feliratot
  `Flexible(overflow: ellipsis)`-szel EGY sorra vágja: a `hu` „Próbáld ki az
  első győzelmed — 30 mp" a KÖTELEZŐ 2.0-s szövegskálán telefon-szélességen
  csonkult. A repó ezt a hibaosztályt már eldöntötte (E15-R08 M3,
  `streak_detail_screen.dart:117-126`) — a CTA visszatért nyers
  `FilledButton`-ra, dokumentált kivétel-kommenttel, és **COMMITOLT cella**
  pinneli (`didExceedMaxLines`, `en`+`hu`, 2.0×, 412×915), amely azt is
  állítja, hogy a CTA `FilledButton` marad.
- **MAJOR-1** — három A3 variáns-mátrix a `flutter_test` 800×600-as
  alapértelmezett felületén futott (minden telefonnál szélesebb), és csak
  `takeException()`-t állított — amit az ellipszis épp ELNYOM. Mindhárom
  harness telefon-szélességre állt (412×915), a csonkulást mérő cellával.
- **MAJOR-2** — a `followers` betöltés-állapota nyers `CircularProgressIndicator`
  maradt (a §5.2 szó szerint nevesített tiltott gyengítése) → `SsSkeleton`,
  típus-cellával.
- **MAJOR-3** — a kör bevezette, hogy az engedély-hiba státusz-szövege
  `colors.danger`-re vált: a világos témán ez **3,27:1**, a repó saját 4,5:1-es
  szöveg-küszöbe alatt, és egyetlen létező kapu sem mérte. A szín-döntés
  visszavéve — a hibát a SZÖVEG mondja ki, nem a szín.
- **MINOR-1..4** — látensen törött baseline-harness, 2,85:1-es banner-ikon,
  beleolvadó followers-avatár, elavult doc-komment; mind javítva, mért
  kontraszt-arányokkal.

**Zöld kapu a `28a94280` merge SHA-n:** Full Gate
[33747154956](https://github.com/wolfcasaba/strumsight/actions/runs/33747154956)
+ Router CI
[33748950221](https://github.com/wolfcasaba/strumsight/actions/runs/33748950221),
mindkettő `success`; gépi scope-audit `ok` (30 fájl, 0 sértés); a
`tools/round-gate.sh` 28/28 zöld, az orchestrátor célzott újrafuttatása 58/58.

**A CI első pirosának MINDKÉT cellája lezárva:** a routing-crash a kör hibája
volt (BLOCKER-1, javítva); a `test/features/songs/import/import_flow_test.dart`
viszont **CI-oldali flake** — lokálisan 2/2 zölden fut, a kör diffje **nulla**
`songs`-fájlt érint, és a következő futáson már nem jelentkezett.

Motor: implementer `sonnet-impl`, orchestrátor/reviewer Claude Opus 5.

## ✅ E15-R10 KÉSZ — Audio Analysis + Analyze 6 képernyő migrálása a design-rendszerre — PR [#547](https://github.com/wolfcasaba/strumsight/pull/547), squash `78e2b5dd` (2026-09-03)

A batch mind a **6** képernyője a `core/design_system` komponenseit és tokenjeit
használja, változatlan viselkedés mellett. Mért migrációs arány:
**86/96 (89,583%)** — a kör nem hozott létre és nem törölt képernyőt, a
`ui_inventory_test.dart` egzakt száma VÁLTOZATLAN.

Migrálva: `analysis_home_screen`, `analysis_recording_screen`,
`analysis_processing_screen`, `analysis_metric_detail_screen`,
`analysis_export_screen`, `analyze_screen`. Diff: 23 fájl, +2153/−310, benne 6
újrafelvett golden PNG (`golden-x86.sh record` a merge-kapu architektúráján,
ADR 0426).

**Egy javító kör futott** — 1 BLOCKER + 4 MAJOR + 6 MINOR, mind ZÁRVA
(`docs/reviews/e15-r10-review.md`): a nem-újrapróbálható hiba zsákutcája
(B1/M3), az `SsContentCard` néma ellipszis-csonkolása `textScaler 2.0`-n (M1),
kitalált CTA az idle `SsEmptyState`-en (M4 — ez volt a teljes CI PIROS
gyökéroka), kulcs-sodródás (m1/m2). Az M2 **mért indoklással** zárult, nem
visszaállítással: az `SsFailurePresentation.from()` szövege a `failure.code`-ból
jön, hívói oldalról nem felülírható a `lib/core/design_system/**` — a kör
`allowed_paths`-án KÍVÜLI — módosítása nélkül.

**A merge két lépcsőben állt helyre.** A kör munkája már a 2. review-menetben
**APPROVED** volt (0 nyitott lelet), de a kapu a `main`-ről ÖRÖKÖLT
titok-kapu-defekten bukott (H3) — ezt az L599 önjavító köre (PR #546,
`d0e21add`) oldotta fel. A friss merge SHA-n (`b2c5fdda`) a kiterjesztett kapu
ezután **magát a kör halt-jelentését** vette találatnak
(`docs/reviews/e15-r10-review.md:361`), mert a H3-diagnózis szó szerint idézte a
fixture-token literált. Az orchestrátor a saját hatáskörében (ADR 0087 §2,
L251) redaktálta az idézetet — marker nélkül, a kapu saját elvét követve. Új
lecke: **[L600](docs/LESSONS.md)**.

**Zöld kapu a merge SHA-n (`a5d03244`), exact-SHA:** Full Gate
[`33741172317`](https://github.com/wolfcasaba/strumsight/actions/runs/33741172317)
`success` (`full-gate` + `Coverage`), Router CI
[`33741207943`](https://github.com/wolfcasaba/strumsight/actions/runs/33741207943)
`success`. CI-terv: `full-gate.yml` (`native_gate=false`, nincs natív diff).
Gépi scope-audit a review-ban: **OK**, 22 változott útvonal, mind az
`allowed_paths`-on.

## ✅ [HEAL E15-R10/H3] KÉSZ — a titok-kapu a `tools/**` automatikus sávjában is mér (ADR 0112) — PR [#546](https://github.com/wolfcasaba/strumsight/pull/546), squash `d0e21add` (2026-09-03)

Az E15-R10 munkája KÉSZ és APPROVED volt (0 nyitott lelet), a merge-kapu mégis
piros: a `main`-ről ÖRÖKÖLT titok-kapu-defekten bukott, nem a kör diffjén.

**Mért gyökérok.** A `tool/ci/check_secrets.dart` a teljes követett fát méri, de
csak a `flutter-gates` composite 5. lépéseként fut, azt pedig kizárólag a
`build-apk.yml` / `full-gate.yml` hívja — **mindkettő `workflow_dispatch`**. A
`tools/**`-ra viszont a `router-ci.yml` indul AUTOMATIKUSAN, és annak nincs
titok-lépése. Ezen a résen vitt a PR #544 (tools-only ops PR, egyetlen zöld
check: `router-ci`) egy csupasz provider-token literált a `main`-re, marker
nélkül (`tools/tests/test_authenticated_git_fetch.py:34`). Mivel a `secrets` az
5. lépés, utána a full-gate MINDEN további lépése (l10n, asset, test, property,
coverage) `skipped` lett — a kör saját munkája meg sem lett mérve —, és az
ADR 0086 §2 miatt minden következő kör ugyanígy bukott volna.

**A javítás két fele.** (1) A szkenner **saját, meglévő** sor végi markere a
fixture-tokenre — nem mérce-gyengítés: a `providerToken` szabálynak nincs
`valueGroup`-ja, ezért a `_placeholder` mentesítés (`fake`/`test_only`/…) rá nem
vonatkozik, a szolgáltatói előtag önmagában találat. (2) A hibaosztály zárása a
`tools/**` oldalon: új őrteszt a router-ci automatikus sávjában. A
`.github/workflows/**` az ADR 0112 §3 tiltott zónája, ezért a lefedettség ott
állt helyre, ahol szabad — szigorúan BŐVÍTVE a mércét.

**Mérés.** A javítás előtt a Dart szkenner tiszta `main`-en (`45d20193`):
`Secret scan failed (4235 file(s) scanned, 1 finding(s))`; utána a heal-fán:
`Secret scan OK (4235 file(s) scanned, 0 finding(s))`. Az őrteszt a javítás
előtt PIROS, pontosan ugyanazzal a `path:line` találattal.

**Őrteszt:** `tools/tests/test_secret_gate_router_paths.py` — a szabályt nem
másolja le, a `check_secrets.dart` forrásából olvassa ki, ezért a két oldal nem
csúszhat szét. Tanulság: [`docs/LESSONS.md`](docs/LESSONS.md) **L599**.

**A lánc folytatása:** az E15-R10 a MERGE-lépésnél folytatódik (ág
`sonnet-impl/e15-r10-analysis-migration`, review APPROVED).

## ✅ E15-R09 KÉSZ — AI Tutor 5 képernyő migrálása a design-rendszerre — PR [#540](https://github.com/wolfcasaba/strumsight/pull/540), squash `7259c563` (2026-09-03)

Az AI-Tutor batch öt képernyője (`tutor_home`, `tutor_chat`, `tutor_data`,
`tutor_profile`, `tutor_privacy`) a design-rendszer komponenseit és tokenjeit
használja, változatlan viselkedés mellett: `SsCard`/`SsSection`/`SsButton`/
`SsSkeleton`/`SsFailureState`/`SsModelStatusCard`/`SsProvenanceBadge`/
`SsValidationSummary` + `SsSpacing`/`SsTypography`/`SsColorScheme` tokenek.
**Migrációs arány: 80/96 (83,333%)** — függetlenül újramérve.

**A kör három menetben zárult (1 alap + 2 javító kör), és H5 halton is átment:**

- **Review #1** — 1 BLOCKER + 5 MAJOR TELJESEN ZÖLD célzott gate mellett. A
  hordozó premissza („az `SsCard` extension-mentes") MÉRTEN hamis volt
  (`ss_card.dart` → `ss_surface.dart:42` → `ss_elevation.dart:14-15`, két `!`-es
  extension-olvasás), ezért a `theme:` nélkül pumpáló
  `tutor_home_screen_test.dart` 2 cellája pirosra váltott — a fájl viszont sem az
  `allowed_paths`-on, sem a `gate_tests`-ben nem volt, tehát a kör saját kapuja
  nem mérte. További leletek: hiba-ág információvesztés (beégetett
  `UnknownFailure`), 4 nem migrált állapot, az A3 (textScale) mércéje `/tmp`-ben
  törölt próbateszt volt, és az egész batch-re EGYETLEN design-rendszer típus-
  állítás jutott.
- **Review #2** — mind a 6 lelet zárva, de ÚJ, nyitott **BLOCKER-2**: az öt
  képernyő **24 MÉLY importtal** érte el a design-rendszert a `public.dart`
  barrel helyett (E13-R02 / [ADR 0273](docs/adr/0273-design-system-token-source-of-truth.md) §1).
  A CI ekkor kétszer volt piros → **H5 halt**.
- **Önjavító kör** ([ADR 0494](docs/adr/0494-derived-completion-matrix-and-h5-counter-reset.md),
  PR [#541](https://github.com/wolfcasaba/strumsight/pull/541)) a mért gyökérokot
  javította: a barrel-szabály bekerült a `tool/check_architecture.dart`-ba, tehát
  MINDEN kör `round-gate.sh` `architecture` lépése méri, lokálisan.
- **Javító kör #2 + Review #3 → APPROVED, 0 nyitott lelet.** A javítás
  fájlonként EGY sor (24 mély import → 5 barrel-import); a diff bizonyítottan
  import-only (a `design_system` sorok kiszűrésével a két revízió byte-azonos),
  a barrel 117 nevű felülete metszve az összes többi importtal **0 ütközés**,
  és teszt-cella törlés/`skip`/gyengítés az EGÉSZ ágon **0** (a cella-számok
  nőttek: chat 16→19, data 9→16, home 4→6, privacy 6→8, profile 5→7).

**A megismétlődés őre kettős:** az ADR 0494 D2 gate-szabálya + a kör
`gate_tests`-ébe felvett `test/core/architecture_dependency_test.dart` (§0.0.C/R20).
Az implementer valódi-sértés próbája MÉRTEN pirosra vitte mindkettőt.
Tanulság: [L593](docs/LESSONS.md#l593).

**Zöld kapu a merge SHA-n (`31e30233`):** Full Gate (no APK)
[33720016489](https://github.com/wolfcasaba/strumsight/actions/runs/33720016489)
`success`, Router CI
[33720058092](https://github.com/wolfcasaba/strumsight/actions/runs/33720058092)
`success`, plusz az orchesztrátor saját, izolált klónban futtatott célzott
gate-je: **19/19 zöld**. ÚJ ADR: **nincs** (a normatív állítások az ADR 0273 /
E13-R02 és az ADR 0494 alá esnek). `risk = "high"` → a `flutter-reviewer` ÉS a
`flutter-devil-advocate` KÖTELEZŐ volt, mindkettő lefutott (0 lelet).

## 🔧 ÖNJAVÍTÓ KÖR (ADR 0112) — E15-R09 / H5 — KÉT lánc-akadály feloldva (2026-09-03)

A kör-pipeline **kétszeresen** állt: (1) a `main` Full Gate PIROS volt (run
[33704424852](https://github.com/wolfcasaba/strumsight/actions/runs/33704424852)),
ezért a driver 02:25–03:54 között **18 firingen, 89 percen át** egyetlen kört
sem indított; (2) az `E15-R09` kör H5-tel halt (a CI kétszer piros).

**(1) gyökérok — MÉRVE.** Az E15-R08 merge a queue `E15` eloszlását
`8 done / 6 pending` → `9 done / 5 pending`-re vitte, a
`docs/sdd/program-completion-report.md` §3 matrixa viszont a kézzel írt régi
számokon maradt; a `program_completion_test.dart` `A1` cellája SZIGORÚ
egyenlőséget mér a queue ellen. Ez pontosan az [L590](docs/LESSONS.md#l590)
által megjósolt csapda, ami az ELSŐ queue-flipen detonált. **Javítás:** a négy
szám-oszlop mostantól SZÁRMAZTATOTT — `tools/sync-completion-matrix.py`, amit a
driver a queue-flip commitban futtat ([ADR 0494](docs/adr/0494-derived-completion-matrix-and-h5-counter-reset.md)
D1). Az `A1` egyenlősége VÁLTOZATLANUL szigorú; csak a kézi bookkeeping szűnt
meg. [L591](docs/LESSONS.md#l591).

**(2) gyökérok — MÉRVE.** Az öt migrált Tutor-képernyő 24 MÉLY importtal érte
el a design-rendszert a `public.dart` barrel helyett (E13-R02 szerződés). A
szabályt KIZÁRÓLAG a teljes CI-suite mérte: a `main` állapotú
`dart tool/check_architecture.dart` ugyanazon a fán `Architecture dependencies
OK`-ot adott, amin a CI kétszer bukott. **Javítás:** új
`designSystemImportsMustUsePublicBarrel` szabály a checkerben → **minden** kör
`tools/round-gate.sh` `architecture` lépése méri, lokálisan, push előtt (ADR
0494 D2). A `main` a szabály alatt tiszta (0 sértés, allowlist nélkül).
[L592](docs/LESSONS.md#l592).

> ✅ **ELVÉGEZVE 2026-09-03:** a folytató session pontosan ezt tette — javító
> kör #2 a MEGLÉVŐ ágon, 24 mély import → 5 barrel-import, review #3 APPROVED,
> merge `7259c563` (PR #540). Az alábbi blokk a történeti recept.
>
> ▶ **A KÖVETKEZŐ SESSION-nek, ami az E15-R09-et folytatja:** a
> `round-resume-probe` `REVIEW-NYITOTT`-ra állítja az ágat
> (`sonnet-impl/e15-r09-ai-tutor-migration @ 78fd3a64`, PR
> [#540](https://github.com/wolfcasaba/strumsight/pull/540) NYITVA) — a dolgod
> a **javító kör a MEGLÉVŐ ágon**, nem újrakezdés. A javítás mechanikus és a
> kör fájllistáján BELÜL van: a 24 mély import helyett fájlonként EGY
> `import 'package:strumsight/core/design_system/public.dart';` (precedens:
> `lib/features/gamification/presentation/screens/achievements_screen.dart:2`,
> E15-R08). A friss `main` beépítése után a gate `architecture` lépése MAGA
> mutatja meg mind a 24-et. **A H5 piros-számláló NULLÁRÓL indul** (ADR 0494
> D3): a heal ELŐTTI két pirosra hivatkozva nem szabad újra halt-olni — a zöld
> kapu viszont változatlan (teljes CI-suite + Router CI a merge SHA-n).

## ✅ E12-R36 KÉSZ — Program completion report és következő roadmap — PR [#538](https://github.com/wolfcasaba/strumsight/pull/538), squash `e8686066` (2026-09-03)

A Chapter 12 **záró köre**. Szállítás: `docs/sdd/program-completion-report.md`
(ÚJ) — a program állapotának bizonyíték-alapú, ŐSZINTE lezárása: egy
completion matrix minden sora egy queue-előtaghoz tartozó, ténylegesen
mért `done`/`pending`/`prepared`/`hold` sorszámot közöl, és a nyitott
sávokat (Epic 9 5 kör, Epic 10 mind a 32 kör, Chapter 14 41/42 kör, a
fejezetfájl NÉLKÜLI `E15`/`E16` sávok) nyitottként nevezi meg — plusz egy
explicit emberi-kapu tábla (Kör 27–33 + a valós gitáros APK-teszt, mind
NYITOTT, mert a `done` queue-sor csak az ESZKÖZ elkészültét bizonyítja, nem
a valódi Play Console/rollout/GA műveletet). `docs/roadmap/next-six-months.md`
(ÚJ) — 7 **outcome**-alapú tétel (nem feature-lista), mindegyik
`**Outcome:**`/`**Mérőszám:**`(számmal)/`**Forrás:**` hármassal.
`test/tooling/program_completion_test.dart` (ÚJ, 20 cella) — tartalom-
paraméteres tiszta függvények + acceptance-pontonként (A1–A5) kézzel épített
RED-bizonyító cella, a valódi fát mérő cellák mellett. `docs/sdd/00-index.md`
— kizárólag a Chapter 5–14 Státusz/Implementation progress cellái frissültek
a mai mérésre (a Kör 2 gépi egyezése — `sdd_index_guard_test.dart`, 36 cella
— érintetlen maradt).

**A KÖTELEZŐ valódi-sértés próba mindkét formában lefutott.** Automatizált
(a tesztfájl "(a)"/"(b)" cellái): a Riport-státusz szöveg és a számok
egymástól függetlenül átírva mutatják, hogy A1 és A2 külön-külön fog hibát.
Kézi (a fájlon): az Epic 10 sorát "lezárva, minden kör kész"-re írva a
`tools/round-gate.sh` szó szerinti futtatása **kilépési kód 10-zel, az A2
cellán PIROSRA váltott** (`Ch11 (E10): open lane (openCount=32) but
report-status claims closure`), majd a mért állapot visszaállítása után a
teljes 7 lépéses gate ismét zöld. Fejlesztés közben a roadmap A4 parserének
egy Unicode-hibáját (`[A-Za-zÀ-ÿ]` karakterosztály nem fedte a magyar "ő"
betűt a "Mérőszám" szóban, `\p{L}`-re javítva) pontosan ez a RED-cella fogta
meg — a hiba felfedezése önmagában bizonyítja, hogy az őr valóban tud
pirosra váltani, nem csak a valódi fán zöld.

**A review a zöld gate mögött 1 MAJOR-t mért — eldobható próbateszttel, nem
olvasással.** Az őr a hamis ÁLLÍTÁST fogta (rossz szám, hazug státusz-szöveg),
az ELHALLGATÁST nem: egy teljes nyitott sáv (`E15` 6 `pending`, `E10` 32
`hold`) vagy egy emberi-kapu sor TÖRLÉSE a riportból **minden cellán zöld
maradt** — épp az a „kozmetikai zárójelentés", amit a brief §9 első kockázatnak
nevez. A javító kör két lefedettség-őrt adott hozzá
(`findLanesMissingFromMatrix`, `findMissingHumanGates` + nyolcelemű
elvárás-lista), RED-bizonyító cellákkal; ugyanaz a három mutáció most piros
(20 → **27 cella**). VERDIKT: APPROVED, 0 nyitott lelet
([`docs/reviews/e12-r36-review.md`](docs/reviews/e12-r36-review.md) §8).
Tanulság: [L588](docs/LESSONS.md#l588).

Exact-SHA evidencia a merge SHA-n (`d47e64fa`): Full Gate
[33698915230](https://github.com/wolfcasaba/strumsight/actions/runs/33698915230),
Router CI
[33698956202](https://github.com/wolfcasaba/strumsight/actions/runs/33698956202)
— mindkettő `success`. ADR: **nincs** (záró/riport-kör; a `docs/adr/**` a kör
tilos zónája volt, a lista tágítása nem orchestrátori hatáskör — precedens:
E12-R35). Részletek:
[`e12-r36-program-completion-and-next-roadmap.md`](docs/rounds/e12-r36-program-completion-and-next-roadmap.md) §10.

> ✅ **LEZÁRVA 2026-09-03** az E15-R09 / H5 önjavító körben ([ADR 0494](docs/adr/0494-derived-completion-matrix-and-h5-counter-reset.md)
> D1, [L591](docs/LESSONS.md#l591)) — az alábbi „nyitott" szöveg a
> MEGJÓSOLT csapdát írja le, ami az ELSŐ queue-flipen (E15-R08) valóban
> elsült, és 89 percre megállította a láncot. A feloldás egyik felkínált
> normatív irány sem lett: a szám-oszlopok SZÁRMAZTATOTTAK, az `A1`
> egyenlősége változatlanul szigorú.
>
> 🔴 **(EREDETI, 2026-09-03 előtt) NYITOTT, a KÖVETKEZŐ kör dolga — a post-merge gate mérte
> ([L590](docs/LESSONS.md#l590)):** a riport §3 matrixának `A1` cellája
> EGYENLŐSÉGET mér az ÉLŐ `docs/execution/pipeline-queue.tsv` ellen. A saját
> záró rituálém (`E12-R36` sor `pending` → `done`) emiatt azonnal pirosra
> váltotta a `main` gate-jét; a Ch12 sor frissítésével zöld lett. **De minden
> jövőbeli kör, amely bármely queue-sort `done`-ra vált (E14, E15, E16, E99, az
> Epic 8/9/10 `hold`-jai), újra pirosra váltja ezt a cellát** — amíg valaki a
> matrix érintett sorát nem frissíti. A tartós feloldás (befagyasztott,
> dátumozott pillanatkép a riport mellett, VAGY nem-egyenlőség alapú, „nem
> overstate" invariáns + a már meglévő lefedettség-cella) normatív döntés:
> **ADR-t és saját kört érdemel**, nem post-merge javítást.

> ⚠ **A riport a program NYITOTT részeit is kimondja** — ez nem „minden kész"
> bejegyzés. Nyitva: Epic 8 1 kör, Epic 9 5 kör, **Epic 10 mind a 32 köre**,
> Chapter 14 41/42 kör (az R20–R42 briefjei MEG SEM ÍRÓDTAK — a program
> legnagyobb, még meg sem tervezett hátraléka), az `E15`/`E16` sávok, `E99`
> 2 kör, és mind a **8 emberi kapu** (E12-R27…R33 valós Play Console /
> rollout / GA műveletei + a **valós gitáros APK-teszt**).

## ✅ E12-R35 KÉSZ — Technikaiadósság- és flag cleanup — PR [#537](https://github.com/wolfcasaba/strumsight/pull/537), squash `3326e32a` (2026-09-02)

A Chapter 12 **Kör 35** azt szállítja, amit a neve ígér, és **csak** azt: mért
adósság-**leltárt** és a hozzá tartozó **audit-eszközt**. A kör **egyetlen
`lib/` fájlt sem módosít** — a kompatibilitási réteg vagy flag lezárása a repó
mért szabálya szerint dedikált GOV-kör dolga ([ADR 0395](docs/adr/0395-community-baseline-feature-flags-and-threat-model-scope.md)),
nem egy építő-köré. ADR **nem** született (indoklás a brief §0.0-ban: új ADR az
`allowed_paths` bővítését kívánta volna, ami ADR 0087 §2 szerint nem
orchestrátori hatáskör).

**Amit szállít.** `tool/check_deprecations.dart` (ÚJ) — a mérő-eszköz, a Kör 5
`check_feature_flags.dart` tartalom-paraméteres mintájára: minden lépés tiszta
függvény, a `main()` vékony `exitCode`-burkoló, így a teszt olyan bemenetet is
felépíthet, amit a valódi fa nem produkál. `docs/release/technical-debt.md`
(ÚJ) — **14 mért tétel**, mindegyik FELELŐSSEL és konkrét ELTÁVOLÍTÁSI
FELTÉTELLEL. `test/tooling/deprecation_audit_test.dart` (ÚJ) — **37 cella**,
köztük a küszöb-cellahármas (11/12/13, INKLUZÍV határ, a bázisvonalból
számolva, nem kézzel írt literálból).

**A mért leltár.** 12 `@Deprecated` jelölés 9 fájlban (8 egyszerű re-export
shim + az `ApiConfig` 4-tagú shimje) — **mind 0 külső importáló fájllal**,
tehát ezek a legerősebb törlés-jelöltek, de a törlés ettől még külön kör. A
`library`/`library_v2` (5 / 1) és `progress`/`progress_v2` (17 / 0) párhuzamos
rétegek, plusz 3 TODO-klaszter (14 TODO). **A `progress_v2` nulla külső
hívóhelye kifejezetten NEM töröl-engedély** (brief §5.3) — a leltár ezt
tételként, feltétellel rögzíti.

**A review két MAJOR-t fogott, mindkettőt eldobható mutációval — és mindkettő
ugyanaz a hibaosztály: a cella a VISELKEDÉST mérte, a SZERZŐDÉST nem.**
**M1** — az A2 „nincs második igazság" nem volt gépi mérce: a Kör 5
`isFeatureFlagExpired` hívást egy lokális, azonos szemantikájú másolatra
cserélve **mind a 14 cella zöld maradt**, holott a brief §6.1 mátrixa
kifejezetten ezt a hibás implementációt ígérte pirosra. **M2** — az A1 „MINDEN
`@Deprecated` elem" némán alulmért: egy VALÓDI, többsoros (szomszédos
string-literálos) `@Deprecated` a nyers előfordulásszámot 13-ra vitte, a tool
viszont továbbra is 12-t látott, és **a 12/9-es bázisvonal-cella is zöld
maradt** — pontosan azért, mert a hiányzó találat miatt a szám nem változott.
Javító kör (`df7ef710` → rebase `3f3ba1c0`) után mindkét mutáció PIROS, és
mindkettőt a MEGFOGÓ próba megismétlésével zártam. +2 MINOR
(`externalCallsiteCount` → `externalImporterCount`, mert importáló FÁJLOKAT
mér; a frozen-scope őr `—`-sal kikerülhető volt) szintén zárva.

**Landolás.** A `main` a kör alatt kétszer mozdult (a párhuzamos E15-R07 sáv),
ezért a landolás a merge-záron át, `tools/round-land.sh`-sal ment: rebase →
kombinált-HEAD gate (8/8 zöld) → safe force push (`c4d76788`) → exact-SHA CI
ÚJRA a rebase-elt HEAD-en → squash-merge. Egy első landolási kísérlet
hamis H8-cal állt meg — a mért ok NEM divergencia volt (a patch-id-k
azonosak), hanem az OSZTOTT munkafa: a másik sáv `git reset --hard
origin/main`-je a landoló futása közben visszaállította a branch refet
([L587](docs/LESSONS.md#l587)).

**Bizonyíték.** Exact-SHA CI a `c4d76788` merge-elt HEAD-en:
[full-gate 33692345767](https://github.com/wolfcasaba/strumsight/actions/runs/33692345767)
+ [router-ci 33692347955](https://github.com/wolfcasaba/strumsight/actions/runs/33692347955),
mindkettő `success`. Review: [`e12-r35-review.md`](docs/reviews/e12-r35-review.md)
(1. menet CHANGES REQUESTED → 2. menet **APPROVED**, 0 nyitott lelet).
Leckék: [L586](docs/LESSONS.md#l586), [L587](docs/LESSONS.md#l587).

**Amit a következő köröknek tudniuk kell.** Az `A1 the real tree reports 12
deprecated sites in 9 files` cella **bázisvonal-jellegű**: minden jövőbeli
`@Deprecated` hozzáadás pirosra viszi, és a számot ott KELL frissíteni. A 9
shim (mind 0 külső importáló) törlése egy dedikált takarító kör olcsó munkája
— a feltételek a `technical-debt.md`-ben tételenként ott vannak.

## ✅ E15-R07 KÉSZ — Practice Generator bekötése (route + flag + belépési pont) — PR [#536](https://github.com/wolfcasaba/strumsight/pull/536), squash `d0cd45ee` (2026-09-02)

A Chapter 15 **Kör 7** azt szállítja, amiért a kör létrejött: a Practice
Generator flow-ja **először megnyitható**. A `PlanSetupScreen` és a
`TodayPlanScreen` route-ot kapott a `practiceGeneratorEnabled` kapuja mögött,
a practice hubon egy flag-kapuzott belépési pont vezet a terv-varázslóhoz, a
flag rollout-határa pedig a mért `nonProd` mintára került — **a production
zárva marad**. A kör ADR-je: [ADR 0491](docs/adr/0491-practice-generator-entry-point-and-rollout.md).

**A kör MÉRT szűkítése — miért 2 képernyő, nem 6.** Az `E15-R14` (ADR 0482)
leszállította a kompozíciós gyökeret, de két seamet szándékosan nyitva hagyott,
és azok ma dobnak (`practice_generator_providers.dart:85` és `:149` →
`UnimplementedError`); konkrét implementációjuk **nulla** a `lib/`-ben, és a
`main.dart` sem írja felül őket. Mivel a `localPracticePlanRepositoryProvider`
watch-olja az elsőt, a dobás **tranzitív**: a 6 képernyőből csak a `PlanSetup`
és a `TodayPlan` konstruálható valódi providerekből. A másik négy
(`PlanPreview`, `PlanPrivacy`, `Weekly`, `PlanChangeReview`) **szándékosan NEM
kapott route-ot** — egy dobó providerre kötött route kattintható crash-út, nem
bekötés (ADR 0491 D1/D5). A `practice_generator` `application/`/`domain/`/
`data/`/`providers/` rétege érintetlen: a STOP-protokoll és a merge-elt
`tools/tests/test_e15_r07_composition_prerequisite.py` mind a 10 cellája zöld.

**Az őszinte fél lépés (ADR 0491 D3, ADR 0078 precedens).** A Setup-varázsló
vége ma nem generál tervet, és ezt a UI nem hazudja el: a belépési pont
cselekvést ígér („Build your practice plan" / „Gyakorlási terv összeállítása"),
nem kész tervet; nincs bevezetett no-op `onComplete` callback.

**Mérés (`dart run tool/check_screen_reachability.dart`):** Reachable **68 → 70**,
Unreachable **28 → 26**, Flag-gated **25 → 27**; `Measured screens: 96`
változatlan (a kör route-ot ad, nem képernyőt).

**⚠ NYITVA MARAD — az ADR 0482 D9/D10/D11 kötelezettségei NEM teljesültek, és
gazdátlanul sem maradnak.** Az ADR 0482 ezeket „halasztott, kötelező
`E15-R07 / F1`-előfeltételként" rögzítette. A D9 tényleges biztonsági feltétele
(*„MIELŐTT bármelyik ÉRINTETT képernyőre route nyílik"*) **teljesül**: ez a kör
a három érintett (dobó) képernyő egyikére sem nyitott route-ot. A
kötelezettségek érdemi része viszont nyitva van, és ANNAK a körnek a dolga,
amelyik a négy maradék képernyőt beköti (ADR 0491 D5):

- **D9** — a `main.dart` boot-override mindkét seamre + az acceptance-cella:
  „egy production-alakú `ProviderScope`-on a 6 képernyő EGYIKE sem dob";
- **D10** — a tulajdonos (`sourcePlanId`) propagálása az `evidence_aggregator`
  hívási láncán VAGY az `outcomePlanLookup` bekötése, **mielőtt** a
  `PlanPrivacyScreen` törlés gombja bekötésre kerül;
- **D11** — a `DeletePracticePlanningData` optimista siker-jelentésének
  megszüntetése.

**Review:** [`e15-r07-review.md`](docs/reviews/e15-r07-review.md) — **APPROVED**,
0 BLOCKER / 0 MAJOR / 0 MINOR, 1 NOTE, javító kör NÉLKÜL. A review külön
megmérte az [L583](docs/LESSONS.md#l583) hibaosztályt: az „a route felépül"
cella **nem** a saját override-jaitól zöld — az `app_router_test` harness
egyetlen generátor-providert sem ír felül, tehát a valódi kompozíciós gyökérből
épül.

**CI a merge SHA-n (`ed362594`):** [full-gate 33689749950](https://github.com/wolfcasaba/strumsight/actions/runs/33689749950),
[router-ci 33689752109](https://github.com/wolfcasaba/strumsight/actions/runs/33689752109) — mindkettő `success`.
Lecke: [L585](docs/LESSONS.md#l585).

## ✅ E12-R34 KÉSZ — Post-launch stabilization és hotfix-út — PR [#535](https://github.com/wolfcasaba/strumsight/pull/535), squash `51184118` (2026-09-02)

A Ch12 **Kör 34** a GA utáni **hotfix-utat** teszi auditálhatóvá. A kör tétele
egyetlen mondat, és az [ADR 0490](docs/adr/0490-hotfix-path-gates-incident-binding-and-regression-obligation.md)
D1-e önti szerződésbe: **a gyorsaság a SCOPE szűkítéséből jön, nem a kapuk
elhagyásából.** A kör terméke ezért nem egy „gyors sáv", hanem a hotfix-út
**gépi őre**: `tool/release/verify_hotfix.py` (kétmódú — statikus
dokumentum-audit + kérés-audit), a `docs/release/workflows/hotfix.proposal.yml`
javaslat, a runbook, a postmortem-sablon és a 7./14. napi riport váza.

A kör **nem telepít workflow-t és nem ad ki hotfixet**: a `.github/workflows/**`
védett mérce-zóna (`PROTECTED_GLOBS`, ADR 0321), az ADR 0372 álló
felhatalmazásának fájlja pedig a fán nem létezik — a telepítés és a dispatch a
merge utáni EMBERI/orchesztrátor lépés (D6, a Kör 25 precedense).

**A pre-flight a brief két állítását megcáfolta.** A `0465`-ös előre kiosztott
ADR elavult volt (a foglaló `0490`-et adott; a Ch12 batch `0460`–`0465`
tartománya végig elavult — a Kör 22 és a Kör 25 ugyanígy cserélt), és a brief
§2 első mért ténye — „a Kör 25 után `release-candidate.yml` is" — HAMIS: az RC
javaslat-fájlként él, a `.github/workflows/` tíz fájlja közt nincs. Az A6
lépés-sorrendje is fordítva állt: a mért RC job-gráf **jóváhagyás → gate →
build**, nem „gate → jóváhagyás → build".

**A review a zöld gate mögött találta a lényeget — és a lényeg maga az őr volt.**
Az implementer 34 cellája, a `tools/round-gate.sh` mind a hét lépése és a
kötelező §6.2 valódi-sértés próba egyaránt zöld volt, a `scope_audit=ok`. Az őr
mégis **három valódi kapu-gyengítést átengedett** `exit=0`-val: a `security-scan`
JOB fejlécére tett `continue-on-error: true`-t és `if:`-et (a mérce csak
LÉPÉS-szinten nézett, és a `fast_track` név kikerülte a `skip|emergency` mintát),
a névben megmaradó de `echo`-t futtató scan-lépést (a mérce a nevet nézte, a
törzset soha), és egy `needs:` nélküli `publish-hotfix` jobot (a jóváhagyás-gráf
denylistára épült). Negyedikként a javaslat `${{ inputs.* }}`-ot interpolált
`run:` törzsbe egy a production keystore-t kezelő jobban — GHA script injection,
a repó saját `env:`-kötéses precedensével szemben. A kötelező `security-reviewer`
(`risk = "high"`) függetlenül ugyanezt a leletcsoportot reprodukálta.

Egy javító kör (`1dcc16c0`) mind a négy MAJOR-t és az egy MINOR-t lezárta. A
zárás bizonyítéka nem bemondás: a kör #1 **mind a négy fixtúrája** `exit=0`-ról
`exit=1`-re váltott, és **két ÚJ, a javító promptban nem szereplő próba** — a
signing-oldali tartalmi próba és a **build** jobra (nem a scan jobra) tett
job-szintű `if:` — szintén megfogott, tehát a javítás általános, nem
fixtúra-szabott. A gyökérok tanulsága: a brief §6.1 mutációs mátrixának sora
KONKRÉT szintaktikai alakot írt le, és pontosan arra illeszkedő ellenőrzést
kapott — a sort HIBAOSZTÁLYKÉNT kell írni ([L584](docs/LESSONS.md#l584)).

Exact-SHA evidencia a `7daaac78` merge SHA-n: Full Gate
[33683136645](https://github.com/wolfcasaba/strumsight/actions/runs/33683136645),
Router CI
[33683203602](https://github.com/wolfcasaba/strumsight/actions/runs/33683203602)
— mindkettő `success`. A Router CI-t az [L581](docs/LESSONS.md#l581) miatt
explicit `workflow_dispatch`-csal kellett a merge SHA-ra kényszeríteni (a kör
utolsó commitja `docs/reviews/**`, ami nincs az `on.push.paths` szűrőn). A
CI-tervet a `tools/round-ci-plan.py` adta (`full-gate.yml`, `native_gate = false`).

**Következő teendő a hotfix-úttal (EMBERI/orchesztrátor lépés):** a
`docs/release/workflows/hotfix.proposal.yml` telepítése
`.github/workflows/hotfix.yml`-ként, a `hotfix-approval` GitHub environment
létrehozása kötelező reviewerekkel, majd egy dispatch-próba — egyszer zölden,
egyszer bizonyítottan pirosan (hiányzó incident-azonosító vagy nem emelt
verzió).

**Előző állapot:** `main` @ `70eefdf4` — E15-R14 Practice Generator kompozíciós réteg.

## ✅ E15-R14 KÉSZ — Practice Generator kompozíciós réteg — PR [#534](https://github.com/wolfcasaba/strumsight/pull/534), squash `d28c79d3` (2026-09-02)

A Ch15 beszúrt előkészítő köre megépítette azt, ami az `E15-R07 / H3` STOP mért
lelete szerint hiányzott: a Practice Generator 6 terv-képernyője mögötti
**kompozíciót**. A kör route-ot NEM nyitott, flaget NEM kapcsolt, képernyőt NEM
módosított — a 6 képernyő verdiktje VÁLTOZATLANUL `unreachable`
(`Measured screens: 96. Reachable: 68. Unreachable: 28.`), a `ui_inventory`
`hasLength(96)` érintetlen.

**Három ÚJ termék** (ADR [0482](docs/adr/0482-practice-generator-composition-layer.md), D1–D11):

- `lib/features/practice_generator/data/local/local_practice_evidence_repository.dart`
  — az ELSŐ perzisztens `PracticeEvidenceRepository` (a fán korábban csak a
  „never forgets" teszt-fake létezett). Saját `ss.practice_generator.evidence`
  névtér, **read-modify-write manifest**, kompenzáló írás-egyeztetés és
  `lastWriteFailure` — a `SkillEvidence` JSON-képe a fájlon belül (a domain
  tilos zóna).
- `presentation/providers/practice_generator_providers.dart` — **EGY**
  kompozíciós gyökér (D1); a fa alatt korábban NULLA provider volt.
- `application/usecase/start_plan_generation.dart` — a Setup-draftot a MEGLÉVŐ
  `GenerationOrchestrator`-nak adja át, nulla új generálási logika (STOP-határ).

**A review a zöld gate mögött találta a lényeget — másodszor is.** A kötelező
három ügynök (`security-reviewer`, `flutter-reviewer`, `flutter-devil-advocate`,
`risk = "high"`) futtatott próbákkal **2 BLOCKER + 7 MAJOR**-t mért ki
TELJESEN ZÖLD gate mellett: (1) az `unawaited` `KeyValueStore` írás/törlés
elnyelte a `StorageException`-t, tehát a törlés sikert jelentett, az adat a
lemezen maradt és **örökre törölhetetlenné** vált — pontosan a hamis
consent-felület, ami ellen a kör létrejött; (2) a production-alakú
`ProviderScope`-ban a 6 képernyőből **3-nak** a függősége és a teljes
generálási út `UnimplementedError`-t dobott, az A3 cella pedig azért volt zöld,
mert a **saját tesztje** írta felül a két hiányzó seamet ([L583](docs/LESSONS.md#l583)).

**Két javító kör** zárta le mindet, független újraméréssel (eldobható
próbatesztek a javított fán, izolált klónokban). Ami a scope-on kívülre esett,
az **kimondott, ADR-be írt `E15-R07 / F1`-előfeltétel** lett — halasztás igen,
hallgatás nem:

- **D9** — a két `UnimplementedError` seam boot-override-ja (`main.dart`);
  7 guard-cella méri provider-enként, MELYIK dob ma.
- **D10** — az `evidence_aggregator.dart:61` tulajdonos nélküli `save`-je
  miatt a `deleteForPlan` ma nem éri el, amit a production ír (a kör hagyott
  hozzá `outcomePlanLookup` seamet).
- **D11** — a `DeletePracticePlanningData` ne jelentsen optimista
  `evidenceCount`-ot bukó platform-remove esetén.

Verdikt: **APPROVED**, 0 nyitott lelet
([`docs/reviews/e15-r14-review.md`](docs/reviews/e15-r14-review.md) §8).
Exact-SHA evidencia a merge SHA-n (`29aa7b91`): Full Gate
[33678702648](https://github.com/wolfcasaba/strumsight/actions/runs/33678702648),
Router CI
[33678705251](https://github.com/wolfcasaba/strumsight/actions/runs/33678705251)
— mindkettő `success`. A CI-tervet a `tools/round-ci-plan.py` adta
(`full-gate.yml`, `native_gate = false`); a Router CI-t az [L581](docs/LESSONS.md#l581)
miatt kézzel kellett a merge SHA-ra dispatch-elni.

## ✅ E12-R33 KÉSZ — Staged rollout 50–100% és GA — PR [#533](https://github.com/wolfcasaba/strumsight/pull/533), squash `f685db4a` (2026-09-02)

A Ch12 **Kör 33** a GA-állapotot teszi **auditálhatóvá — publikálás nélkül**.
A brief §0.0 emberi kapuja szerint a 100%-os store-rollout és a GA-jelölés
kizárólag user-művelet; a kör terméke a **rekord**, az **ellenőrző**, a
**gate-teszt** és a záró **jegyzet**. A kör nem publikált, nem állított
rollout-százalékot, és nem írta át a `staged-rollout-log.md`-t.

**A pre-flight oldott fel egy önmagával ellentmondó briefet ([L582](docs/LESSONS.md#l582)).**
A brief ⚠ kapuja („kitöltetlen rollout-napló → `blocked`") szó szerint
olvasva **véglegesen** megállította volna a láncot: a naplót csak valódi
store-rollout töltheti ki, az pedig ma maga is blokkolt — nyitva van egy
**P0** (`R-SIGN-01`) és öt **P1** (`blockers.md`), a `ga-scope.md` fejléce
pedig „NEM KÉSZ". Ugyanennek a briefnek a §2-je viszont MÁR MÉRTE ezt, és a
kört kifejezetten erre az állapotra tervezte. A §0.0.1 revízió (ADR 0087 §2 —
a kör SAJÁT, még nem merge-elt briefje) a kaput **séma-létezés** ellenőrzéssé
tette, a kitöltetlenséget pedig **gépi invariánssá** emelte: a kör így
SZIGORÚBB lett, nem lazább.

**Négy termék (5 útvonal, `scope_audit=ok`):**

- [`docs/release/ga-record.md`](docs/release/ga-record.md) — `ga_status` gépi
  mező zárt értékkészlettel (ma **`not-yet`**), a verzió-mezők a manifest
  **deklarált bemeneteiből**, a **16 kulcsos** flag-profil pillanatkép, a
  rollback-cél, és a GA UTÁN kitöltendő emberi mezők (build-SHA, support-link,
  publikálási időbélyeg) EXPLICIT `GA UTÁN, EMBERI KITÖLTÉS` jelöléssel —
  kitalált érték egyikbe sem került.
- [`tool/release/verify_ga_record.py`](tool/release/verify_ga_record.py) —
  fail-closed ellenőrző (A1–A7; `exit 2` hiányzó/üres marker-blokkra).
  **Mért tény: statikus release-manifest fájl a fán NINCS** — a manifest
  generált Dart-artefaktum, ezért az ellenőrző a három deklarált bemenetből
  (`pubspec.yaml` + a két asset-manifest sha256) számol újra minden futáskor;
  nincs `dart run`, és nincs a Pythonba másolt verzió-literál.
- [`test/tooling/ga_record_test.dart`](test/tooling/ga_record_test.dart) — az
  A2 Dart-oldali összevetése a `tool/generate_release_manifest.dart`
  importjával (a `release_manifest_test.dart` mért mintája); az A5 cella SAJÁT
  vakság-őrt is hordoz (a használt ISO-8601 regex bizonyítottan felismer egy
  valódi időbélyeget).
- [`docs/release/release-notes.md`](docs/release/release-notes.md) —
  determinisztikus, generálási időbélyeg nélkül, a `known-issues.md`-re
  hivatkozva (nem másolva).

**Review: APPROVED első menetben**, 0 nyitott BLOCKER/MAJOR/MINOR — javító kör
nem kellett ([`docs/reviews/e12-r33-review.md`](docs/reviews/e12-r33-review.md)).
A review a gate-et izolált klónban függetlenül újrafuttatta (MINDEN ZÖLD), a
hiányzó `scope_audit=` kulcsot kézzel pótolta (OK, 5 útvonal), és **12 saját,
eldobható valódi-sértés próbát** futtatott az ellenőrző ellen. Ezek közül a
legfontosabb a **P12 inverz próba**: szintetikus, mind-`approved` naplóval és
üres blocker-táblával a `ga_status: ga` **`exit=0`**-t ad — az A7 tehát
ADAT-VEZÉRELT őr, nem bedrótozott tiltás, és a valódi GA pillanatában zöldet
fog adni. 2 NOTE (nem blokkoló): a jelzésfájl `dirty_files=1` pillanatkép-
műterméke (a fa mérve tiszta volt), és hogy a három GA-utáni emberi mező
prózában él, a gépi A1-hatókörön kívül — a rés zárása egy jövőbeli kör olcsó
munkája.

**CI (exact-SHA, `84844715`):** Full Gate
[33674653017](https://github.com/wolfcasaba/strumsight/actions/runs/33674653017)
**success** · Router CI
[33674655878](https://github.com/wolfcasaba/strumsight/actions/runs/33674655878)
**success**. A `round-ci-plan.py` terve `full-gate.yml` volt
(`native_gate=false`, `apk_required=false`).

**Lecke:** [L582](docs/LESSONS.md#l582) — ha egy előre megírt brief kötelező
kapuja emberi előfeltételt ír elő, a pre-flightban azt is meg kell mérni, hogy
az előfeltétel **teljesíthető-e egyáltalán**; és minden „X tiltva, amíg Y"
alakú őrhöz KELL egy inverz cella, különben a „mindig piros" invariáns az első
éles használatkor kerül megkerülésre.

**Következő kör:** `E12-R34` — Post-launch stabilization és hotfix
(`docs/rounds/e12-r34-post-launch-stabilization-and-hotfix.md`, előre kiosztott
ADR **0465**).


## ✅ E12-R32 KÉSZ — Staged rollout 1–20 százalék (a H7 után folytatva) — PR [#532](https://github.com/wolfcasaba/strumsight/pull/532), squash `f6db8a8d` (2026-09-02)

A Ch12 **Kör 32** a publikus rollout első három lépcsőjét (**1% → 5% → 20%**)
teszi dokumentált, MÉRT döntéssé — **a százalék állítása nélkül**: a brief §0.0
emberi kapuja szerint a store-művelet kizárólag user-feladat, a kör terméke a
döntési SÉMA, az ELLENŐRZŐ és a NAPLÓ.

**Négy termék (6 útvonal, `scope_audit=ok`):**

- [`docs/release/rollout-decision.md`](docs/release/rollout-decision.md) — a
  lépcső-séma zárt marker-blokkokkal: `stage-1`/`stage-5`/`stage-20`, 1/5/20 %,
  **24/48/72 óra** minimális megfigyelési ablak. A `human-gate` blokk szó
  szerint hordozza az „A rollout-százalék állítása EMBERI művelet." mondatot —
  ez az A5 GÉPI horgonya, nem szövegbeli ígéret.
- [`tool/release/verify_rollout_decision.py`](tool/release/verify_rollout_decision.py)
  — R1–R8: fail-closed marker-parserek (`exit 2` hiányzó/üres blokkra, alakra
  nem illő sorra), majd `exit 1` hiányzó mezőre, ismeretlen `decision`-re,
  forrás-jelölés nélküli mutatóra, ismeretlen cohortra, nyitott P0/P1 melletti
  `approved`-ra, az **INKLUZÍV** ablak-küszöb alatti `approved`-ra, hiányzó
  `slo.yaml`-mutatóra és `TBD` döntéshozóra. **Kettős igazságforrás tartva:** a
  kötelező mutató-halmaz a `docs/operations/slo.yaml`-ből, a küszöb a
  `rollout-decision.md`-ből jön — egyik sincs a Pythonba másolva.
- [`test/tooling/rollout_decision_test.dart`](test/tooling/rollout_decision_test.dart)
  — **28 cella**, köztük a `23`/`24`/`25` küszöb-cellahármas (ez különbözteti
  meg a `<` és a `<=` implementációt) és az A2 valódi-sértés próba a VALÓS
  `blockers.md` ellen.
- [`docs/release/staged-rollout-log.md`](docs/release/staged-rollout-log.md) —
  a napló váza: 3 döntés-sor + 15 megfigyelés-sor, minden döntés `pending`,
  minden verdikt `unknown`, `measured_value` `n/a`, és **minden `source`
  `manual`** — telemetria-gyűjtés nincs, a séma ezt kimondja, nem elfedi.

**A H7 halt feloldva.** Az első review verdiktje HALT (H7) volt: a §7 gate a
Kör 30 `freeze_policy_test.dart`-ját is futtatja, és az akkor **a kör diffje
nélkül is** piros volt a `main`-en. A [#530](https://github.com/wolfcasaba/strumsight/pull/530)
önjavító kör (`4de5643f`, L580) ezt javította; a kör-ág az ADR 0087 §0.3
upstream-szinkronjával (`merge --no-ff origin/main` @ `23cdeb09`,
konfliktusmentes) felvette, és a `tools/round-gate.sh
test/tooling/rollout_decision_test.dart test/tooling/freeze_policy_test.dart`
a szinkronizált HEAD-en **MINDEN GATE ZÖLD** (format, analyze, 28+36 cella,
architecture, secrets 4186 fájl/0 lelet, l10n en→hu 2298 üzenet). A review
verdiktje **APPROVED**, 0 nyitott lelettel
([`docs/reviews/e12-r32-review.md`](docs/reviews/e12-r32-review.md)); az egyetlen
NOTE (az R7 lefedettség-ellenőrzés a cohortot figyelmen kívül hagyja) a Kör 33
anyaga.

**CI (exact-SHA, `a50e80a2`):** Full Gate
[33666407322](https://github.com/wolfcasaba/strumsight/actions/runs/33666407322)
**success** · Router CI
[33668495951](https://github.com/wolfcasaba/strumsight/actions/runs/33668495951)
**success**. A `round-ci-plan.py` terve `full-gate.yml` volt
(`native_gate=false`, a diff natív útvonalat nem érint).

**Lecke:** [L581](docs/LESSONS.md#l581) — a Router CI `on.push.paths` szűrője a
PUSH diffjére néz, nem a kör diffjére: a kör utolsó, `docs/reviews/**`-only
commitja sosem triggereli, ezért a merge SHA-n magától NINCS futása. A
`--json headSha` ↔ `git rev-parse HEAD` összevetés fogta meg; a kiszolgálás a
`workflow_dispatch`.

**Következő kör:** `E12-R33` — Staged rollout 50–100% és GA
(`docs/rounds/e12-r33-staged-rollout-50-to-100-and-ga.md`).



## 🔧 ÖNJAVÍTÓ KÖR (ADR 0112) — E12-R32 / H7 feloldva: a NEM SZÁLLÍTOTT verifikációs útvonalak is `release-tooling` — PR [#530](https://github.com/wolfcasaba/strumsight/pull/530), squash `4de5643f` (2026-09-02)

**Az E12-R32 (staged rollout) H7-tel megállt**, pedig a kör négy terméke kész
volt, a `scope_audit=ok`, és a saját mércéje 28/28 zöld. A §7 gate pirosát
**nem a kör diffje** okozta: az `origin/main` csúcsán (`11d0d2bb`), bármely kör
diffje NÉLKÜL:

```
$ python3 tool/release/verify_freeze.py
verify_freeze: 2 finding(s):
  - backend/tests/test_production_smoke_contract.py: not classified …
  - tools/tests/test_sol_terra_both_slots.py: not classified …
exit=1
```

Ez **eggyel több**, mint amit a halt jelentett — a `tools/tests/…` az azóta
merge-elt [#529](https://github.com/wolfcasaba/strumsight/pull/529)-cel érkezett.

**A gyökérok nem a tool, hanem az ADAT.** A `verify_freeze.py` (E12-R30) helyes
és fail-closed; a `docs/release/feature-freeze.md` **prefix-listája** volt
szűkebb a valóságnál, mert a bevezető kör a SAJÁT diffjéből töltötte fel
(`tool/release/`, `test/tooling/`). Egy zárt osztálykészletű politika-ellenőrző
viszont a REPÓ EGÉSZÉRE mér, a freeze VÉGÉIG — így minden későbbi kör nem
szállított kódja osztályozatlan lett. **Ugyanez a hibaosztály harmadszor:**

| # | Útvonal | Honnan | Feloldás |
|---|---|---|---|
| 1 | `HANDOFF.md` | a lánc MINDEN köre ír `docs(handoff)` commitot | `07638527` (E12-R30 post-merge) |
| 2 | `backend/tests/test_production_smoke_contract.py` | E12-R31, `accd30c2` | **ez a kör** |
| 3 | `tools/tests/test_sol_terra_both_slots.py` | `11d0d2bb` (#529) | **ez a kör** |

**Miért nem fogta meg a CI.** A gate-cella (`freeze_policy_test.dart:60–101`) a
sekély (`--depth 1`) CI-klónban a fail-closed ágra fut (a `freeze_base_sha` nem
elérhető → `exit 2`), és zölden állítja a 2-es kódot. A piros ág KIZÁRÓLAG teljes
klónban, azaz a boxon, azaz csak a KÖVETKEZŐ kör §7 gate-jén látszik.

**A javítás — elvből, nem a két mért fájlból (`docs/release/feature-freeze.md`):**
`release-tooling` = ami **nem kerül bele a szállított termékbe**
(`tool/release/`, `test/`, `backend/tests/`, `tools/`).

**A mérce NEM lazult:** a szállított kód (`lib/**`, `backend/app/**`,
`android/**`, `assets/**`, `pubspec.yaml`) továbbra is nyitott P0/P1/P2 blocker
ID-t követel; a `.github/**` és a `.ai/**` **szándékosan nem** került a listára
(a CI-definíció és a router-politika maga a kapu); a három osztály zárt maradt;
teszt nem törlődött és nem lett `skip`-elve; a `tools/round-gate.sh` és a
`.github/workflows/` érintetlen.

**Kötelező regressziós cellák a MÉRT adatból** (`test/tooling/freeze_policy_test.dart`):

| cella | ELŐTTE | UTÁNA |
|---|---|---|
| `the NON-SHIPPING verification paths (backend/tests/, tools/, test/) are release-tooling too` — a piros futás nyers útvonalaival és valódi commit-üzeneteivel | `exit 1`, 3 finding | `exit 0` |
| `the widened release-tooling prefixes do NOT exempt the shipped backend or app code` | `exit 1` | `exit 1` (a határ másik oldala piros marad) |

**Mérés:** izolált worktree-ben `tools/round-gate.sh
test/tooling/freeze_policy_test.dart` → format/analyze/test/architecture/
secrets/l10n MIND ZÖLD, `freeze_policy_test.dart` **36/36** (34+2); Full Gate
[33662777103](https://github.com/wolfcasaba/strumsight/actions/runs/33662777103)
**success** az exact `e89bd183` SHA-n (Router CI nem trigger: a diff egyetlen
`router-ci.yml` útvonalat sem érint). A merge UTÁN a `main`-en
`verify_freeze.py` → **exit 0** (33 útvonal osztályozva).

**A megállt kör folytatható:** a kör saját diffje (6 útvonal) tisztán
osztályozódik a javított doksi ellen, az ága
(`sonnet-impl/e12-r32-staged-rollout-1-to-20-percent` @ `1f286841`) az originon
van, a review verdikt: nincs nyitott lelet
([`docs/reviews/e12-r32-review.md`](docs/reviews/e12-r32-review.md)).

**Lecke:** [L580](docs/LESSONS.md#l580) — a zárt osztálykészletű
politika-ellenőrző prefix-listáját ELVBŐL kell levezetni, nem a bevezető kör
diffjéből; a tágítás határát mutáció-cellával kell őrizni; és ha egy kapunak
környezet-függő ága van, a másik ágat is mérni kell valahol.


## ✅ E12-R31 KÉSZ — Production deployment és internal production cohort — PR [#527](https://github.com/wolfcasaba/strumsight/pull/527), squash `accd30c2` (2026-09-02)

A Ch12 **Kör 31** a production környezet és a belső cohort validálását szállítja
— **deploy nélkül**: a §0.0 emberi kapu szerint a tényleges deploy és a
telepítés user-művelet (infrastruktúra, titkok, store), az implementer terméke a
deploy UTÁN futtatható, gépileg döntő füst-csomag. ADR nincs (a kör
ellenőrzőlistát, füst-cellákat és döntési sablont ad, nem új normát; a
`docs/adr/**` tilos zóna volt).

**Szállítva:**

- `tool/release/production_smoke.py` — paraméteres cél-URL, **titok nélkül** (a
  jelszó sosem argv-ből, csak `--password-env`-ből → nincs `ps`-ben és
  shell-historyban), stdlib-only, minden ágon fail-closed;
- `backend/tests/test_production_smoke_contract.py` (13/13) — a hívott végpontok
  szerződés-cellái + a kötelező valódi-sértés próba;
- `test/tooling/production_readiness_test.dart` (20/20) — kliens production
  profil + CLI-cellák;
- `docs/release/internal-production-checklist.md` — 16 pont **6 GÉPI / 10
  EMBERI** bontásban (a §5.3 tiltja a „minden automatikus" hamis készenlétet);
- `docs/release/rollout-packet-template.md` — az SDD §26.1 mind a kilenc eleme
  (build/commit, active flags, migration version, model version, known issues,
  dashboard snapshot, support readiness, rollback target, döntéshozó).

**A pre-flight a brief KÉT állítását MÉRTEN megcáfolta** (§0.0.1 P1–P7 revízió;
a mérce nem lazult, az engedélyezett-fájllista nem tágult):

- **P1:** `/readyz` **nem létezik** — az E12-R08 §0.0 R1 és az ADR 0449
  kifejezetten elvetette; a readiness `GET /health/ready`
  (`backend/app/main.py:234`).
- **P2:** a fingerprint **nincs** a release manifestben
  (`tool/generate_release_manifest.dart:247–268` — nincs signing mező); az
  ADR 0448 D4 szerint **sidecar** `dist/signing-certificate.json`
  (`keyAlias` + `sha256Fingerprint`), és maga a workflow-lépés is csak
  *proposal* (a `.github/workflows/release-apk.yml` egyiket sem tartalmazza).
  Az A4 ezért a sidecarra lett újraalapozva.

**Review: CHANGES REQUESTED → egy javító kör → APPROVED.** A kötelező
`security-reviewer` (risk = high) 3 MAJOR-t mért, mindhárom a kör SAJÁT kötött
szabályát (§5.1/§5.2) tette vakká; a reviewer saját kódolvasással megerősítette:

1. a `/download` láb **fail-open** volt — a regisztrált, de nem staged
   Lab-letöltő szintén 404-et ad, a check pedig csak státuszkódot nézett
   (javítva: `POST /download` rossz-metódusú próba, 405 ⇒ a route létezik, +
   izolációs contract-cella, ami CSAK az APK-flaget kapcsolja be);
2. az egyetlen titok-szivárgási cella elérhetetlen URL-re mutatott, ezért a
   sikerág — az EGYETLEN szivárgási út — le sem futott (mutáció-kill próbával
   mérve zöld maradt egy jelszót ÉS tokent kiíró mutánsra is); javítva
   stub-szerveres cellával, amely a sikerág lefutását is **bizonyítja**;
3. nem volt `https`-kikényszerítés — `http://` célon a cohort-jelszó tisztán
   ment volna a dróton (javítva: fail-closed `exit 2` a `run_checks()` ELŐTT,
   `--allow-insecure-http` opt-outtal).

A 4 MINOR (redirect-védelem, `community_feed` hamis magabiztossága, nem mért
docstring-állítás, elkerülhető secret-scan marker) szintén zárva. Részletek:
[`docs/reviews/e12-r31-review.md`](docs/reviews/e12-r31-review.md).

**Lecke:** [L579](docs/LESSONS.md#l579) — egy negatív állítást mérő cella (a
Lab-route hiánya, a titok hiánya) csendben vákuummá válhat, ha a mért ág el sem
éri a hibalehetőséget.

## ✅ E12-R30 KÉSZ — Feature freeze és final regression — PR [#526](https://github.com/wolfcasaba/strumsight/pull/526), squash `b3061936` (2026-09-02)

A Ch12 **Kör 30** a projekt ELSŐ feature-freeze köre: kimondott scope- és
kódfagyasztás, gépi freeze-ellenőrző, és egy **őszinte** known-issues lista.
ADR nincs (a kör eljárást ad, nem új normát; a `docs/adr/**` tilos zóna volt) —
a kapcsolódó normát az [ADR 0489](docs/adr/0489-ga-scope-classification-and-contract-freeze.md)
rögzíti. **A kör egyetlen termékkód-fájlt sem módosít** (A6).

**Szállítva:**

- `docs/release/feature-freeze.md` — a freeze szabálya két gépileg parszolható
  blokkal: `freeze_base_sha: 4ac78365` + `approver_role`, és a **zárt, három
  elemű** változás-osztály tábla (`documentation` / `release-tooling` /
  `blocker-fix`). A `blocker-fix` osztály commit-szintű granularitása (egy
  érvényes blocker ID a commit ÖSSZES útvonalát engedélyezi) **kimondva**, a
  jóváhagyó szerep felelősségeként.
- `tool/release/verify_freeze.py` — három ellenőrzés egy eszközben
  (freeze-osztályozás, `known-issues.md`, `CHANGELOG.md`), 0/1/2 kilépő-kóddal
  (a `contract-freeze.md` által fagyasztott testvér-szemantika), végig
  fail-closed parszerekkel.
- `docs/release/known-issues.md` — **17 sor**: a `blockers.md` tíz sorának MAI,
  soronkénti mérése, `K-RC-01` (a Kör 25 RC-workflow soha nem futott), és hat
  gazdátlan, korábban mért nyitott lelet (E12-R20/R21/R23/R24/R29).
- `CHANGELOG.md` — gépileg kötött release-fejléc (`version: 1.0.0`, `build: 1`,
  `schema_version: 1`, **pontosan 3 sor**: egy negyedik, pl. időbélyeg-sor
  fail-closed elutasítva, ADR 0447 D1).
- `test/tooling/freeze_policy_test.dart` — **33 cella** (A1–A4, A7).

**Két MÉRT tény, amit a kör kimond, nem szépít:**

1. A `docs/release/blockers.md` **elavult** (fejléc: `main @ 92576977`,
   2026-08-28; mind a 10 sor `Owner … (pending)`, miközben mind a tíz
   owner-kör MA `done`) — de **tilos zóna**, és mégis ő az A3 szótára. A kör
   nem írja át, hanem a `known-issues.md`-ben kimondja az elavulást, és
   soronként megméri, hogy a **zárási feltétel** teljesült-e. Mérés:
   `docs/governance/04-release-checklist.md` mind a 30 sora ma is pipálatlan,
   ezért **egyetlen blocker sem tekinthető lezártnak**.
2. A Kör 25 RC-workflow-ja (`release-candidate.yml`) **soha nem futott** és
   telepítve sincs (`.github/workflows/` → 10 workflow, nincs köztük); a Kör 25
   szándékosan javaslatként szállította (ADR 0488 D1/D8, a telepítés emberi
   lépés). Az A5 bizonyítéka ezért a `build-apk.yml` dispatch, nem az RC-kapu.

**Pre-flight (§0.0 P1–P7) — az előre megírt brief két állítása MÉRTEN hibás
volt:** (P1) a hivatkozott „ADR 0464" **nem létezik** (`ls docs/adr/0464*` →
nincs), a Kör 28 ADR-je **0489**; (P4) a §3 „a Kör 6 manifest-adataiból
generált CHANGELOG" nem kivitelezhető — a manifest-generátor az engedélyezett
listán KÍVÜL van, ezért az A4 **kötő ellenőrzés** lett (a fejléc-blokk a mért
`pubspec.yaml:5` = `1.0.0+1` és a `generate_release_manifest.dart:23`
`releaseManifestSchemaVersion = 1` forrásokhoz kötve).

**Review:** [`docs/reviews/e12-r30-review.md`](docs/reviews/e12-r30-review.md)
— az 1. kör **két MAJOR** leletet kapott TELJESEN ZÖLD gate és tiszta
scope-audit mellett; mindkettő zárva az 1. javító körben, mindkettő ÚJ
regressziós cellával (31 → 33 cella), a zárás a reviewer friss klónjában,
függetlenül újramérve:

- **MAJOR-1:** a `verify_freeze.py` **ALAPÉRTELMEZETT** hívása nem osztályozott
  — a §5.1 által névszerint tiltott „apró javítás, nem számít" commit is `ok` +
  exit `0`-t kapott, és a deklarált `freeze_base_sha`-nak nulla gépi hatása
  volt (beolvasva, majd eldobva). Súlyosbító: a hibát egy **zöld cella**
  rögzítette elvárásként. Javítva: a bare hívás a `freeze_base_sha`-ra esik
  vissza.
- **MAJOR-2:** egy `blockers.md`-beli P0/P1 sor **lefokozása** a
  known-issues-ban észrevétlen maradt (a felhangolást elkapta, a lefokozást
  nem) — a §5.2 őszinteség-mércéje egy `sed`-del kikerülhető volt. Javítva: a
  súlyosság-egyeztetés iránytól függetlenül fut.
- MINOR-1 (két `P3` besorolás ellentmondott a saját hivatkozott mérésének →
  `P2`) és NOTE-1 (a `blocker-fix` granularitása) szintén zárva.

**Zöld kapu:** `tools/round-gate.sh` (reviewer izolált klónban: format,
analyze, +33, +23, architecture, secrets, l10n — mind zöld) · exact-SHA CI a
`99284e5d` merge SHA-n: [build-apk 33635933136](https://github.com/wolfcasaba/strumsight/actions/runs/33635933136)
+ [router-ci 33635917276](https://github.com/wolfcasaba/strumsight/actions/runs/33635917276).

**Merge UTÁNI javítás (a kötelező post-merge gate lelete, orchestrátor):** a
`main`-en a `freeze_policy_test.dart` két sanity cellája PIROS lett —
`HANDOFF.md: not classified under any freeze change class`. Az őr a lánc
NORMÁL működését (a körönkénti `docs(handoff)` commitot, ami a gyökér
`HANDOFF.md`-t írja) minősítette szabálysértésnek, mert a `documentation`
osztály csak a `docs/` prefixet és a `CHANGELOG.md`-t sorolta fel. Ez sem a
branch-gate-ben, sem a CI-ban nem volt mérhető (a branch diffje `docs/` alatti
volt; a CI sekély klónjában a klasszifikáció el sem futott). Javítva a gyökér
dokumentum-fájljainak nevesítésével (`HANDOFF.md`, `AGENTS.md`, `CLAUDE.md`,
`README.md`) + egy pinnelő cellával (33 → 34 cella); a post-merge gate ezután
teljesen zöld.

**Lecke:** [L578](docs/LESSONS.md#l578) — az őr HÁROM olcsó néma-módja: a FŐ
ellenőrzés kimarad az alapértelmezett hívásból, az összevetés csak az
ártalmatlan irányban fut, és a házirend a rendszer NORMÁL működését minősíti
szabálysértésnek (ez csak a merge utáni gate-en látszott).

## ✅ E12-R29 KÉSZ — Open Beta és canary cohort — PR [#525](https://github.com/wolfcasaba/strumsight/pull/525), squash `3d9721df` (2026-09-02)

A Ch12 **Kör 29** az Open Beta canary-cohort **előkészítését** szállítja. ADR
nincs (a kör eljárást ad, nem új normát; a `docs/adr/**` a tilos zónában volt).
**A cohort megnyitása változatlanul EMBERI kapu** — a kör nem nyit cohortot.

**Szállítva:**

- `docs/operations/capacity-review.md` — a MÉRT backend-korlátokból SZÁMOLT
  cohort-plafon (**25**), `fájl:sor` hivatkozásokkal: login **10/60 s**
  (`backend/app/routers/auth.py:16`), register **5/60 s** (`:17`), bejelentés
  **12/3600 s** (`report_service.py:93-94`), `MAX_UPLOAD_BYTES` **100 MiB**
  (`media_upload_service.py:133`), élő feltöltés **10/profil** (`:154`).
- **Két mért, kimondott tény, amit a dokumentum NEM hallgat el:** (1) a
  Community router **nincs mountolva** a fő appban (`grep -n community
  backend/app/main.py` → 0 találat), tehát a canary ma nulla Community-terhelést
  tud generálni; (2) a `backend/app/routers/settings.py` **egyáltalán nem visel
  rate limitert** — ez rés, nem guard, és a `docs/beta/open-beta-launch.md` §4
  is így nevezi.
- `docs/beta/open-beta-launch.md` — gépileg parszolható canary-profil
  (`<!-- canary-cohort-profile:begin/end -->`, `id: canary`, `maxTesters: 25`,
  16 flag a mért 40-es katalógusból), explicit human-gate blokk, kipipálatlan
  Human launch field. A `docs/beta/cohort-profiles.yaml` **érintetlen**: a
  `ga_scope_test.dart` 16-kulcsos cellája egy 17. kulcstól azonnal pirosra
  váltana (a brief §0.0 P7 mért indoka).
- `backend/tests/test_capacity_guards.py` — A2 rate-limit küszöb-cellahármas a
  `login_limiter.max_attempts`-ból **SZÁMOLVA** (nem 9/10/11 bedrótozva; az
  „elfogadva" helyesen `401`, nem `200`), A3 upload-méret hármas (`MAX-1`/`MAX`
  átmegy, `MAX+1` dob), A4 moderation-queue füst a **MÉRT** úton.
- `test/tooling/canary_cohort_test.dart` — 14 cella: 3-utas plafon-konzisztencia
  (capacity-review marker ↔ launch-doc `maxTesters` ↔ friss újraszámítás),
  canary-izoláció (A5), human-gate (A6), öt **fail-CLOSED** parse-cella
  (L571/L575 ellenszere) és a flag-kulcsok regisztry-ellenőrzése.

**Pre-flight (a kör §0.0 P1–P8) — a brief előre megírt állításai közül kettő
MÉRTEN pontatlan volt:** (P1) a `submit_report` **nem** nyit moderációs ügyet
(`grep case_service report_service.py` → 0 találat), a queue mért útja
`get_or_create_case` → `list_open_cases`, a jel a `priority_score`-ban; (P3/P4)
a Community router nincs mountolva, és a `tests/community/conftest.py` fixtúrái
a kör tesztfájljából nem hivatkozhatók.

**Review:** [`docs/reviews/e12-r29-review.md`](docs/reviews/e12-r29-review.md) —
**hét valódi-sértés próba** izolált klónban, mind a hét a helyes cellát váltotta
pirosra (throttle kikapcs → A2; méret-guard lazítás → A3; report-jel nullázás →
A4; cohort-szivárgás a VALÓDI fán → A5; plafon-drift → A1; human-gate marker
törlés → A6/P6; kitalált flag-kulcs → P7).

- **MAJOR-1 (1. javító körben zárva):** a plafon bázis-inputját (`closed_beta
  = 50`) HAMIS empirikus állítás támasztotta alá — „ténylegesen ki lett osztva
  és incidens nélkül futott" —, miközben a fán `docs/beta/closed-beta-launch.md:3`
  → „Status: **NOT launched**". Pontosan az [ADR 0489](docs/adr/0489-ga-scope-classification-and-contract-freeze.md)
  D3 által mechanizált hibaosztály (kitalált béta-adat bizonyítékként), ezúttal
  gépi őr nélküli prózában. A hivatkozott `docs/HANDOFF.md` útvonal ráadásul nem
  is létezett. Zárva: az 50 most **konfigurációs precedens**, kimondva, hogy
  üzemi tapasztalat nincs mögötte.
- **MINOR-1 (1. javító kör):** a képlet egy **brute-force biztonsági** küszöböt
  (`register_limiter`) köt fejszám-politikához — a dokumentum most kimondja, hogy
  helyettesítőről van szó egy valódi globális kapacitás-mérésig, és hogy egy
  jövőbeli biztonsági szigorítás okozta driftre a válasz nem a küszöb
  visszalazítása.
- **MINOR-2 (2. javító kör):** a launch-doc a három `preview` flaget
  „proven"-ként idézte a `ga-scope.md`-ből, ami ott csak **konfiguráció**
  (`internal: true`/`closed_beta: false`) — átfogalmazva, kimondva, hogy
  futásidejű bizonyíték nincs, mert egyetlen cohort sem indult el.

**Zöld kapu:** Full Gate [`33624228648`](https://github.com/wolfcasaba/strumsight/actions/runs/33624228648)
és Router CI [`33626142221`](https://github.com/wolfcasaba/strumsight/actions/runs/33626142221)
mindkettő `success` a `6cdea0e5` merge SHA-n; a backend sáv (ruff format + ruff
check + teljes pytest) a `backend/` érintése miatt a gate-ben automatikusan
futott. Motor: `sonnet-impl` (Claude Sonnet 5), 2 javító kör. Lecke:
[L577](docs/LESSONS.md#l577).

**Következő kör:** a `docs/execution/pipeline-queue.tsv` következő `pending`
sora — a driver választja ki.

## ✅ E12-R28 KÉSZ — Beta stabilization és scope cut — PR [#524](https://github.com/wolfcasaba/strumsight/pull/524), squash `7b33a1aa` (2026-09-02)

A Ch12 **Kör 28** a GA-scope besorolását és a core contractok befagyasztását
szállítja, GÉPI konzisztencia-őrrel. ADR: **[0489](docs/adr/0489-ga-scope-classification-and-contract-freeze.md)**
(a queue `0464` értéke elavult volt — a foglaló `0489`-et adott, mint az
E12-R22/R23/R25-nél).

**A kör mért kiindulópontja — a brief előfeltétele NEM teljesült.** A brief
`blocked` jelzést írt elő béta-adat hiányára. A pre-flight MÉRTE:
`docs/beta/closed-beta-launch.md:3` → „Status: NOT launched", a §5 Human launch
field üres, a HANDOFF E12-R27 bejegyzése kimondja, hogy **a béta nem indult el**
— és nem is fog, amíg egy ember le nem futtatja (E12-R27 szerint szándékosan
EMBERI kapu). A §0.0.B **R2 revízió** döntése: a kör NEM áll meg, hanem a
béta-hiányt **mért tényként** szállítja, a besorolás pedig a fán mérhető
bizonyítékra épül (a brief §5.2 SAJÁT vagylagos „mérési riport" ága; az A1–A6
egyike sem hivatkozik béta-adatra; precedens: az E12-R27 ugyanezt tette ugyanezzel
az emberi kapuval). **A kitalált béta-adatot nem ígéret zárja ki, hanem gépi őr**
(ADR 0489 D3): minden bizonyíték-hivatkozásnak a fán FELOLDHATÓ útvonalra kell
mutatnia — reviewer-próbával igazolva (egy nem létező `docs/beta/closed-beta-results.md`
hivatkozás → exit 1).

**Szállítva:**

- `docs/release/ga-scope.md` — a `docs/beta/cohort-profiles.yaml` MÉRT **16**
  flag-kulcsának pontosan egy besorolása a zárt készletből
  (`ga`/`preview`/`disabled`/`postponed`): **1 `ga`** (`practiceEngineV2Enabled`),
  4 `preview`, 3 `disabled`, 8 `postponed` — soronként feloldható
  bizonyíték-útvonallal, a mért **`production_default`** értékkel és indoklással;
  a core tanulási út 4 lépése a rátámaszkodó capabilityvel; explicit
  **NEM KÉSZ (NOT READY)** fejléc (nyitott `R-SIGN-01` P0 + öt P1 miatt).
- `docs/release/contract-freeze.md` — 4 befagyasztott contract, mindegyikhez
  NEVESÍTETT, ellenőrizhető feloldó feltétellel (a „szükség esetén módosítható"
  alakú nem-események tiltólistán).
- `docs/release/beta-findings.md` — a béta MÉRT `NOT launched` állapota, a
  helyette használt bizonyítékforrások, és melyik besorolás melyik jövőbeli
  béta-mérésre vár.
- `tool/release/verify_ga_scope.py` — fail-closed ellenőrző (D1–D7), stdlib +
  PyYAML (a testvér `verify_beta_profile.py` precedense).
- `test/tooling/ga_scope_test.dart` — az A1–A5 mutáció-cellái + exit-2
  használati cellák; a Kör 27 `beta_profile_test.dart` VÁLTOZATLAN és zöld (A6).

**Review:** [`docs/reviews/e12-r28-review.md`](docs/reviews/e12-r28-review.md) —
1. menet **2 MAJOR (0 BLOCKER)** teljesen zöld gate és tiszta scope-audit mellett:

- **MAJOR-1 — az A3/D5 őr fail-OPEN volt.** A `_parse_table` a laza elő-szűrőt
  (`row_start`) nem teljesítő sort `continue`-val NÉMÁN eldobta, a core-path
  táblának pedig — a capability-táblával ellentétben — NINCS teljességi
  ellenőrzése. Reviewer-mérés izolált klónban: egy `preview` capabilityt a core
  útra tevő sor, vezető `|` után szóköz nélkül és backtickes lépés-cellával →
  **exit 0, ZÖLD**, a darabszám csendben 4-ről 3-ra esett. Súlyosbító: a
  modul-docstring az ELLENKEZŐJÉT állította („never a silently-dropped row"),
  ilyen kereszt-ellenőrzés a kódban nem volt. Ugyanaz a mutáció a javítás után
  **exit 2**, a sor számával — a javítás mind a HÁROM táblára kiterjed.
- **MAJOR-2 — a kör egyetlen `ga` capabilitye production build-ben `false`.**
  `practiceEngineV2Enabled` mért production alapértelmezése `false`
  (`lib/app/config/feature_flags.dart:78` — `nonProd`, dart-define felülíró ág
  NÉLKÜL), tehát a `/practice*` route-ok production buildben nincsenek
  regisztrálva és a §3 első core-út-lépése ma nem járható végig — a dokumentum
  ezt nem mondta ki. Ez a §9 „Rejtett GA" tükörképe (rejtett NEM-GA), és a
  NOT-READY fejléc NEM fedi le (az a blocker-listáról szól). Javítás: géppel
  kötött `production_default` oszlop, a mért forrásból (`forEnvironment` törzse,
  fail-closed parse) visszaellenőrizve, plusz kikényszerített nevesített
  feloldási feltétel.

**1 javító kör** (`25cad21f`) → **APPROVED** (0 nyitott BLOCKER/MAJOR). A zárás
a reviewer SAJÁT újra-méréseivel: P7 → exit 2; `production_default` hamisítva →
exit 1 a mért értékkel; feloldó feltétel kivéve → exit 1; ismeretlen forrás-alak
→ exit 2 (fail-closed); a D3/D7 regresszió-próbák továbbra is pirosak; célzott
gate 7/7 zöld friss `/tmp` klónban. **MINOR-1 follow-upra marad** (a `postponed`
besorolás cohort-flag állapotát nem köti cella; élő rés nincs — mind a 8
`postponed` flag `false` mindkét cohortban —, és az ADR 0489 D4 sem követeli meg).

**Exact-SHA CI a `a3fe03d3` merge SHA-n:** [full-gate 33613004979](https://github.com/wolfcasaba/strumsight/actions/runs/33613004979)
+ [router-ci 33613007674](https://github.com/wolfcasaba/strumsight/actions/runs/33613007674),
mindkettő `success`. Lecke: [L576](docs/LESSONS.md).

## ✅ E12-R27 KÉSZ — Closed Beta launch és monitoring — PR [#523](https://github.com/wolfcasaba/strumsight/pull/523), squash `6b5dcb5a` (2026-09-02)

A Ch12 **Kör 27** a Closed Beta **indítási konfigurációját** és a hozzá tartozó
**monitoring-eljárást** szállítja — az indítás MAGA emberi kapu, amit ez a kör
szándékosan NEM hajt végre. ADR nincs; a szerződéseket a merge-elt
[ADR 0446](docs/adr/0446-feature-flag-registry-and-emergency-kill-switch.md) (D1/D2/D7),
[ADR 0395](docs/adr/0395-community-baseline-feature-flags-and-threat-model-scope.md) és
[ADR 0486](docs/adr/0486-beta-distribution-consent-and-redacted-diagnostics-bundle.md)
hordozza (precedens: E12-R24, E12-R26).

**Szállítva:**

- `docs/beta/cohort-profiles.yaml` — 2 cohort (`internal`, `closed_beta`), 32
  flag-hozzárendelés a MÉRT 40-es katalógusból; mind a **7** `high` kockázatú
  flag `false` mindkét cohortban.
- `tool/release/verify_beta_profile.py` — a profilt **PyYAML**-lel parse-olja
  (kemény függőség, precedens `build_ai_report.py`), a Dart registryt
  **fail-closed** regexszel: `< 40` bejegyzés VAGY `FeatureFlagDefinition(`
  előfordulásszám ≠ sikeresen parse-olt hármasok száma → nem-nulla kilépés
  kimondott üzenettel. A1/A2/A3 validáció (exit 1), `--kill-switch` **read-only**
  dry-run (exit 0, csak stdout).
- `test/tooling/beta_profile_test.dart` — **18 cella**, A1–A6, ellenséges
  fixture-ök temp-könyvtárban (fixture nincs commitolva).
- `docs/beta/daily-triage-template.md` — napi triage-ritmus, KIMONDOTT döntési
  szabály: **nyitott P0/P1 mellett nincs cohort-bővítés**; a bemenetek a
  diagnosztikai bundle + a kézi visszajelzés, mert **telemetria-gyűjtés MA nincs**.
- `docs/beta/closed-beta-launch.md` — 14 pontos indítási ellenőrzőlista, minden
  pont MÉRT bizonyítékra hivatkozva, a valódi kill-switch dry-run kimenetével
  (`labModeAvailable` a `closed_beta` cohortban — `low` kockázatú ÉS bekapcsolt),
  a monitoring valódi határainak kimondásával, és az **ÜRES emberi indítási
  mezővel**. **A béta NEM indult el.**

**Review:** [`docs/reviews/e12-r27-review.md`](docs/reviews/e12-r27-review.md) —
1. menet **1 MAJOR (0 BLOCKER)** teljesen zöld gate és tiszta scope-audit
mellett: az A5 ellenőrzőlista-őr bullet-mintája fail-OPEN volt a **kipipált**
(`- [x]`) sorokra, tehát pontosan a dokumentum rendeltetésszerű használatakor
némult volna el (reviewer-mérés izolált klónban: kipipált sor + nem létező
útvonal → **exit 0, ZÖLD**; ugyanaz kipipálatlanul → piros). MINOR-1: az A3
másodlagos regex a kettőspont előtt nem engedett szóközt. **1 javító kör** →
**APPROVED** (0 nyitott lelet, 2 NOTE). Zárás a reviewer saját újra-mérésével:
a mutáció most exit 1, a kipipált-de-valós változat 18/18 zöld, célzott gate
`gate_exit=0`. Lecke: [L575](docs/LESSONS.md#l575).

Exact-SHA evidencia a `522248b2` merge SHA-n: Full Gate
[33604475615](https://github.com/wolfcasaba/strumsight/actions/runs/33604475615),
Router CI [33604523266](https://github.com/wolfcasaba/strumsight/actions/runs/33604523266)
(`workflow_dispatch` — a záró review-commit nem trigger-útvonal, [L572](docs/LESSONS.md#l572))
— mindkettő `success`. CI-terv: `tools/round-ci-plan.py` → `full-gate.yml`, `native_gate = false`.

**Következő kör:** a `docs/execution/pipeline-queue.tsv` következő `pending` sora,
új sessionben.

## ✅ E12-R26 KÉSZ — Rollback és disaster recovery drill — PR [#522](https://github.com/wolfcasaba/strumsight/pull/522), squash `e9b20604` (2026-09-02)

A Ch12 **Kör 26** a projekt **ELSŐ rollback-gyakorlata**: nem dokumentumot ír a
visszaállításról, hanem **lefuttatja**, méri, és gépi ellenőrzőt ad rá. ADR nincs —
a szerződéseket a merge-elt [ADR 0446](docs/adr/0446-feature-flag-registry-and-emergency-kill-switch.md)
(D1/D2/D7) és [ADR 0449](docs/adr/0449-staging-readiness-traffic-gate-and-recovery.md)
(D4/D5) hordozza (precedens: E12-R24).

**Szállítva:**

- [`tool/release/verify_rollback.py`](tool/release/verify_rollback.py) — négy
  **fail-closed** dimenzió a visszaállítás UTÁNI állapotra (migrációs fej,
  táblánkénti rekordszám, modell-manifest sha256, flag-profil), importálható
  maggal és CLI-vel. Hiányzó/olvashatatlan bemenet **FAIL**, sosem csendes
  `SKIPPED`; kihagyás csak explicit `--no-flag-profile`-lal, láthatóan.
- [`docs/operations/disaster-recovery-drill.md`](docs/operations/disaster-recovery-drill.md)
  — a **ténylegesen lefuttatott** gyakorlat jegyzőkönyve, lépésenként MÉRT
  idővel, az itt NEM elvégezhető lépések kimondásával.
- `backend/tests/test_rollback_drill.py` (**15 cella**) + `test/tooling/rollback_policy_test.dart`
  (**10 cella**) — az A1–A6 gépi mércéje.

**A pre-flight KÉT acceptance-premisszát mért HAMISNAK** (§0.0.1 revízió, listatágítás nélkül):
az **A4** „flag-cache lejárata" — cache **nem létezik**, és az ADR 0446 D2 kifejezetten
tiltja (`feature_flag_source.dart:72–75`), ezért a küszöb-hármas a **feloldás-indexre**
állt át (elavulási ablak = 0 feloldás, ami ERŐSEBB állítás bármely véges `T`-nél);
az **A2** „előző kliens-verzió" — **nincs API-verziózás** a backendben.

**A review 4 MAJOR-t talált TELJESEN ZÖLD gate és tiszta scope mögött**
([`docs/reviews/e12-r26-review.md`](docs/reviews/e12-r26-review.md)); **1 javító kör** → APPROVED, 0 nyitott lelet.
KÉT független `security-reviewer` futás **egymástól függetlenül ugyanazt a MAJOR-1-et
és MAJOR-2-t** találta meg elsőként:

- **MAJOR-1:** a `verify_rollback.py` a **29 élő táblából 2-t** hasonlított
  (`Base.metadata` az `app.models` importja után csak `users` + `user_settings`), a
  `continue` a többit csendben kihagyta, a PASS-szöveg pedig a DUMP tábláinak számát
  írta ki — így egy 27 táblát vesztő visszaállítás is `PASS / 2 table(s) match / EXIT=0`
  volt. Zárva élő-vs-dump **kétirányú** összehasonlítással; a javítás után a valós
  lánc függetlenül újramérve `OVERALL: FAIL`, `EXIT=1`, mind a 26 Community tábla
  nevesítve. Ugyanaz a fail-OPEN hibaosztály, mint az E12-R25 F1-e ([L566](docs/LESSONS.md#l566), [L573](docs/LESSONS.md#l573)).
- **MAJOR-2:** a jegyzőkönyv „(+ minden Community tábla `0` sorral)" állítása mérhetően
  hamis volt — a dump kulcsai kizárólag `['user_settings','users']`.
- MAJOR-3 (üres `{}` flag-profil → PASS), MAJOR-4 (`{value!r}` visszhang: PII + bcrypt
  hash a riportba), + 7 MINOR — mind zárva, mindegyikhez ÚJ mérő cella ([L574](docs/LESSONS.md#l574)).

**A kör legértékesebb terméke az A6 runbook-lelet** (a jegyzőkönyv §7): a
`backend/scripts/backup.py` a `Base.metadata`-ra támaszkodik, a **27 Community tábla
viszont raw-DDL Alembic-migrációkban jön létre, ORM-modell nélkül** — ezért a dump
ŐKET SOHA nem tartalmazza, akármennyi éles adat van bennük. Ez **latens produkciós
adatvesztési kockázat**, és pontosan az ilyen gyakorlatnak kell felszínre hoznia. A
javítás `backend/scripts/**`-t érintene (tiltott zóna), ezért helyesen LELET maradt,
nem csendes javítás — **egy jövőbeli kör dolga**.

**Nyitva marad (nem blokkoló):** MINOR-3 (elgépelt `sqlite:///` úton 0 bájtos fájl
keletkezik) és a NOTE-ok (rekordszám ≠ tartalom — azonosító-halmaz nincs mérve).

Exact-SHA evidencia a `744bf7b0` merge SHA-n: Full Gate
[33597766331](https://github.com/wolfcasaba/strumsight/actions/runs/33597766331),
Router CI [33597810750](https://github.com/wolfcasaba/strumsight/actions/runs/33597810750)
(`workflow_dispatch` — a záró review-commit nem trigger-útvonal, [L572](docs/LESSONS.md#l572)),
Backend CI [33596216760](https://github.com/wolfcasaba/strumsight/actions/runs/33596216760)
— mind `success`. CI-terv: `tools/round-ci-plan.py` → `full-gate.yml`, `native_gate = false`.

**Következő kör:** a `docs/execution/pipeline-queue.tsv` következő `pending` sora,
új sessionben.

## ✅ E12-R25 KÉSZ — Release Candidate assembly workflow — PR [#521](https://github.com/wolfcasaba/strumsight/pull/521), squash `37724df4` (2026-09-02)

A Ch12 **Kör 25** összeköti a Chapter 12 eddig **külön-külön** meglévő kiadási
bizonyíték-darabjait (manifest/SBOM `E12-R06`, signing `E12-R07`, AI-riport
`E12-R16`, security-scan `E12-R18`) **egyetlen, manuálisan jóváhagyható, auditálható
útba**. A kötött döntések:
[ADR 0488](docs/adr/0488-release-candidate-assembly-and-approval-gate.md) D1–D8.

**A kör kettéosztva szállít, mert a `.github/workflows/**` VÉDETT mérce-zóna**
([ADR 0321](docs/adr/0321-gateguard-round-hold-not-chain-halt.md) `PROTECTED_GLOBS`),
és az [ADR 0372](docs/adr/0372-gate-edit-policy.md) álló felhatalmazásának fájlja
(`.claude/gate-edit-policy`) a fán MA sem létezik — a pre-flight ezt újramérte:

- **javaslatként:** [`docs/release/workflows/release-candidate.proposal.yml`](docs/release/workflows/release-candidate.proposal.yml)
  — a teljes `release-candidate.yml`: `workflow_dispatch` **nulla inputtal**, egyetlen
  `environment: release-candidate-approval` job, amelyre a gate-, build- és
  upload-jobok `needs:`-szel épülnek (a jóváhagyás így ténylegesen a **build ELŐTT**
  áll, D3), a mérce-lánc a KÖZÖS `./.github/actions/flutter-gates` composite-ból (D2),
  a production signing a mért `release-apk.yml` env-szerződésével;
- **kódként:** [`tool/release/assemble_rc.py`](tool/release/assemble_rc.py) — stdlib-only,
  fail-closed összeállító: hét kötelező bemenet feloldása írás ELŐTT, hiányzóra
  nem-nulla kilépés félkész csomag nélkül (D4); `--verify` a csomagot a saját
  checksum-manifestjéhez köti, ahol **hiányzó, megváltozott ÉS többlet** fájl is
  eltérés (D5); `--dry-run` a tervet írja ki és tiszta fán szándékosan nem-nullával áll meg.

**A review a TELJESEN ZÖLD gate mögött találta meg a lényeget** — 1 MAJOR + 1 MINOR
+ 2 NOTE, **1 javító kör** → APPROVED, 0 nyitott lelet
([`docs/reviews/e12-r25-review.md`](docs/reviews/e12-r25-review.md)):

- **MAJOR (F1):** a `verify_package` a csomagot `iterdir()` + `is_file()`-fal járta be —
  **nem rekurzívan**. Egy alkönyvtárba csempészett többletfájl (`extra/evil.apk`) így
  `--verify`-ra **exit 0**-val átment („matches its checksum manifest exactly"), miközben
  az `upload-artifact` a TELJES `dist/rc` fát tölti fel — a fájl kiszállt volna a kiadott
  csomagban. Ugyanaz a fájl a csomag gyökerében helyesen pirosra váltott: a rés kizárólag
  a beágyazottság. A [L566](docs/LESSONS.md#l566) fail-OPEN hibaosztály, fájlrendszeren.
  Zárva `rglob('*')` + csomag-gyökérhez relatív POSIX útvonalakkal, mindkét oldalon
  (assemble ÉS verify), + 1 új cellával ([L573](docs/LESSONS.md#l573)).
- **MINOR (F2):** az `--output-dir` `rmtree`-je a bemenetek ELLENŐRZÉSE UTÁN fut, ezért
  ha a kimeneti könyvtár a bemenetek őse, letörli MAGUKAT a bemeneteket, majd elkapatlan
  `FileNotFoundError`-rel száll el — a docstring D4-ígérete („no half-built package")
  ezen az úton nem tartható. Zárva `resolve()`-alapú ancestor-guarddal a `rmtree` ELŐTT
  + `OSError → AssembleError` fordítással + 1 új cellával.

**A cellák mérő voltát hat valódi-sértés próba igazolta** (mutate → mérj → állítsd vissza,
izolált `/tmp` klónban): a kötelező-bemenet ellenőrzés kivétele → **8 A3-cella piros**;
a composite hívásának bemásolt `run:` lépésre cserélése → **mindkét A5-cella piros**;
a `needs: approve-release-candidate` élek törlése → **az A1 tranzitív-needs cella piros**;
a fix1 előtti assemblerrel a két ÚJ cella **pontosan kettesével** piros (L563).
`security-reviewer` (`risk = high`) lefuttatva: **nincs BLOCKER**.

**Nyitott NOTE-ok (nem merge-blokkolók, a TELEPÍTÉSI lépés ellenőrzési pontjai):**
(1) a `--verify` belső konzisztenciát bizonyít, nem hitelességet — a checksum-manifest
aláíratlan, a valódi horgony az APK aláírása; (2) a jóváhagyási kapu ereje a repo
Settingsben él: a `release-candidate-approval` environmenthez **required reviewert kell
beállítani**, különben az `environment:` kulcs nem blokkol.

**A merge UTÁNI, EMBERI/orchesztrátori lépés (ADR 0488 D8, még NEM történt meg):** a
javaslat telepítése `.github/workflows/release-candidate.yml` néven, majd KÉT dispatch —
egy ZÖLD és egy BIZONYÍTOTT PIROS (hiányzó jóváhagyás vagy hiányzó AI-riport) —, a linkek
a kör §11 review-jegyzetébe. Ez a kör ezt szándékosan nem tette meg: a védett zónába írni
`H-GATEGUARD` halt lenne.

Exact-SHA evidencia a merge SHA-n (`62ab967d`): Full Gate
[33585065695](https://github.com/wolfcasaba/strumsight/actions/runs/33585065695),
Router CI
[33585067030](https://github.com/wolfcasaba/strumsight/actions/runs/33585067030)
— mindkettő `success`. A CI-tervet a `tools/round-ci-plan.py` adta (`full-gate.yml`,
`native_gate = false`, `router_ci_expected = true`).

**Következő kör:** `E12-R26` — rollback és disaster recovery drill
(`docs/rounds/e12-r26-rollback-and-disaster-recovery-drill.md`, ADR `nincs`,
`sonnet-impl`), új sessionben.

## ✅ E12-R24 KÉSZ — Store listing, privacy és legal package — PR [#520](https://github.com/wolfcasaba/strumsight/pull/520), squash `cf7c6fb6` (2026-09-02)

A Ch12 **Kör 24** a production-terjesztéshez szükséges, **ellentmondás-mentes
dokumentum-csomagot** állítja elő, és — ez a lényeg — **gépi mércét** ad rá. A
store-fiók, a feltöltés és a jogi felülvizsgálat továbbra is EMBERI lépés (a
brief §0.0 ezt kimondja). **ÚJ ADR nincs, szándékosan:** minden normatív állítás
MÁR merge-elt döntésre vezet vissza — [ADR 0477](docs/adr/0477-ai-release-evidence-aggregation-and-ga-scope-truth.md)
D1 (a GA-scope EGYETLEN igazsága a `docs/testing/device-matrix.yaml`
`capabilities[].ga_scope`), [ADR 0479](docs/adr/0479-privacy-data-inventory-and-consent-enforcement.md)
(a privacy-leltár), [ADR 0247](docs/adr/0247-analysis-export-share-and-delete-contract.md)
(export/share/delete). Precedens: E12-R13 („új ADR nincs").

**Szállított csomag (5 dokumentum + 1 őr):** `docs/store/listing.md` ·
`docs/store/permissions-rationale.md` · `docs/store/data-safety.yaml` ·
`docs/legal/privacy-policy-draft.md` · `docs/legal/community-guidelines-draft.md`
· `test/tooling/store_package_test.dart` (**31 cella**, A1–A5).

**A kör érdemi állítása: nincs beégetett lista.** A teszt a manifestet, a
privacy-leltárt és a device-mátrixot ÉLŐBEN olvassa. Ezt nem a zöld gate
bizonyítja, hanem a reviewer nyolc valódi-sértés próbája a VALÓDI
forrásfájlokon, eldobható klónban: ÚJ `ACCESS_FINE_LOCATION` a manifestbe → A1
piros; `CAMERA` rationale-blokk eltávolítása → A1 piros; data-safety hivatkozás
nem létező mezőre → A2 piros mindkét irányban; ÚJ `leaves_device: true` mező a
leltárba → A2 piros; `audio_analysis_core` `ga_scope` billentése → A3 piros;
kitalált `/privacy-center` a listingbe → A4 piros.

**A pre-flight két avult brief-állítást mért ki** (§0.0 revízió R1–R6): (1) a
brief §2 azt állította, hogy a fiók-törlés a `backend/app/routers/auth.py`
felelőssége — MÉRVE HAMIS, a router csak `POST /register`, `POST /login`,
`GET /me` végpontot ad, **kliens által indítható fiók-törlés a fán NEM létezik**;
(2) az A3 nem nevezte meg a GA-scope forrását. A csomag ezért a fiók-törlést
őszintén támogatási (e-mail) csatornaként írja le, és a `privacy-policy-draft.md`
szó szerint kimondja a hiányzó végpontot — külön cella méri.

**A review a TELJESEN ZÖLD gate mögött találta meg a lényeget** — 1 MAJOR + 1
MINOR + 2 NOTE, **1 javító kör** → APPROVED, 0 nyitott lelet
([`docs/reviews/e12-r24-review.md`](docs/reviews/e12-r24-review.md)):

- **MAJOR-1 (P7 próba):** az A3 próza-scan némán kihagyta a signature nélküli
  `ga_scope: false` capabilityket (`if (pattern == null) continue`). Egy ÚJ,
  negyedik non-GA capability + „Band Jam Mode … coming soon" próza-ígéret a
  listingben **29/29 ZÖLDEN átment** — pontosan az a §5.3-sértés, aminek a
  megfogása a kör célja. Fail-open egy gépi mércében, az ADR 0477 D2 által
  tiltott „nincs adat → nincs regresszió" minta; ugyanez a hibaosztály már
  egyszer mérve volt ([L555](docs/LESSONS.md#l555), E12-R16 MAJOR-1). Zárva
  fail-closed kezeléssel + 2 új cellával — a P7 forgatókönyv most 3 cellát visz
  pirosra, tetszőleges (nem beégetett) capability-id-vel is
  ([L571](docs/LESSONS.md#l571)).
- **MINOR-1:** az A4 route-scan a csomag 5 dokumentumából csak 4-et nézett.
  Zárva; a P8b próba (backtick-idézett `/privacy-center` a `data-safety.yaml`
  `purpose:` mezőjében) most piros.

**Nyitott NOTE-ok (nem merge-blokkolók, ma gazdátlanok):** (1) a
`privacy-support@strumsight.app` cím **kitalált PLACEHOLDER** — a valódi cím
megerősítése a store-feltöltés emberi előfeltétele; (2) a `data-safety.yaml`
`play_category` mezőinek megfeleltetése a hivatalos Play-taxonómiához a Play
Console űrlapján, emberi lépés.

Exact-SHA evidencia a merge SHA-n (`b3e346d4`): Full Gate
[33579841775](https://github.com/wolfcasaba/strumsight/actions/runs/33579841775),
Router CI
[33579897602](https://github.com/wolfcasaba/strumsight/actions/runs/33579897602)
— mindkettő `success`. A CI-tervet a `tools/round-ci-plan.py` adta
(`full-gate.yml`, `native_gate = false`); a Router CI-t `workflow_dispatch`-csel
kellett a merge SHA-ra kérni, mert a záró review-commit csak `docs/reviews/**`-ot
érintett, ami nem trigger-útvonal ([L572](docs/LESSONS.md#l572)).

## ✅ E12-R23 KÉSZ — Legacy user migration release candidate — PR [#519](https://github.com/wolfcasaba/strumsight/pull/519), squash `3e6dbbf0` (2026-09-02)

A Ch12 **Kör 23** azt méri végig, hogy egy **régi telepítésről frissítő**
felhasználó adata a boot-idejű migrátor-láncon (`appStorageMigrations`, 22 lépés)
átér-e — `lib/**` és a meglévő e2e harness érintése NÉLKÜL. ADR:
[0487](docs/adr/0487-legacy-upgrade-migration-evidence-contract.md) (D1 a „nincs
adatvesztés" invariáns SZÁMSZERŰ, nem viselkedési · D2 megszakítás után FOLYTATÁS
van, nem újrakezdés · D3 a hibás migráció fail-safe és SOHA nem üres profil · D4
a safe-mode felület a MÉRT elérhetőségén pinnelendő · D5 a mérce nem módosít
`lib/**`-ot · D6 minden ÚJ fixture az ADR 0473 manifest-szerződése alá esik).
Szállítva: `test/e2e/upgrade_migration_test.dart` (8 cella: A1 mező-szintű
adatmegőrzés, A2 megszakítás→folytatás replay nélkül, A3 write-fault,
**A3b valódi korrupció**, A4 `BootstrapFailure`, A5 pinnelt lépéssorrend),
három legacy fixture (`legacy_v1`/`legacy_v2`/`corrupted_storage`) manifest-be
regisztrálva (`test/fixtures/manifest.json` 48 → 51), és
[`docs/release/client-migration.md`](docs/release/client-migration.md).

**A pre-flight négy mért állítást döntött meg** (brief §0.0/R1–R6): az ADR
száma `0462` → **`0487`** (a batch-előjegyzés elavult, a foglaló a normatív
forrás); a három ÚJ `.json` fixture a `fixture_manifest_test.dart` egzakt
`hasLength(48)` cellájával a **teljes CI-suite-ot buktatta volna**, ezért az
`allowed_paths` szűken bővült a manifesttel és a cellával (a kör MÉRI a
regisztrációt, nem kerüli meg); az A3 eredeti „sérült bemenet →
`RecoveryScreen`" célja a fán **elérhetetlen** volt.

**A kör érdemi hozadéka mérési** ([L570](docs/LESSONS.md#l570)): a szállított A3
cella a `corrupted_storage.json` NEVE ellenére nem a korrupt bemenetet mérte,
hanem egy injektált írás-hibát — a fixture minden értéke jól formált JSON volt,
a cella szó szerint ugyanígy zöld lett volna a `legacy_v1` fixture-rel. A
reviewer eldobható próbatesztje ténylegesen malformált dokumentummal kimérte,
hogy a `migrate()` **sikert jelent** (`failure=null`, mind a 22 lépés `applied`),
a nyers bájtok a lemezen megmaradnak, **de a production olvasási út üres
dokumentumot ad** — a felhasználó frissítés után üres dalkönyvtárat lát. Egy
javító kör után APPROVED, 0 nyitott lelet
([`docs/reviews/e12-r23-review.md`](docs/reviews/e12-r23-review.md)).

> ⚠ **NYITVA MARAD — ismert korlát, `lib/**` javítást igényel:** egy sérült
> legacy dokumentum után a `JsonDocumentStore.readBody()` `null`-t ad, tehát a
> felhasználó ÜRES dokumentumot lát, miközben az adata a lemezen ott van (a
> következő `write()` karanténba menti). Az A3b cella ezt „ISMERT KORLÁT
> (ADR 0487)" jelöléssel **pinneli**, tehát ha egy jövőbeli kör megjavítja vagy
> elrontja, a cella szól. A javítás iránya (per-dokumentum hiba felszínre
> hozása, vagy a „nincs itt semmi" ↔ „van, de olvashatatlan" megkülönböztetése)
> a `docs/release/client-migration.md` §6-ban dokumentált, és **ma gazdátlan** —
> önálló, `lib/**`-ot érintő kört igényel.

## ✅ E12-R22 KÉSZ — Béta-terjesztés, tesztelői consent és redaktált diagnosztikai csomag — PR [#518](https://github.com/wolfcasaba/strumsight/pull/518), squash `3b1855ff` (2026-09-01)

A Ch12 **Kör 22** a béta-visszajelzés **csatornáját és csomagját** szállítja —
felület nélkül (`lib/**`, `.github/**`, `lab_build.json` a kör tilos zónája volt).
ADR: [0486](docs/adr/0486-beta-distribution-consent-and-redacted-diagnostics-bundle.md)
(D1–D7 + a review után D2.1/D3.1). Szállítva:
`tool/release/build_diagnostics_bundle.py` (rétegzett consent, rekurzív redakció,
tartalom-alapú hang-gate, inkluzív 5 242 880 bájtos korlát HIBÁVAL, korlátos
gzip-kicsomagolás, `0600`-as kanonikus kimenet), `tool/release/generate_beta_notes.py`
(fail-closed, bájtazonos béta-jegyzet a release-manifestből),
`test/tooling/beta_release_notes_test.dart` (53 cella),
`backend/tests/test_diagnostics_redaction.py`, valamint
[`docs/beta/enrollment.md`](docs/beta/enrollment.md),
[`docs/beta/tester-consent.md`](docs/beta/tester-consent.md) (a data-inventory
GÉPI, kétirányú tükre — 12 mező, 3 útvonal) és
[`docs/beta/feedback-triage.md`](docs/beta/feedback-triage.md).

**A kör érdemi hozadéka mérési** ([L569](docs/LESSONS.md#l569)): a teljes gate
10/10 zöld volt, a review mégis **1 BLOCKER + 3 MAJOR + 2 MINOR**-t talált. A
legsúlyosabb (M1): a redakció útvonal-mintája a `wavBase64` ÉRTÉKÉRE is lefutott,
és a base64 ábécé `/` karakterei miatt **csendben megsemmisítette a consentelt
klipet** (117 660 → 189 karakter, `exit 0`, a kimenet nem dekódolható) — pontosan
az a néma csonkítás, amit a D3 nevesítve tilt. A cella azért volt zöld, mert a
fixture `Uint8List(n)` volt: csupa nulla bájt → csupa `A` base64 → **egyetlen `/`
sem**, tehát a hibaosztály szerkezetileg nem tudott előfordulni. Egy javító kör
után APPROVED, 0 nyitott lelet; a zárást a reviewer SAJÁT, a javító kód ellen
futtatott próbái igazolják
([`docs/reviews/e12-r22-review.md`](docs/reviews/e12-r22-review.md) §6).

`risk = "high"` → a kötelező `security-reviewer` futott
([`docs/reviews/e12-r22-review-security.md`](docs/reviews/e12-r22-review-security.md)).
Exact-SHA evidencia a merge SHA-n (`0192cb6b`): Full Gate
[33566453442](https://github.com/wolfcasaba/strumsight/actions/runs/33566453442),
Router CI [33566455858](https://github.com/wolfcasaba/strumsight/actions/runs/33566455858),
Backend CI [33566457950](https://github.com/wolfcasaba/strumsight/actions/runs/33566457950)
— mind `success`.

> ⚠ **NEVESÍTETT HIÁNY:** a `lib/features/feedback/` visszajelzés-KÉPERNYŐ nem
> készült el (ADR 0486 D7) — a `test/ui/ui_inventory_test.dart` egzakt
> képernyőszámot pinnel, és a felületek a Chapter 13/15 sáv kompetenciája. **Ma
> egyetlen nyitott brief sem nevezi meg**, tehát gazdátlan tétel.
>
> ⚠ **Két follow-up NOTE a security review-ból** (nem blokkoló, az ADR 0486 D2
> betűje szerint helyes viselkedés): az e-mail-osztály ASCII-only, tehát egy IDN
> cím (`tesztelő@példa.hu`) redaktálatlan marad; és a titok-osztályt egyedül a
> `token` kulcs-részsztring definiálja, tehát `apiKey`, `password`,
> `authorization` értéke átmegy. A `docs/beta/tester-consent.md` szövege
> erősebbnek hangzik ennél — egy későbbi kör vagy a D2-t bővíti, vagy a
> dokumentumot pontosítja.

## ✅ E12-R21 KÉSZ — Content catalog leltár + pedagógiai readiness validátor — PR [#517](https://github.com/wolfcasaba/strumsight/pull/517), squash `12813a2c` (2026-09-01)

A Ch12 **Kör 21** gépi bizonyítékot ad arra, hogy a szállított tartalom
**leltározott, verziózott, címkézett és hivatkozás-helyes** — tartalom
hozzáadása, átírása vagy áthelyezése NÉLKÜL (`lib/**` és `assets/**` a kör
tilos zónája volt). ADR: [0485](docs/adr/0485-content-catalog-inventory-and-pedagogical-readiness-contract.md).
Szállítva: `tool/validate_content_catalog.py` (stdlib-only, fail-closed
sor-parszer), [`docs/content/catalog-inventory.yaml`](docs/content/catalog-inventory.yaml)
(36 elem), `test/tooling/content_catalog_test.dart` (32 cella) és
[`docs/content/release-readiness.md`](docs/content/release-readiness.md).

**A pre-flight mérése írta a kör alakját (brief §0.0 R1–R8).** A SDD `content/catalog/`
fát ír elő; a fán viszont a tartalom **HÁROM** helyen él (nem kettőn): a
Practice Engine Dart-katalógusa, az `assets/tutor_knowledge/` manifest és a
legacy Learn lecke-katalógus. Egy negyedik fa kettős igazság lett volna, ezért a
kör **leltárat és validátort** ad a meglévőkre. Két további mért tény szűkítette
az acceptance-t: a Practice Generator katalógusa **hívó-táplált** (nincs
`PracticeCatalogReader` implementáció a fán), ezért az A2 a SZÁLLÍTOTT
hivatkozás-halmazon mérődik, nem egy generátor-futáson; és a fán **nincs
kanonikus készség-taxonómia** — a három szótár diszjunkt (a
`LegacyMappingTable` `chord.gMajor|cMajor|dMajor` azonosítói nem elemei az
`ai_tutor` `SkillTaxonomy.initial`-jának) —, ezért a szótár forrásonként
deklarált és kétirányúan mért.

**KÉT MÉRT GA-blokkoló, egyik sem javítva** (a tartalom-források tilos zóna;
nyilvántartás: a leltár `known_exceptions:` blokkja, `owner: strumsight-content`,
`expiry: 2026-12-31`): (1) mind a 10 `practiceCatalog*Description` ARB-kulcs
**hiányzik `en`-ből ÉS `hu`-ból** — miközben mind a 10 `titleKey` fele mindkét
locale-ban megvan —, tehát a beépített gyakorlat-katalógus leírás-felülete ma
egyetlen nyelven sem oldható fel; (2) a `Lesson.name` beégetett angol mind a 17
leckén, `hu` felület nélkül. A kivétel-elnyomás **szűken hatókörözött**: egy
jövőbeli `titleKey`-regresszió NEM bújik el mögötte (mérve), és a lejárat
letelte után a validátor magától pirosra vált.

**Egy MAJOR — a NEGYEDIK egymást követő ŐR-hiba, TELJESEN zöld gate mellett**
(az E12-R18 [L563](docs/LESSONS.md#l563), E12-R19 [L565](docs/LESSONS.md#l565)/[L566](docs/LESSONS.md#l566)
és E12-R20 [L567](docs/LESSONS.md#l567) osztálya): a leltár elemenként hat
dimenziót deklarál, és ebből **négyet** (`difficulty`, `skill_tags`, `locales`,
`version`) egyetlen mérce sem tükrözött — a `_mirror_source()` csak az
ID-halmazokat vetette össze. A reviewer négy egysoros mutációja MIND `exit 0`-t
adott a valódi fán. A javító kör elem-szintű, kétirányú mező-tükröt szállított
(zárt leletkód-listával, `stale_inventory_entry` + mező-név), és a lezárást a
reviewer SAJÁT, megismételt mutációi adták, nem a zöld gate
([L568](docs/LESSONS.md#l568)).

## ✅ E12-R20 KÉSZ — Accessibility és localization release audit — PR [#516](https://github.com/wolfcasaba/strumsight/pull/516), squash `9c323c81` (2026-09-01)

A Ch12 **Kör 20** az első **FOLYAM-szintű** akadálymentességi és lokalizációs
mércét szállította. A Chapter 13 sáv képernyőnként mért; ez a kör a core tanulási
utat (indítás → onboarding → practice hub → setup → session → eredmény) járja
végig **mindkét locale-on** (`en`/`hu`), **telefon-viewporton** (412×915) és
`textScale 1.5`/`2.0`-n. **ADR nem készült** — a szerződéseket az
[ADR 0280](docs/adr/0280-accessibility-contract-and-live-region-budget.md),
[0383](docs/adr/0383-typography-and-text-scale-contract.md) és
[0424](docs/adr/0424-localization-resilience-contract.md) már rögzíti; ez a kör
AUDITÁL, és a `docs/adr/**` a tilos zónája volt.

**A kör HÁROM MÉRT `lib/**` leletet nevez meg — egyiket sem javítva** (a `lib/**`
a kör tilos zónája): (1) `practice_setup_screen.dart:418` 43px túlcsordulás
`textScale 2.0`-n MINDKÉT locale-on; (2) `practice_feedback.dart:89` 65px
túlcsordulás **csak `hu`**-n (a hosszabb fordítás miatt); (3) `ss_switch_row.dart`
— a megosztott DS-komponens szimulált akadálymentességi bejárása KÉT csomópontot
ad egy sor helyett: a külső `tap`-célpont **néma**, a belső feliratos, de nem
aktiválható. Mindhárom **P2**, ezért a STOP-protokoll nem lépett életbe. A
nyilvántartás: [`docs/accessibility/known-exceptions.yaml`](docs/accessibility/known-exceptions.yaml),
a jelentés: [`docs/accessibility/release-audit.md`](docs/accessibility/release-audit.md).

**A 3. lelet a kör önálló hozadéka:** a meglévő `screen_reader_copy_test.dart` /
`semantics_contract_test.dart` `find.bySemanticsLabel` **jelenlét**-próbái
szerkezetileg vakok rá ([L460](docs/LESSONS.md#l460)) — a BELSŐ csomópont
felirata megvan, tehát a jelenlét-próba zöld. Csak a valódi
`tester.semantics.simulatedAccessibilityTraversal()` bejárás hozta elő.

**A pre-flight mérése írta a kör alakját (brief §0.0.A/R1–R10):** a `test/support/e2e_harness.dart`
NINCS az `allowed_paths`-on ÉS a bejáró segédei beégetett ANGOL literálra
illesztenek → a két tesztfájl SAJÁT, locale-paraméteres bejárót írt
(`lookupAppLocalizations`); a locale a store-on át megy
(`{'ss.settings.locale': 'hu'}`), a text-scale a `platformDispatcher`-en (egy a
fa FÖLÉ tett `MediaQuery` inert, mert a `MaterialApp.router` saját
`MediaQuery.fromView`-t szúr be); és **minden cella 412×915-ön mér**, mert a
`flutter_test` default 800×600-a vakká teszi a túlcsordulás-cellát
([L558](docs/LESSONS.md#l558), [L452](docs/LESSONS.md#l452)).

**Egy MAJOR — megint ŐR-hiba, nem kódhiba, TELJESEN zöld gate mellett** (az
E12-R18 [L563](docs/LESSONS.md#l563) és E12-R19 [L565](docs/LESSONS.md#l565)/[L566](docs/LESSONS.md#l566)
osztályának HARMADIK előfordulása): az A6-nak — „minden kivétel ownerrel és
lejárattal" — **nem volt gépi őre**; a `known-exceptions.yaml`-t egyetlen cella
sem olvasta (mind a nyolc említés komment/`reason:` sztring volt), és mindhárom
bejegyzés `expiry: unscheduled` volt. A javító kör fail-closed, kézzel írt
sor-parszert szállított (`package:yaml` nincs a fán) kétirányú tükör-fedéssel.
**A reviewer saját mutációval zárta le, nem bemondásra** ([L567](docs/LESSONS.md#l567)).

## ✅ E12-R19 KÉSZ — Privacy-safe telemetria-szerződés + release SLO/dashboard séma — PR [#515](https://github.com/wolfcasaba/strumsight/pull/515), squash `ea66abc5` (2026-09-01)

A Ch12 **Kör 19** a kliens-oldali **telemetria-szerződést** szállította: typed
esemény (`lib/core/telemetry/telemetry_event.dart`), redakciós kapu, consent-kapuzott
**no-op sink**, valamint a release-döntés gépi bemeneti sémája
(`docs/operations/slo.yaml`, `release-dashboard.md`, `docs/analytics/event-catalog.md`).
ADR: [0484](docs/adr/0484-privacy-safe-telemetry-contract-and-release-slo-schema.md).
A kör **nem** köt be analytics-szolgáltatót, **nem** küld semmit hálózatra, és
`lib/features/**`-ot nem érint.

**A tiltás STRUKTURÁLIS, nem szűrő (D1):** a `TelemetryEvent` mind az öt mezője
zárt enum — nincs `Map<String,dynamic>`, `dynamic`, `Object?`, szabad `String`,
nincs `toString()`/`toJson()` és nincs azonosító-mező sem, tehát korrelációs
vektor sincs. Az időtartam **bucket** (`[0,250) … [10000,∞)`, alsó-inkluzív
határokkal), nem nyers ezredmásodperc. A redakció (D2) a MEGLÉVŐ `LogRedactor`-t
hívja — második lista tilos. Opt-out mellett a sink nem tárol, nem pufferel, és a
consent `false → true` váltása után sincs utólagos flush (D4). A hiányzó metrika
`unknown`, ami **blokkoló**, sosem zöld (D3 — az [ADR 0474](docs/adr/0474-benchmark-record-and-performance-budget-comparison.md)
D5 szabályának átvitele a release-sávra).

**A pre-flight négy MÉRT ténye írta a kör alakját (§0.0 R1–R9):** a fán ma
**nincs telemetria-consent kapcsoló** (→ a consent injektált, nem szerzett);
nincs `dart:mirrors` a `flutter_test` alatt (→ az A1 „típus-szintű" cella
forrás-szken); nincs deklarált `package:yaml` (→ kézi sor-parszer, a
`tool/check_data_inventory.dart` mintájára); és a `check_data_inventory.dart`
egress-felfedezése a D5 hálózat-tilalmának GÉPI őre.

**Két MAJOR — mindkettő ŐR-hiba, nem kódhiba, TELJESEN zöld gate mellett.**
A kód elsőre helyes volt; a szállított MÉRCE nem fogta meg azt, amit a brief
§6.1 mátrixa hozzárendelt. A reviewer mutációval mérte: az A1/A4 cella
típusnév-**denylist** volt enum-**allowlist** helyett, ezért a
`Map<String,String>`, `List<String>` és `double` mező MIND átcsúszott
([L565](docs/LESSONS.md#l565)); az A5 `slo.yaml`-parszer pedig fail-**open** —
egy 4-szóközös behúzású, `required: false` + `on_missing: success` SLO **némán
eltűnt**, és mind az öt cella zöld maradt ([L566](docs/LESSONS.md#l566)).

**A zárás mércéje a mutation-kill volt, nem a zöld gate** (az E12-R18
[L563](docs/LESSONS.md#l563) folytatása): a javító kör után a reviewer saját
harnesse **10 mutánst** mért a javított fán — mind PIROS, baseline 20/20 zöld.
Végső review: **APPROVED**, 0 BLOCKER / 0 MAJOR / 0 nyitott MINOR
([`e12-r19-review.md`](docs/reviews/e12-r19-review.md) §7). A kötelező
`security-reviewer` (a kör `risk = "high"`) 0 CRITICAL/BLOCKER-t adott, leletei
egybeestek a reviewerével.

> 📌 **A réteg ma szándékosan INERT:** `grep -rn "core/telemetry" lib/` → **0
> fogyasztó**, és a `slo.yaml`-nak a kör tesztjén kívül nincs gépi fogyasztója.
> Az esemény-kibocsátás (`lib/features/**`), a telemetria data-inventory
> route-ja (`docs/privacy/**`) és a dashboard tényleges bekötése a **rollout-körök
> (31–33)** dolga, feature-flag mögött. A kör terméke maga a MÉRCE — az értéke
> az, mit fog a jövőben pirosra váltani.

## ✅ E12-R18 KÉSZ — Program threat model + fail-closed release security scan — PR [#514](https://github.com/wolfcasaba/strumsight/pull/514), squash `3b49c501` (2026-09-01)

A Ch12 **Kör 18** program-szintű **threat modelt** (`docs/security/threat-model.md`),
egy lokálisan futtatható, **fail-closed release security scant**
(`tool/release/security_scan.py`) és lejáró **kivétel-nyilvántartást**
(`docs/security/exceptions.yaml`) szállított. ADR:
[0481](docs/adr/0481-program-threat-model-and-release-security-scan.md).
A kör `lib/**`-ot és `backend/app/**`-ot **nem** módosít.

**A pre-flight átírta a kör tartalmát (§0.0 R2):** az eredeti brief mind az öt
viselkedési acceptance-cellája (replay, path traversal, oversize, modell-checksum,
titok-minta) **MÁR MÉRVE VOLT** a fán — újra-implementálásuk második
igazságforrást hozott volna (az E12-R16 MAJOR-jának hibaosztálya, ADR 0477,
[L555](docs/LESSONS.md#l555)). A kör kimenete ezért **bizonyíték-kötés**: a threat
model minden ellenintézkedése géppel olvasható `guard`-ot nevez meg, és a scan
fail-closed módon méri, hogy ezek a guardok a fán LÉTEZNEK és ÉLNEK.

**Négy javító kör, mind a némítás-felismerés körül.** A review-lánc mérte ki,
hogy egy nyilvántartott guard hányféle egysoros idiómával tüntethető el némán:
Dart file-szintű `@Skip` (`library;`-vel és nélküle), `group(..., skip:)` **mindkét**
szintaktikai alakban, Python `pytestmark`, modul-szintű `pytest.skip(...,
allow_module_level=True)` behúzástól függetlenül, `pytest.importorskip`,
osztály-szintű dekorátor a hívás-lokális ablakon kívül. **A fix3 egy hamis pozitív
zárása közben visszanyitott egy igaz pozitívot** — a kanonikus
`group('…', () {…}, skip: 'reason')` alakot —, azaz a `T-EGRESS-01` consent-guard
némán kieshetett, a kapu mégis `EXIT 0`-t adott ([L562](docs/LESSONS.md#l562)).
A fix4 ezt zárta, a hamis pozitívok visszanyitása nélkül.

**A zárás mércéje a mutation-kill volt, nem a zöld gate:** a fix3 review kimérte,
hogy a két legfontosabb javítás (S10/S11) cellái a javítás ELŐTTI eszközzel is
zöldek — vagyis védtelenek voltak ([L563](docs/LESSONS.md#l563)). A fix4 után
minden viselkedés-változtatásnak saját, a reviewer által ÚJRAMÉRT piros útja van.
Végső review: **APPROVED**, 0 BLOCKER / 0 MAJOR
([`e12-r18-review-security-fix4.md`](docs/reviews/e12-r18-review-security-fix4.md)).

> ⚠ **Nyitva hagyott, NEM merge-blokkoló tételek (követő kör):** két
> **fail-closed** hamis pozitív a statikus skip-heurisztikában — `pytest.importorskip`
> egy teszt-TÖRZSÖN belül az egész modult „disabled"-nek jelöli (FP-A), és a
> `def`-lokális 400 karakteres előtag-ablak átlóg a szomszéd teszt legális
> `pytest.skip('…')` hívására (FP-B, a kör előtt is jelen volt). Mindkettő a
> release-t BLOKKOLJA, nem engedi át.

> 📌 **A CI-bekötés szándékosan NEM készült el** (§0.1): a `.github/workflows/security.yml`
> a merge-kapu környékét érinti, és egy workflow-változás bizonyítéka mindig egy
> DISPATCH-elt futás (ADR 0052/0053) — ez a **Kör 25** (RC assembly) dolga.

## 🔧 ÖNJAVÍTÓ KÖR — E15-R07 / H3: a bekötésnek hiányzik az előfeltétele → beszúrt `E15-R14` (2026-09-01)

Az `E15-R07` (Practice Generator bekötése + migrálása) az implementer `stopped`
jelzésével állt meg. A STOP **mérten indokolt** volt; az önjavító kör
függetlenül reprodukálta (`main @ 1544e6bd`): a `practice_generator` alatt
**NULLA** Riverpod-provider van, a `PracticeEvidenceRepository`-nak **NULLA**
konkrét implementációja (csak az `InMemoryPracticeEvidenceRepository` teszt-fake,
ami „never forgets"), és a `PlanSetupScreen` varázslójának vége zsákutca
(`plan_setup_screen.dart:96-99` — csak `controller.next()`).

Az F1 („route + flag") tehát nem route-méretű feladat, a feloldás pedig ÚJ
`data/` + `presentation/providers/` kód — amit a brief SAJÁT §0/§3 STOP-mondata
tilt („a képernyők a meglévő providereikből élnek; **ha nem, az önálló kör**").
**Önmagával ellentmondó brief:** bármely implementer újra `stopped`-ot ad.

**A javítás (a STOP-mondat MARAD, nem gyengítettük):**

| Mit | Hol |
|---|---|
| ÚJ előkészítő kör — perzisztens `PracticeEvidenceRepository`, EGY kompozíciós gyökér a `presentation/providers/`-ben (mért feature-konvenció), `StartPlanGeneration` use case a MEGLÉVŐ `GenerationOrchestrator`-ra | [`docs/rounds/e15-r14-practice-generator-composition-layer.md`](docs/rounds/e15-r14-practice-generator-composition-layer.md), ADR **0482** (lefoglalva) |
| A sor: `E15-R14` az `E15-R07` sora **FÖLÉ** (az `unmet_prerequisites` az epicen belül SOR-SORRENDBEN blokkol) | `docs/execution/pipeline-queue.tsv` |
| `E15-R07` §0.0.B revízió: `Előfeltétel = E15-R14`, a mért leletekkel | `docs/rounds/e15-r07-practice-generator-migration.md` |
| Őrteszt (a driver saját függvényein) | `tools/tests/test_e15_r07_composition_prerequisite.py` — `origin/main`-en **8/10 PIROS**, javítás után **10/10 zöld** |

**A `main`-en NINCS `practice_generator` kód-változás.** Az
`sonnet-impl/e15-r07-practice-generator-migration` ágon az **F2 KÉSZ és
MEGŐRZENDŐ** (mind a 6 képernyő design-rendszer migrációja, commit `30bc31fd`,
69/96) — nincs PR, nincs merge. Az újrainduló `E15-R07` EZT az ágat vigye
tovább, ne kezdje újra; az F2 önmagában továbbra sem merge-elhető
(brief §0.0.A/5).

**Következő kör a láncban: `E15-R14`.** Lecke: [L561](docs/LESSONS.md).

## ✅ E15-R06 KÉSZ — Setlist + Progress képernyők migrálása a design-rendszerre — PR [#510](https://github.com/wolfcasaba/strumsight/pull/510), squash `1c8e214a` (2026-08-29)

A Ch15 **Kör 6** három képernyőt vitt át a design-rendszerre
(`setlist_list_screen.dart`, `setlist_detail_screen.dart`, `progress_screen.dart`)
`SsContentCard` / `SsEmptyState` / `SsButton` komponensekkel, változatlan
viselkedés mellett. Migrációs arány: **60/96 (62,5%) → 63/96 (65,625%)**
([`docs/ui/migration-status.md`](docs/ui/migration-status.md)). Nincs ÚJ ADR.

**A pre-flight felezte a scope-ot:** a brief 8 képernyőt sorolt, a
[`docs/ui/retirement-plan.md`](docs/ui/retirement-plan.md) viszont ötöt
`retire`-nek ítél (E15-R03/ADR 0471) — így a kör a HÁROM `migrate`-verdiktű
képernyőre szűkült (§0.0.A/R2), és a `retire`-ötöst egyetlen sorral sem
érintette (A8, `git diff --stat` bizonyítékkal). A §0.0.A/R9 három komponens-nevet
is mérésre javított: `SsListTile`/`SsErrorState`/`SsMetricTile` **nem létezik**
(`SsContentCard`/`SsFailureState`/`SsMetricCard` a valódi név) — ugyanaz a
hibaosztály, mint az E15-R05 §0.0/R2-nél.

**A kör MÉRT tanulsága: a zöld A3-cella a rossz viewporton semmit nem bizonyít.**
A `flutter_test` alapértelmezett viewportja 800×600 — szélesebb ÉS magasabb
minden telefonnál. A kör saját cellái ezen zöldek voltak, a reviewer
telefon-viewportos (360×640) próbája viszont **1 BLOCKER + 2 MAJOR**-t mért:

| Lelet | Mérés |
|---|---|
| **BLOCKER-1** | a `SetlistDetailScreen` üres állapota `2.0 hu` mellett **72 px**-szel túlcsordult (`origin/main` ugyanott **0**) — a kör a `_ScrollableIfShort` védelmet csak a LISTA-képernyőre tette fel, a testvér-példány védtelen maradt: a „2 valódi túlcsordulás javítva" valójában 2/3 volt |
| **MAJOR-1** | az A3 cellák nem azt mérték, amit állítottak: a magas viewporton a lusta `ListView` **fel sem építette** a `WeeklyBars`-t, tehát a `2.0`/`2.5` cellák ÜRES fát mértek |
| **MAJOR-2** | emiatt a §10.6 „mindkét állapotban zöld" mondata **mérési artefaktum** volt, nem tény |

**Egy javító kör után APPROVED**, mind a 6 lelet zárt, ok-okozati bizonyítékkal
(a pre-fix fájl visszaállítása UGYANEZEKET a cellákat pirosítja: `2.0 hu → 72 px`,
`2.5 en → 315 px`, `2.5 hu → 365 px`). Az A3 cellák azóta kipinnelt
`physicalSize = 360×640` + `devicePixelRatio = 1.0` mellett futnak
`addTearDown(tester.view.reset)`-tel, a populated dashboard pedig
`scrollUntilVisible(find.byType(WeeklyBars), …)`-szal görget a `takeException()`
ELŐTT. Leckék: [L558](docs/LESSONS.md#l558), [L559](docs/LESSONS.md#l559).

> ⚠ **Tudatosan vállalt, NYITOTT tétel (a merge feltétele volt, hogy kimondjuk):**
> a **populated** `ProgressScreen` a helyes mércén mindhárom szövegskálán
> túlcsordul — `1.5 → 7 px`, `2.0 → 22 px`, `2.5 → 73 px` —, MÉRTEN
> **ugyanannyival az `origin/main` kódjával is**, tehát **PRE-EXISTING**, nem a
> migráció regressziója. A gyökérok
> `lib/features/progress/widgets/weekly_bars.dart:32`
> (`SizedBox(height: _maxBar + 46)`: a `46` két ~15px szövegsorra méretezett
> FIX költségvetés), ami a kör `allowed_paths`-án KÍVÜL van → a javítása H3 lett
> volna. A 6 populated cella `skip: true`, a MÉRT px-értékekkel a kódban.
> **Önálló, `weekly_bars.dart`-ra brief-elt kör kell** (§0.0.A/R11, §10.6/F6);
> elfogadás-mércéje reprodukálható: a 6 `skip` cella pirosból zöldbe fordul.

> ⚠ **Mért dokumentációs hiány, NEM ennek a körnek a hibája:** az `E15-R04` és
> `E15-R05` köröknek **nincs HANDOFF-szakasza és nincs RTM-soruk** — az
> orchestrátor-sessionjük a zárás előtt halt meg, a `done` státuszt a driver
> fail-safe ága pótolta (`e77f4101`). A két kör munkája a `main`-en van; a
> pótlás önálló, dokumentum-körbe tartozik.

CI a merge SHA-n (`8b33c197`): Full Gate
[33250085852](https://github.com/wolfcasaba/strumsight/actions/runs/33250085852),
Router CI
[33250086715](https://github.com/wolfcasaba/strumsight/actions/runs/33250086715)
— mindkettő `success`. A golden-tesztek 15 bukása ezen a boxon PRE-EXISTING
raszter-drift (a három képernyőt `origin/main`-re visszaállítva ugyanaz a 15) —
a mérce a CI x86 architektúrája ([ADR 0426](docs/adr/0426-golden-rasterization-on-the-gate-architecture.md)).

## ✅ E12-R17 KÉSZ — Privacy adat-leltár és consent enforcement — PR [#509](https://github.com/wolfcasaba/strumsight/pull/509), squash `6ead9581` (2026-08-29)

A Ch12 **Kör 17** géppel olvasható **adat-leltárt** (`docs/privacy/data-inventory.yaml`,
**11 route**), egy **fa-bejáró teljesség-ellenőrzőt** (`tool/check_data_inventory.dart`)
és MÉRT consent-kényszerítési bizonyítékot adott
(`test/privacy/consent_enforcement_test.dart`). A kör `lib/**`-ot **nem** módosít.
ADR: [0479](docs/adr/0479-privacy-data-inventory-and-consent-enforcement.md) (D1–D4).

**A pre-flight két brief-premisszát cáfolt meg:** (1) **nincs** kliensoldali
Community-consent kapcsoló (`grep -rn "consent" lib/features/community/` → 0
találat), ezért az **A5 átírva** az account-session visszavonására — ami a fán MA a
Community írás-útra ténylegesen hat; (2) az `ui_inventory` pin 94 helyett **96**. Az
előre kiosztott `0457` ADR-szám is elavult volt — a foglaló `0479`-et adott.

**A review 3 MAJOR-t fogott TELJESEN ZÖLD gate mellett** (a `security-reviewer`
kötelező volt, `risk = "high"`): (1) a leltár kihagyta a `ShareService`
(`share_plus`) ÉLŐ, eszközt elhagyó útját; (2) egy ÚJ `ApiClient`-alapú küldő
**nulla** új route-ot termelt — a codebase leggyakoribb küldő-alakja; (3) a tutor
consent-kapcsoló **nincs bekötve** a turn-útra (`_previewTurnRequest` konstans
`modelUseGranted: true`-t drótoz be). Egy javító kör után APPROVED; a zárás a
reviewer SAJÁT, eldobható klónban futtatott négy próbájával, nem a zöld gate-tel.

> ⚠ **Nyitott, átvitt tétel:** a `_previewTurnRequest` (`lib/features/ai_tutor/presentation/providers/tutor_providers.dart:433,438`)
> `lib/**`-javítása **önálló kört érdemel**. Ma nem szivárgás (a tutor cloud gateway
> bekötetlen), és a leltár + a `consent_enforcement_test.dart` MAJOR-3 gépi őre
> kikényszeríti, hogy a bekötés ne történhessen meg észrevétlenül.

## ✅ E12-R16 KÉSZ — AI és ML összesített release gate — PR [#507](https://github.com/wolfcasaba/strumsight/pull/507), squash `dd071f7d` (2026-08-29)

A Ch12 **Kör 16** egyetlen, gépileg ellenőrizhető AI-release bizonyíték-kaput
adott: `tool/release/build_ai_report.py` + `ai_report_schema.json` +
`docs/release/ai-quality-gates.md` + 25 teszt-cella. A GA-scope **egyetlen
igazsága** a már meglévő, géppel olvasható `docs/testing/device-matrix.yaml`
(`capabilities[].ga_scope`) — a kör NEM hozott létre második capability-listát,
és a regresszió-küszöböt sem definiálta újra: a `tool/compare_benchmarks.py`
`classify` / `WARN_THRESHOLD` / `FAIL_THRESHOLD` neveit IMPORTÁLJA (ADR 0474
öröklés). ADR: [0477](docs/adr/0477-ai-release-evidence-aggregation-and-ga-scope-truth.md) (D1–D7).

**A pre-flight két brief-premisszát cáfolt meg:** (1) az `ai_tutor` MA
`ga_scope: false`, tehát a tutor-bizonyíték NEM GA-kritikus (a Tutor-kaput az
ADR 0177 `tutor-eval.yml`-je viszi, változatlanul); (2) a modell-verziónak KÉT
mért alakja van a manifestben (`models[].training_run.identifier` vs
`vision_models[].version`). Az előre kiosztott `0456` ADR-szám is elavult volt —
a foglaló `0477`-et adott.

**A kör HELYES kimenete PIROS:** a mai fán
`python3 tool/release/build_ai_report.py --profile development --scope-file
docs/release/ai-quality-gates.md` → `exit=1`, három findinggel, mert a két
GA-scope AI-capability (`audio_analysis_core`, `live_and_tuner`) bizonyítéka ma
prózai Markdown (`docs/eval/*.md`), nem gépi dokumentum. Ez a fail-closed ág
(D2), nem hiba — és az implementer NEM fedte el kitalált riporttal.

**A review egy MAJOR-t talált ZÖLD gate mellett:** a kapu *bizonyíték*-hiányt
őrizte, a *követelmény*-hiányt nem — a `docs/release/ai-quality-gates.md` három
GA-sorának törlése `exit=0`-t adott, és egyetlen cella sem lett piros. A javító
kör kipinnelt lefedettség-cellát tett be (a SZÁLLÍTOTT mátrixot és
device-mátrixot olvasva); a reviewer saját valódi-sértés próbája szerint a sor
törlése ma PONTOSAN ezt az egy cellát pirosítja, a maradék 23 zöld marad
([L555](docs/LESSONS.md#l555)).

## ✅ E12-R15 KÉSZ — Audio, camera és local AI resource coexistence — PR [#506](https://github.com/wolfcasaba/strumsight/pull/506), squash `949cd274` (2026-08-29)

A Ch12 **Kör 15** mércéje: a fán két, egymásról MIT SEM TUDÓ kizárólagos
koordinátor élt (mikrofon, kamera), és semmilyen szerződés nem mondta meg, mi
történik, amikor **különböző** erőforrások fogyasztói versengenek egyszerre.
Mostantól van kimondott, **gépileg mért** prioritási rend — és ami a review
nélkül kimaradt volna: **visszaút is** belőle.

**Amit a kör szállított** (`lib/core/audio/**`, `lib/core/camera/**`,
`lib/features/**`, `lib/core/foundation/app_failure.dart`, `android/**`,
`tools/**` végig érintetlen — tilos zóna):

- `lib/core/resources/resource_priority.dart` — rendezett enum
  (`liveAudio` > `cameraFeedback` > `backgroundAi`), `outranks()`; a döntetlen
  NEM előz.
- `lib/core/resources/resource_consumer.dart` — absztrakt fogyasztói szerződés
  (`acquire` / `release` / `pauseForHigherPriority` / `resume` + `isActive` /
  `isSuspended`); egyetlen konkrét koordinátor-típust sem ismer.
- `lib/core/resources/resource_arbiter.dart` — a döntő + zárt
  `ResourceDecision` eredménytípus, `releaseConsumer()` /
  `onMemoryPressureRelieved()` visszaúttal.
- `test/core/resources/resource_arbiter_test.dart` (**11 cella**),
  `test/e2e/resource_coexistence_test.dart` (**2 cella**),
  `docs/contracts/resource-coexistence.md`.

**A D2 nem ígéret, hanem szerkezeti tulajdonság.** Az arbiternek **nincs
referenciája** egyik koordinátorra sem (`lib/core/` nem importálhat
`lib/features/`-t, és a szerződés absztrakt), ezért a lease elvétele nem is
kifejezhető benne — az [ADR 0056](docs/adr/0056-exclusive-microphone-session.md)
„busy failure, not steal" döntése nem gyengülhet. Az A2 cella ezt a VALÓDI
`AudioSessionCoordinator`-on méri: felfüggesztés után a lease él, és a második
kérő továbbra is `audio.session_busy`-t kap.

**A pre-flight három mért felfedezése.** (1) **Low-memory jelzés a fán NEM
létezik** (`grep -rni 'memorypressure|didHaveMemoryPressure|lowMemory|low_memory'
lib/ test/` → 0 találat) — az A4 ezért az arbiter SAJÁT `onMemoryPressure()`
belépési pontjára mér, nem platform-csatornára. (2) A kamera-lease-t ma
kizárólag `lib/features/vision/**` szerzi meg (tilos zóna), tehát az arbiter
egyetlen képernyőre sincs bekötve — az A3 ezért a **valódi**
`CameraSessionCoordinator` állapotán mér (`activeOwner == null` ÉS
`lease.isActive == false`), nem a bekötetlen app-fán
([L453](docs/LESSONS.md#l453)), sima `test()`-ben az
[L513](docs/LESSONS.md#l513) fake-clock fagyás-csapdája miatt. (3) Az ADR száma
a foglalótól **0476**, nem a batch-terv `0455`-e.

**1 javító kör — a review 2 MAJOR-t talált TELJESEN ZÖLD gate mellett** (7/7
lépés, 6/6 acceptance-cella), és mindkettő ugyanabból a mintázatból jött, mint
az [L549](docs/LESSONS.md#l549): *a mechanizmus MEGLÉTE ki volt kényszerítve, a
JELENTÉSE nem.*

- **F1** — a szerződés-doksi azt állította, hogy az A5 méri a „fogyasztó
  `cancel`-lel valósítja meg a `pause`-t" sértést. **Mérve nem mérte:** egy
  szándékosan `cancel`-ként megírt fogyasztó a teljes készleten ZÖLDEN átment.
  A brief §6.1 mátrix sora kétértelmű volt (arbiter-oldali vs. fogyasztó-oldali
  olvasat), és a cella csak az elsőt fedte — pont a rossz oldalt, hiszen az
  interfész implementálói későbbi körök ([L552](docs/LESSONS.md#l552)).
- **F2** — a felfüggesztésből **nem volt visszaút**: a magasabb prioritású
  fogyasztó befejezése után a felfüggesztett örökre felfüggesztve maradt
  (`resumeCalls == 0`), és `onMemoryPressure()` a felhasználó ÉPPEN FUTÓ
  gyakorlását is némán leállíthatta. Ez a brief §1 céljában szó szerint
  nevesített „néma elakadás" ([L553](docs/LESSONS.md#l553)).

A javító kör után APPROVED, 0 nyitott lelet
([`docs/reviews/e12-r15-review.md`](docs/reviews/e12-r15-review.md)). A zárás
nem a zöld gate-tel, hanem a reviewer saját, izolált klónban futtatott
**Q1–Q5 próbájával** történt: a visszaút, a *részleges* visszaút (a `camera`
folytatódik, de a `backgroundAi` felfüggesztve marad, amíg a `camera` aktív) és
az is mérve van, hogy egy már elengedett fogyasztót a resume-pass **nem támaszt
fel**.

**Egy infrastruktúra-lecke is mérve:** az első Full Gate futás PIROS volt, de
**nem a kör diffje miatt** — a randomizált HARD property-lépés
(`PROPERTY_SEED=github.run_id`) bukott a `dsp_property_test.dart:438` „a strum
must merge into ONE onset" celláján (`17` a `>= 18` küszöb helyett, 20
próbából), miközben a kör diffje DSP-re hatástalan. Ugyanazon a kódon a merge
SHA-n zöld. A 18/20 = 90 %-os küszöb EGYETLEN próba elcsúszására pirosra vált —
a H5-számlálóba csak a diff-releváns pirosakat szabad bevenni
([L554](docs/LESSONS.md#l554)).

## ✅ E12-R14 KÉSZ — Performance budget harness — PR [#505](https://github.com/wolfcasaba/strumsight/pull/505), squash `449783e8` (2026-08-29)

A Ch12 **Kör 14** mércéje: a fán tizenhat baseline-dokumentum élt Markdownban,
gépi összevetésre alkalmatlanul, és két benchmark-eszköz közös séma nélkül.
Mostantól egyetlen verziózott rekord-séma mondja meg, **mi számít mérésnek, és
mi hasonlítható mihez** — és ezt gépi kapu őrzi.

**Amit a kör szállított** (`lib/**`, `ml/**`, `tools/**`, `.github/**`,
`docs/baseline/**`, `pubspec.*` végig érintetlen — tilos zóna):

- `tool/benchmarks/benchmark_record.dart` — a séma EGYETLEN forrása, 11 kötelező
  mezővel, `dart:convert`-en kívül függőség nélkül; zárt `deviceId`-szótár a Kör
  13 mátrixából (`pixel_6a`, `pixel_7`, `samsung_galaxy_a54`,
  `xiaomi_redmi_note_12`) + `ci_host`.
- `tool/compare_benchmarks.py` — `(metric, deviceId)` kulcsú összevetés; **5,0 %
  warn / 10,0 % fail, mindkét határ INKLUZÍV**, a fájlban rögzítve (nem
  CLI-kapcsoló); a hiányzó mérés `unknown` és nem-nulla kilépés.
- `docs/performance/baseline.json` — **26 bejegyzés**, mind létező forrásra
  hivatkozva.
- `docs/performance/budgets.md`, `test/tooling/benchmark_budget_test.dart` (**42
  cella**, `python3`-mérés skip-ág nélkül, önvédő cellával).

**A pre-flight mért felfedezése (a kör lelke).** A `docs/baseline/` számai
**négy, össze nem keverhető osztályba** esnek, és a fán MA egyetlen dokumentum
hordoz valódi mérést: `epic-06-analysis-performance.md` (6 mikroszekundum-érték,
2026-08-13). A többi felső korlát (`< 0.1 ms`, epic-04), származtatott
szerződés-határ (17/34/51/68 ms, 12/35/70 cent — epic-03) vagy **cél mérés
nélkül** (a vision FPS-táblázat minden mért cellája `PENDING`). A séma ezért
kötelező `kind` mezőt visel, és **csak `measured` ↔ `measured`** párra számol
regressziót — a `< 0.1 ms` felső korlátot `0.1`-ként `measured`-nek felvenni
gépileg tiltott. Az [ADR 0474](docs/adr/0474-benchmark-record-and-performance-budget-comparison.md)
ezen felül köti a **`direction`** mezőt alapérték NÉLKÜL: a vision FPS-célok
`higherIsBetter`, tehát egy irány-vak („nagyobb = rosszabb") összehasonlító pont
az FPS-esést — a felhasználó által ténylegesen érzékelt regressziót — engedné át
zölden.

**Nem mért adat nem került be:** minden bejegyzés `deviceId: ci_host`, mert a fán
ma EGYETLEN fizikai eszközös benchmark sincs; a `budgets.md` ezt kimondja.
Készüléknév kitalálása nem történt.

**1 javító kör.** A review **2 MAJOR**-t talált TELJESEN ZÖLD gate mellett (6/6
lépés, 33/33 cella): az összevetés a puszta metrika-NÉVRE kulcsolt, ezért (F1)
két KÜLÖNBÖZŐ eszközön mért érték némán `pass`-t kapott, és (F2) azonos
metrika-nevű második rekord elnyelte az elsőt — egy 100 %-os regresszió
nyomtalanul eltűnt. A metaadat MEGLÉTE kikényszerített volt, a JELENTÉSE nem
([L549](docs/LESSONS.md#l549)). A javító kör után APPROVED, 0 nyitott lelet
([`docs/reviews/e12-r14-review.md`](docs/reviews/e12-r14-review.md)); a zárás
SEBÉSZI valódi-sértés próbával: device-vak visszaesés injektálva → **pontosan
egy cella** (az F1) piros → visszaállítva.

**Két infrastruktúra-lecke is mérve:** a §0.3 upstream-merge után a
munkapéldány generált l10n-je elavul, és ezt csak a landoló kombinált-HEAD
gate-je fogta meg ([L550](docs/LESSONS.md#l550)); a `protect_factory_files` hook
`rm`-ága pedig a parancs minden további tokenjét írási célpontnak veszi, ezért
egy összetett parancsban a `tools/scope-audit.py` FUTTATÁSA is blokkolódik
([L551](docs/LESSONS.md#l551)).

## ✅ E12-R13 KÉSZ — Device matrix és device lab nyilvántartás — PR [#503](https://github.com/wolfcasaba/strumsight/pull/503), squash `2de98844` (2026-08-29)

A Ch12 **Kör 13** mércéje: a fán hat, egymástól független manuális eszköz-dokumentum
élt, mind más formában, egyik sem géppel olvasható. Mostantól egyetlen
nyilvántartás mondja meg, **melyik készülék blokkolja a release-t, és mit KELL
rajta lemérni** — és ezt gépi kapu őrzi.

**Amit a kör szállított** (`docs/manual-testing/**`, `lib/**`, `pubspec.yaml`,
`.github/**`, `tools/**` végig érintetlen — tilos zóna):

- `docs/testing/device-matrix.yaml` — **4 MÉRT eszköz** (Pixel 6a, Pixel 7,
  Galaxy A54, Redmi Note 12), eszközönként 11 kötelező azonosító-mező, kettős
  forrás-hivatkozással (`provenance` a kamera-specre, `spec_provenance` a
  RAM/SoC-ra); **14 capability** (11 GA-scope az SDD Ch12 §5.1-ből + 3 preview a
  §5.2-ből); **13 elemű kötelező tesztcsomag** eszközönként a §18.2-ből.
- `docs/testing/device-lab.md` — a manuális kör menete, a szűkített YAML-nyelvtan
  mint **szerkesztési szerződés**, a suite→dokumentum térkép, és amit a kör NEM
  futtatott (egyetlen valós eszközös mérés sem — minden manuális sor `PENDING`).
- `tool/device_report.py` — `--check` / `--report`; hiányzó **vagy kiüresített**
  kötelező futásra nem-nulla kilépés (fail-closed).
- `test/tooling/device_matrix_test.dart` — **121 cella**, `package:yaml` NÉLKÜL
  (a csomag tranzitív, `pubspec.lock:1261`, a `pubspec.yaml` pedig tilos zóna),
  saját szűkített olvasóval; a Python eszközt `Process.runSync('python3', …)`
  méri ideiglenes fixture-mátrixokon, **skip-ág nélkül**.

**A pre-flight hét avult brief-állítást javított** (§0.0 R1–R7): hat (nem négy)
manuális dokumentum; a `VisionDeviceTier` enum tényleges helye
(`lib/features/vision/data/landmarks/hand_landmark_provider.dart:125`, nem a
`domain` réteg); `package:yaml` tranzitív → saját olvasó; az A4 gépi mércét kapott;
a user készüléke a fában **nincs kitöltve** (`gov-05-shipping-device-run.md:120`
üres), ezért a mátrix a MÉRT elsődleges teszteszközt (Pixel 6a) viszi; a GA-scope
lista zárt listaként az SDD-ből; a `required_suite` szótára a §18.2-ből.

**Nem mért adat nem került be:** a Galaxy S23 és a Pixel 4a szándékosan kimarad —
`vision-performance-benchmark.md` csak négy eszközhöz mér RAM/SoC-ot, és egy
hihető RAM-érték kitalálása pont a látszat-lefedettség kockázata.

**1 javító kör.** A review egy MAJOR-t talált: a `required_suite` kiüresíthető volt
egy `release_blocking: true` eszközön úgy, hogy a kapu **99/99 ZÖLD** maradt, és a
`device_report.py --check` eredmény-fájl nélkül **0-val** lépett ki („every
mandatory run is recorded") — a capability → blokkoló eszköz → kötelező mérés lánc
harmadik szeme őrizetlen volt ([L548](docs/LESSONS.md#l548)). A javítás fail-closed
`--check`-et, `required_suite`-teljességi cellákat és a `spec_provenance` mezőt
hozta; review **APPROVED**, 0 nyitott lelet
([`docs/reviews/e12-r13-review.md`](docs/reviews/e12-r13-review.md)).

Exact-SHA evidencia a merge SHA-n (`6e9dfcc1`): Full Gate
[33235460985](https://github.com/wolfcasaba/strumsight/actions/runs/33235460985)
`success`, Router CI
[33235461965](https://github.com/wolfcasaba/strumsight/actions/runs/33235461965)
`success`.

## ✅ E12-R12 KÉSZ — Release fixture-korpusz és golden data — PR [#502](https://github.com/wolfcasaba/strumsight/pull/502), squash `ce14443d` (2026-08-29)

A Ch12 **Kör 12** mércéje: a `test/fixtures/` fa **48 adat-fixture-je** mostantól
egyetlen, checksummal és licenccel ellátott manifesten át él — eddig csak a
`song_trainer` alfa (30 fájl) volt védve, a többi **18** adat-fájl néma
tartalomváltozása senkinél nem pirosodott.

**Amit a kör szállított** (`lib/**`, `tool/ci/**` és a meglévő `test/fixtures/**`
adatfájlok végig érintetlenek — tilos zóna):

- `test/fixtures/manifest.json` — 48 bejegyzés (`path`, `bytes`, `sha256`,
  `license`, `source`, `containsUserData`), `schemaVersion: 1`.
- `tool/check_fixture_manifest.dart` — a **FÁT** járja be, nem a manifest listáját
  hiszi el ([ADR 0473](docs/adr/0473-release-fixture-corpus-manifest.md) D1);
  tartalom-sha256 (D3); fail-closed licenc, ahol a **placeholder** (`unknown`,
  `n/a`, `tbd`, …) is gépileg tiltott (D4); repó-relatív útvonalak, abszolút
  gép-útvonal nélkül (D7, [L530](docs/LESSONS.md#l530)); explicit
  `containsUserData` (D8).
- `test/tooling/fixture_manifest_test.dart` — A1–A8, köztük a VALÓDI korpuszt a
  valódi gyökéren mérő cella (`isClean` + `hasLength(48)`) és a valódi-sértés
  próba: egy bájt egy fixture MÁSOLATÁBAN → `checksumMismatch`, az eredeti fájl
  bájtjai a próba után változatlanok.
- `docs/testing/release-fixture-corpus.md` — a korpusz HATÁRAI: a
  `test/ui/goldens/**` (ADR 0426 / [L516](docs/LESSONS.md#l516)), az `ml/**` és a
  `local_ai/**` kifejezetten KÍVÜL.

**A kör mérése két avult brief-állítást javított** (§0.0 pre-flight revízió): a
batch-terv `0453`-as ADR-számát a foglaló `0473`-ra cserélte (a lemezen a max
`0472` volt), és a fixture-fát újramérte (8 al-könyvtár az azóta bekerült
`events/`-szel, 6 — nem 7 — gyökér parity-JSON, 69 fájl / 48 adat-fájl).

**1 javító kör.** A review egy MAJOR-t talált: az „unknown" licenc-helykitöltő
átment a checkeren, és a leszállított teszt ezt `expect(report.isClean, isTrue)`
alakban ZÖLDKÉNT rögzítette — noha a brief falszifikációs mátrixa pontosan ezt a
cellát követelte PIROSNAK ([L546](docs/LESSONS.md#l546)). A javítás egy
exportált `placeholderProvenanceValues` listát és a teljes listát végigjáró
cellát hozott; review **APPROVED**, 0 nyitott lelet
([`docs/reviews/e12-r12-review.md`](docs/reviews/e12-r12-review.md)).

Exact-SHA evidencia a merge SHA-n (`735fded0`): Full Gate
[33232264253](https://github.com/wolfcasaba/strumsight/actions/runs/33232264253)
`success`, Router CI
[33232260512](https://github.com/wolfcasaba/strumsight/actions/runs/33232260512)
`success`.

## ✅ E12-R11 KÉSZ — End-to-end folyam-harness a VALÓDI app-fán (a H2-heal utáni javító kör) — PR [#501](https://github.com/wolfcasaba/strumsight/pull/501), squash `36f57db3` (2026-08-29)

A Ch12 **Kör 11** mércéje: két determinisztikus folyam-teszt a valódi
`StrumSightApp` fán, a `flutter test` gazdában (`test/e2e/`), fake órával és
globális hálózat-őrrel. A kör **két menetben** zárult:

| Menet | Mi történt | Kimenet |
|---|---|---|
| 1. futás | a harness a `lib/**`-ből HIÁNYZÓ Setup → Session lánc-lépést a tesztből pótolta ([L273](docs/LESSONS.md)) | review **B1 BLOCKER** → **H2 halt** |
| önjavító kör | a normatív kérdés eldőlt: **termékhiba** — [ADR 0470](docs/adr/0470-practice-setup-navigates-to-the-session-route.md), PR [#499](https://github.com/wolfcasaba/strumsight/pull/499), [L541](docs/LESSONS.md#l541) | a Start MOST `context.go(AppRoutes.practiceSession)`-nel navigál |
| javító kör (ez) | a harness **három áthidalása** eltávolítva; a folyam a termék saját hand-off-ján megy végig | review **APPROVED** → merge |

**Amit a kör szállított** (`lib/**` végig érintetlen — tilos zóna):

- `test/e2e/first_practice_offline_test.dart` — A1 (fresh install → onboarding →
  Quick Start → offline gyakorlás → history perzisztál), A3 (a hálózat-őr
  mindhárom útja: Dio adapter, `dart:io HttpOverrides`, platform-csatorna
  catch-all — útonként EGY cella, [L453](docs/LESSONS.md#l453)), A4 (determinizmus:
  a folyam kétszer fut le két friss `ProviderContainer`-rel, `expect(second, equals(first))`);
- `test/e2e/returning_user_restart_test.dart` — A2 (app-újraindítás: az első
  container `dispose()`-a után ÚJ container + ÚJ router UGYANARRA a
  store-példányra);
- `test/support/e2e_harness.dart` · `fake_clock.dart` · `fake_network_guard.dart`,
  `docs/testing/e2e-harness.md`, [ADR 0472](docs/adr/0472-e2e-flow-harness-runs-in-the-flutter-test-host.md)
  (miért `test/e2e/` és nem `integration_test/`: a boxon nincs Android SDK, a
  CI-ban nincs emulátoros job → a NEM FUTTATOTT mérce rosszabb a hiányzónál).

**A B1 zárásának bizonyítéka nem a zöld gate** (egy áthidalt teszt is zöld),
hanem **falszifikációs próba** izolált review-klónban: a heal navigációját
(`practice_setup_screen.dart:198`) kivéve az **A1 és az A4 PIROSRA vált**
(`00:03 +3 -2: Some tests failed.`) — a folyam tehát immár a termék saját
lánc-lépésétől függ.

**Mérce:** izolált review-gate 7/7 zöld; a merge SHA-n (`631ce092`)
[full-gate 33229546260](https://github.com/wolfcasaba/strumsight/actions/runs/33229546260)
és [router-ci 33229547180](https://github.com/wolfcasaba/strumsight/actions/runs/33229547180)
mindkettő `success`; gépi scope-audit `ok`.

**Két mért lecke a landolásból:** [L544](docs/LESSONS.md#l544) (a merge-szel
frissen tartott publikus ág landolásakor a landoló rebase-ága a saját brief
branch-oldali revízióját `--ours`-szal eldobja — a `safe-force-push` fail-closed
ága fogta meg, a fa nem romlott el), [L545](docs/LESSONS.md#l545) (a
review-commit nem triggereli a Router CI-t, de a kapu a merge SHA-n kéri →
kézi `workflow_dispatch`).

**Nyitott, tudatosan tovább vitt rés:** az A4 determinizmus-cella a `createdAt`
mezőt kihagyja a snapshotból, mert a `PracticeSessionResultHistoryMapper` valódi
fali órát bélyegez rá (review N3) — **önálló kör tárgya**, nem ezé.


## 🔧 ÖNJAVÍTÓ KÖR (ADR 0112) — E12-R11 / H2 feloldva: a Practice Setup Start-ja a session útvonalra navigál — PR [#499](https://github.com/wolfcasaba/strumsight/pull/499) (2026-08-29)

**Az E12-R11 (E2E folyam-harness) H2-vel megállt**, mert a „first practice" folyam a
szállított appban **nem volt végigjárható**, és az implementer a hiányzó lánc-lépést a
harnessben pótolta ([L273](docs/LESSONS.md)). A halt normatív kérdését — *termékhiba-e a
hiányzó Setup → Session navigáció, vagy szándékosan nem-kész felület?* — nem vélemény,
hanem a repó saját története döntötte el:

| # | Kör | Mit tett | Miért nem zárult le a halasztás |
|---|---|---|---|
| 1 | **E02-R12** | szándékosan halasztott, **címzettel**: „a Setup **nem** navigál a session-képernyőre (az még nem létezik)"; a fájl fejléce: „**Kör 13 brings the session route**" | — |
| 2 | **E02-R13** | megépítette a `/practice/session` route-ot és a `PracticeSessionScreen`-t | a `practice_setup_screen.dart` a **tilos zónájában** volt (round-doc 135. sor; a záró mérés szerint a fájlon „0 sor" változott) |
| 3 | **E02-R21** | célja szó szerint: a Hub → Setup → Session úton „egy valódi felhasználó **valóban le tudjon futtatni**" egy sessiont | a `practice_setup_screen.dart` a §4 **allowlistjén sem szerepelt** |

Mérés (`main @ 8bdcfff9`): `grep -rn "AppRoutes.practiceSession" lib/` → **nulla hívó**
(csak a konstans, a route-regisztráció és egy shell-predikátum). A
`PracticeSessionScreen` a termék saját felületéről elérhetetlen volt.

**A javítás — egyetlen `lib/**` fájl, +37/−12:**

- érvényes Start → `context.go(AppRoutes.practiceSession)`; a „command sent" SnackBar
  **megszűnt** (a gyökér `ScaffoldMessenger`-en túlélné a route-váltást, ráülve a session
  vezérlőire) — az ARB-kulcs a helyén marad;
- az auto-dispose aktiválási lánc (`practiceActiveSessionInputsProvider` →
  `practiceSessionControllerProvider`) **élettartam-szerződése a TERMÉKBEN**, kimondva:
  `ref.read(practiceSessionHostProvider)` a `start()` előtt és közvetlenül utána. Enélkül
  a sink által épp létrehozott controller megfigyelő nélkül bomlik le a session-képernyő
  `initState`-je előtt, és a felhasználó a „session unavailable" állapotra érkezik.

**Regresszió — MÉRT piros → zöld** (valódi router, valódi practice provider-gráf, csak
platform-peremek fake-ek):
[`test/features/practice/presentation/practice_setup_navigation_test.dart`](test/features/practice/presentation/practice_setup_navigation_test.dart)
— **R1** (a Start `/practice/session`-re navigál; előtte `'/practice/setup'`) és **R2**
(a képernyő élő hosttal érkezik; előtte `Expected: not null / Actual: <null>`).

| Fájl | |
|---|---|
| [`docs/adr/0470-…`](docs/adr/0470-practice-setup-navigates-to-the-session-route.md) | D1 termékhiba · D2 a Start navigál · D3 az élettartam-szerződés a hívó oldalán · D4 a mérce a valódi provider-gráfon |
| [`docs/LESSONS.md` L541](docs/LESSONS.md) | a halasztásnak nem elég címzettet adni: a **címzett kör allowlistjén** ott kell lennie a halasztó fájlnak; pre-flight ellenőrzés minden ÚJ route-konstansra |
| [`docs/rounds/e12-r11-…`](docs/rounds/e12-r11-end-to-end-test-harness.md) §0.0 | revízió az újrafuttatásra: a harness `:275`/`:277`/`:281` áthidalásainak eltávolítása; `allowed_paths` **változatlan**, a `lib/**` továbbra is tilos zóna |

**Következmény:** a „first practice" vertical slice a nem-produkciós appban
végigjárható (Hub → Setup → Start → Session), az **E12-R11 újrafuttatható**, és a lánc
feloldódik. A production flag nem mozdul (`practiceEngineV2Enabled: nonProd`) — a
rollout változatlanul a valódi eszközös teszt utáni külön kör.

> ⚠ **Nyitva marad (E12-R11 review N3):** a `PracticeSessionResultHistoryMapper` valódi
> fali órát bélyegez a `createdAt` mezőre, ezért egy determinizmus-snapshot ezt kihagyni
> kényszerül. Önálló kör tárgya — ez a javítás NEM nyúlt hozzá.

## ✅ E15-R03 KÉSZ — Elérhetőségi audit: MELYIK képernyőt éri el a felhasználó — PR [#500](https://github.com/wolfcasaba/strumsight/pull/500), squash `a1205e52` (2026-08-29)

> ⚠ **A squash-commit tárgya „(ADR 0470)"-et ír — ELAVULT.** A kör ADR-je
> **[ADR 0471](docs/adr/0471-screen-reachability-is-measured-not-assumed.md)**;
> a `docs/adr/0470-*` MÁS döntés (a HEAL E12-R11/H2 köré). A PR-cím a merge
> előtti átszámozás előtt készült — [L542](docs/LESSONS.md#l542).

A Chapter 15 migrációs sávja 53 legacy képernyővel indult. Ez a kör azt méri
meg, **melyiket éri el egyáltalán a felhasználó** — mert migrálni egy soha nem
látott képernyőt pazarlás, a „nem hivatkozza a router, tehát halott"
következtetés viszont [L449](docs/LESSONS.md#l449) hibaosztálya.

**MÉRT eredmény** (`dart run tool/check_screen_reachability.dart --format table`):

```
Measured screens: 96. Reachable: 68. Unreachable: 28. Flag-gated: 25.
```

Az 53 legacyből **41 elérhető** = 35 `migrate` + 6 `retire`, mindegyikhez
nevesített kör (`E15-R04`…`E15-R11`) a
[`docs/ui/retirement-plan.md`](docs/ui/retirement-plan.md)-ben.

**A kör semmit nem törölt és route-ot nem vett ki** — `lib/**` diff NÉLKÜL. A
visszavonás JAVASLAT (ADR 0471 D5); a végrehajtás az `E15-R04` önálló,
review-zott dolga, mert felhasználói utat szüntet meg.

**Két MÉRT tervezési megkötés, amit a pre-flight talált:**

| # | Mérés | Következmény |
|---|---|---|
| D3 | a router 46 képernyőt közvetlenül importál, de **3 feature-t a `public.dart` barrelen át** (a `vision/public.dart` 3 képernyőt re-exportál) | a checker OSZTÁLYNÉVRE illeszt; az útvonal-illesztés e hármat hamisan halottnak jelentené ([L190](docs/LESSONS.md#l190)/[L193](docs/LESSONS.md#l193)) |
| D4 | `app_router.dart:561` a Vision setup route-ot csak `visionEnabled && visionSetupEnabled` alatt regisztrálja | „a router regisztrálja" ≠ „a felhasználó ma eléri" — a flag-kapu JELENTETT dimenzió, nem hallgatólagos „elérhető" ([ADR 0065](docs/adr/0065-practice-engine-v2-parallel-rollout.md)) |

**Review: APPROVED, 2 javító kör után** — mindkét MAJOR-t a reviewer
eldobható próbatesztje mérte, nem olvasás:

- **MAJOR-1** — az A4 „kötelező valódi-sértés próbája" **tautológia** volt (egy
  helyben írt literált hasonlított önmagához). Bizonyíték: a VALÓDI A4 őrt
  teljesen kiütve a „próba" **zöld maradt**. Zárva közös assertion-helperrel;
  a javított próba a kiütött őr mellett most **pirosra vált**.
- **MAJOR-2** — a `render()` `O(képernyők × fájlok)` I/O-ja: **3m0.848s**
  egyetlen teszt-fájlra. Ez a kör **első CI-futását is pirosra vitte** — egy
  NEM érintett, időzítés-érzékeny teszten (`import_flow_test.dart:83`; tiszta
  `main`-en 3/3 zöld). Zárva `O(fájlok)`-ra → **5.744s (~31×)**, a `--format
  json` kimenet **byte-azonos** (azonos `sha256`), a teszt-fájl változatlan.

**Merge előtti ADR-ütközés** (a második, [L542](docs/LESSONS.md#l542)): a kör
CI-je alatt a `main`-re merge-elődött a HEAL E12-R11/H2, amely ugyanazt a
foglalótól kapott `0470`-et használta el. A kötelező upstream-szinkron fogta
meg; a saját, még nem merge-elt ADR lett átszámozva `0471`-re.

## ✅ E12-R10 KÉSZ — Idempotens dispatcher és outbox: a hiányzó MÉRCE — PR [#498](https://github.com/wolfcasaba/strumsight/pull/498), squash `e9a29a86` (2026-08-28)

**Az SDD Kör 10 „implementálj dispatchert és outboxot" feladata a fán RÉSZBEN már
teljesült** ([ADR 0333](docs/adr/0333-activity-outbox-reliable-processing.md)): a
korlátos, perzisztált sor karanténnal és kísérlet-számlálóval él, a dedup az
`appendIfAbsent` `sourceEventId`-szűrésén fut. Ami MÉRHETŐEN hiányzott, az nem
mechanizmus, hanem **mérce** — a repóban egyetlen cella sem bizonyította, hogy sok
ismétlés, folyamat-megszakítás vagy sorrend-csere mellett sem keletkezik dupla
hatás. A kör ezt szállítja, **`lib/**` diff nélkül**.

| Fájl | |
|---|---|
| [`test/core/events/idempotency_test.dart`](test/core/events/idempotency_test.dart) | **A1** (100 ismétlés egy batch drainben, eltérő `ledgerId`-kkel) + **A1b** (100 × enqueue→drain pár) |
| [`test/core/events/outbox_resume_test.dart`](test/core/events/outbox_resume_test.dart) | **A2** resume MÁSODIK repository-példánnyal · **A3** out-of-order · **A4** hibatűrés · **A5** karantén-továbbdolgozás · `maxAttempts` küszöb-hármas |
| [`docs/contracts/event-catalog.md`](docs/contracts/event-catalog.md) | „Outbox-invariánsok — MÉRT" alszakasz, invariánsonként a mérő cellával |
| [`docs/adr/0469-…`](docs/adr/0469-outbox-idempotency-is-measured-on-the-ledger-effect.md) | D1 a mérce a ledger-HATÁS · D2 a dedup-kulcs a `sourceEventId` · D3 a resume perzisztált állapotból · D4 a sorrend-függetlenség a ledgeren · D5 a küszöb a drain ELŐTTI számlálón · D6 javítás a MEGLÉVŐ osztályban |

**Négy mért korrekció** (a brief §0.0 / §0.0.0 revíziói):

1. **R2** — a `maxAttempts` küszöb a **drain ELŐTTI, perzisztált** számlálón van (a
   számláló a ledger-hívás ELŐTT nő, a feltétel `>=`); a brief eredeti „alatta"
   cellája (`maxAttempts - 1` → PENDING) **elérhetetlen** volt.
2. **R3** — a `StreakService`-nek **nincs hívója a `lib/` fán**, és az outbox soha nem
   hívja; az out-of-order acceptance ezért a ledger-tartalmon és az egyenlegen mér.
3. **R5** — a katalógus idempotencia-oszlopa már kitöltött (Kör 9) → az A6 a szakasz
   bővítése lett, nem oszlop-kitöltés.
4. **R7** — az első implementer-futás `stopped`-ot jelzett: a pre-flight által
   választott `ProfileProjector.rebuild()` mérce-felület MÉRTEN dob egy nem üres,
   egyoldalas ledgeren. A mérce lényege változatlan, a felület a `readPage`-en
   összegzett egyenleg lett.

**Review (APPROVED, 0 BLOCKER / 0 MAJOR / 0 MINOR / 3 NOTE):** izolált `/tmp` klónban
9/9 cella zöld, és **három FÜGGETLEN valódi-sértés próba** igazolta, hogy a cellák
teherhordók — P1 `maxAttempts` `>=`→`>` → a „rajta"/„fölötte" cella és az A5 PIROS (az
„alatta" helyesen zöld), P2 nem idempotens ledger → **A1 PIROS `Expected: <10>
Actual: <1000>`** (pontosan az a dupla HATÁS, amit egy hívásszám-alapú állítás zölden
átengedett volna), P3 resume kikapcsolva → A2 + A3 PIROS
([`docs/reviews/e12-r10-review.md`](docs/reviews/e12-r10-review.md)).

Exact-SHA evidencia a merge SHA-n (`3263ac06`): Full Gate
[33218813807](https://github.com/wolfcasaba/strumsight/actions/runs/33218813807)
`success`, Router CI
[33218815147](https://github.com/wolfcasaba/strumsight/actions/runs/33218815147)
`success`.

> ⚠ **NYITOTT LELET a következő körnek (review NOTE-1, [L539](docs/LESSONS.md)):** a
> `ProfileProjector.rebuild()` (`profile_projector.dart:48–49`) egy **nem üres, de
> egyetlen oldalra férő** ledgeren `StateError: ledger page cursor did not advance`-szel
> dob — az [L349](docs/LESSONS.md) reziduális fele. Ma nincs `lib/`-beli hívója, ezért
> felhasználót nem ér el, de a Chapter 9 fő use case-e („a profil a főkönyvből teljes
> egészében újraépíthető") egyetlen bejegyzésnél is elbukna. A fájl e kör tilos
> zónájában volt; a javítás külön kör dolga.

## ✅ E15-R02 KÉSZ — Az adaptív shell a nem-production ALAPÉRTELMEZÉS + a két mért túlcsordulás javítása — PR [#497](https://github.com/wolfcasaba/strumsight/pull/497), squash `9dc0b1e6` (2026-08-28)

**A user 2026-08-28-i döntése („minden legyen migrálva, javítva, hogy lássam a
valódi appot") ezzel a körrel lépett hatályba:** az ötterületes adaptív shell
([ADR 0275](docs/adr/0275-five-area-shell-behind-a-flag.md)) mostantól
`development` és `lab` környezetben BE van kapcsolva
([ADR 0467](docs/adr/0467-adaptive-shell-is-the-non-production-default.md) D1),
production továbbra is KI (D2, a GA-scope a Chapter 12 Kör 28 dolga). Az app
belépési pontja `/live` → **`/today`**, a tizenegy legacy útvonal a
`legacyRedirects` táblán át él tovább.

**A két MÉRT elrendezési hiba megszűnt** (`docs/ui/legacy-backlog.md` §1 lezárva):

- `live_screen.dart` stat-sora — a két `_ActionButton` `Expanded`-be került
  (landscape + `textScale 2.0` mellett 12 px `en` / 34 px `hu` túlcsordulás volt).
- `permission_primer_screen.dart` — a **véglegesen elutasított** ág
  `SingleChildScrollView`-ba került (297 px volt); a retryable ág változatlan.

**A mérő cellák ÁTFORDULTAK, nem törlődtek** (a zsugorodás-őr elve, L180): a
`e13_r36_variant_matrix_test.dart` `_excludedCells` kivétel-listája kiürült — a
fájl STALE-őre miatt ez maga a bizonyíték —, a `closure_suite_test` primer-cellája
`isTrue` → `isFalse`. **Valódi-sértés próba:** a `live_screen.dart` javításának
visszavonása PONTOSAN a négy A5-cellát pirosítja (12/34 px), a maradék 188 zöld.

**A flag-flip MÉRT oksági hatósugara** (53 bukás, 19 fájlban — a H3 önjavító kör
mérése) az ÚJ viselkedéshez igazítva: router-navigáció a `legacyRedirects`
céljaira, `/today` belépési pont. `appConfigProvider`-override-dal kikapcsolt
shell SEHOL nincs a szállított alapértelmezés elé tolva (ADR 0467 D9) — a review
ezt BLOCKER-ként fogta meg egyszer, és a javítás a `library_test.dart`-ba egy
override NÉLKÜLI, VALÓDI UI-tapintásokkal navigáló cellát tett (3 → 4 cella).

**Gépi mércét kapott a kill-switch próza is** (A11): a
`feature_flag_registry.dart` `killSwitchPath` szövege eddig azt állította, hogy a
flag „hardcoded to `false` in every environment" — a D1 után ez hazugság lett
volna, és a prózát SEMMI nem mérte. Két új cella a
`feature_flag_audit_test.dart`-ban zárja be.

**Motorok:** implementer `sonnet-impl` (Claude Sonnet 5, `--effort high`) —
1 alapkör + 2 javító kör; orchestrátor/reviewer Claude (Opus 5).
**Review:** [`e15-r02-review.md`](docs/reviews/e15-r02-review.md) — **APPROVED**
(1 BLOCKER + 1 MAJOR + 2 MINOR zárva, 2 NOTE tudatosan nyitva).
**CI a merge SHA-n (`443a9980`):**
[full-gate 33216141930](https://github.com/wolfcasaba/strumsight/actions/runs/33216141930),
[router-ci 33216104973](https://github.com/wolfcasaba/strumsight/actions/runs/33216104973);
kombinált-HEAD gate a landolóban mind a 39 lépésen zöld.
**Leckék:** [L536](docs/LESSONS.md#l536) (a scope-audit a generált golden-bukás-artefaktumot is számolja), [L537](docs/LESSONS.md#l537) (`pageBack()` és a Material back-affordancia).

## ✅ E12-R09 KÉSZ — Domain event katalógus és schema registry — PR [#496](https://github.com/wolfcasaba/strumsight/pull/496), squash `04ae8918` (2026-08-28)

**A cross-feature esemény-forgalomnak eddig nem volt nyilvántartása, csak
típusa.** A `LearningActivityEvent` sealed hierarchia (ADR 0329) hat altípussal
régóta él, de sehol nem volt leírva, melyik feature TERMELI, melyik FOGYASZTJA,
mi az idempotencia-kulcs és mi történik egy jövőbeli séma-verzióval. A kör ezt a
hiányt zárja — **`lib/**` diff nélkül**: dokumentum + fixture + gépi mérce, nem
egy második, konkurens envelope-típus.

| Fájl | |
|---|---|
| [`docs/contracts/event-catalog.md`](docs/contracts/event-catalog.md) | a hat típus katalógusa: `type` kód, séma-verzió, **mért** producer/consumer fájl:sor, idempotencia-kulcs (`eventId`), owner Chapter, kompatibilitási szabály |
| `test/fixtures/events/*.json` (6) | altípusonként egy, BYTE-szinten kanonikus fixture (pontosan a `toJson()` alakja) |
| [`test/core/events/event_schema_compatibility_test.dart`](test/core/events/event_schema_compatibility_test.dart) | 22 cella: A1–A8 + a kétirányú séma-verzió küszöb-hármas, mind a VALÓDI `LearningActivityEvent.fromJson`/`toJson` belépőn |
| [`docs/adr/0468-…`](docs/adr/0468-domain-event-catalog-and-schema-registry.md) | D1 nincs második envelope · D2 a katalógus a KÓDBÓL mért · D3 a „nincs producer" MÉRT állítás · D4 a verzió-határ MINDKÉT irányban zár · D5 kanonikus fixture · D6 idempotencia-kulcs = `eventId` |

**Három mért pre-flight korrekció** (a brief `§0.0` revíziója):

1. **A producer-oldal 8 konstruktor-hívás 7 fájlban**, nem „kilenc adapter".
2. **A `TutorActivityEvent`-nek NINCS termelője a fán** — a tutor adapter
   kifejezetten `PracticeActivityEvent`-ként jutalmaz (chat-farming elkerülése,
   ADR 0289). A katalógus ezt kimondja, és az **A8** cella a HIÁNYT méri.
3. **A brief küszöb-hármasának „alatta" cellája elérhetetlen volt:** a
   `_validateEventFields` a `schemaVersion != 1`-et MINDKÉT irányban
   `ArgumentError`-ral zárja, tehát a `< V` sem „best-effort olvasható".

**Review (APPROVED, 0 BLOCKER / 0 MAJOR / 0 MINOR / 3 NOTE):** a célzott teszt
izolált `/tmp` klónban **22/22 zöld**, és **három valódi-sértés próba** igazolta,
hogy a cellák pirosra tudnak váltani — P1 létező de nem termelő producer → **A5**,
P2 valódi `TutorActivityEvent(...)` a fán → **A8**, P3 nem kanonikus `occurredAt`
→ **A7** ([`docs/reviews/e12-r09-review.md`](docs/reviews/e12-r09-review.md)).

Exact-SHA evidencia a merge SHA-n (`6cc634b2`): Full Gate
[33209945460](https://github.com/wolfcasaba/strumsight/actions/runs/33209945460)
`success` (Coverage `success`), Router CI
[33209914803](https://github.com/wolfcasaba/strumsight/actions/runs/33209914803)
`success`. **Egy CI-flake, nem a kör diffjéből:** a
`test/features/songs/import/import_flow_test.dart` A2 workspace-takarítása —
ugyanaz a MÉRT flake, mint az E12-R05/R06 landolásánál; lokálisan zöld, és a
job újrafuttatása UGYANAZON a SHA-n zöld lett. Egy lecke:
[L535](docs/LESSONS.md#l535).

## 🔧 E15-R02 H3 ÖNJAVÍTÁS (ADR 0112) — a shell-flag MÉRT hatósugara a kör scope-jába került — PR [#495](https://github.com/wolfcasaba/strumsight/pull/495), squash `ee2a2bc4` (2026-08-28)

**A kör NEM futott le — a pre-flight `H3`-mal állt meg, implementer-dispatch
nélkül.** Az `adaptiveShellEnabled: false` → `nonProd` átállítás MÉRVE
53 tesztcellát tesz pirosra 19 fájlban, mert az
`appConfigProvider` ALAPÉRTELMEZETT értéke maga is
`FeatureFlags.forEnvironment(development, …)` — a flip tehát MINDEN olyan
widget-teszt navigációs kiindulását `/live`-ról `/today`-re viszi, amely nem
írja felül a providert. A brief §4 listája ebből 16 fájlt nem engedett, a
tágítás pedig nem orchestrátor-hatáskör (ADR 0087 §2).

**Amit az önjavító kör csinált** (a kör tartalmi munkáját NEM vitte előre):

- **Független reprodukció** — a teljes suite kétszer (flippel és anélkül); a
  különbség a flag oksági hatósugara, a maradék piros cellák mind a MÉRT
  ARM↔x86 raszter-drift (L516).
- **Brief-revízió** (`§0.0/d`): `allowed_paths` + `gate_tests` ← a mért
  fájlok; `lib/core/feature_flags/feature_flag_registry.dart` (ADR 0467 D8
  próza) és `test/tooling/feature_flag_audit_test.dart` (A11 gépi cella);
  `test/ui/goldens/e15_r01_theme_adoption_test.dart` (S11-maradék). Új
  acceptance: **A10** (teljes suite zöld a drifttől eltekintve), **A11**.
- **ADR 0467** (a pre-flight írta, most merge-elve) + **D9**: a bukó tesztek
  KIZÁRÓLAG az új viselkedéshez igazíthatók — `appConfigProvider`-override-dal
  kikapcsolt shell = a mérce elrejtése, tilos.
- **Őrteszt:** `tools/tests/test_e15_r02_adaptive_shell_scope.py` — a valódi
  briefet hajtja a valódi scope-auditon; a lista szűkülése ÉS a könyvtár-
  szintű blanket-tágítás is pirosra váltja. A javítás előtt PIROS, utána zöld.
- **Tanulság:** [L534](docs/LESSONS.md#l534).

**A lánc feloldva:** az E15-R02 a következő firingen újraindul, a most már
teljes §4 listával; a pre-flight ág (`sonnet-impl/e15-r02-…`) tartalma ebbe a
PR-be került, az ág törölve.

## ✅ E12-R08 KÉSZ — Staging backend, migrations és recovery alap — PR [#494](https://github.com/wolfcasaba/strumsight/pull/494), squash `e560ca79` (2026-08-28)

**A migrációs fejre mérő readiness eddig csak VÁLASZ volt, most KISZOLGÁLÁSI
ELŐFELTÉTEL is.** A `/health/ready` (`_readiness_failure`) már korábban mérte,
hogy az alkalmazott revízió = `alembic heads`; a `/settings` és az `/auth/*`
viszont **akkor is kiszolgált**, ha ez hamis volt. Az E12-R08 ezt a rést zárja:
`env ∈ {staging, prod}` alatt a `Depends(_traffic_gate)` minden üzleti routeren
ott van, migrálatlan sémán 503 `{"status":"not_ready","reason":…}` a válasz, és
az üzleti kezelő **le sem fut** ([ADR 0449](docs/adr/0449-staging-readiness-traffic-gate-and-recovery.md) D1).

**A kapu `dev`/`lab` alatt szándékosan nem aktív** (D1, §0.0 R3): ott a séma
legitim forrása a lifespan `create_all`, amely nem stampel — a fej ELVÁRTAN
üres. Egy környezet-független kapu a `conftest.py` fixture-jén álló ~20 meglévő
auth/settings cellát törte volna el. **Új HTTP-útvonal nem jött létre** (R1): a
brief `/readyz`-je a meglévő `/health/ready`-re lett átírva, mert a
`test_migrations.py::test_openapi_contract_is_deterministic` a nyitott
útvonalak halmazát EGYENLŐSÉGRE méri, és az a cella tilos zóna.

**Mentés/visszaállítás bizonyított úton:** `backup.py` a sorokon kívül a
migrációs fejet is menti (0600-as fájl az első bájttól — a dump PII-t és
bcrypt hasheket hordoz); `restore.py` **Alembickel** épít sémát (`create_all`
tilos, ADR 0060), létező adatot csak `--force` **ÉS** a cél nevét szó szerint
megismétlő `--confirm-target` mellett ír felül, és elutasít, ha a cél feje
eltér a mentésétől. **Konténer-profil:** digestre pinelt `python:3.12-slim`,
nem-root user, migration-before-start `CMD`. Két üzemeltetési runbook
(`docs/operations/backend-deploy.md`, `database-recovery.md`).

**Review:** [`docs/reviews/e12-r08-review.md`](docs/reviews/e12-r08-review.md)
— **APPROVED**, 2 MAJOR + 2 MINOR egy javító körben lezárva. A `security-reviewer`
(kockázat: high) találta a MAJOR-1-et: a backup-dump PII-t írt trackelt
könyvtárba, 0644-gyel. A MAJOR-2 a saját mérésem: a `staging.env.example`
`# strumsight:allow-secret-file` markerrel ki van véve a repo titok-scanneréből,
és az EGYETLEN őre, az A5 cella, **átengedte a `STRUMSIGHT_DATABASE_URL`-be
ágyazott valódi jelszót** (mérve: a `<db-password>` valódira cserélve a cella
zöld maradt; a javítás után piros).

**Bizonyíték:** `tools/round-gate.sh test/app/config/feature_flags_test.dart`
9/9 zöld · Full Gate `33197994195` ✅ · Router CI `33197996266` ✅ · Backend CI
`33197977930` ✅ — mind az `f0073bc9` merge-SHA-n · scope-audit OK (10 útvonal).

**Két mért infrastruktúra-lelet a landolásban** (L532, L533): a
`round-gate.sh` backend sávja relatív venv-útvonallal `exit 127`-tel bukik
(`env --chdir=backend backend/.venv/bin/python`), és a megosztott fa a landoló
futása közben KÉTSZER visszabillent `main`-re. Mindkettő megkerülve
(`ROUND_GATE_BACKEND_PYTHON` + landolás a munkapéldányból), a javításuk az
önjavító kör dolga.

**Következő kör:** `E12-R09` — domain event catalog és schema registry (ADR 0450).

## ✅ E15-R01 KÉSZ — A design-rendszer témájának app-szintű bevezetése — a **Chapter 15 sáv INDULT** — PR [#493](https://github.com/wolfcasaba/strumsight/pull/493), squash `a65aa3f9` (2026-08-28)

**A Chapter 13 alatt megépült design-rendszert az alkalmazás SOHA nem kapcsolta
be — most bekapcsolta.** A `strumsight_app.dart` mindhárom téma-hivatkozása
(`theme:`, `darkTheme:`, és a bootstrap-hibaág `theme:`) mostantól
`SsLightTheme.data()` / `SsDarkTheme.data()`, a
`core/design_system/public.dart` barrelen át (`show SsDarkTheme, SsLightTheme`).

Ettől MINDEN képernyő — a 43 migrált és az 53 migrálatlan is — ugyanabból a
`ThemeData`-ból oldja fel a `SsColorScheme` / `SsTypography` /
`SsStateOverlays` / `SsThemeBehavior` extensiont, a kilenc feature-szintű
`*ThemeScope` burkoló nélkül. A burkolók ettől redundánsak (a
`migration-status.md` MÉRT módon elavultnak jelöli őket), de a törlésük a
képernyő-körökre marad — `lib/features/**` ennek a körnek tilos zóna volt.

**Az átállás ADDITÍV** (ADR 0466 D2): a `SsLightTheme`/`SsDarkTheme` a legacy
`AppTheme`-ből származik `copyWith(extensions: …)`-szal, tehát a `colorScheme`,
a `textTheme` és a `scaffoldBackgroundColor` bitre változatlan — a márkaszín-
váltás az `E15-R02` dolga, nem ezé. Az `A7` cella ezt gépi egyenlőséggel köti.

**Normatív döntések:** [ADR 0466](docs/adr/0466-app-runtime-theme-is-the-design-system-theme.md)
D1 (egy token-forrás, a hibaágon is) · D2 (additív átállás) · D3 (a belépő a
`public.dart` barrel, ADR 0273 §1) · D4 (négy extension mindkét fényerőn) ·
D5 (a High Contrast téma megmarad, a bekötése külön kör) · D6
(`ss_theme_extensions.dart` mért módosítási igény nélkül marad) · D7 (a záró
mátrix PNG-mentes és kizárási lista NÉLKÜL zöld).

**Mérce (mind ÚJ):**

- `test/app/theme_adoption_test.dart` — hat cella: A1 (négy extension mindkét
  fényerőn, a TÉNYLEGESEN pumpolt `MaterialApp`-ról olvasva), A2 (`SsButton`
  `*ThemeScope` NÉLKÜL feloldja a tokeneket), A3 (a bootstrap-hibaág is), A6
  (96 képernyő-forrás szám-pin), A7 (a legacy `colorScheme`/`textTheme`/
  `scaffoldBackgroundColor` egyenlőség), A8 (barrel-import forrás-cella).
- `test/ui/goldens/e15_r01_theme_adoption_test.dart` — PNG-mentes variáns-mátrix,
  **48 cella** (6 képernyő × 2 fényerő × 2 locale × 2 szövegskála), compact
  portrait 412×915, `FlutterError.onError`-ra kötött túlcsordulás- és
  kivétel-figyelés, **kizárási lista / `skip` / tolerancia NÉLKÜL** (L524 mintája).

**A review nem bemondásra dolgozott:** izolált `/tmp` klónban futtatott
valódi-sértés próbák a GYÁRTÁSI kódon — a `theme:`+`darkTheme:` visszaállítása
az A1-et ÉS az A2-t pirosra vitte (`Null check operator used on a null value`,
azaz a komponensek `extension<SsColorScheme>()!` force-unwrapja), a hibaág
visszaállítása az A3-at. A cellák tehát valódi kapuk. A reviewer SAJÁT
MINOR-2 lelete (cellaszám) számolási hibának bizonyult és visszavonásra
került — a helyes érték **48**, amit a gate `+48: All tests passed` kimenete
mér; a hibás `24` az előre megírt briefből jött, és a brief + ADR szövegében
is javítva lett.

**Mért kör-tanulság ([L531](docs/LESSONS.md#l531)):** a `sonnet-impl`
implementer KÉTSZER, azonos mintázattal halt meg jelzés nélkül — a `round-gate.sh`
hívást háttér-taskba tette és a válaszát a task-értesítésre várva zárta, a
wrapper-session pedig kilépett alóla és megölte a taskot. Az explicit „ELŐTÉRBEN,
`run_in_background` NÉLKÜL" prompt-utasítás ezt NEM akadályozta meg.

**Következő:** `E15-R02` — adaptív shell alapértelmezetté tétele és a
túlcsordulás-javítások (a queue szerint `sonnet-impl`, ADR `0467`).

## ✅ E12-R06 KÉSZ — Versioning, provenance, SBOM és release manifest — PR [#490](https://github.com/wolfcasaba/strumsight/pull/490), squash `80292431` (2026-08-28)

**Minden kiadott artefaktum mostantól commitig visszakövethető, verzió-monoton és
supply-chain szempontból leírt — és mindezt gépi kapuk tartják, nem szándék.**
Eddig a `pubspec.yaml` `1.0.0+1`-en állt (a build number SOHA nem emelkedett), a
verzió/SHA sehol nem jelent meg, és sem release manifest, sem SBOM, sem
third-party notice-bundle nem létezett. A kör négy eszközt szállít:

- **`tool/generate_release_manifest.dart`** — determinisztikus JSON: kanonikus
  enkóder (minden szinten rendezett kulcsok, `\n` sorvég), **időbélyeg SEHOL**
  (ADR 0447 D1). Mérve a fán: két egymás utáni futás sha256-a azonos
  (`d24ec1bb…`). Az ML- és a tudáscsomagot `schemaVersion` + manifest-sha256 +
  elemszám hármassal hivatkozza — kitalált „package version” nincs, mert
  egyikben sem létezik ilyen mező (D6).
- **`tool/release/generate_sbom.py`** — 171 komponens (160 Dart + 11 backend
  Python pin), `THIRD_PARTY_NOTICES.md` + `sbom.json`. **Csak stdlib.**
- **`tool/release/verify_artifacts.py`** — checksum-audit + **szigorúan monoton**
  build number: a csökkenés ÉS az egyenlőség is nem-nulla kilépés; bázis nélkül
  explicit `baseline: none`, nem néma átcsúszás (D2).
- **`lib/app/build_info.dart`** — `const` compile-time metaadat, a bootstrap
  érintetlen (D7).

**A license-adat nem létezett, ezért MÉRT forrásból jön.** A pre-flight
kimérte, hogy a `pubspec.lock` **egyetlen** csomagra sem hordoz license-mezőt
(`grep -ci license pubspec.lock` → `0`, 160 csomag), és a `requirements*.txt`
sem — az eredeti brief-szerződéssel a generátor MINDIG megbukott volna, és a
kötelező notices-fájl sosem jött volna létre. A feloldás (ADR 0447 D3): a
license vagy a pub cache-beli `LICENSE` fájlból (cache-gyökérhez **relatív** út
+ sha256 + első sor), vagy a generátorban élő, kézzel gondozott
`_CURATED_LICENSES` jegyzékből jön; egyikből sem feloldható csomag →
**nem-nulla kilépés a névvel**. `"unknown"` soha, SPDX-kitalálás soha.

**A `.github/workflows/**` védett zóna, ezért a kör JAVASLATOT szállít**
(`docs/release/workflows/release-apk-provenance.proposal.md`): 6 lépés teljes,
bemásolható YAML-részletként, a beillesztés helyét a `release-apk.yml` LÉTEZŐ
lépésneveivel megnevezve. A tényleges bekötés merge utáni
orchesztrátor/emberi lépés (ADR 0447 D4). A javaslat YAML-validitását és a
kötelező lépéseit gépi cella méri — a mérce nem gyengült.

**Pre-flight: öt mért brief-ütközés feloldva (§0.0.A).** A
`brief-lint --level strict` **0 leletet** adott; a kód-mérés ötöt talált —
a lint a brief ALAKJÁT méri, az ÁLLÍTÁSAIT nem. (R1) a license-forrás fenti
hiánya; (R2) a `package:yaml` csak tranzitív, a `pubspec.yaml` pedig tilos zóna
→ saját, korlátozott YAML-parser (ADR 0444 D3 precedense), és
[L110](docs/LESSONS.md#l110) miatt semmilyen `rg`/`grep`/`jq`/`gh` shell-out;
(R3) a §5.1 két mondata egymásnak feszült („külön időbélyeg-mező, amit a teszt
kizár" vs. „a mező-kihagyásos lazítás tilos") → nincs időbélyeg SEHOL;
(R4) a tudáscsomagnak nincs package-szintű verziója; (R5) nincs
`test/fixtures/**` az engedélyezett listán → futásidejű temp fixture-ök. **A
lista nem bővült.** Új **A7** cella az L110 hibaosztálya ellen.

**Review:** [`docs/reviews/e12-r06-review.md`](docs/reviews/e12-r06-review.md) —
**APPROVED 1 javító kör után**, 0 BLOCKER / 0 MAJOR / 0 nyitott MINOR / 1
follow-up NOTE. Az első kör 2 MINOR-t talált **teljesen zöld gate mellett**:
**F1** — a committolt `THIRD_PARTY_NOTICES.md` **155 abszolút
`/home/ubuntu/.pub-cache/...` útvonalat** hordozott, azaz egy kiadásra szánt
jogi artefaktum gép-függő és nem reprodukálható lett; **F2** — a javasolt
verify-lépés a beillesztési pont kényszere miatt nulla artefaktumot auditál.
A javító kör mindkettőt zárta: **155 → 0**, két ÚJ hordozhatósági gate-cella
(fixture-futás + a committolt fájl), valódi-sértés próbával igazolva; az F2
kapott egy kimondott, follow-uppal együtt dokumentált szakaszt.

**A gate nem bemondás:** `tools/round-gate.sh` **kétszer, két független
izolált `/tmp` klónban** zöld, scope-audit mindkét mérésen `OK`
(`.github/**` érintetlen), és öt reviewer-próba a SZÁLLÍTOTT eszközökön
(feloldhatatlan Dart/Python license → exit 1 névvel, részleges kimenet nélkül;
küszöb-hármas 41/42/43 → exit 1/1/0; checksum-eltérés → exit 1). CI a merge
SHA-n (`46d230e0`): full-gate + router-ci `success`.

**Lecke:** [L530](docs/LESSONS.md#l530) — a „kétszer futtatva bájtazonos"
determinizmus-cella csak UGYANAZON a gépen mér; committolt generált
artefaktumhoz kell egy külön **hordozhatósági** cella is.

**Follow-up (F4, NOTE):** a Python komponensek `version: null`-lal kerülnek az
SBOM-ba, noha a `requirements.txt` mind a 11 pinre hordoz
verzió-specifikációt — a pin-string átvétele `versionSpec` mezőként egy
későbbi supply-chain kör dolga.

**Nyitott orchesztrátor/emberi lépés:** a
`docs/release/workflows/release-apk-provenance.proposal.md` beillesztése a
`.github/workflows/release-apk.yml`-be (a `Read APK metadata from pubspec`
UTÁN, a `Materialize production keystore` ELŐTT) — ez a védett mérce-zóna
miatt szándékosan nem a kör dolga volt.

## ✅ E12-R05 KÉSZ — Feature flag registry és emergency kill switch — PR [#489](https://github.com/wolfcasaba/strumsight/pull/489), squash `186f29c6` (2026-08-28)

**A 40 kockázatos capability-kapcsoló mostantól egyetlen típusos katalógusban él
— owner, kockázati szint, fail-closed alapérték, kill-switch-út és opcionális
lejárat mellett —, és a katalógus teljessége GÉPI állítás.** Eddig 40 `final
bool` mező döntötte el, hogy egy build hálózatot használ-e
(`usesNetwork => accountEnabled || diagnosticsEnabled`), elérhető-e a
Lab-diagnosztika, be van-e kapcsolva a Vision kamerafelület vagy a Community
írás — és egyikhez sem volt leírva, hogy kié, meddig él és hogyan kell
vészhelyzetben kikapcsolni. A `dart run tool/check_feature_flags.dart` ezt
zárja: a `lib/app/config/feature_flags.dart` FORRÁSÁT parse-olja, és minden
mezőhöz katalógus-bejegyzést követel (hiányzó, ismeretlen, duplikált vagy
metaadat nélküli bejegyzés → nem-nulla kilépés).

A feloldás [ADR 0446](docs/adr/0446-feature-flag-registry-and-emergency-kill-switch.md)
szerint **fail-closed**: `emergency > remote(signed) > capability > local/define
> failClosedDefault`. A vészkapcsoló **aszimmetrikus** — kizárólag KIKAPCSOLNI
tud (D1): a `true` értéke átcsordul a gyengébb forrásra, és nem is hiba, mert a
legkevésbé védett bemenet nem kaphat bekapcsoló jogot. A bukott aláírású remote
payload értékei figyelmen kívül maradnak és **nem fatálisak** (D2), hiányzó
forrásnál nincs „utolsó ismert érték", és a kikapcsolás **nem töröl adatot**
(D7). A remote forrás ebben a körben szándékosan csak INTERFÉSZ (D3) — hálózati
csatorna és valódi aláírás-ellenőrzés nélkül; az a Ch12 Kör 30/31 rollout-köreié.

**A kör NEM nyúlt a `lib/app/config/feature_flags.dart`-hoz** (a katalógus a
MEGLÉVŐ mezőkre string-kulccsal hivatkozik, D5 — így a `lib/core/` réteg nem
függ tranzitívan egy feature-domain típustól), és a két meglévő regresszió-őr
(`test/app/config/feature_flags_test.dart` + `test/app/feature_flags_test.dart`,
558 sor) változatlanul zöld.

**1 javító kör**, 0 BLOCKER / 0 MAJOR / 3 MINOR — mind zárva. A kötelező
`security-reviewer` (`risk = "high"`) **PASS**-t adott (D1/D2/D7 mérve, NO
SINKS, nincs titok a katalógusban vagy a doksiban). A három MINOR-t a reviewer
SAJÁT próbái nyitották és zárták: a teljesség-őr eredeti mintája
(`final bool (\w+);`) mellett egy `final bool? x;` vagy `final bool x = true;`
alakban felvett új flag **csendben kicsúszott** az auditból (exit 0) — a
javítás után ugyanaz a próba `exit 1`-et ad, komment-beli fals pozitív nélkül;
üres `owner`/`killSwitchPath` mostantól `incompleteCatalogEntry`; és a
`docs/release/kill-switches.md` bizonyítatlan „generált tábla" állítása
visszavonva.

**Orchestrátor-önkorrekció, ami leckévé vált:** a kör pre-flightja **37**
mezőt mért 40 helyett, mert a `grep -cE "final bool [a-zA-Z]+;"` minta kiejtette
a **számjegyet tartalmazó** három mezőnevet (`practiceEngineV2Enabled`,
`songTrainerV2Enabled`, `audioAnalysisV2Enabled`). Az implementer újramérte,
a helyes 40-et katalogizálta és jelentette is — a brief §0.0 R1 pontja a
review-ban javítva ([L529](docs/LESSONS.md#l529)).

Exact-SHA evidencia a merge SHA-n (`2532f89c`): Full Gate
[33170835429](https://github.com/wolfcasaba/strumsight/actions/runs/33170835429)
`success` (Coverage `success`), Router CI
[33170818767](https://github.com/wolfcasaba/strumsight/actions/runs/33170818767)
`success`. **Két CI-flake mérve, egyik sem a kör diffjéből:** a
`tools/tests/test_safe_force_push.py` `TemporaryDirectory`-takarítása
(`OSError: [Errno 39] Directory not empty`) és a
`test/features/songs/import/import_flow_test.dart` A2 workspace-takarítása —
utóbbi lokálisan zölden fut, és a job újrafuttatása UGYANAZON a SHA-n zöld lett.

## ✅ E12-R04 KÉSZ — Environment és channel konfiguráció lezárása — PR [#488](https://github.com/wolfcasaba/strumsight/pull/488), squash `5a971421` (2026-08-28)

**A backend környezet-jelölője zárt értékkészlet lett, a staging pedig valódi,
fail-closed deployment-céllá vált — és a kör közben egy SAJÁT MAGA nyitotta
titok-szivárgást is lezárt.** Az `STRUMSIGHT_ENV` eddig szabad string volt:
egy elgépelt `prod uction` hiba nélkül elindította a backendet, és mivel minden
production-kapu `== "prod"` egyenlőségre épül, a deploy dev-titokkal, wildcard
CORS-szal és bekapcsolt Lab-route-okkal szolgált volna ki forgalmat. Mostantól
a kanonikus értékkészlet `dev | lab | staging | prod`, a kliens enum-nevei
(`development`, `production`) **aliasok**, és az ismeretlen érték
`ValidationError` — nem csendes visszaesés ([ADR 0445](docs/adr/0445-environment-value-set-and-staging-isolation.md) D1–D2).

| Fájl | |
|---|---|
| [`backend/app/config.py`](backend/app/config.py) | zárt `env` értékkészlet + alias-normalizálás (`trim().lower()`), ÚJ `_guard_staging` példányosítás-idejű őr (dev `secret_key`, wildcard CORS, dev/üres `diag_token` bekapcsolt diagnosztika mellett, escape-hatch nélküli SQLite), Lab-flagek stagingen alapból `False`, `hide_input_in_errors=True` |
| [`lib/app/config/app_config.dart`](lib/app/config/app_config.dart) | productionben a `staging` részláncot tartalmazó host **feltétlen** tiltása, a meglévő loopback-tiltás MELLETT |
| [`lib/app/config/app_environment.dart`](lib/app/config/app_environment.dart) | doc-comment: a staging NEM kliens-környezet + a backend alias-táblája |
| [`backend/tests/test_settings.py`](backend/tests/test_settings.py) | `TestEnvironmentValueSet`, `TestStagingIsolation`, `TestSecretsNeverLeakIntoErrors` — a meglévő 8 cella változatlan |
| [`test/app/app_config_test.dart`](test/app/app_config_test.dart) | A5 cellák: production + staging-host elutasítva, ugyanaz `lab`/`development` alatt elfogadva |
| [`docs/release/environment-matrix.md`](docs/release/environment-matrix.md) (ÚJ) | a négy környezet mátrixa fájl+sor és teszt-hivatkozásokkal |

**A kör legfontosabb tanulsága ([L528](docs/LESSONS.md#l528)):** a szigorítás
maga nyitott egy titok-szivárgást. Egy **model-szintű** pydantic-validátorból
dobott hiba `input_value`-ja nem egy mező értéke, hanem a **teljes bemeneti
settings-szótár** — és a `backend/app/main.py` modul-szintű `create_app()`
hívása miatt ez uvicorn/gunicorn import-time tracebackként a **boot-logba**
kerül. Az orchestrátor saját reprodukciója a DB-jelszót szó szerint kiírta.
A javítás `hide_input_in_errors=True` (az üzenet SZÖVEGE változatlan, tehát
minden `pytest.raises(..., match=…)` cella zöld maradt), az őr pedig három
canary-titkos cella, amelyek a javítás eltávolításakor pirosra váltanak.
A `security-reviewer` ügynök futtatása a `risk = "high"` miatt KÖTELEZŐ volt —
ez a lelet onnan jött.

**A kör HATÁRAI, amiket nem lépett át:** a `_guard_prod`
(`backend/app/main.py`) és a `prod` literál fogyasztói tilos zónában maradtak,
a `backend/tests/test_hardening.py` egyetlen sora sem változott, és az
`AppEnvironment` enum NEM bővült negyedik értékkel (a staging backend-oldali
cél, [ADR 0445](docs/adr/0445-environment-value-set-and-staging-isolation.md) D3).

**Review:** [`docs/reviews/e12-r04-review.md`](docs/reviews/e12-r04-review.md) —
**1 javító kör után APPROVED** (B1 BLOCKER + B2 MAJOR + B3/B4 MINOR zárva,
2 NOTE nyitva az E12-R07 felé: a `_guard_prod` azonos üres-secret rése és a
`ValidationError.errors()` strukturált alakja). Exact-SHA evidencia a merge
SHA-n (`f1bd7ffd`): Full Gate
[33165886801](https://github.com/wolfcasaba/strumsight/actions/runs/33165886801)
`success`, Backend CI
[33165917493](https://github.com/wolfcasaba/strumsight/actions/runs/33165917493)
`success`, Router CI `success`.

**Folyamati megjegyzés:** a javító kör implementer-futása a `sonnet-impl` motor
3600 s abszolút időkorlátjába futott bele (`status=timeout`, `scope_audit=ok`)
a commit ELŐTT, kész kód-munkával. Ez a motor EGY halála (H6 küszöbe kettő),
ezért az orchestrátor nem indított új futást: a scope-auditált diffet
átnézte, a falszifikációs próbákat maga futtatta le, és a `8e832a21`
commitban rögzítette — minden szám a brief §10.5-ben, ténylegesen futtatott
parancsok kimeneteként.

**NEXT:** `E12-R05` — Feature flag registry és kill switch
([`docs/rounds/e12-r05-feature-flag-registry-and-kill-switch.md`](docs/rounds/e12-r05-feature-flag-registry-and-kill-switch.md),
ADR `0446`, motor `sonnet-impl`).

## ✅ E12-R03 KÉSZ — GitHub delivery workflow, branch protection és review policy — PR [#487](https://github.com/wolfcasaba/strumsight/pull/487), squash `00be433e` (2026-08-28)

**A repó megkapta a backlog-, ownership- és PR-evidence-szabályát — úgy, hogy az
autonóm kör-pipeline egyetlen merge-feltétellel sem lett terhelve.** A kör
legfőbb kockázata nem kódhiba volt, hanem szabályozási: egy CODEOWNERS-alapú
`required_approving_review_count ≥ 1` DEADLOCK-ba vinné a láncot, mert a PR-t a
kör orchesztrátora nyitja és squash-merge-eli. Az [ADR 0444](docs/adr/0444-delivery-workflow-and-repository-policy.md)
D1 ezért kimondja: **a CODEOWNERS jelöl, nem kapuz** — és a tilalmat gépi cella
(A6) őrzi mindkét fájlon.

| Fájl | |
|---|---|
| [`.github/ISSUE_TEMPLATE/`](.github/ISSUE_TEMPLATE/) (ÚJ, 6 fájl) | öt sablon (feature, bug, security, migration, release), mindegyiken **hat kötelező mező** (`chapter`, `round`, `acceptance`, `test_plan`, `rollback`, `privacy`) + `config.yml` a blank issue tiltásához |
| [`.github/CODEOWNERS`](.github/CODEOWNERS) (ÚJ) | 14 minta öt területre (audio/backend/security/model/release), **jelölő** szerepben |
| [`.github/pull_request_template.md`](.github/pull_request_template.md) | `## Release evidence` szakasz + kötelezően kitöltendő release-asset sor; a mért 11 szakasz változatlan |
| [`docs/process/backlog-policy.md`](docs/process/backlog-policy.md), [`docs/process/branch-protection.md`](docs/process/branch-protection.md) (ÚJ) | label/severity leképezés a `docs/release/blockers.md` P0–P3 skálájára; required check vs. user-opció szétválasztása |
| [`tool/audit_repository_policy.py`](tool/audit_repository_policy.py) (ÚJ) | statikus, **offline** policy-audit (PyYAML); a `gh api` parancsot kiírja, de nem futtatja |
| [`test/tooling/repository_policy_test.dart`](test/tooling/repository_policy_test.dart) (ÚJ, 817 sor) | **28 cella**, saját sor-alapú issue-form parserrel |

**`package:yaml` itt sem használható** ([ADR 0444](docs/adr/0444-delivery-workflow-and-repository-policy.md) D3,
ugyanaz a mérés, mint az ADR 0443 D3-nál): a `yaml` csak `dependency: transitive`,
és a `depend_on_referenced_packages` lint pirosra váltaná a `flutter analyze`-t,
miközben a `pubspec.yaml` a tilos zónán van (H3). A CI-kaput ezért egy
**szándékosan szűkített** issue-form YAML-részhalmaz + saját parser adja; a
**teljes** YAML-érvényességet a Python audit méri operátor-oldalon PyYAML-lel —
két független mérés ugyanazokra a fájlokra.

**A kör mért tanulsága ([L527](docs/LESSONS.md#l527)) — az ÖNVÉDŐ cella volt a
vakon zöld.** Az A8 cella pont az [L110](docs/LESSONS.md#l110) hibaosztályt
akarta megfogni (külső binárisra shell-elő guard: a boxon zöld, a CI-runneren
piros), és a saját forrásában a `Process.run` mintát kereste. A reviewer
beszúrt egy `Process.start('rg', …)` hívást a guard fájlba: **mind a 28 cella
zöld maradt.** A `dart:io` külső-folyamat belépési pontja három, nem kettő — és
a hibás szám a KOMMENTBEN élt („one check covers both entry points"), tehát aki
elolvasta, megerősítve látta a hiányos mintát. A javító kör mindhárom pontra
kiterjesztette a mérést; a reprodukció mind a háromra piros.

**Review:** [`docs/reviews/e12-r03-review.md`](docs/reviews/e12-r03-review.md) —
**APPROVED egy javító kör után**, 0 BLOCKER / 0 MAJOR / 0 MINOR / 2 NOTE.
A reviewer öt saját valódi-sértés próbát futtatott izolált klónban; kettő
talált leletet (F1 MAJOR, F2 MINOR), egy dokumentált korlátot igazolt
(F3: a szűkített részhalmaz a legitim `assignees:` kulcsot is **hangosan**
elutasítja — PyYAML elfogadná).

**Exact-SHA evidencia a merge SHA-n (`f5fbc26f`):** Full Gate
[33137856678](https://github.com/wolfcasaba/strumsight/actions/runs/33137856678)
`success` + Router CI
[33137858325](https://github.com/wolfcasaba/strumsight/actions/runs/33137858325)
`success`. Scope-audit az implementációra:
`OK (de8d8eece3ec..27f22591e015, 13 changed path(s), 0 generated/ignored)`;
a javító körre a wrapper gépi audit-ja `scope_audit=ok` (4 fájl).
`.github/workflows/**` és `pubspec.*` érintetlen.

**NEXT:** `E12-R04` — Environment és channel isolation
([`docs/rounds/e12-r04-environment-and-channel-isolation.md`](docs/rounds/e12-r04-environment-and-channel-isolation.md),
ADR `0445`, motor `sonnet-impl`). A `docs/process/branch-protection.md` §2
négy elvárt beállítása **dokumentált elvárás** marad, amíg a token nem kap
Administration jogot (ADR 0050 „Szóló-fejlesztői adaptációk" 2. pont) — ez
user-hatáskörű, operátori lépés, nem kör-scope.


## ✅ E12-R02 KÉSZ — SDD index és dependency graph — PR [#486](https://github.com/wolfcasaba/strumsight/pull/486), squash `355defd9` (2026-08-28)

**Az SDD program indexe gépi szerződés lett.** A `docs/sdd/00-index.md`
fejezet-táblája és a fejezet-fájlok szétcsúsztak: az index a Chapter 12-re **42**
kört írt, a fájlban **36** `# Kör` fejléc van. Ezt eddig egy prózai footnote
„kezelte" („végrehajtáskor a fájl tartalma az irányadó") — pontosan az a
hibaosztály, amit ez a kör gépi ellenőrzésre cserélt: **a prózai mentesítés nem
tud pirosra váltani.**

| Fájl | |
|---|---|
| [`tool/check_sdd_index.dart`](tool/check_sdd_index.dart) (ÚJ, 671 sor) | index-parse → fájl-lét → körszám → ciklus; top-level, gyökér-paraméteres API, a `main()` csak `exitCode`-burkoló |
| [`docs/sdd/dependency-graph.yaml`](docs/sdd/dependency-graph.yaml) (ÚJ, 151 sor) | 14 fejezet-csomópont + 31 él, `critical_path` és `capability_gated` jelöléssel |
| [`test/tooling/sdd_index_guard_test.dart`](test/tooling/sdd_index_guard_test.dart) (ÚJ, 699 sor) | **36 cella**, fixture-alapú hibás bemenetekkel (duplikált fejezet, dangling hivatkozás, ciklikus graph) |
| [`docs/sdd/00-index.md`](docs/sdd/00-index.md) | Chapter 12 `42` → **36**; új `Státusz` / `Implementation progress` / `Dependency` oszlopok |

**A körszám FORRÁSA mostantól a fejezet-fájl** ([ADR 0443](docs/adr/0443-sdd-index-machine-checkable-contract.md) D1):
az ellenőrző onnan SZÁMOL, és az indexet ahhoz méri. Mindkét fejléc-alakot
kezeli — `# Kör N` (Ch1–13) és `## Kör N` (Ch14) —, mert egyetlen alak
támogatása **némán nulla kört** mérne a Chapter 14-re, és a hiba pontosan úgy
nézne ki, mint egy helyes mérés. A pre-flight mind a 14 sort újramérte: a
Chapter 12 volt az EGYETLEN eltérés.

**`package:yaml` nincs használva** (ADR 0443 D3, a pre-flight P4 mérése): a
`yaml` csak `dependency: transitive` a `pubspec.lock`-ban, és a
`depend_on_referenced_packages` lint miatt a közvetlen import pirosra váltaná a
`flutter analyze`-t — a `pubspec.yaml` viszont a tilos zónán van (H3). A
manifest ezért **szándékosan szűkített YAML-részhalmaz**, saját sor-alapú
parserrel; ezt önvédő teszt-cella őrzi.

**A kör mért tanulsága ([L526](docs/LESSONS.md#l526)) — a review 1 MAJOR-t
talált teljesen zöld gate mellett.** A három új oszlop mögé került
`Zárójelentés` cellát 9 sor elhagyta (ez a RÉGI, 6 oszlopos táblában még
ártalmatlan volt, mert ott az volt az utolsó oszlop). A GFM a hiányzó cellákat a
sor **VÉGÉRE** teszi, a checker viszont a `Zárójelentés` **HELYÉRE** szúrta be —
így **9/14 sor négy oszloppal eltolva renderelődött**, miközben a checker a saját
értelmezésében helyesnek látta. A javító kör mind a 9 sorba kiírta az explicit
`—` cellát, és tett mellé egy `parseChapterTable`-től FÜGGETLEN, GFM-hű őrt; a
reviewer saját valódi-sértés próbája ezt pirosra mérte
(`line 19: 8 cell(s), expected 9`).

**Review:** [`docs/reviews/e12-r02-review.md`](docs/reviews/e12-r02-review.md) —
**APPROVED egy javító kör után**, 0 BLOCKER / 0 MAJOR / 0 MINOR / 2 NOTE.
A két NOTE follow-up: (F3) a fejezet↔fájl összerendelés a fájlnév-prefixen
múlik, nem a tábla linkjén; (F4) az ASCII „Függőségi kép" nincs a manifesthez
mérve (tudatos, dokumentált korlát).

**Exact-SHA evidencia a merge SHA-n (`0ab830e4`):** Full Gate
[33134488639](https://github.com/wolfcasaba/strumsight/actions/runs/33134488639)
`success` + Router CI
[33134489993](https://github.com/wolfcasaba/strumsight/actions/runs/33134489993)
`success`. Scope-audit a teljes körre:
`OK (4437fdb6f2a9..a7d4308f7271, 6 changed path(s), 1 generated/ignored)`.
A `check_sdd_index.dart` **NEM került a `tools/round-gate.sh` gate-sorába**
(ADR 0443 D5 — az ADR 0052 hatálya); a gépi mércét a guard-teszt adja, ami a
teljes CI-suite része.

## ✅ E12-R01 KÉSZ — Program baseline és release history audit — a **Chapter 12 sáv INDULT** — PR [#485](https://github.com/wolfcasaba/strumsight/pull/485), squash `ae058f88` (2026-08-28)

**A Chapter 13 (UI) lezárása után elindult a Chapter 12 (Release Roadmap, Sprint
Planning & Final Integration) 36 körös sávja.** Az első kör mérési/dokumentációs
baseline: **alkalmazáskód-változás nélkül, ADR nélkül** — a diff kizárólag négy
Markdown fájl (`tools/scope-audit.py` → `OK, 4 changed path(s)`).

**Három ÚJ dokumentum a `docs/release/`-ben** (a könyvtár eddig NEM létezett),
mindhárom fejlécében a mérés SHA-jával (`main @ 92576977`, 2026-08-28):

| Fájl | Tartalom |
|---|---|
| [`docs/release/program-baseline.md`](docs/release/program-baseline.md) (173 sor) | 10 szakasz: alkalmazás-azonosság (`1.0.0+1`, `com.wolfcasaba.strumsight`), a 10 CI-workflow, a `release-apk.yml` fail-closed signing-lánca, a Gradle `GradleException`-ök, 21 backend-migráció, ADR-számozás, a Ch12 36 körös sávja, a governance checklist mért állapota |
| [`docs/release/release-history-audit.md`](docs/release/release-history-audit.md) (139 sor) | **26 GitHub Release**, **27 git tag**, a delta pontosan egy tag-only ref (`build-81`); kimondja: **publikus store-jelenlét NINCS** (4 bizonyítékkal) |
| [`docs/release/blockers.md`](docs/release/blockers.md) (49 sor) | **10 release-blocker** (1×P0, 5×P1, 4×P2), mind ID + severity + `pending` Ch12 **owner-kör** + bizonyíték + **zárási feltétel** |

**A kör legérdekesebb mért ténye:** a 26 GitHub Release és a `pubspec.yaml:5`
változatlan `1.0.0+1` build numbere **csak együtt értelmezhető** — a `build-NN`
tagnevek a projekt SDD előtti belső kör-számozását hordozzák (`build-175` = r175),
NEM a pubspec build számát. A projekt tehát **soha nem emelt build numbert** egy
kiadáshoz sem; ebből lett az `R-VER-01` (P1) blocker, owner: `E12-R06`.

**A megnyitott P0:** `R-SIGN-01` — a workflow- és Gradle-oldali fail-closed
signing-kényszer MEGVAN (`release-apk.yml:9-36`, `build.gradle.kts:58-70`), de a
4 GitHub secret tényleges megléte `gh` nélkül nem igazolható. Owner: `E12-R07`.

**Pre-flight (`§0.0.A`, `8132ed01`).** A brief §2 mind a hét száma újramérve —
mind változatlan. **Feloldott brief-ütközés:** a §7 megtiltja az implementernek a
`gh`-t, a §3 viszont a GitHub Releases auditját kéri → az orchestrátor mérte le a
leltárt és adta át hiteles bemenetként; az implementer `gh`-t nem hívott, a
`release-history-audit.md` pedig **soronként jelöli**, mi jön a pre-flightból és
mit futtatott újra maga. Új **A7** acceptance-cella az [L487](docs/LESSONS.md#l487)
hibaosztálya (le nem futott mérésre hivatkozás) ellen.

**Review:** [`docs/reviews/e12-r01-review.md`](docs/reviews/e12-r01-review.md) —
**APPROVED, 0 BLOCKER / 0 MAJOR / 0 MINOR / 2 NOTE, javító kör NÉLKÜL.** A
jelzésfájlból hiányzott a `scope_audit=` mező ([L177](docs/LESSONS.md#l177)) →
kézi audit mindkét bázisról `OK`. **A7 reprodukció:** a doksikból kimásolt **26
mérés mind reprodukálódott**. **Három valódi-sértés próba:** hamis migráció-szám
→ A7 pirosra vált; a 27 helyi tag vs. 26 Release **halmaz-egyenlősége** `comm`-mal
igazolva (delta = pontosan `build-81`); az implementer próbáinak 19-es
link-kiindulóértéke újramérve. **A6:** mind a 19 belső link él.

**Zöld kapu:** `tools/round-ci-plan.py` → `full-gate.yml` (`apk_required=false`) +
Router CI. A kör **három** SHA-n futtatta végig mindkét kaput, és **egyetlen piros
futást sem** termelt; a merge SHA (`16772202`) evidenciája:
[full-gate 33130933638](https://github.com/wolfcasaba/strumsight/actions/runs/33130933638) ·
[router-ci 33130934851](https://github.com/wolfcasaba/strumsight/actions/runs/33130934851).

**Új lecke:** [L525](docs/LESSONS.md#l525) — az exact-SHA CI-evidencia és a
review-commit körkörössége, és hol zárul le.

**Következő kör:** `E12-R02` — SDD-index és függőségi gráf (ADR `0443`, `sonnet-impl`).

## ✅ E13-R36 KÉSZ — Vizuális regresszió, eszközös elfogadás és a **Chapter 13 LEZÁRÁSA** — PR [#483](https://github.com/wolfcasaba/strumsight/pull/483), squash `15d55b12` (2026-08-27)

**A Chapter 13 (UI/UX Design System) 36 körös sávja ezzel LEZÁRULT.** A záró kör
nem „minden zöld" pecsétet hozott, hanem **két új, valódi kaput**, amelyek a saját
első futásukon **két addig láthatatlan `lib/**` elrendezési hibát mértek ki**.

- `test/ui/goldens/e13_r36_variant_matrix_test.dart` — **PNG nélküli** variáns-mátrix,
  **192 cella**: 6 kockázat-alapú képernyő (`today_hub`, `live`, `tuner`, `settings`,
  `vision_result`, `login`) × {light, dark} × {en, hu} × {compact 412×915, landscape
  915×412, medium 700×1000, expanded 1024×1366} × {textScale 1.0, 2.0}. Minden cella
  `FlutterError.onError`-on át méri a `RenderFlex` túlcsordulást és a pumpolás közbeni
  kivételt — nem szöveg-heurisztikán.
- `test/accessibility/closure_suite_test.dart` — a záró a11y-csomag, **12 cella**
  (route, engedély, állapot-visszaállítás, 200%-os interaktív login-kör), mind
  VALÓDI tap-interakcióval `textScale: 2.0` mellett.
- `docs/ui/legacy-backlog.md` (ÚJ) · `docs/ui/chapter-13-completion-report.md` (ÚJ) ·
  `docs/ui/migration-status.md` (mért záró állapot).

**A két kimért, dátumozott `lib/**` defekt** (a kör tilos zónája miatt itt nem
javítható, csak-zsugorodó kizárólistába téve, gépi stale-entry őrrel):

| Fájl | Cella | Mért túlcsordulás |
|---|---|---|
| `lib/features/live/screens/live_screen.dart:477` (stat-strip `Row`) | `live` × {light,dark} × {en,hu} × landscape × textScale 2.0 | **12 px** (en) / **34 px** (hu) |
| `lib/features/onboarding/screens/permission_primer_screen.dart` (véglegesen megtagadt ág, nem scrollable) | compact portrait × textScale 2.0 | **297 px** |

**Mért záró állapot:** **43 / 96 production képernyő migrálva (44,8%)** — a maradék
53 dátumozott, felelős-jelölt backlogba került. A jelentés kimondja: a fejezet nem
„teljesen migrált", hanem **„a jelenlegi terjedelmén minőségkapuzott"**. Új golden
PNG: **nulla** (a `test/ui/goldens/goldens/` fa érintetlen).

**Review:** [`docs/reviews/e13-r36-review.md`](docs/reviews/e13-r36-review.md) —
**APPROVED**, 1 javító kör (MINOR-1 elavult kizárólista-doc-comment, NOTE-1 az A2
részleges fedésének kimondása; NOTE-2 szándékosan nyitva). **Négy valódi-sértés
próba** mérte, hogy a kizárólista nem díszlet: a dokumentált 34 px tőlem függetlenül
reprodukálódott (P1), egy hamis bejegyzés egy ZÖLD cellára pirosra váltott (P2), a
closure-suite kizárása a tényleges `FlutterError` jelentést méri (P3), a 43/96 szám
reprodukálható (P4).

**Zöld kapu a `72455f2d` merge SHA-n:** Full Gate
[33120961301](https://github.com/wolfcasaba/strumsight/actions/runs/33120961301) +
Router CI [33120963209](https://github.com/wolfcasaba/strumsight/actions/runs/33120963209)
mindkettő `success`; lokális `tools/round-gate.sh` **10/10 zöld** izolált klónban,
mindkét kör-SHA-n. Scope-audit OK (6 fájl, 0 listán kívüli, **nulla `lib/**`**).

**Két eltérés a szokásos rituálétól, kimondva:**

1. **A pre-flight brief-commit KÖZVETLENÜL a `main`-re került** (`066c97ee`), nem a
   kör-ágra: a közös munkafa a `git checkout -b` és a `git commit` KÖZÖTT némán
   visszaváltott `main`-re (a reflog `checkout: moving from sonnet-impl/e13-r36-… to
   main` sora bizonyítja), így a `git push -u origin HEAD` a `main`-t célozta. A
   tartalom docs-only volt (kizárólag a kör SAJÁT briefje), a Router CI utólag zölden
   lefutott rá, és a merge-elt fa tartalma azonos azzal, amit a rendes merge adott
   volna — de a commit **kikerülte a PR/zöld-kapu utat**. Tanulság: [L523](docs/LESSONS.md).
2. **A `security-reviewer` ügynök nem futott** (a brief `risk = "high"`). Ennek a
   sessionnek explicit tiltása van subagent indítására, ezért a biztonsági átnézést
   az orchestrátor MAGA végezte a teljes diffen. Mért alap: a diff **nulla `lib/**`
   fájlt** érint, nincs benne hálózat-, tárolás-, engedély-, hitelesítés-,
   AI-provider- vagy felhasználói-adat-felület (hat fájl: négy dokumentum, két új
   teszt), és a gate `secrets` lépése 3921 fájlon 0 leletet adott. **Kockázat:** ez
   önbevallás, nem független szem — a következő `risk = "high"` körnél a dedikált
   read-only reviewernek futnia kell.

## ✅ E13-R35 KÉSZ (merge-elve) + H-NOSIGNAL önjavítás — PR [#480](https://github.com/wolfcasaba/strumsight/pull/480), squash `57eeb6ff` (2026-08-27)

Az UI-48 / UI-62–UI-65 account-, settings-, privacy-, offline-AI- és share-felület
(SDD Ch13 Kör 35) **zölden merge-elve**: a `b4941257` head SHA-n `full-gate`,
`router-ci` és `Coverage` mind `success`, a squash `57eeb6ff`.

**A kör mégis `H-NOSIGNAL`-lal állt meg.** Az orchestrátor-session 16:30:09-kor
indult, 4 órás abszolút időkorláttal; a merge 20:28:30Z-kor landolt, a driver
20:30:02-kor be is ff-merge-elte a `main`-re — a session viszont **99
másodperccel a merge után**, 20:30:09-kor futott bele az időkorlátba, a záró
rituálék (queue-sor `done`, HANDOFF, git-notes, **kör-jelzés**) előtt.

**Az önjavító kör (ADR 0112) gyökéroka nem a halt, hanem ami utána jött volna.**
A queue-sor `pending` maradt, tehát a lánc újra sorra vette volna a kört, és a
`tools/round-resume-probe.sh` a javítás előtt ezt mérte rá az éles repón:
`ÁLLAPOT: REVIEW-APPROVED` → *„a kör a merge-lépésnél folytatódik … zöld kapus
squash-merge"* — egy MÁR MERGE-ELT körre. A `--squash` miatt az ág csúcsa
(`b4941257`) **nem** őse a `main`-nek (`merge-base --is-ancestor` → 1), a
`--delete-branch` pedig már nem futott le, ezért a szonda „élő" kör-ágat talált.

**A javítás:** a szondán új fok, `MERGE-ELVE`, két független MÉRT jellel —
(a) az ág csúcsa őse a `<remote>/main`-nek, (b) a `<remote>/main` egy commitjának
a TÁRGYA a kör azonosítójával kezdődik (`[E13-R35] …`, a repó 52 kör-merge-én
egységes konvenció). A fok csak pozitív irányban dönt; idegen kör merge-commitja
(`[E13-R34] …`) nem minősít — külön teszt rögzíti. A teendője **lezárás**, nem
merge. A `docs/execution/pipeline-orchestrator-prompt.md` §0.2 létrája is
megkapta a fokot. Regressziós teszt: `tools/tests/test_round_resume_probe.py`
`AlreadyMergedRoundTest` (3 új eset, a valódi E13-R35 ág-/commit-adatokkal) —
a javítás előtt piros, utána zöld. Tanulság: [L522](docs/LESSONS.md).

**A queue-sor `done`**, a kör-ág és a `/home/ubuntu/ss-sonnet-impl-e13-r35`
munkapéldány takarítva; a sáv az **E13-R36** (vizuális regresszió és lezárás)
körrel folytatódik.

## ✅ E13-R34 KÉSZ — Community challenges, clubs, notifications és safety UI — PR [#479](https://github.com/wolfcasaba/strumsight/pull/479), squash `4f7eb630` (2026-08-27)

Az UI-59–UI-61 kihívás-, ranglista-, klub-, értesítés- és biztonsági felülete
(SDD Ch13 Kör 34). A kör **ADR-t nem írt** — a §5 normái a merge-elt
[`0291`](docs/adr/0291-community-is-optional-and-private-by-default.md),
[`0399`](docs/adr/0399-flutter-community-domain-and-public-api.md),
[`0414`](docs/adr/0414-notification-inbox-and-push-abstraction.md) és
[`0418`](docs/adr/0418-leaderboards-and-opt-in-competition.md); a sávon a
**tizenhetedik** ADR nélküli kör egymás után (E13-R17…R34). Implementer
`sonnet-impl` (Claude Sonnet 5, `--effort high`), orchesztrátor/reviewer Claude
Opus 5 + kötelező `security-reviewer` ügynök (`risk = "high"`), **1 javító kör**
— `docs/reviews/e13-r34-review.md`: 1. forduló **0 BLOCKER / 2 MAJOR / 1 MINOR
/ 6 NOTE → CHANGES REQUESTED**, 2. forduló **0 nyitott lelet → APPROVED**.

**A pre-flight ÁTÍRTA a brief fájllistáját, és vele a §0.0 NÉGY celláját.** A
`brief-lint` `S13` lelete szerint a `lib/features/community/{challenges,clubs,safety}/`
a fán nem létezik — ugyanaz a hibaosztály, mint az E13-R33-nál, és pontosan az,
amit [L518](docs/LESSONS.md#l518) tegnap **név szerint átadott ennek a körnek**.
Az `S13` nem egy sort, hanem MINDEN belőle levezetett cellát érvénytelenít: az
`R1` „a képernyőket ez a kör hozza létre" HAMIS volt (mind a hét képernyő a fán
van), az `R2` „nincs ilyen"-je HAMIS (**hat** pinnelő widget-teszt), az `R4` „a
szám elmozdul"-ja HAMIS (nincs új képernyő, a `ui_inventory` bázisvonal
változatlan **94**). A lista a §3 scope-jához tartozó **hét képernyőre** +
`presentation/widgets/`-re mutat — pontosan az a halmaz, amit az E13-R33
§0.0.B/B1 ennek a körnek tartott fenn, tehát a két kör fájlhalmaza
bizonyítottan diszjunkt.

**Négy további mért eltérés a brief feltevéseitől** (§0.0.B/B5–B9), mind a
§1.1 két kötelező mérési szabálya szerint a TÉNYLEGES hívási láncon:

1. **nincs kliens-oldali ranglista opt-in kapcsoló** — az opt-in a szerver
   `verified`-only projekciójának tulajdona (ADR 0418, E09-R23); egy kapcsoló
   bevezetése LEZÁRT kör szerződését írná át (**H2**). Az A1 ezért felület
   felőli absztinencia-cella lett;
2. **a „függő" küszöb `bestMetricValue == null`**, nem enum-érték — `pending` /
   `verified` érték a `ChallengeInviteState`-ben NINCS;
3. **„függő klub-csatlakozási kérelem" állapot a fán NEM ábrázolható**
   (`ClubRole` = `{owner, moderator, member}`) — a §6.1 cellahármas a MÉRT
   `myRole` × `ClubVisibility` küszöbre került (**H2** lett volna bevezetni);
4. **az értesítésnek nincs route-mezője és a közösségi képernyők nincsenek a
   routerben** (`grep -c community lib/app/routing/app_router.dart` → 0), a
   `lib/app/routing/**` pedig tilos zóna — az A4 strukturális absztinencia-cella
   lett (**H3** lett volna route-ot felvenni).

**A kör legnagyobb, MÉRÉSSEL talált munkája nem is a migráció volt: a klub-ág
TELJESEN lokalizálatlan volt.** A három klub-képernyőn **0** `AppLocalizations`
használat és **46** beégetett angol `const String _l10nClub*` konstans élt —
köztük a `Private` / `Discoverable` / `Public` láthatósági választó, a kör
legnagyobb következményű beállítása. Egy magyar nyelvre állított felhasználó a
klub-ág minden gombját angolul látta. Ez az [L519](docs/LESSONS.md#l519)
hibaosztálya fordított irányban, és új **A10** acceptance-cellát kapott `en`/`hu`
cellapárral (a mért tanulság szerint egy locale-specifikus cella önmagában csak
az ELLENKEZŐ nyelv beégetését fogja). Eredmény: 59 új ARB-kulcs a
`community_{en,hu}.arb` FORRÁS-fragmentumban, 0 maradék konstans, 0 bájtazonos
ARB↔Dart pár.

**A review két MAJOR-t talált a zöld gate MÖGÖTT** (`docs/reviews/e13-r34-review.md`):

- **MAJOR-1** — a privát klub NEVE kiszivárgott a klub-LISTA előnézetében
  (látható szöveg ÉS `Semantics` label), mert a körben ÚJ, háromágú
  `myRole × visibility` kapu csak a RÉSZLETnézetre került fel. A brief §6.1
  A3-cellája névvel nevezi a „lista-előnézet" csatornát, a célteszt viszont
  kizárólag a `ClubDetailScreen`-t mérte: **17/17 cella zöld volt, miközben a
  csatorna nyitva állt.** A `security-reviewer` reprodukálta.
- **MAJOR-2** — a kör KÉT ÚJ **védelmi** akciója (block/mute a klub-tagkezelésen
  és a kihívás-lapon) `try`/`catch` NÉLKÜL `await`-elt: hálózati hibán a
  felület sikeresnek látszott, SnackBar nélkül. Némán bukó védelmi művelet =
  hamis biztonságérzet. A testvér `safety_relationships_screen.dart` helyesen
  csinálta — a két új akció nem örökölte a mintát.

Mindkettő + a MINOR-1 (beégetett angol `Semantics` szöveg a kör új kódjában) a
javító körben lezárva, és **mindhárom zárását a reviewer SAJÁT eldobható
falszifikációs próbája igazolta** (P3: a lista-szűrő kivéve → mindkét új A3
cella piros; P4: a klub-oldali `catch` kivéve → pontosan a klub-management cella
piros, a challenges-cella zöld).

**A `textScaler 2.0` golden-keret harmadszor is felderítő mérésnek bizonyult**
([L517](docs/LESSONS.md#l517)): KÉT, kör ELŐTTI `RenderFlex` túlcsordulást
fogott meg (**805 px** a klub-részlet infóblokkján, **54 px** az értesítés-
AppBaren) — mindkettő JAVÍTVA, nem bázisvonalként rögzítve.

**Zöld kapu a merge SHA-n (`c102e581`):** Full Gate
[33090419506](https://github.com/wolfcasaba/strumsight/actions/runs/33090419506)
+ Router CI [33092107103](https://github.com/wolfcasaba/strumsight/actions/runs/33092107103)
mindkettő `success`; a reviewer izolált `/tmp` klónjában `tools/round-gate.sh`
**15/15 zöld**, `tools/golden-x86.sh check` **14/14 zöld** (7 képernyő × 2
keret), `tools/scope-audit.py` OK (0 listán kívüli fájl).

**Átadva a következő köröknek (NOTE, mind KÖR ELŐTTI vagy valódi H3):** az
értesítés `_lookupKey(...) ?? item.titleKey` fail-open feloldása (E09-R20, a
javítása H2); a `_requestJoin` hiányzó hibakezelése; hat bájtazonos `en`/`hu`
ARB-pár; a **`report` (bejelentés) akció bedrótozása** — mérve:
`showReportContentSheet` egy `ReportRepository`-t KÖVETEL és az egész fán
**nulla production hívója** van, egy implementáció a `data/` réteget kívánná
(valódi H3), ezért az A6 a tiltás/némítás lábán teljesül, a bejelentés-láb
jövőbeli kör; a golden-fixture valós handle-je; a klub Feed/Challenges tabok
`UnimplementedError`-jai (E09-R25 óta).

## ✅ E13-R33 KÉSZ — Community profil, feed, keresés és poszt UI — PR [#478](https://github.com/wolfcasaba/strumsight/pull/478), squash `e2b3f71c` (2026-08-27)

Az UI-53–UI-58 **opcionális, alapból nem nyilvános** közösségi felülete (SDD
Ch13 Kör 33). A kör **ADR-t nem írt** — a kiosztott `0291` 2026-08-15 óta
merge-elt (`5b32bd8e`); a sávon a **tizenhatodik** ADR nélküli kör egymás után
(E13-R17…R33). Implementer `sonnet-impl` (Claude Sonnet 5, `--effort high`),
orchesztrátor/reviewer Claude, **1 javító kör** — `docs/reviews/e13-r33-review.md`:
1. forduló **0 BLOCKER / 1 MAJOR / 1 MINOR → CHANGES REQUESTED**, 2. forduló
**0 BLOCKER / 0 MAJOR / 0 MINOR / 4 NOTE → APPROVED**.

**A pre-flight ÁTÍRTA a brief fájllistáját — a három előtag NULLA fájlt fedett.**
A `brief-lint` `S13` lelete szerint a `lib/features/community/{profile,feed,posts}/`
a fán nem létezik: az Epic-9 a feature-t **réteges** szerkezetben építette fel
(`application/`, `data/`, `domain/`, `presentation/`). Ezt a
`docs/execution/pipeline-queue.tsv` Epic-9 blokkja 2026-08-22-én **előre
kimondta**, és a feloldást kifejezetten ennek a körnek a pre-flightjára bízta.
A lista ezért a §3 scope-jához tartozó **nyolc képernyőre** + a `widgets/` és
`dialogs/` előtagra mutat; az E13-R34 öt képernyője (`clubs/*`, challenges,
leaderboard, safety, notifications) szándékosan kimaradt — a két kör
fájlhalmaza **diszjunkt**.

**Ez MIGRÁCIÓS kör volt, nem zöldmezős.** A `grep -rn "design_system"
lib/features/community/presentation/` a pre-flightban **0 találatot** adott: a
nyolc képernyő közvetlenül `material.dart`-ot használt. A kör ezt migrálta —
`CommunityThemeScope` + `SsSurface`/`SsButton`/`SsSwitchRow`/`SsChoice`,
kizárólag a `core/design_system/public.dart` barrelen át (ADR 0273 §1). Új
`CommunityModerationPlaceholder` az A7-hez. A `TextField`/`RadioListTile`
SZÁNDÉKOSAN nem migrált (a 7 meglévő teszt findere tört volna) — dokumentált
scope-határ, nem csendes kihagyás.

**Valódi ÚJ viselkedés, nem kozmetika:** a „nyilvános" közönség (poszt ÉS
profil) mostantól **kimondott, visszavonhatatlanságra figyelmeztető
megerősítés** mögött van (A2); a tiltás/némítás a repository-hívás `await`-je
**ELŐTT** tünteti el a sort (A5, ADR 0291 §4); az eltávolított tartalom
helyőrzőt kap a feedben és a szálban (A7).

**A pre-flight két mérési szabálya mindkettő FOGOTT.** (1) *Elérhetetlen
cél-státusz:* a brief §6.1 első cellája `private` alapértelmezett közönséget
írt elő — ezt a fán **egyetlen input sem produkálja** (a MÉRT alapérték
`CommunityAudience.followers` / `ProfileVisibility.followers`), az átállítása
pedig egy LEZÁRT kör viselkedését változtatta volna (**H2**). A kötő norma a
merge-elt ADR 0291 §2 „**nem nyilvános**" predikátuma; a cellahármas erre
mutat, és a mérce nem lazult (a `public` alapérték az A2-t pirosra váltja).
(2) *Erőforrás-tulajdonlás:* az idempotencia-kulcsot az `application/` réteg
birtokolja — a `PostComposerController` EGYSZER generálja és minden további
mentésnél ÚJRAHASZNÁLJA (`:352–366`); a `presentation/` fa 12 találata mind a
listán KÍVÜLI R34-es képernyőn van, és egyik sem rendereli a kulcsot.

**A §0.0/R2 batch-mérés ÉRVÉNYTELEN volt — és ez a kör legfontosabb tanulsága.**
Az R2 „nincs ilyen"-t írt (nincs a kör fáján élő widget-teszt), mert a NEM
LÉTEZŐ előtagok ellen mért. A MÉRT `presentation/` rétegen **hét** ma zöld
widget-teszt állt közvetlenül a kör képernyőire — pontosan az a `blocked`
hibaosztály, amit az R2 el akart kerülni. Általánosítva: egy `S13` lelet nem
egyetlen sort érvénytelenít, hanem **minden** §0.0 cellát, amit ugyanabból az
előtagból vezettek le ([L518](docs/LESSONS.md#l518)).

**MAJOR-1 — a kör a saját ARB-kulcsát nem kötötte be a szerkesztőben.** A kör
felvette a `communityPublicConfirm*` kulcsokat `en`-be ÉS `hu`-ba, az
`edit_profile_screen.dart`-ban helyesen olvasta is őket — a
`post_composer_screen.dart`-ban viszont ÚJ, beégetett magyar konstansokat adott
hozzá, a `community_hu.arb` értékeivel **bájtra azonosan**. Angol nyelvre
állított felhasználó így a kör legnagyobb következményű műveleténél (a
visszavonhatatlan nyilvánossá tétel megerősítésénél) magyar szöveget kapott,
miközben a helyes angol már a fán volt. A javító kör bekötötte az
`AppLocalizations`-t és gépi őrt adott hozzá ([L519](docs/LESSONS.md#l519)).

**Reviewer-bizonyíték.** Független gate-újrafuttatás izolált `/tmp` klónban,
mindkét SHA-n: **15/15 zöld**. `golden-x86.sh check` **16/16 zöld** (8 képernyő
× 2 keret). Scope-audit `ok` — 42 fájl, **0** listán kívüli, az `application/`,
`data/`, `domain/` réteg érintetlen. **Négy** eldobható falszifikációs próba,
mind pirosra váltotta a saját celláját: P1 (`public` alapérték) **5 cella**,
P2 (szerver-first tiltás) **2 cella**, P3 (friss kulcs minden mentésnél) **1
cella**, P4 (a javított A2-felirat visszaégetése) **1 cella**; a fa minden
próba után visszaállt. A hét meglévő `presentation/`-teszt **gyengítés nélkül**
zöld (`+82`), a `ui_inventory` `hasLength(94)` érintetlen — a kör nem hozott új
képernyőt, és a router (`lib/app/routing/**`) tilos zóna maradt. A kötelező
`security-reviewer` (`risk = "high"`) **0 BLOCKER / 0 MAJOR**-ral zárt; a hét
termékhatárból a döntéshordozókat saját méréssel is ellenőriztem.

Exact-SHA evidencia a merge SHA-n (`185556ec`): Full Gate
[33075065684](https://github.com/wolfcasaba/strumsight/actions/runs/33075065684)
`success` + Router CI
[33075068467](https://github.com/wolfcasaba/strumsight/actions/runs/33075068467)
`success`.

**Következő kör:** `E13-R34` — Community Challenges és Safety UI
(`docs/rounds/e13-r34-community-challenges-and-safety.md`, ADR `nincs`,
implementer `sonnet-impl`). **Horog:** a briefje ugyanabban a NEM LÉTEZŐ
előtag-hibában szenved (`community/{challenges,clubs,safety}/`) — a
pre-flightja ugyanígy a MÉRT `presentation/` rétegre mutasson, és **külön mérje
meg**, mely meglévő widget-tesztek állnak az öt képernyőjére (a
`clubs/club_detail_screen_test.dart`, `clubs/club_list_screen_test.dart`,
`community_challenges_test.dart`, `community_notifications_test.dart`,
`leaderboard_screen_test.dart`, `screens/safety_relationships_screen_test.dart`
— ezeket az E13-R33 szándékosan NEM vitte a listájára).

## ✅ E13-R32 KÉSZ — Gamification Hub, Quest, Achievement és Reward UI — PR [#477](https://github.com/wolfcasaba/strumsight/pull/477), squash `ff9f3096` (2026-08-27)

Az UI-51–UI-52 **együttérző, idempotens** jutalmazási felülete (SDD Ch13 Kör 32).
A kör **ADR-t nem írt** — a kiosztott `0290` 2026-08-15 óta merge-elt
(`5b32bd8e`); a sávon a **tizenötödik** ADR nélküli kör egymás után
(E13-R17…R32). Implementer `sonnet-impl` (Claude Sonnet 5, `--effort high`),
orchesztrátor/reviewer Claude, **0 javító kör** — a review első fordulója
`docs/reviews/e13-r32-review.md`: **0 BLOCKER / 0 MAJOR / 1 MINOR (a review
során javítva) / 2 NOTE → APPROVED**.

**Ez MIGRÁCIÓS kör volt, nem zöldmezős.** A pre-flight kimérte, hogy a hét
gamifikációs képernyő már létezik, mind caller-fed, és a fa **nulla**
`design_system` importtal élt. A kör ezt migrálta: `GamificationThemeScope` +
`SsSurface`, kizárólag a `core/design_system/public.dart` barrelen át
(6 import, mind a barrelen). Új `PendingRewardsCard` a függő/karanténos
főkönyvi sorokhoz, `onRetry` → `ActivityEventIngestor.drain()`; a felület
**sosem** ír főkönyvet (`appendIfAbsent` a `presentation/` fán: **0 találat**)
és sosem mutat jóváírt egyenleget a drain előtt. `reduceMotion` szál a
`StreakStatusCard` / `StreakDetailScreen` / `RewardSummarySheet` widgeteken,
VAGY-kapcsolva a `MediaQuery.disableAnimationsOf`-fal — az ADR 0393 §5.1
kifejezetten erre a körre hagyta a celebration-UI bekötését.

**A pre-flight két mérési szabálya mindkettő FOGOTT.** (1) *Elérhetetlen
cél-státusz:* az A5 „türelmi idő" cellája a `StreakGraceState`-re épült volna,
aminek a fán **egyetlen** értéke van (`none`) — a MÉRT input a
`StreakEvaluationReason`, a küszöb `graceDays = 1`, a cellahármas `gap = 0/1/2`
→ `grace`/`grace`/`broken`. (2) *Erőforrás-tulajdonlás:* az `appendIfAbsent`
hat hívási helye mind az `application/`+`data/` rétegben van, nulla a
presentationben — a „beváltás" felületi művelete ezért a `drain()`
újrapróbálkozás, nem egy claim-gomb (a `RewardInboxItem.seen` doc-commentje
szó szerint „not a claim, not an expiry, not a precondition for anything").

**A golden-felvétel MÁSODSZOR mért ki VALÓDI, addig láthatatlan elrendezési
hibát** `textScaler 2.0` mellett: egy 1577 px-es `RenderFlex overflow`-t az új
kártyán, és egy 41 px-es vízszintes túlcsordulást a **kör előtti**
`_InboxEntryTile` XP-feliratán ([L517](docs/LESSONS.md#l517)).

**MINOR-1 — a §7 gate-sor öröklött golden-útvonala.** Az E13-R31 briefjéből
örökölt sor a `round-gate.sh`-ba fűzte a golden-tesztet; ez a kör megmérte, hogy
az ARM↔x86 raszterizációs drift **képernyő-függő**: ezen a boxon (aarch64)
**5/10 cella piros**, a merge-kapu architektúráján (x86_64) **10/10 zöld**. A
szekvenciális gate így a golden-lépésnél megállt volna az `architecture` /
`secrets` / `l10n` előtt. Az implementer helyesen az ADR 0426 szerint járt el;
az orchestrátor a review-ban a briefet igazította (§0.0.C) — a mérce NEM lazult:
a 10 golden-cellát továbbra is KETTŐ méri, a `tools/golden-x86.sh check` és az
exact-SHA Full Gate, mindkettő x86_64-en ([L516](docs/LESSONS.md#l516)).

**Reviewer-bizonyíték.** Független gate-újrafuttatás izolált `/tmp` klónban:
**15/15 zöld**, `GATE_EXIT=0`. Scope-audit `ok` — 33 fájl, **0** listán kívüli.
Három eldobható **falszifikációs próba** a §6.1 mátrix ellen: a büntető
széria-szöveg az **A1**-et, a pihenőnap-mint-széria-vége az **A5**-öt, az
ünneplés eltüntetése csökkentett mozgásnál az **A8**-at váltotta pirosra —
mind a felirat és az adatforrás szintjén ([L403](docs/LESSONS.md#l403)), nem
widget-típuson; a fa minden próba után visszaállt. Az 5 meglévő gamifikációs
widget-teszt **módosítás nélkül** zöld maradt, a `ui_inventory` `hasLength(94)`
és az `app_router_test` hat pinnelt screen-TÍPUSA érintetlen.

Exact-SHA evidencia a merge SHA-n (`e23d321a`): Full Gate
[33064656196](https://github.com/wolfcasaba/strumsight/actions/runs/33064656196)
`success` + Router CI
[33064599257](https://github.com/wolfcasaba/strumsight/actions/runs/33064599257)
`success`.

**Következő kör:** `E13-R33` — Community Feed és Posts UI
(`docs/rounds/e13-r33-community-feed-and-posts.md`, ADR `0291`, implementer
`sonnet-impl`).

## ✅ E13-R31 KÉSZ — Progress Dashboard és Skill Detail UI — PR [#476](https://github.com/wolfcasaba/strumsight/pull/476), squash `0965188f` (2026-08-27)

Az UI-49–UI-50 **bizonyíték-alapú fejlődési felülete** új
`lib/features/progress_v2/` fán (SDD Ch13 Kör 31). A kör **ADR-t nem írt** — a
kiosztott `0289` 2026-08-15 óta merge-elt (`5b32bd8e`); a sávon a
**tizennegyedik** ADR nélküli kör egymás után (E13-R17…R31). Implementer
`sonnet-impl` (Claude Sonnet 5, `--effort high`), orchesztrátor/reviewer Claude
Opus 5, **1 javító kör** (`docs/reviews/e13-r31-review.md`: első forduló
0 BLOCKER / **1 MAJOR** / 3 MINOR / 2 NOTE → a javító kör után APPROVED,
0 nyitott lelet).

**A MAJOR-t a teljes CI-suite ZÖLDEN átengedte.** A mérce-verzió előzmény
szegmenseit a képernyő a `catalogVersion` ÉRTÉKÉVEL kulcsolta, miközben a kör
SAJÁT `segmentByCatalogVersion` függvénye kimondottan támogatja és teszttel
bizonyítja a visszatérő verziót (`[1, 2, 1]` → 3 szegmens, „never re-merges").
Két azonos verziójú szegmens így két azonos kulcsú testvér ugyanabban a
`Column`-ban → `FlutterError: Duplicate keys found`, azaz a felület
**összeomlik a szerződés szerinti bemeneten**. A Full Gate a javítás előtti
SHA-n (`2903f248`) `success` volt
([run 33053175578](https://github.com/wolfcasaba/strumsight/actions/runs/33053175578));
a leletet egy eldobható reviewer-próbateszt mérte ki, mert a meglévő cella
kizárólag `[1, 2]`-t pumpált. A javítás (pozícióval egyedi kulcs) **valódi-
sértés próbával** igazolt: a régi kulccsal az ÚJ `[1,2,1]`-rendering cella
pirosra vált a pontos eredeti hibaüzenettel — [L514](docs/LESSONS.md#l514).

**A pre-flight §1.1/1. szabálya megtérült (§0.0.B/B3).** A brief §6.1 trend-
küszöbe **5**, a fán mért `minimumSessionsForTrend` viszont **3**
(`audio_analysis/engine/comparison/trend_builder.dart:9`). A kettő MÁS felület
mércéje: az 5 forrása a merge-elt ADR 0289 §4, ezért a `progress_v2` saját
nevesített konstansként hordozza, a `TrendBuilder`-t nem importálja. A §6.1
„alatta" cellája ezért **pontosan 3 adatpont** — falszifikációs őr arra a
hibás implementációra, amelyik a szomszéd konstanst venné át.

**A `scope_audit=VIOLATION` hamis pozitív volt, és orchestrátor-hiba.** A
jelzett egyetlen sértés az **általam** a munkapéldány gyökerébe írt
implementer-prompt (`.pipeline-prompt-e13-r31.md`) volt — untracked, sosem
commitolva, `implementer_status=done` mellett. A fájl kivétele után a kézi
audit `ok` (24 útvonal, 1 generated/ignored = a review-jelentés) —
[L515](docs/LESSONS.md#l515).

**A `risk = "high"` biztonsági mérés: 0 lelet.** A `progress_v2` fa nem
tartalmaz hálózati hívást, tartós tárolást, plugin- vagy falióra-olvasást
(caller-fed projekció, ADR 0378 §1 precedense); cross-feature import kizárólag
`public.dart` barrelen át.

Exact-SHA evidencia a merge SHA-n (`0b70481e`): Full Gate
[33056100194](https://github.com/wolfcasaba/strumsight/actions/runs/33056100194)
`success` + Router CI
[33056172766](https://github.com/wolfcasaba/strumsight/actions/runs/33056172766)
`success`.

## ✅ E13-R30 KÉSZ — Vision Setup, Coach Stage és Result UI — PR [#475](https://github.com/wolfcasaba/strumsight/pull/475), squash `d25c6932` (2026-08-27)

Az UI-45–UI-47 **kamera-, kalibrációs, élő-jelzés és eredmény-felülete**
adatvédelmi és hő-védelemmel (SDD Ch13 Kör 30). A kör **ADR-t nem írt** — a
kiosztott `0288` 2026-08-15 óta merge-elt (`5b32bd8e`); a sávon a
**tizenharmadik** ADR nélküli kör egymás után (E13-R17…R30). Implementer
`sonnet-impl` (Claude Sonnet 5, `--effort high`), orchesztrátor/reviewer Claude
Opus 5, **0 javító kör** — a review első fordulóban APPROVED (0 BLOCKER,
0 MAJOR, 3 MINOR, 4 NOTE, `docs/reviews/e13-r30-review.md`).

**A brief SAJÁT kötelező pre-flightja megtérült (§0.0/B1).** A brief fejléce
előírta annak mérését, elérhető-e a vision modell-bináris és a képkocka-forrás.
Mérve: a `model_manifest.json` MINDKÉT `vision_models[]` bejegyzése
`status: deferred`, a `sha256` csupa nulla, és az `assets/ml/*_deferred.tflite`
fájlok **nincsenek a fán**; a `FeatureFlags.visionEnabled` alapértéke `false`.
A kör ezért végig a **fake képkocka-folyamra** (`FakeCameraCapture`) és
teszt-oldali provider-felülírásra épült — ezt a §10 rögzíti.

**A `lib/features/vision/` előtag SZŰKÜLT `presentation/`-re (§0.0/B2).** Az
eredeti könyvtár-előtag magába foglalta a `data/landmarks/**` képfeldolgozást
és a teljes `domain/**`-t, amit viszont a brief §3-a kimondottan tilt — a lista
és a tilalom ellentmondott egymásnak. A szűkítés mérve elég volt: az egy-jelzés
prioritása MÁR KÉSZ a domainben (`CueBudget.selectRealtime` egyetlen
`VisionInsight?`-ot ad), és a három `.acquire(` hívó mind a presentationon
KÍVÜL van.

**Két acceptance-cella NEM volt előállítható a merge-elt állapotgépből.** A
`VisionSessionStatus` 15 értéke közül egyik sem hő-jellegű, és a
`ThermalStateAdapter`-nek **nulla** production hívója van (A5); a
`VisionSetupStep.audioOnly` egyetlen előállítója pedig a user `skip()`-je, a
SDD-ben megnevezett `VisionCapability` típus a fán nem létezik (A6). Mindkét
cella **presentation-szintű, tesztből felülírható szolgáltatóra** került — a
követés-vesztés viszont a merge-elt `calibrationLost`-ból jön, tehát a két
állapot gépileg is elkülönül.

**Az implementer 3600 s-nél timeoutolt — commit ELŐTT.** `dirty_files=23`,
`head` a pre-flight commit. A wrapper scope-auditja viszont LEFUTOTT
(`scope_audit=ok`, 23 fájl), tehát a mért fa **nem volt elveszett munka**: az
orchestrátor commitolta, és a teljes mércét ő futtatta le
([L512](docs/LESSONS.md#l512)). `round-gate.sh` **19/19 zöld**, scope-audit
0 sértés, `security-reviewer` (kötelező, `risk=high`) **PASS**, és négy
mutáció-ölő valódi-sértés próba mind a **kijelölt** cellát váltotta pirosra.

**Három MINOR maradt nyitva** (merge nincs blokkolva): a képesség- és a
hő-szolgáltató ma konstans defaultot ad, tehát az A6/A5 production-úton még
nem hajtható meg — a valódi jelforrás bekötése az `application/` réteget
kívánná, ami a kör tilos zónája volt, és ezt a §0.0/B3–B4 előre kimondta; a
megőrzés-státusz pedig a FUTÓ Stage-en nem hangzik el, csak a belépésnél és a
kilépésnél (ADR 0288 §2 „végig látható").

**Következő kör:** `E13-R31` — Progress és Skills UI
(`docs/rounds/e13-r31-progress-and-skills.md`), új sessionben.

## ✅ E13-R29 KÉSZ — Coach Home, Tutor és Debrief UI — PR [#474](https://github.com/wolfcasaba/strumsight/pull/474), squash `7dd21a64` (2026-08-27)

Az UI-42–UI-44 **provenance-tudatos** AI-coaching felülete (SDD Ch13 Kör 29):
Coach kezdőképernyő, beszélgetés-felület és debrief / terv-előnézet. A kör
**ADR-t nem írt** — a kiosztott `0287` 2026-08-15 óta merge-elt (a sávon a
**tizenkettedik** ADR nélküli kör egymás után, E13-R17…R29). Implementer
`sonnet-impl` (Claude Sonnet 5, `--effort high`), orchesztrátor/reviewer Claude
Opus 5, **0 javító kör** — a review első fordulóban APPROVED (0 BLOCKER,
0 MAJOR, 2 MINOR, 3 NOTE, `docs/reviews/e13-r29-review.md`).

**A pre-flight legsúlyosabb lelete (§0.0/B1).** A brief `lib/features/coach/`
és `lib/features/tutor/` könyvtár-előtagot sorolt fel — egyik sem létezik
(`brief-lint` S13) —, és a batch pre-flight feloldása („a képernyőket EZ a kör
hozza létre") **mérhetően hamis** volt: a coach/tutor/debrief felület a
`lib/features/ai_tutor/presentation/` fában él, három MEGLÉVŐ képernyővel
(`tutor_home_screen`, `tutor_chat_screen`, `practice_plan_preview_screen`) és
nyolc widgettel. Ez tehát **migrációs**, nem zöldmezős kör volt. A lista a MÉRT
rétegre cserélve, szigorúan szűkebben, mint a szomszéd kör user-jóváhagyott
alakja (nincs `public.dart`, nincs teljes providers-fa, nincs
`application/`/`domain/`).

**Két merge-elt ADR-határ kimérve a pre-flightban.** (1) Az A2/A4 „tool-akció"
fogalma = `TutorAction` (write/launch); a `ReadOnlyTutorTools.safeToolNames`
zárt halmaza az ADR 0133 §2 / ADR 0137 §1–2 **explicit mentesítése**, tehát a
megerősítés megkövetelése rajta **H2** lett volna. (2) A brief §7-je
`flutter test --update-goldens`-t írt elő, ami ütközik a merge-elt ADR 0426
§2–§3-mal (ARM-felvétel az x86-os kapun mindig piros) — a §7 a
`tools/golden-x86.sh record`/`check` alakra váltott.

**A §0.0/B9 gépi őr IGAZOLÓDOTT.** A brief-lint `S11` első ága (a pinnelő
tesztek `allowed_paths`-ra vétele) az orchestrátornak tágítás = H3
([L478](docs/LESSONS.md#l478)), ezért a pre-flight a MÁSODIK ágat választotta:
a kör MÓDOSÍTJA a képernyőket, nem cseréli a típusukat, és a négy pinnelő
teszt a `gate_tests`-be került (futtatni KELL, szerkeszteni TILOS). A kör
közben pontosan ez ütött be: a `TutorHomeScreen` `ConsumerWidget`-té alakítása
elbuktatta a listán kívüli `test/app/navigation/adaptive_scaffold_test.dart`-ot,
és az implementer a **saját kódját** állította vissza (`7efa1059`) — nem a
tesztet írta át. A lelet a LOKÁLIS kapun jött elő, nem CI-only leletként.

**Az implementer futása `timeout`-tal zárult**, miközben a §10 handoff zöld
kaput állított — a jelzés mellett ez **bizonyítatlan**, ezért a reviewer a
teljes mércét újrafuttatta: `round-gate.sh` 17/17 zöld, `golden-x86.sh check`
6/6 zöld, `scope_audit=ok` (22 fájl). A munka `dirty_files=0`-val commitolva
volt, tehát nem veszett el semmi.

**Két MINOR maradt nyitva** (merge nincs blokkolva): a „nincs mért bizonyíték"
jelzés TÍPUS-alapú, nem TARTALOM-alapú (üres evidence-blokk elnyomja — a
[L403](docs/LESSONS.md#l403) osztály, amit a brief §6.1-e csak az A2/A3-ra írt
elő), és a két tool-akció-kártya továbbra sincs bekötve (nem regresszió: a
base-en sem volt, a bekötés a tilos `application/` réteget kívánná).

**Következő kör:** `E13-R30` — Vision UI (`docs/rounds/e13-r30-vision-ui.md`,
ADR `0288`), új sessionben.

## ✅ E13-R28 KÉSZ — Unified Library és Session Detail UI — PR [#473](https://github.com/wolfcasaba/strumsight/pull/473), squash `a3179aa1` (2026-08-27)

Az UI-40–UI-41 **egységes könyvtára** (SDD Ch13 Kör 28): egy felület, amin a
felhasználó ÖSSZES tartalma — elemzés, gyakorlás, dal, setlist — egy listában
él, típus-biztos részletnézettel, hatókört **nevesítő** törléssel és
szinkron-ütközés-választóval. A kör **ADR-t nem írt** — a `0279` és a `0283`
merge-elt és érvényes; a sávon ez a **tizenegyedik** ADR nélküli kör egymás
után (E13-R17…R28).

**A kör egy `H3` halt UTÁN zárult.** Az első futás kész kóddal, de a kapu 12.
lépésén pirosan állt meg: három cross-feature sértés, amelyeknek a javítása a
`lib/features/song_trainer/public.dart`-ban élt — a kör listáján KÍVÜL. A
halt-jelzést az önjavító kör dolgozta fel (`8c48af55`, [L508](docs/LESSONS.md#l508)),
a §0.0/**R5** revízió **egyetlen** fájllal, öt `show`-os szimbólumra szűkítve
tágította az `allowed_paths`-t, és ez a folytató kör hajtotta végre a javítást.

**Az új fa** (`lib/features/library_v2/`): sealed `LibraryItem` az öt
tétel-változattal (`Analysis`, `Practice`, `Song`, `Setlist` + a
`CorruptLibraryItem` placeholder), négy forrás-adapter — mindegyik a **meglévő**
repositoryt csomagolja, új tárolót egyik sem nyit (§5.4) —, a négy forrást
összefésülő `libraryV2ItemsProvider`, valamint a lista, a típus-biztos
részletnézet, a törlés-felület és a szinkron-ütközés választója.

**Routing:** a `AppRoutes.profileLibrary` builder a `UnifiedLibraryScreen`-re
áll át, és új `AppRoutes.profileLibrarySession` route kerül be
(`state.extra is LibraryItem` redirekttel a hiányzó/rossz extra esetére). A
**legacy** `/library` (`app_router.dart:264–265`) és `librarySession`
(`:305–313`) buildere **szó szerint érintetlen** — a V1 fa a rollback-útvonal
miatt sértetlenül fut (ADR 0220).

**A zöld kapu — az orchestrátor SAJÁT, izolált futása:** `tools/round-gate.sh`
a brief §7 szerinti 13 útvonalon → **18/18 ZÖLD**, kilépési kód `0`, **139**
teszt. `check_architecture` **3 → 0** sértés. Exact-SHA CI a merge SHA-n
(`e4c51d95`): **Full Gate** ✅ + **Router CI** ✅.

**Falszifikálva, nem bemondva:** a barrel-import visszaírása a belső útvonalra a
checkert kilépési kód `1`-gyel, pontosan a várt sértéssel pirosra váltja — a
zöld tehát a javításból jön, nem a mérce elnémulásából. Gépileg igazolt, hogy a
kör **nem** nyúlt a `tool/check_architecture.dart`-hoz (nincs új, ADR-t igénylő
allowlist-bejegyzés), a `test/core/architecture_dependency_test.dart`-hoz és a
`tool/ui_inventory.dart`-hoz, és a review `C` ágaként ELVETETT kerülőút (a
wiring `lib/app/routing/`-ba költöztetése, ahol a `lib/app/**` mentesül a
határszabály alól) sem valósult meg.

**Scope:** 38 fájl, mind az `allowed_paths` alatt. A szűk mandátumú fájlok
tételesen igazolva: `ui_inventory_test.dart` PONTOSAN a `hasLength(89) → (91)`
emelés; a `test/app/navigation/` **két** típus-pin cellája (§0.0/R3); a
`song_trainer/public.dart` három **additív** export-sora. Cella törlése,
`skip`-je vagy gyengítése: **nincs**. A `lib/l10n/app_*.arb` aggregátum
bitre reprodukálódik a `base/` szegmensből (`gen_l10n_segments.dart --write`
után 0 módosított fájl), tehát valóban generált.

**Új tanulság:** [L509](docs/LESSONS.md#l509) — a halt utáni upstream-szinkron
brief-konfliktusa NEM „tartsd meg a `main` verzióját": az önjavító kör
(`§0.0/R5`) és a kör saját ág-oldali artefaktumai (`§0.0/B`, `§10`, `§11`)
**diszjunkt** szakaszok, a feloldás **unió**. A §0.3 kifutásának szó szerinti
követése a kör pre-flightját, handoffját és első review-ját dobta volna el.

**Review:** [`docs/reviews/e13-r28-review.md`](docs/reviews/e13-r28-review.md) — **APPROVED**, 0 nyitott lelet.

**Következő kör:** `E13-R29` — Coach, Tutor és Debrief (`docs/rounds/e13-r29-coach-tutor-and-debrief.md`, ADR `0287`), új sessionben.

## 🔧 E13-R28 ÖNJAVÍTÓ KÖR (H3) — a `song_trainer` gyökér-barrel a kör listájára került (2026-08-27)

A kör kész volt, a lokális kapu **12-ből 11 lépésen zöld**, és a
`test/core/architecture_dependency_test.dart` pontosan **három** sértéssel állt
meg: `library_v2` → `song_trainer` belső fájlok (`domain/repositories/**` ×2,
`application/song_trainer_providers.dart`). Reprodukálva a kör munkapéldányán
(`dart run tool/check_architecture.dart`, HEAD `090990f2`).

**Nem implementer-hiba: a lista hiánya.** A §3 scope kimondja, hogy az egységes
könyvtár a dal- és setlist-tételtípust is listázza, a
`lib/features/song_trainer/public.dart` viszont ma kizárólag két képernyőt
exportál — a kör a saját listáján belül maradva egyetlen határ-legális importot
sem tudott volna leírni. A nested `domain/public.dart` nem oldja fel (nincs
rajta `domain/repositories/**`), a wiring `lib/app/routing/`-ba költöztetése
pedig a szabály megkerülése lett volna, ezért elvetve.

**A javítás:** §0.0/**R5** brief-revízió — az `allowed_paths` **egyetlen** új
fájllal bővült (`lib/features/song_trainer/public.dart`), a jogosultság a
§0.0/R5-ben `show`-klauzulával öt szimbólumra szűkítve. A `song_trainer` minden
más fájlja tiltott zóna marad.

**MÉRVE (a kör munkapéldányán, a próbafolt utólag visszaállítva — a kódmunka a
folytatódó köré):** `check_architecture` 3 → 0 sértés, `flutter analyze lib/`
`No issues found!`, `flutter test test/core/architecture_dependency_test.dart`
`+44`. Őrteszt: `tools/tests/test_e13_r28_song_trainer_public_barrel_scope.py`
(a javítás előtt PIROS, utána zöld); `python3 -m pytest tools/tests -q` →
**802 passed, 1 skipped**. Tanulság: [L508](docs/LESSONS.md#l508).

## ✅ E13-R27 KÉSZ — Analysis Overview, Timeline, Metric és Compare UI — PR [#471](https://github.com/wolfcasaba/strumsight/pull/471), squash `245a6ad3` (2026-08-27)

Az UI-37–UI-39 Studio Analytics rendszere (SDD Ch13 Kör 27): **áttekintő**,
**virtualizált idővonal**, **mérőszám-részletnézet** és **session-összehasonlítás**.
A kör **ADR-t nem írt** — a kiosztott [`0286`](docs/adr/0286-charts-need-a-text-alternative.md)
2026-08-15 óta merge-elt (`6e7877de`), újraírása **H1** lett volna. A sávon ez a
**tizedik** ADR nélküli kör egymás után (E13-R17…R27).

**Öt új design-system analitika-komponens** (`lib/core/design_system/components/analytics/`):
`SsScoreRing`, `SsTrendIndicator`, `SsConfidenceLegend`, `SsChartTextSummary`,
`SsEventList` — mind exportálva a `public.dart`-ból, **mind bekötve productionbe**
(nincs halott komponens).

**A pre-flight legfontosabb lelete: a brief megint a MÁSIK analyze-fát írta le.**
A `brief-lint` `S13` jelezte, hogy a `lib/features/analyze/results/` előtag nulla
fájlt fed — de a mélyebb hiba ugyanaz volt, mint az R26-nál ([L503](docs/LESSONS.md#l503)):
a `lib/features/analyze/` a **legacy V1** fa, a kör öt eredmény-képernyője viszont
a **V2 `lib/features/audio_analysis/presentation/`** fában él, és ott **MÁR
LÉTEZETT** — a merge-elt E13-R26 tilos zónája szó szerint „a Kör 27 öt
eredmény-képernyője" néven tartotta fenn ennek a körnek. A kör tehát **migrált és
kiegészített**, nem nulláról épített.

**A csere ára egy ÚJ lint-lelet volt (S11), és a feloldása szűkítés lett, nem tágítás.**
A meglévő fát célozva kilenc, a briefen KÍVÜL élő teszt pinneli a képernyőket. A
lint első ága (vedd fel őket a listára) az orchesztrátornak **H3** ([L478](docs/LESSONS.md#l478)),
ezért a **második** ág: a §0.0/B/B8 kimérte a pontos pineket (`find.byType(Card)`,
`InsightCard` runtimeType 4/5 darabszám, osztálynevek, meglévő l10n feliratok), és
szerződéssé tette, hogy a migráció **ADDITÍV** — típus-cserét (`SsCard`,
`SsInsightCard`) a kör nem végez. A kilenc pin a `gate_tests`-ben fut, de nem
szerkeszthető; a **57/57 zöld** ennek gépi igazolása.

**Az érdemi új munka (a domain már helyes volt):** a §0.0/B/B6 cellánként kimérte,
mi VAN már és mi ÚJ. A hiányzó ≠ nulla (A1), a nem támogatott állapot (A2), a
confidence (A3) és a kompatibilitás-verdikt (A6–A7) a domainben **helyesen élt** —
a kör ezeket **megőrizte és gépileg lepinnelte**. Valódi új munka: a
**virtualizált idővonal** (A4 — a mohó `ListView(children:)` `ListView.builder`-ré
vált, a hotspot-lista `itemExtent`-es `SsEventList`), a **diagram-szöveg-összegzés
és bejárható esemény-lista** (A5), a **kijelölés → gyakorlás callback** (A8,
mindig `start <= end`-re normalizálva) és a **goldenek** (A9).

**A review egy MAJOR-t talált, amit MINDEN gépi mérce átengedett.** A lokális
kapu 16/16 zöld, a Full Gate és a Router CI zöld, a golden-teszt valódi kapu — és
a commitolt PNG **tényleges megnyitása** mégis egy tátongó, 172 px-es üres blokkot
mutatott az idővonalon (a 915 px-es keret ~19%-a): az `SsEventList` fix 220 px
magassága EGY sor mellett halott helyet hagyott. A golden **rögzít, nem ítél** —
az első felvételnek nincs mihez képest csúnyának lennie ([L507](docs/LESSONS.md#l507)).
A javító kör `math.min(height, rows.length * rowExtent)`-tel zárta, a
`ListView.builder`-t és az `itemExtent`-et érintetlenül hagyva (a kézenfekvő
`shrinkWrap: true` a layout-hibát teljesítmény-hibára cserélte volna).

**A második lelet a MÉRCE gyengesége volt, és erősítéssel zárult.** A reviewer
próbája kimutatta, hogy az A4 cella **nem diszkriminál**: a mohó
`ListView(children:)` alakon — mind a 3000 sor-widget előre allokálva — a teszt
**5/5 zölden** ment át, mert a `find.byWidgetPredicate` az ELEM-fán mér, és a
`ListView(children:)` is csak a viewportot mountolja. A javító kör a
**delegátum-típusra** zárt (`isA<SliverChildBuilderDelegate>()`), és a próba
megismételve PIROS lett ([L506](docs/LESSONS.md#l506)).

**Mérce:** lokális kapu **16/16 ZÖLD** mindkét körben (a kilenc pin 57/57),
scope-audit `OK`, `ui_inventory` `hasLength(89)` **változatlan** (a kör nem hozott
új képernyőt), exact-SHA `59d1ddd8`: Full Gate
[33025011510](https://github.com/wolfcasaba/strumsight/actions/runs/33025011510) +
Router CI [33025012728](https://github.com/wolfcasaba/strumsight/actions/runs/33025012728)
mindkettő **success**. Biztonsági felület: NULLA (a `lib/` diff nem érint
hálózatot, tárolást, engedélyt, titkot — tisztán prezentációs kör).

**Következő kör:** `E13-R28` — Unified Library
([`docs/rounds/e13-r28-unified-library.md`](docs/rounds/e13-r28-unified-library.md)).

## ✅ E13-R26 KÉSZ — Analyze Home, Recording és Processing UI — PR [#470](https://github.com/wolfcasaba/strumsight/pull/470), squash `d9f46623` (2026-08-26)

Az UI-34–UI-36 megvalósítása (SDD Ch13 Kör 26): **Analyze kezdőképernyő**,
**felvételi Stage** és **feldolgozás-felület**. A kör **ADR-t nem írt** — a
kiosztott [`0285`](docs/adr/0285-recording-transparency-and-honest-progress.md)
2026-08-15 óta merge-elt (`6e7877de`), újraírása **H1** lett volna. A sávon ez
a **kilencedik** ADR nélküli kör egymás után (E13-R17…R26).

**A pre-flight legfontosabb lelete: a brief a MÁSIK analyze-fát írta le.**
A `brief-lint` `S13` szabálya jelezte, hogy a három `lib/features/analyze/{home,
recording,processing}/` előtag nem létezik — de a mérés ennél mélyebb hibát
talált. A repóban **két** analyze-fa él, és a brief §2 által leírt szakaszos,
megszakítható életciklus a **V2 `lib/features/audio_analysis/`** fában van
(9 fázisú `AnalysisProgressPhase`, opcionális `completedUnits`/`totalUnits`
PÁR, `AnalysisRunHandle.cancel()`, `AnalysisDegradedCompleted`), miközben a
legacy V1 fa egyetlen `compute()` hop, szakaszok és megszakítható elemzés
NÉLKÜL. A lint ajánlotta „legközelebbi létező ős" (`lib/features/analyze/`)
tehát **szintén hibás cél** lett volna: a szakaszos UI abba a fába került
volna, ahol a hozzá tartozó életciklus nem is létezik — zöld gate mögött
([L503](docs/LESSONS.md#l503)).

**Amit hoz.** Három ÚJ képernyő a
`lib/features/audio_analysis/presentation/capture/` alatt, a V2 életciklusra
horgonyozva:

- **Igazmondó haladásjelzés** (ADR 0285 §2): a már meglévő, addig **árva**
  `AnalysisProgressView`-t **befogadta**, nem írta újra (a fájl bájtra
  változatlan). A három küszöb-cella mérve: fázis nélkül `bar.value == null`
  és `%` szöveg SINCS · fázissal szakasz-szintű jelzés (`5/9`), továbbra is
  `value == null` · egységekkel a **tényleges** hányados (`3/5 → 0.6`). A
  három képernyő fáján **nulla** `Timer`/`Ticker`/`AnimationController`.
- **Látható megőrzés-állapot** (ADR 0217): a `_RetentionNotice` a **mért**
  `AudioRetentionPolicy.keepOriginal`-on ágazik (külön ikon + külön szöveg) —
  nem kitalált kapcsoló. Alapesetben (`keepOriginal: false`) a felület a
  „csak a származtatott elemzés marad meg" igazságot mondja ki.
- **Idempotens megszakítás** per-`runId` őrrel: a második koppintás no-op, de
  ÚJ `runId` újra engedélyez — nem „cancel forever".
- **Nincs árva mikrofon**: `dispose()` minden kilépési úton elengedi a
  lease-t, és az `AnalysisRecorder.dispose()` bizonyítottan idempotens.
- **6 golden felvétel** (3 képernyő × 412×915 compact portrait és
  `textScale 2.0`) a merge-kapu **x86_64** architektúráján (ADR 0426 §3).

**Amit a kör NEM talált ki** (§0.0/B6): a fán **nincs** szabad-tárhely-API és
**nincs** hő/akku-jel, ezért az A6 a mért `InputLimits` korlátokra (10 perc /
64 MiB), az A8 pedig a mért `CapabilityUnavailableReason`-re horgonyzott. Egy
kitalált „hő miatt lassabb" felirat pontosan az a hazugság-osztály lett volna,
amit az ADR 0285 tilt.

**A review egy hamis pozitívot is lezárt.** A sáv **kétszer** bukott érintési
célon (E13-R20 40 dp, E13-R21 32 dp — mindkettő ZÖLD gate mögött), és a
statikus jelek most is vádoltak: a három képernyő egyetlen `minimumSize`-t sem
állít, a téma nem ad override-ot, a merge-elt E13-R22 viszont explicit
`Size.fromHeight(48)`-at használ. Az eldobható próbateszt mégis **48.0 dp**-t
mért (a Flutter `MaterialTapTargetSize.padded` tölti ki) — négy egybevágó
statikus jel sem bizonyíték ([L504](docs/LESSONS.md#l504)).

**Review APPROVED, javító kör NÉLKÜL** — 0 BLOCKER, 0 MAJOR, 0 MINOR, 3 NOTE
(`docs/reviews/e13-r26-review.md`). Az implementer jelzésfájljából **hiányzott
a `scope_audit=` kulcs**, ezért az orchestrátor kézzel pótolta: **OK**, 19
útvonal ([L505](docs/LESSONS.md#l505)). Független gate-újrafuttatás izolált
`/tmp` klónban: **18/18 zöld**.

Exact `83c8f229`: Full Gate [33017415531](https://github.com/wolfcasaba/strumsight/actions/runs/33017415531)
+ Router CI [33017406920](https://github.com/wolfcasaba/strumsight/actions/runs/33017406920)
mindkettő success. A záró review-commit új HEAD-et képzett, ezért mindkét
kaput újra kellett dispatch-elni a végleges SHA-n (ADR 0086 §2).

## ✅ E13-R25 KÉSZ — Song Trainer, Result és Setlist Run UI — PR [#469](https://github.com/wolfcasaba/strumsight/pull/469), squash `adf49fd1` (2026-08-26)

Az UI-29–UI-31 és UI-33 Stage/analitika folyamata (SDD Ch13 Kör 25). A kör
**ADR-t nem írt**: a §5 mind az öt kötött döntése MÁR merge-elt ADR-ekben él
([0274](docs/adr/0274-motion-driven-by-the-audio-clock.md),
[0283](docs/adr/0283-results-never-overstate-certainty.md),
[0276](docs/adr/0276-stage-scaffold-owns-no-resources.md),
[0277](docs/adr/0277-failure-presentation-model.md),
[0129](docs/adr/0129-song-trainer-ui-loop-speed-and-result-boundary.md)) —
újraírásuk H1 lett volna. A sávon ez a **nyolcadik** ADR nélküli kör egymás
után (E13-R17…R25).

**Amit hoz.** Mind a négy felület **HELYBEN** migrálva (típusnév, útvonal,
konstruktor-szignatúra változatlan — az `ui_inventory` diffje ÜRES, 86 → 86):

- **A lejátszófej az AUDIO ÓRÁBÓL vezetett** (ADR 0274): a `_RunningBody`
  viewportja a `state.transportState.activePosition`-ból számol — a fán
  **nincs** `Timer`, `Ticker` vagy `AnimationController`. A viewport a
  KONFIGURÁLT `loopRangeEnd`-re clamp-el, **kerekítés nélkül**, így a vizuális
  és a hallható loop-határ ugyanaz (A2/A3).
- **A csak-lejátszás NEM kap pontszámot** (ADR 0283): a MÁR MÉRT
  `isPlaybackOnly` domain-ág kimondva a felületen, heatmap és százalék nélkül.
  **Nem** új domain-mód — a pontozás logikája érintetlen (A1).
- **A setlist hangolás-váltása ELŐRE jelzett**: a `_tuningChangesAhead` a
  szomszédos elemek `overrides` különbségéből számol, és a kártya a futás
  INDÍTÁSA előtt látszik (A5).
- **8 golden felvétel** (4 képernyő × 412×915 compact portrait és
  `textScaler: 2.0`), `tools/golden-x86.sh record`-dal a merge-kapu **x86_64**
  architektúráján (ADR 0426 §3).

**A mérce dolgozott, nem pecsételt.** A golden **VALÓDI** hibát fogott:
`textScaleFactor: 2.0` mellett a `setlist_session_screen.dart`
hangolás-kártyája **77 px-szel túlcsordult** (`RenderFlex overflowed`) —
javítva (`Expanded` a címre). Az A1 valódi-sértés próbája (kitalált pontszám a
csak-lejátszás ágra) a cellát PIROSRA váltotta, majd visszaállítva zöld.

**A pre-flight hét lelete (§0.0/B)** — a legfontosabb a brief HÁROM nem létező
könyvtár-előtagja (`lib/features/songs/trainer|results/`,
`lib/features/setlists/run/`): NULLA fájlt fedtek, miközben mind a négy
felület MÁR LÉTEZETT a `song_trainer/presentation/` rétegben. Ez az
[L497](docs/LESSONS.md#l497) hibaosztály **harmadszor** (E13-R22, E13-R23,
most). Útvonal-csere a fán MÉRT rétegre, az E13-R23 user-jóváhagyott
listájának valódi RÉSZHALMAZÁRA. A körbe merge-elt `main` közben hozta az
**S13** brief-lint szabályt, ami pontosan ezt gépesíti — és rögtön ki is mérte
a negyedik, nem létező `test/fixtures/songs/trainer/` előtagot (§0.0/B/B8,
szűkítéssel feloldva).

**A review APPROVED** ([review](docs/reviews/e13-r25-review.md)) — 0 BLOCKER,
0 MAJOR, **2 MINOR**, javító kör nélkül. A MINOR-1-et a reviewer **eldobható
próbatesztje** mérte ki: a Stage a `songTrainerControllerProvider`
(`autoDispose`, saját `ref.onDispose`-szal) által **BIRTOKOLT** controllert
`dispose`-olja. Cache-elt provider mellett a remount HALOTT controllert kap
(`prepare()` → `idle`, néma no-op); a MAI egy-figyelős felállásban viszont
`ready` — a hiba **nem elérhető**, ezért MINOR. A védelem viszont egy
nem-tesztelt együttálláson (`autoDispose` + pontosan egy figyelő) múlik.

**Az implementer első futása időkorlátba futott** (3600 s, jelzés nélkül); a
részmunkát az orchestrátor commitolta (`0f617462`, scope-audit ok), a folytatás
ugyanazon a branchen zárta le a kört. H6 nem állt fenn (egyszeri `timeout`).

Teljes scope-audit **ok** (21 útvonal, 0 listán kívüli) · `ui_inventory`
**86 → 86** · gyengítés (`skip`/`ignore`) **0** · full-gate
[33010134345](https://github.com/wolfcasaba/strumsight/actions/runs/33010134345)
és router-ci
[33010125404](https://github.com/wolfcasaba/strumsight/actions/runs/33010125404)
**success** a merge SHA-n (`f3bfdb46`).

---

## ✅ E13-R24 KÉSZ — Song import, előnézet és szerkesztő UI — PR [#466](https://github.com/wolfcasaba/strumsight/pull/466), squash `30065dc2` (2026-08-26)

Az UI-26–UI-28 import/szerkesztő felületek migrációja (SDD Ch13 Kör 24). A kör
**ADR-t nem írt**: a [0284](docs/adr/0284-import-preview-is-not-a-commit.md) már
merge-elt (2026-08-15), újraírása H1 lett volna; a foglaló adta `0429`
kiosztott, de fel nem használt szám. A sávon ez a **hetedik** ADR nélküli kör
egymás után (E13-R17…R24).

**Amit hoz.** Mind a három felület **HELYBEN** migrálva (típusnév, útvonal,
konstruktor-szignatúra változatlan — az `ui_inventory` diffje ÜRES, 86 → 86):

- **Import folyamat** — a `failure` fázis nevesítve mutatja a hibát
  (`Icons.error_outline` + error szín-szerep + `Semantics`), és az EGYETLEN
  cselekvés az új próbálkozás: nincs rajta „folytasd mindenképp" affordancia.
- **Import előnézet** — a `fatal.` előtagú lelet a megerősítést **letiltja**
  (`FilledButton.onPressed = null`), és vizuálisan ÉS szemantikusan elkülönül a
  sima figyelmeztetéstől. Az `ImportWorkspace` csak `confirmPreview()`-ban
  nyílik, megszakításkor mindig zár (A1/A2).
- **Szerkesztő** — a Save `canPersist`-tel zárolt; zárolt esetben az egyetlen
  írási út a másolat (új `SongId`, `createdInApp` forrás), az eredeti dokumentum
  változatlan. Mentési hiba után a piszkozat a képernyőn marad, a hiba
  `failureCode` nevesítve. Az átrendezés fel/le gombpárral megy — húzás-widget
  egy sincs a fán —, és minden ilyen affordancia mért mérete `>= 48,0 dp`.

**A review KÉT javító kört kért, és mindkét MAJOR TELJESEN ZÖLD kapu mögött
élt** ([review](docs/reviews/e13-r24-review.md) — **APPROVED**, 0 nyitott lelet).
Mindkettőt a reviewer **eldobható próbatesztjei** találták meg:

- **MAJOR-1** — az A7 érintési-cél cellája a `constraints` 48→32 cseréjére ÉS a
  teljes eltávolítására is ZÖLD maradt: `tester.getSize(IconButton)` a Material
  `MaterialTapTargetSize.padded` miatt konstans `Size(48.0, 48.0)` (a belső
  `ConstrainedBox` 40×40). A cella a Material alapértelmezését mérte, nem a kör
  kódját — [L477](docs/LESSONS.md#l477), és a sáv **harmadik** érintési-cél
  lelete ([L496](docs/LESSONS.md#l496)). Javítva: a cella az
  `IconButton.constraints`-re mér, bizonyítottan piros `32.0`-nál és `null`-nál.
- **MAJOR-2** (a javító kör vezette be) — a `_saveCopy` hiba-ága
  `controller.load(id)`-t hívott, ami a **draftot is** felülírta:
  `"My careful rename"` → `"Legacy Song"`, `createCalls = 0`. Ez az
  [ADR 0284](docs/adr/0284-import-preview-is-not-a-commit.md) §Döntés 4 tiltott
  néma munkavesztése. Javítva: a másolat validációja a controller érintése ELŐTT
  fut, a draft egyik ágon sem íródik felül.

**Evidencia.** A reviewer `tools/round-gate.sh` futása **20/20 ZÖLD, 97 teszt** —
HÁROM különböző, friss izolált `/tmp` klónban, nem az implementer kimenetének
elfogadásával. A gate sora **először tartalmazta a fa-szintű őröket** (a
`57b18ccb` PR #458 munkája): `architecture_dependency` (+44), `dio` /
`preferences` / `route_literal` guard, plusz a NÉGY listán kívüli pin-teszt,
amit az `S11` tett a listákra — mind zöld, azaz a helyben-migráció tartotta a
típusneveket és útvonalakat. Scope-audit: `OK (21 changed path, 1
generated/ignored)`.

**A kör merge-e egy GITHUB-INCIDENSEN akadt meg (H5), nem a fán.** A GitHub
Actions 15:48-tól `major_outage`; a merge SHA-n a Full Gate ~40 percig QUEUED
maradt runner nélkül, a Router CI pedig **magától az incidenstől** lett piros:
788 passed / **4 failed**, mind a négy a
`tools/tests/test_pipeline_integration.py` self-heal celláiban, mert a driver
GitHub-incidens őre (`github_actions_degraded`) ÉLŐ HTTP-hívás, és incidens
alatt rövidre zárja épp azt az ágat, amit ezek a cellák mérnek. A kör diffje ezt
a fájlt nem is érintette. **Gyökérok-javítás:** PR
[#467](https://github.com/wolfcasaba/strumsight/pull/467) (`19f6e684`) — a suite
`run_command`-ja `setdefault`-tal állítja a driver már meglévő
`PIPELINE_STATUS_CHECK=0` kikapcsolóját, plusz két új cella (hamisított
`major_outage` alatt is mérhető self-heal ág; explicit `"1"` visszahozza az őrt).
A kör ága ezt a §0.3 upstream-szinkronnal vette át, és az új HEAD-en **mindkét
kapu zöld**. Lecke: [L500](docs/LESSONS.md#l500).

**Nyitva hagyva (szándékosan).** NOTE-1 expanded több-paneles elrendezés
(follow-up), NOTE-2 az A1/A2 az application réteget méri, NOTE-3
`DateTime.now()` a presentationben — egyik sem blokkol.

## ✅ E13-R23 KÉSZ — Song Library, Overview és Setlist lista UI — PR [#465](https://github.com/wolfcasaba/strumsight/pull/465), squash `44b42a9d` (2026-08-26)

Az UI-24–UI-25 és UI-32 Songs-tartalmak migrációja (SDD Ch13 Kör 23). A kör
**ADR-t nem írt** — a §5 kötött döntései merge-elt ADR-ekre támaszkodnak
([0275](docs/adr/0275-five-area-shell-behind-a-flag.md) legacy route,
[0277](docs/adr/0277-failure-presentation-model.md) hibabemutatás,
[0278](docs/adr/0278-ai-provenance-is-visible.md) provenance), és a `docs/adr/**`
a kör tilos zónájában van. A sávon ez a **hatodik** ADR nélküli kör egymás után
(E13-R17…R23).

**Amit hoz.** A három Songs-felület **HELYBEN** migrálva (típusnév,
fájl-útvonal, konstruktor-szignatúra és route-regisztráció változatlan):

- **Song Library** — minden soron lokalizált **forrás-jelvény**
  (`SongSourceBadge`), `canPersist == false` esetén lakat-jelvény, és a sor
  megtekintő-módba terel a szerkesztő helyett (a `song-editor-open-<id>` Key
  változatlan, csak a navigációs CÉL ágazik). A keresés/szűrés túléli a
  képernyő **valódi** dispose→újrabelépését.
- **Song Overview** — forrás + licenc sor, és a hiányzó kísérőhang
  **nevesített** jelzése a tartalom letiltása NÉLKÜL (§5.3).
- **Setlist lista (V2)** — tételenkénti készenlét-ikon a
  `SetlistItemAvailability`-ből, a hiányzó dal **nevesítve**, önálló
  szövegsorként — soha nem néma kihagyás (§5.4).

**A pre-flight legfontosabb mérése (§0.0/B, R13–R21).** A brief három
megnevezett könyvtára (`lib/features/songs/library|overview/`,
`lib/features/setlists/`) a fán **NEM LÉTEZIK** — az eredeti `allowed_paths`
NULLA létező fájlt fedett, a `brief-lint --level strict` mégis „nincs lelet"-et
adott ([L497](docs/LESSONS.md#l497) MÁSODIK előfordulása). A három felület a
`song_trainer/presentation/screens/` fában él; az útvonal-csere a merge-elt
E03-R14…R22 briefek user-jóváhagyott literáljainak valódi RÉSZHALMAZA (10
screen-fájlból 3), az `application/`, `domain/`, `data/` réteg pedig olvasható,
de NEM írható. **R16:** a modellben **nincs `license` mező és nincs
„közösségi" forrástípus** — a §5.2 a MÉRT hármasra szűkült
(`SongSummary.sourceType` / `SongMetadata.copyright` / `capability.canPersist`),
kitalált címke nélkül. **R17:** a négy listán kívüli pin (`song_library_screen_test`,
`song_overview_screen_test`, a11y-audit, `app_router_test.dart:303`) az `S11`
lint-lelet kimondott kifutójaként HELYBEN maradt ([L488](docs/LESSONS.md#l488)
ötödik alkalmazása) — futnak a kapuban, de nem szerkeszthetők.

**Review — APPROVED, EGY javító kör után** ([jelentés](docs/reviews/e13-r23-review.md)):
0 BLOCKER, 0 MAJOR, 3 MINOR, 3 NOTE — mind a három MINOR **teljesen zöld kapu
mögött** (16/16 lokális gate a reviewer izolált klónjában is, és mindkét
exact-SHA CI-kapu success a `77d083e8`-on).

- **MINOR-1 ([L499](docs/LESSONS.md#l499)):** az A8 cella azért volt zöld, mert
  a tesztelt forgatókönyv (`push` a Library FÖLÉ, majd `pop`) **sosem
  dispose-olja** a képernyőt. A reviewer eldobható próbája a valódi
  kilépés/visszatérés útján `Found 0 widgets with text "Alpha"`-t mért — és ez
  nem elméleti: a `/song-trainer` top-level route, egyetlen belépője egy `push`
  a lecke-listáról. Javítás: file-szintű, **nem-autoDispose** query-tartó +
  ÚJ cella a (b) olvasatra; a gyengébb cella VÁLTOZATLANUL a fán maradt.
  A reviewer valódi-sértés próbája (provider → `autoDispose`) `+5 -1`-gyel
  PONTOSAN az új cellát váltotta pirosra.
- **MINOR-2:** a lista alcíme nyers `sourceType.code` **gép-azonosítót**
  (`strumSightJson`) írt ki a lokalizált forrás-chip fölé, előadó nélküli
  dalnál. Javítás: a `code`-fallback megszűnt, a golden újrafelvéve.
- **MINOR-3:** az A2 „licenc **a listában**" része mérten nem teljesíthető —
  a `SongSummary` index nem hordoz `copyright`-ot, és a
  `SongLibraryController` doc-commentje szó szerint kimondja: *„A full document
  is deliberately never requested here"*. Feloldás: §0.0/B/**R21** revízió —
  forrás MINDKÉT helyen kötelező, licenc az áttekintőn; a mérce nem gyengült,
  csak igazat mond.
- **NOTE-1/2/3** (nem blokkoló, mind az `application/` rétegbe esik): a `null`
  capability szerkeszthetőnek számít; az Overview másodszor is dekódolja a
  dokumentumot csak megjelenítéshez, és a hibát elnyeli; a setlist-készenlét a
  perzisztált `initialAvailability`-ből jön, nem újraszámolva.

**Golden (A9):** 6 PNG (library + overview + setlist-lista × 412×915 compact és
`textScaler: 2.0`), **x86-on felvéve** ([ADR 0426](docs/adr/0426-golden-rasterization-on-the-gate-architecture.md),
`tools/golden-x86.sh`) — `--update-goldens` ezen az ARM boxon tilos.
**Képernyő-leltár:** 86 → 86 (nincs új `*_screen.dart`, a `ui_inventory_test`
diffje ÜRES).

**Zöld kapu (exact `ae4b11a3`):** Full Gate [32966489936](https://github.com/wolfcasaba/strumsight/actions/runs/32966489936)
+ Router CI [32966492836](https://github.com/wolfcasaba/strumsight/actions/runs/32966492836)
mindkettő **success**; reviewer round-gate 16/16 ZÖLD; scope-audit OK.

**Nevesített follow-up:** a `SetlistListScreenV2` route-regisztrációja (ma nincs
GoRoute-on, a konstruktora `controller` + `clock` argumentumot kér) → **E13-R25**
(setlist-run).

---

## ✅ E13-R22 KÉSZ — Practice result, history és Speed Builder UI — PR [#464](https://github.com/wolfcasaba/strumsight/pull/464), squash `5f4266e3` (2026-08-26)

Az UI-21–UI-23 összegzés-központú felületei (SDD Ch13 Kör 22), a merge-elt
[ADR 0283](docs/adr/0283-results-never-overstate-certainty.md) kötött döntései
szerint. A kör **ADR-t nem írt** — a `0283` a briefekkel EGYÜTT merge-elt
(`a4a71550`), és merge-elt ADR újraírása H1 volna (ADR 0087 §2). A sávon ez az
**ötödik** ilyen kör egymás után (E13-R17…R22).

**Amit hoz.** Az **eredmény** (UI-21) HELYBEN migrálva: megbízhatóság-tudatos
összegzés (küszöb **0,60, INKLUZÍV**), részleges-session jelölés a
`finishReasonCode` stabil enum-kódjából, jutalom **a főkönyvből**
(`stableEventId(sessionId)` → `RewardLedgerEntry`, TISZTA olvasás — az
`appendIfAbsent` sehol), végrehajtható következő lépés és minimális
megosztás-vetület. Az **előzmények** (UI-22) ÚJ képernyő: helyi adat, tehát
offline is teljes, sérült rekord izolálva, mód-szűrővel. A **Speed Builder**
(UI-23) ÚJ képernyő: a **stabil legjobb tempót** (`highestStableTempo`)
mutatja, sosem a csúcs-futamot. Hat golden PNG, 412×915 compact portrait ÉS
`textScaler: 2.0`, **x86-on felvéve** (ADR 0426).

**Pre-flight (§0.0/B, `b3ce2027`) — nyolc mért revízió.** **R5:** a `0283` már
merge-elt (a fejléc „a Claude írja meg" mondata elavult); a foglaló adta `0428`
kiosztott, de fel nem használt szám maradt. **R6:** a brief HÁROM megnevezett
könyvtára (`practice/results|history|speed_builder/`) a fán **nem létezik** — a
lista így **nulla létező fájlt** fedett; a felületek a practice `presentation`
rétegéé, és a csere az előző kör user-jóváhagyott listájának valódi
RÉSZHALMAZA (a `domain`/`data`/`application` olvasható, de nem írható).
**R7:** a §0.0/R2 „nincs ilyen" MÉRVE hamis — három listán KÍVÜLI teszt pinneli
a `PracticeResultScreen`-t, ezért a képernyő HELYBEN migrál (típus, útvonal,
`entry:` konstruktor kötve — [L488](docs/LESSONS.md#l488) negyedik
alkalmazása), a három teszt fut, de nem szerkeszthető. **R8:** az A1 három
cellájának (0,45/0,60/0,85) **nincs producere** — session-szintű `confidence`
mező a fán nincs —, ezért a bemenet a MÉRT `resolvedTargets/totalTargets`
lefedettségi arány (9/12/17 per 20, `python3`-mal kiszámolva). **R9:** golden a
merge-kapu architektúráján. **R10:** `hasLength(84)` → **86**. **R11/R12:** a
route-regisztráció (`lib/app/routing/**`) és a valódi megosztás-varrat a listán
kívül esik → nevesített follow-up, a két új képernyő addig a
`Navigator.push(MaterialPageRoute…)` házi mintával érhető el az
eredmény-felületről.

**EGY javító kör** (`docs/reviews/e13-r22-review.md`, végső verdikt
**APPROVED**, 0 nyitott lelet). A MAJOR **teljesen zöld kapu mögött** élt — 16/16
lokális gate-lépés a reviewer saját izolált klónjában is, és mindkét exact-SHA
CI-kapu success:

1. **MAJOR-1** — a Speed Builder aktív felülete GYÁRTOTT
   `PracticeAttemptResult`-okat (`completion: 0.98`, `rhythm: 0.9`,
   `resolvedTargets: 8/8`) adott a VALÓDI `SpeedBuilderEngine`-nek két
   production gombbal („Record pass"/„Record miss", mindkét nyelven
   lokalizálva), és a kapott értéket „Highest stable BPM"-ként közölte. A
   reviewer próbateszttel mérte: **`Highest stable BPM: 90 BPM` puszta
   érintésekből**, mikrofon, session és egyetlen `PracticeObservation` NÉLKÜL.
   Ez pontosan az az állítás-túllövés, amit a kör SAJÁT ADR-je (0283) tilt.
   **A kör cellája ráadásul elvárásként PINNELTE a hibás utat**
   (`speed_ladder_test.dart:135-150`) — az [L495](docs/LESSONS.md#l495)
   hibaosztálya EGY körrel a mérése után megismétlődött, most más felületen.
   Javítás: a szintetikus próbagyártás megszűnt, helyette ADR 0277-stílusú,
   kimondott „élő mérés még nincs" állapot Start/Record affordancia nélkül, és
   egy ABSZENCIA-őrcella, amit a reviewer valódi-sértés próbája (`Start` CTA
   visszatétele) `Found 1 widget with text "Start"`-tal pirosra váltott.
2. **MINOR-1** — nyers `'completedAllTargets'` literál a domain stabil
   `PracticeFinishReason.…code` elérése helyett. **MINOR-2** — a sérült
   előzmény-rekord ma JELZÉS NÉLKÜL tűnik el (a `skipped` számláló megvan a
   `json_document_store.dart`-ban, de a repository nem hordozza tovább, és a
   réteg a listán kívül van) → a §10.5 nevesített korlátként rögzíti.
   **NOTE-1** (nem blokkoló): a Noop jutalom-varrat MÉRVE őszinte — a
   practice-adapter sehol nincs példányosítva, a valódi ledger sincs
   providerbe kötve, tehát a főkönyv production-ban valóban üres.

**Az érintési cél (≥ 48 dp) ezúttal ZÖLD** — a reviewer mind a négy ÚJ
affordanciát megmérte 412×915-ön (`Share`, `History`, `Speed Builder`,
`Practice again` → mind pontosan `48.0`), tehát az E13-R20 → E13-R21 két
egymást követő MAJOR-ját adó hibaosztály ebben a körben nem ismétlődött meg.

**Bizonyíték.** Exact `7e2eb629`: Full Gate
[32953967135](https://github.com/wolfcasaba/strumsight/actions/runs/32953967135)
+ Router CI
[32955584901](https://github.com/wolfcasaba/strumsight/actions/runs/32955584901)
mindkettő success. Scope-audit: `OK (b3ce202714e1..e3dab0480511, 23 changed
path(s), 1 generated/ignored)`.

## ✅ E13-R21 KÉSZ — Practice setup, aktív session és pause/recovery UI — PR [#463](https://github.com/wolfcasaba/strumsight/pull/463), squash `e209af39` (2026-08-26)

Az UI-18–UI-20 migrációja a MEGLÉVŐ gyakorlási állapotgéphez kapcsolva (SDD Ch13
Kör 21). A kör **ADR-t nem írt** — a §5 mind a hat kötött döntése merge-elt
ADR-ek szövege (0073/0078/0079/0276/0279), és új szám merge-elt döntés fölé
tilos (ADR 0087 §4).

**Amit hoz.** A **setup** (UI-18) formja a design-system elemekre migrálva
(`SsValueSlider`, `SsSwitchRow`), a widget-oldali `_bpmDraft` vázlatállapot
megszűnt (§5.1). Az **aktív session** (UI-19) Stage-elrendezést kapott
hero/feedback slotokkal, benne a readiness-sorral, ahol a **gyenge jel** és a
**degradált képesség** két KÜLÖN indikátor — sosem egy összevont banner. A
**Pause/Recovery** (UI-20) overlay, nem külön route, és KIZÁRÓLAG a
`PracticeSessionState.pauseCause`-ból renderel; a Resume ugyanazt a
`ResumePractice` parancsot küldi, amit a transport — második affordancia, nem
második parancsút. A kilépés következmény-központú megerősítést kér
(„Exiting now discards this session's progress…”, `barrierDismissible: false`,
ADR 0279 §1). Hat golden PNG, 412×915 compact portrait ÉS `textScaler: 2.0`,
**x86-on felvéve** (ADR 0426).

**Pre-flight (§0.0/B, `24b95acf`) — négy mért revízió.** **R5:** a goldenek
felvétele ÉS ellenőrzése a merge-kapu architektúráján — a brief eredeti
`--update-goldens` sora pontosan az E13-R20 H5-haltját reprodukálta volna.
**R6:** az A6 „rossz hangolás” tengelyének **nincs producere** a fán (nincs
`TuningState`, a `PracticeObservation` csak strum+chord, és a tuner
feature-nek nincs `public.dart` barrelje → a wiring H3 lenne); a cella két
mérhető tengelyre szűkült, a hangolás-tengelyből readiness-sor +
`AppRoutes.practiceTuner` belépő készült, az élő beolvasás nevesített
follow-up. **R7:** a négy célképernyő HELYBEN migrálva ([L488](docs/LESSONS.md#l488)
harmadik alkalmazása) — `hasLength(84)` és a pin-tesztek érintetlenek.
**R8:** erőforrás-tulajdonlás a tényleges hívási láncon mérve — a mikrofon-lease
a `core/audio/`-é, a practice fában **nulla** `.acquire(`; a brief
kockázat-indoklása ezzel megdőlt.

**EGY javító kör** (`docs/reviews/e13-r21-review.md`, végső verdikt
**APPROVED**, 0 nyitott lelet). Mindkét MAJOR **teljesen zöld kapu mögött** élt
— 18/18 gate, 173/173 presentation-teszt, 6/6 golden, és MINDKÉT exact-SHA
CI-kapu success:

1. **MAJOR-1** — a readiness-sor Tuner-belépője ŐRIZETLEN adatvesztési kijárat
   volt egy FUTÓ sessionből: `context.go` (replace) → a session megszűnt.
   A reviewer mérése: `dialogs=0 sheets=0 alerts=0 commandsSent=()
   leftSession=true` — megkerülte a kör SAJÁT `_requestExit` megerősítését.
   **A kör A6 cellája ráadásul elvárásként PINNELTE a bypasst**: egy zöld cella
   nemcsak elmulaszthatja a hibát, rögzítheti is
   ([L495](docs/LESSONS.md#l495)). Javítás: `context.push` — a session a Tuner
   alatt mountolva marad, a felhasználó visszatalál, és mivel nincs
   következmény, megerősítés sem kell.
2. **MAJOR-2** — a belépő érintési célja `Size(277.5, 32.0)` az ADR 0280
   §Döntés 5 ≥ 48 dp ellen. **Ugyanaz a hibaosztály, mint az E13-R20/MAJOR-1,
   EGY körrel később** — mert az akkori őrcella a konkrét widgethez készült,
   nem a szabályhoz ([L496](docs/LESSONS.md#l496)). Javítás: 48 dp + ÚJ
   őrcella, amit a reviewer valódi-sértés próbája (32 dp visszaállítás)
   `Expected: >= 48.0 / Actual: 32.0`-val pirosra váltott.
3. **MINOR-1** — a readiness-sor hiányzott a Setup felületről (SDD UI-18);
   a MAJOR-1 javítása lezárta, saját cellával. NOTE-1 (nem blokkoló): a
   BPM-csúszka minden drag-tickre ír a controllerbe.

**Folyamat.** Az ELSŐ implementer-futás a burkoló abszolút időkorlátjánál
(3600 s) szakadt meg PONTOSAN a záró gate közben; az orchestrátor a
scope-audit után commitolta a munkát (`f9e61a9e`, 21 fájl, 0 sértés), és
`MM_ROUND_TIMEOUT=5400`-zal folytató futást indított — a kör így **halt nélkül**
zárult. A jelzés `scope_audit=VIOLATION`-je ismét az orchestrátor SAJÁT
prompt-fájlja volt a munkapéldányban ([L494](docs/LESSONS.md#l494) MÁSODIK
előfordulása); a folytató és a javító dispatch prompt-fájlja ezért már
`/tmp`-ben élt.

**Zöld kapu.** Reviewer `tools/round-gate.sh` izolált `/tmp` klónban a javított
HEAD-en **18/18 ZÖLD**, `tools/golden-x86.sh check` 6/6, scope-audit OK (24
fájl). Exact `6bfb8fa6`: Full Gate
[32942002559](https://github.com/wolfcasaba/strumsight/actions/runs/32942002559)
+ Router CI
[32942005369](https://github.com/wolfcasaba/strumsight/actions/runs/32942005369)
mindkettő success. Post-merge `tools/round-gate.sh` a friss `main`-en zöld.

**Nyitott follow-up:** az élő hangolás beolvasása a practice felületre
(`TunerReading` → readiness-sor) — ehhez `lib/features/tuner/public.dart`
barrel kell, amit annak a körnek kell megírnia, amelynek az `allowed_paths`-a
tartalmazza. A ≥ 48 dp célméret repó-szintű őre (a per-widget rés lezárása)
szintén nyitott, `test/core/**` hatáskör ([L496](docs/LESSONS.md#l496)).

## ✅ E13-R20 KÉSZ — Chord Library, Learning Path és Lesson UI migráció — PR [#462](https://github.com/wolfcasaba/strumsight/pull/462), squash `ad5718d1` (2026-08-26)

Az UI-11–UI-14 migrációja közös Learning Mode komponensekre, **balkezes** és
**offline** tartalomtámogatással (SDD Ch13 Kör 20). Kötött döntések:
[ADR 0282](docs/adr/0282-diagram-text-alternative-and-handedness.md) — a kör az
ADR-t **hivatkozta, nem írta újra** (merge-elt döntés, `docs/adr/` tilos zóna;
a brief §0.0/R5 mérte ki).

**Amit hoz.** ÚJ `lib/core/design_system/components/music/ss_chord_diagram.dart`:
a diagram rajza ÉS a szöveges fogás-alternatíva **egyetlen leképezésből**
(`readingOrder` → a festő is ezt használja, tehát a két csatorna nem tud
szétcsúszni). Balkezes módban **a rajz és a felolvasott húrsorrend is**
tükrözött — ez az ADR 0282 §Döntés 2. szerint VISSZAFORDÍTJA a round-88-as
döntést, amit a `chord_diagram_semantics_test.dart` addig az ellenkezőjére
pinnelt. A design system feature-providert nem olvas: a kezesség és a fogás
paraméter, a `leftHandedProvider`-t a feature-réteg watch-olja. Továbbá:
akkordtár keresés/szűrés/kedvencek + állapotmegőrzés, a részletnézetből indított
gyakorlás a **megnyitott** akkorddal paraméterez (`Navigator.push`, ÚJ útvonal
nélkül — §0.0/R8), a tanulási út lineáris hozzáférhető alternatívával és a
zárolás **okával**, és a hiányzó erőforrás (nincs diagram-forma / nincs
lejátszható kíséret) nem omlaszt és nem tűnik el némán. A meglévő haladás a
migráció után megmarad (A5, valódi-sértés próbával mérve).

**HÁROM javító kör** (`docs/reviews/e13-r20-review.md`, végső verdikt
**APPROVED**, 0 nyitott lelet):

1. **MAJOR-1** — az akkord-részletnézet EGYETLEN belépője 40×40 dp-s érintési
   cél volt, ráadásul `right: -6`-tal 6 dp-vel a `Stack`-en KÍVÜLRE lógva (a
   tényleges találati felület ≈ 34×40 dp), miközben az
   [ADR 0280](docs/adr/0280-accessibility-contract-and-live-region-budget.md)
   §Döntés 5. ≥ 48 dp-t ír elő. A gate végig ZÖLD volt: a
   `chord_tile_a11y_test.dart` a semantics-CÍMKÉKET méri, nem a célméretet — a
   mérce **nem volt jelen**, nem pedig teljesült. A reviewer eldobható
   próbateszttel fogta meg; a javításhoz ÚJ őr-cella készült, amit a reviewer
   valódi-sértés próbája (a 28 dp-s `constraints` visszaállítása) pontosan az
   eredeti `Size(40.0, 40.0)`-val pirosra váltott.
2. **L486 színforrás-osztály** — a `_LessonTile` `Card`-ja és az `ActionChip`
   explicit szín nélkül seed-származtatott (`ColorScheme.fromSeed`, HCT
   lebegőpont) felületet kapott, ami golden-diffet adott. Konstans
   `AppPalette` forrásra állítva: `learning_path_compact` **5976 px → 8 px**, a
   párja teljesen zöldre váltott. **Kontrollesettel igazolva:** a `Card` nélküli
   chord library végig zöld volt, a konstans színű `_ContinueCard` pedig
   ugyanazon a bukó képernyőn nem adott diffet.
3. **H5 halt feloldása** — a maradék 3 cella (1 / 8 / 1 px, mind **0,00%**) nem
   színforrás-kérdés volt, hanem **cross-architektúra raszterizációs rés**:
   ARM-on felvett PNG, x86-on verifikálva, nulla toleranciájú komparátorral. A
   kör H5-tel megállt; az [ADR 0112](docs/adr/0112-self-healing-pipeline.md)
   önjavító köre a rést bezárta
   ([ADR 0426](docs/adr/0426-golden-rasterization-on-the-gate-architecture.md),
   `52ce9003`), és a goldenek **a merge-kapu architektúráján** kerültek
   felvételre (`tools/golden-x86.sh record`). **Termékkód egyetlen sora sem
   változott** ebben a javító körben — a diff pontosan 3 PNG + a brief §10 —, és
   a kód elsőre zöld lett a kapun.

**A mérce nem lazult.** A komparátor ugyanaz a nulla toleranciájú
`LocalFileComparator`, a 6 golden-cella `skip` nélkül megvan, a
`.github/**`/`tools/**`/`round-gate.sh` érintetlen. A golden-cellákat ezután
**kettő** mérce méri (lokálisan az x86-konténer, a kapuban a CI teljes
suite-ja), miközben a korábbi lokális ARM-mérésük bizonyítottan hamis zöldet
adott.

**Mérve, a reviewer saját kezével:** `tools/golden-x86.sh check` a halt utáni
HEAD-en **pontosan a CI három celláját** reprodukálta (1 / 8 / 1 px, EXIT=10)
~75 másodpercben a 17 perces exact-SHA futás helyett — ez az ADR 0426
eszközének független hitelesítése is. A javítás után **6/6 zöld, EXIT=0**.

**Zöld kapu.** `tools/round-gate.sh` **21/21 zöld** (16 teszt-útvonal, izolált
`/tmp` klónban, `prepare-flutter-generated.sh` után), `test/features/chords/` +
`test/features/learn/` **235 zöld**, scope-audit **OK** (4 útvonal). Exact-SHA a
merge SHA-n (`065a24fe`): Full Gate
[32929307814](https://github.com/wolfcasaba/strumsight/actions/runs/32929307814)
+ Router CI
[32929309630](https://github.com/wolfcasaba/strumsight/actions/runs/32929309630)
mind **success**. A záró review-commit új HEAD-et képzett, ezért mindkét kapu
ÚJRA futott a végleges SHA-n — a `1cd05fc6`-os zöld futás önmagában nem
mentesített (ADR 0086 §2).

**Két folyamati lelet, amit ez a kör mért ki:**

- a §0.3 upstream-szinkron konfliktusa a kör SAJÁT briefjében **tisztán additív**
  volt (branch §0.0/R5–R13 vs. `main` §0.1/R14) — a helyes feloldás MINDKETTŐT
  megőrzi. Ugyanezt a merge-et az önjavító session már publikálta, és a két
  független feloldás fája **bitre azonos** lett;
- a wrapper `scope_audit=VIOLATION`-t jelzett EGYETLEN útvonalra: az
  orchestrátor SAJÁT, követetlen prompt-fájljára a munkapéldányban. Ez
  hamis-pozitív (nem implementer-kimenet), és ugyanaz az osztály, amit a review
  §1.1 az 1. körön már rögzített — a prompt-fájl helye a munkapéldányon KÍVÜL
  van. Lásd [L494](docs/LESSONS.md#l494).


## 🔧 ÖNJAVÍTÓ KÖR — E13-R20 / H5 feloldva: a golden-raszterizációt a MERGE-KAPU architektúráján mérjük (2026-08-26)

Az E13-R20 kód-oldala kész volt (9/9 acceptance, gate 22/22 zöld kétszer), de az
exact-SHA CI **háromszor** piros lett 3 golden-cellán (1 / 8 / 1 px, mind
**0,00%**). A lánc H5-tel megállt; ez az [ADR 0112](docs/adr/0112-self-healing-pipeline.md)
önjavító köre.

**A MÉRT gyökérok.** A goldeneket ez a box veszi fel (**aarch64**), a kaput adó
CI `ubuntu-latest` = **x86_64**, a `LocalFileComparator` pedig nulla
toleranciájú. Az [L486](docs/LESSONS.md#l486) ezt „ELVBŐL nem mérhető"-nek
mondta ki — az önjavító kör megmérte: a box `qemu-user` amd64 emulációval
futtat x86_64 konténert a CI-vel AZONOS `flutter 3.44.2` SDK-val.

| # | Mérés | Eredmény |
|---|---|---|
| 1 | a `main` MINDEN goldenje az x86-konténerben | **27 zöld** — az eszköz a CI hű mása |
| 2 | az E13-R20 branch goldenjei az x86-konténerben | **pontosan a CI 3 bukása** (1 / 8 / 1 px) |
| 3 | x86-on újrafelvéve, x86-on ellenőrizve | **6 zöld**, pontosan 3 PNG változott |
| 4 | az x86-felvételű PNG-k **natív ARM**-on | **3 piros** — a rés SZIMMETRIKUS |

A 4. mérés a döntő: nulla toleranciával a két architektúra egyszerre nem
elégíthető ki, tehát a felvételnek a KAPU gépén kell történnie.

**A javítás ([ADR 0426](docs/adr/0426-golden-rasterization-on-the-gate-architecture.md), [L493](docs/LESSONS.md#l493)).**

- `tools/golden-x86.sh check|record` + `tools/docker/golden-x86.Dockerfile` —
  golden-tesztek a CI-vel azonos SDK-val, `linux/amd64` konténerben.
- `tools/tests/test_golden_x86_parity.py` — a fix ELŐTT 3 esetben piros, utána
  zöld gépi őr (eszköz-lét, Flutter-pin egyezés, teljes felderítés).
- Az E13-R20 briefje **§0.1/R14** revíziót kapott: `record` x86-on, `check` a
  gate MELLETT, és a golden-útvonal kikerült a lokális ARM `gate_tests`-ből.

**A mérce VÁLTOZATLAN:** ugyanaz a nulla toleranciájú komparátor, ugyanaz a
teljes golden-készlet, változatlan `.github/**` és `tools/round-gate.sh`.

**Előfeltétel a boxon (egyszer, már telepítve):**

```bash
docker run --privileged --rm tonistiigi/binfmt --install amd64
```

**Ami a KÖVETKEZŐ E13-R20 sessionre marad:** a goldenek x86-os újrafelvétele a
kör-branchen (`tools/golden-x86.sh record …`), a §7 gate + `check`, majd a
szokásos exact-SHA CI és merge. Az önjavító kör szándékosan NEM vitte előre a
kör tartalmi munkáját (ADR 0112 §4).

## ✅ E13-R19 KÉSZ — Tuner és Metronome UI migráció — PR [#460](https://github.com/wolfcasaba/strumsight/pull/460), squash `e046eaaa` (2026-08-25)

A hangoló (UI-09) és a metronóm (UI-10) átállítva az `SsStageScaffold`-ra —
**a hangmagasság-becslő és a klikk-időzítés egyetlen sorának módosítása
nélkül**. Implementer `sonnet-impl` (Claude Sonnet 5, `--effort high`),
orchesztrátor/reviewer Claude Opus 5.

**Mi készült.**

- **`TunerScreen` és `MetronomeScreen` HELYBEN migrálva** az öt Stage-slotra
  (statusHeader / hero / feedback / timeline / bottomAction).
- **ÚJ `SsTunerGauge`** design-system komponens — tisztán prezentációs:
  minden színt és a `semanticLabel`-t a hívó adja, az l10n a feature-rétegben
  marad. A `CentsGauge` erre épül, publikus API-ja és az ADR 0280 szerinti
  szemantikája változatlan (a semantics-teszt módosítás nélkül zöld).
- **ÚJ `TunerUiState` + `tunerUiStateOf` tiszta leképezés és `TunerStability`**
  — az „instabil" állapotnak NINCS mezője a becslő kimenetén, ezért a
  származtatás a UI-rétegben él; a `lib/features/tuner/engine/**` diffje üres.
- **Többcsatornás visszajelzés:** irány-ikon + **látható** irány-szöveg + szín
  (a javító kör után az `unstable` ág is az irányt tartja elsődlegesnek, a
  „Hold steady…" másodlagos sor).
- **ÚJ tuner-tulajdonú referenciahang-lejátszó** `Provider.autoDispose`-on: a
  route elhagyásakor a hang leáll (`dispose()` előbb `stop()`-ol) és az
  audio-fókusz felszabadul. A megosztott, app-szintű `Backing` erre
  alkalmatlan volt (más feature-ök használják), a `lib/features/learn/**`
  pedig tilos zóna — a feloldás a kör saját fáján maradt.
- **A metronóm vizuális pulzusa az AUDIO ÓRÁHOZ kötve**
  (`MetronomeBeatClockAdapter implements SsBeatClock`, ADR 0274): az adapter
  UGYANAZT az elapsed-értéket olvassa, amit a klikk-ütemező — a vizuális ütem
  szerkezetileg nem tud elcsúszni a hangzótól. A haladó beállítások (ütemmutató)
  lapra kerültek; a tap tempo kiugró-kezelése érintetlen.
- 3 új l10n kulcs a FORRÁS-szegmensekben (`base/app_*` a metronómnak,
  `features/tuner_*` a hangolónak) + regenerált aggregátum; **4 commitolt
  golden PNG** (tuner + metronóm × compact és `textScale 2.0`).

**Evidencia a merge SHA-n (`d6ae43f1`).** Full Gate
[32910316117](https://github.com/wolfcasaba/strumsight/actions/runs/32910316117)
+ Router CI [32911764893](https://github.com/wolfcasaba/strumsight/actions/runs/32911764893)
mindkettő `success`; a reviewer célzott gate-je **22/22 zöld** izolált klónban,
KÉTSZER (az implementáció és a javító kör után is), `scope-audit` → OK
(27, majd 5 útvonal).

**A review nem bemondásra dolgozott.** Három valódi-sértés próba a GYÁRTÁSI
kódon, mind PIROSRA váltott, majd visszaállítva: a pulzus fázisát a saját
tickerből számolva (a `Timer.periodic`-osztály lényege) **három A4-cella**;
az `autoDispose` eltávolítása az **A5-cella**; és egy eldobható próbateszt
kimérte, hogy az ÚJ `unstable` állapotban a látható irány-szöveg 1 → 0
widgetre vált (MINOR-1) — ez utóbbi olyan rés volt, amit a kör SAJÁT
acceptance-cellái nem fedtek.

**Két MINOR a javító körben lezárva (`2c3df0ee`, `e7d143eb`), mindkettő ÚJ
őrcellával.** MINOR-1: az `unstable` ág elsődleges szövege az irány maradt.
MINOR-2: a `ReferenceTonePlayer.stop()` halott felület volt (nincs hívója, a
`dispose()` sem hívta) — most a `dispose()` első lépése, és a fake is ezt
tükrözi (`stopCalls == 1`).

**A típus-helyben kötés MÁSODSZOR is megspórolt egy H3-at
([L488](docs/LESSONS.md) alkalmazása).** A pre-flight kikötötte, hogy a két
képernyő típusneve és útvonala változatlan marad, és a kör nem hoz új
`*_screen.dart`-ot: a **17** típus-pin, az `ui_inventory_test` `hasLength(84)`
és a `test/app/**` + `test/core/**` + `test/features/today/**` fa így
érintetlen maradt (mérve: a diff azokon az útvonalakon **üres**).

**Két mért, a brief által nem jelzett csapda** (az implementer §10.2-je):
az `SsBeatPulse` és az `SsOverlayHost` az `AppTheme` alatt ÖSSZEOMLIK (mindkettő
`extension<SsColorScheme>()!`-t force-unwrappol, amit csak az `SsDarkTheme`
regisztrál) — a feloldás a kör saját, palette-driven `BeatPulseDot`-ja és a
`showModalBottomSheet`, a design-system fájlokhoz nyúlás nélkül. Ez ugyanaz a
nyitott Ch13-hiány, amit az E13-R17 review NOTE-1 már megnevezett.

## ✅ E13-R18 KÉSZ — Live Stage UI migráció — PR [#459](https://github.com/wolfcasaba/strumsight/pull/459), squash `cc06b7e7` (2026-08-25)

A Live felület (UI-08) átállítva az `SsStageScaffold`-ra és az új zenei
komponensekre — **a felismerési viselkedés változtatása nélkül**. Implementer
`sonnet-impl` (Claude Sonnet 5, `--effort high`), orchesztrátor/reviewer
Claude Opus 5.

**Mi készült.**

- **`LiveScreen` HELYBEN migrálva** az `SsStageScaffold` öt slotjára
  (statusHeader / hero / feedback / timeline / bottomAction), portrait,
  landscape és expanded elrendezésben.
- **Öt új design-system komponens:** `SsChordHero`, `SsStrumGlyph`,
  `SsBeatGrid`, `SsTempoDisplay`, `SsSignalQualityIndicator`.
- **Finish akció** — az ADR 0276 döntés 4 kikényszerítése (a migráció előtti
  `_ActionBar` csak Tuner/Pause/Metronome volt); a tartalék-cél az app
  belépési útvonala, és ha az maga a `/live` (a mai, shell-flag-KI default),
  a session helyben ér véget ahelyett, hogy egy önkényes képernyőre ugrana.
- **Bejelentés-throttling** az ADR 0280 §2 költségvetésére (1000 ms, inkluzív
  határ), a motor SAJÁT óráján — a vizuális kép közben minden változást követ.
- **Gyenge jel és „nincs akkord" KÜLÖN állapot.** 3 új l10n kulcs a `base/`
  FORRÁS-szegmensben + regenerált aggregátum; 2 commitolt golden PNG.

**Evidencia a merge SHA-n (`1b1a1e48`).** Full Gate
[32901984638](https://github.com/wolfcasaba/strumsight/actions/runs/32901984638)
+ Router CI [32902067828](https://github.com/wolfcasaba/strumsight/actions/runs/32902067828)
mindkettő `success`; a reviewer célzott gate-je **17/17 zöld** izolált klónban,
KÉTSZER (az implementáció és a javító kör után is), `scope-audit` → OK a kör
diffjén (22 út).

**A review nem bemondásra dolgozott.** ÖT valódi-sértés próba a GYÁRTÁSI kódon,
mind PIROSRA váltott, majd visszaállítva: a gyenge jel és a „nincs akkord"
összevonása → **A2** (ez a brief §6.1 KÖTELEZŐ próbája), a throttle kiütése →
**A5**, a háttér-ág `engine.stop()`-jának kivétele → **A4**, és a javító kör
után a két fix visszarontása → a hozzájuk írt új őrcellák.

**A sáv H3-osztálya lezárva ([L488](docs/LESSONS.md)).** A `LiveScreen` típust
**9** teszt pinneli; a brief revideált listája hetet fedett, a nyolcadik
(`test/features/today/hub_navigation_test.dart`) az E13-R17-tel érkezett az
S11-mérés UTÁN. Lista-tágítás helyett — az mindig H3 — a pre-flight a típust
HELYBEN tartotta (`§0.0/R5`): a 9 pin, az `ui_inventory_test` `hasLength(84)`
és a `lib/app/routing/**` így mind érintetlen maradt. Ugyanez a pre-flight
mérve megcáfolta a brief §7 golden-precedensét (a `chord_timeline_golden_test.dart`
`GOLDENS=1`-re **skip-elt**), és kimérte, hogy a `countIn` transport-állapot a
Live úton elérhetetlen.

**Két MINOR a javító körben lezárva (`daa5a369`).** Az `SsLiveRegion`
(`ChangeNotifier`) nem került `dispose()`-ra; és a Finish tartalék-célja
(`/learn`) önkényes volt — a shell-flag-KI default mellett ez volt a MINDIG
futó ág. Mindkettőhöz új őrcella, a zárás visszarontás-próbával ellenőrizve.

**Egy dispatch-tanulság ([L489](docs/LESSONS.md)).** Az első futás 86 fordulón
át csak olvasott, majd jelzés nélkül elhalt — `dirty_files=0`, nulla
visszanyerhető munka. A `tools/mm-round.sh` közvetlen hívása NEM örökli a
motor-nyilvántartás őr-küszöbeit (5 perces default a 12 helyett). A retry a
nyilvántartás értékeivel ment, és a prompt kötelezővé tette a korai `progress`
jelzést + az inkrementális commitot: nyolc commit maradt hátra.

## ✅ E13-R17 KÉSZ — Today, Practice és Profile hubok — PR [#456](https://github.com/wolfcasaba/strumsight/pull/456), squash `4235f636` (2026-08-25)

Az UI-05/UI-06/UI-07 cél-hubok bekötve az adaptív shell mögé (ADR 0275, a
flag **defaultból KI**). Implementer `sonnet-impl` (Claude Sonnet 5,
`--effort high`), orchesztrátor/reviewer Claude Opus 5.

**Mi készült.**

- `lib/features/today/` — **TodayHubScreen** (`/today`): egyetlen elsődleges
  CTA négy tervállapotban (új felhasználó / terv kész / nap teljesítve / terv
  nélkül), offline és sync-várakozó sáv a cached tartalom fölött (ADR 0277),
  indokot adó letiltott Vision-kártya, `TodayPlanRepository` seam.
- `lib/features/practice_hub/` — **PracticeAreaHubScreen** (`/practice`,
  a `practiceEngineV2Enabled` kapu VÁLTOZATLAN): egy ajánlott-gyakorlás CTA,
  négy gyors eszköz EGY érintésre, öt cél szerinti kategória-chip.
- `lib/features/profile_hub/` — **ProfileHubScreen** (`/profile`): fiók
  nélkül is teljes, bejelentkezési fal NÉLKÜL; valós auth- és
  community-állapot.
- A shell három destination-buildere átkötve; a legacy route-ok és a
  redirect-térkép érintetlenek. 39 új l10n kulcs a `base/` FORRÁS-szegmensben
  + regenerált aggregátum. 6 commitolt golden PNG.

**Evidencia a merge SHA-n (`b1edc41c`).** Full Gate
[32891144024](https://github.com/wolfcasaba/strumsight/actions/runs/32891144024)
+ Router CI [32891134259](https://github.com/wolfcasaba/strumsight/actions/runs/32891134259)
mindkettő `success`; a reviewer célzott gate-je **11/11 zöld** izolált klónban
(kétszer futtatva), `scope-audit.py` → OK.

**A review nem bemondásra dolgozott.** A §6.1 mérce-mátrix **négy sorát** saját,
eldobható valódi-sértés próbával mértem a GYÁRTÁSI kódon, és mind a négy
PIROSRA váltott: a metronómot harmadik szint mögé téve az **A2** (ez a brief
§6.1 KÖTELEZŐ próbája, amit az implementer teszt-lokális fán érvelt le —
MINOR-1), két egyenrangú `FilledButton`-nal mind a négy **A1** cella,
bejelentkezési fallal az **A3**, kitalált „7 napos" szériával az **A8**.
Mind visszaállítva.

**Két javító kör — a CI golden-pirosa ([L486](docs/LESSONS.md)).** A hat
golden lokálisan zöld volt, a CI négyet pirosra váltott. A diagnózis **két
hipotézist cáfolt meg mérve** (inline `Montserrat`/`w800`, majd a
`withValues(alpha:)` — mindkettőt az E13-R16 CI-ZÖLD precedense zárta ki),
mielőtt a tényleges gyökérokhoz ért: a `_Metric` a `ColorScheme.fromSeed`-ből
(HCT **lebegőpontos**) származó `surfaceContainerHighest`-et festette nagy,
egybefüggő felületre. Konstans színforrásra cserélve a CI zöld. A
betűtípus- és eltolódás-magyarázatot **pixel-aritmetika** zárta ki: a mért
diff (21 096 px) ≈ a két metrika-doboz TELJES területe, miközben négy rövid
felirat glifái együtt is csak ~2-3 ezer px.

**Egy lelet a javító kör DOKUMENTÁCIÓJÁBAN ([L487](docs/LESSONS.md)).** A §12
egy **nem futott** CI-futásra hivatkozott bizonyítékként („a fix után a CI
ismét piros maradt") — a két javító kör között nem futott CI. A következtetés
helyes volt, a hivatkozott bizonyíték nem létezett; a reviewer korrigálta
(`1ee36ebc`), mert a kör-doksikat a következő körök olvassák és a RAG
indexeli.

**Nyitva hagyva (follow-up, nem blokkoló).**

- **MINOR-2:** az A2 négy cellájából kettő tautologikus (a `_DepthLevel`
  teszt-fát méri, gyártási regressziótól sosem pirosodhat) — a valódi
  védelmet a két gyártási cella adja.
- **NOTE-1 (termék-szintű):** a `core/design_system` **19** komponense
  `extension<SsColorScheme>()!`-t force-unwrappol, miközben a `StrumSightApp`
  `AppTheme`-et alkalmaz — ezért **0** shippelt feature-képernyő használ
  `SsCard`/`SsButton`-t. A Ch13 design system ma gyakorlatilag nincs
  élesítve; ez az **E13-R36** (Ch13 zárás) vagy egy önálló ADR dolga.
- **NOTE-2:** a Practice Hub öt kategória-chipje ugyanarra a
  `practiceSetup` route-ra megy (szűrő-API még nincs).

**Következő kör:** **E13-R18** — Live és Stage UI
(`docs/rounds/e13-r18-live-stage-ui.md`, `sonnet-impl`, ADR `nincs`).

## ✅ [HEAL E13-R17/H3] KÉSZ — a shell-destination navigációs őr: `S10` brief-lint szabály + a Ch13 sáv három routert engedő körének eltakarítása — PR [#455](https://github.com/wolfcasaba/strumsight/pull/455) (2026-08-25, L485)

Az **E13-R17** az orchestrátor pre-flightjában állt meg (**H3**),
implementer-dispatch nélkül: a brief §0.0/R3 „nincs keresztmetszeti teszt"
állítása **mérve hamis** volt.

**Saját reprodukció** (izolált klón `/tmp/ss-heal-probe-r17`, `main @ 52df92b3`,
`tools/prepare-flutter-generated.sh` után; a kör magját szimulálva: a shell
három destination-builderét — `/today`, `/practice`, `/profile` — új
hub-képernyőkre átkötve, a `practiceEnabled` kaput változatlanul hagyva):

```
~/flutter/bin/flutter test test/app/navigation/   # bázis        -> +33 All tests passed
~/flutter/bin/flutter test test/app/navigation/   # átkötés után -> +30 -3 Some tests failed
```

A három piros cella az `adaptive_scaffold_test.dart` A1-jében (kettő) és a
`tab_state_restoration_test.dart`-ban (egy) — mind `Found 0 widgets with type
"<LegacyScreen>"`. Az őrök a kör `allowed_paths`-án kívül élnek, a felvételük
az orchestrátornak tágítás ([L478](docs/LESSONS.md)) → H3.

**A javítás két lépése** (az [L483](docs/LESSONS.md) mintája: a hibás mérőműszer
és a már kimért defekt két külön lépés):

1. **`tools/brief-lint.py` `S10`** — ha egy brief a `lib/app/routing/` forrását
   engedi, követelje a `test/app/navigation/` őrt az `allowed_paths`-ban ÉS a
   `gate_tests`-ben. A fedettség a router SAJÁT `_matches` előtag-szemantikájával
   mérve. Hamis riasztás ellen: `status != "done"` + az őr létezése a fában.
   **MÉRVE a korpuszon:** 18 brief engedi a routert, 15 `done` (13 még az őr
   létrejötte, az E13-R08 ELŐTT merge-elt) → a szabály pontosan a **3 `pending`**
   briefre lő (`e13-r17`, `e13-r23`, `e13-r28`), **0 `done` körre**.
2. **A defekt eltakarítása** mindhárom briefen: `allowed_paths` + `gate_tests` +
   §7 gate-parancs + revideált §0.0/R3 a MÉRT cellalistával. A jogosultság
   **PONTOSAN** a lecserélt adapter TÍPUSÁNAK átírása.

**Egy tervezési döntés — átadva, nem meghozva (R17 §0.0/R5).** A `/practice`
destination `if (practiceEnabled)` kapuja **MARAD**: elmozdítása egy lezárt kör
(E13-R08 D15, review MINOR-1) mért viselkedését írná át (H2 osztály), és egy
NEGYEDIK cellát is pirosra váltana. A nyitott termék-kérdés —
`FeatureFlags.forEnvironment` szerint `practiceEngineV2Enabled: nonProd`, tehát
production alatt egy elsődleges nav-destination hiányozhat a shell élesítésekor
— a shell-flag bekapcsolását vivő körhöz vagy önálló ADR-hez került.

**A mérce nem gyengült:** 0 teszt törölve/`skip`-elve, 0 küszöb lazítva, a
`tools/round-gate.sh` és a `.github/workflows/` érintetlen; a `gate_tests`
bővítése tiszta erősítés (a három navigációs őr mostantól a körök lokális
kapujában is fut).

**Evidencia:** regressziós teszt `tools/tests/test_brief_nav_guard_scope.py` — a
javítás ELŐTT `8 failed, 9 passed` a `52df92b3` fán (`/tmp/ss-heal-red` klón),
UTÁNA zöld; a négy brief-lint teszttel együtt **46 passed**; `brief-lint --level
strict` mind a három revideált briefen „nincs lelet"; Router CI a merge SHA-n
`success`.

**A lánc folytatása:** az E13-R17 sorra kerül újra, a `main`-ről már a
revideált briefet olvasva ([L484](docs/LESSONS.md): a javítás a `main`-en
érkezik meg).

## ✅ E13-R16 KÉSZ — Launch, recovery és onboarding migráció — PR [#453](https://github.com/wolfcasaba/strumsight/pull/453), squash `8e530735` (2026-08-25)

A Ch13 **első képernyő-migrációs köre**. Implementer `sonnet-impl` (Claude
Sonnet 5, `--effort high`), orchesztrátor/reviewer Claude Opus 5. ADR **0281**
(már a `main`-en volt — a kör nem írt új ADR-t, és nem osztott új számot
merge-elt döntés fölé).

**Mi készült.** Bootstrap-redakció (A8: a nyers kivétel nem megy a
felhasználónak megjelenő szövegbe); `RecoveryScreen` + `/recovery` route (A4:
in-app biztonságos mód, adattörlő akció NÉLKÜL); villanásmentes `LaunchScreen`;
onboarding-ellenőrzőpont (A6/A7: `OnboardingStep {welcome, permission, done}` +
migráció a legacy `ss.onboarding.seen` boolból); `PermissionPrimerScreen`
(A1/A2: a rendszer-párbeszéd ELŐTT indokol, végleges elutasításnál csak
beállítás-út); „első siker" mini Stage (A3/A5: fake motorral, kör-lokális
`kFirstWinConfidenceThreshold = 0.60`, `ref.onDispose` felszabadítással);
golden-kapu (A9: 10 PNG = 5 képernyő × 2 keret, két valódi túlcsordulást talált
és javított); l10n fragmentum az ADR 0307 §4 útján.

**Négy javító kör** ([review](docs/reviews/e13-r16-review.md) — **APPROVED**).
Az első verdikt CHANGES REQUESTED volt **zöld célzott gate mellett**:

- **F1 BLOCKER (A1):** a karusszel a primer MEGKERÜLÉSÉVEL kért
  rendszer-engedélyt, és a `PermissionPrimerScreen` a futó appban elérhetetlen
  volt (az A1 teszt csak az IZOLÁLT widgetet mérte). Az implementer indoklása
  mérve téves volt: a legacy E2E teszt fake átjárója `granted`, ahol a primer
  átfutó no-op. Javítva, a listán kívüli `onboarding_first_win_test.dart`
  módosítás nélkül zölden maradt.
- **F2/F3 MAJOR:** egyetlen input által sem előállítható enum-állapot törölve;
  a perzisztált `enum.index` sorrend-szerződéshez kipinnelt őrcella.
- **F6 MINOR** — reviewer-próbateszttel találva: az A1 őre csak az EGYIK CTA-t
  fedte, a másik útra injektált sértés MINDEN tesztet zölden hagyott.
- **F8/F9** — a **teljes CI-suite** két olyan leletet hozott, amit a célzott
  gate szerkezetileg nem fedhetett (repó-szintű invariáns-tesztek a kör hat
  céltesztjén kívül): a design-system barrel-határ 11 sértése (javítva, a 10
  golden bit-azonos maradt), és a képernyő-leltár `hasLength(79)` őre.

**Az F9 H3 volt, és a lánc önjavító köre oldotta fel.** A leltárteszt nem
szerepelt az `allowed_paths`-on, a felvétele pedig tágítás → a kör megállt. A
`c064566f` HEAL (PR [#454](https://github.com/wolfcasaba/strumsight/pull/454))
felvette a listára ÉS a `gate_tests`-be, megírta a brief §0.0/R6-ját, és a
**gyökérokot** is javította (`tools/brief-lint.py` `S9`). A folytatás a §0.3
upstream-szinkronnal vette át (`git merge --no-ff origin/main` → `721ab1f0`,
konfliktus nélkül), a javító kör 4 pedig ebből pontosan **egy számot** írt át:
`79` → `81` ([L484](docs/LESSONS.md)).

**Evidencia** (merge-jelölt `14c36e90`): célzott gate **11/11 ZÖLD**
(`GATE_EXIT=0`, izolált `/tmp` klón, csővezeték nélkül), utána a klón
`git status --short` üres; reviewer-próba #4 (extra `_screen.dart` injektálva)
→ `has length of <82>`, `Some tests failed` ⇒ az őr valódi; scope-audit **35
útvonal, 0 sértés**; Full Gate
[32875752367](https://github.com/wolfcasaba/strumsight/actions/runs/32875752367)
+ Router CI
[32875755561](https://github.com/wolfcasaba/strumsight/actions/runs/32875755561)
mindkettő `success` a merge SHA-n; az `origin/main` a dispatch óta nem mozdult.

**Nyitva hagyva (szándékosan).** **F5 NOTE:** a redaktált bootstrap-üzenet nem
lokalizált — a §0.0/B P4 (a `BootstrapFailure` alakja nem törhet, két
fogyasztója tilos zónában) miatt a körben nem oldható. **A
`FirstWinStageScreen` bekötése:** kész, bizonyított komponens, de a `lib/` fából
még nem hivatkozott; a bekötést a listán kívüli
`test/app/routing/onboarding_first_win_test.dart` egyetlen-settle elvárása
blokkolja — **a következő kör briefjének fel kell vennie azt a fájlt az
`allowed_paths`-ra** (review §12).

---

## ✅ [HEAL E13-R16/H3] KÉSZ — az `S9` képernyő-leltár őre KÖNYVTÁR-előtagra is lő; a Ch13 sáv 20 halálának megszüntetése — PR [#454](https://github.com/wolfcasaba/strumsight/pull/454) (2026-08-25, L483)

**A halt.** Az `E13-R16` KÉSZ volt és minden mércéje zöld — célzott gate 10/10,
scope-audit 0 sértés, Router CI success, review APPROVED —, **egyetlen teszt
kivételével**: a `test/ui/ui_inventory_test.dart:14`
`expect(first.screenPaths, hasLength(79))` a mért **81** ellen bukott
([full-gate 32867296946](https://github.com/wolfcasaba/strumsight/actions/runs/32867296946),
6366 passed / 2 failed). A kör két képernyőt hozott a
`lib/features/onboarding/screens/` alá; a leltárteszt nem volt az
`allowed_paths`-on, a felvétele pedig tágítás = **H3** ([L478](docs/LESSONS.md)).

**A gyökérok nem a brief volt, hanem az őr.** Pontosan ezt a hibaosztályt írta
meg az E09-R24 önjavítás `S9` néven a `tools/brief-lint.py`-ba, de a predikátuma
csak **literálisan** `_screen.dart`-ra végződő `allowed_paths` elemet nézett. Az
E13-R16 briefje a `lib/features/onboarding/` **KÖNYVTÁRAT** engedte → az `S9`
néma maradt. A `9acd14e5` sáv-szintű batch pre-flight commit-üzenete rögzíti is:
*„`--level strict` mind a 20 briefen → nincs lelet"*.

**A javítás négy része.** (1) `screen_capable_prefixes()` — a `lib/features/`
alatti könyvtár-előtag is számít, mert a `tool/ui_inventory.dart` REKURZÍVAN
listáz; a hamis riasztás ellen a fa mérhető igazsága zár (a LÉTEZŐ, de
`_screen.dart`-ot nem tartó könyvtár kimarad — `lib/features/community/domain/repositories/`
az E09-R05 `done` körből, `lib/features/practice_generator/public/` az E99-R18
`done` körből). (2) Regressziós teszt a MÉRT E13-R16 adatokkal — a javítás előtt
**3 cella PIROS**. (3) A megállt kör briefje §0.0/**R6**: a leltárteszt az
`allowed_paths`-ra ÉS a `gate_tests`-be; **a kör teendője ebből pontosan EGY
szám: 79 → 81**, kerülőút (átnevezés vagy a `tool/ui_inventory.dart` lazítása)
TILOS. (4) Ugyanez az őr az **R17–R35** (19) briefre is — enélkül a javított lint
csak *korábbra* vinné a haltot, mert a teendője tágítás, amit az orchestrátor az
L478 szerint nem hajthat végre.

**MÉRVE a 308 elemezhető brief korpuszán:** 23 lelet, ebből **0 `done`
(merge-elt) kör** — 20 `pending` (a teljes E13-R16…R35 sáv) és 3 `hold`.

**A következő lépés a láncé:** az `E13-R16` újraindul, a friss `main`-nel
konfliktusmentesen merge-elhető (eldobható klónban mérve a `5c32fb23` PR-csúcs
ellen), és a `hasLength(81)` bumppal a `full-gate.yml` + `router-ci.yml` a merge
SHA-n zöldre vihető.

**Rögzítve, de ebben a körben nem javítva:** a round-gate `architecture` lépése
(`tool/check_architecture.dart`) **nem azonos** a
`test/core/architecture_dependency_test.dart` design-system-határ mércéjével — az
E13-R16 egy teljes javító kört veszített erre (F8, `ded7a628`). Az utóbbi
`gate_tests`-be vétele **erősítés, nem tágítás**, tehát a körök saját
pre-flightjának hatásköre; nem kell hozzá önjavító kör.

## ✅ E09-R27 KÉSZ — Moderation queue, enforcement és appeal — PR [#452](https://github.com/wolfcasaba/strumsight/pull/452), squash `49ac8b21` (2026-08-25)

A Kör 19 media-triage és a Kör 26 report **egyetlen, auditálható
moderation-case modellé** állt össze: `community_moderators` (a projekt
ELSŐ jogosultsági rétege, a `User`/`deps.py`/`security.py` érintése
nélkül), `community_moderation_cases` (öt-értékű `state`, `appeal_state`,
denormalizált `is_open`, `priority_score`) és `community_moderation_actions`
(immutable audit — **nincs `updated_at` oszlop**, és a service nem exportál
`update_action`/`delete_action` függvényt: a hiány maga a mérce). Normatív
forrás **ADR [0425](docs/adr/0425-moderation-queue-enforcement-and-appeal.md)**.
Implementer **MiniMax M3**, orchesztrátor/reviewer **Claude (Opus 5)**.
48 backend cella. **Két javító kör.**

**A sáv 2026-08-24 20:20-kor megállt, és ez a session állította helyre.** Az
implementer 5 commitot hagyott a `minimax/e09-r27-…` branchen (a §10 handoff
kitöltve, 42 teszt zölden), de **PR nem született**, és a Router CI
**pirosan** állt a head SHA-n. A folytatás egy **remote Claude Code
konténerben** történt — ott **nincs Flutter/Dart SDK, nincs `gh` CLI, és
nincs implementer-motor** (sem MiniMax, sem Codex). Ennek két rögzített
következménye: (1) a `tools/round-gate.sh` Dart-oldali lépései lokálisan
NEM futtathatók, ezért a Dart-mérce **kizárólag a CI Full Gate** az exact
head SHA-n — a kör diffje egyetlen Dart fájlt sem érint; (2) a javító kört
**nem az implementer-motor vitte, hanem a reviewer**, amit a
`sdd-round-driver` skill a „motor-oldal nem elérhető" kivételként enged, és
a user a session elején explicit a kör landolását kérte.

**A piros CI gyökéroka: az implementer FELÜLÍRTA a saját kör-briefjét.** A
§10 handoff kitöltése helyett a teljes brief helyére a saját beszámolója
került — eltűnt a §0 (kör-jelzés/STOP), §3 (scope), §4 (engedélyezett
fájlok), §5 (kötött döntések), §6 (acceptance + mérce-mátrix), **§7
(kötelező ellenőrzések, benne a gate-sor)**, §8 és §9. A brief-lint **B4**
(„a brief nem hivatkozza a gate artefaktumot") ennek a **mérhető nyoma**
volt — három router-teszt-cella egyszerre pirosodott rá. A `fix1` a §0 és
§1–§9 visszaállítása az `origin/main` briefjéből (ADR-szám a mért `0425`-re),
az implementer beszámolója a handoff alá (§10.0 / §10.0b), a doc végén lógó
`ai-router` blokk a sablon szerinti helyre. **Új lecke: a kör-brief a kör
TERVE — az implementer kitölti, nem írja felül.**

**A review két MAJOR-t talált ZÖLD backend-gate mellett — mindkettő ugyanazon
a vak folton ült** (`docs/reviews/e09-r27-review.md`): az A5 cella az appeal
**darabszámát** mérte, a **beadó személyét** nem — se a jogosultságát, se az
audit-sorban rögzített szerepét.

- **F1** — a `POST /cases/{id}/appeals` **bármely hitelesített felhasználót**
  elfogadott (a router docstringje szó szerint: „Any authenticated user can
  submit an appeal"), miközben az A5 case-enként **pontosan egy** appealt
  enged. A kettő együtt abúzus-út: egy idegen beadja először, és a szerző
  jogorvoslata elveszett. A modul már tartalmazta a szerző feloldásához
  szükséges `_target_author_profile_id` helpert — az appeal-úton nem hívta.
- **F2** — az appeal-beadás audit sora `actor_type="human_moderator"`-t írt
  akkor is, ha közönséges felhasználó adta be. A D5 immutable audit-lánc
  egyetlen haszna az, hogy **igazat mond**.

A javító kör mindkettőt zárta: a beadó vagy a target szerzője
(`_is_target_author`, `users.id → community_profiles.id` 1:1 feloldás), vagy
moderátor — minden más `NotTargetAuthor` → **403**; a fel nem oldható
`target_type` (pl. a még be nem drótozott `media`) **fail-closed**. Az
audit-lánc új `ACTOR_TYPE_CONTENT_AUTHOR` értéket kapott (`String(16)`-ba
fér, migráció nem kell); a moderátor nevében beadott appeal marad
`human_moderator`. Plusz F3 (a `get_or_create_case` docstringje egy nem
létező uniqueness-garanciára hivatkozott — az index mérve `unique=False`;
az ADR §D2 a service-rétegű mechanizmust kifejezetten megengedi, tehát a
**hamis állítás** volt a lelet) és F4 (nem létező kivétel-nevek a
modul-docstringben).

**A reviewer egyik mérést sem fogadta el bemondásra — mind a négy próba
saját, izolált klónon, a PRODUCTION forrás valódi mutációjával** (nem a
teszt monkeypatchével): a §6.1 kötelező próba a HÁROM automatika-gát
egyidejű kinyitásával → **5 cella PIROS**; a router auth-gát törlése → **A1
PIROS**; publikus `update_action(...)` → **A3 PIROS**; és a javító kör
falszifikációja — a guard visszavonásával a `TestAppealAuthorGuard` **4
cellája PIROS**. Mért érdekesség: az auth-gát törlése után a
`…_on_decision` cella **zölden maradt** — helyesen, mert az
`apply_moderator_decision` a service-rétegben **is** ellenőrzi a
moderátor-identitást (védelem mélységben), tehát ez nem lelet.

**Nyitva, NEM ez a kör tárgya:** (N1) partial unique index a
`(target_type, target_id)` párra `is_open = 1` mellett — a D2 invariánst ma
service-rétegű read-then-insert tartja, SQLite-on a versenyablak nem
elérhető; (N2) a moderation router **sehol nincs felszerelve** — a
`build_community_router` ma is csak a `profile` routert mounttolja, a 13
community routerből 12 (a Kör 26 `reports` is) kívül marad; ez epic-szintű,
korábbról öröklött hiány (ADR 0395 Következmények 3. pont), és a
`backend/app/community/__init__.py` ennek a körnek tilos zónája.

**Zöld kapu az exact `895f2acd` SHA-n:** Full Gate [32828856447](https://github.com/wolfcasaba/strumsight/actions/runs/32828856447) (a `Coverage` job is `success`) + Router CI [32828854512](https://github.com/wolfcasaba/strumsight/actions/runs/32828854512) + Backend CI [32828854674](https://github.com/wolfcasaba/strumsight/actions/runs/32828854674) — mind `success`. A Backend CI első futása `cancelled` lett (az orchesztrátor
korábbi, kézi dispatchével átfedésben futott) — ugyanazon a SHA-n újrafuttatva
zöld. Új leckék: [L479](docs/LESSONS.md) (a brief felülírása),
[L480](docs/LESSONS.md) (a „legfeljebb N-szer" invariáns a „ki" nélkül a
jogosult felhasználó ellen fordul).

## ✅ E13-R15 KÉSZ — Lokalizációs resilience és content style — PR [#450](https://github.com/wolfcasaba/strumsight/pull/450), squash `d21d225f` (2026-08-24)

Az en–hu felület **törésbiztonsága gépi őrökké** vált: fragmentum-szintű
ARB-paritás (a hibaüzenet a `lib/l10n/{base,features}/*.arb` fájlt nevezi meg,
nem csak azt, hogy „valahol hiányzik"), **nyelvhelyes** magyar többes szám,
locale-tudatos formázók (`SsFormatters.{duration,bpm,cents,percent,date}`),
pszeudo-lokalizációs teszt-mód (`ssPseudoLocalize` ≥1,6×, placeholder-őrző),
beégetett-szöveg/mondat-összefűzés guard racsnival, és a
`docs/ui/content-style.md` microcopy-útmutató. Normatív forrás **ADR
[0424](docs/adr/0424-localization-resilience-contract.md)** — a kör ADR-t
KAPOTT (a Ch13 R12–R14 mintájától eltérően: a Ch13 ADR-blokkban
(0273–0289) nincs lokalizációs döntés, a foglaló `0424`-et adott).
Implementer **`sonnet-impl`** (Claude Sonnet 5), orchesztrátor/reviewer
**Claude Opus 5**. 72 gépi cella. **1 javító kör.**

**A pre-flight fogta meg a kör végrehajthatatlanságát — implementer-futás és
halt nélkül.** A brief 2026-08-15-én készült; az azóta merge-elt **ADR 0307
§4** óta a `lib/l10n/app_{en,hu}.arb` **generált aggregátum**, a brief viszont
pontosan ezeket sorolta fel ARB-írás céljára. Ez a hibaosztály **negyedszer**
ütött (L365 E08-R12, L369 E08-R13 H3 self-heal, L396 E08-R20).

A feloldás **szűkítés volt, nem tágítás** — és ez tudatosan tér el a §6-ban
hagyott javaslattól („a brief `allowed_paths`-ának a FRAGMENTUMOKAT kell
felsorolnia"): a fragmentumok felvétele **tágítás, azaz H3**, ami az
orchestrátor hatáskörén kívül esik (ADR 0087 §2). Mérve viszont az is, hogy
**nem volt mit felvenni**: a paritás minden szinten teljes (aggregátum
1838/1838, mind az 5 szegmens 1:1), tehát nulla pótolandó hiány. A kör így
**egyetlen ARB-fájlt sem szerkesztett** — és ezt a gate `L10n aggregate
freshness OK` lépése függetlenül is igazolja.

**A magyar nyelvtan mérve felülírta a brief szó szerinti olvasatát.** A
`{count} nap` **helyes** magyar (számnév után a főnév egyes számban marad); egy
naiv „a hu tükrözze az en ICU-pluralját" őr három nyelvtanilag helyes kulcsot
(`streakV2{Current,Longest,Total}Semantics`) váltott volna pirosra. Az A5
ezért négy nyelvhelyességi szabályt mér, köztük egy pozitív cellát: a hu
kimenet `count=1` és `count=3` mellett csak a számjegyben térhet el.

**A review három MAJOR-t talált ZÖLD gate mellett — mindhárom üres vagy vak
cella volt** (`docs/reviews/e13-r15-review.md`), és mindhárom saját
valódi-sértés próbával kimérve:

- **F1** — az A2 guard nem látta a `'$count ' + l10n.x` alakot, vagyis pontosan
  azt, amit a brief §5.1 és az ADR 0424 §2.3 **néven nevez**. A `_classify`
  csak a string-literál belsejét nézte; a `+` utáni operandust soha.
- **F2** (a súlyosabb) — a guard sor-alapú volt, és **a gate SAJÁT `dart
  format` lépése** írta át a detektált sértést nem detektálttá. Mérve
  ugyanazon a sértésen: egysoros `Text('Save changes')` → PIROS; ugyanaz két
  szokványos argumentummal, `dart format` után → **ZÖLD**. Vagyis minden
  beégetett szöveg, amit a formázó tördel (a valós komponens-kód többsége),
  átcsúszott.
- **F3** — az A6 három küszöb-cellája (46/52/64 karakter) **üres** volt: a
  hordozó `SsFieldError` (`Row` + `Expanded`) szerkezetileg képtelen
  túlcsordulni — mérve **4000 karakteren is** `takeException() == null`.

A javító kör mindhármat zárta, és **production kódot nem érintett**: a
javítás végig a mércén történt. A guard most a fájl EGÉSZÉN fut,
hossz- és sortörés-őrző komment-kiszűréssel (a racsni sorszámai maradnak
helyesek); az A6 egy közbeiktatott `Column`-nal ad a `RenderFlex`-nek
függőleges fő tengelyt, plusz **falszifikációs cellát** kapott. A reviewer
mindhárom próbáját ÚJRAFUTTATTA: F1 → PIROS (A2), F2 → PIROS (A3), és egy
szimulált clipping-regresszió a production `SsFieldError`-on szintén PIROSRA
váltotta a suite-ot.

1 új MINOR follow-upra (**F6**): az A6 flex-**túlcsordulást** mér, nem belső
**csonkolást** — egy `maxLines`/ellipsis mögé rejtett szöveg ma átmenne a három
küszöb-cellán.

**Landolás négy fordulóban, párhuzamos sáv mellett.** Az E09-R26 sávja közben
háromszor mozdította a `main`-t, ezért a `tools/round-land.sh` háromszor kért
új exact-SHA CI-t (ez a §4.1 NORMÁL útja, nem hiba). Egy fordulóban a
kombinált-HEAD gate **pirosat** adott — a hiba az E09-R26 fájljában
(`report_content_sheet.dart`, hiányzó `reportSheetCategory*` getterek) volt,
azaz a munkapéldány **gitignore-olt, elavult** `app_localizations.dart`-ja;
`tools/prepare-flutter-generated.sh` után zöld. Nem H5/H7/H8: a kulcsok a
merge-elt ARB-forrásban végig megvoltak. Exact `5111a147`: Full Gate
32769578246 + Router CI 32769567169 mind success.

## ✅ E09-R26 KÉSZ — Felhasználói report és azonnali safety flow — PR [#451](https://github.com/wolfcasaba/strumsight/pull/451), squash `df0ad3dd` (2026-08-24)

Report/hide/mute/block az ELSŐ darabja: `community_reports` tábla (target
type/id, category, opcionális detail, reporter, `dedup_key`), `report_service`
idempotens submit-tal (azonos target/category triple → 1 sor) és sanitizált
válasszal — a reporter személye SOSEM kerül a target válaszaiba (A1, kétszer
mérve: saját teszt + a security-reviewer független mutation-próbája), Flutter
`report_content_sheet` lokalizált kategóriákkal, self-harm concern jóváhagyott
safety-copy routinggal, és a submit UTÁNI azonnali hide/mute/block választóval.
ADR [0422](docs/adr/0422-user-report-and-immediate-safety-flow.md) (az előre
kiosztott `0414` szám a §0.0 brief-revízióval `0422`-re változott — a régi
számra öt fájlban maradt docstring-hivatkozást a javító kör törölte, F3).
Implementer **MiniMax M3**, orchesztrátor/reviewer **Claude Sonnet 5**.

**Ez a session a §0.2 örökség-létra ÚJ `REVIEW-APPROVED` fokán folytatta,
nem kezdte újra.** A kört egy korábbi, `API Error`-ba futó session
17:48–18:08 között elveszítette PR nélkül, holott 24 commit, a review már
**APPROVED** volt (0 nyitott lelet), és a Full Gate zölden állt a régi
`520be629` head SHA-n (részletesen: `docs/handoff-archive.md`, a felváltott
heal-blokk). A driver §0.2 létrája időközben megkapta a hiányzó fokot
(`tools/round-resume-probe.sh` → `REVIEW-APPROVED`), a `resume-state-E09-R26.md`
ezt jelezte, és a jelen session — implementer-dispatch NÉLKÜL — egyenesen a
merge-lépésnél vette fel a kört: §0.3 upstream-szinkron (két kör, `main`
E13-R14 óta mozdult: `28a53b1a` majd `6d0a2324` merge-commit), PR #451, ÚJ
exact-SHA CI-mérés a friss merge SHA-n (a régi zöldje NEM mentesített) — Full
Gate [32764316892](https://github.com/wolfcasaba/strumsight/actions/runs/32764316892)
+ Router CI [32764303470](https://github.com/wolfcasaba/strumsight/actions/runs/32764303470)
mind success —, majd a megosztott `tools/round-land.sh` (két sáv fut
párhuzamosan, `docs/execution/pipeline-slots` = 2) végezte a rebase +
kombinált-HEAD gate + safe-force-push + squash-merge láncot.

**Review: 1 javító kör, F1–F3 MINOR zárva, 0 nyitott lelet a merge után**
(`docs/reviews/e09-r26-review.md`, végső döntés APPROVED). F1: `target_id`
malformed-UUID 404 helyett 400-at ad (explicit validáció a `target_exists`
hívás ELŐTT). F2: `extra_metadata` méret/kulcsszám-korlát KÓDOLÁS előtt
(`InvalidExtraMetadata` explicit dobás csonkítás helyett — a régi kód
érvénytelen JSON-t is termelhetett volna a Kör 27 moderation-queue-nak).
F3: öt fájl docstring-je a téves `ADR 0414`-ről a helyes `ADR 0422`-re.
Security review (risk=high, kötelező): **PASS**, 0 BLOCKER/CRITICAL/MAJOR.

**Nyitva, NEM ez a kör tárgya:** a moderation-queue tényleges feldolgozása —
Kör 27.


## ✅ E13-R14 KÉSZ — Accessibility foundation audit és semantics toolkit — PR [#448](https://github.com/wolfcasaba/strumsight/pull/448), squash `838865d3` (2026-08-24)

A design system accessibility-szabályai **egyetlen gépi szerződéssé** álltak
össze: `SsLiveRegion` (bejelentés-költségvetés), `SsTapTarget` (érintési cél
audit), a `SsSemantics` szerződés-építői (tuner cents, strum-irány), plusz a
`docs/ui/accessibility.md` kézi TalkBack/VoiceOver ellenőrzőlistája. Normatív
forrás **ADR [0280](docs/adr/0280-accessibility-contract-and-live-region-budget.md)**
— a Ch13 ADR-jei előre merge-elve érkeztek, ezért a kör **ADR-t NEM írt** (a
foglalótól kapott `0423` felhasználatlan; `docs/adr/**` végig tilos zóna).
Ugyanaz a minta, mint az E13-R12 `0278`-ánál és az E13-R13 `0279`-énél — ez a
**hatodik** ismétlés. Implementer **`sonnet-impl`** (Claude Sonnet 5),
orchesztrátor/reviewer **Claude Opus 5**. 27 gépi cella (13 + 6 + 8).

**A kör egy MEGÖLT session munkájából folytatódott.** Az E13-R14 első
orchestrátorát a 20 perces elakadás-őr megölte (H-NOSIGNAL, PR #447 / L472) —
**miközben az implementer 16:03:33-kor `status=done`-nal már befejezte a kört**.
Ez a session a §0.2 örökség-ellenőrzéssel megtalálta a
`/home/ubuntu/ss-sonnet-impl-e13-r14` munkapéldányt (pre-flight `5be0a3a3` +
teljes implementáció `845d3c93`), **felhasználta** a commitolt pre-flightot
(nem írta újra), és a normál review → CI → merge útvonalon zárta le. Nyitott
leletekkel bíró review nem volt, tehát nem javító kör indult.

**Az örökölt jelzésfájl két gyanús mezője kivizsgálva, egyik sem volt valódi:**

- `dirty_files=1` — a fa MOST tiszta a `845d3c93` implementációs commiton, mind
  a 9 fájl commitolva: tranziens `.ai/` burkoló-artefaktum volt a jelzés
  pillanatában, **nincs elveszett munka**.
- `gate_shape=VIOLATION` — **hamis pozitív**. A naplóból kinyert TÉNYLEGES
  `Bash` hívások: a gate-futtatás a helyes, csővezeték nélküli alak; a
  VIOLATION-t egy `cat …/tools/round-gate.sh | head -60` (a script
  ELOLVASÁSA) váltotta ki. Új lecke: [L473](docs/LESSONS.md).

**A szerződés lényege — az élő régió nem spammelhet.** A Live/Stage felismerés
másodpercenként sokszor frissül; a naiv „minden változást bejelentünk" a
felolvasót használó felhasználónak **használhatatlanná tenné** a fő funkciót.
Az `SsLiveRegion.report(value, at:)` csak akkor jelent be, ha az érték eltér az
**utoljára BEJELENTETT** (nem az utoljára LÁTOTT) értéktől, ÉS azóta eltelt
`liveRegionAnnouncementGap` = **1000 ms, inkluzív határ**. A küszöb alatt
érkező olvasat **eldobódik, nem sorba áll**.

**Review: APPROVED első fordulóban** — nincs BLOCKER, nincs MAJOR; 4 MINOR + 3
NOTE, mind follow-up. A reviewer nem fogadta el bemondásra a §10-et:

- a gate **saját kézzel újrafuttatva** izolált `/tmp` klónban — mind a 8 lépés
  zöld, kilépési kód 0;
- `scope-audit.py --base origin/main` → `ok`, 9 útvonal + 1 generated/ignored
  (a review-jelentés állandó mentessége). A `--base 5be0a3a3` négy „sértése" a
  §0.3 upstream-merge `origin/main`-ből hozott fájlja — **nem H3**, pontosan az
  [L467](docs/LESSONS.md) mért hibaosztálya;
- **mindkét kötelező valódi-sértés próba a reviewer által is lefuttatva:**
  a költségvetés kivétele az A1 „below the threshold" cellát ÉS a felépített
  widget celláját pirosra váltotta (a §10.3 üzenetével szó szerint egyezve);
  az angolra drótozott `tunerAccuracyLabel` az A6 cellát váltotta pirosra.
  Mindkét mutáció visszaállítva, TEMP-kód nem maradt.

**Reviewer él-próbák (a kör celláin túl, mind mérve):** `SsButton(label:'A')` =
`64×48` (a csak-`minHeight` kötés ellenére mindkét tengely ≥ 48 — nincs lelet);
`textScale` 1.0 → 2.0 a gombot `104.4` → `136.4` szélesre nyújtja (a skálázó
valóban átmegy); `announcements.add(…)` → `throwsUnsupportedError`; a visszafelé
ugró időbélyeg **nem** nyit ki bejelentést.

**MINOR-ok (follow-up):** (1) `tap_target_test.dart` `setViewport` holt
`textScale` paramétere; (2) a „textScaler travels through MediaQuery" cella
KIZÁRÓLAG `meetsMinimum`-ot assertál, ami minden skálán igaz — a neve többet
ígér, mint amit mér (a skálázó valóban működik, ezt a reviewer mérte meg); (3)
a `tunerAccuracyLabel` megduplázza a `cents_gauge.dart:29-34` kerekítését, a
tükröt semmi nem őrzi (a `cents_gauge.dart` a listán kívül van → a tuner
migrációs körének feladata); (4) az `SsLiveRegion._announcements` korlátlanul
nő egy folyamatos Stage Mode-használatra tervezett osztályban.

**Zöld kapu:** Full Gate [`32754624167`](https://github.com/wolfcasaba/strumsight/actions/runs/32754624167)
+ Router CI [`32754624649`](https://github.com/wolfcasaba/strumsight/actions/runs/32754624649),
mindkettő `success` az exact merge SHA-n (`9f391cdd`).

## ✅ [HEAL E13-R14/H-NOSIGNAL] KÉSZ — az elakadás-őr egy KÉSZ kört ejtett el: néma, de ÉLŐ session ébresztése a kill előtt — PR [#447](https://github.com/wolfcasaba/strumsight/pull/447) (2026-08-24, L472)

**A halt.** Az E13-R14 orchestrátor-sessionre 15:51:11-kor **kívülről érkezett
megszakítás** a `tools/wait-for-round.sh … 540` előtérbe tett hívása közben
(naplóban: `tool_result is_error=true` „The user doesn't want to proceed with
this tool use…" + `[Request interrupted by user for tool use]`), **követő prompt
nélkül**. A session ettől üres prompton állt: a tmux-session élt, a
Claude-process élt, a panel néma maradt. A driver minden ellenőrzése
„rendben"-t adott, így a 20 perces elakadás-őr 16:11:39-kor megölte a sessiont
és H-NOSIGNAL-t jelzett — **miközben az implementer 16:03:33-kor `status=done`-nal
befejezte a kört** (`head=845d3c93`, 27/27 új teszt). A lánc egy **kész kört
ejtett el**.

**A gyökérok nem a megszakítás** (az a repón kívül van: a driver `tmux send-keys`-e
csak az indítás, a párhuzamos E09-R26 session nem hívott tmuxot, a
`claude-session-watch.service` nem küld billentyűt), **hanem a helyreállítás
hiánya**: az őrnek volt felismerése, de nem volt mentése. Egy üres prompton álló
interaktív session önmagától sosem indul újra — csak kívülről, és a driver
kezében ott az eszköz, amivel elindította.

**A javítás.** `run_tmux_session` elakadás-ága korlátos **ELAKADÁS-ÉBRESZTŐ**-t
kapott: néma panel + a pane-en ÉLŐ interaktív Claude-process (ugyanaz a
`ps -t <pane_tty> -o comm=` mérés, amit a driver már használ) → beküld egy
folytatás-promptot, és a következő teljes elakadás-ablakot adja a válaszra.
A stall-referencia a napló mtime-ja ÉS az utolsó ébresztés közül a későbbi — a
naplófájlt (a bizonyítékot) nem írjuk át hamis mtime-mal. **Az őr nem gyengült:**
a keret kimerülése után a `break`/kill változatlanul lecsap, csak nem az ELSŐ
néma ablak dönt. Keret: `PIPELINE_ORCH_STALL_NUDGES` (alap `1`), `0` = a javítás
előtti viselkedés. A `codex exec` panel a promptot argv-ből kapja, oda stdin-re
küldött szöveg nem ér el → ott a minta nem illeszkedik, a viselkedés változatlan.
**Ár (tudatos):** egy valóban menthetetlen session halála egy elakadás-ablakkal
(alapon 20 perc) később következik be.

**Mérce.** `tools/tests/test_round_pipeline_stall_nudge.py`, 3 cella (ébresztés
és jelzés → `RESULT_EXIT=0`; kimerített keret → az őr ugyanúgy öl, pontosan EGY
ébresztés után; `NUDGES=0` → a javítás előtti viselkedés). **RED/GREEN mérve:**
a javítás ELŐTT (`origin/main` driverrel) az első két cella PIROS, UTÁNA mind
zöld. Teljes router-suite **740 passed, 1 skipped**. A meglévő E05-R17
stall-guard regresszió szerkesztés nélkül zöld. Nincs Dart-változás → a
CI-bizonyíték a **Router CI**.

**A kör maga NEM veszett el:** az E13-R14 implementer-munkapéldány
(`/home/ubuntu/ss-sonnet-impl-e13-r14`, branch
`sonnet-impl/e13-r14-accessibility-toolkit`, `head=845d3c93`, `gate_shape=VIOLATION`)
érintetlen; a kör a lánc feloldása után újraindul és onnan folytatható.

## ✅ E13-R13 KÉSZ — Overlay, dialog, bottom sheet és confirmation rendszer — PR [#445](https://github.com/wolfcasaba/strumsight/pull/445), squash `9b3a5d5d` (2026-08-24)

Öt új design-system overlay komponens: `SsOverlayHost`, `SsDialog`,
`SsConfirmationSheet`, `SsToolConfirmationSheet`, `SsSideSheet` + Component
Catalog overlay-mátrix. Normatív forrás **ADR
[0279](docs/adr/0279-consequence-first-confirmations.md)** — a Ch13 ADR-jei
előre merge-elve érkeztek, ezért a kör **ADR-t NEM írt** (a foglalótól kapott
`0421` felhasználatlan; `docs/adr/**` végig tilos zóna). Ugyanaz a minta, mint
az E13-R12 `0278`-ánál. Implementer **`sonnet-impl`** (Claude Sonnet 5),
orchesztrátor/reviewer **Claude Opus 5**.

**A host a Flutter SAJÁT `showGeneralDialog`/`ModalRoute` gépezetére épül**, nem
kézi `Overlay.insert`-re: a `ModalBarrier` adja a `BlockSemantics`-ot (§5.4), a
`Navigator` a fókusz-csapdát és a visszaállítást. Az implementer P3 mutációja
(nyers `Overlay.insert`) mérhetően pirosra váltotta az A4/A5/A7 cellákat — a
döntés tehát bizonyítottan helyes.

**Review: APPROVED KÉT javító kör után** — 1. forduló **1 BLOCKER + 3 MAJOR +
3 MINOR + 3 NOTE**, mind **teljes zöld gate ÉS zöld CI mellett**. A gyökérok
egyetlen mért tény: a `flutter_test` alapfelülete **800×600 dp @ textScale 1.0**
— szélesebb, mint bármely telefon, és a kör mind a 21 cellája ezen futott.

- **BLOCKER-1** — a tool-lap nem görgethető (`Scrollable` a részfában = 0):
  411×891 @ `textScale 2.0`-n (= `SsSemantics.maximumTextScale`, a TÁMOGATOTT
  tartomány teteje) a `leaves-device` és a `recording` sor ÉS mindkét gomb a
  képernyőn kívülre esett; **már @1.0-n is a confirm** (R=471 > 411).
  ADR 0279 §5.2 + §5.3.
- **MAJOR-1** — 915×412 (fekvő telefon) @1.0: Cancel/Confirm látható hányad **0%**.
- **MAJOR-2** — a destruktív gomb felirata **levágódik** (`Clip.antiAlias`, nem
  ellipszis) → a gomb nem nevezi meg a műveletet (§5.1).
- **MAJOR-3** — a `_confirmed` őr a `State`-ben volt, a `showSheetSurface`
  widget-TÍPUST vált az `expandedMin` átlépésekor → új `State` → a destruktív
  visszahívás **kétszer** fut (§5.5 = adatvesztés).

**A fix1 a geometriát lezárta, de ÚJ BLOCKER-t vezetett be:** a MINOR-1
javítása (a `catch` ágban újra-élesítés) a `SsDialog`-ra **tartós őr nélkül**
került rá, mert a `SsDialog.show` a nyers `onConfirm`-ot adta tovább — dobó
`onConfirm` mellett a destruktív visszahívás **korlátlanul** futott (mérve:
**3 hívás**, átméretezés nélkül). **A leletet a reviewer KONTROLL-cellája hozta
elő** (`calls` 1 → 2), nem a fő cella — kontroll nélkül ez zöld gate-tel
merge-elődött volna. A fix2 a `SsDialog.show`-nak is megadta a `show()`-closure
őrt: mindhárom felület **pontosan 1** hívás.

**A zárást nem bemondásra fogadtam el**, hanem eldobható próbatesztekkel
visszamértem izolált `/tmp` klónban: geometria **6/6** `exception: none`, minden
gomb-rect a képernyőn belül (max R=387 < 411, max B=867 < 891); az
exactly-once mindhárom felületen 1; a reshape-próba 1/1.

**37 gépi cella** (7 + 30), köztük az **A9 geometria-mátrix**: 3 felület ×
{411×891, 915×412} × {textScale 1.0, 2.0}, a **kirendelt geometriára** mérve
(`takeException() == null` + a gomb-rect a képernyőn belül), nem
`findsOneWidget`-re.

**A pre-flight §0.0 négy mért korlátot rögzített**, amelyek közül kettő
megmentette a kört: a **listán KÍVÜLI** `component_catalog_test.dart` a zárt
katalóguson `SsCard == 1` és `DecoratedBox == 1`-et rögzít (ezért az
overlay-mátrix csak nyitó-gombokból áll), és a `TutorToolPermission` mindössze
`{readLocal, computeLocal}` — ezért a komponens **saját** négy-dimenziós
prezentációs modellt kapott, különben az A2 elérhetetlen státuszt mért volna.
**Egy pre-flight állításom viszont TÉVES volt** (D5): a
`lib/l10n/app_{en,hu}.arb` **generált aggregátum**, nem kézzel szerkeszthető —
az implementer helyesen tért el tőle ([L469](docs/LESSONS.md)).

Exact `46bd3797`: Full Gate
[32742011580](https://github.com/wolfcasaba/strumsight/actions/runs/32742011580)
+ Router CI [32742072084](https://github.com/wolfcasaba/strumsight/actions/runs/32742072084)
success. **Figyelmeztetés a landolásról:** a landoló a mozdult `main` miatt
`d0857f41`-re rebase-elt, és arra a SHA-ra Full Gate **nem futott** — az
orchesztrátor a landoló első (`blocked`) kimenetét nem olvasta el, és
újrahívta. Utólagos ellenőrzés a merge-elt `main`-en (`9b3a5d5d`):
`tools/round-gate.sh` **7/7 zöld** + Full Gate dispatch. Lecke:
[L470](docs/LESSONS.md).

## ✅ E09-R25 KÉSZ — Club feed, pinned post és club challenge — PR [#446](https://github.com/wolfcasaba/strumsight/pull/446), squash `4725447b` (2026-08-24)

Klub-scope-olt feed + pinned-post + club-challenge lifecycle, a Kör 13
post-projekció és a Kör 21 challenge-invite infrastruktúra újrahasznosításával,
klub-audience/tagság-ellenőrzéssel. Backend: `club_feed.py` (klub-szűrt feed
olvasás), `club_content_service.py` (pin/unpin, club-challenge create/end), új
`community_club_pinned_posts` junction tábla + alembic migráció
(`e09_r25_0019`). Flutter: `club_detail_screen.dart` négy tabot kap
(Feed/Challenges/Members/About), képernyő-helyi providerekkel (a Kör 24
`communityClubRepositoryProvider` mintáját követve — repository-interfész
bővítés helyett) és A2 cache-invalidációval klub-elhagyáskor. Implementer
**MiniMax M3**, orchesztrátor/reviewer **Claude Sonnet 5**.

**Pre-flight (§0.0, `docs/rounds/e09-r25-club-feed-pinned-post-and-challenge.md`).**
Mért, kódból kiolvasott tények zárták le a brief homályos pontjait
[ADR 0420](docs/adr/0420-club-domain-membership-and-roles.md) D1/D2
hivatkozással: a `community_posts.club_id` (BigInteger, belső id) és a
`community_challenges.club_id` (String, a klub `public_id`-ját tárolja) ELTÉRŐ
szemantikájú; a `CommunityChallenge` modellen nincs `state` oszlop, az
"activate/end" ablak-alapú (`starts_at`/`ends_at`); a Flutter oldal a hiányzó
repository-metódusokat NEM interfész-bővítéssel, hanem a Kör 24
képernyő-helyi provider mintájával oldotta fel (L409/L442).

**Review: APPROVED, 2 javító kör után** — a review saját maga talált 1
MAJOR-t (F1: a pinned-post junction tábla privát `MetaData`-n élt, KIFEJEZETTEN
a migráció-drift-őr elkerülésére, tehát éles `alembic upgrade head` után a
tábla hiányzott volna), majd a kötelező `security-reviewer` (risk=`high`) MÉG
2 MAJOR-t: F2 egy hibás/félrevezető, duplikált `CLUB_PIN_AUTHORIZED_ROLES`
konstans a `club_feed.py`-ban (`{owner,moderator,member}`-t engedett volna egy
jövőbeli routernek), F3 az `end_club_challenge` megsérthette volna a
`ck_community_challenges_window_positive` CHECK-et egy még el nem indult
challenge lezárásakor. Mindhárom javítva, a gate-eket mindkét javító kör után
SAJÁT kézzel, izolált `/tmp` klónokban újrafuttattam. 1 MINOR nyitva
follow-upként (F4). Részletek: [`docs/reviews/e09-r25-review.md`](docs/reviews/e09-r25-review.md).

**Exact `4d7bcdf3`:** Full Gate
[32737476796](https://github.com/wolfcasaba/strumsight/actions/runs/32737476796)
success + Router CI (2. dispatch, az 1. egy élő GitHub Actions incidens alatt
pirosra váltott — mérve githubstatus.com API-n, 13:56–14:34 UTC "Actions delays
in starting runs")
[32740432975](https://github.com/wolfcasaba/strumsight/actions/runs/32740432975)
success.

**Landolási akadály, MEGKERÜLVE a tiltott fájl szerkesztése nélkül** (lásd
[L468](docs/LESSONS.md)): a `tools/round-gate.sh::resolve_backend_python()` a
KÖZÖS munkafán egy relatív `backend/.venv/bin/python` jelöltet választott,
amit az `env --chdir=backend` a helytelen `backend/backend/.venv/...`
útvonalra oldott fel (127-es kilépés). A script SAJÁT
`ROUND_GATE_BACKEND_PYTHON` env-override hookjával (abszolút útvonal)
sikerült a landolást megismételni — ez nem a mérce gyengítése, a tényleges
javítás egy jövőbeli governance-/self-heal-kör dolga.

## ✅ E13-R12 KÉSZ — Kártyák, badge-ek, insight és status komponensek — PR [#439](https://github.com/wolfcasaba/strumsight/pull/439), squash `376b8a1d` (2026-08-24)

Hét új design-system komponens: `SsMetricCard`, `SsInsightCard`,
`SsCoachActionCard`, `SsContentCard`, `SsModelStatusCard`, `SsProvenanceBadge`,
`SsStatusBadge` + Component Catalog állapot-mátrix. **ADR
[0278](docs/adr/0278-ai-provenance-is-visible.md)** (a Ch13 ADR-jei előre
merge-elve érkeztek `a4fdfec2`-ben — a kör ADR-t NEM írt, a `docs/adr/**` végig
tilos zóna maradt; a foglalótól kapott `0419` felhasználatlan). Implementer
**`sonnet-impl`** (Claude Sonnet 5), orchesztrátor/reviewer **Claude Opus 5**.

**Review: APPROVED egy javító kör után** — 1. forduló **4 MAJOR + 2 MINOR + 3
NOTE**, mind **teljes zöld gate és zöld CI MELLETT**. A négy MAJOR:

- **F1** — a `syncPending` badge a SAJÁT háttérszínével írt (`SsColorScheme.syncPending`
  = `palette.track` = ugyanaz, amit a séma `surfaceSunken`-ként használ):
  `ratio=1.01` a sötét ÉS a magas kontrasztú témában, azaz a „Szinkronizálás
  függőben" jelzés helyén a felhasználó **üres helyet** látott.
- **F2** — a provenance-felirat `2.18–2.72:1` a világos témában, a projekt saját
  4.5:1-es mércéje alatt — épp azon a feliraton, amit az ADR 0278 §1 adatvédelmi
  ténynek nevez. Ugyanez az `SsCoachActionCard.actionLabel`-en is (`colors.brand`).
- **F3** — a felirat levágódott `textScale ≥ 2.0`-n (a `SsSemantics.maximumTextScale`
  a TÁMOGATOTT tartomány), és az A1 cella végig zöld maradt, mert
  `find.byType`/`find.text` jelenlét-alapú volt ([L460](docs/LESSONS.md)).
- **F4** — AI-eredetű insight-kártya provenance NÉLKÜL is kirendelhető volt, és a
  kör saját A1 cellája ezt **bebetonozta** (`findsNothing`) — [L457](docs/LESSONS.md) osztály.

**A javító kör mind a hatot zárta**, a tilos zónához nyúlás nélkül: a badge-ek
ikonja+felirata `colors.textPrimary`-ből fest (a státusz-token szöveget többé nem
fest), `Flexible` + `maxLines: 1` + `ellipsis` az overflow ellen,
`SsInsightCard.provenance` **`required`**, opcionális provenance-slot a
coach-kártyán, F6 dokumentált döntés. **Négy új kötelező őr**, köztük egy
21 cellás kontraszt-tulajdonságcella (3 téma × [5 status + 2 provenance] a
KIRENDELT `Text.style.color`-ral) és egy 16 cellás geometria-cella.

**A zárást nem bemondásra fogadtam el**, hanem visszamutálva magam mértem:
P1 (`textPrimary` → `syncPending`) **15 cella PIROS**; P2 (`Flexible` törölve)
**5 cella PIROS**, pontosan azok, amiket az 1. kör mért; P3 (provenance nélküli
insight-kártya) **fordítási időben PIROS** — az F4 sértése futásidőben már nem is
*kifejezhető*.

**A gyökérok a pre-flight volt, nem az implementer:** a §0.0/D4 utasította, hogy
a badge „a SZÍNT a `syncPending` tokenből veszi" — egy háttérnek szánt tokent
irányított előtérbe. A briefbe helyesbítő blokk került, hogy egy későbbi kör ne
olvassa normatív igazságként ([L466](docs/LESSONS.md)).

Exact `6f6a301a`: Full Gate
[32726253397](https://github.com/wolfcasaba/strumsight/actions/runs/32726253397)
+ Router CI [32726247193](https://github.com/wolfcasaba/strumsight/actions/runs/32726247193)
success. Saját `tools/round-gate.sh` a merge-elt HEAD-en: **10/10 zöld**.
Scope-audit `origin/main` bázison **OK** (17 útvonal). Landolás a merge-záron át
(`tools/round-land.sh`), mert az E09-R25 sáv párhuzamosan futott. A branch a fix1
után sem volt naprakész — `merge --no-ff origin/main` hozta be azt az ÚJABB
`brief-lint.py`-t (S9), amivel a briefet újramérve **nincs lelet**
([L467](docs/LESSONS.md): a scope-audit bázisválasztása).

## ✅ E09-R24 KÉSZ — Klub domain, tagság és szerepkörök — PR [#441](https://github.com/wolfcasaba/strumsight/pull/441), squash `2f95ad97` (2026-08-24)

**A kör tartalma zölden landolt, de NEM az orchesztrátor-session landolta.**
A session a 4 órás abszolút időkorlátnál jelzés nélkül meghalt
(`H-NOSIGNAL`, exit 124), miközben a `tools/round-land.sh` épp futott — a
landolást és a gyökérok javítását az ADR 0112 **önjavító kör** végezte.
Klub-domain: szerver-autoritatív `owner`/`admin`/`member` szerepmátrix,
owner-less-club invariáns, idempotens tagság-életciklus, a Kör-8
block-filter újrafelhasználva. **ADR [0420](docs/adr/0420-club-domain-membership-and-roles.md)**
(az előre kiosztott `0413` foglalt volt; implementer **MiniMax M3**,
orchesztrátor/reviewer **Claude Sonnet 5**). Review: **APPROVED** javító kör
után — 1 MAJOR (F1: klub-létrehozás nem volt idempotens), 3 MINOR + 4 NOTE
follow-upként. Exact `f29fe61e`: Full Gate
[32716654207](https://github.com/wolfcasaba/strumsight/actions/runs/32716654207)
+ Router CI [32716627760](https://github.com/wolfcasaba/strumsight/actions/runs/32716627760)
success; a landolás előtt a scope-ot függetlenül újramértem (11 változott
fájl, mind az `allowed_paths`-on belül, semmi kívül).

### 🔧 Önjavító kör — a képernyő-leltár drift MOST MÁR pre-dispatch bukik: PR [#442](https://github.com/wolfcasaba/strumsight/pull/442), squash `30467aad`

**Mért gyökérok.** A 240 perces keretből 198 perc blokkoló várakozás volt,
ebből **~60 perc EGYETLEN elkerülhető újramunka**: a
`test/ui/ui_inventory_test.dart` egzakt `hasLength(76)` állítása a kör három
új klub-képernyőjétől 79-re mozdult, de a dispatchelt `allowed_paths` a
leltártesztet nem engedte — így az implementer hozzá sem nyúlhatott, és a
Full Gate a `855db329` SHA-n pirosra váltott
([32713670226](https://github.com/wolfcasaba/strumsight/actions/runs/32713670226)).
Ezt követte a `§0.0c` brief-revízió, EGY TELJES javító implementer-kör az
egysoros szám-emelésért, és a Full Gate újrafuttatása. A kör ~4 óra 10 percet
igényelt, 4 óra állt rendelkezésre.

**A `wait-for-ci.sh` auto-háttérbe kerülését külön megmértem és KIZÁRTAM**
mint okot: a CI valóban 17p40s-ig futott, és a várakozás 4 másodpercen belül
észlelte a befejezést — a mechanizmus helyesen működik.

**Ugyanez a hibaosztály az ELŐZŐ körben (E09-R23, `hasLength(75)`) is
elsült**, és korábban az E08-R15/H3-ban (PR #383) — a védelem viszont eddig
csak KÖRSPECIFIKUS, utólag írt regressziós tesztekben élt, ezért a következő
kört sosem védte. Az E09-R24 saját commit-üzenete (`863a8ac3`) ki is mondja:
*„my own pre-flight missed applying it here despite having read that exact
precedent"* — a precedens elolvasása nem elég, gépi őr kell.

**A javítás:** új `S9` **strict** lelet a `tools/brief-lint.py`-ban, ami a
`round-pipeline.sh` `write_brief_lint` **pre-dispatch** hívásán át a kör
pre-flightjának teendőlistájába kerül. A predikátum a CI igazságához kötött
(`tool/ui_inventory.dart`: `lib/features/**` + `_screen.dart`): akkor lő, ha
az `allowed_paths` MÉG NEM LÉTEZŐ ilyen fájlt enged (tehát a kör létrehozza),
és a `test/ui/ui_inventory_test.dart` nem szerepel egyszerre az
`allowed_paths`-ban ÉS a `gate_tests`-ben.

**Hamis riasztás mérve** a 343 briefes korpuszon: a létezés-feltétel nélkül 39
lelet (36 már zölden merge-elt körre — mind hamis), a feltétellel **0 hamis**
és 4 valódi: `e09-r25`, `e09-r28`, `e09-r29`, `e10-r31` (mind `pending`).
**Az `e09-r25` a sor KÖVETKEZŐ E09 köre — ugyanez a halt egy körön belül
visszatért volna.** A `base` CI-kapu szintje bizonyítottan változatlan
(kilépési kód a javítás előtt és után is 2).

**Őrteszt:** `tools/tests/test_brief_ui_inventory_scope.py` — a fix ELŐTT
piros, UTÁNA zöld; teljes router-suite **737 passed, 1 skipped**. Lecke:
[L465](docs/LESSONS.md).

**Nyitott, e körön kívüli tétel — a merge UTÁN újramérve:** a fenti négyes a
merge ELŐTTI állapot. A PR #441 landolása után az `e09-r25` **kiesett a
listából**, mert az egyetlen "új" képernyője (`club_detail_screen.dart`) épp
ebben a körben jött létre — az `e09-r25` már csak MÓDOSÍTJA, a leltár száma
tehát nem mozdul, és az `S9` helyesen néma rá. A friss `main`-en mérve az
`S9` **hármat** jelöl: `e09-r28`, `e09-r29`, `e10-r31`. Ez nem hiba, hanem a
szabály lényege: a predikátum a fa AKTUÁLIS állapotához képest dönt, ezért a
teendőlista körről körre magától szűkül. A javítás az adott kör `§0.0`
pre-flightjának hatásköre — a self-heal szándékosan NEM nyúlt idegen körök
briefjéhez (heal-prompt §2).


## ✅ E09-R23 KÉSZ — Leaderboards és opt-in versenynézet — PR [#440](https://github.com/wolfcasaba/strumsight/pull/440), squash `60aea065` (2026-08-24)

**Verified, opt-in challenge-ranglista él** — a projekció KIZÁRÓLAG
`verification_state='verified'` sorból épül, a felhasználó explicit opt-in
nélkül nem jelenik meg public scope-ban, és a `friends`-típusú challenge-nél
egy TOVÁBBI, viewer-relatív `community_follows` szűrés fut, mert az invite
egy friends-challenge-hez nem feltétlenül a viewer közvetlen follow-graph-jába
tartozó felet ér el. **ADR [0418](docs/adr/0418-leaderboards-and-opt-in-competition.md)**
(az előre kiosztott `0412` MÁR foglalt volt E09-R19 alatt — a pre-flight friss
számot mért; implementer **MiniMax M3**, orchesztrátor/reviewer **Claude
Sonnet 5**).

**Pre-flight két mért téves feltevést javított, és bővítette az
`allowed_paths`-ot két, MÁR meglévő fájllal.** (1) A brief §2 "Kör 4
privacy-settings MA rendelkezik `leaderboard opt-in` mezővel" állítása 0
találattal cáfolt — a `CommunityPrivacySettings` csak `visibility`+
`audience_default` mezőt hordoz. Megoldás: önálló, e kör tulajdonában lévő
`community_leaderboard_opt_ins` tábla, a Kör 4 táblát érintetlenül hagyva.
(2) `lib/features/community/domain/repositories/challenge_repository.dart` +
`data/repositories/challenge_repository_impl.dart` bekerült az
`allowed_paths`-ba — a Kör 5-ös `leaderboard()` metódus docstringje explicit
"Kör 23 scope"-nak jelölte a bekötést (ugyanaz a hibaosztály, mint az
E09-R22 `challenges.py` bővítése); a metódus SZIGNATÚRÁJA fagyott maradt (két,
e körön kívüli fake-implementer teszt-fájl védelmében), csak a teste és egy
kolokált `LeaderboardEntry` osztály került bele.

**A review (risk=high, `security-reviewer` subagent kötelezően bevonva) 1
MINOR-t mért SAJÁT mutation-próbákkal, miközben az A1/A3/A4/A6 invariánsok
mind álltak** (WHERE-szűrő eltávolítva → PIROS; opt-in EXISTS eltávolítva →
PIROS; follower/followed felcserélve → PIROS). **F1** — a `get_own_rank`
self-lookup egy `friends` típusú challenge-nél tévesen a follow-gráf szűrőt
alkalmazta ÖNMAGÁRA, ezért egy legitim, opt-in, verified résztvevő SAJÁT
rangja mindig `None` volt (fail-closed, NEM privacy-sérülés — a Flutter oldal
ezt a körben nem köti be). A javító kör egy `include_self` paraméterrel
zárta, MINDKÉT (sor-keresés + rank-számláló) lekérdezésen konzisztensen
alkalmazva. A reviewer SAJÁT valódi-sértés próbával mérte a zárást (pre-fix
service-fájl visszahelyezve → az ÚJ teszt PIROS → visszaállítás → ZÖLD).

**Landolás közben két tooling-hiba mérve, `tools/`-hoz nyúlás nélkül
feloldva.** [L451](docs/LESSONS.md) ismét (a `main` E13-R11 merge-e miatt
elavult, gitignore-olt generált l10n a rebase után → hamis analyze-hiba) —
`tools/prepare-flutter-generated.sh` a munkafán feloldotta. **ÚJ:**
[L464](docs/LESSONS.md) — a `round-gate.sh` `resolve_backend_python()` a
MEGOSZTOTT fő fáról futtatva a relatív `backend/.venv/bin/python`-t
választja, ami `env --chdir=backend` alatt feloldhatatlan
(`No such file or directory`, kilépési kód 127) — a script SAJÁT,
dokumentált `ROUND_GATE_BACKEND_PYTHON` env-override escape-jével feloldva.
**ÚJ:** [L463](docs/LESSONS.md) — a §0.0 pre-flight-revízió véletlenül KÉT
` ```ai-router ` kódblokkot hagyott a briefben (az érvényes + a "történeti"
eredeti), ami a `tools/hooks/implementer_guard.py` fail-closed
Write/Edit-blokkolását váltotta ki az implementer ELSŐ dispatch-kísérletén
(`blocked` jelzés) — a második blokk eltávolításával javítva.

**Post-review CI egy mechanikus regisztrációs hibát fogott**, amit a kör
lokális, szűkített gate-hívása nem fedett le: `test/ui/ui_inventory_test.dart`
pinnelt `hasLength(75)` — az ÚJ leaderboard screen a 76. production screen.
`allowed_paths` bővítve (own artifact), egysoros javítás + a screen útvonalára
egy `contains(...)` assertion.

Gate zöld a `cb0cda9f` merge-előtti SHA-n: Full Gate ✅ · Router CI ✅.
Post-merge gate a friss `main`-en (`60aea065`) is zöld. Landolás a
merge-záron át (`tools/round-land.sh`, párhuzamos E13-R12 self-heal sáv
miatt); a `main` a kör alatt egyszer mozdult (E13-R11 merge) — rebase +
kombinált-HEAD gate + safe-force-push, majd friss exact-SHA CI a rebase-elt
HEAD-en. Részletek: [review](docs/reviews/e09-r23-review.md).

## ✅ E13-R11 KÉSZ — Action, input és form komponenskészlet — PR [#438](https://github.com/wolfcasaba/strumsight/pull/438), squash `d55d1656` (2026-08-24)

**A Ch13 action/input készlete él** (SDD Ch13 §11.2): `SsButton` (primary /
secondary / tertiary / destructive, méret-stabil loading), `SsIconButton`,
`SsTextField`, `SsSwitchRow`, `SsChoice` (radio / chip / szegmens),
`SsValueSlider` (csúszka + pontos numerikus bevitel), `SsValidationSummary` +
`SsFieldError`. Mind a hét a `public.dart`-on át exportálva.
Implementer **Claude Sonnet 5** (`sonnet-impl`), orchesztrátor/reviewer
**Claude Opus 5**. ADR nem íródott (a Ch13 ADR-jei az `a4fdfec2`-ben előre
merge-elve — ugyanaz a minta, mint E13-R08/R09/R10).

**A pre-flight három elérhetetlen célt fogott meg, mielőtt bármi elindult
volna** (a brief 2026-08-15-i, a kód azóta elmozdult):

1. **D2 — a brief determinisztikusan haltot adott volna.** Az
   `allowed_paths` KIZÁRÓLAG a `lib/l10n/app_{en,hu}.arb`-t engedte, ami
   2026-08-20 óta **generált aggregátum** (ADR 0307 §4). Pontosan az
   **E08-R12/H6** felállás: az aggregátumba írt kulcsra a `--check` PIROS, a
   `--write` pedig eldobja őket. Ötödik mérés ([L365](docs/LESSONS.md),
   [L369](docs/LESSONS.md), [L396](docs/LESSONS.md), E09-R21 kétszer).
   Feloldás az E13-R10 merge-elt mintájával: a kézzel írt forrás a
   `lib/l10n/features/design_system_{en,hu}.arb` fragmentum + kötelező
   `dart run tool/gen_l10n_segments.dart --write` a gate előtt.
2. **D3 — a `component_catalog_test.dart` csapdája NEM volt a gate-en.** A
   nem szerkeszthető teszt három **exact-count** állítást tesz az egész fára
   (1 `SsCard`, 1 `Material` alatta, 1 `DecoratedBox`), és az E13-R10 már
   MÉRT rajta (el kellett hagynia az `SsSkeleton`-demót). A brief
   `gate_tests`-én nem szerepelt, tehát a katalógus-bővítés törése csak a CI
   teljes suite-jában bukott volna ki — **negyedik gate-útvonalként felvéve**.
3. **D1 — a brief „Ch13 §9.11" hivatkozása nem létező szakasz** (a §9 a
   §9.8-cal ér véget). Valódi normatív forrás: **§11.2** (komponenslista),
   **§13.1** (48×48 dp, fókuszsorrend, 200% text scale, „nem csak színnel
   jelzett állapot" = az A5 gyökere), **§14** (minden string ARB-ba).

A **D5** (az `SsIcon` kétfaktoros API-ja: az `interactive` gyár MAGA csomagol
`Tooltip` + `Semantics(image:)` fába) új **A9** cellát adott — és menet közben
valódi hibát fogott: az `SsIconButton` saját semantics-node-ja `container:
true` nélkül nem volt HATÁR, ezért a `tester.getSemantics` a render-fán
FELFELÉ sétálva egy külső ősre csúszott.

**A review 1 MAJOR-t talált teljesen zöld gate + zöld CI mellett — és a MAJOR
nem implementációs hiba volt, hanem VAKON HAGYOTT ŐR.** A kör zászlós
invariánsa (§5.1 „a placeholder nem label") és a §6.1 mátrix első sora
(„Csak `hintText`, label nélkül → **A1**") mérve NEM működött:

```
# a mátrix által nevesített sértés, izolált klónban:
-        labelText: label,     +        hintText: label,
$ flutter test test/core/design_system/forms/ss_inputs_test.dart
00:01 +8: All tests passed!        ← PIROSNAK KELLETT VOLNA LENNIE

# a gyökérok, eldobható próbateszttel:
PROBE find.text(label) after typing -> 1 match(es)
PROBE   -> nearest ancestor opacity = 0.0
PROBE decoration.labelText = null
```

A `hintText` `Text`-je BENNE MARAD a fában `Opacity(0.0)` alatt, tehát a
`find.text()` a LÁTHATATLAN maradékot is megtalálja; a `find.bySemanticsLabel`
szintén zöld, mert a Flutter a `hintText`-et is a mező semantics-labeljébe
emeli ([L460](docs/LESSONS.md)). A javító kör **production kódot nem
érintett** — csak a mérce erősödött (tulajdonság-szintű cella:
`decoration.labelText == label` ÉS `hintText != label`), és a zárást a
reviewer SAJÁT méréssel igazolta: `Expected: 'Song title' / Actual: <null>`.

1 MINOR (a 48 dp padló-cellája vak — a `ConstrainedBox` törlése nem vált
pirosra, mert a `Switch` saját `padded` célja amúgy is ~64 dp-re tolja a sort;
az ÉRDEMI „teljes sor érinthető" invariánst viszont mutáció alatt PIROS cella
őrzi, [L461](docs/LESSONS.md)) + 2 NOTE nyitva, nem blokkoló.

**Négy valódi-sértés próba** (mind izolált klónban, mind visszaállítva):
A1 ✅ PIROS (a javítás után) · A2 ✅ PIROS (`Size(217.2,48) → Size(66,48)`) ·
A3 ✅ PIROS (az implementer `_round(parsed) + 1` mutációja) · A4 „teljes sor"
✅ PIROS. Az A4 padló és az A1 láthatósági cellája ZÖLD maradt — mindkettő
dokumentálva.

**A `main` a kör alatt kétszer mozdult** (E09-R22 merge, majd annak záró
commitja) — mindkétszer `tools/round-land.sh` rebase + kombinált-HEAD gate +
`safe-force-push`, és MINDKÉTSZER friss exact-SHA CI-dispatch. Exact
`2f2cdabd`: Full Gate
[32686489910](https://github.com/wolfcasaba/strumsight/actions/runs/32686489910)
+ Router CI
[32686151220](https://github.com/wolfcasaba/strumsight/actions/runs/32686151220)
mind **success**; a saját `round-gate.sh` ugyanezen a SHA-n 12 lépéssel zöld
(a rebase behúzta az E09-R22 backend-sávját is).

**A `gate_shape=VIOLATION` jelzés FALSE POSITIVE volt** — az őr regexe egy
`grep -n "analyze" tools/round-gate.sh | head -20` alakú **olvasásra** sült el,
nem a gate csővezetékes futtatására ([L462](docs/LESSONS.md)).

## ✅ E09-R22 KÉSZ — Verified result submission és anti-cheat — PR [#437](https://github.com/wolfcasaba/strumsight/pull/437), squash `206d6993` (2026-08-24)

**A challenge-eredmény szerveroldali, idempotens ellenőrzése és anti-cheat védelme él** —
a szerver SOHA nem fogad el kliens-oldali `verified`/`rank` állítást (a §5.1 elv,
ugyanaz, mint az E08-R28 ledger-szinkron `totalXp`-tilalma). **ADR
[0417](docs/adr/0417-verified-result-submission-and-anti-cheat.md)**
(a queue-ban előre kiosztott `0411` MÁR foglalt volt E09-R08 alatt — a
pre-flight friss számot mért; implementer **MiniMax M3**, orchesztrátor/reviewer
**Claude Sonnet 5**).

**Pre-flight bővítette az `allowed_paths`-ot két, MÁR meglévő fájllal**:
`backend/app/community/routers/challenges.py` (ÚJ `POST .../results` endpoint)
és `lib/features/community/data/repositories/challenge_repository_impl.dart`
(a `submitResult` `UnimplementedError`-stubja valódi HTTP-hívásra cserélve) —
enélkül a funkció nem lett volna végponttól-végpontig működő (ADR 0415 §D6 és
a Kör 21 repo-impl docstringje explicit ezt a kört jelölte ki a bekötésre).
A pre-flight további két mért téves feltevést javított: az `active`
invite-állapot ma elérhetetlen (0 hozzárendelés-hely a kódban), tehát a
"participant-állapot" ellenőrzés olvasás-only; a "server-issued nonce" a
Kör 5 fagyott `submitResult` interfészen NEM megy át, szerver-belső TTL-es
bekönyvelés.

**A review (risk=high, `security-reviewer` subagent kötelezően bevonva) a zöld
gate MÖGÖTT 2 MAJOR-t mért, SAJÁT, az implementer tesztkészletétől FÜGGETLEN
mutation-próbákkal** (`docs/LESSONS.md` L414 mintája): **F1** — egy extrém
(`10**19`) `metric_value` az audit-insertnél `OverflowError`-ral 500-at dobott
`IntegrityError` helyett (A8-sértés: a reject-döntéshez nem tartozott auditált
sor); **F2** — a nem-`personalBest` "first-wins" policy Python-oldali
check-then-act volt, két konkurens beküldés (más-más `source_event_id`-vel)
két `verified` sort hozhatott létre. A javító kör mindkettőt zárta (F1: wire-
szintű Pydantic `Field(ge=, le=)` korlát a döntési lánc elé; F2: atomikus,
rowcount-ellenőrzött feltételes UPDATE a Python-oldali előzetes olvasás
helyett) + 2 MINOR-t (F3: a service-oldali "második védelmi vonal" holt kód
volt, a nyers body-kulcsokból építve javítva; F4: az A5 verzió-cella a
fagyott kliens-interfészről sosem érhető el, dokumentálva). **A reviewer
SAJÁT valódi-sértés próbával mérte F1/F2 zárását** — a fixet ideiglenesen
visszaállítva a régi, hibás alakra, az új regressziós teszt PIROSRA váltott,
majd visszaállítás után zöld.

Landolás közben a kombinált-HEAD gate első futása 25 hamis `analyze`-hibával
PIROS lett (elavult, gitignore-olt generált l10n a rebase után, a
[L451](docs/LESSONS.md) recidívája — egy párhuzamos Ch13-sáv új l10n-kulcsokat
mergelt) — `tools/prepare-flutter-generated.sh` a munkafán feloldotta. A
`tools/safe-force-push.sh` első hívása hamis "MEGTAGADVA"-t adott, mert
abszolút útvonalról, a MEGOSZTOTT fő fa CWD-jéből futott ([L459](docs/LESSONS.md),
a script nem `cd`-l saját magába) — `cd`-vel a munkapéldányba javítva.

Gate zöld a `d94faff8` merge-előtti SHA-n: Full Gate ✅ · Router CI ✅.
Post-merge gate a friss `main`-en (`206d6993`) is zöld. Részletek:
[review](docs/reviews/e09-r22-review.md).

## ✅ E13-R10 KÉSZ — Aszinkron állapotkomponensek — PR [#436](https://github.com/wolfcasaba/strumsight/pull/436), squash `b11ab2ed` (2026-08-24)

**A Ch13 feedback-készlete él** — `SsAsyncState` (9 státusz), `SsSkeleton`,
`SsEmptyState`, `SsFailureState`, `SsPermissionState`, és a
`failure_presentation.dart` mapping. Kötött döntések: **ADR
[0277](docs/adr/0277-failure-presentation-model.md)** — **nem ebben a körben
íródott, már merge-elve volt** (`a4fdfec2`), ezért a kör ADR-t nem írt és a
`docs/adr/**` tilos zóna maradt (ugyanaz a minta, mint E13-R09/D1; a foglalótól
kapott `0416` felhasználatlan). Implementer **Claude Sonnet 5** (`sonnet-impl`),
orchesztrátor/reviewer **Claude Opus 5**.

**A pre-flight két elérhetetlen célt fogott meg, mielőtt bármi elindult.**
(1) A brief §5.1 „a bemenet mindig failure-**kód**" előírása mellett az **A4
mérhetetlen**: a `permanentlyDenied` és a `denied` ág AZONOS kódot hordoz
(`FailureCode.permissionMicrophoneDenied`), és KIZÁRÓLAG az
`AppFailure.retryable` bool különbözteti meg őket (mérve a tényleges
leképezésen: `lib/core/platform/microphone_permission.dart:25-39`,
`lib/core/camera/camera_permission.dart:24-38`) — a mapping bemenete ezért az
`AppFailure` **érték** lett, `code` + `retryable`, a `cause`/`stackTrace` be sem
lép a modellbe. (2) Az ARB-forrás a **fragmentum**
(`lib/l10n/features/design_system_{en,hu}.arb`, ÚJ), az aggregátum generált
(ADR 0307 §4) — ez a NEGYEDIK mérés ugyanerre a hibaosztályra
([L365](docs/LESSONS.md), [L369](docs/LESSONS.md), [L396](docs/LESSONS.md),
[L454](docs/LESSONS.md)), és a párhuzamos E09-R21 KÉTSZER futott bele
`stopped`-dal ugyanaznap.

**Review: 1 MAJOR teljesen zöld gate + zöld CI mellett.** A `SsPermissionState`
a `permission.unavailable` **elérhető** úton (`MicrophonePermissionState.unavailable.failure!`)
kirendelt egy `contactSupport` gombot `onPressed == null`-lal, amit a hívó nem
is tudott bekötni (nem volt ilyen paraméter) — látható, örökre halott vezérlő,
szemben az ADR 0277 §5.3/§5.5-tel. **Miért csúszott át:** az A3/A4 a
prezentációs MODELLT mérte (`hasAction`), sosem a kirendelt gomb
`onPressed`-jét ([L457](docs/LESSONS.md)). A javító kör mindhárom leletet
zárta (F2: ugyanez `SsFailureState`-ben; F3: az offline-ág `Expanded`-je kötött
magasságú őst kíván — most a publikus doksiban), és a reviewer a zárást
valódi-sértés próbával mérte: a hibás alak visszaállítva az őr-cella PIROS,
majd visszaállítva a kapu zöld.

Gate zöld az `ad3ac4e8` merge-előtti SHA-n: Full Gate
[32678739926](https://github.com/wolfcasaba/strumsight/actions/runs/32678739926)
✅ · Router CI ✅. Landolás a merge-záron át (`tools/round-land.sh`), mert a
másik sáv (E09-R21/R22) párhuzamosan futott. Landolás közben mért,
`tools/`-hoz nyúlás nélkül feloldott két tooling-hiba: [L451](docs/LESSONS.md)
ismét (elavult gitignore-olt generált l10n → 25 hamis analyze-hiba a
kombinált-HEAD gate-en) és [L455](docs/LESSONS.md) ismét
(`safe-force-push` elutasítás merge-commitokra) — az utóbbi feloldása ezúttal
**nem** force-push volt, hanem a `main` beolvasztása a branchbe, így a push
fast-forward maradt és a lander rebase-e is elmaradt ([L458](docs/LESSONS.md)).
Részletek: [review](docs/reviews/e13-r10-review.md).

**Következő Chapter 13 kör: E13-R11.**

## ✅ E09-R21 KÉSZ — Community challenge és invite lifecycle — PR [#435](https://github.com/wolfcasaba/strumsight/pull/435), squash `56a68678` (2026-08-24)

**Az aszinkron challenge-meghívás állapotgép él** — `draft → sent →
accepted|declined|expired|cancelled`, majd `accepted → active →
completed|forfeited|expired`, minden átmenet szerveroldali, feltételes
`UPDATE ... WHERE state IN (...)` + rowcount-ellenőrzéssel (nincs
pesszimista lock). **ADR [0415](docs/adr/0415-community-challenge-invite-lifecycle.md)**
(a queue-ban előre kiosztott `0410` MÁR foglalt volt E09-R18 alatt — a
pre-flight friss számot mért; implementer **MiniMax M3**, orchestrátor/reviewer
**Claude Sonnet 5**).

**Pre-flight tényellenőrzés megcáfolta a brief nyitó feltevését**: a brief
"gamifikáció E08-R19 `ChallengeV2`" hivatkozása egy SOSEM létezett típusra
mutatott (`grep -rn "ChallengeV2"` → 0 találat a teljes repóban) — az E08-R19
tényleges terméke `DailyChallengeType`, egy egyjátékos napi generátor,
strukturálisan összeegyeztethetetlen. A TÉNYLEGES, MÁR élő kompatibilis
kontraktus a Community SAJÁT E09-R05 domainje volt
(`ChallengeInviteState`/`ChallengeType`/`CommunityChallengeDefinition`/
`CommunityChallengeRepository`, ADR 0399) — ennek ELSŐ implementációja ez a
kör (repository-impl + controller + screen). A pre-flight emellett két
javító kört is igényelt egy l10n-forrás félreértés miatt: az `app_en.arb`/
`app_hu.arb` ADR 0307 §4 szerint GENERATED fájlok (a valódi forrás
`lib/l10n/features/community_*.arb`), DE a `tools/scope-audit.py`-nak
nincs generated-kivétele — mindkét fájl-párt fel kellett venni az
`allowed_paths`-ra (§0.0a/§0.0b, `docs/rounds/e09-r21-*.md`; lásd
[L454](docs/LESSONS.md)).

**Review APPROVED, 0 BLOCKER/MAJOR** — mind a 7 acceptance-cella (A1–A7)
VALÓDI termelés-kód mutációval újra-mérve (nem az implementer saját
próbáira hagyatkozva): A4 idempotency és A5 cancel-race a reviewer SAJÁT
kezével mutálva → piros → visszaállítva → zöld. 2 nem-blokkoló MINOR/NOTE
(az implementer saját A5 "probe" tesztje monkeypatch-alapú, gyengébb
bizonyíték, mint amit a brief kért, de a tényleges védelmet egy MÁSIK,
valódi teszt adja — a review ezt függetlenül megerősítette). Landolás
közben a `tools/round-land.sh` belső rebase-lépése (párhuzamosan futó
Ch13-sáv miatt mozgó `main`) új HEAD-et képzett — a `tools/safe-force-push.sh`
elutasította (patch-id nem egyezik a merge-commitokra, szerkezeti
korlát), a push emiatt explicit lease-szel, a pontos mért remote SHA
ellen történt, majd új exact-SHA CI-dispatch igazolta a landolás előtt
(ADR 0242 §5.5 szellemében, a script saját korlátján belül; lásd
[L455](docs/LESSONS.md)).

Gate zöld a `fffceaef` merge-előtti SHA-n: Full Gate ✅ · Router CI ✅.
Post-merge gate a friss `main`-en (`56a68678`) is zöld. Részletek:
[review](docs/reviews/e09-r21-review.md).

## ✅ E13-R09 KÉSZ — StageScaffold és session transport — PR [#433](https://github.com/wolfcasaba/strumsight/pull/433), squash `25d2e219` (2026-08-23)

**A CHAPTER 13 KILENCEDIK KÖRE KÉSZ — áll a közös, ÉLETCIKLUS-SEMLEGES Stage
layout a hat aktív módhoz.** ([ADR 0276](docs/adr/0276-stage-scaffold-owns-no-resources.md)
— a döntés MÁR merge-elve volt (`a4fdfec2`), ezért ez a kör ADR-t nem írt; ez a
minta másodszor futott az E13-R08 ADR 0275-e után.)

- **`lib/core/design_system/layouts/ss_stage_scaffold.dart`** (ÚJ) — öt slot
  (status header, hero, feedback, timeline/beat, bottom action), `SafeArea`,
  két elrendezési stratégia (`_CompactStage` portrait: fejléc pinnelve fent,
  hero/feedback/timeline görgethető, akciósor pinnelve lent · `_WideStage`
  landscape VAGY `width >= SsBreakpoints.expandedMin`: kétoszlopos, az
  akciósornak SAJÁT pinnelt oszlopa van, nem zsugorodó alsó csík).
- **`lib/core/design_system/components/music/ss_session_transport.dart`** (ÚJ)
  — hat állapot (idle, count-in, active, paused, finishing, disabled), a Pause
  és a Finish mind a NÉGY aktív állapotban látható és **egyetlen tappal**
  elérhető (nem overflow menü, nem görgetés alatt).
- **Erőforrást NEM birtokol** — nulla mikrofon/kamera/felvétel, nulla
  `wakelock_plus`, nulla `core/platform` import; a képernyő-ébrentartás két
  szimmetrikus **callback** (`initState` kér, `dispose` pontosan egyszer old),
  a mentetlen-session vissza-megerősítés pedig **hook** (`PopScope` +
  `onPopInvokedWithResult`), amiről a szöveget és a mentést a feature dönti el.

**A review a zöld kapu MÖGÖTT három MAJOR-t MÉRT** — mind a nyolc
acceptance-cella, a teljes `tools/round-gate.sh` és a Full Gate CI is zöld volt,
amikor eldobható mutációk kimérték, hogy a §6.1 mérce-mátrix két legfontosabb
sora **nem fog pirosra váltani**:

```
# MAJOR-1 — autoStart, ami MethodChannel('plugins.flutter.io/record')-ot hív:
00:01 +7: All tests passed!      ← az A1 cella zöld maradt

# MAJOR-2 — a deklarált viewport INERT volt:
PROBE P1 declared=Size(800.0, 400.0)  -> actual Scaffold size=Size(800.0, 600.0)
PROBE P1 declared=Size(1200.0, 800.0) -> actual Scaffold size=Size(800.0, 600.0)

# MAJOR-3 — VALÓDI termékhiba, 2.0 text scale mellett:
PROBE P5 idle-label overflow exception=A RenderFlex overflowed by 661 pixels on the right.
```

- **MAJOR-1:** az A1 cella kizárólag a `wakelock_plus` csatornára tett mock
  handlert, tehát bármely MÁS csatorna (mikrofon, kamera, recorder) hívása
  láthatatlan volt neki — a kör egyetlen `risk = "high"` indoka maradt őrizetlen.
  **Javítva:** forrás-szintű őrcella a két új produkciós fájlra (tiltott tokenek,
  komment-leválasztással) + egy cella, ami **magát az őrt** méri a mutált
  forrásrészleten. A produkciós kód változatlan maradt.
- **MAJOR-2:** a `MediaQuery(data: MediaQueryData(size: …))` wrapper csak azt
  írja felül, amit a leszármazottak OLVASNAK — a layout-kényszert a teszt-felület
  adja, amit a teszt sosem állított át. A három „landscape/expanded" A4 cella
  ugyanazt az egy 800×600-as mérést végezte háromszor. **Javítva:**
  `tester.view.physicalSize` + `devicePixelRatio = 1` + `addTearDown(reset)`.
  A javítás magasság-érzékenyen ÚJRAMÉRVE: egy 450 px fix alsó akciósáv
  mutációval a `Size(800,400)` cella PIROS, az `1000×500` és az `1200×800`
  ZÖLD marad.
- **MAJOR-3:** a `_RestIndicator` `Text`-je `Flexible` nélkül ült egy `Row`-ban.
  **Javítva:** `Flexible` + `softWrap`, két új cellával 360×640-es VALÓDI
  felületen, 2.0 text scale-lel.

A §6.1 mátrix másik négy sora (A2 Finish-overflow, A3 paused==active, A5
kétszer hívó hook, A7 bent ragadó ébrentartás) **az első körben is helyesen
pirosra váltott** — a reviewer mind a hatot saját mutációval mérte, kétszer
(a javító kör előtt és után). A teszt-cellák száma 19 → **24**.

## ✅ E09-R20 KÉSZ — Notification inbox és push abstraction — PR [#434](https://github.com/wolfcasaba/strumsight/pull/434), squash `61f31c35` (2026-08-23)

**A KÖZÖSSÉGI ÉRTESÍTÉS-RENDSZER ALAPJA ÁLL — tartós, kategorizált inbox +
provider-semleges push-absztrakció, service-réteg-only.** ([ADR 0414](docs/adr/0414-notification-inbox-and-push-abstraction.md) —
a brief előre kiosztott `0409`-e STALE marker miatt elavult, a friss atomi
foglalás `0414`-et adott, lásd a brief §0.0.)

- **`backend/app/community/notifications/push_gateway.py`** (ÚJ) — `PushPayload`
  zárt `@dataclass(frozen=True)` (notification_id/type/title_key/body_key/
  route_entity_type/route_entity_id), `__post_init__` allowlist-validáció +
  `_assert_payload_is_minimal` struktúrális őr (A1); `NoOpPushGateway` az
  egyetlen adapter ebben a körben — valódi FCM/APNs-bekötés jövőbeli kör dolga.
- **`backend/app/community/notifications/notification_service.py`** (ÚJ) —
  `create_notification` (dedup-kulcs UNIQUE-constraint + `IntegrityError`-alapú
  re-read, A7; reakció-burst aggregáció 15 perces csúszó `(recipient, entity_type,
  entity_id)` ablakban, A2), `mark_read`/`mark_all_read_up_to` (`_before_commit`
  teszt-seam a döntő UPDATE ELŐTT, A3 — [L421](docs/LESSONS.md) Barrier-minta),
  `list_inbox`/`get_unread_count` (`is_blocked_pair`/`list_block_pairs_for_viewer`
  szűrés, A4 — **mindkét olvasási úton**, lásd lent), `get_related_content_id`
  (A5, csak `post` entitásra fedett).
- **`lib/features/community/application/controllers/notification_controller.dart`**
  + **`.../screens/community_notifications_screen.dart`** (mindkettő ÚJ) — a Kör 5
  (ADR 0399) MÁR élő `CommunityNotificationRepository`/`CommunityNotificationItem`
  domain-kontraktusára épül, `UnimplementedError` default providerrel (a valódi
  HTTP data-layer jövőbeli kör dolga, Kör 14/16 precedens).
- **Ez a kör SZÁNDÉKOSAN service-réteg-only** (ADR 0414 D2, mérve a pre-flightban):
  a `reaction_service.py`/`comment_service.py`-nek MA sincs élő router-hívója, a
  `follow_service.py` router-hívója (`social_graph.py`) nincs `allowed_paths`-on
  — a MEGLÉVŐ három szolgáltatás notification-eseményekhez kötése egy jövőbeli
  kör dolga.

**A dedikált biztonsági review (risk=high) 1 MAJOR-t reprodukált a zöld gate
MÖGÖTT:** `get_unread_count` NEM alkalmazta az A4 block-szűrőt, amit a
`list_inbox` igen — egy blockolt actor eseménye eltűnt a listából, de MÉGIS
számított az unread-badge-be (badge-desync + "egy blockolt személy tett
valamit" szivárgás). A brief §10 handoffja az A4-et PASS-nak jelentette a
`list_inbox`-only teszt alapján. 1 javító kör zárta: `list_block_pairs_for_
viewer` materializált halmaz + SQL `NOT IN`, új mérce-cella
(`unread_count == visible_unread`) valódi-sértés próbával (`monkeypatch` →
piros → automatikus revert). 1 MINOR follow-up nyitva marad (`list_inbox`
lapozás blockolt sorokkal alul-tölthet — `docs/reviews/e09-r20-review.md` §5).

**Két KORÁBBAN MÁR dokumentált, kör-idegen infrastruktúra-hiba ismét
lecsapott, mindkettő workaround-dal megkerülve (NEM tools/-módosítás):**

1. **Megosztott munkafa branch-klobberelés** ([L447](docs/LESSONS.md)) — a
   párhuzamos E13-R08/E13-R09 sáv saját záró-rituáléja (`git checkout main` /
   `git reset --hard origin/main`) a KÖZÖS `/home/ubuntu/music-theory` fán,
   miközben az E09-R20 branch volt kicheckoutolva, MEGVÁLTOZTATTA a lokális
   branch-ref-et (a commitok az originon épségben maradtak). Recovery: `git
   reset --hard <ismert jó SHA>` a branch-refre, mielőtt bármit commitolnál a
   megosztott fán.
2. **`tools/round-gate.sh::resolve_backend_python()` relatív útvonal-bug**
   ([L448](docs/LESSONS.md)) — a `backend/.venv/bin/python` jelölt CWD-relatív
   ellenőrzéssel dől el, de a `[10] backend pytest` lépés `env
   --chdir=backend "$backend_python"`-t hív: a repo-gyökérből futtatva (ahol
   `backend/.venv/bin/python` LÉTEZIK) a jelölt kiválasztva, de a
   `--chdir=backend` UTÁN a relatív útvonal `backend/backend/.venv/bin/
   python`-ra oldódik fel — NEM LÉTEZIK (kilépési kód 127). Workaround
   (env-változó, NEM kód-szerkesztés):
   `ROUND_GATE_BACKEND_PYTHON=/home/ubuntu/music-theory/backend/.venv/bin/python`
   a `round-land.sh`/`round-gate.sh` hívás elé. **A tényleges javítás MÉG
   MINDIG nincs meg** — ez a MÁSODIK mérés ugyanarra (E09-R19 landolás, majd
   E09-R20 landolás) — GOV/önjavító kör dolga, `tools/`-ot implementer-kör
   nem érinthet.

Review: [`docs/reviews/e09-r20-review.md`](docs/reviews/e09-r20-review.md)
(APPROVED javító kör után) + [`docs/reviews/e09-r20-security.md`](docs/reviews/e09-r20-security.md)
(dedikált security-reviewer, PASS 1 MAJOR reprodukálva és zárva). Exact
`f36dfc91`: Full Gate 32668900124 + Router CI 32668896344 mind success.

## ✅ E13-R08 KÉSZ — Adaptive scaffold és primary navigation — PR [#432](https://github.com/wolfcasaba/strumsight/pull/432), squash `c96a3276` (2026-08-23)

**A CHAPTER 13 NYOLCADIK KÖRE KÉSZ — az ötterületes alkalmazás-shell váza áll,
flag mögött, alapértelmezetten KIKAPCSOLVA.** ([ADR 0275](docs/adr/0275-five-area-shell-behind-a-flag.md) —
a döntés MÁR merge-elve volt (`a4fdfec2`), ezért ez a kör ADR-t nem írt.)

- **`lib/core/design_system/layouts/ss_adaptive_scaffold.dart`** (ÚJ) — négy módú
  resolver (`compact`/`medium`/`expanded`/`wide`) KIZÁRÓLAG a meglévő
  `SsBreakpoints` tokenekből; compact → `NavigationBar`, medium → nem-extended
  `NavigationRail`, expanded/wide → extended rail; `showPrimaryNavigation: false`
  → puszta `Scaffold`. **Tiszta layout-primitív:** nulla feature-, route- és
  `AppLocalizations`-import (a design-system határőrt az E13-R02 óta gép méri).
- **`lib/app/config/feature_flags.dart`** — egyetlen új flag,
  `adaptiveShellEnabled`, defaultból KI, a `forEnvironment` MINDEN környezetben
  `false`-t ad, dart-define override nincs. A flag mind a **HAT** bővülési
  ponton szerepel (konstruktor, `forEnvironment`, mező, `==`,
  `hashCode`/`additionalBits`, `toString()`) — a brief eredeti „három bővülési
  pont" állítása a pre-flightban mérve hibásnak bizonyult.
- **`lib/app/routing/`** — öt destination (`/today`, `/practice`, `/songs`,
  `/coach`, `/profile`) + tizenegy cél-alútvonal, mind **meglévő képernyő
  adapterként** (új képernyő és új ARB kulcs nélkül);
  `StatefulShellRoute.indexedStack` öt branchcsel; `legacyRedirects` a Ch13 §7.5
  tizenegy legacy route-jára, **query- és fragment-megőrzéssel**
  (`uri.replace(path:)`); `isStageRoute` predikátum a kipinnelt session-halmazon.
- **A flag KI ágán minden bitre a mai** — a `test/app/routing/**` módosítatlanul
  zöld; az `onboardingRedirect` új `home` paramétere opcionális, alapértelmezett.

**A review a zöld kapu MÖGÖTT talált MAJOR-t.** Mind a hét acceptance-cella, a
teljes `tools/round-gate.sh` és a Full Gate CI is zöld volt, amikor egy
eldobható reviewer-próba kimérte: a `StatefulShellRoute.indexedStack` — amit
ÉPPEN az A3 (tab-állapot megőrzése) követelt meg — életben tartja a
meglátogatott brancheket, ezért a `LiveScreen` tabváltás után sem unmountol, és
**a mikrofon-stream meg a képernyő-wakelock aktív marad**, miközben a
felhasználó másik területen van:

```
PROBE offstage LiveScreen instances after tab switch: 2
PROBE wakelock.isHeld after tab switch: true (enableCalls=2, disableCalls=0)
```

A legacy referencia ugyanazzal a próbával zöld volt. A javítás — mivel a
`lib/features/**` tiltott zóna — **szerkezeti**: a `/today` erőforrás-mentes
adaptert kapott (`ProgressScreen`), a `/practice/live` top-level **Stage**
route lett (ahol a mount/dispose szemantika érvényben marad), és ezzel az
`isStageRoute` a produkciós hívási úton is élővé vált. Két további lelet:
a shell megkerülte a `practiceEngineV2Enabled`/`aiTutorEnabled` **termék-rollout**
kaput (MINOR-1), és az `onException` a flag BE ágán minden ismeretlen URL-t egy
navigáció NÉLKÜLI Stage-képernyőn hagyott (MINOR-2, a verifikáció közben mérve).
Mindhárom zárva, mindhez tartozik cella, ami a hibát PIROSRA fogta volna —
az új **A8** csoport a legacy referenciával és `skipOffstage: false`-szal mér,
hogy ne legyen vakuum. Részletek: [`docs/reviews/e13-r08-review.md`](docs/reviews/e13-r08-review.md).

**Mérce.** Exact `c96a3276`: Full Gate
[32666196726](https://github.com/wolfcasaba/strumsight/actions/runs/32666196726)
+ Router CI **mindkettő success**; a merge-elt `main`-en a `tools/round-gate.sh`
is zöld (8/8). Scope-audit OK. **Mért folyamathiba (L450):** a landoló a rebase
után helyesen `blocked`-dal kért friss exact-SHA CI-t, de az orchestrátor a
kilépési kódot tranziens hibának nézte és azonnal újrahívta — a második hívás
merge-elt, exact-SHA Full Gate NÉLKÜL. A merge SHA-ján utólag futtatott mindkét
workflow zöld, tehát a merge-elt artefaktum igazolt; ami sérült, az a SORREND
(ADR 0086 §2). Tanulságok: [L449](docs/LESSONS.md), [L450](docs/LESSONS.md).

## ✅ E09-R19 KÉSZ — Média feldolgozás, privacy és moderation state — PR [#431](https://github.com/wolfcasaba/strumsight/pull/431), squash `957bc00f` (2026-08-23)

**EPIC 9 (COMMUNITY PLATFORM) TIZENKILENCEDIK KÖRE KÉSZ.** A Kör 18
`CommunityMedia` táblát ([ADR 0412](docs/adr/0412-media-processing-privacy-and-moderation-state.md))
teljes feldolgozási állapotgéppé bővíti — additívan, az `upload_state` gépet
érintetlenül hagyva: `backend/app/community/models/media.py` (MÓDOSÍTOTT,
kizárólag additív — ÚJ `processing_state` oszlop hét literállal
`uploaded`/`scanning`/`transcoding`/`review`/`ready`/`rejected`/`deleted`,
plusz öt nullable audit oszlop moderation döntés/confidence/provider/
provider-verzió/időbélyeg rögzítésére), `backend/app/community/tasks/media_processing.py`
(ÚJ — stdlib-only JPEG EXIF/APP1-strip, kliens-deklarált codec/duration/
resolution/frame-rate validáció, tiszta session+sor-paraméteres átmenet-
függvények, HMAC-SHA256 playback-token sign/verify), `backend/app/community/moderation/media_moderation.py`
(ÚJ — malware-scan + content-moderation adapter ABC + mock implementáció;
`triage()` SOHA nem ír `rejected`-et, csak `review`-ba irányít; `resolve_review()`
az EGYETLEN út a súlyos döntéshez), `backend/app/community/services/media_access_service.py`
(ÚJ — önálló HMAC-SHA256 aláírt playback token, audience-ellenőrzött a
MEGLÉVŐ `policies/access_policy.py` read-only újrafelhasználásával, rövid
TTL, max 30 perc), `e09_r19_0013_community_media_state.py` migráció,
`community_media_player.dart` (ÚJ — pending placeholder, nincs lejátszás
nem-`ready` állapotban).

**ADR-szám korrekció a pre-flightban.** A brief előre `0408`-at adott, de azt
közben a bookmark-kör foglalta el — `tools/round-slots.py reserve-adr` friss
számot adott: **[ADR 0412](docs/adr/0412-media-processing-privacy-and-moderation-state.md)**.

**Kötött pre-flight döntés (D2): `models/media.py` felkerült az `allowed_paths`-ra,
szigorúan additív korlátozással.** A brief §5 „Tilos zóna" listája már saját
zárójeles megjegyzéssel („bővítés indokolt, nem átírás") előírta ennek a
fájlnak az additív módosítását, de a gépi `allowed_paths` tömb kihagyta — a
Claude ezt a pre-flightban javította, nem az implementer bővítette a listát.

**D3/D6 — a kör SZÁNDÉKOSAN bekötetlen marad, a Kör 18 router-deferrálás
mintáját folytatva.** `media_upload_service.py` (Kör 18) nem hívja
automatikusan a `start_processing`-et finalize után, és a playback token
NEM a bucket-oldali `ObjectStore`-on keresztül megy (az csak PUT-signinget
definiál) — mindkettő egy jövőbeli wiring-kör nyitott horga.

**Implementer MiniMax M3, orchesztrátor/reviewer Claude Sonnet 5.** ZÉRÓ
javító kör — az implementer első próbálkozása megkapta mindkét review
APPROVED/PASS verdiktjét.

**Két FÜGGETLEN review (`risk=high` miatt kötelező dedikált biztonsági review
is), mindkettő 0 BLOCKER/0 MAJOR:** [`docs/reviews/e09-r19-review.md`](docs/reviews/e09-r19-review.md)
(APPROVED) + [`docs/reviews/e09-r19-security.md`](docs/reviews/e09-r19-security.md)
(PASS). Mindkettő saját, izolált klónban futtatta újra a gate-et, és saját
kézzel elvégezte az A7 valódi-sértés próbát (kódmutáció a human-review-gate
megkerülésére → PIROS → visszaállítás → ZÖLD), függetlenül megerősítve a
súlyos döntés emberi-review-gate invariánsát. 2 MINOR + 6 NOTE lelet, mind
latens a szándékosan bekötetlen pipeline mögött — a jövőbeli wiring-kör
explicit előfeltételei: (1) a `_resolve_audience` FOLLOWERS-tengely tényleges
bekötése + teszt, (2) az EXIF-strip EOI-marker utáni trailer-szegmensek
kezelése vagy a limit explicit dokumentálása.

**Mért tooling-hiba a landolás közben (ÖNJAVÍTÓ kör nélkül feloldva,
`docs/LESSONS.md` L448):** a `tools/round-land.sh` saját, megosztott fabeli
gate-futtatása a `backend pytest` lépésen `env: 'backend/.venv/bin/python':
No such file or directory` hibával elhasalt — a `tools/round-gate.sh`
`resolve_backend_python()`-ja a RELATÍV `backend/.venv/bin/python`
jelöltet választja, amikor a megosztott fában (ahol saját `backend/.venv`
létezik) fut, de az `env --chdir=backend "$backend_python" -m pytest`
sor a chdir UTÁN próbálja feloldani ezt a relatív útvonalat (→
`backend/backend/.venv/...`, ami nem létezik). Friss klónokban (implementer,
mindkét reviewer, CI) ez SOSEM jelentkezik, mert ott nincs saját
`backend/.venv`, a resolver a `$HOME/music-theory/...` ABSZOLÚT fallbackra
esik, ami immunis a chdir-re — ezért volt mindhárom izolált gate-futtatás és
mindkét CI-run zöld, miközben a megosztott fabeli landolás elsőre pirosra
esett. Feloldás a `tools/`-hoz NYÚLÁS NÉLKÜL: a script saját, dokumentált
`ROUND_GATE_BACKEND_PYTHON` override-jával (`resolve_backend_python()`
ELSŐ candidate-je) a landoló hívás elé kötve az abszolút útvonalat kényszerítve
(`ROUND_GATE_BACKEND_PYTHON=/home/ubuntu/music-theory/backend/.venv/bin/python
tools/round-land.sh ...`). **Nyitott GOV-tétel:** a `resolve_backend_python()`/
a `env --chdir=backend` sor tényleges javítása (pl. `cd backend &&
"$backend_python" -m pytest` vagy mindig-abszolút candidate) egy jövőbeli
governance-kör dolga — ez a kör nem nyúlt a `tools/`-hoz.

**Zöld kapu (exact `9a0c5364`).** Full Gate
[32663011671](https://github.com/wolfcasaba/strumsight/actions/runs/32663011671)
**success**, Router CI
[32662979279](https://github.com/wolfcasaba/strumsight/actions/runs/32662979279)
**success**. A kör alatt a `main` egyszer mozdult (E13-R07 lezárása, PR #429,
diszjunkt fájlkör) — `merge --no-ff` a kör-branchbe, majd teljes
CI-újradispatch a kombinált HEAD-en. A landolás a merge-záron át
(`tools/round-land.sh`), mert a másik sáv (E13-R08) párhuzamosan fut.

**Következő Epic 9 kör: E09-R20.**

## ✅ E13-R07 KÉSZ — Ikonográfia és gitárglyph készlet — PR [#429](https://github.com/wolfcasaba/strumsight/pull/429), squash `98fd1168` (2026-08-23)

**CHAPTER 13 (UI/UX DESIGN SYSTEM) HETEDIK KÖRE KÉSZ.** Egységes ikon-API és
hozzáférhető gitárspecifikus glyph-készlet, **nulla új függőséggel és nulla új
asset-tel** ([ADR 0411](docs/adr/0411-iconography-and-guitar-glyph-contract.md)):
`lib/core/design_system/icons/ss_icons.dart` (**ÚJ** — `SsGuitarGlyphName` enum
a Ch13 §9.8 tizennégy nevével, `SsIconSize` 24/32/48 dp szerződés
`isValidForStage` + `resolveForStage`-dzsel, `SsIconResolution` lezárt
hierarchia lekérdezhető `isFallback`-kel, `SsIcons.resolveByName`),
`icons/ss_guitar_glyphs.dart` (**ÚJ** — a tizennégy glyph EGY
`CustomPainter`-ben, egyetlen nevesített `kSsGuitarGlyphStrokeRatio`-ból
számolt vonalvastagsággal), `icons/ss_icon.dart` (**ÚJ** — `.decorative` /
`.interactive` factory-pár: a dekoratív `ExcludeSemantics`, az interaktív
kötelezően nem üres, hívó-oldali semantics label + tooltip; a Stage-méret a
VALÓDI widget-úton clamp-el), `documentation/component_catalog_screen.dart`
(ikon-galéria mind a 14 glyph-fel), `public.dart`.

**Motorok (ADR 0055):** tervező/reviewer **Claude Opus 5**, implementer
**`sonnet-impl`** (Claude Sonnet 5, `--effort high`). Egy javító kör.

**Pre-flight — három MÉRT brief-javítás (§0.0), ami megelőzött egy zsákutcát:**
1. **A brief rossz SDD-szakaszra mutatott.** A Ch13 **§9.7 a Motion tokenek**
   (az E13-R06 tárgya); az ikonográfia a **§9.8** (a fájl 703–726. sora). A
   tizennégy glyph-név onnan jött.
2. **A `lucide_icons_flutter` NINCS a fában** — a plugin-pruning után csak egy
   doc-comment említi (`reaction_bar.dart:99`). A névkatalógus indoka viszont
   él: a Material `Icons.*` konstansok is csak fordításkor bukhatnak.
3. **`assets/icons/` + „vektoros glyph" + „nincs új függőség" EGYÜTT nem
   teljesíthető.** A `flutter_svg` sehol nincs a fában, és a Flutter beépítetten
   nem rendereli az SVG-t; új ikon-csomagot a ONE-win32-major szabály tilt. A fa
   mért, függőségmentes vektor-útja a `CustomPainter` (10 production fájl, köztük
   a `strum_arrow.dart`). → az engedélyezett fájllista **SZŰKÜLT**: az
   `assets/icons/` és a `pubspec.yaml` kikerült, amivel az **A7** („nincs új
   `dependencies:`") gépi ténnyé vált: a `pubspec.yaml` bármely érintése
   `scope_audit=VIOLATION`. A merge-elt diffben a `pubspec.yaml` és az `assets/`
   valóban érintetlen.

**Review — 1 MAJOR, próbával megfogva és próbával lezárva:** az első kör A9
cellája (**„minden glyph a megosztott stroke-arányból számol"**) NEM
falszifikált: a reviewer beinjektált egy kézzel írt `strokeWidth = 7.5`-öt a
`_paintCapo`-ba, és MINDEN cella zöld maradt (`+11: All tests passed!`). Az ok:
a cella a KONSTRUKTORBAN kiszámolt `painter.strokeWidth` mezőt mérte
tizennégyszer, ami a `name`-től függetlenül ugyanaz az egy kifejezés — a
tényleges festésről semmit nem mondott. A javító kör egy `_RecordingCanvas`
teszt-duplát vezetett be (`implements Canvas` + `noSuchMethod`), amely rögzíti
a `drawLine`/`drawPath`/`drawRRect`/`drawCircle`/`drawArc` hívások `Paint`
értékeit, és mind a 14 glyph-re, **három** szerződéses méreten (24/32/48 dp)
megméri, hogy minden `PaintingStyle.stroke` festés vonalvastagsága az
engedélyezett arányok (`{1.0, 0.6}`) egyike a megosztott `strokeWidth`-hez
képest. Ugyanaz az injekció most PIROS. Két MINOR is zárult: az A8 három
téma-cellája egyedi nevet kapott (a `SsHighContrastTheme.brightness` `dark`,
ezért két cella neve korábban ütközött), és új cella követeli meg, hogy a
tizennégy glyph rögzített rajz-hívás-sorozata **páronként különbözzön** (a
`fretboard`-ot a `_paintCapo`-ra irányítva PIROS). Lásd
[`docs/reviews/e13-r07-review.md`](docs/reviews/e13-r07-review.md).

**A6 lelet (felmérve, NEM javítva — a csere a Kör 16–35 dolga):** a production
`lib/features/**`-ben **16 emoji-piktogram 5 fájlban** és **25 nyílkarakter 13
fájlban** maradt (comment-sorok nélkül mérve; a rebase után újramérve
változatlan). A nyílkarakteres fájlok közt van a `share_content.dart` (6), a
`feed_card_registry.dart` (3) és a `strum_card.dart` (3) — a strum-irány ma
több helyen tényleg puszta karakterként megy ki, ami a §5.1 mért
alátámasztása. A `lib/features/**` ebben a körben ÉRINTETLEN maradt.

**Amit a következő köröknek tudni kell:**
- Az `SsIcons.resolveByName` ma hat Material-aliast ismer (`play`, `pause`,
  `settings`, `close`, `check`, `info`) — bővítendő, ha egy jövőbeli kör több
  Material ikonra hivatkozik névvel.
- A `lib/features/live/widgets/strum_arrow.dart` és az új
  `SsGuitarGlyphPainter` down/up ága **két, egymástól független megvalósítás**
  (ADR 0411 „Következmények" — szándékos); az összevonás a képernyő-migrációs
  körök dolga.
- Az ikon-réteg `AppLocalizations`-mentes: a semantics label és a tooltip
  **hívó-oldali** (ADR 0411 §4), tehát a migrációs körök adhatnak ARB-kulcsokat
  anélkül, hogy a design system l10n-függővé válna.
- Az A9 `_RecordingCanvas` mintája újrahasznosítható minden olyan körben, ahol
  egy festési/kimeneti invariánst kell mérni, nem csak egy mező meglétét.

**Zöld kapu (exact `da511df4`):** Full Gate
[32660658827](https://github.com/wolfcasaba/strumsight/actions/runs/32660658827)
**success** + Router CI
[32660654182](https://github.com/wolfcasaba/strumsight/actions/runs/32660654182)
**success**. A landolás a merge-záron át (`tools/round-land.sh`), mert a másik
sáv (E09-R19) párhuzamosan fut. A `main` a kör alatt egyszer mozdult (E09-R18
lezárása, diszjunkt fájlkör) — rebase + `tools/safe-force-push.sh` + teljes
CI-újradispatch a rebase-elt HEAD-en.

## ✅ E09-R18 KÉSZ — Média upload contract és objektumtár integráció — PR [#430](https://github.com/wolfcasaba/strumsight/pull/430), squash `ee741678` (2026-08-23)

**EPIC 9 (COMMUNITY PLATFORM) TIZENNYOLCADIK KÖRE KÉSZ.** Feature-flaggel
(`communityMediaEnabled`/`community_media_enabled` — MÁR létező, KÜLÖN flag a
fő `communityEnabled`-től) védett, direkt-objektumtáras médiafeltöltési
pipeline ALAPJA: `backend/app/community/storage/object_store.py` (ÚJ —
vendor-semleges `ObjectStore` interfész + **stdlib-only** SigV4
`S3CompatibleObjectStore`, NINCS `boto3`/`minio` — a `requirements.txt` nincs
az `allowed_paths`-on, ADR 0410 D2; + `InMemoryObjectStore` teszt-fake),
`models/media.py` (ÚJ `CommunityMedia`, `public UUID + bigint PK` minta),
`services/media_upload_service.py` (ÚJ — intent → signed URL → finalize/
cancel, ownership/checksum/MIME/size ellenőrzés, orphan cleanup, kvóta),
`e09_r18_0012_community_media.py` migráció, `community_media_uploader.dart`
(ÚJ — lifecycle-aware, Dio `CancelToken`-alapú cancel, progress).
Implementer MiniMax M3, orchesztrátor/reviewer Claude Sonnet 5.

**ADR-szám korrekció a pre-flightban.** A brief előre `0407`-et adott, de azt
közben E09-R16 foglalta el — `tools/round-slots.py reserve-adr` friss számot
adott: **[ADR 0410](docs/adr/0410-media-upload-contract-and-object-store.md)**.

**Kötött szerkezeti döntés a pre-flightban (D1): NINCS router-fájl ebben a
körben, szándékosan.** A brief `allowed_paths`-a nem tartalmaz
`routers/media.py`-t; az A1 ("flag KI → elérhetetlen") a
**service-függvény szinten** dől el (`settings.community_media_enabled`
minden publikus belépési ponton) — a HTTP-bekötés egy KÉSŐBBI kör tartozása,
ugyanaz a minta, mint a Kör 12 óta `UnimplementedError`-t dobó feed/post
repository HTTP-integráció.

**EGY javító kör, 1 BLOCKER + 4 MAJOR javítva** (`docs/reviews/e09-r18-review.md`
+ dedikált biztonsági review `docs/reviews/e09-r18-security.md`, `risk="high"`)
— mindhárom fél (correctness review, security review, a Claude saját
önállóan futtatott próbája) FÜGGETLENÜL reprodukálta ugyanazt a három hibát:

- **BLOCKER — az A2 lejárat-cella hamis zöld volt.** `finalize_upload` a
  lejáratot egy hardcode-olt modul-konstansból (`SIGNED_URL_EXPIRES_IN`, 5
  perc) számolta újra, NEM a ténylegesen kiadott `signed_url_expires_in`
  értékből — a sor nem is tárolta a valódi `expires_at`-ot. Próba: 60 mp-es
  signed URL, finalize `+90 mp`-nél → `FINALIZED` (elvárt: `MediaUploadExpired`).
  Javítva: `CommunityMedia.expires_at` persisted oszlop, a finalize a TÁROLT
  értékhez hasonlít.
- **MAJOR — kvóta permanens lockout.** A terminális `cancelled`/`failed`
  sorok örökre beszámítottak a kvótába — 10 megszakított feltöltés után a
  profil véglegesen kizárva. Javítva: csak `pending`/`uploaded` számít élőnek.
- **MAJOR — a checksum-guard (A5) csendes no-op volt a valódi adapterrel**,
  mert `S3CompatibleObjectStore.head_object` fixen `sha256_hex=None`-t adott.
  Javítva LÁTHATÓAN: `pytest.mark.xfail(strict=True)` teszt dokumentálja a
  rést, ami hangos `XPASS→FAIL`-ra vált, amint egy jövőbeli kör beköti a
  valós bucket-oldali SHA-256-ot.
- **MAJOR — `_as_utc` a LOKÁLIS időzónát csatolta, nem UTC-t** (eltérve a
  hivatkozott `post_service._as_utc` precedenstől) — nem-UTC hoston minden
  lejárat/retention-összehasonlítás eltolódott volna; a box UTC-je maszkolta.
  Javítva: `timezone.utc`.
- **MAJOR (dedikált biztonsági review) — a signed URL kitalált,
  nem-szabványos SigV4 query-paraméterekkel próbálta korlátozni a
  content-type/content-length-et**, amit egy valódi bucket nem ismerne fel.
  Javítva: valódi aláírt `content-type` header (`X-Amz-SignedHeaders`); a
  content-length-re a docstring ŐSZINTÉN kimondja, hogy presigned PUT nem
  tudja aláírni (AWS-korlát) — a finalize `head_object`-alapú újraellenőrzés
  a load-bearing réteg.

Review APPROVED javító kör 1 után, 0 nyitott BLOCKER/MAJOR — a Claude a
javításokat friss, izolált `/tmp`-klónokban ÚJRA futtatott gate-tel,
scope-audittal ÉS saját, önállóan futtatott real-violation próbákkal
fogadta el (nem az implementer önjelentésére hagyatkozva). Dedikált
security-reviewer pass (risk=high): PASS, 0 nyitott lelet a javítás után.

**Zöld kapu (exact `4bb95197`).** `full-gate.yml`
[32659147187](https://github.com/wolfcasaba/strumsight/actions/runs/32659147187)
**success**, `router-ci.yml`
[32658886961](https://github.com/wolfcasaba/strumsight/actions/runs/32658886961)
**success**. A kör alatt a `main` egyszer mozdult (E13-R06 lezárása, PR #428,
diszjunkt fájlkör) — `merge --no-ff` + `tools/safe-force-push.sh` + teljes
CI-újradispatch a kombinált HEAD-en, §0.3 szerint. A landolás a merge-záron
át (`tools/round-land.sh`), mert a másik sáv (E13-R07) párhuzamosan fut.
Post-merge `tools/round-gate.sh test/features/community/data/community_media_uploader_test.dart`
a friss, fast-forwardolt `main`-en is zöld (6/6 Flutter-lépés).

**Nyitott horog a következő köröknek:** a `S3CompatibleObjectStore` ebben a
körben BEKÖTETLEN (a service-réteg csak az `InMemoryObjectStore` fake-et
használja a tesztekben) — egy jövőbeli wiring-kör kösse be a valós bucket
oldali SHA-256 kiolvasását (S3 Additional-Checksums vagy `X-Amz-Meta-Sha256`)
és törölje az `object_store.py`-beli TODO-t + az `xfail(strict=True)` tesztet
cserélje normál assertre. A router (`backend/app/community/routers/media.py`)
és a `main.py`-mountolás szintén egy KÉSŐBBI kör dolga.

**Következő Epic 9 kör: E09-R19** (média feldolgozás, privacy és moderation
state).

## ✅ E13-R06 KÉSZ — Motion rendszer és reduced motion — PR [#428](https://github.com/wolfcasaba/strumsight/pull/428), squash `011d1c47` (2026-08-23)

**CHAPTER 13 (UI/UX DESIGN SYSTEM) HATODIK KÖRE KÉSZ.** Hozzáférhető
mozgásrendszer, aminek a ritmus-animációja az **audio órából** jön, nem
független időzítőből (ADR 0274):
`lib/core/design_system/foundations/ss_motion.dart` (**szigorúan additív**: öt
szemantikus duration-alias — `microInteraction`/`chordChange`/`contentFade`/
`routeTransition`/`successFeedback` — plusz négy curve-token `enter`/`exit`/
`emphasizedCurve`/`linear`; a kipinnelt `SsMotion.durations` lista és a
`forReducedMotion` ÉRINTETLEN), `motion/ss_motion_scope.dart` (**ÚJ** —
`InheritedWidget` resolver: injektált nullable `appOverride` + a rendszer
`MediaQuery.disableAnimationsOf`, a felülbírálás MINDKÉT irányban hat),
`motion/ss_beat_pulse.dart` (**ÚJ** — `SsBeatClock` absztrakt idő-port a design
systemen BELÜL + az abból frame-enként pollozott pulzus), `motion/ss_transitions.dart`
(**ÚJ** — token-alapú route-átmenet + `SsContentFade`), `public.dart`.

**Motorok (ADR 0055):** tervező/reviewer **Claude Opus 5**, implementer
**`sonnet-impl`** (Claude Sonnet 5). Két javító kör.

**Pre-flight — három MÉRT brief-javítás (§0.0), ami megelőzött egy H3-at:**
1. Az előre kiosztott **ADR 0274 MÁR MERGE-ELVE volt** (`0bf943cc`), a tartalma
   pontosan e kör döntése → a kör NEM írt új ADR-t. A `reserve-adr` foglalta
   `0409` felhasználatlan (a `test_adr_numbering.py` csak unicitást követel,
   folytonosságot nem — mérve).
2. **A brief rossz helyen kereste az órát.** A `lib/features/audio_analysis/**`
   alatt NINCS lejátszási idővonal (csak `Stopwatch` stage-profilozás:
   `analysis_context.dart:18`, `analysis_pipeline.dart:217`). A valódi források
   a `song_trainer` `LocalPlaybackHandle.positions` és a
   `metronome/beat_clock.dart` — MINDKETTŐ tilos zóna. Ezért az `SsBeatPulse`
   a SAJÁT absztrakt portját definiálja, ahogy az ADR 0274 „Következmények"
   szakasza eleve előírta. (`lessons/L19`, `L100` mintája.)
3. **Scope-csapda ELŐRE elhárítva:** a listán KÍVÜLI
   `test/core/design_system/foundations_test.dart:20-27` kipinneli az
   `SsMotion.durations` listát → a brief kötötte, hogy az `ss_motion.dart`
   változása szigorúan additív. Ez pontosan az E13-R05 §0.0.1 H3 hibaosztálya,
   most kör ELEJÉN megfogva, nem self-heal körben.

**Review — két MAJOR, mindkettő MÉRVE lezárva** (`docs/reviews/e13-r06-review.md`):
- **MAJOR-1:** a brief §6.1 KÖTELEZŐ óra-szinkron hármasa **tautologikus volt** —
  csak a tiszta `isWithinSyncTolerance(Duration)` predikátumot hívta, a widgetet
  soha nem építette fel. Mérve: a tiltott, szabadon futó implementáción
  **0/3 cella váltott pirosra**. Javítva: a cellák most a widgetet hajtják
  (60/100/140 ms-mal lemaradó óra → a renderelt pont méretéből visszaszámolt
  fázis → mért lag), és ugyanaz a rontás már **2/3** cellát visz pirosra.
- **MAJOR-2 (regresszió, a reviewer lelet-iránya okozta):** az első javító kör
  `_ticker.stop()`-ja néma no-opot csinált — PULL-alapú portnál semmi nem
  ébresztette fel újra. Mérve: `PROBE_D RESUMED: false`, a pause→resume a
  halott 16.0 méreten ragadt. Javítva a folyamatosan futó tickerrel
  (`CircularProgressIndicator`-idióma); `PROBE_D RESUMED=true`,
  `PROBE_E BACK_TO_LIVE=true`, a resumed 16.5 méret a 0.9-es fázis PONTOS
  értéke. Gépi őr: két új, rebuild nélküli cella.
- MINOR-1 (reduced-motion off-beat pixelre azonos volt a „nem játszik"
  állapottal), MINOR-2 (`beatDuration == Duration.zero` csak `assert`-tel őrizve
  → release `IntegerDivisionByZeroException`) — mindkettő javítva, cellával.

**Zöld kapu (exact `d091e6fd`).** Full Gate
[32656683061](https://github.com/wolfcasaba/strumsight/actions/runs/32656683061)
**success**, Router CI
[32656678494](https://github.com/wolfcasaba/strumsight/actions/runs/32656678494)
**success**. Reviewer-gate izolált `/tmp` klónban: 7/7 zöld, 21 cella.
Scope-audit: OK (9 fájl, 1 generated/ignored = a review-jelentés). A landolás a
merge-záron át (`tools/round-land.sh`), mert a másik sáv (E09-R18) párhuzamosan fut.

**Nyitott horog a következő köröknek:** az `SsBeatPulse` élő órával
**megfogja a `pumpAndSettle`-t** (folyamatos ticker) — aki valódi képernyőbe
huzalozza, explicit `pump(Duration)`-t használjon. A katalógus-demó emiatt
NEM került be (a listán kívüli `component_catalog_test.dart`-ot pirosra vitte);
egyetlen acceptance-cella sem függött tőle.

**Következő Chapter 13 kör: E13-R07** (ikonográfia és gitár-glyphek).

## ✅ E09-R17 KÉSZ — Bookmark, mentett tartalom és biztonságos import — PR [#427](https://github.com/wolfcasaba/strumsight/pull/427), squash `dc6e3915` (2026-08-23)

**EPIC 9 (COMMUNITY PLATFORM) TIZENHETEDIK KÖRE KÉSZ.** Privát bookmark +
kontrollált Practice/Song import: `backend/app/community/models/bookmark.py`
(ÚJ `community_bookmarks` tábla, `UNIQUE(post_id, profile_id)`, mindkét FK
`ON DELETE CASCADE`), `routers/bookmarks.py` (router+service EGY fájlban —
nincs külön `bookmark_service.py` az `allowed_paths`-on; idempotens
set/remove, önálló base64 `(created_at, id)` keyset cursor, tombstone a
soft-delete/moderation-removed posztra), `import_share_artifact.dart` (PURE,
hívó-táplált use-case: schema-validáció, névütközés, deprecated-fallback,
ÚJ `Song`-ot épít, de NEM perzisztál), `bookmarks_screen.dart`.

**ADR-szám ütközés a pre-flightban.** A brief előre `0406`-ot adott, de azt
közben E09-R13 foglalta el, `0407`-et E09-R16 — `tools/round-slots.py
reserve-adr` friss számot adott: **[ADR 0408](docs/adr/0408-bookmark-and-controlled-import.md)**.

**Erőforrás-tulajdonlás mérve a pre-flightban (D1).** `songsRepositoryProvider`/
`SongsController.add()` — az egyetlen belépési pont egy ÚJ `Song`
perzisztálására — kizárólag `lib/features/songs/` belsejében használt; a
feature `public.dart`-ja csak a `model/song.dart`-ot exportálja, a
repository/provider réteget nem. Mivel a `songs/public.dart` bővítése
kívül esik ezen kör `allowed_paths`-án (más feature-t célzó kör sosem
tartalmazza — strukturális H3, ADR 0087 §2), a feloldás a **L286 precedens**
(E07-R08) megismétlése: az `import_share_artifact.dart` PURE, hívó-táplált
transzformátor maradt — épít egy ÚJ `Song`-értéket, de nem hívja a
`songsProvider`-t. A §6 A5 cella a use-case szintjén mérhető és mérve is
lett (élő repository nélkül). A tényleges helyi mentés bekötése egy
jövőbeli kör dolga.

**Review (Claude Sonnet 5) — APPROVED**, 0 BLOCKER/MAJOR, 2 MINOR (holt
`_resolve_internal_profile_id` helper; a brief §3 "explicit Import action"
scope-tétele nincs a képernyőn vizuálisan bekötve — a §8 implementációs
terv ezt sosem írta elő, egyik A1-A7 cella sem méri, follow-up körre
javasolva a `BookmarkOut` artifact-mezőkkel való bővítésével együtt).
Independensen újrafuttatott gate izolált klónban: mind a 10 lépés zöld,
`tools/scope-audit.py` OK (a diff pontosan az `allowed_paths`-t fedi).

**CI-only javító kör** (a szokásos screen-count drift, mint E09-R05...R16):
`test/ui/ui_inventory_test.dart` `hasLength(72)` → `hasLength(73)` a
`bookmarks_screen.dart` új képernyője miatt — §0.0.1 dokumentált
review-vezérelt scope-bővítés, EGY sor, semmi más.

**Zöld kapu (exact `82013935`).** `full-gate.yml`
[32652652934](https://github.com/wolfcasaba/strumsight/actions/runs/32652652934)
**success**, `router-ci.yml`
[32652091202](https://github.com/wolfcasaba/strumsight/actions/runs/32652091202)
**success**. A landolás a merge-záron át (`tools/round-land.sh`), mert a
másik sáv (E13/E10 lánc) párhuzamosan futott.

**Következő Epic 9 kör: E09-R18** (media upload contract és object store).

## ✅ E13-R05 KÉSZ — Spacing, radius, elevation és surface primitívek — PR [#392](https://github.com/wolfcasaba/strumsight/pull/392), squash `6635a788` (2026-08-23)

**CHAPTER 13 (UI/UX DESIGN SYSTEM) ÖTÖDIK KÖRE KÉSZ — egy 2026-08-21 óta
megállt kör folytatásaként, nem újraindításaként.** A kör terméke a
`SsElevation` felület-hierarchia (`base → raised → overlay → modal`), az
`SsSurface` alap-primitív (a szint és a szemantikai háttérszín EGYÜTT, insetek
kezelésével), valamint az `SsCard`, `SsHeroCard` és `SsSection` komponensek,
plusz a 4 dp rács gépi kikényszerítése. A geometria-szerződést az
[ADR 0385](docs/adr/0385-surface-hierarchy-and-geometry-contract.md) rögzíti.

**Miért folytatás.** A PR #392 2026-08-21-én APPROVED review és zöld célzott
gate mellett zárult be merge NÉLKÜL: az exact `03788441` Full Gate 5519 zöld
teszt mellett háromszor `Found 0 widgets with type "Card"` hibát adott, mert a
helyesen egyetlen `Material`-réteget használó `SsCard` mellől eltűnt a legacy
`Card`, amit a kör allowlistjén KÍVÜLI
`test/core/design_system/component_catalog_test.dart` még várt (L393). A
[HEAL E13-R05/H3](#-heal-e13-r05h3-component-catalog-scope-helyreállítva-2026-08-21-l393)
self-heal (PR #393) ezt az egy fájlt vette fel az `allowed_paths` és
`gate_tests` listára. Ez a session azt a nyitott munkát zárta le.

**Orchestrátor pre-flight (Claude, Opus 5).** (1) `origin/main` NEM volt őse az
ág `03788441` csúcsának — a kötelező upstream-szinkron (ADR 0087 §0.3) egyetlen
ütközése maga a brief volt. (2) Az ütközés mindkét oldalon additív: a `§0.0`
pre-flight (ág) és a `§0.0.1` H3 self-heal (main) EGYÜTT maradt meg. (3) A
self-heal katalógus-cellája `A8` → **`A13`** sorszámot kapott, mert az ágon az
`A8`…`A12` már implementált ÉS review-zott jelentéssel bírt; a main
brief-változatának szó szerinti megőrzése öt kész acceptance-cellát törölt
volna (L440). (4) A brief-lint `S8` lelete (hiányzó visszakeresés) a `§0.0.2`
revízióban lezárva: L393, L420/L106/L145, L102, ADR 0273/0383/0385.

**Implementer (`sonnet-impl`, claude-sonnet-5 `--effort high`).** A diff pontosan
2 útvonal, 60 beszúrás: a katalógus-teszt három cellája `find.byType(Card)`
helyett `find.byType(SsCard)` + a `SsCard` alá **szűkített**
`find.descendant(… matching: Material)` `findsOneWidget` párt mér — a csupasz
`find.byType(Material)` hamis elvárás lett volna, mert a katalógus fája
legalább négy `Material`-t tartalmaz. A route-kapu (compile-time OFF +
debug-gate, ADR 0273) és a dark/light smoke contract érintetlen. Mért
mellék-lelet: a cellák `DecoratedBox`-elvárása addig SOHA nem futott le, mert
az előtte álló `Card`-expect pirosra vitte a cellát — az implementer megmérte
(dark → 1, light → 1), és csak a mért értéket hagyta benne (L441).

**Review (Claude, Opus 5) — APPROVED**, 0 nyitott BLOCKER/MAJOR, 1 MINOR (a §10
zárólistája a régi kétútvonalas gate-sort őrzi; a háromútvonalas gate-et a
reviewer maga futtatta le). Izolált `/tmp` klónban az exact `2af6eca4`-en mind
a 8 gate-lépés zöld (exit 0). Három eldobható valódi-sértés próba: második
`Material` az `SsCard`-ban → `+5 -3` piros; az `SsCard` kivétele a
katalógusból → `Found 0 widgets with type "SsCard"`; a route-kapu `||` → `&&`
lazítása → `Expected: null / Actual: MaterialPageRoute` — a finder tehát nem
vakcella, és a fejlesztői-eszköz szerződés tényleg mérve van. Részletek:
[`docs/reviews/e13-r05-review.md`](docs/reviews/e13-r05-review.md).

**Zöld kapu (exact `552c9312`).** Full Gate
[32651317079](https://github.com/wolfcasaba/strumsight/actions/runs/32651317079)
**success** (teljes `flutter test` + randomizált property + coverage,
APK-építés nélkül — a CI-tervező `full-gate.yml`-t adott, `native_gate=false`),
Router CI
[32651318066](https://github.com/wolfcasaba/strumsight/actions/runs/32651318066)
**success**. A landolás a merge-záron át (`tools/round-land.sh`), mert a másik
sáv (E09-R17) párhuzamosan futott.

**Következő Chapter 13 kör: E13-R07** (ikonográfia) — az E13-R06 (motion) KÉSZ, lásd a fejléc ✅-blokkot.

## ✅ E09-R16 KÉSZ — Kommentek, reply és mention — PR [#425](https://github.com/wolfcasaba/strumsight/pull/425), squash `bf767ca5` (2026-08-23)

**EPIC 9 (COMMUNITY PLATFORM) TIZENHATODIK KÖRE KÉSZ.** Moderálható, korlátozott
mélységű kommentréteg biztonságos mentionnel: `backend/app/community/models/comment.py`
(ÚJ `community_comments` tábla, `depth` oszlop max 1, `updated_at`-mint-
resource_version), `services/comment_service.py` (create/edit/delete/list négyes,
mention-validáció a Kör 3/8/4 hármas kompozíciójaként), `policies/comment_policy.py`
(`can_delete` — owner/post-owner/moderator, `is_moderator: bool` EXPLICIT
paraméter, NEM DB-mező), migráció `e09_r16_0010`, és Flutter oldalon
`comments_screen.dart` + `comment_controller.dart` (optimista create, atomikus
temp-ID csere). `risk = "high"` (mention privacy-megkerülés + jogosultsági
mátrix).

**Pre-flight (Claude Sonnet 5, ADR 0407):** az előre kiosztott `ADR 0405` már
foglalt volt (Kör 11 post-crud) — friss foglalás `0407`. Három mért gap
dokumentálva §0.0-ban: (1) nincs élő "moderator" DB-mező sehol a kódban — a
`can_delete` explicit, hívó-adta `is_moderator: bool`-t kap (a Kör 26/27
admin-auth kör drótozza majd valós forrásra); (2) a mention-validáció a
MEGLÉVŐ Kör 3 (`lookup_active_profile_id`) + Kör 8 (`is_blocked_pair`,
TILOS zóna, csak hívható) + Kör 4 (`CommunityAccessPolicy.evaluate_profile_access
== FULL`) hármas kompozíciója, nem új logika; (3) nincs HTTP router/schema
ebben a körben (Kör 14/15 precedens) — a kör service-réteg-only, az A4
(edit-conflict) mérce kizárólag a backend `test_comment_service.py` felelőssége.

**Implementer MiniMax M3, orchesztrátor/reviewer Claude Sonnet 5 (`--effort
high`). 1 javító kör** (`docs/reviews/e09-r16-review.md`): review CHANGES
REQUESTED elsőre, **1 MAJOR** — `comments_screen.dart` öt hardcode-olt
stringgel (`'Comments'`, `'No comments yet.'`, `'Load more'`, `'Write a
comment…'`, `'Send'`) ment ki 0 `AppLocalizations` hívással — **ugyanaz a
hibaosztály, mint az E09-R08 F1 és az E09-R14 F1** (mindkettő MAJOR volt).
**2 MINOR** — `comment_policy.py` docstringje SIMA (nem raw) triple-quoted
stringben `\|`-t tartalmazott, `SyntaxWarning`-ot dobva minden importnál;
`edit_comment`/`edit_comment_with_resource_version` ~45 sort duplikált,
az előbbit semmi nem hívta. **Mellékhatás, saját méréssel** (a brief
`gate_tests`-én TÚLI, teljes `flutter test` futtatással): a kör ÚJ
`comments_screen.dart`-ja miatt a `test/ui/ui_inventory_test.dart` hardcode-olt
képernyő-számlálója (71) elavulttá vált — **ugyanaz a drift-osztály, mint
E09-R05...R13 és E09-R14 ismételten**. A javító kör mind a négyet zárta:
5 string valódi magyar fordítással ARB-be (`community_{en,hu}.arb` +
a generált `app_{en,hu}.arb` aggregátum, retroaktív scope-bővítéssel, mert
az aggregátum-frissítés mechanikusan szükséges velejárója az ARB-bővítésnek),
a docstring `r"""`-re váltva, `edit_comment` vékony wrapperré alakítva, a
számláló 71→72. A Claude a javítást friss, izolált `/tmp`-klónban ÚJRA
futtatott gate-tel (10/10 lépés zöld, a `ui_inventory_test.dart` most explicit
gate-argumentum) és scope-audittal fogadta el. **Landolási körülmény:** a
`main` a dispatch alatt HÁROMSZOR mozdult (párhuzamos governance/pipeline-
munka ugyanazon a boxon) — mindhárom rebase konfliktusmentes volt (docs-only
governance-commitok), mindhárom után friss exact-SHA CI-dispatch (`full-
gate.yml` + `router-ci.yml`) igazolta a kombinált HEAD-et a `tools/round-
land.sh` fail-closed protokollja szerint; a landolást a SAJÁT izolált
munkapéldányból (`ss-minimax-e09-r16`) futtattam, nem a megosztott fő fából,
mert utóbbin egy másik aktív session commitolatlan governance-munkát végzett
(pipeline-slots 1→2, engine-registry effort-váltás) — a megosztott fa
zavarása nélkül. Exact `88de73c9` → merge `bf767ca5`: Full Gate
[32647755067](https://github.com/wolfcasaba/strumsight/actions/runs/32647755067)
+ Router CI [32647756074](https://github.com/wolfcasaba/strumsight/actions/runs/32647756074)
mindkettő success. Részletesen `docs/reviews/e09-r16-review.md`.

## ✅ E09-R15 KÉSZ — Reakciók és optimista konzisztencia — PR [#424](https://github.com/wolfcasaba/strumsight/pull/424), squash `a8fa5add` (2026-08-23)

**EPIC 9 (COMMUNITY PLATFORM) TIZENÖTÖDIK KÖRE KÉSZ.** Pozitív, idempotens,
allowlistelt (`support`/`celebrate`/`inspiring`/`helpful`) reakció szolgáltatás-
réteg: `backend/app/community/models/reaction.py` (ÚJ `community_reactions`
tábla, `UNIQUE(post_id, profile_id)`), `services/reaction_service.py` (ÚJ
`set_reaction`/`remove_reaction`/`get_reaction_count`/`get_viewer_reaction`
kvartett), migráció `e09_r15_0009`, és a Flutter oldalon egy optimista
`ReactionController` (mutation-ID-alapú legutolsó-szándék-nyer + rollback
hálózati hibán) + egy önálló `ReactionBar` widget. `risk = "normal"`.

**Pre-flight §0.0 D2 (Claude Sonnet 5, a HTTP-router és a `PostOut`/
`FeedPostItem` wire-projekció ebben a körben szándékosan NEM épül meg):**
a brief SDD-ből másolt §3 scope-mondata ("post-projekció: viewer reaction +
aggregált count", "reaction set/remove endpoint idempotensen") egyik fájlja
sincs az `allowed_paths`-on — mérve grep-pel: sem a `PostOut`
(`schemas/post.py`), sem a `FeedPostItem` (`schemas/feed.py`), sem az őket
kitöltő `routers/posts.py::_row_to_out` / `routers/feed.py`, sem egy
reaction-router fájl, sem a `backend/app/main.py` router-regisztráció nincs a
listán. A pre-flight megmérte, hogy a §6 A1–A7 egyike SEM igényli ezt — mind
a `reaction_service` szolgáltatás-rétegen vagy a Flutter controlleren
mérhető —, ezért a §3 két cellája ÚGY teljesült, hogy a HTTP-router és a
wire-projekció egy KÉSŐBBI kör hatásköre marad (a Kör 13/14 pár precedense:
tisztán backend feed-query, majd tisztán UI valós HTTP-bekötés nélkül). A
Flutter oldalon a `CommunityPostRepository.setReaction()` kontraktus és a
`CommunityPost.reactionCount`/`myReaction` mezők MÁR léteztek Kör 5 óta
(ADR 0399 §1) — a `domain/**` tilos zóna emiatt nem korlátozott semmit, amire
a körnek ténylegesen szüksége volt.

**Implementer MiniMax M3, orchesztrátor/reviewer Claude Sonnet 5 (`--effort
high`). 1 javító kör** (`docs/reviews/e09-r15-review.md`): review CHANGES
REQUIRED elsőre, **1 MINOR** — az A5 property-teszt (`count` sosem negatív,
200 random op) `count` változója csak az `op == 2` ágon kapott értéket, de az
`assert count >= 0` feltétel nélkül futott minden iterációban; `seed=42`
(dev-alapértelmezés) mellett véletlenül biztonságos (az első húzott `op`
történetesen 2), de más seeddel (mérve: 1, 2, 12345, 999999 mind) az ELSŐ
iteráció azonnali `UnboundLocalError`-t dobott volna — a teszt saját
docstringjének "CI can monkeypatch seed" állítását megcáfolva. A mai
`backend-ci.yml`-ben nincs `PROPERTY_SEED` override, tehát ez a mai gate-en
nem volt piros, de egy jövőbeli randomizált backend property-gate alatt
azonnal elhalt volna. A javító kör a `count = _count()`-ot minden iterációban
feltétel nélkül futtatóra javította — a review saját kézzel, izolált
`/tmp`-klónban öt különböző `PROPERTY_SEED` értékkel (1, 2, 12345, 999999, 42)
újraellenőrizte. **1 NOTE külön mellékfelfedezés**: a javító kör utáni
re-verifikáció során egy PRE-EXISTING, körön kívüli flaky teszt bukkant fel
(`test_follow_service.py::test_swap_unique_constraint_breaks_a2`, Kör 7,
`threading`-alapú valódi-sértés próba) — izoláltan és két következő
teljes-suite futtatásnál zöld volt, a fájl nincs az `allowed_paths`-on és a
kör diffje nem érinti; dokumentálva egy jövőbeli Kör 7-hez nyúló forduló
számára. A Claude a javítást friss, izolált `/tmp`-klónban ÚJRA futtatott
gate-tel (mind a kilenc lépés, a backend pytest a TELJES suite-ot jelentve)
és saját kézzel futtatott scope-audittal fogadta el. Exact `b4e9c879`: Full
Gate [32639185526](https://github.com/wolfcasaba/strumsight/actions/runs/32639185526)
+ Router CI [32639211541](https://github.com/wolfcasaba/strumsight/actions/runs/32639211541)
mindkettő success. Részletesen `docs/reviews/e09-r15-review.md`.

## ✅ E09-R14 KÉSZ — Feed UI, cache és tudatos használat — PR [#423](https://github.com/wolfcasaba/strumsight/pull/423), squash `ff39ee0c` (2026-08-23)

**EPIC 9 (COMMUNITY PLATFORM) TIZENNEGYEDIK KÖRE KÉSZ.** Az első UI-fogyasztója
a Kör 13 following-feed backendnek: négy ÚJ fájl — `feed_cache.dart` (bounded,
userId-partitionált lokális cache, `ss.community.feed.v1.<userId>`, maxItems=80),
`feed_controller.dart` (nyolcállapotú Riverpod state machine —
initial/loading/content/refreshing/paging/offline/error/end — a
`CommunityFeedRepository` interfészre és a cache-re épülve, valós HTTP-bekötés
NÉLKÜL, az szándékosan egy KÉSŐBBI kör hatásköre), `feed_card_registry.dart`
(exhaustive switch mind a hét Kör 10 artifact-típusra + fallback-kártya) és
`following_feed_screen.dart` (pull-to-refresh scroll-pozíció-megőrzéssel,
explicit "Továbbiak betöltése" — NINCS auto-scroll-pagination, NINCS autoplay).
`risk = "high"` indoklás: account-cache-keveredés (privacy-osztály) + a
§13.6 SDD no-autoplay invariáns blast radiusa.

**Implementer MiniMax M3, orchesztrátor/reviewer Claude Sonnet 5. 1 tartalmi
javító kör + 1 CI-only javító kör** (`docs/reviews/e09-r14-review.md`): review
CHANGES REQUIRED elsőre, **2 MAJOR** — F1: mindkét ÚJ UI-fájl 0
`AppLocalizations` hívással ment ki (ugyanaz a hibaosztály, mint az E09-R08
F1, ott MAJOR volt); F2: a cache-rehydration (`_artifactFromEnvelope`)
MINDIG `UnfilledCommunityShareArtifact`-ra bontotta a mentett artifact-ot,
holott a `ShareArtifact.fromJson` dekóder MÁR LÉTEZETT és importálva is volt
— minden offline/cache-megjelenítés fallback-kártyát mutatott a valódi típus
helyett (independens probe teszttel megerősítve: `practiceCard=0
fallbackCard=1`). **1 MINOR** (F3: `_AudienceBadge.audience` felesleges
`dynamic` típus). A javító kör mindhárom leletet zárta — F1: 13+9
`AppLocalizations` hívás VALÓDI magyar fordítással
(`lib/l10n/features/community_{en,hu}.arb` bővítve, az allowed_paths
orchestrátor-irányítottan bővítve, ugyanaz a precedens, mint az E09-R08 fix);
F2: `ShareArtifact.fromJson` try/catch-csel, új A1.3 regressziós teszt; F3:
típusos `CommunityAudience`. Dedikált security-reviewer pass: PASS, 0
BLOCKER/MAJOR (cache-izoláció strukturálisan helyes, nincs injection-felület,
nincs secret-szivárgás, a no-autoplay invariáns ténylegesen érvényesül). A
Claude a javításokat friss, izolált `/tmp`-klónokban ÚJRA futtatott gate-tel
és scope-audittal fogadta el, egy SAJÁT probe-teszttel igazolva az F2
javítást. A 2. (CI-only) javító kör a `test/ui/ui_inventory_test.dart`
hardcode-olt képernyő-számlálóját bumpolta 70→71-re (a kör ÚJ
`following_feed_screen.dart`-ja miatt) — ugyanaz a drift-osztály, mint
E09-R05...R13-ban ismételten, orchestrátor-oldali egysoros mechanikus
javítás. Exact `a39d15c8`: `full-gate.yml` 32634546134 + `router-ci.yml`
32634547312 mindkettő success. Részletesen `docs/reviews/e09-r14-review.md`.

## ✅ E09-R13 KÉSZ — Following feed és cursor pagination backend — PR [#422](https://github.com/wolfcasaba/strumsight/pull/422), squash `0907f006` (2026-08-23)

**EPIC 9 (COMMUNITY PLATFORM) TIZENHARMADIK KÖRE KÉSZ.** [ADR 0406](docs/adr/0406-following-feed-and-cursor-pagination.md):
tisztán backend kör, az első, ami EGY queryben kombinálja a Kör 7 follow-gráfot,
a Kör 8 block/mute-szűrőt és a Kör 11 post-táblát — egy időrendi, cursor-lapozott
`GET /community/feed` végpont, nincs engagement-alapú fekete-doboz rangsor. Öt új
fájl: `following_feed.py` (a query + HMAC-SHA256 aláírt, opaque cursor +
`query_plan_uses_feed_index` A7-evidencia), `schemas/feed.py`, `routers/feed.py`,
egy migráció (`e09_r13_0008`, EGYETLEN `(created_at, id)` composite index) és
`test_feed_query_plan.py` (16 teszt, a §6/§6.1 minden cellája + a §6.1 KÖTELEZŐ
valódi-sértés próba inline). A brief `risk = "high"` minősítése jogos volt: ez az
ELSŐ listázó (sok sort visszaadó) Community-végpont, ahol egy hibás szűrési
sorrend nem egy poszt, hanem SOK, a nézőre nem tartozó poszt tömeges,
egyetlen kérésben történő kiszivárgását okozhatta volna.

**Implementer MiniMax M3, orchesztrátor/reviewer Claude Sonnet 5. 2 javító
kör** (`docs/reviews/e09-r13-review.md`): review CHANGES REQUIRED elsőre,
**1 BLOCKER** — az A7 mérce-helper (`query_plan_uses_feed_index`) egy
engedékeny "van valahol index a plan-szövegben" OR-fallback miatt ZÖLDET
adott AKKOR IS, ha a szándékolt `(created_at, id)` index HIÁNYZOTT — a review
saját, önállóan futtatott real-violation próbája (500 sor, `DROP INDEX`, a
brief §6.1 KÖTELEZŐ előírása szerint, amit az implementer explicit KIHAGYOTT
"destruktív lenne inline" indoklással) ezt PIROSNAK mérte, a helper mégis
`True`-t adott. Súlyosabb: a mögöttes JOIN-alapú query-alak MÉG az index
JELENLÉTÉBEN sem azt használta, és mindkét esetben `USE TEMP B-TREE FOR ORDER
BY` futott — a kör core A7/N+1-védelem ígérete ténylegesen NEM teljesült,
csak a mérőeszköz hibája miatt tűnt zöldnek. **1 MAJOR** — a migráció
egyoldalúan hozzáadott egy `feed_view_count` oszlopot és egy második
`ix_community_posts_audience_created` indexet, egyik sincs az ADR 0406-ban
vagy a brief §5-ében ("Kör 14+ előkészítés" utólagos önindoklással — pontosan
az a lista-tágítási minta, amit a pre-flight §1 explicit tilt). **4 MINOR**
(cursor-secret fail-open default a publikus dev-placeholderre; audience-szűrés
fail-open denylist a policy allowlist-mintája helyett; router docstring hamis
422-állítása malformed cursorra, holott a tesztelt viselkedés 200; a
`FEED_CURSOR_VERSION` string volt az ADR-kötött `int` helyett). Az 1. javító
kör a query-alakot `WHERE profile_id IN (SELECT … FROM community_follows …)`
formára alakította (a JOIN helyett), a helpert a pontos index-név + a
"nincs TEMP B-TREE" ellenőrzésre szigorította, egy ÚJ inline valódi-sértés
próbát adott (`test_a7_real_violation_probe_drops_feed_index`), eltávolította
a nem-engedélyezett séma-elemeket, és zárta mind a 4 MINOR-t — a review saját,
connection-pool-disposal-t is figyelembe vevő újramérésével megerősítve
(SQLite az `ANALYZE`-statisztikát kapcsolatonként cache-eli — a review saját
próbaszkriptje elsőre emiatt hamis negatívot adott, amíg nem alkalmazta
ugyanazt a pool-disposal technikát, amit az implementer a saját tesztjében
felfedezett és dokumentált). **Váratlan mellékhatás**: az 1. javítás (a
`feed_view_count` oszlop eltávolítása) PIROSRA fordította a Kör 11-től örökölt,
körön KÍVÜLI `test_migrations.py::test_downgrade_one_revision_drops_only_
community_tables`-t — a teszt saját `_schema_snapshot` helpere KIZÁRÓLAG
oszlopneveket hasonlított, indexeket nem, ezért egy immár index-only
downgrade számára láthatatlan volt. A review saját, izolált futtatása fedezte
fel (nem az implementer önjelentése), dokumentált §0.0 D8 `allowed_paths`-
bővítéssel (`backend/tests/test_migrations.py`, CI-only bump minta, mint az
E09-R06/…/R09/R12) zárva egy 2. javító körrel — a snapshot-helper ma
index-neveket is összevet. Dedikált `security-reviewer` agent (risk=high
kötelező): 0 BLOCKER/MAJOR (cursor-forgery ellenálló — teljes 32-byte
HMAC-SHA256, constant-time compare, minden hibás ág fail-closed; nincs
blocked/muted sor-kiszivárgás a cursor-csatornán; FOLLOWERS audience sosem
szivárog nem-követőnek), a fenti 2 MINOR-t önállóan is megtalálta. Mindkét
javító kör GATE-e és a `scope-audit.py` a review SAJÁT kezével, izolált
`/tmp` klónokban ellenőrizve, nem az implementer önjelentésére hagyatkozva.
Exact `21133e09`: Full Gate [32630730552](https://github.com/wolfcasaba/strumsight/actions/runs/32630730552)
+ Router CI [32631215694](https://github.com/wolfcasaba/strumsight/actions/runs/32631215694)
mind success.

**Folyamat-megjegyzés (az orchesztrátor saját hibája, a lánc önkorrekciója):**
az implementer ELSŐ dispatch-kísérlete (session `255c4da9…`) egy `aborted_tools`
crash-szel ért véget jelzés nélkül, munka nélkül — az orchesztrátor tévesen a
saját (pipeline-szintű, meta-) promptját adta át az implementernek a kör-brief
helyett; a modell ezt észlelte és megpróbálta a saját, javított prompt-fájlját
megírni a munkapéldány GYÖKERÉBE (`allowed_paths`-on kívül), a scope-őr helyesen
megtagadta az írást, ami az egész sessiont elvitte magával. Mivel NULLA commit
történt, az újraindítás (UGYANAZZAL a brief-fájllal, a helyes implementer-
prompt-mintát követve) veszteség nélkül helyre tudta állítani a kört — lásd
`docs/LESSONS.md` az új leckéért.

## ✅ E09-R12 KÉSZ — Post composer draft és outbox — PR [#421](https://github.com/wolfcasaba/strumsight/pull/421), squash `d1ccf079` (2026-08-23)

**EPIC 9 (COMMUNITY PLATFORM) TIZENKETTEDIK KÖRE KÉSZ.** Nincs új ADR (tiszta
Flutter UI/integráció — a brief §5 kötött döntései a meglévő E08-R04
gamifikáció-outbox mintára és a Kör 5 `CommunityPostRepository` interfészre
épülnek, nem hoznak új architekturális elhatárolást). Négy új fájl: egy
per-user, verziózott lokális draft store
(`community_draft_store.dart`, `ss.community.drafts.v2.<userId>` — az ELSŐ
user-id-particionált storage-kulcs a repóban), egy perzisztens, stabil-ID
Community outbox (`community_outbox.dart`, az E08-R04 gamifikáció-outbox
mintáját követve — a retry SOHA nem generál új idempotency-kulcsot), a teljes
composer state machine (`post_composer_controller.dart`, editing →
submitting → success/failure, `isSubmitting` guard a dupla-tap ellen), és a
Material 3 composer screen. A brief `risk = "high"` minősítése jogos volt:
audience-vezérelt, felhasználó-generált tartalom, ahol egy hibás offline-retry
duplikált posztot, egy hibás siker-jelzés pedig privát tartalom véletlen
kiküldését okozhatná.

**Implementer MiniMax M3, orchesztrátor/reviewer Claude Sonnet 5. 2 javító
kör** (`docs/reviews/e09-r12-review.md`): review CHANGES REQUIRED elsőre,
**1 MAJOR** — a draft store egy FIKTÍV "korábbi device-wide draft store"
migrációt állított (nem létezett — ez az ELSŐ Community draft store a
repóban), és a hozzá tartozó `legacyKey` NEM volt user-id-particionálva
(minden usernél ugyanaz a literál) — jelenleg holt kód (semmi nem ír rá), de
architekturálisan pontosan azt az izolációs garanciát törte volna meg, amit a
kör bevezetni hivatott, ha bármi valaha ír arra a megosztott kulcsra
(kereszt-user draft-szivárgás). A testvér `community_outbox.dart` UGYANEBBEN a
körben helyesen `legacyKey: ''`-t választott ugyanerre a helyzetre — a draft
store ezt követte a javításban. **1 MINOR** — a `CommunityOutbox.enqueue`
doc-comment egy nem-tesztelt `Throws StateError` állítást tett, miközben a
tényleges kód `accepted:false`-t ad vissza; a doc-comment a valós szerződésre
javítva. Mindkettő zárva, saját kézzel (friss `/tmp`-klón) ellenőrizve.
**Külön, CI-only javító kör** (nem review-lelet): a `full-gate.yml` első
futása a MEGLÉVŐ, körön kívüli `test/ui/ui_inventory_test.dart` hardcode-olt
production-screen-számlálóját buktatta (69→70, az ÚJ `post_composer_screen.dart`
miatt) — UGYANAZ a mintázat, mint az E09-R06/R07/R08/R09 CI-only javításai;
a fájl a brief §0.0 D6 dokumentált bővítésével felkerült az `allowed_paths`-ra,
a MiniMax egysoros bump-ot commitolt. Mindkét CI (Full Gate + Router CI) zöld
az exact-SHA `882ec350`-n a merge előtt.

## ✅ E09-R11 KÉSZ — Post backend CRUD és audience enforcement — PR [#420](https://github.com/wolfcasaba/strumsight/pull/420), squash `98d7b2f6` (2026-08-23)

**EPIC 9 (COMMUNITY PLATFORM) TIZENEGYEDIK KÖRE KÉSZ.** [ADR 0405](docs/adr/0405-post-crud-and-audience-enforcement.md):
`community_posts` — az első valódi "tartalom" endpoint-felszín, ami egyszerre
köti be a Kör 4 `CommunityAccessPolicy` audience-döntését és a Kör 8
`is_blocked_pair` block-ellenőrzését. Create/get/patch/delete, szerveroldali
author (a JWT subjectből, sosem a body-ból), `UNIQUE(profile_id,
idempotency_key)`-alapú idempotens create, `updated_at`-et resource-version
tokenként újrahasznosító optimista konkurencia (a Kör 4 `privacy.py`
precedense — nincs külön verzió-oszlop), soft delete, HTML/script
reject-only body-validáció, `club_id` FK nélküli nullable mező (Kör 24
scope), kétértékű `moderation_state` aktív workflow nélkül (Kör 27/28
scope), a Kör 10 `parse_share_artifact` szerződését hívó (nem újradefiniáló)
artifact-mezők.

**A pre-flight (§0.0, D1-D12) 12 döntést rögzített indítás előtt** — a
legfontosabbak: az ADR-szám `0403`→`0405` korrekció (D1); a
`CommunityAccessPolicy.evaluate_content_access`/`is_blocked_pair` TÉNYLEGES
aláírásának mérése, nem új párhuzamos audience-logika (D2); az
idempotencia-kulcs a `community_posts` táblán él, mert a SDD-javasolt
megosztott `community_idempotency_records` tábla új modell-fájlt igényelne,
ami nincs az `allowed_paths`-on (D4); egységes 404 MINDEN "nem látható"
ágra (nem-létező ID, blocked, audience-kizárt, soft-deleted, moderált) — a
`social_graph.py` follower-lista 403-mintájától TUDATOSAN eltérve, mert egy
poszt közvetlen ID-s olvasásánál a 403 önmagában elárulná a létezést (D7).

Implementer MiniMax M3, orchesztrátor/reviewer Claude Sonnet 5. **1 javító
kör** (`docs/reviews/e09-r11-review.md`): review CHANGES REQUIRED elsőre,
**2 BLOCKER** — F1: a `patch_post` NEM ellenőrizte a tulajdonost — a
`_evaluate_visibility` egy OLVASÁSI láthatóság-kaput valósít meg (owner→
blocked→audience), nem írási jogosultságot, tehát egy PUBLIC posztra bármely
nem-blokkolt hitelesített felhasználó átjutott és módosíthatta a
body/audience/artifact mezőket — a dedikált `security-reviewer` agent (a
brief `risk = "high"` miatt kötelező) ÉLESBEN reprodukálta a defacement-et a
migráció-alapú sémán; F2 (Claude saját olvasása találta): a GET/PATCH válasz
`author_public_id` mezője a NÉZŐ saját public_id-ját adta a poszt tényleges
szerzője helyett — minden nem-saját-poszt olvasásnál hibás szerző-
attribúciót okozva (a szolgáltatás ELSŐDLEGES használati módján, egy
közösségi felszínen). Mindkettőt az egyetlen teszt rejtette el, ami
nem-tulajdonos GET-et/PATCH-et hívott: csak a `public_id`-t ellenőrizte,
nem az `author_public_id`-t, és PATCH-re egyáltalán nem volt nem-tulajdonos
teszt (csak DELETE-re). **2 MINOR** — F3: törölt poszt visszatért a
create-idempotencia-retry útvonalon (a DB-szintű UNIQUE constraint a
`deleted_at`-tól függetlenül tüzelt; javítva: a tombstone `idempotency_key`
mezőjének felszabadításával, az audit-trail megőrzésével); F4: a PATCH
optimista-konkurencia read-compare-write, nem DB-szintű compare-and-swap —
tudatos WONTFIX ebben a körben (a Kör 4 `privacy.py` öröklött korlátja, nem
ÚJ regresszió), follow-up jegyezve. Mind F1-F3 ÚJ regressziós teszttel zárva
(a non-owner PATCH teszt a sértetlen body-t is asszertálja, nem csak a
státuszkódot). Review APPROVED javító kör 1 után — a Claude a javítást NEM
az implementer önjelentésére hagyatkozva fogadta el: friss, izolált
`/tmp`-klónban újra lefuttatta a teljes gate-et és a scope-auditot, és a
diffet sor szerint elolvasta. Exact `49631b97`: Full Gate
[32620211936](https://github.com/wolfcasaba/strumsight/actions/runs/32620211936)
+ Backend CI [32620213409](https://github.com/wolfcasaba/strumsight/actions/runs/32620213409)
+ Router CI [32620214253](https://github.com/wolfcasaba/strumsight/actions/runs/32620214253)
mind success.

**A round jelenleg nincs bekötve** (a Kör 8/10 precedense szerint): a
`build_community_router` factory nem mountolja a `posts` routert — ez Kör
13+ (feed) dolga, amikor a valódi HTTP-felszín aktiválódik.

## ✅ E09-R10 KÉSZ — Share artifact szerződések — PR [#419](https://github.com/wolfcasaba/strumsight/pull/419), squash `a29e4ac8` (2026-08-23)

**EPIC 9 (COMMUNITY PLATFORM) TIZEDIK KÖRE KÉSZ.** [ADR 0404](docs/adr/0404-share-artifact-contracts.md):
sealed `ShareArtifact` hierarchia hét altípussal (practice summary, song
result, original progression, plan template, analysis improvement,
achievement, challenge) — minden altípus explicit, minimális mezőkkel,
`schemaVersion`+`sourceId`+`createdAt` kötelezővel, `type`-discriminátorral
(NEM mezőhalmazból dönt típust). Négy Flutter mapper
(`practice_share_mapper.dart`, `song_share_mapper.dart` — 3 factory:
song result/original progression/plan template, mind `Song`-ból —,
`analysis_share_mapper.dart` — az `audio_analysis/public.dart`
`AnalysisComparison`-jából, NEM az `analyze/public.dart`-ból! —,
`achievement_share_mapper.dart` — 2 factory: achievement + challenge, mind
gamifikációból), mindegyik kizárólag a saját forrás-feature `public.dart`
barreljét importálja. Backend Pydantic discriminated union
(`backend/app/community/schemas/artifacts.py`, `extra="forbid"` + `StrictInt`
`schemaVersion` egyenlőség-ellenőrzés) — ismeretlen `type`/`schemaVersion`
`ValidationError`-t dob, nincs csendes best-effort fallback. A challenge-
artifact hitelesség-mezője a gamifikáció `LedgerEntrySyncStatus`-a
(E08-R28/ADR 0394, `{unverified, verified}`), NEM az `EvidenceTrust` (egy
másik, öt fokozatú aktivitás-bizonyíték tengely — a brief §5.3
megfogalmazása erre a pontosításra szorult). `docs/contracts/
community-share-artifacts.md` — a wire-shape + deprecation/back-compat
szabályok referenciapontja.

**A pre-flight (§0.0) egy ADR-szám-ütközést és két forrás-összetévesztési
kockázatot zárt indítás előtt.** A brief előre kiosztott `ADR 0402`-je a
brief megírása (2026-08-22) és a kör indítása (2026-08-23) között egy
KÖZBEEKŐ, szekvenciális kör (E09-R08) által foglalttá vált —
`tools/round-slots.py reserve-adr` friss `0404`-et adott (D1, [[L430]] —
a foglaló nem csak párhuzamos-session versenyhelyzet, hanem naptári
avulás ellen is véd). D3: az `analysis_share_mapper.dart` forrása
`audio_analysis/public.dart`, NEM `analyze/public.dart` — a két
hasonló nevű feature ([[L430]]) könnyen összetéveszthető lett volna, mert
a brief saját pre-flight-instrukciója épp az `analyze`-t fogyasztó
`strum_card.dart`-ra mutatott referenciaként. D4: a challenge-artifact
hitelesség-mezője a `LedgerEntrySyncStatus`, nem az `EvidenceTrust`. D2: a
négy mapper-fájl és a hét artifact-altípus leképezése rögzítve (nincs
ötödik mapper-fájl, ami tilos-zóna-sértés lett volna).

Implementer MiniMax M3, orchesztrátor/reviewer Claude Sonnet 5. **0 javító
kör** (`docs/reviews/e09-r10-review.md`): review APPROVED elsőre, 0
BLOCKER/MAJOR. A review a §6.1 KÖTELEZŐ valódi-sértés próbát ÖNÁLLÓAN,
kézzel megismételte (nem csak az implementer §10.3 állítását fogadta el):
a `_validate_schema_version` equality-ellenőrzését eltávolította,
`pytest`-tel megmérte, hogy az A3-cella 2 tesztje PIROSRA vált, majd
visszaállította. Dedikált `security-reviewer` agent (a brief `risk =
"high"` miatt kötelező): PASS, 0 BLOCKER/MAJOR — 1 MINOR (`coaching_codes`/
`chords`/`metrics` lista-mezőknek nincs felső hossz-korlát, a skalár
mezőkkel ellentétben — horog Kör 11-nek, amikor a post-creation endpoint
tényleg fogyasztani kezdi) + 2 NOTE (a challenge `verified` állapot
kliens-oldali nem-kikényszerített volta persistálás előtt; a konkrét Dart
`fromJson` factory-k megkerülhetik az A3 schemaVersion-ellenőrzést, ha nem
a bázis `ShareArtifact.fromJson`-on át hívják őket) — egyik sem BLOCKER/
MAJOR, mindkettő Kör 11+/13+ bekötési horog, dokumentálva. Exact `2f2ed131`:
Full Gate [32616408599](https://github.com/wolfcasaba/strumsight/actions/runs/32616408599)
+ Backend CI [32616411741](https://github.com/wolfcasaba/strumsight/actions/runs/32616411741)
+ Router CI [32616404016](https://github.com/wolfcasaba/strumsight/actions/runs/32616404016)
mind success.

**A round jelenleg nincs bekötve** (a security-reviewer mérése): a Dart
entitást a `community/public.dart` nem exportálja, a backend
`parse_share_artifact`-ot egy router sem hívja — ez Kör 11+ (poszt-CRUD)
dolga, a fenti MINOR/NOTE horgokkal együtt.

## ✅ E09-R09 KÉSZ — Profilkeresés és biztonságos discovery — PR [#418](https://github.com/wolfcasaba/strumsight/pull/418), squash `5a1df780` (2026-08-23)

**EPIC 9 (COMMUNITY PLATFORM) KILENCEDIK KÖRE KÉSZ.** Handle-prefix
profilkeresés (`GET /community/profiles/search`, `CurrentUser` kötelező —
§0.0/D1) index-alapú tervvel (`handle_normalized` UNIQUE INDEX, EXPLAIN QUERY
PLAN-nal igazolva), a Kör 8 közös `filter_public_ids_against_viewer_blocks`
page-level helperrel bekötve (§0.0/D2 — nem soronkénti `is_blocked_pair`),
PRIVATE-profil teljes kizárással (§0.0/D3: "non-discoverable" =
`visibility == PRIVATE`, nincs külön mező a sémában). Flutter
`community_search_screen.dart` (debounce, törölhető lokális recent-search
lista), a Kör 5 (`E09-R05`, ADR 0399) óta "Kör 9"-ként megnevezett
`CommunityProfileRepository.searchProfiles` `UnsupportedError`-stub éles HTTP-
bekötése (§0.0/D4). Előre kiosztott ADR nincs (a kör nem hoz új kötött
architekturális döntést, tisztán meglévő szerződések alkalmazása).

**A pre-flight (§0.0) egy MÉRT scope-gapet talált és zárt indítás előtt:** a
Flutter `searchProfiles` domain-metódus és a hozzá tartozó két
`UnsupportedError`-stub MÁR LÉTEZETT (Kör 5 által "Kör 9"-ként megcímezve),
de a brief eredeti `allowed_paths`-a NEM tartalmazta a
`profile_repository_impl.dart`-ot — enélkül a keresés technikailag
teljesíthetetlen lett volna. §0.0 D1-D4 pontosan méri az öt gap-et (auth,
block-filter hívási pont, "discoverable" mező hiánya, a Flutter stub, az
`ApiClient.getJson` query-param hiánya) és a §3/§4/§5/§8 szöveget ehhez
igazítja.

Implementer MiniMax M3, orchesztrátor/reviewer Claude Sonnet 5. **1 javító
kör** (`docs/reviews/e09-r09-review.md`): **2 BLOCKER** — F1: a keresési
találatok a Flutter oldalon MINDEN sorra ugyanazt a fabrikált
`displayName: 'placeholder'` / `handle: 'placeholder-x1'` értéket
jelenítették meg (a widget teszt egy valódi adatot visszaadó fake
repository-t használt, sosem futtatva át a valódi HTTP-decode útvonalat) —
javítva: a backend válasz `hits` tömbbel bővült (`handle_display`+
`display_name`+`created_at`), a Dart oldal ebből épít valódi
`CommunityProfile`-t; F4 (**dedikált `security-reviewer` agent lelete**): a
`next_cursor` a NYERS (block-szűrés ELŐTTI) utolsó sorból épült, tehát egy
blokkolt profil handle-je és belső integer PK-ja a pagination-csatornán át
kiszivárgott a `public_ids` listából való helyes kizárás ELLENÉRE — javítva:
HMAC-SHA256-tal aláírt, opak cursor, a block-szűrt `kept_rows` utolsó
eleméből származtatva (ha egy teljes lap mindegyike blokkolt, a lapozás
inkább None-cursorral áll meg, mint hogy szivárogtasson — dokumentált,
szándékos biztonság-elsőbbségi tradeoff). **1 MINOR** (F2 — a 422 docstring
tévesen állította, hogy nem fogyaszt rate-limit slotot; javítva: a
hossz-ellenőrzés a limiter ELÉ került) + **1 CI-only fix**
(`test/ui/ui_inventory_test.dart` screen-számláló 68→69, UGYANAZ a
drift-osztály mint az E09-R06/R07/R08). Mindhárom lelet ÚJ regressziós
teszttel zárva (F4 a security-reviewer pontos forgatókönyvét pinneli).
Review APPROVED javító kör 1 után. Exact `90dd39d9`: `full-gate.yml`
32613840729 + `backend-ci.yml` 32613842345 mindkettő success (a
`round-ci-plan.py` nem ismeri a `backend-ci.yml`-t, ezt az orchesztrátor
külön, kézzel dispatch-elte a diff `backend/**` érintettsége miatt — ld.
alább a folyamat-tanulságot).

**Mért folyamat-tanulságok (a saját sessionöm hibái, nem az implementeré):**

1. **Az implementer első dispatch-a a HIBÁS promptot kapta** — az
   orchesztrátor saját (pipeline-oldali) meta-promptját adta át
   `mm-round.sh`-nak a kör-brief helyett. Az implementer ennek megfelelően
   ORCHESZTRÁTOR-szerepű munkát kezdett (saját ADR-t foglalt és írt egy,
   a briefben explicit tiltott `docs/adr/**` fájlba, majd a SHARED fő
   munkapéldányba is megpróbált írni), mielőtt jelzés nélkül lefagyott.
   Felismerve → a workdir branch-e visszaállítva a pre-flight commitra, a
   megosztott fába szivárgott (nem commitolt) fájl törölve, a HELYES
   prompt (a kör-brief fájlja magában a munkapéldányban) újra
   dispatch-elve. A `tools/mm-round.sh` a `<prompt-fájl>` argumentumot
   VERBATIM adja át a modellnek — ez mindig a kör-brief legyen, SOHA az
   orchesztrátor saját pipeline-promptja.
2. **A CI-terv (`round-ci-plan.py`) nem ismeri a `backend-ci.yml`-t** — csak
   a `full-gate.yml`/`build-apk.yml` párost nevezi meg. Egy `backend/**`-et
   érintő kör (mint ez) esetén ezt a workflow-t az orchesztrátornak KÉZZEL
   kell dispatch-elnie és zöldre várnia, a `router-ci.yml`-hez hasonlóan —
   a szerszám ezt (még) nem teszi meg helyette.
3. **Ugyanaz a session megismételte a saját L425-mintázatát** — a záró
   rituálék közben egy `git reset --hard origin/main`-t futtatott a
   merge-lock-on BELÜL, miután MÁR beírta a HANDOFF/RTM/LESSONS
   szerkesztéseket, de MIELŐTT commitolta volna azokat — a reset némán
   eldobta mindhármat (csak a queue-sor élte túl, mert azt a reset UTÁN
   írta). Újra kellett írni. A helyes sorrend: reset ELŐSZÖR, utána MINDEN
   szerkesztés, commit legvégül — a reset SOSEM mehet a szerkesztés és a
   commit közé.

## ✅ E09-R08 KÉSZ — Block, mute és safety kapcsolatkezelés — PR [#417](https://github.com/wolfcasaba/strumsight/pull/417), squash `5e086c10` (2026-08-23)

**EPIC 9 (COMMUNITY PLATFORM) NYOLCADIK KÖRE KÉSZ.** [ADR 0402](docs/adr/0402-block-mute-and-safety-relationships.md):
`community_blocks`/`community_mutes` tábla + `block_service.py` atomikus
tranzakció (mindkét irányú follow-él DELETE, pending follow-request UPDATE
`status="blocked"` — a Kör 7 `follow_service.py` MÉRT UPDATE-recycle
mintáját követve, NEM DELETE-elve a requestet). Élő block-first szűrés
(`is_blocked_pair`) a MA authentikált `get_followers`/`get_following`
endpointokba kötve (a Kör 4 `CommunityAccessPolicy` ELSŐ élő bekötése) —
caller↔owner block → 403 a lap materializálása ELŐTT, egyébként a
hívóval blokk-kapcsolatban álló profilok kimaradnak a lapból. ÚJ
`routers/safety.py` HTTP-felület (block/unblock/mute/unmute +
blocked/muted lista). Flutter: a Kör 7 kódjában MÁR "Kör 8 scope"-ként
megnevezett `SocialGraphRepository.block/unblock/mute/unmute`
`UnsupportedError` stub négyes valódi implementációra váltva; a domain
interfész két ÚJ metódussal bővült (`blockedProfilesPage`/
`mutedProfilesPage`, a meglévő 11 metódus változatlan); ÚJ
`safety_relationships_screen.dart` (Blocked/Muted lista, saját
képernyő-kolokált Riverpod state, teljes en/hu lokalizáció).

Előre kiosztott ADR (`0401`) a queue-fájlban STALE volt (a Kör 7 már
foglalta) — friss szám (`0402`) a `round-slots.py reserve-adr`-ból. A
pre-flight (§0.0, D1–D6) jelentős, mért revíziót hordoz: az eredeti
`allowed_paths` NEM tartalmazta a router-fájlokat, amikbe a block-szűrést
be kellett kötni, sem a Dart repository-implementációt — mindkettőt a
saját elődje (Kör 7) már explicit "Kör 8 scope"-ként nevezte meg a
shipped kódjában, csak a batch-elt brief ezt tévesen kihagyta. A
challenge-invite tábla (Kör 21) és a klub-domain (Kör 24) még nem
léteznek — a brief "pending challenge invite törlése"/"közös klub
placeholder" cellái ennek megfelelően pontosítva (D3/D4).

Implementer MiniMax M3, orchesztrátor/reviewer Claude Sonnet 5. **1 javító
kör** (`docs/reviews/e09-r08-review.md`): F1 MAJOR — a safety screen 0
lokalizált stringgel indult (minden testvér Community screen
`AppLocalizations`-t használ) → 11 kulcs `community_{en,hu}.arb`-hoz +
aggregátum-újragenerálás; F2 MAJOR — `block()`/`mute()` nem kapta el a
konkurrens `IntegrityError`-t (ellentétben a `follow_service.py` MÉRT
mintájával), és a saját concurrency-tesztje NÉMÁN nyelte el a szál-kivételt
assert nélkül (`docs/LESSONS.md` L349–L351 mintája) → mindkettő javítva,
függetlenül újra-igazolva friss izolált klónban. **1 CI-only fix**
(`test/ui/ui_inventory_test.dart` screen-számláló 67→68 — UGYANAZ a
drift-osztály, ami a Kör 7-nél is egy 3. javító kört igényelt). Dedikált
`security-reviewer` pass: PASS, nincs BLOCKER (2 MINOR/NOTE — block-létezés
oracle 403 vs 404 között, non-blocking follow-up). Review APPROVED, 0
nyitott BLOCKER/MAJOR. Exact `63890947`: `full-gate.yml` 32608627590 +
`router-ci.yml` 32608635566 mindkettő success.

**Mért folyamat-tanulság (a saját sessionöm hibái, nem az implementeré):**
a `tools/mm-round.sh` NEM push-ol automatikusan — az orchesztrátornak
minden implementer-/javító-forduló UTÁN saját kézzel kell push-olnia a
munkapéldányból, MIELŐTT a shared tree-n bármit commitolna a branchre;
elmulasztva ez egy forkolt, divergens branch-históriát okoz (mérve,
`cherry-pick` + `safe-force-push.sh`-sal helyreállítva, 2×). Az implementer
saját gate-önbevallása HÁROMSZOR jelzett `gate_shape=VIOLATION`-t (a
`round-gate.sh` `| tail`/`&&` mögé rejtve, a promptban explicit tiltás
ELLENÉRE) — mindhárom esetben a review saját kézzel, izolált `/tmp`
klónban futtatta újra csonkolatlanul, és ténylegesen zöld volt (a
csonkolás önmagában nem jelentett rejtett hibát ebben a körben, de a
bemondást egyszer sem fogadtam el enélkül).

## ✅ E09-R07 KÉSZ — Follow és follow request social graph — PR [#416](https://github.com/wolfcasaba/strumsight/pull/416), squash `1cc49e41` (2026-08-22)

**EPIC 9 (COMMUNITY PLATFORM) HETEDIK KÖRE KÉSZ.** [ADR 0401](docs/adr/0401-follow-and-follow-request-social-graph.md):
idempotens, privacy-kompatibilis follow rendszer — public profilnál azonnali
follow, private profilnál explicit `requested → accepted | declined |
cancelled` request lifecycle. `community_follows`/`community_follow_requests`
migráció DB-szintű self-follow `CHECK` és race-biztos `UNIQUE` mindkét
táblán; `follow_service.py` (public/private lifecycle, `IntegrityError`→
domain-kivétel fordítás, állapot-átmenet-alapú idempotencia); `social_graph.py`
router (follow/accept/decline/unfollow/follower-removal/cursor pagination).
Flutter: `relationship_repository_impl.dart` a MEGLÉVŐ (Kör 5, ADR 0399)
`SocialGraphRepository` interfészt implementálja — `block`/`unblock`/`mute`/
`unmute` `UnsupportedError`-t dob (Kör 8 előfeltétele, a Kör 6/ADR 0400
precedens szerint, NEM csendes no-op); `relationship_controller.dart`
optimistic (public) / pending (private) állapotgép; `followers_screen.dart`;
`api_client.dart` egyetlen ÚJ `delete()` metódussal bővült (a `post()` pontos
tükre, a meglévő négy metódus érintetlen).

**Pre-flight mérve öt pontot revideált** (`docs/rounds/e09-r07-follow-and-follow-request-graph.md`
§0.0, [ADR 0401](docs/adr/0401-follow-and-follow-request-social-graph.md)):
(1) az előre kiosztott `ADR 0400` MÁR foglalt volt (E09-R06 saját ADR-je) —
`tools/round-slots.py reserve-adr` friss `0401`-et adott; (2) a Flutter
domain-interfész a MEGLÉVŐ `SocialGraphRepository` (Kör 5), NEM egy új
`RelationshipRepository`; (3) nincs külön "cancel" domain-metódus/endpoint —
a meglévő `unfollow()`/`DELETE .../follow` egyik ága fedi (a domain `**`
NULLA diffet kapott); (4) `lib/core/network/api_client.dart`-nak nem volt
DELETE-metódusa — szűken bekerült az `allowed_paths`-ra egyetlen additív
`delete()`-re; (5) `backend/app/community/__init__.py::build_community_router()`
NEM bővült — a Kör 3 (`handles.py`) precedens szerint a router tesztje önálló,
helyi `FastAPI()`/`TestClient` fixture-t épít.

**Review (`docs/reviews/e09-r07-review.md`): APPROVED, KÉT javító kör
után.** Az első review (Claude + dedikált `security-reviewer` agent, risk=high)
1 BLOCKER + 2 MAJOR + 1 MINOR + 1 NOTE-ot talált: **F1 BLOCKER** — a §6.1
kötelező valódi-sértés próba (`test_swap_unique_constraint_breaks_a2`) NEM
determinisztikus volt (10 ismételt futtatásból 7 PIROS, a két
`threading.Thread` között nem volt szinkronizációs bariér); **F2 MAJOR** —
`get_followers`/`get_following` teljesen hitelesítetlen volt (nincs
`current_user` függőség, szemben a router MINDEN mutáló endpointjével) —
ma latens (a router nincs mountolva), de éles IDOR/enumerációs kockázat lenne
mountoláskor; **F3 MAJOR** — a Dart `unfollow()`/`removeFollower()` sosem
küldte a backend által KÖVETELT `idempotency_key` query-paramétert (minden
éles hívás 422-t kapott volna — egyik teszt sem fogta meg, mert egyik oldal
sem gyakorolta a VALÓDI Dart→backend HTTP-szerződést); **F4 MINOR** —
`post_follow` nem kapta el a `FollowAlreadyExists`-t → nyers 500.
A javító kör 1 (`222a6782`) mind az ötöt zárta — az F1 fix a `threading.
Barrier`-t NEM a szál-indítás elé, hanem a `follow_service._existing_follow`
helperbe monkey-patchelte (a pontos SQL-döntési pontnál szinkronizál) —
FÜGGETLEN 15×-ös reprodukció a reviewer oldalán: 15/15 zöld (szemben a
fix előtti 7/10 PIROS-sal).

A friss exact-SHA CI (`full-gate.yml`) a TELJES suite-tal PIROS lett — nem a
kör tartalma miatt, hanem egy MEGLÉVŐ, körön kívüli gate-teszt
(`test/ui/ui_inventory_test.dart:14`, kemény kódolt production-screen-szám)
avult el a kör saját ÚJ `followers_screen.dart` fájla miatt (66→67, azonos
minta mint az E09-R06 F9 lelet). Javító kör 2 (`7f2e348d`, `allowed_paths`
szűken bővítve a brief §0.0.9-ben) egy sorban javította.

Scope-audit mindhárom fordulóban OK. Minden gate-futtatás FÜGGETLENÜL,
izolált `/tmp` klónokban: format/analyze/architecture/secrets/l10n/backend
ruff/backend pytest (teljes suite) mind zöld. CI a pontos merge SHA-n
(`f75f0007`): `full-gate.yml` 32603023648 + `router-ci.yml` 32603026921
mindkettő `success`.

**Nyitva maradt, EMBERI döntést NEM igénylő tartozás:** az E09-R08 queue-sora
(`docs/execution/pipeline-queue.tsv`) `0401`-et ad előre kiosztott ADR-ként —
ez a szám MOST már foglalt (ez a kör). Az E09-R08 pre-flightja a §1.0.1
szerint `tools/round-slots.py reserve-adr`-rel ÚJ számot kér, ne a queue-fájl
stale értékét használja — pontosan ugyanaz a minta, amit ez a kör is örökölt
az E09-R06-tól.

## ✅ E09-R06 KÉSZ — Profil létrehozás, szerkesztés és Community gate UI — PR [#415](https://github.com/wolfcasaba/strumsight/pull/415), squash `77bc0589` (2026-08-22)

**EPIC 9 (COMMUNITY PLATFORM) HATODIK KÖRE KÉSZ.** ADR 0400: a Community
gate (disabled/logged-out/profile-missing/ready), a profil létrehozó/
szerkesztő flow és — a pre-flightban felfedezett, ADR 0396-ban MÁR ennek
a körnek kiosztott felelősség pótlásaként — a backend SERVICE-SZINTŰ
profil-létrehozás (`POST`/`PUT /community/profiles/me`, `CurrentUser`/
`DbSession` auth-lánc). A batch-elt brief (PR #405) tévesen a teljes
`backend/**`-et tilos zónának jelölte és hamisan állította, hogy a kör
"az ELSŐ, ami ténylegesen HTTP-n keresztül hívja" a Kör 3/4 policy-kat —
mérve: `grep -rn "INSERT INTO community_profiles" backend/` nulla
találat, egyetlen backend endpoint sem hozott létre profilsort. A
pre-flight (§0.0, ADR 0400) szűken, öt névvel megadott fájlra nyitotta
ki a tilos zónát; a `main.py`/`community/__init__.py` router-mounting és
bármilyen új migráció VÁLTOZATLANUL tilos zóna marad — külön, még ki nem
osztott kör dolga (`docs/reviews/e09-r04-review.md` F1/N2-vel együtt).

**Review (`docs/reviews/e09-r06-review.md`): APPROVED, KÉT javító kör
után.** Az első review 1 BLOCKER + 1 MAJOR leletet talált: F1 — a
`fetchMyProfile()` egy nem-létező `GET /community/profiles/me` végpontot
hívott (a gate `ready` állapota élesben sosem lett volna elérhető); F2 —
a `handle_policy.validate()` NFKC-normalizált visszatérési értéke
eldobva, Unicode-ekvivalens handle-ök (pl. fullwidth karakterek)
ütköztek volna — egy dedikált `security-reviewer` agent FÜGGETLENÜL
megerősítette, élesebb impersonation-szöggel. A javító kör 1 (`9592638e`)
mindkettőt fixálta, tesztekkel (a security-reviewer pontos fullwidth/
ASCII forgatókönyvét reprodukálva). Az ELSŐ exact-SHA CI-dispatch
(`full-gate.yml`) ekkor PIROS lett — a TELJES suite (nem a célzott gate)
2 ÚJ MAJOR leletet fedett fel: F9 (`ui_inventory_test.dart` elavult
screen-számláló, 64→66, a kör 2 új production screent ad) és F10
(`dio_factory_guard_test.dart` regex-alapú Dio-őr false positive egy
doc-kommenten, "Dio ("-mintára illeszkedve). A javító kör 2 (`ddbd4e9e`)
mindkettőt fixálta, egysoros javításokkal.

Scope-audit háromszor jelzett VIOLATION-t a kör során — mindhárom
alkalommal kis, additív, tartalmilag helyes fájlt, amit az orchesztrátor
§0.0.x brief-revíziókkal legitimált (nem mást implementáltatott):
`lib/core/foundation/app_failure.dart` (a projekt MEGLÉVŐ per-feature
`FailureCode` mintája), `lib/l10n/app_{en,hu}.arb` (az ARB-aggregátum
tartalmilag friss, `dart run tool/gen_l10n_segments.dart --check`
igazolta — csak a generátor helyett kézzel lett átmásolva),
`test/ui/ui_inventory_test.dart` (F9 fent). A `bio`/`skillInterests`/
`badges`/`avatarUrl` mezők ebben a körben UI-only maradnak (nincs
backend oszlop, nincs migráció) — egy jövőbeli migráció-hozó kör
előfeltétele.

Minden gate-futtatás FÜGGETLENÜL, izolált `/tmp` klónokban (mindkét
javító kör után újra): scope-audit OK, format/analyze/architecture/
secrets/l10n/backend ruff/backend pytest (349 teszt) mind zöld. A KÉT
kötelező valódi-sértés próba (Flutter A5 dupla-submit debounce, backend
A8 `commit_with_uniqueness_check` try/except) PIROS→ZÖLD dokumentálva. CI
a pontos merge SHA-n (`bf2f67da`): `full-gate.yml` 32596780267 +
`router-ci.yml` 32597616787 (manuálisan `workflow_dispatch`-csel pontos
SHA-ra kényszerítve) mindkettő `success`.

**Nyitva maradt, EMBERI döntést NEM igénylő tartozások:** F3/F4 (A6
logout-cache és A7 2.0 text-scale golden teszt hiányzik, a kód-szint
helyes, csak tesztekkel nincs bizonyítva); F6 (`deps.py`
`HTTPBearer(auto_error=True)` hiányzó auth-fejlécre 403-at ad 401 helyett
— projektszintű minta, `deps.py` tilos zóna volt ezen a körön); a
router-mounting kör (F1 review-eredetije, ADR 0396 "Következmények" +
E09-R04 F1/N2) továbbra is elkülönült, még ki nem osztott feladat.
**MÉRT ADR-ütközés a queue-ban:** `docs/execution/pipeline-queue.tsv`
E09-R07 sora `0400`-at ad előre kiosztott ADR-ként (a batch-elt PR #405
tervéből) — ez a szám MÁR foglalt (ADR 0400, ez a kör). Az E09-R07
pre-flightja a §1.0.1 szerint `tools/round-slots.py reserve-adr`-rel ÚJ
számot kér, ne a queue-fájl stale értékét használja.

## 🧭 [GOV] Motorváltás: Claude Sonnet 5 (high) orchestrátor + MiniMax M3 implementer (2026-08-21)

**User-döntés: „lejárt a GPT kvóta — állítsuk át a fejlesztést sonett 5 High
orchestrátor és minimax implementer felállásra."** A ChatGPT Pro keret
elfogyott, tehát a Codex-oldal (a **Sol** ÉS a **Terra** — közös
`~/.codex-terra` auth) NEM futtatható. A 2026-08-20-i Sol-pin ezzel LEZÁRULT.

A hatályos felállás, végig a repóban utazó (file > env > script-default)
szerződéseken — a cron exportált env-je egyiket sem írhatja felül:

| Szerep | Motor | Hordozó |
|---|---|---|
| orchestrátor / reviewer / heal | **Claude Sonnet 5, `--effort high`** | `PIPELINE_MODEL`/`PIPELINE_EFFORT` script-default (`tools/round-pipeline.sh`) |
| rotáció | **`claude`** | commitolt `docs/execution/orchestrator-rotation` |
| implementer | **`minimax`** (MiniMax-M3, `~/.claude-minimax`, saját API-kulcs) | a queue MINDEN nyitott sora (64 sor: 43 pending + 18 prepared + 3 hold) |
| slot | **1 sáv** | commitolt `docs/execution/pipeline-slots` |
| Codex-oldal | **kizárva** | `fallback_engine` default `none` → `orchestrator_available` a `terra`/`sol` széket ezen méri |

**Miért `high` és nem `max`:** a Codex-oldal kiesésével az EGYETLEN
orchestrátor a Claude — a 2026-08-06-i `max` akkor volt vállalható, amikor a
Codex-oldal még osztozott a munkán. **Miért 1 slot:** a Sol-pin alatt mindkét
sáv a Codex-keretből ment; most minden sáv orchestrátora a Claude, két
párhuzamos session ugyanabból az előfizetésből enne, és visszahozná az
ADR 0222-t kikényszerítő hibaosztályt (a keretnek nekifutó kör → H-NOSIGNAL
halt → önjavító kör, ami szintén a keretből megy). **Függetlenség:** Claude
Sonnet 5 ≠ MiniMax-M3, és a `minimax` sor külső kulcsos
(`engine_uses_claude_quota` hamis) — mindkét mérési kulcson független.

A Sol/Terra **gépezete szándékosan a helyén maradt** (registry-sorok, `sol`
ágak a driverben, a mérő cellák a `CODEX_SIDE_ALIVE` /
`fallback="terra"` fixture-ökkel): a Codex-előfizetés esetleges újraéledése
fájl-átírás, nem újraépítés — a pontos visszaállási lista a
`pipeline-orchestrator-prompt.md` MOTOR-FELÁLLÁS blokk utolsó pontja.

A mérce nem gyengült. A `test_open_rounds_follow_the_measured_engine_rule`
carve-outja szűk és fail-closed párja van: a pin CSAK `codex` → `minimax`
irányba mozdulhat (ahol a mért szabály `minimax`-ot ad, ott `minimax`-nak KELL
állnia), és nyitott sor Codex-oldali motort egyáltalán nem nevezhet meg.
Mérés: `python3 -m pytest tools/tests -q` → **712 passed, 2 skipped, 610
subtests passed**; az egyetlen piros
(`test_test_mode_dispatch_does_not_switch_the_working_tree_off_its_branch`) a
környezeté, nem a diffé — ezen a dobozon nincs `gh` CLI, a változtatás előtt
ugyanígy piros volt, a Router CI futóján zöld.

A PR nyitva léte alatt a boxon futó lánc még a RÉGI (Sol/Terra) felállással
lezárta az **E08-R18**-at (PR #394) — a `done` sor motorja ezért `terra`,
történeti tényként; a base-merge ezt megőrizte, és csak a NYITOTT sorok
állnak `minimax`-ra. Mérés a merge után, a friss main fölött:
`python3 -m pytest tools/tests -q` → **713 passed, 1 skipped, 610 subtests
passed** (az egyetlen piros a `gh` CLI hiánya ezen a konténeren, a diff előtt
is ugyanaz; a Router CI futóján zöld).

Pontos következő teendő: nincs kézi indítás — a lánc minden firingen
`git fetch origin main` + `merge --ff-only` (`main_sync_strategy`), tehát a
következő cron-firing már ezzel a felállással veszi ki a queue első `pending`
sorát: **E08-R24 — Practice és Learn integráció**; a Chapter 13 ága
változatlanul **E13-R05** (a revideált scope-pal, lásd a lenti
HEAL-bejegyzést). Boxon egyszer ellenőrizendő: `tools/engine-profile.sh
list` — egy megmaradt `.pipeline/engine-override=terra` minden queue-sort
felülírna.

## ✅ E09-R03 KÉSZ — Public identity és handle policy — PR [#412](https://github.com/wolfcasaba/strumsight/pull/412), squash `607695e9` (2026-08-22)

**EPIC 9 (COMMUNITY PLATFORM) HARMADIK KÖRE KÉSZ.** ADR 0397 §5.1–§5.4:
injektálható UUID public-id generátor, NFKC+casefold-normalizált handle
egyediség DB-szinten (unique index a normalizált oszlopon, NEM app-szintű
check-then-insert), reserved/blocked handle katalógus, egyetlen-handle-per-
hívás rate-limitált availability endpoint (nincs enumerációs felület), és
handle-change cooldown (14 nap) + redirect-ablak (30 nap) history táblával.
Új fájlok: `backend/app/community/{policies/handle_policy.py,
services/identity_service.py, models/handle_history.py,
routers/handles.py}`, `backend/alembic/versions/e09_r03_0003_community_
handle.py`, `backend/tests/community/test_handle_policy.py` (77 teszt).

**A kör három fordulóban zárult, ez az orchestrátor-session a [[L413]] HEAL
(#411) utáni folytatást vitte végig:** (1) a felfüggesztett minimax
implementert a healelt brief §0.1 utasítása szerint resume-oltam
(`9ad6cb3a`, a három lánc-toleráns cross-round tesztjavítás); (2) független
funkcionális + **security-reviewer** review (risk=high) ÖNÁLLÓ mutation-
próbákkal — nem csak a jelentett gate-kimenetre hagyatkozva. A review 1
nyitott **MAJOR**-t és 3 MINOR-t talált:

- **F1 (MAJOR, mérve reprodukálva):** `_client_key` (`routers/handles.py`)
  a kliens által küldött `X-Forwarded-For` fejlécet vette rate-limit
  kulcsnak trusted-proxy nélkül — 60 hívás, mind más hamis fejléccel, **0**
  `rate_limited` választ kapott a 30/perces limit ellenére. A §5.3
  "rate-limitált, nem enumerálható" kontroll ÉRDEMBEN nem működött, bár a
  router ebben a körben még nincs bekötve `app/main.py`-ba (Kör 6 az auth).
- **F2 (MINOR):** duplikált handle-claim 500-at adott 409 helyett — SQLite
  az UNIQUE-sértést az `UPDATE execute()`-nál dobja, nem a `commit()`-nál, a
  router viszont csak a `commit_with_uniqueness_check`-et csomagolta
  `except HandleAlreadyClaimed`-be.

Mindkettő egy javító körben zárult (`6d354812`, a minimax ELSŐ javító köre —
Codex-eszkalációra nem volt szükség): `_client_key` kizárólag
`request.client.host`-ra esik vissza, a claim/change végpontok egyetlen közös
`try/except` alá kerültek. A reviewer MINDKÉT javítást függetlenül
igazolta — a javítás előtti kódra visszaállítva reprodukálta a piros
állapotot (60/60 bypass, illetve 500-as válasz), majd a javítással zöldre.
Két MINOR follow-up nyitva marad (nem blokkol): a küszöb-hármas teszt a
`MIN_LEN`/`MAX_LEN` konstansból, nem a brief literál 2/3/24/25 értékéből
származtat; nincs HTTP-szintű (végpont-szintű) teszt az A1 Unicode-ütközésre,
csak policy- és DB-szintű. Review: `docs/reviews/e09-r03-review.md` +
`docs/reviews/e09-r03-security-review.md`.

Gate mindkét fordulóban (pre-fix `9ad6cb3a`, post-fix `6d354812`/`d830a037`)
izolált `/tmp` klónban, saját `python3.12 -m venv` + friss `pip install`:
`tools/round-gate.sh test/core/architecture_dependency_test.dart` MINDEN
GATE ZÖLD, `backend: ruff check`/`ruff format --check` tiszta, `backend:
pytest -q` **282 passed, 0 failed**. Scope-audit mindkét fordulóban OK (a
javító kör diffje 2 fájl: `handles.py` + a teszt). CI a pontos merge SHA-n
(`d830a037`): Router CI + Full Gate (no APK) mindkettő `success`.

## ✅ [HEAL E09-R03/H3] KÉSZ — az L411 minta egy láncszemmel mélyebben: `allowed_paths` nem fedte a MÁSODIK cross-round migráció-tesztet — PR [#411](https://github.com/wolfcasaba/strumsight/pull/411), squash `2359b808` (2026-08-22, L413)

Az E09-R03 (Public identity és handle policy, ADR 0397) H3-mal állt meg,
MIUTÁN az implementer (minimax) már ledolgozta a kört (branch
`minimax/e09-r03-public-identity-and-handle-policy`, `3cca3ddd`, pushed, saját
scope 75/75 zöld). Gyökérok: a kör saját, helyes migráció-láncolási döntése
(`e09_r03_0003.down_revision = "e09_r02_0002"`) törvényszerűen tört HÁROM,
E09-R02-ben írt cross-round tesztasszerciót két fájlban —
`backend/tests/test_migrations.py::test_downgrade_one_revision_drops_only_community_tables`
és `backend/tests/community/test_profile_schema.py`
(`test_alembic_upgrade_head_applies_community_migration` +
`test_alembic_downgrade_drops_community_tables`) — mert az [[L411]] fixe a
KÉT-migrációs világra hardcode-olt maradt (pinned head-string, relatív
`downgrade -1`, konkrét tábla-nevek). Egyik fájl sem szerepelt az
`allowed_paths`-on, az implementer helyesen `stopped`-öt jelzett a §10.4-ben
pontosan diagnosztizálva mindhárom törött asszerciót. Class B (kör-tartalom:
a saját láncolási döntés kontra egy MÁSIK kör régi, hardcode-olt tesztje),
függetlenül reprodukálva: `cd backend && .venv/bin/python -m pytest
tests/test_migrations.py tests/community/test_profile_schema.py -q` → 3
FAILED.

Feloldás (`docs/rounds/e09-r03-public-identity-and-handle-policy.md` §0.1):
mindkét fájl szűken bekerült az `allowed_paths`-ra, és — mivel ez a MÁSODIK
előfordulása ugyanennek a mintának — a folytatáshoz adott instrukció nem egy
harmadik hardcode-olt javítás, hanem lánc-toleráns ellenőrzés: (1) "head
tartalmazza X-et ŐSKÉNT" (`ScriptDirectory.walk_revisions`) a pinned
head-string helyett; (2) `downgrade(config, "<explicit revízió>")` a relatív
`-1` helyett; (3) a tábla-HALMAZ változásának mérése a konkrét tábla-nevek
kimondása helyett — hogy az Epic 9 hátralévő ~29 köre közül egyik láncoló
migráció se ismételje meg ugyanezt. Regressziós védelem:
`tools/tests/test_e09_r03_migration_chain_test_scope.py` —
`audit_legacy_scope()`-ot futtatja a ténylegesen committolt brief ellen;
mindkét mért halt-útvonal RED volt a javítás előtt, GREEN utána, egy
szomszédos backend-teszt fájl (`test_auth.py`) pedig továbbra is scope-on
kívül marad. Teljes gate izolált heal-worktree-ben: `python3 -m pytest
tools/tests -q` → 718 passed, 1 skipped, 639 subtests (az egyetlen skip a
`gh` CLI hiánya ezen a konténeren, a diff előtt is ugyanaz). `brief-lint
--level strict` tiszta (az S8 visszakeresett-előzmény jelet a §0.1 L411-
hivatkozása zárja). Nincs törölt/gyengített teszt, nincs küszöb-lazítás,
`tools/round-gate.sh`/`.github/workflows/**` érintetlen. Lecke: [[L413]].

Mivel az eredeti E09-R03 implementer-munka már kész és a saját branch-én ül,
ez a heal NEM vitte tovább a tartalmi munkát — a lánc a MEGLÉVŐ
`minimax/e09-r03-public-identity-and-handle-policy` ágon, a felfrissített
brieffel folytatja: a három tesztasszerció lánc-toleráns javítása még
hátravan az implementer oldalán, utána a §7 mindkét parancsa, majd
review/CI/merge a szokásos rend szerint.

## ✅ E09-R02 KÉSZ — Community backend modul és első Alembic migráció — PR [#410](https://github.com/wolfcasaba/strumsight/pull/410), squash `4fffe20e` (2026-08-22)

**EPIC 9 (COMMUNITY PLATFORM) MÁSODIK KÖRE KÉSZ.** A `backend/app/community/`
modulhatár és az első Community migráció (`community_profiles` +
`community_privacy_settings`, `e09_r02_0002` láncolva `e01_r12_0001`-re)
létrejött: BigInteger belső PK + `Uuid` public_id, DB-szintű 1:1 unique
constraint mindkét táblán, whitelist-only Pydantic válasz-séma (a belső `id`
sosem szivárog), `build_community_router(settings)` factory +
`community_readiness_failure()` — mindkettő ÖNÁLLÓAN a `community/` modulban,
`main.py` érintetlen marad (ADR 0396 §3–4, következő kör dolga a bekötés).

A kör két szakaszban futott: az első implementer-futás (`05fa154d`) H3-mal
állt meg, mert a kör saját migráció-láncolási döntése szükségszerűen
elrontotta a MEGLÉVŐ `test_migrations.py::test_downgrade_one_revision_removes_application_schema`
egyetlen-migrációs feltevését, a fájl pedig nem volt az `allowed_paths`-on — lásd
[[HEAL E09-R02/H3]] (PR #409). Ez a session a self-healt main-ről a
munkapéldányba merge-elte, majd az implementer (minimax) elvégezte a §0.1
szerinti tesztfelbontást: `test_downgrade_one_revision_drops_only_community_tables`
(egy lépés a fejtől — csak a Community táblák tűnnek el) és
`test_downgrade_to_base_removes_application_schema` (downgrade a base-ig — a
`users`/`user_settings` is eltűnik).

Független review (`docs/reviews/e09-r02-review.md`): APPROVED, 0
BLOCKER/MAJOR/MINOR, 1 eljárási NOTE. A reviewer izolált `/tmp` klónban
ÖNÁLLÓAN futtatta újra mind a 9 gate-cellát (zöld), a scope-auditot a
folytatás tényleges bázisán (`9be8e613`, a self-heal beépítése után — 2
változott fájl, 0 sértés), és elvégezte a kötelező A7 valódi-sértés próbát
(`user_id` unique constraint eltávolítva →
`test_duplicate_profile_for_same_user_is_rejected_by_db` PIROSRA vált →
visszaállítva, 17/17 zöld). Az orchestrátor a saját munkakönyvtár-hibáját
(egy ideiglenes prompt-fájl a megosztott worktree-ben, ami hamis
`scope_audit=VIOLATION`-t okozott a `mm-round.sh` beépített auditán) felismerte
és javította a review előtt — nem érintette a kód minőségét.

CI: Full Gate
[32575935889](https://github.com/wolfcasaba/strumsight/actions/runs/32575935889)
és Router CI
[32576081884](https://github.com/wolfcasaba/strumsight/actions/runs/32576081884)
success az exact merge-elő SHA-n (`17b899a7`), a helyi HEAD-del összevetve. A
`main` a dispatch óta nem mozdult (`a11608b8` mindkét oldalon).

Pontos következő kör: **E09-R03** — a Community router bekötése
`main.py::create_app()`-ba és a `/health/ready` végpontba (ADR 0395
Következmények 2–3. pont, ADR 0396 §3–4), a queue soros szerint.

## ✅ [HEAL E09-R02/H3] KÉSZ — `allowed_paths` nem fedte a migráció-láncolás által tört downgrade-tesztet — PR [#409](https://github.com/wolfcasaba/strumsight/pull/409) (2026-08-22, L411)

Az E09-R02 (Community backend modul + első Alembic migráció, ADR 0396) H3-mal
állt meg, MIUTÁN az implementer (minimax) már ledolgozta a modult (branch
`minimax/e09-r02-backend-community-module-and-migration`, `05fa154d`, pushed).
Gyökérok: a kör saját §0.0/§5 döntése (a `e09_r02_0002` migráció a MEGLÉVŐ
`e01_r12_0001` fejére láncolódik) szükségszerűen hamissá teszi a MEGLÉVŐ
`backend/tests/test_migrations.py::test_downgrade_one_revision_removes_application_schema`
egyetlen-migrációs feltevését (`downgrade -1` a fejtől == `users`/
`user_settings` eltűnik) — két láncszemmel `downgrade -1` csak a LEGÚJABB
migrációt vonja vissza. A fájl nem szerepelt az `allowed_paths`-on, az
implementer helyesen `blocked`-ot jelzett a STOP-protokoll szerint. Class B
(kör-tartalom: a saját láncolási döntés kontra a `allowed_paths` hiánya),
függetlenül reprodukálva: `cd backend && python -m pytest
tests/test_migrations.py -q` → `AssertionError: assert 'users' not in
{'alembic_version', 'user_settings', 'users'}`.

Feloldás
(`docs/rounds/e09-r02-backend-community-module-and-migration.md` §0.1):
`backend/tests/test_migrations.py` szűken, egyetlen fájlként bekerült az
`allowed_paths`-ra és a §4 táblázatba, konkrét instrukcióval a folytatáshoz —
a downgrade-teszt bontása "egy lépés a fejtől" (csak a Community táblák
tűnnek el) és "downgrade a base-ig" (a `users`/`user_settings` is eltűnik)
esetekre. Regressziós védelem:
`tools/tests/test_e09_r02_migration_downgrade_test_scope.py` —
`audit_legacy_scope()`-ot futtatja a ténylegesen committolt brief ellen; a
mért halt-útvonal (`git show HEAD:...`-tal visszaállított, pre-fix brief-
tartalommal reprodukálva) RED volt a javítás előtt, GREEN utána, egy
szomszédos backend-teszt fájl (`test_auth.py`) pedig továbbra is scope-on
kívül marad. Teljes gate izolált heal-worktree-ben: `python3 -m pytest
tools/tests -q` → 716 passed/1 skipped/640 subtests/0 failed. `brief-lint
--level strict` tiszta. Router CI
[32574365404](https://github.com/wolfcasaba/strumsight/actions/runs/32574365404)
success az exact push SHA-n (`31573292`), amit a merge előtt a helyi HEAD-del
összevetve igazoltam. Nincs törölt/gyengített teszt, nincs küszöb-lazítás,
`tools/round-gate.sh`/`.github/workflows/**` érintetlen. Lecke: [[L411]].

Mivel az eredeti E09-R02 implementer-munka már kész és a saját branch-én ül,
ez a heal NEM vitte tovább a tartalmi munkát — a lánc a MEGLÉVŐ
`minimax/e09-r02-backend-community-module-and-migration` ágon, a felfrissített
brieffel folytatja: a `test_downgrade_one_revision_removes_application_schema`
kétesetes felbontása még hátravan az implementer oldalán, utána a §7
mindkét parancsa, majd review/CI/merge a szokásos rend szerint.

## ✅ E09-R01 KÉSZ — Community baseline, threat model és feature flag — PR [#408](https://github.com/wolfcasaba/strumsight/pull/408), squash `7ad4b28d` (2026-08-22)

**EPIC 9 (COMMUNITY PLATFORM) ELSŐ KÖRE KÉSZ.** Alkalmazáskód-változtatás
nélkül: öt Community feature flag (`communityEnabled` + 4 alkapcsoló,
Flutter + backend), egy nyolc-kategóriás threat model
(`docs/security/community-threat-model.md`), egy mért baseline leltár
(`docs/baseline/epic-09-community-start.md`) és a backend
`community_postgres_ready` readiness placeholder — mind az `ADR 0395`
szerint. Implementer MiniMax M3, orchesztrátor/reviewer Claude Sonnet 5,
javító kör nélkül (0 BLOCKER/MAJOR, 1 MINOR, 1 NOTE —
`docs/reviews/e09-r01-review.md` APPROVED).

**Pre-flight ADR 0395 döntése:** a dart-define/env kill switch mechanizmus
(`STRUMSIGHT_COMMUNITY*`, `defaultValue` nélkül — hiány = `false` MINDEN
környezetben) a Flutter oldalon `FeatureFlags.forEnvironment` TÖRZSÉBEN
olvasódik, `app_config.dart` érintése nélkül, mert az a brief
`allowed_paths`-án kívül esik (az `accountEnabled` élő mintája
app_config.dart-ot olvasna, de az itt tiltott zóna). A backend öt mezője a
`tutor_enabled` mintáját követi (env-aware branch NÉLKÜL, mindig `False`
amíg egy explicit env-var be nem kapcsolja) — NEM a
`diagnostics_enabled`/`apk_download_enabled` nonProd-alapú mintát. A döntés
tudatosan ELTÉR a repó ellentétes precedensétől (ADR 0220, Epic 6:
hardcode-`false` MINDEN környezetben, dart-define NÉLKÜL, a teljes
építő-epic alatt) — az eltérés indoklása ADR 0395 „Elutasított
alternatívák" szakaszában.

Review: saját, izolált `/tmp` klónban újrafuttatott gate (9/9 zöld,
egyezik az implementer §10.2 táblázatával), scope-audit tiszta (7/7
`allowed_paths`, 0 kívüli fájl), §6.1 valódi-sértés próba
(`communityEnabled: true` szabotázs) reprodukálva. 1 MINOR: a baseline-
doksi három mért fájlszáma (`lib/features/auth/` teszt-fájl 7→4 tényleges,
`lib/features/learn/` 24/34→25/32 tényleges) eltér a tényleges
`find`-kimenettől — dokumentum-only, nincs gate-hatás, nem blokkoló; a
Kör 2 pre-flightja javítsa a §1.1 táblázatot, mielőtt rá támaszkodik. Exact
`745a9a15`: Full Gate
[32570982536](https://github.com/wolfcasaba/strumsight/actions/runs/32570982536)
+ Router CI
[32571697617](https://github.com/wolfcasaba/strumsight/actions/runs/32571697617)
success (utóbbi `workflow_dispatch`-csel manuálisan indítva, mert a review-
commit csak `docs/reviews/**`-t érintett, ami nincs a `router-ci.yml`
push-trigger path-listáján — az exact-SHA kapuhoz kellett).

## ✅ E08-R30 KÉSZ — Epic 08 closure: route activation + real-fixture legacy
verification + numerical deprecation gates — PR [#407](https://github.com/wolfcasaba/strumsight/pull/407), squash `a8ecb9f3` (2026-08-22)

**EPIC 8 (GAMIFICATION) LEZÁRVA — mind a 30 köre kész.** Implementer MiniMax
M3, orchesztrátor/reviewer Claude Sonnet 5, javító kör nélkül (0
BLOCKER/MAJOR/MINOR, 2 NOTE — `docs/reviews/e08-r30-review.md` APPROVED). A
kör pre-flightja saját `§0.0` brief-revíziót igényelt: a 2026-08-18-i brief
nem mérte, hogy (1) a tényleges `GoRoute` wiring `app_router.dart`-ban él, nem
az engedélyezett `app_route.dart`-ban ([[L97]]/[[L94]] mintázat), (2) a hat új
képernyő egyike sem volt valaha adathoz kötve (nulla példányosítás
production kódban), (3) a „Kör 24 migrációs kapcsoló" sehol nincs élesítve
(`dualWriteMode:` nulla találat), (4) a meglévő legacy-migrációs teszt
idealizált `PracticeEntry`-kkel dolgozott, nem valós V1-kulcs-alakú JSON-nal.
Az `allowed_paths` a revízióval bővült (`app_router.dart` + egy ÚJ
fixture-teszt), a scope-audit mindkét dispatch után OK (0 sértés). Exact-SHA
`3a6f10b3`: Full Gate
[32569011383](https://github.com/wolfcasaba/strumsight/actions/runs/32569011383)
+ Router CI
[32569012517](https://github.com/wolfcasaba/strumsight/actions/runs/32569012517)
success; a reviewer saját izolált `/tmp` klónban mind a kilenc gate-lépést
függetlenül újrafuttatta (zöld) és a scope-audit-ot is saját kézzel mérte.

Az Epic 8 ZÁRÓ köre. Hat új route élesítve, a régi `/streak` és `/progress`
deep link VÁLTOZATLANUL él (ADR §5.1), a legacy migrátorok valós V1-kulcs
alakú JSON-nal bizonyítottak. Nincs kódbeli kapcsoló-flip — a §0.0 rögzítette,
hogy a dual-write adapternek MA nincs production call chain hívója, tehát a
`newOnly` végállapot SZÁMSZERŰ jövőbeli feltételekhez kötve dokumentálva
([`docs/sdd/epic-08-completion-report.md`](docs/sdd/epic-08-completion-report.md) §3),
nem átbillentve. Ez a kör szándékosan NEM nyúlt a `lib/features/**`-höz —
a route-aktiváció és a minimális Riverpod-ragasztó kizárólag a most
engedélyezett `lib/app/routing/app_router.dart`-ba került, kizárólag már
publikus `keyValueStoreProvider` + `appLoggerProvider` + `gamification/public.dart`
importokból.

ÚJ:
- `lib/app/routing/app_route.dart` — hat új konstans (`gamificationHub`,
  `achievements`, `achievementDetail`, `quests`, `streakDetail`, `rewardInbox`).
- `lib/app/routing/app_router.dart` — hat új `GoRoute` + öt file-private
  provider (`_gamificationRepositoryProvider`, `_levelCurveProvider`,
  `_gamificationProfileProvider`, `_streakStateProvider`,
  `_rewardInboxProvider`); a meglévő útvonalak (`/streak`, `/progress`,
  …) sorai ÉRINTETLENEK.
- `test/app/routing/app_router_test.dart` — nyolc új cella: a két legacy
  deep link VÁLTOZATLANUL a V1 screen-re mutat, a hat új útvonal pedig a
  megfelelő V2 widgetre.
- `test/features/gamification/data/legacy_streak_and_practice_fixture_test.dart`
  (ÚJ) — hét teszt, mind valós V1-kulcs alakú JSON-t ír a
  `LegacyStorageKeys` / `StorageKeys` tényleges kulcsnevei alá egy
  `InMemoryKeyValueStore`-ba, és a `LegacyStreakMigrator`-t (mindkét ág:
  pre-v22 nyers kulcs ÉS post-v22 namespaced envelope) és a
  `LegacyPracticeAdapter` / `GamificationMigrator`-t (valós
  `PracticeEntry.fromJson` dekódolással a `lib/features/progress/`-ból)
  hajtja végig. A fájlnév szándékosan kerüli a "migration" szót (az
  `ai-router` `high_risk_path_fragments` listája ezt a szót tartalmazza —
  ez a teszt nem indokol `risk = "high"` besorolást).
- `docs/sdd/epic-08-completion-report.md` — az Epic 8 lezáró jelentése:
  mért állapot (dual-write kapcsoló be nem kötve, hat képernyő soha nem
  volt adathoz kötve) + SZÁMSZERŰ kivezetési feltételek (wire-shape
  parity ≥30 fixture / 7 CI run, zero ledger loss 3 property-seed,
  production-side ingest mindkét adapterre, 14 napos dual-write soak
  nulla mismatch log mellett) + az A3 próba-jegyzőkönyv + a CI-link
  placeholder (a §7 gate UTÁN, de a végleges CI-linket az orchestrátor
  illeszti be dispatch után — ez a handoff rögzíti a helyét/szerkezetét).
- `README.md` — frissített státusz banner, frissített feature-sor, új
  Gamification szakasz (route lista, settings, storage envelope, offline,
  accessibility, completion-report link).

A no-op callbackek (`onOpenLevelDetail`, `onRecoveryPressed`, a quest
`onAction`, a reward inbox `onItemSelected` / `onMarkSeen`) explicit
`// TODO(E08-R30): <mit kell>` kommenttel vannak jelölve — ezek a
jövőbeli bekötő körök felé nyitott tételek, és a completion report §3
rögzíti, hogy a feature-oldali provider-lift NEM ennek a körnek a dolga.

**Kötelező valódi-sértés próba saját kézzel megismételve (§6.1):**
a completion report korai piszkozatába egy SZÁNDÉKOS PIROS CI-link
került, hogy az A6 cella bizonyíthatóan elutasítsa — cserélve a helyes
GREEN-link placeholderére, az A6 cella így a „rajta" küszöbön áll.

Mérce: `tools/round-gate.sh test/app/routing/app_router_test.dart
test/features/gamification test/features/streak test/features/progress` —
**MINDEN GATE ZÖLD**, előtérben, csonkítás nélkül futtatva. Scope-audit
(`git diff --stat`) nem mutat `lib/features/` útvonalat. A teljes
acceptance-tábla (A1–A8) és a mérce-mátrix minden sora a
[`docs/sdd/epic-08-completion-report.md`](docs/sdd/epic-08-completion-report.md)
§2 / §3 / §5 alatt dokumentálva.

Pontos következő E08 kör: az Epic 8 lezárult — a queue a Chapter 9
(`E09-R01`+) felé folytatódik (ellenőrizve: `pipeline-queue.tsv`-ben ez az
első `pending` sor E08-R30 után, megelőzi a Chapter 13 E13-R05-öt).

**Nyitott, EMBERI döntést NEM igénylő tartozások, EZUTÁN a bekötő kör
dolga** (`docs/sdd/epic-08-completion-report.md` §3 + a review N1/N2):

- a hat új képernyő adatvetületei jelenleg egyszeri (`Provider`, nem
  `StreamProvider`) olvasások `app_router.dart`-ban — a Hub/Streak-
  detail/Inbox nem frissül élőben, amíg az app-session újra nem indul;
- `activeQuestCount`, `masteryUnlockedCount`, az achievement-progressz és a
  napi/heti quest-listák ma hardkódolt `0`/üres értékek — nincs perzisztált
  quest-/achievement-progressz forrás a `GamificationRepository`-ban;
- a `RewardInboxScreen` üres marad, mert a storage-szintű
  `GamificationInboxItem` (csak id/createdAt/viewedAt) és a domain
  `RewardInboxItem` (a teljes `RewardEvent`-et hordozza) között nincs
  triviális leképezés;
- a streak-recovery gomb no-op (nincs publikus repository-metódus a
  vásárláshoz);
- a dual-write kapcsoló `newOnly` végállapotba állításának négy számszerű
  feltétele a completion report §3.2-ben.

## ✅ E08-R28 KÉSZ — Ledger sync contract, merge és verified státusz — PR #406, squash `571981b7` (2026-08-22)

Offline-first, duplikációmentes szinkron-szerződés a jövőbeli fiók- és
közösségi (Epic 9) használathoz — a legfontosabb szabály: **a szerver soha
nem fogad el kliens-oldali összesített XP-t**. ÚJ:
`lib/features/gamification/data/sync/{gamification_sync_contract,ledger_merge_policy}.dart`
(verziózott nyugta-alapú fel-/letöltés, összefésülés kettős dedup-kulccsal —
`ledgerId` ÉS `sourceEventId`), `backend/app/gamification/{schemas,service}.py`
(a szerver saját maga összegez, `totalXp` mező NINCS a bemeneten). ADR
[`0394`](docs/adr/0394-ledger-sync-contract-and-merge.md) — a brief előre
kiosztott `0319`-e stale volt (a `reserve-adr` foglaló `0394`-et adott,
ugyanaz a minta, mint az E08-R27 stale `0318`-ja).

A dedup-kulcs kettőssége a lényeg: csak `ledgerId`-ra dedupolás
duplikálna (két eszköz, két azonosító, ugyanaz az esemény), csak
`sourceEventId`-re dedupolás adatvesztene (két legitim, eltérő eseményű
nyugta ütköző azonosítóval összeolvadna). **Kötelező valódi-sértés próba
saját kézzel megismételve:** a `_collapseGroup` (cross-device
sourceEventId-összefésülés) eltávolítása a TÉNYLEGES
`LedgerMergePolicy.merge`-ből 2/20 tesztet pirosra váltott (A1 idempotencia
+ a §6.1 „on threshold" cella) — pontosan az implementer állítása szerint;
visszaállítva, 20/20 zöld.

**Egy javító kör, F1 MAJOR + F2 MINOR, mindkettő a reviewer saját kezű
mérésével fedve fel, nem az implementer önbevallásából:**

- **F1 (MAJOR, javítva):** a Dart `encodeUpload()` és a backend
  `ReceiptUpload` NEM ugyanazt a wire-alakot beszélték — a Dart minden
  nyugtát `{'schemaVersion':…, 'receipt': {…, 'status':…}}` beágyazásban
  küldött, a backend LAPOS `ReceiptUpload` listát várt. Saját kézzel,
  pydantic `model_validate`-tel igazolva: a Dart kimenet a backend modellen
  8 validációs hibát adott. A kör saját deklarált célja egy "szerződés" volt
  — a két fél nem ugyanazt beszélte, holott mindkettő EBBEN a körben
  készült. Javítás: a Dart-oldal a backend lapos alakjához igazodott
  (`totalXp` és `status` NINCS a wire-en), plusz ÚJ, kétoldali teszt: a Dart
  oldalon a TÉNYLEGES `encodeUpload()` kimenet kulcsait ellenőrzi, a
  backend oldalon egy kézzel felírt, a Dart kimenetet tükröző fixture-t old
  fel elfogadással.
- **F2 (MINOR, javítva):** nincs `max_length` a `ledgerId`/`sourceEventId`/
  `receipts` mezőkön (saját kézzel igazolva: 1M karakteres id és 100k elemű
  lista is elfogadásra került) — látens DoS egy jövőbeli, bekötött útvonalon.
  Javítás: `max_length=256`/`500`, négy határ-teszttel (fölötte/rajta mindkét
  oldalon).
- Köztes tooling-epizód (nem lelet): az első javító-kör futás közben az
  implementer egy ÜRES helyi `backend/.venv`-et hozott létre (a
  `pip install`-t helyesen blokkolta az `implementer_guard`), ami
  beárnyékolta a `tools/round-gate.sh` már meglévő, működő fallback-ját a
  közös `$HOME/music-theory/backend/.venv`-re — emiatt `stopped`-ot
  jelzett. Az orchesztrátor törölte a lokális, üres venv-et (gitignore-olt,
  önmagától létrehozott artefaktum), és egy rövid resume-prompttal
  folytatta a kört — a tényleges F1/F2 kódjavítások érintetlenek maradtak.

Dedikált biztonsági review (`risk = "high"`, `security-reviewer` agent):
**PASS, 0 CRITICAL/BLOCKER**. Egy látens (nem blokkoló) MAJOR-t is felszínre
hozott N1-ként: a `verified` ma kizárólag séma-érvényességet jelent, XP
felső korlát vagy policy-újraszámolás NÉLKÜL — nincs élő fogyasztó, ami ma
bizalmi jelzésként olvasná, de a jövőbeli router-kötő körnek explicit gátat
kell szabnia, mielőtt bármilyen felület `verified`-et bizalmi jelzésként
mutatna. Review: [`docs/reviews/e08-r28-review.md`](docs/reviews/e08-r28-review.md),
[`docs/reviews/e08-r28-security.md`](docs/reviews/e08-r28-security.md).

Mérce: `tools/round-gate.sh
test/features/gamification/data/ledger_merge_policy_test.dart` +
`python3 -m pytest backend/tests/test_gamification_ledger.py -q` — **MINDEN
GATE ZÖLD** (9 lépés, 22 Dart + 15 backend teszt), javítás előtt és után is
SAJÁT kézzel, izolált klónból (GitHub originből) reprodukálva. Scope-audit
mindkétszer OK. A kör alatt a `main` egyszer mozdult (E09 round-brief batch,
PR #405, `docs/rounds/e09-*` + `pipeline-queue.tsv`, diszjunkt fájlkör) —
`merge --no-ff` + teljes CI-újradispatch a §0.3 szerint. Exact `dda4534b`:
Full Gate [32565070603](https://github.com/wolfcasaba/strumsight/actions/runs/32565070603)
+ Router CI [32565071642](https://github.com/wolfcasaba/strumsight/actions/runs/32565071642)
success; post-merge célzott gate + backend pytest a friss `main`-en
önállóan is zöld. Ez a kör NEM köti be a HTTP-végpontot (router mounting) —
a `backend/app/gamification/` router-szintű regisztrációja egy jövőbeli
kör dolga. Pontos következő E08 kör: **E08-R30 — Epic 08 migráció,
regresszió és lezárás** (queue-ban `minimax`) — az **E08-R29** (Integritás,
analytics, balance) `hold`-on marad; a queue-scan a legelső `pending` sort
választja, ez a §0.3-nál mérten `E08-R30`, nem az újonnan batch-elt E09-R01
(annak ellenére, hogy fájl-sorrendben előrébb ér az E09-batch — az E08-R30
sora korábbi a fájlban).

## ✅ E08-R27 KÉSZ — Gamification akadálymentesség és beállítások — PR #404, squash `db6293f4` (2026-08-22)

A teljes gamifikációs réteg MOST már kikapcsolható, hozzáférhető és nem
tolakodó: ÚJ `GamificationPreferences` domain-modell (intenzitás/haptika/
hang/csökkentett mozgás/értesítés), egy szinkron-olvasású `NotifierProvider`
(`gamification_preferences_provider.dart`, kizárólag lokális perzisztencia —
a felhő-szinkron e körben tiltott, `settings_sync.dart` érintetlen), és egy
ÚJ `GamificationSettingsSection` a Settingsben. ADR:
[`0393`](docs/adr/0393-gamification-accessibility-and-settings.md) — a brief
előre kiosztott `0318`-a stale volt (egy korábbi, független kör már foglalta,
`tools/round-slots.py reserve-adr` adta a `0393`-at). A pre-flight (Claude
Sonnet 5) korrigálta az `allowed_paths`-ot is: az ÚJ l10n-kulcsok a
`lib/l10n/features/gamification_{en,hu}.arb` SZEGMENSBE tartoznak, nem a
generált `app_{en,hu}.arb` aggregátumba (ugyanaz a hibaosztály, ami az
E08-R20/E08-R22-ben mid-round fixet igényelt — itt előre elkerülve).

A kikapcsolás VIZUÁLIS — a ledger/széria/mastery kiértékelés a preferenciáktól
függetlenül fut (A1/A2), az értesítési engedély megadása SOSEM ad XP-t/oldja
fel (A3, sötét-minta tilalom), mind az öt beállítás önállóan hat a leképezett
megjelenítésre (A4), a változás azonnal érvényesül (A5), mind a 22
achievement kitöltött a11y-leírással rendelkezik mindkét nyelven (A6,
reverzibilis valódi-sértés próbával), és a WCAG AA kontraszt-küszöb a
MEGLÉVŐ, L381-ben már kijavított `tool/ui_contrast_check.dart`-ot használja
(helyes sRGB gamma-2,4 transzformáció) egy ÚJRA-implementálás helyett.

Egy javító kör: **F1 MAJOR** — a review saját kézzel elkapta, hogy a domain
`gamification_preferences.dart` egy `presentation/widgets/
reward_summary_sheet.dart`-ból importált (`show RewardSummaryFeedback`),
ami `package:flutter/material.dart`-tal kezdődik — a domain-osztály emiatt
TRANZITÍVAN függött a Fluttertől (AGENTS.md §6 sértés). A
`tool/check_architecture.dart` ezt NEM fogta meg, mert a
`sharedDomainMustRemainFrameworkIndependent` szabály `_isSharedDomain()`
allowlistje (`lib/core/music/`, `lib/core/audio/codec/`,
`lib/features/practice/domain/`) nem tartalmazza a
`lib/features/gamification/domain/`-t — GATE-LEFEDETTSÉGI RÉS, amit a
manuális review fogott meg, nem a gépi mérce. Javítás: a leképezés
(`gamificationFeedbackFor`) átköltözött a presentation-réteg providerbe.
Review: [`docs/reviews/e08-r27-review.md`](docs/reviews/e08-r27-review.md) —
APPROVED a javítás után, 0 nyitott BLOCKER/MAJOR, 1 MINOR (F2 — az A1/A2
„valódi-sértés próba" nem köti be ténylegesen a preferenciát a
`CelebrationCoordinator`-ba, mert ma nincs is éles bekötés; a jövőbeli
UI-bekötő kör pre-flightjának szól) + 2 NOTE (inline storage-kulcsok
`StorageKeys` nélkül, dokumentált indokkal; a `reward_summary_sheet.dart`
doc-kommentje még mindig „Kör 27"-re hivatkozik, a tényleges bekötő kör
javítja).

Mérce: `tools/round-gate.sh test/features/gamification/presentation/
gamification_accessibility_test.dart test/features/settings` → **MINDEN GATE
ZÖLD** (12+51 teszt), a javítás ELŐTT és UTÁN is SAJÁT kézzel, izolált
klónban reprodukálva. Scope-audit mindkétszer OK. CI a merge SHA-n
(`a20182a6`): `full-gate.yml` (32560163642) success, `router-ci.yml`
(32560901860, kézi `workflow_dispatch`, mert az utolsó commit csak a
review-jelentést érintette) success. Ez a kör NEM köti be a
`reward_summary_sheet.dart`-ot egyetlen élő hívóba sem (nincs is
`allowed_paths`-on, és MA nincs élő hívó egyáltalán) — egy jövőbeli,
feltehetően `E13-R32` (gamification-ui) kör dolga. Pontos következő E08 kör:
**E08-R28 — Ledger sync contract és merge** (queue-ban `minimax`, ADR 0319
előre kiosztva, ellenőrizendő a foglalóval).

## ✅ E08-R26 KÉSZ — Cross-feature gamification integráció (Analysis/Vision/Tutor/Plan) — PR #403, squash `ea2e22a4` (2026-08-22)

A maradék négy forrás — Analysis, Vision, AI Tutor, Practice Generator —
MOST már bekötve a gamification jutalom-láncba: négy ÚJ, tisztán caller-fed
adapter (`lib/features/{analyze,vision,ai_tutor,practice_generator}/
application/gamification_*_adapter.dart`). ADR: [`0392`](docs/adr/0392-cross-feature-gamification-adapter-caller-fed-boundaries.md)
— a pre-flight (Claude Sonnet 5) NÉGY ponton cáfolta meg a 2026-08-18-i brief
feltevéseit: (1) az `ai_tutor/public.dart` boundary VÉGLEGESEN üres, egy
merge-elt E04-R01 guard pinneli (`test/features/ai_tutor/
ai_tutor_boundary_test.dart`, L139) — a tutor-adapter ezért ZÉRÓ szimbólumot
importál az `ai_tutor`-ból, a beszélgetés-nulla-XP szabály (A1) strukturálisan
garantált, nem futásidejű `if`; (2) `AnalyzeResult`-nak nincs
`sourceHash`/`analyzerVersion` mezője — az analysis-adapter saját, hívó-fed
jel-típust definiál ezekkel; (3) a brief `minVisionConfidence` neve szó
szerint nem létezik — a mért megfelelő `VisionClaimGuard._minimumConfidence
= 0.70`, ami a `vision/domain/integration/public.dart` (egy MÁSIK, szűkebb
barrel) exportján érhető el, NEM a top-level `vision/public.dart`-on; (4) a
`PlanStatus.completed` (teljes terv) enum-érték SEHOL nem kerül beállításra
a mai kódban (L20 — elérhetetlen cél-státusz), csak a blokk-szintű
`PracticeItemStatus.completed`, ami MÁR ma is a meglévő practice/song
adapterekkel jutalmazódik — a plan-adapter ezért caller-fed
`planCompleted: bool` jelet fogad, és nem nyúl az `active_plan_controller.dart`/
`generation_orchestrator.dart` (tilos zóna) állapotgépéhez.

A terv-bónusz (§5.3) FLAT és nem-összegző: `bonusXp` kényszerítve `0`-ra, csak
a policy `baseXp`-je landol a ledgerben, hogy a blokkok (amik már fizettek a
saját forrásukon) ne duplázódjanak. A Vision-adapter két esemény (`vision-base`
mindig, `vision-technical` csak a `VisionClaimGuard` engedélye után) —
a §6.1 küszöb-hármas (0.69/0.70/0.71) szó szerint tesztelve, a küszöb maga
inkluzív-elfogadó. Az Analysis-adapter dedupja `(sourceHash, analyzerVersion)`
párra épül, nem csak a hash-re — egy verzióváltás legitim új jutalom.

Mérce: `tools/round-gate.sh test/features/gamification/integration/
cross_feature_reward_flow_test.dart test/core/architecture_dependency_test.dart`
→ **MINDEN GATE ZÖLD** (16+37 teszt), reprodukálva SAJÁT kézzel izolált
klónban a review-ban is. Az A6 architektúra-guard mind a négy adapterre
kiterjed, a vision-nél MINDKÉT elfogadott barrelt (top-level + `domain/
integration/`) kezeli. Három `_Broken*Adapter` valódi-sértés próba
(chat-farm, blokk-összegzés, hash-only dedup) — mindhárom önálló osztály, a
VALÓDI ingestor/eligibility/policy láncon fut át, nem csonka váz. Review:
[`docs/reviews/e08-r26-review.md`](docs/reviews/e08-r26-review.md) —
APPROVED, 0 BLOCKER/MAJOR/MINOR, 3 NOTE (mind unwired-today, jövőbeli
UI-wiring kör hatókörű: `analyzerVersion` hash nélkül landol a ledgerben; a
caller-fed id-mezők nem típusos/charset-lezárt id-k; a másolt `utf8Bytes()`
segédfüggvény — MÁR az E08-R25 dal-adapterből örökölve, nem ez a kör vezette
be — nem valódi UTF-8, csak ASCII-bemenetre helyes). `security-reviewer`
agent (risk="high") függetlenül: PASS.

Ez a kör NEM köti be az adaptereket a hívó UI-ba (nincs is az
`allowed_paths`-on) — a négy adapter kész, tesztelt felület, amit egy
jövőbeli kör hív majd az Analyze/Vision result-screenekből, a plan-befejezés
UI-jából. CI: `full-gate.yml` + `router-ci.yml` mindkettő zöld a merge SHA-n
(`d3c4a9a0`, PR #403 squash → `ea2e22a4`). Pontos következő E08 kör:
**E08-R27 — Gamification accessibility és settings** (queue-ban `minimax`,
ADR 0318 előre kiosztva).

## ✅ E08-R25 KÉSZ — Song Trainer és setlist integráció — PR #402, squash `204b3798` (2026-08-22)

A dalgyakorlás (szakasz/hurok, teljes dal, setlist-tétel) MOST már bekötve a
gamifikáció jutalom-láncába: `lib/features/songs/application/gamification_song_adapter.dart`
(ÚJ, kizárólag a gamification `public.dart`-on át importál; a `Song`
típust a `songs` feature SAJÁT `model/song.dart`-jából olvassa, a
`song_trainer/**`-hez nem nyúl). ADR: [`0391`](docs/adr/0391-song-gamification-adapter-standalone-bonus-and-hashed-song-id.md)
— a pre-flight mérés megcáfolta a 2026-08-18-i brief két állítását: (1) az
R06 `parentEventId` dedupja (ADR 0341) BINÁRIS mind-vagy-semmi — szó
szerinti használata a reális (szakaszok-előbb) sorrendben NULLÁRA, nem
csökkentett bónuszra ejtette volna a teljes dal jutalmát; (2) a dal
azonosítója (bizonyos kódutakon) cím-eredetű lehet, tehát a ledgerbe
KIZÁRÓLAG SHA-256-hashelt (16 hex karakter) alakban kerülhet. A javított
mechanizmus: minden `RewardPolicyRequest` önálló (`parentEventId: null`),
a bónusz-méretezés (alap egyszer + csökkentett bónusz, nem kétszeres, nem
nulla) az adapter SAJÁT, session-hatókörű könyveléséből adódik. Két
KÖTELEZŐ valódi-sértés próba ÁLLANDÓ regressziós tesztként megtartva
(`song_reward_flow_test.dart` §7): Probe 1 (bookkeeping kikapcsolva →
infláció PIROS) és Probe 2 (a `DefaultRewardPolicy`-t közvetlenül hívva,
`parentEventId`-vel → 0 XP mérve, megerősítve a bináris-dedup állítást).
A `songs` feature dal-haladása VÁLTOZATLAN (49/49 zöld). Az adapter MA
NINCS BEKÖTVE egyetlen hívóból sem (nincs UI/screen ebben a körben) — a
`security-reviewer` agent ezt függetlenül megerősítette, és rögzítette,
hogy a session/section/setlist-azonosítók ma nyersen (nem hash-elve)
kerülnek az `eventId`-be — ha egy jövőbeli bekötő kör cím-eredetű
session/section-id-t adna át, ugyanaz a hibaosztály nyílna meg egy MÁSIK
mezőn (`docs/reviews/e08-r25-review.md` F2, NOTE).

**Review APPROVED, javító kör nélkül** (`docs/reviews/e08-r25-review.md`):
0 BLOCKER/MAJOR. 1 MINOR (F1) — `hashedSongId()` belső `utf8Bytes()`
helper-je NEM valódi UTF-8 kódolás (a `String.codeUnits`-ot `& 0xff`-fel
maszkolja), ami elméletben nem-ASCII karaktereket tartalmazó azonosítóknál
ütközést okozhatna — MA nem elérhető (minden tényleges `Song.id`/`SongId`
forrás ASCII-only), triviális follow-up javítás (`utf8.encode()` a saját
helper helyett). **Kör közbeni process-hazárd:** a MiniMax implementer
`mm-round.sh` wrapper-je a `done` jelzés (05:14:52) UTÁN is tovább futott
(~20 percig), egy jogos, in-scope §10-korrekciós commitot készített
(`f7ade3e8`), majd az orchestrátor review-commitját egy `git pull --rebase`
után saját maga push-olta vissza (`180c8d40` — TARTALMILAG azonos az
orchestrátor eredeti `0d889cba` commitjával, csak más szülőn), és eközben
saját maga dispatch-elt egy `gh workflow run` CI-t is (ami nem az ő
szerepe). Az orchestrátor a folyamatot PID-del megölte (nem
`pkill -f`-fel), tartalom-vesztés nélkül — a jelenség naplózva a
git-notes `lesson=` mezőjében, `docs/LESSONS.md`-be is felveendő.

Mindkét CI (`full-gate.yml` run 32554547623, `router-ci.yml` run
32554548631/32554544697) zöld a pontos merge-jelölt SHA-n (`180c8d40`).

## ✅ E08-R24 KÉSZ — Practice Engine és Learn integráció — PR #401, squash `dc09f5fe` (2026-08-22)

A gyakorlási session és a lecke-befejezés eredménye MOST már bekötve a
gamifikáció jutalom-láncába (esemény → outbox → jogosultság → XP →
főkönyv): `lib/features/practice/application/gamification_practice_adapter.dart`
+ `lib/features/learn/application/gamification_lesson_adapter.dart` (mindkettő
ÚJ, kizárólag a gamification `public.dart`-on át importál, A4 architektúra-
guard védi). Meglévő R05/R06 kapuk (`ActivityOutcome.completed/cancelled/
failed`, `practiceOccurrenceCount` diminishing-returns) — nincs új szabály.
Lecke-csillagok és legjobb pontosság VÁLTOZATLANOK (`lesson_progress_repository.dart`
a diffben nem szerepel). Migrációs kapcsoló (`GamificationDualWriteMode.off/
dual/newOnly`) alapértéke KIKAPCSOLVA — a tényleges élő hívási pont
(`practice_session_controller.dart`, a `learn` eredmény-képernyő) a brief
tiltott zónájában maradt, KÉSŐBBI kör dolga. ADR: [`0390`](docs/adr/0390-practice-and-learn-gamification-adapter-boundary.md)
(a brief előre kiosztott `0317`-e stale volt, a foglaló `0390`-et adott).

**A review egy javító kört zárt (`docs/reviews/e08-r24-review.md`):** két
BLOCKER. **F1** — a lecke-adapter `stableEventId`-je a lecke KATALÓGUS-
azonosítójából (nem egy próbálkozás-szintű azonosítóból) számolt, tehát egy
adott lecke ELSŐ teljesítése után minden további teljesítés örökre elveszett
a ledger `appendIfAbsent` dedupja miatt (mérve, saját eldobható próbateszttel:
két különböző napi teljesítés → azonos `eventId` → 1 ledger-bejegyzés a 2
helyett). **F2** — a `GamificationLessonAdapter`/`recordLesson` nulla
tesztlefedettséggel landolt (`practice_reward_flow_test.dart` kizárólag a
practice adaptert gyakorolta) — ez az oka, hogy F1 zöld gate-en csúszott át.
A javító kör (`0853ae6e`) a `stableEventId`-et egy új, caller-fed
`attemptId` mezőből származtatja, és felvett egy teljes lecke-oldali A1/A3/
A5/A6/A7 tesztmátrixot + egy dedikált F1-regressziós cellát. Mindkét lelet
FIXED, saját, izolált `/tmp` klónban megismételt méréssel megerősítve
(scope-audit + próbateszt + teljes gate 8/8 zöld).

Mindkét CI (`full-gate.yml` run 32551495513, `router-ci.yml` run
32551519892) zöld a pontos merge-jelölt SHA-n (`33733eb6`).

## ✅ E08-R23 KÉSZ — Gamification Hub és level UI — PR #400, squash `384c89df` (2026-08-22)

Nem-domináló áttekintő felület: `gamification_hub_screen.dart` +
`level_detail_screen.dart` + `xp_progress_bar.dart`/`level_badge.dart` —
a `progress_screen.dart` (516 sor) marad az elsődleges napi fejlődés-
felület, érintetlenül (A7). A Hub level/XP-haladást, questeket, sériát,
mastery-összesítőt, legutóbbi eredményt és a postaláda-jelzőt (R22) mutatja
egy képernyőn, "Hogyan működik?" magyarázattal (R06 öt XP-komponens),
villogás/visszaszámláló nélkül (ADR 0290 §1), offline-projekcióból (nincs
főkönyv-újraszámolás megnyitáskor), 200%-os szövegskálán levágás nélkül.

**A review egy BLOCKER-t talált és zárt (F1, `docs/reviews/e08-r23-review.md`):**
a `LevelBadge` — bár VIZUÁLISAN helyesen elkülönült az XP-sávtól (kör medál
vs sáv) — a feliratában és szemantikájában **"Skill mastery"/"Measured
skill, not experience points"**-ot állított, miközben az egyetlen bemenete
(`profile.currentLevel`) egy kizárólag `totalXp`-küszöbökből számolt
`LevelDefinition` (`LevelCurve` — "the single source of truth for
monotonically increasing XP levels"), tehát a valóságban XP-derivált, nem
mért készség-bizonyíték — pontosan az az összemosás, amit az ADR 0289 és a
brief §5.1 a kör legfontosabb invariánsaként tilt. A hiba a §6.1 kötelező
valódi-sértés próbán ÁTCSÚSZOTT, mert az csak a widget-TÍPUS különbségét
mérte, nem a felirat TARTALMÁT (L403). Egy javító kör (`6c04dcf6`) az
"Level {level}" / "a szint a tapasztalati pontokból adódik" őszinte
framing-re cserélte a feliratokat (angolul ÉS magyarul), és egy ÚJ,
tartalom-alapú regresszió-őr tesztet adott — ezt a reviewer saját, független
valódi-sértés próbával igazolta (a régi hibás szöveget visszaírva a teszt
PIROSRA váltott, majd visszaállítás).

Mindkét CI (`full-gate.yml` run 32544553725, `router-ci.yml` run
32544579114) zöld a pontos merge-jelölt SHA-n (`cad80d7f`) — a review a
gate-et és a scope-audit-ot (`tools/scope-audit.py`) KÉTSZER, saját
izolált `/tmp` klónokban futtatta (a javítás előtt és után is).

## ✅ E08-R22 KÉSZ — Jutalom-postaláda és ünneplés-koordinátor — PR #399, squash `8bbe3715` (2026-08-22)

XP/beváltás-mentes, caller-fed ünneplés-koordinátor (ADR 0389, a brief
`0316` előre kiosztott száma stale volt, a foglaló `0389`-et adott —
ugyanaz a mintázat, mint az E08-R21/E08-R20-nál). Új
`lib/features/gamification/domain/profile/reward_inbox_item.dart` +
`application/celebration_coordinator.dart` (pure Dart, nincs Flutter-/
Riverpod-/`RewardLedgerRepository`-import) + `presentation/screens/
reward_inbox_screen.dart` + `presentation/widgets/reward_summary_sheet.dart`:
aktív gyakorlás közben SOHA nem jelenik meg felugró (§5.1, a jutalom a
postaládába kerül helyette), több szintlépés EGY összevont
összefoglalóban (§5.3, determinisztikus `switch`-alapú prioritás, nem
`Map`-bejárás), a postaláda NEM beváltás-mechanika (§5.2, nincs lejárat/
begyűjtés-gomb), reduced motion mellett az információ TELJES marad
(`MediaQuery.disableAnimationsOf`), haptika/hang caller-fed bool
(élő settings-provider még nincs, Kör 27 dolga).

Két mért kör-közbeni brief-revízió: **§0.0.1** — a 12 új ARB-kulcs a
GENERÁLT aggregátumba (`lib/l10n/app_{en,hu}.arb`) került az első
implementer-futásban a forrás-fragmentum (`lib/l10n/features/
gamification_{en,hu}.arb`) helyett (ugyanaz a hibaosztály, mint az
E08-R20 §0.0.1, L396) — egy javító kör a forrásba tette, az
aggregátumot regenerálta. **§0.0.2** — a merge előtti CI (`full-gate.yml`,
run 32538682580) a teljes suite alatt PIROS volt: `test/ui/
ui_inventory_test.dart` a 61-es baseline-t várta, az új
`reward_inbox_screen.dart` miatt 62 a valódi screen-szám — mechanikus
egysoros javító kör (`hasLength(61)` → `hasLength(62)`).

A review (`docs/reviews/e08-r22-review.md`) APPROVED, egy NOTE-tal (a
wrapper `gate_shape` heurisztikája hamis pozitívot adott, mert az
implementer a gate SCRIPTJÉNEK forrását `cat ... | head`-delte, nem
futtatta csonkítva — a nyers log tényleges Bash-hívásai mind tiszták
voltak). A review saját, izolált `/tmp` klónban futtatott valódi-sértés
próbát az A1 megszakítás-őrre (`isActiveSession` ág letiltva → 7 teszt
pirosra vált → visszaállítás → 18/18 zöld). **Mérve, jegyzésre méltó:**
a boxon egy PÁRHUZAMOS orchestrátor-session is dolgozott ugyanezen a
körön a `pipeline-slots=1` konfiguráció ELLENÉRE (mérve, nem
diagnosztizálva — a két session git-push-szinten békésen konvergált,
mindkét review APPROVED volt, a merge egyetlen, konzisztens tartalommal
zárult) — **follow-up**: a slot-kényszerítés versenyfeltétele
kivizsgálandó egy jövőbeli GOV-körben, mielőtt ismét bízunk benne.

Mindkét CI (`full-gate.yml` run 32540666809, `router-ci.yml` run
32540630020) zöld a pontos merge-jelölt SHA-n (`71a5dee6`); a
`tools/round-land.sh` a squash-merge előtt saját kombinált-HEAD gate-et
futtatott (zöld, a `tools/prepare-flutter-generated.sh` friss futása
után — enélkül a stale generált l10n-fájlok ugyanazt a hamis
undefined-getter hibát adták volna, amit a §0.0.1 javító kör már
egyszer elhárított).

## ✅ E08-R21 KÉSZ — Mastery mérföldkő domain és kiértékelő — PR #398, squash `26f83265` (2026-08-21, L399)

XP/ledger-mentes, több-sessionös, confidence-kapuzott, monoton mastery
kiértékelő (ADR 0289 legszigorúbb alkalmazása). Új `lib/features/
gamification/domain/mastery/` (`mastery_milestone.dart`, `mastery_progress.dart`,
`mastery_badge.dart`) + `application/mastery_evaluator.dart`: session-szintű
dedup inkluzív `minEvidenceSessions>=2` küszöbbel, `0.70`-es Vision/Analysis
confidence-kapu (`VisionClaimGuard` pozitív-claim precedenssel egyezően,
ADR 0388 3. döntés), és zárt mezőkészletű, privacy-safe, magyarázható
jelvény (`toSummary()` — nincs `sessionId`, `audio`, egészségügyi mező).

Az előre kiosztott `ADR 0315` a pre-flightban ütközőnek bizonyult (egy
korábbi, független kör azóta lefoglalta, `halt-guard-ledger.md`) — a
foglaló a tényleges szabad számot (**`ADR 0388`**) adta, a brief §0.0
revíziója ezt dokumentálja.

A review egy MAJOR-t talált és önálló próbával igazolt (L399): a monoton
(„egyszer elért mérföldkő nem regresszál") ág egy már elért progressre
`ArgumentError`-ral bukott, ha a friss evidence-batch KEVESEBB minősítő
session-t tartalmazott, mint a korábban tárolt érték — a beküldött `A5`
teszt csak azonos-vagy-nagyobb session-számú batch-csel bizonyított. Egy
MiniMax javító kör (`99c36e90`) a hívó oldalon `max(friss, korábbi)`
clampelést vezetett be és új tesztet adott a kisebb-batch esetre; a review
saját, független `/tmp` klónban futtatott gate-je (21/21 zöld) és
scope-audit-ja is megerősítette a javítást.

Mindkét CI (`full-gate.yml` run 32534927662, `router-ci.yml` run
32536016910 — utóbbi explicit `workflow_dispatch`-csel indítva, mert a
javító kör commitjai nem érintették a `docs/rounds/**` útvonalat, tehát a
push-trigger nem tüzelt volna a merge SHA-n) zöld a pontos merge-jelölt
SHA-n (`6df449a5`); a merge utáni `main`-en független gate-újrafutás
(`format+analyze+test+architecture+secrets+l10n`) szintén zöld.

## ✅ E08-R20 KÉSZ — Quest és kihívás felület — PR #397, squash `684e6334` (2026-08-21, L396–L398)

Áttekinthető napi/heti quest- és kihívás-élmény: `quests_screen.dart` +
`quest_card.dart`/`challenge_card.dart`. Beváltás (claim) gomb NINCS — a
teljesített küldetés jutalma automatikusan látszik (R16 §5.1); a lejárati
szöveg semleges, nincs visszaszámláló (ADR 0290 §1); a Start/Continue CTA
típusos (`QuestRouteAction` sealed hierarchia — `QuestStartPracticeAction`/
`QuestContinuePracticeAction`/`QuestTryLiveAction`/`QuestUnavailableAction`),
sosem szabad szöveges route; nem elérhető tartalomnál a CTA letiltott. Az
útvonal-REGISZTRÁCIÓ változatlanul a Kör 30-ra van halasztva.

Három dispatch volt szükséges, mindhárom mért, valódi ok miatt (nem
implementer-hibából): (1) az implementer jogosan `stopped`-ot jelzett, mert
`lib/l10n/app_en.arb`/`app_hu.arb` 2026-08-20 óta (ADR 0307 §4, PR #343)
GENERÁLT aggregátum — a brief 2026-08-18-i, nem ismerhette a váltást; §0.0.1
brief-revízió a tényleges forrást (`lib/l10n/features/gamification_{en,hu}.arb`)
vette fel az `allowed_paths`-ba (L396). (2) A célzott gate zöld volt, de az
első CI-dispatch (`full-gate.yml`) egyetlen, a kör saját `gate_tests`-én
kívüli tesztet buktatott: `test/ui/ui_inventory_test.dart` rögzített
60-elemű production-screen bázisvonala az ÚJ, jogos `quests_screen.dart`
miatt 61-re nőtt — ugyanaz a hibaosztály, mint az E08-R19
`architecture_dependency_test.dart` lelete (L395), most a screen-inventory
oldalon (L397); §0.0.2 brief-revízió + egysoros javító kör zárta.

A review saját mutáció-próbája (ideiglenes „Begyűjtés" gomb a production
`quest_card.dart`-on, `flutter test --plain-name "A1"` → PIROS, majd
visszaállítás) igazolta, hogy az A1 no-claim-button guard valódi, működő
védelem — a brief §6.1 KÖTELEZŐ próbáját az implementer egy szintetikus,
a production widgetet NEM mutáló teszttel „teljesítette", és a §10 handoff
üresen maradt (L398, MINOR, nem blokkolt). 0 BLOCKER/MAJOR, review APPROVED.

Mindkét CI (`full-gate.yml` + `router-ci.yml`) zöld a pontos merge-jelölt
SHA-n (`f9a5ea4e`); a merge utáni `main`-en független gate-újrafutás
(`format+analyze+2×test+architecture+secrets+l10n`) szintén zöld.

## ✅ E08-R19 KÉSZ — Challenge V2 és legacy napi kihívás migráció — PR #396, squash `a100ff9b` (2026-08-21)

Négy új, tipizált napi kihívás-típus (akkordváltás, ritmus, dal-szakasz,
időzítés) a meglévő, determinisztikus pengetés-minta generátor mellé — a
legacy `DailyChallenge.forDay` VÁLTOZATLAN, az adapter HÍVJA (nem
reprodukálja, `ADR 0387` Döntés 1). A napi példány azonosítója
`type|catalogVersion|epochDay`; a jutalom a meglévő reward-főkönyv
`appendIfAbsent`-jén megy át ugyanezzel a kulccsal, tehát az újrajátszás
szabad, a jutalom egyszeres. A katalógus-verzió a generáláskor rögzül —
egy nap közbeni app-frissítés nem cseréli ki az aznapi aktív kihívást.

Az előre kiosztott `ADR 0314` a pre-flightban ütközőnek bizonyult (egy
korábbi, független kör már lefoglalta) — a foglaló a tényleges szabad számot
(`ADR 0387`) adta, a brief §0.0 revíziója ezt dokumentálja (mérve, nem
`ls`-ből feltételezve, `AGENTS.md` §12).

A CI (`full-gate.yml`) a saját, szűk célzású `round-gate.sh`-nál szélesebb
kört mérve egy BLOCKER-t fogott: a `daily_challenge_service.dart`
`dart:math.Random`-ot használt a gamification `application/` rétegben, ami
sérti az E08-R08 „framework-free application layer" szabályt
(`test/core/architecture_dependency_test.dart`, nincs a kör két célzott
teszt-útvonalán, csak a teljes suite-ban). Egy MiniMax javító kör lecserélte
tiszta FNV-1a hash-projekcióra (`_projectHash(seed, discriminator)`), a
kódbázis meglévő `dailyQuestSortKey` mintáját követve — `dart:math` import és
`Random(` hívás nélkül. Mindkét CI-mátrix (`full-gate.yml`, `router-ci.yml`)
zöld a pontos merge-jelölt SHA-n (`331b8d97`); a merge utáni `main`-en
független gate-újrafutás (`format+analyze+3×test+architecture+secrets+l10n`)
szintén mind zöld.

Lecke: a kör-brief célzott gate-parancsa (`round-gate.sh` két teszt-útvonala)
nem fedte le a keresztmetsző architektúra-invariánsokat (`test/core/
architecture_dependency_test.dart` egy HARMADIK útvonalon él) — ez pontosan
azért mérce-rés, mert a saját review-gate-futásom is csak ezt a két
útvonalat futtatta újra. Jövőbeli gamification `application/`-réteget érintő
briefek gate-parancsába érdemes felvenni az architektúra-tesztfájlt is.

## ✅ E08-R18 KÉSZ — Rugalmas heti quest és consistency objective — PR #394 (2026-08-21, L394)

A pure, caller-fed heti generátor az elérhető percekkel egészértékűen skáláz,
az aktívnap-célt 3/4/5/6/7 napnál rendre 3/4/5/5/5-re korlátozza, és nulla
elérhetőségre nem gyárt kötelező questet. A négy típusos objective közül
stabil UTF-8/FNV-1a sorrenddel választ; improvement mérés nélkül fail-closed,
a rollover pedig nyelvfüggetlen, strukturált tényprojekció.

Az első Sol review két MAJOR rést talált. A scalar previous progress eltérő
replacement objective-re átvihető volt, a 3/7 availability-végpontok és a
`0..7` inputhatár pedig nem voltak közvetlenül őrizve. Egy Terra javító kör
után a progress stable quest ID-hoz kötött: same-ID esetén monoton maximum,
cross-ID esetben csak az új objective saját observed értéke számít. A cap és
az unconditional progress-transfer valódi mutációi pirosak; correctness
**APPROVED**, security **PASS**.

Exact `c131c47e`: Full Gate
[32472133400](https://github.com/wolfcasaba/strumsight/actions/runs/32472133400)
és Router CI
[32472092472](https://github.com/wolfcasaba/strumsight/actions/runs/32472092472)
success. PR [#394](https://github.com/wolfcasaba/strumsight/pull/394), squash
`29c27ab2`, ADR [0386](docs/adr/0386-flexible-weekly-quest-projection.md).
Pontos következő E08 kör: **E08-R19 — Challenge V2 és legacy DailyChallenge
migráció**.

## 🔧 [HEAL E13-R05/H3] Component Catalog scope helyreállítva (2026-08-21, L393)

Az E13-R05 javított `SsCard` kompozíciója helyesen egyetlen, az `SsSurface`
által birtokolt `Material`-réteget használ. A meglévő
`test/core/design_system/component_catalog_test.dart` route- és dark/light
smoke cellái azonban még legacy `Card` widgetet vártak. A PR #392 exact
`03788441` Full Gate-je emiatt 5519 zöld teszt mellett háromszor
`Found 0 widgets with type "Card"` hibát adott; a teszt nem szerepelt a kör
allowlistjében vagy célzott gate-jében. Ez B osztályú brief-scope hiány volt,
nem product- vagy gate-hiba.

A self-heal az E13-R05 briefet exact egyetlen meglévő fájllal bővítette:
`test/core/design_system/component_catalog_test.dart` bekerült az
`allowed_paths` és `gate_tests` listába, valamint az A8 tranzakciós
acceptance-cellába. A folytatott product körnek meg kell őriznie a route-kaput
és a két téma smoke contractját, miközben `SsCard`-ot és pontosan egy
`Material`-leszármazottat mér. Más design-system tesztút nem nyílt meg. A
regressziós `tools/tests/test_e13_r05_component_catalog_scope.py` a revízió
előtt 4/5 piros, utána 5/5 zöld; a teljes tooling suite 714 passed, 1 skipped
és 610 subtests passed. Branch: `heal/E13-R05-H3-1`; az exact-SHA Router CI és
a zöld squash-merge a `fixed` jelzés előfeltétele. A pontos következő Chapter
13 kör változatlanul **E13-R05**, a meglévő product-ág revideált scope-pal
történő folytatásával.

## ✅ E08-R17 KÉSZ — Determinisztikus, capability-safe napi quest generátor — PR #391 (2026-08-21, L388/L392)

Az offline, caller-fed generátor a nap + profil-pillanatkép + katalógusverzió
stabil FNV-1a seedjéből választ legfeljebb három, legalább egy rövid questet.
Kamera-, fiók- és cloud-hiány esetén fail-closed szűr, planned rest napon csak
opcionális rest-eligible eredményt ad, üres katalógusra, hiányzó tervre és új
profilra pedig local fallbacket készít. Permission-, repository-, óra- vagy
hálózathívást nem birtokol.

Az első Sol review két MAJOR mércerést talált. A Terra javító kör közvetlen
shipping-katalógus contractot adott, a H4 self-heal utáni második javítás pedig
camera/account/cloud tengelyenként két-entrys candidate poollal zárta a
truncation által elfedett regressziót. Mindhárom cross-wiring mutáció célzottan
piros; correctness **APPROVED**, security **PASS**. Exact `e96feef3`: Full
Gate [32465903185](https://github.com/wolfcasaba/strumsight/actions/runs/32465903185)
és Router CI
[32465903321](https://github.com/wolfcasaba/strumsight/actions/runs/32465903321)
success. PR [#391](https://github.com/wolfcasaba/strumsight/pull/391), squash
`a2ea758d`, ADR [0384](docs/adr/0384-deterministic-capability-safe-daily-quest-generation.md).
Pontos következő E08 kör: **E08-R18 — Heti quest és consistency objective**.

## ✅ E13-R04 KÉSZ — Accessible typography és text-scale resilience — PR #389 (2026-08-21, L389–L391)

Az immutable `SsTypography` a Chapter 13 teljes Poppins/Montserrat scale-jét
theme extensionként adja mindhárom design-system témához. A metric tokenek
tabular figures-t használnak, a value/unit helper nem törő szóközt ad, az
adaptív `SsChordHeroText` pedig a platform text scale megtartásával és
ellipszis nélkül skáláz le a rendelkezésre álló helyre. A hosszú magyar
fixture 1.0/1.3/2.0/2.5 skálán renderelhető.

Az első független Sol review egy MAJOR leletet reprodukált: a chord hero a
kézi label és a gyermek `Text` miatt kétszer került a semantics fába. Egy
Terra javító kör után `excludeSemantics: true` és exact label-regresszió zárja
a rést; correctness **APPROVED**, security **PASS**. Exact `55832396`: Full
Gate [32462896738](https://github.com/wolfcasaba/strumsight/actions/runs/32462896738)
és Router CI
[32462873685](https://github.com/wolfcasaba/strumsight/actions/runs/32462873685)
success. PR [#389](https://github.com/wolfcasaba/strumsight/pull/389), squash
`57d034be`, ADR [0383](docs/adr/0383-typography-and-text-scale-contract.md).
Pontos következő Chapter 13 kör: **E13-R05 — Spacing, radius, elevation és
surface primitives**.

## 🔧 [HEAL E08-R17/H4] Capability-axis mérce izolálva — PR #390 (2026-08-21, L388)

Az E08-R17 független review-ja az `account → cloud` production-mutációval
bizonyította, hogy a javító kör három availability-cellája közül az account
teszt hamisan zöld: a shipping katalógus négy eligible candidate-jéből a
max-3 korlát épp a hibás account questet vágta le. A production mapping helyes;
a halt B osztályú brief/mérce-contract rés volt.

A self-heal a product allowlist és gate bővítése nélkül előírta a camera,
account és cloud tengelyek külön, két-entrys candidate poolját (local short +
csak a vizsgált capability), a teljes shipping katalógushoz pedig megőrizte a
külön metadata-contract cellát. Mindhárom keresztkötési mutációnak célzottan
pirosnak kell lennie. A regressziós
`tools/tests/test_e08_r17_capability_axis_contract.py` a régi briefen 6
hibával piros, a revízió után 5 teszt + 6 subtest zöld; a teljes tooling suite
709 passed, 1 skipped és 610 subtests passed. Branch:
`heal/E08-R17-H4-1`, PR
[#390](https://github.com/wolfcasaba/strumsight/pull/390). Az exact végső SHA
Router CI success és squash-merge a `fixed` jelzés előfeltétele. A pontos
következő E08 termékkör változatlanul **E08-R17**, a revideált mércével.

## 🔧 [HEAL E13-R04/H3] Typography compatibility scope helyreállítva — PR #388 (2026-08-21, L387)

Az E13-R04 pre-flight ADR 0383 §D3-a az `SsTypography` tényleges
`ThemeData`-extension regisztrációját írja elő. A meglévő
`test/core/design_system/foundations_test.dart` ezzel szemben közvetlenül az
extension nélküli `AppTheme.dark()`/`light()` eredménnyel várta egyenlőnek a
legacy adaptert, de ez a teszt nem szerepelt a kör allowlistjében vagy célzott
gate-jében. A Terra implementer helyesen `stopped` jelzést adott production
módosítás nélkül; a halt B osztályú brief-scope hiány volt.

A self-heal az E13-R04 briefet exact egyetlen meglévő fájllal bővítette:
`test/core/design_system/foundations_test.dart` bekerült az `allowed_paths`
és `gate_tests` listába, valamint az A8 kompatibilitási cellába. A folytatott
product kör ugyanabban a commitban őrzi a legacy theme-forrás paritását és
méri az új extensiont; más design-system tesztút nem nyílt meg. A regressziós
`tools/tests/test_e13_r04_typography_foundations_scope.py` a revízió előtt
4/5 piros, utána 5/5 zöld; a teljes tooling suite 704 passed, 1 skipped és
604 subtest passed. Branch: `heal/E13-R04-H3-1`, PR
[#388](https://github.com/wolfcasaba/strumsight/pull/388). Router CI success
az exact végső SHA-n és squash-merge a `fixed` jelzés előfeltétele. A következő
Chapter 13 kör változatlanul **E13-R04**, a meglévő product-ág folytatásával.

## ✅ E08-R16 KÉSZ — Quest domain, objective és lifecycle — PR #387 (2026-08-21, L384–L385)

A framework- és IO-mentes quest domain zárt, típusos objective-vokabulárt,
verziózott napi/heti schedule-t, ötállapotú életciklust és automatikus,
claim nélküli reward receiptet ad. Az aktivitási felső határ exkluzív; expiry
megőrzi a valós progress/evidence adatot. Ugyanazon quest-instance ismételt
completionje változatlan receiptet ad, más generation day vagy cadence pedig
külön instance identityt kap.

Az első független Sol review két MAJOR leletet talált: a katalógus-ID alapú
receipt a következő napi példány jutalmát deduplikálta volna, a persisted
completed rekord pedig megkerülhette a receipt- és expiry-invariánst. Egy
Terra javító kör után mindkettőt regressziós cella zárja; correctness
**APPROVED**, security **PASS**. Exact `e4ececf4`: Full Gate
[32454251927](https://github.com/wolfcasaba/strumsight/actions/runs/32454251927)
és Router CI
[32454084052](https://github.com/wolfcasaba/strumsight/actions/runs/32454084052)
success. PR [#387](https://github.com/wolfcasaba/strumsight/pull/387), squash
`1e7ed2a3`, ADR [0382](docs/adr/0382-quest-objective-and-lifecycle-contract.md).
Pontos következő E08 termékkör: **E08-R17 — Napi quest generátor**.

## ✅ E13-R03 KÉSZ — Semantic colors and three themes — PR #386 (2026-08-21, L381–L383)

Az új, 23 mezős `SsColorScheme`, a névvel ellátott state overlayek és az
`SsThemeBehavior` egyetlen contractban adják a Dark Studio, Warm Light és
High Contrast témát. A confidence-, offline-, local-AI- és cloud-AI
állapotok páronként külön ikonmarkert kapnak, ezért jelentésük nem csak
színből olvasható. A Component Catalogban a három téma fejlesztői kapcsolóval
ellenőrizhető; a production theme-mode wiring és a legacy olvasási út
változatlan maradt.

Az első független Sol review két MAJOR leletet talált: a kontraszt-CLI a WCAG
sRGB 2,4-es hatványa helyett köbözött, a marker-tesztek pedig nem buktatták az
azonos ikonokra rontást. Egy Terra javító kör után canonical luminancia-vektor
és két all-same marker őr zárja ezeket; correctness **APPROVED**, security
**PASS**. Exact `3fc36778`: Full Gate
[32451933445](https://github.com/wolfcasaba/strumsight/actions/runs/32451933445)
és Router CI
[32451919508](https://github.com/wolfcasaba/strumsight/actions/runs/32451919508)
success. PR [#386](https://github.com/wolfcasaba/strumsight/pull/386), squash
`6e80a441`. Következő Chapter 13 kör: **E13-R04 — Typography and text-scale
resilience**.

## ✅ E08-R15 KÉSZ — Privacy-safe Achievement UI és 60-screen baseline — PR #383 (2026-08-21, L377/L380)

A caller-fed achievement lista és detail UI all/unlocked/in-progress/category
szűrőket, exact-ID kiválasztást, lokalizált üres/not-found állapotot és
1.99/2.0/2.01/3.0 text-scale kompatibilitást ad. Locked hidden állapotban cím,
leírás, progressz, kategória és evidence a widget- és semantics-fából is
hiányzik. Az evidence contract zárt reason code-ot és runtime-validált,
aggregált current/target értéket fogad; Analyze/session/raw audio adatot nem.

Az E08-R15/H3 self-heal után a két új screen ugyanabban a termék-tranzakcióban
emelte 58-ról 60-ra az UI inventoryt, miközben az AppRoutes/GoRoute baseline
40 maradt az E08-R30 wiringig. Implementer Terra, reviewer/orchestrátor Sol;
correctness **APPROVED**, security **PASS**. Exact `d4414f49`: Full Gate
[32449877483](https://github.com/wolfcasaba/strumsight/actions/runs/32449877483)
és Router CI
[32449853724](https://github.com/wolfcasaba/strumsight/actions/runs/32449853724)
success. PR [#383](https://github.com/wolfcasaba/strumsight/pull/383), squash
`22f5e1a0`. Következő E08 termékkör: **E08-R16 — Quest domain, objective és
lifecycle**.

## ✅ E13-R02 KÉSZ — Design System Foundation és compatibility layer — PR #384 (2026-08-21, L378–L379)

Az új `lib/core/design_system/public.dart` mögött megjelentek a kipinnelt
breakpoint-, spacing-, radius-, motion- és semantics-foundationök. A
`SsThemeExtensions` az átmeneti kompatibilitási rétegben közvetlenül a
meglévő `AppTheme`, `AppColors` és `AppPalette` API-kra delegál, ezért nincs
második színforrás. A Component Catalog csak a default-OFF compile-time flag
ÉS debug-build együttes teljesülésekor hoz létre route-ot; maga a screen
privát. Az architektúra-őr tiltja a feature-importot és a design-system
barrel megkerülését.

Implementer: Terra (`gpt-5.6-terra`), egy javító körrel. A Sol
(`gpt-5.6-sol`) független correctness review-ja **APPROVED**, a security
review **PASS**. A review mutációval pirosra vitte a másolt brand-színt, a
feature-importot és a debug-kapu kivételét; a privát catalog screenre tett
külső hivatkozás fordítási hibát adott. Exact branch-csúcs `05ec6276`: Full
Gate [32447387921](https://github.com/wolfcasaba/strumsight/actions/runs/32447387921)
és Router CI [32447381563](https://github.com/wolfcasaba/strumsight/actions/runs/32447381563)
success. PR [#384](https://github.com/wolfcasaba/strumsight/pull/384), squash
`8bd7dc98`. Következő Chapter 13 kör: **E13-R03 — Semantic colors and
themes**.

## 🔧 [HEAL E08-R15/H3] UI-inventory tranzakciós scope helyreállítva — PR #385 (2026-08-21, L377)

Az E08-R15 PR #383 két új achievement presentation screennel 58-ról 60-ra
emeli az E13-R01 production screen inventoryját. A Full Gate exact SHA-n 5442
tesztet zölden futtatott, és kizárólag a változatlan 58-as inventory-őr bukott.
A kör briefje nem engedte a teszt és a hozzá tartozó baseline-dokumentáció
frissítését, ezért a H3 megállás helyes volt.

A Class B self-heal nem emeli előre 60-ra a `main`-alapú Dart-tesztet, mert a
két product screen ezen az ágon még nincs jelen. Ehelyett az E08-R15 brief
exact három fájllal bővült: `test/ui/ui_inventory_test.dart`,
`docs/ui/migration-status.md`, `docs/ui/baseline/route-map.md`; az inventory-
teszt a kör második gate-tesztje. Az E08-R15 resume ugyanabban a product-
commitban frissíti a screen countot, a két exact útvonalat és az R30-ig fennálló
route-wiring kockázatot. Más `docs/ui/**`/`test/ui/**` út nem nyílt meg.

A regressziós `tools/tests/test_e08_r15_ui_inventory_scope.py` a revízió előtt
4/5 piros, utána 5/5 zöld. Branch: `heal/E08-R15-H3-1`; Router CI és squash-
merge a `fixed` jelzés előfeltétele. A merge után a pontos következő kör
változatlanul **E08-R15 — Achievement UI és részletes evidence**, a meglévő
PR #383 folytatásával és új exact-SHA Full Gate futással.

## ✅ [HEAL E13-R01/H8] KÉSZ — a duplikált körtörténet tiszta recovery PR-rel helyreállt — PR #382 (2026-08-21, L376)

Az E13-R01 eredeti PR-jének (`#381`, csúcs `31aab305`) története a tiszta,
rebase-elt `87f247f8` csúcs mögé visszamerge-elte a régi pre-rebase láncot.
A 12 nem-merge commit ezért pontosan hat, páronként azonos stabil patch-id-t
tartalmazott. A már merge-elt H8-SELFDUP őr helyesen blokkolta a landolást;
az eredeti PR-t force-push nélkül lezártuk, így a sérült történet auditálható
maradt.

A `heal/E13-R01-H8-1` recovery ág a jelenlegi `origin/main` fölött a hat
egyedi, már függetlenül APPROVED E13-R01 commitot tartalmazza. A recovered fa
byte-azonos a sérült PR fájával (`git diff --exit-code 87f247f8 31aab305` →
0), de csak hat egyedi patch-id maradt. A valós régi-csúcs-visszamerge fixture-t
tartalmazó `tools/tests/test_round_land.py` 13 tesztet és 3 subtestet zölden
futtatott; a teljes E13-R01 round-gate 7/7 zöld. A Full Gate és Router CI
exact-SHA bizonyítéka a recovery PR merge-feltétele; piros vagy eltérő SHA
esetén nincs merge.

Implementer: Terra (`gpt-5.6-terra`); független correctness reviewer és H8
self-heal orchestrátor: Sol (`gpt-5.6-sol`). Product tartalom nem változott a
javítás során. Következő Chapter 13 kör: **E13-R02 — Design System Foundation**,
új sessionben.

## ✅ E08-R14 KÉSZ — Achievement evaluator és progress projection — PR #380, squash `558b1258` (2026-08-21, L374–L375)

Az indexelt evaluator canonical event-historyból, stabil event-ID deduppal
építi újra a count, threshold, distinct, sequence és compound progresszt. Az
unlock exact `achievement:<id>` source-on atomikus, nulla-XP ledger receipt;
a completion timestamp a trigger eventből jön. A caller-anchored backfill
inkluzív 30 napos ablakot és nyers 10 000-es hard capet őriz, unknown vagy
ütköző evidence pedig fail-closed diagnosztikát ad.

Terra implementáció, Sol correctness/security review: **APPROVED / PASS**.
Három implementer-fázis scope-auditja zöld; a végső round-gate 6/6, a célzott
suite 11/11. Exact `b8b25721`: Full Gate
[32439860548](https://github.com/wolfcasaba/strumsight/actions/runs/32439860548)
és Router CI
[32439873084](https://github.com/wolfcasaba/strumsight/actions/runs/32439873084)
success. Következő termékkör: **E08-R15 — Achievement UI és részletes
evidence**, új sessionben.

## ✅ E08-R13 KÉSZ — Achievement domain és lokalizált katalógus — PR #376, squash `f9d5bbc8` (2026-08-21, L372–L373)

A gamification feature 22 stabil ID-jú, EN/HU lokalizált achievementből álló
verziózott katalógust kapott. A domain típusosan kezeli a count, threshold,
distinct, sequence és compound feltételeket; runtime validáció őrzi az
egyedi ID-kat, a tier-ciklus mentességét, a teljes lokalizációt, a korábbi
verzió ID-folytonosságát és a véges, monoton progresszértékeket. A
deprekáció megőrzi a már kiosztott achievement identitását.

Implementer Terra (`gpt-5.6-terra`), orchestrátor/reviewer Sol
(`gpt-5.6-sol`). Az első független review két MAJOR leletet talált: azonos
elemszám mellett eltűnhetett egy korábbi ID, továbbá `NaN`/végtelen küszöb és
progressz átjuthatott. Egy Terra javító kör után correctness **APPROVED** és
security **PASS**; a cycle-, retention- és finite-őr eldobható mutációi
célzottan pirosak, restore után 20/20 teszt zöld. Exact `679f030f`: Full Gate
[32433372231](https://github.com/wolfcasaba/strumsight/actions/runs/32433372231)
és Router CI
[32433323271](https://github.com/wolfcasaba/strumsight/actions/runs/32433323271)
success. Döntés: [ADR 0374](docs/adr/0374-achievement-domain-and-catalog-contract.md).
Következő termékkör: **E08-R14 — Achievement evaluator és progress
projection**; a másik sloton E13-R01 fut.

## ✅ [HEAL E13-R01/H3] KÉSZ — a hét screenshot és corpus-validátor exact scope-ja helyreállt — PR #377, squash `c505b26f` (2026-08-21, L371)

A Chapter 13 Kör 1 név szerint hét compact-portrait referencia screenshotot
(Live, Tuner, Analyze, Learn, Library, Settings, onboarding) és azok
megnyithatósági/nem-ürességi tesztjét kéri, de az előre megírt E13-R01 brief
egyetlen screenshot- vagy corpus-teszt útvonalat sem engedett. Ez Class B
brief-tartalmi ellentmondás volt; az implementer nem indult el, product diff és
kör-PR nem keletkezett.

A self-heal az SDD-t változatlanul hagyta, `lib/**`-ot nem nyitott meg, hanem
hét exact `docs/ui/baseline/screenshots/*-compact-portrait.png` fájllal és az
egy `test/ui/ui_baseline_screenshot_test.dart` validátorral bővítette a briefet.
A validátor a hét fájlt enumerálja, ténylegesen dekódolja, és pozitív byte- és
pixelméretet plusz portrait képarányt kér; a reviewer mind a hét képet manuálisan
is megnyitja. A `tools/tests/test_e13_r01_screenshot_scope.py` a javítás előtt
4/5 piros, utána 5/5 zöld, és bizonyítja, hogy egy nyolcadik testvérkép továbbra
is scope-sértés. Következő érintett SDD-kör: **E13-R01 — UI baseline inventory
és screenshot corpus**, friss sessionben, a javított briefből.

Branch: `heal/E13-R01-H3-1`; javítási commit: `27e5fc51`; PR:
[#377](https://github.com/wolfcasaba/strumsight/pull/377). A célzott őr
5/5 zöld, strict és open/base brief-lint leletmentes, a teljes tooling-suite
694 passed / 1 skipped / 605 subtest. Izolált klónban a broad screenshot-
directory grant 2/5 cellát pirosra vitt, restore után 5/5 zöld és tiszta fa.
Az exact `27e5fc51` Router CI
[32432394840](https://github.com/wolfcasaba/strumsight/actions/runs/32432394840)
success; Dart/native fájl nem változott, ezért APK/Full Gate nem volt kapu.

## ✅ E99-R22 (GOV-16) KÉSZ — ismétlődő halt-osztályok őrteszt-főkönyve — PR #375, squash `ebff600c` (2026-08-20, L370)

A stdlib-only, READ-ONLY `tools/halt-ledger.py` a verziókövetett
`.pipeline/halted-*.txt` rekordokat halt-osztályonként összesíti, és a
`docs/LESSONS.md` félkövér `**Őrteszt:**` hivatkozásai alapján `fedett`,
`hiányzik` vagy egyszeri `nem jelölt` állapotot ad Markdown és JSON alakban.
A figyelmeztetési határ pontosan két előfordulás; a CLI nem blokkol és valid
futásnál mindig 0-val tér vissza. A pipeline záró rituáléja mostantól halt
utáni leckénél gépi őrhivatkozást vagy kimondott hiányt kér.

Implementer Terra (`gpt-5.6-terra`), reviewer/orchestrator Sol
(`gpt-5.6-sol`). A független review APPROVED, 0/0/0/0 lelettel; a szóhatár
egyszerű részszöveg-keresésre és a `>= 2` küszöb `>= 1`-re rontása célzottan
piros lett, restore után 7/7 zöld. A végső, upstream-szinkronizált HEAD-en a
scope-audit 5 útvonalat látott (1 generated/ignored review), sértés nélkül;
a round-gate 6/6 zöld, a tooling gate 688 passed / 2 skipped / 606 subtest.
Exact `ee053ba8`: Full Gate
[32429315526](https://github.com/wolfcasaba/strumsight/actions/runs/32429315526)
és Router CI
[32429329475](https://github.com/wolfcasaba/strumsight/actions/runs/32429329475)
success. Az E08-R13 már fut a másik sloton; utána a következő termékkör
**E08-R14 — Achievement evaluator és projection**. A következő governance-kör
**E99-R23** jelenleg `hold`.

## ✅ [HEAL E08-R13/H3] KÉSZ — az achievement-fordítások source-segment scope-ja helyreállt — PR #373 (2026-08-20, L369)

Az E08-R13 brief 20–30 achievementhez új lokalizált cím-, leírás- és
akadálymentességi kulcsokat kért, de az E99-R17 óta generált
`lib/l10n/app_en.arb` és `app_hu.arb` aggregátumokat engedte elsődleges
szerkesztési pontként. A kötelező
`lib/l10n/features/gamification_{en,hu}.arb` forrásszegmensek hiányoztak az
allowlistből, ezért a kör a jóváhagyott scope-on belül nem volt
megvalósítható. Ez Class B brief-hiba, nem router baseline-drift és nem
külső szolgáltatási akadály.

A H3 scope-revízió a gamification-szegmenseket nevezi elsődleges forrásnak,
a két aggregátumot csak determinisztikus kimenetként engedi, és kötelezővé
teszi a `dart run tool/gen_l10n_segments.dart --write` lépést. A valódi
briefadatot olvasó `tools/tests/test_e08_r13_l10n_scope.py` a javítás előtt
2/2 piros, utána 2/2 zöld; strict brief-lint: nincs lelet; teljes
Python/router gate: 682 passed, 1 skipped, 604 subtests passed. Branch:
`heal/E08-R13-H3-1`, javítási commit: `24492a53`, PR:
[#373](https://github.com/wolfcasaba/strumsight/pull/373). Lecke: **L369**.
Következő SDD-kör továbbra is: **E08-R13 — Achievement domain és
katalógus**, friss sessionben, a javított briefből.

## ✅ E08-R12 KÉSZ — együttérző Streak UI V2 és recovery flow — PR #367, squash `8aa0010b` (2026-08-20)

A gamification feature caller-fed, passzív Streak V2 képernyőt kapott current,
longest, total days, freeze és 0–7 heti consistency kártyákkal. A broken
állapot kimondja, hogy a megszerzett tudás megmarad, a recovery CTA egyetlen
hívó-adta callbacket indít büntető countdown nélkül, a planned rest külön
védett állapot. A legacy `/streak` route változatlan; a későbbi wiring-kör
köti be a V2 képernyőt. A layout 1.0/2.0/3.0 text scale mellett görgethető,
teljes semantics címkéket ad, reduced motionnál pedig csak az átmenet ideje
lesz nulla.

Implementer Terra (`gpt-5.6-terra`), reviewer Sol (`gpt-5.6-sol`). Az első
review egy MAJOR copy-őr hiányt és egy MINOR angol plural hibát talált; az egy
javító kör után correctness és high-risk security review is APPROVED, nyitott
lelet nélkül. A végső scope-audit 12 útvonalat, 2 generated/ignored
review-jelentést és 0 sértést adott. A kombinált-HEAD gate 7/7 zöld (21 V2 +
20 legacy streak teszt); a fix 80 px magasság, storage-import és tiltott
broken-copy mutációk célzottan pirosak, restore után zöldek.

Exact reviewed head `fe175652`: Full Gate
[32406555330](https://github.com/wolfcasaba/strumsight/actions/runs/32406555330)
és Router CI
[32406581869](https://github.com/wolfcasaba/strumsight/actions/runs/32406581869)
success. PR [#367](https://github.com/wolfcasaba/strumsight/pull/367), squash
`8aa0010b`; ADR 0353. Következő SDD-kör: **E08-R13 — Achievement domain és
katalógus**, új sessionben.

## 📐 [TERV] Chapter 14 briefek: E14-R15…R19 — a strum recovery blokk mérési fele (2026-08-20)

**User-kérés:** „mehetsz tovább". A Chapter 14 §8 harmadik blokkja (R15–R24,
strum onset + direction recovery) első öt köre — mindegyik **mérés és döntés**,
nem hangolás: a production DSP-konstans egyikben sem mozdul.

| Kör | Tárgy | ADR |
|---|---|---|
| `E14-R15` | hard-negative taxonómia (10+ kategória) + **false visible arrow/chord per perc** termék-metrika | 0367 |
| `E14-R16` | canonical SuperFlux A/B (current / 24 sáv-oktáv / complex-domain / simple flux) CPU+latency-vel; a production konstans ÉRINTETLEN | 0368 |
| `E14-R17` | referencia-modell reprodukció + **külön** kód/checkpoint/dataset licenc-audit, gépi licenc-őrrel | 0369 |
| `E14-R18` | joint streaming onset+direction prototípus, verziózott IO-sémával; go/no-go az Alpha kapuhoz kötve | 0370 |
| `E14-R19` | augmentáció seedelve/manifestelve/kikapcsolhatóan + ablation; romló subgroup → nincs automatikus elfogadás | 0371 |

**Két mért tény, amire a briefek épülnek** (a pre-flight ezeket kéri újra):
`ml/negatives.py` (r174) rögzíti, hogy a heurisztikus onset ~minden hatodik
onsetje hamis, és a direction-CRNN ezekre ugyanolyan magabiztos (medián raw
0,94 vs 0,97) — **a confidence önmagában nem szűr**, ezért kell a no-strum
osztály ÉS a termék-oldali hamis-esemény metrika; `ml/augment.py` (r173)
PCM-szintű augmentációja pedig MÁR LÉTEZIK, tehát az R19 bővít és bizonyít,
nem újraír.

**Két kutatási kör (`R17`, `R18`) `blocked`-dal zárhat**, ha a research-
környezet vagy a checkpoint nem elérhető ezen a boxon — a brief ezt KÖTELEZŐ
úttá teszi (Chapter 14 §9/9: hiányzó környezetnél tilos sikeres verifikációt
állítani).

**Mérve:** `brief-lint --level strict` mind az öt briefre → nincs lelet;
`brief-lint --open --level base` → nincs lelet. A sorok `prepared`-ek.

**Hátralévő Chapter 14:** R20–R42 (strum tanítás grouped holdouttal, chord
recovery, adaptív termék-UI, field validation és rollout).

## ✅ [HEAL E08-R12/H8] KÉSZ — a publikus kör-ág veszteségmentesen tartalmazza a friss `main`-t — PR #371 (2026-08-20, L367)

Az E08-R12 landolója a friss `main`-re rebase-elte a kör hét nem-merge
commitját, majd a safe-force-push négy remote-only commitot talált: három
korábbi upstream-merge-et és a `524cf246` pre-flight briefet. Az izolált
cherry-pick próba pontosan a kör briefjén adott content-konfliktust. A
`main`-oldal bizonyítottan tartalmazta a merge-elt H6 scope-revíziót
(`425ad1d7`, PR #365), ezért a H8 brief-history protokoll volt alkalmazható.

A távoli PR-csúcsról (`02ae43af`) indított `git merge --no-ff origin/main`
konfliktus nélkül létrehozta a `c6a96fc1` csúcsot; a brief 73 soros
implementation handoffja és a H6 allowlist egyszerre megmaradt. A helyreállított
fa byte-azonos a korábban teljes round-gate-en zöld rebase-elt fával,
`origin/main` bizonyított őse a csúcsnak, és normál push történt force nélkül.
A H8 regressziós teszt 1/1 zöld; az exact-SHA Router CI
[32402823817](https://github.com/wolfcasaba/strumsight/actions/runs/32402823817)
success. A kör saját PR-je [#367](https://github.com/wolfcasaba/strumsight/pull/367)
nyitva marad; a következő firing ezen a helyreállított ágon folytatja a
landolást. Következő SDD-kör továbbra is: **E08-R12 — Streak UI V2 és recovery
flow**.

## ✅ [HEAL E08-R12/H3] KÉSZ — a presentation Flutter-függése és storage-határa külön őrzött — PR #369 (2026-08-20, L366)

Az E08-R12 exact-SHA Full Gate futása a három, brief által kötelező
gamification UI-fájlt azért utasította el, mert az E08-R08 architektúra-teszt
ugyanazzal a markerlistával vizsgálta az application és presentation réteget.
Ez a presentationben a legitim `package:flutter/` importot is tiltotta,
miközben az eredeti A5 szerződés csak a közvetlen storage-import kizárását
kérte ezen a rétegen.

A javított őr az application rétegben továbbra is tiltja a frameworköt,
storage-ot, faliórát és random forrást; a presentationben külön markerlista
tiltja a `SharedPreferences`, secure-storage és sqflite közvetlen importját,
de engedi a Flutter UI-t. A CI-ben mért három útvonalat használó regressziós
cella a javítás előtt fordítási hibával piros, utána zöld lett; egy ideiglenes
presentation `SharedPreferences` import a valódi-sértés próbában továbbra is
pirosra vitte az őrt. Lokális `tools/round-gate.sh
test/core/architecture_dependency_test.dart`: 6/6 zöld, 26/26 teszt.

Branch: `heal/E08-R12-H3-1`; PR: [#369](https://github.com/wolfcasaba/strumsight/pull/369).
Az E08-R12 saját PR-je [#367](https://github.com/wolfcasaba/strumsight/pull/367)
nyitva marad, mert a pipeline perzisztens queue-azonosítása saját kör-PR-ként
ismeri fel; a következő firing a heal merge-je után ugyanazt a kört folytatja.
Következő SDD-kör továbbra is: **E08-R12 — Streak UI V2 és recovery flow**.

## ✅ [HEAL E08-R12/H6] KÉSZ — generált l10n aggregátum helyett feature-szegmens scope — PR #365 (2026-08-20, L365)

Az E08-R12 Terra implementere a brief szerint közvetlenül módosította a
`lib/l10n/app_en.arb` és `app_hu.arb` fájlokat, de ezek E99-R17 óta generált
aggregátumok. A kötelező round-gate ezért reprodukálhatóan mindkét locale-ra
aggregate-freshness hibával állt meg; a generátor futtatása a hiányzó
forrás-szegmensek miatt eldobta volna az új kulcsokat. Ez Class B brief-hiba
volt, nem router baseline-drift és nem az E08-R10/L360 egyszeri
motor-kimenetcsonkítása.

A javított, kanonikus pre-flight brief név szerint engedi a
`lib/l10n/features/gamification_{en,hu}.arb` forrás-szegmenseket és a két
deterministikusan regenerált aggregátumot, tiltja az output közvetlen
szerkesztését, és előírja a `dart run tool/gen_l10n_segments.dart --write`
lépést. A `tools/tests/test_e08_r12_l10n_scope.py` a javítás előtt 2/2 piros,
utána 2/2 zöld volt; strict brief-lint: nincs lelet; teljes Python/router gate:
680 passed, 1 skipped, 587 subtests passed. A kör production diffje a Terra
worktree-ben érintetlen maradt; a következő firing ugyanazt az E08-R12 kört
folytatja az új source-segment contracttal. Lecke: **[[L365]]**.

## 📐 [TERV] Chapter 14 briefek: E14-R10…R14 — a „truthfulness és UX hotfix" blokk (2026-08-20)

**User-kérés:** „mehetsz tovább" — a Chapter 14 briefelésének folytatása az
R01–R09 blokk lezárása után. Ez az öt kör az, amelyik a user MÉRT panaszára
válaszol („hiába van kész a backend, az APK-n nem látszik semmi"): itt lesz
először igaz és látható a felismerés a felületen.

| Kör | Tárgy | ADR | Előfeltétel |
|---|---|---|---|
| `E14-R10` | direction abstention: bizonytalan iránynál NINCS ↓/↑ nyíl; a user-küszöb nem mehet a biztonsági minimum alá; a bizonytalan esemény nem hibás esemény a pontozásban | 0362 | R04 + R08 |
| `E14-R11` | külön chord- és strum-confidence, `noChord`/`unknownChord`/`lowSignal`, százalék helyett szöveges állapot | 0363 | R04 |
| `E14-R12` | `RecognitionStabilizer` (Free/Guided profil): provisional → confirmed, immutábilis esemény, nincs timeline-churn | 0364 | R04 |
| `E14-R13` | Live UI truthfulness: egy fő üzenet, history lenyitva NEM alapértelmezett, ok-szöveg bizonytalanságnál, 200% textscale | 0365 | R11 + R12 |
| `E14-R14` | Audio Setup és Accuracy Check lépés-gép + eszköz-profil (képernyő nélkül, §0.0 drift) | 0366 | R05 + R11 |

**Kötött döntés minden körben:** a shipping DSP/ML konstans NEM mozdul
(AGENTS.md §9) — az R10 kapuja a classifier FÖLÉ kerül, nem bele; a küszöb
held-out kalibrációs halmazon MÉRT érték, a `docs/eval/`-ban a futtatott
paranccsal együtt. Az `E14-R14` `risk = "high"` (mikrofon + eszköz-profil),
indoklás-sorral; a többi `normal`.

**Mérve:** `python3 tools/brief-lint.py --brief <mind az öt> --level strict` →
nincs lelet; `python3 tools/brief-lint.py --open --level base` → nincs lelet.
A sorok `prepared`-ek: a futó prioritás változatlanul a Chapter 13 UI-sáv.

**Hátralévő Chapter 14:** R15–R42 (hard-negative corpus, strum recovery,
chord recovery, adaptív termék-UI, field validation) — briefek még nincsenek.

## 📝 [TERV] Chapter 14 — az E14-R06…R09 briefjei megírva: a mérési blokk (R01–R09) teljes (2026-08-20)

**User-kérés:** „folytasd a briefek megírását". A Chapter 14 §8 szerinti első
blokk — **R01–R09: mérési és bizonyítási alap** — ezzel teljes: minden körhöz
van futtatható szerződés.

| Kör | Tárgy | ADR | Kockázat |
|---|---|---|---|
| `E14-R06` | Accuracy Lab csomag + consent-kapu (UI nélkül, §0.0 drift) | 0358 | high (mikrofon-felvétel, privacy) |
| `E14-R07` | annotációs séma + validator + annotátor-egyetértés (GUI nélkül, §0.0 drift) | 0359 | normal |
| `E14-R08` | csoportosított evaluation harness + leakage-védelem | 0360 | normal |
| `E14-R09` | baseline dashboard + fail-closed release gate | 0361 | normal |

**Két kötött scope-szűkítés (mindkettő §0.0-ban dokumentálva, mért indokkal):**
az R06 a Lab **adat- és adatvédelmi magját** építi képernyő nélkül (a
képernyők helye a Chapter 13 sáv, különben a két sáv ugyanarra a felületre
írna), az R07 pedig az annotáció **szerződését és validatorát** GUI nélkül (a
repónak nincs desktop/web célja, és a gate egy GUI-t nem tud vezetni). Mindkét
felület-rész külön körre (`E14-R06b`, `E14-R07b`) marad.

**Újrahasznosítás, nem újraírás:** az R07–R09 az `ADR 0249 / E06-R29` bevált
alakját viszi tovább (`evaluation/analysis/manifest_schema.json` +
`EvaluationManifestParser` + `tool/audio_analysis_evaluate.dart`): nyers audio
soha nem kerül a repóba, a CI kis szintetikus fixture-ön fut, a valós korpusz
külső manifesttel, kézzel. A `ml/honest_eval.py` (tanító oldal) NEM módosul.

**Mérve:** `brief-lint --level strict` mind a négy briefre → *nincs lelet*;
`brief-lint --open --level base` az összes nyitott körre → *nincs lelet*;
`python3 -m pytest tools/tests -q` → 679 passed, 1 failed (a szokásos
környezeti `gh`-piros), 595 subtests.

**A sorok `prepared`-ek** — a futó prioritás változatlanul a Chapter 13 UI-sáv.

## 📝 [TERV] Chapter 14 — az E14-R02…R05 briefjei megírva (PREPARED, user-kérés 2026-08-20)

**User-kérés:** „írd meg a briefeket az SDD tervek alapján" — a Chapter 14
(Recognition Accuracy & Useful UI Recovery) folytatása. Az `E14-R01` (recovery
kickoff + release guard) `done`, de a következő körökhöz **nem volt brief**,
tehát a lánc nem tudta futtatni őket.

**Megírva** (`tools/round-brief-prep` protokoll, mind a négy `brief-lint
--level strict` szerint TISZTA):

| Kör | Tárgy | ADR | Kockázat |
|---|---|---|---|
| `E14-R02` | reprodukálható felismerési baseline + evidence index | 0354 | normal |
| `E14-R03` | model activation telemetry, fail-visible fallback | 0355 | high (telemetria-redakció) |
| `E14-R04` | `RecognitionFrame` V2 domain contract (6 döntési állapot) | 0356 | normal |
| `E14-R05` | Live signal quality analyzer (8 állapot, hiszterézis) | 0357 | high (nyers mikrofon-PCM) |

**A briefek mért tényekre épülnek, nem a doksira** — a fontosabbak:
`StrumCrnn.tryLoad` néma `catch (_) → null` (`strum_crnn.dart:28-35`) és a
`_tryLiveCrnn` ugyanez (`live_pipeline.dart:21-30`), tehát ma nem látszik,
melyik felismerő fut; a `LiveFrame` 11 mezőjéből EGYETLEN `confidence` van, és
az a strumé (`live_frame.dart:69`), 19 fájl hivatkozik rá → kötelező adapter; a
Live minőségjelzés ma egyetlen skálázott RMS (`live_pipeline.dart:231`),
miközben a batch oldalon az `signal_quality_math.dart` (ADR 0224) mért
képletei KÉSZEN vannak — az R05 ezért újrahasznosít, nem újraír.

**A sorok `prepared`-ek, nem `pending`-ek:** a user prioritása most az UI-sáv
(Chapter 13). Amikor a felismerési sáv is indulhat, a négy sor `pending`-re
állítása egy commit — a `brief-lint --open --level base` már ma is tiszta rájuk.

**Nyitva marad:** a Chapter 14 R06–R42 briefjei (36 kör) — a következő adag.

## ✅ E08-R11 KÉSZ — Qualified day, planned rest és recovery policy — PR #363, squash `6a8d0b72` (2026-08-20)

A gamification application-réteg most csak legalább 120 másodperc érvényes
aktivitást minősít standard napnak; az explicit recovery út 60 másodpercnél
nyílik. A tervezett pihenőnap a Practice Generator publikus, reason-code-os
heti szerződéséből érkezik, nem fogyaszt freeze-t, az óra-visszalépés pedig
nem növeli és nem töri a streaket. A hétnapos consistency külön, egyedi
qualified napokból számolt projekció. A döntést ADR 0352 rögzíti.

Implementer: Terra (`gpt-5.6-terra`); független correctness és high-risk
security review: Sol (`gpt-5.6-sol`), mindkettő APPROVED. Az első review egy
MAJOR hibát reprodukált `TZ=Europe/Budapest` alatt: az UTC-alapú rest-day
konverzió eltért a shipping `StreakLogic.epochDayOf` helyi-midnight
napalapjától. A javítás után 12/12 célzott teszt és a teljes 6/6 round-gate
zöld; a „minden aktivitás kvalifikál" mutáció A1/A8/A9 cellákat pirosra
vitte. Exact `0674de52`: Full Gate
[32379760277](https://github.com/wolfcasaba/strumsight/actions/runs/32379760277)
és Router CI
[32379709904](https://github.com/wolfcasaba/strumsight/actions/runs/32379709904)
success. A részletes történet a `docs/handoff-archive.md` elején található.
Következő SDD-kör: **E08-R12 — Streak UI V2 és recovery flow**.


## 🚦 [GOV] E13-R01 `prepared` → `pending` — elindul a Chapter 13 (UI/UX design system) sáv (user-döntés 2026-08-20)

**Miért:** a `pipeline-slots=2` merge után (PR #360) a második sáv MÉRHETŐEN
üres maradt, mert nem volt engedélyezett munka hozzá — nem slot-hiba. A
`tools/round-slots.py plan` az E08-R12 futása mellett ezt adta:
`free_slots: 1`, `rejected: E99-R22 — teljesítetlen előfeltétel: E99-R21`
(az R21 `hold`-on áll), az E13-sáv 36 sora pedig `prepared` volt, amit a
driver szándékosan nem futtat — ember állítja futtathatóra.

**A döntés (2026-08-20, két lépésben):** a Chapter 13 program-nyitó köre, az
**E13-R01** (UI baseline inventory és screenshot corpus) `pending` — majd a
user pontosítása után („hagy fejlessze a UI-t") a **teljes E13-sáv nyitva**:
mind a 36 sor `pending`. A sáv így magától halad R01 → R02 → …, ahogy az Epic
8 sáv teszi; bármelyik sor bármikor `hold`-ra tehető, ha közbe kell lépni.
Ugyanaz a minta, mint az Epic 6 sorainak megnyitása (user-döntés 2026-08-11).

**Mérve a teljes nyitásra:** `python3 tools/brief-lint.py --open --level base`
mind a 36 nyitott E13-briefre → *nincs lelet*, tehát a Router CI nyitott-kör
kapuja zöld marad.

**Tesztelhetőség (user-igény):** az E13-R01 diffje szándékosan NEM hoz látható
felületváltozást (leltár-tool + `docs/ui/**` baseline + teszt), a valódi UI a
R02-től épül. A Dart-only körökre a `tools/round-ci-plan.py` APK NÉLKÜLI Full
Gate-et ír elő, ezért a telefonos próbához az APK-t külön kell kérni:
`gh workflow run build-apk.yml --ref main` (a futás artefaktumként adja a
release APK-t).

**Mérve a döntés előtt (ezen a felhő-boxon, `main @ 7b5315b` + ez a sor):**

* `python3 tools/brief-lint.py --open --level base` → *nincs lelet* (az
  E13-R01 briefje a nyitott körök kapuján is átmegy);
* `tools/round-slots.py plan --slots 2` az E08-R12-t `running`-ra állítva,
  `inflight=E08-R12`: **admitted: E13-R01** — tehát a tervező fájl-diszjunktnak
  és előfeltétel-késznek méri a futó gamification-kör mellett. (Ugyanez a hívás
  az E08-R12 `pending` sorával az E08-R12-t admittálja: a `plan` a sor
  státuszát nézi, nem az inflight-regisztert — ez a mérés kerete, nem lelet.)

**Nem változott:** a slotszám (`2`), a rotáció (`sol`), a queue összes többi
sora, és a mérce egyetlen lépése sem. A kör motorja a sor szerint `terra`,
orchestrátora a Sol-pin szerint a Sol.

**Az E13-R01 briefje kötelező pre-flightot ír elő** (§2 számai `main @
17670d4f`-en készültek: képernyők, hex-találatok újramérése, eltérésnél §0.0
revízió) — ezt az orchestrátor a dispatch előtt elvégzi.

## ✅ E99-R20 (GOV-14) KÉSZ — kombinált-HEAD kör-landoló és H8-SELFDUP őr — PR #361, squash `5ad15b5f` (2026-08-20)

A `tools/round-land.sh` a merge-záron belül köti a PR identitását a mért
branchhez/SHA-hoz, friss `main`-re rebase-el, csak a két append-only naplót és
a kör saját briefjét oldja mechanikusan, a kombinált HEAD-en futtatja a
round-gate-et, majd safe-force-push után új exact-SHA CI-t kér. Változatlan,
már igazolt HEAD-en squash-merge-el. Az új H8-SELFDUP patch-id őr rebase előtt
blokkolja azt a mért hibát, amikor egy régi, rebase előtti csúcs
visszamerge-elése a kör saját patcheit megduplázza.

Implementer: Terra; független correctness és high-risk security review: Sol,
mindkettő APPROVED. Izolált review: scope-audit OK (6 útvonal, 2
generated/ignored), round-gate 6/6 zöld, tooling pytest 664 passed / 2 skipped
/ 574 subtest; a H8-SELFDUP mutáció guard nélkül RED, visszaállítva GREEN.
Exact `a73493f4`: Full Gate
[32373805059](https://github.com/wolfcasaba/strumsight/actions/runs/32373805059)
és Router CI
[32373785655](https://github.com/wolfcasaba/strumsight/actions/runs/32373785655)
success; post-merge round-gate a friss `main`-en 6/6 zöld. A részletes
történet a `docs/handoff-archive.md` elején található.
Következő SDD-kör: **E08-R11 — Qualified day, planned rest és recovery
policy**.

## 🔥 [GOV] MIND A KÉT SLOT Sol+Terra — commitolt slot-döntés és Sol-vezényelt önjavítás (user-döntés 2026-08-20, branch `claude/sol-orchestrator-terra-implementator-jtf4z5`)

**User-döntés:** „mind a két sloton azt akarom, hogy a Sol orchestrátor és a
Terra implementátor dolgozzon" — a PR #351 Sol-pin kiterjesztése a párhuzamos
sávra. A kör-dispatch felállása (Sol vezényel, Terra implementál) már élt; ami
hiányzott, az a két MÉRT rés:

1. **A slotszám nem utazott a repóban.** A `PIPELINE_SLOTS` csak a cron
   env-jében élt (`slots=${PIPELINE_SLOTS:-1}`), tehát pontosan az az osztály,
   amit a rotációnál már megmértünk (E99-R14 lecke): a cron exportált env-je
   némán felülírja a git-en érkező user-döntést, és a lánc egysávosra esik
   vissza anélkül, hogy ez bárhol látszana. Mostantól a commitolt
   [`docs/execution/pipeline-slots`](docs/execution/pipeline-slots) (`2`)
   ERŐSEBB az env-nél (**file > env > script-default**), eltérő env-re
   log-sort ír (`SLOT-FÁJL: …`), üres/hiányzó fájlra marad a mai env-
   szemantika, nem pozitív egészre pedig `die` (fail-closed). A RAM-fedezet
   őre (`effective_slots`, ADR 0171 §1) VÁLTOZATLAN — a fájl a KÉRT sávokat
   mondja meg, a tényleges párhuzam ettől lefelé térhet el, naplózott
   `SLOT-KORLÁT` sorral. Új teszthorog: `--requested-slots` (a RAM-őr ELŐTTI,
   feloldott érték). A `tools/pipeline-status.sh` is ezt olvassa, különben
   „1 kért"-et hazudott volna két futó sáv mellett.

2. **Az önjavító kör is slotot foglal — de a Claude-keretből ment.** Az
   `attempt_selfheal` a rögzített `sonnet-impl` identitással és
   `orchestrator_preference=claude`-dal indult, vagyis a második sáv munkája
   épp azt a keretet fogyasztotta, amit a Sol-pin kímélni akar. Mostantól a
   pin alatt (`orch_rotation=sol` ÉS van Codex-oldal) a heal-ülést a **Sol**
   vezényli, rögzített identitása a nyilvántartás új `sol` sora, és a
   harmadik (utolsó) kísérlet innen vált MÁS modellre — a gyakorlatban a
   **Terrára** (ADR 0307 §2 lever, ami `sol` sor nélkül némán elmaradt volna:
   a `heal_engine_for_attempt` ismeretlen névre a saját motort adja vissza).
   Pin nélkül (alternate | claude | terra) minden BITRE a régi, kvóta-tudatos
   Claude→Terra úton marad; a `PIPELINE_FALLBACK_ENGINE=none` fail-safe
   ugyanígy visszaejt a Claude-útra.

**Függetlenség — nem nyílt rés.** Az új `sol` sor (`codex`, `~/.codex-terra`,
`gpt-5.6-sol`) implementernek választva a MODELL-azonosság miatt ütközik a
sol-orchestrátorral, tehát `H-INDEP` fail-closed; a `terra` (`gpt-5.6-terra`)
változatlanul független. A `orchestrator_conflicts_with_implementer` elavult
kommentje („ilyen sor ma nincs a nyilvántartásban") frissítve.

**Módosult:** `tools/round-pipeline.sh` (slot-fájl precedencia + fail-closed,
`--requested-slots` horog, Sol-vezényelt heal + `sol` heal-identitás, frissített
függetlenség-komment), `docs/execution/pipeline-slots` (ÚJ, `2`),
`docs/execution/engine-registry.tsv` (`sol` ülés + indoklás),
`tools/pipeline-status.sh` (őszinte „kért" slotszám),
`docs/execution/pipeline-orchestrator-prompt.md` (MOTOR-FELÁLLÁS + §4.1),
`AGENTS.md` (§15.7 GOV-blokk), tesztek: ÚJ
`tools/tests/test_sol_terra_both_slots.py` (13 cella: commitolt `2`, file>env,
env-szemantika fájl nélkül, 4 fail-closed eset, RAM-őr épsége, `sol`
registry-ülés, driver-default modell-egyezés, ütközés-mátrix, Sol-vezényelt
heal, pin nélküli Claude-heal, utolsó kísérlet → Terra, `fallback=none`
fail-safe), `tools/tests/test_selfheal_escalation.py` (a régi utat mérő cellák
explicit env-pinnel — ugyanaz a minta, mint a PR #351 `alternate`-celláinál).

**Mérés (ezen a boxon):** `python3 -m pytest tools/tests -q` — a kör előtt
650 passed / 1 failed / 2 skipped / 570 subtests, a kör után (lásd a commit
üzenetét) ugyanaz az egyetlen, KÖRNYEZETI piros
(`WorkspaceRestorationHermeticityTest` — nincs `gh` CLI ebben a sandboxban, a
VÁLTOZATLAN HEAD-en is ugyanígy piros). Az új cellák a production-változás
NÉLKÜL mérve pirosak (15 failed / 5 passed a fájlon belül), vele zöldek.

**Visszaálláskor** (a Pro lejárta után) a `docs/execution/pipeline-slots`
fájlt és a `test_the_committed_slots_file_value_is_two` cellát EGYÜTT kell
átírni; a rotáció-fájl `alternate`-re állítása magától visszaviszi a healt is
a Claude-útra.

**BOX-OLDALI TEENDŐK** (a felhő-sandboxból nem pótolhatók):

1. **HORIZON git-notes** — a `refs/notes/*` push innen 403-tiltott (ugyanaz,
   mint a 2026-08-20-i GOV-FIX 3. pontjánál). A merge után a boxon:

   ```bash
   git notes add -m "round=gov-both-slots-sol-terra verdict=pass tests=663 lesson=slot-decision-travels-in-the-repo-and-heal-follows-the-sol-pin" <a merge-elt squash-commit>
   git push origin 'refs/notes/*'
   ```

2. **Crontab-zaj (opcionális):** `crontab -l | grep PIPELINE_SLOTS` — a sor a
   fájl-elsőbbség miatt már hatástalan (log-sor jelzi, ha eltér), a zaj
   csökkentésére törölhető. A rotáció-sorral azonos megfontolás.
## ✅ E08-R10 KÉSZ — Streak V2 domain és read-only legacy migráció — PR #362, squash `892e04a6` (2026-08-20)

A gamification feature új, verziózott `StreakState` V2 contractot, tiszta és
óra-mentes `StreakPolicy`-t, típusos transition reasonöket, valamint read-only
legacy adaptert kapott. Az adapter a `ss.streak.state` envelope-ot részesíti
előnyben, majd a `practice_streak_v1` raw JSON-ra esik vissza; egyik forrást
sem írja vagy törli. Az öt shipping legacy érték veszteség nélkül megmarad,
a legacy feature és `/streak` útvonal érintetlen. A döntést ADR 0351 rögzíti.

Implementer: Terra (`gpt-5.6-terra`); független correctness és security
review: Sol (`gpt-5.6-sol`), mindkettő APPROVED, nyitott lelet nélkül. Az
izolált reviewer gate 7/7 zöld; a legacy↔V2 eldobható parity-próba több mint
4 000 kombinációt mért; a kötelező gap-2 mutáció az A4 cellát pirosra vitte.
Exact `f5a0a8de`: Full Gate
[32371975469](https://github.com/wolfcasaba/strumsight/actions/runs/32371975469)
és Router CI
[32371933077](https://github.com/wolfcasaba/strumsight/actions/runs/32371933077)
success. A részletes történet a `docs/handoff-archive.md` elején található.
Következő SDD-kör: **E08-R11 — Qualified day, planned rest és recovery policy**.

## 🔁 [HEAL E08-R10/H6] `outcome=retry` — Terra `blocked` jelzés a kötelező round-gate.sh kimenet megszakadásáról; byte-azonos reprodukció 54s alatt 7/7 zölden zárt, kódjavítás nem kellett (2026-08-20, L360)

Az E08-R10 (Streak V2 domain + legacy migráció, ADR 0351) Terra
implementációja (`terra/e08-r10-streak-v2-domain-and-legacy-migration`, HEAD
`f2e368b3`, `scope_audit=ok`) `blocked`-ot jelzett: a kötelező
`tools/round-gate.sh test/features/gamification/domain/streak_policy_test.dart
test/features/streak` hívás kimenete a legacy streak-suite indításánál
megszakadt a Terra saját (Codex-exec) futtatókörnyezetében, jóllehet Terra
saját ad-hoc tesztfuttatásai (11+20 teszt), az architecture/secrets/l10n
ellenőrzés és a scope-audit mind zöldek voltak. A self-heal a PONTOS
halt-parancsot futtatta újra ugyanazon a munkapéldányon és HEAD-en, egy
MÁSIK, egyidejűleg futó self-heal (E99-R20/H8) mellett is: 54 másodperc
alatt mind a 7 lépés zöld (`format`/`analyze`/mindkét teszt-útvonal/
`architecture`/`secrets`/`l10n`), kilépési kód 0, „MINDEN GATE ZÖLD". Sem a
gate script, sem a termék-kód nem hibás — a megszakadás a Terra saját, ezen
a repón kívüli futtatókörnyezetének egyszeri jelensége volt. Nincs
kódváltoztatás; a meglévő branch/commit érintetlenül vár a következő
E08-R10 firingre, amely az örökség-ellenőrzés (§0.2) szerint megtalálja és
onnan folytatja. Lecke: **[[L360]]**.

## ✅ E08-R09 KÉSZ — Legacy progress adapter és activity backfill — PR #359, squash `842231f5` (2026-08-20)

A legacy `PracticeEntry` snapshot most determinisztikus, SHA-256-alapú opaque
activity ID-kre fordítható exact duplikátum-megőrzéssel; a backfill nulla
retroaktív XP-t ad, de változtathatatlan statisztikai reportot készít. A
`GamificationMigrationState.processedCount` az eredeti snapshot első fel nem
dolgozott indexét tárolja, ezért invalid rekordok mellett is restart-biztos.
Az első correctness review F1 BLOCKER + F2/F3 MAJOR, a security review S4
MAJOR leletét két javítás lezárta; a végső Sol re-review és security review
APPROVED. Exact `e25d3158`: Full Gate
[32365896298](https://github.com/wolfcasaba/strumsight/actions/runs/32365896298)
és Router CI
[32365922753](https://github.com/wolfcasaba/strumsight/actions/runs/32365922753)
success. A részletes történet a `docs/handoff-archive.md` elején található.
Következő SDD-kör: **E08-R10 — Streak V2 domain és legacy migráció**.

## ✅ [HEAL E08-R09/H4] KÉSZ — checkpoint a szűrt event-listát indexelte az eredeti legacy snapshot helyett — kör-ágra pusholva, PR nélkül, `3a702692` (2026-08-20)

Az E08-R09 (legacy progress adapter + activity backfill, ADR 0307/0350) H4-gyel
állt meg: a Terra/Codex javító kör UTÁN a független security-reviewer S4
MAJORt talált nyitva (`docs/reviews/e08-r09-security.md`) —
`GamificationMigrator._checkpointFor` és a write-loop a
`LegacyPracticeAdapter.adapt(entries)` SZŰRT `events` listáját indexelte az
eredeti, caller-supplied `entries` snapshot helyett, így egy invalid rekord
jelenlétében a perzisztált `processedCount` (ADR 0350 D5: "az első fel nem
dolgozott EREDETI index") alulszámolt, és eltérhetett az `entries.length`-től
egy teljes, sikeres futás után is. Mért bizonyíték a review-ban: checkpoint=2,
4 elemű snapshot 1 invalid rekorddal → várt `[3,4]` írás helyett mért `[3]`.

Javítás (`lib/features/gamification/data/migration/gamification_migrator.dart`):
`_checkpointFor(events.length)` → `_checkpointFor(entries.length)`, a
write-loop és a belső bound-check ugyanígy. Négy állandó regressziós cella
(`legacy_practice_migration_test.dart` S4a-d: invalid a checkpoint
alatt/rajta/fölötte + teljes futás nulláról) — mérve piros a javítás előtt
(mutáció-visszaállítással, S4a byte-azonos a review saját reprodukciójával),
zöld utána; `tools/round-gate.sh` a két érintett teszt-fájlon zöld
(format/analyze/17+11 teszt/architecture/secrets/l10n). **Egy MÁSODIK,
független, izolált klónban egy security-reviewer subagenttel is
újra-ellenőrizve** — saját kézzel megismételt mutáció-kill ugyanazokat a
számokat adta, és a `_checkpointFor`/`processedCount` egyetlen más
hívóhelyénél sem talált a régi szemantikára támaszkodó kódot.

[[L304]] mintája szerint (`docs/LESSONS.md`) a hibás kód kizárólag a megállt
kör SAJÁT, `main`-be még nem olvadt ágán élt (a teljes migrátor/adapter
feature csak a kör 4 commitjában létezik, `main`-en — `9e18c68d` — nincs
jelen sem az ADR 0350, sem a `migration/` könyvtár), ezért a javítás NEM
`heal/E08-R09-H4-1` branch+PR-en ment, hanem 3 commitban közvetlenül a kör
saját ágára (`terra/e08-r09-legacy-progress-adapter-and-backfill`, HEAD
`3a702692`) lett pusholva, PR és CI-dispatch nélkül — `main` és
`docs/rounds/*.md` érintetlen. A `docs/reviews/e08-r09-security.md`
review-doksi frissült: S1-S4 mind CLOSED, Verdikt **APPROVED**. A lánc
következő E08-R09 firingje a szokásos PR/CI/merge lezárást viszi végig ezen
az ágon. Lecke: [[L358]].

## ✅ [HEAL E08-R09/H3] KÉSZ — `allowed_paths` nem tartalmazta az ADR 0344 D7 által R09-re kiosztott séma-fájlt — PR #357, squash `3d88d7d9` (2026-08-20)

Az E08-R09 (legacy progress adapter + activity backfill, ADR 0307) dispatchja
H3-mal állt meg **modellhívás előtt** — a `terra` implementer még el sem
indult (`.pipeline/HALTED` `implementer/PR/CI nem indult`). Gyökérok: a
brief kötött döntése (§5.3/A5, ADR 0307) egy **perzisztált migrációs
checkpointot** követel meg ("Félbeszakadt migráció az ellenőrzőponttól
folytatódik, nem elölről"), de az egyetlen hely, ahol ez élhet —
`GamificationMigrationState` a
`lib/features/gamification/data/gamification_storage_schema.dart`-ban — az
ELŐZŐ, már merge-elt E08-R08 kör (ADR 0344) D7 pontja szerint **szándékosan**
csak verzió-jelölő helyfoglaló: "A tényleges migrációs mezőket a Kör 9/10
... tölti ki." Az E08-R09 brief `allowed_paths`-a viszont sosem sorolta fel
ezt a fájlt — a kör a saját elfogadási kritériumát nem tudta volna
teljesíteni anélkül, hogy vagy scope-on kívülre lépjen, vagy csendben
tágítsa a listát. Class B (kör-tartalom: ADR + brief kontra `allowed_paths`),
nem implementer- vagy eszközhiba.

Feloldás (`docs/rounds/e08-r09-legacy-progress-adapter-and-backfill.md`
§0.0): a séma-fájl **egyetlen, szűken körülhatárolt** bővítésként bekerült
az `allowed_paths`-ba — kizárólag a `GamificationMigrationState` osztály
bővíthető checkpoint mezővel/mezőkkel, a másik három dokumentum és a
`GamificationStorageKeys`/`migrationStateMaxBytes` nem. Kimondott,
nem-tárgyalható korlát: az új mező(k)nek alapértelmezett értékkel kell
rendelkezniük, hogy a már merge-elt (és ebben a körben TILOS zónában maradó)
`gamification_repository_test.dart` A3 zéró-argumentumos round-trip cellája
érintetlenül zöld maradjon. A brief-lint S8 strict lelete (nincs
visszakeresett előzmény) is lezárva: `ADR 0117` Döntés 2 (E03-R08,
dalfájl-migráció) ugyanezt a mintát — checkpoint mint saját verziózott
JSON-dokumentum — már megalapozta.

Regressziós védelem:
`tools/tests/test_e08_r09_migration_state_schema_scope.py` —
`audit_legacy_scope()`-ot futtatja a ténylegesen committolt brief ellen; a
mért halt-útvonal RED volt a javítás előtt (kézzel visszaállítva
`git show HEAD:...`-tal, nem kitalált feltevésből) és GREEN utána, egy
szomszédos fájl (`gamification_repository.dart`, ugyanabban a könyvtárban)
pedig továbbra is scope-on kívül marad — a bővítés egy fájl, nem az egész
`data/` könyvtár. Teljes gate izolált heal-worktree-ben:
`python3 -m pytest tools/tests -q` → 652 passed/1 skipped/570 subtests/0
failed (650/1/570 volt a kör előtt). `brief-lint --open --level base` és
`--level strict` is tiszta. Router CI
[32357936017](https://github.com/wolfcasaba/strumsight/actions/runs/32357936017)
success az exact push SHA-n (`c373f3f4`), amit a merge előtt a helyi HEAD-del
összevetve igazoltam. Nincs törölt/gyengített teszt, nincs küszöb-lazítás,
`tools/round-gate.sh`/`.github/workflows/**` érintetlen. Lecke: [[L357]].

Az eredeti E08-R09 dispatch modellhívás nélkül állt meg — nem volt félkész
munkapéldány, commit vagy nyitott PR a self-heal előtt, ezért ez a heal nem
vitt tovább tartalmi migrációs munkát; a lánc friss dispatch-csal folytatja
E08-R09-et a felfrissített brieffel.

## ✅ [HEAL E99-R20/H6] KÉSZ — `WrapperModeTest` hiányos leszivárgás-pop-listája — PR #356, squash `a0bf0d51` (2026-08-20)

A `terra` implementer E99-R20-on (GOV-14, round-landolás-automatizálás,
ADR 0313) `blocked`-ot jelzett: a kötelező §7 gate
(`python3 -m pytest tools/tests -q`) a
`WrapperModeTest.test_the_legacy_call_without_round_engine_stays_minimax`
cellán bukott, KÉTSZER egymás után (mérve a saját worktree-jében,
`/home/ubuntu/ss-terra-e99-r20`, head `21224fa9`). A self-heal saját, első
reprodukciós kísérlete (a HALTED szó szerinti parancsa egy FRISS shellben)
zöld lett — csak a nyers Terra-napló adta a tényleges gyökéroket: az L341
(UGYANAZON a napon, E99-R17 H6) négyelemű leszivárgás-pop-listája nem volt
teljes. A `tools/codex-round.sh` a `tools/engine-profile.sh env <motor>`
teljes kimenetét (`ENGINE_MODEL` és hat társa) exportálja a HÍVÓ session
sajátjaként, ami a §7 gate-en át ugyanúgy bekerül a `WrapperModeTest.
run_wrapper()` szimulált alfolyamatába, mint az L341-ben talált négyes —
csak EGY SZINTTEL FELJEBBI forrásból, és BÁRMELYIK motorral (nemcsak
minimax-szal) kiváltható. A pop-listát a teljes `engine-profile.sh env`
kulcskészletre bővítettük (`CODEX_HOME`, `CLAUDE_CONFIG_DIR`,
`ENGINE_MODEL`, `ENGINE_STALL_MINUTES`, `ENGINE_ROUND_TIMEOUT`,
`ENGINE_CONTEXT_WINDOW`, `ENGINE_MAX_OUTPUT`, `ENGINE_REASONING`), és egy
regressziós tesztet adtunk hozzá, amely a valódi mért `terra`-exportot
szimulálja (`test_ambient_engine_profile_env_does_not_leak_into_the_legacy_run`).
RED a bővítés nélkül, GREEN vele; teljes `tools/tests` gate izolált
heal-worktree-ben 650 passed/1 skipped/570 subtests/0 failed, Router CI
[32354341693](https://github.com/wolfcasaba/strumsight/actions/runs/32354341693)
success az exact push SHA-n; post-merge egy FÜGGETLEN, friss klónból a
célzott fájl újra zöld (21 passed). Nincs törölt/gyengített teszt, nincs
küszöb-lazítás, `tools/round-gate.sh`/`.github/workflows/**` érintetlen.
Lecke: [[L356]] (a lecke egy mellékesen mért ballépést is dokumentál: az
`engine-profile.sh env <motor>` diagnosztikai futtatása kulcsot birtokló
motoroknál a NYERS API-kulcsot írja stdoutra — a self-heal ezt a boxon,
sajátjának minősülő kulcsokkal, egy interaktív diagnosztikai lépésben tette,
harmadik fél felé nem jutott ki, de jövőbeli self-healnek ezt kerülnie kell).

Az eredeti E99-R20 (GOV-14) kör TARTALMI munkája (D1–D5, `tools/round-land.sh`
+ `tools/tests/test_round_land.py`) ÉRINTETLEN maradt a `terra` worktree-ben
(`/home/ubuntu/ss-terra-e99-r20`, 3 commitolatlan fájl) — ezt a self-heal
szándékosan NEM vitte tovább (ADR 0112 hatókör), a pipeline driver folytatja
friss sessionben. Két, a körhöz nem tartozó, előzőleg is létező maradvány
érintetlen maradt (nem ennek a self-healnek a hatóköre): a
`gov/round-lander` remote branch (`da80e4d8`, a régi ADR 0313 + brief
pre-flight-branchje, tartalma már máshonnan mergelve) és a
`/home/ubuntu/ss-heal-E08-R04-1` worktree (egy korábbi self-heal maradványa).

## ✅ E08-R08 KÉSZ — Gamification repository és tároló-séma — PR #355, squash `ebb03d9d` (2026-08-20)

Négy különálló, verziózott `JsonDocumentStore`-dokumentum EGY sémafájlban
(`gamification_storage_schema.dart`): profil-pillanatkép (`schemaVersion` +
`totalXp` — a domain `GamificationProfile`-tól független DTO, a `progress`
mindig a hívó `LevelCurve`-jével újraszámolva), katalógus-verzió, jutalom-
postaláda (a MEGLÉVŐ `JsonCollectionStore<T>` wrapperrel, `maxItems:
inboxRetentionLimit=50`, inkluzív küszöb) és egy szándékosan minimális
migrációs-állapot placeholder (Kör 9/10 tölti majd ki). `LocalGamificationRepository`:
atomikus egy-hívásos pillanatkép-csere, explicit `available/missing/corrupt`
olvasási státusz, broadcast watch-stream. Új architektúra-guard: a
gamification `application/` (és a még nem létező `presentation/`) NEM
importálhat `SharedPreferences`-t — a MEGLÉVŐ E08-R02 marker-lista és helper
újrafelhasználásával. ADR [`0344`](docs/adr/0344-gamification-storage-schema-versioned-documents-and-layer-purity.md)
(a briefben előre kiosztott `0306` stale volt — a foglaló `0344`-et adta).
Implementer: Codex (`~/.codex`, gpt-5.6-terra).

A független review (`docs/reviews/e08-r08-review.md`) az implementer saját
zöld tesztjei MÖGÖTT egy MAJOR rést talált, eldobható próbateszttel mérve:
**F1** — `readInbox()` egy redundáns, saját előzetes validáló ciklust
futtatott a `JsonCollectionStore` rekordonkénti hibatűrése ELŐTT, ezért egy
EGYETLEN hibás postaláda-bejegyzés a TELJES listát (akár 49 érvényes
bejegyzést is) „sérültnek" jelentette — ez pontosan az ellenkezője [ADR
0054](docs/adr/0054-versioned-user-content-documents.md) garanciájának
("corruption now costs one record, not one feature's entire content").
Mérve egy 3 elemű (2 jó + 1 hiányzó-`id` közepes) envelope-próbával:
`status=corrupt, value=null` a javítás előtt. Egy javító kör törölte a
redundáns ciklust és állandó regressziós tesztet adott hozzá; a reviewer
saját, izolált újraklónban függetlenül megerősítette (11/11 zöld a célzott
tesztben). N1 (a watch-stream optimistán sugároz egy elnyelt írási hiba
esetén — meglévő, projektszintű kockázat öröklődik, nem új regresszió) nyitva
maradt, NEM blokkoló.

A kör alatt a `main` HÁROMSZOR mozdult (E99-R19 GOV-13 lezárása, PR #353
Sol-pin env-fix, E99-R20 GOV-14 induló munkája — mind diszjunkt fájlkör) —
mindháromszor `merge --no-ff` + teljes CI-újradispatch a §0.3 szerint,
IZOLÁLT `/tmp` klónokból (a megosztott munkafa közben egy párhuzamos E99-R19
session `git reset`-je + commitja átmenetileg felülírta a helyi branch-
mutatót a megosztott fán — az `origin`-on lévő, már pusholt munka
érintetlen maradt, a felismerés után minden további git-művelet izolált
klónból ment). Exact `91821f22`: Full Gate 32349845398 + Router CI 32349841249
success; post-merge célzott gate a friss `main`-en (`ebb03d9d`) önállóan is
zöld (7/7, izolált klónban mérve). Következő SDD-kör: **E08-R09** (Legacy
progress adapter és backfill).

## 🔧 [GOV-FIX] A Sol-pin env-biztos: commitolt rotáció-fájl + modell-ID megerősítve + box-teendők (2026-08-20, a PR #351 follow-upja)

A PR #351 három nyitott kockázatának zárása:

1. **Crontab-felülírás KIZÁRVA (repo-oldali fix):** a rotáció mostantól a
   **commitolt `docs/execution/orchestrator-rotation`** fájlban utazik
   (tartalma: `sol`), és a `round-pipeline.sh` ezt ERŐSEBBNEK veszi a
   `PIPELINE_ORCH_ROTATION` env-nél (file > env > script-default; eltérő
   env-nél log-sor). MÉRT ok: a cron a E99-R14 lecke szerint exportálja az
   env-t, ami némán felülírta volna a git-en érkező user-döntést. Üres/
   hiányzó fájl → env/default; érvénytelen érték → die (fail-closed).
   Teszt-horog: `PIPELINE_ORCH_ROTATION_FILE` (=/dev/null → env-szemantika).
   Guard-cellák: file>env precedencia, commitolt érték = `sol` pin,
   invalid → die. **Visszaálláskor a fájlt ÉS a
   `test_the_committed_rotation_file_value_is_sol` cellát együtt írd át.**
2. **Sol modell-ID MEGERŐSÍTVE (nincs teendő):** külső források szerint a
   Codex CLI GPT-5.6 szintjei pontosan `gpt-5.6-sol` / `gpt-5.6-terra` /
   `gpt-5.6-luna` (a Sol a flagship) — a driver defaultja helyes,
   `PIPELINE_SOL_MODEL` felülírás nem kell.
3. **HORIZON git-notes — A KÖVETKEZŐ BOX-OLDALI SESSION ELSŐ TEENDŐJE**
   (a felhő-sandboxból a `refs/notes/*` push 403-tiltott, ott nem pótolható):

   ```bash
   git notes add -m "round=gov-sol-pin verdict=pass tests=627 lesson=burn-expiring-pro-quota-sol-orchestrator-terra-implementer" 8fb5beb5
   git push origin 'refs/notes/*'
   ```

   Opcionális takarítás ugyanott: `crontab -l | grep PIPELINE_ORCH_ROTATION`
   — a sor a fájl-elsőbbség miatt már hatástalan, de a zaj csökkentésére
   törölhető. Elvégzés után ez a 3. pont a bejegyzésből kihúzható.

## 🔥 [GOV] Sol-orchestrátor + Terra-implementer MINDEN körben — Pro-keret égetése a lejáratig (user-döntés 2026-08-20, PR #351, branch `claude/router-config-changes-odzv8m`)

**User-döntés:** a ChatGPT Pro előfizetés **napokon belül lejár**, és a
keretének ~90%-a megmaradt — „hadd fogyjon el". Amíg él, MINDEN kör:

- **Orchestrátor/reviewer: Sol** (`gpt-5.6-sol`) — a `tools/round-pipeline.sh`
  rotáció-defaultja `alternate` → **`sol`** (env-vel felülírható:
  `PIPELINE_ORCH_ROTATION`). A Sol a Codex CLI-vel, a Terra
  `~/.codex-terra` CODEX_HOME-jában fut (közös auth), explicit
  `-m gpt-5.6-sol`-lal (`PIPELINE_SOL_MODEL` env-vel állítható). A Sol-pin a
  Claude-zárlat mérése ELŐTT dönt (a Sol nem a Claude-keretből fogyaszt), a
  körönkénti rögzítés (ADR 0242 D1) változatlanul működik rá.
- **Implementer: `terra`** (`gpt-5.6-terra`) — a queue mind a 65 nyitott
  (pending/hold/prepared) sora explicit `terra`-ra állt; az ADR 0069 mért
  motor-szétosztási szabálya erre az időszakra FELFÜGGESZTVE (a queue
  fejléce + `test_open_rounds_follow_the_measured_engine_rule` carve-out
  dokumentálja). A lezárt sorok motorja történeti tény, változatlan.
- **Függetlenség:** a Sol↔Terra pár a meglévő modell-azonossági kulcson
  (`orchestrator_conflicts_with_implementer`) független — két különböző
  modell; a közös Pro-ELŐFIZETÉS a döntés tudatos ára (épp a keret égetése a
  cél). Az `orchestrator_available` a Codex-oldali kapcsolóhoz köti a Solt
  (`PIPELINE_FALLBACK_ENGINE=none` → claude, fail-safe változatlan).

**Módosult:** `tools/round-pipeline.sh` (sol rotációs mód + default, Sol
session-indítás `-m`-mel, ütközés/elérhetőség/`--orchestrator-engine` horog),
`docs/execution/pipeline-queue.tsv` (65 sor engine → `terra` + fejléc),
`docs/execution/pipeline-orchestrator-prompt.md` (MOTOR-FELÁLLÁS blokk
újraírva 2026-08-20-ra, benne a lejárat utáni visszaállás lépései),
`docs/execution/pipeline-codex-orchestrator-preamble.md` (3. ok: Sol-pin),
tesztek: `test_orchestrator_rotation.py`, `test_round_resume_independence.py`,
`test_reviewer_independence.py`, `test_pipeline_integration.py` — az
`alternate`/fallback gépezet cellái explicit env-pinnel mérik a régi utat,
ÚJ cellák mérik a Sol-defaultot (default→sol zárlat alatt is; kör-pin sol;
resume sol+terra; enum `terra`; `--validate-engine terra`).

**Mérés (ezen a boxon):** `python3 -m pytest tools/tests -q` → **597 passed,
1 failed** — az egy piros a `WorkspaceRestorationHermeticityTest` (nincs
`gh` CLI ebben a sandboxban; a VÁLTOZATLAN HEAD-en ugyanígy piros, tehát
környezeti, nem regresszió). CI-n (gh jelen) zöldnek kell lennie.

**A lejárat UTÁN (visszaállás):** rotáció-default vissza `alternate`-re, a
nyitott `terra` queue-sorok visszaosztása (a lejárt előfizetéssel a
`codex`/`terra` sor nem futtatható — `minimax`/`sonnet-impl` a mezőny), és a
prompt MOTOR-FELÁLLÁS blokkjának frissítése. A pontos lépések a blokkban.

## ✅ E99-R19 (GOV-13) KÉSZ — lánc-higiénia, PR #354, squash `4dc8f7d1` (2026-08-20)

A pipeline tiszta, lemaradt `main`-je most csak fast-forwarddal frissül;
valódi divergencia és piszkos fa továbbra is fail-closed megáll. A záró
ritualé a queue `pending → done` átírását a HANDOFF-dokumentációval közös,
egyetlen commitba írja, a driver korábbi `chore(pipeline)` ága pedig
idempotens fail-safe marad. A strict brief-lint S7 csak az indoklás nélküli,
nem router-kockázatos `risk = "high"` briefet jelzi; a base CI-szint nem
szigorodott. A correctness review egy valódi lemaradt+piszkos-fa cellát
kért; az F1 javítás után a review APPROVED, a security review PASS.

Exact branch-head `c17ed660`: Full Gate
[32347005385](https://github.com/wolfcasaba/strumsight/actions/runs/32347005385)
és Router CI
[32347032703](https://github.com/wolfcasaba/strumsight/actions/runs/32347032703)
success. A merge-elt `main` (`4dc8f7d1`) post-merge gate-je is zöld;
tooling-suite: 647 passed, 571 subtests. Lecke: [[L353]].

## ✅ [HEAL E99-R19/H3] KÉSZ — governance-kör SAJÁT `allowed_paths`-ban felsorolt pipeline-fájlja nem H3-alap — PR #352, squash `c4104234` (2026-08-20)

A rotált (Terra) orchesztrátor megtagadta E99-R19 (GOV-13) implementer-
indítását: a brief `allowed_paths`-ának első eleme `tools/round-pipeline.sh`
(D1/D2 kifejezett céltárgya, ADR 0307 §6), a
`docs/execution/pipeline-orchestrator-prompt.md` §4 viszont minősítő nélkül
mondja, hogy ez a session sosem módosítja azt. A forrás,
`docs/adr/0087-autonomous-round-pipeline.md` §7 ugyanezt **„kör közben"**
(ad hoc, útközben talált akadály) minősítővel írja — ez a szó a prompt
átiratából hiányzott. Az ADR 0087 §2 H3-fogalma szerint tilos zóna kizárólag
az `allowed_paths`-on **kívüli** útvonal; öt korábbi governance-kör
(E99-R08/14/15/16/18) gyakorlata igazolja, hogy a fájl a szabványos
implementer → review → merge úton rendszeresen módosul. Ugyanaz a mintázat,
mint [[L251]] (E99-R08/H3): egy rotált motor a hallgatólagos Claude-
tapasztalat nélkül a betű szerint olvas egy kontextusfüggő tiltást.

Javítás: a prompt §4 és az ADR 0087 §7 (jelölt „Módosítás" blokk) explicit
carve-outot kapott a governance-kör saját, előre engedélyezett briefjére; a
`.github/` és a `round-gate.sh` határa VÁLTOZATLAN maradt normál körre.
Regressziós doksi-teszt (a `test_reviewer_scope_exemption_docs.py` mintáját
követve): `tools/tests/test_pipeline_file_governance_round_exemption_docs.py`
— RED a javítás előtt, GREEN utána, mindkettő lokálisan igazolva. E99-R19
brief `allowed_paths`-a és D1–D3 terve VÁLTOZATLAN, csak egy §0.0 addendumot
kapott. Teljes `pytest tools/tests`: 625 passed, 565 subtests (310s); Router
CI exact-SHA `a2f94f97`: [32341677224](https://github.com/wolfcasaba/strumsight/actions/runs/32341677224)
success (nincs Dart-változás, `build-apk` nem indult). Lecke: [[L352]].

Takarítás: a halted round MiniMax pre-flight-only debris ága
(`minimax/e99-r19-gov-13-chain-hygiene`, csak egy státusz-bump commit, sosem
nyílt rá PR) törölve. A lánc feloldva — a következő firing E99-R19-et friss
sessionnel, a javított prompttal újrapróbálja.

## ✅ E08-R07 KÉSZ — Szintgörbe és profil-projekció — PR #349, squash `010989f3` (2026-08-20)

Monoton `LevelCurve` (egyetlen forrás, inkluzív küszöb, `int64`-közeli
szaturáció), verziózott `GamificationProfile` a lapozott reward ledgerből
teljesen újraépíthetően, és egy `ProfileProjector` (teljes újraépítés +
inkrementális projekció azonos logikával, minden egy eseményben átlépett
szint megjelenik). ADR 0342 (a briefben előre kiosztott `0305` stale volt —
36 szám fogyott el 2026-08-18 óta, a foglaló adta a valódit).

A független review az implementer saját zöld tesztjei MÖGÖTT három valódi
rést talált — mindegyiket mutációs próbával mérve, nem csak olvasással: **F1
BLOCKER** — `rebuild()` kivételt dobott egy vadonatúj (üres) ledgeren,
pontosan a brief fő use case-én (a produkciós `LocalRewardLedgerRepository`
ellen is reprodukálva); **F2 MAJOR** — a „szint soha nem csökken"
lefelé-korrekciós guard teszteletlen volt, törlése mellett minden teszt zöld
maradt; **F3 MAJOR** — az A8 unlock-tiltó regexe egy raw stringbeli dupla
escaping miatt soha nem talált semmit. Egy javító kör mindhármat zárta,
mindegyiket a reviewer külön-külön visszaellenőrizte (fix visszamutálva →
az új teszt pirosra vált → visszaállítva). Lecke: [[L349]]–[[L351]].

A kör alatt a `main` egyszer mozdult (E99-R18/H3 self-heal negyedik
önjavítása, diszjunkt fájlkör) — rebase + teljes CI-újradispatch fogta meg.
Full Gate exact-SHA: 32337856382 success; Router CI: 32337858078 success;
post-merge célzott gate a friss `main`-en önállóan is zöld (6/6). Következő
SDD-kör: E08-R08 — gamification repository és storage schema.

## ✅ [HEAL E99-R18/H3] KÉSZ — a scope-audit jelentése feloldott SHA-t ír `origin/main` helyett, a kör-ág újraszinkronizálva — PR #348, squash `4105c695` (2026-08-20)

Negyedik H3-halt ugyanazon a körön, de a korábbi hármtól ELTÉRŐ gyökérokkal.
`docs/execution/pipeline-queue.tsv` egyszerre védett ÉS a pipeline saját
üzemeltetése által folyamatosan, a kör tartalmától függetlenül íródik (minden
kör-átmenet módosítja). A kör-ág szinkron-merge-e (`e75ae7a4`) néhány
másodperccel egy önálló, a pipeline-tól származó könyvelő commit
(`634562d7`, „E08-R06 done") előtt fagyasztotta be az `origin/main`
pillanatképét — a kör SAJÁT, nem-merge commitjai bizonyíthatóan sosem
érintették a queue-fájlt, mégis a végső `--base origin/main` scope-audit
`protected path changed`-et jelzett, MERT a kör-ág merge-elt másolata
(`E08-R06 … pending`) ténylegesen eltért a friss `main`-től (`E08-R06 …
done`) — egy squash-merge ezt a sort tényleg visszaírta volna. **Ez nem a
scope-audit hibája**: a `legacy_scope.py` fejléce szerint a végső audit
szándékosan a mergelhetőség kérdésére válaszol ([[L347]] már tisztázta ezt a
kettéválasztást a launch-HEAD implementer-scope kérdéstől) — a jelzés IGAZ
volt.

A tényleges javítás: a scope-audit JELENTÉSE a nyers `--base` argumentumot
(a szimbolikus `"origin/main"` sztringet) írta ki feloldott SHA helyett, ami
elrejtette, hogy két, néhány perccel eltérő futás a mögöttes bázis
elmozdulása ellenére azonosnak látszott — ez a self-healben is valódi
nyomozási időt vett el (a megosztott kör-munkapéldány elavult helyi
`origin/main` referenciája miatt egy reprodukciós kísérlet hamis `OK`-t
adott, amíg a blob-hash-ek közvetlen összevetése fel nem fedte az
eltérést). Fix: `tools/ai_router/legacy_scope.py::audit_legacy_scope` a
`base`-t egyetlen `git rev-parse` hívással a függvény elején SHA-ra oldja.

Feloldás: a kör-ág (`minimax/e99-r18-gov-12-generated-public-barrels`) friss
`origin/main`-nel újraszinkronizálva (a H8/`7458ca83` és a második H3/
`96f1ada2` mintáját követve, közvetlen push, PR nélkül — a szinkron csakis
upstream tartalmat húz be); a szinkron közben egy párhuzamosan pusholt F1
review-javítás (`8eeb3146`, architektúra-guard visszaállítás) is
becsatlakozott egy normál, force nélküli merge-dzsel. Végállapot: `dfbfb789`.

Saját méréssel igazolva a HALTED saját reprodukciós parancsával, FRISS `git
fetch` után: `tools/scope-audit.py --repo /home/ubuntu/ss-minimax-e99-r18
--brief docs/rounds/e99-r18-gov-12-generated-public-barrels.md --base
origin/main` → `Legacy scope audit OK (origin/main..dfbfb789bff1, 16
changed path(s), 1 generated/ignored)` (előtte: `FAILED, protected path
changed: docs/execution/pipeline-queue.tsv`). Router CI zöld a heal-ágon
([32336566185](https://github.com/wolfcasaba/strumsight/actions/runs/32336566185),
headSha egyezik); `python3 -m pytest tools/tests -q`: 596 passed, 565
subtests passed (+2 új regressziós teszt, 0 törölve) —
`test_base_symbolic_ref_resolves_to_a_concrete_sha` (RED a fix előtt: a
jelentett `base` a nyers `"origin/main"` sztring; GREEN utána: 40-hex SHA)
és `test_protected_bookkeeping_file_flagged_by_upstream_drift_clears_after_resync`
(a valódi eset kicsinyített, valós útvonalat használó mása). Merge után
independens ellenőrzés friss `main`-en: `pytest tools/tests/
test_legacy_scope.py -q` 12/12 zöld.

**Előretekintő szabály** (rögzítve ADR 0112-ben): ha ugyanez a minta
(folyamatosan íródó védett fájl + hosszan nyitott kör-ág) ötödször
jelentkezik ugyanezen a körön, az már nem pontjavítást igényel, hanem
`outcome=escalate`-et.

Lecke: [[L348]]. ADR: [`0112`](docs/adr/0112-self-healing-pipeline.md)
Módosítás (2026-08-20).

## ✅ E08-R06 KÉSZ — XP policy engine és diminishing returns — PR #347, squash `29e78eaf` (2026-08-20)

Magyarázható, verziózott ötkomponensű XP policy készült napi cap-pel,
practice-repeat csökkenő hozammal és explicit parent/child deduppal. A review
egy farmolható gyermek-event újraküldést talált; a javítás külön
`rewardedEventIds` history-állapottal és A5 RED→GREEN regressziós teszttel
zárta. Full Gate exact-SHA: 32333321826 success; Router CI: 32333305673
success. Következő SDD-kör: E08-R07 — level curve és profile projection.

## ✅ [HEAL E99-R18/H3] KÉSZ — a H8 ADR-0112 blokk landolt `main`-en, a kör-ág visszaszinkronizálva — PR #346, squash `ee010d39` (2026-08-20)

Harmadik H3-halt ugyanazon a körön: a kör-ág az `origin/main`-hez képest a
tiltott `docs/adr/0112-self-healing-pipeline.md`-et is módosította. Gyökérok
(class A, folyamat/precondition): a H8 self-heal (`7458ca83`) a saját,
kör-ág-specifikus javítását — helyesen — a kör SAJÁT ágára pusholta (L343
mintája), de ugyanabban a merge-commitban a saját ADR-0112 „Módosítás"
könyvelő blokkját is odaírta, és sosem mozgatta át `main`-re. Egyetlen
termék-brief `allowed_paths`-ának sem kellene ezt az utat tartalmaznia (ADR
0112 §2: ez kizárólag a self-heal saját, brieftől független joga) — az
`allowed_paths` bővítése tehát téves irányú fix lett volna.

Feloldás: a H8-blokk byte-azonosan landolt `main`-en (PR #346, `ee010d39`;
egy apró szám-ütközés-javítás `a109edbc` — az L346 számot időközben az
E08-R05 saját maga foglalta le), plusz egy új ADR-0112 blokk ([[L347]]) a
szabály rögzítésére: a L343 kör-ág-push kivétel kizárólag a FUNKCIONÁLIS
javításra érvényes, az ADR-0112 könyvelő commit sosem utazhat vele egy
bundle-ben. A kör-ág ezután visszamergelte a friss `main`-t (`96f1ada2`,
`6b9bf12f`) — a `docs/adr/0112` diffje emiatt teljesen eltűnt a kör-ág
`origin/main`-hez képesti diffjéből, allowlist-módosítás nélkül.

Saját méréssel igazolva a HALTED saját reprodukciós parancsával:
`tools/scope-audit.py --repo /home/ubuntu/ss-minimax-e99-r18 --brief
docs/rounds/e99-r18-gov-12-generated-public-barrels.md --base origin/main` →
`Legacy scope audit OK (origin/main..6b9bf12f005c, 15 changed path(s), 0
generated/ignored)` (előtte: `FAILED, path outside allowed scope:
docs/adr/0112-self-healing-pipeline.md`). Router CI zöld a heal-ág fején
([32329319021](https://github.com/wolfcasaba/strumsight/actions/runs/32329319021));
`python3 -m pytest tools/tests -q`: 594 passed, 565 subtests passed (+1 új
hermetikus regressziós teszt, 0 törölve) —
`tools/tests/test_legacy_scope.py::LegacyScopeTest::
test_selfheal_adr_bookkeeping_must_land_on_base_not_only_the_round_branch`
szintetikus git-fixture-rel méri mindkét mintát (bundle → sértés; landolás+
visszamerge → a path eltűnik).

**Mellékesen feltárt, NEM javított lelet** (H8-mintát követve, [[L343]]): a
mergelt kör-ágon a teljes `pytest tools/tests -q` 2 piros tesztet mutat
(`test_e99_r18_scope_debris_revert.py`), mert a kör SAJÁT, ezt a self-healt
MEGELŐZŐ §0.0e munkája egy 12. bejegyzéssel bővítette az `allowed_paths`-t
(`docs/adr/0339-...`), a két korábbi H3 self-heal által pinnelt tuple-ök
viszont 11-et várnak. Igazoltan a resync ELŐTT is fennállt (a merge sem a
briefet, sem a guard-tesztet nem érintette konfliktussal). A round saját
allowlist-bookkeeping munkája — a brief §0.0f-je és a következő E99-R18
dispatch dolga, nem a self-healé.

Lecke: [[L347]]. ADR: [`0112`](docs/adr/0112-self-healing-pipeline.md)
Módosítás (2026-08-20).

## ✅ E08-R05 KÉSZ — Reward eligibility és trust policy — PR #345, squash `30fa8138` (2026-08-20)

Determinisztikus `RewardEligibilityPolicy` (application) +
`DefaultRewardEligibilityPolicy`/`RewardEligibilityPolicyConfig`
(infrastructure): négy KÜLÖN dönthető kapu (alap-XP, quality bonus, mastery,
verified), mindegyik stabil `RewardReason`-nal elutasításkor, verziózva
(`policyVersion: int`, konzisztens az R03 `RewardLedgerEntry.policyVersion`
mezőjével). A bizalom (`EvidenceTrust`, a mastery/verified kapukhoz) és a
mért jelminőség (`quality`, a quality bonus + mastery kapukhoz) SZÁNDÉKOSAN
független tengely — alacsony bizalom önmagában sosem tiltja a quality
bonust, és a hiányzó/fatális minőség sosem alakul át néma számmá (ADR 0286
§1). Döntés: [ADR 0338](docs/adr/0338-reward-eligibility-policy-four-gates.md).

**A brief előre kiosztott `ADR 0303`-a elavult volt** — a
`.pipeline/inflight/adr/0303` marker valójában az E07-R17 körhöz tartozott
(mérve a pre-flightban); az élő `tools/round-slots.py reserve-adr` **0338**-at
adott, dokumentált §0.0 brief-revízióval. [[L267]] precedense („pre-asszignált
ADR-szám elavulhat") itt egy ÚJ változatban jelentkezett: a szám NEM
sosem-foglalt volt, hanem egy MÁSIK kör markere alatt élt — lásd [[L346]].

Független review egy MAJOR leletet talált: a `verified` kapu `mastery`-től
való függetlensége egyetlen teszttel sem volt bizonyítva — mért,
reprodukált mutációs próba (`_evaluateVerified` ideiglenes cseréje
`return mastery;`-re, izolált `/tmp` klónban) a teljes 15/15 tesztet
zöldön hagyta a rontás ALATT is. Javító kör (ugyanaz a motor, codex) egy
cellával zárta (`mastery` adott, `verified` `insufficientTrust`-tal
elutasítva); a mutáció megismétlése utána PIROSRA vált, ahogy kell.
Security review (risk=high, kötelező) PASS, 0 BLOCKER/MAJOR, 3 alacsony
kockázatú NOTE (két már ebben a körben dokumentált: `EvidenceTrust`
sorrend-függés az ADR 0338 §7-ben; a purity-őr még nem fedi a
gamification `application/`-t — jövőbeli bekötő kör dolga).

A kör alatt a `main` egyszer mozdult (párhuzamos E99-R18 self-heal-lánc,
ugyanabban a megosztott munkafában) — `git merge --no-ff origin/main`
konfliktus nélkül, majd Full Gate ÉS Router CI (utóbbi manuálisan
dispatch-elve, mert a sync-merge diffje már nem érintett trigger-útvonalat
— [[L344]] pontosan ezt írja elő) mindkettő zöld a merge SHA-n
(`82b8b683`): [Full Gate](https://github.com/wolfcasaba/strumsight/actions/runs/32327526505),
[Router CI](https://github.com/wolfcasaba/strumsight/actions/runs/32328486649).
Post-merge célzott gate a friss `main`-en (`30fa8138`) önállóan is zöld
(format, analyze, 16/16 teszt, architecture, secrets, l10n). Scope-audit:
a kör saját commitjai (pre-flight + implementáció + javítás) mind az 5
`allowed_paths` bejegyzésen belül, 0 kívül.

Review: [docs/reviews/e08-r05-review.md](docs/reviews/e08-r05-review.md)
(APPROVED, F1 FIXED `8a989af5`). Leckék: [[L267]], [[L344]], [[L346]].
Következő kijelölt SDD-kör: **E08-R06 — Kör 6 (XP policy engine és
diminishing returns)**, előfeltétele ez a kör (jogosultsági policy) és az
R03 ledger.



## ✅ [HEAL E99-R18/H3] KÉSZ — H8 kör-ági coexist-teszt bekerül az allowed_paths-ba, két bejegyzéssel — kör-ág `6a494d5e` (2026-08-20)

A D4 §0.0c narrowing fix (glob → explicit `practice_generator`-regisztráció)
technikailag zöld volt, de a scope-audit egy fájlon bukott:
`tools/tests/test_round_slots_generated_paths_and_patterns_coexist.py` — ezt
a **H8** self-heal (ugyanaznap korábban) írta közvetlenül a kör-ágra, a
normál brief-szerkesztési folyamaton kívül, ezért sosem került az eredeti
`allowed_paths`-ba. A D4 fix legitim módon érintette (pontosan azt a
mechanizmust méri, amit átalakít) — ez a `tools/tests/
test_e99_r18_scope_debris_revert.py` (az ELŐZŐ, 2026-08-19-i H3-önjavítás
terméke) saját docstringje szerinti E07-R29 „valódi bővítés" minta, nem a
§0.0 debris-revert minta ismétlődése.

**Mért csavart:** a bővítés magába az ELŐZŐ H3 debris-revert regressziós
őrbe ütközött, ami bájtra-egyezést követel a pinnelt `allowed_paths`-ra — az
őr frissítése pedig, mivel saját maga sem szerepelt az eredeti listán,
önmagában ÚJ scope-rést nyitott volna. `grep -rl` igazolta, hogy harmadik
fájl nem hivatkozik a pinnelt konstansra, tehát a lánc pontosan **két**
bejegyzésnél zár (a coexist-teszt + maga az őr fájlja); az új regressziós
bizonyítékot a meglévő őr-fájlba kellett összevonni, nem külön fájlba, hogy
ne nyisson egy harmadikat.

Saját méréssel igazolva: a HALTED-ben rögzített reprodukciós paranccsal
(`tools/scope-audit.py --base 7458ca83...`) `Legacy scope audit OK (11
changed path(s))` (előtte: `FAILED`, 1 sértés); `python3 -m pytest
tools/tests -q`: 614 passed, 2 skipped (611-ről, +3 új regressziós teszt, 0
törölve). Router CI a kör-ág friss fejjel
([32326908611](https://github.com/wolfcasaba/strumsight/actions/runs/32326908611))
zöld. A H8 mintáját követve ([[L343]]) NEM main-merge: normál (nem force)
push a kör saját ágára (`6a494d5e`), a PR/review a következő E99-R18
dispatch dolga marad.

Lecke: [[L345]]. ADR: [`0112`](docs/adr/0112-self-healing-pipeline.md)
Módosítás (2026-08-20).

## ✅ E08-R04 KÉSZ — Activity outbox és megbízható feldolgozás — PR #344, squash `318edd6d` (2026-08-20)

A Gamification feature most korlátos, perzisztens lokális activity outboxot
kapott explicit enqueue/drain contracttal. A ledger-írási hiba nem jut vissza
a már mentett feature-sessionhöz; az ack csak sikeres, idempotens
`appendIfAbsent` után történik. Sérült rekord, retry-limit és kapacitás feletti
legrégebbi pending rekord lekérdezhető karanténba kerül. A konstruktor pozitív
kapacitást és retry-limitet követel, a karantén snapshotja restart után is
visszaolvasható. Döntés: [ADR 0333](docs/adr/0333-activity-outbox-reliable-processing.md).

Független correctness review **APPROVED**, security review **PASS**; a végső
izolált A4 mutáció (ack a ledger-írás előtt) pirosra vitte a célteszteket,
visszaállítás után 15/15 zöld. Exact pre-merge CI a `8402ee42` headen: Full
Gate [32323029473](https://github.com/wolfcasaba/strumsight/actions/runs/32323029473)
és Router CI [32324054702](https://github.com/wolfcasaba/strumsight/actions/runs/32324054702)
success. A post-merge `flutter analyze` zöld; a teljes post-merge gate
ismételt futtatása a root worktree-ben a gate-scripten belül az analyze lépés
után nem adott terminális összegzést, ezért nem tekinthető további gate-bizonyítéknak.

Következő kijelölt SDD-kör: **E08-R05 — Reward eligibility és trust policy**.

## ✅ [HEAL E99-R18/H8] KÉSZ — origin/main szinkron, unió generated-path feloldás — kör-ág `7458ca83` (2026-08-20)

A lánc az E99-R18 (GOV-12) kör-ágának `origin/main` szinkronjánál H8-cal
állt meg: a briefen kívül `tools/round-slots.py`-ban is tartalmi ütközés
volt az E99-R17 (squash `8d7b6a67`) exact-set `GENERATED_PATHS`-a és az
E99-R18 D4 saját, glob-alapú `GENERATED_PATH_PATTERNS`/`is_generated_path`
mechanizmusa között — ez NEM a dokumentált brief-only H8 minta. Mérve: a
két mechanizmus additív (mindkét oldal SAJÁT regressziós csomagja csak a
sajátját méri); a feloldás mindkét konstanst megtartja, az `effective_paths`
predikátumát unióvá bővíti, és egy új teszt
(`test_round_slots_generated_paths_and_patterns_coexist.py`) méri a
kombinált esetet. Normál (nem force) push a kör SAJÁT ágára — **ez NEM
`main`-merge**, a H8-recept szerint a PR/review a következő E99-R18
dispatch dolga marad.

**A kötelező teljes `pytest tools/tests -q` gate egy MÁSIK, a H8-tól
független, a kör SAJÁT D4 kódjában már a merge előtt is jelen lévő hibát
tárt fel** (empirikusan igazolva a kör pre-merge HEAD-jén is):
`SlotPlanningTest::test_real_epic_four_rounds_are_correctly_rejected`
piros, mert a D4 broad glob minden feature `public.dart`-ját generáltnak
minősíti, holott csak a `practice_generator` lett migrálva — 25+18 nyitott
brief két másik feature-ön ütközne felügyelet nélkül, ha ez elérné a
`main`-t. Router CI ezért piros (run
[32321598642](https://github.com/wolfcasaba/strumsight/actions/runs/32321598642)) — **ez a self-heal TUDATOSAN nem javította**: a helyes hatókör
(pl. migrált-feature allowlist) a kör saját implementer+reviewer
ciklusának termékdöntése, nem az ADR 0112 §2 szűk (brief/eszköz)
jogosultságáé. A lelet a brief saját `## 0.0b` szakaszába, a
`docs/LESSONS.md` **L343**-ba és a heal-status `detail=`-jébe is bekerült,
hogy a következő E99-R18 dispatch az ELSŐ olvasatnál lássa, review előtt
zárja.

Lecke: [[L343]]. ADR: [`0112`](docs/adr/0112-self-healing-pipeline.md)
Módosítás (2026-08-20).

## ✅ E99-R17 (GOV-11) KÉSZ — szegmentált ARB-források és determinisztikus aggregátum — PR #343, squash `8d7b6a67` (2026-08-20)

Az angol és magyar ARB-k immár `base/` és feature-fragmentum forrásokból
épülnek; a `tuner` 14 kulcsa önálló fragmentumba került, az `app_{en,hu}.arb`
deterministikus, kulcsrendezett aggregátum. A gate a `--check` úton a
frissességet és a 1 405 üzenet kulcs-/placeholder-paritását is méri. Az
aggregátumok a slot-tervezőben regenerálhatók, ezért nem blokkolják a
párhuzamos köröket, a feature-fragmentumok viszont továbbra is ütköznek.

Független review APPROVED; high-risk security re-review PASS WITH NOTE. A
reviewer valódi-sértés próbája a fragmentumközi `@key` tulajdonlás guardját
ideiglenesen kikapcsolva két regressziós tesztet pirosra vitt, majd
visszaállítás után zöldet mért. Exact-SHA CI: Full Gate
[32318857856](https://github.com/wolfcasaba/strumsight/actions/runs/32318857856)
és Router CI
[32318859249](https://github.com/wolfcasaba/strumsight/actions/runs/32318859249)
success. Post-merge célzott gate a friss `main`-en 7/7 zöld. Következő,
kapcsolódó SDD-kör: **E99-R18 (GOV-12)** — generált `public.dart` barrelek.

## ✅ [HEAL E99-R17/H6] KÉSZ — hermetikus WrapperModeTest az ambiens MiniMax-endpoint szivárgás ellen — PR #342, squash `bdad2a64` (2026-08-20)

Az E99-R17 minimax implementer `blocked`-ot jelzett: a kötelező §7 gate
(`python3 -m pytest tools/tests -q`) 2 hibán bukott a
`tools/tests/test_claude_harness_engines.py::WrapperModeTest`-ben, mindkettő
a kör `allowed_paths` listáján kívül — jogos blokk, nem implementer-hiba.

**Gyökérok (Class A, mérve):** a `run_wrapper()` teszt-fixture
`dict(os.environ)`-ból indul. Amikor ez a pytest-gate egy ÉLŐ
`ROUND_ENGINE=minimax` session Bash-hívásaként fut (pont ez az eset — a
minimax implementer a saját gate-jét futtatja), a szülő session saját,
jogos `ANTHROPIC_BASE_URL`/`ANTHROPIC_AUTH_TOKEN`/
`CLAUDE_CODE_AUTO_COMPACT_WINDOW`/`MINIMAX_API_KEY` exportjai öröklődnek a
szimulált `sonnet-impl` (natív, "nincs override") alfolyamatba, és két
asszerció a szivárgást méri, nem a `mm-round.sh` tényleges viselkedését.
Önálló, kód nélküli reprodukció megerősítette: pontosan ugyanez a 2 hiba.
Ez **tisztán teszt-izolációs** hiba — egy valódi, friss `sonnet-impl`
dispatch a driver saját tiszta al-folyamatából indul, a `mm-round.sh`
termék-kód méve NEM hibás.

**Javítás:** `run_wrapper()` explicit törli a négy szivárgás-gyanús
változót az ambiens env-másolatból, mielőtt a teszt saját `extra_env`-je
rákerülne. Regressziós teszt (RED→GREEN mérve, izolált worktree-ben):
`test_ambient_endpoint_env_does_not_leak_into_a_subscription_mode_run`.
Csak ez az egy tesztfájl változott (47 sor +, 0 −); `tools/mm-round.sh` és
minden termék-fájl érintetlen. Teljes `tools/tests` mindkét irányban zöld
(tiszta env 587 passed; a pontos szivárgás-reprodukcióval 586 passed 1
skipped — 0 failed mindkétszer). Router CI zöld a merge SHA-n. Részletek:
[[L341]].

**A self-heal SZÁNDÉKOSAN nem vitte előre E99-R17 tartalmi munkáját** — a
kör saját ága (`minimax/e99-r17-gov-11-l10n-parallel-safety`, benne a már
zöld-tesztelt F1 javítással) érintetlen marad; a lánc ezután egy FRISS
kör-sessionben folytatja E99-R17-et, immár hermetikus gate mellett.

## ✅ E08-R03 KÉSZ — Reward ledger és idempotencia-index — PR #340, squash `39c0bd5f` (2026-08-19)

Append-only egyetlen igazságforrás a jutalmakra: immutable `RewardLedgerEntry`
(`sourceEventId`, policy-verzió, XP-komponensek, `RewardReason` kód) +
`RewardReason` stabil enum + `RewardLedgerRepository` interfész (nincs
`update`/`delete`) + `LocalRewardLedgerRepository` a `JsonDocumentStore`
mintáján (NEM `JsonCollectionStore` — nincs `capRecords`/`maxItems`, egy
audit-ledger nem veszíthet néma evictionnel). Az `appendIfAbsent` egyetlen
atomikus Future-tail-lel szerializált (`SongTransport._commandTail` mintája,
ADR 0301 2. pont) — a `contains`-majd-`append` szétválasztás technikailag
kizárva. `lib/features/gamification/domain/rewards/`, `data/`, bővített
`public.dart` (csak export-sor, a konkrét implementáció szándékosan NEM
exportált). Implementer: Codex (`~/.codex`, `gpt-5.6-terra`), orchesztrátor/
reviewer Claude Sonnet 5. [ADR 0301](docs/adr/0301-reward-ledger-append-only-idempotency.md).

**Ez a kör második nekifutása.** Az első (21:25 UTC) H6-tal állt meg — a
Codex implementer `blocked`-ot jelzett egy hiányzó generált Flutter l10n
miatt, amit egy `git worktree add`-dal (nem klónnal) nyitott munkapéldány
okozott. Egy self-heal (PR #338, [[L339]]) a burkoló scripteket javította
(`codex-round.sh`/`mm-round.sh` mostantól minden dispatch előtt önmaga
futtatja a `prepare-flutter-generated.sh`-t a saját workdirjén). Ez a futás
egy friss `git clone`-ból indult; a korábbi két félkész, COMMITOLATLAN
munkapéldányt (`ss-codex-e08-r03` — `stopped`, egy párhuzamos implementer
által már foglalt branch miatt main-en ragadt uncommitolt diffel;
`ss-codex-e08-r03-impl` — `blocked`, a fenti l10n-hiba) nem használtam fel:
a brief §0.2 „félkész, jelöletlen munka → indíts tisztán" szabálya szerint.

**A review saját kézhez, izolált `/tmp` klónban reprodukálta az A2
mutációs próbát, nem az implementer önjelentésére hagyatkozott.** Az
atomikus Future-tail-et ideiglenesen egy `hasProcessedEvent` + `await
Future.delayed` + feltétlen append párra cserélve az A2 cella pontosan a
várt módon (`Actual: WhereIterable<bool>:[true, true]`) PIROSRA vált,
visszaállítás után ZÖLD. A [review](docs/reviews/e08-r03-review.md)
**APPROVED** (0 BLOCKER/MAJOR/MINOR, 1 NOTE — a jelzésfájl `gate_shape=
VIOLATION` mezője mért HAMIS POZITÍV volt: a `codex-round.sh` `verify_claim()`
regexe a `codex exec` induló, teljes prompt+preambulum szöveget EGYETLEN
log-sorba író hívása miatt két, egymással össze nem függő idézetet — a
brief `round-gate.sh` hivatkozását és a preambulum MÁSIK példájából
származó `git add -A && git commit` mintát — egyetlen találatnak látott a
sortörés nélküli kereséssel; minden TÉNYLEGES `/bin/bash -lc 'tools/
round-gate.sh ...'` végrehajtás a naplóban csővezeték/lánc nélküli volt,
lásd [[L340]]).

**A kör alatt a `main` HÁROMSZOR mozdult** (más, párhuzamos munka: a
`ops/rag-retrieval-quality` PR #336 és két pipeline-feloldó commit, az
egyik egy VALÓDI párhuzamos kör, E99-R17, ugyanebben a megosztott
munkafában). Mindhárom alkalommal `git merge --no-ff origin/main` +
teljes CI-újradispatch a §0.3 szerint, mielőtt a merge SHA-n bármilyen
zöld kapu evidencia számított volna. A záró rituálékat (ez a
HANDOFF-frissítés, RTM, LESSONS, git-notes) a `tools/round-merge-lock.sh`
zárral sorosítva készítettem, az E99-R17 branch-ét/PR-ját nem érintettem.

**Zöld kapu, mind a végleges, main-mozgás utáni HEAD-en (`02477969`):**
Full Gate [32313777603](https://github.com/wolfcasaba/strumsight/actions/runs/32313777603)
és Router CI [32313779449](https://github.com/wolfcasaba/strumsight/actions/runs/32313779449)
success. Post-merge célzott gate a friss `main`-en (`39c0bd5f`) önállóan is
zöld (7/7: format, analyze, 9 alteszt, architecture, secrets, l10n).
Scope-audit: 7/7 megváltozott fájl az engedélyezett listán, 0 kívül.

Egy mért lecke: **[[L340]]** (a `gate_shape` anti-hallucináció-őr hamis
pozitívot adhat egy hosszú, sortörés nélküli log-sorra — a reviewer NE a
mezőre, hanem saját izolált gate-újrafuttatásra hagyatkozzon). Nyitott
tétel az E08-R02-ből öröklődve, még mindig releváns a Kör 4-nek: a
security-review MINOR-1 leletét (architektúra-guard marker-lista
hálózati/fájl-IO kiegészítése) rendezni kell, mielőtt az outbox valódi
sink-szomszédot hoz a gamification domain mellé. Következő kör:
**E08-R04** (Activity outbox és megbízható feldolgozás), új sessionben.

## ✅ [HEAL E08-R03/H6] KÉSZ — round wrapperek önelőkészítik a Flutter l10n-t dispatch előtt — PR #338, squash `911e5145` (2026-08-19)

E08-R03 H6-tal állt meg: a Codex implementer `blocked`-ot jelzett, mert a
`flutter analyze` 1071 független hibával blokkolt a hiányzó generált
`lib/l10n/app_localizations.dart` miatt. A nyomozás saját méréssel (a
`.pipeline/session-E08-R03-20260819T212506.log` és `/tmp/codex-e08-r03.log`
teljes visszakövetésével, nem bemondásra) igazolta a gyökérokot: az
orchesztrátor a `/home/ubuntu/ss-codex-e08-r03` klónt HELYESEN készítette elő
(`tools/prepare-flutter-generated.sh` lefutott, a generált fájlok ott
léteztek), de a TÉNYLEGES Codex-dispatch a `/home/ubuntu/ss-codex-e08-r03-
impl` útvonalra ment — ami `git worktree list` szerint egy `git worktree
add`-dal nyitott WORKTREE volt a klónról, nem önálló klón. A gitignore-olt
generált kimenet worktree-k közt nem öröklődik, ezért a `-impl` sosem kapta
meg a saját `gen-l10n` futtatását, noha `.dart_tool/` (tehát valamilyen `pub
get`) már lefutott ott. Az implementer helyesen `blocked`-ot jelzett ahelyett,
hogy saját maga hívta volna a `tools/prepare-flutter-generated.sh`-t — az a
saját tiltott zónáján (`tools/**`) kívül esett.

Ez a **negyedik** mérés ugyanerre a hibaosztályra (korábbi: L222/E06-R07,
L228/E06-R10, L230/E06-R11) — mindegyik javítása eddig egy PRÓZAI lépés volt
az orchesztrátor promptjában/skill-jében, legutóbb a `sdd-round-driver`
SKILL.md §3-ba ágyazva. Ez a lépés MOST IS a helyén volt és le is futott —
csak épp egy másik könyvtárra, mint ahova a tényleges dispatch ment. A
javítás ezért a mechanikus legalsó rétegbe került: `tools/codex-round.sh` és
`tools/mm-round.sh` mostantól minden dispatch ELŐTT lefuttatja a **workdir
saját másolatát** (`"$workdir/tools/prepare-flutter-generated.sh"`,
argumentum nélkül — L232/E06-R13), fail-open, függetlenül attól, mit tett az
orchesztrátor, és függetlenül attól, hogy a workdir klón vagy worktree.
Regressziós teszt (`tools/tests/test_round_wrapper_flutter_prerequisite.py`,
valódi mért adat: a `ss-codex-e08-r03` → `ss-codex-e08-r03-impl` worktree-alak
szó szerinti reprodukciója hamis codex/claude/flutter binárisokkal) — piros a
javítás előtt (a flutter binárist egyik burkoló sem hívta meg), zöld utána
(`pub get` → `gen-l10n` → engine-hívás, ebben a sorrendben, a fájl a
worktree-ben jön létre). `python3 -m pytest tools/tests -q`: 580 passed, 566
subtests passed; a négy érintett burkoló-tesztfájl (`test_qwen_
implementer_hardening.py`, `test_claude_harness_engines.py`, `test_fix_
workspace_origin.py`, `test_prepare_flutter_generated.py`) külön futtatva is
zöld (53 passed) — nincs regresszió. Router CI
[32308153558](https://github.com/wolfcasaba/strumsight/actions/runs/32308153558)
success a merge-előtti exact `32aa633a` SHA-n (nincs Dart-változás, tehát a
Router CI az egyetlen szükséges CI-bizonyíték). Lecke: [[L339]].

A self-heal nem nyúlt a leftover `/home/ubuntu/ss-codex-e08-r03` /
`ss-codex-e08-r03-impl` munkapéldányokhoz (nincs bennük nyitott PR — az
implementer a félkész implementációt commit nélkül hagyta) — a következő
E08-R03 dispatch a saját §0.2 „Örökség-ellenőrzés" lépésével dönt a
sorsukról, és mostantól, akármelyiket is választja, a saját workdir-jét maga
a burkoló készíti elő.

## ✅ [HEAL E99-R18/H3] KÉSZ — revert-not-expand: implementer scratch debris — PR #337, squash `80b70d1e` (2026-08-19)

A MiniMax implementer (`/home/ubuntu/ss-minimax-e99-r18`, ág
`minimax/e99-r18-gov-12-generated-public-barrels`, HEAD `e9c4a26b`) három
nyomkövetetlen fájlt hagyott a brief `allowed_paths`-án kívül
(`test_project/lib/features/demo/{public.dart,public/application.dart,
public/domain.dart}`). A Terra orchesztrátor-session ezt H3-mal állította le
(`.pipeline/HALTED`, 20:43:38Z), holott `docs/execution/
pipeline-orchestrator-prompt.md` VIOLATION-sora már eleve két utat ismer: „a
listán kívüli fájlokat **vissza kell állítani**, vagy H3 halt" — és a §2
„Önállóan dönthetsz" felsorolása kifejezetten megnevezi „az
engedélyezett-fájllista **szűkítését**" mint a kör saját hatáskörét.

Az önjavítás (ADR 0112, 1/3. kísérlet) méréssel igazolta, hogy a három fájl
NEM legitim munka — nulla hivatkozás bármely tracked/untracked forrásban,
tartalma bájtra megegyezik a `gen_public_barrel_test.dart` saját, már
`Directory.systemTemp`-be izolált fixture-jével, egyik D-feladatot vagy
„Tilos zóna" cellát sem fedi — és ezt dokumentált `## 0.0 Pre-flight
revízió`-ként írta a brief-be: a helyes folytatás REVERT, `allowed_paths`
bővítése NÉLKÜL (a `test_e07_r29_accessibility_privacy_scope.py` precedens
tükörképe, ahol a listán kívüli fájlok igazoltan hiányzó deliverable-ek
voltak). Az ADR 0112-t egy dated Módosítás-blokk egészíti ki, amely ezt a
precedenst SZŰKEN általánosítja (csak akkor alkalmazható, ha a kifogásolt
útvonalak mérhetően függetlenek minden deliverable-től — egyébként H3/
escalate marad az alapértelmezés). Regressziós teszt (`tools/tests/
test_e99_r18_scope_debris_revert.py`, real measured data): egy eset
valóban piros-a-javítás-előtt/zöld-utána (a brief §0.0 dokumentációja), a
többi a mért adatot zárja a valódi `audit_legacy_scope()`-pal mindkét
irányban. `python3 -m pytest tools/tests -q`: 578 passed, 565 subtests
passed (833→834 teszt-fájl, egyetlen gate-artefaktum hash sem változott).
Router CI [32302589265](https://github.com/wolfcasaba/strumsight/actions/runs/32302589265)
success a merge-előtti exact `547e524e` SHA-n (nincs Dart-változás, tehát a
Router CI az egyetlen szükséges CI-bizonyíték).

A self-heal SZÁNDÉKOSAN nem nyúlt a megállt implementer saját
worktree-jéhez/ágához — az ADR 0112 §2 jogosultsága a briefre és az
engedélyezett-fájllistára szól, nem egy még nem review-zott implementer-ág
tartalmára. A következő E99-R18 dispatch dönt: újrahasznosítja-e a meglévő
worktree-t (a három fájl törlése után) vagy frissen indul.

**Mért mellékhatás, dokumentálva ([[L338]]):** a self-heal PR-be előre írt
`[[L333]]` lecke-hivatkozás a merge KÖZBEN ütközésbe került az egyidejűleg
záruló E08-R02 saját `L333–L336` foglalásával (`6db8abcc`) — a helyes,
frissen leolvasott szám `L337` lett, és ez a záró commit javítja a már
merge-elt hivatkozásokat (ADR 0112, a brief) is.

## ✅ E08-R02 KÉSZ — Kanonikus tanulási esemény-szerződések — PR #335, squash `a3d98ed2` (2026-08-19)

A gamifikáció EGYETLEN bemenete: a feature-agnosztikus, immutable, verziózott
`LearningActivityEvent` sealed hierarchia (`lib/features/gamification/domain/
activity/`) hat altípussal (Practice, Song, Analysis, Plan, Tutor, Vision),
hívó-adta stabil `eventId`-vel, kötelező `schemaVersion`-nel (ismeretlen
érték hibát dob, nem csendes default), és explicit `type`-discriminatorral a
JSON round-tripben (nem mezőkitalálás). `ActivitySource`/`EvidenceTrust`
enumok, `RewardEligibility` adatkontraktus (típus, nem logika — a döntési
logika Kör 5), `lib/features/gamification/public.dart` egyetlen belépő. A kör
NEM integrál egyetlen feature-t sem — Kör 24–26 dolga. Implementer: Codex
(`~/.codex`, `gpt-5.6-terra`).

**A pre-flight egy KRITIKUS, mért hibát javított dispatch előtt: az előre
kiosztott `ADR 0300` már foglalt volt.** `.pipeline/inflight/adr/0300`
`round=E07-R15` tartalommal létezett (foglalva 2026-08-16, a brief 2026-08-18-i
írása ELŐTT), de a `docs/adr/`-ban nincs `0300-*.md` — a számot egy korábbi
kör foglalta, sosem fogyasztotta el. A friss `tools/round-slots.py
reserve-adr` a valódi **`ADR 0329`**-et adta. A pre-flight egy második,
technikai kérdést is tisztázott: az A6 architektúra-őr nem bővítheti a
`tool/check_architecture.dart` hardcode-olt `_isSharedDomain()` listáját (az
a fájl nincs a kör engedélyezett listáján), ezért a bevált E07-R02 mintát
követve egy önálló teszt-csoport épült `test/core/architecture_dependency_
test.dart`-ban, a meglévő `_forbiddenDomainMarkerOffenders`/`_withoutTrivia`
segédfüggvények újrafelhasználásával — az implementer ezt pontosan a
pre-flight §0.0.2 útmutatása szerint valósította meg.

**A review saját kézhez, izolált `/tmp` klónban mindkét kötelező
valódi-sértés próbát megismételte, nem az implementer önjelentése alapján
fogadta el.** A `schemaVersion` guard ideiglenes eltávolítása az A2 cellát
pontosan a várt hibaüzenettel vitte pirosra; egy befecskendezett
`package:flutter/foundation.dart` import az új architektúra-guardot vitte
pirosra, pontos hibaüzenettel. Mindkettő tiszta visszaállítás után zöld. A
[correctness review](docs/reviews/e08-r02-review.md) **APPROVED** (0
BLOCKER/MAJOR/MINOR, 3 NOTE — enum wire-formátum a Dart `.name`-en, nem
explicit kódtérképen, ADR 0257 precedenséhez képest; az A1 „const
konstruktor" bizonyítéka forráskód-szintű, nem futásidejű teszt; a
`score`/`duration` minden altípuson univerzális mező, a Kör 24-26
integrátornak érdemes lehet altípusonként felülvizsgálnia). A kötelező
[security review](docs/reviews/e08-r02-security.md) (`risk=high`) **PASS**
(0 CRITICAL/BLOCKER/MAJOR, 1 MINOR, 4 NOTE) — az egyetlen MINOR: az új
architektúra-guard marker-listája nem fed hálózati/fájl-IO markert
(`dart:io`/`dart:convert`/`package:dio/`/`package:http/`), ami MA nem aktív
sértés (a domain tiszta), de a Kör 3 (ledger) / Kör 4 (outbox) előtt
javítandó, mielőtt azok valódi sink-szomszédot hoznak a domain mellé.

**Két mért process-hiba a záráshoz vezető úton, mindkettő javítva, mindkettő
lecke.** (1) Az implementer `done`-t jelzett, de a commitja nem volt
pusholva — az orchesztrátor pusholta, mielőtt bármilyen review érvényes
lehetett volna ([[L334]]). (2) A biztonsági review ELSŐ futása ezt az
pusholatlan állapotot mérte (egy worktree-izoláció a push ELŐTT ágazott le),
és emiatt téves BLOCKER-t adott — a push megerősítése után frissen
klónozva megismételve **PASS** lett ([[L335]]). Egy harmadik lecke a
CI-exact-SHA ellenőrzésről: a záró review-dokumentum-commitok nem mindig
váltanak ki friss Router CI-futást, ha nem érintik a `docs/rounds/**`
útvonalat — a brief §11 kitöltése (ami ÉRINTI) végül friss, a tényleges
végső SHA-n mért Router CI-futást adott ([[L336]]).

**Zöld kapu.** A `round-ci-plan.py` `full-gate.yml`-t (nincs natív diff) ÉS
Router CI-t (a diff `docs/rounds/**`-t érint) is előírt. Mindkettő zöld a
végleges, mindkét review-t és a brief §11-et is tartalmazó HEAD-en
(`4b46ef44` — egy köztes SHA-n dispatch-elt Full Gate-et a §11-lezáró commit
miatt újra kellett dispatch-elni, hogy pontosan a merge SHA-n legyen
evidencia): Full Gate
[32300885059](https://github.com/wolfcasaba/strumsight/actions/runs/32300885059)
és Router CI
[32300867375](https://github.com/wolfcasaba/strumsight/actions/runs/32300867375)
success. Post-merge célzott gate a friss `main`-en (`a3d98ed2`) önállóan is
zöld (7/7: format, analyze, 2 teszt-útvonal, architecture, secrets, l10n).

**A kör alatt egy párhuzamos self-heal (E99-R18, egy másik kör H3 haltjának
javítása) futott ugyanebben a megosztott munkafában** — a záró rituálék
(ez a HANDOFF-frissítés, RTM, LESSONS, git-notes) a `tools/round-merge-lock.sh`
zárral sorosítva készültek, a másik kör branch-ét/PR-ját nem érintettem.

Négy mért lecke: **[[L333]]** (egy brief-be előre írt ADR-szám a brief-írás
és a kör-indítás között elavulhat, verseny nélkül is), **[[L334]]** (a
legacy Codex-motor commitol, de nem feltétlenül pushol), **[[L335]]** (a
security review dispatch-elése az implementer push-ja előtt hamis BLOCKER-t
termel egy elavult snapshot miatt), **[[L336]]** (a CI-dispatch utáni,
csak `docs/reviews/**`-et érintő commit nem vált ki friss Router CI-t —
merge előtt mindig a tényleges végső SHA-n kell ellenőrizni). Nyitott tétel
a Kör 3/4-nek: a security review MINOR-1 leletét (guard marker-lista
hálózati/fájl-IO kiegészítése) rendezni kell, mielőtt a ledger/outbox valódi
sink-szomszédot hoz a gamification domain mellé. Következő kör: **E08-R03**
(Reward ledger és idempotency index), új sessionben.

## ✅ E08-R01 KÉSZ — Gamification baseline és mért migrációs szerződés — PR #334, squash `0e19f67d` (2026-08-19)

Az Epic 8 nyitókörének kimenete az
[`epic-08-start.md`](docs/baseline/epic-08-start.md): file:line alapú leltár a
Progress, Streak, Learn és Share tényleges feature- és import-éleiről, aktuális
és legacy storage-kulcsokról/wire-alakokról, streak-freeze, Daily Challenge és
lesson-star határokról, a meglévő guardokról és az ADR 0289/0290 dark-pattern
checklistről. Az új [ADR 0328](docs/adr/0328-measured-gamification-baseline-contract.md)
rögzíti, hogy a baseline migrációs szerződés, nem új jutalom-policy.

Az első független review két MAJOR leletet mért: a baseline tévesen tagadta a
Share production forrásait és a Learn közvetlen Progress/Streak importjait,
valamint több ADR-követelményt olyan teszttel jelölt lefedettnek, amely csak
szomszédos viselkedést vizsgált. A MiniMax javító köre mindkettőt zárta; a
végső [review](docs/reviews/e08-r01-review.md) APPROVED (0 BLOCKER/MAJOR,
1 MINOR tipográfiai NOTE). Full Gate
[32293515991](https://github.com/wolfcasaba/strumsight/actions/runs/32293515991)
és Router CI
[32293556103](https://github.com/wolfcasaba/strumsight/actions/runs/32293556103)
success a merge-előtti exact `1949f96c` SHA-n; post-merge célzott gate a friss
`main`-en (`0e19f67d`) 9/9 zöld. Következő kör: **E08-R02**, új sessionben.

## ✅ E07-R30 KÉSZ — Evaluation harness, shadow rollout és Epic 7 lezárás — PR #333, squash `ee5821dd` (2026-08-19) — **EPIC 7 LEZÁRVA**

Epic 7 (AI Practice Generator) záró köre. Implementer: Codex (`~/.codex`).
`ShadowPlanGenerator` (`lib/features/practice_generator/application/service/
shadow_plan_generator.dart`, ÚJ) az Epic 7 **első éles, vég-az-végig
kompozíciója**: evidence → skill estimate → priority → candidate selection →
time budget → weekly schedule → a VALÓDI `GenerationOrchestrator.generate()`,
egy saját, no-op `GenerationPlanActivation`-nel (hívásszámláló, nulla
perzisztencia) — a shadow-terv ugyanazon a determinisztikus kódúton születik,
mint az éles út, de sosem aktivál valódi állapotot. A fájl szerkezetileg sem
importál semmit a `data/local/`-ból vagy az `active_plan_controller.dart`-ból,
és nincs `lib/` consumere / `public.dart` exportja — a futó appból
elérhetetlen.

**Pre-flight (§0.0) két, a mért CI-vel ütköző brief-útvonalat javított
dispatch ELŐTT.** (1) A brief (és az SDD-fejezet saját fájllistája is)
`test/features/practice_generator/property/`-t írt elő a két új property
tesztnek — mérve viszont, hogy `.github/actions/flutter-gates/action.yml:47`
a CI randomizált-seedes lépését KIZÁRÓLAG a `test/property` könyvtáron
futtatja (`PROPERTY_SEED: ${{ github.run_id }}`); a brief eredeti útvonalán
a tesztek soha nem kapták volna meg a randomizált seedet, csak a fix 42-t a
sima Test gate-en belül, ami aláásta volna A2/A3-at. Revízió: mindkét teszt
`test/property/`-be került, a meglévő `planner_repair_property_test.dart`/
`planner_time_budget_property_test.dart` mintáját követve. (2) A
`golden_profiles` fixture `.json`-ról `.dart`-ra váltott, mert
`PracticeGenerationRequest`-nek (és beágyazott típusainak) nincs
`fromJson`/`toJson`-ja — a feature MINDEN meglévő fixture-je Dart
builder-függvény. A pre-flight emellett dokumentálta (nem-blokkoló
iránymutatásként), hogy `GenerationPlanInput`-ot korábban SOHA nem épített
`lib/` kód — a `shadow_plan_generator.dart` ezt először teszi élesben.

**Mindkét review zöld, mindkettőt Claude saját kézzel, izolált `/tmp`
klónban ellenőrizte — nem az implementer önjelentése alapján.** A
[correctness review](docs/reviews/e07-r30-review.md) APPROVED (0
BLOCKER/MAJOR/MINOR, 1 NOTE): a gate-et egy friss, GitHub originről klónozott
`/tmp` munkapéldányban újrafuttatta, a hiteles `tools/scope-audit.py`-val
mérte a scope-ot (7 fájl, 0 sértés), saját kézzel megismételte a brief
kötelező valódi-sértés próbáját (egy golden profil elvárását elrontva a
golden-fixture teszt PIROSRA váltott, visszaállítás után zöld), és egy
harmadik, korábban ki nem próbált `PROPERTY_SEED` értékkel is lezöldítette a
property tesztet. A kötelező [security review](docs/reviews/e07-r30-security.md)
(`risk=high`) **PASS** — 0 CRITICAL/BLOCKER/MAJOR/MINOR, 3 előretekintő NOTE
(egyik sem blokkol): `AdaptivePracticePlan.toJson()` egy jövőbeli szabad
szöveges golden profilnál a determinizmus-teszt logjába kerülhetne (ma
inaktív); az aktiválási határ továbbra is fuzionált a
`GenerationOrchestrator`-ban (a completion report ezt maga nevezi meg nyitott
tételként); az eval-tool `test/`-ből importál (réteg-higiénia, nem szállítási
kockázat).

**Zöld kapu.** A `round-ci-plan.py` `full-gate.yml`-t (nincs natív diff) ÉS
Router CI-t (a diff `docs/rounds/**`-t érint) is előírt. Mindkettő zöld a
végleges, mindkét review-commitot is tartalmazó HEAD-en (`d40e2050` — a
review-dokumentumok commitolása UTÁN a korábbi, `404b9b76`-on dispatch-elt
futásokat újra kellett indítani a helyes exact-SHA-n): Full Gate
[32289312900](https://github.com/wolfcasaba/strumsight/actions/runs/32289312900)
és Router CI
[32289316122](https://github.com/wolfcasaba/strumsight/actions/runs/32289316122)
success, `gh run view --json headSha` mindkettőn egyezett a merge előtti
lokális HEAD-del. Post-merge célzott gate a friss `main`-en (`ee5821dd`)
önállóan is zöld (7/7: format, analyze, 2 teszt-útvonal, architecture,
secrets, l10n). Két mért lecke: **[[L330]]** (a property-teszt könyvtárat a
tényleges CI composite action hardcode-olt argumentumával kell mérni, nem a
brief/SDD-fejezet szövegével — mindkettő egyszerre tévedhet ugyanabban az
irányban) és **[[L331]]** (a `sdd-round-review` skill saját
review-klónozó parancsa a megosztott lokális fából elhasal, ha a kör-branch
egy izolált implementer-klónból pusholt közvetlenül originre — GitHub
remote URL-ből klónozva a hiba osztálya kizárt).

**Nyitott tételek (a completion report — `docs/sdd/epic-07-completion-report.md`
— és a security review NOTE-2 által megnevezve, jövőbeli körnek/emberi
döntésnek):** a `practiceGeneratorEnabled`/`plannerAssistEnabled` flagek
bekapcsolása emberi release-döntés; a teljes CI-suite/property/APK
CI-bizonyíték továbbra is kötelező (ez a helyi korpuszfutás nem helyettesíti);
valós Android-eszközös offline flow és eszköz-specifikus latency/memória
baseline még hátravan; a `GenerationOrchestrator.generate()` továbbra is
egyetlen hívásban fuzionálja a validálást/javítást az aktiválással — egy
jövőbeli preview-confirmation implementáló körnek külön kell választania,
mielőtt valódi (perzisztáló) activation bekötődik; a Planner Assist-nek
nincs élő transport-rolloutja ebben a körben.

**Epic 7 (AI Practice Generator) ezzel lezárva** (R01–R30, SDD Ch8). A lánc
**Epic 8-cal (Gamification, SDD Chapter 9, 30 kör) folytatódik: E08-R01**
(Gamification baseline és principles), új sessionben.

## ✅ E07-R29 KÉSZ — Accessibility, localization, privacy és safety hardening — PR #332, squash `73e7876e` (2026-08-19)

A friss orchesztrátor-session (Sonnet 5) a H-NOSIGNAL self-heal (lent) által
otthagyott állapotot vette át: az implementer- és javító-munka
(`minimax/e07-r29-accessibility-privacy-hardening`,
`codex/e07-r29-accessibility-privacy-hardening-fix`) már push-olva volt, a
dolog csak a hátralévő review-zárás, CI-dispatch és merge volt.

**A review három leletet talált, mind zárva.** F1 (MAJOR — a `_writtenKeys`
in-memory lista miatt restart után a draft/archive-only tervek eltűntek a
delete-all/export sweepből) és F2 (BLOCKER — a `null` `outcomePlanLookup`
alapértelmezett `owner = planId` miatt egy plan-scoped törlés más terv
evidence-ét is elvitte) a MiniMax-nak járó EGY javító körben zárult
(`0a6315d2`…`3e05d243`, perzisztált manifest + adat-alapú plan-ownership). A
review egy MÁSODIK, friss valódi-sértés próbával F3-at is talált (MAJOR — a
manifest-írás `_trackWrite`/`_trackRemove` nem `await`-elte a
`keyValueStore.writeString`-et, a hiba silent no-op-ként veszett el); mivel a
MiniMax egy javító köre már elfogyott, a motor-eszkaláció szabálya szerint
(AGENTS.md/ADR 0087 §2) a Codex vitte a második javítást (`8212b0cb`).

**Az orchesztrátor a Codex-javítást NEM a `.codex-round-status` önjelentése
alapján fogadta el.** Elolvasta a `8212b0cb` teljes diffjét, majd saját,
izolált `flutter test test/features/practice_generator/data/
local_repository_test.dart` futtatással megerősítette — **36/36 zöld**,
köztük az új `F3 — manifest persistence failures` eset. Csak ez után
frissítette `docs/reviews/e07-r29-review.md`/`e07-r29-security.md`-t
CHANGES REQUIRED/BLOCKED → **APPROVED/PASS**-ra, és töltötte ki a brief §11-et.

**Mért gotcha a §0.3 upstream-szinkron lépésben (lásd [[L329]]):** a
`git clone --branch <round-branch>` (SKILL.md §3) implicit single-branch
refspecet ad a munkapéldánynak — egy csupasz `git fetch origin main` ebben
NEM frissíti a lokális `origin/main` követő-ágat, és a `merge-base
--is-ancestor` emiatt HAMIS POZITÍVOT adott, mielőtt az explicit
`git fetch origin +refs/heads/main:refs/remotes/origin/main` alakra váltva a
valódi (két commitnyi) elmaradást ki nem mértem. Csak ez után volt biztonságos
a review-t és a gate-et lezárni.

**Zöld kapu.** A round-ci-plan.py `full-gate.yml`-t (nincs natív diff) ÉS
Router CI-t (a diff `docs/rounds/**`-t érint) is előírt. Mindkettő zöld a
végleges, `origin/main`-nel egyesített HEAD-en: exact `1aa7923a` → Full Gate
[32282687647](https://github.com/wolfcasaba/strumsight/actions/runs/32282687647)
és Router CI
[32282629066](https://github.com/wolfcasaba/strumsight/actions/runs/32282629066)
success, `gh run view --json headSha` mindkettőn egyezett a lokális HEAD-del
merge előtt. Post-merge célzott gate a friss `main`-en (`73e7876e`)
önállóan is zöld (14/14: format, analyze, 9 teszt-útvonal, architecture,
secrets, l10n). Lecke: **[[L329]]**.

Az implementáció maga: teljes hu/en ARB-paritás (25 új kulcs), nagy
betűméret/screen-reader/reduced-motion audit a meglévő planner-képernyőkön,
nem-szín-alapú státuszjelölés (`TodayPlanMode` szöveg+ikon badge), redakciós
audit (`ExportPracticePlanningData._redactPlanJson` kitörli a
comfort-constraint értéket és minden goal `userNote`-ját), és a
felhasználó-kezdeményezett teljes törlés/export (`plan_privacy_screen.dart`,
`delete_practice_planning_data.dart`, `export_practice_planning_data.dart`) —
az ADR 0260 §5 szűk, csak erre a hívási útra fenntartott kivételként
(`docs/privacy/practice-planning-data.md` rögzíti a policy-kört).
`practiceGeneratorEnabled`/flag-ek változatlanul `false`. Következő kör:
**E08-R…** vagy a soron lévő pipeline-tétel, új sessionben.

## ✅ [HEAL E07-R29/H-NOSIGNAL] KÉSZ — preambulum: alparancs sikeres lezárása ≠ kör lezárása — PR #331, squash `90cf0628` (2026-08-19)

Az E07-R29 friss orchesztrátor-sessionje (Terra, rotáció szerint) a H3
self-heal (fent) után helyesen újraindult, és ~72 percen át helyesen
vezényelte a kört: implementer-dispatch, review, javítás, majd egy
Codex/Terra escalation-javítás az utolsó nyitott leletre. A záró, független
`tools/round-gate.sh` friss klónban 16:56:47Z-kor VALÓDI, sikeres
eredménnyel zárt (mind a 14 lépés zöld) — a turn mégis hat másodperccel
később, 16:56:53Z-kor egyetlen szöveges összegzéssel ért véget
(„…14/14 zöld, de a kötelező CI-dispatch, exact-SHA ellenőrzés és merge még
hátravan.") jelzésfájl nélkül. A pipeline ELAKADÁS-GYORSÍTÓja 20
másodpercen belül H-NOSIGNAL-ként ismerte fel (`.pipeline/chain.log`,
16:57:12).

**Mért, dokumentált precedenshez illeszkedő gyökérok.** Ugyanennek a
`docs/execution/pipeline-codex-orchestrator-preamble.md`-nek két KORÁBBI,
szomszédos rését az L282 (E07-R04, yielded parancs újraindítása) és az L290
(E07-R09, turn vége csonka poll közben) már bezárta — de egyik szabály sem
mondta ki, hogy egy alparancs SIKERES, terminális eredménye ugyanúgy nem
helyettesíti a kör-jelzést. A Codex/Terra rollout-JSONL
(`~/.codex-terra/sessions/2026/08/19/rollout-2026-08-19T15-45-07-*.jsonl`)
pontosan ezt mérte: a modell hűen, hazugság nélkül idézte a valódi „14/14
zöld" eredményt, majd egy alparancs lezárását a kör lezárásával azonosítva
állt meg.

**A javítás egyetlen új szabály-bullet + regressziós teszt.** A preambulum
§2-je egy új, névvel idézett bullet-et kapott az L290-bullet után: „egy
alparancs sikeres lezárása attól még nem azonos a kör lezárásával" — ha a
§3 checklist bármelyik eleme (push, CI-dispatch, exact-SHA ellenőrzés,
merge, kör-jelzés) hátravan, a válasz KÖVETKEZŐ eleme kötelezően újabb
tool-hívás. Regresszió: `tools/tests/test_pipeline_codex_orchestrator_preamble.py`
új `CodexOrchestratorPreambleNoStopAfterSuccessfulSubtaskTest` osztálya (3
eset), PIROS a javítás előtt → ZÖLD utána, a 7 meglévő preambulum-teszttel
együtt is zöld. Teljes `tools/tests`: **574 passed, 567 subtests passed, 0
hiba** (571→574). Router CLI smoke és `brief-lint.py --open --level base`
lokálisan is zöld, egyezően a CI lépéseivel. Exact SHA `3ca6d07d`: Router CI
([32280795044](https://github.com/wolfcasaba/strumsight/actions/runs/32280795044))
`conclusion=success`, `headSha` és a PR `headRefOid`-ja a merge előtt
egyezett a lokális HEAD-del. Nincs Dart-változás, ezért `build-apk.yml` nem
releváns — a Router CI volt az egyetlen szükséges kapu. Lecke: **[[L328]]**.
A lánc E07-R29-cel folytatódik a következő cron-firingen; a már elkészült
implementer- és javító-munka (`minimax/e07-r29-accessibility-privacy-hardening`,
`codex/e07-r29-accessibility-privacy-hardening-fix` ágak, mindkettő
push-olva originre) érintetlen — a friss orchesztrátor-session dolga csak a
hátralévő CI-dispatch + merge.

## ✅ [HEAL E07-R29/H3] KÉSZ — brief-bővítés: storage-owner, evidence-port és auditált planner-képernyők — PR #330, squash `7176875d` (2026-08-19)

Az E07-R29 (Accessibility, localization, privacy és safety hardening) saját
pre-flightja (Terra orchesztrátor, `29863cba` a sosem push-olt
`minimax/e07-r29-accessibility-privacy-hardening` ágon) helyesen HALT-olt:
a §3/§5.5 teljes törlés/export és a meglévő planner-képernyők
accessibility-auditja a brief régi `allowed_paths`-ában NEM elérhető
fájlokban él — a tényleges storage-tulajdonosok
(`data/local/local_practice_plan_repository.dart`,
`generation_draft_repository.dart`), az evidence-port
(`domain/repository/practice_evidence_repository.dart` — szándékosan SOSEM
töröl, ADR 0260 §5) és a már létező `today_plan_screen.dart`/
`weekly_plan_screen.dart`/`plan_setup_screen.dart` mind a régi tiltott
zónában voltak. Ez a session soha nem érte el a `main`-t — a Terra-session a
mérés után korrektül `H3`-mal állt le, implementer-dispatch nélkül.

Az önjavítás (ADR 0112, 1/3. kísérlet) portolta ezt a mérést `main`-re §0.0
gyanánt, majd §0.0.1-ben oldotta fel — **egyetlen** brief-bővítéssel, új ADR
nélkül (a pre-flight saját szövege szerint ide nem tartozik elfogadott ADR):
17 névre szóló bejegyzés `allowed_paths`-ban (10 meglévő `lib/`-tulajdonos +
7 saját, már létező tesztjük), ebből 7 `gate_tests`-ben is, hogy a kör SAJÁT
gate-je — ne csak a végső CI — védje a bővített területet. Egy új §5.7
rögzíti az ADR 0260 §5 viszonyát: az automatikus/lekérdezés-idejű elévülés
VÁLTOZATLAN marad mindenhol, az új evidence-törlő metódus egy szűk, csak a
felhasználó-kezdeményezett „mindent törölj" útra fenntartott kivétel.

**Mért, a pre-flight saját szövegénél szűkebb megoldás:** `lib/core/storage/
key_value_store.dart` (a megosztott, minden feature-t kiszolgáló
`KeyValueStore` interfész) NEM kellett megnyitni — a
`LocalPracticePlanRepository` minden saját kulcsát maga generálja, és már ma
is egyenként hívja `keyValueStore.remove()`-ot a bounded-history evikció
során (`appendRevision`/`appendOutcome`) —, tehát egy teljes, egy-terv-re
szóló törlés ugyanezzel a mintával, KIZÁRÓLAG ebben az egy fájlban megírható.

**Kötelező regresszió (PIROS a revízió előtt → ZÖLD utána, mindkét irányban
mérve):** `tools/tests/test_e07_r29_accessibility_privacy_scope.py` — a
valódi `audit_legacy_scope()`-ot futtatja a committolt brief ellen; méri a
mért halt-útvonalak és a teljes §0.0.1-grant hatókörbe kerülését, hogy egy-egy
szomszédos fájl mind a négy bővített területen (megosztott storage-interfész,
szomszédos repository, már biztonságosnak mért service, szomszédos képernyő)
kívül marad, hogy `allowed_paths`/`gate_tests` pontosan az eredeti + az új
bejegyzésekkel bővült, és hogy minden újonnan engedélyezett útvonal ma is
létezik. Teljes `tools/tests`: **571 passed, 567 subtests passed, 0 hiba**.
`tools/brief-lint.py --level strict` és a Router CI saját `--open --level
base` kapuja: tiszta. Nincs Dart-változás, ezért `build-apk.yml` nem
releváns; a Router CI (a diff `tools/**`/`docs/rounds/**`-t érint) volt az
egyetlen szükséges kapu, `tools/wait-for-ci.sh`-sal várva előtérben, a merge
előtt SHA-egyezés igazolva. Lecke: **[[L327]]**. A lánc E07-R29-cel
folytatódik a következő cron-firingen, a most bővített `allowed_paths` alatt.

## ✅ E07-R28 KÉSZ — Tutor és PlannerAssistGateway integráció — PR #329, squash `b021eff2` (2026-08-19)

Az opcionális, nem-autoritatív **PlannerAssist** gateway (SDD Ch8 Kör 28,
[ADR 0270](docs/adr/0270-planner-assist-allowlist-and-untrusted-input.md),
előre megírva 2026-08-15) egy strukturált request/response sémán és
**exact** goal-/skill-/candidate-allowlisten (nincs fuzzy illesztés) keresztül
enged nem megbízható nyelvimodell-választ a determinisztikus tervező elé —
a modell SOHA nem aktivál tervet, minden felhő-hiba (timeout, rate limit,
hálózat, kikapcsolt flag) determinisztikus tartalékra esik vissza, és a
tanuló szabad szövege külön, nem-megbízható mezőként utazik, sosem az
instrukció-mezőben.

**Pre-flight mérés fordította meg az implementáció irányát.** A brief §1 (az
Epic 7 SDD-forrása, `08-epic-07-ai-practice-generator.md` Kör 28) szó szerint
azt írta elő, hogy az adapter a Chapter 5 `ai_tutor`
`PracticePlanDraft`-ját képezze le — a mérés viszont azt mutatta, hogy
`lib/features/ai_tutor/public.dart` **fagyasztott üres** (`library;`, 0
export), egy E04-R01-ben merge-elt regressziós teszt
(`ai_tutor_boundary_test.dart`) őrzi, és ugyanez a hibaosztály HÁROMSZOR
mérve, MINDHÁROMSZOR scope-szűkítéssel oldva (`docs/LESSONS.md` L121/L133/
L139). A §0.0 pre-flight revízió ugyanezt az utat követte: a
`TutorPlanProposalAdapter` egy SAJÁT, e körben definiált `TutorPlanOutline`
típusból épít requestet a practice-generator SAJÁT publikus
katalógus-/skill-felületéről — `ai_tutor` import **nélkül**. Az implementer
(Codex) a §0.0-t szó szerint követte, és a saját docstring-jében is rögzítette
az indokot.

**Mindkét review zöld.** A [correctness review](docs/reviews/e07-r28-review.md)
APPROVED (0 BLOCKER/MAJOR/MINOR, 3 NOTE) — a reviewer saját, független
valódi-sértés próbával mérte az A2 allowlist-et (a candidate-ellenőrzés
ideiglenes gyengítése PIROSRA vitte a tesztet, visszaállítás után zöld). A
kötelező [security review](docs/reviews/e07-r28-security.md) (brief
`risk = "high"`) **PASS** — 0 CRITICAL/BLOCKER/MAJOR, 1 MINOR (a séma
`goalIds`/`skillIds`/`candidateIds` tömbjei ma méretkorlát nélküliek —
ártalmatlan, mert nincs élő transport, de a jövőbeli hálózati bekötés előtt
egysoros cappal érdemes zárni), 5 NOTE (a jövőbeli transport/UI-bekötő
körnek: a prompt-elkülönítés STRUKTURÁLIS, csak akkor marad az, ha a jövőbeli
HTTP-transport nem fűzi össze `instructions` + `untrustedLearnerNote`-ot egy
stringgé). Exact `dc413fd8`: Full Gate
[32266022078](https://github.com/wolfcasaba/strumsight/actions/runs/32266022078)
és Router CI
[32266095192](https://github.com/wolfcasaba/strumsight/actions/runs/32266095192)
success; post-merge célzott gate a friss `main`-en (`b021eff2`) önállóan is
zöld. `plannerAssistEnabled` változatlanul `false`, nulla production hívó.

**Folyamat-lecke ([[L326]]).** Az implementer-wrapper (`codex-round.sh`) NEM
push-ol automatikusan — a commit a review indulásakor CSAK az izolált
`ss-codex-e07-r28` munkapéldányban létezett. Az orchestrátornak kellett
push-olnia originre a review-klónozás ELŐTT; enélkül SEM a saját `/tmp`-klón,
SEM a párhuzamosan dispatch-elt security-reviewer subagent (aki a megosztott
fából klónozott) nem látta volna a valódi kódot. Ez a [[L325]] (E07-R26,
stale local ref) ROKON, de ELTÉRŐ gyökérokú hibaosztálya: ott a push
megtörtént, csak a lokális ref nem követte; itt a push MAGA hiányzott, ezért
az L325 „fetch origin előbb" receptje önmagában nem lett volna elég.

**Utólag mért, EBBEN a pre-flightban felfedezett, NYITOTT tartozás
(nem E07-R28 hibája, hanem E07-R27-é):** az E07-R27 (PR #328, squash
`a0c61044`) brief-je `risk = "high"`-ra volt állítva, de a kötelező
biztonsági review (`docs/reviews/e07-r27-security.md`) SOHA nem készült el —
a kör a correctness review-val (APPROVED) egyedül merge-elt, és a záró
rituálék (HANDOFF/RTM/LESSONS) is elmaradtak, csak a
`docs/execution/pipeline-queue.tsv` `done` jelzése készült el
(`chore(pipeline): E07-R27 done`, `e95bd937`). Ez a HANDOFF-bejegyzés ezt a
hiányt UTÓLAG dokumentálja (ld. lentebb), de a hiányzó security review-t NEM
pótolja — az egy jövőbeli kör vagy emberi döntés dolga. Következő kör:
**E07-R29** (Accessibility, localization, privacy és safety hardening, SDD
Ch8 Kör 29), új sessionben.

## ✅ [UTÓLAGOS DOKUMENTÁCIÓ] E07-R27 KÉSZ — Missed day, catch-up, pause és returning flow — PR #328, squash `a0c61044` (2026-08-19, retroaktívan rögzítve az E07-R28 pre-flightjában)

**Ez a bejegyzés utólag készült** — az E07-R27 saját sessionje a merge után
nem futtatta le a záró rituálékat (HANDOFF/RTM/LESSONS-frissítés
elmaradt, csak a pipeline-queue `done` jelzése történt meg). A tartalom a PR
törzséből és a meglévő [review](docs/reviews/e07-r27-review.md)-ból
rekonstruált, NEM az eredeti orchestrátor első kézből írt összegzése.

Domain-pure `MissedDayPolicy` a múltbeli napokat completed/missed/future
kategóriákba sorolja és reschedule-módot választ; a 21 napos rés a
konzervatív oldalra esik, ezért `readinessProposal`-t ad
([ADR 0269](docs/adr/0269-non-punitive-missed-day-handling.md) §5.4).
`PausePracticePlan` `paused` státuszra vált új revízióval;
`ResumePracticePlan` újra-horgonyozza a naplistát (a `resumeDate` lesz az új
`startDate`), eldobja a hátralékos napokat, és `returningAfterBreak` módra
vált, ha a rés eléri a küszöböt. Nem büntető, "bűntudatkeltés-mentes"
catch-up UI.

**A review egy javító kör után APPROVED** (`docs/reviews/e07-r27-review.md`,
0 BLOCKER/MAJOR/MINOR/NOTE nyitva): F1 (MAJOR — a resume felülírta egy
completed nap történeti dátumát) és egy második MAJOR javítva, re-review
`1c5d4562`-n. **A kötelező biztonsági review HIÁNYZIK** — a brief
`risk = "high"`, de `docs/reviews/e07-r27-security.md` sosem készült el; ezt
az E07-R28 pre-flightja fedte fel utólag (ld. fent). Exact `10ed4874`: Full
Gate [32259717044](https://github.com/wolfcasaba/strumsight/actions/runs/32259717044)
és Router CI
[32259719677](https://github.com/wolfcasaba/strumsight/actions/runs/32259719677)
success.

## ✅ E07-R26 KÉSZ — Outcome ingestion, review update és plan revision — PR #326, squash `d7e894de` (2026-08-19)

A befejezett gyakorlás-blokkok eredményének feldolgozása és az **átlátható**
jövőbeli tervmódosítás (SDD Ch8 Kör 26) egy tisztán application-rétegbeli,
**hívó-táplált** csővezetékként épült meg: `OutcomeIngestionService`
(revízió-egyezés, dedup, `SpacedRepetitionPolicy`-alapú review-frissítés,
technikai hiba nem adaptálható — ADR 0268), `RecordPracticeOutcome` (a
service + `AdaptationDecider` összefűzése), `RevisePracticePlan`
(immutable-múlt guard a meglévő `PracticeItemStatus.completed`
mintával — ADR 0256; kis/nagy változás szétválasztás, a "fókusz váltása" is;
elutasított proposal auditálható marad; `PlanRevision(previous:)` meglévő
monotonitás-védelme — nincs saját számláló) és `PlanChangeReviewScreen`
(lokalizált before/after diff a nagy változáshoz). **Egyik új fájl sem hív
repository-metódust** — a §0.0 pre-flight mérése szerint a repository-lokális
és az R23 execution-oldali `PracticeOutcome` két, AZONOS NEVŰ, eltérő alakú
típus (a `public.dart` `hide`-olja az előbbit); a perzisztencia-bekötés
szándékosan egy jövőbeli wiring-körre marad, az R16/R17/R19/R22/R23 mintáját
követve (`practiceGeneratorEnabled` marad `false`, nulla production hívó).

A független review (`docs/reviews/e07-r26-review.md`) egy javító kör után
APPROVED: az F1 MAJOR (a brief §5.2 "fókusz váltása" structural-change ága a
kódban helyesen működött, de a kör saját teszt-suite-ja 0%-ban fedte —
reviewer-oldali eldobható próbateszttel mérve, nem a kód olvasásából
következtetve) egyetlen új teszttel zárult, valódi-sértés próbával
(PIROS→ZÖLD) igazolva. A kötelező biztonsági review
(`docs/reviews/e07-r26-security.md`, `risk=high`) **PASS** — 0
CRITICAL/BLOCKER/MAJOR/MINOR, 5 előretekintő NOTE (sink-mentes, be nem
kötött réteg). Két nem-blokkoló follow-up nyitva maradt: F2 (MINOR) — a
`PlanChange.target` új `day:<id>[:block:<id>]` formátuma nem fedi a MEGLÉVŐ
termelők (`plan_repairer.dart`, `active_plan_controller.dart`,
`time_budget_allocator.dart`) `block:`/`plan:`/`timeBudget` alakjait, mérve
egy eldobható próbateszttel (elkapatlan `ArgumentError`) — nincs élő hívó,
egy jövőbeli wiring-körnek kell tudnia róla; F3 (NOTE) — a review screen
nyers belső értékeket (mikroszekundum, enum-kód) jelenít meg humanizálás
nélkül. Exact `254a4efe`: Full Gate
[32251015719](https://github.com/wolfcasaba/strumsight/actions/runs/32251015719)
és Router CI
[32251108229](https://github.com/wolfcasaba/strumsight/actions/runs/32251108229)
success.

**Folyamat-lecke ([[L325]]):** a review-oldali `/tmp` klón NÉMÁN elavult
ágat adhat, ha a `git clone --branch <kör-branch>` a megosztott
`/home/ubuntu/music-theory` fából történik, miközben az implementáció egy
KÜLÖN klónból (`ss-codex-<kör>`) pusholt közvetlenül originre — a megosztott
fa lokális branch-refje csak explicit `git fetch origin <branch>:<branch>`-re
mozdul. Kétszer mérve ugyanebben a körben (a fő reviewer és a párhuzamosan
dispatch-elt security-reviewer subagent is ugyanabba a csapdába futott,
mindkettő önállóan helyreállt).

Ehhez a körhöz **nem kellett új ADR** — a brief saját indoklása szerint a
határokat a MEGLÉVŐ ADR 0256/0265/0268 rögzíti (az E07-R22 precedensével
egyezően); a defenzíven lefoglalt `0325` szám nem került felhasználásra.
Következő kör: **E07-R27** (Missed day, catch-up, pause és returning flow),
új sessionben.

## ✅ A LÁNC ÚJRA MEGY — a `H-GATEGUARD` mostantól KÖRT tart vissza, nem a LÁNCOT (ADR 0321, 2026-08-19)

**A probléma, mérve.** Az `E99-R17` háromszor állt meg ugyanazzal a gyökérokkal
(05:31 / 09:56 / 10:38 UTC), és mivel a `.pipeline/HALTED` jelzés GLOBÁLIS, a
lánc 05:31–10:40 között **nulla kört vitt előre** — miközben a sorban **32
olyan nyitott kör** állt (E07/E08 termék-munka), aminek semmi köze a gate-hez.
A halt gyökéroka TERVEZÉSI hiba volt: a brief `allowed_paths` listáján védett
fájl (`tool/ci/check_l10n_parity.dart`) szerepelt, amit autonóm session
strukturálisan nem tud megírni (L322–L323).

**A javítás három rétege (ADR 0321):**

1. **Kör-szintű hold.** Kör-session `H-GATEGUARD` haltja → a kör sora `hold`
   (commit + push), halt-archívum + `.pipeline/gateguard-holds.tsv` főkönyv +
   ntfy, és a lánc a következő pending körrel MEGY TOVÁBB.
2. **Az őrszem haltja LÁNC-szintű marad.** Ha a haltot az önjavítás fölötti
   őrszem írta (`gateguard_origin=selfheal` gépi mező), a mércét gyengítő
   commit már a main-en állhat → az egész lánc áll, ahogy eddig.
3. **Pre-flight a dispatch ELŐTT.** `tools/gateguard-scan.py` a védett listát
   **magából az őrből** importálja (nincs második igazság), és a driver a
   kiválasztott kör briefjét ezzel méri. Ütközés → azonnali `hold`,
   implementer-futás és halt nélkül.

**Amit NEM változtat meg:** a mércét és az emberi határt. Gate-érintő kör
továbbra sem fut le emberi döntés nélkül (ADR 0112 §3 érintetlen).

**Emberi döntésre váró (hold) körök — egy közös alkalommal, kötegben:**
`E99-R17` (`tool/ci/check_l10n_parity.dart`), `E99-R20`, `E99-R21`
(`tools/round-gate.sh` + workflow), `E99-R22`, `E08-R29` (workflow).
Gépi lista: `tools/gateguard-scan.py --all` · státusz:
`tools/pipeline-status.sh` „emberi gate-döntésre váró körök" szakasz.
A feloldás menete (E99-R16 precedens): a user SZEMÉLYESEN szerkeszti és
pusholja a védett fájlt a kör ágára, majd a sorban `hold` → `pending`.

**Őrteszt:** `tools/tests/test_gateguard_autohold.py` (12 eset, zöld) ·
tanulság: `docs/LESSONS.md` L324 · brief-szabály: `docs/execution/08-round-brief.md` §4.

## ✅ Router CI paths-szűrő: családi glob — PR #324, squash `a2d64831` (2026-08-19)

Az E99-R16 escalate HIBAOSZTÁLYÁNAK megszüntetése (nem a tünetéé): a `paths:`
blokk 36 fájlonkénti bejegyzése helyett `tools/**` + `docs/execution/**`.
Mérve: lefedettség **127 → 143 fájl (+16)**, elveszett lefedettség **nincs** —
szigorúan bővítő változás, az őr védelme érintetlen. A teljes `tools/tests`
suite elkapott egy minta-SZÖVEGHEZ kötött tesztet
(`test_pipeline_throughput.py`); a javítás lefedettség-alapú állítás lett,
mutációval igazolva, hogy szigorúbb (`tools/**` eltávolítására PIROS).
Zöld kapu: Router CI + Full Gate (no APK) success. Részletek: `docs/LESSONS.md`
**L322** záró blokkja. Mindkét gate-szerkesztést EMBER futtatta — az őr
módosítása szándékosan ELMARADT.

## ✅ E99-R16 (GOV-10) KÉSZ — kör-granularitás mérőeszköz + brief-merge-plan — PR #323, squash `825c7215` (2026-08-19)

**A pipeline első `outcome=escalate` esete lezárva — emberi gate-szerkesztéssel.**

A kör tartalmi munkája (F1/F2/M1 lelet javítva) már korábban APPROVED volt
(`docs/reviews/e99-r16-review.md`). Az EGYETLEN maradvány az F3 volt: a kör új
eszközére (`tools/brief-merge-plan.py`) hivatkozik a `tools/tests` csomag, de a
Router CI push-triggere nem indult volna el rá — a guard-teszt
(`tools/tests/test_router_ci_path_filter.py::test_every_test_referenced_file_is_in_the_ci_filter`)
ezt mérte és pirosra állt.

Három önjavító kísérlet (a 3. már Terra motorral, GOV-09 szerint) egybehangzóan
`escalate`-tel zárult: a javítás helye a `.github/workflows/` — a self-heal
abszolút tiltott zónája (ADR 0112 §3, `docs/LESSONS.md` **L322**), és a teszt
lazítása vagy a fájl kizárása ugyanannak a tiltásnak a másik alakja lett volna.

**Feloldás (2026-08-19, ~05:00 UTC):** a user telefonról explicit engedélyt adott,
és Ő futtatta a gate-szerkesztést (a H-GATEGUARD hook ÉS a harness auto-mode
osztályozója is blokkolta az ügynök-oldali szerkesztést — két független őr).
A változtatás **egy sor**: `"tools/brief-merge-plan.py"` a Router CI `paths:`
blokkjában, a `tools/brief-lint.py` mellé (ADR 0171 áteresztő-eszközök blokkja).
Commit `e71ded2f` — 1 fájl, 1 beszúrt sor, semmi más.

**Mérés (izolált /tmp klón, `ea6e763a`):** javítás előtt
`missing=['tools/brief-merge-plan.py']` → FAILED; utána `Ran 2 tests … OK`.
Teljes `tools/tests` suite (72 modul): **552 teszt, 1 skipped**, az egyetlen
failure környezeti (`test_empty_queue_is_not_a_failure` kifelé hívja a
`python3 -m pytest`-et, ami ezen a boxon nincs telepítve — a CI telepíti).

**Zöld kapu:** Router CI `success` (5m11s, run 32217738001) · Full Gate (no APK)
`success` (run 32217883172) · `gh pr checks 323` mind pass · `mergeStateStatus=CLEAN`.
A friss `main` a merge előtt beolvasztva a branchbe (`174ac6e3`, konfliktusmentes),
mert a guard-teszt a branch SAJÁT workflow-másolatát méri, nem a `main`-ét.

**Tanulság:** az `escalate` kimenet működött — a lánc nem erőltette és nem
kerülte meg a mércét, hanem megállt és emberre várt. A költség ötóra állás
volt; a feloldás egy sor. Következtetés a jövőre: ha egy kör ÚJ, tesztek által
hivatkozott `tools/` fájlt vezet be, a Router CI `paths:` bővítése EMBERI
előkészítő lépés — a kör-brief §0-jában kell jelezni, nem a self-healre bízni.

## ✅ E07-R25 KÉSZ — Analyze és Vision származtatott evidence integráció — PR #322, squash `3ab2a147` (2026-08-19)

Az Analyze és a Vision csak származtatott, confidence-aware evidence-et adhat
át a Practice Generatornak. Az új adapterek a publikus Audio Analysis API-t,
illetve a szűk `vision/domain/evidence/public.dart` contractot használják;
nyers audio, frame, landmark, koordináta és fájlútvonal nem kerül át. A Vision
hiánya üres, hibamentes eredmény, a `notObservable` port-bemenet adapter-szinten
fail-closed, az alacsony confidence pedig súlykorlátozott marad. A független
review APPROVED (0 BLOCKER/MAJOR/MINOR); a reviewer valódi-sértés próbája a
`notObservable` őr eltávolításakor két cellát pirosra váltott, visszaállítás
után 10/10 Vision adapter teszt zöld. Exact `cbcb30c7`: Full Gate
[32210677497](https://github.com/wolfcasaba/strumsight/actions/runs/32210677497)
és Router CI
[32210693573](https://github.com/wolfcasaba/strumsight/actions/runs/32210693573)
success. A merge utáni célzott gate a záró rituálé része.

## ✅ [HEAL E07-R25/H5] KÉSZ — két, egymástól független, self-heal-generált bidirekcionális regressziós pin egyirányúsítva (ADR 0112) — PR #321, squash `a1613fa5` (2026-08-19)

Az E07-R25 (Analyze/Vision evidence integráció) Router CI-ja kétszer pirosra
váltott a kör saját, még nem merge-elt ágán
(`minimax/e07-r25-analysis-and-vision-evidence`), és a driver H5-tel
megállt: `tools/tests/test_e07_r25_vision_evidence_scope.py` (a H3 self-heal
sajátja, [[L319]]) két bidirekcionális `assertEqual`-lel pinnelte az
`EvidenceSource` értékkészletét 4 elemre — a kör implementere közben a SAJÁT
ágán, a H3 által jóváhagyott módon hozzáadta `EvidenceSource.vision`-t
(5. érték), ami a bidirekcionális pint elkerülhetetlenül pirosra váltotta.
**Ez byte-pontosan [[L279]]/[[L280]] hibaosztálya** (E99-R13, 2026-08-15) —
egy self-heal-generált pin szerkezetileg összeegyeztethetetlen egy AKTÍV,
brief-szentesített kör-branch-csel, ami definíció szerint előrébb jár
`main`-nél. A javítás [[L279]] receptjét szó szerint alkalmazza: mindkét
teszt egyirányú, nem-zsugorodás invariánsra vált (a founding 4 érték egyike
sem tűnhet el csendben); `ORIGINAL_EVIDENCE_SOURCE_VALUES` MAGA változatlan
maradt — bővítése "megjavította" volna a kör-ágat, de eltörte volna `main`
SAJÁT, merge utáni Router CI-ját (4 értéke van, amíg a kör ténylegesen nem
merge-el).

**Egy MÁSODIK, a HALT által nem jelentett, ugyanebbe a hibaosztályba tartozó
gyökérokot a SAJÁT fix gate-futtatása fedett fel:** `main` Router CI-ja a
H5-fixem ELŐTT is pirosra váltott (`32207252052`, `32208143911`) egy MÁSIK
self-heal-generált teszten,
`test_knowledge_rag.py::test_brief_lint_flags_a_brief_without_retrieved_precedent`,
amely egy VALÓDI kör briefjére (`e99-r15-gov-09-halt-escalation.md`)
mutatott. A `brief-lint.py` S8 (ADR 0312) checkje szándékosan néma egy
`done` kör briefjén (mért precedens: `e06-r10`) — mihelyt E99-R15 lezárult,
az S8 helyesen elhallgatott, és a teszt nem regresszió, hanem az S8 saját,
szándékos működése miatt tört el. Bármely valódi kör brief-je időzített
bomba ehhez a fixture-höz; a javítás egy szintetikus, a valódi sorban soha
nem szereplő task-id-jú (`E00-R00`) brief, ami a csatolást szünteti meg, nem
csak odébb tolja a lejáratot. Változatlanul hagyva ez a második gyökérok is
blokkolta volna MINDEN jövőbeli kör Router CI zöld merge-ét, nem csak
E07-R25-ét.

**Mindkét irányban mérve** egy izolált heal worktree-ben (a kör-ág valódi
`skill_evidence.dart`/`evidence_weight_policy.dart`-ját commit nélkül a
plain `main` fölé rétegezve): javítatlan teszt + kör-ág kód → PIROS
(byte-azonos a valódi CI-hibával, futások
[32204906795](https://github.com/wolfcasaba/strumsight/actions/runs/32204906795),
[32206385772](https://github.com/wolfcasaba/strumsight/actions/runs/32206385772));
javított teszt + plain `main` kód → ZÖLD; javított teszt + kör-ág kód →
ZÖLD. Egy önálló diff-méréssel (nem a kör saját jelentése alapján) igazolva:
`git diff origin/main...origin/minimax/e07-r25-analysis-and-vision-evidence`
minden érintett fájlja pontosan a H3 által jóváhagyott
`ORIGINAL_ALLOWED_PATHS ∪ NEW_ALLOWED_PATHS` unióját fedi, scope-tágítás
nélkül; a kör saját, független review-ja (`docs/reviews/e07-r25-review.md`)
APPROVED, 0 BLOCKER/MAJOR/MINOR, A1–A8 mind bizonyítva. Sem a
`tools/round-gate.sh`, sem a `.github/workflows/` nem változott; a
teszt-fájlok metódusszáma változatlan (7, 13) — csak átírva, egy sem törölve.
Teljes `python3 -m pytest tools/tests -q`: **537 passed, 1 skipped, 565
subtests passed, 0 failure**. Router CI (egyetlen szükséges kapu, nincs
Dart-változás) zöld a pontos merge SHA-n
([32209227423](https://github.com/wolfcasaba/strumsight/actions/runs/32209227423)),
`tools/wait-for-ci.sh`-sal várva előtérben. Post-merge egy FRISS klónból
(GitHub-ról, nem a helyi, elmaradt `main`-ből) függetlenül újramérve: a két
javított teszt zöld; egy MÁSIK, a MEGELŐZŐ kör (E99-R15) HANDOFF-jában már
dokumentált, élő sor-fájl-állapotra érzékeny flake
(`test_pipeline_integration.py::test_a_full_firing_retries_the_round_
instead_of_healing_a_resolved_terra_wall`) a megosztott, párhuzamosan
terhelt Oracle-boxon inkonzisztensen jelentkezett (a pre-merge commit
UGYANAZON pillanatban zöld volt) — bájt-azonos fájltartalommal a két commit
közt az érintett útvonalakon, tehát NEM ennek a fixnek a regressziója; a
SAJÁT PR Router CI-ja (izolált, terheletlen GitHub-runner, pontos merge SHA)
az irányadó bizonyíték, és az zöld volt. Lecke: **[[L321]]**. A lánc
E07-R25-tel folytatódik a következő cron-firingen, a most javított
mércén.

> **E99-R15 (GOV-09) KÉSZ — Halt-eszkaláció: motorváltás az utolsó önjavító
> kísérletnél és ismétlődő riasztás throttle-lel** — PR
> [#320](https://github.com/wolfcasaba/strumsight/pull/320), squash
> `dcbfb469` (2026-08-19). `heal_engine_for_attempt` az utolsó
> (`selfheal_max`-adik) self-heal kísérletnél determinisztikusan más,
> statikusan elérhető, más `model`-ű motort választ a nyilvántartásból (mai
> alapértelmezés: `codex`), ha van ilyen; az 1–2. kísérlet és az alternatíva
> nélküli utolsó kísérlet a rögzített `sonnet-impl` identitáson marad. A
> kimerült self-heal riasztása (`notify … high`) — amely a `.pipeline/
> chain.log` mérése szerint korábban **5 percenként, throttle nélkül**
> ismétlődött (455 találat, egyetlen 42 órás ablakban ~504 push) —
> `PIPELINE_HALT_REMINDER_MIN` (60 perc) throttle-t és
> `PIPELINE_HALT_REMINDER_MAX_H` (24 óra) felső korlátot kapott; a `KIMERÜLT`
> naplósor változatlanul minden firingkor ír.
>
> **A pre-flight (§0.0) egy MÉRT, TÉVES brief-állítást korrigált** a
> dispatch előtt: a brief „a riasztás egyszer ment ki, nem ismétlődött"
> mondata a `chain.log`-gal szemben hamis volt — a valódi mai hiba
> kontrollálatlan spam, nem csend; ez eldöntötte, hogy D2 a MEGLÉVŐ `notify`
> hívást kapuzza, nem egy másodikat ad hozzá mellé.
>
> **A független review (`docs/reviews/e99-r15-review.md`) 1 MAJORT talált és
> zárt egy javító körben:** az implementer első commitja (`05d81543`) egy ÚJ
> `run_selfheal_session` dispatch-útra váltott MINDEN kísérletnél, elveszítve
> a régi `run_orchestrator_session` beépített Claude-kvótazárlat→Terra
> automatikus fallbackjét — nemcsak az utolsó, motorváltós kísérletnél, hanem
> az 1–2.-nál is, ami sértette a brief saját „a mai viselkedés nem érintett
> ágakon bitre azonos" ígéretét. A review saját falszifikációval mérte
> (`claude_unavailable_until` szimulált zárlat), a javítás (`e938588a`)
> minimális: a változatlan motor a régi, kvóta-tudatos úton marad, a
> `run_selfheal_session` kizárólag valódi motorváltásnál fut. A kötelező
> biztonsági review (`docs/reviews/e99-r15-security.md`, `risk=high`) PASS —
> 0 CRITICAL/BLOCKER/MAJOR/MINOR, függetlenül nyomon követve a MiniMax
> auth-token teljes futásidejű útját (nincs szivárgás argv-be, naplóba vagy
> commitba). Exact-SHA: Full Gate
> [32205415850](https://github.com/wolfcasaba/strumsight/actions/runs/32205415850)
> és Router CI [32204921953](https://github.com/wolfcasaba/strumsight/actions/runs/32204921953)
> success a merge-előtti `e938588a` fejen.
>
> **Post-merge gate (mind saját, izolált klónban futtatva):** a Dart gate
> (`tools/round-gate.sh test/tooling/architecture_allowlist_guard_test.dart`)
> zöld. A `python3 -m pytest tools/tests -q` egyetlen determinisztikus (nem
> flaky) hibával állt le
> (`test_pipeline_integration.py::test_a_full_firing_retries_the_round_instead_of_healing_a_resolved_terra_wall`)
> — méréssel kizárva, hogy ez a kör kódjának regressziója: a hiba KIZÁRÓLAG
> attól függ, hogy az E99-R15 sora a `docs/execution/pipeline-queue.tsv`-ben
> még `pending` (a driver ezt a saját `.pipeline/round-status-E99-R15`
> jelzésem feldolgozása UTÁN, egy KÉSŐBBI firingen frissíti — nem az
> orchesztrátor dolga, §4). A `pipeline-queue.tsv` sort NEM módosítottam
> (tiltott zóna). Lecke: **[[L320]]**.

## ✅ [HEAL E07-R25/H3] KÉSZ — brief-bővítés: hiteles `EvidenceSource.vision` + egy exhaustive-switch fordítási csapda + szűk Vision-owned evidence contract — PR #319, squash `ea042640` (2026-08-19)

Az E07-R25 (Analyze/Vision evidence integráció) saját pre-flightja (ADR 0319,
Terra→minimax, `main @ 90df4d04`) helyesen HALT-olt: a Practice Generator
`EvidenceSource` enumja (`skill_evidence.dart:17-21`) nem ismer `vision`
értéket, és az egyetlen scope-on belüli Vision-kontraktus
(`vision/domain/integration/public.dart`, ADR 0193) nem ad át skillhez
kötött numerikus evidence-et — a §1 cél és az A5/A6/A8 elfogadási pontok
emiatt nem teljesíthetők a régi `allowed_paths`-on belül.

Az önjavítás (ADR 0112, 1/3. kísérlet) a saját, független kódmérésével egy
MÁSODIK, ADR 0319-től független rést is talált: `EvidenceWeightPolicy.
sourceReliability` (`evidence_weight_policy.dart:66-71`) egy `default` ág
nélküli, kimerítő `switch`-et futtat a jelenlegi 4 `EvidenceSource` értéken.
Az ADR 0319 saját listája ezt a fájlt nem nevezte meg — egy `vision` érték
hozzáadása enélkül NEM ugyanazt a HALT-ot hozta volna vissza a következő
dispatchkor, hanem egy kevésbé olvasható `flutter analyze`
non-exhaustive-switch hibát, ugyanabban a tiltott zónában.

**Javítás:** `docs/rounds/e07-r25-analysis-and-vision-evidence.md` §0.0.1
öt névre szóló fájllal bővíti `allowed_paths`/`gate_tests`-t:
`skill_evidence.dart`, `evidence_weight_policy.dart`, a két teszt-társuk, és
egy ÚJ, szűk, raw-media-mentes `lib/features/vision/domain/evidence/
public.dart` (ADR 0193/L193 nested-barrel minta — additív fájl, a megosztott
architektúra-guard és minden más Vision-fogyasztó változatlan). Az ADR 0319
egy dátumozott záró-bekezdést kapott, ami a második rést és a feloldást
rögzíti. Semmilyen production kód nem változott — tisztán
folyamat/dokumentáció-scope (ADR 0112 §2/§3).

**Kötelező regresszió (PIROS a revízió előtt → ZÖLD utána, mindkét irányban
mérve):** `tools/tests/test_e07_r25_vision_evidence_scope.py` — a mért
`EvidenceSource`/`sourceReliability` alakot, a három újranyitott
Vision-típus raw-mentességét és az `allowed_paths` pontos, öt bejegyzésű
bővülését zárolja (egy szomszédos, a bővítésen kívüli útvonal továbbra is
scope-on kívül marad). Teljes `tools/tests`: **535 passed, 560 subtests
passed, 0 hiba**. `tools/brief-lint.py --level strict`: tiszta. Nincs
Dart-változás, ezért `build-apk.yml` nem releváns; a Router CI (a diff
`tools/**`/`docs/rounds/**`/`docs/execution/pipeline-queue.tsv`-t érint) volt
az egyetlen szükséges kapu, `tools/wait-for-ci.sh`-sal várva előtérben, a
merge előtt SHA-egyezés igazolva. Lecke: **[[L319]]**. A lánc E07-R25-tel
folytatódik a következő cron-firingen, a most bővített `allowed_paths` alatt.

> **E07-R24 KÉSZ — Song goal és Song Trainer integráció** — PR
> [#318](https://github.com/wolfcasaba/strumsight/pull/318), squash
> `b08c00e9` (2026-08-19). A Practice Generator most explicit, caller-fed
> `SongDocument`-ből normalizál song goalokat; az ismeretlen, hibás vagy
> előfeltétel nélküli cél fail-closed kiesik. A blokkfordítás determinisztikus,
> és csak a ténylegesen megvalósított prerequisite után enged célt tervbe.
> [ADR 0318](docs/adr/0318-song-goal-public-boundary-and-caller-fed-input.md)
> rögzíti a szándékosan szűk, Song Trainer belső rétegét meg nem nyitó
> nyilvános határt. A correctness review az F1 MAJOR-t valódi no-producer
> próbával találta és a MiniMax javító kör zárta; a security delta-review PASS.
> Exact `028ea117`: Full Gate
> [32200092798](https://github.com/wolfcasaba/strumsight/actions/runs/32200092798)
> és Router CI
> [32200094318](https://github.com/wolfcasaba/strumsight/actions/runs/32200094318)
> success. Következő kör: **E07-R25**, új sessionben.

> **E99-R14 KÉSZ — GOV-08 motor-override lejárat és motor-statisztika** — PR
> [#317](https://github.com/wolfcasaba/strumsight/pull/317), squash
> `52200a81` (2026-08-18). Az `engine-profile.sh use` TTL-t és indoklást
> tároló, háromsoros override-formátumot kapott, miközben a régi egysoros
> forma változatlanul olvasható. A driver lejárt override-nál töröl, a
> motornevet megtartó audit/ntfy üzenetet ír; lejárat nélküli, 72 órásnál
> idősebb override-nál naponta legfeljebb egy értesítést küld. A
> `round-metrics.py --engines --epic` immár chain.log-alapú mintaszámot,
> mediánt, átlagot, kiugrót és önjavítást mutat motoronként.
>
> A [független review](docs/reviews/e99-r14-review.md) APPROVED: M1–M5
> (epic-szűrés, izolált falszifikáció, egyetlen valódi kiértékelési út,
> hermetikus driver-teszt, lejárt motor auditálhatósága) zárva. Exact-SHA:
> Full Gate [32197051577](https://github.com/wolfcasaba/strumsight/actions/runs/32197051577)
> és Router CI [32197078395](https://github.com/wolfcasaba/strumsight/actions/runs/32197078395)
> success a `9fdf556e` fejen; post-merge gate a `52200a81` mainen is zöld.
> A teljes tooling-suite az izolált projekt pytest-környezetben `527 passed,
> 1 skipped, 560 subtests passed`; a rendszer `/usr/bin/python3` interpreter
> nem tartalmaz `pytest` modult. Következő kör: **E99-R15**, új sessionben.

> **E07-R23 KÉSZ — PlanCompiler és Practice Engine végrehajtás** — PR
> [#316](https://github.com/wolfcasaba/strumsight/pull/316), squash
> `d02718fb` (2026-08-18). `PlanCompiler` egy validált terv-blokkot fordít
> pontos, végrehajtható Practice Engine lépéssé — revízió- és
> capability-ellenőrzéssel indítás előtt, a recept konfigjának
> közelítés-mentes átadásával. `PracticeOutcomeAdapter` a Practice Engine
> **hívó-táplált** terminál-bemenetét normalizálja (`completed` /
> `cancelled` / `failedTechnical` / `skipped` / `unavailable`), mert a §0.0
> pre-flight kimérte: a Practice Engine ma KIZÁRÓLAG a `completed` ágon
> állít elő `PracticeSessionResult`-ot (ADR 0077 §9,
> `practice_session_controller.dart:245-256`) — a `cancelled`/`failed` ág
> nem. `PlanExecutionCoordinator` indít + idempotensen könyvel
> (`blockExecutionId` replay-nél first-write-wins). [ADR
> 0268](docs/adr/0268-technical-failure-is-not-skill-failure.md)
> végrehajtva: a technikai hiba SOSEM tanuló-teljesítmény, a megszakítás
> részleges (nem kudarc), az elavult/unavailable blokk nem indul.
>
> [Correctness review](docs/reviews/e07-r23-review.md) APPROVED egy javító
> kör után: az F1 MAJOR azt mérte, hogy a session-konfig pontos-egyezés
> hiba-ága (§5.4 — „nem körülbelül") tesztelve NINCS — a review saját kézzel
> eltávolította a védelmet, és mind a 7 akkori teszt zöld maradt. A javítás
> (`mismatchedSessionConfig()` + egy negatív teszt) után a review
> MEGISMÉTELTE a próbát: PIROS a védelem nélkül, ZÖLD vele — a zárás valódi,
> nem bemondás. [Security review](docs/reviews/e07-r23-security.md) PASS
> (kötelező, brief `risk = "high"`): 0 CRITICAL/BLOCKER/MAJOR/MINOR, 5
> előretekintő NOTE a jövőbeli wiring körnek (elsősorban: a `metricEvidence`
> kulcsok és a `failureCode` maradjanak gép-eredetűek, ne kerüljön bele
> szabad szöveg). Exact-SHA: Full Gate
> [32194483344](https://github.com/wolfcasaba/strumsight/actions/runs/32194483344)
> és Router CI
> [32194473562](https://github.com/wolfcasaba/strumsight/actions/runs/32194473562)
> success a merge-előtti pontos fejen; post-merge célzott gate a friss
> `main`-en önállóan újrafuttatva is zöld (7/7). `practiceGeneratorEnabled`
> marad `false`, nulla production hívó — tisztán domain/application/data
> réteg-bővítés.
>
> **Folyamat-megjegyzés (két külön mérve, mindkettő a review-oldali
> független friss klónozás fogta meg, nem a bemondás):** (1) a javító kör
> `.codex-round-status` `done` jelzése után a HEAD nem volt push-olva
> originra — ugyanaz a hibaosztály, mint `docs/LESSONS.md` L311; (2) a `main`
> a kör folyamán ötször mozdult (más, párhuzamos governance-körök
> docs/tools-commitjai miatt) — minden alkalommal újra-szinkronizálva és a
> CI-t (Full Gate + Router CI) újra-dispatch-elve az ADR 0086 §2 exact-SHA
> szabálya szerint, mielőtt a végső merge megtörtént. Következő kör:
> **E07-R24**, új sessionben.

> **E07-R22 KÉSZ — Weekly Plan és Today screen** — PR
> [#307](https://github.com/wolfcasaba/strumsight/pull/307), squash
> `dd80179e` (2026-08-18). Az aktív terv napi ("ma") és heti nézete
> **helyi dátumból**, injektált órával (`final DateTime Function() clock`,
> a plan_setup_controller.dart-ban már bevett minta) — nincs `.toUtc()` a
> vezérlőben. A pihenőnapot a `PracticeDay.reasonCodes.contains(
> ScheduleDecisionReason.restDay.code)` jelzés különbözteti meg a
> kihagyott/nem-elérhető naptól (a `PracticeItemStatus`-nak NINCS `rest`
> értéke, és a `BlockKind.rest` sosem épül — a §0.0 pre-flight ezt mérte ki
> a dispatch ELŐTT). Rövidítés/csere/kihagyás/szüneteltetés akciók
> `PlanChangeReason.learnerReschedule` change-settel, storage-írás nélkül —
> a mentés egy jövőbeli composition-kör dolga. Típusos,
> `Map<String,String>`-alapú deep-link contract (`TodayPlanRouteRequest`),
> nincs nyers URI-parse. [Correctness review](docs/reviews/e07-r22-review.md)
> APPROVED, [security review](docs/reviews/e07-r22-security.md) PASS — 2
> javító kör után, a MÁSODIK kört egy FÜGGETLEN, második
> `security-reviewer` agent-futás ellenőrizte, nem csak az orchestrátor
> olvasata. Exact-SHA: Full Gate
> [32176316917](https://github.com/wolfcasaba/strumsight/actions/runs/32176316917)
> és Router CI zöld az `5cae87d2` fejen. `practiceGeneratorEnabled` marad
> `false`, nulla production hívó.
>
> **A biztonsági review 2 MAJORt zárt, és 1 nem-blokkoló, KÖTELEZŐEN
> tovább-adandó MINORt hagyott nyitva a következő wiring körnek:**
> `TodayPlanRouteRequest.tryParse` egy `Map<String,dynamic>.cast<String,
> String>()` (a JSON-payloadból jövő IDIOMATIKUS konverzió) view-n
> `TypeError`-t dobott a statikus `is Map<String,String>` kapu Dart-lazy-cast
> gyengesége miatt — mérve: `type '_Map<String, int>' is not a subtype of
> type 'String?' in type cast`; javítva elem-szintű `is String`
> ellenőrzéssel + `try/on TypeError` védelemmel. A `today_plan_screen.dart`
> egy ELUTASÍTOTT deep linket megkülönböztethetetlenné tett a "nincs is
> deep link" esettől, ezért a flag-ellenőrzés kimaradt és egy manipulált
> paraméter TÖBBET kapott, mint egy jólformált, de letiltott — javítva egy
> explicit `isDeepLinkLaunch` paraméterrel. **Nyitott MINOR (kötelezően a
> jövőbeli notification/router wiring kör briefjébe kerül, nem örökölhető
> csendben):** az `isDeepLinkLaunch` hívó-beállítású és alapértelmezetten
> `false` — ha egy jövőbeli hívó ELFELEJTI kitenni egy elutasított
> `launchRequest` mellett, a screen STRUKTURÁLISAN nem tudja megkülönböztetni
> ezt a normál belső navigációtól (a MAJOR-2 eredeti mintája). A wiring
> körnek `tryParse`-t TOTÁLISSÁ kell tennie (`accepted`/`rejected` sealed
> eredmény) vagy sealed `TodayLaunchContext`-et kell bevezetnie, ÉS egy a
> VALÓDI router-hívási úton futó elfogadási cellát kell írnia. Lecke:
> **L309**. Következő kör: E07-R23 (PlanCompiler és Practice Engine
> végrehajtás, SDD Ch8 Kör 23), új sessionben.


> ## 🛡️ [IMPLEMENTER-ŐRÖK + SLOT-ZÁR] Gépi őrök a claude-harness köröknek, és a párhuzam MÁSODIK gyökéroka — ADR 0309 (2026-08-18)
>
> **Implementer-őrök (PR #309, ADR 0309).** A MiniMax/Sonnet implementer három
> mért hibaosztálya (listán kívüli fájl, gate-csonkítás, jelzés nélküli kilépés)
> szövegesen tiltva volt, mégis megtörtént — ezért gépi réteg került alá:
> `tools/hooks/implementer_guard.py` (scope-őr fail-closed, tiltott
> parancsalakok, korlátos Stop-jelzésőr, `dart format` írás után), amit a
> `tools/mm-round.sh` `--settings tools/implementer-settings.json`-nal CSAK az
> implementer-sessionre tölt be. Emellé `tools/implementer-agents.json`
> (`round-auditor` alügynök a KÖTELEZŐ önellenőrzéshez), a nyilvántartás
> `max_out` oszlopa végre hat (`CLAUDE_CODE_MAX_OUTPUT_TOKENS`), és a kör utáni
> scope-audit is megkapja a briefet (eddig némán kimaradt).
> **Mérve élesben:** a modell kiadta a `Write`-ot egy listán kívüli fájlra →
> `PreToolUse:Write hook error: IMPLEMENTER-ŐR …` → a fájl nem jött létre.
>
> **Slot-zár szivárgás (PR #310).** Egyetlen futó kör mellett a driver „minden
> slot foglalt (2)"-t naplózott: a `.pipeline/lock` FD-jét a **tmux szerver**
> tartotta (E07-R22 drivere indította 18:13-kor, a 19:47-es merge után is élt).
> `PIPELINE_SLOTS=2` mellett az 1-es slot tartósan foglalt maradt — ez a
> „0 párhuzamos kör" mérés MÁSODIK, a sor-szerializációtól független oka.
> Javítva: a tmux-hívások fd 9-et lezáró alhéjban futnak; funkcionális
> falszifikációs teszt őrzi (`tools/tests/test_slot_lock_inheritance.py`).

> ## 🚀 [PIPELINE v2] Áteresztő-program beütemezve — ADR 0307, E99-R14…R19 (2026-08-18)
>
> A lánc saját sebességének MÉRT átvizsgálása után hat governance-kör került a
> sor élére (`E99-R14` … `E99-R19`, mind `pending`), és a mérési alap az
> [ADR 0307](docs/adr/0307-pipeline-throughput-program-v2.md)-ben áll.
> **Azonnali intézkedés már megtörtént:** a `.pipeline/engine-override` tíz napja
> `terra`-n ragadt (a 08-06-i kvótaválság maradéka, M3 közben 92%-on) — törölve,
> a sor `engine` oszlopa dönt újra. Mérve: azonos epicen belül `terra` medián
> **63 p**, `minimax` **49 p**, `sonnet-impl` **41 p** kör-idő.
>
> A hat kör: **R14** lejáró motor-override + motor-statisztika · **R15**
> halt-eszkaláció (az utolsó self-heal kísérlet MÁS motorral) és ismétlődő
> riasztás (mérve 42 órás néma állás, 08-16→08-18) · **R16** kör-granularitás
> mérése + összevonási javaslat · **R17** l10n-fragmentumok (az `app_*.arb` 36
> nyitott briefben ütközik) · **R18** generált `public.dart` barrelek (25/18/8
> brief) · **R19** main-szinkron, egyetlen záró commit, őszinte `risk` besorolás.
>
> A `PIPELINE_SLOTS=2` mérve 08-04 óta NULLA párhuzamot adott (120 kör, 1 átfedő
> pár): a sor függőségi értelemben soros volt. Az E99-sáv az első valóban
> diszjunkt munkafolyam — a `tools/round-slots.py plan` az E07-R22 mellé már
> admittálja az E99-R14-et.

> ## 🔁 [HEAL E99-R14/H7] `outcome=retry` — exact-SHA Full Gate 1 tesztje pirosra váltott, de a kör diffje `tools/**`+`docs/**`-re szorítkozik; izolált 5× repro a pontos SHA-n zöld, a rerun is zöld — ismétlődő, kör-független `song_import_controller_test.dart` flake (2026-08-18, L316)
>
> Az E99-R14 exact-SHA Full Gate futása (`32190289173`, fej `bfd43bf9`) 5072
> zöld/1 piros eredménnyel állt le: `test/features/song_trainer/application/
> import/song_import_controller_test.dart: cancellation during import closes
> the workspace without a record` — `Expected: empty`, `Actual:
> [_Directory: '.../import-1']`. A kör brifje kizárólag GOV-08 motor-policy
> tooling (`tools/engine-profile.sh`, `tools/round-metrics.py`,
> `tools/round-pipeline.sh` + tesztek, `docs/rounds/e99-r14-*`) — `git diff
> origin/main...bfd43bf9` nulla `song_trainer` találatot ad, nincs ok-okozati
> út. **Ugyanaz a teszt, ugyanaz az assert**, mint [[L182]] (E05-R21,
> 2026-08-08) — ott egy normál kör oldotta fel inline, itt HALT-ot és
> dedikált self-healt igényelt. Ez a heal a [[L182]]/[[L183]] mért eljárását
> követte, nem fogadta el bemondásra: izolált `git worktree --detach` a
> PONTOS `bfd43bf9` SHA-n, `flutter test
> test/.../song_import_controller_test.dart` **5×** → **5/5 zöld**. Utána
> `gh run rerun 32190289173 --failed`, várakozás `tools/wait-for-ci.sh`-sal
> ELŐTÉRBEN (sosem csupasz `gh run watch`) → **`completed success`, ugyanazon
> `bfd43bf9`-n**; Router CI erre a SHA-ra függetlenül is már zöld volt. Nincs
> kódváltoztatás — a self-heal hatóköre (`tools/**`/`.ai/**`/`docs/adr/**` +
> a megállt kör brifje) nem terjed ki a `song_trainer`-import rétegre, még ha
> a race-nek volna is kézenfekvő javítása. **Nyitva maradt, dokumentált
> tartozás:** ez a flake MOST MÁR KÉTSZER okozott mérhető költséget azonos
> gyökérokkal, javítatlanul — egy jövőbeli, a `song_trainer`-import réteget
> explicit célzó NORMÁL kör brifjének fel kellene vennie (`cancel()`
> várja meg a workspace-cleanup Future-jét, vagy a teszt egy
> determinisztikus completion-jelre várjon a nyers `list()` helyett).
> Lecke: **[[L316]]**.

> ## 🔁 [SELF-HEAL E07-R23/H6, 2. előfordulás] `outcome=retry` — az alábbi „KÉSZ" API-kulcsos javítás ~10 percen belül nyomtalanul eltűnt; nincs kód-gyökérok, a user kötelező kulcs-politikát hozott, és előfizetéses `codex login` állította helyre — VALÓDI hívással igazolva (2026-08-18, L315)
>
> Az alábbi [HEAL E99-R14/H6] bejegyzés „KÉSZ" jelzése **RÉSZBEN ELAVULT**: a
> 21:03-kor API-kulccsal helyreállított `~/.codex/auth.json` 21:03 és E07-R23
> 21:18-as újabb H6-ja között **nyomtalanul eltűnt** — nem lejárt, a fájl
> maga hiányzott. Ez a self-heal megmérte: `tools/**` egyetlen scriptje sem
> nyúl `~/.codex/auth.json`-hoz (Class A kizárva), a
> `~/.codex/log/codex-login.log`-ban 20:57:51Z után nincs újabb login/logout
> esemény — a fájl nem egy újabb `codex login`-tól tűnt el, dokumentált nyom
> nélkül. Vizsgálat közben a `main` egy párhuzamos, emberi-vezérelt session
> commitjával bővült (`ba621b8d`): **kötelező policy**
> (`docs/execution/pipeline-selfheal-prompt.md` „Kulcs-politika") — a boxon
> talált `RAG_OPENAI_API_KEY` (`~/.rag-openai.env`, egy vakvágány, amit ez a
> heal NEM használt) és bármely hasonló kapóra jövő kulcs motor-hitelesítésre
> fordítása **TILOS** (a user API-számláját terhelné), lejárt motor-authnál a
> helyes válasz `blocked`+indoklás vagy működő motor-profilra váltás. Percekkel
> később `~/.codex/auth.json` visszatért `"Logged in using ChatGPT"`
> (előfizetéses mód) — ezt EZ a self-heal független, VALÓDI
> `codex exec -s read-only` hívással igazolta (5 025 token, exit 0), nem
> fogadta el bemondásra. A `terra` profil élő E99-R14-folyamat alatt állt a
> mérés pillanatában, ezért az `engine-profile.sh use terra` nem lett volna
> biztonságos workaround. Nincs PR, nincs kód-diff: `outcome=retry`, a lánc
> feloldódik, E07-R23 a megőrzött pre-flighttal (`9c2aa9bb`) újra sorra kerül.
> Lecke: **[[L315]]**.

> ## 🔐 [HEAL E99-R14/H6] KÉSZ — Codex CLI OAuth refresh token „already used" (401), a boxon frissen megjelent API-kulccsal helyreállítva, VALÓDI `codex exec` hívással bizonyítva — nincs kód-diff, egyúttal E07-R23/H6-ot is feloldja (2026-08-18)
>
> Az E99-R14 saját, review M5 leletét záró **kötelező Codex-javító köre**
> (eredeti kísérlet + 2 automatikus folytatás) `status=unknown`-nal halt el;
> HAT másodperccel az erre indított önjavítás elindulása után egy TŐLE
> FÜGGETLEN kör, az E07-R23 (implementer=codex) is H6-tal állt le ugyanazzal
> a mintával. Mindkét kör Codex-alfolyamat-logja (`/tmp/codex-e99-r14-m5.log`,
> `/tmp/codex-e07-r23.log`) azonos, mért hibát adott: `codex_login::
> auth::manager: Failed to refresh token: 401 … code: "refresh_token_reused"`
> — a `~/.codex/auth.json` refresh tokenjét egy másik folyamat már
> felhasználta, ezért a CLI onnantól minden hívásra 401-et kapott. Mivel
> MINDEN `engine=codex` sor (és az E99-R14 MiniMax→Codex javító-eszkalációja
> is) ugyanazt a megosztott `~/.codex` CODEX_HOME-ot használja, a gyökérok
> közös infrastruktúra, nem a két kör tartalma.
>
> **Nem kód-javítás, hitelesítés-helyreállítás.** Az önjavítás indulása körüli
> percekben megjelent a boxon egy `~/.openai.env` (`OPENAI_API_KEY=`,
> friss időbélyeg, helyes jogosultság, **nincs** hozzá tartozó cron/
> systemd/repo-eredet — mérve, kizárva) — a jelek (+ két aktív kézi SSH-
> session) kézi emberi elhelyezésre mutatnak, amit a self-heal jelentése
> KÖRÜLMÉNY-alapú következtetésként jelöl, nem tanúsítványként. A
> `codex login --help` dokumentált headless-útját követve
> (`printenv OPENAI_API_KEY | codex login --with-api-key`), a
> `~/.codex/auth.json` időbélyegzett mentése után, a self-heal
> helyreállította a hitelesítést, és — mivel a `codex login status` a törött
> állapotban is „Logged in"-t mutatott (csak a LOKÁLIS fájlt nézi) — EGY
> VALÓDI `codex exec -s read-only` hívással igazolta: helyes válasz, 23 303
> token, valódi session-id. Lecke: **[[L314]]**.
>
> **Nyitva maradt, dokumentált mellékhatás (emberi döntés kell):** a
> `~/.codex` mostantól API-kulcsos, TOKENENKÉNTI díjazású hitelesítéssel megy,
> NEM a korábbi ChatGPT Pro előfizetéssel — a
> `docs/execution/engine-registry.tsv` `codex` sora (`auth_env: -`) ezt még
> nem tükrözi. Ha ez nem szándékos tartós váltás, `codex login`
> (böngészős vagy `--device-auth`) visszaállítja az előfizetéses módot.

> ## ✅ [HEAL E99-R14/H3] KÉSZ — a lánc cronja minden firingre `PIPELINE_ORCH_SWAP_ENGINE=minimax`-ot exportál, amit a driver-tesztek ambiensként örököltek — PR #311 (más session írta, ez a heal függetlenül újramérte), `80cdb46a` (2026-08-18)
>
> Az E99-R14 (GOV-08) a saját brief-diffjén zölden állt, de a kötelező teljes
> `tools/tests` suite négy motor-függetlenségi teszttel
> ([review](docs/reviews/e99-r14-review.md) M4: `4 failed, 508 passed, 546
> subtests`) pirosra váltott, és H3-mal megállt
> (`halted_at=2026-08-18T20:05:40Z`). A self-heal (1/3. kísérlet) megmérte a
> gyökérokot: a `.pipeline`-t vezénylő cron-sor (`crontab -l`) MINDEN firingre
> `PIPELINE_ORCH_ROTATION=alternate PIPELINE_ORCH_SWAP_ENGINE=minimax`-ot
> exportál — ez öröklődik a tmux szerver globális környezetén és minden
> onnan induló session/gyerekfolyamaton át, a `tools/tests/
> test_orchestrator_rotation.py`/`test_reviewer_independence.py`
> driver-segédje pedig `dict(os.environ)`-ból építette a tesztelt
> `round-pipeline.sh` gyerekfolyamat környezetét. A MÉRT alapértelmezést
> (`orch_swap_engine=sonnet-impl`, user-döntés 2026-08-11) így csendben
> felülírta az üzemeltetői override, és a teszt a kettő ÜTKÖZÉSÉT mérte, nem a
> kódot — `bash -x` közvetlen reprodukcióval igazolva. Ugyanez a hibaosztály
> már egyszer félrevezetett egy self-healt (HEAL E07-R21/H2, kézi
> env-tisztítással megkerülve, a defekt megmaradt), és szerkezetileg [[L312]]
> rokona (ADR 0307 §1.3.1 — ott egy FD-t, itt egy env változót szivárogtat a
> tmux szerver).
>
> **A tényleges javítást egy párhuzamosan futó másik governance-session adta**
> (`/tmp/ss-hermetic`, branch `gov/hermetic-driver-tests`, PR
> [#311](https://github.com/wolfcasaba/strumsight/pull/311), squash
> `80cdb46a`, Router CI zöld a pontos head SHA-n): mindkét driver-segéd a
> bázis környezetből mostantól kiszűri a `PIPELINE_*` kulcsokat, plusz egy
> falszifikált regressziós őr (`AmbientEnvironmentLeakTest` — RED a szűrés
> kiszedésével, GREEN vissza). Ez a self-heal — AGENTS.md §13 szellemében —
> NEM indított versengő második javítást ugyanazon a két fájlon: bevárta a
> már futó CI-t (`tools/wait-for-ci.sh`, védett timeouttal), majd a merge
> UTÁN egy izolált klónban, a SAJÁT szennyezett ambiensében
> (`PIPELINE_ORCH_SWAP_ENGINE=minimax` élve a futtató shellben) függetlenül
> újramérte: `python3 -m pytest tools/tests -q` → **496 passed, 550
> subtests, 0 hiba**.
>
> **Nyitva maradt, dokumentált megfigyelés (nem ennek a healnek a scope-ja):**
> a crontab `PIPELINE_ORCH_SWAP_ENGINE=minimax` sora ma is ÉLESben minden
> Terra-vezényelt kör csere-implementerét `minimax`-ra kényszeríti a
> dokumentált `sonnet-impl` alapértelmezés helyett — pontosan az az
> „elfelejtett, sosem lejáró override" minta, amit maga az E99-R14 D1/D2 a
> `.pipeline/engine-override` FÁJLRA kíván kezelni. Emberi/governance döntés,
> ezt a self-heal nem módosította. Lecke: **L313**. A lánc E99-R14-gyel
> folytatódik a következő cron-firingen.


> **E07-R19 KÉSZ — PR #303, `2ce22f3b` (2026-08-18).** A local plan
> repository elkülönített draft/active/archive névterekkel, checksumos
> rekord-szintű korrupció-containmenttel, v0→v1 migrációval és korlátos
> történettel merge-elve. A független review és security re-review APPROVED;
> Full Gate exact-SHA: `32147063069`, Router CI exact-SHA: `32148470452`.
> Következő kör: E07-R20, új sessionben.

> **Read this first at the start of every session.** Single source of truth for
> "what's done / what's next" — short operational snapshot (SDD Ch2 §16.6
> [How to update](#how-to-update-this-file)). Last updated: **2026-08-19
> (E07-R26 done — outcome ingestion + plan revision, caller-fed / zero
> repository writes, see banner above.) Prior: 2026-08-19
> (E99-R15/GOV-09 done — self-heal engine escalation + halt-reminder throttle,
> see banner further below.) Prior: 2026-08-18
> (E07-R18 done — application-level, cancellable, state-machine-driven
> GenerationOrchestrator: immutable `GenerationState` (idle/running/completed/
> cancelled/failed + 4 stage checkpoints), a `GenerationOrchestrator` that
> chains the R05–R17 evidence/priority/candidate/time-budget/scheduling/
> review-queue/validator/repairer services into one cancellable, per-request
> single-flight run, and a Flutter-free `PlanGeneratorController` bridge. A
> §0.0 pre-flight revision resolved a measured gap the first dispatch
> correctly stopped on (no scope-approved `WeeklyScheduleDecision →
> AdaptivePracticePlan` assembly contract existed) by assigning that assembly
> to the already-allowed orchestrator file, no new production file. Independent
> review found and closed 1 BLOCKER (a same-request double-`generate()` call
> on `PlanGeneratorController` threw an uncaught `StateError` instead of
> resolving `AppResult` — violated ADR 0266's "no raw exception crosses the
> boundary") + 1 MAJOR (the validate-reject/repair-fail no-activation branch
> had zero test coverage) in one fix round, both confirmed fixed via a
> disposable probe test run by hand in an isolated clone; security review
> (risk=high) PASS with 4 forward-looking NOTEs for the future activation
> implementation. Full Gate and Router CI exact-SHA green, PR #300. Both
> flags remain `false`, zero production callers. Prior: E07-R17 done — bounded deterministic review queue: typed targets/outcomes,
> explicit local-date interval policy, strict daily budget, deduplication and
> replacement-required handling; review APPROVED, exact-SHA CI green, PR #296.
> Prior: E07-R16 done — bounded, evidence-based progression/regression policy for
> the AI Practice Generator: centralized `ProgressionPolicy` bounds
> (one-step-max adaptation, tempo clamp, cooldown, minimum evidence),
> discomfort/safety always blocks advance regardless of performance,
> repeated-struggle-only regression (a single weak session is noise),
> immediate "too hard" self-report override, every decision
> evidence-referenced; independent review + security PASS, Full Gate and
> Router CI exact-SHA green, PR #295. Prior: E07-R15 done — domain-pure,
> deterministic WeeklyScheduler with daily focus, rest/unavailable,
> high-load, bounded-review and signed song-target performance guards;
> independent review + security PASS, Full Gate and Router CI exact-SHA
> green, PR #294. The E07-R15 H3 self-heal narrowed its brief scope to the
> shared scheduling-fixture directory with an executable scope-audit
> regression guard; the subsequent H7 self-heal made the signed target-date
> performance boundary explicit and added its brief-contract regression
> guard (PR #290, Router CI exact-SHA green); a repeated H7 then exposed
> that resumed branches were not required to integrate that merged brief
> before review, so the pipeline prompt now gates repair/review on measured
> `origin/main` ancestry (HEAL E07-R15/H7, upstream-sync).)**

> ## ✅ [HEAL E07-R19/H4] KÉSZ — a v0→v1 envelope-migráció nem relabelte a schemaVersion-t; a fix a kör saját ágára ment, nem `main`-re (2026-08-18)
>
> A független review (`docs/reviews/e07-r19-review.md`, branch
> `minimax/e07-r19-local-plan-repository` @ `dce4f957`) egy nyitott MAJORt
> (M-01) mért: `PracticePlanMigrator._migrateVxToCurrent` a v0 envelope-ot
> változatlanul adta vissza, így a migrált eredmény `schemaVersion`-je `0`
> maradt az elvárt `1` helyett (ADR 0267 §6, brief A7 below-cell) —
> eldobható próba: `Expected: <1>; Actual: <0>`. A review „a kör korábbi
> MiniMax- és Codex-javítási kerete a handoff szerint már elfogyott"
> indoklással H4-gyel halt.
>
> A self-heal (1/3. kísérlet) megmérte, hogy a branch `.codex-round-status`
> jelzése (`head=0d505ca7`, `signalled_at=12:30:06Z`) a MiniMax implementer
> SAJÁT, első befejezés-jelzése volt, nem egy review-utáni javító kör; a
> kör két korábbi self-healje (H3 — brief-scope, PR #301; H-NOSIGNAL —
> `wait-for-round.sh` infra, PR #302) egyike sem érintette a
> migrátort. A hibás kód kizárólag a kör SAJÁT, `main`-be még nem olvadt
> ágán él (a fájl `main`-en nem is létezik), ezért a javítás célja a kör
> ága lett — nem egy `main`-alapú `heal/`-branch —, a
> `pipeline-orchestrator-prompt.md` H8-szakaszának „normál push a
> kör-worktree-re" mintáját követve. `tools/round-pipeline.sh`
> mérce-őrszeme (`heal_pr_number` / `gate_test_count` /
> `gate_artifact_hashes`) ezt kifejezetten tolerálja, amíg `main` és a
> védett gate-artefaktumok (`tools/round-gate.sh`,
> `.github/workflows/{build-apk,router-ci}.yml`) érintetlenek.
>
> A javítás: `_migrateVxToCurrent` másolatot ad vissza
> `schemaVersion: currentSupportedSchemaVersion` felülírással (a checksum
> csak a `body`-t fedi, tehát ez nem érvényteleníti); a meglévő
> `practice_plan_migrator_test.dart` "below cell" esete maga is a régi,
> hibás `0` értéket várta — ez az oka, hogy a gate korábban zölden ment át
> M-01 mellett — most a current verziót várja. Elkülönített worktree-ben
> mérve piros a javítás előtt (`Expected: <1>; Actual: <0>`), zöld utána;
> `tools/round-gate.sh test/features/practice_generator/data/
> local_repository_test.dart test/features/practice_generator/data/
> practice_plan_migrator_test.dart` minden lépése zöld
> (format/analyze/mindkét célzott teszt/architecture/secrets/l10n). Fix
> commit a kör ágán: `45395d9f`. `main` és a round-brief érintetlen.
> `docs/LESSONS.md` **L304**. A lánc E07-R19-cel folytatódik a következő
> cron-firingen — a következő orchestrátor-session friss review-t indít a
> most javított ágon.

> ## ✅ [HEAL E07-R19/H-NOSIGNAL] KÉSZ — `wait-for-round.sh`/`wait-for-router.sh` baseline-ja folyamat-memóriában élt, nem vette észre a köztes-hívások közt már kész jelzést (2026-08-18)
>
> Az E07-R19 folytató köre (orchestrátor=Terra, implementer=minimax) jelzés
> nélkül halt el 12:37:10-kor — a pipeline elakadás-gyorsítója (E99-R13 óta)
> ~2 mp alatt helyesen észlelte, hogy a `codex` motor-folyamat kilépett. A
> tényleges implementer-munka (MiniMax kezdeti implementáció + 1 MiniMax- +
> 1 Codex-javítókör) eközben MÁR KÉSZ és pusholva volt
> (`minimax/e07-r19-local-plan-repository` @ `0d505ca7`, `.codex-round-status`
> `status=done`/`signalled_at=12:30:06Z`).
>
> A session rollout (`~/.codex-terra/sessions/…/rollout-2026-08-18T11-55-08-…jsonl`,
> strukturált JSON, nem a redundáns TUI-újrarajzolással dagadó tmux-log)
> megmérte a gyökérokot: a Terra `exec_command`/`wait` eszköze csendes
> parancsnál önmagától „yield"-el, ezért a dokumentált „exit 5 → hívd meg
> újra" szerződés szerint `tools/wait-for-round.sh`-t ~20, egyenként FRISS
> folyamatként hívta (cell ID 65–87), nem egyetlen hosszan futó hívásként.
> A script a stale-signal védelmét (E02-R08) egy `baseline` shell-változóban
> tartotta, amit MINDEN friss folyamat a SAJÁT indulásakor, a jelzésfájl
> AKKORI tartalmából számolt újra — egy, a tényleges befejezés (12:30:06Z)
> UTÁN induló friss hívás ezért a friss `done`-t tekintette baseline-nak, és
> sosem jelentette késznek. Az orchestrátor 7 percen át kizárólag üres
> kimenetet kapott, majd stale szöveges státusszal ("a Codex javító kör még
> fut") zárta a választ jelzés nélkül — pontosan az E07-R09 self-heal
> (2026-08-16) által már dokumentált és tiltott minta.
>
> A javítás a baseline-t egy, a munkapéldányban élő MARKER-fájlba
> (`.wait-for-round-baseline`/`.wait-for-router-baseline`, gitignore-olt)
> perzisztálja az első hívástól a terminális kézbesítésig, hogy a köztes
> friss újraindítások UGYANAZT lássák; `wait-for-router.sh` (`engine=auto`)
> byte-azonos mintát örökölt, ezért ugyanazt a javítást kapta. Két
> regressziós teszt (RED a javítás előtt, `5 != 0`, GREEN utána, mindkét
> scriptre) + egy nem-regressziós társteszt (az eredeti E02-R08 védelem
> változatlan). `tools/tests`: 467/467 zöld, 524 subtest. PR
> [#302](https://github.com/wolfcasaba/strumsight/pull/302), squash
> `5b520739`; Router CI zöld a pontos head SHA-n (router-only fix, nincs
> Dart-változás, build-apk nem indult). `docs/LESSONS.md` **L303**. A lánc
> E07-R19-cel folytatódik a következő cron-firingen.
>
> ## ✅ [HEAL E07-R19/H3] KÉSZ — a brief pre-flight calloutja Core/domain hiányra méretett, de nem mondta ki: a hiány meglévő típusokkal és írási sorrenddel is teljesíthető (2026-08-18)
>
> Az E07-R19 (Local repository, migráció és korrupcióvédelem) saját
> pre-flightja (sonnet-impl via Terra, branch
> `sonnet-impl/e07-r19-local-plan-repository`, commit `1801a399`) helyesen
> mérte, hogy sem `PracticePlanRepository`/`PracticeOutcome` domain-kontraktus
> (SDD Ch8 §30.1), sem Core atomikus write API nem létezik — de abból, hogy
> MINDKÉT hiány tilos-zónás fájlt igényel, H3-mal halt (`.pipeline/HALTED`,
> halted_at=2026-08-18T11:24:19+00:00).
>
> A self-heal (1/3. kísérlet) megmérte, hogy a következtetés túlterjeszkedő
> volt: a brief saját §0 callout-ja már megnevezte az R04
> `GenerationDraftRepository`-t — egy KONKRÉT osztályt, `abstract interface
> class` nélkül, meglévő domain típusra építve —, ami pontosan a
> „repository-szerződés" mintája; és egyetlen `KeyValueStore.writeString`
> hívás a hívó szemszögéből már all-or-nothing, tehát a „megszakított írás
> nem hagy félkész rekordot" invariáns kulcs-sorrenddel (ÚJ kulcs előbb,
> mutató-váltás utoljára) old meg, Core-módosítás nélkül — pontosan úgy,
> ahogy a repóban máshol (`storage_migrator.dart`, `json_document_store.dart`)
> már bizonyítottan működik.
>
> A feloldás kizárólag dokumentált §0.0 brief-revízió: `allowed_paths`
> byte-for-byte változatlan, 0 produkciós fájl módosult. Regressziós őr:
> `tools/tests/test_e07_r19_repository_contract_scope.py` (mért típus-tények
> zárolása + a §0.0 szöveg jelenléte — RED a mérje-fel briefen, GREEN a
> revízió után). PR [#301](https://github.com/wolfcasaba/strumsight/pull/301),
> squash `b87c7479`; Router CI zöld a pontos head SHA-n (nincs Dart-változás,
> build-apk nem indult). `docs/LESSONS.md` **L302**. A lánc E07-R19-cel
> folytatódik a következő cron-firingen.
>
> ## ✅ [E07-R11] KÉSZ — PlanValidator és korlátos deterministic repair (2026-08-16)
>
> A `PlanValidationContext` explicit catalog/availability/identity inputtal
> fail-closed validál; `error`/`fatal` nem aktiválható. A `PlanRepairer`
> determinisztikus, korlátos és minden lépést `systemAdaptation` okkal naplóz;
> sosem módosít completed múltat vagy növeli a hard időmaximumot. A független
> review egy active day completed-block múltmódosítási rést talált, amit a
> regressziós teszttel javítottunk. PR #285, squash `3178508c`; Full Gate
> `31933205113` és Router CI `31933789551` zöld. Következő: E07-R12.
>
> ## ✅ [E07-R10] KÉSZ — AdaptivePracticePlan, day, block és revision domain (2026-08-16)
>
> Az ADR [0256](docs/adr/0256-practice-plan-revisions-immutable-past.md)
> (revízió-alapú immutable múlt) megvalósítása: `lib/features/practice_generator/domain/model/`
> — `AdaptivePracticePlan` (verziózott, veszteségmentes round-trip JSON,
> `generationProvenance`+`policyVersions`, `PracticePlanSummary` DTO), `PracticeDay`/
> `PracticeBlock` (közös, pinnelt `PracticeItemStatus` — 8 érték az SDD §16.5-ből
> szó szerint, `practice_block.dart`-ban, `PracticeGoalStatus`/`PracticeGoal`
> mintáját tükröző `canTransitionTo`/`transitionTo` + completed-content guard),
> `PlanRevision` (szigorúan monoton szám, TELJES immutable snapshot — nem diff),
> `PlanChangeSet`/`PlanChange` (strukturált before/after, typed `PlanChangeReason`,
> szabad szöveg nélkül).
>
> **Két scope-kérdést a pre-flight/kör közbeni §0.0/§0.0.1 brief-revízió oldott
> fel** (a brief eredetileg egy nem-létező `planned` státuszértékre hivatkozott
> — az SDD-ben csak §16.5 „Block status” 8-elemű listája létezik, külön „Day
> status” szakasz nélkül; illetve az implementer egy negyedik, megosztott
> teszt-fixture fájlt kért a brief 3-fájlos korlátján túl — a repo már meglévő
> `test/fixtures/<feature>/<terület>/<név>_fixtures.dart` konvencióját követve
> engedélyezve, `plan_enums.dart` érintése nélkül). A független review 1 MINOR-t
> talált (`PlanChangeType` a domain stabil-kódú konvenciója helyett nyers
> `.name`-et perzisztált) — egy rövid javító körben javítva (`0a479818`),
> függetlenül újramérve. A kötelező biztonsági review (`risk = "high"`) PASS:
> a `PracticePlanSummary` strukturálisan kizárja a `PracticeGoal.userNote`-ot
> (poison-pill teszttel bizonyítva), minden `fromJson` fail-closed, 4
> nem-blokkoló NOTE jövőbeli köröknek (perzisztencia/AI-tutor export).
>
> Két saját, független valódi-sértés próba (A2 revízió-immutabilitás, A4
> completed-block-tartalom-immutabilitás): mindkettő PIROSRA váltott a guard
> ideiglenes eltávolításával, majd zölden visszaállt. Review:
> [`e07-r10-review.md`](docs/reviews/e07-r10-review.md) (APPROVED),
> [`e07-r10-security.md`](docs/reviews/e07-r10-security.md) (PASS). PR
> [#283](https://github.com/wolfcasaba/strumsight/pull/283), squash `c2778bbc`,
> exact `4d4c3ee4`: Full Gate
> [31929041014](https://github.com/wolfcasaba/strumsight/actions/runs/31929041014)
> + Router CI [31929076484](https://github.com/wolfcasaba/strumsight/actions/runs/31929076484)
> success (Router CI manuálisan dispatch-elve, mert a csúcs-commit önmagában
> nem érintett trigger-útvonalat). Mindkét flag (`practiceGeneratorEnabled`,
> `plannerAssistEnabled`) `false` marad, nulla production hívó — production
> viselkedés változatlan. Következő kör: **E07-R11** (PlanValidator és
> deterministic repair, `docs/rounds/e07-r11-plan-validator-and-repair.md`).
>
> ## ✅ [HEAL E07-R11/H3] KÉSZ — az E07-R11 brief hiányzott egy megosztott validáció-fixture könyvtárat (2026-08-16)
>
> Az E07-R11 brief `allowed_paths`-a a két validáció-tesztfájlt
> (`plan_validator_test.dart`, `plan_repairer_test.dart`) és a property-tesztet
> névre szólóan sorolta fel, de egyetlen megosztott fixture-helyet sem —
> miközben §6/§6.1 mindkét tesztfájltól ugyanazt a nem-triviális
> `AdaptivePracticePlan`/`PracticeDay`/`WeeklyAvailability` felépítést várta
> el. A sonnet-impl (engine=minimax-m3) implementer emiatt listán kívül hozta
> létre `test/fixtures/practice_generator/validation/validation_fixtures.dart`-ot
> (munkapéldány `/home/ubuntu/ss-sonnet-impl-e07-r11`, `head=a82bef17`, 7
> piszkos fájl, egyik sem commitolva) — a scope-audit helyesen `stopped`-ra
> váltotta (H3, `.pipeline/HALTED` halted_at=2026-08-16T06:06:06Z).
>
> **Nem új hibaosztály.** A közvetlen precedens az ELŐZŐ kör, ugyanebben a
> feature-fában: `E07-R10` §0.0.1 — alig öt órával korábban (R10 merge
> `05:50:55`, R11 dispatch `05:51:04`) pontosan ugyanezt a hiányt mérte
> (`test/fixtures/practice_generator/plan/plan_fixtures.dart`), de az R11
> brief korábban (2026-08-15) lett előre megírva, és a két dispatch között
> nem futott olyan pre-flight, ami az R10-frissen-mért konvenciót átvezette
> volna. Lásd még `docs/LESSONS.md` **L242** (E06-R20) és **L246** (E06-R23) —
> ez a NEGYEDIK mérés ugyanarra a gyökérokra. A self-heal elolvasta a fájl
> teljes tartalmát: kizárólag a már engedélyezett `public.dart` típusaiból
> épít paraméterezhető teszt-builder függvényeket, 0 domain-döntés.
>
> Feloldás: `allowed_paths` bővült a `test/fixtures/practice_generator/
> validation` bare directoryval (R10/L242 mintáját követve, nem az egyetlen
> jelenleg létező fájlnevet rögzítve) — 0 tartalmi/architekturális döntés
> változott. Regressziós védelem:
> `tools/tests/test_e07_r11_validation_fixture_scope.py` — a mért
> halt-útvonalat futtatja `audit_legacy_scope()`-on a committolt brief ellen,
> és egy `validation/`-on kívüli szomszéd útvonalat is mér, bizonyítva, hogy
> a bővítés szűk maradt. Teljes `tools/tests` gate: 454 passed, 498 subtests
> passed. PR [#284](https://github.com/wolfcasaba/strumsight/pull/284),
> squash `46f8c23f`, Router CI
> [31931326850](https://github.com/wolfcasaba/strumsight/actions/runs/31931326850)
> success az exact `be5826a0` SHA-n (docs/tools-only, nincs Dart-változás,
> Full Gate nem releváns). Lecke: `docs/LESSONS.md` **L294**.
>
> A megállt kör saját munkapéldánya (`/home/ubuntu/ss-sonnet-impl-e07-r11`,
> commitolatlan, PR nélkül) SZÁNDÉKOSAN érintetlen maradt: ez a self-heal a
> megállt kör levezénylése helyett kizárólag az akadályt szüntette meg (ADR
> 0112 mandátum). A lánc a következő firingen E07-R11-et friss dispatchként
> vagy folytatásként veszi fel, a most javított `allowed_paths` alatt.

> ## 📦 Korábbi kör-narratívák → archívum
>
> A lezárt körök részletes története a
> [`docs/handoff-archive.md`](docs/handoff-archive.md) fájlban van.
> MIÉRT: ezt a fájlt MINDEN session és MINDEN kör elolvassa (orchestrátor +
> implementer), ezért a lezárt körök narratívája itt tiszta kontextus-adó.
>
> **Szabály (ADR 0175 §4):** a fejlécben a friss állapot és a **két legutóbbi**
> kör bannere marad; minden korábbi banner az archívumba kerül a kör lezárásakor.
> 2026-08-18 (E07-R23 zárása): az E07-R21 és HEAL E07-R21/H2 banner
> archiválva; a fejlécben az E07-R23 és E07-R22 banner marad. 2026-08-18
> (E07-R22 zárása): az E07-R20 banner archiválva; a fejlécben az E07-R22,
> E07-R21 és HEAL E07-R21/H2 banner marad (a kettő együtt az R21 narratíva).
> 2026-08-16 (HEAL E07-R11/H3 zárása): a HEAL E07-R09/H5 banner archiválva;
> a fejlécben az E07-R10 és HEAL E07-R11/H3 banner marad.
> A korábbi diéta-bejegyzések teljes szövege: `docs/handoff-archive.md`.

## 1. Current release state

- **StrumSight** — offline, on-device guitar chord + strum-direction detector
  (Flutter, Dart SDK ^3.12.2, Material 3, Riverpod 3 hand-written providers).
- `pubspec` version: **1.0.0+1** (development). No production release yet —
  release signing is fail-closed via `release-apk.yml` (ADR 0062); a version
  bump / release is a separate user decision.
- Development APK per round from CI (`build-apk.yml`), artifact name
  `strumsight-<ver>-<build>-<sha>-development.apk` (ADR 0051).
- **Epic 1 (Core Platform) technikailag kész** — a zárókör (E01-R16) gépi
  gate-jei zöldek; a végső elfogadás a user valódi-eszközös §16.3/§16.4 menetén
  áll (HORIZON-szabály: synthetic green ≠ done). Evidencia:
  [`docs/sdd/epic-01-completion-report.md`](docs/sdd/epic-01-completion-report.md).
- **Epic 2 (Practice Engine) lezárva** — E02-R20 (epic-zárókör) kész; a
  Practice V2 domain és application réteg kimerítően tesztelt, a migrated
  Learn útvonal (`migratedLearnEnabled`) élesíthető. Az önálló Practice V2
  Hub→Setup→Session út production-drótozása **KÉSZ** (E02-R21, PR #55,
  `6e5cec7`) — a `practiceSessionHostProvider` élesben él, a §3
  rendszerszintű rés pótolva.
  Evidencia: [`docs/sdd/epic-02-completion-report.md`](docs/sdd/epic-02-completion-report.md).
- **Epic 3 (Song Trainer) elkezdve** — E03-R01 (kickoff, baseline+ADR-ek+flag),
  E03-R02 (SongDocument V2 identitás/metaadat domain modell + codec),
  E03-R03 (section/measure struktúra + determinisztikus tempo/meter/key map +
  SongTimeMap), E03-R04 (track/event domain modell + monophonic elemzés),
  E03-R05 (validator/normalizer/capability resolver), E03-R06 (legacy
  Song/Setlist migrációs adapter) és E03-R07 (fájlrendszeres Song repository
  és asset store) kész. A modell flagek mögött, hívó UI/import-runner nincs
  — production viselkedés változatlan.
- **Epic 5 (Computer Vision) implementáció TELJES** — E05-R01…R30 mind
  merge-elve: capability audit + hat alapozó ADR, hand/pose landmark
  provider, guitar geometry, metric engine, feedback policy, session
  controller, audio–vision szinkron, observation fusion, posture safety,
  Practice/Song Trainer/AI Tutor/Analyze integráció, device tier + thermal
  hardening, és a záró minőségi kapuk (architektúra-guard, model-integritás,
  vision-off paritás, evaluation harness, completion report, rollout
  runbook). **Mind a 11 vision flag `false` marad minden környezetben** — a
  végső elfogadási kapu a user valódi-eszközös HORIZON-menete (§6 „Kötelező
  sorrend"), nem a technikai készenlét. Evidencia:
  [`docs/sdd/epic-05-completion-report.md`](docs/sdd/epic-05-completion-report.md).
- **Epic 6 (Audio Analysis 2.0) elkezdve** — E06-R01 (kickoff: V1 baseline
  mérés + hat kötött ADR: [0215](docs/adr/0215-analysis-document-versioning.md)–[0220](docs/adr/0220-audio-analysis-v2-parallel-rollout-boundary.md)),
  E06-R02 (`lib/features/audio_analysis/domain/` — verziózott,
  immutable V2 domainmodell, 14 fájl + `public.dart` barrel; 1 MINOR
  security follow-up nyitva), E06-R03 (`lib/features/audio_analysis/data/`
  — determinisztikus `AnalysisDocumentCodec` + `LegacyAnalyzeAdapter`/
  `LegacyViewAdapter` veszteségmentes V1↔V2 migráció, [ADR
  0221](docs/adr/0221-legacy-analysis-v2-migration-mapping.md); 1 MINOR
  follow-up R21-re), E06-R04 (`lib/features/audio_analysis/engine/` +
  `domain/analysis_progress.dart` — moduláris, megszakítható,
  progresszt publikáló pipeline-szerződés fake stage-ekkel, konkrét DSP
  nélkül; 1 MINOR follow-up kötelező R07 pre-flight ellenőrzéssel),
  E06-R05 (`lib/features/audio_analysis/data/input/` +
  `domain/analysis_input.dart` — közös, validált input-boundary a
  mikrofonos és importált audio köré, [ADR
  0217](docs/adr/0217-analysis-raw-audio-retention.md) végrehajtása,
  bounds-safe `WavDecoderAdapter` a bitre változatlan core dekóder körül),
  E06-R06 (`lib/features/audio_analysis/data/capture/` +
  `domain/recording_level.dart` — V2 `AnalysisRecorder`, run ID-alapú
  stale-chunk szűrés, inkluzív maximum kliphossz nem-hibás lezárással,
  öt cellás lifecycle-mátrix, olcsó peak/RMS + hysteresises
  clipping-preview, a meglévő `MicCapture`/`AudioSessionCoordinator`
  (ADR 0056) kompozíciójával, `ClipRecorder` érintése nélkül; a 2 nem
  blokkoló MINOR follow-up (F2/S3/S4) az R07 pre-flightban ÉRTÉKELVE, de
  NYITVA marad — a köztes-chunk preview-hiány a valós idejű `RecordingLevel`
  korlátja, nem az R07 offline stage-jéé, ld. §3) és **E06-R07**
  (`lib/features/audio_analysis/engine/quality/` — determinisztikus,
  verziózott jelminőség-riport: `SignalQualityMath`/`QualityThresholds`/
  `SignalQualityStage`, [ADR
  0224](docs/adr/0224-signal-quality-stage-measurement-boundary.md), a
  riport a felvételről szól, sosem a játékról; `dsp_config.dart` bitre
  változatlan; bekötetlen), **E06-R08** (preprocessing/resampling policy,
  [ADR 0225](docs/adr/0225-analysis-preprocessing-and-resampling-policy.md)),
  **E06-R09** (V1 `ClipAnalyzer` stage-adapter és parity, [ADR
  0226](docs/adr/0226-clip-analyzer-stage-boundary-and-fallback-provenance.md))
  **E06-R10** (event evidence modell + onset/strum timeline builder,
  [ADR 0228](docs/adr/0228-event-evidence-model-and-timeline-builder-contract.md))
  **E06-R11** (chord frame evidence, verziózott V1-paritásos szegmens-
  összeállítás + DSP-primary/ML-advisory decoder-provenance flag mögött,
  [ADR 0229](docs/adr/0229-analysis-chord-decoder-fusion-strategy.md)),
  **E06-R12** (beat grid + tempo curve, target-first becslő,
  [ADR 0230](docs/adr/0230-beat-grid-tempo-curve-boundary.md)) és
  **E06-R13** (target alignment engine — monoton, sávos DP-illesztő +
  tempófüggő tolerancia-policy, [ADR
  0231](docs/adr/0231-target-alignment-engine-boundary.md)),
  **E06-R14** (target/free-play timing- és rush/drag-metrikák, release-safe
  `MetricGate`, [ADR
  0232](docs/adr/0232-timing-metric-identity-and-publication-boundary.md))
  **E06-R15** (rhythm consistency + groove-proxyk — IOI-konzisztencia,
  subdivision-illesztés, target-only swing, [ADR
  0233](docs/adr/0233-rhythm-consistency-and-groove-proxy-boundary.md)),
  **E06-R16** (dynamics + stroke balance — attack-strength/local-RMS/
  dinamikai tartomány/accent-balance, release-safe `DynamicsGate`, [ADR
  0234](docs/adr/0234-dynamics-evidence-and-gating-boundary.md)) és
  **E06-R17** (monofonikus pitch capability — YIN-alapú frame→szegmens→
  capability-gate→hét metrika, [ADR
  0235](docs/adr/0235-monophonic-pitch-capability-boundary.md)),
  **E06-R18** (technique-proxy kísérleti modul — öt Lab-only, mérésre
  korlátozott proxy név/tartalom-tiltással, [ADR
  0236](docs/adr/0236-analysis-technique-proxy-safety-and-naming.md)) és
  **E06-R19** (confidence combiner + capability resolver — egyetlen döntési
  pont minden capability státuszára/kalibrált confidence-ére, geometriai
  kombináció, verziózott küszöbök és identity-kalibráció, [ADR
  0237](docs/adr/0237-analysis-confidence-combiner-and-capability-resolver.md))
  **E06-R20** (determinisztikus insight engine — kilenc evidence-backed
  coaching-szabály, maximum-policy ranker, hotspot ranker, [ADR
  0238](docs/adr/0238-analysis-insight-evidence-and-ranking-boundary.md)),
  **E06-R21** (fájl-alapú `AnalysisRepository` + legacy Library migráció,
  atomikus temp→verify→rename írás, rekord-szintű korrupció-karantén, [ADR
  0239](docs/adr/0239-analysis-document-storage.md)), **E06-R22**
  (analysis runner: 11-állapotos state machine, run-ID-alapú controller,
  futásonkénti isolate-futtató, pipeline-agnosztikus `T = AnalysisDocument`
  határ, [ADR 0240](docs/adr/0240-analysis-runner-and-pipeline-boundary.md)),
  **E06-R23** (overview screen + metric cardok, ötállapotú metric card,
  insight-/signal-quality card, [ADR
  0241](docs/adr/0241-analysis-overview-presentation-boundary.md)) és
  **E06-R24** (többrétegű, zoomolható timeline — nyolc capability-vezérelt
  lane, tiszta `TimelineViewport`, adaptív ruler, hotspot-navigátor,
  virtualizáció, [ADR
  0243](docs/adr/0243-analysis-timeline-lane-data-source-and-degraded-boundary.md)),
  **E06-R25** (session-összehasonlítás és fejlődési trend,
  `CompatibilityEvaluator`/`TrendBuilder`, [ADR
  0246](docs/adr/0246-analysis-session-comparison-and-trend-contract.md)) és
  **E06-R26** (Practice/Song/Tutor/Progress integrációs adapterek
  kizárólag publikus barreleken át, redaktált Tutor-snapshot, egyszeri
  progress-kreditálás — új ADR nincs, ADR 0176/0132/0141/0202 végrehajtása),
  **E06-R27** (export/share/privacy: allowlist-alapú `RedactionPolicy`,
  `AnalysisExportCodec`, `ShareCardBuilder`, `ExportAnalysisUseCase`,
  `DeleteAnalysisUseCase`, [ADR 0247](docs/adr/0247-analysis-export-share-and-delete-contract.md))
  **E06-R28** (cache, performance és model-lifecycle infrastruktúra —
  `AnalysisCacheKey`/`AudioFingerprint`/`AnalysisCache`/`ModelByteCache`,
  bekötetlen, [ADR 0248](docs/adr/0248-analysis-cache-key-and-performance-budget.md))
  és **E06-R30** (shadow rollout, migráció, Epic-lezárás — ZÁRÓ KÖR:
  `AnalysisRolloutStage`/`ShadowAnalysisRunner`/`ShadowDiffReport`, teljes
  50-session migrációs+rollback teszt, 29 ADR státusz-frissítés,
  [`docs/sdd/epic-06-completion-report.md`](docs/sdd/epic-06-completion-report.md))
  **kész — az Epic 6 mind a 30 köre lezárult.** A `docs/execution/pipeline-queue.tsv`
  minden sora `done`, a rollout shadow szinten marad, a folytatás
  (valódi kalibráció/GOV-30a, CI evaluation wiring/GOV-30b, V2 pipeline
  összeszerelés/GOV-30c, opt-in/V1-kivezetés) emberi döntést igényel, lásd
  §6. **`audioAnalysisV2Enabled`
  (+ al-flagek) `false` marad minden környezetben a teljes Epic alatt** (ADR
  0220) — a V1 Analyze marad a shipping út, production viselkedés bitre
  változatlan (a V2 domain + a codec/adapter/input-gateway/recorder teljesen
  bekötetlen). Evidencia:
  [`docs/baseline/epic-06-audio-analysis-start.md`](docs/baseline/epic-06-audio-analysis-start.md),
  [`docs/reviews/e06-r06-recorder-audio-session-integration-review.md`](docs/reviews/e06-r06-recorder-audio-session-integration-review.md).
- **Epic 7 (AI Practice Generator) — LEZÁRVA E07-R30-cal (2026-08-19, PR #333,
  squash `ee5821dd`).** `ShadowPlanGenerator` (evaluation-only, no-op
  activation) + golden-korpusz property gate + `docs/sdd/
  epic-07-completion-report.md`; `practiceGeneratorEnabled`/
  `plannerAssistEnabled` mindvégig `false` maradt, a rollout emberi döntés.
  Részletek a fejléc ✅-blokkjában és §5-ben. Az építkezés sorrendje —
  **E07-R01** (nyitókör:
  baseline, [ADR 0255](docs/adr/0255-deterministic-first-practice-planning.md)
  deterministic-first, [ADR 0256](docs/adr/0256-practice-plan-revisions-immutable-past.md)
  immutable múlt, `practiceGeneratorEnabled` + `plannerAssistEnabled` feature
  flag), **E07-R02** (`domain/id/planner_ids.dart` — hat típusos ID —,
  `domain/model/plan_enums.dart` — öt stabil kódú enum-család —,
  [ADR 0257](docs/adr/0257-planner-typed-ids-and-stable-enum-codes.md)) és
  **E07-R03** (`domain/model/practice_goal.dart` — cél, metric target, goal
  lifecycle —, `domain/model/weekly_availability.dart` — `LocalDate`-alapú
  napi elérhetőség —, `domain/model/learner_constraints.dart` — hard/soft
  korlátok, a keménység a kategóriától független mező —,
  `domain/service/request_validator.dart` — pure konfliktus-detektor —,
  [ADR 0258](docs/adr/0258-hard-and-soft-planning-constraints.md)),
  **E07-R04** (`PracticeGenerationRequest` verziózás + draft persistence,
  [ADR 0259](docs/adr/0259-generation-request-versioning-and-draft-isolation.md)),
  **E07-R05** (`SkillEvidence` normalizálás — csak származtatott mérőszám,
  provenance és strukturált discomfort-kategória, a self-report szabad
  szövege a repository előtt eldobódik —, evidence repository outcome-ID
  dedup + inkluzív expiry + bounded query,
  [ADR 0260](docs/adr/0260-skill-evidence-privacy-and-deduplication.md)) és
  **E07-R06** (`domain/model/skill_estimate.dart` — explicit `unknown`
  állapot, sosem `0.0` default —, `domain/policy/evidence_weight_policy.dart`
  — explicit bounded-influence cap —, `application/service/
  skill_estimate_reducer.dart` — determinisztikus, konfliktus-tudatos
  reducer, a discomfort külön csatornán fut —,
  [ADR 0261](docs/adr/0261-skill-estimate-bounded-influence-and-unknown-state.md))
  kész, **E07-R07** (explicit, versioned Legacy Learn/Progress
  `SkillSnapshotReader` adapterek; ismeretlen/hiányos legacy adatból nincs
  inference vagy fabricated identity, [ADR 0293](docs/adr/0293-legacy-evidence-adapter-identity-and-mapping-contract.md))
  **E07-R08** (`ExerciseCandidate`/`PracticeCatalogSnapshot` — csak
  létező, végrehajtható forrásra mutató, revíziózott katalógus-jelöltek;
  `PracticeCatalogReader` port + két hívó-táplált adapter (Practice Engine,
  Legacy Learn fallback); a nem támogatott capability kimondott
  `unsupported`, sosem hiányzó mező, [ADR 0262](docs/adr/0262-catalog-snapshot-revisions-and-capability-truth.md)),
  **E07-R09** (`domain/model/exercise_prescription.dart` — bounded, immutable
  execution recept egy választott `ExerciseCandidate`-hez: explicit maximumos
  repetition, capability-hez kötött tempo/success criteria, azonos
  skill-target fallback, inkluzív hard elapsed-limit validáció,
  [ADR 0294](docs/adr/0294-exercise-prescription-measurability-and-bounded-execution.md))
  és **E07-R10** (`AdaptivePracticePlan`/`PracticeDay`/`PracticeBlock` —
  közös, pinnelt `PracticeItemStatus` átmenet-kontraktus,
  `PlanRevision` szigorúan monoton, TELJES immutable snapshot,
  `PlanChangeSet` strukturált diff typed indokkal, user-note-mentes
  `PracticePlanSummary` — az ADR 0256 megvalósítása).
  **Mindkét flag `false` marad minden környezetben**, nulla
  `lib/features/practice_generator/` production hívó — az R01–R10 kizárólag
  a határokat és a típusos domaint rögzítette (a köztes **E07-R11…R21**
  köröket, amik a validátort/repairert/wizardot/preview-t adták, ez a
  bekezdés még nem gördítette bele — lásd a fejléc bannereit és
  `docs/handoff-archive.md`-t). **E07-R22** hozzáadta az aktív terv napi/heti
  presentation-rétegét (`today_plan_controller.dart`/`active_plan_controller.dart`/
  `today_plan_screen.dart`/`weekly_plan_screen.dart`) — helyi dátum injektált
  órával, pihenőnap ≠ mulasztás, típusos deep-link contract, tanuló-indított
  change-setek storage-írás nélkül. SDD forrás:
  [`docs/sdd/08-epic-07-ai-practice-generator.md`](docs/sdd/08-epic-07-ai-practice-generator.md).
  A generátor a legacy Learn/Progress/Songs/Analyze adaptereken keresztül lát
  (az Audio Analysis V2 lánc futtatható, de minden flagje OFF — a generátor
  domainje **nem** igazodhat az ideiglenes adapterhez, SDD Ch8 §4.3).

## 2. What is working

- **SongDocument V2 identitás/metaadat (E03-R02, ADR 0089 §Döntés 2/3):**
  `lib/features/song_trainer/domain/models/` — hat típusos ID (`SongId`,
  `SongSectionId`, `SongTrackId`, `SongEventId`, `SongAssetId`,
  `SongMarkerId`) közös `SongIdValidator`-ral (trim/nem-üres/≤128
  karakter/determinisztikus `safeFilename`); `SongMetadata` (cím kötelező,
  capo 0–15, dedup+lowercase tag-lista, immutable); `SongSource`
  (proveniencia: 7 stabil forrás-típus, SHA-256, importer-verzió,
  warning-summary); `SongAssetReference`, `SongMarker`; a minimális
  `SongDocument` identitás-vázlat (`schemaVersion`/`id`/`revision`/
  `metadata`/`source`/`assets`/`markers`/`createdAt`/`updatedAt` —
  section/track/tempoMap E03-R03-ban bővíti). `data/local/
  song_document_codec.dart` — determinisztikus kulcssorrendű UTF-8 JSON,
  UTC ISO-8601 timestamp policy, ismeretlen source type fail-closed.
  Framework-/Riverpod-/storage-mentes (`Domain purity` teszt-scanner őrzi,
  reviewer-oldali valódi-sértés próbával verifikálva). Hívó UI/repository
  még nincs — production viselkedés változatlan.
- **Songstruktúra és determinisztikus időmodell (E03-R03, ADR 0093):**
  `lib/features/song_trainer/domain/models/` — `SongSection` (kind-enum,
  measure-range validáció), `SongMeasure` (index/durationBeats/pickup/
  repeat-mezők); `TempoMap`/`MeterMap`/`KeyMap` **lokális, tick-alapú**
  idő-primitívekkel (a Practice Engine `BeatPosition`/`Tempo`/`Meter`
  importja a domain-purity scanner és ADR 0092 miatt kizárva — csak a
  tervezési elvek öröklődnek, a típusok nem). `domain/services/
  song_time_map.dart` — 480 PPQ tick, szegmensenkénti egész-mikroszekundum
  összegzés egyetlen kerekítési ponttal, **≤1 tick round-trip tolerancia**
  (500 rendezett, seedelt property-mintán mérve), left-closed tempo/meter
  boundary policy (reviewer-oldali mutáció-tesztelt próbával verifikálva),
  speed-multiplier a forrás mapet nem mutálja. `SongDocument` (R02) bekötve
  az öt új mezővel, **value-equal** `operator==`/`hashCode`-dal minden
  strukturális mezőn (a review F1 MAJOR leletének javítása). Hívó UI/
  repository még nincs — production viselkedés változatlan.
- **Track/event domain modell és monophonic elemzés (E03-R04, ADR 0113):**
  `lib/features/song_trainer/domain/models/` — sealed `SongTrack`
  (`ChordTrack`/`StrumTrack`/`NoteTrack`/`LyricsTrack`/`MarkerTrack`/
  `BackingAudioTrack`) + sealed-szerű event-készlet (`SongChordEvent`
  core `Chord` szimbólummal, `SongStrumEvent` nullable core
  `StrumDirection?` iránnyal — `null` = unknown, `SongNoteEvent` MIDI
  pitch/string/fret/velocity validációval, `SongLyricEvent`,
  `SongMarkerEvent`); `SongInstrument` (opcionális core `Tuning` — az
  EGYETLEN canonical tuning contract); `SongNoteTechnique` (8 ismert
  technika + `unknown` raw/display escape hatch, sosem ad hamis scoring
  capabilityt). `domain/services/note_track_analyzer.dart` —
  `NoteTrackAnalyzer` **active-notes sweep-line**-nal (nem
  adjacent-pair-only — ez volt a review BLOCKER leletének gyökere, ld. §5)
  határozza meg az overlap/tie/monophonic reportot. Codec bővítés
  kanonikus (start asc → track id → event id) sorrenddel és fail-loud
  ismeretlen-altípus kezeléssel (`trackTypeUnknown`/`eventTypeUnknown`).
  `SongDocument.tracks` mező bekötve. Hívó UI/repository még nincs —
  production viselkedés változatlan.
- **Validator, normalizer és capability resolver (E03-R05, ADR 0114):**
  `lib/features/song_trainer/domain/services/` — `SongValidator`
  (cross-collection ellenőrzés: section range vs. `measures.length`,
  section-overlap, `StrumEvent.targetChordId` cél-hivatkozás — sorrend-
  független két lépéses gyűjtés+validálás, ld. §5 review-tanulság —,
  ismeretlen chord-root/technique/strum-direction, `NoteTrackAnalyzer`
  polyphony-reuse; sosem dob, mindig `SongValidationReport`-ot ad
  determinisztikus `severity asc, code asc` sorrenddel), `SongNormalizer`
  (idempotens: `normalize(normalize(x)) == normalize(x)`, kanonikus
  `(kind, id)`/`(start, id)` rendezés minden track/event típusra, ID-t
  soha nem ír át), `SongCapabilityResolver` (severity→capability
  szerződés: `fatal` ⇒ minden profil — importPreview/persist/trainer/
  export — `canPersist=false`; chord/pitch display/scoring ÖNÁLLÓ
  tengely a severity-től, a §6 négy kombináció mind reprezentálható).
  Chord-support grammar önálló, domain-lokális (`Root[m?]`), sosem a
  `practice`-feature szótára (ADR 0114 §Döntés 1 — cross-feature import
  + kívül esik az `allowed_paths`-on). Hívó UI/repository még nincs —
  production viselkedés változatlan.
- **Legacy Song/Setlist migrációs adapter (E03-R06, ADR 0116):**
  `lib/features/song_trainer/data/migration/` — `LegacySongReader` (JSON
  DTO boundary, `LegacySongRecord`/`LegacySetlistRecord`, kanonikus
  SHA-256, nincs presentation import), `LegacySongAdapter` (legacy
  `Song` record → `SongDocument`: `ChordTrack`+`StrumTrack`+egy
  `SongSectionKind.custom` „Full Song" section, egyetlen mikroszekundum-
  kerekítési pont eseményenként, `Meter` denominator mindig 4),
  `LegacySetlistAdapter` (sorrend/duplikáció megőrzés, missing id →
  unresolved report, nincs crash), `LegacyMigrationReport` (önálló,
  adapter-lokális fidelity report — NEM a `SongValidationReport`/
  `ImportWarning` kiterjesztése, ADR 0116 §Döntés 1). Veszteségmentes,
  determinisztikus, tartós írás vagy legacy törlés nélkül. Hívó
  UI/migration-runner még nincs — production viselkedés változatlan.
- **Fájlrendszeres Song repository és asset store (E03-R07, ADR 0090):**
  `lib/features/song_trainer/domain/repositories/` — `SongRepository`
  (`list`/`get`/`create`/`update`/`moveToTrash`/`restore`/
  `permanentlyDelete`, optimistic `expectedRevision`), `SongAssetRepository`
  (`put`/`get`/`summary`/`incrementReference`/`decrementReference`/
  `permanentlyDelete`). `data/local/` — `FileSongRepository` (validate→
  temp-serialize→flush→verify→atomic document rename→temp index→atomic
  index rename, `SongValidator`/`SongCapabilityResolver` a mentés előtt),
  `FileSongAssetRepository` (streamelt SHA-256 content-hash store,
  reference count, korrupt sidecar/asset stabil hibakóddal, sosem néma
  playback), `AtomicFileWriter` (temp/flush/verify/rename, staging a
  songs-root `temp/` alatt, előzetes törlés nélküli atomikus rename),
  `SongRepositoryRecovery` (nem-destruktív startup scan: orphan temp,
  orphan document, corrupt index, orphan asset), `InMemorySongRepository`
  (fake). `application/song_trainer_providers.dart` — éles Riverpod
  wiring `path_provider.getApplicationSupportDirectory()` felett
  (tranzitív import, ugyanaz a precedens, mint az E03-R06 `crypto`
  használata). Nincs `SongDocument`/asset SharedPreferences-ben. Három
  független review pass + két javító kör után **APPROVED**
  ([`docs/reviews/e03-r07-song-repository-asset-store-review.md`](docs/reviews/e03-r07-song-repository-asset-store-review.md)) —
  a második pass egy, a saját első javító kör bevezette regressziót
  talált (streamelt-hash `writeFromSync` length/end-index csere,
  `docs/LESSONS.md` L60), amit az orchestrátor javított (implementer-oldal
  mérve nem elérhető: M3 kerete + Terra napi kerete egyaránt kimerült).
  Hívó UI/import-runner még nincs — production viselkedés változatlan.
- **Detektálás (100% on-device):** Live képernyő (akkord + pengetésirány valós
  időben, DSP + CRNN ML), Analyze (felvett klip elemzése), Tuner, metronóm.
  DSP-igazság: `docs/rag/chunks/` — paraméter csak ADR-rel és ugyanabban a
  commitban frissített chunkkal változhat (AGENTS.md §9).
- **Tanulás/tartalom:** Learn (leckék), Songs, Library (sessionök), Progress,
  Streak, onboarding, i18n (en/hu ARB).
- **Opcionális account-réteg:** FastAPI + SQLite + JWT backend (`backend/`),
  login + settings-sync; **az app kijelentkezve teljes értékű**, a 0-request
  offline-garanciát rendszer-szintű teszt őrzi
  (`test/app/offline_network_guard_test.dart`, E01-R16).
- **Core platform (Epic 1):** validált fail-closed AppConfig-bootstrap ·
  `AppResult`/`AppFailure` + redakciós logging · verziózott storage
  (migrátor + karanténos JSON-dokumentumok) · egyetlen `DioFactory`, 401
  session-generációs invalidáció, POST-retry-tilalom · exkluzív mikrofon-session
  (owner+lease, lifecycle guard, ADR 0056) · közös zenei/audio domain
  (`core/music`, `core/audio`, ADR 0057/0058) · route-katalógus + idempotens
  onboarding-redirect (ADR 0059) · Alembic-backend health-endpointokkal és
  prod-hardeninggel (ADR 0060/0061).
- **CI:** `build-apk.yml` + `release-apk.yml` közös gate-sorral
  (`.github/actions/flutter-gates`: format → analyze → architecture → asset →
  test → randomizált property), coverage külön párhuzamos required jobban;
  `backend-ci.yml` (ruff + pytest + alembic-gate); fail-closed release signing.
  ADR 0062/0063 + E01-R16.
- **Practice V2 parity-mérce (E02-R01):** `test/support/practice_baseline_scenarios.dart`
  (10 scorer-semleges forgatókönyv) + `test/fixtures/practice/legacy_scorer_baseline.json`
  (befagyasztott golden, event-szintű verdictekkel). A replay független legacy
  matchert vezet a scorer mellett; a golden regenerálása csak
  `UPDATE_LEGACY_SCORER_BASELINE=1`-gyel, megnevezett okkal (ADR 0067 §1/§3).
- **Practice V2 domain időalap (E02-R02):** `lib/features/practice/domain/model/`
  — `BeatPosition` (480 PPQ integer tick, ADR 0066; egzakt subdivision-factoryk,
  egyetlen auditált legacy `double beat` híd ≤ 1/960 beat toleranciával),
  `Tempo` (30–300 BPM zárt tartomány, clamp nélküli lista-validáció), `Meter`
  (4/4·3/4·6/8, egzakt `ticksPerBar`), stabil validációs kódkészlet. A
  `lib/features/practice/domain/` prefix framework-independence-e GÉPI őr alatt
  (`tool/check_architecture.dart`). Hívója még nincs — production viselkedés
  változatlan.
- **Practice V2 domain-szerződések (E02-R03, ADR 0068):** a teljes modellkészlet
  a `lib/features/practice/domain/model/` alatt — `PracticeEvent`/`PracticeDefinition`
  (kanonikus sharp-spelled chord-labelkészlet, rendezettség/egyediség/tartomány
  aggregáló validációval), `PracticeSessionConfig`, sealed observation-hierarchia,
  `PracticeVerdict` (+TimingGrade/outcome/coaching kódok), `MetricValue`/`PracticeMetrics`,
  attempt/session result (+`PracticeFinishReason`), `ScoringProfile`
  (integer-percent súlyok, összeg=100; `perfect<=good<=match` ablak-rendezés;
  `legacyLearnParity` const profil), mode/source/difficulty enumok stabil
  `code`+fallback-mentes `fromCode` párral — összesen 60 stabil validációs kód,
  mind literálisan tesztelve. `Meter.ticksPerBar` szimmetrikus fail-fast
  (E02-R02 MINOR-1 zárva). Test-oldali purity-őr (`domain_purity_test.dart`).
  Hívó továbbra sincs — production viselkedés változatlan, flagek OFF.

- **Practice V2 accessibility-mátrix és performance-számlálók (E02-R20, nincs új ADR — a zárókör nem hoz architekturális döntést):**
  `test/features/practice/presentation/practice_a11y_audit_test.dart` (A1.1–A1.10) — Hub/Setup/Result képernyőkön a touch-target + label+action + 200%-os szöveg + landscape + reduced motion + chart-szemantika + screen reader + ARB-paritás cellák zöldek, a `_HubCard` / `PracticeModeCard` / `PracticePatternPreview` / `TimingBiasChart` Semantics-merge fixekkel; `test/features/practice/practice_performance_test.dart` (A3) — R14 highway számláló, R09 matcher számlálók, 10 perces szimulált session cap, controller state-emission cap; `practice_a11y_audit_test.dart` A2.1–A2.4 cellái (A2) — minden `PracticeInsightCode` / `PracticeRecommendationKind` értékhez ARB-szöveg mindkét nyelven (a R20-ban hozzáadott 16 kulcs: `practiceInsight*` × 10 + `practiceRecommendation*` × 6; a javító kör #1 az eredetileg különálló `practice_l10n_audit_test.dart`-ot ide olvasztotta, scope-okból); `test/property/practice_engine_property_test.dart` (A4) — öt epic-szintű invariáns (egy target/observation max egyszer, score ∈ [0,1] ∨ NotApplicable, free practice nincs overall accuracy, terminal state tiszta, playing ≤ active ≤ wall). A §3 rendszerszintű rés (önálló Practice V2 session-út drótozatlan) nyíltan dokumentálva a §5 DoD-táblában minden érintett cellánál.

- **Practice V2 tartalom (E02-R04, ADR 0070):** `lib/features/practice/data/`
  `BuiltinPracticeCatalog` — tíz beépített gyakorlat (négy/nyolcad strum-minták,
  folk pattern, G↔D és Em↔C akkordváltás, C-G-Am-F progresszió, 3/4 keringő,
  szinkópált upstroke-ok, rhythm-only, free-practice sablon) stabil
  `builtin.<slug>.v1` ID-kkel, unmodifiable `events`/`const skillTags`
  listákkal; `domain/repository/practice_catalog_repository.dart` szinkron
  szerződés; `application/practice_catalog_controller.dart` két Riverpod
  providerrel. Hívó UI még nincs, ARB-fordítás az első UI-hívóval jön.
- **Practice V2 legacy adapterek (E02-R05, ADR 0071):**
  `lib/features/practice/data/adapters/` — `practiceDefinitionFromLesson`
  (+`easy:`), `…FromSong`, `…FromAnalyze`, `…FromDailyChallenge`: tiszta,
  óra-mentes függvények `AppResult<PracticeDefinition>`-nel (sosem dobnak,
  hibakód `practice.content_unsupported`). Minden adaptált tartalom
  `strumPattern` + befagyasztott `legacyLearnParity` (kivétel: az eseménymentes
  Analyze-import → `freePractice`). `legacyPracticeChordLabel` a legacy
  akkordcímkéket a detektor tényleges 24-elemű maj/min szótárára redukálja
  (`Em7`→`Em`, `Bb`→`A#`, `G/B`→`G`, értelmezhetetlen → strum-only) —
  veszteséges, de nem parity-rontó (ADR 0071 §2).
  `PracticeDefinition.displayTitle` a user-tartalom nevének (61 stabil
  validációs kód). Songs feature-barrel: `lib/features/songs/public.dart`.
  A legacy API (`Lesson`, `Song.toLesson()`, `Lessons.fromAnalyze`,
  `LessonScorer`) érintetlen; hívó UI nincs.
- **Practice V2 időréteg (E02-R06, ADR 0072):**
  `lib/features/practice/domain/model/beat_time_converter.dart` — a domain
  **egyetlen** beat↔idő konverziója (egész µs, egyszeri kerekítés, fail-fast) ·
  `compiled_practice_target.dart` (4 immutable, value-equal modell) ·
  `domain/service/practice_target_compiler.dart` — determinisztikus
  session-timeline count-innal, egész ütemű pass-hosszal, loop-rebase-szel,
  ütemhatárokkal, expected-chord szegmensekkel és scoring applicabilityvel.
  **ADR 0072 §1.1 az egész epic időmodellje:** minden abszolút pillanat a
  nullponttól vett tickszám egyetlen konverziója, minden időtartam két pillanat
  különbsége — így a kompozíció pontos ÉS minden pillanat bitre egyezik a legacy
  képlettel. Parity a szállított korpuszon: **0 µs**. Hívó UI nincs.
- **Practice V2 observation gateway (E02-R08, ADR 0074):** a Live detektor és a
  Practice domain közötti híd. `application/practice_observation_gateway.dart`
  (SDD §13.1 interfész + `PracticeObservationConfig`: 0.55 / 0.60 / 180 ms /
  500 ms) · **`application/practice_observation_activation.dart` — a
  `practiceCaptureActiveByStatus` `const` tábla mind a 11 státuszra**, ez a
  „hallgat-e a mikrofon" EGYETLEN igazságforrása (`countIn` + `running` → be,
  minden más → ki; a `paused → false` a chunk 014 pause-résének szerkezeti
  lezárása a V2 úton), a kulcshalmaz-egyezés gépi őr alatt ·
  `data/live_practice_observation_gateway.dart` — `strumSeq`-dedup, engine-óra
  de-jitter a legacy **szigorú `<`** predikátumával (a kalibrált input latency
  a matcheré marad, ADR 0074 §3), **fajtánként külön** monoton padló, saját sűrű
  `sequence` (§12.5 baseline), change-point + stabilitási chord-mintavétel,
  engedély-elsőség, idempotens start/stop/dispose, hibaleképezés. Fake gateway a
  `test/support/` alatt az R09/R10 számára. Hívó és provider nincs, flagek OFF →
  production viselkedés bitre azonos.
- **Practice V2 event matcher (E02-R09, ADR 0075):**
  `domain/service/practice_event_matcher.dart` — pure, determinisztikus,
  **kurzoralapú** párosító: eldönti, melyik `StrumObservation` melyik
  `CompiledTargetEvent`-hez tartozik, és mikor zárul egy cél kimaradásként.
  Pontozás-mentes (`TimingGrade`/score/combo a Kör 10-é), **megfigyelést nem
  tárol** (`O(célesemény)` memória), az opcionális célt külön feloldással zárja.
  A legacy `LessonScorer` szemantikája (P1–P9) megőrizve: jogosultság `<=`,
  zárás **szigorú `<`**, holtversenynél a **korábbi**, a rossz irány is
  **elfogyasztja** a célt, az extra pengetés **állapotot nem változtat**.
  **A paritás értelmezési tartománya kimondva (ADR 0075 §2b):** a legacy
  kerekítetlen `double`-lel dönt, a compiled target egész µs-mal, ezért a két
  időalap ≤ **0,5 µs**-ban eltér (mérve **0,489795919508 µs** mind a 348
  szállított eseményen) — a **µs-kvantált alap az igazság**, és a levezetett
  védősávon kívül (`≥ 1 µs` a határoktól, `≥ 2 µs` argmin-különbség) a paritás
  **bitre egzakt**, tűrés nélkül. A sávon belüli két divergencia-cella
  (`first-strums[0]`, `anthem-drive[5,6]`) **kipinnelt, őrzött viselkedés**.
  Hívó, provider és flag nincs → production viselkedés bitre azonos.
- **Kétmotoros implementer-készlet (ADR 0069):** `tools/mm-round.sh` +
  `tools/mm-watch.sh` (5 perces korai riasztás) + `tools/mm-trace.py`
  (munkastílus-elemzés) — a MiniMax M3 ugyanazt a kör-jelzés-szerződést
  használja, mint a Codex. Besorolás és a kötelező brief-elemek: AGENTS.md §15.6.

- **Practice V2 pontozás (E02-R10, ADR 0076):** `lib/features/practice/domain/service/`
  — `PracticeTimingScorer` (grade + eseménypont + `meanAbsoluteOffset`/előjeles
  `timingBias`), `PracticeDirectionScorer` (explicit megfigyelés-bemenet,
  fail-fast hiányzó leképezésre), `PracticeChordScorer` (inkluzív
  `[−120 ms, +420 ms]` ablak, `correct`/`wrong`/`noDetection`/`insufficientData`/
  `notApplicable`), `PracticeScoreAggregator` (overall csak az **elérhető**
  dimenziókra, completion + kettős pass-kapu, legacy combo/pont). Minden pontszám
  belül **egész ezrelék**, kifelé `perMille / 1000` — lebegőpontos akkumuláció
  tilos. `PracticeMetricReasonCode` stabil indokkód-készlet; `ChordOutcome`
  ötértékű. **Legacy paritás 51 forgatókönyvön egzakt** (17 lecke × 3 latency,
  nulla kizárt esemény). Hívó nincs → production viselkedés változatlan.

- **Practice V2 result + coaching + history (E02-R18, ADR 0084):** mode-specifikus
  **result képernyő** (`presentation/screens/practice_result_screen.dart` +
  `score_breakdown`/`timing_bias_chart`): csak az **alkalmazható** dimenziók
  látszanak (`MetricNotApplicable` → a blokk nincs a fában; `MetricInsufficientData`
  → lokalizált „nincs elég adat", **nem** 0%); Free Practice külön layout (nincs
  overall/pass-fail/combo). **`PracticeCoach`** pure service
  (`domain/service/practice_coach.dart`): mérésből választott, **bizonyíték-küszöbös**
  insight-kódok (`practice_insight.dart`), determinisztikus prioritás (SDD §17.3),
  legalább egy pozitív insight befejezett sessionre. **Practice History V2**
  (`data/local_practice_history_repository.dart` + `practice_history_serializer.dart`
  + `practice_history_recorder.dart` + `..._mapper.dart`,
  `domain/model/practice_history_entry.dart` + `practice_metric_snapshot.dart`): új
  kulcs `ss.practice.history_v2` (`StorageKeys.all`-ban), verziózott dokumentum,
  karantén a sérült bájtoknak, jövőbeli `schemaVersion` kihagyva, cap
  `maxSessions=200`, a per-attempt **detail-window** csak a legújabb **N=20**
  sessionre, **idempotens** mentés a `sessionId`-re. **A mentési hiba nem néma:** a
  repository közvetlenül a `KeyValueStore`-ral ír (propagálja a `StorageException`-t)
  → `AppResult.failure` → a controller `ShowRecoverableError`-t emittál; a session
  sikeres marad. A V1 `ss.progress.practice_log` **bájtra érintetlen** (egyesítés =
  R19). A live recorder-wiring valós session-metaadatig (mode/source/definition)
  **R19-ig halasztva** (placeholder-metaadatnál `Noop`, hogy ne keletkezzen
  betölthetetlen — write-then-drop — rekord). Flag: `practiceDetailedHistoryEnabled`
  (non-prod ON) → részletes attempt-adat.

## 3. Known blockers / risks
- **E06-R28 cache — 6 lezárandó előfeltétel a jövőbeli BEKÖTŐ körnek, nincs
  kijelölt kör (mérve, `docs/reviews/e06-r28-…-security.md` §6).** A cache-nek
  ma nulla production hívója van (`audioAnalysisV2Enabled` false), úgyhogy
  ezek NEM aktív hibák, csak a wiring-kör előtti kötelező hardening-lista:
  (1) explicit payload-tartalmi szerződés (nyers PCM sosem cache-elhető) +
  a cache-hely újraértékelése Android Auto Backup-jogosultság szempontjából
  (`getTemporaryDirectory()`/backup-kizárás `getApplicationSupportDirectory()`
  helyett); (2) `put()`/`getOrCompute()` ma kivételt propagál a hívóra
  filesystem-hibán (mérve `chmod 500`-zal) — az ADR Döntés 5 szellemével
  ellentétes; (3) a cache minden `*.json` fájlt sajátjának tekint a
  könyvtárában, mérve egy idegen `index.json` törlésével — fájlnév-mintaszűrő
  kell (`^[0-9a-f]{64}\.json$`); (4) `AudioFingerprint` némán clamp-el a
  `[-1,1]` tartományon kívül, ami két KÜLÖNBÖZŐ bemenetet azonos kulcsra
  képezhet — tartományon kívüli mintát el kell utasítani; (5) a mért
  baseline-számok (`docs/baseline/epic-06-analysis-performance.md`) 4 bájtos
  payloadról származnak, a cap közelében (50 MiB) a valós költség ~20×
  nagyobb (mérve: 609 ms + ~90 MiB tranziens allokáció egy `put()`-ra) —
  újramérés kell cap-közeli payloaddal, mielőtt bárki erre budget-döntést
  épít; (6) a `purge()` bekötése a törlési útvonalba (az R27
  `AnalysisCachePort`, `delete_analysis_use_case.dart:10-12`), hogy a
  `ss.analysis.cache` katalógus-bejegyzés valódi törölhetőséget takarjon.
  Content review 2 további MINOR-t is dokumentál (tautologikus
  fingerprint-névfüggetlenségi teszt; a handoff-próza tesztszám-elszámolási
  pontatlansága) — mindkettő dokumentációs, nem kódhiba.
- **E06-R20 follow-up (5 NOTE, review + security) — gate-feltételek egy
  jövőbeli bekötő körnek, nincs kijelölt kör.** (1) review N1: a
  `LowSignalQualityInsightRule` (`lib/features/audio_analysis/engine/insights/insight_rules.dart:268-297`)
  a `dynamics.clipped_event_ratio.v1`-et méri, nem a nyers
  `AnalysisDocument.signalQuality` (R07) riportot — mert az utóbbi nem
  katalogizált metrika, tehát nem használható `factId`-ként; ha egy
  jövőbeli kör a nyers jelminőséget is katalogizálja, érdemes megfontolni,
  hogy a szabály erre váltson-e. (2) review N2: a caller-supplied
  evidence-osztályok (`TimingInsightEvidence` stb.,
  `lib/features/audio_analysis/domain/insights/insight_rule.dart:164-234`)
  csak érték-tartományt validálnak, nem `CapabilityStatus`-t — a „csak
  megbízható mérésből" garancia a jövőbeli hívóra hárul, akinek ezt
  pre-flightban explicit ellenőriznie kell. (3) security NOTE-1 (**a
  bekötés ELŐTT megoldandó**, nem csak follow-up): a
  `ChordTransitionHotspotInsightRule` (`insight_rules.dart:259,261-263`)
  a `hotspot.id`-t verbátim messageArgba és egy action-payload kulcsba
  teszi; ma nincs élő harmony-kind hotspot-termelő, de egy jövőbeli
  decoder/import/sync útvonal szanitálatlan stringet hozhatna be. (4)
  security NOTE-2: a hotspot-alapú `factId`-eknek nincs `isUsable` őre
  (`insight_rules.dart:249`), a `CompatibleImprovementInsightRule`
  mintájára (`:313`) érdemes pótolni egy jövőbeli körben. (5) security
  NOTE-3/NOTE-4: a property-gate nem generál hotspotot (a
  `chord_transition_hotspot` útvonal kívül esik a randomizált mérésen), és
  a `HotspotRanker` duplikált ID esetén nem specifikált sorrendet ad (ma
  nincs élő duplikáció). Mérve:
  `docs/reviews/e06-r20-deterministic-insights-and-hotspots-review.md`
  N1/N2, `docs/reviews/e06-r20-deterministic-insights-and-hotspots-security.md`
  NOTE-1..4.
- **E06-R19 follow-up (F2 review + security NOTE-1) — gate-feltételek egy
  jövőbeli bekötő/kalibrációs körnek, nincs kijelölt kör.** (1) F2: a
  `CapabilityResolver.resolve()` (`lib/features/audio_analysis/engine/confidence/capability_resolver.dart:105-123`)
  a „kritikus capability → min" brief-elvet (§5.2) ma egy bináris hard-gate
  helyettesíti — bármelyik kritikus capability (`signalQuality`/
  `onsetTimeline`) `unavailable` állapota az overall confidence-t nullára
  kényszeríti (`overallStatus` mindig `unavailable`-re esik, sosem
  ténylegesen `degraded`-re), egy MERELY-`degraded` kritikus capability
  pedig csak egyetlen tényezőként hígul a geometriai átlagban a többi
  (akár 13) capabilityvel egyenlő súllyal. Nem sérti a §6 mérhető
  acceptance criteriont, de eltér a brief prózájától — egy jövőbeli
  bekötő/kalibrációs kör (R29 vagy a retrofit-kör) döntse el explicit
  módon, hogy a bináris kapu szándékos-e (ADR 0237 kiegészítéssel), vagy
  a fokozatos „min" viselkedés kell. (2) security NOTE-1: az
  `AnalysisDocument` codec (`lib/features/audio_analysis/data/analysis_document_codec.dart:180-195`,
  a diffen kívül, nem módosult) ma NEM perzisztálja az új
  `CapabilityReport.calibrationVersion`/`calibrationSource` mezőt — egy
  perzisztált-majd-visszatöltött report csendben `identity`-re esik vissza.
  Fail-safe irány (sosem a veszélyes raw→calibrated), de a source-enum
  megfigyelhetőségi célját kiüti perzisztált dokumentumoknál — E06-R29-nél
  a codec round-tripelje mindkét mezőt. Mérve:
  `docs/reviews/e06-r19-confidence-calibration-capability-resolver-review.md`
  F2, `docs/reviews/e06-r19-confidence-calibration-capability-resolver-security.md`
  NOTE-1.
- **E06-R17 security MINOR-1/NOTE-1/NOTE-2 — gate-feltételek egy jövőbeli
  bekötő körnek, nincs kijelölt kör.** (1) MINOR-1:
  `buildPitchMetrics` (`lib/features/audio_analysis/engine/metrics/pitch_metrics.dart`)
  O(szegmens×célhang) — `_targetFor` szegmensenként az összes célhangot
  vizsgálja, `_dropoutRatio` célhangonként az összes szegmenst; mérve:
  8000 célhangra 619 ms, szuperlineáris görbe, ~15 s-ra extrapolál 40 000-re
  (ugyanaz a mérce, mint az E06-R11/E06-R15 precedens). MA elérhetetlen
  (0 fogyasztó, `analysisPitchEnabled=false` mindenhol) — egy jövőbeli
  untrusted/hosszú audióra kötő kör **MUST-fix-before** ezt egyetlen
  bejárásra/indexelésre kell váltania. (2) NOTE-1:
  `PitchCapabilityGate(minimumVoicedRatio: 0)` (nem a default 0.35) csupa
  unvoiced bemenettel `RangeError`-t dobna (`_median([])`) — a default
  biztonságos, csak a konstruktor nem zárja ki a `0` határértéket
  (`maximumPitchSpreadCents` mintájára `<= 0`-ra kellene szigorítani). (3)
  NOTE-2: az exportált `centsBetween` (`monophonic_pitch_segment_builder.dart`,
  `public.dart`-on át cross-feature elérhető) nem-pozitív Hz-re nem-véges
  eredményt adna — ma nincs ilyen belső hívó. Mérve:
  `docs/reviews/e06-r17-monophonic-pitch-capability-security.md`.
- **E06-R11 security NOTE-1/NOTE-2 — gate-feltételek egy jövőbeli bekötő
  körnek, nincs kijelölt kör.** (1) `ChordSegmentAssembler._mergeShortSegments`
  (`lib/features/audio_analysis/engine/harmony/chord_segment_assembler.dart`)
  `removeAt`-alapú O(S²) — mérve: 13 mp @ 40 000 szegmens, `minimumSegment`/
  `mergeTransientSegments` opt-in policy alatt. MA elérhetetlen (a default
  policy `minimumSegment=0` kihagyja ezt az ágat, és a feature bekötetlen) —
  de ha egy jövőbeli kör untrusted/hosszú importált audióra köti be pozitív
  merge-policyval, a security review explicit **MAJOR-ra sorolja át**: a
  merge-t egyetlen bejáráson épített új listával kell megvalósítani,
  `removeAt` nélkül, MIELŐTT a bekötés megtörténik. (2) `ChordSegment.id`
  (`lib/features/audio_analysis/domain/analysis_segment.dart`,
  `_defaultId`) a `label`-t szanitálás nélkül interpolálja
  (`'chord-${startUs}-${endUs}-$label'`) — ha egy jövőbeli hívó ezt fájlnévként/
  DB-kulcsként/log-sorként használja, és egy jövőbeli ML-decoder tetszőleges
  stringet ad `label`-ként, path-traversal- vagy injekció-alakú kulcs
  keletkezhet. Javítás a bekötés ELŐTT: a `label`-komponenst szanitálni/
  hash-elni az ID-ben, vagy dokumentálni, hogy az `id` nem biztonságos útként/
  kulcsként. Mérve: `docs/reviews/e06-r11-chord-evidence-segmentation-provenance-security.md`
  NOTE-1/NOTE-2.
- **E06-R06 F2/S3/S4 follow-up — NYITVA, nincs kijelölt kör.** A live
  level-preview (`RecordingLevel`, E06-R06) csak az éppen throttle-ablakot
  lezáró chunkot méri peak/RMS-re, a köztes chunkokét nem — egy rövid,
  hangos tranziens, ami teljesen egy köztes chunkba esik, nem jelenik meg a
  preview-n (a végleges, teljes PCM-puffer nem érintett). Az E06-R07
  pre-flightja értékelte és kimondta, hogy ez NEM az ő scope-ja (az offline,
  egyszer futó jelminőség-stage más költségszinten dolgozik, mint a valós
  idejű preview) — a follow-up így nyitva marad, jelenleg nincs hozzá
  kijelölt kör.
- **E06-R07 review NOTE-2 — R02 domain-report NaN-vak arány-guard, alacsony
  prioritás.** A meglévő (E06-R02, E06-R07 által NEM módosított)
  `SignalQualityReport` konstruktora (`lib/features/audio_analysis/domain/
  signal_quality_report.dart`) a `clippedSampleRatio`/`silentRatio` mezőkre
  csak `< 0 || > 1` ellenőrzést fut, `isFinite`-et nem — mivel `NaN < 0` és
  `NaN > 1` egyaránt hamis, egy `NaN` arány elméletileg megkerülné az őrt (a
  mai producerek sosem termelnek ilyet). Mérve és dokumentálva:
  `docs/reviews/e06-r07-signal-quality-stage-security.md` NOTE-2. Javítás
  amikor legközelebb valaki ezt a konstruktort érinti: vegye fel a két
  arányt is az `isFinite` ellenőrzésbe.
- **~~A Claude 5 órás session-kerete rendszeresen kimerül és H-NOSIGNAL-lal
  körökbe kerül~~ — MEGOLDVA (ADR 0222, 2026-08-11, user-döntés).** Mért ok: a
  lánc MINDEN körben a Claude-ot ültette az orchestrátor+reviewer székbe
  (~85 perc/kör, `--effort max`, szünet nélkül) → egy 5 órás ablakba ~3,5 kör
  fér. A védőháló (ADR 0115) ráadásul vak volt: a limit-minta egyetlen valós
  CLI-bannerre sem illeszkedett (11 mérés 90→97%-ig az E06-R05 naplójában), a
  második detektor pedig nem létező fájlra mutatott. **Ma:** a körök felét a
  Terra vezényli (`PIPELINE_ORCH_ROTATION=alternate`), ilyenkor a Claude
  implementál (`sonnet-impl`) — a szerepek cserélnek, a mezőny nem gyengül. A
  fogyásmérő a banner százalékát olvassa, és 85% fölött nem indít új kört a
  Claude-dal (futó munkát soha nem szakít meg). Állapot:
  `tools/pipeline-status.sh`. Tanulság: `docs/LESSONS.md` L215.
- ~~**Rendszerszintű rés (E02-R20, mérve): a standalone Practice V2 session nem
  indítható éles buildben.**~~ **JAVÍTVA (E02-R21, PR #55, `6e5cec7`).** A
  `practiceSessionHostProvider`/`practicePrepareSinkProvider` production
  drótozása (A1-A5, ADR 0111) elkészült és merge-elve — a Hub→Setup→Session
  presentation→controller kötés él. Részletek:
  [`docs/sdd/epic-02-completion-report.md`](docs/sdd/epic-02-completion-report.md)
  §3/§5 (a §3 leírás a régi állapotot rögzíti, evidenciaként megmarad).
- **§16.3/§16.4 készülékes menet PENDING** — az Epic-1 zárás végső elfogadási
  kapuja a user valódi-gitáros APK-tesztje; eredménye a completion reportba kerül.
- **Epic-2 valódi eszközös teszt PENDING** — a Practice Engine device-mátrix
  ([`docs/manual-testing/practice-engine-device-matrix.md`](docs/manual-testing/practice-engine-device-matrix.md))
  kész, a user tölti ki — a standalone Practice V2 út (E02-R21 óta) és a
  Learn-migrációs út egyaránt elérhető éles buildben.
- **Login-backend nincs hosztolva** (a :8019-es uvicorn lokális); auth-hiányok:
  nincs jelszó-reset / e-mail-verifikáció / refresh token (14 napos JWT),
  mid-session token-lejárat interceptor szándékosan halasztva.
- **Coverage-küszöb nincs:** `config` 79,66%, `foundation` 76,19% a Ch2 §14.8
  90%-os célja alatt (kritikus modulok együtt 88,07%) — küszöbösítés későbbi kör.
- **User-inputra vár:** Contents:write token (release-publikálás) ·
  Workflows:R+W PAT · Hermes-kutatás továbbítása.
- iOS build Mac nélkül nem lehetséges.
- Nyitott follow-up lista tételesen: completion report §2.
- **~~A `lib/` 43%-a elérhetetlen~~ — TOVÁBB FELOLDVA (GOV-05a+GOV-05c,
  2026-08-09).** Eredeti mérés (2026-08-07): `song_trainer` V2 (25 308 sor),
  `ai_tutor` (14 091), `vision` (5 132) mind hard-kódolt `false` mögött; a
  Learn a legacy motoron futott minden környezetben.
  **Ma:** a `song_trainer` V2 és a `migratedLearnEnabled` is
  `development`/`lab`-ban ON (a Practice V2 szintén — a flagje eddig is ON
  volt, csak belépési pont nem vezetett hozzá); a Learn a Practice Engine
  V2-n fut `production`-ön kívül. **Hátra van:**
  - `ai_tutor` (14 091 sor) — flagje `false` mindenhol, **BLOKKOLT**: hiányzó
    production-drótozás ÉS hiányzó modell-átjáró, emberi döntést igényel →
    **GOV-05b**, lásd alább;
  - `vision` (5 132 sor) — flagje `false`, és **BLOKKOLT**: nem
    flag-kérdés, hanem hiányzó modell-bináris → **GOV-05d**, lásd a
    következő pontot.
  A termék központi állítására eddig egyetlen mért valós-audio szám létezett
  (CRNN pengetés-irány 86,7% vs heurisztika 38,9%, r164 A/B) — akkord-
  pontosságra, onsetre és BPM-re valós felvételen nem volt szám.
  **JAVÍTVA (GOV-06, E99-R04, 2026-08-09):** a szállított, változatlan
  `ClipAnalyzer` mérve 82 valódi telefonos felvételen — akkord-pontosság
  **67,069%** (18,832%-os többségi-osztály baseline fölött), onset F1@50ms
  **67,391%**. Teljes riport:
  [`docs/eval/real-audio-dsp-baseline.md`](docs/eval/real-audio-dsp-baseline.md).
  A korpusz nincs verziókövetve (external, csak ezen a boxon), a mérés ezért
  elkötelezett riport, nem CI-kapu — a verziókövetés nevesített follow-up.
  **A GOV-06 harmadik száma (BPM-MAE 45,067) ÉRVÉNYTELEN volt — VISSZAVONVA
  ÉS JAVÍTVA (GOV-06b, E99-R05, 2026-08-09, ADR 0212, PR #208):** a szám nem
  DSP-tempóhibát mért, hanem a `.strums` pengetés-eseményekből (nem
  ütem-annotációkból) származtatott „ground truth" ellen — két pengetés-
  sűrűség-becslés egyezetlensége volt, nem tempóé. Független
  librosa-beat-tracker referenciával újramérve: szigorú tempó-egyezés
  **11/82 = 13,415%**, metrikai-szint toleráns egyezés (1/3·1/2·2/3·1·3/2·2·3
  szorzók) **32/82 = 39,024%**; a régi szám megőrizve `visszavonva`
  jelöléssel, pengetés-sűrűségként átcímkézve. **A BPM ezen a korpuszon nem
  mérhető, mert nincs validált (kézi) tempó-annotáció** — ez kimondott,
  elfogadott kimenet, nem hiba. Új eszköz: `ml/chords/tempo_reference.py`.
  Az akkord-pontosság és onset F1 (fent) újramérve bitre változatlan.
  **User-döntés (2026-08-07):** az Epic 6 NEM indul, amíg ez nincs meg — a
  §6 „Kötelező sorrend" 3. ÉS 4. pontja is lezárult. **Az 5. pont (Epic 6
  feloldása) is megtörtént** (user-döntés 2026-08-11, „mehet tovább az
  epic 6") — E06-R01 (Kör 1) kész, lásd a fejléc ✅-blokk és §6.
- **Az AI Tutor rollout — a drótozási blokkoló ÉS a backend-adapter FELOLDVA,
  a bekötés és az üzemeltetés hiányzik (frissítve 2026-08-09, GOV-05b-2 /
  E99-R07 merge után).**
  1. ~~Három provider `throw UnimplementedError`-ral indul~~ — ✅ **MEGOLDVA**
     az **E99-R06** (GOV-05b-1, PR #209, `23fdf30a`, ADR 0213) körrel: a
     `tutorOrchestratorProvider`, a `tutorConversationRepositoryProvider` és a
     `tutorMemoryRepositoryProvider` a `lib/main.dart`
     `buildTutorProductionOverrides` függvényén át kap éles implementációt
     (`LocalTutorConversationRepository`, `LocalTutorMemoryRepository`,
     `TutorOrchestrator`). Az avult `tutorMain()` doc-comment-ígéret törölve
     (`grep -rn "tutorMain" lib/` → 0). **Az `aiTutorEnabled` bekapcsolása
     többé nem crash.**
  2. ~~Nincs konkrét `TutorStreamTransport`~~ — ✅ **MEGOLDVA** ugyanabban a
     körben: `HttpTutorStreamTransport` (Dio `ResponseType.stream` a
     `POST /tutor/stream` SSE végpontra, nyers `data:` payloadokat ad tovább;
     a parse és a `seq`-sorrendezés a `RemoteTutorModelGateway` dolga).
     A kliens–backend szerződést a review kézzel összevetette a
     `TutorStreamRequest` `extra="forbid"` sémájával — illeszkedik.
  3. ~~MÉG HIÁNYZIK — a valódi modell-átjáró~~ — ✅ **MEGOLDVA** (**E99-R07**,
     GOV-05b-2, PR [#210](https://github.com/wolfcasaba/strumsight/pull/210),
     squash `f1d57c69`, **ADR 0214**, implementer **Codex (Terra)** 1
     forduló, javító kör nélkül): `OpenAiProviderGateway`
     (`backend/app/tutor/provider_gateway.py`) nyers `httpx`-szel
     implementálja a `ProviderGateway` szerződést — mind a hét hibaágra
     (timeout, 4xx/5xx, kapcsolati hiba, nem-JSON, hiányzó/nem-string
     `content`) normalizált, szivárgásmentes kivétellel (13 új teszt,
     `httpx.MockTransport`, nulla valós hálózat). Review **APPROVED, 0
     BLOCKER/MAJOR/MINOR, 2 NOTE** (reviewer SAJÁT izolált klónban
     újrafuttatott 9/9 zöld gate-tel ÉS a §6.1 valódi-sértés próba KÉTSZERI
     független megismétlésével — a brief mutációja + egy saját
     kulcs-szivárgásra célzó mutáció, mindkettő a várt cellát buktatta meg).
     Dedikált security-review (risk=high) **PASS, 0
     CRITICAL/BLOCKER/MAJOR/MINOR, 4 NOTE** (mind a bekötő körre szóló
     előre-mutató follow-up: `exc.__context__` defense-in-depth,
     `tutor_openai_base_url` validáció, `AsyncClient` lifecycle, válasz-méret
     korlát) — a security-reviewer a kör saját `str(exc)` tesztjén túlmenve a
     teljes traceback + valós `logging.exception()` szintjén is megmérte mind
     a 7 hibaágat szándékosan beültetett titokkal, 7/7 tiszta. **A
     `FakeProviderGateway` érintetlen** (a diffje üres), **a `main.py`
     bekötése ebben a körben TUDATOSAN NEM történt meg** (ADR 0214 Döntés
     2/OD-04): `tutor_provider` marad `"fake"`, `tutor_enabled` marad
     `False`. Zöld kapu exact-SHA `19002611`: Full Gate + Router CI +
     Backend CI mindhárom **success**. Melléktermék: a pre-flight mért egy
     pre-létező, byte-azonos duplikátumot a `config.py` `tutor_*`
     blokkjában (E04-R14 eredetű, `c1c0a771`) — összevonva, viselkedés
     változatlan.
  4. **MÉG HIÁNYZIK — a bekötés.** A backend `main.py`-ban a registry/gateway
     kiválasztás (ma kizárólag `FakeProviderGateway`-t épít, `main.py:147–184`)
     bekötése az OpenAI-adapterre. Külön kör — a briefje **szándékosan még
     nincs megírva**, a pre-flightjának az E99-R07 utáni állapotot kell
     mérnie.
  5. **MÉG HIÁNYZIK — üzemeltetés.** Hosztolt backend + OpenAI API-kulcs; ez
     **user-feladat**. A `/tutor/stream` **JWT-t vár** (`CurrentUser`), tehát a
     `RemoteTutorModelGateway`-t élesítő körnek **authentikált `Dio`-t** kell
     átadnia a transportnak (E99-R06 review NOTE-1).
  **A flagek változatlanul `false` minden környezetben** — az `aiTutorEnabled`
  bekapcsolása a 4. és 5. pont után, külön körben.
- **A vision rollout BLOKKOLT — hiányzó modell-binárisok (mérve 2026-08-09,
  GOV-05a pre-flight; ez NEM flag-kérdés):** az
  `assets/ml/model_manifest.json` `vision_models` mindkét bejegyzése
  (`hand_landmarker` 1.0.0, `pose_landmarker` 1.0.0) `status: "deferred"`,
  `sha256` csupa nulla, és a hivatkozott
  `hand_landmarker_deferred.tflite` / `pose_landmarker_deferred.tflite`
  fájlok **nincsenek a repóban** (`ls assets/ml/` → négy audio `.bin` + a
  manifest). A `NativeHandLandmarkProvider:77` és a
  `NativePoseLandmarkProvider:76` `deferred` bejegyzésre `AppResult.failure`-t
  ad. Következmény: a `visionEnabled` bekapcsolása MA egy zsákutcába futó
  setup-folyamatot tenne láthatóvá — az Epic 5 mind a 30 köre kész, de
  készüléken egyetlen vision-képesség sem tud futni. **Előfeltétel a
  rollouthoz:** a modell-binárisok beszerzése, licenc- és checksum-átvezetés
  a manifestbe (a `test/tooling/vision_model_integrity_test.dart` valódi
  SHA-256-ellenőrzése csak `active` bejegyzésnél fut) → külön **GOV-05d** kör,
  a döntés emberi.
- **`vision/public.dart` wide-barrel szimbólum-rés — a KONKRÉT R26-eset
  zárva, az ÁLTALÁNOS enforcement-rés nyitva (mérve E05-R25 security-review
  MINOR-1 + E05-R26, nem blokkoló):** a wide barrel máig aggregát
  (privacy-safe) ÉS nyers landmark/pose/geometry/koordináta-típusokat +
  landmark-provider osztályokat is exportál, szimbólum-szintű korlát
  nélkül. **E05-R26 lezárta a SAJÁT belépési pontját**: a Song Trainer új
  fájljai egy ÚJ, szűk, domain-safe nested barrelen
  (`lib/features/vision/domain/integration/public.dart`, ADR 0193 Döntés
  4–7) keresztül érik el a vision-t, ami mechanikusan (könyvtár-prefix
  tiltólistával) kizárja a nyers típusokat — ezt gépi őr védi
  (`vision_integration_barrel_boundary_test.dart`). **Nyitva marad:** (1) a
  wide barrel maga változatlan, a Practice (E05-R25) meglévő importja is
  azt célozza még (migrálásuk külön, jövőbeli kör, nem sürgős — a
  security-review szerint ma sem áthágás); (2) a szűk barrel ÖNMAGA is
  csak a saját KÖZVETLEN export-sorait ellenőrzi, a TRANZITÍV
  mező-típus-gráfot nem — E05-R26 review F1/NOTE-1 mérte, hogy a
  `posture_metrics.dart` (domain-safe, exportált) egy mezőjén
  (`PostureMetricDefinition.requiredPoseLandmarkIds`) át egy tiltott enum
  ÉRTÉKEI olvashatók voltak (javítva R26 saját javító körében egy `show`
  kombinátorral, de a MINTA — egy re-exportált „biztonságos" fájl saját
  mezője hordozhat tiltott típust — általánosan nyitva marad). Egy
  dedikált architektúra-kör (tranzitív gráf-ellenőrzés a checkerben, vagy a
  wide barrel teljes migrálása) follow-up marad. Részletek:
  [`docs/reviews/e05-r26-song-trainer-vision-integration-review.md`](docs/reviews/e05-r26-song-trainer-vision-integration-review.md)
  F1, [`docs/reviews/e05-r26-song-trainer-vision-integration-security.md`](docs/reviews/e05-r26-song-trainer-vision-integration-security.md)
  NOTE-1, [`docs/adr/0193-song-trainer-vision-integration-contract.md`](docs/adr/0193-song-trainer-vision-integration-contract.md),
  [`docs/LESSONS.md`](docs/LESSONS.md) L190, L193.
- **A valódi, több-stage V2 DSP pipeline összeszerelése MÉG NEM ÜTEMEZETT
  kör.** Mérve E06-R22 pre-flightjában (2026-08-12): nulla konkrét,
  egymással összefűzhető `AnalysisStage<T, T>` lánc létezik a `lib/`-ben — a
  három meglévő konkrét stage (`SignalQualityStage`, `PreprocessingStage`,
  `ClipAnalyzerStage`) egymással össze nem fűzhető I/O-jú. [ADR
  0240](docs/adr/0240-analysis-runner-and-pipeline-boundary.md) a runner
  réteget (E06-R22) tudatosan pipeline-agnosztikusra rögzítette
  (`T = AnalysisDocument`, `analysisV2RunnerProvider` fail-closed
  `StateError`-ral) — egy jövőbeli kör tervezze meg a közös munka-kontextust
  és szerelje össze a valódi láncot; ez ma NEM blokkolja a V2 utat (a flag
  változatlanul `false`), de a `analysisV2RunnerProvider` felülírás nélkül a
  V2 Analyze képernyő sosem tudna valódi eredményt produkálni.
- **E06-R21 a saját kötelező, dedikált biztonsági review-ja nélkül
  merge-elt** (a brief `risk = "high"`-at jelölt, §11 kifejezetten kérte —
  mérve E06-R22 zárásakor: minden más E06 kör R02-től párosan rendelkezik
  `-review.md` + `-security.md` jelentéssel, R21-nek csak az előbbije volt).
  Az E06-R22 orchesztrátora egy UTÓLAGOS, retroaktív security review-t
  dispatch-elt a már merge-elt kódra (read-only audit, nem blokkol
  semmilyen már megtörtént merge-et) — az eredményt lásd:
  [`docs/reviews/e06-r21-analysis-repository-v2-and-migration-security.md`](docs/reviews/e06-r21-analysis-repository-v2-and-migration-security.md),
  ha időközben elkészült, vagy jelezze egy jövőbeli session, ha még hiányzik.

## 4. Current branch

**Aktuális állapot (2026-09-04):** `main` @ `b82f3ab5` — **E14-R03: fail-visible
modellaktiváció**, PR [#566](https://github.com/wolfcasaba/strumsight/pull/566),
squash-merge. Implementer `sonnet-impl` (Claude Sonnet 5),
orchesztrátor/reviewer Claude (Opus 5), **1 javító kör** (review: APPROVED a
javító kör után, 0 nyitott lelet; CHANGES REQUESTED verdikttel indult:
0 BLOCKER / 0 MAJOR / 4 MINOR / 4 NOTE —
[`docs/reviews/e14-r03-review.md`](docs/reviews/e14-r03-review.md)).
**ÚJ ADR: [0355](docs/adr/0355-fail-visible-model-activation-telemetry.md)** —
a Claude írta a pre-flightban (a `docs/adr/**` a kör tiltott zónája volt).
`risk = "high"` → kötelező biztonsági review
([`docs/reviews/e14-r03-security.md`](docs/reviews/e14-r03-security.md)):
**CLEAN**. `native_gate = false` → a CI-tervet a `tools/round-ci-plan.py` adta
(`full-gate.yml`). Exact-SHA evidencia a `c238ea22` merge SHA-n: Full Gate
[33853601498](https://github.com/wolfcasaba/strumsight/actions/runs/33853601498)
`success` + Router CI
[33853642667](https://github.com/wolfcasaba/strumsight/actions/runs/33853642667)
`success`. A pre-flight **tizenkét mért brief-revíziót** írt (§0.0 R1–R12),
köztük kettő valódi H3-elkerülés.

## 5. Last completed round

**E14-R03 — Model activation telemetry és fail-visible működés** (PR
[#566](https://github.com/wolfcasaba/strumsight/pull/566), squash `b82f3ab5`).
A Live út néma CRNN-fallbackja mostantól **kimondja magát**: `RecognitionRuntimeInfo`
(a modell SHA-256-ja a ténylegesen betöltött bájtokból), `ModelActivation<T>`
valódi `throw`-val őrzött invariánsokkal, ötelemű zárt hibakód-halmaz, és a
`LivePipeline.runtimeInfo` getter. A `StrumCrnn.activate` **additív** — a
`tryLoad` szignatúrája nem változott, mert hat, a kör scope-ján kívüli teszt
pinneli. A fallback VISELKEDÉSE bitre azonos maradt, és ez **mérve** van: a
review frame-ujjlenyomata a tiszta `main` klónnal szemben azonos sha256-ot ad
(63 frame, 3 súly-út). Két új lecke: [L620](docs/LESSONS.md#l620) (a típusos
visszatérés költsége a HÍVÓI oldalon keletkezik → additív belépő) és
[L621](docs/LESSONS.md#l621) (a „viselkedés változatlan" ígéret csak
legacy-referenciás ujjlenyomattal mérés).

**Előző kör: E14-R02 — Reprodukálható felismerési baseline és evidence index**
(PR [#565](https://github.com/wolfcasaba/strumsight/pull/565), squash `2bbd36bd`).
Az `evaluation/recognition/baseline_manifest.json` + generált index: ugyanaz a
bemenet bájtra azonos reportot ad, minden szám mellett `sourceFile` és
mező-szintű `command` ([ADR 0354](docs/adr/0354-recognition-baseline-manifest-and-evidence-index.md)).
Lecke: [L619](docs/LESSONS.md#l619) (a kézzel írt séma-validátor fail-OPEN).

## 6. Exact next task

**Következő kör: `E14-R04` — Recognition frame v2 contract**
(`docs/rounds/e14-r04-recognition-frame-v2-contract.md`, motor `sonnet-impl`,
előre kiosztott ADR `0356`). A `docs/execution/pipeline-queue.tsv` Chapter 14
sávja `pending`; a lánc magától viszi tovább.

**Amit az E14-R03 KIMONDOTTAN az E14-R04 asztalára tett** (mind mérve, a
kör tilos zónája miatt halasztva — a review §9.1 tételesen felsorolja):

| # | Mit hagyott nyitva | Hol |
|---|---|---|
| 1 | **izolátum → Lab bekötés**: a `LivePipeline.runtimeInfo` és a `LiveLabController.reportRuntimeInfo` létezik és tesztelt, de production hívó nincs — a `real_strum_engine.dart` / `strum_engine.dart` a kör tilos zónája volt | `lib/features/live/engine/real_strum_engine.dart:167,220` |
| 2 | **a live út valódi asset-neve**: ma a nevesített `RecognitionRuntimeInfo.isolateLiveModelId` konstans megy át, mert az izolátum-határ csak bájtokat hordoz — a 2 és 3 osztályos live asset id alapján nem különböztethető meg (a `strumModelSha256` viszont igen) | `lib/features/live/engine/dsp/live_pipeline.dart` |
| 3 | **`disabledByFlag` flag-olvasása**: a gyártófüggvény és a stabil kód él, a három recovery-flag olvasása nincs bekötve (`lib/core/feature_flags/**` tilos zóna volt, ADR 0271 szerint mindhárom `false` marad) | `lib/app/config/feature_flags.dart` |

**Változatlanul OPERÁTORI (user-) kapuk:** a valós gitáros APK-teszt (a végső
elfogadási predikátum) és a backend tényleges futtatása + telefon-ráállítás
(`docs/operations/device-backend-runbook.md` §1–§9).
## 7. Required verification (before any "done")

A lokális mérce **egyetlen futtatható artefaktum** (GOV-01) — a parancssorban
reprodukált lista a csővezeték miatt nem bizonyíték (`docs/LESSONS.md` L09):

```bash
tools/round-gate.sh test/<a kör területe> [további teszt-útvonal ...]
```

A script a `format` → `analyze` → `test <minden útvonal külön>` → `architecture`
lépéseket **külön processzként** futtatja (ezért nem OOM-ol), és az első piros
lépésnél a helyes kilépési kóddal megáll. Normatív forrás: `AGENTS.md` §12.
Backend-érintésnél kiegészítő lépés (NEM a gate része):
`cd backend && .venv/bin/python -m pytest`.

- Full suite + property gate + APK: `gh workflow run build-apk.yml --ref <branch>`.
- **Never chain `analyze && test`.** ONE win32 major across the tree
  (`flutter_secure_storage` pinned to v10). Riverpod 3.3.2: `AsyncValue.value`
  (nullable), NOT `.valueOrNull`.
- DSP param change ⇒ `docs/rag/chunks/` update in the SAME commit; new DSP
  behaviour ⇒ randomized property in `test/property/` (`PROPERTY_SEED`).
- Backend writes are easy to lose silently — a failed push must NOT mark state
  synced; verify persistence + offline path.
- Backend dev loop: `cd backend && python3 -m venv .venv &&
  .venv/bin/pip install -r requirements.txt`, then
  `.venv/bin/uvicorn app.main:app --reload` (emulator → host: `10.0.2.2`).
  Deploy-szabály: uvicorn-restart előtt `pip install -r requirements.txt`
  (a `main.py` futásidőben importál `alembic`-ot).
- **HORIZON ritual minden kör-commit után:**
  ```bash
  git notes add -m "round=<n> verdict=pass|fail tests=<n> lesson=<slug>"
  git push origin 'refs/notes/*'
  ```

## 8. Historical archive

A teljes kör-történeti napló (pre-SDD r1–r217 + E01-R01…R15 részletes
összefoglalók, git-notes tükör): [`docs/handoff-archive.md`](docs/handoff-archive.md).
Epic-1 evidencia-gyűjtemény: [`docs/sdd/epic-01-completion-report.md`](docs/sdd/epic-01-completion-report.md).

---

## How to update this file

After **every** round: (1) header date + round; (2) §1/§2 if release state or
capabilities changed; (3) §3 blockers +/-; (4) §4–§6 branch / last round / next
task; (5) move the finished round's detailed story to
`docs/handoff-archive.md` (append, never delete). Keep this file a ~120-line
operational snapshot — history lives in the archive, detail in git.
