# E13-R35 — Account, Settings, Privacy, Offline AI és Share UI

- **Státusz:** PREPARED (előre megírva 2026-08-15, kód olvasva: `main @ 0f7afd9a`)
- **Típus:** Chapter 13 (UI/UX Design System), Kör 35
- **Kör-azonosító:** `E13-R35`
- **Branch:** `<motor>/e13-r35-account-privacy-and-share`
- **Előfeltétel:** `E13-R34` merge-elve (közösségi kihívások)
- **Brief szerzője:** Claude (Opus 5)
- **Előre kiosztott ADR:** [`0292`](../adr/0292-model-activation-requires-verified-integrity.md)
  — **a Claude írja meg a kör indításakor; a `docs/adr/` a TILOS zónában van.**

> ⚠ **Pre-flight (indítás előtt KÖTELEZŐ):** olvasd el a TÉNYLEGES
> beállítás-szinkron réteget (`lib/features/settings/providers/settings_sync.dart`)
> — a projekt MÉRTE, hogy a `try/catch`-be fojtott felhő-írás néma
> munkavesztést ad, és hogy az állapot csak a szerver megerősítése UTÁN
> jelölhető szinkronizáltnak. Eltérésnél §0.0 revízió.

```ai-router
schema_version = 1
risk = "high"
allowed_paths = [
  "lib/features/auth/",
  "lib/features/settings/",
  "lib/features/offline_ai/",
  "lib/features/share/",
  "lib/l10n/app_en.arb",
  "lib/l10n/app_hu.arb",
  "test/features/settings/auth_states_test.dart",
  "test/features/settings/settings_persistence_failure_test.dart",
  "test/features/settings/consent_center_test.dart",
  "test/features/settings/model_integrity_test.dart",
  "test/features/settings/share_redaction_test.dart",
  "test/ui/goldens/",
  "docs/rounds/e13-r35-account-privacy-and-share.md",
]
gate_tests = [
  "test/features/settings/auth_states_test.dart",
  "test/features/settings/settings_persistence_failure_test.dart",
  "test/features/settings/consent_center_test.dart",
  "test/features/settings/model_integrity_test.dart",
  "test/features/settings/share_redaction_test.dart",
  "test/ui/goldens/e13_r35_screens_golden_test.dart",
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

Az UI-48 és UI-62–UI-65 rendszerfelületeinek egységes, **biztonságos**
implementációja (SDD Ch13 Kör 35).

## 2. Jelenlegi állapot — mért tények

- A fiók **opcionális**: a felismerés végig on-device, az app kijelentkezve is
  teljes (CLAUDE.md).
- A projekt **mérte**, hogy a felhő-írást elnyelő `try/catch` néma no-opot ad,
  és hogy a szinkronizált jelölés csak szerver-megerősítés után helyes.
- Az offline AI-modell letölthető bináris — az aktiválás bizalmi döntés.

## 3. Scope

**Benne van:** a bejelentkezés/regisztráció **opcionális** fiókkal és biztonságos
hibamegjelenítéssel · a beállítások kategória / lista-részlet szerkezete és
keresése · az Adatvédelmi és hozzájárulási központ (leltár, export, törlés,
szabályzat-állapotok) · az offline AI modellkezelő letöltés / ellenőrzés /
aktiválás / visszaállítás / tárhely állapotokkal · a megosztás-előnézet
redakcióval, formátummal és közönséggel · tárolási/hálózati hiba,
újraindítás-igény, kevés tárhely, ellenőrzőösszeg-hiba, export/törlés feladat és
offline sor.

**NINCS benne (tilos):** a hitelesítési vagy a szinkron-protokoll módosítása ·
az ellenőrzés nélküli modell-aktiválás engedélyezése · más képernyők ·
`docs/adr/**`, `tools/**`, `.github/**`.

## 4. Engedélyezett fájlok

| Útvonal | Indok |
|---|---|
| `lib/features/auth/` | bejelentkezés/regisztráció |
| `lib/features/settings/` | beállítások + adatvédelem |
| `lib/features/offline_ai/` | modellkezelő |
| `lib/features/share/` | megosztás-előnézet |
| `lib/l10n/app_{en,hu}.arb` | a rendszer-szövegek |
| `test/features/settings/*_test.dart` (5) | a §6 cellái |
| `docs/rounds/e13-r35-…md` | a §10 handoff |

**Tilos zóna:** `lib/features/**` a négy érintett KIVÉTELÉVEL ·
`lib/core/design_system/**` · `docs/adr/**` · `docs/sdd/**` · `tools/**` ·
`.github/**`.

## 5. Kötött architekturális döntések (ADR 0292)

### 5.1 A modell ELLENŐRZÉS NÉLKÜL nem aktiválható

Letöltött bináris aláírás/ellenőrzőösszeg igazolása nélkül nem lép működésbe.
Hibás ellenőrzés esetén a felület **nem kínál** „aktiváld mégis" utat.

**NEM elfogadható gyengítés:** figyelmeztetés melletti aktiválás „a
felhasználó döntsön". Egy hamisított modell mindent lát, amit a mikrofon.

### 5.2 A beállítás CSAK szerver-megerősítés után jelölhető szinkronizáltnak

A projekt mért tanulsága. Sikertelen írás után a felület jelzi a
függőben lévő állapotot és újrapróbál — nem tesz úgy, mintha mentve lenne.

**NEM elfogadható gyengítés:** `try { push() } catch (_) {}` és optimista
„Mentve" felirat. Ez néma szerkesztés-vesztés.

### 5.3 Az adatvédelem NEM rejtett

A leltár, az export és a törlés a beállítások felső szintjéről elérhető, nem
három menü mélyen.

### 5.4 A fiók nélküli kilépés ELÉRHETŐ

A bejelentkezési képernyőről mindig van út „fiók nélkül tovább" irányba.

### 5.5 A megosztás alapból MINIMÁLIS adatot visz

A redakció az alapállapot; a felhasználó **bővíti**, nem szűkíti. A felület
tételesen mutatja, mi kerül ki.

### 5.6 A destruktív adatművelet EXPLICIT és auditálható

Export és törlés feladatként jelenik meg, állapottal és eredménnyel — az
ADR 0279 következmény-központú megerősítésével.

## 6. Acceptance criteria

| # | Kritérium | Bizonyíték |
|---|---|---|
| A1 | A bejelentkezésből elérhető a „fiók nélkül tovább" út | `auth_states_test.dart` |
| A2 | A hitelesítési hiba nem szivárogtat technikai részletet | ugyanott |
| A3 | A beállítás csak szerver-megerősítés után jelölt szinkronizáltnak | `settings_persistence_failure_test.dart` |
| A4 | Sikertelen mentés után a felület jelez és újrapróbál | ugyanott |
| A5 | Az adatvédelmi központ a felső szintről elérhető | `consent_center_test.dart` |
| A6 | Ellenőrzőösszeg-hiba esetén a modell NEM aktiválható | `model_integrity_test.dart` |
| A7 | A megosztás alapból minimális adatot visz, tételesen felsorolva | `share_redaction_test.dart` |
| A8 | Az export/törlés explicit, állapottal és eredménnyel | `consent_center_test.dart` |
| A9 | A kör §3-ban megnevezett MINDEN képernyőről golden-felvétel készül és be van commitolva — 412×915 compact portrait ÉS `textScaleFactor: 2.0` | `e13_r35_screens_golden_test.dart` + a `test/ui/goldens/*.png` a diffben |

### 6.1 Mérce-mátrix — melyik hibás implementációt melyik cella fogja pirosra

| Hibás implementáció | Melyik cella vált PIROSRA |
|---|---|
| „Aktiváld mégis" gomb hibás ellenőrzőösszegnél | **A6** |
| `try/catch` + optimista „Mentve" | **A3** + A4 |
| Az adatvédelem három menü mélyen | A5 |
| A bejelentkezés kötelező | **A1** |
| A megosztás alapból mindent visz | **A7** |
| Nyers hibaüzenet a bejelentkezésnél | A2 |
| A képernyő elcsúszik, túlcsordul vagy nagy szövegméretnél olvashatatlan | **A9** |

**A modell-aktiválás három kötelező cellája** (a küszöb: az integritás
igazolása):

| Cella | Bemenet | Elvárt |
|---|---|---|
| a küszöb alatt | hiányzó vagy hibás ellenőrzőösszeg | **nem aktiválható** — nincs megkerülő út |
| rajta (a küszöbön) | **érvényes ellenőrzőösszeg, ismert forrás** | aktiválható |
| a küszöb fölött | érvényes ellenőrzőösszeg + korábbi működő verzió | aktiválható, **visszaállítási** úttal |

**Valódi-sértés próba (KÖTELEZŐ, §10-ben dokumentálva):** engedélyezd az
aktiválást hibás ellenőrzőösszeg mellett → az **A6** cellának PIROSNAK kell
lennie → állítsd vissza.

## 7. Kötelező ellenőrzések

```bash
tools/round-gate.sh test/features/settings/auth_states_test.dart test/features/settings/settings_persistence_failure_test.dart test/features/settings/consent_center_test.dart test/features/settings/model_integrity_test.dart test/features/settings/share_redaction_test.dart test/ui/goldens/e13_r35_screens_golden_test.dart
```

**A golden-felvétel (A9) rögzítése — a mérce ÚJ, nem alku tárgya:** a képernyő
minden állapotát NEM kell felvenni, a §3 szerinti alap-nézet elég, de a két
keret (412×915 compact portrait és ugyanaz `textScaleFactor: 2.0` mellett)
KÖTELEZŐ. Minta és futó precedens: `test/features/live/chord_timeline_golden_test.dart`
(valódi kapu, nem `skip`-elt rögzítő). Előállítás:

```bash
~/flutter/bin/flutter test --update-goldens test/ui/goldens/e13_r35_screens_golden_test.dart
```

A keletkezett PNG-ket **commitolni kell** — enélkül az A9 nem teljesült. A
márkabetűtípusok a teszt-hostban nem töltődnek be (fallback face); ez a
meglévő golden-teszt mért viselkedése, az elrendezést, méretezést és színeket
nem érinti. MIÉRT ez a kör dolga és nem az E13-R36-é: a záró vizuális
regressziós kör csak azt tudja megmondani, hogy valami MEGVÁLTOZOTT — azt,
hogy a képernyő eleve csúnya-e, a saját körében kell látni.

Külön processzek, csonkítatlan kimenet. **Tilos** `| tail`, `| head`,
`&&`-lánc vagy bármilyen szűrés (L09); a `flutter analyze` és `flutter test`
kézi láncolása OOM-ot ad (L05). A kötelező gate-et **TILOS háttérbe küldeni**
(`run_in_background`) — az egy-fordulós harness a forduló végén megöli (L254).

> **Review-megjegyzés:** ez a kör hitelesítést, adatvédelmet és modell-
> aktiválást érint, ezért a review-ban a `security-reviewer` ügynök futtatása
> kötelező.

## 8. Implementációs sorrend

1. A bejelentkezés/regisztráció, „fiók nélkül tovább" úttal és redaktált hibával.
2. A beállítások szerkezete + a szinkron-állapot **megerősítés után**.
3. A sikertelen mentés jelzése és újrapróbálása.
4. Az adatvédelmi központ (leltár, export, törlés) felső szintű belépéssel.
5. Az offline AI modellkezelő + a három integritás-cella.
6. A megosztás-előnézet minimális alapadattal, tételes felsorolással.
7. A valódi-sértés próba, §10-be dokumentálva.
8. `tools/round-gate.sh` a §7 szerint.

## 9. Kockázatok

- **Az elnyelt szinkron-hiba.** A projekt már mérte: a felület „Mentve"-t
  mutat, az adat elveszik (A3/A4).
- **A megkerülhető modell-ellenőrzés.** A „felhasználó döntsön" érv itt a
  mikrofon teljes tartalmát teszi kockára (A6).
- **A bővítő megosztás.** Ha az alapállapot a teljes adat, a redakció
  elfelejthető — az alapérték a védelem (A7).

## 10. Implementation handoff — az implementer tölti ki

## 11. Review — a Claude tölti ki
