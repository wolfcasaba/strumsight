# E05-R02 — Camera technology döntési kapu és mérési runbook

- **Státusz:** PREPARED (előre megírva 2026-08-05, kód olvasva: main @ `5d082dc`)
- **SDD-kör:** [`docs/sdd/06-epic-05-computer-vision.md`](../sdd/06-epic-05-computer-vision.md) Kör 2; §11
- **Branch:** `codex/e05-r02-camera-technology-decision`
- **Előfeltétel:** **E05-R01 merge**
- **Brief szerzője:** Claude (batch) · **Implementáció:** Codex (Terra)

```ai-router
schema_version = 1
risk = "high"
allowed_paths = [
  "docs/adr/0167-vision-camera-capture-stack.md",
  "docs/baseline/epic-05-camera-stack-evaluation.md",
  "docs/manual-testing/vision-camera-spike-runbook.md",
  "docs/manual-testing/vision-device-matrix.md",
  "docs/rounds/e05-r02-camera-technology-decision.md",
]
gate_tests = [
  "test/tooling",
]
native_gate = false
```

> ⚠ **Pre-flight (KÖTELEZŐ):** `origin/main` + **E05-R01 merge**; olvasd újra az
> ADR 0163-at (Android-first) és a `pubspec.yaml` mai plugin-készletét.
> **ADR 0167** előre kiosztva — ütközéskor a blokk tolása (lásd E05-R01 §5).
> PREPARED→PLANNING, brief commit az implementer indítása ELŐTT.

## 0. Kör-jelzés és STOP-protokoll

```bash
tools/codex-signal.sh progress "<egy sor>" ; tools/codex-signal.sh done "<egy sor>"
tools/codex-signal.sh stopped "<egy sor>" ; tools/codex-signal.sh blocked "<egy sor>"
```

Lezáró jelzés nélkül a kör bukott. Listán kívüli fájl → `stopped`.

## 0.0 Tervezési baseline és pre-flight revízió

**PREPARED.** Előre kiosztott ADR: **0167**.

## 1. Cél

Eldönteni **dokumentált érvek és a repó mért korlátai alapján**, hogy a capture
réteg a hivatalos Flutter `camera` plugin (CameraX-backed) mögé kerül-e, vagy
saját platform channel kell. A döntés kimenete: **ADR 0167 + egy futtatható
mérési runbook**, amit a valós eszközön az ember (vagy egy későbbi eszközös kör)
lefuttat, és amely a döntést **megdöntheti**.

## 2. Jelenlegi állapot (mért, `5d082dc`)

- **Ezen a boxon nincs Android SDK és nincs kamerás eszköz** — a Kör 2 SDD-beli
  „mérj két Android eszközön" feladata a pipeline-ban **nem végrehajtható**.
  A `flutter build apk` a CI-ben fut (`.github/workflows/build-apk.yml`).
- A repó plugin-készlete `audio_streamer`, `permission_handler`, `audioplayers`,
  `wakelock_plus`, `flutter_secure_storage` (v10, **win32 ^6** — ONE win32
  major, CLAUDE.md build gotcha), `file_selector`, `share_plus`.
- Nincs `camera*` függőség; a döntés **ebben a körben nem is adja hozzá**
  (a `pubspec.yaml` a tilos zónában van — a plugin az E05-R06-ban kerül be).

## 3. Scope

**Benne:** a három jelölt (hivatalos `camera` plugin · CameraX-alapú saját
platform channel · hibrid: plugin preview + saját analysis stream) írásos
összevetése a §5 kritériumtáblája szerint; **ADR 0167** a választott úttal és a
megdöntési feltételekkel; a `vision-camera-spike-runbook.md` — parancsonként
reprodukálható, valós eszközön futtatandó mérési lista; a device-mátrix
bővítése a runbook `PENDING` soraival.

**Kívül — TILOS:** `pubspec.yaml`, bármely `lib/`, `android/`, `ios/` fájl,
spike-kód merge-elése, DSP, model-asset.

## 4. Engedélyezett fájlok

| Útvonal | Állapot | Miért |
|---|---|---|
| `docs/adr/0167-vision-camera-capture-stack.md` | ÚJ | a döntés |
| `docs/baseline/epic-05-camera-stack-evaluation.md` | ÚJ | kritériumtábla + érvek |
| `docs/manual-testing/vision-camera-spike-runbook.md` | ÚJ | valós eszközös mérési lista |
| `docs/manual-testing/vision-device-matrix.md` | E05-R01-ből | PENDING sorok |
| `docs/rounds/e05-r02-*.md` | meglévő | §10 handoff |

**Tilos zóna:** minden más. Listán kívül → `stopped`.

## 5. Kötött architekturális döntések

1. **A kiértékelés kritériumai kötöttek** (a baseline táblájának oszlopai):
   init idő · frame FPS · pixel formátum (YUV_420_888 elérhető-e) · rotation
   metadata · buffer-copyk száma · close idő · front mirror · portrait/landscape
   váltás · pause/resume · **frame timestamp monotonic-e** · karbantartottság
   és licenc · win32-ütközés kockázata. Minden cellához **forrás** kell
   (hivatalos dokumentáció-hivatkozás vagy „MÉRENDŐ eszközön").
2. **Default döntés (a runbook megdöntheti):** hivatalos `camera` plugin
   (Androidon CameraX-backed) — a saját platform channel csak akkor indokolt,
   ha a runbook a **latest-frame backpressure** vagy a **monotonic timestamp**
   követelményt megbukottnak méri. Ezt az ADR-ben *feltételes döntésként* kell
   megfogalmazni, a megdöntési küszöbökkel együtt.
   **NEM elfogadható:** „majd kiderül" típusú nyitva hagyás, vagy olyan ADR,
   amely nem mondja meg, MELYIK mért szám vezet a másik ághoz.
3. **A `CameraFrame` ownership-modellje a döntéstől független** — a contractot
   az E05-R03 írja; ez a kör csak azt rögzíti, hogy a választott stack
   **latest-frame** (nem queue) szemantikát tud, vagy hogy az adapternek kell
   megvalósítania.
4. **A runbook artefaktum, nem próza:** minden sora egy futtatható parancs vagy
   egy megfigyelendő, **számmal** kifejezett érték (nem „stabilnak tűnik").

## 6. Acceptance criteria

- [ ] A kritériumtábla mind a 3 jelöltre × mind a 12 kritériumra kitöltött;
      minden „MÉRENDŐ" cella megjelenik a runbookban is (kereszthivatkozás).
- [ ] Az ADR 0167 tartalmaz **numerikus megdöntési küszöböt** legalább háromra:
      init idő, tartós FPS, close utáni resource-felszabadulás.
- [ ] A runbook tartalmazza a **20× preview start/stop**, a background/foreground
      és a memory-snapshot lépést, és mindegyikhez a `PASS` feltételt számmal.
- [ ] A device-mátrixba **PENDING** sorként bekerül minden runbook-mérés.
- [ ] `git diff --stat` egyetlen `lib/`, `test/`, `android/`, `ios/`,
      `pubspec.yaml` fájlt sem érint.

## 7. Kötelező ellenőrzések

```bash
tools/round-gate.sh test/tooling
```

Külön processzek, nincs `&&`/pipe/`tail`. CI-dispatch/PR/merge = orchestrátor.

## 8. Implementációs sorrend

1. Kritériumtábla + források.
2. Runbook (számmal kifejezett PASS-feltételekkel).
3. ADR 0167 a feltételes döntéssel.
4. Device-mátrix PENDING sorok; gate.

## 9. Kockázatok

- **A döntés mérés nélkül születik.** Ez tudatos: a valós mérés a runbookban
  van, és az ADR feltételes. Ellenszer: a megdöntési küszöbök számszerűek.
- **A spike-kód bekerül a `main`-be.** Tiltva: a `pubspec.yaml` és a `lib/` a
  tilos zónában van; a plugin az E05-R06 dolga.

**STOP:** ha a kör csak úgy lenne teljesíthető, hogy plugint ad hozzá vagy
kódot ír — dokumentált brief-revízió.

## 10. Implementation handoff — az implementer tölti ki

_(üres)_

## 11. Review — a független reviewer tölti ki

Tervezett review: `docs/reviews/e05-r02-camera-technology-decision-review.md`.
Merge csak exact-SHA zöld CI, §4-en belüli diff és nulla OPEN BLOCKER/MAJOR után.
