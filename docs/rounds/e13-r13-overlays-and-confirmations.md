# E13-R13 — Overlay, dialog, bottom sheet és confirmation rendszer

- **Státusz:** PREPARED (előre megírva 2026-08-15, kód olvasva: `main @ 93a6c19a`)
- **Típus:** Chapter 13 (UI/UX Design System), Kör 13
- **Kör-azonosító:** `E13-R13`
- **Branch:** `<motor>/e13-r13-overlays-and-confirmations`
- **Előfeltétel:** `E13-R12` merge-elve (kártyák, badge-ek)
- **Brief szerzője:** Claude (Opus 5)
- **Előre kiosztott ADR:** [`0279`](../adr/0279-consequence-first-confirmations.md)
  — **a Claude írja meg a kör indításakor; a `docs/adr/` a TILOS zónában van.**

> ⚠ **Pre-flight (indítás előtt KÖTELEZŐ):** mérd fel, milyen TÉNYLEGES
> AI-tool-akciók léteznek ma (a coach/planner rétegben), mert az §5.2
> következmény-összegzés ezekre képez. Eltérésnél §0.0 revízió.

```ai-router
schema_version = 1
risk = "high"
allowed_paths = [
  "lib/core/design_system/components/overlays/ss_dialog.dart",
  "lib/core/design_system/components/overlays/ss_confirmation_sheet.dart",
  "lib/core/design_system/components/overlays/ss_tool_confirmation_sheet.dart",
  "lib/core/design_system/components/overlays/ss_side_sheet.dart",
  "lib/core/design_system/components/overlays/ss_overlay_host.dart",
  "lib/core/design_system/documentation/component_catalog_screen.dart",
  "lib/core/design_system/public.dart",
  "lib/l10n/app_en.arb",
  "lib/l10n/app_hu.arb",
  "test/core/design_system/overlays/ss_overlay_test.dart",
  "test/core/design_system/overlays/ss_confirmation_test.dart",
  "docs/rounds/e13-r13-overlays-and-confirmations.md",
]
gate_tests = [
  "test/core/design_system/overlays/ss_overlay_test.dart",
  "test/core/design_system/overlays/ss_confirmation_test.dart",
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

Egységes, **biztonságos** overlay-rendszer engedélyekhez, AI-tool-akciókhoz,
destruktív műveletekhez és részletpanelekhez (SDD Ch13 Kör 13).

## 2. Jelenlegi állapot — mért tények

- Az R10 letette az engedély-prezentációs modelleket; ez a kör adja a
  megerősítés-felületet.
- Az R12 kimondta, hogy az AI-eredet látható — a tool-akció megerősítése ennek
  a folytatása: a **következmény** is látható.
- Az R09 vissza-hookja innen kap párbeszédet a mentetlen sessionhöz.

## 3. Scope

**Benne van:** standard riasztó-párbeszéd, megerősítő lap, oldalsó lap és teljes
képernyős modális · `SsToolConfirmationSheet` — akció-összegzés, **érintett
adat**, adatvédelmi / hálózati / rögzítési következmény, megerősítés és mégse ·
tárgy-specifikus destruktív microcopy · fókusz-csapda, fókusz-visszaállítás,
Escape és Android vissza · nagy képernyőn oldalsó lap, compacton alsó lap ·
minták: mentetlen változás, session törlése, poszt közzététele, modell
letöltése, terv-módosítás.

**NINCS benne (tilos):** `lib/features/**` átállítása · a tényleges destruktív
művelet végrehajtása (a felület csak **kéri** a megerősítést) ·
`lib/core/theme/**` · `docs/adr/**`, `tools/**`, `.github/**`.

## 4. Engedélyezett fájlok

| Útvonal | Indok |
|---|---|
| `overlays/ss_dialog.dart` | **ÚJ** — riasztó-párbeszéd |
| `overlays/ss_confirmation_sheet.dart` | **ÚJ** |
| `overlays/ss_tool_confirmation_sheet.dart` | **ÚJ** — AI-tool következmény |
| `overlays/ss_side_sheet.dart` | **ÚJ** — nagy képernyő |
| `overlays/ss_overlay_host.dart` | **ÚJ** — fókusz, vissza, méret-választás |
| `documentation/component_catalog_screen.dart` | overlay-mátrix |
| `public.dart` | az export bővítése |
| `lib/l10n/app_{en,hu}.arb` | a microcopy |
| `test/…/overlays/*_test.dart` (2) | a §6 cellái |
| `docs/rounds/e13-r13-…md` | a §10 handoff |

**Tilos zóna:** `lib/features/**` · `lib/core/theme/**` · `lib/app/**` ·
`docs/adr/**` · `docs/sdd/**` · `tools/**` · `.github/**`.

## 5. Kötött architekturális döntések (ADR 0279)

### 5.1 A megerősítés a KÖVETKEZMÉNYT mondja ki, nem „Igen/Nem"-et

A gombfelirat a műveletet nevezi meg („Session törlése"), a szöveg pedig azt,
mi vész el és mi visszafordíthatatlan.

**NEM elfogadható gyengítés:** általános „Biztos vagy benne? Igen / Nem".
Felolvasóval és sietve olvasva egyaránt információmentes.

### 5.2 Az AI-tool megerősítés MEGMUTATJA az érintett adatot és a módot

Mit olvas, mit ír, elhagyja-e az adat a készüléket, indul-e rögzítés. Ez az
R12 provenance-döntésének a művelet-oldali párja.

**NEM elfogadható gyengítés:** „az AI most frissíti a tervedet" a részletek
nélkül. A felhasználó nem tud informált döntést hozni.

### 5.3 A Mégse MINDEN kockázatos műveletnél elérhető

Nincs olyan megerősítő felület, amiből csak előre lehet menni.

### 5.4 A háttér semanticsa ELREJTETT, a fókusz csapdázott

Modális alatt a képernyőolvasó nem téved ki a háttérbe; bezáráskor a fókusz
oda tér vissza, ahonnan indult.

### 5.5 A destruktív visszahívás PONTOSAN EGYSZER fut

Dupla koppintás, vissza-gomb és Escape kombinációjából sem futhat kétszer —
ez törlésnél adatvesztést jelentene.

### 5.6 A méret-választás a képernyőhöz igazodik

Compacton alsó lap, nagy képernyőn indokolt esetben oldalsó lap — nem
nyújtott bottom sheet tableten.

## 6. Acceptance criteria

| # | Kritérium | Bizonyíték |
|---|---|---|
| A1 | Nincs homályos „Igen/Nem" megerősítés — a gomb a műveletet nevezi meg | `ss_confirmation_test.dart` |
| A2 | Az AI-tool megerősítés mutatja az érintett adatot és a módot | ugyanott |
| A3 | A Mégse minden kockázatos műveletnél elérhető | ugyanott |
| A4 | A háttér semanticsa elrejtett, a fókusz csapdázott | `ss_overlay_test.dart` |
| A5 | Bezáráskor a fókusz visszaáll a kiindulási elemre | ugyanott |
| A6 | A destruktív visszahívás pontosan egyszer fut | `ss_confirmation_test.dart` |
| A7 | Android vissza és Escape ugyanúgy zár | `ss_overlay_test.dart` |
| A8 | Compacton alsó lap, expandeden oldalsó lap jelenik meg | ugyanott |

### 6.1 Mérce-mátrix — melyik hibás implementációt melyik cella fogja pirosra

| Hibás implementáció | Melyik cella vált PIROSRA |
|---|---|
| „Biztos vagy benne? Igen/Nem" | **A1** |
| A tool-lap csak az akció nevét mutatja | **A2** |
| Csak megerősítés, mégse nélkül | A3 |
| A háttér a semantics fában marad | **A4** |
| A fókusz a bezárás után a képernyő elejére ugrik | A5 |
| A visszahívás vissza-gombra is lefut | **A6** |

**A visszahívás három kötelező cellája** (a küszöb: hányszor futhat le):

| Cella | Bemenet | Elvárt |
|---|---|---|
| a küszöb alatt | mégse / vissza / Escape | **0** hívás |
| rajta (a küszöbön) | egyszeri megerősítés | **pontosan 1** hívás |
| a küszöb fölött | dupla koppintás a megerősítésre | **pontosan 1** hívás — a második nem számít |

**Valódi-sértés próba (KÖTELEZŐ, §10-ben dokumentálva):** engedd, hogy a
vissza-gomb is meghívja a destruktív visszahívást → az **A6** cellának PIROSNAK
kell lennie → állítsd vissza.

## 7. Kötelező ellenőrzések

```bash
tools/round-gate.sh test/core/design_system/overlays/ss_overlay_test.dart test/core/design_system/overlays/ss_confirmation_test.dart
```

Külön processzek, csonkítatlan kimenet. **Tilos** `| tail`, `| head`,
`&&`-lánc vagy bármilyen szűrés (L09); a `flutter analyze` és `flutter test`
kézi láncolása OOM-ot ad (L05). A kötelező gate-et **TILOS háttérbe küldeni**
(`run_in_background`) — az egy-fordulós harness a forduló végén megöli (L254).

## 8. Implementációs sorrend

1. `ss_overlay_host.dart` — fókusz-csapda, visszaállítás, vissza/Escape,
   méret-választás.
2. `ss_dialog.dart` + `ss_confirmation_sheet.dart` — következmény-központú
   microcopy.
3. `ss_tool_confirmation_sheet.dart` — érintett adat + mód + hatás.
4. `ss_side_sheet.dart` + a compact/expanded cella.
5. A visszahívás három cellája.
6. ARB (en + hu) + Component Catalog overlay-mátrix.
7. A valódi-sértés próba, §10-be dokumentálva.
8. `tools/round-gate.sh` a §7 szerint.

## 9. Kockázatok

- **Az általános „Igen/Nem".** A legolcsóbb megerősítés, és pont a
  visszafordíthatatlan műveleteknél nem mond semmit (A1).
- **A kétszer futó törlés.** Ritka kombinációból áll elő, és adatot veszít (A6).
- **A háttérben maradó semantics.** Képernyőolvasóval a modális megkerülhetővé
  válik, vizuálisan viszont semmi nem jelzi (A4).

## 10. Implementation handoff — az implementer tölti ki

## 11. Review — a Claude tölti ki
