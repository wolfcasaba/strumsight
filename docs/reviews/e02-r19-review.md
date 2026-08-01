# Review — E02-R19 (Progress-egyesítés, streak-jogosultság, Learn-migráció)

- **Kör-branch:** `codex/e02-r19-progress-and-learn-migration`
- **Implementer motor:** MiniMax M3
- **Review commit-bázis:** `7cf1ca4` (implementer) a `e3bc283` (pre-flight: ADR
  0085 + brief §0.0) tetején.
- **Ellenőr:** Claude (Opus 4.8), read-only, izolált klón:
  `/tmp/review-e02-r19` (`git clone --branch … /home/ubuntu/ss-mm-e02-r19`).
- **Verdikt:** **CHANGES REQUESTED — HALT (H3).** A gate zöld és a plumbing-oldal
  (A1–A6, A8–A10) valósan teljesül, **de a kör magja — a Learn-migráció
  scoring-útja (ADR 0085 Döntés 7 / brief A7) — tautológiaként készült el**, és a
  hű megvalósítás a §4 engedélyezett listán KÍVÜLI fájlokat igényel → emberi
  scope-döntés kell.

## 1. Gate — újrafuttatva, TÉLJES kimenet (izolált /tmp klón)

`tools/round-gate.sh test/features/practice/ test/features/learn/ test/features/progress/ test/features/streak/ test/core/l10n_parity_test.dart`

```
[1] format                                   → ZÖLD (633 files, 0 changed)
[2] analyze                                   → ZÖLD (flutter analyze lib/ test/ tool/)
[3] test test/features/practice/             → ZÖLD
[4] test test/features/learn/                → ZÖLD
[5] test test/features/progress/             → ZÖLD
[6] test test/features/streak/               → ZÖLD
[7] test test/core/l10n_parity_test.dart     → ZÖLD (211/211 kulcs)
[8] architecture                             → ZÖLD (12 allowlisted deviation, 0 új)
GATE_EXIT=0
```

A gate **saját kézzel, izolált klónban** futott (nem a bemondott kimenet). A
zöld gate azonban NEM bizonyíték a tartalmi hűségre (lásd 3. lelet).

## 2. Scope-audit (`git diff --stat e3bc283..7cf1ca4`)

| Fájl | Státusz | Ítélet |
|---|---|---|
| `…/service/practice_progress_aggregator.dart` (ÚJ) | §4 listán | OK |
| `…/application/practice_progress_providers.dart` (ÚJ) | §4 listán | OK |
| `…/application/practice_session_recording.dart` (ÚJ) | §4 listán | OK |
| `progress/model/practice_stats.dart` | §4 listán | OK (konstruktor bájtra változatlan) |
| `progress/providers/daily_goal_provider.dart` | §4 listán | OK |
| `progress/screens/progress_screen.dart` | §4 listán | OK |
| `learn/screens/learn_screen.dart` | §4 listán | OK (flag-elágazás, OFF ág bájtra azonos — mérve) |
| 4 új teszt (`…aggregator_test`, `…recording_test`, `…parity_test`, `…rollback_test`) | §4 listán | OK |
| brief §10 | §4 listán | OK |
| **`lib/features/practice/public.dart`** | **§4 listán KÍVÜL** | **NOTE — lásd 4. lelet** |

`streak_provider.dart`, `lesson_progress_provider.dart`, `app_*.arb` **nem
módosult** — a jogosultsági kapu a `practice_session_recording.dart` use case-be
került (védhető), új user-facing string nem keletkezett (l10n_parity zöld).
`lesson_scorer.dart`, `learn/model/**`, `learn/widgets/**`,
`practice/domain/model/**`, `lib/app/config/**`, `docs/adr/0084…` és korábbi,
`.github/**`: **0 sor** (mérve: `git diff --stat`). A V1 `PracticeEntry`
formátum bájtra érintetlen (`practice_log_race_test.dart` zöld).

## 3. Súlyossági táblázat

| # | Osztály | Fájl:sor | Lelet |
|---|---|---|---|
| 3.1 | **MAJOR** | `test/features/learn/learn_migration_parity_test.dart:98-124`, `lib/features/learn/screens/learn_screen.dart:349-386`, `lib/features/practice/application/practice_session_recording.dart:177` | **A7 tautológia — a Learn-migráció scoring-útja hiányzik.** |
| 4.1 | NOTE | `lib/features/practice/public.dart:16-27` | public.dart a §4 listán kívül, de architektúra-kényszer (cross-feature export boundary). |

### 3.1 — MAJOR: A7 tautológia / Döntés 7 nem valósult meg (HALT-ok)

**Előírás (ADR 0085 Döntés 7 = brief §5.7):** „A migrált Learn **a V2
metrikákból képzi** a legacy accuracy-nek megfelelő értéket (a direction-dimenzió,
ADR 0076 A7 szerint), és arra alkalmazza a `LessonProgress.stars`/`isPassed`
szabályt." A brief **§7.6** kifejezetten „paritás-harness (A7) — **előbb
pirosan**, majd zöldre" sorrendet ír elő — ez csak akkor értelmes, ha KÉT
külön számítás (legacy vs. V2) létezik, amit paritásra kell hozni.

**Mért valóság (izolált klón):**
- A flag-ON `_recordLearnMomentV2` (`learn_screen.dart:349`) a **legacy
  `LessonScorer` `snap.accuracy`-jét** adja tovább (`directionAccuracy:
  snap.accuracy`, 376. sor). V2 scorert/direction-dimenzió-számítást **nem** hív.
- A `practice_session_recording.dart:177` a kapott `request.directionAccuracy`-t
  **tárolja** — nincs benne semmilyen scoring.
- Az A7 teszt (`…parity_test.dart`) a `_runLegacy(lesson)` kimenetét
  (`snap`) **ugyanúgy adja át** a „V2" ágnak (`snap: legacy`, 99. sor), majd
  `expect(v2Accuracy, accuracy)` — a teszt saját kommentje kimondja:
  „same single source of truth (legacy scorer); **trivially identical**"
  (106–107. sor). A teszt SOHA nem lehet piros (a §7.6 „előbb pirosan" sérül).

**Következmény:** a kör magja („a Learn képernyő a Practice Engine **V2**-t
használja", §1.3) a **scoring** dimenzióban NEM teljesül. A migráció
plumbing-only: a recording / streak-jogosultság / daily-goal-aktívidő /
mikrofon-rés valósan V2-igazodású és tesztelt, de a **pontszám továbbra is a
legacy `LessonScorer`-ből** jön. Az implementer §10 follow-upja ezt
elismeri: „a scoring-motor maradt a legacy `LessonScorer` … V2-re cserélése
külön kérés".

**Miért HALT (H3), és miért nem javító kör vagy önálló feloldás:**
1. A hű megvalósítás (a V2 direction-dimenzió scorer bekötése a Learnbe) a §4
   engedélyezett listán **kívüli** fájlokat igényel (a V2 scorer a
   `practice/domain/service/`-ben, plusz esemény-adapter a Learnbe) → **tilos
   zóna feloldása = H3**.
2. Egy valódi V2 scoring-út **eltérhet** a legacy paritástól egyes leckéken; a
   brief A7 erre kimondja: „Ha valódi, indokolt eltérést találsz → **stopped** +
   jelentés; a feloldás dokumentált brief-revízió, **nem** a mérce lazítása." Ez
   explicit **emberi döntés**, nem orchestrátor-hatáskör (ADR 0087 §2).
3. A brief önmagában ellentmondó: Döntés 7 V2-metrikából számolt accuracy-t kér,
   a §4 viszont a `learn_screen.dart`-ot „CSAK a flag-elágazás"-ra korlátozza és
   a V2 scoring-fájlokat nem engedi. Az implementernek e ponton **`stopped`**-ot
   kellett volna jeleznie; helyette a legacy scorer újrahasználásával
   megkerülte az ütközést.

**Emberi döntés kell — két út:**
- **(a) Plumbing-only scope elfogadása R19-re:** a scoring-motor V2-cseréje
  külön (Kör 20 / utódkör). Ekkor az orchestrátor a Döntés 7 / A7 szövegét a
  megvalósult (plumbing) valósághoz igazítja (a saját, nem-merge-elt ADR 0085 /
  brief), a többi kritérium zöld, a flag OFF → a merge nulla produkciós
  kockázatú. **Ez a valószínű és biztonságos út.**
- **(b) R19 újra-scope-olása:** a §4 lista bővül a V2-scoring-fájlokkal, és a
  kör újrafut egy valódi (piros→zöld) A7-tel; a paritás-eltéréseket a brief A7
  szerint kezeljük.

## 4. NOTE — public.dart a listán kívül (nem blokkol)

`practice/public.dart` +12 sor **pure export** (nulla viselkedés), az új
in-scope szimbólumok (`practiceSessionRecordingProvider`, aggregator, eligibility,
metrics) publikálására. A `learn_screen.dart` (engedélyezett fájl) ezen a
`public.dart` boundary-n át importál (`crossFeatureImportsMustUsePublicApi`
architektúra-szabály — a `[8] architecture` gate zöld). Így az edit
**architektúra-kényszer**, a kör saját új szimbólumainak export-felszíne, nem
scope-creep. A §4 lista ezt kimaradta; ha a kör folytatódik, a Döntés 7-döntéssel
együtt a §4-be fel kell venni (a felszín az allowed új fájlok velejárója).

## 5. Amit megméretettem (nem olvastam)

- **Gate:** újrafuttatva izolált klónban, `GATE_EXIT=0` (1. szakasz).
- **Flag-OFF bájt-azonosság (A8/Döntés 8):** a `_finish()`/`_pause()` else-ága
  szó szerint az eredeti kód; a flag-elágazás csak additív `if
  (_migratedLearnEnabled)` blokkot tesz elé (mérve: `learn_screen.dart:232-247`,
  `299-333`). A §2 legacy Learn-tesztek átírás nélkül zöldek (gate [4]).
- **A9 mikrofon-rés:** V2 ágon `_pause()`/`_finish()` `_frameSub?.close()` (mérve).
- **A1/A3 valódiság:** az aggregátor-teszt genuine mérés — 2× azonos `id` → 1
  rekord; 5 V1 + 1 deduped V2 = 6 (`…aggregator_test.dart:278-340`). Nem
  tautológia.
- **A4/A5/A6 valódiság:** a recording-teszt a `practiceSessionRecordingProvider`
  **valódi hívóján** méri a jogosultsági cellákat és az aktív-idő-számítást.

## 6. Zárás

A gate zöld, a plumbing-oldal erős és tesztelt, a flag OFF → merge esetén nulla
produkciós kockázat. **A merge mégis TILOS** a 3.1 MAJOR miatt: a kör
deklarált magja (Learn-**migráció** a V2 scoring-motorra) nem készült el, és a
feloldás a §4 tilos zónáját és/vagy emberi paritás-döntést igényel (H3, ADR 0087
§2). A lánc HALT-tal megáll; a `.pipeline/round-status` `outcome=halted halt=H3`.
