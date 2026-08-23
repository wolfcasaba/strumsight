# Review-jelentés — E09-R19 (Média feldolgozás, privacy és moderation state)

- **Reviewer:** Claude Sonnet 5 (orchesztrátor + delegált review-agent), READ-ONLY
- **Branch:** `minimax/e09-r19-media-processing-privacy-and-moderation-state`
- **Review HEAD:** `52cbeb33` (implementer saját commitja `d278c31b`, alap `6d1216bf`)
- **ADR:** [0412](../adr/0412-media-processing-privacy-and-moderation-state.md) · **Risk:** high
- **Verdikt:** **APPROVED** — 0 BLOCKER, 0 MAJOR

## 1. Jelzés + handoff

A `.codex-round-status` a megosztott fán egy KÉSŐBBI, más köri állapotot mutat
(mérve — nem ehhez a körhöz tartozik). A brief §10 Implementation handoff
(a BRANCH-en, nem `main`-en) fájlonkénti összegzővel, §6 evidencia-táblával, a
§6.1 valódi-sértés próba narratívájával és teljes parancskimenettel van
kitöltve — nem csonkolt/bemásolt állítás.

## 2. Gate-újrafuttatás (izolált klón, saját kézzel)

Izolált `/tmp` klónban (közvetlenül GitHub-ról, a helyi megosztott fa
elavult lokális branch-refjét elkerülve):

```
tools/round-gate.sh test/features/community/presentation/community_media_player_test.dart
```
```
format                                                     zöld
analyze                                                    zöld
test test/features/community/presentation/community_media_player_test.dart zöld
architecture                                               zöld
secrets                                                    zöld
l10n                                                       zöld
backend ruff format                                        zöld
backend ruff check                                         zöld
backend pytest                                             zöld
MINDEN GATE ZÖLD.
```
(Flutter: 8/8 teszt zöld — A2×4 parametrized pending state, A3 rejected,
deleted, ready + `onTapPlay`.)

```
cd backend && python -m pytest tests/community/test_media_processing.py -q
```
```
30 passed, 24 warnings in 7.06s
```

## 3. Scope-audit

`tools/scope-audit.py --repo <klón> --brief docs/rounds/e09-r19-...md --base 6d1216bf`
a HEAD-en (`52cbeb33`) 13 „VIOLATION"-t jelez — mindegyik a diszjunkt,
párhuzamos E13-R07 kör merge-elt fájlja (HANDOFF.md, LESSONS.md, RTM,
pipeline-queue.tsv, handoff-archive.md, a saját E13-R07 brief/ADR/ikon-fájlok).
Elkülönítve mérve:

- `git diff --stat 6d1216bf..d278c31b` (az implementer SAJÁT commitja) —
  pontosan 9 fájl, mind az `allowed_paths`-on (8 kód/teszt fájl + a brief §10
  handoff-szerkesztése). Nulla extra fájl.
- `git diff --stat d278c31b..52cbeb33` (a merge) — pontosan a 15 E13-R07 fájl,
  **nulla átfedés** bármely E09-R19 fájllal.
- A merge diffje a teljes tilos-zóna glob-lista (`media_upload_service.py`,
  `object_store.py`, `access_policy.py`, `requirements.txt`, `config.py`,
  `lib/features/community/domain/**`, `docs/adr/**`, `tools/**`, `.github/**`)
  ellen — kizárólag a `docs/adr/0411-...` (E13-R07 SAJÁT ADR-je) érintett.

**Konklúzió: a scope-audit nyers verdiktje ehhez a körhöz hamis pozitív**,
mert a mérés a merge-commitot nézte, ami — szándékosan és a §4.1 protokoll
szerint — egy másik, diszjunkt párhuzamos kört is hordoz. Az implementer
saját diffje tiszta.

## 4. `models/media.py` additivitás

`git diff 6d1216bf..d278c31b -- backend/app/community/models/media.py` — a
teljes diffben **nulla `-` sor** (kizárólag beszúrás: docstring-bővítés,
`Float` import, hét `PROCESSING_STATE_*` konstans + allowlist +
`is_allowed_processing_state`, öt új nullable audit oszlop, egy új composite
index, `__all__` bővítés). Az `upload_state` oszlop, allowlistje,
`ix_community_media_profile_state` indexe és a tranzíciós kód **byte-szinten
érintetlen**. Megerősítve: valóban additív (ADR 0412 §D2, brief §0.0/§4).

## 5. Acceptance criteria — bizonyítékkal

| # | Verdikt | Bizonyíték |
|---|---|---|
| A1 | PASS (MINOR gap, ld. §7) | `strip_exif_from_jpeg` a fixture egy-APP1-szegmenses JPEG-jét stripeli; `validate_client_metadata` MIME/codec/duration/resolution/frame-rate küszöböt kényszerít (6 teszt, mind zöld). |
| A2 | PASS | 4 parametrized pending state (`uploaded`/`scanning`/`transcoding`/`review`) — egyik sem renderel `Play`-t, mind `CircularProgressIndicator`. Widget `build()` switch-e nem konstruál play-affordance-t `ready`-n kívül. |
| A3 | PASS | Backend: `test_a3_rejected_media_cannot_issue_token` (`MediaNotPlayable`), `test_a3_is_playable_helper_only_ready`. Flutter: rejected-card teszt. |
| A4 | PASS | `relationship_context_from_block_flag` a MEGLÉVŐ `policies/access_policy.py`-ból (read-only import, nincs duplikált blocked-user logika). Verify élőben újrafuttatja a policy-t. |
| A5 | PASS | `test_a5_expired_token_raises_expired`, `test_a5_forged_token_raises_invalid` (bitfordított aláírás), `test_a5_valid_token_round_trip`. `hmac.compare_digest` (konstans idejű) mindkét oldalon. |
| A6 | PASS | `test_a6_audit_columns_written_by_triage`, `test_a6_audit_columns_written_by_review_gate`. |
| A7 | PASS — függetlenül újra-mérve | ld. §6. |

## 6. A7 valódi-sértés próba — függetlenül lefuttatva

Az implementer saját `test_a7_real_violation_probe`-ja mellett a reviewer
SAJÁT KEZŰLEG injektálta a hibát: `triage()`-be beszúrva egy közvetlen
`rejected`-átmenetet magas-confidence reject esetén, a `resolve_review`
megkerülésével. `pytest tests/community/test_media_processing.py` →
**1 failed, 29 passed** (`test_a7_real_violation_probe` PIROS,
`AssertionError: assert 'rejected' == 'review'`). Visszaállítás után
(`git status --short` tiszta) → **30 passed**. **Az A7 invariáns valóban
kényszerített, nem csak narrált.**

## 7. Kiegészítő leletek (a brief checklistjén túl)

Egy dedikált `security-reviewer` sub-agent (`risk=high` miatt kötelező, ld.
`docs/reviews/e09-r19-security.md`) leletei közül egyet a reviewer saját
próbával is megerősített:

**MINOR — az EXIF-strip nem néz tovább az EOI marker utáni bájtokra**
(`backend/app/community/tasks/media_processing.py:253-259`,
`strip_exif_from_jpeg`). Repro: egy szintetikus JPEG, ahol egy APP1/EXIF
szegmens az EOI UTÁN következik — a walker EOI-nál megáll és a maradékot
verbatim hozzáfűzi, tehát egy ilyen trailer-bájtokat hordozó JPEG GPS-adata
átcsúszik. Ez egy NEM dokumentált rés a JPEG-hatókörön BELÜL (a HEIC/RAW
hiány már névvel nevezett, brief §9 / ADR 0412 §D8). **Nem merge-blokkoló**:
a modul teljesen bekötetlen ebben a körben (nulla nem-teszt hívó), tehát ma
nulla production-expozíció; a jövőbeli wiring-kör előfeltétele legyen a
javítás vagy a limit explicit dokumentálása.

**NOTE — `_PROCESSING_TRANSITIONS` megengedné `(uploaded/scanning/transcoding)
→ rejected`-et** strukturálisan, jelenleg nulla hívóval — az A7 garancia ma
azon áll, hogy „senki nem hívja ezt az élt `resolve_review`-n kívül", nem
azon, hogy a tranzíciós tábla strukturálisan tiltja. Egy jövőbeli auto-reject
gyorsút átcsúszhatna ezen anélkül, hogy a `resolve_review`-hoz nyúlna —
szigorítandó, amikor az a kör landol (ADR 0412 §D5 Következmények már
kötelezi az elvet öröklő jövőbeli kört).

**NOTE — két docstring túlállít, funkcionális rés nélkül:** a playback token
docstringje azt állítja, az audience-claim „inside the HMAC" van kötve —
valójában csak `media_public_id|expires_at` van aláírva, az audience élőben,
helyesen újra kiértékelődik verify-kor. A service modul-docstringje szerint
egy nem-követő soha nem kap tokent FOLLOWERS audience-re — a `_resolve_audience`
ma hardcode PUBLIC-ot ad (a függvény SAJÁT docstringje ezt helyesen, Kör 19
hatókör-limitként dokumentálja) — a blocked-viewer tiltás valós, csak a
FOLLOWERS-specifikus állítás aspirációs.

## 8. Architektúra / termékhatárok (AGENTS.md §6)

- `community_media_player.dart` kizárólag `package:flutter/material.dart`-ot
  importál — nincs domain-import, nincs cross-feature import.
- Mindhárom új backend modul kizárólag `..models.media`,
  `..policies.access_policy` (read-only, engedélyezett) és saját csomagon
  belüli modulokat importál — a tiltott `media_upload_service.py`/
  `object_store.py` sehol nincs importálva.
- `architecture` gate-lépés: zöld, 12 allowlistelt eltérés (meglévő
  baseline, ezt a kör nem érintette).
- Migráció (`e09_r19_0013`): helyes `down_revision`, additív
  `op.add_column`/`op.create_index`, szimmetrikus `downgrade()`.

## 9. Verdikt

**APPROVED.** 0 BLOCKER, 0 MAJOR. Minden gate függetlenül újra-futtatva
zöld, a scope tiszta (a diszjunkt E13-R07 merge elkülönítve), a
`models/media.py` byte-szinten additív, mind a hét acceptance-cella
közvetlen méréssel bizonyított, az A7 human-review-gate invariáns valódi
kódmutáció-próbával függetlenül megerősítve. A két MINOR/NOTE-osztályú
lelet a jövőbeli wiring-kör explicit előfeltételeként viendő tovább, nem
blokkolja ezt a merge-et.
