# E15-R03 — Review (Claude / Opus 5, orchestrátor-reviewer)

- **Kör:** `E15-R03` — Elérhetőségi audit és az örökség-képernyők visszavonási terve
- **Ág:** `sonnet-impl/e15-r03-legacy-reachability-audit-and-retirement`
- **Review-zott commit:** `cbcd6e08` (implementáció) a `a4be396c` (pre-flight) fölött
- **Implementer motor:** `sonnet-impl` (Claude Sonnet 5, `--effort high`)
- **ADR:** [`0471`](../adr/0471-screen-reachability-is-measured-not-assumed.md)
- **Review dátuma:** 2026-08-29
- **Módszer:** read-only review izolált `/tmp/ss-review-e15-r03` klónban, saját
  gate-futtatással és eldobható próbatesztekkel. A review NEM módosított
  production fájlt.

## 1. Verdikt

### VÉGSŐ DÖNTÉS: APPROVED (a második javító kör után, `1929e971`)

| Fázis | Commit | Verdikt |
|---|---|---|
| Első review | `cbcd6e08` | CHANGES REQUESTED — MAJOR-1 (tautológ A4-próba) |
| 1. javító kör | `5c938294` | **MAJOR-1 ZÁRVA**, mérve |
| Második review-menet | `8d5cc3d1` | CHANGES REQUESTED — MAJOR-2 (négyzetes I/O, mért CI-destabilizálás) |
| 2. javító kör | `1929e971` | **MAJOR-2 ZÁRVA**, mérve (byte-azonos kimenet, ~31× gyorsulás) |

A két NOTE elfogadott, nem igényel javítást.
Nyitott BLOCKER/MAJOR/MINOR: **nincs**.

---

Az alábbi szakaszok a review menetét rögzítik (a leletek dokumentálása miatt
változatlanul), leletenként a lezárással kiegészítve. A §2 mérései az első
menetből valók (`cbcd6e08`); a §3 lezáró blokkjai a javított commitokon
készültek.

A kör érdemi tartalma (a mérő, a terv, a dokumentum-frissítések) **mért,
helyes és a szerződésnek megfelelő**. A két MAJOR egyike sem a mérés
TARTALMÁT érintette: az egyik egy magát falszifikációs próbának nevező
tautológia (dekoráció a mérce-rendszerben), a másik a mérő négyzetes I/O-ja,
ami a CI-t is destabilizálta. A `96/68/28/25` mérés és a terv mindkét javítás
után változatlan — az utóbbinál bizonyítottan byte-azonosan.

## 2. Amit a review MAGA mért (nem bemondás)

### 2.1 Scope-audit — TISZTA

```
python3 tools/scope-audit.py --repo /home/ubuntu/ss-sonnet-impl-e15-r03 \
  --brief docs/rounds/e15-r03-legacy-reachability-audit-and-retirement.md --base a4be396c
→ Legacy scope audit OK (a4be396c32a2..cbcd6e08f97d, 6 changed path(s), 0 generated/ignored)
```

A hat fájl mind a brief §4 engedélyezett listáján van. A tilos zóna sértetlen:

```
git diff --name-only a4be396c cbcd6e08 | grep -c '^lib/'   → 0
git diff a4be396c cbcd6e08 -- test/ui/ui_inventory_test.dart | wc -l   → 0
```

**A5 TELJESÜL:** a `ui_inventory_test.dart` egzakt `hasLength(96)` értéke
érintetlen; a kör nem hozott és nem vitt képernyőt.

### 2.2 Saját gate-futtatás izolált klónban — MIND ZÖLD

```
tools/round-gate.sh test/tooling/screen_reachability_test.dart test/ui/ui_inventory_test.dart
```

```
    format                                                     zöld
    analyze                                                    zöld
    test test/tooling/screen_reachability_test.dart            zöld
    test test/ui/ui_inventory_test.dart                        zöld
    architecture                                               zöld
    secrets                                                    zöld
    l10n                                                       zöld

MINDEN GATE ZÖLD.
```

Ez FÜGGETLEN futás egy friss `/tmp` klónban — nem az implementer kimenetének
elfogadása. Az implementer §10.3 állítását megerősíti.

### 2.3 A mért számok reprodukálva

```
dart run tool/check_screen_reachability.dart --format table
→ Measured screens: 96. Reachable: 68. Unreachable: 28. Flag-gated: 25.
```

Karakterre egyezik a §10.2-vel és a `retirement-plan.md` §2-vel. A terv
számtana is zár: 53 legacy közül **41 elérhető** = 35 `migrate` + 6 `retire`,
és a §4 kör-hozzárendelés pontosan 35-öt oszt szét
(R05:5 + R06:5 + R07:5 + R08:5 + R09:8 + R10:4 + R11:3 = 35), a 6 `retire` az
`E15-R04`-hez tartozik. **A6 és D6 teljesül.**

## 3. Leletek

### MAJOR-1 — Az A4 „kötelező valódi-sértés próbája" TAUTOLÓGIA: zöld marad akkor is, ha az általa igazolni hivatott őrt teljesen kiütöm

**Hol:** `test/tooling/screen_reachability_test.dart:323–332`

```dart
// The KÖTELEZŐ valódi-sértés próba for A4: a retire row with the
// successor blanked out must be rejected by the same assertion shape
// used above — proving the check is not vacuously true.
test('a retire row with its successor blanked out is rejected', () {
  final mutated = _PlanRow(
    screenPath: 'lib/features/fixture/screens/fixture_screen.dart',
    verdict: 'retire',
    ownerRound: 'E15-R04',
    successor: '—',
    reason: 'Some reason.',
  );
  expect(mutated.successor, anyOf(isEmpty, '—'));
});
```

A teszt egy helyben megírt literált (`successor: '—'`) hasonlít önmagához.
**Nem hívja meg** sem a `_parsePlanRows`-t, sem a valós
`docs/ui/retirement-plan.md`-t, sem az A4 tényleges állítás-logikáját. A
komment állítása („proving the check is not vacuously true") ezért hamis: épp
ez a cella az, ami vákuumosan igaz.

**Eldobható próbateszttel MÉRVE** (izolált klón, `/tmp/ss-review-e15-r03`).
Kiütöttem a VALÓDI A4 állítást:

```dart
expect(row.successor, anything);  // DELIBERATELY BROKEN PROBE
```

majd lefuttattam KIZÁRÓLAG a „próbát":

```
flutter test test/tooling/screen_reachability_test.dart \
  --plain-name "a retire row with its successor blanked out is rejected"
→ 00:00 +1: All tests passed!
```

**Az őr teljesen halott volt, a „falszifikációs próba" mégis zöld.** Egy olyan
mérce, amit semmi nem futtat és semmi nem őriz, dekoráció, nem kapu — ezt a
kör SAJÁT `docs/ui/legacy-backlog.md`-je mondja ki („A measure nothing runs and
nothing guards is a decoration, not a gate"), és az AGENTS.md/round-brief
tanulság-átvitel is ezt tiltja.

**Kontraszt — az A3 próbája HELYES.** Az `screen_reachability_test.dart:263–293`
a valós, mért plan-sorok egy MÁSOLATÁN üti ki az owner-roundot, majd
ÚJRAFUTTATJA a tényleges ellenőrző hurkot. Ez valódi próba. Az A4-nek ugyanezt
az alakot kell követnie.

**Fontos, hogy mit NEM állítok:** a VALÓDI A4 cella
(`screen_reachability_test.dart:298–318`) **jó őr**. Ezt is megmértem — a valós
tervben kiürítettem egy `retire` sor successor-celláját:

```
flutter test ... --plain-name "no retire row has an empty successor or a trivial reason"
→ 00:00 +0 -1: Some tests failed.
  test/tooling/screen_reachability_test.dart 307:9  main.<fn>.<fn>
```

Tehát az **A4 acceptance-cella teljesül**; a defekt kizárólag a mellé tett,
magát próbának nevező tautológia.

**Javítás (a javító kör dolga):** a `:323–332` teszt vagy kövesse az A3-próba
alakját — a valós `_parsePlanRows(...)` sorok egy másolatában ürítsd ki egy
`retire` sor successorát, majd futtasd rá UGYANAZT az állítás-hurkot, amit a
`:298–318` használ, és várd el, hogy pontosan azt az egy sort kifogásolja —,
vagy ha ez nem gazdaságos, TÖRÖLD a tesztet és a hozzá tartozó, valótlan
kommentet (az A4 kötelező valódi-sértés próbája a §10.4-ben kézzel amúgy is
dokumentálva van). **Amit tilos:** a komment megtartása a tautológia mellett.

#### Javítás-ellenőrzés (`5c938294`) — **MAJOR-1 ZÁRVA**

Az implementer az **(a)** utat választotta, és a lényegi pontot eltalálta: a
két hely mostantól **bizonyíthatóan ugyanazt a logikát futtatja** egy közös
helperen keresztül (`_retireRowsMissingSuccessorOrReason`,
`screen_reachability_test.dart:70–79`). A próba (`:337–350`) a VALÓS,
mért `retire` sorok egy MÁSOLATÁBAN üríti ki az egyik successort, és pontosan
azt az egy sort várja vissza — nem csak azt, hogy „valami hibás".

**A review ÚJRA lefuttatta a saját, eldobható próbáját** a javított
`5c938294`-en: kiütöttem a közös helper testét
(`if (false) failing.add(row.screenPath);`), majd futtattam KIZÁRÓLAG a
próbatesztet:

```
flutter test test/tooling/screen_reachability_test.dart \
  --plain-name "blanking one real retire row"
→ 00:00 +0 -1: Some tests failed.
  test/tooling/screen_reachability_test.dart 349:7  main.<fn>.<fn>
  Failing: A4 … blanking one real retire row's successor turns this cell red
```

**Most PIROS** — pontosan az ellentéte a lelet előtti viselkedésnek (ott a
kiütött őr mellett is `+1: All tests passed!` volt). A próba tehát valóban a
mércét méri. A helper testét visszaállítottam, a klón tiszta
(`git status --short` üres).

**Nem gyengült a valódi cella sem:** a `:311–319` továbbra is a valós tervet
parse-olja, `expect(retireRows, isNotEmpty)` guarddal, ugyanazon a helperen.

### MAJOR-2 — A mérő négyzetes I/O-ja: `render()` képernyőnként ÚJRAOLVASTA az egész fát (a CI-t is destabilizálta) — **ZÁRVA (`1929e971`)**

**Hol (a lelet idején):** `tool/check_screen_reachability.dart`, `render()`
hurka (`8d5cc3d1:242–294`).

A hurkok sorrendje `O(képernyők × fájlok)` olvasást adott: mind a 96 képernyőre
végigolvasta az ÖSSZES `lib/` és `test/` fájlt. A helyes alak `O(fájlok)` —
minden fájlt egyszer, soronként mind a 96 osztálynévre nézve.

**MÉRVE (a review futtatta, izolált klónban, `8d5cc3d1`):**

```
time flutter test test/tooling/screen_reachability_test.dart
→ 02:56 +9: All tests passed!
   real 3m0.848s   user 2m47.740s   sys 0m13.148s
```

**Miért MAJOR és nem NOTE — mért CI-hatás.** A kör ELSŐ CI-futása
([`33223102444`](https://github.com/wolfcasaba/strumsight/actions/runs/33223102444),
`cbcd6e08`) PIROS lett, egy olyan teszten, amit ez a kör **nem érintett**:

```
❌ test/features/songs/import/import_flow_test.dart:83
   A2: cancelling a confirmed import cleans the opened workspace
   Expected: non-empty   Actual: []
```

Az a cella `pumpEventQueue()` után várja el, hogy a workspace-könyvtár már
létrejött legyen — időzítés-érzékeny. A fájl az E13-R24-ből való, és a
`lib/**` a kör tilos zónája, tehát a kör diffje okilag nem érinti. **A review
megmérte tiszta `main`-en (`fc880063`, E15-R03 nélkül): 3/3 zöld.** Egy
percekig CPU-t telítő teszt-fájl a párhuzamos suite mellett a legvalószínűbb
destabilizáló ok, ezért a javítás célja kettős volt: helyes algoritmus ÉS
stabil CI.

#### Javítás-ellenőrzés (`1929e971`) — **MAJOR-2 ZÁRVA**

A review MAGA mérte, nem bemondásra:

| Mérés | Előtte (`8d5cc3d1`) | Utána (`1929e971`) |
|---|---|---|
| `time flutter test test/tooling/screen_reachability_test.dart` | `real 3m0.848s` | **`real 0m5.744s`** (~31×) |
| a 9 cella | `+9 All tests passed!` | `+9 All tests passed!` |
| `sha256(--format json)` | `7cebc87d…c4b5958b` | **`7cebc87d…c4b5958b`** |

```
diff -q /tmp/reachability-baseline.json /tmp/reachability-after.json
→ (nincs kimenet)   OUTPUT BYTE-IDENTICAL
```

**A viselkedés bizonyítottan változatlan** (byte-azonos JSON, azonos hash), és
a **teszt-fájl egyáltalán nem módosult**:

```
git diff --stat 8d5cc3d1 1929e971 -- test/tooling/screen_reachability_test.dart
→ (üres)
```

— tehát a gyorsítás nem a cellák gyengítésével született. A `96/68/28/25`
összesítő és a `retirement-plan.md` tartalma változatlan.

### NOTE-1 — Az imperatív csatorna egy-ugrásos; a kör ezt KIMONDJA, nem elhallgatja

A checker azt méri, hogy egy osztály konstruálva van-e valahol `lib/` alatt,
nem azt, hogy a konstruáló hely maga elérhető-e egy belépési pontból. Két mért
következmény: `EditProfileScreen` csak a (mérten elérhetetlen)
`CommunityGateScreen`-ből, `ClubMemberManagementScreen` csak a (mérten
elérhetetlen) `ClubDetailScreen`-ből konstruálódik — mindkettő `keep`-et kap,
noha a bejárási lánc szakadt.

**Ez NEM lelet, hanem helyes viselkedés:** az ADR 0471 D7 pontosan ezt írja
elő (a korlátot kimondani, nem elhallgatni), és a `retirement-plan.md` §1/§3.3
és a §10.5 névvel, útvonallal felsorolja a két esetet. Egy tranzitív lezárás
szigorúbb lenne, de a D5 szerint úgysem törölhet semmit ez a kör. **A
következő kör (`E15-R04`) bemenete**, nem ezé.

### NOTE-2 — A flag-hatókör behúzás-alapú heurisztika, nem AST-parser

A `_computeFlagScopes` (`tool/check_screen_reachability.dart:342`) a
`dart format`-tiszta fa behúzására támaszkodik, és a `_flagIf` regex
(`:225`) csak a belső zárójel nélküli `if (...Enabled...)` alakot fogja
(pl. `if (ref.read(x).flags.yEnabled)` kimaradna). A kör ezt a §10.5-ben és a
tool doc-commentjében kimondja, a `format` gate-lépés pedig minden futásnál
őrzi az előfeltételt. **Elfogadva** — a D4 „jelentett dimenzió" célra elég, és
a korlát dokumentált, nem rejtett.

## 4. Acceptance criteria — cellánként

| # | Kritérium | Verdikt | Bizonyíték |
|---|---|---|---|
| A1 | mind a 96 képernyő ítéletet kap, forrás-hivatkozással | ✅ | `screen_reachability_test.dart:72–88` (`hasLength(96)` + determinizmus + nem-üres `primaryReference`); saját futás: `Measured screens: 96` |
| A2 | az imperatív navigáció is elérhetőség | ✅ | `:90–130` fixture-cella (`OrphanScreen`, csak `Navigator.push`) |
| A2b | a barrelen át hivatkozott képernyő is elérhető (D3) | ✅ | `:132–178` fixture-cella; az implementer §10.4(b) próbája szerint fájlnév-illesztésre PIROSRA vált |
| A3 | minden elérhető legacy képernyőhöz nevesített E15 kör | ✅ | `:216–294`, a valós tervet parse-olja; a beépített próba (`:263–293`) VALÓDI |
| A4 | minden `retire` tételhez indok ÉS felváltó | ✅ | `5c938294:311–319` közös helperen; a review saját próbája PIROSRA vitte. A mellé tett falszifikációs próba a javító körben VALÓDIVÁ vált (MAJOR-1 zárva) |
| A5 | a `ui_inventory_test` egzakt száma változatlan | ✅ | `git diff … -- test/ui/ui_inventory_test.dart` → 0 sor |
| A6 | a `migration-status.md` MÉRT számokat tartalmaz, a paranccsal | ✅ | 68/28/25 + a `dart run …` parancs a dokumentumban; a review reprodukálta |

## 5. Mérce-mátrix (brief §6.1) — az őrök tényleg fognak?

| Hibás implementáció | Melyik cella vált PIROSRA | Igazolva |
|---|---|---|
| A checker csak a routert nézi | A2 | fixture-cella (`:115`) |
| A checker fájlnévre illeszt (barrel-vakság) | A2b | §10.4(b), mért piros |
| Egy elérhető legacy képernyő kimarad a tervből | A3 | a beépített próba (`:263`) + §10.4(a) mért piros |
| „Visszavonandó" indok/felváltó nélkül | A4 | **a review saját próbája** vitte pirosra (`:307`) |
| A kör hozzáad vagy töröl egy képernyőt | A5 | `hasLength(96)` érintetlen |

## 6. Ami a körön KÍVÜL marad (helyesen)

- Semmit nem töröl, route-ot nem vesz ki (D5) — a `retire` hat sora JAVASLAT
  az `E15-R04`-nek.
- `lib/**` érintetlen.
- A `docs/adr/0471` a pre-flight commitban (`a4be396c`) készült, nem az
  implementer diffjében — a `docs/adr/**` tilos zóna tiszta.

## 7. Merge-feltétel — teljesülés

| Feltétel | Állapot |
|---|---|
| MAJOR-1 javítva, a javítás MÉRVE | ✅ `5c938294`, a review saját próbája pirosra vitte a kiütött őrt |
| MAJOR-2 javítva, a javítás MÉRVE | ✅ `1929e971`, byte-azonos JSON (`sha256` egyezik), 3m0.8s → 5.7s, a teszt-fájl változatlan |
| Független gate izolált `/tmp` klónban a javított commiten | ✅ MIND ZÖLD (`format`, `analyze`, mindkét teszt-útvonal, `architecture`, `secrets`, `l10n`) |
| Scope-audit | ✅ `scope_audit=ok`, `lib/**` érintetlen, A5 száma változatlan |
| `gate_shape` | ✅ `ok` (az első futás `VIOLATION`-jét a javító kör orvosolta) |
| Full Gate + Router CI a merge SHA-n `success` | a merge-lépés igazolja (exact-SHA, ADR 0086 §2) |

Nyitott BLOCKER/MAJOR/MINOR: **nincs**. A kör a CI zöldjével merge-elhető.
