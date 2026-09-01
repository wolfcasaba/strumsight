# E12-R20 — Review (Accessibility és localization release audit)

- **Reviewer:** Claude (Opus 5, orchestrátor) — read-only, ADR 0055
- **Implementer:** `sonnet-impl` (claude-sonnet-5)
- **Branch:** `sonnet-impl/e12-r20-accessibility-and-localization-release-audit`
- **Mért HEAD:** `415d75fd`, base `18e1cfdf` (pre-flight commit)
- **Dátum:** 2026-09-01
- **Diff:** 5 fájl, +1009 sor, 0 törlés — pontosan a `allowed_paths` lista
  (`scope_audit=ok`, `scope_audit_changed=5`)

## Verdikt: **CHANGES REQUESTED** — 1 MAJOR, 2 MINOR, 1 NOTE

A kör KÓDJA lényegében helyes, és a brief legkockázatosabb előírásait
(§0.0.A/R2–R7) hiánytalanul teljesíti. A MAJOR nem kódhiba, hanem **őr-hiba**:
egy acceptance-kritériumhoz (A6) a §6.1 mátrix nevesített hibamódot rendel,
amit a szállított mérce **nem mér**. Ez az E12-R18/R19 mért hibaosztályának
harmadik előfordulása ([L563](../LESSONS.md#l563), [L565](../LESSONS.md#l565),
[L566](../LESSONS.md#l566)): teljesen zöld kapu, helyes kód, vak mérce.

---

## MAJOR-1 — Az A6-nak NINCS gépi őre: a kivétel-nyilvántartást egyetlen cella sem olvassa

**Hol:** `docs/accessibility/known-exceptions.yaml` (a mért artefaktum),
`test/accessibility/release_flow_text_scale_test.dart`,
`test/accessibility/release_flow_semantics_test.dart` (a hiányzó cella helye).

**Mit ír elő a brief.** A §6 A6 sora: „Minden talált kivétel **ownerrel és
lejárattal** szerepel a `known-exceptions.yaml`-ben" — bizonyíték: „**a fájl +
a teszt cellája**". A §6.1 mérce-mátrix nevesítve rendel hozzá őrt:
„A kivétel **lejárat nélkül** kerül a nyilvántartásba → **A6** vált PIROSRA".

**Mit mértem.** A két új tesztfájl a `known-exceptions.yaml`-t **kizárólag
kommentben és `reason:` sztringben** említi — nyolc találat, mind az. Egyetlen
cella sem nyitja meg a fájlt:

```
$ grep -n "File(\|readAsString\|dart:io\|loadString\|Directory(" \
    test/accessibility/release_flow_text_scale_test.dart \
    test/accessibility/release_flow_semantics_test.dart
$ echo $?
1        # nincs találat — egyetlen cellának sincs fájlolvasó API-ja
```

Nincs `tool/`- vagy `.github/`-oldali parszer sem
(`grep -rln "known.exceptions" tool/ .github/` → üres).

**A falszifikáció, ami ma NEM fog pirosra váltani** — mindhárom a §6.1
mátrix által A6-hoz rendelt vagy azzal egyosztályú sértés:

1. Töröld bármelyik bejegyzés `owner:` és `expiry:` sorát → a kapu **zöld marad**.
2. Vegyél fel egy negyedik bejegyzést tetszőleges mezőkkel, teszt-tükör
   nélkül → a kapu **zöld marad**.
3. Töröld az egész `exceptions:` listát (üres nyilvántartás), a teszt-oldali
   `_knownOverflows` / `knownUnlabeledCount: 3` toleranciákat meghagyva → a
   kapu **zöld marad**, miközben a fán három nem dokumentált, tolerált
   `lib/**` defekt marad.

**Miért MAJOR, és miért nem elég a meglévő védelem.** A szállított
`_knownOverflows` / `knownUnlabeledCount` **shrink-only** logika valóban erős,
és egy irányt le is zár: *nem rögzített* hiba → piros cella; *elavult*
(már nem reprodukálódó) bejegyzés → piros cella. Ez helyes és megtartandó. De a
lezárt irány a **Dart-konstans** oldala; az A6 tárgya a **YAML-nyilvántartás**,
és a kettő között ma semmi nem tartja a kapcsolatot. A `known-exceptions.yaml`
fejléce maga állítja, hogy „a tükör HARD, shrink-only guard" és hogy a tükör
nélküli bejegyzés „drift bug, nem valid állapot" — ezt az állítást ma **semmi
nem kényszeríti ki**, tehát a fájl próza, nem szerződés.

**Külön, ugyanide tartozó lelet:** mindhárom bejegyzés `expiry: unscheduled`.
Ez tartalmilag pontosan az a „lejárat nélkül" állapot, amit a §6.1 pirosnak
jelöl — egy sosem lejáró kivétel nem lejárat. A javítás tehát nem merül ki a
mezők LÉTÉNEK ellenőrzésében.

**A javítás javasolt helye és alakja** (a döntés az implementeré, ez irány):

- Új cella az egyik meglévő, engedélyezett tesztfájlban (`dart:io` +
  `File(...).readAsStringSync()` a `flutter_test` host-VM alatt működik).
- **`package:yaml` NINCS deklarálva a fán** (mérve az E12-R19-ben) — kézi
  sor-parszer kell, a `tool/check_data_inventory.dart` mintájára.
- A cellának **fail-closed**-nak kell lennie (az E12-R19
  [L566](../LESSONS.md#l566) mért hibája: a fail-open parszer némán elnyelt egy
  egész bejegyzést). Nem-parszolható sor / ismeretlen kulcs / hiányzó
  `exceptions:` blokk → **piros**, sosem „nulla bejegyzés, tehát zöld".
- Mérje mind a három irányt:
  1. minden bejegyzésnek van nem-üres `id`, `owner`, `expiry`, `severity`,
     `file`, `measured_on`, `source_test` mezője;
  2. az `expiry` **konkrét elköteleződés** — dátum vagy megnevezett kör-azonosító;
     ha a projekt megtartja az `unscheduled` fokot, akkor ahhoz KÖTELEZŐ egy
     dátumozott `review_by:` mező, különben piros;
  3. a YAML `id`-halmaza és a teszt-oldali tükrök (`_knownOverflows`
     bejegyzések + a `knownUnlabeledCount` forrása) **kölcsönösen** fedik
     egymást — se árva YAML-bejegyzés, se tükör nélküli tolerancia.
- Az üres nyilvántartás legyen legális (ha egyszer minden defekt javul), de az
  árva **tükör** ne: a 3. pont mindkét irányban mérjen.

---

## MINOR-1 — A „eredmény" lépés valójában a `PracticeResultFallback`, és ez hiányzik a NEM-lefedett listáról

**Hol:** `docs/accessibility/release-audit.md` §5,
`release_flow_text_scale_test.dart:132-147`,
`release_flow_semantics_test.dart:44-50`.

A brief §1 core flow-ja „…→ **eredmény**"-tel zárul. Ellenőriztem az
implementer állítását, és **pontosan igaz**: a router
`AppRoutes.practiceResult` útvonala mindig `const PracticeResultFallback()`-et
épít (`lib/app/routing/app_router.dart:346-348`), a részletes
`PracticeResultScreen` csak explicit `PracticeHistoryEntry`-vel, `Navigator.push`-sal
érhető el. Az implementer ezt őszintén, forrás-hivatkozással dokumentálta a
teszt-kommentekben — ez helyes magatartás, nem lelet.

A lelet az, hogy ez a **lefedettségi korlát** csak a tesztek kommentjeiben él.
A `release-audit.md` §5 („What this audit does NOT cover") öt pontot sorol, és
ezt **nem** — miközben a §2 A1/A2 sora „core flow"-ként számol el egy olyan
utat, amelynek utolsó állomása egy statikus, interaktív elem nélküli
fallback-képernyő. Egy release-döntést hozó olvasó ebből azt értheti, hogy a
tényleges eredmény-képernyő is auditálva lett 2.0 skálán és képernyőolvasóval.
**Javítás:** egy pont a §5-be, ami kimondja, hogy a `PracticeResultScreen`
(a `PracticeHistoryEntry`-vel megnyitott, tartalmas eredménynézet) **nem** része
ennek az auditnak, és megnevezi, melyik útvonalon lenne elérhető.

## MINOR-2 — Az A6 „PASS" indoklása a jelentésben emberi olvasat, gépi mérés nélkül

**Hol:** `docs/accessibility/release-audit.md` §2, A6 sor.

A sor: „**PASS** — `known-exceptions.yaml`, 3 entries, each with
`owner`/`expiry`". A többi sor mérésre hivatkozik (teszt-cella, gate); ez a sor
**szemrevételezésre**. A MAJOR-1 javítása után ez a cella a gépi őrre kell
hivatkozzon (fájl + cellanév), és az `expiry: unscheduled` fokot is fel kell
oldania a MAJOR-1 szerint.

## NOTE-1 — Ami MÉRTEN jó, és a javító körben nem gyengülhet

Kifejezetten rögzítem, mert a javító kör könnyen elrontja:

- **A §0.0.A/R2–R5 maradéktalanul teljesül.** Saját, locale-paraméteres bejáró
  (`_walkCoreFlow`), a harness angol helperei nincsenek hívva; a locale a
  store-on át (`{'ss.settings.locale': localeCode}`) megy; a text-scale a
  `platformDispatcher.textScaleFactorTestValue`-n; és **minden** cella
  412×915-ös telefon-viewporton mér (`_setPhoneViewport`), nem a vak
  800×600-on ([L558](../LESSONS.md#l558), [L452](../LESSONS.md#l452)).
- **A valódi-sértés próba valódi, és PERMANENS cellává vált** — nem egyszeri
  kézi lépés: `1.0 → 20.0px` vs `2.0 → 40.0px`, `greaterThan`-nel mérve. Ha a
  kapcsoló nem érné el a fát, mindkettő 20.0px lenne, és minden A1/A2 cella
  üresen zöldellne.
- **Az A3 nem jelenlét-alapú** ([L460](../LESSONS.md#l460)): a
  `tester.semantics.simulatedAccessibilityTraversal()` tényleges bejárása méri
  az elérhetőséget, és a fókusz-sorrendet `containsAllInOrder`-rel
  (Pause → Finish → Exit), nem „valahol a fában megvan" alakban. A
  `switch-row-split-semantics-node` lelet pontosan azért került elő, mert a
  meglévő komponens-tesztek `find.bySemanticsLabel` jelenlét-próbái vakok rá —
  ez a kör önálló hozadéka.
- **A `2.5` cella szándékos hiánya helyes** (brief §6: a 2.0 az inkluzív
  release-küszöb, egy zöld 2.5 nem bizonyítéka a 2.0-nak).
- **A STOP-protokoll helyesen NEM sült el:** a három lelet P2, a `lib/**`
  érintetlen — a kör auditált, nem javított (brief §0.0/§5.2).

---

## Scope-audit

`scope_audit=ok` (gépi, `base=18e1cfdf`, 5 változott fájl). Kézzel újramérve:
a diff a 4 új fájl + a brief §10 kitöltése. `lib/**`, `test/support/**`,
`test/l10n/**`, `docs/adr/**`, `tools/**` **érintetlen**. Meglévő a11y/l10n
teszt nem gyengült és nem kapott `skip`-et.

## A javító kör hatóköre

Csak a MAJOR-1 + MINOR-1 + MINOR-2. Az `allowed_paths` **változatlan** —
mindhárom javítás a már engedélyezett fájlokon belül elvégezhető.
A NOTE-1-ben felsoroltak egyike sem módosulhat.
