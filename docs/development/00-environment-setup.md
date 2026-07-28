# Development Environment Setup

## Támogatott alapverziók

A repository jelenlegi CI-je alapján:

- Flutter: `3.44.2` stable;
- Dart SDK: a `pubspec.yaml` szerint `^3.12.2`;
- Java/JDK: 17;
- Python: 3.11 ajánlott az ML workflow-khoz;
- Git: aktuális stabil;
- Android SDK és platform tools;
- opcionális: `ffmpeg`, Node.js a repository tool scriptekhez.

A fejlesztői gép és CI Flutter-verziója legyen összehangolva. Verzióváltás külön PR és teljes gate.

## Kötelező komponensek

1. Flutter SDK.
2. Android Studio vagy command-line Android SDK.
3. JDK 17.
4. Python virtual environment támogatás.
5. GitHub CLI opcionális PR/CI munkához.
6. Valódi Android készülék mikrofon-, kamera- és teljesítményteszthez.

## Első ellenőrzés

```bash
flutter --version
dart --version
java -version
python3 --version
git --version
flutter doctor -v
```

## Környezeti elv

- Lokális secret `.env` vagy gitignored define file.
- Production secret csak CI secret store.
- Dataset és nagy modell nem kerül a gitbe, kivéve dokumentált shipping assetet.
- A standard fejlesztési loop nem igényel backendet és nem indít hálózatot.
