<!-- PR-cím formátum: [EXX-RYY] <imperative summary> — pl. [E01-R02] Align package and platform identifiers -->

## SDD requirement / kör

<!-- pl. E01-R02 — docs/sdd/02-epic-01-core-platform.md, Kör 2. Kapcsolódó issue: #NN vagy — -->

## Cél és nem-cél

- **Cél:**
- **Nem cél (scope-on kívül):**

## Fő változások

-

## Migration / API hatás

<!-- storage schema, adatmigráció, OpenAPI/breaking change, rename-hatás — vagy "nincs" -->

## Tesztek (pontos parancsok + TÉNYLEGES eredmény — külön parancsonként, soha `&&`)

- `flutter analyze lib/ test/` →
- `flutter test` →
- `flutter test test/property` →
- backend `pytest` (ha érintett) →
- nem futtatott ellenőrzés + indoklás:

## Evidence

- UI-változásnál screenshot / device-evidence:
- Audio/DSP/ML/vision-változásnál mérési evidence (fixture/parity/real-audio):

## Privacy / security hatás

<!-- secret, PII, nyers audio, permission, log-tartalom — vagy "nincs" -->

## Rollback

<!-- hogyan állítható vissza (revert-elhető-e az egy squash-commit; migrációnál külön terv) -->

## Follow-up

<!-- scope-on kívül talált hibák → külön issue -->

---

- [ ] HANDOFF.md frissítve (kör-sor + NEXT)
- [ ] Traceability (RTM / INDEX status) frissítve
- [ ] Nincs secret / nagy bináris / generált build a diffben
