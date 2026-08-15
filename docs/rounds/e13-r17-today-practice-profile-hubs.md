# E13-R17 — Today, Practice és Profile hubok

- **Státusz:** PREPARED (előre megírva 2026-08-15, kód olvasva: `main @ 6adea220`)
- **Típus:** Chapter 13 (UI/UX Design System), Kör 17
- **Kör-azonosító:** `E13-R17`
- **Branch:** `<motor>/e13-r17-today-practice-profile-hubs`
- **Előfeltétel:** `E13-R16` merge-elve (onboarding) + az R08 adaptív navigáció
- **Brief szerzője:** Claude (Opus 5)
- **Előre kiosztott ADR:** nincs — az ADR 0275 (flag mögötti shell) érvényes.

> ⚠ **Pre-flight (indítás előtt KÖTELEZŐ):** mérd fel, milyen TÉNYLEGES terv- és
> gamifikációs adatforrás érhető el (Chapter 8/9 rétegei), mert a hubok fake
> repository-interfészre épülnek — ha a valódi forrás hiányzik, a §5.5 szerint
> a fake az elfogadott. Eltérésnél §0.0 revízió.

```ai-router
schema_version = 1
risk = "high"
allowed_paths = [
  "lib/features/today/",
  "lib/features/practice_hub/",
  "lib/features/profile_hub/",
  "lib/app/routing/",
  "lib/l10n/app_en.arb",
  "lib/l10n/app_hu.arb",
  "test/features/today/today_hub_test.dart",
  "test/features/today/hub_navigation_test.dart",
  "test/features/profile/profile_hub_test.dart",
  "docs/rounds/e13-r17-today-practice-profile-hubs.md",
]
gate_tests = [
  "test/features/today/today_hub_test.dart",
  "test/features/today/hub_navigation_test.dart",
  "test/features/profile/profile_hub_test.dart",
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

Az UI-05–UI-07 cél-hubok bevezetése **flag mögött**, a legacy tartalmak
fokozatos összefogásával (SDD Ch13 Kör 17).

## 2. Jelenlegi állapot — mért tények

- Az R08 létrehozta az ötterületes shellt flag mögött, legacy adapterekkel — ez
  a kör tölti meg tartalommal a Today, Practice és Profile területet.
- Az R12 kártyái, az R10 állapotai és az R11 űrlapelemei készen állnak.
- Az ADR 0276 tiltja, hogy prezentációs réteg erőforrást nyisson — a hubokra ez
  külön acceptance-cella (A4).

## 3. Scope

**Benne van:** Today Hub összegzés-központú elrendezés · Practice Hub katalógus
és gyors eszközök **képesség-kapukkal** · Profile Hub helyi / bejelentkezett /
közösség-engedélyezett állapotai · adapter a meglévő Live/Analyze/Learn/Library/
Settings route-okhoz · offline cached, terv nélküli, új felhasználó,
sync-várakozó és letiltott képesség állapotok · compact/medium/expanded
elrendezés.

**NINCS benne (tilos):** Stage / Live / Tuner / Song képernyők migrációja
(Kör 18+) · a shell-flag **bekapcsolása** · mikrofon vagy kamera indítása ·
`lib/core/design_system/**` módosítása · `docs/adr/**`, `tools/**`, `.github/**`.

## 4. Engedélyezett fájlok

| Útvonal | Indok |
|---|---|
| `lib/features/today/` | **ÚJ** — Today Hub |
| `lib/features/practice_hub/` | **ÚJ** — Practice Hub |
| `lib/features/profile_hub/` | **ÚJ** — Profile Hub |
| `lib/app/routing/` | a három hub bekötése a shellbe |
| `lib/l10n/app_{en,hu}.arb` | a hub-szövegek |
| `test/features/**` (3) | a §6 cellái |
| `docs/rounds/e13-r17-…md` | a §10 handoff |

**Tilos zóna:** `lib/features/**` a három hub KIVÉTELÉVEL ·
`lib/core/design_system/**` · `lib/core/theme/**` · `docs/adr/**` ·
`docs/sdd/**` · `tools/**` · `.github/**`.

## 5. Kötött architekturális döntések

### 5.1 A hubok NEM indítanak mikrofont vagy kamerát

Áttekintő felületek. Az erőforrás a Stage-en indul, felhasználói szándékra
(ADR 0276 folytatása).

**NEM elfogadható gyengítés:** a hangoló előnézetének „élővé tétele" a Practice
Hubon. Az háttérben futó mikrofont jelentene egy listaképernyőn.

### 5.2 A Today EGY egyértelmű elsődleges akciót ad

Az R11 „egy képernyő — egy primary CTA" szabálya. A hub célja az irányítás, nem
a választék bemutatása.

### 5.3 A Profile fiók NÉLKÜL is értelmes

A termék logout állapotban teljesen használható. A Profile ilyenkor a helyi
adatokat és beállításokat mutatja, nem bejelentkezési falat.

**NEM elfogadható gyengítés:** bejelentkezési fal a Profile területen. Az egy
offline-first terméket tesz feltételessé.

### 5.4 A legacy route ELÉRHETŐ marad

Az ADR 0275 §3 szerint: a hubok nem szüntetik meg a régi utakat.

### 5.5 A hiányzó adatforrás FAKE interfésszel pótolt, nem kitalált adattal

Ha a terv- vagy gamifikációs adat még nem elérhető, a hub interfészt használ, és
a **teszt** adja a fake implementációt. A felületen nem jelenik meg kitalált
statisztika.

### 5.6 A letiltott képesség MEGMONDJA, miért

A Vision kártya letiltott állapotban elmagyarázza az okot — nem tűnik el némán,
és nem is kattinthatatlan rejtély.

## 6. Acceptance criteria

| # | Kritérium | Bizonyíték |
|---|---|---|
| A1 | A Today egyetlen egyértelmű elsődleges akciót ad | `today_hub_test.dart` |
| A2 | A Practice eszközei két érintésen belül elérhetők | `hub_navigation_test.dart` |
| A3 | A Profile fiók nélkül is értelmes tartalmat mutat | `profile_hub_test.dart` |
| A4 | A hubok NEM indítanak mikrofont/kamerát | `today_hub_test.dart` + `grep` a diffben |
| A5 | A legacy route-ok elérhetők maradnak | `hub_navigation_test.dart` |
| A6 | Offline állapotban a cached tartalom látszik (ADR 0277) | `today_hub_test.dart` |
| A7 | A letiltott képesség kártyája megmondja az okot | ugyanott |
| A8 | Nincs kitalált statisztika hiányzó adatforrás mellett | `today_hub_test.dart` |

### 6.1 Mérce-mátrix — melyik hibás implementációt melyik cella fogja pirosra

| Hibás implementáció | Melyik cella vált PIROSRA |
|---|---|
| Három egyenrangú primary gomb a Todayen | **A1** |
| A hangoló élő előnézete a Practice Hubon | **A4** |
| Bejelentkezési fal a Profile-on | **A3** |
| A legacy route törlése | **A5** |
| Offline → üres képernyő | A6 |
| A Vision kártya némán eltűnik | A7 |
| Nulla helyett kitalált „7 napos széria" | **A8** |

**A gyakorlási eszköz elérési mélységének három kötelező cellája** (a küszöb:
**2 érintés**):

| Cella | Bemenet | Elvárt |
|---|---|---|
| a küszöb alatt | 1 érintés (közvetlen gyors eszköz) | elfogadva |
| rajta (a küszöbön) | **2 érintés** | **elfogadva** (a határ inkluzív) |
| a küszöb fölött | 3 érintés | **elutasítva** — a cella PIROS |

**Valódi-sértés próba (KÖTELEZŐ, §10-ben dokumentálva):** tedd a metronómot egy
harmadik szint mögé → az **A2** cellának PIROSNAK kell lennie → állítsd vissza.

## 7. Kötelező ellenőrzések

```bash
tools/round-gate.sh test/features/today/today_hub_test.dart test/features/today/hub_navigation_test.dart test/features/profile/profile_hub_test.dart
```

Külön processzek, csonkítatlan kimenet. **Tilos** `| tail`, `| head`,
`&&`-lánc vagy bármilyen szűrés (L09); a `flutter analyze` és `flutter test`
kézi láncolása OOM-ot ad (L05). A kötelező gate-et **TILOS háttérbe küldeni**
(`run_in_background`) — az egy-fordulós harness a forduló végén megöli (L254).

## 8. Implementációs sorrend

1. A három hub repository-interfésze (fake implementáció a tesztben).
2. Today Hub — összegzés + EGY elsődleges akció.
3. Practice Hub — katalógus, gyors eszközök, képesség-kapuk + a mélység-cella.
4. Profile Hub — helyi / bejelentkezett / közösségi állapot.
5. Legacy adapterek + route-elérhetőség cellája.
6. Offline, terv nélküli, új felhasználó, sync-várakozó állapotok.
7. A valódi-sértés próba, §10-be dokumentálva.
8. `tools/round-gate.sh` a §7 szerint.

## 9. Kockázatok

- **A kitalált statisztika.** Üres állapotban „szebb" egy nullánál, és
  hazugság — a projekt legveszélyesebb hibaosztálya (A8).
- **A bejelentkezési fal.** Kézenfekvő a Profile-on, és megtöri az
  offline-first ígéretet (A3).
- **Az élő előnézet.** Látványos, és háttérben futó mikrofont jelent egy
  áttekintő képernyőn (A4).

## 10. Implementation handoff — az implementer tölti ki

## 11. Review — a Claude tölti ki
