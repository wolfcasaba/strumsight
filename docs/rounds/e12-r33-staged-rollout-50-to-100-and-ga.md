# E12-R33 — Staged rollout 50–100 százalék és GA

- **Státusz:** PREPARED (előre megírva 2026-08-27, kód olvasva: `main @ 9ca4a0dc`)
- **Típus:** Chapter 12 (Release Roadmap, Sprint Planning & Final Integration), Kör 33
- **Kör-azonosító:** `E12-R33`
- **Branch:** `<motor>/e12-r33-staged-rollout-50-to-100-and-ga`
- **Előfeltétel:** `E12-R32` merge-elve ÉS a 20%-os lépcső USER általi lezárása
- **Brief szerzője:** Claude (Opus 5)
- **Előre kiosztott ADR:** nincs — a kör GA-rekordot és záró ellenőrzést szállít.

**Visszakeresett előzmény:** `node tools/knowledge-rag.mjs --corpus lessons,halts,adr --top 5 "general availability rollout 100 percent release notes support"` → **[ADR 0065](../adr/0065-practice-engine-v2-parallel-rollout.md)** és **[ADR 0197](../adr/0197-song-trainer-shipping-rollout-boundary.md)** — a repó MÉRT rollout-mintái (párhuzamos futás, availability flag, belépési pont). A GA-rekordnak ezért a FLAG-PROFILT is rögzítenie kell, nem csak a verziót.

> ⚠ **Pre-flight (indítás előtt KÖTELEZŐ):** ellenőrizd, hogy a `staged-rollout-log.md` 1/5/20%-os lépcsői KITÖLTVE és jóváhagyva vannak-e. Üres napló mellett a kör nem indítható (`blocked`).
>
> **ELVÉGEZVE, MÉRVE, FELOLDVA → lásd [§0.0.1 P1](#001-pre-flight-revízió--orchestrátor-2026-09-02-adr-0087-2-a-kör-saját-még-nem-merge-elt-briefje).** A napló sémája megvan, a lépcsők NINCSENEK kitöltve (mind `pending`/`TBD`), és nem is lehetnek, amíg egy P0 + öt P1 blocker nyitva van. A kapu ezért séma-létezés ellenőrzés, a kitöltetlenség pedig **gépi invariáns** lett (§5.4 / A7) — a kör indítható, és továbbra sem tesz közzé semmit.

## 0.0 EMBERI KAPU

A 50% és 100% lépcső, valamint a store-oldali GA **user-művelet**. Az implementer terméke: a GA-rekord sablonja és ellenőrzője (build, flag-profil, modell-verzió, időbélyeg, támogatási linkek), a végleges release-notes generálása, és a záró konzisztencia-ellenőrzés. A kör NEM tesz közzé semmit.

### 0.0.1 Pre-flight revízió — orchestrátor, 2026-09-02 (ADR 0087 §2: a kör SAJÁT, még nem merge-elt briefje)

**P1 — a ⚠ pre-flight kapu MÉRT feloldása (nem kihagyása).** A
`staged-rollout-log.md` LÉTEZIK és teljes sémájú (Kör 32, `f6db8a8d`): 3
döntés-sor + 15 megfigyelés-sor. Kitöltve azonban NINCS — minden `decision`
`pending`, minden `verdict` `unknown`, minden szöveges cella `TBD` (mérve:
`docs/release/staged-rollout-log.md`). Szó szerint olvasva a „Üres napló
mellett a kör nem indítható" mondat a láncot **véglegesen** megállítaná, mert
a napló csak egy VALÓDI store-rollouttal tölthető ki, az pedig ma maga is
blokkolt: `docs/release/blockers.md` szerint nyitva van **egy P0**
(`R-SIGN-01`) és **öt P1** (`R-VER-01`, `R-PRIV-01`, `R-SEC-01`,
`R-STAGE-01`, `R-STORE-01`), és a `ga-scope.md` fejléce ezért mondja ki:
**„NEM KÉSZ (NOT READY)"**. A brief §2 ezt az állapotot MÁR MÉRTE és a kört
kifejezetten rá tervezte („Store-jelenlét MA nincs … a GA-rekord ezért a
publikálás UTÁN kitöltendő mezőket EXPLICIT emberi jelöléssel viszi").

**Feloldás:** a kapu **séma-létezés** ellenőrzés (teljesül), a kitöltetlen
állapotot pedig nem elkenjük, hanem **gépi invariánssá** tesszük (P2/§5.4/A7).
Precedens: az E12-R32 ugyanígy szállított sémát + ellenőrzőt + üres naplót
tényleges rollout nélkül. A kör terméke sablon, ellenőrző, teszt és jegyzet —
egyik sem függ a napló kitöltöttségétől, és a kör **továbbra sem tesz közzé
semmit**.

**P2 — ÚJ kötött szabály (§5.4): a rekord nem állíthat meg nem történt GA-t.**
A GA-rekord gépi `ga_status` mezőt hordoz, zárt értékkészlettel
(`not-yet` | `in-progress` | `ga`). A `verify_ga_record.py` **nem-nulla
kilépéssel** áll meg, ha `ga_status: ga`, miközben (a) a
`staged-rollout-log.md` bármely `stage-*` döntése nem `approved`, VAGY (b) a
`blockers.md`-ben nyitott P0/P1 van. **NEM elfogadható gyengítés:** a rekord
csak PRÓZÁBAN mondja, hogy „még nincs GA", gépi mező nélkül. → **A7** cella.

**P3 — az A2 MÉRT útvonala (a §1 „táblát mértem, nem az utat" hibaosztály
ellen).** Statikus release-manifest fájl a fán **NINCS**. A manifest generált
Dart-artefaktum: `tool/generate_release_manifest.dart --output <path>` (mérve:
`tool/generate_release_manifest.dart:24-77`), amelynek verzió-bemenete a
`pubspec.yaml:5` (`1.0.0+1`), továbbá az `assets/ml/model_manifest.json` és az
`assets/tutor_knowledge/manifest.json`. Ezért:

- az A2 összevetés **Dartban** fut, a `ga_record_test.dart`-ban, a
  `../../tool/generate_release_manifest.dart` importálásával — ez a
  `test/tooling/release_manifest_test.dart:24` MÉRT mintája
  (`_buildRealManifest()`);
- a `verify_ga_record.py` UGYANEZEKET a mezőket a manifest **deklarált
  BEMENETEI** ellen ellenőrzi (`pubspec.yaml` verzió/build, a két
  asset-manifest sha256-ja). **Tilos** nem létező statikus manifest fájlt
  olvasnia, és **tilos** `dart run`-t hívnia.

**NEM elfogadható gyengítés:** kézzel a Pythonba másolt `1.0.0+1` literál.

**P4 — a flag-profil MÉRT forrása (A3).** A `docs/release/ga-scope.md` zárt
marker-blokkja: `<!-- ga-scope-capabilities:begin/end -->`, **16** flag-kulcs
`classification` + `production_default` oszlopokkal (mérve: `ga-scope.md:58-77`).
A pillanatképnek mind a 16 kulcsot hordoznia kell; az ellenőrző hibát jelez
hiányzó vagy többlet kulcsra ehhez a blokkhoz képest. **NEM elfogadható
gyengítés:** prózai „minden flag ki van kapcsolva" mondat.

**P5 — a rollback-cél MÉRT forrása (A4/§5.3).** Repó-relatív, a fán MA
feloldható útvonal (pl. `docs/release/client-migration.md`,
`docs/operations/disaster-recovery-drill.md`). Az ellenőrző elutasítja az
üres, `TBD`/`<…>` alakú vagy nem feloldható rollback-célt.

**P6 — ADR: nincs, és nem is lesz.** A §3/§4 tilos zónája a `docs/adr/**`, az
engedélyezett-fájllista pedig kizárólag **szűkíthető** (ADR 0087 §2) — az új
§5.4 ezért ugyanúgy briefbeli kötött szabály, mint a meglévő három.

**P7 — az engedélyezett-fájllista VÁLTOZATLAN.** A
`test/tooling/rollout_decision_test.dart` csak `gate_tests` bejegyzés, nem
módosítandó fájl.

```ai-router
schema_version = 1
risk = "normal"
allowed_paths = [
  "docs/release/ga-record.md",
  "docs/release/release-notes.md",
  "tool/release/verify_ga_record.py",
  "test/tooling/ga_record_test.dart",
  "docs/rounds/e12-r33-staged-rollout-50-to-100-and-ga.md",
]
gate_tests = [
  "test/tooling/ga_record_test.dart",
  "test/tooling/rollout_decision_test.dart",
]
native_gate = false
```

## 0. Kör-jelzés és STOP-protokoll

```bash
tools/codex-signal.sh progress "<egy sor>"
tools/codex-signal.sh done "<egy sor>"
tools/codex-signal.sh stopped "<egy sor>"
tools/codex-signal.sh blocked "<egy sor>"
```

**STOP-protokoll:** ha a GA-rekord egy mezőjéhez nincs bizonyíték (pl. hiányzó modell-verzió a manifestben), a kimenet a `stopped` jelzés — kitöltetlen mező nem maradhat, és kitalált érték sem kerülhet bele.

## 1. Cél

A teljes elérhetőség elérése auditálhatóan: a GA-állapot minden lényeges paramétere rögzített, a support- és rollback-készenlét pedig fennmarad.

## 2. Jelenlegi állapot — mért tények

- `docs/release/staged-rollout-log.md` és `rollout-decision.md` a Kör 32 termékei.
- A release-manifest (Kör 6) hordozza a build-, modell- és tudáscsomag-verziót; a flag-profil a Kör 5 katalógus + a Kör 28 GA-scope.
- `docs/release/ga-record.md` és `release-notes.md` **nincs**.
- Store-jelenlét MA nincs (Kör 1) — a GA-rekord ezért a publikálás UTÁN kitöltendő mezőket EXPLICIT emberi jelöléssel viszi.

## 3. Scope

**Benne van:** `docs/release/ga-record.md` (GA időbélyeg, build-azonosító + SHA, flag-profil pillanatkép, modell- és tartalom-verzió, ismert hibák hivatkozása, rollback-cél, támogatási linkek) · `tool/release/verify_ga_record.py` (kitöltetlen kötelező mező, manifesttel nem egyező verzió, hiányzó rollback-cél → nem-nulla kilépés) · `test/tooling/ga_record_test.dart` · `docs/release/release-notes.md` (a Kör 6 manifestjéből és a `known-issues.md`-ből generált, determinisztikus jegyzet).

**NINCS benne (tilos):**

- Store-művelet, publikálás vagy rollout-százalék állítása.
- `lib/**`, `backend/**`, `.github/**` módosítás.
- A `staged-rollout-log.md` átírása.
- `docs/adr/**`.

## 4. Engedélyezett fájlok

| Útvonal | Indok |
|---|---|
| `docs/release/ga-record.md` | ÚJ — a GA-rekord |
| `docs/release/release-notes.md` | ÚJ — végleges jegyzet |
| `tool/release/verify_ga_record.py` | ÚJ — a rekord ellenőrzője |
| `test/tooling/ga_record_test.dart` | a §6 cellái |

**Tilos zóna:** `lib/**` · `backend/**` · `.github/**` · `docs/release/staged-rollout-log.md` · `docs/adr/**` · `tools/**`

## 5. Kötött architekturális döntések

Nincs ADR. Három kötelező szabály:

### 5.1 A GA-rekord a FLAG-PROFILT is rögzíti

A repó mért tapasztalata (ADR 0065/0197): a rollout nem csak verzió, hanem elérhetőségi kapcsolók és belépési pontok kérdése. **NEM elfogadható gyengítés:** csak a verziószám rögzítése.

### 5.2 A verzió-mezők a MANIFESTBŐL származnak

**NEM elfogadható gyengítés:** kézzel írt verzió, ami a manifesttől eltérhet.

### 5.3 A rollback-készenlét a GA UTÁN is fennáll

A rekord megnevezi az érvényes rollback-célt és annak elérhetőségét. **NEM elfogadható gyengítés:** „GA után nincs visszaút" megfogalmazás.

### 5.4 A rekord nem állíthat meg nem történt GA-t (§0.0.1 P2)

Gépi `ga_status` mező, zárt értékkészlettel (`not-yet` | `in-progress` | `ga`).
A `verify_ga_record.py` nem-nulla kilépéssel áll meg, ha `ga_status: ga`,
miközben a `staged-rollout-log.md` bármely `stage-*` döntése nem `approved`,
VAGY a `blockers.md`-ben nyitott P0/P1 van. MA mindkét feltétel fennáll, tehát
a szállított rekord `ga_status`-a **`not-yet`**. **NEM elfogadható gyengítés:**
a tilalom csak prózában, gépi mező és ellenőrzés nélkül.

## 6. Acceptance criteria

| # | Kritérium | Bizonyíték |
|---|---|---|
| A1 | Kitöltetlen kötelező mező → `verify_ga_record.py` nem-nulla kilépés | `ga_record_test.dart` |
| A2 | A rekord verzió-mezői egyeznek a release-manifesttel | `ga_record_test.dart` |
| A3 | A rekord tartalmazza a flag-profil pillanatképét | `ga_record_test.dart` |
| A4 | A rekord megnevezi az érvényes rollback-célt | `ga_record_test.dart` |
| A5 | A release-notes determinisztikus és a `known-issues.md`-re hivatkozik | `ga_record_test.dart` |
| A6 | A dokumentum kimondja, hogy a publikálás EMBERI művelet | a dokumentum |
| A7 | `ga_status: ga` nyitott P0/P1 vagy nem-`approved` `stage-*` döntés mellett → `verify_ga_record.py` nem-nulla kilépés; a szállított rekord `ga_status`-a `not-yet` (§5.4) | `ga_record_test.dart` |

### 6.1 Mérce-mátrix — melyik hibás implementációt melyik cella fogja pirosra

| Hibás implementáció | Melyik cella vált PIROSRA |
|---|---|
| A verziót kézzel írjuk be, manifest-ellenőrzés nélkül | A2 |
| A flag-profil kimarad a rekordból | A3 |
| A rollback-cél mező üresen marad | A4 |
| A release-notes generálási időbélyeget tartalmaz | A5 |
| A rekord `ga_status: ga`-t állít, miközben nyitott P0/P1 van (§5.4) | A7 |
| A `ga_status` mező kimarad, a „még nincs GA" csak prózában szerepel | A7 |

**Valódi-sértés próba 1 (KÖTELEZŐ, a §10-ben dokumentálva):** írj a GA-rekordba a manifestétől ELTÉRŐ build-számot, futtasd a §7 gate-et → az **A2** cellának PIROSNAK kell lennie → állítsd vissza.

**Valódi-sértés próba 2 (KÖTELEZŐ, §0.0.1 P2, a §10-ben dokumentálva):** állítsd a rekord `ga_status` mezőjét `ga`-ra (miközben a `blockers.md`-ben nyitott P0/P1 van), futtasd a `python3 tool/release/verify_ga_record.py --record docs/release/ga-record.md` parancsot → **nem-nulla** kilépés kell (A7) → állítsd vissza `not-yet`-re.

## 7. Kötelező ellenőrzések

```bash
tools/round-gate.sh test/tooling/ga_record_test.dart test/tooling/rollout_decision_test.dart
```

Az ellenőrző közvetlen futtatása (kimenet a §10-be):

```bash
python3 tool/release/verify_ga_record.py --record docs/release/ga-record.md
```

## 8. Implementációs sorrend

1. `docs/release/ga-record.md` sablon (emberi mezők jelölésével, `ga_status: not-yet`, flag-profil pillanatkép a §0.0.1 P4 szerinti 16 kulccsal).
2. `tool/release/verify_ga_record.py` (a §0.0.1 P3 szerint a manifest BEMENETEI ellen mér — nincs statikus manifest fájl, nincs `dart run`).
3. `test/tooling/ga_record_test.dart` (az A2 Dart-oldali manifest-összevetése a `release_manifest_test.dart:24` mintájára).
4. `docs/release/release-notes.md` generálás.
5. MINDKÉT valódi-sértés próba a §10-be.

## 9. Kockázatok

- **Auditálhatatlan GA.** Flag-profil nélkül később nem rekonstruálható, mit kaptak a felhasználók (A3).
- **Verzió-eltérés.** Kézi mező és manifest szétcsúszása (A2).
- **Rollback-készenlét elvesztése.** A GA nem szünteti meg a visszaút kötelezettségét (§5.3).

## 10. Implementation handoff — az implementer tölti ki

## 11. Review — a Claude tölti ki
