# E14-R04 — Review (RecognitionFrame V2 domain contract)

- **Reviewer:** Claude (Opus 5), orchestrátor-szék, read-only review (ADR 0055)
- **Dátum:** 2026-09-04
- **Kör-branch:** `sonnet-impl/e14-r04-recognition-frame-v2-contract`
- **Reviewelt HEAD:** `bd4c36af96ae4576e790514769e18053358dd901`
- **Induló HEAD (pre-flight):** `94f46951aa08198c71efc5bc1f9fdc32e78e2817`
- **Implementer:** Claude Sonnet 5 (`sonnet-impl`)
- **ADR:** [`0505`](../adr/0505-versioned-recognition-frame-contract-and-legacy-adapter.md)

## 1. VÉGSŐ DÖNTÉS: **APPROVED** (a javító kör után — lásd §8)

> **Első kör (`bd4c36af`): CHANGES REQUESTED** — 2 MAJOR, 2 MINOR, 2 NOTE.
> **Javító kör (`ab930516`): mindhárom kért lelet zárva, saját méréssel
> igazolva.** A §2–§7 az EREDETI review szövege (nem írom át visszamenőleg);
> a zárás bizonyítéka a §8.

### 1.1 Az eredeti verdikt — CHANGES REQUESTED, 2 MAJOR, 2 MINOR, 2 NOTE

A kör formai fegyelme kiváló, a gate zöld, a scope tiszta, és a fail-closed
`fromJson` réteg érdemben jobb, mint amit a brief betűje megkövetelt volna. A
két MAJOR mégis **ugyanabból a mintából** jön: a kör felépítette a
bizonytalanság szerződését, majd a saját egyetlen fogyasztójában (az adapter)
és a saját adatmodelljében (a prediction-ök) **nem használja** — pontosan az a
„zöld gate mellett átcsúszó tartalmi hűtlenség", amit az `sdd-round-review`
alapelve őriz.

## 2. Mérések, amiket MAGAM futtattam

### 2.1 Scope-audit — TISZTA

```
$ python3 tools/scope-audit.py --repo /home/ubuntu/ss-sonnet-impl-e14-r04 \
    --brief docs/rounds/e14-r04-recognition-frame-v2-contract.md \
    --base 94f46951aa08198c71efc5bc1f9fdc32e78e2817
Legacy scope audit OK (94f46951aa08..bd4c36af96ae, 11 changed path(s), 0 generated/ignored)
```

> A wrapper `scope_audit=VIOLATION`-t jelzett (`.round-prompt-e14-r04.md`), és
> emiatt a kör-jelzés `stopped` lett. Ez **NEM az implementer sértése**: a
> kifogásolt fájl az ÉN dispatch-artefaktumom volt, amit a munkapéldány
> gyökerébe írtam. Eltávolítás után az audit tiszta. Orchestrátor-hiba, a
> tanulság a §6-ban.

### 2.2 Gate — izolált `/tmp` klónban, MAGAM futtatva, MIND ZÖLD

`git clone --branch sonnet-impl/e14-r04-recognition-frame-v2-contract … /tmp/review-e14-r04`
(HEAD `bd4c36af`), majd:

```
═══ Gate-összegzés
    format                                                     zöld
    analyze                                                    zöld
    test test/features/live/recognition_frame_contract_test.dart zöld
    test test/features/live/live_frame_adapter_test.dart       zöld
    test test/core/architecture_dependency_test.dart           zöld
    test test/features/live                                    zöld
    test test/core                                             zöld
    architecture                                               zöld
    secrets                                                    zöld
    l10n                                                       zöld
```

exit `0`. (Az első futásom `PIROS (1)`-et adott a `test/features/live`-ra —
az ok kizárólag az volt, hogy az eldobható próbatesztemet a futás KÖZBEN
töröltem; a tiszta fán megismételt futás a fenti.)

### 2.3 CI a pontos merge-jelölt SHA-n

| Workflow | Run | `headSha` | Eredmény |
|---|---|---|---|
| `router-ci.yml` | [33859163280](https://github.com/wolfcasaba/strumsight/actions/runs/33859163280) | `bd4c36af` | **success** |
| `full-gate.yml` | [33859174430](https://github.com/wolfcasaba/strumsight/actions/runs/33859174430) | `bd4c36af` | **success** |

Mindkettő zöld ezen a SHA-n — de a javító kör KÓDOT módosít, ezért a merge-kapu
ÚJRA-dispatch-et kíván az új head SHA-n (ADR 0086 §2). A fenti zöld tehát a
review evidenciája, NEM a merge evidenciája.

A CI-terv (`tools/round-ci-plan.py`) `full-gate.yml`-t írt elő
(`apk_required: false`, tisztán Dart/dokumentum-diff), `router_ci_expected: true`.

### 2.4 Próbateszt (eldobható, törölve) — a MAJOR-1 MÉRT bizonyítéka

```
PROBE latestStrum=Instance of 'Strum' confidence=0.0
00:00 +0 -1: PROBE: an UNCERTAIN strum still renders a directional arrow [E]
  Expected: null
    Actual: <Instance of 'Strum'>
  an uncertain direction must not become a visible arrow
00:00 +1 -1: Some tests failed.
```

A kontroll-cella (akkord-oldal) ugyanabban a futásban **átment**: egy
`uncertain` `ChordPrediction` helyesen `current: null`-t ad. Az aszimmetria
tehát mért, nem következtetett.

## 3. Leletek

### MAJOR-1 — az adapter az akkordnál betartja a `decision`-t, a strumnál NEM

**Hol:** `lib/features/live/domain/recognition/live_frame_adapter.dart:66-74`
(`_strumFor`), szemben a `:53-58`-cal (`_chordFor`).

**Mit mértem.** `_chordFor` helyesen kapuz:
`if (chord == null || chord.decision != RecognitionDecision.confirmed) return null;`.
`_strumFor` viszont **egyáltalán nem nézi** a `strum.decision`-t: minden
nem-`null` `StrumPrediction`-ből `Strum`-ot épít. Egy
`pDown: 0.475, pUp: 0.425` jóslat — ami a kör SAJÁT, egyetlen levezetése
szerint (`StrumPrediction.decision`, `strum_prediction.dart:58-61`) pontosan
`RecognitionDecision.uncertain` — így **látható irány-nyilat** eredményez
(`down`), `confidence: 0`-val. A §2.4 próbateszt ezt kimérte.

**Miért MAJOR.**

1. Ellentmond a fájl SAJÁT doc-commentjének (`:12-15`): „The adapter FORDÍT,
   nem DÖNT: it never upgrades a non-`confirmed` … to visible" — az akkordra
   igaz, a strumra nem. Bizonyítatlan doc-comment állítás.
2. Ellentmond az `ADR 0505` D5-nek, ami az `uncertain` láthatóvá tételét
   nevesítve tiltja, és az `ADR 0271` §1-nek (`UNKNOWN > CONFIDENTLY WRONG`):
   egy „nem tudjuk, le vagy fel" verdikt HATÁROZOTT irányú nyílként jelenik meg.
3. A kör headline-levezetése (`StrumPrediction.decision`) így a kör EGYETLEN
   fogyasztójában halott kód — a §6.1 mérce-mátrix „A `decision` kiszámítása
   kimarad" sora a chord-oldalon fog, a strum-oldalon nem.
4. Ez a `docs/LESSONS.md`-ben már nyilvántartott, NYITOTT hibaosztály él
   tovább szerződés-szinten: a strum-nyilak beszédre is elsülnek.

**Miért nem fogta meg a gate.** A `live_frame_adapter_test.dart` MINDEN
strum-cellája `pDown: 0.95, pUp: 0.05` (margin `0.90` → `confirmed`) — a
`:141-183` és `:185-193` tesztek. `uncertain` strum-cella **nincs**. A 6×2-es
mátrix (`:48-101`) kizárólag a `ChordPrediction.decision`-t járja körbe.

**Javasolt irány (nem kész patch).** `_strumFor` kapuzzon a `_chordFor`-ral
azonos szabály szerint (`decision != confirmed` → `null`), és a
`latestStrumTime` fallback is kövesse ezt. A mátrixot terjeszd ki a
strum-oldalra: mind a hat `RecognitionDecision` × {van strum, nincs strum},
a határcellát a brief §6.1 KÖTÖTT `pDown`/`pUp` számpárjaival
(`0.475`/`0.425`), ne kézzel írt margóval.

### MAJOR-2 — a `RecognitionRejectReason` egyetlen jóslathoz sem kapcsolódik

**Hol:** `lib/features/live/domain/recognition/recognition_decision.dart:43-69`
(az enum), `strum_prediction.dart:9-17` és `chord_prediction.dart:13-23`
(a konstruktorok).

**Mit mértem.**

```
$ grep -rn "RejectReason\|rejectReason" lib/ | grep -v recognition_decision.dart
(nincs találat a live feature-ben)
```

Sem a `StrumPrediction`, sem a `ChordPrediction` nem hordoz `rejectReason`
mezőt. Az enum deklarálva van, JSON-ban körbejár, de **egyetlen jóslatból sem
érhető el** — a fogyasztó soha nem tudhatja meg, MIÉRT lett elutasítva vagy
bizonytalan egy verdikt.

**Miért MAJOR.** A brief §3.1 a `RecognitionRejectReason`-t a döntési
állapotokhoz PÁROSÍTVA írja elő („plusz `RecognitionRejectReason`"), és a §6.1
numerikus küszöb-táblázata kifejezetten kimondja a várt párost:
`uncertain` **(reject-ok: `lowConfidence`)**. Ez az acceptance-cella
implementálatlan ÉS méretlen: a szállított `StrumPrediction.decision`
`uncertain`-t ad, `lowConfidence` indoklás nélkül. Egy zárt indok-enum, amit
nem lehet kiolvasni, nem szerződés — az `ADR 0505` D3 épp azért zárt enum, hogy
a UI és a Lab gépi módon tudja megkülönböztetni az elutasítás okait.

**Javasolt irány.** Vidd be a `rejectReason`-t a két prediction-be nullable
mezőként (`null`, ha a `decision` nem elutasító), a `StrumPrediction`-nél a
`decision`-nal EGYÜTT levezetve (`uncertain` → `RecognitionRejectReason.lowConfidence`),
a `ChordPrediction`-nél konstruktorból, a §0.0 R7 logikája szerint. A `toJson`
/`fromJson` maradjon fail-closed (a KULCS kötelező, az érték lehet `null`), és
a §6.1 három cellája mérje a párost, ne csak a `decision`-t.

### MINOR-1 — a `calibratedConfidence` értéktartománya őrizetlen, a legacy határon assert-be fut

`live_frame_adapter.dart:72` → `Strum(confidence: strum.calibratedConfidence ?? 0)`,
miközben `lib/core/music/strum.dart:11` `assert(confidence >= 0 && confidence <= 1)`.
A `StrumPrediction` semmilyen tartomány-ellenőrzést nem végez, sem a
konstruktorban, sem a `fromJson`-ben. Egy `calibratedConfidence: 1.4` jóslat
release buildben CSENDBEN átmegy (assert kikapcsolva), debugban pedig egy
látszólag független `core/music` fájlban robban. Javaslat: a `fromJson`
utasítsa el a `0..1`-en kívüli kalibrált értéket típusos hibával — a
fail-closed elv (D6) már itt van, csak erre a mezőre nincs alkalmazva.

### MINOR-2 — a négy `_require*` segédfüggvény négyszer van lemásolva

`recognition_frame.dart:114-139`, `strum_prediction.dart:120-148`,
`chord_prediction.dart:119-150`, `signal_quality_snapshot.dart` — ugyanaz a
`_requireObject` / `_requireDouble` / `_requireInt` / `_requireString` /
`_requireKey` / `_requireNullableDouble` készlet. Négy másolat négyszeres
esély arra, hogy egy későbbi kör csak az egyiket szigorítsa (pontosan az L619
fail-open osztály következő adagja). Mivel a diff hízlalása nélkül nem oldható
meg a jelenlegi `allowed_paths` mellett (közös fájl kellene), ez **follow-up**,
nem körben javítandó — de a javító kör a MAJOR-2 mezőbővítésekor ne sokszorozza
tovább.

### NOTE-1 — az adapter egyirányú, a brief §3.6 „kétirányú"-t írt

A §10.6/3 indoklása **helytálló és elfogadott**: a `LiveFrame →
RecognitionFrame` irányhoz a legacy `Strum.confidence`-ből `pDown`/`pUp` nyers
valószínűséget kellene kitalálni, ami az `ADR 0505` D2 tiltotta hazugság
fordítottja. A brief §3.6 célja (`hogy a 22 hívó ÉRINTETLEN maradjon`)
kizárólag a `RecognitionFrame → LiveFrame` irányt igényli, és egyetlen
acceptance-pont sem méri a fordítottat. Orchestrátori döntéssel **elfogadva**,
a brief §0.0 R12 revíziójaként rögzítve. Nem blokkol.

### NOTE-2 — a `toJson` derivált kulcsokat ír, amiket a `fromJson` nem olvas

`strum_prediction.dart:70,72` kiírja a `directionMargin`-t és a `decision`-t,
de a `fromJson` (`:80-94`) egyiket sem olvassa vissza — újraszámolja. Ez
szándékos és HELYES (a derivált adatnak nem szabad a drótról jönnie, és a
round-trip így is fixpont), a doc-comment (`:78-79`) ki is mondja. Csak azért
kerül ide, hogy egy későbbi kör ne „javítsa meg" visszaolvasásra.

## 4. Acceptance criteria — tételes ellenőrzés

| # | Kritérium | Verdikt | Bizonyíték |
|---|---|---|---|
| 1 | domain nem importál Fluttert/Riverpodot | ✅ | `architecture_dependency_test.dart` új csoport, 7 cella; a §7.1 valódi-sértés próba PIROS→ZÖLD dokumentálva (§10.3) |
| 2 | JSON round-trip mind az 5 modellre | ✅ | `recognition_frame_contract_test.dart`, saját gate-futásomban zöld |
| 3 | 6×2 backward compat mátrix | ⚠️ **részleges** | a chord-oldal teljes; a strum-oldal fedetlen → **MAJOR-1** |
| 4 | `calibratedConfidence` sosem a nyers `pDown` | ✅ | mindkét prediction-re cella; az adapter is `?? 0`-t ad, nem a nyerset |
| 5 | chord- és direction-confidence külön | ✅ | `RecognitionFrame.strum`/`chord` külön, dedikált cella |
| 6 | ismeretlen `schemaVersion` → típusos hiba | ✅ | `recognition_frame.dart:67-73`, cella zöld |
| 7 | `public.dart` additív, `LiveFrame` bájtra változatlan | ✅ | `git diff --stat 94f46951..bd4c36af -- lib/features/live/model/live_frame.dart` ÜRES; magam mértem |
| 8 | fail-closed hiányzó-kulcs cella modellenként (§0.0 R10) | ✅ | öt cella, a `_requireKey`/`_requireNullableDouble` a KULCS hiányát külön kezeli a `null` ÉRTÉKTŐL — ez pontosan az L619 tanulság helyes alkalmazása |
| 9 | legacy-import határ (§0.0 R5) | ✅ | `_forbiddenRecognitionModelImports` cella; csak az adapter éri el a `live_frame.dart`-ot |
| — | §6.1 „reject-ok: `lowConfidence`" | ❌ | nincs `rejectReason` mező sehol → **MAJOR-2** |

## 5. Architektúra és termékhatárok (AGENTS.md §5–§6)

- **Domain-függetlenség:** teljesül, gépi őrrel. A `package:meta` használata a
  §0.0 R4 szerinti, a fa konvenciójával egyező.
- **`tool/check_architecture.dart` érintetlen** — a §0.0 R3 előírása betartva.
- **`public.dart`:** additív, a `LiveFrame` export sora változatlan; a két új
  teszt KIZÁRÓLAG a barrelen át importál, tehát egy lemaradó export fordítási
  hibát ad, nem néma kihagyást. Ez jó minta.
- **Tilos zóna:** `live_pipeline.dart`, `engine/**`, `screens/**`, `widgets/**`,
  `docs/adr/**` — egyik sincs a diffben (scope-audit §2.1).
- **Audio/hálózat/mic/secret:** a diff egyiket sem érinti; `risk = "normal"`
  helytálló, dedikált security review nem szükséges.
- **Lifecycle-erőforrás:** a kör tisztán adatszerződés, nincs megszerzett
  erőforrás.

## 6. Orchestrátori tanulság (a saját hibámról)

A `.round-prompt-e14-r04.md` implementer-promptot a **munkapéldány gyökerébe**
írtam, ezért a wrapper gépi scope-auditja `VIOLATION`-t adott, és a kör-jelzés
`stopped` lett — miközben az implementer diffje hibátlanul a
`allowed_paths`-on belül maradt. A dispatch-artefaktum a munkapéldányon KÍVÜL
való (vagy gitignore-olt útvonalon), különben az orchestrátor a saját
eszközével téveszt meg egy későbbi olvasót. Ez a `docs/LESSONS.md`-be megy.

## 7. Mi kell a merge-hez

1. **MAJOR-1** zárása: `_strumFor` kapuzzon a `decision`-re + a mátrix
   strum-oldali kiterjesztése (a határcella a §6.1 kötött számpárjaival).
2. **MAJOR-2** zárása: `rejectReason` a két prediction-be, fail-closed
   JSON-nal, és a §6.1 három cellája mérje a párost.
3. **MINOR-1** zárása (olcsó, ugyanabban a diffben): `calibratedConfidence`
   `0..1` tartomány-ellenőrzés a `fromJson`-ben.
4. MINOR-2 → follow-up, NOTE-1/NOTE-2 → nincs teendő.
5. A javító kör után: a gate ÚJRA magam futtatom izolált klónban, és a teljes
   CI-kapu (Full Gate + Router CI) ÚJRA az új head SHA-n.

---

## 8. Javító kör — leletenkénti zárás (`ab930516a53491daa1e2b442c7343a04b37b4c41`)

A javító kört ugyanaz a motor (`sonnet-impl`) vitte, a §3 leletlistájával. A
zárást **nem bemondásra** fogadtam el: friss `/tmp/review2-e14-r04` klónban,
eldobható próbateszttel mértem, majd a próbát töröltem.

### 8.1 A záró próbateszt kimenete (eldobható, törölve)

```
00:00 +0: MAJOR-1 CLOSED: uncertain strum -> no arrow, no leaked onset
00:00 +1: MAJOR-1 control: confirmed strum still visible
00:00 +2: MAJOR-2 CLOSED: uncertain strum pairs lowConfidence; confirmed -> null
00:00 +3: MAJOR-2: chord rejectReason key is REQUIRED (fail-closed)
00:00 +4: MINOR-1 CLOSED: out-of-range calibratedConfidence rejected by fromJson
00:00 +5: All tests passed!
```

Mind az öt cella PONTOSAN azt a viselkedést méri, ami az első leadáson
elbukott volna — a MAJOR-1 cellája `pDown: 0.475 / pUp: 0.425`-tel, a brief
§6.1 KÖTÖTT számpárjával.

### 8.2 Leletenként

| Lelet | Állapot | Mit mértem |
|---|---|---|
| **MAJOR-1** | ✅ **ZÁRVA** | `live_frame_adapter.dart` `_strumFor`: `if (strum == null \|\| strum.decision != RecognitionDecision.confirmed) return null;` — a `_chordFor`-ral azonos szabály. A `latestStrumTime` is követi: csak LÁTHATÓ strum onset-ideje írja felül a base-t, tehát egy elvetett jóslat ideje nem szivárog ki (ezt külön cella méri: `expect(legacy.latestStrumTime, isNot(9.99))`). A kontroll-cella igazolja, hogy a `confirmed` strum továbbra is látszik, `latestStrumTime: 3.0`-val. |
| **MAJOR-2** | ✅ **ZÁRVA** | `StrumPrediction.rejectReason` LEVEZETETT getter (`:69`), a `decision`-nal együtt: `uncertain` → `RecognitionRejectReason.lowConfidence`, `confirmed` → `null` — mérve. `ChordPrediction.rejectReason` konstruktorból (`:23`, `:63`), fail-closed `_requireNullableRejectReason`-nel (`:98`): a `rejectReason` KULCS hiánya `ArgumentError`, az ÉRTÉK lehet `null` — mérve. A brief §6.1 „reject-ok: `lowConfidence`" acceptance-cellája immár implementált ÉS mért. |
| **MINOR-1** | ✅ **ZÁRVA** | `_requireCalibratedConfidence` mindkét prediction `fromJson`-jében (`strum_prediction.dart:170-176`, `chord_prediction.dart:172`): `if (value != null && (value < 0 || value > 1)) throw ArgumentError…`. Mérve `1.4`-re és `-0.1`-re is. A nyers valószínűségekre helyesen NEM vezetett be tartomány-ellenőrzést (az túlnyúlt volna a leleten). |
| **MINOR-2** | ↪ **follow-up** | Szándékosan nem javítva (közös fájl kellene, az `allowed_paths`-on kívül). A javító kör nem sokszorozta tovább a készletet. |
| **NOTE-1 / NOTE-2** | — | Nincs teendő; a viselkedés változatlan. |

### 8.3 A zárás után MAGAM futtatott mérce

**Scope-audit** (`ab930516`):

```
Legacy scope audit OK (94f46951aa08..ab930516a534, 12 changed path(s), 1 generated/ignored)
```

A `1 generated/ignored` a saját review-jelentésem — állandó, kód szintű
mentesség (`tools/ai_router/security.py::GENERATED_IGNORED_PREFIXES`), nem
sértés. A `lib/features/live/model/live_frame.dart` a
`git diff --stat 94f46951..ab930516` alatt **nem szerepel** — a 7.
acceptance-pont a javító kör után is áll.

**Gate**, friss `/tmp` klónban (`ab930516`), exit `0`:

```
═══ Gate-összegzés
    format                                                     zöld
    analyze                                                    zöld
    test test/features/live/recognition_frame_contract_test.dart zöld
    test test/features/live/live_frame_adapter_test.dart       zöld
    test test/core/architecture_dependency_test.dart           zöld
    test test/features/live                                    zöld
    test test/core                                             zöld
    architecture                                               zöld
    secrets                                                    zöld
    l10n                                                       zöld
```

### 8.4 Acceptance criteria — a javító kör utáni állapot

A §4 táblázat két nyitott sora zárva:

| # | Kritérium | Verdikt |
|---|---|---|
| 3 | 6×2 backward compat mátrix | ✅ a strum-oldal is fedve (MAJOR-1) |
| — | §6.1 „reject-ok: `lowConfidence`" | ✅ implementálva és mérve (MAJOR-2) |

A többi hét kritérium az első körben már ✅ volt, és a javító kör nem rontotta
el (a teljes `test/features/live` + `test/core` zöld).

### 8.5 A merge-kapu

A merge SHA-ján (a review-frissítést tartalmazó head) ÚJRA kell futnia a Full
Gate + Router CI párnak — a `bd4c36af`/`ab930516` zöldjei a review evidenciái,
nem a merge-éi (ADR 0086 §2). A merge csak azután történhet, hogy mindkettő
`success` a végleges head SHA-n.
