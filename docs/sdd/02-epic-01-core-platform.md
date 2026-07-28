# StrumSight Software Design Document

## Chapter 2 — Epic 1: Core Platform & Infrastructure

**Dokumentumverzió:** 1.0  
**Implementációs állapot:** fejlesztésre kész  
**Repository:** `wolfcasaba/strumsight`  
**Célplatform:** Flutter, Android-first, később iOS  
**Backend:** FastAPI  
**Alapelv:** offline-first, on-device audiofeldolgozás  
**Végrehajtó:** Codex  
**Végrehajtási mód:** körönként, kis és önálló fejlesztési egységekben

---

# 1. Az Epic célja

Az Epic 1 célja a jelenlegi StrumSight kódbázis stabil, biztonságos és hosszú távon bővíthető platformmá alakítása.

Ez az Epic nem készít új gitártanító funkciót. Ehelyett létrehozza azt az architekturális alapot, amelyre a következő modulok biztonságosan felépíthetők:

- Practice Engine;
- Song Trainer;
- AI Guitar Teacher;
- Computer Vision;
- Audio Analysis 2.0;
- Practice Generator;
- Gamification;
- Community;
- Offline AI.

A jelenlegi alkalmazás működő funkcióit meg kell őrizni:

- Live chord és strum-direction detection;
- Analyze;
- Learn;
- Tuner;
- Metronome;
- Chord Library;
- Songs és Setlists;
- Practice Progress;
- Streak;
- Settings;
- Onboarding;
- Share;
- opcionális auth és cloud settings sync;
- diagnosztikai Lab mód;
- DSP- és ML-modellek.

Az Epic alatt tilos a DSP- vagy ML-algoritmusok eredményét indokolatlanul megváltoztatni.

# 2. Fontos architekturális pontosítás

A Chapter 1 dependency szabályát az alábbi pontosított szabály váltja fel.

## 2.1 Helyes függőségi irány

```text
Presentation ------> Application ------> Domain
       |                    |                 ^
       |                    |                 |
       +--------------------+------> Data ----+
```

Pontosabban:

- a `domain` semmilyen más rétegtől nem függhet;
- az `application` használhat domain modelleket és domain interfészeket;
- a `data` implementálhat domain repository interfészeket;
- a `presentation` használhat application controllereket és use case-eket;
- a domain soha nem importálhat data, presentation, Flutter, Dio vagy platform plugin osztályokat.

A következő irány tiltott:

```text
Domain -> Data
```

## 2.2 Nem lesz teljes, egyszeri újraírás

A jelenlegi alkalmazás 165 körüli Dart forrásfájlt, 159 Dart tesztfájlt, működő DSP-motort és több kész feature-t tartalmaz.

Ezért:

- tilos a teljes projekt egyszeri átszervezése;
- tilos egyszerre minden feature-t Clean Architecture struktúrába mozgatni;
- tilos működő DSP-kódot pusztán esztétikai okból átírni;
- minden migráció fokozatos;
- minden migráció után a teljes tesztcsomagnak zöldnek kell maradnia;
- ideiglenes kompatibilitási exportok használhatók;
- az új szabályokat először az új kódra, majd fokozatosan a régi kódra kell alkalmazni.

# 3. Jelenlegi technikai állapot

A repository jelenleg az alábbi fontos elemeket tartalmazza.

## 3.1 Flutter alkalmazás

Fő technológiák:

- Flutter;
- Dart;
- Riverpod;
- GoRouter;
- SharedPreferences;
- Dio;
- Flutter Secure Storage;
- `audio_streamer`;
- `fftea`;
- `audioplayers`;
- local notifications;
- localization angol és magyar nyelven.

Fő feature-ök:

```text
lib/features/
├── analyze/
├── auth/
├── chords/
├── diagnostics/
├── learn/
├── library/
├── live/
├── metronome/
├── onboarding/
├── progress/
├── settings/
├── share/
├── songs/
├── streak/
└── tuner/
```

## 3.2 Audio- és ML-réteg

A projekt már tartalmazza:

- valós idejű mikrofonfelvételt;
- Dart isolate-ban futó DSP pipeline-t;
- chord detectiont;
- strum-direction detectiont;
- onset detectiont;
- tempo trackinget;
- YIN pitch detectort;
- CRNN inference implementációkat;
- offline modell asseteket;
- Python training és evaluation eszközöket;
- valós és szintetikus audio teszteket;
- property-based regressziós teszteket.

## 3.3 Backend

A backend jelenleg tartalmazza:

- FastAPI alkalmazást;
- JWT authot;
- bcrypt jelszókezelést;
- SQLAlchemy modelleket;
- SQLite fejlesztői adatbázist;
- opcionális PostgreSQL konfigurációt;
- cloud settings szinkronizálást;
- diagnosztikai feltöltést;
- rate limitert;
- backend teszteket.

## 3.4 Azonosított technikai adósságok

Az Epic 1 az alábbi problémákat rendezi:

1. A Dart package neve még `music_theory`.
2. Az Android namespace és application ID még `com.musictheory.music_theory`.
3. Az iOS belső bundle név még `music_theory`.
4. A dokumentáció egyes részei nem követik a repository tényleges állapotát.
5. Sok feature közvetlenül más feature belső fájljait importálja.
6. A SharedPreferences használata sok providerben közvetlenül jelenik meg.
7. Több hely közvetlenül példányosít Dio klienst.
8. Bizonyos platformhibák el vannak nyelve.
9. A mikrofonengedély hibája tesztkörnyezetben és valódi eszközön nincs egyértelműen szétválasztva.
10. A konfiguráció statikus `String.fromEnvironment` mezők köré épül.
11. Nincs egységes alkalmazásszintű failure és result modell.
12. Nincs egységes strukturált logging.
13. A backend production módban még nem használ kötelező adatbázis-migrációt.
14. A backend indításkor közvetlenül meghívja a `create_all` műveletet.
15. A diagnosztikai és APK-letöltési végpontokat egyértelműen el kell választani a production API-tól.
16. A release build jelenleg debug kulccsal is aláírható.
17. A normál CI nem ellenőrzi teljes körűen a backendet.
18. Nincs automatikus architekturális dependency guard.

# 4. Az Epic hatóköre

## 4.1 Az Epic része

- repository- és fejlesztési szabályok;
- Codex végrehajtási szabályok;
- package- és alkalmazásazonosítók;
- app bootstrap;
- környezeti konfiguráció;
- feature flag rendszer;
- egységes result és failure modell;
- strukturált logging;
- lokális storage absztrakció;
- storage schema migration;
- hálózati kliens;
- auth session hardening;
- mikrofon- és audio lifecycle;
- közös zenei domain modellek;
- feature dependency szabályok;
- routing stabilizálása;
- backend production alapok;
- Alembic adatbázis-migráció;
- backend security hardening;
- diagnosztikai végpont elkülönítése;
- Flutter CI;
- backend CI;
- modell- és asset-integritás;
- release readiness ellenőrzések.

## 4.2 Az Epic nem tartalmazza

- új gitárleckék készítését;
- AI tanár implementálását;
- kamerás kézfelismerést;
- közösségi funkciókat;
- fizetést vagy előfizetést;
- új DSP-algoritmust;
- új neurális hálózat tervezését;
- teljes UI-redesignt;
- Guitar Pro importot;
- backing track generálást;
- felhőalapú audioelemzést.

# 5. Codex végrehajtási szabályok

A következő utasításokat minden fejlesztési kör elején át kell adni a Codexnek.

## 5.1 Kötelező működési szabályok

1. Először olvasd el:
   - `AGENTS.md`;
   - `README.md`;
   - `HANDOFF.md`;
   - az aktuális SDD-fejezetet;
   - az érintett feature tesztjeit.
2. Egy körben kizárólag az adott kör feladatait hajtsd végre.
3. Ne kezdj bele a következő körbe.
4. A meglévő működést ne változtasd meg, kivéve, ha azt az adott feladat előírja.
5. Ne módosíts DSP-konstansokat vagy ML-súlyokat.
6. Ne cserélj le dependencyt külön indoklás nélkül.
7. Ne készíts általános „nagy refaktort”.
8. Új absztrakciót csak konkrétan használt felelősséghez hozz létre.
9. Minden hibajavítást először reprodukáló teszttel kezdj.
10. Ne használj:
    - üres `catch` blokkot;
    - indokolatlan `dynamic` típust;
    - `print` hívást production kódban;
    - globális mutable state-et;
    - service locatort;
    - BuildContextet data vagy domain rétegben;
    - közvetlen pluginhívást UI widgetből.
11. Minden megváltoztatott fájlt formázz.
12. A teszteket külön parancsokként futtasd. Ne láncold őket egyetlen hosszú shell paranccsal, ha az fejlesztői gépen memóriahibát okozhat.
13. A kör végén frissítsd a `HANDOFF.md` fájlt.
14. A kör végén jelentésben add meg:
    - módosított fájlok;
    - megvalósított feladatok;
    - futtatott parancsok;
    - teszteredmények;
    - ismert kockázatok;
    - szándékosan elhalasztott feladatok.

## 5.2 Branch-elnevezés

```text
codex/epic-01-round-01-baseline
codex/epic-01-round-02-identity
codex/epic-01-round-03-bootstrap
```

Minden kör külön branch vagy legalább külön, önálló commit legyen.

## 5.3 Commit-formátum

```text
chore(core): establish architecture baseline
refactor(config): introduce validated app configuration
refactor(storage): centralize persistent key-value storage
fix(audio): enforce exclusive microphone ownership
feat(backend): add Alembic database migrations
ci(backend): add backend quality workflow
```

# 6. Célarchitektúra

A teljes migráció után az alkalmazás fő szerkezete a következő legyen:

```text
lib/
├── app/
│   ├── bootstrap/
│   │   ├── app_bootstrap.dart
│   │   └── bootstrap_result.dart
│   ├── config/
│   │   ├── app_config.dart
│   │   ├── app_environment.dart
│   │   └── feature_flags.dart
│   ├── routing/
│   │   ├── app_router.dart
│   │   ├── app_route.dart
│   │   └── route_guards.dart
│   ├── home_shell.dart
│   └── strumsight_app.dart
│
├── core/
│   ├── foundation/
│   │   ├── app_failure.dart
│   │   ├── app_result.dart
│   │   ├── clock.dart
│   │   ├── id_generator.dart
│   │   └── disposable.dart
│   ├── logging/
│   │   ├── app_logger.dart
│   │   ├── debug_app_logger.dart
│   │   └── log_redactor.dart
│   ├── network/
│   │   ├── api_client.dart
│   │   ├── dio_factory.dart
│   │   ├── auth_interceptor.dart
│   │   └── network_status.dart
│   ├── storage/
│   │   ├── key_value_store.dart
│   │   ├── shared_preferences_store.dart
│   │   ├── secure_store.dart
│   │   ├── storage_keys.dart
│   │   └── storage_migrator.dart
│   ├── platform/
│   │   ├── app_lifecycle.dart
│   │   ├── microphone_permission.dart
│   │   └── platform_info.dart
│   ├── audio/
│   │   ├── capture/
│   │   ├── lifecycle/
│   │   ├── codec/
│   │   └── dsp/
│   ├── music/
│   │   ├── chord.dart
│   │   ├── chord_event.dart
│   │   ├── strum.dart
│   │   ├── tempo.dart
│   │   └── tuning.dart
│   ├── theme/
│   ├── i18n/
│   └── widgets/
│
├── features/
│   └── feature_name/
│       ├── domain/
│       ├── application/
│       ├── data/
│       ├── presentation/
│       └── public.dart
│
├── l10n/
└── main.dart
```

A meglévő feature-öket nem kell egyszerre ebbe a szerkezetbe mozgatni.

# 7. Közös platformkontraktusok

## 7.1 AppResult

Az alkalmazás várható hibáit nem exceptionnel kell továbbítani a UI felé.

Kötelező alapszerkezet:

```dart
sealed class AppResult<T> {
  const AppResult();
}

final class Success<T> extends AppResult<T> {
  const Success(this.value);

  final T value;
}

final class Failure<T> extends AppResult<T> {
  const Failure(this.error);

  final AppFailure error;
}
```

Megjegyzés: amennyiben a `Failure` név ütközik más típussal, használható az `AppErrorResult` elnevezés.

## 7.2 AppFailure

```dart
sealed class AppFailure {
  const AppFailure({
    required this.code,
    required this.retryable,
    this.cause,
    this.stackTrace,
  });

  final String code;
  final bool retryable;
  final Object? cause;
  final StackTrace? stackTrace;
}
```

Kötelező kategóriák:

```text
NetworkFailure
AuthenticationFailure
PermissionFailure
StorageFailure
AudioFailure
MlFailure
ValidationFailure
ConfigurationFailure
CancelledFailure
UnknownFailure
```

A failure nem tartalmazhat közvetlenül felhasználónak szánt angol szöveget.

A UI a `code` alapján választ lokalizált üzenetet.

## 7.3 AppLogger

```dart
abstract interface class AppLogger {
  void debug(
    String event, {
    Map<String, Object?> fields = const {},
  });

  void info(
    String event, {
    Map<String, Object?> fields = const {},
  });

  void warning(
    String event, {
    Object? error,
    StackTrace? stackTrace,
    Map<String, Object?> fields = const {},
  });

  void error(
    String event, {
    required Object error,
    required StackTrace stackTrace,
    Map<String, Object?> fields = const {},
  });
}
```

Tilos logolni:

- jelszót;
- JWT-t;
- diagnosztikai tokent;
- teljes e-mail címet;
- nyers audioadatot;
- Base64 WAV-adatot;
- secure storage tartalmat.

## 7.4 KeyValueStore

```dart
abstract interface class KeyValueStore {
  String? readString(String key);
  int? readInt(String key);
  double? readDouble(String key);
  bool? readBool(String key);
  List<String>? readStringList(String key);

  Future<void> writeString(String key, String value);
  Future<void> writeInt(String key, int value);
  Future<void> writeDouble(String key, double value);
  Future<void> writeBool(String key, bool value);
  Future<void> writeStringList(String key, List<String> value);

  Future<void> remove(String key);
  bool contains(String key);
}
```

A feature-ök nem importálhatják közvetlenül a SharedPreferences package-et.

## 7.5 Clock

Időfüggő üzleti logika nem használhat közvetlenül korlátlan `DateTime.now()` hívásokat.

```dart
abstract interface class Clock {
  DateTime now();
}
```

Ez különösen fontos:

- streak;
- daily challenge;
- practice history;
- notification scheduling;
- weekly recap;
- session timestamps.

# 8. Nem funkcionális követelmények

## 8.1 Offline működés

Kijelentkezett állapotban, kikapcsolt diagnosztikával:

- az alkalmazás nem indíthat hálózati kérést;
- a Live működjön;
- a Tuner működjön;
- a Learn működjön;
- a Songs működjön;
- a Progress működjön;
- a lokális Library működjön.

## 8.2 Adatvédelem

- A hangfeldolgozás alapértelmezetten teljesen helyi.
- Nyers audio csak egyértelmű, opt-in Lab módban hagyhatja el az eszközt.
- A diagnosztikai feltöltés nem kapcsolható be véletlenül production buildben.
- A felhasználói beleegyezés állapota tartósan tárolandó.
- Token és jelszó soha nem kerülhet logba.

## 8.3 Audio erőforrás-kezelés

- Egyszerre csak egy modul birtokolhatja a mikrofont.
- Navigációkor a Live mikrofonja felszabadul.
- App háttérbe kerülésekor a mikrofon felszabadul.
- Sikertelen indítás után nem maradhat aktív stream.
- Többszöri `stop()` biztonságos legyen.
- Egymással versenyző `start()` és `stop()` hívások ne hagyjanak árva subscriptiont.

## 8.4 Teljesítmény

Az Epic 1 alatt nem engedélyezett:

- mérhető DSP-latency romlás;
- tartós memóriahasználat-növekedés;
- UI isolate-ba mozgatott DSP-feldolgozás;
- fölösleges PCM-másolás;
- audio frame-enkénti nagy objektumallokáció.

A konkrét teljesítményküszöböket először baseline mérésből kell meghatározni.

Az első cél:

```text
Az Epic 1 utáni mérés legfeljebb 5%-kal lehet rosszabb
a dokumentált baseline-hoz képest.
```

# 9. Fejlesztési körök

# Kör 1 — Repository baseline és Codex szabályrendszer

## Cél

A repository aktuális működésének dokumentálása, és a Codex számára kötelező projektutasítások létrehozása.

## Feladatok

### 1.1 `AGENTS.md` létrehozása

Hozd létre a repository gyökerében:

```text
AGENTS.md
```

Tartalmazza:

- projekt rövid leírása;
- offline-first szabály;
- audio privacy szabály;
- kötelező tesztparancsok;
- tiltott műveletek;
- architekturális irányok;
- DSP és ML módosítási korlátozások;
- HANDOFF frissítési kötelezettség;
- körönkénti fejlesztési szabály;
- Codex jelentési formátuma.

### 1.2 SDD könyvtár létrehozása

```text
docs/sdd/
├── 00-index.md
├── 01-architecture-principles.md
└── 02-epic-01-core-platform.md
```

A már elkészült SDD-fejezeteket ide kell elhelyezni.

### 1.3 ADR könyvtár létrehozása

```text
docs/adr/
├── 0001-offline-first.md
├── 0002-feature-first-clean-architecture.md
├── 0003-pure-dart-dsp-first.md
└── 0004-incremental-refactoring.md
```

### 1.4 Baseline dokumentáció

Hozd létre:

```text
docs/baseline/epic-01-start.md
```

Tartalma:

- Flutter verzió;
- Dart verzió;
- Python verzió;
- Dart forrásfájlok száma;
- Dart tesztfájlok száma;
- backend tesztfájlok száma;
- fő feature-ök;
- elérhető CI workflow-k;
- teszteredmények;
- ismert hibák;
- nem futtatható ellenőrzések indoklása.

### 1.5 Dokumentációs eltérések feljegyzése

A README egyes státuszai nem egyeznek a jelenlegi implementációval. Készíts listát az eltérésekről, de ebben a körben még ne írj át nagy mennyiségű dokumentációt.

## Kötelező ellenőrzések

```bash
flutter pub get
flutter analyze lib/ test/
flutter test
cd backend
python -m pytest -q
```

Amennyiben valamelyik eszköz nincs telepítve, ezt egyértelműen dokumentálni kell. Nem szabad sikeresnek állítani egy le nem futtatott tesztet.

## Elfogadási feltételek

- létrejött az `AGENTS.md`;
- létrejött az SDD-könyvtár;
- létrejöttek az első ADR-ek;
- a baseline dokumentált;
- alkalmazáskód nem változott;
- DSP-kód nem változott;
- a korábbi tesztek változatlanul sikeresek.

## Javasolt commit

```text
chore(core): establish repository and architecture baseline
```

# Kör 2 — Projektazonosítók és verziókezelés

## Cél

A `music_theory` örökölt projektazonosítók eltávolítása és a StrumSight márkanév egységesítése.

## Feladatok

### 2.1 Dart package átnevezése

A `pubspec.yaml` fájlban:

```yaml
name: strumsight
```

Cseréld le az összes:

```dart
package:music_theory/
```

importot erre:

```dart
package:strumsight/
```

### 2.2 Android namespace

A célazonosító:

```text
com.wolfcasaba.strumsight
```

Módosítandó:

- `android/app/build.gradle.kts`;
- Kotlin package deklaráció;
- Kotlin mappastruktúra;
- szükség szerint manifest referenciák.

A `TODO` megjegyzéseket el kell távolítani.

### 2.3 iOS bundle identifier

A cél:

```text
com.wolfcasaba.strumsight
```

Módosítandó:

- `ios/Runner.xcodeproj/project.pbxproj`;
- `CFBundleName`;
- teszt bundle azonosító;
- szükség szerint build konfigurációk.

### 2.4 Verzió forrásának egységesítése

A `pubspec.yaml` legyen a kliensverzió elsődleges forrása.

A README ne tartalmazzon egymásnak ellentmondó verzióállapotokat.

Ne változtasd meg önkényesen a verziószámot. Ebben a körben a meglévő `pubspec.yaml` verziót kell megtartani, hacsak release döntés nem született.

### 2.5 Régi név automatikus ellenőrzése

Készíts tesztet vagy scriptet, amely hibázik, ha production fájlokban megmarad:

```text
music_theory
com.musictheory.music_theory
package:music_theory
```

A történeti dokumentumok indokolt kivételeit allowlistben kell kezelni.

## Fontos migrációs kockázat

Az Android application ID megváltoztatása új alkalmazásként jelenhet meg a készüléken. Ez elfogadható a publikus store release előtt, de dokumentálni kell az ADR-ben.

## Kötelező tesztek

```bash
dart format --output=none --set-exit-if-changed lib test
flutter analyze lib/ test/
flutter test
flutter build apk --debug
```

## Elfogadási feltételek

- nincs aktív Dart import `package:music_theory` névvel;
- Android namespace egységes;
- iOS bundle azonosító egységes;
- az alkalmazás neve minden platformon StrumSight;
- az assetek és modellek elérési útjai változatlanul működnek;
- minden teszt zöld.

## Javasolt commit

```text
chore(app): align package and platform identifiers with StrumSight
```

# Kör 3 — App bootstrap és környezeti konfiguráció

## Cél

A jelenlegi statikus konfiguráció lecserélése validált, tesztelhető alkalmazáskonfigurációra.

## Új fájlok

```text
lib/app/bootstrap/app_bootstrap.dart
lib/app/bootstrap/bootstrap_result.dart
lib/app/config/app_environment.dart
lib/app/config/app_config.dart
lib/app/config/feature_flags.dart
lib/app/strumsight_app.dart
```

## Feladatok

### 3.1 AppEnvironment

```dart
enum AppEnvironment {
  development,
  lab,
  production,
}
```

Támogatott dart-define:

```text
STRUMSIGHT_ENV=development
STRUMSIGHT_ENV=lab
STRUMSIGHT_ENV=production
```

Ismeretlen értéknél az alkalmazás kontrollált configuration failure-rel álljon le.

### 3.2 FeatureFlags

Legalább:

```dart
final class FeatureFlags {
  const FeatureFlags({
    required this.accountEnabled,
    required this.diagnosticsEnabled,
    required this.labModeAvailable,
  });

  final bool accountEnabled;
  final bool diagnosticsEnabled;
  final bool labModeAvailable;
}
```

### 3.3 AppConfig

Tartalmazza:

- environment;
- API base URL;
- account feature flag;
- diagnostics feature flag;
- Lab mód engedélyezése;
- diagnosztikai token;
- build mode;
- alkalmazásverzió.

Production validáció:

- account bekapcsolása esetén HTTPS API URL kötelező;
- diagnostics tokennek nem lehet fejlesztői alapértéke;
- Lab mód alapértelmezetten kikapcsolt;
- üres vagy hibás URL nem fogadható el;
- production nem használhat localhost vagy `10.0.2.2` címet.

### 3.4 Bootstrap folyamat

A `main.dart` csak az alábbi feladatokat végezze:

1. Flutter binding inicializálása.
2. AppConfig létrehozása.
3. Szükséges platform dependencyk inicializálása.
4. Bootstrap hibák kezelése.
5. ProviderScope elindítása.
6. StrumSightApp megjelenítése.

A `StrumSightApp` kerüljön külön fájlba.

### 3.5 Provider override

Az `AppConfig` Riverpod provideren keresztül legyen elérhető.

Tesztben teljesen felülírható legyen.

### 3.6 Régi ApiConfig eltávolításának előkészítése

A `lib/core/api/api_config.dart` ideiglenesen maradhat kompatibilitási rétegként, de legyen deprecated.

Az új kód már ne importálja.

## Kötelező tesztek

- development konfiguráció;
- lab konfiguráció;
- production konfiguráció;
- production HTTP URL elutasítása;
- hiányzó production token elutasítása;
- kikapcsolt account esetén nincs API inicializálás;
- hibás environment érték;
- bootstrap failure képernyő.

## Elfogadási feltételek

- a `main.dart` minimális;
- az AppConfig tesztelhető;
- production konfiguráció fail-closed;
- a diagnosztika nem kapcsolható be véletlenül;
- a teljes alkalmazás továbbra is offline használható;
- nincs funkcionális regresszió.

## Javasolt commit

```text
refactor(config): introduce validated application bootstrap
```

# Kör 4 — Egységes failure, result és logging

## Cél

A hibakezelés egységesítése és a néma exception-elnyelés megszüntetése.

## Új fájlok

```text
lib/core/foundation/app_failure.dart
lib/core/foundation/app_result.dart
lib/core/logging/app_logger.dart
lib/core/logging/debug_app_logger.dart
lib/core/logging/log_redactor.dart
lib/core/logging/logger_provider.dart
```

## Feladatok

### 4.1 Result típus

Implementáld az `AppResult<T>` típust.

Biztosítson legalább:

- success értéket;
- failure értéket;
- `map`;
- `fold`;
- success/failure típusellenőrzést.

Ne készíts túlzott funkcionális programozási keretrendszert.

### 4.2 Failure hierarchia

Implementáld a 7.2 fejezetben meghatározott failure-kategóriákat.

Minden failure rendelkezzen:

- stabil gépi kóddal;
- retryable jelzővel;
- opcionális cause-zal;
- opcionális stack trace-szel.

### 4.3 Strukturált logger

Debug módban a logger írhat konzolra.

Production módban:

- ne használjon korlátlan `print` hívást;
- az érzékeny mezőket automatikusan maszkolja;
- a logger implementation később cserélhető legyen.

### 4.4 Auth vertikális migráció

Első proof-of-conceptként migráld az auth data/application réteget:

- `DioException` ne jusson el a UI-ba;
- repository `AppResult` típust adjon vissza;
- UI lokalizált failure code alapján jelenítsen meg hibát;
- token, jelszó és e-mail ne kerüljön logba.

### 4.5 Catch blokkok felülvizsgálata

Ebben a körben ellenőrizd különösen:

- `MicCapture`;
- `TokenStore`;
- auth repository;
- diagnostics uploader.

A platformhibák tesztkörnyezetben kezelhetők fake dependencyvel. Production kódban nem szabad ismeretlen hibát sikernek tekinteni.

## Kötelező tesztek

- success mapping;
- failure mapping;
- logger redaction;
- auth network failure;
- invalid credentials;
- token storage failure;
- unknown exception;
- UI-localization mapping.

## Elfogadási feltételek

- a UI nem kap DioExceptiont;
- a token nem jelenik meg logban;
- nincs üres catch blokk az érintett kódban;
- minden elnyelt hiba dokumentált és tesztelt;
- auth funkció nem regresszál.

## Javasolt commit

```text
refactor(core): add structured failures results and logging
```

# Kör 5 — Lokális storage infrastruktúra

## Cél

A SharedPreferences és Secure Storage elérés központosítása.

## Új fájlok

```text
lib/core/storage/key_value_store.dart
lib/core/storage/shared_preferences_store.dart
lib/core/storage/secure_store.dart
lib/core/storage/storage_keys.dart
lib/core/storage/storage_migrator.dart
lib/core/storage/storage_providers.dart

test/core/storage/
├── key_value_store_test.dart
├── storage_migrator_test.dart
└── in_memory_key_value_store.dart
```

## Feladatok

### 5.1 SharedPreferences egyszeri inicializálása

A SharedPreferences példány bootstrap során készüljön el, majd dependency injectionön keresztül kerüljön a providerekhez.

Ne történjen minden providerben külön:

```dart
SharedPreferences.getInstance()
```

### 5.2 Typed storage key katalógus

Minden kulcs egy helyen szerepeljen.

Példa:

```dart
abstract final class StorageKeys {
  static const schemaVersion = 'ss.storage.schema_version';
  static const themeMode = 'ss.settings.theme_mode';
  static const locale = 'ss.settings.locale';
  static const capoFret = 'ss.settings.capo_fret';
}
```

Az új kulcsok kapjanak `ss.` prefixet.

### 5.3 Storage schema version

Hozz létre idempotens migrációs rendszert.

Tulajdonságok:

- ugyanaz a migráció többször is biztonságosan lefuthat;
- a régi kulcs csak sikeres új írás után törölhető;
- részleges migráció után folytatható;
- sérült JSON nem omolhatja össze az appot;
- a hiba logolandó;
- lehetőség szerint az adat megőrzendő.

### 5.4 SecureStore

A secure token storage kerüljön közös core interfész mögé.

A secure storage platformhiba:

- ne legyen automatikus siker;
- ne legyen néma tokenvesztés;
- eredményezzen StorageFailure-t;
- a kijelentkezett állapot és a storage hiba különböztethető legyen meg.

## Kötelező tesztek

- primitive read/write;
- remove;
- migráció régi kulcsról újra;
- migráció kétszeri futtatása;
- félbeszakadt migráció;
- sérült JSON;
- secure store failure;
- fake store provider override.

## Elfogadási feltételek

- létrejött a storage infrastruktúra;
- új kód nem importál közvetlenül SharedPreferences-t;
- a meglévő feature-ök még működnek;
- a felhasználói adatok nem vesznek el.

## Javasolt commit

```text
refactor(storage): introduce injected persistent storage layer
```

# Kör 6 — Settings és core preference migráció

## Cél

Az egyszerű alkalmazásbeállítások áthelyezése az új storage rétegre.

## Migrálandó területek

- theme mode;
- locale;
- onboarding;
- confidence threshold;
- left-handed mode;
- capo;
- tuning reference;
- input latency;
- visual latency;
- Lab mode;
- nudge enabled;
- tuner tuning;
- metronome preference;
- practice speed;
- favorite chords;
- daily goal.

## Feladatok

### 6.1 Providerenkénti migráció

Minden provider:

- kapja dependencyként a KeyValueStore-t;
- ne tartson saját SharedPreferences példányt;
- immutable state-et használjon;
- megfelelően kezelje az inicializálást;
- ne írjon felül újabb állapotot későn beérkező régi read eredménnyel.

### 6.2 Race condition védelem

Meg kell őrizni vagy javítani a jelenlegi store race tesztek által védett viselkedést.

Példa probléma:

1. provider elindítja a storage readet;
2. felhasználó módosítja az értéket;
3. a későn visszaérkező read felülírja az új értéket.

Ez nem történhet meg.

### 6.3 Backward-compatible kulcsmigráció

A régi kulcsokból az új prefixel ellátott kulcsokba automatikus migráció történjen.

### 6.4 Tesztek fake store-ral

Az új tesztek ne függjenek közvetlenül SharedPreferences globális mock állapotától, amikor nincs rá szükség.

A régi teszteket fokozatosan kell átalakítani.

## Elfogadási feltételek

- a felsorolt providerek nem importálják a SharedPreferences package-et;
- a régi felhasználói értékek megmaradnak;
- a race regression tesztek zöldek;
- a localization parity zöld;
- onboarding állapot nem regresszál;
- notification preference megmarad.

## Javasolt commit

```text
refactor(settings): migrate application preferences to core storage
```

# Kör 7 — Felhasználói tartalom és progress storage migráció

## Cél

A komplexebb, JSON-alapú lokális tartalom központosított repository storage rétegre mozgatása.

## Migrálandó területek

- lesson progress;
- practice log;
- streak;
- songs;
- setlists;
- analyzed session library;
- session rename;
- session metadata;
- share recap alapadatai.

## Feladatok

### 7.1 Explicit serializer

Minden perzisztált modell rendelkezzen explicit:

```dart
toJson()
fromJson()
```

implementációval.

A dekódolás validálja:

- hiányzó mezők;
- hibás enum;
- negatív időtartam;
- hibás dátum;
- ismeretlen tuning;
- hiányzó chord label;
- túl nagy lista.

### 7.2 Repository-felelősség

A provider ne serializáljon közvetlenül JSON-t.

Helyes irány:

```text
Provider/Controller
        |
        v
Repository interface
        |
        v
Local repository implementation
        |
        v
KeyValueStore
```

### 7.3 Adatverziózás

A komplex modellek JSON-ja tartalmazzon schema versiont.

Példa:

```json
{
  "schemaVersion": 1,
  "items": []
}
```

### 7.4 Korrupció kezelése

Sérült rekord esetén:

- az app ne omoljon össze;
- a hibás rekord legyen elkülöníthető;
- a többi érvényes rekord töltődjön be;
- történjen strukturált logolás;
- ne törlődjön automatikusan az összes felhasználói adat.

### 7.5 Méretkorlátok

Dokumentáld és teszteld:

- library session maximum;
- practice log maximum;
- setlist maximum;
- song maximum;
- diagnosztikai payloadtól való elkülönítés.

## Elfogadási feltételek

- nincs közvetlen SharedPreferences import a migrált feature-ökben;
- a régi adatok migrálódnak;
- sérült rekord nem okoz teljes adatvesztést;
- a jelenlegi cap- és race-tesztek zöldek;
- a repository interfészek tesztelhetők.

## Javasolt commit

```text
refactor(data): migrate user content to versioned repositories
```

# Kör 8 — Hálózati kliens és auth hardening

## Cél

Egységes, biztonságos és feature flaggel vezérelt hálózati réteg létrehozása.

## Új fájlok

```text
lib/core/network/api_client.dart
lib/core/network/dio_factory.dart
lib/core/network/auth_interceptor.dart
lib/core/network/correlation_id_interceptor.dart
lib/core/network/network_failure_mapper.dart
lib/core/network/redacted_log_interceptor.dart
```

## Feladatok

### 8.1 DioFactory

A Dio példányokat kizárólag a DioFactory hozhatja létre.

Konfigurálja:

- base URL;
- connect timeout;
- send timeout;
- receive timeout;
- JSON content type;
- user agent vagy app version header;
- correlation ID;
- biztonságos logolás debug módban.

### 8.2 Account API client

Az account API csak akkor példányosítható, ha:

```text
featureFlags.accountEnabled == true
```

Kijelentkezett vagy account-disabled állapotban ne induljon automatikus settings sync hálózati kérés.

### 8.3 Auth interceptor

Feladat:

- bearer token csatolása;
- token kiolvasási hiba kezelése;
- 401 feldolgozása;
- session állapot érvénytelenítése;
- végtelen request retry megakadályozása.

### 8.4 Retry szabály

Automatikusan legfeljebb idempotens kérés ismételhető.

Megengedett:

- GET;
- opcionálisan biztonságos health check.

Nem ismételhető automatikusan:

- login;
- register;
- settings update;
- diagnostics upload.

### 8.5 Diagnostics kliens elkülönítése

A diagnosztikai uploader ne használja közvetlenül az account kliensét.

Külön kliens szükséges, külön feature flaggel és explicit consent ellenőrzéssel.

### 8.6 API response validáció

A következő hibákat kontrollált failure-ré kell alakítani:

- hiányzó `access_token`;
- hibás user JSON;
- ismeretlen status code;
- timeout;
- certificate hiba;
- connection refused;
- 401;
- 409;
- 422;
- 500.

## Elfogadási feltételek

- production kódban csak a DioFactory példányosít Dio-t;
- nincs token a logban;
- account-disabled build nem indít account requestet;
- POST kérés nem ismétlődik automatikusan;
- 401 kontrollált kijelentkezést eredményez;
- offline funkciók változatlanul működnek.

## Javasolt commit

```text
refactor(network): centralize API and authentication transport
```

# Kör 9 — Mikrofon- és audio lifecycle

## Cél

A mikrofon kizárólagos, versenyhelyzetektől mentes és tesztelhető kezelése.

## Új absztrakciók

```text
lib/core/platform/microphone_permission.dart
lib/core/audio/capture/audio_capture.dart
lib/core/audio/capture/audio_capture_factory.dart
lib/core/audio/lifecycle/audio_session_coordinator.dart
lib/core/audio/lifecycle/audio_session_lease.dart
lib/core/platform/app_lifecycle.dart
```

## Feladatok

### 9.1 Permission gateway

A platform permission plugin kizárólag gateway mögött használható.

```dart
abstract interface class MicrophonePermissionGateway {
  Future<MicrophonePermissionState> currentState();
  Future<MicrophonePermissionState> request();
}
```

Lehetséges állapotok:

```text
granted
denied
permanentlyDenied
restricted
unavailable
```

Production környezetben a pluginhiba nem jelenthet automatikusan `granted` állapotot.

Tesztben fake gatewayt kell használni.

### 9.2 AudioSessionCoordinator

Egyszerre csak egy owner használhatja a mikrofont.

Lehetséges owner:

```text
live
tuner
analyzeRecorder
latencyCalibration
diagnostics
```

A coordinator lease-t adjon:

```dart
final lease = await coordinator.acquire(AudioOwner.live);
await lease.release();
```

Második owner esetén:

- vagy kontrollált busy failure;
- vagy az előző owner explicit leállítása.

A választott viselkedést ADR-ben dokumentálni kell. Alapértelmezésként kontrollált busy failure javasolt.

### 9.3 Start/stop versenyhelyzetek

Védeni kell:

- két párhuzamos start;
- start közbeni stop;
- stop közbeni új start;
- route elhagyása start közben;
- permission dialog közbeni route elhagyása;
- app pause;
- app resume;
- engine exception.

### 9.4 App lifecycle

Az alkalmazás háttérbe kerülésekor:

- mikrofon leáll;
- wakelock felszabadul;
- subscription megszűnik;
- isolate erőforrásai felszabadulnak.

Resume után a mikrofon ne induljon automatikusan a felhasználó tudta nélkül, kivéve, ha ezt külön UX-specifikáció engedélyezi.

### 9.5 Meglévő autoDispose védelem

A Live providerek `autoDispose` viselkedését meg kell őrizni.

Külön regressziós teszt védje, hogy Live képernyő elhagyása után nincs aktív mic stream.

### 9.6 DSP változtatási tilalom

Ebben a körben nem módosítható:

- FFT méret;
- hop size;
- onset threshold;
- chord dictionary;
- Viterbi paraméterek;
- CRNN súlyok;
- strum classifier paraméterek.

## Kötelező tesztek

- permission denied;
- permanently denied;
- plugin unavailable;
- két owner;
- start/start;
- start/stop race;
- stop/stop;
- route leave;
- app background;
- engine throw;
- mic release regression;
- wakelock release.

## Elfogadási feltételek

- egyszerre legfeljebb egy mic owner;
- nincs árva stream;
- nincs néma permission success;
- a jelenlegi audio tesztek zöldek;
- DSP-output parity változatlan.

## Javasolt commit

```text
fix(audio): enforce safe exclusive microphone lifecycle
```

# Kör 10 — Közös zenei és audio domain

## Cél

A több feature által használt modellek eltávolítása a `live` és `learn` feature belső könyvtáraiból.

## Elsőként migrálandó modellek

- `Chord`;
- `Strum`;
- `StrumDirection`;
- `ChordEvent`;
- tuning modellek;
- WAV encoder/decoder közös részei;
- általános lesson timing értékobjektumok, amennyiben nem Learn-specifikusak.

## Célhelyek

```text
lib/core/music/
lib/core/audio/codec/
```

## Feladatok

### 10.1 Domain model mozgatása

A több feature által használt modellek kerüljenek közös, Flutter-független helyre.

A domain modellek nem importálhatnak:

- Fluttert;
- Riverpodot;
- Dio-t;
- SharedPreferences-t;
- widgetet;
- l10n osztályt.

### 10.2 Kompatibilitási re-export

Az átmeneti időszakban a régi fájlok exportálhatják az új modellt:

```dart
@Deprecated('Import from core/music/strum.dart')
export '../../../core/music/strum.dart';
```

Így a migráció több kisebb körben is elvégezhető.

### 10.3 DSP megosztása

Az Analyze és Tuner jelenleg több Live DSP-komponenst használ.

Első körben ne mozgasd át egyszerre a teljes DSP-t. Hozz létre világos közös audio/DSP boundaryt, és csak olyan fájlt mozgass, amely:

- legalább két feature által használt;
- nem tartalmaz UI- vagy providerfüggést;
- parity tesztekkel védett.

### 10.4 Feature public API

Minden feature létrehozhat:

```text
lib/features/<feature>/public.dart
```

Más feature csak:

- a public API-t;
- vagy közös core modellt

importálhat.

Közvetlen import más feature `screens`, `widgets`, `providers`, `data` vagy `engine` könyvtárából hosszú távon tiltott.

### 10.5 Architecture guard

Hozz létre automatikus importellenőrzést.

Javasolt hely:

```text
tool/check_architecture.dart
test/core/architecture_dependency_test.dart
```

Első verzió:

- megtiltja, hogy `core` feature-t importáljon;
- megtiltja, hogy domain Fluttert importáljon;
- megtiltja az új, nem allowlistelt cross-feature belső importot;
- a meglévő eltéréseket ideiglenes allowlist tartalmazza.

Az allowlist csak csökkenhet. Új elem hozzáadása külön indoklást és ADR-t igényel.

## Kötelező parity tesztek

- chord equality;
- strum serialization;
- analyze result serialization;
- DSP fixtures;
- CRNN fixture parity;
- timeline property tests;
- tuner YIN tesztek.

## Elfogadási feltételek

- a közös modelleknek egyetlen kanonikus definíciójuk van;
- a régi importok átmenetileg működnek;
- core nem függ feature-től;
- új cross-feature belső importot a CI blokkol;
- nincs DSP regresszió.

## Javasolt commit

```text
refactor(domain): extract shared music and audio contracts
```

# Kör 11 — Routing és alkalmazás-shell stabilizálása

## Cél

A route stringek, route argumentumok és lifecycle viselkedés biztonságosabbá tétele.

## Új fájlok

```text
lib/app/routing/app_route.dart
lib/app/routing/app_router.dart
lib/app/routing/route_guards.dart
```

## Feladatok

### 11.1 Route katalógus

A route pathok ne legyenek szétszórt stringek.

```dart
abstract final class AppRoutes {
  static const welcome = '/welcome';
  static const live = '/live';
  static const analyze = '/analyze';
  static const learn = '/learn';
}
```

### 11.2 Argumentumvalidáció

A jelenlegi:

```dart
state.extra as AnalyzedSession
```

típusú kontrollálatlan castokat meg kell szüntetni.

Hibás vagy hiányzó argumentum esetén:

- kontrollált error route;
- vagy biztonságos visszairányítás.

### 11.3 Redirect frissülés

Az onboarding és auth redirect viselkedés legyen reaktív és tesztelhető.

Nem történhet:

- redirect loop;
- onboarding flicker;
- bejelentkezés utáni rossz route;
- logout utáni védett route-on maradás.

### 11.4 Shell lifecycle

A bottom-navigation továbbra is biztosítsa, hogy a Live képernyő elhagyása leállítsa az audio engine-t.

### 11.5 Route tesztek

Tesztelendő:

- első indítás;
- onboarding kész;
- közvetlen deep link;
- hibás session argumentum;
- Live → Settings;
- Live → Tuner;
- visszanavigálás;
- mic release.

## Elfogadási feltételek

- nincs kontrollálatlan route cast;
- route pathok centralizáltak;
- nincs redirect loop;
- audio lifecycle tesztek zöldek;
- a meglévő navigáció változatlanul használható.

## Javasolt commit

```text
refactor(routing): centralize routes and validate navigation state
```

# Kör 12 — Backend konfiguráció és adatbázis-migráció

## Cél

A FastAPI backend production-kompatibilis adatbázis-alapjának kialakítása.

## Új elemek

```text
backend/alembic.ini
backend/alembic/
backend/app/database.py
backend/app/config.py
backend/app/main.py
backend/tests/test_migrations.py
```

## Feladatok

### 12.1 Alembic bevezetése

Hozz létre kezdeti migrációt:

- `users`;
- `user_settings`;
- indexek;
- foreign key;
- unique constraint;
- timestamp mezők.

### 12.2 `create_all` production eltávolítása

Production módban tilos automatikusan:

```python
Base.metadata.create_all(...)
```

A táblákat kizárólag migráció hozhatja létre.

Tesztben vagy lokális fejlesztői módban használható explicit helper, de ne legyen rejtett production viselkedés.

### 12.3 Database dependency tisztítása

A database engine ne importáláskor, globális konfigurációból, nehezen felülírható módon jöjjön létre.

A `create_app` legyen tesztelhető külön:

- Settings;
- database URL;
- dependency override;
- feature flag

paraméterezéssel.

### 12.4 PostgreSQL production validáció

Production esetén:

- PostgreSQL javasolt és dokumentált;
- SQLite használata explicit engedélyhez kötött;
- connection hiba readiness failure legyen;
- secret ne kerüljön logba.

### 12.5 Health endpointok

Külön:

```text
GET /health/live
GET /health/ready
```

`live`:

- process működik.

`ready`:

- adatbázis elérhető;
- migráció kompatibilis;
- szükséges konfiguráció érvényes.

### 12.6 OpenAPI contract

Az API title, version és route-ok legyenek determinisztikusak.

Készíts snapshot vagy contract tesztet a lényeges schema részekre.

## Kötelező backend tesztek

- üres adatbázis migrálása latest verzióra;
- upgrade;
- downgrade legalább egy lépésben, amennyiben támogatott;
- production create_all tiltás;
- readiness DB nélkül;
- readiness DB-vel;
- settings dependency override;
- SQLite tesztadatbázis izoláció.

## Elfogadási feltételek

- production schema Alembicből készül;
- a backend nem hoz létre rejtetten táblákat;
- readiness ellenőrzi az adatbázist;
- tesztek külön adatbázissal futnak;
- a meglévő auth/settings API nem regresszál.

## Javasolt commit

```text
feat(backend): add explicit database migrations and readiness checks
```

# Kör 13 — Backend security és diagnosztikai elkülönítés

## Cél

A production account API és a fejlesztői Lab infrastruktúra biztonságos szétválasztása.

## Feladatok

### 13.1 Lab route feature flag

A következő route-ok production környezetben alapértelmezetten ne legyenek regisztrálva:

- diagnostics upload;
- diagnostics health;
- APK download.

A route-regisztrációt environment és feature flag vezérelje.

### 13.2 Diagnosztikai token

Production vagy publikus Lab deploy esetén:

- fejlesztői alapértelmezett token tiltott;
- üres token tiltott;
- token logolása tiltott;
- összehasonlítás lehetőség szerint konstans idejű legyen.

A token továbbra sem tekintendő felhasználói authnak. Csak spam gate.

### 13.3 Streaming upload limit

A jelenlegi teljes `request.body()` beolvasás helyett az upload legyen méretkorlátozott streaming.

Követelmények:

- a limit túllépésekor az olvasás álljon le;
- ne kerüljön teljes, túlméretes payload memóriába;
- ideiglenes fájlba írás;
- siker esetén atomikus rename;
- félbeszakadt feltöltés után temp fájl törlése.

### 13.4 Fájlrendszerbiztonság

- session ID sanitization;
- path traversal tiltás;
- fájlnévütközés kezelése;
- adatkönyvtár explicit konfiguráció;
- minimális szükséges fájljogosultság;
- index írási hiba kezelése.

### 13.5 Jelszó 72 byte validáció

A bcrypt 72 byte-os korlátját nem karakter-, hanem UTF-8 byte-hossz alapján kell validálni.

Tilos a jelszót némán truncatálni.

Helyes működés:

- 72 byte vagy kevesebb: elfogadható;
- 72 byte felett: 422 validation error;
- Unicode jelszó: byte-hossz alapján ellenőrizendő.

### 13.6 Auth hibák

Login esetén az ismeretlen e-mail és hibás jelszó azonos külső választ adjon.

A backend logolhat belső hibakategóriát, de nem logolhat jelszót vagy teljes tokent.

### 13.7 Rate limiter

Dokumentáld:

- single-process korlát;
- multi-worker környezetben nem megosztott;
- production scaling esetén Redis vagy más közös store szükséges.

Ebben az Epicben nem kötelező Redis bevezetése, ha a backend egyetlen processzként fut.

## Kötelező tesztek

- Lab route hiányzik production módban;
- hibás token;
- túl nagy payload;
- félbeszakadt upload;
- path traversal;
- 72 byte Unicode password;
- 73 byte password;
- azonos login error;
- production default secret tiltás;
- wildcard CORS tiltás.

## Elfogadási feltételek

- production account API nem tartalmaz Lab route-ot;
- túlméretes upload nem tölti meg a memóriát;
- jelszó nem csonkolódik;
- nincs secret logolás;
- backend security tesztek zöldek.

## Javasolt commit

```text
fix(backend): isolate lab services and harden authentication
```

# Kör 14 — Flutter CI és release pipeline

## Cél

Olyan CI létrehozása, amely hibás kódból nem készít kiadható buildet.

## Feladatok

### 14.1 Format gate

A CI futtassa:

```bash
dart format --output=none --set-exit-if-changed lib test
```

Szükség szerint a `tool` könyvtárat is.

### 14.2 Analyze gate

```bash
flutter analyze lib/ test/ tool/
```

Figyelmeztetés ne legyen figyelmen kívül hagyva.

### 14.3 Test gate

Külön lépések:

```bash
flutter test
flutter test test/property
```

A property seed továbbra is változó legyen.

### 14.4 Architekturális gate

```bash
dart run tool/check_architecture.dart
```

### 14.5 Build típusok elkülönítése

Legyen külön:

```text
Development APK
Lab APK
Production release
```

Szabályok:

- Development és Lab build használhat fejlesztői aláírást.
- Production release nem használhat debug signing configot.
- Production release signing secret hiányában a workflow álljon le.
- Lab konfiguráció ne kerülhessen production artifactba.

### 14.6 Artifact elnevezés

Az artifact tartalmazza:

- app verzió;
- build number;
- commit rövid SHA;
- environment.

Példa:

```text
strumsight-1.0.0-42-a1b2c3d-lab.apk
```

### 14.7 Dependency és asset ellenőrzés

CI ellenőrizze:

- minden pubspec asset létezik;
- ML asset nem üres;
- checksum manifest egyezik;
- l10n parity zöld;
- régi package név nem került vissza.

### 14.8 Coverage baseline

Készíts coverage reportot.

Ebben a körben ne vezess be önkényes globális küszöböt. Először dokumentáld a baseline-t.

A kritikus új core modulok célja:

```text
legalább 90% line coverage
```

Ez az új modulokra vonatkozik:

- config;
- result/failure;
- storage migrator;
- network failure mapper;
- audio session coordinator.

## Elfogadási feltételek

- format hiba blokkolja a buildet;
- analyze hiba blokkolja a buildet;
- teszthiba blokkolja a buildet;
- architekturális hiba blokkolja a buildet;
- production release nem használ debug kulcsot;
- artifact egyértelműen azonosítható.

## Javasolt commit

```text
ci(flutter): enforce quality architecture and release gates
```

# Kör 15 — Backend és ML CI

## Cél

A backend és a modell-assetek önálló minőségkapujának létrehozása.

## Feladatok

### 15.1 Backend CI workflow

Új workflow:

```text
.github/workflows/backend-ci.yml
```

Futtassa:

```bash
python -m pytest -q
python -m ruff check app tests
python -m ruff format --check app tests
alembic upgrade head
```

A tesztadatbázis izolált legyen.

### 15.2 Dependencyk szétválasztása

Javasolt:

```text
backend/requirements.txt
backend/requirements-dev.txt
```

Production dependency ne tartalmazzon fölösleges tesztcsomagokat.

### 15.3 Python verzió rögzítése

A CI-ben és dokumentációban egységes támogatott Python verzió szerepeljen.

### 15.4 ML asset manifest

Hozd létre:

```text
assets/ml/model_manifest.json
```

Tartalmazza modellenként:

- fájlnév;
- SHA-256;
- formátumverzió;
- input shape;
- output classes;
- training run vagy model card azonosító;
- export script verzió;
- létrehozás dátuma.

### 15.5 Flutter–Python inference parity

A CI ellenőrizze legalább fixture alapon:

- a Python export;
- a Dart betöltés;
- output shape;
- checksum;
- numerikus tolerancia.

A teljes ML training ne fusson minden pull requestben.

Megmarad külön manuális workflow-ként.

### 15.6 Modellcsere szabály

Új modell asset csak akkor merge-elhető, ha:

- model card frissült;
- manifest frissült;
- checksum frissült;
- parity test zöld;
- real-audio vagy honest-eval eredmény dokumentált;
- a shipping modellhez képest nincs elhallgatott regresszió.

## Elfogadási feltételek

- backend PR nem merge-elhető piros pytest vagy Ruff mellett;
- migráció ellenőrzött;
- modell assethez tartozik manifest;
- hibás vagy cserélt bináris assetet a CI felismer;
- training továbbra is külön, manuálisan indítható.

## Javasolt commit

```text
ci(platform): add backend and model integrity gates
```

# Kör 16 — Végső regresszió, teljesítmény és dokumentáció

## Cél

Az Epic 1 lezárása teljes rendszerellenőrzéssel.

## Feladatok

### 16.1 Teljes regressziós teszt

Külön futtatandó:

```bash
flutter pub get
dart format --output=none --set-exit-if-changed lib test tool
flutter analyze lib/ test/ tool/
flutter test
flutter test test/property
dart run tool/check_architecture.dart
```

Backend:

```bash
cd backend
python -m ruff check app tests
python -m ruff format --check app tests
python -m pytest -q
alembic upgrade head
```

### 16.2 Offline network guard

Készíts integrációs vagy provider-szintű tesztet:

- account disabled;
- diagnostics disabled;
- logged out;
- app fő funkcióinak inicializálása.

Elvárás:

```text
0 hálózati request
```

### 16.3 Audio regresszió

Valódi Android készüléken ellenőrizendő:

- Live indítás;
- Live leállítás;
- Live → Settings;
- Live → Tuner;
- app háttérbe küldése;
- képernyő lezárása;
- permission denial;
- permission későbbi engedélyezése;
- hosszabb session;
- microphone indicator kikapcsolása a session végén.

### 16.4 Teljesítménymérés

Dokumentálandó:

- app cold start;
- Live start ideje;
- feldolgozási latency;
- átlagos CPU;
- memória;
- 10 perces session utáni memória;
- dropped frame;
- akkumulátorhasználat, amennyiben mérhető.

A baseline-hoz képest 5%-nál nagyobb romlást meg kell vizsgálni.

### 16.5 README frissítése

A README tükrözze a tényleges állapotot:

- kész feature-ök;
- architektúra;
- futtatás;
- build environmentek;
- backend;
- Lab mód;
- tesztelés;
- offline privacy;
- modell assetek.

### 16.6 HANDOFF egyszerűsítése

A HANDOFF maradjon aktuális operatív dokumentum, de ne legyen végtelen történeti napló.

Javasolt felépítés:

```text
1. Current release state
2. What is working
3. Known blockers
4. Current branch
5. Last completed round
6. Exact next task
7. Required verification
8. Historical archive link
```

A régi részletes körnapló külön archív fájlba mozgatható.

### 16.7 Epic lezáró dokumentum

Hozd létre:

```text
docs/sdd/epic-01-completion-report.md
```

Tartalma:

- elkészült körök;
- kihagyott feladatok;
- architekturális változások;
- teszteredmények;
- teljesítménymérés;
- ismert kockázatok;
- dependency allowlist;
- következő Epic előfeltételei.

## Elfogadási feltételek

- minden CI zöld;
- nincs közvetlen SharedPreferences használat feature-kben;
- nincs közvetlen Dio-példányosítás feature-kben;
- nincs `music_theory` aktív projektazonosító;
- nincs debug-aláírású production release;
- production backend Alembicet használ;
- production backend nem tartalmaz Lab route-okat;
- mikrofon minden kilépési útvonalon felszabadul;
- account és diagnostics nélkül nincs hálózati forgalom;
- az architekturális allowlist nem nőtt indokolatlanul;
- dokumentáció megfelel a tényleges kódnak.

## Javasolt commit

```text
docs(core): close Epic 1 platform foundation
```

# 10. Epic 1 végső Definition of Done

Az Epic 1 kizárólag akkor tekinthető késznek, ha minden alábbi állítás igaz.

## Kódszerkezet

- [ ] Létezik és érvényes az `AGENTS.md`.
- [ ] Az SDD a repositoryban található.
- [ ] Az architekturális döntések ADR-ekben dokumentáltak.
- [ ] A Dart package neve `strumsight`.
- [ ] A platformazonosítók StrumSight-specifikusak.
- [ ] A `main.dart` csak bootstrappel.
- [ ] Az AppConfig validált és tesztelhető.
- [ ] Az új core szolgáltatások dependency injectionnel érhetők el.
- [ ] A core réteg nem importál feature-t.
- [ ] A domain réteg nem importál Fluttert.

## Hibakezelés

- [ ] Létezik közös AppResult.
- [ ] Létezik közös AppFailure.
- [ ] DioException nem jut el a UI-ba.
- [ ] Platform exception nem minősül automatikusan sikernek.
- [ ] Nincs üres catch blokk az érintett production kódban.
- [ ] Felhasználói hibaüzenetek lokalizáltak.

## Storage

- [ ] A feature-ök nem importálnak közvetlenül SharedPreferences-t.
- [ ] A secure storage közös interfész mögött van.
- [ ] A storage schema verziózott.
- [ ] A régi kulcsok migrálódnak.
- [ ] A migráció idempotens.
- [ ] Sérült rekord nem okoz teljes adatvesztést.

## Hálózat

- [ ] A DioFactory az egyetlen production Dio factory.
- [ ] Account-disabled állapotban nincs account request.
- [ ] Diagnostics-disabled állapotban nincs diagnostics request.
- [ ] Token, jelszó és nyers audio nincs logban.
- [ ] 401 kontrollált session invalidációt okoz.
- [ ] POST kérés nem kap veszélyes automatikus retryt.

## Audio

- [ ] Egyszerre egy mic owner lehetséges.
- [ ] Route elhagyásakor felszabadul a mikrofon.
- [ ] App background esetén felszabadul a mikrofon.
- [ ] Start/stop race tesztelt.
- [ ] Az `autoDispose` regresszió védett.
- [ ] DSP parity változatlan.
- [ ] ML asset parity változatlan.

## Backend

- [ ] Alembic kezeli a schema migrációt.
- [ ] Production nem futtat automatikus `create_all` műveletet.
- [ ] Létezik liveness endpoint.
- [ ] Létezik readiness endpoint.
- [ ] Production secret validáció fail-closed.
- [ ] Lab route-ok production módban nincsenek regisztrálva.
- [ ] A diagnosztikai upload streaming és méretkorlátozott.
- [ ] A bcrypt 72 byte korlát megfelelően validált.
- [ ] A backend tesztek CI-ben futnak.

## CI és release

- [ ] Format gate aktív.
- [ ] Analyze gate aktív.
- [ ] Flutter test gate aktív.
- [ ] Property test gate aktív.
- [ ] Architecture gate aktív.
- [ ] Backend pytest gate aktív.
- [ ] Backend Ruff gate aktív.
- [ ] Model checksum gate aktív.
- [ ] Production release nem használ debug signingot.
- [ ] Build artifact verziózott és azonosítható.

# 11. Az Epic eredménye

Az Epic 1 végére a StrumSight:

- továbbra is teljesen használható internet nélkül;
- megőrzi a jelenlegi DSP- és ML-funkciókat;
- biztonságosan kezeli a mikrofont;
- egységesen kezeli a hibákat;
- nem szórja szét a storage és network logikát;
- production-kompatibilis backendet kap;
- tiszta CI/CD minőségkapukkal rendelkezik;
- fokozatosan migrálható architektúrát kap;
- felkészül a teljes gitártanító platform következő moduljaira.

Az Epic 1 lezárása után kezdhető el:

```text
Chapter 3 — Epic 2: Practice Engine
```
