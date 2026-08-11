# E07-R02 — Typed ID-k, enumok és domain primitívek

- **Státusz:** PREPARED (batch előre megírva **2026-08-11**, kód olvasva:
  `main` @ `ce2409fa`; az Epic 6 ekkor FUTOTT — a pre-flight kötelező)
- **SDD-kör:** [`docs/sdd/08-epic-07-ai-practice-generator.md`](../sdd/08-epic-07-ai-practice-generator.md)
  **Kör 2** (2982–3026. sor)
- **Batch-index:** [`epic-07-batch-index.md`](epic-07-batch-index.md)
- **Branch:** `codex/e07-r02-planner-domain-primitives`
- **Előfeltétel:** **E07-R01 merge-elve** (a `practiceGeneratorEnabled` flag
  és az ADR 0221/0222 léteznie kell)
- **Brief szerzője:** Claude (Opus 5, batch)
- **Előre kiosztott ADR:** **nincs** — a kör a 0221/0222 kereteit tölti ki,
  új architekturális döntést nem hoz. Ha az implementer mégis döntési
  kényszert érez → `stopped`, nem saját ADR.

```ai-router
schema_version = 1
risk = "normal"
allowed_paths = [
  "lib/features/practice_generator/domain/id/planner_ids.dart",
  "lib/features/practice_generator/domain/model/plan_enums.dart",
  "lib/features/practice_generator/public.dart",
  "test/features/practice_generator/domain/planner_ids_test.dart",
  "test/features/practice_generator/domain/plan_enums_test.dart",
  "docs/rounds/e07-r02-planner-domain-primitives.md",
]
gate_tests = [
  "test/features/practice_generator",
  "test/core",
]
native_gate = false
```

> **Öt ÚJ fájl** — ez a kör hozza létre a `lib/features/practice_generator/`
> fát. Minden más új fájl scope-sértés.
>
> `risk = "normal"`: jól specifikált, tesztvezérelt domain-primitív kör,
> tervezői ítélet nélkül. A motor-szabály ezért **minimax**-ot ad
> (`risk == "normal"` → minimax) — a queue `engine` oszlopa ezt kapja.
>
> A `test/core` azért van a gate-ben, mert az **architektúra-import teszt**
> ott él, és az SDD Kör 2 kötelező tesztként nevesíti.

## 0. Kör-jelzés és STOP-protokoll

```bash
tools/codex-signal.sh progress "<egy sor>" ; tools/codex-signal.sh done "<egy sor>"
tools/codex-signal.sh stopped "<egy sor>"  ; tools/codex-signal.sh blocked "<egy sor>"
```

Lezáró jelzés nélkül a kör bukott. Listán kívüli fájl → `stopped`.

## 0.0 ⚠ KÖTELEZŐ pre-flight (a brief ELŐRE készült)

1. **Az E07-R01 merge-elve?** Ha nem, `stopped` — a flag nélkül a
   `public.dart` exportnak nincs értelmes gazdája.
2. Létezik-e már a `lib/features/practice_generator/` fa? A brief azt
   feltételezi, hogy **nem**.
3. A `lib/core/foundation/` hibatípusai (`AppResult`, `AppFailure`) —
   a §5.4 ezekre épít; ellenőrizd a nevüket.
4. Egy MEGLÉVŐ typed-ID minta a repóban (§2.2) — kövesd, ne találj ki újat.

## 1. Cél

A generátor **Flutter-független** alaptípusai: typed ID-k, enumok, stabil
JSON round-trip, injektálható `IdGenerator`.

Ez a réteg 28 további kör alapja — a hibái mindenhová beépülnek.

## 2. Jelenlegi állapot (mérve 2026-08-11, `main @ ce2409fa`)

### 2.1 A cél-könyvtár nem létezik

`lib/features/practice_generator/` — **nincs**. Ez a kör hozza létre.

### 2.2 Követendő minták a repóban

A projekt már használ typed ID-t és stabil enum-kódolást; **ezeket kövesd,
ne tervezz újat**:

- `lib/features/song_trainer/domain/**/song_id.dart` (és testvérei) —
  a typed-ID minta.
- `lib/core/foundation/app_result.dart` / `app_failure.dart` — a hibaút:
  `AppResult.failure(...)`, nem dobás.
- A `requireString` / `requireDouble` / `requireEnumByName` segédek
  (`lib/features/analyze/model/analyze_result.dart` használja őket) — a
  fail-closed JSON-dekódolás bevett alakja.

### 2.3 Az architektúra-őr

`dart run tool/check_architecture.dart` — a mérés szerint **12** allowlisted
eltérés, és a lista **csak szűkülhet**. Egy új feature-fa nem kerülhet a
listára.

## 3. Scope

**Benne:**

1. `planner_ids.dart` — a hat typed ID: plan, day, block, goal, revision,
   outcome.
2. `plan_enums.dart` — státusz, mód, block-kind, severity, source enumok,
   stabil string kódokkal.
3. `public.dart` — a feature szűk barrelje (§5.5).
4. A két tesztfájl.
5. A brief §10 handoff.

**Kívül (ebben a körben TILOS):**

- **Bármilyen üzleti logika**: terv-generálás, priorizálás, validátor,
  repository — mind későbbi kör.
- **Flutter import bárhol a domainben** (§5.1).
- Bármely más feature fájlja, a `lib/app/`, a `lib/core/`.
- Az architektúra-allowlist bővítése.
- Új ARB-kulcs, UI, route.

## 4. Engedélyezett fájlok

| Útvonal | Miért |
|---|---|
| `lib/features/practice_generator/domain/id/planner_ids.dart` | **ÚJ** — a hat typed ID |
| `lib/features/practice_generator/domain/model/plan_enums.dart` | **ÚJ** — az öt enum-család |
| `lib/features/practice_generator/public.dart` | **ÚJ** — szűk barrel |
| `test/features/practice_generator/domain/planner_ids_test.dart` | **ÚJ** |
| `test/features/practice_generator/domain/plan_enums_test.dart` | **ÚJ** |
| `docs/rounds/e07-r02-planner-domain-primitives.md` | §10 handoff |

**Tilos zóna:** minden más — `lib/app/`, `lib/core/`, `lib/l10n/`, a többi
`lib/features/**`, `tool/`, `tools/`, `.github/`, `assets/`, `backend/`,
`docs/adr/`.

## 5. Kötött architekturális döntések

### 5.1 A domain NEM importál Fluttert

Sem `package:flutter/...`, sem `dart:ui`. Gépi mérce az A1-ben.

Indok: ez a réteg a generátor magja; ha Flutterre köt, sem izoláltan
tesztelni, sem later háttérszálon futtatni nem lehet.

### 5.2 Az ID fail-closed: üres és érvénytelen érték ELUTASÍTOTT

A konstruktor **nem fogad el** üres vagy csak whitespace értéket. A
visszautasítás alakja a repó bevett módja szerint történjen (a §2.2 minták),
és **következetesen ugyanaz** legyen mind a hat ID-nál.

**Nem elfogadható:** csendes normalizálás (trim + elfogadás), üres ID
„üres objektumként" való átengedése.

### 5.3 Az enum string-kódok STABILAK, és a `.name` NEM elég

A JSON-kód **explicit, kipinnelt string** legyen, nem a Dart `.name`
származéka — különben egy enum-átnevezés némán töri a perzisztált adatot.

**Nem elfogadható:** `values.byName(json)` a kipinnelt kódtábla helyett.

### 5.4 Ismeretlen enum-kód = kontrollált hiba, nem default

Migrációkor egy ismeretlen kód **kontrollált failure**-t ad
(`AppResult.failure` vagy a repó bevett kivétel-alakja), **nem** esik vissza
egy „első" vagy „unknown" értékre.

**Nem elfogadható:** `orElse: () => Xy.unknown`, `?? values.first`, vagy
bármilyen néma default. Ez az ADR 0222 (immutable múlt) gyakorlati
következménye: egy félreolvasott régi terv rosszabb, mint egy olvashatatlan.

### 5.5 A `public.dart` SZŰK barrel

Csak azt exportálja, amire más rétegnek szüksége van. **Nem** exportál
belső segédet, nem re-exportál `dart:` vagy `package:` szimbólumot.

Mért indok (E05-R25/R26 security-review): a wide barrel szimbólum-rést nyit,
amit az architektúra-őr nem lát.

### 5.6 Injektálható `IdGenerator`

Az ID-előállítás **paraméterezhető** legyen (konstruktor-paraméter,
alapértéke a valódi generátor), hogy a teszt determinisztikus lehessen.

**Nem elfogadható:** `DateTime.now()` vagy `Random()` közvetlen hívása a
domain belsejében.

### 5.7 Nyitott döntések (ADR 0138)

```yaml
open_decisions:
  - id: OD-01
    question: Egy fájlban legyen mind a hat ID, vagy fájlonként egy?
    blocking: false
    resolution_policy: use_default
    default: >
      EGY fájl (`planner_ids.dart`) — az `allowed_paths` így van megírva.
      Hat különálló fájl scope-sértés lenne. Ha a fájl kezelhetetlenül
      hosszúra nőne, az a KÖVETKEZŐ kör bontási feladata, nem ezé.

  - id: OD-02
    question: Milyen alakú legyen az érvénytelen ID visszautasítása?
    blocking: false
    resolution_policy: use_default
    default: >
      Kövesd a §2.2-ben mért MEGLÉVŐ typed-ID mintát a repóban. Ha az
      `ArgumentError`-t dob, dobj te is; ha `AppResult`-ot ad, adj te is.
      A lényeg a KÖVETKEZETESSÉG mind a hat ID-nál, nem a konkrét alak.

  - id: OD-03
    question: Mi legyen, ha egy SDD-ben kért enum-érték ütközik meglévő típussal?
    blocking: true
    resolution_policy: stop_and_ask
    default: >
      `stopped`, a névvel és az ütköző típus helyével. Mért eset: az
      E05-R29-ben egy brief olyan `VisionDeviceTier` típust írt elő, ami
      MÁR létezett más értékkészlettel — a néma újradefiniálás párhuzamos
      vokabuláriumot hozott volna létre.
```

## 6. Acceptance criteria

- [ ] **A1 — Nulla Flutter-import a domainben.** Gépi mérce:
  `grep -rE "package:flutter|dart:ui" lib/features/practice_generator/domain/`
  → **0 találat**.

- [ ] **A2 — Az ID-k fail-closed viselkedése, mind a HAT ID-ra.** Mátrix
  (minden ID × minden bemenet):

  | Bemenet | Elvárt |
  |---|---|
  | `""` (üres) | **elutasítva** |
  | `"   "` (csak whitespace) | **elutasítva** |
  | érvényes érték | elfogadva, `value` visszaadja |

  A whitespace-cella az, ami a „csendes trim + elfogadás" hibát pirosra
  váltja. Egyik ID sem hagyható ki.

- [ ] **A3 — ID equality.** Azonos értékű ID-k egyenlők és azonos
  `hashCode`-ot adnak; **különböző TÍPUSÚ**, de azonos szövegű ID-k
  (pl. `PlanId('x')` és `GoalId('x')`) **NEM** egyenlők. Ez utóbbi cella
  fogja meg a „mind csak String wrapper, közös ősosztállyal" hibát.

- [ ] **A4 — JSON round-trip minden enumra.** Minden enum minden értékére:
  `decode(encode(v)) == v`, és az `encode` a **kipinnelt** kódot adja, nem
  a `.name`-et. Teszt-cella: legalább egy enum-értéknél a kód **térjen el**
  a Dart-névtől (pl. `blockKind: chordChange → "chord_change"`), és a teszt
  a konkrét stringre állítson.

- [ ] **A5 — Ismeretlen enum-kód kontrollált hibát ad.** Minden enum-családra:
  a `"__nem_letezik__"` kód **kontrollált failure**-t ad, **nem** default
  értéket. Gépi kerítés:
  `grep -rE "orElse|\?\? *[A-Z][A-Za-z]*\.(unknown|first)" lib/features/practice_generator/domain/model/plan_enums.dart`
  → **0 találat**.

- [ ] **A6 — Az `IdGenerator` injektálható és determinisztikus tesztben.**
  Teszt-cella: egy fix generátorral kétszer előállított ID **azonos**;
  a domain nem hív `DateTime.now()`-ot vagy `Random()`-ot közvetlenül.
  Gépi kerítés: `grep -rE "DateTime\.now\(\)|Random\(\)" lib/features/practice_generator/domain/`
  → **0 találat**.

- [ ] **A7 — A barrel szűk.** A `public.dart` **csak** a hat ID-t és az
  enumokat exportálja; nem exportál belső segédet, és nem re-exportál
  `dart:`/`package:` szimbólumot.

- [ ] **A8 — Az architektúra-őr nem tágult.**
  `dart run tool/check_architecture.dart` legfeljebb **12** allowlisted
  eltérés (a §2.3 mérése; kevesebb elfogadott).

- [ ] **A9 — A gate zöld** a §7 szerinti egyetlen artefaktum-hívással.

> **Miért nincs numerikus cellahármas:** a kör egyetlen acceptance-pontja sem
> mér számértékre — minden mérce logikai (import jelenléte, elfogadás/
> elutasítás, egyenlőség, string-egyezés). Az A8 elemszám-korlát monoton
> szigorítási szabály, nem mérendő érték.

### 6.1 Mérce-mátrix — melyik hibás implementációt melyik cella fogja pirosra

| Hibás implementáció | Melyik cella vált PIROSRA |
|---|---|
| A domain `package:flutter/foundation.dart`-ot importál (`@immutable` kedvéért) | **A1** |
| Az üres ID-t csendben elfogadja | **A2** üres cella |
| Trimmel és elfogadja a whitespace-t | **A2** whitespace cella |
| Minden ID közös `StringId` ősosztály, típus nélküli egyenlőséggel | **A3** kereszt-típus cellája |
| Az enum kódolása `.name`-re épül | **A4** (az eltérő kódú enum-érték cellája) |
| Ismeretlen kódra `orElse: () => X.unknown` | **A5** + a grep-kerítés |
| `DateTime.now()` az ID-generálásban | **A6** + a grep-kerítés |
| A barrel a belső segédeket is exportálja | **A7** |
| Az új feature-fa kivételt kap az allowlistben | **A8** |

**Valódi-sértés próba (kötelező, §10-ben dokumentálandó):** cseréld ki
ideiglenesen az egyik enum dekódolását `values.byName(code)`-ra → az **A4**
eltérő-kódú cellájának **PIROSNAK** kell lennie → állítsd vissza, és idézd a
nyers kimenetet.

## 7. Kötelező ellenőrzések

```bash
tools/round-gate.sh test/features/practice_generator test/core
```

Külön processzek, csonkítatlan kimenet. **Tilos** `| tail`, `| head`,
`&&`-lánc vagy bármilyen szűrés (`docs/LESSONS.md` L09); az `analyze` és a
`test` kézi láncolása ezen a gépen OOM-ot ad (L05).

## 8. Implementációs sorrend

1. **RED először:** `planner_ids_test.dart` — az A2 mátrix (6 ID × 3 bemenet)
   és az A3 kereszt-típus cellája.
2. `planner_ids.dart` — a hat typed ID + injektálható `IdGenerator` (A6).
3. **RED:** `plan_enums_test.dart` — A4 round-trip (az eltérő kódú cellával)
   és A5 ismeretlen kód.
4. `plan_enums.dart` — kipinnelt kódtáblával.
5. `public.dart` — szűk barrel (A7).
6. Gate.
7. A §6.1 valódi-sértés próba + visszaállítás.
8. Záró gate + §10 handoff + `done`.

## 9. Kockázatok

1. **Ez a réteg 28 kör alapja** — egy rossz enum-kód vagy laza ID-validáció
   mindenhová beépül, és később drága javítani. Ezért a szigorú §5.
2. **A „csak egy String wrapper" csábítás** — az A3 kereszt-típus cellája
   ezt fogja meg.
3. **Az SDD enum-értékei ütközhetnek meglévő típussal** (OD-03) — ez
   `stopped`, nem néma újradefiniálás.

## 10. Implementation handoff — a Codex/MiniMax tölti ki

- Fájlonkénti összefoglaló.
- Futtatott parancsok + **TÉNYLEGES, csonkítatlan** kimenet.
- A §6.1 valódi-sértés próba nyers kimenete + visszaállítás.
- Az **A1/A5/A6/A8** gépi kerítéseinek tényleges kimenete.
- A §0.0 pre-flight mérései.
- Eltérések és okuk; nem futtatott ellenőrzések és okuk; follow-upok.

> Állítás teszt nélkül = bemondás.

## 11. Review — a Claude tölti ki

Link: `docs/reviews/e07-r02-planner-domain-primitives-review.md`
