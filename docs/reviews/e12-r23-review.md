# E12-R23 — Review (Claude, orchestrátor/ellenőrző)

- **Kör:** `E12-R23` — Legacy user migration release candidate
- **Ág:** `sonnet-impl/e12-r23-legacy-migration-release-candidate`
- **Review-elt HEAD:** `1ab491e038cf4dbea2cd868230197bd766f18b26`
- **Implementer motor:** `sonnet-impl` (Claude Sonnet 5, `--effort high`)
- **ADR:** [0487](../adr/0487-legacy-upgrade-migration-evidence-contract.md)
- **Dátum:** 2026-09-02
- **VERDIKT (1. kör):** CHANGES REQUESTED — 1 MAJOR, 1 MINOR
- **VÉGSŐ DÖNTÉS (javító kör után, `37be88757584c973cc77cbfb282099a0b782ab3b`):**
  **APPROVED** — 0 nyitott lelet (lásd §7)

## 1. Mit mértem magam

| Mérés | Parancs | Eredmény |
|---|---|---|
| Gate, izolált `/tmp` klónban | `tools/round-gate.sh test/e2e/upgrade_migration_test.dart test/tooling/fixture_manifest_test.dart test/ui/ui_inventory_test.dart` | **8/8 ZÖLD** (format, analyze, 3 teszt, architecture, secrets, l10n) |
| Scope-audit | `python3 tools/scope-audit.py --repo … --brief … --base ba7234e2` | **OK**, 9 changed path |
| Biztonsági review (`risk = high`, kötelező) | `security-reviewer` ügynök | **PASS**, 0 lelet; a három fixture `sha256`/`bytes` értékét függetlenül újraszámolta, mind egyezik |
| Próbateszt (eldobható) | `flutter test test/e2e/zz_review_probe_test.dart` | lásd §2 — **egy nem mért utat talált** |

A `dirty_files=2` jelzést kivizsgáltam: kizárólag az orchestrátor saját, sosem
commitolt prompt-fájlja (`round-prompt-e12-r23.md`, `git ls-files` → üres). A
scope-audit első futása ezt jelölte, eltávolítás után **OK**.

## 2. A próbateszt — a kör saját falszifikációs mátrixának egy sora őrizetlen

A `README.md` (43-59. sor) központi állítása: *„no legacy JSON content, however
malformed, can make `StorageMigrator.migrate()` return a non-null `failure`"*. Ezt
nem olvastam el — **megmértem**:

```
P1 failure=null from=0 to=22 applied=22
P2 legacyKeyPreserved=true newKeyWritten=false schemaVersion=22
P2 readBody=NULL (üres dokumentum)
```

**P1 igazolja a README-t** — az állítás mért, nem feltételezett. Ez a kör javára írandó.

**P2 viszont egy nem mért, a kör szerződésébe ütköző kimenetet mutat.** Egy ténylegesen
sérült legacy dokumentummal (`user_songs_v1` = csonka JSON):

1. a `migrate()` **sikert jelent** (`failure=null`, mind a 22 lépés `applied`, a
   `schemaVersion` 22-re lép);
2. a nyers legacy bájtok **megmaradnak** (nincs adatvesztés a lemezen) — a
   `WrapJsonDocumentMigration.apply` a `jsonDecode` kivételét naplózza és `return`-öl,
   az ÚJ kulcs nem íródik ki, a régi nem törlődik;
3. **de a production olvasási út üres dokumentumot ad**: `JsonDocumentStore.readBody()`
   → `null`, mert az `ss.songs` kulcs nincs, a legacy fallback pedig a sérült bájtokon
   `_decode`-ol.

A felhasználó tehát frissítés után **üres dalkönyvtárat lát**, miközben az adata a lemezen
ott van (a `write()` következő hívása karanténba menti). Ez pontosan az az eredmény,
amit a brief §5.2 és az **ADR 0487 D3** kizár: *„a sikertelen migráció SOHA nem indít
üres profilt"*.

### MAJOR-1 — a sérült bemenet útját egyetlen cella sem méri

**Hol:** `test/e2e/upgrade_migration_test.dart:177-244` (A3 cella),
`test/fixtures/migrations/corrupted_storage.json`.

**A lelet:** az A3 cella a hibát **nem** a sérült bemenetből nyeri, hanem egy injektált
írás-hibából (`store.failingKeys.add(StorageKeys.themeMode)`). A fixture minden értéke
jól formált JSON — a cella szó szerint ugyanígy zöld lenne a `legacy_v1_storage.json`-nal
is. Ebből következik, hogy a brief §6.1 mátrixának **„A sérült bemenet csendben
»sikeresnek« jelenti magát → A3"** sora **őrizetlen**: a fenti P1/P2 próba pontosan ezt az
esetet produkálja, és a kör egyetlen cellája sem vált tőle pirosra.

Egy `risk = "high"`, adatintegritásról szóló release-jelölt körben a legfontosabb
adatvesztés-közeli út marad így mérés nélkül — miközben a README (43-68. sor) helyesen le
is írja. **Ami csak README-ben van, az nem mérce.**

**Javasolt irány (kör-on belüli, teszt+doksi, `lib/**` érintése NÉLKÜL):**

1. Egy ÚJ cella a `upgrade_migration_test.dart`-ban, amely egy **ténylegesen malformált**
   legacy dokumentumot ad be, és pinneli a MÉRT viselkedést:
   - `report.failure` `null` **és** a `schemaVersion` a végértékre lép (a korrupció-átlátszóság
     kimondva, nem feltételezve);
   - a nyers legacy érték **bájtra azonos** marad (ez a valódi adatvesztés-őr);
   - a `JsonDocumentStore.readBody()` mai kimenete (`null` / üres dokumentum) **explicit
     `expect`-ként**, „ismert korlát" megjelöléssel — ha egy jövőbeli kör ezt megjavítja
     vagy elrontja, a cella szól.
2. A korlát átvezetése a `docs/release/client-migration.md`-be (a kör saját
   „mit migrálunk, mi a korlát" dokumentuma) és az ADR 0487 „Ár és korlát" szakaszába.

**Ami NEM a javítás:** a `lib/**` migrátor vagy a `JsonDocumentStore` módosítása. Az a
kör tilos zónája, és külön, review-zott kör tárgya (ADR 0487 D4 mintájára).

### MINOR-1 — a `corrupted_storage.json` neve olyat állít, amit a fájl nem tartalmaz

**Hol:** `test/fixtures/migrations/corrupted_storage.json`, `test/fixtures/manifest.json`.

A fájl neve „corrupted", a tartalma viszont hibátlan JSON. A README ezt tisztességesen
kimondja és meg is indokolja, de a fájlnév és a manifest `source` mezője önmagában
félrevezet — egy későbbi kör a nevére hagyatkozva hihetné, hogy a korrupt út le van fedve
(pontosan az a tévedés, amit a MAJOR-1 leír). A MAJOR-1 javítása ezt természetesen
feloldja: vagy a fixture kap egy ténylegesen malformált mezőt (és a neve igazzá válik),
vagy a nevét kell a tartalmához igazítani (pl. `write_fault_baseline_storage.json`).

## 3. Acceptance criteria — tételes ellenőrzés

| # | Állapot | Bizonyíték |
|---|---|---|
| A1 | **teljesül** | `upgrade_migration_test.dart:33-91` — `equals()` az id-halmazokra, `practiceLog` nap-halmazra, `lessonProgress` és `streak` Map-re; a halmazok bizonyítottan nem üresek (az A5 pinneli a darabszámokat: 2/3/1/4/3 és 1/2/2/3/2) |
| A2 | **teljesül** | `:96-174` — v10 írás-blokk → `toVersion == 9`, resume → `fromVersion == 9`, a maradék 13 lépés fut, és a `writeLog` bizonyítja, hogy a bukott kulcs **pontosan egyszer** íródik (nincs replay) |
| A3 | **részben** | a write-fault ág mérve (`:177-244`), a **sérült bemenet ága nem** → MAJOR-1 |
| A4 | **teljesül** | `:249-280` — `openStore` → `Failure` → `BootstrapFailure`, és a `loadOnboardingSeen` sentinel bizonyítja, hogy store-hozzáférés nem történt |
| A5 | **teljesül** | `:285-339` — `applied` id-lista sorrendhelyesen pinnelve, kulcsonkénti rekordszámok |
| A6 | **teljesül** | `test/ui/ui_inventory_test.dart` a gate-ben zöld, a diff nem érint UI-t |
| A7 | **teljesül** | `fixture_manifest_test.dart` 48 → 51; a security-reviewer a három `sha256`/`bytes` értéket függetlenül újraszámolta, mind egyezik; a hunk KIZÁRÓLAG a számot érinti, egyetlen `expect` sem tűnt el |

**Valódi-sértés próba (brief §6.1):** az implementer a §10-ben dokumentálta. A saját,
független próbám (§2) ettől eltérő irányból mér, és a MAJOR-1-et hozta.

## 4. Architektúra és termékhatárok

- `lib/**` és `test/support/**` **érintetlen** (a diff `--name-only` nem tartalmazza őket).
- A `test/core/storage/in_memory_key_value_store.dart` `failingKeys`/`writeLog`
  hibainjektálása **pre-existing** test double, nem e körben keletkezett (`git diff
  --name-only origin/main...HEAD | grep in_memory` → üres).
- Valós lemez-/SharedPreferences-írás nincs: minden cella injektált `openStore`-ral fut,
  a `File(...)` hívás csak fixture-t olvas.
- Titok-szivárgás nincs (gate `secrets` zöld + security-reviewer).

## 5. NOTE — a gate-őr hook egy fals pozitívja (nem a kör hibája)

A `.claude/hooks/protect_factory_files.py` `_bash_write_targets()` függvénye nem bontja a
parancsot `&&` mentén, ezért egy `rm -rf <tmp-könyvtár> && … && tools/round-gate.sh …`
alakú lánc esetén az `rm` **minden** későbbi tokent operandusnak vesz, és a
`tools/round-gate.sh` „írás-célpontként" blokkolódik (H-GATEGUARD üzenet). Mérve
2026-09-02, a `_bash_write_targets` közvetlen futtatásával. Nem a kör diffjének hibája, és
külön parancsokra bontással megkerülhető — de az önjavító sávnak érdemes tudnia róla.

## 6. Merge-döntés

**(1. kör)** MERGE TILOS, amíg a MAJOR-1 nyitva van. A javító kört ugyanaz a motor
(`sonnet-impl`) viszi, a fenti leletlistával — ez a lánc NORMÁL útja (ADR 0087 §2,
user-döntés 2026-07-31), nem halt-ok.

## 7. Javító kör — leletenkénti zárás (`37be8875`)

A javító kör egy commitot hozott: `37be8875` — 6 fájl, +316/−44, mind az
`allowed_paths`-on belül (`scope-audit` → **OK**, 10 path, 1 generated/ignored = ez a
review-jelentés, a dokumentált mentesség).

### MAJOR-1 — **ZÁRVA**

Új **A3b** cella (`test/e2e/upgrade_migration_test.dart:247-359`), amely a valódi
korrupciós utat hajtja, **injektált írás-hiba nélkül**, és négy dolgot pinnel:

1. a fixture ténylegesen malformált (`expect(() => jsonDecode(raw), throwsFormatException)`)
   — ez maga őrzi, hogy a cella ne csússzon vissza a write-fault ágra;
2. `report.failure` `null`, `toVersion` a végérték, mind a 22 lépés `applied` — a
   korrupció-átlátszóság **mérve, nem feltételezve**;
3. a nyers malformált bájtok bájtra azonosak maradnak a legacy kulcson, és az új kulcs
   NEM íródik ki — ez a valódi adatvesztés-őr;
4. `JsonDocumentStore.readBody()` → `null`, `reason:`-ben **„ISMERT KORLÁT (ADR 0487)"**
   megjelöléssel; plusz egy ellenpróba, hogy a korrupció a többi, jól formált dokumentumra
   NEM terjed át (a `songs` továbbra is nem üresen olvasható).

A korlát átvezetve a `docs/release/client-migration.md`-be és a brief §6/§6.1 tábláiba.

**Valódi-sértés próba a JAVÍTÁSON (magam futtattam, `/tmp/review2-e12-r23`):** a
`corrupted_storage.json` `user_setlists_v1` mezőjét visszaállítottam jól formáltra →
`flutter test test/e2e/upgrade_migration_test.dart` → **`+7 -1`**, és a bukó cella
PONTOSAN az A3b:

```
Failing tests:
  test/e2e/upgrade_migration_test.dart: A3b — a genuinely malformed legacy document
  does NOT make migrate() fail … returns null
```

A fixture visszaállítása után újra **`+8: All tests passed!`**. Az őr tehát bizonyítottan
a korrupciós utat méri, nem valami mást.

### MINOR-1 — **ZÁRVA**

A `corrupted_storage.json` `user_setlists_v1` értéke immár ténylegesen csonka JSON
(`…"name":"Solo practice",`), tehát a fájl neve igazzá vált. A `test/fixtures/manifest.json`
`bytes`/`sha256` bejegyzése és a `README.md` érintett szakasza együtt frissült — a
`fixture_manifest_test.dart` zölden méri.

### Gate újrafuttatás a javítás után (izolált `/tmp/review2-e12-r23` klón)

```
format / analyze / test×3 / architecture / secrets / l10n   → MINDEN GATE ZÖLD
```

### Verdikt

**APPROVED.** Nyitott BLOCKER/MAJOR/MINOR: **nincs**. A merge a zöld kapu (ADR 0052)
teljesülése után mehet: `full-gate.yml` + `router-ci.yml` `success` a merge SHA-n.
