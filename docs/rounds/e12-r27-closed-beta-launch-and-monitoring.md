# E12-R27 — Closed Beta launch és monitoring

- **Státusz:** PREPARED (előre megírva 2026-08-27, kód olvasva: `main @ 9ca4a0dc`)
- **Típus:** Chapter 12 (Release Roadmap, Sprint Planning & Final Integration), Kör 27
- **Kör-azonosító:** `E12-R27`
- **Branch:** `<motor>/e12-r27-closed-beta-launch-and-monitoring`
- **Előfeltétel:** `E12-R22`, `E12-R25` és `E12-R26` merge-elve (terjesztés, RC-csomag, bizonyított rollback)
- **Brief szerzője:** Claude (Opus 5)
- **Előre kiosztott ADR:** nincs — a kör indítási eljárást és mérő-eszközt szállít; a hivatkozott szerződéseket korábbi ADR-ek rögzítik.

**Visszakeresett előzmény:** `node tools/knowledge-rag.mjs --corpus lessons,halts,adr --top 5 "closed beta launch monitoring triage kill switch dry run"` → **[ADR 0395](../adr/0395-community-baseline-feature-flags-and-threat-model-scope.md)** (a kill switch operábilis marad, a hardcode-false lezárás külön GOV-kör). A béta-indítás flag-profilja tehát MŰKÖDŐ kapcsolókra épül, és a visszakapcsolás nem igényel új buildet.

> ⚠ **Pre-flight (indítás előtt KÖTELEZŐ):** ellenőrizd, hogy a Kör 22 `docs/beta/` csomagja, a Kör 25 RC-workflow-ja és a Kör 26 jegyzőkönyve MEGVAN, és hogy a Kör 5 flag-katalógus tartalmazza a béta-profilhoz szükséges MINDEN kapcsolót. Hiány esetén a kör nem indítható (`blocked` jelzés).

## 0.0 EMBERI KAPU — mit csinál az implementer, és mit a user

A Closed Beta INDÍTÁSA (tesztelők meghívása, artefaktum publikálása, cohort megnyitása) **user-döntés és user-művelet** — ugyanaz a kapu-típus, mint a valós gitáros APK-teszt. Az implementer terméke ezért:

1. a béta-profil KONFIGURÁCIÓJA (flag-profil fájl + ellenőrzés),
2. a napi triage sablon és a hozzá tartozó, gépileg ellenőrizhető metrika-lista,
3. a kill-switch **száraz próbája** (dry-run) egy biztonságos feature-en, bizonyított kimenettel,
4. az indítási ellenőrzőlista, amelynek minden pontja a fán MÉRT bizonyítékra hivatkozik.

A kör NEM jelenti azt, hogy a béta elindult; a `docs/beta/closed-beta-launch.md` „indításra kész / elindult" mezőjét a user tölti ki.

```ai-router
schema_version = 1
risk = "normal"
allowed_paths = [
  "docs/beta/closed-beta-launch.md",
  "docs/beta/daily-triage-template.md",
  "docs/beta/cohort-profiles.yaml",
  "tool/release/verify_beta_profile.py",
  "test/tooling/beta_profile_test.dart",
  "docs/rounds/e12-r27-closed-beta-launch-and-monitoring.md",
]
gate_tests = [
  "test/tooling/beta_profile_test.dart",
  "test/core/feature_flags/feature_flag_registry_test.dart",
]
native_gate = false
```

## 0.0.1 Pre-flight brief-revízió (orchestrátor, 2026-09-02, `main @ 02d0e36e`)

**Ahol ez a szakasz és bármely későbbi szakasz eltér, EZ nyer.** ADR nincs
(a kör indítási eljárást és mérő-eszközt szállít; `docs/adr/**` tiltott zóna) —
a hivatkozott szerződések: [ADR 0446](../adr/0446-feature-flag-registry-and-emergency-kill-switch.md)
(flag-katalógus, feloldási lánc, D7 „a kikapcsolás nem töröl adatot"),
[ADR 0395](../adr/0395-community-baseline-feature-flags-and-threat-model-scope.md)
(a kill switch MA operábilis, dart-define/env úton felülírható).

**Visszakeresés (ADR 0312, szűkítve → teljes korpusz):**
`--corpus lessons,halts,adr "closed beta launch monitoring triage kill switch dry run cohort profile"`
→ [ADR 0395](../adr/0395-community-baseline-feature-flags-and-threat-model-scope.md)
(bm25#7 emb#1), [ADR 0486](../adr/0486-beta-distribution-consent-and-redacted-diagnostics-bundle.md)
(bm25#1 emb#3 — a béta-artefaktumok GÉPI igazságforrásra épülnek, hiányzó
kulcs → nem-nulla kilépés, „unknown"-nal továbbmenetel helyett).
`--corpus lessons,halts "python tool parses dart registry yaml profile validation exit code test"`
→ **[L566](../LESSONS.md#l566)** (bm25#4 emb#4) — **ez a kör legfontosabb
előzménye**: egy kézzel írt sor-parszerre épülő doksi-/YAML-őr alapértelmezésben
**fail-OPEN**; ami nem illeszkedik a mintára, az nem hibás, hanem NEM LÉTEZIK.
Az E12-R19 pontosan így engedett át egy őrizetlen SLO-bejegyzést. Továbbá
[L86](../LESSONS.md#l86) (beágyazott Dart tool-package analyzer-csapdái —
ezért a `tool/release/` gyökérben egyetlen fájl, nem új package).

### P1 — A „Kör 5 flag-katalógus" a **Dart registry**, nem a markdown tábla

MÉRVE (`main @ 02d0e36e`):

| Mért tény | Parancs / hely |
|---|---|
| `lib/core/feature_flags/feature_flag_registry.dart` = **40** bejegyzés | `grep -c "key: '" lib/core/feature_flags/feature_flag_registry.dart` → `40` |
| **7** `high` kockázatú bejegyzés: `accountEnabled`, `diagnosticsEnabled`, `aiTutorCloudEnabled`, `visionLabCaptureEnabled`, `communityEnabled`, `communityWritesEnabled`, `communityMediaEnabled` | `grep -B6 "FeatureFlagRisk.high" …registry.dart \| grep "key:"` |
| `grep -c "FeatureFlagRisk.high"` **8**-at ad — a 8. találat a fájl fejléc-doc-commentjének szövege, NEM bejegyzés | `sed -n '26,32p' …registry.dart` |
| mind a 40 bejegyzés `failClosedDefault: false` | `grep -c "failClosedDefault: false"` |
| a besorolás enum: `FeatureFlagRisk { low, medium, high }` | `lib/core/feature_flags/feature_flag_definition.dart:9` |
| a bejegyzés mezői: `key`, `owner`, `risk`, `failClosedDefault`, `killSwitchPath`, opcionális `adr`, `expiresOn` | `feature_flag_definition.dart:20-27` |

**`docs/release/kill-switches.md` NEM az igazságforrás** — a saját fejléce
mondja ki: „magát ezt a markdown táblát ma semmi nem méri". Az A1/A3 cellák
igazságforrása a **Dart registry**; a `verify_beta_profile.py` azt olvassa.
(Ez amúgy is tiltott zóna: `docs/release/**` nincs az `allowed_paths`-on.)

### P2 — Parser-fegyelem: PyYAML a profilhoz, **fail-closed** regex a registryhez (L566)

1. A `cohort-profiles.yaml`-t **PyYAML-lel** parse-old (`import yaml`
   modul-szinten, KEMÉNY függőség). Precedens és CI-bizonyíték:
   `tool/release/build_ai_report.py:59` ugyanígy importál, és a
   `test/tooling/ai_release_report_test.dart` a teljes `flutter test` kapuban
   futtatja — a CI-n tehát MA is zölden fut PyYAML-lel. Kézzel írt sor-parszer
   a YAML-hez **TILOS** (L566).
2. A Dart registry oldalán regex-parse-olsz (Dartot futtatni innen nem lehet).
   Ez a L566 hibaosztály veszélyzónája, ezért **fail-closed** szerződés:
   - a parse-olt bejegyzésszám `< 40` → **nem-nulla kilépés** kimondott
     hibaüzenettel („registry parse yielded N entries, expected >= 40"), NEM
     csendben kisebb katalógus;
   - bármely bejegyzés, amelyből a `key` / `risk` / `failClosedDefault`
     hármas nem olvasható ki → **hiba**, nem kihagyás;
   - a profilban minden olyan sor, amely nem illeszkedik a várt alakra →
     **hiba**, nem „nem létező szabály".
3. Ugyanez köt a Dart-oldali doksi-olvasó cellákra (A5/A6): a fel nem ismert
   ellenőrzőlista-sor **PIROS**, sosem „nincs is ilyen sor".

### P3 — A cellák a TOOL-t futtatják, ellenséges fixture-ökön

Az A2/A3 nem bizonyítható a szállított profilon (az zölden fut). A
`beta_profile_test.dart` `Process.runSync('python3', [...])`-tal hívja a
tool-t ideiglenes könyvtárban felépített, SZÁNDÉKOSAN hibás profilokon
(elgépelt flag-név; `true`-ra állított `high` flag). Precedens:
`test/tooling/rc_assembly_test.dart:104`, `test/tooling/security_scan_test.dart:31`.
**Fixture-t NEM commitolsz** (`test/fixtures/**` nincs az `allowed_paths`-on) —
a temp-fát a teszt építi és takarítja.

### P4 — Az A4 „kill-switch dry-run" GÉPILEG mért alakja

A dry-run definíciója (a brief §5.3 „bizonyított kimenet" követelményének
mérhető alakja):

```bash
python3 tool/release/verify_beta_profile.py --profile docs/beta/cohort-profiles.yaml \
  --kill-switch <flag> --cohort <cohort>
```

Kötelező tulajdonságok, cellánként mérve:

- **read-only**: a `--kill-switch` mód SEMMIT nem ír a lemezre. A cella egy
  temp-be másolt profilon futtatja, és a futás után a fájl tartalma
  bájtazonos, új fájl nem keletkezett;
- **determinisztikus, before/after blokk** a stdout-on;
- **pontosan egy flag billen `false`-ra**, minden más bejegyzés változatlan;
- a dry-run alanya egy **`low` kockázatú, a cohortban BEKAPCSOLT** feature —
  egy `high` flag alapból `false`, azon a dry-run semmit nem bizonyítana;
- a `closed-beta-launch.md`-be beillesztett kimeneti blokk **bájtazonos** a
  tool tényleges stdout-jával: a cella újrafuttatja a tool-t és a dokumentum
  kódblokkjával veti össze. **Ez teszi a „bizonyított kimenetet" méréssé, nem
  állítássá.**

**„A kikapcsolt feature NEM tört adatot" (ADR 0446 D7):** ezt a kör NEM
duplikálja — a round-trip cella MÁR LÉTEZIK
(`test/tooling/rollback_policy_test.dart:86-129`, E12-R26 A3) és az „idegen
adattárat nem mutál" cella is
(`test/core/feature_flags/feature_flag_registry_test.dart:216-248`). Az A4
dokumentum-oldala EZEKRE hivatkozik mért bizonyítékként, a Dart-cella pedig
azt méri, hogy a dry-run maga nem ír a lemezre.

### P5 — Az A5 hivatkozás-cella: minden hivatkozott útvonalnak LÉTEZNIE kell

Az indítási ellenőrzőlista minden sora hordozzon egy repó-relatív útvonalat
vagy egy CI-run URL-t. A cella:

- minden sorból kiolvassa a hivatkozás(oka)t, és a repó-relatív útvonalakra
  `File`/`Directory` `existsSync()`-et mér — hiányzó út → PIROS;
- a hivatkozás NÉLKÜLI sor → PIROS (nem „nem ellenőrzött sor");
- a fel nem ismert alakú sor → PIROS (P2/3, L566).

Az előfeltétel-artefaktumok MÉRVE léteznek, tehát hivatkozhatók:
`docs/beta/{enrollment,tester-consent,feedback-triage}.md` (Kör 22),
`docs/release/rc-checklist.md` + `.github/workflows/release-apk.yml` +
`tool/release/assemble_rc.py` (Kör 25),
`docs/operations/disaster-recovery-drill.md` + `tool/release/verify_rollback.py` (Kör 26),
`docs/release/kill-switches.md` + `lib/core/feature_flags/feature_flag_registry.dart` (Kör 5).

### P6 — Az A6 megfogalmazás-cella

A dokumentum tartalmazzon kimondott mondatot arról, hogy **a béta NEM indult
el**, az indítás EMBERI döntés, és ezt a kört nem hajtja végre. A cella
kis-nagybetű-érzéketlenül tiltja a múltidejű indítás-állítást (pl.
„a béta elindult", „tesztelők meghívva", „beta launched", „testers invited",
„cohort opened") — a „indításra kész" / „ready to launch" alak megengedett.

### P7 — Monitoring-illúzió kimondva

A Kör 19 telemetria-SZERZŐDÉST szállított, gyűjtést nem (brief §2). A
`closed-beta-launch.md`-nek ezt **ki kell mondania**, és a napi triage
bemeneteként a diagnosztikai bundle-t
(`tool/release/build_diagnostics_bundle.py`) és a manuális visszajelzést
(`docs/beta/feedback-triage.md`) kell megneveznie. A P0/P1 nyitottság melletti
cohort-bővítés tilalma a `daily-triage-template.md` döntési szabálya.

### P8 — Előfeltételek MÉRVE megvannak

`docs/beta/{enrollment,tester-consent,feedback-triage}.md` (Kör 22),
`docs/release/rc-checklist.md` + `tool/release/assemble_rc.py` (Kör 25),
`docs/operations/disaster-recovery-drill.md` (Kör 26, 15 970 bájt),
`lib/core/feature_flags/feature_flag_registry.dart` 40 bejegyzéssel (Kör 5).
A `blocked` jelzés tehát csak VALÓDI, mért elakadásra jár, nem kényelemből.

## 0. Kör-jelzés és STOP-protokoll

```bash
tools/codex-signal.sh progress "<egy sor>"
tools/codex-signal.sh done "<egy sor>"
tools/codex-signal.sh stopped "<egy sor>"
tools/codex-signal.sh blocked "<egy sor>"
```

**STOP-protokoll:** ha az ellenőrzőlista egy pontjához nincs a fán MÉRHETŐ bizonyíték, a kimenet a `stopped` jelzés — „majd a béta alatt megnézzük" típusú pont nem kerülhet a listára.

## 1. Cél

A Closed Beta indítása legyen egyetlen, ellenőrzött konfigurációval és bizonyított vészkapcsolóval előkészítve, napi triage-eljárással — az indítás pillanata pedig maradjon explicit emberi döntés.

## 2. Jelenlegi állapot — mért tények

- `docs/beta/`: a Kör 22 után `enrollment.md`, `tester-consent.md`, `feedback-triage.md`; `closed-beta-launch.md` és `cohort-profiles.yaml` **nincs**.
- A flag-katalógus (Kör 5) és a kill-switch dokumentáció (Kör 5) MEGVAN; a flagek dart-define/env úton felülírhatók (ADR 0395).
- Telemetria: a Kör 19 SZERZŐDÉST szállított, tényleges gyűjtést NEM — a béta-monitoring ezért a diagnosztikai bundle-re és a manuális visszajelzésre épül. Ezt a `closed-beta-launch.md` mondja ki.
- A repóban MA nincs publikált béta-csatorna (Kör 1 audit).

## 3. Scope

**Benne van:** `docs/beta/cohort-profiles.yaml` (cohortonként: engedélyezett feature-flagek, verzió-tartomány, létszám-korlát) · `tool/release/verify_beta_profile.py` (a profil MINDEN flagje létezik a Kör 5 katalógusban; a magas kockázatú flagek alapból KI vannak kapcsolva; ismeretlen flag → nem-nulla kilépés) · `test/tooling/beta_profile_test.dart` · `docs/beta/daily-triage-template.md` (kategóriák, súlyosság, döntési szabály: nyitott P0/P1 mellett NINCS cohort-bővítés) · `docs/beta/closed-beta-launch.md` (indítási ellenőrzőlista MÉRT bizonyíték-hivatkozásokkal, a kill-switch dry-run kimenetével, és az EMBERI indítási mezővel).

**NINCS benne (tilos):**

- Tényleges tesztelő-meghívás, publikálás vagy cohort-megnyitás.
- `lib/**` vagy `.github/**` módosítás.
- Új flag bevezetése (csak a MEGLÉVŐK profilba rendezése).
- `docs/adr/**`.

## 4. Engedélyezett fájlok

| Útvonal | Indok |
|---|---|
| `docs/beta/cohort-profiles.yaml` | ÚJ — cohort↔flag profil |
| `tool/release/verify_beta_profile.py` | ÚJ — profil-ellenőrző |
| `test/tooling/beta_profile_test.dart` | a §6 cellái |
| `docs/beta/daily-triage-template.md` | ÚJ — napi triage |
| `docs/beta/closed-beta-launch.md` | ÚJ — indítási ellenőrzőlista + emberi kapu |

**Tilos zóna:** `lib/**` · `.github/**` · `docs/beta/` meglévő fájljai · `docs/adr/**` · `tools/**`

## 5. Kötött architekturális döntések

Nincs ADR. Három kötelező szabály:

### 5.1 A profil MINDEN flagje létező katalógus-bejegyzés

**NEM elfogadható gyengítés:** „majd a build define-ja úgyis eldönti" — egy elgépelt flag-név némán semmit nem kapcsolna.

### 5.2 Magas kockázatú capability a béta-profilban alapból KI

**NEM elfogadható gyengítés:** „a tesztelők úgyis mindent látni akarnak" — a kockázati besorolás a Kör 5 katalógusából jön, nem a szándékból.

### 5.3 A kill-switch dry-run BIZONYÍTOTT kimenettel kerül a listára

**NEM elfogadható gyengítés:** „a mechanizmus tesztelt a Kör 5-ben" hivatkozás önmagában — ez a kör a béta-profilon futtatja le.

## 6. Acceptance criteria

| # | Kritérium | Bizonyíték |
|---|---|---|
| A1 | A cohort-profil minden flagje létezik a Kör 5 katalógusban | `beta_profile_test.dart` |
| A2 | Ismeretlen flag-név → `verify_beta_profile.py` nem-nulla kilépés | `beta_profile_test.dart` |
| A3 | Magas kockázatú flag a béta-profilban alapból `false` | `beta_profile_test.dart` |
| A4 | A kill-switch dry-run kimenete szerepel a `closed-beta-launch.md`-ben, és a kikapcsolt feature NEM tört adatot | `beta_profile_test.dart` + a dokumentum |
| A5 | Az indítási lista MINDEN pontja MÉRT bizonyítékra hivatkozik (fájl, futás vagy jegyzőkönyv) | a dokumentum + a teszt hivatkozás-cellája |
| A6 | A dokumentum kimondja: az indítás EMBERI döntés, és a kör azt nem hajtja végre | a dokumentum |

### 6.1 Mérce-mátrix — melyik hibás implementációt melyik cella fogja pirosra

| Hibás implementáció | Melyik cella vált PIROSRA |
|---|---|
| A profil elgépelt flag-nevet tartalmaz | A1/A2 |
| Egy magas kockázatú capability alapból bekapcsolva kerül a profilba | A3 |
| Az indítási lista „a béta alatt ellenőrizzük" pontot tartalmaz bizonyíték nélkül | A5 |
| A dokumentum úgy fogalmaz, mintha a kör elindította volna a bétát | A6 |

**Valódi-sértés próba (KÖTELEZŐ, a §10-ben dokumentálva):** írj a profilba egy nem létező flag-nevet, futtasd a §7 gate-et → az **A1**/**A2** cellának PIROSNAK kell lennie → állítsd vissza.

## 7. Kötelező ellenőrzések

```bash
tools/round-gate.sh test/tooling/beta_profile_test.dart test/core/feature_flags/feature_flag_registry_test.dart
```

A profil-ellenőrző közvetlen futtatása (kimenet a §10-be):

```bash
python3 tool/release/verify_beta_profile.py --profile docs/beta/cohort-profiles.yaml
```

## 8. Implementációs sorrend

1. `docs/beta/cohort-profiles.yaml` a MÉRT flag-katalógusból.
2. `tool/release/verify_beta_profile.py`.
3. `test/tooling/beta_profile_test.dart`.
4. A kill-switch dry-run futtatása és a kimenet rögzítése.
5. `daily-triage-template.md` + `closed-beta-launch.md` (emberi kapuval) + a valódi-sértés próba a §10-be.

## 9. Kockázatok

- **Látszat-indítás.** A dokumentum azt sugallhatja, hogy a béta elindult, holott az emberi lépés (A6).
- **Néma flag-elgépelés.** Egy nem létező kapcsoló profilban semmit nem kapcsol (A1).
- **Monitoring-illúzió.** Telemetria-gyűjtés nélkül a „monitoring" a diagnosztikai bundle-re és a visszajelzésre korlátozódik — ezt a dokumentum mondja ki, nem hallgatja el.

## 10. Implementation handoff — az implementer tölti ki

## 11. Review — a Claude tölti ki
