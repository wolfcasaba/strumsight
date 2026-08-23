# E09-R10 review — Share artifact szerződések

- **Reviewer:** Claude Sonnet 5 (orchesztrátor), read-only, izolált munkapéldány (`/home/ubuntu/ss-mm-e09-r10`)
- **Implementer:** MiniMax M3
- **Branch:** `minimax/e09-r10-share-artifact-contracts`
- **Reviewelt HEAD:** `9772f003754ae2e28ab8dd4a0ea08a17306c2d7a`
- **Pre-flight commit (bázis):** `863f761bfd61...` (brief-revízió D1-D4 + ADR 0404)
- **Verdikt: APPROVED** — 0 BLOCKER, 0 MAJOR, 1 MINOR (nem blokkoló), 2 NOTE (jövőbeli kör horgai)

## 1. Scope-audit

```
python3 tools/scope-audit.py --repo /home/ubuntu/ss-mm-e09-r10 \
  --brief docs/rounds/e09-r10-share-artifact-contracts.md --base 863f761b
→ Legacy scope audit OK (863f761bfd61..9772f003754a, 10 changed path(s), 0 generated/ignored)
```

10 fájl, mind a brief §4 `allowed_paths` listáján (9 engedélyezett + a brief
saját §10 handoff-bővítése). `docs/adr/0404-*.md` a pre-flightban készült,
NEM a kör diffjében. `community_post.dart` (a meglévő
`CommunityShareArtifact`/`UnfilledCommunityShareArtifact` bázis) — érintetlen,
csak importálva.

## 2. Gate (`tools/round-gate.sh test/features/community/application/share_artifact_test.dart`)

Izolált munkapéldányban, MINDEN lépés külön processzként, csonkítatlan
kimenettel (`/tmp/gate-e09-r10.log`):

```
format                                                     zöld
analyze                                                    zöld
test test/features/community/application/share_artifact_test.dart  zöld
architecture                                               zöld
secrets                                                    zöld
l10n                                                        zöld
backend ruff format                                        zöld
backend ruff check                                         zöld
backend pytest                                             zöld
MINDEN GATE ZÖLD.
```

A brief §7 külön, önálló parancsa is lefutott (nem láncolva):

```
cd backend && .venv/bin/python -m pytest tests/community/test_share_artifact_schema.py -q
→ 21 passed
```

## 3. Valódi-sértés próba — a review MAGA is elvégezte (nem csak elfogadta az implementer állítását)

A §6.1 KÖTELEZŐ próbáját ("vedd ki az ismeretlen `schemaVersion` elutasító
ágát... A3-nak PIROSNAK kell lennie") a review a saját munkapéldányában
fizikailag elvégezte:

1. `backend/app/community/schemas/artifacts.py::_validate_schema_version`
   equality-ellenőrzését eltávolítottam.
2. `pytest backend/tests/community/test_share_artifact_schema.py -q` →
   **2 FAILED** (`test_unknown_schema_version_rejected`,
   `test_strict_validator_rejects_lenient_payload`), a várt PIROS.
3. Visszaállítottam (`git status --short` a fájlra: tiszta), újrafuttatva →
   21 passed.

Az implementer §10.3-ban dokumentált saját `monkeypatch`-es próbája
(`test_reality_probe_unknown_schema_version_rejection_works`) a
suite-ba ÁLLANDÓ regressziós őrként van beépítve — ez a review fenti,
kézzel végzett próbájának permanens megfelelője, mindkettő a forrás
`_validate_schema_version` globális névre hivatkozik (a monkeypatch
ténylegesen hat).

## 4. Kód-review (a négy mapper + a sealed hierarchia, kézzel olvasva)

- **A1** (nincs belső import): mind a négy mapper kizárólag a saját
  forrás-feature `public.dart`-ját importálja
  (`practice/public.dart`, `songs/public.dart`, `audio_analysis/public.dart`,
  `gamification/public.dart`) + a Community saját `share_artifact.dart`-ját.
  A `song_share_mapper.dart` extra `core/music/strum.dart` importja megosztott
  core-típus (`StrumDirection`), nem feature-belső — nem sérti a határt.
- **D1 (ADR 0404) leképezés élesben megerősítve:** `song_share_mapper.dart`
  három factory (`songResultFromSong`/`originalProgressionFromSong`/
  `planTemplateFromSong`), mind `Song`-ból; `achievement_share_mapper.dart`
  kettő (`achievementFromDefinitionAndProgress`/`challengeFromDefinitionAndReceipt`),
  mind a gamifikációból. Nincs ötödik mapper-fájl.
- **D3 (ADR 0404):** `analysis_share_mapper.dart` az `audio_analysis/
  public.dart` `AnalysisComparison`-jából épül (NEM az `analyze` feature-ből)
  — megerősítve.
- **D4 (ADR 0404):** a challenge mapper a `LedgerEntrySyncStatus`-t
  (E08-R28/ADR 0394) fordítja wire-literálra, NEM az `EvidenceTrust`-ot —
  megerősítve (`achievement_share_mapper.dart:28-34`).
- **A5** (nyers audio/video/waveform/landmark hiánya): mind a négy mapper
  kézzel-válogatott mezőket másol (pl. `practice_share_mapper.dart` csak
  `activeDuration/pausedDuration/attempts.length/finishReason/bestScore/
  coachingSummary`-t visz át, a per-attempt DSP/vision-bizonyítékot nem).
  Backend oldalon minden konkrét Pydantic modell `extra="forbid"` — ez a
  valódi garancia, nem a tiltott-kulcs teszt.
- **A6** (SharePreview alapértelmezetten KI): mind az 5 flag `false`.

## 5. Dedikált biztonsági review (kötelező, a brief `risk = "high"`)

Külön `security-reviewer` agent futott, izolált olvasás. **Verdikt: PASS.**
0 BLOCKER, 0 MAJOR. A round jelenleg **be nincs kötve** sehova (a
Dart entitást a `community/public.dart` nem exportálja, a backend
`parse_share_artifact`-ot egy router sem hívja — Kör 11+ dolga), ez
korlátozza a kockázati felületet.

- **MINOR-1** — `coaching_codes`/`chords`/`metrics` lista-mezőknek nincs
  `max_length` felső korlátja (a skalár mezők mind kapottak). Nem blokkoló:
  a round jelenleg nincs bekötve élő endpointra; a brief §6 A-celláinak
  egyike sem követeli meg explicit. **Horog a Kör 11-nek**: a post-creation
  endpoint bekötésekor a három listát is korlátozni kell, mielőtt kliens-
  bemenetet fogyasztanak.
- **NOTE-1** — a `challengeFromDefinitionAndReceipt` a `receiptStatus`-t a
  `receipt`-től FÜGGETLEN paraméterként kapja (Dart oldal); a backend
  `ChallengeArtifact`-nak nincs `model_validator`-a, ami
  `reward_status_code == "verified" ⟹ ledger_id is not None`-t
  kikényszerítené. Jelenleg ártalmatlan (kliens-oldali, nem perzisztált
  megosztás-előkészítés) — **horog a Kör 11-nek**: a szerver NEM bízhat meg
  a kliens-állította `verified`/`rewardXp`/`ledgerId`-ban, ha egyszer
  perzisztálja a posztot; a valódi hitelesítést a reward-ledgerből kell
  újra-levezetnie.
- **NOTE-2** — a konkrét `fromJson` factory-k (pl.
  `PracticeSummaryArtifact.fromJson`) a `schemaVersion`-t csak
  `_requireInt`-tel olvassák, az egyenlőség-ellenőrzés
  (`_requireSchemaVersion`) csak a bázis `ShareArtifact.fromJson`-ban fut. A
  konkrét factory-k KÖZVETLEN hívása (nem a bázison át) megkerülné az A3
  védelmet a Dart oldalon — a backend oldali validátor marad az
  authoritatív kapu, ez csak egy defense-in-depth rés a jövőbeli (Kör 13+)
  szerver→kliens dekódolási útvonalon.

Egyik lelet sem éri el a BLOCKER/MAJOR küszöböt — mindhárom a §4
"Amit ez a session SOHA nem tesz" alá eső, jövőbeli körre tartozó bővítés,
nem ennek a körnek a saját acceptance-kritériumának hiánya. Nem indokolt
javító kör.

## 6. Összegzés

A1–A6 mind teljesítve, mérve (nem csak állítva). A brief §5 kötött
döntései (§5.1–§5.3) és az ADR 0404 §D1–D5 a kódban élesben visszaköszönnek.
A §6.1 valódi-sértés próbát a review önállóan megismételte, függetlenül az
implementer állításától. **Merge-re alkalmas.**
