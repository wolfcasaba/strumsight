# E08-R27 — Akadálymentesség, beállítások és értesítés-kontroll

- **Státusz:** PREPARED (előre megírva 2026-08-18, kód olvasva: `main @ ea6569fb`)
- **Típus:** Chapter 9 (Epic 8 — Gamification), Kör 27
- **Kör-azonosító:** `E08-R27`
- **Branch:** `<motor>/e08-r27-gamification-accessibility-and-settings`
- **Előfeltétel:** `E08-R26` merge-elve (cross-feature integráció)
- **Brief szerzője:** Claude (Opus 5)
- **Előre kiosztott ADR:** `ADR 0318` — a szám FOGLALT. Az ADR-t a Claude írja meg a
  kör indítási pre-flightjában a §5 döntéseiből; az implementer a `docs/adr/`-t
  NEM érinti (TILOS zóna).

> ⚠ **Pre-flight (indítás előtt KÖTELEZŐ):** olvasd újra a `lib/features/settings/` TÉNYLEGES szerkezetét és a `settings_sync.dart` mintáját (a felhő-írás csak szerver-megerősítés után jelöl szinkronizáltnak), valamint az R22 ünneplés-koordinátorának beállítás-bemeneteit. Eltérésnél
> §0.0 brief-revízió, NEM csendes lista-tágítás.

```ai-router
schema_version = 1
risk = "high"
allowed_paths = [
  "lib/features/gamification/domain/gamification_preferences.dart",
  "lib/features/gamification/presentation/providers/gamification_preferences_provider.dart",
  "lib/features/settings/presentation/gamification_settings_section.dart",
  "lib/features/gamification/public.dart",
  "lib/l10n/app_en.arb",
  "lib/l10n/app_hu.arb",
  "test/features/gamification/presentation/gamification_accessibility_test.dart",
  "docs/rounds/e08-r27-gamification-accessibility-and-settings.md",
]
gate_tests = [
  "test/features/gamification/presentation/gamification_accessibility_test.dart",
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

Tedd a teljes gamifikációs élményt **kikapcsolhatóvá**, hozzáférhetővé és nem
tolakodóvá — úgy, hogy a **belső haladás-számítás megmarad** (a kikapcsolás vizuális, nem
adatvesztés).

## 2. Jelenlegi állapot — mért tények

- `lib/features/settings/` létezik; a `settings_sync.dart` mért mintája: szinkronizáltnak jelölés CSAK szerver-megerősítés után (a projekt egyik mért hibaosztálya).
- Az R22 koordinátora már olvassa a beállításokat — ez a kör adja hozzá a tényleges tárolást és felületet.
- `test/features/settings/` MA zöld — elbukása `blocked`.
- Az `ADR 0290` §1: nincs büntető nyelv; az `ADR 0289`: az elsajátítottság mért teljesítmény.

## 3. Scope

**Benne van:** beállítás az ünneplés intenzitására, haptikára, hangra, csökkentett mozgásra és
motivációs értesítésekre · a **belső** haladás-számítás megmarad, a vizuális réteg csökkenthető
vagy elrejthető · az értesítés nem kötelező, és **engedélyért nem jár XP** · minden
achievementhez akadálymentességi metaadat · képernyőolvasó- és szövegskála-tesztek · magyar és
angol szöveg tartalmi ellenőrző-listán.

**NINCS benne (tilos):**

- A `lib/features/settings/` többi fájljának módosítása (csak az új szekció).
- A felhő-szinkron viselkedésének megváltoztatása.
- Tényleges push-értesítés küldése — ez a kör a KAPCSOLÓT adja.
- `docs/adr/**` — az ADR 0318-at a Claude írja.

## 4. Engedélyezett fájlok

| Útvonal | Indok |
|---|---|
| `lib/features/gamification/domain/gamification_preferences.dart` | **ÚJ** — a beállítás-modell |
| `lib/features/gamification/presentation/providers/gamification_preferences_provider.dart` | **ÚJ** — a Riverpod provider |
| `lib/features/settings/presentation/gamification_settings_section.dart` | **ÚJ** — a beállítás-szekció |
| `lib/features/gamification/public.dart` | barrel-bővítés — CSAK export-sor |
| `lib/l10n/app_en.arb` | az ÚJ kulcsok |
| `lib/l10n/app_hu.arb` | az ÚJ kulcsok magyar párja |
| `test/features/gamification/presentation/gamification_accessibility_test.dart` | a §6 cellái |

**Tilos zóna:** `lib/features/settings/` MINDEN más fájlja · `lib/features/` többi feature-e · `lib/core/**` · `lib/app/**` · `docs/adr/**` · `docs/sdd/**` · `tools/**` · `.github/**` · `backend/**`

## 5. Kötött architekturális döntések (ADR 0318)

### 5.1 A KIKAPCSOLÁS VIZUÁLIS — a haladás NEM VÉSZ EL

A gamifikáció teljes elrejtése mellett is fut a főkönyv, a széria és a mastery
kiértékelése. A felhasználó bármikor visszakapcsolhatja, és MINDEN adata megvan.

**NEM elfogadható gyengítés:** a kikapcsoláskor az esemény-feldolgozás leállítása. Az
visszakapcsoláskor lyukat hagyna az előzményben — néma adatvesztés.

### 5.2 ENGEDÉLYÉRT NEM JÁR JUTALOM

Az értesítési engedély megadása nem ad XP-t, nem old fel eredményt, és nem
befolyásol küldetést. Az engedély-jutalom sötét minta.

**NEM elfogadható gyengítés:** „kis üdvözlő bónusz” az értesítés bekapcsolásáért.

### 5.3 A BEÁLLÍTÁS AZONNAL ÉS TELJESEN ÉRVÉNYESÜL

A kapcsoló átállítása után a következő ünneplés már az új beállítás szerint
történik — nincs újraindítás-igény. A tárolás a `settings` mért mintáját követi:
lokálisan azonnal, felhőbe csak szerver-megerősítéssel.

### 5.4 MINDEN ACHIEVEMENTNEK van akadálymentességi metaadata

Rövid, felolvasható leírás, amely képernyőolvasóval értelmes. Az R13 katalógusa
már tartalmazza a mezőt; ez a kör a **kitöltöttséget** kényszeríti ki.

## 6. Acceptance criteria

| # | Kritérium | Bizonyíték |
|---|---|---|
| A1 | Teljes kikapcsolás mellett is fut a főkönyv-, széria- és mastery-számítás | `gamification_accessibility_test.dart` — adat-megőrzés cella |
| A2 | Visszakapcsolás után az előzményben NINCS lyuk | `gamification_accessibility_test.dart` |
| A3 | Az értesítési engedély megadása NEM ad XP-t és nem old fel semmit | `gamification_accessibility_test.dart` — engedély-cella |
| A4 | Mind az öt beállítás (intenzitás / haptika / hang / mozgás / értesítés) hat az ünneplésre | `gamification_accessibility_test.dart` — beállítás-mátrix |
| A5 | A beállítás azonnal érvényesül (nincs újraindítás-igény) | `gamification_accessibility_test.dart` |
| A6 | Minden achievementnek van kitöltött akadálymentességi leírása | `gamification_accessibility_test.dart` |
| A7 | 200%-os szövegskálán nincs túlcsordulás; a kontraszt a WCAG AA szintet eléri | `gamification_accessibility_test.dart` — a11y-mátrix |
| A8 | A `test/features/settings` suite VÁLTOZATLANUL zöld | a §7 gate kimenete |

### 6.1 Mérce-mátrix — melyik hibás implementációt melyik cella fogja pirosra

| Hibás implementáció | Melyik cella vált PIROSRA |
|---|---|
| A kikapcsolás leállítja az esemény-feldolgozást | **A1** és **A2** |
| Az értesítés bekapcsolása bónusz XP-t ad | **A3** |
| A haptika kapcsoló nem hat | **A4** |
| A beállítás csak újraindítás után érvényesül | **A5** |
| Van achievement kitöltetlen a11y-leírással | **A6** |
| A szekció fix magasságú sorokkal | **A7** |

**A küszöb három kötelező cellája** (a szöveg-kontraszt aránya (WCAG AA: normál szövegre 4,5:1)):

| Cella | Bemenet | Elvárt |
|---|---|---|
| a küszöb **alatt** | 4,4:1 kontraszt | **NEM megfelelő** — az a11y-cella pirosra vált |
| **rajta** (a küszöbön) | pontosan 4,5:1 | **MEGFELELŐ** — a WCAG AA küszöb az ELFOGADÓ oldalhoz tartozik (inkluzív) |
| a küszöb **fölött** | 7:1 kontraszt | megfelelő (AAA szint) |

A hármas tömören: **alatt** → elutasít · **rajta** → az §6.1 tábla dönti el · **fölött** → elfogad.

A határ **a **rajta** cellához tartozik (inkluzív) — a fenti táblázat „rajta” sora mondja ki, melyik oldal nyer**.

**Valódi-sértés próba (KÖTELEZŐ, §10-ben dokumentálva):** állítsd a kikapcsolást úgy, hogy az esemény-feldolgozást is leállítsa, futtasd a
gate-et → az **A1** adat-megőrzés cellának PIROSNAK kell lennie → állítsd vissza.

## 7. Kötelező ellenőrzések

```bash
tools/round-gate.sh test/features/gamification/presentation/gamification_accessibility_test.dart test/features/settings
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

1. `gamification_preferences.dart` — az öt beállítás modellje.
2. A provider és a tárolás (lokálisan azonnal; a felhő-jelölés csak megerősítéssel).
3. `gamification_settings_section.dart` — a beállítás-szekció.
4. A vizuális réteg elrejtése a belső számítás megtartásával.
5. Az engedély-jutalom kizárása.
6. Az achievement a11y-metaadatok kitöltöttségének kikényszerítése.
7. Az ARB-kulcsok; a valódi-sértés próba §10-be.
8. `tools/round-gate.sh` a §7 szerint — a `settings` suite-tal együtt.

## 9. Kockázatok

- **A „teljes kikapcsolás” szó szerinti értelmezése.** A feldolgozás leállítása lyukat hagy az előzményben, és a visszakapcsolás adatvesztésként jelentkezik (A1).
- **Az engedély-bónusz.** Ártalmatlan „üdvözlő ajándéknak” látszik, és sötét minta (A3).
- **A `settings` fájljainak „rendbetétele”.** Tilos zóna; a szekció önálló fájlban él.

## 10. Implementation handoff — az implementer tölti ki

## 11. Review — a Claude tölti ki
