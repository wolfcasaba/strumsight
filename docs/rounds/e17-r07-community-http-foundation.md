# E17-R07 — Community HTTP-alap: kliens, hiba-taxonómia, auth-fejléc

- **Státusz:** PREPARED (előre megírva 2026-09-05, kód olvasva: `main @ b17e08ef`) — **`pending`** (a `hold` 2026-09-05-én feloldva, l. §0.0)
- **Típus:** Chapter 17 (Teljes bekötés), Kör 7
- **Kör-azonosító:** `E17-R07`
- **Branch:** `<motor>/e17-r07-community-http-foundation`
- **Brief szerzője:** Claude (Opus 5)
- **Előre kiosztott ADR:** `ADR 0526` — a szám ELŐZETES; a foglaló a kör indulásakor adja a véglegeset (mérve: nyolc egymást követő körön át a queue ADR-oszlopa elavult volt).
- **Fejezet-terv:** [`docs/plans/chapter-17-full-wiring.md`](../plans/chapter-17-full-wiring.md)

**Visszakeresett előzmény:** `node tools/knowledge-rag.mjs --corpus lessons,halts,adr --top 5 "community http-alap: kliens, hiba-taxonómia, auth-fejléc"` — a kör pre-flightjának KÖTELEZŐ lefuttatnia és a találatokat a §2-be beépítenie; a brief előre megírt állapotában a §2 a `main @ b17e08ef` mérésein áll.

## 0.0 A `hold` FELOLDVA (2026-09-05)

A kör a Community sáv (R07–R13) HTTP-alapját építi.

Az eredeti `hold` KÜLSŐ függősége az volt, hogy a `backend/` FastAPI szolgáltatás fusson és a készülék elérje. **2026-09-05-én TELJESÜLT:** a backend él a `https://casaba.app/strumsight` végponton (`/health/ready` → `{"status":"ready"}`, Postgres 17, alembic fej `e09_r27_0020`) — lásd `docs/operations/backend-live-deploy.md`. A `E17-R06`-hoz kötés szintén sorrendi preferencia volt, nem függőség: az R06 a `practice_generator`-t érinti, ez a kör a `community`-t.

```ai-router
schema_version = 1
risk = "high"
# risk = "high" indoklás: A kör hálózati klienst, hitelesítési fejlécet és hibakezelést épít felhasználói adat körül — a `.ai/router.toml` high_risk_path_fragments hatálya alá esik, és a `security-reviewer` review-ja KÖTELEZŐ.
allowed_paths = [
  "lib/features/community/data/api/",
  "lib/features/community/providers/community_providers.dart",
  "lib/features/community/public.dart",
  "test/features/community/data/community_http_client_test.dart",
  "docs/rounds/e17-r07-community-http-foundation.md",
]
native_gate = false
gate_tests = [
  "test/features/community/",
  "test/features/auth/",
  "test/privacy/",
]
```

## 0. Kör-jelzés és STOP-protokoll

Scope-ütközés esetén a kimenet a brief-REVÍZIÓ, nem a scope önkényes tágítása: állítsd meg a kört (`stopped`), és írd le, melyik §-t kell módosítani.

```bash
tools/codex-signal.sh progress "<egy sor>"
tools/codex-signal.sh done "<egy sor>"
tools/codex-signal.sh stopped "<egy sor>"
tools/codex-signal.sh blocked "<egy sor>"
```

**Kockázat = high, indoklás:** a kör diffje hálózatot, hitelesítést, adatvédelmet vagy felhasználói tartalmat érint, ezért a `security-reviewer` review-ja KÖTELEZŐ (AGENTS.md §15, `.ai/router.toml` high_risk_path_fragments).

## 1. Cél

A Community feature kap egy production HTTP-alapot: hitelesített kliens, egységes hiba-taxonómia, offline viselkedés — a repository-implementációk közös alapja.

## 2. Jelenlegi állapot — mért tények (`main @ b17e08ef`)

- A `community` feature-ben **0** Riverpod-provider van, és **11** `throw UnimplementedError` override-seam várja a production bekötést (`feed_controller.dart:213,225`, `club_list_screen.dart:91`, `club_detail_screen.dart:112,121,133`, `notification_controller.dart:183`, `challenge_controller.dart:132`, `challenge_result_controller.dart:111`).
- A domain 7 repository-interfészt hordoz (`challenge`, `club`, `community_profile`, `feed`, `notification`, `post`, `social_graph`); ebből **3** impl létezik (`challenge`, `profile`, `relationship`).
- A `backend/app/main.py:238-241` a 13 community routert MÁR felcsatolja, `settings.community_enabled` mögött.
- Az app máshol Dio-t használ a backendhez (`STRUMSIGHT_API_URL`, JWT `flutter_secure_storage`-ból) — ez a kör NEM épít másodikat.

## 3. Scope

**Benne van:** A community HTTP-kliens a MEGLÉVŐ Dio-alapra · egységes hiba-taxonómia (hálózat / hitelesítés / jogosultság / kvóta / szerver) · a JWT-fejléc a meglévő auth-forrásból · offline állapot explicit jelzése, nem néma üres lista.

**NINCS benne (tilos):**

- Bármely repository-implementáció — azok az R08–R11.
- A backend módosítása — az az R13.
- Új hitelesítési mechanizmus vagy token-tárolás.

## 4. Engedélyezett fájlok

(lásd az `ai-router` blokk teljes listáját)

## 5. Kötött architekturális döntések (ADR 0526)

### 5.1 A community kliens a MEGLÉVŐ Dio/JWT alapra épül, nem másodikra

Az auth-réteg már ma is Dio-val beszél a backenddel, és a JWT a `flutter_secure_storage`-ban él. Egy második kliens két token-életciklust és két hiba-viselkedést adna.

### 5.2 A hálózati hiba SOSEM néma üres lista

A `UNKNOWN > CONFIDENTLY WRONG` elv a felismerésen túl is áll: egy üres feed és egy elérhetetlen szerver KÜLÖNBÖZŐ állapot, és a felhasználónak látnia kell, melyik.

### 5.3 A kliens SEMMILYEN felhasználói tartalmat nem naplóz

A community poszt/komment felhasználói adat. A `security-reviewer` hatálya alatt a naplózás adatvédelmi lelet.

## 6. Acceptance criteria

| # | Kritérium | Bizonyíték |
|---|---|---|
| A1 | A community kliens a meglévő Dio-alapot és a meglévő JWT-forrást használja — a diff nem hoz második klienst vagy token-tárolót | `git diff` + teszt |
| A2 | Az öt hiba-osztály (hálózat / hitelesítés / jogosultság / kvóta / szerver) KÜLÖN, mérhető állapotra képződik | teszt osztályonként egy cellával |
| A3 | Elérhetetlen szerver esetén a kliens explicit offline állapotot ad, NEM üres sikeres választ | teszt, ami üres-sikeres válaszra bukik |
| A4 | A kliens nem naplóz felhasználói tartalmat | teszt, ami a naplókimenetet vizsgálja |
| A5 | Lejárt JWT esetén a kliens a meglévő auth-újrahitelesítési utat hívja, nem sajátot | teszt |

### 6.1 Falszifikációs próba

**Valódi-sértés próba (KÖTELEZŐ, §10-ben dokumentálva):** Térj vissza üres sikeres listával hálózati hiba esetén, futtasd a gate-et → az A3 cellának PIROSNAK kell lennie → állítsd vissza.

Minden fenti acceptance-cella MÉRT állítás: a §7 gate-parancsa futtatja őket, és a falszifikációs próba bizonyítja, hogy a cellák tényleg pirosra váltanak a hibás implementáción.

## 7. Kötelező ellenőrzések

```bash
tools/round-gate.sh test/features/community/ test/features/auth/ test/privacy/
```

A gate a `format` → `analyze` → `test <minden útvonal külön>` → `architecture` lépéseket KÜLÖN processzként futtatja (a box mért OOM-csapdája miatt a `flutter analyze && flutter test` lánc tilos).

## 8. Implementációs sorrend

1. A §2 mért tényeinek ÚJRAMÉRÉSE a kör indulásakor (a brief alapja elmozdulhatott).
2. A §5 döntéseinek rögzítése az ADR-ben.
3. Az implementáció a §4 engedélyezett fájljain belül.
4. A §6 acceptance-cellák tesztjei.
5. A §6.1 valódi-sértés próba lefuttatása és a §10-be dokumentálása.
6. A §7 gate futtatása csonkítatlan kimenettel.

## 9. Kockázatok

- **A néma üres állapot.** A projekt MÉRT hibaosztálya (a `try/catch`-be nyelt backend-írás, CLAUDE.md) — itt olvasási oldalon ismétlődne (5.2, A3).
- **A második token-életciklus.** Divergáló lejárat-kezelés két kliens között (5.1, A5).
- **Felhasználói tartalom a naplóban.** Adatvédelmi lelet, `security-reviewer` hatálya (5.3, A4).

## 10. Implementation handoff — az implementer tölti ki

## 11. Review — a Claude tölti ki
