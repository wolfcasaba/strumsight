# ADR 0112 — Önjavító kör-pipeline: a HALT nem a lánc vége, hanem egy javító kör bemenete

**Státusz:** elfogadva (GOV-03, 2026-08-01, user-döntés: *„állítsd be, hogy az
orchestrátor mindig javítsa a hibát; a cél, hogy autonóm módon fejlesszünk"*).
Módosítja: [ADR 0087](0087-autonomous-round-pipeline.md) §2 és §7.
Érintett: [ADR 0052](0052-ci-apk-automerge-session-per-round.md) (zöld kapu —
**változatlan**), [ADR 0088](0088-minimax-first-development-router.md) (router).

## Kontextus — a mérés, amiből ez az ADR született

2026-08-01 15:53 UTC-kor a lánc H6-tal megállt az E02-R21-en, és **2 óra 45
percig állt**, miközben a cron ötpercenként pontosan lefutott és ötpercenként
ugyanazt írta a naplóba: *„a lánc MEGÁLLT … feloldás: pipeline-status.sh
--resume"*. A user a telefonján annyit látott, hogy a fejlesztés nem halad.

A blokkoló **nem ítéletet kívánó kérdés volt, hanem egy mérhető hiba**: a router
baseline-őre (`tools/ai_router/security.py`) a Flutter **saját, kötelező**
generált fájljait (`lib/l10n/app_localizations*.dart`, `GeneratedPluginRegistrant.*`,
`ios/Flutter/ephemeral/**`, `android/local.properties`) „unsafe ignored"-nak
minősítette minden friss worktree-ben. Következmény: **egyetlen `engine=auto`
Flutter kör sem tudott átmenni a precheck-en** — sem az E02-R21, sem az Epic 3
mind a 21 sora. Egy háromsoros lista-bővítés volt a javítás, de az ADR 0087
szerint ez „megosztott infrastruktúra", tehát a kör nem nyúlhatott hozzá, és a
lánc kötelezően megállt.

Az ADR 0087 megállási szerződése ezt a viselkedést helyesen írta elő: azt
feltételezte, hogy **minden halt ítéletet kíván**. A mérés cáfolta: a haltok
egy része **javítható hiba**, és rájuk az emberre várás tiszta veszteség.

## Döntés

### 1. A halt az önjavító kör bemenete

Ha a `.pipeline/HALTED` létezik, a `tools/round-pipeline.sh` következő futása
**nem áll meg**: friss, headless **önjavító sessiont** indít
(`docs/execution/pipeline-selfheal-prompt.md`), ugyanazon a lánc-záron belül —
egyszerre továbbra is egy session dolgozik.

Az önjavító kör dolga **nem** a megállt kör levezénylése, hanem a **gyökérok
megszüntetése**: mérés → legkisebb javítás → **kötelező regressziós teszt** →
gate → PR → zöld CI → merge → dokumentálás. Utána a `HALTED` archiválódik, és a
lánc a következő firingen újraindítja a megállt kört.

### 2. Az önjavító kör jogosultsága tágabb, mint egy normál köré

Módosíthatja a `tools/**`-ot, a `.ai/**`-ot, a már **merge-elt ADR-eket**
(jelölt módosítás-blokkal, a történet átírása nélkül), a megállt kör briefjét és
engedélyezett-fájllistáját, valamint a sor-fájl érintett sorát.

**Miért tágabb:** az ADR 0087 §2 határa („a kör saját, még nem merge-elt
artefaktuma") azt védte, hogy egy **futó kör** ne írhassa át más körök alapját
menet közben, csendben. Az önjavító kör nem futó kör: külön session, külön
branch, külön PR, saját zöld kapu és kötelező dokumentálás — a döntése tehát
**látható és auditálható**, nem csendes.

### 3. Az EGYETLEN megmaradt emberi határ: a mércét nem gyengítheti

Tilos tesztet törölni/skippelni, küszöböt lazítani, property-gate-et szűkíteni,
ellenőrzést kikapcsolni a routerben, és tilos a `tools/round-gate.sh` és a
`.github/workflows/` módosítása. Ez nem csak prompt-szöveg, hanem **gépi őr**:
a driver a javítás előtt és után megméri a
`git ls-files test tools/tests | wc -l` értéket és a gate-artefaktumok
blob-hash-ét. Ha a teszt-fájlok száma csökkent, vagy egy gate-artefaktum
megváltozott, a lánc **nem oldódik fel**: `H-GATEGUARD` halttal ember elé kerül.

Forrás: `docs/LESSONS.md` — *„a mércét is ellenőrizd"*, és az M3 mért
hibamódja: a szöveges tiltás nem tart, futtatható artefaktum kell.

### 4. Korlátos kísérletszám, hogy a lánc ne pöröghessen

Körönként és **halt-kódonként** legfeljebb `PIPELINE_SELFHEAL_MAX` (alap: **3**)
önjavító kísérlet. A számláló `.pipeline/selfheal.count`-ban él; sikeres `fixed`
után nullázódik, `retry` (külső, átmeneti akadály) után **megmarad**, hogy egy
tartós szolgáltatás-kiesés ne indítson végtelen láncot. A keret kimerülése után
a lánc áll, és a user dönt.

### 5. Három elfogadott önjavító kimenet

| `outcome` | mikor | a lánc |
|---|---|---|
| `fixed` | a gyökérok javítva, regressziós teszttel, zölden merge-elve | feloldódik (mérce-őr után) |
| `retry` | külső, átmeneti akadály (kvóta, 429, kiesés) — nincs mit javítani | feloldódik, a számláló marad |
| `escalate` | a javítás a mércét gyengítené, vagy valódi normatív döntés kell | áll, ember dönt |

Jelzés nélküli önjavító session = a lánc áll (ugyanaz a szabály, mint a
kör-sessionnél: jelzés nélküli futás = bukott futás).

### Módosítás (ADR 0112 önjavító kör, 2026-08-02) — STOPPED feladat visszaállítása kizárólag zöld heal-gate után

Egy önjavítás merge-elhet olyan upstream perzisztencia- vagy infrastruktúra-
javítást, amely egy már STOPPED állapotú kör meglévő worktree-jének célzott
gate-jét zöldre váltja. Ilyenkor a `recover-stopped-after-heal` operátori
út csak akkor teheti a feladatot `READY_FOR_REVIEW` állapotúvá, ha a friss
worktree-manifest és a teljes allowlist scope-audit zöld, majd ugyanazon a
worktree-n a kör célzott gate-je is zöld.

Ez **nem reset**: a korábbi M3-/Terra-kísérletszámok és Terra-reservation
megmaradnak, új modellhívás nem indul. Csak a korábbi, heal által felülírt
terminális intent törlődik; az eredmény továbbra is független review és a
szokásos CI-kapu előtt áll. Scope- vagy gate-hiba fail-closed `StateError`,
tehát a recovery nem gyengítheti a mércét és nem rejthet el piros eredményt.

### Módosítás (ADR 0112 önjavító kör, 2026-08-03) — H8 brief-history konfliktus non-force integrációja

Mérés: E03-R11/H8-nál a már merge-elt H3 scope-revízió és ugyanennek a körnek
régi pre-flight commitja kizárólag az R11 briefben konfliktált (`git rebase
origin/main` → `CONFLICT (content): docs/rounds/e03-r11-musicxml-mxl-importer.md`).
A `main` változat már tartalmazta a H3 preview-contract allowlistet; a rebase
helyi történetének force-push-a viszont tiltott volna.

Ha az unmerged-path lista pontosan a megállt kör briefje, és az `origin/main`
oldal bizonyíthatóan tartalmazza a merge-elt self-heal scope-revíziót, a H8
önjavítás a rebase-et megszakítja, majd `git merge --no-ff origin/main`-nel
integrálja a friss baseline-t. A brief feloldása az aktuális `main` szövegét
őrzi meg, a branch pedig normál push-sal publikálható. Bármely további
konfliktus vagy nem egyértelmű scope esetén fail-closed `escalate` marad.

Ez nem enyhíti az ADR 0086 freshness-követelményét: a körbranch a merge után is
tartalmazza a dispatch előtti `main`-t, és később ugyanúgy exact-head CI-t,
független review-t és zöld kaput igényel.

### Módosítás (ADR 0112 önjavító kör, 2026-08-03) — H8 merge utáni gépi freshness-bizonyítás

E03-R12/H8 mérése megmutatta, hogy a non-force merge sikeres kimenete önmagában
nem elég jól auditálható bizonyíték arra, hogy a célbranch valóban tartalmazza
az éppen vizsgált `origin/main`-t. A brief-only rebase-konfliktus megszakítása
és `git merge --no-ff origin/main` után a self-healnek kötelezően futtatnia
kell a `git merge-base --is-ancestor origin/main HEAD` parancsot; csak a 0-s
kilépési kód után pusholhat normál módon. Ez nem lazít scope-ot, gate-et vagy
CI-követelményt, kizárólag a meglévő ADR 0086 freshness-szabály mérhető
bizonyítékát teszi kötelezővé.

### Módosítás (ADR 0112 önjavító kör, 2026-08-03) — H6 approved-brief metadata recovery

Mérés: E03-R11 H3 scope-revíziója a merge után megváltoztatta a brief
kanonikus `brief_hash`-ét. A `rebase-baseline` a friss manifestet és a
megőrzött diffet már az új, teljes allowlist ellenőrzésével auditálta, de a
régi hash-et meghagyta. A következő `resume` ezért az audit előtt
`BLOCKED: committed brief metadata changed` állapotba tért vissza.

A `rebase-baseline` kizárólag sikeres, aktuális-brief szerinti scope-audit
után a perzisztált `brief_hash`-t is az éppen auditált brief hashére állítja.
Nem reseteli a kísérletszámokat vagy a Terra reservationt, és nem kerüli meg
az allowlist- vagy baseline-őrt; scope-hiba továbbra is fail-closed.

### Módosítás (ADR 0112 önjavító kör, 2026-08-03) — H6 recovery a merge-elt infrastruktúra-drift után

Mérés: E03-R12 review-javító `resume`-ja a perzisztált `ac31e3f` baseline-ról
futott, miközben a körbranch a H3/H4/H8 self-heal merge-ek után `f1612af`-en
állt. A `audit_scope` ezért a merge-elt `.ai/router.toml`, pipeline- és router
utakat modellváltozásként jelölte (`HEAD changed from baseline`), és a valódi,
engedélyezett MIDI javító diffet sem tudta újra auditálni.

Ilyen mért állapotban az önjavító eljárás előbb a megállt kör worktree-jén
kötelezően a `model-router.py rebase-baseline --task <round> --worktree
<round-worktree>` operátori utat használja. Ez a jelenlegi commitolt HEAD-et
teszi baseline-ná, de a megőrzött uncommittolt termékdiffet teljes allowlist és
protected-path audit alatt tartja. Csak `READY_FOR_REVIEW` és megőrzött
attempt/ledger után futtatható újra a review-findings `resume`; kézi state
szerkesztés vagy reset nem megengedett. A scope-hibás recovery változatlanul
fail-closed.

### 6. Az ADR 0087 §7 „epic-zárás = halt" szabálya feloldódik

A `prepared`/kézi indítás továbbra is a sor dolga, de ha egy epic-záró kör
haltba fut, arra is az önjavító lánc vonatkozik. A user 2026-08-01-i döntése
(teljes Epic 3 folyamatos futtatása, az R22-vel együtt) ezt már előrevetítette.

### 7. Kikapcsolható

`PIPELINE_SELFHEAL=0` → a régi, ADR 0087 szerinti viselkedés (halt = a lánc áll
emberi `--resume`-ig). A visszaút egy környezeti változó, nem kód-visszavonás.

## Következmények

- A lánc a hibák **javítható** osztályán nem áll meg többé: az E02-R21-hez
  hasonló infrastruktúra-hiba a következő cron-firingen (≤5 perc) javító kört
  indít, ahelyett hogy órákig várna emberre.
- Az autonómia ára a **kötelező regressziós teszt**: minden önjavítás nyomot
  hagy a mércében, így ugyanaz a halt nem térhet vissza csendben.
- Az emberi felügyelet nem szűnik meg, hanem **egy pontra koncentrálódik**: ha
  a rendszer a saját mércéjét akarná módosítani, az ember elé kerül.
- A `.pipeline/heal-*.log`, `heal-status` és `healed-*.txt` a futásidejű
  bizonyíték; a tartós tanulság a `docs/LESSONS.md`-be megy.
