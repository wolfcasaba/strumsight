# E15-R13 review — A sáv lezárása: teljes migrációs mérés, vizuális regresszió és APK-evidencia

- **Reviewer:** Claude Opus 5 (orchesztrátor, ADR 0055 ellenőrzői szerep) — READ-ONLY
- **Dátum:** 2026-09-03
- **Kör-branch:** `sonnet-impl/e15-r13-ui-closure-and-release-evidence`
- **Review-elt HEAD:** `d7c4c65e`
- **Implementer:** Claude Sonnet 5 (`sonnet-impl`), jelzés `status=done`
- **Diff:** 4 fájl, +4309 / −25 (`test/ui/goldens/e15_r13_full_variant_matrix_test.dart` ÚJ 3854 sor, `docs/ui/chapter-15-completion-report.md` ÚJ, `docs/ui/legacy-backlog.md`, a kör briefje)

## 0. Verdikt

**VÉGSŐ DÖNTÉS: APPROVED** (a javító menet, `45ce01c3` után — a leletenkénti
újra-ellenőrzés a §6-ban; 0 nyitott BLOCKER/MAJOR/MINOR).

**Első mérés (`d7c4c65e`): CHANGES REQUESTED** — 1 MAJOR, 1 MINOR, 2 NOTE. A kör **tartalmi** munkája
erős: a záró mátrix valódi (72 képernyő, mért fákkal), és mind a négy gépi őr
átment a saját valódi-sértés próbámon. A MAJOR nem a mátrixban van, hanem a
zárójelentés egyetlen, **parancs-kimenetként idézett, de a valóságtól eltérő
számában** — pont abban a dokumentumban, amelynek az A5 szerint minden állítása
mért hivatkozás.

## 1. Amit magam mértem (nem bemondásra fogadtam el)

**Izolált klón:** `git clone --branch <kör-branch> /home/ubuntu/ss-sonnet-impl-e15-r13 /tmp/review-e15-r13`
(+ `tools/prepare-flutter-generated.sh`).

### 1.1 Kötelező gate — SAJÁT futás, csonkítatlanul

```
tools/round-gate.sh test/ui/goldens/e15_r13_full_variant_matrix_test.dart test/ui/ui_inventory_test.dart test/tooling/screen_reachability_test.dart test/accessibility/closure_suite_test.dart

═══ Gate-összegzés
    format                                                     zöld
    analyze                                                    zöld
    test test/ui/goldens/e15_r13_full_variant_matrix_test.dart zöld
    test test/ui/ui_inventory_test.dart                        zöld
    test test/tooling/screen_reachability_test.dart            zöld
    test test/accessibility/closure_suite_test.dart            zöld
    architecture                                               zöld
    secrets                                                    zöld
    l10n                                                       zöld

MINDEN GATE ZÖLD.
```

### 1.2 Scope-audit (ADR 0138 §1) — gépi

```
$ python3 tools/scope-audit.py --repo /home/ubuntu/ss-sonnet-impl-e15-r13 \
    --brief docs/rounds/e15-r13-ui-closure-and-release-evidence.md --base origin/main
Legacy scope audit OK (9ba54399ca31..d7c4c65e4f67, 4 changed path(s), 0 generated/ignored)
```

`lib/**` a diffben: **0 sor** (A4 teljesül; a §5.2 „mérj, ne javíts" betartva).
A `docs/ui/migration-status.md` (a párhuzamos `E16-R02` kör fájlja, §0.0.A/R4)
érintetlen — nincs slot-ütközés.

### 1.3 Négy valódi-sértés próba (eldobható, /tmp klónban, törölve)

| Próba | Mutáció | Elvárt | Mért |
|---|---|---|---|
| P1 — A1 teljesség | a `'tuner'` bejegyzés törlése a `_screens`-ből | PIROS | **PIROS**: „every reachable screen is either pumped here or excluded…" |
| P2 — A5 riport-őr, HAMIS állítás helyett **ELHALLGATÁS** (L588) | a `91 / 96 migrated` sor TÖRLÉSE a riportból | PIROS | **PIROS**: „cites the current measured migration + reachability numbers" |
| P3 — A5 riport-őr, törölt LELET | minden `LessonScorePreviewScreen`/`lesson_score_preview` sor törlése | PIROS | **PIROS**: „every currently-excluded SCREEN name is mentioned…" |
| P4 — csak-zsugorodó kizárás (L180) | HAMIS `_ExcludedCell` felvétele a nem túlcsorduló `tuner\|light\|en\|compact_portrait\|1.0` cellára | PIROS | **PIROS**: „STALE exclusion-list entry" |

A P2/P3 a kör legfontosabb állítását igazolja: a riport-őr tényleg az
**elhallgatást** is méri, nem csak a jelen lévő sorok konzisztenciáját.

### 1.4 „Üres fát mér-e a cella?" — a kozmetikai zárás elleni saját mérés

A §9 legfőbb kockázata, hogy a zöld cella valójában spinnert vagy üres
`Scaffold`-ot renderel (L477/L558 hibaosztály). Eldobható próbával mind a 72
képernyőt lemértem a `light|en|compact_portrait|1.0` cellán, `Text`-,
spinner- és widget-számmal:

```
72 képernyő mérve; ebből spinnerrel VAGY 3-nál kevesebb Text-tel:
library|light|en|compact_portrait|1.0   texts=2  spinners=0  widgets=224
progress|light|en|compact_portrait|1.0  texts=40 spinners=1  widgets=744
```

**70/72 képernyő gazdag, valódi fát renderel**, a maradék kettő is épített fa
(224 ill. 744 widget) — a mátrix tehát valóban mér, nem formálisan zöld.
(A két eset NOTE-ként lent.)

### 1.5 Teszt-darabszám — MÉRT

```
$ flutter test test/ui/goldens/e15_r13_full_variant_matrix_test.dart
01:04 +1162: All tests passed!
```

**1162** (= 1152 cella + 5 A1-cella + 5 A5-cella), 64 s alatt.

## 2. Acceptance criteria tételesen

| # | Verdikt | Bizonyíték |
|---|---|---|
| A1 | ✅ | `screen_reachability_test.dart` zöld + a mátrix A1-csoportja (5 cella) + **P1** próba pirosra vált; a mért 71 elérhető ⊆ 72 mátrix-képernyő ∪ 1 indokolt kizárás |
| A2 | ✅ (a 32 dátumozott `_ExcludedCell` LELETTEL) | 1152 cella, mind saját `tester.view.physicalSize`-szal (L558); túlcsordulás csak a 32 mért, dátumozott, csak-zsugorodó kizárt cellán, `skip`/tolerancia sehol; **P4** bizonyítja, hogy a lista nem hízhat csendben |
| A3 | ⚠ **MINOR-1** | a §3.0 nyitott tétel dátuma és gazdája megvan, de a **nevesített kör hiányzik** („SDD, unscheduled") |
| A4 | ✅ | `ui_inventory_test.dart` `hasLength(96)` változatlan, gate zöld, `lib/**` diff = 0 sor |
| A5 | ❌ **MAJOR-1** | a riport két helyen **1157**-et állít, idézett parancs-kimenetként is; a mért érték **1162** |
| A6 | ⏳ | `build-apk.yml` `33795654920` fut a `d7c4c65e` SHA-n; Router CI `33795647344` **success** ugyanazon a SHA-n |

## 3. Leletek

### MAJOR-1 — a zárójelentés hamis parancs-kimenetet idéz (A5)

**Hol:** `docs/ui/chapter-15-completion-report.md:26` és `:85`.

```
:26   structural cells** (A1) — **1157 tests total, all green** …
:85   # +1157: All tests passed!
```

**Mért valóság:** `01:04 +1162: All tests passed!` (§1.5), és a kör SAJÁT
briefje (§10.4) is **1162**-t ír (1152 + 5 + 5) — a riport tehát a saját
handoffjával is ütközik.

**Miért MAJOR:** a `:85` blokk nem elírás, hanem **parancs-kimenetként
idézett** szám, ami az adott parancsból nem jöhet ki. Az A5 kritérium („minden
állítás parancs- vagy fájl-hivatkozású") pontosan ez ellen szól; egy záró
fejezet-jelentésben a nem reprodukálható idézet a legdrágább hibaosztály. Az
A5-őr azért nem fogta meg, mert a teljes darabszámra nincs cellája (a
`_screens.length`, `totalCells` és `_excludedCells.length` mind pinnelve van,
a **végösszeg** nem).

**Javasolt irány:** a két szám javítása 1162-re, ÉS az A5-őr kiegészítése egy
cellával, amely a `1152 + _exclusions-független 5 + 5` végösszeget (vagy a
riportban idézett `+NNNN: All tests passed!` mintát) a mátrix élő állapotából
vezeti le. Kész patchet szándékosan nem adok.

### MINOR-1 — nyitott tételek „nevesített kör" nélkül (A3, §0.0.A/R2)

**Hol:** `docs/ui/legacy-backlog.md` §3.0 („**Owner:** a future round whose
`allowed_paths` covers the five screens' route redirects + file deletion (SDD,
unscheduled)") és `test/ui/goldens/e15_r13_full_variant_matrix_test.dart:3187`
(`followUpRound: 'a future round … (SDD, unscheduled)'`).

A brief §3 és az A3 **nevesített kört** ír elő; a „unscheduled" őszinte, de nem
név. Az őr-cella ma csak `isNotEmpty`-t mér, ezért a hiány gépileg láthatatlan.

**Javasolt irány:** nevezd meg a kört, amelyik a tételt VISZI — a queue-ban a
`E16-R05` (`docs/rounds/e16-r05-full-app-verification-and-release.md`) pre-flightja
kifejezetten újrafuttatja a `check_screen_reachability`-t, tehát ő a mérhető
hordozó; ha a végrehajtó kör tényleg nem létezik még, a szöveg mondja ki
mindkettőt (hordozó kör + „a végrehajtó kör admittálása user/pipeline döntés").
Az őr-cella szigorítható `RegExp(r'E\d{2}-R\d{2}')`-re.

### NOTE-1 — a `library` cella közel üres fát mér

`library|…|compact_portrait|1.0`: 2 `Text`, 224 widget — a képernyő üres
állapotát rendereli, a feltöltött listáét nem. `retire`-verdiktes képernyőnél
ez arányos, de a riport §4 „minden cella mér" állítása mellé érdemes odaírni.

### NOTE-2 — a `StrumReelScreen` már `textScale 1.0`-nál is túlcsordul

191 px a `compact_portrait|1.0` cellán (nem csak 200%-on) — ez alapbeállítású
felhasználót érintő defekt, a 4 lelet közül a legsúlyosabb. A követő kör
prioritása.

## 4. Amit NEM kifogásolok (mérve, rendben)

- A 32 `_ExcludedCell` **nem** a mérce lazítása: `skip` nélkül, minden tétel
  mért px-szel és dátummal, és a P4 próba bizonyítja, hogy egy megjavult cella
  PIROSRA vált (nem marad örökre kizárva).
- Az 5 legacy képernyő `stopped` nélküli kezelése helyes (§0.0.A/R2): mind
  `retire`-verdiktes, utóddal.
- A `docs/ui/migration-status.md`-t az implementer NEM írta — a párhuzamos
  `E16-R02` körrel nincs ütközés.

## 5. Merge-feltétel

MAJOR-1 zárása után: friss gate + `build-apk.yml` és `router-ci.yml`
**success a merge SHA-n** → squash-merge (ADR 0052).

## 6. Javító menet újra-ellenőrzése (`45ce01c3`, 2026-09-03) — leletenként

Új, FRISS izolált klón (`/tmp/review2-e15-r13`), a gate teljes újrafuttatásával
és két új eldobható mutációs próbával.

### MAJOR-1 → **ZÁRVA**

- A riport mindhárom helyen a MÉRT `1163`-at írja (`:27`, `:89`, `:92`), és a
  SAJÁT futásom pontosan ezt adja: `00:55 +1163: All tests passed!`
  (1152 cella + 5 A1 + 6 A5 — az A5 a javító menet új cellájával nőtt 5→6).
- **Új őr-cella:** „cites the grand total test count this file itself produces
  (cells + A1 + A5 structural groups)". **Valódi-sértés próbám:**
  - a riport `1163` → `1164` átírása **CSAK a két idézett helyen**: a cella
    ZÖLD maradt (a harmadik, §4-beli előfordulás miatt) — ezért a próbát
    kiterjesztettem;
  - `sed 's/1163/1164/g'` (mind a 3 előfordulás): a cella **PIROSRA VÁLT**,
    a pontos indoklással („grand total test count (1163 = 1152 matrix cells +
    5 A1 + 6 A5) missing/stale");
  - visszaállítás után ismét ZÖLD.
- Az őr tehát valóban pinneli a végösszeget. **NOTE-3** (nem blokkol): az
  `a1CellCount = 5` / `a5CellCount = 6` kézzel pinnelt literál — a fájlban
  dokumentáltan —, mert a `test()`-hívások futásidejű megszámlálására nincs
  reflexió; ha valaki e két csoportba cellát vesz fel a literál frissítése
  nélkül, a várt végösszeg elcsúszik.

### MINOR-1 → **ZÁRVA**

- `docs/ui/legacy-backlog.md` §3.0 gazdája most **nevesített**: `E16-R05`
  (a mérhető hordozó kör), a végrehajtó kör hiányát pedig kimondja.
- A `_exclusions[0].followUpRound` a vágó, gépi mércét kapta: „no round is
  currently queued … a user/pipeline scheduling decision", és az őr-cella már
  **nem** `isNotEmpty`-t mér, hanem `RegExp(r'E\d{2}-R\d{2}')` **vagy**
  explicit „no round is currently queued" közlést követel — a korábbi
  „(SDD, unscheduled)" alakú, gépileg láthatatlan stub innentől PIROS.

### NOTE-1 / NOTE-2 → átvezetve a riportba és a backlogba.

### Gate — SAJÁT újrafuttatás a javító menet után (friss klón)

```
    format / analyze / test ×4 / architecture / secrets / l10n   mind zöld
MINDEN GATE ZÖLD.
```

`git status --short` a próbák után üres (minden eldobható mutáció
visszaállítva, a próbafájlok törölve).
