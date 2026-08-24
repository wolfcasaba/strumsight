# E13-R11 — Kör-review (Action, input és form komponenskészlet)

- **Kör:** `E13-R11` · **Branch:** `sonnet-impl/e13-r11-actions-and-forms`
- **Implementer:** Claude Sonnet 5 (`sonnet-impl`), `bb76f230`…`517f185a` (7 commit)
- **Reviewer:** Claude Opus 5 (orchestrátor), READ-ONLY — production kódot nem írtam
- **Review-alap:** `bf2184e5..517f185a` (a pre-flight commit óta)
- **Verdikt:** **CHANGES REQUESTED** — 1 MAJOR, 1 MINOR. A MAJOR **nem
  implementációs hiba, hanem VAKON HAGYOTT ŐR**: a kör zászlós invariánsának
  (§5.1) nevesített falszifikációja MÉRVE nem váltja pirosra a celláját.

---

## 1. Jelzés és handoff

`.codex-round-status`: `status=done`, `head=517f185a`, `scope_audit=ok`,
`dirty_files=1`, `gate_shape=VIOLATION`.

Mindkét gyanús mezőt kimértem, egyik sem valódi lelet:

- **`dirty_files=1`** — a jelzés pillanatában még nem commitolt §10 handoff. A
  kilépés utáni `git status --short` a munkapéldányon **üres**, a `head` a
  legutolsó committal egyezik. Nincs elveszett munka.
- **`gate_shape=VIOLATION`** — **FALSE POSITIVE, az őré, nem a köré.** Az őr
  (`tools/mm-round.sh:381-384`) a `round-gate\.sh[^\n]*(\| *(tail|head)|&&)`
  regexet illeszti a TELJES logra. A kör két TÉNYLEGES gate-hívása szabályos:

  ```
  tools/round-gate.sh test/core/design_system/forms/ss_button_test.dart \
    test/core/design_system/forms/ss_inputs_test.dart \
    test/property/design_system/slider_numeric_sync_test.dart \
    test/core/design_system/component_catalog_test.dart
  ```

  (kétszer, csővezeték és `&&` NÉLKÜL). Az őrt egy READ-ONLY vizsgálódás
  sütötte el: `grep -n "analyze" .../tools/round-gate.sh | head -20` — a
  gate-szkript OLVASÁSA, nem futtatása. A minta a `.sh`-t követő `| head`-re
  illeszkedik, függetlenül attól, hogy a sor a gate-et futtatja-e.
  → **NOTE-1** (lentebb), a kör mércéjét nem érinti.

A brief §10 handoffja **őszinte és mérésekkel alátámasztott**: dokumentálja a
két menet közben talált saját hibát (`SsIconButton` szemantika-határ, `SsButton`
2.0 text-scale túlcsordulás), a valódi-sértés próbát, és — kimondva — az A4
cellák átfogalmazását is (lásd MINOR-1).

## 2. Gate — SAJÁT kézzel újrafuttatva

Izolált klón (`/tmp/review-e13-r11`, `517f185a`), csonkítatlan kimenet,
`GATE_EXIT=0`:

```
format                                                     zöld
analyze                                                    zöld
test test/core/design_system/forms/ss_button_test.dart     zöld
test test/core/design_system/forms/ss_inputs_test.dart     zöld
test test/property/design_system/slider_numeric_sync_test.dart zöld
test test/core/design_system/component_catalog_test.dart   zöld
architecture                                               zöld (12 allowlisted deviation)
secrets                                                    zöld (3580 fájl, 0 lelet)
l10n                                                       zöld — aggregate freshness OK (en, hu), parity 1831 üzenet
```

A **negyedik** útvonal a pre-flight §0.0/D3 miatt került a gate-be, és a
katalógus-bővítés mellett zöld maradt — a D3 exact-count csapdája (1 `SsCard`,
1 `Material`, 1 `DecoratedBox`) nem sült el.

## 3. Scope

```
$ python3 tools/scope-audit.py --repo /home/ubuntu/ss-sonnet-impl-e13-r11 \
    --brief docs/rounds/e13-r11-actions-and-forms.md --base bf2184e53523
Legacy scope audit OK (bf2184e53523..517f185a6b0d, 17 changed path(s), 0 generated/ignored)
```

Mind a 17 útvonal a brief `allowed_paths` listáján. A tilos zóna
(`lib/features/**`, `lib/core/theme/**`, `docs/adr/**`, `tools/**`,
`.github/**`) érintetlen. **Scope: OK.**

## 4. Leletek

| # | Súly | Hol | Mit |
|---|---|---|---|
| MAJOR-1 | MAJOR | `test/core/design_system/forms/ss_inputs_test.dart:18-49` | Az **A1** mindkét cellája ZÖLD marad a brief §6.1-ben nevesített falszifikáció alatt (`labelText` → `hintText`) |
| MINOR-1 | MINOR | `test/…/ss_inputs_test.dart:99-118` | Az **A4** „48 dp padló" cellája vak: a `ConstrainedBox` törlése nem váltja pirosra |
| NOTE-1 | NOTE | `tools/mm-round.sh:382` | A `gate_shape` őr egy `grep … round-gate.sh | head` OLVASÁSRA is elsül (nem a kör dolga) |

### MAJOR-1 — Az A1 őre VAK a saját nevesített sértésére

**A szerződés.** A brief §5.1 a kör zászlós döntése („A placeholder nem
label… **NEM elfogadható gyengítés:** csak `hintText` »mert letisztultabb«"),
és a §6.1 mérce-mátrix első sora nevesítve rendel hozzá őrt:

| Hibás implementáció | Melyik cella vált PIROSRA |
|---|---|
| Csak `hintText`, label nélkül | **A1** |

**A mérés.** A `/tmp/review-e13-r11` izolált klónban EGYETLEN sort mutáltam
(`ss_text_field.dart:60`), pontosan a mátrix által leírt sértést:

```dart
-        labelText: label,
+        hintText: label,
```

Eredmény: **`flutter test …/ss_inputs_test.dart` → exit 0, „All tests
passed!"** — az A1 mindkét cellája zöld maradt.

**A gyökérok** (eldobható próbateszttel kimérve, ugyanabban a klónban):

```
PROBE find.text(label) after typing -> 1 match(es)
PROBE   -> nearest ancestor opacity = 0.0
PROBE decoration.labelText = null
PROBE decoration.hintText  = Song title
```

1. A `hintText` `Text` widgetje **BENNE MARAD a fában** gépelés után is, csak
   `Opacity(0.0)` alá kerül. A `find.text()` a LÁTHATATLAN maradékot is
   megtalálja — az `A1` első cellája tehát „a label a fában van"-t mér, nem
   „a label LÁTSZIK"-ot, miközben a cella saját `reason`-je pont az utóbbit
   állítja (`'a real label never disappears once typing starts — a hintText
   would have'`).
2. A második cella (`find.bySemanticsLabel`) is zöld marad: a Flutter a
   `hintText`-et is beemeli a mező semantics-labeljébe, tehát a felolvasós
   cella sem különbözteti meg a két esetet.

Ez pontosan a `lessons/L403` (a próba a widget JELENLÉTÉT méri, nem a
tartalmat/viselkedést) és a `lessons/L446` (az őr nem azt méri, amit állít)
mintája — a brief §0.0/D8 mindkettőt előre nevesítette.

**Miért MAJOR:** a kör legerősebben megfogalmazott architekturális döntése
gépi őr nélkül marad; egy jövőbeli „letisztultabb" refaktor csendben
visszateheti a placeholdert, és minden teszt zöld marad. Az implementáció maga
HELYES (`labelText` + `FloatingLabelBehavior.always`) — kizárólag az őr vak.

**Javasolt irány** (nem kész patch, a javító kör dolga): a cella a
LÁTHATÓSÁGOT vagy a TULAJDONSÁGOT mérje, ne a fában-létet. Két olcsó,
egymást kiegészítő alak:
- tulajdonság-szint: `tester.widget<TextField>(find.byType(TextField))
  .decoration!.labelText` egyenlő a `label`-lel (és a `hintText` NEM hordozza);
- vizuális szint: a megtalált label-`Text` legközelebbi `Opacity`/
  `FadeTransition` őse ne 0 legyen gépelés után.

A javítás után a fenti mutációt (`labelText` → `hintText`) újra le kell
futtatni, és PIROSNAK kell lennie — ezt a javító kör §10-be írja be mért
kimenettel.

### MINOR-1 — Az A4 „48 dp padló" cellája vak (az érdemi invariáns viszont őrzött)

**A mérés.** Ugyanabban a klónban töröltem a padlót
(`ss_switch_row.dart:44-47`, a `ConstrainedBox(minHeight:
SsSemantics.minimumInteractiveDimension)`): a teszt **zöld maradt (exit 0)**.
A `SsSwitchRow` ugyanis a `Switch` saját, M3-alapértelmezett `padded` érintési
célja + a sor `space2` paddingja miatt amúgy is ~64 dp — a padló sosem
aktiválódik, tehát a törlése láthatatlan.

Ez a brief §6.1 „három kötelező cella (küszöb: 48 dp)" előírásának gyenge
pontja: az implementer a §10-ben **kimondottan és mérésekkel** átfogalmazta a
44/48/56 dp cellákat (mert a tényleges komponensen 44 dp-s sor nem áll elő) —
a reinterpretáció indoklása helytálló, de a maradék két cella egyike sem fogja
meg a padló eltűnését.

**Miért csak MINOR:** a §5.4 ÉRDEMI invariánsát (a TELJES sor érinthető, nem
csak a kapcsoló) őrzi cella, és ezt is kimértem — a „csak a `Switch`
kapcsolható" mutáció alatt

```
Expected: true
  Actual: <false>
00:02 +7 -1: Some tests failed.
```

→ **PIROS**, tehát az akadálymentességi kockázat valódi őre működik. A padló
ezen felül redundáns védelem, aminek az elvesztése sem rontaná a mért
érintési célt.

**Javasolt irány:** a padló-cella a `SsSwitchRow`-t olyan tartalommal mérje,
ahol a `Switch` intrinsic magassága NEM dominál (pl. a padló közvetlen
mérése egy `Switch` nélküli, minimális összeállításon), vagy a cella mondja ki
a jelentésében, hogy a padló redundáns — de akkor a §6.1 három-cellás
küszöb-előírását a brief §0.0-jában kell hozzáigazítani. Follow-up körre is
halasztható.

### NOTE-1 — A `gate_shape` őr false positive-ja

Lásd a §1-et. A `tools/` a kör tilos zónája, tehát ez **nem ebben a körben**
javítandó (ADR 0087 §4) — a lánc-infrastruktúra dolga. A mért minta:
egy `grep -n "…" tools/round-gate.sh | head -20` alakú OLVASÁS `VIOLATION`-t
ad, ami a jövőben elfedheti a VALÓDI csővezeték-sértést (riasztás-fáradás).

## 5. Acceptance criteria — tételesen

| # | Kritérium | Bizonyíték | Állapot |
|---|---|---|---|
| A1 | Tartós label minden mezőn | `ss_inputs_test.dart:18-49` — **de a nevesített sértés alatt is zöld** | ❌ **MAJOR-1** (az implementáció helyes, az őr vak) |
| A2 | A loading gomb mérete változatlan, nincs dupla beküldés | 3 cella; sajátkezű mutáció (`Opacity` → `if (!loading)`) → **PIROS**: `Expected: Size(217.2, 48.0) Actual: Size(66.0, 48.0)` | ✅ |
| A3 | Csúszka ↔ numerikus bevitel MINDIG szinkron | `slider_numeric_sync_test.dart` — 100 próba, próbánként 4 állítás, MINDKÉT valódi callback (`Slider.onChanged`, `TextField.onSubmitted`), exakt egyenlőség; az implementer valódi-sértés próbája (`_round(parsed) + 1`) mérten PIROS | ✅ |
| A4 | A kapcsoló teljes sora érinthető (≥ 48 dp) | „teljes sor" cella sajátkezű mutáció alatt **PIROS**; a „48 dp padló" cella viszont vak | ⚠️ **MINOR-1** |
| A5 | A destruktív gomb semanticsban is elkülönül | `ss_button_test.dart` — `data.hint == 'This cannot be undone'`, `isButton`, és a nem-destruktív ág hint NÉLKÜL | ✅ |
| A6 | 2.0 text scale mellett nincs túlcsordulás | `tester.view.physicalSize = Size(360,1200)` (D7/L452 helyesen), 7 komponens, `takeException() == null`; menet közben VALÓDI hibát fogott (`SsButton` `Row` túlcsordulás → `Flexible`) | ✅ |
| A7 | A fókusz-bejárás a vizuális sorrendet követi | `nextFocus()` × 2, monoton `dy` | ✅ |
| A8 | Minden új szöveg ARB-n át (en + hu) | 3 új kulcs a **fragmentumban** (`design_system_{en,hu}.arb`), aggregátum `--write`-tal regenerálva; gate `l10n`: freshness OK + parity 1831 üzenet. Hardkódolt user-facing string a 7 új fájlban: **0** | ✅ |
| A9 (pre-flight D5) | Az `SsIconButton` gomb-, nem kép-semantics | `SsIcon.decorative` + saját `Semantics(container: true, button: true)`; menet közben VALÓDI hibát fogott (határ nélkül a `getSemantics` egy külső ősre csúszott) | ✅ |

## 6. Architektúra és termékhatárok (AGENTS.md §5–§6)

- **Erőforrás-tulajdonlás:** a 7 új fájl egyike sem említ `MethodChannel`-t,
  `wakelock`-ot, kamerát, mikrofont, felvételt vagy engedélyt — a komponensek
  tisztán prezentációsak. (Az E13-R09 forrás-őre két fájlra van kötve, a jelen
  kör fájljaira nem terjed ki; kézzel ellenőrizve.)
- **`core ↛ feature`:** nincs `features/` import. A `public.dart` mind a 7 új
  fájlt exportálja.
- **Lokalizáció:** a design system csak a SAJÁT keretszövegét birtokolja
  (3 ARB-kulcs); a konkrét üzenetek hívó-oldaliak (`SsValidationIssue.message`,
  `destructiveSemanticHint`, `SsIconButton` label/tooltip) — ugyanaz a
  tulajdonlási szabály, mint az ADR 0411 §4-ben.
- **Deprecation-tisztaság:** az `analyze` info-szintű leletei is javítva
  (`IgnorePointer.ignoringSemantics`, `Radio.groupValue`/`onChanged` →
  `RadioGroup`, `SemanticsData.hasFlag` → `flagsCollection`).

## 7. Próbatesztek (eldobhatók — mind visszaállítva)

Mind a `/tmp/review-e13-r11` izolált klónban futott; a klón a próbák után
`git status --porcelain` szerint **tiszta**.

| Próba | Mutáció | Várt | Mért |
|---|---|---|---|
| P1 | `SsSwitchRow`: a 48 dp `ConstrainedBox` törlése | PIROS | **ZÖLD** → MINOR-1 |
| P2 | `SsSwitchRow`: csak a `Switch` kapcsolható, a sor nem | PIROS | **PIROS** ✅ |
| P3 | `SsTextField`: `labelText` → `hintText` | PIROS | **ZÖLD** → MAJOR-1 |
| P4 | `SsButton`: a felirat kikerül a fából loading alatt | PIROS | **PIROS** ✅ |
| P5 | diagnosztika a P3 gyökérokára (`find.text` + ős-`Opacity`) | — | `opacity = 0.0`, `labelText = null` |

## 8. Verdikt

**CHANGES REQUESTED.** A MAJOR-1 zárásáig nincs merge. A javító kör hatóköre
**egyetlen fájl** (`test/core/design_system/forms/ss_inputs_test.dart`) — a
production kód helyes, nem kell hozzányúlni.
