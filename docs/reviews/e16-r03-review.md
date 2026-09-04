# E16-R03 review — Capability rollout-döntések

- **Reviewer:** Claude (Sonnet 5) orchestrátor, ADR 0055 szerint READ-ONLY
- **Kör:** `E16-R03`, ág `sonnet-impl/e16-r03-capability-rollout-decisions`
- **Implementer:** `sonnet-impl` (Claude Sonnet 5)
- **Mért HEAD:** `96f3380547a7dc4b9ac7e59ca3428aa198cc1b7b` (bázis: `daa3a9a8`)
- **Diff:** 3 fájl, +428 sor (`docs/release/capability-rollout.md` ÚJ,
  `test/app/feature_flags_test.dart`, a brief §10)
- **Scope-audit:** `ok` — `Legacy scope audit OK (daa3a9a84d61..96f3380547a7,
  3 changed path(s), 0 generated/ignored)`
- **Célzott kapu (a munkapéldányon, saját futtatás):** MINDEN GATE ZÖLD —
  format, analyze, mind a 7 teszt-útvonal, architecture, secrets, l10n
- **Router CI:** `success` (`33820152751`, head `96f33805`)

## 1. menet — verdikt: **CHANGES REQUESTED** (0 BLOCKER, 1 MAJOR, 3 MINOR)

A kör érdemi döntése — **ZERO FLIP** — MÉRT és helyes. Külön kiemelendő, hogy
az implementer nem engedett a „legyen diff" nyomásnak: mind a 40
`forEnvironment` mezőt kiértékelte, és a `feature_flags.dart`-ot
bizonyíthatóan érintetlenül hagyta (a `git diff` a fájlra üres). A §10.4
valódi-sértés próba tényleg lefutott, és a mért piros cellák (köztük két, a
körön KÍVÜL élő regressziós cella) hitelesek.

### MAJOR-1 — Az A1 és az A6 acceptance-kritériumnak NINCS gépi mércéje; a döntési tábla marker-blokkját semmi nem olvassa

**Mit mértem.**

```
grep -rn "capability-rollout-decisions" --include=*.dart --include=*.py .   → 0 találat a docs/release-en kívül
grep -n "A6\|resolving\|feloldó"  test/app/feature_flags_test.dart          → csak KOMMENT (372–373. sor)
grep -n "capability_group\|classification" test/app/feature_flags_test.dart → csak KOMMENT
```

A `docs/release/capability-rollout.md` §2 táblája köré az implementer
kifejezetten gépi feldolgozásra való határolókat tett
(`<!-- capability-rollout-decisions:begin -->` / `:end`), **de egyetlen cella
sem olvassa őket**. Az első új teszt kommentje „A1/A6"-ot állít, a törzse
viszont KIZÁRÓLAG flag-booleanokat mér — a tábla tartalmáról semmit.

**Miért MAJOR, nem MINOR.** A brief §6.1 falszifikációs mátrixa nevesítve
ígéri: *„A tábla »később« bejegyzést tartalmaz feloldó kör nélkül → **A6**
piros."* Ma **semmilyen** implementáció nem tudja pirosra vinni: a tábla
minden nem-BE sora törölhető, „később"-re cserélhető, vagy egy capability
teljesen kihagyható a táblából — a kapu zöld marad. Az A1 ígért bizonyítéka
(„+ a flag-tesztek **fedettség-cellája**") ugyanígy nem létezik: semmi nem
méri, hogy mind a 40 `forEnvironment` mező pontosan egyszer szerepel.

Ez pontosan az [L271](../LESSONS.md#l271) hibaosztály dokumentum-oldali
párja: a cella NEVE és KOMMENTJE többet ígér, mint amit a törzse mér — és a
kör terméke épp a tábla, tehát a kör fő artefaktumát ma semmi nem őrzi.

**A javítás (a kör `allowed_paths`-án BELÜL, `test/app/feature_flags_test.dart`).**
Új cellák, amelyek a marker-blokkot fájlként olvassák és parse-olják:

1. **A1 — fedettség:** a `forEnvironment` törzsének mind a **40** mezőneve
   pontosan egyszer szerepeljen a tábla `flags` oszlopában. A mezőlistát a
   `lib/app/config/feature_flags.dart`-ból olvasd ki (a `return FeatureFlags(`
   törzs `kulcs:` mintája), NE hardkódold — különben egy jövőbeli új flag
   némán kimaradhat a táblából.
2. **A1 — zárt besorolás-készlet:** minden sor `classification` oszlopa a
   `BE` / `PREVIEW` / `KI` / `N/A` készletből való (a kezdő `**` jelölés
   megengedett); ismeretlen érték → piros.
3. **A6 — feloldó kör:** minden **nem-BE és nem-N/A** sor `resolving`
   oszlopa vagy `EXX-RYY` alakú kör-azonosítót, vagy egy fán feloldható,
   repó-relatív útvonalat tartalmazzon; a puszta „később" / „later" / „TBD" /
   üres cella → piros.
4. **Fail-closed parse:** ha a marker-blokk hiányzik, üres, vagy a
   fejléc-sor oszlopai nem az elvártak, az legyen **piros**, ne néma
   átcsúszás ([L566](../LESSONS.md#l566) mintája).

**Bizonyítsd a javítást mutációval** (a jelentésbe a mért kimenettel): (a)
írj át egy `resolving` cellát „később"-re → az A6 cella piros; (b) törölj egy
sort a táblából → az A1 fedettség-cella piros; állítsd vissza mindkettőt, és
mutasd a zöldet.

### MINOR-1 — Félrecímkézett komment

`test/app/feature_flags_test.dart:372-373` — a komment „A1/A6"-ot állít egy
olyan cellára, amely egyiket sem méri (csak flag-booleanokat). A MAJOR-1
javítása után a kommentet igazítsd ahhoz, amit a cella TÉNYLEG mér.

### MINOR-2 — Szóhiba a dokumentumban

`docs/release/capability-rollout.md`, a fejléc „Amit ez a dokumentum NEM
tesz" blokkja: *„`tool/release/verify_ga_scope.py` **geometrikusan**
visszaellenőrizve"* → **`gépileg`**.

### MINOR-3 — Számhiba a §10.6-ban

A brief §10.6 „A **három**, a körön kívül élő őr" bevezető után **négy**
fájlt sorol fel (`ui_inventory_test.dart`, `ga_scope_test.dart`,
`analysis_rollout_flags_test.dart`, `app_config_test.dart`). A §0.0.1 R5 három
őrt vett fel a `gate_tests`-be, az `ui_inventory_test.dart` korábban is ott
volt — a mondatot ehhez igazítsd.

## NOTE-ok (nem igényelnek javítást)

- **NOTE-1.** A §10.3 érvelése — hogy a zero-flip miatt a D4 hatósugár-mérés
  tárgytalan, és a §10.4 próba mérte fel helyette a kockázatot — helytálló és
  jól dokumentált. A mért megfigyelés (az `aiTutorCloudEnabled` flip nem
  mozdítja a widget-fát, mert a felületi gate az `aiTutorEnabled`-en fut)
  hasznos a következő körnek.
- **NOTE-2.** Az A7 cella szó szerinti magyar sztringekre illeszt
  (`'saját állítást nem tesz'`). Ez a repó bevett doc-guard mintája
  (`rollout_decision_test.dart` A5), de törékeny a dokumentum
  átfogalmazására; a MAJOR-1 strukturált parsere ezt hosszú távon kiváltja.
- **NOTE-3.** A scope-audit első futása `VIOLATION`-t adott a
  `prompt-e16-r03.md`-re — az az ORCHESZTRÁTOR dispatch-artefaktuma volt a
  munkapéldány gyökerében, nem az implementer munkája. Eltávolítva, az audit
  újrafuttatva: `ok`, 3 fájl. A kör diffje végig a listán belül volt.
