# E17-R12 — Community route-ok, gate-képernyő és shell-belépés

- **Státusz:** PREPARED (előre megírva 2026-09-05, kód olvasva: `main @ b17e08ef`) — **`hold`: A 13 community képernyő adatrétegén (R08–R11) áll**
- **Típus:** Chapter 17 (Teljes bekötés), Kör 12
- **Kör-azonosító:** `E17-R12`
- **Branch:** `<motor>/e17-r12-community-routes-and-shell-entry`
- **Brief szerzője:** Claude (Opus 5)
- **Előre kiosztott ADR:** `ADR 0531` — a szám ELŐZETES; a foglaló a kör indulásakor adja a véglegeset (mérve: nyolc egymást követő körön át a queue ADR-oszlopa elavult volt).
- **Fejezet-terv:** [`docs/plans/chapter-17-full-wiring.md`](../plans/chapter-17-full-wiring.md)

**Visszakeresett előzmény:** `node tools/knowledge-rag.mjs --corpus lessons,halts,adr --top 5 "community route-ok, gate-képernyő és shell-belépés"` — a kör pre-flightjának KÖTELEZŐ lefuttatnia és a találatokat a §2-be beépítenie; a brief előre megírt állapotában a §2 a `main @ b17e08ef` mérésein áll.

## 0.0 MIÉRT `hold`

A 13 community képernyő adatrétegén (R08–R11) áll. **Mi oldja fel:** az `E17-R11` lezárása.

```ai-router
schema_version = 1
risk = "normal"
allowed_paths = [
  "lib/app/routing/app_router.dart",
  "lib/app/home_shell.dart",
  "lib/features/community/public.dart",
  "test/features/community/community_routing_test.dart",
  "docs/rounds/e17-r12-community-routes-and-shell-entry.md",
  "test/app/navigation/adaptive_scaffold_test.dart",
  "test/app/navigation/tab_state_restoration_test.dart",
  "test/app/navigation/legacy_route_redirect_test.dart",
  "test/app/navigation/",
]
native_gate = false
gate_tests = [
  "test/features/community/",
  "test/app/routing/",
  "test/e2e/full_app_walkthrough_test.dart",
  "test/app/navigation/adaptive_scaffold_test.dart",
  "test/app/navigation/tab_state_restoration_test.dart",
  "test/app/navigation/legacy_route_redirect_test.dart",
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

## 1. Cél

A 13 community képernyő a szállított kompozícióból elérhető, a meglévő `communityEnabled` kapu alatt, a `CommunityGateScreen` belépési szűrőjén át.

## 2. Jelenlegi állapot — mért tények (`main @ b17e08ef`)

- Mind a 13 community képernyő `reachable: false` — ez a legnagyobb egyben lévő halott halmaz a fában.
- A `CommunityGateScreen` maga is a 13 közt van: ma sem elérhető, pedig ő a feature belépési szűrője.
- A `communityEnabled` és a négy társ-kapu dart-define-függő; a `build-apk.yml` egyiket sem adja át.

## 3. Scope

**Benne van:** A 13 képernyő route-jai a `communityEnabled` kapu alatt · a `CommunityGateScreen` mint KÖTELEZŐ belépési szűrő · a shell-belépés (a Profile Hub vagy a shell egy területéről) · a kapcsolódó al-képernyők közti navigáció.

**NINCS benne (tilos):**

- Bármely repository-implementáció módosítása (R08–R11 zárta le).
- A community kapuk alapértékének megváltoztatása.
- A backend módosítása — az az R13.

## 4. Engedélyezett fájlok

(lásd az `ai-router` blokk teljes listáját)

**A pin-őrök jogosultsága (S10/S11, mérve: E13-R16/F9 full-gate 32867296946, E13-R17/H3 `test/app/navigation/` +33 → +30 −3):** a fenti listán szereplő, a briefen KÍVÜL élő pin-tesztek azért kerültek az `allowed_paths`-ba ÉS a `gate_tests`-be, mert a bekötés a route által renderelt képernyő TÍPUSÁT mozdíthatja el. A jogosultság PONTOSAN ennyi: a lecserélt képernyő típusának átírása a pinnelő cellában. **Cella törlése, `skip`-je vagy gyengítése TILOS** — ha egy cella a típus-átíráson túl válik pirossá, az a kör BLOKKOLÓ lelete, nem a cella hibája.


## 5. Kötött architekturális döntések (ADR 0531)

### 5.1 MINDEN community belépés a `CommunityGateScreen`-en át megy

A gate a feature belépési szűrője (profil-létezés, feltételek elfogadása). Egy megkerülő route a szűrőt üres szabállyá tenné.

### 5.2 `communityEnabled=false` mellett EGYETLEN community route sem létezik

A dart-define nélküli build MINDEN környezetben `false`-ra oldja — a feature ilyenkor teljesen HIÁNYZIK, nem csak üres. Ez az Epic 9 ADR 0395 szerződése.

## 6. Acceptance criteria

| # | Kritérium | Bizonyíték |
|---|---|---|
| A1 | Mind a 13 community képernyő `reachable: true` és `flagGated: true` (`communityEnabled`) | `dart run tool/check_screen_reachability.dart --format json` |
| A2 | Minden community belépés a `CommunityGateScreen`-en át megy — megkerülő route nincs | router-teszt + `git diff` |
| A3 | `communityEnabled=false` mellett egyetlen community route sem létezik | router-teszt mindkét flag-álláson |
| A4 | A shell destination-listája `communityEnabled=false` mellett bájtra a maival azonos | `home_shell.dart` teszt mindkét flag-álláson |

### 6.1 Falszifikációs próba

**Valódi-sértés próba (KÖTELEZŐ, §10-ben dokumentálva):** Vezess be egy közvetlen `/community/feed` route-ot a gate megkerülésével, futtasd a gate-et → az A2 cellának PIROSNAK kell lennie → állítsd vissza.

Minden fenti acceptance-cella MÉRT állítás: a §7 gate-parancsa futtatja őket, és a falszifikációs próba bizonyítja, hogy a cellák tényleg pirosra váltanak a hibás implementáción.

## 7. Kötelező ellenőrzések

```bash
tools/round-gate.sh test/features/community/ test/app/routing/ test/e2e/full_app_walkthrough_test.dart test/app/navigation/adaptive_scaffold_test.dart test/app/navigation/tab_state_restoration_test.dart test/app/navigation/legacy_route_redirect_test.dart test/app/navigation/
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

- **A gate megkerülése.** A belépési szűrő üres szabállyá válik (5.1, A2).
- **A shell elmozdulása kikapcsolt kapunál.** A destination-lista változása a meglévő navigációs őröket (E13-R08 óta) törné (A4).
- **A 13 route egyben.** A legnagyobb egyszeri router-diff a fejezetben — a kör pre-flightjának MÉRNIE kell a router-CI carve-out hatókörét az `E17-` előtagra.

## 10. Implementation handoff — az implementer tölti ki

## 11. Review — a Claude tölti ki
