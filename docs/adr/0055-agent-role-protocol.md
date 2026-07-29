# ADR 0055 — Ágensszerep-protokoll: Claude tervez és review-z, Codex implementál

**Státusz:** elfogadva (explicit user-utasítás, 2026-07-29).
Kiegészíti az [ADR 0050](0050-branch-per-round-pr-workflow.md) PR-workflow-t és
az [ADR 0052](0052-ci-apk-automerge-session-per-round.md) zöld-kapus
auto-merge-öt; folyamat-ADR (0050+ sáv).

## Döntés

A kétágenses fejlesztés alapértelmezett formája mostantól a **váltóbot-modell**:

```
Claude tervez → Codex implementál → Claude review-z → Codex javít → merge (ADR 0052)
```

1. **Codex az implementáló.** Ő ír production kódot és tesztet a jóváhagyott
   kör-briefben engedélyezett fájlokban, ő futtatja a formázást, analyzert és
   a célzott teszteket, ő javítja a review-megállapításokat.
2. **Claude a tervező és a reviewer.** Ő olvassa az SDD-t, írja a kör-briefet
   (scope, engedélyezett fájlok, acceptance criteria, gate-parancsok), ő
   készíti a független review-jelentést, és ő viszi a merge-öt.
3. **Review közben Claude nem ír production kódot.** A review kimenete
   jelentés, nem csendes átírás. Kivétel: aktuális, explicit user-utasítás,
   vagy ha a Codex-oldal nem elérhető — ezt a jelentésben rögzíteni kell.
4. **Engedélyezett fájlok listája commitolt artefaktum**, nem csak promptban
   élő megállapodás (`docs/execution/08-round-brief.md`).
5. **A review-jelentés commitolt artefaktum**, súlyossági osztályozással
   (`docs/execution/09-review-report.md`, `docs/reviews/EXX-RYY-review.md`).
6. **A merge-szabály VÁLTOZATLAN.** Az ADR 0052 zöld-kapus auto-merge-e
   érvényben marad: minden kötelező gate zöld → Claude külön user-jóváhagyás
   nélkül squash-merge-el. A DoD eddig is tartalmazta a „nincs unresolved
   blocking review" pontot — a review-jelentés ezt teszi ellenőrizhetővé, nem
   szigorít rajta.

## Kontextus

Az E01-R01…R09 körökben ugyanaz az ágens tervezte, implementálta és
nyilvánította késznek a saját körét. Ez a self-review csapdája: a „kész"
állítást nem nézte független szem. Az E01-R08 utolsó verifikációs köre
konkrétan meg is fogott egy csendes elvesztett írást a `settings_sync` pull
ágán — de csak azért, mert ott véletlenül szétvált az implementáló és az
ellenőrző oldal. Ezt a szétválást tesszük alapértelmezetté.

A modell egy ChatGPT-vel készített folyamattanulmányból származik; a
felhasználó 2026-07-29-én rendelte el az átvételét azzal a kikötéssel, hogy az
ADR 0052 merge-szabálya nem változik.

## Mit NEM vettünk át a forrástanulmányból

- **Közös `scripts/verify.sh`**, amely sorban futtat format + analyze + teljes
  `flutter test`-et. Ütközik az [ADR 0053](0053-ci-full-test-suite.md)-mal (a
  teljes suite a CI dolga, a boxon ~15 perc) és a mért OOM-viselkedéssel
  (analyze és test nem futhat egy hívásban). A gate-ek külön parancsok
  maradnak, az AGENTS.md §12 szerint.
- **`sandbox_mode = "workspace-write"` + `network_access = false`** a Codex
  konfigban. Ezen a boxon a bwrap AppArmor miatt nem tud user namespace-t
  nyitni (ezért `-s danger-full-access`), a hálózat kikapcsolása pedig megölné
  a `flutter pub get`-et és a `gh`-t. Az izoláció forrása a külön munkapéldány
  (§15), nem a sandbox.
- **Git worktree a külön klón helyett.** Közös `.git` esetén az egyik ágens
  ref-írása/`gc`-je hat a másikra; maradunk a külön klónnál.
- **Kézi, user által végzett merge.** Az ADR 0052 felülírja.

## Következmények

- Az AGENTS.md §13 (git tilalmak) és §15 (ágensszerepek) ennek megfelelően
  átírva — ütközésnél az AGENTS.md a kanonikus.
- A párhuzamos, fájl-diszjunkt kétkörös futás (korábbi §15) nem szűnik meg,
  de **opt-in kivétel** lesz, nem alapértelmezés: csak explicit user-döntésre,
  a korábbi hét feltétel változatlan betartásával.
- A DoR és DoD kiegészült az engedélyezett-fájllista és a review-jelentés
  pontjával.
- Költség: a Claude-oldali terhelés körönként nő (terv + review), a
  körönkénti átfutás a soros lánc miatt hosszabb, cserébe minden diffet lát
  egy független szem.
