# E08-R28 — Főkönyv-szinkron szerződés, összefésülés és igazolt státusz

- **Státusz:** PREPARED (előre megírva 2026-08-18, kód olvasva: `main @ ea6569fb`)
- **Típus:** Chapter 9 (Epic 8 — Gamification), Kör 28
- **Kör-azonosító:** `E08-R28`
- **Branch:** `<motor>/e08-r28-ledger-sync-contract-and-merge`
- **Előfeltétel:** `E08-R27` merge-elve (a11y és beállítások)
- **Brief szerzője:** Claude (Opus 5)
- **Előre kiosztott ADR:** ~~`ADR 0319`~~ **`ADR 0394`** — a `0319` STALE volt
  (a `reserve-adr` foglaló a valós állapotot mérte, ugyanaz a minta, mint az
  E08-R27 stale `0318`-ja). Az ADR-t a Claude írja meg a kör indítási
  pre-flightjában a §5 döntéseiből; az implementer a `docs/adr/`-t NEM érinti
  (TILOS zóna).

> ⚠ **Pre-flight (indítás előtt KÖTELEZŐ):** olvasd újra a `backend/` TÉNYLEGES szerkezetét (`backend/app/`, Alembic migrációk, `backend/tests/`) és a `lib/features/auth/` + `settings_sync.dart` mintáját — a fiók-kikapcsolt állapot ellenőrzése onnan jön. Eltérésnél
> §0.0 brief-revízió, NEM csendes lista-tágítás.

## 0.0 Pre-flight brief-revízió (2026-08-22, E08-R28 indítás)

**Kockázat = high, indoklás:** a kör két ÚJ backend-fájlt hoz létre
(`backend/app/gamification/schemas.py`, `service.py`) hálózati kérésbeérkező
kliens-adatot fogadó API-felülettel, és a szerződés maga a jutalom-integritás
biztonsági határa (a szerver soha nem fogadhat el kliens-oldali összesített
XP-t — 5.1). Egyik `allowed_paths` sem illeszkedik szó szerint a
`high_risk_path_fragments` mintáira, de a tartalmi kockázat (hamisítható
API-bemenet + fiók-kikapcsolt hálózat-tilalom, ami a `credential`/`auth`
osztály testvér-kockázata) indokolja a `risk = "high"`-at — dedikált
`security-reviewer` review kötelező.

**Mért kódtények (grep, a brief 2026-08-18-i olvasata óta nem driftelt):**
- `backend/app/gamification/` **valóban nem létezik** ma (`backend/app/`
  alatt csak `tutor/` és `routers/` van) — a brief 2. szakaszának állítása áll.
- `RewardLedgerEntry` (`lib/features/gamification/domain/rewards/reward_ledger_entry.dart`)
  ténylegesen két mezőt hordoz dedup-kulcsként: `ledgerId` (helyi keletkezésű
  azonosító) ÉS `sourceEventId` (a forrás-esemény azonosítója) — a §6.1
  küszöb-hármas ezt a két mezőt nevezi meg helyesen.
- `RewardLedgerRepository.hasProcessedEvent`/`appendIfAbsent`
  (`lib/features/gamification/data/reward_ledger_repository.dart`) a HELYI
  appendet ma kizárólag `sourceEventId`-re dedupolja — ez egy más réteg
  (helyi idempotencia), a szinkron-összefésülés (kettős kulcs) ÚJ szabály,
  nem ütközik a meglévővel.
- `accountEnabledProvider` (`lib/features/auth/providers/auth_providers.dart:18`)
  a mért fiók-kikapcsolt kapu — a `settings_sync.dart` ugyanezt olvassa a
  konstruktorban, mielőtt bármilyen listenert regisztrálna; az 5.4 szabály
  ugyanezt a mintát várja el a ledger-szinkrontól.
- `lib/features/gamification/public.dart` ma export-only barrel, nincs
  `sync/` alkönyvtár — a §4 "barrel-bővítés — CSAK export-sor" instrukció a
  jelenlegi szerkezettel konzisztens.

**Visszakeresés (ADR 0312, `node tools/knowledge-rag.mjs`):**
- **L140** (`node tools/knowledge-rag.mjs --corpus lessons,halts --top 5
  "backend account logged out zero network requests offline sync dedup
  idempotency"`, bm25#1 emb#2): az „offline ⇒ nincs cloud-hívás" garanciát a
  tényleges TURN-ÚTON, gateway/transport-spy-vel kell mérni, nem egy
  statikus képernyő-renderrel vagy egy már meglévő, más transportra épülő
  network-probe-bal — az A5 hálózat-cellának a ledger-szinkron SAJÁT
  transport-mockját kell hívnia, nem egy örökölt, vak probe-ot.
- Sem a szűkített (`lessons,halts,adr`), sem a teljes korpuszos keresés nem
  talált korábbi H-t vagy ADR-t, amely ennek a körnek a konkrét szerződését
  (unió-alapú dedup, verified/unverified szétválasztás, policy-verzió
  superseding) megkérdőjelezné vagy módosítaná — a brief §5 döntései állnak.

```ai-router
schema_version = 1
risk = "high"
allowed_paths = [
  "lib/features/gamification/data/sync/gamification_sync_contract.dart",
  "lib/features/gamification/data/sync/ledger_merge_policy.dart",
  "lib/features/gamification/public.dart",
  "backend/app/gamification/schemas.py",
  "backend/app/gamification/service.py",
  "test/features/gamification/data/ledger_merge_policy_test.dart",
  "backend/tests/test_gamification_ledger.py",
  "docs/rounds/e08-r28-ledger-sync-contract-and-merge.md",
]
gate_tests = [
  "test/features/gamification/data/ledger_merge_policy_test.dart",
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

Lezáró jelzés nélkül a kör bukott. **Listán kívüli fájl kellene → `stopped`**,
és a kimenet a brief-revízió kérése, nem az `allowed_paths` csendes tágítása.
Meglévő, ma zöld teszt elbukása → `blocked`, nem a teszt átírása.

## 1. Cél

Offline-first, **duplikációmentes** szinkron-szerződés a későbbi fiók- és közösségi
használathoz — a legfontosabb szabállyal: a **szerver soha nem fogad el kliens-oldali
összesített XP-t**.

## 2. Jelenlegi állapot — mért tények

- A `backend/` FastAPI + SQLite + JWT szolgáltatás (CLAUDE.md); ma login + felhő-beállítás szinkront kezel, a felismerés 100%-ban eszközön marad.
- A `settings_sync.dart` mért mintája: szinkronizáltnak jelölés CSAK szerver-megerősítés után, sikertelen küldés újrapróbálva.
- Az R03 főkönyve immutable, `sourceEventId`-re dedupál; az R07 profilja PROJEKCIÓ, nem forrás.
- `backend/app/gamification/` **nem létezik** — ez a kör hozza létre.

## 3. Scope

**Benne van:** az immutable nyugta fel- és letöltési szerződése · összefésülés a főkönyv-azonosító ÉS
a forrás-esemény azonosító alapján · a lokális **nem igazolt** és a szerver által **igazolt**
státusz szétválasztása · **nincs** teljes profil last-write-wins felülírás · policy-verzió
eltérés és felülíró (superseding) nyugta kezelése · fiók-kikapcsolt állapotban SEMMILYEN
hálózati kérés.

**NINCS benne (tilos):**

- A `backend/` bármely más moduljának módosítása; meglévő Alembic migráció átírása.
- Közösségi funkciók (Epic 9) — ez a kör csak a szerződést készíti elő.
- A felismerés vagy bármely gyakorlási adat felhőbe küldése — csak jutalom-nyugták mennek.
- `docs/adr/**` — az ADR 0394-et (a §0.0 szerint korrigált szám) a Claude írja.

## 4. Engedélyezett fájlok

| Útvonal | Indok |
|---|---|
| `lib/features/gamification/data/sync/gamification_sync_contract.dart` | **ÚJ** — a verziózott szerződés |
| `lib/features/gamification/data/sync/ledger_merge_policy.dart` | **ÚJ** — az összefésülés |
| `lib/features/gamification/public.dart` | barrel-bővítés — CSAK export-sor |
| `backend/app/gamification/schemas.py` | **ÚJ** — a szerver-oldali sémák |
| `backend/app/gamification/service.py` | **ÚJ** — a szerver-oldali logika |
| `test/features/gamification/data/ledger_merge_policy_test.dart` | a §6 Dart cellái |
| `backend/tests/test_gamification_ledger.py` | a §6 backend cellái |

**Tilos zóna:** `backend/` MINDEN más fájlja (meglévő migráció, auth, settings) · `lib/features/` többi feature-e · `lib/features/gamification/` nem felsorolt fájljai · `lib/core/**` · `lib/app/**` · `docs/adr/**` · `docs/sdd/**` · `tools/**` · `.github/**`

## 5. Kötött architekturális döntések (ADR 0394)

### 5.1 A SZERVER NEM FOGAD EL KLIENS-OLDALI ÖSSZESÍTETT XP-T

A kliens **nyugtákat** küld, nem összeget. A szerver a nyugtákból SAJÁT MAGA
számol összesítést. Egy `totalXp` mező elfogadása triviálisan hamisítható.

**NEM elfogadható gyengítés:** „gyorsítótárazott összeg” mező a kérésben, akár csak
ellenőrzésre. Ami a kérésben van, arra a szerver támaszkodni fog.

### 5.2 AZ ÖSSZEFÉSÜLÉS AZONOSÍTÓ-ALAPÚ, NEM last-write-wins

A két oldal főkönyve **unióként** fésülődik össze a főkönyv-azonosító és a
forrás-esemény azonosító alapján. A teljes profil felülírása a friss oldal javára
adatvesztést okoz — pontosan azt a hibaosztályt, amit a projekt a beállítás-szinkronon
már megmért.

**NEM elfogadható gyengítés:** „az újabb `updatedAt` nyer” a teljes profilra.

### 5.3 IGAZOLT ÉS NEM IGAZOLT — két külön státusz

A lokálisan keletkezett nyugta `unverified`; a szerver által visszaigazolt
`verified`. A felület mindkettőt mutathatja, de a különbség **auditálható** marad.
Ez a Kör 22 közösségi felhasználásának feltétele.

### 5.4 FIÓK KIKAPCSOLVA → NULLA HÁLÓZATI KÉRÉS

Ha a felhasználó nincs bejelentkezve vagy kikapcsolta a szinkront, a réteg
**egyetlen** kérést sem indít — nem is próbálkozik és nem sorol be. A termék offline
teljes értékű.

### 5.5 A SZERZŐDÉS VERZIÓZOTT; a policy-eltérés kezelt

Eltérő policy-verziójú nyugta nem dobódik el és nem számolódik újra: megőrződik,
és a felülíró (superseding) nyugta explicit hivatkozással váltja le.

## 6. Acceptance criteria

| # | Kritérium | Bizonyíték |
|---|---|---|
| A1 | A szinkron kétszeri futtatása után az összes XP VÁLTOZATLAN (nincs duplázás) | `ledger_merge_policy_test.dart` — idempotencia-cella |
| A2 | A szerver ELUTASÍTJA a kliens által küldött összesített XP-t | `backend/tests/test_gamification_ledger.py` |
| A3 | Az összefésülés unió-alapú: egyik oldal bejegyzése sem vész el | `ledger_merge_policy_test.dart` — unió-mátrix |
| A4 | A lokális `unverified` és a szerver `verified` státusz megkülönböztethető és auditálható | `ledger_merge_policy_test.dart` |
| A5 | Kijelentkezett / kikapcsolt szinkron esetén NULLA hálózati kérés indul | `ledger_merge_policy_test.dart` — hálózat-cella |
| A6 | Eltérő policy-verziójú nyugta megőrződik; a felülíró nyugta explicit hivatkozással vált le | `ledger_merge_policy_test.dart` |
| A7 | A szerződés verziózott; ismeretlen verzió hibát ad | `ledger_merge_policy_test.dart` + `backend/tests/test_gamification_ledger.py` |
| A8 | A lokális offline működés teljes marad (a szinkron nem előfeltétel) | `ledger_merge_policy_test.dart` |

### 6.1 Mérce-mátrix — melyik hibás implementációt melyik cella fogja pirosra

| Hibás implementáció | Melyik cella vált PIROSRA |
|---|---|
| A kérés `totalXp` mezőt tartalmaz, és a szerver elfogadja | **A2** |
| A profil last-write-wins felülírással szinkronizál | **A3** (az unió-mátrix elveszít bejegyzést) |
| A `verified` státusz lokálisan is beállítható | **A4** |
| Kijelentkezve is indul kérés (akár csak „ellenőrzésre”) | **A5** |
| Az eltérő policy-verziójú nyugta eldobódik | **A6** |
| A szinkron dedupja csak a főkönyv-azonosítón | **A1** (a forrás-esemény azonosító nélkül duplikál) |

**A küszöb három kötelező cellája** (az összefésülés dedup-kulcsa (főkönyv-azonosító ÉS forrás-esemény azonosító)):

| Cella | Bemenet | Elvárt |
|---|---|---|
| a küszöb **alatt** | csak a főkönyv-azonosítóra dedupolunk | **DUPLIKÁL**: két eszközön külön azonosítóval keletkezett, de UGYANARRA az eseményre mutató nyugta kétszer számít — A1 PIROS |
| **rajta** (a küszöbön) | mindkét kulcsra dedupolunk (a specifikált állapot) | **HELYES**: az azonos forrás-eseményű nyugták egyesülnek, az összes XP nem nő |
| a küszöb **fölött** | csak a forrás-esemény azonosítóra dedupolunk | **ADATVESZTÉS**: két legitim, eltérő forrás-eseményű nyugta egyesülne, ha az azonosító ütközik — A3 PIROS |

A hármas tömören: **alatt** → elutasít · **rajta** → az §6.1 tábla dönti el · **fölött** → elfogad.

A határ **a **rajta** cellához tartozik (inkluzív) — a fenti táblázat „rajta” sora mondja ki, melyik oldal nyer**.

**Valódi-sértés próba (KÖTELEZŐ, §10-ben dokumentálva):** dedupolj csak a főkönyv-azonosítóra, futtasd a Dart gate-et → az **A1**
idempotencia-cellának PIROSNAK kell lennie → állítsd vissza.

## 7. Kötelező ellenőrzések

```bash
tools/round-gate.sh test/features/gamification/data/ledger_merge_policy_test.dart
```

A backend oldal külön, önálló parancs (NEM láncolva):

```bash
python3 -m pytest backend/tests/test_gamification_ledger.py -q
```

A gate artefaktum a mérce (`tools/round-gate.sh`) — a parancssorban
reprodukált parancslista NEM bizonyíték (AGENTS.md §12, L09). A script
`format` → `analyze` → `test <minden útvonal külön>` → `architecture`
lépéseket KÜLÖN processzként futtat, csonkítatlan kimenettel. **Tilos**
bármilyen szűrés vagy kézi lánc a promptban (OOM, L05). A kötelező gate-et
**TILOS háttérbe küldeni** (`run_in_background`) — az egy-fordulós harness a
forduló végén megöli, mielőtt eredmény érkezne (L183/L254). CI-dispatch, PR és
merge mindig Claude-oldal: az implementer `gh`-t NEM hív.

## 8. Implementációs sorrend

1. `gamification_sync_contract.dart` — a verziózott fel-/letöltési szerződés (nyugták, NEM összegek).
2. `ledger_merge_policy.dart` — unió-alapú összefésülés kettős dedup-kulccsal.
3. Az `unverified` / `verified` státusz szétválasztása.
4. A fiók-kikapcsolt ág: nulla hálózati kérés.
5. `backend/app/gamification/schemas.py` — a sémák, `totalXp` bemenet NÉLKÜL.
6. `backend/app/gamification/service.py` — szerver-oldali összegzés a nyugtákból.
7. A backend teszt (`backend/tests/test_gamification_ledger.py`).
8. A valódi-sértés próba §10-be; a §7 mindkét parancsa KÜLÖN futtatva.

## 9. Kockázatok

- **A kliens-összeg elfogadása.** Kényelmes és triviálisan hamisítható; a főkönyv teljes hitelességét viszi (A2).
- **A last-write-wins profil.** A projekt által MÉRT néma adatvesztés-osztály, most a jutalmakon (A3).
- **A „csak egy ellenőrző kérés” kijelentkezve.** Az offline ígéret megsértése, és a hálózat-cella fogja (A5).

## 10. Implementation handoff — az implementer tölti ki

- **Fájlok (a §4 lista, mind a 7):**
  - `lib/features/gamification/data/sync/gamification_sync_contract.dart` — a
    verziózott fel-/letöltési szerződés. A `LedgerEntrySyncStatus` enum,
    `SyncReceipt`, `SyncLedgerEnvelope`, `GamificationSyncContract` kódoló,
    `SyncReceiptValidation`, `compareSyncReceipts`. A kliens a feltöltéskor
    `status='unverified'`-re kényszeríti (a `verified` státusz kizárólag
    szerver-oldali).
  - `lib/features/gamification/data/sync/ledger_merge_policy.dart` —
    `LedgerMergePolicy` (unió-alapú összefésülés, sourceEventId + XP-alapú
    kereszt-eszköz-merge, ledgerId-alapú egyezés, supersession támogatás),
    `LedgerMergeResult`, `LedgerSyncTransport` interfész,
    `NullLedgerSyncTransport`. Az `accountEnabled` kapu `shouldRun`-ban
    fut le (5.4).
  - `lib/features/gamification/public.dart` — két új `export`-sor a
    barrel-ben. Nincs más módosítás.
  - `backend/app/gamification/schemas.py` — `ReceiptUpload` (extra='forbid',
    `totalXp` sehol, sem kötelező, sem opcionális), `LedgerUploadEnvelope`,
    `ReceiptOut`, `LedgerDownloadEnvelope`, `validate_upload_envelope`,
    `compute_total_xp`. A szerver-oldali összesítés független a kliens
    bármely `totalXp` mezőjétől.
  - `backend/app/gamification/service.py` — `evaluate_upload` (szerződés-verzió
    rövidzár, séma-ellenőrzés, másolat-detektálás, materializálás,
    szerver-oldali aggregáció), `aggregate` segéd, `validate_receipt_schema`,
    `is_supported_contract_version`. A supersession-mechanika a séma és a
    service oldalon is jelen van; a jelenlegi körben a szerver a
    `supersedesLedgerId` mezőt a service rétegen kezeli (a DB-persistálás
    egy későbbi router-körre marad).
  - `test/features/gamification/data/ledger_merge_policy_test.dart` — 20
    teszt, A1–A8 és §6.1 mindhárom küszöb-cellája le van fedve (lásd lent).
  - `backend/tests/test_gamification_ledger.py` — 9 teszt, A2 (kliens
    `totalXp` pydantic-szintű elutasítása + envelope-szintű elutasítása +
    szerver-számítás), A7 (ismeretlen szerződés-verzió és receipt
    séma-verzió elutasítása), idempotencia, dedup, üres-nyugta elutasítás.

- **Futtatott parancsok:**
  - `flutter test test/features/gamification/data/ledger_merge_policy_test.dart`
    → 20 teszt, mind zöld (kilépés 0).
  - `tools/round-gate.sh test/features/gamification/data/ledger_merge_policy_test.dart`
    → 9/9 lépés zöld (format, analyze, test, architecture, secrets, l10n,
    ruff format, ruff check, pytest). A gate a teljes backend pytest suite-
    et is lefuttatta a §7 9. lépésében (166 teszt, mind zöld).
  - `python3 -m pytest backend/tests/test_gamification_ledger.py -q` →
    9 passed (kilépés 0).

- **Valódi-sértés próba (§10 KÖTELEZŐ):**
  - A `_collapseGroup` lépést eltávolítottam a `LedgerMergePolicy.merge`-ből,
    hogy a dedup kizárólag ledgerId-n fusson (ez a §6.1 „a küszöb alatt"
    implementációja). A gate futtatása után az **A1 idempotencia-cella
    PIROSRA váltott** — a „cross-device same event merges on sourceEventId"
    teszt két bejegyzést talált egyetlen `totalXp=10` helyett, és a §6.1
    „on threshold" cella is piros lett. A teljes futás:
    `00:00 +18 -2: Some tests failed.` A policy-t visszaállítottam az
    eredeti, helyes verzióra, és a gate újra zöld.

- **A `totalXp` sehol sem elfogadott a kérésben:** a pydantic séma
  `extra='forbid'`-ja bármilyen `totalXp` (vagy `profile_total_xp`,
  `total_xp`, stb.) mezőt a dekódoláskor elutasít 422-vel. A két
  célzott teszt (`test_a2_*`) ezt explicit bizonyítja, és a
  `test_a2_server_computes_total_from_receipts_not_from_request`
  bizonyítja, hogy a válasz `totalXp`-je a szerver saját összegzéséből
  jön, nem a kérésből.

- **A fiók-kikapcsolt ág (5.4):** a `LedgerMergePolicy.shouldRun`
  `accountEnabled=false` esetén hamisat ad; a teszt egy
  `_CountingTransport`-tal bizonyítja, hogy a hálózati probe
  `requestCount` értéke nulla marad, és a `NullLedgerSyncTransport`
  dob, ha valaki mégis megpróbálja meghívni. A transport-interfész
  (`LedgerSyncTransport`) a későbbi router-körök számára készült, ahol
  a `HttpLedgerSyncTransport` a Dio / ApiClient mintára épül majd.

- **Ismert korlát / kimaradt:** a service `_apply_supersession`
  egyelőre no-op (a `supersedesLedgerId` a szerver-oldali modellben
  nincs még perzisztálva — a jelenlegi kör csak a szerződést rögzíti).
  A service-beli logika készen áll: ha a jövőbeli router-kör hozzáadja
  a DB-oszlopot, csak a service függvény törzsét kell kitölteni.

## 11. Review — a Claude tölti ki
