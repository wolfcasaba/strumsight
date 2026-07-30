# E01-R16 review — offline network guard + CI gate-sor dedup

Reviewer: Claude · Dátum: 2026-07-30 · Diff: `6b6d7a1..60624c2` (3 commit)
Brief: [`docs/rounds/e01-r16-final-regression-and-docs.md`](../rounds/e01-r16-final-regression-and-docs.md)
Verdikt: **APPROVED** — 0 BLOCKER · 0 MAJOR · 0 MINOR · 4 NOTE

## Scope-audit

A diff pontosan a brief §4 engedélyezett fájljait érinti:
`test/app/offline_network_guard_test.dart` (új),
`.github/actions/flutter-gates/action.yml` (új), `build-apk.yml`,
`release-apk.yml`, és a brief §10 szekciója. `test/support/` nem változott
(nem volt rá szükség — a meglévő fake-ek elegek voltak). Production kód
(`lib/`) diff: **üres**. Tilos zóna sértetlen.

## Függetlenül újramért ellenőrzések (Claude, 2026-07-30)

| Ellenőrzés | Eredmény |
|---|---|
| `dart format --set-exit-if-changed lib test tool` | 450 fájl, **0 changed** |
| `flutter analyze lib/ test/ tool/` | **No issues found** |
| `flutter test test/app` (külön hívás) | **41 passed** (39 baseline + 2 új guard) |
| `dart run tool/check_architecture.dart` | OK, 12 allowlisted deviation |
| backend: `ruff check` + `ruff format --check` | tiszta, 20 fájl |
| backend: `pytest -q` (sima + `STRUMSIGHT_ALLOW_SQLITE=true`) | **64 passed** mindkét futásban |
| `backend-ci.yml` a kör-branchen | **zöld** — [run 30521933758](https://github.com/wolfcasaba/strumsight/actions/runs/30521933758) |
| `release-apk.yml` secret nélküli fail-closed próba a refaktor UTÁN | **bizonyított** — [run 30521935406](https://github.com/wolfcasaba/strumsight/actions/runs/30521935406): `signing-prerequisites` failure → `release-apk` és `Coverage` egyaránt **skipped**, **0 artifact** |
| `build-apk.yml` a kör-branchen (teljes suite + property + coverage-job + APK) | dispatch elindítva — a run-link a merge-nél/completion reportban rögzítve |

## Az offline network guard teszt (§3.1) értékelése

A teszt a brief §5.1 döntését pontosan követi: a mérés a **DioFactory-seamen**
történik, nem HTTP-mockon. Erősségei:

- **Valódi bootstrap:** `AppBootstrap.run` production környezet-névvel,
  fail-closed configgal — nem egy kézzel összerakott config-objektum.
- **Kettős számláló:** a factory/kliens **létrehozása** és az adapterig jutó
  **request** külön assertálva (`[creations, requests] == [0, 0]`) — a
  „nem is jött létre kliens" az erősebb állítás, a request-lista a védőháló.
- **Diagnostics-oldal a valódi production úton:** `diagnosticsApiClientProvider
  == null` + null kliensű uploader — nem override, hanem a tényleges
  disabled-ág bizonyítéka.
- **A két eset jól megválasztott:** disabled-nél `tokenStore.reads == 0`,
  account-enabled + kijelentkezettnél `reads == 1` — utóbbi bizonyítja, hogy
  az auth-út tényleg lefutott (konzultálta a storage-ot), és MÉGSEM ment hálózatra.
- **Érzékenység-próba dokumentálva valódi piros kimenettel** (§10): az
  ideiglenesen beinjektált POST `[1, 1]`-re vitte az assertet, majd vissza lett
  vonva. A próba első, fake-async zónában elakadt változatát a Codex nem
  fogadta el evidenciának, hanem `tester.runAsync` alá vitte — helyes
  módszertani döntés.
- Nyolc fő képernyő épül fel route-onként `takeException()`-ellenőrzéssel —
  aszinkron hiba sem csúszhat át némán.

## A CI gate-sor dedup (§3.2) értékelése

- A composite action a gate-sort **változatlan sorrendben és szigorral**
  tartalmazza (format → analyze → architecture → asset → test → property,
  friss property-seed, minden `run` lépés `shell: bash`, nincs
  continue-on-error). A két workflow ugyanarra az actionre mutat — a
  drift-kockázat (R14-review MINOR-2) megszűnt.
- A coverage külön, párhuzamos jobba került (R14-review MINOR-3): a kritikus
  út (gate-sor → APK) többé nem várja a `--coverage` futást; a workflow
  konklúziója viszont csak akkor zöld, ha a Coverage job is az — a merge-gate
  (ADR 0052: a run zöldje) változatlan erősségű.

## NOTE-ok

1. **NOTE — brief fölötti, helyes Codex-döntés:** a `release-apk.yml`-ben új
   `signing-prerequisites` job gate-eli (`needs:`) a release ÉS a coverage
   jobot. Enélkül a párhuzamos Coverage job secret nélküli futáson is LCOV
   artifactot töltött volna fel — az R14-ben bizonyított „0 artifact"
   fail-closed tulajdonság sérült volna. A meglévő inline secret-guard a
   release jobban érintetlenül megmaradt (kettős védelem, a brief „ne nyúlj
   hozzá" utasítása szerint). A refaktor utáni fail-closed viselkedés friss
   futással bizonyított (lásd a táblázatot).
2. **NOTE — compute-többlet:** a Coverage job a teljes suite-ot másodszor
   futtatja (`--coverage`-dzsel). Wall-clock nyereség a kritikus úton a cél;
   a runner-percek nőnek. Elfogadott trade-off, a brief ezt írta elő.
3. **NOTE — ADR 0064 fájl nincs a mainen:** a Codex §10 lelete szerint a
   dokumentum a `chore/codex-code-complete-signal` branchen (`1959bc6`) ül,
   a HANDOFF viszont hivatkozza. Az ADR 0058 fájl szintén hiányzik (R10-B).
   Mindkettő a Claude-oldali záródokumentációban pótolandó — a Codex a §4
   whitelist miatt helyesen nem nyúlt hozzá.
4. **NOTE — protokoll-eltérés (Claude-oldali, átláthatóságból rögzítve):** a
   Codex ezúttal a fő worktree-ben futott, nem külön munkapéldányban
   (AGENTS.md §15.3). Kompenzáció: Claude a futás alatt nem módosított
   repo-fájlt, és a scope-audit + a 18 érintetlen untracked fájl igazolja,
   hogy keveredés nem történt. Következő körre: vissza a külön munkapéldányhoz.

## Verdikt

**APPROVED.** Javítókör nem szükséges. A kör fennmaradó része Claude-oldali
(dokumentáció, teljes CI-evidencia) + user-oldali (§16.3/§16.4 készülékes menet).
