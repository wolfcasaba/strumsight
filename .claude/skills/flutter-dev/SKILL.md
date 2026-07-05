---
name: flutter-dev
description: RecipeWiser-mobile fejlesztési workflow Flutter/Dart-hoz — mikor melyik Dart MCP tool-t használd (analyze/fix/format/test/hot-reload), a Riverpod 3 + Supabase konvenciók, és a verify-gate. Használd MINDEN mobil (recipewiser-mobile) feladatnál: új feature, bugfix, refactor, vagy "fut-e / jó-e" ellenőrzés.
---

# RecipeWiser Mobile — Flutter dev workflow

A `dart` MCP server aktív (`.mcp.json`). Használd a beépített tool-jait shell-kihívás HELYETT — gyorsabb, és nem terheli túl a memóriát (az analysis-servert az MCP kezeli; a `flutter analyze && flutter test` chain ezen a gépen OOM/SIGTERM, lásd CLAUDE.md).

## Tool döntési fa (Dart MCP)

```
Statikus hiba / lint?      → analyze_files   (NE `flutter analyze`-t shell-elj)
Auto-javítható lint/fix?   → dart_fix
Formázás?                  → dart_format
Teszt futtatás?            → run_tests       (NE chain-eld analyze-zel)
Futó app frissítése?       → hot_reload / hot_restart
Csomag/dependency vizsg.?  → read_package_uris, rip_grep_packages, pub_dev_search
Runtime hiba a futó appban?→ get_runtime_errors, get_app_logs
Widget-fa vizsgálat?       → widget_inspector
```

Hibánál vagy ismeretlen csomagnál előbb **listázd az MCP resource-okat** (a szerver instrukciója szerint), utána dolgozz.

## Konvenciók (a CLAUDE.md a teljes forrás — itt a lényeg)

- **Riverpod 3, kézi providerek** (nincs codegen). `Notifier`+`NotifierProvider`, async-hoz `AsyncNotifier`. **`StateProvider` TILOS** (Riverpod 3-ból kivették).
- **Repository-provider minta**: valós Supabase repo ha `SupabaseConfig.isConfigured` && bejelentkezve, különben `Preview…Repository` (mock).
- **Backend írás előtt** verifikáld a tábla+oszlop nevet a prod baseline SQL ellen (`~/Recipewiser/supabase/migrations/00000000000000_remote_baseline.sql`) — a `catch(_){}` elnyeli a rossz nevet (néma no-op). Pl. `recipe_favorites` (nem `recipe_likes`), cookbooks `title` (nem `name`).
- **AI feature** = a web route hívása Dio-val + `Authorization: Bearer <accessToken>`.
- **Navigáció**: `Navigator.push(MaterialPageRoute)` (a `go_router` jelen, de nincs használva — ne vezess be `context.go()`-t).
- **Perf**: `const`, `ListView.builder`, `compute()` nagy JSON-ra, legkisebb `ref.watch(...select)` szelet.

## Verify-gate (mielőtt "kész")

1. `analyze_files` → 0 hiba (vagy `flutter analyze lib/` ÖNÁLLÓAN, ≥240s timeout).
2. `run_tests` → zöld (KÜLÖN hívásban, soha nem chain-elve — OOM).
3. UI-változásnál: real-data screenshot `--dart-define=SUPABASE_ANON_KEY=<NEXT_PUBLIC_SUPABASE_ANON_KEY a ~/Recipewiser/.env.local-ból>` (a mock build elrejti az adat-formájú hibákat).
4. Deliverable = **APK** (`flutter build apk`), nem PWA.

Nyelv: a felhasználóval **magyarul**, a kódban **angolul**.
