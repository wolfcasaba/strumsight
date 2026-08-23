# E09-R12 — Review

Brief: docs/rounds/e09-r12-post-composer-draft-and-outbox.md
Diff: `git diff 6e710a0d..785b44b7` (branch `minimax/e09-r12-post-composer-draft-and-outbox`)
Reviewer: Claude Sonnet 5 · Dátum: 2026-08-23
Verdikt: CHANGES REQUIRED

## Összegzés

BLOCKER: 0 · MAJOR: 1 · MINOR: 1 · NOTE: 1

## Acceptance criteria

| # | Kritérium | Teljesült | Bizonyíték |
|---|---|---|---|
| A1 | Preview a közzététel előtt, szerver-visszaigazolás előtt nincs "sikeres" | ✅ | `post_composer_controller.dart:274-297` — `success` csak `report.acknowledged.contains(draft.idempotencyKey)` után; `post_composer_test.dart::A1` |
| A2 | Offline retry nem duplikál | ✅ | `community_outbox.dart:346-397` a persistált kulcsot küldi minden drain-en; `community_outbox_test.dart::A2` (2 teszt) + §6.1 measure-matrix probe (a fentiek szerint mérve, saját kézzel újrafuttatva ZÖLD) |
| A3 | Dupla tap nem indít két mutációt | ✅ | `post_composer_controller.dart:257` `isSubmitting` early-return; `post_composer_test.dart::A3` |
| A4 | App kill/restart után draft + pending post helyreáll | ✅ | `community_draft_store.dart` (JsonObjectStore-alapú perzisztencia) + `community_outbox.dart:_ensureLoaded`; `post_composer_test.dart::persistence` + `community_outbox_test.dart::A4` (2 teszt, incl. per-record decode resilience) |
| A5 | Hiba esetén a szöveg megmarad | ✅ | `post_composer_controller.dart:298-325` a `catch` ágak nem törlik `body`-t, csak `status`/`lastError`-t írnak; `post_composer_test.dart::A5` (2 teszt: AppFailure + catch-all) |
| A6 | Logout policy dokumentálva és mérve | ✅ | §10.5 döntés (draft user-scope-ban marad); `post_composer_test.dart::A6` két különböző `userId`-vel igazolja az izolációt |
| A7 | Érzékeny mezők alapból KI | ✅ | `SharePreview()` default konstruktor minden flag `false`; `post_composer_test.dart::A7` (2 teszt: defaults + flag-stomper) |

Minden cella saját, dedikált teszttel fedett; a §6.1 measure-matrix mind az 5
sora külön asszerciót kapott (l. §10.2/§10.3 a brief-ben).

## Scope-audit

```
python3 tools/scope-audit.py --repo /tmp/review-e09-r12 \
  --brief docs/rounds/e09-r12-post-composer-draft-and-outbox.md --base 6e710a0d3729f9735143cbbeb09c2db968d34b8
→ Legacy scope audit OK (6e710a0d3729..785b44b7bef1, 7 changed path(s), 0 generated/ignored)
```

Engedélyezett fájlokon kívüli változás: **nincs.**

`gate_shape=VIOLATION` a `.codex-round-status`-ban **hamis pozitív** — a
naplóban egyetlen `round-gate.sh | head -80` mintázatú parancs van, de az egy
`cat tools/round-gate.sh | head -80` (a gate-script FORRÁSÁNAK olvasása
megértés céljából), amit az implementer_guard hook **elutasított**
(`permission_denials` a naplóban) — LE SE FUTOTT. A tényleges három
`tools/round-gate.sh <útvonalak> 2>&1` hívás egyike sem csonkolt/láncolt. A
saját, izolált `/tmp/review-e09-r12` klónban futtatott gate (lásd lent) ezt
függetlenül megerősíti.

## Megállapítások

### F1 — MAJOR — Fiktív "legacy" migráció + nem user-scope-olt fallback-kulcs a draft store-ban

- **Fájl:** `lib/features/community/data/local/community_draft_store.dart:45-51, 288-294`
- **Probléma:** a `CommunityDraftStore.open` a `JsonDocumentStore`-t
  `legacyKey: _legacyStorageKey` (`'ss.community.drafts.v1'`) értékkel
  konstruálja. Ez a kulcs **nincs user-id-vel particionálva** — MINDEN
  usernél ugyanaz a szó szerinti string. A docstring (14. sor) azt állítja,
  hogy "a Kör 12 rewrite mozog per-user particionálásra" egy korábbi,
  device-wide draft store-ból — ez **nem igaz**: mérve (grep a teljes
  `lib/`-en és a git-történeten), a `community_draft_store.dart` ez a kör
  hozza létre ELŐSZÖR, nincs korábbi Community draft store, tehát nincs mit
  migrálni. A `_legacyStorageKey` konstans emellett **nincs regisztrálva** a
  kanonikus `LegacyStorageKeys` osztályban (`lib/core/storage/storage_keys.dart:166`),
  amelynek saját fejléc-kommentje szerint EZ a kötelező hely az ilyen
  történeti kulcsoknak ("egy feature egyikről a másikra mozog... soha nem
  egy konstans helyben szerkesztésével").
- **Hatás:** `JsonDocumentStore.readBody()` (`json_document_store.dart:86-97`)
  a saját (user-scope-olt) kulcs hiányában A `legacyKey`-t olvassa vissza —
  jelenleg ez holt kód, mert semmi nem ír a `'ss.community.drafts.v1'`
  literálra. DE: ez a kör kifejezetten `risk=high`-nak lett minősítve (S7,
  §0.0) PONTOSAN az audience-vezérelt tartalom felhasználó-izolációja miatt,
  és a pre-flight D3 explicit kimondta, hogy ez az ELSŐ user-id-particionált
  storage-minta a repóban — ez a fallback-ág pontosan azt az izolációs
  garanciát töri meg építészetileg, amit a kör bevezetni hivatott: ha
  BÁRMILYEN jövőbeli kód (debug, teszt-fixture, egy másik feature
  véletlen kulcs-újrafelhasználása) valaha ír erre a megosztott literálra,
  MINDEN usernek, akinek még nincs saját v2-draftja, ugyanazt az idegen
  draftot adná vissza a `readDraft()`. A `community_outbox.dart` UGYANEBBEN
  a körben helyesen ismerte fel ugyanezt a helyzetet ("No legacy key — the
  outbox is a fresh Kör 12 document with no pre-envelope shape",
  `community_outbox.dart:270-274`, `legacyKey: ''`) — a draft store nem
  követte a saját testvér-fájlja döntését.
- **Kötelező javítás:** `CommunityDraftStore.open`-ban `legacyKey: ''`
  (üres, mint a `community_outbox.dart`-ban), és a docstring
  "Schema version" / class-header szakaszának a fiktív migrációs történetet
  törölni kell — helyette egyszerűen: "nincs korábbi verzió, ez az első Kör
  12 dokumentum".
- **Ellenőrzés:** egy próbateszt (review-only, a jelentésben dokumentálva,
  NEM commitolva): `store.writeString('ss.community.drafts.v1', <B user
  draftja>)`, majd `CommunityDraftStore.open(userId: A).readDraft()` — a
  javítás ELŐTT ez B draftját adja vissza A-nak; a javítás UTÁN `null`-t ad
  (a store a sajátjától eltérő kulcsot nem olvassa).
- **Státusz:** OPEN

### F2 — MINOR — Doc-comment olyan viselkedést állít, amit a kód nem tesz

- **Fájl:** `lib/features/community/application/outbox/community_outbox.dart:239-242`
- **Probléma:** a `CommunityOutbox.enqueue` interfész doc-comment-je szerint
  "Throws `StateError` when a pending record with the same idempotency key
  already exists" — a tényleges `LocalCommunityOutbox._enqueue`
  (`community_outbox.dart:313-331`) SOHA nem dob `StateError`-t: egy
  duplikált kulcsnál `CommunityOutboxEnqueueResult(accepted: false, record:
  existing.first)`-öt ad vissza. A `docs/execution/implementer-preamble-minimax.md`
  §1 kifejezetten megköti, hogy a doc-commentbe csak tesztben bizonyított
  állítás kerülhet — ez a mondat nincs tesztelve, mert nem igaz.
- **Hatás:** egy jövőbeli `CommunityOutbox`-implementáló (pl. egy
  in-memory teszt-dupla) a doc-comment alapján `throw StateError`-t írna,
  ami a controller `try { ... } on AppFailure catch` ágát kerülné meg (a
  `StateError` nem `AppFailure`), és a §6.1 A1-invariáns (nincs hamis siker)
  helyett egy kezeletlen kivétellel állna meg.
- **Kötelező javítás:** a doc-comment cseréje a tényleges
  `accepted:false`/`record: existing.first` szerződésre.
- **Ellenőrzés:** nincs külön teszt szükséges — a meglévő
  `enqueue idempotency` teszt (`community_outbox_test.dart`) már a helyes
  viselkedést méri; a javítás csak a szöveget igazítja hozzá.
- **Státusz:** OPEN

### F3 — NOTE — A composer-screen stringjei hardcode-oltak, nem ARB-en keresztül mennek

- **Fájl:** `lib/features/community/presentation/screens/post_composer_screen.dart:51-74`
- **Megfigyelés:** a `_ComposerLabels` konstansok magyar szöveget
  tartalmaznak közvetlenül a Dart-kódban, a `CLAUDE.md` i18n-konvenciója
  ("minden user-facing string ARB-on megy") ellenére. Mérve: ez NEM ennek a
  körnek az egyedi eltérése — a Community feature MINDEN meglévő
  presentation screenje (`community_gate_screen.dart`,
  `safety_relationships_screen.dart`, `edit_profile_screen.dart`,
  `followers_screen.dart`, `community_search_screen.dart`) ugyanígy
  hardcode-olja a stringeket, egyik sem importál `AppLocalizations`-t —
  tehát ez a kör egy már meglévő, tudatosan halasztott mintát követ (a
  screen-fájl docstringje ezt explicit meg is indokolja: `lib/l10n/**` nincs
  az `allowed_paths`-on, egy jövőbeli i18n-kör mozgatja majd át). Nem
  blokkoló, csak rögzítve a nyilvántartás kedvéért.
- **Státusz:** nem blokkol.

## Gate-bizonyíték ellenőrzése

| Gate | Állított eredmény | Ellenőrizve |
|---|---|---|
| format | zöld | ✅ (saját `/tmp/review-e09-r12` klón, `tools/round-gate.sh` teljes kimenet) |
| analyze | zöld (0 issue) | ✅ |
| test post_composer_test.dart (9 teszt) | zöld | ✅ |
| test community_outbox_test.dart (6 teszt) | zöld | ✅ |
| architecture | zöld (12 allowlistelt eltérés, nincs új) | ✅ |
| secrets | zöld (0 lelet) | ✅ |
| l10n | zöld | ✅ |
| CI (teljes suite + property + APK) | — | a review nem dispatch-elt CI-t; az orchestrátor a review lezárása UTÁN indítja |

## Merge-döntés

**Nem mehet merge-re jelenleg** — F1 (MAJOR) nyitva. A javítás triviális
(`legacyKey: ''` + docstring-korrekció, egy-két soros diff, nem hizlalja a
kört) — a MiniMax egy javító körben lezárhatja F1-et és F2-t egyszerre.
