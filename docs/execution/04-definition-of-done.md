# Definition of Done

## Funkció és scope

- [ ] Minden kijelölt acceptance criterion teljesült.
- [ ] Scope-on kívüli változás nincs a diffben — a `git diff --stat` a
      kör-brief engedélyezett-fájllistája ellen ellenőrizve.
- [ ] A következő SDD-kör nem kezdődött el.
- [ ] Feature flag és fallback viselkedés dokumentált.
- [ ] A brief „Implementation handoff" szekciója kitöltve.

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
- [ ] Érintett widget/integration/property teszt zöld (lokálisan).
- [ ] Teljes kötelező Flutter gate zöld — a lokális mérce a
      `tools/round-gate.sh <érintett terület> [további …]` artefaktum
      (normatív forrás: [`AGENTS.md` §12](../../AGENTS.md), részletek
      `docs/execution/08-round-brief.md` §7), a **teljes suite + property gate a CI-ban**
      ([ADR 0053](../adr/0053-ci-full-test-suite.md)), a bizonyíték a run linkje.
- [ ] Backend/ML gate zöld, ha releváns.
- [ ] Valódi device/real-audio gate teljesült vagy explicit release blocker.

## MiniMax-first router (`engine=auto`)

- [ ] A brief pontosan egy valid `ai-router` blokkot tartalmaz; scope-ja és
      `gate_tests` listája egyezik a brief normatív §4/§7 tartalmával.
- [ ] A hiteles külső state ugyanahhoz a task ID-hez tartozik; budgetet nem
      nulláztunk state-törléssel, új ID-val vagy új worktree-vel.
- [ ] A végső router-result `READY_FOR_REVIEW`; `DEFERRED`, `BLOCKED`,
      `STOPPED` vagy `INTERNAL_ERROR` nem minősül kész implementációnak.
- [ ] A teljes tracked/untracked/ignored/deleted/symlink scope-audit zöld.
- [ ] A strukturált router-gate zöld; natív módosításnál a natív gate is zöld.
- [ ] Provider quota/429/5xx/hálózati hiba nem indított Terra fallbacket.
- [ ] Az M3/Terra nem commitolt, pusholt vagy jelzett közvetlenül; a router-diffet
      az orchestrátor auditálta és commitolta `READY_FOR_REVIEW` után.
- [ ] A `READY_FOR_REVIEW` jelzés csak `progress`; `done` kizárólag független
      review + exact-`headSha` CI + merge után született.

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
- [ ] Nincs unresolved blocking review — a független review-jelentés
      (`docs/reviews/eXX-rYY-review.md`, sablon: [09-review-report](09-review-report.md))
      commitolva, és nincs benne OPEN státuszú BLOCKER vagy MAJOR.
- [ ] Merge után a main zöld és az artifact azonosítható.

Egy kör nem Done, ha a tesztet nem lehetett futtatni és a hiányzó ellenőrzés release-kritikus.

---
