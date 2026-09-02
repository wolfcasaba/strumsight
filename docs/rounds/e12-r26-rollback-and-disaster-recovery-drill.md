# E12-R26 — Rollback és disaster recovery rehearsal

- **Státusz:** PRE-FLIGHT KÉSZ (előre megírva 2026-08-27; §0.0 revízió 2026-09-02, kód újramérve: `main @ 5effc542`)
- **Típus:** Chapter 12 (Release Roadmap, Sprint Planning & Final Integration), Kör 26
- **Kör-azonosító:** `E12-R26`
- **Branch:** `<motor>/e12-r26-rollback-and-disaster-recovery-drill`
- **Előfeltétel:** `E12-R08` és `E12-R25` merge-elve (staging recovery alap; RC-artefaktum, amire visszaállni lehet)
- **Brief szerzője:** Claude (Opus 5)
- **Előre kiosztott ADR:** nincs — a kör GYAKORLATOT és ellenőrző eszközt szállít; a szerződéseket az ADR 0449 (staging/recovery) és ADR 0446 (kill switch) rögzíti.

**Visszakeresett előzmény:** `node tools/knowledge-rag.mjs --corpus lessons,halts,adr --top 5 "rollback disaster recovery drill restore recovery time"` → nincs release-domain előzmény (a találatok — ADR 0352, [L68](../LESSONS.md#l68) — más terület recovery-fogalmai); a kör a Kör 8 saját runbookjaira épül, és ez a projekt ELSŐ rollback-gyakorlata.

> ⚠ **Pre-flight (indítás előtt KÖTELEZŐ):** olvasd újra a Kör 8-ban készült `docs/operations/backend-deploy.md` és `database-recovery.md` lépéseit, valamint a Kör 5 kill-switch útjait (`docs/release/kill-switches.md`). A gyakorlat EZEKET futtatja végig — ha egy lépés a valóságban nem elvégezhető, az LELET.

## 0.0 Mi gyakorolható itt, és mi nem

Felhő-infrastruktúra nincs a boxon, tehát a gyakorlat LOKÁLIS: konténer-image visszaállítás, adatbázis-restore ideiglenes célra, feature-flag kikapcsolás hatásának mérése, modell-verzió visszaállítás. A tényleges production rollback (élő forgalom mellett) a Kör 31–33 operátori lépése. A kör értéke a MÉRT recovery-idő és a runbook-hibák felfedezése.

```ai-router
schema_version = 1
risk = "high"
allowed_paths = [
  "tool/release/verify_rollback.py",
  "docs/operations/disaster-recovery-drill.md",
  "backend/tests/test_rollback_drill.py",
  "test/tooling/rollback_policy_test.dart",
  "docs/rounds/e12-r26-rollback-and-disaster-recovery-drill.md",
]
gate_tests = [
  "test/tooling/rollback_policy_test.dart",
  "test/core/feature_flags/feature_flag_registry_test.dart",
]
native_gate = false
```

**Kockázat = high, indoklás:** a gyakorlat adatbázis-visszaállítást futtat; egy hibás script fejlesztői adatot semmisíthet meg, és a Kör 8 §5.2 `--force` szabályát is próbára teszi. A `security-reviewer` futtatása a review-ban KÖTELEZŐ.

## 0.0.1 Pre-flight revízió (2026-09-02, orchestrátor: Claude/Opus 5) — KÖTELEZŐ OLVASNI

A pre-flight a brief MINDEN mért állítását újramérte `main @ 5effc542`-n. **Két
acceptance-cella premisszája MÉRHETŐEN HAMIS volt** — mindkettő az ADR 0087 §2
szerinti, dokumentált §0.0 revízióval oldva, listatágítás NÉLKÜL (az
engedélyezett-fájllista változatlan). Az implementer az ALÁBBI, revideált
szöveget valósítja meg, nem a §6 eredeti szövegét.

**Visszakeresés (ADR 0312, szűkítve → teljes):** `adr/0487` D1 (a „nincs
adatvesztés" invariáns SZÁMSZERŰ: rekordszám + azonosító-halmaz, az „elindul,
tehát rendben" cella nem bizonyíték) · [L534](../LESSONS.md#l534) (egy flag-alapértelmezés
átbillentése 19 fájlban 53 cellát tesz pirosra — ezért nem nyúlunk `lib/**`-hoz) ·
[L566](../LESSONS.md#l566) (fail-OPEN hibaosztály: a csendben átengedett dimenzió
„zölden" hazudik) · `halts/E12-R05` (a Kör 5 kill-switch szerződése, ADR 0446 D1–D7).
SDD-forrás a gyakorlat forgatókönyvéhez: `docs/sdd/12-release-roadmap-final-integration.md`
§26.3 (rollback sorrend) és §26.1 (rollout decision packet: active flags,
migration version, model version, rollback target).

### P1 — **A4 premisszája HAMIS: flag-cache NEM létezik, merge-elt döntésből**

Mért tények:

- `lib/core/feature_flags/feature_flag_source.dart:72–75` doc-comment:
  „None of these steps caches a prior resolution or falls back to *the last
  known value*" — a `FeatureFlagResolver` **állapotmentes**.
- `docs/adr/0446-feature-flag-registry-and-emergency-kill-switch.md:96` (D2):
  „**NEM elfogadható gyengítés:** cache-elt »utolsó ismert érték« felhasználása".
- `grep -rn "cache" lib/core/feature_flags/ backend/app/` → egyetlen találat a
  fenti doc-comment; `grep -n -i "cache\|ttl\|propagat" docs/release/kill-switches.md`
  → **0 találat**.

Tehát a §6 „MÉRT cache-élettartam `T`" nem létezik és nem is mérhető ki. Egy
cache MEGÉPÍTÉSE `lib/**`-ot igényelne (a §4 tiltott zónája) és egy merge-elt
ADR-döntést fordítana meg → **H1/H2 halt** lenne, nem kör-munka.

**A4 revideált szövege:** *a távoli/vész-kikapcsolás a KÖVETKEZŐ feloldáskor
érvényre jut — a resolver két `resolve()` hívás között nem őriz állapotot,
ezért az elavulási ablak **0 feloldás** (`T = 0`).*

**Küszöb-cellahármas — a feloldás-INDEXEN, nem az órán** (`k` = az első
`resolve()` hívás a forrás átbillenése UTÁN; a határ INKLUZÍV):

| Cella | Bemenet | Elvárás |
|---|---|---|
| küszöb alatt (`k-1`) | az utolsó `resolve()` a billentés ELŐTT | a RÉGI (bekapcsolt) érték |
| pontosan a küszöbön (`k`) | az ELSŐ `resolve()` a billentés UTÁN | az ÚJ (kikapcsolt) érték |
| küszöb fölött (`k+1`) | minden további `resolve()` | az ÚJ (kikapcsolt) érték |

**A cella mérő voltának feltétele (enélkül nem falszifikál):** a hármast EGYETLEN,
végig ugyanazon `FeatureFlagResolver` példányon kell futtatni, olyan fake
forrással, amelynek `valueFor`/`fetch` visszatérése a hívások KÖZÖTT változik.
Két külön felépített resolver egy memoizáló implementációt sem tenne pirosra.

**Amit TILOS megismételni:** az `isFeatureFlagExpired` tegnap/ma/holnap
hármasa MÁR LÉTEZIK (`test/tooling/feature_flag_audit_test.dart:86–100`) — az A4
nem az `expiresOn` lejáratáról szól, és nem duplikálja azt.

### P2 — **A2 premisszája HAMIS: nincs API-verziózás a backendben**

Mért: `grep -rn "api_version\|API_VERSION\|min_client\|X-Client" backend/app/*.py`
→ egyetlen, nem ide tartozó találat (`tutor_openai_base_url`). A routerek
(`backend/app/routers/{auth,settings,diagnostics}.py`) **verziózatlan** útvonalakat
szolgálnak (`/auth/register`, `/auth/login`, `/settings`). „Előző kliens-verzió"
mint egyeztetett protokoll-verzió tehát nem létezik.

**A2 revideált szövege:** *a visszaállított — a BACKUPBAN rögzített migrációs
fejre épített — sémán a szállított kliens TÉNYLEGES végpont-halmaza működik:
`/auth/register` → `/auth/login` → hitelesített `/settings` olvasás, mind 2xx.*
A füst-cella a `create_app` + `TestClient` úton hajtja a visszaállított
adatbázis-FÁJLT (nem a `conftest.py` in-memory `client` fixture-jét — az
`Base.metadata.create_all`-lal épít, tehát a restore-t nem mérné).

**Amit TILOS megismételni:** a „cél-séma újabb, mint a backup" irány már mérve van
(`backend/tests/test_readiness_and_recovery.py::test_restore_rejects_target_schema_newer_than_backup`),
ahogy a `--force` + `--confirm-target` kettős megerősítés is.

### P3 — A1 bizonyítéka SZÁMSZERŰ (ADR 0487 D1)

A `verify_rollback.py` a visszaállítás UTÁN a **migrációs fejet** ÉS a
**táblánkénti rekordszámot** hasonlítja a backup-dumphoz. A „kapcsolódik, tehát
rendben" cella nem bizonyíték. Mért forrás a fejhez: `MigrationContext.configure(
connection).get_current_heads()` (ugyanaz, amit a `backend/scripts/backup.py:57`
használ); a rekordszámokhoz a dump táblánkénti sor-tömbje.

### P4 — A `verify_rollback.py` NÉGY dimenziója és a fail-closed szabály

| Dimenzió | Mért forrás |
|---|---|
| migrációs fej | élő DB `get_current_heads()` ↔ a dump `revision` mezője |
| rekordszám | élő DB táblánkénti `count` ↔ a dump táblánkénti sorszáma |
| modell-verzió | `assets/ml/model_manifest.json` (`schema_version`, `models[].filename/sha256`) ↔ a lemezen lévő `assets/ml/*.bin` `hashlib.sha256`-ja |
| flag-profil | egy ÁTADOTT, várt profil (`{"<flag kulcs>": <bool>}` JSON) ↔ egy ÁTADOTT, megfigyelt profil |

**Mért korlát a flag-profilra:** gépi olvasásra alkalmas flag-profil fájl a fán
**nem létezik** — a katalógus Dart (`lib/core/feature_flags/feature_flag_registry.dart`),
az operátori tábla próza (`docs/release/kill-switches.md`). A
`verify_rollback.py` ezért **nem parse-ol Dartot**; a profilt bemenetként kapja.

**Fail-closed szabály (a [L566](../LESSONS.md#l566) hibaosztály ellen):** hiányzó vagy
olvashatatlan bemenet **FAIL**, nem `SKIPPED`. Egy dimenzió KIZÁRÓLAG explicit
opt-out kapcsolóval hagyható ki (pl. `--no-flag-profile`), a kihagyás pedig
megjelenik a kimenetben ÉS a jegyzőkönyvben. Bármely `FAIL` → **nem-nulla
kilépési kód**. Minden dimenzióhoz mért eltelt idő tartozik (A5 bemenete).

### P5 — Az A5/A6 GÉPI mércét kap, nem prózai ígéretet

A `test/tooling/rollback_policy_test.dart` beolvassa a
`docs/operations/disaster-recovery-drill.md`-t, és állítja, hogy (a) minden
jegyzőkönyvezett lépéshez tartozik szigorú numerikus időtartam-minta
(`\d+(\.\d+)?\s*(s|ms)`), és (b) a jegyzőkönyv NEM tartalmaz becslés-jelölőt
(`kb.`, `~`, `approx`, `becsült`, `körülbelül`). Így az A5 mérhető, nem
bemondásos. A6-hoz: a jegyzőkönyvnek van „Felfedezett runbook-hibák" szakasza,
és az `git diff --stat` bizonyítja, hogy a Kör 8 scriptjei/runbookjai
VÁLTOZATLANOK (tiltott zóna).

### P6 — Az A3 a VISSZAKAPCSOLÁST is méri (nem duplikátum)

Mért: a „kikapcsolás nem mutál idegen adattárat" cella MÁR LÉTEZIK
(`test/core/feature_flags/feature_flag_registry_test.dart:216–220`). Az A3 új
tartalma ezért az ADR 0446 D7 második fele: *kikapcsolás → az adat megvan →
VISSZAkapcsolás → UGYANAZ az adat ismét elérhető* (round-trip), ami ma nincs mérve.

### P7 — ADR: nincs, és ez MÉRT döntés

A kör gyakorlatot és ellenőrző eszközt szállít; a szerződéseket a már merge-elt
ADR 0446 (D1/D2/D7) és ADR 0449 (D4/D5) hordozza. Az orchestrátor ADR-számot
**nem foglalt** (`tools/round-slots.py reserve-adr` nem futott). Precedens:
E12-R24 („dokumentum-csomag, ADR nincs", `cf7c6fb6`). Új ADR-t ez a kör nem ír;
merge-elt ADR-t nem módosít (az H1 lenne).

### P8 — Futtathatóság mérve (a gyakorlat nem papír-gyakorlat)

`cd backend && python3 -m pytest tests/test_readiness_and_recovery.py -q` →
**11 cella zöld** (2026-09-02, ezen a boxon); `python3 -c "import fastapi,
sqlalchemy, alembic"` → ok; pytest 8.4.2. A backup→restore→verify lánc tehát
TÉNYLEGESEN lefuttatható — a `stopped` jelzés (§0 STOP-protokoll) csak valódi,
MÉRT elakadásra jár, nem kényelemből.

**A restore célja MINDIG `tmp_path`/ideiglenes fájl** — a fejlesztői
`backend/strumsight.db` fájlt a gyakorlat nem érinti.

## 0. Kör-jelzés és STOP-protokoll

```bash
tools/codex-signal.sh progress "<egy sor>"
tools/codex-signal.sh done "<egy sor>"
tools/codex-signal.sh stopped "<egy sor>"
tools/codex-signal.sh blocked "<egy sor>"
```

**STOP-protokoll:** ha egy runbook-lépés MÉRHETŐEN nem elvégezhető, a kimenet a `stopped` jelzés és jelentés — a runbook „elméleti" javítása (a lépés átírása anélkül, hogy lefutott volna) TILOS.

## 1. Cél

Bizonyítani, hogy a kritikus visszaállítási lépések nem csak dokumentáltak, hanem MÉRT idővel és adat-ellenőrzéssel végrehajthatók.

## 2. Jelenlegi állapot — mért tények

- `docs/operations/`: a Kör 8 után `backend-deploy.md`, `database-recovery.md`, valamint a Community moderation runbook.
- `backend/scripts/{backup,restore}.py` a Kör 8 terméke; `tool/release/verify_rollback.py` **nem létezik**.
- A kill-switch utak a Kör 5 `docs/release/kill-switches.md`-ben; a flag-katalógus tesztje `test/core/feature_flags/feature_flag_registry_test.dart`.
- A modell-asset visszaállítás mai támpontja az `assets/ml/model_manifest.json` + `test/tooling/ml_asset_manifest_test.dart`.
- Gyakorlat (drill) dokumentum **nem létezik** — ez az első.

## 3. Scope

**Benne van:** `tool/release/verify_rollback.py` — a visszaállítás UTÁNI állapot ellenőrzése (migrációs fej, rekordszámok, flag-profil, modell-verzió), MÉRT idővel · `backend/tests/test_rollback_drill.py` (restore → ellenőrzés → előző kliens-API kompatibilitás füst-cellája) · `test/tooling/rollback_policy_test.dart` (kill-switch kikapcsolás NEM töröl adatot; a flag-cache lejárata után a kikapcsolás érvényre jut) · `docs/operations/disaster-recovery-drill.md` (a LEFUTTATOTT gyakorlat jegyzőkönyve: lépés, mért idő, eredmény, felfedezett runbook-hiba).

**NINCS benne (tilos):**

- Éles/felhő rollback végrehajtása.
- A Kör 8 scriptjeinek átírása (mérni szabad; hibát jelenteni kell).
- `lib/**` módosítás.
- `docs/adr/**`.

## 4. Engedélyezett fájlok

| Útvonal | Indok |
|---|---|
| `tool/release/verify_rollback.py` | ÚJ — a visszaállítás-ellenőrző |
| `docs/operations/disaster-recovery-drill.md` | ÚJ — a gyakorlat jegyzőkönyve |
| `backend/tests/test_rollback_drill.py` | a backend-oldali §6 cellák |
| `test/tooling/rollback_policy_test.dart` | a kliens-oldali §6 cellák |

**Tilos zóna:** `backend/scripts/**` · `backend/app/**` · `lib/**` · `.github/**` · `docs/operations/{backend-deploy,database-recovery}.md` · `docs/adr/**`

## 5. Kötött architekturális döntések

Nincs ADR. Két kötelező szabály:

### 5.1 A gyakorlat jegyzőkönyve MÉRT időt tartalmaz

Minden lépéshez tényleges, mért időtartam tartozik. **NEM elfogadható gyengítés:** becsült („kb. 5 perc") érték.

### 5.2 A kill switch NEM töröl adatot — ez a gyakorlat egyik mércéje

**NEM elfogadható gyengítés:** a takarítás „a tiszta állapot érdekében" (a Kör 5 §5.2 szabálya).

## 6. Acceptance criteria

| # | Kritérium | Bizonyíték |
|---|---|---|
| A1 | Backup → restore → `verify_rollback.py` után a migrációs fej és a rekordszámok egyeznek | `test_rollback_drill.py` |
| A2 | A szállított kliens TÉNYLEGES végpont-halmaza (`/auth/register` → `/auth/login` → hitelesített `/settings`) a visszaállított sémán 2xx-et ad — **§0.0.1 P2 szerint revideálva** (nincs API-verziózás a backendben) | `test_rollback_drill.py` |
| A3 | A kill switch kikapcsolás után az adat MEGMARAD, és VISSZAkapcsolás után ugyanaz az adat ismét elérhető (ADR 0446 D7 round-trip, §0.0.1 P6) | `rollback_policy_test.dart` |
| A4 | A távoli/vész-kikapcsolás a KÖVETKEZŐ feloldáskor érvényre jut (a resolver állapotmentes, elavulási ablak = 0 feloldás) — **§0.0.1 P1 szerint revideálva** (flag-cache nem létezik, ADR 0446 D2) | `rollback_policy_test.dart` |
| A5 | A jegyzőkönyv minden lépéshez MÉRT időt és eredményt rögzít, és ezt GÉPI cella állítja (§0.0.1 P5) | `rollback_policy_test.dart` + `docs/operations/disaster-recovery-drill.md` |
| A6 | A gyakorlat során talált runbook-hibák LELETKÉNT szerepelnek (nem csendben javítva); a Kör 8 scriptjei/runbookjai változatlanok | a jegyzőkönyv + `git diff --stat` |

**Küszöb-cellahármas — a §0.0.1 P1 táblája a kötelező alak** (a feloldás-indexen,
`k` = az első `resolve()` a forrás billentése után; a határ INKLUZÍV; EGYETLEN
resolver-példány, hívások között változó fake forrással). Az eredeti, órán
alapuló `T-1 / T / T+1` perc-hármas mérhetetlen: cache nincs.

### 6.1 Mérce-mátrix — melyik hibás implementációt melyik cella fogja pirosra

| Hibás implementáció | Melyik cella vált PIROSRA |
|---|---|
| A restore után csak a kapcsolat ellenőrzött, a migrációs fej nem | A1 |
| A restore után a fej egyezik, de a rekordszámok nem ellenőrzöttek | A1 (ADR 0487 D1, §0.0.1 P3) |
| Egy `verify_rollback.py`-dimenzió hiányzó bemenetre csendben `SKIPPED`-et ad és 0-val lép ki | A1 (fail-closed szabály, §0.0.1 P4) |
| A kill switch takarít (adatot töröl) | A3 |
| A visszakapcsolás nem teszi újra elérhetővé a megőrzött adatot | A3 (round-trip, §0.0.1 P6) |
| A resolver memoizálja az előző feloldást — a kikapcsolás a következő `resolve()`-ra nem hat | A4 (küszöb-cellahármas `k` cellája) |
| A jegyzőkönyv becsült („kb. 5 perc") időket tartalmaz | A5 (gépi minta-cella, §0.0.1 P5) |

**Valódi-sértés próba (KÖTELEZŐ, a §10-ben dokumentálva):** állítsd a `verify_rollback.py` migrációs fej ellenőrzését figyelmeztetésre, futtasd a §7 gate-et → az **A1** cellának PIROSNAK kell lennie → állítsd vissza.

## 7. Kötelező ellenőrzések

```bash
tools/round-gate.sh test/tooling/rollback_policy_test.dart test/core/feature_flags/feature_flag_registry_test.dart
```

Backend sáv (külön processzként):

```bash
cd backend && python -m pytest tests/test_rollback_drill.py -q
```

## 8. Implementációs sorrend

1. `tool/release/verify_rollback.py`.
2. `backend/tests/test_rollback_drill.py` (restore + kompatibilitás).
3. `test/tooling/rollback_policy_test.dart` (kill switch + cache-küszöb).
4. A gyakorlat LEFUTTATÁSA és a jegyzőkönyv írása MÉRT időkkel.
5. A valódi-sértés próba a §10-be.

## 9. Kockázatok

- **Adatvesztés a gyakorlat közben.** A restore ideiglenes célra menjen; a Kör 8 `--force` szabálya itt élesben próbálódik.
- **Papír-gyakorlat.** Mért idő nélkül a jegyzőkönyv nem bizonyíték (A5).
- **Csendes runbook-javítás.** A talált hiba elrejtése értékesebb információt semmisít meg, mint amennyit a javítás ér (A6).

## 10. Implementation handoff — az implementer tölti ki

## 11. Review — a Claude tölti ki
