# E09-R16 review — Kommentek, reply és mention

- **Kör:** E09-R16 — Kommentek, reply és mention
- **Branch:** `minimax/e09-r16-comments-reply-and-mention`, PR [#425](https://github.com/wolfcasaba/strumsight/pull/425)
- **Implementer:** MiniMax M3
- **Reviewer:** Claude Sonnet 5 (`--effort high`)
- **Mért HEAD az 1. review-nál:** `60d8feff`
- **Verdict (1. kör):** CHANGES REQUESTED — 1 MAJOR, 2 MINOR
- **Mért HEAD a javító kör után:** `ff6cabb9` (4 javító commit:
  `e777f033`/`8442c663`/`f2d7766f`/`f49351fc` + 2 orchestrátor-oldali
  scope-bővítő commit `8406ed1f`/`ff6cabb9`, ld. §8)
- **Verdict (2. kör):** **APPROVED**

## 8. Javító kör utáni re-verifikáció (2. review-menet)

Friss, izolált `/tmp` klón (`/tmp/review-e09-r16-fix1`), a HEAD `ff6cabb9`-on:

```bash
git clone --branch minimax/e09-r16-comments-reply-and-mention \
  https://github.com/wolfcasaba/strumsight.git /tmp/review-e09-r16-fix1
tools/round-gate.sh test/features/community/presentation/comments_screen_test.dart test/ui/ui_inventory_test.dart
```

→ **10/10 lépés ZÖLD** (a `test/ui/ui_inventory_test.dart` most explicit
gate-argumentumként fut, a §4.2-ben mért piros MOST zöld: `hasLength(72)`).
Külön, nem láncolt: `cd backend && python3 -m pytest
tests/community/test_comment_service.py -q` → 21/21 zöld, **és a
`SyntaxWarning` a warnings summary-ból eltűnt** (a docstring `r"""`-re
váltása megerősítve).

```bash
python3 tools/scope-audit.py --repo /tmp/review-e09-r16-fix1 \
  --brief docs/rounds/e09-r16-comments-reply-and-mention.md \
  --base e1a2f351ce8a3fc38c9055cba48786561994670d
```

→ `Legacy scope audit OK (e1a2f351ce8a..ff6cabb93edc, 15 changed path(s), 1
generated/ignored)` — a §0.0.1/§0.0.2 orchestrátor-oldali scope-bővítés (5
fájl: 2 feature-ARB, 2 generált aggregátum-ARB, 1 teszt-számláló) lefedi a
teljes diffet.

**Leletenkénti zárás:**

| Lelet | Zárás | Bizonyíték |
|---|---|---|
| MAJOR — 0 `AppLocalizations` | ZÁRVA | `comments_screen.dart` mind az 5 string `AppLocalizations.of(context).communityComments*`-re cserélve, valódi magyar fordítással (`community_hu.arb`: „Hozzászólások", „Még nincsenek hozzászólások.", „Továbbiak betöltése", „Írj egy hozzászólást…", „Küldés") |
| MINOR — SyntaxWarning | ZÁRVA | `comment_policy.py` docstring `r"""`-re váltva, a warnings summary-ból eltűnt |
| MINOR — `edit_comment` duplikáció | ZÁRVA | `edit_comment` most vékony wrapper (`return edit_comment_with_resource_version(..., resource_version=None, ...)`), a duplikált törzs megszűnt |
| Mellékhatás — screen-count drift | ZÁRVA | `test/ui/ui_inventory_test.dart` `hasLength(72)`, saját kézzel is zöldre mérve |
| NOTE — üres §10 handoff | nem blokkolt, továbbra is üres | — |

Nincs új MAJOR/BLOCKER. **A kör mehet CI-dispatchra és merge-re.**

## 1. Jelzés + handoff

`.codex-round-status`: `status=done`, `gate_shape=ok`, `scope_audit=ok`,
`scope_audit_changed=8`. A brief `§10 Implementation handoff` szakasza
**üresen maradt** — az implementer nem töltötte ki, holott a preambulum
kifejezetten kéri. Ez önmagában nem hordoz hamis attribúciót (üres, nem
téves), ezért NOTE, nem MAJOR/MINOR — lásd a leletek táblázatában.

## 2. Gate-újrafuttatás — SAJÁT kézzel, izolált `/tmp` klónban

```bash
git clone --branch minimax/e09-r16-comments-reply-and-mention \
  https://github.com/wolfcasaba/strumsight.git /tmp/review-e09-r16
cd /tmp/review-e09-r16 && bash tools/prepare-flutter-generated.sh
tools/round-gate.sh test/features/community/presentation/comments_screen_test.dart
```

Mind a 9 lépés **ZÖLD** (format, analyze, test, architecture, secrets, l10n,
backend ruff format, backend ruff check, backend pytest — TELJES suite, 507
teszt, a 12 community-fájl mindegyike belefoglalva). Külön, nem láncolt
parancs:

```bash
cd backend && python3 -m pytest tests/community/test_comment_service.py -q
```

→ 21/21 zöld (a §6.1 mérce-mátrix mind a 8 A-cellája + a mélység-hármas +
mindkét KÖTELEZŐ valódi-sértés próba, ld. lent).

**A gate ÖNMAGÁBAN NEM elég** — a brief `gate_tests` szándékosan szűk
(`test/features/community/presentation/comments_screen_test.dart`), a TELJES
`flutter test` suite csak CI-ban fut (ADR 0053). Saját kézzel lefuttattam a
teljes Flutter suite-ot is (`flutter test`, lásd 4.2. pont) — ez fogta meg a
MAJOR leletet.

## 3. Scope-audit

```bash
python3 tools/scope-audit.py --repo /tmp/review-e09-r16 \
  --brief docs/rounds/e09-r16-comments-reply-and-mention.md \
  --base e1a2f351ce8a3fc38c9055cba48786561994670d
```

→ `Legacy scope audit OK (e1a2f351ce8a..60d8feff5db7, 8 changed path(s), 0
generated/ignored)`. A 8 megváltozott fájl pontosan a brief `allowed_paths`
listája, egy-az-egyben. **Nincs H3.**

## 4. Acceptance criteria tételesen

| # | Kritérium | Bizonyíték | Verdikt |
|---|---|---|---|
| A1 | Nincs végtelen threadmélység | `test_a1_depth_triple_*` (3 teszt: alatt/rajta/fölött) + `test_a1_real_violation_probe_depth_guard_bypassed` | ✅ mérve |
| A2 | Mention nem kerülheti meg a block/privacy szabályt | `test_a2_mention_to_blocked_profile_is_stripped`, `test_a2_mention_to_nonexistent_profile_is_stripped`, `test_a2_mention_privacy_real_violation_probe` | ✅ mérve |
| A3 | Private posztra írt komment jogosultsághoz kötött | `test_a3_audience_gate_private_post_rejects_comment` | ✅ mérve |
| A4 | Edit conflict (elavult resource version) elutasítva | `test_a4_stale_resource_version_rejected` + `test_a4_fresh_resource_version_accepted` | ✅ mérve — ld. 4.3 megjegyzés |
| A5 | Delete jogosultság: szerző, post-owner, moderator — más nem | `test_a5_delete_authorization_matrix`, `test_a5_post_owner_deletes_any_comment`, `test_a5_moderator_deletes_any_comment` | ✅ mérve |
| A6 | Temp ID atomikusan cserélődik, nincs duplikált elem | `comments_screen_test.dart` 3 teszt (siker, rollback, submit-lock) | ✅ mérve, saját kézzel is olvasva a controller kódját (4.4) |
| A7 | Komment-pagination stabil, nincs duplikált oldal | `test_a7_pagination_round_trip_no_duplicates`, `test_a7_pagination_tampered_cursor_falls_back` | ✅ mérve |
| A8 | XSS stringek elutasítva | `test_a8_html_tag_rejected`, `test_a8_mention_cap_rejected`, `test_a8_body_length_cap_rejected` | ✅ mérve |

### 4.1 §6.1 KÖTELEZŐ valódi-sértés próba

A brief a mélység-ellenőrzés kivételét írja elő. Az implementer EZT ÉS a
mention-privacy ágat is önálló valódi-sértés próbával fedte:

- **A1**: `test_a1_real_violation_probe_depth_guard_bypassed` — egy
  `_create_without_depth_guard` segédfüggvény a service `create_comment`
  logikáját tükrözi a mélység-guard NÉLKÜL, és megméri, hogy `depth=2` sor
  jön létre — ez a guard TÉNYLEGES hatását bizonyítja, nem csak azt, hogy a
  publikus API elutasít egy konkrét bemenetet.
- **A2**: `test_a2_mention_privacy_real_violation_probe` — a
  `_mention_visible` függvényt monkeypatch-eli mindig-`True`-ra, méri, hogy a
  blokkolt mention EKKOR átmegy (piros lenne), majd visszaállítja.

Mindkettő önálló futtatással ellenőrizve (`pytest -q
tests/community/test_comment_service.py -k "real_violation"`) — 2/2 zöld.

### 4.2 Saját, a brief `gate_tests`-en TÚLI mérés — a TELJES Flutter suite

A brief `gate_tests` szándékosan a `comments_screen_test.dart`-ra szűkít
(service-réteg-only kör, ADR 0407 §D7). Mivel a kör egy ÚJ `*_screen.dart`
fájlt ad hozzá, saját kézzel lefuttattam a `test/ui/ui_inventory_test.dart`-ot
is (a mechanikus képernyő-számláló, amit az E09-R05...R13 és E09-R14 körök
ismételten elfelejtettek bumpolni, `docs/LESSONS.md`/HANDOFF precedens):

```bash
cd /tmp/review-e09-r16 && flutter test test/ui/ui_inventory_test.dart
```

→ **PIROS**: `Expected: an object with length of <71> / Actual: has length of
<72>` — a `comments_screen.dart` a `*_screen.dart` mechanikus mintával
számít bele, a hardcode-olt `hasLength(71)` NEM lett bumpolva. Ez a fájl
NINCS a brief `gate_tests`-én, de a TELJES suite (CI, `full-gate.yml`,
ADR 0053) futtatja — merge előtt PIROSRA fordítaná a kaput. Ugyanaz a
drift-osztály, mint E09-R14 (HANDOFF: „ugyanaz a drift-osztály, mint
E09-R05...R13-ban ismételten"). **MAJOR — ld. leletek.**

### 4.3 A4 megjegyzés — a resource_version mérce KIZÁRÓLAG a backend teszt felelőssége

Az ADR 0407 §D7 dokumentálja: a `post_repository.dart::updateComment` NEM
kap `resourceVersion` paramétert (domain tilos zóna), ezért az A4 Dart-oldali
UI-mércéje NINCS — ez SZÁNDÉKOS, nem hiány. Az implementer az
`edit_comment_with_resource_version` függvényt vezette be az A4 mérésére,
míg a sima `edit_comment` (resource_version nélkül) a jövőbeli, nem-versioned
hívási útvonalat modellezi. **Lásd a MINOR leletet (dead code) lent.**

### 4.4 A6 kódolvasás — atomikus temp-ID csere

`comment_controller.dart::submitDraft()` (307–401. sor): a temp sor a hívás
ELŐTT kerül be a state-be, a válasz megérkeztekor egyetlen `state =
AsyncData(...)` írással cserélődik — nincs két egymást követő write, ami
átmenetileg két sort mutatna. Hibaágon `_rollbackOptimistic(tempId)` törli a
temp sort. **Megfelel a §5.3 kontraktusnak.**

## 5. Leletek

### MAJOR — comments_screen.dart 0 `AppLocalizations` hívással ment ki

**Fájl:** `lib/features/community/presentation/screens/comments_screen.dart:65,129,191,256,272`

Öt hardcode-olt, felhasználó felé látszó string (`'Comments'`, `'No comments
yet.'`, `'Load more'`, `'Write a comment…'`, `'Send'`) egyetlen
`AppLocalizations` hívás nélkül. **Ugyanaz a hibaosztály, mint az E09-R08 F1
és az E09-R14 F1 — mindkettő MAJOR volt** (HANDOFF: „mindkét ÚJ UI-fájl 0
`AppLocalizations` hívással ment ki"). Az AGENTS.md/CLAUDE.md konvenció
kötelezővé teszi: minden felhasználó felé látszó string ARB → `AppLocalizations`
úton megy. A `comment_controller.dart` maga NEM hordoz UI-stringet (a
`state.lastError` egy `AppFailure`, a screen rendereli — a screen felelős a
lokalizációért).

**Javasolt irány:** az `lib/l10n/features/community_{en,hu}.arb` bővítése
(a Kör 14-es F1-fix precedense, orchestrátor-irányítottan bővített
`allowed_paths`), a fenti 5 string valódi magyar fordítással.

### MINOR — `comment_policy.py` docstring SyntaxWarning (nem raw string)

**Fájl:** `backend/app/community/policies/comment_policy.py:11`

A modul-docstring `"role\|moderator\|is_staff\|is_admin"`-t tartalmaz egy
SIMA (nem `r"""`) triple-quoted stringben — a `\|` nem ismert escape-
szekvencia, minden importnál `SyntaxWarning`-ot dob (mérve: a pytest saját
warnings summary-jában látszik, `test_comment_service.py` importja
kiváltja). Nem funkcionális hiba, de zajt hagy a CI logban és a `ruff check`
sem fogta meg (docstring-tartalom, nem kód). **Javasolt irány:** `\|` → `\\|`
vagy a docstring `r"""`-re váltása.

### MINOR — `edit_comment`/`edit_comment_with_resource_version` közel-duplikált, az egyik HÍVATLAN

**Fájl:** `backend/app/community/services/comment_service.py:642-725` (`edit_comment`)

A két függvény (`edit_comment`, `edit_comment_with_resource_version`) ~45
sornyi logikát duplikál szó szerint (profil-feloldás, komment-feloldás,
author-only guard, mention-stripping, body-validáció, `on_invalidate`
esemény). A `git grep -n "edit_comment("` szerint a sima `edit_comment`-et
**semmi nem hívja** — sem a `test_comment_service.py`, sem a Dart oldal
(ami a domain-kontraktuson ($post_repository.dart::updateComment$) keresztül
egyébként sem hívhatná közvetlenül a Python service-t). Egy jövőbeli
módosítás, ami csak az egyik függvényt frissíti, némán divergálna a
másiktól. **Javasolt irány:** `edit_comment` törlése az `__all__`-ból és a
modulból, VAGY egy vékony wrapperré alakítása
(`edit_comment_with_resource_version(resource_version=None, ...)` hívása) —
bármelyik a diffet csökkenti, nem növeli.

### NOTE — a brief §10 Implementation handoff szakasza üresen maradt

Az implementer nem töltötte ki a §10-et, holott a preambulum kéri. Nem
hordoz hamis állítást (üres ≠ téves), ezért nem blokkol, de a javító kör
promptjában érdemes megismételni a kérést.

## 6. Architektúra + termékhatárok

`tool/check_architecture.dart` (gate lépés 4) zöld, 12 allowlistelt eltérés
— egyik sem ebből a körből. A `comment_service.py` a `query_filters.py`-t
CSAK importálja (nem módosítja) — a tilos zóna sértetlen. A
`comments_screen.dart`/`comment_controller.dart` a `domain/**`-et csak
importálja, nem módosítja.

## 7. Javító kör

A MAJOR (l10n) és a két MINOR javítását, valamint a `test/ui/
ui_inventory_test.dart` mechanikus bumpolását (71→72, a saját mérésem, 4.2.
pont) EGY javító körben kéri az orchesztrátor — az `allowed_paths`
dokumentáltan bővül (lásd a javító-prompt), a Kör 14 F1/screen-count
precedensét követve.
