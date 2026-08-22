# E09-R19 — Média feldolgozás, privacy és moderation state

- **Státusz:** PREPARED (előre megírva 2026-08-22, kód olvasva: `main @ db6293f4`)
- **Típus:** Chapter 10 (Epic 9 — Community Platform), Kör 19
- **Kör-azonosító:** `E09-R19`
- **Branch:** `<motor>/e09-r19-media-processing-privacy-and-moderation-state`
- **Előfeltétel:** `E09-R18` merge-elve
- **Brief szerzője:** Claude (Opus 5)
- **Előre kiosztott ADR:** `ADR 0408` — a szám FOGLALT (Epic 9 batch-tartomány 0395-0419). Az ADR-t a Claude írja meg a kör indítási pre-flightjában a §5 döntéseiből; az implementer a `docs/adr/`-t NEM érinti (TILOS zóna).

> ⚠ **Pre-flight (indítás előtt KÖTELEZŐ):** olvasd újra a Kör 18 `media` tábla TÉNYLEGES `state` mezőjét és értékkészletét — ez a kör bővíti állapotgéppé, nem cseréli le. Eltérésnél
> §0.0 brief-revízió, NEM csendes lista-tágítás.

```ai-router
schema_version = 1
risk = "high"
allowed_paths = [
  "backend/app/community/tasks/media_processing.py",
  "backend/app/community/services/media_access_service.py",
  "backend/app/community/moderation/media_moderation.py",
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
- `docs/adr/**` — az ADR 0408-at a Claude írja.

## 4. Engedélyezett fájlok

| Útvonal | Indok |
|---|---|
| `backend/app/community/tasks/media_processing.py` | ÚJ |
| `backend/app/community/services/media_access_service.py` | ÚJ |
| `backend/app/community/moderation/media_moderation.py` | ÚJ |
| `backend/alembic/versions/e09_r19_0013_community_media_state.py` | ÚJ |
| `lib/features/community/presentation/widgets/community_media_player.dart` | ÚJ |
| `backend/tests/community/test_media_processing.py` | ÚJ — a §6 cellái |
| `test/features/community/presentation/community_media_player_test.dart` | ÚJ |

**Tilos zóna:** `backend/app/community/models/media.py` (bővítés indokolt, nem átírás) · `lib/features/community/domain/**` · `docs/adr/**` · `tools/**` · `.github/**`

## 5. Kötött architekturális döntések (ADR 0408)

### 5.1 Súlyos account action SOSEM kizárólag automatikus modell döntése

Az automatikus content-moderation triage-ot végez és confidence-et ad, de a végleges, súlyos (removal/suspension szintű) döntés emberi review-t igényel — kivéve dokumentált, sürgős technikai spam-containment esetet.

**NEM elfogadható gyengítés:** egy automatikus modell közvetlen `rejected`/account-suspend döntése emberi review nélkül "mert a confidence magas" — ez a §18.4 SDD-invariáns közvetlen megsértése.

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
| Az automatikus modell közvetlenül suspend-eli az accountot | A7 |

**Valódi-sértés próba (KÖTELEZŐ, §10-ben dokumentálva):** kapcsold ki az emberi review-kényszert a súlyos action-ágon, futtasd a backend pytest-et magas-confidence triage-gel → az **A7** cellának PIROSNAK kell lennie → állítsd vissza.

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

1. Az állapotgép bővítése: uploaded → scanning → transcoding → review → ready | rejected | deleted.
2. `media_processing.py` — EXIF/location strip, codec/duration/resolution validáció.
3. A malware-scan és content-moderation adapter-interfész (mock implementációval erre a körre).
4. `media_moderation.py` — triage-only automatika, human-review-gate súlyos akcióhoz.
5. `media_access_service.py` — signed playback URL, rövid TTL, audience-ellenőrzés.
6. `community_media_player.dart` — pending placeholder, ready lejátszás.
7. A valódi-sértés próba §10-be; a §7 mindkét parancsa KÜLÖN futtatva.

## 9. Kockázatok

- **A kizárólag automatikus súlyos döntés.** Ez a legkomolyabb biztonsági/etikai kockázat ebben a körben (A7).
- **A megkerülhető EXIF-strip.** Egy elfelejtett formátum-ág (pl. HEIC) helyadatot szivárogtathat (A1).
- **A pending média lejátszhatósága.** Egy feldolgozatlan, esetleg sértő tartalom idő előtt látszódna (A2).

## 10. Implementation handoff — az implementer tölti ki

## 11. Review — a Claude tölti ki
