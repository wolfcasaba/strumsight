# E13-R09 review — StageScaffold és session transport

- **Kör:** `E13-R09` · **Branch:** `sonnet-impl/e13-r09-stage-scaffold-and-transport`
- **Reviewelt commit:** `2f3b7c14` (implementer: `sonnet-impl` / Claude Sonnet 5)
- **Reviewer:** Claude Opus 5 (orchestrátor), read-only, izolált klón:
  `/tmp/review-e13-r09`
- **Dátum:** 2026-08-23
- **Verdikt:** **CHANGES REQUESTED** — 3 MAJOR (mind MÉRVE), 1 MINOR, 2 NOTE

## 1. Jelzés, scope, gate

| Ellenőrzés | Eredmény |
|---|---|
| `.codex-round-status` | `status=done`, `gate_shape=ok`, `scope_audit=ok`, `head=2f3b7c14` |
| `dirty_files=1` kivizsgálva | a jelzés pillanatképe; a fa a jelzés után **tiszta** (`git status --short` üres), mind a 7 fájl a `2f3b7c14` commitban |
| Scope-audit (saját futtatás) | `Legacy scope audit OK (abe98fb0..2f3b7c14, 7 changed path(s), 0 generated/ignored)` — pontosan a brief `allowed_paths` hét eleme |
| `tools/round-gate.sh` (saját futtatás, izolált klón) | **mind a 8 lépés ZÖLD** (format, analyze 0 issue, 3× test = 7+9+3 PASS, architecture, secrets, l10n) |
| Router CI a kör SHA-ján | `32669563051` @ `2f3b7c14` → **success** |
| §10 handoff igazmondása | a leírt állítások reprodukálva; az implementer maga jelentette, hogy az ELSŐ A2-próbája zöld maradt és megerősítette a cellát — ez helyes és jóhiszemű önjelentés |

**A zöld kapu nem bizonyíték** (a protokoll alapelve): az alábbi három MAJOR
mindegyike a teljesen zöld gate MÖGÖTT él, és mindegyiket eldobható
próbateszttel MÉRTEM, nem olvasással következtettem.

## 2. A §6.1 mérce-mátrix gépi ellenőrzése (mutáció → cella)

Minden sort a produkciós fájl tényleges mutálásával mértem, majd visszaállítottam.

| §6.1 sor (hibás implementáció) | Elvárt | **MÉRT** |
|---|---|---|
| `autoStart` a scaffoldban, ami mikrofont nyit | **A1** PIROS | **GREEN — nem fogja meg** ❌ |
| A Finish overflow menübe kerül | **A2** PIROS | RED ✅ (mind a 4 aktív cella + a tap-próba) |
| A paused és az active vizuálisan azonos | A3 PIROS | RED ✅ |
| Fix magasságú Stage fejléc | **A4** PIROS | **GREEN — nem fogja meg** ❌ |
| A vissza-hook kétszer hív | **A5** PIROS | RED ✅ |
| Az ébrentartás bent ragad kilépés után | A7 PIROS | RED ✅ |

Hat sorból négy teljesül; a két **vastagon szedett**, legfontosabb sor nem.

## 3. Leletek

### MAJOR-1 — az A1 cella nem méri a kör LEGFONTOSABB invariánsát (mikrofon/kamera)

**Hely:** `test/core/design_system/stage/ss_stage_scaffold_test.dart:43-79`

**Mit mértem.** A `ss_stage_scaffold.dart`-ba beírtam pontosan azt a hibás
implementációt, amit a §6.1 első sora nevez meg — egy `autoStart` paramétert,
ami az `initState`-ben mikrofont nyit:

```dart
if (widget.autoStart) {
  const MethodChannel('plugins.flutter.io/record').invokeMethod<void>('start');
}
```

`flutter test test/core/design_system/stage/ss_stage_scaffold_test.dart` →

```
00:01 +7: All tests passed!
```

**Mind a hét cella zöld maradt, az A1 is.** Ok: az A1 cella kizárólag a
`MethodChannel('wakelock_plus')` csatornára regisztrál mock handlert, és csak
az azon a csatornán érkező hívásokat gyűjti a `channelCalls` listába. Bármely
MÁS platform-csatorna (mikrofon, kamera, recorder, permission) hívása
láthatatlan marad számára — pedig a cella címe és az acceptance-kritérium
(„A scaffold NEM indít mikrofont/kamerát/felvételt") pont ezt ígéri.

**Miért MAJOR.** Ez a kör egyetlen `risk = "high"` indoka (ADR 0276 Kontextus,
brief §0.0): egy prezentációs widget ne telepíthessen csendes adatgyűjtést.
A gépi őr ma a wakelockot őrzi, a mikrofont nem — a védett dolog a védtelen.
A brief §6 A1-sora a `grep`-et is bizonyítékként említi, de a grep egy
egyszeri, kézi lépés, nem a fán maradó regresszió-őr; a §10-ben szereplő
grep-kimenet a MAI állapotot igazolja, a jövőbeli `autoStart`-ot nem.

**Javasolt irány (nem kész patch).** Forrás-szintű őrcella a két új produkciós
fájlra (a `test/core/architecture_dependency_test.dart` mintájára: `File(...)
.readAsStringSync()` + tiltott token-lista — `MethodChannel`, `wakelock`,
`camera`, `record`, `microphone`, `permission`), és/vagy a meglévő
csatorna-cella kiterjesztése a mikrofon/kamera/recorder csatornákra is. A
döntés az implementeré; a mérce az, hogy a fenti mutáció PIROSAT adjon.

### MAJOR-2 — az A4 cellák nem a deklarált geometrián mérnek (a landscape mérése elmarad)

**Hely:** `test/core/design_system/stage/ss_stage_scaffold_test.dart:124-137`
(a harness `MediaQuery` wrappere: `:23-24`)

**Mit mértem.** A harness a `MediaQueryData(size: …)`-szal csak azt írja felül,
amit a leszármazottak *olvasnak* a MediaQuery-ből; a tényleges layout-kényszert
a teszt-felület (`tester.view`) adja, amit a teszt sosem állít át. Próba:

```
PROBE P1 declared=Size(800.0, 400.0)  -> actual Scaffold size=Size(800.0, 600.0)  view=Size(800.0, 600.0)
PROBE P1 declared=Size(1000.0, 500.0) -> actual Scaffold size=Size(800.0, 600.0)  view=Size(800.0, 600.0)
PROBE P1 declared=Size(1200.0, 800.0) -> actual Scaffold size=Size(800.0, 600.0)  view=Size(800.0, 600.0)
PROBE P1 declared=Size(400.0, 800.0)  -> actual Scaffold size=Size(800.0, 600.0)  view=Size(800.0, 600.0)
```

Vagyis a három „landscape/expanded" A4 cella **ugyanazt az egyetlen 800×600-as
mérést** végzi el háromszor. A `MediaQuery.orientationOf`-ból jövő ág-választás
(`_WideStage`) helyesen működik, de a kritérium lényege — a **helyhiányos,
alacsony** landscape viewport — sosem áll elő. A brief §5.4 és §9 pont ezt
nevezi meg a kör fő elrendezési kockázatának.

**Amit a próba NEM talált:** maga az implementáció rendben van. Valódi
800×400-as felületen, 2.0 text scale mellett, a valódi `SsSessionTransport`-tal
a `bottomAction` slotban nincs túlcsordulás (`PROBE P2`, `PROBE P3` →
`exception=null`). Ez tehát **őr-hiba, nem termék-hiba** — de a jövőbeli
regressziót (pl. az `Expanded`+scroll kicserélése fix magasságokra) semmi nem
fogja meg.

**Javasolt irány.** A cellák állítsák be a tényleges felületet
(`tester.view.physicalSize` + `devicePixelRatio`, `addTearDown(tester.view.reset)`),
és a `MediaQuery` maradjon a `textScaler`-höz. Így a cellanevekben szereplő
méretek valóban azok lesznek, amiken a mérés fut.

### MAJOR-3 — 661 pixeles túlcsordulás a rest-állapotú transportban 2.0 text scale mellett

**Hely:** `lib/core/design_system/components/music/ss_session_transport.dart:113-122`
(`_RestIndicator`)

**Mit mértem.** `idle` állapot, valós hosszúságú magyar felirattal, 360×640-es
telefon-felületen (tényleges `tester.view.physicalSize`), 2.0 text scale:

```
PROBE P5 idle-label overflow exception=A RenderFlex overflowed by 661 pixels on the right.
```

A `Text(label!)` egy `Row`-ban ül `Flexible`/`Expanded` nélkül, így a felirat
nem tördelhet. A brief §3 a scope-ba explicit beleírja a „high contrast és 2.0
text scale" támogatást, az A4 kritérium szövege pedig „Landscape-ben **és 2.0
text scale mellett** nincs túlcsordulás" — ez a mai kódban egy valós,
felhasználó által kiváltható (akadálymentességi beállítás) törés. Egyetlen
transport-cella sem állít text scale-t, ezért a gate zöld marad.

**Javasolt irány.** A feliratot tördelhetővé tenni (`Flexible`/`Expanded` +
`softWrap`), és a transport-tesztbe felvenni egy 2.0 text scale-es, szűk
viewportos cellát mind a rest-, mind az aktív ágra.

### MINOR-1 — a „Fix magasságú Stage fejléc → A4" mátrix-sor így nem teljesíthető

Mérve: 240 px és 500 px fix magasságú fejléccel, VALÓDI 800×400-as landscape
felületen sem lesz túlcsordulás, mert a középső slot `Expanded` + görgethető —
a fejléc elveszi a helyet, a scroll pedig elnyeli. (500 px-nél az **A8** vált
pirosra, nem az A4.) Ez a layout javára szól, de azt jelenti, hogy a mátrix
sora rossz cellához van rendelve. A MAJOR-2 javításakor a §10-ben mondja ki az
implementer, hogy ezt a sort ténylegesen az A8 (slot-sorrend) őrzi, vagy adjon
hozzá egy célzott cellát (pl. a scroll-ág eltávolítása → PIROS).

### NOTE-1 — az A8 a paint-sorrendet méri, nem a semantics-bejárást

`getTopLeft(...).dy` szigorú monotonitása egy nem-átfedő függőleges layoutra jó
közelítés, és a teszt doc-commentje ezt korrektül ki is mondja. A §10 őszintén
leírja, miért nem a `SemanticsNode` DFS lett a mérce. Nem blokkoló.

### NOTE-2 — a Pause `countIn` és `finishing` alatt látható, de letiltott

Az A2 kritérium a **láthatóságot** követeli („MINDIG látható"), és a ADR 0276
4. döntése is így fogalmaz, tehát ez megfelel. Csak tudatosításként:
count-in közben a felhasználó nem tud egy mozdulattal megállni — ha ez
termék-szinten nem szándékos, az egy KÖVETKEZŐ kör kérdése, nem ezé.

## 4. Ami rendben van (mérve)

- **A2** — négy aktív állapot, kulcs + semantics-tooltip + egyetlen tap
  közvetlen `onFinish`-hívása; az overflow-menü sértés mind a négy cellát
  pirosra váltja (saját próba megismételte).
- **A3** — hat páronként különböző aláírás; a `paused == active` mutáció piros.
- **A5** — a három küszöb-cella valódi rendszer-visszával
  (`handlePopRoute`); a duplán hívó hook piros.
- **A6** — `NavigationBar`/`NavigationRail` `findsNothing`.
- **A7** — mount 1× kér, rebuild nem kér újra, unmount 1× old; a
  `dispose`-ból kivett release piros.
- **Erőforrás-tulajdonlás** — a két új fájlban nulla plugin-import, nulla
  `MethodChannel`, nulla `core/platform` import (grep + a saját olvasásom); a
  design-system határőr (`architecture`) zöld.
- **Scope** — pontosan a hét engedélyezett útvonal, ADR-t nem írt (a 0276 már
  merge-elve volt).

## 5. Merge-döntés

**Nem merge-elhető**, amíg a MAJOR-1, MAJOR-2 és MAJOR-3 nyitva van. A javító
kört ugyanaz a motor (`sonnet-impl`) viszi a fenti leletlistával; utána a
review frissül, és a CI-t a javított HEAD-en újra kell dispatch-elni
(exact-SHA kapu).

**A javító körben módosítható fájlok** (a brief `allowed_paths` szűkítése, nem
tágítása):
`lib/core/design_system/components/music/ss_session_transport.dart` ·
`test/core/design_system/stage/ss_stage_scaffold_test.dart` ·
`test/core/design_system/stage/ss_session_transport_test.dart` ·
`docs/rounds/e13-r09-stage-scaffold-and-transport.md`

## 6. A review próbatesztjei

Mind eldobható volt, a jelentés megírásakor törölve
(`git status --short` a review-klónban üres):
`zz_probe_test.dart` (P1–P3), `zz_probe4_test.dart` (P4),
`zz_probe5_test.dart` (P5), valamint öt produkciós mutáció, mindegyik
`git checkout --`-ral visszaállítva.
