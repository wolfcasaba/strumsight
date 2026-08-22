# E09-R06 — Profil létrehozás, szerkesztés és Community gate UI

- **Státusz:** PREPARED (előre megírva 2026-08-22, kód olvasva: `main @ db6293f4`)
- **Típus:** Chapter 10 (Epic 9 — Community Platform), Kör 6
- **Kör-azonosító:** `E09-R06`
- **Branch:** `<motor>/e09-r06-profile-onboarding-and-editing`
- **Előfeltétel:** `E09-R05` merge-elve
- **Brief szerzője:** Claude (Opus 5)
- **Előre kiosztott ADR:** nincs — ez a kör nem hoz új kötött architekturális döntést (tisztán UI/integráció/lezárás).

> ⚠ **Pre-flight (indítás előtt KÖTELEZŐ):** olvasd újra a Kör 5-ben lefektetett `public.dart` TÉNYLEGES export-listáját és a `lib/features/auth/public.dart` mintáját — a Community gate ugyanúgy épül, mint az `accountEnabledProvider`-re épülő auth-gate. Eltérésnél
> §0.0 brief-revízió, NEM csendes lista-tágítás.

```ai-router
schema_version = 1
risk = "high"
allowed_paths = [
  "lib/features/community/data/repositories/profile_repository_impl.dart",
  "lib/features/community/data/dto/profile_dto.dart",
  "lib/features/community/application/controllers/profile_controller.dart",
  "lib/features/community/presentation/screens/community_gate_screen.dart",
  "lib/features/community/presentation/screens/edit_profile_screen.dart",
  "lib/l10n/features/community_en.arb",
  "lib/l10n/features/community_hu.arb",
  "test/features/community/presentation/community_gate_test.dart",
  "test/features/community/presentation/profile_onboarding_test.dart",
  "docs/rounds/e09-r06-profile-onboarding-and-editing.md",
]
gate_tests = [
  "test/features/community/presentation/community_gate_test.dart",
  "test/features/community/presentation/profile_onboarding_test.dart"
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

Adj a felhasználónak kontrollált módot a közösségi profil létrehozására és szerkesztésére: disabled/logged-out/profile-missing/ready állapotú gate, handle-debounce, és a privacy beállítás mint a flow explicit lépése.

## 2. Jelenlegi állapot — mért tények

- A Kör 3 backend handle-policy és a Kör 4 access-policy MÁR élesek — ez a kör az ELSŐ, ami ténylegesen HTTP-n keresztül hívja őket
- `lib/features/auth/public.dart` `accountEnabledProvider`-t exportál — a Community gate erre épül, ugyanazzal a mintával, mint a `settings_sync.dart`
- a projekt konvenciója: repository-provider minta, Preview/in-memory repo a logged-out/mock-mode úthoz

## 3. Scope

**Benne van:** Community belépő gate: disabled, logged-out, profile-missing, ready állapot · profile repository Dio implementáció a közös API klienssel · handle availability debounced ellenőrzés + lokális validáció · profil létrehozó/szerkesztő képernyő (avatar placeholder, display name, bio, interest tag) · a privacy beállítás mint a létrehozó flow explicit lépése · logoutkor a Community személyes cache és pending draft törlése policy szerint.

**NINCS benne (tilos):**

- Follow, block, feed vagy poszt UI — Kör 7+.
- Média (avatar) tényleges feltöltése — Kör 18 mögötti feature flag.
- `docs/adr/**`, `docs/sdd/**`, `tools/**`, `.github/**`, `backend/**`.

## 4. Engedélyezett fájlok

| Útvonal | Indok |
|---|---|
| `lib/features/community/data/repositories/profile_repository_impl.dart` | ÚJ — Dio implementáció |
| `lib/features/community/data/dto/profile_dto.dart` | ÚJ — DTO mapping |
| `lib/features/community/application/controllers/profile_controller.dart` | ÚJ — Riverpod controller |
| `lib/features/community/presentation/screens/community_gate_screen.dart` | ÚJ |
| `lib/features/community/presentation/screens/edit_profile_screen.dart` | ÚJ |
| `lib/l10n/features/community_en.arb` | ÚJ — a Community szöveges szegmens (ADR 0307 §4) |
| `lib/l10n/features/community_hu.arb` | ÚJ — magyar parity |
| `test/features/community/presentation/community_gate_test.dart` | ÚJ — a §6 cellái |
| `test/features/community/presentation/profile_onboarding_test.dart` | ÚJ |

**Tilos zóna:** `lib/features/community/domain/**` (Kör 5 lezárt szerződése, csak bővítés indokolt esettel) · `lib/features/` más feature-je · `lib/l10n/app_{en,hu}.arb` (a generált aggregátum, nem kézzel szerkesztendő) · `lib/core/**` · `docs/adr/**` · `tools/**` · `.github/**` · `backend/**`

## 5. Kötött architekturális döntések

### 5.1 Community profil KIZÁRÓLAG explicit user actionre készül

A gate 4 állapota (disabled/logged-out/profile-missing/ready) sosem hoz létre implicit profilt — a `ready` állapotba csak a user saját, explicit létrehozó műveletén át kerülhet.

**NEM elfogadható gyengítés:** egy "gyorsítás" a bejelentkezés után automatikus profil-létrehozással, alapértelmezett handle-lel — ez pontosan az implicit megosztás elleni SDD-invariánst sértené.

### 5.2 A privacy beállítás a flow EXPLICIT lépése, nem utólagos beállítás

A létrehozó flow megállítja a felhasználót a privacy-választásnál; az alapérték `private`/`followers`, nem `public`.

## 6. Acceptance criteria

| # | Kritérium | Bizonyíték |
|---|---|---|
| A1 | Community profil csak explicit user actionre készül | `profile_onboarding_test.dart` |
| A2 | A privacy alapérték látható és módosítható a flow-ban | `profile_onboarding_test.dart` |
| A3 | Hálózati hiba nem veszti el a kitöltött profilt | `profile_onboarding_test.dart` — retry cella |
| A4 | Logged-out és feature-disabled gate helyesen jelenik meg | `community_gate_test.dart` |
| A5 | Handle debounce és dupla submit blokkolva | `profile_onboarding_test.dart` |
| A6 | Logoutkor a Community cache törlődik | `community_gate_test.dart` |
| A7 | 2.0 text scale mellett nincs kritikus overflow | `profile_onboarding_test.dart` — golden |

### 6.1 Mérce-mátrix — melyik hibás implementációt melyik cella fogja pirosra

| Hibás implementáció | Melyik cella vált PIROSRA |
|---|---|
| A profil a bejelentkezés után automatikusan létrejön | A1 |
| A privacy-választás lépés kihagyható, alapérték `public` | A2 |
| Hálózati hiba a beírt szöveget törli | A3 |
| A dupla tap két profilt hoz létre | A5 |
| Logout után a régi user profilja megjelenik a cache-ből | A6 |

**Valódi-sértés próba (KÖTELEZŐ, §10-ben dokumentálva):** vedd ki a submit-gomb debounce/disable logikáját, futtasd a gate-et → az **A5** dupla-submit cellának PIROSNAK kell lennie → állítsd vissza.

## 7. Kötelező ellenőrzések

```bash
tools/round-gate.sh test/features/community/presentation/community_gate_test.dart test/features/community/presentation/profile_onboarding_test.dart
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

1. `profile_repository_impl.dart` — Dio implementáció a Kör 3 handle és Kör 2 profil endpointjaira.
2. `profile_controller.dart` — állapotgép (disabled/logged-out/profile-missing/ready).
3. `community_gate_screen.dart` — a négy állapot UI-ja.
4. `edit_profile_screen.dart` — handle debounce, validáció, privacy-lépés.
5. Logout cache-cleanup.
6. ARB szegmens (`community_en/hu.arb`).
7. A valódi-sértés próba §10-be.

## 9. Kockázatok

- **Az implicit profil-létrehozás "UX-gyorsításként".** Ez a legfontosabb invariáns ebben a körben (A1).
- **A privacy-lépés kihagyhatósága.** Egy `Skip` gomb alapértelmezett public audience-t eredményezne (A2).
- **A dupla submit.** Gyors, kettős tap két profilt hozhat létre a Kör 2 1:1 constraint hiányában védtelen köztes állapotban (A5).

## 10. Implementation handoff — az implementer tölti ki

## 11. Review — a Claude tölti ki
