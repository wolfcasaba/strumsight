# E06-R19 — Review

Brief: `docs/rounds/e06-r19-confidence-calibration-capability-resolver.md`
Diff: `git diff cc8faca1...codex/e06-r19-confidence-calibration-capability-resolver`
Reviewer: Claude (Sonnet 5) · Dátum: 2026-08-12
Verdikt: **APPROVED** (javító kör után; első pass CHANGES REQUESTED volt)

## Összegzés

Végső: BLOCKER: 0 · MAJOR: 0 · MINOR: 0 · NOTE: 1 (nem blokkoló follow-up)
Első pass: BLOCKER: 0 · MAJOR: 1 (F1) · MINOR: 1 (F2, nyitva marad follow-upként) · NOTE: 1 (F3, javítva)

Az implementáció szerkezetileg tiszta, a §6 mind a kilenc acceptance criterionja
mérve teljesül (beleértve a pre-flight során javított geometriai-átlag
referenciaértéket, `0.5799546134795288`, amit a teszt bitre pontosan
visszaad). Az első pass egy valódi, reprodukált crash-t (F1, MAJOR) talált —
a resolver kivételt dobott, ha egyetlen capability sem `notApplicable`-től
különböző (`supportedCapabilities: {}`) —, amit a javító kör (commit
`ba713d28`) lezárt: explicit üres-`overallFactors` ág, `notApplicable`
overall verdikttel, dedikált teszttel. **Függetlenül újra futtatott gate
(friss `/tmp` klón) és saját próbateszt** (a korábban crash-elő bemenetet
megismételve) is megerősíti a javítást — lásd „Javító kör utáni ellenőrzés".
F3 (teszt-fixture mutáció) szintén javítva, bónuszként, ugyanabban a
commitban. F2 (a „min a kritikus capabilityken" §5.2-prózahűség) szándékosan
NYITVA maradt — nem blokkoló, dokumentált follow-up (lásd lent).

## Acceptance criteria

| # | Kritérium | Teljesült | Bizonyíték |
|---|---|---|---|
| 1 | Capability-mátrix, 9 bemeneti eset | ✅ | `capability_resolver_test.dart:10-111`, mind a 14 capability státusza+oka ellenőrizve esetenként |
| 2 | Küszöb-hármasok (0.3999/0.4/0.4001/0.6999/0.7/0.7001) | ✅ | `capability_resolver_test.dart:113-135`; kód: `capability_resolver.dart:275-283` inkluzív `>=` mindkét határon |
| 3 | Nincs átlag (geometriai `0.5799546134795288` ≠ 0.74) | ✅ | `confidence_combiner_test.dart:5-11`; független `python3 -c` ellenőrzés ugyanezt adta (lásd brief §0.0 3. pont) |
| 4 | Kritikus capability hatása (signalQuality unavailable → overall ≤ degraded) | ✅ (lásd F2) | `capability_resolver_test.dart:170-181`, `isNot(available)` — a gyakorlatban mindig `unavailable`-ra esik, sosem ténylegesen `degraded`-re, ld. F2 |
| 5 | Kalibráció-jelölés (`identity.v1`, sosem hamis `calibrated`) | ✅ | `capability_resolver_test.dart:137-150`, `capability_report_test.dart:23-34` (valódi-sértés jellegű: a guard kivételt dob vegyes verzió/forrásra) |
| 6 | Monotonitás property | ✅ | `analysis_confidence_property_test.dart`, 200 seedelt próba, `PROPERTY_SEED` tiszteletben tartva |
| 7 | Ok-lokalizáció teljesség | ✅ | `capability_report_test.dart:8-21` a valódi enumon iterál; függetlenül újraszámolva: 13/13 kulcs mindkét ARB-ben, l10n-parity gate zöld |
| 8 | Egyetlen döntési pont (§0.0 szerint az ÚJ modulra szűkítve) | ✅ | `capability_resolver_test.dart:184-200`; függetlenül `grep -c "CapabilityStatus\."` a 4 fájlon: csak `capability_resolver.dart`-ban (11 találat), a többi 0 |
| 9 | Determinizmus (100 futás bitazonos) | ✅ | `capability_resolver_test.dart:152-168` |

## Scope-audit

`git diff --stat cc8faca1...HEAD` (a pre-round `main`-től): 12 `lib/`+`test/`
fájl, mind az `allowed_paths` listáján, 1:1 megfeleltetve (4 új
`engine/confidence/*.dart`, `domain/analysis_capability.dart` additív,
`public.dart` export, 2 ARB, 4 teszt). **Listán kívüli változás: nincs.**
`scope_audit=ok` a jelzésfájlban, függetlenül megerősítve.

Az `analysis_capability.dart` bővítése valóban **tisztán additív**: egy új
enum (`ConfidenceCalibrationSource`), két új opcionális, alapértelmezett
értékű mező a `CapabilityReport`-on, és egy **szigorúbb** (nem gyengébb)
`confidence` guard (`isFinite` hozzáadva a korábbi `< 0 || > 1`-hez — ez
pontosan azt a NaN-rést zárja, amit a `docs/reviews/e06-r07-signal-quality-stage-security.md`
NOTE-2 és hasonló korábbi review-k dokumentáltak máshol). Egyetlen meglévő
enum-érték vagy mező nem változott/tűnt el.

## Megállapítások

### F1 — MAJOR — `CapabilityResolver.resolve()` kivételt dob üres `supportedCapabilities`-re

- **Fájl:** `lib/features/audio_analysis/engine/confidence/capability_resolver.dart:113-115`,
  `lib/features/audio_analysis/engine/confidence/confidence_combiner.dart:38-41`
- **Probléma:** ha minden capability `notApplicable`-re oldódik (a
  legegyszerűbb reprodukció: `CapabilityResolverInput(..., supportedCapabilities:
  const <AnalysisCapability>{})`), az `overallFactors` lista üres marad, és a
  `ConfidenceCombiner.combine([])` a `factors.isEmpty` ágon
  `ArgumentError('Confidence factors must be finite and in [0, 1].')`-t dob —
  **mielőtt** a `hardGateOpen` ellenőrzés egyáltalán lefutna. Reprodukálva
  (eldobható próbateszt, futtatva és törölve, lásd lent): a hívás ténylegesen
  kivétellel áll meg, nem gracefules `CapabilityResolution`-nel tér vissza.
- **Miért valós kockázat, nem elméleti:** a `supportedCapabilities` paraméter
  konstruktora (`capability_resolver.dart:9-35`) nem tiltja az üres halmazt,
  és a mező szemantikailag pontosan ezt az esetet ("ehhez a felvételhez
  semmilyen capability nem érvényes", pl. teljesen sérült/ismeretlen formátumú
  input) van hivatva kifejezni. A testvér-kapuk **ugyanezt** az esetosztályt
  gracefully kezelik: `PitchCapabilityGate.evaluate` `frames.isEmpty`-re
  `_unavailable(insufficientEvents)`-t ad (`pitch_capability_gate.dart:75-77`),
  nem kivételt. A resolver az egyetlen a három kapu közül, amelyik degenerált,
  de érvényesen konstruálható bemenetre crash-el ahelyett, hogy státuszt adna.
- **Hatás:** amint egy jövőbeli kör bekapcsolja a resolvert (a brief §0.0
  szerint ez már NEM ennek a körnek a scope-ja, de a resolver KÖZVETLEN
  KÖVETKEZŐ fogyasztója ebbe bele fog futni), egy legitim "nincs mérhető
  capability" bemenet a teljes Analyze-folyamatot elszállítja egy kezeletlen
  kivétellel ahelyett, hogy egy `unavailable`/`notApplicable` overall
  állapotot adna — pontosan az a hiba-osztály, amit a §5 „gyenge confidence
  nem jelenhet meg biztos állításként” elve és az egész capability-modell
  (ADR 0219) meg akar előzni: itt nem hibás állítás a hiba, hanem egy csendes
  crash, ami rosszabb.
- **Kötelező javítás:** `CapabilityResolver.resolve()` a `combine()` hívás
  előtt (vagy a `ConfidenceCombiner.combine()` belsejében, felüldefiniálva az
  üres-lista esetet) kezelje explicit módon az üres `overallFactors` esetet —
  pl. `overallStatus: CapabilityStatus.notApplicable, overallConfidence: 0`,
  analóg módon a per-capability `notApplicable` ághoz. A választott
  viselkedést dokumentálja doc-comment, és fedje le teszt.
- **Ellenőrzés:** egy új teszteset (`CapabilityResolverInput(...,
  supportedCapabilities: const <AnalysisCapability>{})`) ne dobjon, és az
  `overallStatus`/`overallConfidence` a választott, dokumentált értéket adja.
- **Státusz:** FIXED (`ba713d28`) — explicit üres-`overallFactors` ág
  `capability_resolver.dart:114-122`, `overallStatus:
  CapabilityStatus.notApplicable, overallConfidence: 0`; dedikált teszt
  (`capability_resolver_test.dart` „returns a not-applicable overall when no
  capabilities are supported”). Függetlenül újra-reprodukálva a javítás
  UTÁN (saját próbateszttel, friss `/tmp` klónban) — a korábban dobó hívás
  most `notApplicable`/`0`-t ad, nem dob. Lásd „Javító kör utáni ellenőrzés".

### F2 — MINOR — a „kritikus capability” hatás csak bináris kapu, nem a brief §5.2 szerinti „min”

- **Fájl:** `lib/features/audio_analysis/engine/confidence/capability_resolver.dart:105-123`
- **Probléma:** a brief §5 pont 2 szó szerint „`min` a kritikus
  capabilityken, súlyozott aggregátum a többin” szabályt ír elő. A
  implementáció ehelyett egy bináris kapcsolót valósít meg: ha BÁRMELYIK
  kritikus capability (`signalQuality`/`onsetTimeline`) pontosan
  `unavailable`, az `overallConfidence`-t nullára kényszeríti
  (`hardGateOpen: !criticalUnavailable` →
  `ConfidenceCombiner.combine`-ban `!hardGateOpen` ág, `confidence: 0`,
  lásd `confidence_combiner.dart:42-44`) — ez mindig `overallStatus =
  unavailable`-t ad, SOSEM ténylegesen `degraded`-et, holott a brief
  szövege és a §6 kritérium („legfeljebb degraded”) egy fokozatosabb,
  degraded-re képes viselkedést sugall. Ha egy kritikus capability csak
  `degraded` (nem `unavailable`, pl. confidence 0.41), a jelenlegi kód ezt
  csak EGYETLEN tényezőként keveri a geometriai átlagba a többi (akár 13)
  capabilityvel egyenlő súllyal — egy 14 tényezős geometriai átlagban egy
  0.41-es kritikus érték alig húzza le az eredményt, miközben a brief
  „min a kritikus capabilityken” elve azt sugallja, hogy a kritikus
  capability gyengeségének DOMINÁLNIA kellene, nem csak hígulnia.
- **Miért nem BLOCKER/MAJOR:** a §6-ban expliciten pinnelt, mérhető
  acceptance criterion („signalQuality unavailable → overall NEM
  available”) betű szerint teljesül minden lefedett esetben, és a
  mérce-mátrix (§6.1) sem nevez meg ehhez tartozó piros cellát a
  „degraded, nem unavailable” megkülönböztetésre. A modul ma teljesen
  bekötetlen (0 fogyasztó), tehát a résnek nincs jelenlegi termékhatása.
- **Javasolt irány (nem kötelező ebben a körben):** egy jövőbeli bekötő/
  kalibrációs kör (R29 vagy a retrofit-kör) explicit tesztelje és szükség
  esetén implementálja a „kritikus capability confidence-e ténylegesen
  `min`-ként korlátozza az overallt” viselkedést a jelenlegi bináris
  kapu helyett — vagy, ha a bináris kapu a szándékos, konzervatívabb
  döntés, az ADR 0237 egy mondatos kiegészítése zárja le a
  kétértelműséget explicit döntésként.
- **Státusz:** OPEN (follow-up, nem blokkol)

### F3 — NOTE — megosztott mutable fixture a 9-eset mátrix tesztben

- **Fájl:** `test/features/audio_analysis/engine/capability_resolver_test.dart:11,62-65,94`
- **Probléma:** a 7. teszteset `allCapabilities..remove(AnalysisCapability.dynamicConsistency)`
  kaszkádot használ a `supportedCapabilities` mezőhöz — ez a `final
  allCapabilities` változót (11. sor) MAGÁT mutálja (nem másolatot készít),
  mert a `cases` lista-literál minden eleme a `for` ciklus ELŐTT, egyszerre
  épül fel. Ennek eredményeként a 94. soron lévő `containsAll(allCapabilities)`
  a ciklus MINDEN (mind a 9) esetére egy 13, nem 14 elemű halmaz ellen
  ellenőriz — a `dynamicConsistency` kimarad a bizonyított invariánsból.
- **Miért NOTE, nem MINOR:** a közvetlenül fölötte lévő
  `expect(result.reports, hasLength(AnalysisCapability.values.length))`
  (93. sor) egy nem-mutálható forrásból (`AnalysisCapability.values.length`)
  számol, és ez már önmagában bizonyítja, hogy egyetlen capability sem
  hiányzik egyetlen esetben sem — a `containsAll` gyengülése nem nyit
  tényleges lefedettségi rést, csak redundáns.
- **Javasolt irány:** `allCapabilities.toSet()..remove(...)` (másolat) a 7.
  esetben, hogy a fixture ne mutálódjon — kozmetikai, nem sürgős.
- **Státusz:** FIXED (`ba713d28`, bónuszként a javító körben, nem volt
  kötelező) — `allCapabilities.toSet()..remove(...)`.

## Javító kör utáni ellenőrzés

1. **Diff-audit:** `git diff c3d71c76...ba713d28` — 3 fájl
   (`capability_resolver.dart`, `capability_resolver_test.dart`, a brief §10
   handoff-frissítése), mind az `allowed_paths`-on belül. `scope_audit=ok`
   (jelzésfájl, `scope_audit_changed=3`), függetlenül megerősítve.
2. **Gate újra, MÁSODIK friss `/tmp` klónban** (`/tmp/review-e06-r19-fix1`,
   nem ugyanaz, mint az első pass klónja) — `tools/round-gate.sh
   test/features/audio_analysis test/property test/app`: mind a nyolc lépés
   zöld.
3. **Saját eldobható próbateszt megismételve** a fix UTÁN (ugyanaz a bemenet,
   ami az első pass-ban dobott): `resolve()` most `overallStatus ==
   CapabilityStatus.notApplicable`, `overallConfidence == 0` — NEM dob.
   Próbafájl futtatva, majd törölve (`git status` tiszta a klónban).
4. **F3 zárás ellenőrizve:** a 7. teszteset most `.toSet()`-tel másol, az
   `allCapabilities` változó a ciklus alatt változatlan 14 elemű marad.

## Gate-bizonyíték ellenőrzése

| Gate | Állított eredmény | Ellenőrizve |
|---|---|---|
| format | zöld (implementer) | ✅ saját `/tmp/review-e06-r19` klónban újrafuttatva, zöld |
| analyze | zöld (implementer) | ✅ újrafuttatva, zöld |
| test test/features/audio_analysis | zöld (implementer, 11/11 célzott) | ✅ újrafuttatva a teljes `test/features/audio_analysis` fán, zöld |
| test test/property | zöld (implementer) | ✅ újrafuttatva, zöld |
| test test/app | zöld (implementer) | ✅ újrafuttatva, zöld |
| architecture | zöld (implementer) | ✅ újrafuttatva, zöld (12 allowlisted deviation — meglévő, nem ebből a körből) |
| secrets | — | ✅ újrafuttatva, zöld (0 finding) |
| l10n parity | — | ✅ újrafuttatva, zöld (en→hu, 1070 üzenet) |
| CI (teljes suite + property + APK) | — | ⏳ még nem dispatch-elve — az orchestrátor a review után indítja |

Mind a nyolc lokális gate-lépést **saját kézzel, izolált `/tmp/review-e06-r19`
klónban** futtattam újra (`tools/round-gate.sh test/features/audio_analysis
test/property test/app`), nem fogadtam el az implementer állítását
bemondásra. Emellett egy külön, eldobható próbateszttel (lásd F1)
reprodukáltam a crash-t, majd töröltem a próbafájlt — a jelenlegi
munkapéldány tiszta, csak a review-jelentés az új tartalom.

## Biztonsági review

Kötelező (`risk = "high"`) — külön dokumentumban:
`docs/reviews/e06-r19-confidence-calibration-capability-resolver-security.md`.
**Verdikt: PASS** (0 CRITICAL/BLOCKER/MAJOR, 1 MINOR, 2 NOTE). A
security-reviewer FÜGGETLENÜL, saját pure-Dart próbával ugyanazt a
gyökérokot reprodukálta, mint ez a jelentés F1-e (ott MINOR-1, mert
fail-closed — dob, nem szivárogtat/publikál rossz értéket — de a javító
kör ezt is lezárta). Két nem blokkoló, előretekintő NOTE (codec nem
perzisztálja az új `calibrationVersion`/`calibrationSource` mezőket;
`details` map jövőbeli JSON-sink) — mindkettő R29-re/egy jövőbeli bekötő
körre jelezve, HANDOFF §3-ban rögzítve.

## Merge-döntés

**APPROVED.** Minden BLOCKER/MAJOR zárva (F1 FIXED, függetlenül
újra-ellenőrizve gate-tel és próbateszttel is); a security review PASS;
nulla nyitott BLOCKER/MAJOR marad (F2 dokumentált, nem blokkoló follow-up).
Az ADR 0052 zöld-kapu szabálya szerint a helyi gate zöldje + a CI-run
zöldje (dispatch az orchestrátor következő lépése) → squash-merge külön
jóváhagyás nélkül.
