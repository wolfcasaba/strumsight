# E05-R22 — Review

Brief: `docs/rounds/e05-r22-observation-fusion-and-evidence.md`
Diff: `git diff origin/main...codex/e05-r22-observation-fusion-and-evidence`
Reviewer: Claude Sonnet 5 · Dátum: 2026-08-08
Verdikt: CHANGES REQUIRED

## Összegzés

BLOCKER: 0 · MAJOR: 1 · MINOR: 1 · NOTE: 1

## Jelzés + handoff

`.codex-round-status`: `status=done`, `head=7e9bd17`, `dirty_files=1`,
`gate_shape=ok`, `scope_audit=ok`, `scope_audit_changed=10`. A `dirty_files=1`
kivizsgálva: `codex-signal.sh` a saját atomikus-írás temp-fájlját
(`.codex-round-status.tmp.$$`) számolta be a `git status --porcelain`
futtatásakor — a `.gitignore` csak a végleges `.codex-round-status` nevet
fedi, a `.tmp.$$` variánst nem. A munkapéldány a jelzés UTÁN mérve teljesen
tiszta (`git status --short` → üres). Nem valódi el nem küldött módosítás —
a fájl-alapú jelzőmechanizmus önreferenciás mellékhatása.

A brief §10 „Implementation handoff" ki van töltve: fájlonkénti összefoglaló,
TÉNYLEGES parancskimenetek (a valódi-sértés próba pontos számokkal:
`Expected 0.25, Actual 0.8125`; `model=0.9` cellán `Actual 0.975`), a
`round-gate.sh --result-json` strukturált kimenete idézve.

## Gate-újrafuttatás (saját kézzel, izolált klón)

```bash
git clone --branch codex/e05-r22-observation-fusion-and-evidence /home/ubuntu/music-theory /tmp/review-e05-r22
cd /tmp/review-e05-r22 && tools/prepare-flutter-generated.sh
tools/round-gate.sh test/features/vision
```

Eredmény: **MINDEN GATE ZÖLD** — format, analyze, `test test/features/vision`
(364 teszt, `00:24 +364: All tests passed!`), architecture (12 allowlistelt
eltérés, mind a körön KÍVÜLI, korábbi), secrets (2001 fájl, 0 lelet), l10n
(964 üzenet, en↔hu paritás). Külön processzenként futtatva, nincs `&&`/pipe/
`tail` — a `verify_claim`/`gate_shape=ok` jelzés ezt gépileg is megerősíti.

## Acceptance criteria

| # | Kritérium | Teljesült | Bizonyíték |
|---|---|---|---|
| 1 | Golden evidence snapshot, bit-stabil, ID-kkel | ✅ | `observation_fusion_test.dart: produces a deterministic, JSON-stable evidence snapshot` — két független `ObservationFusion` instance, azonos `jsonEncode` a fixture-hoz és egymáshoz, `firstEvidence.id == secondEvidence.id` |
| 2 | 12 cellás confidence-propagáció mátrix, leggyengébb komponens nem léphető túl | ✅ | `confidence_model_test.dart: propagates good, boundary and poor values for every component` (4 komponens × [0.9,0.5,0.1], `lessThanOrEqualTo`) + `uses the weakest component instead of averaging it away` (pontos `0.25` egyenlőség, nem csak `<=`) |
| 3 | Minimum-frame mátrix (alatt/rajta/fölött) | ✅ | `rejects a window below the minimum observation count` (1 obs), `accepts the observation-count boundary and the value above it` (2 és 3 obs) |
| 4 | Gap/occlusion: notObservable VAGY csökkentett confidence, soha változatlan | ✅ | `short bridgeable gaps are inferred and reduce confidence` (`inferred.confidence < observed.confidence`), `unbridgeable gaps are not observable` |
| 5 | Duplikáció-teszt: egy evidence, nem kettő | ✅ | `is idempotent for an identical metric window` — `second, same(first)` (objektum-azonosság, erősebb mint puszta ID-egyezés), `emittedEvidence hasLength(1)` |
| 6 | Memória-teszt: korlátos, nem nő monoton | ⚠️ **részleges — lásd F1** | A szállított teszt (`bounds raw observations…`) zöld, DE csak azt a hívási mintát fedi, ahol minden `add()`-hoz tartozik rendszeres `fuse()` ugyanarra a metrikára. Saját próba (lásd F1) egy `add()`-only, sosem fuse-olt metrikára **korlátlan** növekedést mért. |
| 7 | Valódi-sértés próba: átlagolásra csere → PIROS → visszaállítás | ✅ | Implementer önjelentése + **saját, független reprodukálás** (lásd lent) — 3 teszt PIROS, pontos számokkal egyezik |
| 8 | `experimental` kizárásos teszt (brief §6, revízió) | ✅ | `current metric catalog never produces experimental evidence` — a teljes mai `EvidenceMetric.currentCatalog`-on (17 metrika: 6 fretting+7 picking+4 posture) egyik sem termel `experimental`-t |

### Saját valódi-sértés reprodukálás (F7 megerősítése)

Izolált klónban `ConfidenceModel.combine` ideiglenesen átlagra cserélve:

```bash
git -C /tmp/review-e05-r22 diff -- lib/features/vision/domain/evidence/confidence_model.dart  # (mentve, majd visszaállítva)
flutter test test/features/vision/domain/confidence_model_test.dart test/features/vision/application/observation_fusion_test.dart
```

3 teszt PIROS (`model=0.9 must not be averaged away` → `Actual 0.975`; golden
snapshot `confidence":0.9` → `Actual 0.975`; `uses the weakest component…` →
`Actual 0.8125`) — számszerűen egyezik az implementer §10 handoffjában
idézettel. Visszaállítva, a fájl a review után bitre azonos az eredetivel.

## Scope-audit

```
git diff --stat origin/main...codex/e05-r22-observation-fusion-and-evidence
```

11 fájl változott — **pontosan** a brief §4 engedélyezett listája (4 új
evidence-domain fájl, 1 új application fájl, `public.dart` additív export, 2
teszt, 1 fixture, `docs/adr/0190-*.md`, `docs/rounds/e05-r22-*.md`).
Engedélyezett listán kívüli változás: **nincs**. A `scope_audit=ok` gépi
jelzés ezt megerősíti (`scope_audit_changed=10`, a pre-flight ADR-fájl a
`scope_base` UTÁN már a saját commitja, ezért nem számít bele az implementer
diffjébe, csak az orchestrátoréba).

## Architektúra + termékhatárok

- `public.dart`: kizárólag additív `export` sor (+5 sor, 0 törlés/átrendezés).
- Domain-függetlenség: az architecture gate zöld, 0 ÚJ allowlistelt eltérés
  (a 12 meglévő mind korábbi kör öröksége).
- Erőforrás-tulajdonlás: a pre-flight §0.0/8 szerint N/A — megerősítve, a diff
  egyetlen fájlja sem importál `CameraSessionLease`-t vagy hasonlót; a réteg
  tisztán szinkron domain/application kód, nincs `Stream`/`Timer`/`dispose()`
  felszabadítandó erőforrás.
- `quality`/`sync` komponens-forrás (§5.9): megerősítve — `confidence_model.dart`
  KIZÁRÓLAG `vision_frame_quality.dart`-ot importál (`VisionQualitySummary`
  sehol nem szerepel az új fájlokban), a `sync` a `SyncQuality`-t olvassa, a
  `picking_metrics.dart`/`picking_metric_engine.dart` fájlokhoz a diff
  **nem** nyúl.
- Ablak-hossz-forrás (§5.7): megerősítve — `EvidenceMetric.fretting/picking/posture`
  mindhárom a valódi katalógus `.window`/`.minimumVisibility` mezőit olvassa
  ki, nincs párhuzamos ablak-fogalom.

## Megállapítások

### F1 — MAJOR — Memóriakorlát csak `fuse()` mellékhatásaként érvényesül, `add()`-only metrikára korlátlan

- **Fájl:** `lib/features/vision/application/observation_fusion.dart:33-45` (`add`), `:56-79` (`fuse`)
- **Probléma:** a nyers observationök eltávolítása (`retained.removeWhere(...)`)
  kizárólag a `fuse()` hívás VÉGÉN történik, ARRA a metrikára, amelyikre a
  hívás szólt. Az `add()` önmagában semmit nem korlátoz. A brief §5/6 kötött,
  feltétel nélküli architekturális döntése („a pipeline **NEM** tarthat meg
  minden nyers observationt") ezzel csak addig igaz, amíg a hívó MINDEN
  metrikát rendszeresen fuse-ol — ami nem következik sem a brief szövegéből,
  sem az `ObservationFusion` publikus API-jából (`add`/`addAll` bármelyik
  metrikára hívható `fuse()` nélkül is, és ez teljesen legitim hívási minta,
  pl. egy jövőbeli session-controller, amely csak az éppen kijelzett
  metrikára fuse-ol, a többire csak streamel).
- **Hatás:** egy 10 perces, 20fps session-szimulációban egyetlen, sosem
  fuse-olt metrikára **12 012** nyers observation maradt memóriában (mérve,
  lásd lent) — 17 metrikás valós katalógusnál (6 fretting + 7 picking + 4
  posture) ez a szám metrikánként hasonló nagyságrendű, ha a jövőbeli hívó
  nem fuse-ol egyenletesen mindegyikre.
- **Ellenőrzés (saját próba, izolált klónban, NEM commitolva):**
  `test/features/vision/application/_probe_unfused_metric_memory_test.dart`
  — két metrikát streamel 10 percen át (20fps), az egyiket rendszeresen
  fuse-olja, a másikat SOHA. `retainedObservationCount` a sosem-fuse-olt
  metrikánál **12012**, holott a brief szerinti elvárás korlátos szám
  (`lessThan(200)` a próbában). A meglévő „bounds raw observations…" teszt
  ezt NEM fogja meg, mert ott minden `add()`-hoz tartozik rendszeres
  `fuse()` UGYANARRA a metrikára — a teszt hívási mintája épp azt a
  cadenciát reprodukálja, ami elrejti a hibát.
- **Kötelező javítás:** az `add()` maga is korlátozza a per-metrika nyers
  observation-listát — pl. időalapú (egy dokumentált, a legszélesebb
  metrika-ablaknál nem rövidebb retention-horizont) vagy méretalapú felső
  korlát, amit `add()` minden hívásnál kikényszerít, függetlenül attól, hogy
  `fuse()` mikor fut az adott metrikára. A `fuse()`-beli pruning maradhat
  kiegészítésként, de a garanciát nem szabad hozzá kötni.
- **Ellenőrzés (javításhoz):** a fenti próbateszt (vagy ezzel ekvivalens) a
  round saját, commitolt suite-jába kerüljön, és zöldre váltson a javítással.
- **Státusz:** OPEN

### F2 — MINOR — A „minimum látható időtartam" ág nincs önállóan tesztelve

- **Fájl:** `test/features/vision/application/observation_fusion_test.dart`
- **Probléma:** a szállított „minimum-frame" tesztek kizárólag az
  observation-SZÁM tengelyt variálják (1/2/3 megfigyelés); a §5/1 másik fele
  (`minimumVisibleDuration`) sosem a limitáló tényező egyik tesztben sem. Egy
  olyan eset, ahol a szám elegendő (≥ `minimumObservationCount`), de az
  időtartam nem, nincs lefedve.
- **Hatás:** ma NEM funkcionális hiba — saját próbával megerősítve (lásd
  lent), a `_visibleDuration(...) >= thresholds.minimumVisibleDuration`
  ág helyesen `notObservable`-t ad. A hiány pusztán regresszió-védelmi: egy
  jövőbeli refaktor (pl. a két feltétel `&&`-ének felcserélése egy hibás
  early-returnre) ezt a suite-ot zölden hagyná.
- **Ellenőrzés (saját próba, izolált klónban, NEM commitolva):** 3
  megfigyelés 30 ms-on belül (`minimumObservationCount=2` teljesül,
  `minimumVisibleDuration=100ms` NEM) → `ObservationState.notObservable` —
  a próba ZÖLD, azaz a mai kód helyes.
- **Kötelező javítás:** egy külön teszteset: szám-elegendő ÉS
  időtartam-elégtelen bemenet → `notObservable`.
- **Ellenőrzés:** az új teszt fut és zöld.
- **Státusz:** OPEN

### F3 — NOTE — Az evidence `value` aggregáció (számtani átlag) outlier-politika nélkül

- **Fájl:** `lib/features/vision/application/observation_fusion.dart` (`_fuseWindow`, a `value` számítás)
- **Megfigyelés:** a látható megfigyelések értékének egyszerű számtani átlaga
  kerül az evidence `value` mezőjébe. Az SDD §23.2 az „outlier policy"-t a
  fusion input egyik generikus paramétereként sorolja fel, de **ez a kör
  brief-je nem ír elő rá acceptance-cellát** — nincs is brief-sértés, csak
  jövőbeli lehetőség. Egyetlen kiugró (de még `visible`-nek minősülő)
  megfigyelés torzíthatja az emitált `value`-t, miközben a `confidence`
  komponensei ezt nem tükrözik.
- **Javaslat (nem kötelező ebben a körben):** egy jövőbeli kör (feedback
  policy / insight R23, vagy egy dedikált finomítás) dönthet median vagy
  trimmed-mean aggregációról, dokumentált ADR-rel.
- **Státusz:** OPEN (follow-up, nem blokkoló)

## Biztonsági review

A brief `risk = "high"` — AGENTS.md §15.1 szerint kötelező dedikált
security-reviewer pass. Külön dispatch-elve, a jelentés
`docs/reviews/e05-r22-observation-fusion-and-evidence-security.md` — lásd
ott a verdiktet; ez a szakasz csak hivatkozás, nem duplikálja a tartalmat.

## Gate-bizonyíték ellenőrzése

| Gate | Állított eredmény | Ellenőrizve |
|---|---|---|
| format | zöld (implementer: `Formatted 8 files (5 changed)`) | ✅ saját újrafuttatás, izolált klón |
| analyze | zöld | ✅ saját újrafuttatás |
| célzott tesztek (`test/features/vision`) | zöld, 364 teszt | ✅ saját újrafuttatás, `00:24 +364` |
| architecture | zöld, 12 allowlistelt (korábbi) eltérés | ✅ saját újrafuttatás |
| secrets | zöld, 2001 fájl, 0 lelet | ✅ saját újrafuttatás |
| l10n | zöld, 964 üzenet | ✅ saját újrafuttatás |
| CI (teljes suite + property + APK) | **még nem dispatch-elve ebben a jelentésben** | ⏳ orchestrátor a merge előtt |

## Merge-döntés

Az ADR 0052 szerint: minden gate zöld ÉS nincs nyitott BLOCKER/MAJOR → merge.
**Jelenleg 1 nyitott MAJOR (F1) → merge TILOS.** Javító kör szükséges,
ugyanaz a motor (Terra), F1 (kötelező) + F2 (kötelező, olcsó) + F3
(opcionális, csak ha nem hizlalja érdemben a diffet) a leletlistával. A
javítás után a gate-eket és a memória-próbát újra, saját kézzel futtatom, és
a jelentést frissítem.
