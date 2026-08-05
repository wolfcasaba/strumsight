# E05-R28 — Persistence, privacy control és törlés

- **Státusz:** PREPARED (előre megírva 2026-08-05, kód olvasva: main @ `5d082dc`)
- **SDD-kör:** [`docs/sdd/06-epic-05-computer-vision.md`](../sdd/06-epic-05-computer-vision.md) Kör 28; §28
- **Branch:** `codex/e05-r28-vision-persistence-privacy-and-deletion`
- **Előfeltétel:** **E05-R10, E05-R22, E05-R24 merge**
- **Brief szerzője:** Claude (batch) · **Implementáció:** Codex (Terra)

```ai-router
schema_version = 1
risk = "high"
allowed_paths = [
  "lib/features/vision/data/persistence/vision_session_repository.dart",
  "lib/features/vision/data/persistence/vision_session_codec.dart",
  "lib/features/vision/data/persistence/vision_export.dart",
  "lib/features/vision/domain/vision_privacy_control.dart",
  "lib/features/vision/public.dart",
  "lib/core/storage/storage_keys.dart",
  "lib/features/settings/screens/vision_privacy_screen.dart",
  "lib/l10n/app_en.arb",
  "lib/l10n/app_hu.arb",
  "test/features/vision/data/vision_session_repository_test.dart",
  "test/features/vision/data/vision_export_privacy_test.dart",
  "test/features/settings/vision_privacy_screen_test.dart",
  "test/app/offline_network_guard_test.dart",
  "docs/rounds/e05-r28-vision-persistence-privacy-and-deletion.md",
]
gate_tests = [
  "test/features/vision",
  "test/features/settings",
  "test/app/offline_network_guard_test.dart",
]
native_gate = false
```

> ⚠ **Pre-flight (KÖTELEZŐ):** `origin/main` + E05-R10/R22/R24 merge; olvasd újra
> `lib/core/storage/storage_migrator.dart` karantén-mintáját, az R10 kalibrációs
> repository-t (ugyanaz a minta) és a `test/app/offline_network_guard_test.dart`
> mai alakját. Nincs ÚJ ADR (0161/0166 végrehajtása). PREPARED→PLANNING,
> brief commit az implementer indítása ELŐTT.

## 0. Kör-jelzés és STOP-protokoll

```bash
tools/codex-signal.sh progress "<egy sor>" ; tools/codex-signal.sh done "<egy sor>"
tools/codex-signal.sh stopped "<egy sor>" ; tools/codex-signal.sh blocked "<egy sor>"
```

Lezáró jelzés nélkül a kör bukott. Listán kívüli fájl → `stopped`.

## 0.0 Tervezési baseline és pre-flight revízió

**PREPARED.** Nincs előre kiosztott ADR.

## 1. Cél

Verziózott `VisionSessionResult` tárolás **raw média nélkül**, és **teljes
felhasználói kontroll**: privacy panel, egy-session és teljes törlés, export.

## 2. Jelenlegi állapot (mért, `5d082dc` + megelőző körök)

- Az R10 kalibrációs repository már ezt a mintát használja (verziózott envelope,
  idempotens migráció, record-szintű karantén) — ez a kör **ugyanazt** követi.
- Az R24 `VisionSessionResult`-ja létezik, de **nem** perzisztált.
- A `test/app/offline_network_guard_test.dart` a meglévő őre annak, hogy a
  detektálás nem generál hálózati forgalmat.
- A Settings ma `lib/features/settings/screens/` alatt tart képernyőket.

## 3. Scope

**Benne:** `VisionSessionRepository` + codec + schema migration, mentendő
adatkör (aggregátum, insight, capability, quality, model-verzió), **teljes
landmark-idősor NEM** mentődik alapból, Settings privacy panel (vision history,
kalibráció, Lab data), egy-session és **delete-all**, JSON export **kép nélkül**,
record-szintű karantén, és a nulla-hálózat bizonyítéka.

**Kívül — TILOS:** raw frame/kép mentése bármilyen formában, cloud-szinkron,
új hálózati útvonal, a tutor/analysis adapterek módosítása.

## 4. Engedélyezett fájlok

| Útvonal | Állapot | Miért |
|---|---|---|
| `.../data/persistence/vision_session_repository.dart` | ÚJ | verziózott tár |
| `.../data/persistence/vision_session_codec.dart` | ÚJ | JSON round-trip |
| `.../data/persistence/vision_export.dart` | ÚJ | export kép nélkül |
| `.../domain/vision_privacy_control.dart` | ÚJ | törlés/retenció szabályok |
| `lib/features/vision/public.dart` | meglévő | additív export |
| `lib/core/storage/storage_keys.dart` | meglévő | **csak új** `ss.vision.*` kulcs |
| `lib/features/settings/screens/vision_privacy_screen.dart` | ÚJ | privacy panel |
| `lib/l10n/app_*.arb` | meglévő | **csak additív** kulcs |
| `test/features/*`, `test/app/offline_network_guard_test.dart` | ÚJ/meglévő | tesztek |
| `docs/rounds/e05-r28-*.md` | meglévő | §10 handoff |

**Tilos zóna:** minden más; meglévő storage-kulcs átírása; `backend/`.
Listán kívül → `stopped`.

## 5. Kötött architekturális döntések

1. **Raw média soha nem perzisztálódik** (ADR 0166) — sem kép, sem videó, sem
   base64 blob, sem „debug dump". **NEM elfogadható** flag mögötti kivétel a
   consumer útvonalon; a Lab capture (explicit consent) **külön**,
   `visionLabCaptureEnabled` mögötti, és **nem e kör tárgya**.
2. **Teljes landmark-idősor alapból nincs mentve.** Ha egy jövőbeli kör
   opcionálisan engedélyezi, az külön flag + külön consent — **NEM elfogadható**
   itt bevezetni „csak a fejlesztéshez".
3. **A törlés tényleges:** a delete-all után a store-ban **nincs** vision
   rekord, és ezt a teszt a nyers store tartalmán ellenőrzi (nem a repository
   API-ján át). **NEM elfogadható:** „töröltnek jelölt" rekord.
4. **Record-szintű karantén:** egy sérült rekord nem teheti olvashatatlanná a
   historyt.
5. **Nulla hálózat:** a vision használata és a persistence **egyetlen** hálózati
   kérést sem generál (account/cloud kikapcsolt állapotban sem — és bekapcsolt
   account mellett sem küld vision adatot).
6. **Export = ugyanaz a minimalizált halmaz**, mint a tárolt adat, plusz a
   séma-verzió; a privacy-snapshot teszt mindkettőre fut.

## 6. Acceptance criteria

- [ ] **Round-trip + migrációs mátrix** (v0 / vN-1 / vN / vN+1) az R10 mintája
      szerint, idempotens migrációval.
- [ ] **Privacy-snapshot teszt (a kör kulcsbizonyítéka):** a tárolt és az
      exportált JSON kulcskészlete rögzített halmazzal egyezik; kép/landmark/
      arc-gyanús kulcs esetén PIROS.
- [ ] **Delete-mátrix:** egy session törlése / delete-all / törlés sérült
      rekord mellett — mindhárom után a **nyers store** tartalma ellenőrizve.
- [ ] **Karantén-teszt:** csonka rekord → csak az érintett karanténba, a többi
      olvasható.
- [ ] **Network-spy teszt:** a teljes vision-út (session → persistence → export)
      **nulla** hálózati kérés; a meglévő offline-guard bővítve.
- [ ] **Privacy panel widget-teszt:** a törlés destruktív megerősítést kér, és
      a megerősítés nélkül **nem** hív törlést (hívásszámláló 0).
- [ ] **Lokalizációs paritás** zöld.
- [ ] **Valódi-sértés próba (§10):** egy landmark-idősor mező felvétele a
      codecbe → a privacy-snapshot teszt PIROS → visszaállítás.

## 7. Kötelező ellenőrzések

```bash
tools/round-gate.sh test/features/vision test/features/settings test/app/offline_network_guard_test.dart
```

Külön processzek, nincs `&&`/pipe/`tail`. CI-dispatch/PR/merge = orchestrátor.

## 8. Implementációs sorrend

1. RED: privacy-snapshot + delete-mátrix + network-spy.
2. Codec + repository + migráció + karantén.
3. Export.
4. Privacy panel + ARB; gate.

## 9. Kockázatok

- **A „csak fejlesztéshez" landmark-dump** — a legvalószínűbb privacy-szivárgás;
  a snapshot-teszt az egyetlen gépi őr.
- **A törlés csak logikai** (soft delete) — a nyers store ellenőrzése ezt fogja meg.

**STOP:** raw média mentése, soft delete vagy hálózati út bevezetése helyett
dokumentált brief-revízió.

## 10. Implementation handoff — az implementer tölti ki

_(üres)_

## 11. Review — a független reviewer tölti ki

Tervezett review: `docs/reviews/e05-r28-vision-persistence-privacy-and-deletion-review.md`.
Merge csak exact-SHA zöld CI, §4-en belüli diff és nulla OPEN BLOCKER/MAJOR után.

> **Reviewer figyelem:** privacy-kritikus kör (ADR 0161/0166) — a
> `security-reviewer` ágens bevonása KÖTELEZŐ.
