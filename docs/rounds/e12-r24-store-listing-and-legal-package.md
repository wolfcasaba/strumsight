# E12-R24 — Store listing, privacy és legal package

- **Státusz:** PREPARED (előre megírva 2026-08-27, kód olvasva: `main @ 9ca4a0dc`)
- **Típus:** Chapter 12 (Release Roadmap, Sprint Planning & Final Integration), Kör 24
- **Kör-azonosító:** `E12-R24`
- **Branch:** `<motor>/e12-r24-store-listing-and-legal-package`
- **Előfeltétel:** `E12-R17` merge-elve (a data safety nyilatkozat FORRÁSA a data-inventory)
- **Brief szerzője:** Claude (Opus 5)
- **Előre kiosztott ADR:** nincs — a kör dokumentum-csomagot állít elő; a hivatkozott szerződéseket korábbi ADR-ek rögzítik.

**Visszakeresett előzmény:** `node tools/knowledge-rag.mjs --corpus lessons,halts,adr --top 5 "store listing privacy policy data safety permission rationale deletion"` → **[ADR 0247](../adr/0247-analysis-export-share-and-delete-contract.md)** (export/share/delete szerződés — a törlési út MÉRT szerződése) és **[ADR 0378](../adr/0378-achievement-presentation-and-privacy-safe-evidence.md)**. A store-nyilatkozat ezekre hivatkozik, nem újat ígér.

> ⚠ **Pre-flight (indítás előtt KÖTELEZŐ):** olvasd ki az `android/app/src/main/AndroidManifest.xml` TÉNYLEGESEN kért engedélyeit és a `docs/privacy/data-inventory.yaml` (Kör 17) mezőit. A store-csomag minden állítása EBBŐL a két forrásból következzen — nem a marketing-szándékból.

## 0.0 A kör felelősségi határa

A store-fiók, a tényleges feltöltés és a jogi felülvizsgálat EMBERI (user-) lépés. A kör terméke a döntéshez szükséges, ellentmondás-mentes DOKUMENTUM-csomag és annak gépi ellenőrzése (minden engedélyhez indoklás, minden data-safety kategóriához leltár-fedezet, minden hivatkozott URL/route létezik).

```ai-router
schema_version = 1
risk = "normal"
allowed_paths = [
  "docs/store/listing.md",
  "docs/store/permissions-rationale.md",
  "docs/store/data-safety.yaml",
  "docs/legal/privacy-policy-draft.md",
  "docs/legal/community-guidelines-draft.md",
  "test/tooling/store_package_test.dart",
  "docs/rounds/e12-r24-store-listing-and-legal-package.md",
]
gate_tests = [
  "test/tooling/store_package_test.dart",
  "test/tooling/data_inventory_test.dart",
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

**STOP-protokoll:** ha a manifest olyan engedélyt kér, amire nincs a fán MÉRHETŐ funkció, a kimenet a `stopped` jelzés — az engedély eltávolítása vagy indoklása külön döntés.

## 1. Cél

A store-metaadat, az adatbiztonsági nyilatkozat és a jogi dokumentumok legyenek a TÉNYLEGES adatkezeléssel konzisztensek, túlzó AI- vagy tanulási ígéret nélkül.

## 2. Jelenlegi állapot — mért tények

- `docs/store/` és `docs/legal/` **nem létezik**.
- A `docs/privacy/data-inventory.yaml` a Kör 17 után létezik — ez a data-safety nyilatkozat egyetlen forrása.
- A törlési/exportálási út szerződése ADR 0247-ben rögzített; a fiók-törlés backend-oldali útja a `backend/app/routers/auth.py` felelőssége.
- A publikus store-jelenlét MA nincs (Kör 1 release-history audit).

## 3. Scope

**Benne van:** `docs/store/listing.md` (leírás, képernyőkép-terv, kategória, korhatár-megfontolás) · `docs/store/permissions-rationale.md` (MINDEN, a manifestben kért engedélyhez: melyik funkció, milyen adat, opcionális-e) · `docs/store/data-safety.yaml` (a data-inventory kategóriáira leképezve, gépileg összevethető alakban) · `docs/legal/privacy-policy-draft.md` és `community-guidelines-draft.md` (TERVEZET jelöléssel — a jogi felülvizsgálat emberi lépés) · `test/tooling/store_package_test.dart` (a fenti konzisztencia gépi ellenőrzése).

**NINCS benne (tilos):**

- `android/**` engedély-módosítás.
- Store-feltöltés vagy fiók-művelet.
- Olyan képesség-ígéret, amit a fán MÉRT állapot nem támogat (pl. „valós idejű AI-tanár", ha az Offline AI sáv `hold`-on áll).
- `docs/adr/**`.

## 4. Engedélyezett fájlok

| Útvonal | Indok |
|---|---|
| `docs/store/listing.md` | ÚJ — store-metaadat |
| `docs/store/permissions-rationale.md` | ÚJ — engedély-indoklások |
| `docs/store/data-safety.yaml` | ÚJ — gépileg ellenőrizhető nyilatkozat |
| `docs/legal/privacy-policy-draft.md` | ÚJ — adatkezelési tájékoztató tervezet |
| `docs/legal/community-guidelines-draft.md` | ÚJ — közösségi irányelvek tervezet |
| `test/tooling/store_package_test.dart` | a §6 cellái |

**Tilos zóna:** `android/**` · `lib/**` · `backend/**` · `docs/privacy/**` · `docs/adr/**` · `.github/**`

## 5. Kötött architekturális döntések

Nincs ADR. Három kötelező szabály:

### 5.1 A data-safety nyilatkozat SZÁRMAZTATOTT

Minden kategóriája a `data-inventory.yaml` egy vagy több mezőjére hivatkozik. **NEM elfogadható gyengítés:** önállóan megfogalmazott kategória-lista, ami „nagyjából" fedi a valóságot.

### 5.2 Minden kért engedélyhez indoklás tartozik

**NEM elfogadható gyengítés:** „a Flutter plugin kéri" típusú indoklás önmagában — meg kell nevezni a FUNKCIÓT és az adatot.

### 5.3 Nincs túlzó képesség-ígéret

A listing csak a GA-scope-ban lévő capabilitykre hivatkozik. **NEM elfogadható gyengítés:** „hamarosan" megfogalmazású funkció-ígéret a store-leírásban.

## 6. Acceptance criteria

| # | Kritérium | Bizonyíték |
|---|---|---|
| A1 | A manifest MINDEN kért engedélyéhez van indoklás | `store_package_test.dart` |
| A2 | A data-safety minden kategóriája leltár-mezőre hivatkozik, és fordítva: nincs leltár-mező nyilatkozat nélkül | `store_package_test.dart` |
| A3 | A listing nem hivatkozik GA-scope-on kívüli capabilityre | `store_package_test.dart` |
| A4 | A fiók-/adattörlés útja a dokumentumban létező route-ra/URL-re mutat | `store_package_test.dart` |
| A5 | A jogi dokumentumok TERVEZET jelöléssel és felülvizsgálati felelőssel készülnek | a dokumentumok fejléce |
| A6 | A Kör 17 `data_inventory_test.dart` VÁLTOZATLANUL zöld | a §7 gate |

### 6.1 Mérce-mátrix — melyik hibás implementációt melyik cella fogja pirosra

| Hibás implementáció | Melyik cella vált PIROSRA |
|---|---|
| Egy manifest-engedély indoklás nélkül marad | A1 |
| A data-safety kategória kézzel íródik, leltár-hivatkozás nélkül | A2 |
| A listing „AI gitártanár"-t ígér, miközben az Offline AI nincs GA-scope-ban | A3 |
| A törlési útvonal nem létező route-ra mutat | A4 |

**Valódi-sértés próba (KÖTELEZŐ, a §10-ben dokumentálva):** vedd ki az egyik engedély indoklását, futtasd a §7 gate-et → az **A1** cellának PIROSNAK kell lennie → állítsd vissza.

## 7. Kötelező ellenőrzések

```bash
tools/round-gate.sh test/tooling/store_package_test.dart test/tooling/data_inventory_test.dart
```

## 8. Implementációs sorrend

1. Az `AndroidManifest.xml` engedélyeinek és a data-inventory mezőinek MÉRÉSE.
2. `docs/store/permissions-rationale.md` és `data-safety.yaml`.
3. `test/tooling/store_package_test.dart`.
4. `docs/store/listing.md` (a GA-scope korlátjával).
5. A két jogi tervezet + a valódi-sértés próba a §10-be.

## 9. Kockázatok

- **Ellentmondás a valósággal.** A store-nyilatkozat és a tényleges adatkezelés eltérése a legnagyobb jogi kockázat (A2).
- **Túlzó ígéret.** A `hold`-on álló Offline AI sáv reklámozása (A3).
- **Emberi lépés összemosása.** A jogi felülvizsgálat és a store-feltöltés a useré — a dokumentum ezt mondja ki (§0.0).

## 10. Implementation handoff — az implementer tölti ki

## 11. Review — a Claude tölti ki
