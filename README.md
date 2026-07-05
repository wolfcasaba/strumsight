# Music Theory

Standalone Flutter mobile app. Infrastructure scaffolded from the recipewiser-mobile stack
(Riverpod 3, go_router, supabase_flutter, i18n, dev-agents, learning systems) but a fully
separate project. See `CLAUDE.md` for architecture and conventions.

## Run

```bash
flutter pub get
flutter run                 # mock mode (no backend) by default
```

Backend keys (once a backend is chosen) are passed at build time and never committed:

```bash
flutter run --dart-define=SUPABASE_URL=... --dart-define=SUPABASE_ANON_KEY=...
```
