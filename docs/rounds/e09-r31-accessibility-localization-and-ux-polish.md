# E09-R31 — Accessibility, localization és UX polish

- **Státusz:** PREPARED (előre megírva 2026-08-22, kód olvasva: `main @ db6293f4`)
- **Típus:** Chapter 10 (Epic 9 — Community Platform), Kör 31
- **Kör-azonosító:** `E09-R31`
- **Branch:** `<motor>/e09-r31-accessibility-localization-and-ux-polish`
- **Előfeltétel:** `E09-R30` merge-elve
- **Brief szerzője:** Claude (Opus 5)
- **Előre kiosztott ADR:** `ADR 0419` — a szám FOGLALT (Epic 9 batch-tartomány 0395-0419). Az ADR-t a Claude írja meg a kör indítási pre-flightjában a §5 döntéseiből; az implementer a `docs/adr/`-t NEM érinti (TILOS zóna).

> ⚠ **Pre-flight (indítás előtt KÖTELEZŐ):** olvasd újra az ADR 0393 (E08-R27) WCAG-küszöb mérési módszerét (`math.pow(x, 2.4)` sRGB→luminancia, nem köbözés, kipinnelt RGB-vektor) — ez a kör UGYANAZT a mért mintát alkalmazza a Community felületre. Eltérésnél
> §0.0 brief-revízió, NEM csendes lista-tágítás.

```ai-router
schema_version = 1
risk = "high"
allowed_paths = [
  "lib/l10n/features/community_en.arb",
  "lib/l10n/features/community_hu.arb",
  "test/features/community/accessibility/community_a11y_test.dart",
  "test/features/community/goldens/community_golden_test.dart",
  "docs/rounds/e09-r31-accessibility-localization-and-ux-polish.md",
]
gate_tests = [
  "test/features/community/accessibility/community_a11y_test.dart",
  "test/features/community/goldens/community_golden_test.dart"
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

A teljes Community-funkció hozzáférhető, lokalizált és kontrollálható használati élményének biztosítása — 2.0 text scale, reduced motion, autoplay-off minden képernyőn.

## 2. Jelenlegi állapot — mért tények

- A Kör 1-30 MOST már a teljes Community felületet lefedi — ez a kör az ELSŐ, ami mindet EGYSZERRE auditálja a11y/l10n szempontból
- az ADR 0393 (E08-R27, ha addigra merge-elve) MÁR bizonyított WCAG-mérési módszert ad — ez a kör újrahasznosítja, nem talál ki újat

## 3. Scope

**Benne van:** magyar/angol ARB parity ellenőrzés MINDEN Community kulcsra · screen-reader traversal, semantics, touch-target, focus-return audit · 2.0 text scale teszt: feed, profil, composer, komment, leaderboard, klub, report flow · reduced-motion és autoplay-off viselkedés · media alt-text/caption mező + playback semantics · offline/loading/empty/private/blocked/removed/error state EGYSÉGES design-systemből · notification-intenzitás és media data-saver beállítás.

**NINCS benne (tilos):**

- Bármely üzleti logika módosítása — ez a kör kizárólag a11y/l10n/UX polish.
- `docs/adr/**` — az ADR 0419-et a Claude írja.

## 4. Engedélyezett fájlok

| Útvonal | Indok |
|---|---|
| `lib/l10n/features/community_en.arb` | BŐVÍTÉS — a teljes Community kulcs-parity |
| `lib/l10n/features/community_hu.arb` | BŐVÍTÉS — magyar parity |
| `test/features/community/accessibility/community_a11y_test.dart` | ÚJ — a §6 cellái |
| `test/features/community/goldens/community_golden_test.dart` | ÚJ — 2.0 text scale + dark/light golden |

**Tilos zóna:** `lib/features/community/domain/**`, `application/**`, `data/**` (logika nem változik, csak a `presentation/**` widget-fa a11y-attribútumai) · `docs/adr/**` · `tools/**` · `.github/**` · `backend/**`

## 5. Kötött architekturális döntések (ADR 0419)

### 5.1 A WCAG AA kontrasztküszöb a MÉRT, nem idealizált luminancia-formulán megy

Az ADR 0393 (E08-R27) mérése szerint a köbözött (nem `math.pow(x, 2.4)`) linearizálás hibás küszöb-eredményt ad — ez a kör a bizonyított formulát és egy kipinnelt, nem idealizált RGB-vektort használ a Community felület minden színpárjára.

**NEM elfogadható gyengítés:** egy leegyszerűsített, köbözésen alapuló kontraszt-becslés "elég jó közelítésként" — az L381 hibaosztály (E08-R27) pontosan ezt mérte hibásnak.

### 5.2 Autoplay-off és reduced-motion MINDEN Community képernyőn egységesen érvényesül

Nem elég, ha a feed (Kör 14) betartja — minden media-megjelenítési pontnak (komment-csatolmány, klub-pin, profil-avatar-animáció) ugyanazt a szabályt kell követnie.

## 6. Acceptance criteria

| # | Kritérium | Bizonyíték |
|---|---|---|
| A1 | Magyar/angol ARB parity teljes a Community kulcskészletre | `community_a11y_test.dart` — l10n parity teszt |
| A2 | Minden safety action (report/block/mute) screen readerrel elérhető | `community_a11y_test.dart` |
| A3 | 2.0 text scale mellett nincs kritikus overflow egyik Community képernyőn sem | `community_golden_test.dart` |
| A4 | Reduced motion tiszteletben tartott minden animált elemnél | `community_a11y_test.dart` |
| A5 | Autoplay alapértelmezetten nincs sehol | `community_a11y_test.dart` |
| A6 | Media rendelkezik alt-text/caption lehetőséggel | `community_a11y_test.dart` |
| A7 | A WCAG AA küszöb a mért `math.pow(x, 2.4)` formulán és kipinnelt vektoron megy | `community_a11y_test.dart` — küszöb-hármas |

### 6.1 Mérce-mátrix — melyik hibás implementációt melyik cella fogja pirosra

| Hibás implementáció | Melyik cella vált PIROSRA |
|---|---|
| Egy hiányzó magyar kulcs csendben az angol fallbackre esik vissza | A1 |
| A report-gomb nincs ellátva screen-reader label-lel | A2 |
| A leaderboard sor levágódik 2.0 text scale-en | A3 |
| Egy komment-csatolmány automatikusan lejátszódik | A5 |
| A kontraszt-számítás köbözött (nem `math.pow(x, 2.4)`) linearizálást használ | A7 |

**A küszöb három kötelező cellája** (a WCAG AA kontraszt-arány (4.5:1 normál szöveghez)):

| Cella | Bemenet | Elvárt |
|---|---|---|
| a küszöb **alatt** | kipinnelt RGB-pár, mért arány `4.49:1` | PIROS — a szövegszín nem felel meg AA-nak |
| **rajta** (a küszöbön) | kipinnelt RGB-pár, mért arány pontosan `4.5:1` | ZÖLD — a határ az elfogadó oldalhoz tartozik |
| a küszöb **fölött** | kipinnelt RGB-pár, mért arány `4.51:1` | ZÖLD |

A hármas tömören: **alatt** → piros (nem felel meg) · **rajta** → zöld (megfelel, inkluzív határ) · **fölött** → zöld.

A határ a 4.5:1 a WCAG AA hivatalos, inkluzív minimuma — a mérésnek `math.pow(x, 2.4)` sRGB-linearizáláson kell alapulnia, nem köbözésen (ADR 0393/L381).

**Valódi-sértés próba (KÖTELEZŐ, §10-ben dokumentálva):** cseréld a kontraszt-számítás linearizáló függvényét köbözésre (`x**3` `math.pow(x, 2.4)` helyett), futtasd a teszt kipinnelt vektorát → az **A7** cellának PIROSNAK kell lennie (a köbözés téves megfelelést mutatna) → állítsd vissza.

## 7. Kötelező ellenőrzések

```bash
tools/round-gate.sh test/features/community/accessibility/community_a11y_test.dart test/features/community/goldens/community_golden_test.dart
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

1. A teljes Community ARB-kulcskészlet magyar/angol parity-ellenőrzése és pótlása.
2. Screen-reader semantics audit minden safety-action és interaktív elemen.
3. 2.0 text-scale golden tesztek mind a hét fő képernyőre.
4. Reduced-motion + autoplay-off egységesítés minden media-megjelenítési ponton.
5. A WCAG-küszöb-hármas mérés az ADR 0393 módszerével.
6. A valódi-sértés próba §10-be.

## 9. Kockázatok

- **A köbözött kontraszt-becslés visszacsúszása.** Az L381 hibaosztály (E08-R27) pontosan ezt mérte hibásnak — könnyű véletlenül megismételni egy másik feature-ben (A7).
- **Az elszórt autoplay.** Harminc kör alatt könnyen bekerülhetett egy elfelejtett automatikus lejátszás valahol — ez a kör az első, ami MINDET egyszerre auditálja (A5).
- **A hiányzó l10n-kulcs csendes fallbackje.** Enélkül egy magyar felhasználó angol szöveget látna anélkül, hogy bárki észrevenné (A1).

## 10. Implementation handoff — az implementer tölti ki

## 11. Review — a Claude tölti ki
