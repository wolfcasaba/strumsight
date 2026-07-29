# ADR 0052 — CI-s APK-build, zöld-kapus auto-merge, kör = új session

**Státusz:** elfogadva (explicit user-utasítás, 2026-07-29).
Kiegészíti az [ADR 0050](0050-branch-per-round-pr-workflow.md) PR-workflow
szabályait; folyamat-ADR (0050+ sáv).

## Döntés

A user 2026-07-29-én három állandó szabályt rendelt el:

1. **APK-build mindig CI-vel.** `flutter build apk` a fejlesztői boxon nem
   futtatható (nincs Android SDK) és nem is próbálandó — a build-evidencia
   MINDIG a CI-ből jön:

   ```bash
   gh workflow run build-apk.yml --ref <kör-branch>
   ```

   A futás linkje a PR kötelező build-evidenciája. (Amíg a `build-apk.yml`
   nem kap `pull_request` triggert — E01-R14 —, a dispatch kézi.)

2. **Minden zöld → automatikus merge.** Ha a kör MINDEN kötelező gate-je
   zöld (format, analyze, teljes `flutter test`, property gate, a fejezet
   kör-specifikus tesztjei, ÉS a branchre dispatchelt CI-build success), a
   PR-t külön user-jóváhagyás nélkül squash-merge-elni kell. A gate-ek
   bármelyikének hiánya vagy pirossága esetén a merge tilos marad
   (`docs/execution/05` „Tilos merge-elni" listája változatlanul él, a
   frissítetlen HANDOFF/traceability is blokkol).

3. **Új kört mindig új sessionben.** Ami a tervben új sessionre van előírva
   (egy session = egy SDD-kör), azt új sessionben kell indítani — egy session
   a köre lezárása (merge + jelentés) után MEGÁLL, és nem kezdi el a
   következő kört. Kivétel csak aktuális, explicit user-utasításra van
   (dokumentációs elsőbbség #1), ahogy 2026-07-29-én az E01-R03 azonnali
   folytatása volt.

## Kontextus

Az E01-R02/R03 körök alatt mindhárom kérdés élesben merült fel: a box nem
tud APK-t buildelni (a CI-dispatch bizonyult az egyetlen működő
build-evidenciának), a zöld PR-ok merge-e külön kérdezgetést igényelt, és az
egy-session-egy-kör szabály „folytassuk most" utasítással ütközött. A user
mindhármat állandó szabályként rögzítette.

## Következmények

- Az AGENTS.md §4 (scope), §12 (kötelező ellenőrzések) és §13 (git) ennek
  megfelelően kiegészült — ütközésnél az AGENTS.md a kanonikus.
- Az auto-merge a szóló-workflow ADR 0050-es adaptációjával együtt él: az
  ügynöki second-eye review továbbra is a merge ELŐTTI kötelező lépés, ha a
  sessionben futtatható; ha nem (subagent-tiltás), kézi diff-audit + a
  helyettesítés follow-upként rögzítése a PR-ben.
- A merge visszavonása a szokásos revert-PR útvonalon történik.
