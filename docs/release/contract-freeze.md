# Contract freeze — StrumSight core-path szerződések

**Kör:** `E12-R28` (Chapter 12, Kör 28). **Normatív forrás:**
[ADR 0489](../adr/0489-ga-scope-classification-and-contract-freeze.md) D6.
Ez a fájl azokat a publikus contractokat sorolja fel, amelyekre a
[`ga-scope.md`](ga-scope.md) `ga`-besorolású capabilityje vagy a core
tanulási út lépései ma támaszkodnak — mindegyik sorhoz egy **nevesített,
ellenőrizhető eseményt** ír le feloldó feltételként (D6); egyik sor sem
mondja azt, hogy „szükség esetén módosítható" — az ilyen megfogalmazást a
`tool/release/verify_ga_scope.py` tiltólistával fogja.

## A táblázat oszlopai

| Oszlop | Jelentés |
|---|---|
| `contract` | mit fagyaszt be ez a sor, egy mondatban |
| `frozen_scope` | a befagyasztott contract pontos helye a fán (fájl, ill. sortartomány, ahol értelmezhető) |
| `evidence` | egy, a fán MA feloldható repó-relatív útvonal, ami a contract jelenlegi alakját bizonyítja |
| `resolution_condition` | a nevesített, ellenőrizhető esemény, ami a fagyasztást feloldja |

<!-- contract-freeze:begin -->
| contract | frozen_scope | evidence | resolution_condition |
|---|---|---|---|
| A 16 cohort-profil flag-kulcs zárt halmaza és a MÉRT kockázati besorolásuk (`high`/`medium`/`low`) nem bővül és nem szűkül csendben | `docs/beta/cohort-profiles.yaml` flags kulcshalmaza + `lib/core/feature_flags/feature_flag_registry.dart` risk mezői a 16 lefedett kulcsra | `lib/core/feature_flags/feature_flag_registry.dart` | Egy jövőbeli kör bővíti a cohort-profilt egy 17. flag-kulccsal (ADR 0489 "Nyitott" szakasza kimondottan megköveteli, hogy a GA-scope-ot vele EGYÜTT kell bővíteni), VAGY a Closed Beta ténylegesen lefut és a `beta-findings.md` D8 szerinti újramérése esedékessé válik. |
| A core tanulási út `practiceEngineV2Enabled`-függősége (a Practice Hub route flag-kapuja) nem enyhül csendben egy másik flagre | `lib/app/routing/app_router.dart:180-183` | `lib/app/routing/app_router.dart` | A `lib/features/practice/presentation/screens/practice_hub_screen.dart` saját doc-commentje szerinti "Kör 13 pre-flight" ténylegesen felold ja a Hub flag-kapuját, és a Hub attól kezdve flag nélkül elérhető. |
| `StorageMigrator.migrate()` soha nem dob kivételt, és egy sikertelen lépés a `schemaVersion`-t ott hagyja, ahol volt (per-lépés try/catch) | `lib/core/storage/storage_migrator.dart` | `test/e2e/upgrade_migration_test.dart` | Egy jövőbeli kör explicit ADR-t ír egy eltérő hibakezelési szerződésre (pl. fail-fast bevezetése egy nevesített migrációs lépésnél) — enélkül a jelenlegi never-throws szerződés fagyott. |
| A `verify_ga_scope.py`/`verify_beta_profile.py` kilépő-kód szemantikája (0 = ok, 1 = validációs találat, 2 = használati/formátumhiba) nem bővül csendben egy negyedik jelentéssel | `tool/release/verify_ga_scope.py`, `tool/release/verify_beta_profile.py` | `tool/release/verify_beta_profile.py` | A `test/tooling/ga_scope_test.dart` vagy a `test/tooling/beta_profile_test.dart` egy jövőbeli körben explicit új cellát kap egy negyedik kilépő-kódhoz — enélkül a három kód jelentése fagyott. |
<!-- contract-freeze:end -->

## Miért pont ez a négy sor

Az első sor a [D1](../adr/0489-ga-scope-classification-and-contract-freeze.md)
zárt halmazát védi — enélkül a `ga-scope.md` besorolása bármikor a lába alól
kicsúszhatna egy csendesen átírt kockázati szint vagy egy csendesen bővített
profil miatt. A második sor az egyetlen MA `ga`-besorolású capability
tényleges gépi kapuját fagyasztja — ez a sor a [D5](../adr/0489-ga-scope-classification-and-contract-freeze.md)
párja. A harmadik a core migrációs útvonal viselkedési szerződése (miért nem
dobhat kivételt egy megszakított frissítés), amit a `E12-R23`
(`client-migration.md`) már dokumentál, itt csak befagyasztva. A negyedik
a két testvér-eszköz (`verify_ga_scope.py` MOST, `verify_beta_profile.py`
`E12-R27`-ből) kilépő-kód szemantikáját védi, mert erre épül ennek a körnek
és a `beta_profile_test.dart`-nak a saját gate-elvárása is.
