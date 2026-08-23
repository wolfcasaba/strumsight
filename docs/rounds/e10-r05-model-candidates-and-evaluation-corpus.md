# E10-R05 — Modelljelöltek és bilingual evaluation corpus

- **Státusz:** PREPARED (előre megírva 2026-08-22, kód olvasva: `main @ 194b48c4`)
- **Típus:** Chapter 11 (Epic 10 — Offline AI), Kör 5
- **Kör-azonosító:** `E10-R05`
- **Branch:** `<motor>/e10-r05-model-candidates-and-evaluation-corpus`
- **Előfeltétel:** `E10-R04` merge-elve
- **Brief szerzője:** Claude (Opus 5)
- **Előre kiosztott ADR:** nincs — a kör csak konfigurációt és corpus-adatot szállít, végleges modellválasztás nélkül.

**Visszakeresett előzmény:** `node tools/knowledge-rag.mjs --corpus lessons,halts,adr --top 5 "bilingual evaluation corpus schema safety severity"` → nincs releváns előzmény (a találatok más domain hibaosztályai) — ez a kör a projekt ELSŐ ilyen jellegű infrastruktúrája, a §5/§9 saját tervezésére támaszkodik.

> ⚠ **Pre-flight (indítás előtt KÖTELEZŐ):** olvasd újra a `backend/` és `lib/l10n/` meglévő magyar/angol lokalizációs mintáját — a corpus stílusa illeszkedjen a projekt tényleges nyelvi regiszteréhez. Eltérésnél §0.0 brief-revízió.

## 0.0 Hardver/scope-korlát (batch-prep megjegyzés)

Ez a kör **NEM tölt le és NEM futtat valódi modellt** — a `local_ai/configs/candidate_models.yaml` csak METAADATOT (licenc, forrás, várható paraméterosztály) rögzít PLACEHOLDER pinned revisionnel, amit a Kör 6 (bake-off, `hold`) tölt ki valós adattal. A corpus (JSONL) tisztán szöveges adat, nincs benne futtatható kód vagy modell-függés — teljesen software-only, git-be commitolható méret.

```ai-router
schema_version = 1
risk = "normal"
allowed_paths = [
  "local_ai/configs/candidate_models.yaml",
  "local_ai/evaluation/corpus/offline_tutor_eval.hu.jsonl",
  "local_ai/evaluation/corpus/offline_tutor_eval.en.jsonl",
  "local_ai/evaluation/rubrics/human_review_rubric.md",
  "local_ai/tests/test_corpus_schema.py",
  "docs/rounds/e10-r05-model-candidates-and-evaluation-corpus.md",
]
gate_tests = [
  "test/app/config/feature_flags_test.dart",
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

Verziózott, review-olható magyar/angol evaluation corpus és human-review rubrika, ami a KÉSŐBBI (valós, `hold`-on lévő) modellválasztást fogja mérni. Ez a kör NEM választ győztest, és nem futtat semmilyen modellt.

## 2. Jelenlegi állapot — mért tények

- `local_ai/` **nem létezik** — ez az első kör, ami ezt a könyvtárfát megnyitja.
- A projekt MA két nyelven lokalizál (`lib/l10n/app_en.arb`, `app_hu.arb`) — a corpus stílusát ehhez a regiszterhez kell igazítani, nem formális/gépi fordítás-szagú szöveghez.
- `backend/` Python teszt-konvenciója (`pytest`, `ruff`) — a `local_ai/tests/` ugyanezt a mintát követi, DE külön `local_ai/requirements-lock.txt` alatt fut majd (Kör 29), EBBEN a körben elég a puszta JSON-séma-validáció, ami a rendszer Python3-ával is futtatható (nincs új dependency).

## 3. Scope

**Benne van:** compact és standard modellkategória PLACEHOLDER konfiguráció (`candidate_models.yaml`, pinned revision mezőkkel, de MEGJELÖLVE "TBD — Kör 6 bake-off tölti ki") · legalább 150, magyar/angol kiegyensúlyozott evaluation eset · kategóriák: debrief, RAG, tool, safety, insufficient evidence, prompt injection, pedagógiai · minden esethez expected behavior, forbidden claim, required citation/tool, severity · human review rubrika (helyesség, grounding, tömörség, pedagógia, nyelvi természetesség, safety) · séma-validáló teszt.

**NINCS benne (tilos):**

- Valódi modell letöltése, futtatása vagy kiválasztása.
- Szerzői jogvédett dalszöveg vagy tab a corpusban.
- `docs/adr/**`, `tools/**`, `.github/**`, `android/**`.

## 4. Engedélyezett fájlok

| Útvonal | Indok |
|---|---|
| `local_ai/configs/candidate_models.yaml` | ÚJ — PLACEHOLDER modellkategória-konfiguráció |
| `local_ai/evaluation/corpus/offline_tutor_eval.hu.jsonl` | ÚJ — magyar eval corpus |
| `local_ai/evaluation/corpus/offline_tutor_eval.en.jsonl` | ÚJ — angol eval corpus |
| `local_ai/evaluation/rubrics/human_review_rubric.md` | ÚJ — human review rubrika |
| `local_ai/tests/test_corpus_schema.py` | ÚJ — a §6 cellái |

**Tilos zóna:** `local_ai/export/**`, `local_ai/benchmark/**` (más körök) · `lib/**` · `android/**` · `docs/adr/**` · `tools/**` · `.github/**`

## 5. Kötött architekturális döntések

### 5.1 Nincs ÚJ kötött döntés — adat- és konfigurációs kör

**NEM elfogadható gyengítés:** a `candidate_models.yaml`-ban egy KONKRÉT, végleges modellnév "ideiglenes jelölésként" való rögzítése úgy, hogy egy KÉSŐBBI kör (pl. UI-szöveg) már erre a névre hivatkozik — a modellnév a bake-off (Kör 6/7) előtt MINDIG "TBD" vagy explicit placeholder marad.

## 6. Acceptance criteria

| # | Kritérium | Bizonyíték |
|---|---|---|
| A1 | A corpus mindkét nyelven legalább 150 egyedi, ütközésmentes case ID-t tartalmaz | `test_corpus_schema.py` |
| A2 | Minden eset tartalmazza a kötelező mezőket (expected behavior, forbidden claim, severity) | `test_corpus_schema.py` |
| A3 | A hu/en corpus kategória-eloszlása kiegyensúlyozott (egyik kategória sem hiányzik egyik nyelvből) | `test_corpus_schema.py` |
| A4 | Minden kritikus safety eset `severity: critical`-lel jelölt | `test_corpus_schema.py` |
| A5 | Nincs szerzői jogvédett hosszú dalszöveg/tab a corpusban (kézi review + kulcsszó-heurisztika) | review — dokumentum-audit |

### 6.1 Mérce-mátrix — melyik hibás implementációt melyik cella fogja pirosra

| Hibás implementáció | Melyik cella vált PIROSRA |
|---|---|
| A corpus 150 alatti esetszámmal áll meg valamelyik nyelven | A1 |
| Egy eset hiányzik a `severity` mezőt | A2 |
| A `prompt injection` kategória csak angolul szerepel | A3 |
| Egy fájdalom/sérülés eset `severity: low`-ként van jelölve | A4 |

## 7. Kötelező ellenőrzések

```bash
python3 -m pytest local_ai/tests/test_corpus_schema.py -q
```

Ez a kör NEM érinti a Flutter/Dart kódot, ezért a `tools/round-gate.sh` Dart-lépései nem relevánsak — a fenti Python-teszt önmagában a mérce. CI-dispatch, PR és merge mindig Claude-oldal: az implementer `gh`-t NEM hív.

## 8. Implementációs sorrend

1. `candidate_models.yaml` — compact/standard kategória, PLACEHOLDER mezőkkel.
2. A corpus séma (case ID, kategória, nyelv, expected behavior, forbidden claim, citation/tool, severity).
3. 150+ magyar eset, 150+ angol eset, kategóriánként kiegyensúlyozva.
4. `human_review_rubric.md`.
5. `test_corpus_schema.py` — séma- és kiegyensúlyozottság-validáció.

## 9. Kockázatok

- **A corpus torzított kategória-eloszlása.** Ha egy kategória (pl. prompt injection) alulreprezentált, a Kör 26 minőségi kapuja vak foltot hagyna (A3).
- **Szerzői jogi kockázat.** Egy véletlenül bemásolt teljes dalszöveg jogi kockázatot hozna — a review-nak explicit ellenőriznie kell (A5).
- **A placeholder-modellnév "megszilárdulása".** Ha egy implementer a placeholder nevet véglegesként kezdi kezelni, a Kör 6/7 valós döntése ütközne vele.

## 10. Implementation handoff — az implementer tölti ki

## 11. Review — a Claude tölti ki
