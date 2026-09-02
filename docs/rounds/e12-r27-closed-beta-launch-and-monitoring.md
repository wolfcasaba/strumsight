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

**Motor:** Claude Sonnet 5 (`sonnet-impl`), branch
`sonnet-impl/e12-r27-closed-beta-launch-and-monitoring`.

### 10.1 Mit építettem

Az engedélyezett hat fájl mindegyike elkészült, egyenként commitolva:

| Fájl | Tartalom |
|---|---|
| `docs/beta/cohort-profiles.yaml` | 2 cohort (`internal`, `closed_beta`), összesen 32 flag-hozzárendelés a MÉRT 40-es katalógusból. Mind a 7 `high` flag `false` mindkét cohortban. A `closed_beta` cohort `labModeAvailable: true` — ez a §4.4/A4 dry-run alanya (egyetlen `low` kockázatú, bekapcsolt flag). |
| `tool/release/verify_beta_profile.py` | Stdlib + `import yaml` (modul-szinten, kemény függőség, precedens `build_ai_report.py:59`). A registryt regexszel olvassa fail-closed szerződéssel: `< 40` bejegyzés VAGY `FeatureFlagDefinition(` előfordulásszám ≠ sikeresen parse-olt hármasok száma → nem-nulla kilépés kimondott üzenettel. A1/A2/A3 validáció (exit 1), `--kill-switch <flag> --cohort <c>` read-only dry-run mód (exit 0, csak stdout, semmi lemezírás), formátum/használati hiba exit 2. |
| `test/tooling/beta_profile_test.dart` | 16 teszt-eset, A1–A6 lefedve (l. §10.2 leképezés). `Process.runSync('python3', …)` a valódi fán és ideiglenes könyvtárban épített ellenséges fixture-ökön (precedens: `rc_assembly_test.dart`, `security_scan_test.dart`) — fixture nincs commitolva. |
| `docs/beta/daily-triage-template.md` | `feedback-triage.md` kategóriáira/súlyosságára épül (nem duplikálja), napi 5-lépéses ritmus, KIMONDOTT döntési szabály: nyitott P0 (Blocker) / P1 (High) mellett nincs cohort-bővítés. Bemenetek kimondva: diagnosztikai bundle (`build_diagnostics_bundle.py`) + kézi visszajelzés; telemetria-gyűjtés MA nincs (kimondva, E12-R19-re hivatkozva). |
| `docs/beta/closed-beta-launch.md` | 14 pontos indítási ellenőrzőlista, minden pont MÉRT hivatkozással (A5); a §3-ban a valódi, lefuttatott kill-switch dry-run kimenete (A4, `<!-- beta-kill-switch-dry-run:begin/end -->` jelölőkkel körülvéve); §4 kimondja, mit NEM lehetett elvégezni ezen a boxon; §5 az üres emberi indítási mező. §1 „Status" bekezdés kimondja: a béta NEM indult el, az indítás emberi döntés (A6). |
| `docs/rounds/e12-r27-closed-beta-launch-and-monitoring.md` | ez a §10 szakasz. |

### 10.2 Mérce-mátrix leképezés (A1–A6 → `beta_profile_test.dart` csoportok)

- **A1** — „A1 — the shipped profile validates…" csoport: exit 0 a valódi fán + registry-parse fail-closed cella (5 bejegyzésre csonkolt registry-másolat temp-ben → nem-nulla kilépés, üzenetben „expected >= 40").
- **A2** — „A2 — an unknown flag name…" csoport: temp-profil elgépelt `accountEnabldTypo` kulccsal → nem-nulla kilépés, stderr tartalmazza a kulcsnevet.
- **A3** — „A3 — a high-risk flag…" csoport: temp-profil `communityWritesEnabled: true`-val → nem-nulla kilépés; PLUSZ egy regex-alapú cella, amely a SZÁLLÍTOTT `cohort-profiles.yaml`-ban ellenőrzi mind a 7 ismert `high` flag `false` állapotát.
- **A4** — „A4 — the kill-switch dry-run…" csoport, 4 cella: (a) read-only — temp-profil bájtazonos marad, nem keletkezik új fájl a temp könyvtárban; (b) pontosan egy sor különbözik a before/after blokk között; (c) ismeretlen `--cohort`/`--kill-switch` → nem-nulla kilépés; (d) a `closed-beta-launch.md` beágyazott blokkja bájtazonos (trim-elve) a tool friss stdout-jával — ÚJRA lefuttatja a tool-t és összeveti.
- **A5** — „A5 — every launch-checklist line…" csoport: a valódi dokumentum minden ellenőrzőlista-sora (többsoros elemek is, 6 szóköz behúzású folytatással összefűzve) hordoz felismert hivatkozást (backtick-es repó-relatív útvonal, `existsSync()`-kel ellenőrizve, VAGY URL); hiányzó vagy lógó hivatkozás → PIROS. Két mutáció-próba (nincs hivatkozás; nem létező útvonal) + egy önteszt (létező útvonal nem jelez hibát) + méret-önteszt (≥ 8 elem).
- **A6** — „A6 — the document states…" csoport: a dokumentum tartalmazza („has not launched", „human decision"), és NEM tartalmazza a múltidejű indítás-állítások egyikét sem (kis-nagybetű-érzéketlen lista, angol + magyar variánsokkal).

### 10.3 `verify_beta_profile.py` valódi kimenete (szállított profil)

```
$ python3 tool/release/verify_beta_profile.py --profile docs/beta/cohort-profiles.yaml
verify_beta_profile: ok — 32 flag assignment(s) across 2 cohort(s), all present in a 40-entry registry
```

Exit code: 0.

### 10.4 Kill-switch dry-run — valódi kimenet

Parancs: `python3 tool/release/verify_beta_profile.py --profile docs/beta/cohort-profiles.yaml --kill-switch labModeAvailable --cohort closed_beta`. A teljes, valódi stdout a `closed-beta-launch.md` §3-ban van rögzítve (`<!-- beta-kill-switch-dry-run:begin/end -->` jelölők között) — a `beta_profile_test.dart` A4 csoportjának utolsó cellája ezt a blokkot ÚJRA-futtatással veti össze, tehát a dokumentum kimenete nem állítás, hanem mérés.

### 10.5 Valódi-sértés próba (brief §6, KÖTELEZŐ)

1. **Mutáció:** a szállított `docs/beta/cohort-profiles.yaml`-ban az `internal` cohort `accountEnabled: false` sorát `accountEnabledXYZ: false`-ra cseréltem (`sed`/python string-replace, első előfordulás).
2. **Direkt tool-futás a sabotált fájlon:** `python3 tool/release/verify_beta_profile.py --profile docs/beta/cohort-profiles.yaml` → `verify_beta_profile: 1 finding(s): - cohort 'internal': flag 'accountEnabledXYZ' does not exist in the feature flag registry (A1/A2)`, exit 1.
3. **`flutter test test/tooling/beta_profile_test.dart` a sabotált fán:** az „A1 — … exit 0 on the real tree" cella PIROSRA váltott (`Expected: <0> Actual: <1>`), minden más cella (A2–A6, beleértve az A3 „szállított profil" cellát is, mert az csak a 7 `high` flagre néz, nem az `accountEnabled` kulcsra) ZÖLD maradt — pontosan az elvárt A1/A2 szelektivitás.
4. **Visszaállítás:** a fájlt az eredeti (utolsó commitolt) tartalomra állítottam vissza; `diff` a mentett eredetivel üres, `git status --short docs/beta/cohort-profiles.yaml` tiszta (nincs diff a HEAD-hez képest).
5. **Újra-zöldítés bizonyítéka:** `tools/round-gate.sh test/tooling/beta_profile_test.dart test/core/feature_flags/feature_flag_registry_test.dart` a visszaállítás UTÁN mind a 7 lépésre (`format`, `analyze`, mindkét teszt-útvonal, `architecture`, `secrets`, `l10n`) ZÖLD-öt adott — l. §10.6.

### 10.6 Záró gate — a teljes, csonkítatlan futás

```bash
tools/round-gate.sh test/tooling/beta_profile_test.dart test/core/feature_flags/feature_flag_registry_test.dart
```

Eredmény: `format` zöld, `analyze` zöld (0 finding), `test test/tooling/beta_profile_test.dart` zöld (16/16), `test test/core/feature_flags/feature_flag_registry_test.dart` zöld (16/16), `architecture` zöld, `secrets` zöld (0 finding, 4151 fájl), `l10n` zöld. „MINDEN GATE ZÖLD."

### 10.7 Amit ez a kör NEM végzett el ezen a boxon, és miért

- **Nem futott APK-build és nem történt telepítés.** A jelölt/RC artefaktum összeállítása a Kör 25 (`tool/release/assemble_rc.py`, `.github/workflows/release-apk.yml`) dolga; ez a kör a konfigurációt készíti, nem az artefaktumot.
- **Nem történt valódi tesztelő-meghívás és cohort-megnyitás.** Ez a §0.0 EMBERI KAPU szerint szándékosan a user döntése és művelete — a `closed-beta-launch.md` §5 emberi mezője ezért maradt üresen.
- **`maxTesters`/`versionRange` nincs kódban kikényszerítve.** Operatív fegyelem kérdése, ahogy a `docs/beta/enrollment.md` már kimondja a cohort-tagságra nézve is.
- **Nincs élő monitoring-dashboard.** A Kör 19 csak szerződést szállított, gyűjtést nem — ezt a `closed-beta-launch.md` §2 és a `daily-triage-template.md` is kimondja, nem állít mást.
- **A teljes `flutter test` suite + randomizált property gate + APK nem futott itt** — az ADR 0053 szerint ez CI-feladat (`gh workflow run build-apk.yml`), amit az orchestrátor indít, nem az implementer.

### 10.8 Javító kör (fix1) — a review leleteinek javítása

**Alap:** `docs/reviews/e12-r27-review.md` §2–3, verdikt CHANGES REQUESTED (1 MAJOR,
1 MINOR, 2 NOTE nélkül javítás). Engedélyezett fájlok: `test/tooling/beta_profile_test.dart`
és ez a szakasz.

**MAJOR-1 (az A5 őr fail-OPEN a kipipált sorokra) — javítva.**
`_splitChecklistItems` bullet-mintáját (`beta_profile_test.dart:384`)
`RegExp(r'^- \[ \] (.*)$')`-ról `RegExp(r'^- \[[ xX]\] (.*)$')`-re cseréltem —
a kipipált (`- [x]`/`- [X]`) és a kipipálatlan (`- [ ]`) sor egyaránt
felismert bullet-ként, a 6 szóköz behúzású folytatás-sor kezelése
változatlan. Két ÚJ mérő-cella került az A5 csoportba, a meglévő
kipipálatlan mutáció-próbák MELLÉ (nem helyettük):

- „mutation probe: a CHECKED (- [x]) line referencing a non-existent
  repo-relative path is flagged (fail-open guard, L566)" — egy `- [x]`
  kezdetű, nem létező `docs/beta/NOPE-does-not-exist.md` útvonalra hivatkozó
  fixture-sorra `findChecklistReferenceProblems` nem-üres listát ad.
- „mutation probe: a CHECKED (- [x]) line referencing a real path is NOT
  flagged" — egy `- [x]` kezdetű, LÉTEZŐ (`docs/beta/cohort-profiles.yaml`)
  útvonalra hivatkozó sor NEM jelez hibát, tehát a javítás nem lőtt túl.

A helper doc-kommentjét (`beta_profile_test.dart:368-381`) frissítettem: a
„- [ ] ... OR - [x] ..." alak mindkettőt lefedi, és kimondja, hogy a
fail-closed szerződés a kipipált sorra érvényesül a leginkább — épp akkor,
amikor egy ember már kipipálta és megbízna benne.

**MINOR-1 (az A3 szállított-profil regex a kettőspont előtt nem enged
szóközt) — javítva.** A mintát (`beta_profile_test.dart:128`, a fix után
kb. 133. sor) `'^\\s*$flag:\\s*true\\s*\$'`-ról `'^\\s*$flag\\s*:\\s*true\\s*\$'`-re
cseréltem — `\s*` most a kettőspont ELŐTT is megengedett, tehát az
`accountEnabled : true` alakot is elkapja. A cella fölé egy megjegyzést
írtam, amely kimondja: ez másodlagos backstop, az elsődleges mérés az A1
„exit 0 a valódi fán" cella (az futtatja a tool-t, tehát a PyYAML-lel
parse-olt igazságot méri).

**NOTE-1 / NOTE-2 — nem javítottam**, a review kifejezetten nem kért
javítást rájuk.

**Regressziós önpróba (a MAJOR-1 javítás valódi hatásának bizonyítéka):**

1. Mutáltam a szállított `docs/beta/closed-beta-launch.md` 26. sorát:
   `- [ ] Cohort profile exists and is schema-valid — \`docs/beta/cohort-profiles.yaml\`.`
   →
   `- [x] Cohort profile exists and is schema-valid — \`docs/beta/NOPE-does-not-exist.md\`.`
   (kipipált, nem létező útvonalra hivatkozó sor — pontosan a review 1. próbája).
2. `tools/round-gate.sh test/tooling/beta_profile_test.dart` a mutált fán:
   a `[3] test` lépés **PIROSRA váltott** (kilépési kód 1), konkrétan az
   „A5 — … the real document has no unreferenced or dangling-reference
   checklist lines" cella bukott —
   `Expected: empty` / `Actual: [dangling path reference: Cohort profile
   exists and is schema-valid — \`docs/beta/NOPE-does-not-exist.md\`.]`
   — tehát a javítás UTÁN a review 1. próbájában mért fail-OPEN eltűnt.
3. Visszaállítás: `git checkout -- docs/beta/closed-beta-launch.md`; a fájl
   bájtazonos a mutáció előtti (utolsó commitolt) tartalommal (`diff` a
   mentett másolattal üres).
4. Újra-zöldítés: `tools/round-gate.sh test/tooling/beta_profile_test.dart
   test/core/feature_flags/feature_flag_registry_test.dart` a visszaállítás
   UTÁN mind a 7 lépésre (`format`, `analyze`, mindkét teszt-útvonal 18/18
   ill. 16/16, `architecture`, `secrets`, `l10n`) ZÖLD-öt adott —
   „MINDEN GATE ZÖLD."

**Záró gate (fix1, a tényleges javítás után, csonkítatlan):**

```bash
tools/round-gate.sh test/tooling/beta_profile_test.dart test/core/feature_flags/feature_flag_registry_test.dart
```

Eredmény: `format` zöld, `analyze` zöld (0 finding), `test
test/tooling/beta_profile_test.dart` zöld (18/18 — a két új A5 cellával),
`test test/core/feature_flags/feature_flag_registry_test.dart` zöld
(16/16), `architecture` zöld, `secrets` zöld, `l10n` zöld. „MINDEN GATE
ZÖLD."

## 11. Review — a Claude tölti ki
