# E09-R05 — Flutter Community domain és public API

- **Státusz:** PREPARED (előre megírva 2026-08-22, kód olvasva: `main @ db6293f4`)
- **Típus:** Chapter 10 (Epic 9 — Community Platform), Kör 5
- **Kör-azonosító:** `E09-R05`
- **Branch:** `<motor>/e09-r05-flutter-community-domain-and-public-api`
- **Előfeltétel:** `E09-R04` merge-elve
- **Brief szerzője:** Claude (Opus 5)
- **Előre kiosztott ADR:** `ADR 0399` — a szám FOGLALT (Epic 9 batch-tartomány 0395-0419). Az ADR-t a Claude írja meg a kör indítási pre-flightjában a §5 döntéseiből; az implementer a `docs/adr/`-t NEM érinti (TILOS zóna).

> ⚠ **Pre-flight (indítás előtt KÖTELEZŐ):** olvasd újra a `tool/check_architecture.dart` `_isSharedDomain()` hardcode-olt listáját — a `lib/features/community/domain/` NINCS rajta (ugyanaz a mért hiányosság, mint E08-R02-ben), ezért a domain-purity guard a bevált, önálló teszt-csoportos mintát követi, nem a checker bővítését. Eltérésnél
> §0.0 brief-revízió, NEM csendes lista-tágítás.

```ai-router
schema_version = 1
risk = "high"
allowed_paths = [
  "lib/features/community/domain/entities/community_profile.dart",
  "lib/features/community/domain/entities/community_post.dart",
  "lib/features/community/domain/entities/community_comment.dart",
  "lib/features/community/domain/entities/community_reaction.dart",
  "lib/features/community/domain/entities/community_challenge.dart",
  "lib/features/community/domain/entities/community_club.dart",
  "lib/features/community/domain/entities/notification_item.dart",
  "lib/features/community/domain/entities/moderation_state.dart",
  "lib/features/community/domain/value_objects/public_user_id.dart",
  "lib/features/community/domain/value_objects/community_handle.dart",
  "lib/features/community/domain/value_objects/audience.dart",
  "lib/features/community/domain/value_objects/cursor_page.dart",
  "lib/features/community/domain/value_objects/content_id.dart",
  "lib/features/community/domain/repositories/",
  "lib/features/community/public.dart",
  "test/features/community/domain/community_domain_test.dart",
  "test/core/architecture_dependency_test.dart",
  "docs/rounds/e09-r05-flutter-community-domain-and-public-api.md",
]
gate_tests = [
  "test/features/community/domain/community_domain_test.dart",
  "test/core/architecture_dependency_test.dart"
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

Hozd létre a Flutter-oldali, framework-független Community domaint és a stabil feature boundaryt. Ez a kör NEM ad hálózati implementációt vagy teljes UI-t — csak típusokat és repository-interfészeket.

## 2. Jelenlegi állapot — mért tények

- `lib/features/community/` **nem létezik** a Flutter oldalon (a Kör 2-4 kizárólag backend munka volt)
- `lib/features/community/domain/policies/community_audience.dart` (Kör 4) MÁR LÉTEZIK — ez a kör a köré építi a teljes domain-fát
- `test/core/architecture_dependency_test.dart` a bevált E07-R02/E08-R02 mintát hordozza: önálló, feature-gyökeret közvetlenül beolvasó teszt-csoport a domain-purity mérésére (nem a checker bővítése)
- a projekt konvenciója: 21+ feature mind EGY `public.dart` barrelen át importálható

## 3. Scope

**Benne van:** a Chapter 10 §7.1 mappastruktúra (`domain/{entities,value_objects,repositories,policies}`) · public ID, handle, audience, profile summary, relationship és cursor page value object · repository interfészek: profile, social graph, feed, post, challenge, club, notification · immutable state, explicit `copyWith`/equality · `public.dart` barrel kizárólag stabil típusokkal · architektúra-guard bejegyzés az önálló teszt-csoport mintájával.

**NINCS benne (tilos):**

- Hálózati (Dio) implementáció — Kör 6-tól kezdve, repositoryként.
- Bármely UI/widget/screen — Kör 6-tól.
- Más feature importálása (a Community még senkinek nem fogyasztója és nem is fogyasztja őket).
- `docs/adr/**` — az ADR 0399-et a Claude írja.

## 4. Engedélyezett fájlok

| Útvonal | Indok |
|---|---|
| `lib/features/community/domain/entities/community_profile.dart` | ÚJ |
| `lib/features/community/domain/entities/community_post.dart` | ÚJ |
| `lib/features/community/domain/entities/community_comment.dart` | ÚJ |
| `lib/features/community/domain/entities/community_reaction.dart` | ÚJ |
| `lib/features/community/domain/entities/community_challenge.dart` | ÚJ |
| `lib/features/community/domain/entities/community_club.dart` | ÚJ |
| `lib/features/community/domain/entities/notification_item.dart` | ÚJ |
| `lib/features/community/domain/entities/moderation_state.dart` | ÚJ |
| `lib/features/community/domain/value_objects/public_user_id.dart` | ÚJ |
| `lib/features/community/domain/value_objects/community_handle.dart` | ÚJ |
| `lib/features/community/domain/value_objects/audience.dart` | ÚJ |
| `lib/features/community/domain/value_objects/cursor_page.dart` | ÚJ |
| `lib/features/community/domain/value_objects/content_id.dart` | ÚJ |
| `lib/features/community/domain/repositories/` | ÚJ — a hét repository-interfész |
| `lib/features/community/public.dart` | ÚJ — az EGYETLEN belépő |
| `test/features/community/domain/community_domain_test.dart` | ÚJ — a §6 cellái |
| `test/core/architecture_dependency_test.dart` | az új feature-gyökér határa |

**Tilos zóna:** `lib/features/` MINDEN más feature-je · `lib/features/community/application/**` · `lib/features/community/data/**` · `lib/features/community/presentation/**` (ezek Kör 6-tól) · `lib/core/**` · `lib/app/**` · `docs/adr/**` · `docs/sdd/**` · `tools/**` · `.github/**` · `backend/**`

## 5. Kötött architekturális döntések (ADR 0399)

### 5.1 A domain TISZTA Dart — nincs Flutter, Riverpod, storage vagy Dio import

A Kör 5 domain-fája framework-független, teljesen unit-tesztelhető, mert erre épül a Kör 6-tól minden repository-implementáció.

**NEM elfogadható gyengítés:** `package:flutter/foundation.dart` behúzása `@immutable` kedvéért — az immutabilitást `final` mezők és `const` konstruktor adja, ugyanaz a minta, mint a Gamification domainben (E08-R02).

### 5.2 Domain-purity guard önálló teszt-csoporttal, NEM a checker bővítésével

`tool/check_architecture.dart` NINCS az `allowed_paths` listán, ezért a `lib/features/community/domain/` framework-mentességét a bevált E07-R02/E08-R02 mintát követve, `architecture_dependency_test.dart` önálló csoportjával mérjük — a cross-feature-import szabály (A7-ekvivalens) viszont automatikus, mert generikusan fut minden `lib/features/*` fára.

### 5.3 EGY belépő: `public.dart`

A Community kizárólag a `public.dart`-on át importálható. Ez a 21+ meglévő feature konvenciója, és a Kör 6-tól kezdve minden fogyasztó erre a felületre épít.

## 6. Acceptance criteria

| # | Kritérium | Bizonyíték |
|---|---|---|
| A1 | A domain nem importál Fluttert, Dio-t vagy SharedPreferences-t | `architecture_dependency_test.dart` |
| A2 | Minden value object immutable és validált (üres handle, negatív cursor stb. elutasítva) | `community_domain_test.dart` |
| A3 | Minden wire enum ismeretlen értéket kontrolláltan kezel | `community_domain_test.dart` |
| A4 | A cursor page opaque (a kliens nem értelmezi a belső tartalmát) | `community_domain_test.dart` |
| A5 | A feature EGYETLEN `public.dart`-ból importálható | `architecture_dependency_test.dart` |
| A6 | Más feature ma nem importálja a Communityt, és a Community sem importál más feature-t | `architecture_dependency_test.dart` |

### 6.1 Mérce-mátrix — melyik hibás implementációt melyik cella fogja pirosra

| Hibás implementáció | Melyik cella vált PIROSRA |
|---|---|
| `package:flutter/foundation.dart` importálva `@immutable` miatt | A1 |
| Egy value object mezői utólag írhatók (nincs `final`) | A2 |
| Egy ismeretlen wire-enum érték kivételt dob dekódoláskor ahelyett, hogy kontrolláltan `unknown` ágra futna | A3 |
| A cursor egy nyers, kliens által értelmezhető JSON objektum | A4 |
| Egy belső fájl közvetlenül importálható a barrel megkerülésével | A5 |

**Valódi-sértés próba (KÖTELEZŐ, §10-ben dokumentálva):** importálj `package:flutter/foundation.dart`-ot a `community_profile.dart`-ba egy `@immutable` annotációhoz, futtasd a gate-et → az **A1** cellának PIROSNAK kell lennie → állítsd vissza.

## 7. Kötelező ellenőrzések

```bash
tools/round-gate.sh test/features/community/domain/community_domain_test.dart test/core/architecture_dependency_test.dart
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

1. A value objectek (`public_user_id`, `community_handle`, `audience`, `cursor_page`, `content_id`).
2. Az entitások (`community_profile`, `..._post`, `..._comment`, `..._reaction`, `..._challenge`, `..._club`, `notification_item`, `moderation_state`).
3. A hét repository-interfész (`domain/repositories/`).
4. `public.dart` — az egyetlen belépő.
5. Az architektúra-guard bejegyzése az E07-R02/E08-R02 mintával (önálló teszt-csoport).
6. `tools/round-gate.sh` a §7 szerint.

## 9. Kockázatok

- **A `flutter/foundation.dart` behúzása.** Egyetlen `@immutable` kedvéért, és a domain tesztelhetősége/újrafelhasználhatósága elvész (A1).
- **A checker bővítésének kísértése.** `tool/check_architecture.dart` NINCS ezen a listán — a bővítés elérhetetlen cél ebben a körben (§0.0 mérés kötelező a pre-flightban, mint E08-R02-ben).
- **A hét entitás "majd később" hozzáadása.** A `public.dart` barrel Kör 6-tól fix felület — az utólagos bővítés minden fogyasztót érint.

## 10. Implementation handoff — az implementer tölti ki

## 11. Review — a Claude tölti ki
