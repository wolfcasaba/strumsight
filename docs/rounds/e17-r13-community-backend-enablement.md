# E17-R13 — Backend `community_enabled` bekapcsolás + e2e füstteszt

- **Státusz:** PREPARED (előre megírva 2026-09-05, kód olvasva: `main @ b17e08ef`) — **`hold`: A teljes Community sávon áll, és KÜLSŐ függősége van: futó, elérhető backend**
- **Típus:** Chapter 17 (Teljes bekötés), Kör 13
- **Kör-azonosító:** `E17-R13`
- **Branch:** `<motor>/e17-r13-community-backend-enablement`
- **Brief szerzője:** Claude (Opus 5)
- **Előre kiosztott ADR:** `ADR 0532` — a szám ELŐZETES; a foglaló a kör indulásakor adja a véglegeset (mérve: nyolc egymást követő körön át a queue ADR-oszlopa elavult volt).
- **Fejezet-terv:** [`docs/plans/chapter-17-full-wiring.md`](../plans/chapter-17-full-wiring.md)

**Visszakeresett előzmény:** `node tools/knowledge-rag.mjs --corpus lessons,halts,adr --top 5 "backend `community_enabled` bekapcsolás + e2e füstteszt"` — a kör pre-flightjának KÖTELEZŐ lefuttatnia és a találatokat a §2-be beépítenie; a brief előre megírt állapotában a §2 a `main @ b17e08ef` mérésein áll.

## 0.0 MIÉRT `hold`

A teljes Community sávon áll, és KÜLSŐ függősége van: futó, elérhető backend. **Mi oldja fel:** az `E17-R12` lezárása + a szolgáltatás elérhetőségének megerősítése.

```ai-router
schema_version = 1
risk = "high"
# risk = "high" indoklás: Backend-konfiguráció, hitelesítés és 13 végpont élesítése felhasználói adat körül — `security-reviewer` KÖTELEZŐ.
allowed_paths = [
  "backend/app/main.py",
  "backend/README.md",
  "backend/tests/test_community_smoke.py",
  "tool/release/community_smoke.py",
  "docs/rounds/e17-r13-community-backend-enablement.md",
]
native_gate = false
gate_tests = [
  "test/features/community/",
  "test/features/auth/",
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

A 13 community backend-router élesíthető, és egy e2e füstteszt MÉRI, hogy a Flutter-oldali repository-k valós szerverrel működnek.

## 2. Jelenlegi állapot — mért tények (`main @ b17e08ef`)

- `backend/app/main.py:238-241` — a community router `settings.community_enabled` mögött MÁR felcsatolható.
- A modul 13 routert (`feed`, `posts`, `comments` … `moderation`) és 20 Alembic-migrációt hordoz.
- A Flutter-oldal az `E17-R07`..`E17-R11` után valós repository-kkal áll.
- **Mért kikötés:** a detektálás 100%-ban on-device marad; a Community OPCIONÁLIS fiók-réteg, és az app kijelentkezve teljesen használható (CLAUDE.md).

## 3. Scope

**Benne van:** A `community_enabled` konfiguráció dokumentált élesítési útja · migrációk futtatási rendje · e2e füstteszt a Flutter-repository-k és a valós végpontok között · a kijelentkezett út érintetlenségének mérése.

**NINCS benne (tilos):**

- Új backend-végpont vagy sémaváltozás.
- Éles üzemeltetési döntés (hol fut, milyen domainen) — az üzemeltetés a felhasználó döntése.
- A Flutter-oldali repository-k módosítása.

## 4. Engedélyezett fájlok

(lásd az `ai-router` blokk teljes listáját)

## 5. Kötött architekturális döntések (ADR 0532)

### 5.1 A kijelentkezett út bájtra érintetlen marad

Az app fő szerződése, hogy fiók nélkül teljesen használható, és a detektálás on-device. A community élesítése ezt nem érintheti.

### 5.2 A füstteszt VALÓS végpontokat hív, nem mockot

A kör értéke pont az, hogy a Flutter-oldali repository-k és a szerver EGYÜTT működnek. Mockolt füstteszt semmit sem bizonyít erről.

## 6. Acceptance criteria

| # | Kritérium | Bizonyíték |
|---|---|---|
| A1 | `community_enabled=true` mellett a 13 router felcsatolódik és a `/health` zöld | backend-teszt |
| A2 | A füstteszt VALÓS végpontokat hív (feed olvasás, poszt írás, klub lista), és zöld | `tool/release/community_smoke.py` |
| A3 | `community_enabled=false` mellett egyetlen community végpont sem elérhető (404) | backend-teszt |
| A4 | A kijelentkezett Flutter-út változatlan: a detektálás és a helyi funkciók fiók nélkül futnak | meglévő teszt-halmaz zölden |

### 6.1 Falszifikációs próba

**Valódi-sértés próba (KÖTELEZŐ, §10-ben dokumentálva):** Cseréld a füstteszt egy végpontját mockra, futtasd → az A2 cellának PIROSNAK kell lennie (a mock nem bizonyít szerver-együttműködést) → állítsd vissza.

Minden fenti acceptance-cella MÉRT állítás: a §7 gate-parancsa futtatja őket, és a falszifikációs próba bizonyítja, hogy a cellák tényleg pirosra váltanak a hibás implementáción.

## 7. Kötelező ellenőrzések

```bash
tools/round-gate.sh test/features/community/ test/features/auth/
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

- **A mockolt füstteszt.** Üres biztonságérzet a szerver-együttműködésről (5.2, A2).
- **A kijelentkezett út megsértése.** Az app fő szerződése (5.1, A4).
- **A migrációs rend.** 20 Alembic-migráció rossz sorrendben futtatva adatvesztést okozhat (A1).

## 10. Implementation handoff — az implementer tölti ki

## 11. Review — a Claude tölti ki
