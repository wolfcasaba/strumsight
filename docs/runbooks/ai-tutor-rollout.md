# AI Tutor — Rollout és Incident Runbook

- **Verzió:** 1.0 (2026-08-06)
- **Epic:** 4 — AI Gitártanár
- **Kör:** E04-R24 (záró)

## Flag-ek

Az AI Tutor két feature flag mögött van:

| Flag | Alapérték | Jelentés |
|---|---|---|
| `FeatureFlags.aiTutorEnabled` | `false` | A teljes tutor feature elérhetősége (route-ok, UI) |
| `FeatureFlags.aiTutorCloudEnabled` | `false` | Cloud AI backend proxy hívások engedélyezése |

**Jelenlegi állapot (merge-kor): mindkét flag `OFF`.** A GA-flip külön
user/termék döntés.

A flag-ek a `lib/app/config/feature_flags.dart`-ban vannak definiálva, és az
`AppConfig.resolve()` validálja őket.

## Rollout lépcsők

### 1. Internal (fejlesztői build)

- `aiTutorEnabled = true`, `aiTutorCloudEnabled = true`
- Csak fejlesztői eszközökön (`AppEnvironment.development` vagy `lab`)
- Fake gateway használata validációra

### 2. Lab (belső teszt)

- `aiTutorEnabled = true`, `aiTutorCloudEnabled = true`
- `AppEnvironment.lab` build
- Valós backend proxy, staging provider API kulcs
- Belső tesztelők (csapat + barátok)

### 3. Opt-in Beta (korlátozott production)

- `aiTutorEnabled = true`, `aiTutorCloudEnabled = true`
- `AppEnvironment.production` build
- Explicit consent szükséges (a feature első használatakor)
- Rate limiting aktív
- Monitorozás: hibaarány, latency, usage

### 4. Limited Production (fokozatos kiterjesztés)

- Fokozatos %-os rollout (pl. 10% → 25% → 50% → 100%)
- Ha a `aiTutorCloudEnabled` server-side flag, akkor a rollout %-os
- Folyamatos evaluation metrika monitorozás

### 5. GA (általános elérhetőség)

- `aiTutorEnabled = true`, `aiTutorCloudEnabled = true`
- Minden felhasználó számára elérhető
- **Ez KÜLÖN user/termék döntés — a merge nem flippeli GA-ra**

## Rollback

### Azonnali rollback (incidens esetén)

Ha a tutor feature problémát okoz (hiba, safety, költség), a rollback lépései:

1. **Feature flag OFF:** `aiTutorEnabled = false` → a tutor route-ok nem
   regisztráltak, a `/tutor/*` URL-ek a LiveScreen-re esnek vissza.

2. **Cloud flag OFF:** `aiTutorCloudEnabled = false` → a backend proxy hívások
   letiltva, csak a `LocalTutorFallback` (offline determinisztikus coaching)
   működik.

3. **Teljes letiltás:** mindkét flag OFF → a tutor feature eltűnik a UI-ból,
   nincs háttérhívás, nincs adatvesztés. A felhasználó korábbi AI-adatai
   megmaradnak (a Data képernyőn keresztül törölhetők).

### Rollback verifikáció

```bash
# Flag OFF → tutor route-ok nem elérhetők
flutter test test/features/ai_tutor/presentation/tutor_home_screen_test.dart --plain-name "OFF"

# Cloud OFF → nincs network request
flutter test test/app/offline_network_guard_test.dart --plain-name "cloud OFF"
```

## Monitorozás

A rollout során figyelendő metrikák:

| Metrika | Küszöb | Forrás |
|---|---|---|
| Safety coverage | ≥ 98% | `run_eval.dart` safety metrika |
| Schema validity | ≥ 95% | `run_eval.dart` schema metrika |
| Action validity | ≥ 90% | `run_eval.dart` action metrika |
| Groundedness | ≥ 90% | `run_eval.dart` groundedness metrika |
| Backend hibaarány | < 1% | Backend metrics |
| P95 latency | < 5s | Backend metrics |
| Usage limit találatok | < 0.1% | Backend metrics |

## Incident eljárás

1. **Észlelés:** CI piros, user report, vagy monitorozási riasztás
2. **Azonnali:** `aiTutorEnabled = false` → nincs UI
3. **Kivizsgálás:** logok, evaluation metrikák, backend hibák
4. **Javítás:** hotfix PR a megfelelő rétegben
5. **Visszaállítás:** flag ON + verifikáció

## GA döntési pont

A GA-flip az alábbi feltételek EGYÜTTES teljesülése esetén történhet:

- [ ] Valós eszközös hálózatvesztés + background teszt (HORIZON)
- [ ] Belső + Lab rollout legalább 2 hétig stabil
- [ ] Minden evaluation metrika a küszöb felett
- [ ] Backend költség a tervezett kereten belül
- [ ] User visszajelzések pozitívak
- [ ] **Explicit user/termék döntés**

A döntést a `docs/adr/`-ben kell dokumentálni.
