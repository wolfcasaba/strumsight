---
id: 115
topic: Definition of Done — kör-zárási checklist (scope, kód, teszt, migráció, erőforrás, security, a11y, doku, git)
tags: [execution, dod, checklist]
status: active
depends_on: []
canonical_target: docs/execution/04-definition-of-done.md
verify: kör csak teljes DoD után Done
source: chatgpt-plan 2026-07-28 (Codex Execution Pack, 58-file manifest)
---

# Definition of Done

## Funkció és scope

- [ ] Minden kijelölt acceptance criterion teljesült.
- [ ] Scope-on kívüli változás nincs a diffben.
- [ ] A következő SDD-kör nem kezdődött el.
- [ ] Feature flag és fallback viselkedés dokumentált.

## Kód és architektúra

- [ ] Kód formázott.
- [ ] Analyzer/linter zöld.
- [ ] Domain és core dependency szabályok teljesülnek.
- [ ] Nincs új, nem engedélyezett cross-feature belső import.
- [ ] Nincs üres catch, rejtett globális state vagy production print.
- [ ] Public contract dokumentált és verziózási hatása ismert.

## Tesztek

- [ ] Új logika unit teszttel védett.
- [ ] Regressziós teszt készült a javított hibára.
- [ ] Érintett widget/integration/property teszt zöld.
- [ ] Teljes kötelező Flutter gate zöld.
- [ ] Backend/ML gate zöld, ha releváns.
- [ ] Valódi device/real-audio gate teljesült vagy explicit release blocker.

## Adat és migráció

- [ ] Schema és serializáció verziózott.
- [ ] Régi adat migrációja tesztelt.
- [ ] Migráció idempotens vagy biztonságosan újraindítható.
- [ ] Sérült adat nem okoz teljes adatvesztést.
- [ ] Rollback/forward-fix stratégia dokumentált.

## Erőforrás és teljesítmény

- [ ] Mic, camera, stream, timer, isolate, wakelock és fájl handle felszabadul.
- [ ] Nincs ismert memória- vagy resource leak.
- [ ] Teljesítmény nem romlott az engedélyezett kereten túl.
- [ ] Thermal és low-memory fallback tesztelt, ha releváns.

## Security és privacy

- [ ] Secret scan tiszta.
- [ ] Token, jelszó, PII, nyers audio/video nincs logban.
- [ ] Authorization szerveroldali.
- [ ] Consent és adatmegőrzési viselkedés tesztelt.
- [ ] Dependency/modell/tartalom licence dokumentált.

## UI és accessibility

- [ ] Minden új szöveg lokalizált.
- [ ] Szín nem az egyetlen jelentéshordozó.
- [ ] Screen reader label és fókuszsorrend megfelelő.
- [ ] Reduced motion és nagy betűméret ellenőrzött.
- [ ] Empty/loading/error/offline állapot megtervezett.

## Dokumentáció

- [ ] SDD/ADR/API dokumentáció frissült.
- [ ] Traceability matrix frissült.
- [ ] HANDOFF frissült.
- [ ] Issue acceptance criteria kipipálva.
- [ ] Ismert technikai adósság külön issue.

## Git és PR

- [ ] Branch és commit elnevezés megfelelő.
- [ ] Diff review-zható méretű.
- [ ] PR leírás tartalmazza a tesztbizonyítékot.
- [ ] CI zöld.
- [ ] Nincs unresolved blocking review.
- [ ] Merge után a main zöld és az artifact azonosítható.

Egy kör nem Done, ha a tesztet nem lehetett futtatni és a hiányzó ellenőrzés release-kritikus.

---
