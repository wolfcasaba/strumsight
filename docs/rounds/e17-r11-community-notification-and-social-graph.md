# E17-R11 — `NotificationRepository` + `SocialGraphRepository` impl

- **Státusz:** PREPARED (előre megírva 2026-09-05, kód olvasva: `main @ b17e08ef`) — **`hold`: Az `E17-R07` alapján áll**
- **Típus:** Chapter 17 (Teljes bekötés), Kör 11
- **Kör-azonosító:** `E17-R11`
- **Branch:** `<motor>/e17-r11-community-notification-and-social-graph`
- **Brief szerzője:** Claude (Opus 5)
- **Előre kiosztott ADR:** `ADR 0530` — a szám ELŐZETES; a foglaló a kör indulásakor adja a véglegeset (mérve: nyolc egymást követő körön át a queue ADR-oszlopa elavult volt).
- **Fejezet-terv:** [`docs/plans/chapter-17-full-wiring.md`](../plans/chapter-17-full-wiring.md)

**Visszakeresett előzmény:** `node tools/knowledge-rag.mjs --corpus lessons,halts,adr --top 5 "`notificationrepository` + `socialgraphrepository` impl"` — a kör pre-flightjának KÖTELEZŐ lefuttatnia és a találatokat a §2-be beépítenie; a brief előre megírt állapotában a §2 a `main @ b17e08ef` mérésein áll.

## 0.0 MIÉRT `hold`

Az `E17-R07` alapján áll. **Mi oldja fel:** az `E17-R10` lezárása.

```ai-router
schema_version = 1
risk = "high"
# risk = "high" indoklás: Követési kapcsolatok, blokkolás és értesítések — kapcsolat-adat és biztonsági (safety) útvonal, `security-reviewer` KÖTELEZŐ.
allowed_paths = [
  "lib/features/community/data/repositories/notification_repository_impl.dart",
  "lib/features/community/data/repositories/social_graph_repository_impl.dart",
  "lib/features/community/application/controllers/",
  "lib/features/community/providers/community_providers.dart",
  "test/features/community/data/notification_repository_impl_test.dart",
  "test/features/community/data/social_graph_repository_impl_test.dart",
  "docs/rounds/e17-r11-community-notification-and-social-graph.md",
]
native_gate = false
gate_tests = [
  "test/features/community/",
  "test/privacy/",
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

**Kockázat = high, indoklás:** a kör diffje hálózatot, hitelesítést, adatvédelmet vagy felhasználói tartalmat érint, ezért a `security-reviewer` review-ja KÖTELEZŐ (AGENTS.md §15, `.ai/router.toml` high_risk_path_fragments).

## 1. Cél

A `CommunityNotificationsScreen`, `FollowersScreen`, `CommunitySearchScreen`, `LeaderboardScreen`, `CommunityChallengesScreen` és `SafetyRelationshipsScreen` valós adatot kap.

## 2. Jelenlegi állapot — mért tények (`main @ b17e08ef`)

- `notification_controller.dart:183`, `challenge_controller.dart:132`, `challenge_result_controller.dart:111` — három `throw UnimplementedError` override-seam.
- A `notification_repository.dart` és a `social_graph_repository.dart` domain-interfész LÉTEZIK; impl nincs. A `relationship_repository_impl.dart` MÁR létezik — a pre-flightnak MÉRNIE kell, mit fed le abból, ami itt kellene.
- Hat képernyő `reachable: false`; a `communityLeaderboardEnabled` kapu dart-define-függő.

## 3. Scope

**Benne van:** A `NotificationRepository` és a `SocialGraphRepository` HTTP-implementációja · a három override-seam production kitöltése · a blokkolás/némítás (safety) útvonal · a keresés és a ranglista bekötése a meglévő kapuk alatt.

**NINCS benne (tilos):**

- A hat képernyő route-ja — az az R12.
- Új safety-szabály vagy moderációs döntés.
- A `communityLeaderboardEnabled` alapértékének megváltoztatása.

## 4. Engedélyezett fájlok

(lásd az `ai-router` blokk teljes listáját)

## 5. Kötött architekturális döntések (ADR 0530)

### 5.1 A blokkolás a KLIENS oldalon is azonnal érvényesül, nem csak a szerver következő válaszában

Egy blokkolt felhasználó tartalma a következő frissítésig látható maradna. A safety-útvonalon a késleltetés maga a hiba.

### 5.2 A `relationship_repository_impl.dart` NEM íródik újra: a social-graph impl mellé kerül, ha a pre-flight átfedést mér

A meglévő impl a fában él és tesztelt. Újraírása scope-on kívüli regressziót nyitna; az átfedést a pre-flight §2-ben kell MÉRNI és rögzíteni.

## 6. Acceptance criteria

| # | Kritérium | Bizonyíték |
|---|---|---|
| A1 | A három override-seam production úton NEM dob `UnimplementedError`-t | teszt a szállított kompozíción |
| A2 | Blokkolás után a blokkolt felhasználó tartalma AZONNAL eltűnik a kliens-oldali nézetből | teszt, ami a szerver következő válaszát nem várja be |
| A3 | A meglévő `relationship_repository_impl.dart` szemantikája változatlan | meglévő tesztjei zölden + `git diff` |
| A4 | `communityLeaderboardEnabled=false` mellett a ranglista-útvonal nem hívódik | teszt mindkét flag-álláson |

### 6.1 Falszifikációs próba

**Valódi-sértés próba (KÖTELEZŐ, §10-ben dokumentálva):** Halaszd a blokkolás kliens-oldali érvényesítését a következő szerver-válaszig, futtasd a gate-et → az A2 cellának PIROSNAK kell lennie → állítsd vissza.

Minden fenti acceptance-cella MÉRT állítás: a §7 gate-parancsa futtatja őket, és a falszifikációs próba bizonyítja, hogy a cellák tényleg pirosra váltanak a hibás implementáción.

## 7. Kötelező ellenőrzések

```bash
tools/round-gate.sh test/features/community/ test/privacy/
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

- **A késleltetett blokkolás.** A safety-útvonalon a késleltetés maga a kár (5.1, A2).
- **A meglévő impl újraírása.** Scope-on kívüli regresszió tesztelt kódon (5.2, A3).
- **A kapu megkerülése.** Ranglista-hívás kikapcsolt kapu mellett (A4).

## 10. Implementation handoff — az implementer tölti ki

## 11. Review — a Claude tölti ki
