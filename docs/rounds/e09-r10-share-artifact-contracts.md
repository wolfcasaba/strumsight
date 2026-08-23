# E09-R10 — Share artifact szerződések

- **Státusz:** PREPARED (előre megírva 2026-08-22, kód olvasva: `main @ db6293f4`)
- **Típus:** Chapter 10 (Epic 9 — Community Platform), Kör 10
- **Kör-azonosító:** `E09-R10`
- **Branch:** `<motor>/e09-r10-share-artifact-contracts`
- **Előfeltétel:** `E09-R09` merge-elve
- **Brief szerzője:** Claude (Opus 5)
- **Előre kiosztott ADR:** ~~`ADR 0402`~~ → **`ADR 0404`** (ld. §0.0 — a `0402` időközben a Kör 8-é lett). Az ADR-t a Claude írja meg a kör indítási pre-flightjában a §5 döntéseiből; az implementer a `docs/adr/`-t NEM érinti (TILOS zóna).

## 0.0 Pre-flight brief-revízió (Claude, 2026-08-23)

**D1 — ADR-szám korrekció.** A fenti `0402` a brief megírásakor (2026-08-22)
volt szabad; időközben a Kör 8 (`E09-R08`) foglalta le
(`docs/adr/0402-block-mute-and-safety-relationships.md`). A
`tools/round-slots.py reserve-adr --round E09-R10` friss számot adott:
**`0404`** (a `0403` egy másik, még nem indult kör előjegyzett foglalása). A
§5 alábbi "(ADR 0402)" hivatkozásait és a ténylegesen megírt ADR-fájlt
`0404` alatt kell érteni: [`docs/adr/0404-share-artifact-contracts.md`](../adr/0404-share-artifact-contracts.md).

**D2 — A négy mapper és a hét artifact-altípus leképezése rögzítve** (ADR
0404 D1): `song_share_mapper.dart` HÁROM altípust ad (song result, original
progression, plan template), mind a `songs/public.dart` `Song` típusából,
külön factory-metódusokkal egy fájlban; `achievement_share_mapper.dart` KETTŐT
(achievement + challenge), mind a `gamification/public.dart`-ból. Nincs
ötödik mapper-fájl.

**D3 — `analysis_share_mapper.dart` forrása `audio_analysis/public.dart`
(NEM `analyze/public.dart`).** Ez két különböző feature: az `analyze` az
eredeti klip-szintű chord/strum DSP-detektor (ezt fogyasztja a
`strum_card.dart` `AnalyzeResult`-ja), az `audio_analysis` a V2, gazdagabb
elemzés-feature `AnalysisComparison`/`AnalysisTrend` típusokkal (ADR 0247
export-szerződése). Az "analysis improvement" szemantikája (két mérés közti
javulás) az `audio_analysis` comparison/trend típusaihoz illik. A pre-flight
által hivatkozott `strum_card.dart`/`wrapped_card.dart` a "minimalizált
nézet" PÉLDÁJA (mennyi/milyen adat biztonságos exportálni), nem a mapperek
tényleges bemeneti típusa.

**D4 — A challenge-artifact hitelesség-mezője a `LedgerEntrySyncStatus`
(NEM az `EvidenceTrust`).** `lib/features/gamification/data/sync/
gamification_sync_contract.dart:28` — `enum LedgerEntrySyncStatus {
unverified, verified }`, a `SyncReceipt.status` mezőn, E08-R28/ADR 0394-ben
bevezetve. Az `EvidenceTrust` (`domain/activity/evidence_trust.dart`) egy
MÁSIK, öt fokozatú aktivitás-bizonyíték tengely — nem ez a brief §5.3
"verified/unverified reward-státusza".

**Visszakeresés (ADR 0312, §4.9):**
`node tools/knowledge-rag.mjs --corpus lessons,halts,adr --top 5 "share artifact schema minimal export community"`
→ [ADR 0247](../adr/0247-analysis-export-share-and-delete-contract.md)
(Analysis export/share/delete szerződés — allowlist-alapú, verziózott JSON,
nyers audio/device-id/belső diagnosztika alapból kizárva — közvetlen
precedens a D2/A5 minimalizáltsági mércéhez) és
[ADR 0118](../adr/0118-native-json-exchange-contract.md) (natív JSON
csereboríték: `formatVersion` a boríték verziója, KÜLÖNBÖZIK a
`document.schemaVersion`-től — ez a kör EGY schemaVersion-t visz
artifact-onként, a kétszintű verziózás itt nem indokolt, mert az artifact
maga a legkülső boríték). Releváns halt/lecke a szűkített lekérdezésen nem
került elő (`--corpus lessons,halts --top 5 "discriminated union pydantic
unknown schema version reject"` → 0 releváns találat; a discriminated-union
minta ÚJ ebben a backendben, `grep -rln "Discriminator\|discriminator="
backend/app/` → 0 találat).

> ⚠ **Pre-flight (indítás előtt KÖTELEZŐ):** olvasd újra a `lib/features/share/widgets/{strum_card,wrapped_card}.dart` TÉNYLEGES modelljét és a gamifikáció verified/unverified reward-státusz szerződését (E08-R28) — az artifact ezekre a MEGLÉVŐ, minimalizált nézetekre épül, nem a belső repository-objektumokra. Eltérésnél
> §0.0 brief-revízió, NEM csendes lista-tágítás.

```ai-router
schema_version = 1
risk = "high"
allowed_paths = [
  "lib/features/community/domain/entities/share_artifact.dart",
  "lib/features/community/application/mappers/practice_share_mapper.dart",
  "lib/features/community/application/mappers/song_share_mapper.dart",
  "lib/features/community/application/mappers/analysis_share_mapper.dart",
  "lib/features/community/application/mappers/achievement_share_mapper.dart",
  "backend/app/community/schemas/artifacts.py",
  "docs/contracts/community-share-artifacts.md",
  "test/features/community/application/share_artifact_test.dart",
  "backend/tests/community/test_share_artifact_schema.py",
  "docs/rounds/e09-r10-share-artifact-contracts.md",
]
gate_tests = [
  "test/features/community/application/share_artifact_test.dart"
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

Minimalizált, verziózott Community export a Practice, Song, Analysis, Tutor, Vision és Gamification eredményekhez — nyers audio, video, waveform, landmark és belső score debug NÉLKÜL.

## 2. Jelenlegi állapot — mért tények

- `lib/features/share/` MA `strum_card.dart` és `wrapped_card.dart` widgetet ad — ezek a RENDERELŐ réteg, nem az artifact-adatmodell
- A gamifikáció (E08-R28) MA `verified`/`unverified` reward-státuszt különböztet meg — a challenge-artifact ezt a MEGLÉVŐ megkülönböztetést használja, nem talál ki újat
- A Kör 5 domain MA hordozza a `CommunityPost`/`content_id` value objecteket, de artifact-típus még nincs

## 3. Scope

**Benne van:** külön artifact típus: practice summary, song result, analysis improvement, achievement, challenge, plan template, original progression · minden forrás-feature saját mapperrel exportál a Community contractba · schema version, content hash, source ID minden artifacton · backend Pydantic discriminated union validáció · share preview modell field-level kapcsolókkal · backward compatibility / deprecation szabályok dokumentálva.

**NINCS benne (tilos):**

- Bármely forrás-feature (`practice`, `songs`, `audio_analysis`, `gamification` stb.) belső fájljának importálása — csak a saját `public.dart`-jukon át.
- Poszt-létrehozás vagy feed — Kör 11+.
- `docs/adr/**` — az ADR 0402-t a Claude írja.

## 4. Engedélyezett fájlok

| Útvonal | Indok |
|---|---|
| `lib/features/community/domain/entities/share_artifact.dart` | ÚJ — sealed artifact hierarchia |
| `lib/features/community/application/mappers/practice_share_mapper.dart` | ÚJ |
| `lib/features/community/application/mappers/song_share_mapper.dart` | ÚJ |
| `lib/features/community/application/mappers/analysis_share_mapper.dart` | ÚJ |
| `lib/features/community/application/mappers/achievement_share_mapper.dart` | ÚJ |
| `backend/app/community/schemas/artifacts.py` | ÚJ — Pydantic discriminated union |
| `docs/contracts/community-share-artifacts.md` | ÚJ — a szerződés + deprecation szabályok |
| `test/features/community/application/share_artifact_test.dart` | ÚJ — a §6 cellái |
| `backend/tests/community/test_share_artifact_schema.py` | ÚJ |

**Tilos zóna:** `lib/features/practice/**`, `lib/features/songs/**`, `lib/features/audio_analysis/**`, `lib/features/gamification/**` belső (nem `public.dart`) fájljai · `lib/features/community/presentation/**` · `docs/adr/**` · `tools/**` · `.github/**`

## 5. Kötött architekturális döntések (ADR 0404, ld. §0.0 D1)

### 5.1 Az artifact MINIMÁLIS, immutable és verziózott — sosem a belső repository-objektum

Minden artifact explicit mezőkkel rendelkezik, `schemaVersion`-t hordoz, és a forrás feature `public.dart`-ján keresztül, saját mapperrel készül — a Community sosem importálja a forrás domain belső típusait.

**NEM elfogadható gyengítés:** egy "praktikus" megoldás, ami a forrás feature teljes belső entitását szerializálja az artifactba "hogy semmi ne maradjon ki" — ez pontosan a nyers DSP/audio/landmark szivárgás kockázata.

### 5.2 Ismeretlen vagy manipulált artifact-verzió a szerver ELUTASÍTJA

A Pydantic discriminated union ismeretlen `type`/`schemaVersion` kombinációra hibát ad, nem csendes best-effort parse-olást.

### 5.3 A challenge-artifact a MEGLÉVŐ verified/unverified megkülönböztetést hordozza

A gamifikáció (E08-R28) reward-ledger `verified`/`unverified` állapota közvetlenül leképeződik az artifactba — a Community nem talál ki egy párhuzamos hitelesség-fogalmat.

## 6. Acceptance criteria

| # | Kritérium | Bizonyíték |
|---|---|---|
| A1 | A Community nem importál más feature belső modelljét | `share_artifact_test.dart` + `architecture_dependency_test.dart` |
| A2 | Minden artifact minimális és explicit mezőkkel rendelkezik | `share_artifact_test.dart` — mezőlista mátrix |
| A3 | A szerver elutasít ismeretlen vagy manipulált artifactot | `test_share_artifact_schema.py` |
| A4 | Artifact round-trip (JSON) mind a hét típusra azonosságot ad | `share_artifact_test.dart` |
| A5 | Nyers audio/video/waveform/landmark SOSEM kerül artifactba | `share_artifact_test.dart` — mezőhiány-teszt |
| A6 | Field-level share kapcsolók alapértelmezetten konzervatívak (KI) | `share_artifact_test.dart` |

### 6.1 Mérce-mátrix — melyik hibás implementációt melyik cella fogja pirosra

| Hibás implementáció | Melyik cella vált PIROSRA |
|---|---|
| Egy mapper a forrás feature belső entitását adja tovább közvetlenül | A1/A5 |
| Az artifact tartalmaz egy `rawAudioPath` vagy hasonló belső mezőt | A5 |
| Ismeretlen `schemaVersion` csendben az 1-es verzióként értelmeződik | A3 |
| A field-level kapcsoló alapértéke `true` (pl. audio-clip csatolás) | A6 |
| A JSON round-trip a mezők jelenlétéből következtet típusra, nem discriminatorból | A4 |

**Valódi-sértés próba (KÖTELEZŐ, §10-ben dokumentálva):** vedd ki az ismeretlen `schemaVersion` elutasító ágát a backend discriminated unionból, futtasd a pytest-et → az **A3** cellának PIROSNAK kell lennie → állítsd vissza.

## 7. Kötelező ellenőrzések

```bash
tools/round-gate.sh test/features/community/application/share_artifact_test.dart
```

A backend oldal külön, önálló parancs (NEM láncolva):

```bash
cd backend && python -m pytest tests/community/test_share_artifact_schema.py -q
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

1. `share_artifact.dart` — a sealed hierarchia, hét altípus, `schemaVersion`/`sourceId`/`createdAt`.
2. A négy mapper (practice/song/analysis/achievement) a forrás `public.dart`-okra építve.
3. `artifacts.py` — Pydantic discriminated union, ismeretlen verzió elutasítással.
4. A share-preview modell field-level kapcsolókkal, konzervatív alapértékkel.
5. `docs/contracts/community-share-artifacts.md` — backward-compat + deprecation szabály.
6. A valódi-sértés próba §10-be; a §7 mindkét parancsa KÜLÖN futtatva.

## 9. Kockázatok

- **A belső entitás közvetlen szerializálása.** A leggyorsabb út egy mapper megírásában, de pont ez szivárogtatná a nyers/belső adatot (A1/A5).
- **Az ismeretlen verzió csendes elfogadása.** Egy jövőbeli schema-váltás visszamenőleg hibás artifactokat termelne (A3).
- **A field-level kapcsoló alapértéke.** Egy `true` alapérték a §9.3 SDD-invariánst ("a kapcsolók alapértelmezetten konzervatívak") sértené (A6).

## 10. Implementation handoff — az implementer tölti ki

## 11. Review — a Claude tölti ki
