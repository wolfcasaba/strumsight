# E07-R19 — security review

**Dátum:** 2026-08-18
**Reviewer:** független security-reviewer, izolált klón
**Implementer:** MiniMax
**Verdikt:** CHANGES REQUESTED

## Mérések

- Scope-audit: az eredeti `04749442..0d505ca7` implementációs tartomány
  zöld (7 engedélyezett útvonal); a `3bff8967..45395d9f` javítási tartomány
  zöld (3 engedélyezett útvonal).
- A módosított implementációban nem talált network-, raw-audio-, secret- vagy
  production-logging utat.
- Az izolált klón saját gate-je a generált Flutter/l10n előfeltételek hiánya
  miatt analyze-nál 997 környezeti hibával megállt; a fő review-klón ugyanazon
  branchen a kötelező gate-et zölden lefuttatta.

## Leletek

### S-01 — MAJOR — a nem-objektum JSON sérülés hiányzó rekordnak látszik

- **Fájl:** `lib/features/practice_generator/data/local/local_practice_plan_repository.dart:308-314,355-361`
- **Bizonyíték:** egy jelen lévő, érvényes JSON, de nem `Map<String, dynamic>`
  érték (`[]`, `null`, `42`) `Success(null)`-t ad vissza, így kihagyja a
  serializer kontrollált korrupciós hibáját.
- **Hatás:** a perzisztált sérülés összetéveszthető egy hiányzó aktív tervvel
  vagy drafttal.
- **Kötelező javítás:** csak a hiányzó storage-kulcs maradhat `Success(null)`;
  minden jelen lévő, nem objektum envelope `StorageFailure` legyen. Adj
  aktív- és draft-regressziós tesztet.
- **Státusz:** OPEN.

### S-02 — MAJOR — egy szemantikailag sérült archív rekord az egész archívot elviheti

- **Fájl:** `lib/features/practice_generator/data/local/local_practice_plan_repository.dart:524-537,572-580`
- **Bizonyíték:** a per-record catch csak serializer/migrator kivételt kezel,
  miközben a domain dekóder `ArgumentError` vagy `FormatException`-t dobhat
  például dátum- vagy blokkalak-hibánál.
- **Hatás:** egy checksum szempontjából érvényes, de szemantikailag sérült
  archív body megszakíthatja a teljes archív olvasását, és elrejti az ép
  rekordokat; ez sérti az A2 rekord-szintű containmentet.
- **Kötelező javítás:** indexed archív rekord dekódolásakor minden dekódolási
  kivétel legyen az adott rekord eldobása; az index-szintű sérülés maradjon
  kontrollált plan-szintű hiba. Adj re-stamped checksumos sérült body + ép
  sibling regressziós cellát.
- **Státusz:** OPEN.

## Merge-döntés

S-01 és S-02 nyitott MAJOR, ezért merge tilos a javítás, független re-review
és exact-SHA CI utánig.
