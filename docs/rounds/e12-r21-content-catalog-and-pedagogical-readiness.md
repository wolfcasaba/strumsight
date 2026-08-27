# E12-R21 — Content catalog és pedagógiai readiness

- **Státusz:** PREPARED (előre megírva 2026-08-27, kód olvasva: `main @ 9ca4a0dc`)
- **Típus:** Chapter 12 (Release Roadmap, Sprint Planning & Final Integration), Kör 21
- **Kör-azonosító:** `E12-R21`
- **Branch:** `<motor>/e12-r21-content-catalog-and-pedagogical-readiness`
- **Előfeltétel:** `E12-R12` merge-elve (a fixture-manifest mintája adja a tartalom-manifest formáját)
- **Brief szerzője:** Claude (Opus 5)
- **Előre kiosztott ADR:** `ADR 0460` — a szám FOGLALT (Chapter 12 batch-tartomány).

**Visszakeresett előzmény:** `node tools/knowledge-rag.mjs --corpus lessons,halts,adr --top 5 "content catalog exercise reference validation difficulty progression"` → **[ADR 0068](../adr/0068-practice-domain-model-contracts.md)** (score 3.00): Practice V2 domain contractok — validation-as-value, egész százalékok, kanonikus akkord-címkék. A tartalom-validáció ezt a MEGLÉVŐ szerződést használja mérceként, nem definiál másodikat.

> ⚠ **Pre-flight (indítás előtt KÖTELEZŐ):** mérd meg a tartalom TÉNYLEGES forrásait: `lib/features/practice/data/builtin_practice_catalog.dart` (beépített gyakorlat-katalógus), `assets/tutor_knowledge/manifest.json` + `assets/tutor_knowledge/{en,hu}/`, `assets/tutor_prompts/*.json`, és a Practice Generator kimenetének gyakorlat-hivatkozásai. `content/` könyvtár a fán NINCS.

## 0.0 Miért nem `content/catalog/`

A SDD Kör 21 `content/catalog/` fát ír elő. A fán a tartalom MA KÉT helyen él: Dart-beépített katalógusban (`builtin_practice_catalog.dart`) és `assets/tutor_knowledge/` alatt, saját manifesttel (ADR 0135 governance). Egy harmadik, párhuzamos tartalom-fa bevezetése kettős igazságot csinálna. A kör ezért **leltárat és validátort** ad a MEGLÉVŐ két forrásra, nem költöztet tartalmat.

```ai-router
schema_version = 1
risk = "normal"
allowed_paths = [
  "docs/content/catalog-inventory.yaml",
  "docs/content/release-readiness.md",
  "tool/validate_content_catalog.py",
  "test/tooling/content_catalog_test.dart",
  "docs/rounds/e12-r21-content-catalog-and-pedagogical-readiness.md",
]
gate_tests = [
  "test/tooling/content_catalog_test.dart",
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

**STOP-protokoll:** ha a validátor olyan generált gyakorlat-hivatkozást talál, ami nem létező tartalomra mutat, a kimenet a `stopped` jelzés és jelentés — a generátor javítása külön kör.

## 1. Cél

Bizonyítani, hogy minden ajánlott/generált gyakorlat LÉTEZŐ tartalomra mutat, a kezdő tanulási út végigjárható, és minden tartalom-elem verziózott, locale-lefedett.

## 2. Jelenlegi állapot — mért tények

- `lib/features/practice/data/builtin_practice_catalog.dart` — a beépített gyakorlat-katalógus (Dart forrás).
- `assets/tutor_knowledge/manifest.json` + `en`/`hu` alkönyvtárak; `assets/tutor_prompts/` hat prompt-JSON.
- `content/` és `tool/validate_content_catalog.py` **nem létezik**.
- A Practice Generator (`lib/features/practice_generator/`) MA gyakorlat-hivatkozásokat állít elő; a hivatkozások érvényességét folyam-szintű mérce NEM védi.
- `docs/content/` **nem létezik**.

## 3. Scope

**Benne van:** `docs/content/catalog-inventory.yaml` — MINDEN tartalom-elem: azonosító, forrás (Dart-beépített / asset), nehézség, készség-címke, locale-lefedettség, verzió · `tool/validate_content_catalog.py` (a leltár ↔ MÉRT forrás összevetése; hiányzó locale, ismeretlen készség-címke, nem létező hivatkozás → nem-nulla kilépés) · `test/tooling/content_catalog_test.dart` (a generátor-kimenet minden gyakorlat-hivatkozása LÉTEZŐ katalógus-elemre mutat; a kezdő út lépései hézagmentesen egymásra épülnek) · `docs/content/release-readiness.md`.

**NINCS benne (tilos):**

- Tartalom hozzáadása, átírása vagy áthelyezése (`lib/features/practice/data/**`, `assets/**`).
- Új `content/` fa létrehozása.
- A Practice Generator javítása.
- `docs/adr/**` — az ADR 0460-at a Claude írja.

## 4. Engedélyezett fájlok

| Útvonal | Indok |
|---|---|
| `docs/content/catalog-inventory.yaml` | ÚJ — a tartalom-leltár |
| `docs/content/release-readiness.md` | ÚJ — a pedagógiai readiness riport |
| `tool/validate_content_catalog.py` | ÚJ — a validátor |
| `test/tooling/content_catalog_test.dart` | a §6 cellái |

**Tilos zóna:** `lib/**` · `assets/**` · `docs/adr/**` · `.github/**` · `tools/**`

## 5. Kötött architekturális döntések (ADR 0460)

### 5.1 A leltár TÜKÖR, nem forrás

A tartalom forrása marad a Dart-katalógus és az asset-manifest; a leltár ezekből generálódik/ellenőrződik. **NEM elfogadható gyengítés:** a leltár „kanonikussá" tétele és a kód-oldali katalógus onnan való feltöltése — az a kettős igazság.

### 5.2 A törött hivatkozás BLOKKOL

Egy generált terv, ami nem létező gyakorlatra mutat, a felhasználónak üres képernyő. **NEM elfogadható gyengítés:** figyelmeztetés-szintre sorolás.

### 5.3 A locale-lefedettség mindkét nyelvre kötelező

A GA-scope tartalomnak `en` ÉS `hu` változata is kell. **NEM elfogadható gyengítés:** „a magyar majd később" — a kivétel csak a `known-exceptions` úton, ownerrel és lejárattal élhet.

## 6. Acceptance criteria

| # | Kritérium | Bizonyíték |
|---|---|---|
| A1 | A leltár MINDEN mért tartalom-elemet tartalmaz (a validátor a forrásból indul) | `content_catalog_test.dart` |
| A2 | A generátor-kimenet minden gyakorlat-hivatkozása LÉTEZŐ elemre mutat | `content_catalog_test.dart` |
| A3 | Hiányzó `hu` (vagy `en`) változat → nem-nulla kilépés | `content_catalog_test.dart` |
| A4 | A kezdő tanulási út lépései hézagmentesen egymásra épülnek (nincs zsákutca) | `content_catalog_test.dart` progresszió-cellája |
| A5 | Ismeretlen készség-címke → nem-nulla kilépés | `content_catalog_test.dart` |
| A6 | A kör egyetlen tartalom-fájlt sem módosít | `git diff --stat` a §4 listán |

### 6.1 Mérce-mátrix — melyik hibás implementációt melyik cella fogja pirosra

| Hibás implementáció | Melyik cella vált PIROSRA |
|---|---|
| A validátor a leltárból indul, nem a forrásból (új gyakorlat láthatatlan) | A1 |
| A hivatkozás-ellenőrzés csak formátumot néz, létezést nem | A2 |
| A locale-ellenőrzés csak az `en` ágat követeli | A3 |
| A progresszió-cella csak a nehézség monotonitását nézi, a készség-előfeltételt nem | A4 |

**Valódi-sértés próba (KÖTELEZŐ, a §10-ben dokumentálva):** vedd ki a leltárból egy létező gyakorlat bejegyzését, futtasd a §7 gate-et → az **A1** cellának PIROSNAK kell lennie → állítsd vissza.

## 7. Kötelező ellenőrzések

```bash
tools/round-gate.sh test/tooling/content_catalog_test.dart
```

A validátor közvetlen futtatása (kimenet a §10-be):

```bash
python3 tool/validate_content_catalog.py --inventory docs/content/catalog-inventory.yaml
```

## 8. Implementációs sorrend

1. A MÉRÉS: a két tartalom-forrás tényleges elemei.
2. `docs/content/catalog-inventory.yaml`.
3. `tool/validate_content_catalog.py`.
4. `test/tooling/content_catalog_test.dart` — az A2/A4 cellák a generátor kimenetén.
5. `docs/content/release-readiness.md` + a valódi-sértés próba a §10-be.

## 9. Kockázatok

- **Harmadik tartalom-fa.** A `content/` bevezetése kettős igazságot csinálna (§5.1).
- **Törött generátor-hivatkozás.** Ha a MÉRÉS ilyet talál, az `stopped` — de a lelet önmagában is a kör értéke (A2).
- **Locale-hiány elfedése.** A „majd később" kivétel nyilvántartás nélkül GA-blokkolót rejt el (A3).

## 10. Implementation handoff — az implementer tölti ki

## 11. Review — a Claude tölti ki
