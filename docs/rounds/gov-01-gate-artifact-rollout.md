# GOV-01 — A gate-artefaktum és a szigorított brief-szabályok átvezetése

- **Státusz:** READY (kiadható, 2026-07-30)
- **Típus:** governance-kör (nem SDD-fejezet) — a fejlesztési folyamat saját karbantartása
- **Előfeltétel:** `tools/round-gate.sh` és a `docs/execution/08-round-brief.md`
  szigorítása **már létezik** (E02-R07 utáni hiánypótló PR)
- **Branch:** `mm/gov-01-gate-artifact-rollout`
- **Javasolt implementer motor:** **MiniMax M3** — sok fájlt érintő, tételesen
  kipinnelt, mechanikus szövegátvezetés, tervezői döntés nélkül
  ([ADR 0069](../adr/0069-two-engine-implementer-pool.md) §15.6 „volumen" sor)
- **ADR:** nem kell — ez a meglévő ADR 0052/0053/0055 gyakorlatának átvezetése,
  nem új döntés. **Az implementer NEM hoz létre `docs/adr/` fájlt.**

## 0. Kör-jelzés — KÖTELEZŐ (AGENTS.md §15.2)

```bash
tools/codex-signal.sh progress "<egy sor>"
tools/codex-signal.sh done    "<egy sor>"
tools/codex-signal.sh stopped "<egy sor>"
tools/codex-signal.sh blocked "<egy sor>"
```

Lezáró jelzés nélküli kör = bukott kör. `gh`-t NE hívj, ne pusholj.
**STOP-klauzula:** listán kívüli fájl vagy ütköző előírás → `stopped` + jelentés.
**A §7 a terved** — külön task-lista ne készüljön.

## 1. Cél

Az E02-R07 mérte, hogy a **prompt-szövegben megfogalmazott mérce nem tart**: az
implementer motor háromszor futtatta a záró gate-et `| tail -N`-nel, pedig a
brief és a javító prompt is szó szerint tiltotta
([`docs/reviews/e02-r07-review.md`](../reviews/e02-r07-review.md),
[`docs/LESSONS.md`](../LESSONS.md) L09–L11).

A `tools/round-gate.sh` és a szigorított brief-sablon már létrejött. **Ez a kör
azt vezeti át**, hogy a rendszer minden pontja ugyanazt mondja: a gate egyetlen
futtatható artefaktum, és a brief-sablon három új kötelező eleme (nem elfogadható
gyengítés · a méréshez szükséges eszköz · paraméter-mátrix) mindenhol megjelenik.

**Ez a kör kizárólag dokumentációt és prompt-sablont módosít — production Dart
kódot NEM.**

## 2. Jelenlegi állapot (mért tények)

- **`tools/round-gate.sh`** — létezik, futtatható, mindkét irányban kipróbálva:
  zöld úton összegző táblát és „MINDEN GATE ZÖLD" sort ír; piros úton az első
  bukott lépésnél megáll, `exit=1`, és NINCS zöld-jelentés. Használat:
  `tools/round-gate.sh <teszt-útvonal> [további teszt-útvonal ...]`.
  A lépések: `format` → `analyze` → `test <mindegyik útvonal külön>` →
  `architecture`, mind külön processzként (L05, OOM).
- **`docs/execution/08-round-brief.md`** — a §4, §6, §7 és §10 már tartalmazza
  az új szabályokat. **Ez a forrás; a többi helyre EZT kell átvezetni.**
- Ami MÉG a régi, kézzel felsorolt parancslistát tartalmazza:
  - `AGENTS.md` §12 (gate-parancsok)
  - `CLAUDE.md` „Verify gate (before 'done')" szakasz
  - `.claude/skills/sdd-round-driver/SKILL.md`
  - `.claude/skills/round-brief-prep/SKILL.md`
  - `.claude/skills/sdd-round-review/SKILL.md`
  - `docs/execution/04-definition-of-done.md` (ha felsorolja a gate-et — ELLENŐRIZD)
  - `tools/mm-round.sh` és `tools/codex-round.sh` fejléc-kommentjei (ha hivatkoznak a gate-re)

## 3. Scope

**Benne:** a fenti helyeken a kézzel felsorolt gate-parancsok cseréje a
`tools/round-gate.sh` hívására, a „miért artefaktum" indoklás egy mondatban, és
a brief-sablon három új acceptance-szabályának megemlítése a
`round-brief-prep` skillben.

**Kívül (TILOS):**

- Bármilyen `lib/**` vagy `test/**` módosítás.
- A `tools/round-gate.sh` **viselkedésének** megváltoztatása (a script kész;
  legfeljebb elgépelés javítható, és azt a jelentésben rögzítsd).
- Új ADR, új skill, új workflow.
- A CI-workflow (`.github/**`) módosítása — a CI továbbra is a saját lépéseit futtatja.
- `docs/sdd/**`, `docs/adr/**`, `HANDOFF.md`.

## 4. Engedélyezett fájlok

| Útvonal | Miért |
|---|---|
| `AGENTS.md` | §12 gate-szakasz |
| `CLAUDE.md` | „Verify gate" szakasz |
| `.claude/skills/sdd-round-driver/SKILL.md` | a kör-levezénylés gate-hivatkozása |
| `.claude/skills/round-brief-prep/SKILL.md` | a brief-írás gate- és acceptance-szabályai |
| `.claude/skills/sdd-round-review/SKILL.md` | a review gate-újrafuttatása |
| `docs/execution/04-definition-of-done.md` | ha felsorolja a gate-parancsokat |
| `tools/mm-round.sh`, `tools/codex-round.sh` | KIZÁRÓLAG fejléc-komment, kódot NE |
| `docs/rounds/gov-01-gate-artifact-rollout.md` | CSAK a §8 (handoff) kitöltése |

**Tilos zóna:** `lib/**`, `test/**`, `docs/sdd/**`, `docs/adr/**`, `HANDOFF.md`,
`.github/**`, `pubspec.yaml`, `tools/round-gate.sh` (viselkedés).

**ÚJ fájl létrehozása is scope-sértés** — ha új fájl kellene, `stopped` jelzés.

## 5. Kötött döntések

1. **A gate hívása mindenhol pontosan ez a forma:**
   `tools/round-gate.sh <teszt-útvonal> [további teszt-útvonal ...]`.
   A régi négy-öt soros parancslista **helyére** kerül, nem mellé.
2. **A „miért" egy mondatban mindenhol ott legyen:** a csővezeték elrejti a
   kilépési kódot, ezért a mérce futtatható artefaktum, nem prompt-szöveg
   (hivatkozás: `docs/LESSONS.md` L09).
3. **Az `AGENTS.md` §12 marad a normatív forrás** — a `CLAUDE.md` és a skillek
   rá hivatkoznak, nem duplikálják a részleteket.
4. **A CI-dispatch változatlanul orchestrátor-jog:** minden érintett helyen
   maradjon ott, hogy az implementer `gh`-t nem hív.
5. **A `docs/execution/08-round-brief.md`-et NE írd át** — az a forrás, amiből
   dolgozol.

## 6. Acceptance criteria

- [ ] `grep -rn "flutter analyze lib/ test/" AGENTS.md CLAUDE.md .claude/skills/ docs/execution/`
      → a találatok kizárólag magyarázó/történeti kontextusban maradnak, gate-előírásként nem.
- [ ] `grep -rn "round-gate.sh" AGENTS.md CLAUDE.md .claude/skills/ docs/execution/`
      → **mind a hét** §4-ben felsorolt hely (ahol értelmezhető) hivatkozik rá.
- [ ] Egyik módosított fájlban sincs `| tail`, `| head` vagy `&&` láncolás a
      gate-előírás közelében.
- [ ] A `round-brief-prep` skill kötelező brief-elemei között megjelenik mind a
      három új acceptance-szabály (nem elfogadható gyengítés · a méréshez
      szükséges eszköz · paraméter-mátrix).
- [ ] `git diff --stat` → `lib/` és `test/` **0 sor**.
- [ ] `tools/round-gate.sh` diffje **üres** (vagy csak elgépelés-javítás, a §8-ban indokolva).

## 7. Implementációs sorrend (ez a TERVED)

1. Olvasd el a forrást: `docs/execution/08-round-brief.md` §4, §6, §7, §10.
2. `AGENTS.md` §12 — a parancslista cseréje, a „miért" mondattal.
3. `CLAUDE.md` verify-gate szakasz — rövid hivatkozás az `AGENTS.md` §12-re
   (a box mért igazságai — OOM, win32, Riverpod — MARADNAK).
4. A három skill sorban.
5. `docs/execution/04-definition-of-done.md` — csak ha ténylegesen felsorolja.
6. A két round-wrapper fejléc-kommentje.
7. Ellenőrzés: a §6 két `grep`-je, majd `git diff --stat`.

## 8. Implementation handoff — az IMPLEMENTER tölti ki

*(Fájlonkénti összefoglaló · a futtatott `grep`-ek TÉNYLEGES kimenete ·
eltérések és okuk · nem futtatott ellenőrzések és okuk · follow-upok.)*

## 9. Review — Claude tölti ki

Link: `docs/reviews/gov-01-review.md`

**Megjegyzés a gate-ről:** ez a kör Dart kódot nem érint, ezért a
`tools/round-gate.sh` futtatása **nem** követelmény — a §6 grep-jei és a
`git diff --stat` a mérce. A CI-dispatch a merge előtt ettől függetlenül kötelező
(a `main`-re menő doksi-változás is végigfut a build-apk gate-en).
