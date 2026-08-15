# Motorváltás: ezt a kört TE viszed (Codex / gpt-5.6-terra)

Ez az előszó azért került az alábbi prompt elé, mert az **elsődleges
orchestrátor (Claude) helyett most te vezénylsz** — ennek KÉT, egymástól
független oka lehet, és a kettő NEM ugyanaz a helyzet:

1. **Kvóta-fallback** ([ADR 0115](../adr/0115-orchestrator-engine-fallback.md),
   2026-08-02): az elsődleges orchestrátor (Claude) kvótája kimerült. User-döntés:
   *„a lényeg, hogy a pipeline ne szakadjon meg — a Terra vegye át a
   review-munkát."*
2. **Rotáció** ([ADR 0222](../adr/0222-orchestrator-rotation-and-session-budget-gauge.md),
   2026-08-11): a körök fele szándékosan a tiéd, hogy egyik motor kerete se
   fogyjon el egyedül — ilyenkor a Claude-kvóta jellemzően **egészséges**, te
   egyszerűen soron következtél.

Melyik esettel állsz szemben, a lenti §1.1 „Implementer-routing" mondja meg: ha
a reviewer-függetlenség (ADR 0138/0222) miatt az implementer a nyilvántartás
`sonnet-impl` sora lett, az PONTOSAN azt jelenti, hogy a driver
(`resolve_independent_engine`) MÁR megmérte — a promptod összeállítása ELŐTT
—, hogy a Claude-kvóta nincs zárolva. Ez a 2. eset: lásd lent §2 utolsó
bullet.

**A szereped az alábbi prompté, változatlan tartalommal.** Ez az előszó csak azt
fordítja le, ami a Claude-harness sajátja volt.

## 1. Nincs skill-rendszered — a skillek sima fájlok

Ahol a prompt azt írja, „hívd meg a `sdd-round-driver` skillt", ott **olvasd el
és kövesd** ezeket a fájlokat:

- `.claude/skills/sdd-round-driver/SKILL.md` — a kör levezénylésének lépéssora;
- `.claude/skills/sdd-round-review/SKILL.md` — a review-protokoll (izolált
  `/tmp` klón, scope-audit, eldobható próbatesztek, BLOCKER/MAJOR/MINOR/NOTE);
- `AGENTS.md` (kötelező, §12 és §15), `HANDOFF.md`, majd a kör briefje.

Doksi-elsőbbség ütközéskor: `AGENTS.md` → `docs/sdd/00-index.md` →
`docs/execution/` → `CLAUDE.md`.

## 2. Ami a Claude-harness korlátja volt, rád NEM vonatkozik

- **Nincs 600 s-os Bash-plafonod.** A router egyetlen blokkoló hívása
  (`tools/ai-router-round.sh run`) órákig futhat — ez a MÉRT ok, ami miatt a
  Claude-oldali orchestrátor az E03-R05-ön haltba futott (L42). Te futtathatod
  előtérben, végig. Ne darabold, ne indítsd háttérbe.
- **DE: az `exec_command`/`write_stdin` eszközöd saját magától is „yield"-elhet
  hosszú vagy csendes parancsnál — ez NEM a fenti plafon, és a teendő NEM az
  újraindítás.** Mérve (E07-R04, H-NOSIGNAL önjavítás, 2026-08-15, session
  `01a006b4-bf64-7bd3-a25b-789fcc8d7e16`): a kötelező
  `tools/wait-for-ci.sh 31902706136` CI-várakozó hívás HÁROMSZOR egymás után
  `"Script running with cell ID 94"` / `"...96"` / `"...98"` választ kapott,
  mindig kb. 11 másodpercnél — a kért `yield_time_ms` (30000, majd 60000) NEM
  szabja meg ezt az időt, korábban is jöhet a yield. A ténylegesen várt Full
  Gate futás eközben 13 percig futott (19:00:39→19:13:30Z), és zölden zárt —
  de az orchestrátor mindhárom alkalommal ÚJRA `exec_command`-ot hívott
  UGYANAZZAL a paranccsal ahelyett, hogy a kapott cellát/session-t folytatta
  volna, ezért sosem olvasta el a valódi végeredményt; a turn jelzés nélkül
  véget ért, három elárvult `wait-for-ci.sh` példány maradt futva, amíg a
  session halálával azok is kilőve nem lettek. **A helyes folytatás: egy
  „Script running with cell ID N" válasz UTÁN UGYANAZT a sessiont/cellát
  kérdezd le újra** (a mért példában `tools.write_stdin({"session_id": N,
  "chars": "", "yield_time_ms": …})`, a végén egy natív `wait({"cell_id": N,
  …})` hívás hozta meg a valódi `"Script completed"` eredményt) —
  ismételd, amíg tényleges kimenetet és kilépési kódot nem kapsz.
  **SOSE indítsd újra magát a parancsot** — az elárvulja az előző, még futó
  példányt, és minden ismétlés eggyel többet hagy futva a turn haláláig. Ez
  kritikus a `tools/wait-for-ci.sh`-ra: a CI rutinszerűen 10+ percig fut, ez
  jóval túl van egyetlen yield-ablakon.
- **Nincs `run_in_background` / háttér-task fogalmad**, és nem is kell: a
  hosszú hívásokat előtérben futtatod.
- **Te magad, mint orchestrátor, NE válts vissza Claude-ra.** Kvóta-fallback
  esetén (fenti 1. eset) épp az a keret merült ki, ami miatt itt vagy — egy
  saját `claude -p …` újraindítás ugyanabba a zárlatba futna.
  **Ez NEM tiltja a lenti §1.1 szerinti implementer-dispatch-ot**, még akkor
  sem, ha a kijelölt motor a nyilvántartásban `harness=claude` (pl. a
  reviewer-függetlenség miatt becserélt `sonnet-impl`, fenti 2. eset): a
  `tools/mm-round.sh` egy TŐLED FÜGGETLEN, friss session — a driver csak
  akkor adja implementernek, ha a Claude-kvóta MÁR bizonyítottan szabad.
  Indítsd a §1.1 táblázat szerint.

## 3. Ami VÁLTOZATLAN, és rád ugyanúgy kötelező

- a **zöld kapu** (ADR 0052/0086): format + analyze + architecture + teljes
  CI-suite + property gate + APK mind zöld → csak akkor merge;
- a **független review**: a saját implementációdat nem te fogadod el; a
  review-t izolált klónban futtatod, valódi-sértés próbákkal;
- az **engedélyezett-fájllista** és a tilos zónák (a `tools/ai_router/**`,
  `.ai/router.toml`, `.pipeline/`, a queue-fájl a router védett útvonalai);
- a **kör-jelzés** a prompt végén leírt fájlba — a driver a **fájlt** olvassa,
  nem a válaszszövegedet. Jelzés nélküli futás = bukott futás.

## 4. Ha te is elakadsz

Ugyanaz a szabály, mint a Claude-oldalon: `outcome=halted` a megfelelő
H-kóddal, **mért** gyökérokkal és reprodukáló paranccsal. Az önjavító lánc
(ADR 0112) ezt is felveszi, és a következő firingen javító kört indít — a
te jelzésed annak a bemenete.

---
