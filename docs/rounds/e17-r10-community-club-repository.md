# E17-R10 — `CommunityClubRepository` impl — klub-lista, -részlet, tagkezelés

- **Státusz:** PREPARED (előre megírva 2026-09-05, kód olvasva: `main @ b17e08ef`) — **`hold`: Az `E17-R07` alapján áll**
- **Típus:** Chapter 17 (Teljes bekötés), Kör 10
- **Kör-azonosító:** `E17-R10`
- **Branch:** `<motor>/e17-r10-community-club-repository`
- **Brief szerzője:** Claude (Opus 5)
- **Előre kiosztott ADR:** `ADR 0529` — a szám ELŐZETES; a foglaló a kör indulásakor adja a véglegeset (mérve: nyolc egymást követő körön át a queue ADR-oszlopa elavult volt).
- **Fejezet-terv:** [`docs/plans/chapter-17-full-wiring.md`](../plans/chapter-17-full-wiring.md)

**Visszakeresett előzmény:** `node tools/knowledge-rag.mjs --corpus lessons,halts,adr --top 5 "`communityclubrepository` impl — klub-lista, -részlet, tagkezelés"` — a kör pre-flightjának KÖTELEZŐ lefuttatnia és a találatokat a §2-be beépítenie; a brief előre megírt állapotában a §2 a `main @ b17e08ef` mérésein áll.

## 0.0 MIÉRT `hold`

Az `E17-R07` alapján áll. **Mi oldja fel:** az `E17-R09` lezárása.

```ai-router
schema_version = 1
risk = "high"
# risk = "high" indoklás: Tagsági és jogosultsági műveletek (tag felvétel/eltávolítás, szerepkör) — jogosultsági hibaosztály, `security-reviewer` KÖTELEZŐ.
allowed_paths = [
  "lib/features/community/data/repositories/club_repository_impl.dart",
  "lib/features/community/presentation/screens/clubs/club_list_screen.dart",
  "lib/features/community/presentation/screens/clubs/club_detail_screen.dart",
  "lib/features/community/providers/community_providers.dart",
  "test/features/community/data/club_repository_impl_test.dart",
  "docs/rounds/e17-r10-community-club-repository.md",
  "test/features/community/presentation/clubs/club_detail_screen_test.dart",
  "test/features/community/private_club_leakage_test.dart",
  "test/ui/goldens/e13_r34_screens_golden_test.dart",
  "test/features/community/presentation/clubs/club_list_screen_test.dart",
  "test/app/navigation/",
]
native_gate = false
gate_tests = [
  "test/features/community/",
  "test/privacy/",
  "test/features/community/presentation/clubs/club_detail_screen_test.dart",
  "test/features/community/private_club_leakage_test.dart",
  "test/ui/goldens/e13_r34_screens_golden_test.dart",
  "test/features/community/presentation/clubs/club_list_screen_test.dart",
  "test/app/navigation/",
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

A `ClubListScreen`, `ClubDetailScreen` és `ClubMemberManagementScreen` valós adatot kap: a klub-repository production implementációt kap.

## 2. Jelenlegi állapot — mért tények (`main @ b17e08ef`)

- `club_list_screen.dart:91` és `club_detail_screen.dart:112,121,133` — négy `throw UnimplementedError` override-seam; a doc-comment KIMONDJA, hogy a `club_repository_impl.dart` egy későbbi kör.
- A `club_repository.dart` domain-interfész LÉTEZIK, impl nincs.
- A `communityClubsEnabled` kapu dart-define-függő, alapból `false`.

## 3. Scope

**Benne van:** A `CommunityClubRepository` HTTP-implementációja (lista, részlet, csatlakozás, kilépés, tagkezelés) · a négy override-seam production kitöltése · a jogosultsági hibák explicit kezelése.

**NINCS benne (tilos):**

- A három képernyő route-ja — az az R12.
- A moderációs útvonal (Epic 9 külön körei).
- A `communityClubsEnabled` alapértékének megváltoztatása.

## 4. Engedélyezett fájlok

(lásd az `ai-router` blokk teljes listáját)

**A pin-őrök jogosultsága (S10/S11, mérve: E13-R16/F9 full-gate 32867296946, E13-R17/H3 `test/app/navigation/` +33 → +30 −3):** a fenti listán szereplő, a briefen KÍVÜL élő pin-tesztek azért kerültek az `allowed_paths`-ba ÉS a `gate_tests`-be, mert a bekötés a route által renderelt képernyő TÍPUSÁT mozdíthatja el. A jogosultság PONTOSAN ennyi: a lecserélt képernyő típusának átírása a pinnelő cellában. **Cella törlése, `skip`-je vagy gyengítése TILOS** — ha egy cella a típus-átíráson túl válik pirossá, az a kör BLOKKOLÓ lelete, nem a cella hibája.


## 5. Kötött architekturális döntések (ADR 0529)

### 5.1 A jogosultsági hiba KÜLÖN állapot, nem üres lista

Egy klub, amihez a felhasználónak nincs joga, és egy üres klub KÜLÖNBÖZŐ. Összemosásuk a felhasználót téves modellhez vezeti.

### 5.2 A tagkezelési műveletek a szerver ítéletét fogadják el, nem a kliens-oldali szerepkört

A kliens-oldali szerepkör-ellenőrzés kényelmi réteg; a döntés a szerveré. Kliens-oldali engedélyezés jogosultsági rést nyitna.

## 6. Acceptance criteria

| # | Kritérium | Bizonyíték |
|---|---|---|
| A1 | A négy override-seam production úton NEM dob `UnimplementedError`-t | teszt a szállított kompozíción |
| A2 | Jogosultsági hiba KÜLÖN mérhető állapot, nem üres lista | teszt 403-at injektálva |
| A3 | A tagkezelés a szerver válaszára támaszkodik — kliens-oldali szerepkör NEM engedélyez műveletet | teszt, ami kliens-oldali engedélyezésre bukik |
| A4 | `communityClubsEnabled=false` mellett a klub-útvonalak nem hívódnak | teszt mindkét flag-álláson |

### 6.1 Falszifikációs próba

**Valódi-sértés próba (KÖTELEZŐ, §10-ben dokumentálva):** Engedélyezz egy tagkezelési műveletet kliens-oldali szerepkör alapján, futtasd a gate-et → az A3 cellának PIROSNAK kell lennie → állítsd vissza.

Minden fenti acceptance-cella MÉRT állítás: a §7 gate-parancsa futtatja őket, és a falszifikációs próba bizonyítja, hogy a cellák tényleg pirosra váltanak a hibás implementáción.

## 7. Kötelező ellenőrzések

```bash
tools/round-gate.sh test/features/community/ test/privacy/ test/features/community/presentation/clubs/club_detail_screen_test.dart test/features/community/private_club_leakage_test.dart test/ui/goldens/e13_r34_screens_golden_test.dart test/features/community/presentation/clubs/club_list_screen_test.dart test/app/navigation/
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

- **A kliens-oldali engedélyezés.** Jogosultsági rés — a legdrágább hibaosztály ebben a körben (5.2, A3).
- **A jogosultsági hiba elnyelése.** Üres listaként megjelenő 403 téves felhasználói modellt épít (5.1, A2).
- **A kapu megkerülése.** Klub-hívás kikapcsolt kapu mellett (A4).

## 10. Implementation handoff — az implementer tölti ki

## 11. Review — a Claude tölti ki
