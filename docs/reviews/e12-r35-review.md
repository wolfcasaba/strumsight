# E12-R35 review — Technikaiadósság- és flag cleanup

- **Reviewer:** Claude (Opus 5), orchestrátor-szék, ADR 0055 read-only review
- **Implementer:** Claude Sonnet 5 (`sonnet-impl`)
- **Ág:** `sonnet-impl/e12-r35-technical-debt-and-flag-cleanup`
- **Review-alap:** `9c265f0d` (`origin/main` = `496264d9`)
- **Izolált klón:** `/tmp/rev-e12-r35` (`git clone` a munkapéldányból, `9c265f0d`,
  `tools/prepare-flutter-generated.sh` után) — a próbák NEM a munkapéldányban futottak
- **Verdikt (1. kör):** CHANGES REQUESTED — 2 MAJOR, 2 MINOR
- **Verdikt (2. kör, `a261400c` után):** **APPROVED** — 0 nyitott lelet (§7)

## 0. Mit mértem újra

```
flutter test test/tooling/deprecation_audit_test.dart \
  test/tooling/architecture_allowlist_guard_test.dart \
  test/tooling/feature_flag_audit_test.dart
→ 00:06 +35: All tests passed!
```

A gate ZÖLD, a scope tiszta (`tools/scope-audit.py --base 11277b3d` →
`Legacy scope audit OK (4 changed path(s))`), egyetlen `lib/` fájl sem
módosult (A6), és a §10 valódi-sértés próbája hitelesen dokumentált. A két
MAJOR nem a zöldet cáfolja, hanem azt, hogy **a zöld nem bizonyíték** a
brief §6.1-ben megígért két hibaosztályra: mindkettőt eldobható mutációval
fogtam meg, és mindkét mutáció mellett a teljes cellakészlet ZÖLD maradt.

## 1. BLOCKER

Nincs.

## 2. MAJOR

### M1 — Az A2 „nincs második igazság" NEM gépi mérce: a Kör 5 hívás lecserélhető saját dátum-összehasonlításra, és minden cella zöld marad

**Hol:** `tool/check_deprecations.dart:8` (import), `:210-220`
(`findExpiredFlags`) · `test/tooling/deprecation_audit_test.dart:71-88`

**Mit ígér a brief:** a §6.1 mérce-mátrix első sora szó szerint: „Az audit
saját flag-listát **vagy saját dátum-összehasonlítást** épít a Kör 5 eszköze
helyett → `A2 expired flags come from the round-5 checker`". A §9 ugyanezt
nevezi meg a kör harmadik fő kockázatának („Kettős flag-igazság").

**Mit mértem (izolált klón, `9c265f0d`):** kicseréltem a Kör 5 hívást egy
lokális, szemantikailag azonos másolatra —

```dart
// import 'check_feature_flags.dart' show isFeatureFlagExpired;  ← törölve
bool _localExpired({required DateTime expiresOn, required DateTime now}) {
  final e = DateTime(expiresOn.year, expiresOn.month, expiresOn.day);
  final t = DateTime(now.year, now.month, now.day);
  return t.isAfter(e);
}
// findExpiredFlags: isFeatureFlagExpired(...) → _localExpired(...)
```

majd `flutter test test/tooling/deprecation_audit_test.dart`:

```
00:06 +14: All tests passed!
```

**Tehát pontosan az a hibás implementáció, amit a §6.1 szerint az A2 cellának
pirosra kell váltania, ZÖLDEN átmegy.** Az A2 két cellája a
`findExpiredFlags` *viselkedését* méri (fixture-katalógus, inkluzív határ) —
azt viszont egy duplikált implementáció is teljesíti. A tényleges
újrahasznosítás ma csak emberi olvasással igazolható, márpedig a kör egyik
kimondott célja épp az, hogy ne kelljen olvasásra hagyatkozni.

**Fontos, hogy mit NEM állítok:** a szállított kód **valóban** a Kör 5
eszközét hívja (`check_deprecations.dart:8` + `:217`) — a lelet nem
szerződésszegés, hanem hiányzó ŐR. A jövőbeli körnek ma semmi nem szól, ha
kényelmi okból lemásolja a lejárati logikát.

**Javítás (a §4 engedélyezett listáján belül):** forrás-szintű cella a
`deprecation_audit_test.dart`-ban, amely a `tool/check_deprecations.dart`
SAJÁT forrását olvassa, és állítja, hogy (a) importálja a
`check_feature_flags.dart`-ot `isFeatureFlagExpired`-del, (b) hivatkozik rá,
és (c) nem tartalmaz saját nap-granularitású dátum-összehasonlítást
(`isAfter`/`isBefore`/`compareTo` a lejárati úton). A cella neve legyen
`A2 the tool has no second expiry truth of its own`, és a §6.1 mátrix
első sora erre a névre mutasson.

### M2 — Az A1 „MINDEN `@Deprecated` elem" NÉMÁN alulmér: a többsoros annotációt a minta nem fogja, és a 12/9-es cella sem veszi észre

**Hol:** `tool/check_deprecations.dart:57-60` (`_deprecatedPattern`) ·
`test/tooling/deprecation_audit_test.dart:50-68`

**Mit ígér a brief:** A1 — „Az audit MINDEN `@Deprecated` elemhez kiad egy
tételt". A `_deprecatedPattern` viszont csak az `@Deprecated('egyetlen
string literál')` alakot ismeri fel; a Dartban teljesen szokásos, hosszú
üzenetnél gyakori többsoros / szomszédos-string-literálos alakot nem.

**Mit mértem (izolált klón):** a `lib/features/live/model/chord.dart` végére
egy VALÓDI, 13. deprecation került —

```dart
@Deprecated(
  'probe: a multi-line deprecation message '
  'spanning two adjacent string literals',
)
class ProbeMultiLineDeprecated {}
```

A nyers előfordulásszám ezzel `grep -ro "@Deprecated(" lib --include="*.dart" | wc -l`
→ **13**. A tool viszont továbbra is 12-t lát, és:

```
00:06 +14: All tests passed!
```

Az `A1 the real tree reports 12 deprecated sites in 9 files` cella pont
azért marad zöld, mert a hiányzó találat miatt a szám nem változik — a
baseline-cella tehát a saját vak foltját nem tudja megfogni. A hatás nem
elméleti: a `docs/release/technical-debt.md` egy RELEASE-dokumentum, amelynek
teljességére a jövőbeli takarító körök hivatkoznak; egy néma alulmérés ott
„nincs több adósság"-ként olvasódik.

**Javítás (a §4 listáján belül):** (a) a minta fogja fel az `@Deprecated(`
minden argumentum-alakját (a záró zárójelig, több soron át is), és (b)
kereszt-ellenőrző cella: a `findDeprecatedSites` találatszáma EGYEZZEN a
nyers `@Deprecated(` előfordulásszámmal ugyanazon a bemeneten — ez az a
cella, amelyik a jövőbeli új alakokat is elkapja, nem csak a mait. Javasolt
név: `A1 no @Deprecated form is silently missed`. A fixture tartalmazzon
egy többsoros annotációt is.

## 3. MINOR

### m1 — Az `externalCallsiteCount` név többet állít, mint amit mér (importáló FÁJLOK száma)

`tool/check_deprecations.dart:114-131` — a `countExternalImporters` fájlonként
legfeljebb egyet számol (`break` az első találatnál), tehát az érték
**importáló fájlok** száma, nem hívóhelyeké. A mező neve
(`externalCallsiteCount`), a jelentés szövege („external callsite(s)") és a
`technical-debt.md` „Measured" oszlopa („external callsites") viszont
hívóhelyet állít. Egy fájl, amely háromszor importál, egynek számít. A mérés
maga védhető és a döntéshez elegendő; a **név** és a doc-comment pontatlan,
és ez a repó doc-comment-fegyelmébe ütközik („csak tesztben bizonyított
állítás"). Javítás: nevezd át `externalImporterCount`-ra (a jelentés- és
doc-szöveggel együtt), vagy mondd ki mindhárom helyen, hogy importáló
fájlokat mér.

### m2 — A frozen-scope őr (A5) kikerülhető azzal, hogy a tétel `Path` cellájába `—` kerül

`tool/check_deprecations.dart:354-356` — a frozen-scope ellenőrzés csak akkor
fut, ha `item.path.trim().isNotEmpty`. A szállított `technical-debt.md` három
sora (`docs/release/technical-debt.md:56-58`) `—`-t ír a `Path` oszlopba, ami
nem üres, de nem is útvonal, tehát az `any(cell.contains(path))` sosem talál.
A három mai sor tartalma legitim (valóban szórt TODO-klaszterek), a **minta**
viszont opt-out-ot ad: egy jövőbeli sor `—`-sal befagyasztott útvonalat is
listázhat anélkül, hogy az A5 megszólalna. A `TechnicalDebtItem.path`
doc-commentje ráadásul „empty string"-et ír, a valóságban `—` szerepel.
Javítás: normalizáld a „nincs egyetlen útvonal" jelölést (üres cella VAGY egy
explicit, felismert jelölő), és a felismert jelölőn kívül minden nem-üres
érték essen át a frozen-scope ellenőrzésen.

## 4. NOTE

- `_parseMarkdownTableRows` a `rows.sublist(1)`-gyel feltétel nélkül eldobja
  az első adatsort fejlécként. Ma helyes (mindkét markerblokk fejléces
  táblát tartalmaz), de fejléc nélküli blokkon néma adatvesztés lenne.
- Az `A1 the real tree reports 12 deprecated sites in 9 files` cella
  szándékosan bázisvonal-jellegű: minden jövőbeli deprecation-hozzáadás
  pirosra viszi. Ez a kör mércéje szerint helyes (mért bázisvonal), de a
  következő, `@Deprecated`-et hozzáadó körnek tudnia kell, hogy ezt a számot
  ott KELL frissítenie — érdemes a §10/`technical-debt.md` szövegében is
  kimondani.
- A `readSourceTree` a gitignore-olt, generált `lib/l10n/app_localizations*.dart`
  fájlokat is beolvassa. Ma ártalmatlan (nincs bennük `@Deprecated`), de a
  12/9-es cella így egy generált előfeltételtől is függ.

## 5. Amit kifejezetten jónak mértem

- A `check_feature_flags.dart` tartalom-paraméteres mintája hűen átvéve: a
  `main()` vékony burkoló, minden lépés tiszta függvény — a §8 szerkezeti
  előírása maradéktalanul teljesül.
- A küszöb-cellahármas bemenetei `architectureAllowlistBaseline ± 1`-ből
  számolnak, nem kézzel beírt 11/13 literálból — a bázisvonal átírásakor a
  hármas együtt mozog.
- Az A3 SHIPPED-halmaz cellája (L120) valóban a valódi `architectureAllowlist`-et
  köti; a §10 valódi-sértés próbája szó szerinti piros kimenettel dokumentált,
  a visszaállítás `grep -c`-vel igazolva.
- A `countExternalImporters` relatívút-feloldása MÉRT javítás egy naiv
  substring-egyezéssel szemben (6 vs 17 találat a `lib/features/progress/`-ra),
  és a mérés a §10-ben és a `technical-debt.md` Methodology szakaszában is
  szerepel — pontosan az a fajta „a számot megmagyarázom" fegyelem, amit a
  leltártól várunk.
- A 14 leltártétel mindegyike hordoz felelőst ÉS konkrét, ellenőrizhető
  eltávolítási feltételt; a `progress_v2` nulla hívóhelye kifejezetten NEM
  töröl-engedélyként szerepel (§5.3).

## 6. Javító kör — a nyitott leletek

| # | Súly | Mit kell tenni |
|---|---|---|
| M1 | MAJOR | forrás-szintű őr az A2 „nincs második igazság"-ra (`A2 the tool has no second expiry truth of its own`) |
| M2 | MAJOR | a `@Deprecated` minta fogja a többsoros alakot is + kereszt-ellenőrző cella (`A1 no @Deprecated form is silently missed`) |
| m1 | MINOR | `externalCallsiteCount` → importáló-fájl-szám néven/szövegben, mindhárom helyen |
| m2 | MINOR | a frozen-scope őr ne legyen `—`-sal kikerülhető |

A javítás mindhárom érintett fájlja a §4 engedélyezett listáján van; a
§6.1 mérce-mátrixot és a §6 cellanév-táblát a brief-ben együtt kell
frissíteni az új cellanevekkel.

---

## 7. Második kör — a javítás ellenőrzése

- **Javító kör commitja:** `a261400c` (motor: `sonnet-impl`, ugyanaz az ág)
- **Izolált klón:** `/tmp/rev2-e12-r35` (`a261400c`, friss
  `prepare-flutter-generated.sh`)
- **Scope:** `tools/scope-audit.py --base 11277b3d` →
  `Legacy scope audit OK (11277b3dbd60..a261400c50b7, 5 changed path(s), 1 generated/ignored)`
- **Alapfutás:** `flutter test` a §7 három útvonalán → `00:09 +37: All tests passed!`
  (a review-alapon 35 volt; +2 az új őrcella)

### Leletenkénti zárás — mindegyik a MEGFOGÓ próba megismétlésével

| # | Státusz | Amit MÉRTEM a javítás után |
|---|---|---|
| **M1** | **ZÁRVA** | Ugyanaz a mutáció (a Kör 5 `isFeatureFlagExpired` import + hívás lecserélve egy lokális, azonos szemantikájú `_localExpired`-re) most PIROSRA vált: `Some tests failed.` — és pontosan egy cella bukik: `check_deprecations.dart source — A2 has no second expiry truth A2 the tool has no second expiry truth of its own`. Az 1. körben ugyanez a mutáció mellett `All tests passed!` volt. Visszaállítva. |
| **M2** | **ZÁRVA** | Ugyanaz a mutáció (`lib/features/live/model/chord.dart` végére egy valódi, többsoros / szomszédos-string-literálos `@Deprecated`, nyers `grep -ro '@Deprecated(' lib` → **13**) most PIROSRA vált: `A1 the real tree reports 12 deprecated sites in 9 files [E]` — vagyis a tool MEGTALÁLJA a többsoros alakot, és a bázisvonal-cella észreveszi az új deprecationt. Az 1. körben a tool 12-t látott és minden cella zöld maradt. Visszaállítva (`git status --short` üres). Az új kereszt-ellenőrző cella (`A1 no @Deprecated form is silently missed`, `deprecation_audit_test.dart:70`) a jövőbeli alakokra is köt. |
| **m1** | **ZÁRVA** | `externalCallsiteCount` → `externalImporterCount` (`check_deprecations.dart:169,179,197`), a jelentés szövege `external importer file(s)` (`:471`), és a `technical-debt.md` mindhárom helye átírva (Methodology, a „Measured" oszlop 14 sora, a `zero external importers` megfogalmazás). A számok változatlanok — csak az állítás lett igaz. |
| **m2** | **ZÁRVA** | Bevezetve a `noSinglePathMarker = '—'` konstans (`check_deprecations.dart:286`); a frozen-scope őr doc-commentje (`:377`) kimondja, hogy KIZÁRÓLAG ez a jelölő opt-out, minden más nem-üres érték átesik az ellenőrzésen. A `TechnicalDebtItem.path` doc-commentje (`:271`) a valósághoz igazítva. |

### Mit ellenőriztem még

- A §6 cellanév-tábla és a §6.1 mérce-mátrix a briefben az ÚJ cellaneveket
  hivatkozza, és a §10 mindkét új őr valódi-sértés próbáját dokumentálja.
- A tilos zóna érintetlen: `tool/check_architecture.dart`,
  `tool/check_feature_flags.dart` és a `lib/**` fa a kör diffjében nem
  szerepel (`git diff --stat origin/main...HEAD` → 5 útvonal, mind a §4
  listáján + ez a review-fájl).
- A NOTE-ok (§4) nyitva maradnak — egyik sem merge-blokkoló, és egyik sem
  romlott a javítással.

## VÉGSŐ DÖNTÉS: **APPROVED**

0 nyitott BLOCKER/MAJOR/MINOR. A merge feltétele a változatlan zöld kapu a
merge SHA-n (Full Gate + Router CI).
