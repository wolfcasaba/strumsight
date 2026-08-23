# E10-R21 — Prompt assembly és injection boundary

- **Státusz:** PREPARED (előre megírva 2026-08-22, kód olvasva: `main @ 194b48c4`)
- **Típus:** Chapter 11 (Epic 10 — Offline AI), Kör 21
- **Kör-azonosító:** `E10-R21`
- **Branch:** `<motor>/e10-r21-prompt-assembly-and-injection-boundary`
- **Előfeltétel:** `E10-R20` merge-elve
- **Brief szerzője:** Claude (Opus 5)
- **Előre kiosztott ADR:** `ADR 0435` — a szám FOGLALT (Epic 10 batch-tartomány, driftre számítva).

**Visszakeresett előzmény:** `node tools/knowledge-rag.mjs --corpus lessons,halts,adr --top 5 "prompt injection trust boundary user text system policy"` → **ADR 0141 (AI Tutor prompt-építés, output-schema és injection boundary) — közvetlen precedens, lásd a §0.0 pre-flight.**

> ⚠ **Pre-flight (indítás előtt KÖTELEZŐ):** olvasd újra a `docs/adr/0141-ai-tutor-prompt-output-schema-injection-boundary.md` (Chapter 5, MEGLÉVŐ) tartalmát — ez a kör a MEGLÉVŐ trust-boundary ELVET alkalmazza a helyi, model-specifikus template-re, nem talál ki új elvet. Eltérésnél §0.0 brief-revízió.

## 0.0 Pre-flight kiegészítés

**A projektben MÁR VAN egy elfogadott prompt-injection-boundary ADR** Chapter 5-ből (`0141-ai-tutor-prompt-output-schema-injection-boundary.md`) — ez a kör NEM írja felül vagy dupla ellenőrzi ugyanazt a cloud-oldali logikát, hanem a HELYI, model-specifikus chat-template-re (Kör 15) fordítja le UGYANAZT az elvet: trusted system/tool/knowledge/evidence vs. untrusted user szekció-elkülönítés, most már a helyi tokenizer delimiterjeivel.

```ai-router
schema_version = 1
risk = "high"
allowed_paths = [
  "lib/features/offline_ai/application/local_prompt_assembler.dart",
  "lib/features/offline_ai/data/prompt_package_repository.dart",
  "local_ai/evaluation/corpus/prompt_injection.hu.jsonl",
  "local_ai/evaluation/corpus/prompt_injection.en.jsonl",
  "test/features/offline_ai/application/local_prompt_assembler_test.dart",
  "docs/rounds/e10-r21-prompt-assembly-and-injection-boundary.md",
]
gate_tests = [
  "test/features/offline_ai/application/local_prompt_assembler_test.dart",
]
native_gate = false
```

**Kockázat = high, indoklás:** egyik `allowed_paths` sem egyezik szó szerint a `high_risk_path_fragments` listával, de a kör a legkritikusabb biztonsági határ egyike: ha a felhasználói szöveg bekerülhet a trusted system/tool szekcióba, a modell megkerülhető biztonsági korlátokat "hihetne el" a felhasználótól.

## 0. Kör-jelzés és STOP-protokoll

```bash
tools/codex-signal.sh progress "<egy sor>"
tools/codex-signal.sh done "<egy sor>"
tools/codex-signal.sh stopped "<egy sor>"
tools/codex-signal.sh blocked "<egy sor>"
```

## 1. Cél

A helyi prompt ugyanazokat a trust-határokat használja, mint a cloud tutor (ADR 0141), model-specifikus chat-template-be fordítva — a felhasználói szöveg SOSEM interpolálódhat trusted mezőbe.

## 2. Jelenlegi állapot — mért tények

- Az ADR 0141 (Chapter 5) MÁR rögzíti a cloud-oldali trust-boundary elvet — ez a kör a HELYI oldalra fordítja.
- A Kör 15 chat-template-je adja a model-specifikus delimitereket — ez a kör ezekre épít.
- A Kör 16 context budgeter és a Kör 20 hibrid retrieval szállítja a bemeneti komponenseket (safety, evidence, knowledge, user message) — ez a kör ÖSSZEÁLLÍTJA ezeket egy végleges prompt-stringgé.

## 3. Scope

**Benne van:** trusted system/tool/knowledge/evidence és untrusted user szekciók implementálása · delimiter és escaping, model-template-specifikusan, parity-tesztelve · felhasználói szöveg SOSEM interpolálódik tool-schema vagy system-policy mezőbe · verziózott, package-compatibility-hez kötött prompt package · magyar/angol injection corpus teszt · modell output NEM módosíthatja a prompt package-et vagy safety configot · safe debug prompt-structure nézet, redaktált tartalommal.

**NINCS benne (tilos):**

- A cloud-oldali (ADR 0141) prompt assembler módosítása.
- `docs/adr/**` — az ADR 0435-öt a Claude írja.

## 4. Engedélyezett fájlok

| Útvonal | Indok |
|---|---|
| `lib/features/offline_ai/application/local_prompt_assembler.dart` | ÚJ — a helyi prompt-összeállító |
| `lib/features/offline_ai/data/prompt_package_repository.dart` | ÚJ — a verziózott prompt package |
| `local_ai/evaluation/corpus/prompt_injection.hu.jsonl` | ÚJ — magyar injection corpus |
| `local_ai/evaluation/corpus/prompt_injection.en.jsonl` | ÚJ — angol injection corpus |
| `test/features/offline_ai/application/local_prompt_assembler_test.dart` | a §6 cellái |

**Tilos zóna:** a cloud-oldali (Chapter 5) prompt-assembler fájlok · `docs/adr/**` · `tools/**` · `.github/**`

## 5. Kötött architekturális döntések (ADR 0435)

### 5.1 A felhasználói szöveg SOSEM interpolálódhat trusted mezőbe — strukturálisan, nem csak szövegi escaping-gel

A delimiter/escaping séma úgy épül fel, hogy a felhasználói szöveg egy KÜLÖN, dedikált szekcióba kerül, amit a modell chat-template-je NEM azonosít system/tool résznek — ez STRUKTURÁLIS garancia, nem csak egy karakter-escaping heurisztika.

**NEM elfogadható gyengítés:** kizárólag string-escaping (pl. idézőjel-kódolás) alkalmazása strukturális szekció-elkülönítés helyett — egy elég kreatív injection-kísérlet megkerülhetné a puszta escaping-et, de nem a strukturális elkülönítést.

### 5.2 A modell output SOSEM módosíthatja a prompt package-et vagy a safety configot

## 6. Acceptance criteria

| # | Kritérium | Bizonyíték |
|---|---|---|
| A1 | A delimiter/escaping a KIVÁLASZTOTT model-template szerint parity-tesztelt | `local_prompt_assembler_test.dart` |
| A2 | "Ignore previous instructions" típusú felhasználói szöveg NEM kerül trusted szekcióba | `local_prompt_assembler_test.dart` — corpus |
| A3 | Hamis tool-schema a felhasználói szövegben NEM értelmeződik valós tool-schemaként | `local_prompt_assembler_test.dart` — corpus |
| A4 | Tudásbázisból (retrieval) érkező injection-kísérlet (mérgezett chunk) NEM emel jogosultságot | `local_prompt_assembler_test.dart` — corpus |
| A5 | Magyar és angol injection corpus mindkettő lefedett, egyik sem "csak angol tesztelt" | `local_prompt_assembler_test.dart` |
| A6 | Prompt-package-verzió mismatch explicit hibát ad | `local_prompt_assembler_test.dart` |
| A7 | A debug prompt-structure nézet redaktált (nincs benne a nyers felhasználói szöveg) | `local_prompt_assembler_test.dart` |

### 6.1 Mérce-mátrix — melyik hibás implementációt melyik cella fogja pirosra

| Hibás implementáció | Melyik cella vált PIROSRA |
|---|---|
| A felhasználói szöveget egyszerű string-concat illeszti a system prompt mellé, delimiter nélkül | A2 (a corpus injection-kísérlete "átcsúszik") |
| A tool-schema validáció a felhasználói szövegből is elfogad JSON-t | A3 |
| A retrieval-chunk tartalma nincs elkülönítve a system policytól | A4 |
| A debug nézet a teljes nyers promptot (user szöveggel) kiírja | A7 |

**Valódi-sértés próba (KÖTELEZŐ, §10-ben dokumentálva):** cseréld a strukturális szekció-elkülönítést egyszerű string-concat-ra, futtasd az injection corpus tesztet → legalább egy **A2/A3/A4** cellának PIROSNAK kell lennie → állítsd vissza.

## 7. Kötelező ellenőrzések

```bash
tools/round-gate.sh test/features/offline_ai/application/local_prompt_assembler_test.dart
```

## 8. Implementációs sorrend

1. A magyar/angol injection corpus (legalább 30-30 eset, ADR 0141 mintájára).
2. `prompt_package_repository.dart` — verziózott prompt package, compatibility-check.
3. `local_prompt_assembler.dart` — strukturális szekció-elkülönítés, model-template delimiterekkel.
4. A debug redaktált nézet.
5. A valódi-sértés próba §10-be.

## 9. Kockázatok

- **A puszta string-escaping csapdája.** Egy implementer könnyen "elég jónak" gondolhat egy karakter-szintű escaping-et, ami valójában nem strukturális védelem (5.1, A2-A4).
- **A retrieval-chunk mint injection-vektor.** Ha egy tudásbázis-chunk tartalma (elméletileg jóváhagyott, de mégis kompromittált) ugyanolyan súlyt kap, mint a system policy, az megkerülné a határt (A4).
- **A debug-nézet szivárgása.** Ha a redaktált nézet mégis tartalmazza a nyers user-szöveget, az sértené a §22 observability-tiltást (A7).

## 10. Implementation handoff — az implementer tölti ki

## 11. Review — a Claude tölti ki
