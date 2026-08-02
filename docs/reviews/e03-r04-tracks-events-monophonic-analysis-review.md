# E03-R04 — Review

Brief: `docs/rounds/e03-r04-tracks-events-monophonic-analysis.md`
Diff: uncommitted worktree diff, `/home/ubuntu/ss-router-e03-r04` @ pre-flight
base `389d32e` (`docs/LESSONS.md` L51 — kept uncommitted until the review
cycle fully resolves)
Reviewer: Claude Sonnet 5 (orchestrator, same session) · Dátum: 2026-08-02
Verdikt: **APPROVED** (javító kör után, ld. §Javító kör lent)

## Összegzés

BLOCKER: 1 → FIXED · MAJOR: 0 · MINOR: 1 (OPEN, follow-up) · NOTE: 1 (OPEN, follow-up)

## Acceptance criteria

| # | Kritérium | Teljesült | Bizonyíték |
|---|---|---|---|
| 1 | Minden track/event subtype determinisztikusan round-tripel és immutable. | ✅ | `song_track_codec_test.dart` (17/17 zöld, saját mérésem `/tmp/review-e03-r04`-ben) — round-trip minden subtype-ra, `List.unmodifiable` a track/event listákon, byte-identical kettős encode. |
| 2 | Pitch/string/fret invalid érték stabil validation failure; unknown direction és technique adatvesztés nélkül megmarad. | ✅ | `SongNoteEvent` konstruktor (`song_event.dart:205-269`) MIDI/string/fret/velocity ellenőrzés stabil kódokkal; `SongStrumEvent.direction: StrumDirection?` null=unknown (ADR 0113 Döntés 3); `SongNoteTechnique.unknown` megőrzi a raw/display párost (`song_note_technique.dart:52-61`). |
| 3 | Az analyzer azonos inputra azonos reportot ad, tie és valódi overlap elkülönül. | ❌ | **Determinizmus igen** (`note_track_analyzer_test.dart` „same input → same report"), **de a tie/overlap elkülönítés hibás** — lásd F1 (BLOCKER). |
| 4 | A document teljes tracklistát tárol platform- és parserfüggés nélkül. | ✅ | `song_document.dart:76-159` `tracks: List<SongTrack>` mező, codec round-trip teszt fedi; `BackingAudioTrack.assetId: SongAssetId`, nincs platform path mező. |

## Scope-audit

```
git diff --stat 389d32e -- (uncommitted worktree state)
```

Minden módosított/új fájl a brief §4 engedélyezett listáján belül van:

- ÚJ: `song_track.dart`, `song_event.dart`, `song_instrument.dart`,
  `song_note_technique.dart`, `services/note_track_analyzer.dart`,
  `test/.../song_track_codec_test.dart`, `test/.../note_track_analyzer_test.dart`
- MÓDOSÍTVA: `song_document.dart`, `song_document_codec.dart`, `public.dart`,
  a brief maga (§10 handoff)
- `backing_audio_track.dart` a listán ÚJ-ként szerepel, státusza a
  handoff §10.3 szerint MÓDOSÍTVA `export 'song_track.dart' show
  BackingAudioTrack;`-re — indokolt (Dart 3 sealed-library invariant),
  dokumentálva, a fájl maga a listán marad.

Engedélyezett fájlokon kívüli változás: **nincs.**

## Megállapítások

### F1 — BLOCKER — `NoteTrackAnalyzer.analyze` csak SZOMSZÉDOS (start-sorrendben egymást követő) párokat hasonlít össze, nem futó maximumot — egy azonos-pitch tie "kitakarhat" egy valódi, eltérő-pitch overlapet

- **Fájl:** `lib/features/song_trainer/domain/services/note_track_analyzer.dart:158-174`
- **Probléma:** az overlap-detekció `ordered[index-1]` (a start szerint
  rendezett lista KÖZVETLEN megelőző eleme) végét (`prevEnd`) hasonlítja
  `ordered[index].start`-hoz — nem egy futó maximum-véget (sweep-line). Ha a
  közvetlen megelőző elem korábban ér véget, mint egy KORÁBBI (nem
  szomszédos) note, egy valódi, azzal a korábbi note-tal átfedő, eltérő
  pitchű esemény némán kimarad az `overlapCount`-ból — és ha a köztes elem
  (a valódi átfedő elemmel szomszédos) éppen AZONOS pitchű a hosszú
  note-tal (tie-candidate, nem overlap), a lánc teljesen megszakad:
  `isMonophonic` hamisan `true`-t ad egy ténylegesen polifón track-re.
- **Reprodukció (mért, önálló referenciaszámítással ellenőrizve):**
  ```
  A: 0–10000ms, pitch 60 (hosszú note)
  B: 100–200ms, pitch 60  (AZONOS pitch A-val, beágyazva A-ba → tie-candidate)
  C: 5000–5100ms, pitch 62 (KÜLÖNBÖZŐ pitch, beágyazva A-ba, de NEM fedi B-t)
  ```
  Kézi (sweep-line) referencia: A–B tie-candidate, A–C VALÓDI eltérő-pitch
  overlap, B–C nincs átfedés → `isMonophonic` **hamis**, `overlapCount ≥ 1`.
  A tényleges `NoteTrackAnalyzer.analyze([A,B,C])` kimenete:
  `isMonophonic == true`, mert a `(B,C)` szomszédos pár lokálisan valóban
  nem fedi egymást, és az algoritmus soha nem veti össze `C`-t `A`-val. Egy
  eldobható próbateszt (`/tmp/review-e03-r04/test/.../_adversarial/overlap_bug_probe_test.dart`,
  a review után törölve) PIROSAN igazolta ezt — a `flutter test` kimenete:
  `Expected: false / Actual: <true>`.
- **Hatás:** a §6 kötelező megkülönböztető mátrix 3. sora
  („end > next start → polyphonic overlap") sérül minden olyan track-re,
  ahol egy korai azonos-pitch tie "eltakarja" egy későbbi, valódi,
  eltérő-pitch overlapet. Ez nem elméleti — bármely importált riff, ahol egy
  hosszan kitartott alaphang (pl. egy bordone/drone note) alatt egy rövid,
  azonos hangmagasságú ismétlés majd egy VALÓDI másik hang következik,
  hamisan `isMonophonic: true`-nak minősül. Egy jövőbeli körben ez a
  capability resolvert (§7.3 „Monophonic Note Trainer csak ellenőrzött
  monophonic track esetén engedélyezhető") téves engedélyezésre vezetné —
  pontosan az a hiba-osztály, amit a §6 mátrix ki akar zárni.
- **Kötelező javítás:** sweep-line invariáns: tartsunk egy `runningMaxEnd`
  (és az ahhoz tartozó pitch-halmazt vagy legalább a hozzá tartozó
  reprezentatív pitch-listát) a start szerint rendezett listán való
  áthaladás közben, és minden `curr` eseményt hasonlítsunk össze MINDEN
  olyan korábbi eseménnyel, amelynek vége > `curr.start` (nem csak a
  közvetlen megelőzővel). Egy egyszerű, helyes O(n log n) megoldás: tartsunk
  egy "aktív" note-listát (min-heap vagy rendezett lista a végük szerint),
  és minden új note-nál távolítsuk el az already-ended aktívakat, majd
  hasonlítsuk össze a maradék aktívakkal (pitch szerint tie vs. overlap).
- **Ellenőrzés:** a fenti reprodukciós szcenárió (A/B/C) legyen bevett
  regressziós teszt a `note_track_analyzer_test.dart`-ban, PIROS a jelenlegi
  kóddal, ZÖLD a javítás után; érdemes egy randomizált property tesztet is
  hozzáadni (`test/property/`, HORIZON-konvenció), amely véletlen
  intervallum-halmazokon a naiv O(n²) brute-force overlap-referenciával veti
  össze `isMonophonic`/`overlapCount`-ot.
- **Státusz:** **FIXED** — a Terra (Codex) javító kör (router `terra_calls: 1`,
  `resume` a `.ai/review-findings-e03-r04.md` leletlistával) az adjacent-pair
  szkennelést egy helyes `activeNotes` sweep-line-ra cserélte
  (`note_track_analyzer.dart:157-174`: minden `curr`-nál eltávolítja a már
  véget ért aktív note-okat, majd `curr`-ot MINDEN megmaradó aktívval
  összeveti, nem csak a start-sorrend szerinti közvetlen megelőzővel), és
  hozzáadta a pontosan reprodukált regressziós tesztet
  (`note_track_analyzer_test.dart` „long note remains active past an
  intervening same-pitch tie candidate", 15. teszt). **Independens
  újra-ellenőrzés** (reviewer, saját kézzel, `/tmp/review-e03-r04` friss
  rsync-klón): az eredeti A/B/C szcenárió PIROS volt a javítás előtt (mérve
  — `Expected: false / Actual: <true>`), ZÖLD utána; egy plusz, az
  implementer felé SOHA nem közölt negyedik-note szcenárió (két FÜGGETLEN
  cross-pitch overlap ugyanazon a hosszú note-on, egy tie-vel keverve) is
  helyesen `overlapCount: 2`, `tieCandidateCount: 1`-et ad. Teljes
  `test/features/song_trainer` regresszió: **143/143 zöld** (142 + 1 új).
  M3 attempt-könyvelési incidens (nem az implementer hibája): az
  orchestrátor egy korai, gyakorlatilag azonnal megölt `resume` hívás miatt
  véletlenül elfogyasztotta az M3 „egy javító kör" keretét anélkül, hogy
  valódi M3-modellhívás történt volna (`RECOVERED_M3_CALL_2` fázis, a router
  saját, dokumentált — bár ezen az élen hibás — recovery-heurisztikája
  miatt); a router emiatt a KÖVETKEZŐ `resume`-ot közvetlenül Terrára
  (Codex) irányította, ami éppen a round §2 motor-eszkalációs szabályával
  (M3 egy kör → utána Codex) egybeesik, tehát a végeredmény a protokollnak
  megfelelő, csak a köztes könyvelés forrása nem egy valódi M3-hiba volt.
  Dokumentálva, nem produkciós kód — a `tools/ai_router/router.py` érintése
  nélkül (tilos zóna).

### F2 — MINOR — `SongNoteTechnique._normalizeRaw`/`_normalizeDisplay` sima `ArgumentError`-t dob, nem a kör saját stabil-kód konvencióját

- **Fájl:** `lib/features/song_trainer/domain/models/song_note_technique.dart:89-117`
- **Probléma:** a kör MINDEN más modellje (`SongTrack`, `SongEvent`
  altípusok, `SongInstrument`, a codec) egy dedikált
  `Stable...Exception` + géppel olvasható kód-konstans mintát követ; ez a
  fájl helyette csupasz `ArgumentError.value(...)`-t dob string üzenettel.
  Egy jövőbeli fogyasztó (pl. import-hibakezelő UI), amely a többi modell
  mintáját követve `code`-ra kapcsol, itt nem tud stabilan reagálni.
- **Hatás:** karbantarthatósági inkonzisztencia, nem funkcionális hiba —
  a validáció maga helyesen működik (teszt: „SongNoteTechnique.equal
  compares kind+raw+display" közvetve fedi, de az üres/túl hosszú
  raw/display esetet egyik teszt sem célozza expliciten).
- **Kötelező javítás (opcionális e körön belül, KÖVETKEZŐ kör is
  elfogadható):** vezessen be egy `SongNoteTechniqueValidationException` +
  `SongNoteTechniqueValidationCode` párost, ugyanabban a mintában, mint a
  többi modell.
- **Ellenőrzés:** teszt az üres és a túl hosszú `rawCode`/`displayText`
  esetre, ami a stabil kódot asserteli.
- **Státusz:** OPEN (follow-up-ként is elfogadható, ha a fixer kör diffje
  emiatt nőne túl nagyra — a döntés a fixer kör hatásköre).

### F3 — NOTE — `BackingAudioTrack` gain/offset hibái a `negativeStart` kódot használják újra

- **Fájl:** `lib/features/song_trainer/domain/models/song_track.dart:313-324, 353-360`
- **Megfigyelés:** a `gainDb` és `gridOffset` validációs hibái a
  `SongTrackValidationCode.negativeStart` kódot dobják (`song_event.dart`-
  ban deklarálva „start"-hoz), ami félrevezető géppel olvasva. Nem blokkol —
  a `field` paraméter helyesen `'gainDb'`/`'gridOffset'`-et hordozza, tehát
  az `Exception.toString()` és a `field` kulcs alapján továbbra is
  megkülönböztethető, csak a `code` konstans neve pontatlan.
- **Javasolt (nem kötelező):** dedikált kód
  (`songTrack.gainDb.outOfRange`, `songTrack.gridOffset.negative`) egy
  jövőbeli körben.

## Gate-bizonyíték ellenőrzése

| Gate | Állított eredmény (implementer, §10.2) | Ellenőrizve (reviewer, saját kézzel, izolált `/tmp/review-e03-r04` klón) |
|---|---|---|
| format | zöld | ✅ zöld |
| analyze | zöld | ✅ zöld |
| test `song_track_codec_test.dart` | zöld (17/17) | ✅ zöld (17/17) |
| test `note_track_analyzer_test.dart` | zöld (14/14, javítás előtt) → zöld (15/15, javítás után) | ✅ javítás előtt zöld volt DE a hibát nem fedte (F1); javítás UTÁN saját kézzel újramérve zöld (15/15), és a hiba-reprodukció is zöldre fordult |
| architecture | zöld | ✅ zöld |
| teljes `test/features/song_trainer` | 142/142 zöld | ✅ 142/142 zöld |
| CI (teljes suite + property + APK) | nem futott (orchestrátor dolga) | — a review lezárása UTÁN, a fixer kör után dispatch-elendő |

A jelentett parancskimenetek valósak — a gate ténylegesen zöld. A zöld
kapu azonban **nem bizonyíték** a §6 mátrix 3. sorára: az implementer saját
tesztje csak SZOMSZÉDOS-lánc overlapeket fedett (ld. brief §6 megjegyzés:
„bemásolt zöld kimenet önmagában nem evidencia" — pontosan ez az eset).

## Javító kör

1. Leletlista: `.ai/review-findings-e03-r04.md` (F1 BLOCKER, F2 MINOR opcionális, F3 NOTE).
2. `tools/ai-router-round.sh resume` → router `terra_calls: 1`, `status: READY_FOR_REVIEW`, `reason: "final gate passed"`.
3. Reviewer saját kézzel újramérte (fent) — F1 FIXED, evidence-szel.
4. F2/F3 nyitva maradtak follow-up-ként (nem blokkolnak, a brief §9 egyik
   sem nevezi meg őket kötelezőként; a diffet nem hizlalták volna érdemben).

## Merge-döntés

**Merge ENGEDÉLYEZETT** (ADR 0052): a helyi gate minden eleme zöld
(saját kézzel, izolált `/tmp/review-e03-r04` klónban újramérve), a diff a §4
listáján belül marad, és nincs nyitott BLOCKER/MAJOR. A CI-dispatch (teljes
suite + randomizált property + APK) az orchestrátor következő lépése; a
squash-merge csak az exact-SHA CI zöld után történhet.
