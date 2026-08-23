# E10-R31 — Offline AI settings, model manager és accessibility UI

- **Státusz:** PREPARED (előre megírva 2026-08-22, kód olvasva: `main @ 194b48c4`)
- **Típus:** Chapter 11 (Epic 10 — Offline AI), Kör 31
- **Kör-azonosító:** `E10-R31`
- **Branch:** `<motor>/e10-r31-offline-ai-settings-and-model-manager-ui`
- **Előfeltétel:** `E10-R30` merge-elve (UI-oldalon a Kör 9/10/24 FAKE providereket használ, lásd §0.0)
- **Brief szerzője:** Claude (Opus 5)
- **Előre kiosztott ADR:** nincs — tisztán UI-réteg, nincs új architekturális kényszer.

**Visszakeresett előzmény:** `node tools/knowledge-rag.mjs --corpus lessons,halts,adr --top 5 "settings model manager accessibility localization segmented arb"` → **ADR 0307 §4 (l10n szegmentáció) — közvetlen precedens, lásd az 5.1 kötött döntés.**

> ⚠ **Pre-flight (indítás előtt KÖTELEZŐ):** olvasd újra a projekt MEGLÉVŐ settings-képernyő mintáját (`lib/features/settings/`) és a Kör 24 `execution_origin_badge.dart`-ot — a stílus illeszkedjen. Eltérésnél §0.0 brief-revízió.

## 0.0 Hardver/scope-korlát — miért PENDING

Ez a kör Flutter-oldali UI, ami a Kör 9/10/24 (letöltés/aktiválás/routing) MÁR MEGLÉVŐ, tesztelt providereire épül — a widget-tesztek Riverpod `ProviderScope` override-okkal FAKE availability/download állapotokat szimulálnak (a projekt bevett mintája, pl. Epic 8/9 UI-köreiben). Nem igényel valódi eszközt vagy natív buildet.

```ai-router
schema_version = 1
risk = "normal"
allowed_paths = [
  "lib/features/offline_ai/presentation/screens/offline_ai_settings_screen.dart",
  "lib/features/offline_ai/presentation/screens/model_manager_screen.dart",
  "lib/features/offline_ai/presentation/widgets/",
  "lib/l10n/features/offline_ai_en.arb",
  "lib/l10n/features/offline_ai_hu.arb",
  "test/features/offline_ai/presentation/",
  "docs/rounds/e10-r31-offline-ai-settings-and-model-manager-ui.md",
]
gate_tests = [
  "test/features/offline_ai/presentation/",
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

## 1. Cél

A felhasználó érthetően kezelhesse a helyi AI-t, a modellt, a tárhelyet, a módot és az adatot — teljes accessibility- és lokalizáció-lefedettséggel.

## 2. Jelenlegi állapot — mért tények

- `lib/l10n/features/` a szegmentált ARB-minta (E08-R27/ADR 0307 §4 óta bevett) — az ÚJ Offline AI stringek IDE kerülnek, NEM a generált `app_{en,hu}.arb`-ba.
- A Kör 24 `execution_origin_badge.dart` a UI-mintát adja az origin-jelzéshez — ez a kör újrahasználja.

## 3. Scope

**Benne van:** Offline AI settings képernyő availability/mode state-ekkel · modellméret/verzió/channel/nyelv/device-tier/várható-profil megjelenítés · download progress/pause/resume/cancel/verify/activate/rollback/delete flow · model package és knowledge package storage KÜLÖN megjelenítve · first-run compatibility + privacy explanation flow · local/cloud/deterministic origin badge (Kör 24 újrahasznosítása) · conversation/memory delete + diagnostics export kontroll (Kör 17 hívása) · 200% text/screen-reader/Stop-gomb/reduced-motion/kontraszt accessibility · teljes hu/en lokalizáció.

**NINCS benne (tilos):**

- Valódi letöltés/aktiválás natív végrehajtása — a widget-tesztek FAKE providerrel futnak.
- `docs/adr/**`, `tools/**`, `.github/**`, `android/**`.

## 4. Engedélyezett fájlok

| Útvonal | Indok |
|---|---|
| `lib/features/offline_ai/presentation/screens/offline_ai_settings_screen.dart` | ÚJ |
| `lib/features/offline_ai/presentation/screens/model_manager_screen.dart` | ÚJ |
| `lib/features/offline_ai/presentation/widgets/` | ÚJ — progress/state widgetek |
| `lib/l10n/features/offline_ai_en.arb` | ÚJ — angol lokalizáció (szegmentált) |
| `lib/l10n/features/offline_ai_hu.arb` | ÚJ — magyar lokalizáció (szegmentált) |
| `test/features/offline_ai/presentation/` | a §6 cellái |

**Tilos zóna:** `lib/l10n/app_{en,hu}.arb` (a generált aggregátum, kézzel NEM szerkeszthető) · `lib/features/settings/**` (más feature, csak mintaként nézi) · `docs/adr/**` · `tools/**` · `.github/**`

## 5. Kötött architekturális döntések

### 5.1 Nincs ÚJ kötött döntés — az l10n-szegmentáció és az accessibility-minta a MEGLÉVŐ ADR 0307 §4 alkalmazása

**NEM elfogadható gyengítés:** az ÚJ stringek felvétele a generált `app_{en,hu}.arb`-ba "gyorsabb lenne" — ugyanaz a hibaosztály, amit az ADR 0307 §4 már kizárt, és amit korábbi köröknek (E08-R20/R22) mid-round javítania kellett.

## 6. Acceptance criteria

| # | Kritérium | Bizonyíték |
|---|---|---|
| A1 | Minden `LocalAiAvailability` állapot (disabled/unsupported/installable/downloading/verifying/ready/incompatible/corrupted/updateAvailable/temporarilyUnavailable) saját, érthető UI-állapotot kap | `test/features/offline_ai/presentation/` |
| A2 | Download controls (pause/resume/cancel) helyesen kötöttek a Kör 9 controllerhez | ugyanott |
| A3 | Delete megerősítést kér, és csak unload után engedélyezett (Kör 10 policy tiszteletben tartva) | ugyanott |
| A4 | Rollback UI-ból elérhető és működik (fake providerrel) | ugyanott |
| A5 | 200% text scale mellett nincs adatvesztés/levágás | ugyanott — golden/semantics teszt |
| A6 | Screen-reader semantics minden interaktív elemre jelen van | ugyanott |
| A7 | Angol/magyar lokalizáció parity teszt zöld | l10n parity gate (`tools/round-gate.sh` beépített lépése) |
| A8 | Reduced-motion módban nincs pulzáló animáció | ugyanott |

### 6.1 Mérce-mátrix — melyik hibás implementációt melyik cella fogja pirosra

| Hibás implementáció | Melyik cella vált PIROSRA |
|---|---|
| A delete gomb unload nélkül is aktiválható a UI-n | A3 |
| Egy `LocalAiAvailability` állapothoz nincs dedikált UI-ág (default/fallback szöveg jelenik meg) | A1 |
| Az új stringek a generált `app_en.arb`-ba kerülnek a szegmentált fájl helyett | A7 (l10n aggregate freshness ellenőrzés elakad) |
| Egy "AI gondolkodik" animáció reduced-motion módban is pulzál | A8 |

**Valódi-sértés próba (KÖTELEZŐ, §10-ben dokumentálva):** engedd a delete gombot unload nélkül is aktívra, futtasd a tesztet → az **A3** cellának PIROSNAK kell lennie → állítsd vissza.

## 7. Kötelező ellenőrzések

```bash
tools/round-gate.sh test/features/offline_ai/presentation
```

## 8. Implementációs sorrend

1. `offline_ai_settings_screen.dart` — mode/availability state, első futás flow.
2. `model_manager_screen.dart` — download/activate/rollback/delete.
3. Az origin badge és a memory/diagnostics kontroll bekötése (Kör 17/24 hívása).
4. Accessibility (200%, screen-reader, reduced-motion) + szegmentált ARB.
5. A valódi-sértés próba §10-be.

## 9. Kockázatok

- **Az l10n-szegmentáció megsértése.** Ismételten mért hibaosztály korábbi köröknél (E08-R20/R22) — itt előre elkerülve (5.1).
- **A delete-unload sorrend megkerülése.** Adatvesztést vagy inkonzisztens állapotot okozna (A3).
- **Az accessibility-hiányosság.** 200% text scale vagy screen-reader hiánya kizárná a felhasználók egy részét (A5/A6).

## 10. Implementation handoff — az implementer tölti ki

## 11. Review — a Claude tölti ki
