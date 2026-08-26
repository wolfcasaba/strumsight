# E13-R22 — Practice result, history és Speed Builder UI

- **Státusz:** PREPARED (előre megírva 2026-08-15, kód olvasva: `main @ 74f8a8ec`)
- **Típus:** Chapter 13 (UI/UX Design System), Kör 22
- **Kör-azonosító:** `E13-R22`
- **Branch:** `<motor>/e13-r22-practice-results-and-speed-builder`
- **Előfeltétel:** `E13-R21` merge-elve (aktív session UI)
- **Brief szerzője:** Claude (Opus 5)
- **Előre kiosztott ADR:** [`0283`](../adr/0283-results-never-overstate-certainty.md)
  — **MÁR MEGÍRVA ÉS MERGE-ELVE** (`a4a71550`, 2026-08-15). A fejléc eredeti
  „a Claude írja meg a kör indításakor" mondata elavult; újraírása **H1**
  volna. Lásd §0.0/B/R5. A kör **nem** ír új ADR-t.

> ⚠ **Pre-flight (indítás előtt KÖTELEZŐ):** olvasd el a TÉNYLEGES jutalom-
> főkönyv (ledger) interfészét — a §5.4 kimondja, hogy a jutalom-összegzés
> onnan jön, nem UI-oldali számításból. Ha nincs ilyen réteg, `blocked`
> jelzéssel állj meg. Eltérésnél §0.0 revízió.

```ai-router
schema_version = 1
risk = "high"
allowed_paths = [
  # §0.0/B/R6 — a brief eredeti három könyvtára (`practice/results/`,
  # `practice/history/`, `practice/speed_builder/`) a fán NEM létezik, és a
  # practice feature rétegzése application/data/domain/presentation. A három
  # felület a presentation rétegé; a kör azon belül dolgozik.
  "lib/features/practice/presentation/screens/practice_result_screen.dart",
  "lib/features/practice/presentation/screens/practice_history_screen.dart",
  "lib/features/practice/presentation/screens/speed_builder_screen.dart",
  "lib/features/practice/presentation/widgets/",
  "lib/features/practice/presentation/providers/",
  "lib/features/practice/public.dart",
  "lib/l10n/base/app_en.arb",
  "lib/l10n/base/app_hu.arb",
  "lib/l10n/app_en.arb",
  "lib/l10n/app_hu.arb",
  "test/features/practice/result_confidence_test.dart",
  "test/features/practice/history_corrupt_record_test.dart",
  "test/features/practice/speed_ladder_test.dart",
  "test/features/practice/reward_idempotency_test.dart",
  "test/ui/goldens/",
  "test/ui/ui_inventory_test.dart",
  "docs/rounds/e13-r22-practice-results-and-speed-builder.md",
]
gate_tests = [
  "test/features/practice/result_confidence_test.dart",
  "test/features/practice/history_corrupt_record_test.dart",
  "test/features/practice/speed_ladder_test.dart",
  "test/features/practice/reward_idempotency_test.dart",
  # §0.0/B/R7 — a három MEGLÉVŐ, listán KÍVÜLI pin (futtatni kell, szerkeszteni
  # tilos): a result-screen teszt és az a11y-audit a practice presentation
  # fájában, a screen-size guard a `test/core/` fában.
  "test/features/practice/presentation/",
  "test/core/screen_size_guard_test.dart",
  # A golden-sáv a §0.0/B/R9 (ADR 0426) óta NEM a lokális ARM-gate-en fut:
  # `tools/golden-x86.sh check test/ui/goldens/e13_r22_screens_golden_test.dart`
  "test/ui/ui_inventory_test.dart",
  "test/core/architecture_dependency_test.dart",
  "test/tooling/dio_factory_guard_test.dart",
  "test/tooling/preferences_plugin_import_guard_test.dart",
  "test/tooling/route_literal_guard_test.dart",
]
native_gate = false
```

## 0.0 BRIEF-REVÍZIÓ — 2026-08-25, batch pre-flight (E13-R17…R35)

A brief 2026-08-15-én készült; ez a pre-flight `main @ 41fbd40` ellen mért.
**Visszakeresett előzmény:** [L478](../LESSONS.md) (a pre-flight csak szűkíthet;
a tágítás H3), [ADR 0307 §4](../adr/0307-parallel-round-execution.md) (a
`lib/l10n/app_*.arb` GENERÁLT aggregátum, a forrás a `base/` és a
`features/` szegmens), [L481](../LESSONS.md) (a lánc remote konténerből nem
indítható). A hibaosztályt a **teljes Ch13 sávon** mérte ki egy batch-vizsgálat:
az R17–R35 MIND a generált aggregátumot sorolta fel forrásként (`agg=2, frag=0`).

**Kockázat = high, indoklás:** az eredmény- és előzmény-felületek a felhasználó teljes gyakorlási történetét (személyes adat) jelenítik meg.

### R1 — `lib/l10n/app_{en,hu}.arb` GENERÁLT aggregátum → a FORRÁS a szegmens

A kör fájából `lib/features/practice/results/`, `lib/features/practice/history/`, `lib/features/practice/speed_builder/` **még nem létezik** — a képernyőket ez a kör hozza létre, tehát MINDEN szövege új.

A kör ezért **nem tudott volna egyetlen szöveget sem írni** a saját listáján
belül. Feloldás — H3 lista-tágítás, **user-engedéllyel (2026-08-25)**, a
lehető legszűkebb alakban:

- `practice` → nincs saját fragmentuma, a kulcsai a `base/app_*.arb` szegmensben élnek

Az aggregátum a listán MARAD, de **kizárólag generált kimenetként**
(`dart run tool/gen_l10n_segments.dart --write`); a merge-elt precedens
egységesen a forrást ÉS a regenerált aggregátumot is commitolja (E09-R26
`df0ad3dd`, E13-R12 `376b8a1d`, E13-R10 `b11ab2ed`). **Új fragmentum NEM
készül**, ezért a `test/l10n/arb_parity_test.dart` beégetett szegmens-listáját
sem kell bővíteni — a felvett források mind szerepelnek benne.

### R2 — a kör SAJÁT feature-fáján élő, ma zöld widget-tesztek (FELVÉVE)

Ezek közvetlenül a migrálandó képernyőkre állítanak, tehát a migráció után
pirosra váltanának, ami a §0 szerint `blocked` lenne:

  - nincs ilyen.

**A jogosultság szűk:** a teszteket az ÚJ widgetekre kell ráállítani. A lefedett
viselkedést gyengíteni, cellát törölni vagy `skip`-elni **TILOS** — az a mérce
meggyengítése, amit a gate-guard emberhez eszkalál.

### R3 — keresztmetszeti tesztek (NEM kerültek listára — figyelmeztetés)

A kör fájára hivatkozó további widget-tesztek közös infrastruktúrán élnek
(`test/app/**`, `test/core/**`, más feature-ek fái) — nincs ilyen. Ezeket a kör
**NEM** szerkesztheti: ha egy elbukik, az `blocked` jelzés és célzott
brief-revízió, nem csendes átírás. A körbe húzásuk a scope-fegyelem feladása
lenne.

### R4 — a képernyő-leltár őre (H3 önjavító kör, ADR 0112, 2026-08-25)

A `test/ui/ui_inventory_test.dart` **repó-szintű** őr: a `tool/ui_inventory.dart`
a `lib/features/**` fa `_screen.dart` végű fájljait számolja, a teszt pedig
EGZAKT `hasLength(...)`-et állít rájuk. Ez a kör a(z) `lib/features/practice/history/`, `lib/features/practice/results/`, `lib/features/practice/speed_builder/` könyvtár-előtag
alá képernyőt hoz vagy hozhat, tehát a szám **elmozdul**, és az exact-SHA Full
Gate pirosra vált.

A `test/ui/goldens/` előtag ezt **nem** fedi (az a `test/ui/` fának csak az egyik
ága), a leltárteszt utólagos felvétele pedig tágítás, azaz **H3** — az
orchestrátor a pre-flightban nem oldhatja fel ([L478](../LESSONS.md)). Ezért
kerül a listára MOST, az önjavító körben.

**MÉRVE (E13-R16, 2026-08-25):** pontosan ez a hiány állította meg a sáv első
migrációs körét — [full-gate 32867296946](https://github.com/wolfcasaba/strumsight/actions/runs/32867296946)
6366 passed / 2 failed, `hasLength(79)` a tényleges 81 ellen. A `9acd14e5`
sáv-szintű batch pre-flight azért nem találta meg, mert a `tools/brief-lint.py`
`S9` szabálya csak LITERÁLIS `*_screen.dart` útvonalat nézett, KÖNYVTÁR-előtagot
nem — a predikátumot ugyanez az önjavító kör javította, regressziós teszttel
([L483](../LESSONS.md)).

**A jogosultság PONTOSAN a szám emelése** a kör tényleges képernyőszámára; a
leltárteszt minden más állítása érintetlen marad. Kerülőút (képernyő-átnevezés
vagy a `tool/ui_inventory.dart` szabályának lazítása) **TILOS** — az a mérce
meghamisítása.

### S12 — a fa-szintű őrök a kör LOKÁLIS kapujába (2026-08-25)

A kör lokális kapuja eddig KIZÁRÓLAG a saját céltesztjeit futtatta, ezért a
teljes `lib/` fát pásztázó őrök leletei szerkezetileg csak a ~17 perces
exact-SHA Full Gate-en jelentek meg — javító kör árán. MÉRT eset: **E13-R16/F8**
(`docs/reviews/e13-r16-review.md`), ahol mind a három új képernyő közvetlenül
importálta a `design_system/foundations/**`-ot a `public.dart` helyett — **11
sértés** —, és a review szó szerint rögzíti, miért nem fogta a célzott gate:
a `tools/round-gate.sh` `architecture` lépése a `tool/check_architecture.dart`-ot
futtatja, ami egy MÁSIK, tágabb szabálykészlet; a design-system-határ mércéje
egy külön `test/core/` teszt, amit csak a teljes suite futtat.

Ezért ez a kör mostantól a `gate_tests`-ben futtatja ezeket az őröket:

- `test/core/architecture_dependency_test.dart`
- `test/tooling/dio_factory_guard_test.dart`
- `test/tooling/preferences_plugin_import_guard_test.dart`
- `test/tooling/route_literal_guard_test.dart`

A kiválasztás MÉRT, nem vaktában: a globális őrök a `Directory('lib')` teljes
fát pásztázzák (bármelyik kör diffje elmozdíthatja őket), a szűkített őrök pedig
csak akkor kerülnek fel, ha a kör `allowed_paths`-a metszi a pásztázott
gyökeret.

**Ezek az őrök NEM kerülnek az `allowed_paths`-ra** — és ez szándékos: a kör
futtatja, de NEM szerkesztheti őket, tehát a lelet javítása kizárólag a kör
SAJÁT kódjában történhet. Cella törlése, `skip`-je vagy küszöb-lazítása így
gépileg kizárt, a mérce pedig tiszta erősítést kap.

## 0.0/B BRIEF-REVÍZIÓ — 2026-08-26, a kör SAJÁT pre-flightja (`main @ cf73bdf2`)

A §0.0 batch-revízió `main @ 41fbd40`-en mért; azóta az E13-R20 és az E13-R21
merge-elt. Az alábbi hét revízió a `cf73bdf2` fán ÚJRAMÉRT tények alapján
készült ([L488](../LESSONS.md#l488): egy brief-revízió mért állítása
MÉRÉSI IDŐPONTHOZ kötött).

**Visszakeresés (ADR 0312, KÖTELEZŐ).** Szűkítve → teljes korpuszon:
[ADR 0301](../adr/0301-reward-ledger-append-only-idempotency.md) (append-only
főkönyv, szerializált idempotencia — az A5 gépi alapja),
[ADR 0283](../adr/0283-results-never-overstate-certainty.md) (a kör kötött
döntései), [ADR 0290 §2](../adr/0290-compassionate-streaks-and-idempotent-claims.md)
(a felület nem számol jutalmat), [L486](../LESSONS.md#l486) +
[L493](../LESSONS.md#l493) + [ADR 0426](../adr/0426-golden-rasterization-on-the-gate-architecture.md)
(golden-raszterizáció), [L397](../LESSONS.md#l397) +
[L465](../LESSONS.md#l465) (a képernyő-leltár egzakt száma),
[L478](../LESSONS.md#l478) (a pre-flight csak szűkíthet).

### R5 — az ADR 0283 MÁR MERGE-ELT: a kör nem ír ADR-t

```
git log --oneline -1 -- docs/adr/0283-results-never-overstate-certainty.md
→ a4a71550 docs(ch13): E13-R22..R25 briefek + ADR 0283, 0284
```

A fejléc „a Claude írja meg a kör indításakor" mondata a batch-előkészítés
maradéka: a `0283` a briefekkel EGYÜTT megíródott és merge-elt. Újraírása
**H1** (merge-elt ADR módosítása, ADR 0087 §2). A kör kötött döntései a
merge-elt ADR 0283 §Döntés 1–7 pontjai; ez a brief §5-je azokat ismétli.

A `tools/round-slots.py reserve-adr --round E13-R22` a pre-flightban **0428**-at
foglalta, MIELŐTT a mérés kiderítette, hogy nincs szükség új számra. A 0428
ezért **kiosztott, de fel nem használt** szám marad — a foglaló szándékosan a
lemezen lévő ÉS a foglalt számok fölé megy, tehát ez nem ütközés, csak egy
kihagyott sorszám.

### R6 — a három megnevezett könyvtár NEM létezik → a felületek a `presentation` rétegben élnek

```
find lib/features/practice -type d
→ application  data  domain  presentation  (presentation/{screens,views,widgets})
ls lib/features/practice/presentation/screens
→ practice_hub_screen.dart  practice_result_screen.dart
  practice_session_screen.dart  practice_setup_screen.dart
```

A §0.0/R1 azt állította, hogy „a képernyőket ez a kör hozza létre" — ez az
**eredmény-felületre mérve hamis**: a `PracticeResultScreen` létezik, a
`/practice/result` route-on regisztrált, és három teszt pinneli (R7). A brief
eredeti listája így **nulla létező fájlt** fedett: a körnek egyetlen
engedélyezett fájlja sem lett volna, amin dolgozhat.

**Feloldás — útvonal-csere, NEM új jogosultság-osztály.** A három felület a
practice feature `presentation` rétegéé; a lista erre cserélődik. A csere a
közvetlenül előző, merge-elt kör (E13-R21, `e209af39`) user-jóváhagyott
listájának **valódi részhalmaza** — az `lib/features/practice/` (teljes fa)
helyett csak a `presentation/` réteg + a `public.dart` barrel. A kör tehát
**kevesebbet** kap, mint a szomszédja, nem többet:

| E13-R21 (merge-elt) | E13-R22 (ez a kör) |
|---|---|
| `lib/features/practice/` (teljes fa) | `lib/features/practice/presentation/` + `public.dart` |

**A `domain/`, `data/` és `application/` a kör számára OLVASHATÓ, de NEM
írható** — a §3 „a pontozás vagy a jutalom-logika módosítása tilos" tiltása
így gépi is: a scope-audit a listán kívüli írást `VIOLATION`-nel jelzi.

### R7 — a §0.0/R2 „nincs ilyen" MÉRVE HAMIS: három meglévő teszt pinneli az eredmény-felületet

```
grep -rln "PracticeResultScreen" test/
→ test/features/practice/presentation/practice_result_screen_test.dart
  test/features/practice/presentation/practice_a11y_audit_test.dart
  test/core/screen_size_guard_test.dart
```

A `test/core/screen_size_guard_test.dart:368` konkrét hívása:

```dart
home: PracticeResultScreen(entry: fixture),
```

**A feloldás L488 szerint NEM a lista tágítása, hanem a típus HELYBEN
tartása.** A kör kötelezettségei:

1. a `PracticeResultScreen` **típusneve, fájl-útvonala és `entry:` nevesített
   konstruktor-paramétere változatlan** marad (a képernyő HELYBEN migrál, nem
   új fájlba költözik);
2. a három pin **zöld marad** — a migráció HOZZÁAD (megbízhatóság-sáv,
   jutalom-összegzés, végrehajtható következő lépés, megosztás), nem vesz el;
3. a három teszt a `gate_tests`-ben **fut**, de az `allowed_paths`-on **nincs
   rajta**: a kör futtatja, szerkeszteni nem tudja (az S12-vel azonos minta).
   Ha valamelyik pirosra vált, az `blocked` jelzés és célzott brief-revízió,
   nem csendes átírás.

**Ez a bekezdés az `S11` brief-lint lelet KIMONDOTT válasza.** A `tools/brief-lint.py`
`S11` szabálya a revideált briefen a `practice_result_screen.dart`-ra jelez
(`test/core/screen_size_guard_test.dart`,
`test/features/practice/presentation/practice_a11y_audit_test.dart`,
`test/features/practice/presentation/practice_result_screen_test.dart`), és két
kifutót ad. A kör a MÁSODIKAT választja — a szabály saját szövege szerint:
*„Ha a kör a képernyőt bizonyíthatóan nem cseréli le, a §0.0 mondja ki ezt a
mérést."* A kör a képernyőt **nem cseréli le**: a típus, az útvonal és az
`entry:` konstruktor kötött (fent, 1. pont), tehát a három pin nem a migráció
áldozata, hanem a migráció **mércéje**. A tesztek felvétele az
`allowed_paths`-ra tágítás volna, ami az orchestrátornak **H3**
([L478](../LESSONS.md#l478)) — ezért nem történik meg.

**Az S11-lelet a pre-flight ELŐTT nem létezett** (`.pipeline/brief-lint-E13-R22.md`
→ „nincs lelet"): az eredeti lista nulla létező fájlt fedett, tehát nem is
tudott meglévő képernyőt érinteni. A lelet az R6 útvonal-cserével jelent meg,
és ezzel a kifutóval zárul.

### R8 — az A1 három cellájának NINCS producere → a mért bemenet a lefedettségi arány

Az első pre-flight-szabály („elérhetetlen cél-státusz: mérd meg, melyik INPUT
produkálja") szerint megmérve:

```
grep -rn "confidence" lib/features/practice/domain/model/*.dart
→ KIZÁRÓLAG PracticeObservation/ChordObservation.confidence (megfigyelésenként)
```

A `PracticeHistoryEntry`-nek **nincs** session-szintű `confidence` mezője, és a
`PracticeMetricSnapshot` sem hordoz ilyet. A 0,45 / 0,60 / 0,85 bemenetek tehát
a mai fán **nem előállíthatók**, a domain bővítése pedig a §3 szerint tilos
(és az R6 után a listán kívül is esik).

**A mért, létező bizonyíték-erősség a lefedettségi arány**, két meglévő mezőből:

```dart
final class PracticeHistoryEntry {
  final int totalTargets;      // hány célt tűzött ki a session
  final int resolvedTargets;   // hányat oldott fel a felismerés
}
```

A megbízhatóság ezért `resolvedTargets / totalTargets`, a küszöb az ADR 0283
§Döntés 1 szerinti **0,60, inkluzív határral**. A három cella bemenete
`python3 -c` -vel kiszámolva:

```
9 / 20 = 0.45 | >=0.60: False
12 / 20 = 0.6 | >=0.60: True
17 / 20 = 0.85 | >=0.60: True
```

**A számítás a presentation rétegben tiszta függvény**, és ez NEM ütközik az
ADR 0283 §Döntés 4-gyel: az tiltás a **jutalomra** vonatkozik (ott a főkönyv az
igazságforrás), nem egy már mért domain-arány megjelenítésére.

### R9 — a golden-sáv a MERGE-KAPU architektúráján fut (ADR 0426)

A §7 eredeti sora (`~/flutter/bin/flutter test --update-goldens`) **ARM-pixelt**
rögzítene, amit a x86-os CI nulla toleranciával pirosra vált — pontosan ez
állította meg az E13-R20-at **H5**-tel ([L493](../LESSONS.md#l493)). A kör a
merge-elt `tools/golden-x86.sh`-t használja (`record` + kötelező `check`), és a
golden-cella **nincs** a lokális `round-gate.sh` sorban.

### R10 — a képernyő-leltár egzakt száma 84 → a kör tényleges száma

```
find lib/features -name '*_screen.dart' | wc -l   → 84
test/ui/ui_inventory_test.dart                    → expect(first.screenPaths, hasLength(84));
```

A kör két ÚJ képernyőt hoz (előzmények, Speed Builder), tehát a szám **86**-ra
mozdul. A jogosultság PONTOSAN a szám emelése a TÉNYLEGES értékre; a
leltárteszt minden más állítása érintetlen marad
([L397](../LESSONS.md#l397), [L465](../LESSONS.md#l465)).

### R11 — az útvonal-regisztráció és a Hub-belépő NEM fér a körbe: nevesített follow-up

```
grep -n "practiceHistory\|speedBuilder" lib/app/routing/app_route.dart → (üres)
```

Az SDD UI-22/UI-23 `/practice/history` és `/practice/speed-builder` útvonalat ír
elő, a regisztráció viszont a `lib/app/routing/**`-ban élne, ami a listán
KÍVÜL van (**H3**). A Hub-belépő szintén zárt: a
`practice_hub_screen.dart:13` doc-commentje kimondja, hogy a Continue/Recent
blokk **szándékosan hiányzik**, és ezt a listán kívüli
`practice_hub_screen_test.dart` A3 cellája pinneli.

**Feloldás — a fán MÉRT házi minta.** Az elérhetőség a repó bevett,
route-mentes mintájával készül, amit három feature már használ:

```
lib/features/songs/screens/song_list_screen.dart:39
lib/features/library/screens/session_detail_screen.dart:126
lib/features/analyze/screens/analyze_screen.dart:299
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => …))
```

A két új képernyő tehát az **eredmény-felületről** érhető el (előzmények-link,
illetve a következő-lépés akció), ami a kör saját, engedélyezett fájlja. A
nevesített route-ok és a Hub-belépő egy KÉSŐBBI kör dolga — ezt a §10
handoffban ki kell mondani. Ez a kör terméki szűkítése, nyíltan vállalva.

### R12 — az A8 megosztás-célja a listán kívül van → a cella a HASZNOS TEHERRE szűkül

```
grep -rn "share" lib/app/routing/app_route.dart          → (üres: nincs megosztás-route)
lib/features/share/screens/share_preview_screen.dart     → AnalyzeResult-ot vár
lib/features/community/application/mappers/practice_share_mapper.dart
    → PracticeSessionResult-ot vár, és a community/public.dart NEM exportálja
```

A meglévő megosztás-varratok bemenete tehát vagy egy másik feature belső
típusa, vagy egy nem exportált mapper — mindkettő a listán kívüli fájl
módosítását kívánná. Az A8 ezért a **mérhető részre szűkül**: a megosztás-akció
egy MINIMÁLIS, kézzel válogatott vetületet ad át (session-azonosító, cím,
mód, időpont, összegző mérőszám), és a nyers `PracticeHistoryEntry`-t,
a per-attempt részleteket és bármilyen fiók-/személyes adatot **NEM** — a
cella a hiányt is állítja (`findsNothing` / abszencia-állítás). A tényleges
Community-composer bekötése a `practiceSummaryFromSessionResult` varraton át
ugyanaz a nevesített follow-up, mint az R11.

## 0. Kör-jelzés és STOP-protokoll

```bash
tools/codex-signal.sh progress "<egy sor>"
tools/codex-signal.sh done "<egy sor>"
tools/codex-signal.sh stopped "<egy sor>"
tools/codex-signal.sh blocked "<egy sor>"
```

Lezáró jelzés nélkül a kör bukott. Listán kívüli fájl → `stopped`.

## 1. Cél

Az UI-21–UI-23 (eredmény, előzmények, tempó-progresszió) **összegzés-központú**
felületei (SDD Ch13 Kör 22).

## 2. Jelenlegi állapot — mért tények

- Az R12 mérőszám- és insight-kártyái, az R10 állapotai készen állnak.
- Az R21 lezárta a session-t; ez a kör mutatja meg az eredményét.
- A jutalom-főkönyv **idempotens** réteg — az összegzés onnan jön.

**A pre-flightban ÚJRAMÉRVE (`main @ cf73bdf2`) — a §5.4 kötelező mérése:**

| Mért tény | Hol |
|---|---|
| `RewardLedgerRepository` — `appendIfAbsent` / `hasProcessedEvent(sourceEventId)` / `readPage({limit, cursor})` | `lib/features/gamification/data/reward_ledger_repository.dart` |
| a főkönyv és a bejegyzés a `gamification/public.dart`-on át elérhető (`export 'data/reward_ledger_repository.dart'`, `export 'domain/rewards/reward_ledger_entry.dart'`) | `lib/features/gamification/public.dart:46,51` |
| `RewardLedgerEntry` — `sourceEventId`, `baseXp`, `bonusXp`, `totalXp` (`totalXp == baseXp + bonusXp` kikényszerítve) | `lib/features/gamification/domain/rewards/reward_ledger_entry.dart` |
| a session→esemény kulcs **determinisztikus**: `GamificationPracticeAdapter.stableEventId(sessionId)` — az eredmény újranyitása UGYANAZT az eventId-t adja (ADR 0390 §4) | `lib/features/practice/application/gamification_practice_adapter.dart:194` |

A réteg tehát megvan — a `blocked`-feltétel NEM áll fenn. Az eredmény-felület a
`stableEventId(entry.id)` kulccsal olvassa ki a főkönyvből a jutalmat, és
**semmit nem számol** belőle.

**Ami a fán NINCS meg** (a cellák ezért szűkültek): session-szintű
`confidence` mező (§0.0/B/R8), `/practice/history` és `/practice/speed-builder`
route (§0.0/B/R11), practice-oldali megosztás-varrat (§0.0/B/R12).

## 3. Scope

**Benne van:** az eredmény mérőszám / insight / következő lépés elrendezése
**confidence-tudatosan** · az előzmények szűrhető, **sérült rekordot izoláló**
listája · a Speed Builder beállítás / aktív / eredmény elrendezése · megosztás,
tutor és korrekció route-leképezés · a jutalom-összegzés a **főkönyvből** ·
elégtelen jel, részleges session és offline sync állapotok.

**NINCS benne (tilos):** a pontozás vagy a jutalom-logika módosítása · a
jutalom UI-oldali **számítása** · más képernyők migrációja · `docs/adr/**`,
`tools/**`, `.github/**`.

## 4. Engedélyezett fájlok

| Útvonal | Indok |
|---|---|
| `lib/features/practice/presentation/` | a három felület (eredmény HELYBEN migrálva, előzmények + Speed Builder új képernyő) — §0.0/B/R6 |
| `lib/features/practice/public.dart` | az új képernyők barrel-exportja, a meglévő sorrend és tartalom megőrzésével |
| `lib/l10n/base/app_{en,hu}.arb` | **FORRÁS** — az eredmény-szövegek (a kör feature-ei még nem migráltak, a kulcsaik itt élnek) |
| `lib/l10n/app_{en,hu}.arb` | **CSAK GENERÁLT KIMENET** — kizárólag `dart run tool/gen_l10n_segments.dart --write`, kézzel írni TILOS |
| `test/features/practice/*_test.dart` (4) | a §6 cellái |
| `test/ui/goldens/` | az A9 golden-teszt + a felvett PNG-k |
| `test/ui/ui_inventory_test.dart` | **repó-szintű képernyő-leltár őr** — a kör két ÚJ `lib/features/**/*_screen.dart`-ot hoz, ezért az egzakt `hasLength(84)` **86**-ra mozdul; a jogosultság PONTOSAN a szám emelése, más állítás nem érinthető (§0.0/R4 + §0.0/B/R10) |
| `docs/rounds/e13-r22-…md` | a §10 handoff |

**Tilos zóna:** `lib/features/practice/{domain,data,application}/**` (OLVASHATÓ,
nem írható — §0.0/B/R6) · `lib/features/**` a practice presentation
KIVÉTELÉVEL · `lib/app/routing/**` (§0.0/B/R11) ·
`lib/core/design_system/**` · `lib/core/theme/**` · `docs/adr/**` ·
`docs/sdd/**` · `tools/**` · `.github/**`.

## 5. Kötött architekturális döntések (ADR 0283)

### 5.1 Az alacsony megbízhatóságú eredmény NEM kategorikus

Ha a felismerés bizonytalan volt, az eredmény ezt **kimondja**, és nem közöl
pontos százalékot ítéletként. A bizonytalanság a felületen is bizonytalanság
marad.

**NEM elfogadható gyengítés:** „78%" kiírása gyenge jel mellett is, mert „így
egységesebb". Az a mérés hitelét adja fel a látszatért.

### 5.2 A sérült rekord IZOLÁLT, nem omlasztja a listát

Egyetlen olvashatatlan előzmény-rekord nem viheti magával az egész képernyőt —
a sor hibásként jelenik meg, a többi elérhető marad.

### 5.3 Az előzmények OFFLINE elérhetők

Helyi adat. Hálózat nélkül is látszik.

### 5.4 A jutalom a FŐKÖNYVBŐL jön, nem UI-számításból

Az eredmény újranyitása nem adhat újabb jutalmat. Az idempotencia forrása a
főkönyv; a felület csak megjelenít.

**NEM elfogadható gyengítés:** a jutalom kiszámítása a képernyőn a session
adataiból. Újranyitáskor duplikálódik.

### 5.5 A Speed Builder a STABIL legjobb tempót mutatja

Egyetlen szerencsés futam nem „legjobb". A stabilitás definíciója a domainé; a
felület azt jeleníti meg, amit kap.

### 5.6 A következő lépés VÉGREHAJTHATÓ

Nem tanács, hanem gomb: elindítja a javasolt gyakorlatot a helyes
paraméterezéssel.

## 6. Acceptance criteria

| # | Kritérium | Bizonyíték |
|---|---|---|
| A1 | Alacsony megbízhatóságnál (`resolvedTargets/totalTargets < 0,60`) az eredmény nem kategorikus | `result_confidence_test.dart` |
| A2 | Részleges session eredménye részlegesként jelenik meg (`PracticeFinishReason` a `finishReasonCode`-ból) | ugyanott |
| A3 | Sérült előzmény-rekord izolált, a lista működik | `history_corrupt_record_test.dart` |
| A4 | Az előzmények offline elérhetők (helyi repository, hálózat nélkül) | ugyanott |
| A5 | A jutalom a főkönyvből jön, és újranyitáskor NEM duplikálódik | `reward_idempotency_test.dart` |
| A6 | A Speed Builder a stabil legjobb tempót (`highestStableTempo`) mutatja, nem a csúcs-futamot | `speed_ladder_test.dart` |
| A7 | A következő lépés végrehajtható és helyesen paraméterez | `result_confidence_test.dart` |
| A8 | A megosztás-akció MINIMÁLIS vetületet ad át, nyers rekordot/személyes adatot nem (§0.0/B/R12) | ugyanott |
| A10 | A `PracticeResultScreen` típusneve, útvonala és `entry:` konstruktora változatlan; a három meglévő pin zöld (§0.0/B/R7) | `test/features/practice/presentation/` + `test/core/screen_size_guard_test.dart` |
| A9 | A kör §3-ban megnevezett MINDEN képernyőről golden-felvétel készül és be van commitolva — 412×915 compact portrait ÉS `textScaleFactor: 2.0` | `e13_r22_screens_golden_test.dart` + a `test/ui/goldens/*.png` a diffben |

### 6.1 Mérce-mátrix — melyik hibás implementációt melyik cella fogja pirosra

| Hibás implementáció | Melyik cella vált PIROSRA |
|---|---|
| Pontos százalék gyenge jel mellett | **A1** |
| A részleges session teljesként jelenik meg | A2 |
| Egy sérült rekord kiüti a listát | **A3** |
| A jutalom a képernyőn számolva | **A5** |
| A csúcs-futam „legjobb"-ként | A6 |
| A következő lépés csak szöveges tanács | A7 |
| A képernyő elcsúszik, túlcsordul vagy nagy szövegméretnél olvashatatlan | **A9** |

**Az eredmény-megbízhatóság három kötelező cellája** (a küszöb: **0,60**, az
ADR 0281 §2-vel egyező, INKLUZÍV határ). A bemenet a `PracticeHistoryEntry`
két MÉRT mezőjéből számolt lefedettségi arány, `resolvedTargets / totalTargets`
(§0.0/B/R8 — session-szintű `confidence` mező a fán NINCS):

| Cella | Bemenet (`resolvedTargets` / `totalTargets`) | Arány | Elvárt |
|---|---|---|---|
| a küszöb alatt | 9 / 20 | **0,45** | **nem kategorikus** — tartomány + magyarázat, nincs pontszám-ítélet |
| rajta (a küszöbön) | 12 / 20 | **0,60** | kategorikus eredmény megengedett (a határ inkluzív) |
| a küszöb fölött | 17 / 20 | **0,85** | kategorikus eredmény |

Az arányokat `python3 -c` számolta ki, nem becslés:

```
9 / 20 = 0.45 | >=0.60: False
12 / 20 = 0.6 | >=0.60: True
17 / 20 = 0.85 | >=0.60: True
```

**A `12/20` cella a falszifikációs él:** egy `>` (szigorú) összehasonlítás
pontosan ezt a cellát váltja pirosra, egy `>=` (inkluzív) zölden hagyja.

**Valódi-sértés próba (KÖTELEZŐ, §10-ben dokumentálva):** számold ki a jutalmat
a képernyőn a főkönyv helyett → az **A5** cellának PIROSNAK kell lennie →
állítsd vissza.

## 7. Kötelező ellenőrzések

```bash
tools/round-gate.sh test/features/practice/result_confidence_test.dart test/features/practice/history_corrupt_record_test.dart test/features/practice/speed_ladder_test.dart test/features/practice/reward_idempotency_test.dart test/features/practice/presentation/ test/core/screen_size_guard_test.dart test/ui/ui_inventory_test.dart test/core/architecture_dependency_test.dart test/tooling/dio_factory_guard_test.dart test/tooling/preferences_plugin_import_guard_test.dart test/tooling/route_literal_guard_test.dart
```

**A golden-felvétel (A9) rögzítése — a mérce ÚJ, nem alku tárgya:** a képernyő
minden állapotát NEM kell felvenni, a §3 szerinti alap-nézet elég, de a két
keret (412×915 compact portrait és ugyanaz `textScaleFactor: 2.0` mellett)
KÖTELEZŐ. Minta és futó precedens: `test/features/live/chord_timeline_golden_test.dart`
(valódi kapu, nem `skip`-elt rögzítő). Előállítás:

```bash
tools/golden-x86.sh record test/ui/goldens/e13_r22_screens_golden_test.dart
tools/golden-x86.sh check  test/ui/goldens/e13_r22_screens_golden_test.dart
```

**A felvétel x86-on történik, nem ezen a boxon** (§0.0/B/R9, ADR 0426): a
`~/flutter/bin/flutter test --update-goldens` ARM-pixelt rögzítene, amit a CI
nulla toleranciával pirosra vált — pontosan ez állította meg az E13-R20-at
H5-tel. A `check` a felvétel után KÖTELEZŐ, és a `tools/round-gate.sh` MELLETT
fut (nem helyette); a golden-cella ezért nincs a fenti gate-sorban.

A keletkezett PNG-ket **commitolni kell** — enélkül az A9 nem teljesült. A
márkabetűtípusok a teszt-hostban nem töltődnek be (fallback face); ez a
meglévő golden-teszt mért viselkedése, az elrendezést, méretezést és színeket
nem érinti. MIÉRT ez a kör dolga és nem az E13-R36-é: a záró vizuális
regressziós kör csak azt tudja megmondani, hogy valami MEGVÁLTOZOTT — azt,
hogy a képernyő eleve csúnya-e, a saját körében kell látni.

Külön processzek, csonkítatlan kimenet. **Tilos** `| tail`, `| head`,
`&&`-lánc vagy bármilyen szűrés (L09); a `flutter analyze` és `flutter test`
kézi láncolása OOM-ot ad (L05). A kötelező gate-et **TILOS háttérbe küldeni**
(`run_in_background`) — az egy-fordulós harness a forduló végén megöli (L254).

## 8. Implementációs sorrend

1. Az eredmény-felület + a megbízhatóság három cellája.
2. A részleges session és az elégtelen jel állapota.
3. Az előzmények listája, sérült rekord izolálásával, offline.
4. A jutalom-összegzés a főkönyvből + az idempotencia-cella.
5. A Speed Builder három felülete + a stabil legjobb tempó.
6. A következő lépés végrehajtható akciója + a megosztás minimális vetülete
   (§0.0/B/R12).
7. Elérhetőség az eredmény-felületről `Navigator.push(MaterialPageRoute…)`-sal
   (§0.0/B/R11), a két új képernyő exportja a `public.dart`-ba, és a
   `test/ui/ui_inventory_test.dart` `hasLength(84)` → **a tényleges szám**
   (§0.0/B/R10).
8. A valódi-sértés próba, §10-be dokumentálva.
9. `tools/round-gate.sh` a §7 szerint, majd a golden-sáv
   `tools/golden-x86.sh record` + `check`.

## 9. Kockázatok

- **A kategorikus pontszám.** Egységesnek látszik, és bizonytalan mérésre
  ítéletet mond — a termék hitelét viszi (A1).
- **A UI-oldali jutalom.** Kényelmes, és minden újranyitáskor duplikál (A5).
- **A sérült rekord.** Ritka, és ha kiüti a listát, az összes előzmény
  elérhetetlen lesz (A3).

## 10. Implementation handoff — az implementer tölti ki

### 10.1 Acceptance → bizonyíték

| # | Kritérium | Bizonyíték (cella) |
|---|---|---|
| A1 | Alacsony megbízhatóság (`<0,60`) → nem kategorikus | `result_confidence_test.dart` — `A1` csoport, 3 cella: 9/20=0,45 (piros lenne, low-confidence banner, nulla `%`), 12/20=0,60 (kategorikus, INKLUZÍV határ), 17/20=0,85 (kategorikus) |
| A2 | Részleges session `finishReasonCode`-ból | `result_confidence_test.dart` — `A2` csoport: `completedAllTargets` → nincs badge, `interrupted`/`userFinished` → `practiceResultPartialBadge` látszik |
| A3 | Sérült rekord izolált, a lista működik | `history_corrupt_record_test.dart` — `A3` csoport, valódi `LocalPracticeHistoryRepository` + kevert jó/sérült JSON envelope; 2/2 jó rekord renderelődik, a sérült nem dob kivételt |
| A4 | Előzmények offline elérhetők | `history_corrupt_record_test.dart` — `A4` csoport: a `ProviderScope` KIZÁRÓLAG a `keyValueStoreProvider`-t írja felül (nincs hálózati provider), a képernyő így is teljes |
| A5 | Jutalom a főkönyvből, nem duplikálódik | `reward_idempotency_test.dart` — mindhárom teszt: van/nincs bejegyzés, majd kétszeri megnyitás → azonos `totalXp`, `appendCallCount == 0` |
| A6 | Speed Builder a stabil legjobb tempót mutatja | `speed_ladder_test.dart` — `A6` csoport: egy egyszeri magas (150 BPM) áthaladás SOSEM "legjobb"; csak a kétszeres egymást követő áthaladással elért 110 BPM az |
| A7 | Végrehajtható, helyesen paraméterezett következő lépés | `result_confidence_test.dart` — `A7` csoport: a "Practice again" gomb megnyitja a `PracticeSetupScreen`-t UGYANAZZAL a `definitionId`-vel |
| A8 | Megosztás — minimális vetület | `result_confidence_test.dart` — `A8` csoport: a felnyitott kártya tartalmazza a session-azonosítót/címet/módot/időpontot/összegző mérőszámot, de a `skillTags` string SOHA nem jelenik meg (`findsNothing`) |
| A9 | Golden — mindhárom képernyő, 412×915 + textScaler 2.0 | `test/ui/goldens/e13_r22_screens_golden_test.dart` + 6 PNG a `test/ui/goldens/goldens/` alatt |
| A10 | `PracticeResultScreen` típusa/útvonala/`entry:` változatlan, a 3 pin zöld | `test/features/practice/presentation/practice_result_screen_test.dart`, `practice_a11y_audit_test.dart`, `test/core/screen_size_guard_test.dart` — mind zöld a záró gate-ben |

### 10.2 Valódi-sértés próba (A5, §6.1 KÖTELEZŐ)

A `practiceRewardForSessionProvider`-t ideiglenesen átírtam, hogy a
főkönyv helyett egy kitalált (`totalXp: 999`) bejegyzést adjon vissza
minden sessionre, majd lefuttattam a `reward_idempotency_test.dart`-ot:

```
00:01 +0 -1: no ledger entry for this session renders "no reward" — never an estimated number
  Expected: exactly one matching candidate
    Actual: _TextWidgetFinder:<Found 0 widgets with text
    "No reward recorded yet for this session": []>
00:02 +0 -3: A5 — reopening the SAME result twice reads the identical reward…
  Expected: exactly one matching candidate
    Actual: _TextWidgetFinder:<Found 0 widgets with text "+40 XP": []>
Some tests failed. (mindhárom teszt piros lett)
```

A cella tehát a mércének megfelelően PIROSRA vált a tiltott
implementációra. Ezután visszaálltam az eredeti (főkönyvet olvasó)
kódra, és a teszt újra zöld:

```
00:01 +3: All tests passed!
```

### 10.3 A záró gate és a golden-sáv tényleges kimenete

`tools/round-gate.sh` a brief §7 pontos parancsával, a végleges (commitolt)
állapoton, csonkítatlanul:

```
═══ Gate-összegzés
    format                                                     zöld
    analyze                                                    zöld
    test test/features/practice/result_confidence_test.dart    zöld
    test test/features/practice/history_corrupt_record_test.dart zöld
    test test/features/practice/speed_ladder_test.dart         zöld
    test test/features/practice/reward_idempotency_test.dart   zöld
    test test/features/practice/presentation/                  zöld
    test test/core/screen_size_guard_test.dart                 zöld
    test test/ui/ui_inventory_test.dart                        zöld
    test test/core/architecture_dependency_test.dart           zöld
    test test/tooling/dio_factory_guard_test.dart              zöld
    test test/tooling/preferences_plugin_import_guard_test.dart zöld
    test test/tooling/route_literal_guard_test.dart            zöld
    architecture                                               zöld
    secrets                                                    zöld
    l10n                                                       zöld

MINDEN GATE ZÖLD.
```

Golden-sáv (`tools/golden-x86.sh`, x86_64/qemu, ADR 0426):

```
$ tools/golden-x86.sh record test/ui/goldens/e13_r22_screens_golden_test.dart
00:00 +0: practice result — compact
00:27 +1: practice history — compact
00:36 +2: speed builder — active — compact
00:39 +3: practice result — compact_scale2
00:40 +4: practice history — compact_scale2
00:42 +5: speed builder — active — compact_scale2
00:43 +6: All tests passed!

$ tools/golden-x86.sh check test/ui/goldens/e13_r22_screens_golden_test.dart
00:00 +0: practice result — compact
… (mind a 6 cella)
00:48 +6: All tests passed!
```

A felvétel során a Speed Builder aktív rétege `textScaler: 2.0` mellett
73 pixellel túlcsordult (`RenderFlex overflowed`) — VALÓS lelet, nem a
mérce hibája. Javítás: a `SpeedBuilderScreen` törzse `SingleChildScrollView`-ba
került (korábban sima `Padding` volt); a felvétel utána tiszta.

### 10.4 A `test/ui/ui_inventory_test.dart` száma és az R7 pin-ek

A leltárteszt `hasLength(84)` → **`hasLength(86)`** — pontosan a két új
`_screen.dart` (`practice_history_screen.dart`, `speed_builder_screen.dart`)
miatt; a teszt egyetlen más állítását nem érintettem.

Az R7 három, a listán KÍVÜLI pin — `practice_result_screen_test.dart`,
`practice_a11y_audit_test.dart`, `test/core/screen_size_guard_test.dart`
(`PracticeResultScreen`-re állítva) — mind ZÖLD maradt a záró gate-ben:
a `PracticeResultScreen` típusneve, fájl-útvonala és `entry:` konstruktora
változatlan, a migráció kizárólag HOZZÁADOTT (megbízhatóság-sáv,
jutalom, next-step, share, quick-link).

### 10.5 Ami NEM készült el (nevesített follow-up, §0.0/B/R11 és R12)

- **Nincs `/practice/history` és `/practice/speed-builder` névvel
  regisztrált route.** A két új képernyő KIZÁRÓLAG a
  `PracticeResultScreen`-ről érhető el
  (`Navigator.of(context).push(MaterialPageRoute…)`), a `lib/app/routing/**`
  ezen a körön kívül maradt. A névvel ellátott route-ok és a
  `practice_hub_screen.dart` Continue/Recent belépője egy KÉSŐBBI kör
  dolga (a Hub-képernyő doc-commentje ezt a hiányt már ma is kimondja).
- **Nincs valódi Community-share bekötés.** Az A8 megosztás-gombja a
  minimális vetületet CSAK egy in-screen kártyán jeleníti meg; a
  `lib/features/share/**` / `lib/features/community/**` felé egy
  `practiceSummaryFromSessionResult`-szerű varrat egy KÉSŐBBI kör dolga
  (§0.0/B/R12).
- **A Speed Builder "aktív" fázisa szintetikus próbákkal demózik.** A
  `domain/service/speed_builder_engine.dart` a valódi állapotgép; mivel
  az `application`-réteg (élő session-controller, felismerés) ezen a
  körön KÍVÜL van, az aktív fázis "Record pass"/"Record miss" gombokkal
  szimulált próbákat küld az engine-nek. A ténylegesen élő
  (mikrofon-vezérelt) Speed Builder session-bekötés egy KÉSŐBBI kör
  dolga.
- **A jutalom-főkönyv seam Noop-alapértelmezésű.** A
  `rewardLedgerRepositoryProvider` production-alapértelmezése egy üres
  (mindig "nincs jutalom") implementáció — ez MA a valós állapot, mert a
  `GamificationDualWriteMode` alapértelmezése `off`, tehát a főkönyv MA
  sehol nem kap valódi írást. Amikor egy későbbi kör bekapcsolja a
  dual-write-ot és vezényli a valódi `LocalRewardLedgerRepository`-t a
  kompozíciós gyökérbe, ez a provider felülíródik — a screen kódja nem
  változik.

## 11. Review — a Claude tölti ki
