# E09-R19 — Média feldolgozás, privacy és moderation state

- **Státusz:** PREPARED (előre megírva 2026-08-22, kód olvasva: `main @ db6293f4`)
- **Típus:** Chapter 10 (Epic 9 — Community Platform), Kör 19
- **Kör-azonosító:** `E09-R19`
- **Branch:** `<motor>/e09-r19-media-processing-privacy-and-moderation-state`
- **Előfeltétel:** `E09-R18` merge-elve
- **Brief szerzője:** Claude (Opus 5)
- **Előre kiosztott ADR:** `ADR 0408` — **ELAVULT, ld. §0.0 D1.** Tényleges: **[ADR 0412](../adr/0412-media-processing-privacy-and-moderation-state.md)**. Az ADR-t a Claude írta meg a kör indítási pre-flightjában a §5 döntéseiből; az implementer a `docs/adr/`-t NEM érinti (TILOS zóna).

> ⚠ **Pre-flight (indítás előtt KÖTELEZŐ):** olvasd újra a Kör 18 `media` tábla TÉNYLEGES `state` mezőjét és értékkészletét — ez a kör bővíti állapotgéppé, nem cseréli le. Eltérésnél
> §0.0 brief-revízió, NEM csendes lista-tágítás.

```ai-router
schema_version = 1
risk = "high"
allowed_paths = [
  "backend/app/community/tasks/media_processing.py",
  "backend/app/community/services/media_access_service.py",
  "backend/app/community/moderation/media_moderation.py",
  "backend/app/community/models/media.py",
  "backend/alembic/versions/e09_r19_0013_community_media_state.py",
  "lib/features/community/presentation/widgets/community_media_player.dart",
  "backend/tests/community/test_media_processing.py",
  "test/features/community/presentation/community_media_player_test.dart",
  "docs/rounds/e09-r19-media-processing-privacy-and-moderation-state.md",
]
gate_tests = [
  "test/features/community/presentation/community_media_player_test.dart"
]
native_gate = false
```

## 0.0 Brief-revízió (orchestrátor pre-flight, Claude Sonnet 5, 2026-08-23, `main @ 71b74a20`)

Teljes indoklás: **[ADR 0412](../adr/0412-media-processing-privacy-and-moderation-state.md)**
Kontextus szakasza (9 mért pont) + Döntés szakasz (D1–D8). Rövid összefoglaló:

- **D1 — ADR-szám.** Az előre kiosztott `0408` már merge-elt (bookmark-kör)
  → tényleges szám **`0412`** (`tools/round-slots.py reserve-adr`).
- **D2 — `allowed_paths` pótlás: `backend/app/community/models/media.py`.**
  A brief §5 „Tilos zóna" listája már saját zárójeles megjegyzéssel
  („bővítés indokolt, nem átírás") előírta ennek a fájlnak az additív
  módosítását, de a gépi `allowed_paths` tömb és a §4 táblázat kihagyta —
  ez egy önellentmondó scope-rés, nem szándékos tiltás. **A fájl felkerült
  az `allowed_paths`-ra** (ld. fent), **szigorúan additív korlátozással**:
  ÚJ `processing_state` oszlop + konstansok/allowlist, plusz az A6 audit-
  igényét kiszolgáló nullable oszlopok UGYANAZON a soron (`moderation_decision`,
  `moderation_confidence`, `moderation_provider`, `moderation_provider_version`,
  `moderated_at` — pontos nevek az implementer döntése, a szerep kötött; ADR
  0412 D2 részletezi). Az `upload_state` oszlop, annak értékkészlete,
  indexei és tranzíciói (Kör 18, ADR 0410) **változatlanok maradnak** —
  ezek módosítása a fájl engedélyezettsége ELLENÉRE is H3.
  A `processing_state` a brief §3/§8 szerinti hét literál értéket veszi fel
  (`uploaded`/`scanning`/`transcoding`/`review`/`ready`/`rejected`/`deleted`)
  — ez egy MÁSODIK, önálló oszlop, nem az `upload_state` gép bővítése (ADR
  0412 D2).
- **D3 — nincs automatikus trigger-bekötés ebben a körben.**
  `media_upload_service.py` (Kör 18) NEM az `allowed_paths` része és NEM
  módosul. A `tasks/media_processing.py` közvetlenül hívható, tesztelhető
  függvényeket exportál; a finalize → feldolgozás-indítás tényleges
  bekötése egy KÉSŐBBI wiring-kör nyitott horga (ADR 0412 D3, HANDOFF §6-ba
  kötelező bekerülnie záráskor).
- **D6 — a signed playback URL NEM az `ObjectStore`-on keresztül megy.**
  `storage/object_store.py` (Kör 18) csak PUT-signinget definiál, NINCS az
  `allowed_paths`-on, módosítása H3 lenne. A playback-token
  alkalmazás-szintű, önálló HMAC-SHA256 aláírás `media_access_service.py`-ban
  (ADR 0412 D6) — a valódi bucket-oldali GET-signing egy KÉSŐBBI kör dolga.
- **D7 — az audience-ellenőrzés a meglévő `policies/access_policy.py`-t
  importálja** (`CommunityAccessPolicy.evaluate_content_access`,
  `RelationshipContext`) — READ-ONLY import, a fájl nem kerül
  `allowed_paths`-ra és nem módosul (ADR 0412 D7).
- **D8 — a metaadat-eltávolítás és a codec/duration/resolution/frame-rate
  „korlátozás" hatóköre stdlib-only.** A `requirements.txt` NINCS
  `allowed_paths`-on és csomagtelepítés tilos (nincs Pillow/ffmpeg-python/
  mutagen a repóban, mérve) → az EXIF/GPS-strip a fixture formátumra (A1)
  szabott bájt-szintű implementáció, a HEIC-szerű rések a brief §9 már
  névvel nevezett, nyitott kockázata marad; a codec/duration/resolution/
  frame-rate „korlátozás" a kliens-deklarált mezők allowlist/határérték-
  ellenőrzése, NEM valódi bináris transzkódolás (ADR 0412 D8).
- **D5 (§0.0-n kívül, csak jegyzet) — a „súlyos account action" hatóköre.**
  A backend ma NEM rendelkezik account-suspension mechanizmussal (mérve:
  nulla találat `suspend`/`ban_user`/`is_banned`-re) — az A7 ezért a média
  SAJÁT `rejected` átmenetére korlátozódik ebben a körben; a human-review-
  gate elve (triage sosem dönt egyedül) egy jövőbeli account-action kör
  számára is kötelező invariáns marad (ADR 0412 D5, Következmények).

Ezek a pontok a brief §3/§5/§8 TARTALMÁT nem változtatják meg — kizárólag
azt rögzítik, MELYIK fájl/mechanizmus valósítja meg, és hol a mért,
stdlib-only/deferred-wiring határ. A §6 acceptance-táblázat és a §6.1
mérce-mátrix változatlan.

## 0. Kör-jelzés és STOP-protokoll

```bash
tools/codex-signal.sh progress "<egy sor>"
tools/codex-signal.sh done "<egy sor>"
tools/codex-signal.sh stopped "<egy sor>"
tools/codex-signal.sh blocked "<egy sor>"
```

Lezáró jelzés nélkül a kör bukott. **Listán kívüli fájl kellene → `stopped`**,
és a kimenet a brief-revízió kérése, nem az `allowed_paths` csendes tágítása.
Meglévő, ma zöld teszt elbukása → `blocked`, nem a teszt átírása.

## 1. Cél

A feltöltött média biztonságos transcode-, metadata-strip- és review-folyamata — pending média nem játszható le, súlyos döntés sosem KIZÁRÓLAG automatikus.

## 2. Jelenlegi állapot — mért tények

- A Kör 18 `media.state` MA egyszerű upload-állapotokat hordoz (uploaded/finalized) — ez a kör bővíti a teljes állapotgéppé
- a projekt MA NEM rendelkezik malware-scan vagy content-moderation adapterrel — ez az ELSŐ ilyen integrációs pont, adapter-mintával

## 3. Scope

**Benne van:** media processing state machine: uploaded, scanning, transcoding, review, ready, rejected, deleted · EXIF/location metaadat eltávolítás; a megőrzött technikai metadata dokumentálva · codec/duration/resolution/frame-rate korlátozás · adapter malware-scan és opcionális content-moderation providerhez · automatikus modell CSAK triage — súlyos account action előtt emberi review kell · post media csak `ready` állapotban renderelhető; pending placeholder · signed playback URL rövid TTL-lel + audience-ellenőrzéssel.

**NINCS benne (tilos):**

- Post-létrehozás vagy komment-logika módosítása.
- Teljes moderation-QUEUE workflow — Kör 27 (itt csak a media-specifikus review-lépés).
- `docs/adr/**` — az ADR 0412-t a Claude írja.

## 4. Engedélyezett fájlok

| Útvonal | Indok |
|---|---|
| `backend/app/community/tasks/media_processing.py` | ÚJ |
| `backend/app/community/services/media_access_service.py` | ÚJ |
| `backend/app/community/moderation/media_moderation.py` | ÚJ |
| `backend/app/community/models/media.py` | MÓDOSÍTOTT — **kizárólag additív** (§0.0 D2): ÚJ `processing_state` oszlop + konstansok + A6-audit nullable oszlopok (decision/confidence/provider/provider_version/moderated_at). Az `upload_state` oszlop, értékkészlete, indexei, tranzíciói VÁLTOZATLANOK |
| `backend/alembic/versions/e09_r19_0013_community_media_state.py` | ÚJ |
| `lib/features/community/presentation/widgets/community_media_player.dart` | ÚJ |
| `backend/tests/community/test_media_processing.py` | ÚJ — a §6 cellái |
| `test/features/community/presentation/community_media_player_test.dart` | ÚJ |

**Tilos zóna:** `backend/app/community/services/media_upload_service.py` · `backend/app/community/storage/object_store.py` · `backend/app/community/policies/access_policy.py` (READ-ONLY import megengedett) · `lib/features/community/domain/**` · `docs/adr/**` · `tools/**` · `.github/**`

## 5. Kötött architekturális döntések (ADR 0412)

### 5.1 Súlyos account action SOSEM kizárólag automatikus modell döntése

Az automatikus content-moderation triage-ot végez és confidence-et ad, de a végleges, súlyos döntés (ebben a körben: a média `rejected` állapotba állítása — a backend MA nem rendelkezik account-suspension mechanizmussal, §0.0 D5) emberi review-t igényel — kivéve dokumentált, sürgős technikai spam-containment esetet.

**NEM elfogadható gyengítés:** egy automatikus modell közvetlen `rejected` döntése emberi review nélkül "mert a confidence magas" — ez a §18.4 SDD-invariáns közvetlen megsértése. (Egy jövőbeli account-action kör ugyanezt az elvet öröklés útján, nem újratárgyalással veszi át.)

### 5.2 Nem `ready` média SOSEM játszható le közvetlen URL-lel

A playback URL csak `ready` állapotú médiára generálódik, és audience-ellenőrzött, rövid TTL-lel.

### 5.3 Pontos helymetaadat NEM marad a publikált médiában

Az EXIF/GPS-metaadat eltávolítása a feldolgozási pipeline kötelező, meg nem kerülhető lépése.

## 6. Acceptance criteria

| # | Kritérium | Bizonyíték |
|---|---|---|
| A1 | EXIF/location metaadat eltávolítva a fixture-mérésben | `test_media_processing.py` |
| A2 | Pending média nem játszható le | `community_media_player_test.dart` |
| A3 | Rejected állapotú média nem renderelhető posztban | `test_media_processing.py` |
| A4 | Playback audience-ellenőrzött (blocked/non-visible user nem kap URL-t) | `test_media_processing.py` |
| A5 | Lejárt signed playback URL elutasított | `test_media_processing.py` |
| A6 | A moderation döntés és a provider-verzió auditált | `test_media_processing.py` |
| A7 | Súlyos account action nem kizárólag automatikus döntés alapján történik | `test_media_processing.py` — human-review gate teszt |

### 6.1 Mérce-mátrix — melyik hibás implementációt melyik cella fogja pirosra

| Hibás implementáció | Melyik cella vált PIROSRA |
|---|---|
| Az EXIF-strip lépés kihagyható vagy megkerülhető | A1 |
| A player pending médiát is lejátszik placeholderrel egyidejűleg | A2 |
| A playback URL nem ellenőrzi az audience-t | A4 |
| A lejárt URL továbbra is működik | A5 |
| Az automatikus modell közvetlenül `rejected`-be állítja a médiát (a `review` state és a human-decision függvény megkerülésével) | A7 |

**Valódi-sértés próba (KÖTELEZŐ, §10-ben dokumentálva):** kapcsold ki az emberi review-kényszert a súlyos action-ágon (a triage-eredmény közvetlenül hívja a `rejected` átmenetet a `resolve_review`/human-decision függvény megkerülésével), futtasd a backend pytest-et magas-confidence triage-gel → az **A7** cellának PIROSNAK kell lennie → állítsd vissza.

## 7. Kötelező ellenőrzések

```bash
tools/round-gate.sh test/features/community/presentation/community_media_player_test.dart
```

A backend oldal külön, önálló parancs (NEM láncolva):

```bash
cd backend && python -m pytest tests/community/test_media_processing.py -q
```

A gate artefaktum a mérce (`tools/round-gate.sh`) — a parancssorban
reprodukált parancslista NEM bizonyíték (AGENTS.md §12, L09). A script
`format` → `analyze` → `test <minden útvonal külön>` → `architecture`
lépéseket KÜLÖN processzként futtat, csonkítatlan kimenettel. **Tilos**
bármilyen szűrés vagy kézi lánc a promptban (OOM, L05). A kötelező gate-et
**TILOS háttérbe küldeni** (`run_in_background`) — az egy-fordulós harness a
forduló végén megöli, mielőtt eredmény érkezne (L183/L254). CI-dispatch, PR és
merge mindig Claude-oldal: az implementer `gh`-t NEM hív.

## 8. Implementációs sorrend

1. `models/media.py` — ÚJ `processing_state` oszlop + konstansok + A6-audit nullable oszlopok, additív (§0.0 D2); `upload_state` érintetlen. A migráció (`e09_r19_0013…`) ezt tükrözi, `down_revision = "e09_r18_0012"`.
2. `media_processing.py` — EXIF/location strip (stdlib-only, a fixture formátumra, §0.0 D8), codec/duration/resolution kliens-deklaráció validáció (§0.0 D8) — tiszta, session+sor-paraméteres függvények, `media_upload_service.py`-t NEM hívja meg semmi automatikusan (§0.0 D3).
3. A malware-scan és content-moderation adapter-interfész (mock implementációval erre a körre, `ObjectStore` ABC + fake mintáját követve).
4. `media_moderation.py` — triage-only automatika (`review`-ba irányít, sosem `rejected`-be), human-review-gate súlyos akcióhoz (§0.0 D5).
5. `media_access_service.py` — önálló HMAC-SHA256 aláírt playback token (nem `ObjectStore`, §0.0 D6), rövid TTL, `policies/access_policy.py` audience-ellenőrzés újrafelhasználásával (§0.0 D7, READ-ONLY import).
6. `community_media_player.dart` — pending placeholder, ready lejátszás.
7. A valódi-sértés próba §10-be; a §7 mindkét parancsa KÜLÖN futtatva.

## 9. Kockázatok

- **A kizárólag automatikus súlyos döntés.** Ez a legkomolyabb biztonsági/etikai kockázat ebben a körben (A7).
- **A megkerülhető EXIF-strip.** Egy elfelejtett formátum-ág (pl. HEIC) helyadatot szivárogtathat (A1).
- **A pending média lejátszhatósága.** Egy feldolgozatlan, esetleg sértő tartalom idő előtt látszódna (A2).

## 10. Implementation handoff — az implementer tölti ki

## 11. Review — a Claude tölti ki
