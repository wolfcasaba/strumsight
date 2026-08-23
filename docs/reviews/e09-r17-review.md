# E09-R17 — Review

Brief: docs/rounds/e09-r17-bookmarks-and-controlled-import.md
ADR: docs/adr/0408-bookmark-and-controlled-import.md
Diff: `git diff 831f77ef..0221996f` (branch `minimax/e09-r17-bookmarks-and-controlled-import`)
Reviewer: Claude Sonnet 5 · Dátum: 2026-08-23
Verdikt: **APPROVED**

## Összegzés

BLOCKER: 0 · MAJOR: 0 · MINOR: 2 · NOTE: 1

## Gate-bizonyíték (saját kézzel, izolált klónban)

```
git clone --branch minimax/e09-r17-bookmarks-and-controlled-import \
  https://github.com/wolfcasaba/strumsight.git /tmp/review-e09-r17
tools/round-gate.sh test/features/community/application/import_share_artifact_test.dart
```

```
format                                                     zöld
analyze                                                    zöld
test import_share_artifact_test.dart (22/22)               zöld
architecture (12 allowlisted deviation — mind pre-existing) zöld
secrets                                                     zöld
l10n                                                        zöld
backend ruff format                                        zöld
backend ruff check                                         zöld
backend pytest (teljes suite, benne 13 bookmark-teszt)      zöld
```

```
python3 tools/scope-audit.py --repo /tmp/review-e09-r17 \
  --brief docs/rounds/e09-r17-bookmarks-and-controlled-import.md --base 831f77ef
→ Legacy scope audit OK (831f77ef9187..0221996f665a, 7 changed path(s), 0 generated/ignored)
```

A 7 megváltozott útvonal **pontosan** megegyezik a brief `allowed_paths`
listájával — nincs listán kívüli fájl.

## Acceptance criteria

| # | Kritérium | Bizonyíték | Verdikt |
|---|---|---|---|
| A1 | Bookmark set/remove idempotens | `test_set_bookmark_creates_one_row`, `test_set_bookmark_idempotent_no_second_row`, `test_remove_bookmark_idempotent_noop_on_second` + `test_a1_idempotency_real_violation_probe` (UNIQUE constraint + service-guard EGYÜTT eltávolítva → két sor landol, mérve pirosan) | ✅ |
| A2 | Bookmark-count nem publikus | `test_post_out_does_not_carry_bookmark_count` — a poszt-response-t közvetlenül vizsgálja, nem csak strukturális következtetés | ✅ |
| A3 | Törölt poszt bookmarkja biztonságos tombstone | `test_list_bookmarks_emits_tombstone_for_soft_deleted_post`; a modell `ON DELETE CASCADE`-je csak hard-delete-re vonatkozik, a soft-delete (`deleted_at`) a sort megőrzi | ✅ |
| A4 | Ismeretlen/érvénytelen schema-verzió elutasítva | `A4 — unknown schema version is rejected`, `A4 — schema version 0 is rejected` + §6.1 valódi-sértés próba (a guard kikapcsolva → A4 pirosra vált, mérve) | ✅ |
| A5 | Import új lokális példányt hoz létre, forrás változatlan | `A5 — import builds a new Song with a fresh id`, `A5 — the source artifact identity is preserved through the call` + §6.1 próba | ✅ |
| A6 | Lokális névütközés kezelt | `A6 — collision returns NameCollision, not a silent overwrite` + §6.1 próba | ✅ |
| A7 | Deprecated artifactnál read-only fallback | `A7 — isDeprecated=true returns Deprecated, not Success`, `A7 — deprecated is checked AFTER schema version` | ✅ |

Mind a hét cella tesztelt, és a §6.1 kötelező valódi-sértés próbák (A1, A4, A5,
A6) ténylegesen PIROSRA fordultak a védelem ideiglenes eltávolításakor —
ellenőrizve a próbák forráskódjában, nem csak a leírásukban.

## Architektúra és termékhatárok

- **D1 (ADR 0408) betartva**: `import_share_artifact.dart` importjai —
  `flutter/foundation.dart`, `core/music/strum.dart`,
  `community/domain/entities/share_artifact.dart`,
  `songs/public.dart`. **Nincs** `songsRepositoryProvider`/`songsProvider`/
  `SongsController` import vagy hívás (`grep` nulla találat) — a use-case
  valóban PURE, hívó-táplált (`idGenerator`, `localSongExists` mindkettő
  paraméter, alapértelmezett tiszta függvénnyel).
- **A router+service egy fájlban** (`routers/bookmarks.py`) — dokumentált,
  indokolt döntés (a brief `allowed_paths`-a nem tartalmaz külön
  `bookmark_service.py`-t); a teszt a `test_post_service.py` bevett
  "saját FastAPI+TestClient, csak a saját router mountolva" mintáját követi,
  `main.py`/`profile.py` érintése nélkül.
- **D4 cursor** — önálló base64 `(created_at, id)` keyset, tampered cursor
  `None`-ra decode-ol és a lista elölről indul (`test_list_bookmarks_tampered_
  cursor_starts_from_top`) — nem HMAC, indokolt (D4).
- Migráció `down_revision = "e09_r16_0010"` — helyesen láncolódik a jelenlegi
  fejre, mindkét FK `ondelete="CASCADE"`, `UNIQUE(post_id, profile_id)`.
- `docs/sdd/10-epic-09-community-platform.md` §7.3 tiltása ("más Flutter
  feature belső data rétegének importálása") nem sérül.

## MINOR leletek

1. **`backend/app/community/routers/bookmarks.py:547` — `_resolve_internal_
   profile_id` holt kód.** A függvényt semmi nem hívja (sem a router, sem a
   teszt), és nincs az `__all__`-ban sem — a ténylegesen használt párja
   `_resolve_viewer_public_id`. Nem hibás, csak felesleges; törlésre javasolt
   egy következő kis javításban vagy a Kör 18 érintésekor (nem éri meg önálló
   diffet nyitni csak ezért).
2. **A brief §3 "explicit Import action ... jelenjen meg" scope-tétele a
   `bookmarks_screen.dart`-ban vizuálisan NEM jelenik meg** — a képernyő a
   tombstone-állapotot és a Remove-akciót rendereli, de nincs UI-elem, ami az
   `importShareArtifact()`-ot hívná. **Ez nem acceptance-hiba** (egyik A1-A7
   cella sem méri ezt a UI-vezetéket, és a brief §8 implementációs sorrendje —
   ami "a terv" — a `bookmarks_screen.dart` lépésénél KIZÁRÓLAG a
   tombstone-állapotot írja elő, az Import-gombot nem). Emellett a jelenlegi
   `BookmarkOut` wire-válasz nem hordozza az artifact típusát/mezőit — a
   gomb tényleges bekötése a `list_bookmarks` response bővítését is
   igényelné. Ez a §3/§8 belső ellentmondása volt a brief-ben már a
   pre-flight előtt is; a pre-flight (§0.0 D1) csak a `songsProvider`
   perzisztálási rést azonosította, ezt a UI-vezeték rést nem. Javaslat:
   egy külön, kicsi follow-up kör (a Kör 18 l10n-körrel összevonható), ami
   (a) a `BookmarkOut`-ot kiegészíti az artifact `type`/`schema_version`/
   mezőkkel a jogosult (plan-template/original-progression) sorokra, és
   (b) a képernyőn egy "Import" akciót köt az `importShareArtifact()`-hoz,
   eredmény-dialógussal (siker/collision/deprecated/unsupported) — a
   TÉNYLEGES `songsProvider`-mentés továbbra is a D1 szerint egy KÉSŐBBI
   körben (ADR 0408 "Következmények" szakasza már jelzi ezt).

## NOTE

- A `_ = Any; # silence "Any imported but unused"...` sor
  (`bookmarks.py:746-748`) egy kicsit szokatlan minta a `ruff`/`analyze`
  csendesítésére — működik (mindkét gate zöld), de egy jövőbeli olvasó
  számára nem azonnal magától értetődő. Nem blokkoló.

## Döntés

A hét acceptance-cella mindegyike mérve, tesztelve és zöld; a scope-audit
tiszta; a gate teljes egészében zöld egy független, izolált klónban
újrafuttatva. A két MINOR lelet egyike holt kód (törölhető, nem viselkedési
kockázat), másika egy már a brief-ben (nem ebben a körben) meglévő
scope-tábla/§8-terv ellentmondás, amit egy dokumentált follow-up kör zár le —
egyik sem éri el a BLOCKER/MAJOR küszöböt. **Merge engedélyezve.**
