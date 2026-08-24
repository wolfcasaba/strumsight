# E13-R13 review — Overlay, dialog, bottom sheet és confirmation rendszer

- **Kör:** `E13-R13`, branch `sonnet-impl/e13-r13-overlays-and-confirmations`
- **Reviewelt HEAD:** `34dc6380`
- **Implementer:** `sonnet-impl` (Claude Sonnet 5)
- **Reviewer:** Claude Opus 5 (orchesztrátor) + `security-reviewer` ügynök
  (a brief `risk = "high"`, ezért kötelező)
- **Módszer:** read-only; izolált `/tmp/rev-e13r13` klón, eldobható próbatesztek
- **Verdikt (1. forduló):** **CHANGES REQUESTED** — 1 BLOCKER + 3 MAJOR

## 0. A kiindulási helyzet: minden kapu ZÖLD

| Mérce | Eredmény |
|---|---|
| `tools/round-gate.sh` (implementer, 7 lépés) | ZÖLD |
| Full Gate CI, exact `34dc6380` | [32734185278](https://github.com/wolfcasaba/strumsight/actions/runs/32734185278) **success** |
| Scope-audit (`origin/main` és pre-flight bázison is) | **OK**, 10 útvonal, 0 sértés |
| A kör saját 21 cellája (A1–A8) | 21/21 ZÖLD |
| P1–P5 mutációk (implementer mérte) | mind pirosra váltott — a cellák mérőképesek |

**A leletek MIND e mellett a teljes zöld mellett állnak elő** — ugyanaz a
minta, mint az E13-R12-nél. A gyökérok egyetlen, kimérhető tény:

> A `flutter_test` alapértelmezett felülete **800×600 dp @ dpr 1.0** — szélesebb,
> mint bármely telefon. A kör mind a 21 cellája ezen fut, `textScale = 1.0`-n.
> Egyetlen cella sem lép ki erről a felületről.

## 1. Leletek

### BLOCKER-1 — a lap nem görgethető: támogatott szövegméreten a két
### adatvédelmi dimenzió ÉS mindkét gomb lecsúszik a képernyőről

**Fájl:** `ss_tool_confirmation_sheet.dart:119` (`Column(mainAxisSize: min)`,
`Scrollable` a részfában = **0**) + `ss_overlay_host.dart:141`
(`maxHeight = height * 0.9`) + `:150` (`clipBehavior: Clip.antiAlias`).

A sorrend `reads → writes → leaves-device → recording → gombok`, tehát a két
adatvédelmileg legkritikusabb sor esik ki **elsőként**.

**Saját mérésem** (`zz_review_probe2_test.dart`, 411×891 dp, dpr 3.0, a
kirendelt rect-ekkel; a képernyő jobb széle 411, alja 891):

```
RESULT | SsToolConfirmationSheet | scale=1.0 | cancel: L=24 R=133 B=867 |
        confirm: L=141 R=471 B=867  <== OFF-SCREEN | RenderFlex overflow 84px right
RESULT | SsToolConfirmationSheet | scale=2.0 | cancel: L=24 R=209 B=1437 <== OFF-SCREEN |
        confirm: L=217 R=803 B=1437 <== OFF-SCREEN | overflow 416px right + 570px bottom
```

Azaz **már az ALAPÉRTELMEZETT `textScale = 1.0`-n** is a képernyőn kívülre
kerül a megerősítő gomb (R=471 > 411), `textScale = 2.0`-n pedig **mindkét
gomb és a `leaves-device` + `recording` sor is**.

A `textScale = 2.0` NEM extrém: `SsSemantics.maximumTextScale = 2.0` a
projekt saját, **támogatott** tartományának a teteje.

**A `security-reviewer` független mérése ugyanerre** (412×915, látható hányad):

| text scale | reads | writes | **leaves-device** | **recording** | Cancel | Confirm |
|---|---|---|---|---|---|---|
| 1.0 | 100% | 100% | 100% | 100% | 100% | 82% |
| **2.0** | 100% | 84% | **0%** | **0%** | **0%** | **0%** |
| 800×600 @1.0 (a gate felülete) | 100% | 100% | 100% | 100% | 100% | 100% |

Semantics-bejárással is: 412×915 @2.0-n a „Starts recording" **a semantics
fából is kiesik** (13 → 9 csomópont).

**Sértett szabály:** ADR 0279 **§5.2** (a tool-megerősítés megmutatja,
elhagyja-e az adat a készüléket, indul-e rögzítés) és **§5.3** (a Mégse
minden kockázatos műveletnél elérhető).

**Miért nem fogta meg a kör saját őre:** az A2 cella
`find.byKey('ss-tool-confirmation-leaves-device') → findsOneWidget`
**minden fenti sorban zöld** — a widget létezik, csak nem látszik. Pontosan az
`L460`/`L457` hibaosztály, amit a brief **§0.0/D7 maga tilt**.

### MAJOR-1 — a Mégse elérhetetlen fekvő telefonon, akadálymentesítési
### beállítás NÉLKÜL

**Fájl:** `ss_overlay_host.dart:118-125` (side-sheet ág:
`SizedBox(height: MediaQuery.sizeOf(...).height, ...)`).

915×412 dp (ugyanaz a telefon elfordítva; 915 ≥ `SsBreakpoints.expandedMin`
→ oldalsó lap), **textScale 1.0**:

```
recording = 88%  [y 352..420]
Cancel    = 0%   [y 438..486]   vs. viewport magasság 412
Confirm   = 0%
find(cancel) findsOneWidget = true      ← az A3 cella ZÖLD
tap(cancel) bezárta a lapot = FALSE     ← a viselkedés hamis
```

A menekülő-utak élnek (Escape zár, barrier-koppintás zár), ezért **nem
csapda** — de a §5.3 által előírt, felfedezhető Mégse-vezérlő nem elérhető, és
az A3 cella szövege („always renders a **tappable** cancel control") a
800×600-on kívül **mérhetően téves**.

### MAJOR-2 — a destruktív gomb FELIRATA levágódik: a gomb már nem nevezi meg
### a műveletet (§5.1)

**Fájl:** `ss_dialog.dart:117` · `ss_confirmation_sheet.dart:107` ·
`ss_tool_confirmation_sheet.dart:158` — mindhárom
`Row(mainAxisAlignment: end, [SsButton, SizedBox, SsButton])`,
`Flexible`/`Wrap` nélkül. Az `SsButton` belső `Flexible(Text(ellipsis))`-e
**nem véd**: a gomb megtartja a természetes szélességét, és a felület
`Material(clipBehavior: Clip.antiAlias)`-a keményen **levágja** — nem
ellipszis, hanem vágás.

Saját mérés (`SsDialog`, `confirmLabel: 'Delete session'`, 411 dp):

```
scale=1.0 | confirm: L=165 R=410 | RenderFlex overflowed by 47 pixels on the right
scale=2.0 | confirm: L=241 R=658  <== OFF-SCREEN | overflow 295px
```

`SsConfirmationSheet` @411 dp, scale 2.0: `confirm R=634` **OFF-SCREEN**,
overflow 247px.

Az A1 cella a felépített `Text.data` MEZŐT olvassa
(`ss_confirmation_test.dart:153-163`), nem a kirendelt pixeleket, ezért zöld
marad, miközben a felhasználó **csonkolt destruktív gombot** lát.

### MAJOR-3 — a „pontosan egyszer" őr NEM tartós: reszponzív alakváltásnál a
### destruktív visszahívás **KÉTSZER** fut

**Fájl:** `ss_confirmation_sheet.dart:70` (`var _confirmed = false` a
`State`-ben) és `ss_tool_confirmation_sheet.dart:99`; a mechanizmus
`ss_overlay_host.dart:104-127`.

A `showSheetSurface` `pageBuilder`-e a `presentationForWidth` alapján
**widget-TÍPUST** vált (`_SsBottomSheetSurface` ↔ `SizedBox`+`SsSideSheet`).
Az `expandedMin` átlépésekor a részfa unmountol és újrainflálódik → **új
`State` → `_confirmed = false`**, a gombok újra aktívak.

**Ezt a leletet SAJÁT próbateszttel is megmértem** (nem bemondásra fogadtam
el), differenciál-kontrollal:

```
AFTER-1ST-TAP  calls=1 sheetOpen=true confirmEnabled=false
AFTER-RESIZE   sheetOpen=true confirmReEnabled=true
FINAL SsConfirmationSheet calls=2   (ADR 0279 §5.5 expects 1)
FINAL SsDialog            calls=1 reEnabled=false   (control — nincs alakváltás)
```

Lépéssor: 400×900-on megnyitás → megerősítés, amelynek `onConfirm`-ja dob
(pl. „backend unreachable"), ezért a `Navigator.maybePop()` (`:105`) **soha nem
fut le**, a lap nyitva marad → a készülék elfordítása / foldable kinyitása /
ablak-átméretezés 1000×700-ra → **a gomb újra él** → újabb koppintás →
**`calls = 2`**.

**Sértett szabály:** ADR 0279 **§5.5** — „a destruktív visszahívás pontosan
egyszer fut … törlésnél a második lefutás **adatvesztés**".

A brief §6 három visszahívás-cellája (mégse/vissza/Escape → 0; egyszeri → 1;
dupla koppintás → 1) mind zöld: az őr tárolási helyét egyik sem méri.

## 2. MINOR

- **MINOR-1 — zsákutca sikertelen megerősítés után.**
  `ss_confirmation_sheet.dart:73-79`, `ss_dialog.dart:81-87`,
  `ss_tool_confirmation_sheet.dart:101-106`. Ha `onConfirm` dob, a lap nyitva
  marad **két halott gombbal** (`cancel.onPressed == null`,
  `confirm.onPressed == null`), visszajelzés nélkül. Ez egyben a MAJOR-3
  előfeltétele.
- **MINOR-2 — a négy dimenzió csak POZICIONÁLISAN kikényszerített.**
  `ss_tool_confirmation_sheet.dart:17-23` (`SsToolDimension`, `assert` nélkül):
  `detail: ''` esetén a sor megjelenik, a válasz üres. Ráadásul az A2 cella
  alakja `expect(own, contains(ownDetail))` — üres `ownDetail`-lel
  **tautológia**, tehát ezt az utat elvileg sem tudja pirosra váltani.
- **MINOR-3 — az AI-tool lap az egyetlen felület destruktív semantics-hint
  nélkül.** `ss_tool_confirmation_sheet.dart:168-172` vs. a másik kettő: nincs
  `destructiveSemanticHint`, és nincs `destructive` kapcsoló sem.

## 3. NOTE

- **NOTE-1** — `barrierLabel: cancelLabel` (`ss_overlay_host.dart:48, :78`): a
  barrier a Mégse feliratát kapja a `MaterialLocalizations.modalBarrierDismissLabel`
  helyett.
- **NOTE-2** — `SsOverlayHost` publikusan exportálva
  (`public.dart:15,17`): tetszőleges `WidgetBuilder`-t fogad, így egy későbbi
  feature-kör a §5.1–§5.3 szerződés MEGKERÜLÉSÉVEL is mutathat modálist.
- **NOTE-3** — `maybePop()` a navigátor tetejére hat, nem a komponens saját
  route-jára; a helyesség a hívó `onConfirm`-jának navigációs mellékhatásától
  függ, amit a doc-comment nem köt ki.

## 4. Ami MÉRTEN TISZTA (nem lelet)

- **§5.4 — a háttér semanticsa elrejtett.** Négy konfigurációban
  (800×600@1.0, 412×915@1.0, 412×915@2.0, 915×412@1.0) a valódi
  `simulatedAccessibilityTraversal()` bejáráson a háttér-szonda **egyikben sem
  elérhető**. A `showGeneralDialog`-ra építés (saját `Overlay.insert` helyett)
  **helyes döntés**: a `ModalBarrier` → `BlockSemantics` a keretrendszertől jön.
- **Fókusz-visszaállítás a MEGERŐSÍTÉS útján is** (amit az A5 nem mér):
  `primaryFocus == a nyitó FocusNode` = true.
- **A „pontosan egyszer" a brief által felsorolt HAT úton**: dupla koppintás,
  mégse, Android vissza, Escape, barrier-dismiss, route-pop verseny, async gap
  — mind helyes (0 vagy 1 hívás). A §5.5 csak a MAJOR-3 útján bukik.
- **Adat / engedély / hálózat / titok / prompt-injection:** tiszta. Az overlay
  fájlok kizárólag `package:flutter/material.dart`-ot + 7 design-system
  foundationt + 2 testvér-komponenst importálnak; nincs `lib/features/**`,
  `dart:io`, `dart:convert`, `dio`, `http`, `Uri`, permission-hívás, logolás.
  `pubspec.*` és `assets/` diffje **üres**. Minden hívó-oldali string
  `Text()`-en át renderelődik (markup-inert).
- **Scope:** a diff pontosan a 10 engedélyezett útvonal; a
  `component_catalog_test.dart` (§0.0/D4) és a
  `stage_back_confirmation_test.dart` (§0.0/D3) érintetlenül zöld.
- **Az ARB-eltérés (§10) elfogadva** — lásd §5.

## 5. Az implementer §0.0/D5-eltérése: ELFOGADVA, a pre-flight tévedett

Az implementer nem módosította a `lib/l10n/app_{en,hu}.arb`-ot, holott a
§0.0/D5 ezt írta elő. **Az implementernek van igaza, a pre-flightom volt
hibás:** a két fájl **generált aggregátum** a `lib/l10n/base/**` +
`lib/l10n/features/<feature>_{en,hu}.arb` fragmentumokból, és a valódi forrás
(`lib/l10n/features/design_system_{en,hu}.arb`) **nincs** az engedélyezett
listán. Mért bizonyíték: a kézzel szerkesztett aggregátumon a gate `[7] l10n`
lépése pirosra váltott.

A választott feloldás — a microcopy hívó-oldali `String` paraméterként — a
design system **meglévő mintája** (`SsButton.label`, `SsPermissionState`), és
nem gyengíti a §5 egyetlen kötött döntését sem. Biztonsági szempontból is
semleges. **Nem lelet.**

## 6. Amit a javító körnek meg kell tennie

1. **BLOCKER-1 + MAJOR-1 + MAJOR-2 közös gyökere egy javítás:** a lap/párbeszéd
   törzse **görgethető** (`SingleChildScrollView`), a **gombsor a görgethető
   területen KÍVÜL**, az aljára rögzítve, és a gombsor `Wrap`-elhető (vagy
   `Flexible`-ökkel), hogy ne nyúljon túl vízszintesen.
2. **MAJOR-3:** az egyszeri-őr kerüljön a `State`-en KÍVÜLRE (a `show()`
   closure-jébe zárt `bool`, vagy `Completer`), hogy az alakváltás ne
   nullázhassa.
3. **A mérce bővítése — enélkül a javítás nem bizonyított:** a két gate-teszt
   sosem lép ki a 800×600-as alapfelületről. Kell egy **méret- és
   szövegméret-mátrix** cella (411×891 és 915×412 × textScale 1.0 és 2.0), ami
   a **látható** geometriára mér (`getRect` a képernyő-téglalapon belül +
   `takeException()` == null), nem `findsOneWidget`-re. Ennek a mátrixnak a
   javítás ELŐTTI kódon PIROSNAK kell lennie.

## 7. 2. forduló (fix1, `ffdecc22`) — a geometria zárva, de ÚJ BLOCKER

**A fix1 a hét leletből hatot lezárt**, a tilos zónához nyúlás nélkül: a
lap/párbeszéd törzse görgethető lett, a gombsor a görgethető területen KÍVÜLRE
került (`OverflowBar`), és a két LAP `show()`-closure őrt kapott
(`guardedOnConfirm`).

**A zárást nem bemondásra fogadtam el** — saját próbateszttel újramértem
(`zz_review_probe2`, 411×891, a kirendelt rect-ek):

```
scale=1.0 és 2.0 × {SsDialog, SsConfirmationSheet, SsToolConfirmationSheet}
→ exception: none MIND A HATBAN; minden gomb a képernyőn belül
  (max R=387 < 411, max B=867 < 891)
```

Az 1. forduló ugyanezen a próbán 4 túlnyúlást és 5 képernyőn kívüli gombot
mért — a geometria-osztály (BLOCKER-1, MAJOR-1, MAJOR-2) tehát **zárva**.

### BLOCKER-1 (2. forduló) — a fix1 ÚJ regressziót vezetett be a §5.5-re

**A `SsDialog` a destruktív visszahívást KORLÁTLANUL sokszor futtatja.**

A fix1 a MINOR-1-et úgy oldotta meg, hogy a `catch` ágban **visszaállítja** az
őrt (`ss_dialog.dart:79-86`, `if (mounted) setState(() => _confirmed = false)`),
**de a `SsDialog.show()` nem kapta meg** azt a closure-őrt, amit a két lap igen
— a `show` a nyers `onConfirm`-ot adta tovább (`ss_dialog.dart:62`). Így minden
sikertelen megerősítés újra élesítette a gombot, tartós őr nélkül.

**Saját mérésem (`zz_review_probe4`, `ffdecc22`, ÁTMÉRETEZÉS NÉLKÜL,
411×891 @1.0, dobó `onConfirm`, max 3 koppintás):**

```
RESULT | SsDialog                | destructive callback ran 3 time(s)   <== BLOCKER
RESULT | SsConfirmationSheet     | destructive callback ran 1 time(s)   ✓
RESULT | SsToolConfirmationSheet | destructive callback ran 1 time(s)   ✓
```

A fix1 **ELŐTT** a `SsDialog` 1 hívást adott — a javítás tehát pont a
legdrágább szerződésen rontott. A kör saját új cellája
(`ss_confirmation_test.dart:411`) csak a „dobás + reszponzív alakváltás" utat
méri, ami **csak a lapokra** vonatkozik; a `SsDialog` útjára (dobás → azonnali
újra-élesítés, átméretezés NÉLKÜL) nem volt cella.

**A lelet a reviewer KONTROLL-cellájából jött elő**, nem a fő cellából: a
`zz_review_probe3` `SsDialog`-kontrollja `calls=1`-ről `calls=2`-re változott a
fix1 után. Kontroll nélkül ez a regresszió zöld gate-tel merge-elődött volna.

## 8. 3. forduló (fix2, `80b680d4`) — **APPROVED**

A fix2 a `SsDialog.show()`-nak megadta ugyanazt a `show()`-closure őrt
(`guardedOnConfirm`), és felvett egy gépi őrt **mindhárom** felületre.

**Újramérve, saját próbateszttel (`80b680d4`):**

```
RESULT | SsDialog                | destructive callback ran 1 time(s)   ✓
RESULT | SsConfirmationSheet     | destructive callback ran 1 time(s)   ✓
RESULT | SsToolConfirmationSheet | destructive callback ran 1 time(s)   ✓
FINAL (reshape-próba) SsConfirmationSheet calls=1 | SsDialog calls=1     ✓
geometria: 6/6 exception: none, minden gomb a képernyőn belül            ✓
```

**Leletenkénti zárás:**

| Lelet | Állapot | Az őr |
|---|---|---|
| BLOCKER-1 (1. f.) — nem görgethető lap | ZÁRVA | A9 × 12 cella (3 felület × 2 méret × 2 szövegméret), a `leaves-device`/`recording` görgetéssel elérhetőségével |
| MAJOR-1 — fekvő telefon, Mégse 0% | ZÁRVA | A9 `915×412` cellák |
| MAJOR-2 — levágott gombfelirat | ZÁRVA | A9 `takeException() == null` + rect-ek |
| MAJOR-3 — alakváltás nullázza az őrt | ZÁRVA | `ss_confirmation_test.dart:411` reshape-cella |
| **BLOCKER-1 (2. f.) — `SsDialog` 3× fut** | **ZÁRVA** | „fix2 — 3× un-resized confirm tap" cella, **mindhárom** felületre |
| MINOR-1/2/3 | ZÁRVA | a fix1/fix2 cellái |
| NOTE-1/2/3 | tudomásul véve, jövőbeli kör |

**Független gate-futtatás izolált `/tmp/rev3-e13r13` klónban, `80b680d4`-en:**

```
[1] format ZÖLD (1961 fájl, 0 változott)   [2] analyze ZÖLD (No issues found)
[3] ss_overlay_test.dart ZÖLD (7 cella)    [4] ss_confirmation_test.dart ZÖLD (30 cella)
[5] architecture ZÖLD (12 allowlisted)     [6] secrets ZÖLD (3628 fájl, 0 lelet)
[7] l10n ZÖLD (aggregate friss, 1838 kulcs mindkét nyelven)
MINDEN GATE ZÖLD.
```

Scope-audit `origin/main` bázison: **OK**, 11 útvonal, 0 sértés.
A `component_catalog_test.dart` (§0.0/D4) és a `stage_back_confirmation_test.dart`
(§0.0/D3) érintetlen és zöld.

**Verdikt: APPROVED** — nyitott BLOCKER/MAJOR nincs.
