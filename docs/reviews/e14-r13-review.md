# E14-R13 — kör-review

- **Kör:** `E14-R13` — Live UI truthfulness hotfix
- **Brief:** [`docs/rounds/e14-r13-live-ui-truthfulness-hotfix.md`](../rounds/e14-r13-live-ui-truthfulness-hotfix.md)
- **ADR:** [`0520`](../adr/0520-live-uncertainty-reason-from-the-merged-recognition-vocabulary.md)
- **PR:** [#590](https://github.com/wolfcasaba/strumsight/pull/590)
- **Branch / head:** `sonnet-impl/e14-r13-live-ui-truthfulness-hotfix` @ `6146c33d`
- **Base (a kör induló HEAD-je):** `c8dbc0d6` (pre-flight commit, rebase után)
- **Implementer motor:** `sonnet-impl` (Claude Sonnet 5, `--effort high`)
- **Reviewer:** Claude (Opus 5), read-only — a review során production kód nem
  módosult; a próbatesztek eldobható klónokban futottak és törölve lettek.
- **Dátum:** 2026-09-05

## 1. Verdikt

**VÉGSŐ DÖNTÉS: APPROVED** (javító kör után, `93ed3ea6`).

Az első fordulóban **CHANGES REQUESTED** volt 1 MAJOR-ral; a javító kör azt
lezárta, és a zárást a reviewer FÜGGETLENÜL újramérte (§9). A három NOTE
tudatosan nyitva marad — mind a kör tilos zónáján kívülre esik, follow-up.

### Az első forduló verdiktje (megőrizve)

**CHANGES REQUESTED** — 1 MAJOR nyitva.

A kör tartalmi magja **hűen teljesíti** a briefet és az ADR 0520 D1–D7-et: a
képernyő „miért nem sikerült" állítása a merge-elt, zárt hatelemű
`RecognitionRejectReason`-ből jön, kimerítő `switch`-kifejezéssel, a
heurisztikus ág érintetlen marad a „nincs döntés" ágon, és a kulcsok a `base/`
forrás-szegmensbe kerültek. A MAJOR **nem a bannerre**, hanem a kör SAJÁT
mércéjének egyetlen cellájára vonatkozik: a 250%-os textscale-cella
bizonyítottan **semmit nem mér**, miközben a brief 5. acceptance-pontja
kifejezetten mérést ír elő rá, és a cella doc-commentje ennek az ellenkezőjét
állítja.

## 2. Mérce — amit MAGAM futtattam

### 2.1 Célzott gate, izolált klónban

```
$ git clone --branch sonnet-impl/e14-r13-live-ui-truthfulness-hotfix \
    /home/ubuntu/ss-sonnet-impl-e14-r13 /tmp/review-e14-r13-clean
$ /tmp/review-e14-r13-clean/tools/prepare-flutter-generated.sh
$ cd /tmp/review-e14-r13-clean && tools/round-gate.sh <a brief §7 hét útvonala>
```

Eredmény: **MINDEN GATE ZÖLD** (`GATE_EXIT=0`) — `[1] format` · `[2] analyze` ·
`[3]`–`[9]` a hét célzott teszt-útvonal · `[10] architecture` · `[11] secrets` ·
`[12] l10n`.

> **Módszertani megjegyzés (saját hiba, javítva).** Az ELSŐ reviewer-gate-futást
> (`/tmp/review-e14-r13`) a saját próbatesztjeimmel PÁRHUZAMOSAN indítottam
> ugyanabban a klónban, és a violation-próba közben a bannert átmenetileg
> elrontottam. Az a futás zölden zárult, de a mutáció miatt **nem bizonyíték** —
> ezért a fenti, érintetlen `/tmp/review-e14-r13-clean` klónban ÚJRA lefuttattam,
> semmilyen párhuzamos írás nélkül. A jelentés a második, tiszta futásra
> hivatkozik.

### 2.2 Scope-audit (ADR 0138)

```
$ python3 tools/scope-audit.py --repo /home/ubuntu/ss-sonnet-impl-e14-r13 \
    --brief docs/rounds/e14-r13-live-ui-truthfulness-hotfix.md --base c8dbc0d6
Legacy scope audit OK (c8dbc0d64c02..6146c33dc6ae, 10 changed path(s), 0 generated/ignored)
```

A tíz érintett útvonal mind az `allowed_paths`-on belül. A tilos zóna
(`domain/recognition/**`, `engine/**`, `providers/**`, a másik négy live-widget,
`core/design_system/**`, `docs/adr/**`, `tools/`, `.github/`) **érintetlen**.

### 2.3 `gate_shape=VIOLATION` — MÉRVE hamis pozitív, nem sértés

A jelzésfájl `gate_shape=VIOLATION`-t hordoz. A log tényleges `round-gate.sh`-t
említő Bash-hívásait kigyűjtve **kettő** van:

```
grep -n "l10n\|gen-l10n\|gen_l10n" tools/round-gate.sh | head -30     ← csak OLVASSA a scriptet
tools/round-gate.sh test/features/live/uncertainty_reason_banner_test.dart …  ← a §7 pontos, csővezeték nélküli alakja
```

Az őrmintát az ELSŐ sor elégíti ki (`round-gate.sh` … `| head`), a tényleges
gate-hívás szabályos. Ez pontosan az [L640](../LESSONS.md#l640)-ben mért
false-positive osztály (a minta a script EMLÍTÉSÉRE is illeszkedik). A `tools/`
javítása nem ennek a körnek a hatásköre (ADR 0087 §4) — a lelet marad az
önjavító kör asztalán.

### 2.4 `dirty_files=1` a jelzésben — kivizsgálva, tiszta

A `done` jelzés `dirty_files=1`-et hordozott (L21 szerint kivizsgálandó). A
munkapéldány `git status --short`-ja a kilépés után **üres**; a jelzés a saját,
gitignore-olt `.codex-round-status` fájlját mérte a záró commit előtti
pillanatban. Nincs elveszett vagy be nem commitolt munka.

## 3. Leletek

| # | Osztály | Rövid |
|---|---|---|
| MAJOR-1 | MAJOR | A 250%-os textscale-cella bizonyítottan SEMMIT nem mér, a doc-commentje pedig cáfolt állítást tesz |
| NOTE-1 | NOTE | A banner „No chord detected yet" szövege és a timeline „Play a chord…" promptja EGYSZERRE látszik (mérve) — a D4 csak a `liveWeakSignal`-t tiltotta |
| NOTE-2 | NOTE | Az új widget nyers `AppColors` + hardcode-olt `'Poppins'`/11px-et használ, nem design-system tokent |
| NOTE-3 | NOTE | Az ok-szöveg változása nincs bekötve az ugyanabban a slotban élő `SsLiveRegionAnnouncer`-be |

### MAJOR-1 — a 250%-os cella nem mérce: minden esetben zöld, akkor is, ha a képernyő ELSZÁLL

**Hol:** `test/features/live/live_screen_truthfulness_test.dart:200-212`

**Mit ír elő a brief.** §6 5. acceptance-pont: „*a küszöb **fölött** (250%) a kör
NEM vállal garanciát — ott a cella csak azt méri, hogy a képernyő **nem dob
kivételt***."

**Mit csinál a cella.**

```dart
testWidgets('250% (above the ceiling) — no guarantee against overflow, only '
    'that the screen does not crash (ADR 0520 D8)', (tester) async {
  await pumpAtScale(tester, 2.5);
  // Above 200% the round makes no overflow promise — consume whatever
  // rendering error may have been reported so it doesn't auto-fail the
  // test; a genuine crash would still surface as a thrown exception
  // from the pump above, which this cell does not catch.
  tester.takeException();
});
```

A `tester.takeException()` visszatérési értéke **eldobva**, állítás nincs. A
doc-comment állítása („*a genuine crash would still surface as a thrown
exception from the pump above*") **téves**: a `flutter_test` a build/layout
közben dobott kivételt NEM engedi ki a `pump`-ból, hanem eltárolja, és épp a
`takeException()` az, ami kiveszi és **elnyeli**.

**Reviewer-próba (eldobható, futtatva, törölve).** A cellával azonos mintát egy
build-ban garantáltan dobó widgetre mérve:

```dart
class _AlwaysThrows extends StatelessWidget {
  @override
  Widget build(BuildContext context) => throw StateError('a genuine crash inside build');
}

// PROBE A — pontosan azt teszi, amit a 250%-os cella:
await tester.pumpWidget(const MaterialApp(home: Scaffold(body: _AlwaysThrows())));
await tester.pumpAndSettle();
tester.takeException();                       // az érték eldobva

// PROBE B — ugyanaz a fa, de állítással:
final taken = tester.takeException();
expect(taken, isA<StateError>());
```

```
00:00 +0: PROBE A: pumping a widget that throws, then discarding takeException(), PASSES …
00:00 +1: PROBE B: the same tree, asserting on the taken exception, SEES the crash
00:00 +2: All tests passed!
```

**PROBE A ZÖLD** — vagyis a 250%-os cella akkor is átmegy, ha a `LiveScreen` a
`pumpAtScale` alatt `StateError`-ral elszáll. A cella tehát nem a brief által
előírt „nem dob kivételt" mércét adja, hanem **nulla** mércét, miközben a
neve, a leírása és a §10 handoff is mérésként hivatkozik rá.

**Miért MAJOR és nem NOTE.** Nem stílus: a brief egy acceptance-pontja
konkrétan ehhez a cellához köt egy mérést, és a cella azt bizonyítottan nem
végzi el. Ráadásul a §7 doc-comment-fegyelme („*doc-commentben csak tesztben
bizonyított állítás*") pont az ellenkezőjét kapta: egy cáfolt állítást. Egy
jövőbeli kör, amely a Stage-slotokhoz nyúl, ezt a cellát zöldnek látná akkor is,
ha 250%-on a képernyő összeomlik.

**Javasolt irány (nem kész patch).** Vedd ki a kivételt változóba, és ha nem
`null`, mondd ki, hogy CSAK a garanciából kizárt elrendezési túlcsordulás
elfogadható — bármi más (pl. `StateError`) essen el:

```
final taken = tester.takeException();
if (taken != null) {
  // 200% fölött a túlcsordulás megengedett; a crash nem.
  expect(taken.toString(), contains('overflowed'));
}
```

A 150%/200%-os cellák a `takeException()` értékére ÁLLÍTANAK (`isNull`), ezért
ott ez a hiba nem áll fenn — lásd a 4.5 pont violation-próbáját.

### NOTE-1 — két mondat ugyanarról a tényről (mérve), a körön KÍVÜL

`chordRejectReason == noChord` és `current == null` mellett a banner
„No chord detected yet" szövege ÉS a `ChordTimeline` „Play a chord…"
(`liveWaitingForChord`) promptja **egyszerre** van a fában — reviewer-próbával
mérve:

```
PROBE-RESULT banner="1" waitingForChord="1"
```

Ez **nem sértése** a körnek: az ADR 0520 D4 kizárólag a `liveWeakSignal`
együttes megjelenését tiltja, a `chord_timeline.dart` pedig a brief tilos
zónájában van, tehát a kör helyesen NEM nyúlt hozzá. A „ne mondjuk ugyanazt
kétszer" elv teljes érvényesítése külön kör, amely a timeline promptját is
átkötheti a döntési forrásra — a következő körök asztalára.

### NOTE-2 — az új widget nem design-system tokenekkel épül

`uncertainty_reason_banner.dart:44-58`: `AppColors.danger`, `fontFamily:
'Poppins'`, `fontSize: 11`, `EdgeInsets` literálok. A `feedback` slot többi
gyereke (`SsSignalQualityIndicator`, `SsLiveRegionAnnouncer`) `ss_`-prefixű
design-system komponens. A brief §3 kifejezetten kizárja a Chapter 13
design-token cserét, tehát ez **helyes scope-döntés** volt — de a Chapter 15
migrációs sáv így egy új, nem migrált widgetet örököl. Érdemes a Live-migráció
körének listájára venni.

Kisebb megjegyzés ugyanitt: `Icon(Icons.info_outline, … color: AppColors.danger)`
— információs ikon hibaszínnel. A `modelUnavailable` és a `noChord` nem
hibaállapot a felhasználó szempontjából (ADR 0271 `UNKNOWN > CONFIDENTLY WRONG`).

### NOTE-3 — az ok-szöveg nincs bemondva képernyőolvasónak

Ugyanabban a `feedback` slotban él az `SsLiveRegionAnnouncer`, de a banner
szövegváltozása nincs bekötve — a látássérült felhasználó a „miért nem
sikerült" információt nem kapja meg. A brief ezt nem írta elő, és az
accessibility-cellák a kör `gate_tests`-ében nincsenek; follow-up kör tárgya.

## 4. Acceptance criteria tételesen

| # | Kritérium | Bizonyíték | Verdikt |
|---|---|---|---|
| 1 | Hatelemű, kimerítő mátrix, `values` fölött ITERÁLVA, mindkét locale | `uncertainty_reason_banner_test.dart:18-32` — `for (final locale in _locales) for (final reason in RecognitionRejectReason.values)`; gate `[3]` 15/15 zöld | ✅ |
| 2 | Distinctness mindkét locale-ban | `uncertainty_reason_banner_test.dart:35-47` — `Set` méret == `values.length`; az implementer §7.1/1. falszifikációja MÉRTE pirosra (`Expected: <6> Actual: <1>`) | ✅ |
| 3 | Termelő-cella: a MA előálló három ok a VALÓDI `LiveScreen`-re jut | `live_screen_truthfulness_test.dart:71-108` — a három eset **`LivePipeline.debugDeriveChordDecision` HÍVÁSÁBÓL** származik (nem bemásolt enum-literálból), `StrumSightApp` + `FakeStrumEngine` fán át; gate `[4]` zöld | ✅ |
| 4 | Kölcsönös kizárás + a két merge-elt cella zölden, törlés nélkül | `live_screen_truthfulness_test.dart:111-137` (`inputLevel: 0.02` ÉS `noChord` → `liveWeakSignal` `findsNothing`); `live_stage_test.dart` diffje **+11/-1**: mindkét cella megvan, az állítások BŐVÜLTEK (`findsNothing` a bannerre), egy sem törölve/`skip`-elve; az implementer §7.1/2. falszifikációja MÉRTE pirosra | ✅ |
| 5 | Textscale hármas (150 / 200 / 250), látható bannerrel | 150% és 200%: valódi mérce — a 4.5 violation-próba MINDKETTŐT pirosra vitte. **250%: nem mérce** → **MAJOR-1** | ⚠️ **részleges** |
| 6 | A hero változatlan | `live_screen_test.dart` diffje **üres** (0 sor); gate `[6]` zöld a változatlan állítás-szövegekkel | ✅ |
| 7 | l10n: hat kulcs mindkét locale-on a `base/` FORRÁSBAN, az aggregátum újragenerálva | `lib/l10n/base/app_{en,hu}.arb` +24/+24 sor, `@kulcs` metaadattal; `lib/l10n/app_{en,hu}.arb` +24/+24 generátor-kimenetként; gate `[8] arb_parity` · `[9] gen_l10n_segments` · `[12] l10n` zöld | ✅ |
| 8 | Golden: a két merge-elt cella zöld, a PNG-k változatlanok | `git diff --stat` a két PNG-re: **üres**; gate `[7]` mindkét keret (`compact`, `compact_scale2`) zöld | ✅ |

## 5. Próbatesztek (eldobhatók — futtatva, majd törölve)

1. **`zz_review_probe_test.dart`** — `takeException()` szemantika (MAJOR-1
   bizonyítéka). PROBE A zöld = a 250%-os minta semmit nem mér; PROBE B zöld =
   állítással viszont látja a crasht. **Törölve.**
2. **Valódi-sértés próba a textscale-cellákon** — a bannerben az
   `Expanded(Text(...))` lecserélve `SizedBox(width: 500, child: Text(…,
   maxLines: 1, softWrap: false))`-ra (a §6.1 mátrix „fix magasságú / nem
   tördelő banner" sora):

   ```
   00:03 +0 -6: textscale threshold triple (ADR 0520 D8) 200% (exactly the inclusive ceiling) — no overflow, banner visible [E]
   00:03 +1 -6: Some tests failed.
   ```

   A 150%-os és a 200%-os cella **PIROSRA** váltott (a producer- és
   exclusion-cellák is, mert a banner szövege eltört) — tehát ezek VALÓDI őrök.
   A 250%-os cella ekkor is **zöld** maradt, ami a küszöb fölötti
   garancia-hiány miatt önmagában helyes; a MAJOR-1 nem ebből, hanem a
   PROBE A-ból következik. A banner **visszaállítva**, a fa `git status`-a
   tiszta, a teszt-fájl újra 7/7 zöld.
3. **`zz_review_probe2_test.dart`** — a banner és a `liveWaitingForChord`
   együttállása (NOTE-1 bizonyítéka): `PROBE-RESULT banner="1"
   waitingForChord="1"`. **Törölve.**

Mindhárom próba eldobható `/tmp` klónban futott; a kör-branch egyetlen
próbatesztet sem tartalmaz.

## 6. Architektúra és termékhatárok (AGENTS.md §5–§6)

- **Feature-határ:** az új widget a `features/live/` fán belül marad, és a
  saját feature domainjét importálja
  (`../domain/recognition/recognition_decision.dart`) — nem lép át másik
  feature-be, és nem hoz be `core → feature` irányú függőséget. Gate
  `[10] architecture` zöld.
- **A domain nem UI-függő:** a leképezés a widget statikus metódusában él, az
  enum érintetlen; a `domain/recognition/**` diffje **nulla sor**.
- **A UI nem dönt (ADR 0520 D6):** a banner nem következtet okot, nem ír
  `LiveFrame`-et, nem hív pipeline-t; a `reason` konstruktor-paraméter.
- **Erőforrás:** a widget `StatelessWidget`, nincs controller, stream,
  ticker vagy subscription — nincs mit felszabadítani. A `feedback` slot
  gyereke feltételes (`if (frame.chordRejectReason != null)`), tehát a
  fából ki- és visszakerülhet állapotvesztés nélkül.
- **Audio / hálózat / engedély / secret:** a diff egyiket sem érinti; gate
  `[11] secrets` zöld. A kör `risk = "normal"`, külön security-review nem
  kötelező.

## 7. Zöld kapu (ADR 0052) — a merge feltételei

| Elem | Állapot |
|---|---|
| Célzott gate (izolált, tiszta klón) | ZÖLD — `GATE_EXIT=0`, 12/12 lépés |
| Scope-audit | OK — 10 útvonal, 0 sértés |
| `full-gate.yml` a merge SHA-n (`6146c33d`) | lásd §8 |
| `router-ci.yml` a merge SHA-n (`6146c33d`) | lásd §8 |
| Review | **APPROVED** — MAJOR-1 lezárva, 0 nyitott BLOCKER/MAJOR/MINOR |

## 8. CI

- **Terv:** `tools/round-ci-plan.py` → `dispatch: ["full-gate.yml"]`
  (`native_gate=false`, tisztán Dart/dokumentum-diff), `router_ci_expected:
  true` (`docs/rounds/**` érintve).
- **`full-gate.yml`:** run `33967130454`, head SHA `6146c33d` — a végeredményt
  a §9 rögzíti.
- **`router-ci.yml`:** run `33967128196`, head SHA `6146c33d`.

## 9. Javító kör után — zárás (`93ed3ea6`)

### 9.1 MAJOR-1 — LEZÁRVA

A javító kör **kizárólag** a kifogásolt cellát írta át (`git diff --stat
2fbcb214..93ed3ea6`: `live_screen_truthfulness_test.dart` **+7/-5**, a brief §10
handoffja **+169**; production kód **nulla sor**):

```diff
-        // Above 200% the round makes no overflow promise — consume whatever
-        // rendering error may have been reported so it doesn't auto-fail the
-        // test; a genuine crash would still surface as a thrown exception
-        // from the pump above, which this cell does not catch.
-        tester.takeException();
+        // Above 200% the round makes no overflow promise, but it DOES still
+        // guarantee no crash: only a layout-overflow exception is acceptable
+        // here — anything else (e.g. a StateError) must fail this cell.
+        final taken = tester.takeException();
+        if (taken != null) {
+          expect(taken.toString(), contains('overflowed'));
+        }
```

A cáfolt doc-comment-állítás eltűnt, helyette a tényleges viselkedés leírása
áll — a §7 doc-comment-fegyelme teljesül.

### 9.2 A zárás FÜGGETLEN újramérése (reviewer, nem az implementer bemondása)

Az implementer §10.7-ben leír egy saját falszifikációt. A protokoll szerint ezt
**nem fogadom el bemondásra**: friss klónban (`/tmp/review-e14-r13-fix`) magam
kényszerítettem egy nem-túlcsordulás jellegű kivételt a 250%-os fába —
szándékosan MÁS mechanizmussal, mint az implementer (`FlutterError.reportError`
egy `StateError`-ral, nem `build`-ban dobó `Builder`):

```
00:03 +6: textscale threshold triple (ADR 0520 D8) 250% (above the ceiling) …
Expected: contains 'overflowed'
  Actual: 'Bad state: reviewer probe: a real crash, not layout'
00:04 +6 -1: Some tests failed.
```

A cella **PIROSRA VÁLT** egy valódi crashre — a hibát, amit a MAJOR-1 leírt,
mostantól elkapja. Ugyanez a cella a próba visszavonása után zöld. Ez az a
teszt, „ami a hibát pirosra fogta volna" — **MAJOR-1 zárva**.

### 9.3 Ami NEM változott a javító körben

`uncertainty_reason_banner.dart`, `live_screen.dart`, mind a négy ARB-fájl,
`uncertainty_reason_banner_test.dart`, `live_stage_test.dart`,
`live_screen_test.dart`, `e13_r18_screens_golden_test.dart` és a két golden PNG:
**nulla sor**. A 150%/200%-os cellák érintetlenek. A javító kör tehát nem
hizlalta a diffet és nem nyitott új felületet.

### 9.4 Maradék NOTE-ok

NOTE-1/2/3 tudatosan **nyitva marad** — mindhárom a kör `allowed_paths`-án
KÍVÜLI fájlt igényelne (`chord_timeline.dart`, design-system, accessibility-
cellák), tehát a körben javítani őket H3 volna. A HANDOFF §6 viszi tovább őket.

### 9.45 CI-addendum — egy MÉRT flake, nem a kör hibája

A landolás előtti exact-SHA futás (`33969635992`, head `9dc86618`) **pirosra**
váltott: `10141 tests passed, 1 failed, 21 skipped`. Az egyetlen bukó cella

```
test/features/song_trainer/application/import/song_import_controller_test.dart:
  SongImportController cancellation during import closes the workspace without a record (failed)
  Expected: empty
    Actual: [_Directory:Directory: '/tmp/song-import-controller-STXLNL/import-1']
```

**Nem ennek a körnek a diffje.** A kör teljes fájlhalmaza az aktuális `main`-hez
képest 12 útvonal (3 doc + `live_screen.dart` + a banner + 4 ARB + 3
live-teszt) — `song_trainer` nincs köztük, és a scope-audit is 0 sértést mért.

**Mért bizonyíték, hogy flake:**

1. **UGYANEZ a kör-kód zölden ment** a `63ce10ac` SHA-n (full-gate
   `33967927330` `success`) — a két SHA között kizárólag upstream commitok
   vannak.
2. Az upstream delta a zöld futás óta: `a09248ce` **tisztán `docs/`**
   (`git show --name-only | grep -v '^docs/'` → üres) és `0eb14f01`
   (`docs/execution/pipeline-queue.tsv` + `tools/tests/test_pipeline_integration.py`).
   Egyik sem ér `song_trainer`-t.
3. A bukó cella **async-verseny**: `cancel()` után azonnal állít a workspace
   ürességére (`song_import_controller_test.dart:82-90`), miközben a takarítás
   még futhat — a maradék `import-1` könyvtár épp ezt mutatja.
4. **Újramérve UGYANAZON a SHA-n** (`33970821329`, head `9dc86618`):
   **`success`**. Azonos bemenet, eltérő kimenet ⇒ nem determinisztikus cella.

A piros tehát **nem** a kör kódjára vonatkozó bizonyíték, és nem a mérce
gyengítése: a merge-kapu ugyanazon a SHA-n, zölden teljesült. A flake maga
**follow-up** — a `song_trainer` cella determinisztikussá tétele a kör tilos
zónáján kívül esik; a HANDOFF §6 viszi tovább.

### 9.46 CI-addendum 2 — a MÁSODIK piros egy ÖRÖKÖLT alap-drift, szintén nem a kör

A `0a964310` SHA-n mindkét kapu pirosra váltott, és MINDKETTŐ **ugyanaz az
egyetlen gyökérok**: a completion-matrix drift.

```
router-ci 33972014841 → tools/tests/test_completion_matrix_sync.py::test_the_real_tree_is_in_sync
full-gate 33972014063 → test/tooling/program_completion_test.dart (3 cella)

  Ch14 (E14): reports done=16,    queue measures done=17
  Ch14 (E14): reports pending=3,  queue measures pending=2
```

A két érintett fájl — `docs/sdd/program-completion-report.md` és
`docs/execution/pipeline-queue.tsv` — a kör diffjében **nem szerepel** (a
queue-t az ADR 0087 §4 szerint kifejezetten a driver vezeti, nem a kör).

**Mért gyökérok — a drift az ALAP commiton él, nem a körön:**

```
$ git merge-base origin/main HEAD          →  ff9027b5   (a rebase-alap, egy main-commit)
$ cd <plain main klón> && git checkout ff9027b5
$ python3 tools/sync-completion-matrix.py --check
  2 drifted cell(s) …                                    EXIT=1     ← az ALAP már drifteles
$ git reset --hard origin/main             →  9632a96d
$ python3 tools/sync-completion-matrix.py --check
  completion matrix is in sync with the queue            EXIT=0     ← a KÖVETKEZŐ main-commit javította
```

A kör tehát egy olyan pillanatnyi `main`-állapotra rebase-elt, amelyben egy
másik sáv már `done`-ra írta a queue-sorát, de a completion-matrix
szinkronizálása még nem landolt. A megoldás **kizárólag** újra-rebase az
azóta javított `main`-re — a kör egyetlen sorát sem kellett módosítani:

```
$ git rebase origin/main                   →  9632a96d alapon
$ python3 tools/sync-completion-matrix.py --check
  completion matrix is in sync with the queue            EXIT=0
```

**H5-megfontolás.** A körön két piros CI-futás van, de EGYIK SEM a kör kódjára
vonatkozó bizonyíték, és egyik sem vak újrapróbálkozás: mindkettőnek kimért,
a körön KÍVÜLI gyökéroka van (1. egy nem-determinisztikus `song_trainer` cella,
ugyanazon a SHA-n újramérve zöld; 2. egy örökölt alap-drift, a rebase-alap
commiton reprodukálva és a friss `main`-en eltűnve). A zöld kapu változatlanul
áll: a merge kizárólag olyan SHA-n történhet, amelyen a `full-gate` ÉS a
`router-ci` `success`.

### 9.5 Végső verdikt

**APPROVED.** 0 nyitott BLOCKER / MAJOR / MINOR. A merge a zöld kapu (§7)
teljesülésekor mehet.
