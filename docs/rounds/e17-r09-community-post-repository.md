# E17-R09 — `CommunityPostRepository` impl — poszt, komment, könyvjelző

- **Státusz:** PREPARED (előre megírva 2026-09-05, kód olvasva: `main @ b17e08ef`) — **`hold`: Az `E17-R07`/`E17-R08` alapján áll**
- **Típus:** Chapter 17 (Teljes bekötés), Kör 9
- **Kör-azonosító:** `E17-R09`
- **Branch:** `<motor>/e17-r09-community-post-repository`
- **Brief szerzője:** Claude (Opus 5)
- **Előre kiosztott ADR:** `ADR 0528` — a szám ELŐZETES; a foglaló a kör indulásakor adja a véglegeset (mérve: nyolc egymást követő körön át a queue ADR-oszlopa elavult volt).
- **Fejezet-terv:** [`docs/plans/chapter-17-full-wiring.md`](../plans/chapter-17-full-wiring.md)

**Visszakeresett előzmény:** `node tools/knowledge-rag.mjs --corpus lessons,halts,adr --top 5 "`communitypostrepository` impl — poszt, komment, könyvjelző"` — a kör pre-flightjának KÖTELEZŐ lefuttatnia és a találatokat a §2-be beépítenie; a brief előre megírt állapotában a §2 a `main @ b17e08ef` mérésein áll.

## 0.0 MIÉRT `hold`

Az `E17-R07`/`E17-R08` alapján áll. **Mi oldja fel:** az `E17-R08` lezárása.

```ai-router
schema_version = 1
risk = "high"
# risk = "high" indoklás: Felhasználó által ÍRT tartalom hálózati útja (poszt, komment) — moderáció, adatvédelem, `security-reviewer` KÖTELEZŐ.
allowed_paths = [
  "lib/features/community/data/repositories/post_repository_impl.dart",
  "lib/features/community/providers/community_providers.dart",
  "lib/features/community/public.dart",
  "test/features/community/data/post_repository_impl_test.dart",
  "docs/rounds/e17-r09-community-post-repository.md",
]
native_gate = false
gate_tests = [
  "test/features/community/",
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

A `PostComposerScreen`, `CommentsScreen` és `BookmarksScreen` valós adatot kap: a poszt-repository production implementációt kap.

## 2. Jelenlegi állapot — mért tények (`main @ b17e08ef`)

- A `post_repository.dart` domain-interfész LÉTEZIK, impl nincs; a `community_draft_store.dart` és a `community_media_uploader.dart` a fában él.
- A három képernyő (`PostComposer`, `Comments`, `Bookmarks`) `reachable: false`.
- A `communityWritesEnabled` és `communityMediaEnabled` kapuk dart-define-függők, alapból `false`.

## 3. Scope

**Benne van:** A `CommunityPostRepository` HTTP-implementációja (létrehozás, olvasás, komment, könyvjelző) · a piszkozat-tároló bekötése · a média-feltöltés bekötése a `communityMediaEnabled` kapu alatt · írás-hibák explicit, nem néma kezelése.

**NINCS benne (tilos):**

- A három képernyő route-ja — az az R12.
- Moderációs döntési logika (az Epic 9 külön körei).
- A `communityWrites`/`communityMedia` kapuk alapértékének megváltoztatása.

## 4. Engedélyezett fájlok

(lásd az `ai-router` blokk teljes listáját)

## 5. Kötött architekturális döntések (ADR 0528)

### 5.1 Sikertelen írás SOSEM tűnik el csendben: a piszkozat megmarad, és a hiba a felhasználóig jut

A projekt MÉRT hibaosztálya (CLAUDE.md: „Cloud writes swallowed by try/catch → silent no-op / lost edit”). Community-írásnál ez elveszett posztot jelentene.

### 5.2 Az írás csak a szerver megerősítése UTÁN számít elküldöttnek

Ugyanaz a szerződés, amit a settings-sync köre (17.) mért: optimista jelölés elveszett tartalmat takar.

### 5.3 A média-feltöltés a `communityMediaEnabled` kapu alatt marad

A kapu alapértéke rollout-döntés; a bekötésnek a kapu MINDKÉT állásán mérhetőnek kell lennie.

## 6. Acceptance criteria

| # | Kritérium | Bizonyíték |
|---|---|---|
| A1 | A poszt-repository production úton NEM dob `UnimplementedError`-t | teszt a szállított kompozíción |
| A2 | Szerver-hiba esetén a piszkozat MEGMARAD és a hiba a hívóig jut — nincs néma elnyelés | teszt, ami hibát injektál |
| A3 | Az írás csak a szerver megerősítése után jelölődik elküldöttnek | teszt, ami a megerősítés előtti állapotot vizsgálja |
| A4 | `communityMediaEnabled=false` mellett média-feltöltés NEM indul | teszt mindkét flag-álláson |
| A5 | A komment és a könyvjelző ugyanazon a repository-n megy, nem külön kliensen | `git diff` |

### 6.1 Falszifikációs próba

**Valódi-sértés próba (KÖTELEZŐ, §10-ben dokumentálva):** Nyeld el az írás-hibát `try/catch`-csel és jelöld sikeresnek, futtasd a gate-et → az A2 és A3 cellának PIROSNAK kell lennie → állítsd vissza.

Minden fenti acceptance-cella MÉRT állítás: a §7 gate-parancsa futtatja őket, és a falszifikációs próba bizonyítja, hogy a cellák tényleg pirosra váltanak a hibás implementáción.

## 7. Kötelező ellenőrzések

```bash
tools/round-gate.sh test/features/community/ test/privacy/
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

- **A néma írás-hiba.** A projekt legdrágább, MÉRT hibaosztálya — itt elveszett felhasználói poszt (5.1, A2).
- **Az optimista jelölés.** Megerősítés előtti „elküldve” hamis biztonságérzet (5.2, A3).
- **A kapu megkerülése.** Média-feltöltés kikapcsolt kapu mellett (5.3, A4).

## 10. Implementation handoff — az implementer tölti ki

## 11. Review — a Claude tölti ki
