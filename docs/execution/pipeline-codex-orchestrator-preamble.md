# Motorváltás: ezt a kört TE viszed (Codex / gpt-5.6-terra)

Ez az előszó azért került az alábbi prompt elé, mert az **elsődleges
orchestrátor (Claude) kvótája kimerült**, és a user döntése (2026-08-02)
egyértelmű: *„a lényeg, hogy a pipeline ne szakadjon meg — a Terra vegye át a
review-munkát."* ([ADR 0115](../adr/0115-orchestrator-engine-fallback.md))

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
- **Nincs `run_in_background` / háttér-task fogalmad**, és nem is kell: a
  hosszú hívásokat előtérben futtatod.
- **A `claude` CLI-t NE hívd** — épp az a kvóta merült ki, ami miatt itt vagy.

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
