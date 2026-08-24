# E13-R15 review — Lokalizációs resilience és content style

- **Kör:** `E13-R15` · **Branch:** `sonnet-impl/e13-r15-localization-resilience`
- **Reviewelt HEAD:** `dfe96d29` (base: `7908dda2`, a pre-flight commit)
- **Implementer:** `sonnet-impl` (Claude Sonnet 5, `--effort high`)
- **Reviewer:** Claude (Opus 5) — read-only, izolált `/tmp/review-e13-r15` klón
- **Verdikt (1. forduló):** **CHANGES REQUESTED** — 3 MAJOR, 0 BLOCKER
- **Verdikt (2. forduló, javító kör után):** lásd §7

---

## 1. Amit magam futtattam (nem bemondás)

| Ellenőrzés | Eredmény |
|---|---|
| `tools/round-gate.sh` a 3 gate-teszttel, izolált `/tmp` klónban | **GATE_EXIT=0** — 54 + 16 + 1 = 71 cella zöld, architecture OK (12 allowlisted), secret scan OK (3649 fájl), **L10n aggregate freshness OK (en, hu)**, L10n parity OK (1838 üzenet) |
| `python3 tools/scope-audit.py --base 7908dda2` | **OK** — 8 változott útvonal, 0 generated/ignored, mind az `allowed_paths`-on |
| `.codex-round-status` `dirty_files=1` kivizsgálva | **nem valódi** — a fa `dfe96d29`-en tiszta (`git status --short` üres), mind a 8 fájl commitolva; tranziens artefaktum a jelzés pillanatában |
| `git diff --name-only 7908dda2..HEAD` | 8 fájl, **egyetlen `lib/l10n/**` sem** — az M1/M3 tilalom betartva, és ezt a gate `L10n aggregate freshness` lépése függetlenül is igazolja |

A zöld gate **nem** bizonyíték (AGENTS.md, `docs/LESSONS.md` L460), ezért a
mérce-mátrix (§6.1) minden sorát valódi-sértés próbával mértem. Három próba
megbukott — az alábbi három MAJOR.

## 2. Leletek

### F1 — MAJOR: az A2 guard VAK a §5.1 által NÉVEN NEVEZETT összefűzés-alakra

**Hol:** `test/l10n/hardcoded_string_guard_test.dart:44-60` (`_classify`)

A brief §5.1 és az ADR 0424 §2.3 szó szerint ezt az alakot tiltja:
`'$count ' + t.songs`. A guard ezt **nem látja**.

**Mérve** (izolált klón, a frozen bejegyzés sorszáma szándékosan nem mozdult —
a próba a fájl VÉGÉRE került):

```dart
final class _ReviewProbeP1 extends StatelessWidget {
  @override
  Widget build(BuildContext context) =>
      Text('$count ' + l10n.dsFieldErrorSemanticPrefix);
}
```

```
00:00 +1: All tests passed!
```

**Gyökérok.** A `_classify` csak a *string-literál belsejét* vizsgálja. Itt a
literál `'$count '`: nincs benne `l10n.` hivatkozás → az A3-ágra fut → az
interpoláció leszedése után a maradék `' '`, nincs szó-szerű tartalom →
`null`. A `+ l10n.dsFieldErrorSemanticPrefix` operandus a literálon KÍVÜL van,
és a szkenner soha nem nézi meg.

**Javasolt irány:** a klasszifikáció ne álljon meg a literál záró aposztrófjánál
— a literált követő kifejezés-töredéket is vizsgálni kell `+` operátorra és
`l10n.`/`AppLocalizations` hivatkozásra. (Nem kész patch — a megoldás
megválasztása az implementeré.)

### F2 — MAJOR: a guard sor-alapú, és a gate SAJÁT `format` lépése teszi láthatatlanná a sértést

**Hol:** `test/l10n/hardcoded_string_guard_test.dart:62-84` (`_scan`), a
`_textPropertyPattern` egyetlen fizikai sorra illeszkedik.

Ez a súlyosabb lelet, mert **nem** széli eset: a `dart format` — a
`tools/round-gate.sh` **első** lépése — a valós komponens-kódot pontosan abba
az alakba írja át, amit a guard nem lát.

**Mérve, három lépésben, ugyanazon a sértésen:**

1. egysoros alak → **PIROS** (a guard működik ezen a szűk alakon):

```dart
Widget build(BuildContext context) => const Text('Save changes');
```
```
(file: …/ss_validation_summary.dart, line: 113, violationClass: A3)
00:00 +0 -1: Some tests failed.
```

2. UGYANAZ a sértés, két szokványos argumentummal, `dart format` ELŐTT egy
   sorban — majd lefuttatva a projekt saját formázóját:

```
$ dart format lib/core/design_system/components/inputs/ss_validation_summary.dart
  Widget build(BuildContext context) => const Text(
    'Save changes',
    textAlign: TextAlign.center,
    overflow: TextOverflow.ellipsis,
    maxLines: 2,
  );
```

3. a formázott — azaz a repóban ténylegesen előálló — alakon:

```
00:00 +1: All tests passed!
```

**Következmény:** minden olyan beégetett szöveg, amely elég argumentumot kap
ahhoz, hogy a formázó tördelje (a valós komponens-kód többsége), **átcsúszik**
az A3 kapun. A guard a mai fán zöld, de nem azért, mert nincs sértés, hanem
mert csak a legszűkebb alakot méri.

**Javasolt irány:** a szkennelés a fájl EGÉSZÉN fusson (nem
`readAsLinesSync()` soronként), a kommentek kiszűrése után, több soron
átnyúló mintával; a sorszám a találat offsetjéből számolható a racsni
számára.

### F3 — MAJOR: az A6 három küszöb-cellája ÜRES — a választott hordozó nem tud túlcsordulni

**Hol:** `test/l10n/formatters_test.dart:100-170`, a `pumpAtSize` +
`expect(tester.takeException(), isNull)` hármas.

A §6.2 három számított cellája (46 / 52 / 64 karakter) azt hivatott mérni,
hogy a kritikus komponens a +30% magyar tartalékon és a pszeudo-locale +60%-án
sem clippel. A választott hordozó `SsFieldError`:
`Row(icon, SizedBox, Expanded(Text(...)))` — az `Expanded` miatt vízszintesen
nem tud túlcsordulni, függőlegesen pedig a `Row` kereszttengelyén nincs
`RenderFlex overflow` jelentés.

**Mérve:**

```
P3a (SizedBox(height: 24) kalitkába zárt SsFieldError, 2.0 text scale):
  takeException() == null   → a kényszerített túlcsordulás SEM detektálódik

P3b (ugyanaz a hordozó, 4000 karakteres üzenet, 393×852, 2.0 scale):
  P3b exception: null
```

Ha 4000 karakter sem vált ki kivételt, akkor a 46/52/64 karakteres cellák
`isNull` állítása **nem tud pirosra váltani** azon az okon, amit mér — az A6
kritérium gépileg nincs lefedve. (A cellák `measuredSize == logicalSize`
állítása — az F12/L452 zárás — ettől függetlenül **valódi és helyes**, csak
más dolgot bizonyít: a geometria tényleg előáll.)

Az implementer §10-ben őszintén jelezte, hogy ez „regresszió-őr, nem azt
bizonyítja, hogy ma hibás". A mérés viszont azt mutatja, hogy **regressziót sem
tud fogni**: a hordozó szerkezetileg képtelen a mért hibamódra.

**Mérve, hogy a mechanizmus MŰKÖDIK a helyes hordozóval** — tehát a javítás nem
igényel új mérési módszert, csak alkalmas hordozót és layout-kontextust:

```dart
Row(children: [SsButton(label: ssPseudoLocalize('Practice reminder settings label'), …)])
```
```
SsButton-in-Row exception: A RenderFlex overflowed by 1233 pixels on the right.
```

Megjegyzendő, hogy `lib/core/design_system/components/actions/ss_button.dart:69`
kommentje maga is ezt a hibamódot nevezi meg („a width-constrained button and
overflow the Row (A6)").

**Javasolt irány:** olyan hordozó + layout-kontextus, amelyben a túlcsordulás
ténylegesen jelentődik, és a §6.2 három cellája a küszöb körül valóban vált.
A `measuredSize` (F12) állítást tartsd meg mindhárom cellában.

### F4 — MINOR: a „minden függvény tiszta" doc-állítás túlmegy a mérten igazolton

**Hol:** `lib/core/i18n/ss_formatters.dart:19-21`

> „Every function is pure: the locale is a required parameter, none reads
> `BuildContext` …"

A `date()` egy memoizált globálist ír (`_dateSymbolsReady`, 8–14. sor). A
mondat második fele pontosan definiálja, mit ért „pure" alatt (a brief §5.3
definíciója), tehát nem hamis állítás — de a driver-szabály („doc-commentben
csak tesztben bizonyított állítás") szerint a „pure" szó itt szűkítendő vagy
a mellékhatás kimondandó. Nincs cella, ami a tisztaságot mérné.

### F5 — NOTE: a `duration()` tizedes percet ad, nem `m:ss` alakot

**Hol:** `lib/core/i18n/ss_formatters.dart:25-28` — `Duration(seconds: 750)`
→ `"12.5"` / `"12,5"`. Ez dokumentált és locale-tudatos, tehát nem hiba; a
képernyő-körök viszont jellemzően `12:30` alakot várnak majd. Érdemes a
§10-ben rögzíteni, hogy ez szándékos, és a `m:ss` alak külön formázó lesz.

## 3. Acceptance criteria — tételes állás (1. forduló)

| # | Állás | Bizonyíték |
|---|---|---|
| A1 | ✅ | 5 fragmentum × paritás-cella zöld; az implementer §6.3/1 próbája PIROSAT adott a fragmentum nevével — általam a gate-újrafuttatásban megerősítve |
| A2 | ❌ **F1 + F2** | két mért, zöldben maradó sértés-alak |
| A3 | ❌ **F2** | a `dart format`-tal tördelt beégetett mondat zöldben marad |
| A4 | ✅ | en/hu kimenet-diff mind az 5 formázóra, mért CLDR-értékekkel (hu `1 234,5` U+00A0, `2026. aug. 24.`) |
| A5 | ✅ | 14 en ICU-plural kulcs × 3 szabály-cella; a §5.6/4 noun-stabilitás cella valódi (count=1 vs 3, számjegy-maszkolással) |
| A6 | ❌ **F3** | a hordozó 4000 karakteren sem csordul túl |
| A7 | ✅ | `docs/ui/content-style.md` — mind az 5 helyzet, jó/rossz példapárral en+hu, valós ARB-kulcsokra hivatkozva |

## 4. Amit külön ellenőriztem, és rendben van

- **Nincs ARB-írás.** A gate `L10n aggregate freshness OK (en, hu)` lépése
  függetlenül igazolja, hogy a generált aggregátum nem lett kézzel piszkálva —
  ez az M1/M3 pre-flight döntés gépi megerősítése.
- **A `public.dart` nem generált** — nincs `GENERATED-FILE-MARKER`, a
  `tool/gen_public_barrel.dart` a `lib/features/<feature>/public.dart`
  barrelekre való; a `tools/round-slots.py::is_generated_path` `False`-t ad rá.
  A 2 új export sor legitim.
- **A racsni tényleg racsni.** Az implementer §6.3/2 próbája — és a saját, első
  próbám sorszám-eltolódása (90 → 93) — mindkét irányt igazolja: új sértés ÉS
  elavuló bejegyzés is pirosra vált (`difference` mindkét irányban).
- **A pszeudo-transzform hossz-garanciája helyes.** Az accent-térkép csupa BMP
  kódpont (1 UTF-16 code unit), tehát a hossz tényleg nem változik tőle, és a
  ≥1,6× kizárólag a filleren múlik — a §10 3. pontjának indoklása kiállja.
- **`ssPseudoLocaleTestHarness`** a `MaterialApp.builder`-ben helyezi el a
  `textScaler` override-ot, tehát az a `home` alatti fára ténylegesen érvényes
  (kívülre téve a MaterialApp felülírná).
- **Architektúra:** `core/i18n` → `core/design_system/public.dart` export nem
  sért feature-határt; az architecture cella zöld.

## 5. A javító körnek adott leletlista

| # | Súly | Egy sor |
|---|---|---|
| F1 | MAJOR | az A2 guard nem látja a `'$x ' + l10n.y` alakot (a §5.1 által néven nevezett formát) |
| F2 | MAJOR | a guard sor-alapú; a `dart format` tördelt `Text(\n 'Save changes',\n …)` alak átcsúszik |
| F3 | MAJOR | az A6 három küszöb-cellája üres: `SsFieldError` 4000 karakteren sem csordul túl |
| F4 | MINOR | a „minden függvény tiszta" doc-állítás a `date()` memoizált globálisára nem áll |
| F5 | NOTE | `duration()` tizedes percet ad — szándékos, de rögzítendő |

## 6. Merge-kapu állása az 1. forduló végén

- gate (izolált klón): **zöld**, de a zöld a fenti három üres/vak cella miatt
  nem bizonyítja az A2/A3/A6-ot;
- scope-audit: **OK**;
- `full-gate.yml` `dfe96d29`-en: futott (a javító kör után újra kell
  dispatch-elni, exact-SHA — ADR 0086 §2);
- **3 nyitott MAJOR → merge TILOS.**

## 7. Második forduló — a javító kör után

*(a javító kör commitja után töltve)*
