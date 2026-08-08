# E05-R19 — Review

Brief: `docs/rounds/e05-r19-picking-hand-stroke-metrics.md`
Diff: `git diff a382cf7...minimax/e05-r19-picking-hand-stroke-metrics` (pre-flight commits `a2d1797`/`12d3748` excluded — implementer diff is `12d3748..78daad1`, fix-round-1 diff `047ccd1..0670bb6`)
Reviewer: Claude Sonnet 5 (orchestrator) · Dátum: 2026-08-08
Independent gate: fresh clone `/tmp/review-e05-r19` from `https://github.com/wolfcasaba/strumsight.git` (not the shared tree, not the implementer's own workspace)
Verdikt: **APPROVED** (fix-round 1 után, `0670bb6`)

## Összegzés

**Javító kör 1 — záró ellenőrzés.** F1 BLOCKER **FIXED** (`0670bb6`),
függetlenül újra-ellenőrizve saját reprodukciós próbával a javítás UTÁN is
(nem csak az implementer önjelentésére hagyatkozva). Eredeti összegzés
alant, változatlanul, evidenciaként.

BLOCKER: 1 (FIXED) · MAJOR: 0 · MINOR: 0 · NOTE: 2 (nyitva, nem blokkoló)

Egy mért, reprodukált BLOCKER: a `StrokeWindow` csonkolási szabálya
lehetővé teszi, hogy ugyanaz a fizikai minta KÉT egymást követő ablak
mintalistájában is szerepeljen, ami a `strokeAmplitude`/`strokeSpeed`/
`strokeLinearity` értékeket duplán számolja a gyors-váltogatás
forgatókönyvben — pontosan abban a forgatókönyvben, amit a brief §6 első
pontja ("nagyon gyors váltogatás") és a dedikált "Átfedő ablak teszt"
("nem duplikálják a mintákat") kifejezetten előír. A többi hat acceptance
criterion, a mirror/handedness paritás terhelő volta és a sync-kapu
load-bearing volta saját, eldobható mutáció-próbával függetlenül
megerősítve.

## Acceptance criteria

| # | Kritérium | Teljesült | Bizonyíték |
|---|---|---|---|
| 1 | Stroke-fixture-mátrix (le/fel/vegyes/**nagyon gyors váltogatás**) | ⚠️ RÉSZLEGES | `picking_metric_engine_test.dart:43-155` — le/fel/zajos VAN, számolt értékkel (§10.2 `python3 -c` egyezik). **A "nagyon gyors váltogatás" cellának nincs irány/amplitúdó/sebesség/linearitás értéke tesztelve** — a `FastToggleStrokes.sixAt130ms()` fixture kizárólag a `truncated` boolean flag-et ellenőrzi (`:265-286`), a tényleges metrika-értékeket nem. Ld. F1 — ugyanaz a gyökérok. |
| 2 | Sync-mátrix (poor/acceptable/good/excellent, határ mindkét oldala) | ✅ | `:161-217`, mind a 4 cella külön tesztelve. Saját mutáció-próbával (`_eventLevelAllowed` → `true`) megerősítve: a `poor`/`acceptable` cellák PIROSRA váltottak, visszaállítás után zöld. |
| 3 | Nincs-esemény teszt | ✅ | `:223-259` — üres onset-lista → `perEvent` üres, aggregátok `notObservable`. |
| 4 | Átfedő ablak teszt (vágás, **nem duplikálják a mintákat**) | ❌ **NEM teljesült** | `:265-286` csak `truncated` flaget ellenőriz, a mintaszámot/mintaazonosságot SOHA nem. Saját próbateszttel bizonyítva, hogy a duplikáció ténylegesen bekövetkezik — ld. F1. |
| 5 | Mirror/balkezes paritás (2 cella, `HandTrack.handedness`) | ✅ | `:545-601` — ténylegesen variáló 2 cella (`left` vs `right`, minden más mező bit-azonos). Saját mutáció-próbával (hamis `handedness`-ág `_rawDirection`/`strokeDirection`-be injektálva) load-bearingnek igazolva — a teszt PIROSRA váltott, majd a revert után zöld. NEM ismétli meg az E05-R18 F4/L176 hibát. |
| 6 | Aggregát-minimum (n=3 → érték, n=2 → notObservable) | ✅ | `:352-375`, mindkét oldal, `python3 -c` egyező érték (0.931959). |
| 7 | Picking-zóna kategorizáció (§0.0/5 — 4 SDD §20.2 kategória, határ mindkét oldalon) | ✅ | `:414-523` — mind a 4 kategória + mindkét küszöb (0.40, 0.70) mindkét oldala tesztelve. Helyesen ELKÜLÖNÍTVE az R15 `GuitarRegion`-től (saját `PickingZone` enum, saját `PickingZoneThresholds`). |
| 8 | Valódi-sértés próba (§10, sync-kapu) | ✅ | §10.4 dokumentálja a manuális mutációt (`_eventLevelAllowed` → `true`) és a 6 PIROS teszt tranzakcióját; a reviewer saját, független futtatással megerősítette ugyanezt. |
| — | ADR (nincs új) | ✅ | Pre-flight igazolta ADR 0179/0181 ellen (§0.0/1) — nem az implementer felelőssége, előre lezárva. |

## Scope-audit

```
$ python3 tools/scope-audit.py --repo /home/ubuntu/ss-mm-e05-r19 --brief docs/rounds/e05-r19-picking-hand-stroke-metrics.md --base 12d3748
Legacy scope audit OK (12d3748..78daad1eabea, 8 changed path(s), 0 generated/ignored)
```

Engedélyezett fájlokon kívüli változás: **nincs.** Mind a 8 megváltozott
útvonal a brief §4 listáján van (3 lib + 2 test + 1 fixture + `public.dart`
additív export + a brief maga, §10-hez).

## Megállapítások

### F1 — BLOCKER — `StrokeWindow.cut()` csonkolása nem zárja ki az átfedést a szomszédos ablakok mintái között; a duplikált minták torzítják az amplitúdó/sebesség/linearitás metrikát gyors váltogatásnál

- **Fájl:** `lib/features/vision/domain/metrics/stroke_window.dart:104-140` (a `cut()` metódus), a hatás `lib/features/vision/domain/metrics/picking_metric_engine.dart:484-497` (`_pathSegments`) ÉS minden hívóján (`strokeAmplitude`/`strokeSpeed`/`strokeLinearity`/`_rawAmplitude`/`_rawSpeed`) keresztül érvényesül.
- **Probléma:** a csonkolás (`truncatedToNext`) az ablak VÉGÉT a KÖVETKEZŐ onset NYERS timestampjéig engedi ("actualEnd = truncatedToNext"), de a következő ablak SAJÁT eleje `nextOnset.timestamp - pre` — ami MINDIG korábbi, mint `nextOnset.timestamp` (mivel `pre > 0`). A `[nextOnset - pre, nextOnset)` sávba eső minták ezért MINDKÉT ablak `samples` listájában szerepelnek egyszerre.
- **Reprodukálva** (eldobható próbateszt, a review-ban futtatva, NEM commitolva) a repóban már meglévő `FastToggleStrokes.sixAt130ms()` fixture-rel (`onset[0]=0ms`, `onset[1]=130ms`, alapértelmezett `pre=100ms`/`post=150ms`):
  ```
  window0 samples: [-100, -67, -34, -1, 32, 65, 98]
  window1 samples: [32, 65, 98, 131, 164, 197, 230]
  shared timestamps between window0 and window1: {32, 65, 98}
  ```
  A `{32, 65, 98}` minták BÁRMELYIK szomszédos ablak `_pathSegments`
  hívásában szerepelnek — a `(32→65)` és `(65→98)` szegmensek TÉNYLEGESEN
  duplán adódnak `window0.amplitude`-hoz (a farkán) ÉS `window1.amplitude`-hoz
  (az elején) is, mert a `_pathSegments` a saját `samples` listáján belüli
  EGYMÁS UTÁNI mintapárokat összegzi, függetlenül attól, hogy azok egy másik
  ablakban is szerepelnek-e.
- **Hatás:** a §6 első acceptance-pontja explicit megköveteli a "nagyon
  gyors váltogatás" cellát irány/amplitúdó/sebesség/linearitás elvárt
  értékkel — ez az EGYETLEN forgatókönyv, ahol a csonkolás egyáltalán
  aktiválódik (lásd a fixture-mátrix hiányát is, acceptance #1 fent). A
  duplikáció torzítja pontosan azt a metrikát (amplitúdó/sebesség/
  linearitás), amit a brief a leginkább aggódik — a shippelt kód ma egy
  gyors le-fel váltogatásnál RENDSZERESEN túlbecsüli az amplitúdót/
  sebességet a szomszédos ablakok határán, és a `beatToBeatConsistency`
  aggregátumot is torzítja (ami a `_rawAmplitude`-en keresztül ugyanezt a
  duplikált path-hosszt fogyasztja).
- **Kötelező javítás:** a `StrokeWindow.cut()` csonkolási szabálya
  garantálja, hogy egy adott timestamp-ű minta LEGFELJEBB EGY ablak
  `samples` listájában szerepeljen (pl. az ablak vége ne a következő onset
  nyers timestampjéig, hanem a következő ablak SAJÁT kért kezdetéig —
  `nextOnset.timestamp - nextPre` — csonkoljon; vagy egy explicit
  particionáló lépés zárja ki az átfedést). A pontos megoldást az
  implementer választja — a review nem ír patchet —, de a következő
  poszt-kondíciónak kötelezően teljesülnie kell: **semmilyen minta
  timestamp nem szerepelhet egynél több `PickingStrokeCut.samples`
  listában.** Ezzel egyidejűleg egy ÚJ, VALÓS mintákkal futtatott teszt is
  kell (nem üres `frames: []`, mint a jelenlegi "six-on-130ms" teszt), ami
  ténylegesen a mintaszámot/mintahalmazt asszertálja átfedő ablakokra —
  ez a brief §6 "a mintaszám assertálva" szó szerinti előírása, amit a
  jelenlegi teszt-csoport nem teljesít. Emellett a §6 első acceptance-
  pontja ("nagyon gyors váltogatás" irány/amplitúdó/sebesség/linearitás
  elvárt értékkel) is hiányzik — a javítás után egy `python3 -c`-vel
  számolt, deduplikált-path várt értékkel kiegészítendő a
  "stroke fixture matrix" csoport.
- **Ellenőrzés:** az új teszt a javítás ELŐTT PIROS (a fenti próba
  megismétlésével — két szomszédos `cuts[i].samples`/`cuts[i+1].samples`
  metszete NEM üres), a javítás UTÁN ZÖLD (a metszet üres MINDEN
  szomszédos párra a `FastToggleStrokes.sixAt130ms()` fixture-ön), és a
  meglévő csonkolás-flag tesztek (`window.truncated`, `window.end`) a
  megváltozott határ-szemantikával összhangban frissítve/újraellenőrizve.
- **Státusz:** **FIXED** (`0670bb6`). A javítás a csonkolási határt a
  következő onset NYERS timestampja helyett a következő ablak SAJÁT
  kért kezdetére (`nextOnset.timestamp - pre`) mozgatja
  (`stroke_window.dart` `cut()`, `nextRequestStart`). Két új regressziós
  teszt: (1) `stroke_window_test.dart` "adjacent windows share NO sample
  timestamps" — páronkénti metszet-üresség VALÓS mintákkal; (2) "every
  sample is included in EXACTLY one window (global partition)" — erősebb
  invariáns, a teljes idővonalon minden minta PONTOSAN egy ablakhoz
  tartozik. A hiányzó "nagyon gyors váltogatás" érték-cella is pótolva:
  `picking_metric_engine_test.dart` új "stroke fixture matrix — fast
  toggle" csoport, mind a négy metrika (irány/amplitúdó/sebesség/
  linearitás) tényleges, `python3 -c`-vel számolt várt értékkel mind a 6
  ablakra.
  **Reviewer saját, független megerősítése** (nem az implementer
  önjelentésére hagyatkozva): a review saját, eldobható próbateszttel
  (a `FastToggleStrokes.sixAt130ms()` 6-onsetes, teljes idővonalán, MINDEN
  szomszédos ablakpárra) megismételte az eredeti reprodukciós mérést a
  javítás UTÁNI kódon — a metszet MINDEN párra üres:
  ```
  window0 ∩ window1 = {} (window0=[-100, -67, -34, -1], window1=[32, 65, 98, 131])
  window1 ∩ window2 = {} (window1=[32, 65, 98, 131], window2=[164, 197, 230, 263])
  window2 ∩ window3 = {} (window2=[164, 197, 230, 263], window3=[296, 329, 362, 395])
  window3 ∩ window4 = {} (window3=[296, 329, 362, 395], window4=[428, 461, 494, 527])
  window4 ∩ window5 = {} (window4=[428, 461, 494, 527], window5=[560, 593, 626, 659, 692, 725, 758, 791])
  ```
  A teljes gate friss, független klónon (`/tmp/review-e05-r19`) újra
  lefuttatva a javítás utáni HEAD-en (`0670bb6`): format/analyze/test
  (292/292)/architecture/secrets/l10n mind ZÖLD.

### N1 — NOTE — `Δv > 0 → down` numerikus ±1 kódolás, nem `StrumDirection`

A brief §0.0/4 pre-flight-guidance-a a core `StrumDirection` közvetlen
visszaadását javasolta a duplikált enum elkerülésére. Az implementer ehelyett
egy dokumentált ±1.0 numerikus konvenciót adott vissza (§10.6), azzal az
indoklással, hogy a `MetricObservation.value` szerződése (`double?`, R18)
eleve nem tudna `StrumDirection`-t hordozni, és a `StrumDirection`-ra
alakítás a hívó rétegé. Ez egy ésszerű, a container-típus valódi
megkötéséből fakadó, dokumentált eltérés — NEM hoz létre párhuzamos enumot
(a guidance valódi szándéka), nem blokkoló.

### N2 — NOTE — `PickingSessionResult.zoneDistribution` nincs `MetricObservation`-be csomagolva

A `zoneDistribution` egy nyers `Map<PickingZone, double>`, sosem
`notObservable` (üres eseménylistánál üres map-et ad, nem egy explicit
"nem megfigyelhető" jelzést). A brief nem írt elő erre explicit
acceptance-kritériumot, és a mögöttes `perEvent` már helyesen jelzi az
egyedi zónák megfigyelhetőségét — de egy jövőbeli hívó számára kétértelmű
lehet, hogy az üres map "nulla esemény" vagy "nem mérhető" jelentésű.
Nem blokkoló, follow-up jelölésre javasolt.

## Gate-bizonyíték ellenőrzése

| Gate | Állított eredmény (§10.3) | Ellenőrizve (saját, friss klón) |
|---|---|---|
| format | zöld | ✅ (`dart format`, 1136 fájl, 0 változás) |
| analyze | zöld | ✅ (`flutter analyze lib/ test/ tool/`, 0 hiba) |
| test test/features/vision | zöld, 174 (113+11+50) | ✅ — a teljes `test/features/vision` alfa (286 teszt, a 174 egy szűkebb önjelentett részhalmaz) mind zöld |
| architecture | zöld | ✅ (12 előzetesen engedélyezett eltérés, egyik sem ebből a diffből) |
| secrets | zöld | ✅ (1973 fájl, 0 lelet) |
| l10n | zöld | ✅ (en→hu, 964 üzenet) |
| Mirror-paritás load-bearing | állítva | ✅ saját mutáció-próba: hamis `handedness`-ág → PIROS → revert → zöld |
| Sync-kapu load-bearing | állítva, §10.4 | ✅ saját mutáció-próba: `_eventLevelAllowed` → `true` → 5 teszt PIROS → revert → zöld |
| Átfedő ablak — nincs duplikáció | eredetileg állítva (csak `truncated` flag), javítás UTÁN: valódi partíció | ✅ **fix-round 1 (`0670bb6`) UTÁN**: saját próba, minden szomszédos ablakpár metszete üres (fent idézve) + globális partíció teszt |
| test test/features/vision (fix-round 1 után) | 292/292 zöld | ✅ saját, friss klónon független futtatással megerősítve |
| CI (teljes suite + property + APK) | — | orchestrátor dispatch-eli ezután, a `0670bb6` SHA-n |

## Merge-döntés

**F1 BLOCKER FIXED, nulla nyitott BLOCKER/MAJOR marad.** Az ADR 0052
szerint: minden gate zöld ÉS nincs nyitott BLOCKER/MAJOR → merge. A CI
(Full Gate + Router CI) dispatch-e és az exact-SHA zöld kapu ellenőrzése
az orchestrátor következő lépése; a squash-merge azt követően, külön
jóváhagyás nélkül.
