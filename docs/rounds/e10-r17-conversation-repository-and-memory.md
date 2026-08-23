# E10-R17 — Strukturált tutor memória: retenció, export és local-only garancia

- **Státusz:** PREPARED (előre megírva 2026-08-22, kód olvasva: `main @ 194b48c4`)
- **Típus:** Chapter 11 (Epic 10 — Offline AI), Kör 17
- **Kör-azonosító:** `E10-R17`
- **Branch:** `<motor>/e10-r17-conversation-repository-and-memory`
- **Előfeltétel:** `E10-R16` merge-elve
- **Brief szerzője:** Claude (Opus 5)
- **Előre kiosztott ADR:** `ADR 0431` — a szám FOGLALT (Epic 10 batch-tartomány, driftre számítva).

> ⚠ **Pre-flight (indítás előtt KÖTELEZŐ):** olvasd újra a `lib/features/ai_tutor/data/repositories/local_tutor_conversation_repository.dart` és `local_tutor_memory_repository.dart` TÉNYLEGES, MA MEGLÉVŐ tartalmát. Eltérésnél §0.0 brief-revízió.

**Visszakeresett előzmény:** `node tools/knowledge-rag.mjs --corpus lessons,halts,adr --top 5 "retention limit delete export conversation memory local only"` → **ADR 0134** (AI Tutor memory policy, bm25#2 emb#1) — közvetlen precedens: local-first, megtekinthető, szerkeszthető/törölhető, dokumentált retention. Ez a brief az 5.1/5.2 kötött döntéseit erre a MEGLÉVŐ elvre építi, nem talál ki új memória-policyt.

## 0.0 Pre-flight kiegészítés — a SDD Kör 17 fájllistája ELAVULT

**A `lib/features/ai_tutor/data/local_conversation_repository.dart` és a `TutorMemory`/`local_tutor_memory_repository.dart` MÁR LÉTEZIK** — Chapter 5 kész munkája (`local_tutor_conversation_repository.dart` implementálja a `TutorConversationRepository`-t, `local_tutor_memory_repository.dart` a memóriát). **Ez a kör NEM hozza létre ezeket újra**, és NEM is nyúl hozzájuk közvetlenül (nincsenek `allowed_paths`-on) — a valódi ÚJ munka a retenció-, export- és local-only-policy RÉTEG, ami a MEGLÉVŐ repository-kra épül egy ÚJ, alkalmazás-szintű `tutor_memory_compactor.dart` fájlban.

**Ez lényegesen szűkebb kör, mint a SDD eredeti feladatlistája sugallja** — a §10-ben az implementer kötelezően rögzítse, hogy a repository-k létező kódját GREP-pel ellenőrizte, és a kompaktor a MEGLÉVŐ publikus API-t hívja (nem a belső storage-formátumot).

```ai-router
schema_version = 1
risk = "high"
allowed_paths = [
  "lib/features/offline_ai/application/tutor_memory_compactor.dart",
  "test/features/offline_ai/application/tutor_memory_compactor_test.dart",
  "docs/rounds/e10-r17-conversation-repository-and-memory.md",
]
gate_tests = [
  "test/features/offline_ai/application/tutor_memory_compactor_test.dart",
]
native_gate = false
```

**Kockázat = high, indoklás:** egyik `allowed_paths` sem egyezik szó szerint a `high_risk_path_fragments` listával, de a kör a `privacy` kategóriával azonos kockázatot hordoz: a felhasználó személyes beszélgetés-adatának retenciója, exportja és törlése.

## 0. Kör-jelzés és STOP-protokoll

```bash
tools/codex-signal.sh progress "<egy sor>"
tools/codex-signal.sh done "<egy sor>"
tools/codex-signal.sh stopped "<egy sor>"
tools/codex-signal.sh blocked "<egy sor>"
```

**Ha a §0.0 mérése driftelt** (pl. a repository-k mégsem léteznek, vagy más API-val rendelkeznek), az implementer AZONNAL `stopped`-ot jelez a pontos eltéréssel — ez a kör a MEGLÉVŐ kódra épít, nem tud attól függetlenül dolgozni.

## 1. Cél

A `TutorMemory` retenciója, korlátozása, exportja és törlése legyen felhasználó-kontrollált, a MEGLÉVŐ Chapter 5 repository-kra építve — helyi-only módban nincs sync.

## 2. Jelenlegi állapot — mért tények

- `local_tutor_conversation_repository.dart` és `local_tutor_memory_repository.dart` MÁR LÉTEZNEK — lásd §0.0.
- A `TutorConversation`/`TutorMessage` domain (`lib/features/ai_tutor/domain/models/`) stabil, MA IS használt Chapter 5 munka.
- Az Offline AI feature-nek MA nincs saját conversation-kezelése — helyette a MEGLÉVŐ ai_tutor infrastruktúrát HASZNÁLJA egy vékony alkalmazás-rétegen keresztül.

## 3. Scope

**Benne van:** retention/maximum-conversation-limit policy a MEGLÉVŐ repository publikus API-ján keresztül · export, egyedi conversation delete, delete-all funkció · account-namespace elkülönítés ellenőrzése (nem ez a kör hozza létre, csak VERIFIKÁLJA a meglévő mechanizmust teszttel) · local-only módban nincs conversation sync indítás.

**NINCS benne (tilos):**

- A `local_tutor_conversation_repository.dart`/`local_tutor_memory_repository.dart` MÓDOSÍTÁSA.
- KV-cache binárist vagy hidden reasoningot tároló bármilyen kód.
- `docs/adr/**` — az ADR 0431-et a Claude írja.

## 4. Engedélyezett fájlok

| Útvonal | Indok |
|---|---|
| `lib/features/offline_ai/application/tutor_memory_compactor.dart` | ÚJ — retenció, export, delete-all, a MEGLÉVŐ repository API-n keresztül |
| `test/features/offline_ai/application/tutor_memory_compactor_test.dart` | a §6 cellái |

**Tilos zóna:** `lib/features/ai_tutor/data/repositories/**` (MEGLÉVŐ, nem módosítható) · `lib/features/ai_tutor/domain/**` · `docs/adr/**` · `tools/**` · `.github/**`

## 5. Kötött architekturális döntések (ADR 0431)

### 5.1 Local-only módban SOSEM indul conversation sync

A `tutor_memory_compactor.dart` sosem hív hálózati kódot; ha egy jövőbeli felhő-szinkron réteg épül a beszélgetésre, az EXPLICIT, külön opt-in flaget igényel, amit ez a kör NEM ad meg.

**NEM elfogadható gyengítés:** egy "csak metaadat" háttér-szinkronizáció bevezetése helyi-only módban, akár csak a beszélgetés-számláló szinkronizálására is.

### 5.2 A retenciós limit levágása mindig a LEGRÉGEBBI beszélgetést dobja el, sosem a legutóbbit

## 6. Acceptance criteria

| # | Kritérium | Bizonyíték |
|---|---|---|
| A1 | A retenciós limit fölé kerülő beszélgetés-szám a legrégebbit dobja el, nem a legutóbbit | `tutor_memory_compactor_test.dart` |
| A2 | Export az összes megmaradt beszélgetést és a strukturált memóriát tartalmazza, hidden reasoning nélkül | `tutor_memory_compactor_test.dart` |
| A3 | Delete-all ténylegesen töröl minden conversation és memory rekordot a MEGLÉVŐ repository-n át | `tutor_memory_compactor_test.dart` |
| A4 | Local-only módban a compactor egyetlen hálózati hívást sem indít (transport-spy méri, L140 minta) | `tutor_memory_compactor_test.dart` |
| A5 | Korrupt memória-rekord esetén a compactor kontrolláltan kezel (nem crash, nem adatvesztés a többi rekordon) | `tutor_memory_compactor_test.dart` |

### 6.1 Mérce-mátrix — melyik hibás implementációt melyik cella fogja pirosra

| Hibás implementáció | Melyik cella vált PIROSRA |
|---|---|
| A retenciós vágás a legutóbbi beszélgetést dobja el (LIFO helyett FIFO-hiba) | A1 |
| A delete-all csak a conversation-öket törli, a memóriát nem | A3 |
| A compactor egy "usage ping"-et küld helyi-only módban is | A4 |
| Egy korrupt rekord a teljes export/delete műveletet elhasalja, más rekordokat is elveszítve | A5 |

**Valódi-sértés próba (KÖTELEZŐ, §10-ben dokumentálva):** cseréld fel a retenciós vágás sorrendjét (legutóbbi dobása), futtasd a tesztet → az **A1** cellának PIROSNAK kell lennie → állítsd vissza.

## 7. Kötelező ellenőrzések

```bash
tools/round-gate.sh test/features/offline_ai/application/tutor_memory_compactor_test.dart
```

## 8. Implementációs sorrend

1. Grep-eld ki a MEGLÉVŐ `local_tutor_conversation_repository.dart`/`local_tutor_memory_repository.dart` publikus API-ját — dokumentáld a §10-ben.
2. `tutor_memory_compactor.dart` — retenció (FIFO-vágás), export, delete-all.
3. A hálózat-mentesség transport-spy tesztje.
4. A korrupt-rekord kezelés.
5. A valódi-sértés próba §10-be.

## 9. Kockázatok

- **A meglévő repository API drift.** Ha a §0.0 mérése stale, az implementer vakon dolgozna egy nem létező API-ra — a STOP-protokoll ezt védi.
- **A csendes sync-kísértés.** Egy "csak backup célból" bevezetett háttér-feltöltés a legfontosabb privacy-invariánst sértené (5.1).
- **A FIFO/LIFO felcserélése.** Egy elsőre ártalmatlannak tűnő indexelési hiba a legfrissebb, legrelevánsabb kontextust dobná el (A1).

## 10. Implementation handoff — az implementer tölti ki

## 11. Review — a Claude tölti ki
