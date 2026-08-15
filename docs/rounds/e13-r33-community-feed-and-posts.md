# E13-R33 — Community profil, feed, keresés és poszt UI

- **Státusz:** PREPARED (előre megírva 2026-08-15, kód olvasva: `main @ 0f7afd9a`)
- **Típus:** Chapter 13 (UI/UX Design System), Kör 33
- **Kör-azonosító:** `E13-R33`
- **Branch:** `<motor>/e13-r33-community-feed-and-posts`
- **Előfeltétel:** `E13-R32` merge-elve (gamifikáció)
- **Brief szerzője:** Claude (Opus 5)
- **Előre kiosztott ADR:** [`0291`](../adr/0291-community-is-optional-and-private-by-default.md)
  — **a Claude írja meg a kör indításakor; a `docs/adr/` a TILOS zónában van.**

> ⚠ **Pre-flight (indítás előtt KÖTELEZŐ):** olvasd el a TÉNYLEGES közösségi
> domain-t és a poszt-küldés idempotencia-kulcsát — a §5.5 kimondja, hogy az
> újrapróbálkozás nem duplikálhat. Eltérésnél §0.0 revízió.

```ai-router
schema_version = 1
risk = "high"
allowed_paths = [
  "lib/features/community/profile/",
  "lib/features/community/feed/",
  "lib/features/community/posts/",
  "lib/l10n/app_en.arb",
  "lib/l10n/app_hu.arb",
  "test/features/community/community_gate_test.dart",
  "test/features/community/composer_audience_test.dart",
  "test/features/community/offline_publish_retry_test.dart",
  "test/features/community/block_mute_test.dart",
  "docs/rounds/e13-r33-community-feed-and-posts.md",
]
gate_tests = [
  "test/features/community/community_gate_test.dart",
  "test/features/community/composer_audience_test.dart",
  "test/features/community/offline_publish_retry_test.dart",
  "test/features/community/block_mute_test.dart",
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

Lezáró jelzés nélkül a kör bukott. Listán kívüli fájl → `stopped`.

## 1. Cél

Az UI-53–UI-58 **opcionális** közösségi felületei: belépő, feed, felfedezés,
profil, szerkesztő és beszélgetés (SDD Ch13 Kör 33).

## 2. Jelenlegi állapot — mért tények

- A közösségi funkció **opcionális**: a termék magja nélküle is teljes.
- Az R13 megerősítés-rendszere és az R12 provenance-badge-ei készen állnak.
- A gyakorlási adat a felhasználó legszemélyesebb tartalma — a megosztása
  soha nem lehet implicit.

## 3. Scope

**Benne van:** a közösségi belépő és a nyilvános profil beállítása
**alapból priváttal** · a feed tartalmi / offline / eltávolított / moderációs
állapotai · keresés és felfedezés, nyilvános profil kapcsolat- és
biztonsági akcióival · a poszt-szerkesztő közönség-, csatolmány-,
gyakorlás-megosztás és offline sor felülete · a poszt részletnézete, reakciók,
kommentek, szál-állapotok · a tiltás/némítás **azonnali helyi szűrése**.

**NINCS benne (tilos):** a moderációs vagy a backend-logika módosítása · az
idempotencia-kulcs megjelenítése a felületen · a közösség kötelezővé tétele ·
`docs/adr/**`, `tools/**`, `.github/**`.

## 4. Engedélyezett fájlok

| Útvonal | Indok |
|---|---|
| `community/profile/` | belépő és nyilvános profil |
| `community/feed/` | feed és felfedezés |
| `community/posts/` | szerkesztő és beszélgetés |
| `lib/l10n/app_{en,hu}.arb` | a közösségi szövegek |
| `test/features/community/*_test.dart` (4) | a §6 cellái |
| `docs/rounds/e13-r33-…md` | a §10 handoff |

**Tilos zóna:** `lib/features/**` a `community/` három almappáján kívül ·
`lib/core/design_system/**` · `docs/adr/**` · `docs/sdd/**` · `tools/**` ·
`.github/**`.

## 5. Kötött architekturális döntések (ADR 0291)

### 5.1 A termék magja közösség NÉLKÜL is teljes

Semmilyen alapfunkció nem követel fiókot vagy nyilvános profilt. A belépő
elutasítása nem zár ki semmit.

### 5.2 Az alapértelmezett közönség NEM nyilvános

Sem a profil, sem a poszt. A nyilvánosságot a felhasználó választja, tudatosan.

**NEM elfogadható gyengítés:** a „Nyilvános" előre kiválasztott közönség „mert
úgyis azt akarják". Ez visszavonhatatlan megosztást eredményez félrekattintásból.

### 5.3 A nyers gyakorlási adat NEM megy implicit módon

Ha egy poszt gyakorlási eredményt oszt meg, a felület megmutatja, **pontosan
mi** kerül ki, és a nyers hang alapból nem tartozik bele.

### 5.4 A tiltás AZONNAL hat, helyben is

Nem kell megvárni a szerver megerősítését ahhoz, hogy a tartalom eltűnjön a
felhasználó képernyőjéről.

### 5.5 Az újrapróbálkozás NEM duplikál posztot vagy kommentet

Az offline sor idempotencia-kulcsot használ. A kulcs a **transzportban** él, a
felületen nem jelenik meg.

**NEM elfogadható gyengítés:** „a felhasználó úgyis látja, ha kétszer ment el".
Egy duplikált poszt nyilvános és kínos, egy duplikált komment zajos.

### 5.6 Az eltávolított tartalom HELYŐRZŐT kap

Nem tűnik el némán a szálból — a beszélgetés érthető marad.

## 6. Acceptance criteria

| # | Kritérium | Bizonyíték |
|---|---|---|
| A1 | A termék magja közösség nélkül teljesen működik | `community_gate_test.dart` |
| A2 | Az alapértelmezett közönség nem nyilvános (profil és poszt) | `composer_audience_test.dart` |
| A3 | A gyakorlás-megosztás megmutatja, pontosan mi kerül ki | ugyanott |
| A4 | A nyers hang alapból nem része a megosztásnak | ugyanott |
| A5 | A tiltás/némítás azonnal, helyben is hat | `block_mute_test.dart` |
| A6 | Az újrapróbálkozás nem duplikál posztot vagy kommentet | `offline_publish_retry_test.dart` |
| A7 | Az eltávolított tartalom helyőrzőt kap | `community_gate_test.dart` |
| A8 | A felhasználónév-validáció hibás bevitelt nem enged tovább | ugyanott |

### 6.1 Mérce-mátrix — melyik hibás implementációt melyik cella fogja pirosra

| Hibás implementáció | Melyik cella vált PIROSRA |
|---|---|
| A „Nyilvános" előre kiválasztva | **A2** |
| A gyakorlás-megosztás nem sorolja fel a tartalmat | **A3** |
| A nyers hang alapból csatolva | **A4** |
| A tiltás csak szerver-válasz után hat | **A5** |
| Az offline sor kulcs nélkül próbálkozik újra | **A6** |
| Az eltávolított komment némán eltűnik | A7 |

**A közönség-alapérték három kötelező cellája** (a küszöb: a láthatóság szintje):

| Cella | Bemenet | Elvárt |
|---|---|---|
| a küszöb alatt | új felhasználó, nincs választás | **privát** — ez az alapérték |
| rajta (a küszöbön) | a felhasználó „követők" közönséget választ | a választás érvényesül és látszik a küldés előtt |
| a küszöb fölött | a felhasználó „nyilvános"-t választ | **kimondott megerősítés** a visszavonhatatlanságról |

**Valódi-sértés próba (KÖTELEZŐ, §10-ben dokumentálva):** állítsd az
alapértelmezett közönséget nyilvánosra → az **A2** cellának PIROSNAK kell
lennie → állítsd vissza.

## 7. Kötelező ellenőrzések

```bash
tools/round-gate.sh test/features/community/community_gate_test.dart test/features/community/composer_audience_test.dart test/features/community/offline_publish_retry_test.dart test/features/community/block_mute_test.dart
```

Külön processzek, csonkítatlan kimenet. **Tilos** `| tail`, `| head`,
`&&`-lánc vagy bármilyen szűrés (L09); a `flutter analyze` és `flutter test`
kézi láncolása OOM-ot ad (L05). A kötelező gate-et **TILOS háttérbe küldeni**
(`run_in_background`) — az egy-fordulós harness a forduló végén megöli (L254).

> **Review-megjegyzés:** ez a kör nyilvános megosztást és felhasználói adatot
> érint, ezért a review-ban a `security-reviewer` ügynök futtatása kötelező.

## 8. Implementációs sorrend

1. A közösségi belépő — a mag működése nélküle is.
2. A nyilvános profil beállítása, alapból priváttal + a három közönség-cella.
3. A feed állapotai, eltávolított tartalom helyőrzővel.
4. A poszt-szerkesztő: közönség, csatolmány, gyakorlás-megosztás tételesen.
5. Az offline sor idempotencia-kulccsal (a felületen nem látszik).
6. A tiltás/némítás azonnali helyi szűrése.
7. A valódi-sértés próba, §10-be dokumentálva.
8. `tools/round-gate.sh` a §7 szerint.

## 9. Kockázatok

- **Az előre kiválasztott nyilvános közönség.** Egyetlen félrekattintásból
  visszavonhatatlan megosztás lesz (A2).
- **A duplikált poszt.** Az offline sor legkézenfekvőbb hibája, és nyilvánosan
  látszik (A6).
- **A késleltetett tiltás.** A felhasználó továbbra is látja azt, akitől épp
  védekezni próbál (A5).

## 10. Implementation handoff — az implementer tölti ki

## 11. Review — a Claude tölti ki
