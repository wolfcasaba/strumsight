# E03-R02 — Review

Brief: `docs/rounds/e03-r02-song-document-identity-metadata.md`
Diff: `git diff origin/main...codex/e03-r02-song-document-identity-metadata` (HEAD `019e9dd`)
Reviewer: Claude Sonnet 5 (orchestrátor) · Dátum: 2026-08-02
Verdikt: **APPROVED**

## Összegzés

BLOCKER: 0 · MAJOR: 0 · MINOR: 1 · NOTE: 2

## Kör-előzmény (H6 self-heal recovery — miért nem a szokásos READY_FOR_REVIEW útvonal)

Az implementáció (M3, 1 attempt, `/home/ubuntu/ss-router-e03-r02`) ténylegesen
scope-tiszta volt, de a router `BLOCKED`-ba futott két hiba miatt: (1) a
`coverage/lcov.info` (a brief §7 saját elfogadási kritériuma miatt legitim
melléktermék) nem volt a scope-audit `GENERATED_IGNORED_PREFIXES`
listáján, (2) M3 saját maga commitolt (`439392b`), megszegve a "a modell
sosem tulajdonolja a Git-et" szerződést. Egy self-heal kör (PR #57, `6db1170`,
`docs/LESSONS.md` L49) az (1) hibát javította, a (2)-t szándékosan NEM
lazította (a `test_scope_audit_rejects_a_model_created_commit` egy szándékos
invariáns), és a commit-üzenetében rögzítette, hogy a konkrét megrekedt
task-ot "a worktree kézi resetje" oldja fel, nem router-policy módosítás.

Ez az orchestrátor-session ezt hajtotta végre: `git reset --soft` az M3
commitjára (visszaállítva a diffet uncommitted állapotba), a branch
rebase-elve a healed `main`-re (`2c8bcdc`), a diff scope-audit ellen
ellenőrizve (minden módosított útvonal pontosan a brief §4 listáján), a
gate saját kézzel újrafuttatva, majd a diff az orchestrátor saját
authorship-jével commitolva (`019e9dd`) — pontosan a normál
READY_FOR_REVIEW → orchestrátor-commit szerződés szerint, csak a router
állapotgépe helyett kézzel végrehajtva, mert a `BLOCKED` állapotból nincs
sanctioned automatikus visszatérési út `READY_FOR_REVIEW`-ba anélkül, hogy a
már elkészült munkát egy teljes friss M3-attempt eldobná. Az M3 diffje maga
**egyetlen byte-ot sem változott** ebben a recovery lépésben.

## Acceptance criteria

| # | Kritérium | Teljesült | Bizonyíték |
|---|---|---|---|
| 1 | Minden typed ID trimelt, nem üres, limitált, determinisztikusan egyenlő és hash-elhető. | ✅ | `song_id.dart` `SongIdValidator.normalize` + `SongTypedId.==`/`hashCode`. Reviewer-oldali független próba (`_review_probe_test.dart`, törölve): `SongId('a'*127)`/`128` accept, `129` → `SongIdValidationException` (MAX_LENGTH=128); üres és `'   '` → exception. `song_id_test.dart` 25/25 saját futtatásban is zöld. |
| 2 | Metadata title trimelt/nem üres, capo és tag limit validált, collectionök immutable-ek. | ✅ | `song_metadata.dart` `_normalizeTitle` (trim+empty+maxLength), `defaultCapo` 0–15 range-check, `_normalizeTags` (trim+lowercase+dedup+maxTagCount/maxTagLength), `tags` getter `List<String>.unmodifiable`. `song_document_test.dart` "SongMetadata validation" csoport zöld. |
| 3 | Codec ugyanarra a documentre byte-sorrendben stabil JSON-t ad, UTC és revision round-trip megmarad. | ✅ | `song_document_codec.dart` fix kulcssorrend `_documentToMap`/`_metadataToMap`/stb.; reviewer-próba: két egymást követő `encode()` egy populált (tags+assets) dokumentumra byte-azonos; offset-timestampes dokumentum round-trip után `toUtc().microsecondsSinceEpoch` egyenlő és `isUtc == true`. `song_document_codec_test.dart` 11/11 zöld. |
| 4 | Domain transitív import auditja nem talál Flutter/Riverpod/platform/más feature importot; új domain fájlok line coverage ≥90%. | ✅ | **Valódi-sértés próba:** `song_id.dart`-ba ideiglenesen beszúrva `import 'package:flutter/widgets.dart';` → a "Domain purity" teszt PIROSRA váltott, pontos hibaüzenettel (`song_id.dart:15: framework or storage import`); visszaállítás után ismét zöld. Coverage — reviewer saját `flutter test --coverage` futtatása az izolált klónban, `coverage/lcov.info` közvetlen olvasva: `song_id.dart` 63/63 (100%), `song_source.dart` 53/53 (100%), `song_document.dart` 46/45 (97.8%), `song_asset_reference.dart` 44/42 (95.5%), `song_metadata.dart` 67/66 (98.5%), `song_marker.dart` 28/26 (92.9%) — mind ≥90%, egyezik az implementer §10.3 táblájával. |

### Kötelező megkülönböztető mátrix (§6)

| Bemenet | Várt | Mérve |
|---|---|---|
| ID üres/whitespace | stabil failure | ✅ reviewer-próba |
| ID max−1/max/max+1 | accept/accept/reject | ✅ reviewer-próba (127/128 accept, 129 reject) |
| source type ismert/ismeretlen | round-trip/fail-closed | ✅ reviewer-próba: `"createdInApp"` → `"totallyUnknownType"` tamper a kódolt JSON-ban → `decode()` `SongDocumentCodecException` |
| timestamp offsetes/UTC | UTC-ra normalizált azonos instant | ✅ reviewer-próba (`+05:00` offset → azonos `microsecondsSinceEpoch`, `isUtc=true`) |
| title trimelhető/csak whitespace | normalizált/reject | ✅ `song_document_test.dart` "SongMetadata validation" |

## Gate-bizonyíték

Saját kézzel, izolált `/tmp/review-e03-r02` klónban (nem a közös munkapéldányban):

```
tools/round-gate.sh test/features/song_trainer/domain/song_id_test.dart \
  test/features/song_trainer/domain/song_document_test.dart \
  test/features/song_trainer/data/local/song_document_codec_test.dart
```

format ZÖLD · analyze ZÖLD · 3 célzott teszt ZÖLD (25+57+11 = 93/93) ·
architecture ZÖLD (12 allowlisted deviation, változatlan az E03-R01 óta).

CI (`build-apk.yml`, branch `codex/e03-r02-song-document-identity-metadata`,
dispatch `headSha` = `019e9dd`, run
[30732535213](https://github.com/wolfcasaba/strumsight/actions/runs/30732535213)):
státusza a merge-döntés előtt ellenőrizve, lásd a kör-jelzés fájlt.

## Scope-audit

`git diff --stat origin/main...HEAD` (12 fájl, `/tmp/review-e03-r02`-ban mérve):
mind a 12 megváltozott útvonal pontosan a brief §4 `allowed_paths` listáján
van (`lib/features/song_trainer/domain/models/*.dart` × 6,
`lib/features/song_trainer/domain/public.dart`,
`lib/features/song_trainer/data/local/song_document_codec.dart`, a 3
megfelelő teszt, `docs/rounds/e03-r02-*.md` §10 handoff).
**Engedélyezett fájlokon kívüli változás: nincs.** A router saját
`changed_paths` mérése (a `BLOCKED` állapotban rögzített
`.ai/runs/E03-R02/router-result.json`) ugyanezt a 12+1 (a `coverage/lcov.info`
mellékterméket is beleértve) halmazt mutatta — az orchestrátor commit ebből
a `coverage/lcov.info`-t szándékosan NEM vette fel (generált, gitignore-olt
melléktermék, nem tartozik a brief §4 listájára).

## Megállapítások

### F1 — MINOR — `SongMetadata._validateText` az "üres" hibakódot a "túl hosszú" esetre dobja

- **Fájl:** `lib/features/song_trainer/domain/models/song_metadata.dart:177-182`
- **Probléma:** `_validateText(field, value, emptyCode)` kizárólag a
  `value.length > maxTextLength` ágat ellenőrzi, de a paraméter neve és a
  hívási helyeken átadott kód (`artistEmpty`, `albumEmpty`, `composerEmpty`,
  `copyrightEmpty`, `notesEmpty`) "üres" szemantikát sugall — valójában a
  túl hosszú inputra dobódik. Tényleges üres string ezekhez a mezőkhöz
  NEM validációs hiba (ami helyes, mert nincs ilyen acceptance criterion),
  de a kód neve félrevezető egy jövőbeli olvasónak/hívónak.
- **Hatás:** nincs futásidejű vagy teszt-szintű hatás — a §6 acceptance
  criteria egyike sem írja elő artist/album/composer/copyright/notes
  emptiness-ellenőrzést, és a kódok stabilak maradnak (nem UX-fordítási
  kulcs). Az implementer maga is dokumentálta ezt a brief §10.7-ben
  ("nem szerencsés, de nem blokkoló").
- **Kötelező javítás:** átnevezni a kódokat/paramétert (`tooLongCode`) egy
  következő, ezt a fájlt is érintő körben (pl. E03-R03 domain-bővítés),
  vagy ha valódi emptiness-szemantika kell, azt is validálni.
- **Ellenőrzés:** a kód-átnevezés után a meglévő `song_document_test.dart`
  "SongMetadata validation" csoport asserted kódjait frissíteni kell.
- **Státusz:** OPEN — nem hizlalja a diffet érdemben ebben a körben, a
  §9 kockázat-listán már szerepel implicit módon; follow-up a következő
  domain-érintő körre (E03-R03) halasztva, nem blokkolja ezt a merge-öt.

### F2 — NOTE — ADR 0089 §Döntés 1 `domain/model/` (egyes szám), a brief és a kód `domain/models/` (többes szám)

- **Fájl:** `docs/adr/0089-song-document-v2.md` (merge-elt ADR, ebben a körben
  nem módosítható — tilos zóna) vs. a brief §4 és a tényleges
  `lib/features/song_trainer/domain/models/*.dart` elérési utak.
- **Probléma:** doc-only elnevezési eltérés egy már elfogadott ADR és a
  ténylegesen implementált (és a brief §4-ben explicit felsorolt, tehát
  mérvadó) útvonal között.
- **Hatás:** nincs — a doc-elsőbbségi lánc szerint a kör saját brief §4-e
  (a kijelölt SDD-kör artefaktuma) a mérvadó a Chapter/ADR fölött, és a kód
  ezzel egyezik.
- **Javasolt irány:** egy jövőbeli doc-only follow-up körben az ADR 0089
  szövegét `domain/models/`-re javítani (mint az E03-R01 review F1-je a
  baseline dokumentum ADR-linkjeit).
- **Státusz:** OPEN, nem blokkoló.

### F3 — NOTE — `SongId.safeFilename` a vezető kötőjeleket nem vágja le, a komment mást állít

- **Fájl:** `lib/features/song_trainer/domain/models/song_id.dart:155,166-168`
- **Probléma:** a `// collapse leading hyphens.` komment és a `lastWasHyphen =
  true` kezdőállapot azt sugallja, hogy a vezető kötőjelek is levágásra
  kerülnek, de a tényleges `while (cleaned.endsWith('-'))` ciklus csak a
  **záró** kötőjeleket vágja. Az implementer ezt maga is dokumentálta
  (brief §10.7).
- **Hatás:** nincs — a §6 acceptance criteria nem ír elő vezető-kötőjel
  szabályt, csak "deterministic filesystem-safe projection"-t, ami
  teljesül; a `song_id_test.dart` 113-117. sora ezt a viselkedést kifejezetten
  rögzíti (pinned behavior).
- **Javasolt irány:** vagy a komment pontosítása, vagy (ha a UX ezt kívánja)
  a vezető kötőjelek levágásának hozzáadása egy jövőbeli körben.
- **Státusz:** OPEN, nem blokkoló.
