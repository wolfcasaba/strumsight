# E13-R24 — Song import, preview és editor UI

- **Státusz:** PREPARED (előre megírva 2026-08-15, kód olvasva: `main @ 74f8a8ec`)
- **Típus:** Chapter 13 (UI/UX Design System), Kör 24
- **Kör-azonosító:** `E13-R24`
- **Branch:** `<motor>/e13-r24-song-import-and-editor`
- **Előfeltétel:** `E13-R23` merge-elve (dal-könyvtár)
- **Brief szerzője:** Claude (Opus 5)
- **Előre kiosztott ADR:** [`0284`](../adr/0284-import-preview-is-not-a-commit.md)
  — **a Claude írja meg a kör indításakor; a `docs/adr/` a TILOS zónában van.**

> ⚠ **Pre-flight (indítás előtt KÖTELEZŐ):** olvasd el a TÉNYLEGES import-
> csővezeték kimenetét (figyelmeztetés és blokkoló hiba típusai, ideiglenes
> fájlok helye) — a §5.1 és §5.3 ezekre a mért típusokra képez felületet.
> Eltérésnél §0.0 revízió.

```ai-router
schema_version = 1
risk = "high"
allowed_paths = [
  "lib/features/songs/import/",
  "lib/features/songs/editor/",
  "lib/l10n/app_en.arb",
  "lib/l10n/app_hu.arb",
  "test/features/songs/import/import_flow_test.dart",
  "test/features/songs/import/import_blocking_error_test.dart",
  "test/features/songs/import/editor_draft_test.dart",
  "test/features/songs/import/editor_keyboard_flow_test.dart",
  "docs/rounds/e13-r24-song-import-and-editor.md",
]
gate_tests = [
  "test/features/songs/import/import_flow_test.dart",
  "test/features/songs/import/import_blocking_error_test.dart",
  "test/features/songs/import/editor_draft_test.dart",
  "test/features/songs/import/editor_keyboard_flow_test.dart",
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

Az UI-26–UI-28 **biztonságos** import-, leképezés- és szerkesztési felülete
(SDD Ch13 Kör 24).

## 2. Jelenlegi állapot — mért tények

- Az import csővezeték **létező** réteg: külső, nem megbízható fájlt dolgoz fel,
  és figyelmeztetéseket meg blokkoló hibákat ad vissza.
- Az R13 overlay-rendszere és az R11 űrlapelemei készen állnak.
- Az ADR 0279 kimondta: a megerősítés a következményt nevezi meg.

## 3. Scope

**Benne van:** az import folyamat (üres, választás, másolás, felismerés,
elemzés, megszakítás, hiba) · az import-előnézet sáv-választással,
figyelmeztetésekkel és **blokkoló** hibával · a szerkesztő compact strukturált
és expanded több-paneles elrendezése · mentetlen piszkozat, csak olvasható
forrás, ütközés, visszavonás/újra és mentési hiba állapotok · a húzás-műveletek
**billentyűs/gombos alternatívája** · rosszindulatú, nagy és nem támogatott
fixture-ök felületi integrációja.

**NINCS benne (tilos):** az elemző (parser) vagy az import-csővezeték logikájának
módosítása · a biztonsági ellenőrzések gyengítése · a tréner (Kör 25) ·
`docs/adr/**`, `tools/**`, `.github/**`.

## 4. Engedélyezett fájlok

| Útvonal | Indok |
|---|---|
| `songs/import/` | az import és az előnézet felülete |
| `songs/editor/` | a szerkesztő |
| `lib/l10n/app_{en,hu}.arb` | az import- és hibaszövegek |
| `test/features/songs/import/*_test.dart` (4) | a §6 cellái |
| `docs/rounds/e13-r24-…md` | a §10 handoff |

**Tilos zóna:** az elemző és az import-csővezeték logikája ·
`lib/features/songs/` a két érintett almappán kívül ·
`lib/core/design_system/**` · `docs/adr/**` · `docs/sdd/**` · `tools/**` ·
`.github/**`.

## 5. Kötött architekturális döntések (ADR 0284)

### 5.1 Az előnézet NEM publikál és nem ment semmit

A preview kizárólag megmutat. Amíg a felhasználó nem erősít meg, nem keletkezik
tartós rekord, és semmi nem kerül ki a készülékről.

**NEM elfogadható gyengítés:** a dal „ideiglenes" mentése az előnézet
megnyitásakor, hogy egyszerűbb legyen az állapotkezelés. Onnantól a megszakítás
is hagy maga után adatot.

### 5.2 A megszakítás TAKARÍT

Megszakított import után nem marad ideiglenes fájl a készüléken. Ez
acceptance-cella (A2).

### 5.3 A blokkoló hiba NEM kerülhető meg

Ha az elemző blokkoló hibát ad, a felület nem kínál „mindegy, folytasd" utat. A
figyelmeztetés és a blokkoló hiba **két különböző** dolog, és a felületen is
annak látszik.

**NEM elfogadható gyengítés:** a blokkoló hiba figyelmeztetésként kezelése
„hogy a felhasználó ne akadjon el". Az egy nem megbízható fájlt engedne be.

### 5.4 A piszkozat MENTÉSI HIBA UTÁN IS megmarad

Ha a mentés elbukik, a szerkesztett tartalom nem vész el. A projekt már mérte,
hogy a `try/catch`-be fojtott írási hiba néma munkavesztést ad.

### 5.5 A csak olvasható forrás CSAK MÁSOLHATÓ

Szerkesztés helyett a felület saját másolat készítését kínálja (az R23 §5.2
folytatása).

### 5.6 A húzás-műveletnek van BILLENTYŰS/GOMBOS alternatívája

A szakaszok átrendezése nem köthető kizárólag húzáshoz — motorikusan korlátozott
és felolvasót használó felhasználónak is elérhető.

## 6. Acceptance criteria

| # | Kritérium | Bizonyíték |
|---|---|---|
| A1 | Az előnézet nem hoz létre tartós rekordot és nem publikál | `import_flow_test.dart` |
| A2 | A megszakított import után nem marad ideiglenes fájl | ugyanott |
| A3 | A blokkoló hiba nem kerülhető meg | `import_blocking_error_test.dart` |
| A4 | A figyelmeztetés és a blokkoló hiba vizuálisan elkülönül | ugyanott |
| A5 | A piszkozat mentési hiba után is megmarad | `editor_draft_test.dart` |
| A6 | Csak olvasható forrásból csak másolat készíthető | ugyanott |
| A7 | Az átrendezés billentyűvel/gombbal is elvégezhető | `editor_keyboard_flow_test.dart` |
| A8 | A mentetlen kilépés következménye szövegben megjelenik | `editor_draft_test.dart` |

### 6.1 Mérce-mátrix — melyik hibás implementációt melyik cella fogja pirosra

| Hibás implementáció | Melyik cella vált PIROSRA |
|---|---|
| Az előnézet ideiglenes rekordot ment | **A1** |
| A megszakítás után marad temp fájl | **A2** |
| A blokkoló hiba „folytasd mindenképp" gombbal | **A3** |
| A figyelmeztetés és a blokkoló hiba azonos megjelenésű | A4 |
| A mentési hiba eldobja a piszkozatot | **A5** |
| Csak húzással átrendezhető szakaszok | **A7** |

**Az elemző-lelet három kötelező cellája** (a küszöb: a lelet súlyossága):

| Cella | Bemenet | Elvárt |
|---|---|---|
| a küszöb alatt | tájékoztató lelet | látszik, az import folytatható |
| rajta (a küszöbön) | **figyelmeztetés** | látszik, kiemelten; az import **folytatható** megerősítéssel |
| a küszöb fölött | **blokkoló hiba** | az import **nem folytatható** — nincs megkerülő út |

**Valódi-sértés próba (KÖTELEZŐ, §10-ben dokumentálva):** kezeld a blokkoló
hibát figyelmeztetésként → az **A3** cellának PIROSNAK kell lennie → állítsd
vissza.

## 7. Kötelező ellenőrzések

```bash
tools/round-gate.sh test/features/songs/import/import_flow_test.dart test/features/songs/import/import_blocking_error_test.dart test/features/songs/import/editor_draft_test.dart test/features/songs/import/editor_keyboard_flow_test.dart
```

Külön processzek, csonkítatlan kimenet. **Tilos** `| tail`, `| head`,
`&&`-lánc vagy bármilyen szűrés (L09); a `flutter analyze` és `flutter test`
kézi láncolása OOM-ot ad (L05). A kötelező gate-et **TILOS háttérbe küldeni**
(`run_in_background`) — az egy-fordulós harness a forduló végén megöli (L254).

## 8. Implementációs sorrend

1. Az import folyamat állapotai + megszakítás és takarítás.
2. Az előnézet — tartós rekord NÉLKÜL.
3. A lelet-súlyosság három cellája (tájékoztató / figyelmeztetés / blokkoló).
4. A szerkesztő compact és expanded elrendezése.
5. A piszkozat megőrzése mentési hiba után + a csak olvasható másolás.
6. Billentyűs/gombos átrendezés.
7. A valódi-sértés próba, §10-be dokumentálva.
8. `tools/round-gate.sh` a §7 szerint.

## 9. Kockázatok

- **Az „ideiglenes" mentés.** Egyszerűsíti az állapotkezelést, és a
  megszakítás után is adatot hagy (A1/A2).
- **A blokkoló hiba felpuhítása.** A felhasználó elakadása kellemetlen; a nem
  megbízható fájl beengedése rosszabb (A3).
- **A néma piszkozat-vesztés.** A projekt már mérte ezt a hibaosztályt: a
  `try/catch`-be fojtott írási hiba nem látszik, csak a munka tűnik el (A5).

## 10. Implementation handoff — az implementer tölti ki

## 11. Review — a Claude tölti ki
