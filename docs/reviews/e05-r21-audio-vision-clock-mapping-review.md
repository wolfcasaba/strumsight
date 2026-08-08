# E05-R21 — Review

Brief: docs/rounds/e05-r21-audio-vision-clock-mapping.md
Diff: `git diff 52fcf8d..68face1` (pre-flight commit → implementer commit, branch `codex/e05-r21-audio-vision-clock-mapping`)
Reviewer: Claude Sonnet 5 (orchestrátor) · Dátum: 2026-08-08
Verdikt: **APPROVED**

## Összegzés

BLOCKER: 0 · MAJOR: 0 · MINOR: 0 · NOTE: 4

Egyetlen implementer-forduló (`continuations=0`), gate-alak és scope-audit
gépi jelzése is `ok`. A gate-et saját kézzel, izolált `/tmp/review-e05-r21`
klónban újrafuttattam (nem az implementer önjelentésére hagyatkozva), és egy
harmadik, eldobható `/tmp/mutate-e05-r21` klónban a §6 „valódi-sértés próba"
kritériumot magam is előidéztem — a forrás-guard teszt ténylegesen pirosra
vált, majd a mutációt eldobtam.

## Acceptance criteria

| # | Kritérium | Teljesült | Bizonyíték |
|---|---|---|---|
| 1 | Offset-mátrix, ≥5 érték, köztük 0 és negatív | ✅ | `clock_mapping_test.dart` `recovers known offset $offsetUs µs` öt értékre: -25000, -1, 0, 1, 37000 — mind pontos egyezés, `driftPpm=0`, `confidence=1` |
| 2 | Outlier-teszt: N valid + 1 durva hiba → offset gyakorlatilag változatlan, elutasított minta a statisztikában | ✅ | `rejects one large outlier without moving the offset`: 4 valid (offset 12345) + 1 durva (5 000 000/500 000 pár) → `mapping.offsetUs=12345` változatlan, `rejectedSamples=1`, `confidence=0.8` |
| 3 | Bucket-mátrix minden határ alatt/rajta/fölött, `python3 -c` számolva | ✅ | `sync quality boundary matrix` csoport (4 teszt) — a határértékeket a THRESHOLD KONSTANSOKBÓL számítja (`excellentMaximumErrorUs ± 1` stb.), nem hardcode-olt számból, ami a hardcode-olt táblánál is robusztusabb. Saját `python3 -c` újraszámítás (lásd alább) betű szerint egyezik a §10 táblával |
| 4 | Property teszt (`PROPERTY_SEED`), %-alapú küszöb | ✅ | `clock_mapping_property_test.dart`: seed env-ből (`PROPERTY_SEED`, alapértelmezett 42), 64 random trial × 11 mappelt pont, `errorRate ≤ 0.01`. Saját futtatás: ZÖLD, `PROPERTY_SEED=42` |
| 5 | Monotonicitás-teszt: nem monotonic bemenet → kontrollált hiba | ✅ | `a non-monotonic audio timestamp fails explicitly` + `a non-increasing camera timestamp fails explicitly` — mindkét óra `ClockMappingException`-t dob, nem rendez át némán |
| 6 | Újramérés-teszt: korábbi observationök időbélyege változatlan | ✅ | `sync_calibration_controller_test.dart` `recalibration preserves already-issued observation provenance` — a recalibráció ELŐTT kiadott `MappedObservation.mapping.offsetUs` (1000) a recalibráció UTÁN is 1000 marad, az ÚJ kiadás -2000-et használ |
| 7 | Valódi-sértés próba: `DateTime.now()` a mappingbe → monotonicitás/determinizmus teszt PIROS → visszaállítás | ✅ | Permanens forrás-guard teszt (`mapping-domain sources contain no system wall-clock read`, szó szerinti `'DateTime.now('` grep a 3 mapping-fájlon) + **saját, független mutáció**: `AudioClock.toSessionTime`-ba `DateTime.now()` beszúrva egy harmadik klónban → pontosan 1 teszt bukott (a guard maga), a többi 15 zöld maradt → mutáció eldobva |

## Scope-audit

Engedélyezett fájlokon kívüli változás: **nincs**. `git diff --stat 52fcf8d..68face1` — 9 fájl, mind a brief §4 listáján (4 új domain/application fájl, `public.dart` additív export, 3 új teszt, `docs/rounds/e05-r21-*.md` §10 kitöltés). A wrapper saját gépi scope-auditja is `scope_audit=ok`, `scope_audit_changed=9`, bázis a pre-flight commit (`52fcf8d`) — egyezik a saját méréssel.

## Megállapítások

### F1 — NOTE — `AudioClock`/`VisionClock` eltérő szigorúságú monotonicitás-őr, dokumentálatlanul

- **Fájl:** `lib/features/vision/domain/sync/vision_clock.dart:53` (`VisionClock`, `compareTo(previous) <= 0` → egyenlőségre IS dob) vs. `:77` (`AudioClock`, `isBefore(previous)` → egyenlőségre NEM dob).
- **Probléma:** a két óra különböző szigorúsággal definiálja a "monotonic": `VisionClock` szigorú növekedést követel, `AudioClock` csak nem-csökkenést (ismétlődő `DateTime` érték átmegy).
- **Hatás:** funkcionálisan indokolt (a §5.1 mérése szerint az audio `DateTime`-forrás felbontása platformfüggően durvább lehet, mint a vision oldal mesterségesen szigorú Stopwatch-őre — egy valódi, egyidejűnek látszó két audio-frame hamis hibát dobna szigorú összehasonlítással), de a kódban NINCS erre utaló komment, és a brief sem mondja ki explicit módon, hogy a két őrnek különböznie kell.
- **Kötelező javítás:** nem kötelező ebben a körben — javasolt egy egysoros komment az `AudioClock.toSessionTime`-nál, ami rögzíti, hogy az egyenlőség szándékosan megengedett (a `DateTime`-forrás felbontása miatt), nehogy egy jövőbeli takarítás "egységesítse" a két őrt.
- **Ellenőrzés:** nem igényel új tesztet, dokumentációs kiegészítés.
- **Státusz:** OPEN (follow-up, nem blokkoló).

### F2 — NOTE — `ClockMapping.defaultMaximumAbsoluteDriftPpm` nincs "provizórikus" jelzéssel dokumentálva

- **Fájl:** `lib/features/vision/domain/sync/clock_mapping.dart:57`.
- **Probléma:** a `sync_quality.dart` küszöbei explicit "provisional until the pending device benchmark" kommenttel vannak jelölve; az 500 ppm drift-határ doc-commentje ("Maximum permitted drift before extrapolation becomes unsafe.") nem jelzi, hogy ez is a valós-eszközös benchmarkra vár (brief §9).
- **Hatás:** kozmetikus — a round-szintű §9 Kockázatok szakasz már lefedi ezt, de fájl-szinten egy olvasó tévesen véglegesnek hiheti a konstanst.
- **Kötelező javítás:** nem kötelező; javasolt egyszavas "provisional" jelző a doc-commentbe egy jövőbeli hangoló körben.
- **Ellenőrzés:** —
- **Státusz:** OPEN (follow-up, nem blokkoló).

### F3 — NOTE — Nincs teszt a `calibrate(estimateDrift: true)` → túl nagy drift → érvénytelen mapping teljes láncára

- **Fájl:** `lib/features/vision/application/sync_calibration_controller.dart:67-78`.
- **Probléma:** a "drift a határon túl érvényteleníti a mappinget" invariáns (§5/4) `ClockMapping`-szinten közvetlenül tesztelt (`mapping with excessive drift is invalid instead of extrapolated`), de nincs teszt, ami a `SyncCalibrationController.calibrate(..., estimateDrift: true)`-ot valódi, szélsőséges mintákkal hívva ellenőrizné, hogy a **becsült** (nem kézzel megadott) `driftPpm` a határ fölé kerülve ugyanígy `isValid == false` eredményt ad.
- **Hatás:** alacsony kockázatú rés — a becsült `driftPpm` a `ClockMapping` konstruktorba változtatás nélkül, egyetlen mezőként kerül át (nincs köztes elágazás, ami elronthatná), így a hiányzó teszt inkább hiányos lezárás, mint valószínű hiba forrása.
- **Kötelező javítás:** nem kötelező ebben a körben; javasolt egy fixture (pl. két, mesterségesen ellentétes irányú, nagy meredekségű mintapár) egy későbbi javító/hangoló körben.
- **Ellenőrzés:** egy jövőbeli teszt, ami `calibrate(estimateDrift: true)`-tal szélsőséges mintasort ad, és `result.mapping.isValid == false`-t vár.
- **Státusz:** OPEN (follow-up, nem blokkoló).

### F4 — NOTE — §10 a bucket-mátrix EREDMÉNYÉT idézi, a szó szerinti `python3 -c` parancsot nem

- **Fájl:** `docs/rounds/e05-r21-audio-vision-clock-mapping.md` §10.
- **Probléma:** a brief §6 betű szerint "a cellák értékét `python3 -c` számolja (a §10-ben idézve)" — a §10 egy kész táblázatot közöl, a parancs maga nincs beidézve.
- **Hatás:** nincs — saját, független `python3 -c` újraszámítás (lásd Acceptance #3) betűre egyezik a táblával, és a tényleges Dart-tesztek a küszöb-KONSTANSOKBÓL, nem hardcode-olt számokból számolnak, ami a brief betűjénél is erősebb védelem a konstans-drift ellen.
- **Kötelező javítás:** nem szükséges — dokumentálva, hogy a lelet formai, nem tartalmi.
- **Ellenőrzés:** —
- **Státusz:** OPEN (formai follow-up, nem blokkoló).

## Gate-bizonyíték ellenőrzése

| Gate | Állított eredmény (implementer) | Ellenőrizve (reviewer, `/tmp/review-e05-r21`) |
|---|---|---|
| format | 8 fájl formázva | ✅ saját futtatás, zöld |
| analyze | (a teljes gate részeként) | ✅ saját futtatás, zöld |
| test test/features/vision | 353 teszt, mind zöld | ✅ saját futtatás, 353 teszt, mind zöld |
| test test/property/clock_mapping_property_test.dart | zöld, `PROPERTY_SEED=42` | ✅ saját futtatás, zöld |
| architecture | — | ✅ saját futtatás, "12 allowlisted deviation(s)" — egyik sem az új `sync/`-fájlokra (grep-ellenőrizve, nulla találat) |
| secrets | — | ✅ saját futtatás, 1991 fájl, 0 lelet |
| l10n | — | ✅ saját futtatás, en→hu, 964 üzenet, parity OK |
| Valódi-sértés próba (§6/7) | forrás-guard teszt leírva | ✅ saját, független mutáció (`/tmp/mutate-e05-r21`): a guard PIROSAT adott, semmi más nem bukott |
| CI (teljes suite + property + APK) | — | PENDING — a review után dispatch-elem (`round-ci-plan.py`) |

Minden gate-parancs SAJÁT kézzel, izolált `/tmp` klónban futtatva, csonkítatlan
kimenettel — a `tools/round-gate.sh` egyetlen futtatható artefaktumként, nem
a kör branch közös munkapéldányában.

## Merge-döntés

ADR 0052 szerint: minden helyi gate zöld ÉS nincs nyitott BLOCKER/MAJOR →
**mehet a CI-dispatch, majd a merge**, a CI (teljes suite + randomizált
property + router-ci, ha releváns) zöldjének exact-SHA ellenőrzése után. A
négy NOTE dokumentálva, follow-upként nyitva hagyva — egyik sem blokkolja a
mai mérget.
