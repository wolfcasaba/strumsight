# ADR 0063 — Generált ML asset manifest és önálló backend CI

- **Státusz:** elfogadva (2026-07-30, E01-R15)
- **Kontextus:** SDD Chapter 2, Kör 15; kör-brief
  `docs/rounds/e01-r15-backend-and-ml-ci.md`
- **Kapcsolódó:** [ADR 0052](0052-ci-apk-automerge-session-per-round.md)
  (a `build-apk.yml` mint kör-gate), [ADR 0053](0053-ci-full-test-suite.md)
  (a teljes suite CI-ben fut), [ADR 0060](0060-alembic-schema-source-and-injected-engine-lifecycle.md)
  (Alembic mint egyetlen prod schema-forrás — a backend CI migráció-gate-je
  erre épül), [ADR 0062](0062-ci-gate-chain-and-fail-closed-release-signing.md)
  (a Flutter gate-sor, amelybe a manifest-teszt a `flutter test`-en át beáll)

## Kontextus

A kör előtt a backend 64 pytestje **csak lokálisan** futott — merge előtt semmi
nem kényszerítette ki a zöldjüket. A négy shippelt ML-bináris
(`assets/ml/{chord_crnn,strum_crnn,strum_crnn_live,strum_crnn_live_3c}.bin`)
mögött pedig nem volt manifest: egy némán kicserélt vagy sérült `.bin`-t
semmi nem fogott meg merge előtt (az R14-es `check_assets.dart` a létezést és a
nem-ürességet nézi, tartalmat nem — és üres deklarációs halmazon némán zöld
volt, R14-review MINOR-1).

## Döntések

1. **A manifest generált, nem kézzel írt.** `ml/make_manifest.py` állítja elő
   az `assets/ml/model_manifest.json`-t: a SHA-256, a formátum/verzió és a
   shape-ek **mért** értékek (a script a bináris headert is parseolja, és a
   classlista hosszát a mért kimeneti shape-hez validálja). Kézi
   checksum-szerkesztés review-ban elutasítandó; modellcserénél a script
   újrafuttatása kötelező. A script idempotens: a `created_at` csak
   checksum-változásnál frissül.
2. **A checksum-gate a `flutter test`-en át érvényesül**
   (`test/tooling/ml_asset_manifest_test.dart`), NEM külön workflow-lépésként —
   egy gate-hely, egy igazság. Mivel a `flutter test` a `build-apk.yml` ÉS a
   `release-apk.yml` közös gate-sora, a manifest automatikusan mindkét
   APK-utat védi.
3. **A manifest a névvel nevezett alsó korlát.** A guard a manifest négy
   bejegyzéséből indul és **kétirányú** a pubspec felé: manifest-bejegyzés
   pubspec-deklaráció nélkül ÉS pubspec-deklarált ML-bin manifest nélkül is
   piros. Ezzel a pubspec `assets:` blokk törlése/elgépelése sem maradhat néma
   (az R14-review MINOR-1 lezárása) — a `tool/ci/check_assets.dart` érintése
   nélkül.
4. **Provenance: mért, nem placeholder.** A brief `pre-manifest` jelölést
   engedett a rekonstruálhatatlan esetre; az implementáció ehelyett mind a négy
   bináris valódi shipping-revízióját rekonstruálta a git-történetből
   (`origin: repository-history` + commit SHA — round163/168/175/204, mind
   függetlenül ellenőrizve). A guard a négy ismert azonosítót rögzíti is:
   modellcserénél a manifest ÉS a teszt tudatos frissítése kell — ez a
   modellcsere-szabály (SDD 15.6) gépi fedezete. Kitalált run-azonosító tilos;
   a `pre-manifest` jelölés csak jövőbeli, tényleg rekonstruálhatatlan
   legacy-esetre maradt nyitva.
5. **Önálló backend CI** (`.github/workflows/backend-ci.yml`): Ruff lint →
   Ruff format-check → pytest → `alembic upgrade head` izolált temp-SQLite
   URL-lel, Python 3.12-n (a box venvjével egyezően; a training workflow-k
   3.11-e nem változott). Trigger: push a `backend/**`-ra + dispatch — a
   backend-körök így a Flutter gate-sortól függetlenül, ~1 perc alatt kapnak
   kaput.
6. **Requirements-szétválasztás:** `requirements.txt` csak runtime;
   `requirements-dev.txt` a gate-eszközök (pytest, httpx, ruff). A prod-only
   telepítés önmagában bootolja a backendet (smoke-bizonyíték a kör §10-ében).
   A Ruff scope-ja `app` + `tests` — az `alembic/` (generált) és a `.venv`
   explicit exclude.

## Következmények

- Backend-változás merge-bar-ja mostantól: zöld `backend-ci.yml` (a kör-branchen
  bizonyítva: run 30517873919) — a 64 teszt nem tud többé némán elromlani.
- `.bin` csere manifest-frissítés nélkül → piros `flutter test` mindkét
  APK-workflow-ban; a csere tudatos, kétfájlos (manifest + guard) művelet.
- A Dart-teszt SHA-256-ja kézzel implementált (a `pubspec.yaml` a kör alatt
  zárt volt, a `crypto` csomag nem volt felvehető) — NIST-vektorokkal és a
  Python-oldali checksumokkal kereszt-validált; ha a `crypto` egyszer közvetlen
  dependency lesz, a csere triviális follow-up.
- Az R14-review MINOR-2 (gate-sor duplikáció a két APK-workflow közt) és
  MINOR-3 (Flutter CI-idő) változatlanul nyitott → E01-R16 pre-flight bemenet.
